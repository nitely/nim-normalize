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
