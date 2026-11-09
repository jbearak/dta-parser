# Parquet benchmark: R's polars reader (plan 0025, stage 4)

Written by `bench/parquet/polars_r.R`. No target: this records what `read_parquet_pl()` costs beside polars' own reader and datakit's tibble `read_parquet()`.

File: DHS Albania 2018 wm, 15,000 rows and 4,962 columns, written as Parquet by datakit's `save_parquet()` with its defaults (5.7 MB).
Five columns: `caseid`, `m49g_3`, `h57m_5`, `v762ab`, `sy1307pr_6`.

Method: each reader once to warm up, then 10 runs in one R process, `gc()` before each; the best wall time, the median wall time, and the CPU time (user plus system) of the best run. Default thread counts. One-minute load average before the runs: 2.44.

R 4.6.1, datakit 3.1.0, dtaparser 3.1.0, polars 2.1.0, nanoarrow 0.9.0; Apple M4 Max.

| case | reader | best wall ms | median wall ms | CPU ms (best run) |
|---|---|---|---|---|
| whole file | datakit read_parquet_pl() | 119.2 | 124.8 | 143.0 |
| whole file | polars pl$read_parquet() | 12.0 | 12.9 | 29.0 |
| whole file | datakit read_parquet() (tibble) | 34.8 | 42.5 | 59.0 |
| five columns | datakit read_parquet_pl() | 12.4 | 12.6 | 13.0 |
| five columns | polars pl$read_parquet() | 4.7 | 4.7 | 5.0 |
| five columns | datakit read_parquet() (tibble) | 6.0 | 6.0 | 6.0 |
