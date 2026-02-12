import asyncdispatch, asynchttpserver, strutils, sequtils
import ../requests, ../responses, ../applications

proc TrustedHostMiddleware*(allowed_hosts: seq[string]): MiddlewareHandler =
  return proc (req: requests.Request, next: proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.}): Future[responses.Response] {.async, gcsafe.} =
    let host = req.headers.getHeader("Host", "").split(':')[0]

    var allowed = false
    if allowed_hosts.contains("*"):
      allowed = true
    else:
      for pattern in allowed_hosts:
        if pattern == host:
          allowed = true
          break
        if pattern.startsWith("*.") and host.endsWith(pattern[2 .. ^1]):
          allowed = true
          break

    if not allowed:
      return newResponse("Invalid host header", Http400)

    return await next(req)
