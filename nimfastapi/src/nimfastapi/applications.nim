import asyncdispatch, asynchttpserver, strutils, sequtils, tables, json, macros
import routing, requests, responses, openapi, dependencies, background

type
  MiddlewareHandler* = proc (req: requests.Request, next: proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.}): Future[responses.Response] {.async, gcsafe.}

  FastAPI* = ref object
    router*: APIRouter
    title*: string
    version*: string
    openapi_url*: string
    docs_url*: string
    middlewares*: seq[MiddlewareHandler]

proc newFastAPI*(title: string = "FastAPI", version: string = "0.1.0", openapi_url: string = "/openapi.json", docs_url: string = "/docs"): FastAPI =
  FastAPI(
    router: newAPIRouter(),
    title: title,
    version: version,
    openapi_url: openapi_url,
    docs_url: docs_url,
    middlewares: @[]
  )

proc add_middleware*(self: FastAPI, handler: MiddlewareHandler) =
  self.middlewares.add(handler)

proc add_route*(self: FastAPI, path: string, handler: RequestHandler, methods: seq[string] = @["GET"], parameters: seq[ParamInfo] = @[]) =
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
    return quote do: `req`.pathParams.getOrDefault(`nameStr`, "")

proc resolveProcRecursive(req: NimNode, setupStmts: NimNode, handler: NimNode, btSym: NimNode): NimNode =
  let handlerType = handler.getTypeImpl
  var formalParams: NimNode
  if handlerType.kind == nnkProcTy:
    formalParams = handlerType[0]
  else:
    formalParams = handler.getImpl.params

  var callArgs = newSeq[NimNode]()

  for i in 1 .. formalParams.len - 1:
    let identDefs = formalParams[i]
    let typ = identDefs[^2]
    let default = identDefs[^1]

    for j in 0 .. identDefs.len - 3:
      let name = identDefs[j]
      let nameStr = $name

      if default.kind != nnkEmpty and (default.kind == nnkCall or default.kind == nnkCommand) and ($default[0] == "Depends"):
        let depProc = default[1]
        let depRes = genSym(nskLet, "depRes")
        let depCall = resolveProcRecursive(req, setupStmts, depProc, btSym)
        setupStmts.add(quote do:
          let `depRes` = `depCall`
        )
        callArgs.add(depRes)
      elif $typ == "Request":
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

  setupStmts.add(quote do:
    let `btSym` = newBackgroundTasks()
  )

  let callExpr = resolveProcRecursive(req, setupStmts, handler, btSym)

  result = quote do:
    proc (`req`: requests.Request): Future[responses.Response] {.async, gcsafe.} =
      `setupStmts`

      template callHandler(): untyped = `callExpr`

      var finalRes: responses.Response
      when callHandler() is Future:
        let res = await callHandler()
        when res is JsonNode:
          finalRes = JSONResponse(res)
        elif res is responses.Response:
          finalRes = res
        else:
          finalRes = newResponse($res)
      else:
        let res = callHandler()
        when res is JsonNode:
          finalRes = JSONResponse(res)
        elif res is responses.Response:
          finalRes = res
        else:
          finalRes = newResponse($res)

      await `btSym`.run()
      return finalRes

# Macros for decorators
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
