import os, strutils, tables, json, asynchttpserver
import requests, responses

type
  NimTemplates* = ref object
    directory*: string

proc newNimTemplates*(directory: string): NimTemplates =
  NimTemplates(directory: directory)

proc TemplateResponse*(self: NimTemplates, name: string, context: Table[string, string]): responses.Response =
  let path = self.directory / name
  if not fileExists(path):
    return newResponse("Template not found", Http404)

  var content = readFile(path)
  for k, v in context:
    content = content.replace("{{" & k & "}}", v)

  return newResponse(content, Http200, newHttpHeaders({"Content-Type": "text/html"}))

proc TemplateResponse*(self: NimTemplates, name: string, context: JsonNode): responses.Response =
  var ctx = initTable[string, string]()
  if context.kind == JObject:
    for k, v in context:
      if v.kind == JString: ctx[k] = v.getStr()
      else: ctx[k] = $v
  return self.TemplateResponse(name, ctx)
