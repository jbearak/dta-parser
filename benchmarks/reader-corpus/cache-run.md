# Survey-cache `read_dta()` rerun

`cache-run.py` measures the current `read_dta()` on every regular file with a
case-insensitive `.dta` suffix within the DHS, MICS, NSFG, ENADID and WFS roots
beneath the supplied cache root. Only those five survey roots are included,
and all must be present as ordinary directories. Each file has
one fresh-process attempt with `output = "tibble"` and one with
`output = "dibble"`, both using `threads = 0L` and default numeric ALTREP.
The runner invokes neither haven nor Stata and does not convert or read Arrow
files. Separate Stata-oracle work, when used, must finish before this runner's
qualification and measurement phases.

The October 1, 2026 survey inventory contains 1,881 files totaling 57,114,293,618
bytes:

| Corpus | Files |
| --- | ---: |
| DHS | 643 |
| MICS | 951 |
| NSFG | 229 |
| ENADID | 17 |
| WFS | 41 |
| Total | 1,881 |

File and directory symlinks are excluded. The two directory symlinks in this
inventory are MICS aliases to directories already included, so following them
would duplicate physical files. The private inventory records their paths and
the selection policy. The run records the alias count. The required
`--expected-files` count catches an initially incomplete cache; a complete
recursive inventory comparison before and after execution catches later
additions, removals or metadata changes.

## Build and qualify

Use independently installed baseline and candidate libraries produced by the
[acceptance build wrapper](../r-file-readers/README.md#build-and-bind-acceptance-libraries).
The commands below name each wrapper's work directory, which contains
`library/`, preserved source snapshots and `build-receipt.json`.
The runner verifies those receipts, complete installed-file inventories,
source hashes and replayable patches. It does not accept an unbound library.

Keep all output in a new private directory outside Git. After other heavy
work has finished, qualify the complete inventory:

```sh
python3 benchmarks/reader-corpus/cache-run.py prepare \
  --baseline-build-work /private/tmp/reader-build-baseline \
  --candidate-build-work /private/tmp/reader-build-candidate \
  --cache /opt/aww_cache --expected-files 1881 \
  --output /private/tmp/reader-cache-full
```

Preparation reads each file as both containers in each library: 7,524 untimed
reads for this inventory. It uses one sequential batch process per library,
removing each result and collecting garbage before continuing. For each file,
it checks the requested container and requires exact baseline/candidate
equality separately for each output: complete `datasig()` values, dimensions,
warning messages, error classes and error messages. Dimensions and conditions
must also agree between outputs. Signatures cover values and Stata metadata.
Dibble construction can widen a string's declared Stata storage to fit decoded
UTF-8 bytes, so its raw signature need not equal the tibble's. Cross-output
signature differences are recorded explicitly. There is no additional R
aggregate traversal. Qualification records remain private.

Only these two existing malformed-input exclusions are accepted, using the
exact corpus, canonical stable ID, byte count and SHA-256 tuple from
[`r-corpus-roundtrip/common.R`](../r-corpus-roundtrip/common.R):

| Canonical ID | Bytes | Reason | SHA-256 |
| --- | ---: | --- | --- |
| `MICS-9fcbb54ada2fcece459bca33` | 0 | Empty source | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `MICS-8cb7d864111538cd2265198f` | 27,792 | Malformed source | `76b12af213a2e89d4ae241694a1d09dc06efbc5a36f6b85cb2d0257c89e1111a` |

Both exclusions must be present. Any unexpected failure, changed exclusion
identity, success on an expected malformed file, or qualification disagreement
aborts preparation. Expected failures remain attempted files, with their
conditions retained; they are never reported as successful reads.

Successful preparation writes a `QUALIFIED` seal binding the inventory,
configuration, input selection, build/input/worker provenance, and both
libraries' qualification records. It stops before timing. The measurement
command verifies that seal and the source, installation and input bindings
again. Keep all measurement and build-verification scripts unchanged between
the two phases.

For a bounded runtime smoke, use the same preparation command with `--smoke`
and a different output directory. It selects the smallest nonempty file in
each of the five corpora and both known malformed files: seven files in the
current cache. The expected count still checks the complete cache inventory.
Smoke runs are marked explicitly and cannot serve as full-cache evidence.

## Revalidate an unchanged completed qualification

The first October 1 qualification required raw signatures to agree between
tibbles and dibbles. That was too strict for established string-storage
normalization: baseline and candidate records matched exactly within each
output, but 29 files had different signatures between outputs. A separate
diagnostic checked all 29 pairs and found that changing only the tibble string
storage declarations to the dibble declarations made every signature equal.
All values and other logical metadata matched. The original failed run has
no qualification seal or timed observations and remains intact.

The explicit `revalidate` command can apply the corrected policy to complete
records without pretending that R reread the files. Before editing the
controller, archive its exact original bytes outside the failed run. The
command verifies this archive against the hash in the original binding,
requires every other worker, input, runtime, source and installation binding
to remain identical, and rechecks the complete cache inventory and input
hashes. It rejects incomplete, sealed or previously timed runs and chained
revalidations. It copies the original records byte-for-byte into a new
directory, records both controller hashes and original artifact hashes, and
seals the new qualification. The R workers and timing protocol are unchanged.

```sh
python3 benchmarks/reader-corpus/cache-run.py revalidate \
  --source-output /private/tmp/reader-cache-original \
  --original-controller /private/tmp/cache-run-original.py \
  --output /private/tmp/reader-cache-revalidated
```

Use the new directory with `measure`. Publish the policy correction and
revalidation provenance with the results; do not label the original failed
run as successful or imply that new qualification reads occurred.

That recorded revalidation preceded the later survey-only scope correction.
It used the archived [measured controller](results-2026-10-01-full-cache/measured-controller.py).
The current inventory policy requires the five survey roots, so it cannot
revalidate the earlier, broader inventory. Use the current `prepare` and
`measure` commands above and below for a new survey-only run.

## Select the published survey results

The published October 1 survey results select DHS, MICS, NSFG, ENADID and WFS from the
completed observations without rerunning reads or changing any values. The
original 1,882-input, 3,764-attempt records remain private and unchanged;
the selected subset has 1,881 inputs and 3,762 attempts. It retains all
3,758 successful observations and four expected malformed-input errors within
the survey roots.

The [selection record](results-2026-10-01-full-cache/selection.json) binds the
original, selected and excluded records by hash and records the exact root
allowlist. Aggregates are recomputed from the selected records. Source-run
metadata and host samples still describe the original execution and are
labeled accordingly. The measured controller remains available by its exact
hash; the [scope patch](results-2026-10-01-full-cache/inventory-scope.patch)
records the later inventory restriction for future runs.

The reproducible selector verifies the original published provenance and
qualification seal before copying selected raw records into a new private
directory and recomputing the twelve aggregate rows:

```sh
python3 benchmarks/reader-corpus/select-surveys.py \
  --source-output /private/tmp/reader-cache-completed \
  --source-provenance /private/tmp/reader-cache-original-provenance.json \
  --output /private/tmp/reader-survey-selection --expected-files 1881
```

Only `summary.csv` and the sanitized `selection.json` are published from that
directory. Its selected inputs and per-file observations remain private.

## Measure

Run measurement after qualification succeeds and the host is ready:

```sh
python3 benchmarks/reader-corpus/cache-run.py measure \
  --output /private/tmp/reader-cache-full
```

This produces 3,762 attempts, including both containers for each malformed
input. Files and outputs run sequentially, with at most one timed R child at
a time. Output order alternates by file. Every attempt launches a fresh R
process, loads the selected dtatools package, then times its first public
`read_dta()` call. There is no in-process read warmup, wrapper compilation or
forced pre-read garbage collection. Hashing each file immediately before its
two attempts warms the filesystem cache. These are warm-cache measurements,
not cold-storage measurements.

The worker uses base R for argument handling and output. It checks that
`jsonlite` is absent before and after reading. Read-call wall time and CPU
come from the same `proc.time()` interval; CPU is user plus system time across
threads. Warning capture occurs inside that interval. After the timer, the
worker checks shape and container, hashes the warning/error record and prints
its result. A successful dataset stays live until process exit. The Python
controller checks dimensions, finite nonnegative clocks and condition identity
against qualification before retaining an observation.

Whole-process CPU and peak RSS come from `wait4()` and include startup,
package loading, the read, result checks, condition serialization/hashing,
reporting and shutdown. RSS is normalized to bytes on macOS and Linux.
These process metrics are not read-only allocation measurements. In
particular, condition hashing adds work after the read timer that the
historical corpus worker did not perform. The warning handler is also an
instrumentation difference; this is a dated rerun with similar timing
boundaries, not identical historical instrumentation.

Every completed observation is appended to `observations.jsonl`; all records
are also written to `observations.csv` at completion. No outliers or slow
reads are removed. `MEASUREMENT_STARTED` prevents accidentally restarting a
partial measurement in the same directory. A failed or interrupted run keeps
its records but has no `COMPLETE` marker. Start a new private run to repeat it.
The final marker is written only after exact attempt-completeness checks,
re-inventory, full input rehashing, source/install/runtime/worker checks and
qualification-seal verification succeed.

## Aggregate and publish

`summary.csv` reports each corpus and an all-corpus total separately for each
container. It distinguishes attempted, readable and excluded files. Read-wall,
read-CPU and process-CPU totals sum one successful observation per file;
peak RSS is the largest individual process peak. These are batch totals,
not repeated-run medians or paired baseline/candidate speed estimates. The
baseline participates in correctness qualification only. With the two known
malformed files unchanged, this inventory has 1,879 readable inputs per
container.

Keep the entire run directory private. It contains source paths, survey
identities, complete signatures, warning/error text and child commands/logs.
Publish only reviewed aggregate tables, coverage/exclusion counts, the
measurement protocol and sanitized provenance. Sanitize build/runtime
bindings and input identities before copying them; do not publish private
inventory, input, configuration, qualification or job files wholesale.
Record host interference honestly and retain every timing observation.

The earlier README table used 1,812 comparable files selected from a
1,823-file DHS/MICS/NSFG inventory. This run includes 58 additional files from
ENADID and WFS, plus readable files outside the historical comparator
subset. The retained historical archive is not required or reconstructed by
this runner. Historical haven, Stata and Arrow totals must remain explicitly
dated and separate; do not divide them into this run's totals or claim a new
same-file comparison. See the
[September 16 report](results-2026-09-16-base-r/README.md) for that historical
selection and its comparator dates.

Run the public, data-free parser and completeness checks with:

```sh
python3 -m unittest discover -s benchmarks/reader-corpus -p 'test_*.py' -v
```
