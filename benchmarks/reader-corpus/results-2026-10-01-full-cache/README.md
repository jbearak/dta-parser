# Survey-cache `read_dta()` results, October 1, 2026

Across all 1,879 readable survey inputs, `read_dta()` totaled **31.792 seconds
for tibbles** and **37.323 seconds for dibbles**. The benchmark covers DHS,
MICS, NSFG, ENADID and WFS: 1,881 regular DTA files and 3,762 attempts across
both outputs, with 3,758 successful reads and four expected errors from the
two existing malformed inputs.

These totals select only the five survey roots from the completed
observations. Every selected observation is retained byte-for-byte, without
rerunning reads or filtering by performance. The original records remain
private and unchanged. The
[selection record](selection.json) binds the original, selected and excluded
records and the derivation script by hash. [Source-run metadata](source-run.json)
and host-load counters still describe the original execution.

The candidate is the source-bound package snapshot at
[`61954ee`](https://github.com/jbearak/dta-parser/commit/61954ee88431eb2212e36a24ca8db1781e932ac7).
The [source audit](../../r-corpus-roundtrip/results-2026-10-01/build/source-commit-audit.json)
matches all 409 package files to that commit. The run completed at
18:55 UTC. Every final inventory, input-byte, source, installed-library,
runtime, worker and qualification-seal check passed.

The later `a4cbc870` integration adds summarize functions with the reader
code unchanged. Its integrated namespace and library contents were not part
of these timings; the separate
[integration validation](../../r-file-readers/results-2026-10-01/integration-validation.json)
records that package's correctness checks.

## Read-call totals

Each total sums one first read per file in a fresh R process. Files are
hashed immediately before their two output attempts, warming the filesystem
cache. These are single-pass totals, not repeated-run medians or paired
baseline/candidate performance estimates. Size and memory use decimal GB.

| Corpus | Readable files | DTA input size | Tibble wall time | Dibble wall time |
| --- | ---: | ---: | ---: | ---: |
| DHS | 643 | 46.963 GB | 21.863 s | 25.644 s |
| MICS | 949 | 3.690 GB | 4.463 s | 5.288 s |
| NSFG | 229 | 5.777 GB | 4.812 s | 5.648 s |
| ENADID | 17 | 0.554 GB | 0.454 s | 0.500 s |
| WFS | 41 | 0.130 GB | 0.200 s | 0.243 s |
| **All** | **1,879** | **57.114 GB** | **31.792 s** | **37.323 s** |

The survey inventory contains 57,114,293,618 bytes; successful inputs
contain 57,114,265,826 bytes. MICS contributes the two malformed files: one
empty input and one 27,792-byte malformed input. Their exact identity, size
and SHA-256 tuples are fixed in the [protocol](../cache-run.md). Both were
attempted in both containers and retained as errors. Two directory symlinks
were excluded because they alias directories already counted.

## CPU and peak memory

Read CPU is user plus system CPU across threads, measured over the same
`proc.time()` interval as read wall time. Process CPU and peak RSS cover the
entire fresh child, including startup, package loading, result checks,
condition serialization/hashing, reporting and shutdown. CPU columns sum
successful reads; RSS is the largest individual process peak.

| Output | Read CPU | Process CPU | Maximum peak RSS |
| --- | ---: | ---: | ---: |
| Tibble | 83.446 s | 583.614 s | 5.257 GB |
| Dibble | 89.014 s | 589.140 s | 5.254 GB |

The [aggregate CSV](summary.csv) includes these metrics for each corpus and
the exact byte counts. Every observation within the five survey roots is
included; no outlier or slow-read filtering was applied.

## Qualification and the container-policy correction

The original untimed qualification read 1,882 files as both outputs in both
source-bound libraries: 7,528 reads, including 7,524 records for the selected
survey inputs. It computed complete `datasig()` values and recorded
dimensions, warning messages, error classes and error messages. The baseline
and candidate's complete 3,764-record files are byte-for-byte identical.
Separate [Stata-oracle checks](../../r-corpus-roundtrip/results-2026-10-01.md)
also passed for all 1,879 readable survey inputs. The survey-only supplemental
oracle and its audits were rerun after the scope correction.

The initial controller additionally required tibble and dibble signatures to
match each other. It stopped before timing because 29 files had different
cross-output signatures in both library versions. This was an incorrect
qualification assumption: the established dibble constructor widens string
storage declarations when decoded UTF-8 needs more bytes, and `datasig()`
includes those declarations.

A separate diagnostic checked every affected pair. Across 117 character
columns, the dibble declarations widened to the required fixed byte width;
no column changed to `strL`. Values, names, shapes and other logical metadata
matched. Six columns in two files also lost an internal metadata class
marker. Changing only the tibble's string-storage attributes to the dibble
declarations made all 29 full signatures equal. A synthetic example reproduced
the behavior in both builds. The diagnostic flushed all 29 passing records
before its final summary formatter failed; the aggregate was derived from
those complete records after correcting only the formatter. The
[diagnostic provenance](container-signatures.json) preserves this distinction
and the executed-source, record and log hashes.

The corrected controller requires complete baseline/candidate equality
separately for each output, plus cross-output equality of status, shape and
conditions. It records raw signature differences explicitly. All 18 lightweight
controller tests and a fresh eight-file smoke run under the original scope
passed. An explicit
`revalidate` command then copied the unchanged full qualification records into
a new directory and checked all input, source, library, runtime and worker
bindings. Only the controller hash changed; neither R worker changed. The
original failed run remains unsealed and untimed. Revalidation performed no
new corpus reads and created a new seal before the first full timed attempt.
See the [revalidation record](revalidation.json) and the
[controller correction](qualification-policy.patch). The later survey-root
restriction is separate: the exact [measured controller](measured-controller.py)
retains its original hash, while the [scope patch](inventory-scope.patch)
maps the current five-root controller back to that measured source. The
current controller searches only the five survey roots and rejects missing
or symlinked required roots. All 22 data-free controller and selection checks pass.

## Measurement conditions

- Both outputs used `threads = 0L` and default numeric ALTREP. There was no
  additional R aggregate traversal inside timed reads; complete signatures
  were computed during qualification.
- One timed R child ran at a time. Output order alternated by file. Package
  loading was outside the read timer; first-reader initialization was inside.
  There was no in-process warmup, wrapper compilation or forced pre-read GC.
  Successful datasets remained live until process exit.
- The base-R worker checked that `jsonlite` was absent before and after the
  read. Warning capture was inside the read timer; shape checks and condition
  hashing were outside it. These latter operations still contribute to
  whole-process CPU and RSS.
- The host reported macOS 26.7, 16 logical CPUs and R 4.6.1. The package was
  dtatools 0.10.0 with tibble 3.3.1. The timed phase ran from
  18:35:58 to 18:55:13 UTC. No owned build, test, oracle or other benchmark
  overlapped it.
- The [host monitor](host-monitor.py) sampled the original execution's competing processes at or above
  50% CPU every 30 seconds, excluding the benchmark process tree. Its
  [40 samples](host-load.jsonl) span 18:35:33–18:55:15 UTC. Thirteen samples
  caught Bun, reaching 150.5% CPU, and one caught cliproxyapi at 78.7%; none
  caught competing R or Stata. These thresholded `ps` samples do not establish
  continuous quiet or total machine utilization. See the
  [host summary](host-summary.json).

## Historical results and reproduction

The [September 16 report](../results-2026-09-16-base-r/README.md) used a
1,812-file comparison subset from the earlier 1,823-file DHS/MICS/NSFG
inventory. This run includes nine other readable files from those corpora
and 58 from ENADID and WFS. Its totals therefore remain separate from
historical haven, Stata and Arrow totals. No such comparator was timed here,
and no historical speed ratio is inferred. The warning handler and post-read
condition hashing also differ from the historical worker's instrumentation.

The [survey-cache protocol](../cache-run.md) gives exact preparation,
selection and measurement commands, plus the historical revalidation details.
The [provenance](provenance.json)
binds the R workers, original and corrected qualification evidence, all
unfiltered private observations, and the verified
[source/build records](../../r-corpus-roundtrip/results-2026-10-01/build/build-bindings.json).
Input paths, survey identities, exact signatures, detailed conditions and
individual child logs remain private. The public CSV contains corpus
aggregates.
