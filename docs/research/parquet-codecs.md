# Parquet codecs: speed and size of the candidate Rust crates

Measured 2026-11-04 on an Apple M-series Mac (arm64), release build with
LTO, one thread. Plan 0018 chose its codecs from these numbers.

## Input

The column values of the DHS Turkey 2013 women's recode (`wm.dta`, 52 MB
on disk), as a Parquet writer would lay them out in PLAIN encoding:
integers as 4 bytes, doubles as 8 bytes, strings as a 4-byte length and
the bytes, column after column (184 MB). It was compressed in 1 MiB
pieces, the page size plan 0018 writes. Real pages are dictionary-encoded
first and so are less redundant than this: treat the ratios as an upper
bound on what compression gains, and the speeds as comparable between
codecs.

| codec (crate) | size / uncompressed | write MB/s | read MB/s |
|---|---|---|---|
| snappy (`snap` 1) | 0.086 | 4,296 | 4,422 |
| lz4_raw (`lz4_flex` 0.11) | 0.050 | 5,436 | 2,639 |
| gzip level 1 (`miniz_oxide` 0.8) | 0.034 | 2,956 | 2,586 |
| gzip level 3 (`miniz_oxide`) | 0.022 | 643 | 2,409 |
| zstd level 1 (`zstd` 0.13, C libzstd) | 0.023 | 3,107 | 3,679 |
| zstd level 3 (`zstd`, C libzstd) | 0.022 | 2,562 | 3,743 |
| zstd, fastest level (`ruzstd` 0.8, pure Rust) | 0.060 | 510 | 2,669 |
| zstd level 3 written by libzstd, read by `ruzstd` | 0.022 | — | 1,006 |

On a synthetic buffer of 4 million random small doubles (32 MB, less
compressible), snappy wrote at 1.2 GB/s and read at 2.3 GB/s with ratio
0.24; `ruzstd`'s fastest level wrote at 280 MB/s with ratio 0.29, worse
than snappy.

## What follows

- **zstd through C libzstd is the best trade.** At level 3 its output is a
  quarter the size of snappy's, written at 60% of snappy's speed and read
  at 85% of it. On a disk that writes 1 to 3 GB/s, the smaller file costs
  less wall time than the extra compression, so zstd is the default on
  native builds (R, Python, Julia).
- **`ruzstd` reads zstd at a quarter of libzstd's speed** and writes only
  its fastest level. It is used only in the wasm build, where C libzstd
  would need a C toolchain for wasm32.
- **All five pure-Rust crates (`snap`, `lz4_flex`, `miniz_oxide`,
  `ruzstd`, `brotli-decompressor`) build for wasm32-unknown-unknown.**
  `zstd` (C) is native only.
- `ruzstd` 0.8.3 panics with "not implemented" for its `Default` level,
  so only `Fastest` can be used.

## The `parquet` crate from arrow-rs, for comparison

Measured the same day: a program that opens a file and prints its row
count, built in release mode with LTO, against `parquet` 57.3.2.

| build | crates compiled | clean build (wall) | vendored source |
|---|---|---|---|
| `parquet` without its Arrow layer, with snappy, zstd, gzip, lz4 and brotli | 44 | 13 s | 54 MB |
| the same with the `arrow` feature | 64 | 25 s | — |
| our five codec crates plus `zstd` (C) | 21 | — | 16 MB |
| `crates/dta` today | 1 | 1.4 s | — |

The first build's native binary is 550 KB. The vendored size counts every
platform's sources (`libc` alone is 5.7 MB).
