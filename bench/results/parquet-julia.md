# Parquet benchmarks (Julia)

Written by `bench/parquet/run.py`; see bench/RESULTS.md for what the numbers mean.

One-minute load average before the runs: median 13.0, range 9.3 to 44.1.

| library | version | threads |
|---|---|---|
| duckdb | 2.0.0 | 1 |
| ours | 0.3.0 | default |
| parquet2 | 0.2.37 | 1 |

## Ratios, ours to theirs (geometric means)

Below 1 is better for us. Targets 1 and 2 hold where wall and RSS are at most 1.05 on NSFG and DHS.

| against | case | input | family | files | wall | CPU | peak RSS |
|---|---|---|---|---|---|---|---|
| parquet2 | whole file | pyarrow | NSFG | 36 | 0.07 | 0.07 | 0.61 |
| parquet2 | whole file | pyarrow | DHS | 10 | 0.10 | 0.11 | 0.83 |
| parquet2 | whole file | pyarrow | Synthetic | 3 | 0.14 | 0.25 | 0.68 |
| parquet2 | whole file | polars | NSFG | 36 | 0.05 | 0.05 | 0.56 |
| parquet2 | whole file | polars | DHS | 10 | 0.09 | 0.09 | 0.81 |
| parquet2 | whole file | polars | Synthetic | 3 | 0.14 | 0.32 | 0.66 |
| parquet2 | whole file | ours | NSFG | 36 | 0.06 | 0.06 | 0.59 |
| parquet2 | whole file | ours | DHS | 10 | 0.05 | 0.05 | 0.71 |
| parquet2 | whole file | ours | Synthetic | 3 | 0.15 | 0.27 | 0.67 |
| parquet2 | five columns | pyarrow | NSFG | 36 | 0.16 | 0.16 | 0.61 |
| parquet2 | five columns | pyarrow | DHS | 10 | 0.16 | 0.16 | 0.61 |
| parquet2 | five columns | pyarrow | Synthetic | 3 | 0.20 | 0.23 | 0.76 |
| parquet2 | five columns | polars | NSFG | 36 | 0.16 | 0.15 | 0.61 |
| parquet2 | five columns | polars | DHS | 10 | 0.17 | 0.16 | 0.61 |
| parquet2 | five columns | polars | Synthetic | 3 | 0.21 | 0.26 | 0.71 |
| parquet2 | five columns | ours | NSFG | 36 | 0.16 | 0.16 | 0.62 |
| parquet2 | five columns | ours | DHS | 10 | 0.17 | 0.17 | 0.63 |
| parquet2 | five columns | ours | Synthetic | 3 | 0.21 | 0.24 | 0.72 |
| parquet2 | 1,000 rows | pyarrow | NSFG | 36 | 0.06 | 0.06 | 0.48 |
| parquet2 | 1,000 rows | pyarrow | DHS | 10 | 0.06 | 0.06 | 0.36 |
| parquet2 | 1,000 rows | pyarrow | Synthetic | 3 | 0.06 | 0.06 | 0.22 |
| parquet2 | 1,000 rows | polars | NSFG | 36 | 0.04 | 0.04 | 0.45 |
| parquet2 | 1,000 rows | polars | DHS | 10 | 0.06 | 0.05 | 0.35 |
| parquet2 | 1,000 rows | polars | Synthetic | 3 | 0.08 | 0.08 | 0.43 |
| parquet2 | 1,000 rows | ours | NSFG | 36 | 0.05 | 0.05 | 0.47 |
| parquet2 | 1,000 rows | ours | DHS | 10 | 0.03 | 0.03 | 0.34 |
| parquet2 | 1,000 rows | ours | Synthetic | 3 | 0.06 | 0.07 | 0.34 |
| parquet2 | read + pass | pyarrow | NSFG | 36 | 0.12 | 0.12 | 0.62 |
| parquet2 | read + pass | pyarrow | DHS | 10 | 0.16 | 0.16 | 0.84 |
| parquet2 | read + pass | pyarrow | Synthetic | 3 | 0.19 | 0.29 | 0.68 |
| parquet2 | read + pass | polars | NSFG | 36 | 0.08 | 0.08 | 0.57 |
| parquet2 | read + pass | polars | DHS | 10 | 0.14 | 0.14 | 0.81 |
| parquet2 | read + pass | polars | Synthetic | 3 | 0.17 | 0.34 | 0.63 |
| parquet2 | read + pass | ours | NSFG | 36 | 0.09 | 0.09 | 0.59 |
| parquet2 | read + pass | ours | DHS | 10 | 0.08 | 0.08 | 0.71 |
| parquet2 | read + pass | ours | Synthetic | 3 | 0.19 | 0.28 | 0.64 |
| parquet2 | write, defaults | dta | NSFG | 36 | 0.03 | 0.03 | 0.51 |
| parquet2 | write, defaults | dta | DHS | 10 | 0.04 | 0.05 | 0.50 |
| parquet2 | write, defaults | dta | Synthetic | 3 | 0.12 | 0.29 | 0.61 |
| parquet2 | write, zstd 3 | dta | NSFG | 36 | 0.03 | 0.03 | 0.51 |
| parquet2 | write, zstd 3 | dta | DHS | 10 | 0.04 | 0.05 | 0.50 |
| parquet2 | write, zstd 3 | dta | Synthetic | 3 | 0.14 | 0.32 | 0.61 |
| duckdb | whole file | pyarrow | NSFG | 36 | 0.27 | 0.27 | 0.74 |
| duckdb | whole file | pyarrow | DHS | 10 | 0.24 | 0.26 | 0.73 |
| duckdb | whole file | pyarrow | Synthetic | 2 | 0.31 | 0.44 | 0.35 |
| duckdb | whole file | polars | NSFG | 36 | 0.27 | 0.27 | 0.74 |
| duckdb | whole file | polars | DHS | 10 | 0.25 | 0.26 | 0.73 |
| duckdb | whole file | polars | Synthetic | 3 | 0.25 | 0.56 | 0.34 |
| duckdb | whole file | ours | NSFG | 36 | 0.28 | 0.29 | 0.75 |
| duckdb | whole file | ours | DHS | 10 | 0.26 | 0.28 | 0.74 |
| duckdb | whole file | ours | Synthetic | 3 | 0.30 | 0.51 | 0.33 |
| duckdb | five columns | pyarrow | NSFG | 36 | 0.70 | 0.69 | 0.81 |
| duckdb | five columns | pyarrow | DHS | 10 | 0.71 | 0.70 | 0.80 |
| duckdb | five columns | pyarrow | Synthetic | 3 | 0.56 | 0.63 | 0.48 |
| duckdb | five columns | polars | NSFG | 36 | 0.70 | 0.70 | 0.81 |
| duckdb | five columns | polars | DHS | 10 | 0.70 | 0.70 | 0.80 |
| duckdb | five columns | polars | Synthetic | 3 | 0.54 | 0.64 | 0.47 |
| duckdb | five columns | ours | NSFG | 36 | 0.74 | 0.73 | 0.82 |
| duckdb | five columns | ours | DHS | 10 | 0.75 | 0.74 | 0.82 |
| duckdb | five columns | ours | Synthetic | 3 | 0.55 | 0.62 | 0.46 |
| duckdb | 1,000 rows | pyarrow | NSFG | 36 | 0.28 | 0.28 | 0.66 |
| duckdb | 1,000 rows | pyarrow | DHS | 10 | 0.21 | 0.21 | 0.54 |
| duckdb | 1,000 rows | pyarrow | Synthetic | 2 | 0.40 | 0.39 | 0.74 |
| duckdb | 1,000 rows | polars | NSFG | 36 | 0.28 | 0.28 | 0.66 |
| duckdb | 1,000 rows | polars | DHS | 10 | 0.22 | 0.21 | 0.54 |
| duckdb | 1,000 rows | polars | Synthetic | 3 | 0.41 | 0.45 | 0.60 |
| duckdb | 1,000 rows | ours | NSFG | 36 | 0.30 | 0.30 | 0.67 |
| duckdb | 1,000 rows | ours | DHS | 10 | 0.23 | 0.23 | 0.56 |
| duckdb | 1,000 rows | ours | Synthetic | 3 | 0.38 | 0.37 | 0.50 |
| duckdb | read + pass | pyarrow | NSFG | 36 | 0.38 | 0.39 | 0.74 |
| duckdb | read + pass | pyarrow | DHS | 10 | 0.35 | 0.36 | 0.73 |
| duckdb | read + pass | pyarrow | Synthetic | 2 | 0.39 | 0.50 | 0.35 |
| duckdb | read + pass | polars | NSFG | 36 | 0.38 | 0.39 | 0.74 |
| duckdb | read + pass | polars | DHS | 10 | 0.36 | 0.36 | 0.73 |
| duckdb | read + pass | polars | Synthetic | 3 | 0.32 | 0.62 | 0.34 |
| duckdb | read + pass | ours | NSFG | 36 | 0.40 | 0.40 | 0.75 |
| duckdb | read + pass | ours | DHS | 10 | 0.36 | 0.37 | 0.75 |
| duckdb | read + pass | ours | Synthetic | 3 | 0.39 | 0.57 | 0.34 |
| duckdb | write, defaults | dta | NSFG | 36 | 0.20 | 0.22 | 0.62 |
| duckdb | write, defaults | dta | DHS | 10 | 0.25 | 0.31 | 0.48 |
| duckdb | write, defaults | dta | Synthetic | 3 | 0.31 | 0.68 | 0.94 |
| duckdb | write, zstd 3 | dta | NSFG | 36 | 0.21 | 0.24 | 0.62 |
| duckdb | write, zstd 3 | dta | DHS | 10 | 0.25 | 0.31 | 0.48 |
| duckdb | write, zstd 3 | dta | Synthetic | 3 | 0.34 | 0.78 | 0.95 |

## Other tools reading our files

Time on our file ÷ time on the tool's own default output (target 4: at most 1.10).

Our files with the default codec (snappy), and with zstd 3 (`ours_zstd`, not gated).

| tool | our codec | family | files | geometric mean | worst file | its ratio |
|---|---|---|---|---|---|---|

## Our writes: zstd 3 against snappy (the default)

Ratios of our zstd write to our snappy write (geometric means), and how parquet2, duckdb (their defaults) compare with each (wall time).

| family | files | wall zstd/snappy | size zstd/snappy | vs parquet2 (zstd, snappy) | vs duckdb (zstd, snappy) |
|---|---|---|---|---|---|
| NSFG | 36 | 1.10 | 0.84 | 0.03, 0.03 | 0.22, 0.20 |
| DHS | 10 | 1.00 | 0.84 | 0.04, 0.04 | 0.25, 0.25 |
| Synthetic | 3 | 1.46 | 0.95 | 0.18, 0.12 | 0.45, 0.31 |

## Misses

None: every target holds.

## Every file

### long.dta

10,000,000 rows, 12 columns; .dta 740.0 MB; Parquet pyarrow 650.9 MB, polars 597.3 MB, ours 632.9 MB, duckdb 647.6 MB, ours_zstd 585.2 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 521 ms / 0.92 s / 1930 MB | 3.67 s / 3.67 s / 2556 MB | 1.43 s / 1.46 s / 4015 MB |
| whole file | polars | 503 ms / 1.20 s / 1767 MB | 3.59 s / 3.59 s / 2639 MB | 1.80 s / 1.84 s / 4027 MB |
| whole file | ours | 428 ms / 0.79 s / 1790 MB | 3.30 s / 3.30 s / 2559 MB | 1.38 s / 1.42 s / 4080 MB |
| five columns | pyarrow | 607 ms / 0.79 s / 1381 MB | 2.73 s / 2.73 s / 1589 MB | 932 ms / 0.96 s / 2121 MB |
| five columns | polars | 607 ms / 0.88 s / 1234 MB | 2.43 s / 2.43 s / 1665 MB | 1.10 s / 1.12 s / 2063 MB |
| five columns | ours | 543 ms / 0.73 s / 1245 MB | 2.41 s / 2.40 s / 1643 MB | 922 ms / 0.95 s / 2084 MB |
| 1,000 rows | pyarrow | 170 ms / 0.17 s / 376 MB | 3.25 s / 3.24 s / 884 MB | 448 ms / 0.45 s / 547 MB |
| 1,000 rows | polars | 169 ms / 0.17 s / 373 MB | 2.81 s / 2.81 s / 686 MB | 446 ms / 0.45 s / 486 MB |
| 1,000 rows | ours | 161 ms / 0.16 s / 374 MB | 2.98 s / 2.98 s / 726 MB | 459 ms / 0.46 s / 496 MB |
| read + pass | pyarrow | 735 ms / 1.12 s / 1943 MB | 4.10 s / 4.09 s / 2590 MB | 1.66 s / 1.70 s / 4028 MB |
| read + pass | polars | 723 ms / 1.43 s / 1786 MB | 4.58 s / 4.57 s / 2979 MB | 1.99 s / 2.03 s / 4041 MB |
| read + pass | ours | 639 ms / 1.01 s / 1808 MB | 4.34 s / 4.33 s / 2834 MB | 1.60 s / 1.64 s / 4083 MB |
| write, defaults | dta | 884 ms / 1.49 s / 2123 MB | 7.77 s / 7.76 s / 3761 MB | 1.99 s / 2.06 s / 2103 MB |
| write, zstd 3 | dta | 1.36 s / 2.22 s / 2125 MB | 8.99 s / 8.97 s / 3814 MB | 2.79 s / 2.86 s / 2098 MB |

### wide.dta

1,500,000 rows, 400 columns; .dta 4800.3 MB; Parquet pyarrow 5020.6 MB, polars 4607.6 MB, ours 4800.8 MB, duckdb 4800.9 MB, ours_zstd 4607.6 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 812 ms / 2.15 s / 5924 MB | 4.13 s / 4.13 s / 11583 MB | – |
| whole file | polars | 1.17 s / 5.11 s / 5807 MB | 6.64 s / 6.64 s / 11112 MB | 5.56 s / 5.81 s / 16155 MB |
| whole file | ours | 747 ms / 1.92 s / 5825 MB | 2.96 s / 2.96 s / 11284 MB | 2.24 s / 2.51 s / 17389 MB |
| five columns | pyarrow | 272 ms / 0.28 s / 462 MB | 1.31 s / 1.31 s / 760 MB | 360 ms / 0.37 s / 697 MB |
| five columns | polars | 293 ms / 0.32 s / 447 MB | 1.29 s / 1.28 s / 760 MB | 383 ms / 0.39 s / 668 MB |
| five columns | ours | 264 ms / 0.27 s / 450 MB | 1.14 s / 1.14 s / 747 MB | 346 ms / 0.36 s / 700 MB |
| 1,000 rows | pyarrow | 246 ms / 0.32 s / 384 MB | 3.87 s / 3.86 s / 8682 MB | – |
| 1,000 rows | polars | 270 ms / 0.37 s / 382 MB | 2.37 s / 2.37 s / 1508 MB | 630 ms / 0.65 s / 1071 MB |
| 1,000 rows | ours | 181 ms / 0.19 s / 381 MB | 2.34 s / 2.34 s / 2910 MB | 487 ms / 0.56 s / 1784 MB |
| read + pass | pyarrow | 1.21 s / 2.59 s / 5920 MB | 4.94 s / 4.94 s / 11623 MB | – |
| read + pass | polars | 1.57 s / 5.50 s / 5808 MB | 7.53 s / 7.53 s / 11164 MB | 5.96 s / 6.21 s / 16157 MB |
| read + pass | ours | 1.16 s / 2.33 s / 5826 MB | 3.90 s / 3.89 s / 11324 MB | 2.66 s / 2.93 s / 17305 MB |
| write, defaults | dta | 830 ms / 4.71 s / 5404 MB | 6.34 s / 6.30 s / 6332 MB | 5.46 s / 5.95 s / 7462 MB |
| write, zstd 3 | dta | 1.60 s / 9.56 s / 5396 MB | 11.94 s / 11.90 s / 6223 MB | 8.43 s / 8.91 s / 7318 MB |

### groups.dta

15,000,000 rows, 2 columns; .dta 270.0 MB; Parquet pyarrow 24.1 MB, polars 23.4 MB, ours 24.0 MB, duckdb 23.9 MB, ours_zstd 23.4 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 243 ms / 0.29 s / 656 MB | 2.30 s / 2.30 s / 794 MB | 944 ms / 0.95 s / 2557 MB |
| whole file | polars | 247 ms / 0.29 s / 644 MB | 2.30 s / 2.29 s / 793 MB | 951 ms / 0.95 s / 2551 MB |
| whole file | ours | 241 ms / 0.28 s / 649 MB | 2.26 s / 2.26 s / 796 MB | 934 ms / 0.94 s / 2551 MB |
| five columns | pyarrow | 347 ms / 0.39 s / 658 MB | 2.05 s / 2.05 s / 790 MB | 961 ms / 0.96 s / 2559 MB |
| five columns | polars | 352 ms / 0.40 s / 647 MB | 2.08 s / 2.08 s / 788 MB | 961 ms / 0.96 s / 2552 MB |
| five columns | ours | 354 ms / 0.40 s / 652 MB | 2.06 s / 2.06 s / 791 MB | 954 ms / 0.96 s / 2553 MB |
| 1,000 rows | pyarrow | 153 ms / 0.15 s / 370 MB | 2.44 s / 2.43 s / 670 MB | 365 ms / 0.36 s / 466 MB |
| 1,000 rows | polars | 155 ms / 0.15 s / 371 MB | 2.42 s / 2.42 s / 653 MB | 354 ms / 0.35 s / 465 MB |
| 1,000 rows | ours | 154 ms / 0.15 s / 371 MB | 2.40 s / 2.39 s / 655 MB | 360 ms / 0.36 s / 465 MB |
| read + pass | pyarrow | 374 ms / 0.42 s / 656 MB | 2.52 s / 2.52 s / 798 MB | 1.11 s / 1.11 s / 2569 MB |
| read + pass | polars | 376 ms / 0.42 s / 645 MB | 2.50 s / 2.50 s / 799 MB | 1.09 s / 1.09 s / 2561 MB |
| read + pass | ours | 372 ms / 0.41 s / 649 MB | 2.50 s / 2.50 s / 798 MB | 1.10 s / 1.11 s / 2562 MB |
| write, defaults | dta | 437 ms / 0.58 s / 1616 MB | 3.55 s / 3.54 s / 3425 MB | 1.04 s / 1.05 s / 1408 MB |
| write, zstd 3 | dta | 456 ms / 0.61 s / 1616 MB | 3.70 s / 3.69 s / 3404 MB | 1.06 s / 1.07 s / 1408 MB |

### 1973_FemResp

9,797 rows, 450 columns; .dta 5.7 MB; Parquet pyarrow 1.6 MB, polars 1.3 MB, ours 1.7 MB, duckdb 1.5 MB, ours_zstd 1.4 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 153 ms / 0.16 s / 408 MB | 2.29 s / 2.28 s / 674 MB | 529 ms / 0.53 s / 530 MB |
| whole file | polars | 153 ms / 0.16 s / 410 MB | 2.43 s / 2.42 s / 680 MB | 523 ms / 0.52 s / 531 MB |
| whole file | ours | 156 ms / 0.16 s / 412 MB | 2.37 s / 2.37 s / 678 MB | 521 ms / 0.52 s / 529 MB |
| five columns | pyarrow | 246 ms / 0.24 s / 373 MB | 1.51 s / 1.51 s / 606 MB | 337 ms / 0.34 s / 458 MB |
| five columns | polars | 242 ms / 0.24 s / 373 MB | 1.65 s / 1.65 s / 609 MB | 335 ms / 0.33 s / 459 MB |
| five columns | ours | 247 ms / 0.24 s / 374 MB | 1.61 s / 1.61 s / 607 MB | 336 ms / 0.34 s / 458 MB |
| 1,000 rows | pyarrow | 165 ms / 0.16 s / 374 MB | 2.67 s / 2.67 s / 704 MB | 481 ms / 0.48 s / 504 MB |
| 1,000 rows | polars | 165 ms / 0.16 s / 374 MB | 2.81 s / 2.81 s / 705 MB | 482 ms / 0.48 s / 504 MB |
| 1,000 rows | ours | 166 ms / 0.16 s / 374 MB | 2.77 s / 2.76 s / 703 MB | 482 ms / 0.48 s / 504 MB |
| read + pass | pyarrow | 281 ms / 0.28 s / 412 MB | 2.38 s / 2.38 s / 674 MB | 640 ms / 0.64 s / 530 MB |
| read + pass | polars | 280 ms / 0.28 s / 413 MB | 2.54 s / 2.54 s / 682 MB | 667 ms / 0.67 s / 530 MB |
| read + pass | ours | 291 ms / 0.29 s / 413 MB | 2.50 s / 2.50 s / 681 MB | 649 ms / 0.65 s / 531 MB |
| write, defaults | dta | 135 ms / 0.15 s / 376 MB | 5.84 s / 5.84 s / 735 MB | 615 ms / 0.61 s / 548 MB |
| write, zstd 3 | dta | 151 ms / 0.17 s / 377 MB | 5.93 s / 5.93 s / 754 MB | 624 ms / 0.62 s / 548 MB |

### 1976_FemResp

8,611 rows, 468 columns; .dta 6.0 MB; Parquet pyarrow 1.8 MB, polars 1.4 MB, ours 2.2 MB, duckdb 1.7 MB, ours_zstd 1.8 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 160 ms / 0.16 s / 407 MB | 2.23 s / 2.22 s / 670 MB | 476 ms / 0.48 s / 531 MB |
| whole file | polars | 161 ms / 0.16 s / 407 MB | 2.34 s / 2.34 s / 672 MB | 488 ms / 0.49 s / 530 MB |
| whole file | ours | 165 ms / 0.16 s / 412 MB | 2.30 s / 2.30 s / 670 MB | 478 ms / 0.48 s / 533 MB |
| five columns | pyarrow | 253 ms / 0.25 s / 373 MB | 1.55 s / 1.55 s / 608 MB | 336 ms / 0.34 s / 458 MB |
| five columns | polars | 252 ms / 0.25 s / 373 MB | 1.70 s / 1.69 s / 610 MB | 337 ms / 0.34 s / 459 MB |
| five columns | ours | 267 ms / 0.26 s / 378 MB | 1.65 s / 1.65 s / 611 MB | 336 ms / 0.33 s / 458 MB |
| 1,000 rows | pyarrow | 171 ms / 0.17 s / 373 MB | 2.51 s / 2.51 s / 690 MB | 452 ms / 0.45 s / 506 MB |
| 1,000 rows | polars | 166 ms / 0.16 s / 373 MB | 2.69 s / 2.69 s / 701 MB | 454 ms / 0.45 s / 505 MB |
| 1,000 rows | ours | 177 ms / 0.18 s / 378 MB | 2.65 s / 2.65 s / 701 MB | 453 ms / 0.45 s / 506 MB |
| read + pass | pyarrow | 282 ms / 0.28 s / 410 MB | 2.31 s / 2.31 s / 669 MB | 601 ms / 0.60 s / 533 MB |
| read + pass | polars | 284 ms / 0.28 s / 408 MB | 2.46 s / 2.46 s / 670 MB | 601 ms / 0.60 s / 532 MB |
| read + pass | ours | 291 ms / 0.29 s / 412 MB | 2.42 s / 2.42 s / 675 MB | 615 ms / 0.61 s / 534 MB |
| write, defaults | dta | 143 ms / 0.14 s / 380 MB | 5.56 s / 5.55 s / 727 MB | 610 ms / 0.61 s / 552 MB |
| write, zstd 3 | dta | 162 ms / 0.16 s / 382 MB | 5.50 s / 5.49 s / 729 MB | 610 ms / 0.61 s / 550 MB |

### 1976_PSU

8,611 rows, 3 columns; .dta 0.0 MB; Parquet pyarrow 0.1 MB, polars 0.0 MB, ours 0.0 MB, duckdb 0.0 MB, ours_zstd 0.0 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 143 ms / 0.14 s / 368 MB | 1.97 s / 1.97 s / 629 MB | 320 ms / 0.32 s / 455 MB |
| whole file | polars | 142 ms / 0.14 s / 368 MB | 2.13 s / 2.12 s / 635 MB | 317 ms / 0.32 s / 455 MB |
| whole file | ours | 142 ms / 0.14 s / 368 MB | 2.10 s / 2.09 s / 635 MB | 310 ms / 0.31 s / 456 MB |
| five columns | pyarrow | 253 ms / 0.25 s / 371 MB | 1.54 s / 1.53 s / 608 MB | 310 ms / 0.31 s / 456 MB |
| five columns | polars | 253 ms / 0.25 s / 372 MB | 1.68 s / 1.68 s / 612 MB | 313 ms / 0.31 s / 455 MB |
| five columns | ours | 245 ms / 0.24 s / 371 MB | 1.63 s / 1.63 s / 612 MB | 315 ms / 0.31 s / 455 MB |
| 1,000 rows | pyarrow | 157 ms / 0.16 s / 369 MB | 2.26 s / 2.26 s / 636 MB | 306 ms / 0.30 s / 458 MB |
| 1,000 rows | polars | 156 ms / 0.15 s / 369 MB | 2.46 s / 2.45 s / 641 MB | 309 ms / 0.31 s / 458 MB |
| 1,000 rows | ours | 160 ms / 0.16 s / 369 MB | 2.41 s / 2.41 s / 643 MB | 303 ms / 0.30 s / 457 MB |
| read + pass | pyarrow | 251 ms / 0.25 s / 372 MB | 2.07 s / 2.07 s / 633 MB | 423 ms / 0.42 s / 462 MB |
| read + pass | polars | 246 ms / 0.24 s / 371 MB | 2.22 s / 2.22 s / 632 MB | 420 ms / 0.42 s / 463 MB |
| read + pass | ours | 243 ms / 0.24 s / 372 MB | 2.20 s / 2.19 s / 637 MB | 426 ms / 0.43 s / 463 MB |
| write, defaults | dta | 103 ms / 0.10 s / 367 MB | 2.02 s / 2.01 s / 611 MB | 437 ms / 0.43 s / 457 MB |
| write, zstd 3 | dta | 112 ms / 0.11 s / 368 MB | 2.00 s / 2.00 s / 613 MB | 438 ms / 0.44 s / 458 MB |

### 1976_Preg

23,042 rows, 80 columns; .dta 2.4 MB; Parquet pyarrow 0.4 MB, polars 0.3 MB, ours 0.4 MB, duckdb 0.4 MB, ours_zstd 0.4 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 147 ms / 0.14 s / 383 MB | 2.01 s / 2.01 s / 639 MB | 405 ms / 0.40 s / 487 MB |
| whole file | polars | 146 ms / 0.14 s / 383 MB | 2.01 s / 2.01 s / 639 MB | 391 ms / 0.39 s / 486 MB |
| whole file | ours | 147 ms / 0.15 s / 381 MB | 2.12 s / 2.11 s / 645 MB | 403 ms / 0.40 s / 486 MB |
| five columns | pyarrow | 256 ms / 0.25 s / 372 MB | 1.56 s / 1.56 s / 608 MB | 339 ms / 0.34 s / 459 MB |
| five columns | polars | 260 ms / 0.25 s / 372 MB | 1.56 s / 1.55 s / 606 MB | 332 ms / 0.33 s / 459 MB |
| five columns | ours | 254 ms / 0.25 s / 372 MB | 1.53 s / 1.52 s / 606 MB | 338 ms / 0.34 s / 459 MB |
| 1,000 rows | pyarrow | 170 ms / 0.17 s / 371 MB | 2.32 s / 2.32 s / 659 MB | 364 ms / 0.36 s / 471 MB |
| 1,000 rows | polars | 165 ms / 0.16 s / 371 MB | 2.31 s / 2.31 s / 659 MB | 363 ms / 0.36 s / 471 MB |
| 1,000 rows | ours | 166 ms / 0.16 s / 371 MB | 2.46 s / 2.46 s / 657 MB | 366 ms / 0.37 s / 471 MB |
| read + pass | pyarrow | 267 ms / 0.26 s / 385 MB | 2.12 s / 2.11 s / 642 MB | 509 ms / 0.51 s / 488 MB |
| read + pass | polars | 264 ms / 0.26 s / 384 MB | 2.12 s / 2.12 s / 642 MB | 500 ms / 0.50 s / 489 MB |
| read + pass | ours | 260 ms / 0.26 s / 385 MB | 2.24 s / 2.24 s / 643 MB | 500 ms / 0.50 s / 488 MB |
| write, defaults | dta | 119 ms / 0.12 s / 371 MB | 2.92 s / 2.92 s / 683 MB | 543 ms / 0.54 s / 495 MB |
| write, zstd 3 | dta | 130 ms / 0.13 s / 373 MB | 2.97 s / 2.96 s / 686 MB | 567 ms / 0.57 s / 497 MB |

### 1982_FemResp

7,969 rows, 741 columns; .dta 7.6 MB; Parquet pyarrow 1.8 MB, polars 1.5 MB, ours 2.1 MB, duckdb 1.7 MB, ours_zstd 1.8 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 174 ms / 0.18 s / 425 MB | 2.44 s / 2.43 s / 710 MB | 605 ms / 0.60 s / 562 MB |
| whole file | polars | 205 ms / 0.18 s / 424 MB | 2.46 s / 2.46 s / 710 MB | 597 ms / 0.60 s / 563 MB |
| whole file | ours | 220 ms / 0.19 s / 427 MB | 2.51 s / 2.50 s / 709 MB | 594 ms / 0.59 s / 562 MB |
| five columns | pyarrow | 296 ms / 0.27 s / 373 MB | 1.52 s / 1.52 s / 607 MB | 337 ms / 0.34 s / 460 MB |
| five columns | polars | 251 ms / 0.25 s / 373 MB | 1.52 s / 1.51 s / 608 MB | 336 ms / 0.33 s / 459 MB |
| five columns | ours | 279 ms / 0.27 s / 376 MB | 1.49 s / 1.49 s / 607 MB | 335 ms / 0.33 s / 459 MB |
| 1,000 rows | pyarrow | 180 ms / 0.18 s / 376 MB | 2.83 s / 2.83 s / 751 MB | 554 ms / 0.55 s / 534 MB |
| 1,000 rows | polars | 179 ms / 0.18 s / 377 MB | 2.91 s / 2.90 s / 749 MB | 550 ms / 0.55 s / 534 MB |
| 1,000 rows | ours | 180 ms / 0.18 s / 379 MB | 2.95 s / 2.95 s / 749 MB | 550 ms / 0.55 s / 535 MB |
| read + pass | pyarrow | 294 ms / 0.30 s / 427 MB | 2.53 s / 2.53 s / 708 MB | 714 ms / 0.71 s / 564 MB |
| read + pass | polars | 292 ms / 0.30 s / 426 MB | 2.57 s / 2.57 s / 712 MB | 716 ms / 0.72 s / 562 MB |
| read + pass | ours | 304 ms / 0.31 s / 428 MB | 2.63 s / 2.63 s / 712 MB | 718 ms / 0.72 s / 564 MB |
| write, defaults | dta | 134 ms / 0.16 s / 382 MB | 5.90 s / 5.89 s / 774 MB | 651 ms / 0.65 s / 584 MB |
| write, zstd 3 | dta | 149 ms / 0.17 s / 382 MB | 5.91 s / 5.90 s / 760 MB | 662 ms / 0.66 s / 581 MB |

### 1982_Preg

13,768 rows, 174 columns; .dta 3.0 MB; Parquet pyarrow 0.4 MB, polars 0.4 MB, ours 0.5 MB, duckdb 0.4 MB, ours_zstd 0.5 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 148 ms / 0.15 s / 395 MB | 2.05 s / 2.04 s / 647 MB | 407 ms / 0.41 s / 496 MB |
| whole file | polars | 150 ms / 0.15 s / 394 MB | 2.05 s / 2.04 s / 652 MB | 404 ms / 0.40 s / 497 MB |
| whole file | ours | 159 ms / 0.16 s / 396 MB | 2.15 s / 2.15 s / 648 MB | 408 ms / 0.41 s / 497 MB |
| five columns | pyarrow | 257 ms / 0.25 s / 372 MB | 1.54 s / 1.54 s / 604 MB | 334 ms / 0.33 s / 457 MB |
| five columns | polars | 253 ms / 0.25 s / 372 MB | 1.54 s / 1.54 s / 605 MB | 334 ms / 0.33 s / 458 MB |
| five columns | ours | 254 ms / 0.25 s / 374 MB | 1.65 s / 1.64 s / 611 MB | 334 ms / 0.33 s / 459 MB |
| 1,000 rows | pyarrow | 165 ms / 0.16 s / 370 MB | 2.35 s / 2.35 s / 667 MB | 385 ms / 0.39 s / 478 MB |
| 1,000 rows | polars | 166 ms / 0.16 s / 371 MB | 2.35 s / 2.34 s / 667 MB | 384 ms / 0.38 s / 478 MB |
| 1,000 rows | ours | 167 ms / 0.16 s / 371 MB | 2.49 s / 2.49 s / 667 MB | 383 ms / 0.38 s / 478 MB |
| read + pass | pyarrow | 260 ms / 0.26 s / 396 MB | 2.16 s / 2.16 s / 646 MB | 521 ms / 0.52 s / 496 MB |
| read + pass | polars | 260 ms / 0.26 s / 395 MB | 2.16 s / 2.15 s / 651 MB | 518 ms / 0.52 s / 497 MB |
| read + pass | ours | 272 ms / 0.27 s / 398 MB | 2.27 s / 2.26 s / 648 MB | 525 ms / 0.53 s / 497 MB |
| write, defaults | dta | 120 ms / 0.12 s / 372 MB | 4.15 s / 4.14 s / 714 MB | 546 ms / 0.55 s / 509 MB |
| write, zstd 3 | dta | 134 ms / 0.13 s / 371 MB | 4.15 s / 4.15 s / 712 MB | 549 ms / 0.55 s / 510 MB |

### 1988_FemResp

8,450 rows, 1,437 columns; .dta 19.1 MB; Parquet pyarrow 6.1 MB, polars 5.1 MB, ours 6.6 MB, duckdb 5.4 MB, ours_zstd 5.5 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 194 ms / 0.20 s / 498 MB | 2.71 s / 2.71 s / 772 MB | 751 ms / 0.75 s / 691 MB |
| whole file | polars | 194 ms / 0.21 s / 496 MB | 2.87 s / 2.87 s / 792 MB | 758 ms / 0.76 s / 694 MB |
| whole file | ours | 206 ms / 0.22 s / 502 MB | 2.81 s / 2.81 s / 792 MB | 743 ms / 0.74 s / 694 MB |
| five columns | pyarrow | 249 ms / 0.25 s / 373 MB | 1.56 s / 1.56 s / 609 MB | 339 ms / 0.34 s / 461 MB |
| five columns | polars | 248 ms / 0.25 s / 373 MB | 1.70 s / 1.70 s / 612 MB | 336 ms / 0.33 s / 460 MB |
| five columns | ours | 261 ms / 0.26 s / 387 MB | 1.66 s / 1.66 s / 614 MB | 338 ms / 0.34 s / 461 MB |
| 1,000 rows | pyarrow | 179 ms / 0.18 s / 382 MB | 3.08 s / 3.08 s / 841 MB | 698 ms / 0.70 s / 610 MB |
| 1,000 rows | polars | 185 ms / 0.18 s / 382 MB | 3.25 s / 3.25 s / 835 MB | 705 ms / 0.71 s / 607 MB |
| 1,000 rows | ours | 193 ms / 0.19 s / 392 MB | 3.20 s / 3.20 s / 834 MB | 695 ms / 0.70 s / 609 MB |
| read + pass | pyarrow | 327 ms / 0.34 s / 499 MB | 2.84 s / 2.84 s / 774 MB | 873 ms / 0.87 s / 695 MB |
| read + pass | polars | 332 ms / 0.34 s / 497 MB | 3.00 s / 3.00 s / 795 MB | 880 ms / 0.88 s / 695 MB |
| read + pass | ours | 333 ms / 0.34 s / 507 MB | 2.95 s / 2.95 s / 793 MB | 881 ms / 0.88 s / 696 MB |
| write, defaults | dta | 174 ms / 0.23 s / 425 MB | 5.73 s / 5.72 s / 841 MB | 773 ms / 0.77 s / 722 MB |
| write, zstd 3 | dta | 181 ms / 0.23 s / 427 MB | 5.76 s / 5.75 s / 844 MB | 786 ms / 0.79 s / 724 MB |

### 1988_Preg

15,759 rows, 284 columns; .dta 10.7 MB; Parquet pyarrow 3.3 MB, polars 2.8 MB, ours 3.5 MB, duckdb 3.6 MB, ours_zstd 3.0 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 154 ms / 0.16 s / 401 MB | 2.11 s / 2.10 s / 665 MB | 436 ms / 0.44 s / 530 MB |
| whole file | polars | 151 ms / 0.15 s / 400 MB | 2.11 s / 2.11 s / 663 MB | 438 ms / 0.44 s / 531 MB |
| whole file | ours | 163 ms / 0.16 s / 404 MB | 2.23 s / 2.22 s / 666 MB | 443 ms / 0.44 s / 533 MB |
| five columns | pyarrow | 252 ms / 0.25 s / 373 MB | 1.54 s / 1.54 s / 605 MB | 333 ms / 0.33 s / 458 MB |
| five columns | polars | 250 ms / 0.25 s / 372 MB | 1.56 s / 1.56 s / 609 MB | 334 ms / 0.33 s / 458 MB |
| five columns | ours | 251 ms / 0.25 s / 375 MB | 1.53 s / 1.53 s / 605 MB | 336 ms / 0.33 s / 458 MB |
| 1,000 rows | pyarrow | 161 ms / 0.16 s / 372 MB | 2.43 s / 2.43 s / 690 MB | 415 ms / 0.42 s / 495 MB |
| 1,000 rows | polars | 167 ms / 0.17 s / 372 MB | 2.45 s / 2.45 s / 694 MB | 424 ms / 0.42 s / 495 MB |
| 1,000 rows | ours | 172 ms / 0.17 s / 374 MB | 2.57 s / 2.57 s / 698 MB | 410 ms / 0.41 s / 495 MB |
| read + pass | pyarrow | 275 ms / 0.28 s / 402 MB | 2.25 s / 2.25 s / 662 MB | 567 ms / 0.57 s / 534 MB |
| read + pass | polars | 267 ms / 0.27 s / 403 MB | 2.25 s / 2.24 s / 668 MB | 558 ms / 0.56 s / 532 MB |
| read + pass | ours | 276 ms / 0.28 s / 405 MB | 2.33 s / 2.33 s / 670 MB | 561 ms / 0.56 s / 532 MB |
| write, defaults | dta | 126 ms / 0.14 s / 380 MB | 4.57 s / 4.57 s / 769 MB | 591 ms / 0.59 s / 552 MB |
| write, zstd 3 | dta | 139 ms / 0.16 s / 383 MB | 4.58 s / 4.58 s / 766 MB | 592 ms / 0.59 s / 554 MB |

### 1995_FemResp

10,847 rows, 5,754 columns; .dta 78.9 MB; Parquet pyarrow 7.5 MB, polars 6.7 MB, ours 9.5 MB, duckdb 7.1 MB, ours_zstd 8.3 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 346 ms / 0.38 s / 1074 MB | 2.49 s / 2.48 s / 1028 MB | 1.74 s / 1.74 s / 1551 MB |
| whole file | polars | 348 ms / 0.39 s / 1077 MB | 2.51 s / 2.50 s / 1029 MB | 1.75 s / 1.75 s / 1549 MB |
| whole file | ours | 417 ms / 0.46 s / 1122 MB | 2.47 s / 2.47 s / 1031 MB | 1.75 s / 1.75 s / 1550 MB |
| five columns | pyarrow | 257 ms / 0.25 s / 382 MB | 1.58 s / 1.58 s / 622 MB | 348 ms / 0.35 s / 474 MB |
| five columns | polars | 260 ms / 0.26 s / 381 MB | 1.71 s / 1.71 s / 620 MB | 347 ms / 0.35 s / 473 MB |
| five columns | ours | 334 ms / 0.33 s / 426 MB | 1.67 s / 1.67 s / 626 MB | 347 ms / 0.35 s / 482 MB |
| 1,000 rows | pyarrow | 213 ms / 0.22 s / 439 MB | 3.02 s / 3.02 s / 1479 MB | 1.48 s / 1.48 s / 1036 MB |
| 1,000 rows | polars | 215 ms / 0.23 s / 439 MB | 3.09 s / 3.09 s / 1483 MB | 1.52 s / 1.52 s / 1037 MB |
| 1,000 rows | ours | 283 ms / 0.29 s / 487 MB | 3.04 s / 3.04 s / 1491 MB | 1.48 s / 1.48 s / 1035 MB |
| read + pass | pyarrow | 542 ms / 0.58 s / 1089 MB | 2.66 s / 2.66 s / 1039 MB | 1.94 s / 1.94 s / 1551 MB |
| read + pass | polars | 548 ms / 0.59 s / 1094 MB | 2.71 s / 2.71 s / 1030 MB | 1.95 s / 1.95 s / 1549 MB |
| read + pass | ours | 627 ms / 0.66 s / 1126 MB | 2.68 s / 2.68 s / 1035 MB | 1.94 s / 1.94 s / 1554 MB |
| write, defaults | dta | 311 ms / 0.46 s / 630 MB | 10.54 s / 10.54 s / 1276 MB | 2.41 s / 2.42 s / 1735 MB |
| write, zstd 3 | dta | 335 ms / 0.49 s / 631 MB | 10.56 s / 10.56 s / 1258 MB | 2.41 s / 2.42 s / 1733 MB |

### 1995_Preg

21,332 rows, 245 columns; .dta 6.2 MB; Parquet pyarrow 1.3 MB, polars 1.1 MB, ours 1.4 MB, duckdb 1.2 MB, ours_zstd 1.2 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 158 ms / 0.16 s / 417 MB | 2.18 s / 2.18 s / 669 MB | 481 ms / 0.48 s / 539 MB |
| whole file | polars | 158 ms / 0.16 s / 418 MB | 2.08 s / 2.07 s / 670 MB | 478 ms / 0.48 s / 538 MB |
| whole file | ours | 163 ms / 0.17 s / 420 MB | 2.28 s / 2.28 s / 673 MB | 483 ms / 0.48 s / 539 MB |
| five columns | pyarrow | 242 ms / 0.24 s / 373 MB | 1.50 s / 1.50 s / 605 MB | 335 ms / 0.33 s / 459 MB |
| five columns | polars | 242 ms / 0.24 s / 373 MB | 1.51 s / 1.51 s / 608 MB | 335 ms / 0.33 s / 459 MB |
| five columns | ours | 246 ms / 0.24 s / 374 MB | 1.49 s / 1.49 s / 605 MB | 334 ms / 0.33 s / 459 MB |
| 1,000 rows | pyarrow | 167 ms / 0.16 s / 372 MB | 2.56 s / 2.56 s / 706 MB | 431 ms / 0.43 s / 485 MB |
| 1,000 rows | polars | 166 ms / 0.16 s / 372 MB | 2.46 s / 2.46 s / 707 MB | 433 ms / 0.43 s / 486 MB |
| 1,000 rows | ours | 167 ms / 0.17 s / 374 MB | 2.70 s / 2.70 s / 707 MB | 435 ms / 0.43 s / 486 MB |
| read + pass | pyarrow | 279 ms / 0.28 s / 419 MB | 2.28 s / 2.28 s / 670 MB | 599 ms / 0.60 s / 540 MB |
| read + pass | polars | 286 ms / 0.29 s / 419 MB | 2.20 s / 2.20 s / 671 MB | 601 ms / 0.60 s / 538 MB |
| read + pass | ours | 285 ms / 0.29 s / 423 MB | 2.40 s / 2.40 s / 673 MB | 598 ms / 0.60 s / 539 MB |
| write, defaults | dta | 124 ms / 0.14 s / 375 MB | 4.94 s / 4.94 s / 749 MB | 598 ms / 0.60 s / 560 MB |
| write, zstd 3 | dta | 136 ms / 0.15 s / 377 MB | 4.94 s / 4.94 s / 756 MB | 606 ms / 0.60 s / 560 MB |

### 2002_FemPreg

13,593 rows, 243 columns; .dta 4.3 MB; Parquet pyarrow 1.0 MB, polars 0.8 MB, ours 1.1 MB, duckdb 1.0 MB, ours_zstd 0.9 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 159 ms / 0.16 s / 400 MB | 2.27 s / 2.27 s / 663 MB | 503 ms / 0.50 s / 514 MB |
| whole file | polars | 161 ms / 0.16 s / 402 MB | 2.16 s / 2.16 s / 664 MB | 503 ms / 0.50 s / 513 MB |
| whole file | ours | 162 ms / 0.16 s / 402 MB | 2.35 s / 2.35 s / 666 MB | 503 ms / 0.50 s / 514 MB |
| five columns | pyarrow | 244 ms / 0.24 s / 373 MB | 1.60 s / 1.60 s / 608 MB | 383 ms / 0.38 s / 464 MB |
| five columns | polars | 244 ms / 0.24 s / 373 MB | 1.60 s / 1.59 s / 609 MB | 384 ms / 0.38 s / 463 MB |
| five columns | ours | 248 ms / 0.25 s / 373 MB | 1.58 s / 1.58 s / 608 MB | 385 ms / 0.38 s / 463 MB |
| 1,000 rows | pyarrow | 175 ms / 0.17 s / 373 MB | 2.69 s / 2.69 s / 692 MB | 461 ms / 0.46 s / 486 MB |
| 1,000 rows | polars | 168 ms / 0.17 s / 372 MB | 2.59 s / 2.59 s / 692 MB | 460 ms / 0.46 s / 484 MB |
| 1,000 rows | ours | 167 ms / 0.17 s / 372 MB | 2.84 s / 2.83 s / 693 MB | 459 ms / 0.46 s / 485 MB |
| read + pass | pyarrow | 281 ms / 0.28 s / 403 MB | 2.39 s / 2.39 s / 665 MB | 624 ms / 0.62 s / 514 MB |
| read + pass | polars | 281 ms / 0.28 s / 402 MB | 2.29 s / 2.29 s / 666 MB | 632 ms / 0.63 s / 515 MB |
| read + pass | ours | 291 ms / 0.29 s / 403 MB | 2.49 s / 2.48 s / 665 MB | 627 ms / 0.63 s / 515 MB |
| write, defaults | dta | 128 ms / 0.13 s / 373 MB | 5.41 s / 5.41 s / 728 MB | 584 ms / 0.58 s / 527 MB |
| write, zstd 3 | dta | 141 ms / 0.14 s / 374 MB | 5.42 s / 5.42 s / 731 MB | 591 ms / 0.59 s / 525 MB |

### 2002_FemResp

7,643 rows, 3,087 columns; .dta 29.3 MB; Parquet pyarrow 3.8 MB, polars 3.4 MB, ours 4.9 MB, duckdb 3.6 MB, ours_zstd 4.3 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 245 ms / 0.26 s / 620 MB | 3.16 s / 3.16 s / 1011 MB | 1.30 s / 1.30 s / 898 MB |
| whole file | polars | 242 ms / 0.26 s / 619 MB | 15.57 s / 15.56 s / 1332 MB | 1.32 s / 1.32 s / 901 MB |
| whole file | ours | 278 ms / 0.29 s / 648 MB | 6.92 s / 6.92 s / 1172 MB | 1.32 s / 1.32 s / 903 MB |
| five columns | pyarrow | 256 ms / 0.25 s / 376 MB | 1.74 s / 1.74 s / 616 MB | 411 ms / 0.41 s / 471 MB |
| five columns | polars | 256 ms / 0.25 s / 376 MB | 1.56 s / 1.56 s / 615 MB | 409 ms / 0.41 s / 469 MB |
| five columns | ours | 289 ms / 0.29 s / 399 MB | 1.64 s / 1.64 s / 624 MB | 411 ms / 0.41 s / 471 MB |
| 1,000 rows | pyarrow | 197 ms / 0.19 s / 401 MB | 3.69 s / 3.69 s / 1066 MB | 1.22 s / 1.22 s / 772 MB |
| 1,000 rows | polars | 204 ms / 0.20 s / 401 MB | 16.64 s / 16.64 s / 1336 MB | 1.22 s / 1.22 s / 771 MB |
| 1,000 rows | ours | 230 ms / 0.23 s / 426 MB | 7.59 s / 7.59 s / 1177 MB | 1.21 s / 1.21 s / 773 MB |
| read + pass | pyarrow | 391 ms / 0.41 s / 626 MB | 3.31 s / 3.31 s / 1012 MB | 1.46 s / 1.46 s / 900 MB |
| read + pass | polars | 389 ms / 0.41 s / 626 MB | 16.38 s / 16.37 s / 1331 MB | 1.47 s / 1.47 s / 902 MB |
| read + pass | ours | 423 ms / 0.44 s / 653 MB | 7.02 s / 7.02 s / 1172 MB | 1.46 s / 1.46 s / 903 MB |
| write, defaults | dta | 199 ms / 0.26 s / 469 MB | 7.72 s / 7.71 s / 934 MB | 1.16 s / 1.17 s / 940 MB |
| write, zstd 3 | dta | 218 ms / 0.28 s / 470 MB | 7.75 s / 7.75 s / 957 MB | 1.20 s / 1.21 s / 939 MB |

### 2002_HHvars

12,571 rows, 10 columns; .dta 0.1 MB; Parquet pyarrow 0.1 MB, polars 0.1 MB, ours 0.1 MB, duckdb 0.1 MB, ours_zstd 0.1 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 135 ms / 0.13 s / 368 MB | 1.96 s / 1.95 s / 630 MB | 334 ms / 0.33 s / 458 MB |
| whole file | polars | 133 ms / 0.13 s / 368 MB | 2.11 s / 2.11 s / 634 MB | 335 ms / 0.33 s / 459 MB |
| whole file | ours | 133 ms / 0.13 s / 369 MB | 2.07 s / 2.06 s / 633 MB | 336 ms / 0.34 s / 458 MB |
| five columns | pyarrow | 247 ms / 0.25 s / 371 MB | 1.53 s / 1.53 s / 604 MB | 338 ms / 0.34 s / 458 MB |
| five columns | polars | 247 ms / 0.24 s / 371 MB | 1.68 s / 1.68 s / 614 MB | 336 ms / 0.34 s / 457 MB |
| five columns | ours | 245 ms / 0.24 s / 371 MB | 1.62 s / 1.62 s / 611 MB | 334 ms / 0.33 s / 458 MB |
| 1,000 rows | pyarrow | 155 ms / 0.15 s / 370 MB | 2.29 s / 2.29 s / 644 MB | 331 ms / 0.33 s / 460 MB |
| 1,000 rows | polars | 158 ms / 0.16 s / 370 MB | 2.45 s / 2.45 s / 642 MB | 329 ms / 0.33 s / 459 MB |
| 1,000 rows | ours | 158 ms / 0.16 s / 369 MB | 2.42 s / 2.41 s / 646 MB | 319 ms / 0.32 s / 459 MB |
| read + pass | pyarrow | 255 ms / 0.25 s / 370 MB | 2.07 s / 2.07 s / 633 MB | 451 ms / 0.45 s / 464 MB |
| read + pass | polars | 258 ms / 0.26 s / 371 MB | 2.21 s / 2.21 s / 632 MB | 453 ms / 0.45 s / 465 MB |
| read + pass | ours | 248 ms / 0.25 s / 371 MB | 2.18 s / 2.17 s / 632 MB | 449 ms / 0.45 s / 464 MB |
| write, defaults | dta | 104 ms / 0.10 s / 368 MB | 2.93 s / 2.92 s / 667 MB | 501 ms / 0.50 s / 457 MB |
| write, zstd 3 | dta | 116 ms / 0.11 s / 368 MB | 2.91 s / 2.91 s / 668 MB | 496 ms / 0.50 s / 459 MB |

### 2002_Male

4,928 rows, 1,993 columns; .dta 12.7 MB; Parquet pyarrow 1.8 MB, polars 1.7 MB, ours 2.1 MB, duckdb 1.7 MB, ours_zstd 1.9 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 199 ms / 0.20 s / 476 MB | 3.13 s / 3.12 s / 780 MB | 945 ms / 0.95 s / 676 MB |
| whole file | polars | 195 ms / 0.20 s / 477 MB | 2.91 s / 2.91 s / 781 MB | 964 ms / 0.96 s / 678 MB |
| whole file | ours | 206 ms / 0.21 s / 481 MB | 2.90 s / 2.90 s / 812 MB | 960 ms / 0.96 s / 677 MB |
| five columns | pyarrow | 248 ms / 0.25 s / 375 MB | 1.62 s / 1.61 s / 613 MB | 392 ms / 0.39 s / 466 MB |
| five columns | polars | 248 ms / 0.25 s / 373 MB | 1.55 s / 1.54 s / 609 MB | 387 ms / 0.39 s / 466 MB |
| five columns | ours | 265 ms / 0.26 s / 384 MB | 1.63 s / 1.62 s / 615 MB | 388 ms / 0.39 s / 467 MB |
| 1,000 rows | pyarrow | 183 ms / 0.18 s / 390 MB | 3.60 s / 3.60 s / 849 MB | 895 ms / 0.89 s / 650 MB |
| 1,000 rows | polars | 188 ms / 0.19 s / 390 MB | 3.37 s / 3.36 s / 836 MB | 901 ms / 0.90 s / 647 MB |
| 1,000 rows | ours | 194 ms / 0.19 s / 395 MB | 3.43 s / 3.43 s / 864 MB | 915 ms / 0.91 s / 649 MB |
| read + pass | pyarrow | 327 ms / 0.33 s / 482 MB | 3.28 s / 3.27 s / 786 MB | 1.09 s / 1.09 s / 681 MB |
| read + pass | polars | 331 ms / 0.34 s / 481 MB | 3.06 s / 3.06 s / 779 MB | 1.10 s / 1.10 s / 682 MB |
| read + pass | ours | 340 ms / 0.34 s / 488 MB | 3.03 s / 3.03 s / 809 MB | 1.08 s / 1.08 s / 681 MB |
| write, defaults | dta | 147 ms / 0.17 s / 399 MB | 6.95 s / 6.95 s / 800 MB | 867 ms / 0.87 s / 692 MB |
| write, zstd 3 | dta | 161 ms / 0.19 s / 399 MB | 7.05 s / 7.03 s / 806 MB | 860 ms / 0.86 s / 691 MB |

### 2002_curr_ins

12,571 rows, 3 columns; .dta 0.1 MB; Parquet pyarrow 0.1 MB, polars 0.0 MB, ours 0.1 MB, duckdb 0.1 MB, ours_zstd 0.0 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 140 ms / 0.14 s / 368 MB | 1.95 s / 1.95 s / 632 MB | 310 ms / 0.31 s / 456 MB |
| whole file | polars | 138 ms / 0.14 s / 368 MB | 2.12 s / 2.11 s / 634 MB | 308 ms / 0.31 s / 456 MB |
| whole file | ours | 134 ms / 0.13 s / 368 MB | 2.06 s / 2.06 s / 633 MB | 317 ms / 0.32 s / 456 MB |
| five columns | pyarrow | 242 ms / 0.24 s / 371 MB | 1.54 s / 1.54 s / 604 MB | 310 ms / 0.31 s / 456 MB |
| five columns | polars | 243 ms / 0.24 s / 371 MB | 1.67 s / 1.67 s / 613 MB | 318 ms / 0.32 s / 456 MB |
| five columns | ours | 256 ms / 0.25 s / 371 MB | 1.66 s / 1.66 s / 611 MB | 314 ms / 0.31 s / 456 MB |
| 1,000 rows | pyarrow | 160 ms / 0.16 s / 369 MB | 2.30 s / 2.30 s / 644 MB | 312 ms / 0.31 s / 457 MB |
| 1,000 rows | polars | 154 ms / 0.15 s / 369 MB | 2.49 s / 2.48 s / 651 MB | 311 ms / 0.31 s / 458 MB |
| 1,000 rows | ours | 153 ms / 0.15 s / 369 MB | 2.41 s / 2.41 s / 639 MB | 307 ms / 0.31 s / 457 MB |
| read + pass | pyarrow | 249 ms / 0.25 s / 371 MB | 2.08 s / 2.08 s / 634 MB | 432 ms / 0.43 s / 464 MB |
| read + pass | polars | 252 ms / 0.25 s / 371 MB | 2.22 s / 2.22 s / 630 MB | 422 ms / 0.42 s / 464 MB |
| read + pass | ours | 251 ms / 0.25 s / 371 MB | 2.19 s / 2.18 s / 636 MB | 424 ms / 0.42 s / 463 MB |
| write, defaults | dta | 102 ms / 0.10 s / 367 MB | 2.00 s / 2.00 s / 611 MB | 439 ms / 0.44 s / 456 MB |
| write, zstd 3 | dta | 114 ms / 0.11 s / 368 MB | 2.01 s / 2.01 s / 611 MB | 435 ms / 0.43 s / 457 MB |

### 2002_hhpartypnew

12,571 rows, 3 columns; .dta 0.1 MB; Parquet pyarrow 0.1 MB, polars 0.0 MB, ours 0.1 MB, duckdb 0.1 MB, ours_zstd 0.0 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 138 ms / 0.14 s / 367 MB | 1.96 s / 1.95 s / 630 MB | 311 ms / 0.31 s / 455 MB |
| whole file | polars | 137 ms / 0.14 s / 368 MB | 2.11 s / 2.11 s / 630 MB | 306 ms / 0.31 s / 456 MB |
| whole file | ours | 140 ms / 0.14 s / 368 MB | 2.07 s / 2.06 s / 632 MB | 314 ms / 0.31 s / 456 MB |
| five columns | pyarrow | 246 ms / 0.24 s / 371 MB | 1.54 s / 1.53 s / 605 MB | 309 ms / 0.31 s / 456 MB |
| five columns | polars | 244 ms / 0.24 s / 371 MB | 1.67 s / 1.67 s / 613 MB | 309 ms / 0.31 s / 456 MB |
| five columns | ours | 247 ms / 0.25 s / 371 MB | 1.64 s / 1.64 s / 611 MB | 313 ms / 0.31 s / 456 MB |
| 1,000 rows | pyarrow | 156 ms / 0.15 s / 369 MB | 2.29 s / 2.29 s / 643 MB | 302 ms / 0.30 s / 458 MB |
| 1,000 rows | polars | 161 ms / 0.16 s / 369 MB | 2.44 s / 2.44 s / 641 MB | 302 ms / 0.30 s / 458 MB |
| 1,000 rows | ours | 160 ms / 0.16 s / 369 MB | 2.42 s / 2.41 s / 641 MB | 301 ms / 0.30 s / 457 MB |
| read + pass | pyarrow | 252 ms / 0.25 s / 371 MB | 2.07 s / 2.07 s / 629 MB | 422 ms / 0.42 s / 463 MB |
| read + pass | polars | 249 ms / 0.25 s / 371 MB | 2.22 s / 2.21 s / 633 MB | 419 ms / 0.42 s / 463 MB |
| read + pass | ours | 246 ms / 0.24 s / 371 MB | 2.18 s / 2.18 s / 632 MB | 421 ms / 0.42 s / 463 MB |
| write, defaults | dta | 103 ms / 0.10 s / 368 MB | 2.01 s / 2.00 s / 612 MB | 436 ms / 0.43 s / 457 MB |
| write, zstd 3 | dta | 116 ms / 0.11 s / 368 MB | 2.01 s / 2.00 s / 612 MB | 439 ms / 0.44 s / 457 MB |

### 2006_2010_FemPreg

20,492 rows, 287 columns; .dta 7.6 MB; Parquet pyarrow 1.7 MB, polars 1.4 MB, ours 1.7 MB, duckdb 1.6 MB, ours_zstd 1.5 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 167 ms / 0.17 s / 424 MB | 2.32 s / 2.32 s / 677 MB | 548 ms / 0.55 s / 553 MB |
| whole file | polars | 161 ms / 0.16 s / 426 MB | 2.23 s / 2.22 s / 680 MB | 550 ms / 0.55 s / 553 MB |
| whole file | ours | 164 ms / 0.17 s / 425 MB | 2.42 s / 2.41 s / 678 MB | 547 ms / 0.55 s / 554 MB |
| five columns | pyarrow | 242 ms / 0.24 s / 373 MB | 1.62 s / 1.62 s / 608 MB | 384 ms / 0.38 s / 463 MB |
| five columns | polars | 247 ms / 0.24 s / 373 MB | 1.62 s / 1.61 s / 610 MB | 381 ms / 0.38 s / 463 MB |
| five columns | ours | 256 ms / 0.25 s / 373 MB | 1.60 s / 1.60 s / 608 MB | 383 ms / 0.38 s / 465 MB |
| 1,000 rows | pyarrow | 169 ms / 0.17 s / 372 MB | 2.78 s / 2.78 s / 719 MB | 482 ms / 0.48 s / 490 MB |
| 1,000 rows | polars | 171 ms / 0.17 s / 372 MB | 2.66 s / 2.66 s / 717 MB | 482 ms / 0.48 s / 490 MB |
| 1,000 rows | ours | 171 ms / 0.17 s / 373 MB | 2.92 s / 2.91 s / 721 MB | 480 ms / 0.48 s / 491 MB |
| read + pass | pyarrow | 293 ms / 0.30 s / 427 MB | 2.45 s / 2.45 s / 678 MB | 669 ms / 0.67 s / 554 MB |
| read + pass | polars | 298 ms / 0.30 s / 426 MB | 2.35 s / 2.35 s / 680 MB | 669 ms / 0.67 s / 554 MB |
| read + pass | ours | 304 ms / 0.31 s / 429 MB | 2.54 s / 2.53 s / 684 MB | 674 ms / 0.67 s / 556 MB |
| write, defaults | dta | 155 ms / 0.17 s / 378 MB | 7.11 s / 7.11 s / 749 MB | 652 ms / 0.65 s / 569 MB |
| write, zstd 3 | dta | 170 ms / 0.18 s / 380 MB | 7.16 s / 7.16 s / 784 MB | 642 ms / 0.64 s / 570 MB |

### 2006_2010_FemResp

12,279 rows, 3,741 columns; .dta 55.6 MB; Parquet pyarrow 6.8 MB, polars 5.8 MB, ours 8.1 MB, duckdb 6.4 MB, ours_zstd 7.0 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 288 ms / 0.32 s / 806 MB | 3.43 s / 3.43 s / 1151 MB | 1.62 s / 1.62 s / 1167 MB |
| whole file | polars | 283 ms / 0.32 s / 806 MB | 9.95 s / 9.94 s / 1516 MB | 1.62 s / 1.62 s / 1169 MB |
| whole file | ours | 341 ms / 0.37 s / 836 MB | 8.72 s / 8.71 s / 1433 MB | 1.63 s / 1.63 s / 1168 MB |
| five columns | pyarrow | 264 ms / 0.26 s / 378 MB | 1.65 s / 1.64 s / 619 MB | 390 ms / 0.39 s / 470 MB |
| five columns | polars | 263 ms / 0.26 s / 376 MB | 1.68 s / 1.68 s / 623 MB | 388 ms / 0.39 s / 471 MB |
| five columns | ours | 300 ms / 0.30 s / 404 MB | 1.75 s / 1.74 s / 624 MB | 389 ms / 0.39 s / 476 MB |
| 1,000 rows | pyarrow | 211 ms / 0.21 s / 407 MB | 3.96 s / 3.95 s / 1281 MB | 1.43 s / 1.43 s / 861 MB |
| 1,000 rows | polars | 218 ms / 0.22 s / 408 MB | 10.67 s / 10.67 s / 1682 MB | 1.43 s / 1.43 s / 860 MB |
| 1,000 rows | ours | 262 ms / 0.26 s / 439 MB | 9.35 s / 9.34 s / 1438 MB | 1.44 s / 1.44 s / 857 MB |
| read + pass | pyarrow | 478 ms / 0.50 s / 813 MB | 3.58 s / 3.57 s / 1154 MB | 1.80 s / 1.80 s / 1169 MB |
| read + pass | polars | 463 ms / 0.50 s / 815 MB | 10.18 s / 10.18 s / 1525 MB | 1.81 s / 1.81 s / 1170 MB |
| read + pass | ours | 531 ms / 0.56 s / 852 MB | 8.90 s / 8.90 s / 1432 MB | 1.81 s / 1.81 s / 1172 MB |
| write, defaults | dta | 273 ms / 0.40 s / 561 MB | 10.02 s / 10.02 s / 1049 MB | 1.58 s / 1.59 s / 1309 MB |
| write, zstd 3 | dta | 291 ms / 0.43 s / 564 MB | 10.05 s / 10.04 s / 1077 MB | 1.62 s / 1.62 s / 1328 MB |

### 2006_2010_Male

10,403 rows, 2,801 columns; .dta 37.2 MB; Parquet pyarrow 3.8 MB, polars 3.3 MB, ours 4.3 MB, duckdb 3.5 MB, ours_zstd 3.8 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 247 ms / 0.26 s / 711 MB | 3.14 s / 3.14 s / 1024 MB | 1.30 s / 1.30 s / 1005 MB |
| whole file | polars | 250 ms / 0.27 s / 710 MB | 7.08 s / 7.08 s / 1201 MB | 1.29 s / 1.29 s / 1002 MB |
| whole file | ours | 283 ms / 0.30 s / 727 MB | 6.18 s / 6.16 s / 1111 MB | 1.29 s / 1.29 s / 1003 MB |
| five columns | pyarrow | 264 ms / 0.26 s / 376 MB | 1.64 s / 1.64 s / 620 MB | 387 ms / 0.39 s / 470 MB |
| five columns | polars | 258 ms / 0.26 s / 377 MB | 1.67 s / 1.67 s / 620 MB | 388 ms / 0.39 s / 470 MB |
| five columns | ours | 279 ms / 0.28 s / 394 MB | 1.73 s / 1.73 s / 623 MB | 385 ms / 0.39 s / 471 MB |
| 1,000 rows | pyarrow | 195 ms / 0.19 s / 400 MB | 3.63 s / 3.63 s / 1120 MB | 1.15 s / 1.15 s / 770 MB |
| 1,000 rows | polars | 198 ms / 0.20 s / 400 MB | 7.65 s / 7.65 s / 1207 MB | 1.14 s / 1.14 s / 773 MB |
| 1,000 rows | ours | 215 ms / 0.21 s / 417 MB | 6.74 s / 6.74 s / 1251 MB | 1.14 s / 1.14 s / 772 MB |
| read + pass | pyarrow | 410 ms / 0.43 s / 717 MB | 3.29 s / 3.28 s / 1023 MB | 1.46 s / 1.46 s / 1006 MB |
| read + pass | polars | 420 ms / 0.44 s / 717 MB | 7.22 s / 7.21 s / 1200 MB | 1.46 s / 1.46 s / 1001 MB |
| read + pass | ours | 449 ms / 0.47 s / 736 MB | 6.34 s / 6.34 s / 1110 MB | 1.45 s / 1.45 s / 1003 MB |
| write, defaults | dta | 201 ms / 0.27 s / 501 MB | 9.14 s / 9.14 s / 1030 MB | 1.22 s / 1.23 s / 1121 MB |
| write, zstd 3 | dta | 218 ms / 0.30 s / 492 MB | 9.15 s / 9.15 s / 1042 MB | 1.22 s / 1.22 s / 1121 MB |

### 2011_2013_FemPreg

9,543 rows, 278 columns; .dta 3.5 MB; Parquet pyarrow 0.8 MB, polars 0.7 MB, ours 0.8 MB, duckdb 0.8 MB, ours_zstd 0.7 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 156 ms / 0.15 s / 394 MB | 2.30 s / 2.29 s / 654 MB | 508 ms / 0.51 s / 502 MB |
| whole file | polars | 158 ms / 0.16 s / 394 MB | 2.19 s / 2.19 s / 656 MB | 511 ms / 0.51 s / 502 MB |
| whole file | ours | 160 ms / 0.16 s / 396 MB | 2.39 s / 2.39 s / 657 MB | 507 ms / 0.51 s / 503 MB |
| five columns | pyarrow | 248 ms / 0.25 s / 372 MB | 1.61 s / 1.61 s / 610 MB | 380 ms / 0.38 s / 463 MB |
| five columns | polars | 246 ms / 0.24 s / 372 MB | 1.62 s / 1.61 s / 609 MB | 383 ms / 0.38 s / 463 MB |
| five columns | ours | 244 ms / 0.24 s / 374 MB | 1.59 s / 1.58 s / 608 MB | 383 ms / 0.38 s / 463 MB |
| 1,000 rows | pyarrow | 168 ms / 0.17 s / 372 MB | 2.71 s / 2.71 s / 678 MB | 469 ms / 0.47 s / 488 MB |
| 1,000 rows | polars | 166 ms / 0.16 s / 372 MB | 2.61 s / 2.61 s / 679 MB | 466 ms / 0.47 s / 487 MB |
| 1,000 rows | ours | 174 ms / 0.17 s / 373 MB | 2.87 s / 2.86 s / 682 MB | 470 ms / 0.47 s / 488 MB |
| read + pass | pyarrow | 284 ms / 0.28 s / 394 MB | 2.42 s / 2.41 s / 655 MB | 628 ms / 0.63 s / 502 MB |
| read + pass | polars | 275 ms / 0.27 s / 394 MB | 2.31 s / 2.31 s / 655 MB | 638 ms / 0.64 s / 504 MB |
| read + pass | ours | 276 ms / 0.27 s / 398 MB | 2.50 s / 2.50 s / 661 MB | 628 ms / 0.63 s / 503 MB |
| write, defaults | dta | 120 ms / 0.12 s / 374 MB | 5.36 s / 5.36 s / 767 MB | 582 ms / 0.58 s / 516 MB |
| write, zstd 3 | dta | 134 ms / 0.13 s / 374 MB | 5.38 s / 5.38 s / 754 MB | 584 ms / 0.58 s / 518 MB |

### 2011_2013_FemResp

5,601 rows, 3,094 columns; .dta 22.6 MB; Parquet pyarrow 3.7 MB, polars 3.4 MB, ours 4.3 MB, duckdb 3.5 MB, ours_zstd 3.8 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 215 ms / 0.23 s / 539 MB | 3.16 s / 3.15 s / 925 MB | 1.29 s / 1.29 s / 818 MB |
| whole file | polars | 214 ms / 0.23 s / 540 MB | 7.94 s / 7.94 s / 1269 MB | 1.30 s / 1.30 s / 821 MB |
| whole file | ours | 245 ms / 0.26 s / 558 MB | 12.99 s / 12.99 s / 1112 MB | 1.28 s / 1.28 s / 817 MB |
| five columns | pyarrow | 254 ms / 0.25 s / 377 MB | 1.64 s / 1.64 s / 619 MB | 391 ms / 0.39 s / 469 MB |
| five columns | polars | 253 ms / 0.25 s / 377 MB | 1.67 s / 1.67 s / 621 MB | 387 ms / 0.39 s / 469 MB |
| five columns | ours | 271 ms / 0.27 s / 393 MB | 1.64 s / 1.64 s / 624 MB | 386 ms / 0.39 s / 469 MB |
| 1,000 rows | pyarrow | 194 ms / 0.19 s / 399 MB | 3.68 s / 3.67 s / 1017 MB | 1.21 s / 1.21 s / 774 MB |
| 1,000 rows | polars | 196 ms / 0.19 s / 399 MB | 8.46 s / 8.45 s / 1272 MB | 1.21 s / 1.21 s / 768 MB |
| 1,000 rows | ours | 214 ms / 0.21 s / 417 MB | 13.09 s / 13.09 s / 1115 MB | 1.21 s / 1.21 s / 775 MB |
| read + pass | pyarrow | 357 ms / 0.37 s / 548 MB | 3.29 s / 3.29 s / 923 MB | 1.45 s / 1.45 s / 821 MB |
| read + pass | polars | 359 ms / 0.37 s / 548 MB | 8.04 s / 8.04 s / 1270 MB | 1.45 s / 1.45 s / 820 MB |
| read + pass | ours | 387 ms / 0.40 s / 566 MB | 12.48 s / 12.48 s / 1114 MB | 1.45 s / 1.45 s / 822 MB |
| write, defaults | dta | 183 ms / 0.24 s / 442 MB | 7.92 s / 7.92 s / 876 MB | 1.14 s / 1.14 s / 938 MB |
| write, zstd 3 | dta | 200 ms / 0.27 s / 443 MB | 8.00 s / 8.00 s / 924 MB | 1.17 s / 1.18 s / 938 MB |

### 2011_2013_Male

4,815 rows, 3,059 columns; .dta 19.4 MB; Parquet pyarrow 2.4 MB, polars 2.3 MB, ours 2.9 MB, duckdb 2.2 MB, ours_zstd 2.6 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 206 ms / 0.21 s / 528 MB | 3.12 s / 3.12 s / 890 MB | 1.28 s / 1.28 s / 803 MB |
| whole file | polars | 215 ms / 0.22 s / 528 MB | 15.70 s / 15.69 s / 1246 MB | 1.28 s / 1.28 s / 805 MB |
| whole file | ours | 241 ms / 0.25 s / 541 MB | 6.39 s / 6.39 s / 1090 MB | 1.26 s / 1.26 s / 799 MB |
| five columns | pyarrow | 260 ms / 0.26 s / 377 MB | 1.63 s / 1.63 s / 619 MB | 387 ms / 0.39 s / 469 MB |
| five columns | polars | 258 ms / 0.26 s / 376 MB | 1.68 s / 1.68 s / 621 MB | 386 ms / 0.39 s / 470 MB |
| five columns | ours | 274 ms / 0.27 s / 391 MB | 1.64 s / 1.64 s / 623 MB | 388 ms / 0.39 s / 469 MB |
| 1,000 rows | pyarrow | 195 ms / 0.19 s / 401 MB | 3.62 s / 3.61 s / 970 MB | 1.20 s / 1.20 s / 761 MB |
| 1,000 rows | polars | 194 ms / 0.19 s / 400 MB | 16.81 s / 16.80 s / 1252 MB | 1.22 s / 1.22 s / 764 MB |
| 1,000 rows | ours | 208 ms / 0.21 s / 417 MB | 6.92 s / 6.92 s / 1022 MB | 1.20 s / 1.20 s / 766 MB |
| read + pass | pyarrow | 346 ms / 0.35 s / 535 MB | 3.27 s / 3.27 s / 875 MB | 1.40 s / 1.40 s / 807 MB |
| read + pass | polars | 345 ms / 0.35 s / 537 MB | 15.76 s / 15.76 s / 1247 MB | 1.41 s / 1.41 s / 805 MB |
| read + pass | ours | 370 ms / 0.38 s / 548 MB | 6.54 s / 6.54 s / 1094 MB | 1.42 s / 1.42 s / 807 MB |
| write, defaults | dta | 163 ms / 0.20 s / 436 MB | 7.54 s / 7.54 s / 912 MB | 1.09 s / 1.09 s / 851 MB |
| write, zstd 3 | dta | 179 ms / 0.22 s / 438 MB | 7.54 s / 7.54 s / 911 MB | 1.13 s / 1.13 s / 851 MB |

### 2011_2019_FemaleWgt

22,995 rows, 7 columns; .dta 1.2 MB; Parquet pyarrow 1.0 MB, polars 0.7 MB, ours 0.8 MB, duckdb 0.8 MB, ours_zstd 0.7 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 142 ms / 0.14 s / 369 MB | 2.02 s / 2.02 s / 637 MB | 357 ms / 0.36 s / 465 MB |
| whole file | polars | 143 ms / 0.14 s / 371 MB | 1.86 s / 1.85 s / 638 MB | 361 ms / 0.36 s / 464 MB |
| whole file | ours | 143 ms / 0.14 s / 369 MB | 1.82 s / 1.82 s / 636 MB | 362 ms / 0.36 s / 465 MB |
| five columns | pyarrow | 246 ms / 0.24 s / 373 MB | 1.58 s / 1.57 s / 608 MB | 352 ms / 0.35 s / 464 MB |
| five columns | polars | 247 ms / 0.24 s / 372 MB | 1.43 s / 1.43 s / 608 MB | 351 ms / 0.35 s / 463 MB |
| five columns | ours | 246 ms / 0.24 s / 373 MB | 1.39 s / 1.39 s / 606 MB | 351 ms / 0.35 s / 462 MB |
| 1,000 rows | pyarrow | 158 ms / 0.16 s / 370 MB | 2.39 s / 2.39 s / 650 MB | 346 ms / 0.34 s / 466 MB |
| 1,000 rows | polars | 159 ms / 0.16 s / 370 MB | 2.22 s / 2.21 s / 649 MB | 348 ms / 0.35 s / 465 MB |
| 1,000 rows | ours | 161 ms / 0.16 s / 370 MB | 2.17 s / 2.17 s / 649 MB | 345 ms / 0.34 s / 465 MB |
| read + pass | pyarrow | 252 ms / 0.25 s / 372 MB | 2.13 s / 2.13 s / 640 MB | 468 ms / 0.47 s / 465 MB |
| read + pass | polars | 255 ms / 0.25 s / 372 MB | 1.97 s / 1.97 s / 636 MB | 469 ms / 0.47 s / 465 MB |
| read + pass | ours | 252 ms / 0.25 s / 371 MB | 1.93 s / 1.93 s / 637 MB | 468 ms / 0.47 s / 466 MB |
| write, defaults | dta | 100 ms / 0.10 s / 370 MB | 2.12 s / 2.12 s / 623 MB | 489 ms / 0.49 s / 470 MB |
| write, zstd 3 | dta | 114 ms / 0.11 s / 371 MB | 2.13 s / 2.13 s / 624 MB | 490 ms / 0.49 s / 472 MB |

### 2011_2019_MaleWgt

19,067 rows, 7 columns; .dta 1.0 MB; Parquet pyarrow 0.8 MB, polars 0.6 MB, ours 0.7 MB, duckdb 0.7 MB, ours_zstd 0.6 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 140 ms / 0.14 s / 370 MB | 2.02 s / 2.01 s / 638 MB | 355 ms / 0.35 s / 464 MB |
| whole file | polars | 140 ms / 0.14 s / 369 MB | 1.86 s / 1.86 s / 638 MB | 360 ms / 0.36 s / 464 MB |
| whole file | ours | 140 ms / 0.14 s / 370 MB | 1.82 s / 1.82 s / 637 MB | 353 ms / 0.35 s / 464 MB |
| five columns | pyarrow | 245 ms / 0.24 s / 373 MB | 1.58 s / 1.58 s / 608 MB | 361 ms / 0.36 s / 463 MB |
| five columns | polars | 248 ms / 0.25 s / 372 MB | 1.43 s / 1.43 s / 610 MB | 355 ms / 0.35 s / 462 MB |
| five columns | ours | 245 ms / 0.24 s / 372 MB | 1.39 s / 1.39 s / 608 MB | 362 ms / 0.36 s / 463 MB |
| 1,000 rows | pyarrow | 158 ms / 0.16 s / 370 MB | 2.39 s / 2.39 s / 650 MB | 345 ms / 0.34 s / 466 MB |
| 1,000 rows | polars | 159 ms / 0.16 s / 370 MB | 2.21 s / 2.20 s / 648 MB | 351 ms / 0.35 s / 465 MB |
| 1,000 rows | ours | 158 ms / 0.16 s / 370 MB | 2.19 s / 2.19 s / 649 MB | 350 ms / 0.35 s / 465 MB |
| read + pass | pyarrow | 259 ms / 0.26 s / 372 MB | 2.17 s / 2.16 s / 634 MB | 483 ms / 0.48 s / 466 MB |
| read + pass | polars | 255 ms / 0.25 s / 372 MB | 1.98 s / 1.98 s / 617 MB | 480 ms / 0.48 s / 465 MB |
| read + pass | ours | 251 ms / 0.25 s / 370 MB | 1.95 s / 1.94 s / 637 MB | 467 ms / 0.47 s / 464 MB |
| write, defaults | dta | 100 ms / 0.10 s / 369 MB | 2.13 s / 2.13 s / 622 MB | 492 ms / 0.49 s / 470 MB |
| write, zstd 3 | dta | 113 ms / 0.11 s / 371 MB | 2.13 s / 2.13 s / 625 MB | 490 ms / 0.49 s / 471 MB |

### 2013_2015_FemPreg

9,358 rows, 278 columns; .dta 3.4 MB; Parquet pyarrow 0.8 MB, polars 0.7 MB, ours 0.8 MB, duckdb 0.7 MB, ours_zstd 0.7 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 154 ms / 0.15 s / 394 MB | 2.29 s / 2.29 s / 655 MB | 508 ms / 0.51 s / 502 MB |
| whole file | polars | 154 ms / 0.15 s / 393 MB | 2.19 s / 2.19 s / 657 MB | 512 ms / 0.51 s / 502 MB |
| whole file | ours | 155 ms / 0.15 s / 394 MB | 2.39 s / 2.39 s / 660 MB | 506 ms / 0.51 s / 502 MB |
| five columns | pyarrow | 243 ms / 0.24 s / 371 MB | 1.61 s / 1.61 s / 608 MB | 384 ms / 0.38 s / 463 MB |
| five columns | polars | 243 ms / 0.24 s / 372 MB | 1.62 s / 1.62 s / 609 MB | 383 ms / 0.38 s / 463 MB |
| five columns | ours | 245 ms / 0.24 s / 373 MB | 1.59 s / 1.59 s / 608 MB | 384 ms / 0.38 s / 463 MB |
| 1,000 rows | pyarrow | 164 ms / 0.16 s / 371 MB | 2.74 s / 2.74 s / 680 MB | 477 ms / 0.48 s / 487 MB |
| 1,000 rows | polars | 167 ms / 0.16 s / 372 MB | 2.63 s / 2.63 s / 679 MB | 470 ms / 0.47 s / 487 MB |
| 1,000 rows | ours | 166 ms / 0.16 s / 372 MB | 2.89 s / 2.89 s / 683 MB | 470 ms / 0.47 s / 487 MB |
| read + pass | pyarrow | 276 ms / 0.27 s / 393 MB | 2.44 s / 2.44 s / 655 MB | 637 ms / 0.64 s / 505 MB |
| read + pass | polars | 274 ms / 0.27 s / 396 MB | 2.31 s / 2.31 s / 657 MB | 635 ms / 0.63 s / 503 MB |
| read + pass | ours | 275 ms / 0.27 s / 397 MB | 2.51 s / 2.51 s / 660 MB | 644 ms / 0.64 s / 503 MB |
| write, defaults | dta | 119 ms / 0.12 s / 374 MB | 5.39 s / 5.39 s / 740 MB | 579 ms / 0.58 s / 518 MB |
| write, zstd 3 | dta | 134 ms / 0.13 s / 374 MB | 5.40 s / 5.40 s / 746 MB | 587 ms / 0.59 s / 517 MB |

### 2013_2015_FemResp

5,699 rows, 3,207 columns; .dta 24.0 MB; Parquet pyarrow 3.8 MB, polars 3.4 MB, ours 4.7 MB, duckdb 3.6 MB, ours_zstd 4.2 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 216 ms / 0.23 s / 545 MB | 3.18 s / 3.18 s / 934 MB | 1.31 s / 1.31 s / 827 MB |
| whole file | polars | 218 ms / 0.23 s / 545 MB | 15.23 s / 15.23 s / 1272 MB | 1.32 s / 1.32 s / 829 MB |
| whole file | ours | 244 ms / 0.26 s / 568 MB | 13.69 s / 13.68 s / 1112 MB | 1.33 s / 1.33 s / 829 MB |
| five columns | pyarrow | 257 ms / 0.26 s / 377 MB | 1.65 s / 1.64 s / 619 MB | 389 ms / 0.39 s / 470 MB |
| five columns | polars | 254 ms / 0.25 s / 375 MB | 1.68 s / 1.68 s / 622 MB | 387 ms / 0.39 s / 471 MB |
| five columns | ours | 286 ms / 0.28 s / 396 MB | 1.63 s / 1.63 s / 625 MB | 398 ms / 0.40 s / 471 MB |
| 1,000 rows | pyarrow | 194 ms / 0.19 s / 401 MB | 3.74 s / 3.74 s / 1027 MB | 1.24 s / 1.24 s / 781 MB |
| 1,000 rows | polars | 199 ms / 0.20 s / 400 MB | 15.99 s / 15.98 s / 1276 MB | 1.27 s / 1.27 s / 783 MB |
| 1,000 rows | ours | 228 ms / 0.23 s / 422 MB | 14.06 s / 14.05 s / 1117 MB | 1.25 s / 1.25 s / 789 MB |
| read + pass | pyarrow | 354 ms / 0.37 s / 553 MB | 3.36 s / 3.36 s / 937 MB | 1.49 s / 1.49 s / 828 MB |
| read + pass | polars | 365 ms / 0.38 s / 553 MB | 15.39 s / 15.39 s / 1271 MB | 1.50 s / 1.50 s / 832 MB |
| read + pass | ours | 380 ms / 0.39 s / 576 MB | 14.49 s / 14.48 s / 1116 MB | 1.49 s / 1.49 s / 834 MB |
| write, defaults | dta | 191 ms / 0.25 s / 458 MB | 7.58 s / 7.57 s / 892 MB | 1.18 s / 1.18 s / 953 MB |
| write, zstd 3 | dta | 209 ms / 0.28 s / 459 MB | 7.58 s / 7.57 s / 902 MB | 1.21 s / 1.21 s / 953 MB |

### 2013_2015_Male

4,506 rows, 2,940 columns; .dta 18.0 MB; Parquet pyarrow 2.3 MB, polars 2.2 MB, ours 2.9 MB, duckdb 2.1 MB, ours_zstd 2.7 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 206 ms / 0.21 s / 522 MB | 3.10 s / 3.09 s / 867 MB | 1.23 s / 1.23 s / 791 MB |
| whole file | polars | 205 ms / 0.21 s / 521 MB | 13.91 s / 13.90 s / 1090 MB | 1.23 s / 1.23 s / 793 MB |
| whole file | ours | 239 ms / 0.25 s / 538 MB | 6.23 s / 6.22 s / 989 MB | 1.24 s / 1.24 s / 788 MB |
| five columns | pyarrow | 253 ms / 0.25 s / 376 MB | 1.65 s / 1.65 s / 619 MB | 388 ms / 0.39 s / 470 MB |
| five columns | polars | 254 ms / 0.25 s / 375 MB | 1.68 s / 1.68 s / 620 MB | 387 ms / 0.39 s / 470 MB |
| five columns | ours | 277 ms / 0.28 s / 394 MB | 1.64 s / 1.64 s / 622 MB | 389 ms / 0.39 s / 471 MB |
| 1,000 rows | pyarrow | 191 ms / 0.19 s / 400 MB | 3.61 s / 3.61 s / 964 MB | 1.17 s / 1.17 s / 756 MB |
| 1,000 rows | polars | 198 ms / 0.20 s / 399 MB | 13.61 s / 13.60 s / 1098 MB | 1.18 s / 1.18 s / 754 MB |
| 1,000 rows | ours | 225 ms / 0.22 s / 417 MB | 6.73 s / 6.72 s / 1075 MB | 1.16 s / 1.16 s / 751 MB |
| read + pass | pyarrow | 349 ms / 0.35 s / 529 MB | 3.23 s / 3.23 s / 865 MB | 1.37 s / 1.37 s / 792 MB |
| read + pass | polars | 343 ms / 0.35 s / 528 MB | 14.12 s / 14.12 s / 1091 MB | 1.35 s / 1.35 s / 790 MB |
| read + pass | ours | 393 ms / 0.40 s / 548 MB | 6.39 s / 6.39 s / 996 MB | 1.37 s / 1.37 s / 794 MB |
| write, defaults | dta | 159 ms / 0.19 s / 429 MB | 7.44 s / 7.43 s / 892 MB | 1.05 s / 1.06 s / 829 MB |
| write, zstd 3 | dta | 176 ms / 0.21 s / 431 MB | 7.44 s / 7.44 s / 875 MB | 1.08 s / 1.09 s / 828 MB |

### 2015_2017_FemPreg

9,553 rows, 248 columns; .dta 3.0 MB; Parquet pyarrow 0.6 MB, polars 0.5 MB, ours 0.6 MB, duckdb 0.5 MB, ours_zstd 0.5 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 151 ms / 0.15 s / 391 MB | 2.28 s / 2.28 s / 654 MB | 502 ms / 0.50 s / 498 MB |
| whole file | polars | 152 ms / 0.15 s / 390 MB | 2.18 s / 2.18 s / 653 MB | 504 ms / 0.50 s / 499 MB |
| whole file | ours | 158 ms / 0.16 s / 390 MB | 2.38 s / 2.38 s / 653 MB | 502 ms / 0.50 s / 499 MB |
| five columns | pyarrow | 243 ms / 0.24 s / 372 MB | 1.61 s / 1.61 s / 608 MB | 383 ms / 0.38 s / 462 MB |
| five columns | polars | 244 ms / 0.24 s / 372 MB | 1.62 s / 1.62 s / 610 MB | 386 ms / 0.39 s / 462 MB |
| five columns | ours | 245 ms / 0.24 s / 372 MB | 1.60 s / 1.59 s / 607 MB | 383 ms / 0.38 s / 463 MB |
| 1,000 rows | pyarrow | 167 ms / 0.16 s / 371 MB | 2.72 s / 2.72 s / 672 MB | 460 ms / 0.46 s / 484 MB |
| 1,000 rows | polars | 167 ms / 0.16 s / 371 MB | 2.60 s / 2.59 s / 671 MB | 467 ms / 0.47 s / 486 MB |
| 1,000 rows | ours | 167 ms / 0.17 s / 372 MB | 2.84 s / 2.83 s / 674 MB | 464 ms / 0.46 s / 485 MB |
| read + pass | pyarrow | 274 ms / 0.27 s / 390 MB | 2.39 s / 2.39 s / 654 MB | 620 ms / 0.62 s / 500 MB |
| read + pass | polars | 276 ms / 0.27 s / 390 MB | 2.30 s / 2.30 s / 652 MB | 623 ms / 0.62 s / 499 MB |
| read + pass | ours | 273 ms / 0.27 s / 393 MB | 2.49 s / 2.49 s / 656 MB | 619 ms / 0.62 s / 499 MB |
| write, defaults | dta | 118 ms / 0.12 s / 373 MB | 5.38 s / 5.38 s / 760 MB | 573 ms / 0.57 s / 510 MB |
| write, zstd 3 | dta | 132 ms / 0.13 s / 372 MB | 5.36 s / 5.36 s / 761 MB | 575 ms / 0.57 s / 510 MB |

### 2015_2017_FemResp

5,554 rows, 3,024 columns; .dta 21.7 MB; Parquet pyarrow 3.4 MB, polars 3.1 MB, ours 4.3 MB, duckdb 3.2 MB, ours_zstd 3.8 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 214 ms / 0.22 s / 534 MB | 3.14 s / 3.14 s / 907 MB | 1.26 s / 1.26 s / 806 MB |
| whole file | polars | 213 ms / 0.23 s / 534 MB | 15.11 s / 15.10 s / 1253 MB | 1.27 s / 1.27 s / 807 MB |
| whole file | ours | 236 ms / 0.25 s / 555 MB | 11.93 s / 11.93 s / 1108 MB | 1.27 s / 1.27 s / 810 MB |
| five columns | pyarrow | 253 ms / 0.25 s / 376 MB | 1.63 s / 1.63 s / 618 MB | 387 ms / 0.39 s / 468 MB |
| five columns | polars | 257 ms / 0.26 s / 375 MB | 1.67 s / 1.67 s / 619 MB | 385 ms / 0.39 s / 470 MB |
| five columns | ours | 275 ms / 0.27 s / 396 MB | 1.63 s / 1.63 s / 622 MB | 386 ms / 0.39 s / 471 MB |
| 1,000 rows | pyarrow | 195 ms / 0.19 s / 397 MB | 3.67 s / 3.67 s / 1005 MB | 1.19 s / 1.19 s / 767 MB |
| 1,000 rows | polars | 197 ms / 0.20 s / 399 MB | 15.98 s / 15.97 s / 1258 MB | 1.19 s / 1.19 s / 761 MB |
| 1,000 rows | ours | 221 ms / 0.22 s / 419 MB | 12.58 s / 12.58 s / 1109 MB | 1.18 s / 1.18 s / 761 MB |
| read + pass | pyarrow | 352 ms / 0.36 s / 540 MB | 3.30 s / 3.29 s / 902 MB | 1.42 s / 1.42 s / 809 MB |
| read + pass | polars | 354 ms / 0.37 s / 540 MB | 15.90 s / 15.89 s / 1252 MB | 1.40 s / 1.41 s / 810 MB |
| read + pass | ours | 380 ms / 0.39 s / 563 MB | 13.18 s / 13.18 s / 1104 MB | 1.40 s / 1.40 s / 810 MB |
| write, defaults | dta | 179 ms / 0.23 s / 453 MB | 7.43 s / 7.42 s / 906 MB | 1.11 s / 1.12 s / 910 MB |
| write, zstd 3 | dta | 199 ms / 0.25 s / 455 MB | 7.43 s / 7.43 s / 909 MB | 1.11 s / 1.12 s / 910 MB |

### 2015_2017_Male

4,540 rows, 2,945 columns; .dta 17.7 MB; Parquet pyarrow 2.1 MB, polars 2.1 MB, ours 2.8 MB, duckdb 1.9 MB, ours_zstd 2.6 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 206 ms / 0.21 s / 521 MB | 3.11 s / 3.11 s / 886 MB | 1.24 s / 1.24 s / 791 MB |
| whole file | polars | 205 ms / 0.21 s / 523 MB | 13.96 s / 13.96 s / 1090 MB | 1.23 s / 1.23 s / 788 MB |
| whole file | ours | 239 ms / 0.25 s / 541 MB | 6.20 s / 6.19 s / 988 MB | 1.23 s / 1.23 s / 792 MB |
| five columns | pyarrow | 253 ms / 0.25 s / 376 MB | 1.63 s / 1.63 s / 618 MB | 389 ms / 0.39 s / 469 MB |
| five columns | polars | 252 ms / 0.25 s / 376 MB | 1.67 s / 1.67 s / 621 MB | 385 ms / 0.39 s / 468 MB |
| five columns | ours | 275 ms / 0.27 s / 393 MB | 1.63 s / 1.63 s / 622 MB | 382 ms / 0.38 s / 469 MB |
| 1,000 rows | pyarrow | 193 ms / 0.19 s / 400 MB | 3.60 s / 3.59 s / 965 MB | 1.16 s / 1.16 s / 755 MB |
| 1,000 rows | polars | 191 ms / 0.19 s / 399 MB | 13.76 s / 13.75 s / 1094 MB | 1.18 s / 1.18 s / 757 MB |
| 1,000 rows | ours | 224 ms / 0.22 s / 418 MB | 6.78 s / 6.77 s / 1071 MB | 1.16 s / 1.16 s / 754 MB |
| read + pass | pyarrow | 338 ms / 0.34 s / 530 MB | 3.23 s / 3.23 s / 868 MB | 1.36 s / 1.36 s / 791 MB |
| read + pass | polars | 341 ms / 0.35 s / 530 MB | 13.51 s / 13.51 s / 1091 MB | 1.37 s / 1.37 s / 795 MB |
| read + pass | ours | 373 ms / 0.38 s / 549 MB | 6.35 s / 6.34 s / 994 MB | 1.37 s / 1.37 s / 792 MB |
| write, defaults | dta | 164 ms / 0.20 s / 428 MB | 7.41 s / 7.41 s / 880 MB | 1.06 s / 1.06 s / 827 MB |
| write, zstd 3 | dta | 179 ms / 0.22 s / 429 MB | 7.41 s / 7.41 s / 857 MB | 1.08 s / 1.08 s / 829 MB |

### 2017_2019_FemPreg

10,215 rows, 171 columns; .dta 2.2 MB; Parquet pyarrow 0.4 MB, polars 0.4 MB, ours 0.5 MB, duckdb 0.4 MB, ours_zstd 0.4 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 148 ms / 0.15 s / 381 MB | 2.10 s / 2.10 s / 650 MB | 441 ms / 0.44 s / 486 MB |
| whole file | polars | 148 ms / 0.15 s / 381 MB | 2.01 s / 2.01 s / 651 MB | 442 ms / 0.44 s / 487 MB |
| whole file | ours | 149 ms / 0.15 s / 385 MB | 2.22 s / 2.21 s / 650 MB | 442 ms / 0.44 s / 488 MB |
| five columns | pyarrow | 242 ms / 0.24 s / 371 MB | 1.50 s / 1.49 s / 605 MB | 333 ms / 0.33 s / 458 MB |
| five columns | polars | 241 ms / 0.24 s / 371 MB | 1.50 s / 1.50 s / 605 MB | 332 ms / 0.33 s / 459 MB |
| five columns | ours | 242 ms / 0.24 s / 372 MB | 1.61 s / 1.60 s / 607 MB | 333 ms / 0.33 s / 458 MB |
| 1,000 rows | pyarrow | 163 ms / 0.16 s / 370 MB | 2.49 s / 2.48 s / 667 MB | 412 ms / 0.41 s / 477 MB |
| 1,000 rows | polars | 165 ms / 0.16 s / 371 MB | 2.38 s / 2.38 s / 667 MB | 419 ms / 0.42 s / 477 MB |
| 1,000 rows | ours | 164 ms / 0.16 s / 371 MB | 2.61 s / 2.61 s / 669 MB | 413 ms / 0.41 s / 477 MB |
| read + pass | pyarrow | 267 ms / 0.26 s / 383 MB | 2.23 s / 2.23 s / 649 MB | 556 ms / 0.56 s / 488 MB |
| read + pass | polars | 268 ms / 0.27 s / 385 MB | 2.13 s / 2.13 s / 649 MB | 557 ms / 0.56 s / 487 MB |
| read + pass | ours | 268 ms / 0.27 s / 385 MB | 2.33 s / 2.33 s / 652 MB | 552 ms / 0.55 s / 487 MB |
| write, defaults | dta | 115 ms / 0.11 s / 373 MB | 4.90 s / 4.90 s / 747 MB | 554 ms / 0.55 s / 496 MB |
| write, zstd 3 | dta | 128 ms / 0.13 s / 373 MB | 4.91 s / 4.90 s / 749 MB | 556 ms / 0.55 s / 495 MB |

### 2017_2019_FemResp

6,141 rows, 2,609 columns; .dta 20.2 MB; Parquet pyarrow 3.5 MB, polars 3.1 MB, ours 4.3 MB, duckdb 3.3 MB, ours_zstd 3.8 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 208 ms / 0.22 s / 518 MB | 3.00 s / 2.99 s / 896 MB | 1.11 s / 1.11 s / 775 MB |
| whole file | polars | 211 ms / 0.22 s / 520 MB | 11.18 s / 11.18 s / 1143 MB | 1.11 s / 1.12 s / 772 MB |
| whole file | ours | 233 ms / 0.25 s / 539 MB | 10.59 s / 10.59 s / 1012 MB | 1.10 s / 1.10 s / 776 MB |
| five columns | pyarrow | 252 ms / 0.25 s / 374 MB | 1.63 s / 1.63 s / 617 MB | 386 ms / 0.39 s / 469 MB |
| five columns | polars | 258 ms / 0.26 s / 375 MB | 1.67 s / 1.66 s / 620 MB | 385 ms / 0.39 s / 469 MB |
| five columns | ours | 275 ms / 0.27 s / 394 MB | 1.62 s / 1.62 s / 621 MB | 383 ms / 0.38 s / 469 MB |
| 1,000 rows | pyarrow | 190 ms / 0.19 s / 395 MB | 3.42 s / 3.41 s / 983 MB | 1.05 s / 1.05 s / 730 MB |
| 1,000 rows | polars | 193 ms / 0.19 s / 395 MB | 11.72 s / 11.72 s / 1101 MB | 1.04 s / 1.04 s / 729 MB |
| 1,000 rows | ours | 212 ms / 0.21 s / 415 MB | 11.19 s / 11.18 s / 1025 MB | 1.05 s / 1.05 s / 730 MB |
| read + pass | pyarrow | 347 ms / 0.36 s / 526 MB | 3.11 s / 3.11 s / 898 MB | 1.23 s / 1.23 s / 774 MB |
| read + pass | polars | 349 ms / 0.36 s / 525 MB | 11.72 s / 11.71 s / 1143 MB | 1.24 s / 1.24 s / 773 MB |
| read + pass | ours | 366 ms / 0.38 s / 546 MB | 10.47 s / 10.46 s / 1002 MB | 1.23 s / 1.23 s / 773 MB |
| write, defaults | dta | 185 ms / 0.24 s / 439 MB | 6.70 s / 6.70 s / 873 MB | 1.00 s / 1.01 s / 854 MB |
| write, zstd 3 | dta | 196 ms / 0.25 s / 440 MB | 6.74 s / 6.74 s / 879 MB | 1.02 s / 1.02 s / 853 MB |

### 2017_2019_Male

5,206 rows, 3,009 columns; .dta 20.1 MB; Parquet pyarrow 2.2 MB, polars 2.2 MB, ours 2.9 MB, duckdb 2.0 MB, ours_zstd 2.7 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 212 ms / 0.22 s / 549 MB | 2.99 s / 2.99 s / 897 MB | 1.23 s / 1.23 s / 807 MB |
| whole file | polars | 211 ms / 0.22 s / 548 MB | 14.18 s / 14.18 s / 1251 MB | 1.21 s / 1.22 s / 806 MB |
| whole file | ours | 247 ms / 0.25 s / 568 MB | 6.11 s / 6.11 s / 1012 MB | 1.22 s / 1.22 s / 810 MB |
| five columns | pyarrow | 256 ms / 0.25 s / 375 MB | 1.63 s / 1.63 s / 617 MB | 386 ms / 0.39 s / 469 MB |
| five columns | polars | 253 ms / 0.25 s / 376 MB | 1.66 s / 1.66 s / 620 MB | 383 ms / 0.38 s / 470 MB |
| five columns | ours | 274 ms / 0.27 s / 393 MB | 1.62 s / 1.62 s / 621 MB | 384 ms / 0.38 s / 471 MB |
| 1,000 rows | pyarrow | 200 ms / 0.20 s / 400 MB | 3.44 s / 3.44 s / 990 MB | 1.16 s / 1.16 s / 761 MB |
| 1,000 rows | polars | 195 ms / 0.19 s / 401 MB | 14.32 s / 14.31 s / 1254 MB | 1.14 s / 1.14 s / 755 MB |
| 1,000 rows | ours | 213 ms / 0.21 s / 419 MB | 6.53 s / 6.53 s / 1119 MB | 1.16 s / 1.16 s / 763 MB |
| read + pass | pyarrow | 347 ms / 0.36 s / 556 MB | 3.13 s / 3.13 s / 906 MB | 1.35 s / 1.35 s / 806 MB |
| read + pass | polars | 348 ms / 0.36 s / 555 MB | 15.08 s / 15.08 s / 1253 MB | 1.34 s / 1.34 s / 805 MB |
| read + pass | ours | 373 ms / 0.38 s / 576 MB | 6.20 s / 6.20 s / 1016 MB | 1.37 s / 1.37 s / 802 MB |
| write, defaults | dta | 228 ms / 0.25 s / 449 MB | 7.07 s / 7.06 s / 904 MB | 1.08 s / 1.09 s / 914 MB |
| write, zstd 3 | dta | 200 ms / 0.25 s / 440 MB | 7.07 s / 7.07 s / 904 MB | 1.10 s / 1.10 s / 914 MB |

### 2022_2023_FemPreg

8,247 rows, 111 columns; .dta 1.2 MB; Parquet pyarrow 0.3 MB, polars 0.3 MB, ours 0.3 MB, duckdb 0.3 MB, ours_zstd 0.3 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 148 ms / 0.15 s / 376 MB | 2.08 s / 2.07 s / 640 MB | 426 ms / 0.43 s / 475 MB |
| whole file | polars | 145 ms / 0.14 s / 377 MB | 2.00 s / 2.00 s / 641 MB | 429 ms / 0.43 s / 474 MB |
| whole file | ours | 145 ms / 0.14 s / 376 MB | 2.19 s / 2.18 s / 643 MB | 427 ms / 0.43 s / 476 MB |
| five columns | pyarrow | 239 ms / 0.24 s / 371 MB | 1.50 s / 1.50 s / 604 MB | 332 ms / 0.33 s / 459 MB |
| five columns | polars | 296 ms / 0.26 s / 371 MB | 1.51 s / 1.50 s / 605 MB | 332 ms / 0.33 s / 459 MB |
| five columns | ours | 311 ms / 0.27 s / 372 MB | 1.48 s / 1.47 s / 606 MB | 332 ms / 0.33 s / 459 MB |
| 1,000 rows | pyarrow | 169 ms / 0.17 s / 370 MB | 2.45 s / 2.45 s / 653 MB | 397 ms / 0.40 s / 472 MB |
| 1,000 rows | polars | 165 ms / 0.16 s / 370 MB | 2.35 s / 2.35 s / 653 MB | 401 ms / 0.40 s / 472 MB |
| 1,000 rows | ours | 163 ms / 0.16 s / 370 MB | 2.59 s / 2.58 s / 658 MB | 400 ms / 0.40 s / 473 MB |
| read + pass | pyarrow | 265 ms / 0.26 s / 377 MB | 2.19 s / 2.19 s / 641 MB | 544 ms / 0.54 s / 478 MB |
| read + pass | polars | 265 ms / 0.26 s / 379 MB | 2.10 s / 2.09 s / 641 MB | 542 ms / 0.54 s / 476 MB |
| read + pass | ours | 278 ms / 0.28 s / 378 MB | 2.29 s / 2.29 s / 643 MB | 542 ms / 0.54 s / 476 MB |
| write, defaults | dta | 118 ms / 0.12 s / 373 MB | 4.84 s / 4.84 s / 713 MB | 540 ms / 0.54 s / 484 MB |
| write, zstd 3 | dta | 129 ms / 0.13 s / 372 MB | 4.84 s / 4.84 s / 715 MB | 547 ms / 0.54 s / 483 MB |

### 2022_2023_FemResp

5,586 rows, 1,912 columns; .dta 13.3 MB; Parquet pyarrow 2.6 MB, polars 2.3 MB, ours 2.7 MB, duckdb 2.5 MB, ours_zstd 2.4 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 202 ms / 0.21 s / 484 MB | 3.14 s / 3.14 s / 814 MB | 949 ms / 0.95 s / 674 MB |
| whole file | polars | 198 ms / 0.21 s / 485 MB | 3.14 s / 3.13 s / 801 MB | 950 ms / 0.95 s / 674 MB |
| whole file | ours | 202 ms / 0.21 s / 485 MB | 3.08 s / 3.08 s / 801 MB | 951 ms / 0.95 s / 675 MB |
| five columns | pyarrow | 249 ms / 0.25 s / 375 MB | 1.52 s / 1.52 s / 610 MB | 339 ms / 0.34 s / 462 MB |
| five columns | polars | 245 ms / 0.24 s / 374 MB | 1.66 s / 1.66 s / 619 MB | 336 ms / 0.34 s / 463 MB |
| five columns | ours | 251 ms / 0.25 s / 375 MB | 1.61 s / 1.61 s / 614 MB | 336 ms / 0.34 s / 463 MB |
| 1,000 rows | pyarrow | 196 ms / 0.19 s / 388 MB | 3.65 s / 3.64 s / 859 MB | 875 ms / 0.88 s / 650 MB |
| 1,000 rows | polars | 212 ms / 0.20 s / 388 MB | 3.65 s / 3.65 s / 857 MB | 881 ms / 0.88 s / 650 MB |
| 1,000 rows | ours | 191 ms / 0.19 s / 390 MB | 3.57 s / 3.57 s / 854 MB | 879 ms / 0.88 s / 645 MB |
| read + pass | pyarrow | 341 ms / 0.35 s / 488 MB | 3.28 s / 3.27 s / 812 MB | 1.07 s / 1.07 s / 674 MB |
| read + pass | polars | 363 ms / 0.37 s / 488 MB | 3.26 s / 3.25 s / 800 MB | 1.07 s / 1.07 s / 674 MB |
| read + pass | ours | 363 ms / 0.37 s / 489 MB | 3.20 s / 3.20 s / 808 MB | 1.08 s / 1.08 s / 676 MB |
| write, defaults | dta | 185 ms / 0.24 s / 396 MB | 6.72 s / 6.72 s / 868 MB | 857 ms / 0.86 s / 730 MB |
| write, zstd 3 | dta | 220 ms / 0.27 s / 398 MB | 6.73 s / 6.73 s / 871 MB | 867 ms / 0.87 s / 731 MB |

### 2022_2023_MaleResp

4,371 rows, 1,157 columns; .dta 6.3 MB; Parquet pyarrow 1.2 MB, polars 1.1 MB, ours 1.3 MB, duckdb 1.1 MB, ours_zstd 1.1 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 172 ms / 0.17 s / 428 MB | 2.70 s / 2.70 s / 749 MB | 726 ms / 0.73 s / 592 MB |
| whole file | polars | 171 ms / 0.17 s / 429 MB | 2.71 s / 2.71 s / 744 MB | 728 ms / 0.73 s / 592 MB |
| whole file | ours | 172 ms / 0.18 s / 429 MB | 2.63 s / 2.63 s / 724 MB | 732 ms / 0.73 s / 591 MB |
| five columns | pyarrow | 252 ms / 0.25 s / 373 MB | 1.52 s / 1.52 s / 610 MB | 335 ms / 0.33 s / 460 MB |
| five columns | polars | 256 ms / 0.25 s / 373 MB | 1.65 s / 1.65 s / 614 MB | 335 ms / 0.33 s / 462 MB |
| five columns | ours | 259 ms / 0.26 s / 374 MB | 1.61 s / 1.60 s / 608 MB | 337 ms / 0.34 s / 460 MB |
| 1,000 rows | pyarrow | 185 ms / 0.18 s / 381 MB | 3.17 s / 3.17 s / 776 MB | 685 ms / 0.69 s / 580 MB |
| 1,000 rows | polars | 184 ms / 0.18 s / 381 MB | 3.21 s / 3.21 s / 792 MB | 693 ms / 0.69 s / 579 MB |
| 1,000 rows | ours | 185 ms / 0.18 s / 382 MB | 3.11 s / 3.11 s / 766 MB | 688 ms / 0.69 s / 581 MB |
| read + pass | pyarrow | 319 ms / 0.32 s / 431 MB | 2.85 s / 2.85 s / 747 MB | 867 ms / 0.87 s / 595 MB |
| read + pass | polars | 319 ms / 0.32 s / 430 MB | 2.85 s / 2.85 s / 745 MB | 858 ms / 0.86 s / 592 MB |
| read + pass | ours | 336 ms / 0.33 s / 431 MB | 2.78 s / 2.78 s / 724 MB | 859 ms / 0.86 s / 594 MB |
| write, defaults | dta | 144 ms / 0.17 s / 378 MB | 5.55 s / 5.54 s / 813 MB | 684 ms / 0.68 s / 605 MB |
| write, zstd 3 | dta | 167 ms / 0.20 s / 381 MB | 5.52 s / 5.52 s / 811 MB | 683 ms / 0.68 s / 605 MB |

### Senegal 2019 wm

8,649 rows, 4,997 columns; .dta 49.1 MB; Parquet pyarrow 4.2 MB, polars 4.0 MB, ours 4.8 MB, duckdb 3.7 MB, ours_zstd 4.3 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 323 ms / 0.35 s / 907 MB | 2.31 s / 2.30 s / 894 MB | 1.48 s / 1.48 s / 1256 MB |
| whole file | polars | 333 ms / 0.35 s / 906 MB | 2.36 s / 2.36 s / 896 MB | 1.50 s / 1.50 s / 1257 MB |
| whole file | ours | 346 ms / 0.37 s / 932 MB | 16.61 s / 16.60 s / 1435 MB | 1.47 s / 1.47 s / 1258 MB |
| five columns | pyarrow | 281 ms / 0.28 s / 379 MB | 1.63 s / 1.63 s / 618 MB | 369 ms / 0.37 s / 477 MB |
| five columns | polars | 275 ms / 0.27 s / 380 MB | 1.57 s / 1.57 s / 618 MB | 372 ms / 0.37 s / 475 MB |
| five columns | ours | 297 ms / 0.29 s / 398 MB | 1.45 s / 1.45 s / 619 MB | 373 ms / 0.37 s / 477 MB |
| 1,000 rows | pyarrow | 211 ms / 0.22 s / 429 MB | 2.81 s / 2.81 s / 1203 MB | 1.32 s / 1.32 s / 967 MB |
| 1,000 rows | polars | 206 ms / 0.21 s / 430 MB | 2.90 s / 2.90 s / 1178 MB | 1.36 s / 1.36 s / 967 MB |
| 1,000 rows | ours | 245 ms / 0.25 s / 449 MB | 17.00 s / 17.00 s / 1620 MB | 1.34 s / 1.34 s / 969 MB |
| read + pass | pyarrow | 481 ms / 0.51 s / 924 MB | 2.50 s / 2.50 s / 895 MB | 1.65 s / 1.65 s / 1257 MB |
| read + pass | polars | 496 ms / 0.52 s / 925 MB | 2.55 s / 2.55 s / 897 MB | 1.65 s / 1.65 s / 1256 MB |
| read + pass | ours | 521 ms / 0.55 s / 946 MB | 16.68 s / 16.68 s / 1433 MB | 1.65 s / 1.65 s / 1257 MB |
| write, defaults | dta | 423 ms / 0.51 s / 600 MB | 9.48 s / 9.48 s / 1124 MB | 1.90 s / 1.90 s / 1276 MB |
| write, zstd 3 | dta | 401 ms / 0.53 s / 602 MB | 9.48 s / 9.47 s / 1138 MB | 1.90 s / 1.91 s / 1272 MB |

### Senegal 2019 bh

21,562 rows, 1,191 columns; .dta 28.9 MB; Parquet pyarrow 4.0 MB, polars 3.1 MB, ours 4.0 MB, duckdb 3.7 MB, ours_zstd 3.1 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 243 ms / 0.26 s / 629 MB | 2.71 s / 2.70 s / 848 MB | 798 ms / 0.80 s / 858 MB |
| whole file | polars | 253 ms / 0.27 s / 627 MB | 2.71 s / 2.70 s / 845 MB | 796 ms / 0.80 s / 853 MB |
| whole file | ours | 247 ms / 0.26 s / 630 MB | 2.68 s / 2.68 s / 826 MB | 798 ms / 0.80 s / 856 MB |
| five columns | pyarrow | 262 ms / 0.26 s / 375 MB | 1.58 s / 1.58 s / 608 MB | 366 ms / 0.37 s / 465 MB |
| five columns | polars | 250 ms / 0.25 s / 374 MB | 1.58 s / 1.58 s / 608 MB | 365 ms / 0.37 s / 466 MB |
| five columns | ours | 264 ms / 0.26 s / 376 MB | 1.56 s / 1.56 s / 608 MB | 365 ms / 0.37 s / 466 MB |
| 1,000 rows | pyarrow | 182 ms / 0.18 s / 381 MB | 3.12 s / 3.12 s / 990 MB | 667 ms / 0.67 s / 587 MB |
| 1,000 rows | polars | 185 ms / 0.18 s / 381 MB | 3.13 s / 3.13 s / 996 MB | 663 ms / 0.66 s / 587 MB |
| 1,000 rows | ours | 184 ms / 0.18 s / 384 MB | 3.18 s / 3.18 s / 967 MB | 666 ms / 0.67 s / 587 MB |
| read + pass | pyarrow | 388 ms / 0.41 s / 629 MB | 2.85 s / 2.85 s / 851 MB | 945 ms / 0.95 s / 856 MB |
| read + pass | polars | 390 ms / 0.41 s / 630 MB | 2.86 s / 2.85 s / 850 MB | 943 ms / 0.94 s / 857 MB |
| read + pass | ours | 412 ms / 0.42 s / 634 MB | 2.86 s / 2.86 s / 828 MB | 935 ms / 0.94 s / 857 MB |
| write, defaults | dta | 290 ms / 0.35 s / 448 MB | 6.16 s / 6.16 s / 905 MB | 846 ms / 0.85 s / 883 MB |
| write, zstd 3 | dta | 250 ms / 0.32 s / 450 MB | 6.17 s / 6.17 s / 911 MB | 874 ms / 0.87 s / 881 MB |

### Turkey 2013 wm

9,746 rows, 4,668 columns; .dta 52.6 MB; Parquet pyarrow 4.3 MB, polars 4.0 MB, ours 4.9 MB, duckdb 4.0 MB, ours_zstd 4.3 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 289 ms / 0.31 s / 879 MB | 2.33 s / 2.33 s / 876 MB | 1.42 s / 1.42 s / 1215 MB |
| whole file | polars | 290 ms / 0.32 s / 877 MB | 2.34 s / 2.34 s / 879 MB | 1.43 s / 1.43 s / 1213 MB |
| whole file | ours | 323 ms / 0.35 s / 903 MB | 16.82 s / 16.82 s / 1410 MB | 1.41 s / 1.42 s / 1219 MB |
| five columns | pyarrow | 262 ms / 0.26 s / 379 MB | 1.63 s / 1.63 s / 616 MB | 373 ms / 0.37 s / 476 MB |
| five columns | polars | 266 ms / 0.26 s / 379 MB | 1.57 s / 1.57 s / 616 MB | 377 ms / 0.38 s / 475 MB |
| five columns | ours | 287 ms / 0.29 s / 398 MB | 1.65 s / 1.65 s / 622 MB | 371 ms / 0.37 s / 476 MB |
| 1,000 rows | pyarrow | 206 ms / 0.21 s / 425 MB | 2.80 s / 2.79 s / 1168 MB | 1.25 s / 1.25 s / 938 MB |
| 1,000 rows | polars | 206 ms / 0.21 s / 425 MB | 2.88 s / 2.88 s / 1168 MB | 1.26 s / 1.26 s / 936 MB |
| 1,000 rows | ours | 238 ms / 0.24 s / 445 MB | 17.90 s / 17.90 s / 1442 MB | 1.25 s / 1.25 s / 938 MB |
| read + pass | pyarrow | 476 ms / 0.50 s / 894 MB | 2.50 s / 2.50 s / 878 MB | 1.58 s / 1.58 s / 1213 MB |
| read + pass | polars | 479 ms / 0.51 s / 891 MB | 2.55 s / 2.55 s / 879 MB | 1.60 s / 1.60 s / 1213 MB |
| read + pass | ours | 518 ms / 0.55 s / 916 MB | 16.26 s / 16.22 s / 1412 MB | 1.62 s / 1.62 s / 1214 MB |
| write, defaults | dta | 336 ms / 0.46 s / 585 MB | 9.12 s / 9.11 s / 1140 MB | 1.80 s / 1.80 s / 1233 MB |
| write, zstd 3 | dta | 351 ms / 0.48 s / 588 MB | 9.12 s / 9.11 s / 1146 MB | 1.82 s / 1.83 s / 1232 MB |

### Turkey 2013 bh

17,871 rows, 1,173 columns; .dta 23.3 MB; Parquet pyarrow 3.3 MB, polars 2.7 MB, ours 3.5 MB, duckdb 3.1 MB, ours_zstd 2.7 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 216 ms / 0.23 s / 592 MB | 2.67 s / 2.67 s / 837 MB | 784 ms / 0.78 s / 791 MB |
| whole file | polars | 219 ms / 0.23 s / 594 MB | 2.70 s / 2.70 s / 844 MB | 775 ms / 0.78 s / 793 MB |
| whole file | ours | 234 ms / 0.25 s / 594 MB | 2.68 s / 2.68 s / 812 MB | 782 ms / 0.78 s / 791 MB |
| five columns | pyarrow | 258 ms / 0.26 s / 373 MB | 1.64 s / 1.64 s / 613 MB | 375 ms / 0.37 s / 468 MB |
| five columns | polars | 271 ms / 0.27 s / 374 MB | 1.64 s / 1.64 s / 613 MB | 381 ms / 0.38 s / 466 MB |
| five columns | ours | 263 ms / 0.26 s / 376 MB | 1.73 s / 1.73 s / 615 MB | 368 ms / 0.37 s / 467 MB |
| 1,000 rows | pyarrow | 182 ms / 0.18 s / 380 MB | 3.10 s / 3.10 s / 952 MB | 665 ms / 0.66 s / 587 MB |
| 1,000 rows | polars | 185 ms / 0.18 s / 380 MB | 3.12 s / 3.12 s / 956 MB | 674 ms / 0.67 s / 586 MB |
| 1,000 rows | ours | 191 ms / 0.19 s / 385 MB | 3.08 s / 3.08 s / 931 MB | 656 ms / 0.66 s / 587 MB |
| read + pass | pyarrow | 392 ms / 0.40 s / 593 MB | 2.80 s / 2.80 s / 838 MB | 902 ms / 0.90 s / 791 MB |
| read + pass | polars | 385 ms / 0.39 s / 594 MB | 2.83 s / 2.82 s / 837 MB | 923 ms / 0.92 s / 794 MB |
| read + pass | ours | 370 ms / 0.38 s / 598 MB | 2.80 s / 2.80 s / 808 MB | 911 ms / 0.91 s / 793 MB |
| write, defaults | dta | 228 ms / 0.28 s / 436 MB | 6.21 s / 6.20 s / 896 MB | 817 ms / 0.82 s / 812 MB |
| write, zstd 3 | dta | 254 ms / 0.32 s / 440 MB | 6.18 s / 6.18 s / 902 MB | 820 ms / 0.82 s / 811 MB |

### Tajikistan 2017 wm

10,718 rows, 5,160 columns; .dta 63.8 MB; Parquet pyarrow 5.7 MB, polars 5.3 MB, ours 6.4 MB, duckdb 5.3 MB, ours_zstd 5.6 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 339 ms / 0.37 s / 1010 MB | 2.41 s / 2.41 s / 991 MB | 1.60 s / 1.60 s / 1456 MB |
| whole file | polars | 337 ms / 0.38 s / 1012 MB | 2.47 s / 2.46 s / 992 MB | 1.61 s / 1.61 s / 1454 MB |
| whole file | ours | 378 ms / 0.41 s / 1036 MB | 18.39 s / 18.39 s / 1515 MB | 1.59 s / 1.60 s / 1459 MB |
| five columns | pyarrow | 276 ms / 0.27 s / 380 MB | 1.65 s / 1.65 s / 619 MB | 376 ms / 0.38 s / 477 MB |
| five columns | polars | 277 ms / 0.27 s / 379 MB | 1.58 s / 1.58 s / 618 MB | 381 ms / 0.38 s / 477 MB |
| five columns | ours | 302 ms / 0.30 s / 400 MB | 1.66 s / 1.66 s / 622 MB | 375 ms / 0.38 s / 477 MB |
| 1,000 rows | pyarrow | 218 ms / 0.23 s / 432 MB | 2.93 s / 2.92 s / 1384 MB | 1.39 s / 1.39 s / 1012 MB |
| 1,000 rows | polars | 219 ms / 0.23 s / 431 MB | 2.99 s / 2.99 s / 1386 MB | 1.38 s / 1.39 s / 1013 MB |
| 1,000 rows | ours | 261 ms / 0.26 s / 453 MB | 18.84 s / 18.83 s / 1821 MB | 1.39 s / 1.39 s / 1013 MB |
| read + pass | pyarrow | 610 ms / 0.58 s / 1028 MB | 2.60 s / 2.60 s / 989 MB | 1.78 s / 1.78 s / 1455 MB |
| read + pass | polars | 792 ms / 0.58 s / 1026 MB | 2.64 s / 2.64 s / 992 MB | 1.79 s / 1.79 s / 1454 MB |
| read + pass | ours | 535 ms / 0.57 s / 1054 MB | 18.26 s / 18.26 s / 1507 MB | 1.80 s / 1.80 s / 1456 MB |
| write, defaults | dta | 324 ms / 0.45 s / 604 MB | 9.82 s / 9.82 s / 1192 MB | 2.07 s / 2.07 s / 1493 MB |
| write, zstd 3 | dta | 334 ms / 0.45 s / 604 MB | 9.76 s / 9.76 s / 1188 MB | 2.09 s / 2.10 s / 1477 MB |

### Tajikistan 2017 bh

21,985 rows, 1,146 columns; .dta 29.4 MB; Parquet pyarrow 4.8 MB, polars 3.8 MB, ours 4.8 MB, duckdb 4.4 MB, ours_zstd 3.8 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 224 ms / 0.24 s / 606 MB | 2.70 s / 2.70 s / 845 MB | 781 ms / 0.78 s / 833 MB |
| whole file | polars | 228 ms / 0.25 s / 606 MB | 2.70 s / 2.70 s / 850 MB | 777 ms / 0.78 s / 832 MB |
| whole file | ours | 236 ms / 0.25 s / 609 MB | 2.68 s / 2.68 s / 821 MB | 780 ms / 0.78 s / 831 MB |
| five columns | pyarrow | 250 ms / 0.25 s / 373 MB | 1.60 s / 1.60 s / 607 MB | 371 ms / 0.37 s / 466 MB |
| five columns | polars | 266 ms / 0.26 s / 373 MB | 1.63 s / 1.63 s / 611 MB | 373 ms / 0.37 s / 467 MB |
| five columns | ours | 311 ms / 0.28 s / 376 MB | 1.70 s / 1.69 s / 612 MB | 369 ms / 0.37 s / 467 MB |
| 1,000 rows | pyarrow | 210 ms / 0.19 s / 380 MB | 3.14 s / 3.14 s / 977 MB | 663 ms / 0.66 s / 573 MB |
| 1,000 rows | polars | 309 ms / 0.19 s / 380 MB | 3.13 s / 3.12 s / 984 MB | 658 ms / 0.66 s / 573 MB |
| 1,000 rows | ours | 190 ms / 0.19 s / 383 MB | 3.18 s / 3.18 s / 954 MB | 656 ms / 0.66 s / 576 MB |
| read + pass | pyarrow | 374 ms / 0.39 s / 607 MB | 2.85 s / 2.85 s / 844 MB | 923 ms / 0.92 s / 832 MB |
| read + pass | polars | 375 ms / 0.39 s / 608 MB | 2.86 s / 2.85 s / 859 MB | 923 ms / 0.92 s / 831 MB |
| read + pass | ours | 382 ms / 0.40 s / 613 MB | 2.84 s / 2.84 s / 826 MB | 929 ms / 0.93 s / 832 MB |
| write, defaults | dta | 236 ms / 0.29 s / 443 MB | 6.19 s / 6.18 s / 904 MB | 861 ms / 0.86 s / 881 MB |
| write, zstd 3 | dta | 254 ms / 0.32 s / 446 MB | 6.26 s / 6.25 s / 905 MB | 865 ms / 0.86 s / 881 MB |

### Myanmar 2016 wm

12,885 rows, 4,993 columns; .dta 72.0 MB; Parquet pyarrow 5.3 MB, polars 4.9 MB, ours 5.9 MB, duckdb 4.9 MB, ours_zstd 5.1 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 332 ms / 0.37 s / 1086 MB | 2.44 s / 2.44 s / 982 MB | 1.61 s / 1.61 s / 1517 MB |
| whole file | polars | 344 ms / 0.38 s / 1089 MB | 2.52 s / 2.51 s / 986 MB | 1.63 s / 1.63 s / 1514 MB |
| whole file | ours | 379 ms / 0.41 s / 1108 MB | 9.19 s / 9.18 s / 1524 MB | 1.58 s / 1.58 s / 1521 MB |
| five columns | pyarrow | 270 ms / 0.27 s / 381 MB | 1.65 s / 1.65 s / 617 MB | 375 ms / 0.38 s / 476 MB |
| five columns | polars | 262 ms / 0.26 s / 379 MB | 1.58 s / 1.57 s / 620 MB | 379 ms / 0.38 s / 477 MB |
| five columns | ours | 286 ms / 0.28 s / 398 MB | 1.70 s / 1.70 s / 630 MB | 376 ms / 0.38 s / 479 MB |
| 1,000 rows | pyarrow | 208 ms / 0.21 s / 429 MB | 2.88 s / 2.88 s / 1364 MB | 1.38 s / 1.38 s / 970 MB |
| 1,000 rows | polars | 213 ms / 0.22 s / 429 MB | 3.06 s / 3.06 s / 1341 MB | 1.38 s / 1.38 s / 969 MB |
| 1,000 rows | ours | 246 ms / 0.25 s / 450 MB | 9.74 s / 9.73 s / 1534 MB | 1.33 s / 1.33 s / 968 MB |
| read + pass | pyarrow | 516 ms / 0.55 s / 1103 MB | 2.62 s / 2.62 s / 983 MB | 1.81 s / 1.81 s / 1514 MB |
| read + pass | polars | 538 ms / 0.58 s / 1100 MB | 2.66 s / 2.66 s / 981 MB | 1.78 s / 1.78 s / 1516 MB |
| read + pass | ours | 586 ms / 0.62 s / 1123 MB | 9.33 s / 9.32 s / 1517 MB | 1.78 s / 1.78 s / 1516 MB |
| write, defaults | dta | 380 ms / 0.55 s / 601 MB | 9.70 s / 9.69 s / 1229 MB | 2.10 s / 2.10 s / 1495 MB |
| write, zstd 3 | dta | 631 ms / 0.60 s / 609 MB | 9.61 s / 9.60 s / 1211 MB | 2.12 s / 2.13 s / 1493 MB |

### Myanmar 2016 bh

22,989 rows, 1,184 columns; .dta 30.7 MB; Parquet pyarrow 4.2 MB, polars 3.3 MB, ours 4.3 MB, duckdb 3.9 MB, ours_zstd 3.4 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 244 ms / 0.26 s / 638 MB | 2.91 s / 2.83 s / 874 MB | 814 ms / 0.81 s / 891 MB |
| whole file | polars | 243 ms / 0.26 s / 639 MB | 2.70 s / 2.70 s / 881 MB | 801 ms / 0.80 s / 889 MB |
| whole file | ours | 257 ms / 0.27 s / 640 MB | 2.69 s / 2.69 s / 846 MB | 811 ms / 0.81 s / 890 MB |
| five columns | pyarrow | 270 ms / 0.27 s / 373 MB | 1.60 s / 1.60 s / 608 MB | 371 ms / 0.37 s / 467 MB |
| five columns | polars | 251 ms / 0.25 s / 374 MB | 1.60 s / 1.60 s / 609 MB | 377 ms / 0.38 s / 467 MB |
| five columns | ours | 254 ms / 0.25 s / 376 MB | 1.58 s / 1.58 s / 611 MB | 370 ms / 0.37 s / 467 MB |
| 1,000 rows | pyarrow | 175 ms / 0.17 s / 380 MB | 3.15 s / 3.15 s / 1034 MB | 680 ms / 0.68 s / 590 MB |
| 1,000 rows | polars | 180 ms / 0.18 s / 381 MB | 3.17 s / 3.17 s / 1040 MB | 678 ms / 0.68 s / 592 MB |
| 1,000 rows | ours | 185 ms / 0.18 s / 383 MB | 3.16 s / 3.15 s / 1012 MB | 667 ms / 0.67 s / 592 MB |
| read + pass | pyarrow | 375 ms / 0.39 s / 639 MB | 2.86 s / 2.86 s / 874 MB | 935 ms / 0.94 s / 892 MB |
| read + pass | polars | 381 ms / 0.40 s / 640 MB | 2.85 s / 2.85 s / 878 MB | 948 ms / 0.95 s / 891 MB |
| read + pass | ours | 395 ms / 0.41 s / 644 MB | 2.86 s / 2.86 s / 851 MB | 950 ms / 0.95 s / 892 MB |
| write, defaults | dta | 244 ms / 0.31 s / 448 MB | 6.19 s / 6.19 s / 907 MB | 859 ms / 0.86 s / 882 MB |
| write, zstd 3 | dta | 293 ms / 0.38 s / 451 MB | 6.24 s / 6.24 s / 912 MB | 901 ms / 0.90 s / 885 MB |

### Dominican Republic 2013 wm

9,372 rows, 3,854 columns; .dta 39.7 MB; Parquet pyarrow 3.8 MB, polars 3.5 MB, ours 4.3 MB, duckdb 3.5 MB, ours_zstd 3.7 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 297 ms / 0.31 s / 791 MB | 3.21 s / 3.21 s / 1108 MB | 1.53 s / 1.53 s / 1066 MB |
| whole file | polars | 288 ms / 0.30 s / 787 MB | 20.34 s / 20.34 s / 1439 MB | 1.54 s / 1.54 s / 1066 MB |
| whole file | ours | 315 ms / 0.33 s / 811 MB | 7.11 s / 7.11 s / 1211 MB | 1.53 s / 1.53 s / 1065 MB |
| five columns | pyarrow | 265 ms / 0.26 s / 377 MB | 1.62 s / 1.62 s / 617 MB | 381 ms / 0.38 s / 472 MB |
| five columns | polars | 267 ms / 0.27 s / 377 MB | 1.57 s / 1.57 s / 615 MB | 370 ms / 0.37 s / 473 MB |
| five columns | ours | 287 ms / 0.28 s / 395 MB | 1.66 s / 1.66 s / 625 MB | 370 ms / 0.37 s / 473 MB |
| 1,000 rows | pyarrow | 204 ms / 0.20 s / 410 MB | 3.65 s / 3.65 s / 1149 MB | 1.39 s / 1.39 s / 840 MB |
| 1,000 rows | polars | 205 ms / 0.20 s / 410 MB | 21.67 s / 21.64 s / 1585 MB | 1.38 s / 1.38 s / 837 MB |
| 1,000 rows | ours | 230 ms / 0.23 s / 428 MB | 7.73 s / 7.73 s / 1219 MB | 1.38 s / 1.38 s / 842 MB |
| read + pass | pyarrow | 427 ms / 0.45 s / 799 MB | 3.36 s / 3.36 s / 1103 MB | 1.70 s / 1.70 s / 1073 MB |
| read + pass | polars | 432 ms / 0.46 s / 797 MB | 21.15 s / 20.96 s / 1504 MB | 1.71 s / 1.71 s / 1070 MB |
| read + pass | ours | 466 ms / 0.49 s / 818 MB | 7.50 s / 7.40 s / 1210 MB | 1.73 s / 1.73 s / 1069 MB |
| write, defaults | dta | 338 ms / 0.41 s / 512 MB | 8.25 s / 8.24 s / 1044 MB | 1.52 s / 1.52 s / 1111 MB |
| write, zstd 3 | dta | 287 ms / 0.37 s / 524 MB | 8.22 s / 8.20 s / 1025 MB | 1.49 s / 1.49 s / 1111 MB |

### Dominican Republic 2013 bh

18,167 rows, 1,078 columns; .dta 22.2 MB; Parquet pyarrow 3.5 MB, polars 2.8 MB, ours 3.6 MB, duckdb 3.3 MB, ours_zstd 2.9 MB.

| case | input | ours | parquet2 | duckdb |
|---|---|---|---|---|
| whole file | pyarrow | 198 ms / 0.21 s / 576 MB | 2.67 s / 2.67 s / 805 MB | 759 ms / 0.76 s / 759 MB |
| whole file | polars | 201 ms / 0.21 s / 574 MB | 2.65 s / 2.65 s / 803 MB | 748 ms / 0.75 s / 759 MB |
| whole file | ours | 204 ms / 0.22 s / 577 MB | 2.67 s / 2.66 s / 796 MB | 781 ms / 0.77 s / 759 MB |
| five columns | pyarrow | 255 ms / 0.25 s / 373 MB | 1.66 s / 1.66 s / 617 MB | 373 ms / 0.37 s / 465 MB |
| five columns | polars | 258 ms / 0.26 s / 374 MB | 1.64 s / 1.63 s / 611 MB | 371 ms / 0.37 s / 466 MB |
| five columns | ours | 260 ms / 0.26 s / 376 MB | 1.71 s / 1.70 s / 615 MB | 385 ms / 0.38 s / 467 MB |
| 1,000 rows | pyarrow | 175 ms / 0.17 s / 380 MB | 3.14 s / 3.13 s / 922 MB | 652 ms / 0.65 s / 566 MB |
| 1,000 rows | polars | 184 ms / 0.18 s / 379 MB | 3.16 s / 3.16 s / 922 MB | 658 ms / 0.66 s / 568 MB |
| 1,000 rows | ours | 185 ms / 0.18 s / 382 MB | 3.18 s / 3.17 s / 914 MB | 651 ms / 0.65 s / 566 MB |
| read + pass | pyarrow | 346 ms / 0.36 s / 576 MB | 2.83 s / 2.83 s / 812 MB | 900 ms / 0.90 s / 758 MB |
| read + pass | polars | 416 ms / 0.38 s / 576 MB | 2.82 s / 2.82 s / 808 MB | 897 ms / 0.90 s / 758 MB |
| read + pass | ours | 418 ms / 0.39 s / 579 MB | 2.82 s / 2.82 s / 798 MB | 885 ms / 0.88 s / 758 MB |
| write, defaults | dta | 429 ms / 0.32 s / 431 MB | 6.17 s / 6.16 s / 893 MB | 784 ms / 0.78 s / 802 MB |
| write, zstd 3 | dta | 245 ms / 0.30 s / 435 MB | 6.16 s / 6.16 s / 905 MB | 805 ms / 0.80 s / 798 MB |

