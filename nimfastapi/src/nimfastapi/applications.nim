import asyncdispatch, asynchttpserver, strutils, sequtils, tables, json, macros, times
import routing, requests, responses, openapi, dependencies, background, exceptions, encoders, params

type
  MiddlewareHandler* = proc (req: requests.Request, next: proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.}): Future[responses.Response] {.async, gcsafe.}

  ExceptionHandler* = proc (req: requests.Request, exc: ref Exception): Future[responses.Response] {.async, gcsafe.}

  FastAPI* = ref object
    router*: APIRouter
    title*: string
    version*: string
    openapi_url*: string
    docs_url*: string
    middlewares*: seq[MiddlewareHandler]
    exception_handlers*: Table[string, ExceptionHandler]

proc newFastAPI*(title: string = "FastAPI", version: string = "0.1.0", openapi_url: string = "/openapi.json", docs_url: string = "/docs"): FastAPI =
  FastAPI(
    router: newAPIRouter(),
    title: title,
    version: version,
    openapi_url: openapi_url,
    docs_url: docs_url,
    middlewares: @[],
    exception_handlers: initTable[string, ExceptionHandler]()
  )

proc add_middleware*(self: FastAPI, handler: MiddlewareHandler) =
  self.middlewares.add(handler)

proc add_exception_handler*(self: FastAPI, exc_class: typedesc, handler: ExceptionHandler) =
  self.exception_handlers[$exc_class] = handler

proc add_route*(self: FastAPI, path: string, handler: routing.RequestHandler, methods: seq[string] = @["GET"], parameters: seq[ParamInfo] = @[]) =
  let route = newRoute(path, handler, methods)
  if parameters.len > 0:
    route.parameters = parameters
  self.router.routes.add(route)

proc getParamExtraction(req: NimNode, nameStr: string, typ: NimNode): NimNode =
  if $typ == "int":
    return quote do:
      if `req`.pathParams.hasKey(`nameStr`):
        parseInt(`req`.pathParams[`nameStr`])
      else:
        parseInt(`req`.queryParams.getOrDefault(`nameStr`, "0"))
  elif $typ == "string":
    return quote do:
      if `req`.pathParams.hasKey(`nameStr`):
        `req`.pathParams[`nameStr`]
      else:
        `req`.queryParams.getOrDefault(`nameStr`, "")
  elif $typ == "JsonNode":
    return quote do:
      `req`.json()
  else:
    return quote do:
      decode_json[`typ`](`req`.json())

proc resolveProcRecursive(req: NimNode, setupStmts: NimNode, handler: NimNode, btSym: NimNode): NimNode =
  let handlerType = handler.getTypeImpl
  var formalParams: NimNode
  if handlerType.kind == nnkProcTy:
    formalParams = handlerType[0]
  else:
    let impl = handler.getImpl
    if impl.kind != nnkEmpty:
      formalParams = impl.params
    else:
      return newCall(handler)

  var callArgs = newSeq[NimNode]()

  if formalParams.len > 1:
    for i in 1 .. formalParams.len - 1:
      let identDefs = formalParams[i]
      let typ = identDefs[^2]
      let default = identDefs[^1]

      for j in 0 .. identDefs.len - 3:
        let name = identDefs[j]
        let nameStr = $name

        var isDepends = false
        var depProc: NimNode

        if default.kind in {nnkCall, nnkCommand, nnkHiddenCallConv}:
          let callNode = default[0]
          if callNode.kind == nnkBracketExpr:
            if $callNode[0] == "Depends":
              isDepends = true
              depProc = default[1]
          elif $callNode == "Depends":
            isDepends = true
            depProc = default[1]

        if isDepends:
          let depRes = genSym(nskLet, "depRes")
          let depCall = resolveProcRecursive(req, setupStmts, depProc, btSym)
          setupStmts.add(quote do:
            let `depRes` = `depCall`
          )
          callArgs.add(depRes)
        elif $typ == "Request" or $typ == "requests.Request":
          callArgs.add(req)
        elif $typ == "BackgroundTasks":
          callArgs.add(btSym)
        else:
          let val = genSym(nskLet, "val")
          let extract = getParamExtraction(req, nameStr, typ)
          setupStmts.add(quote do:
            let `val` = `extract`
          )
          callArgs.add(val)

  result = newCall(handler)
  for arg in callArgs:
    result.add(arg)

macro api_handler*(handler: typed): untyped =
  let req = genSym(nskParam, "req")
  var setupStmts = newStmtList()
  let btSym = genSym(nskLet, "bt")

  let callExpr = resolveProcRecursive(req, setupStmts, handler, btSym)

  result = quote do:
    proc (`req`: requests.Request): Future[responses.Response] {.async, gcsafe.} =
      var finalRes: responses.Response
      try:
        let `btSym` = newBackgroundTasks()
        `setupStmts`

        var res: responses.Response
        when compiles(await `callExpr`):
          let rawRes = await `callExpr`
        else:
          let rawRes = `callExpr`

        when typeof(rawRes) is JsonNode:
          res = JSONResponse(rawRes)
        elif typeof(rawRes) is responses.Response:
          res = rawRes
        else:
          res = newResponse($rawRes)

        finalRes = res
        await `btSym`.run()
      except HTTPException as e:
        finalRes = JSONResponse(e.detail, e.status_code)
      except Exception as e:
        finalRes = JSONResponse(%*{"detail": e.msg}, Http500)

      return finalRes

macro get*(self: FastAPI, path: static string, handler: typed): untyped =
  result = quote do:
    `self`.add_route(`path`, api_handler(`handler`), @["GET"])

macro post*(self: FastAPI, path: static string, handler: typed): untyped =
  result = quote do:
    `self`.add_route(`path`, api_handler(`handler`), @["POST"])

proc setup(self: FastAPI) =
  let selfCapture = self
  if self.openapi_url != "":
    self.add_route(self.openapi_url, proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.} =
      return JSONResponse(generateOpenAPI(selfCapture.title, selfCapture.version, selfCapture.router.routes))
    )

  if self.docs_url != "":
    self.add_route(self.docs_url, proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.} =
      let html = """
<!DOCTYPE html>
<html>
<head>
    <link type="text/css" rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css">
    <title>""" & selfCapture.title & """ - Swagger UI</title>
</head>
<body>
    <div id="swagger-ui"></div>
    <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
    <script>
    const ui = SwaggerUIBundle({
        url: '""" & selfCapture.openapi_url & """',
        dom_id: '#swagger-ui',
        presets: [
            SwaggerUIBundle.presets.apis,
            SwaggerUIBundle.SwaggerUIStandalonePreset
        ],
        layout: "BaseLayout"
    })
    </script>
</body>
</html>
"""
      return newResponse(html, Http200, newHttpHeaders({"Content-Type": "text/html"}))
    )

proc handleRequest(self: FastAPI, req: requests.Request): Future[responses.Response] {.async, gcsafe.} =
  var idx = 0
  let selfCapture = self
  proc next(req: requests.Request): Future[responses.Response] {.async, gcsafe.} =
    if idx < selfCapture.middlewares.len:
      let mw = selfCapture.middlewares[idx]
      idx += 1
      return await mw(req, next)
    else:
      return await selfCapture.router.handle(req)

  return await next(req)

proc run*(self: FastAPI, port: int = 8000) =
  self.setup()
  let server = newAsyncHttpServer()
  let selfCapture = self
  proc cb(req: asynchttpserver.Request) {.async, gcsafe.} =
    let fastReq = newRequest(req)
    let resp = await selfCapture.handleRequest(fastReq)
    await req.respond(resp.status, resp.body, resp.headers)

  echo "Serving on http://localhost:", port
  waitFor server.serve(Port(port), cb)
