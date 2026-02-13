import ../requests, ../exceptions, asynchttpserver, strutils, base64, asyncdispatch

type
  HTTPBasicCredentials* = object
    username*: string
    password*: string

proc HTTPBearer*(req: requests.Request): Future[string] {.async, gcsafe.} =
  let auth = req.headers.getHeader("Authorization", "")
  if auth.startsWith("Bearer "):
    return auth[7 .. ^1]
  raise newHTTPException(HttpCode(401), "Not authenticated")

proc HTTPBasic*(req: requests.Request): Future[HTTPBasicCredentials] {.async, gcsafe.} =
  let auth = req.headers.getHeader("Authorization", "")
  if auth.startsWith("Basic "):
    try:
      let decoded = decode(auth[6 .. ^1])
      let parts = decoded.split(':', 1)
      if parts.len == 2:
        return HTTPBasicCredentials(username: parts[0], password: parts[1])
    except:
      discard
  raise newHTTPException(HttpCode(401), "Not authenticated")
