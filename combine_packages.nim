import std/algorithm
import std/json
import std/os
import std/parseopt
import std/strutils

const Usage = """
Usage:
  combine_packages [pkgs-dir] [packages.json]

Combine sharded package files back into packages.json.

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

proc replaceFile(sourcePath, destinationPath: string) =
  if fileExists(destinationPath):
    removeFile(destinationPath)
  moveFile(sourcePath, destinationPath)

proc firstShardLetter(name: string): char =
  if name.len == 0:
    die("package metadata missing name")
  result = name[0].toLowerAscii()
  if result notin {'a'..'z'}:
    die("package name must start with an ASCII letter for alphabetical sharding: " & name)

proc requireStringField(node: JsonNode, fieldName, pathForErrors: string): string =
  if not node.hasKey(fieldName) or node[fieldName].kind != JString or node[fieldName].getStr() == "":
    die("package metadata field '" & fieldName & "' must be a non-empty string: " & pathForErrors)
  result = node[fieldName].getStr()

proc optionalStringField(node: JsonNode, fieldName, pathForErrors: string) =
  if node.hasKey(fieldName) and node[fieldName].kind != JString:
    die("package metadata field '" & fieldName & "' must be a string: " & pathForErrors)

proc packageName(node: JsonNode, pathForErrors: string): string =
  if node.kind != JObject:
    die("package metadata is not a JSON object: " & pathForErrors)
  result = requireStringField(node, "name", pathForErrors)

proc validateTags(node: JsonNode, pathForErrors: string) =
  if not node.hasKey("tags") or node["tags"].kind != JArray:
    die("package metadata field 'tags' must be an array: " & pathForErrors)
  if node["tags"].len == 0:
    die("package metadata field 'tags' must not be empty: " & pathForErrors)
  for tag in node["tags"].items:
    if tag.kind != JString or tag.getStr() == "":
      die("package metadata tags must be non-empty strings: " & pathForErrors)

proc validatePackageMetadata(node: JsonNode, pathForErrors: string) =
  let name = packageName(node, pathForErrors)
  discard firstShardLetter(name)

  let hasAlias = node.hasKey("alias")
  if hasAlias:
    discard requireStringField(node, "alias", pathForErrors)
    optionalStringField(node, "url", pathForErrors)
    optionalStringField(node, "method", pathForErrors)
    optionalStringField(node, "description", pathForErrors)
    optionalStringField(node, "license", pathForErrors)
    optionalStringField(node, "web", pathForErrors)
    optionalStringField(node, "doc", pathForErrors)
    if node.hasKey("tags") and node["tags"].kind != JArray:
      die("package metadata field 'tags' must be an array: " & pathForErrors)
    return

  discard requireStringField(node, "url", pathForErrors)
  let packageMethod = requireStringField(node, "method", pathForErrors)
  if packageMethod notin ["git", "hg"]:
    die("package metadata field 'method' must be 'git' or 'hg': " & pathForErrors)
  validateTags(node, pathForErrors)
  discard requireStringField(node, "description", pathForErrors)
  discard requireStringField(node, "license", pathForErrors)
  optionalStringField(node, "web", pathForErrors)
  optionalStringField(node, "doc", pathForErrors)

proc comparePackages(a, b: JsonNode): int =
  let aName = packageName(a, "<in-memory>").toLowerAscii()
  let bName = packageName(b, "<in-memory>").toLowerAscii()
  result = cmp(aName, bName)
  if result == 0:
    result = cmp(packageName(a, "<in-memory>"), packageName(b, "<in-memory>"))

proc collectPackageFiles(inputRoot: string): seq[string] =
  for path in walkDirRec(inputRoot):
    if path.toLowerAscii().endsWith(".json"):
      result.add(path)

proc combinePackages(inputRoot, outputPath: string) =
  if not dirExists(inputRoot):
    die("shard directory not found: " & inputRoot)

  var packages: seq[JsonNode]
  for metadataPath in collectPackageFiles(inputRoot):
    let relative = relativePath(metadataPath, inputRoot).replace('\\', '/')
    let parts = relative.split('/')
    if parts.len != 2:
      die("unexpected shard path layout: " & metadataPath)

    let shardFromPath = parts[0]
    let filenameFromPath = parts[1]
    if not filenameFromPath.toLowerAscii().endsWith(".json"):
      die("unexpected shard filename: " & metadataPath)

    let pkg = parseFile(metadataPath)
    validatePackageMetadata(pkg, metadataPath)
    let name = packageName(pkg, metadataPath)
    let expectedShard = $firstShardLetter(name)
    let expectedFilename = name & ".json"

    if filenameFromPath != expectedFilename:
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
  replaceFile(tmpPath, outputPath)
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
