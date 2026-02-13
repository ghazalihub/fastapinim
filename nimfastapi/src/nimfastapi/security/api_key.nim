{.experimental: "callOperator".}
import asyncdispatch, tables, strutils
import ../requests, ../responses, ../exceptions, ../status

type
  APIKeyHeader* = ref object
    name*: string

proc newAPIKeyHeader*(name: string): APIKeyHeader =
  APIKeyHeader(name: name)

proc `()`*(self: APIKeyHeader, req: requests.Request): Future[string] {.async, gcsafe.} =
  let key = req.headers.getHeader(self.name, "")
  if key == "":
    raise newHTTPException(HttpCode(403), "Forbidden")
  return key

type
  APIKeyQuery* = ref object
    name*: string

proc newAPIKeyQuery*(name: string): APIKeyQuery =
  APIKeyQuery(name: name)

proc `()`*(self: APIKeyQuery, req: requests.Request): Future[string] {.async, gcsafe.} =
  let key = req.queryParams.getOrDefault(self.name, "")
  if key == "":
    raise newHTTPException(HttpCode(403), "Forbidden")
  return key
