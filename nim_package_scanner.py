#!/usr/bin/env python

"""
A very simple Nim package scanner.

Scan the package list from:
https://github.com/nim-lang/packages/blob/master/packages.json

Check for packages hosted on GitHub for:
    * Missing/unknown license
    * Missing description
    * Missing name
    * Missing/unknown method
    * Latest release

Usage: ./nim_package_scanner.py <github_token>

Copyright 2015 Federico Ceratto <federico.ceratto@gmail.com>
Released under GPLv3 License, see /usr/share/common-licenses/GPL-3
"""

from argparse import ArgumentParser
import requests
from setproctitle import setproctitle
from github import Github, UnknownObjectException
import logging

log = logging.getLogger(__name__)

PKG_LIST_URL = "https://raw.githubusercontent.com/nim-lang/packages/" \
    "master/packages.json"

# non-exhaustive list of known licenses
LICENSES = set((
    'Allegro 4 Giftware',
    'BSD',
    'BSD3',
    'CC0',
    'GPL',
    'GPLv2',
    'GPLv3',
    'LGPLv2',
    'LGPLv3',
    'MIT',
    'MS-PL',
    'WTFPL',
    'libpng'
    'zlib',
))


def setup_logging(debug):
    lvl = logging.DEBUG if debug else logging.INFO
    log.setLevel(lvl)
    ch = logging.StreamHandler()
    ch.setLevel(lvl)
    formatter = logging.Formatter('%(message)s')
    # formatter = logging.Formatter('%(name)s %(levelname)s %(message)s')
    ch.setFormatter(formatter)
    log.addHandler(ch)


def parse_args():
    """Parse CLI options and arguments

    :returns: args object
    """
    ap = ArgumentParser()
    ap.add_argument('-d', '--debug', action='store_true')
    ap.add_argument('github_token')
    args = ap.parse_args()
    return args


def main():
    args = parse_args()
    setup_logging(args.debug)
    setproctitle(__name__)

    r = requests.get(PKG_LIST_URL)
    packages = r.json()
    packages = sorted(packages, key=lambda p: p['name'])

    ghclient = Github(args.github_token)
    for pdata in packages:
        check_package(ghclient, pdata)


def check_package(ghclient, pdata):
    """Check Nim package"""
    if 'name' not in pdata:
        print "missing name in %r" % pdata
        return

    name = pdata['name']
    if 'web' not in pdata:
        print "%-30s missing web URL" % name
        return

    if 'method' not in pdata:
        print "%-30s missing method" % name

    elif pdata['method'] != 'git':
        print "%-30s incorrect method: %s" % (name, pdata['method'])

    if not pdata.get('description', None):
        print "%-30s missing or incorrect description" % name

    if 'license' not in pdata:
        print "%-30s missing license" % name

    elif pdata['license'] not in LICENSES:
        print "%-30s unknown or incorrect license: %s" % (name,
                                                            pdata['license'])
    url = pdata['web']
    if not url.startswith(('http://github.com/', 'https://github.com/')):
        print "%-30s not on GitHub" % name
        return

    try:
        repo_name = url.split('/',3)[-1]
        gh_repo = ghclient.get_repo(repo_name)
        tags = [tag.name for tag in gh_repo.get_tags()]
        if tags:
            last_tag = max(tags)
            print "%-30s %s" % (name, last_tag)
        else:
            print "%-30s not released" % name

    except UnknownObjectException as e:
        if e.data['message'] == 'Not Found':
            print "%-30s is missing from GitHub!" % name
        else:
            print "%-30s cannot be fetched: %s" % (name, e.data)


if __name__ == '__main__':
    main()
