# Package scanner for the nimble package list.
#
# Check the packages for:
# * Duplicate and invalid names
# * Missing alias targets
# * Empty tags
# * Invalid method
# * Missing description or license
# * Unavailable URLs
# * Insecure URLs
# * PR-specific new-package vs modified-package rules
#
# Usage: nim r package_scanner.nim <packages.json> [--check-urls] [--check-pr]
#
# Copyright 2015 Federico Ceratto <federico.ceratto@gmail.com>
# Copyright 2023 Gabriel Huber <mail@gabrielhuber.at>
# Released under GPLv3 License, see LICENSE-GPLv3.txt

import std/parseopt
import std/os
import std/json
import std/tables
import std/strutils
import std/httpclient
import std/streams
import std/net
import std/osproc
import std/sets


const usage = """
Usage: package_scanner <packages.json> [--check-urls] [--check-pr]
Scans the nimble package list for mistakes and dead packages.
Options:
  --check-urls  Try to request the package url
  --check-pr    Compare against the git merge base for the PR and enforce PR rules
                This is the CI mode used for pull requests.
  --help        Print this help text"""

const allowedNameChars = {'a'..'z', 'A'..'Z', '0'..'9', '_', '-', '.'}

type
  PackageDiff = object
    oldPackagesTable: Table[string, JsonNode]
    mergeBase: string
    newPackageNames: seq[string]
    modifiedExistingNames: seq[string]
    removedPackageNames: seq[string]


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
    let rendered = @[exe] & @args
    raise newException(IOError, "command failed: " & rendered.join(" ") & "\n" & output.strip())
  result = output

proc requireEnv(name: string): string =
  result = getEnv(name)
  if result.len == 0:
    raise newException(IOError, "missing required environment variable: " & name)

proc getStrIfExists(n: JsonNode, name: string, default: string = ""): string =
  result = default
  if n.hasKey(name) and n[name].kind == JString:
    result = n[name].str

proc getElemsIfExists(n: JsonNode, name: string, default: seq[JsonNode] = @[]): seq[JsonNode] =
  result = default
  if n.hasKey(name) and n[name].kind == JArray:
    result = n[name].elems

proc shardPathFor(packageName: string): string =
  if packageName.len == 0:
    raise newException(ValueError, "package metadata missing name")
  let shard = packageName[0].toLowerAscii()
  if shard notin {'a'..'z'}:
    raise newException(ValueError, "package name must start with an ASCII letter for alphabetical sharding: " & packageName)
  result = "pkgs/" & $shard & "/" & packageName & ".json"

proc loadOldPackagesFromJson(oldPackagesJson: JsonNode): Table[string, JsonNode] =
  if oldPackagesJson.kind != JArray:
    raise newException(ValueError, "old package file must contain a JSON array")
  for oldPkg in oldPackagesJson:
    let oldNameNorm = oldPkg.getStrIfExists("name").normalize()
    if oldNameNorm != "":
      result[oldNameNorm] = oldPkg

proc loadOldPackagesTable(oldPackagesPath: string): Table[string, JsonNode] =
  if oldPackagesPath == "":
    return initTable[string, JsonNode]()
  result = loadOldPackagesFromJson(parseJson(readFile(oldPackagesPath)))

proc loadPrDiff(newPackagesPath: string): PackageDiff =
  let repository = requireEnv("GITHUB_REPOSITORY")
  let baseRef = requireEnv("GITHUB_BASE_REF")
  let targetRepository = "https://github.com/" & repository

  discard runCommand("git", ["fetch", targetRepository, baseRef])
  let mergeBase = runCommand("git", ["merge-base", "HEAD", "FETCH_HEAD"]).strip()
  if mergeBase.len == 0:
    raise newException(IOError, "git merge-base returned an empty commit id")

  let oldPackagesRaw = runCommand("git", ["show", mergeBase & ":" & newPackagesPath])
  let oldPackagesJson = parseJson(oldPackagesRaw)
  result.oldPackagesTable = loadOldPackagesFromJson(oldPackagesJson)
  result.mergeBase = mergeBase

  let newPackagesJson = parseJson(readFile(newPackagesPath))
  if newPackagesJson.kind != JArray:
    raise newException(ValueError, "new package file must contain a JSON array")

  var seenCurrentNames = initHashSet[string]()
  for pkg in newPackagesJson:
    let pkgName = pkg.getStrIfExists("name")
    let pkgNameNorm = pkgName.normalize()
    if pkgNameNorm == "":
      continue

    seenCurrentNames.incl(pkgNameNorm)
    if not result.oldPackagesTable.hasKey(pkgNameNorm):
      result.newPackageNames.add(pkgName)
    elif result.oldPackagesTable[pkgNameNorm] != pkg:
      result.modifiedExistingNames.add(pkgName)

  for oldNameNorm, oldPkg in result.oldPackagesTable.pairs:
    if oldNameNorm notin seenCurrentNames:
      result.removedPackageNames.add(oldPkg.getStrIfExists("name", oldNameNorm))

proc checkPrSharding(newPackageNames: seq[string], mergeBase: string): seq[string] =
  for packageName in newPackageNames:
    let shardPath = shardPathFor(packageName)
    let existsCode = execCmdEx("git cat-file -e " & quoteShell(mergeBase & ":" & shardPath)).exitCode
    if existsCode == 0:
      result.add("New package " & packageName & " would clash with existing shard path " & shardPath)
    elif existsCode != 128:
      result.add("Unable to verify shard path for " & packageName & ": git cat-file exited with code " & $existsCode)

proc checkUrlReachable(client: HttpClient, url: string): string =
  var headers: HttpHeaders = nil
  if url.startsWith("https://github.com"):
    if existsEnv("GITHUB_TOKEN"):
      headers = newHttpHeaders({"Authorization": "Bearer " & getEnv("GITHUB_TOKEN")})

  try:
    let resp = client.request(url, headers=headers)
    discard resp.bodyStream.readAll()
    if not resp.code.is2xx:
      result = "Server returned status " & $resp.code
  except TimeoutError:
    result = "Timeout after " & $client.timeout & "ms"
    client.close()
  except HttpRequestError:
    result = "HTTP error: " & getCurrentExceptionMsg()
    client.close()
  except AssertionDefect:
    result = "httpclient error: " & getCurrentExceptionMsg()
    client.close()
  except CatchableError as e:
    result = "Unexpected exception " & $e.name & ": " & e.msg
    client.close()

template logPackageError(errorMsg: string) =
  echo "E: ", errorMsg
  success = false

template checkUrl(urlType: string, url: string) =
  if url == "":
    logPackageError(displayName & " has an empty " & urlType & " URL")
  elif not url.startsWith("https://"):
    logPackageError(displayName & " has a non-https " & urlType & " URL: " & url)
  elif checkUrls:
    let urlError = client.checkUrlReachable(url)
    if urlError != "":
      logPackageError(displayName & " has an unreachable " & urlType & " URL: " & url)
      logPackageError(urlError)

proc checkPackages(newPackagesPath: string, oldPackagesPath: string, checkUrls: bool = false,
                   checkPr: bool = false): int =
  var oldPackagesTable = initTable[string, JsonNode]()
  var mergeBase = ""
  var newPackageNames: seq[string]
  var modifiedExistingNames: seq[string]
  var removedPackageNames: seq[string]
  if checkPr:
    let prDiff = loadPrDiff(newPackagesPath)
    oldPackagesTable = prDiff.oldPackagesTable
    mergeBase = prDiff.mergeBase
    newPackageNames = prDiff.newPackageNames
    modifiedExistingNames = prDiff.modifiedExistingNames
    removedPackageNames = prDiff.removedPackageNames
  else:
    oldPackagesTable = loadOldPackagesTable(oldPackagesPath)

  let newPackagesJson = parseJson(readFile(newPackagesPath))
  doAssert newPackagesJson.kind == JArray
  # Do a first pass through the list to count duplicate names
  var packageNameCounter = initCountTable[string]()
  for pkg in newPackagesJson:
    let pkgNameNorm = pkg.getStrIfExists("name").normalize()
    if pkgNameNorm != "":
      packageNameCounter.inc(pkgNameNorm)

  var client: HttpClient = nil
  if checkUrls:
    client = newHttpClient(timeout=3000)
    client.headers = newHttpHeaders({"User-Agent": "Nim packge_scanner/2.0"})

  var modifiedPackagesCount = 0
  var failedPackagesCount = 0
  if checkPr and newPackageNames.len > 0 and (modifiedExistingNames.len > 0 or removedPackageNames.len > 0):
    echo "E: PRs that add new packages may not also modify or remove existing packages"
    if modifiedExistingNames.len > 0:
      echo "E: Modified existing packages: ", modifiedExistingNames.join(", ")
    if removedPackageNames.len > 0:
      echo "E: Removed existing packages: ", removedPackageNames.join(", ")
    inc failedPackagesCount

  if checkPr:
    for errorMsg in checkPrSharding(newPackageNames, mergeBase):
      echo "E: ", errorMsg
      inc failedPackagesCount

  for pkg in newPackagesJson:
    var success = true  # Set to false by logPackageError
    let pkgName = pkg.getStrIfExists("name")
    let pkgNameNorm = pkgName.normalize()
    var displayName = pkgName
    if displayName == "":
      displayName = "<unnamed package>"

    # Start with detecting duplicates
    if packageNameCounter[pkgNameNorm] > 1:
      let url = pkg.getStrIfExists("url", "<no url>")
      logPackageError("Duplicate package " & displayName & " from url " & url)

    # isNew should be used in future versions to do a conditional inspection
    # of the package contents which requires downloading the full release tarball
    let isNew = not oldPackagesTable.hasKey(pkgNameNorm)
    var isModified: bool
    if isNew:
      isModified = true
    else:
      isModified = oldPackagesTable[pkgNameNorm] != pkg

    if isModified:
      inc modifiedPackagesCount

      if pkgName == "":
        logPackageError("Missing package name")

      let isAlias = pkg.hasKey("alias")
      if isAlias:
        if packageNameCounter[pkg["alias"].getStr().normalize()] == 0:
          logPackageError(displayName & " is an alias pointing to a missing package")
      else:
        var tags = pkg.getElemsIfExists("tags")
        var isDeleted = false
        if tags.len == 0:
          logPackageError(displayName & " has no tags")
        else:
          var emptyTags = false
          for tag in tags:
            if tag.getStr == "":
              emptyTags = true
            if tag.getStr.toLowerAscii() == "deleted":
              isDeleted = true
          if emptyTags:
            logPackageError(displayName & " has empty tags")

        if not isDeleted:
          if not pkgName.allCharsInSet(allowedNameChars):
            logPackageError(displayName & " is not a valid package name")

          if not pkg.hasKey("method"):
            logPackageError(displayName & " has no method")
          elif pkg["method"].kind != JString or pkg["method"].str notin ["git", "hg"]:
            logPackageError(displayName & " has an invalid method")

          if pkg.getStrIfExists("description") == "":
            logPackageError(displayName & " has no description")

          if pkg.getStrIfExists("license") == "":
            logPackageError(displayName & " has no license")

          var downloadUrl = pkg.getStrIfExists("url")
          if not pkg.hasKey("url"):
            logPackageError(displayName & " has no download URL")
          else:
            downloadUrl = downloadUrl
            checkUrl("download", downloadUrl)

          if pkg.hasKey("web"):
            let webUrl = pkg["web"].getStr()
            if webUrl != downloadUrl:
              checkUrl("web", webUrl)

          if pkg.hasKey("doc"):
            let docUrl = pkg["doc"].getStr()
            if docUrl != downloadUrl:
              checkUrl("doc", docUrl)


    if not success:
      inc failedPackagesCount


  if client != nil:
    client.close()

  echo ""
  if checkPr:
    echo "Compared against merge base ", mergeBase
    echo "Found ", newPackageNames.len, " new package(s), ",
      modifiedExistingNames.len, " modified existing package(s), and ",
      removedPackageNames.len, " removed package(s)"
  elif oldPackagesPath != "":
    echo "Found ", modifiedPackagesCount, " modified package(s)"
  echo "Problematic packages count: ", failedPackagesCount
  if failedPackagesCount > 0:
    result = 1


proc cliMain(): int =
  var parser = initOptParser(os.commandLineParams())
  var newPackagesPath = ""
  var oldPackagesPath = ""
  var checkUrls = false
  var checkPr = false
  while true:
    parser.next()
    case parser.kind:
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      if parser.key == "old":
        oldPackagesPath = parser.val
      elif parser.key == "check-urls":
        checkUrls = true
      elif parser.key == "check-pr":
        checkPr = true
      elif parser.key == "help":
        echo usage
        return 0
    of cmdArgument:
      if newPackagesPath == "":
        newPackagesPath = parser.key
      else:
        echo "Too many arguments!"
        return 1

  if newPackagesPath == "":
    echo usage
    return 1

  if checkPr and oldPackagesPath != "":
    echo "Cannot use --old and --check-pr together"
    return 1

  result = checkPackages(newPackagesPath, oldPackagesPath, checkUrls, checkPr)

when isMainModule:
  quit(cliMain())
