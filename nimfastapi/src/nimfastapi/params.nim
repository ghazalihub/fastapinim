type
  Param* = ref object of RootObj
    default*: string # Simplified, using string for now

  Query* = ref object of Param
  Path* = ref object of Param
  Body* = ref object of Param

proc NewQuery*(default: string = ""): Query = Query(default: default)
proc NewPath*(): Path = Path()
proc NewBody*(default: string = ""): Body = Body(default: default)
