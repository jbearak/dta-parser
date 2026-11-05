"""One Parquet read in Python, in a fresh process, for plan 0018's fourth
target: pyarrow, polars and DuckDB reading our files against their own
default output. bench/parquet/run.py runs it under /usr/bin/time -l.

    python bench/parquet/case.py TOOL FILE OUT

TOOL is pyarrow (pyarrow.parquet.read_table), polars (polars.read_parquet)
or duckdb (SELECT * fetched as an Arrow table). Only the read is timed.
"""

import json
import resource
import sys
import time

tool, path, out = sys.argv[1:4]
if tool == "pyarrow":
    import pyarrow
    import pyarrow.parquet as pq

    version = pyarrow.__version__
    read = lambda p: pq.read_table(p)
elif tool == "polars":
    import polars as pl

    version = pl.__version__
    read = lambda p: pl.read_parquet(p)
elif tool == "duckdb":
    import duckdb

    version = duckdb.__version__
    con = duckdb.connect()
    read = lambda p: con.sql("SELECT * FROM read_parquet(?)", params=[p]).fetch_arrow_table()
else:
    raise SystemExit(f"unknown tool {tool}")


def cpu():
    r = resource.getrusage(resource.RUSAGE_SELF)
    return r.ru_utime + r.ru_stime


loaded = time.time()
t0, c0 = time.perf_counter(), cpu()
table = read(path)
wall, used = time.perf_counter() - t0, cpu() - c0
with open(out, "w") as f:
    json.dump({"loaded": loaded, "version": version, "wall": wall, "cpu": used, "rows": len(table)}, f)
