import asynchttpserver, tables, json, strutils, uri

type
  Request* = ref object
    httpReq*: asynchttpserver.Request
    pathParams*: Table[string, string]
    queryParams*: Table[string, string]

proc newRequest*(req: asynchttpserver.Request): Request =
  var queryParams = initTable[string, string]()

  if req.url.query != "":
    for pair in req.url.query.split('&'):
      let parts = pair.split('=')
      if parts.len == 2:
        queryParams[parts[0]] = parts[1]

  Request(
    httpReq: req,
    pathParams: initTable[string, string](),
    queryParams: queryParams
  )

proc body*(self: Request): string =
  self.httpReq.body

proc json*(self: Request): JsonNode =
  parseJson(self.body)

proc httpMethod*(self: Request): string =
  $self.httpReq.reqMethod
