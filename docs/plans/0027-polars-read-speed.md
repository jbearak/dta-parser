# Plan: Parquet reads into polars as fast as polars' own

Status: done. Revision 3, after two rounds of review by Claude Opus and
GPT Sol (see "Review"); the results are under "What was done".

## Problem

`bench/results/parquet-polars-r.md` (plan 0025, stage 4) shows R's
`read_parquet_pl()` at about twice the wall time of polars' own
`pl$read_parquet()` on a DHS file of 4,962 columns. The user asked
(2026-11-09) that we study polars' reader, which is MIT licensed, and
tune ours.

Measured 2026-11-09 on an Apple M4 Max (12 performance cores, 4
efficiency), load average 2 to 3, best of 15 to 20 runs in one process,
files in the page cache. Files are the benchmark's own conversions
(`bench/parquet/convert.R`), written by our writer unless named.
"Core" is `crates/arrow`'s `parquet_read` timed from Rust by the new
`crates/arrow/examples/read_bench.rs`, which is the code both R's and
Python's polars reads call.

| file | case | polars (Python 2.1.0) | core | R `read_parquet_pl()` | R `pl$read_parquet()` |
|---|---|---|---|---|---|
| DHS Tajikistan 2017 wm, 10,718 × 5,160 | whole | 12.7 ms, 28 ms CPU | 11.1 ms, 31 ms CPU | 26.9 ms | 13.7 ms |
| the same | five columns | 3.6 ms | 3.5 ms | 12.7 ms | 4.8 ms |
| NSFG 2002 FemResp, 7,643 × 3,087 | whole | 15.2 ms, 20 ms CPU | 9.5 ms, 21 ms CPU | 20.0 ms | 15.1 ms |
| the same | five columns | 2.6 ms | 2.6 ms | 11.6 ms | 3.7 ms |
| groups, 15 million × 2 (text of few values, int) | whole | 4.1 ms, 42 ms CPU | 7.7 ms, 50 ms CPU | 8.2 ms | 4.3 ms |
| long, 10 million × 12 | whole | 27.8 ms, 320 ms CPU | 35.1 ms, 337 ms CPU | not run | not run |

So there are two separate gaps:

1. **R's glue, not the decoder, is most of R's gap on wide files.** The
   core already matches polars there. Timing each step of
   `read_parquet_pl()` on the Tajikistan file:

   | step | whole file | five columns |
   |---|---|---|
   | `.Call` (the core's 11.1 ms or 3.5 ms, plus building R's metadata list) | 13.7 ms | 3.8 ms |
   | `polars::as_polars_df()` on the stream | 5.5 ms | 0.4 ms |
   | `frame_of()` | 0.6 ms | 0 |
   | `meta_of()`, an R `lapply` over the columns | 7.1 ms | 0 |
   | reading the footer into R to see whether a column is named like the variable in `col_select = cols` | 0 | 8.5 ms |

2. **The decoder is slower than polars on long files**: 1.9 times on
   `groups`, 1.25 times on `long`, and about 1.1 times polars' CPU time
   everywhere.

A sampling profile of the core on one thread (samply, 4 kHz) gives the
decoder's shares. Wide file (28 ms on one thread):

| where | share |
|---|---|
| `columnar::merge`: a chunk's validity bits into the column's, one byte at a time through an atomic | 18 to 31% (inlined; 31% when kept out of line) |
| `rle::levels_bits`: definition levels to bits | 11 to 13% |
| `Num::page` with `scatter` (values spread over rows with nulls) | 8 to 10% |
| malloc and free, `bzero`, `memset` (per-chunk vectors) | 13% |
| `memmove` | 6% |
| `gather` and `Hybrid::next` (dictionary indices) | 9% |
| opening: profile JSON 6%, footer 4%, `ARROW:schema` 4% | 14% |

`groups` (48 ms on one thread): `scatter` 17%, `levels_bits` 17%,
`Hybrid::next` 15%, `gather` of views 12%, `memmove` 10%, `merge` 7%,
`memset` 5%, growing a `Vec<u128>` a view at a time 3%. `long` (298 ms
on one thread): snappy 28%, `memmove` 12%, `str::from_utf8` a value at a
time 12%, `read` 10%, `merge` 6%, `Views::view` 5%.

## What polars does

From reading `crates/polars-parquet` (the commit is under "Review"),
with no code copied. Its `LICENSE` says the crate began as arrow2 and
parquet2 (Apache-2.0), with parts ported from arrow-rs (Apache-2.0),
and later changes under polars' MIT license.

1. **Dictionary indices**: unpacks 32 at a time through a function per
   bit width (every shift a constant), checks the 32 against the
   dictionary's size with one branch, and gathers straight into the
   output. An RLE run is one lookup and a fill.
2. **Validity**: bit-packed level runs are already the bitmap and are
   copied a word at a time; RLE runs set a range. A page of one all-ones
   run makes no bitmap.
3. **Nulls**: values are written into place without a branch per row:
   every row writes the next value and the source advances by the
   validity bit.
4. **PLAIN numbers** of the output's width: one `memcpy`.
5. **Text**: a view per dictionary entry, then a 16-byte gather per
   row. UTF-8 is checked once over a dictionary's or a PLAIN page's
   bytes, not a value at a time.
6. **Buffers**: outputs are sized once and never zero-filled; snappy
   and zstd write into spare capacity; zstd keeps a context per thread.
7. **Threads**: a task is a batch of column chunks holding about a
   million values, so a wide file makes tens of tasks, not thousands.

Ours already does 2 (in part), 4, the per-dictionary views of 5, and
batches tasks by bytes. It does not do 1, 3, the bulk UTF-8 check of 5,
or avoid the per-chunk allocations of 6.

## Changes

Revision 3, after review by Claude Opus and GPT Sol (below). Each
change is its own commit. The order is: tests, then R, then the core
by measured share. A core change is kept only if alternating runs of
main's and the branch's `read_bench` show a lower median one-thread CPU
time on at least one of the four files and no higher median on any;
`read_bench` prints the median wall and CPU times and the steps.

### 0. Tests first (`crates/parquet/tests`)

The damaged-file suites read only through the plain outputs, so they
never run the Arrow outputs' kernels (`levels_bits`, `Hybrid`, `gather`,
`scatter`, `merge`, `Views`).

- `tests/hostile.rs` and `tests/fuzz.rs` gain an Arrow arm: every
  column into an Arrow output, on 1 and 4 threads, under the same
  allocation bound. A damaged file gives an error, never a panic or an
  allocation past the bound.
- That arm finds an existing fault, fixed here: `Views::dictionary` and
  `Keys::dictionary` reserve `count` entries from the page header (up to
  2^31) before finding the bytes short. The reservation is capped by
  what the page's bytes can hold (a BYTE_ARRAY value is at least 4
  bytes).
- `tests/arrow.rs` gains a file of tiny row groups that do not end on a
  byte of the validity bitmap, with nulls, `.a` to `.z` and text, read
  whole and in windows on 4 threads, against the plain outputs.
- Each kernel changed below keeps its old loop as a `#[cfg(test)]`
  reference, and a unit test compares the two, results and errors, over
  random inputs at every bit offset, width and tail length.

Error order is kept by construction, not by a differential harness:
the changes below never check something earlier or later than now.

### R (`r/datakit`, `r/dtaparser`)

1. **`col_select = cols`.** `read_parquet_pl()` reads the whole footer
   into R (8.5 ms on the wide file) to see whether a column is named
   like the variable. The tibble path passes the variable's name down
   instead (`prefer`, `r/dtaparser/src/init.c:347`), and the native
   reader picks that column if the file has it. The Arrow read does the
   same: `init.c` reads the attribute as it does for the tibble path,
   `dta_arrow::read::parquet_read` and `select` take `prefer:
   Option<&str>` (resolved after the file is opened; the profile
   entries projected at opening are those of the names and of
   `prefer`), and Python passes `None`. A dtaparser built before this
   would ignore the attribute and read the wrong columns, so the
   metadata list says the attribute was honoured and datakit stops with
   "reinstall dtaparser" when it does not (as `key_value_table()` does);
   the bridge's signatures and ABI number do not change. (With an old
   dtaparser a read whose names are not all in the file fails on the
   name first; that is an error either way.) As in the tibble path and
   as `read_parquet_pl()` does now, a nested column of the variable's
   name is picked and is then an error, whatever `nested` says. Tests:
   a file with a column named like the variable, without one, an empty
   vector, a non-ASCII name, and a nested column of that name under
   both values of `nested`.
2. **`meta_of()` and `frame_of()`.** `columns` is built over the four
   fields at once instead of a closure and four `na_null()` calls per
   column; `frame_of()` loops over `which(!is.na(cols$flag))`. A test
   holds the result `identical()` to the present function's on no
   columns, `NA` in each field, and `ordered` `TRUE`, `FALSE` and `NA`.
3. **The stream.** `polars::as_polars_df(stream)` first infers the
   dtype of the whole struct in R (3.4 ms of its 5.4 ms on the wide
   file). `polars::as_polars_series(stream)$struct$unnest()` is what it
   then runs, and gives an equal frame in 2.1 ms; polars' own exported
   stream costs the same 5.4 ms through `as_polars_df()`, so the rest is
   not ours. The 2.7 ms of the metadata list is profiled, and
   `export_stream`'s two copies of the table removed if they show.

### Core (`crates/parquet`, `crates/arrow`; R's copies refreshed by `configure` in the same commit)

4. **`merge`**, when the chunk starts on a byte (every chunk of the
   four files): the bytes wholly inside the chunk's range, which are
   this chunk's alone, are copied with one `copy_nonoverlapping` through
   a pointer taken from the whole atomic slice, its length checked, not
   clamped; the last, partial byte still goes through `fetch_or`. A chunk that starts inside a byte
   keeps today's loop. Other chunks never touch the copied bytes, and
   the threads are joined before anything reads them.
5. **`levels_bits`.** A bit-packed run that lands on a byte boundary is
   OR-ed into the bits a byte at a time over whole slices (which the
   compiler vectorises) and its ones counted eight bytes at a time. It
   is OR, not a copy, as now: a damaged offset index can make two pages
   cover the same rows. The last group's padding is masked. The unit
   test starts from random bits outside the range and checks they
   survive.
6. **Unpacking** (`rle::unpack8`): read the packed bytes in place,
   instead of copying them to a 40-byte buffer for every eight values,
   with the width a constant (a `match` to monomorphised functions).
   Value `i` of a group at byte `s` loads eight bytes from
   `s + i * w / 8`, so the in-place read needs `s + w + 8 <= buf.len()`,
   checked against the slice the decoder holds (so `unpack8` takes the
   buffer and the group's start, not the group's bytes); a group nearer
   the end takes today's padded copy. `gather`'s index buffer and
   `scatter`'s scratch stop being zeroed for every batch: they keep
   their length, and each batch uses exactly `idx[..n]` and
   `tmp[..present]`. The index buffer, the bound check per batch and
   the handling of a short last group stay as they are.
7. **Zeroing.** Each page's decompressed bytes are zero-filled before
   the codec overwrites them (`out.clear()` then `resize`, `codec.rs`).
   For the codecs that are given the declared size and either fill all
   of it or fail (snappy, lz4, zstd), `resize` without the `clear`
   leaves the buffer's length exactly the declared size, as now, and
   zeroes only what it grows by. The buffer's length stays its logical
   length, so its readers (`decode.rs:757`, the page cache, the check
   at `codec.rs:168`) are untouched; a buffer kept longer than its
   contents was rejected in review, since those readers take the whole
   vector. gzip and brotli, which grow as they go, and the compressed
   bytes are left as they are. A test decompresses a small page after a
   larger one into the same buffer, with each codec, and a short and an
   oversized output give today's errors. `dict_t` reserves its count
   (capped as in 0).
8. **Text.** A value that is all ASCII skips `str::from_utf8` (checked
   per value, so the order of errors is unchanged), and a page's views
   are reserved before they are pushed, capped by the page's bytes.
9. **Opening**, which is serial and so on the wall-time path (3.6 ms of
   the wide file's 11.1 ms): profiled first, then only what shows
   (`arrow::read_schema`, the profile's parse, the footer).

Deferred, each for the reason given in review: a branch-free `scatter`
(null slots would hold a neighbour's value, and the gain is unmeasured);
a fused unpack-and-gather (changes which error a damaged file gives);
bulk UTF-8 validation (the same, and PLAIN length prefixes sit between
the values); a pool of typed scratch vectors; writing validity straight
into the column; `merge` a word at a time for chunks that start inside a
byte (none of the four files has one).

The thread rule is not changed blind. On `groups` we use 8 threads to
polars' 16, so its wall time cannot match polars' by kernels alone: its
target is CPU time. The rule is measured again at the end
(`bench/parquet/threads_polars.py`'s cases) and changed only if both of
its targets still hold.

## Correctness

No behaviour changes: every file reads to the same frame and metadata,
with the same errors.

- `cargo test --workspace` and `cargo clippy --workspace --all-targets
  -- -D warnings`, with the tests of section 0.
- R: `R CMD INSTALL` of the three packages, then dtaparser's and
  datakit's `tests/testthat` with `DATAKIT_REQUIRE_POLARS=true`.
  Python: `pytest` of `python/tests` and `python/datakit`. Then
  `compat/parquet/cross_language_polars.sh` (R and Python read the same
  frames).
- Unsafe code added is the copy in 4 and the in-place reads in 6, each
  with its bound checked just before and a SAFETY comment.

## Measurement

- Main against the branch in identical environments (one scratch R
  library and one venv per build), runs alternated: `read_bench` on the
  four files (whole and five columns; one thread and the default), the
  R table above, and Python's `dk.read_parquet` against
  `pl.read_parquet`.
- `bench/parquet/polars_r.R` is run again and
  `bench/results/parquet-polars-r.md` replaced.
- A no-regression run of the tibble path, Julia and Node on the
  Tajikistan and NSFG 2002 files.

The aim is R's `read_parquet_pl()` within 1.2 times `pl$read_parquet()`
on whole wide files and faster on five columns, and the core's CPU time
at or below polars' on all four files. What is not reached is reported
with its numbers.

## Review

Claude Opus and GPT Sol (gpt-6.1-sol) each reviewed revisions 1 and 2.
On revision 2 both marked every earlier finding resolved and both found
change 7 unsafe as then written (buffers kept at a high-water length,
which their readers would take whole); it is now the narrower form
above. Opus's bound for change 6, OR in change 5 and notes on change 1
are in the text. Revision 1's findings:

| finding | outcome |
|---|---|
| The fuzz and hostile suites never reach the Arrow kernels (both) | section 0 |
| `with_capacity(count)` from a page header in `Views` and `Keys` (Opus) | fixed in section 0 |
| `merge`: prove which bytes a chunk owns; no word store over an end byte; drop the direct write and the word shift (both) | change 4 narrowed |
| Branch-free `scatter`: must decode exactly `present` values; null slots change (both) | deferred |
| Fused gather changes error order and reads padding (both) | change 6 narrowed to unpacking |
| Bulk UTF-8: length prefixes, skipped values, error order (both) | change 8 narrowed to an ASCII test per value |
| `prefer` cannot be resolved in `selectors()`; read it in `init.c`; version skew (both) | change 1 rewritten |
| `as_polars_df()` and the export's copies (both) | change 3, with the measured floor |
| Rank by wall time; opening is serial; `groups` is a thread-count gap (Opus) | change 9 kept, thread note added |
| Zero-filling of compressed and page buffers (Opus) | change 7 |
| Typed scratch pool is more than moving fields; `Views`' buffers are handed to the arrays (both) | deferred |
| Alternate runs, medians, one-thread CPU (both) | Changes and Measurement |
| The commit's date and full hash (both) | below |

polars was read at commit
09251856d4ca82595e27476fd52a2e00d6ba6a00 (dated 2026-11-10 in UTC+11),
on 2026-11-09.

## What was done

Every change of revision 3 was made and kept, each faster on at least
one file and slower on none (the numbers by change are in
`bench/RESULTS.md`, "Parquet into polars, after reading polars'
reader"), with these differences from the text above:

- Section 0's test of tiny row groups that end inside a byte was
  already there (`tests/arrow.rs`, `written_tables_read_the_same_into_arrow`:
  row groups of 3, 7 and 1,001 rows, on 4 threads, in windows, against
  the plain outputs), so none was added.
- The Arrow arm of `tests/fuzz.rs` failed at once on the reservation of
  section 0: ten of 5,600 damaged files asked for 16 to 34 GB.
- Changes 5 and 6 were measured together.
- Change 2: `meta$columns` is built in C in datakit (`src/meta.c`); the
  form built in R a field at a time still took 2.6 ms.
- Change 3: the metadata list's column fields are passed to R without a
  copy each (0.3 ms). `export_stream`'s copies did not show and stay.
- Change 9: only the base64 of the `ARROW:schema` entry, which was 12%
  of opening the wide file. The footer's and the profile's allocations
  are the rest of it and were left.
- The thread rule is unchanged: its cases were not rerun.
- Julia's and Node's benchmarks were not rerun.

Reached: R's `read_parquet_pl()` is 1.02 to 1.12 times
`pl$read_parquet()` on whole wide files (it was 1.9 to 2.2) and faster
on five columns, and the core's CPU time is below polars' on all four
files. Not reached: wall time on `groups`, which is a thread count.

## Documents

- `docs/acknowledgements.md`: polars' entry says what was learned from
  `polars-parquet`'s reader (the list above), that no code was copied,
  and its licences (MIT, with the Apache-2.0 parts from arrow2, parquet2
  and arrow-rs).
- `bench/RESULTS.md`: a short section with the before and after table.
- This plan's status line, when done.

No version numbers change in the PR.
