# Long and float addition

The numeric kernel preserves binary64 addition for full-length, non-temporal
Stata long/float pairs in either operand order. A 64-row local proof skips
per-value missing classification for ordinary blocks. Exceptional blocks retain
the exact format-aware writer. Four failed proofs use that exact writer only
for the remainder of the captured span, at most 16,384 rows. A captured exact
all-missing count on either source permits a canonical double-NA fill without
reading either input. Existing capture and read-claim ownership rules apply.

The [measured results and limits](results-2026-10-03.md) link this mechanism to
the retained [public evidence](evidence/publication-manifest.json).

`run.py`, `core.py`, `worker.R`, and `test-run.py` reproduce the final decision
screen from supplied clean source-bound build directories. The exact historical
source pins are in run.py. The corresponding raw records and source bindings
are published with the report. This Unix-only controller checks the actual
receipt variants rather than treating logical baseline/candidate role labels as
build variants.

The screen has 58 observations per build and round, 116 no-clock observations
and 696 timed observations over six rounds. It covers both operand orders,
ordinary/sparse/random-half/prefix/suffix/all-tags inputs, retained 8191/16385
spans and short 7/11 spans. All-tags is a plain-only timing case; retained
8191/16385 uses the other five patterns, and 7/11 uses ordinary/sparse inputs.
Typed and bare controls are plain doubles even in
retained panels. Random input masks are independently half missing; output
missing density is their recorded union. Bare controls occur only for ordinary
inputs. Full inputs and outputs, exact cache clearing, source state, native
entries, balanced representation/build orders and before/after source/runtime
bindings are checked outside the clocks.

Run the protocol guards normally and under Python optimization. Run `run.py`
with `--baseline`, `--candidate`, `--repository`, a fresh `--output`, and
`--qualify-only` first. Timing requires `--qualification` pointing to those
completed observations and an otherwise quiet host. Calls include output
allocation and automatic GC. Calibration, explicit GC, construction, hashing
and mutation qualification are outside timing.

`work-count.py --output FRESH_DIRECTORY --require-proved` is a structural
regression check, not a timer. It copies actual arithmetic headers and extracts
their result/preflight policies into a private compilation, then adds counters
at the pair-loader/proof boundaries. R allocation, captured spans and interrupt
entry are mocked. The independent bit oracle covers 162 cases, including both
missing layouts, imported finite/nonfinite encodings, overlapping missing
positions and all-missing sources. The current checkout is checked against its
immutable HEAD before and after execution. This test does not establish public
ownership, reentry or allocator behavior; the R regressions cover those.

The small fixture `fixtures/work-count-red.csv` preserves the actual 162-case
pre-fill structural records. `test-work-count.py` checks that incomplete or
contradictory records are rejected, normally and with Python optimization.
The current-source compiled probe separately requires the work gates to pass.
