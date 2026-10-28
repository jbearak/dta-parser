# Benchmark results

Machine: Apple M4 Max, 16 cores, 128 GB, macOS 26.7.1, R 4.6.1, haven
2.5.5. Each run is a fresh R process under `/usr/bin/time -l`.

## Writing (`sh bench/write.sh`)

"RSS over data" is the run's peak resident memory minus that of a run
that makes the same data without writing it.

| case | tool | write s | peak RSS MB | RSS over data MB | file MB |
|---|---|---|---|---|---|
| numeric (5M rows, 10 columns) | haven | 1.78 | 588 | 40 | 324 |
| numeric | dtatools | 0.17 | 557 | 9 | 300 |
| strN (5M rows, 3 columns) | haven | 0.85 | 265 | 33 | 147 |
| strN | dtatools | 0.23 | 241 | 9 | 147 |
| strL, 200k rows of 20 texts | haven | 0.23 | 94 | 20 | 2 |
| strL, repeated | dtatools | 0.15 | 74 | 0 | 2 |
| strL, 100k distinct texts | haven | 0.46 | 929 | 421 | 183 |
| strL, distinct | dtatools | 0.20 | 511 | 3 | 183 |
| 3 strL columns, 100k rows of 50 texts each | haven | 0.31 | 103 | 10 | 2 |
| 3 strL columns | dtatools | 0.29 | 93 | 0 | 2 |

dtatools reads R's vectors in place and builds rows 8 MiB at a time, so
its overhead is that buffer, plus, for each strL column, a table of its
distinct texts (borrowed, not copied). haven's numeric file is larger
because it stores R integers that fit a byte as long. The page cache was
warm; writes end in the cache either way.
