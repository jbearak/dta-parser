# Manual fertility-survey differential corpus

This is a local, report-only compatibility framework for the private fertility
survey cache. It is never a CI or release gate. It refuses to run when common CI
or GitHub Actions variables are present and requires an explicit manual opt-in.
It does not add Stata release 111 support: release-111 files are inventoried and
classified as `unsupported-release` without being passed to a reader.

The inventory intentionally reproduces `~/repos/fertility_surveys/check_raw_data.r`
path construction rather than recursively searching the cache. It reads exactly
`~/repos/fertility_surveys/datasigs.csv`, maps underscores in non-WFS survey
folder names to commas, maps women/birth records to `wm.dta`/`bh.dta`, maps WFS
to `<survey>.dta`, tries the program's primary directory, and only for DHS tries
`DHS/Original_Data_Provenance_Unknown`. The cache root is exactly
`/opt/aww_cache`; neither path can be overridden by command-line options.

A valid inventory has exactly 1,004 unique files and these release counts:

| Release | Files | Differential status |
|---:|---:|---|
| 111 | 130 | inventoried, unsupported |
| 113 | 475 | compared |
| 114 | 23 | compared |
| 117 | 150 | compared |
| 118 | 226 | compared |

Every file is SHA-512 hashed; a non-empty recorded signature must match, while
rows whose historical signature is empty are bound to the hash computed by the
checkpoint. Supported files are never decoded into whole-file data frames. An
isolated metadata subprocess compares zero-row direct-R, internal Rust-vector,
and haven frames, including dataset label/notes and every column's class, label,
`format.stata`, value labels, and `tzone`. A bounded source-header parser
independently obtains the declared observation count, column count, fixed-string
widths (including `str2045`), and `strL` identity without decoding values.
Direct-R and Rust-vector zero-column shape reads are checked against that count;
the installed haven rejects an empty projection. Normal traversal is bound to the
source count. The first column batch then receives only a configured small number
of deterministic beyond-end windows (default one, hard maximum eight). Any reader
that still returns rows is classified `row-termination-mismatch`; it never extends
traversal. A hard per-batch tile ceiling likewise produces `unresolved` rather
than an open-ended loop. Haven participates in zero-row metadata comparison,
beyond-end verification, and every value tile.

Columns remain in source order. `--column-batch` bounds their count, while `strL`
columns are always isolated. Row sizing uses numeric bytes, exact fixed-string
widths, a conservative per-object overhead, three-reader cell and byte budgets,
and returns a one-row window for every `strL` batch. Each child also starts with
`R_MAX_VSIZE` set to `--memory-mib` (minimum 128 MiB), making the memory budget an
enforced vector-heap limit rather than only a scheduling estimate. Memory-limit
failures are reduced to a privacy-safe fixed classification. Every metadata/value
tile runs in its own timeout-isolated subprocess and reads exactly
that projection/window through `dtaparser::read_dta()`,
`dtaparser:::.read_dta_rust_vectors()`, and `haven::read_dta()`.

Comparison evaluates every available direct-R/Rust, direct-R/haven, and
Rust/haven pair and accumulates every mismatch rather than returning at the first
one. It checks dimensions, the overlapping common row prefix even when dimensions
differ, names, dataset/column attributes, storage types, missing
positions and NA/NaN kinds, tagged missing values, Date/POSIXct/tzone semantics,
exact strings and integers, exact Date/POSIXct unclassed values and nonfinite
values, and every ordinary finite floating value with absolute tolerance `1e-7`.
Mismatches do not stop later tiles. Public
reports contain only fixed categories, counts, and hashed signatures; values,
labels, names, paths, and reader messages remain private. Each reader also emits
an ordered, framework-salted projection hash and count for every value and
terminal tile. The worker compares returned names/order to the requested batch in
memory, and completeness requires matching attestations from all three readers;
raw variable names are never stored in these attestations or published. A
supported file can be classified `pass` only after exact gap-free coverage of
every expected row and column batch plus exactly the configured terminal probes:
batch 1, one-row windows at contiguous offsets beginning at the structural row
count, with zero rows returned and valid three-reader projection attestations.
Zero-column supported files use a single explicit empty projection batch and the
same traversal and terminal requirements. Inputs are fully hashed before accepting
checkpoints and again after
all tiles; cheap size/mtime fingerprints detect changes around each child.

## Run manually

From the checkout root:

```sh
export DTAPARSER_FERTILITY_CORPUS=I_UNDERSTAND_THIS_READS_PROPRIETARY_DATA
benchmarks/fertility-surveys/benchmark.sh --inventory-only
benchmarks/fertility-surveys/benchmark.sh --id=F0001 --timeout-seconds=120
```

Inventory IDs are stable row numbers, not release selectors. To exercise the
unsupported classification without asking a reader to open a file, use:

```sh
benchmarks/fertility-surveys/benchmark.sh --release=111 --max-files=1 --timeout-seconds=120
```

A bounded supported-file smoke run can use another release and the same count
filter:

```sh
benchmarks/fertility-surveys/benchmark.sh --release=118 --max-files=1 --timeout-seconds=120
```

The exhaustive run is:

```sh
benchmarks/fertility-surveys/benchmark.sh
```

Do not run it casually. The default timeout is 600 seconds per metadata/value
tile. Available options are:

- `--inventory-only`
- `--program=dhs,mics` (comma-separated)
- `--release=113,118` (comma-separated)
- `--id=F0001,F0002` (privacy-safe inventory IDs)
- `--shard-index=N --shard-count=N` (both required; one-based)
- `--max-files=N`
- `--timeout-seconds=N`
- `--chunk-rows=N` (hard row-window cap; default 10,000)
- `--column-batch=N` (maximum columns per batch; default 16; `strL` is isolated)
- `--memory-mib=N` (sizing budget and enforced child vector limit; default 256,
  minimum 128)
- `--cell-budget=N` (cells across all three readers; default 1,000,000)
- `--max-tiles-per-batch=N` (hard traversal ceiling; default 100,000)
- `--beyond-end-windows=N` (terminal verification windows; default 1, maximum 8)
- `--retry` (rerun failed tiles only; completed matches and mismatches resume)

The orchestrator builds the current checkout package and installs it beneath
`target/fertility-surveys/raw/library/`. Before any corpus item is processed it
must pass a synthetic metadata regression through the exact production callr
callback, target-local temporary directory, and immutable framework snapshot; the
regression also proves comparator helpers remain confined to the callback lexical
environment. Build provenance binds the commit,
scoped dirty state, package and framework source digests, source tarball, and the
installed package. Every runtime dependency is bound by version, canonical
installed path, canonical loaded-namespace path, and deterministic installed-tree
digest. A valid existing installation is reused so checkpoints can resume;
source, dependency, or installation changes force a rebuild and a new framework
identity. The private run lock and per-run temporary directory publish the
orchestrating shell's PID, host, and OS-verified process-start generation as their
authoritative owner. A separate long-lived helper refreshes only a supplemental
heartbeat while monitoring that exact shell generation. Matching live PID/start
identity remains authoritative if heartbeat updates are delayed or the helper
itself dies; confirmed owner death or a live PID with a different start generation
permits recovery regardless of helper state. Permission-denied or unavailable
process probes are indeterminate rather than dead and use conservative
heartbeat/stale-age handling, never immediate reclamation. This prevents another
invocation from replacing the installation
mid-run while permitting safe recovery after an owner dies or initialization is
abandoned. Workers source an immutable provenance-addressed
script snapshot, and all provenance is recomputed before report publication.

Each file has private atomic metadata, tile, and aggregate RDS checkpoints bound
to the checkpoint schema, framework/package provenance, `datasigs.csv`, inventory
ID/release/signature, full input identity, exact tile projection/window, and a
stable configuration ID. The configuration includes timeout, row cap, column
batch, memory budget, cell budget, reader count, object overhead, probe count, and
tile ceiling, so changing any sizing/resource limit cannot silently reuse foreign
tiles. Timeout, memory-limit, crash, and reader-error tiles are resumable and are
rerun only with `--retry`;
completed semantic mismatches remain valid evidence. Filters and shards do not
alter tile identity.

File-level classifications include `pass`, `expected-unsupported-111`,
`inventory-hash-error`, `direct-vs-rust-mismatch`, `dtaparser-only-error`,
`haven-only-error`, `shared-reader-error`, `metadata-mismatch`, `value-mismatch`,
`tag-mismatch`, `date-mismatch`, `encoding-mismatch`,
`row-termination-mismatch`, `known-intentional-divergence`, `timeout`,
`memory-limit`, `crash`, and `unresolved`. Detailed
secondary fixed categories and hashed mismatch signatures are retained without
publishing source metadata or values.

Each filter/shard selection publishes a complete immutable report bundle beneath
`raw/reports/<selection-id>/` and atomically updates only that selection's
`CURRENT` pointer, so smoke runs and separate shards do not overwrite one another.
Results carry framework and build provenance IDs.

All generated files, package builds, checkpoints, and reports stay below the
ignored `target/fertility-surveys/raw/` directory. Public TSVs contain only
privacy-safe IDs, program/level/release, shapes, timings, and classifications.
They never contain source paths, survey names, labels, values, or reader error
text. Subprocess failures are reduced to fixed classifications for the same
reason. `inventory-hash-error` reports only a fixed privacy-safe reason
(`hash-read-error`, `signature-mismatch`, or `input-changed`); a nonempty recorded
signature mismatch is never silently treated like an intentionally empty
historical signature. Before any parent R or callr process starts, the shell creates a private
per-run `TMPDIR` beneath `raw/tmp/`; parent and child R processes verify their
canonical `tempdir()` remains beneath the raw root, and abandoned run temp
directories are safely reclaimed. The shell uses a restrictive umask and the R
writers enforce private artifact permissions. Do not copy RDS checkpoints
outside the private target
directory because they contain input signatures.

## Deterministic tests

The synthetic framework tests create only temporary fake headers and synthetic
R values; they do not read the private corpus:

```sh
Rscript --vanilla benchmarks/fertility-surveys/test-framework.R
```

They cover exact non-recursive inventory mapping, release parsing, privacy-safe
inventory projection, argument validation, filtering/sharding, deterministic
width-aware batches and adaptive row sizing, fixed-width and `strL` structural
metadata, nonterminating-reader and tile-ceiling bounds, enforced memory-limit
attribution, metadata/zero-column contracts, multi-tile gap-free coverage,
continued traversal after early mismatches,
tile-level timeout resume/retry, schema/input/config invalidation, exhaustive
metadata/value/tag/date/encoding categories and numeric outliers, absence of
unbounded supported-file reads, atomic publication, parent input identity, live
owner recovery, dependency provenance, nested parent-R/callr temp confinement,
release-111 handling, signature refusal, and CI/manual opt-in refusal.
