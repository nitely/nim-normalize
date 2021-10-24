# Normalize

[![Build Status](https://img.shields.io/travis/nitely/nim-normalize.svg?style=flat-square)](https://travis-ci.org/nitely/nim-normalize)
[![licence](https://img.shields.io/github/license/nitely/nim-normalize.svg?style=flat-square)](https://raw.githubusercontent.com/nitely/nim-normalize/master/LICENSE)

A library for normalizing unicode text. Implements all the
Unicode Normalization Form algorithms. Normalization is
buffered and takes O(n) time and O(1) space.

> Note: the ``iterator`` version takes O(1)
> space, but the ``proc`` takes O(n) space.

## Install

```
nimble install normalize
```

## Compatibility

Nim +1.0.0

## Usage

```nim
import normalize

# Normalization
assert toNfc("E◌̀") == "È"
assert toNfc("\u0045\u0300") == "\u00C8"
assert toNfd("È") == "E◌̀"
assert toNfd("\u00C8") == "\u0045\u0300"

# toNfkc and toNfkd are also available

# Canonical comparison
assert cmpNfd(
  "Voulez-vous un caf\u00E9?",
  "Voulez-vous un caf\u0065\u0301?")

# Normalization check (not always reliable, see docs)
assert isNfd(toNfd("\u1E0A"))

# isNfc, isNfkc and isNfkd are also available
```

> Note: when printing to a terminal,
> the output may visually trick you.
> Better try printing the len or the runes

[docs](https://nitely.github.io/nim-normalize/)

## Optimizations

The best optimization is to avoid normalizing when the text
is already normalized. The `isNf` family of procs can be
used for this purpose.

```nim
import normalize

template fastNfc(s: var string) =
  if not isNfc(s):
    s = toNfc(s)
```

> Beware `isNf` may return `false` even after normalizing,
  this is because the internal check has 3 possible outputs
  "Yes", "No" and "MayBe". The problem is the output may
  always be "MayBe" for certain texts.

## Tests

```
nimble test
```

## LICENSE

MIT
