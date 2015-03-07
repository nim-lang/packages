
# A very simple Nim package scanner.
#
# Scan the package list from:
# https://github.com/nim-lang/packages/blob/master/packages.json
#
# Check the packages for:
#  * Missing/unknown license
#  * Missing description
#  * Missing name
#  * Missing/unknown method
#  * Missing/unreachable repository
#
# Usage: nim c -d:ssl -r package_scanner.nim
#
# Copyright 2015 Federico Ceratto <federico.ceratto@gmail.com>
# Released under GPLv3 License, see /usr/share/common-licenses/GPL-3

import httpclient
import net
import json

const
  PKG_LIST_URL = "https://raw.githubusercontent.com/nim-lang/packages/master/packages.json"

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

proc check(): int =
  var
    name: string
    url: string


  echo ""
  let
    pkg_list = parseJson(getContent(PKG_LIST_URL))

  for pdata in pkg_list:
    if not pdata.hasKey("name"):
      echo "E: missing package name"
      result.inc()
      continue

    name = pdata["name"].str
    if not pdata.hasKey("method"):
      echo "E: ", name, "has no method"
      result.inc()

    elif not (pdata["method"].str in VCS_TYPES):
      echo "E: ", name, "has an unknown method: ", pdata["method"].str
      result.inc()

    if not pdata.hasKey("license"):
      echo "E: ", name, "has no license"
      result.inc()
    elif not (pdata["license"].str in LICENSES):
      echo "W: ", name, "has an unexpected license: ", pdata["license"]

    if not pdata.hasKey("description"):
      echo "E: ", name, "has no description"
      result.inc()

    if not pdata.hasKey("web"):
      echo "E: ", name, "has no URL"
      result.inc()
      continue

  for pdata in pkg_list:
    if pdata.hasKey("name") and pdata.hasKey("web"):
      name = pdata["name"].str
      url = pdata["web"].str
      try:
        discard getContent(url, timeout=3000)

      except HttpRequestError, TimeoutError, AssertionError:
        echo "E: ", name, ": unable to fetch repository ", url, " ", getCurrentExceptionMsg()
        result.inc()

  echo "Error count: ", result
  return

when isMainModule:
  quit(check())

