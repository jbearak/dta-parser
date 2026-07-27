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
checkpoint. For each supported file, one isolated R subprocess reads the complete
file through `dtaparser::read_dta()`, requires exact
identity with `dtaparser:::.read_dta_rust_vectors()`, then compares the complete
result with `haven::read_dta()`. Haven comparison checks dimensions, names,
data-frame and column attributes, storage types, missing positions and kinds,
tagged missing values, exact non-floating and nonfinite values, and an exhaustive
elementwise absolute tolerance of `1e-7` for finite floating values. Inputs are
hashed by the parent before launch, independently in the child, again after the
child exits, and once more before report publication.

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

Do not run it casually. The default timeout is 600 seconds per file. Available
options are:

- `--inventory-only`
- `--program=dhs,mics` (comma-separated)
- `--release=113,118` (comma-separated)
- `--id=F0001,F0002` (privacy-safe inventory IDs)
- `--shard-index=N --shard-count=N` (both required; one-based)
- `--max-files=N`
- `--timeout-seconds=N`
- `--retry` (rerun only prior failures; matches and unsupported releases resume)

The orchestrator builds the current checkout package and installs it beneath
`target/fertility-surveys/raw/library/`. Build provenance binds the commit,
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

Each file has an atomic RDS checkpoint bound to the checkpoint schema, framework
and package provenance, `datasigs.csv`, inventory ID, release, expected signature,
and a parent-captured input identity containing the actual SHA-512 or a stable
hash-error fingerprint. Checkpoint compatibility also includes the requested
per-file timeout, so changing `--timeout-seconds` cannot silently reuse a result
created under a different limit. Current identities are rechecked after each
child, before resume, and before publication. This makes timeout,
subprocess-error, and input-hash-error checkpoints publishable and resumable.
`--retry` reruns those failures; without it they resume like other completed
checkpoints. Filters and shards do not alter checkpoint identity.

Each filter/shard selection publishes a complete immutable report bundle beneath
`raw/reports/<selection-id>/` and atomically updates only that selection's
`CURRENT` pointer, so smoke runs and separate shards do not overwrite one another.
Results carry framework and build provenance IDs.

All generated files, package builds, checkpoints, and reports stay below the
ignored `target/fertility-surveys/raw/` directory. Public TSVs contain only
privacy-safe IDs, program/level/release, shapes, timings, and classifications.
They never contain source paths, survey names, labels, values, or reader error
text. Subprocess failures are reduced to fixed classifications for the same
reason. Before any parent R or callr process starts, the shell creates a private
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
inventory projection, argument validation, filtering, sharding, retry/checkpoint
invalidation, atomic publication, timeout publication/resume/retry, parent input
identity and timeout compatibility, live-owner lock/temp preservation followed
by dead-owner recovery, dependency relocation/modification invalidation, nested
parent-R/callr temporary-directory confinement including live callr control and
serialization artifacts, semantic mismatch classifications and numeric outliers,
release-111 handling, signature refusal, and CI/manual opt-in refusal.
