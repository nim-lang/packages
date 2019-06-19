## Package JSON Linter
## ===================
##
## - Tests the ``package.json`` list from this repository.
##
## Check the packages for:
## - Validate by parsing with NodeJS
## - Missing name
## - Missing/unknown method
## - Missing/unreachable repository
## - Missing tags
## - Missing description
## - Missing/unknown license
## - Insecure git:// url on GitHub
## - Insecure http:// url
## - Blacklisted tags
## - Empty string tags
## - Unwanted whitespaces on tags
## - Too much tags
## - Missing nimble files on repos
## - Packages with duplicated URLs
## - Enforce required keys
## - Maximum number of tags
## - Maximum lenght of tags
## - Alias relate to Names
## - Try to download the nimble file from the repo.
## - Try to Git clone the repo (deletes folder after).
## - Works online/offline
##
## Use
## ---
##
## - Off-line: ``nim c -r -d:offline package_scanner.nim`` (Faster, wont use Internet).
## - On-line: ``nim c -r package_scanner.nim`` (Checks URLs, needs SSL).
##
## Credits
## -------
##
## Based and inspired on a previous ``package_scanner.nim`` from:
## Copyright 2015 Federico Ceratto <federico.ceratto@gmail.com>
## Released under GPLv3 License, see /usr/share/common-licenses/GPL-3

import
  httpclient, json, net, os, osproc, sets, strutils, streams, logging,
  unittest, sequtils, std/editdistance


const
  allowBrokenUrl = true      ## Allow broken Repo URLs
  allowMissingNimble = true  ## Allow missing ``*.nimble`` files
  checkNimbleFile = true     ## Check if repos have ``*.nimble`` file
  checkByGit = false         ## Check via Git
  httpTimeout = 10_000       ## Timeout. Below ~2000 false positives happen?
  tagsMaxLen = 32            ## Maximum lenght for the string in tags
  tagsMaximum = 17           ## Maximum number of tags allowed on the list
  lineLenMax = 250           ## Maximum line lenght for values
  vcsTypes = ["git", "hg"]   ## Valid known Version Control Systems.
  tagsBlacklist = ["nimrod", "nim"] ## Tags that should be not allowed.
  keysRequired = ["name", "url", "method", "tags", "description", "license"]
  gitTempDir = "/tmp/gitTempDir"
  gitCmd = "git clone --no-checkout --no-tags --bare --depth 1 $1 " & gitTempDir
  nodeCmd = "node ./validate_json.js"
  defaultFilePermissions = {fpUserWrite, fpUserRead, fpGroupWrite, fpGroupRead, fpOthersRead}
  packagesFilePath = currentSourcePath().parentDir / "packages.json"
  packagesJsonStr = readFile(packagesFilePath)
  hostsSkip = [
    "bitbucket.org",
    "gitlab.3dicc",
    "mahlon@bitbucket.org",
    "notabug.org",
  ] ## Hostnames to skip checks, for reliability, wont like direct HTTP GET?.
  licenses = [
    "allegro 4 giftware",
    "apache",
    "apache2",
    "apache2.0",
    "apache 2.0",
    "apache-2.0",
    "apache version 2.0",
    "apache license 2.0",
    "bsd",
    "bsd2",
    "bsd-2",
    "bsd3",
    "bsd-3",
    "bsd 2-clause",
    "bsd-2-clause",
    "bsd 3-clause",
    "bsd-3-clause",
    "cc0",
    "gpl",
    "gpl2",
    "gpl-2.0",
    "gpl3",
    "gpl-3.0",
    "gplv2",
    "gplv3",
    "lgpl",
    "lgplv2",
    "lgplv2.1",
    "lgplv3",
    "mit",
    "ms-pl",
    "mpl",
    "ppl",
    "wtfpl",
    "libpng",
    "zlib",
    "isc",
    "unlicense",
    # Not concrete Licenses, but some rare cases observed on the JSON.
    "0bsd",
    "agplv3",
    "agpl-3.0",
    "apache license 2.0 or mit",
    "fontconfig",
    "gnu lesser general public license v2.1",
    "public domain",
    "lgplv3 or gplv2",
    "openssl and ssleay",
    "openldap",
    "apache 2.0 or gplv2",
    "mit or apache 2.0",
    "lgpl with static linking exception",
  ]  ## All valid known licences for Nimble packages, on lowercase.


let
  packagesJson = parseJson(packagesJsonStr).getElems         ## ``string`` to ``JsonNode``
  pckgsList = filterIt(packagesJson, not it.hasKey("alias")) ## Packages, without Aliases
  aliasList = filterIt(packagesJson, it.hasKey("alias"))     ## Aliases, without Packages
  client = newHttpClient(timeout = httpTimeout) ## HTTP Client with Timeout
  report = newJUnitOutputFormatter(openFileStream("report.xml", fmWrite)) ## JUnit Report XML
addOutputFormatter(defaultConsoleFormatter())
addOutputFormatter(report)


proc handler() {.noconv.} =
  quit("CTRL+C Pressed, package_scanner is shutting down, Bye.")
setControlCHook(handler)


func stripEndingSlash(url: string): string {.inline.} =
  ## Strip the ending '/' if any else return the same string.
  result = if url[0..^1] == "/": url[0..^2] else: url

func preprocessUrl(url, name: string): string =
  ## Take **Normalized** URL & Name return Download link. GitHub & GitLab supported.
  if url.startswith("https://github.com/"):
    result = url.replace("https://github.com/", "https://raw.githubusercontent.com/")
    result = stripEndingSlash(result)
    result &= "/master/" & name & ".nimble"
  elif url.startswith("https://0xacab.org/") or url.startswith("https://gitlab."):
    result = stripEndingSlash(result)
    result &= "/raw/master/" & name & ".nimble"

proc existsNimbleFile(url, name: string): string =
  ## Take **Normalized** URL & Name try to Fetch the Nimble file. Needs SSL.
  if url.startswith("http"):
    try:
      let urly = preprocessUrl(url, name)
      if urly.len == 0:
        raise newException(HttpRequestError, "GIT Hosting not supported: " & url)
      if client.get(url).status != $Http200: # Check that Repo Exists.
        raise newException(HttpRequestError, "GIT Repo not found: " & url)
      result = urly
    except TimeoutError, HttpRequestError, AssertionError:
      warn("HttpClient request error fetching repo: " & url, getCurrentExceptionMsg())
    except:
      warn("Unkown Error fetching repo: " & url, getCurrentExceptionMsg())
  else:
    result = url  # SSH or other non-HTTP kinda URLs?

proc existsGitRepo(url: string): string =
  ## Take **Normalized** URL try to Fetch the Git repo index page. Needs SSL.
  if url.startswith("http"):
    try:
      if client.get(url).status != $Http200:  # Check that Repo Exists.
        raise newException(HttpRequestError, "GIT Repo not found: " & url)
      result = url
    except TimeoutError, HttpRequestError, AssertionError:
      warn("HttpClient request error fetching repo: " & url, getCurrentExceptionMsg())
    except:
      warn("Unkown Error fetching repo: " & url, getCurrentExceptionMsg())
  else:
    result = url  # SSH or other non-HTTP kinda URLs?


suite "Packages consistency testing":

  var
    names = initHashSet[string]()
    urls = initHashSet[string]()

  test "Check file permissions":
    check getFilePermissions(packagesFilePath) == defaultFilePermissions

  test "Check validate whole JSON by NodeJS":
    check execCmd(nodeCmd) == 0

  test "Check Basic Structure":
    for pdata in pckgsList:
      for key in keysRequired:
        if pdata.hasKey(key):
          if key == "tags":
            check pdata[key].kind == JArray  # Tags is array
            check pdata[key].len > 0         # Tags can not be empty
          else:
            check pdata[key].kind == JString      # Other keys are string
            check pdata[key].str.len > 0          # No field can be empty string
            check pdata[key].str.len < lineLenMax # No field can be empty string
            check r"\t" notin pdata[key].str      # No Tabs
        else:
          fatal("Missing Keys on the JSON (making it invalid): " & $key)

  test "Check Tags":
    for pdata in pckgsList:
      check pdata["tags"].len > 0            # Minimum number of tags
      check tagsMaximum > pdata["tags"].len # Maximum number of tags
      for tagy in pdata["tags"]:
        check tagy.str.strip.len >= 1     # No empty string tags
        check tagsMaxLen > tagy.str.len # Maximum lenght of tags
        check tagy.str.strip.toLowerAscii notin tagsBlacklist

  test "Check Methods":
    for pdata in pckgsList:
      var metod = pdata["method"]
      check metod.kind == JString
      check metod.str.len == pdata["method"].str.strip.len
      check metod.str in vcsTypes

  test "Check Licenses":
    for pdata in pckgsList:
      var license = pdata["license"]
      check license.kind == JString
      check license.str.len == license.str.strip.len
      check(not license.str.strip.startsWith("the ")) # Dont use "The GPL" etc
      check license.str.normalize in licenses

  test "Check Names":
    for pdata in pckgsList:
      var name = pdata["name"]
      check name.kind == JString
      check name.str.len == name.str.strip.len # No Whitespace
      if name.str.strip notin names:
        names.incl name.str.strip.toLowerAscii
      else:
        fatal("Package by that name already exists: " & $name)

  test "Check Webs":
    for pdata in pckgsList:
      if pdata.hasKey("web"):
        var weeb = pdata["web"]
        check weeb.kind == JString
        check weeb.str.len == weeb.str.strip.len
        check weeb.str.strip.startswith("http")
        # Insecure Link URLs
        check(not weeb.str.strip.startsWith("http://github.com"))
        check(not weeb.str.strip.startsWith("http://gitlab.com"))
        check(not weeb.str.strip.startsWith("http://0xacab.org"))

  test "Check URLs Off-Line":
    for pdata in pckgsList:
      var url = pdata["url"].str
      check url.len == url.strip.len # No Whitespace
      # Insecure Link URLs
      check(not url.strip.startsWith("git://github.com/"))
      check(not url.strip.startsWith("http://github.com"))
      check(not url.strip.startsWith("http://gitlab.com"))
      check(not url.strip.startsWith("http://0xacab.org"))
      if url notin urls:
        urls.incl url
      else:
        fatal("Package by that URL already exists: " & $url)

  test "Check Alias":
    doAssert names.len > 0, $names
    doAssert aliasList.len > 0, $aliasList
    for pdata in aliasList:
      var alias = pdata["alias"].str
      check alias.len == alias.strip.len
      check alias.strip.toLowerAscii in names  # Alias must relate to a name

  test "Check URLs On-Line by Git":
    when checkByGit:
      for pdata in pckgsList:
        removeDir(gitTempDir)
        check execCmd(gitCmd.format(pdata["url"].str)) == 0

  test "Check URLs On-Line by HttpClient":
    when defined(ssl):
      when defined(offline):
        {.hint: "Compile with no options to do checking of Repo URLs On-Line.".}
      else:
        var existent, nonexistent, nimbleExistent, nimbleNonexistent: seq[string]
        for pdata in pckgsList:
          var
            skip: bool
            url = pdata["url"].str.strip.toLowerAscii
            name = pdata["name"].str.normalize

          # Some hostings randomly timeout or fail sometimes, skip them.
          for skipurl in hostsSkip:
            if url.startsWith(skipurl):
              skip = true
          if skip: continue

          echo url  # Do Not remove, Travis quits with "N minutes without output, job cancelled".

          # Check that the Git Repo actually exists.
          var this_repo = existsGitRepo(url=url) # Fetch test.
          if this_repo.len > 0:
            existent.add this_repo
          else:
            nonexistent.add url

          # Check for Nimble Files on Existent Repos.
          if this_repo.len > 0 and checkNimbleFile:
            var this_nimble = existsNimbleFile(url=this_repo, name=name)
            if this_nimble.len > 0:
              nimbleExistent.add this_nimble
            else:
              nimbleNonexistent.add url

        # Warn or Assert the possible errors at the end.
        if nonexistent.len > 0 and allowBrokenUrl:
          warn "Missing repos list:\n" & nonexistent.join("\n  ")
          warn "Missing repos count: " & $nonexistent.len & " of " & $pckgsList.len
        else:
          doAssert nonexistent.len == 0, "Missing repos: Broken Packages."
        if nimbleNonexistent.len > 0 and allowMissingNimble:
          warn "Missing Nimble files:\n" & nimbleNonexistent.join("\n  ")
          warn "Missing Nimble files count: " & $nimbleNonexistent.len & " of " & $pckgsList.len
        else:
          doAssert nimbleNonexistent.len == 0, "Missing Nimble files: Broken Packages."

    else:
      {.hint: "Compile with SSL to do checking of Repo URLs On-Line: '-d:ssl'.".}


report.close()
{.hints: off.}
