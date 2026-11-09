# Gate 1, round 2: plan 0021 revision 2

Both judges returned **CHANGES**; both said the round-1 findings were
answered.

| question | Sonnet | Terra |
|---|---|---|
| 1. package split, two modules | sound; Rust split now compiles on paper | reasonable; round 1 answered |
| 2. `Dataset`, no frame library | right call; types consistent | defensible; conversion contract misses strings and untyped numbers |
| 3. correctness risks | adequately specified; fixed-width peak understated | factor markers and the reader interface |
| 4. tests prove it | yes; one test missing | broad; add the conversion and factor cases |
| 5. wrong about the code | `TableInfo` has no `timestamp` | the same, and `TableReader.variables` is the base `Variable` |

## Findings and what revision 3 did

| id | finding | answer in revision 3 |
|---|---|---|
| T1 (blocker) | `saveDta` has no rule for Parquet `string`, so the catch-all rejects it | `string` becomes strN up to 2,045 bytes, else `strL`; `binary` `strL`; tested |
| T2 | untyped numbers with fractions | integer storage only when every value is whole; else double; tested with 1.5 |
| T3 | a categorical with `.a` to `.z` against plan 0020's marker checks | a Parquet categorical cannot hold letters; one built with a letter keeps it and gets no marker, reading back as labelled numbers; the round-trip promise is for categoricals without letters |
| S-F1, T4 | `TableInfo` has no `timestamp`; `Variable` has no `unit`, `timeZone`, `categorical` | 2.0 adds optional `TableInfo.timestamp` and optional `Variable.unit`, `timeZone`, `categorical`; `readDataset` tested on a reader that implements only the interface |
| S-F2 | wasm memory never shrinks; both modules' memory at once | datakit replaces its instance after the conversion when no Parquet reader is open; the peak stated; `DTA_TOO_LARGE` checked before any copy; a bound for the largest NSFG file |
| S-F3 | `stataKey`, `stataKeys` aliases | move to `./format` with `dtaKey`, the same function objects |
| S-F4 | the registry has no guard | key `.../missing/v1`; what is found is used only if it has the expected 27 frozen objects; tested |
| S-F5 | integer ranges and the unsigned types in the union | Stata's ranges stated; `uint8` to `uint64`, `time`, `decimal` in the union |
| T5 | `readDatasetAsync` missing from the table; ADR said `Dataset` is a `WriteDataset` and promised nodejs-polars recipes | table and ADR reconciled |
