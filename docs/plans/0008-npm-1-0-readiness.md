# Plan: the npm package before 1.0: Node 24, fast string reads, bounded wasm memory

Status: approved by Sonnet and Terra (round 5); not yet implemented.

## Problem

`@jbearak/dta-parser` 1.0 has never been published (npm has 0.11.2).
Before it is, the user wants:

1. **Node.** Require Node 24 or later, and use what that allows.
2. **Faster reads, above all of strings.** In TypeScript a full read of
   groups.dta (15M rows, a byte and a str17) takes 1.68 s; R takes
   0.12 s and Python 0.27 s. The string column alone takes 1.62 s.
   long.dta takes 2.41 s (strings 2.13 s). Sight measured 10M `str12` at
   1,046 ms, against 537 ms in 0.6.
3. **Bounded wasm memory.** Sight's tests of the 1.0 tarball found:
   - the strL index costs 106–130 bytes per strL (a `HashMap`), so about
     40M strLs fill the 4 GiB instance, and it **traps** instead of
     returning an error, closing every file open on that instance;
   - decoding a strL reserves three times its length, so a 500 MB strL
     grows RSS by 1.9 GiB and a 1 GB strL fails;
   - wasm memory never shrinks, so after a 500 MB strL, RSS stays at
     1,924 MiB after `close()` and GC;
   - previews must read whole values (Sight's D2);
   - each reader builds its own strL index (Sight's D3).
4. **Consumers keep working.** Sight, table-viewer and manuscript-markdown
   are ported to the 1.0 tarball and tested before anything is
   published (see "Release gates").

## Measurements behind the design

All on an M4 Max, Node 26.12.1, unless stated.

**Where a string read's time goes** (groups.dta, string column, CPU
profile): garbage collection 520 ms, the per-cell `TextDecoder.decode`
loop 99 ms of JavaScript plus decoding, the wasm decode 143 ms. 15M
string objects are made for 300 distinct values.

**Prototypes, through the real wasm module** (a temporary export, since
reverted; script kept outside the repo). Each reads one string column
through `dta_read` windows, then builds `string[]`:

| file, column | per-cell decode (today) | one decode + `substring` | dictionary in wasm |
|---|---|---|---|
| groups.dta str17 (300 distinct) | 1,589 ms, heap after GC 691 MiB | 760 ms, 576 MiB | **580 ms, 119 MiB** |
| long.dta str5 (4 distinct) | 992 ms, 309 MiB | 400 ms, 309 MiB | **355 ms, 80 MiB** |

The heap left after a dictionary read is the `string[]` itself (8 bytes
a row). With `{ kind: "dictionary" }` (Sight's D1) not even that is
made: the codes are a 4-byte-a-row `Uint32Array` outside the heap.

Natively, building the dictionary adds 0.11–0.18 s to 10–15M rows
(std's SipHash). On a column of 10M distinct values the rule below gives
up after 65,537 rows at no measurable cost. Filling 15M rows of
`string[]` from 300 values takes 25 ms in JavaScript.

**Ways to make 1M strings of 5–17 ASCII bytes** from one buffer with
end offsets:

| method | ms per 1M |
|---|---|
| `TextDecoder.decode` per cell (today) | 84 |
| `Buffer.utf8Slice` / `latin1Slice` per cell | 49–52 |
| one `decode` of the whole buffer, then `substring` per cell | 22–25 |

**Where a numeric read's time goes** (wide.dta, 2.28 s): wasm decode
883 ms, copying out of wasm memory 518 ms, `Column::append` inside wasm
336 ms, the call's bookkeeping 261 ms, reading the file 218 ms.

**Node 24 (V8 13.6) and 26 (V8 14.6), probed directly:**

| feature | 24 | 26 | use here |
|---|---|---|---|
| wasm memory64 | yes | yes | Rust's `wasm64-unknown-unknown` is tier 3: nightly and `-Zbuild-std` only. Not adopted. |
| `wasm:js-string` builtins | yes | yes | build strings from wasm GC arrays, which Rust cannot produce. Not usable. |
| `using` / `Symbol.dispose` | yes | yes | readers that close themselves. Adopted. |
| `WebAssembly.Memory.prototype.toResizableBuffer` | no | yes | Node 26 only. Not relied on. |
| `Uint8Array.fromBase64` | no | yes | Node 26 only. Not relied on. |
| wasm SIMD128 | yes | yes | measured no gain on reads (1–3%, within noise). Not adopted. |

VS Code runs extensions on Node 24 (1.123 and later, through 1.144),
so nothing here may need Node 26. Node 24 is a policy choice, not a
technical need: no adopted feature needs more than Node 20 except
`Symbol.dispose` (Node 24 has it without flags).

## Design

### N. Node 24

- `engines.node` `>=24`; esbuild target `node24` (build.mjs and
  js/test/bundle.test.mjs); `@types/node` `^24`; CI's npm and readback
  jobs on Node 24, and the npm job also on 26.
- `DtaReader` gets `[Symbol.dispose]()`, which does exactly what
  `close()` does: it never closes an fd the caller passed in (a borrowed
  fd stays open, as with `close()`). Tested both ways.
- CONTRIBUTING.md, docs/typescript.md and the README say Node 24; ADR
  0002 gains a note that Node 24 is the floor.
- docs/research/node-24.md records the probe table, with how each row
  was tested, and Sight's measurements: the 1.0
  tarball runs on Node 18.20.8 and fails to compile its wasm on 16.20.2
  (reference types); VS Code 1.123 (Electron 42, Node 24.15) is the
  first release on Node 24, and 1.144 is on Node 24.22.1. No Node
  26-only feature may be used: VS Code does not ship Node 26.

### E. Error codes

Errors the package throws carry a `code`, documented and tested:

| code | when | class |
|---|---|---|
| `DTA_TOO_LARGE` | the value or read does not fit the module's memory, or a text value exceeds V8's longest string | `Error` |
| `DTA_CLOSED` | the reader is closed, or its module instance was replaced | `Error` |
| `DTA_CORRUPT` | the file is damaged, or no longer matches what was read before (index check, below) | `Error` |
| `DTA_OUT_OF_RANGE` | rows or a variable outside the file | `RangeError` |
| `DTA_INVALID` | bad arguments, including to the writer | `TypeError` or `RangeError` |
| `DTA_IO` | the `ReadAt` callback or the file system failed | `Error` |

The core's `dta::Error` gains a `kind` (`Corrupt`, `TooLarge`, `Io`,
`Invalid`, `OutOfRange`), set where each error is made; `Error::new`
and `Error::at` keep their meaning with `Corrupt` as the default kind,
and the sites that mean something else (allocation failures, source
read failures, argument checks) say so. The wasm module passes the kind
next to the message (`dta_error_kind()`), and the glue maps it to a
code without reading the message. When a `ReadAt` callback throws, the
glue keeps that exception and throws `DTA_IO` with it as `cause`.

### S. String reads

**S1. A dictionary in the wasm module.** For each string column of a
`readColumns` call, the module builds a dictionary: distinct values in
order of first appearance, a `u32` code per row. It lives in
`crates/dta-ffi/src/wasm.rs`, not the core: R's dictionary (ADR 0011)
stays as it is, so R's behaviour and timings cannot change. It gives up
by all three of ADR 0011's rules: once more than half of at least 65,536
rows are distinct; when it would pass 2^31 − 1 entries; when values
collide in the hash table more than chance allows (a probe-length limit,
since wasm has no random hash keys and a crafted file could aim for
collisions). Values are keyed on their decoded UTF-8 (two invalid inputs that
both decode to U+FFFD are one value). It also gives up when the
distinct values' bytes pass
16 MiB, or at the first binary strL. A column that gives up is plain
from then on.

**Protocol.** `dta_read` gains a flag, "new read", which `readColumns`
sets on its first wasm call and clears on the calls that continue the
same read (a read larger than the 64 MiB budget takes several calls).
"New read" clears every dictionary; dictionaries are also freed when
the last call of a read returns (the glue tells the module with a
"last call" flag, sent from a `finally`, so a read that throws midway
frees them too) and on `close()`, so up to 16 MiB of values does not
linger between reads. Each call first decodes its rows plainly,
then codes them. For each string column a call returns one of:
- codes for all its rows, and the values first seen in this call (bytes
  and UTF-16 ends); or
- all its rows plain (below), when the column gave up before or during
  this call. A call is never part coded and part plain: if it gives up
  partway, it drops that call's codes and returns the plain column it
  already holds.

When a column turns plain partway through a read, JavaScript expands
the codes of earlier calls into strings (it holds every value seen so far),
then continues plain. Codes are stable within one `readColumns` call
and mean nothing across calls; the docs say so. Sight reads in ranges
and remaps each range's few values itself, which it confirmed is fine.

**S2. Plain columns** hand JavaScript the bytes, byte ends and **UTF-16
ends**: the core counts UTF-16 units while it decodes (one per byte that
is not a `0x80..0xBF` continuation byte, plus one more for each
four-byte sequence; the decoded text is always valid UTF-8, since
invalid input is replaced first). For an all-ASCII call the byte ends
are reused and no array is made. Binary strL rows are not part of the
text: their bytes go in a separate buffer with their own ends, so no
`decode` sees them.

**S3. JavaScript.**
- The text decoder is `new TextDecoder("utf-8", { ignoreBOM: true })`,
  so a value that starts with U+FEFF keeps it, wherever it falls in the
  buffer.
- Plain columns: one `decode` per call's text bytes, read as a view
  into module memory (no `.slice()` copy), then `substring` per row by
  UTF-16 ends.
- Dictionary columns: the call's new values are decoded the same way
  and stored; each row of `string[]` points at its value.
- Binary strL rows stay `Uint8Array` copies.
- `readColumns(cols, { strings: "dictionary" })` returns, for string
  columns, `{ kind: "dictionary", codes: Uint32Array, values: string[] }`
  (Sight's D1 exactly), or a plain `string[]` (or `(string|Uint8Array)[]`
  for strLs) where the dictionary gave up. A column holding a binary
  strL therefore never comes back as a dictionary. TypeScript overloads keep today's return type when neither option is
given. With `maxStringBytes`, string columns are `StringColumn & {
storedBytes: Uint32Array }`; with `strings: "dictionary"`, they are
`StringColumn | DictionaryColumn`. `StringColumn` itself does not
change. A type test checks each overload.
- `substring` results share their parent string (V8 sliced strings),
  so one retained cell can keep its call's whole decoded text (at most
  64 MiB) alive. Measured (4M rows, Node 26, heap after GC per row): one decode then
`substring`, 10-character cells, 40.0 B whether the call is all ASCII
or has one `é`; 30-character cells (V8 slices them), 39.8 B in both
cases, so one non-ASCII cell does not widen the call's other cells.
Decoding in 4,096-row blocks instead costs 69.8 B (each block's text
is kept), so one decode per call stays. The Retention test re-measures
this on Node 24 with non-ASCII files.

**Targets** (Node 24, median of 5 runs, fresh process each):
- groups.dta's string column as `string[]`: at most 0.65 s (1.62 s
  today), heap after GC at most 150 MiB;
- as `{ kind: "dictionary" }`: at most 0.45 s;
- long.dta's two string columns: at most 0.9 s (2.13 s today);
- an all-distinct str10 column: at most 0.45 s per 10M rows;
- a str17 column that is 10% non-ASCII (UTF-8) and one in Windows-1252
  (release 117): measured against today and no slower than today's
  per-cell decode; recorded, not gated, since no prototype covered them.

**S4. Python and Julia** are unchanged: they already share one object
per recent value and read groups.dta in 0.27 s and 0.29 s.

### W. wasm read path

**Where the changes live.** The rules only JavaScript needs (ending a
call before V8's string limit, the V8-limit `DTA_TOO_LARGE`, the
dictionary, the emergency reserve) live in the wasm module or behind
read options only it sets, as W1's entry point does, so R, Python and
Julia read as before. Core changes that every binding sees (M1's
checks, M2's fallible allocations, M3's exact reserves, M5's option,
E's `kind`) run the R, Python and Julia suites in their stage; NEWS
lines are added only where behaviour changes (M1's rejections).

**W1. Fewer copies.** Two copies go:
- **inside wasm**, `Column::append`: a new core entry point, used only by
  the wasm module, decodes a call's rows in 2 MiB raw sub-blocks (the
  raw row buffer stays 2 MiB, as today) straight into one set of call
  columns sized for the call. `read_chunks` and so R, Python and Julia
  are unchanged;
- **in JavaScript**, `wasm.part` copies with `.slice()` and
  `readColumns` copies again with `.set()` (js/src/wasm.ts:175,
  js/src/index.ts:225). `readColumns` sets straight from a view of
  module memory, made after the call returns.

Target: wide.dta's full read in TypeScript at least 15% faster (the
measured `append` and copy-out shares are 15% and 23%). If it misses
10%, the change is dropped.

### M. wasm memory

**M1. A compact strL index in the core.** Replace
`HashMap<(u32, u64), StrlEntry>` with sorted parallel arrays: `u64` keys
`v·2^40 + o`, `u64` payload offsets, `u32` lengths, and a bitset of
binary flags: 20.1 bytes per strL. The `(v, o)` fields fit in every
release when `v` < 2^24 and `o` < 2^40 (118 stores `o` in 6 bytes, 119
in 5, 117 both `v` and `o` in 4). A record whose key does not fit (`v` ≥ 2^24 or `o` ≥ 2^40) is
`DTA_CORRUPT`. Keys past nvar or nobs are kept, as today: an entry no
cell refers to is harmless. Both byte orders are tested.
- **Building.** Files written by this library, haven, pandas and
  ReadStat list strLs in key order, so building appends and checks
  order. A file out of order is sorted once (in place, a permutation of
  the four arrays, peak extra memory 8 bytes per strL).
- **Duplicates.** Equal keys are `DTA_CORRUPT` (see C); today's
  `HashMap` silently keeps the last. Tested. This and the key-fit check
  are core changes, so R, Python and Julia reject such files too: the
  M1 stage runs their suites and adds a NEWS line in each package.
- **Lookup.** Binary search, with a cursor: a lookup first tries the
  entry after the previous hit (rows are read in order, so most hits are
  next), then searches.
- **Pre-117 files** have no strLs, so no index.
- Target: 10M strLs index in under 250 MB (1,058 MiB today); building
  it and reading every strL no slower than today (measured).

**M2. No traps.** Running out of module memory becomes `DTA_TOO_LARGE`,
not a trap, on every public call: open, metadata, value labels,
characteristics, `readColumns`, `strlIndex`, adoption, and the writer
calls. Rust aborts when an infallible allocation fails, and a global
allocator may not unwind, so the rule is:
- **every allocation whose size comes from the file or the caller** goes
  through `try_reserve` or a fallible constructor: on open, the
  descriptor blocks `read_vec` reads, variable names, formats and
  labels, value label tables and characteristics; on read, the call's
  columns, byte buffers and ends (budget check first, 3% headroom), strL
  payloads and their decoded text, the strL index arrays and the
  dictionary's table and values; `dta_alloc` returns 0 instead of
  aborting, and JavaScript checks it;
- **every output serialised from those** (metadata, label and
  characteristics JSON, the exported index) is written into a buffer
  reserved fallibly up front at its computed size, not grown;
- what is left is small and fixed (error messages, a few words per
  call). For those the module holds a 1 MiB emergency reserve, an
  allocation nothing else uses: when any fallible reservation fails,
  the reserve is freed first, so building and returning the error
  cannot run out. Each public call starts by re-taking the reserve
  (fallibly); if it cannot, the call returns `DTA_TOO_LARGE` before doing anything,
through an allocation-free path: the error kind is a number and the
message a static string, which `dta_error` returns as is. A test makes a
second call after the reserve could not be re-taken and checks that
error. A test fails an allocation after a large one has succeeded
  and checks the error arrives intact.

The PR lists each allocation site on these paths with the rule it
follows. The JavaScript side reads every pointer and length from wasm as
`>>> 0`, so offsets past 2 GiB are not negative: `host_read`'s and
`host_write`'s `ptr` and `len` (js/src/wasm.ts:51, 59, which arrive as
signed i32), every `dta_column_part` and `dta_result_len` result, and
`dta_alloc`'s, and clamps each
`fs.readSync` to 1 GiB per call (Node rejects 2 GiB and more). Tests
run a test build of the module capped at 64 MiB and, for each public
call, a file that makes that call's largest allocation too big (huge
label tables, characteristics, a wide variable list, an index, columns,
a strL, a dictionary): each throws `DTA_TOO_LARGE`, and a second reader open on the same instance still reads correctly
afterwards. A CI test pushes module memory past 2 GiB (a 2.1 GiB
`dta_alloc` filler, which the OS backs lazily), then reads strN, strL
and numeric columns and writes a file, so every pointer it sees is past
2^31. JavaScript's own allocations for a read (`new Float64Array`,
`new Array`) failing become `DTA_TOO_LARGE`, not a bare `RangeError`.

**M3. Exact room for decoded text.** Decoding reserves what the text
needs, not three times its length: UTF-8 text is validated first, so a
valid value reserves its length and an invalid one its length plus 2
bytes per invalid byte, counted first; single-byte encodings reserve
their length plus one byte per character at `0x80` or above (two for
Windows-1252's `0x80..0x9F` that map above U+07FF), counted first, in place of
the `len × 3` at reader.rs:478. The read budget's strL estimate
(reader.rs:320, also `len × 3`) counts from the index alone, before any
payload is read: the stored length for UTF-8 files (release 118 and
later), where the decoded text is no longer unless bytes are invalid
(then the call may pass its budget; that is safe, since every reserve
is fallible, M2), and `len × 3` for release 117,
whose strLs may be Windows-1252. Chunk sizing (reader.rs:358) keeps its ×3 bound for strN: it
sizes before any text is seen, and over-estimating only makes chunks
smaller. For valid UTF-8 the payload is read straight into the column's
bytes, not through the separate `payload` buffer (reader.rs:471). The glue decodes
straight from a view into module memory, so a strL is not copied out
first. A call's decoded text must also fit one string, since S3 decodes it
once: the core ends a call before the row that would take its text
bytes (an upper bound on UTF-16 units) past 2^29 − 24, so many small
values plus one large strL go in two calls, not one failed decode. A
call's first row is always taken; a single value over the limit is
handled below. The limit is a module setting that `dta_test_set` can lower (T), so
the test runs in the 64 MiB test module: a block of small values
followed by a strL that together pass a lowered limit. A text
value longer than V8's limit (2^29 − 24 UTF-16 units) is
`DTA_TOO_LARGE`, found before its payload is reserved: in UTF-8 a value
has no more UTF-16 units than bytes, so only a value whose stored length
passes the limit is checked, by scanning its payload in 1 MiB pieces
through `host_read` and counting the units it will decode to (U+FFFD
for each invalid subpart counted as one, the decoder's state carried
across pieces), and stopping as soon as the count
passes. In single-byte encodings units equal bytes, so the stored
length decides. Such a value's bytes can still be read with `maxStringBytes`. Targets: a 500 MB text
strL (500M ASCII characters, under V8's limit) read raises RSS by at
most 1.1 GiB (1.9 GiB today); a 1 GB binary strL reads; a 600 MB ASCII
text strL throws `DTA_TOO_LARGE` without growing module memory.

**M4. Memory is given back, and calls do not nest.**
- **No re-entry.** The module's state is borrowed for the length of
  each call, including while it waits on `host_read` or `host_write`.
  The glue keeps a call-depth counter; any package call made while it
  is above zero (from inside a `ReadAt` callback or a write sink) throws
  `DTA_INVALID` before entering wasm. Tests call open, read, close and
  write from inside callbacks and get that error, and the outer call
  then completes normally.
- **Replacement.** wasm memory cannot shrink. When `close()` closes the
  last reader open on an instance whose memory has passed 256 MiB, and
  no call is running (always true for a `close()` that is not nested,
  which the rule above rejects), the glue replaces the instance there
  and then. Opens are counted in `wasm.open` and closes in `wasm.close`, with
`try`/`finally`, so a reader whose constructor fails after the open
(metadata or JSON) closes its handle and is not counted. A reader dropped without `close()` is caught by a `FinalizationRegistry`
that closes its handle, and does nothing if the handle belongs to an
older instance generation; until it runs, it keeps the instance, and the docs
say to `close()` or `using`. The 256 MiB threshold has a test-only
override, so CI's swap test reads an 8 MiB strL in the test module
with the threshold lowered to 4 MiB, then asserts the
generation changed and RSS dropped. Readers keep their instance's generation and
  report `DTA_CLOSED` if it changed (as today after a trap).
- Target: after reading the 500 MB strL and closing, RSS (after
  `--expose-gc` GC) returns to within 50 MB of where it was.

**M5. Previews (Sight's D2).** `readColumns` takes `maxStringBytes`
(a whole number, 0 allowed), counted in **stored bytes**: each
string reads at most `maxStringBytes` bytes as stored in the file and
decodes them. Single-byte encodings need no cut. For UTF-8, only when the cap truncates the value (`storedBytes >
maxStringBytes`), and the bytes read end inside a sequence that is valid so far (a lead byte followed by
fewer continuation bytes than it needs), the cut moves back to that lead
byte; anything else, including invalid bytes, is kept and decoded as a
full read decodes it (U+FFFD per maximal invalid subpart, as
`TextDecoder` does). The decoded cut is then always a prefix of the
full value's decoding; the tests check this on malformed input too. The column gets
`storedBytes: Uint32Array`, each value's full stored length: for a text
strL, its record's length less its terminating NUL; for a binary strL,
its record's length; for strN, the bytes before the first NUL.
A text strL's record usually ends in a NUL, but the reader strips one
only if present, so a capped read also reads the record's last byte to
know its stored length. A value was cut exactly when `storedBytes[i] >
maxStringBytes`, in every release and encoding. `maxStringBytes: 0`
returns empty values and lengths only; for a text strL it reads one
byte of payload, the last. A capped strL read reads at most `maxStringBytes` bytes from the
payload's start and one from its end (plus the header, in the same
read, when the index was adopted), and never reserves its full length. Binary strLs get their first `maxStringBytes` bytes.
`maxStringBytes` with `strings: "dictionary"` is `DTA_INVALID` (cut
values would merge). Implemented in the core as a read option; exposed
in TypeScript only.

**M6. Sharing the strL index (Sight's D3).** In 1.0 because Sight's
Phase 1b reads in several worker threads, each opening the file, and
without it each rescans the strL section. The layout is versioned, so
1.1 can change it. `reader.strlIndex()`
returns the M1 index as one `Uint8Array` in a documented, versioned
layout: magic, version, then the file's shape (length, release, byte
order, nobs, nvar, the strL section's offset and length), then the
arrays. `openDta(bytes, { strlIndex })`, `openDtaFile(path | fd,
{ strlIndex })` and `new DtaReader(readAt, length, { strlIndex })`
adopt it: it may be backed by a `SharedArrayBuffer`, and is copied into the
instance before it is validated, so another thread writing to it
cannot change it between check and use. The trust model, stated in the docs: the caller vouches
that the index came from this file. The package checks what it can
cheaply:
- on adoption, the header matches this file's shape, the version is
  known, the arrays have the stated lengths, keys are strictly increasing and
fit the packed form, and every offset and length lies within the strL section;
  any failure is `DTA_CORRUPT` and nothing is adopted;
- on every lookup through an adopted index (a locally built one is
  trusted and skips this), the strL's record header (16 bytes in 117,
  20 from 118: `GSO`, `v`, `o`, type, length) must match the index
  entry; a mismatch is `DTA_CORRUPT`. Today only the payload is read
  (reader.rs:482); with an adopted index the header and payload are
  read in one `ReadAt` into the column's spare room, and the payload is
  moved down over the header, so no extra read per strL. Target: a read
  of every strL in a 2M-strL file through an adopted index within 5% of
  the same read through a built one.

That catches an index whose entries point at the wrong places, which is
what using an index from another file or an older copy usually looks
like. It does not prove identity: a file rewritten in place with the
same layout and different payload bytes passes, and its new values are
returned. The docs say an adopted index requires an unchanged file, as
a reader opened on a file requires already. No checksum (it would read
the section the index exists to skip) and no file-system identity
(`bytes` and `ReadAt` sources have none).

### F. Display formats (manuscript-markdown's port)

`formatValue` must never throw. The port found three bugs in
js/src/format.ts:
- dates outside JavaScript's `Date` range (|`%td`| above about 1e8,
  `%tc` above 8.64e15) throw at `MONTHS[m]`; they now format as the plain
  number, as `%9.0g` would;
- fractional `%td` values are rounded (format.ts:108); they now floor,
  as haven does and as `%tc` already does;
- negative `%ty` years render wrong (−1 as `-199`); `CC`/`YY` now use the
  sign and absolute value.

Numeric formats can throw too: `toFixed` and `toExponential` reject
more than 100 digits, so `%9.101f` throws. A format whose width or
digits the code cannot honour falls back to the plain number, as for
dates. A property test formats random doubles (including ±huge,
fractions, missing codes) under every date unit, and under random
`%f`, `%e`, `%g` and `%fc`/`%gc` formats including absurd widths and
digit counts, and checks nothing throws.

### C. Other findings from the table-viewer and manuscript-markdown ports

Bugs, fixed in 1.0:
- **BOMs.** Both `TextDecoder`s (js/src/index.ts:133, js/src/wasm.ts:96)
  drop a leading U+FEFF, so a value, label name or label text starting
  with it loses it, even when 1.0's own writer wrote it. Both get
  `ignoreBOM: true` (S3); a round-trip test covers strN, strL, label
  names and label text.
- **Writes past 2 GiB.** `writeDta` fails between 1.77 and 2.1 GB
  ("unreachable" for a string column, "could not be written" for
  numbers): pointers past 2^31 arrive in JavaScript negative. M2's
  `>>> 0` covers `host_write` and the writer's copies too; a test writes
  a 2.5 GB file (bench, not CI) and reads it back.
- **Unknown encoding names.** `open()` looks up `ENCODINGS[encoding]`
  and an unknown name becomes `undefined`, read as Windows-1252. It
  throws `DTA_INVALID`.
- **Duplicate strL ids.** Two records with the same `(v, o)` silently
  show one's text for the other. The M1 build finds equal keys next to
  each other after sorting, and the file is `DTA_CORRUPT`. Round 2 said
  the later one wins. No writer this library tests against
  produces them.
- **Declared counts before allocation.** Counts read from the file
  (label entries, table sizes, nvar) are checked against the bytes
  left in their section before anything is reserved (part of M2).
- **`Missing.missing`** is typed as the union of the 27 codes, not
  `string`.

Checked, not changed (documented in docs/migration.md as differences
from 0.x):
- **Release 108 label-table names.** table-viewer expected 33 bytes.
  The open-source readers disagree: pandas (`io/stata.py`, the
  `_format_version == 108` branch of its value-label reader) and
  readstata13 (`src/read_pre13_dta.cpp`, `lbllen = 9` for 107–108) read
  9, as we do; ReadStat (`src/stata/readstat_dta.c`, 33 for 105–117)
  reads 33. We keep 9 and, when a table does not add up read that way,
  retry it with 33, so files written either way read. Tested with a
  108 file written each way; docs/other-readers.md records the
  difference.
- **A repeated label-set name keeps the last table** (0.x kept the
  first). pandas also keeps the last (it fills a dict).
- **Lenient reads** of type-130 strLs that are empty or lack a final
  NUL, label text without a NUL, a label whose text offset equals the text
block's length (it reads as ""), and a map whose end-of-file offset is
  past the end. Each reads what is there; none can return another
  value's data. 0.x rejected them.

Speed: table-viewer measured `formatValue` 3–4× slower than 0.7 (`%td`
542 against 140 ms per million values, `%g` 314 against 94). F also
profiles it: the target is within 1.5× of 0.7 on those two, measured
the same way.

Not in 1.0: listing label-set names without parsing them, limits and
cancellation for `valueLabels()`, and cancelling inside a read
(table-viewer reads in 64K-cell steps and checks between them). These
are 1.1 candidates.

### P. Packaging

- `typesVersions` for the `/node` and `/format` subpaths, so
  `"module": "commonjs"` projects (manuscript-markdown) resolve their
  types. A test compiles an import of each subpath under
  `moduleResolution: node10` and `bundler`.
- **D4.** `@jbearak/dta-parser/format` exports `formatValue`, `MISSING`,
  `missingValue`, `isMissing` and the types they take (`Cell`,
  `Missing`, `ValueLabels`), without the wasm module. A test checks the
  subpath's bundle contains no wasm bytes and no `node:` or bare Node
  built-in imports.
- The README links docs/migration.md by its GitHub URL (the file is
  not in the tarball).
- **docs/migration.md** maps each 0.x call table-viewer and
  manuscript-markdown use to 1.0 (from the ports), and lists what users
  will see change: reads past the last row throw `DTA_OUT_OF_RANGE`;
  files before release 118 decode as Windows-1252 by default (0.x used
  UTF-8; pass `{ encoding }`); `%g` keeps to the column width; masked
  dates, `%tC`, `%th`, `%ty` and old `%d` now format; binary strLs are
  `Uint8Array`.

### T. Test hooks in the wasm module

Environment variables do not reach wasm32-unknown-unknown
(`DTA_TEST_SMALL_CHUNKS` is read through `std::env`, threads.rs:36), and
`BUDGET` is a constant (wasm.rs:232). A cargo feature `test-hooks`
builds a separate test module (never shipped; a test checks the
published one lacks the export) with `dta_test_set(budget, chunk_bytes, replace_threshold,
string_limit)` and a 64 MiB memory maximum. The string property
test, the memory-cap tests and the M4 swap test use it.

## Not in this plan

- **memory64**: needs nightly Rust; M1–M5 remove the cases measured to
  hit the ceiling. Revisit when `wasm64-unknown-unknown` is stable.
- **Streaming numeric writes from TypeScript** (round 1's M7): deferred
  to 1.1. It needs a complete design (`number[]` columns, validation
  before the header, error propagation, partial-file removal), and no
  consumer writes `.dta` from TypeScript.
- **D5, D6, D7**: additions for 1.1, as Sight agreed.
- **Threads in the npm package**: wasm threads need nightly Rust; Sight
  reads in its own workers.
- **Moving R's dictionary into the core**: R keeps its own (S1).
- **The wasm duplicated in two bundles** of a consumer that bundles the
  package twice (manuscript-markdown's extension and server, +309 KB
  each): the consumer's choice.

## Stages

Each its own commit, measured before the next: N and P; E; F and C; W1;
S1–S3; M1–M2; M3; M4; M5; M6; docs. Then the release gates.

## Tests

- **Strings.** A property test generates string columns (ASCII,
  non-ASCII UTF-8 including 4-byte characters, Windows-1252 before
  118, invalid UTF-8, empty strings, values starting with U+FEFF at any
  position in the buffer, strLs text and binary interleaved, few and
  many distinct values, columns that give up the dictionary mid-read,
  reads split across many wasm calls with `dta_test_set`'s `chunk_bytes` and a
  small call budget) and compares `readColumns` with and without
  `strings: "dictionary"` against a reference decode of each cell.
- **Retention.** Keeping one cell of a 64 MiB call alive and dropping
  the rest: heap after GC measured and recorded (S3's last point).
- **D2.** Cuts at every byte position of multi-byte characters and of
  malformed UTF-8 (lone continuation bytes, truncated and overlong
  sequences), and in Windows-1252: the cut decodes to a prefix of the
  full value's decoding; text strLs with and without a final NUL; `storedBytes` equals the file's length
  for strN and strL; `storedBytes > maxStringBytes` exactly when the
  value differs from the full read; `maxStringBytes: 0` reads, with a built index, one payload byte of
each text strL (the last) and none of a binary one; malformed values whose full length is at
or below the cap decode exactly as an uncapped read; a capped read of a 64 MiB strL reads under 1 MB of it
  (counted through `ReadAt`).
- **Index.** Lookups agree with today's `HashMap` on every fixture and a
  file of 2M strLs, in both byte orders and releases 117, 118 and 119;
  out-of-order sections; duplicates (`DTA_CORRUPT`); keys out of bounds
  (`DTA_CORRUPT`); build peak memory measured on 10M strLs.
- **Index sharing.** Adoption gives the same values without reading the
  strL section (counted through `ReadAt`); a mismatched shape, a
  truncated or reordered block, an unknown version, an out-of-bounds
  offset, and an index from another file of the same shape whose
  entries point elsewhere each give `DTA_CORRUPT`; all three open
  paths. (A same-layout rewrite is not detectable and is not tested as
  if it were.)
- **No traps** (M2): the capped-memory tests above.
- **Memory** (M3, M4): the 500 MB strL read, close and RSS check runs in
  the bench script (it needs the file); a 64 MB version runs in CI.
- **Errors** (E): each code from at least one real trigger; a throwing
  `ReadAt` gives `DTA_IO` with the thrown error as `cause`.
- **Re-entry** (M4): the nested-call tests.
- **Formats** (F): the property test, plus the three port cases.
- **Dispose** (N): `using` closes a path-opened reader; a borrowed fd is
  still readable after dispose.
- Every existing suite passes, on Node 24 and 26.

## Release gates

Nothing is published until each holds, and the user approves the
publish:

1. The targets in S1–S3, W1 (or W1 dropped), M1, M3 and M4 met on
   Node 24, median of 5 runs, recorded in bench/RESULTS.md with
   before-and-after numbers.
2. Sight's needs, checked one by one against its spec:

   | item | status in 1.0 |
   |---|---|
   | D1 dictionary columns | S1–S3 |
   | D2 previews and `storedBytes` | M5 |
   | D3 strL index sharing | M6 |
   | D4 `/format` subpath | P |
   | D5 three format differences | 1.1 |
   | D6 `readRowsAt` | 1.1 |
   | D7 strL in pieces | 1.1 |
   | error codes | E |
   | Node 24, `using` | N |

   and the Sight thread confirms it is satisfied with the final plan.
3. Consumers, each on the packed tarball (`npm pack`), in a scratch
   copy, never pushed:
   - manuscript-markdown: typecheck, lint, all 144 test files, compile,
     `vsce package`, and the port's old-versus-new `parseDta`
     comparison, with only the documented differences;
   - table-viewer, with Arrow removed (the user's decision): its test
     suite and VS Code integration tests;
   - Sight: its browser tests and smoke test on VS Code 1.123.
4. docs/typescript.md documents every option, return shape and error
   code above, with an example each.
