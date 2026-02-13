import nimfastapi, json, asyncdispatch, options
import ../models/schemas

let router* = newAPIRouter()

# Simple JWT secret for demo
const SECRET_KEY = "super-secret-key"

router.post("/login"):
  proc login(form: OAuth2PasswordRequestForm = Depends(get_oauth2_form)): JsonNode =
    if form.username == "admin" and form.password == "secret":
      let access_token = create_access_token(%*{"sub": form.username}, JWTConfig(secret: SECRET_KEY, algorithm: HS256, expire_minutes: 30))
      return %*{"access_token": access_token, "token_type": "bearer"}
    else:
      raise newHTTPException(HttpCode(401), "Incorrect username or password")

router.get("/me"):
  proc read_users_me(current_user: JsonNode = Depends(JWTBearer(SECRET_KEY))): JsonNode =
    return current_user
