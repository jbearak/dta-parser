# Gate 1 brief: plan 0021 (datakit in TypeScript)

You are a design reviewer for the repository at the working directory
(dta-parser: Stata `.dta` and Parquet I/O in R, Python, Julia and
TypeScript). Read `AGENTS.md` first and follow its rules: never run or
look for Stata, never read official Stata documentation. Do not edit,
commit or push anything; this is a read-only review.

## What to review

- `docs/plans/0021-datakit-typescript.md` (the plan under review) and
  `docs/adr/0035-datakit-in-typescript.md`.
- Earlier rounds of this review, if any: `docs/judging/datakit-typescript/round-*.md`.
  Check that every earlier finding was answered, and do not re-raise one
  the plan answered unless the answer is wrong.

Context to read as needed:

- Plan 0019 (`docs/plans/0019-datakit-packages.md`), especially "TypeScript:
  Parquet stays in `@jbearak/dta-parser`", which this plan reverses, and
  ADR 0034; its review record `docs/judging/datakit-design/`.
- Plan 0020 (`docs/plans/0020-factor-characteristic.md`).
- The npm package: `js/src/*.ts` (`index.ts`, `parquet.ts`, `wasm.ts`,
  `node.ts`, `values.ts`), `js/build.mjs`, `js/package.json`,
  `docs/typescript.md`, `docs/research/parquet-typescript.md`.
- The Rust FFI: `crates/dta-ffi/` (`Cargo.toml`, `src/lib.rs`, `wasm.rs`,
  `parquet_wasm.rs`, `native.rs`), `crates/dta/src/fixed_width.rs`,
  `scripts/build-wasm.sh`, `.github/workflows/ci.yml`.
- Python's and Julia's datakits for comparison: `python/datakit/`,
  `julia/Datakit/`.

## The question

The user asked for a datakit package in TypeScript, matching the R,
Python and Julia datakits (data preparation that keeps Stata's labels and
`.a` to `.z`; Parquet as the format the languages exchange; fixed-width
text through SAS setup files). Is this plan's design the right one, and
complete enough to implement without guessing? In particular:

1. The package split (`@jbearak/datakit`; `@jbearak/dta-parser` 2.0.0
   `.dta` only), and two WebAssembly modules rather than one shared one.
2. Whether the `Dataset` API (and no frame library) serves a TypeScript
   user doing data preparation better than the alternatives: hyparquet /
   parquet-wasm / apache-arrow for Parquet, nodejs-polars, Arquero.
3. Correctness risks: `MISSING` object identity, peer dependency, the
   `saveDta` conversions, factor markers, fixed-width, the cargo feature
   split, browser safety of the root entry, CI and packaging.
4. Whether the tests and measurements would prove the change.
5. Anything the plan gets wrong about the code as it is.

Check claims against the code; say where the plan is wrong, missing
something, or over-built. Keep findings concrete and actionable; prefer
fewer, real findings to many speculative ones. Say what you would cut as
well as what you would add.

## Reply format

```
VERDICT: APPROVE | CHANGES
Per question 1-5: one or two lines each.
FINDINGS (only if any):
<id>. [blocker|should|nit] <finding>. Fix: <what the plan should say>.
```

APPROVE means you would let implementation start from this text as it
stands (nits allowed). Reply with that text only.
