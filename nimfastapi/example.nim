import nimfastapi, json, asyncdispatch, tables, os, asynchttpserver, httpcore, times

let app = newFastAPI(title = "Comprehensive NimFastAPI")

# 1. Middleware
app.add_middleware(proc (req: requests.Request, next: proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.}): Future[responses.Response] {.async, gcsafe.} =
  echo "DEBUG: Middleware start"
  let start = cpuTime()
  var resp = await next(req)
  let duration = cpuTime() - start
  resp.headers.add("X-Process-Time", $duration)
  echo "DEBUG: Middleware end"
  return resp
)

# 2. Dependency
proc get_query_token(token: string = ""): string =
  if token != "jessica":
    echo "Warning: Invalid token"
  return token

# 3. Routes
proc readRoot(): string =
  return "Hello World"

app.get("/", readRoot)

proc readItem(item_id: int, q: string = ""): JsonNode =
  return %*{"item_id": item_id, "q": q}

app.get("/items/{item_id}", readItem)

proc readUser(user_id: string, token: string = Depends(get_query_token)): JsonNode =
  return %*{"user_id": user_id, "token": token}

app.get("/users/{user_id}", readUser)

# 4. Background Tasks
proc some_background_task() {.async.} =
  echo "Background task started..."
  await sleepAsync(1000)
  echo "Background task finished!"

proc testBackground(bt: BackgroundTasks): string =
  bt.add_task(some_background_task)
  return "Background task scheduled"

app.get("/background", testBackground)

if paramCount() > 0 and paramStr(1) == "run":
  app.run(8001)
else:
  echo "Setup complete. Run with 'run' argument to start server."
