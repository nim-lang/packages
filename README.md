# Nim packages

This is a central listing of all packages for
[Nimble](https://github.com/nim-lang/nimble), a package manager for the
[Nim programming language](http://nim-lang.org).

An overview of all packages is available at https://nimble.directory or https://nimpkgs.org.

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

## Sharded package metadata

This repo now supports per-package metadata files under:

```text
pkgs/<first-letter>/<package-name>/package.json
```

For example:

```text
pkgs/a/AccurateSums/package.json
pkgs/n/nimble/package.json
```

The long-term direction is for this sharded `pkgs/` layout to become the
canonical source of package metadata.

For now, this repository keeps both `packages.json` and `pkgs/` in sync to
support existing tooling and workflows that still update `packages.json`
directly, including current `nimble publish` behavior.

Split `packages.json` into shard files:

```sh
nim r package_index.nim split packages.json pkgs
```

Add one package from an existing metadata JSON file:

```sh
nim r package_index.nim add path/to/package.json pkgs packages.json
```

Create one package interactively:

```sh
nim r package_index.nim create pkgs packages.json
```

This prompts for the package metadata fields, writes the new package into
`pkgs/` first, and then regenerates `packages.json` from the sharded metadata.

Remove one package:

```sh
nim r package_index.nim remove PackageName pkgs packages.json
```

Build `packages.json` from those shard folders:

```sh
nim r package_index.nim
```

The combine step also validates each shard's JSON metadata shape before writing
the merged manifest.

In CI, PR validation is handled by the scanner directly from the git merge base:

```sh
nim test
```

On push, CI also keeps `packages.json` and `pkgs/` in sync by generating the
missing counterpart when it can determine a single authoritative side.

The current push-sync rules are:

* if only `packages.json` changed, CI regenerates `pkgs/`
* if only `pkgs/` changed, CI regenerates `packages.json`
* if both changed and already agree, CI accepts them as-is
* if the checked-out tree inherited one-sided drift from an earlier commit,
  CI repairs the missing side when the changed side is a strict superset of the
  unchanged side and all overlapping package metadata matches
* if both sides contain conflicting metadata, CI fails and requires a manual
  fix

The test suite lives under `tests/` and can be run locally with:

```sh
nim test
```

# License

* `package_scanner.nim` - [GPLv3](LICENSE-GPLv3.txt)
* Everything else - [CC-BY-4.0](LICENSE.txt)

