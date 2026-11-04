# Gate 1, round 6: check of revision 6

**Terra: APPROVE**, yes for every language and library, no findings.

**Sonnet: CHANGES**, H1 to H5 resolved, yes for every library (pandas
once I1 is fixed):

| id | finding | answer in revision 7 |
|---|---|---|
| I1 (should) | A `%td` column holding a time of day would be truncated to a date | An error naming the column and row, saying to drop the format to write a timestamp; tested |
| I2 (nit) | "Smaller" than what | Brotli-compressed module against parquet-wasm's 456 KB read-only build |
| I3 (nit) | "The index" paragraph unwrapped | Re-wrapped |
| I4 (nit) | Python cell of the `ARROW:schema` dictionary row silent on order | Unordered in every cell |
