import json, std/jsonutils, tables, strutils

proc jsonable_encoder*[T](obj: T): JsonNode =
  return toJson(obj)

proc decode_json*[T](node: JsonNode): T =
  var res: T
  fromJson(res, node)
  return res
