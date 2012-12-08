# Nimrod packages

This is a central listing of all packages for babel.

## Adding your own package
To add your own package, fork this repository, edit packages.json and make
a pull request.

Packages.json is a simple array of objects. Each package object should have the
following fields:
  
  * name   - The name of the package, this should match the name in the package's
             babel file.
  * url    - The url from which to retrieve the package.
  * method - The method that should be used to retrieve this package. Currently
             only "git" is supported.
  * tags   - A list of tags describing this package.
  * description - A description of this package.
  * license - The license of the source code in the package.

Your packages may be removed if the url stops working. It goes without
saying that your pull request will not be accepted unless you fill out all of
the above fields correctly, the package that ``url`` points to must also contain
a babel file, or else it will be rejected.