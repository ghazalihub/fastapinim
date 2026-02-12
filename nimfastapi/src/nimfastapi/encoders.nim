import json, std/jsonutils, tables, strutils, options

proc toJsonHook*[T](opt: Option[T]): JsonNode =
  if opt.isSome: return toJson(opt.get)
  else: return newJNull()

proc fromJsonHook*[T](opt: var Option[T], node: JsonNode) =
  if node.kind == JNull:
    opt = none(T)
  else:
    var val: T
    fromJson(val, node)
    opt = some(val)

proc jsonable_encoder*[T](obj: T): JsonNode =
  return toJson(obj)

proc decode_json*[T](node: JsonNode): T =
  var res: T
  fromJson(res, node)
  return res
