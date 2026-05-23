import std/algorithm
import std/json
import std/os
import std/parseopt
import std/strutils

const Usage = """
Usage: combine_packages [pkgs-dir] [packages.json]

Combine sharded package folders back into a single packages.json array.

Arguments:
  pkgs-dir       Input shard directory. Default: pkgs
  packages.json  Output manifest path. Default: packages.json
"""

proc cleanupWhitespace(s: string): string =
  ## Removes trailing whitespace and normalizes line endings to LF.
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    if s[i] == ' ':
      var j = i + 1
      while j < s.len and s[j] == ' ':
        inc j
      if j < s.len and s[j] == '\c':
        inc j
        if j < s.len and s[j] == '\L':
          inc j
        result.add '\L'
        i = j
      elif j < s.len and s[j] == '\L':
        result.add '\L'
        i = j + 1
      else:
        result.add ' '
        inc i
    elif s[i] == '\c':
      inc i
      if i < s.len and s[i] == '\L':
        inc i
      result.add '\L'
    elif s[i] == '\L':
      result.add '\L'
      inc i
    else:
      result.add s[i]
      inc i

  if result.len == 0 or result[^1] != '\L':
    result.add '\L'

proc die(message: string) {.noreturn.} =
  stderr.writeLine("error: " & message)
  quit(1)

proc firstShardLetter(name: string): char =
  if name.len == 0:
    die("package metadata missing name")
  result = name[0].toLowerAscii()
  if result notin {'a'..'z'}:
    die("package name must start with an ASCII letter for alphabetical sharding: " & name)

proc packageName(node: JsonNode, pathForErrors: string): string =
  if node.kind != JObject:
    die("package metadata is not a JSON object: " & pathForErrors)
  if not node.hasKey("name") or node["name"].kind != JString or node["name"].getStr() == "":
    die("package metadata missing name: " & pathForErrors)
  result = node["name"].getStr()

proc comparePackages(a, b: JsonNode): int =
  let aName = packageName(a, "<in-memory>").toLowerAscii()
  let bName = packageName(b, "<in-memory>").toLowerAscii()
  result = cmp(aName, bName)
  if result == 0:
    result = cmp(packageName(a, "<in-memory>"), packageName(b, "<in-memory>"))

proc collectPackageFiles(inputRoot: string): seq[string] =
  for path in walkDirRec(inputRoot):
    if path.extractFilename() == "package.json":
      result.add(path)

proc combinePackages(inputRoot, outputPath: string) =
  if not dirExists(inputRoot):
    die("shard directory not found: " & inputRoot)

  var packages: seq[JsonNode]
  for metadataPath in collectPackageFiles(inputRoot):
    let relative = relativePath(metadataPath, inputRoot).replace('\\', '/')
    let parts = relative.split('/')
    if parts.len != 3:
      die("unexpected shard path layout: " & metadataPath)

    let shardFromPath = parts[0]
    let packageDirFromPath = parts[1]
    if parts[2] != "package.json":
      die("unexpected shard filename: " & metadataPath)

    let pkg = parseFile(metadataPath)
    let name = packageName(pkg, metadataPath)
    let expectedShard = $firstShardLetter(name)

    if packageDirFromPath != name:
      die("package path does not match .name for " & metadataPath)
    if shardFromPath != expectedShard:
      die("shard path does not match first letter for " & metadataPath)

    packages.add(pkg)

  if packages.len == 0:
    die("no package metadata files found under " & inputRoot)

  packages.sort(comparePackages)

  let outputJson = %packages
  let tmpPath = outputPath & ".tmp"
  writeFile(tmpPath, outputJson.pretty.cleanupWhitespace)
  moveFile(tmpPath, outputPath)
  echo "Wrote ", packages.len, " packages into ", outputPath

proc cliMain(): int =
  var parser = initOptParser(commandLineParams())
  var positional: seq[string]

  while true:
    parser.next()
    case parser.kind
    of cmdEnd:
      break
    of cmdShortOption, cmdLongOption:
      if parser.key in ["help", "h"]:
        stdout.write(Usage)
        return 0
      else:
        stderr.writeLine("error: unknown option: --" & parser.key)
        stderr.write(Usage)
        return 1
    of cmdArgument:
      positional.add(parser.key)

  if positional.len > 2:
    stderr.writeLine("error: too many arguments")
    stderr.write(Usage)
    return 1

  let inputRoot = if positional.len >= 1: positional[0] else: "pkgs"
  let outputPath = if positional.len >= 2: positional[1] else: "packages.json"
  combinePackages(inputRoot, outputPath)
  return 0

when isMainModule:
  quit(cliMain())
