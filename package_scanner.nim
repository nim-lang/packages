## Package JSON Linter
## ===================
##
## - Tests the ``package.json`` list from this repository.
##
## Check the packages for:
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
## - Works online/offline
##
## Use
## ---
##
## - Off-line: ``nim c -r package_scanner2.nim`` (Faster, wont use Internet).
## - On-line: ``nim c -d:ssl -r package_scanner2.nim`` (Checks URLs).
##
## Credits
## -------
##
## Based and inspired on a previous ``package_scanner.nim`` from:
## Copyright 2015 Federico Ceratto <federico.ceratto@gmail.com>
## Released under GPLv3 License, see /usr/share/common-licenses/GPL-3
import httpclient, json, net, os, sets, strutils, logging, unittest, ospaths, sequtils

const
<<<<<<< HEAD
  allow_broken_url* = true     ## Allow broken Repo URLs
  allow_missing_nimble* = true ## Allow missing ``*.nimble`` files
  check_nimble_file* = true    ## Check if repos have ``*.nimble`` file
  http_timeout* = 2_000        ## Timeout. Below ~2000 false positives happen?
  tags_max_len* = 32           ## Maximum lenght for the string in tags
  tags_maximum* = 16           ## Maximum number of tags allowed on the list
  vcs_types* = ["git", "hg"]   ## Valid known Version Control Systems.
  tags_blacklist* = ["nimrod", "nim"] ## Tags that should be not allowed.
  keys_required* = ["name", "url", "method", "tags", "description", "license"]
  packages_json_str = readFile(currentSourcePath().parentDir / "packages.json")
  hosts_skip* = [
    "https://bitbucket",
    "https://gitlab.3dicc",
    "https://mahlon@bitbucket",
    "https://notabug",
  ] ## Hostnames to skip checks, for reliability, wont like direct HTTP GET?.
  licenses* = [
    "allegro 4 giftware",
    "apache",
    "apache2",
    "apache2.0",
    "apache 2.0",
    "apache version 2.0",
    "apache license 2.0",
    "bsd",
    "bsd2",
    "bsd-2",
    "bsd3",
    "bsd-3",
    "bsd 2-clause",
    "bsd 3-clause",
    "cc0",
    "gpl",
    "gpl2",
    "gpl3",
    "gplv2",
    "gplv3",
    "lgpl",
    "lgplv2",
    "lgplv2.1",
    "lgplv3",
    "mit",
    "ms-pl",
    "mpl",
    "wtfpl",
    "libpng",
    "zlib",
    "isc",
    "unlicense",
    # Not concrete Licenses, but some rare cases observed on the JSON.
    "fontconfig",
    "public domain",
    "lgplv3 or gplv2",
    "openssl and ssleay",
    "apache 2.0 or gplv2",
    "mit or apache 2.0",
    "lgpl with static linking exception",
  ]  ## All valid known licences for Nimble packages, on lowercase.

let
  packages_json* = parseJson(packages_json_str).getElems         ## ``string`` to ``JsonNode``
  pckgs_list* = filter_it(packages_json, not it.hasKey("alias")) ## Packages, without Aliases
  alias_list* = filter_it(packages_json, it.hasKey("alias"))     ## Aliases, without Packages
  client* = newHttpClient(timeout = http_timeout) ## HTTP Client with Timeout
  console_logger* = newConsoleLogger(fmtStr = verboseFmtStr) ## Basic Logger
addHandler(console_logger)
=======
  LICENSES = @[
    "Allegro 4 Giftware",
    "Apache License 2.0",
    "BSD",
    "BSD2",
    "BSD3",
    "CC0",
    "GPL",
    "GPLv2",
    "GPLv3",
    "LGPLv2",
    "LGPLv3",
    "MIT",
    "MS-PL",
    "MPL",
    "WTFPL",
    "libpng",
    "zlib",
    "ISC",
    "Unlicense"
  ]
  VCS_TYPES = @["git", "hg"]
>>>>>>> efdcc9f9315e9f3c026bfe101b61ce88f01d1db6

func strip_ending_slash*(url: string): string =
  ## Strip the ending '/' if any else return the same string.
  if url[url.len - 1] == '/':      # if ends in '/'
    result = url[0 .. url.len - 2] # Remove it.
  else:
    result = url

func preprocess_url*(url, name: string): string =
  ## Take **Normalized** URL & Name return Download link. GitHub & GitLab supported.
  if url.startswith("https://github.com/"):
    result = url.replace("https://github.com/", "https://raw.githubusercontent.com/")
    result = strip_ending_slash(result)
    result &= "/master/" & name & ".nimble"
  elif url.startswith("https://0xacab.org/") or url.startswith("https://gitlab."):
    result = strip_ending_slash(result)
    result &= "/raw/master/" & name & ".nimble"

proc nimble_file_exists*(url, name: string): string =
  ## Take **Normalized** URL & Name try to Fetch the Nimble file. Needs SSL.
  debug url
  if url.startswith("http"):
    try:
      let urly = preprocess_url(url, name)
      doAssert urly.len > 0, "GIT or HG Hosting not supported: " & url
      doAssert client.get(url).status == $Http200 # Check that Repo Exists.
      result = urly
    except TimeoutError, HttpRequestError, AssertionError:
      warn("HttpClient request error fetching repo: " & url, getCurrentExceptionMsg())
    except:
      warn("Unkown Error fetching repo: " & url, getCurrentExceptionMsg())
  else:
    result = url  # SSH or other non-HTTP kinda URLs?

proc git_repo_exists*(url: string): string =
  ## Take **Normalized** URL try to Fetch the Git repo index page. Needs SSL.
  if url.startswith("http"):
    try:
      doAssert client.get(url).status == $Http200 # Check that Repo Exists.
      result = url
    except TimeoutError, HttpRequestError, AssertionError:
      warn("HttpClient request error fetching repo: " & url, getCurrentExceptionMsg())
    except:
      warn("Unkown Error fetching repo: " & url, getCurrentExceptionMsg())
  else:
    result = url  # SSH or other non-HTTP kinda URLs?


<<<<<<< HEAD
suite "Packages consistency testing":

  var
    names = initSet[string]()
    urls = initSet[string]()

  test "Check Basic Structure":
    for pdata in pckgs_list:
      for key in keys_required:
        if pdata.hasKey(key):
          if key == "tags":
            check pdata[key].kind == JArray  # Tags is array
            check pdata[key].len > 0         # Tags can not be empty
          else:
            check pdata[key].kind == JString # Other keys are string
            check pdata[key].str.len > 0     # No field can be empty string
        else:
          fatal("Missing Keys on the JSON (making it invalid): " & $key)

  test "Check Tags":
    for pdata in pckgs_list:
      check pdata["tags"].len > 0            # Minimum number of tags
      check tags_maximum > pdata["tags"].len # Maximum number of tags
      for tagy in pdata["tags"]:
        check tagy.str.strip.len >= 1     # No empty string tags
        check tags_max_len > tagy.str.len # Maximum lenght of tags
        check tagy.str.strip.toLowerAscii notin tags_blacklist

  test "Check Methods":
    for pdata in pckgs_list:
      var metod = pdata["method"]
      check metod.kind == JString
      check metod.str.len == pdata["method"].str.strip.len
      check metod.str in vcs_types

  test "Check Licenses":
    for pdata in pckgs_list:
      var license = pdata["license"]
      check license.kind == JString
      check license.str.len == license.str.strip.len
      check(not license.str.strip.startsWith("the ")) # Dont use "The GPL" etc
      check license.str.normalize in licenses

  test "Check Names":
    for pdata in pckgs_list:
      var name = pdata["name"]
      check name.kind == JString
      check name.str.len == name.str.strip.len # No Whitespace
      if name.str.strip notin names:
        names.incl name.str.strip.toLowerAscii
      else:
        fatal("Package by that name already exists: " & $name)

  test "Check Webs":
    for pdata in pckgs_list:
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
    for pdata in pckgs_list:
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
    doAssert alias_list.len > 0, $alias_list
    for pdata in alias_list:
      var alias = pdata["alias"].str
      check alias.len == alias.strip.len
      check alias.strip.toLowerAscii in names  # Alias must relate to a name

  test "Check URLs On-Line":
    when defined(ssl):
      var existent, nonexistent, nimble_existent, nimble_nonexistent: seq[string]
      for pdata in pckgs_list:
        var
          skip: bool
          url = pdata["url"].str.strip.toLowerAscii
          name = pdata["name"].str.normalize

        # Some hostings randomly timeout or fail sometimes, skip them.
        for skipurl in hosts_skip:
          if url.startsWith(skipurl):
            skip = true
        if skip: continue

        # Check that the Git Repo actually exists.
        var this_repo = git_repo_exists(url=url) # Fetch test.
        if this_repo.len > 0:
          existent.add this_repo
        else:
          nonexistent.add url

        # Check for Nimble Files on Existent Repos.
        if this_repo.len > 0 and check_nimble_file:
          var this_nimble = nimble_file_exists(url=this_repo, name=name)
          if this_nimble.len > 0:
            nimble_existent.add this_nimble
          else:
            nimble_nonexistent.add url

      # Warn or Assert the possible errors at the end.
      if nonexistent.len > 0 and allow_broken_url:
        warn "Missing repos list:\n" & nonexistent.join("\n  ")
        warn "Missing repos count: " & $nonexistent.len & " of " & $pckgs_list.len
=======
proc check(): int =
  var name: string
  echo ""
  let pkg_list = parseJson(readFile(getCurrentDir() / "packages.json"))
  var names = initSet[string]()

  for pdata in pkg_list:
    name = if pdata.hasKey("name"): pdata["name"].str else: ""

    if pdata.hasKey("alias"):
      verifyAlias(pdata, result)
    else:
      if name == "":
        echo "E: missing package name"
        result.inc()
      elif not pdata.hasKey("method"):
        echo "E: ", name, " has no method"
        result.inc()
      elif not (pdata["method"].str in VCS_TYPES):
        echo "E: ", name, " has an unknown method: ", pdata["method"].str
        result.inc()
      elif not pdata.hasKey("url"):
        echo "E: ", name, " has no URL"
        result.inc()
      elif pdata.hasKey("web") and not canFetchNimbleRepository(name, pdata["web"]):
        result.inc()
      elif not pdata.hasKey("tags"):
        echo "E: ", name, " has no tags"
        result.inc()
      elif not pdata.hasKey("description"):
        echo "E: ", name, " has no description"
        result.inc()
      elif not pdata.hasKey("license"):
        echo "E: ", name, " has no license"
        result.inc()
      elif pdata["url"].str.normalize.startsWith("git://github.com/"):
        echo "E: ", name, " has an insecure git:// URL instead of https://"
        result.inc()
>>>>>>> efdcc9f9315e9f3c026bfe101b61ce88f01d1db6
      else:
        doAssert nonexistent.len == 0, "Missing repos: Broken Packages."
      if nimble_nonexistent.len > 0 and allow_missing_nimble:
        warn "Missing Nimble files:\n" & nimble_nonexistent.join("\n  ")
        warn "Missing Nimble files count: " & $nimble_nonexistent.len & " of " & $pckgs_list.len
      else:
        doAssert nimble_nonexistent.len == 0, "Missing Nimble files: Broken Packages."

    else:
      info "Compile with SSL to do checking of Repo URLs On-Line: '-d:ssl'."
