import asyncdispatch, asynchttpserver, strutils
import ../requests, ../responses, ../applications

proc HTTPSRedirectMiddleware*(): MiddlewareHandler =
  return proc (req: requests.Request, next: proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.}): Future[responses.Response] {.async, gcsafe.} =
    # In a real scenario we'd check if the request is secure.
    # asynchttpserver doesn't easily tell us this if we're behind a proxy.
    # Usually we check X-Forwarded-Proto.
    let proto = req.headers.getHeader("X-Forwarded-Proto", "http")

    if proto == "http":
      let host = req.headers.getHeader("Host", "")
      let url = "https://" & host & req.httpReq.url.path
      var headers = newHttpHeaders()
      headers.add("Location", url)
      return newResponse("", Http307, headers)

    return await next(req)
