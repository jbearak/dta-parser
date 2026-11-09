"""One case of plan 0019's Python benchmark (datakit into pandas since
plan 0024), in a fresh process; bench/parquet/run_polars.py runs it
under /usr/bin/time -l.

    python bench/parquet/case_polars.py LIB TASK FILE OUT COLS SKIP N

LIB:
  ours     datakit's public functions: read_parquet (the pandas frame
           and its whole Meta), save_parquet (of the frame it read)
  pdarrow  pandas.read_parquet with the pyarrow engine (whole and
           columns=; the window as pyarrow's row groups, sliced, then
           to_pandas); DataFrame.to_parquet
  polars   pl.read_parquet (whole and columns=), pl.scan_parquet(...)
           .slice(skip, n).collect() (the window); DataFrame.write_parquet
  pyarrow  pyarrow.parquet.read_table (whole and columns=), and for the
           window the row groups that hold it, then sliced;
           pq.write_table(df.to_arrow()), the Arrow table made before
           timing
TASK: full, five (COLS), window (N rows from SKIP), pass (full, then one
pass over every value: each column's null count and sum, as numbers,
byte lengths or physical values), write and zstd (FILE read before
timing by the library's own reader: datakit, pandas or polars; each
library's defaults, and zstd level 3).

The .dta cases (published, not gated), FILE a .dta: dtaread, the whole
file (ours: datakit.read_dta, into pandas with the whole Meta; pandas:
dta_parser.read_dta); dtawrite, the file read untimed by each, then
written as release 118 (ours: datakit.save_dta; pandas:
dta_parser.write_dta).

Only the task is timed (wall, and CPU as user plus system of the
process); OUT gets a JSON report.
"""

import json
import os
import resource
import sys
import time

lib, task, path, out_path = sys.argv[1:5]
cols = [c for c in sys.argv[5].split(",") if c]
skip, n = int(sys.argv[6]), int(sys.argv[7])

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
if lib in ("polars", "pyarrow"):
    import polars as pl
if lib == "pandas":
    import dta_parser as dp

    version = "dta_parser (pandas)"
    threads = os.environ.get("DTA_THREADS") or "default"
elif lib == "ours":
    import datakit as pm

    version = f"datakit {pm.__version__}"
    threads = os.environ.get("DTA_THREADS") or "default"
elif lib == "polars":
    version = pl.__version__
    threads = str(pl.thread_pool_size())
elif lib == "pdarrow":
    import pandas as pd
    import pyarrow
    import pyarrow.parquet as pq

    version = f"pandas {pd.__version__}, pyarrow {pyarrow.__version__}"
    threads = str(pyarrow.cpu_count())
else:
    import pyarrow
    import pyarrow.compute as pc
    import pyarrow.parquet as pq

    version = pyarrow.__version__
    threads = str(pyarrow.cpu_count())

loaded = time.time()


def cpu():
    r = resource.getrusage(resource.RUSAGE_SELF)
    return r.ru_utime + r.ru_stime


def window_pyarrow(p):
    f = pq.ParquetFile(p)
    md = f.metadata
    groups, first, at = [], None, 0
    for g in range(md.num_row_groups):
        rows = md.row_group(g).num_rows
        if at + rows > skip and at < skip + n:
            groups.append(g)
            first = at if first is None else first
        at += rows
    t = f.read_row_groups(groups)
    return t.slice(skip - (first or 0), n)


READS = {
    "ours": {
        "full": lambda p: pm.read_parquet(p),
        "five": lambda p: pm.read_parquet(p, columns=cols),
        "window": lambda p: pm.read_parquet(p, skip=skip, n_max=n),
    },
    "pdarrow": {
        "full": lambda p: pd.read_parquet(p),
        "five": lambda p: pd.read_parquet(p, columns=cols),
        "window": lambda p: window_pyarrow(p).to_pandas(),
    },
    "polars": {
        "full": lambda p: pl.read_parquet(p),
        "five": lambda p: pl.read_parquet(p, columns=cols),
        "window": lambda p: pl.scan_parquet(p).slice(skip, n).collect(),
    },
    "pyarrow": {
        "full": lambda p: pq.read_table(p),
        "five": lambda p: pq.read_table(p, columns=cols),
        "window": window_pyarrow,
    },
}


def pass_polars(df):
    exprs = []
    for name, dt in df.schema.items():
        c = pl.col(name)
        exprs.append(c.null_count().alias(f"{name}\0n"))
        if dt == pl.String:
            v = c.str.len_bytes().sum()
        elif dt == pl.Binary:
            v = c.bin.size().sum()
        elif dt == pl.Boolean:
            v = c.sum()
        elif dt.is_numeric():
            v = c.cast(pl.Float64).sum()
        else:
            v = c.to_physical().cast(pl.Float64).sum()
        exprs.append(v.alias(f"{name}\0v"))
    row = df.select(exprs).row(0)
    return {"missing": int(sum(row[0::2])), "sum": float(sum(float(x or 0) for x in row[1::2]))}


def pass_pandas(df):
    import numpy as np
    import pandas as pd

    missing, total = 0, 0.0
    for name in df.columns:
        s = df[name]
        missing += int(s.isna().sum())
        t = s.dtype
        if isinstance(t, pd.CategoricalDtype):
            v = float(s.cat.codes.to_numpy().sum())
        elif t.kind in "Mm":
            v = float(s.dropna().to_numpy().view(np.int64).sum())
        elif t.kind in "biuf" or str(t).startswith("dta["):
            v = float(s.sum())
        else:
            v = float(sum(len(x.encode()) if isinstance(x, str) else len(x) for x in s.dropna()))
        total += v
    return {"missing": missing, "sum": total}


def pass_arrow(t):
    missing, total = 0, 0.0
    for name in t.column_names:
        a = t[name]
        missing += a.null_count
        ty = a.type
        if pyarrow.types.is_string(ty) or pyarrow.types.is_large_string(ty) or pyarrow.types.is_string_view(ty):
            v = pc.sum(pc.binary_length(a)).as_py()
        elif pyarrow.types.is_dictionary(ty):
            v = pc.sum(pc.cast(pc.dictionary_encode(a).combine_chunks().indices, "float64")).as_py() if len(a) else 0
        elif pyarrow.types.is_temporal(ty):
            v = pc.sum(pc.cast(pc.cast(a, pyarrow.int64()), "float64")).as_py()
        else:
            v = pc.sum(pc.cast(a, "float64")).as_py()
        total += float(v or 0)
    return {"missing": missing, "sum": total}


WRITES = {
    "ours": {
        "write": lambda df, dst: pm.save_parquet(df, dst),
        "zstd": lambda df, dst: pm.save_parquet(df, dst, compression="zstd", compression_level=3),
    },
    "pdarrow": {
        "write": lambda df, dst: df.to_parquet(dst),
        "zstd": lambda df, dst: df.to_parquet(dst, compression="zstd", compression_level=3),
    },
    "polars": {
        "write": lambda df, dst: df.write_parquet(dst),
        "zstd": lambda df, dst: df.write_parquet(dst, compression="zstd", compression_level=3),
    },
    "pyarrow": {
        "write": lambda t, dst: pq.write_table(t, dst),
        "zstd": lambda t, dst: pq.write_table(t, dst, compression="zstd", compression_level=3),
    },
}

result = {"loaded": loaded, "version": version, "threads": threads}
if task == "dtaread":
    t0, c0 = time.perf_counter(), cpu()
    got = pm.read_dta(path, timestamps="truncate") if lib == "ours" else dp.read_dta(path)
    result["wall"], result["cpu"] = time.perf_counter() - t0, cpu() - c0
    result["rows"] = len(got[0]) if lib == "ours" else len(got)
elif task == "dtawrite":
    dst = os.path.join(os.path.dirname(os.path.abspath(out_path)), f"w{os.getpid()}.dta")
    frame = pm.read_dta(path, timestamps="truncate") if lib == "ours" else dp.read_dta(path)
    t0, c0 = time.perf_counter(), cpu()
    if lib == "ours":
        pm.save_dta(frame[0], dst, meta=frame[1], timestamps="truncate")
    else:
        dp.write_dta(frame, dst)
    result["wall"], result["cpu"] = time.perf_counter() - t0, cpu() - c0
    result["bytes"] = os.path.getsize(dst)
    os.unlink(dst)
elif task in ("write", "zstd"):
    if lib == "ours":
        frame = pm.read_parquet(path)[0]
    elif lib == "pdarrow":
        frame = pd.read_parquet(path)
    else:
        frame = pl.read_parquet(path)
        if lib == "pyarrow":
            frame = frame.to_arrow()
    dst = os.path.join(os.path.dirname(os.path.abspath(out_path)), f"w{os.getpid()}.parquet")
    t0, c0 = time.perf_counter(), cpu()
    WRITES[lib][task](frame, dst)
    result["wall"], result["cpu"] = time.perf_counter() - t0, cpu() - c0
    result["bytes"] = os.path.getsize(dst)
    os.unlink(dst)
else:
    reader = READS[lib]
    t0, c0 = time.perf_counter(), cpu()
    if task == "pass":
        got = reader["full"](path)
        df = got[0] if lib == "ours" else got
        check = pass_arrow(df) if lib == "pyarrow" else pass_polars(df) if lib == "polars" else pass_pandas(df)
    else:
        got = reader[task](path)
        df = got[0] if lib == "ours" else got
        check = None
    result["wall"], result["cpu"] = time.perf_counter() - t0, cpu() - c0
    result["rows"] = df.num_rows if lib == "pyarrow" else df.height if lib == "polars" else len(df)
    if check is not None:
        result["checksum"] = check
with open(out_path, "w") as f:
    json.dump(result, f)
