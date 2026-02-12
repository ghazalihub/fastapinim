import asyncdispatch, asynchttpserver, strutils, sequtils, tables, options
import requests, responses, websockets

type
  RequestHandler* = proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.}

  ParamInfo* = object
    name*: string
    kind*: string # "path", "query", "body", "header", "cookie"
    typ*: string # "string", "int", etc.
    description*: string
    required*: bool
    default*: string
    alias*: string
    deprecated*: bool
    # Validation
    gt*: Option[float]
    ge*: Option[float]
    lt*: Option[float]
    le*: Option[float]
    min_length*: Option[int]
    max_length*: Option[int]
    regex*: string

  Route* = ref object
    path*: string
    methods*: seq[string]
    handler*: RequestHandler
    wsHandler*: WebSocketHandler
    isWebSocket*: bool
    pathParts*: seq[string]
    paramNames*: seq[string]
    parameters*: seq[ParamInfo]
    tags*: seq[string]
    summary*: string
    description*: string
    isMount*: bool

  APIRouter* = ref object
    routes*: seq[Route]
    prefix*: string
    tags*: seq[string]

proc compilePath(path: string): (seq[string], seq[string]) =
  var pathParts: seq[string] = @[]
  var paramNames: seq[string] = @[]
  let parts = path.split('/')
  for part in parts:
    if part == "": continue
    if part.startsWith("{") and part.endsWith("}"):
      paramNames.add(part[1 .. ^2])
      pathParts.add("{}")
    else:
      pathParts.add(part)
  return (pathParts, paramNames)

proc newRoute*(path: string, handler: RequestHandler, methods: seq[string] = @["GET"]): Route =
  let (pathParts, paramNames) = compilePath(path)
  var params: seq[ParamInfo] = @[]
  for name in paramNames:
    params.add(ParamInfo(name: name, kind: "path", typ: "string"))

  Route(
    path: path,
    methods: methods,
    handler: handler,
    pathParts: pathParts,
    paramNames: paramNames,
    parameters: params,
    isWebSocket: false
  )

proc newWebSocketRoute*(path: string, handler: WebSocketHandler): Route =
  let (pathParts, paramNames) = compilePath(path)
  Route(
    path: path,
    wsHandler: handler,
    isWebSocket: true,
    pathParts: pathParts,
    paramNames: paramNames,
    parameters: @[]
  )

proc match*(self: Route, req: requests.Request): bool =
  if not self.isMount and not self.isWebSocket and req.httpMethod notin self.methods:
    return false

  let path = req.httpReq.url.path
  if self.isMount:
    return path.startsWith(self.path)

  let reqParts = path.split('/').filterIt(it != "")
  if reqParts.len != self.pathParts.len:
    return false

  var params = initTable[string, string]()
  var paramIdx = 0
  for i in 0 ..< self.pathParts.len:
    if self.pathParts[i] == "{}":
      params[self.paramNames[paramIdx]] = reqParts[i]
      paramIdx += 1
    elif self.pathParts[i] != reqParts[i]:
      return false

  for k, v in params:
    req.pathParams[k] = v
  return true

proc newAPIRouter*(prefix: string = "", tags: seq[string] = @[]): APIRouter =
  APIRouter(routes: @[], prefix: prefix, tags: tags)

proc add_route*(self: APIRouter, path: string, handler: RequestHandler, methods: seq[string] = @["GET"]) =
  self.routes.add(newRoute(path, handler, methods))

proc handle*(self: APIRouter, req: requests.Request): Future[responses.Response] {.async, gcsafe.} =
  for route in self.routes:
    if not route.isWebSocket and route.match(req):
      return await route.handler(req)
  return newResponse("Not Found", Http404)
