# Manual fertility-survey differential corpus

This is a local, report-only compatibility framework for the private fertility
survey cache. It is never a CI or release gate. It refuses to run when common CI
or GitHub Actions variables are present and requires an explicit manual opt-in.
Release-111 files are passed through the same bounded differential readers as
the later supported releases. Historical published results retain their
`expected-unsupported-111` classifications as immutable evidence of the parser
support that existed when those runs were recorded.

Every Wave 2 invocation requires caller-supplied `--cache-root` and `--manifest`
arguments naming existing absolute canonical, non-symlink paths. The inventory
intentionally reproduces the authorized upstream inventory mapping rather than
recursively searching the cache. It reads exactly the supplied manifest, maps
underscores in non-WFS survey folder names to commas, maps women/birth records
to `wm.dta`/`bh.dta`, maps WFS to `<survey>.dta`, tries each program's primary
directory, and only for DHS tries `DHS/Original_Data_Provenance_Unknown`.
Neither source argument is inferred, globbed, or discovered from a checkout.

A valid inventory has exactly 1,004 unique files and these release counts:

| Release | Files | Differential status |
|---:|---:|---|
| 111 | 130 | supported Stata/SE 7 inputs |
| 113 | 475 | compared |
| 114 | 23 | compared |
| 117 | 150 | compared |
| 118 | 226 | compared |

Every file is SHA-512 hashed; a non-empty recorded signature must match, while
rows whose historical signature is empty are bound to the hash computed by the
checkpoint. The supplied manifest and its recorded hashes are external provenance
assertions: this repository binds inputs to them fail-closed but does not maintain,
warrant, or repair those external values. Supported files are never decoded into whole-file data frames. An
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
widths, a conservative per-object overhead, and three-reader cell and byte budgets.
For each `strL` batch, one isolated sizing child reads a fixed deterministic sample
of one-row windows, retains only the maximum aggregate payload-byte count, and
chooses a safety-factored row window bounded by the ordinary row/cell/memory caps.
If a rare larger payload makes a value child hit its enforced memory limit, that
range is split deterministically until it succeeds or reaches a one-row leaf;
failed parents and sizing children also count against the hard subprocess-tile
ceiling. Each child starts with `R_MAX_VSIZE` set to `--memory-mib` (minimum 128
MiB), making the memory budget an enforced vector-heap limit rather than only a
scheduling estimate. Memory-limit failures are reduced to a privacy-safe fixed
classification. Every metadata/value tile runs in its own timeout-isolated
subprocess and reads exactly
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
checkpoints and again after all tiles. For every supported file, the parent keeps a
verified source descriptor open; each isolated tile receives that descriptor and
first attempts a private target-local copy-on-write clone directly from it. If the
platform or filesystem cannot clone, the worker falls back to a private bounded-chunk
byte-for-byte copy from the already-open descriptor before any reader opens a pathname.
Source identity and cheap size/mtime fingerprints are revalidated around each child,
and snapshots are removed when the child exits. If neither descriptor-derived
materialization method succeeds, the run aborts before publishing a case result rather
than recording a reader crash.

## Wave 3 generated-output corpus

The same comparator, isolated workers, bounded tiles, checkpoints, sharding,
provenance, privacy filtering, and publication machinery also supports the
explicit generated-output root. This mode is enabled only by supplying the
exact authorized canonical absolute path. Set `OUTPUT_ROOT` to that private path;
the public documentation does not publish it:

```sh
benchmarks/fertility-surveys/benchmark.sh \
  --output-root="$OUTPUT_ROOT" --inventory-only
```

It recursively inventories regular files whose extension is `.dta` or `.DTA`,
including top-level aggregate files and nested survey files, and ignores every
other entry. Stable `F0001`-style IDs are assigned by bytewise-sorted canonical
relative path. The root and every ancestor directory are pinned through retained
no-follow directory descriptors; each DTA is opened relative to its pinned parent,
and device, inode, mode, size, modification time, and change time are revalidated
around descriptor-bound hashing and release reads. Relative paths and private file metadata are frozen only in a content-bound
artifact beneath the ignored private artifact root.
Public inventory manifests expose only the stable ID, `program=output`, the
privacy-safe `survey`/`aggregate` level, and DTA release. Public family manifests
add the deterministic `shard_index`.

The run refuses any other output root and asserts the observed baseline exactly:
1,226 files, 70,873,334,682 bytes, and a largest file of 10,332,252,930 bytes.
The observed output family supports releases 111, 113, 114, 115, and 118. Source files and the
upstream repository are read-only; all mutable state remains under the
checkout-local ignored target. Aggregate files are identified separately because
the upstream build uses forced Stata append coercion; that provenance explains
stored analytical types but never excuses a disagreement among Direct-R,
Rust-vector, and Haven.

Fresh generated-output execution and publication use corpus schema 13, which
binds each isolated worker to the descriptor identity captured during input
attestation. A transient pathname identity change is published with the canonical
`input-changed` reason and its tile checkpoint is replaceable under `--retry`, so
restoring the attested input cannot permanently poison resume. Corpus schema 10 is
retained only as the explicitly documented historical Wave 2 replay format; it is
not the identity of current Wave 3 evidence.

All normal filters, encoding overrides, resource bounds, resume, and shard
options apply. An unfiltered output run is recorded as a full family. Merge
validation requires exactly all 1,226 frozen IDs, the frozen release and
survey/aggregate distributions, and terminal outcomes with exact
completed-versus-expected tile accounting for every supported file. A `pass`
must also have `complete=TRUE`; an explicit
reader-error or divergence terminal may have `complete=FALSE` because that field
records all-reader projection success rather than whether every planned tile ran.
Timeout, memory, crash, unresolved, inventory-hash, or partial tile accounting
cannot pass the full-family gate. Merging an output family repeats the explicit
root:

```sh
benchmarks/fertility-surveys/benchmark.sh \
  --family-id=<family-id> \
  --output-root="$OUTPUT_ROOT"
```

## Run manually

From the checkout root:

```sh
export DTAPARSER_FERTILITY_CORPUS=I_UNDERSTAND_THIS_READS_PROPRIETARY_DATA
export CACHE_ROOT=/absolute/canonical/private-cache-root
export MANIFEST=/absolute/canonical/private-manifest.csv
benchmarks/fertility-surveys/benchmark.sh \
  --cache-root="$CACHE_ROOT" --manifest="$MANIFEST" --inventory-only
benchmarks/fertility-surveys/benchmark.sh \
  --cache-root="$CACHE_ROOT" --manifest="$MANIFEST" \
  --id=F0001 --timeout-seconds=120
benchmarks/fertility-surveys/benchmark.sh \
  --cache-root="$CACHE_ROOT" --manifest="$MANIFEST" \
  --id=F0574 --encoding-override=F0574:ISO-8859-1 --timeout-seconds=120
```

Inventory IDs are stable row numbers, not release selectors. To exercise the
unsupported classification without asking a reader to open a file, use:

```sh
benchmarks/fertility-surveys/benchmark.sh \
  --cache-root="$CACHE_ROOT" --manifest="$MANIFEST" \
  --release=111 --max-files=1 --timeout-seconds=120
```

A bounded supported-file smoke run can use another release and the same count
filter:

```sh
benchmarks/fertility-surveys/benchmark.sh \
  --cache-root="$CACHE_ROOT" --manifest="$MANIFEST" \
  --release=118 --max-files=1 --timeout-seconds=120
```

The exhaustive run is:

```sh
benchmarks/fertility-surveys/benchmark.sh \
  --cache-root="$CACHE_ROOT" --manifest="$MANIFEST"
```

## Explicit accepted-current-hash evidence for F0633-F0637

The historical SHA-512 values in `datasigs.csv` are caller-supplied external
provenance and are never rewritten. Reconciling or maintaining them is outside
this repository's parser-compatibility responsibility. If a separately authorized
local review accepts the current
bytes for exactly `F0633` through `F0637`, capture those bytes into a private,
immutable content-addressed commitment beneath the ignored artifact root:

```sh
commitment_id=$(
  benchmarks/fertility-surveys/benchmark.sh \
    --cache-root="$CACHE_ROOT" --manifest="$MANIFEST" \
    --capture-accepted-current-hashes
)
```

Capture requires the normal proprietary-data opt-in, is refused in CI and GitHub
Actions, rejects symlinked output ancestors, confines publication to the
canonical ignored artifact root, validates exactly five canonical 128-hex
SHA-512 values, and emits only the privacy-safe commitment ID. The private
artifact is not tracked and contains no source paths. It does not modify the
supplied manifest, cache root, or any existing checkpoint or report.

Run the separate accepted family only through the explicit CLI option. There is
no environment-variable fallback, and accepted execution rejects every selection
other than the exact unsharded five-ID family:

```sh
benchmarks/fertility-surveys/benchmark.sh \
  --cache-root="$CACHE_ROOT" --manifest="$MANIFEST" \
  --accepted-current-hashes="$commitment_id" \
  --id=F0633,F0634,F0635,F0636,F0637
```

The loader revalidates the immutable artifact, its authority and commitment
identity, the unchanged manifest signatures, and the current file bytes. The
same validation runs again before publication. The commitment authority, ID, and
artifact identity are bound into the accepted framework, configuration, input,
checkpoint, family, selection, evidence, and report-bundle identities. The
original `expected_sha512` remains unchanged and its status remains
`signature-mismatch`; accepted execution records a separate
`accepted-current-sha512-match` local-evidence status and never describes the
manifest as verified.

Merge the resulting separate five-ID family normally:

```sh
benchmarks/fertility-surveys/benchmark.sh \
  --cache-root="$CACHE_ROOT" --manifest="$MANIFEST" \
  --family-id=<accepted-family-id>
```

Merge validation requires exactly one shard, exactly `F0633`-`F0637`, consistent
acceptance provenance, and executable outcomes for all five. Immediately before
publication it rebuilds the live canonical inventory, reloads the exact immutable
artifact, verifies its recorded SHA-256 identity, and revalidates all five current
files. It cannot merge the accepted evidence into the original 1,004-file family.
After both families have been merged, publish a separate derived assessment:

```sh
benchmarks/fertility-surveys/benchmark.sh \
  --cache-root="$CACHE_ROOT" --manifest="$MANIFEST" \
  --assessment-family-id=<original-full-family-id> \
  --accepted-family-id=<accepted-five-family-id>
```

The assessment consumes and strictly revalidates each family's explicitly
selected private merged bundle. The accepted family must use the complete current five-file merged schema,
including its aggregate input attestation and acceptance authority. Only the
original/base role has a compatibility path for the immutable four-file
schema-10/report-schema-2 fresh full-family bundle: it requires exactly 8 shards,
1,004 canonical files, the exact legacy provenance and file schemas, the live
inventory and current report-schema-2 framework snapshot, and recomputes the
schema-2 evidence-family identity. It does not synthesize the absent attestation
table or permit this format for accepted evidence. A privacy-safe identity over
the exact legacy provenance and public content IDs is bound into the assessment
identity and revalidated at both publication boundaries. Merge and republication
remain current-schema-only. The assessment preserves both source identities and
classifications, requires the original full family to retain
`inventory-hash-error` for exactly `F0633`-`F0637` with the sole privacy-safe
reason `signature-mismatch`, and exposes two historically named orthogonal status
fields: `manifest_gate=blocked-signature-mismatch` and
`explicit_local_evidence_gate=validated`. The first records only the unresolved
caller-supplied external provenance assertion; it is not a dtaparser parser gate
or repository responsibility. The assessment does not rewrite either family or
authorize Wave 3.

## Historical schema-10 validation and republication

The complete eight-shard run from framework
`6f0e40d786d054ec2cb924c74dabb67b66bb0d079f01147294c48187565a6488`
can be revalidated from its private schema-10 result and tile checkpoints without
opening any DTA input or launching a reader. Validation-only performs every build,
framework, configuration, inventory, input-attestation, checkpoint, aggregation,
privacy, and public-schema check, but does not stage or publish reports:

```sh
benchmarks/fertility-surveys/benchmark.sh \
  --cache-root="$CACHE_ROOT" --manifest="$MANIFEST" \
  --republish-framework=6f0e40d786d054ec2cb924c74dabb67b66bb0d079f01147294c48187565a6488 \
  --validate-only --shard-count=8 --chunk-rows=50000 --column-batch=32 \
  --memory-mib=1024 --cell-budget=10000000 --max-tiles-per-batch=100000 \
  --beyond-end-windows=1 --timeout-seconds=600
```

Remove `--validate-only` to atomically publish all eight replay-derived shard
bundles. Republication requires exactly eight shards and the exact recorded
configuration. It records `historical-schema-10-replay` evidence provenance and a
privacy-safe aggregate input-attestation ID; individual expected or actual hashes
remain private. Only the exact schema-10 `-reader-error` artifact caused by the
empty-reader `paste0()` bug is discarded, and only in this historical replay path.
Current execution and normal checkpoint resume reject that artifact.

All shard bundles are validated and staged before publication. Bundle renames and
private pointer updates form one rollback-checked transaction: a staging, rename,
or pointer failure restores every prior selection and removes every new bundle, while
a failed rollback is reported rather than treated as success. Historical replay
validates and republishes historical evidence; it is not a substitute for the
mandatory final exhaustive fresh run with the corrected worker.

Do not run it casually. The default timeout is 600 seconds per metadata/value
tile. Available options are:

- `--cache-root=/absolute/canonical/path` and
  `--manifest=/absolute/canonical/file.csv` (both required in raw mode and
  rejected in generated-output mode)
- `--output-root=/absolute/canonical/path` (required in generated-output mode
  and rejected with raw root arguments)
- `--inventory-only`
- `--capture-accepted-current-hashes` (publish the separately authorized private
  five-file commitment described above)
- `--family-id=ID` (merge a completed shard family)
- `--assessment-family-id=ID --accepted-family-id=ID` (publish the Wave 2
  raw-plus-supplemental assessment; both are required together)
- `--republish-framework=ID` (historical validation/republication mode)
- `--validate-only` (validate historical evidence without publishing it)
- `--program=dhs,mics` (comma-separated)
- `--release=113,118` (comma-separated)
- `--id=F0001,F0002` (privacy-safe inventory IDs)
- `--encoding-override=F0001:ENCODING` (repeatable or comma-separated;
  canonical encodings are `UTF-8`, `Windows-1252`, and `ISO-8859-1`;
  aliases include `UTF8`, `CP1252`, and `latin1`)
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
- `--accepted-current-hashes=ID` (explicit private commitment; valid only with
  the exact unsharded `F0633`-`F0637` selection)
- `--retry` (rerun failed tiles only; completed matches and mismatches resume)

Encoding overrides are explicit run configuration, never tracked corpus-specific
policy. Every override ID must belong to the complete selected family, and every
shard in that family must receive the same sorted canonical map. The selected
encoding is passed symmetrically to public direct-R materialization, internal
Rust-vector materialization, Haven, structural name discovery, value and terminal
windows, and `strL` sizing samples. The canonical privacy-safe map is recorded in
run provenance and bound into the configuration and family identities. Changing
it therefore selects a different checkpoint namespace; omitting it preserves the
legacy configuration identity and reader defaults. Historical schema-10 replay
rejects encoding overrides because replay must retain its exact recorded
configuration.

The orchestrator builds the current checkout package into an immutable,
provenance-addressed generation beneath the ignored private artifact root.
A short owner-aware build lock covers installation, SHA-256 package/dependency
provenance, and framework snapshot preparation, then is released before corpus
execution. Concurrent starters wait for that setup and reuse the same verified
generation rather than replacing a live shard's library. Before any corpus item is
processed, exact production callr regressions exercise both metadata and `strL`
sizing through the target-local temporary directory and immutable snapshot; they
also prove comparator helpers remain confined to the callback lexical environment.

Each active shard then acquires its own selection lock plus sorted per-case locks.
Disjoint deterministic shards run concurrently and share atomic per-case
checkpoints, while any overlapping active selection is rejected. The lock and
per-run temporary directory publish the orchestrating shell's PID, host, and
OS-verified process-start generation as their authoritative owner. A separate
long-lived helper refreshes a supplemental heartbeat while monitoring that exact
shell generation. Matching local PID/start identity or a fresh matching remote
heartbeat preserves ownership; confirmed owner death or a live PID with a
different start generation permits recovery. Permission-denied or unavailable
process probes are indeterminate rather than dead and use conservative
heartbeat/stale-age handling. Build staging lives inside the owner-tracked private
run directory, so abandoned setup is reclaimed without touching another live
shard. Workers source the immutable provenance-addressed script snapshot, and all
source, dependency, installed-package, inventory, and framework provenance is
recomputed before report publication.

Each file has private atomic metadata, tile, and aggregate RDS checkpoints bound
to the checkpoint schema, framework/package provenance, `datasigs.csv`, inventory
ID/release/signature, full input identity, exact tile projection/window, and a
stable configuration ID. The configuration includes timeout, row cap, column
batch, memory budget, cell budget, reader count, object overhead, probe count, and
tile ceiling, so changing any sizing/resource limit cannot silently reuse foreign
tiles. Timeout, memory-limit, crash, reader-error, and independent
`structural-metadata-unavailable` tiles are resumable and are rerun only with
`--retry`;
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

Each filter/shard selection publishes a complete immutable, content-bound private
report bundle and atomically updates only that selection's private pointer, so
smoke runs and separate shards do not overwrite one another.
Results carry framework, configuration, inventory, family, and build provenance
IDs. After every shard in a family completes, merge its privacy-safe reports with:

```sh
benchmarks/fertility-surveys/benchmark.sh \
  --cache-root="$CACHE_ROOT" --manifest="$MANIFEST" \
  --family-id=<family-id>
```

Prepare publishes a privacy-safe canonical inventory manifest inside the immutable
framework snapshot. Every shard report carries the complete canonical family
manifest, including deterministic shard ownership, and binds it by SHA-256-derived
identity to its family provenance. The merge reconstructs the family from the
snapshot plus the strictly parsed filter specification and requires exact manifest,
per-shard, and union membership and ordering. It also requires exactly one report
for every shard index and identical framework/configuration/build/inventory/report
schema provenance. An unfiltered family must contain exactly `F0001` through
`F1004`, preserve release counts 111=130, 113=475, 114=23, 117=150, and 118=226,
account for exactly five inventory hash errors plus 999 supported executable
outcomes. Validation
finishes before any merged output is staged or published; publication is atomic within the ignored private artifact root.

All generated files, package builds, checkpoints, and reports stay below an
ignored checkout-local private artifact root. Public result TSVs use one exact,
versioned schema and reject missing, reordered, or unexpected columns before
publication. They contain only privacy-safe IDs, program/level/release, shapes,
timings, fixed categories, and hashed mismatch signatures.
They never contain source paths, survey names, labels, values, or reader error
text. Subprocess failures are reduced to fixed classifications for the same
reason. `inventory-hash-error` reports only a fixed privacy-safe reason
(`hash-read-error`, `signature-mismatch`, or `input-changed`); a nonempty recorded
signature mismatch is never silently treated like an intentionally empty
historical signature. Before any parent R or callr process starts, the shell creates a private
per-run temporary directory beneath the ignored artifact root; parent and child
R processes verify their canonical `tempdir()` remains confined there, and
abandoned temporary directories are safely reclaimed. The shell uses a restrictive umask and the R
writers enforce private artifact permissions. Do not copy RDS checkpoints
outside the private target
directory because they contain input signatures.

## Privacy-safe mismatch adjudication

Raw differential evidence remains immutable and is never normalized, hidden, or
rewritten to match one reader. Adjudication should be a separate derived process:

1. Group raw results by the existing public mismatch signature and fixed reader-pair
   identity, retaining the raw file and comparison counts for every cluster.
2. Select one or more privacy-safe inventory IDs per cluster for an explicitly
   authorized, target-local attribute-only diagnostic.
3. Record only fixed categories such as variable label, value-label mapping, class,
   format, or character-decoding policy; direct-versus-Rust agreement; a fixed owner
   category; the explicit encoding modes tested; and the source raw signature.
4. Require a second review before marking a cluster intentional. The derived record
   may explain or reclassify a confirmed divergence, but it must continue to link to
   the unchanged raw signature and counts.
5. Keep diagnostic paths, names, labels, values, error text, and source hashes out of
   both the derived artifact and public reports. Store any private working material
   only under the ignored target-local raw directory and remove it after review.

This process can adjudicate the observed public signature clusters incrementally
without rereading the complete corpus or changing the public result schema.

## Deterministic tests

The synthetic framework tests create only temporary fake headers and synthetic
R values; they do not read the private corpus:

```sh
Rscript --vanilla benchmarks/fertility-surveys/test-framework.R
```

They cover exact non-recursive inventory mapping, release parsing, privacy-safe
inventory projection, argument validation, deterministic disjoint filtering and
sharding, concurrent selection/case ownership, empty shards, strict merge
accounting, width-aware batches, fixed-width and `strL` structural metadata,
bounded deterministic `strL` payload sampling, practical small-payload tile
counts, rare-large-payload recursive splitting, hard execution ceilings, gap-free
coverage, and sizing/value checkpoint resume. They also cover nonterminating-reader
bounds, enforced memory-limit attribution, metadata/zero-column contracts,
continued traversal after early mismatches, timeout retry, schema/input/config
invalidation, exhaustive metadata/value/tag/date/encoding categories and numeric
outliers, absence of unbounded supported-file reads, atomic publication, immutable
SHA-256 build/dependency provenance, live and remote owner recovery, nested
parent-R/callr temp confinement, release-111 handling, signature refusal,
structural-metadata retry, accepted-hash parsing and exact selection, private
artifact/input invalidation, identity isolation, strict accepted-family merge,
derived dual-gate assessment, and CI/manual opt-in refusal.
