# Gate 1, round 7: check of plan 0019 revision 7

**Terra: APPROVE**, yes for every language and library, no findings.

**Sonnet: APPROVE**, yes for every language and library, three nits,
fixed in the approved text:

- The out-of-range rule applied only to `read_dta`'s `%tc`; it now
  covers DOUBLE dates and timestamps in Parquet, `%td`, and
  `save_parquet` of a letter column past what a double of seconds
  holds, each with an edge test.
- "Converted back to seconds as a double" now says how (`n / 10^6`),
  since `n * 1e-6` gives a different double.
- An infinity, or a NaN that is not a letter, in a date or timestamp
  column is named as an error.

Gate 1 passed: both judges say the planned API and documentation would
serve a user better than polars, pyarrow and pandas (Python, for files
with a dta profile, with polars itself recommended for lazy and general
Parquet work), Parquet2.jl and DuckDB.jl (Julia), and agree that
Parquet stays in `@jbearak/dta-parser` for TypeScript.
