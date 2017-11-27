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

iterator items[T](it: (iterator: T)): T {.inline.} =
  # This is missing from stdlib
  while true:
    let i = it()
    if finished(it):
      break
    yield i

type
  Buffer = tuple
    ## A buffer has a fixed size but works
    ## as if it were dynamic by tracking
    ## the last index in use
    data: array[32, int]
    pt: int
  UnBuffer = seq[int]
    ## For testing purposes
  SomeBuffer = (Buffer | UnBuffer)

iterator items(buffer: Buffer): int {.inline.} =
  var i = 0
  while i < buffer.pt:
    yield buffer.data[i]
    inc i

proc isFull(buffer: Buffer): bool {.inline.} =
  buffer.pt == buffer.data.len

proc clear(buffer: var Buffer) {.inline.} =
  buffer.pt = 0

proc add(buffer: var Buffer, elm: int) {.inline.} =
  assert(not buffer.isFull)
  buffer.data[buffer.pt] = elm
  inc buffer.pt

proc len(buffer: Buffer): int {.inline.} =
  buffer.pt

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

const nfMasks: array[NfType, array[2, (NfMasks, QcStatus)]] = [
  [
    (NfMasks.NfcQcNo, QcStatus.NO),
    (NfMasks.NfcQcMaybe, QcStatus.MAYBE)
  ],
  [
    (NfMasks.NfkcQcNo, QcStatus.NO),
    (NfMasks.NfkcQcMaybe, QcStatus.MAYBE)
  ],
  [
    (NfMasks.NfdQcNo, QcStatus.NO),
    (NfMasks.NfdQcNo, QcStatus.NO)
  ],
  [
    (NfMasks.NfkdQcNo, QcStatus.NO),
    (NfMasks.NfkdQcNo, QcStatus.NO)
  ]
]

proc isAllowed(qc: int, nfType: NfType): QcStatus {.inline.} =
  ## Return the quick check property value
  result = QcStatus.YES
  for mask, status in items(nfMasks[nfType]):
    if (qc and mask.ord) != 0:
      result = status
      break

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
    return SBase + (LIndex * VCount + VIndex) * TCount

  let
    SIndex = cpA - SBase
    TIndex = cpB - TBase
  if 0 <= SIndex and SIndex < SCount and
      (SIndex mod TCount) == 0 and
      0 < TIndex and TIndex < TCount:
    return cpA + TIndex

  return -1

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
  var i = cps.len - 1
  while i > 0:
    var isSwapped = false
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
    return result

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
    let hdcp = hangulDecomposition(cp)
    if hdcp.len == 0:
      result.add(cp)
      return result
    return hdcp

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
    let hdcp = hangulDecomposition(cp)
    if hdcp.len == 0:
      result.add(cp)
      return result
    return hdcp

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

const
  nfDecompositions = [
    canonicalDcp,
    compatibilityDecomposition,
    canonicalDcp,
    compatibilityDecomposition]
  graphemeJoiner = 0x034F

proc toNF(cps: (iterator: Rune), nfType: NfType): (iterator: Rune) =
  ## Buffered unicode normalization
  let
    decompose = nfDecompositions[nfType.ord]
    isComposable = nfType in {NfType.NFC, NfType.NFKC}
  var
    buff: Buffer
    cccs: Buffer
    lastCCC = 0
  result = iterator: Rune {.closure.} =
    for rune in cps:
      let cp = int(rune)
      for dcp in decompose(cp):
        let
          props = properties(dcp)
          ccc = combining(props)
          qc = quickCheck(props)
          isSafeBreak = (
            isAllowed(qc, nfType) == QcStatus.YES and
            ccc == 0)
        if isSafeBreak or buff.isFull:
          # Flush the buffer
          buff.canonicSort(cccs)
          if isComposable:
            buff.canonicalComposition()
          for bcp in buff:
            yield Rune(bcp)
          buff.clear()
          cccs.clear()
          # Put a CGJ beetwen non-starters
          if lastCCC != 0 and ccc != 0:
            yield Rune(graphemeJoiner)
        lastCCC = ccc
        buff.add(dcp)
        cccs.add(ccc)
    # Flush the buffer
    buff.canonicSort(cccs)
    if isComposable:
      buff.canonicalComposition()
    for bcp in buff:
      yield Rune(bcp)

proc toRunes(text: seq[Rune]): (iterator: Rune) =
  result = iterator: Rune {.closure.} =
    for cp in text:
      yield cp

proc toRunes(text: ref seq[Rune]): (iterator: Rune) =
  result = iterator: Rune {.closure.} =
    for cp in text[]:
      yield cp

proc toRunes(text: string): (iterator: Rune) =
  result = iterator: Rune {.closure.} =
    for cp in runes(text):
      yield cp

proc toRunes(text: ref string): (iterator: Rune) =
  result = iterator: Rune {.closure.} =
    for cp in runes(text[]):
      yield cp

proc toRunes(text: (iterator: Rune)): (iterator: Rune) {.inline.} =
  # no-op
  text

type
  IterRunes* = (seq[Rune] | ref seq[Rune] | (iterator: Rune))

iterator toNFD*(cps: IterRunes): Rune {.inline.} =
  ## Iterates over each normalized unicode character.
  ## Passing a ref or iterator will make this take O(1) space,
  ## otherwise the sequence gets copied once.
  # Call items explicitly here coz it's private
  for cp in toNF(toRunes(cps), NfType.NFD).items:
    yield cp

iterator toNFC*(cps: IterRunes): Rune {.inline.} =
  ## Iterates over each normalized unicode character.
  ## Passing a ref or iterator will make this take O(1) space,
  ## otherwise the sequence gets copied once.
  for cp in toNF(toRunes(cps), NfType.NFC).items:
    yield cp

iterator toNFKD*(cps: IterRunes): Rune {.inline.} =
  ## Iterates over each normalized unicode character.
  ## Passing a ref or iterator will make this take O(1) space,
  ## otherwise the sequence gets copied once.
  for cp in toNF(toRunes(cps), NfType.NFKD).items:
    yield cp

iterator toNFKC*(cps: IterRunes): Rune {.inline.} =
  ## Iterates over each normalized unicode character.
  ## Passing a ref or iterator will make this take O(1) space,
  ## otherwise the sequence gets copied once.
  for cp in toNF(toRunes(cps), NfType.NFKC).items:
    yield cp

proc toNF(cps: seq[Rune], nfType: NfType): seq[Rune] {.inline.} =
  result = newSeqOfCap[Rune](cps.len)
  for cp in toNF(toRunes(cps), nfType):
    result.add(cp)

proc toNF(cps: string, nfType: NfType): string {.inline.} =
  result = newStringOfCap(cps.len)
  for cp in toNF(toRunes(cps), nfType):
    result.add(cp.toUTF8)

proc toNFD*[T: seq[Rune] | string](cps: T): T =
  ## Return the normalized input
  toNF(cps, NfType.NFD)

proc toNFC*[T: seq[Rune] | string](cps: T): T =
  ## Return the normalized input
  toNF(cps, NfType.NFC)

proc toNFKD*[T: seq[Rune] | string](cps: T): T =
  ## Return the normalized input
  toNF(cps, NfType.NFKD)

proc toNFKC*[T: seq[Rune] | string](cps: T): T =
  ## Return the normalized input
  toNF(cps, NfType.NFKC)

proc toNFUnbuffered(cps: seq[Rune], nfType: NfType): seq[Rune] =
  ## This exists for testing purposes
  let
    decompose = nfDecompositions[nfType.ord]
    isComposable = nfType in [NfType.NFC, NfType.NFKC]
  var
    cpsB = newSeqOfCap[int](result.len)
    cccs = newSeqOfCap[int](result.len)
  for rune in cps:
    for dcp in decompose(rune.int):
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

iterator runes(cps: seq[Rune]): Rune {.inline.} =
  # no-op
  for cp in cps:
    yield cp

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
      return QcStatus.NO
    let check = isAllowed(quickCheck(props), nfType)
    if check == QcStatus.NO:
      return QcStatus.NO
    if check == QcStatus.MAYBE:
      result = QcStatus.MAYBE
    lastCanonicalClass = canonicalClass

proc isNFC*(cps: (seq[Rune] | string)): bool {.inline.} =
  ## Return whether the unicode characters
  ## are normalized or not
  isNF(cps, NfType.NFC) == QcStatus.YES

proc isNFD*(cps: (seq[Rune] | string)): bool {.inline.} =
  ## Return whether the unicode characters
  ## are normalized or not
  isNF(cps, NfType.NFD) == QcStatus.YES

proc isNFKC*(cps: (seq[Rune] | string)): bool {.inline.} =
  ## Return whether the unicode characters
  ## are normalized or not
  isNF(cps, NfType.NFKC) == QcStatus.YES

proc isNFKD*(cps: (seq[Rune] | string)): bool {.inline.} =
  ## Return whether the unicode characters
  ## are normalized or not
  isNF(cps, NfType.NFKD) == QcStatus.YES

when isMainModule:
  echo len(toNFC(@[Rune(0x00C8)]))
  echo len(toNFD(@[Rune(0x00C8)]))
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
