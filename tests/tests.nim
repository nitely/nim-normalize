import std/unittest, std/strutils, std/algorithm
import std/unicode except strip
import ../src/normalize

type
  testRecord = tuple
    source: seq[Rune]
    nfd: seq[Rune]
    nfc: seq[Rune]
    nfkc: seq[Rune]
    nfkd: seq[Rune]

proc parse(): seq[testRecord] =
  result = @[]
  for line in lines("./tests/NormalizationTest.txt"):
    if len(line.strip()) == 0:
      continue
    if line.startsWith('#'):
      continue
    if line.startsWith('@'):
      continue
    let
      parts = line.split(';', 5)
      source = parts[0]
      nfc = parts[1]
      nfd = parts[2]
      nfkc = parts[3]
      nfkd = parts[4]

    var record: testRecord = (
      source: @[],
      nfd: @[],
      nfc: @[],
      nfkc: @[],
      nfkd: @[])
    for c in source.split(' '):
      record.source.add(Rune(parseHexInt("0x$#" % c)))
    for c in nfc.split(' '):
      record.nfc.add(Rune(parseHexInt("0x$#" % c)))
    for c in nfd.split(' '):
      record.nfd.add(Rune(parseHexInt("0x$#" % c)))
    for c in nfkc.split(' '):
      record.nfkc.add(Rune(parseHexInt("0x$#" % c)))
    for c in nfkd.split(' '):
      record.nfkd.add(Rune(parseHexInt("0x$#" % c)))

    result.add(record)

proc parsePart1(): seq[int] =
  result = @[]
  var canParse = false
  for line in lines("./tests/NormalizationTest.txt"):
    if len(line.strip()) == 0:
      continue
    if line.startsWith('#'):
      continue
    if line.startsWith('@') and canParse:
      break
    if line.startsWith("@Part1 "):
      canParse = true
      continue
    if not canParse:
      continue
    let
      parts = line.split(';', 5)
      source = parts[0]
    result.add(parseHexInt("0x$#" % source))
  result.sort(system.cmp[int])

let
  testData = parse()
  testExcludeData = parsePart1()
  maxCP = 0x10FFFF

proc toUTF8(s: seq[Rune]): string =
  result = ""
  for r in s:
    result.add(r.toUTF8)

test "Sanity check":
  check testData.len > 1000
  check testExcludeData.len > 0
  check toUTF8(@['a'.ord.Rune, 'b'.ord.Rune]) == "ab"

test "Test NFD":
  ##    NFD
  ##      c3 ==  toNFD(c1) ==  toNFD(c2) ==  toNFD(c3)
  ##      c5 ==  toNFD(c4) ==  toNFD(c5)
  var i = 0
  for record in testData:
    check record.nfd == toNFD(record.source)
    check record.nfd == toNFD(record.nfc)
    check record.nfd == toNFD(record.nfd)
    check record.nfkd == toNFD(record.nfkc)
    check record.nfkd == toNFD(record.nfkd)
    inc i
  echo "tested $# records" % $i

test "Test NFD strings":
  var i = 0
  for record in testData:
    check record.nfd.toUTF8 == toNFD(record.source.toUTF8)
    check record.nfd.toUTF8 == toNFD(record.nfc.toUTF8)
    check record.nfd.toUTF8 == toNFD(record.nfd.toUTF8)
    check record.nfkd.toUTF8 == toNFD(record.nfkc.toUTF8)
    check record.nfkd.toUTF8 == toNFD(record.nfkd.toUTF8)
    inc i
  echo "tested $# records" % $i

test "Test some NFD for runes":
  check @[Rune(0x0044), Rune(0x0307)] == toNFD(@[Rune(0x1E0A)])
  check @[Rune(0)] == toNFD(@[Rune(0)])
  let empty: seq[Rune] = @[]
  check empty == toNFD(empty)

test "Test some NFD for string":
  check @[Rune(0x0044), Rune(0x0307)].`$` == toNFD(@[Rune(0x1E0A)].`$`)
  check "" == toNFD("")

test "Test NFC":
  ##    NFC
  ##      c2 ==  toNFC(c1) ==  toNFC(c2) ==  toNFC(c3)
  ##      c4 ==  toNFC(c4) ==  toNFC(c5)
  var i = 0
  for record in testData:
    check record.nfc == toNFC(record.source)
    check record.nfc == toNFC(record.nfc)
    check record.nfc == toNFC(record.nfd)
    inc i
  echo "tested $# records" % $i

test "Test NFC strings":
  var i = 0
  for record in testData:
    check record.nfc.toUTF8 == toNFC(record.source.toUTF8)
    check record.nfc.toUTF8 == toNFC(record.nfc.toUTF8)
    check record.nfc.toUTF8 == toNFC(record.nfd.toUTF8)
    inc i
  echo "tested $# records" % $i

test "Test some NFC for runes":
  check @[Rune(0x1E0C), Rune(0x0307)] == toNFC(@[Rune(0x1E0A), Rune(0x0323)])
  check @[Rune(0)] == toNFC(@[Rune(0)])
  let empty: seq[Rune] = @[]
  check empty == toNFC(empty)

test "Test some NFD for string":
  check(@[Rune(0x1E0C), Rune(0x0307)].`$` == toNFC(
    @[Rune(0x1E0A), Rune(0x0323)].`$`))
  check "" == toNFD("")

test "Test NFKD":
  ##    NFKD
  ##      c5 == toNFKD(c1) == toNFKD(c2) == toNFKD(c3) == toNFKD(c4) == toNFKD(c5)
  var i = 0
  for record in testData:
    check record.nfkd == toNFKD(record.source)
    check record.nfkd == toNFKD(record.nfc)
    check record.nfkd == toNFKD(record.nfd)
    check record.nfkd == toNFKD(record.nfkc)
    check record.nfkd == toNFKD(record.nfkd)
    inc i
  echo "tested $# records" % $i

test "Test NFKD strings":
  var i = 0
  for record in testData:
    check record.nfkd.toUTF8 == toNFKD(record.source.toUTF8)
    check record.nfkd.toUTF8 == toNFKD(record.nfc.toUTF8)
    check record.nfkd.toUTF8 == toNFKD(record.nfd.toUTF8)
    check record.nfkd.toUTF8 == toNFKD(record.nfkc.toUTF8)
    check record.nfkd.toUTF8 == toNFKD(record.nfkd.toUTF8)
    inc i
  echo "tested $# records" % $i

test "Test NFKC":
  ##    NFKC
  ##      c4 == toNFKC(c1) == toNFKC(c2) == toNFKC(c3) == toNFKC(c4) == toNFKC(c5)
  var i = 0
  for record in testData:
    check record.nfkc == toNFKC(record.source)
    check record.nfkc == toNFKC(record.nfc)
    check record.nfkc == toNFKC(record.nfd)
    check record.nfkc == toNFKC(record.nfkc)
    check record.nfkc == toNFKC(record.nfkd)
    inc i
  echo "tested $# records" % $i

test "Test NFKC strings":
  var i = 0
  for record in testData:
    check record.nfkc.toUTF8 == toNFKC(record.source.toUTF8)
    check record.nfkc.toUTF8 == toNFKC(record.nfc.toUTF8)
    check record.nfkc.toUTF8 == toNFKC(record.nfd.toUTF8)
    check record.nfkc.toUTF8 == toNFKC(record.nfkc.toUTF8)
    check record.nfkc.toUTF8 == toNFKC(record.nfkd.toUTF8)
    inc i
  echo "tested $# records" % $i

test "Test missing CPs":
  ##      X == toNFC(X) == toNFD(X) == toNFKC(X) == toNFKD(X)
  var cps = newSeq[Rune](1)
  var j = 0
  for i in 0 .. maxCP:
    if testExcludeData.binarySearch(i) != -1:
      continue
    cps[0] = Rune(i)
    check cps == toNFC(cps)
    check cps == toNFD(cps)
    check cps == toNFKC(cps)
    check cps == toNFKD(cps)
    inc j
  echo "tested $# chars" % $j

test "Test it adds a grapheme joiner":
  var text = @[Rune(0x0041)]
  for i in 0 .. 40:
    text.add(Rune(0x0300))
  var i = 0
  for cp in toNFC(text):
    if cp == Rune(0x034F):
      inc i
  check i == 1  # Make sure it's just 1

test "Test expansion factor":
  # from http://unicode.org/faq/normalization.html
  check(
    len(toNfc(0x1D160.Rune.toUTF8)) ==
    len(0x1D160.Rune.toUTF8) * 3)
  check(len(toNfc(@[0xFB2C.Rune])) == 3)
  check(
    len(toNfd(0x0390.Rune.toUTF8)) ==
    len(0x0390.Rune.toUTF8) * 3)
  check(len(toNfd(@[0x1F82.Rune])) == 4)
  check(
    len(toNfkc(0xFDFA.Rune.toUTF8)) ==
    len(0xFDFA.Rune.toUTF8) * 11)
  check(len(toNfkc(@[0xFDFA.Rune])) == 18)
  check(
    len(toNfkd(0xFDFA.Rune.toUTF8)) ==
    len(0xFDFA.Rune.toUTF8) * 11)
  check(len(toNfkd(@[0xFDFA.Rune])) == 18)

test "Test it does not add a grapheme joiner":
  var text = @[Rune(0x0041)]
  for i in 0 .. 40:
    text.add(Rune(0x0041))
  check(Rune(0x034F) notin toNFC(text))

test "Test is NFC":
  check(not isNFC(@[Rune(0x1E0A), Rune(0x0323)]))
  check(not isNFC(toNFC(@[Rune(0x1E0C), Rune(0x0307)])))  # Maybe
  check isNFC("abc")

test "Test is NFD":
  check(not isNFD(@[Rune(0x1E0A)]))
  check isNFD(toNFD(@[Rune(0x1E0A)]))
  check isNFD("abc")

test "Test idempotency":
  for record in testData:
    check toNFD(record.source) == toNFD(toNFD(record.source))
    check toNFKD(record.source) == toNFKD(toNFKD(record.source))
    check toNFC(record.source) == toNFC(toNFC(record.source))
    check toNFKC(record.source) == toNFKC(toNFKC(record.source))

test "Test cmpNFD":
  var i = 0
  for record in testData:
    check cmpNFD(record.nfd.toUTF8, record.source.toUTF8)
    check cmpNFD(record.nfd.toUTF8, record.nfc.toUTF8)
    check cmpNFD(record.nfd.toUTF8, record.nfd.toUTF8)
    check cmpNFD(record.nfkd.toUTF8, record.nfkc.toUTF8)
    check cmpNFD(record.nfkd.toUTF8, record.nfkd.toUTF8)
    inc i
  echo "tested $# records" % $i

test "Test some cmpNFD":
  check cmpNfd("", "")
  check cmpNfd("a", "a")
  check cmpNfd(
    "Voulez-vous un caf\u00E9?",
    "Voulez-vous un caf\u0065\u0301?")
  check(not cmpNfd("\u0041", "\u0410"))
  check(not cmpNfd("a", "b"))
  check(not cmpNfd("abc", "abd"))
  check(not cmpNfd("cba", "dba"))
  check(not cmpNfd("a", ""))
  check(not cmpNfd("", "a"))
  check(not cmpNfd("a", "aa"))
  check(not cmpNfd("aa", "a"))
  check(not cmpNfd("\u00E9-a", "\u0065\u0301-b"))

when (NimMajor, NimMinor, NimPatch) >= (0, 19, 0):
  test "Test openArray cmpNFD":
    check cmpNfd("".toOpenArray(0, -1), "".toOpenArray(0, -1))
    check cmpNfd("a".toOpenArray(0, 0), "a".toOpenArray(0, 0))
    check cmpNfd("abc".toOpenArray(0, 2), "abc".toOpenArray(0, 2))
    check cmpNfd("abcd".toOpenArray(0, 2), "abcz".toOpenArray(0, 2))
    check(not cmpNfd("abcd".toOpenArray(0, 3), "abcz".toOpenArray(0, 3)))
