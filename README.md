# Nim packages [![Build Status](https://travis-ci.org/nim-lang/packages.svg?branch=master)](https://travis-ci.org/nim-lang/packages)

This is a central listing of all packages for
[Nimble](https://github.com/nim-lang/nimble), a package manager for the
[Nim programming language](http://nim-lang.org).

An overview of all packages is available at https://nimble.directory.

NOTE: The packages listed here are not peer-reviewed or otherwise screened. We try to keep the list up-to-date but we cannot guarantee quality or maturity of the packages.

## Adding your own package
To add your own package, fork this repository, edit
[packages.json](packages.json) and make a pull request.

[Packages.json](packages.json) is a simple array of objects. Each package
object should have the following fields (unless the field is marked as
optional):

  * name   - The name of the package, this should match the name in the package's
             nimble file.
  * url    - The url from which to retrieve the package.
  * method - The method that should be used to retrieve this package. Currently
             "git" and "hg" is supported.
  * tags   - A list of tags describing this package.
  * description - A description of this package.
  * license - The license of the source code in the package.
  * web    - An optional URL for humans to read additional information about
             the package.
  * doc    - An optional URL for humans to read the package HTML documentation
  * donations - A list of URLs that can be used to monetarily support the author of this package. Check [Accepting Donations](#accepting-donations)

### Requirements

While we really appreciate your contribution, please follow the requirements: other developers will rely on your package. Non-compliant packages might be removed with no warning.

* The URL should work, a .nimble file should be present and the package should be installable
* The package should build correctly with the latest Nim release
* The package should not contain files without a license or in breach of 3rd parties licensing
* Non-mature packages should be flagged as such by opening an issue here with a good explanation on how they are non-mature, especially if they perform security-critical tasks (e.g. encryption)
* If a vulnerability is found, make a patch release against the latest stable release (or more) that fixes the issue without introducing any other change.
* Tiny libraries should be avoided where possible
* Avoid having many dependencies. Use "when defined(...)" to enable optional features.
* If abandoning a package, please tag it as "abandoned"
* The package name should be unique and specific. Avoid overly generic names e.g. "math", "http"
* Provide a contact email address.
* Optionally try to support older Nim releases (6 months to 1 year)
* Optionally GPG-sign your releases
* Optionally follow [SemVer 2](http://semver.org)

Your packages may be removed if the url stops working. It goes without saying
that your pull request will not be accepted unless you fill out all of the
above required fields correctly, the package that ``url`` points to must also
contain a .nimble file, or else it will be rejected.

The requirements might change in future.

## Releasing a new package version

The version number in the directory is derived from git tags (not the `version` field in the `.nimble` script). To release a new version of a package, follow the [instructions from the Nimble readme](https://github.com/nim-lang/nimble#releasing-a-new-version):

> * Increment the version in your ``.nimble`` file.
> * Commit your changes.
> * Tag your release, by for example running ``git tag v0.2.0``.
> * Push your tags and commits.

## Renaming packages

To rename a package you will need to add a new entry for your package. Simply
perform the following steps:

* Duplicate your package's current entry.
* Remove every field in one of the entries apart from the `name` field.
* Add an `alias` field to that entry.
* Change the name in the other package entry.

For example:

```
...
  {
    "name": "myoldname",
    "alias": "mynewname"
  },
  {
    "name": "mynewname",
    "url": "...",
    "method": "git",
    ...
  },
...
```

## Accepting Donations

You can optionally link donation URLs that can be used by other users to support you. \
Try to link a mainstream donation website like BuyMeACoffee, Patreon or OpenCollective over less well-known ones to make it easier for others to support you.

Donation links must follow the following guidelines:
* They must be valid URLs
* They mustn't be malicious (see [Donation Abuse](#donation-abuse))
* If you decide to close your account on any of the websites you use to accept donations, you must remove the link from all your packages that still link to that URL.

This is a relatively new feature (as of 17th of August 2024, the time of writing this, it hasn't been merged into Nimble's master branch) and the vast majority of Nimble clients will simply ignore this field for now. Newer ones that are taken from a source like `choosenim` or from a rolling release Linux distribution's packages will likely receive this update shortly after the [pull request](https://github.com/nim-lang/nimble/pulls/1258) is merged.

If you wish to send a donation to a library's developer and are on a version of Nimble that supports this feature, run `nimble sponsor <name of library>`.

### Donation Abuse
Your package will be removed without notice if you attempt to use this feature maliciously (i.e, phishing via typosquatting or through another means) and you might be banned from adding your packages to the index for an indefinite period of time.

# License

* `package_scanner.nim` - [GPLv3](LICENSE-GPLv3.txt)
* Everything else - [CC-BY-4.0](LICENSE.txt)
