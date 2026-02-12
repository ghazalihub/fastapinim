import json, options, macros, requests

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
    gt*: Option[float]
    ge*: Option[float]
    lt*: Option[float]
    le*: Option[float]
    min_length*: Option[int]
    max_length*: Option[int]
    regex*: string
    example*: JsonNode
    deprecated*: bool
    include_in_schema*: bool = true

  QueryParam* = ref object of ParamBase
  PathParam* = ref object of ParamBase
  HeaderParam* = ref object of ParamBase
  CookieParam* = ref object of ParamBase
  BodyParam* = ref object of ParamBase
  FormParam* = ref object of ParamBase
  FileParam* = ref object of ParamBase

# Converters to allow using markers as default values
converter toString*(p: ParamBase): string = ""
converter toInt*(p: ParamBase): int = 0
converter toFloat*(p: ParamBase): float = 0.0
converter toBool*(p: ParamBase): bool = false
converter toJson*(p: ParamBase): JsonNode = newJNull()
converter toUploadFile*(p: ParamBase): UploadFile = nil

proc NewQuery*(
    default: JsonNode = newJNull(),
    alias: string = "",
    title: string = "",
    description: string = "",
    required: bool = false,
    gt: Option[float] = none(float),
    ge: Option[float] = none(float),
    lt: Option[float] = none(float),
    le: Option[float] = none(float),
    min_length: Option[int] = none(int),
    max_length: Option[int] = none(int),
    regex: string = "",
    example: JsonNode = newJNull(),
    deprecated: bool = false,
    include_in_schema: bool = true
): QueryParam =
  QueryParam(
    kind: pkQuery, default: default, alias: alias, title: title,
    description: description, required: required, gt: gt, ge: ge,
    lt: lt, le: le, min_length: min_length, max_length: max_length,
    regex: regex, example: example, deprecated: deprecated,
    include_in_schema: include_in_schema
  )

# Use templates that return the actual NewQuery call
template Query*(
    default_val: untyped = nil,
    alias: string = "",
    title: string = "",
    description: string = "",
    required: bool = false,
    min_length: int = -1,
    max_length: int = -1,
    regex: string = ""
): untyped =
  NewQuery(
    %default_val, alias, title, description, required,
    min_length = (if min_length == -1: none(int) else: some(min_length)),
    max_length = (if max_length == -1: none(int) else: some(max_length)),
    regex = regex
  )

# ... add others similarly
proc NewPath*(
    alias: string = "",
    title: string = "",
    description: string = ""
): PathParam =
  PathParam(kind: pkPath, alias: alias, title: title, description: description, required: true)

template Path*(
    alias: string = "",
    title: string = "",
    description: string = ""
): untyped =
  NewPath(alias, title, description)

proc NewBody*(
    default: JsonNode = newJNull(),
    alias: string = "",
    title: string = "",
    description: string = "",
    required: bool = true
): BodyParam =
  BodyParam(kind: pkBody, default: default, alias: alias, title: title, description: description, required: required)

template Body*(
    default_val: untyped = nil,
    alias: string = "",
    title: string = "",
    description: string = "",
    required: bool = true,
    embed: bool = false
): untyped =
  NewBody(%default_val, alias, title, description, required)

proc NewHeader*(
    default: JsonNode = newJNull(),
    alias: string = "",
    title: string = "",
    description: string = "",
    required: bool = true
): HeaderParam =
  HeaderParam(kind: pkHeader, default: default, alias: alias, title: title, description: description, required: required)

template Header*(
    default_val: untyped = nil,
    alias: string = "",
    title: string = "",
    description: string = "",
    required: bool = true
): untyped =
  NewHeader(%default_val, alias, title, description, required)

proc NewCookie*(
    default: JsonNode = newJNull(),
    alias: string = "",
    title: string = "",
    description: string = "",
    required: bool = true
): CookieParam =
  CookieParam(kind: pkCookie, default: default, alias: alias, title: title, description: description, required: required)

template Cookie*(
    default_val: untyped = nil,
    alias: string = "",
    title: string = "",
    description: string = "",
    required: bool = true
): untyped =
  NewCookie(%default_val, alias, title, description, required)

proc NewForm*(
    default: JsonNode = newJNull(),
    alias: string = "",
    title: string = "",
    description: string = "",
    required: bool = true
): FormParam =
  FormParam(kind: pkForm, default: default, alias: alias, title: title, description: description, required: required)

template Form*(
    default_val: untyped = nil,
    alias: string = "",
    title: string = "",
    description: string = "",
    required: bool = true
): untyped =
  NewForm(%default_val, alias, title, description, required)

proc NewFile*(
    default: JsonNode = newJNull(),
    alias: string = "",
    title: string = "",
    description: string = "",
    required: bool = true
): FileParam =
  FileParam(kind: pkFile, default: default, alias: alias, title: title, description: description, required: required)

template File*(
    default_val: untyped = nil,
    alias: string = "",
    title: string = "",
    description: string = "",
    required: bool = true
): untyped =
  NewFile(%default_val, alias, title, description, required)
