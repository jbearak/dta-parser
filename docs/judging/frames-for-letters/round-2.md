# Gate 1, round 2: plan 0024 revision 2

Judges as in round 1. Both returned **CHANGES**. Every round 1 id was
marked resolved, except S5 (text operands, R2-2), S2 (DECIMAL writes,
O-S2), S7 (parity, O-S7) and S8 (ufuncs, O-S8), answered below.

## Findings and what revision 3 did

R2 = Sonnet's round 2 ids; O = Sol's.

| id | finding | answer in revision 3 |
|---|---|---|
| R2-1 (blocker) | with "any missing value means `DtaArray`", `pd.concat` and `merge` with a numpy column give `object`, `DataFrame.to_numpy()` gives `object`, `cumsum` raises, `rolling` gives all NaN (checked on pandas 3.1.1) | stage 3 gains an operations table: `_get_common_dtype` gives a `DtaDtype` for numpy and nullable numeric types (the narrowest storage holding each type's range), `to_numpy`/`astype(float)` float64, `_accumulate`, `rolling`/`expanding`/`ewm` through float64, `quantile`/`describe`/`corr`/`cov`, `fillna`/`where`/`mask`, `clip`/`round`, `isin`; each tested, including against numpy columns, and `pd.concat` of two windows |
| R2-2 | comparison rule ambiguous: `DtaArray == DtaArray` on shared letters, `x == np.nan`, text | split into an operand table and three row rules: only a `MissingValue` *names* a letter (code equality); otherwise any missing side gives `<NA>` (so `DtaArray == DtaArray` and `x == np.nan` are `<NA>`, as R); text gives all false / all true for `==` / `!=` as nullable `Int64` does, and `TypeError` only for ordering |
| R2-3, O-N1 | `tagged_na`, `na_tag`, `is_tagged_na` undefined over pandas; tagged floats silently become `.` | a "Missing values in the API" section: `tagged_na` returns `MissingValue`; `na_tag` reads `DtaArray` codes and tagged-NaN bits of plain floats, returning `LETTERS` as a `CategoricalDtype`; assignment works on a `DtaArray`, and for a numpy column the docs say to `astype("dta[double]")` (pandas 3 raises `TypeError`, 2.2 upcasts to `object`), with saves refusing `object` columns holding a `MissingValue`; a tagged NaN in a plain float column is written as its letter, as today; tests for each |
| R2-4 | stage 3 changes `dta_parser.read_dta` output without a release, docs or migration note; memory cost | dta_parser 0.4.0; `docs/python.md` and `docs/migration.md` updated; memory (9 bytes a row) named in stage 3 and Risks |
| R2-5 | adapter: zero copy only for columns without missing; BOOLEAN bit-packed; DATE days; aliasing of writable views; write-side array checks; nullable masks | one table per read, nothing shared; zero copy only for numeric columns with no missing value, timestamps and times; native conversion into new buffers for missing-value columns (values and codes, or values and a bool mask for nullable `Int64`/`UInt*`/`boolean`), BOOLEAN and DATE; text, levels and DECIMAL copied into Python objects; writes take C-contiguous arrays the native side checks by type string, shape and layout; tests for each |
| R2-6 | TIME unit changes on round trip; `np.where`/`bool()` on pandas 2.2; date/categorical types with letters vary with the rows read | stated; tested on 2.2; documented beside the numeric rule |
| O-S8 | `DtaArray` inherits `ExtensionArray.__array_ufunc__`, which sends `np.add`, `np.abs` to the operators; `map` gives `MissingValue`s | a "numpy functions" paragraph: operator ufuncs follow the operator rules, others (`np.log`) give `float64`, `map`/`apply` see `MissingValue` and NaN; pinned by tests on both pandas versions |
| O-S7 | parity test impossible: dta_parser has no `letters`/`factors`; `dtaparser_factor` defaults differ | parity on default arguments; the `dtaparser_factor` difference (category in dta_parser, labelled numbers in datakit, plan 0023) and the datakit-only flags are tested against stated results |
| O-S2 | DECIMAL writing exceeds the writer (`write.rs` rejects Decimal; the core has no DECIMAL values) | cut: `Decimal` objects are an error naming the column, as a polars `Decimal` is today |
