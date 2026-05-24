import std/json
import std/os
import std/unittest

import helpers

let root = rootDir()

suite "package_index":
  test "split and combine roundtrip":
    let dir = tempDir("nim-packages-index-roundtrip")
    let manifestPath = dir / "packages.json"
    let splitRoot = dir / "pkgs"
    let combinedPath = dir / "combined.json"

    writeJsonFile(manifestPath, %*[
      packageNode("Beta"),
      packageNode("Alpha")
    ])

    runOk("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " split packages.json pkgs", dir)

    check fileExists(splitRoot / "a" / "Alpha" / "package.json")
    check fileExists(splitRoot / "b" / "Beta" / "package.json")

    runOk("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " pkgs combined.json", dir)

    let combined = parseFile(combinedPath)
    check combined.kind == JArray
    check combined.len == 2
    check combined[0]["name"].getStr() == "Alpha"
    check combined[1]["name"].getStr() == "Beta"

  test "sync packages.json to pkgs":
    let dir = tempDir("nim-packages-index-sync")
    let manifestPath = dir / "packages.json"

    git(["init", "-q"], dir)
    git(["config", "user.name", "test"], dir)
    git(["config", "user.email", "test@example.com"], dir)

    writeJsonFile(manifestPath, %*[packageNode("Alpha")])
    git(["add", "packages.json"], dir)
    git(["commit", "-q", "-m", "base"], dir)
    let baseRev = commandOutput("git rev-parse HEAD", dir)

    writeJsonFile(manifestPath, %*[
      packageNode("Alpha"),
      packageNode("Gamma")
    ])
    git(["add", "packages.json"], dir)
    git(["commit", "-q", "-m", "add gamma"], dir)
    let headRev = commandOutput("git rev-parse HEAD", dir)

    runOk("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " sync " & baseRev & " " & headRev & " packages.json pkgs", dir)

    check fileExists(dir / "pkgs" / "a" / "Alpha" / "package.json")
    check fileExists(dir / "pkgs" / "g" / "Gamma" / "package.json")

  test "sync repairs inherited packages.json-only drift":
    let dir = tempDir("nim-packages-index-inherited-drift")
    let manifestPath = dir / "packages.json"

    git(["init", "-q"], dir)
    git(["config", "user.name", "test"], dir)
    git(["config", "user.email", "test@example.com"], dir)

    writeJsonFile(manifestPath, %*[packageNode("Alpha")])
    runOk("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " split packages.json pkgs", dir)
    git(["add", "packages.json", "pkgs"], dir)
    git(["commit", "-q", "-m", "base"], dir)

    writeJsonFile(manifestPath, %*[
      packageNode("Alpha"),
      packageNode("Foo")
    ])
    git(["add", "packages.json"], dir)
    git(["commit", "-q", "-m", "manifest only"], dir)
    let inconsistentRev = commandOutput("git rev-parse HEAD", dir)

    writeFile(dir / "README.md", "trigger push sync\n")
    git(["add", "README.md"], dir)
    git(["commit", "-q", "-m", "tooling only"], dir)
    let headRev = commandOutput("git rev-parse HEAD", dir)

    runOk("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " sync " & inconsistentRev & " " & headRev & " packages.json pkgs", dir)

    check fileExists(dir / "pkgs" / "f" / "Foo" / "package.json")

  test "add writes pkgs first and regenerates packages.json":
    let dir = tempDir("nim-packages-index-add")
    let manifestPath = dir / "packages.json"
    let shardRoot = dir / "pkgs"
    let metadataPath = dir / "new-package.json"

    writeJsonFile(manifestPath, %*[packageNode("Alpha")])
    runOk("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " split packages.json pkgs", dir)

    writeJsonFile(metadataPath, packageNode("Beta"))

    runOk("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " add new-package.json pkgs packages.json", dir)

    check fileExists(shardRoot / "b" / "Beta" / "package.json")
    let manifest = parseFile(manifestPath)
    check manifest.len == 2
    check manifest[0]["name"].getStr() == "Alpha"
    check manifest[1]["name"].getStr() == "Beta"

  test "remove deletes from pkgs and regenerates packages.json":
    let dir = tempDir("nim-packages-index-remove")
    let manifestPath = dir / "packages.json"
    let shardRoot = dir / "pkgs"

    writeJsonFile(manifestPath, %*[
      packageNode("Alpha"),
      packageNode("Beta")
    ])
    runOk("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " split packages.json pkgs", dir)

    runOk("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " remove Beta pkgs packages.json", dir)

    check not fileExists(shardRoot / "b" / "Beta" / "package.json")
    let manifest = parseFile(manifestPath)
    check manifest.len == 1
    check manifest[0]["name"].getStr() == "Alpha"

  test "create prompts for metadata and regenerates packages.json":
    let dir = tempDir("nim-packages-index-create")
    let manifestPath = dir / "packages.json"
    let shardRoot = dir / "pkgs"

    writeJsonFile(manifestPath, %*[packageNode("Alpha")])
    runOk("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " split packages.json pkgs", dir)

    runOk("""
cat <<'EOF' | nim r -d:ssl """ & quoteShell(root / "package_index.nim") & """ create pkgs packages.json
n
Beta
https://example.com/beta
git
demo, cli
Beta package
MIT
https://example.com/beta/site

EOF
""", dir)

    check fileExists(shardRoot / "b" / "Beta" / "package.json")
    let created = parseFile(shardRoot / "b" / "Beta" / "package.json")
    check created["name"].getStr() == "Beta"
    check created["tags"].len == 2
    check created["web"].getStr() == "https://example.com/beta/site"
    check not created.hasKey("doc")

    let manifest = parseFile(manifestPath)
    check manifest.len == 2
    check manifest[0]["name"].getStr() == "Alpha"
    check manifest[1]["name"].getStr() == "Beta"
