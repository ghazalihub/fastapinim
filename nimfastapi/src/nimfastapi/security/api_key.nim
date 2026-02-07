import ../requests, ../exceptions, asynchttpserver, tables, strutils

type
  APIKeyIn* = enum
    apiKeyInQuery, apiKeyInHeader, apiKeyInCookie

  APIKey* = ref object of RootObj
    name*: string
    location*: APIKeyIn

proc newAPIKeyQuery*(name: string): APIKey =
  APIKey(name: name, location: apiKeyInQuery)

proc newAPIKeyHeader*(name: string): APIKey =
  APIKey(name: name, location: apiKeyInHeader)

proc newAPIKeyCookie*(name: string): APIKey =
  APIKey(name: name, location: apiKeyInCookie)

proc get_key*(self: APIKey, req: requests.Request): string =
  case self.location
  of apiKeyInQuery:
    return req.queryParams.getOrDefault(self.name, "")
  of apiKeyInHeader:
    return req.httpReq.headers.getOrDefault(self.name)
  of apiKeyInCookie:
    return ""
