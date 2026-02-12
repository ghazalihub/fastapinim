import asyncdispatch, sequtils, macros

type
  BackgroundTask* = proc () {.gcsafe.}

  BackgroundTasks* = ref object
    tasks*: seq[BackgroundTask]

proc newBackgroundTasks*(): BackgroundTasks =
  BackgroundTasks(tasks: @[])

proc add_task_proc*(self: BackgroundTasks, task: BackgroundTask) =
  self.tasks.add(task)

macro add_task*(self: BackgroundTasks, task: untyped, args: varargs[untyped]): untyped =
  result = quote do:
    let t = proc () {.gcsafe.} =
      when compiles((let _ = `task`(`args`))):
        let res = `task`(`args`)
        when res is Future:
          waitFor res
      else:
        `task`(`args`)
    `self`.add_task_proc(t)

proc run*(self: BackgroundTasks) {.async.} =
  for task in self.tasks:
    task()
