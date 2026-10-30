# R-only benchmarks

These predate `bench/run.py` and measure what only dtatools does: writing
from R, survey-shaped string columns and grouping. Same machine as
[../RESULTS.md](../RESULTS.md): Apple M4 Max, 16 cores, 128 GB, macOS
26.7.1, R 4.6.1, haven 2.5.5. Each run is a fresh R process under
`/usr/bin/time -l`.

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

## Survey-shaped string columns (`bench/fresh_case.R`)

`groups.dta` (from `make_large.R`): 15M rows, a string column of 300
values in random order and a byte column of 5 values plus `.`. Each task
starts from a fresh read, so no strings are made yet; "again" times a
second `dta_group_id` after a first. Before is dtatools at ad40bba
(packed columns, ADR 0010); after adds dictionary columns (ADR 0011).
Medians of five fresh processes.

| task | before s | before MB | after s | after MB |
|---|---|---|---|---|
| read | 0.34 | 952 | 0.33 | 344 |
| read, then `dta_group_id(s, a, missing = TRUE)` | 2.23 | 2210 | 1.24 | 1660 |
| read, then `tab(s)` | 1.27 | 1594 | 0.36 | 344 |
| a second `dta_group_id` | 1.25 | 2327 | 0.79 | 1662 |

A dictionary column holds each distinct value once plus a code per row,
so R makes 300 strings instead of 15M, and `tab`, `dta_group_id` and
`is_missing` work on the codes. A column whose values are mostly
distinct, like `long.dta`'s `s2`, gives the dictionary up after 65,536
rows and reads as before; the full read of `long.dta` stayed at
0.46–0.47 s.

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
