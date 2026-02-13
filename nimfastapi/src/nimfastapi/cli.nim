import os, strutils, parseopt

proc print_help() =
  echo """
Nim FastAPI CLI
Usage:
  nimfastapi run <file.nim> [options]
  nimfastapi new <project_name>

Options:
  --port:8000    Port to run on
  --help         Show this help
"""

proc run_app(filename: string, port: string = "8000") =
  if not fileExists(filename):
    echo "Error: File not found: ", filename
    quit(1)

  echo "Running ", filename, " on port ", port
  let cmd = "nim c -r -d:release --threads:on " & filename
  discard execShellCmd(cmd)

proc create_new_project(name: string) =
  echo "Creating new project: ", name
  createDir(name)
  createDir(name / "routers")
  createDir(name / "models")
  createDir(name / "static")

  writeFile(name / "main.nim", """
import nimfastapi

let app = newFastAPI()

@app.get("/")
proc root(): JsonNode =
  return %*{"message": "Hello World"}

if isMainModule:
  app.run()
""")
  echo "Project created successfully!"

proc main*() =
  var p = initOptParser()
  var command = ""
  var filename = ""
  var port = "8000"

  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdArgument:
      if command == "": command = p.key
      elif filename == "": filename = p.key
    of cmdLongOption, cmdShortOption:
      case p.key
      of "port", "p": port = p.val
      of "help", "h":
        print_help()
        quit(0)

  case command
  of "run":
    run_app(filename, port)
  of "new":
    create_new_project(filename)
  else:
    print_help()

if isMainModule:
  main()
