# Package

version = "0.8.0"
author = "Esteban Castro Borsani (@nitely)"
description = "Unicode normalization forms (tr15)"
license = "MIT"
srcDir = "src"

skipDirs = @["tests"]

# Dependencies

requires "nim >= 1.0.0"
requires "unicodedb >= 0.7"

task test, "Test":
  # using the Git submodule
  exec "nim c -r -p:unicodedb/src src/normalize"
  exec "nim c -r -p:unicodedb/src tests/tests"
  # using the Nimble package
  exec "nim c -r src/normalize"
  exec "nim c -r tests/tests"

task docs, "Docs":
  exec "nim doc --project -o:./docs ./src/normalize.nim"
