import asyncdispatch, asynchttpserver, strutils, sequtils, tables
import ../requests, ../responses, ../applications

proc CORSMiddleware*(
    allow_origins: seq[string] = @[],
    allow_methods: seq[string] = @["GET"],
    allow_headers: seq[string] = @[],
    allow_credentials: bool = false,
    expose_headers: seq[string] = @[],
    max_age: int = 600
): MiddlewareHandler =
  return proc (req: requests.Request, next: proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.}): Future[responses.Response] {.async, gcsafe.} =
    let origin = req.headers.getHeader("Origin", "")

    # Handle preflight
    if req.httpMethod == "OPTIONS" and origin != "" and req.headers.hasKey("Access-Control-Request-Method"):
      var headers = newHttpHeaders()

      # Origins
      if allow_origins.contains("*"):
        headers.add("Access-Control-Allow-Origin", "*")
      elif allow_origins.contains(origin):
        headers.add("Access-Control-Allow-Origin", origin)
        headers.add("Vary", "Origin")

      # Credentials
      if allow_credentials:
        headers.add("Access-Control-Allow-Credentials", "true")

      # Methods
      headers.add("Access-Control-Allow-Methods", allow_methods.join(", "))

      # Headers
      if allow_headers.contains("*"):
        if req.headers.hasKey("Access-Control-Request-Headers"):
          headers.add("Access-Control-Allow-Headers", req.headers["Access-Control-Request-Headers"])
      else:
        headers.add("Access-Control-Allow-Headers", allow_headers.join(", "))

      headers.add("Access-Control-Max-Age", $max_age)

      return newResponse("", Http200, headers)

    # Simple requests
    var res = await next(req)

    if origin != "":
      if allow_origins.contains("*"):
        res.headers.add("Access-Control-Allow-Origin", "*")
      elif allow_origins.contains(origin):
        res.headers.add("Access-Control-Allow-Origin", origin)
        res.headers.add("Vary", "Origin")

      if allow_credentials:
        res.headers.add("Access-Control-Allow-Credentials", "true")

      if expose_headers.len > 0:
        res.headers.add("Access-Control-Expose-Headers", expose_headers.join(", "))

    return res
