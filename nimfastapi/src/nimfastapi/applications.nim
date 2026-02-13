import asyncdispatch, asynchttpserver, strutils, sequtils, tables, json, macros, times, options, ws as ws_lib, re
import routing, requests, responses, openapi, dependencies, background, exceptions, encoders, params, websockets

export tables, strutils, options, requests, responses, json, encoders, asyncdispatch # Export common ones used by macros

type
  MiddlewareHandler* = proc (req: requests.Request, next: proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.}): Future[responses.Response] {.async, gcsafe.}
  ExceptionHandler* = proc (req: requests.Request, exc: ref Exception): Future[responses.Response] {.async, gcsafe.}
  LifespanHandler* = proc (): Future[void] {.async, gcsafe.}

  FastAPI* = ref object
    router*: APIRouter
    title*: string
    description*: string
    version*: string
    openapi_url*: string
    docs_url*: string
    redoc_url*: string
    middlewares*: seq[MiddlewareHandler]
    exception_handlers*: Table[string, ExceptionHandler]
    on_startup*: seq[LifespanHandler]
    on_shutdown*: seq[LifespanHandler]
    dependencies*: seq[DependencyMarker]

proc http_exception_handler(req: requests.Request, exc: ref Exception): Future[responses.Response] {.async, gcsafe.} =
  let e = cast[HTTPException](exc)
  return JSONResponse(%*{"detail": e.detail}, e.status_code)

proc general_exception_handler(req: requests.Request, exc: ref Exception): Future[responses.Response] {.async, gcsafe.} =
  return JSONResponse(%*{"detail": exc.msg}, Http500)

proc newFastAPI*(title: string = "FastAPI", description: string = "", version: string = "0.1.0", openapi_url: string = "/openapi.json", docs_url: string = "/docs", redoc_url: string = "/redoc"): FastAPI =
  let app = FastAPI(router: newAPIRouter(), title: title, description: description, version: version, openapi_url: openapi_url, docs_url: docs_url, redoc_url: redoc_url, middlewares: @[], exception_handlers: initTable[string, ExceptionHandler](), on_startup: @[], on_shutdown: @[], dependencies: @[])
  app.exception_handlers["HTTPException"] = http_exception_handler
  app.exception_handlers["Exception"] = general_exception_handler
  return app

proc add_middleware*(self: FastAPI, handler: MiddlewareHandler) = self.middlewares.add(handler)
proc add_exception_handler*(self: FastAPI, exc_class: typedesc, handler: ExceptionHandler) = self.exception_handlers[$exc_class] = handler
proc add_event_handler*(self: FastAPI, event_type: string, handler: LifespanHandler) = (if event_type == "startup": self.on_startup.add(handler) elif event_type == "shutdown": self.on_shutdown.add(handler))

proc handleRequest*(self: FastAPI, req: requests.Request): Future[responses.Response] {.async, gcsafe.}

# Safe Parsing Helpers
proc safeParseInt*(s: string, name: string): int =
  try: result = parseInt(s)
  except: raise newHTTPException(HttpCode(422), "Invalid integer value for parameter: " & name)

proc safeParseFloat*(s: string, name: string): float =
  try: result = parseFloat(s)
  except: raise newHTTPException(HttpCode(422), "Invalid float value for parameter: " & name)

proc safeParseBool*(s: string, name: string): bool =
  let val = s.toLowerAscii()
  if val in ["true", "1", "yes", "on"]: return true
  if val in ["false", "0", "no", "off"]: return false
  raise newHTTPException(HttpCode(422), "Invalid boolean value for parameter: " & name)

proc add_route*(self: FastAPI, path: string, handler: routing.RequestHandler, methods: seq[string] = @["GET"], parameters: seq[ParamInfo] = @[], tags: seq[string] = @[], summary: string = "", description: string = "") =
  let route = newRoute(path, handler, methods)
  route.parameters = parameters
  route.tags = tags
  route.summary = summary
  route.description = description
  self.router.routes.add(route)

proc include_router*(self: FastAPI, router: APIRouter) =
  for route in router.routes:
    let fullPath = router.prefix & (if route.path == "/" and router.prefix != "": "" else: route.path)
    let newRoute = newRoute(fullPath, route.handler, route.methods)
    newRoute.parameters = route.parameters
    newRoute.tags = router.tags & route.tags
    newRoute.summary = route.summary
    newRoute.description = route.description
    newRoute.isWebSocket = route.isWebSocket
    newRoute.wsHandler = route.wsHandler
    self.router.routes.add(newRoute)

proc mount*(self: FastAPI, path: string, app: FastAPI) =
  let mountPath = if path.endsWith("/") and path.len > 1: path[0 .. ^2] else: path
  let handler = proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.} =
    let oldRoot = req.root_path
    req.root_path = oldRoot & mountPath
    let res = await app.handleRequest(req)
    req.root_path = oldRoot
    return res
  let route = newRoute(mountPath, handler, @[])
  route.isMount = true
  self.router.routes.add(route)

proc getCallName(call: NimNode): string =
  if call.kind notin {nnkCall, nnkCommand}: return ""
  let nameNode = call[0]
  if nameNode.kind == nnkIdent: return $nameNode
  if nameNode.kind == nnkDotExpr: return $nameNode[1]
  return ""

proc typeToString(node: NimNode): string =
  if node.kind == nnkIdent: return $node
  if node.kind == nnkDotExpr: return typeToString(node[0]) & "." & typeToString(node[1])
  if node.kind == nnkBracketExpr:
    var res = typeToString(node[0]) & "["
    for i in 1 ..< node.len:
      res.add(typeToString(node[i]))
      if i < node.len - 1: res.add(", ")
    res.add("]")
    return res
  return ""

proc getParamExtraction(req: NimNode, nameStr: string, typ: NimNode, kind: string): NimNode =
  let nameLit = newLit(nameStr)
  let reqPathParams = nnkDotExpr.newTree(req, ident"pathParams")
  let reqHeaders = nnkDotExpr.newTree(req, ident"headers")
  let reqQueryParams = nnkDotExpr.newTree(req, ident"queryParams")
  let typStr = typeToString(typ)
  if kind == "path":
    let extraction = nnkBracketExpr.newTree(reqPathParams, nameLit)
    if typStr == "int": result = nnkCall.newTree(ident"safeParseInt", extraction, nameLit)
    else: result = extraction
  elif kind == "header": result = nnkCall.newTree(ident"getHeader", reqHeaders, nameLit, newLit(""))
  elif kind == "cookie": result = nnkCall.newTree(ident"getHeader", reqHeaders, newLit("Cookie"), newLit(""))
  elif kind == "body":
    if typStr == "JsonNode": result = nnkCall.newTree(nnkDotExpr.newTree(req, ident"json"))
    else: result = nnkCall.newTree(nnkBracketExpr.newTree(ident"decode_json", typ), nnkCall.newTree(nnkDotExpr.newTree(req, ident"json")))
  elif kind == "form":
    let formCall = nnkCall.newTree(nnkDotExpr.newTree(req, ident"form"))
    let extraction = nnkCall.newTree(ident"getOrDefault", formCall, nameLit, (if typStr == "int": newLit("0") else: newLit("")))
    if typStr == "int": result = nnkCall.newTree(ident"safeParseInt", extraction, nameLit)
    else: result = extraction
  elif kind == "file":
    let filesCall = nnkCall.newTree(nnkDotExpr.newTree(req, ident"files"))
    result = nnkBracketExpr.newTree(filesCall, nameLit)
  else:
    let extraction = nnkCall.newTree(ident"getOrDefault", reqQueryParams, nameLit, (if typStr == "int": newLit("0") elif typStr == "float": newLit("0.0") elif typStr == "bool": newLit("false") else: newLit("")))
    if typStr == "int": result = nnkCall.newTree(ident"safeParseInt", extraction, nameLit)
    elif typStr == "float": result = nnkCall.newTree(ident"safeParseFloat", extraction, nameLit)
    elif typStr == "bool": result = nnkCall.newTree(ident"safeParseBool", extraction, nameLit)
    else: result = extraction

proc parseParamMetadata(call: NimNode): ParamInfo =
  result = ParamInfo(required: true)
  let name = getCallName(call)
  if name == "": return result
  if name.contains("Query"): result.kind = "query"
  elif name.contains("Path"): result.kind = "path"
  elif name.contains("Body"): result.kind = "body"
  elif name.contains("Header"): result.kind = "header"
  elif name.contains("Cookie"): result.kind = "cookie"
  elif name.contains("Form"): result.kind = "form"
  elif name.contains("File"): result.kind = "file"
  for i in 1 .. call.len - 1:
    let arg = call[i]
    if arg.kind in {nnkExprColonExpr, nnkExprEqExpr}:
      let key = $arg[0]
      let val = arg[1]
      case key:
      of "min_length": result.min_length = some(val.intVal.int)
      of "max_length": result.max_length = some(val.intVal.int)
      of "regex": result.regex = val.strVal
      of "gt": result.gt = some(if val.kind == nnkFloatLit: val.floatVal else: val.intVal.float)
      of "default", "default_val": result.required = false
      else: discard
    elif i == 1: result.required = false

proc extractParamInfos(handler: NimNode): seq[ParamInfo] =
  result = @[]
  var actualHandler = handler
  if handler.kind == nnkStmtList and handler.len > 0: actualHandler = handler[0]
  var formalParams: NimNode
  if actualHandler.kind in {nnkProcDef, nnkLambda, nnkDo}: formalParams = actualHandler.params
  else: return @[]
  if formalParams != nil and formalParams.len > 1:
    for i in 1 .. formalParams.len - 1:
      let identDefs = formalParams[i]
      let typ = identDefs[^2]
      let default = identDefs[^1]
      for j in 0 .. identDefs.len - 3:
        let name = identDefs[j]
        let nameStr = $name
        var info = ParamInfo(name: nameStr, typ: typeToString(typ), kind: "query", required: true)
        if default.kind != nnkEmpty:
          info.required = false
          if default.kind in {nnkCall, nnkCommand}:
            let callName = getCallName(default)
            if callName in ["Query", "Path", "Header", "Cookie", "Body", "Form", "File", "NewQuery", "NewPath"]:
               info = parseParamMetadata(default)
               info.name = nameStr
               info.typ = typeToString(typ)
        let typStr = typeToString(typ)
        if typStr notin ["int", "string", "float", "bool", "JsonNode", "Request", "requests.Request", "BackgroundTasks"] and info.kind == "query": info.kind = "body"
        if typStr == "Request" or typStr == "requests.Request" or typStr == "BackgroundTasks": continue
        result.add(info)

macro resolveDependency*(req: requests.Request, dep: typed): untyped =
  var impl: NimNode = newEmptyNode()
  if dep.kind == nnkSym:
    try: impl = dep.getImpl
    except: impl = newEmptyNode()
  if impl.kind == nnkEmpty:
    return quote do: (block:
      when compiles(`dep`(`req`)):
        when `dep`(`req`) is Future: await `dep`(`req`)
        else: `dep`(`req`)
      else:
        when `dep`() is Future: await `dep`()
        else: `dep`()
    )
  if impl.kind notin {nnkProcDef, nnkLambda, nnkDo}: return newCall(dep, req)
  var callArgs = newSeq[NimNode]()
  let params = impl.params
  for i in 1 ..< params.len:
    let identDefs = params[i]
    let typ = identDefs[^2]
    let default = identDefs[^1]
    for j in 0 .. identDefs.len - 3:
      let name = identDefs[j]
      let nameStr = $name
      let typStr = typeToString(typ)
      if typStr == "Request" or typStr == "requests.Request": callArgs.add(req)
      elif default.kind in {nnkCall, nnkCommand} and getCallName(default) == "Depends":
        let subDep = default[1]
        callArgs.add(nnkCall.newTree(ident"resolveDependency", req, subDep))
      else:
        var info = ParamInfo(kind: "query", required: true)
        if default.kind in {nnkCall, nnkCommand}: info = parseParamMetadata(default)
        let extractKind = if not (typStr in ["int", "string", "float", "bool", "JsonNode", "UploadFile"]) and info.kind == "query": "body" else: info.kind
        callArgs.add(getParamExtraction(req, nameStr, typ, extractKind))
  let callExpr = newCall(dep)
  for arg in callArgs: callExpr.add(arg)
  result = quote do: (block: (when `callExpr` is Future: await `callExpr` else: `callExpr`))

macro api_handler_v4*(handler: untyped, extra_deps: static seq[DependencyMarker] = @[]): untyped =
  let req = genSym(nskParam, "req")
  let btSym = genSym(nskLet, "bt")
  var setupStmts = newStmtList()
  var validationStmts = newStmtList()
  var actualHandler = handler
  if handler.kind == nnkStmtList: actualHandler = handler[0]
  var callArgs = newSeq[NimNode]()
  if actualHandler.kind in {nnkProcDef, nnkLambda, nnkDo}:
    var paramsNode = actualHandler.params
    for i in 1 ..< paramsNode.len:
      let identDefs = paramsNode[i]
      let typ = identDefs[^2]
      let default = identDefs[^1]
      for j in 0 .. identDefs.len - 3:
        let name = identDefs[j]
        let nameStr = $name
        var info = ParamInfo(kind: "query", required: true)
        if default.kind in {nnkCall, nnkCommand}: info = parseParamMetadata(default)
        let typStr = typeToString(typ)
        if typStr == "Request" or typStr == "requests.Request": callArgs.add(req)
        elif typStr == "BackgroundTasks": callArgs.add(btSym)
        elif default.kind in {nnkCall, nnkCommand} and getCallName(default) == "Depends":
          let depProc = default[1]
          let depRes = genSym(nskLet, "depRes")
          setupStmts.add(quote do: (let `depRes` = resolveDependency(`req`, `depProc`)))
          callArgs.add(depRes)
        else:
          let val = genSym(nskLet, "val")
          let extractKind = if not (typStr in ["int", "string", "float", "bool", "JsonNode", "UploadFile"]) and info.kind == "query": "body" else: info.kind
          let extract = getParamExtraction(req, nameStr, typ, extractKind)
          setupStmts.add(newLetStmt(val, extract))
          if info.min_length.isSome:
            let ml = info.min_length.get
            validationStmts.add(quote do: (if `val`.len < `ml`: raise newHTTPException(HttpCode(422), "String too short for parameter " & `nameStr` & ". Min length: " & $`ml`)))
          if info.max_length.isSome:
            let ml = info.max_length.get
            validationStmts.add(quote do: (if `val`.len > `ml`: raise newHTTPException(HttpCode(422), "String too long for parameter " & `nameStr` & ". Max length: " & $`ml`)))
          if info.gt.isSome:
            let gtv = info.gt.get
            validationStmts.add(quote do: (if `val`.float <= `gtv`: raise newHTTPException(HttpCode(422), "Value must be greater than " & $`gtv` & " for parameter " & `nameStr`)))
          callArgs.add(val)
  var cleanHandler = actualHandler.copyNimTree
  if cleanHandler.kind in {nnkProcDef, nnkLambda, nnkDo}:
    for i in 1 ..< cleanHandler.params.len:
      let default = cleanHandler.params[i][^1]
      if default.kind in {nnkCall, nnkCommand} and getCallName(default) in ["Query", "Path", "Body", "Depends"]:
        cleanHandler.params[i][^1] = nnkCall.newTree(ident"default", cleanHandler.params[i][^2])
  let body = newStmtList()
  body.add(newLetStmt(btSym, newCall(ident"newBackgroundTasks")))
  for dep in extra_deps: body.add(quote do: await `dep`.handler(`req`))
  for s in setupStmts: body.add(s)
  for v in validationStmts: body.add(v)
  let handlerName = if cleanHandler.kind == nnkProcDef and cleanHandler.name.kind != nnkEmpty: cleanHandler.name else: genSym(nskProc, "handler")
  if cleanHandler.kind == nnkProcDef:
    if cleanHandler.name.kind == nnkEmpty: cleanHandler.name = handlerName
    body.add(cleanHandler)
  elif cleanHandler.kind in {nnkLambda, nnkDo}: body.add(newLetStmt(handlerName, cleanHandler))
  let callExpr = newCall(handlerName)
  for arg in callArgs: callExpr.add(arg)
  body.add(quote do:
    var res: responses.Response
    let rawRes = (block:
      when `callExpr` is Future: await `callExpr`
      else: `callExpr`)
    when typeof(rawRes) is JsonNode: res = JSONResponse(rawRes)
    elif typeof(rawRes) is responses.Response: res = rawRes
    elif typeof(rawRes) is void: res = JSONResponse(newJNull())
    else:
      when compiles(jsonable_encoder(rawRes)): res = JSONResponse(jsonable_encoder(rawRes))
      else: res = newResponse($rawRes)
    await `btSym`.run()
    return res
  )
  result = nnkLambda.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode(), nnkFormalParams.newTree(nnkBracketExpr.newTree(ident"Future", ident"Response"), nnkIdentDefs.newTree(req, nnkDotExpr.newTree(ident"requests", ident"Request"), newEmptyNode())), nnkPragma.newTree(ident"async", ident"gcsafe"), newEmptyNode(), body)

macro get*(self: FastAPI | APIRouter, path: static string, args: varargs[untyped]): untyped =
  var handler, summary, description: NimNode
  var tags = nnkPrefix.newTree(ident"@", nnkBracket.newTree())
  var dependencies = nnkPrefix.newTree(ident"@", nnkBracket.newTree())
  summary = newLit(""); description = newLit("")
  for arg in args:
    if arg.kind in {nnkProcDef, nnkLambda, nnkDo}: handler = arg
    elif arg.kind == nnkStmtList and arg.len > 0:
      for sub in arg: (if sub.kind in {nnkProcDef, nnkLambda, nnkDo}: (handler = sub; break))
    elif arg.kind == nnkExprColonExpr:
      let key = $arg[0]
      if key == "tags": tags = arg[1]
      elif key == "summary": summary = arg[1]
      elif key == "description": description = arg[1]
      elif key == "dependencies": dependencies = arg[1]
  let params = extractParamInfos(handler)
  var paramsNode = nnkPrefix.newTree(ident"@", nnkBracket.newTree())
  for p in params:
    paramsNode[1].add(nnkObjConstr.newTree(ident"ParamInfo", nnkExprColonExpr.newTree(ident"name", newLit(p.name)), nnkExprColonExpr.newTree(ident"kind", newLit(p.kind)), nnkExprColonExpr.newTree(ident"typ", newLit(p.typ)), nnkExprColonExpr.newTree(ident"required", newLit(p.required)), nnkExprColonExpr.newTree(ident"description", newLit(p.description)), nnkExprColonExpr.newTree(ident"regex", newLit(p.regex)), nnkExprColonExpr.newTree(ident"min_length", (if p.min_length.isSome: nnkCall.newTree(ident"some", newLit(p.min_length.get)) else: nnkCall.newTree(ident"none", ident"int"))), nnkExprColonExpr.newTree(ident"max_length", (if p.max_length.isSome: nnkCall.newTree(ident"some", newLit(p.max_length.get)) else: nnkCall.newTree(ident"none", ident"int"))), nnkExprColonExpr.newTree(ident"gt", (if p.gt.isSome: nnkCall.newTree(ident"some", newLit(p.gt.get)) else: nnkCall.newTree(ident"none", ident"float"))), nnkExprColonExpr.newTree(ident"ge", (if p.ge.isSome: nnkCall.newTree(ident"some", newLit(p.ge.get)) else: nnkCall.newTree(ident"none", ident"float"))), nnkExprColonExpr.newTree(ident"lt", (if p.lt.isSome: nnkCall.newTree(ident"some", newLit(p.lt.get)) else: nnkCall.newTree(ident"none", ident"float"))), nnkExprColonExpr.newTree(ident"le", (if p.le.isSome: nnkCall.newTree(ident"some", newLit(p.le.get)) else: nnkCall.newTree(ident"none", ident"float")))))
  result = quote do:
    when `self` is FastAPI: `self`.add_route(`path`, api_handler_v4(`handler`, `dependencies`), @["GET"], `paramsNode`, tags = `tags`, summary = `summary`, description = `description`)
    else: (let route = newRoute(`path`, api_handler_v4(`handler`, `dependencies`), @["GET"]); route.parameters = `paramsNode`; route.tags = `tags`; route.summary = `summary`; route.description = `description`; `self`.routes.add(route))

macro post*(self: FastAPI | APIRouter, path: static string, args: varargs[untyped]): untyped =
  var handler, summary, description: NimNode
  var tags = nnkPrefix.newTree(ident"@", nnkBracket.newTree())
  var dependencies = nnkPrefix.newTree(ident"@", nnkBracket.newTree())
  summary = newLit(""); description = newLit("")
  for arg in args:
    if arg.kind in {nnkProcDef, nnkLambda, nnkDo}: handler = arg
    elif arg.kind == nnkStmtList and arg.len > 0:
      for sub in arg: (if sub.kind in {nnkProcDef, nnkLambda, nnkDo}: (handler = sub; break))
    elif arg.kind == nnkExprColonExpr:
      let key = $arg[0]
      if key == "tags": tags = arg[1]
      elif key == "summary": summary = arg[1]
      elif key == "description": description = arg[1]
      elif key == "dependencies": dependencies = arg[1]
  let params = extractParamInfos(handler)
  var paramsNode = nnkPrefix.newTree(ident"@", nnkBracket.newTree())
  for p in params:
    paramsNode[1].add(nnkObjConstr.newTree(ident"ParamInfo", nnkExprColonExpr.newTree(ident"name", newLit(p.name)), nnkExprColonExpr.newTree(ident"kind", newLit(p.kind)), nnkExprColonExpr.newTree(ident"typ", newLit(p.typ)), nnkExprColonExpr.newTree(ident"required", newLit(p.required)), nnkExprColonExpr.newTree(ident"min_length", nnkCall.newTree(ident"none", ident"int")), nnkExprColonExpr.newTree(ident"max_length", nnkCall.newTree(ident"none", ident"int")), nnkExprColonExpr.newTree(ident"gt", nnkCall.newTree(ident"none", ident"float")), nnkExprColonExpr.newTree(ident"ge", nnkCall.newTree(ident"none", ident"float")), nnkExprColonExpr.newTree(ident"lt", nnkCall.newTree(ident"none", ident"float")), nnkExprColonExpr.newTree(ident"le", nnkCall.newTree(ident"none", ident"float"))))
  result = quote do:
    when `self` is FastAPI: `self`.add_route(`path`, api_handler_v4(`handler`, `dependencies`), @["POST"], `paramsNode`, tags = `tags`, summary = `summary`, description = `description`)
    else: (let route = newRoute(`path`, api_handler_v4(`handler`, `dependencies`), @["POST"]); route.parameters = `paramsNode`; route.tags = `tags`; route.summary = `summary`; route.description = `description`; `self`.routes.add(route))

macro websocket*(self: FastAPI | APIRouter, path: static string, handler: untyped): untyped =
  var actualHandler = handler
  if handler.kind == nnkStmtList: actualHandler = handler[0]
  let handlerName = if actualHandler.kind == nnkProcDef and actualHandler.name.kind != nnkEmpty: actualHandler.name else: genSym(nskProc, "wsHandler")
  if actualHandler.kind == nnkProcDef and actualHandler.name.kind == nnkEmpty: actualHandler.name = handlerName
  let setup = if actualHandler.kind == nnkProcDef: actualHandler else: newLetStmt(handlerName, actualHandler)
  result = quote do:
    `setup`
    let route = newWebSocketRoute(`path`, `handlerName`)
    when `self` is FastAPI: `self`.router.routes.add(route)
    else: `self`.routes.add(route)

proc setup*(self: FastAPI) =
  let selfCapture = self
  if self.openapi_url != "": self.add_route(self.openapi_url, proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.} = return JSONResponse(generateOpenAPI(selfCapture.title, selfCapture.version, selfCapture.router.routes, description = selfCapture.description)))
  if self.docs_url != "": self.add_route(self.docs_url, proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.} = (let html = "<html><head><link type='text/css' rel='stylesheet' href='https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css'><title>" & selfCapture.title & " - Swagger UI</title></head><body><div id='swagger-ui'></div><script src='https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js'></script><script>const ui = SwaggerUIBundle({url: '" & selfCapture.openapi_url & "',dom_id: '#swagger-ui',presets: [SwaggerUIBundle.presets.apis,SwaggerUIBundle.SwaggerUIStandalonePreset],layout: 'BaseLayout'})</script></body></html>"; return newResponse(html, Http200, newHttpHeaders({"Content-Type": "text/html"}))))
  if self.redoc_url != "": self.add_route(self.redoc_url, proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.} = (let html = "<html><head><title>" & selfCapture.title & " - ReDoc</title><meta charset='utf-8'/><meta name='viewport' content='width=device-width, initial-scale=1'><link href='https://fonts.googleapis.com/css?family=Montserrat:300,400,700|Roboto:300,400,700' rel='stylesheet'><style>body { margin: 0; padding: 0; }</style></head><body><redoc spec-url='" & selfCapture.openapi_url & "'></redoc><script src='https://cdn.jsdelivr.net/npm/redoc@next/bundles/redoc.standalone.js'> </script></body></html>"; return newResponse(html, Http200, newHttpHeaders({"Content-Type": "text/html"}))))

proc handleRequest(self: FastAPI, req: requests.Request): Future[responses.Response] {.async, gcsafe.} =
  var idx = 0
  let selfCapture = self
  proc next(req: requests.Request): Future[responses.Response] {.async, gcsafe.} =
    if idx < selfCapture.middlewares.len:
      let mw = selfCapture.middlewares[idx]
      idx += 1
      return await mw(req, next)
    else:
      try:
        for dep in selfCapture.dependencies: await dep.handler(req)
        return await selfCapture.router.handle(req)
      except Exception as e:
        if selfCapture.exception_handlers.hasKey($typeof(e)): return await selfCapture.exception_handlers[$typeof(e)](req, e)
        elif e of HTTPException: return await selfCapture.exception_handlers["HTTPException"](req, e)
        else: return await selfCapture.exception_handlers["Exception"](req, e)
  return await next(req)

proc run*(self: FastAPI, port: int = 8000) =
  self.setup()
  let selfCapture = self
  for handler in self.on_startup: waitFor handler()
  let server = newAsyncHttpServer()
  proc cb(req: asynchttpserver.Request) {.async, gcsafe.} =
    let fastReq = newRequest(req)
    for route in selfCapture.router.routes:
      if route.isWebSocket and route.match(fastReq):
        try:
          let websocket = await ws_lib.newWebSocket(req)
          let fws = websockets.newWebSocket(websocket, fastReq)
          await route.wsHandler(fws)
          return
        except: return
    let resp = await selfCapture.handleRequest(fastReq)
    await req.respond(resp.status, resp.body, resp.headers)
  echo "Serving on http://localhost:", port
  try: waitFor server.serve(Port(port), cb)
  finally:
    for handler in selfCapture.on_shutdown: waitFor handler()
