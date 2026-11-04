"""Read every fixture in compat/parquet/fixtures/ with pyarrow and write
what it reads to compat/parquet/expected/<name>.json: each column's Arrow
type and values. crates/parquet/tests/compat.rs compares dta-parquet's
reading of the fixtures with these.

Values are made comparable in JSON: timestamps and times as integers in
the column's unit, dates as days since 1970-01-01, bytes (fixed-size
too) as lists of integers, decimals as text with every digit (Python's
`format(d, "f")`), NaN as the text "NaN", dictionary columns as their
values, extension types (UUID, JSON) as their storage.

Run from the repository root: python3 compat/parquet/expected.py
"""

import glob
import json
import math
import os

import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.parquet as pq

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "expected")
os.makedirs(OUT, exist_ok=True)


def values(col):
    t = col.type
    if isinstance(t, pa.BaseExtensionType):
        col = pa.chunked_array([c.storage for c in col.chunks], t.storage_type)
        t = t.storage_type
    if pa.types.is_dictionary(t):
        col = col.cast(t.value_type)
        t = t.value_type
    if pa.types.is_timestamp(t):
        col = pc.cast(col, pa.int64())
    elif pa.types.is_date32(t) or pa.types.is_time32(t):
        col = pc.cast(col, pa.int32())
    elif pa.types.is_time64(t):
        col = pc.cast(col, pa.int64())
    out = col.to_pylist()
    if pa.types.is_decimal(t):
        out = [None if v is None else format(v, "f") for v in out]
    if pa.types.is_binary(t) or pa.types.is_large_binary(t) or pa.types.is_fixed_size_binary(t):
        out = [None if v is None else list(v) for v in out]
    if pa.types.is_floating(t):
        out = ["NaN" if v is not None and math.isnan(v) else v for v in out]
    return out


for path in sorted(glob.glob(os.path.join(HERE, "fixtures", "*.parquet"))):
    stem = os.path.splitext(os.path.basename(path))[0]
    table = pq.read_table(path)
    nested = [f.name for f in table.schema if pa.types.is_nested(f.type)]
    doc = {
        "rows": table.num_rows,
        "columns": [
            {"name": f.name, "arrow_type": str(f.type), "values": values(table.column(f.name))}
            for f in table.schema
            if f.name not in nested
        ],
    }
    if nested:
        # Not read by dta-parquet; listed so the test checks they are named.
        doc["nested"] = nested
    with open(os.path.join(OUT, stem + ".json"), "w") as f:
        json.dump(doc, f, indent=None, separators=(",", ":"))
        f.write("\n")
    print(f"{stem}: {table.num_rows} rows, {table.num_columns} columns")
