# Parquet benchmarks (Python, datakit into pandas)

**Scope of this run (plan 0024, stage 4, 2026-11-09).** DHS family only
(10 files), reading the files datakit writes (`--inputs ours`): the NSFG
and synthetic `.dta` sources were not on the machine that ran it. The
polars-era numbers for every family are in
[parquet-datakit.md](parquet-datakit.md), kept as they were.

Written by `bench/parquet/run_polars.py`; bench/RESULTS.md says what the numbers mean.

One-minute load average before each run: median 3.9, range 2.4 to 5.1 (plan 0018 asks for under 2).

| library | version | threads |
|---|---|---|
| datakit | datakit 0.4.0 | default |
| dta_parser (pandas) | dta_parser (pandas) | default |
| pandas (pyarrow engine) | pandas 3.1.1, pyarrow 26.0.1 | 16 |
| polars | 2.1.0 | 16 |
| pyarrow (Table) | 26.0.1 | 16 |

## Ratios, ours to theirs (geometric means)

Below 1 is better for us. Plan 0024 sets no speed target; plan 0018's target 1 (wall and RSS at most 1.05 on NSFG and DHS) is reported for comparison. Writes are of the frame each library's reader gives of our file.

| against | case | input | family | files | wall | CPU | peak RSS |
|---|---|---|---|---|---|---|---|
| pandas (pyarrow engine) | whole file | ours | DHS | 10 | 1.25 | 0.23 | 0.89 |
| pandas (pyarrow engine) | five columns | ours | DHS | 10 | 0.19 | 0.20 | 0.89 |
| pandas (pyarrow engine) | 1,000 rows | ours | DHS | 10 | 1.25 | 0.23 | 0.49 |
| pandas (pyarrow engine) | read + pass | ours | DHS | 10 | 0.99 | 0.36 | 0.89 |
| pandas (pyarrow engine) | write, defaults | write | DHS | 10 | 0.38 | 0.87 | 1.21 |
| pandas (pyarrow engine) | write, zstd 3 | write | DHS | 10 | 0.37 | 0.89 | 1.23 |
| polars | whole file | ours | DHS | 10 | 4.36 | 2.94 | 1.98 |
| polars | five columns | ours | DHS | 10 | 0.98 | 0.52 | 1.24 |
| polars | 1,000 rows | ours | DHS | 10 | 4.42 | 2.62 | 1.47 |
| polars | read + pass | ours | DHS | 10 | 4.80 | 2.77 | 1.82 |
| polars | write, defaults | write | DHS | 10 | 4.10 | 1.02 | 2.29 |
| polars | write, zstd 3 | write | DHS | 10 | 4.16 | 1.08 | 2.31 |
| pyarrow (Table) | whole file | ours | DHS | 10 | 0.57 | 0.36 | 1.47 |
| pyarrow (Table) | five columns | ours | DHS | 10 | 0.03 | 0.04 | 0.73 |
| pyarrow (Table) | 1,000 rows | ours | DHS | 10 | 2.09 | 0.29 | 0.53 |
| pyarrow (Table) | read + pass | ours | DHS | 10 | 1.02 | 0.61 | 1.46 |
| pyarrow (Table) | write, defaults | write | DHS | 10 | 0.57 | 1.31 | 2.25 |
| pyarrow (Table) | write, zstd 3 | write | DHS | 10 | 0.54 | 1.29 | 2.28 |

## .dta into pandas against dta_parser's reader and writer (published, not gated)

| case | family | files | wall | CPU | peak RSS |
|---|---|---|---|---|---|
| .dta read | DHS | 10 | 0.39 | 0.51 | 0.93 |
| .dta write | DHS | 10 | 1.95 | 1.87 | 1.08 |

## Plan 0018's targets that do not hold (reported, not required)

- 1 wall: pdarrow full ours dhs: geometric mean 1.25x
- 2 wall: pdarrow full ours Senegal 2019 wm: 141 ms vs 98 ms (1.44x)
- 2 wall: pdarrow full ours Turkey 2013 wm: 126 ms vs 94 ms (1.35x)
- 2 wall: pdarrow full ours Tajikistan 2017 wm: 137 ms vs 99 ms (1.39x)
- 2 wall: pdarrow full ours Myanmar 2016 wm: 145 ms vs 104 ms (1.39x)
- 2 wall: pdarrow full ours Dominican Republic 2013 wm: 100 ms vs 77 ms (1.30x)
- 1 wall: pdarrow window ours dhs: geometric mean 1.25x
- 2 wall: pdarrow window ours Senegal 2019 wm: 85 ms vs 63 ms (1.36x)
- 2 wall: pdarrow window ours Turkey 2013 wm: 81 ms vs 58 ms (1.40x)
- 2 wall: pdarrow window ours Tajikistan 2017 wm: 86 ms vs 63 ms (1.37x)
- 1 RSS: pdarrow write write dhs: geometric mean 1.21x
- 2 RSS: pdarrow write write Senegal 2019 wm: 1016 vs 773 MB (1.31x)
- 2 RSS: pdarrow write write Turkey 2013 wm: 980 vs 777 MB (1.26x)
- 2 RSS: pdarrow write write Tajikistan 2017 wm: 1165 vs 929 MB (1.25x)
- 2 RSS: pdarrow write write Dominican Republic 2013 wm: 821 vs 645 MB (1.27x)
- 1 RSS: pdarrow zstd write dhs: geometric mean 1.23x
- 2 RSS: pdarrow zstd write Senegal 2019 wm: 1022 vs 773 MB (1.32x)
- 2 RSS: pdarrow zstd write Turkey 2013 wm: 988 vs 775 MB (1.27x)
- 2 RSS: pdarrow zstd write Tajikistan 2017 wm: 1173 vs 924 MB (1.27x)
- 2 RSS: pdarrow zstd write Dominican Republic 2013 wm: 828 vs 646 MB (1.28x)
- 1 wall: polars full ours dhs: geometric mean 4.36x
- 1 RSS: polars full ours dhs: geometric mean 1.98x
- 2 wall: polars full ours Senegal 2019 wm: 141 ms vs 18 ms (7.68x)
- 2 RSS: polars full ours Senegal 2019 wm: 702 vs 322 MB (2.18x)
- 3 CPU: polars full ours Senegal 2019 wm: 0.169 s vs 0.040 s, speedup 0.13 allows 0.046 s
- 2 wall: polars full ours Senegal 2019 bh: 49 ms vs 19 ms (2.64x)
- 2 RSS: polars full ours Senegal 2019 bh: 394 vs 216 MB (1.82x)
- 3 CPU: polars full ours Senegal 2019 bh: 0.067 s vs 0.029 s, speedup 0.38 allows 0.033 s
- 2 wall: polars full ours Turkey 2013 wm: 126 ms vs 18 ms (7.16x)
- 2 RSS: polars full ours Turkey 2013 wm: 677 vs 308 MB (2.20x)
- 3 CPU: polars full ours Turkey 2013 wm: 0.156 s vs 0.040 s, speedup 0.14 allows 0.046 s
- 2 wall: polars full ours Turkey 2013 bh: 42 ms vs 15 ms (2.86x)
- 2 RSS: polars full ours Turkey 2013 bh: 344 vs 196 MB (1.75x)
- 3 CPU: polars full ours Turkey 2013 bh: 0.055 s vs 0.023 s, speedup 0.35 allows 0.027 s
- 2 wall: polars full ours Tajikistan 2017 wm: 137 ms vs 20 ms (6.92x)
- 2 RSS: polars full ours Tajikistan 2017 wm: 830 vs 377 MB (2.20x)
- 3 CPU: polars full ours Tajikistan 2017 wm: 0.169 s vs 0.051 s, speedup 0.14 allows 0.058 s
- 2 wall: polars full ours Tajikistan 2017 bh: 49 ms vs 16 ms (3.01x)
- 2 RSS: polars full ours Tajikistan 2017 bh: 372 vs 215 MB (1.73x)
- 3 CPU: polars full ours Tajikistan 2017 bh: 0.066 s vs 0.028 s, speedup 0.33 allows 0.032 s
- 2 wall: polars full ours Myanmar 2016 wm: 145 ms vs 17 ms (8.32x)
- 2 RSS: polars full ours Myanmar 2016 wm: 913 vs 409 MB (2.23x)
- 3 CPU: polars full ours Myanmar 2016 wm: 0.189 s vs 0.050 s, speedup 0.12 allows 0.058 s
- 2 wall: polars full ours Myanmar 2016 bh: 47 ms vs 18 ms (2.65x)
- 2 RSS: polars full ours Myanmar 2016 bh: 408 vs 223 MB (1.83x)
- 3 CPU: polars full ours Myanmar 2016 bh: 0.064 s vs 0.029 s, speedup 0.38 allows 0.033 s
- 2 wall: polars full ours Dominican Republic 2013 wm: 100 ms vs 18 ms (5.51x)
- 2 RSS: polars full ours Dominican Republic 2013 wm: 574 vs 268 MB (2.14x)
- 3 CPU: polars full ours Dominican Republic 2013 wm: 0.118 s vs 0.035 s, speedup 0.18 allows 0.040 s
- 2 wall: polars full ours Dominican Republic 2013 bh: 40 ms vs 17 ms (2.35x)
- 2 RSS: polars full ours Dominican Republic 2013 bh: 335 vs 189 MB (1.78x)
- 3 CPU: polars full ours Dominican Republic 2013 bh: 0.054 s vs 0.023 s, speedup 0.43 allows 0.027 s
- 1 RSS: polars five ours dhs: geometric mean 1.24x
- 2 RSS: polars five ours Senegal 2019 bh: 111 vs 86 MB (1.30x)
- 2 RSS: polars five ours Turkey 2013 bh: 110 vs 85 MB (1.30x)
- 2 RSS: polars five ours Tajikistan 2017 bh: 111 vs 85 MB (1.30x)
- 2 RSS: polars five ours Myanmar 2016 bh: 111 vs 85 MB (1.29x)
- 2 RSS: polars five ours Dominican Republic 2013 bh: 110 vs 85 MB (1.30x)
- 1 wall: polars window ours dhs: geometric mean 4.42x
- 1 RSS: polars window ours dhs: geometric mean 1.47x
- 2 wall: polars window ours Senegal 2019 wm: 85 ms vs 11 ms (7.50x)
- 2 RSS: polars window ours Senegal 2019 wm: 211 vs 130 MB (1.62x)
- 3 CPU: polars window ours Senegal 2019 wm: 0.091 s vs 0.022 s, speedup 0.13 allows 0.026 s
- 2 RSS: polars window ours Senegal 2019 bh: 130 vs 95 MB (1.37x)
- 3 CPU: polars window ours Senegal 2019 bh: 0.027 s vs 0.014 s, speedup 0.34 allows 0.016 s
- 2 wall: polars window ours Turkey 2013 wm: 81 ms vs 11 ms (7.55x)
- 2 RSS: polars window ours Turkey 2013 wm: 206 vs 128 MB (1.61x)
- 3 CPU: polars window ours Turkey 2013 wm: 0.087 s vs 0.021 s, speedup 0.13 allows 0.025 s
- 2 RSS: polars window ours Turkey 2013 bh: 130 vs 94 MB (1.37x)
- 3 CPU: polars window ours Turkey 2013 bh: 0.024 s vs 0.012 s, speedup 0.32 allows 0.014 s
- 2 wall: polars window ours Tajikistan 2017 wm: 86 ms vs 11 ms (7.62x)
- 2 RSS: polars window ours Tajikistan 2017 wm: 214 vs 134 MB (1.59x)
- 3 CPU: polars window ours Tajikistan 2017 wm: 0.093 s vs 0.025 s, speedup 0.13 allows 0.028 s
- 2 RSS: polars window ours Tajikistan 2017 bh: 129 vs 96 MB (1.34x)
- 3 CPU: polars window ours Tajikistan 2017 bh: 0.025 s vs 0.016 s, speedup 0.41 allows 0.018 s
- 2 wall: polars window ours Myanmar 2016 wm: 84 ms vs 11 ms (7.83x)
- 2 RSS: polars window ours Myanmar 2016 wm: 211 vs 133 MB (1.59x)
- 3 CPU: polars window ours Myanmar 2016 wm: 0.090 s vs 0.025 s, speedup 0.13 allows 0.029 s
- 2 RSS: polars window ours Myanmar 2016 bh: 130 vs 96 MB (1.36x)
- 3 CPU: polars window ours Myanmar 2016 bh: 0.025 s vs 0.015 s, speedup 0.38 allows 0.017 s
- 2 wall: polars window ours Dominican Republic 2013 wm: 66 ms vs 11 ms (6.18x)
- 2 RSS: polars window ours Dominican Republic 2013 wm: 186 vs 120 MB (1.55x)
- 3 CPU: polars window ours Dominican Republic 2013 wm: 0.071 s vs 0.019 s, speedup 0.16 allows 0.022 s
- 2 RSS: polars window ours Dominican Republic 2013 bh: 128 vs 94 MB (1.37x)
- 3 CPU: polars window ours Dominican Republic 2013 bh: 0.023 s vs 0.013 s, speedup 0.43 allows 0.015 s
- 1 wall: polars pass ours dhs: geometric mean 4.80x
- 1 RSS: polars pass ours dhs: geometric mean 1.82x
- 2 wall: polars pass ours Senegal 2019 wm: 289 ms vs 51 ms (5.65x)
- 2 RSS: polars pass ours Senegal 2019 wm: 701 vs 358 MB (1.96x)
- 3 CPU: polars pass ours Senegal 2019 wm: 0.310 s vs 0.092 s, speedup 0.18 allows 0.105 s
- 2 wall: polars pass ours Senegal 2019 bh: 107 ms vs 28 ms (3.87x)
- 2 RSS: polars pass ours Senegal 2019 bh: 395 vs 233 MB (1.70x)
- 3 CPU: polars pass ours Senegal 2019 bh: 0.124 s vs 0.053 s, speedup 0.26 allows 0.061 s
- 2 wall: polars pass ours Turkey 2013 wm: 289 ms vs 47 ms (6.14x)
- 2 RSS: polars pass ours Turkey 2013 wm: 677 vs 342 MB (1.98x)
- 3 CPU: polars pass ours Turkey 2013 wm: 0.312 s vs 0.089 s, speedup 0.16 allows 0.103 s
- 2 wall: polars pass ours Turkey 2013 bh: 88 ms vs 22 ms (3.95x)
- 2 RSS: polars pass ours Turkey 2013 bh: 344 vs 212 MB (1.63x)
- 3 CPU: polars pass ours Turkey 2013 bh: 0.101 s vs 0.043 s, speedup 0.25 allows 0.049 s
- 2 wall: polars pass ours Tajikistan 2017 wm: 312 ms vs 49 ms (6.31x)
- 2 RSS: polars pass ours Tajikistan 2017 wm: 831 vs 414 MB (2.01x)
- 3 CPU: polars pass ours Tajikistan 2017 wm: 0.342 s vs 0.104 s, speedup 0.16 allows 0.119 s
- 2 wall: polars pass ours Tajikistan 2017 bh: 95 ms vs 24 ms (3.94x)
- 2 RSS: polars pass ours Tajikistan 2017 bh: 373 vs 230 MB (1.62x)
- 3 CPU: polars pass ours Tajikistan 2017 bh: 0.113 s vs 0.048 s, speedup 0.25 allows 0.056 s
- 2 wall: polars pass ours Myanmar 2016 wm: 325 ms vs 46 ms (7.01x)
- 2 RSS: polars pass ours Myanmar 2016 wm: 913 vs 445 MB (2.05x)
- 3 CPU: polars pass ours Myanmar 2016 wm: 0.373 s vs 0.104 s, speedup 0.14 allows 0.120 s
- 2 wall: polars pass ours Myanmar 2016 bh: 100 ms vs 26 ms (3.89x)
- 2 RSS: polars pass ours Myanmar 2016 bh: 408 vs 240 MB (1.70x)
- 3 CPU: polars pass ours Myanmar 2016 bh: 0.118 s vs 0.053 s, speedup 0.26 allows 0.060 s
- 2 wall: polars pass ours Dominican Republic 2013 wm: 210 ms vs 41 ms (5.12x)
- 2 RSS: polars pass ours Dominican Republic 2013 wm: 574 vs 296 MB (1.94x)
- 3 CPU: polars pass ours Dominican Republic 2013 wm: 0.228 s vs 0.077 s, speedup 0.20 allows 0.088 s
- 2 wall: polars pass ours Dominican Republic 2013 bh: 86 ms vs 24 ms (3.53x)
- 2 RSS: polars pass ours Dominican Republic 2013 bh: 336 vs 204 MB (1.65x)
- 3 CPU: polars pass ours Dominican Republic 2013 bh: 0.100 s vs 0.044 s, speedup 0.28 allows 0.051 s
- 1 wall: polars write write dhs: geometric mean 4.10x
- 1 RSS: polars write write dhs: geometric mean 2.29x
- 2 wall: polars write write Senegal 2019 wm: 165 ms vs 35 ms (4.68x)
- 2 RSS: polars write write Senegal 2019 wm: 1016 vs 394 MB (2.58x)
- 2 wall: polars write write Senegal 2019 bh: 76 ms vs 19 ms (3.90x)
- 2 RSS: polars write write Senegal 2019 bh: 540 vs 255 MB (2.12x)
- 2 wall: polars write write Turkey 2013 wm: 162 ms vs 38 ms (4.32x)
- 2 RSS: polars write write Turkey 2013 wm: 980 vs 382 MB (2.56x)
- 2 wall: polars write write Turkey 2013 bh: 63 ms vs 16 ms (3.88x)
- 2 RSS: polars write write Turkey 2013 bh: 470 vs 236 MB (1.99x)
- 2 wall: polars write write Tajikistan 2017 wm: 188 ms vs 44 ms (4.24x)
- 2 RSS: polars write write Tajikistan 2017 wm: 1165 vs 455 MB (2.56x)
- 2 wall: polars write write Tajikistan 2017 bh: 64 ms vs 19 ms (3.44x)
- 2 RSS: polars write write Tajikistan 2017 bh: 505 vs 258 MB (1.96x)
- 2 wall: polars write write Myanmar 2016 wm: 198 ms vs 44 ms (4.46x)
- 2 RSS: polars write write Myanmar 2016 wm: 1326 vs 489 MB (2.71x)
- 2 wall: polars write write Myanmar 2016 bh: 70 ms vs 20 ms (3.56x)
- 2 RSS: polars write write Myanmar 2016 bh: 550 vs 265 MB (2.07x)
- 2 wall: polars write write Dominican Republic 2013 wm: 143 ms vs 31 ms (4.66x)
- 2 RSS: polars write write Dominican Republic 2013 wm: 821 vs 328 MB (2.50x)
- 2 wall: polars write write Dominican Republic 2013 bh: 65 ms vs 16 ms (4.06x)
- 2 RSS: polars write write Dominican Republic 2013 bh: 453 vs 227 MB (2.00x)
- 1 wall: polars zstd write dhs: geometric mean 4.16x
- 1 RSS: polars zstd write dhs: geometric mean 2.31x
- 2 wall: polars zstd write Senegal 2019 wm: 170 ms vs 38 ms (4.50x)
- 2 RSS: polars zstd write Senegal 2019 wm: 1022 vs 393 MB (2.60x)
- 3 CPU: polars zstd write Senegal 2019 wm: 0.358 s vs 0.293 s, speedup 0.22 allows 0.337 s
- 2 wall: polars zstd write Senegal 2019 bh: 78 ms vs 20 ms (3.98x)
- 2 RSS: polars zstd write Senegal 2019 bh: 548 vs 255 MB (2.15x)
- 2 wall: polars zstd write Turkey 2013 wm: 164 ms vs 38 ms (4.30x)
- 2 RSS: polars zstd write Turkey 2013 wm: 988 vs 382 MB (2.58x)
- 3 CPU: polars zstd write Turkey 2013 wm: 0.348 s vs 0.301 s, speedup 0.23 allows 0.346 s
- 2 wall: polars zstd write Turkey 2013 bh: 64 ms vs 17 ms (3.84x)
- 2 RSS: polars zstd write Turkey 2013 bh: 476 vs 236 MB (2.02x)
- 2 wall: polars zstd write Tajikistan 2017 wm: 189 ms vs 42 ms (4.55x)
- 2 RSS: polars zstd write Tajikistan 2017 wm: 1173 vs 453 MB (2.59x)
- 3 CPU: polars zstd write Tajikistan 2017 wm: 0.426 s vs 0.369 s, speedup 0.22 allows 0.424 s
- 2 wall: polars zstd write Tajikistan 2017 bh: 65 ms vs 19 ms (3.53x)
- 2 RSS: polars zstd write Tajikistan 2017 bh: 514 vs 258 MB (1.99x)
- 2 wall: polars zstd write Myanmar 2016 wm: 205 ms vs 43 ms (4.73x)
- 2 RSS: polars zstd write Myanmar 2016 wm: 1333 vs 489 MB (2.73x)
- 2 wall: polars zstd write Myanmar 2016 bh: 73 ms vs 20 ms (3.62x)
- 2 RSS: polars zstd write Myanmar 2016 bh: 560 vs 267 MB (2.10x)
- 2 wall: polars zstd write Dominican Republic 2013 wm: 137 ms vs 30 ms (4.63x)
- 2 RSS: polars zstd write Dominican Republic 2013 wm: 828 vs 328 MB (2.52x)
- 3 CPU: polars zstd write Dominican Republic 2013 wm: 0.295 s vs 0.248 s, speedup 0.22 allows 0.285 s
- 2 wall: polars zstd write Dominican Republic 2013 bh: 64 ms vs 16 ms (4.11x)
- 2 RSS: polars zstd write Dominican Republic 2013 bh: 459 vs 228 MB (2.02x)
- 1 RSS: pyarrow full ours dhs: geometric mean 1.47x
- 2 RSS: pyarrow full ours Senegal 2019 wm: 702 vs 432 MB (1.63x)
- 2 RSS: pyarrow full ours Senegal 2019 bh: 394 vs 289 MB (1.36x)
- 2 RSS: pyarrow full ours Turkey 2013 wm: 677 vs 417 MB (1.62x)
- 2 RSS: pyarrow full ours Turkey 2013 bh: 344 vs 269 MB (1.28x)
- 2 RSS: pyarrow full ours Tajikistan 2017 wm: 830 vs 490 MB (1.70x)
- 2 RSS: pyarrow full ours Tajikistan 2017 bh: 372 vs 285 MB (1.30x)
- 2 RSS: pyarrow full ours Myanmar 2016 wm: 913 vs 566 MB (1.61x)
- 2 RSS: pyarrow full ours Myanmar 2016 bh: 408 vs 290 MB (1.40x)
- 2 RSS: pyarrow full ours Dominican Republic 2013 wm: 574 vs 366 MB (1.57x)
- 2 RSS: pyarrow full ours Dominican Republic 2013 bh: 335 vs 260 MB (1.29x)
- 1 wall: pyarrow window ours dhs: geometric mean 2.09x
- 2 wall: pyarrow window ours Senegal 2019 wm: 85 ms vs 36 ms (2.38x)
- 2 wall: pyarrow window ours Turkey 2013 wm: 81 ms vs 34 ms (2.41x)
- 2 wall: pyarrow window ours Tajikistan 2017 wm: 86 ms vs 36 ms (2.40x)
- 2 wall: pyarrow window ours Myanmar 2016 wm: 84 ms vs 39 ms (2.14x)
- 2 wall: pyarrow window ours Dominican Republic 2013 wm: 66 ms vs 28 ms (2.34x)
- 1 RSS: pyarrow pass ours dhs: geometric mean 1.46x
- 2 wall: pyarrow pass ours Senegal 2019 wm: 289 ms vs 188 ms (1.54x)
- 2 RSS: pyarrow pass ours Senegal 2019 wm: 701 vs 436 MB (1.61x)
- 2 RSS: pyarrow pass ours Senegal 2019 bh: 395 vs 291 MB (1.36x)
- 2 wall: pyarrow pass ours Turkey 2013 wm: 289 ms vs 193 ms (1.50x)
- 2 RSS: pyarrow pass ours Turkey 2013 wm: 677 vs 417 MB (1.62x)
- 2 RSS: pyarrow pass ours Turkey 2013 bh: 344 vs 271 MB (1.27x)
- 2 wall: pyarrow pass ours Tajikistan 2017 wm: 312 ms vs 206 ms (1.52x)
- 2 RSS: pyarrow pass ours Tajikistan 2017 wm: 831 vs 491 MB (1.69x)
- 2 RSS: pyarrow pass ours Tajikistan 2017 bh: 373 vs 287 MB (1.30x)
- 2 wall: pyarrow pass ours Myanmar 2016 wm: 325 ms vs 196 ms (1.66x)
- 2 RSS: pyarrow pass ours Myanmar 2016 wm: 913 vs 572 MB (1.60x)
- 2 RSS: pyarrow pass ours Myanmar 2016 bh: 408 vs 292 MB (1.40x)
- 2 RSS: pyarrow pass ours Dominican Republic 2013 wm: 574 vs 367 MB (1.57x)
- 2 RSS: pyarrow pass ours Dominican Republic 2013 bh: 336 vs 261 MB (1.29x)
- 1 RSS: pyarrow write write dhs: geometric mean 2.25x
- 2 RSS: pyarrow write write Senegal 2019 wm: 1016 vs 393 MB (2.59x)
- 3 CPU: pyarrow write write Senegal 2019 wm: 0.339 s vs 0.217 s, speedup 1.32 allows 0.287 s
- 2 RSS: pyarrow write write Senegal 2019 bh: 540 vs 266 MB (2.03x)
- 2 RSS: pyarrow write write Turkey 2013 wm: 980 vs 380 MB (2.58x)
- 3 CPU: pyarrow write write Turkey 2013 wm: 0.335 s vs 0.229 s, speedup 1.41 allows 0.322 s
- 2 RSS: pyarrow write write Turkey 2013 bh: 470 vs 244 MB (1.92x)
- 2 RSS: pyarrow write write Tajikistan 2017 wm: 1165 vs 452 MB (2.58x)
- 2 RSS: pyarrow write write Tajikistan 2017 bh: 505 vs 264 MB (1.91x)
- 2 RSS: pyarrow write write Myanmar 2016 wm: 1326 vs 481 MB (2.76x)
- 2 RSS: pyarrow write write Myanmar 2016 bh: 550 vs 272 MB (2.02x)
- 2 RSS: pyarrow write write Dominican Republic 2013 wm: 821 vs 330 MB (2.49x)
- 3 CPU: pyarrow write write Dominican Republic 2013 wm: 0.288 s vs 0.203 s, speedup 1.42 allows 0.287 s
- 2 RSS: pyarrow write write Dominican Republic 2013 bh: 453 vs 237 MB (1.91x)
- 1 RSS: pyarrow zstd write dhs: geometric mean 2.28x
- 2 RSS: pyarrow zstd write Senegal 2019 wm: 1022 vs 392 MB (2.61x)
- 2 RSS: pyarrow zstd write Senegal 2019 bh: 548 vs 266 MB (2.06x)
- 2 RSS: pyarrow zstd write Turkey 2013 wm: 988 vs 378 MB (2.61x)
- 2 RSS: pyarrow zstd write Turkey 2013 bh: 476 vs 244 MB (1.95x)
- 2 RSS: pyarrow zstd write Tajikistan 2017 wm: 1173 vs 451 MB (2.60x)
- 2 RSS: pyarrow zstd write Tajikistan 2017 bh: 514 vs 264 MB (1.95x)
- 2 RSS: pyarrow zstd write Myanmar 2016 wm: 1333 vs 481 MB (2.77x)
- 3 CPU: pyarrow zstd write Myanmar 2016 wm: 0.445 s vs 0.301 s, speedup 1.47 allows 0.442 s
- 2 RSS: pyarrow zstd write Myanmar 2016 bh: 560 vs 272 MB (2.06x)
- 2 RSS: pyarrow zstd write Dominican Republic 2013 wm: 828 vs 330 MB (2.51x)
- 3 CPU: pyarrow zstd write Dominican Republic 2013 wm: 0.295 s vs 0.198 s, speedup 1.44 allows 0.286 s
- 2 RSS: pyarrow zstd write Dominican Republic 2013 bh: 459 vs 237 MB (1.94x)

## Every file

Each cell: wall / CPU / peak RSS (median of the runs).

### Senegal 2019 wm

8,649 rows, 4,997 columns; .dta 49.1 MB.

| case | input | datakit | pandas (pyarrow engine) | polars | pyarrow (Table) |
|---|---|---|---|---|---|
| whole file | pyarrow | – | – | – | – |
| whole file | polars | – | – | – | – |
| whole file | ours | 141 ms / 0.17 s / 702 MB | 98 ms / 0.56 s / 748 MB | 18 ms / 0.04 s / 322 MB | 150 ms / 0.35 s / 432 MB |
| five columns | pyarrow | – | – | – | – |
| five columns | polars | – | – | – | – |
| five columns | ours | 6 ms / 0.01 s / 114 MB | 25 ms / 0.03 s / 134 MB | 6 ms / 0.01 s / 97 MB | 133 ms / 0.13 s / 161 MB |
| 1,000 rows | pyarrow | – | – | – | – |
| 1,000 rows | polars | – | – | – | – |
| 1,000 rows | ours | 85 ms / 0.09 s / 211 MB | 63 ms / 0.32 s / 431 MB | 11 ms / 0.02 s / 130 MB | 36 ms / 0.24 s / 382 MB |
| read + pass | pyarrow | – | – | – | – |
| read + pass | polars | – | – | – | – |
| read + pass | ours | 289 ms / 0.31 s / 701 MB | 276 ms / 0.75 s / 744 MB | 51 ms / 0.09 s / 358 MB | 188 ms / 0.40 s / 436 MB |
| write, defaults | write | 165 ms / 0.34 s / 1016 MB | 354 ms / 0.35 s / 773 MB | 35 ms / 0.30 s / 394 MB | 218 ms / 0.22 s / 393 MB |
| write, zstd 3 | write | 170 ms / 0.36 s / 1022 MB | 375 ms / 0.38 s / 773 MB | 38 ms / 0.29 s / 393 MB | 250 ms / 0.25 s / 392 MB |
| .dta read (ours, pandas) | dta | 165 ms / 0.23 s / 640 MB | 305 ms / 0.36 s / 690 MB | – |
| .dta write (ours, pandas) | dta | 284 ms / 0.42 s / 787 MB | 177 ms / 0.27 s / 720 MB | – |

### Senegal 2019 bh

21,562 rows, 1,191 columns; .dta 28.9 MB.

| case | input | datakit | pandas (pyarrow engine) | polars | pyarrow (Table) |
|---|---|---|---|---|---|
| whole file | pyarrow | – | – | – | – |
| whole file | polars | – | – | – | – |
| whole file | ours | 49 ms / 0.07 s / 394 MB | 43 ms / 0.30 s / 450 MB | 19 ms / 0.03 s / 216 MB | 134 ms / 0.22 s / 289 MB |
| five columns | pyarrow | – | – | – | – |
| five columns | polars | – | – | – | – |
| five columns | ours | 3 ms / 0.00 s / 111 MB | 17 ms / 0.02 s / 121 MB | 3 ms / 0.01 s / 86 MB | 109 ms / 0.11 s / 148 MB |
| 1,000 rows | pyarrow | – | – | – | – |
| 1,000 rows | polars | – | – | – | – |
| 1,000 rows | ours | 23 ms / 0.03 s / 130 MB | 18 ms / 0.13 s / 265 MB | 8 ms / 0.01 s / 95 MB | 12 ms / 0.10 s / 246 MB |
| read + pass | pyarrow | – | – | – | – |
| read + pass | polars | – | – | – | – |
| read + pass | ours | 107 ms / 0.12 s / 395 MB | 116 ms / 0.35 s / 451 MB | 28 ms / 0.05 s / 233 MB | 140 ms / 0.24 s / 291 MB |
| write, defaults | write | 76 ms / 0.19 s / 540 MB | 232 ms / 0.23 s / 460 MB | 19 ms / 0.20 s / 255 MB | 154 ms / 0.15 s / 266 MB |
| write, zstd 3 | write | 78 ms / 0.21 s / 548 MB | 247 ms / 0.25 s / 459 MB | 20 ms / 0.19 s / 255 MB | 166 ms / 0.17 s / 266 MB |
| .dta read (ours, pandas) | dta | 60 ms / 0.10 s / 357 MB | 206 ms / 0.23 s / 389 MB | – |
| .dta write (ours, pandas) | dta | 148 ms / 0.24 s / 438 MB | 67 ms / 0.12 s / 411 MB | – |

### Turkey 2013 wm

9,746 rows, 4,668 columns; .dta 52.6 MB.

| case | input | datakit | pandas (pyarrow engine) | polars | pyarrow (Table) |
|---|---|---|---|---|---|
| whole file | pyarrow | – | – | – | – |
| whole file | polars | – | – | – | – |
| whole file | ours | 126 ms / 0.16 s / 677 MB | 94 ms / 0.59 s / 749 MB | 18 ms / 0.04 s / 308 MB | 158 ms / 0.35 s / 417 MB |
| five columns | pyarrow | – | – | – | – |
| five columns | polars | – | – | – | – |
| five columns | ours | 5 ms / 0.01 s / 114 MB | 25 ms / 0.03 s / 133 MB | 5 ms / 0.01 s / 96 MB | 127 ms / 0.13 s / 160 MB |
| 1,000 rows | pyarrow | – | – | – | – |
| 1,000 rows | polars | – | – | – | – |
| 1,000 rows | ours | 81 ms / 0.09 s / 206 MB | 58 ms / 0.30 s / 412 MB | 11 ms / 0.02 s / 128 MB | 34 ms / 0.23 s / 367 MB |
| read + pass | pyarrow | – | – | – | – |
| read + pass | polars | – | – | – | – |
| read + pass | ours | 289 ms / 0.31 s / 677 MB | 277 ms / 0.77 s / 749 MB | 47 ms / 0.09 s / 342 MB | 193 ms / 0.39 s / 417 MB |
| write, defaults | write | 162 ms / 0.33 s / 980 MB | 369 ms / 0.37 s / 777 MB | 38 ms / 0.30 s / 382 MB | 229 ms / 0.23 s / 380 MB |
| write, zstd 3 | write | 164 ms / 0.35 s / 988 MB | 385 ms / 0.38 s / 775 MB | 38 ms / 0.30 s / 382 MB | 246 ms / 0.24 s / 378 MB |
| .dta read (ours, pandas) | dta | 158 ms / 0.22 s / 625 MB | 291 ms / 0.34 s / 664 MB | – |
| .dta write (ours, pandas) | dta | 278 ms / 0.42 s / 766 MB | 169 ms / 0.26 s / 694 MB | – |

### Turkey 2013 bh

17,871 rows, 1,173 columns; .dta 23.3 MB.

| case | input | datakit | pandas (pyarrow engine) | polars | pyarrow (Table) |
|---|---|---|---|---|---|
| whole file | pyarrow | – | – | – | – |
| whole file | polars | – | – | – | – |
| whole file | ours | 42 ms / 0.06 s / 344 MB | 39 ms / 0.27 s / 400 MB | 15 ms / 0.02 s / 196 MB | 119 ms / 0.20 s / 269 MB |
| five columns | pyarrow | – | – | – | – |
| five columns | polars | – | – | – | – |
| five columns | ours | 3 ms / 0.00 s / 110 MB | 16 ms / 0.02 s / 120 MB | 3 ms / 0.01 s / 85 MB | 102 ms / 0.10 s / 148 MB |
| 1,000 rows | pyarrow | – | – | – | – |
| 1,000 rows | polars | – | – | – | – |
| 1,000 rows | ours | 21 ms / 0.02 s / 130 MB | 18 ms / 0.12 s / 242 MB | 7 ms / 0.01 s / 94 MB | 11 ms / 0.10 s / 224 MB |
| read + pass | pyarrow | – | – | – | – |
| read + pass | polars | – | – | – | – |
| read + pass | ours | 88 ms / 0.10 s / 344 MB | 96 ms / 0.32 s / 401 MB | 22 ms / 0.04 s / 212 MB | 127 ms / 0.21 s / 271 MB |
| write, defaults | write | 63 ms / 0.15 s / 470 MB | 176 ms / 0.18 s / 406 MB | 16 ms / 0.16 s / 236 MB | 127 ms / 0.12 s / 244 MB |
| write, zstd 3 | write | 64 ms / 0.16 s / 476 MB | 186 ms / 0.19 s / 407 MB | 17 ms / 0.16 s / 236 MB | 133 ms / 0.13 s / 244 MB |
| .dta read (ours, pandas) | dta | 54 ms / 0.09 s / 322 MB | 187 ms / 0.21 s / 348 MB | – |
| .dta write (ours, pandas) | dta | 122 ms / 0.19 s / 395 MB | 56 ms / 0.09 s / 370 MB | – |

### Tajikistan 2017 wm

10,718 rows, 5,160 columns; .dta 63.8 MB.

| case | input | datakit | pandas (pyarrow engine) | polars | pyarrow (Table) |
|---|---|---|---|---|---|
| whole file | pyarrow | – | – | – | – |
| whole file | polars | – | – | – | – |
| whole file | ours | 137 ms / 0.17 s / 830 MB | 99 ms / 0.73 s / 894 MB | 20 ms / 0.05 s / 377 MB | 147 ms / 0.39 s / 490 MB |
| five columns | pyarrow | – | – | – | – |
| five columns | polars | – | – | – | – |
| five columns | ours | 5 ms / 0.01 s / 115 MB | 24 ms / 0.03 s / 135 MB | 6 ms / 0.01 s / 98 MB | 113 ms / 0.11 s / 162 MB |
| 1,000 rows | pyarrow | – | – | – | – |
| 1,000 rows | polars | – | – | – | – |
| 1,000 rows | ours | 86 ms / 0.09 s / 214 MB | 63 ms / 0.36 s / 485 MB | 11 ms / 0.02 s / 134 MB | 36 ms / 0.28 s / 437 MB |
| read + pass | pyarrow | – | – | – | – |
| read + pass | polars | – | – | – | – |
| read + pass | ours | 312 ms / 0.34 s / 831 MB | 294 ms / 0.92 s / 892 MB | 49 ms / 0.10 s / 414 MB | 206 ms / 0.44 s / 491 MB |
| write, defaults | write | 188 ms / 0.41 s / 1165 MB | 487 ms / 0.49 s / 929 MB | 44 ms / 0.37 s / 455 MB | 281 ms / 0.28 s / 452 MB |
| write, zstd 3 | write | 189 ms / 0.43 s / 1173 MB | 441 ms / 0.44 s / 924 MB | 42 ms / 0.37 s / 453 MB | 297 ms / 0.30 s / 451 MB |
| .dta read (ours, pandas) | dta | 170 ms / 0.25 s / 758 MB | 301 ms / 0.37 s / 820 MB | – |
| .dta write (ours, pandas) | dta | 344 ms / 0.53 s / 932 MB | 195 ms / 0.32 s / 850 MB | – |

### Tajikistan 2017 bh

21,985 rows, 1,146 columns; .dta 29.4 MB.

| case | input | datakit | pandas (pyarrow engine) | polars | pyarrow (Table) |
|---|---|---|---|---|---|
| whole file | pyarrow | – | – | – | – |
| whole file | polars | – | – | – | – |
| whole file | ours | 49 ms / 0.07 s / 372 MB | 40 ms / 0.29 s / 438 MB | 16 ms / 0.03 s / 215 MB | 119 ms / 0.21 s / 285 MB |
| five columns | pyarrow | – | – | – | – |
| five columns | polars | – | – | – | – |
| five columns | ours | 3 ms / 0.00 s / 111 MB | 17 ms / 0.02 s / 121 MB | 3 ms / 0.01 s / 85 MB | 103 ms / 0.10 s / 148 MB |
| 1,000 rows | pyarrow | – | – | – | – |
| 1,000 rows | polars | – | – | – | – |
| 1,000 rows | ours | 20 ms / 0.02 s / 129 MB | 18 ms / 0.13 s / 260 MB | 8 ms / 0.02 s / 96 MB | 11 ms / 0.10 s / 241 MB |
| read + pass | pyarrow | – | – | – | – |
| read + pass | polars | – | – | – | – |
| read + pass | ours | 95 ms / 0.11 s / 373 MB | 100 ms / 0.34 s / 437 MB | 24 ms / 0.05 s / 230 MB | 141 ms / 0.22 s / 287 MB |
| write, defaults | write | 64 ms / 0.18 s / 505 MB | 216 ms / 0.22 s / 445 MB | 19 ms / 0.20 s / 258 MB | 158 ms / 0.16 s / 264 MB |
| write, zstd 3 | write | 65 ms / 0.19 s / 514 MB | 221 ms / 0.22 s / 445 MB | 19 ms / 0.20 s / 258 MB | 177 ms / 0.18 s / 264 MB |
| .dta read (ours, pandas) | dta | 56 ms / 0.09 s / 334 MB | 196 ms / 0.22 s / 365 MB | – |
| .dta write (ours, pandas) | dta | 136 ms / 0.22 s / 409 MB | 61 ms / 0.11 s / 386 MB | – |

### Myanmar 2016 wm

12,885 rows, 4,993 columns; .dta 72.0 MB.

| case | input | datakit | pandas (pyarrow engine) | polars | pyarrow (Table) |
|---|---|---|---|---|---|
| whole file | pyarrow | – | – | – | – |
| whole file | polars | – | – | – | – |
| whole file | ours | 145 ms / 0.19 s / 913 MB | 104 ms / 0.80 s / 1037 MB | 17 ms / 0.05 s / 409 MB | 146 ms / 0.43 s / 566 MB |
| five columns | pyarrow | – | – | – | – |
| five columns | polars | – | – | – | – |
| five columns | ours | 6 ms / 0.01 s / 115 MB | 26 ms / 0.03 s / 135 MB | 6 ms / 0.01 s / 97 MB | 121 ms / 0.12 s / 161 MB |
| 1,000 rows | pyarrow | – | – | – | – |
| 1,000 rows | polars | – | – | – | – |
| 1,000 rows | ours | 84 ms / 0.09 s / 211 MB | 65 ms / 0.39 s / 554 MB | 11 ms / 0.03 s / 133 MB | 39 ms / 0.31 s / 508 MB |
| read + pass | pyarrow | – | – | – | – |
| read + pass | polars | – | – | – | – |
| read + pass | ours | 325 ms / 0.37 s / 913 MB | 307 ms / 1.04 s / 1038 MB | 46 ms / 0.10 s / 445 MB | 196 ms / 0.49 s / 572 MB |
| write, defaults | write | 198 ms / 0.43 s / 1326 MB | 465 ms / 0.46 s / 1071 MB | 44 ms / 0.39 s / 489 MB | 294 ms / 0.29 s / 481 MB |
| write, zstd 3 | write | 205 ms / 0.44 s / 1333 MB | 468 ms / 0.47 s / 1074 MB | 43 ms / 0.40 s / 489 MB | 301 ms / 0.30 s / 481 MB |
| .dta read (ours, pandas) | dta | 178 ms / 0.26 s / 841 MB | 318 ms / 0.39 s / 903 MB | – |
| .dta write (ours, pandas) | dta | 384 ms / 0.59 s / 1026 MB | 195 ms / 0.32 s / 932 MB | – |

### Myanmar 2016 bh

22,989 rows, 1,184 columns; .dta 30.7 MB.

| case | input | datakit | pandas (pyarrow engine) | polars | pyarrow (Table) |
|---|---|---|---|---|---|
| whole file | pyarrow | – | – | – | – |
| whole file | polars | – | – | – | – |
| whole file | ours | 47 ms / 0.06 s / 408 MB | 42 ms / 0.32 s / 460 MB | 18 ms / 0.03 s / 223 MB | 121 ms / 0.21 s / 290 MB |
| five columns | pyarrow | – | – | – | – |
| five columns | polars | – | – | – | – |
| five columns | ours | 3 ms / 0.00 s / 111 MB | 16 ms / 0.02 s / 121 MB | 3 ms / 0.01 s / 85 MB | 104 ms / 0.10 s / 148 MB |
| 1,000 rows | pyarrow | – | – | – | – |
| 1,000 rows | polars | – | – | – | – |
| 1,000 rows | ours | 21 ms / 0.03 s / 130 MB | 19 ms / 0.12 s / 264 MB | 8 ms / 0.01 s / 96 MB | 11 ms / 0.11 s / 247 MB |
| read + pass | pyarrow | – | – | – | – |
| read + pass | polars | – | – | – | – |
| read + pass | ours | 100 ms / 0.12 s / 408 MB | 103 ms / 0.37 s / 461 MB | 26 ms / 0.05 s / 240 MB | 133 ms / 0.23 s / 292 MB |
| write, defaults | write | 70 ms / 0.18 s / 550 MB | 224 ms / 0.22 s / 469 MB | 20 ms / 0.20 s / 265 MB | 176 ms / 0.18 s / 272 MB |
| write, zstd 3 | write | 73 ms / 0.20 s / 560 MB | 248 ms / 0.25 s / 468 MB | 20 ms / 0.20 s / 267 MB | 186 ms / 0.19 s / 272 MB |
| .dta read (ours, pandas) | dta | 63 ms / 0.10 s / 368 MB | 218 ms / 0.25 s / 399 MB | – |
| .dta write (ours, pandas) | dta | 149 ms / 0.24 s / 447 MB | 64 ms / 0.11 s / 421 MB | – |

### Dominican Republic 2013 wm

9,372 rows, 3,854 columns; .dta 39.7 MB.

| case | input | datakit | pandas (pyarrow engine) | polars | pyarrow (Table) |
|---|---|---|---|---|---|
| whole file | pyarrow | – | – | – | – |
| whole file | polars | – | – | – | – |
| whole file | ours | 100 ms / 0.12 s / 574 MB | 77 ms / 0.48 s / 623 MB | 18 ms / 0.03 s / 268 MB | 139 ms / 0.31 s / 366 MB |
| five columns | pyarrow | – | – | – | – |
| five columns | polars | – | – | – | – |
| five columns | ours | 4 ms / 0.00 s / 113 MB | 22 ms / 0.02 s / 129 MB | 5 ms / 0.01 s / 94 MB | 132 ms / 0.13 s / 156 MB |
| 1,000 rows | pyarrow | – | – | – | – |
| 1,000 rows | polars | – | – | – | – |
| 1,000 rows | ours | 66 ms / 0.07 s / 186 MB | 49 ms / 0.26 s / 358 MB | 11 ms / 0.02 s / 120 MB | 28 ms / 0.19 s / 320 MB |
| read + pass | pyarrow | – | – | – | – |
| read + pass | polars | – | – | – | – |
| read + pass | ours | 210 ms / 0.23 s / 574 MB | 199 ms / 0.61 s / 623 MB | 41 ms / 0.08 s / 296 MB | 183 ms / 0.35 s / 367 MB |
| write, defaults | write | 143 ms / 0.29 s / 821 MB | 313 ms / 0.31 s / 645 MB | 31 ms / 0.26 s / 328 MB | 203 ms / 0.20 s / 330 MB |
| write, zstd 3 | write | 137 ms / 0.29 s / 828 MB | 312 ms / 0.31 s / 646 MB | 30 ms / 0.25 s / 328 MB | 198 ms / 0.20 s / 330 MB |
| .dta read (ours, pandas) | dta | 114 ms / 0.16 s / 524 MB | 246 ms / 0.29 s / 560 MB | – |
| .dta write (ours, pandas) | dta | 228 ms / 0.34 s / 642 MB | 134 ms / 0.20 s / 588 MB | – |

### Dominican Republic 2013 bh

18,167 rows, 1,078 columns; .dta 22.2 MB.

| case | input | datakit | pandas (pyarrow engine) | polars | pyarrow (Table) |
|---|---|---|---|---|---|
| whole file | pyarrow | – | – | – | – |
| whole file | polars | – | – | – | – |
| whole file | ours | 40 ms / 0.05 s / 335 MB | 37 ms / 0.25 s / 381 MB | 17 ms / 0.02 s / 189 MB | 112 ms / 0.19 s / 260 MB |
| five columns | pyarrow | – | – | – | – |
| five columns | polars | – | – | – | – |
| five columns | ours | 3 ms / 0.00 s / 110 MB | 16 ms / 0.02 s / 120 MB | 3 ms / 0.01 s / 85 MB | 106 ms / 0.11 s / 148 MB |
| 1,000 rows | pyarrow | – | – | – | – |
| 1,000 rows | polars | – | – | – | – |
| 1,000 rows | ours | 19 ms / 0.02 s / 128 MB | 17 ms / 0.11 s / 234 MB | 8 ms / 0.01 s / 94 MB | 10 ms / 0.09 s / 216 MB |
| read + pass | pyarrow | – | – | – | – |
| read + pass | polars | – | – | – | – |
| read + pass | ours | 86 ms / 0.10 s / 336 MB | 92 ms / 0.29 s / 381 MB | 24 ms / 0.04 s / 204 MB | 126 ms / 0.21 s / 261 MB |
| write, defaults | write | 65 ms / 0.15 s / 453 MB | 171 ms / 0.17 s / 387 MB | 16 ms / 0.16 s / 227 MB | 122 ms / 0.12 s / 237 MB |
| write, zstd 3 | write | 64 ms / 0.16 s / 459 MB | 182 ms / 0.18 s / 387 MB | 16 ms / 0.16 s / 228 MB | 132 ms / 0.13 s / 237 MB |
| .dta read (ours, pandas) | dta | 50 ms / 0.08 s / 307 MB | 185 ms / 0.21 s / 330 MB | – |
| .dta write (ours, pandas) | dta | 118 ms / 0.19 s / 377 MB | 57 ms / 0.09 s / 351 MB | – |

