# Parquet benchmarks (R)

Written by `bench/parquet/run.py`; see bench/RESULTS.md for what the numbers mean.

One-minute load average before the runs: median 11.9, range 9.5 to 17.3.

| library | version | threads |
|---|---|---|
| arrow | 26.0.0 | 16 |
| duckdb | 2.0.0 | 16 |
| nanoparquet | 0.5.2 | 1 |
| ours | 3.1.0 | default |
| py-duckdb | 2.0.0 | None |
| py-polars | 2.1.0 | None |
| py-pyarrow | 26.0.1 | None |

## Ratios, ours to theirs (geometric means)

Below 1 is better for us. Targets 1 and 2 hold where wall and RSS are at most 1.05 on NSFG and DHS.

| against | case | input | family | files | wall | CPU | peak RSS |
|---|---|---|---|---|---|---|---|
| arrow | whole file | pyarrow | NSFG | 36 | 0.38 | 0.23 | 0.62 |
| arrow | whole file | pyarrow | DHS | 10 | 0.85 | 0.32 | 0.73 |
| arrow | whole file | pyarrow | Synthetic | 3 | 0.63 | 0.67 | 0.47 |
| arrow | whole file | polars | NSFG | 36 | 0.42 | 0.23 | 0.62 |
| arrow | whole file | polars | DHS | 10 | 0.87 | 0.32 | 0.74 |
| arrow | whole file | polars | Synthetic | 3 | 0.72 | 0.68 | 0.44 |
| arrow | whole file | ours | NSFG | 36 | 0.46 | 0.25 | 0.63 |
| arrow | whole file | ours | DHS | 10 | 0.98 | 0.35 | 0.75 |
| arrow | whole file | ours | Synthetic | 3 | 0.55 | 0.65 | 0.46 |
| arrow | five columns | pyarrow | NSFG | 36 | 0.10 | 0.12 | 0.59 |
| arrow | five columns | pyarrow | DHS | 10 | 0.13 | 0.14 | 0.57 |
| arrow | five columns | pyarrow | Synthetic | 3 | 0.65 | 0.68 | 0.53 |
| arrow | five columns | polars | NSFG | 36 | 0.10 | 0.12 | 0.58 |
| arrow | five columns | polars | DHS | 10 | 0.13 | 0.14 | 0.57 |
| arrow | five columns | polars | Synthetic | 3 | 0.78 | 0.68 | 0.47 |
| arrow | five columns | ours | NSFG | 36 | 0.16 | 0.18 | 0.60 |
| arrow | five columns | ours | DHS | 10 | 0.23 | 0.25 | 0.59 |
| arrow | five columns | ours | Synthetic | 3 | 0.64 | 0.67 | 0.52 |
| arrow | 1,000 rows | pyarrow | NSFG | 36 | 0.21 | 0.10 | 0.46 |
| arrow | 1,000 rows | pyarrow | DHS | 10 | 0.25 | 0.08 | 0.31 |
| arrow | 1,000 rows | pyarrow | Synthetic | 3 | 0.06 | 0.02 | 0.04 |
| arrow | 1,000 rows | polars | NSFG | 36 | 0.26 | 0.12 | 0.46 |
| arrow | 1,000 rows | polars | DHS | 10 | 0.30 | 0.09 | 0.31 |
| arrow | 1,000 rows | polars | Synthetic | 3 | 0.05 | 0.01 | 0.04 |
| arrow | 1,000 rows | ours | NSFG | 36 | 0.26 | 0.12 | 0.48 |
| arrow | 1,000 rows | ours | DHS | 10 | 0.32 | 0.10 | 0.32 |
| arrow | 1,000 rows | ours | Synthetic | 3 | 0.03 | 0.01 | 0.04 |
| arrow | read + pass | pyarrow | NSFG | 36 | 0.48 | 0.39 | 0.64 |
| arrow | read + pass | pyarrow | DHS | 10 | 0.49 | 0.40 | 0.75 |
| arrow | read + pass | pyarrow | Synthetic | 3 | 0.46 | 0.49 | 0.64 |
| arrow | read + pass | polars | NSFG | 36 | 0.49 | 0.39 | 0.65 |
| arrow | read + pass | polars | DHS | 10 | 0.49 | 0.40 | 0.76 |
| arrow | read + pass | polars | Synthetic | 3 | 0.46 | 0.53 | 0.62 |
| arrow | read + pass | ours | NSFG | 36 | 0.51 | 0.42 | 0.65 |
| arrow | read + pass | ours | DHS | 10 | 0.52 | 0.43 | 0.78 |
| arrow | read + pass | ours | Synthetic | 3 | 0.47 | 0.48 | 0.64 |
| arrow | write, defaults | dta | NSFG | 36 | 0.04 | 0.06 | 0.67 |
| arrow | write, defaults | dta | DHS | 10 | 0.03 | 0.05 | 0.84 |
| arrow | write, defaults | dta | Synthetic | 3 | 0.27 | 0.57 | 0.76 |
| arrow | write, zstd 3 | dta | NSFG | 36 | 0.05 | 0.07 | 0.67 |
| arrow | write, zstd 3 | dta | DHS | 10 | 0.03 | 0.05 | 0.85 |
| arrow | write, zstd 3 | dta | Synthetic | 3 | 0.28 | 0.60 | 0.76 |
| nanoparquet | whole file | pyarrow | NSFG | 36 | 0.52 | 0.71 | 0.75 |
| nanoparquet | whole file | pyarrow | DHS | 10 | 0.37 | 0.59 | 0.53 |
| nanoparquet | whole file | pyarrow | Synthetic | 3 | 0.11 | 0.38 | 0.56 |
| nanoparquet | whole file | polars | NSFG | 36 | 0.51 | 0.70 | 0.75 |
| nanoparquet | whole file | polars | DHS | 10 | 0.37 | 0.59 | 0.53 |
| nanoparquet | whole file | polars | Synthetic | 3 | 0.11 | 0.43 | 0.64 |
| nanoparquet | whole file | ours | NSFG | 36 | 0.61 | 0.78 | 0.79 |
| nanoparquet | whole file | ours | DHS | 10 | 0.43 | 0.66 | 0.64 |
| nanoparquet | whole file | ours | Synthetic | 3 | 0.11 | 0.38 | 0.66 |
| nanoparquet | five columns | pyarrow | NSFG | 36 | 0.30 | 0.33 | 0.81 |
| nanoparquet | five columns | pyarrow | DHS | 10 | 0.08 | 0.08 | 0.66 |
| nanoparquet | five columns | pyarrow | Synthetic | 3 | 0.10 | 0.18 | 0.60 |
| nanoparquet | five columns | polars | NSFG | 36 | 0.31 | 0.36 | 0.81 |
| nanoparquet | five columns | polars | DHS | 10 | 0.08 | 0.09 | 0.66 |
| nanoparquet | five columns | polars | Synthetic | 3 | 0.13 | 0.24 | 0.62 |
| nanoparquet | five columns | ours | NSFG | 36 | 0.51 | 0.55 | 0.84 |
| nanoparquet | five columns | ours | DHS | 10 | 0.14 | 0.16 | 0.69 |
| nanoparquet | five columns | ours | Synthetic | 3 | 0.10 | 0.17 | 0.64 |
| nanoparquet | 1,000 rows | pyarrow | NSFG | 36 | 0.26 | 0.28 | 0.54 |
| nanoparquet | 1,000 rows | pyarrow | DHS | 10 | 0.11 | 0.14 | 0.22 |
| nanoparquet | 1,000 rows | pyarrow | Synthetic | 3 | 0.01 | 0.01 | 0.04 |
| nanoparquet | 1,000 rows | polars | NSFG | 36 | 0.29 | 0.33 | 0.55 |
| nanoparquet | 1,000 rows | polars | DHS | 10 | 0.13 | 0.16 | 0.22 |
| nanoparquet | 1,000 rows | polars | Synthetic | 3 | 0.01 | 0.01 | 0.05 |
| nanoparquet | 1,000 rows | ours | NSFG | 36 | 0.33 | 0.34 | 0.58 |
| nanoparquet | 1,000 rows | ours | DHS | 10 | 0.14 | 0.16 | 0.27 |
| nanoparquet | 1,000 rows | ours | Synthetic | 3 | 0.00 | 0.01 | 0.05 |
| nanoparquet | read + pass | pyarrow | NSFG | 36 | 0.83 | 0.89 | 0.81 |
| nanoparquet | read + pass | pyarrow | DHS | 10 | 0.74 | 0.82 | 0.67 |
| nanoparquet | read + pass | pyarrow | Synthetic | 3 | 0.84 | 0.98 | 0.76 |
| nanoparquet | read + pass | polars | NSFG | 36 | 0.82 | 0.87 | 0.82 |
| nanoparquet | read + pass | polars | DHS | 10 | 0.73 | 0.82 | 0.65 |
| nanoparquet | read + pass | polars | Synthetic | 3 | 0.70 | 0.94 | 0.80 |
| nanoparquet | read + pass | ours | NSFG | 36 | 0.90 | 0.95 | 0.84 |
| nanoparquet | read + pass | ours | DHS | 10 | 0.79 | 0.88 | 0.71 |
| nanoparquet | read + pass | ours | Synthetic | 3 | 0.89 | 0.98 | 0.81 |
| nanoparquet | write, defaults | dta | NSFG | 36 | 0.35 | 0.48 | 0.85 |
| nanoparquet | write, defaults | dta | DHS | 10 | 0.34 | 0.54 | 0.83 |
| nanoparquet | write, defaults | dta | Synthetic | 3 | 0.47 | 1.04 | 0.87 |
| nanoparquet | write, zstd 3 | dta | NSFG | 36 | 0.36 | 0.49 | 0.86 |
| nanoparquet | write, zstd 3 | dta | DHS | 10 | 0.33 | 0.53 | 0.85 |
| nanoparquet | write, zstd 3 | dta | Synthetic | 3 | 0.47 | 1.02 | 0.88 |
| duckdb | whole file | pyarrow | NSFG | 36 | 0.24 | 0.25 | 0.50 |
| duckdb | whole file | pyarrow | DHS | 10 | 0.16 | 0.18 | 0.45 |
| duckdb | whole file | pyarrow | Synthetic | 2 | 0.05 | 0.12 | 0.36 |
| duckdb | whole file | polars | NSFG | 36 | 0.25 | 0.24 | 0.49 |
| duckdb | whole file | polars | DHS | 10 | 0.17 | 0.19 | 0.45 |
| duckdb | whole file | polars | Synthetic | 3 | 0.08 | 0.23 | 0.35 |
| duckdb | whole file | ours | NSFG | 36 | 0.27 | 0.26 | 0.51 |
| duckdb | whole file | ours | DHS | 10 | 0.18 | 0.19 | 0.46 |
| duckdb | whole file | ours | Synthetic | 3 | 0.07 | 0.19 | 0.36 |
| duckdb | five columns | pyarrow | NSFG | 36 | 0.36 | 0.35 | 0.58 |
| duckdb | five columns | pyarrow | DHS | 10 | 0.29 | 0.28 | 0.57 |
| duckdb | five columns | pyarrow | Synthetic | 3 | 0.11 | 0.16 | 0.42 |
| duckdb | five columns | polars | NSFG | 36 | 0.36 | 0.38 | 0.58 |
| duckdb | five columns | polars | DHS | 10 | 0.31 | 0.31 | 0.58 |
| duckdb | five columns | polars | Synthetic | 3 | 0.13 | 0.22 | 0.37 |
| duckdb | five columns | ours | NSFG | 36 | 0.62 | 0.61 | 0.60 |
| duckdb | five columns | ours | DHS | 10 | 0.57 | 0.56 | 0.60 |
| duckdb | five columns | ours | Synthetic | 3 | 0.11 | 0.17 | 0.39 |
| duckdb | 1,000 rows | pyarrow | NSFG | 36 | 0.15 | 0.05 | 0.24 |
| duckdb | 1,000 rows | pyarrow | DHS | 10 | 0.10 | 0.03 | 0.13 |
| duckdb | 1,000 rows | pyarrow | Synthetic | 2 | 0.20 | 0.18 | 0.47 |
| duckdb | 1,000 rows | polars | NSFG | 36 | 0.18 | 0.07 | 0.24 |
| duckdb | 1,000 rows | polars | DHS | 10 | 0.11 | 0.04 | 0.13 |
| duckdb | 1,000 rows | polars | Synthetic | 3 | 0.31 | 0.14 | 0.29 |
| duckdb | 1,000 rows | ours | NSFG | 36 | 0.19 | 0.07 | 0.25 |
| duckdb | 1,000 rows | ours | DHS | 10 | 0.13 | 0.04 | 0.13 |
| duckdb | 1,000 rows | ours | Synthetic | 3 | 0.19 | 0.13 | 0.25 |
| duckdb | read + pass | pyarrow | NSFG | 36 | 0.59 | 0.53 | 0.56 |
| duckdb | read + pass | pyarrow | DHS | 10 | 0.47 | 0.42 | 0.51 |
| duckdb | read + pass | pyarrow | Synthetic | 2 | 0.70 | 0.72 | 0.62 |
| duckdb | read + pass | polars | NSFG | 36 | 0.59 | 0.51 | 0.57 |
| duckdb | read + pass | polars | DHS | 10 | 0.47 | 0.42 | 0.51 |
| duckdb | read + pass | polars | Synthetic | 3 | 0.60 | 0.70 | 0.59 |
| duckdb | read + pass | ours | NSFG | 36 | 0.62 | 0.55 | 0.57 |
| duckdb | read + pass | ours | DHS | 10 | 0.50 | 0.45 | 0.52 |
| duckdb | read + pass | ours | Synthetic | 3 | 0.75 | 0.76 | 0.59 |
| duckdb | write, defaults | dta | NSFG | 36 | 0.35 | 0.34 | 0.48 |
| duckdb | write, defaults | dta | DHS | 10 | 0.25 | 0.26 | 0.54 |
| duckdb | write, defaults | dta | Synthetic | 3 | 0.46 | 0.91 | 0.84 |
| duckdb | write, zstd 3 | dta | NSFG | 36 | 0.36 | 0.34 | 0.48 |
| duckdb | write, zstd 3 | dta | DHS | 10 | 0.25 | 0.27 | 0.54 |
| duckdb | write, zstd 3 | dta | Synthetic | 3 | 0.45 | 0.74 | 0.84 |

## Other tools reading our files

Time on our file ÷ time on the tool's own default output (target 4: at most 1.10).

Our files with the default codec (snappy), and with zstd 3 (`ours_zstd`, not gated).

| tool | our codec | family | files | geometric mean | worst file | its ratio |
|---|---|---|---|---|---|---|
| pyarrow | snappy | NSFG | 36 | 0.99 | 2006_2010_FemPreg | 1.09 |
| pyarrow | snappy | DHS | 10 | 0.99 | Tajikistan 2017 bh | 1.02 |
| pyarrow | snappy | Synthetic | 3 | 0.93 | wide.dta | 1.05 |
| pyarrow | zstd 3 | NSFG | 36 | 1.00 | 2022_2023_MaleResp | 1.09 |
| pyarrow | zstd 3 | DHS | 10 | 1.00 | Senegal 2019 wm | 1.06 |
| pyarrow | zstd 3 | Synthetic | 3 | 1.09 | wide.dta | 1.49 |
| polars | snappy | NSFG | 36 | 0.86 | 2002_hhpartypnew | 1.07 |
| polars | snappy | DHS | 10 | 0.90 | Senegal 2019 wm | 0.99 |
| polars | snappy | Synthetic | 3 | 0.42 | groups.dta | 0.71 |
| polars | zstd 3 | NSFG | 36 | 1.04 | 1976_PSU | 2.55 |
| polars | zstd 3 | DHS | 10 | 1.00 | Dominican Republic 2013 wm | 1.05 |
| polars | zstd 3 | Synthetic | 3 | 0.85 | long.dta | 1.00 |
| duckdb | snappy | NSFG | 36 | 1.03 | 2013_2015_FemResp | 1.10 |
| duckdb | snappy | DHS | 10 | 1.04 | Tajikistan 2017 bh | 1.10 |
| duckdb | snappy | Synthetic | 3 | 1.07 | long.dta | 1.09 |
| duckdb | zstd 3 | NSFG | 36 | 1.06 | 2017_2019_FemPreg | 1.15 |
| duckdb | zstd 3 | DHS | 10 | 1.07 | Tajikistan 2017 bh | 1.15 |
| duckdb | zstd 3 | Synthetic | 3 | 1.57 | wide.dta | 2.38 |

## Our writes: zstd 3 against snappy (the default)

Ratios of our zstd write to our snappy write (geometric means), and how arrow, nanoparquet and DuckDB (their defaults) compare with each (wall time).

| family | files | wall zstd/snappy | size zstd/snappy | vs arrow (zstd, snappy) | vs nanoparquet | vs duckdb |
|---|---|---|---|---|---|---|
| NSFG | 36 | 1.11 | 0.84 | 0.05, 0.04 | 0.39, 0.35 | 0.39, 0.35 |
| DHS | 10 | 1.03 | 0.83 | 0.03, 0.03 | 0.35, 0.34 | 0.26, 0.25 |
| Synthetic | 3 | 1.29 | 0.95 | 0.34, 0.27 | 0.61, 0.47 | 0.59, 0.46 |

## Misses

None: every target holds.

## Every file

### long.dta

10,000,000 rows, 12 columns; .dta 740.0 MB; Parquet pyarrow 650.9 MB, polars 597.3 MB, ours 632.9 MB, duckdb 647.6 MB, ours_zstd 585.2 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 148 ms / 0.48 s / 1388 MB | 160 ms / 0.60 s / 2122 MB | 5.39 s / 5.39 s / 2728 MB | 6.08 s / 6.54 s / 3349 MB |
| whole file | polars | 206 ms / 0.81 s / 1233 MB | 195 ms / 1.03 s / 2141 MB | 5.84 s / 5.84 s / 2263 MB | 6.46 s / 6.56 s / 3406 MB |
| whole file | ours | 124 ms / 0.43 s / 1326 MB | 150 ms / 0.56 s / 2034 MB | 5.35 s / 5.35 s / 2299 MB | 6.03 s / 6.47 s / 3347 MB |
| five columns | pyarrow | 148 ms / 0.29 s / 855 MB | 146 ms / 0.28 s / 1020 MB | 5.18 s / 5.18 s / 1859 MB | 5.63 s / 5.92 s / 1928 MB |
| five columns | polars | 211 ms / 0.42 s / 741 MB | 182 ms / 0.49 s / 1108 MB | 5.37 s / 5.37 s / 1631 MB | 5.76 s / 5.81 s / 1897 MB |
| five columns | ours | 144 ms / 0.28 s / 823 MB | 136 ms / 0.27 s / 984 MB | 5.18 s / 5.18 s / 1674 MB | 5.52 s / 5.74 s / 1953 MB |
| 1,000 rows | pyarrow | 8 ms / 0.01 s / 106 MB | 155 ms / 0.61 s / 2099 MB | 5.37 s / 5.37 s / 2727 MB | 19 ms / 0.03 s / 264 MB |
| 1,000 rows | polars | 7 ms / 0.01 s / 101 MB | 197 ms / 1.04 s / 2174 MB | 5.92 s / 5.92 s / 2261 MB | 19 ms / 0.04 s / 218 MB |
| 1,000 rows | ours | 3 ms / 0.00 s / 100 MB | 158 ms / 0.59 s / 2037 MB | 5.39 s / 5.39 s / 2298 MB | 13 ms / 0.03 s / 220 MB |
| read + pass | pyarrow | 6.11 s / 6.44 s / 2651 MB | 9.53 s / 9.98 s / 3437 MB | 7.49 s / 7.49 s / 3269 MB | 8.04 s / 8.51 s / 3349 MB |
| read + pass | polars | 6.18 s / 6.79 s / 2523 MB | 10.07 s / 10.80 s / 3483 MB | 8.19 s / 8.19 s / 3141 MB | 8.24 s / 8.36 s / 3405 MB |
| read + pass | ours | 6.09 s / 6.39 s / 2578 MB | 9.94 s / 10.36 s / 3360 MB | 7.67 s / 7.67 s / 3179 MB | 7.89 s / 8.33 s / 3430 MB |
| write, defaults | dta | 1.12 s / 1.91 s / 2018 MB | 3.80 s / 3.87 s / 2334 MB | 1.93 s / 1.93 s / 2230 MB | 1.69 s / 1.79 s / 2097 MB |
| write, zstd 3 | dta | 1.58 s / 2.62 s / 2015 MB | 4.45 s / 4.53 s / 2338 MB | 2.72 s / 2.71 s / 2230 MB | 2.49 s / 5.03 s / 2094 MB |

### wide.dta

1,500,000 rows, 400 columns; .dta 4800.3 MB; Parquet pyarrow 5020.6 MB, polars 4607.6 MB, ours 4800.8 MB, duckdb 4800.9 MB, ours_zstd 4607.6 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 218 ms / 1.57 s / 5042 MB | 295 ms / 1.94 s / 10399 MB | 1.61 s / 1.61 s / 9407 MB | – |
| whole file | polars | 588 ms / 4.49 s / 4928 MB | 675 ms / 5.66 s / 9923 MB | 5.31 s / 5.30 s / 6224 MB | 4.83 s / 9.24 s / 12707 MB |
| whole file | ours | 189 ms / 1.34 s / 4942 MB | 341 ms / 1.78 s / 10120 MB | 1.24 s / 1.24 s / 6121 MB | 1.58 s / 2.57 s / 13065 MB |
| five columns | pyarrow | 22 ms / 0.03 s / 181 MB | 28 ms / 0.05 s / 317 MB | 197 ms / 0.20 s / 247 MB | 44 ms / 0.06 s / 349 MB |
| five columns | polars | 40 ms / 0.07 s / 165 MB | 40 ms / 0.09 s / 311 MB | 240 ms / 0.24 s / 193 MB | 86 ms / 0.10 s / 391 MB |
| five columns | ours | 20 ms / 0.03 s / 163 MB | 29 ms / 0.05 s / 312 MB | 187 ms / 0.19 s / 189 MB | 39 ms / 0.06 s / 358 MB |
| 1,000 rows | pyarrow | 154 ms / 0.15 s / 103 MB | 294 ms / 1.97 s / 10397 MB | 1.58 s / 1.58 s / 9407 MB | – |
| 1,000 rows | polars | 206 ms / 0.21 s / 108 MB | 691 ms / 5.64 s / 9916 MB | 5.40 s / 5.36 s / 6228 MB | 268 ms / 0.60 s / 1103 MB |
| 1,000 rows | ours | 31 ms / 0.03 s / 107 MB | 324 ms / 1.74 s / 10113 MB | 1.27 s / 1.27 s / 6124 MB | 123 ms / 0.23 s / 1720 MB |
| read + pass | pyarrow | 3.27 s / 4.61 s / 7067 MB | 10.14 s / 11.65 s / 10499 MB | 4.68 s / 4.67 s / 9770 MB | – |
| read + pass | polars | 3.72 s / 7.62 s / 7069 MB | 10.56 s / 15.38 s / 10018 MB | 8.47 s / 8.46 s / 8104 MB | 7.88 s / 12.30 s / 12553 MB |
| read + pass | ours | 3.92 s / 4.62 s / 7059 MB | 10.17 s / 11.59 s / 10210 MB | 4.29 s / 4.29 s / 8001 MB | 4.59 s / 5.56 s / 12544 MB |
| write, defaults | dta | 1.57 s / 9.81 s / 5050 MB | 7.15 s / 7.71 s / 5056 MB | 7.69 s / 7.66 s / 4948 MB | 6.53 s / 7.74 s / 6875 MB |
| write, zstd 3 | dta | 2.27 s / 14.14 s / 5050 MB | 11.04 s / 11.54 s / 5057 MB | 11.23 s / 11.14 s / 4950 MB | 9.48 s / 10.69 s / 6742 MB |

### groups.dta

15,000,000 rows, 2 columns; .dta 270.0 MB; Parquet pyarrow 24.1 MB, polars 23.4 MB, ours 24.0 MB, duckdb 23.9 MB, ours_zstd 23.4 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 61 ms / 0.11 s / 292 MB | 165 ms / 0.24 s / 914 MB | 176 ms / 0.18 s / 458 MB | 543 ms / 0.55 s / 931 MB |
| whole file | polars | 62 ms / 0.12 s / 284 MB | 152 ms / 0.23 s / 974 MB | 176 ms / 0.18 s / 459 MB | 549 ms / 0.56 s / 936 MB |
| whole file | ours | 61 ms / 0.11 s / 289 MB | 162 ms / 0.24 s / 915 MB | 171 ms / 0.17 s / 458 MB | 534 ms / 0.54 s / 951 MB |
| five columns | pyarrow | 62 ms / 0.11 s / 290 MB | 174 ms / 0.25 s / 913 MB | 176 ms / 0.18 s / 459 MB | 543 ms / 0.70 s / 930 MB |
| five columns | polars | 63 ms / 0.12 s / 284 MB | 156 ms / 0.23 s / 975 MB | 181 ms / 0.18 s / 458 MB | 553 ms / 0.56 s / 936 MB |
| five columns | ours | 61 ms / 0.11 s / 289 MB | 164 ms / 0.24 s / 915 MB | 174 ms / 0.17 s / 460 MB | 543 ms / 0.55 s / 952 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 99 MB | 164 ms / 0.24 s / 914 MB | 176 ms / 0.18 s / 460 MB | 12 ms / 0.02 s / 177 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 97 MB | 150 ms / 0.23 s / 974 MB | 180 ms / 0.18 s / 459 MB | 13 ms / 0.02 s / 183 MB |
| 1,000 rows | ours | 1 ms / 0.00 s / 100 MB | 163 ms / 0.24 s / 915 MB | 174 ms / 0.17 s / 458 MB | 13 ms / 0.02 s / 182 MB |
| read + pass | pyarrow | 645 ms / 0.70 s / 669 MB | 1.40 s / 1.47 s / 1353 MB | 628 ms / 0.63 s / 900 MB | 1.01 s / 1.01 s / 1371 MB |
| read + pass | polars | 641 ms / 0.69 s / 664 MB | 1.40 s / 1.47 s / 1412 MB | 632 ms / 0.63 s / 901 MB | 1.03 s / 1.04 s / 1378 MB |
| read + pass | ours | 638 ms / 0.69 s / 669 MB | 1.42 s / 1.49 s / 1354 MB | 646 ms / 0.65 s / 898 MB | 1.01 s / 1.01 s / 1391 MB |
| write, defaults | dta | 323 ms / 0.32 s / 407 MB | 1.09 s / 1.09 s / 793 MB | 361 ms / 0.36 s / 564 MB | 540 ms / 0.57 s / 491 MB |
| write, zstd 3 | dta | 340 ms / 0.34 s / 409 MB | 1.11 s / 1.11 s / 793 MB | 388 ms / 0.39 s / 552 MB | 557 ms / 0.58 s / 490 MB |

### 1973_FemResp

9,797 rows, 450 columns; .dta 5.7 MB; Parquet pyarrow 1.6 MB, polars 1.3 MB, ours 1.7 MB, duckdb 1.5 MB, ours_zstd 1.4 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 7 ms / 0.01 s / 122 MB | 16 ms / 0.04 s / 197 MB | 13 ms / 0.01 s / 150 MB | 28 ms / 0.04 s / 225 MB |
| whole file | polars | 7 ms / 0.01 s / 122 MB | 16 ms / 0.04 s / 196 MB | 15 ms / 0.02 s / 151 MB | 30 ms / 0.05 s / 225 MB |
| whole file | ours | 8 ms / 0.01 s / 124 MB | 16 ms / 0.04 s / 197 MB | 13 ms / 0.01 s / 150 MB | 28 ms / 0.04 s / 224 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 99 MB | 14 ms / 0.01 s / 170 MB | 3 ms / 0.00 s / 106 MB | 3 ms / 0.00 s / 168 MB |
| five columns | polars | 1 ms / 0.00 s / 98 MB | 14 ms / 0.01 s / 168 MB | 3 ms / 0.00 s / 106 MB | 3 ms / 0.00 s / 168 MB |
| five columns | ours | 2 ms / 0.00 s / 100 MB | 14 ms / 0.02 s / 169 MB | 3 ms / 0.00 s / 107 MB | 3 ms / 0.00 s / 168 MB |
| 1,000 rows | pyarrow | 5 ms / 0.01 s / 100 MB | 17 ms / 0.04 s / 198 MB | 15 ms / 0.01 s / 154 MB | 25 ms / 0.08 s / 299 MB |
| 1,000 rows | polars | 6 ms / 0.01 s / 100 MB | 18 ms / 0.05 s / 196 MB | 17 ms / 0.02 s / 154 MB | 25 ms / 0.08 s / 292 MB |
| 1,000 rows | ours | 6 ms / 0.01 s / 102 MB | 17 ms / 0.04 s / 197 MB | 15 ms / 0.02 s / 151 MB | 23 ms / 0.07 s / 285 MB |
| read + pass | pyarrow | 35 ms / 0.04 s / 171 MB | 71 ms / 0.10 s / 258 MB | 40 ms / 0.04 s / 180 MB | 55 ms / 0.07 s / 261 MB |
| read + pass | polars | 36 ms / 0.04 s / 168 MB | 71 ms / 0.10 s / 265 MB | 42 ms / 0.04 s / 178 MB | 59 ms / 0.08 s / 273 MB |
| read + pass | ours | 36 ms / 0.04 s / 171 MB | 70 ms / 0.10 s / 258 MB | 41 ms / 0.04 s / 178 MB | 55 ms / 0.07 s / 273 MB |
| write, defaults | dta | 19 ms / 0.03 s / 148 MB | 699 ms / 0.70 s / 233 MB | 70 ms / 0.07 s / 196 MB | 72 ms / 0.11 s / 290 MB |
| write, zstd 3 | dta | 21 ms / 0.04 s / 148 MB | 718 ms / 0.71 s / 233 MB | 79 ms / 0.08 s / 191 MB | 75 ms / 0.10 s / 290 MB |

### 1976_FemResp

8,611 rows, 468 columns; .dta 6.0 MB; Parquet pyarrow 1.8 MB, polars 1.4 MB, ours 2.2 MB, duckdb 1.7 MB, ours_zstd 1.8 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 10 ms / 0.01 s / 122 MB | 22 ms / 0.04 s / 195 MB | 13 ms / 0.01 s / 154 MB | 24 ms / 0.04 s / 227 MB |
| whole file | polars | 11 ms / 0.01 s / 123 MB | 17 ms / 0.04 s / 195 MB | 15 ms / 0.02 s / 153 MB | 27 ms / 0.04 s / 227 MB |
| whole file | ours | 12 ms / 0.01 s / 125 MB | 15 ms / 0.04 s / 199 MB | 12 ms / 0.01 s / 153 MB | 24 ms / 0.04 s / 227 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 99 MB | 14 ms / 0.01 s / 167 MB | 3 ms / 0.00 s / 107 MB | 3 ms / 0.00 s / 169 MB |
| five columns | polars | 1 ms / 0.00 s / 99 MB | 14 ms / 0.01 s / 167 MB | 3 ms / 0.00 s / 107 MB | 3 ms / 0.01 s / 168 MB |
| five columns | ours | 3 ms / 0.00 s / 103 MB | 15 ms / 0.01 s / 169 MB | 3 ms / 0.00 s / 108 MB | 3 ms / 0.01 s / 169 MB |
| 1,000 rows | pyarrow | 5 ms / 0.01 s / 100 MB | 17 ms / 0.04 s / 198 MB | 15 ms / 0.02 s / 154 MB | 24 ms / 0.08 s / 291 MB |
| 1,000 rows | polars | 6 ms / 0.01 s / 101 MB | 17 ms / 0.05 s / 197 MB | 17 ms / 0.02 s / 154 MB | 25 ms / 0.08 s / 294 MB |
| 1,000 rows | ours | 7 ms / 0.01 s / 104 MB | 17 ms / 0.04 s / 200 MB | 14 ms / 0.01 s / 154 MB | 23 ms / 0.08 s / 302 MB |
| read + pass | pyarrow | 35 ms / 0.04 s / 181 MB | 65 ms / 0.09 s / 265 MB | 39 ms / 0.04 s / 188 MB | 50 ms / 0.06 s / 272 MB |
| read + pass | polars | 39 ms / 0.04 s / 179 MB | 65 ms / 0.10 s / 265 MB | 40 ms / 0.04 s / 191 MB | 53 ms / 0.07 s / 273 MB |
| read + pass | ours | 40 ms / 0.04 s / 180 MB | 67 ms / 0.09 s / 267 MB | 38 ms / 0.04 s / 188 MB | 50 ms / 0.06 s / 273 MB |
| write, defaults | dta | 30 ms / 0.03 s / 153 MB | 792 ms / 0.80 s / 245 MB | 69 ms / 0.07 s / 202 MB | 60 ms / 0.10 s / 297 MB |
| write, zstd 3 | dta | 36 ms / 0.04 s / 151 MB | 811 ms / 0.82 s / 245 MB | 79 ms / 0.08 s / 202 MB | 68 ms / 0.11 s / 298 MB |

### 1976_PSU

8,611 rows, 3 columns; .dta 0.0 MB; Parquet pyarrow 0.1 MB, polars 0.0 MB, ours 0.0 MB, duckdb 0.0 MB, ours_zstd 0.0 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 1 ms / 0.00 s / 98 MB | 9 ms / 0.01 s / 165 MB | 2 ms / 0.00 s / 97 MB | 2 ms / 0.00 s / 167 MB |
| whole file | polars | 1 ms / 0.00 s / 96 MB | 8 ms / 0.01 s / 165 MB | 2 ms / 0.00 s / 99 MB | 2 ms / 0.00 s / 167 MB |
| whole file | ours | 1 ms / 0.00 s / 99 MB | 8 ms / 0.01 s / 165 MB | 2 ms / 0.00 s / 97 MB | 2 ms / 0.00 s / 167 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 98 MB | 13 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 98 MB | 2 ms / 0.00 s / 168 MB |
| five columns | polars | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 98 MB | 2 ms / 0.00 s / 167 MB |
| five columns | ours | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 99 MB | 2 ms / 0.00 s / 168 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 99 MB | 9 ms / 0.01 s / 165 MB | 2 ms / 0.00 s / 97 MB | 3 ms / 0.00 s / 172 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 98 MB | 9 ms / 0.01 s / 165 MB | 2 ms / 0.00 s / 99 MB | 3 ms / 0.01 s / 172 MB |
| 1,000 rows | ours | 1 ms / 0.00 s / 98 MB | 9 ms / 0.01 s / 165 MB | 2 ms / 0.00 s / 99 MB | 3 ms / 0.01 s / 174 MB |
| read + pass | pyarrow | 4 ms / 0.01 s / 99 MB | 12 ms / 0.01 s / 166 MB | 5 ms / 0.01 s / 100 MB | 5 ms / 0.01 s / 168 MB |
| read + pass | polars | 4 ms / 0.01 s / 99 MB | 12 ms / 0.01 s / 165 MB | 5 ms / 0.01 s / 99 MB | 6 ms / 0.01 s / 168 MB |
| read + pass | ours | 4 ms / 0.01 s / 99 MB | 12 ms / 0.01 s / 165 MB | 5 ms / 0.01 s / 98 MB | 5 ms / 0.01 s / 168 MB |
| write, defaults | dta | 1 ms / 0.00 s / 100 MB | 10 ms / 0.01 s / 170 MB | 4 ms / 0.00 s / 99 MB | 3 ms / 0.00 s / 169 MB |
| write, zstd 3 | dta | 1 ms / 0.00 s / 98 MB | 10 ms / 0.01 s / 170 MB | 4 ms / 0.00 s / 101 MB | 3 ms / 0.00 s / 169 MB |

### 1976_Preg

23,042 rows, 80 columns; .dta 2.4 MB; Parquet pyarrow 0.4 MB, polars 0.3 MB, ours 0.4 MB, duckdb 0.4 MB, ours_zstd 0.4 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 4 ms / 0.00 s / 106 MB | 10 ms / 0.02 s / 176 MB | 5 ms / 0.01 s / 117 MB | 10 ms / 0.02 s / 187 MB |
| whole file | polars | 4 ms / 0.00 s / 106 MB | 10 ms / 0.02 s / 176 MB | 6 ms / 0.01 s / 116 MB | 10 ms / 0.02 s / 186 MB |
| whole file | ours | 4 ms / 0.01 s / 106 MB | 10 ms / 0.02 s / 176 MB | 5 ms / 0.01 s / 117 MB | 10 ms / 0.02 s / 184 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 167 MB | 2 ms / 0.00 s / 101 MB | 3 ms / 0.00 s / 167 MB |
| five columns | polars | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 101 MB | 3 ms / 0.00 s / 169 MB |
| five columns | ours | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 101 MB | 3 ms / 0.00 s / 168 MB |
| 1,000 rows | pyarrow | 2 ms / 0.00 s / 98 MB | 11 ms / 0.02 s / 176 MB | 6 ms / 0.01 s / 116 MB | 7 ms / 0.02 s / 195 MB |
| 1,000 rows | polars | 2 ms / 0.00 s / 96 MB | 11 ms / 0.02 s / 176 MB | 6 ms / 0.01 s / 118 MB | 7 ms / 0.02 s / 199 MB |
| 1,000 rows | ours | 2 ms / 0.00 s / 99 MB | 11 ms / 0.02 s / 176 MB | 5 ms / 0.01 s / 116 MB | 7 ms / 0.02 s / 192 MB |
| read + pass | pyarrow | 17 ms / 0.02 s / 151 MB | 34 ms / 0.04 s / 221 MB | 18 ms / 0.02 s / 158 MB | 24 ms / 0.03 s / 225 MB |
| read + pass | polars | 17 ms / 0.02 s / 150 MB | 34 ms / 0.04 s / 222 MB | 18 ms / 0.02 s / 156 MB | 23 ms / 0.03 s / 225 MB |
| read + pass | ours | 18 ms / 0.02 s / 151 MB | 34 ms / 0.04 s / 222 MB | 18 ms / 0.02 s / 156 MB | 23 ms / 0.03 s / 231 MB |
| write, defaults | dta | 10 ms / 0.01 s / 114 MB | 118 ms / 0.12 s / 198 MB | 22 ms / 0.02 s / 135 MB | 25 ms / 0.03 s / 210 MB |
| write, zstd 3 | dta | 12 ms / 0.01 s / 113 MB | 119 ms / 0.12 s / 199 MB | 24 ms / 0.03 s / 137 MB | 27 ms / 0.03 s / 211 MB |

### 1982_FemResp

7,969 rows, 741 columns; .dta 7.6 MB; Parquet pyarrow 1.8 MB, polars 1.5 MB, ours 2.1 MB, duckdb 1.7 MB, ours_zstd 1.8 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 8 ms / 0.01 s / 125 MB | 18 ms / 0.06 s / 210 MB | 16 ms / 0.02 s / 160 MB | 36 ms / 0.06 s / 248 MB |
| whole file | polars | 9 ms / 0.02 s / 126 MB | 18 ms / 0.06 s / 211 MB | 19 ms / 0.02 s / 159 MB | 39 ms / 0.06 s / 247 MB |
| whole file | ours | 10 ms / 0.02 s / 127 MB | 18 ms / 0.05 s / 210 MB | 16 ms / 0.02 s / 160 MB | 36 ms / 0.06 s / 248 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 99 MB | 16 ms / 0.02 s / 167 MB | 4 ms / 0.00 s / 112 MB | 4 ms / 0.01 s / 169 MB |
| five columns | polars | 1 ms / 0.00 s / 98 MB | 15 ms / 0.02 s / 167 MB | 3 ms / 0.00 s / 111 MB | 4 ms / 0.00 s / 169 MB |
| five columns | ours | 3 ms / 0.00 s / 102 MB | 15 ms / 0.02 s / 171 MB | 4 ms / 0.00 s / 112 MB | 4 ms / 0.01 s / 169 MB |
| 1,000 rows | pyarrow | 6 ms / 0.01 s / 103 MB | 20 ms / 0.06 s / 211 MB | 20 ms / 0.02 s / 162 MB | 37 ms / 0.14 s / 404 MB |
| 1,000 rows | polars | 8 ms / 0.01 s / 103 MB | 20 ms / 0.06 s / 209 MB | 22 ms / 0.02 s / 163 MB | 39 ms / 0.14 s / 403 MB |
| 1,000 rows | ours | 8 ms / 0.01 s / 106 MB | 21 ms / 0.06 s / 212 MB | 19 ms / 0.02 s / 163 MB | 36 ms / 0.13 s / 405 MB |
| read + pass | pyarrow | 44 ms / 0.05 s / 164 MB | 91 ms / 0.13 s / 268 MB | 53 ms / 0.05 s / 199 MB | 71 ms / 0.09 s / 273 MB |
| read + pass | polars | 46 ms / 0.05 s / 162 MB | 90 ms / 0.13 s / 267 MB | 55 ms / 0.06 s / 199 MB | 75 ms / 0.10 s / 284 MB |
| read + pass | ours | 48 ms / 0.06 s / 166 MB | 90 ms / 0.13 s / 265 MB | 51 ms / 0.05 s / 195 MB | 72 ms / 0.09 s / 281 MB |
| write, defaults | dta | 30 ms / 0.05 s / 160 MB | 1.31 s / 1.31 s / 249 MB | 111 ms / 0.11 s / 191 MB | 97 ms / 0.13 s / 337 MB |
| write, zstd 3 | dta | 33 ms / 0.06 s / 161 MB | 1.32 s / 1.32 s / 252 MB | 119 ms / 0.12 s / 193 MB | 102 ms / 0.16 s / 337 MB |

### 1982_Preg

13,768 rows, 174 columns; .dta 3.0 MB; Parquet pyarrow 0.4 MB, polars 0.4 MB, ours 0.5 MB, duckdb 0.4 MB, ours_zstd 0.5 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 5 ms / 0.01 s / 109 MB | 13 ms / 0.03 s / 181 MB | 6 ms / 0.01 s / 126 MB | 14 ms / 0.02 s / 193 MB |
| whole file | polars | 5 ms / 0.01 s / 108 MB | 12 ms / 0.02 s / 181 MB | 7 ms / 0.01 s / 124 MB | 14 ms / 0.02 s / 195 MB |
| whole file | ours | 5 ms / 0.01 s / 110 MB | 11 ms / 0.02 s / 180 MB | 6 ms / 0.01 s / 123 MB | 14 ms / 0.02 s / 194 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 98 MB | 13 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 100 MB | 3 ms / 0.00 s / 167 MB |
| five columns | polars | 1 ms / 0.00 s / 97 MB | 13 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 102 MB | 3 ms / 0.00 s / 168 MB |
| five columns | ours | 2 ms / 0.00 s / 100 MB | 13 ms / 0.01 s / 167 MB | 2 ms / 0.00 s / 102 MB | 3 ms / 0.00 s / 168 MB |
| 1,000 rows | pyarrow | 2 ms / 0.00 s / 99 MB | 12 ms / 0.02 s / 182 MB | 7 ms / 0.01 s / 126 MB | 11 ms / 0.04 s / 225 MB |
| 1,000 rows | polars | 2 ms / 0.00 s / 99 MB | 13 ms / 0.03 s / 182 MB | 8 ms / 0.01 s / 125 MB | 11 ms / 0.03 s / 220 MB |
| 1,000 rows | ours | 3 ms / 0.00 s / 99 MB | 12 ms / 0.02 s / 182 MB | 7 ms / 0.01 s / 124 MB | 12 ms / 0.03 s / 213 MB |
| read + pass | pyarrow | 20 ms / 0.02 s / 157 MB | 42 ms / 0.06 s / 229 MB | 22 ms / 0.02 s / 162 MB | 29 ms / 0.04 s / 232 MB |
| read + pass | polars | 20 ms / 0.02 s / 157 MB | 41 ms / 0.06 s / 230 MB | 21 ms / 0.02 s / 162 MB | 29 ms / 0.04 s / 232 MB |
| read + pass | ours | 21 ms / 0.02 s / 158 MB | 42 ms / 0.05 s / 229 MB | 21 ms / 0.02 s / 161 MB | 29 ms / 0.04 s / 234 MB |
| write, defaults | dta | 12 ms / 0.01 s / 124 MB | 313 ms / 0.32 s / 211 MB | 26 ms / 0.03 s / 163 MB | 34 ms / 0.04 s / 231 MB |
| write, zstd 3 | dta | 14 ms / 0.01 s / 123 MB | 303 ms / 0.30 s / 213 MB | 28 ms / 0.03 s / 161 MB | 36 ms / 0.04 s / 233 MB |

### 1988_FemResp

8,450 rows, 1,437 columns; .dta 19.1 MB; Parquet pyarrow 6.1 MB, polars 5.1 MB, ours 6.6 MB, duckdb 5.4 MB, ours_zstd 5.5 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 16 ms / 0.03 s / 173 MB | 27 ms / 0.10 s / 256 MB | 47 ms / 0.05 s / 275 MB | 73 ms / 0.11 s / 366 MB |
| whole file | polars | 19 ms / 0.03 s / 173 MB | 28 ms / 0.11 s / 257 MB | 54 ms / 0.05 s / 273 MB | 82 ms / 0.13 s / 366 MB |
| whole file | ours | 19 ms / 0.03 s / 179 MB | 28 ms / 0.10 s / 260 MB | 46 ms / 0.05 s / 273 MB | 74 ms / 0.11 s / 367 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 100 MB | 17 ms / 0.02 s / 170 MB | 5 ms / 0.01 s / 126 MB | 6 ms / 0.01 s / 170 MB |
| five columns | polars | 2 ms / 0.00 s / 98 MB | 16 ms / 0.02 s / 169 MB | 5 ms / 0.01 s / 125 MB | 5 ms / 0.01 s / 171 MB |
| five columns | ours | 4 ms / 0.00 s / 104 MB | 17 ms / 0.02 s / 173 MB | 5 ms / 0.01 s / 128 MB | 5 ms / 0.01 s / 172 MB |
| 1,000 rows | pyarrow | 12 ms / 0.01 s / 107 MB | 30 ms / 0.10 s / 257 MB | 52 ms / 0.05 s / 289 MB | 69 ms / 0.28 s / 621 MB |
| 1,000 rows | polars | 17 ms / 0.02 s / 106 MB | 31 ms / 0.12 s / 255 MB | 60 ms / 0.06 s / 288 MB | 73 ms / 0.26 s / 600 MB |
| 1,000 rows | ours | 15 ms / 0.01 s / 111 MB | 30 ms / 0.10 s / 259 MB | 52 ms / 0.05 s / 288 MB | 70 ms / 0.27 s / 617 MB |
| read + pass | pyarrow | 98 ms / 0.11 s / 212 MB | 173 ms / 0.25 s / 325 MB | 117 ms / 0.12 s / 318 MB | 165 ms / 0.20 s / 405 MB |
| read + pass | polars | 100 ms / 0.11 s / 243 MB | 172 ms / 0.25 s / 333 MB | 123 ms / 0.12 s / 290 MB | 171 ms / 0.22 s / 400 MB |
| read + pass | ours | 103 ms / 0.12 s / 218 MB | 168 ms / 0.24 s / 392 MB | 114 ms / 0.11 s / 288 MB | 166 ms / 0.20 s / 435 MB |
| write, defaults | dta | 78 ms / 0.12 s / 284 MB | 2.36 s / 2.38 s / 357 MB | 250 ms / 0.25 s / 335 MB | 189 ms / 0.30 s / 577 MB |
| write, zstd 3 | dta | 85 ms / 0.14 s / 284 MB | 2.41 s / 2.42 s / 363 MB | 278 ms / 0.28 s / 327 MB | 214 ms / 0.35 s / 577 MB |

### 1988_Preg

15,759 rows, 284 columns; .dta 10.7 MB; Parquet pyarrow 3.3 MB, polars 2.8 MB, ours 3.5 MB, duckdb 3.6 MB, ours_zstd 3.0 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 7 ms / 0.01 s / 118 MB | 13 ms / 0.03 s / 194 MB | 12 ms / 0.01 s / 143 MB | 21 ms / 0.04 s / 219 MB |
| whole file | polars | 8 ms / 0.01 s / 119 MB | 15 ms / 0.04 s / 193 MB | 15 ms / 0.01 s / 144 MB | 24 ms / 0.04 s / 220 MB |
| whole file | ours | 8 ms / 0.01 s / 120 MB | 13 ms / 0.04 s / 194 MB | 12 ms / 0.01 s / 143 MB | 22 ms / 0.04 s / 221 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 167 MB | 2 ms / 0.00 s / 105 MB | 3 ms / 0.00 s / 169 MB |
| five columns | polars | 1 ms / 0.00 s / 100 MB | 13 ms / 0.01 s / 167 MB | 3 ms / 0.00 s / 104 MB | 3 ms / 0.00 s / 168 MB |
| five columns | ours | 2 ms / 0.00 s / 99 MB | 14 ms / 0.01 s / 168 MB | 2 ms / 0.00 s / 102 MB | 3 ms / 0.00 s / 168 MB |
| 1,000 rows | pyarrow | 5 ms / 0.01 s / 100 MB | 15 ms / 0.04 s / 193 MB | 13 ms / 0.01 s / 146 MB | 17 ms / 0.06 s / 265 MB |
| 1,000 rows | polars | 7 ms / 0.01 s / 100 MB | 15 ms / 0.04 s / 193 MB | 16 ms / 0.02 s / 144 MB | 19 ms / 0.06 s / 253 MB |
| 1,000 rows | ours | 6 ms / 0.01 s / 101 MB | 15 ms / 0.04 s / 193 MB | 13 ms / 0.01 s / 143 MB | 16 ms / 0.05 s / 264 MB |
| read + pass | pyarrow | 33 ms / 0.04 s / 164 MB | 65 ms / 0.09 s / 245 MB | 38 ms / 0.04 s / 170 MB | 48 ms / 0.06 s / 255 MB |
| read + pass | polars | 34 ms / 0.04 s / 162 MB | 65 ms / 0.09 s / 247 MB | 42 ms / 0.04 s / 174 MB | 50 ms / 0.07 s / 254 MB |
| read + pass | ours | 35 ms / 0.04 s / 167 MB | 65 ms / 0.09 s / 248 MB | 37 ms / 0.04 s / 175 MB | 49 ms / 0.06 s / 265 MB |
| write, defaults | dta | 22 ms / 0.04 s / 133 MB | 373 ms / 0.37 s / 223 MB | 73 ms / 0.07 s / 169 MB | 66 ms / 0.11 s / 274 MB |
| write, zstd 3 | dta | 24 ms / 0.04 s / 134 MB | 383 ms / 0.39 s / 223 MB | 85 ms / 0.09 s / 170 MB | 74 ms / 0.13 s / 273 MB |

### 1995_FemResp

10,847 rows, 5,754 columns; .dta 78.9 MB; Parquet pyarrow 7.5 MB, polars 6.7 MB, ours 9.5 MB, duckdb 7.1 MB, ours_zstd 8.3 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 57 ms / 0.10 s / 392 MB | 78 ms / 0.34 s / 539 MB | 173 ms / 0.17 s / 852 MB | 541 ms / 0.74 s / 979 MB |
| whole file | polars | 60 ms / 0.10 s / 394 MB | 79 ms / 0.36 s / 540 MB | 186 ms / 0.19 s / 851 MB | 562 ms / 0.75 s / 986 MB |
| whole file | ours | 75 ms / 0.11 s / 415 MB | 80 ms / 0.33 s / 549 MB | 178 ms / 0.18 s / 738 MB | 569 ms / 0.78 s / 987 MB |
| five columns | pyarrow | 4 ms / 0.01 s / 103 MB | 28 ms / 0.03 s / 184 MB | 69 ms / 0.07 s / 214 MB | 16 ms / 0.02 s / 182 MB |
| five columns | polars | 3 ms / 0.00 s / 101 MB | 29 ms / 0.03 s / 182 MB | 66 ms / 0.07 s / 211 MB | 14 ms / 0.01 s / 182 MB |
| five columns | ours | 12 ms / 0.01 s / 120 MB | 32 ms / 0.03 s / 189 MB | 65 ms / 0.07 s / 213 MB | 14 ms / 0.01 s / 186 MB |
| 1,000 rows | pyarrow | 18 ms / 0.03 s / 133 MB | 91 ms / 0.36 s / 553 MB | 206 ms / 0.21 s / 878 MB | 377 ms / 1.22 s / 1994 MB |
| 1,000 rows | polars | 21 ms / 0.04 s / 134 MB | 89 ms / 0.38 s / 547 MB | 209 ms / 0.21 s / 877 MB | 377 ms / 1.20 s / 1990 MB |
| 1,000 rows | ours | 31 ms / 0.04 s / 157 MB | 89 ms / 0.35 s / 561 MB | 191 ms / 0.19 s / 766 MB | 367 ms / 1.24 s / 1997 MB |
| read + pass | pyarrow | 323 ms / 0.36 s / 465 MB | 676 ms / 0.95 s / 643 MB | 455 ms / 0.46 s / 886 MB | 823 ms / 1.01 s / 1169 MB |
| read + pass | polars | 321 ms / 0.36 s / 474 MB | 680 ms / 0.97 s / 653 MB | 463 ms / 0.46 s / 909 MB | 833 ms / 1.04 s / 1094 MB |
| read + pass | ours | 353 ms / 0.39 s / 494 MB | 674 ms / 0.92 s / 659 MB | 434 ms / 0.43 s / 759 MB | 836 ms / 1.05 s / 1169 MB |
| write, defaults | dta | 223 ms / 0.35 s / 732 MB | 9.81 s / 9.85 s / 861 MB | 655 ms / 0.65 s / 866 MB | 1.04 s / 1.60 s / 1614 MB |
| write, zstd 3 | dta | 236 ms / 0.38 s / 736 MB | 9.87 s / 9.93 s / 864 MB | 697 ms / 0.70 s / 860 MB | 1.07 s / 1.67 s / 1611 MB |

### 1995_Preg

21,332 rows, 245 columns; .dta 6.2 MB; Parquet pyarrow 1.3 MB, polars 1.1 MB, ours 1.4 MB, duckdb 1.2 MB, ours_zstd 1.2 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 6 ms / 0.01 s / 124 MB | 13 ms / 0.04 s / 196 MB | 12 ms / 0.01 s / 157 MB | 27 ms / 0.04 s / 223 MB |
| whole file | polars | 7 ms / 0.01 s / 125 MB | 14 ms / 0.04 s / 195 MB | 13 ms / 0.01 s / 160 MB | 27 ms / 0.04 s / 223 MB |
| whole file | ours | 7 ms / 0.01 s / 127 MB | 15 ms / 0.04 s / 197 MB | 12 ms / 0.01 s / 157 MB | 25 ms / 0.04 s / 222 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 167 MB | 3 ms / 0.00 s / 104 MB | 3 ms / 0.01 s / 168 MB |
| five columns | polars | 1 ms / 0.00 s / 99 MB | 14 ms / 0.01 s / 167 MB | 3 ms / 0.00 s / 102 MB | 3 ms / 0.00 s / 168 MB |
| five columns | ours | 2 ms / 0.00 s / 100 MB | 13 ms / 0.01 s / 167 MB | 3 ms / 0.00 s / 104 MB | 3 ms / 0.00 s / 168 MB |
| 1,000 rows | pyarrow | 4 ms / 0.00 s / 98 MB | 15 ms / 0.04 s / 198 MB | 13 ms / 0.01 s / 161 MB | 14 ms / 0.05 s / 241 MB |
| 1,000 rows | polars | 4 ms / 0.01 s / 101 MB | 15 ms / 0.04 s / 198 MB | 14 ms / 0.01 s / 158 MB | 15 ms / 0.05 s / 250 MB |
| 1,000 rows | ours | 4 ms / 0.01 s / 102 MB | 15 ms / 0.04 s / 198 MB | 13 ms / 0.01 s / 159 MB | 14 ms / 0.05 s / 246 MB |
| read + pass | pyarrow | 34 ms / 0.04 s / 167 MB | 74 ms / 0.10 s / 258 MB | 41 ms / 0.04 s / 179 MB | 56 ms / 0.07 s / 256 MB |
| read + pass | polars | 36 ms / 0.04 s / 168 MB | 77 ms / 0.10 s / 257 MB | 43 ms / 0.04 s / 203 MB | 55 ms / 0.07 s / 254 MB |
| read + pass | ours | 36 ms / 0.04 s / 166 MB | 72 ms / 0.10 s / 257 MB | 42 ms / 0.04 s / 181 MB | 55 ms / 0.07 s / 255 MB |
| write, defaults | dta | 18 ms / 0.03 s / 149 MB | 462 ms / 0.47 s / 238 MB | 70 ms / 0.07 s / 172 MB | 69 ms / 0.11 s / 303 MB |
| write, zstd 3 | dta | 20 ms / 0.04 s / 153 MB | 452 ms / 0.46 s / 238 MB | 73 ms / 0.07 s / 175 MB | 74 ms / 0.12 s / 303 MB |

### 2002_FemPreg

13,593 rows, 243 columns; .dta 4.3 MB; Parquet pyarrow 1.0 MB, polars 0.8 MB, ours 1.1 MB, duckdb 1.0 MB, ours_zstd 0.9 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 7 ms / 0.01 s / 114 MB | 13 ms / 0.03 s / 189 MB | 9 ms / 0.01 s / 138 MB | 18 ms / 0.03 s / 205 MB |
| whole file | polars | 8 ms / 0.01 s / 116 MB | 13 ms / 0.03 s / 189 MB | 10 ms / 0.01 s / 135 MB | 19 ms / 0.03 s / 205 MB |
| whole file | ours | 7 ms / 0.01 s / 115 MB | 13 ms / 0.03 s / 189 MB | 9 ms / 0.01 s / 136 MB | 19 ms / 0.03 s / 204 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 99 MB | 14 ms / 0.01 s / 165 MB | 3 ms / 0.00 s / 102 MB | 3 ms / 0.01 s / 168 MB |
| five columns | polars | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 167 MB | 3 ms / 0.00 s / 104 MB | 3 ms / 0.01 s / 168 MB |
| five columns | ours | 2 ms / 0.00 s / 101 MB | 13 ms / 0.01 s / 167 MB | 3 ms / 0.00 s / 102 MB | 3 ms / 0.00 s / 168 MB |
| 1,000 rows | pyarrow | 3 ms / 0.00 s / 100 MB | 14 ms / 0.03 s / 189 MB | 10 ms / 0.01 s / 138 MB | 13 ms / 0.05 s / 249 MB |
| 1,000 rows | polars | 4 ms / 0.00 s / 101 MB | 14 ms / 0.03 s / 189 MB | 11 ms / 0.01 s / 138 MB | 14 ms / 0.05 s / 249 MB |
| 1,000 rows | ours | 4 ms / 0.00 s / 101 MB | 14 ms / 0.03 s / 189 MB | 10 ms / 0.01 s / 136 MB | 14 ms / 0.05 s / 246 MB |
| read + pass | pyarrow | 29 ms / 0.03 s / 167 MB | 55 ms / 0.07 s / 248 MB | 30 ms / 0.03 s / 170 MB | 39 ms / 0.05 s / 245 MB |
| read + pass | polars | 30 ms / 0.03 s / 173 MB | 54 ms / 0.07 s / 245 MB | 30 ms / 0.03 s / 169 MB | 41 ms / 0.05 s / 245 MB |
| read + pass | ours | 31 ms / 0.03 s / 179 MB | 54 ms / 0.07 s / 242 MB | 29 ms / 0.03 s / 181 MB | 39 ms / 0.05 s / 248 MB |
| write, defaults | dta | 20 ms / 0.02 s / 131 MB | 346 ms / 0.35 s / 217 MB | 44 ms / 0.04 s / 172 MB | 46 ms / 0.07 s / 251 MB |
| write, zstd 3 | dta | 23 ms / 0.02 s / 131 MB | 347 ms / 0.35 s / 221 MB | 49 ms / 0.05 s / 171 MB | 50 ms / 0.08 s / 252 MB |

### 2002_FemResp

7,643 rows, 3,087 columns; .dta 29.3 MB; Parquet pyarrow 3.8 MB, polars 3.4 MB, ours 4.9 MB, duckdb 3.6 MB, ours_zstd 4.3 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 31 ms / 0.05 s / 209 MB | 44 ms / 0.17 s / 335 MB | 72 ms / 0.07 s / 362 MB | 206 ms / 0.28 s / 500 MB |
| whole file | polars | 33 ms / 0.05 s / 210 MB | 44 ms / 0.18 s / 334 MB | 77 ms / 0.08 s / 361 MB | 212 ms / 0.29 s / 498 MB |
| whole file | ours | 40 ms / 0.06 s / 221 MB | 42 ms / 0.16 s / 342 MB | 68 ms / 0.07 s / 341 MB | 212 ms / 0.29 s / 502 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 102 MB | 21 ms / 0.02 s / 175 MB | 30 ms / 0.03 s / 158 MB | 10 ms / 0.01 s / 174 MB |
| five columns | polars | 3 ms / 0.00 s / 100 MB | 21 ms / 0.02 s / 176 MB | 29 ms / 0.03 s / 156 MB | 9 ms / 0.01 s / 173 MB |
| five columns | ours | 8 ms / 0.01 s / 113 MB | 23 ms / 0.02 s / 180 MB | 30 ms / 0.03 s / 160 MB | 9 ms / 0.01 s / 174 MB |
| 1,000 rows | pyarrow | 14 ms / 0.01 s / 118 MB | 49 ms / 0.17 s / 335 MB | 98 ms / 0.10 s / 375 MB | 163 ms / 0.59 s / 1151 MB |
| 1,000 rows | polars | 18 ms / 0.02 s / 116 MB | 50 ms / 0.19 s / 337 MB | 104 ms / 0.10 s / 377 MB | 177 ms / 0.59 s / 1155 MB |
| 1,000 rows | ours | 21 ms / 0.02 s / 129 MB | 56 ms / 0.17 s / 345 MB | 97 ms / 0.10 s / 350 MB | 168 ms / 0.62 s / 1153 MB |
| read + pass | pyarrow | 138 ms / 0.15 s / 249 MB | 288 ms / 0.42 s / 415 MB | 196 ms / 0.20 s / 424 MB | 318 ms / 0.39 s / 520 MB |
| read + pass | polars | 145 ms / 0.16 s / 249 MB | 287 ms / 0.42 s / 396 MB | 199 ms / 0.20 s / 423 MB | 334 ms / 0.41 s / 521 MB |
| read + pass | ours | 161 ms / 0.18 s / 257 MB | 284 ms / 0.41 s / 399 MB | 195 ms / 0.20 s / 392 MB | 324 ms / 0.41 s / 522 MB |
| write, defaults | dta | 112 ms / 0.17 s / 352 MB | 4.79 s / 4.83 s / 449 MB | 311 ms / 0.31 s / 396 MB | 371 ms / 0.57 s / 881 MB |
| write, zstd 3 | dta | 120 ms / 0.18 s / 354 MB | 4.86 s / 4.90 s / 447 MB | 333 ms / 0.33 s / 397 MB | 390 ms / 0.60 s / 881 MB |

### 2002_HHvars

12,571 rows, 10 columns; .dta 0.1 MB; Parquet pyarrow 0.1 MB, polars 0.1 MB, ours 0.1 MB, duckdb 0.1 MB, ours_zstd 0.1 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 1 ms / 0.00 s / 98 MB | 9 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 99 MB | 2 ms / 0.00 s / 169 MB |
| whole file | polars | 1 ms / 0.00 s / 96 MB | 9 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 100 MB | 2 ms / 0.00 s / 169 MB |
| whole file | ours | 1 ms / 0.00 s / 98 MB | 9 ms / 0.01 s / 165 MB | 2 ms / 0.00 s / 99 MB | 2 ms / 0.00 s / 169 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 98 MB | 13 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 98 MB | 2 ms / 0.00 s / 167 MB |
| five columns | polars | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 99 MB | 2 ms / 0.00 s / 168 MB |
| five columns | ours | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 99 MB | 2 ms / 0.00 s / 167 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 99 MB | 9 ms / 0.01 s / 167 MB | 2 ms / 0.00 s / 99 MB | 3 ms / 0.01 s / 176 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 99 MB | 9 ms / 0.01 s / 167 MB | 2 ms / 0.00 s / 98 MB | 3 ms / 0.01 s / 177 MB |
| 1,000 rows | ours | 1 ms / 0.00 s / 99 MB | 9 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 98 MB | 3 ms / 0.01 s / 175 MB |
| read + pass | pyarrow | 5 ms / 0.01 s / 103 MB | 14 ms / 0.01 s / 169 MB | 6 ms / 0.01 s / 102 MB | 7 ms / 0.01 s / 172 MB |
| read + pass | polars | 5 ms / 0.01 s / 103 MB | 14 ms / 0.01 s / 169 MB | 6 ms / 0.01 s / 103 MB | 7 ms / 0.01 s / 171 MB |
| read + pass | ours | 6 ms / 0.01 s / 103 MB | 14 ms / 0.01 s / 168 MB | 6 ms / 0.01 s / 101 MB | 7 ms / 0.01 s / 171 MB |
| write, defaults | dta | 2 ms / 0.00 s / 98 MB | 29 ms / 0.03 s / 179 MB | 5 ms / 0.01 s / 103 MB | 4 ms / 0.01 s / 172 MB |
| write, zstd 3 | dta | 2 ms / 0.00 s / 100 MB | 30 ms / 0.03 s / 178 MB | 6 ms / 0.01 s / 103 MB | 5 ms / 0.01 s / 171 MB |

### 2002_Male

4,928 rows, 1,993 columns; .dta 12.7 MB; Parquet pyarrow 1.8 MB, polars 1.7 MB, ours 2.1 MB, duckdb 1.7 MB, ours_zstd 1.9 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 10 ms / 0.02 s / 147 MB | 28 ms / 0.10 s / 237 MB | 26 ms / 0.03 s / 214 MB | 81 ms / 0.12 s / 343 MB |
| whole file | polars | 12 ms / 0.02 s / 147 MB | 33 ms / 0.10 s / 239 MB | 30 ms / 0.03 s / 213 MB | 88 ms / 0.13 s / 343 MB |
| whole file | ours | 13 ms / 0.02 s / 151 MB | 28 ms / 0.09 s / 237 MB | 25 ms / 0.03 s / 204 MB | 86 ms / 0.12 s / 342 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 101 MB | 18 ms / 0.02 s / 172 MB | 7 ms / 0.01 s / 135 MB | 7 ms / 0.01 s / 173 MB |
| five columns | polars | 2 ms / 0.00 s / 101 MB | 18 ms / 0.02 s / 171 MB | 6 ms / 0.01 s / 136 MB | 7 ms / 0.01 s / 171 MB |
| five columns | ours | 4 ms / 0.01 s / 103 MB | 19 ms / 0.02 s / 176 MB | 6 ms / 0.01 s / 136 MB | 6 ms / 0.01 s / 172 MB |
| 1,000 rows | pyarrow | 8 ms / 0.01 s / 109 MB | 32 ms / 0.10 s / 240 MB | 35 ms / 0.04 s / 229 MB | 97 ms / 0.37 s / 804 MB |
| 1,000 rows | polars | 11 ms / 0.01 s / 108 MB | 34 ms / 0.11 s / 238 MB | 38 ms / 0.04 s / 227 MB | 98 ms / 0.37 s / 788 MB |
| 1,000 rows | ours | 11 ms / 0.01 s / 112 MB | 32 ms / 0.09 s / 240 MB | 34 ms / 0.03 s / 217 MB | 95 ms / 0.38 s / 779 MB |
| read + pass | pyarrow | 62 ms / 0.07 s / 171 MB | 137 ms / 0.20 s / 299 MB | 80 ms / 0.08 s / 231 MB | 139 ms / 0.17 s / 353 MB |
| read + pass | polars | 64 ms / 0.07 s / 171 MB | 139 ms / 0.21 s / 299 MB | 82 ms / 0.08 s / 239 MB | 138 ms / 0.17 s / 355 MB |
| read + pass | ours | 70 ms / 0.08 s / 176 MB | 138 ms / 0.20 s / 312 MB | 77 ms / 0.08 s / 226 MB | 138 ms / 0.17 s / 356 MB |
| write, defaults | dta | 47 ms / 0.07 s / 216 MB | 2.65 s / 2.68 s / 292 MB | 162 ms / 0.16 s / 245 MB | 171 ms / 0.26 s / 502 MB |
| write, zstd 3 | dta | 52 ms / 0.08 s / 216 MB | 2.72 s / 2.73 s / 292 MB | 175 ms / 0.17 s / 245 MB | 202 ms / 0.30 s / 489 MB |

### 2002_curr_ins

12,571 rows, 3 columns; .dta 0.1 MB; Parquet pyarrow 0.1 MB, polars 0.0 MB, ours 0.1 MB, duckdb 0.1 MB, ours_zstd 0.0 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 1 ms / 0.00 s / 98 MB | 9 ms / 0.01 s / 165 MB | 2 ms / 0.00 s / 98 MB | 2 ms / 0.00 s / 167 MB |
| whole file | polars | 1 ms / 0.00 s / 98 MB | 9 ms / 0.01 s / 165 MB | 2 ms / 0.00 s / 99 MB | 2 ms / 0.00 s / 167 MB |
| whole file | ours | 1 ms / 0.00 s / 99 MB | 8 ms / 0.01 s / 164 MB | 2 ms / 0.00 s / 98 MB | 2 ms / 0.00 s / 167 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 98 MB | 12 ms / 0.01 s / 168 MB | 2 ms / 0.00 s / 97 MB | 2 ms / 0.00 s / 168 MB |
| five columns | polars | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 97 MB | 2 ms / 0.00 s / 167 MB |
| five columns | ours | 1 ms / 0.00 s / 97 MB | 13 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 98 MB | 2 ms / 0.00 s / 167 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 98 MB | 9 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 99 MB | 3 ms / 0.01 s / 175 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 98 MB | 9 ms / 0.01 s / 165 MB | 2 ms / 0.00 s / 98 MB | 3 ms / 0.01 s / 173 MB |
| 1,000 rows | ours | 1 ms / 0.00 s / 97 MB | 10 ms / 0.01 s / 164 MB | 2 ms / 0.00 s / 98 MB | 3 ms / 0.01 s / 174 MB |
| read + pass | pyarrow | 5 ms / 0.01 s / 99 MB | 12 ms / 0.01 s / 164 MB | 5 ms / 0.01 s / 99 MB | 6 ms / 0.01 s / 167 MB |
| read + pass | polars | 5 ms / 0.01 s / 98 MB | 12 ms / 0.01 s / 166 MB | 5 ms / 0.01 s / 99 MB | 6 ms / 0.01 s / 168 MB |
| read + pass | ours | 5 ms / 0.01 s / 99 MB | 12 ms / 0.01 s / 164 MB | 5 ms / 0.01 s / 98 MB | 6 ms / 0.01 s / 169 MB |
| write, defaults | dta | 1 ms / 0.00 s / 99 MB | 10 ms / 0.01 s / 172 MB | 4 ms / 0.00 s / 100 MB | 3 ms / 0.01 s / 169 MB |
| write, zstd 3 | dta | 1 ms / 0.00 s / 97 MB | 10 ms / 0.01 s / 171 MB | 4 ms / 0.00 s / 100 MB | 3 ms / 0.01 s / 169 MB |

### 2002_hhpartypnew

12,571 rows, 3 columns; .dta 0.1 MB; Parquet pyarrow 0.1 MB, polars 0.0 MB, ours 0.1 MB, duckdb 0.1 MB, ours_zstd 0.0 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 1 ms / 0.00 s / 97 MB | 9 ms / 0.01 s / 165 MB | 2 ms / 0.00 s / 98 MB | 2 ms / 0.00 s / 167 MB |
| whole file | polars | 1 ms / 0.00 s / 97 MB | 9 ms / 0.01 s / 164 MB | 2 ms / 0.00 s / 98 MB | 2 ms / 0.00 s / 168 MB |
| whole file | ours | 1 ms / 0.00 s / 98 MB | 9 ms / 0.01 s / 164 MB | 2 ms / 0.00 s / 98 MB | 2 ms / 0.00 s / 167 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 168 MB | 2 ms / 0.00 s / 98 MB | 2 ms / 0.00 s / 167 MB |
| five columns | polars | 1 ms / 0.00 s / 96 MB | 13 ms / 0.01 s / 165 MB | 2 ms / 0.00 s / 99 MB | 2 ms / 0.00 s / 167 MB |
| five columns | ours | 1 ms / 0.00 s / 98 MB | 12 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 96 MB | 2 ms / 0.00 s / 167 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 98 MB | 9 ms / 0.01 s / 165 MB | 2 ms / 0.00 s / 98 MB | 3 ms / 0.00 s / 174 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 96 MB | 9 ms / 0.01 s / 164 MB | 2 ms / 0.00 s / 97 MB | 3 ms / 0.01 s / 173 MB |
| 1,000 rows | ours | 1 ms / 0.00 s / 98 MB | 9 ms / 0.01 s / 165 MB | 2 ms / 0.00 s / 98 MB | 3 ms / 0.01 s / 173 MB |
| read + pass | pyarrow | 5 ms / 0.01 s / 99 MB | 12 ms / 0.01 s / 165 MB | 5 ms / 0.01 s / 98 MB | 6 ms / 0.01 s / 168 MB |
| read + pass | polars | 5 ms / 0.01 s / 100 MB | 12 ms / 0.01 s / 166 MB | 5 ms / 0.01 s / 99 MB | 6 ms / 0.01 s / 168 MB |
| read + pass | ours | 5 ms / 0.01 s / 99 MB | 12 ms / 0.01 s / 165 MB | 5 ms / 0.01 s / 101 MB | 6 ms / 0.01 s / 168 MB |
| write, defaults | dta | 1 ms / 0.00 s / 98 MB | 10 ms / 0.01 s / 171 MB | 4 ms / 0.00 s / 100 MB | 3 ms / 0.00 s / 169 MB |
| write, zstd 3 | dta | 1 ms / 0.00 s / 99 MB | 10 ms / 0.01 s / 171 MB | 4 ms / 0.00 s / 99 MB | 4 ms / 0.01 s / 168 MB |

### 2006_2010_FemPreg

20,492 rows, 287 columns; .dta 7.6 MB; Parquet pyarrow 1.7 MB, polars 1.4 MB, ours 1.7 MB, duckdb 1.6 MB, ours_zstd 1.5 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 7 ms / 0.01 s / 128 MB | 14 ms / 0.04 s / 205 MB | 13 ms / 0.01 s / 171 MB | 28 ms / 0.05 s / 234 MB |
| whole file | polars | 7 ms / 0.01 s / 130 MB | 14 ms / 0.04 s / 204 MB | 14 ms / 0.01 s / 169 MB | 29 ms / 0.05 s / 234 MB |
| whole file | ours | 7 ms / 0.01 s / 130 MB | 14 ms / 0.04 s / 203 MB | 13 ms / 0.01 s / 167 MB | 28 ms / 0.04 s / 233 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 100 MB | 14 ms / 0.01 s / 167 MB | 3 ms / 0.00 s / 105 MB | 3 ms / 0.01 s / 169 MB |
| five columns | polars | 1 ms / 0.00 s / 99 MB | 14 ms / 0.01 s / 169 MB | 3 ms / 0.00 s / 104 MB | 3 ms / 0.00 s / 167 MB |
| five columns | ours | 2 ms / 0.00 s / 98 MB | 14 ms / 0.01 s / 167 MB | 3 ms / 0.00 s / 105 MB | 3 ms / 0.00 s / 169 MB |
| 1,000 rows | pyarrow | 4 ms / 0.00 s / 100 MB | 18 ms / 0.04 s / 204 MB | 15 ms / 0.02 s / 170 MB | 16 ms / 0.05 s / 257 MB |
| 1,000 rows | polars | 5 ms / 0.01 s / 100 MB | 15 ms / 0.04 s / 205 MB | 15 ms / 0.02 s / 171 MB | 17 ms / 0.06 s / 266 MB |
| 1,000 rows | ours | 4 ms / 0.01 s / 100 MB | 15 ms / 0.04 s / 205 MB | 14 ms / 0.01 s / 169 MB | 15 ms / 0.05 s / 255 MB |
| read + pass | pyarrow | 40 ms / 0.05 s / 171 MB | 82 ms / 0.11 s / 266 MB | 46 ms / 0.05 s / 204 MB | 60 ms / 0.08 s / 265 MB |
| read + pass | polars | 42 ms / 0.05 s / 196 MB | 82 ms / 0.11 s / 269 MB | 46 ms / 0.05 s / 185 MB | 61 ms / 0.08 s / 298 MB |
| read + pass | ours | 40 ms / 0.05 s / 171 MB | 81 ms / 0.11 s / 266 MB | 44 ms / 0.05 s / 200 MB | 68 ms / 0.08 s / 272 MB |
| write, defaults | dta | 20 ms / 0.04 s / 158 MB | 520 ms / 0.52 s / 246 MB | 83 ms / 0.08 s / 197 MB | 79 ms / 0.10 s / 328 MB |
| write, zstd 3 | dta | 24 ms / 0.04 s / 160 MB | 518 ms / 0.52 s / 247 MB | 88 ms / 0.09 s / 179 MB | 84 ms / 0.13 s / 327 MB |

### 2006_2010_FemResp

12,279 rows, 3,741 columns; .dta 55.6 MB; Parquet pyarrow 6.8 MB, polars 5.8 MB, ours 8.1 MB, duckdb 6.4 MB, ours_zstd 7.0 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 49 ms / 0.08 s / 353 MB | 58 ms / 0.26 s / 408 MB | 140 ms / 0.14 s / 648 MB | 350 ms / 0.49 s / 755 MB |
| whole file | polars | 54 ms / 0.09 s / 352 MB | 60 ms / 0.27 s / 413 MB | 156 ms / 0.16 s / 645 MB | 370 ms / 0.52 s / 755 MB |
| whole file | ours | 62 ms / 0.09 s / 367 MB | 57 ms / 0.26 s / 414 MB | 135 ms / 0.14 s / 601 MB | 372 ms / 0.52 s / 756 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 101 MB | 24 ms / 0.02 s / 177 MB | 52 ms / 0.05 s / 168 MB | 12 ms / 0.01 s / 178 MB |
| five columns | polars | 3 ms / 0.00 s / 102 MB | 24 ms / 0.03 s / 177 MB | 50 ms / 0.05 s / 167 MB | 10 ms / 0.01 s / 177 MB |
| five columns | ours | 9 ms / 0.01 s / 114 MB | 26 ms / 0.03 s / 185 MB | 54 ms / 0.06 s / 170 MB | 10 ms / 0.01 s / 178 MB |
| 1,000 rows | pyarrow | 20 ms / 0.02 s / 120 MB | 68 ms / 0.27 s / 412 MB | 152 ms / 0.15 s / 676 MB | 211 ms / 0.75 s / 1343 MB |
| 1,000 rows | polars | 27 ms / 0.03 s / 119 MB | 66 ms / 0.28 s / 410 MB | 161 ms / 0.16 s / 674 MB | 218 ms / 0.78 s / 1362 MB |
| 1,000 rows | ours | 30 ms / 0.03 s / 135 MB | 65 ms / 0.26 s / 418 MB | 150 ms / 0.15 s / 632 MB | 211 ms / 0.77 s / 1351 MB |
| read + pass | pyarrow | 262 ms / 0.29 s / 478 MB | 522 ms / 0.71 s / 530 MB | 362 ms / 0.36 s / 817 MB | 564 ms / 0.70 s / 867 MB |
| read + pass | polars | 263 ms / 0.30 s / 479 MB | 519 ms / 0.73 s / 533 MB | 358 ms / 0.36 s / 795 MB | 573 ms / 0.72 s / 909 MB |
| read + pass | ours | 282 ms / 0.31 s / 489 MB | 514 ms / 0.71 s / 475 MB | 351 ms / 0.35 s / 762 MB | 586 ms / 0.73 s / 933 MB |
| write, defaults | dta | 170 ms / 0.27 s / 639 MB | 6.40 s / 6.41 s / 750 MB | 548 ms / 0.55 s / 787 MB | 710 ms / 1.09 s / 1250 MB |
| write, zstd 3 | dta | 179 ms / 0.29 s / 642 MB | 6.40 s / 6.44 s / 748 MB | 579 ms / 0.58 s / 747 MB | 719 ms / 1.13 s / 1250 MB |

### 2006_2010_Male

10,403 rows, 2,801 columns; .dta 37.2 MB; Parquet pyarrow 3.8 MB, polars 3.3 MB, ours 4.3 MB, duckdb 3.5 MB, ours_zstd 3.8 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 34 ms / 0.05 s / 243 MB | 43 ms / 0.17 s / 346 MB | 86 ms / 0.09 s / 458 MB | 220 ms / 0.31 s / 557 MB |
| whole file | polars | 35 ms / 0.06 s / 243 MB | 45 ms / 0.18 s / 346 MB | 93 ms / 0.09 s / 461 MB | 220 ms / 0.32 s / 557 MB |
| whole file | ours | 41 ms / 0.06 s / 250 MB | 50 ms / 0.17 s / 350 MB | 92 ms / 0.09 s / 414 MB | 226 ms / 0.32 s / 562 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 100 MB | 21 ms / 0.02 s / 176 MB | 30 ms / 0.03 s / 155 MB | 9 ms / 0.01 s / 176 MB |
| five columns | polars | 2 ms / 0.00 s / 100 MB | 20 ms / 0.02 s / 175 MB | 28 ms / 0.03 s / 154 MB | 8 ms / 0.01 s / 175 MB |
| five columns | ours | 6 ms / 0.01 s / 108 MB | 22 ms / 0.02 s / 178 MB | 31 ms / 0.03 s / 155 MB | 8 ms / 0.01 s / 175 MB |
| 1,000 rows | pyarrow | 13 ms / 0.01 s / 113 MB | 52 ms / 0.19 s / 346 MB | 99 ms / 0.10 s / 486 MB | 153 ms / 0.58 s / 1054 MB |
| 1,000 rows | polars | 17 ms / 0.02 s / 113 MB | 55 ms / 0.19 s / 351 MB | 108 ms / 0.11 s / 485 MB | 159 ms / 0.56 s / 1053 MB |
| 1,000 rows | ours | 18 ms / 0.02 s / 121 MB | 51 ms / 0.17 s / 349 MB | 96 ms / 0.10 s / 438 MB | 153 ms / 0.56 s / 1052 MB |
| read + pass | pyarrow | 157 ms / 0.18 s / 292 MB | 325 ms / 0.46 s / 447 MB | 229 ms / 0.23 s / 507 MB | 372 ms / 0.46 s / 637 MB |
| read + pass | polars | 161 ms / 0.18 s / 331 MB | 330 ms / 0.47 s / 412 MB | 231 ms / 0.23 s / 454 MB | 367 ms / 0.46 s / 603 MB |
| read + pass | ours | 175 ms / 0.19 s / 300 MB | 330 ms / 0.46 s / 469 MB | 228 ms / 0.23 s / 518 MB | 369 ms / 0.47 s / 645 MB |
| write, defaults | dta | 114 ms / 0.17 s / 428 MB | 4.77 s / 4.80 s / 518 MB | 330 ms / 0.33 s / 550 MB | 447 ms / 0.68 s / 931 MB |
| write, zstd 3 | dta | 120 ms / 0.19 s / 429 MB | 4.81 s / 4.84 s / 516 MB | 349 ms / 0.35 s / 487 MB | 466 ms / 0.72 s / 893 MB |

### 2011_2013_FemPreg

9,543 rows, 278 columns; .dta 3.5 MB; Parquet pyarrow 0.8 MB, polars 0.7 MB, ours 0.8 MB, duckdb 0.8 MB, ours_zstd 0.7 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 6 ms / 0.01 s / 112 MB | 12 ms / 0.03 s / 185 MB | 8 ms / 0.01 s / 131 MB | 16 ms / 0.02 s / 202 MB |
| whole file | polars | 6 ms / 0.01 s / 110 MB | 13 ms / 0.03 s / 186 MB | 8 ms / 0.01 s / 129 MB | 17 ms / 0.03 s / 202 MB |
| whole file | ours | 6 ms / 0.01 s / 113 MB | 12 ms / 0.03 s / 186 MB | 7 ms / 0.01 s / 129 MB | 16 ms / 0.03 s / 201 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 98 MB | 14 ms / 0.01 s / 165 MB | 2 ms / 0.00 s / 104 MB | 3 ms / 0.00 s / 168 MB |
| five columns | polars | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 169 MB | 3 ms / 0.00 s / 104 MB | 3 ms / 0.00 s / 168 MB |
| five columns | ours | 2 ms / 0.00 s / 99 MB | 14 ms / 0.01 s / 169 MB | 3 ms / 0.00 s / 103 MB | 3 ms / 0.00 s / 168 MB |
| 1,000 rows | pyarrow | 3 ms / 0.00 s / 99 MB | 14 ms / 0.03 s / 186 MB | 9 ms / 0.01 s / 131 MB | 14 ms / 0.05 s / 260 MB |
| 1,000 rows | polars | 3 ms / 0.00 s / 99 MB | 13 ms / 0.03 s / 185 MB | 10 ms / 0.01 s / 131 MB | 14 ms / 0.05 s / 253 MB |
| 1,000 rows | ours | 3 ms / 0.00 s / 100 MB | 14 ms / 0.03 s / 184 MB | 9 ms / 0.01 s / 129 MB | 14 ms / 0.05 s / 253 MB |
| read + pass | pyarrow | 25 ms / 0.03 s / 173 MB | 48 ms / 0.06 s / 240 MB | 26 ms / 0.03 s / 172 MB | 35 ms / 0.04 s / 246 MB |
| read + pass | polars | 25 ms / 0.03 s / 165 MB | 48 ms / 0.06 s / 240 MB | 27 ms / 0.03 s / 170 MB | 35 ms / 0.04 s / 244 MB |
| read + pass | ours | 25 ms / 0.03 s / 165 MB | 47 ms / 0.06 s / 240 MB | 26 ms / 0.03 s / 170 MB | 35 ms / 0.04 s / 244 MB |
| write, defaults | dta | 17 ms / 0.02 s / 127 MB | 406 ms / 0.41 s / 215 MB | 40 ms / 0.04 s / 175 MB | 39 ms / 0.06 s / 243 MB |
| write, zstd 3 | dta | 19 ms / 0.02 s / 127 MB | 410 ms / 0.41 s / 214 MB | 44 ms / 0.04 s / 173 MB | 41 ms / 0.07 s / 243 MB |

### 2011_2013_FemResp

5,601 rows, 3,094 columns; .dta 22.6 MB; Parquet pyarrow 3.7 MB, polars 3.4 MB, ours 4.3 MB, duckdb 3.5 MB, ours_zstd 3.8 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 34 ms / 0.05 s / 188 MB | 53 ms / 0.15 s / 315 MB | 61 ms / 0.06 s / 313 MB | 173 ms / 0.23 s / 456 MB |
| whole file | polars | 32 ms / 0.05 s / 186 MB | 45 ms / 0.17 s / 310 MB | 63 ms / 0.06 s / 313 MB | 175 ms / 0.24 s / 456 MB |
| whole file | ours | 35 ms / 0.05 s / 196 MB | 42 ms / 0.16 s / 316 MB | 56 ms / 0.06 s / 300 MB | 174 ms / 0.23 s / 457 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 100 MB | 22 ms / 0.02 s / 173 MB | 25 ms / 0.03 s / 159 MB | 10 ms / 0.01 s / 172 MB |
| five columns | polars | 2 ms / 0.00 s / 99 MB | 22 ms / 0.02 s / 175 MB | 20 ms / 0.02 s / 157 MB | 9 ms / 0.01 s / 172 MB |
| five columns | ours | 6 ms / 0.01 s / 105 MB | 22 ms / 0.02 s / 178 MB | 20 ms / 0.02 s / 158 MB | 8 ms / 0.01 s / 174 MB |
| 1,000 rows | pyarrow | 15 ms / 0.01 s / 116 MB | 50 ms / 0.17 s / 311 MB | 85 ms / 0.09 s / 325 MB | 167 ms / 0.56 s / 1140 MB |
| 1,000 rows | polars | 19 ms / 0.02 s / 116 MB | 52 ms / 0.17 s / 313 MB | 90 ms / 0.09 s / 326 MB | 165 ms / 0.62 s / 1142 MB |
| 1,000 rows | ours | 20 ms / 0.02 s / 122 MB | 51 ms / 0.16 s / 312 MB | 84 ms / 0.09 s / 312 MB | 158 ms / 0.60 s / 1154 MB |
| read + pass | pyarrow | 124 ms / 0.14 s / 238 MB | 238 ms / 0.35 s / 392 MB | 164 ms / 0.16 s / 349 MB | 283 ms / 0.34 s / 502 MB |
| read + pass | polars | 125 ms / 0.14 s / 230 MB | 239 ms / 0.37 s / 377 MB | 171 ms / 0.17 s / 351 MB | 286 ms / 0.35 s / 497 MB |
| read + pass | ours | 136 ms / 0.15 s / 239 MB | 234 ms / 0.35 s / 378 MB | 162 ms / 0.16 s / 342 MB | 283 ms / 0.34 s / 500 MB |
| write, defaults | dta | 103 ms / 0.15 s / 303 MB | 4.60 s / 4.63 s / 388 MB | 290 ms / 0.29 s / 346 MB | 323 ms / 0.49 s / 798 MB |
| write, zstd 3 | dta | 114 ms / 0.17 s / 305 MB | 4.56 s / 4.60 s / 387 MB | 328 ms / 0.33 s / 343 MB | 337 ms / 0.53 s / 799 MB |

### 2011_2013_Male

4,815 rows, 3,059 columns; .dta 19.4 MB; Parquet pyarrow 2.4 MB, polars 2.3 MB, ours 2.9 MB, duckdb 2.2 MB, ours_zstd 2.6 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 14 ms / 0.02 s / 174 MB | 40 ms / 0.14 s / 270 MB | 51 ms / 0.05 s / 277 MB | 166 ms / 0.22 s / 438 MB |
| whole file | polars | 16 ms / 0.03 s / 172 MB | 47 ms / 0.15 s / 271 MB | 57 ms / 0.06 s / 278 MB | 166 ms / 0.22 s / 437 MB |
| whole file | ours | 19 ms / 0.03 s / 177 MB | 38 ms / 0.13 s / 272 MB | 50 ms / 0.05 s / 256 MB | 168 ms / 0.22 s / 437 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 101 MB | 21 ms / 0.02 s / 175 MB | 10 ms / 0.01 s / 159 MB | 9 ms / 0.01 s / 173 MB |
| five columns | polars | 2 ms / 0.00 s / 100 MB | 21 ms / 0.02 s / 173 MB | 9 ms / 0.01 s / 157 MB | 8 ms / 0.01 s / 174 MB |
| five columns | ours | 5 ms / 0.01 s / 106 MB | 23 ms / 0.02 s / 176 MB | 9 ms / 0.01 s / 159 MB | 8 ms / 0.01 s / 174 MB |
| 1,000 rows | pyarrow | 11 ms / 0.01 s / 117 MB | 45 ms / 0.14 s / 270 MB | 65 ms / 0.07 s / 306 MB | 158 ms / 0.56 s / 1117 MB |
| 1,000 rows | polars | 14 ms / 0.01 s / 116 MB | 46 ms / 0.15 s / 271 MB | 68 ms / 0.07 s / 306 MB | 161 ms / 0.56 s / 1128 MB |
| 1,000 rows | ours | 15 ms / 0.02 s / 120 MB | 44 ms / 0.13 s / 273 MB | 61 ms / 0.06 s / 284 MB | 159 ms / 0.59 s / 1132 MB |
| read + pass | pyarrow | 98 ms / 0.11 s / 211 MB | 191 ms / 0.29 s / 335 MB | 138 ms / 0.14 s / 327 MB | 230 ms / 0.28 s / 460 MB |
| read + pass | polars | 100 ms / 0.11 s / 208 MB | 193 ms / 0.30 s / 338 MB | 147 ms / 0.15 s / 329 MB | 239 ms / 0.29 s / 460 MB |
| read + pass | ours | 110 ms / 0.12 s / 217 MB | 189 ms / 0.28 s / 335 MB | 133 ms / 0.13 s / 316 MB | 240 ms / 0.29 s / 471 MB |
| write, defaults | dta | 68 ms / 0.11 s / 271 MB | 4.09 s / 4.13 s / 355 MB | 222 ms / 0.22 s / 310 MB | 272 ms / 0.42 s / 692 MB |
| write, zstd 3 | dta | 74 ms / 0.12 s / 272 MB | 4.12 s / 4.16 s / 354 MB | 241 ms / 0.24 s / 313 MB | 286 ms / 0.44 s / 693 MB |

### 2011_2019_FemaleWgt

22,995 rows, 7 columns; .dta 1.2 MB; Parquet pyarrow 1.0 MB, polars 0.7 MB, ours 0.8 MB, duckdb 0.8 MB, ours_zstd 0.7 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 1 ms / 0.00 s / 98 MB | 9 ms / 0.01 s / 169 MB | 2 ms / 0.00 s / 101 MB | 3 ms / 0.00 s / 171 MB |
| whole file | polars | 2 ms / 0.00 s / 99 MB | 9 ms / 0.01 s / 168 MB | 2 ms / 0.00 s / 98 MB | 3 ms / 0.01 s / 170 MB |
| whole file | ours | 1 ms / 0.00 s / 100 MB | 9 ms / 0.01 s / 168 MB | 2 ms / 0.00 s / 97 MB | 4 ms / 0.00 s / 170 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 98 MB | 13 ms / 0.01 s / 168 MB | 2 ms / 0.00 s / 100 MB | 3 ms / 0.00 s / 169 MB |
| five columns | polars | 2 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 168 MB | 2 ms / 0.00 s / 99 MB | 3 ms / 0.00 s / 169 MB |
| five columns | ours | 1 ms / 0.00 s / 97 MB | 13 ms / 0.01 s / 170 MB | 2 ms / 0.00 s / 98 MB | 2 ms / 0.00 s / 168 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 98 MB | 10 ms / 0.01 s / 169 MB | 2 ms / 0.00 s / 100 MB | 3 ms / 0.01 s / 174 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 99 MB | 10 ms / 0.01 s / 169 MB | 3 ms / 0.00 s / 99 MB | 3 ms / 0.01 s / 176 MB |
| 1,000 rows | ours | 1 ms / 0.00 s / 99 MB | 9 ms / 0.01 s / 168 MB | 2 ms / 0.00 s / 100 MB | 3 ms / 0.01 s / 175 MB |
| read + pass | pyarrow | 5 ms / 0.01 s / 103 MB | 14 ms / 0.02 s / 172 MB | 6 ms / 0.01 s / 104 MB | 7 ms / 0.01 s / 171 MB |
| read + pass | polars | 6 ms / 0.01 s / 100 MB | 14 ms / 0.02 s / 169 MB | 7 ms / 0.01 s / 103 MB | 7 ms / 0.01 s / 172 MB |
| read + pass | ours | 5 ms / 0.01 s / 103 MB | 14 ms / 0.01 s / 170 MB | 6 ms / 0.01 s / 103 MB | 7 ms / 0.01 s / 171 MB |
| write, defaults | dta | 3 ms / 0.00 s / 100 MB | 14 ms / 0.01 s / 176 MB | 7 ms / 0.01 s / 103 MB | 5 ms / 0.01 s / 172 MB |
| write, zstd 3 | dta | 5 ms / 0.01 s / 104 MB | 15 ms / 0.02 s / 177 MB | 11 ms / 0.01 s / 104 MB | 9 ms / 0.01 s / 174 MB |

### 2011_2019_MaleWgt

19,067 rows, 7 columns; .dta 1.0 MB; Parquet pyarrow 0.8 MB, polars 0.6 MB, ours 0.7 MB, duckdb 0.7 MB, ours_zstd 0.6 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 1 ms / 0.00 s / 99 MB | 9 ms / 0.01 s / 169 MB | 2 ms / 0.00 s / 100 MB | 3 ms / 0.00 s / 169 MB |
| whole file | polars | 2 ms / 0.00 s / 98 MB | 9 ms / 0.01 s / 169 MB | 2 ms / 0.00 s / 99 MB | 3 ms / 0.01 s / 169 MB |
| whole file | ours | 1 ms / 0.00 s / 99 MB | 8 ms / 0.01 s / 167 MB | 2 ms / 0.00 s / 100 MB | 3 ms / 0.00 s / 169 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 100 MB | 12 ms / 0.01 s / 169 MB | 2 ms / 0.00 s / 100 MB | 2 ms / 0.00 s / 169 MB |
| five columns | polars | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 169 MB | 2 ms / 0.00 s / 100 MB | 3 ms / 0.00 s / 168 MB |
| five columns | ours | 1 ms / 0.00 s / 100 MB | 13 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 100 MB | 2 ms / 0.00 s / 169 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 97 MB | 9 ms / 0.01 s / 170 MB | 2 ms / 0.00 s / 100 MB | 3 ms / 0.01 s / 177 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 99 MB | 9 ms / 0.01 s / 168 MB | 3 ms / 0.00 s / 100 MB | 3 ms / 0.01 s / 175 MB |
| 1,000 rows | ours | 1 ms / 0.00 s / 99 MB | 9 ms / 0.01 s / 167 MB | 2 ms / 0.00 s / 99 MB | 3 ms / 0.01 s / 177 MB |
| read + pass | pyarrow | 5 ms / 0.01 s / 101 MB | 14 ms / 0.01 s / 171 MB | 6 ms / 0.01 s / 101 MB | 7 ms / 0.01 s / 172 MB |
| read + pass | polars | 6 ms / 0.01 s / 102 MB | 14 ms / 0.01 s / 169 MB | 6 ms / 0.01 s / 103 MB | 7 ms / 0.01 s / 171 MB |
| read + pass | ours | 5 ms / 0.01 s / 102 MB | 14 ms / 0.01 s / 168 MB | 6 ms / 0.01 s / 102 MB | 6 ms / 0.01 s / 171 MB |
| write, defaults | dta | 3 ms / 0.00 s / 101 MB | 14 ms / 0.01 s / 175 MB | 7 ms / 0.01 s / 101 MB | 5 ms / 0.01 s / 171 MB |
| write, zstd 3 | dta | 4 ms / 0.00 s / 104 MB | 15 ms / 0.01 s / 178 MB | 9 ms / 0.01 s / 103 MB | 7 ms / 0.01 s / 173 MB |

### 2013_2015_FemPreg

9,358 rows, 278 columns; .dta 3.4 MB; Parquet pyarrow 0.8 MB, polars 0.7 MB, ours 0.8 MB, duckdb 0.7 MB, ours_zstd 0.7 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 5 ms / 0.01 s / 113 MB | 13 ms / 0.03 s / 186 MB | 7 ms / 0.01 s / 131 MB | 15 ms / 0.02 s / 202 MB |
| whole file | polars | 6 ms / 0.01 s / 112 MB | 13 ms / 0.03 s / 184 MB | 8 ms / 0.01 s / 130 MB | 16 ms / 0.03 s / 202 MB |
| whole file | ours | 6 ms / 0.01 s / 114 MB | 12 ms / 0.03 s / 186 MB | 7 ms / 0.01 s / 130 MB | 16 ms / 0.03 s / 200 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 98 MB | 13 ms / 0.01 s / 165 MB | 3 ms / 0.00 s / 103 MB | 3 ms / 0.00 s / 169 MB |
| five columns | polars | 1 ms / 0.00 s / 98 MB | 14 ms / 0.01 s / 168 MB | 3 ms / 0.00 s / 104 MB | 3 ms / 0.00 s / 167 MB |
| five columns | ours | 2 ms / 0.00 s / 100 MB | 13 ms / 0.01 s / 166 MB | 2 ms / 0.00 s / 104 MB | 3 ms / 0.00 s / 168 MB |
| 1,000 rows | pyarrow | 3 ms / 0.00 s / 99 MB | 14 ms / 0.03 s / 185 MB | 9 ms / 0.01 s / 130 MB | 15 ms / 0.05 s / 262 MB |
| 1,000 rows | polars | 3 ms / 0.00 s / 100 MB | 14 ms / 0.03 s / 187 MB | 10 ms / 0.01 s / 131 MB | 15 ms / 0.05 s / 259 MB |
| 1,000 rows | ours | 3 ms / 0.00 s / 101 MB | 13 ms / 0.03 s / 185 MB | 8 ms / 0.01 s / 130 MB | 14 ms / 0.05 s / 251 MB |
| read + pass | pyarrow | 24 ms / 0.02 s / 168 MB | 47 ms / 0.06 s / 241 MB | 26 ms / 0.03 s / 174 MB | 34 ms / 0.04 s / 254 MB |
| read + pass | polars | 24 ms / 0.03 s / 168 MB | 47 ms / 0.06 s / 241 MB | 26 ms / 0.03 s / 171 MB | 35 ms / 0.04 s / 244 MB |
| read + pass | ours | 25 ms / 0.03 s / 169 MB | 47 ms / 0.06 s / 240 MB | 26 ms / 0.03 s / 172 MB | 34 ms / 0.04 s / 245 MB |
| write, defaults | dta | 17 ms / 0.02 s / 128 MB | 482 ms / 0.48 s / 217 MB | 39 ms / 0.04 s / 178 MB | 38 ms / 0.06 s / 245 MB |
| write, zstd 3 | dta | 19 ms / 0.02 s / 129 MB | 473 ms / 0.48 s / 217 MB | 43 ms / 0.04 s / 180 MB | 41 ms / 0.07 s / 245 MB |

### 2013_2015_FemResp

5,699 rows, 3,207 columns; .dta 24.0 MB; Parquet pyarrow 3.8 MB, polars 3.4 MB, ours 4.7 MB, duckdb 3.6 MB, ours_zstd 4.2 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 29 ms / 0.04 s / 191 MB | 44 ms / 0.16 s / 314 MB | 71 ms / 0.07 s / 323 MB | 176 ms / 0.23 s / 465 MB |
| whole file | polars | 31 ms / 0.05 s / 192 MB | 43 ms / 0.17 s / 315 MB | 78 ms / 0.08 s / 322 MB | 181 ms / 0.25 s / 467 MB |
| whole file | ours | 38 ms / 0.05 s / 201 MB | 42 ms / 0.16 s / 317 MB | 70 ms / 0.07 s / 310 MB | 179 ms / 0.24 s / 468 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 99 MB | 22 ms / 0.02 s / 173 MB | 21 ms / 0.02 s / 162 MB | 10 ms / 0.01 s / 173 MB |
| five columns | polars | 2 ms / 0.00 s / 102 MB | 22 ms / 0.02 s / 174 MB | 20 ms / 0.02 s / 160 MB | 9 ms / 0.01 s / 174 MB |
| five columns | ours | 7 ms / 0.01 s / 111 MB | 23 ms / 0.02 s / 176 MB | 21 ms / 0.02 s / 162 MB | 9 ms / 0.01 s / 175 MB |
| 1,000 rows | pyarrow | 15 ms / 0.01 s / 118 MB | 50 ms / 0.17 s / 316 MB | 87 ms / 0.09 s / 352 MB | 169 ms / 0.63 s / 1176 MB |
| 1,000 rows | polars | 19 ms / 0.02 s / 118 MB | 52 ms / 0.19 s / 317 MB | 95 ms / 0.09 s / 350 MB | 179 ms / 0.61 s / 1194 MB |
| 1,000 rows | ours | 21 ms / 0.02 s / 128 MB | 53 ms / 0.17 s / 326 MB | 89 ms / 0.09 s / 337 MB | 171 ms / 0.62 s / 1174 MB |
| read + pass | pyarrow | 128 ms / 0.14 s / 229 MB | 253 ms / 0.36 s / 396 MB | 169 ms / 0.17 s / 350 MB | 298 ms / 0.35 s / 510 MB |
| read + pass | polars | 132 ms / 0.15 s / 240 MB | 258 ms / 0.38 s / 408 MB | 180 ms / 0.18 s / 356 MB | 299 ms / 0.37 s / 508 MB |
| read + pass | ours | 150 ms / 0.16 s / 240 MB | 250 ms / 0.37 s / 406 MB | 177 ms / 0.18 s / 341 MB | 301 ms / 0.36 s / 507 MB |
| write, defaults | dta | 106 ms / 0.15 s / 323 MB | 5.23 s / 5.26 s / 413 MB | 317 ms / 0.32 s / 345 MB | 350 ms / 0.52 s / 822 MB |
| write, zstd 3 | dta | 113 ms / 0.17 s / 326 MB | 5.27 s / 5.30 s / 410 MB | 329 ms / 0.33 s / 344 MB | 368 ms / 0.57 s / 819 MB |

### 2013_2015_Male

4,506 rows, 2,940 columns; .dta 18.0 MB; Parquet pyarrow 2.3 MB, polars 2.2 MB, ours 2.9 MB, duckdb 2.1 MB, ours_zstd 2.7 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 14 ms / 0.02 s / 171 MB | 46 ms / 0.13 s / 266 MB | 51 ms / 0.05 s / 271 MB | 130 ms / 0.18 s / 428 MB |
| whole file | polars | 15 ms / 0.03 s / 169 MB | 40 ms / 0.14 s / 265 MB | 54 ms / 0.06 s / 270 MB | 134 ms / 0.18 s / 427 MB |
| whole file | ours | 19 ms / 0.03 s / 178 MB | 36 ms / 0.12 s / 268 MB | 48 ms / 0.05 s / 251 MB | 136 ms / 0.19 s / 428 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 99 MB | 21 ms / 0.02 s / 175 MB | 9 ms / 0.01 s / 156 MB | 9 ms / 0.01 s / 173 MB |
| five columns | polars | 2 ms / 0.00 s / 100 MB | 21 ms / 0.02 s / 174 MB | 8 ms / 0.01 s / 155 MB | 8 ms / 0.01 s / 172 MB |
| five columns | ours | 6 ms / 0.01 s / 108 MB | 22 ms / 0.02 s / 181 MB | 8 ms / 0.01 s / 155 MB | 8 ms / 0.01 s / 173 MB |
| 1,000 rows | pyarrow | 11 ms / 0.01 s / 115 MB | 48 ms / 0.14 s / 266 MB | 63 ms / 0.06 s / 298 MB | 149 ms / 0.55 s / 1060 MB |
| 1,000 rows | polars | 14 ms / 0.01 s / 114 MB | 44 ms / 0.15 s / 268 MB | 66 ms / 0.07 s / 298 MB | 153 ms / 0.58 s / 1103 MB |
| 1,000 rows | ours | 16 ms / 0.02 s / 124 MB | 44 ms / 0.13 s / 269 MB | 60 ms / 0.06 s / 279 MB | 153 ms / 0.54 s / 1096 MB |
| read + pass | pyarrow | 90 ms / 0.10 s / 211 MB | 179 ms / 0.27 s / 334 MB | 117 ms / 0.12 s / 297 MB | 218 ms / 0.26 s / 454 MB |
| read + pass | polars | 91 ms / 0.10 s / 206 MB | 182 ms / 0.29 s / 336 MB | 119 ms / 0.12 s / 293 MB | 222 ms / 0.27 s / 452 MB |
| read + pass | ours | 108 ms / 0.12 s / 217 MB | 178 ms / 0.26 s / 338 MB | 118 ms / 0.12 s / 269 MB | 220 ms / 0.27 s / 453 MB |
| write, defaults | dta | 84 ms / 0.12 s / 276 MB | 4.95 s / 4.98 s / 360 MB | 234 ms / 0.23 s / 299 MB | 270 ms / 0.39 s / 682 MB |
| write, zstd 3 | dta | 89 ms / 0.12 s / 277 MB | 4.96 s / 4.99 s / 358 MB | 247 ms / 0.25 s / 299 MB | 284 ms / 0.42 s / 685 MB |

### 2015_2017_FemPreg

9,553 rows, 248 columns; .dta 3.0 MB; Parquet pyarrow 0.6 MB, polars 0.5 MB, ours 0.6 MB, duckdb 0.5 MB, ours_zstd 0.5 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 5 ms / 0.01 s / 110 MB | 12 ms / 0.03 s / 184 MB | 7 ms / 0.01 s / 128 MB | 14 ms / 0.02 s / 199 MB |
| whole file | polars | 6 ms / 0.01 s / 110 MB | 12 ms / 0.03 s / 183 MB | 7 ms / 0.01 s / 127 MB | 14 ms / 0.02 s / 198 MB |
| whole file | ours | 6 ms / 0.01 s / 111 MB | 12 ms / 0.03 s / 183 MB | 7 ms / 0.01 s / 127 MB | 14 ms / 0.02 s / 197 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 167 MB | 3 ms / 0.00 s / 103 MB | 3 ms / 0.00 s / 169 MB |
| five columns | polars | 1 ms / 0.00 s / 99 MB | 14 ms / 0.01 s / 167 MB | 2 ms / 0.00 s / 102 MB | 3 ms / 0.00 s / 168 MB |
| five columns | ours | 1 ms / 0.00 s / 100 MB | 14 ms / 0.01 s / 169 MB | 2 ms / 0.00 s / 104 MB | 3 ms / 0.00 s / 168 MB |
| 1,000 rows | pyarrow | 2 ms / 0.00 s / 98 MB | 13 ms / 0.03 s / 183 MB | 8 ms / 0.01 s / 129 MB | 14 ms / 0.05 s / 247 MB |
| 1,000 rows | polars | 3 ms / 0.00 s / 98 MB | 13 ms / 0.03 s / 183 MB | 9 ms / 0.01 s / 126 MB | 13 ms / 0.04 s / 243 MB |
| 1,000 rows | ours | 3 ms / 0.00 s / 101 MB | 13 ms / 0.03 s / 183 MB | 8 ms / 0.01 s / 128 MB | 14 ms / 0.04 s / 229 MB |
| read + pass | pyarrow | 23 ms / 0.02 s / 164 MB | 49 ms / 0.06 s / 237 MB | 24 ms / 0.02 s / 169 MB | 31 ms / 0.04 s / 243 MB |
| read + pass | polars | 23 ms / 0.02 s / 164 MB | 43 ms / 0.06 s / 237 MB | 24 ms / 0.03 s / 170 MB | 31 ms / 0.04 s / 243 MB |
| read + pass | ours | 24 ms / 0.02 s / 164 MB | 44 ms / 0.06 s / 238 MB | 23 ms / 0.02 s / 170 MB | 31 ms / 0.04 s / 243 MB |
| write, defaults | dta | 15 ms / 0.02 s / 125 MB | 430 ms / 0.43 s / 213 MB | 36 ms / 0.04 s / 171 MB | 35 ms / 0.05 s / 235 MB |
| write, zstd 3 | dta | 17 ms / 0.02 s / 125 MB | 432 ms / 0.43 s / 213 MB | 39 ms / 0.04 s / 168 MB | 36 ms / 0.06 s / 236 MB |

### 2015_2017_FemResp

5,554 rows, 3,024 columns; .dta 21.7 MB; Parquet pyarrow 3.4 MB, polars 3.1 MB, ours 4.3 MB, duckdb 3.2 MB, ours_zstd 3.8 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 30 ms / 0.04 s / 187 MB | 47 ms / 0.16 s / 308 MB | 58 ms / 0.06 s / 309 MB | 167 ms / 0.22 s / 449 MB |
| whole file | polars | 34 ms / 0.05 s / 185 MB | 46 ms / 0.17 s / 307 MB | 60 ms / 0.06 s / 309 MB | 167 ms / 0.23 s / 450 MB |
| whole file | ours | 36 ms / 0.05 s / 193 MB | 40 ms / 0.15 s / 308 MB | 54 ms / 0.06 s / 298 MB | 167 ms / 0.23 s / 449 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 101 MB | 21 ms / 0.02 s / 175 MB | 23 ms / 0.02 s / 158 MB | 10 ms / 0.01 s / 173 MB |
| five columns | polars | 2 ms / 0.00 s / 101 MB | 21 ms / 0.02 s / 175 MB | 21 ms / 0.02 s / 158 MB | 9 ms / 0.01 s / 173 MB |
| five columns | ours | 6 ms / 0.01 s / 109 MB | 23 ms / 0.02 s / 178 MB | 22 ms / 0.02 s / 162 MB | 8 ms / 0.01 s / 175 MB |
| 1,000 rows | pyarrow | 14 ms / 0.01 s / 115 MB | 48 ms / 0.17 s / 306 MB | 84 ms / 0.08 s / 322 MB | 153 ms / 0.56 s / 1061 MB |
| 1,000 rows | polars | 18 ms / 0.02 s / 116 MB | 49 ms / 0.17 s / 308 MB | 87 ms / 0.09 s / 320 MB | 160 ms / 0.61 s / 1129 MB |
| 1,000 rows | ours | 20 ms / 0.02 s / 124 MB | 54 ms / 0.16 s / 315 MB | 84 ms / 0.09 s / 310 MB | 158 ms / 0.57 s / 1064 MB |
| read + pass | pyarrow | 120 ms / 0.13 s / 236 MB | 233 ms / 0.34 s / 373 MB | 157 ms / 0.16 s / 350 MB | 272 ms / 0.33 s / 493 MB |
| read + pass | polars | 119 ms / 0.14 s / 223 MB | 228 ms / 0.35 s / 383 MB | 168 ms / 0.17 s / 350 MB | 279 ms / 0.34 s / 500 MB |
| read + pass | ours | 137 ms / 0.15 s / 237 MB | 228 ms / 0.34 s / 374 MB | 154 ms / 0.15 s / 337 MB | 273 ms / 0.33 s / 502 MB |
| write, defaults | dta | 104 ms / 0.15 s / 312 MB | 4.93 s / 4.97 s / 403 MB | 304 ms / 0.30 s / 329 MB | 320 ms / 0.48 s / 751 MB |
| write, zstd 3 | dta | 111 ms / 0.17 s / 314 MB | 4.97 s / 4.97 s / 401 MB | 316 ms / 0.32 s / 347 MB | 347 ms / 0.53 s / 750 MB |

### 2015_2017_Male

4,540 rows, 2,945 columns; .dta 17.7 MB; Parquet pyarrow 2.1 MB, polars 2.1 MB, ours 2.8 MB, duckdb 1.9 MB, ours_zstd 2.6 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 13 ms / 0.02 s / 169 MB | 39 ms / 0.13 s / 263 MB | 50 ms / 0.05 s / 272 MB | 133 ms / 0.18 s / 428 MB |
| whole file | polars | 15 ms / 0.03 s / 169 MB | 40 ms / 0.14 s / 267 MB | 53 ms / 0.05 s / 271 MB | 135 ms / 0.19 s / 427 MB |
| whole file | ours | 19 ms / 0.03 s / 177 MB | 37 ms / 0.12 s / 268 MB | 48 ms / 0.05 s / 251 MB | 135 ms / 0.19 s / 428 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 99 MB | 21 ms / 0.02 s / 174 MB | 9 ms / 0.01 s / 156 MB | 9 ms / 0.01 s / 172 MB |
| five columns | polars | 2 ms / 0.00 s / 100 MB | 21 ms / 0.02 s / 175 MB | 8 ms / 0.01 s / 154 MB | 8 ms / 0.01 s / 173 MB |
| five columns | ours | 6 ms / 0.01 s / 106 MB | 22 ms / 0.02 s / 176 MB | 9 ms / 0.01 s / 155 MB | 8 ms / 0.01 s / 175 MB |
| 1,000 rows | pyarrow | 11 ms / 0.01 s / 114 MB | 45 ms / 0.14 s / 269 MB | 62 ms / 0.06 s / 298 MB | 153 ms / 0.53 s / 1090 MB |
| 1,000 rows | polars | 13 ms / 0.01 s / 116 MB | 45 ms / 0.15 s / 268 MB | 66 ms / 0.07 s / 297 MB | 153 ms / 0.55 s / 1073 MB |
| 1,000 rows | ours | 16 ms / 0.02 s / 122 MB | 43 ms / 0.13 s / 269 MB | 61 ms / 0.06 s / 278 MB | 151 ms / 0.57 s / 1090 MB |
| read + pass | pyarrow | 92 ms / 0.10 s / 214 MB | 182 ms / 0.28 s / 338 MB | 121 ms / 0.12 s / 294 MB | 216 ms / 0.26 s / 454 MB |
| read + pass | polars | 94 ms / 0.10 s / 205 MB | 180 ms / 0.28 s / 337 MB | 126 ms / 0.13 s / 294 MB | 224 ms / 0.27 s / 462 MB |
| read + pass | ours | 109 ms / 0.12 s / 214 MB | 181 ms / 0.27 s / 348 MB | 110 ms / 0.11 s / 271 MB | 219 ms / 0.27 s / 454 MB |
| write, defaults | dta | 86 ms / 0.12 s / 276 MB | 4.96 s / 4.99 s / 359 MB | 218 ms / 0.22 s / 301 MB | 273 ms / 0.40 s / 685 MB |
| write, zstd 3 | dta | 92 ms / 0.13 s / 276 MB | 5.01 s / 5.03 s / 359 MB | 232 ms / 0.23 s / 301 MB | 284 ms / 0.42 s / 675 MB |

### 2017_2019_FemPreg

10,215 rows, 171 columns; .dta 2.2 MB; Parquet pyarrow 0.4 MB, polars 0.4 MB, ours 0.5 MB, duckdb 0.4 MB, ours_zstd 0.4 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 4 ms / 0.00 s / 105 MB | 11 ms / 0.02 s / 178 MB | 5 ms / 0.01 s / 118 MB | 10 ms / 0.02 s / 190 MB |
| whole file | polars | 5 ms / 0.01 s / 106 MB | 11 ms / 0.02 s / 178 MB | 6 ms / 0.01 s / 118 MB | 11 ms / 0.02 s / 188 MB |
| whole file | ours | 5 ms / 0.01 s / 107 MB | 11 ms / 0.02 s / 177 MB | 6 ms / 0.01 s / 118 MB | 11 ms / 0.02 s / 189 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 98 MB | 13 ms / 0.01 s / 167 MB | 2 ms / 0.00 s / 102 MB | 2 ms / 0.00 s / 169 MB |
| five columns | polars | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 167 MB | 2 ms / 0.00 s / 102 MB | 2 ms / 0.00 s / 168 MB |
| five columns | ours | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 167 MB | 2 ms / 0.00 s / 101 MB | 2 ms / 0.00 s / 168 MB |
| 1,000 rows | pyarrow | 2 ms / 0.00 s / 99 MB | 12 ms / 0.02 s / 178 MB | 6 ms / 0.01 s / 118 MB | 10 ms / 0.03 s / 226 MB |
| 1,000 rows | polars | 2 ms / 0.00 s / 97 MB | 13 ms / 0.02 s / 178 MB | 7 ms / 0.01 s / 117 MB | 11 ms / 0.04 s / 219 MB |
| 1,000 rows | ours | 3 ms / 0.00 s / 100 MB | 12 ms / 0.02 s / 177 MB | 6 ms / 0.01 s / 117 MB | 10 ms / 0.04 s / 221 MB |
| read + pass | pyarrow | 18 ms / 0.02 s / 154 MB | 35 ms / 0.05 s / 226 MB | 19 ms / 0.02 s / 162 MB | 25 ms / 0.03 s / 234 MB |
| read + pass | polars | 18 ms / 0.02 s / 156 MB | 35 ms / 0.05 s / 225 MB | 20 ms / 0.02 s / 164 MB | 25 ms / 0.03 s / 231 MB |
| read + pass | ours | 19 ms / 0.02 s / 157 MB | 35 ms / 0.05 s / 226 MB | 19 ms / 0.02 s / 163 MB | 24 ms / 0.03 s / 233 MB |
| write, defaults | dta | 12 ms / 0.01 s / 116 MB | 295 ms / 0.30 s / 204 MB | 28 ms / 0.03 s / 146 MB | 25 ms / 0.03 s / 214 MB |
| write, zstd 3 | dta | 13 ms / 0.01 s / 117 MB | 304 ms / 0.31 s / 204 MB | 31 ms / 0.03 s / 147 MB | 27 ms / 0.03 s / 215 MB |

### 2017_2019_FemResp

6,141 rows, 2,609 columns; .dta 20.2 MB; Parquet pyarrow 3.5 MB, polars 3.1 MB, ours 4.3 MB, duckdb 3.3 MB, ours_zstd 3.8 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 29 ms / 0.04 s / 182 MB | 39 ms / 0.14 s / 288 MB | 56 ms / 0.06 s / 289 MB | 150 ms / 0.20 s / 416 MB |
| whole file | polars | 31 ms / 0.05 s / 178 MB | 39 ms / 0.15 s / 286 MB | 59 ms / 0.06 s / 288 MB | 152 ms / 0.21 s / 417 MB |
| whole file | ours | 36 ms / 0.05 s / 189 MB | 36 ms / 0.14 s / 290 MB | 52 ms / 0.05 s / 285 MB | 146 ms / 0.20 s / 417 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 99 MB | 20 ms / 0.02 s / 171 MB | 21 ms / 0.02 s / 148 MB | 8 ms / 0.01 s / 175 MB |
| five columns | polars | 2 ms / 0.00 s / 99 MB | 19 ms / 0.02 s / 171 MB | 19 ms / 0.02 s / 149 MB | 8 ms / 0.01 s / 174 MB |
| five columns | ours | 6 ms / 0.01 s / 108 MB | 21 ms / 0.02 s / 175 MB | 19 ms / 0.02 s / 149 MB | 8 ms / 0.01 s / 176 MB |
| 1,000 rows | pyarrow | 13 ms / 0.01 s / 114 MB | 44 ms / 0.15 s / 287 MB | 80 ms / 0.08 s / 303 MB | 133 ms / 0.50 s / 993 MB |
| 1,000 rows | polars | 18 ms / 0.02 s / 114 MB | 46 ms / 0.16 s / 288 MB | 92 ms / 0.09 s / 303 MB | 140 ms / 0.50 s / 990 MB |
| 1,000 rows | ours | 19 ms / 0.02 s / 122 MB | 44 ms / 0.15 s / 290 MB | 77 ms / 0.08 s / 298 MB | 132 ms / 0.49 s / 994 MB |
| read + pass | pyarrow | 119 ms / 0.13 s / 218 MB | 223 ms / 0.32 s / 372 MB | 154 ms / 0.15 s / 339 MB | 236 ms / 0.29 s / 443 MB |
| read + pass | polars | 116 ms / 0.13 s / 216 MB | 222 ms / 0.33 s / 380 MB | 163 ms / 0.16 s / 338 MB | 245 ms / 0.30 s / 446 MB |
| read + pass | ours | 130 ms / 0.14 s / 220 MB | 218 ms / 0.32 s / 361 MB | 153 ms / 0.15 s / 332 MB | 232 ms / 0.28 s / 438 MB |
| write, defaults | dta | 98 ms / 0.15 s / 298 MB | 4.28 s / 4.28 s / 388 MB | 273 ms / 0.27 s / 342 MB | 274 ms / 0.42 s / 726 MB |
| write, zstd 3 | dta | 105 ms / 0.16 s / 300 MB | 4.26 s / 4.29 s / 385 MB | 292 ms / 0.29 s / 342 MB | 297 ms / 0.47 s / 716 MB |

### 2017_2019_Male

5,206 rows, 3,009 columns; .dta 20.1 MB; Parquet pyarrow 2.2 MB, polars 2.2 MB, ours 2.9 MB, duckdb 2.0 MB, ours_zstd 2.7 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 26 ms / 0.04 s / 185 MB | 39 ms / 0.14 s / 303 MB | 50 ms / 0.05 s / 310 MB | 162 ms / 0.21 s / 447 MB |
| whole file | polars | 28 ms / 0.04 s / 184 MB | 41 ms / 0.15 s / 303 MB | 55 ms / 0.06 s / 309 MB | 162 ms / 0.22 s / 448 MB |
| whole file | ours | 33 ms / 0.04 s / 194 MB | 38 ms / 0.14 s / 304 MB | 48 ms / 0.05 s / 282 MB | 164 ms / 0.22 s / 448 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 100 MB | 22 ms / 0.02 s / 173 MB | 23 ms / 0.02 s / 156 MB | 9 ms / 0.01 s / 173 MB |
| five columns | polars | 2 ms / 0.00 s / 102 MB | 21 ms / 0.02 s / 175 MB | 20 ms / 0.02 s / 156 MB | 8 ms / 0.01 s / 173 MB |
| five columns | ours | 6 ms / 0.01 s / 109 MB | 22 ms / 0.02 s / 179 MB | 20 ms / 0.02 s / 158 MB | 8 ms / 0.01 s / 173 MB |
| 1,000 rows | pyarrow | 11 ms / 0.01 s / 117 MB | 48 ms / 0.15 s / 305 MB | 80 ms / 0.08 s / 325 MB | 156 ms / 0.57 s / 1124 MB |
| 1,000 rows | polars | 14 ms / 0.01 s / 116 MB | 47 ms / 0.16 s / 305 MB | 81 ms / 0.08 s / 327 MB | 157 ms / 0.59 s / 1126 MB |
| 1,000 rows | ours | 16 ms / 0.02 s / 124 MB | 46 ms / 0.14 s / 306 MB | 78 ms / 0.08 s / 298 MB | 156 ms / 0.58 s / 1105 MB |
| read + pass | pyarrow | 102 ms / 0.11 s / 219 MB | 202 ms / 0.30 s / 371 MB | 138 ms / 0.14 s / 354 MB | 235 ms / 0.29 s / 468 MB |
| read + pass | polars | 104 ms / 0.12 s / 221 MB | 200 ms / 0.31 s / 373 MB | 139 ms / 0.14 s / 353 MB | 237 ms / 0.29 s / 469 MB |
| read + pass | ours | 117 ms / 0.13 s / 220 MB | 201 ms / 0.30 s / 391 MB | 137 ms / 0.14 s / 322 MB | 240 ms / 0.29 s / 467 MB |
| write, defaults | dta | 92 ms / 0.13 s / 314 MB | 5.04 s / 5.07 s / 398 MB | 245 ms / 0.25 s / 327 MB | 281 ms / 0.43 s / 736 MB |
| write, zstd 3 | dta | 97 ms / 0.14 s / 316 MB | 5.08 s / 5.12 s / 400 MB | 258 ms / 0.26 s / 326 MB | 304 ms / 0.45 s / 737 MB |

### 2022_2023_FemPreg

8,247 rows, 111 columns; .dta 1.2 MB; Parquet pyarrow 0.3 MB, polars 0.3 MB, ours 0.3 MB, duckdb 0.3 MB, ours_zstd 0.3 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 3 ms / 0.00 s / 102 MB | 10 ms / 0.02 s / 174 MB | 4 ms / 0.00 s / 111 MB | 7 ms / 0.01 s / 181 MB |
| whole file | polars | 3 ms / 0.00 s / 101 MB | 11 ms / 0.02 s / 173 MB | 5 ms / 0.01 s / 111 MB | 8 ms / 0.01 s / 181 MB |
| whole file | ours | 3 ms / 0.00 s / 103 MB | 10 ms / 0.02 s / 174 MB | 4 ms / 0.00 s / 110 MB | 7 ms / 0.01 s / 182 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 168 MB | 2 ms / 0.00 s / 101 MB | 2 ms / 0.00 s / 167 MB |
| five columns | polars | 1 ms / 0.00 s / 99 MB | 13 ms / 0.01 s / 167 MB | 2 ms / 0.00 s / 100 MB | 3 ms / 0.00 s / 169 MB |
| five columns | ours | 1 ms / 0.00 s / 98 MB | 13 ms / 0.01 s / 167 MB | 2 ms / 0.00 s / 100 MB | 2 ms / 0.00 s / 168 MB |
| 1,000 rows | pyarrow | 2 ms / 0.00 s / 98 MB | 11 ms / 0.02 s / 174 MB | 5 ms / 0.01 s / 111 MB | 7 ms / 0.02 s / 200 MB |
| 1,000 rows | polars | 2 ms / 0.00 s / 99 MB | 11 ms / 0.02 s / 174 MB | 5 ms / 0.01 s / 111 MB | 8 ms / 0.03 s / 199 MB |
| 1,000 rows | ours | 2 ms / 0.00 s / 98 MB | 11 ms / 0.02 s / 175 MB | 5 ms / 0.01 s / 109 MB | 8 ms / 0.03 s / 208 MB |
| read + pass | pyarrow | 12 ms / 0.01 s / 135 MB | 24 ms / 0.03 s / 202 MB | 13 ms / 0.01 s / 139 MB | 16 ms / 0.02 s / 207 MB |
| read + pass | polars | 12 ms / 0.01 s / 136 MB | 24 ms / 0.03 s / 205 MB | 14 ms / 0.01 s / 139 MB | 16 ms / 0.02 s / 209 MB |
| read + pass | ours | 12 ms / 0.01 s / 136 MB | 24 ms / 0.03 s / 206 MB | 13 ms / 0.01 s / 139 MB | 16 ms / 0.02 s / 209 MB |
| write, defaults | dta | 7 ms / 0.01 s / 107 MB | 30 ms / 0.03 s / 178 MB | 17 ms / 0.02 s / 119 MB | 16 ms / 0.02 s / 193 MB |
| write, zstd 3 | dta | 8 ms / 0.01 s / 108 MB | 30 ms / 0.03 s / 181 MB | 19 ms / 0.02 s / 118 MB | 18 ms / 0.02 s / 193 MB |

### 2022_2023_FemResp

5,586 rows, 1,912 columns; .dta 13.3 MB; Parquet pyarrow 2.6 MB, polars 2.3 MB, ours 2.7 MB, duckdb 2.5 MB, ours_zstd 2.4 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 13 ms / 0.02 s / 153 MB | 36 ms / 0.11 s / 263 MB | 31 ms / 0.03 s / 230 MB | 87 ms / 0.12 s / 347 MB |
| whole file | polars | 15 ms / 0.03 s / 154 MB | 34 ms / 0.11 s / 261 MB | 36 ms / 0.04 s / 230 MB | 92 ms / 0.13 s / 350 MB |
| whole file | ours | 14 ms / 0.02 s / 154 MB | 30 ms / 0.10 s / 259 MB | 30 ms / 0.03 s / 225 MB | 87 ms / 0.13 s / 347 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 101 MB | 18 ms / 0.02 s / 170 MB | 7 ms / 0.01 s / 133 MB | 7 ms / 0.01 s / 170 MB |
| five columns | polars | 2 ms / 0.00 s / 100 MB | 18 ms / 0.02 s / 170 MB | 6 ms / 0.01 s / 135 MB | 6 ms / 0.01 s / 170 MB |
| five columns | ours | 2 ms / 0.00 s / 101 MB | 18 ms / 0.02 s / 170 MB | 6 ms / 0.01 s / 136 MB | 6 ms / 0.01 s / 172 MB |
| 1,000 rows | pyarrow | 11 ms / 0.01 s / 110 MB | 33 ms / 0.11 s / 258 MB | 40 ms / 0.04 s / 236 MB | 91 ms / 0.35 s / 732 MB |
| 1,000 rows | polars | 14 ms / 0.01 s / 107 MB | 33 ms / 0.12 s / 261 MB | 44 ms / 0.04 s / 237 MB | 99 ms / 0.37 s / 778 MB |
| 1,000 rows | ours | 11 ms / 0.01 s / 110 MB | 33 ms / 0.10 s / 258 MB | 39 ms / 0.04 s / 233 MB | 91 ms / 0.36 s / 778 MB |
| read + pass | pyarrow | 74 ms / 0.09 s / 178 MB | 162 ms / 0.24 s / 335 MB | 93 ms / 0.09 s / 252 MB | 153 ms / 0.19 s / 356 MB |
| read + pass | polars | 78 ms / 0.09 s / 178 MB | 159 ms / 0.24 s / 327 MB | 99 ms / 0.10 s / 249 MB | 158 ms / 0.20 s / 357 MB |
| read + pass | ours | 75 ms / 0.09 s / 179 MB | 153 ms / 0.23 s / 316 MB | 91 ms / 0.09 s / 247 MB | 152 ms / 0.19 s / 356 MB |
| write, defaults | dta | 47 ms / 0.08 s / 178 MB | 267 ms / 0.31 s / 255 MB | 169 ms / 0.17 s / 253 MB | 192 ms / 0.30 s / 486 MB |
| write, zstd 3 | dta | 52 ms / 0.09 s / 178 MB | 284 ms / 0.33 s / 252 MB | 186 ms / 0.19 s / 251 MB | 206 ms / 0.33 s / 485 MB |

### 2022_2023_MaleResp

4,371 rows, 1,157 columns; .dta 6.3 MB; Parquet pyarrow 1.2 MB, polars 1.1 MB, ours 1.3 MB, duckdb 1.1 MB, ours_zstd 1.1 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 7 ms / 0.01 s / 129 MB | 20 ms / 0.06 s / 209 MB | 16 ms / 0.02 s / 164 MB | 43 ms / 0.06 s / 269 MB |
| whole file | polars | 8 ms / 0.01 s / 126 MB | 20 ms / 0.06 s / 210 MB | 19 ms / 0.02 s / 163 MB | 45 ms / 0.07 s / 269 MB |
| whole file | ours | 7 ms / 0.01 s / 128 MB | 19 ms / 0.06 s / 208 MB | 16 ms / 0.02 s / 159 MB | 43 ms / 0.06 s / 269 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 99 MB | 16 ms / 0.02 s / 169 MB | 5 ms / 0.01 s / 121 MB | 5 ms / 0.01 s / 170 MB |
| five columns | polars | 1 ms / 0.00 s / 99 MB | 15 ms / 0.02 s / 168 MB | 4 ms / 0.00 s / 119 MB | 4 ms / 0.01 s / 169 MB |
| five columns | ours | 2 ms / 0.00 s / 100 MB | 16 ms / 0.02 s / 169 MB | 4 ms / 0.00 s / 120 MB | 4 ms / 0.01 s / 170 MB |
| 1,000 rows | pyarrow | 6 ms / 0.01 s / 103 MB | 23 ms / 0.06 s / 210 MB | 21 ms / 0.02 s / 171 MB | 56 ms / 0.22 s / 528 MB |
| 1,000 rows | polars | 7 ms / 0.01 s / 105 MB | 23 ms / 0.07 s / 210 MB | 23 ms / 0.02 s / 170 MB | 57 ms / 0.23 s / 530 MB |
| 1,000 rows | ours | 6 ms / 0.01 s / 107 MB | 23 ms / 0.06 s / 210 MB | 20 ms / 0.02 s / 170 MB | 55 ms / 0.21 s / 513 MB |
| read + pass | pyarrow | 38 ms / 0.04 s / 176 MB | 81 ms / 0.12 s / 277 MB | 48 ms / 0.05 s / 216 MB | 75 ms / 0.09 s / 305 MB |
| read + pass | polars | 39 ms / 0.04 s / 178 MB | 83 ms / 0.13 s / 276 MB | 49 ms / 0.05 s / 213 MB | 76 ms / 0.10 s / 317 MB |
| read + pass | ours | 37 ms / 0.04 s / 179 MB | 81 ms / 0.12 s / 278 MB | 47 ms / 0.05 s / 211 MB | 74 ms / 0.09 s / 304 MB |
| write, defaults | dta | 24 ms / 0.04 s / 138 MB | 151 ms / 0.18 s / 220 MB | 76 ms / 0.08 s / 194 MB | 93 ms / 0.14 s / 334 MB |
| write, zstd 3 | dta | 27 ms / 0.05 s / 140 MB | 158 ms / 0.19 s / 220 MB | 84 ms / 0.09 s / 203 MB | 99 ms / 0.15 s / 335 MB |

### Senegal 2019 wm

8,649 rows, 4,997 columns; .dta 49.1 MB; Parquet pyarrow 4.2 MB, polars 4.0 MB, ours 4.8 MB, duckdb 3.7 MB, ours_zstd 4.3 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 45 ms / 0.07 s / 359 MB | 63 ms / 0.26 s / 445 MB | 122 ms / 0.12 s / 730 MB | 383 ms / 0.51 s / 843 MB |
| whole file | polars | 43 ms / 0.07 s / 357 MB | 63 ms / 0.27 s / 451 MB | 135 ms / 0.14 s / 730 MB | 389 ms / 0.52 s / 849 MB |
| whole file | ours | 50 ms / 0.07 s / 366 MB | 61 ms / 0.24 s / 447 MB | 114 ms / 0.11 s / 570 MB | 380 ms / 0.51 s / 843 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 101 MB | 27 ms / 0.03 s / 182 MB | 63 ms / 0.06 s / 197 MB | 15 ms / 0.02 s / 182 MB |
| five columns | polars | 3 ms / 0.00 s / 102 MB | 26 ms / 0.03 s / 180 MB | 59 ms / 0.06 s / 196 MB | 13 ms / 0.01 s / 181 MB |
| five columns | ours | 7 ms / 0.01 s / 109 MB | 28 ms / 0.03 s / 185 MB | 58 ms / 0.06 s / 199 MB | 12 ms / 0.01 s / 182 MB |
| 1,000 rows | pyarrow | 13 ms / 0.02 s / 131 MB | 74 ms / 0.27 s / 451 MB | 164 ms / 0.16 s / 740 MB | 277 ms / 1.01 s / 1761 MB |
| 1,000 rows | polars | 14 ms / 0.02 s / 131 MB | 78 ms / 0.29 s / 449 MB | 163 ms / 0.16 s / 739 MB | 281 ms / 0.99 s / 1751 MB |
| 1,000 rows | ours | 19 ms / 0.03 s / 139 MB | 74 ms / 0.26 s / 452 MB | 150 ms / 0.15 s / 590 MB | 271 ms / 0.98 s / 1752 MB |
| read + pass | pyarrow | 226 ms / 0.25 s / 464 MB | 481 ms / 0.67 s / 528 MB | 314 ms / 0.32 s / 727 MB | 581 ms / 0.71 s / 959 MB |
| read + pass | polars | 236 ms / 0.26 s / 488 MB | 483 ms / 0.69 s / 583 MB | 320 ms / 0.32 s / 728 MB | 585 ms / 0.71 s / 958 MB |
| read + pass | ours | 248 ms / 0.27 s / 489 MB | 501 ms / 0.68 s / 587 MB | 303 ms / 0.30 s / 602 MB | 582 ms / 0.71 s / 1052 MB |
| write, defaults | dta | 164 ms / 0.24 s / 634 MB | 7.89 s / 7.94 s / 735 MB | 454 ms / 0.45 s / 797 MB | 732 ms / 1.09 s / 1149 MB |
| write, zstd 3 | dta | 170 ms / 0.26 s / 635 MB | 7.99 s / 8.05 s / 735 MB | 473 ms / 0.47 s / 800 MB | 747 ms / 1.13 s / 1149 MB |

### Senegal 2019 bh

21,562 rows, 1,191 columns; .dta 28.9 MB; Parquet pyarrow 4.0 MB, polars 3.1 MB, ours 4.0 MB, duckdb 3.7 MB, ours_zstd 3.1 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 32 ms / 0.05 s / 221 MB | 30 ms / 0.13 s / 311 MB | 80 ms / 0.08 s / 396 MB | 150 ms / 0.23 s / 459 MB |
| whole file | polars | 32 ms / 0.05 s / 220 MB | 27 ms / 0.13 s / 311 MB | 83 ms / 0.08 s / 400 MB | 154 ms / 0.23 s / 450 MB |
| whole file | ours | 35 ms / 0.05 s / 224 MB | 29 ms / 0.13 s / 311 MB | 75 ms / 0.08 s / 360 MB | 147 ms / 0.22 s / 452 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 101 MB | 16 ms / 0.02 s / 170 MB | 29 ms / 0.03 s / 121 MB | 6 ms / 0.01 s / 171 MB |
| five columns | polars | 2 ms / 0.00 s / 99 MB | 16 ms / 0.02 s / 171 MB | 28 ms / 0.03 s / 123 MB | 6 ms / 0.01 s / 171 MB |
| five columns | ours | 3 ms / 0.00 s / 101 MB | 17 ms / 0.02 s / 172 MB | 28 ms / 0.03 s / 123 MB | 6 ms / 0.01 s / 171 MB |
| 1,000 rows | pyarrow | 11 ms / 0.01 s / 105 MB | 32 ms / 0.14 s / 312 MB | 87 ms / 0.09 s / 408 MB | 64 ms / 0.22 s / 546 MB |
| 1,000 rows | polars | 14 ms / 0.01 s / 105 MB | 33 ms / 0.14 s / 310 MB | 88 ms / 0.09 s / 407 MB | 65 ms / 0.22 s / 544 MB |
| 1,000 rows | ours | 13 ms / 0.01 s / 107 MB | 31 ms / 0.13 s / 311 MB | 81 ms / 0.08 s / 370 MB | 59 ms / 0.23 s / 538 MB |
| read + pass | pyarrow | 152 ms / 0.17 s / 301 MB | 289 ms / 0.39 s / 405 MB | 194 ms / 0.19 s / 402 MB | 274 ms / 0.34 s / 504 MB |
| read + pass | polars | 152 ms / 0.17 s / 305 MB | 285 ms / 0.39 s / 374 MB | 193 ms / 0.19 s / 404 MB | 283 ms / 0.35 s / 513 MB |
| read + pass | ours | 156 ms / 0.17 s / 302 MB | 293 ms / 0.39 s / 403 MB | 191 ms / 0.19 s / 365 MB | 275 ms / 0.35 s / 501 MB |
| write, defaults | dta | 99 ms / 0.15 s / 366 MB | 2.07 s / 2.08 s / 442 MB | 271 ms / 0.27 s / 472 MB | 329 ms / 0.51 s / 674 MB |
| write, zstd 3 | dta | 90 ms / 0.15 s / 368 MB | 2.08 s / 2.10 s / 442 MB | 281 ms / 0.28 s / 405 MB | 347 ms / 0.54 s / 677 MB |

### Turkey 2013 wm

9,746 rows, 4,668 columns; .dta 52.6 MB; Parquet pyarrow 4.3 MB, polars 4.0 MB, ours 4.9 MB, duckdb 4.0 MB, ours_zstd 4.3 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 43 ms / 0.07 s / 343 MB | 73 ms / 0.26 s / 435 MB | 147 ms / 0.15 s / 689 MB | 377 ms / 0.50 s / 799 MB |
| whole file | polars | 46 ms / 0.07 s / 342 MB | 72 ms / 0.27 s / 435 MB | 145 ms / 0.14 s / 690 MB | 371 ms / 0.50 s / 802 MB |
| whole file | ours | 49 ms / 0.07 s / 349 MB | 61 ms / 0.24 s / 434 MB | 137 ms / 0.14 s / 536 MB | 377 ms / 0.51 s / 805 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 101 MB | 26 ms / 0.03 s / 180 MB | 58 ms / 0.06 s / 191 MB | 14 ms / 0.02 s / 182 MB |
| five columns | polars | 3 ms / 0.00 s / 103 MB | 25 ms / 0.03 s / 181 MB | 60 ms / 0.06 s / 191 MB | 12 ms / 0.01 s / 181 MB |
| five columns | ours | 7 ms / 0.01 s / 109 MB | 27 ms / 0.03 s / 185 MB | 53 ms / 0.05 s / 192 MB | 12 ms / 0.01 s / 181 MB |
| 1,000 rows | pyarrow | 13 ms / 0.02 s / 131 MB | 72 ms / 0.27 s / 437 MB | 161 ms / 0.16 s / 716 MB | 252 ms / 0.93 s / 1649 MB |
| 1,000 rows | polars | 14 ms / 0.02 s / 131 MB | 72 ms / 0.28 s / 437 MB | 164 ms / 0.17 s / 716 MB | 268 ms / 0.92 s / 1641 MB |
| 1,000 rows | ours | 18 ms / 0.03 s / 139 MB | 83 ms / 0.25 s / 444 MB | 163 ms / 0.16 s / 562 MB | 257 ms / 0.85 s / 1645 MB |
| read + pass | pyarrow | 231 ms / 0.26 s / 435 MB | 529 ms / 0.73 s / 551 MB | 332 ms / 0.33 s / 693 MB | 578 ms / 0.70 s / 926 MB |
| read + pass | polars | 237 ms / 0.27 s / 459 MB | 535 ms / 0.73 s / 559 MB | 335 ms / 0.34 s / 693 MB | 573 ms / 0.71 s / 888 MB |
| read + pass | ours | 250 ms / 0.28 s / 463 MB | 501 ms / 0.68 s / 498 MB | 341 ms / 0.34 s / 740 MB | 577 ms / 0.71 s / 969 MB |
| write, defaults | dta | 162 ms / 0.25 s / 599 MB | 7.27 s / 7.32 s / 700 MB | 443 ms / 0.44 s / 732 MB | 718 ms / 1.09 s / 1109 MB |
| write, zstd 3 | dta | 169 ms / 0.26 s / 601 MB | 7.26 s / 7.31 s / 698 MB | 464 ms / 0.47 s / 686 MB | 743 ms / 1.10 s / 1095 MB |

### Turkey 2013 bh

17,871 rows, 1,173 columns; .dta 23.3 MB; Parquet pyarrow 3.3 MB, polars 2.7 MB, ours 3.5 MB, duckdb 3.1 MB, ours_zstd 2.7 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 27 ms / 0.04 s / 199 MB | 27 ms / 0.11 s / 289 MB | 62 ms / 0.06 s / 343 MB | 109 ms / 0.16 s / 409 MB |
| whole file | polars | 28 ms / 0.04 s / 199 MB | 28 ms / 0.12 s / 290 MB | 66 ms / 0.07 s / 342 MB | 115 ms / 0.17 s / 408 MB |
| whole file | ours | 28 ms / 0.04 s / 201 MB | 25 ms / 0.11 s / 290 MB | 58 ms / 0.06 s / 300 MB | 109 ms / 0.17 s / 410 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 101 MB | 16 ms / 0.02 s / 172 MB | 15 ms / 0.01 s / 121 MB | 6 ms / 0.01 s / 172 MB |
| five columns | polars | 2 ms / 0.00 s / 100 MB | 16 ms / 0.02 s / 171 MB | 16 ms / 0.02 s / 122 MB | 6 ms / 0.01 s / 172 MB |
| five columns | ours | 3 ms / 0.00 s / 104 MB | 16 ms / 0.02 s / 172 MB | 15 ms / 0.01 s / 123 MB | 5 ms / 0.01 s / 170 MB |
| 1,000 rows | pyarrow | 9 ms / 0.01 s / 106 MB | 29 ms / 0.12 s / 290 MB | 64 ms / 0.07 s / 352 MB | 55 ms / 0.22 s / 526 MB |
| 1,000 rows | polars | 12 ms / 0.01 s / 105 MB | 30 ms / 0.12 s / 290 MB | 69 ms / 0.07 s / 354 MB | 59 ms / 0.23 s / 534 MB |
| 1,000 rows | ours | 11 ms / 0.01 s / 106 MB | 30 ms / 0.11 s / 288 MB | 62 ms / 0.06 s / 312 MB | 54 ms / 0.21 s / 520 MB |
| read + pass | pyarrow | 123 ms / 0.14 s / 242 MB | 238 ms / 0.32 s / 352 MB | 160 ms / 0.16 s / 348 MB | 225 ms / 0.28 s / 478 MB |
| read + pass | polars | 125 ms / 0.14 s / 241 MB | 239 ms / 0.33 s / 353 MB | 169 ms / 0.17 s / 348 MB | 228 ms / 0.29 s / 452 MB |
| read + pass | ours | 128 ms / 0.14 s / 245 MB | 233 ms / 0.32 s / 351 MB | 162 ms / 0.16 s / 327 MB | 220 ms / 0.28 s / 445 MB |
| write, defaults | dta | 76 ms / 0.12 s / 324 MB | 1.94 s / 1.95 s / 396 MB | 234 ms / 0.23 s / 383 MB | 272 ms / 0.41 s / 569 MB |
| write, zstd 3 | dta | 80 ms / 0.13 s / 326 MB | 1.95 s / 1.97 s / 394 MB | 251 ms / 0.25 s / 366 MB | 284 ms / 0.43 s / 566 MB |

### Tajikistan 2017 wm

10,718 rows, 5,160 columns; .dta 63.8 MB; Parquet pyarrow 5.7 MB, polars 5.3 MB, ours 6.4 MB, duckdb 5.3 MB, ours_zstd 5.6 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 48 ms / 0.08 s / 367 MB | 67 ms / 0.29 s / 504 MB | 143 ms / 0.14 s / 775 MB | 449 ms / 0.61 s / 912 MB |
| whole file | polars | 50 ms / 0.08 s / 366 MB | 69 ms / 0.31 s / 499 MB | 150 ms / 0.15 s / 774 MB | 447 ms / 0.61 s / 914 MB |
| whole file | ours | 56 ms / 0.09 s / 375 MB | 68 ms / 0.29 s / 506 MB | 136 ms / 0.14 s / 620 MB | 448 ms / 0.61 s / 914 MB |
| five columns | pyarrow | 4 ms / 0.00 s / 103 MB | 27 ms / 0.03 s / 184 MB | 65 ms / 0.07 s / 202 MB | 15 ms / 0.02 s / 180 MB |
| five columns | polars | 4 ms / 0.00 s / 102 MB | 26 ms / 0.03 s / 182 MB | 62 ms / 0.06 s / 201 MB | 13 ms / 0.01 s / 179 MB |
| five columns | ours | 8 ms / 0.01 s / 111 MB | 28 ms / 0.03 s / 186 MB | 63 ms / 0.06 s / 202 MB | 13 ms / 0.01 s / 181 MB |
| 1,000 rows | pyarrow | 14 ms / 0.02 s / 132 MB | 80 ms / 0.31 s / 503 MB | 188 ms / 0.19 s / 783 MB | 303 ms / 1.07 s / 1807 MB |
| 1,000 rows | polars | 16 ms / 0.03 s / 134 MB | 79 ms / 0.32 s / 508 MB | 185 ms / 0.19 s / 784 MB | 306 ms / 1.08 s / 1801 MB |
| 1,000 rows | ours | 20 ms / 0.03 s / 141 MB | 76 ms / 0.29 s / 507 MB | 173 ms / 0.17 s / 629 MB | 300 ms / 1.07 s / 1804 MB |
| read + pass | pyarrow | 280 ms / 0.31 s / 463 MB | 604 ms / 0.81 s / 616 MB | 384 ms / 0.39 s / 771 MB | 697 ms / 0.85 s / 1024 MB |
| read + pass | polars | 279 ms / 0.31 s / 445 MB | 600 ms / 0.84 s / 617 MB | 388 ms / 0.39 s / 776 MB | 697 ms / 0.86 s / 1090 MB |
| read + pass | ours | 300 ms / 0.33 s / 502 MB | 594 ms / 0.79 s / 595 MB | 369 ms / 0.37 s / 644 MB | 700 ms / 0.86 s / 1050 MB |
| write, defaults | dta | 189 ms / 0.29 s / 645 MB | 7.97 s / 8.03 s / 752 MB | 539 ms / 0.54 s / 747 MB | 889 ms / 1.34 s / 1345 MB |
| write, zstd 3 | dta | 198 ms / 0.31 s / 648 MB | 8.04 s / 8.10 s / 751 MB | 568 ms / 0.56 s / 774 MB | 911 ms / 1.17 s / 1342 MB |

### Tajikistan 2017 bh

21,985 rows, 1,146 columns; .dta 29.4 MB; Parquet pyarrow 4.8 MB, polars 3.8 MB, ours 4.8 MB, duckdb 4.4 MB, ours_zstd 3.8 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 31 ms / 0.05 s / 216 MB | 30 ms / 0.13 s / 307 MB | 78 ms / 0.08 s / 386 MB | 146 ms / 0.22 s / 447 MB |
| whole file | polars | 32 ms / 0.05 s / 216 MB | 29 ms / 0.13 s / 305 MB | 81 ms / 0.08 s / 389 MB | 147 ms / 0.22 s / 440 MB |
| whole file | ours | 33 ms / 0.05 s / 219 MB | 29 ms / 0.12 s / 306 MB | 75 ms / 0.08 s / 352 MB | 143 ms / 0.21 s / 443 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 99 MB | 16 ms / 0.02 s / 171 MB | 29 ms / 0.03 s / 122 MB | 6 ms / 0.01 s / 171 MB |
| five columns | polars | 2 ms / 0.00 s / 100 MB | 16 ms / 0.02 s / 171 MB | 26 ms / 0.03 s / 121 MB | 6 ms / 0.01 s / 172 MB |
| five columns | ours | 3 ms / 0.00 s / 102 MB | 17 ms / 0.02 s / 172 MB | 26 ms / 0.03 s / 123 MB | 6 ms / 0.01 s / 172 MB |
| 1,000 rows | pyarrow | 12 ms / 0.01 s / 107 MB | 34 ms / 0.13 s / 308 MB | 86 ms / 0.09 s / 395 MB | 57 ms / 0.21 s / 515 MB |
| 1,000 rows | polars | 15 ms / 0.02 s / 107 MB | 32 ms / 0.14 s / 308 MB | 86 ms / 0.09 s / 398 MB | 61 ms / 0.22 s / 521 MB |
| 1,000 rows | ours | 14 ms / 0.01 s / 107 MB | 30 ms / 0.13 s / 308 MB | 80 ms / 0.08 s / 363 MB | 58 ms / 0.23 s / 533 MB |
| read + pass | pyarrow | 147 ms / 0.17 s / 259 MB | 286 ms / 0.39 s / 367 MB | 191 ms / 0.19 s / 390 MB | 280 ms / 0.35 s / 500 MB |
| read + pass | polars | 146 ms / 0.17 s / 259 MB | 277 ms / 0.38 s / 365 MB | 190 ms / 0.19 s / 392 MB | 277 ms / 0.35 s / 492 MB |
| read + pass | ours | 151 ms / 0.17 s / 264 MB | 277 ms / 0.38 s / 360 MB | 191 ms / 0.19 s / 357 MB | 263 ms / 0.33 s / 492 MB |
| write, defaults | dta | 85 ms / 0.14 s / 357 MB | 1.96 s / 1.98 s / 433 MB | 250 ms / 0.25 s / 396 MB | 310 ms / 0.48 s / 662 MB |
| write, zstd 3 | dta | 91 ms / 0.15 s / 360 MB | 1.98 s / 1.99 s / 435 MB | 279 ms / 0.28 s / 495 MB | 330 ms / 0.51 s / 663 MB |

### Myanmar 2016 wm

12,885 rows, 4,993 columns; .dta 72.0 MB; Parquet pyarrow 5.3 MB, polars 4.9 MB, ours 5.9 MB, duckdb 4.9 MB, ours_zstd 5.1 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 54 ms / 0.09 s / 440 MB | 79 ms / 0.32 s / 582 MB | 169 ms / 0.17 s / 931 MB | 466 ms / 0.64 s / 1011 MB |
| whole file | polars | 53 ms / 0.09 s / 440 MB | 74 ms / 0.33 s / 568 MB | 168 ms / 0.17 s / 933 MB | 462 ms / 0.64 s / 1010 MB |
| whole file | ours | 59 ms / 0.10 s / 448 MB | 67 ms / 0.30 s / 571 MB | 156 ms / 0.16 s / 720 MB | 462 ms / 0.64 s / 1016 MB |
| five columns | pyarrow | 4 ms / 0.00 s / 103 MB | 26 ms / 0.03 s / 182 MB | 63 ms / 0.06 s / 200 MB | 15 ms / 0.01 s / 183 MB |
| five columns | polars | 3 ms / 0.00 s / 101 MB | 25 ms / 0.03 s / 180 MB | 62 ms / 0.06 s / 199 MB | 13 ms / 0.01 s / 182 MB |
| five columns | ours | 7 ms / 0.01 s / 110 MB | 27 ms / 0.03 s / 186 MB | 62 ms / 0.06 s / 202 MB | 12 ms / 0.01 s / 183 MB |
| 1,000 rows | pyarrow | 14 ms / 0.02 s / 133 MB | 79 ms / 0.33 s / 575 MB | 182 ms / 0.18 s / 961 MB | 278 ms / 1.00 s / 1750 MB |
| 1,000 rows | polars | 15 ms / 0.03 s / 131 MB | 80 ms / 0.34 s / 576 MB | 190 ms / 0.19 s / 958 MB | 281 ms / 1.03 s / 1743 MB |
| 1,000 rows | ours | 20 ms / 0.03 s / 140 MB | 79 ms / 0.32 s / 577 MB | 178 ms / 0.18 s / 746 MB | 275 ms / 0.98 s / 1746 MB |
| read + pass | pyarrow | 301 ms / 0.34 s / 526 MB | 675 ms / 0.93 s / 690 MB | 436 ms / 0.44 s / 932 MB | 729 ms / 0.91 s / 1115 MB |
| read + pass | polars | 297 ms / 0.34 s / 530 MB | 670 ms / 0.93 s / 643 MB | 439 ms / 0.44 s / 928 MB | 738 ms / 0.93 s / 1199 MB |
| read + pass | ours | 326 ms / 0.36 s / 537 MB | 681 ms / 0.91 s / 696 MB | 428 ms / 0.43 s / 919 MB | 725 ms / 0.91 s / 1106 MB |
| write, defaults | dta | 196 ms / 0.31 s / 791 MB | 7.92 s / 7.96 s / 894 MB | 574 ms / 0.57 s / 1021 MB | 971 ms / 1.48 s / 1428 MB |
| write, zstd 3 | dta | 203 ms / 0.32 s / 789 MB | 7.96 s / 7.99 s / 893 MB | 608 ms / 0.61 s / 920 MB | 987 ms / 1.51 s / 1427 MB |

### Myanmar 2016 bh

22,989 rows, 1,184 columns; .dta 30.7 MB; Parquet pyarrow 4.2 MB, polars 3.3 MB, ours 4.3 MB, duckdb 3.9 MB, ours_zstd 3.4 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 32 ms / 0.05 s / 220 MB | 27 ms / 0.13 s / 312 MB | 77 ms / 0.08 s / 398 MB | 149 ms / 0.22 s / 468 MB |
| whole file | polars | 33 ms / 0.05 s / 220 MB | 31 ms / 0.14 s / 311 MB | 80 ms / 0.08 s / 398 MB | 148 ms / 0.22 s / 462 MB |
| whole file | ours | 34 ms / 0.05 s / 222 MB | 29 ms / 0.12 s / 311 MB | 75 ms / 0.07 s / 359 MB | 144 ms / 0.21 s / 461 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 100 MB | 16 ms / 0.02 s / 171 MB | 25 ms / 0.03 s / 122 MB | 6 ms / 0.01 s / 171 MB |
| five columns | polars | 2 ms / 0.00 s / 100 MB | 16 ms / 0.02 s / 171 MB | 24 ms / 0.02 s / 123 MB | 6 ms / 0.01 s / 170 MB |
| five columns | ours | 3 ms / 0.00 s / 104 MB | 16 ms / 0.02 s / 172 MB | 25 ms / 0.03 s / 123 MB | 6 ms / 0.01 s / 173 MB |
| 1,000 rows | pyarrow | 11 ms / 0.01 s / 107 MB | 32 ms / 0.13 s / 311 MB | 84 ms / 0.09 s / 407 MB | 60 ms / 0.23 s / 540 MB |
| 1,000 rows | polars | 14 ms / 0.01 s / 107 MB | 31 ms / 0.14 s / 308 MB | 85 ms / 0.09 s / 408 MB | 63 ms / 0.24 s / 529 MB |
| 1,000 rows | ours | 13 ms / 0.01 s / 110 MB | 32 ms / 0.13 s / 310 MB | 81 ms / 0.08 s / 367 MB | 63 ms / 0.23 s / 544 MB |
| read + pass | pyarrow | 156 ms / 0.17 s / 303 MB | 304 ms / 0.40 s / 424 MB | 209 ms / 0.21 s / 402 MB | 286 ms / 0.36 s / 548 MB |
| read + pass | polars | 160 ms / 0.18 s / 304 MB | 305 ms / 0.41 s / 423 MB | 211 ms / 0.21 s / 451 MB | 291 ms / 0.37 s / 540 MB |
| read + pass | ours | 163 ms / 0.18 s / 306 MB | 302 ms / 0.40 s / 367 MB | 215 ms / 0.21 s / 475 MB | 276 ms / 0.35 s / 500 MB |
| write, defaults | dta | 88 ms / 0.15 s / 368 MB | 2.05 s / 2.07 s / 443 MB | 296 ms / 0.29 s / 452 MB | 331 ms / 0.51 s / 674 MB |
| write, zstd 3 | dta | 93 ms / 0.16 s / 369 MB | 2.06 s / 2.08 s / 440 MB | 321 ms / 0.32 s / 423 MB | 353 ms / 0.54 s / 678 MB |

### Dominican Republic 2013 wm

9,372 rows, 3,854 columns; .dta 39.7 MB; Parquet pyarrow 3.8 MB, polars 3.5 MB, ours 4.3 MB, duckdb 3.5 MB, ours_zstd 3.7 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 37 ms / 0.06 s / 298 MB | 52 ms / 0.21 s / 383 MB | 111 ms / 0.11 s / 579 MB | 284 ms / 0.39 s / 685 MB |
| whole file | polars | 38 ms / 0.06 s / 300 MB | 52 ms / 0.23 s / 381 MB | 114 ms / 0.11 s / 577 MB | 290 ms / 0.40 s / 687 MB |
| whole file | ours | 42 ms / 0.06 s / 304 MB | 51 ms / 0.21 s / 386 MB | 103 ms / 0.10 s / 467 MB | 282 ms / 0.39 s / 691 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 103 MB | 24 ms / 0.03 s / 179 MB | 45 ms / 0.05 s / 169 MB | 12 ms / 0.01 s / 178 MB |
| five columns | polars | 3 ms / 0.00 s / 103 MB | 23 ms / 0.02 s / 178 MB | 40 ms / 0.04 s / 167 MB | 10 ms / 0.01 s / 177 MB |
| five columns | ours | 6 ms / 0.01 s / 106 MB | 24 ms / 0.03 s / 180 MB | 40 ms / 0.04 s / 170 MB | 10 ms / 0.01 s / 178 MB |
| 1,000 rows | pyarrow | 15 ms / 0.01 s / 121 MB | 61 ms / 0.22 s / 383 MB | 125 ms / 0.13 s / 607 MB | 199 ms / 0.75 s / 1386 MB |
| 1,000 rows | polars | 18 ms / 0.02 s / 120 MB | 60 ms / 0.22 s / 384 MB | 131 ms / 0.13 s / 605 MB | 202 ms / 0.75 s / 1382 MB |
| 1,000 rows | ours | 19 ms / 0.02 s / 127 MB | 59 ms / 0.21 s / 387 MB | 121 ms / 0.12 s / 491 MB | 197 ms / 0.74 s / 1374 MB |
| read + pass | pyarrow | 191 ms / 0.21 s / 402 MB | 412 ms / 0.57 s / 511 MB | 275 ms / 0.28 s / 581 MB | 468 ms / 0.57 s / 817 MB |
| read + pass | polars | 183 ms / 0.21 s / 352 MB | 398 ms / 0.57 s / 448 MB | 279 ms / 0.28 s / 579 MB | 457 ms / 0.57 s / 750 MB |
| read + pass | ours | 206 ms / 0.23 s / 363 MB | 401 ms / 0.56 s / 466 MB | 262 ms / 0.26 s / 582 MB | 454 ms / 0.56 s / 766 MB |
| write, defaults | dta | 135 ms / 0.21 s / 518 MB | 6.14 s / 6.15 s / 611 MB | 419 ms / 0.42 s / 637 MB | 559 ms / 0.85 s / 930 MB |
| write, zstd 3 | dta | 141 ms / 0.22 s / 519 MB | 6.10 s / 6.13 s / 610 MB | 428 ms / 0.43 s / 609 MB | 575 ms / 0.87 s / 1006 MB |

### Dominican Republic 2013 bh

18,167 rows, 1,078 columns; .dta 22.2 MB; Parquet pyarrow 3.5 MB, polars 2.8 MB, ours 3.6 MB, duckdb 3.3 MB, ours_zstd 2.9 MB.

| case | input | ours | arrow | nanoparquet | duckdb |
|---|---|---|---|---|---|
| whole file | pyarrow | 27 ms / 0.04 s / 191 MB | 27 ms / 0.11 s / 281 MB | 62 ms / 0.06 s / 323 MB | 108 ms / 0.16 s / 390 MB |
| whole file | polars | 29 ms / 0.04 s / 191 MB | 26 ms / 0.12 s / 280 MB | 65 ms / 0.07 s / 325 MB | 111 ms / 0.17 s / 387 MB |
| whole file | ours | 29 ms / 0.04 s / 194 MB | 26 ms / 0.11 s / 281 MB | 58 ms / 0.06 s / 299 MB | 107 ms / 0.16 s / 390 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 99 MB | 16 ms / 0.02 s / 170 MB | 15 ms / 0.02 s / 120 MB | 6 ms / 0.01 s / 172 MB |
| five columns | polars | 2 ms / 0.00 s / 100 MB | 15 ms / 0.02 s / 171 MB | 15 ms / 0.01 s / 121 MB | 6 ms / 0.01 s / 171 MB |
| five columns | ours | 3 ms / 0.00 s / 103 MB | 16 ms / 0.02 s / 172 MB | 15 ms / 0.01 s / 120 MB | 5 ms / 0.01 s / 171 MB |
| 1,000 rows | pyarrow | 10 ms / 0.01 s / 106 MB | 28 ms / 0.11 s / 281 MB | 64 ms / 0.07 s / 334 MB | 54 ms / 0.21 s / 500 MB |
| 1,000 rows | polars | 12 ms / 0.01 s / 106 MB | 29 ms / 0.12 s / 280 MB | 67 ms / 0.07 s / 334 MB | 58 ms / 0.21 s / 512 MB |
| 1,000 rows | ours | 11 ms / 0.01 s / 108 MB | 29 ms / 0.11 s / 280 MB | 62 ms / 0.06 s / 307 MB | 52 ms / 0.20 s / 501 MB |
| read + pass | pyarrow | 119 ms / 0.13 s / 228 MB | 224 ms / 0.31 s / 337 MB | 150 ms / 0.15 s / 327 MB | 212 ms / 0.27 s / 420 MB |
| read + pass | polars | 120 ms / 0.14 s / 234 MB | 221 ms / 0.31 s / 343 MB | 157 ms / 0.16 s / 331 MB | 217 ms / 0.28 s / 419 MB |
| read + pass | ours | 123 ms / 0.14 s / 230 MB | 225 ms / 0.31 s / 343 MB | 146 ms / 0.15 s / 303 MB | 216 ms / 0.27 s / 420 MB |
| write, defaults | dta | 73 ms / 0.12 s / 309 MB | 1.82 s / 1.83 s / 382 MB | 211 ms / 0.21 s / 329 MB | 253 ms / 0.39 s / 540 MB |
| write, zstd 3 | dta | 78 ms / 0.13 s / 311 MB | 1.83 s / 1.84 s / 382 MB | 230 ms / 0.23 s / 329 MB | 266 ms / 0.41 s / 541 MB |

