import asyncdispatch, asynchttpserver, strutils, zippy
import ../requests, ../responses, ../applications

proc GZipMiddleware*(minimum_size: int = 500): MiddlewareHandler =
  return proc (req: requests.Request, next: proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.}): Future[responses.Response] {.async, gcsafe.} =
    var res = await next(req)

    let acceptEncoding = req.headers.getHeader("Accept-Encoding", "")
    if acceptEncoding.contains("gzip") and res.body.len >= minimum_size and not res.headers.hasKey("Content-Encoding"):
      res.body = compress(res.body, DefaultCompression, dfGzip)
      res.headers["Content-Encoding"] = "gzip"
      res.headers["Content-Length"] = $res.body.len

    return res
