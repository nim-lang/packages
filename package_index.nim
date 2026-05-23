import std/algorithm
import std/json
import std/os
import std/osproc
import std/parseopt
import std/streams
import std/strutils

const Usage = """
Usage:
  package_index [pkgs-dir] [packages.json]
  package_index split [packages.json] [pkgs-dir]
  package_index sync <base-rev> <head-rev> [packages.json] [pkgs-dir]

Commands:
  combine  Combine sharded package files back into packages.json. This is the default.
  split    Split packages.json into pkgs/<letter>/<name>/package.json shard files.
  sync     Synchronize packages.json and pkgs/ for a pushed git revision range.

Combine arguments:
  pkgs-dir       Input shard directory. Default: pkgs
  packages.json  Output manifest path. Default: packages.json

Split arguments:
  packages.json  Input manifest path. Default: packages.json
  pkgs-dir       Output shard directory. Default: pkgs

Sync arguments:
  base-rev       Previous revision for the push
  head-rev       New revision for the push
  packages.json  Manifest path. Default: packages.json
  pkgs-dir       Shard directory. Default: pkgs
"""

type
  SyncMode = enum
    smNone = "none"
    smPackagesToPkgs = "packages-to-pkgs"
    smPkgsToPackages = "pkgs-to-packages"
    smBothConsistent = "both-consistent"

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

proc replaceDir(sourcePath, destinationPath: string) =
  if dirExists(destinationPath):
    removeDir(destinationPath)
  moveDir(sourcePath, destinationPath)

proc runCommand(exe: string, args: openArray[string]): string =
  var process = startProcess(
    exe,
    args = @args,
    options = {poUsePath, poStdErrToStdOut}
  )
  let output = process.outputStream.readAll()
  let exitCode = waitForExit(process)
  close(process)
  if exitCode != 0:
    var rendered = @[exe]
    for arg in args:
      rendered.add(arg)
    die("command failed: " & rendered.join(" ") & "\n" & output.strip())
  result = output.strip()

proc commandSucceeded(exe: string, args: openArray[string]): bool =
  var process = startProcess(exe, args = @args, options = {poUsePath, poStdErrToStdOut})
  discard process.outputStream.readAll()
  result = waitForExit(process) == 0
  close(process)

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

proc canonicalizePackages(packages: var seq[JsonNode]) =
  packages.sort(comparePackages)

proc collectPackageFiles(inputRoot: string): seq[string] =
  for path in walkDirRec(inputRoot):
    if path.toLowerAscii().endsWith(".json"):
      result.add(path)

proc metadataRelativePath(inputRoot, metadataPath: string): string =
  let normalizedRoot = normalizedPath(inputRoot).replace('\\', '/').strip(chars = {'/'})
  let normalizedPathValue = normalizedPath(metadataPath).replace('\\', '/')
  let prefix = normalizedRoot & "/"
  if normalizedPathValue.startsWith(prefix):
    return normalizedPathValue[prefix.len .. ^1]
  result = relativePath(metadataPath, inputRoot).replace('\\', '/')

proc loadManifestPackages(inputPath: string): seq[JsonNode] =
  if not fileExists(inputPath):
    die("manifest file not found: " & inputPath)
  let manifest = parseFile(inputPath)
  if manifest.kind != JArray:
    die("manifest must be a JSON array: " & inputPath)
  for index in 0 ..< manifest.len:
    let pkg = manifest[index]
    validatePackageMetadata(pkg, inputPath & "[" & $index & "]")
    result.add(pkg)

proc loadShardedPackages(inputRoot: string): seq[JsonNode] =
  if not dirExists(inputRoot):
    die("shard directory not found: " & inputRoot)
  for metadataPath in collectPackageFiles(inputRoot):
    let relative = metadataRelativePath(inputRoot, metadataPath)
    let parts = relative.split('/')

    let pkg = parseFile(metadataPath)
    validatePackageMetadata(pkg, metadataPath)
    let name = packageName(pkg, metadataPath)
    let expectedShard = $firstShardLetter(name)

    if parts.len != 3:
      die("unexpected shard path layout: " & metadataPath)
    let shardFromPath = parts[0]
    let packageDirFromPath = parts[1]
    let filenameFromPath = parts[2]
    if filenameFromPath != "package.json":
      die("unexpected shard filename: " & metadataPath)
    if packageDirFromPath != name:
      die("package path does not match .name for " & metadataPath)
    if shardFromPath != expectedShard:
      die("shard path does not match first letter for " & metadataPath)

    result.add(pkg)

  if result.len == 0:
    die("no package metadata files found under " & inputRoot)

proc renderPackagesJson(packages: seq[JsonNode]): string =
  let outputJson = %packages
  result = outputJson.pretty.cleanupWhitespace

proc writeCombinedPackages(packages: seq[JsonNode], outputPath: string) =
  let tmpPath = outputPath & ".tmp"
  writeFile(tmpPath, renderPackagesJson(packages))
  replaceFile(tmpPath, outputPath)

proc packageShardRelativePath(pkg: JsonNode, pathForErrors: string): string =
  let name = packageName(pkg, pathForErrors)
  let shard = $firstShardLetter(name)
  result = shard / name / "package.json"

proc writeSplitPackages(packages: seq[JsonNode], outputRoot: string) =
  let tempRoot = getTempDir() / ("split-packages-" & $getCurrentProcessId())
  defer:
    if dirExists(tempRoot):
      removeDir(tempRoot)

  createDir(tempRoot)
  for index, pkg in packages:
    let relativePath = packageShardRelativePath(pkg, "<in-memory>[" & $index & "]")
    let outputPath = tempRoot / relativePath
    createDir(parentDir(outputPath))
    if fileExists(outputPath):
      die("duplicate shard output path: " & relativePath.replace('\\', '/'))
    writeFile(outputPath, pkg.pretty.cleanupWhitespace)

  replaceDir(tempRoot, outputRoot)

proc combinePackages(inputRoot, outputPath: string) =
  var packages = loadShardedPackages(inputRoot)
  canonicalizePackages(packages)
  writeCombinedPackages(packages, outputPath)
  echo "Wrote ", packages.len, " packages into ", outputPath

proc splitPackages(inputPath, outputRoot: string) =
  var packages = loadManifestPackages(inputPath)
  canonicalizePackages(packages)
  writeSplitPackages(packages, outputRoot)
  echo "Wrote ", packages.len, " package metadata files into ", outputRoot

proc normalizeBaseRev(baseRev: string): string =
  if baseRev == "0000000000000000000000000000000000000000" or
      not commandSucceeded("git", ["cat-file", "-e", baseRev & "^{commit}"]):
    if commandSucceeded("git", ["rev-parse", "HEAD^"]):
      return runCommand("git", ["rev-parse", "HEAD^"])
    return ""
  result = baseRev

proc revisionsDiffer(baseRev, headRev, path: string): bool =
  if baseRev.len == 0:
    return false
  result = not commandSucceeded("git", ["diff", "--quiet", baseRev, headRev, "--", path])

proc packagesEqual(manifestPath, shardRoot: string): bool =
  var manifestPackages = loadManifestPackages(manifestPath)
  var shardedPackages = loadShardedPackages(shardRoot)
  canonicalizePackages(manifestPackages)
  canonicalizePackages(shardedPackages)
  result = renderPackagesJson(manifestPackages) == renderPackagesJson(shardedPackages)

proc syncPackages(baseRevArg, headRev, manifestPath, shardRoot: string) =
  if not fileExists(manifestPath) and not dirExists(shardRoot):
    die("neither " & manifestPath & " nor " & shardRoot & " exists")

  let baseRev = normalizeBaseRev(baseRevArg)
  let packagesChanged = revisionsDiffer(baseRev, headRev, manifestPath)
  let pkgsChanged = revisionsDiffer(baseRev, headRev, shardRoot)
  var syncMode = smNone

  if packagesChanged and not pkgsChanged:
    var packages = loadManifestPackages(manifestPath)
    canonicalizePackages(packages)
    writeSplitPackages(packages, shardRoot)
    syncMode = smPackagesToPkgs
  elif not packagesChanged and pkgsChanged:
    var packages = loadShardedPackages(shardRoot)
    canonicalizePackages(packages)
    writeCombinedPackages(packages, manifestPath)
    syncMode = smPkgsToPackages
  else:
    if not fileExists(manifestPath):
      die("manifest file not found: " & manifestPath)
    if not dirExists(shardRoot):
      die("shard directory not found: " & shardRoot)
    if not packagesEqual(manifestPath, shardRoot):
      die(manifestPath & " and " & shardRoot & " disagree; update only one source or make both consistent")
    if packagesChanged and pkgsChanged:
      syncMode = smBothConsistent

  echo "Sync mode: ", $syncMode

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

  if positional.len > 0 and positional[0] == "sync":
    if positional.len < 3 or positional.len > 5:
      stderr.writeLine("error: sync requires 2 to 4 arguments")
      stderr.write(Usage)
      return 1

    let baseRev = positional[1]
    let headRev = positional[2]
    let manifestPath = if positional.len >= 4: positional[3] else: "packages.json"
    let shardRoot = if positional.len >= 5: positional[4] else: "pkgs"
    syncPackages(baseRev, headRev, manifestPath, shardRoot)
    return 0

  if positional.len > 0 and positional[0] == "split":
    if positional.len > 3:
      stderr.writeLine("error: split accepts at most 2 arguments")
      stderr.write(Usage)
      return 1

    let inputPath = if positional.len >= 2: positional[1] else: "packages.json"
    let outputRoot = if positional.len >= 3: positional[2] else: "pkgs"
    splitPackages(inputPath, outputRoot)
    return 0

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
