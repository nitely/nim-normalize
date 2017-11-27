import unittest, strutils, unicode, algorithm

import normalize

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

test "Test some NFD for runes":
  check @[Rune(0x0044), Rune(0x0307)] == toNFD(@[Rune(0x1E0A)])
  check @[Rune(0)] == toNFD(@[Rune(0)])
  let empty: seq[Rune] = @[]
  check empty == toNFD(empty)

type
  SeqRef[T] = ref seq[T]

proc newSeqRef[T](): SeqRef[T] =
  new(result)
  result[] = @[]
  return result

test "Test some NFD for ref runes":
  var someRunes = newSeqRef[Rune]()
  someRunes[].add(Rune(0x1E0A))
  var res: seq[Rune] =  @[]
  for cp in toNFD(someRunes):
    res.add(cp)
  check @[Rune(0x0044), Rune(0x0307)] == res

test "Test some NFD for string":
  check @[Rune(0x0044), Rune(0x0307)].`$` == toNFD(@[Rune(0x1E0A)].`$`)
  check "" == toNFD("")

test "Test some NFD for iterator":
  iterator myiter(): Rune {.closure.} =
    yield Rune(0x1E0A)
  var res: seq[Rune] = @[]
  for cp in toNFD(myiter):
    res.add(cp)
  check @[Rune(0x0044), Rune(0x0307)] == res

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

test "Test some NFC for runes":
  check @[Rune(0x1E0C), Rune(0x0307)] == toNFC(@[Rune(0x1E0A), Rune(0x0323)])
  check @[Rune(0)] == toNFC(@[Rune(0)])
  let empty: seq[Rune] = @[]
  check empty == toNFC(empty)

test "Test some NFC for ref runes":
  var someRunes = newSeqRef[Rune]()
  someRunes[].add(@[Rune(0x1E0A), Rune(0x0323)])
  var res: seq[Rune] =  @[]
  for cp in toNFC(someRunes):
    res.add(cp)
  check @[Rune(0x1E0C), Rune(0x0307)] == res

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
