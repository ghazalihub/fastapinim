import asynchttpserver, tables, json, strutils, uri, multipart, os

type
  UploadFile* = ref object
    filename*: string
    content_type*: string
    body*: string

  Request* = ref object
    httpReq*: asynchttpserver.Request
    pathParams*: Table[string, string]
    queryParams*: Table[string, string]
    headers*: HttpHeaders
    root_path*: string # The path where the app was mounted

proc getHeader*(headers: HttpHeaders, key: string, default: string = ""): string =
  if headers.hasKey(key):
    return headers[key]
  return default

proc newRequest*(req: asynchttpserver.Request): Request =
  var queryParams = initTable[string, string]()

  if req.url.query != "":
    for pair in req.url.query.split('&'):
      let parts = pair.split('=')
      if parts.len == 2:
        queryParams[decodeUrl(parts[0])] = decodeUrl(parts[1])

  Request(
    httpReq: req,
    pathParams: initTable[string, string](),
    queryParams: queryParams,
    headers: req.headers,
    root_path: ""
  )

proc body*(self: Request): string =
  self.httpReq.body

proc json*(self: Request): JsonNode =
  if self.body == "": return newJObject()
  parseJson(self.body)

proc form*(self: Request): Table[string, string] {.gcsafe.} =
  var res = initTable[string, string]()
  let contentType = self.headers.getHeader("Content-Type")

  if contentType.startsWith("application/x-www-form-urlencoded"):
    if self.body != "":
      for pair in self.body.split('&'):
        let parts = pair.split('=')
        if parts.len == 2:
          res[decodeUrl(parts[0])] = decodeUrl(parts[1])
  elif contentType.startsWith("multipart/form-data"):
    var mp = initMultipart(contentType)
    {.cast(gcsafe).}:
      mp.parse(self.body)
      for entry in mp:
        if entry.dataType == MultipartText:
          res[entry.fieldName] = entry.value
  return res

proc files*(self: Request): Table[string, UploadFile] {.gcsafe.} =
  var res = initTable[string, UploadFile]()
  let contentType = self.headers.getHeader("Content-Type")
  if contentType.startsWith("multipart/form-data"):
    var mp = initMultipart(contentType)
    {.cast(gcsafe).}:
      mp.parse(self.body)
      for entry in mp:
        if entry.dataType == MultipartFile:
          res[entry.fieldName] = UploadFile(
            filename: entry.fileName,
            content_type: entry.fileType,
            body: readFile(entry.filePath)
          )
  return res

proc httpMethod*(self: Request): string =
  $self.httpReq.reqMethod
