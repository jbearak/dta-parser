# Parquet benchmarks (Python)

Written by `bench/parquet/run_py.py`; bench/RESULTS.md says what the numbers mean.

One-minute load average before the runs: median 10.9, range 9.3 to 15.2.

| library | version | threads |
|---|---|---|
| DuckDB → Arrow | 2.0.0 | 16 |
| fastparquet | 2026.9.0 | 1 |
| dta_parser | 0.2.0 | default |
| pandas.read_parquet | 3.1.1 | 16 |
| polars → pandas | 2.1.0 | 16 |
| polars DataFrame | 2.1.0 | 16 |
| pyarrow → pandas | 26.0.1 | 16 |
| pyarrow Table | 26.0.1 | 16 |

## Ratios, ours to theirs (geometric means), gated

Below 1 is better for us. Target 1 holds where wall and RSS are at most 1.05 on NSFG and DHS.

| against | case | input | family | files | wall | CPU | peak RSS |
|---|---|---|---|---|---|---|---|
| pyarrow → pandas | whole file | pyarrow | NSFG | 36 | 0.18 | 0.12 | 0.75 |
| pyarrow → pandas | whole file | pyarrow | DHS | 10 | 0.44 | 0.18 | 0.65 |
| pyarrow → pandas | whole file | pyarrow | Synthetic | 3 | 0.54 | 0.50 | 0.51 |
| pyarrow → pandas | whole file | polars | NSFG | 36 | 0.19 | 0.13 | 0.75 |
| pyarrow → pandas | whole file | polars | DHS | 10 | 0.46 | 0.18 | 0.65 |
| pyarrow → pandas | whole file | polars | Synthetic | 3 | 0.83 | 0.56 | 0.49 |
| pyarrow → pandas | whole file | ours | NSFG | 36 | 0.20 | 0.13 | 0.76 |
| pyarrow → pandas | whole file | ours | DHS | 10 | 0.49 | 0.19 | 0.66 |
| pyarrow → pandas | whole file | ours | Synthetic | 3 | 0.52 | 0.36 | 0.48 |
| pyarrow → pandas | five columns | pyarrow | NSFG | 36 | 0.05 | 0.05 | 0.89 |
| pyarrow → pandas | five columns | pyarrow | DHS | 10 | 0.09 | 0.08 | 0.86 |
| pyarrow → pandas | five columns | pyarrow | Synthetic | 3 | 0.53 | 0.45 | 0.66 |
| pyarrow → pandas | five columns | polars | NSFG | 36 | 0.05 | 0.05 | 0.89 |
| pyarrow → pandas | five columns | polars | DHS | 10 | 0.08 | 0.08 | 0.86 |
| pyarrow → pandas | five columns | polars | Synthetic | 3 | 1.00 | 0.47 | 0.60 |
| pyarrow → pandas | five columns | ours | NSFG | 36 | 0.06 | 0.06 | 0.89 |
| pyarrow → pandas | five columns | ours | DHS | 10 | 0.11 | 0.10 | 0.85 |
| pyarrow → pandas | five columns | ours | Synthetic | 3 | 0.58 | 0.31 | 0.59 |
| pyarrow → pandas | 1,000 rows | pyarrow | NSFG | 36 | 0.11 | 0.06 | 0.65 |
| pyarrow → pandas | 1,000 rows | pyarrow | DHS | 10 | 0.23 | 0.08 | 0.40 |
| pyarrow → pandas | 1,000 rows | pyarrow | Synthetic | 3 | 0.04 | 0.01 | 0.05 |
| pyarrow → pandas | 1,000 rows | polars | NSFG | 36 | 0.13 | 0.07 | 0.65 |
| pyarrow → pandas | 1,000 rows | polars | DHS | 10 | 0.27 | 0.09 | 0.40 |
| pyarrow → pandas | 1,000 rows | polars | Synthetic | 3 | 0.05 | 0.01 | 0.05 |
| pyarrow → pandas | 1,000 rows | ours | NSFG | 36 | 0.13 | 0.07 | 0.67 |
| pyarrow → pandas | 1,000 rows | ours | DHS | 10 | 0.28 | 0.10 | 0.42 |
| pyarrow → pandas | 1,000 rows | ours | Synthetic | 3 | 0.03 | 0.00 | 0.05 |
| pyarrow → pandas | read + pass | pyarrow | NSFG | 36 | 0.36 | 0.23 | 0.75 |
| pyarrow → pandas | read + pass | pyarrow | DHS | 10 | 0.71 | 0.30 | 0.65 |
| pyarrow → pandas | read + pass | pyarrow | Synthetic | 3 | 0.79 | 0.59 | 0.57 |
| pyarrow → pandas | read + pass | polars | NSFG | 36 | 0.37 | 0.24 | 0.75 |
| pyarrow → pandas | read + pass | polars | DHS | 10 | 0.72 | 0.31 | 0.65 |
| pyarrow → pandas | read + pass | polars | Synthetic | 3 | 0.94 | 0.63 | 0.55 |
| pyarrow → pandas | read + pass | ours | NSFG | 36 | 0.38 | 0.24 | 0.76 |
| pyarrow → pandas | read + pass | ours | DHS | 10 | 0.74 | 0.32 | 0.66 |
| pyarrow → pandas | read + pass | ours | Synthetic | 3 | 0.79 | 0.47 | 0.54 |
| pyarrow → pandas | write, defaults | dta | NSFG | 36 | 0.31 | 0.44 | 0.94 |
| pyarrow → pandas | write, defaults | dta | DHS | 10 | 0.26 | 0.47 | 0.95 |
| pyarrow → pandas | write, defaults | dta | Synthetic | 3 | 0.23 | 0.59 | 1.00 |
| pyarrow → pandas | write, zstd 3 | dta | NSFG | 36 | 0.33 | 0.47 | 0.95 |
| pyarrow → pandas | write, zstd 3 | dta | DHS | 10 | 0.27 | 0.49 | 0.95 |
| pyarrow → pandas | write, zstd 3 | dta | Synthetic | 3 | 0.27 | 0.70 | 1.00 |
| pandas.read_parquet | whole file | pyarrow | NSFG | 36 | 0.17 | 0.12 | 0.75 |
| pandas.read_parquet | whole file | pyarrow | DHS | 10 | 0.43 | 0.18 | 0.65 |
| pandas.read_parquet | whole file | pyarrow | Synthetic | 3 | 0.54 | 0.49 | 0.51 |
| pandas.read_parquet | whole file | polars | NSFG | 36 | 0.19 | 0.12 | 0.75 |
| pandas.read_parquet | whole file | polars | DHS | 10 | 0.46 | 0.18 | 0.65 |
| pandas.read_parquet | whole file | polars | Synthetic | 3 | 0.85 | 0.55 | 0.49 |
| pandas.read_parquet | whole file | ours | NSFG | 36 | 0.20 | 0.12 | 0.76 |
| pandas.read_parquet | whole file | ours | DHS | 10 | 0.49 | 0.19 | 0.66 |
| pandas.read_parquet | whole file | ours | Synthetic | 3 | 0.51 | 0.37 | 0.48 |
| pandas.read_parquet | five columns | pyarrow | NSFG | 36 | 0.05 | 0.05 | 0.89 |
| pandas.read_parquet | five columns | pyarrow | DHS | 10 | 0.09 | 0.08 | 0.86 |
| pandas.read_parquet | five columns | pyarrow | Synthetic | 3 | 0.53 | 0.43 | 0.66 |
| pandas.read_parquet | five columns | polars | NSFG | 36 | 0.05 | 0.05 | 0.89 |
| pandas.read_parquet | five columns | polars | DHS | 10 | 0.08 | 0.08 | 0.86 |
| pandas.read_parquet | five columns | polars | Synthetic | 3 | 1.01 | 0.47 | 0.60 |
| pandas.read_parquet | five columns | ours | NSFG | 36 | 0.06 | 0.06 | 0.89 |
| pandas.read_parquet | five columns | ours | DHS | 10 | 0.11 | 0.10 | 0.85 |
| pandas.read_parquet | five columns | ours | Synthetic | 3 | 0.57 | 0.31 | 0.59 |
| pandas.read_parquet | 1,000 rows | pyarrow | NSFG | 36 | 0.11 | 0.05 | 0.54 |
| pandas.read_parquet | 1,000 rows | pyarrow | DHS | 10 | 0.20 | 0.05 | 0.24 |
| pandas.read_parquet | 1,000 rows | pyarrow | Synthetic | 3 | 0.03 | 0.01 | 0.04 |
| pandas.read_parquet | 1,000 rows | polars | NSFG | 36 | 0.13 | 0.07 | 0.54 |
| pandas.read_parquet | 1,000 rows | polars | DHS | 10 | 0.24 | 0.06 | 0.24 |
| pandas.read_parquet | 1,000 rows | polars | Synthetic | 3 | 0.04 | 0.01 | 0.04 |
| pandas.read_parquet | 1,000 rows | ours | NSFG | 36 | 0.13 | 0.06 | 0.55 |
| pandas.read_parquet | 1,000 rows | ours | DHS | 10 | 0.25 | 0.06 | 0.25 |
| pandas.read_parquet | 1,000 rows | ours | Synthetic | 3 | 0.02 | 0.00 | 0.04 |
| pandas.read_parquet | read + pass | pyarrow | NSFG | 36 | 0.36 | 0.23 | 0.75 |
| pandas.read_parquet | read + pass | pyarrow | DHS | 10 | 0.71 | 0.31 | 0.65 |
| pandas.read_parquet | read + pass | pyarrow | Synthetic | 3 | 0.80 | 0.59 | 0.57 |
| pandas.read_parquet | read + pass | polars | NSFG | 36 | 0.37 | 0.24 | 0.75 |
| pandas.read_parquet | read + pass | polars | DHS | 10 | 0.72 | 0.30 | 0.65 |
| pandas.read_parquet | read + pass | polars | Synthetic | 3 | 0.94 | 0.64 | 0.55 |
| pandas.read_parquet | read + pass | ours | NSFG | 36 | 0.37 | 0.24 | 0.76 |
| pandas.read_parquet | read + pass | ours | DHS | 10 | 0.74 | 0.32 | 0.66 |
| pandas.read_parquet | read + pass | ours | Synthetic | 3 | 0.78 | 0.47 | 0.54 |
| fastparquet | whole file | pyarrow | NSFG | 36 | 0.16 | 0.23 | 1.04 |
| fastparquet | whole file | pyarrow | DHS | 10 | 0.15 | 0.28 | 1.51 |
| fastparquet | whole file | pyarrow | Synthetic | 3 | 0.20 | 0.85 | 1.30 |
| fastparquet | whole file | polars | NSFG | 36 | 0.17 | 0.25 | 1.05 |
| fastparquet | whole file | polars | DHS | 10 | 0.17 | 0.30 | 1.52 |
| fastparquet | whole file | polars | Synthetic | 3 | 0.20 | 0.90 | 1.25 |
| fastparquet | whole file | ours | NSFG | 36 | 0.19 | 0.26 | 1.06 |
| fastparquet | whole file | ours | DHS | 10 | 0.19 | 0.32 | 1.54 |
| fastparquet | whole file | ours | Synthetic | 3 | 0.25 | 1.10 | 1.25 |
| fastparquet | five columns | pyarrow | NSFG | 36 | 0.13 | 0.13 | 0.91 |
| fastparquet | five columns | pyarrow | DHS | 10 | 0.09 | 0.09 | 0.89 |
| fastparquet | five columns | pyarrow | Synthetic | 3 | 0.35 | 0.74 | 1.30 |
| fastparquet | five columns | polars | NSFG | 36 | 0.13 | 0.13 | 0.92 |
| fastparquet | five columns | polars | DHS | 10 | 0.09 | 0.09 | 0.90 |
| fastparquet | five columns | polars | Synthetic | 3 | 0.36 | 0.77 | 1.18 |
| fastparquet | five columns | ours | NSFG | 36 | 0.16 | 0.16 | 0.92 |
| fastparquet | five columns | ours | DHS | 10 | 0.12 | 0.12 | 0.91 |
| fastparquet | five columns | ours | Synthetic | 3 | 0.38 | 0.82 | 1.22 |
| fastparquet | 1,000 rows | pyarrow | NSFG | 36 | 0.10 | 0.11 | 0.74 |
| fastparquet | 1,000 rows | pyarrow | DHS | 10 | 0.07 | 0.09 | 0.56 |
| fastparquet | 1,000 rows | pyarrow | Synthetic | 3 | 0.01 | 0.01 | 0.10 |
| fastparquet | 1,000 rows | polars | NSFG | 36 | 0.11 | 0.13 | 0.75 |
| fastparquet | 1,000 rows | polars | DHS | 10 | 0.08 | 0.10 | 0.56 |
| fastparquet | 1,000 rows | polars | Synthetic | 3 | 0.01 | 0.01 | 0.09 |
| fastparquet | 1,000 rows | ours | NSFG | 36 | 0.12 | 0.13 | 0.78 |
| fastparquet | 1,000 rows | ours | DHS | 10 | 0.09 | 0.11 | 0.59 |
| fastparquet | 1,000 rows | ours | Synthetic | 3 | 0.01 | 0.01 | 0.09 |
| fastparquet | read + pass | pyarrow | NSFG | 36 | 0.34 | 0.39 | 1.03 |
| fastparquet | read + pass | pyarrow | DHS | 10 | 0.30 | 0.39 | 1.16 |
| fastparquet | read + pass | pyarrow | Synthetic | 3 | 0.25 | 0.53 | 1.32 |
| fastparquet | read + pass | polars | NSFG | 36 | 0.35 | 0.41 | 1.04 |
| fastparquet | read + pass | polars | DHS | 10 | 0.31 | 0.40 | 1.16 |
| fastparquet | read + pass | polars | Synthetic | 3 | 0.22 | 0.58 | 1.25 |
| fastparquet | read + pass | ours | NSFG | 36 | 0.37 | 0.42 | 1.06 |
| fastparquet | read + pass | ours | DHS | 10 | 0.33 | 0.42 | 1.18 |
| fastparquet | read + pass | ours | Synthetic | 3 | 0.31 | 0.64 | 1.25 |
| fastparquet | write, defaults | dta | NSFG | 36 | 0.17 | 0.25 | 0.97 |
| fastparquet | write, defaults | dta | DHS | 10 | 0.14 | 0.27 | 0.98 |
| fastparquet | write, defaults | dta | Synthetic | 3 | 0.41 | 1.15 | 0.64 |
| fastparquet | write, zstd 3 | dta | NSFG | 36 | 0.17 | 0.26 | 0.97 |
| fastparquet | write, zstd 3 | dta | DHS | 10 | 0.15 | 0.27 | 0.99 |
| fastparquet | write, zstd 3 | dta | Synthetic | 3 | 0.25 | 0.69 | 0.59 |
| polars → pandas | whole file | pyarrow | NSFG | 36 | 0.45 | 0.24 | 0.65 |
| polars → pandas | whole file | pyarrow | DHS | 10 | 0.66 | 0.27 | 0.63 |
| polars → pandas | whole file | pyarrow | Synthetic | 3 | 0.49 | 0.53 | 0.53 |
| polars → pandas | whole file | polars | NSFG | 36 | 0.46 | 0.26 | 0.65 |
| polars → pandas | whole file | polars | DHS | 10 | 0.67 | 0.27 | 0.63 |
| polars → pandas | whole file | polars | Synthetic | 3 | 0.55 | 0.64 | 0.42 |
| polars → pandas | whole file | ours | NSFG | 36 | 0.51 | 0.26 | 0.66 |
| polars → pandas | whole file | ours | DHS | 10 | 0.73 | 0.28 | 0.63 |
| polars → pandas | whole file | ours | Synthetic | 3 | 0.46 | 0.48 | 0.44 |
| polars → pandas | five columns | pyarrow | NSFG | 36 | 0.30 | 0.12 | 0.67 |
| polars → pandas | five columns | pyarrow | DHS | 10 | 0.44 | 0.19 | 0.66 |
| polars → pandas | five columns | pyarrow | Synthetic | 3 | 0.70 | 0.56 | 0.59 |
| polars → pandas | five columns | polars | NSFG | 36 | 0.30 | 0.12 | 0.67 |
| polars → pandas | five columns | polars | DHS | 10 | 0.41 | 0.18 | 0.66 |
| polars → pandas | five columns | polars | Synthetic | 3 | 0.97 | 0.60 | 0.41 |
| polars → pandas | five columns | ours | NSFG | 36 | 0.36 | 0.15 | 0.67 |
| polars → pandas | five columns | ours | DHS | 10 | 0.53 | 0.23 | 0.66 |
| polars → pandas | five columns | ours | Synthetic | 3 | 0.67 | 0.47 | 0.42 |
| polars → pandas | 1,000 rows | pyarrow | NSFG | 36 | 0.36 | 0.16 | 0.66 |
| polars → pandas | 1,000 rows | pyarrow | DHS | 10 | 0.50 | 0.23 | 0.65 |
| polars → pandas | 1,000 rows | pyarrow | Synthetic | 3 | 0.55 | 0.16 | 0.23 |
| polars → pandas | 1,000 rows | polars | NSFG | 36 | 0.39 | 0.19 | 0.66 |
| polars → pandas | 1,000 rows | polars | DHS | 10 | 0.54 | 0.25 | 0.65 |
| polars → pandas | 1,000 rows | polars | Synthetic | 3 | 0.56 | 0.30 | 0.50 |
| polars → pandas | 1,000 rows | ours | NSFG | 36 | 0.43 | 0.19 | 0.68 |
| polars → pandas | 1,000 rows | ours | DHS | 10 | 0.61 | 0.26 | 0.67 |
| polars → pandas | 1,000 rows | ours | Synthetic | 3 | 0.50 | 0.16 | 0.37 |
| polars → pandas | read + pass | pyarrow | NSFG | 36 | 0.70 | 0.42 | 0.65 |
| polars → pandas | read + pass | pyarrow | DHS | 10 | 0.88 | 0.43 | 0.63 |
| polars → pandas | read + pass | pyarrow | Synthetic | 3 | 0.76 | 0.61 | 0.68 |
| polars → pandas | read + pass | polars | NSFG | 36 | 0.70 | 0.42 | 0.65 |
| polars → pandas | read + pass | polars | DHS | 10 | 0.88 | 0.43 | 0.63 |
| polars → pandas | read + pass | polars | Synthetic | 3 | 0.73 | 0.70 | 0.55 |
| polars → pandas | read + pass | ours | NSFG | 36 | 0.73 | 0.43 | 0.67 |
| polars → pandas | read + pass | ours | DHS | 10 | 0.91 | 0.44 | 0.64 |
| polars → pandas | read + pass | ours | Synthetic | 3 | 0.74 | 0.57 | 0.57 |
| polars → pandas | write, defaults | dta | NSFG | 36 | 0.57 | 0.30 | 0.69 |
| polars → pandas | write, defaults | dta | DHS | 10 | 0.65 | 0.49 | 0.76 |
| polars → pandas | write, defaults | dta | Synthetic | 3 | 1.21 | 0.59 | 0.81 |
| polars → pandas | write, zstd 3 | dta | NSFG | 36 | 0.67 | 0.35 | 0.69 |
| polars → pandas | write, zstd 3 | dta | DHS | 10 | 0.72 | 0.54 | 0.77 |
| polars → pandas | write, zstd 3 | dta | Synthetic | 3 | 1.86 | 0.88 | 0.83 |

## Ratios against reads into Arrow and polars types (published, not gated)

| against | case | input | family | files | wall | CPU | peak RSS |
|---|---|---|---|---|---|---|---|
| pyarrow Table | whole file | pyarrow | NSFG | 36 | 0.21 | 0.16 | 0.95 |
| pyarrow Table | whole file | pyarrow | DHS | 10 | 0.65 | 0.35 | 1.16 |
| pyarrow Table | whole file | pyarrow | Synthetic | 3 | 0.76 | 0.67 | 0.71 |
| pyarrow Table | five columns | pyarrow | NSFG | 36 | 0.05 | 0.05 | 0.90 |
| pyarrow Table | five columns | pyarrow | DHS | 10 | 0.09 | 0.09 | 0.87 |
| pyarrow Table | five columns | pyarrow | Synthetic | 3 | 0.68 | 0.51 | 0.84 |
| pyarrow Table | 1,000 rows | pyarrow | NSFG | 36 | 0.13 | 0.08 | 0.68 |
| pyarrow Table | 1,000 rows | pyarrow | DHS | 10 | 0.30 | 0.11 | 0.43 |
| pyarrow Table | 1,000 rows | pyarrow | Synthetic | 3 | 0.04 | 0.01 | 0.05 |
| polars DataFrame | whole file | pyarrow | NSFG | 36 | 0.81 | 0.64 | 0.83 |
| polars DataFrame | whole file | pyarrow | DHS | 10 | 1.69 | 1.54 | 1.11 |
| polars DataFrame | whole file | pyarrow | Synthetic | 3 | 2.04 | 1.19 | 0.92 |
| polars DataFrame | five columns | pyarrow | NSFG | 36 | 0.36 | 0.14 | 0.67 |
| polars DataFrame | five columns | pyarrow | DHS | 10 | 0.52 | 0.24 | 0.67 |
| polars DataFrame | five columns | pyarrow | Synthetic | 3 | 2.54 | 1.12 | 0.91 |
| polars DataFrame | 1,000 rows | pyarrow | NSFG | 36 | 0.73 | 0.40 | 0.71 |
| polars DataFrame | 1,000 rows | pyarrow | DHS | 10 | 1.53 | 0.92 | 0.74 |
| polars DataFrame | 1,000 rows | pyarrow | Synthetic | 3 | 0.64 | 0.17 | 0.23 |
| DuckDB → Arrow | whole file | pyarrow | NSFG | 36 | 0.26 | 0.37 | 0.65 |
| DuckDB → Arrow | whole file | pyarrow | DHS | 10 | 0.19 | 0.35 | 0.63 |
| DuckDB → Arrow | whole file | pyarrow | Synthetic | 2 | 1.81 | 0.68 | 0.84 |
| DuckDB → Arrow | five columns | pyarrow | NSFG | 36 | 0.32 | 0.30 | 0.77 |
| DuckDB → Arrow | five columns | pyarrow | DHS | 10 | 0.30 | 0.29 | 0.76 |
| DuckDB → Arrow | five columns | pyarrow | Synthetic | 3 | 1.54 | 0.67 | 0.85 |
| DuckDB → Arrow | 1,000 rows | pyarrow | NSFG | 36 | 0.15 | 0.05 | 0.30 |
| DuckDB → Arrow | 1,000 rows | pyarrow | DHS | 10 | 0.13 | 0.04 | 0.16 |
| DuckDB → Arrow | 1,000 rows | pyarrow | Synthetic | 2 | 0.12 | 0.09 | 0.60 |

## Misses

- 2 wall: pyarrow five polars long.dta: 185 ms vs 88 ms (2.11x)
- 2 wall: pyarrow five ours long.dta: 113 ms vs 84 ms (1.35x)
- 2 wall: pandas five polars long.dta: 185 ms vs 93 ms (1.99x)
- 2 wall: pandas five ours long.dta: 113 ms vs 86 ms (1.32x)
- 1 RSS: fastparquet full pyarrow dhs: geometric mean 1.51x
- 2 RSS: fastparquet full pyarrow groups.dta: 621 vs 314 MB (1.98x)
- 2 RSS: fastparquet full pyarrow 1995_FemResp: 604 vs 425 MB (1.42x)
- 2 RSS: fastparquet full pyarrow 2006_2010_FemResp: 459 vs 336 MB (1.37x)
- 2 RSS: fastparquet full pyarrow 2006_2010_Male: 342 vs 273 MB (1.25x)
- 2 RSS: fastparquet full pyarrow Senegal 2019 wm: 467 vs 291 MB (1.60x)
- 2 RSS: fastparquet full pyarrow Senegal 2019 bh: 304 vs 227 MB (1.34x)
- 2 RSS: fastparquet full pyarrow Turkey 2013 wm: 487 vs 280 MB (1.74x)
- 2 RSS: fastparquet full pyarrow Turkey 2013 bh: 274 vs 199 MB (1.38x)
- 2 RSS: fastparquet full pyarrow Tajikistan 2017 wm: 557 vs 321 MB (1.74x)
- 2 RSS: fastparquet full pyarrow Tajikistan 2017 bh: 295 vs 225 MB (1.31x)
- 2 RSS: fastparquet full pyarrow Myanmar 2016 wm: 631 vs 335 MB (1.88x)
- 2 RSS: fastparquet full pyarrow Myanmar 2016 bh: 314 vs 226 MB (1.38x)
- 2 RSS: fastparquet full pyarrow Dominican Republic 2013 wm: 408 vs 264 MB (1.54x)
- 2 RSS: fastparquet full pyarrow Dominican Republic 2013 bh: 264 vs 206 MB (1.29x)
- 1 RSS: fastparquet full polars dhs: geometric mean 1.52x
- 2 RSS: fastparquet full polars groups.dta: 612 vs 316 MB (1.94x)
- 2 RSS: fastparquet full polars 1995_FemResp: 603 vs 421 MB (1.43x)
- 2 RSS: fastparquet full polars 2006_2010_FemResp: 459 vs 334 MB (1.38x)
- 2 RSS: fastparquet full polars 2006_2010_Male: 341 vs 271 MB (1.26x)
- 2 RSS: fastparquet full polars Senegal 2019 wm: 466 vs 288 MB (1.62x)
- 2 RSS: fastparquet full polars Senegal 2019 bh: 304 vs 227 MB (1.34x)
- 2 RSS: fastparquet full polars Turkey 2013 wm: 487 vs 278 MB (1.75x)
- 2 RSS: fastparquet full polars Turkey 2013 bh: 274 vs 199 MB (1.38x)
- 2 RSS: fastparquet full polars Tajikistan 2017 wm: 557 vs 318 MB (1.75x)
- 2 RSS: fastparquet full polars Tajikistan 2017 bh: 295 vs 223 MB (1.32x)
- 2 RSS: fastparquet full polars Myanmar 2016 wm: 632 vs 333 MB (1.90x)
- 2 RSS: fastparquet full polars Myanmar 2016 bh: 314 vs 225 MB (1.39x)
- 2 RSS: fastparquet full polars Dominican Republic 2013 wm: 407 vs 262 MB (1.56x)
- 2 RSS: fastparquet full polars Dominican Republic 2013 bh: 264 vs 206 MB (1.29x)
- 1 RSS: fastparquet full ours nsfg: geometric mean 1.06x
- 1 RSS: fastparquet full ours dhs: geometric mean 1.54x
- 2 RSS: fastparquet full ours groups.dta: 615 vs 319 MB (1.93x)
- 2 RSS: fastparquet full ours 1995_FemResp: 636 vs 426 MB (1.49x)
- 2 RSS: fastparquet full ours 2006_2010_FemResp: 481 vs 337 MB (1.43x)
- 2 RSS: fastparquet full ours 2006_2010_Male: 351 vs 271 MB (1.29x)
- 2 RSS: fastparquet full ours Senegal 2019 wm: 477 vs 287 MB (1.66x)
- 2 RSS: fastparquet full ours Senegal 2019 bh: 307 vs 226 MB (1.36x)
- 2 RSS: fastparquet full ours Turkey 2013 wm: 498 vs 276 MB (1.81x)
- 2 RSS: fastparquet full ours Turkey 2013 bh: 277 vs 198 MB (1.40x)
- 2 RSS: fastparquet full ours Tajikistan 2017 wm: 571 vs 317 MB (1.80x)
- 2 RSS: fastparquet full ours Tajikistan 2017 bh: 298 vs 223 MB (1.33x)
- 2 RSS: fastparquet full ours Myanmar 2016 wm: 643 vs 332 MB (1.94x)
- 2 RSS: fastparquet full ours Myanmar 2016 bh: 317 vs 225 MB (1.41x)
- 2 RSS: fastparquet full ours Dominican Republic 2013 wm: 416 vs 261 MB (1.59x)
- 2 RSS: fastparquet full ours Dominican Republic 2013 bh: 267 vs 206 MB (1.29x)
- 2 RSS: fastparquet five pyarrow groups.dta: 621 vs 313 MB (1.99x)
- 2 RSS: fastparquet five polars groups.dta: 612 vs 316 MB (1.94x)
- 2 RSS: fastparquet five ours groups.dta: 614 vs 316 MB (1.94x)
- 1 RSS: fastparquet pass pyarrow dhs: geometric mean 1.16x
- 2 RSS: fastparquet pass pyarrow groups.dta: 1030 vs 563 MB (1.83x)
- 2 RSS: fastparquet pass pyarrow 2006_2010_FemResp: 460 vs 359 MB (1.28x)
- 1 RSS: fastparquet pass polars dhs: geometric mean 1.16x
- 2 RSS: fastparquet pass polars groups.dta: 985 vs 566 MB (1.74x)
- 2 RSS: fastparquet pass polars 2006_2010_FemResp: 460 vs 359 MB (1.28x)
- 1 RSS: fastparquet pass ours nsfg: geometric mean 1.06x
- 1 RSS: fastparquet pass ours dhs: geometric mean 1.18x
- 2 RSS: fastparquet pass ours groups.dta: 988 vs 565 MB (1.75x)
- 2 RSS: fastparquet pass ours 1995_FemResp: 637 vs 496 MB (1.28x)
- 2 RSS: fastparquet pass ours 2006_2010_FemResp: 483 vs 363 MB (1.33x)
- 2 RSS: fastparquet pass ours Tajikistan 2017 wm: 572 vs 457 MB (1.25x)
- 3 CPU: fastparquet write dta wide.dta: 4.394 s vs 1.128 s, speedup 1.63 allows 1.842 s
- 2 wall: polars five polars long.dta: 185 ms vs 120 ms (1.54x)
- 2 wall: polars write dta long.dta: 643 ms vs 393 ms (1.64x)
- 2 wall: polars write dta groups.dta: 168 ms vs 127 ms (1.32x)
- 2 wall: polars zstd dta long.dta: 1.11 s vs 394 ms (2.83x)
- 2 wall: polars zstd dta wide.dta: 1.46 s vs 835 ms (1.75x)
- 3 CPU: polars zstd dta wide.dta: 9.348 s vs 7.247 s, speedup 0.57 allows 8.334 s
- 2 wall: polars zstd dta groups.dta: 173 ms vs 132 ms (1.31x)

## Every file

Each cell: wall / CPU / peak RSS (median of the runs).

### long.dta

10,000,000 rows, 12 columns; .dta 740.0 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 116 ms / 0.46 s / 1314 MB | 149 ms / 0.75 s / 2562 MB | 151 ms / 0.75 s / 2546 MB | 558 ms / 0.56 s / 1194 MB | 168 ms / 0.76 s / 2472 MB | 126 ms / 0.58 s / 1816 MB | 64 ms / 0.38 s / 1432 MB | 74 ms / 0.65 s / 1886 MB |
| whole file | polars | 183 ms / 0.80 s / 1163 MB | 151 ms / 1.21 s / 2536 MB | 152 ms / 1.21 s / 2535 MB | 888 ms / 0.89 s / 1150 MB | 187 ms / 1.28 s / 3014 MB | – | – | – |
| whole file | ours | 97 ms / 0.41 s / 1180 MB | 127 ms / 0.83 s / 2516 MB | 129 ms / 0.82 s / 2509 MB | 427 ms / 0.43 s / 1158 MB | 145 ms / 0.79 s / 2793 MB | – | – | – |
| five columns | pyarrow | 119 ms / 0.26 s / 786 MB | 115 ms / 0.36 s / 1206 MB | 116 ms / 0.37 s / 1200 MB | 329 ms / 0.33 s / 716 MB | 102 ms / 0.39 s / 1252 MB | 93 ms / 0.30 s / 876 MB | 33 ms / 0.25 s / 858 MB | 47 ms / 0.37 s / 894 MB |
| five columns | polars | 185 ms / 0.38 s / 618 MB | 88 ms / 0.64 s / 1184 MB | 93 ms / 0.63 s / 1181 MB | 468 ms / 0.47 s / 667 MB | 120 ms / 0.63 s / 1780 MB | – | – | – |
| five columns | ours | 113 ms / 0.24 s / 633 MB | 84 ms / 0.50 s / 1171 MB | 86 ms / 0.47 s / 1164 MB | 274 ms / 0.27 s / 670 MB | 99 ms / 0.41 s / 1760 MB | – | – | – |
| 1,000 rows | pyarrow | 6 ms / 0.01 s / 118 MB | 121 ms / 0.59 s / 1845 MB | 151 ms / 0.76 s / 2551 MB | 561 ms / 0.56 s / 1194 MB | 6 ms / 0.02 s / 232 MB | 120 ms / 0.58 s / 1836 MB | 5 ms / 0.02 s / 232 MB | 17 ms / 0.02 s / 237 MB |
| 1,000 rows | polars | 7 ms / 0.01 s / 113 MB | 132 ms / 1.03 s / 1860 MB | 157 ms / 1.21 s / 2526 MB | 887 ms / 0.89 s / 1150 MB | 9 ms / 0.02 s / 173 MB | – | – | – |
| 1,000 rows | ours | 2 ms / 0.00 s / 114 MB | 96 ms / 0.66 s / 1757 MB | 136 ms / 0.80 s / 2504 MB | 426 ms / 0.43 s / 1158 MB | 4 ms / 0.01 s / 182 MB | – | – | – |
| read + pass | pyarrow | 292 ms / 0.63 s / 1787 MB | 310 ms / 0.90 s / 2840 MB | 311 ms / 0.93 s / 2848 MB | 1.20 s / 1.20 s / 1453 MB | 331 ms / 0.92 s / 2464 MB | – | – | – |
| read + pass | polars | 360 ms / 0.98 s / 1652 MB | 316 ms / 1.37 s / 2835 MB | 318 ms / 1.35 s / 2832 MB | 1.40 s / 1.39 s / 1492 MB | 353 ms / 1.41 s / 3010 MB | – | – | – |
| read + pass | ours | 273 ms / 0.58 s / 1675 MB | 289 ms / 0.99 s / 2809 MB | 293 ms / 1.00 s / 2809 MB | 932 ms / 0.93 s / 1499 MB | 317 ms / 0.98 s / 2771 MB | – | – | – |
| write, defaults | dta | 643 ms / 1.22 s / 2108 MB | 1.60 s / 1.74 s / 2112 MB | – | 1.17 s / 1.15 s / 2939 MB | 393 ms / 2.19 s / 2177 MB | – | – | – |
| write, zstd 3 | dta | 1.11 s / 1.94 s / 2109 MB | 2.25 s / 2.39 s / 2111 MB | – | 2.70 s / 2.68 s / 3279 MB | 394 ms / 2.20 s / 2181 MB | – | – | – |

### wide.dta

1,500,000 rows, 400 columns; .dta 4800.3 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 195 ms / 1.52 s / 5026 MB | 439 ms / 4.41 s / 14976 MB | 438 ms / 4.55 s / 14977 MB | 1.52 s / 1.52 s / 4933 MB | 508 ms / 4.44 s / 10513 MB | 280 ms / 2.81 s / 10172 MB | 211 ms / 1.93 s / 7561 MB | – |
| whole file | polars | 571 ms / 4.48 s / 4931 MB | 674 ms / 6.97 s / 14575 MB | 649 ms / 7.02 s / 14577 MB | 4.64 s / 4.64 s / 4933 MB | 1.40 s / 7.48 s / 12226 MB | – | – | – |
| whole file | ours | 166 ms / 1.28 s / 4948 MB | 483 ms / 5.39 s / 14743 MB | 485 ms / 5.32 s / 14746 MB | 785 ms / 0.78 s / 4926 MB | 478 ms / 4.02 s / 12171 MB | – | – | – |
| five columns | pyarrow | 10 ms / 0.02 s / 192 MB | 30 ms / 0.08 s / 338 MB | 31 ms / 0.09 s / 338 MB | 26 ms / 0.03 s / 192 MB | 15 ms / 0.05 s / 353 MB | 26 ms / 0.07 s / 281 MB | 8 ms / 0.02 s / 293 MB | 12 ms / 0.03 s / 278 MB |
| five columns | polars | 31 ms / 0.06 s / 177 MB | 35 ms / 0.14 s / 322 MB | 34 ms / 0.14 s / 322 MB | 85 ms / 0.09 s / 191 MB | 22 ms / 0.11 s / 433 MB | – | – | – |
| five columns | ours | 9 ms / 0.02 s / 181 MB | 31 ms / 0.11 s / 329 MB | 31 ms / 0.11 s / 330 MB | 21 ms / 0.02 s / 184 MB | 14 ms / 0.06 s / 422 MB | – | – | – |
| 1,000 rows | pyarrow | 81 ms / 0.16 s / 122 MB | 279 ms / 2.69 s / 10172 MB | 430 ms / 4.53 s / 14972 MB | 1.52 s / 1.52 s / 4933 MB | 94 ms / 0.78 s / 3681 MB | 284 ms / 2.84 s / 10165 MB | 93 ms / 0.82 s / 3684 MB | – |
| 1,000 rows | polars | 104 ms / 0.20 s / 121 MB | 497 ms / 5.35 s / 9783 MB | 665 ms / 6.90 s / 14585 MB | 4.65 s / 4.65 s / 4932 MB | 118 ms / 0.27 s / 431 MB | – | – | – |
| 1,000 rows | ours | 17 ms / 0.03 s / 120 MB | 335 ms / 3.66 s / 9944 MB | 477 ms / 5.32 s / 14747 MB | 770 ms / 0.77 s / 4926 MB | 28 ms / 0.18 s / 1023 MB | – | – | – |
| read + pass | pyarrow | 717 ms / 2.02 s / 5040 MB | 926 ms / 4.80 s / 14979 MB | 924 ms / 4.81 s / 14989 MB | 2.04 s / 2.04 s / 4949 MB | 997 ms / 4.88 s / 10491 MB | – | – | – |
| read + pass | polars | 1.08 s / 4.99 s / 4946 MB | 1.16 s / 7.38 s / 14604 MB | 1.16 s / 7.44 s / 14591 MB | 5.13 s / 5.13 s / 4936 MB | 1.88 s / 7.86 s / 11367 MB | – | – | – |
| read + pass | ours | 672 ms / 1.79 s / 4961 MB | 976 ms / 5.69 s / 14754 MB | 985 ms / 5.60 s / 14762 MB | 1.27 s / 1.27 s / 4938 MB | 971 ms / 4.44 s / 12137 MB | – | – | – |
| write, defaults | dta | 714 ms / 4.39 s / 5056 MB | 6.57 s / 7.66 s / 5020 MB | – | 1.17 s / 1.13 s / 4979 MB | 876 ms / 7.17 s / 6902 MB | – | – | – |
| write, zstd 3 | dta | 1.46 s / 9.35 s / 5048 MB | 10.19 s / 11.23 s / 5020 MB | – | 5.64 s / 5.61 s / 5698 MB | 835 ms / 7.25 s / 6396 MB | – | – | – |

### groups.dta

15,000,000 rows, 2 columns; .dta 270.0 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 54 ms / 0.13 s / 621 MB | 120 ms / 0.23 s / 795 MB | 120 ms / 0.23 s / 807 MB | 178 ms / 0.18 s / 314 MB | 122 ms / 0.19 s / 1059 MB | 79 ms / 0.19 s / 617 MB | 11 ms / 0.08 s / 494 MB | 26 ms / 0.20 s / 607 MB |
| whole file | polars | 52 ms / 0.14 s / 612 MB | 93 ms / 0.32 s / 820 MB | 89 ms / 0.34 s / 819 MB | 164 ms / 0.16 s / 316 MB | 123 ms / 0.20 s / 1301 MB | – | – | – |
| whole file | ours | 52 ms / 0.13 s / 615 MB | 98 ms / 0.32 s / 879 MB | 102 ms / 0.32 s / 888 MB | 154 ms / 0.15 s / 319 MB | 123 ms / 0.19 s / 1249 MB | – | – | – |
| five columns | pyarrow | 55 ms / 0.13 s / 621 MB | 122 ms / 0.24 s / 797 MB | 122 ms / 0.24 s / 795 MB | 179 ms / 0.18 s / 313 MB | 124 ms / 0.19 s / 1058 MB | 85 ms / 0.22 s / 644 MB | 15 ms / 0.08 s / 494 MB | 31 ms / 0.20 s / 605 MB |
| five columns | polars | 51 ms / 0.14 s / 612 MB | 95 ms / 0.33 s / 827 MB | 91 ms / 0.34 s / 827 MB | 163 ms / 0.16 s / 316 MB | 123 ms / 0.20 s / 1302 MB | – | – | – |
| five columns | ours | 52 ms / 0.13 s / 614 MB | 97 ms / 0.31 s / 882 MB | 101 ms / 0.32 s / 894 MB | 152 ms / 0.15 s / 316 MB | 121 ms / 0.19 s / 1291 MB | – | – | – |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 111 MB | 79 ms / 0.19 s / 625 MB | 122 ms / 0.23 s / 795 MB | 176 ms / 0.18 s / 313 MB | 2 ms / 0.01 s / 163 MB | 82 ms / 0.20 s / 638 MB | 2 ms / 0.01 s / 162 MB | 11 ms / 0.01 s / 152 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 111 MB | 54 ms / 0.31 s / 702 MB | 91 ms / 0.34 s / 823 MB | 163 ms / 0.16 s / 316 MB | 2 ms / 0.01 s / 163 MB | – | – | – |
| 1,000 rows | ours | 1 ms / 0.00 s / 111 MB | 58 ms / 0.27 s / 689 MB | 100 ms / 0.32 s / 875 MB | 155 ms / 0.15 s / 315 MB | 2 ms / 0.01 s / 163 MB | – | – | – |
| read + pass | pyarrow | 146 ms / 0.23 s / 1030 MB | 212 ms / 0.33 s / 1169 MB | 209 ms / 0.32 s / 1175 MB | 804 ms / 0.80 s / 563 MB | 214 ms / 0.28 s / 1130 MB | – | – | – |
| read + pass | polars | 143 ms / 0.23 s / 985 MB | 181 ms / 0.43 s / 1194 MB | 182 ms / 0.42 s / 1187 MB | 775 ms / 0.77 s / 566 MB | 212 ms / 0.29 s / 1381 MB | – | – | – |
| read + pass | ours | 143 ms / 0.22 s / 988 MB | 191 ms / 0.41 s / 1261 MB | 191 ms / 0.42 s / 1268 MB | 768 ms / 0.77 s / 565 MB | 213 ms / 0.28 s / 1331 MB | – | – | – |
| write, defaults | dta | 168 ms / 0.31 s / 1134 MB | 603 ms / 0.60 s / 1135 MB | – | 846 ms / 0.84 s / 3117 MB | 127 ms / 0.51 s / 1487 MB | – | – | – |
| write, zstd 3 | dta | 173 ms / 0.32 s / 1133 MB | 617 ms / 0.62 s / 1135 MB | – | 1.16 s / 1.16 s / 3117 MB | 132 ms / 0.53 s / 1488 MB | – | – | – |

### 1973_FemResp

9,797 rows, 450 columns; .dta 5.7 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 7 ms / 0.01 s / 144 MB | 29 ms / 0.06 s / 182 MB | 28 ms / 0.06 s / 182 MB | 39 ms / 0.04 s / 142 MB | 13 ms / 0.03 s / 216 MB | 23 ms / 0.04 s / 151 MB | 7 ms / 0.01 s / 184 MB | 24 ms / 0.02 s / 212 MB |
| whole file | polars | 7 ms / 0.01 s / 143 MB | 30 ms / 0.07 s / 182 MB | 27 ms / 0.07 s / 182 MB | 42 ms / 0.04 s / 142 MB | 14 ms / 0.03 s / 216 MB | – | – | – |
| whole file | ours | 8 ms / 0.01 s / 144 MB | 27 ms / 0.06 s / 183 MB | 28 ms / 0.07 s / 183 MB | 39 ms / 0.04 s / 142 MB | 12 ms / 0.03 s / 217 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 110 MB | 19 ms / 0.02 s / 122 MB | 19 ms / 0.02 s / 122 MB | 5 ms / 0.01 s / 118 MB | 3 ms / 0.01 s / 165 MB | 18 ms / 0.02 s / 121 MB | 2 ms / 0.01 s / 163 MB | 2 ms / 0.00 s / 142 MB |
| five columns | polars | 1 ms / 0.00 s / 111 MB | 19 ms / 0.02 s / 122 MB | 19 ms / 0.02 s / 122 MB | 5 ms / 0.01 s / 119 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| five columns | ours | 1 ms / 0.00 s / 110 MB | 18 ms / 0.02 s / 122 MB | 19 ms / 0.02 s / 122 MB | 5 ms / 0.01 s / 118 MB | 3 ms / 0.01 s / 166 MB | – | – | – |
| 1,000 rows | pyarrow | 5 ms / 0.00 s / 114 MB | 28 ms / 0.05 s / 155 MB | 28 ms / 0.07 s / 182 MB | 40 ms / 0.04 s / 142 MB | 9 ms / 0.02 s / 173 MB | 24 ms / 0.05 s / 152 MB | 4 ms / 0.01 s / 167 MB | 21 ms / 0.07 s / 269 MB |
| 1,000 rows | polars | 6 ms / 0.01 s / 115 MB | 27 ms / 0.06 s / 155 MB | 28 ms / 0.07 s / 182 MB | 42 ms / 0.04 s / 141 MB | 11 ms / 0.02 s / 172 MB | – | – | – |
| 1,000 rows | ours | 6 ms / 0.01 s / 117 MB | 26 ms / 0.05 s / 157 MB | 28 ms / 0.06 s / 182 MB | 39 ms / 0.04 s / 141 MB | 9 ms / 0.02 s / 174 MB | – | – | – |
| read + pass | pyarrow | 22 ms / 0.03 s / 144 MB | 42 ms / 0.08 s / 183 MB | 42 ms / 0.08 s / 183 MB | 60 ms / 0.06 s / 143 MB | 27 ms / 0.05 s / 217 MB | – | – | – |
| read + pass | polars | 23 ms / 0.03 s / 145 MB | 42 ms / 0.08 s / 182 MB | 42 ms / 0.08 s / 183 MB | 62 ms / 0.06 s / 142 MB | 29 ms / 0.05 s / 217 MB | – | – | – |
| read + pass | ours | 23 ms / 0.03 s / 147 MB | 42 ms / 0.08 s / 184 MB | 42 ms / 0.08 s / 184 MB | 60 ms / 0.06 s / 142 MB | 27 ms / 0.05 s / 218 MB | – | – | – |
| write, defaults | dta | 17 ms / 0.03 s / 142 MB | 64 ms / 0.06 s / 150 MB | – | 113 ms / 0.11 s / 148 MB | 29 ms / 0.08 s / 212 MB | – | – | – |
| write, zstd 3 | dta | 19 ms / 0.04 s / 144 MB | 69 ms / 0.07 s / 150 MB | – | 131 ms / 0.13 s / 149 MB | 30 ms / 0.09 s / 211 MB | – | – | – |

### 1976_FemResp

8,611 rows, 468 columns; .dta 6.0 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 6 ms / 0.01 s / 138 MB | 26 ms / 0.06 s / 178 MB | 27 ms / 0.06 s / 179 MB | 39 ms / 0.04 s / 142 MB | 12 ms / 0.03 s / 212 MB | 24 ms / 0.05 s / 153 MB | 7 ms / 0.01 s / 185 MB | 22 ms / 0.02 s / 216 MB |
| whole file | polars | 7 ms / 0.01 s / 140 MB | 27 ms / 0.06 s / 179 MB | 27 ms / 0.06 s / 179 MB | 42 ms / 0.04 s / 140 MB | 14 ms / 0.03 s / 212 MB | – | – | – |
| whole file | ours | 8 ms / 0.01 s / 143 MB | 27 ms / 0.06 s / 179 MB | 27 ms / 0.06 s / 180 MB | 39 ms / 0.04 s / 142 MB | 12 ms / 0.03 s / 213 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 110 MB | 18 ms / 0.02 s / 121 MB | 19 ms / 0.02 s / 122 MB | 6 ms / 0.01 s / 119 MB | 3 ms / 0.01 s / 165 MB | 18 ms / 0.02 s / 120 MB | 2 ms / 0.01 s / 163 MB | 2 ms / 0.00 s / 141 MB |
| five columns | polars | 1 ms / 0.00 s / 110 MB | 18 ms / 0.02 s / 122 MB | 19 ms / 0.02 s / 123 MB | 5 ms / 0.01 s / 118 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| five columns | ours | 1 ms / 0.00 s / 112 MB | 18 ms / 0.02 s / 124 MB | 19 ms / 0.02 s / 123 MB | 5 ms / 0.01 s / 119 MB | 3 ms / 0.01 s / 167 MB | – | – | – |
| 1,000 rows | pyarrow | 5 ms / 0.00 s / 114 MB | 27 ms / 0.06 s / 157 MB | 27 ms / 0.06 s / 179 MB | 39 ms / 0.04 s / 140 MB | 9 ms / 0.02 s / 172 MB | 24 ms / 0.05 s / 153 MB | 5 ms / 0.01 s / 167 MB | 21 ms / 0.09 s / 292 MB |
| 1,000 rows | polars | 6 ms / 0.01 s / 114 MB | 26 ms / 0.05 s / 157 MB | 27 ms / 0.06 s / 179 MB | 42 ms / 0.04 s / 140 MB | 11 ms / 0.02 s / 172 MB | – | – | – |
| 1,000 rows | ours | 7 ms / 0.01 s / 119 MB | 26 ms / 0.05 s / 158 MB | 27 ms / 0.06 s / 180 MB | 39 ms / 0.04 s / 141 MB | 9 ms / 0.02 s / 173 MB | – | – | – |
| read + pass | pyarrow | 21 ms / 0.03 s / 139 MB | 40 ms / 0.07 s / 180 MB | 41 ms / 0.07 s / 179 MB | 57 ms / 0.06 s / 141 MB | 26 ms / 0.04 s / 213 MB | – | – | – |
| read + pass | polars | 22 ms / 0.03 s / 139 MB | 41 ms / 0.08 s / 180 MB | 42 ms / 0.07 s / 179 MB | 60 ms / 0.06 s / 140 MB | 28 ms / 0.04 s / 213 MB | – | – | – |
| read + pass | ours | 23 ms / 0.03 s / 145 MB | 41 ms / 0.08 s / 180 MB | 41 ms / 0.07 s / 181 MB | 57 ms / 0.06 s / 141 MB | 26 ms / 0.04 s / 213 MB | – | – | – |
| write, defaults | dta | 28 ms / 0.03 s / 144 MB | 62 ms / 0.06 s / 150 MB | – | 110 ms / 0.11 s / 148 MB | 28 ms / 0.08 s / 210 MB | – | – | – |
| write, zstd 3 | dta | 33 ms / 0.03 s / 144 MB | 68 ms / 0.07 s / 149 MB | – | 129 ms / 0.13 s / 148 MB | 27 ms / 0.08 s / 212 MB | – | – | – |

### 1976_PSU

8,611 rows, 3 columns; .dta 0.0 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 17 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 116 MB | 2 ms / 0.01 s / 162 MB | 17 ms / 0.02 s / 119 MB | 2 ms / 0.01 s / 160 MB | 1 ms / 0.00 s / 140 MB |
| whole file | polars | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 119 MB | 17 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| whole file | ours | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 17 ms / 0.02 s / 119 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 161 MB | – | – | – |
| five columns | pyarrow | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 18 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | 17 ms / 0.02 s / 119 MB | 2 ms / 0.01 s / 161 MB | 1 ms / 0.00 s / 141 MB |
| five columns | polars | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 17 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| five columns | ours | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 17 ms / 0.02 s / 119 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 161 MB | – | – | – |
| 1,000 rows | pyarrow | 0 ms / 0.00 s / 109 MB | 17 ms / 0.02 s / 120 MB | 18 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 161 MB | 17 ms / 0.02 s / 119 MB | 2 ms / 0.01 s / 160 MB | 1 ms / 0.00 s / 148 MB |
| 1,000 rows | polars | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 17 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 161 MB | – | – | – |
| 1,000 rows | ours | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 119 MB | 17 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 161 MB | – | – | – |
| read + pass | pyarrow | 1 ms / 0.00 s / 110 MB | 18 ms / 0.02 s / 120 MB | 18 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 116 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| read + pass | polars | 1 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 18 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| read + pass | ours | 1 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 18 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| write, defaults | dta | 1 ms / 0.00 s / 110 MB | 2 ms / 0.00 s / 117 MB | – | 2 ms / 0.00 s / 117 MB | 3 ms / 0.00 s / 160 MB | – | – | – |
| write, zstd 3 | dta | 1 ms / 0.00 s / 111 MB | 3 ms / 0.00 s / 117 MB | – | 3 ms / 0.00 s / 118 MB | 2 ms / 0.00 s / 160 MB | – | – | – |

### 1976_Preg

23,042 rows, 80 columns; .dta 2.4 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 4 ms / 0.00 s / 123 MB | 20 ms / 0.03 s / 143 MB | 20 ms / 0.03 s / 144 MB | 11 ms / 0.01 s / 125 MB | 6 ms / 0.01 s / 184 MB | 19 ms / 0.03 s / 131 MB | 4 ms / 0.01 s / 170 MB | 8 ms / 0.01 s / 159 MB |
| whole file | polars | 4 ms / 0.00 s / 123 MB | 20 ms / 0.03 s / 143 MB | 20 ms / 0.03 s / 144 MB | 10 ms / 0.01 s / 125 MB | 6 ms / 0.02 s / 184 MB | – | – | – |
| whole file | ours | 4 ms / 0.00 s / 123 MB | 20 ms / 0.03 s / 143 MB | 20 ms / 0.03 s / 143 MB | 10 ms / 0.01 s / 124 MB | 5 ms / 0.01 s / 184 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 121 MB | 3 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 165 MB | 17 ms / 0.02 s / 120 MB | 2 ms / 0.01 s / 163 MB | 1 ms / 0.00 s / 141 MB |
| five columns | polars | 1 ms / 0.00 s / 111 MB | 17 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 122 MB | 3 ms / 0.00 s / 117 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| five columns | ours | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 121 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 165 MB | – | – | – |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 109 MB | 19 ms / 0.03 s / 132 MB | 20 ms / 0.03 s / 144 MB | 11 ms / 0.01 s / 125 MB | 4 ms / 0.01 s / 164 MB | 19 ms / 0.03 s / 130 MB | 2 ms / 0.01 s / 161 MB | 5 ms / 0.02 s / 171 MB |
| 1,000 rows | polars | 2 ms / 0.00 s / 111 MB | 19 ms / 0.03 s / 131 MB | 20 ms / 0.03 s / 144 MB | 10 ms / 0.01 s / 124 MB | 4 ms / 0.01 s / 164 MB | – | – | – |
| 1,000 rows | ours | 1 ms / 0.00 s / 111 MB | 19 ms / 0.03 s / 131 MB | 20 ms / 0.03 s / 144 MB | 10 ms / 0.01 s / 124 MB | 3 ms / 0.01 s / 163 MB | – | – | – |
| read + pass | pyarrow | 8 ms / 0.01 s / 124 MB | 24 ms / 0.03 s / 144 MB | 24 ms / 0.04 s / 144 MB | 17 ms / 0.02 s / 125 MB | 9 ms / 0.02 s / 185 MB | – | – | – |
| read + pass | polars | 8 ms / 0.01 s / 124 MB | 24 ms / 0.04 s / 144 MB | 24 ms / 0.04 s / 145 MB | 16 ms / 0.02 s / 125 MB | 10 ms / 0.02 s / 185 MB | – | – | – |
| read + pass | ours | 8 ms / 0.01 s / 124 MB | 24 ms / 0.04 s / 144 MB | 24 ms / 0.03 s / 144 MB | 15 ms / 0.02 s / 125 MB | 9 ms / 0.02 s / 185 MB | – | – | – |
| write, defaults | dta | 10 ms / 0.01 s / 123 MB | 22 ms / 0.03 s / 128 MB | – | 25 ms / 0.02 s / 129 MB | 9 ms / 0.03 s / 187 MB | – | – | – |
| write, zstd 3 | dta | 11 ms / 0.01 s / 124 MB | 23 ms / 0.03 s / 129 MB | – | 28 ms / 0.03 s / 130 MB | 9 ms / 0.03 s / 187 MB | – | – | – |

### 1982_FemResp

7,969 rows, 741 columns; .dta 7.6 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 9 ms / 0.02 s / 155 MB | 32 ms / 0.08 s / 206 MB | 32 ms / 0.08 s / 206 MB | 61 ms / 0.06 s / 150 MB | 17 ms / 0.04 s / 235 MB | 26 ms / 0.06 s / 166 MB | 10 ms / 0.01 s / 191 MB | 32 ms / 0.03 s / 219 MB |
| whole file | polars | 10 ms / 0.02 s / 155 MB | 33 ms / 0.09 s / 207 MB | 32 ms / 0.09 s / 207 MB | 63 ms / 0.06 s / 149 MB | 19 ms / 0.04 s / 234 MB | – | – | – |
| whole file | ours | 11 ms / 0.02 s / 158 MB | 32 ms / 0.08 s / 207 MB | 32 ms / 0.08 s / 208 MB | 60 ms / 0.06 s / 150 MB | 17 ms / 0.04 s / 235 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 111 MB | 19 ms / 0.02 s / 122 MB | 20 ms / 0.02 s / 122 MB | 8 ms / 0.01 s / 120 MB | 3 ms / 0.01 s / 165 MB | 19 ms / 0.02 s / 122 MB | 2 ms / 0.01 s / 164 MB | 3 ms / 0.00 s / 142 MB |
| five columns | polars | 1 ms / 0.00 s / 111 MB | 19 ms / 0.02 s / 122 MB | 19 ms / 0.02 s / 123 MB | 8 ms / 0.01 s / 119 MB | 3 ms / 0.01 s / 166 MB | – | – | – |
| five columns | ours | 1 ms / 0.00 s / 112 MB | 19 ms / 0.02 s / 124 MB | 20 ms / 0.02 s / 124 MB | 8 ms / 0.01 s / 119 MB | 3 ms / 0.01 s / 167 MB | – | – | – |
| 1,000 rows | pyarrow | 6 ms / 0.01 s / 117 MB | 32 ms / 0.08 s / 171 MB | 32 ms / 0.08 s / 207 MB | 61 ms / 0.06 s / 149 MB | 12 ms / 0.03 s / 178 MB | 26 ms / 0.06 s / 166 MB | 6 ms / 0.01 s / 169 MB | 32 ms / 0.12 s / 374 MB |
| 1,000 rows | polars | 8 ms / 0.01 s / 117 MB | 33 ms / 0.08 s / 172 MB | 32 ms / 0.08 s / 207 MB | 64 ms / 0.06 s / 149 MB | 14 ms / 0.03 s / 177 MB | – | – | – |
| 1,000 rows | ours | 8 ms / 0.01 s / 121 MB | 31 ms / 0.07 s / 173 MB | 32 ms / 0.08 s / 207 MB | 61 ms / 0.06 s / 150 MB | 12 ms / 0.03 s / 178 MB | – | – | – |
| read + pass | pyarrow | 30 ms / 0.04 s / 154 MB | 52 ms / 0.10 s / 208 MB | 53 ms / 0.11 s / 207 MB | 90 ms / 0.09 s / 150 MB | 37 ms / 0.06 s / 236 MB | – | – | – |
| read + pass | polars | 32 ms / 0.04 s / 154 MB | 52 ms / 0.11 s / 208 MB | 52 ms / 0.11 s / 208 MB | 92 ms / 0.09 s / 150 MB | 39 ms / 0.06 s / 235 MB | – | – | – |
| read + pass | ours | 32 ms / 0.04 s / 158 MB | 52 ms / 0.10 s / 209 MB | 54 ms / 0.10 s / 208 MB | 89 ms / 0.09 s / 150 MB | 37 ms / 0.06 s / 236 MB | – | – | – |
| write, defaults | dta | 25 ms / 0.05 s / 151 MB | 90 ms / 0.09 s / 157 MB | – | 179 ms / 0.18 s / 155 MB | 37 ms / 0.11 s / 226 MB | – | – | – |
| write, zstd 3 | dta | 28 ms / 0.05 s / 151 MB | 97 ms / 0.10 s / 158 MB | – | 200 ms / 0.20 s / 155 MB | 38 ms / 0.11 s / 225 MB | – | – | – |

### 1982_Preg

13,768 rows, 174 columns; .dta 3.0 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 3 ms / 0.01 s / 129 MB | 22 ms / 0.04 s / 155 MB | 21 ms / 0.04 s / 155 MB | 16 ms / 0.02 s / 128 MB | 7 ms / 0.02 s / 193 MB | 19 ms / 0.03 s / 136 MB | 4 ms / 0.01 s / 172 MB | 11 ms / 0.01 s / 169 MB |
| whole file | polars | 3 ms / 0.01 s / 130 MB | 22 ms / 0.04 s / 155 MB | 22 ms / 0.04 s / 155 MB | 16 ms / 0.02 s / 128 MB | 7 ms / 0.02 s / 193 MB | – | – | – |
| whole file | ours | 4 ms / 0.01 s / 131 MB | 21 ms / 0.04 s / 155 MB | 22 ms / 0.04 s / 156 MB | 15 ms / 0.02 s / 129 MB | 7 ms / 0.02 s / 193 MB | – | – | – |
| five columns | pyarrow | 0 ms / 0.00 s / 110 MB | 18 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 121 MB | 3 ms / 0.00 s / 118 MB | 2 ms / 0.01 s / 165 MB | 17 ms / 0.02 s / 120 MB | 2 ms / 0.01 s / 163 MB | 2 ms / 0.00 s / 141 MB |
| five columns | polars | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 121 MB | 3 ms / 0.00 s / 118 MB | 2 ms / 0.01 s / 165 MB | – | – | – |
| five columns | ours | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 121 MB | 3 ms / 0.00 s / 117 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| 1,000 rows | pyarrow | 2 ms / 0.00 s / 112 MB | 21 ms / 0.03 s / 138 MB | 22 ms / 0.04 s / 155 MB | 16 ms / 0.02 s / 128 MB | 5 ms / 0.01 s / 166 MB | 19 ms / 0.03 s / 136 MB | 3 ms / 0.01 s / 162 MB | 9 ms / 0.03 s / 199 MB |
| 1,000 rows | polars | 2 ms / 0.00 s / 112 MB | 21 ms / 0.03 s / 138 MB | 22 ms / 0.04 s / 155 MB | 17 ms / 0.02 s / 128 MB | 5 ms / 0.01 s / 166 MB | – | – | – |
| 1,000 rows | ours | 2 ms / 0.00 s / 113 MB | 21 ms / 0.03 s / 138 MB | 23 ms / 0.04 s / 155 MB | 15 ms / 0.02 s / 128 MB | 5 ms / 0.01 s / 166 MB | – | – | – |
| read + pass | pyarrow | 9 ms / 0.01 s / 130 MB | 27 ms / 0.04 s / 155 MB | 27 ms / 0.05 s / 156 MB | 24 ms / 0.02 s / 130 MB | 12 ms / 0.03 s / 194 MB | – | – | – |
| read + pass | polars | 9 ms / 0.01 s / 131 MB | 27 ms / 0.05 s / 156 MB | 27 ms / 0.05 s / 155 MB | 24 ms / 0.02 s / 130 MB | 12 ms / 0.02 s / 193 MB | – | – | – |
| read + pass | ours | 9 ms / 0.01 s / 133 MB | 27 ms / 0.05 s / 156 MB | 26 ms / 0.04 s / 156 MB | 24 ms / 0.02 s / 131 MB | 12 ms / 0.03 s / 194 MB | – | – | – |
| write, defaults | dta | 11 ms / 0.01 s / 131 MB | 27 ms / 0.03 s / 136 MB | – | 48 ms / 0.05 s / 136 MB | 14 ms / 0.04 s / 195 MB | – | – | – |
| write, zstd 3 | dta | 13 ms / 0.01 s / 131 MB | 29 ms / 0.03 s / 136 MB | – | 51 ms / 0.05 s / 138 MB | 12 ms / 0.04 s / 193 MB | – | – | – |

### 1988_FemResp

8,450 rows, 1,437 columns; .dta 19.1 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 17 ms / 0.03 s / 196 MB | 49 ms / 0.15 s / 292 MB | 49 ms / 0.14 s / 293 MB | 121 ms / 0.12 s / 195 MB | 33 ms / 0.07 s / 317 MB | 39 ms / 0.10 s / 214 MB | 19 ms / 0.02 s / 234 MB | 72 ms / 0.07 s / 375 MB |
| whole file | polars | 20 ms / 0.04 s / 195 MB | 47 ms / 0.16 s / 293 MB | 48 ms / 0.16 s / 293 MB | 126 ms / 0.13 s / 194 MB | 40 ms / 0.08 s / 317 MB | – | – | – |
| whole file | ours | 20 ms / 0.03 s / 202 MB | 50 ms / 0.15 s / 295 MB | 48 ms / 0.14 s / 295 MB | 120 ms / 0.12 s / 196 MB | 33 ms / 0.07 s / 319 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 112 MB | 21 ms / 0.02 s / 125 MB | 21 ms / 0.02 s / 126 MB | 14 ms / 0.01 s / 122 MB | 4 ms / 0.01 s / 168 MB | 21 ms / 0.02 s / 124 MB | 3 ms / 0.01 s / 166 MB | 5 ms / 0.00 s / 144 MB |
| five columns | polars | 1 ms / 0.00 s / 112 MB | 21 ms / 0.02 s / 125 MB | 22 ms / 0.02 s / 125 MB | 13 ms / 0.01 s / 121 MB | 4 ms / 0.01 s / 168 MB | – | – | – |
| five columns | ours | 2 ms / 0.00 s / 112 MB | 21 ms / 0.02 s / 127 MB | 21 ms / 0.02 s / 127 MB | 13 ms / 0.01 s / 121 MB | 3 ms / 0.01 s / 169 MB | – | – | – |
| 1,000 rows | pyarrow | 13 ms / 0.01 s / 124 MB | 46 ms / 0.13 s / 223 MB | 46 ms / 0.15 s / 294 MB | 122 ms / 0.12 s / 195 MB | 22 ms / 0.05 s / 193 MB | 37 ms / 0.10 s / 214 MB | 11 ms / 0.02 s / 179 MB | 65 ms / 0.26 s / 593 MB |
| 1,000 rows | polars | 18 ms / 0.02 s / 122 MB | 46 ms / 0.14 s / 223 MB | 55 ms / 0.15 s / 293 MB | 132 ms / 0.13 s / 196 MB | 28 ms / 0.05 s / 192 MB | – | – | – |
| 1,000 rows | ours | 16 ms / 0.02 s / 129 MB | 49 ms / 0.12 s / 223 MB | 53 ms / 0.15 s / 295 MB | 124 ms / 0.12 s / 195 MB | 33 ms / 0.03 s / 194 MB | – | – | – |
| read + pass | pyarrow | 58 ms / 0.07 s / 196 MB | 101 ms / 0.19 s / 297 MB | 106 ms / 0.18 s / 295 MB | 176 ms / 0.18 s / 196 MB | 72 ms / 0.11 s / 318 MB | – | – | – |
| read + pass | polars | 61 ms / 0.08 s / 196 MB | 89 ms / 0.20 s / 293 MB | 91 ms / 0.19 s / 294 MB | 181 ms / 0.18 s / 196 MB | 76 ms / 0.12 s / 317 MB | – | – | – |
| read + pass | ours | 62 ms / 0.08 s / 203 MB | 85 ms / 0.18 s / 295 MB | 85 ms / 0.19 s / 296 MB | 174 ms / 0.17 s / 197 MB | 71 ms / 0.11 s / 319 MB | – | – | – |
| write, defaults | dta | 51 ms / 0.10 s / 221 MB | 192 ms / 0.19 s / 231 MB | – | 336 ms / 0.33 s / 224 MB | 72 ms / 0.23 s / 317 MB | – | – | – |
| write, zstd 3 | dta | 60 ms / 0.11 s / 222 MB | 207 ms / 0.21 s / 232 MB | – | 381 ms / 0.38 s / 225 MB | 91 ms / 0.23 s / 317 MB | – | – | – |

### 1988_Preg

15,759 rows, 284 columns; .dta 10.7 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 6 ms / 0.01 s / 139 MB | 25 ms / 0.05 s / 176 MB | 24 ms / 0.05 s / 176 MB | 29 ms / 0.03 s / 136 MB | 12 ms / 0.03 s / 217 MB | 21 ms / 0.04 s / 148 MB | 8 ms / 0.01 s / 189 MB | 20 ms / 0.02 s / 195 MB |
| whole file | polars | 7 ms / 0.01 s / 141 MB | 25 ms / 0.06 s / 176 MB | 25 ms / 0.05 s / 176 MB | 31 ms / 0.03 s / 136 MB | 14 ms / 0.03 s / 217 MB | – | – | – |
| whole file | ours | 7 ms / 0.01 s / 142 MB | 24 ms / 0.05 s / 176 MB | 24 ms / 0.05 s / 177 MB | 28 ms / 0.03 s / 136 MB | 12 ms / 0.03 s / 218 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 121 MB | 4 ms / 0.00 s / 118 MB | 2 ms / 0.01 s / 165 MB | 17 ms / 0.02 s / 120 MB | 2 ms / 0.01 s / 163 MB | 2 ms / 0.00 s / 142 MB |
| five columns | polars | 1 ms / 0.00 s / 110 MB | 18 ms / 0.02 s / 122 MB | 18 ms / 0.02 s / 122 MB | 4 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| five columns | ours | 1 ms / 0.00 s / 112 MB | 18 ms / 0.02 s / 122 MB | 18 ms / 0.02 s / 122 MB | 4 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 166 MB | – | – | – |
| 1,000 rows | pyarrow | 5 ms / 0.00 s / 112 MB | 24 ms / 0.04 s / 150 MB | 24 ms / 0.05 s / 176 MB | 29 ms / 0.03 s / 136 MB | 8 ms / 0.02 s / 170 MB | 21 ms / 0.04 s / 149 MB | 5 ms / 0.01 s / 167 MB | 14 ms / 0.04 s / 217 MB |
| 1,000 rows | polars | 7 ms / 0.01 s / 113 MB | 23 ms / 0.05 s / 151 MB | 25 ms / 0.06 s / 176 MB | 32 ms / 0.03 s / 137 MB | 10 ms / 0.02 s / 170 MB | – | – | – |
| 1,000 rows | ours | 6 ms / 0.01 s / 115 MB | 24 ms / 0.04 s / 152 MB | 24 ms / 0.05 s / 177 MB | 29 ms / 0.03 s / 136 MB | 8 ms / 0.02 s / 171 MB | – | – | – |
| read + pass | pyarrow | 17 ms / 0.02 s / 141 MB | 35 ms / 0.06 s / 176 MB | 34 ms / 0.06 s / 176 MB | 42 ms / 0.04 s / 138 MB | 22 ms / 0.04 s / 218 MB | – | – | – |
| read + pass | polars | 18 ms / 0.02 s / 141 MB | 34 ms / 0.06 s / 177 MB | 36 ms / 0.07 s / 176 MB | 44 ms / 0.04 s / 138 MB | 24 ms / 0.04 s / 217 MB | – | – | – |
| read + pass | ours | 18 ms / 0.02 s / 144 MB | 34 ms / 0.07 s / 177 MB | 35 ms / 0.06 s / 178 MB | 42 ms / 0.04 s / 137 MB | 22 ms / 0.04 s / 219 MB | – | – | – |
| write, defaults | dta | 19 ms / 0.04 s / 142 MB | 64 ms / 0.06 s / 147 MB | – | 65 ms / 0.06 s / 145 MB | 24 ms / 0.09 s / 211 MB | – | – | – |
| write, zstd 3 | dta | 22 ms / 0.04 s / 143 MB | 71 ms / 0.07 s / 146 MB | – | 81 ms / 0.08 s / 147 MB | 23 ms / 0.08 s / 210 MB | – | – | – |

### 1995_FemResp

10,847 rows, 5,754 columns; .dta 78.9 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 63 ms / 0.11 s / 604 MB | 136 ms / 0.55 s / 978 MB | 136 ms / 0.59 s / 975 MB | 528 ms / 0.53 s / 425 MB | 83 ms / 0.39 s / 975 MB | 88 ms / 0.30 s / 502 MB | 25 ms / 0.08 s / 487 MB | 422 ms / 0.42 s / 1044 MB |
| whole file | polars | 66 ms / 0.12 s / 603 MB | 138 ms / 0.58 s / 976 MB | 138 ms / 0.59 s / 982 MB | 540 ms / 0.54 s / 421 MB | 83 ms / 0.40 s / 974 MB | – | – | – |
| whole file | ours | 77 ms / 0.12 s / 636 MB | 135 ms / 0.55 s / 976 MB | 134 ms / 0.56 s / 977 MB | 511 ms / 0.51 s / 426 MB | 81 ms / 0.39 s / 980 MB | – | – | – |
| five columns | pyarrow | 4 ms / 0.00 s / 115 MB | 32 ms / 0.03 s / 140 MB | 32 ms / 0.03 s / 140 MB | 57 ms / 0.06 s / 140 MB | 7 ms / 0.01 s / 178 MB | 31 ms / 0.03 s / 139 MB | 7 ms / 0.01 s / 176 MB | 15 ms / 0.02 s / 158 MB |
| five columns | polars | 3 ms / 0.00 s / 115 MB | 31 ms / 0.03 s / 139 MB | 31 ms / 0.03 s / 139 MB | 52 ms / 0.05 s / 135 MB | 7 ms / 0.01 s / 178 MB | – | – | – |
| five columns | ours | 6 ms / 0.01 s / 121 MB | 33 ms / 0.03 s / 152 MB | 33 ms / 0.03 s / 151 MB | 51 ms / 0.05 s / 141 MB | 7 ms / 0.01 s / 185 MB | – | – | – |
| 1,000 rows | pyarrow | 27 ms / 0.04 s / 171 MB | 123 ms / 0.42 s / 543 MB | 137 ms / 0.57 s / 976 MB | 533 ms / 0.53 s / 425 MB | 56 ms / 0.15 s / 274 MB | 90 ms / 0.31 s / 502 MB | 14 ms / 0.03 s / 218 MB | 348 ms / 1.13 s / 1938 MB |
| 1,000 rows | polars | 31 ms / 0.05 s / 171 MB | 128 ms / 0.44 s / 545 MB | 138 ms / 0.59 s / 976 MB | 548 ms / 0.55 s / 420 MB | 58 ms / 0.16 s / 274 MB | – | – | – |
| 1,000 rows | ours | 41 ms / 0.05 s / 203 MB | 120 ms / 0.40 s / 544 MB | 135 ms / 0.57 s / 976 MB | 513 ms / 0.51 s / 426 MB | 54 ms / 0.15 s / 278 MB | – | – | – |
| read + pass | pyarrow | 193 ms / 0.24 s / 604 MB | 258 ms / 0.68 s / 978 MB | 260 ms / 0.69 s / 977 MB | 732 ms / 0.73 s / 490 MB | 207 ms / 0.49 s / 976 MB | – | – | – |
| read + pass | polars | 198 ms / 0.25 s / 605 MB | 259 ms / 0.73 s / 977 MB | 261 ms / 0.67 s / 978 MB | 746 ms / 0.75 s / 490 MB | 206 ms / 0.52 s / 977 MB | – | – | – |
| read + pass | ours | 212 ms / 0.26 s / 637 MB | 257 ms / 0.68 s / 977 MB | 255 ms / 0.66 s / 976 MB | 710 ms / 0.71 s / 496 MB | 203 ms / 0.50 s / 981 MB | – | – | – |
| write, defaults | dta | 173 ms / 0.31 s / 598 MB | 620 ms / 0.62 s / 628 MB | – | 1.37 s / 1.37 s / 588 MB | 232 ms / 0.65 s / 733 MB | – | – | – |
| write, zstd 3 | dta | 187 ms / 0.34 s / 600 MB | 649 ms / 0.65 s / 626 MB | – | 1.45 s / 1.45 s / 589 MB | 226 ms / 0.64 s / 734 MB | – | – | – |

### 1995_Preg

21,332 rows, 245 columns; .dta 6.2 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 6 ms / 0.01 s / 150 MB | 25 ms / 0.06 s / 190 MB | 25 ms / 0.06 s / 190 MB | 32 ms / 0.03 s / 145 MB | 12 ms / 0.03 s / 228 MB | 21 ms / 0.04 s / 152 MB | 8 ms / 0.01 s / 189 MB | 23 ms / 0.02 s / 198 MB |
| whole file | polars | 7 ms / 0.01 s / 151 MB | 25 ms / 0.06 s / 191 MB | 26 ms / 0.06 s / 190 MB | 28 ms / 0.03 s / 144 MB | 13 ms / 0.03 s / 229 MB | – | – | – |
| whole file | ours | 7 ms / 0.01 s / 151 MB | 25 ms / 0.06 s / 191 MB | 24 ms / 0.06 s / 190 MB | 27 ms / 0.03 s / 144 MB | 12 ms / 0.03 s / 229 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 122 MB | 4 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 165 MB | 18 ms / 0.02 s / 121 MB | 2 ms / 0.01 s / 164 MB | 2 ms / 0.00 s / 141 MB |
| five columns | polars | 1 ms / 0.00 s / 112 MB | 18 ms / 0.02 s / 122 MB | 18 ms / 0.02 s / 122 MB | 4 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| five columns | ours | 1 ms / 0.00 s / 112 MB | 18 ms / 0.02 s / 122 MB | 18 ms / 0.02 s / 122 MB | 4 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 166 MB | – | – | – |
| 1,000 rows | pyarrow | 3 ms / 0.00 s / 112 MB | 22 ms / 0.04 s / 155 MB | 26 ms / 0.06 s / 190 MB | 32 ms / 0.03 s / 144 MB | 6 ms / 0.01 s / 169 MB | 22 ms / 0.04 s / 153 MB | 4 ms / 0.01 s / 165 MB | 12 ms / 0.05 s / 219 MB |
| 1,000 rows | polars | 4 ms / 0.00 s / 113 MB | 22 ms / 0.05 s / 155 MB | 25 ms / 0.06 s / 190 MB | 28 ms / 0.03 s / 144 MB | 7 ms / 0.02 s / 168 MB | – | – | – |
| 1,000 rows | ours | 4 ms / 0.00 s / 113 MB | 23 ms / 0.04 s / 155 MB | 25 ms / 0.06 s / 190 MB | 27 ms / 0.03 s / 144 MB | 6 ms / 0.01 s / 169 MB | – | – | – |
| read + pass | pyarrow | 17 ms / 0.02 s / 151 MB | 36 ms / 0.07 s / 191 MB | 35 ms / 0.07 s / 191 MB | 48 ms / 0.05 s / 146 MB | 22 ms / 0.04 s / 229 MB | – | – | – |
| read + pass | polars | 17 ms / 0.02 s / 151 MB | 35 ms / 0.07 s / 190 MB | 36 ms / 0.07 s / 191 MB | 44 ms / 0.04 s / 146 MB | 23 ms / 0.05 s / 229 MB | – | – | – |
| read + pass | ours | 18 ms / 0.02 s / 152 MB | 35 ms / 0.07 s / 191 MB | 36 ms / 0.07 s / 191 MB | 42 ms / 0.04 s / 145 MB | 22 ms / 0.04 s / 230 MB | – | – | – |
| write, defaults | dta | 16 ms / 0.03 s / 147 MB | 61 ms / 0.06 s / 153 MB | – | 74 ms / 0.07 s / 152 MB | 19 ms / 0.07 s / 220 MB | – | – | – |
| write, zstd 3 | dta | 18 ms / 0.03 s / 149 MB | 65 ms / 0.07 s / 153 MB | – | 86 ms / 0.09 s / 153 MB | 18 ms / 0.07 s / 220 MB | – | – | – |

### 2002_FemPreg

13,593 rows, 243 columns; .dta 4.3 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 9 ms / 0.01 s / 135 MB | 24 ms / 0.05 s / 167 MB | 24 ms / 0.05 s / 167 MB | 23 ms / 0.02 s / 135 MB | 9 ms / 0.03 s / 203 MB | 21 ms / 0.03 s / 144 MB | 5 ms / 0.01 s / 178 MB | 15 ms / 0.02 s / 184 MB |
| whole file | polars | 5 ms / 0.01 s / 135 MB | 23 ms / 0.05 s / 166 MB | 23 ms / 0.05 s / 167 MB | 24 ms / 0.02 s / 134 MB | 10 ms / 0.03 s / 203 MB | – | – | – |
| whole file | ours | 6 ms / 0.01 s / 137 MB | 24 ms / 0.05 s / 167 MB | 24 ms / 0.05 s / 168 MB | 23 ms / 0.02 s / 134 MB | 9 ms / 0.03 s / 204 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 122 MB | 19 ms / 0.02 s / 123 MB | 4 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 165 MB | 17 ms / 0.02 s / 121 MB | 2 ms / 0.01 s / 163 MB | 2 ms / 0.00 s / 142 MB |
| five columns | polars | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 122 MB | 18 ms / 0.02 s / 122 MB | 4 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| five columns | ours | 1 ms / 0.00 s / 112 MB | 18 ms / 0.02 s / 123 MB | 19 ms / 0.02 s / 123 MB | 4 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 166 MB | – | – | – |
| 1,000 rows | pyarrow | 3 ms / 0.00 s / 113 MB | 22 ms / 0.04 s / 147 MB | 23 ms / 0.05 s / 167 MB | 23 ms / 0.02 s / 134 MB | 6 ms / 0.02 s / 168 MB | 20 ms / 0.03 s / 143 MB | 3 ms / 0.01 s / 164 MB | 11 ms / 0.04 s / 217 MB |
| 1,000 rows | polars | 3 ms / 0.00 s / 112 MB | 23 ms / 0.04 s / 146 MB | 24 ms / 0.05 s / 167 MB | 24 ms / 0.02 s / 134 MB | 7 ms / 0.02 s / 168 MB | – | – | – |
| 1,000 rows | ours | 3 ms / 0.00 s / 114 MB | 22 ms / 0.04 s / 147 MB | 24 ms / 0.05 s / 167 MB | 23 ms / 0.02 s / 133 MB | 6 ms / 0.02 s / 169 MB | – | – | – |
| read + pass | pyarrow | 13 ms / 0.02 s / 137 MB | 32 ms / 0.06 s / 168 MB | 33 ms / 0.06 s / 168 MB | 35 ms / 0.04 s / 135 MB | 17 ms / 0.03 s / 204 MB | – | – | – |
| read + pass | polars | 14 ms / 0.02 s / 138 MB | 31 ms / 0.06 s / 168 MB | 32 ms / 0.06 s / 168 MB | 36 ms / 0.04 s / 135 MB | 18 ms / 0.04 s / 204 MB | – | – | – |
| read + pass | ours | 14 ms / 0.02 s / 138 MB | 32 ms / 0.06 s / 167 MB | 32 ms / 0.06 s / 169 MB | 35 ms / 0.03 s / 135 MB | 17 ms / 0.04 s / 205 MB | – | – | – |
| write, defaults | dta | 18 ms / 0.02 s / 133 MB | 43 ms / 0.04 s / 140 MB | – | 65 ms / 0.06 s / 141 MB | 18 ms / 0.05 s / 200 MB | – | – | – |
| write, zstd 3 | dta | 21 ms / 0.02 s / 134 MB | 47 ms / 0.05 s / 140 MB | – | 74 ms / 0.07 s / 141 MB | 17 ms / 0.06 s / 200 MB | – | – | – |

### 2002_FemResp

7,643 rows, 3,087 columns; .dta 29.3 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 27 ms / 0.05 s / 293 MB | 79 ms / 0.25 s / 471 MB | 77 ms / 0.26 s / 470 MB | 244 ms / 0.24 s / 256 MB | 50 ms / 0.14 s / 462 MB | 56 ms / 0.16 s / 299 MB | 23 ms / 0.03 s / 283 MB | 158 ms / 0.16 s / 459 MB |
| whole file | polars | 30 ms / 0.05 s / 292 MB | 77 ms / 0.26 s / 470 MB | 78 ms / 0.27 s / 472 MB | 247 ms / 0.25 s / 253 MB | 53 ms / 0.14 s / 462 MB | – | – | – |
| whole file | ours | 34 ms / 0.05 s / 308 MB | 75 ms / 0.25 s / 477 MB | 77 ms / 0.25 s / 475 MB | 233 ms / 0.23 s / 254 MB | 49 ms / 0.14 s / 465 MB | – | – | – |
| five columns | pyarrow | 3 ms / 0.00 s / 113 MB | 26 ms / 0.03 s / 131 MB | 26 ms / 0.03 s / 131 MB | 32 ms / 0.03 s / 130 MB | 5 ms / 0.01 s / 173 MB | 25 ms / 0.03 s / 130 MB | 5 ms / 0.01 s / 170 MB | 9 ms / 0.01 s / 149 MB |
| five columns | polars | 2 ms / 0.00 s / 113 MB | 25 ms / 0.03 s / 130 MB | 25 ms / 0.03 s / 130 MB | 29 ms / 0.03 s / 128 MB | 5 ms / 0.01 s / 172 MB | – | – | – |
| five columns | ours | 4 ms / 0.00 s / 116 MB | 26 ms / 0.03 s / 137 MB | 26 ms / 0.03 s / 138 MB | 29 ms / 0.03 s / 129 MB | 5 ms / 0.01 s / 176 MB | – | – | – |
| 1,000 rows | pyarrow | 14 ms / 0.02 s / 144 MB | 76 ms / 0.22 s / 321 MB | 76 ms / 0.25 s / 471 MB | 243 ms / 0.24 s / 257 MB | 38 ms / 0.09 s / 221 MB | 57 ms / 0.16 s / 298 MB | 13 ms / 0.02 s / 192 MB | 160 ms / 0.55 s / 1116 MB |
| 1,000 rows | polars | 16 ms / 0.02 s / 144 MB | 76 ms / 0.23 s / 319 MB | 77 ms / 0.28 s / 470 MB | 250 ms / 0.25 s / 253 MB | 39 ms / 0.09 s / 221 MB | – | – | – |
| 1,000 rows | ours | 21 ms / 0.03 s / 159 MB | 73 ms / 0.21 s / 325 MB | 75 ms / 0.26 s / 475 MB | 232 ms / 0.23 s / 255 MB | 36 ms / 0.09 s / 224 MB | – | – | – |
| read + pass | pyarrow | 97 ms / 0.12 s / 293 MB | 141 ms / 0.32 s / 472 MB | 141 ms / 0.33 s / 472 MB | 335 ms / 0.33 s / 256 MB | 115 ms / 0.21 s / 463 MB | – | – | – |
| read + pass | polars | 98 ms / 0.12 s / 293 MB | 143 ms / 0.33 s / 470 MB | 143 ms / 0.34 s / 471 MB | 343 ms / 0.34 s / 254 MB | 120 ms / 0.22 s / 462 MB | – | – | – |
| read + pass | ours | 104 ms / 0.12 s / 309 MB | 142 ms / 0.33 s / 476 MB | 140 ms / 0.32 s / 475 MB | 325 ms / 0.33 s / 256 MB | 115 ms / 0.21 s / 466 MB | – | – | – |
| write, defaults | dta | 78 ms / 0.14 s / 291 MB | 279 ms / 0.28 s / 305 MB | – | 713 ms / 0.71 s / 288 MB | 121 ms / 0.34 s / 395 MB | – | – | – |
| write, zstd 3 | dta | 86 ms / 0.15 s / 293 MB | 296 ms / 0.30 s / 304 MB | – | 753 ms / 0.75 s / 289 MB | 121 ms / 0.34 s / 398 MB | – | – | – |

### 2002_HHvars

12,571 rows, 10 columns; .dta 0.1 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 1 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 121 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 163 MB | 17 ms / 0.02 s / 121 MB | 2 ms / 0.01 s / 161 MB | 1 ms / 0.00 s / 141 MB |
| whole file | polars | 1 ms / 0.00 s / 111 MB | 17 ms / 0.02 s / 122 MB | 18 ms / 0.02 s / 121 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 163 MB | – | – | – |
| whole file | ours | 1 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 121 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 163 MB | – | – | – |
| five columns | pyarrow | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 18 ms / 0.02 s / 120 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 163 MB | 17 ms / 0.02 s / 120 MB | 2 ms / 0.01 s / 162 MB | 1 ms / 0.00 s / 141 MB |
| five columns | polars | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 17 ms / 0.02 s / 120 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 163 MB | – | – | – |
| five columns | ours | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 17 ms / 0.02 s / 120 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 163 MB | – | – | – |
| 1,000 rows | pyarrow | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 121 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 161 MB | 17 ms / 0.02 s / 120 MB | 2 ms / 0.01 s / 160 MB | 2 ms / 0.01 s / 149 MB |
| 1,000 rows | polars | 0 ms / 0.00 s / 110 MB | 18 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 122 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| 1,000 rows | ours | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 121 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| read + pass | pyarrow | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 122 MB | 19 ms / 0.02 s / 122 MB | 3 ms / 0.00 s / 117 MB | 3 ms / 0.01 s / 163 MB | – | – | – |
| read + pass | polars | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 122 MB | 18 ms / 0.02 s / 122 MB | 3 ms / 0.00 s / 117 MB | 3 ms / 0.01 s / 164 MB | – | – | – |
| read + pass | ours | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 122 MB | 19 ms / 0.02 s / 122 MB | 3 ms / 0.00 s / 117 MB | 3 ms / 0.01 s / 164 MB | – | – | – |
| write, defaults | dta | 1 ms / 0.00 s / 112 MB | 4 ms / 0.00 s / 118 MB | – | 5 ms / 0.00 s / 118 MB | 4 ms / 0.01 s / 165 MB | – | – | – |
| write, zstd 3 | dta | 2 ms / 0.00 s / 112 MB | 4 ms / 0.00 s / 118 MB | – | 5 ms / 0.00 s / 119 MB | 4 ms / 0.01 s / 165 MB | – | – | – |

### 2002_Male

4,928 rows, 1,993 columns; .dta 12.7 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 14 ms / 0.02 s / 191 MB | 53 ms / 0.15 s / 271 MB | 54 ms / 0.16 s / 271 MB | 143 ms / 0.14 s / 181 MB | 30 ms / 0.08 s / 294 MB | 40 ms / 0.10 s / 196 MB | 14 ms / 0.02 s / 215 MB | 77 ms / 0.08 s / 344 MB |
| whole file | polars | 15 ms / 0.02 s / 191 MB | 52 ms / 0.16 s / 271 MB | 53 ms / 0.16 s / 270 MB | 146 ms / 0.15 s / 180 MB | 33 ms / 0.08 s / 294 MB | – | – | – |
| whole file | ours | 17 ms / 0.03 s / 196 MB | 51 ms / 0.15 s / 272 MB | 51 ms / 0.14 s / 271 MB | 137 ms / 0.14 s / 179 MB | 30 ms / 0.07 s / 294 MB | – | – | – |
| five columns | pyarrow | 2 ms / 0.00 s / 113 MB | 22 ms / 0.02 s / 127 MB | 23 ms / 0.02 s / 127 MB | 21 ms / 0.02 s / 125 MB | 4 ms / 0.01 s / 170 MB | 22 ms / 0.02 s / 127 MB | 4 ms / 0.01 s / 168 MB | 6 ms / 0.01 s / 147 MB |
| five columns | polars | 2 ms / 0.00 s / 112 MB | 22 ms / 0.02 s / 127 MB | 22 ms / 0.02 s / 126 MB | 20 ms / 0.02 s / 123 MB | 4 ms / 0.01 s / 170 MB | – | – | – |
| five columns | ours | 2 ms / 0.00 s / 112 MB | 22 ms / 0.02 s / 128 MB | 22 ms / 0.02 s / 129 MB | 19 ms / 0.02 s / 124 MB | 4 ms / 0.01 s / 170 MB | – | – | – |
| 1,000 rows | pyarrow | 11 ms / 0.01 s / 130 MB | 54 ms / 0.14 s / 213 MB | 53 ms / 0.15 s / 272 MB | 146 ms / 0.15 s / 182 MB | 27 ms / 0.06 s / 201 MB | 41 ms / 0.10 s / 197 MB | 10 ms / 0.01 s / 181 MB | 94 ms / 0.35 s / 773 MB |
| 1,000 rows | polars | 13 ms / 0.01 s / 130 MB | 51 ms / 0.14 s / 212 MB | 53 ms / 0.16 s / 270 MB | 148 ms / 0.15 s / 180 MB | 28 ms / 0.06 s / 201 MB | – | – | – |
| 1,000 rows | ours | 13 ms / 0.01 s / 135 MB | 53 ms / 0.13 s / 213 MB | 51 ms / 0.15 s / 272 MB | 140 ms / 0.14 s / 179 MB | 25 ms / 0.06 s / 202 MB | – | – | – |
| read + pass | pyarrow | 52 ms / 0.06 s / 192 MB | 87 ms / 0.18 s / 272 MB | 86 ms / 0.18 s / 272 MB | 194 ms / 0.19 s / 181 MB | 65 ms / 0.11 s / 295 MB | – | – | – |
| read + pass | polars | 53 ms / 0.06 s / 193 MB | 88 ms / 0.20 s / 271 MB | 88 ms / 0.20 s / 272 MB | 196 ms / 0.20 s / 180 MB | 67 ms / 0.11 s / 295 MB | – | – | – |
| read + pass | ours | 55 ms / 0.06 s / 198 MB | 87 ms / 0.18 s / 272 MB | 86 ms / 0.18 s / 272 MB | 189 ms / 0.19 s / 181 MB | 64 ms / 0.11 s / 296 MB | – | – | – |
| write, defaults | dta | 35 ms / 0.06 s / 187 MB | 139 ms / 0.14 s / 202 MB | – | 441 ms / 0.44 s / 194 MB | 72 ms / 0.19 s / 275 MB | – | – | – |
| write, zstd 3 | dta | 39 ms / 0.07 s / 189 MB | 147 ms / 0.15 s / 202 MB | – | 462 ms / 0.46 s / 194 MB | 73 ms / 0.19 s / 275 MB | – | – | – |

### 2002_curr_ins

12,571 rows, 3 columns; .dta 0.1 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 17 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 116 MB | 2 ms / 0.01 s / 162 MB | 17 ms / 0.02 s / 119 MB | 2 ms / 0.01 s / 160 MB | 1 ms / 0.00 s / 140 MB |
| whole file | polars | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 119 MB | 17 ms / 0.02 s / 119 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| whole file | ours | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 119 MB | 18 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 116 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| five columns | pyarrow | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 17 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | 17 ms / 0.02 s / 119 MB | 2 ms / 0.01 s / 161 MB | 1 ms / 0.00 s / 141 MB |
| five columns | polars | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 119 MB | 18 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| five columns | ours | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 119 MB | 17 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| 1,000 rows | pyarrow | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 17 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 161 MB | 17 ms / 0.02 s / 119 MB | 2 ms / 0.01 s / 160 MB | 2 ms / 0.00 s / 146 MB |
| 1,000 rows | polars | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 17 ms / 0.02 s / 119 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 161 MB | – | – | – |
| 1,000 rows | ours | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 119 MB | 17 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 161 MB | – | – | – |
| read + pass | pyarrow | 1 ms / 0.00 s / 111 MB | 17 ms / 0.02 s / 120 MB | 18 ms / 0.02 s / 120 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| read + pass | polars | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 120 MB | 18 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 116 MB | 3 ms / 0.01 s / 162 MB | – | – | – |
| read + pass | ours | 1 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 119 MB | 18 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| write, defaults | dta | 1 ms / 0.00 s / 111 MB | 2 ms / 0.00 s / 117 MB | – | 1 ms / 0.00 s / 117 MB | 3 ms / 0.01 s / 160 MB | – | – | – |
| write, zstd 3 | dta | 1 ms / 0.00 s / 111 MB | 2 ms / 0.00 s / 117 MB | – | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 161 MB | – | – | – |

### 2002_hhpartypnew

12,571 rows, 3 columns; .dta 0.1 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 17 ms / 0.02 s / 119 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | 17 ms / 0.02 s / 119 MB | 1 ms / 0.01 s / 160 MB | 1 ms / 0.00 s / 141 MB |
| whole file | polars | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 17 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 116 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| whole file | ours | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 119 MB | 18 ms / 0.02 s / 119 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| five columns | pyarrow | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 119 MB | 18 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 116 MB | 2 ms / 0.01 s / 162 MB | 17 ms / 0.02 s / 119 MB | 2 ms / 0.01 s / 161 MB | 1 ms / 0.00 s / 140 MB |
| five columns | polars | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 119 MB | 17 ms / 0.02 s / 119 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| five columns | ours | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 119 MB | 17 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 116 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| 1,000 rows | pyarrow | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 17 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 161 MB | 17 ms / 0.02 s / 119 MB | 2 ms / 0.01 s / 160 MB | 1 ms / 0.00 s / 146 MB |
| 1,000 rows | polars | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 18 ms / 0.02 s / 119 MB | 1 ms / 0.00 s / 116 MB | 2 ms / 0.01 s / 161 MB | – | – | – |
| 1,000 rows | ours | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 119 MB | 17 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 161 MB | – | – | – |
| read + pass | pyarrow | 1 ms / 0.00 s / 111 MB | 17 ms / 0.02 s / 120 MB | 17 ms / 0.02 s / 120 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| read + pass | polars | 1 ms / 0.00 s / 111 MB | 17 ms / 0.02 s / 120 MB | 18 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| read + pass | ours | 1 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 120 MB | 18 ms / 0.02 s / 120 MB | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| write, defaults | dta | 1 ms / 0.00 s / 111 MB | 2 ms / 0.00 s / 117 MB | – | 1 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 160 MB | – | – | – |
| write, zstd 3 | dta | 1 ms / 0.00 s / 112 MB | 2 ms / 0.00 s / 117 MB | – | 3 ms / 0.00 s / 117 MB | 3 ms / 0.01 s / 161 MB | – | – | – |

### 2006_2010_FemPreg

20,492 rows, 287 columns; .dta 7.6 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 7 ms / 0.01 s / 153 MB | 26 ms / 0.06 s / 200 MB | 27 ms / 0.06 s / 200 MB | 36 ms / 0.04 s / 147 MB | 13 ms / 0.04 s / 237 MB | 22 ms / 0.04 s / 158 MB | 8 ms / 0.01 s / 195 MB | 25 ms / 0.03 s / 211 MB |
| whole file | polars | 7 ms / 0.01 s / 155 MB | 26 ms / 0.06 s / 200 MB | 26 ms / 0.07 s / 200 MB | 32 ms / 0.03 s / 147 MB | 14 ms / 0.04 s / 237 MB | – | – | – |
| whole file | ours | 8 ms / 0.01 s / 154 MB | 25 ms / 0.06 s / 200 MB | 26 ms / 0.06 s / 200 MB | 30 ms / 0.03 s / 147 MB | 13 ms / 0.04 s / 237 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 112 MB | 19 ms / 0.02 s / 123 MB | 19 ms / 0.02 s / 123 MB | 5 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 167 MB | 18 ms / 0.02 s / 121 MB | 2 ms / 0.01 s / 164 MB | 2 ms / 0.00 s / 141 MB |
| five columns | polars | 1 ms / 0.00 s / 111 MB | 19 ms / 0.02 s / 123 MB | 19 ms / 0.02 s / 123 MB | 4 ms / 0.00 s / 119 MB | 3 ms / 0.01 s / 166 MB | – | – | – |
| five columns | ours | 1 ms / 0.00 s / 112 MB | 19 ms / 0.02 s / 123 MB | 19 ms / 0.02 s / 123 MB | 4 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 166 MB | – | – | – |
| 1,000 rows | pyarrow | 4 ms / 0.00 s / 113 MB | 25 ms / 0.05 s / 161 MB | 27 ms / 0.06 s / 199 MB | 36 ms / 0.04 s / 147 MB | 7 ms / 0.02 s / 171 MB | 23 ms / 0.04 s / 158 MB | 4 ms / 0.01 s / 166 MB | 14 ms / 0.04 s / 226 MB |
| 1,000 rows | polars | 5 ms / 0.00 s / 113 MB | 24 ms / 0.05 s / 161 MB | 26 ms / 0.06 s / 200 MB | 32 ms / 0.03 s / 147 MB | 8 ms / 0.02 s / 170 MB | – | – | – |
| 1,000 rows | ours | 4 ms / 0.00 s / 114 MB | 25 ms / 0.05 s / 162 MB | 26 ms / 0.06 s / 201 MB | 31 ms / 0.03 s / 148 MB | 7 ms / 0.02 s / 171 MB | – | – | – |
| read + pass | pyarrow | 20 ms / 0.03 s / 155 MB | 39 ms / 0.08 s / 201 MB | 39 ms / 0.08 s / 201 MB | 55 ms / 0.05 s / 151 MB | 26 ms / 0.05 s / 239 MB | – | – | – |
| read + pass | polars | 20 ms / 0.03 s / 155 MB | 38 ms / 0.08 s / 200 MB | 39 ms / 0.07 s / 200 MB | 50 ms / 0.05 s / 150 MB | 26 ms / 0.05 s / 238 MB | – | – | – |
| read + pass | ours | 20 ms / 0.03 s / 157 MB | 38 ms / 0.08 s / 201 MB | 39 ms / 0.07 s / 201 MB | 49 ms / 0.05 s / 150 MB | 25 ms / 0.05 s / 238 MB | – | – | – |
| write, defaults | dta | 18 ms / 0.03 s / 151 MB | 70 ms / 0.07 s / 158 MB | – | 84 ms / 0.08 s / 158 MB | 29 ms / 0.08 s / 221 MB | – | – | – |
| write, zstd 3 | dta | 20 ms / 0.04 s / 152 MB | 75 ms / 0.07 s / 159 MB | – | 99 ms / 0.10 s / 159 MB | 29 ms / 0.08 s / 220 MB | – | – | – |

### 2006_2010_FemResp

12,279 rows, 3,741 columns; .dta 55.6 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 47 ms / 0.09 s / 459 MB | 102 ms / 0.38 s / 710 MB | 103 ms / 0.37 s / 710 MB | 331 ms / 0.33 s / 336 MB | 65 ms / 0.24 s / 723 MB | 69 ms / 0.20 s / 375 MB | 23 ms / 0.05 s / 378 MB | 257 ms / 0.26 s / 726 MB |
| whole file | polars | 51 ms / 0.09 s / 459 MB | 103 ms / 0.40 s / 715 MB | 103 ms / 0.38 s / 710 MB | 340 ms / 0.34 s / 334 MB | 66 ms / 0.24 s / 721 MB | – | – | – |
| whole file | ours | 56 ms / 0.09 s / 481 MB | 100 ms / 0.37 s / 716 MB | 101 ms / 0.37 s / 717 MB | 321 ms / 0.32 s / 337 MB | 63 ms / 0.26 s / 725 MB | – | – | – |
| five columns | pyarrow | 3 ms / 0.00 s / 113 MB | 27 ms / 0.03 s / 134 MB | 27 ms / 0.03 s / 134 MB | 38 ms / 0.04 s / 132 MB | 6 ms / 0.01 s / 175 MB | 26 ms / 0.03 s / 133 MB | 5 ms / 0.01 s / 174 MB | 10 ms / 0.01 s / 150 MB |
| five columns | polars | 3 ms / 0.00 s / 113 MB | 26 ms / 0.03 s / 133 MB | 27 ms / 0.03 s / 134 MB | 35 ms / 0.03 s / 129 MB | 6 ms / 0.01 s / 175 MB | – | – | – |
| five columns | ours | 4 ms / 0.00 s / 117 MB | 27 ms / 0.03 s / 141 MB | 28 ms / 0.03 s / 140 MB | 34 ms / 0.03 s / 132 MB | 6 ms / 0.01 s / 180 MB | – | – | – |
| 1,000 rows | pyarrow | 19 ms / 0.03 s / 151 MB | 91 ms / 0.28 s / 399 MB | 101 ms / 0.37 s / 711 MB | 334 ms / 0.33 s / 336 MB | 42 ms / 0.11 s / 239 MB | 70 ms / 0.21 s / 375 MB | 13 ms / 0.03 s / 203 MB | 206 ms / 0.65 s / 1322 MB |
| 1,000 rows | polars | 22 ms / 0.03 s / 151 MB | 92 ms / 0.31 s / 399 MB | 101 ms / 0.42 s / 710 MB | 344 ms / 0.34 s / 333 MB | 45 ms / 0.12 s / 237 MB | – | – | – |
| 1,000 rows | ours | 29 ms / 0.04 s / 172 MB | 89 ms / 0.29 s / 406 MB | 99 ms / 0.41 s / 716 MB | 325 ms / 0.33 s / 337 MB | 41 ms / 0.11 s / 242 MB | – | – | – |
| read + pass | pyarrow | 151 ms / 0.19 s / 460 MB | 197 ms / 0.51 s / 711 MB | 196 ms / 0.52 s / 712 MB | 478 ms / 0.48 s / 359 MB | 160 ms / 0.37 s / 724 MB | – | – | – |
| read + pass | polars | 154 ms / 0.20 s / 460 MB | 197 ms / 0.51 s / 710 MB | 197 ms / 0.52 s / 711 MB | 486 ms / 0.49 s / 359 MB | 163 ms / 0.35 s / 723 MB | – | – | – |
| read + pass | ours | 162 ms / 0.20 s / 483 MB | 194 ms / 0.50 s / 719 MB | 197 ms / 0.49 s / 718 MB | 470 ms / 0.47 s / 363 MB | 160 ms / 0.37 s / 727 MB | – | – | – |
| write, defaults | dta | 128 ms / 0.23 s / 419 MB | 480 ms / 0.48 s / 439 MB | – | 913 ms / 0.91 s / 413 MB | 215 ms / 0.56 s / 543 MB | – | – | – |
| write, zstd 3 | dta | 135 ms / 0.25 s / 420 MB | 504 ms / 0.50 s / 440 MB | – | 989 ms / 0.99 s / 413 MB | 214 ms / 0.55 s / 542 MB | – | – | – |

### 2006_2010_Male

10,403 rows, 2,801 columns; .dta 37.2 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 32 ms / 0.06 s / 342 MB | 77 ms / 0.29 s / 531 MB | 78 ms / 0.28 s / 530 MB | 228 ms / 0.23 s / 273 MB | 48 ms / 0.17 s / 549 MB | 53 ms / 0.15 s / 308 MB | 20 ms / 0.04 s / 321 MB | 167 ms / 0.17 s / 578 MB |
| whole file | polars | 33 ms / 0.06 s / 341 MB | 76 ms / 0.30 s / 530 MB | 74 ms / 0.30 s / 533 MB | 233 ms / 0.23 s / 271 MB | 51 ms / 0.18 s / 548 MB | – | – | – |
| whole file | ours | 36 ms / 0.06 s / 351 MB | 75 ms / 0.28 s / 534 MB | 75 ms / 0.28 s / 535 MB | 214 ms / 0.21 s / 271 MB | 49 ms / 0.18 s / 550 MB | – | – | – |
| five columns | pyarrow | 2 ms / 0.00 s / 113 MB | 24 ms / 0.03 s / 130 MB | 25 ms / 0.03 s / 129 MB | 29 ms / 0.03 s / 129 MB | 5 ms / 0.01 s / 171 MB | 24 ms / 0.02 s / 129 MB | 4 ms / 0.01 s / 169 MB | 8 ms / 0.01 s / 148 MB |
| five columns | polars | 2 ms / 0.00 s / 113 MB | 24 ms / 0.02 s / 129 MB | 24 ms / 0.03 s / 129 MB | 26 ms / 0.03 s / 127 MB | 5 ms / 0.01 s / 171 MB | – | – | – |
| five columns | ours | 3 ms / 0.00 s / 115 MB | 25 ms / 0.03 s / 134 MB | 25 ms / 0.03 s / 133 MB | 26 ms / 0.03 s / 126 MB | 5 ms / 0.01 s / 173 MB | – | – | – |
| 1,000 rows | pyarrow | 13 ms / 0.02 s / 141 MB | 72 ms / 0.22 s / 330 MB | 76 ms / 0.28 s / 532 MB | 229 ms / 0.23 s / 273 MB | 31 ms / 0.08 s / 217 MB | 55 ms / 0.16 s / 309 MB | 10 ms / 0.02 s / 189 MB | 145 ms / 0.52 s / 1028 MB |
| 1,000 rows | polars | 15 ms / 0.02 s / 142 MB | 71 ms / 0.23 s / 332 MB | 76 ms / 0.29 s / 531 MB | 235 ms / 0.24 s / 271 MB | 34 ms / 0.09 s / 217 MB | – | – | – |
| 1,000 rows | ours | 18 ms / 0.02 s / 151 MB | 71 ms / 0.21 s / 334 MB | 74 ms / 0.28 s / 534 MB | 223 ms / 0.22 s / 271 MB | 31 ms / 0.08 s / 219 MB | – | – | – |
| read + pass | pyarrow | 96 ms / 0.12 s / 343 MB | 139 ms / 0.34 s / 531 MB | 137 ms / 0.34 s / 532 MB | 325 ms / 0.32 s / 299 MB | 109 ms / 0.24 s / 550 MB | – | – | – |
| read + pass | polars | 99 ms / 0.12 s / 343 MB | 136 ms / 0.35 s / 531 MB | 137 ms / 0.34 s / 531 MB | 330 ms / 0.33 s / 300 MB | 110 ms / 0.24 s / 549 MB | – | – | – |
| read + pass | ours | 100 ms / 0.12 s / 353 MB | 135 ms / 0.33 s / 535 MB | 136 ms / 0.34 s / 534 MB | 318 ms / 0.32 s / 300 MB | 110 ms / 0.23 s / 551 MB | – | – | – |
| write, defaults | dta | 80 ms / 0.15 s / 349 MB | 295 ms / 0.30 s / 373 MB | – | 662 ms / 0.66 s / 355 MB | 156 ms / 0.37 s / 455 MB | – | – | – |
| write, zstd 3 | dta | 87 ms / 0.16 s / 352 MB | 308 ms / 0.31 s / 370 MB | – | 701 ms / 0.70 s / 353 MB | 153 ms / 0.37 s / 457 MB | – | – | – |

### 2011_2013_FemPreg

9,543 rows, 278 columns; .dta 3.5 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 3 ms / 0.01 s / 130 MB | 24 ms / 0.04 s / 160 MB | 25 ms / 0.05 s / 160 MB | 23 ms / 0.02 s / 131 MB | 8 ms / 0.02 s / 196 MB | 21 ms / 0.03 s / 141 MB | 5 ms / 0.01 s / 175 MB | 14 ms / 0.01 s / 184 MB |
| whole file | polars | 4 ms / 0.01 s / 131 MB | 23 ms / 0.05 s / 159 MB | 23 ms / 0.05 s / 159 MB | 24 ms / 0.02 s / 131 MB | 9 ms / 0.02 s / 195 MB | – | – | – |
| whole file | ours | 4 ms / 0.01 s / 131 MB | 24 ms / 0.05 s / 160 MB | 23 ms / 0.04 s / 160 MB | 22 ms / 0.02 s / 131 MB | 8 ms / 0.02 s / 196 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 122 MB | 19 ms / 0.02 s / 122 MB | 4 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 165 MB | 18 ms / 0.02 s / 121 MB | 2 ms / 0.01 s / 163 MB | 2 ms / 0.00 s / 142 MB |
| five columns | polars | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 122 MB | 18 ms / 0.02 s / 122 MB | 4 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| five columns | ours | 1 ms / 0.00 s / 111 MB | 19 ms / 0.02 s / 122 MB | 19 ms / 0.02 s / 123 MB | 4 ms / 0.00 s / 117 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| 1,000 rows | pyarrow | 2 ms / 0.00 s / 112 MB | 23 ms / 0.04 s / 144 MB | 23 ms / 0.04 s / 159 MB | 23 ms / 0.02 s / 131 MB | 6 ms / 0.02 s / 169 MB | 21 ms / 0.03 s / 141 MB | 3 ms / 0.01 s / 164 MB | 13 ms / 0.04 s / 231 MB |
| 1,000 rows | polars | 3 ms / 0.00 s / 113 MB | 23 ms / 0.04 s / 143 MB | 24 ms / 0.05 s / 159 MB | 24 ms / 0.02 s / 130 MB | 7 ms / 0.02 s / 169 MB | – | – | – |
| 1,000 rows | ours | 3 ms / 0.00 s / 114 MB | 23 ms / 0.04 s / 143 MB | 24 ms / 0.04 s / 160 MB | 22 ms / 0.02 s / 130 MB | 6 ms / 0.02 s / 169 MB | – | – | – |
| read + pass | pyarrow | 12 ms / 0.02 s / 131 MB | 31 ms / 0.05 s / 161 MB | 32 ms / 0.05 s / 160 MB | 35 ms / 0.03 s / 131 MB | 16 ms / 0.03 s / 198 MB | – | – | – |
| read + pass | polars | 12 ms / 0.02 s / 131 MB | 31 ms / 0.05 s / 159 MB | 32 ms / 0.06 s / 160 MB | 36 ms / 0.04 s / 133 MB | 17 ms / 0.03 s / 197 MB | – | – | – |
| read + pass | ours | 13 ms / 0.02 s / 134 MB | 31 ms / 0.05 s / 161 MB | 32 ms / 0.05 s / 160 MB | 34 ms / 0.03 s / 132 MB | 16 ms / 0.03 s / 198 MB | – | – | – |
| write, defaults | dta | 15 ms / 0.02 s / 130 MB | 36 ms / 0.04 s / 137 MB | – | 69 ms / 0.07 s / 138 MB | 19 ms / 0.05 s / 196 MB | – | – | – |
| write, zstd 3 | dta | 17 ms / 0.02 s / 131 MB | 39 ms / 0.04 s / 137 MB | – | 77 ms / 0.08 s / 139 MB | 18 ms / 0.05 s / 197 MB | – | – | – |

### 2011_2013_FemResp

5,601 rows, 3,094 columns; .dta 22.6 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 24 ms / 0.04 s / 243 MB | 74 ms / 0.24 s / 397 MB | 72 ms / 0.24 s / 395 MB | 239 ms / 0.24 s / 226 MB | 48 ms / 0.12 s / 387 MB | 54 ms / 0.15 s / 272 MB | 24 ms / 0.03 s / 257 MB | 138 ms / 0.14 s / 462 MB |
| whole file | polars | 26 ms / 0.05 s / 243 MB | 73 ms / 0.24 s / 396 MB | 75 ms / 0.25 s / 396 MB | 245 ms / 0.25 s / 223 MB | 53 ms / 0.12 s / 386 MB | – | – | – |
| whole file | ours | 29 ms / 0.05 s / 252 MB | 73 ms / 0.24 s / 399 MB | 72 ms / 0.23 s / 400 MB | 232 ms / 0.23 s / 225 MB | 48 ms / 0.12 s / 388 MB | – | – | – |
| five columns | pyarrow | 2 ms / 0.00 s / 112 MB | 25 ms / 0.03 s / 130 MB | 26 ms / 0.03 s / 130 MB | 32 ms / 0.03 s / 129 MB | 5 ms / 0.01 s / 171 MB | 25 ms / 0.03 s / 129 MB | 5 ms / 0.01 s / 170 MB | 9 ms / 0.01 s / 149 MB |
| five columns | polars | 2 ms / 0.00 s / 113 MB | 25 ms / 0.03 s / 130 MB | 25 ms / 0.03 s / 130 MB | 29 ms / 0.03 s / 126 MB | 5 ms / 0.01 s / 171 MB | – | – | – |
| five columns | ours | 3 ms / 0.00 s / 113 MB | 25 ms / 0.03 s / 134 MB | 25 ms / 0.03 s / 133 MB | 29 ms / 0.03 s / 127 MB | 5 ms / 0.01 s / 173 MB | – | – | – |
| 1,000 rows | pyarrow | 14 ms / 0.02 s / 143 MB | 76 ms / 0.23 s / 295 MB | 73 ms / 0.23 s / 396 MB | 244 ms / 0.24 s / 226 MB | 40 ms / 0.09 s / 221 MB | 55 ms / 0.16 s / 273 MB | 15 ms / 0.02 s / 191 MB | 153 ms / 0.56 s / 1104 MB |
| 1,000 rows | polars | 16 ms / 0.02 s / 143 MB | 74 ms / 0.23 s / 297 MB | 73 ms / 0.25 s / 398 MB | 247 ms / 0.25 s / 224 MB | 44 ms / 0.09 s / 220 MB | – | – | – |
| 1,000 rows | ours | 19 ms / 0.03 s / 151 MB | 75 ms / 0.21 s / 300 MB | 72 ms / 0.24 s / 399 MB | 233 ms / 0.23 s / 225 MB | 40 ms / 0.09 s / 222 MB | – | – | – |
| read + pass | pyarrow | 93 ms / 0.11 s / 244 MB | 137 ms / 0.30 s / 397 MB | 136 ms / 0.30 s / 397 MB | 330 ms / 0.33 s / 227 MB | 112 ms / 0.18 s / 388 MB | – | – | – |
| read + pass | polars | 95 ms / 0.11 s / 245 MB | 137 ms / 0.32 s / 397 MB | 137 ms / 0.31 s / 397 MB | 337 ms / 0.34 s / 225 MB | 120 ms / 0.18 s / 386 MB | – | – | – |
| read + pass | ours | 97 ms / 0.11 s / 253 MB | 141 ms / 0.29 s / 402 MB | 142 ms / 0.29 s / 402 MB | 324 ms / 0.32 s / 226 MB | 113 ms / 0.18 s / 390 MB | – | – | – |
| write, defaults | dta | 67 ms / 0.12 s / 247 MB | 255 ms / 0.26 s / 267 MB | – | 688 ms / 0.69 s / 254 MB | 142 ms / 0.34 s / 358 MB | – | – | – |
| write, zstd 3 | dta | 75 ms / 0.14 s / 249 MB | 273 ms / 0.27 s / 269 MB | – | 742 ms / 0.74 s / 254 MB | 141 ms / 0.33 s / 358 MB | – | – | – |

### 2011_2013_Male

4,815 rows, 3,059 columns; .dta 19.4 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 20 ms / 0.03 s / 232 MB | 69 ms / 0.21 s / 346 MB | 72 ms / 0.21 s / 347 MB | 225 ms / 0.23 s / 214 MB | 42 ms / 0.10 s / 360 MB | 53 ms / 0.14 s / 233 MB | 19 ms / 0.02 s / 241 MB | 131 ms / 0.13 s / 456 MB |
| whole file | polars | 21 ms / 0.04 s / 232 MB | 73 ms / 0.22 s / 347 MB | 73 ms / 0.22 s / 347 MB | 230 ms / 0.23 s / 212 MB | 46 ms / 0.11 s / 360 MB | – | – | – |
| whole file | ours | 24 ms / 0.04 s / 240 MB | 68 ms / 0.21 s / 348 MB | 68 ms / 0.21 s / 348 MB | 216 ms / 0.22 s / 212 MB | 44 ms / 0.11 s / 361 MB | – | – | – |
| five columns | pyarrow | 2 ms / 0.00 s / 113 MB | 25 ms / 0.03 s / 130 MB | 26 ms / 0.03 s / 130 MB | 32 ms / 0.03 s / 129 MB | 5 ms / 0.01 s / 171 MB | 25 ms / 0.03 s / 130 MB | 4 ms / 0.01 s / 170 MB | 8 ms / 0.01 s / 148 MB |
| five columns | polars | 2 ms / 0.00 s / 112 MB | 25 ms / 0.03 s / 130 MB | 25 ms / 0.03 s / 131 MB | 29 ms / 0.03 s / 126 MB | 5 ms / 0.01 s / 171 MB | – | – | – |
| five columns | ours | 3 ms / 0.00 s / 113 MB | 25 ms / 0.03 s / 133 MB | 25 ms / 0.03 s / 133 MB | 29 ms / 0.03 s / 126 MB | 5 ms / 0.01 s / 172 MB | – | – | – |
| 1,000 rows | pyarrow | 13 ms / 0.02 s / 144 MB | 74 ms / 0.20 s / 260 MB | 74 ms / 0.21 s / 348 MB | 231 ms / 0.23 s / 214 MB | 38 ms / 0.09 s / 220 MB | 57 ms / 0.14 s / 234 MB | 14 ms / 0.02 s / 189 MB | 155 ms / 0.54 s / 1104 MB |
| 1,000 rows | polars | 14 ms / 0.02 s / 144 MB | 72 ms / 0.21 s / 259 MB | 71 ms / 0.23 s / 348 MB | 233 ms / 0.23 s / 213 MB | 40 ms / 0.09 s / 219 MB | – | – | – |
| 1,000 rows | ours | 17 ms / 0.02 s / 151 MB | 72 ms / 0.21 s / 260 MB | 69 ms / 0.20 s / 349 MB | 218 ms / 0.22 s / 213 MB | 37 ms / 0.08 s / 221 MB | – | – | – |
| read + pass | pyarrow | 77 ms / 0.09 s / 234 MB | 125 ms / 0.27 s / 348 MB | 126 ms / 0.27 s / 349 MB | 300 ms / 0.30 s / 214 MB | 96 ms / 0.16 s / 361 MB | – | – | – |
| read + pass | polars | 78 ms / 0.09 s / 233 MB | 126 ms / 0.27 s / 351 MB | 121 ms / 0.27 s / 347 MB | 305 ms / 0.30 s / 212 MB | 97 ms / 0.16 s / 362 MB | – | – | – |
| read + pass | ours | 81 ms / 0.09 s / 241 MB | 122 ms / 0.26 s / 349 MB | 120 ms / 0.26 s / 350 MB | 293 ms / 0.29 s / 213 MB | 94 ms / 0.16 s / 363 MB | – | – | – |
| write, defaults | dta | 50 ms / 0.09 s / 237 MB | 204 ms / 0.20 s / 257 MB | – | 669 ms / 0.67 s / 243 MB | 129 ms / 0.29 s / 339 MB | – | – | – |
| write, zstd 3 | dta | 57 ms / 0.10 s / 237 MB | 218 ms / 0.22 s / 258 MB | – | 697 ms / 0.70 s / 244 MB | 130 ms / 0.29 s / 338 MB | – | – | – |

### 2011_2019_FemaleWgt

22,995 rows, 7 columns; .dta 1.2 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 1 ms / 0.00 s / 112 MB | 17 ms / 0.02 s / 125 MB | 18 ms / 0.02 s / 125 MB | 2 ms / 0.00 s / 117 MB | 3 ms / 0.01 s / 166 MB | 17 ms / 0.02 s / 123 MB | 2 ms / 0.01 s / 164 MB | 2 ms / 0.00 s / 144 MB |
| whole file | polars | 1 ms / 0.00 s / 112 MB | 18 ms / 0.02 s / 124 MB | 18 ms / 0.02 s / 124 MB | 2 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| whole file | ours | 1 ms / 0.00 s / 111 MB | 17 ms / 0.02 s / 124 MB | 18 ms / 0.02 s / 124 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 165 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 123 MB | 18 ms / 0.02 s / 123 MB | 2 ms / 0.00 s / 118 MB | 2 ms / 0.01 s / 166 MB | 17 ms / 0.02 s / 122 MB | 2 ms / 0.01 s / 163 MB | 1 ms / 0.00 s / 143 MB |
| five columns | polars | 1 ms / 0.00 s / 111 MB | 17 ms / 0.02 s / 123 MB | 18 ms / 0.02 s / 123 MB | 2 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 166 MB | – | – | – |
| five columns | ours | 0 ms / 0.00 s / 112 MB | 17 ms / 0.02 s / 122 MB | 17 ms / 0.02 s / 122 MB | 2 ms / 0.00 s / 118 MB | 2 ms / 0.01 s / 165 MB | – | – | – |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 111 MB | 17 ms / 0.02 s / 123 MB | 18 ms / 0.02 s / 125 MB | 2 ms / 0.00 s / 118 MB | 2 ms / 0.01 s / 164 MB | 17 ms / 0.02 s / 123 MB | 2 ms / 0.01 s / 162 MB | 2 ms / 0.00 s / 151 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 123 MB | 18 ms / 0.02 s / 124 MB | 2 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 163 MB | – | – | – |
| 1,000 rows | ours | 0 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 123 MB | 18 ms / 0.02 s / 124 MB | 2 ms / 0.00 s / 118 MB | 2 ms / 0.01 s / 163 MB | – | – | – |
| read + pass | pyarrow | 1 ms / 0.00 s / 113 MB | 18 ms / 0.02 s / 124 MB | 18 ms / 0.02 s / 125 MB | 3 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 167 MB | – | – | – |
| read + pass | polars | 2 ms / 0.00 s / 112 MB | 18 ms / 0.02 s / 125 MB | 18 ms / 0.02 s / 124 MB | 3 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 166 MB | – | – | – |
| read + pass | ours | 1 ms / 0.00 s / 112 MB | 18 ms / 0.02 s / 125 MB | 18 ms / 0.02 s / 125 MB | 2 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 166 MB | – | – | – |
| write, defaults | dta | 2 ms / 0.00 s / 113 MB | 6 ms / 0.01 s / 127 MB | – | 3 ms / 0.00 s / 119 MB | 4 ms / 0.01 s / 168 MB | – | – | – |
| write, zstd 3 | dta | 3 ms / 0.00 s / 114 MB | 7 ms / 0.01 s / 126 MB | – | 5 ms / 0.00 s / 120 MB | 3 ms / 0.01 s / 168 MB | – | – | – |

### 2011_2019_MaleWgt

19,067 rows, 7 columns; .dta 1.0 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 125 MB | 18 ms / 0.02 s / 125 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 165 MB | 17 ms / 0.02 s / 124 MB | 2 ms / 0.01 s / 163 MB | 1 ms / 0.00 s / 144 MB |
| whole file | polars | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 124 MB | 18 ms / 0.02 s / 125 MB | 2 ms / 0.00 s / 117 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| whole file | ours | 0 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 124 MB | 18 ms / 0.02 s / 124 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 165 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 123 MB | 18 ms / 0.02 s / 123 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 165 MB | 17 ms / 0.02 s / 122 MB | 2 ms / 0.01 s / 164 MB | 1 ms / 0.00 s / 143 MB |
| five columns | polars | 1 ms / 0.00 s / 110 MB | 18 ms / 0.02 s / 123 MB | 17 ms / 0.02 s / 123 MB | 2 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| five columns | ours | 0 ms / 0.00 s / 111 MB | 17 ms / 0.02 s / 123 MB | 17 ms / 0.02 s / 122 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 165 MB | – | – | – |
| 1,000 rows | pyarrow | 0 ms / 0.00 s / 111 MB | 17 ms / 0.02 s / 124 MB | 18 ms / 0.02 s / 125 MB | 2 ms / 0.00 s / 118 MB | 2 ms / 0.01 s / 163 MB | 18 ms / 0.02 s / 124 MB | 2 ms / 0.01 s / 162 MB | 2 ms / 0.00 s / 151 MB |
| 1,000 rows | polars | 1 ms / 0.00 s / 111 MB | 17 ms / 0.02 s / 123 MB | 18 ms / 0.02 s / 125 MB | 2 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 163 MB | – | – | – |
| 1,000 rows | ours | 0 ms / 0.00 s / 110 MB | 17 ms / 0.02 s / 123 MB | 18 ms / 0.02 s / 124 MB | 2 ms / 0.00 s / 118 MB | 2 ms / 0.01 s / 162 MB | – | – | – |
| read + pass | pyarrow | 1 ms / 0.00 s / 112 MB | 18 ms / 0.02 s / 126 MB | 18 ms / 0.02 s / 126 MB | 2 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 166 MB | – | – | – |
| read + pass | polars | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 125 MB | 18 ms / 0.02 s / 125 MB | 2 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 166 MB | – | – | – |
| read + pass | ours | 1 ms / 0.00 s / 112 MB | 18 ms / 0.02 s / 125 MB | 18 ms / 0.02 s / 125 MB | 2 ms / 0.00 s / 117 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| write, defaults | dta | 2 ms / 0.00 s / 113 MB | 5 ms / 0.01 s / 123 MB | – | 4 ms / 0.00 s / 119 MB | 3 ms / 0.01 s / 167 MB | – | – | – |
| write, zstd 3 | dta | 3 ms / 0.00 s / 114 MB | 6 ms / 0.01 s / 122 MB | – | 4 ms / 0.00 s / 119 MB | 3 ms / 0.01 s / 167 MB | – | – | – |

### 2013_2015_FemPreg

9,358 rows, 278 columns; .dta 3.4 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 4 ms / 0.01 s / 130 MB | 23 ms / 0.04 s / 159 MB | 24 ms / 0.04 s / 160 MB | 23 ms / 0.02 s / 130 MB | 8 ms / 0.02 s / 196 MB | 21 ms / 0.03 s / 140 MB | 4 ms / 0.01 s / 175 MB | 13 ms / 0.01 s / 184 MB |
| whole file | polars | 4 ms / 0.01 s / 129 MB | 23 ms / 0.04 s / 158 MB | 23 ms / 0.05 s / 159 MB | 24 ms / 0.02 s / 130 MB | 9 ms / 0.02 s / 196 MB | – | – | – |
| whole file | ours | 4 ms / 0.01 s / 131 MB | 23 ms / 0.04 s / 159 MB | 24 ms / 0.04 s / 160 MB | 22 ms / 0.02 s / 131 MB | 8 ms / 0.02 s / 196 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 122 MB | 18 ms / 0.02 s / 122 MB | 4 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 165 MB | 18 ms / 0.02 s / 121 MB | 2 ms / 0.01 s / 163 MB | 2 ms / 0.00 s / 142 MB |
| five columns | polars | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 122 MB | 18 ms / 0.02 s / 122 MB | 4 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| five columns | ours | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 122 MB | 19 ms / 0.02 s / 123 MB | 4 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| 1,000 rows | pyarrow | 2 ms / 0.00 s / 112 MB | 23 ms / 0.04 s / 144 MB | 24 ms / 0.05 s / 160 MB | 23 ms / 0.02 s / 131 MB | 6 ms / 0.02 s / 169 MB | 21 ms / 0.03 s / 141 MB | 3 ms / 0.01 s / 164 MB | 12 ms / 0.04 s / 232 MB |
| 1,000 rows | polars | 3 ms / 0.00 s / 112 MB | 23 ms / 0.04 s / 143 MB | 23 ms / 0.04 s / 158 MB | 24 ms / 0.02 s / 130 MB | 7 ms / 0.02 s / 169 MB | – | – | – |
| 1,000 rows | ours | 3 ms / 0.00 s / 113 MB | 23 ms / 0.04 s / 144 MB | 24 ms / 0.04 s / 160 MB | 22 ms / 0.02 s / 130 MB | 6 ms / 0.02 s / 169 MB | – | – | – |
| read + pass | pyarrow | 12 ms / 0.01 s / 133 MB | 31 ms / 0.05 s / 160 MB | 32 ms / 0.05 s / 160 MB | 34 ms / 0.03 s / 132 MB | 16 ms / 0.03 s / 197 MB | – | – | – |
| read + pass | polars | 12 ms / 0.02 s / 132 MB | 31 ms / 0.05 s / 160 MB | 32 ms / 0.05 s / 159 MB | 35 ms / 0.04 s / 132 MB | 17 ms / 0.03 s / 197 MB | – | – | – |
| read + pass | ours | 13 ms / 0.02 s / 134 MB | 31 ms / 0.05 s / 160 MB | 31 ms / 0.05 s / 160 MB | 34 ms / 0.03 s / 132 MB | 16 ms / 0.03 s / 197 MB | – | – | – |
| write, defaults | dta | 15 ms / 0.02 s / 130 MB | 36 ms / 0.04 s / 137 MB | – | 67 ms / 0.07 s / 138 MB | 18 ms / 0.05 s / 195 MB | – | – | – |
| write, zstd 3 | dta | 17 ms / 0.02 s / 131 MB | 38 ms / 0.04 s / 138 MB | – | 77 ms / 0.08 s / 138 MB | 19 ms / 0.05 s / 195 MB | – | – | – |

### 2013_2015_FemResp

5,699 rows, 3,207 columns; .dta 24.0 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 25 ms / 0.04 s / 250 MB | 75 ms / 0.24 s / 408 MB | 75 ms / 0.25 s / 408 MB | 249 ms / 0.25 s / 230 MB | 49 ms / 0.12 s / 396 MB | 56 ms / 0.16 s / 278 MB | 24 ms / 0.03 s / 260 MB | 145 ms / 0.15 s / 473 MB |
| whole file | polars | 27 ms / 0.05 s / 250 MB | 77 ms / 0.26 s / 408 MB | 77 ms / 0.26 s / 408 MB | 255 ms / 0.26 s / 229 MB | 53 ms / 0.12 s / 396 MB | – | – | – |
| whole file | ours | 32 ms / 0.05 s / 263 MB | 76 ms / 0.24 s / 412 MB | 75 ms / 0.24 s / 413 MB | 239 ms / 0.24 s / 231 MB | 49 ms / 0.12 s / 398 MB | – | – | – |
| five columns | pyarrow | 2 ms / 0.00 s / 112 MB | 26 ms / 0.03 s / 131 MB | 26 ms / 0.03 s / 132 MB | 32 ms / 0.03 s / 129 MB | 5 ms / 0.01 s / 171 MB | 25 ms / 0.03 s / 130 MB | 5 ms / 0.01 s / 170 MB | 9 ms / 0.01 s / 150 MB |
| five columns | polars | 2 ms / 0.00 s / 113 MB | 25 ms / 0.03 s / 131 MB | 25 ms / 0.03 s / 131 MB | 30 ms / 0.03 s / 126 MB | 5 ms / 0.01 s / 171 MB | – | – | – |
| five columns | ours | 4 ms / 0.00 s / 115 MB | 26 ms / 0.03 s / 135 MB | 26 ms / 0.03 s / 136 MB | 29 ms / 0.03 s / 128 MB | 5 ms / 0.01 s / 175 MB | – | – | – |
| 1,000 rows | pyarrow | 15 ms / 0.02 s / 144 MB | 77 ms / 0.23 s / 299 MB | 75 ms / 0.24 s / 408 MB | 250 ms / 0.25 s / 231 MB | 39 ms / 0.09 s / 222 MB | 57 ms / 0.16 s / 279 MB | 15 ms / 0.02 s / 192 MB | 160 ms / 0.57 s / 1147 MB |
| 1,000 rows | polars | 17 ms / 0.03 s / 144 MB | 78 ms / 0.25 s / 302 MB | 74 ms / 0.27 s / 408 MB | 257 ms / 0.26 s / 228 MB | 45 ms / 0.09 s / 222 MB | – | – | – |
| 1,000 rows | ours | 21 ms / 0.03 s / 157 MB | 75 ms / 0.21 s / 307 MB | 76 ms / 0.24 s / 412 MB | 244 ms / 0.24 s / 230 MB | 37 ms / 0.08 s / 224 MB | – | – | – |
| read + pass | pyarrow | 98 ms / 0.12 s / 251 MB | 143 ms / 0.31 s / 409 MB | 144 ms / 0.31 s / 409 MB | 343 ms / 0.34 s / 231 MB | 116 ms / 0.19 s / 397 MB | – | – | – |
| read + pass | polars | 99 ms / 0.12 s / 251 MB | 144 ms / 0.32 s / 411 MB | 144 ms / 0.32 s / 408 MB | 349 ms / 0.35 s / 230 MB | 121 ms / 0.19 s / 397 MB | – | – | – |
| read + pass | ours | 105 ms / 0.12 s / 264 MB | 141 ms / 0.30 s / 413 MB | 143 ms / 0.31 s / 413 MB | 337 ms / 0.34 s / 230 MB | 116 ms / 0.19 s / 400 MB | – | – | – |
| write, defaults | dta | 70 ms / 0.12 s / 259 MB | 271 ms / 0.27 s / 274 MB | – | 720 ms / 0.72 s / 260 MB | 146 ms / 0.34 s / 364 MB | – | – | – |
| write, zstd 3 | dta | 73 ms / 0.13 s / 259 MB | 288 ms / 0.29 s / 274 MB | – | 762 ms / 0.76 s / 260 MB | 143 ms / 0.35 s / 366 MB | – | – | – |

### 2013_2015_Male

4,506 rows, 2,940 columns; .dta 18.0 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 19 ms / 0.03 s / 220 MB | 68 ms / 0.21 s / 331 MB | 68 ms / 0.21 s / 332 MB | 216 ms / 0.22 s / 211 MB | 41 ms / 0.10 s / 346 MB | 51 ms / 0.14 s / 230 MB | 18 ms / 0.02 s / 238 MB | 123 ms / 0.12 s / 445 MB |
| whole file | polars | 20 ms / 0.03 s / 220 MB | 68 ms / 0.22 s / 331 MB | 68 ms / 0.22 s / 330 MB | 217 ms / 0.22 s / 209 MB | 44 ms / 0.10 s / 346 MB | – | – | – |
| whole file | ours | 24 ms / 0.04 s / 230 MB | 66 ms / 0.20 s / 333 MB | 66 ms / 0.20 s / 334 MB | 204 ms / 0.20 s / 209 MB | 40 ms / 0.10 s / 347 MB | – | – | – |
| five columns | pyarrow | 2 ms / 0.00 s / 112 MB | 24 ms / 0.03 s / 129 MB | 25 ms / 0.03 s / 129 MB | 30 ms / 0.03 s / 128 MB | 5 ms / 0.01 s / 171 MB | 24 ms / 0.02 s / 129 MB | 4 ms / 0.01 s / 169 MB | 8 ms / 0.01 s / 149 MB |
| five columns | polars | 2 ms / 0.00 s / 112 MB | 24 ms / 0.03 s / 130 MB | 25 ms / 0.03 s / 129 MB | 27 ms / 0.03 s / 125 MB | 5 ms / 0.01 s / 171 MB | – | – | – |
| five columns | ours | 3 ms / 0.00 s / 113 MB | 25 ms / 0.03 s / 132 MB | 26 ms / 0.03 s / 133 MB | 27 ms / 0.03 s / 127 MB | 5 ms / 0.01 s / 173 MB | – | – | – |
| 1,000 rows | pyarrow | 13 ms / 0.02 s / 143 MB | 70 ms / 0.19 s / 253 MB | 67 ms / 0.20 s / 331 MB | 217 ms / 0.22 s / 210 MB | 35 ms / 0.08 s / 218 MB | 51 ms / 0.14 s / 231 MB | 13 ms / 0.02 s / 188 MB | 144 ms / 0.53 s / 1068 MB |
| 1,000 rows | polars | 14 ms / 0.02 s / 143 MB | 68 ms / 0.20 s / 253 MB | 68 ms / 0.21 s / 331 MB | 223 ms / 0.22 s / 208 MB | 39 ms / 0.09 s / 217 MB | – | – | – |
| 1,000 rows | ours | 18 ms / 0.02 s / 153 MB | 70 ms / 0.19 s / 255 MB | 65 ms / 0.19 s / 334 MB | 210 ms / 0.21 s / 208 MB | 37 ms / 0.08 s / 220 MB | – | – | – |
| read + pass | pyarrow | 73 ms / 0.09 s / 222 MB | 115 ms / 0.25 s / 331 MB | 116 ms / 0.25 s / 331 MB | 285 ms / 0.29 s / 211 MB | 89 ms / 0.14 s / 347 MB | – | – | – |
| read + pass | polars | 73 ms / 0.09 s / 222 MB | 117 ms / 0.27 s / 331 MB | 117 ms / 0.26 s / 331 MB | 291 ms / 0.29 s / 209 MB | 93 ms / 0.15 s / 346 MB | – | – | – |
| read + pass | ours | 80 ms / 0.09 s / 232 MB | 114 ms / 0.25 s / 335 MB | 114 ms / 0.24 s / 335 MB | 280 ms / 0.28 s / 210 MB | 88 ms / 0.15 s / 348 MB | – | – | – |
| write, defaults | dta | 48 ms / 0.08 s / 226 MB | 190 ms / 0.19 s / 242 MB | – | 641 ms / 0.64 s / 230 MB | 124 ms / 0.28 s / 324 MB | – | – | – |
| write, zstd 3 | dta | 51 ms / 0.09 s / 228 MB | 204 ms / 0.20 s / 242 MB | – | 670 ms / 0.67 s / 230 MB | 125 ms / 0.28 s / 323 MB | – | – | – |

### 2015_2017_FemPreg

9,553 rows, 248 columns; .dta 3.0 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 5 ms / 0.00 s / 126 MB | 23 ms / 0.04 s / 155 MB | 23 ms / 0.04 s / 155 MB | 20 ms / 0.02 s / 129 MB | 7 ms / 0.02 s / 192 MB | 20 ms / 0.03 s / 138 MB | 4 ms / 0.01 s / 174 MB | 12 ms / 0.01 s / 179 MB |
| whole file | polars | 5 ms / 0.01 s / 127 MB | 22 ms / 0.04 s / 155 MB | 23 ms / 0.04 s / 154 MB | 21 ms / 0.02 s / 129 MB | 8 ms / 0.02 s / 192 MB | – | – | – |
| whole file | ours | 5 ms / 0.01 s / 128 MB | 23 ms / 0.04 s / 156 MB | 23 ms / 0.04 s / 156 MB | 20 ms / 0.02 s / 129 MB | 8 ms / 0.02 s / 192 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 122 MB | 18 ms / 0.02 s / 122 MB | 4 ms / 0.00 s / 118 MB | 3 ms / 0.01 s / 165 MB | 18 ms / 0.02 s / 121 MB | 2 ms / 0.01 s / 163 MB | 2 ms / 0.00 s / 142 MB |
| five columns | polars | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 122 MB | 18 ms / 0.02 s / 122 MB | 4 ms / 0.00 s / 117 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| five columns | ours | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 122 MB | 18 ms / 0.02 s / 123 MB | 4 ms / 0.00 s / 117 MB | 3 ms / 0.01 s / 165 MB | – | – | – |
| 1,000 rows | pyarrow | 2 ms / 0.00 s / 112 MB | 22 ms / 0.04 s / 141 MB | 23 ms / 0.04 s / 155 MB | 20 ms / 0.02 s / 130 MB | 6 ms / 0.02 s / 168 MB | 21 ms / 0.03 s / 138 MB | 3 ms / 0.01 s / 164 MB | 11 ms / 0.04 s / 222 MB |
| 1,000 rows | polars | 3 ms / 0.00 s / 113 MB | 22 ms / 0.04 s / 140 MB | 22 ms / 0.04 s / 154 MB | 21 ms / 0.02 s / 129 MB | 6 ms / 0.02 s / 167 MB | – | – | – |
| 1,000 rows | ours | 3 ms / 0.00 s / 113 MB | 22 ms / 0.04 s / 141 MB | 22 ms / 0.04 s / 155 MB | 20 ms / 0.02 s / 129 MB | 6 ms / 0.02 s / 168 MB | – | – | – |
| read + pass | pyarrow | 13 ms / 0.01 s / 128 MB | 30 ms / 0.05 s / 156 MB | 30 ms / 0.05 s / 156 MB | 31 ms / 0.03 s / 131 MB | 14 ms / 0.03 s / 193 MB | – | – | – |
| read + pass | polars | 13 ms / 0.01 s / 128 MB | 30 ms / 0.05 s / 155 MB | 30 ms / 0.05 s / 155 MB | 32 ms / 0.03 s / 130 MB | 15 ms / 0.03 s / 193 MB | – | – | – |
| read + pass | ours | 13 ms / 0.01 s / 130 MB | 29 ms / 0.05 s / 156 MB | 31 ms / 0.05 s / 156 MB | 30 ms / 0.03 s / 130 MB | 15 ms / 0.03 s / 193 MB | – | – | – |
| write, defaults | dta | 13 ms / 0.01 s / 128 MB | 32 ms / 0.03 s / 134 MB | – | 62 ms / 0.06 s / 136 MB | 17 ms / 0.04 s / 192 MB | – | – | – |
| write, zstd 3 | dta | 15 ms / 0.02 s / 128 MB | 35 ms / 0.03 s / 134 MB | – | 69 ms / 0.07 s / 137 MB | 17 ms / 0.04 s / 192 MB | – | – | – |

### 2015_2017_FemResp

5,554 rows, 3,024 columns; .dta 21.7 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 23 ms / 0.04 s / 238 MB | 73 ms / 0.23 s / 386 MB | 71 ms / 0.23 s / 387 MB | 231 ms / 0.23 s / 223 MB | 47 ms / 0.11 s / 379 MB | 53 ms / 0.15 s / 268 MB | 23 ms / 0.03 s / 254 MB | 134 ms / 0.13 s / 455 MB |
| whole file | polars | 25 ms / 0.04 s / 238 MB | 71 ms / 0.24 s / 387 MB | 72 ms / 0.24 s / 386 MB | 240 ms / 0.24 s / 221 MB | 52 ms / 0.12 s / 378 MB | – | – | – |
| whole file | ours | 30 ms / 0.05 s / 250 MB | 71 ms / 0.23 s / 392 MB | 70 ms / 0.23 s / 391 MB | 228 ms / 0.23 s / 222 MB | 48 ms / 0.11 s / 380 MB | – | – | – |
| five columns | pyarrow | 2 ms / 0.00 s / 113 MB | 25 ms / 0.03 s / 129 MB | 25 ms / 0.03 s / 129 MB | 31 ms / 0.03 s / 128 MB | 5 ms / 0.01 s / 171 MB | 24 ms / 0.03 s / 128 MB | 4 ms / 0.01 s / 170 MB | 8 ms / 0.01 s / 149 MB |
| five columns | polars | 2 ms / 0.00 s / 112 MB | 25 ms / 0.03 s / 130 MB | 25 ms / 0.03 s / 130 MB | 28 ms / 0.03 s / 127 MB | 5 ms / 0.01 s / 171 MB | – | – | – |
| five columns | ours | 3 ms / 0.00 s / 115 MB | 25 ms / 0.03 s / 134 MB | 26 ms / 0.03 s / 135 MB | 28 ms / 0.03 s / 128 MB | 5 ms / 0.01 s / 174 MB | – | – | – |
| 1,000 rows | pyarrow | 14 ms / 0.02 s / 142 MB | 73 ms / 0.22 s / 292 MB | 72 ms / 0.24 s / 387 MB | 234 ms / 0.23 s / 223 MB | 38 ms / 0.09 s / 218 MB | 54 ms / 0.16 s / 269 MB | 15 ms / 0.02 s / 189 MB | 149 ms / 0.54 s / 1093 MB |
| 1,000 rows | polars | 16 ms / 0.02 s / 142 MB | 71 ms / 0.22 s / 291 MB | 72 ms / 0.24 s / 387 MB | 238 ms / 0.24 s / 220 MB | 43 ms / 0.10 s / 217 MB | – | – | – |
| 1,000 rows | ours | 20 ms / 0.03 s / 153 MB | 72 ms / 0.21 s / 295 MB | 71 ms / 0.23 s / 392 MB | 230 ms / 0.23 s / 222 MB | 39 ms / 0.09 s / 219 MB | – | – | – |
| read + pass | pyarrow | 92 ms / 0.11 s / 239 MB | 136 ms / 0.30 s / 387 MB | 135 ms / 0.30 s / 388 MB | 320 ms / 0.32 s / 223 MB | 111 ms / 0.18 s / 380 MB | – | – | – |
| read + pass | polars | 94 ms / 0.11 s / 239 MB | 135 ms / 0.30 s / 388 MB | 137 ms / 0.31 s / 387 MB | 326 ms / 0.33 s / 222 MB | 113 ms / 0.19 s / 379 MB | – | – | – |
| read + pass | ours | 98 ms / 0.11 s / 251 MB | 134 ms / 0.28 s / 391 MB | 136 ms / 0.29 s / 392 MB | 314 ms / 0.31 s / 224 MB | 110 ms / 0.18 s / 381 MB | – | – | – |
| write, defaults | dta | 62 ms / 0.11 s / 249 MB | 247 ms / 0.25 s / 263 MB | – | 675 ms / 0.67 s / 250 MB | 137 ms / 0.32 s / 354 MB | – | – | – |
| write, zstd 3 | dta | 71 ms / 0.13 s / 248 MB | 262 ms / 0.26 s / 263 MB | – | 714 ms / 0.71 s / 251 MB | 135 ms / 0.32 s / 352 MB | – | – | – |

### 2015_2017_Male

4,540 rows, 2,945 columns; .dta 17.7 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 19 ms / 0.03 s / 222 MB | 67 ms / 0.20 s / 332 MB | 68 ms / 0.21 s / 332 MB | 214 ms / 0.21 s / 211 MB | 41 ms / 0.10 s / 347 MB | 51 ms / 0.14 s / 230 MB | 18 ms / 0.02 s / 238 MB | 124 ms / 0.13 s / 445 MB |
| whole file | polars | 20 ms / 0.03 s / 222 MB | 69 ms / 0.21 s / 331 MB | 68 ms / 0.22 s / 332 MB | 217 ms / 0.22 s / 208 MB | 44 ms / 0.10 s / 347 MB | – | – | – |
| whole file | ours | 24 ms / 0.04 s / 232 MB | 68 ms / 0.20 s / 334 MB | 68 ms / 0.20 s / 334 MB | 205 ms / 0.20 s / 208 MB | 40 ms / 0.10 s / 349 MB | – | – | – |
| five columns | pyarrow | 2 ms / 0.00 s / 112 MB | 25 ms / 0.03 s / 129 MB | 25 ms / 0.03 s / 129 MB | 30 ms / 0.03 s / 129 MB | 5 ms / 0.01 s / 171 MB | 24 ms / 0.02 s / 128 MB | 4 ms / 0.01 s / 170 MB | 8 ms / 0.01 s / 149 MB |
| five columns | polars | 2 ms / 0.00 s / 112 MB | 24 ms / 0.03 s / 130 MB | 24 ms / 0.03 s / 129 MB | 27 ms / 0.03 s / 125 MB | 5 ms / 0.01 s / 171 MB | – | – | – |
| five columns | ours | 3 ms / 0.00 s / 113 MB | 26 ms / 0.03 s / 134 MB | 25 ms / 0.03 s / 133 MB | 27 ms / 0.03 s / 126 MB | 5 ms / 0.01 s / 174 MB | – | – | – |
| 1,000 rows | pyarrow | 13 ms / 0.02 s / 143 MB | 72 ms / 0.21 s / 253 MB | 68 ms / 0.20 s / 332 MB | 219 ms / 0.22 s / 210 MB | 35 ms / 0.08 s / 218 MB | 52 ms / 0.14 s / 228 MB | 13 ms / 0.02 s / 188 MB | 144 ms / 0.52 s / 1066 MB |
| 1,000 rows | polars | 14 ms / 0.02 s / 143 MB | 69 ms / 0.20 s / 254 MB | 68 ms / 0.21 s / 332 MB | 224 ms / 0.22 s / 209 MB | 38 ms / 0.09 s / 217 MB | – | – | – |
| 1,000 rows | ours | 18 ms / 0.02 s / 153 MB | 70 ms / 0.20 s / 256 MB | 67 ms / 0.21 s / 336 MB | 210 ms / 0.21 s / 208 MB | 36 ms / 0.08 s / 219 MB | – | – | – |
| read + pass | pyarrow | 73 ms / 0.09 s / 224 MB | 117 ms / 0.26 s / 333 MB | 118 ms / 0.26 s / 333 MB | 288 ms / 0.29 s / 211 MB | 89 ms / 0.15 s / 348 MB | – | – | – |
| read + pass | polars | 75 ms / 0.09 s / 223 MB | 115 ms / 0.26 s / 333 MB | 116 ms / 0.27 s / 334 MB | 290 ms / 0.29 s / 210 MB | 93 ms / 0.15 s / 348 MB | – | – | – |
| read + pass | ours | 78 ms / 0.09 s / 233 MB | 117 ms / 0.25 s / 336 MB | 114 ms / 0.24 s / 335 MB | 277 ms / 0.28 s / 209 MB | 90 ms / 0.14 s / 350 MB | – | – | – |
| write, defaults | dta | 46 ms / 0.08 s / 227 MB | 191 ms / 0.19 s / 241 MB | – | 640 ms / 0.64 s / 230 MB | 123 ms / 0.28 s / 324 MB | – | – | – |
| write, zstd 3 | dta | 51 ms / 0.09 s / 228 MB | 202 ms / 0.20 s / 241 MB | – | 673 ms / 0.67 s / 230 MB | 125 ms / 0.28 s / 326 MB | – | – | – |

### 2017_2019_FemPreg

10,215 rows, 171 columns; .dta 2.2 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 4 ms / 0.00 s / 121 MB | 21 ms / 0.04 s / 143 MB | 21 ms / 0.04 s / 144 MB | 15 ms / 0.01 s / 125 MB | 6 ms / 0.02 s / 182 MB | 19 ms / 0.03 s / 132 MB | 4 ms / 0.01 s / 169 MB | 9 ms / 0.01 s / 166 MB |
| whole file | polars | 4 ms / 0.00 s / 122 MB | 21 ms / 0.04 s / 144 MB | 21 ms / 0.04 s / 144 MB | 16 ms / 0.02 s / 125 MB | 6 ms / 0.02 s / 182 MB | – | – | – |
| whole file | ours | 4 ms / 0.00 s / 122 MB | 21 ms / 0.03 s / 144 MB | 22 ms / 0.03 s / 144 MB | 15 ms / 0.01 s / 125 MB | 6 ms / 0.02 s / 182 MB | – | – | – |
| five columns | pyarrow | 0 ms / 0.00 s / 110 MB | 18 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 121 MB | 3 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 164 MB | 17 ms / 0.02 s / 120 MB | 2 ms / 0.01 s / 162 MB | 1 ms / 0.00 s / 141 MB |
| five columns | polars | 0 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 121 MB | 3 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 164 MB | – | – | – |
| five columns | ours | 1 ms / 0.00 s / 111 MB | 18 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 121 MB | 3 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 164 MB | – | – | – |
| 1,000 rows | pyarrow | 2 ms / 0.00 s / 111 MB | 20 ms / 0.03 s / 134 MB | 21 ms / 0.04 s / 144 MB | 15 ms / 0.02 s / 125 MB | 5 ms / 0.01 s / 166 MB | 19 ms / 0.03 s / 133 MB | 3 ms / 0.01 s / 163 MB | 8 ms / 0.03 s / 200 MB |
| 1,000 rows | polars | 2 ms / 0.00 s / 112 MB | 21 ms / 0.03 s / 134 MB | 21 ms / 0.04 s / 144 MB | 16 ms / 0.02 s / 125 MB | 5 ms / 0.01 s / 166 MB | – | – | – |
| 1,000 rows | ours | 2 ms / 0.00 s / 111 MB | 21 ms / 0.03 s / 134 MB | 21 ms / 0.04 s / 144 MB | 15 ms / 0.02 s / 125 MB | 4 ms / 0.01 s / 166 MB | – | – | – |
| read + pass | pyarrow | 10 ms / 0.01 s / 122 MB | 27 ms / 0.04 s / 145 MB | 27 ms / 0.04 s / 144 MB | 22 ms / 0.02 s / 124 MB | 12 ms / 0.02 s / 183 MB | – | – | – |
| read + pass | polars | 10 ms / 0.01 s / 122 MB | 27 ms / 0.04 s / 145 MB | 27 ms / 0.04 s / 145 MB | 23 ms / 0.02 s / 125 MB | 12 ms / 0.02 s / 182 MB | – | – | – |
| read + pass | ours | 10 ms / 0.01 s / 123 MB | 26 ms / 0.04 s / 145 MB | 27 ms / 0.04 s / 145 MB | 22 ms / 0.02 s / 124 MB | 12 ms / 0.02 s / 182 MB | – | – | – |
| write, defaults | dta | 11 ms / 0.01 s / 122 MB | 26 ms / 0.02 s / 127 MB | – | 41 ms / 0.04 s / 127 MB | 13 ms / 0.03 s / 184 MB | – | – | – |
| write, zstd 3 | dta | 12 ms / 0.01 s / 123 MB | 27 ms / 0.03 s / 128 MB | – | 46 ms / 0.05 s / 129 MB | 12 ms / 0.03 s / 184 MB | – | – | – |

### 2017_2019_FemResp

6,141 rows, 2,609 columns; .dta 20.2 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 22 ms / 0.04 s / 231 MB | 70 ms / 0.21 s / 362 MB | 65 ms / 0.20 s / 362 MB | 205 ms / 0.21 s / 212 MB | 42 ms / 0.10 s / 359 MB | 47 ms / 0.14 s / 251 MB | 23 ms / 0.03 s / 242 MB | 117 ms / 0.12 s / 412 MB |
| whole file | polars | 24 ms / 0.04 s / 232 MB | 67 ms / 0.23 s / 362 MB | 67 ms / 0.23 s / 362 MB | 209 ms / 0.21 s / 209 MB | 47 ms / 0.11 s / 359 MB | – | – | – |
| whole file | ours | 28 ms / 0.04 s / 242 MB | 65 ms / 0.21 s / 366 MB | 64 ms / 0.21 s / 367 MB | 199 ms / 0.20 s / 210 MB | 42 ms / 0.10 s / 362 MB | – | – | – |
| five columns | pyarrow | 2 ms / 0.00 s / 113 MB | 24 ms / 0.02 s / 129 MB | 24 ms / 0.02 s / 129 MB | 27 ms / 0.03 s / 126 MB | 5 ms / 0.01 s / 170 MB | 24 ms / 0.02 s / 128 MB | 4 ms / 0.01 s / 169 MB | 7 ms / 0.01 s / 148 MB |
| five columns | polars | 2 ms / 0.00 s / 112 MB | 24 ms / 0.02 s / 128 MB | 24 ms / 0.03 s / 129 MB | 25 ms / 0.02 s / 125 MB | 4 ms / 0.01 s / 170 MB | – | – | – |
| five columns | ours | 3 ms / 0.00 s / 114 MB | 25 ms / 0.03 s / 132 MB | 24 ms / 0.02 s / 132 MB | 24 ms / 0.02 s / 126 MB | 5 ms / 0.01 s / 173 MB | – | – | – |
| 1,000 rows | pyarrow | 13 ms / 0.02 s / 138 MB | 66 ms / 0.19 s / 269 MB | 65 ms / 0.21 s / 362 MB | 208 ms / 0.21 s / 211 MB | 33 ms / 0.07 s / 210 MB | 50 ms / 0.14 s / 250 MB | 14 ms / 0.02 s / 186 MB | 126 ms / 0.45 s / 966 MB |
| 1,000 rows | polars | 15 ms / 0.02 s / 138 MB | 65 ms / 0.20 s / 269 MB | 65 ms / 0.21 s / 362 MB | 209 ms / 0.21 s / 209 MB | 37 ms / 0.08 s / 210 MB | – | – | – |
| 1,000 rows | ours | 18 ms / 0.02 s / 149 MB | 67 ms / 0.19 s / 271 MB | 65 ms / 0.20 s / 366 MB | 202 ms / 0.20 s / 211 MB | 33 ms / 0.07 s / 213 MB | – | – | – |
| read + pass | pyarrow | 84 ms / 0.10 s / 232 MB | 123 ms / 0.27 s / 363 MB | 123 ms / 0.27 s / 364 MB | 284 ms / 0.28 s / 211 MB | 101 ms / 0.16 s / 360 MB | – | – | – |
| read + pass | polars | 88 ms / 0.11 s / 233 MB | 124 ms / 0.28 s / 363 MB | 122 ms / 0.27 s / 363 MB | 294 ms / 0.29 s / 209 MB | 105 ms / 0.16 s / 360 MB | – | – | – |
| read + pass | ours | 91 ms / 0.11 s / 244 MB | 123 ms / 0.26 s / 367 MB | 123 ms / 0.27 s / 367 MB | 283 ms / 0.28 s / 211 MB | 100 ms / 0.16 s / 362 MB | – | – | – |
| write, defaults | dta | 59 ms / 0.10 s / 231 MB | 232 ms / 0.23 s / 246 MB | – | 590 ms / 0.59 s / 234 MB | 106 ms / 0.29 s / 328 MB | – | – | – |
| write, zstd 3 | dta | 66 ms / 0.12 s / 232 MB | 251 ms / 0.25 s / 246 MB | – | 635 ms / 0.64 s / 233 MB | 107 ms / 0.29 s / 328 MB | – | – | – |

### 2017_2019_Male

5,206 rows, 3,009 columns; .dta 20.1 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 19 ms / 0.03 s / 239 MB | 71 ms / 0.22 s / 385 MB | 73 ms / 0.23 s / 387 MB | 223 ms / 0.22 s / 221 MB | 43 ms / 0.11 s / 377 MB | 53 ms / 0.15 s / 265 MB | 20 ms / 0.02 s / 252 MB | 131 ms / 0.13 s / 452 MB |
| whole file | polars | 22 ms / 0.04 s / 239 MB | 70 ms / 0.23 s / 386 MB | 70 ms / 0.23 s / 386 MB | 226 ms / 0.23 s / 219 MB | 47 ms / 0.11 s / 377 MB | – | – | – |
| whole file | ours | 26 ms / 0.04 s / 249 MB | 70 ms / 0.22 s / 388 MB | 69 ms / 0.22 s / 389 MB | 211 ms / 0.21 s / 220 MB | 42 ms / 0.11 s / 379 MB | – | – | – |
| five columns | pyarrow | 2 ms / 0.00 s / 113 MB | 25 ms / 0.03 s / 129 MB | 25 ms / 0.03 s / 129 MB | 30 ms / 0.03 s / 130 MB | 5 ms / 0.01 s / 171 MB | 24 ms / 0.02 s / 129 MB | 4 ms / 0.01 s / 169 MB | 8 ms / 0.01 s / 149 MB |
| five columns | polars | 2 ms / 0.00 s / 113 MB | 25 ms / 0.03 s / 129 MB | 24 ms / 0.03 s / 129 MB | 28 ms / 0.03 s / 127 MB | 5 ms / 0.01 s / 170 MB | – | – | – |
| five columns | ours | 3 ms / 0.00 s / 114 MB | 25 ms / 0.03 s / 134 MB | 25 ms / 0.03 s / 134 MB | 28 ms / 0.03 s / 127 MB | 5 ms / 0.01 s / 173 MB | – | – | – |
| 1,000 rows | pyarrow | 13 ms / 0.02 s / 143 MB | 73 ms / 0.21 s / 290 MB | 70 ms / 0.22 s / 386 MB | 227 ms / 0.23 s / 222 MB | 36 ms / 0.08 s / 217 MB | 54 ms / 0.15 s / 265 MB | 13 ms / 0.02 s / 188 MB | 147 ms / 0.56 s / 1085 MB |
| 1,000 rows | polars | 14 ms / 0.02 s / 145 MB | 75 ms / 0.21 s / 291 MB | 69 ms / 0.23 s / 386 MB | 231 ms / 0.23 s / 219 MB | 38 ms / 0.08 s / 217 MB | – | – | – |
| 1,000 rows | ours | 18 ms / 0.02 s / 153 MB | 73 ms / 0.20 s / 293 MB | 69 ms / 0.22 s / 388 MB | 214 ms / 0.21 s / 220 MB | 35 ms / 0.08 s / 219 MB | – | – | – |
| read + pass | pyarrow | 77 ms / 0.09 s / 240 MB | 121 ms / 0.27 s / 386 MB | 123 ms / 0.28 s / 386 MB | 300 ms / 0.30 s / 227 MB | 94 ms / 0.16 s / 379 MB | – | – | – |
| read + pass | polars | 78 ms / 0.09 s / 240 MB | 122 ms / 0.28 s / 387 MB | 122 ms / 0.28 s / 387 MB | 302 ms / 0.30 s / 225 MB | 97 ms / 0.16 s / 378 MB | – | – | – |
| read + pass | ours | 83 ms / 0.09 s / 250 MB | 118 ms / 0.26 s / 390 MB | 122 ms / 0.27 s / 389 MB | 288 ms / 0.29 s / 227 MB | 93 ms / 0.15 s / 380 MB | – | – | – |
| write, defaults | dta | 55 ms / 0.09 s / 260 MB | 206 ms / 0.21 s / 272 MB | – | 652 ms / 0.65 s / 258 MB | 115 ms / 0.28 s / 349 MB | – | – | – |
| write, zstd 3 | dta | 59 ms / 0.10 s / 258 MB | 218 ms / 0.22 s / 275 MB | – | 686 ms / 0.69 s / 260 MB | 116 ms / 0.28 s / 350 MB | – | – | – |

### 2022_2023_FemPreg

8,247 rows, 111 columns; .dta 1.2 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 2 ms / 0.00 s / 117 MB | 20 ms / 0.03 s / 134 MB | 20 ms / 0.03 s / 135 MB | 10 ms / 0.01 s / 121 MB | 4 ms / 0.01 s / 174 MB | 18 ms / 0.02 s / 129 MB | 3 ms / 0.01 s / 166 MB | 6 ms / 0.01 s / 157 MB |
| whole file | polars | 3 ms / 0.00 s / 116 MB | 20 ms / 0.03 s / 135 MB | 20 ms / 0.03 s / 135 MB | 10 ms / 0.01 s / 122 MB | 5 ms / 0.01 s / 174 MB | – | – | – |
| whole file | ours | 3 ms / 0.00 s / 116 MB | 20 ms / 0.03 s / 135 MB | 20 ms / 0.03 s / 135 MB | 10 ms / 0.01 s / 121 MB | 4 ms / 0.01 s / 174 MB | – | – | – |
| five columns | pyarrow | 0 ms / 0.00 s / 110 MB | 18 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 121 MB | 3 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 164 MB | 17 ms / 0.02 s / 120 MB | 2 ms / 0.01 s / 162 MB | 1 ms / 0.00 s / 141 MB |
| five columns | polars | 0 ms / 0.00 s / 110 MB | 18 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 121 MB | 3 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 164 MB | – | – | – |
| five columns | ours | 0 ms / 0.00 s / 110 MB | 18 ms / 0.02 s / 121 MB | 18 ms / 0.02 s / 121 MB | 2 ms / 0.00 s / 117 MB | 2 ms / 0.01 s / 163 MB | – | – | – |
| 1,000 rows | pyarrow | 1 ms / 0.00 s / 110 MB | 19 ms / 0.03 s / 130 MB | 20 ms / 0.03 s / 134 MB | 10 ms / 0.01 s / 121 MB | 4 ms / 0.01 s / 164 MB | 19 ms / 0.02 s / 128 MB | 2 ms / 0.01 s / 162 MB | 6 ms / 0.02 s / 179 MB |
| 1,000 rows | polars | 2 ms / 0.00 s / 111 MB | 19 ms / 0.03 s / 130 MB | 20 ms / 0.03 s / 135 MB | 10 ms / 0.01 s / 121 MB | 4 ms / 0.01 s / 164 MB | – | – | – |
| 1,000 rows | ours | 1 ms / 0.00 s / 111 MB | 20 ms / 0.03 s / 130 MB | 21 ms / 0.03 s / 134 MB | 10 ms / 0.01 s / 121 MB | 4 ms / 0.01 s / 164 MB | – | – | – |
| read + pass | pyarrow | 6 ms / 0.01 s / 117 MB | 23 ms / 0.03 s / 135 MB | 24 ms / 0.03 s / 135 MB | 14 ms / 0.01 s / 121 MB | 8 ms / 0.02 s / 174 MB | – | – | – |
| read + pass | polars | 6 ms / 0.01 s / 117 MB | 23 ms / 0.03 s / 136 MB | 24 ms / 0.03 s / 136 MB | 15 ms / 0.01 s / 122 MB | 8 ms / 0.02 s / 174 MB | – | – | – |
| read + pass | ours | 6 ms / 0.01 s / 118 MB | 23 ms / 0.03 s / 135 MB | 24 ms / 0.03 s / 135 MB | 14 ms / 0.01 s / 122 MB | 8 ms / 0.02 s / 174 MB | – | – | – |
| write, defaults | dta | 7 ms / 0.01 s / 119 MB | 16 ms / 0.02 s / 125 MB | – | 27 ms / 0.03 s / 125 MB | 9 ms / 0.02 s / 181 MB | – | – | – |
| write, zstd 3 | dta | 8 ms / 0.01 s / 119 MB | 17 ms / 0.02 s / 125 MB | – | 31 ms / 0.03 s / 126 MB | 9 ms / 0.03 s / 181 MB | – | – | – |

### 2022_2023_FemResp

5,586 rows, 1,912 columns; .dta 13.3 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 17 ms / 0.03 s / 199 MB | 53 ms / 0.17 s / 298 MB | 54 ms / 0.17 s / 299 MB | 148 ms / 0.15 s / 189 MB | 33 ms / 0.09 s / 309 MB | 40 ms / 0.11 s / 216 MB | 18 ms / 0.02 s / 221 MB | 81 ms / 0.08 s / 340 MB |
| whole file | polars | 18 ms / 0.03 s / 199 MB | 53 ms / 0.18 s / 298 MB | 54 ms / 0.18 s / 300 MB | 156 ms / 0.16 s / 188 MB | 38 ms / 0.09 s / 308 MB | – | – | – |
| whole file | ours | 18 ms / 0.03 s / 201 MB | 55 ms / 0.17 s / 300 MB | 53 ms / 0.17 s / 299 MB | 145 ms / 0.14 s / 188 MB | 34 ms / 0.09 s / 309 MB | – | – | – |
| five columns | pyarrow | 2 ms / 0.00 s / 112 MB | 23 ms / 0.02 s / 126 MB | 23 ms / 0.02 s / 126 MB | 19 ms / 0.02 s / 124 MB | 4 ms / 0.01 s / 168 MB | 22 ms / 0.02 s / 125 MB | 4 ms / 0.01 s / 167 MB | 6 ms / 0.01 s / 146 MB |
| five columns | polars | 2 ms / 0.00 s / 112 MB | 23 ms / 0.02 s / 127 MB | 23 ms / 0.02 s / 126 MB | 18 ms / 0.02 s / 122 MB | 4 ms / 0.01 s / 169 MB | – | – | – |
| five columns | ours | 2 ms / 0.00 s / 112 MB | 23 ms / 0.02 s / 127 MB | 23 ms / 0.02 s / 128 MB | 17 ms / 0.02 s / 123 MB | 4 ms / 0.01 s / 170 MB | – | – | – |
| 1,000 rows | pyarrow | 13 ms / 0.01 s / 130 MB | 55 ms / 0.16 s / 232 MB | 54 ms / 0.17 s / 299 MB | 149 ms / 0.15 s / 189 MB | 28 ms / 0.06 s / 201 MB | 41 ms / 0.11 s / 217 MB | 11 ms / 0.02 s / 181 MB | 87 ms / 0.32 s / 724 MB |
| 1,000 rows | polars | 16 ms / 0.02 s / 129 MB | 54 ms / 0.17 s / 232 MB | 54 ms / 0.18 s / 298 MB | 154 ms / 0.15 s / 188 MB | 30 ms / 0.07 s / 201 MB | – | – | – |
| 1,000 rows | ours | 14 ms / 0.01 s / 133 MB | 54 ms / 0.15 s / 232 MB | 52 ms / 0.17 s / 299 MB | 147 ms / 0.15 s / 189 MB | 27 ms / 0.07 s / 201 MB | – | – | – |
| read + pass | pyarrow | 59 ms / 0.07 s / 200 MB | 91 ms / 0.21 s / 300 MB | 92 ms / 0.21 s / 300 MB | 205 ms / 0.20 s / 189 MB | 73 ms / 0.13 s / 310 MB | – | – | – |
| read + pass | polars | 60 ms / 0.07 s / 200 MB | 91 ms / 0.22 s / 299 MB | 91 ms / 0.22 s / 299 MB | 211 ms / 0.21 s / 187 MB | 75 ms / 0.13 s / 309 MB | – | – | – |
| read + pass | ours | 60 ms / 0.07 s / 203 MB | 90 ms / 0.21 s / 299 MB | 91 ms / 0.21 s / 300 MB | 203 ms / 0.20 s / 187 MB | 71 ms / 0.12 s / 310 MB | – | – | – |
| write, defaults | dta | 39 ms / 0.07 s / 193 MB | 170 ms / 0.17 s / 211 MB | – | 450 ms / 0.45 s / 204 MB | 78 ms / 0.23 s / 295 MB | – | – | – |
| write, zstd 3 | dta | 45 ms / 0.08 s / 195 MB | 183 ms / 0.18 s / 210 MB | – | 475 ms / 0.48 s / 203 MB | 79 ms / 0.23 s / 295 MB | – | – | – |

### 2022_2023_MaleResp

4,371 rows, 1,157 columns; .dta 6.3 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 8 ms / 0.01 s / 154 MB | 39 ms / 0.10 s / 205 MB | 39 ms / 0.10 s / 205 MB | 82 ms / 0.08 s / 154 MB | 19 ms / 0.05 s / 235 MB | 30 ms / 0.07 s / 166 MB | 10 ms / 0.01 s / 193 MB | 40 ms / 0.04 s / 260 MB |
| whole file | polars | 9 ms / 0.02 s / 153 MB | 38 ms / 0.11 s / 205 MB | 38 ms / 0.11 s / 205 MB | 83 ms / 0.08 s / 153 MB | 21 ms / 0.05 s / 235 MB | – | – | – |
| whole file | ours | 9 ms / 0.01 s / 155 MB | 38 ms / 0.10 s / 205 MB | 39 ms / 0.10 s / 205 MB | 81 ms / 0.08 s / 153 MB | 19 ms / 0.05 s / 234 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 111 MB | 20 ms / 0.02 s / 125 MB | 21 ms / 0.02 s / 124 MB | 12 ms / 0.01 s / 121 MB | 4 ms / 0.01 s / 167 MB | 21 ms / 0.02 s / 124 MB | 3 ms / 0.01 s / 165 MB | 4 ms / 0.00 s / 144 MB |
| five columns | polars | 1 ms / 0.00 s / 112 MB | 21 ms / 0.02 s / 124 MB | 21 ms / 0.02 s / 124 MB | 11 ms / 0.01 s / 121 MB | 3 ms / 0.01 s / 166 MB | – | – | – |
| five columns | ours | 1 ms / 0.00 s / 111 MB | 21 ms / 0.02 s / 124 MB | 21 ms / 0.02 s / 125 MB | 11 ms / 0.01 s / 120 MB | 4 ms / 0.01 s / 167 MB | – | – | – |
| 1,000 rows | pyarrow | 7 ms / 0.01 s / 121 MB | 40 ms / 0.09 s / 176 MB | 40 ms / 0.10 s / 205 MB | 84 ms / 0.08 s / 153 MB | 16 ms / 0.03 s / 185 MB | 32 ms / 0.08 s / 166 MB | 7 ms / 0.01 s / 172 MB | 53 ms / 0.20 s / 509 MB |
| 1,000 rows | polars | 9 ms / 0.01 s / 122 MB | 39 ms / 0.10 s / 176 MB | 39 ms / 0.11 s / 204 MB | 86 ms / 0.09 s / 153 MB | 19 ms / 0.04 s / 186 MB | – | – | – |
| 1,000 rows | ours | 7 ms / 0.01 s / 123 MB | 41 ms / 0.09 s / 177 MB | 39 ms / 0.10 s / 204 MB | 81 ms / 0.08 s / 153 MB | 17 ms / 0.04 s / 186 MB | – | – | – |
| read + pass | pyarrow | 31 ms / 0.04 s / 155 MB | 58 ms / 0.12 s / 205 MB | 60 ms / 0.13 s / 205 MB | 114 ms / 0.11 s / 153 MB | 40 ms / 0.07 s / 236 MB | – | – | – |
| read + pass | polars | 33 ms / 0.04 s / 154 MB | 59 ms / 0.13 s / 206 MB | 58 ms / 0.13 s / 205 MB | 114 ms / 0.11 s / 154 MB | 43 ms / 0.07 s / 236 MB | – | – | – |
| read + pass | ours | 33 ms / 0.04 s / 156 MB | 58 ms / 0.12 s / 205 MB | 61 ms / 0.12 s / 207 MB | 111 ms / 0.11 s / 154 MB | 41 ms / 0.07 s / 236 MB | – | – | – |
| write, defaults | dta | 19 ms / 0.03 s / 154 MB | 86 ms / 0.09 s / 165 MB | – | 264 ms / 0.26 s / 162 MB | 43 ms / 0.12 s / 235 MB | – | – | – |
| write, zstd 3 | dta | 21 ms / 0.04 s / 154 MB | 93 ms / 0.09 s / 167 MB | – | 276 ms / 0.28 s / 162 MB | 43 ms / 0.12 s / 233 MB | – | – | – |

### Senegal 2019 wm

8,649 rows, 4,997 columns; .dta 49.1 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 41 ms / 0.07 s / 467 MB | 114 ms / 0.47 s / 751 MB | 114 ms / 0.48 s / 748 MB | 394 ms / 0.39 s / 291 MB | 68 ms / 0.27 s / 750 MB | 76 ms / 0.26 s / 410 MB | 21 ms / 0.05 s / 400 MB | 296 ms / 0.30 s / 939 MB |
| whole file | polars | 45 ms / 0.08 s / 466 MB | 113 ms / 0.49 s / 747 MB | 111 ms / 0.51 s / 749 MB | 404 ms / 0.40 s / 288 MB | 69 ms / 0.29 s / 749 MB | – | – | – |
| whole file | ours | 50 ms / 0.08 s / 477 MB | 111 ms / 0.47 s / 752 MB | 111 ms / 0.46 s / 752 MB | 370 ms / 0.37 s / 287 MB | 67 ms / 0.28 s / 753 MB | – | – | – |
| five columns | pyarrow | 3 ms / 0.00 s / 115 MB | 29 ms / 0.03 s / 138 MB | 30 ms / 0.03 s / 139 MB | 49 ms / 0.05 s / 136 MB | 7 ms / 0.01 s / 177 MB | 30 ms / 0.03 s / 137 MB | 6 ms / 0.01 s / 175 MB | 13 ms / 0.01 s / 154 MB |
| five columns | polars | 3 ms / 0.00 s / 115 MB | 29 ms / 0.03 s / 137 MB | 29 ms / 0.03 s / 137 MB | 46 ms / 0.05 s / 132 MB | 7 ms / 0.01 s / 177 MB | – | – | – |
| five columns | ours | 4 ms / 0.00 s / 117 MB | 30 ms / 0.03 s / 141 MB | 31 ms / 0.03 s / 142 MB | 44 ms / 0.04 s / 131 MB | 7 ms / 0.01 s / 180 MB | – | – | – |
| 1,000 rows | pyarrow | 21 ms / 0.03 s / 167 MB | 110 ms / 0.37 s / 452 MB | 112 ms / 0.47 s / 750 MB | 406 ms / 0.41 s / 291 MB | 53 ms / 0.15 s / 259 MB | 77 ms / 0.27 s / 411 MB | 13 ms / 0.03 s / 210 MB | 265 ms / 0.97 s / 1706 MB |
| 1,000 rows | polars | 22 ms / 0.03 s / 167 MB | 109 ms / 0.39 s / 451 MB | 112 ms / 0.48 s / 747 MB | 409 ms / 0.41 s / 289 MB | 54 ms / 0.15 s / 259 MB | – | – | – |
| 1,000 rows | ours | 27 ms / 0.03 s / 179 MB | 107 ms / 0.36 s / 452 MB | 112 ms / 0.46 s / 752 MB | 375 ms / 0.38 s / 288 MB | 53 ms / 0.15 s / 262 MB | – | – | – |
| read + pass | pyarrow | 140 ms / 0.17 s / 467 MB | 205 ms / 0.57 s / 749 MB | 203 ms / 0.56 s / 750 MB | 551 ms / 0.55 s / 434 MB | 158 ms / 0.38 s / 751 MB | – | – | – |
| read + pass | polars | 145 ms / 0.18 s / 467 MB | 203 ms / 0.58 s / 749 MB | 203 ms / 0.57 s / 749 MB | 561 ms / 0.56 s / 435 MB | 156 ms / 0.38 s / 750 MB | – | – | – |
| read + pass | ours | 148 ms / 0.18 s / 479 MB | 202 ms / 0.55 s / 751 MB | 200 ms / 0.54 s / 752 MB | 534 ms / 0.53 s / 434 MB | 157 ms / 0.36 s / 755 MB | – | – | – |
| write, defaults | dta | 105 ms / 0.18 s / 507 MB | 425 ms / 0.42 s / 538 MB | – | 1.08 s / 1.08 s / 512 MB | 194 ms / 0.40 s / 644 MB | – | – | – |
| write, zstd 3 | dta | 120 ms / 0.22 s / 508 MB | 441 ms / 0.44 s / 539 MB | – | 1.12 s / 1.12 s / 511 MB | 192 ms / 0.40 s / 644 MB | – | – | – |

### Senegal 2019 bh

21,562 rows, 1,191 columns; .dta 28.9 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 25 ms / 0.05 s / 304 MB | 51 ms / 0.25 s / 457 MB | 52 ms / 0.24 s / 457 MB | 138 ms / 0.14 s / 227 MB | 39 ms / 0.16 s / 491 MB | 37 ms / 0.12 s / 267 MB | 20 ms / 0.03 s / 298 MB | 106 ms / 0.11 s / 423 MB |
| whole file | polars | 27 ms / 0.05 s / 304 MB | 52 ms / 0.24 s / 455 MB | 53 ms / 0.24 s / 456 MB | 120 ms / 0.12 s / 227 MB | 41 ms / 0.18 s / 490 MB | – | – | – |
| whole file | ours | 27 ms / 0.05 s / 307 MB | 51 ms / 0.24 s / 457 MB | 52 ms / 0.26 s / 457 MB | 110 ms / 0.11 s / 226 MB | 38 ms / 0.16 s / 491 MB | – | – | – |
| five columns | pyarrow | 2 ms / 0.00 s / 112 MB | 21 ms / 0.02 s / 127 MB | 21 ms / 0.02 s / 128 MB | 13 ms / 0.01 s / 122 MB | 4 ms / 0.01 s / 169 MB | 20 ms / 0.02 s / 126 MB | 3 ms / 0.01 s / 167 MB | 4 ms / 0.00 s / 145 MB |
| five columns | polars | 1 ms / 0.00 s / 112 MB | 21 ms / 0.02 s / 127 MB | 21 ms / 0.02 s / 127 MB | 12 ms / 0.01 s / 122 MB | 4 ms / 0.01 s / 170 MB | – | – | – |
| five columns | ours | 2 ms / 0.00 s / 112 MB | 21 ms / 0.02 s / 129 MB | 22 ms / 0.02 s / 128 MB | 12 ms / 0.01 s / 120 MB | 4 ms / 0.01 s / 169 MB | – | – | – |
| 1,000 rows | pyarrow | 12 ms / 0.01 s / 122 MB | 43 ms / 0.14 s / 277 MB | 53 ms / 0.24 s / 458 MB | 139 ms / 0.14 s / 227 MB | 19 ms / 0.05 s / 190 MB | 36 ms / 0.12 s / 268 MB | 9 ms / 0.02 s / 176 MB | 55 ms / 0.21 s / 508 MB |
| 1,000 rows | polars | 15 ms / 0.01 s / 122 MB | 44 ms / 0.15 s / 277 MB | 52 ms / 0.24 s / 455 MB | 118 ms / 0.12 s / 227 MB | 21 ms / 0.05 s / 189 MB | – | – | – |
| 1,000 rows | ours | 14 ms / 0.01 s / 126 MB | 43 ms / 0.14 s / 278 MB | 51 ms / 0.23 s / 457 MB | 114 ms / 0.11 s / 226 MB | 19 ms / 0.05 s / 190 MB | – | – | – |
| read + pass | pyarrow | 67 ms / 0.09 s / 306 MB | 92 ms / 0.29 s / 457 MB | 92 ms / 0.28 s / 457 MB | 207 ms / 0.21 s / 264 MB | 79 ms / 0.20 s / 492 MB | – | – | – |
| read + pass | polars | 68 ms / 0.09 s / 306 MB | 93 ms / 0.29 s / 456 MB | 92 ms / 0.30 s / 456 MB | 184 ms / 0.18 s / 264 MB | 80 ms / 0.20 s / 491 MB | – | – | – |
| read + pass | ours | 69 ms / 0.09 s / 309 MB | 91 ms / 0.28 s / 459 MB | 91 ms / 0.28 s / 459 MB | 179 ms / 0.18 s / 263 MB | 78 ms / 0.21 s / 492 MB | – | – | – |
| write, defaults | dta | 63 ms / 0.12 s / 295 MB | 239 ms / 0.24 s / 310 MB | – | 323 ms / 0.32 s / 301 MB | 84 ms / 0.24 s / 392 MB | – | – | – |
| write, zstd 3 | dta | 69 ms / 0.13 s / 296 MB | 255 ms / 0.25 s / 311 MB | – | 358 ms / 0.36 s / 304 MB | 84 ms / 0.24 s / 393 MB | – | – | – |

### Turkey 2013 wm

9,746 rows, 4,668 columns; .dta 52.6 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 44 ms / 0.08 s / 487 MB | 111 ms / 0.47 s / 754 MB | 110 ms / 0.48 s / 755 MB | 362 ms / 0.36 s / 280 MB | 65 ms / 0.30 s / 759 MB | 71 ms / 0.24 s / 396 MB | 18 ms / 0.04 s / 388 MB | 280 ms / 0.28 s / 884 MB |
| whole file | polars | 46 ms / 0.08 s / 487 MB | 109 ms / 0.48 s / 752 MB | 110 ms / 0.48 s / 754 MB | 370 ms / 0.37 s / 278 MB | 64 ms / 0.31 s / 758 MB | – | – | – |
| whole file | ours | 51 ms / 0.08 s / 498 MB | 109 ms / 0.47 s / 757 MB | 108 ms / 0.47 s / 757 MB | 346 ms / 0.35 s / 276 MB | 65 ms / 0.31 s / 760 MB | – | – | – |
| five columns | pyarrow | 3 ms / 0.00 s / 115 MB | 29 ms / 0.03 s / 138 MB | 29 ms / 0.03 s / 138 MB | 46 ms / 0.05 s / 135 MB | 6 ms / 0.01 s / 177 MB | 29 ms / 0.03 s / 137 MB | 6 ms / 0.01 s / 175 MB | 12 ms / 0.01 s / 154 MB |
| five columns | polars | 3 ms / 0.00 s / 114 MB | 28 ms / 0.03 s / 136 MB | 28 ms / 0.03 s / 136 MB | 42 ms / 0.04 s / 131 MB | 6 ms / 0.01 s / 177 MB | – | – | – |
| five columns | ours | 4 ms / 0.00 s / 116 MB | 30 ms / 0.03 s / 141 MB | 29 ms / 0.03 s / 141 MB | 41 ms / 0.04 s / 131 MB | 7 ms / 0.01 s / 179 MB | – | – | – |
| 1,000 rows | pyarrow | 20 ms / 0.03 s / 165 MB | 103 ms / 0.36 s / 434 MB | 111 ms / 0.48 s / 756 MB | 374 ms / 0.37 s / 280 MB | 50 ms / 0.14 s / 255 MB | 73 ms / 0.25 s / 397 MB | 11 ms / 0.02 s / 208 MB | 237 ms / 0.88 s / 1605 MB |
| 1,000 rows | polars | 21 ms / 0.03 s / 164 MB | 101 ms / 0.36 s / 433 MB | 110 ms / 0.49 s / 755 MB | 378 ms / 0.38 s / 277 MB | 52 ms / 0.14 s / 254 MB | – | – | – |
| 1,000 rows | ours | 26 ms / 0.03 s / 176 MB | 99 ms / 0.34 s / 437 MB | 107 ms / 0.47 s / 757 MB | 348 ms / 0.35 s / 277 MB | 50 ms / 0.14 s / 257 MB | – | – | – |
| read + pass | pyarrow | 138 ms / 0.17 s / 488 MB | 197 ms / 0.57 s / 756 MB | 196 ms / 0.56 s / 758 MB | 518 ms / 0.52 s / 417 MB | 151 ms / 0.39 s / 759 MB | – | – | – |
| read + pass | polars | 138 ms / 0.17 s / 488 MB | 195 ms / 0.58 s / 754 MB | 197 ms / 0.57 s / 755 MB | 522 ms / 0.52 s / 418 MB | 148 ms / 0.40 s / 759 MB | – | – | – |
| read + pass | ours | 143 ms / 0.18 s / 500 MB | 194 ms / 0.56 s / 757 MB | 192 ms / 0.55 s / 758 MB | 499 ms / 0.50 s / 416 MB | 150 ms / 0.39 s / 761 MB | – | – | – |
| write, defaults | dta | 106 ms / 0.19 s / 490 MB | 430 ms / 0.43 s / 521 MB | – | 1.02 s / 1.02 s / 491 MB | 190 ms / 0.41 s / 628 MB | – | – | – |
| write, zstd 3 | dta | 113 ms / 0.20 s / 494 MB | 468 ms / 0.47 s / 520 MB | – | 1.09 s / 1.09 s / 494 MB | 192 ms / 0.41 s / 630 MB | – | – | – |

### Turkey 2013 bh

17,871 rows, 1,173 columns; .dta 23.3 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 20 ms / 0.04 s / 274 MB | 49 ms / 0.20 s / 405 MB | 48 ms / 0.20 s / 405 MB | 102 ms / 0.10 s / 199 MB | 33 ms / 0.15 s / 440 MB | 34 ms / 0.10 s / 246 MB | 16 ms / 0.03 s / 277 MB | 87 ms / 0.09 s / 404 MB |
| whole file | polars | 22 ms / 0.04 s / 274 MB | 47 ms / 0.21 s / 404 MB | 48 ms / 0.22 s / 404 MB | 108 ms / 0.11 s / 199 MB | 35 ms / 0.16 s / 440 MB | – | – | – |
| whole file | ours | 22 ms / 0.04 s / 277 MB | 48 ms / 0.21 s / 405 MB | 48 ms / 0.20 s / 406 MB | 98 ms / 0.10 s / 198 MB | 33 ms / 0.15 s / 441 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 112 MB | 21 ms / 0.02 s / 127 MB | 20 ms / 0.02 s / 127 MB | 12 ms / 0.01 s / 120 MB | 4 ms / 0.01 s / 169 MB | 20 ms / 0.02 s / 125 MB | 3 ms / 0.01 s / 166 MB | 4 ms / 0.00 s / 144 MB |
| five columns | polars | 1 ms / 0.00 s / 112 MB | 20 ms / 0.02 s / 126 MB | 21 ms / 0.02 s / 127 MB | 12 ms / 0.01 s / 122 MB | 4 ms / 0.01 s / 169 MB | – | – | – |
| five columns | ours | 2 ms / 0.00 s / 113 MB | 21 ms / 0.02 s / 128 MB | 21 ms / 0.02 s / 127 MB | 11 ms / 0.01 s / 120 MB | 4 ms / 0.01 s / 169 MB | – | – | – |
| 1,000 rows | pyarrow | 10 ms / 0.01 s / 123 MB | 42 ms / 0.13 s / 256 MB | 49 ms / 0.22 s / 405 MB | 104 ms / 0.10 s / 199 MB | 18 ms / 0.05 s / 188 MB | 35 ms / 0.10 s / 246 MB | 8 ms / 0.01 s / 176 MB | 52 ms / 0.24 s / 514 MB |
| 1,000 rows | polars | 13 ms / 0.01 s / 123 MB | 41 ms / 0.13 s / 255 MB | 49 ms / 0.21 s / 404 MB | 109 ms / 0.11 s / 199 MB | 20 ms / 0.05 s / 188 MB | – | – | – |
| 1,000 rows | ours | 12 ms / 0.01 s / 126 MB | 42 ms / 0.13 s / 255 MB | 48 ms / 0.21 s / 406 MB | 102 ms / 0.10 s / 198 MB | 18 ms / 0.04 s / 188 MB | – | – | – |
| read + pass | pyarrow | 55 ms / 0.07 s / 276 MB | 81 ms / 0.24 s / 407 MB | 81 ms / 0.24 s / 406 MB | 156 ms / 0.16 s / 240 MB | 66 ms / 0.18 s / 441 MB | – | – | – |
| read + pass | polars | 56 ms / 0.07 s / 276 MB | 80 ms / 0.24 s / 405 MB | 81 ms / 0.25 s / 406 MB | 162 ms / 0.16 s / 241 MB | 68 ms / 0.17 s / 441 MB | – | – | – |
| read + pass | ours | 57 ms / 0.07 s / 278 MB | 81 ms / 0.24 s / 407 MB | 81 ms / 0.25 s / 406 MB | 154 ms / 0.15 s / 240 MB | 65 ms / 0.16 s / 442 MB | – | – | – |
| write, defaults | dta | 53 ms / 0.10 s / 270 MB | 206 ms / 0.21 s / 285 MB | – | 297 ms / 0.30 s / 276 MB | 74 ms / 0.19 s / 366 MB | – | – | – |
| write, zstd 3 | dta | 58 ms / 0.11 s / 271 MB | 217 ms / 0.22 s / 283 MB | – | 328 ms / 0.32 s / 279 MB | 73 ms / 0.19 s / 367 MB | – | – | – |

### Tajikistan 2017 wm

10,718 rows, 5,160 columns; .dta 63.8 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 54 ms / 0.09 s / 557 MB | 124 ms / 0.55 s / 895 MB | 124 ms / 0.57 s / 896 MB | 425 ms / 0.42 s / 321 MB | 76 ms / 0.36 s / 899 MB | 79 ms / 0.28 s / 464 MB | 21 ms / 0.05 s / 456 MB | 337 ms / 0.34 s / 966 MB |
| whole file | polars | 56 ms / 0.10 s / 557 MB | 125 ms / 0.59 s / 895 MB | 123 ms / 0.57 s / 895 MB | 436 ms / 0.44 s / 318 MB | 75 ms / 0.36 s / 898 MB | – | – | – |
| whole file | ours | 61 ms / 0.10 s / 571 MB | 121 ms / 0.56 s / 896 MB | 122 ms / 0.55 s / 897 MB | 400 ms / 0.40 s / 317 MB | 77 ms / 0.35 s / 901 MB | – | – | – |
| five columns | pyarrow | 3 ms / 0.00 s / 115 MB | 30 ms / 0.03 s / 139 MB | 30 ms / 0.03 s / 139 MB | 51 ms / 0.05 s / 137 MB | 7 ms / 0.01 s / 178 MB | 30 ms / 0.03 s / 138 MB | 6 ms / 0.01 s / 176 MB | 13 ms / 0.01 s / 157 MB |
| five columns | polars | 3 ms / 0.00 s / 115 MB | 29 ms / 0.03 s / 138 MB | 30 ms / 0.03 s / 138 MB | 47 ms / 0.05 s / 133 MB | 7 ms / 0.01 s / 178 MB | – | – | – |
| five columns | ours | 5 ms / 0.00 s / 117 MB | 31 ms / 0.03 s / 144 MB | 31 ms / 0.03 s / 143 MB | 46 ms / 0.05 s / 134 MB | 7 ms / 0.01 s / 182 MB | – | – | – |
| 1,000 rows | pyarrow | 23 ms / 0.03 s / 167 MB | 114 ms / 0.40 s / 507 MB | 126 ms / 0.57 s / 895 MB | 433 ms / 0.43 s / 321 MB | 55 ms / 0.15 s / 265 MB | 80 ms / 0.28 s / 463 MB | 13 ms / 0.03 s / 214 MB | 286 ms / 0.99 s / 1761 MB |
| 1,000 rows | polars | 25 ms / 0.04 s / 167 MB | 114 ms / 0.41 s / 505 MB | 123 ms / 0.57 s / 894 MB | 440 ms / 0.44 s / 318 MB | 54 ms / 0.15 s / 265 MB | – | – | – |
| 1,000 rows | ours | 29 ms / 0.04 s / 180 MB | 109 ms / 0.38 s / 510 MB | 122 ms / 0.54 s / 898 MB | 404 ms / 0.40 s / 318 MB | 53 ms / 0.15 s / 267 MB | – | – | – |
| read + pass | pyarrow | 164 ms / 0.20 s / 560 MB | 228 ms / 0.67 s / 895 MB | 227 ms / 0.65 s / 895 MB | 609 ms / 0.61 s / 457 MB | 177 ms / 0.47 s / 899 MB | – | – | – |
| read + pass | polars | 160 ms / 0.20 s / 559 MB | 225 ms / 0.68 s / 893 MB | 226 ms / 0.67 s / 893 MB | 613 ms / 0.61 s / 457 MB | 178 ms / 0.47 s / 899 MB | – | – | – |
| read + pass | ours | 171 ms / 0.21 s / 572 MB | 225 ms / 0.65 s / 897 MB | 224 ms / 0.65 s / 897 MB | 585 ms / 0.58 s / 457 MB | 178 ms / 0.49 s / 902 MB | – | – | – |
| write, defaults | dta | 129 ms / 0.23 s / 541 MB | 512 ms / 0.51 s / 579 MB | – | 1.15 s / 1.15 s / 545 MB | 220 ms / 0.49 s / 688 MB | – | – | – |
| write, zstd 3 | dta | 138 ms / 0.25 s / 545 MB | 533 ms / 0.53 s / 577 MB | – | 1.23 s / 1.23 s / 547 MB | 222 ms / 0.49 s / 688 MB | – | – | – |

### Tajikistan 2017 bh

21,985 rows, 1,146 columns; .dta 29.4 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 25 ms / 0.05 s / 295 MB | 50 ms / 0.23 s / 443 MB | 51 ms / 0.23 s / 443 MB | 134 ms / 0.13 s / 225 MB | 37 ms / 0.16 s / 478 MB | 35 ms / 0.12 s / 264 MB | 19 ms / 0.03 s / 295 MB | 103 ms / 0.10 s / 413 MB |
| whole file | polars | 26 ms / 0.05 s / 295 MB | 51 ms / 0.23 s / 442 MB | 50 ms / 0.24 s / 441 MB | 117 ms / 0.12 s / 223 MB | 39 ms / 0.18 s / 478 MB | – | – | – |
| whole file | ours | 25 ms / 0.04 s / 298 MB | 50 ms / 0.23 s / 443 MB | 50 ms / 0.23 s / 443 MB | 110 ms / 0.11 s / 223 MB | 37 ms / 0.17 s / 479 MB | – | – | – |
| five columns | pyarrow | 2 ms / 0.00 s / 113 MB | 21 ms / 0.02 s / 127 MB | 21 ms / 0.02 s / 127 MB | 12 ms / 0.01 s / 122 MB | 4 ms / 0.01 s / 169 MB | 20 ms / 0.02 s / 126 MB | 3 ms / 0.01 s / 166 MB | 4 ms / 0.00 s / 145 MB |
| five columns | polars | 1 ms / 0.00 s / 113 MB | 20 ms / 0.02 s / 127 MB | 20 ms / 0.02 s / 126 MB | 11 ms / 0.01 s / 122 MB | 4 ms / 0.01 s / 169 MB | – | – | – |
| five columns | ours | 2 ms / 0.00 s / 113 MB | 21 ms / 0.02 s / 129 MB | 21 ms / 0.02 s / 128 MB | 11 ms / 0.01 s / 120 MB | 4 ms / 0.01 s / 170 MB | – | – | – |
| 1,000 rows | pyarrow | 13 ms / 0.01 s / 122 MB | 43 ms / 0.14 s / 273 MB | 51 ms / 0.23 s / 442 MB | 136 ms / 0.14 s / 224 MB | 19 ms / 0.05 s / 189 MB | 35 ms / 0.12 s / 263 MB | 8 ms / 0.02 s / 177 MB | 54 ms / 0.22 s / 507 MB |
| 1,000 rows | polars | 16 ms / 0.02 s / 122 MB | 42 ms / 0.14 s / 272 MB | 50 ms / 0.24 s / 440 MB | 119 ms / 0.12 s / 224 MB | 21 ms / 0.05 s / 188 MB | – | – | – |
| 1,000 rows | ours | 14 ms / 0.01 s / 125 MB | 42 ms / 0.14 s / 274 MB | 50 ms / 0.23 s / 444 MB | 110 ms / 0.11 s / 223 MB | 19 ms / 0.05 s / 190 MB | – | – | – |
| read + pass | pyarrow | 67 ms / 0.09 s / 296 MB | 91 ms / 0.27 s / 444 MB | 91 ms / 0.29 s / 444 MB | 196 ms / 0.20 s / 256 MB | 77 ms / 0.21 s / 480 MB | – | – | – |
| read + pass | polars | 68 ms / 0.09 s / 296 MB | 91 ms / 0.27 s / 442 MB | 90 ms / 0.29 s / 443 MB | 182 ms / 0.18 s / 256 MB | 79 ms / 0.21 s / 478 MB | – | – | – |
| read + pass | ours | 69 ms / 0.09 s / 299 MB | 89 ms / 0.27 s / 445 MB | 90 ms / 0.27 s / 444 MB | 175 ms / 0.17 s / 256 MB | 77 ms / 0.21 s / 480 MB | – | – | – |
| write, defaults | dta | 64 ms / 0.12 s / 282 MB | 242 ms / 0.24 s / 295 MB | – | 307 ms / 0.31 s / 289 MB | 82 ms / 0.24 s / 380 MB | – | – | – |
| write, zstd 3 | dta | 70 ms / 0.13 s / 283 MB | 259 ms / 0.26 s / 295 MB | – | 347 ms / 0.35 s / 290 MB | 83 ms / 0.24 s / 380 MB | – | – | – |

### Myanmar 2016 wm

12,885 rows, 4,993 columns; .dta 72.0 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 58 ms / 0.10 s / 631 MB | 129 ms / 0.63 s / 1039 MB | 126 ms / 0.62 s / 1037 MB | 417 ms / 0.42 s / 335 MB | 77 ms / 0.43 s / 1003 MB | 79 ms / 0.29 s / 534 MB | 20 ms / 0.06 s / 487 MB | 355 ms / 0.36 s / 1022 MB |
| whole file | polars | 59 ms / 0.11 s / 632 MB | 125 ms / 0.64 s / 1037 MB | 125 ms / 0.65 s / 1038 MB | 414 ms / 0.41 s / 333 MB | 78 ms / 0.42 s / 1002 MB | – | – | – |
| whole file | ours | 64 ms / 0.11 s / 643 MB | 126 ms / 0.59 s / 1041 MB | 125 ms / 0.62 s / 1041 MB | 390 ms / 0.39 s / 332 MB | 75 ms / 0.45 s / 1006 MB | – | – | – |
| five columns | pyarrow | 3 ms / 0.00 s / 116 MB | 30 ms / 0.03 s / 139 MB | 30 ms / 0.03 s / 139 MB | 49 ms / 0.05 s / 136 MB | 7 ms / 0.01 s / 178 MB | 30 ms / 0.03 s / 138 MB | 6 ms / 0.01 s / 176 MB | 13 ms / 0.01 s / 155 MB |
| five columns | polars | 3 ms / 0.00 s / 115 MB | 29 ms / 0.03 s / 137 MB | 29 ms / 0.03 s / 137 MB | 45 ms / 0.05 s / 133 MB | 7 ms / 0.01 s / 178 MB | – | – | – |
| five columns | ours | 5 ms / 0.00 s / 117 MB | 30 ms / 0.03 s / 143 MB | 30 ms / 0.03 s / 143 MB | 45 ms / 0.04 s / 133 MB | 7 ms / 0.01 s / 182 MB | – | – | – |
| 1,000 rows | pyarrow | 23 ms / 0.03 s / 168 MB | 114 ms / 0.41 s / 573 MB | 128 ms / 0.65 s / 1039 MB | 420 ms / 0.42 s / 335 MB | 53 ms / 0.15 s / 261 MB | 80 ms / 0.30 s / 537 MB | 12 ms / 0.03 s / 211 MB | 271 ms / 0.97 s / 1707 MB |
| 1,000 rows | polars | 24 ms / 0.04 s / 167 MB | 112 ms / 0.41 s / 575 MB | 127 ms / 0.62 s / 1036 MB | 426 ms / 0.43 s / 332 MB | 52 ms / 0.15 s / 261 MB | – | – | – |
| 1,000 rows | ours | 28 ms / 0.04 s / 180 MB | 111 ms / 0.39 s / 576 MB | 124 ms / 0.61 s / 1040 MB | 397 ms / 0.40 s / 332 MB | 49 ms / 0.14 s / 265 MB | – | – | – |
| read + pass | pyarrow | 168 ms / 0.21 s / 633 MB | 229 ms / 0.73 s / 1038 MB | 230 ms / 0.73 s / 1039 MB | 598 ms / 0.60 s / 534 MB | 177 ms / 0.54 s / 1003 MB | – | – | – |
| read + pass | polars | 169 ms / 0.22 s / 633 MB | 229 ms / 0.74 s / 1037 MB | 227 ms / 0.80 s / 1038 MB | 603 ms / 0.60 s / 536 MB | 178 ms / 0.53 s / 1003 MB | – | – | – |
| read + pass | ours | 174 ms / 0.22 s / 644 MB | 226 ms / 0.73 s / 1043 MB | 227 ms / 0.73 s / 1041 MB | 577 ms / 0.58 s / 534 MB | 176 ms / 0.58 s / 1007 MB | – | – | – |
| write, defaults | dta | 140 ms / 0.25 s / 624 MB | 545 ms / 0.54 s / 658 MB | – | 1.14 s / 1.14 s / 627 MB | 231 ms / 0.49 s / 773 MB | – | – | – |
| write, zstd 3 | dta | 148 ms / 0.27 s / 626 MB | 564 ms / 0.56 s / 657 MB | – | 1.20 s / 1.20 s / 627 MB | 230 ms / 0.49 s / 770 MB | – | – | – |

### Myanmar 2016 bh

22,989 rows, 1,184 columns; .dta 30.7 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 26 ms / 0.05 s / 314 MB | 51 ms / 0.25 s / 466 MB | 52 ms / 0.26 s / 466 MB | 138 ms / 0.14 s / 226 MB | 39 ms / 0.19 s / 506 MB | 36 ms / 0.11 s / 267 MB | 20 ms / 0.03 s / 304 MB | 108 ms / 0.11 s / 421 MB |
| whole file | polars | 27 ms / 0.05 s / 314 MB | 51 ms / 0.25 s / 464 MB | 52 ms / 0.26 s / 463 MB | 118 ms / 0.12 s / 225 MB | 41 ms / 0.18 s / 505 MB | – | – | – |
| whole file | ours | 27 ms / 0.05 s / 317 MB | 51 ms / 0.26 s / 466 MB | 52 ms / 0.23 s / 466 MB | 110 ms / 0.11 s / 225 MB | 39 ms / 0.18 s / 507 MB | – | – | – |
| five columns | pyarrow | 2 ms / 0.00 s / 112 MB | 20 ms / 0.02 s / 128 MB | 21 ms / 0.02 s / 128 MB | 12 ms / 0.01 s / 122 MB | 4 ms / 0.01 s / 169 MB | 20 ms / 0.02 s / 125 MB | 3 ms / 0.01 s / 167 MB | 4 ms / 0.00 s / 145 MB |
| five columns | polars | 2 ms / 0.00 s / 114 MB | 20 ms / 0.02 s / 126 MB | 21 ms / 0.02 s / 127 MB | 12 ms / 0.01 s / 121 MB | 4 ms / 0.01 s / 169 MB | – | – | – |
| five columns | ours | 2 ms / 0.00 s / 113 MB | 21 ms / 0.02 s / 128 MB | 21 ms / 0.02 s / 129 MB | 12 ms / 0.01 s / 122 MB | 4 ms / 0.01 s / 170 MB | – | – | – |
| 1,000 rows | pyarrow | 12 ms / 0.01 s / 123 MB | 42 ms / 0.14 s / 277 MB | 52 ms / 0.26 s / 466 MB | 138 ms / 0.14 s / 226 MB | 19 ms / 0.05 s / 189 MB | 35 ms / 0.12 s / 268 MB | 9 ms / 0.02 s / 176 MB | 59 ms / 0.23 s / 519 MB |
| 1,000 rows | polars | 15 ms / 0.01 s / 123 MB | 43 ms / 0.14 s / 276 MB | 52 ms / 0.25 s / 464 MB | 120 ms / 0.12 s / 226 MB | 22 ms / 0.05 s / 188 MB | – | – | – |
| 1,000 rows | ours | 14 ms / 0.01 s / 126 MB | 43 ms / 0.14 s / 278 MB | 52 ms / 0.24 s / 467 MB | 112 ms / 0.11 s / 225 MB | 20 ms / 0.05 s / 190 MB | – | – | – |
| read + pass | pyarrow | 68 ms / 0.09 s / 315 MB | 92 ms / 0.30 s / 467 MB | 91 ms / 0.28 s / 467 MB | 203 ms / 0.20 s / 263 MB | 78 ms / 0.22 s / 507 MB | – | – | – |
| read + pass | polars | 68 ms / 0.09 s / 315 MB | 91 ms / 0.29 s / 466 MB | 91 ms / 0.29 s / 466 MB | 184 ms / 0.18 s / 264 MB | 80 ms / 0.23 s / 507 MB | – | – | – |
| read + pass | ours | 68 ms / 0.09 s / 318 MB | 91 ms / 0.28 s / 467 MB | 91 ms / 0.30 s / 468 MB | 176 ms / 0.18 s / 262 MB | 78 ms / 0.22 s / 508 MB | – | – | – |
| write, defaults | dta | 67 ms / 0.13 s / 292 MB | 255 ms / 0.25 s / 305 MB | – | 318 ms / 0.32 s / 299 MB | 85 ms / 0.24 s / 393 MB | – | – | – |
| write, zstd 3 | dta | 73 ms / 0.14 s / 294 MB | 271 ms / 0.27 s / 304 MB | – | 354 ms / 0.35 s / 300 MB | 85 ms / 0.24 s / 390 MB | – | – | – |

### Dominican Republic 2013 wm

9,372 rows, 3,854 columns; .dta 39.7 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 36 ms / 0.06 s / 408 MB | 92 ms / 0.39 s / 630 MB | 95 ms / 0.39 s / 631 MB | 300 ms / 0.30 s / 264 MB | 57 ms / 0.23 s / 641 MB | 63 ms / 0.21 s / 345 MB | 21 ms / 0.04 s / 348 MB | 221 ms / 0.22 s / 750 MB |
| whole file | polars | 39 ms / 0.07 s / 407 MB | 94 ms / 0.41 s / 630 MB | 93 ms / 0.41 s / 629 MB | 304 ms / 0.30 s / 262 MB | 58 ms / 0.25 s / 641 MB | – | – | – |
| whole file | ours | 42 ms / 0.07 s / 416 MB | 92 ms / 0.38 s / 632 MB | 92 ms / 0.39 s / 631 MB | 287 ms / 0.29 s / 261 MB | 56 ms / 0.23 s / 642 MB | – | – | – |
| five columns | pyarrow | 3 ms / 0.00 s / 114 MB | 27 ms / 0.03 s / 135 MB | 27 ms / 0.03 s / 135 MB | 38 ms / 0.04 s / 132 MB | 6 ms / 0.01 s / 176 MB | 27 ms / 0.03 s / 134 MB | 5 ms / 0.01 s / 174 MB | 10 ms / 0.01 s / 151 MB |
| five columns | polars | 2 ms / 0.00 s / 114 MB | 27 ms / 0.03 s / 134 MB | 27 ms / 0.03 s / 134 MB | 35 ms / 0.04 s / 129 MB | 6 ms / 0.01 s / 176 MB | – | – | – |
| five columns | ours | 3 ms / 0.00 s / 115 MB | 27 ms / 0.03 s / 137 MB | 28 ms / 0.03 s / 137 MB | 35 ms / 0.04 s / 129 MB | 6 ms / 0.01 s / 178 MB | – | – | – |
| 1,000 rows | pyarrow | 17 ms / 0.02 s / 154 MB | 87 ms / 0.29 s / 376 MB | 94 ms / 0.39 s / 631 MB | 306 ms / 0.31 s / 264 MB | 43 ms / 0.12 s / 239 MB | 64 ms / 0.21 s / 345 MB | 12 ms / 0.02 s / 201 MB | 191 ms / 0.74 s / 1345 MB |
| 1,000 rows | polars | 18 ms / 0.03 s / 154 MB | 89 ms / 0.30 s / 376 MB | 94 ms / 0.40 s / 630 MB | 312 ms / 0.31 s / 261 MB | 46 ms / 0.12 s / 239 MB | – | – | – |
| 1,000 rows | ours | 22 ms / 0.03 s / 163 MB | 85 ms / 0.29 s / 377 MB | 91 ms / 0.38 s / 631 MB | 288 ms / 0.29 s / 261 MB | 43 ms / 0.12 s / 240 MB | – | – | – |
| read + pass | pyarrow | 115 ms / 0.14 s / 408 MB | 166 ms / 0.47 s / 631 MB | 165 ms / 0.47 s / 632 MB | 425 ms / 0.43 s / 363 MB | 129 ms / 0.31 s / 642 MB | – | – | – |
| read + pass | polars | 117 ms / 0.15 s / 408 MB | 163 ms / 0.48 s / 630 MB | 163 ms / 0.47 s / 632 MB | 428 ms / 0.43 s / 365 MB | 129 ms / 0.32 s / 641 MB | – | – | – |
| read + pass | ours | 122 ms / 0.15 s / 417 MB | 163 ms / 0.46 s / 632 MB | 162 ms / 0.45 s / 632 MB | 411 ms / 0.41 s / 363 MB | 130 ms / 0.31 s / 643 MB | – | – | – |
| write, defaults | dta | 88 ms / 0.16 s / 419 MB | 354 ms / 0.35 s / 446 MB | – | 839 ms / 0.84 s / 423 MB | 160 ms / 0.36 s / 542 MB | – | – | – |
| write, zstd 3 | dta | 103 ms / 0.19 s / 419 MB | 368 ms / 0.37 s / 448 MB | – | 892 ms / 0.89 s / 424 MB | 159 ms / 0.35 s / 542 MB | – | – | – |

### Dominican Republic 2013 bh

18,167 rows, 1,078 columns; .dta 22.2 MB.

| case | input | dta_parser | pyarrow → pandas | pandas.read_parquet | fastparquet | polars → pandas | pyarrow Table | polars DataFrame | DuckDB → Arrow |
|---|---|---|---|---|---|---|---|---|---|
| whole file | pyarrow | 21 ms / 0.04 s / 264 MB | 46 ms / 0.20 s / 387 MB | 47 ms / 0.20 s / 386 MB | 100 ms / 0.10 s / 206 MB | 35 ms / 0.14 s / 423 MB | 33 ms / 0.10 s / 237 MB | 19 ms / 0.03 s / 270 MB | 82 ms / 0.08 s / 382 MB |
| whole file | polars | 22 ms / 0.04 s / 264 MB | 45 ms / 0.20 s / 386 MB | 46 ms / 0.20 s / 385 MB | 102 ms / 0.10 s / 206 MB | 37 ms / 0.14 s / 422 MB | – | – | – |
| whole file | ours | 22 ms / 0.04 s / 267 MB | 45 ms / 0.19 s / 386 MB | 47 ms / 0.19 s / 387 MB | 96 ms / 0.10 s / 206 MB | 35 ms / 0.14 s / 423 MB | – | – | – |
| five columns | pyarrow | 1 ms / 0.00 s / 112 MB | 20 ms / 0.02 s / 128 MB | 21 ms / 0.02 s / 127 MB | 11 ms / 0.01 s / 121 MB | 4 ms / 0.01 s / 169 MB | 20 ms / 0.02 s / 126 MB | 3 ms / 0.01 s / 166 MB | 4 ms / 0.00 s / 144 MB |
| five columns | polars | 1 ms / 0.00 s / 112 MB | 20 ms / 0.02 s / 126 MB | 20 ms / 0.02 s / 126 MB | 11 ms / 0.01 s / 120 MB | 4 ms / 0.01 s / 169 MB | – | – | – |
| five columns | ours | 2 ms / 0.00 s / 112 MB | 20 ms / 0.02 s / 127 MB | 21 ms / 0.02 s / 128 MB | 10 ms / 0.01 s / 120 MB | 4 ms / 0.01 s / 169 MB | – | – | – |
| 1,000 rows | pyarrow | 11 ms / 0.01 s / 122 MB | 40 ms / 0.12 s / 246 MB | 48 ms / 0.19 s / 386 MB | 102 ms / 0.10 s / 206 MB | 19 ms / 0.04 s / 186 MB | 33 ms / 0.10 s / 238 MB | 9 ms / 0.02 s / 175 MB | 50 ms / 0.21 s / 482 MB |
| 1,000 rows | polars | 13 ms / 0.01 s / 122 MB | 41 ms / 0.13 s / 244 MB | 47 ms / 0.20 s / 385 MB | 105 ms / 0.11 s / 205 MB | 21 ms / 0.05 s / 186 MB | – | – | – |
| 1,000 rows | ours | 12 ms / 0.01 s / 124 MB | 40 ms / 0.13 s / 247 MB | 47 ms / 0.19 s / 386 MB | 97 ms / 0.10 s / 205 MB | 18 ms / 0.04 s / 187 MB | – | – | – |
| read + pass | pyarrow | 54 ms / 0.07 s / 266 MB | 79 ms / 0.23 s / 387 MB | 78 ms / 0.25 s / 387 MB | 153 ms / 0.15 s / 231 MB | 66 ms / 0.16 s / 424 MB | – | – | – |
| read + pass | polars | 56 ms / 0.07 s / 265 MB | 77 ms / 0.25 s / 386 MB | 78 ms / 0.23 s / 387 MB | 154 ms / 0.15 s / 231 MB | 70 ms / 0.17 s / 424 MB | – | – | – |
| read + pass | ours | 55 ms / 0.07 s / 268 MB | 77 ms / 0.22 s / 388 MB | 78 ms / 0.23 s / 389 MB | 150 ms / 0.15 s / 231 MB | 67 ms / 0.17 s / 424 MB | – | – | – |
| write, defaults | dta | 52 ms / 0.10 s / 258 MB | 199 ms / 0.20 s / 270 MB | – | 285 ms / 0.28 s / 265 MB | 72 ms / 0.20 s / 354 MB | – | – | – |
| write, zstd 3 | dta | 58 ms / 0.11 s / 260 MB | 211 ms / 0.21 s / 273 MB | – | 319 ms / 0.32 s / 266 MB | 74 ms / 0.21 s / 354 MB | – | – | – |

