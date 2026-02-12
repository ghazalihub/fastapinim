import nimfastapi, asyncdispatch, json
import routers/items as items_router
import routers/users as users_router
import nimfastapi/staticfiles

let app = newFastAPI(
    title = "Master Example",
    description = "A structured example project showcasing all features",
    version = "1.0.0"
)

# Global Middleware
proc log_middleware(req: Request, next: proc (req: Request): Future[Response] {.async, gcsafe.}): Future[Response] {.async, gcsafe.} =
  echo "Incoming request: ", req.httpMethod, " ", req.httpReq.url.path
  let res = await next(req)
  echo "Response status: ", res.status.int
  return res

app.add_middleware(log_middleware)

# Events
app.add_event_handler("startup", proc () {.async.} =
  echo "Application is starting up..."
)

app.add_event_handler("shutdown", proc () {.async.} =
  echo "Application is shutting down..."
)

# Routes
app.get("/"):
  proc root(): JsonNode =
    return %*{"message": "Welcome to the Master Example"}

# Include Routers
items_router.router.prefix = "/items"
app.include_router(items_router.router)

users_router.router.prefix = "/users"
app.include_router(users_router.router)

# WebSockets
app.websocket("/ws"):
  proc websocket_endpoint(ws: WebSocket) {.async.} =
    echo "WS Connected"
    try:
      while true:
        let data = await ws.receiveText()
        if data == "": break
        echo "WS Received: ", data
        await ws.sendText("Echo: " & data)
    except:
      discard
    echo "WS Disconnected"

# Static Files
app.mount("/static", StaticFiles("master_example/static"))

if isMainModule:
  app.run(port = 8000)
