# Combined Stage 5 expression measurements

These measurements compare the Stage 4 baseline
`f622f1ddba04b2bb7ac07415faccf2b417aab0e6` with combined Stage 5 source
`a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9`. Each ran from its exact fresh
installation. The shared fixture and measurement drivers are retained as plain
files. Timed runs were sequential while the implementation agent and both
reviewers paused local workloads.

The full grid has 25 cases and two modes per source: the direct implementation
and an equivalently isolated snapshot/delegation reference for this qualified
corpus. Each series retains seven elapsed-time samples. The comparison uses
plain milliseconds, recalculated from raw seconds. A diagnostic flag requires
both a median increase above 10% and an increase above 1 ms.

The combined direct implementation has no such flag against the baseline or
the candidate's safe reference. The original full grid has one safe-reference
pipeline flag, 93.001 to 110.677 ms. It remains in the original comparison.
Three fresh paired repeats did not reproduce a flag in either mode. Those
repeats do not prove a cause for the original variation.

| Selected direct case | Baseline ms | Combined ms |
| --- | ---: | ---: |
| Retain, 1M rows and 16 columns | 0.587 | 0.424 |
| Dependent expression, 1M rows and 16 columns | 54.044 | 54.658 |
| Five-verb pipeline, 1M rows and 16 columns | 91.858 | 89.977 |
| Retain, 100k rows and 64 columns | 1.179 | 0.836 |
| Grouped expression, 100k rows and 1,000 groups | 2710.748 | 965.130 |
| Rowwise expression, 10k rows | 26581.189 | 8669.698 |

The separate write grid records 40 series across both sources, with 280 raw
samples and source/result state checks. No paired same-mode timing flag occurs.
At one million rows, a first shared target write copies 8,000,000 bytes of that
column; subsequent private writes avoid another target copy. Full replacement
avoids copying the old target. Untouched result columns retain their backings.

Eight isolated memory processes cover both sources, 100k/1M rows and direct/safe
modes. Source and retained-column backings stay unchanged with handle depth one
at checkpoints 0, 5 and 50. At 1M rows, direct whole-process maximum RSS is
574,078,976 bytes for the baseline and 492,683,264 for the combined candidate.
That peak includes startup, fixtures and validation. It is distinct from
cumulative allocations and the saved post-GC live-vector heap. Both direct runs
add 1,121 Vcells between checkpoints 5 and 50. A single process peak is not a
confidence interval or a per-read memory result.

The selection includes 30 accepted qualification, measurement and audit runsets,
the completed comparison/coordinator records and the associated review files.
Both independent reviews checked retained sample units, medians, state records
and original bindings. Their historical pending-gate statements retain their
original scope. Earlier source variants, rejected reporting attempts, broader
owned-column matrices and the base-R read-cost investigation have separate
records. None is relabeled as a combined-source result by this archive.

All selected original bytes and Unix modes are listed in [selection.json](selection.json).
Drivers, checks, reviewer scripts and this description remain plain files;
repeated indexes, logs and saved data are in `records.tar.gz`. Tar timestamps
and owner fields are normalized. Verify membership, bytes and modes without
extracting paths:

```sh
python3 bundle-evidence-v1.py verify .
```

The original profilers removed their temporary allocation-event files. The
write records save milliseconds rather than the clock's primitive seconds and
do not retain each timed call's native counters. Those limits remain explicit
in the reviews. R and native allocation counters can overlap and must not be
added. Full OS libraries, the SDK and Python runtime closure were not frozen.

This selective archive omits installed packages, runtime trees and generated
build products. Their identities remain in the original indexes. Absolute
paths identify the measured environment; this is not a standalone replay
bundle or a fresh execution of the experiments. Local reviewers inspect the
selected contents; no claim is made that an external review service inspects
compressed contents. The verified expression results do not resolve the
separate retained base-R read costs or the Stage 6 filter work.
