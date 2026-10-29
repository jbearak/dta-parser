```json
{"A": {"1": [3,3,2,3], "2": [2,3,1,2], "3": [3,3,2,3], "4": [3,3,2,3], "5": [3,3,2,2], "6": [3,3,2,3], "7": [3,3,2,2], "8": [3,2,2,2], "9": [3,3,2,2], "10": [3,1,2,2]},
 "B": {"1": [3,3,3,3], "2": [3,3,3,3], "3": [3,3,3,3], "4": [3,3,3,3], "5": [3,3,3,3], "6": [3,3,3,3], "7": [3,3,3,3], "8": [3,3,3,3], "9": [3,3,3,3], "10": [3,3,3,3]}}
```

## Reasons for scores below 3 (Library A)

Task 1: Completeness 2: supported Python versions are not stated (the reader is sent to PyPI). Platforms are only "windows, mac, linux". Failure advice covers compiling, iconv and zlib.

Task 2: Findability 2: the README's read example uses `read_sas7bdat`. `read_dta` appears only in the function table and the API reference. Completeness 1: it gives the return type (dataframe plus meta) but never says what each Stata storage type becomes. Clarity 2: the reader has to infer the dta call from the SAS example.

Task 3: Completeness 2: it says the match is case sensitive and the argument must be a list. It does not say whether column order is kept or what happens with a name that is not in the file.

Task 4: Completeness 2: `row_offset`, `row_limit` and chunking are covered. The behaviour of an out-of-range request is not stated.

Task 5: Completeness 2: `metadataonly` and the meta fields are covered, as is `file_label`. Display formats and storage types are only hinted at through `original_variable_types`, which is not clearly explained for dta. Clarity 2: the examples use SAS and print no output.

Task 6: Completeness 2: the label-set lookup, `apply_value_formats` and `set_value_labels` are covered. What happens to codes that have no label is not said. Examples use sav and sas rather than dta.

Task 7: Completeness 2: there is no list of which Stata display formats become dates, and no epoch. The switch to turn conversion off, `disable_datetime_conversion`, is not in the dates section; it appears under Known limitations and in the API reference. The overflow error is mentioned. Clarity 2: the example shows no result and the Stata formats are not named.

Task 8: Correctness 2: the README's write example uses `write_sav`, not `write_dta`. The type table is loose ("integer (stata)" for int32, an `np.float` entry). Completeness 2: the version range 8 to 15 and the default 15 are only in the API reference. What counts as an error is mostly absent. Clarity 2: no dta write example and no output.

Task 9: Completeness 2: the attach arguments are covered, but reading back to check is not shown. The Writing value labels example uses `write_sav`. Clarity 2: the same sav-only example, with no output and no read-back.

Task 10: Correctness 1: the Stata writing example is broken. It has a missing brace and calls `write_sav` with `missing_ranges`, the SPSS arguments. It also mixes letters into a numeric column, which would mislead a user. Completeness 2: reading `.a` to `.z` with `user_missing` and `missing_user_values` are covered. Nothing is said about keeping them through filtering and sorting. Clarity 2: examples show no output.

Library B has no score below 3.

## Task scores

| task | A | B |
|---|---|---|
| 1 | 2.75 | 3.00 |
| 2 | 2.00 | 3.00 |
| 3 | 2.75 | 3.00 |
| 4 | 2.75 | 3.00 |
| 5 | 2.50 | 3.00 |
| 6 | 2.75 | 3.00 |
| 7 | 2.50 | 3.00 |
| 8 | 2.25 | 3.00 |
| 9 | 2.50 | 3.00 |
| 10 | 2.00 | 3.00 |

Common total (tasks 1 to 9): A = 22.75, B = 27.00.
Task 10 (reported separately): A = 2.00, B = 3.00.
