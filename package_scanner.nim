# A very simple Nim package scanner.
#
# Scans the package list from this repository.
#
# Check the packages for:
#  * Missing name
#  * Missing/unknown method
#  * Missing/unreachable repository
#  * Missing tags
#  * Missing description
#  * Missing/unknown license
#  * Insecure git:// url on GitHub
#
# Usage: nim r -d:ssl package_scanner.nim
#
# Copyright 2015 Federico Ceratto <federico.ceratto@gmail.com>
# Released under GPLv3 License, see /usr/share/common-licenses/GPL-3

import std/[httpclient, net, json, os, sets, strutils]

const licenses = [
    "allegro 4 giftware",
    "apache license 2.0",
    "apache",
    "apache2",
    "apache 2.0",
    "apache-2.0",
    "apache-2.0 license",
    "apache version 2.0",
    "mit or apache 2.0",
    "apache license 2.0 or mit",
    "mit or apache license 2.0",
    "(mit or apache license 2.0) and simplified bsd",
    "lxxsdt-mit",
    "lgplv2.1",
    "0bsd",
    "bsd",
    "bsd2",
    "bsd-2",
    "bsd3",
    "bsd-3",
    "bsd 3-clause",
    "bsd-3-clause",
    "boost",
    "boost-1.0",
    "bsl",
    "bsl-1.0",
    "2-clause bsd",
    "cc0",
    "cc0-1.0",
    "gpl",
    "gpl2",
    "gpl-2.0-only",
    "gpl3",
    "gplv2",
    "gplv3",
    "gplv3+",
    "gpl-2.0",
    "agpl-3.0",
    "gpl-3.0",
    "gpl-3.0-or-later",
    "gpl-3.0-only",
    "lgplv3 or gplv2",
    "apache 2.0 or gplv2",
    "lgpl-2.1-or-later",
    "lgpl with static linking exception",
    "gnu lesser general public license v2.1",
    "openldap",
    "lgpl",
    "lgplv2",
    "lgplv3",
    "lgpl-2.1",
    "lgpl-3.0",
    "agplv3",
    "mit",
    "mit/isc",
    "ms-pl",
    "mpl",
    "mplv2",
    "mpl-2.0",
    "mpl 2.0",
    "epl-2.0",
    "eupl-1.2",
    "wtfpl",
    "libpng",
    "fontconfig",
    "zlib",
    "isc",
    "ppl",
    "hydra",
    "openssl and ssleay",
    "unlicense",
    "public domain",
    "proprietary",
  ]

proc canFetchNimbleRepository(name: string, urlJson: JsonNode): bool =
  # TODO: Make this check the actual repo url and check if there is a
  #       nimble file in it
  result = true
  var url: string
  var client = newHttpClient(timeout = 100_000)

  if not urlJson.isNil:
    url = urlJson.str
    if url.startsWith("https://github.com"):
      if existsEnv("GITHUB_TOKEN"):
        client.headers = newHttpHeaders({"authorization": "Bearer " & getEnv("GITHUB_TOKEN")})
    try:
      discard client.getContent(url)
    except TimeoutError:
      echo "W: ", name, ": Timeout error fetching repo ", url, " ", getCurrentExceptionMsg()
    except HttpRequestError:
      echo "W: ", name, ": HTTP error fetching repo ", url, " ", getCurrentExceptionMsg()
    except AssertionDefect:
      echo "W: ", name, ": httpclient error fetching repo ", url, " ", getCurrentExceptionMsg()
    except:
      echo "W: Unkown error fetching repo ", url, " ", getCurrentExceptionMsg()
    finally:
      client.close()

proc verifyAlias(pkg: JsonNode, result: var int) =
  if not pkg.hasKey("name"):
    echo "E: Missing alias' package name"
    inc result
  # TODO: Verify that 'alias' points to a known package.

proc check(): int =
  var name: string
  var names = initHashSet[string]()

  for pkg in parseJson(readFile(getCurrentDir() / "packages.json")):
    name = if pkg.hasKey("name"): pkg["name"].str else: ""
    if pkg.hasKey("alias"):
      verifyAlias(pkg, result)
    else:
      if name.len == 0:
        echo "E: missing package name"
        inc result
      elif not pkg.hasKey("method"):
        echo "E: ", name, " has no method"
        inc result
      elif pkg["method"].str notin ["git", "hg"]:
        echo "E: ", name, " has an unknown method: ", pkg["method"].str
        inc result
      elif not pkg.hasKey("url"):
        echo "E: ", name, " has no URL"
        inc result
      elif not pkg.hasKey("tags"):
        echo "E: ", name, " has no tags"
        inc result
      elif not pkg.hasKey("description"):
        echo "E: ", name, " has no description"
        inc result
      elif pkg.hasKey("description") and pkg["description"].str == "":
        echo "E: ", name, " has empty description"
        inc result
      elif not pkg.hasKey("license"):
        echo "E: ", name, " has no license"
        inc result
      elif pkg["url"].str.normalize.startsWith("git://github.com/"):
        echo "E: ", name, " has an insecure git:// URL instead of https://"
        inc result
      elif pkg["license"].str.toLowerAscii notin licenses:
        echo "E: ", name, " has an unexpected license: ", pkg["license"]
        inc result
      elif pkg.hasKey("web") and not canFetchNimbleRepository(name, pkg["web"]):
        echo "W: Failed to fetch source code repo for ", name

    if name.normalize notin names:
      names.incl name.normalize
    else:
      echo("E: ", name, ": a package by that name already exists.")
      inc result

  echo "\nProblematic packages count: ", result


when isMainModule:
  quit(check())
