## Findings

On the 36 public-use NSFG files and the 10 DHS files, ours is faster than
every other reader in its language at reading whole files, at the pass
over every value, at five columns and at a 1,000-row window, taking the
geometric mean over the files (the exceptions on single files are under
"Targets missed"). The other readers' time over ours:

| language | full read (NSFG, DHS) | read + pass (NSFG, DHS) |
|---|---|---|
| R | haven 13×, 22×; readstata13 14×, 25× | haven 6.8×, 12×; readstata13 7.5×, 13× |
| Python | pandas 1.6×, 1.7×; pyreadstat 8.4×, 9.5× | pandas 1.3×, 1.5×; pyreadstat 8.4×, 12× |
| Julia | ReadStatTables 7.4×, 7.4×; StatFiles about 1,300×, 5,700× | ReadStatTables 5.6×, 5.3× |
| TypeScript | statfmt 14×, 13× | statfmt 8.1×, 8.9× |

The margin is narrowest in Python, where pandas' reader is NumPy code too,
and in R's pass over every value, where dtatools makes its packed
strings into R strings (ADR 0010). Metadata alone is where the others
come closest: readstata13 (which here reads one row) and ReadStatTables
are as fast or faster on the smaller files, by fractions of a
millisecond.

### Fixed because of these runs

Each fix is its own commit, with a test where the behaviour can be
tested (1 to 5). Ours was then measured again with `--readers ours`;
the other readers' results were not re-run.

1. **Python, `attrs`** (`python/dta_parser/_read.py`). pandas deep-copies
   `attrs` into every column and frame it derives, and ours kept the
   file's metadata there, so each `df[c]` on a 3,000-variable file cost
   about 5 ms. `attrs["dta"]` is now shared by derived frames (docs/python.md
   says how to give one its own). 2017_2019_Male: the pass over every
   value 14.06 s → 0.14 s (pandas 0.24 s), `write_dta` 13.74 s → 0.20 s
   (pandas 0.51 s).
2. **Julia, first calls** (`julia/DtaParser/src/precompile.jl`,
   `read.jl`, `json.jl`). A session's first call compiled the read
   path: `read_meta` took 0.12 s on long.dta (ReadStatTables 0.006 s), a
   1,000-row window 0.50 s (0.18 s). A precompile workload over every
   storage type, and metadata built in typed loops: 0.0015 s and 0.022 s.
   `read_meta` on 1973_FemResp, warm: 2.6 ms → 1.4 ms.
3. **TypeScript, writing** (`js/src/index.ts`). Writing what
   `readColumns` returned meant an array of numbers and `Missing` values
   per column, and a `Uint8Array` per string. A variable may now give its
   `Float64Array` and missing codes, and strings are encoded into one
   buffer. long.dta: 10.2 s and 9.3 GB → 3.5 s and 3.4 GB (statfmt
   18.8 s); 2002_FemPreg: 289 MB → 195 MB (statfmt 187 MB).
4. **Core, chunk size** (`crates/dta/src/reader.rs`). Chunks were 8 MiB
   of rows, but a byte decodes to 9 bytes, so files of byte variables
   held 72 MiB decoded per chunk. Chunks are now 8 MiB decoded. With the
   next fix, peak memory of a full read of 2015_2017_Male: Python
   390 MB → 198 MB (pandas 249 MB), R 365 MB → 255 MB (readstata13
   229 MB), TypeScript 573 MB → 418 MB with fix 7 (statfmt 325 MB).
5. **Python, string cache** (`python/src/lib.rs`). Every column got a
   32 KiB cache of recent strings, numeric or not: 100 MB on that file.
   It is now made on a column's first string.
6. **Core, column room** (`crates/dta/src/reader.rs`). Decoded columns
   grew by doubling; they now reserve a chunk's rows. Python's native
   read: 1976_Preg 7.0 → 4.8 ms, 2015_2017_Male 42.5 → 33.8 ms.
7. **wasm, read buffers** (`crates/dta-ffi/src/wasm.rs`). Appending
   chunks regrew the columns in module memory, which never shrinks; a
   read now reserves its rows.
8. **The harness, not the package**: haven loads tibble and vctrs with
   itself, dtatools on its first read, so 0.08 s fell inside dtatools'
   timed tasks only. Both now load them before the clock.

### Targets missed, and why

- **Julia metadata on small files** (35 files, by 0.01 to 0.1 ms). The
  metadata crosses the C ABI as JSON (the plan's design) and is parsed
  in Julia; ReadStatTables fills its structures directly. Two
  optimisation attempts (fix 2) narrowed it; the rest is that JSON.
- **R metadata and windows on small files** (by 0.02 to 0.2 ms).
  dtatools builds a tibble with per-column attributes; readstata13's
  "metadata" here is a one-row read without them.
- **Python, read + pass on four pregnancy files** (by 10–20%). Ours
  gives byte and int columns with `.` as float32 (the plan's
  representation); the pass sums in float64, so each converts, where
  pandas' columns are already float64.
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
- **Julia, writing groups.dta**: 1.5 GB against ReadStatTables' 1.0 GB;
  the C ABI takes every string column as one byte buffer with offsets,
  a copy of 15M strings.

### What the correctness checks found

- **Values agree everywhere**: every full read, five-column read, window
  and checksum of every reader equals ours, on every file where both
  ran (missing codes too, where haven keeps `.a`–`.z`).
- **Labels with trailing spaces**: haven, pyreadstat, ReadStatTables and
  statfmt (all ReadStat-based) drop trailing spaces from variable and
  value labels; ours, readstata13 and pandas keep the file's text. This
  is every metadata "difference" on NSFG and most on DHS.
- **Windows-1252 text before release 118**: pandas decodes it as
  Latin-1, so a curly apostrophe (byte 0x92) becomes a control
  character in one DHS label per file pair; ours, pyreadstat and
  readstata13 decode it as Windows-1252.
- **Writers**: ours writes back values and metadata that the
  open-source readers read as they read the source, in all four
  languages, except where that reader misreads the source (the pandas
  case above). readstata13's writer drops the data label and display
  formats, pandas' and pyreadstat's change storage types and formats,
  ReadStatTables' changes some labels and value labels on DHS files (not
  investigated further), and pyreadstat cannot write back 30 of the 36
  NSFG frames it read (all-missing numeric columns arrive as objects).
- **Readers that could not finish**: StatFiles takes 5–15 minutes per
  DHS women's file and over a minute on most NSFG files, so tasks 3
  and 4 were not repeated there; it has no metadata read or writer.
  statfmt's write of wide.dta failed in the harness, not in statfmt:
  it wrote the 4.8 GB result with one `fs.writeFileSync`, which Node
  limits to 2 GiB. The harness now writes it in pieces; the measurement
  was not repeated, since the other readers' results are not re-run.

The earlier R-only measurements (writing from R, survey-shaped string
columns, grouping) are in [results/r-only.md](results/r-only.md).
