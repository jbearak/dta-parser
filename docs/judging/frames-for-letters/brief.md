# Gate 1 brief: plan 0024 (frames where `.a` to `.z` compare as missing)

You are a design reviewer for the repository at the working directory
(dta-parser: Stata `.dta` and Parquet I/O in R, Python, Julia and
TypeScript). Read `AGENTS.md` first and follow its rules: never run or
look for Stata, never read official Stata documentation. Do not edit,
commit or push anything, and do not start subagents; this is a
read-only review.

## What to review

- `docs/plans/0024-frames-for-letters.md` (the plan under review).
- Earlier rounds of this review, if any:
  `docs/judging/frames-for-letters/round-*.md`. Check that every earlier
  finding was answered, and do not re-raise one the plan answered unless
  the answer is wrong.

Evidence and context:

- `docs/research/polars-2.md` (polars 2 and R polars, probed).
- `docs/research/polars-2-probes/` (in `docs/judging/frames-for-letters/probes/` during rounds 1 to 5): the probe scripts behind
  the plan's tables (arrow `probe*.R`, R grouping `by.R`, `t.R`,
  `bench.R`, comparisons `cmp.R`/`cmp.py`, pandas `pd*.py`). They ran
  against scratch installs (R polars and nanoarrow in
  `$TMPDIR/polars2-research/rlib`, Python polars in
  `$TMPDIR/polars2-research/pyenv/.venv`, pandas 3.1.1 in
  `$TMPDIR/pd-probe/.venv`); you may run them if those exist.
- Decisions already made by the user (not open for review, but check
  the plan states them faithfully): R's datakit stays on tibbles;
  grouping in R gets a helper, `datakit_by()`, not a proxy class;
  polars was the wrong choice for Python's datakit.
- R: `r/datakit/R/` (package), `r/dtaparser/R/accessors.R` (`na_tag`),
  `r/dtatools/R/dta_num.R` (the proxy approach rejected), `docs/r.md`.
- Python: `python/dta_parser/_array.py` (`DtaArray`), ADR 0015
  (`docs/adr/0015-stata-array-in-pandas.md`), `python/datakit/datakit/`
  (the polars datakit), `python/src/arrow/` (its native Arrow path),
  `python/src/lib.rs`, ADRs 0034 and 0036, plan 0018's Exactness table
  (`docs/plans/0018-parquet.md`), `docs/python.md`.

## The question

Is this plan the right way to carry out the user's decisions, complete
enough to implement each stage without guessing, and would its tests
prove it? In particular:

- Stage 2: is `datakit_by()` specified well enough (naming, types,
  errors, dplyr verbs it works in), and are its claims about dplyr
  right?
- Stage 3: are the new `DtaArray` comparison and arithmetic rules
  right and complete, and what in pandas or in dta_parser's own code
  (reads, writes, `groupby`, `merge`, `sort_values`, reductions) would
  they break?
- Stage 4: is pandas with `DtaArray` the right replacement for polars
  given the evidence, is the column table complete, and is the native
  adapter (Arrow-shaped native results handed to NumPy, and NumPy
  input to the writers) sound and adequately specified?
- Anything the plan gets wrong about the code, and anything it should
  cut.

Check claims against the code. Keep findings concrete and actionable;
prefer fewer, real findings to many speculative ones. Say what you would
cut as well as what you would add.

## Reply format

```
VERDICT: APPROVE | CHANGES
Per stage (1, 2, 3, 4): one or two lines each.
FINDINGS (only if any):
<id>. [blocker|should|nit] <finding>. Fix: <what the plan should say>.
```

APPROVE means you would let implementation start from this text as it
stands (nits allowed). Reply with that text only.
