import asyncdispatch, os, mimetypes, strutils, asynchttpserver
import requests, responses, applications, routing

proc StaticFiles*(directory: string, html: bool = false): FastAPI =
  let app = newFastAPI()
  let m = newMimetypes()
  let absoluteDir = absolutePath(directory)

  app.router.routes.add(Route(
    path: "/",
    isMount: true,
    handler: proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.} =
      let fullPath = req.httpReq.url.path
      var relPath = fullPath
      if relPath.startsWith(req.root_path):
        relPath = relPath[req.root_path.len .. ^1]

      let filePath = absolutePath(absoluteDir / relPath.strip(chars={'/'}))

      # Path Traversal Protection
      if not filePath.startsWith(absoluteDir):
        return newResponse("Forbidden", Http403)

      if fileExists(filePath):
        let content = readFile(filePath)
        let ext = splitFile(filePath).ext.strip(chars={'.'})
        let contentType = m.getMimetype(ext, "application/octet-stream")
        return newResponse(content, Http200, newHttpHeaders({"Content-Type": contentType}))
      elif html and fileExists(filePath / "index.html"):
        let content = readFile(filePath / "index.html")
        return newResponse(content, Http200, newHttpHeaders({"Content-Type": "text/html"}))
      else:
        return newResponse("Not Found", Http404)
  ))
  return app
