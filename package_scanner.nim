
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
#
# Usage: nim c -d:ssl -r package_scanner.nim
#
# Copyright 2015 Federico Ceratto <federico.ceratto@gmail.com>
# Released under GPLv3 License, see /usr/share/common-licenses/GPL-3

import httpclient
import net
import json
import os
import sets
import strutils

const

  LICENSES = @[
    "Allegro 4 Giftware",
    "BSD",
    "BSD3",
    "CC0",
    "GPL",
    "GPLv2",
    "GPLv3",
    "LGPLv2",
    "LGPLv3",
    "MIT",
    "MS-PL",
    "WTFPL",
    "libpng",
    "zlib"
  ]

  VCS_TYPES = @["git", "hg"]

proc canFetchNimbleRepository(name: string, urlJson: JsonNode): bool =
  # The fetch is a lie!
  # TODO: Make this check the actual repo url and check if there is a
  #       nimble file in it
  result = true
  var url: string

  if not urlJson.isNil:
    url = urlJson.str

    try:
      discard getContent(url, timeout=5000)
    except HttpRequestError, TimeoutError:
      echo "E: ", name, ": unable to fetch repository ", url, " ",
           getCurrentExceptionMsg()
      result = false
    except AssertionError:
      echo "W: ", name, ": httpclient failed ", url, " ",
           getCurrentExceptionMsg()
    except:
      echo "W: Another error attempting to request: ", url
      echo "  Error was: ", getCurrentExceptionMsg()


proc check(): int =
  var
    name: string

  echo ""

  let
    pkg_list = parseJson(readFile(getCurrentDir() / "packages.json"))

  var names = initSet[string]()

  for pdata in pkg_list:
    name = if pdata.hasKey("name"): pdata["name"].str else: nil

    if name.isNil:
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

    elif not canFetchNimbleRepository(name, pdata["web"]):
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

    else:
      # Other warnings should go here
      if not (pdata["license"].str in LICENSES):
        echo "W: ", name, " has an unexpected license: ", pdata["license"]

    if name.normalize notin names:
      names.incl(name.normalize)
    else:
      echo("E: ", name, ": a package by that name already exists.")
      result.inc()

  echo ""
  echo "Problematic packages count: ", result


when isMainModule:
  quit(check())

