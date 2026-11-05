# Parquet benchmarks (TypeScript, Node)

Written by `bench/parquet/run_node.py`; see bench/RESULTS.md for what the numbers mean.

One-minute load average before each run: median 10.8, range 8.8 to 25.6, over 9,930 runs.

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
| hyparquet (writes: hyparquet-writer) | whole file | pyarrow | NSFG | 36 | 0.24 | 0.30 | 0.70 |
| hyparquet (writes: hyparquet-writer) | whole file | pyarrow | DHS | 10 | 0.12 | 0.18 | 0.55 |
| hyparquet (writes: hyparquet-writer) | whole file | pyarrow | Synthetic | 2 | 0.18 | 0.11 | 0.28 |
| hyparquet (writes: hyparquet-writer) | whole file | polars | NSFG | 36 | 0.22 | 0.28 | 0.71 |
| hyparquet (writes: hyparquet-writer) | whole file | polars | DHS | 10 | 0.12 | 0.18 | 0.55 |
| hyparquet (writes: hyparquet-writer) | whole file | polars | Synthetic | 2 | 0.18 | 0.12 | 0.26 |
| hyparquet (writes: hyparquet-writer) | whole file | ours | NSFG | 36 | 0.25 | 0.33 | 0.70 |
| hyparquet (writes: hyparquet-writer) | whole file | ours | DHS | 10 | 0.13 | 0.21 | 0.55 |
| hyparquet (writes: hyparquet-writer) | whole file | ours | Synthetic | 1 | 0.22 | 0.19 | 0.23 |
| hyparquet (writes: hyparquet-writer) | five columns | pyarrow | NSFG | 36 | 0.66 | 0.63 | 0.98 |
| hyparquet (writes: hyparquet-writer) | five columns | pyarrow | DHS | 10 | 0.68 | 0.76 | 0.92 |
| hyparquet (writes: hyparquet-writer) | five columns | pyarrow | Synthetic | 3 | 0.23 | 0.20 | 0.34 |
| hyparquet (writes: hyparquet-writer) | five columns | polars | NSFG | 36 | 0.62 | 0.56 | 1.01 |
| hyparquet (writes: hyparquet-writer) | five columns | polars | DHS | 10 | 0.61 | 0.77 | 0.95 |
| hyparquet (writes: hyparquet-writer) | five columns | polars | Synthetic | 3 | 0.19 | 0.17 | 0.37 |
| hyparquet (writes: hyparquet-writer) | five columns | ours | NSFG | 36 | 0.93 | 0.96 | 1.03 |
| hyparquet (writes: hyparquet-writer) | five columns | ours | DHS | 10 | 1.04 | 1.39 | 0.99 |
| hyparquet (writes: hyparquet-writer) | five columns | ours | Synthetic | 3 | 0.22 | 0.18 | 0.33 |
| hyparquet (writes: hyparquet-writer) | 1,000 rows | pyarrow | NSFG | 36 | 0.20 | 0.27 | 0.51 |
| hyparquet (writes: hyparquet-writer) | 1,000 rows | pyarrow | DHS | 10 | 0.08 | 0.15 | 0.27 |
| hyparquet (writes: hyparquet-writer) | 1,000 rows | pyarrow | Synthetic | 3 | 0.47 | 0.25 | 0.30 |
| hyparquet (writes: hyparquet-writer) | 1,000 rows | polars | NSFG | 36 | 0.19 | 0.27 | 0.51 |
| hyparquet (writes: hyparquet-writer) | 1,000 rows | polars | DHS | 10 | 0.08 | 0.15 | 0.26 |
| hyparquet (writes: hyparquet-writer) | 1,000 rows | polars | Synthetic | 3 | 0.21 | 0.21 | 0.32 |
| hyparquet (writes: hyparquet-writer) | 1,000 rows | ours | NSFG | 36 | 0.21 | 0.31 | 0.51 |
| hyparquet (writes: hyparquet-writer) | 1,000 rows | ours | DHS | 10 | 0.08 | 0.17 | 0.26 |
| hyparquet (writes: hyparquet-writer) | 1,000 rows | ours | Synthetic | 3 | 0.15 | 0.15 | 0.22 |
| hyparquet (writes: hyparquet-writer) | read + pass | pyarrow | NSFG | 36 | 0.30 | 0.35 | 0.72 |
| hyparquet (writes: hyparquet-writer) | read + pass | pyarrow | DHS | 10 | 0.15 | 0.21 | 0.56 |
| hyparquet (writes: hyparquet-writer) | read + pass | pyarrow | Synthetic | 2 | 0.21 | 0.13 | 0.29 |
| hyparquet (writes: hyparquet-writer) | read + pass | polars | NSFG | 36 | 0.28 | 0.32 | 0.72 |
| hyparquet (writes: hyparquet-writer) | read + pass | polars | DHS | 10 | 0.16 | 0.22 | 0.57 |
| hyparquet (writes: hyparquet-writer) | read + pass | polars | Synthetic | 2 | 0.20 | 0.14 | 0.27 |
| hyparquet (writes: hyparquet-writer) | read + pass | ours | NSFG | 36 | 0.32 | 0.38 | 0.71 |
| hyparquet (writes: hyparquet-writer) | read + pass | ours | DHS | 10 | 0.17 | 0.24 | 0.57 |
| hyparquet (writes: hyparquet-writer) | read + pass | ours | Synthetic | 1 | 0.31 | 0.27 | 0.26 |
| hyparquet (writes: hyparquet-writer) | write, defaults | dta | NSFG | 36 | 0.32 | 0.31 | 0.66 |
| hyparquet (writes: hyparquet-writer) | write, defaults | dta | DHS | 10 | 0.30 | 0.31 | 0.62 |
| hyparquet (writes: hyparquet-writer) | write, defaults | dta | Synthetic | 2 | 0.37 | 0.32 | 0.50 |
| parquet-wasm | whole file | pyarrow | NSFG | 36 | 0.32 | 0.30 | 0.67 |
| parquet-wasm | whole file | pyarrow | DHS | 10 | 0.18 | 0.23 | 0.59 |
| parquet-wasm | whole file | pyarrow | Synthetic | 2 | 0.19 | 0.20 | 0.24 |
| parquet-wasm | whole file | polars | NSFG | 36 | 0.25 | 0.27 | 0.65 |
| parquet-wasm | whole file | polars | DHS | 10 | 0.11 | 0.17 | 0.66 |
| parquet-wasm | whole file | polars | Synthetic | 2 | 0.18 | 0.19 | 0.24 |
| parquet-wasm | whole file | ours | NSFG | 36 | 0.35 | 0.34 | 0.66 |
| parquet-wasm | whole file | ours | DHS | 10 | 0.19 | 0.26 | 0.61 |
| parquet-wasm | whole file | ours | Synthetic | 2 | 0.21 | 0.23 | 0.25 |
| parquet-wasm | five columns | pyarrow | NSFG | 36 | 0.10 | 0.11 | 0.27 |
| parquet-wasm | five columns | pyarrow | DHS | 10 | 0.03 | 0.05 | 0.09 |
| parquet-wasm | five columns | pyarrow | Synthetic | 2 | 0.16 | 0.17 | 0.20 |
| parquet-wasm | five columns | polars | NSFG | 36 | 0.08 | 0.09 | 0.25 |
| parquet-wasm | five columns | polars | DHS | 10 | 0.02 | 0.04 | 0.10 |
| parquet-wasm | five columns | polars | Synthetic | 2 | 0.14 | 0.16 | 0.19 |
| parquet-wasm | five columns | ours | NSFG | 36 | 0.14 | 0.16 | 0.27 |
| parquet-wasm | five columns | ours | DHS | 10 | 0.04 | 0.09 | 0.10 |
| parquet-wasm | five columns | ours | Synthetic | 2 | 0.19 | 0.20 | 0.19 |
| parquet-wasm | 1,000 rows | pyarrow | NSFG | 36 | 0.49 | 0.48 | 0.70 |
| parquet-wasm | 1,000 rows | pyarrow | DHS | 10 | 0.43 | 0.42 | 0.77 |
| parquet-wasm | 1,000 rows | pyarrow | Synthetic | 2 | 0.30 | 0.30 | 0.23 |
| parquet-wasm | 1,000 rows | polars | NSFG | 36 | 0.35 | 0.42 | 0.54 |
| parquet-wasm | 1,000 rows | polars | DHS | 10 | 0.21 | 0.30 | 0.46 |
| parquet-wasm | 1,000 rows | polars | Synthetic | 2 | 0.27 | 0.29 | 0.17 |
| parquet-wasm | 1,000 rows | ours | NSFG | 36 | 0.56 | 0.56 | 0.71 |
| parquet-wasm | 1,000 rows | ours | DHS | 10 | 0.49 | 0.51 | 0.79 |
| parquet-wasm | 1,000 rows | ours | Synthetic | 2 | 0.25 | 0.27 | 0.17 |
| parquet-wasm | read + pass | pyarrow | NSFG | 36 | 0.41 | 0.35 | 0.63 |
| parquet-wasm | read + pass | pyarrow | DHS | 10 | 0.23 | 0.26 | 0.51 |
| parquet-wasm | read + pass | pyarrow | Synthetic | 2 | 0.12 | 0.12 | 0.17 |
| parquet-wasm | read + pass | polars | NSFG | 36 | 0.32 | 0.32 | 0.61 |
| parquet-wasm | read + pass | polars | DHS | 10 | 0.15 | 0.19 | 0.56 |
| parquet-wasm | read + pass | polars | Synthetic | 2 | 0.11 | 0.12 | 0.17 |
| parquet-wasm | read + pass | ours | NSFG | 36 | 0.44 | 0.39 | 0.62 |
| parquet-wasm | read + pass | ours | DHS | 10 | 0.24 | 0.29 | 0.52 |
| parquet-wasm | read + pass | ours | Synthetic | 2 | 0.13 | 0.13 | 0.17 |
| parquet-wasm | write, defaults | dta | NSFG | 36 | 0.62 | 0.57 | 0.49 |
| parquet-wasm | write, defaults | dta | DHS | 10 | 0.94 | 0.75 | 0.41 |
| parquet-wasm | write, defaults | dta | Synthetic | 2 | 0.97 | 0.89 | 0.10 |
| parquet-wasm | write, zstd 3 | dta | NSFG | 36 | 0.45 | 0.49 | 0.46 |
| parquet-wasm | write, zstd 3 | dta | DHS | 10 | 0.56 | 0.54 | 0.36 |
| parquet-wasm | write, zstd 3 | dta | Synthetic | 2 | 0.87 | 0.83 | 0.11 |

## Misses

- 3 CPU: hyparquet five ours 1982_FemResp: 0.035 s vs 0.024 s, speedup 0.98 allows 0.027 s
- 3 CPU: hyparquet five ours 1988_FemResp: 0.047 s vs 0.037 s, speedup 0.98 allows 0.042 s
- 3 CPU: hyparquet five ours 1988_Preg: 0.026 s vs 0.021 s, speedup 1.11 allows 0.025 s
- 3 CPU: hyparquet five ours 1995_FemResp: 0.090 s vs 0.056 s, speedup 0.84 allows 0.064 s
- 3 CPU: hyparquet five ours 2002_FemResp: 0.078 s vs 0.049 s, speedup 0.86 allows 0.057 s
- 3 CPU: hyparquet five ours 2002_Male: 0.064 s vs 0.041 s, speedup 0.89 allows 0.048 s
- 3 CPU: hyparquet five ours 2006_2010_FemResp: 0.081 s vs 0.059 s, speedup 1.02 allows 0.067 s
- 3 CPU: hyparquet five ours 2006_2010_Male: 0.074 s vs 0.059 s, speedup 1.11 allows 0.068 s
- 3 CPU: hyparquet five ours 2011_2013_FemResp: 0.076 s vs 0.051 s, speedup 1.07 allows 0.059 s
- 3 CPU: hyparquet five ours 2011_2013_Male: 0.075 s vs 0.042 s, speedup 0.90 allows 0.049 s
- 3 CPU: hyparquet five ours 2013_2015_Male: 0.078 s vs 0.047 s, speedup 0.92 allows 0.054 s
- 3 CPU: hyparquet five ours 2015_2017_FemResp: 0.068 s vs 0.042 s, speedup 0.87 allows 0.048 s
- 3 CPU: hyparquet five ours 2015_2017_Male: 0.067 s vs 0.039 s, speedup 0.87 allows 0.044 s
- 3 CPU: hyparquet five ours 2017_2019_FemResp: 0.066 s vs 0.043 s, speedup 0.94 allows 0.050 s
- 3 CPU: hyparquet five ours 2017_2019_Male: 0.080 s vs 0.046 s, speedup 0.71 allows 0.052 s
- 3 CPU: hyparquet five ours 2022_2023_MaleResp: 0.033 s vs 0.023 s, speedup 1.05 allows 0.027 s
- 3 CPU: hyparquet five ours Senegal 2019 wm: 0.091 s vs 0.054 s, speedup 0.74 allows 0.062 s
- 3 CPU: hyparquet five ours Senegal 2019 bh: 0.060 s vs 0.039 s, speedup 1.11 allows 0.045 s
- 3 CPU: hyparquet five ours Turkey 2013 wm: 0.093 s vs 0.052 s, speedup 0.77 allows 0.060 s
- 3 CPU: hyparquet five ours Turkey 2013 bh: 0.046 s vs 0.037 s, speedup 1.07 allows 0.043 s
- 3 CPU: hyparquet five ours Tajikistan 2017 wm: 0.088 s vs 0.058 s, speedup 0.86 allows 0.067 s
- 3 CPU: hyparquet five ours Tajikistan 2017 bh: 0.048 s vs 0.042 s, speedup 1.13 allows 0.048 s
- 3 CPU: hyparquet five ours Myanmar 2016 wm: 0.092 s vs 0.065 s, speedup 0.95 allows 0.074 s
- 3 CPU: hyparquet five ours Myanmar 2016 bh: 0.052 s vs 0.045 s, speedup 1.12 allows 0.052 s
- 3 CPU: hyparquet five ours Dominican Republic 2013 wm: 0.076 s vs 0.051 s, speedup 0.89 allows 0.059 s

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
| whole file | pyarrow | 955 ms / 1.08 s / 1689 MB | 6.75 s / 18.45 s / 5637 MB | 4.38 s / 4.70 s / 5169 MB |
| whole file | polars | 1.49 s / 1.66 s / 1681 MB | 11.12 s / 24.66 s / 6377 MB | 5.74 s / 6.03 s / 5291 MB |
| whole file | ours | 908 ms / 1.07 s / 1683 MB | failed | 3.16 s / 3.41 s / 5145 MB |
| five columns | pyarrow | 743 ms / 0.84 s / 1095 MB | 2.96 s / 5.94 s / 2884 MB | 4.46 s / 4.75 s / 5168 MB |
| five columns | polars | 953 ms / 1.11 s / 1045 MB | 4.31 s / 7.63 s / 2791 MB | 5.71 s / 5.98 s / 5292 MB |
| five columns | ours | 727 ms / 0.81 s / 1042 MB | 2.90 s / 6.49 s / 3206 MB | 3.15 s / 3.41 s / 5145 MB |
| 1,000 rows | pyarrow | 24 ms / 0.04 s / 150 MB | 48 ms / 0.12 s / 234 MB | 104 ms / 0.15 s / 1414 MB |
| 1,000 rows | polars | 19 ms / 0.04 s / 81 MB | 121 ms / 0.23 s / 181 MB | 105 ms / 0.16 s / 1304 MB |
| 1,000 rows | ours | 10 ms / 0.02 s / 80 MB | 76 ms / 0.13 s / 210 MB | 89 ms / 0.12 s / 1372 MB |
| read + pass | pyarrow | 1.28 s / 1.40 s / 1724 MB | 9.02 s / 22.61 s / 5737 MB | 7.64 s / 8.32 s / 7153 MB |
| read + pass | polars | 1.74 s / 1.93 s / 1692 MB | 13.37 s / 29.52 s / 6443 MB | 9.97 s / 10.74 s / 7257 MB |
| read + pass | ours | 1.18 s / 1.31 s / 1695 MB | failed | 6.42 s / 7.08 s / 7131 MB |
| write, defaults | dta | 2.67 s / 2.98 s / 1965 MB | 9.03 s / 13.51 s / 4876 MB | 2.46 s / 3.11 s / 11932 MB |
| write, zstd 3 | dta | 3.61 s / 3.92 s / 1966 MB | – | 4.03 s / 4.70 s / 11109 MB |

### wide.dta

1,500,000 rows, 400 columns; Parquet pyarrow 5020.6 MB, polars 4607.6 MB, ours 4800.8 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 1.55 s / 1.66 s / 5573 MB | failed | failed |
| whole file | polars | 6.12 s / 6.25 s / 5561 MB | failed | failed |
| whole file | ours | 1.29 s / 1.40 s / 5560 MB | failed | failed |
| five columns | pyarrow | 33 ms / 0.06 s / 202 MB | 174 ms / 0.26 s / 508 MB | failed |
| five columns | polars | 91 ms / 0.13 s / 206 MB | 612 ms / 0.75 s / 493 MB | failed |
| five columns | ours | 29 ms / 0.05 s / 200 MB | 165 ms / 0.25 s / 555 MB | failed |
| 1,000 rows | pyarrow | 205 ms / 0.25 s / 294 MB | 702 ms / 2.50 s / 7242 MB | failed |
| 1,000 rows | polars | 302 ms / 0.35 s / 94 MB | 2.55 s / 2.83 s / 1126 MB | failed |
| 1,000 rows | ours | 44 ms / 0.07 s / 91 MB | 674 ms / 1.12 s / 2439 MB | failed |
| read + pass | pyarrow | 2.64 s / 2.75 s / 5577 MB | failed | failed |
| read + pass | polars | 7.16 s / 7.30 s / 5562 MB | failed | failed |
| read + pass | ours | 2.34 s / 2.45 s / 5564 MB | failed | failed |
| write, defaults | dta | 7.20 s / 7.19 s / 5574 MB | failed | failed |
| write, zstd 3 | dta | 13.61 s / 13.65 s / 5579 MB | – | failed |

### groups.dta

15,000,000 rows, 2 columns; Parquet pyarrow 24.1 MB, polars 23.4 MB, ours 24.0 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 221 ms / 0.26 s / 375 MB | 919 ms / 1.18 s / 1435 MB | 1.35 s / 1.52 s / 2087 MB |
| whole file | polars | 213 ms / 0.26 s / 394 MB | 892 ms / 1.18 s / 1572 MB | 1.71 s / 1.92 s / 2146 MB |
| whole file | ours | 208 ms / 0.25 s / 392 MB | 959 ms / 1.34 s / 1685 MB | 1.33 s / 1.53 s / 2108 MB |
| five columns | pyarrow | 225 ms / 0.25 s / 375 MB | 861 ms / 1.14 s / 1402 MB | 1.42 s / 1.60 s / 2089 MB |
| five columns | polars | 213 ms / 0.26 s / 393 MB | 954 ms / 1.31 s / 1179 MB | 1.73 s / 1.95 s / 2147 MB |
| five columns | ours | 208 ms / 0.25 s / 391 MB | 902 ms / 1.23 s / 1238 MB | 1.34 s / 1.55 s / 2108 MB |
| 1,000 rows | pyarrow | 6 ms / 0.01 s / 65 MB | 8 ms / 0.02 s / 66 MB | 16 ms / 0.02 s / 129 MB |
| 1,000 rows | polars | 8 ms / 0.01 s / 67 MB | 16 ms / 0.03 s / 75 MB | 18 ms / 0.03 s / 139 MB |
| 1,000 rows | ours | 8 ms / 0.01 s / 67 MB | 22 ms / 0.04 s / 87 MB | 16 ms / 0.03 s / 136 MB |
| read + pass | pyarrow | 305 ms / 0.35 s / 390 MB | 973 ms / 1.26 s / 1436 MB | 3.44 s / 3.75 s / 3286 MB |
| read + pass | polars | 300 ms / 0.35 s / 409 MB | 967 ms / 1.25 s / 1520 MB | 4.31 s / 4.67 s / 3315 MB |
| read + pass | ours | 296 ms / 0.35 s / 407 MB | 968 ms / 1.29 s / 1563 MB | 3.45 s / 3.81 s / 3303 MB |
| write, defaults | dta | 994 ms / 1.03 s / 491 MB | 2.11 s / 2.19 s / 785 MB | 1.15 s / 1.23 s / 7353 MB |
| write, zstd 3 | dta | 1.02 s / 1.05 s / 498 MB | – | 1.20 s / 1.29 s / 7355 MB |

### 1973_FemResp

9,797 rows, 450 columns; Parquet pyarrow 1.6 MB, polars 1.3 MB, ours 1.7 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 28 ms / 0.06 s / 156 MB | 120 ms / 0.19 s / 191 MB | 62 ms / 0.18 s / 220 MB |
| whole file | polars | 32 ms / 0.07 s / 158 MB | 152 ms / 0.25 s / 193 MB | 68 ms / 0.20 s / 214 MB |
| whole file | ours | 30 ms / 0.07 s / 158 MB | 126 ms / 0.19 s / 188 MB | 57 ms / 0.18 s / 208 MB |
| five columns | pyarrow | 7 ms / 0.02 s / 67 MB | 11 ms / 0.02 s / 65 MB | 61 ms / 0.18 s / 218 MB |
| five columns | polars | 8 ms / 0.01 s / 66 MB | 12 ms / 0.03 s / 63 MB | 68 ms / 0.19 s / 214 MB |
| five columns | ours | 9 ms / 0.02 s / 68 MB | 10 ms / 0.02 s / 64 MB | 55 ms / 0.18 s / 207 MB |
| 1,000 rows | pyarrow | 17 ms / 0.05 s / 84 MB | 89 ms / 0.14 s / 170 MB | 26 ms / 0.10 s / 130 MB |
| 1,000 rows | polars | 21 ms / 0.06 s / 87 MB | 120 ms / 0.19 s / 167 MB | 35 ms / 0.12 s / 154 MB |
| 1,000 rows | ours | 19 ms / 0.06 s / 85 MB | 105 ms / 0.15 s / 166 MB | 26 ms / 0.09 s / 129 MB |
| read + pass | pyarrow | 44 ms / 0.09 s / 158 MB | 133 ms / 0.21 s / 191 MB | 72 ms / 0.20 s / 233 MB |
| read + pass | polars | 47 ms / 0.10 s / 160 MB | 164 ms / 0.26 s / 188 MB | 81 ms / 0.22 s / 232 MB |
| read + pass | ours | 47 ms / 0.09 s / 159 MB | 138 ms / 0.21 s / 189 MB | 70 ms / 0.20 s / 224 MB |
| write, defaults | dta | 60 ms / 0.08 s / 158 MB | 199 ms / 0.32 s / 262 MB | 85 ms / 0.15 s / 319 MB |
| write, zstd 3 | dta | 67 ms / 0.10 s / 162 MB | – | 105 ms / 0.18 s / 345 MB |

### 1976_FemResp

8,611 rows, 468 columns; Parquet pyarrow 1.8 MB, polars 1.4 MB, ours 2.2 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 27 ms / 0.06 s / 153 MB | 110 ms / 0.16 s / 210 MB | 55 ms / 0.18 s / 206 MB |
| whole file | polars | 30 ms / 0.08 s / 155 MB | 141 ms / 0.22 s / 210 MB | 68 ms / 0.19 s / 203 MB |
| whole file | ours | 30 ms / 0.08 s / 157 MB | 120 ms / 0.17 s / 202 MB | 56 ms / 0.18 s / 224 MB |
| five columns | pyarrow | 7 ms / 0.02 s / 67 MB | 11 ms / 0.03 s / 64 MB | 53 ms / 0.18 s / 205 MB |
| five columns | polars | 8 ms / 0.02 s / 68 MB | 13 ms / 0.03 s / 63 MB | 67 ms / 0.19 s / 202 MB |
| five columns | ours | 11 ms / 0.03 s / 69 MB | 11 ms / 0.03 s / 65 MB | 54 ms / 0.17 s / 221 MB |
| 1,000 rows | pyarrow | 18 ms / 0.06 s / 86 MB | 81 ms / 0.12 s / 166 MB | 27 ms / 0.10 s / 135 MB |
| 1,000 rows | polars | 22 ms / 0.07 s / 87 MB | 116 ms / 0.18 s / 168 MB | 36 ms / 0.13 s / 154 MB |
| 1,000 rows | ours | 21 ms / 0.07 s / 88 MB | 86 ms / 0.13 s / 165 MB | 26 ms / 0.10 s / 143 MB |
| read + pass | pyarrow | 42 ms / 0.08 s / 158 MB | 126 ms / 0.19 s / 192 MB | 65 ms / 0.20 s / 218 MB |
| read + pass | polars | 47 ms / 0.10 s / 159 MB | 154 ms / 0.24 s / 190 MB | 76 ms / 0.21 s / 216 MB |
| read + pass | ours | 45 ms / 0.10 s / 160 MB | 130 ms / 0.18 s / 202 MB | 63 ms / 0.19 s / 241 MB |
| write, defaults | dta | 57 ms / 0.09 s / 162 MB | 180 ms / 0.28 s / 267 MB | 86 ms / 0.15 s / 323 MB |
| write, zstd 3 | dta | 67 ms / 0.11 s / 167 MB | – | 107 ms / 0.18 s / 343 MB |

### 1976_PSU

8,611 rows, 3 columns; Parquet pyarrow 0.1 MB, polars 0.0 MB, ours 0.0 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 5 ms / 0.01 s / 60 MB | 4 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 79 MB |
| whole file | polars | 6 ms / 0.01 s / 60 MB | 6 ms / 0.01 s / 57 MB | 12 ms / 0.01 s / 79 MB |
| whole file | ours | 6 ms / 0.01 s / 60 MB | 4 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 79 MB |
| five columns | pyarrow | 5 ms / 0.01 s / 60 MB | 6 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 79 MB |
| five columns | polars | 6 ms / 0.01 s / 61 MB | 7 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 79 MB |
| five columns | ours | 6 ms / 0.01 s / 61 MB | 6 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 79 MB |
| 1,000 rows | pyarrow | 5 ms / 0.01 s / 60 MB | 5 ms / 0.01 s / 58 MB | 11 ms / 0.01 s / 79 MB |
| 1,000 rows | polars | 6 ms / 0.01 s / 60 MB | 7 ms / 0.01 s / 57 MB | 12 ms / 0.01 s / 79 MB |
| 1,000 rows | ours | 6 ms / 0.01 s / 60 MB | 5 ms / 0.01 s / 57 MB | 11 ms / 0.01 s / 79 MB |
| read + pass | pyarrow | 6 ms / 0.01 s / 62 MB | 5 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 80 MB |
| read + pass | polars | 7 ms / 0.01 s / 63 MB | 6 ms / 0.01 s / 57 MB | 12 ms / 0.01 s / 79 MB |
| read + pass | ours | 7 ms / 0.01 s / 62 MB | 5 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 79 MB |
| write, defaults | dta | 4 ms / 0.01 s / 65 MB | 7 ms / 0.02 s / 73 MB | 11 ms / 0.01 s / 93 MB |
| write, zstd 3 | dta | 5 ms / 0.01 s / 65 MB | – | 14 ms / 0.02 s / 93 MB |

### 1976_Preg

23,042 rows, 80 columns; Parquet pyarrow 0.4 MB, polars 0.3 MB, ours 0.4 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 15 ms / 0.03 s / 100 MB | 54 ms / 0.09 s / 147 MB | 31 ms / 0.12 s / 171 MB |
| whole file | polars | 15 ms / 0.03 s / 101 MB | 65 ms / 0.12 s / 150 MB | 34 ms / 0.13 s / 164 MB |
| whole file | ours | 15 ms / 0.03 s / 99 MB | 55 ms / 0.09 s / 147 MB | 31 ms / 0.12 s / 168 MB |
| five columns | pyarrow | 7 ms / 0.01 s / 66 MB | 11 ms / 0.03 s / 67 MB | 31 ms / 0.11 s / 171 MB |
| five columns | polars | 7 ms / 0.01 s / 67 MB | 14 ms / 0.03 s / 68 MB | 34 ms / 0.13 s / 163 MB |
| five columns | ours | 8 ms / 0.01 s / 68 MB | 11 ms / 0.03 s / 67 MB | 31 ms / 0.12 s / 169 MB |
| 1,000 rows | pyarrow | 9 ms / 0.02 s / 68 MB | 34 ms / 0.07 s / 100 MB | 15 ms / 0.04 s / 115 MB |
| 1,000 rows | polars | 10 ms / 0.02 s / 69 MB | 53 ms / 0.10 s / 116 MB | 18 ms / 0.05 s / 109 MB |
| 1,000 rows | ours | 10 ms / 0.02 s / 68 MB | 45 ms / 0.08 s / 116 MB | 15 ms / 0.04 s / 114 MB |
| read + pass | pyarrow | 22 ms / 0.04 s / 104 MB | 60 ms / 0.10 s / 147 MB | 36 ms / 0.13 s / 172 MB |
| read + pass | polars | 22 ms / 0.04 s / 104 MB | 74 ms / 0.14 s / 147 MB | 39 ms / 0.14 s / 164 MB |
| read + pass | ours | 23 ms / 0.04 s / 103 MB | 64 ms / 0.11 s / 149 MB | 35 ms / 0.13 s / 171 MB |
| write, defaults | dta | 24 ms / 0.03 s / 98 MB | 77 ms / 0.13 s / 178 MB | 35 ms / 0.05 s / 178 MB |
| write, zstd 3 | dta | 27 ms / 0.05 s / 106 MB | – | 42 ms / 0.06 s / 195 MB |

### 1982_FemResp

7,969 rows, 741 columns; Parquet pyarrow 1.8 MB, polars 1.5 MB, ours 2.1 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 34 ms / 0.08 s / 185 MB | 175 ms / 0.26 s / 258 MB | 76 ms / 0.21 s / 258 MB |
| whole file | polars | 37 ms / 0.09 s / 185 MB | 197 ms / 0.29 s / 250 MB | 98 ms / 0.23 s / 245 MB |
| whole file | ours | 37 ms / 0.09 s / 185 MB | 182 ms / 0.27 s / 258 MB | 77 ms / 0.22 s / 265 MB |
| five columns | pyarrow | 8 ms / 0.02 s / 70 MB | 12 ms / 0.03 s / 67 MB | 74 ms / 0.20 s / 257 MB |
| five columns | polars | 9 ms / 0.02 s / 69 MB | 13 ms / 0.03 s / 66 MB | 97 ms / 0.23 s / 243 MB |
| five columns | ours | 12 ms / 0.04 s / 70 MB | 11 ms / 0.02 s / 67 MB | 74 ms / 0.20 s / 262 MB |
| 1,000 rows | pyarrow | 23 ms / 0.07 s / 93 MB | 132 ms / 0.22 s / 214 MB | 34 ms / 0.13 s / 147 MB |
| 1,000 rows | polars | 26 ms / 0.08 s / 93 MB | 151 ms / 0.24 s / 200 MB | 48 ms / 0.15 s / 168 MB |
| 1,000 rows | ours | 24 ms / 0.08 s / 94 MB | 138 ms / 0.23 s / 203 MB | 34 ms / 0.13 s / 146 MB |
| read + pass | pyarrow | 49 ms / 0.10 s / 188 MB | 197 ms / 0.29 s / 268 MB | 87 ms / 0.22 s / 283 MB |
| read + pass | polars | 53 ms / 0.11 s / 191 MB | 219 ms / 0.32 s / 263 MB | 110 ms / 0.26 s / 272 MB |
| read + pass | ours | 53 ms / 0.11 s / 189 MB | 203 ms / 0.30 s / 267 MB | 88 ms / 0.22 s / 292 MB |
| write, defaults | dta | 77 ms / 0.12 s / 190 MB | 241 ms / 0.37 s / 308 MB | 121 ms / 0.21 s / 393 MB |
| write, zstd 3 | dta | 86 ms / 0.14 s / 193 MB | – | 159 ms / 0.26 s / 430 MB |

### 1982_Preg

13,768 rows, 174 columns; Parquet pyarrow 0.4 MB, polars 0.4 MB, ours 0.5 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 16 ms / 0.04 s / 110 MB | 70 ms / 0.11 s / 161 MB | 36 ms / 0.13 s / 188 MB |
| whole file | polars | 20 ms / 0.05 s / 110 MB | 77 ms / 0.13 s / 162 MB | 40 ms / 0.14 s / 186 MB |
| whole file | ours | 17 ms / 0.04 s / 113 MB | 71 ms / 0.12 s / 161 MB | 35 ms / 0.12 s / 182 MB |
| five columns | pyarrow | 7 ms / 0.01 s / 66 MB | 10 ms / 0.02 s / 62 MB | 35 ms / 0.12 s / 188 MB |
| five columns | polars | 7 ms / 0.01 s / 66 MB | 12 ms / 0.03 s / 63 MB | 39 ms / 0.14 s / 179 MB |
| five columns | ours | 8 ms / 0.02 s / 68 MB | 11 ms / 0.02 s / 63 MB | 35 ms / 0.13 s / 183 MB |
| 1,000 rows | pyarrow | 10 ms / 0.03 s / 71 MB | 49 ms / 0.09 s / 120 MB | 16 ms / 0.04 s / 115 MB |
| 1,000 rows | polars | 12 ms / 0.04 s / 73 MB | 60 ms / 0.12 s / 120 MB | 21 ms / 0.06 s / 117 MB |
| 1,000 rows | ours | 12 ms / 0.03 s / 71 MB | 52 ms / 0.09 s / 119 MB | 16 ms / 0.04 s / 116 MB |
| read + pass | pyarrow | 21 ms / 0.05 s / 115 MB | 80 ms / 0.13 s / 160 MB | 39 ms / 0.13 s / 188 MB |
| read + pass | polars | 25 ms / 0.05 s / 113 MB | 90 ms / 0.15 s / 160 MB | 43 ms / 0.15 s / 185 MB |
| read + pass | ours | 22 ms / 0.05 s / 115 MB | 81 ms / 0.13 s / 161 MB | 39 ms / 0.13 s / 184 MB |
| write, defaults | dta | 28 ms / 0.04 s / 112 MB | 92 ms / 0.14 s / 208 MB | 34 ms / 0.05 s / 206 MB |
| write, zstd 3 | dta | 32 ms / 0.05 s / 120 MB | – | 41 ms / 0.07 s / 213 MB |

### 1988_FemResp

8,450 rows, 1,437 columns; Parquet pyarrow 6.1 MB, polars 5.1 MB, ours 6.6 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 60 ms / 0.13 s / 283 MB | 326 ms / 0.45 s / 408 MB | 183 ms / 0.34 s / 392 MB |
| whole file | polars | 69 ms / 0.15 s / 281 MB | 421 ms / 0.59 s / 389 MB | 272 ms / 0.44 s / 372 MB |
| whole file | ours | 65 ms / 0.14 s / 284 MB | 349 ms / 0.45 s / 390 MB | 182 ms / 0.34 s / 398 MB |
| five columns | pyarrow | 10 ms / 0.03 s / 72 MB | 17 ms / 0.04 s / 73 MB | 176 ms / 0.33 s / 390 MB |
| five columns | polars | 11 ms / 0.03 s / 72 MB | 18 ms / 0.04 s / 69 MB | 267 ms / 0.43 s / 371 MB |
| five columns | ours | 15 ms / 0.05 s / 76 MB | 15 ms / 0.04 s / 71 MB | 178 ms / 0.34 s / 397 MB |
| 1,000 rows | pyarrow | 36 ms / 0.09 s / 120 MB | 233 ms / 0.34 s / 287 MB | 56 ms / 0.18 s / 164 MB |
| 1,000 rows | polars | 45 ms / 0.12 s / 116 MB | 320 ms / 0.46 s / 282 MB | 105 ms / 0.24 s / 237 MB |
| 1,000 rows | ours | 39 ms / 0.11 s / 121 MB | 243 ms / 0.36 s / 291 MB | 57 ms / 0.19 s / 169 MB |
| read + pass | pyarrow | 89 ms / 0.16 s / 286 MB | 361 ms / 0.49 s / 419 MB | 206 ms / 0.38 s / 461 MB |
| read + pass | polars | 97 ms / 0.18 s / 286 MB | 465 ms / 0.62 s / 396 MB | 293 ms / 0.47 s / 436 MB |
| read + pass | ours | 92 ms / 0.17 s / 288 MB | 380 ms / 0.49 s / 403 MB | 203 ms / 0.38 s / 463 MB |
| write, defaults | dta | 150 ms / 0.20 s / 292 MB | 495 ms / 0.62 s / 462 MB | 242 ms / 0.36 s / 680 MB |
| write, zstd 3 | dta | 173 ms / 0.24 s / 297 MB | – | 371 ms / 0.50 s / 751 MB |

### 1988_Preg

15,759 rows, 284 columns; Parquet pyarrow 3.3 MB, polars 2.8 MB, ours 3.5 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 26 ms / 0.05 s / 154 MB | 116 ms / 0.17 s / 256 MB | 53 ms / 0.16 s / 228 MB |
| whole file | polars | 30 ms / 0.06 s / 154 MB | 159 ms / 0.24 s / 254 MB | 62 ms / 0.18 s / 201 MB |
| whole file | ours | 28 ms / 0.06 s / 154 MB | 121 ms / 0.17 s / 257 MB | 51 ms / 0.16 s / 225 MB |
| five columns | pyarrow | 7 ms / 0.02 s / 69 MB | 11 ms / 0.02 s / 67 MB | 51 ms / 0.16 s / 226 MB |
| five columns | polars | 8 ms / 0.02 s / 68 MB | 14 ms / 0.03 s / 68 MB | 60 ms / 0.18 s / 201 MB |
| five columns | ours | 9 ms / 0.03 s / 70 MB | 11 ms / 0.02 s / 66 MB | 50 ms / 0.16 s / 224 MB |
| 1,000 rows | pyarrow | 16 ms / 0.04 s / 82 MB | 88 ms / 0.15 s / 201 MB | 22 ms / 0.07 s / 119 MB |
| 1,000 rows | polars | 21 ms / 0.05 s / 79 MB | 130 ms / 0.22 s / 197 MB | 31 ms / 0.10 s / 141 MB |
| 1,000 rows | ours | 18 ms / 0.05 s / 81 MB | 90 ms / 0.15 s / 200 MB | 22 ms / 0.07 s / 122 MB |
| read + pass | pyarrow | 38 ms / 0.07 s / 158 MB | 130 ms / 0.19 s / 256 MB | 59 ms / 0.17 s / 233 MB |
| read + pass | polars | 41 ms / 0.08 s / 159 MB | 174 ms / 0.26 s / 256 MB | 69 ms / 0.19 s / 210 MB |
| read + pass | ours | 39 ms / 0.08 s / 159 MB | 134 ms / 0.19 s / 257 MB | 59 ms / 0.17 s / 232 MB |
| write, defaults | dta | 61 ms / 0.07 s / 157 MB | 204 ms / 0.29 s / 272 MB | 84 ms / 0.13 s / 298 MB |
| write, zstd 3 | dta | 70 ms / 0.10 s / 162 MB | – | 110 ms / 0.17 s / 321 MB |

### 1995_FemResp

10,847 rows, 5,754 columns; Parquet pyarrow 7.5 MB, polars 6.7 MB, ours 9.5 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 178 ms / 0.29 s / 807 MB | 1.88 s / 2.36 s / 1762 MB | 2.09 s / 2.34 s / 1375 MB |
| whole file | polars | 189 ms / 0.32 s / 806 MB | 1.96 s / 2.50 s / 1742 MB | 4.16 s / 4.42 s / 1394 MB |
| whole file | ours | 186 ms / 0.32 s / 810 MB | 1.77 s / 2.24 s / 1755 MB | 1.90 s / 2.14 s / 1374 MB |
| five columns | pyarrow | 19 ms / 0.05 s / 81 MB | 33 ms / 0.07 s / 106 MB | 1.99 s / 2.24 s / 1375 MB |
| five columns | polars | 19 ms / 0.05 s / 81 MB | 28 ms / 0.06 s / 88 MB | 4.09 s / 4.36 s / 1396 MB |
| five columns | ours | 32 ms / 0.09 s / 90 MB | 27 ms / 0.06 s / 101 MB | 1.80 s / 2.04 s / 1375 MB |
| 1,000 rows | pyarrow | 76 ms / 0.16 s / 222 MB | 1.26 s / 1.55 s / 976 MB | 309 ms / 0.48 s / 279 MB |
| 1,000 rows | polars | 88 ms / 0.20 s / 216 MB | 1.42 s / 1.72 s / 972 MB | 1.11 s / 1.29 s / 566 MB |
| 1,000 rows | ours | 85 ms / 0.19 s / 222 MB | 1.24 s / 1.50 s / 979 MB | 304 ms / 0.47 s / 292 MB |
| read + pass | pyarrow | 246 ms / 0.37 s / 818 MB | 2.04 s / 2.54 s / 1773 MB | 2.20 s / 2.52 s / 1656 MB |
| read + pass | polars | 255 ms / 0.38 s / 816 MB | 2.12 s / 2.66 s / 1751 MB | 4.30 s / 4.63 s / 1673 MB |
| read + pass | ours | 255 ms / 0.40 s / 820 MB | 1.90 s / 2.40 s / 1776 MB | 2.03 s / 2.33 s / 1654 MB |
| write, defaults | dta | 454 ms / 0.54 s / 871 MB | 1.55 s / 1.74 s / 1338 MB | 453 ms / 0.62 s / 2194 MB |
| write, zstd 3 | dta | 484 ms / 0.59 s / 874 MB | – | 1.32 s / 1.52 s / 2546 MB |

### 1995_Preg

21,332 rows, 245 columns; Parquet pyarrow 1.3 MB, polars 1.1 MB, ours 1.4 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 26 ms / 0.05 s / 168 MB | 130 ms / 0.20 s / 255 MB | 54 ms / 0.16 s / 232 MB |
| whole file | polars | 29 ms / 0.06 s / 168 MB | 155 ms / 0.25 s / 255 MB | 62 ms / 0.18 s / 222 MB |
| whole file | ours | 28 ms / 0.05 s / 169 MB | 135 ms / 0.19 s / 256 MB | 54 ms / 0.16 s / 233 MB |
| five columns | pyarrow | 7 ms / 0.02 s / 70 MB | 12 ms / 0.03 s / 67 MB | 55 ms / 0.17 s / 232 MB |
| five columns | polars | 9 ms / 0.02 s / 70 MB | 16 ms / 0.03 s / 66 MB | 61 ms / 0.18 s / 220 MB |
| five columns | ours | 9 ms / 0.02 s / 69 MB | 12 ms / 0.03 s / 66 MB | 54 ms / 0.16 s / 232 MB |
| 1,000 rows | pyarrow | 13 ms / 0.03 s / 74 MB | 89 ms / 0.14 s / 177 MB | 20 ms / 0.06 s / 116 MB |
| 1,000 rows | polars | 17 ms / 0.04 s / 75 MB | 120 ms / 0.20 s / 178 MB | 26 ms / 0.08 s / 132 MB |
| 1,000 rows | ours | 15 ms / 0.04 s / 76 MB | 102 ms / 0.15 s / 179 MB | 20 ms / 0.06 s / 116 MB |
| read + pass | pyarrow | 36 ms / 0.07 s / 171 MB | 148 ms / 0.22 s / 257 MB | 63 ms / 0.18 s / 242 MB |
| read + pass | polars | 40 ms / 0.07 s / 171 MB | 173 ms / 0.27 s / 262 MB | 70 ms / 0.19 s / 235 MB |
| read + pass | ours | 38 ms / 0.07 s / 172 MB | 155 ms / 0.22 s / 258 MB | 63 ms / 0.17 s / 242 MB |
| write, defaults | dta | 56 ms / 0.07 s / 168 MB | 195 ms / 0.29 s / 319 MB | 78 ms / 0.12 s / 333 MB |
| write, zstd 3 | dta | 62 ms / 0.09 s / 175 MB | – | 96 ms / 0.15 s / 364 MB |

### 2002_FemPreg

13,593 rows, 243 columns; Parquet pyarrow 1.0 MB, polars 0.8 MB, ours 1.1 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 21 ms / 0.05 s / 129 MB | 97 ms / 0.15 s / 177 MB | 44 ms / 0.15 s / 207 MB |
| whole file | polars | 23 ms / 0.05 s / 132 MB | 116 ms / 0.20 s / 181 MB | 50 ms / 0.16 s / 198 MB |
| whole file | ours | 22 ms / 0.05 s / 131 MB | 105 ms / 0.16 s / 181 MB | 44 ms / 0.15 s / 194 MB |
| five columns | pyarrow | 8 ms / 0.02 s / 69 MB | 11 ms / 0.02 s / 65 MB | 44 ms / 0.15 s / 207 MB |
| five columns | polars | 9 ms / 0.02 s / 67 MB | 14 ms / 0.03 s / 65 MB | 50 ms / 0.16 s / 199 MB |
| five columns | ours | 10 ms / 0.02 s / 69 MB | 11 ms / 0.02 s / 65 MB | 44 ms / 0.15 s / 194 MB |
| 1,000 rows | pyarrow | 13 ms / 0.04 s / 74 MB | 70 ms / 0.12 s / 153 MB | 20 ms / 0.06 s / 115 MB |
| 1,000 rows | polars | 16 ms / 0.04 s / 76 MB | 92 ms / 0.16 s / 157 MB | 25 ms / 0.08 s / 130 MB |
| 1,000 rows | ours | 15 ms / 0.03 s / 75 MB | 77 ms / 0.13 s / 153 MB | 21 ms / 0.06 s / 116 MB |
| read + pass | pyarrow | 33 ms / 0.06 s / 132 MB | 107 ms / 0.16 s / 178 MB | 55 ms / 0.17 s / 213 MB |
| read + pass | polars | 37 ms / 0.07 s / 134 MB | 125 ms / 0.21 s / 181 MB | 61 ms / 0.18 s / 206 MB |
| read + pass | ours | 36 ms / 0.06 s / 134 MB | 111 ms / 0.17 s / 182 MB | 55 ms / 0.17 s / 201 MB |
| write, defaults | dta | 43 ms / 0.07 s / 136 MB | 130 ms / 0.23 s / 234 MB | 62 ms / 0.13 s / 275 MB |
| write, zstd 3 | dta | 49 ms / 0.08 s / 139 MB | – | 74 ms / 0.15 s / 290 MB |

### 2002_FemResp

7,643 rows, 3,087 columns; Parquet pyarrow 3.8 MB, polars 3.4 MB, ours 4.9 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 85 ms / 0.17 s / 382 MB | 638 ms / 0.83 s / 698 MB | 460 ms / 0.67 s / 657 MB |
| whole file | polars | 92 ms / 0.19 s / 382 MB | 701 ms / 0.92 s / 701 MB | 867 ms / 1.09 s / 716 MB |
| whole file | ours | 95 ms / 0.21 s / 384 MB | 645 ms / 0.81 s / 690 MB | 453 ms / 0.66 s / 654 MB |
| five columns | pyarrow | 15 ms / 0.04 s / 76 MB | 23 ms / 0.06 s / 86 MB | 437 ms / 0.65 s / 655 MB |
| five columns | polars | 16 ms / 0.04 s / 76 MB | 27 ms / 0.06 s / 80 MB | 846 ms / 1.06 s / 716 MB |
| five columns | ours | 25 ms / 0.08 s / 83 MB | 21 ms / 0.05 s / 82 MB | 421 ms / 0.63 s / 655 MB |
| 1,000 rows | pyarrow | 48 ms / 0.13 s / 154 MB | 497 ms / 0.66 s / 440 MB | 121 ms / 0.27 s / 199 MB |
| 1,000 rows | polars | 53 ms / 0.15 s / 152 MB | 511 ms / 0.68 s / 451 MB | 298 ms / 0.46 s / 349 MB |
| 1,000 rows | ours | 55 ms / 0.15 s / 156 MB | 521 ms / 0.76 s / 506 MB | 117 ms / 0.26 s / 202 MB |
| read + pass | pyarrow | 137 ms / 0.23 s / 385 MB | 692 ms / 0.88 s / 700 MB | 502 ms / 0.73 s / 762 MB |
| read + pass | polars | 147 ms / 0.25 s / 386 MB | 746 ms / 0.98 s / 701 MB | 920 ms / 1.15 s / 824 MB |
| read + pass | ours | 147 ms / 0.26 s / 390 MB | 691 ms / 0.87 s / 692 MB | 492 ms / 0.72 s / 765 MB |
| write, defaults | dta | 201 ms / 0.28 s / 431 MB | 655 ms / 0.84 s / 595 MB | 276 ms / 0.45 s / 974 MB |
| write, zstd 3 | dta | 223 ms / 0.32 s / 433 MB | – | 622 ms / 0.81 s / 1143 MB |

### 2002_HHvars

12,571 rows, 10 columns; Parquet pyarrow 0.1 MB, polars 0.1 MB, ours 0.1 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 6 ms / 0.01 s / 66 MB | 8 ms / 0.02 s / 64 MB | 14 ms / 0.03 s / 94 MB |
| whole file | polars | 7 ms / 0.01 s / 67 MB | 11 ms / 0.03 s / 64 MB | 15 ms / 0.03 s / 94 MB |
| whole file | ours | 7 ms / 0.01 s / 66 MB | 9 ms / 0.02 s / 64 MB | 14 ms / 0.03 s / 95 MB |
| five columns | pyarrow | 6 ms / 0.01 s / 65 MB | 8 ms / 0.02 s / 59 MB | 14 ms / 0.03 s / 94 MB |
| five columns | polars | 7 ms / 0.01 s / 64 MB | 11 ms / 0.02 s / 59 MB | 15 ms / 0.03 s / 94 MB |
| five columns | ours | 7 ms / 0.01 s / 65 MB | 8 ms / 0.02 s / 59 MB | 14 ms / 0.03 s / 95 MB |
| 1,000 rows | pyarrow | 6 ms / 0.01 s / 62 MB | 9 ms / 0.02 s / 63 MB | 11 ms / 0.01 s / 79 MB |
| 1,000 rows | polars | 7 ms / 0.01 s / 63 MB | 11 ms / 0.02 s / 63 MB | 13 ms / 0.01 s / 80 MB |
| 1,000 rows | ours | 7 ms / 0.01 s / 63 MB | 9 ms / 0.02 s / 63 MB | 11 ms / 0.01 s / 79 MB |
| read + pass | pyarrow | 8 ms / 0.01 s / 69 MB | 10 ms / 0.02 s / 65 MB | 15 ms / 0.03 s / 96 MB |
| read + pass | polars | 8 ms / 0.01 s / 69 MB | 13 ms / 0.03 s / 64 MB | 16 ms / 0.03 s / 95 MB |
| read + pass | ours | 8 ms / 0.01 s / 69 MB | 10 ms / 0.02 s / 64 MB | 15 ms / 0.03 s / 96 MB |
| write, defaults | dta | 7 ms / 0.01 s / 67 MB | 15 ms / 0.04 s / 80 MB | 16 ms / 0.03 s / 100 MB |
| write, zstd 3 | dta | 8 ms / 0.02 s / 71 MB | – | 17 ms / 0.03 s / 100 MB |

### 2002_Male

4,928 rows, 1,993 columns; Parquet pyarrow 1.8 MB, polars 1.7 MB, ours 2.1 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 48 ms / 0.12 s / 257 MB | 302 ms / 0.41 s / 374 MB | 175 ms / 0.35 s / 330 MB |
| whole file | polars | 52 ms / 0.15 s / 258 MB | 313 ms / 0.44 s / 370 MB | 297 ms / 0.47 s / 400 MB |
| whole file | ours | 54 ms / 0.15 s / 261 MB | 286 ms / 0.38 s / 370 MB | 171 ms / 0.34 s / 337 MB |
| five columns | pyarrow | 13 ms / 0.04 s / 72 MB | 18 ms / 0.05 s / 77 MB | 161 ms / 0.32 s / 324 MB |
| five columns | polars | 13 ms / 0.04 s / 71 MB | 19 ms / 0.05 s / 71 MB | 282 ms / 0.45 s / 396 MB |
| five columns | ours | 18 ms / 0.06 s / 75 MB | 16 ms / 0.04 s / 75 MB | 158 ms / 0.32 s / 337 MB |
| 1,000 rows | pyarrow | 34 ms / 0.10 s / 125 MB | 229 ms / 0.34 s / 281 MB | 76 ms / 0.22 s / 169 MB |
| 1,000 rows | polars | 38 ms / 0.12 s / 127 MB | 243 ms / 0.38 s / 278 MB | 149 ms / 0.29 s / 270 MB |
| 1,000 rows | ours | 38 ms / 0.13 s / 125 MB | 213 ms / 0.32 s / 280 MB | 74 ms / 0.22 s / 176 MB |
| read + pass | pyarrow | 68 ms / 0.15 s / 261 MB | 319 ms / 0.43 s / 377 MB | 195 ms / 0.38 s / 377 MB |
| read + pass | polars | 72 ms / 0.17 s / 264 MB | 335 ms / 0.47 s / 377 MB | 318 ms / 0.51 s / 448 MB |
| read + pass | ours | 73 ms / 0.17 s / 266 MB | 306 ms / 0.41 s / 371 MB | 193 ms / 0.37 s / 388 MB |
| write, defaults | dta | 94 ms / 0.16 s / 267 MB | 330 ms / 0.51 s / 419 MB | 134 ms / 0.27 s / 611 MB |
| write, zstd 3 | dta | 106 ms / 0.18 s / 269 MB | – | 292 ms / 0.44 s / 704 MB |

### 2002_curr_ins

12,571 rows, 3 columns; Parquet pyarrow 0.1 MB, polars 0.0 MB, ours 0.1 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 6 ms / 0.01 s / 63 MB | 5 ms / 0.01 s / 58 MB | 12 ms / 0.02 s / 84 MB |
| whole file | polars | 6 ms / 0.01 s / 60 MB | 7 ms / 0.01 s / 58 MB | 13 ms / 0.02 s / 83 MB |
| whole file | ours | 6 ms / 0.01 s / 60 MB | 5 ms / 0.01 s / 58 MB | 12 ms / 0.02 s / 83 MB |
| five columns | pyarrow | 6 ms / 0.01 s / 63 MB | 6 ms / 0.01 s / 58 MB | 12 ms / 0.02 s / 83 MB |
| five columns | polars | 6 ms / 0.01 s / 61 MB | 8 ms / 0.02 s / 58 MB | 13 ms / 0.02 s / 84 MB |
| five columns | ours | 6 ms / 0.01 s / 61 MB | 6 ms / 0.01 s / 58 MB | 12 ms / 0.02 s / 84 MB |
| 1,000 rows | pyarrow | 5 ms / 0.01 s / 60 MB | 6 ms / 0.01 s / 58 MB | 11 ms / 0.01 s / 79 MB |
| 1,000 rows | polars | 6 ms / 0.01 s / 60 MB | 8 ms / 0.02 s / 58 MB | 12 ms / 0.01 s / 79 MB |
| 1,000 rows | ours | 6 ms / 0.01 s / 60 MB | 6 ms / 0.01 s / 58 MB | 11 ms / 0.01 s / 79 MB |
| read + pass | pyarrow | 6 ms / 0.01 s / 65 MB | 5 ms / 0.01 s / 58 MB | 12 ms / 0.02 s / 84 MB |
| read + pass | polars | 7 ms / 0.01 s / 63 MB | 8 ms / 0.02 s / 58 MB | 13 ms / 0.02 s / 84 MB |
| read + pass | ours | 7 ms / 0.01 s / 62 MB | 5 ms / 0.01 s / 58 MB | 12 ms / 0.02 s / 84 MB |
| write, defaults | dta | 5 ms / 0.01 s / 65 MB | 9 ms / 0.02 s / 76 MB | 11 ms / 0.02 s / 94 MB |
| write, zstd 3 | dta | 6 ms / 0.01 s / 68 MB | – | 13 ms / 0.02 s / 94 MB |

### 2002_hhpartypnew

12,571 rows, 3 columns; Parquet pyarrow 0.1 MB, polars 0.0 MB, ours 0.1 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 5 ms / 0.01 s / 60 MB | 5 ms / 0.01 s / 58 MB | 12 ms / 0.02 s / 84 MB |
| whole file | polars | 6 ms / 0.01 s / 61 MB | 7 ms / 0.02 s / 58 MB | 13 ms / 0.01 s / 80 MB |
| whole file | ours | 6 ms / 0.01 s / 61 MB | 5 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 80 MB |
| five columns | pyarrow | 6 ms / 0.01 s / 61 MB | 6 ms / 0.01 s / 58 MB | 12 ms / 0.02 s / 84 MB |
| five columns | polars | 6 ms / 0.01 s / 61 MB | 8 ms / 0.02 s / 58 MB | 13 ms / 0.01 s / 80 MB |
| five columns | ours | 6 ms / 0.01 s / 60 MB | 6 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 80 MB |
| 1,000 rows | pyarrow | 5 ms / 0.01 s / 60 MB | 6 ms / 0.01 s / 58 MB | 11 ms / 0.01 s / 79 MB |
| 1,000 rows | polars | 6 ms / 0.01 s / 60 MB | 8 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 79 MB |
| 1,000 rows | ours | 6 ms / 0.01 s / 60 MB | 6 ms / 0.01 s / 58 MB | 11 ms / 0.01 s / 79 MB |
| read + pass | pyarrow | 6 ms / 0.01 s / 62 MB | 5 ms / 0.01 s / 58 MB | 12 ms / 0.02 s / 84 MB |
| read + pass | polars | 7 ms / 0.01 s / 62 MB | 7 ms / 0.01 s / 58 MB | 13 ms / 0.01 s / 80 MB |
| read + pass | ours | 7 ms / 0.01 s / 63 MB | 5 ms / 0.01 s / 58 MB | 12 ms / 0.01 s / 80 MB |
| write, defaults | dta | 5 ms / 0.01 s / 65 MB | 8 ms / 0.02 s / 75 MB | 11 ms / 0.02 s / 93 MB |
| write, zstd 3 | dta | 6 ms / 0.01 s / 65 MB | – | 13 ms / 0.02 s / 94 MB |

### 2006_2010_FemPreg

20,492 rows, 287 columns; Parquet pyarrow 1.7 MB, polars 1.4 MB, ours 1.7 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 29 ms / 0.06 s / 181 MB | 150 ms / 0.23 s / 284 MB | 63 ms / 0.18 s / 252 MB |
| whole file | polars | 31 ms / 0.07 s / 184 MB | 175 ms / 0.28 s / 277 MB | 71 ms / 0.20 s / 260 MB |
| whole file | ours | 31 ms / 0.06 s / 184 MB | 160 ms / 0.23 s / 285 MB | 61 ms / 0.17 s / 260 MB |
| five columns | pyarrow | 9 ms / 0.02 s / 69 MB | 13 ms / 0.03 s / 68 MB | 60 ms / 0.17 s / 249 MB |
| five columns | polars | 9 ms / 0.02 s / 68 MB | 16 ms / 0.03 s / 68 MB | 68 ms / 0.19 s / 251 MB |
| five columns | ours | 10 ms / 0.02 s / 71 MB | 12 ms / 0.03 s / 67 MB | 60 ms / 0.17 s / 259 MB |
| 1,000 rows | pyarrow | 14 ms / 0.04 s / 77 MB | 106 ms / 0.18 s / 206 MB | 21 ms / 0.07 s / 123 MB |
| 1,000 rows | polars | 17 ms / 0.05 s / 78 MB | 136 ms / 0.24 s / 205 MB | 28 ms / 0.09 s / 138 MB |
| 1,000 rows | ours | 16 ms / 0.04 s / 78 MB | 126 ms / 0.21 s / 223 MB | 25 ms / 0.08 s / 132 MB |
| read + pass | pyarrow | 42 ms / 0.08 s / 187 MB | 179 ms / 0.27 s / 283 MB | 74 ms / 0.20 s / 268 MB |
| read + pass | polars | 43 ms / 0.08 s / 187 MB | 196 ms / 0.31 s / 278 MB | 83 ms / 0.21 s / 274 MB |
| read + pass | ours | 43 ms / 0.08 s / 186 MB | 185 ms / 0.26 s / 293 MB | 75 ms / 0.19 s / 277 MB |
| write, defaults | dta | 64 ms / 0.09 s / 186 MB | 221 ms / 0.34 s / 352 MB | 93 ms / 0.15 s / 388 MB |
| write, zstd 3 | dta | 71 ms / 0.11 s / 193 MB | – | 111 ms / 0.18 s / 428 MB |

### 2006_2010_FemResp

12,279 rows, 3,741 columns; Parquet pyarrow 6.8 MB, polars 5.8 MB, ours 8.1 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 139 ms / 0.24 s / 574 MB | 1.15 s / 1.36 s / 1127 MB | 1.06 s / 1.29 s / 1030 MB |
| whole file | polars | 148 ms / 0.26 s / 574 MB | 1.26 s / 1.50 s / 1114 MB | 1.93 s / 2.18 s / 1026 MB |
| whole file | ours | 149 ms / 0.27 s / 578 MB | 1.20 s / 1.39 s / 1127 MB | 1.06 s / 1.29 s / 1038 MB |
| five columns | pyarrow | 15 ms / 0.04 s / 78 MB | 25 ms / 0.06 s / 86 MB | 1.02 s / 1.26 s / 1024 MB |
| five columns | polars | 15 ms / 0.04 s / 76 MB | 29 ms / 0.07 s / 84 MB | 1.93 s / 2.17 s / 1019 MB |
| five columns | ours | 25 ms / 0.08 s / 84 MB | 26 ms / 0.06 s / 89 MB | 1.01 s / 1.24 s / 1033 MB |
| 1,000 rows | pyarrow | 62 ms / 0.14 s / 172 MB | 848 ms / 1.09 s / 689 MB | 165 ms / 0.34 s / 216 MB |
| 1,000 rows | polars | 71 ms / 0.17 s / 172 MB | 890 ms / 1.18 s / 697 MB | 463 ms / 0.64 s / 422 MB |
| 1,000 rows | ours | 68 ms / 0.17 s / 177 MB | 831 ms / 1.05 s / 690 MB | 160 ms / 0.32 s / 221 MB |
| read + pass | pyarrow | 204 ms / 0.30 s / 580 MB | 1.28 s / 1.50 s / 1138 MB | 1.15 s / 1.42 s / 1202 MB |
| read + pass | polars | 213 ms / 0.33 s / 579 MB | 1.38 s / 1.62 s / 1122 MB | 2.03 s / 2.32 s / 1201 MB |
| read + pass | ours | 213 ms / 0.34 s / 584 MB | 1.33 s / 1.54 s / 1140 MB | 1.15 s / 1.42 s / 1216 MB |
| write, defaults | dta | 372 ms / 0.46 s / 634 MB | 1.23 s / 1.43 s / 973 MB | 444 ms / 0.60 s / 1600 MB |
| write, zstd 3 | dta | 405 ms / 0.51 s / 634 MB | – | 746 ms / 0.93 s / 1866 MB |

### 2006_2010_Male

10,403 rows, 2,801 columns; Parquet pyarrow 3.8 MB, polars 3.3 MB, ours 4.3 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 92 ms / 0.19 s / 464 MB | 800 ms / 1.01 s / 888 MB | 542 ms / 0.78 s / 726 MB |
| whole file | polars | 100 ms / 0.21 s / 464 MB | 863 ms / 1.13 s / 876 MB | 950 ms / 1.20 s / 694 MB |
| whole file | ours | 99 ms / 0.22 s / 465 MB | 784 ms / 0.98 s / 888 MB | 536 ms / 0.78 s / 785 MB |
| five columns | pyarrow | 13 ms / 0.04 s / 74 MB | 23 ms / 0.06 s / 79 MB | 516 ms / 0.75 s / 719 MB |
| five columns | polars | 13 ms / 0.04 s / 76 MB | 24 ms / 0.06 s / 80 MB | 925 ms / 1.17 s / 691 MB |
| five columns | ours | 22 ms / 0.07 s / 80 MB | 24 ms / 0.06 s / 83 MB | 520 ms / 0.75 s / 785 MB |
| 1,000 rows | pyarrow | 45 ms / 0.12 s / 147 MB | 602 ms / 0.83 s / 545 MB | 119 ms / 0.29 s / 193 MB |
| 1,000 rows | polars | 51 ms / 0.14 s / 146 MB | 593 ms / 0.85 s / 560 MB | 261 ms / 0.43 s / 331 MB |
| 1,000 rows | ours | 52 ms / 0.15 s / 149 MB | 608 ms / 0.83 s / 547 MB | 116 ms / 0.28 s / 184 MB |
| read + pass | pyarrow | 137 ms / 0.24 s / 472 MB | 880 ms / 1.10 s / 902 MB | 585 ms / 0.85 s / 854 MB |
| read + pass | polars | 145 ms / 0.25 s / 471 MB | 913 ms / 1.15 s / 878 MB | 986 ms / 1.24 s / 827 MB |
| read + pass | ours | 145 ms / 0.27 s / 474 MB | 841 ms / 1.03 s / 899 MB | 562 ms / 0.80 s / 915 MB |
| write, defaults | dta | 219 ms / 0.30 s / 498 MB | 800 ms / 0.99 s / 719 MB | 234 ms / 0.37 s / 1106 MB |
| write, zstd 3 | dta | 238 ms / 0.33 s / 502 MB | – | 443 ms / 0.61 s / 1265 MB |

### 2011_2013_FemPreg

9,543 rows, 278 columns; Parquet pyarrow 0.8 MB, polars 0.7 MB, ours 0.8 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 19 ms / 0.04 s / 119 MB | 73 ms / 0.12 s / 166 MB | 42 ms / 0.15 s / 187 MB |
| whole file | polars | 23 ms / 0.06 s / 120 MB | 88 ms / 0.15 s / 167 MB | 46 ms / 0.15 s / 181 MB |
| whole file | ours | 20 ms / 0.04 s / 119 MB | 78 ms / 0.13 s / 167 MB | 39 ms / 0.14 s / 190 MB |
| five columns | pyarrow | 7 ms / 0.02 s / 66 MB | 10 ms / 0.02 s / 62 MB | 40 ms / 0.14 s / 189 MB |
| five columns | polars | 8 ms / 0.02 s / 68 MB | 13 ms / 0.03 s / 63 MB | 45 ms / 0.15 s / 183 MB |
| five columns | ours | 9 ms / 0.02 s / 67 MB | 10 ms / 0.02 s / 62 MB | 39 ms / 0.14 s / 190 MB |
| 1,000 rows | pyarrow | 13 ms / 0.04 s / 76 MB | 55 ms / 0.10 s / 131 MB | 20 ms / 0.06 s / 121 MB |
| 1,000 rows | polars | 14 ms / 0.04 s / 77 MB | 72 ms / 0.13 s / 133 MB | 26 ms / 0.09 s / 134 MB |
| 1,000 rows | ours | 14 ms / 0.03 s / 74 MB | 58 ms / 0.11 s / 135 MB | 20 ms / 0.07 s / 123 MB |
| read + pass | pyarrow | 29 ms / 0.06 s / 123 MB | 82 ms / 0.13 s / 166 MB | 49 ms / 0.16 s / 198 MB |
| read + pass | polars | 32 ms / 0.07 s / 124 MB | 97 ms / 0.16 s / 166 MB | 56 ms / 0.17 s / 192 MB |
| read + pass | ours | 30 ms / 0.06 s / 121 MB | 86 ms / 0.14 s / 167 MB | 49 ms / 0.16 s / 199 MB |
| write, defaults | dta | 36 ms / 0.06 s / 121 MB | 116 ms / 0.21 s / 217 MB | 55 ms / 0.12 s / 267 MB |
| write, zstd 3 | dta | 41 ms / 0.07 s / 128 MB | – | 66 ms / 0.15 s / 285 MB |

### 2011_2013_FemResp

5,601 rows, 3,094 columns; Parquet pyarrow 3.7 MB, polars 3.4 MB, ours 4.3 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 76 ms / 0.16 s / 326 MB | 510 ms / 0.71 s / 542 MB | 415 ms / 0.65 s / 487 MB |
| whole file | polars | 81 ms / 0.18 s / 326 MB | 699 ms / 0.98 s / 537 MB | 809 ms / 1.06 s / 596 MB |
| whole file | ours | 82 ms / 0.19 s / 330 MB | 594 ms / 0.86 s / 548 MB | 434 ms / 0.69 s / 512 MB |
| five columns | pyarrow | 14 ms / 0.04 s / 75 MB | 29 ms / 0.07 s / 83 MB | 405 ms / 0.64 s / 490 MB |
| five columns | polars | 14 ms / 0.04 s / 75 MB | 27 ms / 0.07 s / 75 MB | 751 ms / 0.97 s / 593 MB |
| five columns | ours | 21 ms / 0.08 s / 81 MB | 23 ms / 0.05 s / 79 MB | 384 ms / 0.59 s / 511 MB |
| 1,000 rows | pyarrow | 49 ms / 0.13 s / 153 MB | 506 ms / 0.62 s / 360 MB | 143 ms / 0.30 s / 205 MB |
| 1,000 rows | polars | 56 ms / 0.15 s / 152 MB | 587 ms / 0.67 s / 366 MB | 551 ms / 0.53 s / 358 MB |
| 1,000 rows | ours | 55 ms / 0.16 s / 155 MB | 586 ms / 0.61 s / 353 MB | 140 ms / 0.29 s / 208 MB |
| read + pass | pyarrow | 105 ms / 0.19 s / 332 MB | 569 ms / 0.79 s / 580 MB | 441 ms / 0.66 s / 568 MB |
| read + pass | polars | 112 ms / 0.22 s / 333 MB | 652 ms / 0.88 s / 552 MB | 857 ms / 1.09 s / 675 MB |
| read + pass | ours | 113 ms / 0.23 s / 336 MB | 576 ms / 0.78 s / 552 MB | 437 ms / 0.64 s / 591 MB |
| write, defaults | dta | 180 ms / 0.27 s / 333 MB | 601 ms / 0.78 s / 484 MB | 304 ms / 0.49 s / 864 MB |
| write, zstd 3 | dta | 203 ms / 0.32 s / 333 MB | – | 744 ms / 0.94 s / 1033 MB |

### 2011_2013_Male

4,815 rows, 3,059 columns; Parquet pyarrow 2.4 MB, polars 2.3 MB, ours 2.9 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 62 ms / 0.14 s / 319 MB | 441 ms / 0.58 s / 507 MB | 331 ms / 0.52 s / 439 MB |
| whole file | polars | 68 ms / 0.16 s / 319 MB | 475 ms / 0.61 s / 505 MB | 665 ms / 0.89 s / 552 MB |
| whole file | ours | 70 ms / 0.18 s / 321 MB | 463 ms / 0.62 s / 511 MB | 329 ms / 0.51 s / 440 MB |
| five columns | pyarrow | 13 ms / 0.04 s / 73 MB | 22 ms / 0.05 s / 83 MB | 303 ms / 0.50 s / 437 MB |
| five columns | polars | 14 ms / 0.04 s / 74 MB | 21 ms / 0.05 s / 78 MB | 631 ms / 0.83 s / 549 MB |
| five columns | ours | 20 ms / 0.07 s / 80 MB | 18 ms / 0.04 s / 79 MB | 302 ms / 0.47 s / 437 MB |
| 1,000 rows | pyarrow | 43 ms / 0.12 s / 150 MB | 338 ms / 0.47 s / 355 MB | 125 ms / 0.29 s / 202 MB |
| 1,000 rows | polars | 50 ms / 0.14 s / 149 MB | 373 ms / 0.53 s / 358 MB | 300 ms / 0.46 s / 351 MB |
| 1,000 rows | ours | 49 ms / 0.15 s / 151 MB | 330 ms / 0.45 s / 353 MB | 119 ms / 0.27 s / 196 MB |
| read + pass | pyarrow | 88 ms / 0.17 s / 323 MB | 500 ms / 0.68 s / 510 MB | 359 ms / 0.56 s / 510 MB |
| read + pass | polars | 93 ms / 0.19 s / 321 MB | 524 ms / 0.71 s / 506 MB | 675 ms / 0.90 s / 626 MB |
| read + pass | ours | 97 ms / 0.21 s / 325 MB | 513 ms / 0.73 s / 537 MB | 367 ms / 0.60 s / 512 MB |
| write, defaults | dta | 136 ms / 0.22 s / 349 MB | 502 ms / 0.72 s / 458 MB | 213 ms / 0.40 s / 764 MB |
| write, zstd 3 | dta | 147 ms / 0.25 s / 350 MB | – | 599 ms / 0.79 s / 912 MB |

### 2011_2019_FemaleWgt

22,995 rows, 7 columns; Parquet pyarrow 1.0 MB, polars 0.7 MB, ours 0.8 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 7 ms / 0.01 s / 69 MB | 15 ms / 0.03 s / 75 MB | 15 ms / 0.03 s / 97 MB |
| whole file | polars | 8 ms / 0.01 s / 68 MB | 22 ms / 0.04 s / 75 MB | 16 ms / 0.03 s / 97 MB |
| whole file | ours | 7 ms / 0.01 s / 65 MB | 13 ms / 0.02 s / 74 MB | 14 ms / 0.02 s / 96 MB |
| five columns | pyarrow | 7 ms / 0.01 s / 68 MB | 13 ms / 0.03 s / 70 MB | 15 ms / 0.03 s / 97 MB |
| five columns | polars | 8 ms / 0.01 s / 67 MB | 20 ms / 0.04 s / 70 MB | 16 ms / 0.03 s / 97 MB |
| five columns | ours | 7 ms / 0.01 s / 64 MB | 12 ms / 0.02 s / 70 MB | 14 ms / 0.02 s / 96 MB |
| 1,000 rows | pyarrow | 6 ms / 0.01 s / 65 MB | 12 ms / 0.02 s / 70 MB | 12 ms / 0.01 s / 82 MB |
| 1,000 rows | polars | 8 ms / 0.01 s / 66 MB | 22 ms / 0.04 s / 72 MB | 15 ms / 0.02 s / 82 MB |
| 1,000 rows | ours | 6 ms / 0.01 s / 61 MB | 12 ms / 0.02 s / 71 MB | 11 ms / 0.01 s / 81 MB |
| read + pass | pyarrow | 8 ms / 0.01 s / 71 MB | 15 ms / 0.03 s / 75 MB | 16 ms / 0.03 s / 102 MB |
| read + pass | polars | 9 ms / 0.02 s / 72 MB | 24 ms / 0.04 s / 75 MB | 18 ms / 0.03 s / 100 MB |
| read + pass | ours | 8 ms / 0.01 s / 69 MB | 15 ms / 0.03 s / 74 MB | 16 ms / 0.03 s / 100 MB |
| write, defaults | dta | 7 ms / 0.02 s / 69 MB | 20 ms / 0.04 s / 98 MB | 18 ms / 0.03 s / 110 MB |
| write, zstd 3 | dta | 12 ms / 0.03 s / 76 MB | – | 22 ms / 0.04 s / 112 MB |

### 2011_2019_MaleWgt

19,067 rows, 7 columns; Parquet pyarrow 0.8 MB, polars 0.6 MB, ours 0.7 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 7 ms / 0.01 s / 68 MB | 12 ms / 0.03 s / 71 MB | 15 ms / 0.03 s / 97 MB |
| whole file | polars | 8 ms / 0.01 s / 68 MB | 20 ms / 0.04 s / 71 MB | 16 ms / 0.03 s / 95 MB |
| whole file | ours | 7 ms / 0.01 s / 64 MB | 11 ms / 0.02 s / 70 MB | 14 ms / 0.02 s / 95 MB |
| five columns | pyarrow | 7 ms / 0.01 s / 66 MB | 12 ms / 0.03 s / 68 MB | 16 ms / 0.03 s / 97 MB |
| five columns | polars | 7 ms / 0.01 s / 66 MB | 19 ms / 0.04 s / 66 MB | 16 ms / 0.03 s / 95 MB |
| five columns | ours | 7 ms / 0.01 s / 63 MB | 11 ms / 0.02 s / 66 MB | 14 ms / 0.02 s / 95 MB |
| 1,000 rows | pyarrow | 6 ms / 0.01 s / 63 MB | 12 ms / 0.02 s / 68 MB | 12 ms / 0.01 s / 81 MB |
| 1,000 rows | polars | 7 ms / 0.01 s / 64 MB | 19 ms / 0.04 s / 67 MB | 14 ms / 0.01 s / 82 MB |
| 1,000 rows | ours | 6 ms / 0.01 s / 61 MB | 10 ms / 0.02 s / 67 MB | 11 ms / 0.01 s / 81 MB |
| read + pass | pyarrow | 8 ms / 0.01 s / 68 MB | 14 ms / 0.03 s / 71 MB | 17 ms / 0.03 s / 101 MB |
| read + pass | polars | 9 ms / 0.01 s / 69 MB | 21 ms / 0.04 s / 71 MB | 18 ms / 0.03 s / 101 MB |
| read + pass | ours | 8 ms / 0.01 s / 67 MB | 12 ms / 0.02 s / 70 MB | 16 ms / 0.03 s / 100 MB |
| write, defaults | dta | 7 ms / 0.02 s / 68 MB | 16 ms / 0.03 s / 90 MB | 16 ms / 0.03 s / 109 MB |
| write, zstd 3 | dta | 11 ms / 0.03 s / 74 MB | – | 20 ms / 0.04 s / 110 MB |

### 2013_2015_FemPreg

9,358 rows, 278 columns; Parquet pyarrow 0.8 MB, polars 0.7 MB, ours 0.8 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 24 ms / 0.06 s / 118 MB | 73 ms / 0.12 s / 167 MB | 41 ms / 0.15 s / 190 MB |
| whole file | polars | 28 ms / 0.07 s / 120 MB | 91 ms / 0.15 s / 167 MB | 46 ms / 0.15 s / 178 MB |
| whole file | ours | 27 ms / 0.06 s / 118 MB | 78 ms / 0.14 s / 168 MB | 46 ms / 0.16 s / 192 MB |
| five columns | pyarrow | 10 ms / 0.02 s / 67 MB | 12 ms / 0.03 s / 63 MB | 42 ms / 0.15 s / 188 MB |
| five columns | polars | 11 ms / 0.02 s / 66 MB | 14 ms / 0.04 s / 63 MB | 50 ms / 0.17 s / 186 MB |
| five columns | ours | 10 ms / 0.02 s / 67 MB | 10 ms / 0.03 s / 63 MB | 42 ms / 0.16 s / 193 MB |
| 1,000 rows | pyarrow | 14 ms / 0.05 s / 76 MB | 55 ms / 0.10 s / 131 MB | 21 ms / 0.07 s / 124 MB |
| 1,000 rows | polars | 16 ms / 0.05 s / 77 MB | 70 ms / 0.13 s / 135 MB | 26 ms / 0.09 s / 136 MB |
| 1,000 rows | ours | 15 ms / 0.04 s / 75 MB | 59 ms / 0.11 s / 135 MB | 20 ms / 0.06 s / 121 MB |
| read + pass | pyarrow | 34 ms / 0.08 s / 120 MB | 83 ms / 0.13 s / 166 MB | 50 ms / 0.16 s / 197 MB |
| read + pass | polars | 35 ms / 0.08 s / 122 MB | 101 ms / 0.16 s / 167 MB | 58 ms / 0.18 s / 198 MB |
| read + pass | ours | 35 ms / 0.07 s / 121 MB | 85 ms / 0.15 s / 167 MB | 50 ms / 0.16 s / 201 MB |
| write, defaults | dta | 36 ms / 0.06 s / 121 MB | 113 ms / 0.20 s / 217 MB | 54 ms / 0.12 s / 264 MB |
| write, zstd 3 | dta | 41 ms / 0.07 s / 126 MB | – | 66 ms / 0.15 s / 278 MB |

### 2013_2015_FemResp

5,699 rows, 3,207 columns; Parquet pyarrow 3.8 MB, polars 3.4 MB, ours 4.7 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 80 ms / 0.17 s / 331 MB | 555 ms / 0.80 s / 555 MB | 442 ms / 0.68 s / 500 MB |
| whole file | polars | 87 ms / 0.20 s / 331 MB | 613 ms / 0.82 s / 535 MB | 837 ms / 1.09 s / 611 MB |
| whole file | ours | 86 ms / 0.20 s / 335 MB | 574 ms / 0.81 s / 560 MB | 439 ms / 0.69 s / 561 MB |
| five columns | pyarrow | 14 ms / 0.04 s / 76 MB | 26 ms / 0.07 s / 83 MB | 404 ms / 0.62 s / 500 MB |
| five columns | polars | 14 ms / 0.04 s / 76 MB | 24 ms / 0.06 s / 79 MB | 811 ms / 1.05 s / 611 MB |
| five columns | ours | 22 ms / 0.08 s / 82 MB | 37 ms / 0.06 s / 80 MB | 424 ms / 0.66 s / 565 MB |
| 1,000 rows | pyarrow | 50 ms / 0.12 s / 155 MB | 474 ms / 0.72 s / 379 MB | 160 ms / 0.35 s / 209 MB |
| 1,000 rows | polars | 57 ms / 0.15 s / 153 MB | 518 ms / 0.76 s / 356 MB | 367 ms / 0.58 s / 366 MB |
| 1,000 rows | ours | 57 ms / 0.16 s / 157 MB | 550 ms / 0.67 s / 375 MB | 147 ms / 0.34 s / 202 MB |
| read + pass | pyarrow | 127 ms / 0.22 s / 336 MB | 602 ms / 0.88 s / 564 MB | 482 ms / 0.76 s / 589 MB |
| read + pass | polars | 135 ms / 0.24 s / 335 MB | 673 ms / 0.87 s / 542 MB | 857 ms / 1.08 s / 695 MB |
| read + pass | ours | 136 ms / 0.25 s / 339 MB | 588 ms / 0.78 s / 555 MB | 464 ms / 0.69 s / 646 MB |
| write, defaults | dta | 194 ms / 0.30 s / 375 MB | 632 ms / 0.86 s / 500 MB | 311 ms / 0.49 s / 890 MB |
| write, zstd 3 | dta | 224 ms / 0.35 s / 378 MB | – | 799 ms / 1.02 s / 1065 MB |

### 2013_2015_Male

4,506 rows, 2,940 columns; Parquet pyarrow 2.3 MB, polars 2.2 MB, ours 2.9 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 65 ms / 0.15 s / 311 MB | 420 ms / 0.56 s / 498 MB | 321 ms / 0.51 s / 424 MB |
| whole file | polars | 75 ms / 0.17 s / 312 MB | 461 ms / 0.63 s / 495 MB | 629 ms / 0.83 s / 535 MB |
| whole file | ours | 81 ms / 0.18 s / 315 MB | 424 ms / 0.63 s / 512 MB | 322 ms / 0.52 s / 458 MB |
| five columns | pyarrow | 14 ms / 0.04 s / 72 MB | 23 ms / 0.06 s / 82 MB | 293 ms / 0.48 s / 421 MB |
| five columns | polars | 17 ms / 0.04 s / 74 MB | 23 ms / 0.06 s / 77 MB | 603 ms / 0.81 s / 531 MB |
| five columns | ours | 23 ms / 0.08 s / 80 MB | 21 ms / 0.05 s / 79 MB | 290 ms / 0.48 s / 455 MB |
| 1,000 rows | pyarrow | 49 ms / 0.12 s / 146 MB | 326 ms / 0.46 s / 348 MB | 126 ms / 0.30 s / 200 MB |
| 1,000 rows | polars | 53 ms / 0.14 s / 145 MB | 352 ms / 0.51 s / 349 MB | 317 ms / 0.51 s / 342 MB |
| 1,000 rows | ours | 54 ms / 0.16 s / 149 MB | 337 ms / 0.48 s / 350 MB | 131 ms / 0.29 s / 188 MB |
| read + pass | pyarrow | 94 ms / 0.18 s / 316 MB | 468 ms / 0.62 s / 502 MB | 355 ms / 0.59 s / 492 MB |
| read + pass | polars | 102 ms / 0.20 s / 316 MB | 494 ms / 0.68 s / 501 MB | 664 ms / 0.91 s / 599 MB |
| read + pass | ours | 103 ms / 0.22 s / 317 MB | 438 ms / 0.62 s / 517 MB | 334 ms / 0.53 s / 523 MB |
| write, defaults | dta | 125 ms / 0.21 s / 336 MB | 446 ms / 0.61 s / 503 MB | 192 ms / 0.36 s / 798 MB |
| write, zstd 3 | dta | 141 ms / 0.24 s / 337 MB | – | 577 ms / 0.75 s / 940 MB |

### 2015_2017_FemPreg

9,553 rows, 248 columns; Parquet pyarrow 0.6 MB, polars 0.5 MB, ours 0.6 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 17 ms / 0.04 s / 110 MB | 71 ms / 0.12 s / 161 MB | 37 ms / 0.14 s / 183 MB |
| whole file | polars | 19 ms / 0.04 s / 113 MB | 92 ms / 0.16 s / 162 MB | 44 ms / 0.15 s / 173 MB |
| whole file | ours | 19 ms / 0.04 s / 111 MB | 73 ms / 0.12 s / 160 MB | 38 ms / 0.14 s / 187 MB |
| five columns | pyarrow | 7 ms / 0.02 s / 66 MB | 11 ms / 0.03 s / 63 MB | 37 ms / 0.14 s / 183 MB |
| five columns | polars | 8 ms / 0.01 s / 67 MB | 12 ms / 0.03 s / 62 MB | 42 ms / 0.15 s / 171 MB |
| five columns | ours | 9 ms / 0.02 s / 68 MB | 10 ms / 0.02 s / 63 MB | 38 ms / 0.14 s / 186 MB |
| 1,000 rows | pyarrow | 11 ms / 0.03 s / 73 MB | 54 ms / 0.11 s / 130 MB | 20 ms / 0.06 s / 119 MB |
| 1,000 rows | polars | 14 ms / 0.04 s / 74 MB | 64 ms / 0.13 s / 130 MB | 25 ms / 0.08 s / 128 MB |
| 1,000 rows | ours | 13 ms / 0.03 s / 74 MB | 59 ms / 0.10 s / 129 MB | 19 ms / 0.06 s / 119 MB |
| read + pass | pyarrow | 26 ms / 0.05 s / 116 MB | 76 ms / 0.13 s / 159 MB | 48 ms / 0.16 s / 192 MB |
| read + pass | polars | 28 ms / 0.06 s / 116 MB | 88 ms / 0.16 s / 160 MB | 53 ms / 0.17 s / 181 MB |
| read + pass | ours | 30 ms / 0.06 s / 115 MB | 80 ms / 0.13 s / 160 MB | 48 ms / 0.16 s / 195 MB |
| write, defaults | dta | 33 ms / 0.05 s / 118 MB | 102 ms / 0.18 s / 207 MB | 49 ms / 0.11 s / 248 MB |
| write, zstd 3 | dta | 38 ms / 0.07 s / 121 MB | – | 59 ms / 0.14 s / 264 MB |

### 2015_2017_FemResp

5,554 rows, 3,024 columns; Parquet pyarrow 3.4 MB, polars 3.1 MB, ours 4.3 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 71 ms / 0.14 s / 322 MB | 488 ms / 0.67 s / 533 MB | 384 ms / 0.56 s / 475 MB |
| whole file | polars | 78 ms / 0.17 s / 322 MB | 546 ms / 0.75 s / 530 MB | 740 ms / 0.93 s / 577 MB |
| whole file | ours | 79 ms / 0.18 s / 325 MB | 490 ms / 0.67 s / 534 MB | 380 ms / 0.57 s / 534 MB |
| five columns | pyarrow | 13 ms / 0.04 s / 74 MB | 20 ms / 0.04 s / 83 MB | 352 ms / 0.53 s / 470 MB |
| five columns | polars | 14 ms / 0.04 s / 74 MB | 22 ms / 0.05 s / 79 MB | 726 ms / 0.91 s / 576 MB |
| five columns | ours | 21 ms / 0.07 s / 81 MB | 18 ms / 0.04 s / 82 MB | 352 ms / 0.53 s / 532 MB |
| 1,000 rows | pyarrow | 46 ms / 0.11 s / 154 MB | 384 ms / 0.54 s / 350 MB | 121 ms / 0.27 s / 196 MB |
| 1,000 rows | polars | 54 ms / 0.14 s / 150 MB | 438 ms / 0.61 s / 379 MB | 303 ms / 0.46 s / 349 MB |
| 1,000 rows | ours | 53 ms / 0.14 s / 154 MB | 378 ms / 0.51 s / 352 MB | 119 ms / 0.27 s / 190 MB |
| read + pass | pyarrow | 120 ms / 0.20 s / 325 MB | 518 ms / 0.72 s / 532 MB | 413 ms / 0.61 s / 554 MB |
| read + pass | polars | 126 ms / 0.22 s / 325 MB | 587 ms / 0.79 s / 531 MB | 767 ms / 0.97 s / 658 MB |
| read + pass | ours | 128 ms / 0.23 s / 328 MB | 537 ms / 0.71 s / 530 MB | 410 ms / 0.62 s / 614 MB |
| write, defaults | dta | 176 ms / 0.26 s / 359 MB | 626 ms / 0.81 s / 477 MB | 291 ms / 0.46 s / 842 MB |
| write, zstd 3 | dta | 197 ms / 0.30 s / 359 MB | – | 703 ms / 0.89 s / 1007 MB |

### 2015_2017_Male

4,540 rows, 2,945 columns; Parquet pyarrow 2.1 MB, polars 2.1 MB, ours 2.8 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 60 ms / 0.13 s / 314 MB | 420 ms / 0.54 s / 492 MB | 320 ms / 0.51 s / 426 MB |
| whole file | polars | 62 ms / 0.15 s / 313 MB | 454 ms / 0.60 s / 492 MB | 636 ms / 0.82 s / 535 MB |
| whole file | ours | 64 ms / 0.16 s / 314 MB | 403 ms / 0.59 s / 520 MB | 315 ms / 0.49 s / 456 MB |
| five columns | pyarrow | 13 ms / 0.04 s / 73 MB | 22 ms / 0.05 s / 82 MB | 283 ms / 0.45 s / 422 MB |
| five columns | polars | 13 ms / 0.04 s / 73 MB | 22 ms / 0.05 s / 77 MB | 604 ms / 0.78 s / 530 MB |
| five columns | ours | 20 ms / 0.07 s / 79 MB | 17 ms / 0.04 s / 78 MB | 282 ms / 0.45 s / 457 MB |
| 1,000 rows | pyarrow | 40 ms / 0.11 s / 149 MB | 326 ms / 0.45 s / 342 MB | 119 ms / 0.27 s / 192 MB |
| 1,000 rows | polars | 45 ms / 0.13 s / 148 MB | 340 ms / 0.49 s / 350 MB | 287 ms / 0.45 s / 338 MB |
| 1,000 rows | ours | 46 ms / 0.14 s / 151 MB | 308 ms / 0.43 s / 344 MB | 114 ms / 0.26 s / 184 MB |
| read + pass | pyarrow | 82 ms / 0.16 s / 317 MB | 450 ms / 0.58 s / 492 MB | 339 ms / 0.53 s / 489 MB |
| read + pass | polars | 86 ms / 0.18 s / 318 MB | 481 ms / 0.64 s / 495 MB | 655 ms / 0.85 s / 602 MB |
| read + pass | ours | 88 ms / 0.19 s / 318 MB | 452 ms / 0.64 s / 522 MB | 332 ms / 0.52 s / 525 MB |
| write, defaults | dta | 124 ms / 0.20 s / 336 MB | 444 ms / 0.63 s / 507 MB | 192 ms / 0.36 s / 794 MB |
| write, zstd 3 | dta | 139 ms / 0.24 s / 338 MB | – | 592 ms / 0.78 s / 938 MB |

### 2017_2019_FemPreg

10,215 rows, 171 columns; Parquet pyarrow 0.4 MB, polars 0.4 MB, ours 0.5 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 14 ms / 0.04 s / 98 MB | 57 ms / 0.10 s / 158 MB | 31 ms / 0.11 s / 170 MB |
| whole file | polars | 15 ms / 0.04 s / 99 MB | 68 ms / 0.13 s / 158 MB | 35 ms / 0.13 s / 163 MB |
| whole file | ours | 16 ms / 0.04 s / 97 MB | 61 ms / 0.12 s / 158 MB | 31 ms / 0.11 s / 175 MB |
| five columns | pyarrow | 6 ms / 0.01 s / 66 MB | 9 ms / 0.02 s / 63 MB | 30 ms / 0.11 s / 170 MB |
| five columns | polars | 7 ms / 0.01 s / 65 MB | 11 ms / 0.03 s / 62 MB | 35 ms / 0.13 s / 163 MB |
| five columns | ours | 8 ms / 0.02 s / 67 MB | 9 ms / 0.02 s / 62 MB | 30 ms / 0.11 s / 175 MB |
| 1,000 rows | pyarrow | 10 ms / 0.03 s / 71 MB | 43 ms / 0.08 s / 126 MB | 17 ms / 0.05 s / 116 MB |
| 1,000 rows | polars | 11 ms / 0.03 s / 72 MB | 55 ms / 0.12 s / 126 MB | 21 ms / 0.07 s / 121 MB |
| 1,000 rows | ours | 12 ms / 0.03 s / 71 MB | 45 ms / 0.09 s / 127 MB | 17 ms / 0.05 s / 115 MB |
| read + pass | pyarrow | 21 ms / 0.05 s / 101 MB | 65 ms / 0.12 s / 159 MB | 36 ms / 0.13 s / 173 MB |
| read + pass | polars | 23 ms / 0.05 s / 105 MB | 74 ms / 0.15 s / 160 MB | 40 ms / 0.14 s / 169 MB |
| read + pass | ours | 23 ms / 0.05 s / 101 MB | 66 ms / 0.12 s / 158 MB | 36 ms / 0.13 s / 176 MB |
| write, defaults | dta | 27 ms / 0.04 s / 98 MB | 77 ms / 0.14 s / 153 MB | 41 ms / 0.06 s / 181 MB |
| write, zstd 3 | dta | 30 ms / 0.06 s / 106 MB | – | 48 ms / 0.08 s / 193 MB |

### 2017_2019_FemResp

6,141 rows, 2,609 columns; Parquet pyarrow 3.5 MB, polars 3.1 MB, ours 4.3 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 69 ms / 0.14 s / 297 MB | 453 ms / 0.62 s / 458 MB | 308 ms / 0.48 s / 438 MB |
| whole file | polars | 74 ms / 0.16 s / 298 MB | 520 ms / 0.70 s / 453 MB | 574 ms / 0.76 s / 511 MB |
| whole file | ours | 75 ms / 0.17 s / 298 MB | 465 ms / 0.62 s / 477 MB | 311 ms / 0.48 s / 499 MB |
| five columns | pyarrow | 12 ms / 0.04 s / 74 MB | 20 ms / 0.05 s / 80 MB | 288 ms / 0.46 s / 436 MB |
| five columns | polars | 13 ms / 0.04 s / 73 MB | 22 ms / 0.06 s / 76 MB | 567 ms / 0.74 s / 507 MB |
| five columns | ours | 19 ms / 0.07 s / 81 MB | 18 ms / 0.04 s / 79 MB | 287 ms / 0.45 s / 497 MB |
| 1,000 rows | pyarrow | 43 ms / 0.11 s / 144 MB | 362 ms / 0.51 s / 319 MB | 104 ms / 0.25 s / 186 MB |
| 1,000 rows | polars | 50 ms / 0.13 s / 145 MB | 395 ms / 0.55 s / 360 MB | 240 ms / 0.39 s / 315 MB |
| 1,000 rows | ours | 50 ms / 0.14 s / 145 MB | 354 ms / 0.48 s / 318 MB | 103 ms / 0.25 s / 181 MB |
| read + pass | pyarrow | 114 ms / 0.19 s / 301 MB | 491 ms / 0.62 s / 454 MB | 334 ms / 0.53 s / 511 MB |
| read + pass | polars | 121 ms / 0.21 s / 301 MB | 556 ms / 0.74 s / 453 MB | 608 ms / 0.81 s / 582 MB |
| read + pass | ours | 121 ms / 0.23 s / 302 MB | 492 ms / 0.65 s / 475 MB | 330 ms / 0.51 s / 569 MB |
| write, defaults | dta | 172 ms / 0.23 s / 325 MB | 539 ms / 0.69 s / 441 MB | 307 ms / 0.44 s / 746 MB |
| write, zstd 3 | dta | 191 ms / 0.27 s / 328 MB | – | 699 ms / 0.85 s / 879 MB |

### 2017_2019_Male

5,206 rows, 3,009 columns; Parquet pyarrow 2.2 MB, polars 2.2 MB, ours 2.9 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 64 ms / 0.14 s / 320 MB | 453 ms / 0.57 s / 494 MB | 370 ms / 0.56 s / 463 MB |
| whole file | polars | 69 ms / 0.17 s / 321 MB | 480 ms / 0.66 s / 517 MB | 725 ms / 0.91 s / 565 MB |
| whole file | ours | 70 ms / 0.17 s / 323 MB | 442 ms / 0.62 s / 527 MB | 368 ms / 0.56 s / 496 MB |
| five columns | pyarrow | 13 ms / 0.04 s / 73 MB | 21 ms / 0.05 s / 82 MB | 343 ms / 0.52 s / 461 MB |
| five columns | polars | 14 ms / 0.04 s / 73 MB | 21 ms / 0.05 s / 77 MB | 709 ms / 0.90 s / 565 MB |
| five columns | ours | 25 ms / 0.08 s / 80 MB | 18 ms / 0.05 s / 81 MB | 341 ms / 0.53 s / 496 MB |
| 1,000 rows | pyarrow | 44 ms / 0.12 s / 148 MB | 345 ms / 0.49 s / 348 MB | 124 ms / 0.29 s / 194 MB |
| 1,000 rows | polars | 46 ms / 0.13 s / 147 MB | 390 ms / 0.54 s / 357 MB | 299 ms / 0.48 s / 343 MB |
| 1,000 rows | ours | 49 ms / 0.15 s / 151 MB | 340 ms / 0.47 s / 355 MB | 118 ms / 0.28 s / 186 MB |
| read + pass | pyarrow | 91 ms / 0.17 s / 323 MB | 494 ms / 0.64 s / 499 MB | 400 ms / 0.61 s / 545 MB |
| read + pass | polars | 93 ms / 0.18 s / 322 MB | 521 ms / 0.75 s / 507 MB | 760 ms / 0.99 s / 649 MB |
| read + pass | ours | 95 ms / 0.20 s / 325 MB | 501 ms / 0.71 s / 534 MB | 405 ms / 0.64 s / 579 MB |
| write, defaults | dta | 143 ms / 0.24 s / 356 MB | 559 ms / 0.72 s / 460 MB | 201 ms / 0.38 s / 751 MB |
| write, zstd 3 | dta | 156 ms / 0.27 s / 357 MB | – | 589 ms / 0.79 s / 896 MB |

### 2022_2023_FemPreg

8,247 rows, 111 columns; Parquet pyarrow 0.3 MB, polars 0.3 MB, ours 0.3 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 11 ms / 0.02 s / 83 MB | 39 ms / 0.08 s / 105 MB | 25 ms / 0.09 s / 148 MB |
| whole file | polars | 12 ms / 0.03 s / 86 MB | 43 ms / 0.10 s / 107 MB | 30 ms / 0.11 s / 152 MB |
| whole file | ours | 12 ms / 0.02 s / 86 MB | 36 ms / 0.08 s / 105 MB | 25 ms / 0.09 s / 151 MB |
| five columns | pyarrow | 6 ms / 0.01 s / 61 MB | 9 ms / 0.02 s / 61 MB | 26 ms / 0.10 s / 150 MB |
| five columns | polars | 7 ms / 0.01 s / 61 MB | 10 ms / 0.03 s / 61 MB | 30 ms / 0.11 s / 143 MB |
| five columns | ours | 7 ms / 0.01 s / 65 MB | 10 ms / 0.03 s / 61 MB | 24 ms / 0.09 s / 147 MB |
| 1,000 rows | pyarrow | 9 ms / 0.02 s / 68 MB | 28 ms / 0.07 s / 83 MB | 17 ms / 0.05 s / 115 MB |
| 1,000 rows | polars | 10 ms / 0.02 s / 69 MB | 37 ms / 0.10 s / 86 MB | 19 ms / 0.06 s / 118 MB |
| 1,000 rows | ours | 10 ms / 0.02 s / 68 MB | 30 ms / 0.07 s / 83 MB | 16 ms / 0.05 s / 116 MB |
| read + pass | pyarrow | 16 ms / 0.03 s / 86 MB | 40 ms / 0.09 s / 105 MB | 30 ms / 0.11 s / 155 MB |
| read + pass | polars | 17 ms / 0.04 s / 88 MB | 50 ms / 0.12 s / 105 MB | 36 ms / 0.14 s / 153 MB |
| read + pass | ours | 17 ms / 0.04 s / 89 MB | 41 ms / 0.09 s / 105 MB | 32 ms / 0.12 s / 157 MB |
| write, defaults | dta | 16 ms / 0.03 s / 82 MB | 51 ms / 0.11 s / 134 MB | 30 ms / 0.05 s / 138 MB |
| write, zstd 3 | dta | 19 ms / 0.04 s / 91 MB | – | 36 ms / 0.06 s / 144 MB |

### 2022_2023_FemResp

5,586 rows, 1,912 columns; Parquet pyarrow 2.6 MB, polars 2.3 MB, ours 2.7 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 56 ms / 0.13 s / 255 MB | 320 ms / 0.43 s / 363 MB | 190 ms / 0.36 s / 342 MB |
| whole file | polars | 61 ms / 0.15 s / 254 MB | 372 ms / 0.50 s / 364 MB | 319 ms / 0.50 s / 396 MB |
| whole file | ours | 60 ms / 0.15 s / 257 MB | 320 ms / 0.44 s / 363 MB | 196 ms / 0.39 s / 361 MB |
| five columns | pyarrow | 11 ms / 0.04 s / 73 MB | 19 ms / 0.05 s / 74 MB | 186 ms / 0.37 s / 345 MB |
| five columns | polars | 12 ms / 0.04 s / 72 MB | 18 ms / 0.05 s / 70 MB | 322 ms / 0.52 s / 407 MB |
| five columns | ours | 14 ms / 0.05 s / 74 MB | 16 ms / 0.04 s / 73 MB | 185 ms / 0.37 s / 355 MB |
| 1,000 rows | pyarrow | 37 ms / 0.10 s / 123 MB | 269 ms / 0.42 s / 275 MB | 78 ms / 0.24 s / 172 MB |
| 1,000 rows | polars | 42 ms / 0.13 s / 122 MB | 292 ms / 0.44 s / 270 MB | 149 ms / 0.31 s / 270 MB |
| 1,000 rows | ours | 39 ms / 0.11 s / 125 MB | 254 ms / 0.37 s / 275 MB | 76 ms / 0.23 s / 164 MB |
| read + pass | pyarrow | 86 ms / 0.17 s / 259 MB | 364 ms / 0.50 s / 366 MB | 225 ms / 0.46 s / 401 MB |
| read + pass | polars | 89 ms / 0.17 s / 260 MB | 408 ms / 0.59 s / 367 MB | 355 ms / 0.60 s / 456 MB |
| read + pass | ours | 88 ms / 0.18 s / 260 MB | 369 ms / 0.51 s / 366 MB | 229 ms / 0.45 s / 417 MB |
| write, defaults | dta | 114 ms / 0.18 s / 258 MB | 423 ms / 0.62 s / 425 MB | 213 ms / 0.38 s / 648 MB |
| write, zstd 3 | dta | 130 ms / 0.22 s / 259 MB | – | 409 ms / 0.60 s / 749 MB |

### 2022_2023_MaleResp

4,371 rows, 1,157 columns; Parquet pyarrow 1.2 MB, polars 1.1 MB, ours 1.3 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 32 ms / 0.09 s / 191 MB | 152 ms / 0.25 s / 211 MB | 88 ms / 0.24 s / 244 MB |
| whole file | polars | 36 ms / 0.10 s / 191 MB | 171 ms / 0.27 s / 221 MB | 131 ms / 0.28 s / 276 MB |
| whole file | ours | 36 ms / 0.10 s / 193 MB | 150 ms / 0.25 s / 222 MB | 92 ms / 0.25 s / 257 MB |
| five columns | pyarrow | 9 ms / 0.03 s / 70 MB | 13 ms / 0.03 s / 69 MB | 84 ms / 0.23 s / 244 MB |
| five columns | polars | 10 ms / 0.03 s / 70 MB | 14 ms / 0.03 s / 67 MB | 123 ms / 0.27 s / 274 MB |
| five columns | ours | 11 ms / 0.03 s / 72 MB | 12 ms / 0.02 s / 66 MB | 86 ms / 0.24 s / 260 MB |
| 1,000 rows | pyarrow | 25 ms / 0.08 s / 105 MB | 119 ms / 0.20 s / 195 MB | 47 ms / 0.17 s / 154 MB |
| 1,000 rows | polars | 32 ms / 0.11 s / 105 MB | 143 ms / 0.23 s / 201 MB | 72 ms / 0.20 s / 199 MB |
| 1,000 rows | ours | 30 ms / 0.10 s / 106 MB | 122 ms / 0.20 s / 197 MB | 46 ms / 0.18 s / 152 MB |
| read + pass | pyarrow | 51 ms / 0.12 s / 195 MB | 162 ms / 0.26 s / 204 MB | 99 ms / 0.26 s / 270 MB |
| read + pass | polars | 57 ms / 0.15 s / 194 MB | 184 ms / 0.29 s / 223 MB | 140 ms / 0.30 s / 300 MB |
| read + pass | ours | 53 ms / 0.13 s / 194 MB | 165 ms / 0.26 s / 224 MB | 101 ms / 0.26 s / 282 MB |
| write, defaults | dta | 55 ms / 0.10 s / 187 MB | 224 ms / 0.36 s / 300 MB | 92 ms / 0.20 s / 408 MB |
| write, zstd 3 | dta | 65 ms / 0.12 s / 190 MB | – | 154 ms / 0.28 s / 463 MB |

### Senegal 2019 wm

8,649 rows, 4,997 columns; Parquet pyarrow 4.2 MB, polars 4.0 MB, ours 4.8 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 121 ms / 0.21 s / 621 MB | 1.22 s / 1.44 s / 1021 MB | 1.05 s / 1.28 s / 1046 MB |
| whole file | polars | 127 ms / 0.24 s / 624 MB | 1.20 s / 1.45 s / 1018 MB | 2.32 s / 2.57 s / 1022 MB |
| whole file | ours | 129 ms / 0.25 s / 626 MB | 1.14 s / 1.34 s / 1020 MB | 1.04 s / 1.29 s / 1023 MB |
| five columns | pyarrow | 19 ms / 0.05 s / 80 MB | 27 ms / 0.06 s / 87 MB | 968 ms / 1.20 s / 1040 MB |
| five columns | polars | 22 ms / 0.05 s / 80 MB | 29 ms / 0.07 s / 86 MB | 2.24 s / 2.49 s / 1013 MB |
| five columns | ours | 32 ms / 0.09 s / 85 MB | 23 ms / 0.05 s / 86 MB | 967 ms / 1.20 s / 1017 MB |
| 1,000 rows | pyarrow | 68 ms / 0.16 s / 201 MB | 844 ms / 1.11 s / 643 MB | 221 ms / 0.40 s / 241 MB |
| 1,000 rows | polars | 75 ms / 0.18 s / 195 MB | 859 ms / 1.14 s / 642 MB | 745 ms / 0.94 s / 497 MB |
| 1,000 rows | ours | 73 ms / 0.20 s / 199 MB | 830 ms / 1.10 s / 648 MB | 222 ms / 0.41 s / 245 MB |
| read + pass | pyarrow | 179 ms / 0.32 s / 639 MB | 1.33 s / 1.58 s / 1036 MB | 1.13 s / 1.43 s / 1286 MB |
| read + pass | polars | 217 ms / 0.36 s / 639 MB | 1.29 s / 1.55 s / 1031 MB | 2.43 s / 2.73 s / 1255 MB |
| read + pass | ours | 210 ms / 0.37 s / 643 MB | 1.22 s / 1.43 s / 1030 MB | 1.13 s / 1.41 s / 1260 MB |
| write, defaults | dta | 297 ms / 0.39 s / 681 MB | 1.06 s / 1.30 s / 1013 MB | 266 ms / 0.46 s / 1714 MB |
| write, zstd 3 | dta | 315 ms / 0.43 s / 684 MB | – | 830 ms / 1.05 s / 1964 MB |

### Senegal 2019 bh

21,562 rows, 1,191 columns; Parquet pyarrow 4.0 MB, polars 3.1 MB, ours 4.0 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 84 ms / 0.15 s / 394 MB | 569 ms / 0.71 s / 659 MB | 299 ms / 0.50 s / 624 MB |
| whole file | polars | 88 ms / 0.17 s / 394 MB | 640 ms / 0.80 s / 654 MB | 408 ms / 0.61 s / 509 MB |
| whole file | ours | 88 ms / 0.17 s / 394 MB | 564 ms / 0.67 s / 662 MB | 295 ms / 0.49 s / 598 MB |
| five columns | pyarrow | 14 ms / 0.04 s / 74 MB | 17 ms / 0.04 s / 79 MB | 293 ms / 0.48 s / 624 MB |
| five columns | polars | 13 ms / 0.04 s / 74 MB | 20 ms / 0.05 s / 75 MB | 402 ms / 0.60 s / 509 MB |
| five columns | ours | 15 ms / 0.06 s / 78 MB | 17 ms / 0.04 s / 75 MB | 311 ms / 0.51 s / 597 MB |
| 1,000 rows | pyarrow | 33 ms / 0.09 s / 112 MB | 383 ms / 0.50 s / 450 MB | 51 ms / 0.18 s / 150 MB |
| 1,000 rows | polars | 39 ms / 0.11 s / 109 MB | 499 ms / 0.63 s / 419 MB | 81 ms / 0.21 s / 211 MB |
| 1,000 rows | ours | 40 ms / 0.11 s / 112 MB | 425 ms / 0.54 s / 446 MB | 50 ms / 0.18 s / 153 MB |
| read + pass | pyarrow | 121 ms / 0.20 s / 401 MB | 657 ms / 0.79 s / 658 MB | 344 ms / 0.55 s / 742 MB |
| read + pass | polars | 128 ms / 0.22 s / 401 MB | 709 ms / 0.88 s / 658 MB | 455 ms / 0.67 s / 630 MB |
| read + pass | ours | 125 ms / 0.22 s / 401 MB | 643 ms / 0.75 s / 661 MB | 346 ms / 0.56 s / 712 MB |
| write, defaults | dta | 211 ms / 0.27 s / 393 MB | 676 ms / 0.84 s / 672 MB | 253 ms / 0.40 s / 928 MB |
| write, zstd 3 | dta | 225 ms / 0.30 s / 392 MB | – | 339 ms / 0.51 s / 1113 MB |

### Turkey 2013 wm

9,746 rows, 4,668 columns; Parquet pyarrow 4.3 MB, polars 4.0 MB, ours 4.9 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 124 ms / 0.22 s / 596 MB | 1.17 s / 1.38 s / 963 MB | 1.18 s / 1.41 s / 1059 MB |
| whole file | polars | 133 ms / 0.25 s / 595 MB | 1.16 s / 1.40 s / 960 MB | 2.42 s / 2.67 s / 1046 MB |
| whole file | ours | 131 ms / 0.27 s / 598 MB | 1.09 s / 1.28 s / 959 MB | 1.03 s / 1.27 s / 1045 MB |
| five columns | pyarrow | 18 ms / 0.05 s / 81 MB | 26 ms / 0.06 s / 88 MB | 1.13 s / 1.35 s / 1061 MB |
| five columns | polars | 19 ms / 0.05 s / 80 MB | 28 ms / 0.06 s / 85 MB | 2.36 s / 2.60 s / 1044 MB |
| five columns | ours | 29 ms / 0.09 s / 85 MB | 22 ms / 0.05 s / 84 MB | 972 ms / 1.20 s / 1044 MB |
| 1,000 rows | pyarrow | 59 ms / 0.14 s / 195 MB | 799 ms / 1.05 s / 617 MB | 196 ms / 0.37 s / 233 MB |
| 1,000 rows | polars | 64 ms / 0.16 s / 192 MB | 836 ms / 1.14 s / 618 MB | 663 ms / 0.85 s / 468 MB |
| 1,000 rows | ours | 65 ms / 0.17 s / 196 MB | 813 ms / 1.05 s / 608 MB | 192 ms / 0.36 s / 221 MB |
| read + pass | pyarrow | 180 ms / 0.30 s / 608 MB | 1.29 s / 1.51 s / 973 MB | 1.27 s / 1.56 s / 1285 MB |
| read + pass | polars | 186 ms / 0.32 s / 609 MB | 1.28 s / 1.53 s / 968 MB | 2.54 s / 2.83 s / 1269 MB |
| read + pass | ours | 185 ms / 0.33 s / 609 MB | 1.21 s / 1.41 s / 971 MB | 1.13 s / 1.42 s / 1270 MB |
| write, defaults | dta | 303 ms / 0.40 s / 651 MB | 1.08 s / 1.31 s / 1000 MB | 269 ms / 0.47 s / 1681 MB |
| write, zstd 3 | dta | 321 ms / 0.44 s / 653 MB | – | 717 ms / 0.94 s / 1935 MB |

### Turkey 2013 bh

17,871 rows, 1,173 columns; Parquet pyarrow 3.3 MB, polars 2.7 MB, ours 3.5 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 70 ms / 0.13 s / 344 MB | 498 ms / 0.62 s / 658 MB | 236 ms / 0.41 s / 564 MB |
| whole file | polars | 74 ms / 0.15 s / 346 MB | 538 ms / 0.69 s / 665 MB | 322 ms / 0.50 s / 456 MB |
| whole file | ours | 73 ms / 0.15 s / 347 MB | 486 ms / 0.60 s / 654 MB | 238 ms / 0.43 s / 558 MB |
| five columns | pyarrow | 11 ms / 0.03 s / 73 MB | 17 ms / 0.04 s / 78 MB | 236 ms / 0.41 s / 569 MB |
| five columns | polars | 12 ms / 0.03 s / 74 MB | 19 ms / 0.04 s / 77 MB | 318 ms / 0.49 s / 453 MB |
| five columns | ours | 15 ms / 0.05 s / 75 MB | 16 ms / 0.04 s / 76 MB | 235 ms / 0.41 s / 555 MB |
| 1,000 rows | pyarrow | 28 ms / 0.08 s / 108 MB | 350 ms / 0.45 s / 414 MB | 48 ms / 0.17 s / 154 MB |
| 1,000 rows | polars | 34 ms / 0.10 s / 108 MB | 411 ms / 0.58 s / 409 MB | 77 ms / 0.21 s / 208 MB |
| 1,000 rows | ours | 33 ms / 0.10 s / 109 MB | 345 ms / 0.45 s / 413 MB | 48 ms / 0.18 s / 156 MB |
| read + pass | pyarrow | 100 ms / 0.17 s / 352 MB | 553 ms / 0.68 s / 663 MB | 282 ms / 0.48 s / 652 MB |
| read + pass | polars | 102 ms / 0.18 s / 354 MB | 591 ms / 0.75 s / 650 MB | 373 ms / 0.58 s / 543 MB |
| read + pass | ours | 100 ms / 0.18 s / 354 MB | 542 ms / 0.66 s / 650 MB | 283 ms / 0.49 s / 645 MB |
| write, defaults | dta | 169 ms / 0.23 s / 347 MB | 552 ms / 0.74 s / 583 MB | 218 ms / 0.36 s / 813 MB |
| write, zstd 3 | dta | 183 ms / 0.26 s / 344 MB | – | 259 ms / 0.42 s / 896 MB |

### Tajikistan 2017 wm

10,718 rows, 5,160 columns; Parquet pyarrow 5.7 MB, polars 5.3 MB, ours 6.4 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 146 ms / 0.25 s / 738 MB | 1.47 s / 1.90 s / 1589 MB | 1.37 s / 1.62 s / 1230 MB |
| whole file | polars | 155 ms / 0.27 s / 740 MB | 1.60 s / 2.04 s / 1581 MB | 2.88 s / 3.14 s / 1203 MB |
| whole file | ours | 154 ms / 0.28 s / 742 MB | 1.48 s / 1.91 s / 1591 MB | 1.36 s / 1.63 s / 1211 MB |
| five columns | pyarrow | 19 ms / 0.05 s / 83 MB | 32 ms / 0.07 s / 100 MB | 1.30 s / 1.57 s / 1231 MB |
| five columns | polars | 20 ms / 0.05 s / 82 MB | 33 ms / 0.07 s / 86 MB | 2.78 s / 3.09 s / 1201 MB |
| five columns | ours | 29 ms / 0.09 s / 86 MB | 25 ms / 0.06 s / 90 MB | 1.29 s / 1.54 s / 1215 MB |
| 1,000 rows | pyarrow | 64 ms / 0.14 s / 207 MB | 1.09 s / 1.38 s / 877 MB | 235 ms / 0.42 s / 255 MB |
| 1,000 rows | polars | 70 ms / 0.16 s / 204 MB | 1.06 s / 1.37 s / 895 MB | 803 ms / 0.99 s / 514 MB |
| 1,000 rows | ours | 70 ms / 0.17 s / 207 MB | 1.12 s / 1.39 s / 892 MB | 227 ms / 0.40 s / 242 MB |
| read + pass | pyarrow | 212 ms / 0.32 s / 749 MB | 1.65 s / 2.06 s / 1591 MB | 1.51 s / 1.82 s / 1474 MB |
| read + pass | polars | 219 ms / 0.35 s / 749 MB | 1.72 s / 2.16 s / 1596 MB | 3.09 s / 3.41 s / 1450 MB |
| read + pass | ours | 219 ms / 0.36 s / 753 MB | 1.61 s / 2.04 s / 1594 MB | 1.49 s / 1.81 s / 1460 MB |
| write, defaults | dta | 373 ms / 0.48 s / 765 MB | 1.29 s / 1.53 s / 1214 MB | 325 ms / 0.53 s / 1969 MB |
| write, zstd 3 | dta | 402 ms / 0.53 s / 770 MB | – | 891 ms / 1.11 s / 2254 MB |

### Tajikistan 2017 bh

21,985 rows, 1,146 columns; Parquet pyarrow 4.8 MB, polars 3.8 MB, ours 4.8 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 83 ms / 0.15 s / 384 MB | 567 ms / 0.69 s / 658 MB | 283 ms / 0.47 s / 611 MB |
| whole file | polars | 89 ms / 0.17 s / 384 MB | 641 ms / 0.85 s / 646 MB | 392 ms / 0.59 s / 505 MB |
| whole file | ours | 86 ms / 0.17 s / 386 MB | 550 ms / 0.67 s / 657 MB | 288 ms / 0.48 s / 616 MB |
| five columns | pyarrow | 12 ms / 0.03 s / 76 MB | 17 ms / 0.04 s / 77 MB | 286 ms / 0.49 s / 613 MB |
| five columns | polars | 12 ms / 0.03 s / 76 MB | 30 ms / 0.05 s / 79 MB | 386 ms / 0.58 s / 500 MB |
| five columns | ours | 15 ms / 0.05 s / 78 MB | 17 ms / 0.04 s / 76 MB | 281 ms / 0.47 s / 612 MB |
| 1,000 rows | pyarrow | 32 ms / 0.08 s / 111 MB | 376 ms / 0.49 s / 432 MB | 50 ms / 0.18 s / 152 MB |
| 1,000 rows | polars | 39 ms / 0.11 s / 109 MB | 463 ms / 0.61 s / 428 MB | 82 ms / 0.21 s / 210 MB |
| 1,000 rows | ours | 35 ms / 0.10 s / 112 MB | 413 ms / 0.52 s / 426 MB | 50 ms / 0.18 s / 147 MB |
| read + pass | pyarrow | 118 ms / 0.19 s / 387 MB | 645 ms / 0.77 s / 654 MB | 336 ms / 0.55 s / 720 MB |
| read + pass | polars | 122 ms / 0.21 s / 391 MB | 718 ms / 0.87 s / 641 MB | 444 ms / 0.65 s / 616 MB |
| read + pass | ours | 120 ms / 0.20 s / 391 MB | 628 ms / 0.75 s / 657 MB | 336 ms / 0.55 s / 720 MB |
| write, defaults | dta | 214 ms / 0.27 s / 384 MB | 685 ms / 0.86 s / 656 MB | 265 ms / 0.41 s / 948 MB |
| write, zstd 3 | dta | 232 ms / 0.31 s / 398 MB | – | 348 ms / 0.52 s / 1118 MB |

### Myanmar 2016 wm

12,885 rows, 4,993 columns; Parquet pyarrow 5.3 MB, polars 4.9 MB, ours 5.9 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 162 ms / 0.27 s / 808 MB | 1.58 s / 2.00 s / 1527 MB | 1.61 s / 1.86 s / 1601 MB |
| whole file | polars | 168 ms / 0.29 s / 806 MB | 1.65 s / 2.10 s / 1537 MB | 3.25 s / 3.52 s / 1708 MB |
| whole file | ours | 173 ms / 0.32 s / 812 MB | 1.56 s / 1.97 s / 1548 MB | 1.60 s / 1.85 s / 1567 MB |
| five columns | pyarrow | 20 ms / 0.05 s / 81 MB | 28 ms / 0.06 s / 93 MB | 1.53 s / 1.80 s / 1594 MB |
| five columns | polars | 20 ms / 0.05 s / 82 MB | 31 ms / 0.07 s / 87 MB | 3.20 s / 3.46 s / 1704 MB |
| five columns | ours | 29 ms / 0.09 s / 86 MB | 28 ms / 0.06 s / 89 MB | 1.54 s / 1.78 s / 1560 MB |
| 1,000 rows | pyarrow | 65 ms / 0.15 s / 203 MB | 1.11 s / 1.37 s / 862 MB | 227 ms / 0.40 s / 250 MB |
| 1,000 rows | polars | 70 ms / 0.17 s / 200 MB | 1.11 s / 1.42 s / 898 MB | 772 ms / 0.96 s / 495 MB |
| 1,000 rows | ours | 69 ms / 0.18 s / 203 MB | 1.09 s / 1.36 s / 857 MB | 224 ms / 0.39 s / 236 MB |
| read + pass | pyarrow | 235 ms / 0.36 s / 821 MB | 1.76 s / 2.19 s / 1547 MB | 1.76 s / 2.09 s / 1920 MB |
| read + pass | polars | 239 ms / 0.37 s / 820 MB | 1.77 s / 2.22 s / 1541 MB | 3.46 s / 3.79 s / 2036 MB |
| read + pass | ours | 242 ms / 0.38 s / 824 MB | 1.71 s / 2.14 s / 1546 MB | 1.74 s / 2.05 s / 1887 MB |
| write, defaults | dta | 401 ms / 0.50 s / 868 MB | 1.42 s / 1.64 s / 1378 MB | 341 ms / 0.54 s / 2202 MB |
| write, zstd 3 | dta | 432 ms / 0.55 s / 868 MB | – | 780 ms / 1.00 s / 2485 MB |

### Myanmar 2016 bh

22,989 rows, 1,184 columns; Parquet pyarrow 4.2 MB, polars 3.3 MB, ours 4.3 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 85 ms / 0.15 s / 412 MB | 672 ms / 0.80 s / 858 MB | 305 ms / 0.50 s / 647 MB |
| whole file | polars | 90 ms / 0.17 s / 412 MB | 715 ms / 0.92 s / 857 MB | 420 ms / 0.61 s / 522 MB |
| whole file | ours | 88 ms / 0.17 s / 412 MB | 653 ms / 0.85 s / 885 MB | 312 ms / 0.51 s / 655 MB |
| five columns | pyarrow | 13 ms / 0.04 s / 76 MB | 20 ms / 0.05 s / 81 MB | 306 ms / 0.50 s / 644 MB |
| five columns | polars | 13 ms / 0.04 s / 76 MB | 21 ms / 0.05 s / 79 MB | 416 ms / 0.61 s / 521 MB |
| five columns | ours | 16 ms / 0.05 s / 78 MB | 18 ms / 0.05 s / 79 MB | 303 ms / 0.49 s / 654 MB |
| 1,000 rows | pyarrow | 31 ms / 0.08 s / 109 MB | 371 ms / 0.47 s / 450 MB | 51 ms / 0.18 s / 147 MB |
| 1,000 rows | polars | 37 ms / 0.10 s / 109 MB | 503 ms / 0.72 s / 528 MB | 83 ms / 0.21 s / 211 MB |
| 1,000 rows | ours | 34 ms / 0.10 s / 111 MB | 467 ms / 0.59 s / 555 MB | 50 ms / 0.18 s / 153 MB |
| read + pass | pyarrow | 121 ms / 0.19 s / 418 MB | 747 ms / 0.88 s / 868 MB | 358 ms / 0.57 s / 762 MB |
| read + pass | polars | 127 ms / 0.21 s / 420 MB | 791 ms / 0.97 s / 861 MB | 475 ms / 0.69 s / 647 MB |
| read + pass | ours | 125 ms / 0.21 s / 420 MB | 719 ms / 0.84 s / 864 MB | 363 ms / 0.58 s / 777 MB |
| write, defaults | dta | 215 ms / 0.27 s / 424 MB | 691 ms / 0.88 s / 710 MB | 281 ms / 0.42 s / 1013 MB |
| write, zstd 3 | dta | 236 ms / 0.31 s / 427 MB | – | 367 ms / 0.53 s / 1170 MB |

### Dominican Republic 2013 wm

9,372 rows, 3,854 columns; Parquet pyarrow 3.8 MB, polars 3.5 MB, ours 4.3 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 104 ms / 0.19 s / 512 MB | 934 ms / 1.14 s / 823 MB | 769 ms / 1.00 s / 887 MB |
| whole file | polars | 110 ms / 0.21 s / 512 MB | 951 ms / 1.16 s / 814 MB | 1.55 s / 1.79 s / 861 MB |
| whole file | ours | 110 ms / 0.22 s / 515 MB | 932 ms / 1.12 s / 817 MB | 752 ms / 0.97 s / 869 MB |
| five columns | pyarrow | 16 ms / 0.04 s / 78 MB | 24 ms / 0.06 s / 84 MB | 716 ms / 0.94 s / 888 MB |
| five columns | polars | 17 ms / 0.05 s / 78 MB | 27 ms / 0.06 s / 84 MB | 1.55 s / 1.79 s / 861 MB |
| five columns | ours | 25 ms / 0.08 s / 83 MB | 22 ms / 0.05 s / 85 MB | 713 ms / 0.93 s / 872 MB |
| 1,000 rows | pyarrow | 50 ms / 0.12 s / 170 MB | 695 ms / 0.93 s / 529 MB | 152 ms / 0.32 s / 213 MB |
| 1,000 rows | polars | 56 ms / 0.14 s / 173 MB | 706 ms / 0.97 s / 526 MB | 460 ms / 0.64 s / 408 MB |
| 1,000 rows | ours | 56 ms / 0.15 s / 171 MB | 720 ms / 0.93 s / 522 MB | 148 ms / 0.31 s / 203 MB |
| read + pass | pyarrow | 145 ms / 0.24 s / 518 MB | 1.03 s / 1.23 s / 830 MB | 832 ms / 1.09 s / 1071 MB |
| read + pass | polars | 152 ms / 0.26 s / 520 MB | 1.04 s / 1.27 s / 824 MB | 1.65 s / 1.94 s / 1044 MB |
| read + pass | ours | 153 ms / 0.27 s / 530 MB | 1.03 s / 1.24 s / 828 MB | 824 ms / 1.09 s / 1052 MB |
| write, defaults | dta | 253 ms / 0.33 s / 555 MB | 879 ms / 1.09 s / 833 MB | 248 ms / 0.43 s / 1384 MB |
| write, zstd 3 | dta | 273 ms / 0.37 s / 556 MB | – | 523 ms / 0.73 s / 1600 MB |

### Dominican Republic 2013 bh

18,167 rows, 1,078 columns; Parquet pyarrow 3.5 MB, polars 2.8 MB, ours 3.6 MB.

| case | input | ours | hyparquet | parquet-wasm |
|---|---|---|---|---|
| whole file | pyarrow | 70 ms / 0.14 s / 330 MB | 477 ms / 0.59 s / 612 MB | 221 ms / 0.39 s / 534 MB |
| whole file | polars | 74 ms / 0.15 s / 329 MB | 512 ms / 0.66 s / 624 MB | 292 ms / 0.47 s / 431 MB |
| whole file | ours | 71 ms / 0.14 s / 331 MB | 459 ms / 0.56 s / 610 MB | 220 ms / 0.39 s / 526 MB |
| five columns | pyarrow | 11 ms / 0.03 s / 73 MB | 18 ms / 0.05 s / 74 MB | 217 ms / 0.38 s / 534 MB |
| five columns | polars | 12 ms / 0.03 s / 73 MB | 19 ms / 0.04 s / 75 MB | 287 ms / 0.46 s / 431 MB |
| five columns | ours | 14 ms / 0.04 s / 76 MB | 16 ms / 0.04 s / 75 MB | 217 ms / 0.39 s / 528 MB |
| 1,000 rows | pyarrow | 29 ms / 0.08 s / 107 MB | 357 ms / 0.46 s / 425 MB | 48 ms / 0.18 s / 149 MB |
| 1,000 rows | polars | 34 ms / 0.10 s / 107 MB | 388 ms / 0.50 s / 392 MB | 75 ms / 0.21 s / 203 MB |
| 1,000 rows | ours | 31 ms / 0.09 s / 108 MB | 343 ms / 0.45 s / 422 MB | 47 ms / 0.17 s / 150 MB |
| read + pass | pyarrow | 99 ms / 0.17 s / 336 MB | 557 ms / 0.67 s / 610 MB | 261 ms / 0.45 s / 615 MB |
| read + pass | polars | 103 ms / 0.18 s / 337 MB | 564 ms / 0.73 s / 612 MB | 338 ms / 0.55 s / 511 MB |
| read + pass | ours | 98 ms / 0.18 s / 336 MB | 509 ms / 0.62 s / 611 MB | 262 ms / 0.46 s / 609 MB |
| write, defaults | dta | 168 ms / 0.22 s / 339 MB | 537 ms / 0.71 s / 549 MB | 216 ms / 0.36 s / 769 MB |
| write, zstd 3 | dta | 182 ms / 0.25 s / 328 MB | – | 255 ms / 0.41 s / 848 MB |

