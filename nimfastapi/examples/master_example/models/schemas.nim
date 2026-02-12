import options

type
  Item* = object
    id*: int
    title*: string
    description*: Option[string]
    price*: float
    tax*: Option[float] = none(float)

  User* = object
    username*: string
    full_name*: Option[string] = none(string)
    email*: Option[string] = none(string)
    disabled*: Option[bool] = some(false)
