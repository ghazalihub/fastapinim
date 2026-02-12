import asynchttpserver

# Re-export statuses from asynchttpserver and add some common ones if missing
export asynchttpserver.HttpCode

const
  Http100* = HttpCode(100)
  Http101* = HttpCode(101)
  Http200* = HttpCode(200)
  Http201* = HttpCode(201)
  Http202* = HttpCode(202)
  Http204* = HttpCode(204)
  Http301* = HttpCode(301)
  Http302* = HttpCode(302)
  Http304* = HttpCode(304)
  Http307* = HttpCode(307)
  Http308* = HttpCode(308)
  Http400* = HttpCode(400)
  Http401* = HttpCode(401)
  Http403* = HttpCode(403)
  Http404* = HttpCode(404)
  Http405* = HttpCode(405)
  Http422* = HttpCode(422)
  Http500* = HttpCode(500)
