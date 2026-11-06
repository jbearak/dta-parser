# Parquet benchmarks (Python, polars)

Written by `bench/parquet/run_polars.py`; bench/RESULTS.md says what the numbers mean.

One-minute load average before each run: median 14.4, range 11.2 to 28.0 (plan 0018 asks for under 2).

| library | version | threads |
|---|---|---|
| ours (Arrow path, whole Meta) | dta_parser (Arrow path) | default |
| dta_parser (pandas) | dta_parser (pandas) | default |
| polars | 2.1.0 | 16 |
| pyarrow (Table) | 26.0.1 | 16 |

## Ratios, ours to theirs (geometric means), gated

Below 1 is better for us. Target 1 holds where wall and RSS are at most 1.05 on NSFG and DHS. Writes are of the frame pl.read_parquet gives of our file.

| against | case | input | family | files | wall | CPU | peak RSS |
|---|---|---|---|---|---|---|---|
| polars | whole file | pyarrow | NSFG | 13 | 0.40 | 0.59 | 0.83 |
| polars | whole file | pyarrow | DHS | 10 | 0.61 | 0.93 | 0.68 |
| polars | whole file | pyarrow | Synthetic | 3 | 0.91 | 1.18 | 0.86 |
| polars | whole file | polars | NSFG | 13 | 0.38 | 0.61 | 0.83 |
| polars | whole file | polars | DHS | 10 | 0.59 | 0.95 | 0.69 |
| polars | whole file | polars | Synthetic | 3 | 0.72 | 0.98 | 0.87 |
| polars | whole file | ours | NSFG | 13 | 0.50 | 0.65 | 0.84 |
| polars | whole file | ours | DHS | 10 | 0.73 | 1.02 | 0.69 |
| polars | whole file | ours | Synthetic | 3 | 0.82 | 1.11 | 0.83 |
| polars | five columns | pyarrow | NSFG | 13 | 0.33 | 0.15 | 0.78 |
| polars | five columns | pyarrow | DHS | 10 | 0.50 | 0.31 | 0.78 |
| polars | five columns | pyarrow | Synthetic | 3 | 1.05 | 1.25 | 0.89 |
| polars | five columns | polars | NSFG | 13 | 0.30 | 0.14 | 0.78 |
| polars | five columns | polars | DHS | 10 | 0.47 | 0.31 | 0.78 |
| polars | five columns | polars | Synthetic | 3 | 0.92 | 0.97 | 0.72 |
| polars | five columns | ours | NSFG | 13 | 0.42 | 0.19 | 0.78 |
| polars | five columns | ours | DHS | 10 | 0.66 | 0.38 | 0.78 |
| polars | five columns | ours | Synthetic | 3 | 0.98 | 1.03 | 0.74 |
| polars | 1,000 rows | pyarrow | NSFG | 13 | 0.44 | 0.42 | 0.83 |
| polars | 1,000 rows | pyarrow | DHS | 10 | 0.69 | 0.67 | 0.84 |
| polars | 1,000 rows | pyarrow | Synthetic | 3 | 0.38 | 0.29 | 0.27 |
| polars | 1,000 rows | polars | NSFG | 13 | 0.38 | 0.43 | 0.83 |
| polars | 1,000 rows | polars | DHS | 10 | 0.63 | 0.67 | 0.85 |
| polars | 1,000 rows | polars | Synthetic | 3 | 0.28 | 0.33 | 0.55 |
| polars | 1,000 rows | ours | NSFG | 13 | 0.56 | 0.46 | 0.84 |
| polars | 1,000 rows | ours | DHS | 10 | 0.80 | 0.70 | 0.86 |
| polars | 1,000 rows | ours | Synthetic | 3 | 0.34 | 0.25 | 0.39 |
| polars | read + pass | pyarrow | NSFG | 13 | 0.70 | 0.99 | 0.93 |
| polars | read + pass | pyarrow | DHS | 10 | 0.81 | 1.01 | 0.76 |
| polars | read + pass | pyarrow | Synthetic | 3 | 0.90 | 1.15 | 0.91 |
| polars | read + pass | polars | NSFG | 13 | 0.66 | 0.97 | 0.93 |
| polars | read + pass | polars | DHS | 10 | 0.79 | 1.00 | 0.76 |
| polars | read + pass | polars | Synthetic | 3 | 0.72 | 0.99 | 0.90 |
| polars | read + pass | ours | NSFG | 13 | 0.75 | 1.01 | 0.94 |
| polars | read + pass | ours | DHS | 10 | 0.92 | 1.05 | 0.77 |
| polars | read + pass | ours | Synthetic | 3 | 0.83 | 1.13 | 0.87 |
| polars | write, defaults | write | NSFG | 13 | 1.02 | 0.73 | 0.90 |
| polars | write, defaults | write | DHS | 10 | 1.16 | 0.95 | 0.91 |
| polars | write, defaults | write | Synthetic | 3 | 1.28 | 0.94 | 1.20 |
| polars | write, zstd 3 | write | NSFG | 13 | 1.05 | 0.83 | 0.92 |
| polars | write, zstd 3 | write | DHS | 10 | 1.20 | 1.03 | 0.93 |
| polars | write, zstd 3 | write | Synthetic | 3 | 1.75 | 1.32 | 1.18 |
| pyarrow (Table) | whole file | pyarrow | NSFG | 13 | 0.02 | 0.04 | 0.49 |
| pyarrow (Table) | whole file | pyarrow | DHS | 10 | 0.06 | 0.12 | 0.50 |
| pyarrow (Table) | whole file | pyarrow | Synthetic | 3 | 0.18 | 0.48 | 0.59 |
| pyarrow (Table) | whole file | polars | NSFG | 13 | 0.02 | 0.05 | 0.49 |
| pyarrow (Table) | whole file | polars | DHS | 10 | 0.06 | 0.13 | 0.50 |
| pyarrow (Table) | whole file | polars | Synthetic | 3 | 0.25 | 0.50 | 0.54 |
| pyarrow (Table) | whole file | ours | NSFG | 13 | 0.03 | 0.05 | 0.50 |
| pyarrow (Table) | whole file | ours | DHS | 10 | 0.08 | 0.13 | 0.51 |
| pyarrow (Table) | whole file | ours | Synthetic | 3 | 0.16 | 0.38 | 0.56 |
| pyarrow (Table) | five columns | pyarrow | NSFG | 13 | 0.01 | 0.01 | 0.43 |
| pyarrow (Table) | five columns | pyarrow | DHS | 10 | 0.01 | 0.02 | 0.44 |
| pyarrow (Table) | five columns | pyarrow | Synthetic | 3 | 0.09 | 0.29 | 0.62 |
| pyarrow (Table) | five columns | polars | NSFG | 13 | 0.01 | 0.01 | 0.43 |
| pyarrow (Table) | five columns | polars | DHS | 10 | 0.01 | 0.02 | 0.44 |
| pyarrow (Table) | five columns | polars | Synthetic | 3 | 0.12 | 0.34 | 0.54 |
| pyarrow (Table) | five columns | ours | NSFG | 13 | 0.01 | 0.01 | 0.44 |
| pyarrow (Table) | five columns | ours | DHS | 10 | 0.02 | 0.02 | 0.44 |
| pyarrow (Table) | five columns | ours | Synthetic | 3 | 0.08 | 0.23 | 0.56 |
| pyarrow (Table) | 1,000 rows | pyarrow | NSFG | 13 | 0.33 | 0.16 | 0.48 |
| pyarrow (Table) | 1,000 rows | pyarrow | DHS | 10 | 0.24 | 0.10 | 0.30 |
| pyarrow (Table) | 1,000 rows | pyarrow | Synthetic | 3 | 0.09 | 0.12 | 0.13 |
| pyarrow (Table) | 1,000 rows | polars | NSFG | 13 | 0.35 | 0.18 | 0.48 |
| pyarrow (Table) | 1,000 rows | polars | DHS | 10 | 0.25 | 0.12 | 0.30 |
| pyarrow (Table) | 1,000 rows | polars | Synthetic | 3 | 0.45 | 0.44 | 0.36 |
| pyarrow (Table) | 1,000 rows | ours | NSFG | 13 | 0.43 | 0.17 | 0.49 |
| pyarrow (Table) | 1,000 rows | ours | DHS | 10 | 0.29 | 0.11 | 0.31 |
| pyarrow (Table) | 1,000 rows | ours | Synthetic | 3 | 0.17 | 0.15 | 0.23 |
| pyarrow (Table) | read + pass | pyarrow | NSFG | 13 | 0.06 | 0.13 | 0.60 |
| pyarrow (Table) | read + pass | pyarrow | DHS | 10 | 0.15 | 0.23 | 0.60 |
| pyarrow (Table) | read + pass | pyarrow | Synthetic | 3 | 0.20 | 0.52 | 0.69 |
| pyarrow (Table) | read + pass | polars | NSFG | 13 | 0.06 | 0.13 | 0.60 |
| pyarrow (Table) | read + pass | polars | DHS | 10 | 0.15 | 0.23 | 0.60 |
| pyarrow (Table) | read + pass | polars | Synthetic | 3 | 0.27 | 0.54 | 0.63 |
| pyarrow (Table) | read + pass | ours | NSFG | 13 | 0.06 | 0.13 | 0.61 |
| pyarrow (Table) | read + pass | ours | DHS | 10 | 0.16 | 0.23 | 0.61 |
| pyarrow (Table) | read + pass | ours | Synthetic | 3 | 0.19 | 0.43 | 0.65 |
| pyarrow (Table) | write, defaults | write | NSFG | 13 | 0.24 | 0.84 | 0.76 |
| pyarrow (Table) | write, defaults | write | DHS | 10 | 0.22 | 1.11 | 0.87 |
| pyarrow (Table) | write, defaults | write | Synthetic | 3 | 0.16 | 0.94 | 1.07 |
| pyarrow (Table) | write, zstd 3 | write | NSFG | 13 | 0.23 | 0.87 | 0.77 |
| pyarrow (Table) | write, zstd 3 | write | DHS | 10 | 0.20 | 1.12 | 0.89 |
| pyarrow (Table) | write, zstd 3 | write | Synthetic | 3 | 0.16 | 1.00 | 1.10 |

## .dta into polars against dta_parser's pandas path (published, not gated)

| case | family | files | wall | CPU | peak RSS |
|---|---|---|---|---|---|
| .dta read | NSFG | 13 | 0.61 | 0.72 | 0.43 |
| .dta read | DHS | 10 | 0.42 | 0.72 | 0.33 |
| .dta read | Synthetic | 3 | 0.41 | 0.71 | 0.62 |
| .dta write | NSFG | 13 | 1.22 | 1.35 | 0.46 |
| .dta write | DHS | 10 | 1.14 | 1.47 | 0.36 |
| .dta write | Synthetic | 3 | 0.66 | 1.00 | 0.47 |

## Misses

- 3 CPU: polars full pyarrow long.dta: 0.472 s vs 0.373 s, speedup 1.21 allows 0.452 s
- 3 CPU: polars full pyarrow groups.dta: 0.092 s vs 0.073 s, speedup 0.84 allows 0.084 s
- 3 CPU: polars full polars Myanmar 2016 wm: 0.072 s vs 0.063 s, speedup 1.15 allows 0.072 s
- 3 CPU: polars full ours long.dta: 0.417 s vs 0.354 s, speedup 1.07 allows 0.407 s
- 3 CPU: polars full ours groups.dta: 0.094 s vs 0.080 s, speedup 0.95 allows 0.091 s
- 3 CPU: polars full ours 2006_2010_FemResp: 0.067 s vs 0.057 s, speedup 1.06 allows 0.066 s
- 3 CPU: polars full ours Myanmar 2016 wm: 0.074 s vs 0.059 s, speedup 0.88 allows 0.068 s
- 3 CPU: polars five pyarrow long.dta: 0.315 s vs 0.224 s, speedup 0.84 allows 0.258 s
- 3 CPU: polars five pyarrow wide.dta: 0.026 s vs 0.023 s, speedup 1.10 allows 0.026 s
- 3 CPU: polars five pyarrow groups.dta: 0.092 s vs 0.077 s, speedup 0.93 allows 0.088 s
- 3 CPU: polars five polars groups.dta: 0.099 s vs 0.086 s, speedup 0.99 allows 0.098 s
- 3 CPU: polars five ours long.dta: 0.303 s vs 0.235 s, speedup 0.91 allows 0.271 s
- 3 CPU: polars five ours groups.dta: 0.093 s vs 0.079 s, speedup 0.95 allows 0.090 s
- 3 CPU: polars pass pyarrow long.dta: 0.544 s vs 0.442 s, speedup 1.05 allows 0.508 s
- 3 CPU: polars pass pyarrow groups.dta: 0.123 s vs 0.099 s, speedup 0.94 allows 0.114 s
- 3 CPU: polars pass pyarrow Myanmar 2016 wm: 0.131 s vs 0.111 s, speedup 0.96 allows 0.127 s
- 3 CPU: polars pass ours groups.dta: 0.125 s vs 0.102 s, speedup 1.13 allows 0.117 s
- 3 CPU: polars pass ours 2006_2010_FemResp: 0.133 s vs 0.115 s, speedup 0.99 allows 0.132 s
- 2 wall: polars pass ours Tajikistan 2017 wm: 107 ms vs 78 ms (1.38x)
- 3 CPU: polars pass ours Myanmar 2016 wm: 0.134 s vs 0.115 s, speedup 0.93 allows 0.133 s
- 1 wall: polars write write dhs: geometric mean 1.16x
- 2 wall: polars write write long.dta: 308 ms vs 227 ms (1.36x)
- 2 RSS: polars write write long.dta: 2012 vs 1554 MB (1.29x)
- 2 wall: polars write write groups.dta: 108 ms vs 68 ms (1.59x)
- 2 RSS: polars write write groups.dta: 731 vs 542 MB (1.35x)
- 2 wall: polars write write Senegal 2019 bh: 67 ms vs 39 ms (1.71x)
- 1 wall: polars zstd write dhs: geometric mean 1.20x
- 2 wall: polars zstd write long.dta: 436 ms vs 200 ms (2.19x)
- 2 RSS: polars zstd write long.dta: 2060 vs 1547 MB (1.33x)
- 3 CPU: polars zstd write long.dta: 2.559 s vs 1.916 s, speedup 0.46 allows 2.204 s
- 2 wall: polars zstd write wide.dta: 1.21 s vs 892 ms (1.35x)
- 3 CPU: polars zstd write wide.dta: 11.428 s vs 6.612 s, speedup 0.74 allows 7.603 s
- 2 wall: polars zstd write groups.dta: 108 ms vs 59 ms (1.83x)
- 2 RSS: polars zstd write groups.dta: 745 vs 541 MB (1.38x)
- 3 CPU: polars zstd write 2002_FemResp: 0.209 s vs 0.182 s, speedup 0.89 allows 0.209 s
- 2 wall: polars zstd write Myanmar 2016 wm: 79 ms vs 57 ms (1.38x)
- 2 RSS: pyarrow write write long.dta: 2012 vs 1585 MB (1.27x)
- 2 RSS: pyarrow zstd write long.dta: 2060 vs 1564 MB (1.32x)

## Every file

Each cell: wall / CPU / peak RSS (median of the runs).

### long.dta

10,000,000 rows, 12 columns; .dta 740.0 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 60 ms / 0.47 s / 1280 MB | 72 ms / 0.37 s / 1353 MB | 279 ms / 0.71 s / 1855 MB |
| whole file | polars | 92 ms / 0.80 s / 1132 MB | 110 ms / 0.85 s / 1331 MB | 278 ms / 1.11 s / 1889 MB |
| whole file | ours | 55 ms / 0.42 s / 1155 MB | 59 ms / 0.35 s / 1307 MB | 250 ms / 0.69 s / 1781 MB |
| five columns | pyarrow | 50 ms / 0.32 s / 665 MB | 42 ms / 0.22 s / 723 MB | 247 ms / 0.43 s / 912 MB |
| five columns | polars | 57 ms / 0.45 s / 568 MB | 73 ms / 0.45 s / 807 MB | 238 ms / 0.65 s / 893 MB |
| five columns | ours | 42 ms / 0.30 s / 591 MB | 39 ms / 0.24 s / 833 MB | 220 ms / 0.49 s / 866 MB |
| 1,000 rows | pyarrow | 4 ms / 0.01 s / 88 MB | 6 ms / 0.02 s / 154 MB | 23 ms / 0.06 s / 324 MB |
| 1,000 rows | polars | 2 ms / 0.01 s / 78 MB | 9 ms / 0.01 s / 92 MB | 5 ms / 0.01 s / 135 MB |
| 1,000 rows | ours | 2 ms / 0.00 s / 77 MB | 5 ms / 0.01 s / 101 MB | 7 ms / 0.02 s / 157 MB |
| read + pass | pyarrow | 76 ms / 0.54 s / 1600 MB | 80 ms / 0.44 s / 1500 MB | 327 ms / 0.75 s / 1956 MB |
| read + pass | polars | 107 ms / 0.88 s / 1429 MB | 114 ms / 0.90 s / 1619 MB | 321 ms / 1.18 s / 1932 MB |
| read + pass | ours | 66 ms / 0.49 s / 1438 MB | 63 ms / 0.44 s / 1498 MB | 278 ms / 0.76 s / 1828 MB |
| write, defaults | write | 308 ms / 1.70 s / 2012 MB | 227 ms / 1.89 s / 1554 MB | 1.59 s / 1.59 s / 1585 MB |
| write, zstd 3 | write | 436 ms / 2.56 s / 2060 MB | 200 ms / 1.92 s / 1547 MB | 2.25 s / 2.24 s / 1564 MB |
| .dta read (ours, pandas) | dta | 217 ms / 0.64 s / 1003 MB | 800 ms / 1.20 s / 2141 MB | – |
| .dta write (ours, pandas) | dta | 483 ms / 1.23 s / 1019 MB | 1.28 s / 1.47 s / 2702 MB | – |

### wide.dta

1,500,000 rows, 400 columns; .dta 4800.3 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 182 ms / 1.71 s / 5211 MB | 238 ms / 1.66 s / 7205 MB | 458 ms / 2.74 s / 10188 MB |
| whole file | polars | 470 ms / 4.29 s / 4971 MB | 1.15 s / 4.81 s / 5676 MB | 710 ms / 5.30 s / 9817 MB |
| whole file | ours | 136 ms / 1.27 s / 4997 MB | 244 ms / 1.27 s / 6887 MB | 482 ms / 3.22 s / 9969 MB |
| five columns | pyarrow | 8 ms / 0.03 s / 180 MB | 9 ms / 0.02 s / 213 MB | 162 ms / 0.20 s / 304 MB |
| five columns | polars | 18 ms / 0.06 s / 138 MB | 18 ms / 0.08 s / 230 MB | 173 ms / 0.24 s / 285 MB |
| five columns | ours | 6 ms / 0.02 s / 142 MB | 7 ms / 0.03 s / 221 MB | 166 ms / 0.21 s / 291 MB |
| 1,000 rows | pyarrow | 38 ms / 0.32 s / 156 MB | 108 ms / 0.66 s / 3585 MB | 409 ms / 1.52 s / 7133 MB |
| 1,000 rows | polars | 37 ms / 0.23 s / 88 MB | 115 ms / 0.26 s / 352 MB | 55 ms / 0.28 s / 666 MB |
| 1,000 rows | ours | 10 ms / 0.05 s / 92 MB | 26 ms / 0.17 s / 944 MB | 115 ms / 0.49 s / 1842 MB |
| read + pass | pyarrow | 195 ms / 1.85 s / 5235 MB | 266 ms / 1.86 s / 7157 MB | 518 ms / 2.84 s / 10195 MB |
| read + pass | polars | 452 ms / 4.41 s / 4987 MB | 1.19 s / 4.98 s / 5664 MB | 808 ms / 5.39 s / 9828 MB |
| read + pass | ours | 161 ms / 1.46 s / 5013 MB | 257 ms / 1.41 s / 6885 MB | 559 ms / 3.32 s / 9972 MB |
| write, defaults | write | 733 ms / 6.05 s / 7699 MB | 759 ms / 6.82 s / 7864 MB | 6.40 s / 6.37 s / 6921 MB |
| write, zstd 3 | write | 1.21 s / 11.43 s / 7829 MB | 892 ms / 6.61 s / 8739 MB | 10.09 s / 10.07 s / 6921 MB |
| .dta read (ours, pandas) | dta | 776 ms / 2.33 s / 4961 MB | 592 ms / 1.41 s / 4977 MB | – |
| .dta write (ours, pandas) | dta | 1.55 s / 4.67 s / 4978 MB | 1.25 s / 2.38 s / 5004 MB | – |

### groups.dta

15,000,000 rows, 2 columns; .dta 270.0 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 14 ms / 0.09 s / 381 MB | 12 ms / 0.07 s / 416 MB | 222 ms / 0.35 s / 653 MB |
| whole file | polars | 14 ms / 0.10 s / 380 MB | 13 ms / 0.09 s / 431 MB | 200 ms / 0.45 s / 730 MB |
| whole file | ours | 14 ms / 0.09 s / 382 MB | 13 ms / 0.08 s / 428 MB | 200 ms / 0.42 s / 713 MB |
| five columns | pyarrow | 15 ms / 0.09 s / 379 MB | 14 ms / 0.08 s / 415 MB | 233 ms / 0.37 s / 675 MB |
| five columns | polars | 14 ms / 0.10 s / 380 MB | 14 ms / 0.09 s / 432 MB | 193 ms / 0.44 s / 733 MB |
| five columns | ours | 14 ms / 0.09 s / 382 MB | 13 ms / 0.08 s / 427 MB | 196 ms / 0.42 s / 706 MB |
| 1,000 rows | pyarrow | 0 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 83 MB | 10 ms / 0.01 s / 173 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 82 MB | 2 ms / 0.00 s / 112 MB |
| 1,000 rows | ours | 1 ms / 0.00 s / 66 MB | 3 ms / 0.01 s / 81 MB | 3 ms / 0.00 s / 125 MB |
| read + pass | pyarrow | 26 ms / 0.12 s / 571 MB | 25 ms / 0.10 s / 596 MB | 268 ms / 0.41 s / 744 MB |
| read + pass | polars | 26 ms / 0.13 s / 571 MB | 24 ms / 0.11 s / 615 MB | 243 ms / 0.48 s / 852 MB |
| read + pass | ours | 26 ms / 0.13 s / 573 MB | 29 ms / 0.10 s / 611 MB | 248 ms / 0.46 s / 812 MB |
| write, defaults | write | 108 ms / 0.46 s / 731 MB | 68 ms / 0.45 s / 542 MB | 562 ms / 0.56 s / 843 MB |
| write, zstd 3 | write | 108 ms / 0.45 s / 745 MB | 59 ms / 0.46 s / 541 MB | 583 ms / 0.58 s / 842 MB |
| .dta read (ours, pandas) | dta | 91 ms / 0.27 s / 592 MB | 481 ms / 0.67 s / 1164 MB | – |
| .dta write (ours, pandas) | dta | 513 ms / 0.51 s / 603 MB | 851 ms / 0.85 s / 2158 MB | – |

### 1973_FemResp

9,797 rows, 450 columns; .dta 5.7 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 3 ms / 0.01 s / 89 MB | 8 ms / 0.01 s / 104 MB | 162 ms / 0.18 s / 182 MB |
| whole file | polars | 4 ms / 0.01 s / 89 MB | 9 ms / 0.01 s / 104 MB | 160 ms / 0.18 s / 182 MB |
| whole file | ours | 4 ms / 0.01 s / 90 MB | 7 ms / 0.01 s / 105 MB | 159 ms / 0.18 s / 182 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 84 MB | 158 ms / 0.16 s / 150 MB |
| five columns | polars | 1 ms / 0.00 s / 65 MB | 3 ms / 0.01 s / 84 MB | 163 ms / 0.16 s / 152 MB |
| five columns | ours | 1 ms / 0.00 s / 67 MB | 3 ms / 0.01 s / 85 MB | 162 ms / 0.16 s / 151 MB |
| 1,000 rows | pyarrow | 3 ms / 0.00 s / 73 MB | 5 ms / 0.01 s / 87 MB | 7 ms / 0.03 s / 135 MB |
| 1,000 rows | polars | 2 ms / 0.01 s / 74 MB | 6 ms / 0.01 s / 87 MB | 7 ms / 0.03 s / 135 MB |
| 1,000 rows | ours | 3 ms / 0.00 s / 74 MB | 5 ms / 0.01 s / 88 MB | 6 ms / 0.03 s / 135 MB |
| read + pass | pyarrow | 9 ms / 0.02 s / 108 MB | 12 ms / 0.02 s / 114 MB | 174 ms / 0.20 s / 183 MB |
| read + pass | polars | 9 ms / 0.02 s / 108 MB | 13 ms / 0.02 s / 113 MB | 249 ms / 0.21 s / 183 MB |
| read + pass | ours | 9 ms / 0.02 s / 108 MB | 13 ms / 0.02 s / 112 MB | 182 ms / 0.20 s / 183 MB |
| write, defaults | write | 24 ms / 0.04 s / 111 MB | 11 ms / 0.05 s / 122 MB | 49 ms / 0.05 s / 151 MB |
| write, zstd 3 | write | 15 ms / 0.06 s / 113 MB | 14 ms / 0.06 s / 120 MB | 53 ms / 0.05 s / 151 MB |
| .dta read (ours, pandas) | dta | 12 ms / 0.01 s / 75 MB | 19 ms / 0.02 s / 170 MB | – |
| .dta write (ours, pandas) | dta | 44 ms / 0.04 s / 82 MB | 28 ms / 0.03 s / 177 MB | – |

### 1976_FemResp

8,611 rows, 468 columns; .dta 6.0 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 3 ms / 0.01 s / 87 MB | 8 ms / 0.01 s / 105 MB | 159 ms / 0.18 s / 183 MB |
| whole file | polars | 4 ms / 0.01 s / 87 MB | 9 ms / 0.01 s / 104 MB | 161 ms / 0.18 s / 183 MB |
| whole file | ours | 4 ms / 0.01 s / 89 MB | 7 ms / 0.01 s / 107 MB | 159 ms / 0.18 s / 184 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 84 MB | 151 ms / 0.15 s / 151 MB |
| five columns | polars | 1 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 85 MB | 153 ms / 0.15 s / 151 MB |
| five columns | ours | 1 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 85 MB | 155 ms / 0.16 s / 153 MB |
| 1,000 rows | pyarrow | 2 ms / 0.00 s / 73 MB | 5 ms / 0.01 s / 87 MB | 6 ms / 0.03 s / 135 MB |
| 1,000 rows | polars | 3 ms / 0.01 s / 73 MB | 7 ms / 0.01 s / 87 MB | 6 ms / 0.03 s / 136 MB |
| 1,000 rows | ours | 3 ms / 0.01 s / 75 MB | 5 ms / 0.01 s / 89 MB | 8 ms / 0.03 s / 136 MB |
| read + pass | pyarrow | 8 ms / 0.02 s / 106 MB | 12 ms / 0.02 s / 113 MB | 168 ms / 0.19 s / 183 MB |
| read + pass | polars | 8 ms / 0.03 s / 105 MB | 14 ms / 0.02 s / 113 MB | 165 ms / 0.19 s / 184 MB |
| read + pass | ours | 9 ms / 0.02 s / 108 MB | 12 ms / 0.02 s / 114 MB | 166 ms / 0.19 s / 186 MB |
| write, defaults | write | 9 ms / 0.04 s / 112 MB | 11 ms / 0.05 s / 122 MB | 47 ms / 0.05 s / 152 MB |
| write, zstd 3 | write | 12 ms / 0.05 s / 115 MB | 13 ms / 0.05 s / 121 MB | 54 ms / 0.05 s / 152 MB |
| .dta read (ours, pandas) | dta | 12 ms / 0.01 s / 75 MB | 16 ms / 0.02 s / 170 MB | – |
| .dta write (ours, pandas) | dta | 38 ms / 0.04 s / 84 MB | 26 ms / 0.03 s / 179 MB | – |

### 1976_PSU

8,611 rows, 3 columns; .dta 0.0 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 80 MB | 153 ms / 0.15 s / 149 MB |
| whole file | polars | 0 ms / 0.00 s / 64 MB | 2 ms / 0.01 s / 80 MB | 153 ms / 0.15 s / 150 MB |
| whole file | ours | 0 ms / 0.00 s / 63 MB | 2 ms / 0.01 s / 80 MB | 156 ms / 0.16 s / 149 MB |
| five columns | pyarrow | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 152 ms / 0.15 s / 149 MB |
| five columns | polars | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 82 MB | 151 ms / 0.15 s / 150 MB |
| five columns | ours | 0 ms / 0.00 s / 64 MB | 2 ms / 0.01 s / 81 MB | 154 ms / 0.15 s / 149 MB |
| 1,000 rows | pyarrow | 0 ms / 0.00 s / 64 MB | 2 ms / 0.01 s / 80 MB | 1 ms / 0.00 s / 103 MB |
| 1,000 rows | polars | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 81 MB | 1 ms / 0.00 s / 103 MB |
| 1,000 rows | ours | 0 ms / 0.00 s / 64 MB | 2 ms / 0.01 s / 81 MB | 0 ms / 0.00 s / 103 MB |
| read + pass | pyarrow | 1 ms / 0.00 s / 75 MB | 2 ms / 0.01 s / 84 MB | 152 ms / 0.15 s / 151 MB |
| read + pass | polars | 1 ms / 0.00 s / 76 MB | 2 ms / 0.01 s / 83 MB | 153 ms / 0.15 s / 150 MB |
| read + pass | ours | 1 ms / 0.00 s / 76 MB | 2 ms / 0.01 s / 83 MB | 156 ms / 0.16 s / 150 MB |
| write, defaults | write | 1 ms / 0.00 s / 83 MB | 1 ms / 0.00 s / 85 MB | 1 ms / 0.00 s / 123 MB |
| write, zstd 3 | write | 1 ms / 0.00 s / 84 MB | 1 ms / 0.00 s / 84 MB | 1 ms / 0.00 s / 123 MB |
| .dta read (ours, pandas) | dta | 0 ms / 0.00 s / 64 MB | 0 ms / 0.00 s / 141 MB | – |
| .dta write (ours, pandas) | dta | 0 ms / 0.00 s / 64 MB | 1 ms / 0.00 s / 141 MB | – |

### 1976_Preg

23,042 rows, 80 columns; .dta 2.4 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 1 ms / 0.00 s / 73 MB | 4 ms / 0.01 s / 91 MB | 160 ms / 0.17 s / 160 MB |
| whole file | polars | 1 ms / 0.00 s / 73 MB | 4 ms / 0.01 s / 90 MB | 153 ms / 0.16 s / 161 MB |
| whole file | ours | 1 ms / 0.00 s / 73 MB | 4 ms / 0.01 s / 91 MB | 155 ms / 0.16 s / 160 MB |
| five columns | pyarrow | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 83 MB | 152 ms / 0.15 s / 150 MB |
| five columns | polars | 0 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 83 MB | 153 ms / 0.15 s / 150 MB |
| five columns | ours | 0 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 83 MB | 152 ms / 0.15 s / 150 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 82 MB | 2 ms / 0.01 s / 114 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 66 MB | 3 ms / 0.01 s / 81 MB | 2 ms / 0.01 s / 114 MB |
| 1,000 rows | ours | 1 ms / 0.00 s / 66 MB | 3 ms / 0.01 s / 82 MB | 2 ms / 0.01 s / 114 MB |
| read + pass | pyarrow | 3 ms / 0.01 s / 88 MB | 5 ms / 0.01 s / 97 MB | 159 ms / 0.17 s / 162 MB |
| read + pass | polars | 3 ms / 0.01 s / 88 MB | 6 ms / 0.01 s / 98 MB | 159 ms / 0.17 s / 162 MB |
| read + pass | ours | 3 ms / 0.01 s / 89 MB | 5 ms / 0.01 s / 98 MB | 155 ms / 0.16 s / 161 MB |
| write, defaults | write | 4 ms / 0.01 s / 97 MB | 4 ms / 0.02 s / 103 MB | 17 ms / 0.02 s / 134 MB |
| write, zstd 3 | write | 4 ms / 0.01 s / 99 MB | 4 ms / 0.02 s / 102 MB | 18 ms / 0.02 s / 134 MB |
| .dta read (ours, pandas) | dta | 6 ms / 0.01 s / 69 MB | 7 ms / 0.01 s / 152 MB | – |
| .dta write (ours, pandas) | dta | 16 ms / 0.02 s / 72 MB | 8 ms / 0.01 s / 155 MB | – |

### 1982_FemResp

7,969 rows, 741 columns; .dta 7.6 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 4 ms / 0.01 s / 96 MB | 10 ms / 0.01 s / 112 MB | 162 ms / 0.20 s / 196 MB |
| whole file | polars | 5 ms / 0.01 s / 96 MB | 12 ms / 0.02 s / 112 MB | 165 ms / 0.20 s / 196 MB |
| whole file | ours | 6 ms / 0.01 s / 98 MB | 10 ms / 0.01 s / 112 MB | 165 ms / 0.20 s / 197 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 65 MB | 3 ms / 0.01 s / 85 MB | 158 ms / 0.16 s / 151 MB |
| five columns | polars | 1 ms / 0.00 s / 65 MB | 3 ms / 0.01 s / 84 MB | 154 ms / 0.15 s / 152 MB |
| five columns | ours | 1 ms / 0.00 s / 66 MB | 3 ms / 0.01 s / 86 MB | 154 ms / 0.15 s / 152 MB |
| 1,000 rows | pyarrow | 3 ms / 0.01 s / 75 MB | 6 ms / 0.01 s / 90 MB | 9 ms / 0.04 s / 148 MB |
| 1,000 rows | polars | 3 ms / 0.01 s / 75 MB | 8 ms / 0.01 s / 90 MB | 9 ms / 0.05 s / 149 MB |
| 1,000 rows | ours | 4 ms / 0.01 s / 77 MB | 6 ms / 0.01 s / 91 MB | 9 ms / 0.04 s / 149 MB |
| read + pass | pyarrow | 11 ms / 0.03 s / 117 MB | 16 ms / 0.03 s / 123 MB | 178 ms / 0.21 s / 197 MB |
| read + pass | polars | 12 ms / 0.03 s / 118 MB | 19 ms / 0.03 s / 122 MB | 178 ms / 0.21 s / 197 MB |
| read + pass | ours | 13 ms / 0.03 s / 119 MB | 16 ms / 0.03 s / 123 MB | 178 ms / 0.21 s / 198 MB |
| write, defaults | write | 15 ms / 0.05 s / 119 MB | 13 ms / 0.07 s / 134 MB | 66 ms / 0.07 s / 159 MB |
| write, zstd 3 | write | 18 ms / 0.06 s / 121 MB | 14 ms / 0.07 s / 132 MB | 73 ms / 0.07 s / 159 MB |
| .dta read (ours, pandas) | dta | 17 ms / 0.02 s / 79 MB | 24 ms / 0.02 s / 176 MB | – |
| .dta write (ours, pandas) | dta | 57 ms / 0.06 s / 88 MB | 40 ms / 0.04 s / 185 MB | – |

### 1982_Preg

13,768 rows, 174 columns; .dta 3.0 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 1 ms / 0.00 s / 75 MB | 4 ms / 0.01 s / 93 MB | 156 ms / 0.17 s / 165 MB |
| whole file | polars | 2 ms / 0.00 s / 75 MB | 5 ms / 0.01 s / 93 MB | 163 ms / 0.17 s / 166 MB |
| whole file | ours | 2 ms / 0.00 s / 77 MB | 4 ms / 0.01 s / 94 MB | 154 ms / 0.16 s / 167 MB |
| five columns | pyarrow | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 83 MB | 156 ms / 0.16 s / 150 MB |
| five columns | polars | 0 ms / 0.00 s / 65 MB | 2 ms / 0.01 s / 83 MB | 153 ms / 0.15 s / 150 MB |
| five columns | ours | 1 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 83 MB | 152 ms / 0.15 s / 150 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 67 MB | 3 ms / 0.01 s / 82 MB | 3 ms / 0.01 s / 119 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 67 MB | 3 ms / 0.01 s / 83 MB | 3 ms / 0.01 s / 120 MB |
| 1,000 rows | ours | 1 ms / 0.00 s / 68 MB | 3 ms / 0.01 s / 83 MB | 3 ms / 0.01 s / 119 MB |
| read + pass | pyarrow | 4 ms / 0.01 s / 91 MB | 6 ms / 0.01 s / 99 MB | 156 ms / 0.17 s / 167 MB |
| read + pass | polars | 4 ms / 0.01 s / 91 MB | 7 ms / 0.02 s / 99 MB | 157 ms / 0.17 s / 167 MB |
| read + pass | ours | 4 ms / 0.01 s / 93 MB | 6 ms / 0.02 s / 100 MB | 157 ms / 0.17 s / 167 MB |
| write, defaults | write | 4 ms / 0.02 s / 98 MB | 5 ms / 0.02 s / 104 MB | 18 ms / 0.02 s / 136 MB |
| write, zstd 3 | write | 5 ms / 0.02 s / 99 MB | 5 ms / 0.02 s / 104 MB | 20 ms / 0.02 s / 136 MB |
| .dta read (ours, pandas) | dta | 7 ms / 0.01 s / 70 MB | 11 ms / 0.01 s / 159 MB | – |
| .dta write (ours, pandas) | dta | 18 ms / 0.02 s / 74 MB | 12 ms / 0.01 s / 163 MB | – |

### 1988_FemResp

8,450 rows, 1,437 columns; .dta 19.1 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 8 ms / 0.02 s / 125 MB | 19 ms / 0.02 s / 154 MB | 179 ms / 0.24 s / 244 MB |
| whole file | polars | 10 ms / 0.03 s / 125 MB | 25 ms / 0.03 s / 153 MB | 177 ms / 0.25 s / 243 MB |
| whole file | ours | 11 ms / 0.03 s / 129 MB | 19 ms / 0.02 s / 155 MB | 178 ms / 0.24 s / 245 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 66 MB | 3 ms / 0.01 s / 86 MB | 158 ms / 0.16 s / 154 MB |
| five columns | polars | 1 ms / 0.00 s / 66 MB | 3 ms / 0.01 s / 87 MB | 155 ms / 0.16 s / 154 MB |
| five columns | ours | 2 ms / 0.00 s / 67 MB | 3 ms / 0.01 s / 88 MB | 157 ms / 0.16 s / 157 MB |
| 1,000 rows | pyarrow | 5 ms / 0.01 s / 82 MB | 11 ms / 0.01 s / 100 MB | 17 ms / 0.08 s / 195 MB |
| 1,000 rows | polars | 7 ms / 0.02 s / 82 MB | 17 ms / 0.02 s / 99 MB | 17 ms / 0.09 s / 194 MB |
| 1,000 rows | ours | 7 ms / 0.01 s / 84 MB | 10 ms / 0.02 s / 100 MB | 16 ms / 0.08 s / 196 MB |
| read + pass | pyarrow | 20 ms / 0.05 s / 151 MB | 31 ms / 0.05 s / 170 MB | 193 ms / 0.26 s / 244 MB |
| read + pass | polars | 21 ms / 0.05 s / 152 MB | 36 ms / 0.05 s / 169 MB | 193 ms / 0.26 s / 243 MB |
| read + pass | ours | 23 ms / 0.05 s / 154 MB | 30 ms / 0.05 s / 170 MB | 192 ms / 0.26 s / 246 MB |
| write, defaults | write | 26 ms / 0.12 s / 165 MB | 25 ms / 0.16 s / 197 MB | 140 ms / 0.14 s / 205 MB |
| write, zstd 3 | write | 29 ms / 0.14 s / 168 MB | 26 ms / 0.16 s / 196 MB | 158 ms / 0.16 s / 206 MB |
| .dta read (ours, pandas) | dta | 19 ms / 0.05 s / 106 MB | 36 ms / 0.05 s / 246 MB | – |
| .dta write (ours, pandas) | dta | 57 ms / 0.11 s / 127 MB | 58 ms / 0.08 s / 265 MB | – |

### 1988_Preg

15,759 rows, 284 columns; .dta 10.7 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 3 ms / 0.01 s / 87 MB | 8 ms / 0.01 s / 109 MB | 158 ms / 0.17 s / 179 MB |
| whole file | polars | 4 ms / 0.01 s / 88 MB | 10 ms / 0.01 s / 108 MB | 156 ms / 0.17 s / 179 MB |
| whole file | ours | 4 ms / 0.01 s / 89 MB | 8 ms / 0.01 s / 109 MB | 160 ms / 0.18 s / 179 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 68 MB | 2 ms / 0.01 s / 84 MB | 152 ms / 0.15 s / 150 MB |
| five columns | polars | 1 ms / 0.00 s / 69 MB | 2 ms / 0.01 s / 84 MB | 152 ms / 0.15 s / 150 MB |
| five columns | ours | 1 ms / 0.00 s / 69 MB | 2 ms / 0.01 s / 84 MB | 159 ms / 0.16 s / 151 MB |
| 1,000 rows | pyarrow | 2 ms / 0.01 s / 71 MB | 5 ms / 0.01 s / 87 MB | 4 ms / 0.02 s / 132 MB |
| 1,000 rows | polars | 2 ms / 0.01 s / 72 MB | 7 ms / 0.01 s / 86 MB | 5 ms / 0.02 s / 132 MB |
| 1,000 rows | ours | 3 ms / 0.01 s / 73 MB | 5 ms / 0.01 s / 88 MB | 5 ms / 0.02 s / 132 MB |
| read + pass | pyarrow | 7 ms / 0.02 s / 105 MB | 11 ms / 0.02 s / 117 MB | 162 ms / 0.18 s / 180 MB |
| read + pass | polars | 7 ms / 0.02 s / 106 MB | 14 ms / 0.02 s / 117 MB | 161 ms / 0.18 s / 180 MB |
| read + pass | ours | 7 ms / 0.02 s / 107 MB | 11 ms / 0.02 s / 117 MB | 160 ms / 0.18 s / 180 MB |
| write, defaults | write | 10 ms / 0.04 s / 117 MB | 14 ms / 0.07 s / 130 MB | 53 ms / 0.05 s / 154 MB |
| write, zstd 3 | write | 11 ms / 0.04 s / 119 MB | 11 ms / 0.07 s / 134 MB | 61 ms / 0.06 s / 154 MB |
| .dta read (ours, pandas) | dta | 13 ms / 0.01 s / 80 MB | 14 ms / 0.01 s / 169 MB | – |
| .dta write (ours, pandas) | dta | 34 ms / 0.03 s / 90 MB | 18 ms / 0.02 s / 179 MB | – |

### 1995_FemResp

10,847 rows, 5,754 columns; .dta 78.9 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 1995_Preg

21,332 rows, 245 columns; .dta 6.2 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2002_FemPreg

13,593 rows, 243 columns; .dta 4.3 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2002_FemResp

7,643 rows, 3,087 columns; .dta 29.3 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 13 ms / 0.03 s / 175 MB | 23 ms / 0.03 s / 203 MB | 194 ms / 0.30 s / 330 MB |
| whole file | polars | 14 ms / 0.04 s / 175 MB | 26 ms / 0.04 s / 204 MB | 194 ms / 0.31 s / 329 MB |
| whole file | ours | 17 ms / 0.04 s / 182 MB | 22 ms / 0.03 s / 207 MB | 190 ms / 0.29 s / 334 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 71 MB | 5 ms / 0.01 s / 91 MB | 160 ms / 0.16 s / 160 MB |
| five columns | polars | 2 ms / 0.00 s / 71 MB | 5 ms / 0.01 s / 90 MB | 161 ms / 0.16 s / 160 MB |
| five columns | ours | 4 ms / 0.00 s / 74 MB | 5 ms / 0.01 s / 95 MB | 173 ms / 0.17 s / 166 MB |
| 1,000 rows | pyarrow | 9 ms / 0.02 s / 96 MB | 13 ms / 0.02 s / 112 MB | 32 ms / 0.13 s / 277 MB |
| 1,000 rows | polars | 10 ms / 0.02 s / 95 MB | 16 ms / 0.02 s / 111 MB | 32 ms / 0.15 s / 277 MB |
| 1,000 rows | ours | 13 ms / 0.02 s / 102 MB | 12 ms / 0.02 s / 115 MB | 30 ms / 0.13 s / 279 MB |
| read + pass | pyarrow | 37 ms / 0.08 s / 218 MB | 45 ms / 0.08 s / 230 MB | 226 ms / 0.33 s / 330 MB |
| read + pass | polars | 38 ms / 0.08 s / 218 MB | 49 ms / 0.08 s / 230 MB | 225 ms / 0.35 s / 330 MB |
| read + pass | ours | 41 ms / 0.08 s / 226 MB | 45 ms / 0.08 s / 231 MB | 234 ms / 0.34 s / 335 MB |
| write, defaults | write | 39 ms / 0.19 s / 222 MB | 30 ms / 0.18 s / 255 MB | 185 ms / 0.19 s / 267 MB |
| write, zstd 3 | write | 36 ms / 0.21 s / 227 MB | 32 ms / 0.18 s / 255 MB | 202 ms / 0.20 s / 267 MB |
| .dta read (ours, pandas) | dta | 30 ms / 0.07 s / 123 MB | 70 ms / 0.10 s / 308 MB | – |
| .dta write (ours, pandas) | dta | 96 ms / 0.19 s / 148 MB | 115 ms / 0.16 s / 333 MB | – |

### 2002_HHvars

12,571 rows, 10 columns; .dta 0.1 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2002_Male

4,928 rows, 1,993 columns; .dta 12.7 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2002_curr_ins

12,571 rows, 3 columns; .dta 0.1 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2002_hhpartypnew

12,571 rows, 3 columns; .dta 0.1 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2006_2010_FemPreg

20,492 rows, 287 columns; .dta 7.6 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2006_2010_FemResp

12,279 rows, 3,741 columns; .dta 55.6 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 19 ms / 0.06 s / 256 MB | 25 ms / 0.06 s / 298 MB | 202 ms / 0.36 s / 403 MB |
| whole file | polars | 19 ms / 0.07 s / 256 MB | 27 ms / 0.06 s / 297 MB | 203 ms / 0.37 s / 404 MB |
| whole file | ours | 24 ms / 0.07 s / 267 MB | 25 ms / 0.06 s / 301 MB | 201 ms / 0.35 s / 410 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 72 MB | 5 ms / 0.01 s / 94 MB | 160 ms / 0.16 s / 162 MB |
| five columns | polars | 3 ms / 0.00 s / 71 MB | 5 ms / 0.01 s / 94 MB | 161 ms / 0.16 s / 163 MB |
| five columns | ours | 5 ms / 0.01 s / 75 MB | 5 ms / 0.01 s / 98 MB | 164 ms / 0.16 s / 171 MB |
| 1,000 rows | pyarrow | 11 ms / 0.02 s / 101 MB | 13 ms / 0.03 s / 124 MB | 42 ms / 0.19 s / 352 MB |
| 1,000 rows | polars | 12 ms / 0.03 s / 100 MB | 16 ms / 0.03 s / 122 MB | 43 ms / 0.21 s / 350 MB |
| 1,000 rows | ours | 16 ms / 0.02 s / 112 MB | 13 ms / 0.03 s / 126 MB | 40 ms / 0.19 s / 353 MB |
| read + pass | pyarrow | 48 ms / 0.13 s / 310 MB | 52 ms / 0.12 s / 327 MB | 254 ms / 0.41 s / 404 MB |
| read + pass | polars | 50 ms / 0.13 s / 310 MB | 56 ms / 0.12 s / 326 MB | 254 ms / 0.43 s / 404 MB |
| read + pass | ours | 54 ms / 0.13 s / 322 MB | 53 ms / 0.11 s / 328 MB | 252 ms / 0.41 s / 411 MB |
| write, defaults | write | 54 ms / 0.34 s / 320 MB | 49 ms / 0.33 s / 358 MB | 335 ms / 0.33 s / 367 MB |
| write, zstd 3 | write | 54 ms / 0.36 s / 329 MB | 54 ms / 0.33 s / 357 MB | 360 ms / 0.36 s / 368 MB |
| .dta read (ours, pandas) | dta | 53 ms / 0.13 s / 158 MB | 116 ms / 0.17 s / 433 MB | – |
| .dta write (ours, pandas) | dta | 184 ms / 0.36 s / 182 MB | 171 ms / 0.26 s / 458 MB | – |

### 2006_2010_Male

10,403 rows, 2,801 columns; .dta 37.2 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2011_2013_FemPreg

9,543 rows, 278 columns; .dta 3.5 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2011_2013_FemResp

5,601 rows, 3,094 columns; .dta 22.6 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2011_2013_Male

4,815 rows, 3,059 columns; .dta 19.4 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 11 ms / 0.02 s / 141 MB | 20 ms / 0.02 s / 162 MB | 200 ms / 0.29 s / 264 MB |
| whole file | polars | 12 ms / 0.03 s / 142 MB | 23 ms / 0.03 s / 162 MB | 197 ms / 0.29 s / 264 MB |
| whole file | ours | 14 ms / 0.03 s / 145 MB | 19 ms / 0.02 s / 163 MB | 197 ms / 0.27 s / 268 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 68 MB | 5 ms / 0.01 s / 91 MB | 167 ms / 0.17 s / 160 MB |
| five columns | polars | 2 ms / 0.00 s / 68 MB | 4 ms / 0.01 s / 90 MB | 170 ms / 0.17 s / 159 MB |
| five columns | ours | 3 ms / 0.00 s / 69 MB | 5 ms / 0.01 s / 92 MB | 170 ms / 0.17 s / 163 MB |
| 1,000 rows | pyarrow | 9 ms / 0.02 s / 95 MB | 14 ms / 0.02 s / 110 MB | 32 ms / 0.12 s / 212 MB |
| 1,000 rows | polars | 9 ms / 0.02 s / 95 MB | 17 ms / 0.02 s / 110 MB | 32 ms / 0.13 s / 213 MB |
| 1,000 rows | ours | 11 ms / 0.02 s / 99 MB | 13 ms / 0.02 s / 111 MB | 32 ms / 0.11 s / 214 MB |
| read + pass | pyarrow | 35 ms / 0.07 s / 179 MB | 43 ms / 0.06 s / 186 MB | 227 ms / 0.31 s / 265 MB |
| read + pass | polars | 36 ms / 0.07 s / 179 MB | 46 ms / 0.06 s / 186 MB | 227 ms / 0.32 s / 266 MB |
| read + pass | ours | 37 ms / 0.07 s / 184 MB | 43 ms / 0.06 s / 187 MB | 224 ms / 0.31 s / 268 MB |
| write, defaults | write | 28 ms / 0.13 s / 174 MB | 30 ms / 0.13 s / 204 MB | 129 ms / 0.13 s / 222 MB |
| write, zstd 3 | write | 31 ms / 0.15 s / 176 MB | 29 ms / 0.13 s / 205 MB | 143 ms / 0.14 s / 222 MB |
| .dta read (ours, pandas) | dta | 19 ms / 0.04 s / 110 MB | 52 ms / 0.07 s / 259 MB | – |
| .dta write (ours, pandas) | dta | 63 ms / 0.11 s / 132 MB | 101 ms / 0.12 s / 282 MB | – |

### 2011_2019_FemaleWgt

22,995 rows, 7 columns; .dta 1.2 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2011_2019_MaleWgt

19,067 rows, 7 columns; .dta 1.0 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2013_2015_FemPreg

9,358 rows, 278 columns; .dta 3.4 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2013_2015_FemResp

5,699 rows, 3,207 columns; .dta 24.0 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2013_2015_Male

4,506 rows, 2,940 columns; .dta 18.0 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2015_2017_FemPreg

9,553 rows, 248 columns; .dta 3.0 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 2 ms / 0.00 s / 77 MB | 5 ms / 0.01 s / 94 MB | 163 ms / 0.17 s / 168 MB |
| whole file | polars | 2 ms / 0.01 s / 77 MB | 5 ms / 0.01 s / 94 MB | 163 ms / 0.17 s / 168 MB |
| whole file | ours | 2 ms / 0.01 s / 78 MB | 4 ms / 0.01 s / 94 MB | 157 ms / 0.17 s / 168 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 83 MB | 160 ms / 0.16 s / 151 MB |
| five columns | polars | 1 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 84 MB | 153 ms / 0.15 s / 150 MB |
| five columns | ours | 1 ms / 0.00 s / 66 MB | 2 ms / 0.01 s / 84 MB | 152 ms / 0.15 s / 150 MB |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 69 MB | 3 ms / 0.01 s / 84 MB | 3 ms / 0.01 s / 121 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 68 MB | 4 ms / 0.01 s / 85 MB | 3 ms / 0.02 s / 121 MB |
| 1,000 rows | ours | 1 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 84 MB | 3 ms / 0.01 s / 121 MB |
| read + pass | pyarrow | 5 ms / 0.02 s / 94 MB | 7 ms / 0.02 s / 101 MB | 160 ms / 0.17 s / 170 MB |
| read + pass | polars | 5 ms / 0.02 s / 93 MB | 7 ms / 0.02 s / 101 MB | 158 ms / 0.17 s / 168 MB |
| read + pass | ours | 5 ms / 0.02 s / 94 MB | 7 ms / 0.02 s / 102 MB | 160 ms / 0.17 s / 169 MB |
| write, defaults | write | 5 ms / 0.02 s / 99 MB | 5 ms / 0.03 s / 106 MB | 23 ms / 0.02 s / 139 MB |
| write, zstd 3 | write | 5 ms / 0.02 s / 101 MB | 5 ms / 0.03 s / 107 MB | 25 ms / 0.03 s / 139 MB |
| .dta read (ours, pandas) | dta | 7 ms / 0.01 s / 71 MB | 10 ms / 0.01 s / 157 MB | – |
| .dta write (ours, pandas) | dta | 20 ms / 0.02 s / 75 MB | 14 ms / 0.01 s / 161 MB | – |

### 2015_2017_FemResp

5,554 rows, 3,024 columns; .dta 21.7 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2015_2017_Male

4,540 rows, 2,945 columns; .dta 17.7 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2017_2019_FemPreg

10,215 rows, 171 columns; .dta 2.2 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2017_2019_FemResp

6,141 rows, 2,609 columns; .dta 20.2 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2017_2019_Male

5,206 rows, 3,009 columns; .dta 20.1 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2022_2023_FemPreg

8,247 rows, 111 columns; .dta 1.2 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### 2022_2023_FemResp

5,586 rows, 1,912 columns; .dta 13.3 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 8 ms / 0.02 s / 120 MB | 17 ms / 0.02 s / 142 MB | 176 ms / 0.25 s / 246 MB |
| whole file | polars | 9 ms / 0.02 s / 121 MB | 21 ms / 0.03 s / 142 MB | 188 ms / 0.25 s / 247 MB |
| whole file | ours | 10 ms / 0.02 s / 122 MB | 17 ms / 0.02 s / 143 MB | 187 ms / 0.25 s / 246 MB |
| five columns | pyarrow | 2 ms / 0.00 s / 67 MB | 4 ms / 0.01 s / 88 MB | 171 ms / 0.17 s / 156 MB |
| five columns | polars | 1 ms / 0.00 s / 66 MB | 7 ms / 0.01 s / 88 MB | 169 ms / 0.17 s / 155 MB |
| five columns | ours | 2 ms / 0.00 s / 67 MB | 4 ms / 0.01 s / 88 MB | 166 ms / 0.17 s / 156 MB |
| 1,000 rows | pyarrow | 6 ms / 0.01 s / 85 MB | 11 ms / 0.02 s / 102 MB | 23 ms / 0.09 s / 197 MB |
| 1,000 rows | polars | 7 ms / 0.01 s / 85 MB | 15 ms / 0.02 s / 101 MB | 22 ms / 0.09 s / 198 MB |
| 1,000 rows | ours | 7 ms / 0.01 s / 86 MB | 11 ms / 0.02 s / 102 MB | 23 ms / 0.08 s / 197 MB |
| read + pass | pyarrow | 25 ms / 0.05 s / 149 MB | 33 ms / 0.05 s / 159 MB | 215 ms / 0.27 s / 249 MB |
| read + pass | polars | 27 ms / 0.06 s / 149 MB | 38 ms / 0.05 s / 158 MB | 215 ms / 0.28 s / 248 MB |
| read + pass | ours | 26 ms / 0.05 s / 151 MB | 33 ms / 0.05 s / 158 MB | 210 ms / 0.27 s / 248 MB |
| write, defaults | write | 27 ms / 0.11 s / 151 MB | 25 ms / 0.12 s / 174 MB | 111 ms / 0.11 s / 195 MB |
| write, zstd 3 | write | 29 ms / 0.12 s / 152 MB | 26 ms / 0.12 s / 172 MB | 124 ms / 0.12 s / 196 MB |
| .dta read (ours, pandas) | dta | 27 ms / 0.03 s / 86 MB | 48 ms / 0.05 s / 220 MB | – |
| .dta write (ours, pandas) | dta | 96 ms / 0.10 s / 99 MB | 87 ms / 0.09 s / 231 MB | – |

### 2022_2023_MaleResp

4,371 rows, 1,157 columns; .dta 6.3 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | – | – | – |
| whole file | polars | – | – | – |
| whole file | ours | – | – | – |
| five columns | pyarrow | – | – | – |
| five columns | polars | – | – | – |
| five columns | ours | – | – | – |
| 1,000 rows | pyarrow | – | – | – |
| 1,000 rows | polars | – | – | – |
| 1,000 rows | ours | – | – | – |
| read + pass | pyarrow | – | – | – |
| read + pass | polars | – | – | – |
| read + pass | ours | – | – | – |
| write, defaults | write | – | – | – |
| write, zstd 3 | write | – | – | – |
| .dta read (ours, pandas) | dta | – | – | – |
| .dta write (ours, pandas) | dta | – | – | – |

### Senegal 2019 wm

8,649 rows, 4,997 columns; .dta 49.1 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 17 ms / 0.05 s / 215 MB | 21 ms / 0.05 s / 321 MB | 216 ms / 0.37 s / 443 MB |
| whole file | polars | 17 ms / 0.05 s / 216 MB | 22 ms / 0.05 s / 320 MB | 213 ms / 0.39 s / 443 MB |
| whole file | ours | 21 ms / 0.05 s / 222 MB | 21 ms / 0.05 s / 323 MB | 212 ms / 0.36 s / 445 MB |
| five columns | pyarrow | 4 ms / 0.00 s / 73 MB | 6 ms / 0.01 s / 96 MB | 167 ms / 0.17 s / 168 MB |
| five columns | polars | 3 ms / 0.00 s / 73 MB | 6 ms / 0.01 s / 95 MB | 164 ms / 0.17 s / 167 MB |
| five columns | ours | 5 ms / 0.01 s / 74 MB | 6 ms / 0.01 s / 98 MB | 163 ms / 0.16 s / 171 MB |
| 1,000 rows | pyarrow | 12 ms / 0.02 s / 112 MB | 12 ms / 0.02 s / 129 MB | 48 ms / 0.21 s / 385 MB |
| 1,000 rows | polars | 13 ms / 0.02 s / 113 MB | 14 ms / 0.03 s / 128 MB | 48 ms / 0.22 s / 384 MB |
| 1,000 rows | ours | 16 ms / 0.02 s / 120 MB | 12 ms / 0.02 s / 132 MB | 46 ms / 0.20 s / 386 MB |
| read + pass | pyarrow | 53 ms / 0.10 s / 270 MB | 55 ms / 0.10 s / 359 MB | 265 ms / 0.43 s / 442 MB |
| read + pass | polars | 53 ms / 0.11 s / 270 MB | 56 ms / 0.10 s / 359 MB | 263 ms / 0.44 s / 440 MB |
| read + pass | ours | 59 ms / 0.11 s / 276 MB | 55 ms / 0.10 s / 358 MB | 260 ms / 0.42 s / 444 MB |
| write, defaults | write | 44 ms / 0.28 s / 344 MB | 49 ms / 0.30 s / 389 MB | 246 ms / 0.25 s / 397 MB |
| write, zstd 3 | write | 52 ms / 0.31 s / 351 MB | 47 ms / 0.30 s / 390 MB | 265 ms / 0.26 s / 396 MB |
| .dta read (ours, pandas) | dta | 47 ms / 0.12 s / 151 MB | 121 ms / 0.18 s / 522 MB | – |
| .dta write (ours, pandas) | dta | 156 ms / 0.30 s / 178 MB | 178 ms / 0.26 s / 548 MB | – |

### Senegal 2019 bh

21,562 rows, 1,191 columns; .dta 28.9 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 10 ms / 0.03 s / 154 MB | 20 ms / 0.03 s / 219 MB | 181 ms / 0.26 s / 298 MB |
| whole file | polars | 13 ms / 0.03 s / 154 MB | 22 ms / 0.04 s / 218 MB | 185 ms / 0.26 s / 299 MB |
| whole file | ours | 11 ms / 0.03 s / 155 MB | 19 ms / 0.03 s / 218 MB | 183 ms / 0.25 s / 298 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 88 MB | 161 ms / 0.16 s / 155 MB |
| five columns | polars | 2 ms / 0.00 s / 69 MB | 4 ms / 0.01 s / 87 MB | 167 ms / 0.17 s / 156 MB |
| five columns | ours | 2 ms / 0.00 s / 70 MB | 4 ms / 0.01 s / 87 MB | 166 ms / 0.17 s / 155 MB |
| 1,000 rows | pyarrow | 5 ms / 0.01 s / 80 MB | 10 ms / 0.02 s / 96 MB | 26 ms / 0.10 s / 248 MB |
| 1,000 rows | polars | 6 ms / 0.01 s / 80 MB | 12 ms / 0.02 s / 95 MB | 29 ms / 0.09 s / 249 MB |
| 1,000 rows | ours | 6 ms / 0.01 s / 81 MB | 10 ms / 0.02 s / 97 MB | 25 ms / 0.09 s / 250 MB |
| read + pass | pyarrow | 23 ms / 0.06 s / 180 MB | 32 ms / 0.06 s / 234 MB | 216 ms / 0.28 s / 303 MB |
| read + pass | polars | 33 ms / 0.06 s / 177 MB | 53 ms / 0.07 s / 231 MB | 234 ms / 0.29 s / 299 MB |
| read + pass | ours | 42 ms / 0.06 s / 179 MB | 49 ms / 0.06 s / 234 MB | 317 ms / 0.30 s / 300 MB |
| write, defaults | write | 67 ms / 0.21 s / 235 MB | 39 ms / 0.20 s / 249 MB | 178 ms / 0.18 s / 271 MB |
| write, zstd 3 | write | 42 ms / 0.21 s / 242 MB | 32 ms / 0.20 s / 251 MB | 197 ms / 0.19 s / 271 MB |
| .dta read (ours, pandas) | dta | 27 ms / 0.07 s / 114 MB | 60 ms / 0.09 s / 321 MB | – |
| .dta write (ours, pandas) | dta | 107 ms / 0.20 s / 132 MB | 75 ms / 0.11 s / 342 MB | – |

### Turkey 2013 wm

9,746 rows, 4,668 columns; .dta 52.6 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 15 ms / 0.04 s / 212 MB | 19 ms / 0.05 s / 309 MB | 212 ms / 0.37 s / 429 MB |
| whole file | polars | 17 ms / 0.05 s / 214 MB | 20 ms / 0.05 s / 308 MB | 215 ms / 0.38 s / 430 MB |
| whole file | ours | 20 ms / 0.05 s / 218 MB | 28 ms / 0.05 s / 309 MB | 224 ms / 0.35 s / 431 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 73 MB | 6 ms / 0.01 s / 96 MB | 176 ms / 0.18 s / 167 MB |
| five columns | polars | 3 ms / 0.00 s / 73 MB | 7 ms / 0.01 s / 95 MB | 174 ms / 0.17 s / 166 MB |
| five columns | ours | 5 ms / 0.01 s / 75 MB | 6 ms / 0.01 s / 99 MB | 175 ms / 0.18 s / 170 MB |
| 1,000 rows | pyarrow | 12 ms / 0.02 s / 110 MB | 13 ms / 0.03 s / 129 MB | 52 ms / 0.20 s / 372 MB |
| 1,000 rows | polars | 13 ms / 0.02 s / 110 MB | 15 ms / 0.03 s / 129 MB | 56 ms / 0.19 s / 378 MB |
| 1,000 rows | ours | 15 ms / 0.02 s / 117 MB | 13 ms / 0.03 s / 130 MB | 49 ms / 0.18 s / 373 MB |
| read + pass | pyarrow | 81 ms / 0.11 s / 270 MB | 87 ms / 0.10 s / 344 MB | 294 ms / 0.42 s / 435 MB |
| read + pass | polars | 61 ms / 0.11 s / 268 MB | 62 ms / 0.11 s / 342 MB | 273 ms / 0.43 s / 427 MB |
| read + pass | ours | 58 ms / 0.11 s / 277 MB | 52 ms / 0.10 s / 343 MB | 259 ms / 0.40 s / 434 MB |
| write, defaults | write | 58 ms / 0.31 s / 332 MB | 49 ms / 0.30 s / 376 MB | 255 ms / 0.25 s / 384 MB |
| write, zstd 3 | write | 61 ms / 0.32 s / 339 MB | 50 ms / 0.30 s / 376 MB | 272 ms / 0.27 s / 383 MB |
| .dta read (ours, pandas) | dta | 48 ms / 0.12 s / 157 MB | 119 ms / 0.18 s / 506 MB | – |
| .dta write (ours, pandas) | dta | 160 ms / 0.31 s / 184 MB | 173 ms / 0.26 s / 532 MB | – |

### Turkey 2013 bh

17,871 rows, 1,173 columns; .dta 23.3 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 8 ms / 0.02 s / 132 MB | 17 ms / 0.03 s / 197 MB | 177 ms / 0.24 s / 277 MB |
| whole file | polars | 9 ms / 0.03 s / 133 MB | 18 ms / 0.03 s / 197 MB | 178 ms / 0.24 s / 276 MB |
| whole file | ours | 9 ms / 0.02 s / 135 MB | 16 ms / 0.03 s / 198 MB | 175 ms / 0.24 s / 277 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 69 MB | 3 ms / 0.01 s / 86 MB | 161 ms / 0.16 s / 155 MB |
| five columns | polars | 1 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 87 MB | 155 ms / 0.16 s / 155 MB |
| five columns | ours | 2 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 87 MB | 156 ms / 0.16 s / 157 MB |
| 1,000 rows | pyarrow | 4 ms / 0.01 s / 79 MB | 8 ms / 0.01 s / 95 MB | 16 ms / 0.08 s / 227 MB |
| 1,000 rows | polars | 5 ms / 0.01 s / 80 MB | 10 ms / 0.02 s / 96 MB | 16 ms / 0.08 s / 227 MB |
| 1,000 rows | ours | 5 ms / 0.01 s / 81 MB | 7 ms / 0.01 s / 97 MB | 15 ms / 0.08 s / 228 MB |
| read + pass | pyarrow | 18 ms / 0.05 s / 159 MB | 26 ms / 0.05 s / 213 MB | 193 ms / 0.26 s / 277 MB |
| read + pass | polars | 23 ms / 0.05 s / 157 MB | 29 ms / 0.05 s / 213 MB | 197 ms / 0.26 s / 277 MB |
| read + pass | ours | 20 ms / 0.05 s / 160 MB | 27 ms / 0.05 s / 213 MB | 204 ms / 0.26 s / 280 MB |
| write, defaults | write | 49 ms / 0.16 s / 213 MB | 31 ms / 0.17 s / 228 MB | 144 ms / 0.14 s / 248 MB |
| write, zstd 3 | write | 39 ms / 0.18 s / 218 MB | 36 ms / 0.17 s / 231 MB | 155 ms / 0.15 s / 248 MB |
| .dta read (ours, pandas) | dta | 21 ms / 0.06 s / 107 MB | 46 ms / 0.07 s / 297 MB | – |
| .dta write (ours, pandas) | dta | 75 ms / 0.15 s / 127 MB | 56 ms / 0.08 s / 317 MB | – |

### Tajikistan 2017 wm

10,718 rows, 5,160 columns; .dta 63.8 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 18 ms / 0.06 s / 246 MB | 22 ms / 0.06 s / 377 MB | 354 ms / 0.41 s / 507 MB |
| whole file | polars | 21 ms / 0.07 s / 246 MB | 41 ms / 0.07 s / 376 MB | 604 ms / 0.42 s / 513 MB |
| whole file | ours | 45 ms / 0.07 s / 253 MB | 35 ms / 0.06 s / 380 MB | 224 ms / 0.38 s / 500 MB |
| five columns | pyarrow | 4 ms / 0.00 s / 73 MB | 7 ms / 0.01 s / 97 MB | 168 ms / 0.17 s / 169 MB |
| five columns | polars | 3 ms / 0.00 s / 73 MB | 6 ms / 0.01 s / 96 MB | 165 ms / 0.17 s / 168 MB |
| five columns | ours | 5 ms / 0.01 s / 75 MB | 6 ms / 0.01 s / 99 MB | 169 ms / 0.17 s / 171 MB |
| 1,000 rows | pyarrow | 13 ms / 0.02 s / 114 MB | 13 ms / 0.03 s / 134 MB | 56 ms / 0.23 s / 442 MB |
| 1,000 rows | polars | 14 ms / 0.03 s / 115 MB | 14 ms / 0.04 s / 133 MB | 64 ms / 0.25 s / 443 MB |
| 1,000 rows | ours | 19 ms / 0.03 s / 121 MB | 32 ms / 0.04 s / 137 MB | 105 ms / 0.25 s / 443 MB |
| read + pass | pyarrow | 77 ms / 0.12 s / 299 MB | 83 ms / 0.14 s / 415 MB | 327 ms / 0.47 s / 511 MB |
| read + pass | polars | 82 ms / 0.13 s / 301 MB | 90 ms / 0.14 s / 414 MB | 461 ms / 0.50 s / 519 MB |
| read + pass | ours | 107 ms / 0.12 s / 307 MB | 78 ms / 0.13 s / 415 MB | 284 ms / 0.45 s / 500 MB |
| write, defaults | write | 68 ms / 0.37 s / 402 MB | 61 ms / 0.38 s / 447 MB | 313 ms / 0.31 s / 455 MB |
| write, zstd 3 | write | 72 ms / 0.39 s / 411 MB | 58 ms / 0.38 s / 449 MB | 331 ms / 0.33 s / 455 MB |
| .dta read (ours, pandas) | dta | 58 ms / 0.15 s / 169 MB | 144 ms / 0.22 s / 558 MB | – |
| .dta write (ours, pandas) | dta | 199 ms / 0.39 s / 197 MB | 238 ms / 0.35 s / 584 MB | – |

### Tajikistan 2017 bh

21,985 rows, 1,146 columns; .dta 29.4 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 9 ms / 0.03 s / 154 MB | 19 ms / 0.03 s / 216 MB | 174 ms / 0.25 s / 293 MB |
| whole file | polars | 10 ms / 0.03 s / 154 MB | 21 ms / 0.04 s / 215 MB | 177 ms / 0.25 s / 293 MB |
| whole file | ours | 11 ms / 0.03 s / 156 MB | 20 ms / 0.03 s / 216 MB | 184 ms / 0.25 s / 295 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 88 MB | 162 ms / 0.16 s / 155 MB |
| five columns | polars | 1 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 87 MB | 155 ms / 0.16 s / 155 MB |
| five columns | ours | 2 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 87 MB | 156 ms / 0.16 s / 155 MB |
| 1,000 rows | pyarrow | 4 ms / 0.01 s / 79 MB | 8 ms / 0.02 s / 97 MB | 18 ms / 0.09 s / 245 MB |
| 1,000 rows | polars | 5 ms / 0.01 s / 80 MB | 11 ms / 0.02 s / 97 MB | 19 ms / 0.09 s / 244 MB |
| 1,000 rows | ours | 5 ms / 0.01 s / 82 MB | 9 ms / 0.02 s / 98 MB | 18 ms / 0.09 s / 246 MB |
| read + pass | pyarrow | 20 ms / 0.06 s / 181 MB | 30 ms / 0.06 s / 232 MB | 194 ms / 0.27 s / 294 MB |
| read + pass | polars | 21 ms / 0.06 s / 182 MB | 30 ms / 0.06 s / 231 MB | 191 ms / 0.26 s / 294 MB |
| read + pass | ours | 21 ms / 0.06 s / 183 MB | 28 ms / 0.05 s / 232 MB | 189 ms / 0.26 s / 295 MB |
| write, defaults | write | 29 ms / 0.19 s / 234 MB | 28 ms / 0.20 s / 254 MB | 177 ms / 0.18 s / 268 MB |
| write, zstd 3 | write | 32 ms / 0.20 s / 243 MB | 29 ms / 0.20 s / 254 MB | 196 ms / 0.20 s / 268 MB |
| .dta read (ours, pandas) | dta | 23 ms / 0.06 s / 113 MB | 51 ms / 0.08 s / 308 MB | – |
| .dta write (ours, pandas) | dta | 89 ms / 0.18 s / 133 MB | 60 ms / 0.10 s / 329 MB | – |

### Myanmar 2016 wm

12,885 rows, 4,993 columns; .dta 72.0 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 18 ms / 0.07 s / 253 MB | 23 ms / 0.06 s / 409 MB | 216 ms / 0.41 s / 565 MB |
| whole file | polars | 18 ms / 0.07 s / 253 MB | 21 ms / 0.06 s / 408 MB | 219 ms / 0.42 s / 568 MB |
| whole file | ours | 22 ms / 0.07 s / 260 MB | 20 ms / 0.06 s / 411 MB | 215 ms / 0.40 s / 567 MB |
| five columns | pyarrow | 4 ms / 0.00 s / 73 MB | 6 ms / 0.01 s / 96 MB | 165 ms / 0.17 s / 168 MB |
| five columns | polars | 3 ms / 0.00 s / 73 MB | 6 ms / 0.01 s / 96 MB | 165 ms / 0.17 s / 166 MB |
| five columns | ours | 5 ms / 0.01 s / 76 MB | 6 ms / 0.01 s / 99 MB | 164 ms / 0.16 s / 171 MB |
| 1,000 rows | pyarrow | 12 ms / 0.02 s / 113 MB | 12 ms / 0.03 s / 132 MB | 51 ms / 0.25 s / 507 MB |
| 1,000 rows | polars | 13 ms / 0.02 s / 113 MB | 13 ms / 0.03 s / 132 MB | 52 ms / 0.26 s / 511 MB |
| 1,000 rows | ours | 16 ms / 0.02 s / 120 MB | 12 ms / 0.03 s / 135 MB | 48 ms / 0.23 s / 510 MB |
| read + pass | pyarrow | 56 ms / 0.13 s / 310 MB | 53 ms / 0.11 s / 447 MB | 275 ms / 0.47 s / 565 MB |
| read + pass | polars | 56 ms / 0.14 s / 311 MB | 57 ms / 0.12 s / 446 MB | 272 ms / 0.47 s / 567 MB |
| read + pass | ours | 59 ms / 0.13 s / 318 MB | 55 ms / 0.12 s / 447 MB | 268 ms / 0.45 s / 568 MB |
| write, defaults | write | 64 ms / 0.38 s / 433 MB | 63 ms / 0.41 s / 480 MB | 339 ms / 0.34 s / 486 MB |
| write, zstd 3 | write | 79 ms / 0.41 s / 441 MB | 57 ms / 0.41 s / 482 MB | 353 ms / 0.35 s / 486 MB |
| .dta read (ours, pandas) | dta | 61 ms / 0.16 s / 179 MB | 152 ms / 0.23 s / 640 MB | – |
| .dta write (ours, pandas) | dta | 208 ms / 0.42 s / 206 MB | 201 ms / 0.32 s / 667 MB | – |

### Myanmar 2016 bh

22,989 rows, 1,184 columns; .dta 30.7 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 10 ms / 0.03 s / 158 MB | 19 ms / 0.03 s / 225 MB | 174 ms / 0.25 s / 297 MB |
| whole file | polars | 10 ms / 0.03 s / 158 MB | 21 ms / 0.03 s / 223 MB | 176 ms / 0.25 s / 299 MB |
| whole file | ours | 11 ms / 0.03 s / 159 MB | 20 ms / 0.03 s / 225 MB | 176 ms / 0.25 s / 297 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 87 MB | 163 ms / 0.16 s / 155 MB |
| five columns | polars | 1 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 87 MB | 157 ms / 0.16 s / 156 MB |
| five columns | ours | 2 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 87 MB | 156 ms / 0.16 s / 156 MB |
| 1,000 rows | pyarrow | 4 ms / 0.01 s / 80 MB | 9 ms / 0.02 s / 96 MB | 17 ms / 0.09 s / 249 MB |
| 1,000 rows | polars | 5 ms / 0.01 s / 80 MB | 11 ms / 0.02 s / 96 MB | 17 ms / 0.09 s / 250 MB |
| 1,000 rows | ours | 5 ms / 0.01 s / 81 MB | 9 ms / 0.02 s / 97 MB | 18 ms / 0.08 s / 249 MB |
| read + pass | pyarrow | 21 ms / 0.06 s / 185 MB | 30 ms / 0.06 s / 241 MB | 199 ms / 0.27 s / 299 MB |
| read + pass | polars | 21 ms / 0.06 s / 186 MB | 32 ms / 0.06 s / 241 MB | 198 ms / 0.27 s / 298 MB |
| read + pass | ours | 24 ms / 0.06 s / 186 MB | 29 ms / 0.05 s / 242 MB | 197 ms / 0.27 s / 300 MB |
| write, defaults | write | 37 ms / 0.18 s / 242 MB | 29 ms / 0.20 s / 261 MB | 188 ms / 0.19 s / 277 MB |
| write, zstd 3 | write | 38 ms / 0.21 s / 251 MB | 29 ms / 0.20 s / 260 MB | 205 ms / 0.21 s / 276 MB |
| .dta read (ours, pandas) | dta | 25 ms / 0.07 s / 114 MB | 54 ms / 0.08 s / 319 MB | – |
| .dta write (ours, pandas) | dta | 97 ms / 0.19 s / 134 MB | 64 ms / 0.10 s / 339 MB | – |

### Dominican Republic 2013 wm

9,372 rows, 3,854 columns; .dta 39.7 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 15 ms / 0.04 s / 189 MB | 21 ms / 0.04 s / 269 MB | 211 ms / 0.33 s / 376 MB |
| whole file | polars | 15 ms / 0.04 s / 189 MB | 22 ms / 0.04 s / 268 MB | 212 ms / 0.34 s / 378 MB |
| whole file | ours | 18 ms / 0.04 s / 194 MB | 19 ms / 0.04 s / 269 MB | 206 ms / 0.32 s / 378 MB |
| five columns | pyarrow | 3 ms / 0.00 s / 71 MB | 5 ms / 0.01 s / 94 MB | 167 ms / 0.17 s / 164 MB |
| five columns | polars | 3 ms / 0.00 s / 72 MB | 5 ms / 0.01 s / 95 MB | 166 ms / 0.17 s / 163 MB |
| five columns | ours | 4 ms / 0.00 s / 72 MB | 5 ms / 0.01 s / 96 MB | 166 ms / 0.17 s / 166 MB |
| 1,000 rows | pyarrow | 10 ms / 0.02 s / 102 MB | 11 ms / 0.02 s / 121 MB | 42 ms / 0.17 s / 322 MB |
| 1,000 rows | polars | 10 ms / 0.02 s / 102 MB | 13 ms / 0.03 s / 120 MB | 42 ms / 0.17 s / 324 MB |
| 1,000 rows | ours | 12 ms / 0.02 s / 106 MB | 11 ms / 0.02 s / 122 MB | 37 ms / 0.16 s / 323 MB |
| read + pass | pyarrow | 43 ms / 0.08 s / 234 MB | 47 ms / 0.08 s / 297 MB | 244 ms / 0.37 s / 378 MB |
| read + pass | polars | 43 ms / 0.09 s / 235 MB | 50 ms / 0.09 s / 298 MB | 240 ms / 0.39 s / 377 MB |
| read + pass | ours | 46 ms / 0.09 s / 240 MB | 46 ms / 0.08 s / 297 MB | 242 ms / 0.36 s / 378 MB |
| write, defaults | write | 44 ms / 0.24 s / 287 MB | 43 ms / 0.26 s / 322 MB | 214 ms / 0.21 s / 334 MB |
| write, zstd 3 | write | 44 ms / 0.26 s / 296 MB | 40 ms / 0.25 s / 323 MB | 230 ms / 0.23 s / 333 MB |
| .dta read (ours, pandas) | dta | 36 ms / 0.09 s / 135 MB | 96 ms / 0.14 s / 436 MB | – |
| .dta write (ours, pandas) | dta | 132 ms / 0.26 s / 161 MB | 146 ms / 0.22 s / 461 MB | – |

### Dominican Republic 2013 bh

18,167 rows, 1,078 columns; .dta 22.2 MB.

| case | input | ours (Arrow path, whole Meta) | polars | pyarrow (Table) |
|---|---|---|---|---|
| whole file | pyarrow | 8 ms / 0.02 s / 137 MB | 19 ms / 0.03 s / 190 MB | 173 ms / 0.24 s / 266 MB |
| whole file | polars | 9 ms / 0.03 s / 138 MB | 22 ms / 0.03 s / 190 MB | 175 ms / 0.24 s / 268 MB |
| whole file | ours | 9 ms / 0.02 s / 138 MB | 19 ms / 0.03 s / 190 MB | 175 ms / 0.23 s / 269 MB |
| five columns | pyarrow | 1 ms / 0.00 s / 69 MB | 3 ms / 0.01 s / 86 MB | 153 ms / 0.15 s / 155 MB |
| five columns | polars | 1 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 87 MB | 155 ms / 0.16 s / 155 MB |
| five columns | ours | 2 ms / 0.00 s / 70 MB | 3 ms / 0.01 s / 87 MB | 161 ms / 0.16 s / 156 MB |
| 1,000 rows | pyarrow | 4 ms / 0.01 s / 78 MB | 9 ms / 0.02 s / 95 MB | 15 ms / 0.08 s / 219 MB |
| 1,000 rows | polars | 5 ms / 0.01 s / 79 MB | 12 ms / 0.02 s / 94 MB | 16 ms / 0.08 s / 218 MB |
| 1,000 rows | ours | 5 ms / 0.01 s / 80 MB | 9 ms / 0.01 s / 96 MB | 16 ms / 0.08 s / 219 MB |
| read + pass | pyarrow | 18 ms / 0.05 s / 163 MB | 29 ms / 0.05 s / 206 MB | 193 ms / 0.25 s / 269 MB |
| read + pass | polars | 19 ms / 0.05 s / 163 MB | 32 ms / 0.05 s / 205 MB | 193 ms / 0.26 s / 268 MB |
| read + pass | ours | 19 ms / 0.05 s / 164 MB | 30 ms / 0.05 s / 206 MB | 197 ms / 0.26 s / 269 MB |
| write, defaults | write | 27 ms / 0.14 s / 205 MB | 27 ms / 0.17 s / 221 MB | 141 ms / 0.14 s / 241 MB |
| write, zstd 3 | write | 29 ms / 0.16 s / 212 MB | 25 ms / 0.16 s / 222 MB | 152 ms / 0.15 s / 241 MB |
| .dta read (ours, pandas) | dta | 19 ms / 0.05 s / 106 MB | 43 ms / 0.07 s / 286 MB | – |
| .dta write (ours, pandas) | dta | 72 ms / 0.15 s / 125 MB | 54 ms / 0.08 s / 306 MB | – |

