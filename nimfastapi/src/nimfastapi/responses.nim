import asynchttpserver, json, tables, os, mimetypes, strutils

type
  Response* = ref object
    status*: HttpCode
    body*: string
    headers*: HttpHeaders

proc newResponse*(body: string = "", status: HttpCode = Http200, headers: HttpHeaders = newHttpHeaders()): Response =
  Response(status: status, body: body, headers: headers)

proc JSONResponse*(content: JsonNode, status: HttpCode = Http200): Response =
  let headers = newHttpHeaders({"Content-Type": "application/json"})
  newResponse($content, status, headers)

proc HTMLResponse*(content: string, status: HttpCode = Http200): Response =
  let headers = newHttpHeaders({"Content-Type": "text/html"})
  newResponse(content, status, headers)

proc PlainTextResponse*(content: string, status: HttpCode = Http200): Response =
  let headers = newHttpHeaders({"Content-Type": "text/plain"})
  newResponse(content, status, headers)

proc RedirectResponse*(url: string, status: HttpCode = Http307): Response =
  let headers = newHttpHeaders({"Location": url})
  newResponse("", status, headers)

proc FileResponse*(path: string, status: HttpCode = Http200, media_type: string = ""): Response =
  let m = newMimetypes()
  let contentType = if media_type != "": media_type
                    else: m.getMimetype(splitFile(path).ext.strip(chars={'.'}))
  let body = readFile(path)
  let headers = newHttpHeaders({"Content-Type": contentType})
  newResponse(body, status, headers)

# StreamingResponse is tricky with standard asynchttpserver
# as it expects a full body in req.respond.
# For now we'll just implement it as a normal response that takes an iterator.
# A real implementation would need a different server backend.
proc StreamingResponse*(content: iterator (): string, status: HttpCode = Http200): Response =
  var fullBody = ""
  for chunk in content():
    fullBody.add(chunk)
  newResponse(fullBody, status)
