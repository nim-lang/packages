--define:ssl

task test, "Run test suite":
  exec "nim c -r tests/tpackage_index.nim"
  exec "nim c -r tests/tpackage_scanner.nim"
