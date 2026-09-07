# Stage 4 review supplement

This directory addresses the five evidence findings in
[PR196's substantive review](https://github.com/jbearak/dta-parser/pull/196#pullrequestreview-5129614197).
It preserves the original evidence at
[`5173f39`](https://github.com/jbearak/dta-parser/tree/5173f39b9b1bf895c4ced776b83db276e4593bc1/benchmarks/r-dibble-dplyr/results-2026-09-07-stage4).
The measured package remains
[`e343b3b`](https://github.com/jbearak/dta-parser/tree/e343b3b56a8529e9ee0ac40f8bd88beebcd2be15/r-package/dtatools),
package tree `f12a2a1dd430636a33b7f6e953023d90d1ff2589`. This evidence-only
branch starts at Stage3 merge `ec10a6a`; its package tree is still
`25140719d251c9827c108c291f99705b26fe38dd`. The supplement does not qualify
that Stage3 package as the Stage4 candidate.

[The index](index.json) records every copied artifact's original path, byte
length, SHA-256, full Unix mode and Git executable mode. Copies retain original
bytes. Git distinguishes regular nonexecutable `100644` from executable
`100755`; it does not preserve every Unix permission bit. The authored README,
current helper and index are separate from those copied historical records.

## Missing review inputs

Finding [3947800413](https://github.com/jbearak/dta-parser/pull/196#discussion_r3947800413)
correctly identified omitted review inputs. `review-inputs/` contains the two
identity records and all 26 frozen API13 snapshot files. Independent follow-up
also found the separately referenced API13 audit JSON, bringing the total to
29. Their bytes and hashes match the retained originals. The
[API13 identities](review-inputs/api-review-round13-identities.json) bind the
snapshot; its [independent audit](review-inputs/api-review-round13-independent-evidence-audit.json)
retains both failed strict downstream comparisons and the narrow footer-only
semantic audit. No original archive script or index has been rewritten.

## Fresh workspace qualification

Finding [3947800434](https://github.com/jbearak/dta-parser/pull/196#discussion_r3947800434)
identified a real proof gap. Equality of three committed Git objects did not
establish which working files the earlier five Cargo commands read. The
historical reuse claim was therefore insufficient to bind those results to the
final source. Its original proof and logs remain unchanged at `5173f39`.

The [new manifest](workspace-gates/manifest.json) records fresh formatting,
clippy, 278 tests, documentation and packaging gates from a detached clean
checkout of exact `e343b3b`. All five commands passed. Packaging used no
`--allow-dirty`; documentation used `RUSTDOCFLAGS=-D warnings`. Before and after
each command, the [driver](supplement-source/run-clean-workspace.py) checked the
full 1,060-file tracked source inventory, byte hashes, file modes, exact HEAD,
workspace manifests, package tree and empty status including ignored files.
All input snapshots are identical. Build outputs and logs live outside the
source checkout. The [actual verified crate](workspace-gates/package-artifact.json) is separately
bound by path, 172,669-byte size, SHA-256 and all 27 member identities. Its VCS
record identifies clean `e343b3b`; ordinary members match that source and
generated manifest, lockfile and VCS text are retained. The new qualification
supersedes only the insufficient historical workspace-input binding; it does
not rewrite earlier measurements.

## Diagnostic replay boundary

Finding [3947800419](https://github.com/jbearak/dta-parser/pull/196#discussion_r3947800419)
correctly notes that the two old diagnosis scripts could fall back to another
library. Their retained logs identify the actual working-library path and DLL,
but those development records were not exact-source qualification. They remain
unchanged and are not retroactively upgraded by this supplement.

[guarded-diagnostic.py](guarded-diagnostic.py) is the supported replay entry
point. It checks the selected installation's provenance, loads with explicit
`lib.loc`, verifies the loaded namespace and DLL path, and repeats installation
checks after execution. It binds both historical diagnostic scripts and all
three helper files, including the transitive `owned-double-helpers.R`, before
and after the child process. Existing CSV outputs are rejected.

For example, from any directory, use a fresh exact-source installation and a
checkout containing the recorded helper bytes:

```sh
python3 /path/to/supplement/guarded-diagnostic.py diagnose aggregate \
  --library /path/to/exact-library \
  --source e343b3b56a8529e9ee0ac40f8bd88beebcd2be15 \
  --repository /path/to/implementation-checkout --check-only
```

Remove `--check-only` for a separately labelled replay. The `accessor` command
also requires a new `--csv` path. These replays do not replace the original
paired benchmark matrices or resolve the fifteen disclosed read flags.

The first new wrapper run completed the aggregate operation but rejected its
final identity check because the historical script overwrote its `expected`
variable. That wrapper failure remains in `diagnostic-guards/`. The corrected
wrapper sources the historical script in a child environment. The ten-case
[second run](diagnostic-guards-v2/manifest.json) passed both valid preflights,
both positive replays, and each script's missing-library, wrong-source and
changed-transitive-helper rejection. Rejected cases produced no stdout or CSV,
even with a valid fallback installation in `R_LIBS_USER`. Its exact executed
helper is retained as a source snapshot. The [current relocated helper qualification](diagnostic-guards-final/manifest.json)
passes the same ten cases and binds its exact helper and dependency bytes before
and after execution. Earlier logs retain their actual tool identity.

## Executable fixtures and historical links

Finding [3947800424](https://github.com/jbearak/dta-parser/pull/196#discussion_r3947800424)
correctly identified sixteen shell fixtures copied as nonexecutable files.
`native-fixtures/` contains their byte-identical retained originals with Unix
`0755` and Git executable mode `100755`. The index records both these modes and
the historical archive's `0644`/`100644`. These copies restore runnable command
fixtures while preserving the original archive and its mode-loss history.
[Execution checks](fixture-mode-check.json) compare exit status, stdout and stderr
for all sixteen original/copied pairs; every result matches and all bytes/modes
remain unchanged.

Finding [3947800450](https://github.com/jbearak/dta-parser/pull/196#discussion_r3947800450)
correctly identifies broken navigation in two relocated progress snapshots.
Those hash-bound source snapshots retain their original text. The index maps
all twelve links to their original `docs/plans` context. Portable destinations
for readers are listed here:

- [Stage4 report](https://github.com/jbearak/dta-parser/blob/5173f39b9b1bf895c4ced776b83db276e4593bc1/benchmarks/r-dibble-dplyr/results-2026-09-07-stage4.md)
- [Stage3 report](https://github.com/jbearak/dta-parser/blob/5173f39b9b1bf895c4ced776b83db276e4593bc1/benchmarks/r-dibble-dplyr/results-2026-09-06-stage3.md)
- [Stage2 report](https://github.com/jbearak/dta-parser/blob/5173f39b9b1bf895c4ced776b83db276e4593bc1/benchmarks/r-dibble-dplyr/results-2026-09-06-stage2.md)
- [Stage1 report](https://github.com/jbearak/dta-parser/blob/5173f39b9b1bf895c4ced776b83db276e4593bc1/benchmarks/r-dibble-dplyr/results-2026-09-06-stage1.md)
- [Plan at the qualified source](https://github.com/jbearak/dta-parser/blob/e343b3b56a8529e9ee0ac40f8bd88beebcd2be15/docs/plans/dibble-result-performance.md)

## Review scope

Both [storage](supplement-source/storage-assessment.md) and
[API](supplement-source/api-assessment.md) initial assessments independently
confirmed the five findings. Final review of this supplement is a separate
gate. The linked-issue warning is accurate: Stage4 evidence does not implement
all of issue172. Stages5–9 and the final integrated checks remain required;
issue172 stays open. The service's zero-percent docstring warning concerns
61 functions in immutable historical scripts. This supplement does not rewrite
those records or claim whole-diff 80-percent coverage. Current helper functions
have purpose docstrings.
