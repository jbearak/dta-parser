```json
{"A": {"1": [2, 3, 3, 2], "2": [2, 3, 3, 2], "3": [2, 3, 2, 3], "4": [3, 3, 2, 3], "5": [2, 3, 2, 3], "6": [2, 3, 3, 3], "7": [2, 2, 2, 3], "8": [2, 3, 3, 3], "9": [2, 3, 3, 3], "10": [2, 3, 3, 3], "11": [3, 2, 3, 3]},
 "B": {"1": [3, 3, 1, 3], "2": [3, 2, 2, 2], "3": [1, 3, 2, 2], "4": [1, 2, 1, 2], "5": [3, 3, 3, 2], "6": [0, 0, 0, 0], "7": [1, 1, 0, 1], "8": [3, 2, 2, 3], "9": [1, 1, 1, 1], "10": [0, 0, 0, 0], "11": [2, 2, 2, 2]}}
```

Scores are in the order findability, correctness, completeness, clarity. Below, only scores under 3 are explained.

## Library A

**Task 1, Install** (2, 3, 3, 2)
- Findability 2: the README has an install paragraph, but the R steps are on the R page. The Parquet task list sends the reader on to "Parquet: install", which sends them on to "Install". That is two hops.
- Clarity 2: the install section is long, with several routes (binaries, pak, remotes, source, a clone). The package names are hard to tell apart.

**Task 2, Read a whole file** (2, 3, 3, 2)
- Findability 2: the Parquet page has a heading for the task, but it only links to the R page's "Read a Parquet file" and type-table sections.
- Clarity 2: the examples assume `survey.dta` from an earlier section. Value labels and tagged NAs are used before they are explained.

**Task 3, Read some columns** (2, 3, 2, 3)
- Findability 2: the Parquet page has a heading, then a link to the R page.
- Completeness 2: the R page says names or tidyselect, order kept, and that an unknown name is an error listing the columns. It never says whether numeric positions work. Positions are only in the Python error text.

**Task 4, Read a range of rows** (3, 3, 2, 3)
- Completeness 2: `skip` and `n_max` are shown, and the docs say only the needed row groups and pages are read. The docs do not say what a range past the end of the file does. The cost is only "quick".

**Task 5, Schema and metadata** (2, 3, 2, 3)
- Findability 2: the heading is only a link on the Parquet page.
- Completeness 2: `read_parquet_info()` gives rows, row groups, codecs, the data label, notes and column types. The R page does not show the file's raw key-value entries. Only the Julia note mentions the footer's key-value entries.

**Task 6, Value labels and variable labels** (2, 3, 3, 3)
- Findability 2: the heading is only a link on the Parquet page.

**Task 7, Dates and timestamps** (2, 2, 2, 3)
- Findability 2: the heading is only a link on the Parquet page.
- Correctness 2: the R type table says the zone is "else UTC". The dates section says a `POSIXct` with no `tzone` comes back with none. A reader could be unsure which holds.
- Completeness 2: units and zones are covered, including nanosecond truncation and INT96. The R page says nothing about values outside the range a `Date` or `POSIXct` can hold. It does not explain what a naive timestamp is, apart from one row in the Parquet page's type table for polars.

**Task 8, Write a table** (2, 3, 3, 3)
- Findability 2: the heading is only a link on the Parquet page.

**Task 9, Write labels and check them** (2, 3, 3, 3)
- Findability 2: the heading is only a link on the Parquet page.

**Task 10, Keep .a to .z** (2, 3, 3, 3)
- Findability 2: the heading is only a link on the Parquet page, though the README names the feature.

**Task 11, Read a file another tool wrote** (3, 2, 3, 3)
- Correctness 2: the R page says "every encoding" is read, but the error table lists BIT_PACKED as not read. That is a small overclaim.

### Library A, task scores

| Task | Score |
|---|---|
| 1 | 2.50 |
| 2 | 2.50 |
| 3 | 2.50 |
| 4 | 2.75 |
| 5 | 2.50 |
| 6 | 2.75 |
| 7 | 2.25 |
| 8 | 2.75 |
| 9 | 2.75 |
| 10 | 2.75 |
| 11 | 2.75 |
| **Total** | **28.75** |

## Library B

**Task 1, Install** (3, 3, 1, 3)
- Completeness 1: the README gives `install.packages("nanoparquet")` and nothing else. There are no supported platforms or R versions, and nothing on what to do if installation fails.

**Task 2, Read a whole file** (3, 2, 2, 2)
- Correctness 2: the README says nested types are unsupported. The list-columns article says flat list columns are read and written. The two contradict each other on what is refused.
- Completeness 2: the Parquet-to-R type mapping is only linked, and its page is not in the material. Some of the mapping appears in the options text (int64, factors from the Arrow metadata, difftime). The limits are listed.
- Clarity 2: the README gives no result for the read call.

**Task 3, Read some columns** (1, 3, 2, 2)
- Findability 1: the README features list names the subset-of-columns feature but never shows how. The answer is only in the `read_parquet()` reference.
- Completeness 2: names or indices are accepted, order is kept, and selecting a column twice is an error. What happens with a name not in the file is not said.
- Clarity 2: there is no example.

**Task 4, Read a range of rows** (1, 2, 1, 2)
- Findability 1: the README is silent. The only statements are in the conference-talk file, which says it "cannot read a subset of the rows" and lists it as a future plan.
- Correctness 2: the statement is dated, and the README does not repeat it.
- Completeness 1: it says only that the feature is absent. It gives no workaround and no cost.
- Clarity 2: the statement is clear but terse.

**Task 5, Schema and metadata** (3, 3, 3, 2)
- Clarity 2: the README shows the calls but not their output. The reference lists the columns well, and the talk file shows the output.

**Task 6, Value labels and variable labels** (0, 0, 0, 0)
- Nothing in the material covers variable labels or value labels. Factors are only mentioned as an Arrow-metadata feature.

**Task 7, Dates and timestamps** (1, 1, 0, 1)
- The material only says "temporal types" can be written. It gives no mapping of units or time zones. It mentions difftime and a timestamp type in a list. The type mapping is only linked.

**Task 8, Write a table** (3, 2, 2, 3)
- Correctness 2: the README says only flat data is written, but lists are written.
- Completeness 2: the call, the snappy default, the other codecs, the level ranges, the row-group default of 122,880 and the encodings are all covered. The mapping from each R type is not in the material, though `infer_parquet_schema()` is offered to show it.

**Task 9, Write labels and check them** (1, 1, 1, 1)
- Only the generic `metadata` argument of `write_parquet()`, for extra key-value entries, is found in the function reference. `read_parquet_metadata()` can show them. Labels are never mentioned.

**Task 10, Keep .a to .z** (0, 0, 0, 0)
- Nothing is covered.

**Task 11, Read a file another tool wrote** (2, 2, 2, 2)
- Findability 2: the Limitations list is in the README, but the encodings and codecs are only in the talk file and the reference.
- Correctness 2: the README and the list-columns article contradict each other on nested data.
- Completeness 2: the limits are listed (nested types, INTERVAL, UNKNOWN, codecs, encryption, URLs). Which types are read is only linked. What other tools see in its files is covered only for factors and lists.
- Clarity 2: the limits are short, but the contradiction needs sorting out.

### Library B, task scores

| Task | Score |
|---|---|
| 1 | 2.50 |
| 2 | 2.25 |
| 3 | 2.00 |
| 4 | 1.50 |
| 5 | 2.75 |
| 6 | 0.00 |
| 7 | 0.75 |
| 8 | 2.50 |
| 9 | 1.00 |
| 10 | 0.00 |
| 11 | 2.00 |
| **Total** | **17.25** |

## Totals

| Library | Total (max 33) |
|---|---|
| A | 28.75 |
| B | 17.25 |
