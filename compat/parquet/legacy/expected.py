"""Read every legacy fixture (compat/parquet/legacy/*.parquet) with
pyarrow and write what it reads to compat/parquet/legacy/expected/<name>.json.

Each file's JSON holds its rows, its row groups' sizes, the file's `dta`
metadata entry (the profile, parsed), whether it has an `ARROW:schema`
entry, and for each column its Parquet physical and logical types and
codec, its Arrow type and its values.

Values are made comparable in JSON as in ../expected.py: timestamps as
integers in the column's unit, dates as days since 1970-01-01, bytes as
lists of integers, dictionary columns as their values. A NaN is written
as "NaN:" and its bits in hexadecimal (16 digits for a double, 8 for a
float), so `.a` to `.z`, which are NaNs whose payload holds the letter,
keep it.

Run from the repository root: python3 compat/parquet/legacy/expected.py
"""

import glob
import json
import os

import numpy as np
import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.parquet as pq

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "expected")
os.makedirs(OUT, exist_ok=True)


def float_values(col):
    """A float column's values, each NaN with its bits."""
    out = []
    bits_type = np.uint64 if pa.types.is_float64(col.type) else np.uint32
    width = 16 if bits_type is np.uint64 else 8
    for chunk in col.chunks:
        valid = chunk.is_valid().to_pylist()
        data = chunk.to_numpy(zero_copy_only=False)
        bits = data.view(bits_type)
        for v, x, b in zip(valid, data, bits):
            if not v:
                out.append(None)
            elif np.isnan(x):
                out.append(f"NaN:{int(b):0{width}x}")
            else:
                out.append(float(x))
    return out


def values(col):
    t = col.type
    if pa.types.is_dictionary(t):
        col = col.cast(t.value_type)
        t = t.value_type
    if pa.types.is_floating(t):
        return float_values(col)
    if pa.types.is_timestamp(t):
        col = pc.cast(col, pa.int64())
    elif pa.types.is_date32(t) or pa.types.is_time32(t):
        col = pc.cast(col, pa.int32())
    elif pa.types.is_time64(t):
        col = pc.cast(col, pa.int64())
    out = col.to_pylist()
    if pa.types.is_binary(t) or pa.types.is_large_binary(t) or pa.types.is_fixed_size_binary(t):
        out = [None if v is None else list(v) for v in out]
    return out


for path in sorted(glob.glob(os.path.join(HERE, "*.parquet"))):
    stem = os.path.splitext(os.path.basename(path))[0]
    pf = pq.ParquetFile(path)
    md = pf.metadata
    kv = md.metadata or {}
    table = pf.read()
    schema = pf.schema
    columns = []
    for k, f in enumerate(table.schema):
        pcol = schema.column(k)
        columns.append({
            "name": f.name,
            "physical_type": pcol.physical_type,
            "logical_type": str(pcol.logical_type),
            "codec": md.row_group(0).column(k).compression if md.num_row_groups else None,
            "arrow_type": str(f.type),
            "values": values(table.column(k)),
        })
    doc = {
        "rows": table.num_rows,
        "row_groups": [md.row_group(g).num_rows for g in range(md.num_row_groups)],
        "arrow_schema": b"ARROW:schema" in kv,
        "dta": json.loads(kv[b"dta"]) if b"dta" in kv else None,
        "columns": columns,
    }
    with open(os.path.join(OUT, stem + ".json"), "w") as f:
        json.dump(doc, f, indent=None, separators=(",", ":"), ensure_ascii=False)
        f.write("\n")
    print(f"{stem}: {table.num_rows} rows, {table.num_columns} columns, {md.num_row_groups} row groups")
