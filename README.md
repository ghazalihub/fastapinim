# NimFastAPI

A completely complete FastAPI clone in Nim. Powerful, fast, and productive.

NimFastAPI brings the productivity and ease of use of Python's FastAPI to the performance world of Nim. It uses macro-based metaprogramming to provide automatic parameter validation, dependency injection, and OpenAPI generation.

## Features

- **Fast**: High performance thanks to Nim's compiled nature and `asyncdispatch`.
- **Easy to use**: Intuitive API inspired by FastAPI.
- **Automatic Docs**: Integrated Swagger UI and ReDoc.
- **Dependency Injection**: Robust and recursive DI system with `Depends()`.
- **Validation**: Runtime validation for parameters (min/max length, regex, gt/lt/ge/le).
- **Security**: Built-in support for JWT, OAuth2 Password Flow, API Keys, and Basic/Bearer Auth.
- **WebSockets**: Native WebSocket support.
- **Middleware**: CORS, GZip, Sessions, and more.
- **Background Tasks**: Execute logic after returning a response.
- **Static Files**: Serve directories easily.
- **CLI**: Scaffolding and running tools.

## Installation

```bash
nimble install nimfastapi
```

## Quickstart

Create a file `main.nim`:

```nim
import nimfastapi

let app = newFastAPI()

@app.get("/")
proc root(): JsonNode =
  return %*{"message": "Hello World"}

@app.get("/items/{item_id}")
proc read_item(item_id: int = Path(), q: string = Query(default_val = "none")): JsonNode =
  return %*{"item_id": item_id, "q": q}

if isMainModule:
  app.run(port = 8000)
```

Run it:
```bash
nim c -r main.nim
```
Visit `http://localhost:8000/docs` for the Swagger UI.

## Parameter Validation

NimFastAPI supports powerful validation using `Query`, `Path`, `Body`, `Header`, `Cookie`, `Form`, and `File`.

```nim
@app.get("/search")
proc search(
  q: string = Query(min_length = 3, regex = "^foo"),
  limit: int = Query(default_val = 10, gt = 0, le = 100)
): JsonNode =
  return %*{"q": q, "limit": limit}
```

## Dependency Injection

Use `Depends()` to inject shared logic into your handlers. Dependencies can be nested!

```nim
proc get_query(q: string = "default"): string =
  return q

proc get_user(token: string = Depends(HTTPBearer)): string =
  # Validate token here
  return "user_from_token"

@app.get("/items")
proc read_items(q: string = Depends(get_query), user: string = Depends(get_user)): JsonNode =
  return %*{"q": q, "user": user}
```

## Security with JWT

```nim
const SECRET_KEY = "your-secret-key"

@app.post("/login")
proc login(form: OAuth2PasswordRequestForm = Depends(get_oauth2_form)): JsonNode =
  if form.username == "admin" and form.password == "secret":
    let token = create_access_token(%*{"sub": form.username}, JWTConfig(secret: SECRET_KEY, algorithm: HS256, expire_minutes: 30))
    return %*{"access_token": token, "token_type": "bearer"}
  else:
    raise newHTTPException(HttpCode(401), "Unauthorized")

@app.get("/users/me")
proc me(user: JsonNode = Depends(JWTBearer(SECRET_KEY))): JsonNode =
  return user
```

## Routers and Modularization

```nim
# in items_router.nim
let router* = newAPIRouter(prefix = "/items", tags = @["items"])
@router.get("/")
proc list_items(): seq[Item] = @[]

# in main.nim
app.include_router(items_router.router)
```

## CLI

```bash
# Create a new project
nimfastapi new my_project

# Run an app
nimfastapi run main.nim --port:8080
```

## Documentation

For full API documentation, please refer to the `examples/` directory and the auto-generated Swagger UI in any running app.
