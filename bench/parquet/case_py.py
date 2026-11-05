"""One Parquet benchmark case in Python, in a fresh process;
bench/parquet/run_py.py runs it under /usr/bin/time -l, five times per
case (plan 0018, "Speed and memory", Python).

    python bench/parquet/case_py.py LIB TASK FILE OUT COLS SKIP N

LIB, into pandas (gated): ours (dta_parser.read_parquet / write_parquet),
pyarrow (pyarrow.parquet.read_table().to_pandas(); writes
DataFrame.to_parquet, whose engine is pyarrow), pandas
(pandas.read_parquet), fastparquet (ParquetFile().to_pandas(); writes
fastparquet.write), polars (polars.read_parquet().to_pandas(); writes
polars.from_pandas().write_parquet()).
Into their own types (published, not gated): pyarrow-table
(read_table), polars-df (polars.read_parquet), duckdb-arrow (DuckDB's
relation fetched as an Arrow table).

TASK is one of
  full    read the whole file
  five    read five named columns (COLS, comma-separated)
  window  read N rows from row SKIP (0-based)
  pass    read the whole file, then one pass over every value
  write   read FILE (a .dta) with dta_parser.read_dta, then time
          writing it with LIB's defaults
  zstd    the same, with zstd at level 3
Only the task is timed (wall and CPU, user plus system, of this process
and its threads); OUT gets a JSON report.
"""

import json
import os
import resource
import sys
import time

lib, task, path, out_path = sys.argv[1:5]
cols = [c for c in sys.argv[5].split(",") if c]
skip, n = int(sys.argv[6]), int(sys.argv[7])

import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

import dta_parser as dp  # noqa: E402

if lib in ("pyarrow", "pyarrow-table", "pandas"):
    import pyarrow
    import pyarrow.parquet as pq

    version = pyarrow.__version__ if lib != "pandas" else pd.__version__
elif lib in ("polars", "polars-df"):
    import polars as pl

    version = pl.__version__
elif lib == "fastparquet":
    import fastparquet

    version = fastparquet.__version__
elif lib == "duckdb-arrow":
    import duckdb

    version = duckdb.__version__
    con = duckdb.connect()
else:
    version = dp.__version__ if hasattr(dp, "__version__") else "0.2.0"

loaded = time.time()


def cpu():
    r = resource.getrusage(resource.RUSAGE_SELF)
    return r.ru_utime + r.ru_stime


def quoted(name):
    return '"' + name.replace('"', '""') + '"'


def duck(sql, *params):
    return con.sql(sql, params=list(params) or None).fetch_arrow_table()


READS = {
    "ours": {
        "full": lambda p: dp.read_parquet(p),
        "five": lambda p: dp.read_parquet(p, columns=cols),
        "window": lambda p: dp.read_parquet(p, skip=skip, n_max=n),
    },
    "pyarrow": {
        "full": lambda p: pq.read_table(p).to_pandas(),
        "five": lambda p: pq.read_table(p, columns=cols).to_pandas(),
        # read_table has no rows: read the table, convert only the slice.
        "window": lambda p: pq.read_table(p).slice(skip, n).to_pandas(),
    },
    "pandas": {
        "full": lambda p: pd.read_parquet(p),
        "five": lambda p: pd.read_parquet(p, columns=cols),
        # No rows either: read, then slice.
        "window": lambda p: pd.read_parquet(p).iloc[skip:skip + n],
    },
    "fastparquet": {
        "full": lambda p: fastparquet.ParquetFile(p).to_pandas(),
        "five": lambda p: fastparquet.ParquetFile(p).to_pandas(columns=cols),
        "window": lambda p: fastparquet.ParquetFile(p).to_pandas().iloc[skip:skip + n],
    },
    "polars": {
        "full": lambda p: pl.read_parquet(p).to_pandas(),
        "five": lambda p: pl.read_parquet(p, columns=cols).to_pandas(),
        "window": lambda p: pl.scan_parquet(p).slice(skip, n).collect().to_pandas(),
    },
    "pyarrow-table": {
        "full": lambda p: pq.read_table(p),
        "five": lambda p: pq.read_table(p, columns=cols),
        "window": lambda p: pq.read_table(p).slice(skip, n),
    },
    "polars-df": {
        "full": lambda p: pl.read_parquet(p),
        "five": lambda p: pl.read_parquet(p, columns=cols),
        "window": lambda p: pl.scan_parquet(p).slice(skip, n).collect(),
    },
    "duckdb-arrow": {
        "full": lambda p: duck("SELECT * FROM read_parquet(?)", p),
        "five": lambda p: duck(f"SELECT {', '.join(map(quoted, cols))} FROM read_parquet(?)", p),
        "window": lambda p: duck(f"SELECT * FROM read_parquet(?) LIMIT {n} OFFSET {skip}", p),
    },
}


def write_fastparquet(df, dst, codec=None):
    if codec is None:
        fastparquet.write(dst, df)
    else:
        fastparquet.write(dst, df, compression={"_default": {"type": "ZSTD", "args": {"level": 3}}})


WRITES = {
    "ours": {
        "write": lambda df, dst: dp.write_parquet(df, dst),
        "zstd": lambda df, dst: dp.write_parquet(df, dst, compression="zstd", compression_level=3),
    },
    "pyarrow": {
        "write": lambda df, dst: df.to_parquet(dst, index=False),
        "zstd": lambda df, dst: df.to_parquet(dst, index=False, compression="zstd", compression_level=3),
    },
    "fastparquet": {
        "write": lambda df, dst: write_fastparquet(df, dst),
        "zstd": lambda df, dst: write_fastparquet(df, dst, "zstd"),
    },
    "polars": {
        "write": lambda df, dst: pl.from_pandas(df).write_parquet(dst),
        "zstd": lambda df, dst: pl.from_pandas(df).write_parquet(dst, compression="zstd", compression_level=3),
    },
}


def pass_over(df):
    """One pass over every value of a pandas frame: the sum of the
    numbers, the count of missing values and the total length of the
    text, the same loop for every library."""
    total, missing, length = 0.0, 0, 0
    for name in df.columns:
        x = df[name]
        dt = x.dtype
        if isinstance(dt, pd.CategoricalDtype):
            codes = x.cat.codes.to_numpy()
            missing += int((codes < 0).sum())
            length += int(x.astype(object).dropna().map(len).sum()) if len(x) else 0
        elif dt.kind in "iufb" or isinstance(dt, dp.StataDtype):
            v = x.to_numpy(dtype=np.float64, na_value=np.nan)
            miss = np.isnan(v)
            total += float(v[~miss].sum())
            missing += int(miss.sum())
        elif dt.kind in "Mm":
            v = x.isna().to_numpy()
            missing += int(v.sum())
            total += float(np.asarray(x.array.asi8 if hasattr(x.array, "asi8") else x.to_numpy().view(np.int64))[~v]
                           .astype(np.float64).sum())
        elif isinstance(dt, pd.StringDtype):
            lengths = x.str.len()
            missing += int(lengths.isna().sum())
            length += int(lengths.sum())
        else:
            for v in x.to_numpy(dtype=object):
                if v is None or (isinstance(v, float) and v != v):
                    missing += 1
                else:
                    length += len(v)
    return {"sum": total, "missing": missing, "length": length}


def plain(df):
    """The frame for the other libraries: StataArray columns as float64
    (no other writer takes them), and no attrs (pandas cannot write
    attrs holding missing-value keys)."""
    out = df.copy(deep=False)
    for name in out.columns:
        if isinstance(out[name].dtype, dp.StataDtype):
            out[name] = out[name].to_numpy(dtype=np.float64, na_value=np.nan)
    out.attrs = {}
    return out


threads = os.environ.get("DTA_THREADS") or "default"
if lib in ("pyarrow", "pyarrow-table", "pandas"):
    threads = str(pyarrow.cpu_count())
elif lib in ("polars", "polars-df"):
    threads = str(pl.thread_pool_size())
elif lib == "fastparquet":
    threads = "1"
elif lib == "duckdb-arrow":
    threads = str(con.sql("SELECT current_setting('threads')").fetchall()[0][0])
result = {"loaded": loaded, "version": version, "threads": threads}
if task in ("write", "zstd"):
    df = dp.read_dta(path)
    if lib != "ours":
        df = plain(df)
    dst = os.path.join(os.path.dirname(os.path.abspath(out_path)), f"w{os.getpid()}.parquet")
    t0, c0 = time.perf_counter(), cpu()
    WRITES[lib][task](df, dst)
    result["wall"], result["cpu"] = time.perf_counter() - t0, cpu() - c0
    result["bytes"] = os.path.getsize(dst)
    os.unlink(dst)
else:
    reader = READS[lib]
    t0, c0 = time.perf_counter(), cpu()
    if task == "pass":
        out = pass_over(reader["full"](path))
    else:
        out = reader[task](path)
    result["wall"], result["cpu"] = time.perf_counter() - t0, cpu() - c0
    if task == "pass":
        result["checksum"] = out
    else:
        result["rows"] = len(out)
with open(out_path, "w") as f:
    json.dump(result, f)
