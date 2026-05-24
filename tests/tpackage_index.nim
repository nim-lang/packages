import std/json
import std/os
import std/strutils
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


  test "rebuild regenerates packages.json explicitly":
    let dir = tempDir("nim-packages-index-rebuild")
    let manifestPath = dir / "packages.json"

    writeJsonFile(manifestPath, %*[
      packageNode("Beta"),
      packageNode("Alpha")
    ])
    runOk("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " split packages.json pkgs", dir)
    removeFile(manifestPath)

    runOk("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " rebuild pkgs packages.json", dir)

    let rebuilt = parseFile(manifestPath)
    check rebuilt.len == 2
    check rebuilt[0]["name"].getStr() == "Alpha"
    check rebuilt[1]["name"].getStr() == "Beta"

  test "no args prints usage":
    let dir = tempDir("nim-packages-index-help")
    let output = commandOutput("nim r -d:ssl " & quoteShell(root / "package_index.nim"), dir)
    check output.contains("Usage:")
    check output.contains("package_index combine [pkgs-dir] [packages.json]")
    check output.contains("package_index rebuild [pkgs-dir] [packages.json]")


  test "sync-git defaults to master versus HEAD":
    let dir = tempDir("nim-packages-index-sync-default-revs")
    let manifestPath = dir / "packages.json"

    git(["init", "-q", "-b", "master"], dir)
    git(["config", "user.name", "test"], dir)
    git(["config", "user.email", "test@example.com"], dir)

    writeJsonFile(manifestPath, %*[packageNode("Alpha")])
    runOk("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " split packages.json pkgs", dir)
    git(["add", "packages.json", "pkgs"], dir)
    git(["commit", "-q", "-m", "base"], dir)

    git(["checkout", "-q", "-b", "feature"], dir)
    writeJsonFile(manifestPath, %*[
      packageNode("Alpha"),
      packageNode("Gamma")
    ])

    let output = commandOutput("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " sync-git packages.json pkgs", dir)

    check fileExists(dir / "pkgs" / "g" / "Gamma" / "package.json")
    check output.contains("Sync: add Gamma from packages.json to pkgs")

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

    let output = commandOutput("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " sync-git " & baseRev & " " & headRev & " packages.json pkgs", dir)

    check fileExists(dir / "pkgs" / "a" / "Alpha" / "package.json")
    check fileExists(dir / "pkgs" / "g" / "Gamma" / "package.json")
    check output.contains("Sync: add Gamma from packages.json to pkgs")

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

    let output = commandOutput("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " sync-git " & inconsistentRev & " " & headRev & " packages.json pkgs", dir)

    check fileExists(dir / "pkgs" / "f" / "Foo" / "package.json")
    check output.contains("Sync: add Foo from packages.json to pkgs")

  test "add writes pkgs without regenerating packages.json":
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
    check manifest.len == 1
    check manifest[0]["name"].getStr() == "Alpha"

  test "remove deletes from pkgs without regenerating packages.json":
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
    check manifest.len == 2
    check manifest[0]["name"].getStr() == "Alpha"
    check manifest[1]["name"].getStr() == "Beta"


  test "create-alias prompts for alias metadata without regenerating packages.json":
    let dir = tempDir("nim-packages-index-create-alias")
    let manifestPath = dir / "packages.json"
    let shardRoot = dir / "pkgs"

    writeJsonFile(manifestPath, %*[packageNode("Alpha")])
    runOk("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " split packages.json pkgs", dir)

    runOk("""
cat <<'EOF' | nim r -d:ssl """ & quoteShell(root / "package_index.nim") & """ create-alias pkgs packages.json
AlphaOld
Alpha
EOF
""", dir)

    check fileExists(shardRoot / "a" / "AlphaOld" / "package.json")
    let created = parseFile(shardRoot / "a" / "AlphaOld" / "package.json")
    check created["name"].getStr() == "AlphaOld"
    check created["alias"].getStr() == "Alpha"
    check not created.hasKey("url")

    let manifest = parseFile(manifestPath)
    check manifest.len == 1
    check manifest[0]["name"].getStr() == "Alpha"

  test "create prompts for metadata without regenerating packages.json":
    let dir = tempDir("nim-packages-index-create")
    let manifestPath = dir / "packages.json"
    let shardRoot = dir / "pkgs"

    writeJsonFile(manifestPath, %*[packageNode("Alpha")])
    runOk("nim r -d:ssl " & quoteShell(root / "package_index.nim") &
      " split packages.json pkgs", dir)

    runOk("""
cat <<'EOF' | nim r -d:ssl """ & quoteShell(root / "package_index.nim") & """ create pkgs packages.json
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
    check manifest.len == 1
    check manifest[0]["name"].getStr() == "Alpha"
