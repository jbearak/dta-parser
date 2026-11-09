"""Read the Parquet files dta-parquet wrote with pyarrow, pandas, polars
and DuckDB, and check their values and types against what the writer was
given (expected.json from the samples example) and against plan 0018's
table "What other tools see in our files".

Run from the repository root:

    cargo run -p dta-parquet --example samples -- DIR
    python3 compat/parquet/readback.py DIR

Where Python's datakit is installed, it also writes its own files into
DIR/datakit (every pandas dtype save_parquet writes, with nulls, `.a` to `.z`
in each storage type, an ordered category with an unused level, and
a zone, in four codecs and in small row groups) and checks what pyarrow,
polars and DuckDB read from them, value by value (plan 0019).

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
        entry = profile.get("columns", {}).get(name, {})
        if entry.get("storage") != col_spec.get("storage"):
            fail("pyarrow", file, f"{name}: profile storage {entry.get('storage')!r}, not {col_spec.get('storage')!r}")
        # A date or timestamp written as DOUBLE (days or seconds since
        # 1970) says so, and a timestamp keeps its zone.
        if entry.get("logical") != col_spec.get("logical"):
            fail("pyarrow", file, f"{name}: profile logical {entry.get('logical')!r}, not {col_spec.get('logical')!r}")
        if col_spec.get("logical") == "timestamp" and entry.get("tz") != col_spec.get("tz"):
            fail("pyarrow", file, f"{name}: profile tz {entry.get('tz')!r}, not {col_spec.get('tz')!r}")
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



# ---- datakit's own files ----

# The storage types of datakit_files' DtaArray columns, and the polars
# dtypes they are written as without letters.
STORAGE = {"i8": "byte", "i16": "int", "i32": "long", "f32": "float", "f64": "double"}
POLARS = {"byte": "Int8", "int": "Int16", "long": "Int32", "float": "Float32", "double": "Float64"}


def datakit_files():
    """(name, frame, meta, save options) of the files datakit writes."""
    import datetime as dt

    import numpy as np
    import pandas as pd

    import datakit as dk

    n = 300
    r = list(range(n))
    def nulls(values, every=7):
        return [None if i % every == 3 else v for i, v in enumerate(values)]
    # A letter in every 11th row of the DtaArray columns, one of each
    # storage type (ADR 0040).
    letter = [f".{chr(97 + i % 26)}" if i % 11 == 5 else None for i in r]
    def lettered(values, storage):
        return pd.Series([dk.tagged_na(letter[i]) if letter[i] is not None else v for i, v in enumerate(values)],
                         dtype=f"dta[{storage}]")
    def times(values, unit):
        return pd.Series(values, dtype=f"datetime64[{unit}]")
    frame = pd.DataFrame({
        "i8": lettered(nulls([float(i % 100 - 50) for i in r]), "byte"),
        "i16": lettered(nulls([float(i * 97 - 9000) for i in r]), "int"),
        "i32": lettered(nulls([float(i * 7_000_001 - 10**9) for i in r]), "long"),
        "f32": lettered(nulls([i / 4 - 20 for i in r]), "float"),
        "f64": lettered(nulls([i * 1.5e10 - 1e12 for i in r]), "double"),
        "nan": np.array(nulls([float("nan") if i % 5 == 0 else i / 3 for i in r]), dtype=np.float64),
        "i64": pd.array(nulls([2**62 - i for i in r]), dtype="Int64"),
        "u8": pd.array(nulls([i % 256 for i in r]), dtype="UInt8"),
        "u64": pd.array(nulls([2**64 - 1 - i for i in r]), dtype="UInt64"),
        "flag": pd.array(nulls([i % 2 == 0 for i in r]), dtype="boolean"),
        "text": pd.Series(nulls([f"value {i} " + "é" * (i % 4) for i in r]), dtype=pd.Series(["a"]).dtype),
        "blob": pd.Series(nulls([bytes([i % 256, 0, 255]) for i in r]), dtype=object),
        "day": times(nulls([dt.datetime(1900, 1, 1) + dt.timedelta(days=97 * i) for i in r]), "s"),
        "local": times(nulls([dt.datetime(1960, 1, 1) + dt.timedelta(microseconds=123_456_789 * i) for i in r]), "us"),
        "zoned": times(nulls([dt.datetime(2024, 3, 1) + dt.timedelta(minutes=37 * i) for i in r]), "us")
        .dt.tz_localize("UTC").dt.tz_convert("Asia/Tokyo"),
        "ns": times(nulls([dt.datetime(2001, 1, 1) + dt.timedelta(seconds=i) for i in r]), "ns"),
        "cat": pd.Categorical(nulls([["lo", "mid", "hi"][i % 3] for i in r]), categories=["lo", "mid", "hi", "unused"],
                              ordered=True),
    })
    meta = dk.Meta(
        label="datakit readback", notes=["Written by compat/parquet/readback.py."],
        columns={"day": dk.Column(format="%td"), "i8": dk.Column(label="A byte", value_labels="v")},
        value_labels={"v": {1: "one", ".a": "skipped"}},
        rows=n,
    )
    out = []
    for codec in ("snappy", "zstd", "gzip", "none"):
        out.append((f"datakit_{codec}", frame, meta, {"compression": codec}))
    out.append(("datakit_groups", frame, meta, {"row_group_size": 64}))
    out.append(("datakit_nulls", frame, meta, {"missing_letters": False}))
    return out


def check_datakit(name, frame, meta, path, letters_kept):
    """What pyarrow, polars and DuckDB read from a file datakit wrote."""
    import numpy as np
    import pandas as pd

    from dta_parser import DtaArray

    table = pq.read_table(path)
    kv = pq.read_metadata(path).metadata or {}
    if b"dta" not in kv:
        fail("pyarrow", name, "no dta key")
    tdf = pl.read_parquet(path)
    con = duckdb.connect()
    def sql(expr):
        return [r[0] for r in con.execute(f"SELECT {expr} FROM '{path}'").fetchall()]
    for c in frame.columns:
        src = frame[c]
        t = src.dtype
        missing = src.isna().to_numpy()
        if isinstance(src.array, DtaArray):
            # With letters kept: a DOUBLE, NaN for each letter. Without:
            # its storage type, a null for each letter.
            codes = src.array.codes
            storage = src.dtype.storage
            kept = letters_kept and (codes > 1).any()
            values = src.array._values.tolist()
            integer = storage in ("byte", "int", "long") and not kept
            expect = [("NaN" if kept and code > 1 else None) if code else (int(v) if integer else v)
                      for v, code in zip(values, codes)]
            want_type = "Float64" if kept else POLARS[storage]
            if str(tdf.schema[c]) != want_type:
                fail("polars", name, f"{c}: dtype {tdf.schema[c]}, not {want_type}")
            if storage == "float" and not kept:
                expect = [None if v is None else float(np.float32(v)) for v in expect]
            compare("pyarrow", name, c, expect, table.column(c).to_pylist())
            compare("polars", name, c, expect, tdf[c].to_list())
            compare("duckdb", name, c, expect, sql(f'"{c}"'))
            continue
        if isinstance(t, pd.CategoricalDtype):
            expect = [None if m else v for v, m in zip(src.astype(object).tolist(), missing)]
            col = table.column(c)
            for chunk in col.chunks:
                if chunk.dictionary.to_pylist() != list(t.categories) or col.type.ordered != t.ordered:
                    fail("pyarrow", name, f"{c}: levels {chunk.dictionary.to_pylist()}, ordered {col.type.ordered}")
            compare("pyarrow", name, c, expect, col.cast(pa.string()).to_pylist())
            compare("polars", name, c, expect, tdf[c].cast(pl.String).to_list())
            compare("duckdb", name, c, expect, sql(f'"{c}"'))
            continue
        if t.kind == "M" and c == "day":
            # %td at midnight: a DATE.
            days = src.to_numpy().astype("datetime64[D]").view(np.int64)
            expect = [None if m else int(d) for d, m in zip(days, missing)]
            compare("pyarrow", name, c, expect, pc.cast(table.column(c), pa.int32()).to_pylist())
            compare("polars", name, c, expect, tdf[c].to_physical().to_list())
            compare("duckdb", name, c, expect, sql(f"(\"{c}\" - DATE '1970-01-01')"))
            continue
        if t.kind == "M":
            unit = np.datetime_data(src.array._ndarray.dtype)[0]
            expect = [None if m else int(v) for v, m in zip(src.array.asi8, missing)]
            zone = str(t.tz) if isinstance(t, pd.DatetimeTZDtype) else None
            if zone != (tdf[c].dtype.time_zone or None):
                fail("polars", name, f"{c}: zone {tdf[c].dtype.time_zone}, not {zone}")
            compare("pyarrow", name, c, expect, pc.cast(table.column(c), pa.int64()).to_pylist())
            compare("polars", name, c, expect, tdf[c].dt.epoch(unit).to_list())
            fn = {"ms": "epoch_ms", "us": "epoch_us", "ns": "epoch_ns"}[unit]
            compare("duckdb", name, c, expect, sql(f'{fn}("{c}")'))
            continue
        # A NaN is `.`, a null (plan 0024).
        expect = [None if m else v for v, m in zip(src.astype(object).tolist(), missing)]
        compare("pyarrow", name, c, expect, table.column(c).to_pylist())
        compare("polars", name, c, expect, tdf[c].to_list())
        compare("duckdb", name, c, expect, sql(f'"{c}"'))
    for tool in ("pyarrow", "polars", "duckdb"):
        checked[tool] = checked.get(tool, 0) + 1


def reads_back_equal(frame, back):
    """datakit reads its own file back: the same values and codes; a NaN
    in a float column is `.`, so that column comes back a DtaArray."""
    import numpy as np
    import pandas as pd

    from dta_parser import DtaArray

    for c in frame.columns:
        a, b = frame[c], back[c]
        if c == "nan":
            if not (isinstance(b.array, DtaArray) and np.array_equal(b.array.codes, a.isna().to_numpy())):
                return False
            continue
        if isinstance(a.array, DtaArray) and not (isinstance(b.array, DtaArray) and a.array.equals(b.array)):
            return False
        try:
            pd.testing.assert_series_equal(a, b)
        except AssertionError:
            return False
    return True


try:
    import datakit as _dk
except ImportError:
    _dk = None
if _dk is not None:
    out_dir = os.path.join(DIR, "datakit")
    os.makedirs(out_dir, exist_ok=True)
    for name, frame, meta, options in datakit_files():
        path = os.path.join(out_dir, name + ".parquet")
        try:
            _dk.save_parquet(frame, path, meta=meta, **options)
            check_datakit(name, frame, meta, path, options.get("missing_letters", True))
            back, back_meta = _dk.read_parquet(path)
            if options.get("missing_letters", True) and not reads_back_equal(frame, back):
                fail("datakit", name, "does not read back equal")
        except Exception as e:  # noqa: BLE001 - report every failure
            fail("datakit", name, f"{type(e).__name__}: {e}")

print(
    f"pyarrow {pa.__version__}, polars {pl.__version__}, duckdb {duckdb.__version__}: "
    + ", ".join(f"{tool} read {n} files" for tool, n in sorted(checked.items()))
)
if failures:
    print("\n".join(failures))
    sys.exit(1)
