import jwt, times, json, asyncdispatch, options, tables, strutils
import ../requests, ../exceptions, ../status

export jwt # Export SignatureAlgorithm and others

type
  JWTConfig* = object
    secret*: string
    algorithm*: SignatureAlgorithm # e.g. HS256
    expire_minutes*: int

proc create_access_token*(data: JsonNode, config: JWTConfig): string =
  var claims = toClaims(data)
  claims["exp"] = newEXP(toInt(epochTime()) + config.expire_minutes * 60)
  var token = initJWT(%*{"alg": $config.algorithm, "typ": "JWT"}, claims)
  token.sign(config.secret)
  return $token

proc verify_token*(tokenStr: string, secret: string, algorithm: SignatureAlgorithm = HS256): Option[JsonNode] =
  try:
    let t = toJWT(tokenStr)
    if t.verify(secret, algorithm):
      t.verifyTimeClaims()
      # Convert claims back to JsonNode
      var res = newJObject()
      for k, v in t.claims:
        res[k] = %v
      return some(res)
    else:
      return none(JsonNode)
  except:
    return none(JsonNode)

proc JWTBearer*(secret: string, algorithm: SignatureAlgorithm = HS256): proc (req: requests.Request): Future[JsonNode] {.async, gcsafe.} =
  return proc (req: requests.Request): Future[JsonNode] {.async, gcsafe.} =
    let authHeader = req.headers.getHeader("Authorization", "")
    if not authHeader.startsWith("Bearer "):
      raise newHTTPException(HttpCode(401), "Not authenticated")
    let tokenStr = authHeader[7 .. ^1]
    let payload = verify_token(tokenStr, secret, algorithm)
    if payload.isNone:
      raise newHTTPException(HttpCode(401), "Invalid or expired token")
    return payload.get
