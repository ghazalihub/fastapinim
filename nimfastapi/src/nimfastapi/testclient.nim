import asyncdispatch, asynchttpserver, tables, json, uri
import applications, requests, responses

type
  TestClient* = ref object
    app*: FastAPI

proc newTestClient*(app: FastAPI): TestClient =
  TestClient(app: app)

proc request*(self: TestClient, meth: string, path: string, body: string = "", headers: HttpHeaders = newHttpHeaders()): responses.Response =
  # Construct a dummy asynchttpserver.Request
  # This is hard because asynchttpserver.Request is a ref object with hidden fields in some versions.
  # We might need to mock it or update applications.nim to handle our own Request type earlier.

  # For now, we'll try to construct a minimal one.
  # If this fails, we'll have to change how handleRequest works.

  # Actually, handleRequest takes our custom requests.Request.
  # So we just need to create that!

  var fastReq = requests.Request(
    httpReq: asynchttpserver.Request(), # Dummy
    pathParams: initTable[string, string](),
    queryParams: initTable[string, string](),
    headers: headers,
    root_path: ""
  )

  # We need to set some properties that might be used
  fastReq.httpReq.url = parseUri(path)
  fastReq.httpReq.reqMethod = meth.toUpperAscii().parseEnum[:HttpMethod]()
  fastReq.httpReq.body = body

  # Handle query params
  if fastReq.httpReq.url.query != "":
    for pair in fastReq.httpReq.url.query.split('&'):
      let parts = pair.split('=')
      if parts.len == 2:
        fastReq.queryParams[decodeUrl(parts[0])] = decodeUrl(parts[1])

  return waitFor self.app.handleRequest(fastReq)

proc get*(self: TestClient, path: string, headers: HttpHeaders = newHttpHeaders()): responses.Response =
  self.request("GET", path, "", headers)

proc post*(self: TestClient, path: string, body: string = "", headers: HttpHeaders = newHttpHeaders()): responses.Response =
  self.request("POST", path, body, headers)
