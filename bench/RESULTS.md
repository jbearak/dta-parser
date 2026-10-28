# Benchmark results

Machine: Apple M4 Max, 16 cores, 128 GB, macOS 26.7.1, R 4.6.1, haven
2.5.5. Each run is a fresh R process under `/usr/bin/time -l`.

## Writing (`sh bench/write.sh`)

"RSS over data" is the run's peak resident memory minus that of a run
that makes the same data without writing it.

| case | tool | write s | peak RSS MB | RSS over data MB | file MB |
|---|---|---|---|---|---|
| numeric (5M rows, 10 columns) | haven | 1.76 | 588 | 40 | 324 |
| numeric | dtatools | 0.18 | 556 | 8 | 300 |
| strN (5M rows, 3 columns) | haven | 0.86 | 265 | 33 | 147 |
| strN | dtatools | 0.25 | 241 | 9 | 147 |
| strL, 200k rows of 20 texts | haven | 0.24 | 94 | 20 | 2 |
| strL, repeated | dtatools | 0.15 | 74 | 0 | 2 |
| strL, 100k distinct texts | haven | 0.54 | 1176 | 668 | 289 |
| strL, distinct | dtatools | 0.24 | 516 | 8 | 289 |
| 3 strL columns, 100k rows of 50 texts each | haven | 0.31 | 102 | 9 | 2 |
| 3 strL columns | dtatools | 0.29 | 94 | 1 | 2 |

dtatools reads R's vectors in place and builds rows 8 MiB at a time, so
its overhead is that buffer, plus, for each strL column, a table of its
distinct texts (borrowed, not copied). haven's numeric file is larger
because it stores R integers that fit a byte as long. The page cache was
warm; writes end in the cache either way.

## Reading (`sh bench/read.sh <dir>`)

Files from `bench/make_large.R`, written by dtatools with a fixed seed:
`long.dta` (10M rows, 12 variables of every storage type, 0.74 GB) and
`wide.dta` (1.5M rows, 400 doubles, 4.8 GB, past 4 GiB). readstata13
0.11.0, pandas 3.0.5, Node 26. Timings start after each tool's packages are loaded
and stop when the read returns (for npm, opening the file is inside).
The page cache was warm. A cold-cache run
needs `purge`, which needs admin rights this machine's runs did not have.
Rows are stored row-major, so even a 5-variable read passes over every
byte of the file.

| read | seconds | peak RSS MB |
|---|---|---|
| long.dta, all 12 variables: dtatools | 5.50 | 1761 |
| long.dta, all 12 variables: haven | 19.46 | 2107 |
| long.dta, all 12 variables: readstata13 | 18.26 | 2102 |
| long.dta, all 12 variables: pandas | 2.46 | 3962 |
| long.dta, all 12 variables: npm | 2.15 | 1915 |
| wide.dta, 5 of 400 variables: dtatools | 0.24 | 154 |
| wide.dta, 5 of 400 variables: haven | 1.75 | 176 |
| wide.dta, 5 of 400 variables: readstata13 | 1.20 | 150 |
| wide.dta, 5 of 400 variables: pandas | 2.80 | 9285 |
| wide.dta, 5 of 400 variables: npm | 0.22 | 254 |
| wide.dta, 200 rows at the start: npm | 0.005 | 57 |
| wide.dta, 200 rows at the end: npm | 0.004 | 57 |

Of dtatools' 5.5 s on `long.dta`, 4.6 s go to one variable of 10M
distinct strings. That is R making 10M new strings, which haven and
readstata13 pay too. The other 11 variables take 0.55 s. Against the
plan's target of 1.5× the fastest full read: within R, dtatools reads
3.3–3.5× faster than haven and readstata13. Across languages, R's
string cost puts it outside 1.5× of npm and pandas on this file. The npm
package reads fastest of all five.

The downstream workload, 3 of 302 variables from an 11.8 GB
release-115 file with 15.1M rows (warm cache), takes 0.8 s and 464 MB
with dtatools, against 15.7 s and 492 MB with haven.

## Grouping and comparing (`Rscript bench/group_case.R`)

10M rows: a `dta_num` column of 50 values plus `.`, and a string column
of 300 values.

| operation | seconds |
|---|---|
| `dta_group_tag(a, s, missing = TRUE)` | 0.80 |
| `dta_group_id(a, s, missing = TRUE)` | 0.69 |
| `tab(a, missing = TRUE)` | 0.24 |
| `unique(a)` | 0.10 |
| `a == 3` | 0.05 |

All of them work on one order key per value (ADR 0009). Grouping is a
single radix `order()` over the keys followed by a pass for run
boundaries; rows are never pasted together.
