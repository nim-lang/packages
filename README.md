# Nim packages [![Build Status](https://travis-ci.org/nim-lang/packages.svg?branch=master)](https://travis-ci.org/nim-lang/packages)

This is a central listing of all packages for
[Nimble](https://github.com/nim-lang/nimble), a package manager for the
[Nim programming language](http://nim-lang.org).

An overview of all Nimble packages is available in the 
[library documentation](https://nim-lang.org/docs/lib.html#nimble).

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
  * web    - An optional url for humans to read additional information about
             the package.

Your packages may be removed if the url stops working. It goes without saying
that your pull request will not be accepted unless you fill out all of the
above required fields correctly, the package that ``url`` points to must also
contain a .nimble file, or else it will be rejected.

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