# Nim packages [![Build Status](https://travis-ci.org/nim-lang/packages.svg?branch=master)](https://travis-ci.org/nim-lang/packages)

This is a central listing of all packages for
[Nimble](https://github.com/nim-lang/nimble), a package manager for the
[Nim programming language](http://nim-lang.org).

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

### Requirements

While we really appreciate your contribution, please ensure that you package matches the following requirements: other developers rely on your package. Non-compliant packages might be removed with no warning.

* The URL should work, a .nimble file should be present and the package should be installable
* The package should build correctly with the latest Nim release
* The package should not contain files without a license or in breach of 3rd parties licensing
* Non-mature packages should be flagged as such, especially if they perform security-critical tasks (e.g. encryption)
* If abandoning a package, please tag it as "abandoned".
