import asynchttpserver, tables, json

type
  HTTPException* = ref object of CatchableError
    status_code*: HttpCode
    detail*: JsonNode
    headers*: HttpHeaders

proc newHTTPException*(status_code: HttpCode, detail: string, headers: HttpHeaders = newHttpHeaders()): HTTPException =
  result = HTTPException(status_code: status_code, detail: %detail, headers: headers)
  result.msg = detail

proc newHTTPException*(status_code: HttpCode, detail: JsonNode, headers: HttpHeaders = newHttpHeaders()): HTTPException =
  result = HTTPException(status_code: status_code, detail: detail, headers: headers)
  result.msg = $detail

type
  RequestValidationError* = ref object of HTTPException
    errors*: JsonNode

proc newRequestValidationError*(errors: JsonNode): RequestValidationError =
  RequestValidationError(
    status_code: Http422,
    detail: errors,
    errors: errors,
    headers: newHttpHeaders()
  )
