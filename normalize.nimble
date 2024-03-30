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
  exec "nim c -r src/normalize"
  exec "nim c -r tests/tests"
  when (NimMajor, NimMinor) >= (2, 0):
    exec "nim c --mm:refc -r src/normalize"
    exec "nim c --mm:refc -r tests/tests"

task docs, "Docs":
  exec "nim doc --project -o:./docs ./src/normalize.nim"
