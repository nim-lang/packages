import std/parseopt
import std/os
import std/json
import std/tables
import std/strutils
import std/httpclient
import std/streams
import std/net


const usage = """
Usage: packagescanner2 <packages.json> [--old=packages_old.json] [--check-urls]
Scans the nimble package list for mistakes and dead packages.
Options:
  --old=        Old package file, will only scan changed packages
  --check-urls  Try to request the package url
  --help        Print this help text"""


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

proc getStrIfExists(n: JsonNode, name: string, default: string = ""): string =
  result = default
  if n.hasKey(name) and n[name].kind == JString:
    result = n[name].str

proc getElemsIfExists(n: JsonNode, name: string, default: seq[JsonNode] = @[]): seq[JsonNode] =
  result = default
  if n.hasKey(name) and n[name].kind == JArray:
    result = n[name].elems

proc checkPackages(newPackagesPath: string, oldPackagesPath: string, checkUrls: bool = false): int =
  var oldPackagesTable = initTable[string, JsonNode]()
  if oldPackagesPath != "":
    let oldPackagesJson = parseJson(readFile(oldPackagesPath))
    for oldPkg in oldPackagesJson:
      let oldNameLower = oldPkg.getStrIfExists("name").toLowerAscii()
      if oldNameLower != "":
        oldPackagesTable[oldNameLower] = oldPkg

  let newPackagesJson = parseJson(readFile(newPackagesPath))
  # Do a first pass through the list to count duplicate names
  var packageNameCounter = initCountTable[string]()
  for pkg in newPackagesJson:
    let pkgNameLower = pkg.getStrIfExists("name").toLowerAscii()
    if pkgNameLower != "":
      packageNameCounter.inc(pkgNameLower)

  var client: HttpClient = nil
  if checkUrls:
    client = newHttpClient(timeout=3000)
    client.headers = newHttpHeaders({"User-Agent": "Nim packge_scanner/2.0"})

  var modifiedPackages = 0
  var failedPackages = 0
  for pkg in newPackagesJson:
    var success = true  # Set to false by logPackageError
    let pkgName = pkg.getStrIfExists("name")
    let pkgNameLower = pkgName.toLowerAscii()
    var displayName = pkgName
    if displayName == "":
      displayName = "<unnamed package>"

    # Start with detecting duplicates
    if packageNameCounter[pkgNameLower] > 1:
      let url = pkg.getStrIfExists("url", "<no url>")
      logPackageError("Duplicate package " & displayName & " from url " & url)

    # isNew should be used in future versions to do a conditional inspection
    # of the package contents which requires downloading the full release tarball
    let isNew = not oldPackagesTable.hasKey(pkgNameLower)
    var isModified: bool
    if isNew:
      isModified = true
    else:
      isModified = oldPackagesTable[pkgNameLower] != pkg

    if isModified:
      inc modifiedPackages

      if pkgName == "":
        logPackageError("Missing package name")

      let isAlias = pkg.hasKey("alias")
      if isAlias:
        if packageNameCounter[pkg["alias"].getStr().toLowerAscii()] == 0:
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
          if not pkgName.validIdentifier():
            logPackageError(displayName & " is not a valid identifier")

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
      inc failedPackages


  echo ""
  if oldPackagesPath != "":
    echo "Found ", modifiedPackages, " modified package(s)"
  echo "Problematic packages count: ", failedPackages
  if failedPackages > 0:
    result = 1


proc cliMain(): int =
  var parser = initOptParser(os.commandLineParams())
  var newPackagesPath = ""
  var oldPackagesPath = ""
  var checkUrls = false
  while true:
    parser.next()
    case parser.kind:
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      if parser.key == "old":
        oldPackagesPath = parser.val
      elif parser.key == "check-urls":
        checkUrls = true
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

  result = checkPackages(newPackagesPath, oldPackagesPath, checkUrls)

when isMainModule:
  quit(cliMain())
