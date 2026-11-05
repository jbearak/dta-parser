# Parquet benchmarks (TypeScript, Node)

Written by `bench/parquet/run_node.py`; see bench/RESULTS.md for what the numbers mean.

One-minute load average before each run: median 10.7, range 10.1 to 13.2, over 2,345 runs.

| library | version | threads | Node |
|---|---|---|---|
| hyparquet | 1.32.0 | 1 | v26.12.1 |
| hyparquet-writer | 0.18.0 | 1 | v26.12.1 |
| ours | 1.1.0 | 1 | v26.12.1 |
| parquet-wasm | 0.9.0 | 1 | v26.12.1 |

## Ratios, ours to theirs (geometric means)

Below 1 is better for us. Target 1 holds where wall and RSS are at most 1.05 on NSFG and DHS.

| against | case | input | family | files | wall | CPU | peak RSS |
|---|---|---|---|---|---|---|---|
| hyparquet (writes: hyparquet-writer) | whole file | pyarrow | NSFG | 9 | 0.25 | 0.37 | 0.72 |
| hyparquet (writes: hyparquet-writer) | whole file | pyarrow | Synthetic | 2 | 0.18 | 0.12 | 0.28 |
| hyparquet (writes: hyparquet-writer) | whole file | polars | NSFG | 9 | 0.27 | 0.36 | 0.73 |
| hyparquet (writes: hyparquet-writer) | whole file | polars | Synthetic | 2 | 0.30 | 0.20 | 0.26 |
| hyparquet (writes: hyparquet-writer) | whole file | ours | NSFG | 9 | 0.27 | 0.43 | 0.74 |
| hyparquet (writes: hyparquet-writer) | whole file | ours | Synthetic | 1 | 0.22 | 0.21 | 0.23 |
| hyparquet (writes: hyparquet-writer) | five columns | pyarrow | NSFG | 9 | 0.71 | 0.82 | 1.11 |
| hyparquet (writes: hyparquet-writer) | five columns | pyarrow | Synthetic | 3 | 0.23 | 0.21 | 0.35 |
| hyparquet (writes: hyparquet-writer) | five columns | polars | NSFG | 9 | 0.67 | 0.78 | 1.17 |
| hyparquet (writes: hyparquet-writer) | five columns | polars | Synthetic | 3 | 0.38 | 0.31 | 0.38 |
| hyparquet (writes: hyparquet-writer) | five columns | ours | NSFG | 9 | 1.11 | 1.41 | 1.18 |
| hyparquet (writes: hyparquet-writer) | five columns | ours | Synthetic | 3 | 0.22 | 0.19 | 0.34 |
| hyparquet (writes: hyparquet-writer) | 1,000 rows | pyarrow | NSFG | 9 | 0.22 | 0.37 | 0.54 |
| hyparquet (writes: hyparquet-writer) | 1,000 rows | pyarrow | Synthetic | 3 | 0.48 | 0.27 | 0.30 |
| hyparquet (writes: hyparquet-writer) | 1,000 rows | polars | NSFG | 9 | 0.24 | 0.37 | 0.54 |
| hyparquet (writes: hyparquet-writer) | 1,000 rows | polars | Synthetic | 3 | 0.44 | 0.47 | 0.35 |
| hyparquet (writes: hyparquet-writer) | 1,000 rows | ours | NSFG | 9 | 0.24 | 0.42 | 0.54 |
| hyparquet (writes: hyparquet-writer) | 1,000 rows | ours | Synthetic | 3 | 0.16 | 0.22 | 0.25 |
| hyparquet (writes: hyparquet-writer) | read + pass | pyarrow | NSFG | 9 | 0.32 | 0.40 | 0.74 |
| hyparquet (writes: hyparquet-writer) | read + pass | pyarrow | Synthetic | 2 | 0.20 | 0.13 | 0.29 |
| hyparquet (writes: hyparquet-writer) | read + pass | polars | NSFG | 9 | 0.32 | 0.41 | 0.76 |
| hyparquet (writes: hyparquet-writer) | read + pass | polars | Synthetic | 2 | 0.31 | 0.21 | 0.27 |
| hyparquet (writes: hyparquet-writer) | read + pass | ours | NSFG | 9 | 0.34 | 0.46 | 0.75 |
| hyparquet (writes: hyparquet-writer) | read + pass | ours | Synthetic | 1 | 0.31 | 0.28 | 0.26 |
| hyparquet (writes: hyparquet-writer) | write, defaults | dta | NSFG | 9 | 0.38 | 0.34 | 0.61 |
| hyparquet (writes: hyparquet-writer) | write, defaults | dta | Synthetic | 2 | 0.41 | 0.35 | 0.95 |
| parquet-wasm | whole file | pyarrow | NSFG | 9 | 0.38 | 0.37 | 0.69 |
| parquet-wasm | whole file | pyarrow | Synthetic | 2 | 0.19 | 0.20 | 0.25 |
| parquet-wasm | whole file | polars | NSFG | 9 | 0.39 | 0.38 | 0.72 |
| parquet-wasm | whole file | polars | Synthetic | 2 | 0.30 | 0.32 | 0.24 |
| parquet-wasm | whole file | ours | NSFG | 9 | 0.43 | 0.43 | 0.70 |
| parquet-wasm | whole file | ours | Synthetic | 2 | 0.21 | 0.24 | 0.25 |
| parquet-wasm | five columns | pyarrow | NSFG | 9 | 0.12 | 0.13 | 0.31 |
| parquet-wasm | five columns | pyarrow | Synthetic | 2 | 0.16 | 0.17 | 0.20 |
| parquet-wasm | five columns | polars | NSFG | 9 | 0.10 | 0.12 | 0.33 |
| parquet-wasm | five columns | polars | Synthetic | 2 | 0.21 | 0.23 | 0.19 |
| parquet-wasm | five columns | ours | NSFG | 9 | 0.18 | 0.21 | 0.32 |
| parquet-wasm | five columns | ours | Synthetic | 2 | 0.19 | 0.21 | 0.20 |
| parquet-wasm | 1,000 rows | pyarrow | NSFG | 9 | 0.61 | 0.63 | 0.73 |
| parquet-wasm | 1,000 rows | pyarrow | Synthetic | 2 | 0.30 | 0.33 | 0.23 |
| parquet-wasm | 1,000 rows | polars | NSFG | 9 | 0.59 | 0.60 | 0.61 |
| parquet-wasm | 1,000 rows | polars | Synthetic | 2 | 0.42 | 0.50 | 0.19 |
| parquet-wasm | 1,000 rows | ours | NSFG | 9 | 0.71 | 0.75 | 0.73 |
| parquet-wasm | 1,000 rows | ours | Synthetic | 2 | 0.27 | 0.46 | 0.19 |
| parquet-wasm | read + pass | pyarrow | NSFG | 9 | 0.48 | 0.42 | 0.67 |
| parquet-wasm | read + pass | pyarrow | Synthetic | 2 | 0.12 | 0.13 | 0.17 |
| parquet-wasm | read + pass | polars | NSFG | 9 | 0.47 | 0.43 | 0.69 |
| parquet-wasm | read + pass | polars | Synthetic | 2 | 0.17 | 0.18 | 0.17 |
| parquet-wasm | read + pass | ours | NSFG | 9 | 0.53 | 0.48 | 0.67 |
| parquet-wasm | read + pass | ours | Synthetic | 2 | 0.12 | 0.13 | 0.17 |
| parquet-wasm | write, defaults | dta | NSFG | 9 | 0.78 | 0.69 | 0.50 |
| parquet-wasm | write, defaults | dta | Synthetic | 2 | 1.05 | 0.98 | 0.20 |
| parquet-wasm | write, zstd 3 | dta | NSFG | 9 | 0.80 | 0.77 | 0.47 |
| parquet-wasm | write, zstd 3 | dta | Synthetic | 2 | 1.71 | 1.60 | 0.20 |

## Misses

- 1 RSS: hyparquet five pyarrow nsfg: geometric mean 1.11x
- 1 RSS: hyparquet five polars nsfg: geometric mean 1.17x
- 1 wall: hyparquet five ours nsfg: geometric mean 1.11x
- 1 RSS: hyparquet five ours nsfg: geometric mean 1.18x
- 2 RSS: hyparquet five ours 1973_FemResp: 83 vs 64 MB (1.29x)
- 3 CPU: hyparquet five ours 1973_FemResp: 0.046 s vs 0.025 s, speedup 0.89 allows 0.028 s
- 3 CPU: hyparquet five ours 1976_FemResp: 0.048 s vs 0.026 s, speedup 0.80 allows 0.030 s
- 2 RSS: hyparquet five ours 1982_FemResp: 84 vs 67 MB (1.26x)
- 3 CPU: hyparquet five ours 1982_FemResp: 0.050 s vs 0.024 s, speedup 0.82 allows 0.027 s
- 3 CPU: hyparquet five ours 1982_Preg: 0.028 s vs 0.023 s, speedup 1.19 allows 0.027 s
- 3 CPU: hyparquet five ours 1988_FemResp: 0.059 s vs 0.037 s, speedup 0.80 allows 0.042 s
- 2 RSS: hyparquet five ours 1988_Preg: 85 vs 66 MB (1.27x)
- 3 CPU: hyparquet five ours 1988_Preg: 0.047 s vs 0.021 s, speedup 0.85 allows 0.025 s
- 3 CPU: hyparquet five ours 1995_FemResp: 0.094 s vs 0.056 s, speedup 0.65 allows 0.064 s
- 2 RSS: hyparquet write dta groups.dta: 1515 vs 785 MB (1.93x)
- 2 wall: parquet-wasm write dta 1995_FemResp: 573 ms vs 453 ms (1.27x)
- 2 wall: parquet-wasm zstd dta long.dta: 10.43 s vs 4.03 s (2.59x)
- 3 CPU: parquet-wasm zstd dta long.dta: 10.786 s vs 4.704 s, speedup 0.39 allows 5.409 s

## Cases another library could not run

- hyparquet full ours long.dta: exit -6: 31: 0x104140774 node::NodeMainInstance::Run() [/opt/homebrew/Cellar/node/26.12.1_1/lib/libnode.147.dylib] | 32: 0x1040ab06c node::Start(int, char**) [/
- hyparquet full ours wide.dta: exit 1:     at file:///Users/jmb/.t3/worktrees/dta-parser.new/t3-7730bc90/bench/parquet/case.mjs:250:71 { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12
- hyparquet full polars wide.dta: exit 1:     at file:///Users/jmb/.t3/worktrees/dta-parser.new/t3-7730bc90/bench/parquet/case.mjs:250:71 { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12
- hyparquet full pyarrow wide.dta: exit 1:     at file:///Users/jmb/.t3/worktrees/dta-parser.new/t3-7730bc90/bench/parquet/case.mjs:250:71 { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12
- hyparquet pass ours long.dta: exit -6: 31: 0x105db0774 node::NodeMainInstance::Run() [/opt/homebrew/Cellar/node/26.12.1_1/lib/libnode.147.dylib] | 32: 0x105d1b06c node::Start(int, char**) [/
- hyparquet pass ours wide.dta: exit 1:     at file:///Users/jmb/.t3/worktrees/dta-parser.new/t3-7730bc90/bench/parquet/case.mjs:250:71 { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12
- hyparquet pass polars wide.dta: exit 1:     at file:///Users/jmb/.t3/worktrees/dta-parser.new/t3-7730bc90/bench/parquet/case.mjs:250:71 { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12
- hyparquet pass pyarrow wide.dta: exit 1:     at file:///Users/jmb/.t3/worktrees/dta-parser.new/t3-7730bc90/bench/parquet/case.mjs:250:71 { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12
- hyparquet write dta wide.dta: exit -6: 30: 0x1065a0774 node::NodeMainInstance::Run() [/opt/homebrew/Cellar/node/26.12.1_1/lib/libnode.147.dylib] | 31: 0x10650b06c node::Start(int, char**) [/
- parquet-wasm five ours wide.dta: exit 1:     at async asyncRunEntryPointWithESMLoader (node:internal/modules/run_main:105:5) { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12.1
- parquet-wasm five polars wide.dta: exit 1:     at async asyncRunEntryPointWithESMLoader (node:internal/modules/run_main:105:5) { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12.1
- parquet-wasm five pyarrow wide.dta: exit 1:     at async asyncRunEntryPointWithESMLoader (node:internal/modules/run_main:105:5) { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12.1
- parquet-wasm full ours wide.dta: exit 1:     at async asyncRunEntryPointWithESMLoader (node:internal/modules/run_main:105:5) { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12.1
- parquet-wasm full polars wide.dta: exit 1:     at async asyncRunEntryPointWithESMLoader (node:internal/modules/run_main:105:5) { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12.1
- parquet-wasm full pyarrow wide.dta: exit 1:     at async asyncRunEntryPointWithESMLoader (node:internal/modules/run_main:105:5) { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12.1
- parquet-wasm pass ours wide.dta: exit 1:     at async asyncRunEntryPointWithESMLoader (node:internal/modules/run_main:105:5) { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12.1
- parquet-wasm pass polars wide.dta: exit 1:     at async asyncRunEntryPointWithESMLoader (node:internal/modules/run_main:105:5) { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12.1
- parquet-wasm pass pyarrow wide.dta: exit 1:     at async asyncRunEntryPointWithESMLoader (node:internal/modules/run_main:105:5) { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12.1
- parquet-wasm window ours wide.dta: exit 1:     at async asyncRunEntryPointWithESMLoader (node:internal/modules/run_main:105:5) { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12.1
- parquet-wasm window polars wide.dta: exit 1:     at async asyncRunEntryPointWithESMLoader (node:internal/modules/run_main:105:5) { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12.1
- parquet-wasm window pyarrow wide.dta: exit 1:     at async asyncRunEntryPointWithESMLoader (node:internal/modules/run_main:105:5) { |   code: 'ERR_FS_FILE_TOO_LARGE' | } | Node.js v26.12.1
- parquet-wasm write dta wide.dta: exit 1:     at ModuleJob.run (node:internal/modules/esm/module_job:569:25) |     at async node:internal/modules/esm/loader:650:26 |     at async asyncRunEntryPo
- parquet-wasm zstd dta wide.dta: exit 1:     at ModuleJob.run (node:internal/modules/esm/module_job:569:25) |     at async node:internal/modules/esm/loader:650:26 |     at async asyncRunEntryPo

## Every file

### long.dta

10,000,000 rows, 12 columns; Parquet pyarrow 650.9 MB, polars 597.3 MB, ours 632.9 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 930 ms / 1.09 s / 1697 MB | 6.75 s / 18.45 s / 5637 MB | 4.38 s / 4.70 s / 5169 MB |
| whole file | polars | 3.51 s / 3.65 s / 1680 MB | 11.12 s / 24.66 s / 6377 MB | 5.74 s / 6.03 s / 5291 MB |
| whole file | ours | 888 ms / 1.05 s / 1689 MB | failed | 3.16 s / 3.41 s / 5145 MB |
| five columns | pyarrow | 722 ms / 0.86 s / 1103 MB | 2.96 s / 5.94 s / 2884 MB | 4.46 s / 4.75 s / 5168 MB |
| five columns | polars | 1.82 s / 1.97 s / 1049 MB | 4.31 s / 7.63 s / 2791 MB | 5.71 s / 5.98 s / 5292 MB |
| five columns | ours | 723 ms / 0.84 s / 1051 MB | 2.90 s / 6.49 s / 3206 MB | 3.15 s / 3.41 s / 5145 MB |
| 1,000 rows | pyarrow | 23 ms / 0.05 s / 153 MB | 48 ms / 0.12 s / 234 MB | 104 ms / 0.15 s / 1414 MB |
| 1,000 rows | polars | 42 ms / 0.07 s / 91 MB | 121 ms / 0.23 s / 181 MB | 105 ms / 0.16 s / 1304 MB |
| 1,000 rows | ours | 11 ms / 0.03 s / 92 MB | 76 ms / 0.13 s / 210 MB | 89 ms / 0.12 s / 1372 MB |
| read + pass | pyarrow | 1.18 s / 1.38 s / 1734 MB | 9.02 s / 22.61 s / 5737 MB | 7.64 s / 8.32 s / 7153 MB |
| read + pass | polars | 3.75 s / 3.91 s / 1694 MB | 13.37 s / 29.52 s / 6443 MB | 9.97 s / 10.74 s / 7257 MB |
| read + pass | ours | 1.14 s / 1.32 s / 1700 MB | failed | 6.42 s / 7.08 s / 7131 MB |
| write, defaults | dta | 2.93 s / 3.24 s / 2259 MB | 9.03 s / 13.51 s / 4876 MB | 2.46 s / 3.11 s / 11932 MB |
| write, zstd 3 | dta | 10.43 s / 10.79 s / 2260 MB | – | 4.03 s / 4.70 s / 11109 MB |

### wide.dta

1,500,000 rows, 400 columns; Parquet pyarrow 5020.6 MB, polars 4607.6 MB, ours 4800.8 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 1.52 s / 1.65 s / 5577 MB | failed | failed |
| whole file | polars | 23.11 s / 23.23 s / 5563 MB | failed | failed |
| whole file | ours | 1.28 s / 1.39 s / 5565 MB | failed | failed |
| five columns | pyarrow | 33 ms / 0.07 s / 215 MB | 174 ms / 0.26 s / 508 MB | failed |
| five columns | polars | 304 ms / 0.35 s / 213 MB | 612 ms / 0.75 s / 493 MB | failed |
| five columns | ours | 29 ms / 0.06 s / 211 MB | 165 ms / 0.25 s / 555 MB | failed |
| 1,000 rows | pyarrow | 204 ms / 0.27 s / 301 MB | 702 ms / 2.50 s / 7242 MB | failed |
| 1,000 rows | polars | 1.26 s / 1.31 s / 104 MB | 2.55 s / 2.83 s / 1126 MB | failed |
| 1,000 rows | ours | 46 ms / 0.09 s / 102 MB | 674 ms / 1.12 s / 2439 MB | failed |
| read + pass | pyarrow | 2.60 s / 2.72 s / 5582 MB | failed | failed |
| read + pass | polars | 24.28 s / 24.42 s / 5567 MB | failed | failed |
| read + pass | ours | 2.35 s / 2.47 s / 5568 MB | failed | failed |
| write, defaults | dta | 7.99 s / 7.98 s / 5573 MB | failed | failed |
| write, zstd 3 | dta | 69.25 s / 69.13 s / 5572 MB | – | failed |

### groups.dta

15,000,000 rows, 2 columns; Parquet pyarrow 24.1 MB, polars 23.4 MB, ours 24.0 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 218 ms / 0.27 s / 383 MB | 919 ms / 1.18 s / 1435 MB | 1.35 s / 1.52 s / 2087 MB |
| whole file | polars | 248 ms / 0.33 s / 396 MB | 892 ms / 1.18 s / 1572 MB | 1.71 s / 1.92 s / 2146 MB |
| whole file | ours | 212 ms / 0.28 s / 394 MB | 959 ms / 1.34 s / 1685 MB | 1.33 s / 1.53 s / 2108 MB |
| five columns | pyarrow | 219 ms / 0.27 s / 382 MB | 861 ms / 1.14 s / 1402 MB | 1.42 s / 1.60 s / 2089 MB |
| five columns | polars | 243 ms / 0.32 s / 395 MB | 954 ms / 1.31 s / 1179 MB | 1.73 s / 1.95 s / 2147 MB |
| five columns | ours | 212 ms / 0.28 s / 397 MB | 902 ms / 1.23 s / 1238 MB | 1.34 s / 1.55 s / 2108 MB |
| 1,000 rows | pyarrow | 7 ms / 0.01 s / 65 MB | 8 ms / 0.02 s / 66 MB | 16 ms / 0.02 s / 129 MB |
| 1,000 rows | polars | 8 ms / 0.02 s / 72 MB | 16 ms / 0.03 s / 75 MB | 18 ms / 0.03 s / 139 MB |
| 1,000 rows | ours | 9 ms / 0.02 s / 75 MB | 22 ms / 0.04 s / 87 MB | 16 ms / 0.03 s / 136 MB |
| read + pass | pyarrow | 303 ms / 0.36 s / 397 MB | 973 ms / 1.26 s / 1436 MB | 3.44 s / 3.75 s / 3286 MB |
| read + pass | polars | 332 ms / 0.41 s / 411 MB | 967 ms / 1.25 s / 1520 MB | 4.31 s / 4.67 s / 3315 MB |
| read + pass | ours | 298 ms / 0.36 s / 409 MB | 968 ms / 1.29 s / 1563 MB | 3.45 s / 3.81 s / 3303 MB |
| write, defaults | dta | 1.07 s / 1.14 s / 1515 MB | 2.11 s / 2.19 s / 785 MB | 1.15 s / 1.23 s / 7353 MB |
| write, zstd 3 | dta | 1.36 s / 1.44 s / 1519 MB | – | 1.20 s / 1.29 s / 7355 MB |

### 1973_FemResp

9,797 rows, 450 columns; Parquet pyarrow 1.6 MB, polars 1.3 MB, ours 1.7 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 29 ms / 0.08 s / 165 MB | 120 ms / 0.19 s / 191 MB | 62 ms / 0.18 s / 220 MB |
| whole file | polars | 38 ms / 0.10 s / 163 MB | 152 ms / 0.25 s / 193 MB | 68 ms / 0.20 s / 214 MB |
| whole file | ours | 33 ms / 0.10 s / 167 MB | 126 ms / 0.19 s / 188 MB | 57 ms / 0.18 s / 208 MB |
| five columns | pyarrow | 8 ms / 0.03 s / 77 MB | 11 ms / 0.02 s / 65 MB | 61 ms / 0.18 s / 218 MB |
| five columns | polars | 9 ms / 0.03 s / 78 MB | 12 ms / 0.03 s / 63 MB | 68 ms / 0.19 s / 214 MB |
| five columns | ours | 11 ms / 0.05 s / 83 MB | 10 ms / 0.02 s / 64 MB | 55 ms / 0.18 s / 207 MB |
| 1,000 rows | pyarrow | 20 ms / 0.07 s / 95 MB | 89 ms / 0.14 s / 170 MB | 26 ms / 0.10 s / 130 MB |
| 1,000 rows | polars | 27 ms / 0.09 s / 96 MB | 120 ms / 0.19 s / 167 MB | 35 ms / 0.12 s / 154 MB |
| 1,000 rows | ours | 23 ms / 0.09 s / 98 MB | 105 ms / 0.15 s / 166 MB | 26 ms / 0.09 s / 129 MB |
| read + pass | pyarrow | 46 ms / 0.12 s / 163 MB | 133 ms / 0.21 s / 191 MB | 72 ms / 0.20 s / 233 MB |
| read + pass | polars | 54 ms / 0.13 s / 168 MB | 164 ms / 0.26 s / 188 MB | 81 ms / 0.22 s / 232 MB |
| read + pass | ours | 49 ms / 0.13 s / 170 MB | 138 ms / 0.21 s / 189 MB | 70 ms / 0.20 s / 224 MB |
| write, defaults | dta | 70 ms / 0.10 s / 160 MB | 199 ms / 0.32 s / 262 MB | 85 ms / 0.15 s / 319 MB |
| write, zstd 3 | dta | 100 ms / 0.14 s / 155 MB | – | 105 ms / 0.18 s / 345 MB |

### 1976_FemResp

8,611 rows, 468 columns; Parquet pyarrow 1.8 MB, polars 1.4 MB, ours 2.2 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 27 ms / 0.08 s / 159 MB | 110 ms / 0.16 s / 210 MB | 55 ms / 0.18 s / 206 MB |
| whole file | polars | 37 ms / 0.10 s / 163 MB | 141 ms / 0.22 s / 210 MB | 68 ms / 0.19 s / 203 MB |
| whole file | ours | 33 ms / 0.10 s / 165 MB | 120 ms / 0.17 s / 202 MB | 56 ms / 0.18 s / 224 MB |
| five columns | pyarrow | 8 ms / 0.02 s / 77 MB | 11 ms / 0.03 s / 64 MB | 53 ms / 0.18 s / 205 MB |
| five columns | polars | 8 ms / 0.03 s / 79 MB | 13 ms / 0.03 s / 63 MB | 67 ms / 0.19 s / 202 MB |
| five columns | ours | 14 ms / 0.05 s / 82 MB | 11 ms / 0.03 s / 65 MB | 54 ms / 0.17 s / 221 MB |
| 1,000 rows | pyarrow | 19 ms / 0.07 s / 95 MB | 81 ms / 0.12 s / 166 MB | 27 ms / 0.10 s / 135 MB |
| 1,000 rows | polars | 28 ms / 0.09 s / 94 MB | 116 ms / 0.18 s / 168 MB | 36 ms / 0.13 s / 154 MB |
| 1,000 rows | ours | 24 ms / 0.09 s / 97 MB | 86 ms / 0.13 s / 165 MB | 26 ms / 0.10 s / 143 MB |
| read + pass | pyarrow | 42 ms / 0.11 s / 163 MB | 126 ms / 0.19 s / 192 MB | 65 ms / 0.20 s / 218 MB |
| read + pass | polars | 52 ms / 0.12 s / 167 MB | 154 ms / 0.24 s / 190 MB | 76 ms / 0.21 s / 216 MB |
| read + pass | ours | 47 ms / 0.13 s / 168 MB | 130 ms / 0.18 s / 202 MB | 63 ms / 0.19 s / 241 MB |
| write, defaults | dta | 66 ms / 0.10 s / 160 MB | 180 ms / 0.28 s / 267 MB | 86 ms / 0.15 s / 323 MB |
| write, zstd 3 | dta | 99 ms / 0.15 s / 160 MB | – | 107 ms / 0.18 s / 343 MB |

### 1976_PSU

8,611 rows, 3 columns; Parquet pyarrow 0.1 MB, polars 0.0 MB, ours 0.0 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 6 ms / 0.01 s / 61 MB | 4 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 79 MB |
| whole file | polars | 6 ms / 0.01 s / 63 MB | 6 ms / 0.01 s / 57 MB | 12 ms / 0.01 s / 79 MB |
| whole file | ours | 6 ms / 0.01 s / 61 MB | 4 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 79 MB |
| five columns | pyarrow | 6 ms / 0.01 s / 61 MB | 6 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 79 MB |
| five columns | polars | 6 ms / 0.01 s / 63 MB | 7 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 79 MB |
| five columns | ours | 6 ms / 0.01 s / 61 MB | 6 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 79 MB |
| 1,000 rows | pyarrow | 6 ms / 0.01 s / 61 MB | 5 ms / 0.01 s / 58 MB | 11 ms / 0.01 s / 79 MB |
| 1,000 rows | polars | 6 ms / 0.01 s / 63 MB | 7 ms / 0.01 s / 57 MB | 12 ms / 0.01 s / 79 MB |
| 1,000 rows | ours | 6 ms / 0.01 s / 61 MB | 5 ms / 0.01 s / 57 MB | 11 ms / 0.01 s / 79 MB |
| read + pass | pyarrow | 6 ms / 0.01 s / 63 MB | 5 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 80 MB |
| read + pass | polars | 7 ms / 0.01 s / 65 MB | 6 ms / 0.01 s / 57 MB | 12 ms / 0.01 s / 79 MB |
| read + pass | ours | 7 ms / 0.01 s / 63 MB | 5 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 79 MB |
| write, defaults | dta | 4 ms / 0.01 s / 65 MB | 7 ms / 0.02 s / 73 MB | 11 ms / 0.01 s / 93 MB |
| write, zstd 3 | dta | 7 ms / 0.01 s / 68 MB | – | 14 ms / 0.02 s / 93 MB |

### 1976_Preg

23,042 rows, 80 columns; Parquet pyarrow 0.4 MB, polars 0.3 MB, ours 0.4 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 15 ms / 0.04 s / 104 MB | 54 ms / 0.09 s / 147 MB | 31 ms / 0.12 s / 171 MB |
| whole file | polars | 18 ms / 0.05 s / 106 MB | 65 ms / 0.12 s / 150 MB | 34 ms / 0.13 s / 164 MB |
| whole file | ours | 16 ms / 0.04 s / 109 MB | 55 ms / 0.09 s / 147 MB | 31 ms / 0.12 s / 168 MB |
| five columns | pyarrow | 7 ms / 0.01 s / 74 MB | 11 ms / 0.03 s / 67 MB | 31 ms / 0.11 s / 171 MB |
| five columns | polars | 8 ms / 0.02 s / 78 MB | 14 ms / 0.03 s / 68 MB | 34 ms / 0.13 s / 163 MB |
| five columns | ours | 8 ms / 0.02 s / 74 MB | 11 ms / 0.03 s / 67 MB | 31 ms / 0.12 s / 169 MB |
| 1,000 rows | pyarrow | 9 ms / 0.03 s / 75 MB | 34 ms / 0.07 s / 100 MB | 15 ms / 0.04 s / 115 MB |
| 1,000 rows | polars | 13 ms / 0.04 s / 77 MB | 53 ms / 0.10 s / 116 MB | 18 ms / 0.05 s / 109 MB |
| 1,000 rows | ours | 10 ms / 0.03 s / 75 MB | 45 ms / 0.08 s / 116 MB | 15 ms / 0.04 s / 114 MB |
| read + pass | pyarrow | 22 ms / 0.05 s / 112 MB | 60 ms / 0.10 s / 147 MB | 36 ms / 0.13 s / 172 MB |
| read + pass | polars | 25 ms / 0.06 s / 108 MB | 74 ms / 0.14 s / 147 MB | 39 ms / 0.14 s / 164 MB |
| read + pass | ours | 23 ms / 0.05 s / 107 MB | 64 ms / 0.11 s / 149 MB | 35 ms / 0.13 s / 171 MB |
| write, defaults | dta | 26 ms / 0.03 s / 94 MB | 77 ms / 0.13 s / 178 MB | 35 ms / 0.05 s / 178 MB |
| write, zstd 3 | dta | 36 ms / 0.06 s / 98 MB | – | 42 ms / 0.06 s / 195 MB |

### 1982_FemResp

7,969 rows, 741 columns; Parquet pyarrow 1.8 MB, polars 1.5 MB, ours 2.1 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 35 ms / 0.10 s / 188 MB | 175 ms / 0.26 s / 258 MB | 76 ms / 0.21 s / 258 MB |
| whole file | polars | 43 ms / 0.11 s / 189 MB | 197 ms / 0.29 s / 250 MB | 98 ms / 0.23 s / 245 MB |
| whole file | ours | 39 ms / 0.11 s / 190 MB | 182 ms / 0.27 s / 258 MB | 77 ms / 0.22 s / 265 MB |
| five columns | pyarrow | 8 ms / 0.03 s / 78 MB | 12 ms / 0.03 s / 67 MB | 74 ms / 0.20 s / 257 MB |
| five columns | polars | 9 ms / 0.03 s / 80 MB | 13 ms / 0.03 s / 66 MB | 97 ms / 0.23 s / 243 MB |
| five columns | ours | 14 ms / 0.05 s / 84 MB | 11 ms / 0.02 s / 67 MB | 74 ms / 0.20 s / 262 MB |
| 1,000 rows | pyarrow | 23 ms / 0.08 s / 102 MB | 132 ms / 0.22 s / 214 MB | 34 ms / 0.13 s / 147 MB |
| 1,000 rows | polars | 32 ms / 0.10 s / 102 MB | 151 ms / 0.24 s / 200 MB | 48 ms / 0.15 s / 168 MB |
| 1,000 rows | ours | 25 ms / 0.10 s / 106 MB | 138 ms / 0.23 s / 203 MB | 34 ms / 0.13 s / 146 MB |
| read + pass | pyarrow | 49 ms / 0.12 s / 200 MB | 197 ms / 0.29 s / 268 MB | 87 ms / 0.22 s / 283 MB |
| read + pass | polars | 58 ms / 0.13 s / 199 MB | 219 ms / 0.32 s / 263 MB | 110 ms / 0.26 s / 272 MB |
| read + pass | ours | 54 ms / 0.14 s / 204 MB | 203 ms / 0.30 s / 267 MB | 88 ms / 0.22 s / 292 MB |
| write, defaults | dta | 90 ms / 0.14 s / 188 MB | 241 ms / 0.37 s / 308 MB | 121 ms / 0.21 s / 393 MB |
| write, zstd 3 | dta | 126 ms / 0.19 s / 190 MB | – | 159 ms / 0.26 s / 430 MB |

### 1982_Preg

13,768 rows, 174 columns; Parquet pyarrow 0.4 MB, polars 0.4 MB, ours 0.5 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 16 ms / 0.05 s / 114 MB | 70 ms / 0.11 s / 161 MB | 36 ms / 0.13 s / 188 MB |
| whole file | polars | 20 ms / 0.06 s / 115 MB | 77 ms / 0.13 s / 162 MB | 40 ms / 0.14 s / 186 MB |
| whole file | ours | 18 ms / 0.05 s / 114 MB | 71 ms / 0.12 s / 161 MB | 35 ms / 0.12 s / 182 MB |
| five columns | pyarrow | 7 ms / 0.02 s / 71 MB | 10 ms / 0.02 s / 62 MB | 35 ms / 0.12 s / 188 MB |
| five columns | polars | 8 ms / 0.02 s / 73 MB | 12 ms / 0.03 s / 63 MB | 39 ms / 0.14 s / 179 MB |
| five columns | ours | 9 ms / 0.03 s / 74 MB | 11 ms / 0.02 s / 63 MB | 35 ms / 0.13 s / 183 MB |
| 1,000 rows | pyarrow | 11 ms / 0.04 s / 80 MB | 49 ms / 0.09 s / 120 MB | 16 ms / 0.04 s / 115 MB |
| 1,000 rows | polars | 15 ms / 0.05 s / 79 MB | 60 ms / 0.12 s / 120 MB | 21 ms / 0.06 s / 117 MB |
| 1,000 rows | ours | 13 ms / 0.04 s / 79 MB | 52 ms / 0.09 s / 119 MB | 16 ms / 0.04 s / 116 MB |
| read + pass | pyarrow | 21 ms / 0.05 s / 116 MB | 80 ms / 0.13 s / 160 MB | 39 ms / 0.13 s / 188 MB |
| read + pass | polars | 25 ms / 0.07 s / 118 MB | 90 ms / 0.15 s / 160 MB | 43 ms / 0.15 s / 185 MB |
| read + pass | ours | 23 ms / 0.06 s / 115 MB | 81 ms / 0.13 s / 161 MB | 39 ms / 0.13 s / 184 MB |
| write, defaults | dta | 33 ms / 0.04 s / 107 MB | 92 ms / 0.14 s / 208 MB | 34 ms / 0.05 s / 206 MB |
| write, zstd 3 | dta | 42 ms / 0.07 s / 111 MB | – | 41 ms / 0.07 s / 213 MB |

### 1988_FemResp

8,450 rows, 1,437 columns; Parquet pyarrow 6.1 MB, polars 5.1 MB, ours 6.6 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 61 ms / 0.13 s / 289 MB | 326 ms / 0.45 s / 408 MB | 183 ms / 0.34 s / 392 MB |
| whole file | polars | 94 ms / 0.17 s / 285 MB | 421 ms / 0.59 s / 389 MB | 272 ms / 0.44 s / 372 MB |
| whole file | ours | 69 ms / 0.16 s / 289 MB | 349 ms / 0.45 s / 390 MB | 182 ms / 0.34 s / 398 MB |
| five columns | pyarrow | 10 ms / 0.03 s / 82 MB | 17 ms / 0.04 s / 73 MB | 176 ms / 0.33 s / 390 MB |
| five columns | polars | 11 ms / 0.03 s / 83 MB | 18 ms / 0.04 s / 69 MB | 267 ms / 0.43 s / 371 MB |
| five columns | ours | 18 ms / 0.06 s / 85 MB | 15 ms / 0.04 s / 71 MB | 178 ms / 0.34 s / 397 MB |
| 1,000 rows | pyarrow | 37 ms / 0.10 s / 127 MB | 233 ms / 0.34 s / 287 MB | 56 ms / 0.18 s / 164 MB |
| 1,000 rows | polars | 68 ms / 0.14 s / 124 MB | 320 ms / 0.46 s / 282 MB | 105 ms / 0.24 s / 237 MB |
| 1,000 rows | ours | 44 ms / 0.13 s / 127 MB | 243 ms / 0.36 s / 291 MB | 57 ms / 0.19 s / 169 MB |
| read + pass | pyarrow | 88 ms / 0.16 s / 296 MB | 361 ms / 0.49 s / 419 MB | 206 ms / 0.38 s / 461 MB |
| read + pass | polars | 120 ms / 0.20 s / 297 MB | 465 ms / 0.62 s / 396 MB | 293 ms / 0.47 s / 436 MB |
| read + pass | ours | 94 ms / 0.18 s / 298 MB | 380 ms / 0.49 s / 403 MB | 203 ms / 0.38 s / 463 MB |
| write, defaults | dta | 178 ms / 0.23 s / 288 MB | 495 ms / 0.62 s / 462 MB | 242 ms / 0.36 s / 680 MB |
| write, zstd 3 | dta | 271 ms / 0.34 s / 289 MB | – | 371 ms / 0.50 s / 751 MB |

### 1988_Preg

15,759 rows, 284 columns; Parquet pyarrow 3.3 MB, polars 2.8 MB, ours 3.5 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 26 ms / 0.07 s / 164 MB | 116 ms / 0.17 s / 256 MB | 53 ms / 0.16 s / 228 MB |
| whole file | polars | 44 ms / 0.09 s / 163 MB | 159 ms / 0.24 s / 254 MB | 62 ms / 0.18 s / 201 MB |
| whole file | ours | 30 ms / 0.09 s / 164 MB | 121 ms / 0.17 s / 257 MB | 51 ms / 0.16 s / 225 MB |
| five columns | pyarrow | 8 ms / 0.03 s / 81 MB | 11 ms / 0.02 s / 67 MB | 51 ms / 0.16 s / 226 MB |
| five columns | polars | 9 ms / 0.03 s / 82 MB | 14 ms / 0.03 s / 68 MB | 60 ms / 0.18 s / 201 MB |
| five columns | ours | 12 ms / 0.05 s / 85 MB | 11 ms / 0.02 s / 66 MB | 50 ms / 0.16 s / 224 MB |
| 1,000 rows | pyarrow | 18 ms / 0.06 s / 89 MB | 88 ms / 0.15 s / 201 MB | 22 ms / 0.07 s / 119 MB |
| 1,000 rows | polars | 35 ms / 0.09 s / 91 MB | 130 ms / 0.22 s / 197 MB | 31 ms / 0.10 s / 141 MB |
| 1,000 rows | ours | 21 ms / 0.08 s / 94 MB | 90 ms / 0.15 s / 200 MB | 22 ms / 0.07 s / 122 MB |
| read + pass | pyarrow | 38 ms / 0.09 s / 165 MB | 130 ms / 0.19 s / 256 MB | 59 ms / 0.17 s / 233 MB |
| read + pass | polars | 55 ms / 0.11 s / 167 MB | 174 ms / 0.26 s / 256 MB | 69 ms / 0.19 s / 210 MB |
| read + pass | ours | 42 ms / 0.10 s / 165 MB | 134 ms / 0.19 s / 257 MB | 59 ms / 0.17 s / 232 MB |
| write, defaults | dta | 67 ms / 0.09 s / 158 MB | 204 ms / 0.29 s / 272 MB | 84 ms / 0.13 s / 298 MB |
| write, zstd 3 | dta | 113 ms / 0.14 s / 159 MB | – | 110 ms / 0.17 s / 321 MB |

### 1995_FemResp

10,847 rows, 5,754 columns; Parquet pyarrow 7.5 MB, polars 6.7 MB, ours 9.5 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 178 ms / 0.30 s / 809 MB | 1.88 s / 2.36 s / 1762 MB | 2.09 s / 2.34 s / 1375 MB |
| whole file | polars | 211 ms / 0.33 s / 807 MB | 1.96 s / 2.50 s / 1742 MB | 4.16 s / 4.42 s / 1394 MB |
| whole file | ours | 191 ms / 0.32 s / 824 MB | 1.77 s / 2.24 s / 1755 MB | 1.90 s / 2.14 s / 1374 MB |
| five columns | pyarrow | 21 ms / 0.05 s / 91 MB | 33 ms / 0.07 s / 106 MB | 1.99 s / 2.24 s / 1375 MB |
| five columns | polars | 21 ms / 0.06 s / 92 MB | 28 ms / 0.06 s / 88 MB | 4.09 s / 4.36 s / 1396 MB |
| five columns | ours | 41 ms / 0.09 s / 104 MB | 27 ms / 0.06 s / 101 MB | 1.80 s / 2.04 s / 1375 MB |
| 1,000 rows | pyarrow | 79 ms / 0.17 s / 230 MB | 1.26 s / 1.55 s / 976 MB | 309 ms / 0.48 s / 279 MB |
| 1,000 rows | polars | 113 ms / 0.22 s / 228 MB | 1.42 s / 1.72 s / 972 MB | 1.11 s / 1.29 s / 566 MB |
| 1,000 rows | ours | 95 ms / 0.20 s / 234 MB | 1.24 s / 1.50 s / 979 MB | 304 ms / 0.47 s / 292 MB |
| read + pass | pyarrow | 247 ms / 0.37 s / 820 MB | 2.04 s / 2.54 s / 1773 MB | 2.20 s / 2.52 s / 1656 MB |
| read + pass | polars | 283 ms / 0.40 s / 818 MB | 2.12 s / 2.66 s / 1751 MB | 4.30 s / 4.63 s / 1673 MB |
| read + pass | ours | 264 ms / 0.40 s / 826 MB | 1.90 s / 2.40 s / 1776 MB | 2.03 s / 2.33 s / 1654 MB |
| write, defaults | dta | 573 ms / 0.67 s / 868 MB | 1.55 s / 1.74 s / 1338 MB | 453 ms / 0.62 s / 2194 MB |
| write, zstd 3 | dta | 720 ms / 0.83 s / 872 MB | – | 1.32 s / 1.52 s / 2546 MB |

### 1995_Preg

21,332 rows, 245 columns; Parquet pyarrow 1.3 MB, polars 1.1 MB, ours 1.4 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2002_FemPreg

13,593 rows, 243 columns; Parquet pyarrow 1.0 MB, polars 0.8 MB, ours 1.1 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2002_FemResp

7,643 rows, 3,087 columns; Parquet pyarrow 3.8 MB, polars 3.4 MB, ours 4.9 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2002_HHvars

12,571 rows, 10 columns; Parquet pyarrow 0.1 MB, polars 0.1 MB, ours 0.1 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2002_Male

4,928 rows, 1,993 columns; Parquet pyarrow 1.8 MB, polars 1.7 MB, ours 2.1 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2002_curr_ins

12,571 rows, 3 columns; Parquet pyarrow 0.1 MB, polars 0.0 MB, ours 0.1 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2002_hhpartypnew

12,571 rows, 3 columns; Parquet pyarrow 0.1 MB, polars 0.0 MB, ours 0.1 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2006_2010_FemPreg

20,492 rows, 287 columns; Parquet pyarrow 1.7 MB, polars 1.4 MB, ours 1.7 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2006_2010_FemResp

12,279 rows, 3,741 columns; Parquet pyarrow 6.8 MB, polars 5.8 MB, ours 8.1 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2006_2010_Male

10,403 rows, 2,801 columns; Parquet pyarrow 3.8 MB, polars 3.3 MB, ours 4.3 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2011_2013_FemPreg

9,543 rows, 278 columns; Parquet pyarrow 0.8 MB, polars 0.7 MB, ours 0.8 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2011_2013_FemResp

5,601 rows, 3,094 columns; Parquet pyarrow 3.7 MB, polars 3.4 MB, ours 4.3 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2011_2013_Male

4,815 rows, 3,059 columns; Parquet pyarrow 2.4 MB, polars 2.3 MB, ours 2.9 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2011_2019_FemaleWgt

22,995 rows, 7 columns; Parquet pyarrow 1.0 MB, polars 0.7 MB, ours 0.8 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2011_2019_MaleWgt

19,067 rows, 7 columns; Parquet pyarrow 0.8 MB, polars 0.6 MB, ours 0.7 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2013_2015_FemPreg

9,358 rows, 278 columns; Parquet pyarrow 0.8 MB, polars 0.7 MB, ours 0.8 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2013_2015_FemResp

5,699 rows, 3,207 columns; Parquet pyarrow 3.8 MB, polars 3.4 MB, ours 4.7 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2013_2015_Male

4,506 rows, 2,940 columns; Parquet pyarrow 2.3 MB, polars 2.2 MB, ours 2.9 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2015_2017_FemPreg

9,553 rows, 248 columns; Parquet pyarrow 0.6 MB, polars 0.5 MB, ours 0.6 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2015_2017_FemResp

5,554 rows, 3,024 columns; Parquet pyarrow 3.4 MB, polars 3.1 MB, ours 4.3 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2015_2017_Male

4,540 rows, 2,945 columns; Parquet pyarrow 2.1 MB, polars 2.1 MB, ours 2.8 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2017_2019_FemPreg

10,215 rows, 171 columns; Parquet pyarrow 0.4 MB, polars 0.4 MB, ours 0.5 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2017_2019_FemResp

6,141 rows, 2,609 columns; Parquet pyarrow 3.5 MB, polars 3.1 MB, ours 4.3 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2017_2019_Male

5,206 rows, 3,009 columns; Parquet pyarrow 2.2 MB, polars 2.2 MB, ours 2.9 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2022_2023_FemPreg

8,247 rows, 111 columns; Parquet pyarrow 0.3 MB, polars 0.3 MB, ours 0.3 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2022_2023_FemResp

5,586 rows, 1,912 columns; Parquet pyarrow 2.6 MB, polars 2.3 MB, ours 2.7 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### 2022_2023_MaleResp

4,371 rows, 1,157 columns; Parquet pyarrow 1.2 MB, polars 1.1 MB, ours 1.3 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### Senegal 2019 wm

8,649 rows, 4,997 columns; Parquet pyarrow 4.2 MB, polars 4.0 MB, ours 4.8 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### Senegal 2019 bh

21,562 rows, 1,191 columns; Parquet pyarrow 4.0 MB, polars 3.1 MB, ours 4.0 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### Turkey 2013 wm

9,746 rows, 4,668 columns; Parquet pyarrow 4.3 MB, polars 4.0 MB, ours 4.9 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### Turkey 2013 bh

17,871 rows, 1,173 columns; Parquet pyarrow 3.3 MB, polars 2.7 MB, ours 3.5 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### Tajikistan 2017 wm

10,718 rows, 5,160 columns; Parquet pyarrow 5.7 MB, polars 5.3 MB, ours 6.4 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### Tajikistan 2017 bh

21,985 rows, 1,146 columns; Parquet pyarrow 4.8 MB, polars 3.8 MB, ours 4.8 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### Myanmar 2016 wm

12,885 rows, 4,993 columns; Parquet pyarrow 5.3 MB, polars 4.9 MB, ours 5.9 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### Myanmar 2016 bh

22,989 rows, 1,184 columns; Parquet pyarrow 4.2 MB, polars 3.3 MB, ours 4.3 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### Dominican Republic 2013 wm

9,372 rows, 3,854 columns; Parquet pyarrow 3.8 MB, polars 3.5 MB, ours 4.3 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

### Dominican Republic 2013 bh

18,167 rows, 1,078 columns; Parquet pyarrow 3.5 MB, polars 2.8 MB, ours 3.6 MB.

| case | input | ours | hyparquet | parquet-wasm |
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
| write, defaults | dta | – | – | – |
| write, zstd 3 | dta | – | – | – |

