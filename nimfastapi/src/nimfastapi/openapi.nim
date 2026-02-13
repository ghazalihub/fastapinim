import json, tables, strutils, options
import routing

proc generateOpenAPI*(title: string, version: string, routes: seq[Route], description: string = ""): JsonNode {.gcsafe.} =
  var paths = newJObject()

  for route in routes:
    var pathItem = newJObject()
    for httpMethod in route.methods:
      var operation = %* {
        "responses": {
          "200": {
            "description": "Successful Response"
          }
        }
      }

      if route.summary != "": operation["summary"] = %route.summary
      else: operation["summary"] = %route.path

      if route.description != "": operation["description"] = %route.description
      if route.tags.len > 0: operation["tags"] = %route.tags

      # Add parameters
      var parameters = newJArray()
      for p in route.parameters:
        if p.kind == "body": continue # Body handled differently in OAS3

        var schema = %* { "type": if p.typ == "int": "integer" else: "string" }
        if p.min_length.isSome: schema["minLength"] = %p.min_length.get
        if p.max_length.isSome: schema["maxLength"] = %p.max_length.get
        if p.regex != "": schema["pattern"] = %p.regex
        if p.gt.isSome: schema["exclusiveMinimum"] = %p.gt.get
        if p.ge.isSome: schema["minimum"] = %p.ge.get
        if p.lt.isSome: schema["exclusiveMaximum"] = %p.lt.get
        if p.le.isSome: schema["maximum"] = %p.le.get

        var paramObj = %* {
          "name": p.name,
          "in": p.kind,
          "required": p.required,
          "schema": schema
        }
        if p.description != "": paramObj["description"] = %p.description
        if p.deprecated: paramObj["deprecated"] = %true

        parameters.add(paramObj)

      if parameters.len > 0:
        operation["parameters"] = parameters

      # Handle body
      for p in route.parameters:
        if p.kind == "body":
           operation["requestBody"] = %* {
             "content": {
               "application/json": {
                 "schema": {
                   "type": "object",
                   "title": p.typ
                 }
               }
             }
           }
           break

      pathItem[httpMethod.toLowerAscii()] = operation

    paths[route.path] = pathItem

  result = %* {
    "openapi": "3.0.0",
    "info": {
      "title": title,
      "version": version,
      "description": description
    },
    "paths": paths
  }
