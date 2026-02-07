type
  DependencyWrapper*[T] = object
    dep*: proc

template Depends*[T](d: proc): T =
  # This will be seen as a call to a template
  var res: T
  res
