v0.9.0
==================

* Drop Nim < 1.0 support

v0.8.0
==================

* Deprecate functions taking a `seq[Rune]`

v0.7.0
==================

* Drop Nim 0.18 support

v0.6.0
==================

* Change `cmpNfd` signature to accept `openArray[char]`
  instead of `string`

v0.5.0
==================

* Update to Unicode 12.1

v0.4.0
==================

* Drop support for Nim 0.17
* Add support for Nim 0.19
* Update dependencies

v0.3.1
==================

* Update dependencies

v0.3.0
==================

* Update to unicode 11

v0.2.2
==================

* Improve perf of compilation

v0.2.1
==================

* New: `cmpNfd` API
* Fix: wrong normalization when the text is malformed
  (i.e when a `graphemeJoiner` is inserted)
* Improve perf of `toNfx` functions

v0.2.0
==================

* Remove APIs taking `ref seq[Rune]` and `iterator: Rune` param
* Fix: passing a `seq` or a `string` won't make a copy
* Fix: nimble file unicodedb dependency version range

v0.1.1
==================

* Update unicodedb dependency
  and fixes breaking changes
* Rename command `nimble tests` to `nimble test` and
  `nimble tests2` to `nimble test2`

v0.1.0
==================

* Initial release
