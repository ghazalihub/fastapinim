import asyncdispatch, asyncnet, ws, asynchttpserver, tables
import requests

type
  WebSocket* = ref object
    ws*: ws.WebSocket
    req*: requests.Request

proc newWebSocket*(ws: ws.WebSocket, req: requests.Request): WebSocket =
  WebSocket(ws: ws, req: req)

proc sendText*(self: WebSocket, data: string) {.async.} =
  await self.ws.send(data)

proc receiveText*(self: WebSocket): Future[string] {.async.} =
  return await self.ws.receiveStrPacket()

proc close*(self: WebSocket) {.async.} =
  self.ws.close()

type
  WebSocketHandler* = proc (ws: WebSocket): Future[void] {.gcsafe.}
