# R's datakit has no polars functions, and the Arrow interface is removed

Supersedes ADR 0041 (polars in R and Python) and the part of ADR 0042
that keeps `crates/arrow` for it. ADR 0038 stands again:
datakit's frames are tibbles.

On 2026-11-10 the user decided to rebuild datakit's Parquet reader and
writer on arrow-rs, in a repository of its own, so that the code is
short enough to review before it is used on real data. polars support
is not needed for that, and the user does not know whether they will
use it; carrying it into the new package would mean a hand-built Arrow
bridge kept alongside arrow-rs. It is left out, and can come back as an
issue in the new repository.

**Removed**: `read_parquet_pl()`, `read_dta_pl()`,
`read_fixed_width_pl()`, the polars methods of `save_parquet()` and
`save_dta()`, `datakit_meta`, `is_missing()` and `is_na()` (datakit's;
dtatools' `is_missing()` stays), `tagged_na_pl()`, `na_tag_pl()`,
`is_tagged_na_pl()` and `datakit_by_pl()`; `crates/arrow` (the Arrow C
data interface by hand, and Parquet and `.dta` reads and writes through
Arrow memory); dtaparser's `arrow_r.rs` and the five C callables it
backed, among them `dtaparser_fixed_width_dta`; datakit's `meta.c`;
their tests, benchmark, results and docs.

## Consequences

- dtaparser's ABI number is 5: a datakit or dtatools built for 4
  refuses it, and the reverse.
- `save_parquet()` is a plain function, and datakit's `save_dta()` is
  dtaparser's, re-exported.
- `crates/parquet` keeps its Arrow output (`columnar.rs`), which no
  other crate calls now; it goes with the rest of `crates/parquet` when
  datakit moves.
- `compat/parquet/categorical_marker.sh` checks one direction only:
  TypeScript writes the `dtaparser_categorical` marker and R reads it.
- The plans and research that built the polars path (0019, 0024, 0025,
  0027, `docs/research/polars-2*`) stay as the record.
