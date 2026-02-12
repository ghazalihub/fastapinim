import os, strutils

type
  BaseSettings* = object of RootObj

proc loadFromEnv*[T](obj: var T) =
  ## Automatically loads environment variables into fields of an object.
  ## Field names are converted to uppercase for environment variable lookup.
  for name, value in fieldPairs(obj):
    let envVal = getEnv(name.toUpperAscii())
    if envVal != "":
      when value is string:
        value = envVal
      elif value is int:
        value = parseInt(envVal)
      elif value is bool:
        value = envVal.toLowerAscii() in ["true", "1", "yes", "on"]
      elif value is float:
        value = parseFloat(envVal)
      elif value is seq[string]:
        value = envVal.split(',')
