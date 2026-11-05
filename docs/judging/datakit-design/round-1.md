# Gate 1, round 1: design review of plan 0019 (revision 1)

Judges: Claude Sonnet 5.5 (`claude-sonnet-5-5`) and GPT-6.1 Terra
(`gpt-6.1-terra`), each in a fresh session with the plan, ADR 0034, plan
0018 and its ADRs, the Parquet docs and research notes, and the code.
Both returned **CHANGES**.

## Verdicts per library

| language | compared with | Sonnet | Terra |
|---|---|---|---|
| Python | polars | yes for profiled files, no for plain Parquet (say when to use polars); after S1 | no |
| Python | pyarrow | yes, with the same note | no |
| Python | pandas | yes | no |
| Julia | Parquet2.jl | yes, after S2 | no |
| Julia | DuckDB.jl | yes | no |
| TypeScript | keep Parquet in the npm package | agree (reason 3 weak) | yes (hyparquet, parquet-wasm) |

## Findings and what revision 2 did

S = Sonnet, T = Terra.

| id | finding | answer in revision 2 |
|---|---|---|
| T1, S1 | Positional letters in `meta.missing` can attach to the wrong rows; the length-and-null check misses same-length reorderings; generated code hits a `KeyError` for a column with no letters in a window; `!=` on an Enum is null on valued rows; polars sorts nulls first and unstably | Two ways to keep letters: `meta.missing` (default) and companion columns `x_letter` (`letters="columns"`, `letters_to_columns`), which follow rows and are what a translator generates. `meta.letters(name)` is total. `save_parquet` checks a digest of each column's values as read, described as validation, not proof, with the case it cannot see. The traps (`ne_missing`, `nulls_last=[True, False]`, `maintain_order`) lead the section. Recipes for new letters, replacing a letter, new columns, joins, aggregation |
| T2 | Fractional R dates, sub-microsecond timestamps and Int64 with letters cannot be exact in polars | DOUBLE dates and timestamps that are not exact are errors naming the column and row, with `timestamps="truncate"`; Int64, UInt32/64 and Boolean with letters stay errors (plan 0018); R fixtures for each edge in the cross-language test |
| T2, S6 | "polars holds every type exactly" overstated; UUID, FLOAT16, INTERVAL, DECIMAL beyond 38, `"unit": "s"` missing from the table | Table completed: DECIMAL above 38 reads as String; UUID as Binary; FLOAT16, INTERVAL errors; `"s"` reads as "ms" |
| T3 | `factors=True` underspecified; `pl.Enum` rejects repeated texts; R keeps unlabelled values as text | Python follows R's `labelled_factor` exactly (levels by value, unlabelled values as text, repeated texts one level); letters are not lost, unlike R; cross-language test of levels |
| S8 | `factors=True` dropped the set name `labels()` needs | The set name stays; what saving an Enum column with a set does is stated |
| T4, S2 | `set_stata_code!` needs a `DtaColumn`; `vcat` and `combine` lose letters per DtaParser's own test; `transform!` drops `:note` metadata | Recipe converts in place first; the keep/lose list follows `test/dataframes.jl`; joins tested in the PR, not promised; "a DataFrame whose letter columns are `DtaColumn`s" |
| T5, S7 | `Meta`'s mutation, copying, equality and errors undefined; `@dataclass` equality fails on Series; `rename` must alias; `sort` can become false | `eq=False` with a defined `==` using `Series.equals`, `copy()`, fresh defaults, `labels` live with `KeyError`, `rename`/`select` deep copies with errors and the `sort` cut; `sort` checked when saving and dropped with a warning if false |
| T6, S6 | Reader returns types the writer rejects; unsigned widened; no key-value metadata in the info call; Enum ordering | The core's writer gains unsigned types and TIME; Decimal stays an error with the reason; the round-trip test lists what cannot round trip; `key_value` in `read_parquet_info`; Enum ordering stated |
| T7, S3 | The Arrow path and the speed claim are unproven | A spike before revision 3 measures decode into Arrow and import into polars on DHS, NSFG and synthetic files (`docs/research/parquet-polars-spike.md`); write comparison's input preparation and memory stated; what happens on a thread-count miss stated |
| T8, S10 | Install, CI and integration tests while nothing is published; the PyPI name clash; the cross-language test across independent PRs | Install from a checkout documented and tested in a clean environment; ABI mismatch and offline sdist tests; the clash stated; the Python PR does R–Python, the Julia PR adds Julia |
| S4 | dta_parser imports pandas eagerly, so datakit would too | dta_parser loads its pandas names lazily; the install still pulls pandas, stated; import time measured |
| S5 | No path from `.dta` to polars in Python | `read_dta` and `save_dta` in Python's datakit, on the same native path; `read_fixed_width` uses it |
| S9 | The native contract is undefined; exact pin plus ABI is redundant | `_native.ABI_VERSION` in Python; `DtaParser.Internals` in Julia; `>=0.3,<0.4` plus the ABI check; Datakit's precompile workload and time to first read |
| S11 | Julia's argument order and keyword overrides | Stated |
| S12 | The npm README does not mention Parquet in its opening; reason 3 restates the situation | PR 4 changes the README opening and `package.json` description; reason 3 dropped |
| S13 | Tests to add (windows without letters, `columns=`, readback by other tools, info's `meta`, Categorical vs Enum) | Added |
| S14 | Tuple return, `fill_null` breaks the check, name clash, tags | Docs say reads return a tuple; the error names `meta.missing.pop`; the clash is in the README; tags when the user publishes |
| S6 | Say when to use polars directly | First paragraph of the Python Parquet section |
