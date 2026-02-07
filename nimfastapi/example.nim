import nimfastapi, json, asyncdispatch, tables, os, asynchttpserver, httpcore, times

# 1. Models
type
  Item = object
    name: string
    price: float
    is_offer: bool

# 2. Security
let api_key_header = newAPIKeyHeader("X-API-Key")

proc get_api_key(req: requests.Request): string =
  let key = api_key_header.get_key(req)
  if key != "secret-token":
    raise newHTTPException(Http403, "Invalid API Key")
  return key

# 3. Application
let app = newFastAPI(title = "Completely Complete NimFastAPI")

# 4. Middleware
app.add_middleware(proc (req: requests.Request, next: proc (req: requests.Request): Future[responses.Response] {.async, gcsafe.}): Future[responses.Response] {.async, gcsafe.} =
  echo "Processing: ", req.httpMethod, " ", req.httpReq.url.path
  let start = cpuTime()
  let resp = await next(req)
  echo "Took: ", cpuTime() - start
  return resp
)

# 5. Routes
proc welcome(): string =
  return "Welcome to NimFastAPI"

app.get("/", welcome)

# Automatic object decoding from JSON body
proc create_item(item: Item): JsonNode =
  return %*{"received_item": item, "status": "created"}

app.post("/items", create_item)

# Dependency Injection + Path Parameters
proc read_user(user_id: int, api_key: string = Depends[string](get_api_key)): JsonNode =
  return %*{"user_id": user_id, "authorized_by": api_key}

app.get("/users/{user_id}", read_user)

# Exceptions
proc teapot(): string =
  raise newHTTPException(Http418, "I am a teapot")

app.get("/error", teapot)

# Background Tasks
proc notify(email: string) {.async.} =
  echo "Sending notification to ", email
  await sleepAsync(500)
  echo "Notification sent!"

proc schedule_notification(email: string, bt: BackgroundTasks): string =
  bt.add_task(proc () {.async.} = await notify(email))
  return "Notification scheduled"

app.post("/send-notification/{email}", schedule_notification)

if paramCount() > 0 and paramStr(1) == "run":
  app.run(8001)
else:
  echo "Setup complete. Run with 'run' argument to start server."
