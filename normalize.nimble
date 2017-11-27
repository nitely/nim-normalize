# Package

version       = "0.1.0"
author        = "Esteban Castro Borsani (@nitely)"
description   = "Unicode normalization forms (tr15)"
license       = "MIT"
srcDir = "src"

skipDirs = @["tests"]

# Dependencies

requires "nim >= 0.17.2"
requires "unicodedb >= 0.1 & <= 0.2"

task tests, "Test":
  exec "nim c -r tests/tests"

task tests2, "Src test":
  exec "nim c -r src/normalize"

task docs, "Docs":
  exec "nim doc2 -o:./docs/index.html ./src/normalize.nim"
