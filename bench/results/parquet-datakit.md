# Parquet benchmarks (Python, datakit into polars)

Written by `bench/parquet/run_polars.py`; bench/RESULTS.md says what the numbers mean.

One-minute load average before each run: median 12.5, range 9.1 to 31.3 (plan 0018 asks for under 2).

| library | version | threads |
|---|---|---|
| datakit | datakit 0.3.0 | default |
| dta_parser (pandas) | dta_parser (pandas) | default |
| polars | 2.1.0 | 16 |
| pyarrow (Table) | 26.0.1 | 16 |

## Ratios, ours to theirs (geometric means), gated

Below 1 is better for us. Target 1 holds where wall and RSS are at most 1.05 on NSFG and DHS. Writes are of the frame pl.read_parquet gives of our file.

| against | case | input | family | files | wall | CPU | peak RSS |
|---|---|---|---|---|---|---|---|
| polars | whole file | pyarrow | NSFG | 36 | 0.39 | 0.54 | 0.83 |
| polars | whole file | pyarrow | DHS | 10 | 0.64 | 0.95 | 0.68 |
| polars | whole file | pyarrow | Synthetic | 3 | 0.85 | 1.12 | 0.83 |
| polars | whole file | polars | NSFG | 36 | 0.38 | 0.55 | 0.83 |
| polars | whole file | polars | DHS | 10 | 0.62 | 0.98 | 0.69 |
| polars | whole file | polars | Synthetic | 3 | 0.70 | 0.98 | 0.87 |
| polars | whole file | ours | NSFG | 36 | 0.47 | 0.57 | 0.84 |
| polars | whole file | ours | DHS | 10 | 0.75 | 1.03 | 0.70 |
| polars | whole file | ours | Synthetic | 3 | 0.81 | 1.12 | 0.83 |
| polars | five columns | pyarrow | NSFG | 36 | 0.33 | 0.16 | 0.78 |
| polars | five columns | pyarrow | DHS | 10 | 0.50 | 0.32 | 0.78 |
| polars | five columns | pyarrow | Synthetic | 3 | 0.95 | 1.11 | 0.88 |
| polars | five columns | polars | NSFG | 36 | 0.31 | 0.15 | 0.78 |
| polars | five columns | polars | DHS | 10 | 0.44 | 0.31 | 0.78 |
| polars | five columns | polars | Synthetic | 3 | 0.55 | 0.94 | 0.72 |
| polars | five columns | ours | NSFG | 36 | 0.42 | 0.19 | 0.78 |
| polars | five columns | ours | DHS | 10 | 0.61 | 0.39 | 0.78 |
| polars | five columns | ours | Synthetic | 3 | 0.93 | 1.10 | 0.75 |
| polars | 1,000 rows | pyarrow | NSFG | 36 | 0.44 | 0.40 | 0.83 |
| polars | 1,000 rows | pyarrow | DHS | 10 | 0.70 | 0.67 | 0.84 |
| polars | 1,000 rows | pyarrow | Synthetic | 3 | 0.34 | 0.29 | 0.27 |
| polars | 1,000 rows | polars | NSFG | 36 | 0.38 | 0.40 | 0.84 |
| polars | 1,000 rows | polars | DHS | 10 | 0.64 | 0.67 | 0.85 |
| polars | 1,000 rows | polars | Synthetic | 3 | 0.29 | 0.33 | 0.55 |
| polars | 1,000 rows | ours | NSFG | 36 | 0.55 | 0.42 | 0.85 |
| polars | 1,000 rows | ours | DHS | 10 | 0.83 | 0.71 | 0.86 |
| polars | 1,000 rows | ours | Synthetic | 3 | 0.27 | 0.25 | 0.40 |
| polars | read + pass | pyarrow | NSFG | 36 | 0.71 | 0.91 | 0.93 |
| polars | read + pass | pyarrow | DHS | 10 | 0.80 | 0.98 | 0.76 |
| polars | read + pass | pyarrow | Synthetic | 3 | 1.03 | 1.10 | 0.90 |
| polars | read + pass | polars | NSFG | 36 | 0.68 | 0.92 | 0.93 |
| polars | read + pass | polars | DHS | 10 | 0.78 | 1.01 | 0.76 |
| polars | read + pass | polars | Synthetic | 3 | 0.78 | 0.98 | 0.90 |
| polars | read + pass | ours | NSFG | 36 | 0.74 | 0.95 | 0.94 |
| polars | read + pass | ours | DHS | 10 | 0.91 | 1.02 | 0.77 |
| polars | read + pass | ours | Synthetic | 3 | 0.88 | 1.09 | 0.87 |
| polars | write, defaults | write | NSFG | 36 | 0.81 | 0.62 | 0.91 |
| polars | write, defaults | write | DHS | 10 | 0.72 | 0.68 | 0.92 |
| polars | write, defaults | write | Synthetic | 3 | 0.91 | 0.72 | 1.26 |
| polars | write, zstd 3 | write | NSFG | 36 | 0.90 | 0.71 | 0.93 |
| polars | write, zstd 3 | write | DHS | 10 | 0.80 | 0.75 | 0.94 |
| polars | write, zstd 3 | write | Synthetic | 3 | 1.10 | 1.09 | 1.24 |
| pyarrow (Table) | whole file | pyarrow | NSFG | 36 | 0.02 | 0.04 | 0.49 |
| pyarrow (Table) | whole file | pyarrow | DHS | 10 | 0.07 | 0.13 | 0.50 |
| pyarrow (Table) | whole file | pyarrow | Synthetic | 3 | 0.15 | 0.48 | 0.59 |
| pyarrow (Table) | whole file | polars | NSFG | 36 | 0.02 | 0.04 | 0.49 |
| pyarrow (Table) | whole file | polars | DHS | 10 | 0.07 | 0.13 | 0.50 |
| pyarrow (Table) | whole file | polars | Synthetic | 3 | 0.22 | 0.49 | 0.54 |
| pyarrow (Table) | whole file | ours | NSFG | 36 | 0.02 | 0.04 | 0.50 |
| pyarrow (Table) | whole file | ours | DHS | 10 | 0.07 | 0.13 | 0.51 |
| pyarrow (Table) | whole file | ours | Synthetic | 3 | 0.16 | 0.38 | 0.56 |
| pyarrow (Table) | five columns | pyarrow | NSFG | 36 | 0.01 | 0.01 | 0.44 |
| pyarrow (Table) | five columns | pyarrow | DHS | 10 | 0.01 | 0.02 | 0.44 |
| pyarrow (Table) | five columns | pyarrow | Synthetic | 3 | 0.07 | 0.27 | 0.64 |
| pyarrow (Table) | five columns | polars | NSFG | 36 | 0.01 | 0.01 | 0.43 |
| pyarrow (Table) | five columns | polars | DHS | 10 | 0.01 | 0.02 | 0.44 |
| pyarrow (Table) | five columns | polars | Synthetic | 3 | 0.11 | 0.32 | 0.54 |
| pyarrow (Table) | five columns | ours | NSFG | 36 | 0.01 | 0.01 | 0.44 |
| pyarrow (Table) | five columns | ours | DHS | 10 | 0.02 | 0.02 | 0.44 |
| pyarrow (Table) | five columns | ours | Synthetic | 3 | 0.08 | 0.23 | 0.57 |
| pyarrow (Table) | 1,000 rows | pyarrow | NSFG | 36 | 0.34 | 0.17 | 0.49 |
| pyarrow (Table) | 1,000 rows | pyarrow | DHS | 10 | 0.25 | 0.11 | 0.30 |
| pyarrow (Table) | 1,000 rows | pyarrow | Synthetic | 3 | 0.09 | 0.12 | 0.13 |
| pyarrow (Table) | 1,000 rows | polars | NSFG | 36 | 0.37 | 0.18 | 0.48 |
| pyarrow (Table) | 1,000 rows | polars | DHS | 10 | 0.26 | 0.12 | 0.30 |
| pyarrow (Table) | 1,000 rows | polars | Synthetic | 3 | 0.48 | 0.45 | 0.35 |
| pyarrow (Table) | 1,000 rows | ours | NSFG | 36 | 0.44 | 0.18 | 0.50 |
| pyarrow (Table) | 1,000 rows | ours | DHS | 10 | 0.33 | 0.12 | 0.31 |
| pyarrow (Table) | 1,000 rows | ours | Synthetic | 3 | 0.16 | 0.16 | 0.24 |
| pyarrow (Table) | read + pass | pyarrow | NSFG | 36 | 0.05 | 0.11 | 0.59 |
| pyarrow (Table) | read + pass | pyarrow | DHS | 10 | 0.14 | 0.22 | 0.59 |
| pyarrow (Table) | read + pass | pyarrow | Synthetic | 3 | 0.24 | 0.52 | 0.68 |
| pyarrow (Table) | read + pass | polars | NSFG | 36 | 0.05 | 0.12 | 0.59 |
| pyarrow (Table) | read + pass | polars | DHS | 10 | 0.16 | 0.23 | 0.59 |
| pyarrow (Table) | read + pass | polars | Synthetic | 3 | 0.32 | 0.53 | 0.63 |
| pyarrow (Table) | read + pass | ours | NSFG | 36 | 0.06 | 0.12 | 0.60 |
| pyarrow (Table) | read + pass | ours | DHS | 10 | 0.16 | 0.23 | 0.60 |
| pyarrow (Table) | read + pass | ours | Synthetic | 3 | 0.19 | 0.43 | 0.64 |
| pyarrow (Table) | write, defaults | write | NSFG | 36 | 0.21 | 0.72 | 0.76 |
| pyarrow (Table) | write, defaults | write | DHS | 10 | 0.14 | 0.79 | 0.88 |
| pyarrow (Table) | write, defaults | write | Synthetic | 3 | 0.11 | 0.74 | 1.14 |
| pyarrow (Table) | write, zstd 3 | write | NSFG | 36 | 0.21 | 0.74 | 0.77 |
| pyarrow (Table) | write, zstd 3 | write | DHS | 10 | 0.13 | 0.80 | 0.90 |
| pyarrow (Table) | write, zstd 3 | write | Synthetic | 3 | 0.10 | 0.84 | 1.11 |

## .dta into polars against dta_parser's pandas path (published, not gated)

| case | family | files | wall | CPU | peak RSS |
|---|---|---|---|---|---|
| .dta read | NSFG | 36 | 0.04 | 0.05 | 0.43 |
| .dta read | DHS | 10 | 0.12 | 0.28 | 0.33 |
| .dta read | Synthetic | 3 | 0.31 | 0.62 | 0.62 |
| .dta write | NSFG | 36 | 1.12 | 1.24 | 0.46 |
| .dta write | DHS | 10 | 1.17 | 1.49 | 0.37 |
| .dta write | Synthetic | 3 | 0.59 | 0.91 | 0.47 |

## Misses

- 3 CPU: polars full pyarrow long.dta: 0.475 s vs 0.370 s, speedup 1.15 allows 0.427 s
- 3 CPU: polars full pyarrow groups.dta: 0.088 s vs 0.076 s, speedup 1.04 allows 0.088 s
- 3 CPU: polars full pyarrow 1995_FemResp: 0.096 s vs 0.071 s, speedup 1.03 allows 0.082 s
- 3 CPU: polars full ours groups.dta: 0.097 s vs 0.075 s, speedup 1.00 allows 0.087 s
- 3 CPU: polars full ours 1995_FemResp: 0.099 s vs 0.077 s, speedup 0.81 allows 0.089 s
- 3 CPU: polars full ours 2006_2010_FemResp: 0.071 s vs 0.057 s, speedup 1.00 allows 0.066 s
- 3 CPU: polars full ours Senegal 2019 wm: 0.051 s vs 0.041 s, speedup 0.90 allows 0.047 s
- 3 CPU: polars full ours Myanmar 2016 wm: 0.075 s vs 0.059 s, speedup 0.90 allows 0.068 s
- 3 CPU: polars five pyarrow long.dta: 0.320 s vs 0.235 s, speedup 0.85 allows 0.270 s
- 3 CPU: polars five ours long.dta: 0.309 s vs 0.240 s, speedup 0.98 allows 0.276 s
- 3 CPU: polars five ours groups.dta: 0.092 s vs 0.074 s, speedup 0.95 allows 0.086 s
- 2 wall: polars pass pyarrow long.dta: 164 ms vs 123 ms (1.32x)
- 3 CPU: polars pass pyarrow long.dta: 0.530 s vs 0.450 s, speedup 0.75 allows 0.518 s
- 3 CPU: polars pass pyarrow groups.dta: 0.122 s vs 0.102 s, speedup 0.98 allows 0.118 s
- 2 RSS: polars write write long.dta: 2242 vs 1537 MB (1.46x)
- 2 RSS: polars write write groups.dta: 747 vs 540 MB (1.38x)
- 2 RSS: polars zstd write long.dta: 2209 vs 1529 MB (1.44x)
- 3 CPU: polars zstd write wide.dta: 9.382 s vs 7.007 s, speedup 0.91 allows 8.058 s
- 2 RSS: polars zstd write groups.dta: 728 vs 546 MB (1.34x)
- 2 RSS: pyarrow write write long.dta: 2242 vs 1566 MB (1.43x)
- 2 RSS: pyarrow zstd write long.dta: 2209 vs 1593 MB (1.39x)

## Every file

Each cell: wall / CPU / peak RSS (median of the runs).

### long.dta

10,000,000 rows, 12 columns; .dta 740.0 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 64 ms / 0.48 s / 1266 MB | 74 ms / 0.37 s / 1330 MB | 401 ms / 0.72 s / 1866 MB |
| whole file | polars | 98 ms / 0.81 s / 1133 MB | 103 ms / 0.86 s / 1326 MB | 294 ms / 1.17 s / 1885 MB |
| whole file | ours | 53 ms / 0.43 s / 1159 MB | 57 ms / 0.39 s / 1300 MB | 248 ms / 0.77 s / 1782 MB |
| five columns | pyarrow | 45 ms / 0.32 s / 681 MB | 38 ms / 0.24 s / 783 MB | 247 ms / 0.43 s / 919 MB |
| five columns | polars | 54 ms / 0.46 s / 569 MB | 62 ms / 0.45 s / 818 MB | 224 ms / 0.66 s / 889 MB |
| five columns | ours | 43 ms / 0.31 s / 594 MB | 42 ms / 0.24 s / 832 MB | 224 ms / 0.54 s / 864 MB |
| 1,000 rows | pyarrow | 4 ms / 0.01 s / 88 MB | 9 ms / 0.02 s / 154 MB | 26 ms / 0.06 s / 325 MB |
| 1,000 rows | polars | 3 ms / 0.01 s / 77 MB | 12 ms / 0.01 s / 91 MB | 5 ms / 0.02 s / 137 MB |
| 1,000 rows | ours | 2 ms / 0.00 s / 77 MB | 12 ms / 0.01 s / 101 MB | 10 ms / 0.02 s / 158 MB |
| read + pass | pyarrow | 164 ms / 0.53 s / 1566 MB | 123 ms / 0.45 s / 1481 MB | 426 ms / 0.75 s / 1951 MB |
| read + pass | polars | 133 ms / 0.85 s / 1418 MB | 107 ms / 0.91 s / 1580 MB | 320 ms / 1.20 s / 1935 MB |
| read + pass | ours | 66 ms / 0.49 s / 1410 MB | 64 ms / 0.46 s / 1502 MB | 277 ms / 0.77 s / 1816 MB |
| write, defaults | write | 163 ms / 1.40 s / 2242 MB | 186 ms / 1.91 s / 1537 MB | 1.58 s / 1.57 s / 1566 MB |
| write, zstd 3 | write | 228 ms / 2.22 s / 2209 MB | 190 ms / 1.95 s / 1529 MB | 2.22 s / 2.22 s / 1593 MB |
| .dta read (ours, pandas) | dta | 197 ms / 0.59 s / 1003 MB | 937 ms / 1.25 s / 2141 MB | – |
| .dta write (ours, pandas) | dta | 412 ms / 1.02 s / 1020 MB | 1.23 s / 1.38 s / 2703 MB | – |

### wide.dta

1,500,000 rows, 400 columns; .dta 4800.3 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 174 ms / 1.73 s / 5203 MB | 233 ms / 1.84 s / 7991 MB | 441 ms / 2.79 s / 10194 MB |
| whole file | polars | 454 ms / 4.32 s / 4971 MB | 1.24 s / 4.93 s / 5631 MB | 715 ms / 5.50 s / 9816 MB |
| whole file | ours | 138 ms / 1.30 s / 4996 MB | 245 ms / 1.32 s / 6898 MB | 525 ms / 3.14 s / 9970 MB |
| five columns | pyarrow | 10 ms / 0.03 s / 180 MB | 16 ms / 0.03 s / 214 MB | 337 ms / 0.22 s / 301 MB |
| five columns | polars | 20 ms / 0.06 s / 139 MB | 94 ms / 0.08 s / 232 MB | 263 ms / 0.28 s / 295 MB |
| five columns | ours | 7 ms / 0.02 s / 142 MB | 9 ms / 0.03 s / 217 MB | 171 ms / 0.21 s / 287 MB |
| 1,000 rows | pyarrow | 39 ms / 0.33 s / 158 MB | 110 ms / 0.71 s / 3595 MB | 423 ms / 1.45 s / 7130 MB |
| 1,000 rows | polars | 36 ms / 0.23 s / 88 MB | 117 ms / 0.26 s / 353 MB | 59 ms / 0.29 s / 668 MB |
| 1,000 rows | ours | 11 ms / 0.05 s / 97 MB | 31 ms / 0.17 s / 944 MB | 114 ms / 0.50 s / 1839 MB |
| read + pass | pyarrow | 212 ms / 1.85 s / 5220 MB | 263 ms / 1.95 s / 7184 MB | 527 ms / 2.89 s / 10201 MB |
| read + pass | polars | 507 ms / 4.49 s / 4987 MB | 1.19 s / 5.08 s / 5675 MB | 790 ms / 5.42 s / 9811 MB |
| read + pass | ours | 169 ms / 1.54 s / 5013 MB | 271 ms / 1.40 s / 6868 MB | 572 ms / 3.38 s / 9972 MB |
| write, defaults | write | 720 ms / 4.11 s / 8012 MB | 800 ms / 6.96 s / 8056 MB | 6.45 s / 6.42 s / 6904 MB |
| write, zstd 3 | write | 1.02 s / 9.38 s / 7899 MB | 928 ms / 7.01 s / 8033 MB | 10.72 s / 10.67 s / 6848 MB |
| .dta read (ours, pandas) | dta | 789 ms / 2.36 s / 4962 MB | 724 ms / 1.46 s / 4976 MB | – |
| .dta write (ours, pandas) | dta | 1.24 s / 3.93 s / 4980 MB | 1.24 s / 2.34 s / 5003 MB | – |

### groups.dta

15,000,000 rows, 2 columns; .dta 270.0 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 12 ms / 0.09 s / 381 MB | 13 ms / 0.08 s / 415 MB | 216 ms / 0.33 s / 645 MB |
| whole file | polars | 15 ms / 0.10 s / 381 MB | 15 ms / 0.08 s / 431 MB | 304 ms / 0.44 s / 728 MB |
| whole file | ours | 14 ms / 0.10 s / 383 MB | 14 ms / 0.08 s / 427 MB | 205 ms / 0.42 s / 710 MB |
| five columns | pyarrow | 16 ms / 0.09 s / 380 MB | 14 ms / 0.08 s / 416 MB | 235 ms / 0.38 s / 650 MB |
| five columns | polars | 15 ms / 0.09 s / 381 MB | 16 ms / 0.09 s / 432 MB | 203 ms / 0.44 s / 743 MB |
| five columns | ours | 15 ms / 0.09 s / 382 MB | 14 ms / 0.07 s / 428 MB | 201 ms / 0.42 s / 707 MB |
| 1,000 rows | pyarrow | 0 ms / 0.00 s / 67 MB | 2 ms / 0.01 s / 83 MB | 10 ms / 0.01 s / 173 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 82 MB | 2 ms / 0.00 s / 113 MB |
| 1,000 rows | ours | 1 ms / 0.00 s / 67 MB | 2 ms / 0.01 s / 82 MB | 3 ms / 0.00 s / 125 MB |
| read + pass | pyarrow | 25 ms / 0.12 s / 572 MB | 24 ms / 0.10 s / 597 MB | 268 ms / 0.40 s / 759 MB |
| read + pass | polars | 29 ms / 0.12 s / 571 MB | 31 ms / 0.11 s / 616 MB | 241 ms / 0.48 s / 858 MB |
| read + pass | ours | 24 ms / 0.12 s / 574 MB | 23 ms / 0.11 s / 607 MB | 235 ms / 0.45 s / 842 MB |
| write, defaults | write | 63 ms / 0.40 s / 747 MB | 66 ms / 0.46 s / 540 MB | 561 ms / 0.56 s / 844 MB |
| write, zstd 3 | write | 68 ms / 0.39 s / 728 MB | 68 ms / 0.45 s / 546 MB | 586 ms / 0.59 s / 842 MB |
| .dta read (ours, pandas) | dta | 89 ms / 0.27 s / 597 MB | 664 ms / 0.86 s / 1164 MB | – |
| .dta write (ours, pandas) | dta | 511 ms / 0.51 s / 606 MB | 846 ms / 0.85 s / 2159 MB | – |

### 1973_FemResp

9,797 rows, 450 columns; .dta 5.7 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 4 ms / 0.01 s / 89 MB | 11 ms / 0.01 s / 105 MB | 245 ms / 0.20 s / 182 MB |
| whole file | polars | 4 ms / 0.01 s / 89 MB | 9 ms / 0.01 s / 105 MB | 166 ms / 0.19 s / 182 MB |
| whole file | ours | 4 ms / 0.01 s / 90 MB | 7 ms / 0.01 s / 106 MB | 165 ms / 0.19 s / 182 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 85 MB | 162 ms / 0.16 s / 151 MB |
| five columns | polars | 1 ms / 0.00 s / 66 MB | 3 ms / 0.01 s / 85 MB | 220 ms / 0.18 s / 151 MB |
| five columns | ours | 1 ms / 0.00 s / 66 MB | 5 ms / 0.01 s / 85 MB | 172 ms / 0.17 s / 152 MB |
| 1,000 rows | pyarrow | 2 ms / 0.00 s / 73 MB | 5 ms / 0.01 s / 88 MB | 7 ms / 0.03 s / 134 MB |
| 1,000 rows | polars | 3 ms / 0.01 s / 73 MB | 6 ms / 0.01 s / 87 MB | 7 ms / 0.03 s / 135 MB |
| 1,000 rows | ours | 3 ms / 0.00 s / 74 MB | 5 ms / 0.01 s / 88 MB | 7 ms / 0.03 s / 134 MB |
| read + pass | pyarrow | 8 ms / 0.02 s / 108 MB | 12 ms / 0.02 s / 114 MB | 169 ms / 0.19 s / 183 MB |
| read + pass | polars | 8 ms / 0.02 s / 108 MB | 13 ms / 0.02 s / 113 MB | 176 ms / 0.20 s / 184 MB |
| read + pass | ours | 9 ms / 0.02 s / 108 MB | 12 ms / 0.02 s / 114 MB | 174 ms / 0.20 s / 184 MB |
| write, defaults | write | 10 ms / 0.04 s / 112 MB | 12 ms / 0.06 s / 121 MB | 47 ms / 0.05 s / 152 MB |
| write, zstd 3 | write | 11 ms / 0.04 s / 114 MB | 14 ms / 0.06 s / 122 MB | 53 ms / 0.05 s / 152 MB |
| .dta read (ours, pandas) | dta | 12 ms / 0.01 s / 76 MB | 203 ms / 0.20 s / 170 MB | – |
| .dta write (ours, pandas) | dta | 43 ms / 0.04 s / 83 MB | 27 ms / 0.03 s / 177 MB | – |

### 1976_FemResp

8,611 rows, 468 columns; .dta 6.0 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 4 ms / 0.01 s / 87 MB | 8 ms / 0.01 s / 106 MB | 180 ms / 0.20 s / 184 MB |
| whole file | polars | 5 ms / 0.01 s / 88 MB | 10 ms / 0.01 s / 105 MB | 173 ms / 0.19 s / 183 MB |
| whole file | ours | 7 ms / 0.01 s / 89 MB | 14 ms / 0.01 s / 107 MB | 169 ms / 0.19 s / 184 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 66 MB | 3 ms / 0.01 s / 84 MB | 166 ms / 0.17 s / 152 MB |
| five columns | polars | 1 ms / 0.00 s / 66 MB | 3 ms / 0.01 s / 85 MB | 163 ms / 0.16 s / 152 MB |
| five columns | ours | 1 ms / 0.00 s / 68 MB | 3 ms / 0.01 s / 86 MB | 166 ms / 0.17 s / 152 MB |
| 1,000 rows | pyarrow | 3 ms / 0.01 s / 73 MB | 5 ms / 0.01 s / 88 MB | 10 ms / 0.03 s / 136 MB |
| 1,000 rows | polars | 3 ms / 0.01 s / 73 MB | 7 ms / 0.01 s / 87 MB | 8 ms / 0.03 s / 135 MB |
| 1,000 rows | ours | 4 ms / 0.01 s / 75 MB | 5 ms / 0.01 s / 89 MB | 6 ms / 0.03 s / 137 MB |
| read + pass | pyarrow | 8 ms / 0.02 s / 106 MB | 12 ms / 0.02 s / 114 MB | 166 ms / 0.19 s / 185 MB |
| read + pass | polars | 8 ms / 0.02 s / 106 MB | 13 ms / 0.02 s / 114 MB | 167 ms / 0.19 s / 185 MB |
| read + pass | ours | 9 ms / 0.02 s / 108 MB | 12 ms / 0.02 s / 114 MB | 167 ms / 0.19 s / 185 MB |
| write, defaults | write | 9 ms / 0.04 s / 113 MB | 14 ms / 0.05 s / 124 MB | 48 ms / 0.05 s / 152 MB |
| write, zstd 3 | write | 12 ms / 0.05 s / 116 MB | 14 ms / 0.05 s / 122 MB | 53 ms / 0.05 s / 152 MB |
| .dta read (ours, pandas) | dta | 13 ms / 0.01 s / 77 MB | 198 ms / 0.20 s / 172 MB | – |
| .dta write (ours, pandas) | dta | 38 ms / 0.04 s / 84 MB | 26 ms / 0.03 s / 179 MB | – |

### 1976_PSU

8,611 rows, 3 columns; .dta 0.0 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 0 ms / 0.00 s / 65 MB | 4 ms / 0.01 s / 81 MB | 177 ms / 0.17 s / 150 MB |
| whole file | polars | 0 ms / 0.00 s / 65 MB | 4 ms / 0.01 s / 81 MB | 176 ms / 0.17 s / 149 MB |
| whole file | ours | 0 ms / 0.00 s / 65 MB | 5 ms / 0.01 s / 81 MB | 408 ms / 0.18 s / 150 MB |
| five columns | pyarrow | 0 ms / 0.00 s / 65 MB | 5 ms / 0.00 s / 82 MB | 213 ms / 0.17 s / 150 MB |
| five columns | polars | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 162 ms / 0.16 s / 149 MB |
| five columns | ours | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 82 MB | 160 ms / 0.16 s / 150 MB |
| 1,000 rows | pyarrow | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 1 ms / 0.00 s / 103 MB |
| 1,000 rows | polars | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 0 ms / 0.00 s / 103 MB |
| 1,000 rows | ours | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 0 ms / 0.00 s / 103 MB |
| read + pass | pyarrow | 1 ms / 0.00 s / 76 MB | 2 ms / 0.01 s / 84 MB | 158 ms / 0.16 s / 151 MB |
| read + pass | polars | 1 ms / 0.00 s / 76 MB | 2 ms / 0.01 s / 84 MB | 157 ms / 0.16 s / 151 MB |
| read + pass | ours | 1 ms / 0.00 s / 76 MB | 2 ms / 0.01 s / 84 MB | 158 ms / 0.16 s / 151 MB |
| write, defaults | write | 1 ms / 0.00 s / 84 MB | 1 ms / 0.00 s / 85 MB | 1 ms / 0.00 s / 123 MB |
| write, zstd 3 | write | 1 ms / 0.00 s / 85 MB | 1 ms / 0.00 s / 85 MB | 1 ms / 0.00 s / 124 MB |
| .dta read (ours, pandas) | dta | 0 ms / 0.00 s / 65 MB | 185 ms / 0.18 s / 142 MB | – |
| .dta write (ours, pandas) | dta | 1 ms / 0.00 s / 65 MB | 2 ms / 0.00 s / 142 MB | – |

### 1976_Preg

23,042 rows, 80 columns; .dta 2.4 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 1 ms / 0.00 s / 75 MB | 4 ms / 0.01 s / 91 MB | 159 ms / 0.17 s / 161 MB |
| whole file | polars | 1 ms / 0.00 s / 74 MB | 4 ms / 0.01 s / 91 MB | 159 ms / 0.17 s / 161 MB |
| whole file | ours | 1 ms / 0.00 s / 75 MB | 4 ms / 0.01 s / 91 MB | 168 ms / 0.17 s / 161 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 67 MB | 2 ms / 0.01 s / 83 MB | 157 ms / 0.16 s / 151 MB |
| five columns | polars | 1 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 84 MB | 158 ms / 0.16 s / 151 MB |
| five columns | ours | 1 ms / 0.00 s / 67 MB | 2 ms / 0.01 s / 84 MB | 159 ms / 0.16 s / 150 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 68 MB | 3 ms / 0.01 s / 82 MB | 3 ms / 0.01 s / 114 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 67 MB | 3 ms / 0.01 s / 82 MB | 3 ms / 0.01 s / 114 MB |
| 1,000 rows | ours | 1 ms / 0.00 s / 67 MB | 3 ms / 0.01 s / 83 MB | 3 ms / 0.01 s / 114 MB |
| read + pass | pyarrow | 4 ms / 0.01 s / 88 MB | 7 ms / 0.01 s / 97 MB | 171 ms / 0.18 s / 162 MB |
| read + pass | polars | 4 ms / 0.01 s / 87 MB | 7 ms / 0.01 s / 98 MB | 166 ms / 0.17 s / 162 MB |
| read + pass | ours | 4 ms / 0.01 s / 88 MB | 10 ms / 0.02 s / 98 MB | 170 ms / 0.18 s / 162 MB |
| write, defaults | write | 5 ms / 0.02 s / 98 MB | 7 ms / 0.02 s / 100 MB | 17 ms / 0.02 s / 134 MB |
| write, zstd 3 | write | 5 ms / 0.02 s / 100 MB | 4 ms / 0.02 s / 102 MB | 18 ms / 0.02 s / 134 MB |
| .dta read (ours, pandas) | dta | 5 ms / 0.01 s / 70 MB | 193 ms / 0.19 s / 151 MB | – |
| .dta write (ours, pandas) | dta | 16 ms / 0.02 s / 73 MB | 9 ms / 0.01 s / 155 MB | – |

### 1982_FemResp

7,969 rows, 741 columns; .dta 7.6 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 5 ms / 0.01 s / 96 MB | 10 ms / 0.01 s / 113 MB | 166 ms / 0.20 s / 197 MB |
| whole file | polars | 5 ms / 0.01 s / 97 MB | 12 ms / 0.02 s / 112 MB | 165 ms / 0.20 s / 197 MB |
| whole file | ours | 6 ms / 0.01 s / 98 MB | 10 ms / 0.02 s / 113 MB | 166 ms / 0.20 s / 198 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 66 MB | 3 ms / 0.01 s / 85 MB | 156 ms / 0.16 s / 152 MB |
| five columns | polars | 1 ms / 0.00 s / 66 MB | 3 ms / 0.01 s / 85 MB | 155 ms / 0.16 s / 152 MB |
| five columns | ours | 1 ms / 0.00 s / 68 MB | 3 ms / 0.01 s / 86 MB | 158 ms / 0.16 s / 153 MB |
| 1,000 rows | pyarrow | 3 ms / 0.01 s / 75 MB | 6 ms / 0.01 s / 90 MB | 10 ms / 0.04 s / 149 MB |
| 1,000 rows | polars | 4 ms / 0.01 s / 76 MB | 8 ms / 0.01 s / 90 MB | 10 ms / 0.05 s / 149 MB |
| 1,000 rows | ours | 4 ms / 0.01 s / 78 MB | 6 ms / 0.01 s / 91 MB | 11 ms / 0.04 s / 149 MB |
| read + pass | pyarrow | 12 ms / 0.03 s / 115 MB | 18 ms / 0.03 s / 123 MB | 183 ms / 0.22 s / 198 MB |
| read + pass | polars | 13 ms / 0.03 s / 117 MB | 19 ms / 0.03 s / 123 MB | 186 ms / 0.22 s / 198 MB |
| read + pass | ours | 14 ms / 0.03 s / 118 MB | 20 ms / 0.03 s / 122 MB | 195 ms / 0.22 s / 199 MB |
| write, defaults | write | 18 ms / 0.05 s / 121 MB | 20 ms / 0.08 s / 131 MB | 67 ms / 0.07 s / 159 MB |
| write, zstd 3 | write | 23 ms / 0.06 s / 123 MB | 20 ms / 0.08 s / 132 MB | 160 ms / 0.09 s / 160 MB |
| .dta read (ours, pandas) | dta | 17 ms / 0.02 s / 79 MB | 207 ms / 0.21 s / 178 MB | – |
| .dta write (ours, pandas) | dta | 58 ms / 0.06 s / 88 MB | 39 ms / 0.04 s / 187 MB | – |

### 1982_Preg

13,768 rows, 174 columns; .dta 3.0 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 2 ms / 0.00 s / 76 MB | 9 ms / 0.01 s / 93 MB | 225 ms / 0.18 s / 166 MB |
| whole file | polars | 2 ms / 0.01 s / 77 MB | 5 ms / 0.01 s / 93 MB | 170 ms / 0.18 s / 167 MB |
| whole file | ours | 2 ms / 0.00 s / 78 MB | 4 ms / 0.01 s / 94 MB | 164 ms / 0.17 s / 166 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 83 MB | 165 ms / 0.16 s / 150 MB |
| five columns | polars | 1 ms / 0.00 s / 66 MB | 6 ms / 0.01 s / 83 MB | 205 ms / 0.17 s / 151 MB |
| five columns | ours | 1 ms / 0.00 s / 67 MB | 2 ms / 0.01 s / 84 MB | 157 ms / 0.16 s / 151 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 68 MB | 3 ms / 0.01 s / 83 MB | 3 ms / 0.01 s / 119 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 68 MB | 3 ms / 0.01 s / 83 MB | 3 ms / 0.01 s / 119 MB |
| 1,000 rows | ours | 1 ms / 0.00 s / 69 MB | 3 ms / 0.01 s / 84 MB | 3 ms / 0.01 s / 120 MB |
| read + pass | pyarrow | 4 ms / 0.01 s / 93 MB | 6 ms / 0.02 s / 100 MB | 163 ms / 0.17 s / 167 MB |
| read + pass | polars | 4 ms / 0.01 s / 92 MB | 7 ms / 0.02 s / 100 MB | 166 ms / 0.18 s / 168 MB |
| read + pass | ours | 5 ms / 0.01 s / 94 MB | 7 ms / 0.02 s / 100 MB | 159 ms / 0.17 s / 168 MB |
| write, defaults | write | 4 ms / 0.01 s / 99 MB | 5 ms / 0.02 s / 104 MB | 18 ms / 0.02 s / 136 MB |
| write, zstd 3 | write | 5 ms / 0.02 s / 100 MB | 5 ms / 0.02 s / 104 MB | 19 ms / 0.02 s / 137 MB |
| .dta read (ours, pandas) | dta | 7 ms / 0.01 s / 72 MB | 197 ms / 0.20 s / 161 MB | – |
| .dta write (ours, pandas) | dta | 18 ms / 0.02 s / 76 MB | 13 ms / 0.01 s / 165 MB | – |

### 1988_FemResp

8,450 rows, 1,437 columns; .dta 19.1 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 9 ms / 0.02 s / 125 MB | 19 ms / 0.02 s / 155 MB | 180 ms / 0.24 s / 244 MB |
| whole file | polars | 10 ms / 0.03 s / 126 MB | 25 ms / 0.03 s / 154 MB | 185 ms / 0.25 s / 246 MB |
| whole file | ours | 12 ms / 0.03 s / 129 MB | 27 ms / 0.03 s / 155 MB | 194 ms / 0.25 s / 249 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 67 MB | 4 ms / 0.01 s / 87 MB | 168 ms / 0.17 s / 155 MB |
| five columns | polars | 1 ms / 0.00 s / 68 MB | 3 ms / 0.01 s / 87 MB | 164 ms / 0.16 s / 155 MB |
| five columns | ours | 2 ms / 0.00 s / 68 MB | 3 ms / 0.01 s / 88 MB | 161 ms / 0.16 s / 156 MB |
| 1,000 rows | pyarrow | 5 ms / 0.01 s / 82 MB | 11 ms / 0.02 s / 100 MB | 17 ms / 0.08 s / 194 MB |
| 1,000 rows | polars | 7 ms / 0.02 s / 82 MB | 17 ms / 0.02 s / 99 MB | 18 ms / 0.09 s / 194 MB |
| 1,000 rows | ours | 8 ms / 0.01 s / 85 MB | 11 ms / 0.01 s / 101 MB | 17 ms / 0.08 s / 196 MB |
| read + pass | pyarrow | 23 ms / 0.05 s / 152 MB | 32 ms / 0.05 s / 170 MB | 204 ms / 0.26 s / 245 MB |
| read + pass | polars | 23 ms / 0.06 s / 152 MB | 37 ms / 0.05 s / 170 MB | 205 ms / 0.27 s / 246 MB |
| read + pass | ours | 24 ms / 0.05 s / 155 MB | 32 ms / 0.05 s / 171 MB | 197 ms / 0.26 s / 246 MB |
| write, defaults | write | 23 ms / 0.11 s / 167 MB | 29 ms / 0.16 s / 196 MB | 139 ms / 0.14 s / 205 MB |
| write, zstd 3 | write | 26 ms / 0.12 s / 171 MB | 30 ms / 0.17 s / 198 MB | 160 ms / 0.16 s / 206 MB |
| .dta read (ours, pandas) | dta | 18 ms / 0.04 s / 106 MB | 220 ms / 0.23 s / 246 MB | – |
| .dta write (ours, pandas) | dta | 58 ms / 0.11 s / 127 MB | 59 ms / 0.08 s / 266 MB | – |

### 1988_Preg

15,759 rows, 284 columns; .dta 10.7 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 3 ms / 0.01 s / 88 MB | 9 ms / 0.01 s / 110 MB | 181 ms / 0.19 s / 178 MB |
| whole file | polars | 5 ms / 0.01 s / 88 MB | 13 ms / 0.02 s / 109 MB | 177 ms / 0.19 s / 178 MB |
| whole file | ours | 5 ms / 0.01 s / 89 MB | 12 ms / 0.01 s / 110 MB | 179 ms / 0.19 s / 179 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 67 MB | 4 ms / 0.01 s / 84 MB | 230 ms / 0.17 s / 151 MB |
| five columns | polars | 1 ms / 0.00 s / 67 MB | 11 ms / 0.01 s / 84 MB | 338 ms / 0.18 s / 152 MB |
| five columns | ours | 1 ms / 0.00 s / 70 MB | 4 ms / 0.01 s / 84 MB | 182 ms / 0.17 s / 151 MB |
| 1,000 rows | pyarrow | 2 ms / 0.01 s / 72 MB | 5 ms / 0.01 s / 88 MB | 5 ms / 0.02 s / 132 MB |
| 1,000 rows | polars | 3 ms / 0.01 s / 72 MB | 8 ms / 0.01 s / 87 MB | 5 ms / 0.02 s / 132 MB |
| 1,000 rows | ours | 3 ms / 0.01 s / 73 MB | 5 ms / 0.01 s / 88 MB | 5 ms / 0.02 s / 133 MB |
| read + pass | pyarrow | 7 ms / 0.02 s / 106 MB | 12 ms / 0.02 s / 118 MB | 171 ms / 0.19 s / 180 MB |
| read + pass | polars | 11 ms / 0.02 s / 103 MB | 14 ms / 0.02 s / 117 MB | 171 ms / 0.19 s / 180 MB |
| read + pass | ours | 8 ms / 0.02 s / 107 MB | 11 ms / 0.02 s / 118 MB | 172 ms / 0.19 s / 181 MB |
| write, defaults | write | 11 ms / 0.04 s / 119 MB | 13 ms / 0.07 s / 130 MB | 54 ms / 0.05 s / 154 MB |
| write, zstd 3 | write | 10 ms / 0.04 s / 121 MB | 14 ms / 0.07 s / 132 MB | 60 ms / 0.06 s / 154 MB |
| .dta read (ours, pandas) | dta | 13 ms / 0.01 s / 81 MB | 200 ms / 0.20 s / 168 MB | – |
| .dta write (ours, pandas) | dta | 34 ms / 0.03 s / 90 MB | 18 ms / 0.02 s / 178 MB | – |

### 1995_FemResp

10,847 rows, 5,754 columns; .dta 78.9 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 23 ms / 0.10 s / 312 MB | 24 ms / 0.07 s / 408 MB | 229 ms / 0.44 s / 533 MB |
| whole file | polars | 23 ms / 0.09 s / 312 MB | 28 ms / 0.09 s / 408 MB | 227 ms / 0.46 s / 534 MB |
| whole file | ours | 31 ms / 0.10 s / 328 MB | 25 ms / 0.08 s / 413 MB | 222 ms / 0.43 s / 540 MB |
| five columns | pyarrow | 4 ms / 0.00 s / 71 MB | 7 ms / 0.01 s / 97 MB | 169 ms / 0.17 s / 169 MB |
| five columns | polars | 4 ms / 0.00 s / 71 MB | 6 ms / 0.01 s / 98 MB | 168 ms / 0.17 s / 171 MB |
| five columns | ours | 6 ms / 0.01 s / 77 MB | 7 ms / 0.01 s / 104 MB | 168 ms / 0.17 s / 181 MB |
| 1,000 rows | pyarrow | 16 ms / 0.03 s / 117 MB | 14 ms / 0.03 s / 140 MB | 59 ms / 0.28 s / 476 MB |
| 1,000 rows | polars | 17 ms / 0.03 s / 118 MB | 17 ms / 0.04 s / 139 MB | 61 ms / 0.29 s / 476 MB |
| 1,000 rows | ours | 23 ms / 0.03 s / 134 MB | 14 ms / 0.03 s / 145 MB | 61 ms / 0.26 s / 483 MB |
| read + pass | pyarrow | 70 ms / 0.18 s / 383 MB | 73 ms / 0.17 s / 452 MB | 307 ms / 0.51 s / 537 MB |
| read + pass | polars | 71 ms / 0.19 s / 383 MB | 74 ms / 0.17 s / 451 MB | 302 ms / 0.52 s / 540 MB |
| read + pass | ours | 82 ms / 0.19 s / 399 MB | 80 ms / 0.18 s / 452 MB | 320 ms / 0.50 s / 546 MB |
| write, defaults | write | 60 ms / 0.30 s / 442 MB | 70 ms / 0.42 s / 482 MB | 405 ms / 0.40 s / 489 MB |
| write, zstd 3 | write | 51 ms / 0.33 s / 449 MB | 60 ms / 0.41 s / 483 MB | 429 ms / 0.42 s / 489 MB |
| .dta read (ours, pandas) | dta | 69 ms / 0.17 s / 192 MB | 350 ms / 0.43 s / 609 MB | – |
| .dta write (ours, pandas) | dta | 256 ms / 0.48 s / 224 MB | 254 ms / 0.38 s / 637 MB | – |

### 1995_Preg

21,332 rows, 245 columns; .dta 6.2 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 3 ms / 0.01 s / 91 MB | 10 ms / 0.01 s / 110 MB | 169 ms / 0.19 s / 182 MB |
| whole file | polars | 3 ms / 0.01 s / 91 MB | 8 ms / 0.01 s / 110 MB | 158 ms / 0.18 s / 183 MB |
| whole file | ours | 3 ms / 0.01 s / 91 MB | 8 ms / 0.01 s / 111 MB | 159 ms / 0.18 s / 183 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 84 MB | 153 ms / 0.15 s / 151 MB |
| five columns | polars | 1 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 85 MB | 152 ms / 0.15 s / 151 MB |
| five columns | ours | 1 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 85 MB | 153 ms / 0.15 s / 151 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 72 MB | 4 ms / 0.01 s / 86 MB | 5 ms / 0.02 s / 136 MB |
| 1,000 rows | polars | 2 ms / 0.00 s / 71 MB | 5 ms / 0.01 s / 86 MB | 4 ms / 0.02 s / 136 MB |
| 1,000 rows | ours | 2 ms / 0.00 s / 72 MB | 4 ms / 0.01 s / 86 MB | 4 ms / 0.02 s / 135 MB |
| read + pass | pyarrow | 6 ms / 0.02 s / 109 MB | 11 ms / 0.02 s / 119 MB | 165 ms / 0.18 s / 184 MB |
| read + pass | polars | 6 ms / 0.02 s / 109 MB | 11 ms / 0.02 s / 119 MB | 163 ms / 0.18 s / 184 MB |
| read + pass | ours | 7 ms / 0.02 s / 111 MB | 11 ms / 0.02 s / 120 MB | 164 ms / 0.18 s / 184 MB |
| write, defaults | write | 8 ms / 0.03 s / 119 MB | 10 ms / 0.05 s / 128 MB | 46 ms / 0.05 s / 155 MB |
| write, zstd 3 | write | 9 ms / 0.03 s / 121 MB | 10 ms / 0.05 s / 127 MB | 50 ms / 0.05 s / 155 MB |
| .dta read (ours, pandas) | dta | 13 ms / 0.01 s / 75 MB | 203 ms / 0.20 s / 175 MB | – |
| .dta write (ours, pandas) | dta | 44 ms / 0.04 s / 82 MB | 22 ms / 0.02 s / 181 MB | – |

### 2002_FemPreg

13,593 rows, 243 columns; .dta 4.3 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 2 ms / 0.01 s / 83 MB | 5 ms / 0.01 s / 99 MB | 154 ms / 0.17 s / 174 MB |
| whole file | polars | 2 ms / 0.01 s / 83 MB | 6 ms / 0.01 s / 99 MB | 158 ms / 0.17 s / 174 MB |
| whole file | ours | 3 ms / 0.01 s / 84 MB | 5 ms / 0.01 s / 99 MB | 158 ms / 0.17 s / 174 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 84 MB | 153 ms / 0.15 s / 151 MB |
| five columns | polars | 1 ms / 0.00 s / 67 MB | 2 ms / 0.01 s / 84 MB | 154 ms / 0.15 s / 152 MB |
| five columns | ours | 1 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 85 MB | 155 ms / 0.16 s / 152 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 71 MB | 3 ms / 0.01 s / 85 MB | 4 ms / 0.02 s / 127 MB |
| 1,000 rows | polars | 2 ms / 0.00 s / 70 MB | 4 ms / 0.01 s / 85 MB | 4 ms / 0.02 s / 128 MB |
| 1,000 rows | ours | 2 ms / 0.00 s / 71 MB | 3 ms / 0.01 s / 86 MB | 4 ms / 0.02 s / 126 MB |
| read + pass | pyarrow | 5 ms / 0.02 s / 100 MB | 8 ms / 0.02 s / 107 MB | 161 ms / 0.17 s / 175 MB |
| read + pass | polars | 5 ms / 0.02 s / 100 MB | 9 ms / 0.02 s / 106 MB | 161 ms / 0.17 s / 175 MB |
| read + pass | ours | 6 ms / 0.02 s / 102 MB | 8 ms / 0.02 s / 107 MB | 160 ms / 0.17 s / 175 MB |
| write, defaults | write | 6 ms / 0.02 s / 106 MB | 7 ms / 0.04 s / 116 MB | 32 ms / 0.03 s / 144 MB |
| write, zstd 3 | write | 6 ms / 0.02 s / 108 MB | 7 ms / 0.04 s / 115 MB | 35 ms / 0.03 s / 144 MB |
| .dta read (ours, pandas) | dta | 9 ms / 0.01 s / 73 MB | 199 ms / 0.20 s / 163 MB | – |
| .dta write (ours, pandas) | dta | 29 ms / 0.03 s / 78 MB | 16 ms / 0.02 s / 169 MB | – |

### 2002_FemResp

7,643 rows, 3,087 columns; .dta 29.3 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 13 ms / 0.03 s / 175 MB | 22 ms / 0.03 s / 204 MB | 194 ms / 0.30 s / 328 MB |
| whole file | polars | 14 ms / 0.04 s / 175 MB | 26 ms / 0.04 s / 204 MB | 191 ms / 0.31 s / 329 MB |
| whole file | ours | 18 ms / 0.04 s / 183 MB | 22 ms / 0.03 s / 208 MB | 189 ms / 0.29 s / 334 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 71 MB | 5 ms / 0.01 s / 91 MB | 162 ms / 0.16 s / 160 MB |
| five columns | polars | 2 ms / 0.00 s / 71 MB | 5 ms / 0.01 s / 91 MB | 160 ms / 0.16 s / 160 MB |
| five columns | ours | 4 ms / 0.00 s / 74 MB | 5 ms / 0.01 s / 95 MB | 161 ms / 0.16 s / 165 MB |
| 1,000 rows | pyarrow | 9 ms / 0.02 s / 95 MB | 13 ms / 0.02 s / 112 MB | 31 ms / 0.13 s / 276 MB |
| 1,000 rows | polars | 10 ms / 0.02 s / 96 MB | 16 ms / 0.02 s / 112 MB | 32 ms / 0.15 s / 276 MB |
| 1,000 rows | ours | 13 ms / 0.02 s / 105 MB | 12 ms / 0.02 s / 116 MB | 29 ms / 0.13 s / 280 MB |
| read + pass | pyarrow | 38 ms / 0.08 s / 218 MB | 47 ms / 0.08 s / 232 MB | 226 ms / 0.34 s / 330 MB |
| read + pass | polars | 38 ms / 0.08 s / 218 MB | 49 ms / 0.08 s / 230 MB | 226 ms / 0.35 s / 331 MB |
| read + pass | ours | 42 ms / 0.08 s / 226 MB | 46 ms / 0.08 s / 231 MB | 223 ms / 0.32 s / 335 MB |
| write, defaults | write | 25 ms / 0.14 s / 225 MB | 31 ms / 0.18 s / 254 MB | 184 ms / 0.18 s / 267 MB |
| write, zstd 3 | write | 27 ms / 0.15 s / 230 MB | 31 ms / 0.18 s / 255 MB | 201 ms / 0.20 s / 267 MB |
| .dta read (ours, pandas) | dta | 30 ms / 0.07 s / 125 MB | 253 ms / 0.28 s / 309 MB | – |
| .dta write (ours, pandas) | dta | 97 ms / 0.18 s / 150 MB | 116 ms / 0.16 s / 333 MB | – |

### 2002_HHvars

12,571 rows, 10 columns; .dta 0.1 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 0 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 82 MB | 152 ms / 0.15 s / 151 MB |
| whole file | polars | 0 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 82 MB | 154 ms / 0.16 s / 151 MB |
| whole file | ours | 0 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 82 MB | 153 ms / 0.15 s / 151 MB |
| five columns | pyarrow | 0 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 82 MB | 155 ms / 0.16 s / 150 MB |
| five columns | polars | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 82 MB | 152 ms / 0.15 s / 150 MB |
| five columns | ours | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 82 MB | 151 ms / 0.15 s / 150 MB |
| 1,000 rows | pyarrow | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 1 ms / 0.00 s / 104 MB |
| 1,000 rows | polars | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 1 ms / 0.00 s / 104 MB |
| 1,000 rows | ours | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 1 ms / 0.00 s / 104 MB |
| read + pass | pyarrow | 1 ms / 0.01 s / 79 MB | 2 ms / 0.01 s / 86 MB | 157 ms / 0.16 s / 152 MB |
| read + pass | polars | 1 ms / 0.01 s / 78 MB | 2 ms / 0.01 s / 86 MB | 154 ms / 0.15 s / 152 MB |
| read + pass | ours | 1 ms / 0.01 s / 78 MB | 2 ms / 0.01 s / 86 MB | 153 ms / 0.15 s / 152 MB |
| write, defaults | write | 1 ms / 0.00 s / 86 MB | 1 ms / 0.00 s / 88 MB | 2 ms / 0.00 s / 125 MB |
| write, zstd 3 | write | 1 ms / 0.00 s / 87 MB | 1 ms / 0.00 s / 88 MB | 2 ms / 0.00 s / 125 MB |
| .dta read (ours, pandas) | dta | 1 ms / 0.00 s / 65 MB | 185 ms / 0.18 s / 142 MB | – |
| .dta write (ours, pandas) | dta | 2 ms / 0.00 s / 66 MB | 1 ms / 0.00 s / 142 MB | – |

### 2002_Male

4,928 rows, 1,993 columns; .dta 12.7 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 8 ms / 0.02 s / 118 MB | 14 ms / 0.02 s / 135 MB | 178 ms / 0.24 s / 226 MB |
| whole file | polars | 8 ms / 0.02 s / 118 MB | 17 ms / 0.02 s / 135 MB | 176 ms / 0.25 s / 227 MB |
| whole file | ours | 9 ms / 0.02 s / 121 MB | 14 ms / 0.02 s / 136 MB | 174 ms / 0.23 s / 226 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 67 MB | 4 ms / 0.01 s / 89 MB | 157 ms / 0.16 s / 157 MB |
| five columns | polars | 2 ms / 0.00 s / 68 MB | 4 ms / 0.01 s / 89 MB | 157 ms / 0.16 s / 157 MB |
| five columns | ours | 2 ms / 0.00 s / 68 MB | 4 ms / 0.01 s / 90 MB | 157 ms / 0.16 s / 158 MB |
| 1,000 rows | pyarrow | 6 ms / 0.01 s / 86 MB | 10 ms / 0.01 s / 102 MB | 19 ms / 0.08 s / 177 MB |
| 1,000 rows | polars | 6 ms / 0.01 s / 86 MB | 13 ms / 0.02 s / 101 MB | 19 ms / 0.09 s / 177 MB |
| 1,000 rows | ours | 8 ms / 0.01 s / 89 MB | 10 ms / 0.01 s / 102 MB | 18 ms / 0.07 s / 177 MB |
| read + pass | pyarrow | 23 ms / 0.05 s / 148 MB | 29 ms / 0.04 s / 153 MB | 196 ms / 0.26 s / 227 MB |
| read + pass | polars | 24 ms / 0.05 s / 148 MB | 31 ms / 0.05 s / 153 MB | 195 ms / 0.27 s / 227 MB |
| read + pass | ours | 25 ms / 0.05 s / 151 MB | 29 ms / 0.04 s / 153 MB | 193 ms / 0.25 s / 229 MB |
| write, defaults | write | 16 ms / 0.05 s / 146 MB | 18 ms / 0.09 s / 169 MB | 84 ms / 0.08 s / 189 MB |
| write, zstd 3 | write | 17 ms / 0.06 s / 149 MB | 18 ms / 0.09 s / 168 MB | 95 ms / 0.10 s / 190 MB |
| .dta read (ours, pandas) | dta | 22 ms / 0.02 s / 87 MB | 228 ms / 0.23 s / 212 MB | – |
| .dta write (ours, pandas) | dta | 74 ms / 0.07 s / 101 MB | 76 ms / 0.08 s / 225 MB | – |

### 2002_curr_ins

12,571 rows, 3 columns; .dta 0.1 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 153 ms / 0.15 s / 150 MB |
| whole file | polars | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 154 ms / 0.15 s / 150 MB |
| whole file | ours | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 154 ms / 0.15 s / 150 MB |
| five columns | pyarrow | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 82 MB | 153 ms / 0.15 s / 150 MB |
| five columns | polars | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 82 MB | 155 ms / 0.15 s / 150 MB |
| five columns | ours | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 82 MB | 154 ms / 0.15 s / 150 MB |
| 1,000 rows | pyarrow | 0 ms / 0.00 s / 65 MB | 1 ms / 0.01 s / 81 MB | 0 ms / 0.00 s / 103 MB |
| 1,000 rows | polars | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 0 ms / 0.00 s / 103 MB |
| 1,000 rows | ours | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 1 ms / 0.00 s / 103 MB |
| read + pass | pyarrow | 1 ms / 0.00 s / 76 MB | 3 ms / 0.01 s / 84 MB | 160 ms / 0.16 s / 151 MB |
| read + pass | polars | 1 ms / 0.00 s / 77 MB | 2 ms / 0.01 s / 84 MB | 162 ms / 0.16 s / 151 MB |
| read + pass | ours | 1 ms / 0.00 s / 77 MB | 2 ms / 0.01 s / 84 MB | 157 ms / 0.16 s / 151 MB |
| write, defaults | write | 1 ms / 0.00 s / 84 MB | 1 ms / 0.00 s / 85 MB | 2 ms / 0.00 s / 124 MB |
| write, zstd 3 | write | 1 ms / 0.00 s / 85 MB | 1 ms / 0.00 s / 86 MB | 1 ms / 0.00 s / 124 MB |
| .dta read (ours, pandas) | dta | 0 ms / 0.00 s / 65 MB | 184 ms / 0.18 s / 141 MB | – |
| .dta write (ours, pandas) | dta | 1 ms / 0.00 s / 66 MB | 1 ms / 0.00 s / 142 MB | – |

### 2002_hhpartypnew

12,571 rows, 3 columns; .dta 0.1 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 157 ms / 0.16 s / 150 MB |
| whole file | polars | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 154 ms / 0.15 s / 149 MB |
| whole file | ours | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 153 ms / 0.15 s / 150 MB |
| five columns | pyarrow | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 82 MB | 155 ms / 0.15 s / 150 MB |
| five columns | polars | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 82 MB | 153 ms / 0.15 s / 150 MB |
| five columns | ours | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 82 MB | 164 ms / 0.16 s / 150 MB |
| 1,000 rows | pyarrow | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 1 ms / 0.00 s / 103 MB |
| 1,000 rows | polars | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 1 ms / 0.00 s / 103 MB |
| 1,000 rows | ours | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 1 ms / 0.00 s / 103 MB |
| read + pass | pyarrow | 1 ms / 0.00 s / 77 MB | 2 ms / 0.01 s / 84 MB | 157 ms / 0.16 s / 151 MB |
| read + pass | polars | 1 ms / 0.00 s / 77 MB | 2 ms / 0.01 s / 84 MB | 158 ms / 0.16 s / 151 MB |
| read + pass | ours | 1 ms / 0.00 s / 77 MB | 2 ms / 0.01 s / 84 MB | 163 ms / 0.16 s / 151 MB |
| write, defaults | write | 1 ms / 0.00 s / 84 MB | 1 ms / 0.00 s / 85 MB | 1 ms / 0.00 s / 124 MB |
| write, zstd 3 | write | 1 ms / 0.00 s / 84 MB | 1 ms / 0.00 s / 85 MB | 1 ms / 0.00 s / 124 MB |
| .dta read (ours, pandas) | dta | 0 ms / 0.00 s / 65 MB | 182 ms / 0.18 s / 141 MB | – |
| .dta write (ours, pandas) | dta | 1 ms / 0.00 s / 65 MB | 1 ms / 0.00 s / 142 MB | – |

### 2006_2010_FemPreg

20,492 rows, 287 columns; .dta 7.6 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 3 ms / 0.01 s / 94 MB | 8 ms / 0.01 s / 115 MB | 160 ms / 0.18 s / 189 MB |
| whole file | polars | 3 ms / 0.01 s / 94 MB | 9 ms / 0.01 s / 115 MB | 159 ms / 0.18 s / 190 MB |
| whole file | ours | 4 ms / 0.01 s / 95 MB | 8 ms / 0.01 s / 115 MB | 158 ms / 0.18 s / 190 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 69 MB | 2 ms / 0.01 s / 85 MB | 155 ms / 0.16 s / 152 MB |
| five columns | polars | 1 ms / 0.00 s / 69 MB | 2 ms / 0.01 s / 85 MB | 155 ms / 0.16 s / 152 MB |
| five columns | ours | 1 ms / 0.00 s / 69 MB | 2 ms / 0.01 s / 85 MB | 153 ms / 0.15 s / 152 MB |
| 1,000 rows | pyarrow | 2 ms / 0.00 s / 72 MB | 4 ms / 0.01 s / 87 MB | 5 ms / 0.03 s / 142 MB |
| 1,000 rows | polars | 2 ms / 0.00 s / 72 MB | 5 ms / 0.01 s / 86 MB | 5 ms / 0.03 s / 143 MB |
| 1,000 rows | ours | 2 ms / 0.00 s / 72 MB | 4 ms / 0.01 s / 87 MB | 5 ms / 0.02 s / 142 MB |
| read + pass | pyarrow | 7 ms / 0.02 s / 114 MB | 12 ms / 0.02 s / 124 MB | 165 ms / 0.18 s / 190 MB |
| read + pass | polars | 7 ms / 0.02 s / 114 MB | 12 ms / 0.02 s / 125 MB | 165 ms / 0.19 s / 191 MB |
| read + pass | ours | 7 ms / 0.02 s / 114 MB | 11 ms / 0.02 s / 125 MB | 162 ms / 0.18 s / 191 MB |
| write, defaults | write | 9 ms / 0.03 s / 123 MB | 10 ms / 0.06 s / 136 MB | 53 ms / 0.05 s / 161 MB |
| write, zstd 3 | write | 10 ms / 0.04 s / 128 MB | 10 ms / 0.06 s / 135 MB | 58 ms / 0.06 s / 161 MB |
| .dta read (ours, pandas) | dta | 15 ms / 0.02 s / 77 MB | 205 ms / 0.20 s / 178 MB | – |
| .dta write (ours, pandas) | dta | 48 ms / 0.05 s / 86 MB | 24 ms / 0.02 s / 188 MB | – |

### 2006_2010_FemResp

12,279 rows, 3,741 columns; .dta 55.6 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 19 ms / 0.06 s / 256 MB | 24 ms / 0.06 s / 298 MB | 204 ms / 0.36 s / 404 MB |
| whole file | polars | 19 ms / 0.07 s / 257 MB | 26 ms / 0.06 s / 298 MB | 204 ms / 0.38 s / 402 MB |
| whole file | ours | 25 ms / 0.07 s / 268 MB | 25 ms / 0.06 s / 302 MB | 202 ms / 0.36 s / 410 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 72 MB | 5 ms / 0.01 s / 94 MB | 164 ms / 0.16 s / 163 MB |
| five columns | polars | 3 ms / 0.00 s / 72 MB | 5 ms / 0.01 s / 94 MB | 163 ms / 0.16 s / 162 MB |
| five columns | ours | 5 ms / 0.01 s / 76 MB | 5 ms / 0.01 s / 99 MB | 161 ms / 0.16 s / 171 MB |
| 1,000 rows | pyarrow | 11 ms / 0.02 s / 100 MB | 13 ms / 0.03 s / 124 MB | 42 ms / 0.20 s / 351 MB |
| 1,000 rows | polars | 12 ms / 0.03 s / 101 MB | 16 ms / 0.03 s / 123 MB | 43 ms / 0.21 s / 350 MB |
| 1,000 rows | ours | 16 ms / 0.02 s / 112 MB | 13 ms / 0.03 s / 127 MB | 40 ms / 0.19 s / 353 MB |
| read + pass | pyarrow | 49 ms / 0.13 s / 310 MB | 52 ms / 0.11 s / 328 MB | 254 ms / 0.41 s / 405 MB |
| read + pass | polars | 50 ms / 0.13 s / 310 MB | 55 ms / 0.12 s / 328 MB | 255 ms / 0.43 s / 405 MB |
| read + pass | ours | 53 ms / 0.13 s / 322 MB | 54 ms / 0.12 s / 328 MB | 253 ms / 0.40 s / 411 MB |
| write, defaults | write | 39 ms / 0.25 s / 326 MB | 50 ms / 0.33 s / 358 MB | 334 ms / 0.33 s / 366 MB |
| write, zstd 3 | write | 39 ms / 0.27 s / 334 MB | 49 ms / 0.34 s / 358 MB | 362 ms / 0.36 s / 369 MB |
| .dta read (ours, pandas) | dta | 52 ms / 0.13 s / 158 MB | 298 ms / 0.35 s / 432 MB | – |
| .dta write (ours, pandas) | dta | 188 ms / 0.37 s / 183 MB | 172 ms / 0.27 s / 457 MB | – |

### 2006_2010_Male

10,403 rows, 2,801 columns; .dta 37.2 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 14 ms / 0.03 s / 186 MB | 21 ms / 0.04 s / 241 MB | 192 ms / 0.30 s / 339 MB |
| whole file | polars | 15 ms / 0.04 s / 187 MB | 24 ms / 0.04 s / 241 MB | 195 ms / 0.31 s / 342 MB |
| whole file | ours | 16 ms / 0.04 s / 191 MB | 21 ms / 0.04 s / 243 MB | 193 ms / 0.29 s / 343 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 71 MB | 5 ms / 0.01 s / 91 MB | 161 ms / 0.16 s / 160 MB |
| five columns | polars | 2 ms / 0.00 s / 68 MB | 4 ms / 0.01 s / 91 MB | 162 ms / 0.16 s / 160 MB |
| five columns | ours | 3 ms / 0.00 s / 70 MB | 4 ms / 0.01 s / 92 MB | 165 ms / 0.17 s / 163 MB |
| 1,000 rows | pyarrow | 9 ms / 0.02 s / 93 MB | 11 ms / 0.02 s / 111 MB | 34 ms / 0.14 s / 288 MB |
| 1,000 rows | polars | 9 ms / 0.02 s / 93 MB | 13 ms / 0.03 s / 110 MB | 38 ms / 0.14 s / 289 MB |
| 1,000 rows | ours | 12 ms / 0.02 s / 98 MB | 11 ms / 0.02 s / 112 MB | 32 ms / 0.13 s / 291 MB |
| read + pass | pyarrow | 38 ms / 0.08 s / 231 MB | 45 ms / 0.08 s / 266 MB | 247 ms / 0.35 s / 343 MB |
| read + pass | polars | 41 ms / 0.09 s / 230 MB | 51 ms / 0.09 s / 265 MB | 254 ms / 0.35 s / 347 MB |
| read + pass | ours | 45 ms / 0.08 s / 235 MB | 49 ms / 0.08 s / 266 MB | 237 ms / 0.33 s / 343 MB |
| write, defaults | write | 29 ms / 0.15 s / 260 MB | 37 ms / 0.21 s / 288 MB | 195 ms / 0.19 s / 303 MB |
| write, zstd 3 | write | 29 ms / 0.16 s / 267 MB | 34 ms / 0.21 s / 287 MB | 208 ms / 0.21 s / 304 MB |
| .dta read (ours, pandas) | dta | 32 ms / 0.08 s / 130 MB | 262 ms / 0.30 s / 372 MB | – |
| .dta write (ours, pandas) | dta | 109 ms / 0.21 s / 154 MB | 116 ms / 0.17 s / 396 MB | – |

### 2011_2013_FemPreg

9,543 rows, 278 columns; .dta 3.5 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 3 ms / 0.01 s / 80 MB | 9 ms / 0.01 s / 96 MB | 169 ms / 0.18 s / 170 MB |
| whole file | polars | 2 ms / 0.01 s / 80 MB | 6 ms / 0.01 s / 96 MB | 163 ms / 0.18 s / 171 MB |
| whole file | ours | 2 ms / 0.01 s / 81 MB | 5 ms / 0.01 s / 97 MB | 158 ms / 0.17 s / 171 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 67 MB | 2 ms / 0.01 s / 84 MB | 159 ms / 0.16 s / 152 MB |
| five columns | polars | 1 ms / 0.00 s / 67 MB | 2 ms / 0.01 s / 84 MB | 157 ms / 0.16 s / 152 MB |
| five columns | ours | 1 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 84 MB | 153 ms / 0.15 s / 152 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 85 MB | 4 ms / 0.02 s / 123 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 70 MB | 4 ms / 0.01 s / 85 MB | 4 ms / 0.02 s / 124 MB |
| 1,000 rows | ours | 2 ms / 0.00 s / 72 MB | 3 ms / 0.01 s / 85 MB | 4 ms / 0.02 s / 124 MB |
| read + pass | pyarrow | 6 ms / 0.02 s / 96 MB | 8 ms / 0.02 s / 104 MB | 165 ms / 0.18 s / 172 MB |
| read + pass | polars | 6 ms / 0.02 s / 98 MB | 9 ms / 0.02 s / 104 MB | 165 ms / 0.18 s / 172 MB |
| read + pass | ours | 7 ms / 0.01 s / 95 MB | 14 ms / 0.02 s / 102 MB | 180 ms / 0.19 s / 171 MB |
| write, defaults | write | 11 ms / 0.03 s / 103 MB | 10 ms / 0.03 s / 108 MB | 27 ms / 0.03 s / 142 MB |
| write, zstd 3 | write | 7 ms / 0.03 s / 104 MB | 10 ms / 0.03 s / 108 MB | 30 ms / 0.03 s / 142 MB |
| .dta read (ours, pandas) | dta | 8 ms / 0.01 s / 73 MB | 195 ms / 0.19 s / 160 MB | – |
| .dta write (ours, pandas) | dta | 23 ms / 0.02 s / 77 MB | 15 ms / 0.02 s / 165 MB | – |

### 2011_2013_FemResp

5,601 rows, 3,094 columns; .dta 22.6 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 13 ms / 0.03 s / 153 MB | 24 ms / 0.03 s / 178 MB | 204 ms / 0.30 s / 303 MB |
| whole file | polars | 14 ms / 0.04 s / 153 MB | 29 ms / 0.03 s / 177 MB | 203 ms / 0.31 s / 305 MB |
| whole file | ours | 17 ms / 0.04 s / 158 MB | 24 ms / 0.03 s / 179 MB | 207 ms / 0.30 s / 308 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 68 MB | 6 ms / 0.01 s / 91 MB | 256 ms / 0.20 s / 159 MB |
| five columns | polars | 2 ms / 0.00 s / 68 MB | 4 ms / 0.01 s / 91 MB | 161 ms / 0.16 s / 160 MB |
| five columns | ours | 4 ms / 0.00 s / 70 MB | 5 ms / 0.01 s / 92 MB | 166 ms / 0.17 s / 163 MB |
| 1,000 rows | pyarrow | 9 ms / 0.02 s / 95 MB | 15 ms / 0.02 s / 112 MB | 34 ms / 0.14 s / 252 MB |
| 1,000 rows | polars | 10 ms / 0.02 s / 96 MB | 20 ms / 0.03 s / 112 MB | 39 ms / 0.14 s / 253 MB |
| 1,000 rows | ours | 13 ms / 0.02 s / 101 MB | 18 ms / 0.02 s / 114 MB | 45 ms / 0.13 s / 268 MB |
| read + pass | pyarrow | 40 ms / 0.07 s / 190 MB | 59 ms / 0.08 s / 201 MB | 247 ms / 0.33 s / 310 MB |
| read + pass | polars | 38 ms / 0.08 s / 190 MB | 52 ms / 0.07 s / 201 MB | 237 ms / 0.34 s / 306 MB |
| read + pass | ours | 39 ms / 0.07 s / 195 MB | 49 ms / 0.07 s / 202 MB | 238 ms / 0.33 s / 311 MB |
| write, defaults | write | 32 ms / 0.12 s / 193 MB | 36 ms / 0.17 s / 223 MB | 180 ms / 0.18 s / 239 MB |
| write, zstd 3 | write | 32 ms / 0.14 s / 196 MB | 34 ms / 0.16 s / 223 MB | 211 ms / 0.20 s / 239 MB |
| .dta read (ours, pandas) | dta | 24 ms / 0.06 s / 114 MB | 242 ms / 0.26 s / 271 MB | – |
| .dta write (ours, pandas) | dta | 80 ms / 0.15 s / 139 MB | 107 ms / 0.14 s / 295 MB | – |

### 2011_2013_Male

4,815 rows, 3,059 columns; .dta 19.4 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 10 ms / 0.02 s / 141 MB | 20 ms / 0.02 s / 162 MB | 190 ms / 0.29 s / 264 MB |
| whole file | polars | 11 ms / 0.03 s / 142 MB | 23 ms / 0.03 s / 161 MB | 189 ms / 0.29 s / 264 MB |
| whole file | ours | 13 ms / 0.03 s / 146 MB | 19 ms / 0.02 s / 163 MB | 198 ms / 0.28 s / 271 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 69 MB | 5 ms / 0.01 s / 91 MB | 170 ms / 0.17 s / 160 MB |
| five columns | polars | 2 ms / 0.00 s / 68 MB | 5 ms / 0.01 s / 90 MB | 170 ms / 0.17 s / 161 MB |
| five columns | ours | 3 ms / 0.00 s / 70 MB | 6 ms / 0.01 s / 92 MB | 170 ms / 0.17 s / 163 MB |
| 1,000 rows | pyarrow | 9 ms / 0.02 s / 96 MB | 14 ms / 0.02 s / 110 MB | 31 ms / 0.12 s / 213 MB |
| 1,000 rows | polars | 9 ms / 0.02 s / 95 MB | 17 ms / 0.02 s / 110 MB | 31 ms / 0.13 s / 213 MB |
| 1,000 rows | ours | 11 ms / 0.02 s / 100 MB | 13 ms / 0.02 s / 111 MB | 30 ms / 0.11 s / 215 MB |
| read + pass | pyarrow | 62 ms / 0.06 s / 178 MB | 47 ms / 0.06 s / 187 MB | 238 ms / 0.31 s / 267 MB |
| read + pass | polars | 37 ms / 0.06 s / 179 MB | 48 ms / 0.06 s / 186 MB | 242 ms / 0.34 s / 266 MB |
| read + pass | ours | 37 ms / 0.07 s / 185 MB | 42 ms / 0.06 s / 187 MB | 227 ms / 0.31 s / 268 MB |
| write, defaults | write | 22 ms / 0.09 s / 176 MB | 29 ms / 0.13 s / 205 MB | 122 ms / 0.12 s / 223 MB |
| write, zstd 3 | write | 26 ms / 0.11 s / 179 MB | 29 ms / 0.14 s / 205 MB | 135 ms / 0.14 s / 222 MB |
| .dta read (ours, pandas) | dta | 20 ms / 0.04 s / 110 MB | 237 ms / 0.25 s / 259 MB | – |
| .dta write (ours, pandas) | dta | 62 ms / 0.12 s / 132 MB | 96 ms / 0.12 s / 281 MB | – |

### 2011_2019_FemaleWgt

22,995 rows, 7 columns; .dta 1.2 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 1 ms / 0.00 s / 70 MB | 2 ms / 0.01 s / 85 MB | 152 ms / 0.15 s / 154 MB |
| whole file | polars | 1 ms / 0.00 s / 69 MB | 2 ms / 0.01 s / 84 MB | 153 ms / 0.15 s / 153 MB |
| whole file | ours | 1 ms / 0.00 s / 69 MB | 2 ms / 0.01 s / 84 MB | 153 ms / 0.15 s / 153 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 70 MB | 2 ms / 0.01 s / 85 MB | 152 ms / 0.15 s / 153 MB |
| five columns | polars | 1 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 84 MB | 152 ms / 0.15 s / 152 MB |
| five columns | ours | 1 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 84 MB | 153 ms / 0.15 s / 152 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 69 MB | 2 ms / 0.01 s / 83 MB | 1 ms / 0.00 s / 107 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 82 MB | 1 ms / 0.00 s / 106 MB |
| 1,000 rows | ours | 0 ms / 0.00 s / 68 MB | 1 ms / 0.01 s / 82 MB | 1 ms / 0.00 s / 106 MB |
| read + pass | pyarrow | 2 ms / 0.01 s / 82 MB | 2 ms / 0.01 s / 88 MB | 153 ms / 0.15 s / 155 MB |
| read + pass | polars | 2 ms / 0.01 s / 81 MB | 3 ms / 0.01 s / 87 MB | 154 ms / 0.16 s / 154 MB |
| read + pass | ours | 2 ms / 0.01 s / 80 MB | 2 ms / 0.01 s / 87 MB | 152 ms / 0.15 s / 154 MB |
| write, defaults | write | 1 ms / 0.00 s / 91 MB | 2 ms / 0.01 s / 93 MB | 5 ms / 0.00 s / 133 MB |
| write, zstd 3 | write | 2 ms / 0.00 s / 95 MB | 2 ms / 0.01 s / 93 MB | 5 ms / 0.01 s / 133 MB |
| .dta read (ours, pandas) | dta | 1 ms / 0.00 s / 67 MB | 186 ms / 0.18 s / 144 MB | – |
| .dta write (ours, pandas) | dta | 1 ms / 0.00 s / 68 MB | 1 ms / 0.00 s / 145 MB | – |

### 2011_2019_MaleWgt

19,067 rows, 7 columns; .dta 1.0 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 1 ms / 0.00 s / 69 MB | 2 ms / 0.01 s / 84 MB | 154 ms / 0.16 s / 154 MB |
| whole file | polars | 1 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 83 MB | 154 ms / 0.16 s / 154 MB |
| whole file | ours | 1 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 83 MB | 153 ms / 0.15 s / 153 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 69 MB | 2 ms / 0.01 s / 84 MB | 154 ms / 0.15 s / 153 MB |
| five columns | polars | 1 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 84 MB | 153 ms / 0.15 s / 152 MB |
| five columns | ours | 0 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 84 MB | 153 ms / 0.15 s / 152 MB |
| 1,000 rows | pyarrow | 0 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 83 MB | 1 ms / 0.00 s / 108 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 82 MB | 1 ms / 0.00 s / 107 MB |
| 1,000 rows | ours | 0 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 82 MB | 1 ms / 0.00 s / 107 MB |
| read + pass | pyarrow | 2 ms / 0.01 s / 81 MB | 2 ms / 0.01 s / 87 MB | 155 ms / 0.16 s / 155 MB |
| read + pass | polars | 2 ms / 0.01 s / 80 MB | 3 ms / 0.01 s / 86 MB | 154 ms / 0.16 s / 155 MB |
| read + pass | ours | 1 ms / 0.01 s / 79 MB | 2 ms / 0.01 s / 86 MB | 153 ms / 0.15 s / 154 MB |
| write, defaults | write | 1 ms / 0.00 s / 91 MB | 2 ms / 0.00 s / 92 MB | 4 ms / 0.00 s / 130 MB |
| write, zstd 3 | write | 1 ms / 0.00 s / 94 MB | 1 ms / 0.00 s / 93 MB | 5 ms / 0.00 s / 131 MB |
| .dta read (ours, pandas) | dta | 1 ms / 0.00 s / 68 MB | 185 ms / 0.18 s / 143 MB | – |
| .dta write (ours, pandas) | dta | 1 ms / 0.00 s / 67 MB | 1 ms / 0.00 s / 145 MB | – |

### 2013_2015_FemPreg

9,358 rows, 278 columns; .dta 3.4 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 2 ms / 0.00 s / 80 MB | 5 ms / 0.01 s / 96 MB | 156 ms / 0.17 s / 171 MB |
| whole file | polars | 2 ms / 0.01 s / 80 MB | 5 ms / 0.01 s / 96 MB | 157 ms / 0.17 s / 171 MB |
| whole file | ours | 2 ms / 0.01 s / 81 MB | 5 ms / 0.01 s / 96 MB | 156 ms / 0.17 s / 170 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 67 MB | 2 ms / 0.01 s / 84 MB | 155 ms / 0.16 s / 152 MB |
| five columns | polars | 1 ms / 0.00 s / 67 MB | 2 ms / 0.01 s / 84 MB | 153 ms / 0.15 s / 152 MB |
| five columns | ours | 1 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 84 MB | 153 ms / 0.15 s / 152 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 85 MB | 4 ms / 0.02 s / 124 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 70 MB | 4 ms / 0.01 s / 85 MB | 4 ms / 0.02 s / 123 MB |
| 1,000 rows | ours | 2 ms / 0.00 s / 72 MB | 3 ms / 0.01 s / 85 MB | 3 ms / 0.02 s / 124 MB |
| read + pass | pyarrow | 5 ms / 0.02 s / 98 MB | 7 ms / 0.02 s / 104 MB | 162 ms / 0.18 s / 172 MB |
| read + pass | polars | 6 ms / 0.02 s / 97 MB | 8 ms / 0.02 s / 104 MB | 160 ms / 0.17 s / 172 MB |
| read + pass | ours | 6 ms / 0.02 s / 98 MB | 7 ms / 0.02 s / 104 MB | 158 ms / 0.17 s / 172 MB |
| write, defaults | write | 5 ms / 0.02 s / 102 MB | 6 ms / 0.03 s / 111 MB | 26 ms / 0.03 s / 141 MB |
| write, zstd 3 | write | 6 ms / 0.02 s / 104 MB | 7 ms / 0.03 s / 110 MB | 29 ms / 0.03 s / 141 MB |
| .dta read (ours, pandas) | dta | 8 ms / 0.01 s / 73 MB | 196 ms / 0.19 s / 161 MB | – |
| .dta write (ours, pandas) | dta | 22 ms / 0.02 s / 77 MB | 15 ms / 0.02 s / 164 MB | – |

### 2013_2015_FemResp

5,699 rows, 3,207 columns; .dta 24.0 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 13 ms / 0.03 s / 157 MB | 24 ms / 0.03 s / 181 MB | 200 ms / 0.30 s / 308 MB |
| whole file | polars | 13 ms / 0.03 s / 157 MB | 30 ms / 0.04 s / 180 MB | 196 ms / 0.30 s / 310 MB |
| whole file | ours | 18 ms / 0.04 s / 163 MB | 24 ms / 0.03 s / 183 MB | 209 ms / 0.30 s / 314 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 68 MB | 5 ms / 0.01 s / 91 MB | 171 ms / 0.17 s / 161 MB |
| five columns | polars | 2 ms / 0.00 s / 68 MB | 5 ms / 0.01 s / 91 MB | 170 ms / 0.17 s / 160 MB |
| five columns | ours | 4 ms / 0.00 s / 71 MB | 5 ms / 0.01 s / 94 MB | 170 ms / 0.17 s / 167 MB |
| 1,000 rows | pyarrow | 11 ms / 0.02 s / 96 MB | 16 ms / 0.02 s / 113 MB | 40 ms / 0.13 s / 262 MB |
| 1,000 rows | polars | 16 ms / 0.02 s / 97 MB | 37 ms / 0.03 s / 112 MB | 37 ms / 0.15 s / 258 MB |
| 1,000 rows | ours | 13 ms / 0.02 s / 102 MB | 15 ms / 0.02 s / 115 MB | 33 ms / 0.13 s / 260 MB |
| read + pass | pyarrow | 38 ms / 0.08 s / 196 MB | 49 ms / 0.07 s / 206 MB | 241 ms / 0.34 s / 312 MB |
| read + pass | polars | 38 ms / 0.08 s / 195 MB | 53 ms / 0.08 s / 205 MB | 243 ms / 0.35 s / 313 MB |
| read + pass | ours | 45 ms / 0.08 s / 201 MB | 66 ms / 0.08 s / 205 MB | 246 ms / 0.33 s / 317 MB |
| write, defaults | write | 43 ms / 0.15 s / 196 MB | 35 ms / 0.17 s / 227 MB | 176 ms / 0.18 s / 243 MB |
| write, zstd 3 | write | 37 ms / 0.15 s / 199 MB | 40 ms / 0.19 s / 227 MB | 196 ms / 0.20 s / 243 MB |
| .dta read (ours, pandas) | dta | 25 ms / 0.06 s / 118 MB | 246 ms / 0.27 s / 277 MB | – |
| .dta write (ours, pandas) | dta | 87 ms / 0.17 s / 143 MB | 115 ms / 0.15 s / 302 MB | – |

### 2013_2015_Male

4,506 rows, 2,940 columns; .dta 18.0 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 10 ms / 0.02 s / 136 MB | 19 ms / 0.02 s / 159 MB | 188 ms / 0.27 s / 260 MB |
| whole file | polars | 11 ms / 0.03 s / 137 MB | 22 ms / 0.03 s / 159 MB | 188 ms / 0.28 s / 259 MB |
| whole file | ours | 13 ms / 0.02 s / 141 MB | 18 ms / 0.02 s / 161 MB | 188 ms / 0.27 s / 263 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 68 MB | 4 ms / 0.01 s / 90 MB | 159 ms / 0.16 s / 160 MB |
| five columns | polars | 2 ms / 0.00 s / 68 MB | 4 ms / 0.01 s / 90 MB | 159 ms / 0.16 s / 159 MB |
| five columns | ours | 3 ms / 0.00 s / 70 MB | 4 ms / 0.01 s / 93 MB | 161 ms / 0.16 s / 163 MB |
| 1,000 rows | pyarrow | 8 ms / 0.02 s / 95 MB | 13 ms / 0.02 s / 109 MB | 28 ms / 0.11 s / 207 MB |
| 1,000 rows | polars | 9 ms / 0.02 s / 94 MB | 16 ms / 0.02 s / 109 MB | 28 ms / 0.12 s / 208 MB |
| 1,000 rows | ours | 11 ms / 0.02 s / 99 MB | 12 ms / 0.02 s / 111 MB | 26 ms / 0.10 s / 210 MB |
| read + pass | pyarrow | 32 ms / 0.06 s / 173 MB | 41 ms / 0.06 s / 183 MB | 222 ms / 0.31 s / 264 MB |
| read + pass | polars | 33 ms / 0.06 s / 173 MB | 45 ms / 0.06 s / 183 MB | 233 ms / 0.31 s / 263 MB |
| read + pass | ours | 38 ms / 0.07 s / 178 MB | 41 ms / 0.06 s / 183 MB | 225 ms / 0.30 s / 265 MB |
| write, defaults | write | 21 ms / 0.09 s / 172 MB | 27 ms / 0.12 s / 201 MB | 115 ms / 0.12 s / 219 MB |
| write, zstd 3 | write | 26 ms / 0.10 s / 174 MB | 28 ms / 0.12 s / 201 MB | 136 ms / 0.13 s / 219 MB |
| .dta read (ours, pandas) | dta | 32 ms / 0.03 s / 98 MB | 251 ms / 0.25 s / 247 MB | – |
| .dta write (ours, pandas) | dta | 103 ms / 0.10 s / 115 MB | 116 ms / 0.12 s / 263 MB | – |

### 2015_2017_FemPreg

9,553 rows, 248 columns; .dta 3.0 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 2 ms / 0.00 s / 79 MB | 4 ms / 0.01 s / 95 MB | 156 ms / 0.17 s / 169 MB |
| whole file | polars | 2 ms / 0.00 s / 79 MB | 5 ms / 0.01 s / 95 MB | 157 ms / 0.17 s / 169 MB |
| whole file | ours | 2 ms / 0.00 s / 79 MB | 4 ms / 0.01 s / 95 MB | 159 ms / 0.17 s / 169 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 67 MB | 2 ms / 0.01 s / 84 MB | 153 ms / 0.15 s / 152 MB |
| five columns | polars | 1 ms / 0.00 s / 67 MB | 2 ms / 0.01 s / 84 MB | 155 ms / 0.16 s / 152 MB |
| five columns | ours | 1 ms / 0.00 s / 67 MB | 2 ms / 0.01 s / 84 MB | 153 ms / 0.15 s / 152 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 69 MB | 3 ms / 0.01 s / 85 MB | 3 ms / 0.02 s / 121 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 69 MB | 4 ms / 0.01 s / 85 MB | 4 ms / 0.02 s / 122 MB |
| 1,000 rows | ours | 2 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 85 MB | 3 ms / 0.01 s / 121 MB |
| read + pass | pyarrow | 5 ms / 0.02 s / 95 MB | 7 ms / 0.02 s / 102 MB | 160 ms / 0.17 s / 170 MB |
| read + pass | polars | 5 ms / 0.02 s / 93 MB | 7 ms / 0.02 s / 102 MB | 159 ms / 0.17 s / 170 MB |
| read + pass | ours | 5 ms / 0.02 s / 96 MB | 7 ms / 0.02 s / 102 MB | 161 ms / 0.17 s / 169 MB |
| write, defaults | write | 4 ms / 0.02 s / 100 MB | 5 ms / 0.03 s / 107 MB | 23 ms / 0.02 s / 140 MB |
| write, zstd 3 | write | 5 ms / 0.02 s / 102 MB | 5 ms / 0.03 s / 107 MB | 25 ms / 0.03 s / 140 MB |
| .dta read (ours, pandas) | dta | 7 ms / 0.01 s / 72 MB | 195 ms / 0.19 s / 158 MB | – |
| .dta write (ours, pandas) | dta | 20 ms / 0.02 s / 76 MB | 14 ms / 0.01 s / 164 MB | – |

### 2015_2017_FemResp

5,554 rows, 3,024 columns; .dta 21.7 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 12 ms / 0.03 s / 150 MB | 23 ms / 0.03 s / 174 MB | 189 ms / 0.29 s / 299 MB |
| whole file | polars | 13 ms / 0.03 s / 150 MB | 27 ms / 0.03 s / 174 MB | 189 ms / 0.30 s / 299 MB |
| whole file | ours | 15 ms / 0.03 s / 156 MB | 23 ms / 0.03 s / 177 MB | 189 ms / 0.29 s / 302 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 68 MB | 4 ms / 0.01 s / 91 MB | 160 ms / 0.16 s / 159 MB |
| five columns | polars | 2 ms / 0.00 s / 69 MB | 4 ms / 0.01 s / 90 MB | 161 ms / 0.16 s / 160 MB |
| five columns | ours | 4 ms / 0.00 s / 71 MB | 4 ms / 0.01 s / 93 MB | 159 ms / 0.16 s / 165 MB |
| 1,000 rows | pyarrow | 9 ms / 0.02 s / 94 MB | 15 ms / 0.02 s / 111 MB | 30 ms / 0.13 s / 247 MB |
| 1,000 rows | polars | 9 ms / 0.02 s / 95 MB | 19 ms / 0.02 s / 110 MB | 30 ms / 0.14 s / 247 MB |
| 1,000 rows | ours | 12 ms / 0.02 s / 101 MB | 14 ms / 0.02 s / 112 MB | 29 ms / 0.13 s / 250 MB |
| read + pass | pyarrow | 34 ms / 0.07 s / 187 MB | 45 ms / 0.06 s / 199 MB | 224 ms / 0.33 s / 299 MB |
| read + pass | polars | 35 ms / 0.07 s / 187 MB | 49 ms / 0.07 s / 199 MB | 223 ms / 0.34 s / 300 MB |
| read + pass | ours | 38 ms / 0.07 s / 193 MB | 44 ms / 0.06 s / 198 MB | 222 ms / 0.32 s / 304 MB |
| write, defaults | write | 23 ms / 0.12 s / 190 MB | 29 ms / 0.16 s / 220 MB | 164 ms / 0.16 s / 237 MB |
| write, zstd 3 | write | 26 ms / 0.14 s / 193 MB | 31 ms / 0.17 s / 219 MB | 179 ms / 0.18 s / 236 MB |
| .dta read (ours, pandas) | dta | 25 ms / 0.06 s / 113 MB | 240 ms / 0.26 s / 268 MB | – |
| .dta write (ours, pandas) | dta | 81 ms / 0.15 s / 138 MB | 105 ms / 0.14 s / 291 MB | – |

### 2015_2017_Male

4,540 rows, 2,945 columns; .dta 17.7 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 10 ms / 0.02 s / 136 MB | 19 ms / 0.02 s / 159 MB | 186 ms / 0.28 s / 260 MB |
| whole file | polars | 10 ms / 0.02 s / 136 MB | 21 ms / 0.03 s / 159 MB | 186 ms / 0.28 s / 261 MB |
| whole file | ours | 13 ms / 0.02 s / 141 MB | 18 ms / 0.02 s / 161 MB | 185 ms / 0.26 s / 262 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 69 MB | 4 ms / 0.01 s / 91 MB | 160 ms / 0.16 s / 159 MB |
| five columns | polars | 2 ms / 0.00 s / 68 MB | 4 ms / 0.01 s / 90 MB | 160 ms / 0.16 s / 160 MB |
| five columns | ours | 3 ms / 0.00 s / 70 MB | 4 ms / 0.01 s / 93 MB | 160 ms / 0.16 s / 163 MB |
| 1,000 rows | pyarrow | 8 ms / 0.02 s / 94 MB | 13 ms / 0.02 s / 109 MB | 28 ms / 0.12 s / 207 MB |
| 1,000 rows | polars | 9 ms / 0.02 s / 94 MB | 16 ms / 0.02 s / 109 MB | 28 ms / 0.13 s / 208 MB |
| 1,000 rows | ours | 11 ms / 0.02 s / 99 MB | 12 ms / 0.02 s / 111 MB | 26 ms / 0.10 s / 209 MB |
| read + pass | pyarrow | 32 ms / 0.06 s / 173 MB | 39 ms / 0.06 s / 184 MB | 215 ms / 0.31 s / 261 MB |
| read + pass | polars | 33 ms / 0.06 s / 174 MB | 43 ms / 0.06 s / 184 MB | 216 ms / 0.31 s / 262 MB |
| read + pass | ours | 35 ms / 0.06 s / 179 MB | 38 ms / 0.06 s / 183 MB | 214 ms / 0.30 s / 263 MB |
| write, defaults | write | 19 ms / 0.09 s / 172 MB | 23 ms / 0.12 s / 202 MB | 113 ms / 0.11 s / 220 MB |
| write, zstd 3 | write | 21 ms / 0.10 s / 175 MB | 23 ms / 0.12 s / 201 MB | 124 ms / 0.12 s / 218 MB |
| .dta read (ours, pandas) | dta | 32 ms / 0.03 s / 98 MB | 247 ms / 0.25 s / 248 MB | – |
| .dta write (ours, pandas) | dta | 102 ms / 0.10 s / 113 MB | 116 ms / 0.12 s / 262 MB | – |

### 2017_2019_FemPreg

10,215 rows, 171 columns; .dta 2.2 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 1 ms / 0.00 s / 75 MB | 4 ms / 0.01 s / 90 MB | 152 ms / 0.16 s / 163 MB |
| whole file | polars | 2 ms / 0.00 s / 75 MB | 4 ms / 0.01 s / 90 MB | 156 ms / 0.17 s / 163 MB |
| whole file | ours | 2 ms / 0.00 s / 76 MB | 4 ms / 0.01 s / 90 MB | 154 ms / 0.16 s / 163 MB |
| five columns | pyarrow | 0 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 83 MB | 154 ms / 0.15 s / 151 MB |
| five columns | polars | 0 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 84 MB | 152 ms / 0.15 s / 151 MB |
| five columns | ours | 1 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 84 MB | 153 ms / 0.15 s / 151 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 68 MB | 3 ms / 0.01 s / 84 MB | 3 ms / 0.01 s / 116 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 68 MB | 3 ms / 0.01 s / 83 MB | 3 ms / 0.01 s / 116 MB |
| 1,000 rows | ours | 1 ms / 0.00 s / 69 MB | 3 ms / 0.01 s / 84 MB | 2 ms / 0.01 s / 116 MB |
| read + pass | pyarrow | 4 ms / 0.01 s / 91 MB | 6 ms / 0.01 s / 97 MB | 160 ms / 0.17 s / 164 MB |
| read + pass | polars | 4 ms / 0.01 s / 90 MB | 6 ms / 0.01 s / 97 MB | 157 ms / 0.17 s / 164 MB |
| read + pass | ours | 4 ms / 0.01 s / 91 MB | 6 ms / 0.01 s / 97 MB | 157 ms / 0.17 s / 164 MB |
| write, defaults | write | 4 ms / 0.01 s / 95 MB | 4 ms / 0.02 s / 101 MB | 19 ms / 0.02 s / 134 MB |
| write, zstd 3 | write | 4 ms / 0.01 s / 97 MB | 4 ms / 0.02 s / 101 MB | 20 ms / 0.02 s / 134 MB |
| .dta read (ours, pandas) | dta | 6 ms / 0.01 s / 71 MB | 191 ms / 0.19 s / 152 MB | – |
| .dta write (ours, pandas) | dta | 18 ms / 0.02 s / 74 MB | 10 ms / 0.01 s / 153 MB | – |

### 2017_2019_FemResp

6,141 rows, 2,609 columns; .dta 20.2 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 11 ms / 0.03 s / 145 MB | 23 ms / 0.03 s / 163 MB | 193 ms / 0.28 s / 279 MB |
| whole file | polars | 12 ms / 0.03 s / 146 MB | 27 ms / 0.03 s / 162 MB | 189 ms / 0.29 s / 279 MB |
| whole file | ours | 14 ms / 0.03 s / 151 MB | 23 ms / 0.03 s / 164 MB | 188 ms / 0.28 s / 284 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 68 MB | 4 ms / 0.01 s / 90 MB | 161 ms / 0.16 s / 158 MB |
| five columns | polars | 2 ms / 0.00 s / 68 MB | 4 ms / 0.01 s / 90 MB | 160 ms / 0.16 s / 158 MB |
| five columns | ours | 3 ms / 0.00 s / 70 MB | 4 ms / 0.01 s / 92 MB | 163 ms / 0.16 s / 162 MB |
| 1,000 rows | pyarrow | 8 ms / 0.02 s / 91 MB | 14 ms / 0.02 s / 107 MB | 27 ms / 0.11 s / 229 MB |
| 1,000 rows | polars | 9 ms / 0.02 s / 92 MB | 18 ms / 0.02 s / 107 MB | 28 ms / 0.13 s / 229 MB |
| 1,000 rows | ours | 11 ms / 0.02 s / 97 MB | 14 ms / 0.02 s / 109 MB | 27 ms / 0.12 s / 232 MB |
| read + pass | pyarrow | 31 ms / 0.07 s / 179 MB | 43 ms / 0.06 s / 184 MB | 217 ms / 0.30 s / 281 MB |
| read + pass | polars | 32 ms / 0.07 s / 180 MB | 46 ms / 0.06 s / 184 MB | 222 ms / 0.32 s / 283 MB |
| read + pass | ours | 34 ms / 0.07 s / 185 MB | 42 ms / 0.06 s / 184 MB | 218 ms / 0.31 s / 284 MB |
| write, defaults | write | 22 ms / 0.12 s / 177 MB | 29 ms / 0.16 s / 204 MB | 163 ms / 0.16 s / 220 MB |
| write, zstd 3 | write | 25 ms / 0.13 s / 179 MB | 32 ms / 0.16 s / 204 MB | 179 ms / 0.18 s / 220 MB |
| .dta read (ours, pandas) | dta | 24 ms / 0.05 s / 111 MB | 239 ms / 0.26 s / 252 MB | – |
| .dta write (ours, pandas) | dta | 79 ms / 0.15 s / 136 MB | 96 ms / 0.13 s / 276 MB | – |

### 2017_2019_Male

5,206 rows, 3,009 columns; .dta 20.1 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 11 ms / 0.03 s / 144 MB | 20 ms / 0.02 s / 173 MB | 188 ms / 0.28 s / 296 MB |
| whole file | polars | 11 ms / 0.03 s / 144 MB | 23 ms / 0.03 s / 172 MB | 189 ms / 0.29 s / 297 MB |
| whole file | ours | 14 ms / 0.03 s / 150 MB | 20 ms / 0.02 s / 175 MB | 189 ms / 0.28 s / 299 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 68 MB | 4 ms / 0.01 s / 91 MB | 159 ms / 0.16 s / 159 MB |
| five columns | polars | 2 ms / 0.00 s / 68 MB | 4 ms / 0.01 s / 90 MB | 160 ms / 0.16 s / 160 MB |
| five columns | ours | 3 ms / 0.00 s / 70 MB | 4 ms / 0.01 s / 93 MB | 160 ms / 0.16 s / 163 MB |
| 1,000 rows | pyarrow | 9 ms / 0.02 s / 94 MB | 13 ms / 0.02 s / 109 MB | 28 ms / 0.12 s / 244 MB |
| 1,000 rows | polars | 9 ms / 0.02 s / 95 MB | 16 ms / 0.02 s / 109 MB | 28 ms / 0.13 s / 245 MB |
| 1,000 rows | ours | 12 ms / 0.02 s / 100 MB | 13 ms / 0.02 s / 111 MB | 27 ms / 0.12 s / 246 MB |
| read + pass | pyarrow | 33 ms / 0.06 s / 181 MB | 42 ms / 0.06 s / 196 MB | 216 ms / 0.32 s / 298 MB |
| read + pass | polars | 33 ms / 0.06 s / 181 MB | 44 ms / 0.06 s / 197 MB | 219 ms / 0.32 s / 297 MB |
| read + pass | ours | 37 ms / 0.07 s / 187 MB | 41 ms / 0.06 s / 197 MB | 218 ms / 0.30 s / 299 MB |
| write, defaults | write | 18 ms / 0.09 s / 188 MB | 26 ms / 0.13 s / 216 MB | 123 ms / 0.12 s / 233 MB |
| write, zstd 3 | write | 20 ms / 0.10 s / 190 MB | 23 ms / 0.12 s / 215 MB | 134 ms / 0.13 s / 233 MB |
| .dta read (ours, pandas) | dta | 21 ms / 0.04 s / 112 MB | 239 ms / 0.26 s / 278 MB | – |
| .dta write (ours, pandas) | dta | 64 ms / 0.12 s / 135 MB | 99 ms / 0.13 s / 301 MB | – |

### 2022_2023_FemPreg

8,247 rows, 111 columns; .dta 1.2 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 1 ms / 0.00 s / 71 MB | 3 ms / 0.01 s / 87 MB | 155 ms / 0.16 s / 159 MB |
| whole file | polars | 1 ms / 0.00 s / 71 MB | 3 ms / 0.01 s / 87 MB | 154 ms / 0.16 s / 159 MB |
| whole file | ours | 1 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 87 MB | 155 ms / 0.16 s / 159 MB |
| five columns | pyarrow | 0 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 83 MB | 152 ms / 0.15 s / 151 MB |
| five columns | polars | 0 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 83 MB | 153 ms / 0.15 s / 151 MB |
| five columns | ours | 0 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 83 MB | 155 ms / 0.16 s / 151 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 67 MB | 2 ms / 0.01 s / 83 MB | 2 ms / 0.01 s / 112 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 67 MB | 3 ms / 0.01 s / 83 MB | 2 ms / 0.01 s / 112 MB |
| 1,000 rows | ours | 1 ms / 0.00 s / 67 MB | 2 ms / 0.01 s / 83 MB | 2 ms / 0.01 s / 112 MB |
| read + pass | pyarrow | 3 ms / 0.01 s / 84 MB | 4 ms / 0.01 s / 93 MB | 156 ms / 0.16 s / 160 MB |
| read + pass | polars | 3 ms / 0.01 s / 85 MB | 5 ms / 0.01 s / 93 MB | 157 ms / 0.16 s / 160 MB |
| read + pass | ours | 3 ms / 0.01 s / 85 MB | 4 ms / 0.01 s / 93 MB | 155 ms / 0.16 s / 160 MB |
| write, defaults | write | 3 ms / 0.01 s / 92 MB | 4 ms / 0.01 s / 97 MB | 12 ms / 0.01 s / 130 MB |
| write, zstd 3 | write | 3 ms / 0.01 s / 93 MB | 3 ms / 0.01 s / 97 MB | 12 ms / 0.01 s / 130 MB |
| .dta read (ours, pandas) | dta | 3 ms / 0.00 s / 69 MB | 187 ms / 0.19 s / 150 MB | – |
| .dta write (ours, pandas) | dta | 9 ms / 0.01 s / 70 MB | 7 ms / 0.01 s / 150 MB | – |

### 2022_2023_FemResp

5,586 rows, 1,912 columns; .dta 13.3 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 8 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 142 MB | 175 ms / 0.24 s / 247 MB |
| whole file | polars | 9 ms / 0.02 s / 121 MB | 21 ms / 0.03 s / 142 MB | 177 ms / 0.25 s / 247 MB |
| whole file | ours | 9 ms / 0.02 s / 122 MB | 17 ms / 0.02 s / 143 MB | 174 ms / 0.24 s / 246 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 67 MB | 4 ms / 0.01 s / 88 MB | 157 ms / 0.16 s / 156 MB |
| five columns | polars | 1 ms / 0.00 s / 67 MB | 3 ms / 0.01 s / 88 MB | 157 ms / 0.16 s / 156 MB |
| five columns | ours | 2 ms / 0.00 s / 67 MB | 3 ms / 0.01 s / 89 MB | 156 ms / 0.16 s / 156 MB |
| 1,000 rows | pyarrow | 6 ms / 0.01 s / 85 MB | 11 ms / 0.01 s / 102 MB | 19 ms / 0.09 s / 196 MB |
| 1,000 rows | polars | 7 ms / 0.01 s / 86 MB | 15 ms / 0.02 s / 101 MB | 19 ms / 0.09 s / 196 MB |
| 1,000 rows | ours | 6 ms / 0.01 s / 87 MB | 11 ms / 0.01 s / 102 MB | 18 ms / 0.08 s / 197 MB |
| read + pass | pyarrow | 23 ms / 0.05 s / 150 MB | 31 ms / 0.05 s / 159 MB | 199 ms / 0.27 s / 246 MB |
| read + pass | polars | 24 ms / 0.05 s / 151 MB | 35 ms / 0.05 s / 159 MB | 200 ms / 0.27 s / 248 MB |
| read + pass | ours | 24 ms / 0.05 s / 152 MB | 31 ms / 0.05 s / 159 MB | 199 ms / 0.27 s / 248 MB |
| write, defaults | write | 19 ms / 0.08 s / 152 MB | 23 ms / 0.12 s / 174 MB | 111 ms / 0.11 s / 195 MB |
| write, zstd 3 | write | 21 ms / 0.09 s / 153 MB | 21 ms / 0.12 s / 175 MB | 125 ms / 0.12 s / 196 MB |
| .dta read (ours, pandas) | dta | 27 ms / 0.03 s / 86 MB | 231 ms / 0.23 s / 220 MB | – |
| .dta write (ours, pandas) | dta | 95 ms / 0.10 s / 99 MB | 86 ms / 0.09 s / 232 MB | – |

### 2022_2023_MaleResp

4,371 rows, 1,157 columns; .dta 6.3 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 5 ms / 0.01 s / 95 MB | 10 ms / 0.01 s / 113 MB | 167 ms / 0.20 s / 196 MB |
| whole file | polars | 5 ms / 0.01 s / 96 MB | 11 ms / 0.02 s / 113 MB | 166 ms / 0.21 s / 197 MB |
| whole file | ours | 5 ms / 0.01 s / 96 MB | 9 ms / 0.01 s / 113 MB | 163 ms / 0.20 s / 197 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 66 MB | 3 ms / 0.01 s / 86 MB | 157 ms / 0.16 s / 154 MB |
| five columns | polars | 1 ms / 0.00 s / 66 MB | 3 ms / 0.01 s / 86 MB | 156 ms / 0.16 s / 154 MB |
| five columns | ours | 1 ms / 0.00 s / 67 MB | 3 ms / 0.01 s / 86 MB | 155 ms / 0.16 s / 154 MB |
| 1,000 rows | pyarrow | 4 ms / 0.01 s / 80 MB | 7 ms / 0.01 s / 93 MB | 11 ms / 0.05 s / 147 MB |
| 1,000 rows | polars | 4 ms / 0.01 s / 79 MB | 9 ms / 0.01 s / 93 MB | 11 ms / 0.05 s / 148 MB |
| 1,000 rows | ours | 4 ms / 0.01 s / 80 MB | 7 ms / 0.01 s / 94 MB | 10 ms / 0.04 s / 147 MB |
| read + pass | pyarrow | 14 ms / 0.03 s / 119 MB | 19 ms / 0.03 s / 126 MB | 177 ms / 0.22 s / 198 MB |
| read + pass | polars | 15 ms / 0.03 s / 119 MB | 20 ms / 0.03 s / 127 MB | 178 ms / 0.22 s / 197 MB |
| read + pass | ours | 15 ms / 0.03 s / 120 MB | 18 ms / 0.03 s / 126 MB | 178 ms / 0.22 s / 199 MB |
| write, defaults | write | 10 ms / 0.03 s / 121 MB | 12 ms / 0.06 s / 135 MB | 52 ms / 0.05 s / 163 MB |
| write, zstd 3 | write | 12 ms / 0.04 s / 122 MB | 13 ms / 0.06 s / 135 MB | 60 ms / 0.06 s / 162 MB |
| .dta read (ours, pandas) | dta | 13 ms / 0.01 s / 78 MB | 208 ms / 0.21 s / 182 MB | – |
| .dta write (ours, pandas) | dta | 43 ms / 0.04 s / 86 MB | 43 ms / 0.04 s / 189 MB | – |

### Senegal 2019 wm

8,649 rows, 4,997 columns; .dta 49.1 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 21 ms / 0.05 s / 218 MB | 25 ms / 0.05 s / 322 MB | 227 ms / 0.38 s / 442 MB |
| whole file | polars | 18 ms / 0.05 s / 216 MB | 22 ms / 0.05 s / 322 MB | 229 ms / 0.39 s / 442 MB |
| whole file | ours | 21 ms / 0.05 s / 222 MB | 19 ms / 0.04 s / 324 MB | 211 ms / 0.36 s / 443 MB |
| five columns | pyarrow | 4 ms / 0.00 s / 74 MB | 6 ms / 0.01 s / 96 MB | 170 ms / 0.17 s / 167 MB |
| five columns | polars | 3 ms / 0.00 s / 73 MB | 6 ms / 0.01 s / 96 MB | 164 ms / 0.16 s / 168 MB |
| five columns | ours | 5 ms / 0.01 s / 75 MB | 6 ms / 0.01 s / 99 MB | 167 ms / 0.17 s / 171 MB |
| 1,000 rows | pyarrow | 13 ms / 0.02 s / 113 MB | 13 ms / 0.03 s / 131 MB | 49 ms / 0.22 s / 385 MB |
| 1,000 rows | polars | 13 ms / 0.02 s / 113 MB | 14 ms / 0.03 s / 129 MB | 49 ms / 0.22 s / 386 MB |
| 1,000 rows | ours | 16 ms / 0.02 s / 120 MB | 12 ms / 0.02 s / 133 MB | 44 ms / 0.19 s / 387 MB |
| read + pass | pyarrow | 54 ms / 0.10 s / 270 MB | 54 ms / 0.10 s / 360 MB | 265 ms / 0.43 s / 443 MB |
| read + pass | polars | 54 ms / 0.11 s / 271 MB | 57 ms / 0.10 s / 360 MB | 268 ms / 0.45 s / 444 MB |
| read + pass | ours | 57 ms / 0.11 s / 278 MB | 56 ms / 0.10 s / 360 MB | 266 ms / 0.42 s / 445 MB |
| write, defaults | write | 35 ms / 0.20 s / 348 MB | 48 ms / 0.30 s / 389 MB | 250 ms / 0.25 s / 397 MB |
| write, zstd 3 | write | 39 ms / 0.21 s / 354 MB | 47 ms / 0.30 s / 389 MB | 263 ms / 0.26 s / 397 MB |
| .dta read (ours, pandas) | dta | 46 ms / 0.11 s / 153 MB | 304 ms / 0.36 s / 523 MB | – |
| .dta write (ours, pandas) | dta | 157 ms / 0.30 s / 180 MB | 177 ms / 0.26 s / 548 MB | – |

### Senegal 2019 bh

21,562 rows, 1,191 columns; .dta 28.9 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 10 ms / 0.03 s / 154 MB | 20 ms / 0.03 s / 218 MB | 186 ms / 0.26 s / 298 MB |
| whole file | polars | 11 ms / 0.03 s / 154 MB | 22 ms / 0.04 s / 218 MB | 183 ms / 0.26 s / 299 MB |
| whole file | ours | 11 ms / 0.03 s / 156 MB | 20 ms / 0.03 s / 219 MB | 186 ms / 0.25 s / 299 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 70 MB | 4 ms / 0.01 s / 87 MB | 177 ms / 0.18 s / 155 MB |
| five columns | polars | 2 ms / 0.00 s / 68 MB | 9 ms / 0.01 s / 87 MB | 175 ms / 0.17 s / 156 MB |
| five columns | ours | 2 ms / 0.00 s / 69 MB | 7 ms / 0.01 s / 87 MB | 168 ms / 0.17 s / 156 MB |
| 1,000 rows | pyarrow | 6 ms / 0.01 s / 80 MB | 11 ms / 0.02 s / 97 MB | 23 ms / 0.10 s / 252 MB |
| 1,000 rows | polars | 8 ms / 0.01 s / 80 MB | 16 ms / 0.02 s / 96 MB | 22 ms / 0.10 s / 252 MB |
| 1,000 rows | ours | 6 ms / 0.01 s / 82 MB | 10 ms / 0.02 s / 98 MB | 23 ms / 0.09 s / 250 MB |
| read + pass | pyarrow | 26 ms / 0.05 s / 177 MB | 36 ms / 0.06 s / 233 MB | 207 ms / 0.28 s / 301 MB |
| read + pass | polars | 26 ms / 0.06 s / 180 MB | 33 ms / 0.06 s / 234 MB | 195 ms / 0.27 s / 298 MB |
| read + pass | ours | 21 ms / 0.06 s / 183 MB | 28 ms / 0.05 s / 235 MB | 192 ms / 0.27 s / 300 MB |
| write, defaults | write | 22 ms / 0.14 s / 239 MB | 29 ms / 0.19 s / 253 MB | 182 ms / 0.18 s / 271 MB |
| write, zstd 3 | write | 26 ms / 0.16 s / 245 MB | 28 ms / 0.20 s / 253 MB | 187 ms / 0.19 s / 270 MB |
| .dta read (ours, pandas) | dta | 23 ms / 0.06 s / 114 MB | 238 ms / 0.26 s / 322 MB | – |
| .dta write (ours, pandas) | dta | 90 ms / 0.18 s / 133 MB | 64 ms / 0.10 s / 343 MB | – |

### Turkey 2013 wm

9,746 rows, 4,668 columns; .dta 52.6 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 17 ms / 0.05 s / 212 MB | 20 ms / 0.05 s / 309 MB | 210 ms / 0.37 s / 426 MB |
| whole file | polars | 17 ms / 0.05 s / 213 MB | 19 ms / 0.05 s / 309 MB | 214 ms / 0.38 s / 430 MB |
| whole file | ours | 20 ms / 0.05 s / 219 MB | 19 ms / 0.05 s / 310 MB | 210 ms / 0.35 s / 430 MB |
| five columns | pyarrow | 4 ms / 0.00 s / 73 MB | 6 ms / 0.01 s / 96 MB | 169 ms / 0.17 s / 167 MB |
| five columns | polars | 3 ms / 0.00 s / 73 MB | 6 ms / 0.01 s / 96 MB | 165 ms / 0.17 s / 167 MB |
| five columns | ours | 5 ms / 0.01 s / 74 MB | 6 ms / 0.01 s / 99 MB | 168 ms / 0.17 s / 171 MB |
| 1,000 rows | pyarrow | 13 ms / 0.02 s / 111 MB | 13 ms / 0.03 s / 129 MB | 52 ms / 0.20 s / 371 MB |
| 1,000 rows | polars | 13 ms / 0.02 s / 112 MB | 14 ms / 0.03 s / 129 MB | 52 ms / 0.22 s / 374 MB |
| 1,000 rows | ours | 16 ms / 0.02 s / 117 MB | 13 ms / 0.03 s / 130 MB | 48 ms / 0.18 s / 373 MB |
| read + pass | pyarrow | 54 ms / 0.10 s / 270 MB | 57 ms / 0.11 s / 344 MB | 286 ms / 0.42 s / 437 MB |
| read + pass | polars | 62 ms / 0.12 s / 270 MB | 59 ms / 0.11 s / 344 MB | 295 ms / 0.42 s / 443 MB |
| read + pass | ours | 63 ms / 0.12 s / 277 MB | 60 ms / 0.11 s / 343 MB | 297 ms / 0.41 s / 441 MB |
| write, defaults | write | 38 ms / 0.20 s / 336 MB | 66 ms / 0.32 s / 373 MB | 260 ms / 0.26 s / 385 MB |
| write, zstd 3 | write | 40 ms / 0.22 s / 343 MB | 49 ms / 0.31 s / 374 MB | 275 ms / 0.27 s / 382 MB |
| .dta read (ours, pandas) | dta | 46 ms / 0.12 s / 157 MB | 305 ms / 0.36 s / 506 MB | – |
| .dta write (ours, pandas) | dta | 155 ms / 0.31 s / 184 MB | 170 ms / 0.26 s / 535 MB | – |

### Turkey 2013 bh

17,871 rows, 1,173 columns; .dta 23.3 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 8 ms / 0.02 s / 133 MB | 17 ms / 0.03 s / 198 MB | 173 ms / 0.24 s / 278 MB |
| whole file | polars | 9 ms / 0.03 s / 133 MB | 18 ms / 0.03 s / 198 MB | 173 ms / 0.24 s / 276 MB |
| whole file | ours | 9 ms / 0.02 s / 135 MB | 17 ms / 0.03 s / 199 MB | 172 ms / 0.23 s / 278 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 87 MB | 159 ms / 0.16 s / 156 MB |
| five columns | polars | 1 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 88 MB | 162 ms / 0.16 s / 155 MB |
| five columns | ours | 2 ms / 0.00 s / 71 MB | 3 ms / 0.01 s / 88 MB | 162 ms / 0.16 s / 156 MB |
| 1,000 rows | pyarrow | 4 ms / 0.01 s / 80 MB | 8 ms / 0.01 s / 96 MB | 18 ms / 0.08 s / 228 MB |
| 1,000 rows | polars | 5 ms / 0.01 s / 80 MB | 10 ms / 0.02 s / 96 MB | 17 ms / 0.08 s / 228 MB |
| 1,000 rows | ours | 5 ms / 0.01 s / 82 MB | 8 ms / 0.01 s / 97 MB | 16 ms / 0.07 s / 230 MB |
| read + pass | pyarrow | 19 ms / 0.05 s / 160 MB | 28 ms / 0.05 s / 214 MB | 204 ms / 0.27 s / 278 MB |
| read + pass | polars | 20 ms / 0.05 s / 159 MB | 30 ms / 0.05 s / 213 MB | 199 ms / 0.26 s / 279 MB |
| read + pass | ours | 20 ms / 0.05 s / 161 MB | 28 ms / 0.05 s / 214 MB | 204 ms / 0.26 s / 278 MB |
| write, defaults | write | 27 ms / 0.12 s / 216 MB | 34 ms / 0.18 s / 229 MB | 148 ms / 0.15 s / 249 MB |
| write, zstd 3 | write | 25 ms / 0.13 s / 220 MB | 30 ms / 0.17 s / 230 MB | 158 ms / 0.16 s / 249 MB |
| .dta read (ours, pandas) | dta | 22 ms / 0.06 s / 108 MB | 228 ms / 0.25 s / 298 MB | – |
| .dta write (ours, pandas) | dta | 75 ms / 0.15 s / 128 MB | 55 ms / 0.08 s / 317 MB | – |

### Tajikistan 2017 wm

10,718 rows, 5,160 columns; .dta 63.8 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 19 ms / 0.06 s / 246 MB | 23 ms / 0.06 s / 377 MB | 230 ms / 0.40 s / 495 MB |
| whole file | polars | 19 ms / 0.07 s / 247 MB | 25 ms / 0.07 s / 377 MB | 220 ms / 0.40 s / 496 MB |
| whole file | ours | 23 ms / 0.07 s / 253 MB | 23 ms / 0.06 s / 379 MB | 229 ms / 0.38 s / 502 MB |
| five columns | pyarrow | 4 ms / 0.00 s / 73 MB | 7 ms / 0.01 s / 97 MB | 171 ms / 0.17 s / 169 MB |
| five columns | polars | 4 ms / 0.00 s / 74 MB | 6 ms / 0.01 s / 97 MB | 174 ms / 0.17 s / 168 MB |
| five columns | ours | 5 ms / 0.01 s / 75 MB | 6 ms / 0.01 s / 100 MB | 177 ms / 0.18 s / 172 MB |
| 1,000 rows | pyarrow | 14 ms / 0.03 s / 114 MB | 13 ms / 0.03 s / 135 MB | 57 ms / 0.23 s / 439 MB |
| 1,000 rows | polars | 15 ms / 0.03 s / 114 MB | 15 ms / 0.04 s / 134 MB | 56 ms / 0.23 s / 440 MB |
| 1,000 rows | ours | 17 ms / 0.03 s / 121 MB | 13 ms / 0.03 s / 137 MB | 48 ms / 0.22 s / 442 MB |
| read + pass | pyarrow | 58 ms / 0.13 s / 303 MB | 62 ms / 0.12 s / 417 MB | 296 ms / 0.46 s / 503 MB |
| read + pass | polars | 61 ms / 0.13 s / 304 MB | 63 ms / 0.13 s / 415 MB | 277 ms / 0.47 s / 498 MB |
| read + pass | ours | 61 ms / 0.13 s / 312 MB | 60 ms / 0.12 s / 416 MB | 276 ms / 0.45 s / 499 MB |
| write, defaults | write | 44 ms / 0.25 s / 406 MB | 54 ms / 0.37 s / 448 MB | 316 ms / 0.31 s / 456 MB |
| write, zstd 3 | write | 48 ms / 0.27 s / 413 MB | 65 ms / 0.38 s / 447 MB | 352 ms / 0.35 s / 455 MB |
| .dta read (ours, pandas) | dta | 56 ms / 0.14 s / 171 MB | 327 ms / 0.40 s / 560 MB | – |
| .dta write (ours, pandas) | dta | 198 ms / 0.38 s / 198 MB | 199 ms / 0.31 s / 588 MB | – |

### Tajikistan 2017 bh

21,985 rows, 1,146 columns; .dta 29.4 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 10 ms / 0.03 s / 155 MB | 19 ms / 0.03 s / 216 MB | 173 ms / 0.24 s / 294 MB |
| whole file | polars | 10 ms / 0.03 s / 155 MB | 21 ms / 0.04 s / 216 MB | 173 ms / 0.25 s / 294 MB |
| whole file | ours | 11 ms / 0.03 s / 157 MB | 19 ms / 0.03 s / 217 MB | 186 ms / 0.25 s / 294 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 87 MB | 168 ms / 0.17 s / 156 MB |
| five columns | polars | 1 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 87 MB | 161 ms / 0.16 s / 156 MB |
| five columns | ours | 2 ms / 0.00 s / 71 MB | 3 ms / 0.01 s / 88 MB | 165 ms / 0.17 s / 158 MB |
| 1,000 rows | pyarrow | 5 ms / 0.01 s / 80 MB | 9 ms / 0.02 s / 98 MB | 20 ms / 0.09 s / 245 MB |
| 1,000 rows | polars | 6 ms / 0.01 s / 80 MB | 14 ms / 0.02 s / 97 MB | 25 ms / 0.09 s / 244 MB |
| 1,000 rows | ours | 6 ms / 0.01 s / 81 MB | 11 ms / 0.02 s / 98 MB | 19 ms / 0.08 s / 246 MB |
| read + pass | pyarrow | 21 ms / 0.06 s / 181 MB | 30 ms / 0.06 s / 232 MB | 221 ms / 0.29 s / 299 MB |
| read + pass | polars | 29 ms / 0.05 s / 177 MB | 50 ms / 0.06 s / 230 MB | 222 ms / 0.29 s / 298 MB |
| read + pass | ours | 39 ms / 0.06 s / 179 MB | 39 ms / 0.06 s / 229 MB | 209 ms / 0.28 s / 297 MB |
| write, defaults | write | 26 ms / 0.15 s / 239 MB | 39 ms / 0.21 s / 250 MB | 186 ms / 0.19 s / 268 MB |
| write, zstd 3 | write | 27 ms / 0.16 s / 245 MB | 34 ms / 0.21 s / 251 MB | 203 ms / 0.20 s / 269 MB |
| .dta read (ours, pandas) | dta | 23 ms / 0.06 s / 114 MB | 236 ms / 0.26 s / 310 MB | – |
| .dta write (ours, pandas) | dta | 90 ms / 0.18 s / 134 MB | 61 ms / 0.10 s / 329 MB | – |

### Myanmar 2016 wm

12,885 rows, 4,993 columns; .dta 72.0 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 18 ms / 0.07 s / 253 MB | 21 ms / 0.06 s / 409 MB | 225 ms / 0.41 s / 567 MB |
| whole file | polars | 18 ms / 0.07 s / 254 MB | 23 ms / 0.07 s / 408 MB | 221 ms / 0.42 s / 567 MB |
| whole file | ours | 22 ms / 0.08 s / 261 MB | 20 ms / 0.06 s / 411 MB | 214 ms / 0.40 s / 568 MB |
| five columns | pyarrow | 4 ms / 0.00 s / 73 MB | 7 ms / 0.01 s / 97 MB | 173 ms / 0.17 s / 169 MB |
| five columns | polars | 4 ms / 0.00 s / 74 MB | 6 ms / 0.01 s / 96 MB | 172 ms / 0.17 s / 167 MB |
| five columns | ours | 5 ms / 0.01 s / 75 MB | 6 ms / 0.01 s / 100 MB | 167 ms / 0.17 s / 172 MB |
| 1,000 rows | pyarrow | 14 ms / 0.03 s / 113 MB | 13 ms / 0.03 s / 132 MB | 59 ms / 0.24 s / 510 MB |
| 1,000 rows | polars | 14 ms / 0.03 s / 115 MB | 14 ms / 0.03 s / 132 MB | 61 ms / 0.24 s / 514 MB |
| 1,000 rows | ours | 16 ms / 0.02 s / 120 MB | 13 ms / 0.03 s / 135 MB | 53 ms / 0.23 s / 512 MB |
| read + pass | pyarrow | 58 ms / 0.14 s / 311 MB | 63 ms / 0.13 s / 446 MB | 306 ms / 0.47 s / 577 MB |
| read + pass | polars | 67 ms / 0.14 s / 309 MB | 87 ms / 0.14 s / 446 MB | 311 ms / 0.49 s / 588 MB |
| read + pass | ours | 73 ms / 0.14 s / 316 MB | 61 ms / 0.13 s / 447 MB | 283 ms / 0.44 s / 574 MB |
| write, defaults | write | 43 ms / 0.27 s / 437 MB | 57 ms / 0.40 s / 481 MB | 332 ms / 0.33 s / 485 MB |
| write, zstd 3 | write | 44 ms / 0.28 s / 445 MB | 57 ms / 0.40 s / 482 MB | 350 ms / 0.35 s / 486 MB |
| .dta read (ours, pandas) | dta | 62 ms / 0.16 s / 180 MB | 338 ms / 0.42 s / 639 MB | – |
| .dta write (ours, pandas) | dta | 218 ms / 0.43 s / 207 MB | 197 ms / 0.31 s / 666 MB | – |

### Myanmar 2016 bh

22,989 rows, 1,184 columns; .dta 30.7 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 11 ms / 0.03 s / 158 MB | 21 ms / 0.04 s / 225 MB | 188 ms / 0.26 s / 298 MB |
| whole file | polars | 12 ms / 0.04 s / 158 MB | 22 ms / 0.04 s / 224 MB | 188 ms / 0.25 s / 300 MB |
| whole file | ours | 13 ms / 0.03 s / 160 MB | 23 ms / 0.04 s / 225 MB | 191 ms / 0.26 s / 300 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 69 MB | 4 ms / 0.01 s / 87 MB | 167 ms / 0.17 s / 156 MB |
| five columns | polars | 2 ms / 0.00 s / 71 MB | 5 ms / 0.01 s / 87 MB | 166 ms / 0.17 s / 157 MB |
| five columns | ours | 2 ms / 0.00 s / 71 MB | 4 ms / 0.01 s / 88 MB | 171 ms / 0.17 s / 158 MB |
| 1,000 rows | pyarrow | 6 ms / 0.01 s / 80 MB | 15 ms / 0.02 s / 97 MB | 23 ms / 0.09 s / 253 MB |
| 1,000 rows | polars | 6 ms / 0.01 s / 80 MB | 18 ms / 0.02 s / 96 MB | 21 ms / 0.09 s / 251 MB |
| 1,000 rows | ours | 7 ms / 0.01 s / 82 MB | 14 ms / 0.02 s / 98 MB | 20 ms / 0.08 s / 254 MB |
| read + pass | pyarrow | 29 ms / 0.06 s / 182 MB | 41 ms / 0.06 s / 240 MB | 223 ms / 0.28 s / 302 MB |
| read + pass | polars | 26 ms / 0.06 s / 185 MB | 36 ms / 0.06 s / 237 MB | 211 ms / 0.28 s / 299 MB |
| read + pass | ours | 24 ms / 0.06 s / 186 MB | 31 ms / 0.06 s / 241 MB | 212 ms / 0.28 s / 302 MB |
| write, defaults | write | 23 ms / 0.15 s / 246 MB | 38 ms / 0.21 s / 258 MB | 190 ms / 0.19 s / 277 MB |
| write, zstd 3 | write | 28 ms / 0.17 s / 252 MB | 34 ms / 0.20 s / 260 MB | 309 ms / 0.21 s / 277 MB |
| .dta read (ours, pandas) | dta | 25 ms / 0.07 s / 116 MB | 238 ms / 0.27 s / 319 MB | – |
| .dta write (ours, pandas) | dta | 97 ms / 0.19 s / 136 MB | 63 ms / 0.10 s / 339 MB | – |

### Dominican Republic 2013 wm

9,372 rows, 3,854 columns; .dta 39.7 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 16 ms / 0.04 s / 189 MB | 21 ms / 0.04 s / 269 MB | 204 ms / 0.34 s / 375 MB |
| whole file | polars | 15 ms / 0.04 s / 189 MB | 22 ms / 0.04 s / 268 MB | 210 ms / 0.34 s / 375 MB |
| whole file | ours | 17 ms / 0.04 s / 194 MB | 19 ms / 0.04 s / 270 MB | 202 ms / 0.32 s / 378 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 72 MB | 5 ms / 0.01 s / 95 MB | 169 ms / 0.17 s / 163 MB |
| five columns | polars | 3 ms / 0.00 s / 73 MB | 5 ms / 0.01 s / 95 MB | 168 ms / 0.17 s / 164 MB |
| five columns | ours | 4 ms / 0.00 s / 73 MB | 5 ms / 0.01 s / 97 MB | 164 ms / 0.16 s / 165 MB |
| 1,000 rows | pyarrow | 10 ms / 0.02 s / 102 MB | 12 ms / 0.02 s / 122 MB | 43 ms / 0.17 s / 324 MB |
| 1,000 rows | polars | 11 ms / 0.02 s / 102 MB | 13 ms / 0.03 s / 121 MB | 47 ms / 0.17 s / 324 MB |
| 1,000 rows | ours | 13 ms / 0.02 s / 108 MB | 12 ms / 0.02 s / 123 MB | 39 ms / 0.16 s / 323 MB |
| read + pass | pyarrow | 45 ms / 0.09 s / 236 MB | 51 ms / 0.09 s / 298 MB | 256 ms / 0.38 s / 379 MB |
| read + pass | polars | 48 ms / 0.09 s / 234 MB | 56 ms / 0.09 s / 294 MB | 279 ms / 0.39 s / 391 MB |
| read + pass | ours | 53 ms / 0.09 s / 239 MB | 59 ms / 0.10 s / 297 MB | 277 ms / 0.39 s / 395 MB |
| write, defaults | write | 43 ms / 0.18 s / 290 MB | 55 ms / 0.27 s / 320 MB | 230 ms / 0.23 s / 334 MB |
| write, zstd 3 | write | 35 ms / 0.18 s / 297 MB | 54 ms / 0.26 s / 322 MB | 254 ms / 0.24 s / 334 MB |
| .dta read (ours, pandas) | dta | 36 ms / 0.09 s / 136 MB | 281 ms / 0.32 s / 436 MB | – |
| .dta write (ours, pandas) | dta | 131 ms / 0.25 s / 163 MB | 143 ms / 0.22 s / 463 MB | – |

### Dominican Republic 2013 bh

18,167 rows, 1,078 columns; .dta 22.2 MB.

| case | input | datakit | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 9 ms / 0.03 s / 138 MB | 20 ms / 0.03 s / 191 MB | 188 ms / 0.25 s / 269 MB |
| whole file | polars | 9 ms / 0.03 s / 139 MB | 22 ms / 0.03 s / 190 MB | 174 ms / 0.24 s / 268 MB |
| whole file | ours | 10 ms / 0.03 s / 140 MB | 20 ms / 0.03 s / 191 MB | 207 ms / 0.25 s / 271 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 69 MB | 4 ms / 0.01 s / 87 MB | 182 ms / 0.18 s / 156 MB |
| five columns | polars | 1 ms / 0.00 s / 70 MB | 4 ms / 0.01 s / 87 MB | 162 ms / 0.16 s / 156 MB |
| five columns | ours | 2 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 88 MB | 162 ms / 0.16 s / 157 MB |
| 1,000 rows | pyarrow | 5 ms / 0.01 s / 79 MB | 10 ms / 0.02 s / 96 MB | 17 ms / 0.08 s / 219 MB |
| 1,000 rows | polars | 5 ms / 0.01 s / 79 MB | 12 ms / 0.02 s / 95 MB | 23 ms / 0.09 s / 220 MB |
| 1,000 rows | ours | 7 ms / 0.01 s / 81 MB | 15 ms / 0.02 s / 96 MB | 20 ms / 0.08 s / 224 MB |
| read + pass | pyarrow | 22 ms / 0.05 s / 160 MB | 36 ms / 0.06 s / 205 MB | 210 ms / 0.27 s / 271 MB |
| read + pass | polars | 23 ms / 0.05 s / 160 MB | 40 ms / 0.05 s / 203 MB | 206 ms / 0.27 s / 270 MB |
| read + pass | ours | 24 ms / 0.05 s / 163 MB | 31 ms / 0.05 s / 206 MB | 192 ms / 0.26 s / 269 MB |
| write, defaults | write | 19 ms / 0.12 s / 209 MB | 24 ms / 0.16 s / 223 MB | 140 ms / 0.14 s / 241 MB |
| write, zstd 3 | write | 21 ms / 0.12 s / 215 MB | 25 ms / 0.16 s / 223 MB | 151 ms / 0.15 s / 242 MB |
| .dta read (ours, pandas) | dta | 20 ms / 0.05 s / 107 MB | 231 ms / 0.25 s / 286 MB | – |
| .dta write (ours, pandas) | dta | 73 ms / 0.15 s / 126 MB | 54 ms / 0.08 s / 306 MB | – |

