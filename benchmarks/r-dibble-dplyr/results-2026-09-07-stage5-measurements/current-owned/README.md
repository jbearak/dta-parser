# Combined Stage 5 ownership measurements

The current thirteen-phase run compares Stage 4 source
`f622f1ddba04b2bb7ac07415faccf2b417aab0e6` with combined Stage 5 source
`a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9`. Both use the same pinned
benchmark helpers and exact installed packages. Timed phases ran sequentially
while the implementation agent and both reviewers paused local workloads.

The completed outer receipt binds 230 products and 48,334 inputs. Both
independent reviews verified the original run records and the detailed
operation, allocation, write and memory comparisons. Candidate post-read
selectors retain their allocation and unchanged-column scan limits. First
shared writes copy the target payload; subsequent private writes and full
replacement retain their distinct copy budgets. The retained-heap comparisons
pass the candidate's less-than-1-MB retained/excess limits.

The 252 current operation comparisons have one timing flag: logical Arrow
writing at 100k rows and eight columns, 7.138 to 8.154 ms. Allocation is unchanged
for that row. Its three later paired repetitions have no flag; those raw
repetitions are separate read-diagnostic evidence. The original flagged row
remains in this archive. Both current and historical double comparisons have
no timing flags.

A separate comparison against the original Stage 3 baseline
`ec10a6ac34602f3bd691e8043019c1b479babda4` retains fifteen flags at 1M rows and
eight columns: twelve base-R reads and three filters. Each of the twelve reads
uses one column. Later repetitions reproduce those twelve at 1M rows and on a
one-column table, while the 100k cases stay below the 1-ms absolute threshold.
The native read investigation and Stage 6 filter work remain open. These costs
are not waived by the passing ownership gates.

The historical comparison derivations were hashed after execution. They do
not acquire pre-execution or failure-finalization bindings from this archive.
Original baseline records and whole-run metadata retain their earlier source
identities; omitted historical candidate records are not relabeled as current
evidence. Independent review scripts recalculate the saved comparisons.

The complete broad matrix retained reported medians and allocation summaries,
not individual timing samples or the original temporary allocation events.
Later narrow repetitions retain raw samples separately. Some legacy retained
vector-heap aggregates lack a printed primitive before/after pair; reviewers
distinguish what can be recalculated from logs from source-checked reporting.
Cumulative R allocation, native copy counters, retained heap and process peak
RSS are different quantities. The counters may overlap and must not be added.

The [selection](selection.json) lists every retained file's source path, archive
path, size, Unix mode and SHA-256. Executed drivers, helper code, review scripts
and this description remain plain files. Repeated indexes, logs and data are
stored in `records.tar.gz`; tar timestamps and owner fields are normalized.
Verify all selected bytes and modes without extracting filesystem paths:

```sh
python3 bundle-evidence-v1.py verify .
```

Installed libraries, runtime trees and generated build products are omitted,
with their original identities retained in the indexes. Absolute paths identify
the original environment. This archive is a selective record, not a standalone
replay bundle or a new experiment. Full external OS, SDK and Python closures
were not frozen. The verifier checks consistency, not external authenticity,
concurrent mutation or omitted inputs. Local reviewers inspect the selected
contents; no claim is made that an external review service inspects compressed
contents. Overall performance and the later direct-operation stages remain
separate acceptance work.
