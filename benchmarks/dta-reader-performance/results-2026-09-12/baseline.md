# Historical reader experiment baseline

This metadata was recovered from retained records for the September 12, 2026
experiment. No measurements were rerun. The six published observation and
summary CSVs are byte-for-byte copies of the original phase outputs.

The [execution manifest](execution-manifest.json) exports all 135 recorded
child processes, their order, argument lists, variant settings, start times,
exit codes and whole-process resource totals. It also includes each phase's
original plan and file-binding snapshot. Private input, library and checkout
paths use documented tokens. Original unredacted record hashes identify the
retained files, and added log hashes identify each child's retained output.
The top-level Python invocation and full inherited environment were not
recorded. Redacted commands are records of the original arguments, not shell
commands that can be executed without replacing their path tokens.

| Phase | Cases | Variants | Rounds | Processes | Order |
| --- | ---: | ---: | ---: | ---: | --- |
| Screening | 1 | 5 | 3 | 15 | Seeded shuffle, seed 20260912 |
| Tuning | 1 | 10 | 3 | 30 | Seeded shuffle, seed 20260912 |
| Final comparison | 3 | 3 | 10 | 90 | Reverse on alternating rounds |

Every process exited with status zero and produced one timed read with the
expected dimensions. Export checks matched all recorded elapsed values and
RSS totals to the published observations. The final variants were stock,
batch-default and batch-16-threads. Stock and batch-default requested zero,
which selected eight workers at that source version. The third variant
explicitly requested 16. The separate four-tool baseline is described in the
[main report](../README.md#relation-to-the-four-tool-comparison); it is not one
of these three phases.

| Input | Rows | Columns | Bytes | SHA-256 |
| --- | ---: | ---: | ---: | --- |
| India | 724115 | 5972 | 5196403097 | `53acf9bc37e4c207e026379f156758bfc47020cbdbf0aa26667e9e1a617ab3fc` |
| Synthetic 100 MB | 231956 | 40 | 100000187 | `fc2cd5376eea3b29b2a989ead21d224351a75ed1a9b75dc5940b80f2c70a63da` |
| Synthetic 1 GB | 2320123 | 40 | 1000000164 | `ab08515fbe880e06aeef3f2054ce5b6f1201c3aacfe631e9808e8fb913aa6a24` |

The contemporaneous report records an Apple M4 Max with 16 cores and 128 GB,
macOS 26.6.2 and R 4.6.1. A separate machine-readable host capture was not
retained for these phases. Instrumented and final installation logs record
Rust 1.98.0, Apple clang 21.0.0 and SDK 26.5, with release, locked, offline
Cargo builds. Their authentic excerpts and full-log hashes are in the
manifest. The stock installation reused an existing native library, so its
log's compiler labels do not establish that binary's build compiler.

Each trial loaded the isolated package in a fresh R process, ran a full GC,
then measured `proc.time()` elapsed around one read. The result remained live
through exit. `wait4()` supplied peak RSS for the entire process, including
startup. The job's `wall_seconds` also covers the entire process and is
distinct from the CSV's read elapsed time. RSS uses decimal GB. These phases
did not record CPU time. The original report states that filesystem caches
were warm and that no builds or other benchmarks ran concurrently.

The [nine final signatures](signatures.json) match stock on every input and
variant. Signature computation occurred in separate processes and is absent
from the reported timing and RSS. The old runner did not enforce that
qualification happened before timing; retained records do not establish the
order. Complete separate signature records for every screening and tuning
variant are also absent. Adding the manifest does not retroactively qualify
those measurements under the current runner's stronger gate.

The historical report states that input, worker and library hashes matched
before and after each phase. The original binding snapshots are retained;
separate after snapshots were not. The final runner's source confirms it
checked bindings again before writing its summary. Screening and tuning
bindings omitted the runner and plan themselves, so their exact runner bytes
cannot be independently established from those bindings.

The final measured source is commit
`53e388f19707620ad24ce215b3862da7c07c9c47`, based on
`cf0c80d72191491d42db51d5882a9d7f9d16194e`. Its runner hashes to
`8e02a6bc2f846e694da6cfab928f5aa59abfbd5d362c11c92da7a290bed71e50`.
The [existing provenance](provenance.json) retains the source patch, worker,
input, Rscript and installed-file hashes. The current runner's added
qualification and metadata do not change those historical source identities.
