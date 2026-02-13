import asynchttpserver, asyncdispatch, requests

type
  DependencyHandler* = proc (req: requests.Request): Future[void] {.async, gcsafe.}

  DependencyMarker* = object
    handler*: DependencyHandler

template Depends*(d: untyped): DependencyMarker =
  ## Marker for dependency injection.
  ## The macro will replace this call with the actual dependency resolution logic
  ## for parameters. For global/decorator dependencies, it captures the handler.
  block:
    let marker = DependencyMarker(handler: proc (req: requests.Request): Future[void] {.async, gcsafe.} =
      when compiles(d(req)):
        discard await d(req)
      else:
        discard await d()
    )
    marker

converter toAny*[T](m: DependencyMarker): T =
  ## Allows `Depends()` to be used as a default value for any type in proc signatures.
  default(T)

converter toString*(m: DependencyMarker): string = ""
converter toInt*(m: DependencyMarker): int = 0
converter toFloat*(m: DependencyMarker): float = 0.0
converter toBool*(m: DependencyMarker): bool = false
