import asyncdispatch, tables, strutils, options, asynchttpserver
import ../requests, ../responses, ../exceptions, ../dependencies, ../params, ../status

type
  OAuth2PasswordRequestForm* = object
    grant_type*: string
    username*: string
    password*: string
    scope*: seq[string]
    client_id*: string
    client_secret*: string

proc OAuth2PasswordBearer*(tokenUrl: string): proc (req: requests.Request): Future[string] {.async, gcsafe.} =
  return proc (req: requests.Request): Future[string] {.async, gcsafe.} =
    let authHeader = req.headers.getHeader("Authorization", "")
    if not authHeader.startsWith("Bearer "):
      raise newHTTPException(HttpCode(401), "Not authenticated")
    return authHeader[7 .. ^1]

# Dependency to extract OAuth2 form
proc get_oauth2_form*(req: requests.Request): Future[OAuth2PasswordRequestForm] {.async, gcsafe.} =
  let form = req.form()
  var res = OAuth2PasswordRequestForm()
  res.grant_type = form.getOrDefault("grant_type", "")
  res.username = form.getOrDefault("username", "")
  res.password = form.getOrDefault("password", "")
  res.scope = form.getOrDefault("scope", "").split(' ')
  res.client_id = form.getOrDefault("client_id", "")
  res.client_secret = form.getOrDefault("client_secret", "")
  return res
