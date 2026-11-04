"""Make the pyarrow, polars and DuckDB inputs from ours, each with that
tool's default writer settings, so all hold the same data (plan 0018,
"Speed and memory"). Our profile is not carried over: the others' files
are what those tools write.

    python bench/parquet/convert.py DIR KEY ...

reads DIR/ours/KEY.parquet and writes DIR/{pyarrow,polars,duckdb}/KEY.parquet.
"""

import os
import sys

import duckdb
import polars as pl
import pyarrow.parquet as pq

root, keys = sys.argv[1], sys.argv[2:]
for tool in ("pyarrow", "polars", "duckdb"):
    os.makedirs(os.path.join(root, tool), exist_ok=True)
for key in keys:
    src = os.path.join(root, "ours", key + ".parquet")
    for tool in ("pyarrow", "polars", "duckdb"):
        dst = os.path.join(root, tool, key + ".parquet")
        if os.path.exists(dst):
            continue
        tmp = dst + ".tmp"
        if tool == "pyarrow":
            table = pq.read_table(src)
            pq.write_table(table.replace_schema_metadata(None), tmp)
        elif tool == "polars":
            pl.read_parquet(src).write_parquet(tmp)
        else:
            con = duckdb.connect()
            con.execute("COPY (SELECT * FROM read_parquet(?)) TO '%s' (FORMAT parquet)" % tmp.replace("'", "''"), [src])
            con.close()
        os.replace(tmp, dst)
        print(key, tool, f"{os.path.getsize(dst) / 1e6:.3g} MB", flush=True)
