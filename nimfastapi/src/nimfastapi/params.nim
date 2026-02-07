import json

type
  ParamKind* = enum
    pkQuery, pkPath, pkHeader, pkCookie, pkBody, pkForm, pkFile

  ParamBase* = ref object of RootObj
    kind*: ParamKind
    default*: JsonNode
    alias*: string
    title*: string
    description*: string
    required*: bool

  QueryParam* = ref object of ParamBase
  PathParam* = ref object of ParamBase
  HeaderParam* = ref object of ParamBase
  CookieParam* = ref object of ParamBase
  BodyParam* = ref object of ParamBase
  FormParam* = ref object of ParamBase
  FileParam* = ref object of ParamBase

proc NewQuery*(default: JsonNode = newJNull(), alias: string = "", title: string = "", description: string = "", required: bool = false): QueryParam =
  QueryParam(kind: pkQuery, default: default, alias: alias, title: title, description: description, required: required)

proc NewPath*(alias: string = "", title: string = "", description: string = ""): PathParam =
  PathParam(kind: pkPath, default: newJNull(), alias: alias, title: title, description: description, required: true)

proc NewHeader*(default: JsonNode = newJNull(), alias: string = "", title: string = "", description: string = "", required: bool = false): HeaderParam =
  HeaderParam(kind: pkHeader, default: default, alias: alias, title: title, description: description, required: required)

proc NewCookie*(default: JsonNode = newJNull(), alias: string = "", title: string = "", description: string = "", required: bool = false): CookieParam =
  CookieParam(kind: pkCookie, default: default, alias: alias, title: title, description: description, required: required)

proc NewBody*(default: JsonNode = newJNull(), alias: string = "", title: string = "", description: string = "", required: bool = true, embed: bool = false): BodyParam =
  BodyParam(kind: pkBody, default: default, alias: alias, title: title, description: description, required: required)

proc NewForm*(default: JsonNode = newJNull(), alias: string = "", title: string = "", description: string = "", required: bool = true): FormParam =
  FormParam(kind: pkForm, default: default, alias: alias, title: title, description: description, required: required)

proc NewFile*(default: JsonNode = newJNull(), alias: string = "", title: string = "", description: string = "", required: bool = true): FileParam =
  FileParam(kind: pkFile, default: default, alias: alias, title: title, description: description, required: required)

template Query*(default: untyped = nil): untyped = NewQuery(%default)
template Path*(): untyped = NewPath()
template Header*(default: untyped = nil): untyped = NewHeader(%default)
template Cookie*(default: untyped = nil): untyped = NewCookie(%default)
template Body*(default: untyped = nil): untyped = NewBody(%default)
template Form*(default: untyped = nil): untyped = NewForm(%default)
template File*(default: untyped = nil): untyped = NewFile(%default)
