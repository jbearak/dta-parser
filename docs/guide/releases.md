# Releases

Every `.dta` file starts with its *release*, a number that fixes the
layout of the file. Stata 14 writes release 118, for example. The
release is not the Stata version, and several Stata versions share one
release.

dta-parser reads releases 104, 105, 108, 110, 111, 113, 114, 115, 117,
118 and 119, written on big-endian or little-endian machines. It writes
release 118 only: every Stata from 14 on reads it, and so do haven,
readstata13, pandas, pyreadstat and ReadStat. Files with releases
outside that list (102, 103, or newer than 119) fail to open with
"unsupported .dta release".

To see a file's release without reading its data:

| language | call |
|---|---|
| R | not exposed; `read_dta` reads every release the same way |
| Python | `dta_parser.read_meta(path)["release"]` |
| Julia | `read_meta(path)["release"]` |
| TypeScript | `openDtaFile(path).info.release` |

## What each release can hold

| release | names | strings | missing values | text | other limits |
|---|---|---|---|---|---|
| 104 | up to 8 characters | fixed width | `.` only | one byte per character | no timestamp, no characteristics; 32-byte labels |
| 105 | up to 8 | fixed width | `.` only | one byte per character | 32-byte labels |
| 108 | up to 8 | fixed width | `.` only | one byte per character | 81-byte labels |
| 110, 111 | up to 32 | fixed width; up to 244 bytes from 111 | `.` only | one byte per character | |
| 113 | up to 32 | up to 244 bytes | `.` and `.a` to `.z` | one byte per character | |
| 114, 115 | up to 32 | up to 244 bytes | `.`, `.a` to `.z` | one byte per character | longer display formats (up to 48 bytes) |
| 117 | up to 32 | up to 2045 bytes, and strLs | `.`, `.a` to `.z` | one byte per character | at most 4,294,967,295 rows; the file has named sections |
| 118 | up to 32 characters (128 bytes) | up to 2045 bytes, and strLs | `.`, `.a` to `.z` | UTF-8 | 80-character labels (320 bytes); up to 32,767 variables |
| 119 | as 118 | as 118 | as 118 | UTF-8 | more than 32,767 variables |

What this means in practice:

- **Before 113, a file has one missing value per type.** dta-parser reads
  it as `.`. There is nothing to lose.
- **Before 118, the file does not say how its text is encoded.** You may
  need to pass an encoding; see [Text encodings](encodings.md).
- **Before 117, strings are at most 244 bytes** and there are no strLs.
- **From 117 on, the file is split into tagged sections** (`<header>`,
  `<data>`, `<strls>` and so on), with a map of where each starts. This
  lets a reader jump to the value labels without reading the rows.
- **119** differs from 118 only in allowing more variables; Stata writes
  it only when a dataset has more than 32,767 of them.

## Why dta-parser writes 118

A writer has to pick one release. 118 is the oldest release that stores
UTF-8 text, so any string in any language round-trips. Stata 14 and
later read it, as do all the open-source readers we compare against.
Stata 13 and earlier cannot open it; if you need to hand a file to
Stata 13, write it with another tool. dta-parser refuses to write more
than 32,767 variables, since 118 cannot hold them.

## Byte order

Releases before 117 store a byte-order flag in the second byte; later
ones store `MSF` (big-endian) or `LSF` (little-endian) in the header.
dta-parser reads both and always writes little-endian. You never need to
handle this yourself.
