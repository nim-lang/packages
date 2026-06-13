import std/json
import std/os
import std/osproc
import std/strtabs
import std/strutils

proc rootDir*(): string =
  currentSourcePath.parentDir.parentDir

proc tempDir*(name: string): string =
  let path = getTempDir() / name
  if dirExists(path):
    removeDir(path)
  createDir(path)
  path

proc mergedEnv(env: openArray[(string, string)]): StringTableRef =
  result = newStringTable()
  for pair in envPairs():
    result[pair[0]] = pair[1]
  for pair in env:
    let (key, value) = pair
    result[key] = value

proc runOk*(cmd: string, workdir: string, env: openArray[(string, string)] = []) =
  let cmdResult = execCmdEx(cmd, workingDir = workdir, env = mergedEnv(env))
  doAssert cmdResult.exitCode == 0,
    "command failed: " & cmd & "\nstdout+stderr:\n" & cmdResult.output

proc runFails*(cmd: string, workdir: string, env: openArray[(string, string)] = []): string =
  let cmdResult = execCmdEx(cmd, workingDir = workdir, env = mergedEnv(env))
  doAssert cmdResult.exitCode != 0, "command unexpectedly succeeded: " & cmd
  cmdResult.output

proc commandOutput*(cmd: string, workdir: string, env: openArray[(string, string)] = []): string =
  let cmdResult = execCmdEx(cmd, workingDir = workdir, env = mergedEnv(env))
  doAssert cmdResult.exitCode == 0,
    "command failed: " & cmd & "\nstdout+stderr:\n" & cmdResult.output
  cmdResult.output.strip()

proc writeJsonFile*(path: string, node: JsonNode) =
  createDir(path.parentDir)
  writeFile(path, pretty(node) & "\n")

proc packageNode*(name: string, description = ""): JsonNode =
  %*{
    "name": name,
    "url": "https://example.com/" & name.toLowerAscii(),
    "method": "git",
    "tags": ["demo"],
    "description": (if description.len > 0: description else: name & " package"),
    "license": "MIT"
  }

proc git*(args: openArray[string], workdir: string, env: openArray[(string, string)] = []) =
  var quoted: seq[string]
  for arg in args:
    quoted.add(quoteShell(arg))
  runOk("git " & quoted.join(" "), workdir, env)
