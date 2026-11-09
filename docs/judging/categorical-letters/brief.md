# Gate 1 brief: plan 0022 (Parquet categoricals that keep `.a` to `.z`)

You are a design reviewer for the repository at the working directory
(dta-parser: Stata `.dta` and Parquet I/O in R, Python, Julia and
TypeScript). Read `AGENTS.md` first and follow its rules: never run or
look for Stata, never read official Stata documentation. Do not edit,
commit or push anything; this is a read-only review.

## What to review

- `docs/plans/0022-categorical-letters.md` (the plan under review).
- Earlier rounds of this review, if any:
  `docs/judging/categorical-letters/round-*.md`. Check that every earlier
  finding was answered, and do not re-raise one the plan answered unless
  the answer is wrong.

Context to read as needed:

- `docs/parquet.md` ("The file", "Missing values", "The profile", "What
  other tools see"), the format this changes.
- The core: `crates/parquet/src/write.rs` (`Values::Categorical`,
  `FillCodes`, `holds_letters`, `profile_for`, `schema_for`,
  `Encoder::column`), `profile.rs` (`Logical`), `read.rs`
  (`check_widened`, the levels warning), `columnar.rs`.
- The bindings: `crates/dta-ffi/src/parquet_wasm.rs` and
  `js/datakit/src/parquet.ts` (TypeScript), `python/src/parquet.rs`,
  `python/src/arrow/*.rs` and `python/datakit/datakit/` (Python),
  `r/dtaparser/src/rust/parquet_r.rs` and `r/datakit/R/parquet.R` (R),
  `julia/Datakit/src/parquet.jl` and `parquet_write.jl` (Julia).
- Plans 0018, 0019, 0020 and 0021 for the decisions this builds on.

## The question

The user asked that the project's Parquet categoricals keep `.a` to `.z`,
and that R, whose factor cannot hold them, read such a column as labelled
doubles. Is this plan the right design, complete enough to implement in
all four languages without guessing, and would its tests prove it? In
particular: the file representation and its effect on other tools and
older readers; the read-side check and fallback; what each language
reads and writes; round trips between languages; TypeScript `saveDta`;
anything the plan gets wrong about the code.

Check claims against the code. Keep findings concrete and actionable;
prefer fewer, real findings to many speculative ones. Say what you would
cut as well as what you would add.

## Reply format

```
VERDICT: APPROVE | CHANGES
Per area (file format, core, each language, tests): one or two lines each.
FINDINGS (only if any):
<id>. [blocker|should|nit] <finding>. Fix: <what the plan should say>.
```

APPROVE means you would let implementation start from this text as it
stands (nits allowed). Reply with that text only.
