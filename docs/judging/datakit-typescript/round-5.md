# Gate 1, round 5: plan 0021 revision 5

**Sonnet: APPROVE**, one nit. **Terra: CHANGES**, two findings.

## Findings and what revision 6 did

| id | finding | answer in revision 6 |
|---|---|---|
| T1 | "a null is `.`" read as covering strings, but `.dta` strings have no missing value and `writeDta` rejects one | a null in a numeric, date or timestamp column is `.`; a null in a `string` or `binary` column is an error naming the variable and row, saying to fill it; tested for both |
| T2, S-N1 | a restored factor keeps a reference to a set that left `valueLabels`; a set not named after its column comes back under the column's name | a restored variable has `valueLabels` `""` and keeps the set's name as `categorical.labelSet`; `saveDta` names the set from `labelSet`, else the column, then `name_2` on any clash; through Parquet (no place for `labelSet`) the column's name; tested with `region` labelled by `regions`, and `saveParquet` of a restored dataset |
