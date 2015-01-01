# Nim packages

This is a central listing of all packages for
[Nimble](https://github.com/nimrod-code/nimble), a package manager for the
[Nim programming language](http://nim-lang.org).

## Adding your own package
To add your own package, fork this repository, edit
[packages.json](packages.json) and make a pull request.

[Packages.json](packages.json) is a simple array of objects. Each package
object should have the following fields (unless the field is marked as
optional):
  
  * name   - The name of the package, this should match the name in the package's
             babel file.
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
