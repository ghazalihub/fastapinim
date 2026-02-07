import macros

macro Depends*(dep: typed): untyped =
  let handlerType = dep.getTypeImpl
  # handlerType[0] is formal params, [0][0] is return type
  let retType = handlerType[0][0]
  result = quote do:
    # Use a dummy value of the right type
    var d: `retType`
    d
