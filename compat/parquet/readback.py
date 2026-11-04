"""Read the Parquet files dta-parquet wrote with pyarrow, pandas, polars
and DuckDB, and check their values and types against what the writer was
given (expected.json from the samples example) and against plan 0018's
table "What other tools see in our files".

Run from the repository root:

    cargo run -p dta-parquet --example samples -- DIR
    python3 compat/parquet/readback.py DIR

Needs pyarrow, pandas, polars and duckdb.
"""

import json
import math
import os
import sys

import duckdb
import polars as pl
import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.parquet as pq

DIR = sys.argv[1]
with open(os.path.join(DIR, "expected.json")) as f:
    EXPECTED = json.load(f)

failures = []
checked = {}


def fail(tool, file, what):
    failures.append(f"{tool}: {file}: {what}")


def same(a, b):
    """Values equal, with NaN equal to NaN (written "NaN" in JSON) and
    -0.0 told from 0.0."""
    if a == "NaN":
        return isinstance(b, float) and math.isnan(b)
    if isinstance(a, float) and isinstance(b, (int, float)):
        return a == b and math.copysign(1, a) == math.copysign(1, b)
    return a == b


def compare(tool, file, name, want, got):
    if len(want) != len(got):
        fail(tool, file, f"{name}: {len(got)} rows, not {len(want)}")
        return
    for i, (a, b) in enumerate(zip(want, got)):
        if not same(a, b):
            fail(tool, file, f"{name}: row {i + 1} is {b!r}, not {a!r}")
            return


def letters_of(spec):
    return spec.get("letters")


def as_nan(spec):
    """The values a tool that sees .a to .z as NaN gets: our tagged NaNs
    are NaN values, not nulls (plan 0018, "Missing values")."""
    letters = letters_of(spec)
    if letters is None:
        return spec["values"]
    return ["NaN" if l is not None else v for v, l in zip(spec["values"], letters)]


# ---- pyarrow and pandas ----

def arrow_type(spec):
    t = spec["type"]
    if t == "timestamp":
        zone = spec["zone"] or ("UTC" if spec["utc"] else None)
        return f"timestamp[{spec['unit']}, tz={zone}]" if zone else f"timestamp[{spec['unit']}]"
    if t == "categorical":
        return f"dictionary<values=string, indices=int32, ordered={int(spec['ordered'])}>"
    return {
        "int8": "int8",
        "int16": "int16",
        "int32": "int32",
        "int64": "int64",
        "float32": "float",
        "float64": "double",
        "bool": "bool",
        "text": "string",
        "binary": "binary",
        "date": "date32[day]",
    }[t]


def arrow_values(col, spec):
    t = spec["type"]
    if t in ("timestamp", "date"):
        col = pc.cast(col, pa.int64() if t == "timestamp" else pa.int32())
    values = col.to_pylist()
    if t == "binary":
        values = [None if v is None else list(v) for v in values]
    return values


def check_pyarrow(file, spec):
    path = os.path.join(DIR, file + ".parquet")
    table = pq.read_table(path)
    meta = pq.read_metadata(path)
    if b"dta" not in (meta.metadata or {}):
        fail("pyarrow", file, "no dta key in the file metadata")
    profile = json.loads((meta.metadata or {}).get(b"dta", b"{}"))
    if table.num_rows != spec["rows"]:
        fail("pyarrow", file, f"{table.num_rows} rows")
    for name, col_spec in spec["columns"].items():
        col = table.column(name)
        if str(col.type) != arrow_type(col_spec):
            fail("pyarrow", file, f"{name}: type {col.type}, not {arrow_type(col_spec)}")
        compare("pyarrow", file, name, as_nan(col_spec), arrow_values(col, col_spec))
        # A column written as DOUBLE because it holds .a to .z names its
        # storage type in the profile.
        storage = profile.get("columns", {}).get(name, {}).get("storage")
        if storage != col_spec.get("storage"):
            fail("pyarrow", file, f"{name}: profile storage {storage!r}, not {col_spec.get('storage')!r}")
        if col_spec["type"] == "categorical" and spec["rows"] > 0:
            # Every row group's dictionary holds every level, in order. A
            # table without rows has no row groups, so its levels are only
            # in the profile.
            for chunk in col.chunks:
                if chunk.dictionary.to_pylist() != col_spec["levels"]:
                    fail("pyarrow", file, f"{name}: levels {chunk.dictionary.to_pylist()}")
    checked["pyarrow"] = checked.get("pyarrow", 0) + 1

    # pandas, through pyarrow: the table's pandas column.
    df = table.to_pandas()
    for name, col_spec in spec["columns"].items():
        t = col_spec["type"]
        s = df[name]
        has_null = any(v is None for v in col_spec["values"])
        if t in ("int8", "int16"):
            want = "float64" if has_null else t
            if str(s.dtype) != want:
                fail("pandas", file, f"{name}: dtype {s.dtype}, not {want}")
        if t == "categorical" and spec["rows"] > 0:
            if str(s.dtype) != "category":
                fail("pandas", file, f"{name}: dtype {s.dtype}, not category")
            elif list(s.cat.categories) != col_spec["levels"] or bool(s.cat.ordered) != col_spec["ordered"]:
                fail("pandas", file, f"{name}: categories {list(s.cat.categories)}, ordered {s.cat.ordered}")
        if t == "timestamp" and col_spec["zone"]:
            if str(s.dt.tz) != col_spec["zone"]:
                fail("pandas", file, f"{name}: zone {s.dt.tz}, not {col_spec['zone']}")
        letters = letters_of(col_spec)
        if letters is not None:
            # pandas reads every NaN as missing, so .a to .z are missing
            # too (and so is a NaN value).
            missing = [v is None or v == "NaN" for v in col_spec["values"]]
            got = s.isna().tolist()
            if got != missing:
                row = next(i for i, (a, b) in enumerate(zip(missing, got)) if a != b)
                fail("pandas", file, f"{name}: row {row + 1} isna() is {got[row]}")
    checked["pandas"] = checked.get("pandas", 0) + 1


# ---- polars ----

def polars_type(spec):
    t = spec["type"]
    if t == "timestamp":
        zone = spec["zone"] or ("UTC" if spec["utc"] else None)
        return f"Datetime(time_unit='{spec['unit']}', time_zone={zone!r})"
    return {
        "int8": "Int8",
        "int16": "Int16",
        "int32": "Int32",
        "int64": "Int64",
        "float32": "Float32",
        "float64": "Float64",
        "bool": "Boolean",
        "text": "String",
        "binary": "Binary",
        "date": "Date",
        "categorical": "Categorical",
    }[t]


def check_polars(file, spec):
    df = pl.read_parquet(os.path.join(DIR, file + ".parquet"))
    if df.height != spec["rows"]:
        fail("polars", file, f"{df.height} rows")
    for name, col_spec in spec["columns"].items():
        s = df[name]
        t = col_spec["type"]
        dtype = str(s.dtype)
        if t == "categorical":
            dtype = dtype.split("(")[0]
        if dtype != polars_type(col_spec):
            fail("polars", file, f"{name}: dtype {s.dtype}, not {polars_type(col_spec)}")
        if t == "timestamp":
            s = s.dt.epoch(col_spec["unit"])
        elif t == "date":
            s = s.cast(pl.Int32)
        elif t == "categorical":
            s = s.cast(pl.String)
        values = s.to_list()
        if t == "binary":
            values = [None if v is None else list(v) for v in values]
        compare("polars", file, name, as_nan(col_spec), values)
        letters = letters_of(col_spec)
        if letters is not None:
            # NaN, not null: is_null() is false for .a to .z.
            want = sum(v is None and l is None for v, l in zip(col_spec["values"], letters))
            if s.null_count() != want:
                fail("polars", file, f"{name}: null_count() is {s.null_count()}, not {want}")
    checked["polars"] = checked.get("polars", 0) + 1


# ---- DuckDB ----

def duckdb_type(spec):
    t = spec["type"]
    if t == "timestamp":
        if spec["utc"]:
            return "TIMESTAMP WITH TIME ZONE"
        return {"ms": "TIMESTAMP_MS", "us": "TIMESTAMP", "ns": "TIMESTAMP_NS"}[spec["unit"]]
    return {
        "int8": "TINYINT",
        "int16": "SMALLINT",
        "int32": "INTEGER",
        "int64": "BIGINT",
        "float32": "FLOAT",
        "float64": "DOUBLE",
        "bool": "BOOLEAN",
        "text": "VARCHAR",
        "binary": "BLOB",
        "date": "DATE",
        "categorical": "VARCHAR",
    }[t]


def check_duckdb(file, spec):
    path = os.path.join(DIR, file + ".parquet").replace("'", "''")
    con = duckdb.connect()
    types = dict(con.execute(f"SELECT column_name, column_type FROM (DESCRIBE SELECT * FROM '{path}')").fetchall())
    for name, col_spec in spec["columns"].items():
        if types.get(name) != duckdb_type(col_spec):
            fail("duckdb", file, f"{name}: type {types.get(name)}, not {duckdb_type(col_spec)}")
        t = col_spec["type"]
        q = f'"{name}"'
        if t == "timestamp":
            q = {"ms": f"epoch_ms({q})", "us": f"epoch_us({q})", "ns": f"epoch_ns({q})"}[col_spec["unit"]]
        elif t == "date":
            q = f"({q} - DATE '1970-01-01')"
        values = [r[0] for r in con.execute(f"SELECT {q} FROM '{path}'").fetchall()]
        if t == "binary":
            values = [None if v is None else list(v) for v in values]
        compare("duckdb", file, name, as_nan(col_spec), values)
    # .a to .z are NaN, not NULL: count() counts them, and the docs' query
    # (x IS NULL OR isnan(x)) finds every missing value.
    for name, col_spec in spec["columns"].items():
        letters = letters_of(col_spec)
        if letters is not None:
            n, missing = con.execute(
                f'SELECT count("{name}"), count(*) FILTER ("{name}" IS NULL OR isnan("{name}")) FROM \'{path}\''
            ).fetchone()
            values = col_spec["values"]
            want = sum(v is not None or l is not None for v, l in zip(values, letters))
            if n != want:
                fail("duckdb", file, f"count({name}) is {n}, not {want}")
            want = sum(v is None or v == "NaN" for v in values)
            if missing != want:
                fail("duckdb", file, f"{name}: {missing} rows are NULL or NaN, not {want}")
    checked["duckdb"] = checked.get("duckdb", 0) + 1


for file, spec in EXPECTED.items():
    for check in (check_pyarrow, check_polars, check_duckdb):
        try:
            check(file, spec)
        except Exception as e:  # noqa: BLE001 - report every tool's failure
            fail(check.__name__[6:], file, f"{type(e).__name__}: {e}")

print(
    f"pyarrow {pa.__version__}, polars {pl.__version__}, duckdb {duckdb.__version__}: "
    + ", ".join(f"{tool} read {n} files" for tool, n in sorted(checked.items()))
)
if failures:
    print("\n".join(failures))
    sys.exit(1)
