import asynchttpserver, json, httpcore

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
