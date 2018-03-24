## This module implements all the
## Unicode Normalization Form algorithms
##
## The normalization is buffered. Buffering
## makes the algorithm take O(n) time and O(1) space.
## Making it suitable for untrusted text and streaming.
##
## The result is not guaranteed to be equal to
## the unbuffered one. However, this is usually
## only true for malformed text. The buffer may
## be flushed before filling it completely.
##
## NFD will apply a canonical decomposition.
## NFC will apply a canonical decomposition, then
## the canonical composition. NFKD will apply a
## compatibility decomposition. NFKC will apply a
## compatibility decomposition, then the canonical composition.

import unicode

import unicodedb

type
  Buffer = tuple
    ## A buffer has a fixed size but works
    ## as if it were dynamic by tracking
    ## the last index in use
    data: array[32, int]  # todo: int -> int32 or Rune
    pt: int
  UnBuffer = seq[int]  # todo: remove
    ## For testing purposes
  SomeBuffer = (Buffer | UnBuffer)  # todo: remove

iterator items(buffer: Buffer): int {.inline.} =
  var i = 0
  while i < buffer.pt:
    yield buffer.data[i]
    inc i

iterator pairs(buffer: Buffer): (int, int) {.inline.} =
  var i = 0
  for n in buffer:
    yield (i, n)
    inc i

proc left(buffer: Buffer): int {.inline.} =
  ## return capacity left
  buffer.data.len - buffer.pt

proc clear(buffer: var Buffer) {.inline.} =
  buffer.pt = 0

proc add(buffer: var Buffer, elm: int) {.inline.} =
  assert buffer.left > 0
  buffer.data[buffer.pt] = elm
  inc buffer.pt

proc len(buffer: Buffer): int {.inline.} =
  buffer.pt

proc high(buffer: Buffer): int {.inline.} =
  buffer.pt - 1

proc setLen(buffer: var Buffer, i: int) {.inline.} =
  assert i <= buffer.data.len
  buffer.pt = i

proc `[]`(buffer: var Buffer, i: int): var int {.inline.} =
  buffer.data[i]

proc `[]=`(buffer: var Buffer, i: int, x: int) {.inline.} =
  buffer.data[i] = x

proc reverse(buffer: var Buffer) {.inline.} =
  var x = 0
  var y = max(0, buffer.len - 1)
  while x < y:
    swap(buffer.data[x], buffer.data[y])
    dec(y)
    inc(x)

proc pop(buffer: var Buffer): int {.inline.} =
  assert buffer.len - 1 >= 0
  result = buffer.data[buffer.len - 1]
  dec buffer.pt

type
  NfType {.pure.} = enum
    NFC, NFKC, NFD, NFKD

  QcStatus {.pure.} = enum
    YES, NO, MAYBE

const nfMasks: array[NfType, array[2, (NfMask, QcStatus)]] = [
  [(nfcQcNo, QcStatus.NO),
   (nfcQcMaybe, QcStatus.MAYBE)],
  [(nfkcQcNo, QcStatus.NO),
   (nfkcQcMaybe, QcStatus.MAYBE)],
  [(nfdQcNo, QcStatus.NO),
   (nfdQcNo, QcStatus.NO)],
  [(nfkdQcNo, QcStatus.NO),
   (nfkdQcNo, QcStatus.NO)]]

proc isAllowed(qc: int, nfType: NfType): QcStatus {.inline.} =
  ## Return the quick check property value
  result = QcStatus.YES
  for mask, status in items(nfMasks[nfType]):
    if mask in qc:
      result = status
      return

proc primaryComposite(cpA: int, cpB: int): int {.inline.} =
  ## Find the composition of two decomposed CPs
  # This does not include hangul chars
  # as those can be dynamically computed
  composition(cpA, cpB)

# Hangul
const
  SBase = 0xAC00
  LBase = 0x1100
  VBase = 0x1161
  TBase = 0x11A7
  LCount = 19
  VCount = 21
  TCount = 28
  NCount = VCount * TCount
  SCount = LCount * NCount

proc hangulComposition(cpA: int, cpB: int): int =
  ## Return hangul composition. Return -1 if not found
  let
    LIndex = cpA - LBase
    VIndex = cpB - VBase
  if 0 <= LIndex and LIndex < LCount and
      0 <= VIndex and VIndex < VCount:
    result = SBase + (LIndex * VCount + VIndex) * TCount
    return

  let
    SIndex = cpA - SBase
    TIndex = cpB - TBase
  if 0 <= SIndex and SIndex < SCount and
      (SIndex mod TCount) == 0 and
      0 < TIndex and TIndex < TCount:
    result = cpA + TIndex
    return

  result = -1

proc canonicalComposition(cps: var SomeBuffer) =
  ## In-place composition
  # * Last step for NFC or NFKC. Recomposition.
  # * Checks it for pairs of characters which meet
  #   certain criteria and replaced by the composite character,
  #   until the string contains no further such pairs.
  # * Algorithm: D117 http://www.unicode.org/versions/Unicode10.0.0/ch03.pdf
  #   (see also 115 and 116)
  var
    lastStarterIdx = -1
    lastCCC = -1
    pt = 0
  for cp in cps:
    if lastStarterIdx != -1 and
        lastStarterIdx + 1 == pt:  # At head
      let cpc = hangulComposition(cps[lastStarterIdx], cp)
      if cpc != -1:
        cps[lastStarterIdx] = cpc
        lastCCC = 0
        continue
    # else not Hangul composition

    # Starter can be non-assigned
    let ccc = combining(cp)
    if lastStarterIdx == -1:
      if ccc == 0:
        lastStarterIdx = pt
      lastCCC = ccc
      cps[pt] = cp
      inc pt
      continue

    # Because the string is in canonical order,
    # testing whether a character is blocked requires
    # looking only at the immediately preceding char
    if lastCCC >= ccc and lastCCC > 0:
      lastCCC = ccc
      cps[pt] = cp
      inc pt
      continue
    # else not blocked

    let pcp = primaryComposite(cps[lastStarterIdx], cp)
    if pcp != -1:
      cps[lastStarterIdx] = pcp
      assert combining(pcp) == 0
      lastCCC = 0
      continue

    if ccc == 0:
      lastStarterIdx = pt
      lastCCC = 0
      cps[pt] = cp
      inc pt
      continue

    lastCCC = ccc
    cps[pt] = cp
    inc pt
  cps.setLen(pt)

proc canonicSort(cps, cccs: var SomeBuffer) =
  ## In-place canonical sort
  # See http://www.unicode.org/versions/Unicode10.0.0/ch03.pdf point D108
  # * Needed for canonical and compat decomposition
  # * Once (fully) decompose any sequences of combining marks
  #   are put into a well-defined order
  # * Sorts sequences of combining marks based on the value of
  #   their Canonical_Combining_Class (ccc) property
  # * Reorderable pair: Two adjacent characters A and B in a
  #   coded character sequence <A, B> are a Reorderable Pair
  #   if and only if ccc(A) > ccc(B) > 0.
  var
    i = cps.len - 1
    isSwapped = false
  while i > 0:
    isSwapped = false
    for j in 0 ..< i:
      let
        cccA = cccs[j]
        cccB = cccs[j + 1]
      if cccA > cccB and cccB > 0:
        swap(cps[j], cps[j + 1])
        swap(cccs[j], cccs[j + 1])
        isSwapped = true
    if not isSwapped:
      break
    dec i

proc hangulDecomposition(cp: int): Buffer =
  let SIndex = cp - SBase
  if 0 > SIndex and SIndex >= SCount:
    return

  result.add(LBase + SIndex div NCount)  # L
  result.add(VBase + (SIndex mod NCount) div TCount)  # V

  let T = TBase + SIndex mod TCount
  if T != TBase:
    result.add(T)

proc isHangul(cp: int): bool {.inline.} =
  0xAC00 <= cp and cp <= 0xD7A3

# NFD
# NFC (+ canonic_composition later)
proc canonicalDcp(cp: int): Buffer =
  ## Return 4 code points at most.
  ## It does a full canonical decomposition
  if cp.isHangul:
    result = hangulDecomposition(cp)
    if result.len == 0:
      result.add(cp)
    return

  var
    cpA = cp
    i = 0
  while true:
    i = 0
    for cpX in canonicalDecomposition(cpA):
      if i == 0:
        cpA = cpX
      else:
        result.add(cpX)
      inc i
    if i == 0:
      result.add(cpA)
      break
  result.reverse()

# NFKD
# NFKC (+ canonicalComposition later)
proc compatibilityDecomposition(cp: int): Buffer =
  ## Return 18 code points at most.
  ## It does a full decomposition
  if cp.isHangul:
    result = hangulDecomposition(cp)
    if result.len == 0:
      result.add(cp)
    return

  var queue: Buffer
  queue.add(cp)
  while queue.len > 0:
    let
      curCp = queue.pop()
      lastLen = queue.len
    for dcp in decomposition(curCp):
      queue.add(dcp)
    if lastLen == queue.len:  # No decomposition
      result.add(curCp)
  result.reverse()

const graphemeJoiner = 0x034F

template decompose(result, cp, nfType) =
  when nfType in {NfType.NFC, NfType.NFD}:
    result = canonicalDcp(cp)
  else:
    result = compatibilityDecomposition(cp)

iterator runesN(s: string): (bool, Rune) {.inline.} =
  var
    n = 0
    r: Rune
  while n < len(s):
    fastRuneAt(s, n, r, true)
    yield (n == len(s), r)

iterator runesN(s: seq[Rune]): (bool, Rune) {.inline.} =
  for i, r in s:
    yield (i == s.high, r)

iterator toNF(
    s: (seq[Rune] | string),
    nfType: static[NfType]): Rune {.inline.} =
  ## Buffered unicode normalization
  var
    buff: Buffer
    cccs: Buffer
    dcps: Buffer
    lastCCC = 0
  for done, r in runesN(s):
    decompose(dcps, r.int, nfType)
    for j, cp in pairs(dcps):
      let
        finished = done and j == dcps.high
        props = properties(cp)
        ccc = combining(props)
        qc = quickCheck(props)
        isSafeBreak = (
          isAllowed(qc, nfType) == QcStatus.YES and
          ccc == 0)
      if finished or isSafeBreak or buff.left == 1:
        if finished:
          buff.add(cp)
          cccs.add(ccc)
        # Flush the buffer
        buff.canonicSort(cccs)
        when nfType in {NfType.NFC, NfType.NFKC}:
          buff.canonicalComposition()
        for bcp in items(buff):
          yield Rune(bcp)
        buff.clear()
        cccs.clear()
        # Put a CGJ beetwen non-starters
        if lastCCC != 0 and ccc != 0:
          buff.add(graphemeJoiner)
      lastCCC = ccc
      buff.add(cp)
      cccs.add(ccc)

iterator toNFD*(s: string): Rune {.inline.} =
  ## Iterates over each normalized unicode character
  for r in toNF(s, NfType.NFD):
    yield r

iterator toNFD*(s: seq[Rune]): Rune {.inline.} =
  ## Iterates over each normalized unicode character
  for r in toNF(s, NfType.NFD):
    yield r

iterator toNFC*(s: string): Rune {.inline.} =
  ## Iterates over each normalized unicode character
  for r in toNF(s, NfType.NFC):
    yield r

iterator toNFC*(s: seq[Rune]): Rune {.inline.} =
  ## Iterates over each normalized unicode character
  for r in toNF(s, NfType.NFC):
    yield r

iterator toNFKD*(s: string): Rune {.inline.} =
  ## Iterates over each normalized unicode character
  for r in toNF(s, NfType.NFKD):
    yield r

iterator toNFKD*(s: seq[Rune]): Rune {.inline.} =
  ## Iterates over each normalized unicode character
  for r in toNF(s, NfType.NFKD):
    yield r

iterator toNFKC*(s: string): Rune {.inline.} =
  ## Iterates over each normalized unicode character
  for r in toNF(s, NfType.NFKC):
    yield r

iterator toNFKC*(s: seq[Rune]): Rune {.inline.} =
  ## Iterates over each normalized unicode character
  for r in toNF(s, NfType.NFKC):
    yield r

proc toNF(s: seq[Rune], nfType: static[NfType]): seq[Rune] =
  # fixme: normalization may take 3x (or more?)
  # times the len of the original string
  result = newSeqOfCap[Rune](s.len)
  for r in toNF(s, nfType):
    result.add(r)

proc toNF(s: string, nfType: static[NfType]): string =
  # fixme: normalization may take 3x (or more?)
  # times the len of the original string
  result = newStringOfCap(s.len)
  for r in toNF(s, nfType):
    result.add(r.toUTF8)

proc toNFD*(s: string): string =
  ## Return the normalized input
  toNF(s, NfType.NFD)

proc toNFD*(s: seq[Rune]): seq[Rune] =
  ## Return the normalized input
  toNF(s, NfType.NFD)

proc toNFC*(s: string): string =
  ## Return the normalized input
  toNF(s, NfType.NFC)

proc toNFC*(s: seq[Rune]): seq[Rune] =
  ## Return the normalized input
  toNF(s, NfType.NFC)

proc toNFKD*(s: string): string =
  ## Return the normalized input
  toNF(s, NfType.NFKD)

proc toNFKD*(s: seq[Rune]): seq[Rune] =
  ## Return the normalized input
  toNF(s, NfType.NFKD)

proc toNFKC*(s: string): string =
  ## Return the normalized input
  toNF(s, NfType.NFKC)

proc toNFKC*(s: seq[Rune]): seq[Rune] =
  ## Return the normalized input
  toNF(s, NfType.NFKC)

proc toNFUnbuffered(cps: seq[Rune], nfType: static[NfType]): seq[Rune] =
  ## This exists for testing purposes
  let isComposable = nfType in [NfType.NFC, NfType.NFKC]
  var
    cpsB = newSeqOfCap[int](result.len)
    cccs = newSeqOfCap[int](result.len)
    dcps: Buffer
  for rune in cps:
    decompose(dcps, rune.int, nfType)
    for dcp in dcps:
      cpsB.add(dcp)
      cccs.add(combining(dcp))
  cpsB.canonicSort(cccs)
  if isComposable:
    cpsB.canonicalComposition()
  result = newSeq[Rune](cpsB.len)
  for i, cp in cpsB:
    result[i] = Rune(cp)

proc isSupplementary(cp: int): bool {.inline.} =
  ## Check a given code point is within a private area
  # Private areas
  result = (
    (0x100000 <= cp and cp <= 0x10FFFD) or
    (0xF0000 <= cp and cp <= 0xFFFFF))

iterator runes(s: seq[Rune]): Rune {.inline.} =
  # no-op
  for r in s:
    yield r

proc isNF(cps: (seq[Rune] | string), nfType: NfType): QcStatus =
  ## isNFx(s) is true if and only
  ## if toNFX(s) is identical to s
  result = QcStatus.YES
  var
    lastCanonicalClass = 0
    skipOne = false
  for rune in runes(cps):
    let cp = int(rune)
    if skipOne:
      skipOne = false
      continue
    if isSupplementary(cp):
      skipOne = true
    let
      props = properties(cp)
      canonicalClass = combining(props)
    if lastCanonicalClass > canonicalClass and canonicalClass != 0:
      result = QcStatus.NO
      return
    let check = isAllowed(quickCheck(props), nfType)
    if check == QcStatus.NO:
      result = QcStatus.NO
      return
    if check == QcStatus.MAYBE:
      result = QcStatus.MAYBE
    lastCanonicalClass = canonicalClass

proc isNFC*(s: string): bool {.inline.} =
  ## Return whether the unicode characters
  ## are normalized or not
  isNF(s, NfType.NFC) == QcStatus.YES

proc isNFC*(s: seq[Rune]): bool {.inline.} =
  ## Return whether the unicode characters
  ## are normalized or not
  isNF(s, NfType.NFC) == QcStatus.YES

proc isNFD*(s: string): bool {.inline.} =
  ## Return whether the unicode characters
  ## are normalized or not
  isNF(s, NfType.NFD) == QcStatus.YES

proc isNFD*(s: seq[Rune]): bool {.inline.} =
  ## Return whether the unicode characters
  ## are normalized or not
  isNF(s, NfType.NFD) == QcStatus.YES

proc isNFKC*(s: string): bool {.inline.} =
  ## Return whether the unicode characters
  ## are normalized or not
  isNF(s, NfType.NFKC) == QcStatus.YES

proc isNFKC*(s: seq[Rune]): bool {.inline.} =
  ## Return whether the unicode characters
  ## are normalized or not
  isNF(s, NfType.NFKC) == QcStatus.YES

proc isNFKD*(s: string): bool {.inline.} =
  ## Return whether the unicode characters
  ## are normalized or not
  isNF(s, NfType.NFKD) == QcStatus.YES

proc isNFKD*(s: seq[Rune]): bool {.inline.} =
  ## Return whether the unicode characters
  ## are normalized or not
  isNF(s, NfType.NFKD) == QcStatus.YES

when isMainModule:
  block:
    echo "Test random text"
    var text: seq[Rune] = @[]
    for line in lines("./tests/TestNormRandomText.txt"):
      for r in runes(line):
        text.add(r)
    doAssert toNFUnbuffered(text, NfType.NFD) == toNFD(text)
    doAssert toNFUnbuffered(text, NfType.NFC) == toNFC(text)
    doAssert toNFUnbuffered(text, NfType.NFKC) == toNFKC(text)
    doAssert toNFUnbuffered(text, NfType.NFKD) == toNFKD(text)

    doAssert isNFD(toNFD(text))
    doAssert isNFC(toNFC(text))
    doAssert isNFKC(toNFKC(text))
    doAssert isNFKD(toNFKD(text))
    echo "Tested: " & $text.len & " chars"

  echo "Test Buffer"
  block:
    echo "Test len"
    var buff: Buffer
    doAssert buff.len == 0
    buff.add(1)
    buff.add(1)
    buff.add(1)
    doAssert buff.len == 3
    buff.setLen(2)
    doAssert buff.len == 2
  block:
    echo "Test left"
    var buff: Buffer
    doAssert buff.left == buff.data.len
    var i = 0
    while buff.left > 0:
      buff.add(1)
      inc i
    doAssert buff.left == 0
    doAssert i == buff.len
    doAssert i > 1
  block:
    echo "Test iter"
    var buff: Buffer
    buff.add(1)
    buff.add(1)
    var i = 0
    for n in buff:
      doAssert n == 1
      inc i
    doAssert i == 2
  block:
    echo "Test setLen"
    var buff: Buffer
    buff.add(1)
    buff.add(1)
    buff.add(1)
    doAssert buff.len == 3
    buff.setLen(2)
    doAssert buff.len == 2
  block:
    echo "Test high"
    var buff: Buffer
    doAssert buff.high == -1
    buff.add(1)
    buff.add(1)
    buff.add(1)
    doAssert buff.high == 2
  block:
    echo "Test clear"
    var buff: Buffer
    buff.add(1)
    buff.add(1)
    buff.add(1)
    doAssert buff.len == 3
    buff.clear()
    doAssert buff.len == 0

  block:
    echo "Test runesN"
    var i = 0
    for done, r in runesN(@[Rune(97)]):
      doAssert done
      inc i
    doAssert i == 1
    for done, r in runesN(@[Rune(97), Rune(98)]):
      doAssert r in [Rune(97), Rune(98)]
      if r == Rune(97):
        doAssert(not done)
      if r == Rune(98):
        doAssert(done)
    var j = 0
    for done, r in runesN("a"):
      doAssert done
      inc j
    doAssert j == 1
    for done, r in runesN("ab"):
      doAssert r in [Rune(97), Rune(98)]
      if r == Rune(97):
        doAssert(not done)
      if r == Rune(98):
        doAssert(done)

  block:
    echo "Test it does not blow the buffer"
    # This tests that the buffer has a
    # reserved slot for the last char when
    # the buffer is full.
    # No other test catches this since it can
    # only occur with malformed text
    var buff: Buffer
    doAssert buff.data.len > 0
    var text = newSeq[Rune]()
    for i in 0 .. buff.data.len:
      text.add(Rune(0x0300))
    var i = 0
    for _ in toNFC(text):
      inc i
    doAssert i == text.len + 1  # + joiner char
  block:
    echo "Test idempotency"
    var buff: Buffer
    doAssert buff.data.len > 0
    var text = newSeq[Rune]()
    for i in 0 .. buff.data.len:
      text.add(Rune(0x0300))
    doAssert(toNFC(text) == toNFC(toNFC(text)))
    doAssert(toNFKC(text) == toNFKC(toNFKC(text)))
    doAssert(toNFD(text) == toNFD(toNFD(text)))
    doAssert(toNFKD(text) == toNFKD(toNFKD(text)))
