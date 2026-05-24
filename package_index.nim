import std/algorithm
import std/json
import std/os
import std/osproc
import std/parseopt
import std/streams
import std/strutils
import std/tables

const Usage = """
Usage:
  package_index
  package_index combine [pkgs-dir] [packages.json]
  package_index rebuild [pkgs-dir] [packages.json]
  package_index split [packages.json] [pkgs-dir]
  package_index sync-git [packages.json] [pkgs-dir]
  package_index sync-git <base-rev> <head-rev> [packages.json] [pkgs-dir]
  package_index add <package.json> [pkgs-dir] [packages.json]
  package_index create [pkgs-dir] [packages.json]
  package_index create-alias [pkgs-dir] [packages.json]
  package_index remove <package-name> [pkgs-dir] [packages.json]
  package_index [pkgs-dir] [packages.json]

Commands:
  combine   Combine sharded package files back into packages.json.
  rebuild   Regenerate packages.json from pkgs/.
  split     Split packages.json into pkgs/<letter>/<name>/package.json shard files.
  sync-git  Synchronize packages.json and pkgs/ using git revisions.
            Defaults to comparing master..HEAD when revisions are omitted.
  add       Add one package metadata file into pkgs/ and regenerate packages.json.
  create    Prompt for normal package metadata and write pkgs/.
  create-alias Prompt for alias package metadata and write pkgs/.
  remove    Remove one package from pkgs/.

Help:
  Running `package_index` with no arguments prints this help text.

Combine/Rebuild arguments:
  pkgs-dir       Input shard directory. Default: pkgs
  packages.json  Output manifest path. Default: packages.json

Legacy positional combine arguments:
  pkgs-dir       Input shard directory. Default: pkgs
  packages.json  Output manifest path. Default: packages.json
  Note: `package_index [pkgs-dir] [packages.json]` is kept for compatibility.

Split arguments:
  packages.json  Input manifest path. Default: packages.json
  pkgs-dir       Output shard directory. Default: pkgs

Sync-git arguments:
  base-rev       Previous revision for the comparison. Default: master
  head-rev       New revision for the comparison. Default: HEAD
  packages.json  Manifest path. Default: packages.json
  pkgs-dir       Shard directory. Default: pkgs

Add arguments:
  package.json   Input package metadata JSON file
  pkgs-dir       Shard directory to update. Default: pkgs
  packages.json  Unused compatibility argument. Default: packages.json

Create arguments:
  pkgs-dir       Shard directory to update. Default: pkgs
  packages.json  Unused compatibility argument. Default: packages.json

Create-alias arguments:
  pkgs-dir       Shard directory to update. Default: pkgs
  packages.json  Unused compatibility argument. Default: packages.json

Remove arguments:
  package-name   Package name to remove
  pkgs-dir       Shard directory to update. Default: pkgs
  packages.json  Unused compatibility argument. Default: packages.json
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

proc packageShardPath(pkg: JsonNode, pathForErrors, outputRoot: string): string =
  outputRoot / packageShardRelativePath(pkg, pathForErrors)

proc removeDirIfEmpty(path: string) =
  if not dirExists(path):
    return
  for kind, _ in walkDir(path):
    if kind != pcDir and kind != pcFile and kind != pcLinkToDir and kind != pcLinkToFile:
      continue
    return
  removeDir(path)

proc rebuildManifestFromShards(shardRoot, manifestPath: string) =
  var packages = loadShardedPackages(shardRoot)
  canonicalizePackages(packages)
  writeCombinedPackages(packages, manifestPath)

proc addPackageNode(pkg: JsonNode, pathForErrors, shardRoot: string) =
  validatePackageMetadata(pkg, pathForErrors)
  let outputPath = packageShardPath(pkg, pathForErrors, shardRoot)
  if fileExists(outputPath):
    die("package already exists: " & packageName(pkg, pathForErrors))
  createDir(parentDir(outputPath))
  writeFile(outputPath, pkg.pretty.cleanupWhitespace)
  echo "Added ", packageName(pkg, pathForErrors), " to ", shardRoot

proc addPackage(metadataPath, shardRoot, manifestPath: string) =
  if not fileExists(metadataPath):
    die("package metadata file not found: " & metadataPath)
  let pkg = parseFile(metadataPath)
  addPackageNode(pkg, metadataPath, shardRoot)

proc prompt(message: string): string =
  stdout.write(message)
  stdout.flushFile()
  if stdin.endOfFile:
    die("unexpected end of input")
  result = stdin.readLine().strip()

proc promptRequired(message, fieldName: string): string =
  result = prompt(message)
  if result.len == 0:
    die(fieldName & " must not be empty")

proc parseTagsInput(value: string): JsonNode =
  result = newJArray()
  for part in value.split(','):
    let tag = part.strip()
    if tag.len > 0:
      result.add(%tag)

proc createPackageMetadata(): JsonNode =
  let name = promptRequired("Package name: ", "package name")
  result = newJObject()
  result["name"] = %name

  result["url"] = %promptRequired("Repository URL: ", "url")
  result["method"] = %promptRequired("Method (git/hg): ", "method")
  result["tags"] = parseTagsInput(promptRequired("Tags (comma-separated): ", "tags"))
  result["description"] = %promptRequired("Description: ", "description")
  result["license"] = %promptRequired("License: ", "license")

  let web = prompt("Website URL (optional): ")
  if web.len > 0:
    result["web"] = %web

  let doc = prompt("Documentation URL (optional): ")
  if doc.len > 0:
    result["doc"] = %doc

proc createPackage(shardRoot, manifestPath: string) =
  let pkg = createPackageMetadata()
  addPackageNode(pkg, "<interactive>", shardRoot)

proc createAliasPackageMetadata(): JsonNode =
  let name = promptRequired("Alias package name: ", "package name")
  let alias = promptRequired("Alias target name: ", "alias")
  result = newJObject()
  result["name"] = %name
  result["alias"] = %alias

proc createAliasPackage(shardRoot, manifestPath: string) =
  let pkg = createAliasPackageMetadata()
  addPackageNode(pkg, "<interactive-alias>", shardRoot)

proc removePackage(packageNameToRemove, shardRoot, manifestPath: string) =
  if packageNameToRemove.len == 0:
    die("package name must not be empty")
  let shard = $firstShardLetter(packageNameToRemove)
  let packageDir = shardRoot / shard / packageNameToRemove
  let metadataPath = packageDir / "package.json"
  if not fileExists(metadataPath):
    die("package not found: " & packageNameToRemove)
  removeFile(metadataPath)
  removeDirIfEmpty(packageDir)
  removeDirIfEmpty(parentDir(packageDir))
  echo "Removed ", packageNameToRemove, " from ", shardRoot

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

proc packageTable(packages: seq[JsonNode], pathForErrors: string): Table[string, string] =
  for index, pkg in packages:
    let name = packageName(pkg, pathForErrors & "[" & $index & "]")
    if result.hasKey(name):
      die("duplicate package name: " & name & " in " & pathForErrors)
    result[name] = pkg.pretty.cleanupWhitespace

proc addedPackageNames(sourcePackages, destinationPackages: seq[JsonNode], sourcePath, destinationPath: string): seq[string] =
  let sourceTable = packageTable(sourcePackages, sourcePath)
  let destinationTable = packageTable(destinationPackages, destinationPath)
  for name in sourceTable.keys:
    if not destinationTable.hasKey(name):
      result.add(name)
  result.sort(system.cmp[string])

proc logAddedPackages(sourceLabel, destinationLabel: string, packageNames: seq[string]) =
  if packageNames.len == 0:
    echo "Sync: no new packages added from ", sourceLabel, " to ", destinationLabel
    return
  for name in packageNames:
    echo "Sync: add ", name, " from ", sourceLabel, " to ", destinationLabel

proc canSyncDirection(sourcePackages, destinationPackages: seq[JsonNode], sourcePath, destinationPath: string): bool =
  let sourceTable = packageTable(sourcePackages, sourcePath)
  let destinationTable = packageTable(destinationPackages, destinationPath)
  if sourceTable.len < destinationTable.len:
    return false

  for name, destinationJson in destinationTable.pairs:
    if not sourceTable.hasKey(name):
      return false
    if sourceTable[name] != destinationJson:
      return false

  result = true

proc syncPackages(baseRevArg, headRev, manifestPath, shardRoot: string) =
  if not fileExists(manifestPath) and not dirExists(shardRoot):
    die("neither " & manifestPath & " nor " & shardRoot & " exists")

  let baseRev = normalizeBaseRev(baseRevArg)
  let packagesChanged = revisionsDiffer(baseRev, headRev, manifestPath)
  let pkgsChanged = revisionsDiffer(baseRev, headRev, shardRoot)
  var syncMode = smNone

  if packagesChanged and not pkgsChanged:
    var packages = loadManifestPackages(manifestPath)
    let shardedPackages = if dirExists(shardRoot): loadShardedPackages(shardRoot) else: @[]
    canonicalizePackages(packages)
    let addedNames = addedPackageNames(packages, shardedPackages, manifestPath, shardRoot)
    writeSplitPackages(packages, shardRoot)
    logAddedPackages(manifestPath, shardRoot, addedNames)
    syncMode = smPackagesToPkgs
  elif not packagesChanged and pkgsChanged:
    let manifestPackages = if fileExists(manifestPath): loadManifestPackages(manifestPath) else: @[]
    var packages = loadShardedPackages(shardRoot)
    canonicalizePackages(packages)
    let addedNames = addedPackageNames(packages, manifestPackages, shardRoot, manifestPath)
    writeCombinedPackages(packages, manifestPath)
    logAddedPackages(shardRoot, manifestPath, addedNames)
    syncMode = smPkgsToPackages
  else:
    if not fileExists(manifestPath):
      die("manifest file not found: " & manifestPath)
    if not dirExists(shardRoot):
      die("shard directory not found: " & shardRoot)
    var manifestPackages = loadManifestPackages(manifestPath)
    var shardedPackages = loadShardedPackages(shardRoot)
    canonicalizePackages(manifestPackages)
    canonicalizePackages(shardedPackages)

    if renderPackagesJson(manifestPackages) == renderPackagesJson(shardedPackages):
      if packagesChanged and pkgsChanged:
        syncMode = smBothConsistent
    elif canSyncDirection(manifestPackages, shardedPackages, manifestPath, shardRoot):
      let addedNames = addedPackageNames(manifestPackages, shardedPackages, manifestPath, shardRoot)
      writeSplitPackages(manifestPackages, shardRoot)
      logAddedPackages(manifestPath, shardRoot, addedNames)
      syncMode = smPackagesToPkgs
    elif canSyncDirection(shardedPackages, manifestPackages, shardRoot, manifestPath):
      let addedNames = addedPackageNames(shardedPackages, manifestPackages, shardRoot, manifestPath)
      writeCombinedPackages(shardedPackages, manifestPath)
      logAddedPackages(shardRoot, manifestPath, addedNames)
      syncMode = smPkgsToPackages
    else:
      die(manifestPath & " and " & shardRoot & " disagree; update only one source or make both consistent")

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

  if positional.len > 0 and positional[0] == "sync-git":
    if positional.len notin 1..5 or positional.len == 2 or positional.len == 4:
      stderr.writeLine("error: sync-git accepts either 0 or 2 revisions, plus optional packages.json and pkgs arguments")
      stderr.write(Usage)
      return 1

    let useDefaultRevs = positional.len == 1 or positional.len == 3
    let baseRev = if useDefaultRevs: "master" else: positional[1]
    let headRev = if useDefaultRevs: "HEAD" else: positional[2]
    let manifestPath = if useDefaultRevs:
        (if positional.len >= 2: positional[1] else: "packages.json")
      else:
        (if positional.len >= 4: positional[3] else: "packages.json")
    let shardRoot = if useDefaultRevs:
        (if positional.len >= 3: positional[2] else: "pkgs")
      else:
        (if positional.len >= 5: positional[4] else: "pkgs")
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

  if positional.len > 0 and positional[0] == "add":
    if positional.len < 2 or positional.len > 4:
      stderr.writeLine("error: add requires 1 to 3 arguments")
      stderr.write(Usage)
      return 1

    let metadataPath = positional[1]
    let shardRoot = if positional.len >= 3: positional[2] else: "pkgs"
    let manifestPath = if positional.len >= 4: positional[3] else: "packages.json"
    addPackage(metadataPath, shardRoot, manifestPath)
    return 0

  if positional.len > 0 and positional[0] == "create":
    if positional.len > 3:
      stderr.writeLine("error: create accepts at most 2 arguments")
      stderr.write(Usage)
      return 1

    let shardRoot = if positional.len >= 2: positional[1] else: "pkgs"
    let manifestPath = if positional.len >= 3: positional[2] else: "packages.json"
    createPackage(shardRoot, manifestPath)
    return 0

  if positional.len > 0 and positional[0] == "create-alias":
    if positional.len > 3:
      stderr.writeLine("error: create-alias accepts at most 2 arguments")
      stderr.write(Usage)
      return 1

    let shardRoot = if positional.len >= 2: positional[1] else: "pkgs"
    let manifestPath = if positional.len >= 3: positional[2] else: "packages.json"
    createAliasPackage(shardRoot, manifestPath)
    return 0

  if positional.len > 0 and positional[0] == "remove":
    if positional.len < 2 or positional.len > 4:
      stderr.writeLine("error: remove requires 1 to 3 arguments")
      stderr.write(Usage)
      return 1

    let packageNameToRemove = positional[1]
    let shardRoot = if positional.len >= 3: positional[2] else: "pkgs"
    let manifestPath = if positional.len >= 4: positional[3] else: "packages.json"
    removePackage(packageNameToRemove, shardRoot, manifestPath)
    return 0

  if positional.len == 0:
    stdout.write(Usage)
    return 0

  if positional[0] in ["rebuild", "combine"]:
    if positional.len > 3:
      stderr.writeLine("error: " & positional[0] & " accepts at most 2 arguments")
      stderr.write(Usage)
      return 1

    let inputRoot = if positional.len >= 2: positional[1] else: "pkgs"
    let outputPath = if positional.len >= 3: positional[2] else: "packages.json"
    combinePackages(inputRoot, outputPath)
    return 0

  if positional.len <= 2:
    let inputRoot = positional[0]
    let outputPath = if positional.len >= 2: positional[1] else: "packages.json"
    combinePackages(inputRoot, outputPath)
    return 0

  stderr.writeLine("error: unknown command: " & positional[0])
  stderr.write(Usage)
  return 1

when isMainModule:
  quit(cliMain())
