## Findings

On the 36 public-use NSFG files and the 10 DHS files, ours is faster than
every other reader in its language at reading whole files, at the pass
over every value, at five columns and at a 1,000-row window, taking the
geometric mean over the files (the exceptions on single files are under
"Targets missed"). The other readers' time over ours:

| language | full read (NSFG, DHS) | read + pass (NSFG, DHS) |
|---|---|---|
| R | haven 13×, 22×; readstata13 14×, 25× | haven 6.8×, 12×; readstata13 7.5×, 13× |
| TypeScript | statfmt 14×, 13× | statfmt 8.1×, 8.9× |

The margin is narrowest in R's pass over every value, where dtatools
makes its packed strings into R strings (ADR 0010). Metadata alone is
where the others come closest: readstata13 (which here reads one row)
is as fast or faster on the smaller files, by fractions of a
millisecond.

The project once had Python and Julia packages too, measured in the
same runs. They were removed on 2026-11-09, and their rows, sections,
and reports with them; where a number below was taken through one of
them, the text says so.

### Fixed because of these runs

Each fix is its own commit, with a test where the behaviour can be
tested (1 and 2). Ours was then measured again with `--readers ours`;
the other readers' results were not re-run.

1. **TypeScript, writing** (`js/src/index.ts`). Writing what
   `readColumns` returned meant an array of numbers and `Missing` values
   per column, and a `Uint8Array` per string. A variable may now give its
   `Float64Array` and missing codes, and strings are encoded into one
   buffer. long.dta: 10.2 s and 9.3 GB → 3.5 s and 3.4 GB (statfmt
   18.8 s); 2002_FemPreg: 289 MB → 195 MB (statfmt 187 MB).
2. **Core, chunk size** (`crates/dta/src/reader.rs`). Chunks were 8 MiB
   of rows, but a byte decodes to 9 bytes, so files of byte variables
   held 72 MiB decoded per chunk. Chunks are now 8 MiB decoded. Peak
   memory of a full read of 2015_2017_Male: R 365 MB → 255 MB
   (readstata13 229 MB), TypeScript 573 MB → 418 MB with fix 4 (statfmt
   325 MB).
3. **Core, column room** (`crates/dta/src/reader.rs`). Decoded columns
   grew by doubling; they now reserve a chunk's rows. The native read,
   timed through the Python binding (since removed): 1976_Preg
   7.0 → 4.8 ms, 2015_2017_Male 42.5 → 33.8 ms.
4. **wasm, read buffers** (`crates/dta-ffi/src/wasm.rs`). Appending
   chunks regrew the columns in module memory, which never shrinks; a
   read now reserves its rows.
5. **The harness, not the package**: haven loads tibble and vctrs with
   itself, dtatools on its first read, so 0.08 s fell inside dtatools'
   timed tasks only. Both now load them before the clock.

### Targets missed, and why

- **R metadata and windows on small files** (by 0.02 to 0.2 ms).
  dtatools builds a tibble with per-column attributes; readstata13's
  "metadata" here is a one-row read without them.
- **R memory** on the pass over every value (6 files) and one full read:
  dtatools keeps the packed text while R makes its strings (ADR 0010),
  and stores every number as a double (ADR 0003) where readstata13 keeps
  R integers.
- **TypeScript memory** reading one 3,000-variable NSFG file
  (2013_2015_Male, 1.6×) and writing three files: ours holds a
  `Float64Array` and a byte of missing code per value (9 bytes), statfmt
  small integers in plain arrays. Writing copies every column into
  module memory before streaming the file, so writing costs more memory
  than reading, and **wide.dta (4.8 GB) cannot be written** from
  TypeScript: wasm32 memory stops at 4 GiB. Writing row blocks as they
  come would lift that; not done here.

### What the correctness checks found

- **Values agree everywhere**: every full read, five-column read, window
  and checksum of every reader equals ours, on every file where both
  ran (missing codes too, where haven keeps `.a`–`.z`).
- **Labels with trailing spaces**: haven and statfmt (both
  ReadStat-based) drop trailing spaces from variable and value labels;
  ours and readstata13 keep the file's text. This is every metadata
  "difference" on NSFG and most on DHS.
- **Writers**: ours writes back values and metadata that the
  open-source readers read as they read the source, in both languages.
  readstata13's writer drops the data label and display formats.
- **Readers that could not finish**: statfmt's write of wide.dta failed
  in the harness, not in statfmt: it wrote the 4.8 GB result with one
  `fs.writeFileSync`, which Node limits to 2 GiB. The harness now
  writes it in pieces; the measurement was not repeated, since the
  other readers' results are not re-run.

The earlier R-only measurements (writing from R, survey-shaped string
columns, grouping) are in [results/r-only.md](results/r-only.md).

## Parquet

Plan 0018's speed and memory gate for R (PR 3): datakit's
`read_parquet()` and `save_parquet()` against arrow 26.0.0, nanoparquet
0.5.2 and duckdb 2.0.0, and pyarrow 26.0.1, polars 2.1.0 and DuckDB
2.0.0 reading our files. Every file and number is in
[results/parquet.md](results/parquet.md), written by
`bench/parquet/run.py`; this section is written by hand from it.

**Every target holds**, on the 36 NSFG files, the 10 DHS files and the
three synthetic files, on each of the three inputs (pyarrow's, polars'
and our files of the same data).

Ours over theirs, geometric means of wall time over the files (NSFG,
DHS); below 1 is faster. Reads are of pyarrow's files; reads of polars'
and our files are within a few hundredths of these, and are in the
full report.

| against | whole file | five columns | 1,000 rows | read + pass | write (defaults) |
|---|---|---|---|---|---|
| arrow | 0.38, 0.85 | 0.10, 0.13 | 0.21, 0.25 | 0.48, 0.49 | 0.04, 0.03 |
| nanoparquet | 0.52, 0.37 | 0.30, 0.08 | 0.26, 0.11 | 0.83, 0.74 | 0.35, 0.34 |
| duckdb | 0.24, 0.16 | 0.36, 0.29 | 0.15, 0.10 | 0.59, 0.47 | 0.35, 0.25 |

- **Target 1** (geometric mean of wall time and of peak RSS at most
  1.05 times theirs, over NSFG and over DHS): the highest wall ratio is
  0.98 (arrow, whole file of our DHS files: arrow's whole-file read
  makes its vectors lazily), the highest RSS ratio 0.85.
- **Target 2** (no file over 1.25 times, unless by under 20 ms or 16
  MiB): the closest on wall time is arrow reading DHS Senegal 2019 bh,
  32 ms against 27 (1.21); on peak RSS, nanoparquet's read and pass of
  NSFG 2006_2010_FemPreg (1.06), and nanoparquet writing wide.dta,
  5,050 MB against 4,948 (1.02).
- **Target 3** (CPU at most theirs times the larger of 1.15 and our
  speedup): the closest is groups.dta's read and pass against
  nanoparquet, 0.696 s against the 0.723 s allowed.
- **Target 4** (pyarrow, polars and DuckDB read our files within 1.10
  times their own): geometric means of 0.99 (pyarrow), 0.86 to 0.90
  (polars) and 1.03 to 1.07 (DuckDB). The one file over 1.10 in the run
  was DuckDB on DHS Tajikistan 2017 bh at 1.1008; 15 interleaved runs
  of each gave 135.7 ms against 125.3 (1.08).
- **Not compared.** DuckDB's R package could not read
  pyarrow's 4.8 GB wide.dta file ("Could not read from file ...:
  Invalid argument"); those cases have no comparison.

### Fixed because of these runs

Each is its own commit on the branch.

1. **Snappy, not zstd, by default.** With zstd 3 (the plan's default)
   DuckDB took 1.40 times as long to read our long.dta as its own
   snappy file, 2.38 times on wide.dta, and up to 1.15 times on the
   survey files; pyarrow 1.49 times on wide.dta. Snappy fixed all of
   them. zstd made survey files only 16 to 17% smaller (the size ratio
   is 0.84 on NSFG and 0.83 on DHS: most columns are dictionary-encoded
   before compression) and our reader three times slower on doubles
   that do not compress. zstd writes took 1.03 to 1.29 times as long as
   snappy ones and were still faster than every other library's.
2. **Threads by size.** At first every large read used two threads (see
   below); arrow, on sixteen, read long.dta in 160 ms against our 215.
   Reads now take a thread per 176 MiB of decoded values (up to eight)
   and writes one per 256 MiB (up to six); long.dta then took 148 ms.
3. **R's heap grown once.** A first read in a new session spent a
   quarter to a third of its time in garbage collection while R grew
   its memory a step at a time (13 collections on long.dta). datakit
   now has R make room for the result first: NSFG 1995 read in 0.161 s
   instead of 0.231.
4. **Text copied by the run.** A chunk of plain text, and the PLAIN
   pages of pyarrow's chunks whose dictionary filled, are copied a run
   of values at a time instead of a row at a time.
5. **Column chunks written as they are encoded.** The writer held a
   whole row group's pages (840 MB of wide.dta's) before writing them;
   writing wide.dta with zstd peaked at 6.3 GB, 1.27 times nanoparquet.
   Chunks now go out in order as soon as they are done: 5.0 GB.
6. **A shorter path to a packed column's strings.** nchar() and is.na()
   over groups.dta's 15 million rows took 0.338 and 0.105 s instead of
   0.376 and 0.143; its read and pass had used 0.795 s of CPU against
   0.744 allowed.
7. Earlier, while building: row groups of up to 1 GiB instead of the
   plan's 64 MiB (pyarrow took 2.4 times as long to read a DHS file cut
   into four), and the profile's JSON parsed without copying its
   strings.

### Threads

Plan 0018 sets the Parquet default by plan 0007's rule: each thread
added must make the task faster by at least half of what one thread
does (the speedup gained, per thread added, at least 0.5), and CPU
time must stay within 1.15 times one thread's. Measured in one R
session (`bench/parquet/threads.R`, median of nine runs after one to
warm up, snappy files, load average about 12), the counts that pass
depend on the size of the work: survey files of up to about 250 MiB
decoded stop at two, because much of their work is per column on the
calling thread, while long.dta passes for reads at four and wide.dta at
eight. One fixed count would either hold large reads to two or give
survey files threads that do not pay. So the rule is applied per size,
which plan 0007 left to later stages: reads use a thread per 176 MiB of
decoded values, from two to eight; writes one per 256 MiB of values,
from two to six. Reads and writes under 16 MB use one. These are the
measurements behind them, taken before fixes 3 to 6. Those change a
first read in a new session and the pass after a read, not how a read
scales; fix 5 lets the writer write while it encodes, which can only
help writes on more threads.

Whole-file reads. Each cell: wall time; CPU time over one thread's; speed gained per thread added since the previous count, in threads. Bold: the rule fails there.

| file (decoded size) | 1 | 2 | 3 | 4 | 6 | 8 | 12 | 16 |
|---|---|---|---|---|---|---|---|---|
| NSFG 1995_FemResp (238 MiB) | 76 ms | 48 ms; 1.03×; 0.60 | 38 ms; 1.04×; **0.39** | 34 ms; 1.05×; **0.29** | 30 ms; 1.11×; **0.15** | 27 ms; 1.11×; **0.12** | 26 ms; **1.16×**; **0.03** | 26 ms; **1.18×**; **0.01** |
| NSFG 2006_2010_FemResp (176 MiB) | 63 ms | 39 ms; 1.05×; 0.61 | 30 ms; 1.03×; 0.50 | 26 ms; 1.05×; **0.32** | 22 ms; 1.08×; **0.22** | 20 ms; 1.14×; **0.12** | 19 ms; **1.17×**; **0.04** | 18 ms; **1.17×**; **0.05** |
| DHS Myanmar 2016 wm (246 MiB) | 60 ms | 35 ms; 1.03×; 0.69 | 28 ms; 1.05×; **0.48** | 23 ms; 1.07×; **0.39** | 21 ms; **1.22×**; **0.18** | 18 ms; 1.12×; **0.18** | 16 ms; **1.17×**; **0.09** | 16 ms; **1.23×**; **0.04** |
| DHS Tajikistan 2017 bh (96 MiB) | 33 ms | 19 ms; 1.03×; 0.80 | 13 ms; 1.03×; 0.72 | 11 ms; 1.06×; **0.45** | 9 ms; **1.15×**; **0.40** | 8 ms; **1.15×**; **0.18** | 8 ms; **1.18×**; **0.00** | 7 ms; **1.24×**; **0.22** |
| groups (74 MiB) | 82 ms | 38 ms; 1.02×; 1.18 | 35 ms; **1.22×**; **0.17** | 22 ms; **1.20×**; 1.29 | 18 ms; **1.21×**; **0.48** | 17 ms; **1.21×**; **0.12** | 17 ms; **1.28×**; **0.01** | 16 ms; **1.28×**; **0.09** |
| long (777 MiB) | 329 ms | 166 ms; 1.04×; 0.99 | 111 ms; 1.07×; 0.97 | 93 ms; 1.03×; 0.59 | 97 ms; **1.23×**; **-0.07** | 103 ms; **1.30×**; **-0.11** | 113 ms; **1.41×**; **-0.07** | 88 ms; **1.41×**; **0.20** |
| wide (4,578 MiB) | 1.02 s | 521 ms; 1.02×; 0.95 | 355 ms; 1.03×; 0.91 | 281 ms; 1.07×; 0.75 | 197 ms; 1.12×; 0.78 | 157 ms; 1.14×; 0.66 | 130 ms; **1.30×**; **0.33** | 132 ms; **1.41×**; **-0.03** |

Five columns. Each cell: wall time; CPU time over one thread's; speed gained per thread added since the previous count, in threads. Bold: the rule fails there.

| file (decoded size) | 1 | 2 | 3 | 4 | 6 | 8 | 12 | 16 |
|---|---|---|---|---|---|---|---|---|
| groups (74 MiB) | 82 ms | 38 ms; 1.04×; 1.17 | 32 ms; **1.24×**; **0.41** | 21 ms; 1.13×; 1.29 | 18 ms; **1.21×**; **0.29** | 16 ms; **1.20×**; **0.34** | 17 ms; **1.29×**; **-0.09** | 16 ms; **1.26×**; **0.11** |
| long (777 MiB) | 216 ms | 105 ms; 1.00×; 1.06 | 81 ms; 1.02×; 0.61 | 84 ms; 1.04×; **-0.11** | 60 ms; **1.23×**; 0.52 | 62 ms; **1.33×**; **-0.05** | 60 ms; **1.35×**; **0.02** | 59 ms; **1.30×**; **0.02** |
| wide (4,578 MiB) | 12 ms | 7 ms; 1.00×; 0.80 | 5 ms; 1.00×; 0.74 | 4 ms; 1.08×; **0.48** | 4 ms; **1.25×**; **0.14** | 3 ms; **1.33×**; **0.04** | 3 ms; **1.42×**; **0.02** | 3 ms; **1.42×**; **0.03** |

Writes (snappy). Each cell: wall time; CPU time over one thread's; speed gained per thread added since the previous count, in threads. Bold: the rule fails there.

| file (decoded size) | 1 | 2 | 3 | 4 | 6 | 8 | 12 | 16 |
|---|---|---|---|---|---|---|---|---|
| NSFG 1995_FemResp (238 MiB) | 257 ms | 173 ms; 1.07×; **0.49** | 138 ms; 1.07×; **0.38** | 123 ms; 1.09×; **0.23** | 113 ms; **1.22×**; **0.09** | 106 ms; **1.20×**; **0.08** | 103 ms; **1.28×**; **0.01** | 98 ms; **1.25×**; **0.04** |
| NSFG 2006_2010_FemResp (176 MiB) | 205 ms | 132 ms; 1.06×; 0.56 | 103 ms; 1.07×; **0.43** | 90 ms; 1.08×; **0.31** | 77 ms; **1.17×**; **0.18** | 73 ms; **1.22×**; **0.08** | 74 ms; **1.30×**; **-0.01** | 73 ms; **1.27×**; **0.01** |
| DHS Myanmar 2016 wm (246 MiB) | 226 ms | 147 ms; 1.06×; 0.53 | 117 ms; 1.06×; **0.39** | 104 ms; 1.07×; **0.25** | 91 ms; **1.16×**; **0.15** | 85 ms; **1.23×**; **0.09** | 83 ms; **1.23×**; **0.02** | 86 ms; **1.30×**; **-0.03** |
| DHS Tajikistan 2017 bh (96 MiB) | 108 ms | 64 ms; 1.05×; 0.69 | 47 ms; 1.06×; 0.60 | 39 ms; 1.09×; **0.46** | 33 ms; **1.23×**; **0.26** | 31 ms; **1.34×**; **0.08** | 33 ms; **1.37×**; **-0.05** | 34 ms; **1.39×**; **-0.02** |
| groups (74 MiB) | 322 ms | 320 ms; 1.00×; **0.00** | 321 ms; 1.00×; **-0.00** | 321 ms; 1.00×; **0.00** | 319 ms; 0.99×; **0.00** | 321 ms; 1.00×; **-0.00** | 321 ms; 1.00×; **-0.00** | 321 ms; 1.00×; **0.00** |
| long (777 MiB) | 1.98 s | 1.24 s; 1.02×; 0.60 | 945 ms; 1.02×; **0.49** | 884 ms; 1.03×; **0.15** | 774 ms; 1.15×; **0.16** | 756 ms; **1.19×**; **0.03** | 745 ms; **1.18×**; **0.01** | 787 ms; **1.21×**; **-0.03** |
| wide (4,578 MiB) | 9.25 s | 4.99 s; 1.02×; 0.86 | 3.57 s; 1.03×; 0.74 | 2.87 s; 1.04×; 0.64 | 2.15 s; 1.06×; 0.53 | 1.81 s; 1.08×; **0.41** | 1.51 s; 1.13×; **0.25** | 1.45 s; **1.17×**; **0.06** |

The five-column reads of the survey files are under 16 MB and use one
thread whatever is asked, so they are not shown. groups.dta's write
does not gain from threads at any count (two columns, one of text, and
the text is sized on one thread) and costs nothing either; its reads
pass at two. NSFG 1995's write gained 0.49 at two threads in this run
and 0.54 in an earlier one with zstd; two stays the floor.

### Method

Machine: Apple M4 Max (16 cores: 12 performance, 4 efficiency), 128 GB,
macOS 26.7.1; R 4.6.1; Python 3.13 for pyarrow, polars and DuckDB.
Every case ran five times, each in a fresh process under
`/usr/bin/time -l`, with the file in the page cache; the medians of
wall and CPU time (user plus system) of the task alone, timed inside
the process after its packages loaded, and of the process's peak RSS
are used. Each library used its default thread count (arrow and
DuckDB sixteen, nanoparquet one, ours by the rule above). Writes time
writing the frame `dtaparser::read_dta()` returns, with every string
made first; for DuckDB, labelled columns are plain numbers (it cannot
register the class). The read and pass is the whole read and then one
loop over every value: the sum of the numbers, the count of missing
values and the total length of the text, the same loop for every
library. The plan asks for a quiet machine (load average under 2); this
one carried other work throughout, with a one-minute load average of
9.5 to 17.3 (median 11.9) recorded before each run, so single
measurements are noisier than the plan intended; every comparison ran
under the same load.
