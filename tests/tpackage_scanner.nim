import std/json
import std/os
import std/strutils
import std/unittest

import helpers

let root = rootDir()

suite "package_scanner":
  test "check-pr rejects mixing new and modified packages":
    let temp = tempDir("nim-packages-scanner-pr")
    let originDir = temp / "origin"
    let workDir = temp / "work"
    let gitConfigPath = temp / "gitconfig"
    createDir(originDir)

    git(["init", "-q", "--bare", originDir], temp)
    runOk("git clone -q " & quoteShell(originDir) & " " & quoteShell(workDir), temp)

    git(["config", "user.name", "test"], workDir)
    git(["config", "user.email", "test@example.com"], workDir)

    writeJsonFile(workDir / "packages.json", %*[packageNode("Alpha", "alpha v1")])
    git(["add", "packages.json"], workDir)
    git(["commit", "-q", "-m", "base"], workDir)
    git(["branch", "-M", "master"], workDir)
    git(["push", "-q", "-u", "origin", "master"], workDir)

    writeJsonFile(workDir / "packages.json", %*[
      packageNode("Alpha", "alpha v2"),
      packageNode("Beta", "beta v1")
    ])
    git(["add", "packages.json"], workDir)
    git(["commit", "-q", "-m", "mix new and modified"], workDir)

    let originUrl = "file://" & originDir
    writeFile(
      gitConfigPath,
      "[url \"" & originUrl & "\"]\n" &
      "    insteadOf = https://github.com/test/packages\n"
    )

    let output = runFails(
      "nim r -d:ssl " & quoteShell(root / "package_scanner.nim") &
      " packages.json --check-pr",
      workDir,
      [
        ("GIT_CONFIG_GLOBAL", gitConfigPath),
        ("GITHUB_REPOSITORY", "test/packages"),
        ("GITHUB_BASE_REF", "master")
      ]
    )

    doAssert output.contains("may not also modify or remove existing packages"), output
