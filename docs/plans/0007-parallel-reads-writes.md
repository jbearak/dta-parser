# Plan: faster, leaner reads and writes, with bounded parallelism

Status: approved by Sonnet 5.5 (three rounds) and GPT-6.1 Terra (five
rounds); implemented in PR #22. One change from the plan: the default
is at most three threads, not four (Python's full read of wide.dta used
1.10–1.16× the CPU at four). Results: bench/RESULTS.md, fixes 9 to 13.

## Problem

Measured on an M4 Max (12 performance and 4 efficiency cores), files in
the page cache:

| file | core read | core write | R read | Python read | Julia read | R write |
|---|---|---|---|---|---|---|
| wide.dta (4.8 GB, 400 doubles, 1.5M rows) | 1.00 s | 5.40 s | 1.74 s | 1.60 s | 1.38 s | 5.37 s |
| long.dta (740 MB, 12 mixed, 10M rows) | 0.28 s | 0.73 s | 0.47 s | 0.78 s | 0.71 s | 6.24 s |
| groups.dta (270 MB, byte + str17, 15M rows) | 0.16 s | 0.35 s | 0.29 s | 0.44 s | 0.46 s | 0.73 s |

Core times are from a throwaway Rust harness that reads every column
with `read_chunks`, or writes what it read; binding times are from
bench/results/synthetic.md (task 1 and task 6).

1. **The writer is the slowest part of the core**: 9 ns per cell on
   wide.dta. Every cell is a dynamic call returning `(f64, u8)`, made
   twice (plan pass and row pass), and rows are built row-major, so
   each row touches 800 arrays (values and codes) on wide.dta.
2. **R writes force packed strings.** `save_dta` of dtatools'
   `read_dta(long.dta)` takes 6.17 s; after `x[]` has made the strings,
   the same write takes 0.87 s. `write()` in init.c calls
   `materialize()` on the whole spec, whose `STRING_PTR_RO` runs the
   packed class's dataptr method: every R string of each packed column
   is made (strings.c), 20M of them here, and the packed text dropped.
3. **Reads run on one thread**, and the bindings copy decoded columns
   into their own arrays on that thread too (R, Python and Julia add
   0.4–0.7 s to the core's 1.0 s on wide.dta).
4. **Chunk size**: reading in 2 MiB chunks instead of 8 MiB takes
   wide.dta's core read from 1.00 s to 0.855 s (long and groups
   unchanged); 1 MiB and 512 KiB are no better.

## Constraint on parallelism

The user's rule: parallelise, but not where saving wall time costs an
unreasonable amount of CPU time.

A probe of independent readers over disjoint row ranges (all columns,
output discarded) scales almost linearly:

| file | 1 thread | 2 | 4 | 8 | 12 | CPU (user + sys) at 1 / 4 / 8 |
|---|---|---|---|---|---|---|
| long.dta | 0.29 s | 0.14 | 0.069 | 0.039 | 0.036 | 0.28 / 0.26 / 0.29 s |
| groups.dta | 0.16 s | 0.081 | 0.041 | 0.022 | 0.022 | 0.15 / 0.15 / 0.16 s |
| wide.dta | 1.01 s | 0.52 | 0.27 | 0.17 | 0.16 | 1.00 / 1.05 / 1.34 s |

The policy:

- **Budget**: with threads, the task's CPU time is at most **1.15×**
  the same build's with one thread, measured per task (below). wide.dta
  at 8 threads (1.34×) breaks it; at 4 (1.05×) it holds.
- **Default thread count: `min(4, available_parallelism)`, and on
  x86 `min(4, max(1, available_parallelism / 2))` unconditionally** (SMT
  siblings add little, and a shared CI VM's CPU times are too noisy to
  gate on). Four is
  the most this machine's probe allows within budget; marginal
  efficiency (speedup gained by the last thread added ÷ 1) is ≥ 0.5 up
  to 4 on every file. The count is fixed, not chosen per file: a
  per-workload choice needs a model of costs we do not have, and a
  fixed small number is predictable. Stages 4 and 5 may lower the
  ceiling (see their acceptance rules); they never raise it.
- **Only large work**: a read or write stays on the calling thread
  unless its rows cover at least 16 MiB of the file (row length ×
  rows read, counting only the selected columns' widths). The 23 NSFG
  files under 16 MiB, every 1,000-row window and every metadata read
  stay serial; the 13 larger NSFG files (17–79 MB) go parallel and are
  in the measurements.
- **Controls**: `threads` on the core's read and write options (0 means
  the default); `DTA_THREADS` in the environment for every binding;
  in R also `options(dtaparser.threads = )`, which wins over the
  variable. R honours `_R_CHECK_LIMIT_CORES_` (at most 2 when set to
  anything but `false`), so `R CMD check` stays within CRAN's limit.
  `1` turns parallelism off. Both are read at each call, not cached.
- **wasm**: threading code is behind `cfg(not(target_arch = "wasm32"))`
  for both reader and writer; wasm is always serial.
- **No new dependencies** for the library: `std::thread::scope`,
  `Mutex`/`Condvar`, atomics. Threads are spawned once per read or
  write, never per chunk.

## Stages

Each stage is its own commit, measured before the next starts, and
kept only if it helps. Threads come last.

1. **W4**: R writes packed columns from their bytes.
2. **W1 + W3 serial**: the writer fills numbers by block and builds
   rows column-major in cache-sized slabs, one thread.
3. **Reads serial**: 2 MiB chunks; then R2's decode tightening, each
   kept only if it is faster.
4. **Parallel writes** (W2, W3 with workers).
5. **Parallel reads** (R1).

**Acceptance rule for stages 4 and 5**, measured with `bench/threads`
(real destination arrays, task-only CPU): at the default thread count,
on every task and binding measured, CPU time ≤ 1.15× the one-thread
run of the same build; wall time at least 25% lower on wide.dta and
long.dta; peak RSS no more than the serial run's + 5% + 32 MiB. If a
count fails anywhere, the default ceiling drops to the largest count
that passes everywhere; if none above 1 passes, the stage is
reverted. The rule is applied per path: full reads, column selections
and writes, in each binding, and the NSFG files over the threshold. A
path that fails at every count above 1 is made serial (the binding
passes `threads = 1` for it, or the core's threshold for that
operation is raised until the path no longer goes parallel) before the
next stage starts; the rest keep their threads. User and system CPU
are recorded separately, with their sum (which the rule uses) and peak
RSS. The x86 CI run (Measurement) is reported, not gated.

## Design

### W4. R: write packed columns from their bytes (stage 1)

strings.c exports `dtaparser_packed_parts(x, &bytes, &ends, &codes)`:

- returns 0 if `x` is not of dtaparser's packed class (an exact
  `R_altrep_inherits(x, packed_class)` test);
- 1 if it is packed, with its `bytes` (raw), `ends` (double) and
  `codes` (integer or `R_NilValue`) from data1;
- 2 if it is made, with data2 (an ordinary character vector) in `bytes`.

The Rust side reads value `i` as `bytes[ends[j-1]..ends[j]]` with
`j = codes[i]` (or `i` without codes), and a made column with
`STRING_ELT` on data2 (`NA` → `""` as today). No R string is made and
the column stays packed. The parts are reachable from `x`, which the
`spec` list passed to `.Call` keeps alive, so they need no extra
protection. Packed text is UTF-8 without NULs: `read_dta` decoded it to
UTF-8 and rejected embedded NULs (`Strings::gather`); the writer's
UTF-8 check still runs on it.

`write()` in init.c materialises the spec as today except for one
case: a **direct element of `spec$columns`** (element 0, the data
columns) of the packed class (same exact class test) is skipped. Every
other field (names, labels, notes, characteristics, value label texts,
and any packed vector found there) is materialised as before, so the
metadata Rust reads with `r_strings()`/`STRING_ELT` is never packed.
So:
any other ALTREP vector (vroom, arrow, R's deferred strings, compact
integer sequences) is made in C before Rust borrows anything, where an
allocation failure or R error is an ordinary R error. After that, every
string the writer borrows is a CHARSXP held by a materialised vector
reachable from `spec`, so it stays alive and in place for the whole
`.Call`, including the strL dedup table's borrowed keys
(`writer.rs:90`). Reading a made packed column through data2 uses
`STRING_ELT` on an ordinary vector, which neither allocates nor
errors. Only the calling thread touches string columns (below).

### W1. Writer: numbers by block (stage 2)

`Values::Numbers` changes to a block fill:

```rust
Numbers(Box<dyn Fn(usize, &mut [f64], &mut [u8]) + Sync + 'a>)
```

called with a first row and buffers of up to 1024 rows; it writes each
row's value and missing code. One dynamic call per column per block,
and the binding's loop is a tight, monomorphised loop over its slice.
Every binding holds numbers as slices: R `REAL`/`INTEGER`/`LOGICAL`,
numpy buffers, Julia's arrays (native C ABI), wasm's copies.

This is a breaking change to the `dta` crate's API. Its callers:
`crates/dta/tests/{budget,write}.rs`, `crates/dta-ffi/src/{native,wasm}.rs`,
`python/src/lib.rs` and `r/dtaparser/src/rust/lib.rs`. The crate is not
published (README: no package is on a registry); its only users are
this repository's bindings, all updated in the same commit. The same
goes for adding `threads` to `Options` and to a new `WriteOptions`.
The crate's version and CHANGELOG-style note in its docs say so.

Strings keep their per-row `Fn(usize)` closures without `Sync`:
Python's need the GIL, and R's foreign ALTREP vectors the R thread.

### W3. Writer: rows column-major in slabs (stage 2, serial)

Rows are built in blocks of 8 MiB as now, but each block is filled as
slabs of up to 256 KiB of rows (at least one row), column by column:
for each numeric column, the block fill writes up to 1024 rows of
`(f64, u8)` into a small buffer and `encode` stores them at the
column's offset in each row; then each string column copies and pads
its rows; strL columns write their references. The slab size is
measured at 128, 256 and 512 KiB and the best kept. Output is
byte-identical to today's writer (tests below).

### W2. Writer: plan pass in parallel (stage 4)

The plan pass runs as today per variable: global checks (variable
count, data label, sort order), then for each variable in order its
metadata (name, label, format, value label name) and then its data.
In parallel:

- metadata checks for all variables run first on the calling thread
  (cheap) and record each variable's first metadata error: name,
  label, format, value label name, numbers given for a string storage
  type (`writer.rs:129`), and the strL row and variable limit
  (`writer.rs:149`, for columns that will be strLs);
- numeric columns are checked by workers, one column at a time from a
  shared counter; each records its first bad row;
- string and strL columns are checked on the calling thread at the
  same time (longest value, strL limits, UTF-8, the strL dedup table,
  in today's order within the column).

The error reported is the one the serial pass would hit first: the
lowest variable index with any error, and within it the metadata error
if any, else its data error. Value label and characteristic errors
come after every variable, as today (`writer.rs:188-189`). The plan
pass uses the block `Numbers` fill too. Each column's own check runs exactly the
serial code over that column, so its first error is the same. A worker
stops early only for columns after the lowest error found so far.

### W3 with workers (stage 4)

Per 8 MiB block, with two blocks:

- the calling thread fills the string and strL cells of the block one
  slab at a time (strL references through the recent-text cache and
  dedup table, as today), and after each slab publishes it (an atomic
  count of ready slabs);
- workers take ready slabs from a counter and fill their numeric
  cells, so a slab is never written by the caller and a worker at the
  same time (no false sharing within a slab; only the cache lines
  where two slabs meet can be shared). With no string columns every
  slab is ready at once;
- when the caller has filled the block's strings it writes the
  previous block to the file, then waits for the workers to finish the
  block, and the blocks swap.

The caller and workers write disjoint bytes (each column's cells are
its own, and a slab is handed over once), so no string pointers are
staged: string memory beyond the block is zero. The writes go through
a raw pointer to the block; that `unsafe` is confined to one function
with the disjointness argument in its comment. Writing the strL section and
value labels stays serial and unchanged, so strL first-occurrence
order, text/binary flags and section order are as today.

Memory: two blocks of 8 MiB capacity, the per-worker 1024-row buffers
(9 KiB), the dedup tables as today, and thread stacks. A row longer
than 8 MiB (possible: up to 32,767 strN variables) makes a block of
one row larger than that; such writes run serially, as today.

### R1. Reader: chunks decoded in parallel, used in order (stage 5)

- `Source` gains `fn read_at_shared(&self, ...)` through a new
  `SharedSource: Source + Sync` trait, implemented for `FileSource` on
  Unix (`FileExt::read_exact_at`, which loops over short reads and
  does not move the file position, so `FileSource`'s own position
  bookkeeping stays right) and for `Bytes`. On Windows, `seek_read`
  moves the cursor, and no Windows CI job runs the core's tests, so
  Windows reads stay serial (`cfg(unix)`); Windows writes may still be
  parallel, as they touch no `Source`.
- A read goes parallel only if it is over the 16 MiB threshold, has no
  `budget`, and selects **no strL column**. strL payloads can be far
  larger than the 8-byte references the chunk size counts, so keeping
  them serial is what keeps the memory bound true; strL-heavy reads
  keep today's behaviour exactly.
- Chunks are 2 MiB of decoded output, numbered. Workers take the next
  number from a counter, read the rows and decode every selected
  column in selection order into their own `Vec<Column>`, then call
  `each(k, first, &Column) -> Result<bool>` for each column in order;
  `true` means the column was put where it belongs, `false` that the
  calling thread must handle it.
- The worker hands the chunk, with its first error if any, to the
  calling thread, which takes chunks strictly in row order and calls
  `rest(first, &[Column], &[bool])`. Chunk buffers go back to a free
  list.
- **Window**: at most `threads + 2` chunks are taken but not yet used
  by the caller; a worker waits on a condition variable before taking
  a number beyond it. Buffers are reused through a free list of at
  most `threads + 2` chunks, each allocated with capacity for one
  chunk's rows (decoded ≤ 2 MiB, raw ≤ 2 MiB, as `rows_per_chunk`
  sizes them) and never grown beyond it, because strL columns (whose
  payloads are uncounted) are excluded. So capacity in flight is at
  most `(threads + 2) × 4 MiB`, 24 MiB at 4 threads. A read whose
  decoded or raw row exceeds 2 MiB (a chunk of one row is then larger
  than the bound) runs serially.
- **Errors**: the caller handles chunks in row order. The serial path
  decodes every column of a chunk (source errors first) and then runs
  the binding's callback, which handles columns in order and stops at
  the first failure (or a native cancellation). To keep that order, a
  worker that fails decoding sends only that error; a worker whose
  `each` fails at column `j` stops calling `each` and sends the chunk
  with `upto = j` and the error. The caller then calls
  `rest(first, &[Column], &[bool] taken, upto)`, which handles the
  untaken columns before `upto` in order; if `rest` fails, its error
  (from an earlier column) is returned, else the worker's. `upto` is
  the column count when no `each` failed. Bindings whose `each` never
  takes a column (Julia's native ABI) see exactly today's callback,
  with today's cancellation. The caller returns a chunk's error only
  after `rest` has run for every earlier chunk. An error from a
  later chunk is never returned before an earlier chunk is used. On
  any error, or `rest` failing, the caller sets a stop flag and
  notifies the condition variable; workers finish their current chunk,
  see the flag and exit; the scope joins them before the call returns.
- **Interrupts**: the caller calls a `poll()` callback once per chunk
  before `rest` (as R does today) and between waits for a chunk, which
  time out every 100 ms. R checks Ctrl-C there; Python takes the GIL
  briefly and calls `check_signals`, keeping the `PyErr` to re-raise
  (as `read` keeps string errors today) and returning an error that
  stops the read.
- **Panics and early exits**: each worker holds a drop guard that, if
  the worker leaves without finishing (panic or error), records that
  its chunk failed, sets the stop flag and notifies the condition
  variable; the caller then sees the failed chunk (or the stop flag)
  instead of waiting for it, stops, and lets the scope join. The
  caller's own early returns (an error from `rest`, an interrupt) go
  through the same stop-and-notify guard, so no worker is left waiting
  on the window. A worker's panic is then re-raised by
  `thread::scope` after the join, and the bindings' existing
  `catch_unwind` guards turn it into an error. The caller's guard also
  runs during a panic on the caller (unwinding drops it), so workers
  waiting on the window are woken and exit before the scope joins
  them. No R or Python call
  happens in a worker, so nothing can `longjmp` across the scope. The
  parallel writer uses the same guards: a worker panic or a failing
  `write_all` on the caller sets the stop flag and wakes everyone
  waiting on a slab or a block swap.
- `read_chunks` keeps its signature and is the serial case (no
  workers; `each` never called).

Bindings, with what workers may touch:

- **R**: workers fill only numeric columns whose R kind is double
  (dtatools' Stata mode, and in plain mode doubles, floats, dates and
  date-times) through a pointer taken from `REAL` before the read.
  **Integer-kind columns (plain mode's byte, int and long, which may
  need promotion to double when `.a`–`.z` appear) return `false` and
  are filled in `rest` on the R thread, exactly as today**, so the
  promotion code is unchanged and no worker ever writes an integer
  vector. Strings go to `rest`. All R vectors are allocated and
  protected (reachable from `holder`) before the read starts and are
  not replaced while workers run; the only replacement (promotion) is
  of a vector workers never touch.
- **Python**: workers fill numeric arrays (allocated by `_read.py`,
  held by it for the call, not yet visible to other Python code) and
  the missing-code arrays. The per-column flag (largest code) is an
  `AtomicU8` updated with `fetch_max`. Strings go to `rest`, which
  takes the GIL as today. The GIL stays released during the read.
- **Julia (native C ABI)**: `each` returns `false`; the Julia callback
  gets every column of each chunk in order, as today. Julia gains the
  parallel read and decode.
- **wasm**: serial, unchanged.

Writers' inputs: the core borrows caller memory, as today, under the
contract each binding already states: the data must not change while
a write runs. R holds the R thread for the whole `.Call` (R code cannot
run; R's own memory is not touched by other threads). Python's
`write` already requires unchanged input (`python/src/lib.rs:277`);
holding the GIL stops Python code but not native threads, so the
contract stays a documented precondition, now also in `write_dta`'s
docstring. Julia's and C callers' buffers are covered by dta.h's
existing requirement (`native.rs:127`), restated there for parallel
writes. String access stays on the calling thread.

### R2. Decode tightening (stage 3)

Tried one at a time, each kept only if faster: test a double's or
float's high bits before computing a missing code (most values are not
missing); store the value without a NaN select when the code is 0.

## Tests

- **Byte identity with today's writer**: before any writer change, a
  test writes 30 seeded random datasets (every storage type, `.` to
  `.z`, empty and NUL-free strings, non-ASCII text, strN up to 2045,
  strLs with repeats, binary strLs, value labels, characteristics,
  sort order) with the current writer and records a 64-bit FNV hash of
  each file in the test. Every later stage must reproduce those hashes
  with 1 and with 4 threads (with a test-only small block and slab so
  tiny data uses many).
- **Reads**: each existing reader test also runs with 4 threads and a
  test-only 4 KiB chunk and threshold 0, comparing columns with the
  serial read, on every fixture (all releases, both byte orders, the
  legacy encodings), plus `budget` reads, which stay serial.
- **Panics and aborts**: a test-only hook panics a read worker on
  chunk k, and a write worker on slab k; the read callback (`rest`)
  panics with a full window; a write to a sink whose
  `write` fails after the first block, with workers mid-block. Each
  returns (error or propagated panic) without hanging.
- **Shared positional reads**: a test reads, through the shared path
  of a `FileSource`, every offset and length the serial path reads,
  and gets the same bytes and the same end-of-file error.
- **Error order**: writes with a bad value in column 3 and a bad name
  in column 5 (and the reverse); a bad value late in a numeric column
  and an invalid UTF-8 string earlier in a later column; same message
  with 1 and 4 threads. Reads: an `each` error in chunk 2 and a source
  read error in chunk 5 (a test `Source` that fails at that offset),
  with chunk 5 forced to finish first (a test hook delays chunk 2's
  worker): the chunk-2 error is returned; in one chunk, an `each`
  error at column 3 and a `rest` error at column 1 give the column-1
  error, and a `rest` error at column 4 gives the column-3 one; a
  native-ABI cancellation in a parallel read returns -2 as today; a `rest`
  error with a full window returns and joins without hanging.
- **R**: `save_dta` of packed plain, packed dictionary, partly made
  (cache partly filled), fully made, empty-string, non-ASCII and `NA`
  columns, each compared byte for byte with the file written from a
  plain character copy, and a foreign ALTREP column
  (`as.character(1:10)`, R's deferred strings) likewise; after writing,
    each column is in the state it was before (a made column made, a
  packed one packed); and a packed vector given as metadata (as the
  data frame's `notes`, and as a characteristic's values) is written
  correctly end to end through `save_dta`; and, because `save_dta`'s
  `enc2utf8()` may already replace such a vector, a direct test builds
  a spec by hand whose `notes` and characteristic values are packed
  vectors (checked packed with the state helper just before the call),
  calls the write entry point (`dtaparser:::C_dta_write`) with it, and
  checks the file's notes and characteristics read back and that those
  vectors are made afterwards
  (checked through a test helper that reports the ALTREP state). A
  plain-mode read of a file whose byte column has `.a` only in its last
  chunk, with 4 threads, gives the doubles and tags it gives serially.
- **Python, Julia, TypeScript**: their suites, and in CI the R, Python
  and Julia suites run once with `DTA_THREADS=4` and the thresholds
  lowered through a test-only variable.

## Measurement

- `bench/threads/`: a script per binding (R, Python, Julia) and a Rust
  example for the core, each timing one task in-process with wall time
  and CPU time of that task alone (R `system.time`, Python
  `time.process_time` and `resource.getrusage`, Julia `@timed` plus
  `getrusage` through `ccall`, Rust `getrusage` through a dev-only
  `libc` dependency), and peak RSS from `/usr/bin/time -l` in a fresh
  process. Five runs each, median, with 1, 2, 4 and 8 threads, on
  wide, long and groups for full reads, five columns and writes.
- The same Rust example runs in CI on x86 Linux on a 1.5 GB synthetic
  file it writes itself, printing wall and CPU per thread count, as the
  SMT check above.
- `bench/run.py --readers ours` on synthetic and NSFG before and after;
  RESULTS.md gains a "Fixed because of these runs" entry per stage with
  before and after numbers. The other readers are not re-run.

## Implementation notes

- Guards run while unwinding, so they must not panic: locks use
  `PoisonError::into_inner`. Workers run under `catch_unwind` so the
  binding reports the panic's message, not scope's generic one.
- Workers are spawned with `Builder::spawn_scoped`; if spawning fails
  (a pid limit), the work continues with the workers that started, or
  serially.
- "Threads" counts workers. For numeric-only reads the caller mostly
  waits; for string-heavy reads it works too. An invalid
  `DTA_THREADS` is ignored (default used); an explicit value is
  honoured up to `available_parallelism`.
- The parallel read entry point is `Reader::read_chunks_with`
  (`each`, `rest`, `poll`); `read_chunks` stays the serial wrapper.
- Python's `poll` takes the GIL at most every 100 ms, not per chunk.
- Workers see only the numeric block fills, as `&(dyn Fn + Sync)`;
  R and Python destinations cross as `Send`/`Sync` newtypes over
  pointers taken before the read. Workers call no R API (`REAL`,
  `INTEGER`, `STRING_ELT` can raise errors in R).
- Test knobs (chunk size, threshold, panic and delay hooks) are
  `#[doc(hidden)]` fields of the options so integration tests reach
  them; the bindings' test variable is `DTA_TEST_SMALL_CHUNKS=1`.
- Chunk string columns reserve their 2 MiB bound up front, so
  capacity does not double past it.
- Acceptance: a path that misses the wall-time target but meets the
  CPU and memory rules keeps its threads (it costs nothing); a stage is
  reverted only if no path keeps a count above 1.
- Windows reads are serial; docs say so.

## Not in this plan

- TypeScript streaming writes (writing without copying every column
  into module memory): needs host callbacks per block and changes the
  JS write API; its own plan.
- Parallel strL reads, and parallel fills for Julia's callback.
- `mmap`.
- Changing what any binding returns.
