# Gate 1 brief: plan 0025 (polars in R and Python)

You are a design reviewer for the repository at the working directory
(dta-parser: Stata `.dta` and Parquet I/O in R, Python, Julia and
TypeScript). Read `AGENTS.md` first and follow its rules: never run or
look for Stata, never read official Stata documentation. Do not edit,
commit or push anything, and do not start subagents; this is a
read-only review.

## What to review

- `docs/plans/0025-polars-in-r-and-python.md` (the plan under review).
- Earlier rounds of this review, if any:
  `docs/judging/polars-r-python/round-*.md`. Check that every earlier
  finding was answered, and do not re-raise one the plan answered unless
  the answer is wrong.

Evidence and context:

- `docs/research/polars-2.md` (polars 2 and R polars, probed; section 7
  for the comparison rules) and `docs/research/polars-2-probes/`.
- Plan 0024 (`docs/plans/0024-frames-for-letters.md`) and ADR 0038:
  what this plan reverses in part.
- Decisions already made by the user (not open for review, but check
  the plan states them faithfully): Python's datakit stays on polars;
  R's datakit gains polars through `*_pl` functions returning
  `list(df, meta)`; R's frames come from the native Arrow C stream,
  shared with Python; `is_missing()` with the alias `is_mi()` in both
  languages.
- Python: `python/datakit/datakit/` (`_tagged.py`, `_frame.py`,
  `_parquet.py`, `_dta.py`, `_meta.py`), `python/src/arrow/` (the
  Arrow C stream code stage 2 moves), `python/src/lib.rs`.
- R: `r/datakit/` (incl. `R/by.R`, `datakit_by()`), `r/dtaparser/src/`
  (`init.c` callables, `rust/lib.rs`, `rust/parquet_r.rs`, the committed
  crate copies), `r/datparser/` (R's `read_fixed_width`, ADR 0039),
  `.github/workflows/ci.yml` and `r-packages.yml`.

## The question

Is this plan the right way to carry out the user's decisions, complete
enough to implement each stage without guessing, and would its tests
prove it? In particular:

- Stage 1: are `is_missing`/`is_mi` and `dk.by` specified well, and
  right for every dtype?
- Stage 2: is the crate split sound (what moves, what stays pyo3), and
  does "no behaviour change" have a real proof?
- Stage 3: are the C callables, the nanoarrow stream ownership, the
  letter rules in R polars, `datakit_meta`, the `save_*` dispatch over
  dtaparser's `save_dta`, and `read_fixed_width_pl` sound and specified?
  What would break existing callers?
- Stage 4: would the checks prove R and Python give the same frames?
- Anything the plan gets wrong about the code, and anything to cut.

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
