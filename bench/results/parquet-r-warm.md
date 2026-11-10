# Parquet benchmarks (R): the first call and the calls after it

Written by `bench/parquet/warm.py`; bench/RESULTS.md says what the numbers mean.

One-minute load average before each process: median 3.0, range 2.1 to 6.7.

| library | version | threads |
|---|---|---|
| datakit | 3.1.0 | default |
| arrow | 26.0.0 | 16 |
| nanoparquet | 0.5.2 | 1 |

## Ratios, datakit to the other library (geometric means)

Below 1 is better for datakit. "First" is a fresh process's first call; "warm" is the median of up to 7 further calls in that process.

| against | case | input | family | files | wall, first | wall, warm | CPU, first | CPU, warm |
|---|---|---|---|---|---|---|---|---|
| arrow | whole file | pyarrow | NSFG | 36 | 0.44 | 0.69 | 0.20 | 0.34 |
| arrow | whole file | pyarrow | DHS | 10 | 1.03 | 1.05 | 0.26 | 0.23 |
| arrow | whole file | pyarrow | Synthetic | 3 | 0.66 | 0.66 | 0.65 | 0.71 |
| arrow | whole file | ours | NSFG | 36 | 0.51 | 0.79 | 0.22 | 0.41 |
| arrow | whole file | ours | DHS | 10 | 1.28 | 1.33 | 0.31 | 0.28 |
| arrow | whole file | ours | Synthetic | 3 | 0.64 | 0.63 | 0.64 | 0.69 |
| arrow | five columns | pyarrow | NSFG | 36 | 0.11 | 0.19 | 0.13 | 0.32 |
| arrow | five columns | pyarrow | DHS | 10 | 0.15 | 0.24 | 0.16 | 0.20 |
| arrow | five columns | pyarrow | Synthetic | 3 | 0.60 | 0.55 | 0.63 | 0.63 |
| arrow | five columns | ours | NSFG | 36 | 0.17 | 0.33 | 0.20 | 0.51 |
| arrow | five columns | ours | DHS | 10 | 0.25 | 0.45 | 0.28 | 0.40 |
| arrow | five columns | ours | Synthetic | 3 | 0.62 | 0.54 | 0.66 | 0.62 |
| arrow | 1,000 rows | pyarrow | NSFG | 36 | 0.24 | 0.37 | 0.10 | 0.15 |
| arrow | 1,000 rows | pyarrow | DHS | 10 | 0.31 | 0.40 | 0.07 | 0.07 |
| arrow | 1,000 rows | pyarrow | Synthetic | 3 | 0.05 | 0.04 | 0.02 | 0.06 |
| arrow | 1,000 rows | ours | NSFG | 36 | 0.29 | 0.46 | 0.12 | 0.20 |
| arrow | 1,000 rows | ours | DHS | 10 | 0.41 | 0.56 | 0.08 | 0.10 |
| arrow | 1,000 rows | ours | Synthetic | 3 | 0.02 | 0.02 | 0.01 | 0.01 |
| arrow | read + pass | pyarrow | NSFG | 36 | 0.49 | 0.48 | 0.37 | 0.49 |
| arrow | read + pass | pyarrow | DHS | 10 | 0.51 | 0.51 | 0.38 | 0.38 |
| arrow | read + pass | pyarrow | Synthetic | 3 | 0.46 | 0.42 | 0.49 | 0.45 |
| arrow | read + pass | ours | NSFG | 36 | 0.52 | 0.50 | 0.39 | 0.55 |
| arrow | read + pass | ours | DHS | 10 | 0.53 | 0.53 | 0.39 | 0.40 |
| arrow | read + pass | ours | Synthetic | 3 | 0.45 | 0.41 | 0.48 | 0.44 |
| nanoparquet | whole file | pyarrow | NSFG | 36 | 0.52 | 0.52 | 0.74 | 0.75 |
| nanoparquet | whole file | pyarrow | DHS | 10 | 0.36 | 0.39 | 0.58 | 0.70 |
| nanoparquet | whole file | pyarrow | Synthetic | 3 | 0.11 | 0.11 | 0.39 | 0.42 |
| nanoparquet | whole file | ours | NSFG | 36 | 0.61 | 0.60 | 0.81 | 0.96 |
| nanoparquet | whole file | ours | DHS | 10 | 0.45 | 0.47 | 0.68 | 0.79 |
| nanoparquet | whole file | ours | Synthetic | 3 | 0.11 | 0.11 | 0.40 | 0.42 |
| nanoparquet | five columns | pyarrow | NSFG | 36 | 0.33 | 0.34 | 0.37 | 0.49 |
| nanoparquet | five columns | pyarrow | DHS | 10 | 0.09 | 0.12 | 0.10 | 0.11 |
| nanoparquet | five columns | pyarrow | Synthetic | 3 | 0.10 | 0.13 | 0.18 | 0.26 |
| nanoparquet | five columns | ours | NSFG | 36 | 0.54 | 0.66 | 0.63 | 0.87 |
| nanoparquet | five columns | ours | DHS | 10 | 0.16 | 0.24 | 0.19 | 0.23 |
| nanoparquet | five columns | ours | Synthetic | 3 | 0.09 | 0.13 | 0.16 | 0.26 |
| nanoparquet | 1,000 rows | pyarrow | NSFG | 36 | 0.26 | 0.28 | 0.30 | 0.33 |
| nanoparquet | 1,000 rows | pyarrow | DHS | 10 | 0.11 | 0.15 | 0.14 | 0.19 |
| nanoparquet | 1,000 rows | pyarrow | Synthetic | 3 | 0.01 | 0.01 | 0.01 | 0.04 |
| nanoparquet | 1,000 rows | ours | NSFG | 36 | 0.33 | 0.36 | 0.37 | 0.44 |
| nanoparquet | 1,000 rows | ours | DHS | 10 | 0.15 | 0.20 | 0.17 | 0.24 |
| nanoparquet | 1,000 rows | ours | Synthetic | 3 | 0.00 | 0.00 | 0.01 | 0.00 |
| nanoparquet | read + pass | pyarrow | NSFG | 36 | 0.84 | 0.87 | 0.92 | 1.18 |
| nanoparquet | read + pass | pyarrow | DHS | 10 | 0.74 | 0.90 | 0.82 | 0.99 |
| nanoparquet | read + pass | pyarrow | Synthetic | 3 | 0.82 | 0.87 | 0.96 | 1.04 |
| nanoparquet | read + pass | ours | NSFG | 36 | 0.90 | 0.91 | 0.97 | 1.15 |
| nanoparquet | read + pass | ours | DHS | 10 | 0.78 | 0.94 | 0.87 | 1.03 |
| nanoparquet | read + pass | ours | Synthetic | 3 | 0.84 | 0.89 | 0.98 | 1.03 |

## The synthetic files, each

| against | case | input | file | datakit, first | datakit, warm | theirs, first | theirs, warm |
|---|---|---|---|---|---|---|---|
| arrow | whole file | pyarrow | groups | 55 ms | 38 ms | 145 ms | 119 ms |
| arrow | whole file | pyarrow | long | 129 ms | 111 ms | 139 ms | 122 ms |
| arrow | whole file | pyarrow | wide | 200 ms | 194 ms | 241 ms | 193 ms |
| arrow | whole file | ours | groups | 55 ms | 37 ms | 143 ms | 119 ms |
| arrow | whole file | ours | long | 116 ms | 101 ms | 132 ms | 116 ms |
| arrow | whole file | ours | wide | 173 ms | 164 ms | 218 ms | 177 ms |
| arrow | five columns | pyarrow | groups | 55 ms | 37 ms | 166 ms | 126 ms |
| arrow | five columns | pyarrow | long | 134 ms | 123 ms | 128 ms | 112 ms |
| arrow | five columns | pyarrow | wide | 17 ms | 8 ms | 28 ms | 15 ms |
| arrow | five columns | ours | groups | 57 ms | 38 ms | 146 ms | 120 ms |
| arrow | five columns | ours | long | 126 ms | 108 ms | 131 ms | 108 ms |
| arrow | five columns | ours | wide | 16 ms | 7 ms | 26 ms | 15 ms |
| arrow | 1,000 rows | pyarrow | groups | 1 ms | 0 ms | 153 ms | 130 ms |
| arrow | 1,000 rows | pyarrow | long | 7 ms | 6 ms | 138 ms | 122 ms |
| arrow | 1,000 rows | pyarrow | wide | 78 ms | 77 ms | 239 ms | 194 ms |
| arrow | 1,000 rows | ours | groups | 1 ms | 1 ms | 151 ms | 118 ms |
| arrow | 1,000 rows | ours | long | 3 ms | 2 ms | 133 ms | 118 ms |
| arrow | 1,000 rows | ours | wide | 16 ms | 15 ms | 224 ms | 180 ms |
| arrow | read + pass | pyarrow | groups | 563 ms | 505 ms | 1.22 s | 1.11 s |
| arrow | read + pass | pyarrow | long | 5.71 s | 3.82 s | 9.05 s | 7.77 s |
| arrow | read + pass | pyarrow | wide | 2.87 s | 2.81 s | 8.80 s | 8.71 s |
| arrow | read + pass | ours | groups | 554 ms | 504 ms | 1.24 s | 1.12 s |
| arrow | read + pass | ours | long | 5.69 s | 3.83 s | 9.13 s | 7.74 s |
| arrow | read + pass | ours | wide | 2.85 s | 2.79 s | 8.75 s | 8.75 s |
| nanoparquet | whole file | pyarrow | groups | 55 ms | 38 ms | 151 ms | 123 ms |
| nanoparquet | whole file | pyarrow | long | 129 ms | 111 ms | 5.09 s | 4.17 s |
| nanoparquet | whole file | pyarrow | wide | 200 ms | 194 ms | 1.39 s | 1.18 s |
| nanoparquet | whole file | ours | groups | 55 ms | 37 ms | 153 ms | 123 ms |
| nanoparquet | whole file | ours | long | 116 ms | 101 ms | 5.05 s | 4.13 s |
| nanoparquet | whole file | ours | wide | 173 ms | 164 ms | 1.09 s | 915 ms |
| nanoparquet | five columns | pyarrow | groups | 55 ms | 37 ms | 156 ms | 128 ms |
| nanoparquet | five columns | pyarrow | long | 134 ms | 123 ms | 4.94 s | 4.73 s |
| nanoparquet | five columns | pyarrow | wide | 17 ms | 8 ms | 161 ms | 26 ms |
| nanoparquet | five columns | ours | groups | 57 ms | 38 ms | 168 ms | 128 ms |
| nanoparquet | five columns | ours | long | 126 ms | 108 ms | 4.87 s | 4.73 s |
| nanoparquet | five columns | ours | wide | 16 ms | 7 ms | 182 ms | 23 ms |
| nanoparquet | 1,000 rows | pyarrow | groups | 1 ms | 0 ms | 152 ms | 122 ms |
| nanoparquet | 1,000 rows | pyarrow | long | 7 ms | 6 ms | 5.11 s | 4.15 s |
| nanoparquet | 1,000 rows | pyarrow | wide | 78 ms | 77 ms | 1.43 s | 1.20 s |
| nanoparquet | 1,000 rows | ours | groups | 1 ms | 1 ms | 158 ms | 124 ms |
| nanoparquet | 1,000 rows | ours | long | 3 ms | 2 ms | 5.08 s | 4.08 s |
| nanoparquet | 1,000 rows | ours | wide | 16 ms | 15 ms | 1.09 s | 929 ms |
| nanoparquet | read + pass | pyarrow | groups | 563 ms | 505 ms | 572 ms | 421 ms |
| nanoparquet | read + pass | pyarrow | long | 5.71 s | 3.82 s | 7.28 s | 5.05 s |
| nanoparquet | read + pass | pyarrow | wide | 2.87 s | 2.81 s | 4.10 s | 3.90 s |
| nanoparquet | read + pass | ours | groups | 554 ms | 504 ms | 554 ms | 424 ms |
| nanoparquet | read + pass | ours | long | 5.69 s | 3.83 s | 7.18 s | 5.01 s |
| nanoparquet | read + pass | ours | wide | 2.85 s | 2.79 s | 3.85 s | 3.66 s |
