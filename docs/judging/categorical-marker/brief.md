# Gate 1 brief: plan 0023 (a `.dta` marker for categoricals)

You are a design reviewer for the repository at the working directory
(dta-parser: Stata `.dta` and Parquet I/O in R, Python, Julia and
TypeScript). Read `AGENTS.md` first and follow its rules: never run or
look for Stata, never read official Stata documentation. Do not edit,
commit or push anything; this is a read-only review.

## What to review

- `docs/plans/0023-categorical-marker.md` (the plan under review).
- Earlier rounds of this review, if any:
  `docs/judging/categorical-marker/round-*.md`. Check that every earlier
  finding was answered, and do not re-raise one the plan answered unless
  the answer is wrong.

Context to read as needed:

- Plan 0020 (`docs/plans/0020-factor-characteristic.md`, the factor
  marker), plan 0021 (TypeScript datakit, `saveDta`, `readDta`) and plan
  0022 (`docs/plans/0022-categorical-letters.md`, Parquet categoricals
  with `.a` to `.z`).
- Writers: `python/datakit/datakit/_dta.py` and `python/src/arrow/dta.rs`
  (`dta_write_arrow`, `category_sets`), `js/datakit/src/save-dta.ts`
  (`categorical`), `r/dtaparser/R/save_dta.R`, `python/dta_parser/_write.py`.
- Readers: `python/datakit/datakit/_frame.py` (`finish`, `to_factors`)
  and `python/src/arrow/dta.rs` (`dta_read_arrow`), `js/datakit/src/dataset.ts`
  (`restoreFactors`, `check`), `r/dtaparser/R/read_dta.R`
  (`marked_factor_holds`), `python/dta_parser/_read.py` (`_marked_factor`).
- `compat/parquet/save_dta_compare.sh` and `compare_saved.py`.

## The question

The user asked that Python's and TypeScript's `save_dta` mark what they
write as a categorical, not as a factor, since a categorical there may
hold `.a` to `.z`. Is this plan the right design, complete enough to
implement in every language without guessing, and would its tests prove
it? In particular: the marker and its relation to `dtaparser_factor`;
the read checks and fallback; what each language reads and writes;
round trips between languages; anything the plan gets wrong about the
code.

Check claims against the code. Keep findings concrete and actionable;
prefer fewer, real findings to many speculative ones. Say what you would
cut as well as what you would add.

## Reply format

```
VERDICT: APPROVE | CHANGES
Per area (marker, writers, each reader, tests): one or two lines each.
FINDINGS (only if any):
<id>. [blocker|should|nit] <finding>. Fix: <what the plan should say>.
```

APPROVE means you would let implementation start from this text as it
stands (nits allowed). Reply with that text only.
