# Spike: Parquet into polars through the Arrow C stream (plan 0019)

A measurement spike for plan 0019's Python `datakit.read_parquet`, which
is to return a polars DataFrame. The question: can our Rust core decode
into Arrow-layout buffers that polars imports through the Arrow
PyCapsule stream interface, without pyarrow, as fast as
`pl.read_parquet` and `pyarrow.parquet.read_table` (plan 0018's targets
1 to 3)? The code is throwaway. It lives on branch `spike/polars-arrow`
and is not for merging.

**Short answer.** The interface works. Polars takes numbers and
Utf8View text without a copy, keeps the buffers alive after our object
is gone, and accepts multi-chunk and sliced arrays. Speed is a
different matter. With our default thread rules the path is about 2×
slower than polars on wall time (3.3× on `groups`). Tuned to polars'
thread count, with two smaller fixes, wall time comes within 6% of
polars' (geometric mean) and no single file misses target 2. CPU time
still runs 1.4 to 1.9 times polars', so target 3 fails on most cases.
The import is not the cause. The remaining gap is in the core's decoder:
per-value cost, the per-row missing codes, and the text pipeline.
Against pyarrow's `read_table`, every case passes, even with the
default rules.

## What was built

- `python/src/arrow.rs`: `parquet_read_arrow(source, columns, skip,
  n_max, chunks, threads, view_threads, lazy_labels)` returns an
  `ArrowRead` object with `__arrow_c_stream__`. It hand-writes
  `ArrowSchema`, `ArrowArray` and `ArrowArrayStream` (`#[repr(C)]`),
  with release callbacks that own the Rust buffers through an `Arc` per
  column. It does not use arrow-rs and adds no dependency. The capsule is
  named `arrow_array_stream`, and its destructor releases the stream
  unless the consumer has moved it out.
  - Numbers are read with `dta_parquet::read::Reader` into 16-byte-aligned
    buffers allocated with `calloc`. A `u8` code per row is written
    where the footer does not rule out nulls. After the read, the codes
    are packed into a validity bitmap, eight bytes at a time.
  - Text becomes Utf8View (`vu`). For a dictionary chunk, each
    dictionary value is made into a 16-byte view once, and each row
    copies its view. Values of 12 bytes or fewer are inline; longer
    ones point into the chunk's bytes. Those bytes become one of the
    column's variadic data buffers. They are moved, not copied: the core
    gained `Reader::read_owned`, which passes each `TextChunk` by value.
    PLAIN chunks are handled the same way, with a view per row.
  - Categoricals (`Output::Levels`) become dictionary arrays: int32 keys
    with utf8 values.
  - Dates are `tdD` (int32). Timestamps are `ts{m,u,n}:zone`, times
    `tt{m,u,n}` and booleans `b`. DECIMALs of more than 15 digits are
    not handled.
  - `chunks="one"` exports one batch. `chunks="groups"` exports one
    batch per row group, as arrays sliced from the whole column's
    buffers (`offset` != 0).
  - Spike options:
    - `threads`: the core's read threads.
    - `view_threads`: helper threads that build views while the read
      goes on, and pack bitmaps afterwards.
    - `lazy_labels`: `ReadOptions::lazy_value_labels`.
    - `DTA_SPIKE_WINDOW`: an environment variable that multiplies the
      core's in-order look-ahead window (a spike-only change in
      `crates/parquet/src/read.rs`).
- `python/dta_parser/_polars_spike.py`: `read_parquet_polars(path, ...)`
  returns `pl.DataFrame(read_parquet_arrow(...))`.
- `bench/parquet/spike/`: the benchmark scripts.
  - `case.py`: one timed case in a fresh process.
  - `run.py`: five runs per case, medians, holding the lock directory
    per file.
  - `table.py`: the tables and target checks below.
  - `check.py`: equality with `pl.read_parquet`, and the garbage
    collection test.
  - `cat_check.py`: the categorical and text copy test.
  - `odd_check.py`: slices at offsets that are not multiples of 8.
  - `results.json`: every median.

## Method

- **Machine:** Apple M4 Max, 16 cores, 128 GiB, macOS (Darwin 25.6.0).
- **Software:** Python 3.14.7, polars 2.1.0 (thread pool 16), pyarrow
  26.0.1 (`cpu_count` 16), rustc 1.99.1, release build (LTO, one codegen
  unit).
- **The machine was not quiet.** Another project's processes (unrelated
  to this repository; left alone) kept the one-minute load average
  between 8.6 and 10.1, median 9.4, throughout. Plan 0018 asks for a
  load under 2. The spread of five runs was a median of 5% and a
  maximum of 36% of the median. Treat ratios within about 10% as ties,
  and rerun on a quiet machine before the plan quotes any number.
- **Inputs:** from `/private/tmp/claude-501/pq-bench`, each file as
  written by our writer, pyarrow and polars.

  | file | rows | columns | types |
  |---|---|---|---|
  | DHS Tajikistan 2017 wm (the widest DHS file) | 10,718 | 5,160 | int32 with nulls, 11 text |
  | NSFG 2002 FemResp (mid-size) | 7,643 | 3,087 | mostly int32 |
  | `long` | 10,000,000 | 12 | 7 double, 3 int32, 2 text |
  | `groups` | 15,000,000 | 2 | int32 and text, 58 row groups |

- **Cases:** a whole-file read; five columns (chosen as in
  `bench/parquet/run.py`; `groups` has only two); 1,000 rows from the
  middle; and a whole-file read followed by one pass over every value.
- **How each library was called:**
  - Window read: ours uses `skip`/`n_max`; polars uses
    `pl.scan_parquet(p).slice(skip, 1000).collect()`; pyarrow uses
    `read_table(p).slice(...)`.
  - The pass, for both polars frames: one `select` of each column's
    null count and sum (byte lengths for text, physical values for
    dates and categoricals). For pyarrow's Table, the same through
    `pyarrow.compute`. The missing counts agreed in every pass.
- **Measurement:** five fresh processes per case, medians.
  - Wall and CPU (user plus system) are taken around the task alone.
    Peak RSS is `getrusage` `ru_maxrss`.
  - The baseline RSS after imports was 57 to 58 MiB for every library.
    Ours loads the extension module alone, without `dta_parser`'s
    pandas import.
- **Variants of ours:**
  - **ours (default):** the core's thread rule, views made on the
    calling thread, value labels read eagerly. This is what the pandas
    path does today.
  - **ours tuned:** 16 read threads (polars' pool size), 4 view
    helpers, lazy value labels, and the look-ahead window ×4.

## Results

Each cell is wall ms / CPU ms / peak RSS MiB, median of 5.

| file | writer | task | ours (default) | ours tuned | polars | pyarrow |
|---|---|---|---|---|---|---|
| DHS Tajikistan 2017 wm | ours | full | 51.9 / 85.7 / 403 | 23.7 / 110.7 / 415 | 22.8 / 61.2 / 359 | 219.9 / 413.2 / 443 |
| DHS Tajikistan 2017 wm | ours | five | 4.9 / 4.9 / 68 | 5.0 / 5.2 / 68 | 6.4 / 12.2 / 93 | 174.5 / 175.1 / 133 |
| DHS Tajikistan 2017 wm | ours | window | 21.3 / 28.9 / 116 | 16.2 / 41.5 / 127 | 13.0 / 29.8 / 128 | 221.8 / 413.8 / 444 |
| DHS Tajikistan 2017 wm | ours | pass | 90.1 / 149.8 / 457 | 62.3 / 174.7 / 467 | 59.2 / 120.8 / 395 | 276.8 / 470.7 / 445 |
| DHS Tajikistan 2017 wm | pyarrow | full | 47.6 / 81.1 / 396 | 21.7 / 111.8 / 411 | 21.3 / 54.6 / 358 | 222.6 / 423.1 / 441 |
| DHS Tajikistan 2017 wm | pyarrow | five | 3.6 / 3.6 / 66 | 3.8 / 4.1 / 66 | 6.5 / 11.5 / 91 | 173.0 / 173.6 / 130 |
| DHS Tajikistan 2017 wm | pyarrow | window | 18.8 / 28.2 / 109 | 13.7 / 44.9 / 123 | 13.0 / 29.6 / 127 | 224.4 / 427.7 / 442 |
| DHS Tajikistan 2017 wm | pyarrow | pass | 86.1 / 145.5 / 448 | 60.7 / 173.9 / 464 | 56.8 / 114.5 / 396 | 280.6 / 485.1 / 444 |
| DHS Tajikistan 2017 wm | polars | full | 49.8 / 85.9 / 395 | 21.9 / 116.1 / 411 | 23.0 / 59.8 / 358 | 223.4 / 441.9 / 444 |
| DHS Tajikistan 2017 wm | polars | five | 3.4 / 3.4 / 65 | 3.5 / 3.7 / 66 | 6.3 / 11.6 / 90 | 171.6 / 172.2 / 129 |
| DHS Tajikistan 2017 wm | polars | window | 19.9 / 30.6 / 108 | 13.6 / 43.5 / 124 | 14.2 / 33.5 / 127 | 223.5 / 434.2 / 444 |
| DHS Tajikistan 2017 wm | polars | pass | 87.7 / 147.8 / 448 | 59.3 / 178.0 / 464 | 61.3 / 125.3 / 396 | 279.8 / 498.5 / 443 |
| NSFG 2002 FemResp | ours | full | 30.7 / 45.0 / 203 | 17.9 / 54.4 / 212 | 22.6 / 34.7 / 196 | 198.2 / 311.7 / 287 |
| NSFG 2002 FemResp | ours | five | 3.9 / 3.9 / 67 | 4.0 / 4.2 / 67 | 4.9 / 9.8 / 89 | 169.1 / 169.7 / 128 |
| NSFG 2002 FemResp | ours | window | 20.0 / 20.0 / 97 | 17.6 / 19.8 / 90 | 12.5 / 20.4 / 109 | 197.1 / 308.6 / 288 |
| NSFG 2002 FemResp | ours | pass | 53.9 / 91.8 / 241 | 40.9 / 100.5 / 249 | 45.6 / 77.0 / 220 | 231.2 / 344.1 / 288 |
| NSFG 2002 FemResp | pyarrow | full | 25.9 / 40.2 / 194 | 15.6 / 53.3 / 209 | 23.1 / 35.3 / 193 | 198.3 / 313.7 / 283 |
| NSFG 2002 FemResp | pyarrow | five | 2.7 / 2.7 / 64 | 2.8 / 3.0 / 64 | 4.9 / 10.1 / 85 | 166.9 / 167.5 / 122 |
| NSFG 2002 FemResp | pyarrow | window | 15.9 / 15.9 / 87 | 16.5 / 18.6 / 87 | 13.1 / 21.5 / 106 | 196.7 / 316.4 / 283 |
| NSFG 2002 FemResp | pyarrow | pass | 49.5 / 86.3 / 232 | 38.6 / 98.7 / 247 | 44.5 / 76.9 / 219 | 232.1 / 347.8 / 284 |
| NSFG 2002 FemResp | polars | full | 28.1 / 44.8 / 194 | 15.6 / 58.0 / 209 | 26.1 / 40.0 / 194 | 197.7 / 327.8 / 283 |
| NSFG 2002 FemResp | polars | five | 2.4 / 2.4 / 64 | 2.5 / 2.7 / 64 | 4.7 / 9.8 / 85 | 166.6 / 167.2 / 122 |
| NSFG 2002 FemResp | polars | window | 19.9 / 19.9 / 87 | 20.3 / 22.5 / 88 | 16.2 / 26.3 / 105 | 199.2 / 332.2 / 283 |
| NSFG 2002 FemResp | polars | pass | 51.6 / 91.0 / 232 | 39.5 / 104.0 / 247 | 49.2 / 84.0 / 219 | 229.7 / 359.8 / 284 |
| long | ours | full | 101.7 / 423.7 / 1089 | 52.2 / 530.8 / 1236 | 46.4 / 426.5 / 1273 | 243.5 / 803.1 / 1673 |
| long | ours | five | 115.9 / 258.6 / 529 | 36.5 / 342.3 / 759 | 32.6 / 262.3 / 792 | 205.4 / 557.8 / 800 |
| long | ours | window | 2.3 / 2.3 / 64 | 2.4 / 2.6 / 64 | 4.0 / 10.6 / 95 | 240.2 / 827.7 / 1677 |
| long | ours | pass | 117.0 / 502.4 / 1369 | 68.8 / 624.0 / 1517 | 62.1 / 499.2 / 1466 | 277.1 / 823.7 / 1715 |
| long | pyarrow | full | 114.8 / 454.0 / 1208 | 57.1 / 565.8 / 1479 | 64.7 / 376.3 / 1306 | 263.6 / 734.3 / 1757 |
| long | pyarrow | five | 122.6 / 266.2 / 670 | 41.7 / 358.9 / 893 | 34.0 / 251.2 / 735 | 235.5 / 442.1 / 837 |
| long | pyarrow | window | 5.5 / 5.5 / 66 | 5.6 / 5.8 / 68 | 5.8 / 20.6 / 146 | 265.1 / 734.1 / 1742 |
| long | pyarrow | pass | 129.0 / 527.9 / 1491 | 72.8 / 655.7 / 1786 | 85.0 / 445.2 / 1464 | 306.8 / 763.8 / 1825 |
| long | polars | full | 185.7 / 819.7 / 1064 | 90.3 / 938.9 / 1159 | 86.7 / 878.9 / 1279 | 265.7 / 1215 / 1765 |
| long | polars | five | 188.2 / 405.0 / 518 | 48.9 / 511.4 / 667 | 52.6 / 453.7 / 769 | 213.3 / 719.8 / 823 |
| long | polars | window | 6.5 / 6.5 / 64 | 6.7 / 6.8 / 65 | 8.5 / 14.5 / 87 | 265.3 / 1217 / 1766 |
| long | polars | pass | 202.6 / 898.6 / 1358 | 102.8 / 1030 / 1453 | 97.8 / 965.0 / 1561 | 309.6 / 1258 / 1811 |
| groups | ours | full | 41.1 / 95.7 / 372 | 23.4 / 152.4 / 468 | 12.4 / 84.9 / 408 | 202.9 / 439.8 / 647 |
| groups | ours | five | 41.1 / 95.5 / 373 | 23.5 / 159.7 / 467 | 12.5 / 86.3 / 409 | 201.3 / 438.2 / 649 |
| groups | ours | window | 0.8 / 0.8 / 61 | 1.0 / 1.2 / 62 | 2.1 / 8.0 / 77 | 198.7 / 432.8 / 639 |
| groups | ours | pass | 51.3 / 128.3 / 554 | 33.0 / 189.8 / 648 | 22.0 / 114.4 / 581 | 236.2 / 475.4 / 764 |
| groups | pyarrow | full | 42.1 / 96.9 / 378 | 24.7 / 153.1 / 436 | 12.4 / 82.3 / 396 | 226.5 / 340.9 / 591 |
| groups | pyarrow | five | 42.1 / 96.0 / 377 | 22.0 / 145.1 / 438 | 12.0 / 78.8 / 397 | 226.8 / 340.5 / 584 |
| groups | pyarrow | window | 0.5 / 0.5 / 61 | 0.6 / 0.8 / 61 | 1.9 / 7.7 / 79 | 223.1 / 336.2 / 590 |
| groups | pyarrow | pass | 51.3 / 127.1 / 556 | 32.6 / 182.7 / 616 | 22.2 / 109.2 / 563 | 260.3 / 380.7 / 693 |
| groups | polars | full | 42.9 / 100.4 / 370 | 22.1 / 162.3 / 448 | 13.3 / 95.1 / 411 | 199.9 / 480.9 / 674 |
| groups | polars | five | 43.0 / 100.5 / 369 | 22.0 / 155.9 / 441 | 13.4 / 98.2 / 411 | 197.6 / 459.7 / 668 |
| groups | polars | window | 0.6 / 0.6 / 61 | 0.7 / 0.9 / 61 | 2.0 / 7.5 / 77 | 199.7 / 480.0 / 670 |
| groups | polars | pass | 53.0 / 133.6 / 549 | 30.7 / 193.6 / 622 | 22.8 / 122.5 / 585 | 231.1 / 515.5 / 784 |

Ours over theirs as geometric means over the 4 files and 3 writers
(wall, peak RSS, CPU). Below 1 means ours is lower. These pool the
families, where plan 0018 takes one mean for NSFG and one for DHS.

| ours | against | whole file | five columns | 1,000 rows | read + pass |
|---|---|---|---|---|---|
| default | polars | 2.05, 0.97, 1.19 | 1.45, 0.78, 0.57 | 0.82, 0.77, 0.37 | 1.62, 1.02, 1.13 |
| tuned | polars | 1.06, 1.08, 1.60 | 0.94, 0.88, 0.72 | 0.80, 0.79, 0.47 | 1.06, 1.11, 1.40 |
| default | pyarrow | 0.24, 0.70, 0.25 | 0.08, 0.57, 0.08 | 0.03, 0.13, 0.01 | 0.29, 0.84, 0.35 |
| tuned | pyarrow | 0.12, 0.78, 0.34 | 0.05, 0.65, 0.11 | 0.02, 0.13, 0.02 | 0.19, 0.91, 0.43 |

Target checks per file (`table.py` lists each miss):

| ours | against | target 2 (wall or RSS > 1.25×, beyond 20 ms / 16 MiB) | target 3 (CPU) |
|---|---|---|---|
| default | polars | 25 misses | 12 misses |
| tuned | polars | 0 misses | 28 misses |
| default or tuned | pyarrow | 0 misses | 0 misses |

The default's 25 target-2 misses are all wall time, between 1.43× and
3.6×: whole-file reads, five columns of `long` and `groups`, and the
read and pass.

The tuned variant's 28 target-3 misses are CPU, between 1.3× and 1.9×
polars':
- `groups` and the DHS file in every case.
- `long` and NSFG in most whole-file and pass cases.
- The DHS window read.

## The five questions

### 1. Does polars import our buffers without copying?

Numbers and text: yes. Dictionary arrays (categoricals): no; polars
converts them, as its own reader does.

- **Numbers.** `Series._s.as_single_ptr()` gives the same address as
  our buffer for every numeric column read:
  - all 5,149 numeric columns of the DHS file;
  - all 10 numeric columns of `long`;
  - `groups`' int32 column.

  Peak RSS agrees. Ours is the data we hold plus the base: DHS 403 MiB
  is 219 MiB of data, 58 MiB of base, and the per-row codes (see
  question 4). `df.estimated_size()` equals that of the frame from
  `pl.read_parquet` (228.3 MB for DHS, 96.9 MB for NSFG).
- **Utf8View text, with views into shared dictionary bytes.** No copy.
  - On a 20M-row text column with values longer than 12 bytes (so every
    view points into a shared buffer), importing took 0.1 ms. Peak RSS
    did not grow (310 → 311 MiB above base; we hold 305 MiB).
  - `groups` and `long` show no growth in peak RSS on import either.
  - `estimated_size` reports 491 MiB for the 305 MiB we hold. It seems
    to count a shared buffer once per view array that uses it. That is
    an accounting difference, not a copy.
- **Dictionary arrays (categoricals).** Polars converts them to its own
  `Categorical`.
  - On a 20M-row column (40 levels, a fixture written by our writer from
    data made in the script), the import took 38 to 40 ms and peak RSS
    rose by 78 MiB, about the size of the keys.
  - int32 and uint32 keys behave the same.
  - `pl.read_parquet` of the same column takes 36 ms and +237 MiB, so
    this costs no more than polars' own path. It is still not
    zero-copy.

### 2. Do the buffers stay valid after the producer is dropped?

Yes. For every input in `check.py` (DHS, NSFG 2002 FemResp, `long`,
`groups`, NSFG 1976 PSU; each from three writers), the test does this:
build the frame; `del` the producer; `gc.collect()`; allocate and
discard 64 MiB of random bytes to overwrite freed memory; then compare
every value with `pl.read_parquet`. All were equal, in one batch and in
one batch per row group, with and without view helpers. Polars holds
the arrays through their release callbacks. Each array's private data
holds an `Arc` of its column's buffers, so the buffers outlive both
our Python object and the stream.

### 3. Multi-chunk and sliced arrays

- **Polars keeps the chunks.** `pl.DataFrame(stream)` does not
  rechunk, so one batch per row group gives a frame of one chunk per
  row group. That is what `pl.read_parquet` itself returns:
  - 39 chunks for `long` from our file, 77 from pyarrow's or polars';
  - 58 chunks for `groups` from our file, 115 from the others.
- **Batching costs nothing either way.** One batch per row group
  against one batch per column, tuned:

  | case | one batch | one per row group |
  |---|---|---|
  | `long` full read | 52 ms | 62 ms |
  | `long` read and pass | 69 ms | 69 ms |
  | `groups` full read | 23 ms | 22 ms |

  This is within noise, and RSS is the same. A user who calls
  `df.rechunk()` on the 39-chunk `long` pays 23 ms.
- **Sliced arrays (`offset` != 0) import correctly and without a
  copy.** The per-row-group batches are slices of whole-column buffers,
  and RSS matched the single batch. Every bench file's row groups start
  at multiples of 8. So `odd_check.py` also writes a file with
  1,001-row groups (pyarrow, from data made in the script), where the
  validity bit offsets are not byte-aligned. The 100 chunks, with
  int32 and text nulls, equal `pl.read_parquet`'s.
- **Recommendation:** export one array per column (or per row group
  when that falls out naturally). It makes no difference to polars, so
  choose whichever the decoder finds simplest.

### 4. Where does the time go?

Timings of the steps, in ms, for whole-file reads of our files (one
run's steps, the median run):

| file | variant | open | setup | read | text on calling thread | bitmaps | polars import | total |
|---|---|---|---|---|---|---|---|---|
| DHS Tajikistan 2017 wm | default | 6.4 | 4.2 | 34.3 | 0.2 | 3.6 | 2.6 | 51.9 |
| DHS Tajikistan 2017 wm | tuned | 4.8 | 4.2 | 9.5 | 0.0 | 1.8 | 2.7 | 23.7 |
| NSFG 2002 FemResp | default | 6.3 | 6.0 | 14.7 | 0.1 | 1.3 | 1.6 | 30.7 |
| NSFG 2002 FemResp | tuned | 3.8 | 6.1 | 4.8 | 0.0 | 1.0 | 1.7 | 17.9 |
| long | default | 0.2 | 0.0 | 100.2 | 63.3 | 1.0 | 0.2 | 101.7 |
| long | tuned | 0.2 | 0.0 | 51.1 | 0.1 | 0.5 | 0.2 | 52.2 |
| groups | default | 0.2 | 0.0 | 40.0 | 15.3 | 0.7 | 0.2 | 41.1 |
| groups | tuned | 0.2 | 0.0 | 22.3 | 0.0 | 0.8 | 0.2 | 23.4 |

What each step covers:
- **open:** the footer, schema and dta profile.
- **setup:** column kinds and buffer allocation.
- **read:** decoding, including views on the calling thread for the
  default variant.
- **bitmaps:** packing codes into validity bitmaps, and dictionaries.
- **polars import:** `pl.DataFrame(obj)`.

What else was measured (3-run medians outside the main run):

- **Thread count.**
  - The core's default rule gives Parquet reads one thread per 176 MiB
    decoded, at least 2 and at most 8. The DHS and NSFG files decode to
    100 to 300 MB, so they get 2 threads; polars uses 16.
  - With 16 threads, the DHS read step falls from 34 to 10 ms.
  - On `long`, scaling stopped at 4 threads: 338 ms at 1 thread, 95 ms
    at 4, 90 ms at 8.
- **In-order delivery.** The core delivers results in row order and
  decodes at most `max(2 × columns, 2 × threads)` tasks ahead. With the
  window ×4, `long` went from 90 to 56 ms at 8 threads and from 70 to
  50 ms at 16. That matches polars' 46 to 50 ms. For `groups` and the
  DHS file, the window made no difference.
- **Text.**
  - With views made on the calling thread, text took 63 of `long`'s
    100 ms and 15 of `groups`' 40 ms. Moving view building to helper
    threads made the calling thread's share almost nothing. On its own,
    without more threads and the wider window, it saved little wall time
    (`long` 102 → 96 ms).
  - `groups` remains 23 ms against polars' 12, with 152 ms CPU against
    85. The cause is the core's text pipeline: each dictionary-encoded
    chunk is decoded to a `Vec<u32>` of codes plus the dictionary's
    bytes (`TextChunk`), then turned into views in a second pass.
    Polars decodes the indices straight into views.
- **Per-row missing codes.** Dropping them (`DTA_SPIKE_NO_CODES=1`,
  which loses the nulls) saved 6 to 7 ms of CPU and 70 MiB of peak RSS
  on the DHS file, and 3 ms and 22 MiB on NSFG. This is the RSS
  difference with polars on the DHS file (403 to 415 MiB against 359).
- **Per-value decode speed.** This is the largest remaining cost, and
  it is in the core, not the Arrow handoff. On one thread:

  | file | ours: read step / total | polars, `POLARS_MAX_THREADS=1` |
  |---|---|---|
  | DHS Tajikistan 2017 wm | 57 ms / 75 ms | 42 ms |
  | NSFG 2002 FemResp | 27 ms / 44 ms | 27 ms |

  Going from 1 thread to 16 adds about 40 ms of CPU on the DHS file
  (75 → 116 ms). Spawning threads per read and waiting for in-order
  delivery account for some of it.
- **Fixed costs on wide files.**
  - open: 6.4 ms, or 4.8 ms with lazy value labels.
  - setup: 4 to 6 ms, for a kind and two `calloc`s per column, for 3,000
    to 5,000 columns.
  - polars' import: 1.6 to 2.7 ms. This is the cost of the capsule
    route itself: polars parses one schema and imports one array per
    column. It is small next to the rest.

### 5. Does it pass plan 0018's targets 1 to 3?

**Against pyarrow's `read_table`: yes, in every case, even with the
default rules.** No target-2 or target-3 misses. Wall-time geometric
means are 0.02 to 0.29 of pyarrow's, and RSS 0.13 to 0.91. pyarrow is
slow on these files: 170 to 280 ms even for five columns, which
suggests a per-column cost on wide files.

**Against `pl.read_parquet`: no.**

- **Default rules.** Wall time is 2.05× polars' on whole-file reads
  (geometric mean), and 25 single cases miss target 2.
- **Tuned.** Wall time is 1.06× (whole file), 0.94× (five columns),
  0.80× (1,000 rows) and 1.06× (read and pass). That is at or just above
  target 1's 1.05, within this machine's noise, and no case misses
  target 2. RSS is 1.08× and 1.11× on the whole-file and pass reads.
  But CPU is 1.4× to 1.9× polars' while wall time is no better, so 28
  cases miss target 3.

**What the gap is:**

1. **Thread count.** This explains most of the wall-time gap on the
   survey files: DHS 52 → 24 ms, NSFG 31 → 18 ms. Our rule gives these
   files 2 threads; polars uses 16. Raising the thread count fixes wall
   time but not CPU.
2. **Per-value decode cost in the core.** This is what fails target 3.
   On one thread our decoder takes 1.4× (DHS) to 1.0× (NSFG) polars'
   whole read on the read step alone, before the setup and footer
   costs. More threads make it worse.
3. **Text building.**
   - The calling-thread bottleneck goes away with helper threads.
   - The intermediate codes-then-views pass remains, and it is why
     `groups` stays at 1.9× polars' wall and CPU.
   - The in-order look-ahead window is why `long` needs the ×4 setting.
4. **Per-row missing codes.** These cost RSS (the DHS file at 1.12 to
   1.16× polars') and some CPU.
5. **The Arrow import is not the problem.** It is 0.1 to 2.7 ms, and
   zero-copy for everything but categoricals.

## What production should do differently

1. **Decode definition levels straight into a validity bitmap.** Arrow
   outputs should get a bitmap from the core, not a `u8` per row packed
   afterwards. Keep per-row codes only where `.a` to `.z` must be told
   apart, which is DOUBLE columns, and even there the NaN payload already
   carries the letter. That saves the 1-byte-per-value buffer (70 MiB
   on the DHS file) and a pass.
2. **Build text views on the worker that decodes the chunk.**
   - Add a core output (an `Output::Views`, say) that decodes
     dictionary indices straight into 16-byte views and PLAIN values
     straight into views over the page's bytes.
   - Each worker writes its own rows. That needs no in-order delivery,
     no `Vec<u32>` of codes, no calling-thread work and no helper
     threads.
   - Buffer indexes can be fixed per (row group, column) in advance.
3. **Drop the in-order look-ahead window for outputs that do not need
   order.** Arrow outputs need no order: every task writes disjoint rows
   and owns its buffers. Levels found in the rows read (`LevelsFrom::Rows`)
   still need order, but they can be merged after the read.
4. **Choose threads for this path as polars does.** Up to the machine's
   cores for whole-file reads, not the 2-to-8 rule tuned for pandas
   output. Then measure target 3 against polars after items 1 to 3.
   Our single-thread decode is the cost that remains, and closing it
   is core work (snappy, RLE and bit-unpacking per value; page-header
   and task overhead on 5,000 small chunks). A persistent thread pool,
   instead of spawning threads per read, should cut the extra CPU of
   multithreaded reads.
5. **Read value labels lazily on open,** and make setup cheaper on wide
   files: one allocation per type rather than two per column, and kinds
   without per-column hash lookups. Together these are about 5 to 8 ms
   on 5,000 columns, close to a third of polars' whole read of such a
   file.
6. **Keep the hand-written C Data Interface.** It is about 500 lines,
   with no new dependency, and it worked first time with polars 2.1.0.
   - The capsule destructor must release a stream the consumer did not
     take.
   - An `Arc` per column lets slices and repeated exports share buffers.
   - Variadic data buffers per chunk let text chunks move in without a
     copy.
   - Buffers should be aligned to 16 (views) and allocated zeroed with
     `calloc`.
7. **Categoricals:** dictionary arrays (int32 keys, utf8 values) are
   the right export. Polars always converts them, at a cost like its own
   reader's; no key type avoids it. The labels object stays separate,
   as plan 0019 intends.
8. **Rerun on a quiet machine,** over all 36 NSFG and 10 DHS files from
   each writer and with per-family geometric means, before plan 0019
   commits to numbers. The load here was about 9.

## Reproducing

From a checkout of branch `spike/polars-arrow` (commit `3ec678a`), at
the repository root, in a venv with polars and pyarrow:

```sh
(cd python && maturin develop --release)
python bench/parquet/spike/check.py      # equality and the GC test
python bench/parquet/spike/run.py        # the matrix; writes results.json
python bench/parquet/spike/table.py      # the tables above
python bench/parquet/spike/cat_check.py make /tmp/cat.parquet
python bench/parquet/spike/cat_check.py cat /tmp/cat.parquet
```
