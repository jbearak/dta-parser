# Gate 1, round 3: design review of plan 0018 (revision 3)

Same judges, fresh sessions. Both returned **CHANGES**. The judges were
told that Gate 1 judges the design and the documentation plan, and that
the documentation itself is judged at Gate 2.

## Verdicts per library

| language | library | Sonnet | Terra |
|---|---|---|---|
| R | arrow | no (F1: factors from other tools) | yes |
| R | nanoparquet | yes | yes |
| Python | pyarrow | no (F1, F3) | no (F1: install exception) |
| Python | pandas | no (F1, F3) | no (install exception) |
| Python | polars | no (F1) | no (install exception) |
| Julia | Parquet2.jl | yes | no (install exception) |
| TypeScript | hyparquet (+ writer) | yes (needs F2) | no (install exception) |
| TypeScript | parquet-wasm | yes (needs F2) | no (install exception) |

Every round-1 and round-2 finding was marked resolved by both judges.
Both judged the declines (nested data, native results not gated,
predicate pushdown) reasonable.

## Findings and what revision 4 did

| id | finding | answer in revision 4 |
|---|---|---|
| Terra F1 (blocker) | Leaving task 1 out of the pass rule for an unpublished package lets a worse install pass | Task 1 stays in the rule. If an unpublished package's install scores below another library's, Gate 2 fails for that language and the user is asked. (Sonnet had judged the exception reasonable; Terra's stricter reading is the user's own rule) |
| Sonnet F1 | Dictionary columns from other tools come back as text | Read dictionary types from `ARROW:schema` when there is no profile entry: factor, `category`, `CategoricalArray`, `DictionaryColumn`, levels in order of first appearance, `ordered` from the schema. New row in the exactness table; in PR 4 |
| Sonnet F2 | TypeScript `auto` trusts statistics | Every decoded value is checked; a value beyond ±2^53 in a `NumberColumn` is an error naming the column, row and `int64: "bigint"`. The undefined "unreliable writers" wording is gone |
| Sonnet F3 | pandas index | Written as columns only, as `write_dta`; `reset_index()` advice; an index pandas stored (named in its `pandas` key) is restored on read |
| Sonnet F4 | "Same argument names" overstated | "where the meaning is the same" |
| Sonnet F5 | Julia `:error` friction | The first example for other tools' files uses `:truncate`; the error message gives the exact call |
| Sonnet F6 | Size comparison uneven | PR 7 records the module size with Parquet; the reason is dropped if it no longer holds |
| Sonnet F7 | Python unsigned with nulls, decimals | Stated: float64 (32-bit) or `UInt64`; `Decimal` always |
| Sonnet F8 | R's PR 3 documents types that arrive in PR 4 | PR 3 errors on them by name as not yet read; PR 4 completes the table |
