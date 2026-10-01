# I/O and merge comparison against v0.10.0

The later build is not uniformly faster or slower. Typed-input writes and
the wide typed merges remain near parity. Ordinary-R `m:1` merge is about 21%
slower, ordinary-R DTA writing is 1% to 2% slower, and package namespace
loading adds about 0.112 seconds. Fresh large DTA reads are slower, but the
separate warm India DTA control is faster. The fresh India Arrow improvement
does not persist in the warm control.

These are paired build comparisons on this machine, not replacements for the
R README's historical full-corpus, Stata, Haven, dplyr or base-R results.
No comparator package or Stata timing was refreshed here. The write operations
below are the exported `save_dta()` and `save_arrow()` APIs.

## Builds and scope

The baseline is v0.10.0, commit
`20b66c6999af60ccac14207f43ea29318d8f48f0`, package tree
`ffcf370dd5ce9bd40a3030ceccd257d918fcfe0e`. The candidate is the production tree
at `cbabff67950308f67595af1808af4f99cdb9bc59` plus the grouped-dplyr allocation
capacity fix under review. Both installed packages report version 0.10.0.
Production-file and installed-file hashes, not the version string, identify
the exact measured builds in the provenance records.

Archived baseline production files were checked against the tag's Git blob
IDs. For both builds, the source-build DLL matched the installed DLL. The
baseline DLL SHA-256 is
`cb1090c44af769afd8e011d97130a698cc05c90ad98a70102c47f1deca3dcb20`;
the candidate DLL SHA-256 is
`ceecbf65aea0b898d8a99a729154508df08f7d344248caa1d102332f42a9ea06`.
The installation logs record the same R 4.6.1, Apple clang 21 and Rust 1.98.1
toolchain. Measurements ran on macOS 26.7 with 16 logical CPUs reported.
The installed dependency versions available to both libraries were rlang 1.3.0,
vctrs 0.7.3, tibble 3.3.1, dplyr 1.2.1 and data.table 1.18.6.1. This inventory
does not mean every timing worker loaded every dependency. Observed
`dtatools.threads` was 0 and `dtatools.alloccol` was 1024.

None of the five public entry-point files changed since v0.10.0. Neither did
the Rust reader or writer engines. The sole Rust change uses a serial gather
for one numeric column; `dta_merge()` can reach that helper. Shared numeric
constructors, owned-column handling, metadata copying and namespace setup did
change. Readers also finish through shared column typing and dibble
construction. The source audit therefore does not establish that downstream
performance must be unchanged. These measurements establish the build-level
differences, not which individual change caused each difference.

## Inputs and protocol

| Workload | Shape | Source |
| --- | ---: | --- |
| Primary 100 MB | 231,956 by 40 | Existing Stata first-save generator |
| Primary 1 GB | 2,320,123 by 40 | Same generator and schema |
| India 2021 women | 724,115 by 5,972 | Same DTA SHA-256 as the September README report |
| Ordinary R 100 MB | 222,711 by 40 | Existing deterministic ordinary-R factory |
| Ordinary R 1 GB | 2,227,111 by 40 | Same factory |
| Wide merge | Master 200,000 by 151; using 360,044 by 110 | Existing seed-7 README fixture |

The primary files retain four byte, four int, nine long, four float, nine
double and ten string columns, including labels and temporal formats. They
were newly generated, so their file hashes differ from the historical files.
The India DTA is 5,196,403,097 bytes and retains SHA-256
`53acf9bc37e4c207e026379f156758bfc47020cbdbf0aa26667e9e1a617ab3fc`.
Arrow inputs were generated once through the baseline, with current-profile
metadata and checksums, then shared by both builds. They are not the old
Arrow files used by all historical reports. File sizes and SHA-256 hashes are
in the provenance records. The ordinary-R factory's source hash and exact row
counts identify its deterministically constructed input.

There are 408 valid timing workers. Reads, merges and namespace loading each
use ten balanced pairs per case; writers use eight. The warm India control
adds ten pairs for each reader. Each case has equal baseline-first and
candidate-first counts. Cases rotate between pairs. Builds, tests and other
benchmarks were stopped during the measurement window.

Call wall time and call CPU share one `proc.time()` interval. Whole-process
wall time, CPU and peak RSS are recorded separately. Fresh reader calls have
no in-process warmup or pre-read GC. Writer input construction or reading and
full GC occur before timing. Merge inputs are already loaded; one untimed
merge and full GC precede the measured merge. The result remains live through
process exit. Default threads, Arrow verification and Arrow checksums remain
enabled; filesystem cache is warm.

This merge protocol uses the same fixture/schema as August's report, not its
full protocol. The August 0.6.0 run loaded bench and dplyr, validated other join
engines, then used repeated `bench::mark()` calls. The newer package also
defaults to dibble output. Its historical 0.101/0.097-second typed results
cannot be compared directly with the absolute values below. The v0.10.0
baseline is already at 0.3545/0.381 seconds in this protocol.

## Fresh reads

Times are seconds. Changes and intervals describe the median paired
candidate/baseline wall-time ratio, not the ratio of the two displayed
medians. Intervals are descriptive 95% paired-bootstrap intervals from
10,000 resamples.

| Reader and input | v0.10 wall | Candidate wall | Paired wall change, 95% interval | CPU, v0.10 to candidate |
| --- | ---: | ---: | ---: | ---: |
| DTA 100 MB | 0.0430 | 0.0430 | 0.0%, -2.3% to +2.4% | 0.1295 to 0.1305 |
| Arrow 100 MB | 0.0290 | 0.0290 | 0.0%, -3.4% to +3.6% | 0.0940 to 0.0945 |
| DTA 1 GB | 0.1865 | 0.1970 | +5.3%, +4.3% to +6.5% | 0.7090 to 0.7210 |
| Arrow 1 GB | 0.1075 | 0.1110 | +3.3%, +0.9% to +5.7% | 0.5780 to 0.5700 |
| DTA India | 0.5995 | 0.6365 | +6.0%, +5.1% to +7.2% | 5.0935 to 4.9435 |
| Arrow India | 0.2910 | 0.2625 | -9.8%, -11.0% to -8.9% | 2.7410 to 2.7170 |

The India DTA result trades higher fresh-call wall time for lower CPU time.
The Arrow India wall improvement does not imply the same improvement for all
files or protocols. Neither result updates a full-corpus total.

## Writes

| Writer and input | v0.10 wall | Candidate wall | Paired wall change, 95% interval | CPU, v0.10 to candidate |
| --- | ---: | ---: | ---: | ---: |
| DTA primary 100 MB | 0.0295 | 0.0295 | 0.0%, -3.3% to +3.4% | 0.0750 to 0.0770 |
| Arrow primary 100 MB | 0.0400 | 0.0405 | +0.1%, -5.0% to +5.1% | 0.0585 to 0.0585 |
| DTA primary 1 GB | 0.1645 | 0.1650 | 0.0%, -1.5% to +2.5% | 0.6660 to 0.6650 |
| Arrow primary 1 GB | 0.2460 | 0.2455 | +0.1%, -4.5% to +3.0% | 0.4600 to 0.4580 |
| DTA ordinary 100 MB | 0.1955 | 0.2000 | +2.3%, +0.5% to +3.6% | 0.1925 to 0.1970 |
| Arrow ordinary 100 MB | 0.0855 | 0.0860 | 0.0%, -2.3% to 0.0% | 0.1080 to 0.1085 |
| DTA ordinary 1 GB | 1.9560 | 1.9785 | +1.3%, +0.4% to +1.8% | 1.9300 to 1.9520 |
| Arrow ordinary 1 GB | 0.7015 | 0.7045 | -0.4%, -1.1% to +4.6% | 0.9440 to 0.9400 |

## Merges

Both inputs are loaded outside the timer. Wide results contain 440,044 rows
and 201 columns, with shared columns coalesced and `_merge` codes preserved.
The one-column control keeps only `caseid` and one compact numeric column
from each input; its result has three columns.

| Merge | v0.10 wall | Candidate wall | Paired wall change, 95% interval | CPU, v0.10 to candidate |
| --- | ---: | ---: | ---: | ---: |
| Typed 1:m | 0.3545 | 0.3550 | +0.3%, -1.9% to +1.0% | 0.6385 to 0.6360 |
| Typed m:1 | 0.3810 | 0.3820 | +0.3%, -0.5% to +2.4% | 0.6450 to 0.6450 |
| Ordinary 1:m | 0.0940 | 0.0930 | -0.5%, -1.1% to +0.5% | 0.0935 to 0.0930 |
| Ordinary m:1 | 0.1090 | 0.1320 | +21.1%, +19.0% to +25.2% | 0.1095 to 0.1320 |
| One compact column 1:m | 0.2770 | 0.2690 | -2.4%, -3.6% to -0.7% | 0.2770 to 0.2690 |

The ordinary `m:1` slowdown is the clearest downstream call-level regression
in this matrix. Its CPU cost rises with wall time. The fixed ordinary inputs
are the same fingerprinted RDS files for both builds. No cause is assigned to
an individual change, and no production fix was made during the assessment.

## Startup and warm-read controls

`loadNamespace("dtatools")` alone takes 0.083 seconds wall and CPU in the
baseline, versus 0.195 seconds in the candidate. This directly measures
0.112 seconds of extra namespace-loading cost. Peak process RSS rises from
96.7 MB to 122.5 MB. The 100 MB DTA worker's whole-process wall median rises
from 0.2152 to 0.3260 seconds even though its read-call median is unchanged.
Long-running R sessions do not pay namespace loading on every read.

For the separate warm India control, each fresh worker performs an untimed
read, removes it, runs full GC, then measures a second read:

| Reader | v0.10 wall | Candidate wall | Paired wall change, 95% interval | CPU, v0.10 to candidate |
| --- | ---: | ---: | ---: | ---: |
| DTA India | 0.4070 | 0.3925 | -3.6%, -4.2% to -3.1% | 4.2685 to 4.0355 |
| Arrow India | 0.2145 | 0.2155 | +0.5%, -1.3% to +0.9% | 2.1825 to 2.2010 |

The fresh and warm protocols give different answers. This rules out treating
the fresh-call deltas as general steady-state throughput changes; it does not
identify the underlying runtime mechanism.

## Correctness and records

All three DTA/Arrow pairs have equal full canonical signatures across builds
and formats. All five merge cases passed full-signature, shape, key-count,
match-count, shared-value and unchanged-input checks. Timed merge workers
check shape; separate repeated-call qualification checks the full result and
input signatures after a warmup and second merge. Full timed-process merge
outputs were not retained.

First and final writer samples for every case/build were read through the
baseline reader and signed, giving 32 readback checks. Another 16 calls checked
input signature preservation. Warning sequences matched across all 128 write
timings. Arrow's warning about dropping the temporal columns' `tzone`
attributes is pre-existing and equal in both builds; the profile's canonical
metadata signature excludes unsupported attributes. No correctness difference
was found in these workloads.

The initial write attempt stopped because the harness incorrectly required
zero warnings. Its two completed DTA timings are excluded; the expected Arrow
warning was added to per-call comparison and the entire write matrix restarted.
Read timings had already used the correct balanced schedule and were not
rerun. Read and later-phase harness/provenance snapshots are recorded
separately. The portable provenance helper replaces local path constants with
configuration fields; timing-worker and driver sources are retained.

The [harness instructions](../README.md),
[configuration example](../configuration.example.json) and
[sanitized measured configuration](recorded-configuration.json) describe
reproduction; the supplemental control has its own
[warm configuration](warm-recorded-configuration.json).
The merge fixture uses seed 7; paired bootstrap intervals use
seed 20261001. Production, installed-library, input and worker SHA-256 hashes
are recorded in the provenance files.

| Records | Raw observations | Summary |
| --- | --- | --- |
| Fresh reads | [JSONL](reads-raw.jsonl) | [CSV](reads-summary.csv) |
| Writes | [JSONL](writes-raw.jsonl) | [CSV](writes-summary.csv) |
| Merges | [JSONL](merges-raw.jsonl) | [CSV](merges-summary.csv) |
| Namespace loading | [JSONL](loads-raw.jsonl) | [CSV](loads-summary.csv) |
| Warm India reads | [JSONL](warm-reads-raw.jsonl) | [CSV](warm-reads-summary.csv) |

Qualification records cover [inputs and merges](inputs-qualification.json),
[writer outputs and preservation](outputs-qualification.json), and
[repeated merges](repeated-merge-qualification.json). Provenance records cover
the read phase [before](reads-provenance-before.json) and
[after](reads-provenance-after.json), then later phases
[before](later-provenance-before.json) and
[after](later-provenance-after.json). Each pre/post comparison passed for
production files, installed packages, fixed inputs and its recorded root-level
harness. The supplemental warm helpers were outside that collector's glob;
their [separate source-hash record](warm-harness-provenance.json) was captured
after execution, not before. Their published copies match the executed files,
and the library/input pre/post checks cover their measurement window.
The [excluded write attempt](excluded-write-attempt.jsonl) remains available
but contributes no sample to the write summary.

Local input paths and raw process logs remain private. The intervals describe
this single machine and warm filesystem.
They do not include variation between hardware, R versions, datasets or cold
caches. Namespace startup and ordinary `m:1` merge are candidates for a
separate performance investigation, not fixes included in this assessment.
