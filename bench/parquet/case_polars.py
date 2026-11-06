"""One case of plan 0019's Python benchmark (PR 2a), in a fresh process;
bench/parquet/run_polars.py runs it under /usr/bin/time -l.

    python bench/parquet/case_polars.py LIB TASK FILE OUT COLS SKIP N

LIB:
  ours     dta_parser's native Arrow read through bench/parquet/
           polars_meta.py, which makes the whole Meta eagerly; writes
           through its save_parquet (the native writer reading polars'
           own export)
  polars   pl.read_parquet (whole and columns=), pl.scan_parquet(...)
           .slice(skip, n).collect() (the window); DataFrame.write_parquet
  pyarrow  pyarrow.parquet.read_table (whole and columns=), and for the
           window the row groups that hold it, then sliced;
           pq.write_table(df.to_arrow()), the Arrow table made before
           timing
TASK: full, five (COLS), window (N rows from SKIP), pass (full, then one
pass over every value: each column's null count and sum, as numbers,
byte lengths or physical values), write and zstd (FILE read by
pl.read_parquet before timing; each library's defaults, and zstd level
3).

The .dta cases (published, not gated), FILE a .dta: dtaread, the whole
file (ours: the native Arrow read into polars with the whole Meta;
pandas: dta_parser.read_dta); dtawrite, the file read untimed by each,
then written as release 118 (ours: the native writer from polars'
export; pandas: dta_parser.write_dta).

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

import polars as pl  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
if lib == "pandas":
    import dta_parser as dp

    version = "dta_parser (pandas)"
    threads = os.environ.get("DTA_THREADS") or "default"
elif lib == "ours":
    import polars_meta as pm

    version = "dta_parser (Arrow path)"
    threads = os.environ.get("DTA_THREADS") or "default"
elif lib == "polars":
    version = pl.__version__
    threads = str(pl.thread_pool_size())
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
    got = pm.read_dta(path) if lib == "ours" else dp.read_dta(path)
    result["wall"], result["cpu"] = time.perf_counter() - t0, cpu() - c0
    result["rows"] = got[0].height if lib == "ours" else len(got)
elif task == "dtawrite":
    dst = os.path.join(os.path.dirname(os.path.abspath(out_path)), f"w{os.getpid()}.dta")
    frame = pm.read_dta(path) if lib == "ours" else dp.read_dta(path)
    t0, c0 = time.perf_counter(), cpu()
    if lib == "ours":
        pm.save_dta(frame[0], dst, frame[1])
    else:
        dp.write_dta(frame, dst)
    result["wall"], result["cpu"] = time.perf_counter() - t0, cpu() - c0
    result["bytes"] = os.path.getsize(dst)
    os.unlink(dst)
elif task in ("write", "zstd"):
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
        check = pass_arrow(df) if lib == "pyarrow" else pass_polars(df)
    else:
        got = reader[task](path)
        df = got[0] if lib == "ours" else got
        check = None
    result["wall"], result["cpu"] = time.perf_counter() - t0, cpu() - c0
    result["rows"] = df.num_rows if lib == "pyarrow" else df.height
    if check is not None:
        result["checksum"] = check
with open(out_path, "w") as f:
    json.dump(result, f)
