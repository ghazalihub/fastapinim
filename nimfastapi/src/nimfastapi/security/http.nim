import ../requests, ../exceptions, asynchttpserver, strutils, base64

type
  HTTPBase* = ref object of RootObj
    scheme*: string

  HTTPBearer* = ref object of HTTPBase
  HTTPBasic* = ref object of HTTPBase

proc newHTTPBearer*(): HTTPBearer =
  HTTPBearer(scheme: "bearer")

proc newHTTPBasic*(): HTTPBasic =
  HTTPBasic(scheme: "basic")

proc get_token*(self: HTTPBearer, req: requests.Request): string =
  let auth = req.httpReq.headers.getOrDefault("Authorization")
  if auth.startsWith("Bearer "):
    return auth[7 .. ^1]
  return ""

proc get_credentials*(self: HTTPBasic, req: requests.Request): tuple[user, password: string] =
  let auth = req.httpReq.headers.getOrDefault("Authorization")
  if auth.startsWith("Basic "):
    try:
      let decoded = decode(auth[6 .. ^1])
      let parts = decoded.split(':', 1)
      if parts.len == 2:
        return (parts[0], parts[1])
    except:
      discard
  return ("", "")
