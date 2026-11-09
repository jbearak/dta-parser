# Gate 1, round 2: plan 0025 revision 2

Judges as in round 1. Both returned **CHANGES**. Sonnet marked every
round 1 id resolved except S1 (in part); Sol kept S1/S2, S4, S9/O5,
S10/O6 and S14 open.

## Findings and what revision 3 did

| id | finding | answer in revision 3 |
|---|---|---|
| Sonnet F1, Sol S1/S2 (blocker) | the `Expr` form of `is_missing` raises on Categorical and Enum (and Binary, List); `dk.by` via `na_tag` raises on Binary | the `Expr` is `is_null() \| to_physical().cast(Float64, strict=False).is_nan().fill_null(False)`, as `_na_tag` builds its bits; checked in polars 2.1.0 on Float32, Int64, Boolean, Decimal, Date, Duration, Time, Categorical, Enum and Null (right) and Binary (raises); Binary, List, Array, Struct and text are named as not for the `Expr` form; `dk.by` takes the same dtypes, a Binary key raising; tests for each, the R expression the same |
| Sonnet F2 | the ABI bump contradicts "dtatools unchanged" (`DTAPARSER_ABI <- 3L`, exact match, `test-seam.R`) | the bump to 4 is stated with its reason (datakit needs the callables at load), and `init.c`, datakit's and dtatools' `zzz.R` and both `test-seam.R` change; dtatools' `save_dta` re-export stays |
| Sonnet F3 (nit) | polars `save_dta` and `missing_letters` | the polars methods take `missing_letters = TRUE`, as Python's do, through `_frame.prepare`'s rule |
| Sonnet F4 (nit) | the renamed ADR's own title; an index | its title line and text follow; there is no ADR index |
| Sol S4 | the error enum lacks `KeyError` (unknown name) and `IndexError` (bad position) | variants for each exception raised today, `KeyError` and `IndexError` included; `prefix()` stays `ValueError`-only; the baseline test covers both formats, from paths and from bytes or file objects |
| Sol S9/O5 | `fixed_width_to_dta` writes long labels (320 UTF-8 bytes, cut with a warning; `long_labels` test), not 80 characters | the 80-character claim is cut; the real behaviour is described and tested (a 200-character ASCII label whole, 200 "é" cut to 160 with the warning) |
| Sol S10/O6 | `reinterpret(UInt64)` fails on Float32; value-label JSON loses tagged codes | Float32 compared through UInt32; value labels written as `{set, code, text}` records with `code` a number or `"."`, `".a"` ... `".z"`; fixtures with a shared text and labels on `.`, `.a`, `.z` |
| Sol S14 | R-multiverse has no Linux binaries for Ubuntu 24.04 or R 4.5 | per matrix entry: binaries on macOS and Windows, a source install with `NOT_CRAN=true` (prebuilt Rust library) on Ubuntu 24.04; a step that must load polars and nanoarrow; `DATAKIT_REQUIRE_POLARS=true` turns a skip into a failure in CI |
