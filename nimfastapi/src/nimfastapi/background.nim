import asyncdispatch, sequtils

type
  BackgroundTask* = proc () {.async, gcsafe.}

  BackgroundTasks* = ref object
    tasks*: seq[BackgroundTask]

proc newBackgroundTasks*(): BackgroundTasks =
  BackgroundTasks(tasks: @[])

proc add_task*(self: BackgroundTasks, task: BackgroundTask) =
  self.tasks.add(task)

proc run*(self: BackgroundTasks) {.async.} =
  for task in self.tasks:
    await task()
