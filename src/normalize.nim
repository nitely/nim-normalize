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

import unicode except fastRuneAt

import unicodedb/compositions
import unicodedb/decompositions
import unicodedb/properties

# XXX remove, taken from stdlib
#     stdlib proc does not accept openArray
const replRune = Rune(0xFFFD)
template ones(n: untyped): untyped = ((1 shl n)-1)
template fastRuneAt(s: openArray[char], i: int, result: untyped, doInc = true) =
  bind ones
  if ord(s[i]) <=% 127:
    result = Rune(ord(s[i]))
    when doInc: inc(i)
  elif ord(s[i]) shr 5 == 0b110:
    if i <= s.len - 2:
      result = Rune((ord(s[i]) and (ones(5))) shl 6 or
                    (ord(s[i+1]) and ones(6)))
      when doInc: inc(i, 2)
    else:
      result = replRune
      when doInc: inc(i)
  elif ord(s[i]) shr 4 == 0b1110:
    if i <= s.len - 3:
      result = Rune((ord(s[i]) and ones(4)) shl 12 or
               (ord(s[i+1]) and ones(6)) shl 6 or
               (ord(s[i+2]) and ones(6)))
      when doInc: inc(i, 3)
    else:
      result = replRune
      when doInc: inc(i)
  elif ord(s[i]) shr 3 == 0b11110:
    if i <= s.len - 4:
      result = Rune((ord(s[i]) and ones(3)) shl 18 or
               (ord(s[i+1]) and ones(6)) shl 12 or
               (ord(s[i+2]) and ones(6)) shl 6 or
               (ord(s[i+3]) and ones(6)))
      when doInc: inc(i, 4)
    else:
      result = replRune
      when doInc: inc(i)
  elif ord(s[i]) shr 2 == 0b111110:
    if i <= s.len - 5:
      result = Rune((ord(s[i]) and ones(2)) shl 24 or
               (ord(s[i+1]) and ones(6)) shl 18 or
               (ord(s[i+2]) and ones(6)) shl 12 or
               (ord(s[i+3]) and ones(6)) shl 6 or
               (ord(s[i+4]) and ones(6)))
      when doInc: inc(i, 5)
    else:
      result = replRune
      when doInc: inc(i)
  elif ord(s[i]) shr 1 == 0b1111110:
    if i <= s.len - 6:
      result = Rune((ord(s[i]) and ones(1)) shl 30 or
               (ord(s[i+1]) and ones(6)) shl 24 or
               (ord(s[i+2]) and ones(6)) shl 18 or
               (ord(s[i+3]) and ones(6)) shl 12 or
               (ord(s[i+4]) and ones(6)) shl 6 or
               (ord(s[i+5]) and ones(6)))
      when doInc: inc(i, 6)
    else:
      result = replRune
      when doInc: inc(i)
  else:
    result = Rune(ord(s[i]))
    when doInc: inc(i)

# A Rune is a distinct int32. Well, not anymore...
converter toInt32(x: Rune): int32 = x.int32
converter toRune(x: int32): Rune = x.Rune

type
  Buffer = object
    ## A buffer has a fixed size but works
    ## as if it were dynamic by tracking
    ## the last index in use
    data: array[32, int32]
    pos: int
  UnBuffer = seq[int32]
    ## For testing purposes
  SomeBuffer = Buffer or UnBuffer

iterator items(buffer: Buffer): int32 {.inline.} =
  var i = 0
  while i < buffer.pos:
    yield buffer.data[i]
    inc i

iterator pairs(buffer: Buffer): (int, int32) {.inline.} =
  var i = 0
  for n in buffer:
    yield (i, n)
    inc i

proc left(buffer: Buffer): int {.inline.} =
  ## return capacity left
  buffer.data.len - buffer.pos

proc clear(buffer: var Buffer) {.inline.} =
  buffer.pos = 0

proc add(buffer: var Buffer, x: int32) {.inline.} =
  assert buffer.left > 0
  buffer.data[buffer.pos] = x
  inc buffer.pos

proc len(buffer: Buffer): int {.inline.} =
  buffer.pos

proc high(buffer: Buffer): int {.inline.} =
  buffer.pos - 1

proc setLen(buffer: var Buffer, i: int) {.inline.} =
  assert i <= buffer.data.len
  buffer.pos = i

proc `[]`(buffer: var Buffer, i: int): var int32 {.inline.} =
  assert i < buffer.pos
  buffer.data[i]

proc `[]=`(buffer: var Buffer, i: int, x: int32) {.inline.} =
  assert i < buffer.pos
  buffer.data[i] = x

proc reverse(buffer: var Buffer) {.inline.} =
  var x = 0
  var y = max(0, buffer.len - 1)
  while x < y:
    swap(buffer.data[x], buffer.data[y])
    dec(y)
    inc(x)

proc pop(buffer: var Buffer): int32 {.inline.} =
  assert buffer.len-1 >= 0
  result = buffer.data[buffer.len - 1]
  dec buffer.pos

proc `==`(a, b: Buffer): bool =
  a.data.toOpenArray(0, a.len-1) == b.data.toOpenArray(0, b.len-1)

type
  NfType = enum
    nftNfc
    nftNfkc
    nftNfd
    nftNfkd

  QcStatus = enum
    qcsYes
    qcsNo
    qcsMaybe

const nfMasks: array[NfType, array[2, (NfMask, QcStatus)]] = [
  [(nfcQcNo, qcsNo),
   (nfcQcMaybe, qcsMaybe)],
  [(nfkcQcNo, qcsNo),
   (nfkcQcMaybe, qcsMaybe)],
  [(nfdQcNo, qcsNo),
   (nfdQcNo, qcsNo)],
  [(nfkdQcNo, qcsNo),
   (nfkdQcNo, qcsNo)]]

proc isAllowed(qc: int, nfType: NfType): QcStatus {.inline.} =
  ## Return the quick check property value
  result = qcsYes
  for mask, status in items(nfMasks[nfType]):
    if mask in qc:
      result = status
      return

proc primaryComposite(r: var Rune, rA: Rune, rB: Rune): bool {.inline.} =
  ## Find the composition of two decomposed CPs
  # This does not include hangul chars
  # as those can be dynamically computed
  result = composition(r, rA, rB)

# Hangul
const
  SBase = 0xAC00'i32
  LBase = 0x1100'i32
  VBase = 0x1161'i32
  TBase = 0x11A7'i32
  LCount = 19'i32
  VCount = 21'i32
  TCount = 28'i32
  NCount = VCount * TCount
  SCount = LCount * NCount

proc hangulComposition(rA: Rune, rB: Rune): Rune =
  ## Return hangul composition.
  ## Return -1 if not found
  let
    LIndex = rA - LBase
    VIndex = rB - VBase
  if 0 <= LIndex and LIndex < LCount and
      0 <= VIndex and VIndex < VCount:
    result = SBase + (LIndex * VCount + VIndex) * TCount
    return
  let
    SIndex = rA - SBase
    TIndex = rB - TBase
  if 0 <= SIndex and SIndex < SCount and
      (SIndex mod TCount) == 0 and
      0 < TIndex and TIndex < TCount:
    result = rA + TIndex
    return
  result = -1'i32

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
    pos = 0
    pcp: Rune
  for cp in cps:
    # Hangul composition
    if lastStarterIdx != -1 and
        lastStarterIdx + 1 == pos:  # At head
      let cpc = hangulComposition(cps[lastStarterIdx], cp)
      if cpc != -1:
        cps[lastStarterIdx] = cpc
        lastCCC = 0
        continue
    # Starter can be non-assigned
    let ccc = combining(cp)
    if lastStarterIdx == -1:
      if ccc == 0:
        lastStarterIdx = pos
      lastCCC = ccc
      cps[pos] = cp
      inc pos
      continue
    # Because the string is in canonical order,
    # testing whether a character is blocked requires
    # looking only at the immediately preceding char
    if lastCCC >= ccc and lastCCC > 0:
      lastCCC = ccc
      cps[pos] = cp
      inc pos
      continue
    if primaryComposite(pcp, cps[lastStarterIdx], cp):
      cps[lastStarterIdx] = pcp
      assert combining(pcp) == 0
      lastCCC = 0
      continue
    if ccc == 0:
      lastStarterIdx = pos
      lastCCC = 0
      cps[pos] = cp
      inc pos
      continue
    lastCCC = ccc
    cps[pos] = cp
    inc pos
  cps.setLen(pos)

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
  assert len(cps) == len(cccs)
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
      return
    dec i

proc hangulDecomposition(r: Rune): Buffer =
  let SIndex = r - SBase
  if 0 > SIndex and SIndex >= SCount:
    return
  result.add(LBase + SIndex div NCount)  # L
  result.add(VBase + (SIndex mod NCount) div TCount)  # V
  let T = TBase + SIndex mod TCount
  if T != TBase:
    result.add(T)

proc isHangul(r: Rune): bool {.inline.} =
  0xAC00 <= r and r <= 0xD7A3

template decomposeImpl(result, r, decompositionProc) =
  ## Return 4 code points at most for NFD and NFC.
  ## Return 18 code points at most for NFKD and NFKC.
  ## It does a full decomposition
  if r.isHangul:
    result = hangulDecomposition(r)
    if result.len == 0:
      result.add(r)
  else:
    result.clear()
    var queue: Buffer
    queue.add(r)
    while queue.len > 0:
      let
        curCp = queue.pop()
        lastLen = queue.len
      for dcp in decompositionProc(curCp.Rune):
        queue.add(dcp)
      if lastLen == queue.len:  # No decomposition
        result.add(curCp)
    result.reverse()

template decompose(result, r, nfType) =
  when nfType in {nftNfc, nftNfd}:
    decomposeImpl(result, r, canonicalDecomposition)
  else:
    decomposeImpl(result, r, decomposition)

const graphemeJoiner = 0x034F.Rune

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
    buff, cccs, dcps: Buffer
    lastCCC = 0
  for done, r in runesN(s):
    decompose(dcps, r, nfType)
    for i, cp in pairs(dcps):
      let
        finished = done and i == dcps.high
        props = properties(cp)
        ccc = combining(props).int32  # todo: return i8?
        qc = quickCheck(props)
        isSafeBreak =
          isAllowed(qc, nfType) == qcsYes and
          ccc == 0
      if finished or isSafeBreak or buff.left == 1:
        if finished:
          buff.add(cp)
          cccs.add(ccc)
        # Flush the buffer
        buff.canonicSort(cccs)
        when nfType in {nftNfc, nftNfkc}:
          buff.canonicalComposition()
        for bcp in items(buff):
          yield Rune(bcp)
        buff.clear()
        cccs.clear()
        # Put a CGJ beetwen non-starters
        if lastCCC != 0 and ccc != 0:
          buff.add(graphemeJoiner)
          cccs.add(0)
      lastCCC = ccc
      buff.add(cp)
      cccs.add(ccc)

iterator toNFD*(s: string): Rune {.inline.} =
  ## Iterates over each normalized unicode character
  for r in toNF(s, nftNfd):
    yield r

iterator toNFD*(s: seq[Rune]): Rune {.inline, deprecated: "Use toNFD(string)".} =
  ## Iterates over each normalized unicode character
  for r in toNF(s, nftNfd):
    yield r

iterator toNFC*(s: string): Rune {.inline.} =
  ## Iterates over each normalized unicode character
  for r in toNF(s, nftNfc):
    yield r

iterator toNFC*(s: seq[Rune]): Rune {.inline, deprecated: "Use toNFC(string)".} =
  ## Iterates over each normalized unicode character
  for r in toNF(s, nftNfc):
    yield r

iterator toNFKD*(s: string): Rune {.inline.} =
  ## Iterates over each normalized unicode character
  for r in toNF(s, nftNfkd):
    yield r

iterator toNFKD*(s: seq[Rune]): Rune {.inline, deprecated: "Use toNFKD(string)".} =
  ## Iterates over each normalized unicode character
  for r in toNF(s, nftNfkd):
    yield r

iterator toNFKC*(s: string): Rune {.inline.} =
  ## Iterates over each normalized unicode character
  for r in toNF(s, nftNfkc):
    yield r

iterator toNFKC*(s: seq[Rune]): Rune {.inline, deprecated: "Use toNFKC(string)".} =
  ## Iterates over each normalized unicode character
  for r in toNF(s, nftNfkc):
    yield r

proc toNF(s: seq[Rune], nfType: static[NfType]): seq[Rune] =
  # the grow factor used to be
  # passed by every Nf. But
  # now we just grow it when needed.
  # Nf's grow factors
  # are 3x (NFC), 4x (NFD)
  # and 18x (NFKC/NFKD), so growing
  # by 2x seems best
  result = newSeq[Rune](len(s))
  var i = 0
  for r in toNF(s, nfType):
    if i > result.high:
      result.setLen(result.len*2)
    result[i] = r
    inc i
  result.setLen(i)

proc toNF(s: string, nfType: static[NfType]): string =
  result = newString(len(s))
  var i = 0
  for r in toNF(s, nfType):
    if i >= result.high:
      result.setLen(result.len*2)
    fastToUTF8Copy(r, result, i, true)
  result.setLen(i)

proc toNFD*(s: string): string =
  ## Return the normalized input.
  ## Result may take 3 times
  ## the size of the input
  toNF(s, nftNfd)

proc toNFD*(s: seq[Rune]): seq[Rune] {.deprecated: "Use toNFD(string)".} =
  ## Return the normalized input.
  ## Result may take 4 times
  ## the size of the input
  toNF(s, nftNfd)

proc toNFC*(s: string): string =
  ## Return the normalized input.
  ## Result may take 3 times
  ## the size of the input
  toNF(s, nftNfc)

proc toNFC*(s: seq[Rune]): seq[Rune] {.deprecated: "Use toNFC(string)".} =
  ## Return the normalized input.
  ## Result may take 3 times
  ## the size of the input
  toNF(s, nftNfc)

proc toNFKD*(s: string): string =
  ## Return the normalized input.
  ## Result may take 11 times
  ## the size of the input
  toNF(s, nftNfkd)

proc toNFKD*(s: seq[Rune]): seq[Rune] {.deprecated: "Use toNFKD(string)".} =
  ## Return the normalized input.
  ## Result may take 18 times
  ## the size of the input
  toNF(s, nftNfkd)

proc toNFKC*(s: string): string =
  ## Return the normalized input.
  ## Result may take 11 times
  ## the size of the input
  toNF(s, nftNfkc)

proc toNFKC*(s: seq[Rune]): seq[Rune] {.deprecated: "Use toNFKC(string)".} =
  ## Return the normalized input.
  ## Result may take 18 times
  ## the size of the input
  toNF(s, nftNfkc)

proc toNFUnbuffered(
    cps: seq[Rune],
    nfType: static[NfType]): seq[Rune] {.used.} =
  ## This exists for testing purposes
  let isComposable = nfType in [nftNfc, nftNfkc]
  var
    cpsB = newSeqOfCap[int32](result.len)
    cccs = newSeqOfCap[int32](result.len)
    dcps: Buffer
  for rune in cps:
    decompose(dcps, rune, nfType)
    for dcp in dcps:
      cpsB.add(dcp)
      cccs.add(combining(dcp).int32)
  cpsB.canonicSort(cccs)
  if isComposable:
    cpsB.canonicalComposition()
  result = newSeq[Rune](cpsB.len)
  for i, cp in cpsB:
    result[i] = Rune(cp)

proc isSupplementary(r: Rune): bool {.inline.} =
  ## Check a given code point is within a private area
  # Private areas
  result = (
    (0x100000 <= r and r <= 0x10FFFD) or
    (0xF0000 <= r and r <= 0xFFFFF))

iterator runes(s: seq[Rune]): Rune {.inline.} =
  # no-op
  for r in s:
    yield r

proc isNF(cps: (seq[Rune] | string), nfType: NfType): QcStatus =
  ## This may return a Maybe
  ## result, even if the string
  ## is perfectly normalized.
  ## Result ain't always Yes or No
  result = qcsYes
  var
    lastCanonicalClass = 0
    skipOne = false
  for r in runes(cps):
    if skipOne:
      skipOne = false
      continue
    if isSupplementary(r):
      skipOne = true
    let
      props = properties(r)
      canonicalClass = combining(props)
    if lastCanonicalClass > canonicalClass and canonicalClass != 0:
      result = qcsNo
      return
    let check = isAllowed(quickCheck(props), nfType)
    if check == qcsNo:
      result = qcsNo
      return
    if check == qcsMaybe:
      result = qcsMaybe
    lastCanonicalClass = canonicalClass

proc isNFC*(s: string): bool {.inline.} =
  ## Return whether the unicode characters
  ## are normalized or not. For some inputs
  ## the result is always ``false`` (even if it's normalized)
  isNF(s, nftNfc) == qcsYes

proc isNFC*(s: seq[Rune]): bool {.inline, deprecated: "Use isNFC(string)".} =
  ## Return whether the unicode characters
  ## are normalized or not. For some inputs
  ## the result is always ``false`` (even if it's normalized)
  isNF(s, nftNfc) == qcsYes

proc isNFD*(s: string): bool {.inline.} =
  ## Return whether the unicode characters
  ## are normalized or not. For some inputs
  ## the result is always ``false`` (even if it's normalized)
  isNF(s, nftNfd) == qcsYes

proc isNFD*(s: seq[Rune]): bool {.inline, deprecated: "Use isNFD(string)".} =
  ## Return whether the unicode characters
  ## are normalized or not. For some inputs
  ## the result is always ``false`` (even if it's normalized)
  isNF(s, nftNfd) == qcsYes

proc isNFKC*(s: string): bool {.inline.} =
  ## Return whether the unicode characters
  ## are normalized or not. For some inputs
  ## the result is always ``false`` (even if it's normalized)
  isNF(s, nftNfkc) == qcsYes

proc isNFKC*(s: seq[Rune]): bool {.inline, deprecated: "Use isNFKC(string)".} =
  ## Return whether the unicode characters
  ## are normalized or not. For some inputs
  ## the result is always ``false`` (even if it's normalized)
  isNF(s, nftNfkc) == qcsYes

proc isNFKD*(s: string): bool {.inline.} =
  ## Return whether the unicode characters
  ## are normalized or not. For some inputs
  ## the result is always ``false`` (even if it's normalized)
  isNF(s, nftNfkd) == qcsYes

proc isNFKD*(s: seq[Rune]): bool {.inline, deprecated: "Use isNFKD(string)".} =
  ## Return whether the unicode characters
  ## are normalized or not. For some inputs
  ## the result is always ``false`` (even if it's normalized)
  isNF(s, nftNfkd) == qcsYes

# todo: cmpNfkd for compat cmp
proc cmpNfd*(a, b: openArray[char]): bool =
  ## Compare two strings
  ## are canonically equivalent.
  ## This is more efficient than
  ## normalizing + comparing, as it
  ## does not create temporary strings
  ## (i.e it won't allocate).
  template fillBuffer(
    s: openArray[char],
    ni, di: var int,
    r: var Rune,
    buff, cccs, dcps: var Buffer,
    cp, ccc: var int32
  ) =
    ## This is meant to be called and
    ## resumed later with a partially
    ## consumed "decomposed rune"
    assert ni <= len(s)
    assert di <= len(dcps)
    block fillBuff:
      # decompose s[ni] into dcps
      # and fill buff and cccs buffers
      while ni < len(s) or di < len(dcps):
        if di == len(dcps):
          di = 0
          fastRuneAt(s, ni, r, true)
          decompose(dcps, r, nftNfd)
        while di < len(dcps):
          cp = dcps[di]
          let props = properties(cp)
          ccc = combining(props).int32 # todo: return i8?
          let
            qc = quickCheck(props)
            isSafeBreak =
              isAllowed(qc, nftNfd) == qcsYes and
              ccc == 0
            finished = ni == len(s) and di == high(dcps)
          if not finished and (isSafeBreak or buff.left == 1):
            break fillBuff
          buff.add(cp)
          cccs.add(ccc)
          inc di
  result = true
  var
    cpa, cpb, ccca, cccb: int32
    ra, rb: Rune
    nia, nib, dia, dib = 0
    buffa, cccsa, dcpsa: Buffer
    buffb, cccsb, dcpsb: Buffer
  while nia < len(a) or dia < len(dcpsa) or
        nib < len(b) or dib < len(dcpsb):
    fillBuffer(a, nia, dia, ra, buffa, cccsa, dcpsa, cpa, ccca)
    fillBuffer(b, nib, dib, rb, buffb, cccsb, dcpsb, cpb, cccb)
    buffa.canonicSort(cccsa)
    buffb.canonicSort(cccsb)
    result = buffa == buffb
    if not result:
      return
    buffa.clear()
    cccsa.clear()
    if nia < len(a) or dia < len(dcpsa):
      buffa.add(cpa)
      cccsa.add(ccca)
      inc dia
    buffb.clear()
    cccsb.clear()
    if nib < len(b) or dib < len(dcpsb):
      buffb.add(cpb)
      cccsb.add(cccb)
      inc dib

when isMainModule:
  block:
    echo "Test random text"
    var
      text = newSeq[Rune]()
      text2 = ""
    for line in lines("./tests/TestNormRandomText.txt"):
      text.add(line.toRunes)
      text2.add(line)
    doAssert toNFUnbuffered(text, nftNfd) == toNFD(text)
    doAssert toNFUnbuffered(text, nftNfc) == toNFC(text)
    doAssert toNFUnbuffered(text, nftNfkc) == toNFKC(text)
    doAssert toNFUnbuffered(text, nftNfkd) == toNFKD(text)

    doAssert isNFD(toNFD(text))
    doAssert isNFC(toNFC(text))
    doAssert isNFKC(toNFKC(text))
    doAssert isNFKD(toNFKD(text))
    doAssert isNFD(toNFD(text2))
    doAssert isNFC(toNFC(text2))
    doAssert isNFKC(toNFKC(text2))
    doAssert isNFKD(toNFKD(text2))

    doAssert cmpNfd(toNfd(text2), toNfd(text2))
    doAssert cmpNfd(toNfc(text2), toNfc(text2))
    doAssert cmpNfd(toNfc(text2), toNfd(text2))
    doAssert cmpNfd(text2, toNfd(text2))
    doAssert cmpNfd(text2, toNfc(text2))
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
