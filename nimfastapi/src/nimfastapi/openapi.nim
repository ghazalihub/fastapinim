import json, tables, strutils
import routing

proc generateOpenAPI*(title: string, version: string, routes: seq[Route]): JsonNode {.gcsafe.} =
  var paths = newJObject()

  for route in routes:
    var pathItem = newJObject()
    for httpMethod in route.methods:
      var operation = %* {
        "summary": route.path,
        "responses": {
          "200": {
            "description": "Successful Response"
          }
        }
      }
      # Add parameters
      var parameters = newJArray()
      for p in route.parameters:
        parameters.add(%* {
          "name": p.name,
          "in": p.kind,
          "required": p.kind == "path",
          "schema": { "type": p.typ }
        })

      if parameters.len > 0:
        operation["parameters"] = parameters

      pathItem[httpMethod.toLowerAscii()] = operation

    paths[route.path] = pathItem

  result = %* {
    "openapi": "3.0.0",
    "info": {
      "title": title,
      "version": version
    },
    "paths": paths
  }
