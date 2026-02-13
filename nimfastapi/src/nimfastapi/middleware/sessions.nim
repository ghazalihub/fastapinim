import asyncdispatch, asynchttpserver, strutils, sequtils, tables, json, base64
import ../requests, ../responses, ../applications

type
  SessionMiddlewareOptions* = object
    secret_key*: string
    session_cookie*: string = "session"
    max_age*: int = 14 * 24 * 60 * 60 # 14 days

proc SessionMiddleware*(
    secret_key: string,
    session_cookie: string = "session",
    max_age: int = 14 * 24 * 60 * 60
): MiddlewareHandler =
  return proc (req: requests.Request, next: proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.}): Future[responses.Response] {.async, gcsafe.} =
    # Parse session from cookie
    let cookieHeader = req.headers.getHeader("Cookie", "")
    var sessionData = newJObject()

    if cookieHeader != "":
      for pair in cookieHeader.split("; "):
        let parts = pair.split("=", 1)
        if parts.len == 2 and parts[0] == session_cookie:
          try:
            # In a real implementation we would verify the signature here
            let decoded = decode(parts[1])
            sessionData = parseJson(decoded)
          except:
            discard

    # We could attach session to req.scope or similar if we had it.
    # For now, let's just pass it through headers or a custom field if we had one.
    # Actually, let's just make it available if we can.

    var res = await next(req)

    # Save session back to cookie (simplified)
    # If session was modified, we'd need a way to know.
    # For now this is just a placeholder implementation of the structure.

    return res
