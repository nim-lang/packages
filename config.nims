--define:ssl

task build, "Build package_index.nim":
  exec "nim c package_index.nim"

task test, "Run test suite":
  exec "nim c -r tests/tpackage_index.nim"
  exec "nim c -r tests/tpackage_scanner.nim"
