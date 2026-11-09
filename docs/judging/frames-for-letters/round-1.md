# Gate 1, round 1: plan 0024 revision 1

Judges: Claude Sonnet 5.5 (`claude-sonnet-5-5`, effort high) and GPT-6.1
Sol (`gpt-6.1-sol`, reasoning effort high), each in a fresh session
given `brief.md`. Both returned **CHANGES**.

## Findings and what revision 2 did

S = Sonnet, O = Sol.

| id | finding | answer in revision 2 |
|---|---|---|
| S1, O5 (blocker) | "without a copy, through the buffer protocol" cannot work: the build is `abi3-py310`, and the buffer protocol is not in the abi3 API before 3.11 (`lib.rs:5`); no ownership contract | numeric buffers go to numpy through a native object holding the table's `Arc` with `__array_interface__` (writable), kept as the array's `base`; text is copied; `ABI_VERSION` goes up; a test keeps arrays and slices after the table is deleted and collected |
| S3, O4 (blocker) | a `.`-only column stays `float64` (`x != 1` true on `.`, `groupby` drops it) while a lettered one is a `DtaArray`: semantics change with the rows read; NaN and null collapse | one rule in both Python packages: every byte/int/long/float/double column holding any missing value in the rows read is a `DtaArray` (dta_parser's `read_dta` too, stage 3); INT64, unsigned and BOOLEAN with nulls are nullable types (no letters possible); a NaN value reads as `.`, with the probe showing a nullable `Float64` turns an unmasked NaN into `<NA>` under `x * 2`; window tests |
| S2 | no write dtype table; `category` marker; storage fallback; NaN payloads; `ParquetInfo`, `_same`/`_deep`, `read_fixed_width` | a "Columns written" table; `category` gets `dtaparser_categorical`; widening as `stored()`/`_choose`; every plain NaN is `.`; `ParquetInfo` frames, `_same`/`_deep` and `read_fixed_width` named |
| S4, O3 | `missing.a == s` is a plain `False`, `missing.a < s` raises | `MissingValue` returns `NotImplemented` for list, array, Series and Index operands; both orders tested |
| S5 | operand kinds (nullable arrays, `pd.NA`, `None`, lists with letters, text) | an operand table: NaN, `None` and `pd.NA` are `.`, a `MissingValue` keeps its code, nullable `<NA>` is `.`, text is `TypeError`; each tested |
| S8, O3 | arithmetic: "matches R" overstated (`x ** 0`); ufuncs bypass; `__pos__` | the rule is stated as "a missing operand's code wins whatever the numbers give", with `x ** 0` named; the R claim is cut; ufuncs and `apply` listed as returning `float64`; unary `+` covered |
| O6 | TIME is scaled to nanoseconds natively; writer rejects Duration | TIME reads as `timedelta64[ns]` (correcting plan 0018 for datakit); `timedelta64` writes TIME(NANOS) within a day, else an error; ms/us/ns tests |
| O1, S6 | `datakit_by()` name collisions; `.suffix`; joins with `na_matches = "never"`; `.by` error | duplicate outputs in one call are an error; an existing frame column is replaced, as dplyr does, and documented; `.suffix` validated; joins keep `"na"`, documented; `.by` shows dplyr's error |
| O1 | cut the syntactic-name restriction | cut; names follow `group_by()` (`rlang::as_label()`) |
| O2 | `summarise()` leaves the result grouped by `x` alone | examples use `.groups = "drop"`; docs explain; `group_vars()` tested |
| S7 | `datakit.read_dta` and `dta_parser.read_dta` must agree | a test compares them on markers, windows, `letters=False`, `factors=True` |
| S9 | naming (`{{ }}`, `.data[[v]]`); letter column by class list; dplyr in Suggests | names by `as_label()`; an explicit class list (`integer64`, `difftime` excluded); dplyr `(>= 1.1.0)` in Suggests, tests skip without it |
| S10 | the polars-only tests cannot all be ported; text dtype | the dropped tests are listed with their replacements; text assertions accept `object` and `str` |
| S (cut) | move the timing line out of stage 2 | moved to ADR 0038 in stage 1 |
