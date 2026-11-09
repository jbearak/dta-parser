"""One frame in both languages (plan 0025, stage 4). Python's half, and
the checker:

    python compat/parquet/cross_language_polars.py fixtures DIR
    python compat/parquet/cross_language_polars.py save DIR
    python compat/parquet/cross_language_polars.py dump DIR
    python compat/parquet/cross_language_polars.py compare DIR

compat/parquet/cross_language_polars.sh runs them with R's halves
(cross_language_polars.R) in turn:

1. `fixtures` writes the inputs with this library's writers, from data
   made here: DIR/fixture.parquet and DIR/fixture.dta (Python datakit's
   save_parquet and save_dta), DIR/other.parquet (pyarrow: Decimal,
   Int64, UInt64 and a dictionary column, which the "dta" profile does
   not describe), and DIR/cases.json, the reads both languages make.
2. `save`, in each language: the fixtures read with read_parquet /
   read_dta (R: read_parquet_pl / read_dta_pl), with factors off and on,
   and saved again with save_parquet and save_dta, as
   DIR/saved_python*.{parquet,dta} and DIR/saved_r*.{parquet,dta}.
3. `dump`, in each language: every read in cases.json, of the fixtures
   and of both languages' saved files, written as Arrow IPC
   (DIR/python/CASE.arrow, DIR/r/CASE.arrow) with the metadata as JSON
   beside it (CASE.json). A read that fails writes {"error": message}.
4. `compare` checks R's dump against Python's, case by case: the column
   names and order; the dtypes, with temporal units and zones and Enum
   levels; which rows are null; every valid cell, a Float64 by its bits
   (as UInt64) and a Float32 by its own (as UInt32), so that each
   letter's payload counts; and the metadata, field by field, `storage`
   by dtype name and value labels as {"set", "code", "text"} records, a
   code being a number or ".", ".a" ... ".z". Buffers under nulls, chunk
   boundaries and dictionary layout are not compared. Exits with status
   1 if anything differs.

Needs dta_parser, datakit, polars and pyarrow installed.
"""

import datetime as dt
import json
import math
import os
import sys
import warnings

import polars as pl

import datakit as dk

MODE, DIR = sys.argv[1], sys.argv[2]
NA = dk.tagged_na
MS1960 = 3653 * 86_400_000
NY = "America/New_York"


def path(*parts):
    return os.path.join(DIR, *parts)


# ---------------------------------------------------------------- the fixtures

# Rows 1 to 3 hold no letter in any column, rows 4 to 6 hold them, so
# that a window of rows 1 to 3 reads every column with its own dtype and
# one of rows 4 to 7 reads the letters.
def fixture():
    df = pl.DataFrame({
        "id": pl.Series(range(1, 9), dtype=pl.Int32),
        # Labels on ., .a and .z; -0.0 and 2^1000 checked by their bits.
        "score": [1.0, 1.5, -2.25, 2.0**1000, NA(".a"), None, NA(".z"), -0.0],
        # Columns holding letters are Float64; meta keeps their storage.
        "small": [1.0, 0.0, 100.0, NA(".d"), -127.0, None, 1.0, 0.0],
        "lng": [2147483620.0, -2147483647.0, 0.0, NA(".b"), None, 7.0, 1.0, 2.0],
        "fl": [0.5, 3.25, -1.0, NA(".c"), None, 2.0, 0.375, 1024.0],
        "count": pl.Series([3, None, 0, -5, 2147483647, 1, 2, 3], dtype=pl.Int32),
        "flag": [True, False, None, True, True, False, None, True],
        # "nan" as text: is_missing's expression would count it, the
        # Series form does not.
        "word": ["a", None, "", "été", "x y", "z", "nan", "q"],
        "region": pl.Series(["N", "S", None, "N", "E", "S", "W", "W"], dtype=pl.Enum(["S", "N", "E", "W"])),
        # Two codes sharing a text, and a value with no label.
        "dup": pl.Series([1, 2, 3, 1, 5, None, 2, 3], dtype=pl.Int8),
        "day": [dt.date(2024, 3, 1), dt.date(1960, 1, 1), None, dt.date(1900, 2, 28), dt.date(2100, 12, 31),
                dt.date(1970, 1, 1), dt.date(2000, 2, 29), dt.date(1959, 12, 31)],
        "stamp": pl.Series([0, 1_709_285_400_250, None, -1000, 86_400_000, 1_000_000_000_000, 1, -1],
                           dtype=pl.Int64).cast(pl.Datetime("ms")),
        # A date and a timestamp holding letters: Stata's days and
        # milliseconds since 1960, with %td and %tc.
        "seen": [23436.0, 23437.0, 0.0, NA(".d"), None, NA(".z"), 1.0, -1.0],
        "clock": [MS1960 + 500.0, MS1960 + 1e12, None, NA(".k"), MS1960 - 86_400_250.0, 0.0, 1.0, 2.0],
        # A categorical holding letters: its level numbers with its set.
        "grade": [1.0, 3.0, 2.0, NA(".a"), None, NA(".z"), 2.0, 1.0],
    })
    meta = dk.Meta(
        label="Fixture for both languages",
        notes=["First note.", "Second note, été."],
        characteristics={"_dta": {"origin": "made up"}, "score": {"source": "a test", "unit": "points"}},
        sort=["id"],
        timestamp="05 Nov 2026 10:00",
        columns={c: dk.Column() for c in df.columns},
        value_labels={
            "scorelab": {1: "One", ".": "Not asked", ".a": "Refused", ".z": "Other"},
            "yn": {0: "No", 1: "Yes", ".d": "Don't know"},
            "dupl": {1: "Yes", 2: "No", 3: "Yes"},
            "grade": {1: "low", 2: "mid", 3: "high"},
        },
        rows=df.height,
    )
    meta._storage = {"small": pl.Int8, "lng": pl.Int32, "fl": pl.Float32}
    meta.columns["score"] = dk.Column("A score", "%9.2f", "scorelab")
    meta.columns["small"] = dk.Column("Yes or no", None, "yn")
    meta.columns["lng"].label = "A long"
    meta.columns["count"].label = "A count"
    meta.columns["dup"].value_labels = "dupl"
    meta.columns["day"].format = "%tdCCYY-NN-DD"
    meta.columns["seen"].format = "%td"
    meta.columns["clock"].format = "%tc"
    meta.columns["grade"].value_labels = "grade"
    return df, meta


# A zoned timestamp and a plain NaN, which only Parquet holds.
def parquet_only(df):
    when = pl.Series([0, 1_709_285_400_250_000, None, -1_000_000, 86_400_000_000, 1_000_000_000_000_000, 1, -1],
                     dtype=pl.Int64).cast(pl.Datetime("us")).dt.replace_time_zone("UTC").dt.convert_time_zone(NY)
    return df.with_columns(when.alias("when"),
                           pl.Series("nan", [0.5, float("nan"), None, 1.0, NA(".e"), -float("nan"), 2.0, 3.0]))


def other_parquet(file):
    """Decimal, Int64, UInt64 and a dictionary column, written by pyarrow."""
    import decimal

    import pyarrow as pa
    import pyarrow.parquet as pq

    table = pa.table({
        "dec": pa.array([decimal.Decimal("1.25"), None, decimal.Decimal("-99999999.99"), decimal.Decimal("0.01")],
                        pa.decimal128(10, 2)),
        "big": pa.array([2**53 + 1, None, -(2**62), 0], pa.int64()),
        "ubig": pa.array([2**64 - 1, 0, None, 7], pa.uint64()),
        "cat": pa.array(["b", "a", None, "b"]).dictionary_encode(),
        "f32": pa.array([1.5, float("nan"), None, -0.0], pa.float32()),
    })
    pq.write_table(table, file)


# Each read both languages make: a file, then the arguments. Windows of
# rows 1 to 3 (no letter) and 4 to 7 (letters); factors and letters
# each way; and some columns, in an order of their own.
def cases():
    reads = [
        ("default", {}),
        ("no_letters", {"letters": False}),
        ("factors", {"factors": True}),
        ("factors_no_letters", {"factors": True, "letters": False}),
        ("window_plain", {"skip": 0, "n_max": 3}),
        ("window_letters", {"skip": 3, "n_max": 4}),
        ("window_letters_off", {"skip": 3, "n_max": 4, "letters": False}),
        ("some_columns", {"columns": ["grade", "score", "id", "small"]}),
    ]
    files = ["fixture.parquet", "fixture.dta"]
    for who in ("python", "r"):
        for kind in ("", "_factors"):
            files += [f"saved_{who}{kind}.parquet", f"saved_{who}{kind}.dta"]
    out = []
    for file in files:
        for name, args in reads:
            out.append({"name": f"{file.replace('.', '_')}__{name}", "file": file, "args": args})
    for name, args in reads[:2] + reads[4:6]:
        if "columns" not in args:
            out.append({"name": f"other_parquet__{name}", "file": "other.parquet", "args": args})
    return out


def read(file, args):
    reader = dk.read_dta if file.endswith(".dta") else dk.read_parquet
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        return reader(path(file), **args)


if MODE == "fixtures":
    os.makedirs(DIR, exist_ok=True)
    df, meta = fixture()
    dk.save_parquet(parquet_only(df), path("fixture.parquet"), meta=meta)
    # A .dta file cannot label `.`: only the Parquet file does.
    meta = meta.copy()
    del meta.value_labels["scorelab"]["."]
    dk.save_dta(df, path("fixture.dta"), meta=meta)
    other_parquet(path("other.parquet"))
    with open(path("cases.json"), "w", encoding="utf-8") as f:
        json.dump(cases(), f, indent=1)
    print("Python wrote the fixtures and", len(cases()), "cases in", DIR)
    sys.exit(0)

if MODE == "save":
    for src in ("fixture.parquet", "fixture.dta"):
        for kind, factors in (("", False), ("_factors", True)):
            df, meta = read(src, {"factors": factors})
            out = path(f"saved_python{kind}.{src.split('.')[1]}")
            (dk.save_dta if src.endswith(".dta") else dk.save_parquet)(df, out, meta=meta)
    print("Python saved what it read in", DIR)
    sys.exit(0)


# ---------------------------------------------------------------- dump

def code_of(k):
    """A value label's code: a number, or ".", ".a" ... ".z"."""
    if isinstance(k, str):
        return k
    return float(k)


def meta_json(meta):
    return {
        "label": meta.label,
        "notes": list(meta.notes),
        "characteristics": meta.characteristics,
        "sort": list(meta.sort),
        "timestamp": meta.timestamp,
        "columns": [{"name": n, "label": c.label, "format": c.format, "value_labels": c.value_labels,
                     "ordered": c.ordered} for n, c in meta.columns.items()],
        "value_labels": [{"set": s, "code": code_of(k), "text": v}
                         for s, table in meta.value_labels.items() for k, v in table.items()],
        "rows": meta.rows,
        "storage": {k: str(v) for k, v in meta._storage.items()},
    }


if MODE == "dump":
    os.makedirs(path("python"), exist_ok=True)
    with open(path("cases.json"), encoding="utf-8") as f:
        todo = json.load(f)
    for case in todo:
        out = path("python", case["name"])
        try:
            df, meta = read(case["file"], case["args"])
        except Exception as e:  # noqa: BLE001
            with open(out + ".json", "w", encoding="utf-8") as f:
                json.dump({"error": str(e)}, f)
            continue
        df.write_ipc(out + ".arrow", compression="uncompressed")
        with open(out + ".json", "w", encoding="utf-8") as f:
            json.dump(meta_json(meta), f, indent=1, ensure_ascii=False)
    print("Python dumped", len(todo), "reads in", path("python"))
    sys.exit(0)

if MODE != "compare":
    sys.exit(f"the mode is fixtures, save, dump or compare, not {MODE}")


# ---------------------------------------------------------------- compare

failures = []
counts = {"cases": 0, "errors": 0, "columns": 0, "cells": 0, "fields": 0}


def fail(case, what):
    failures.append(f"{case}: {what}")


def cell_values(s):
    """The valid cells of a Series in a form to compare exactly."""
    valid = s.filter(s.is_not_null())
    if s.dtype == pl.Float64:
        return valid.reinterpret(dtype=pl.UInt64).to_list()
    if s.dtype == pl.Float32:
        return valid.reinterpret(dtype=pl.UInt32).to_list()
    if s.dtype.is_temporal():
        return valid.to_physical().to_list()
    if isinstance(s.dtype, (pl.Enum, pl.Categorical)):
        return valid.cast(pl.String).to_list()
    if isinstance(s.dtype, pl.Decimal):
        return [str(v) for v in valid.to_list()]
    return valid.to_list()


def same_code(a, b):
    if isinstance(a, str) or isinstance(b, str):
        return a == b
    return float(a) == float(b) or (math.isnan(float(a)) and math.isnan(float(b)))


def compare_meta(case, r, p):
    for field in ("label", "notes", "characteristics", "sort", "timestamp", "columns", "rows", "storage"):
        counts["fields"] += 1
        if r[field] != p[field]:
            fail(case, f"meta {field}: R {r[field]!r}, Python {p[field]!r}")
    counts["fields"] += 1
    rv, pv = r["value_labels"], p["value_labels"]
    ok = len(rv) == len(pv) and all(
        a["set"] == b["set"] and a["text"] == b["text"] and same_code(a["code"], b["code"]) for a, b in zip(rv, pv))
    if not ok:
        fail(case, f"meta value_labels: R {rv!r}, Python {pv!r}")


def compare_case(case):
    name = case["name"]
    with open(path("r", name + ".json"), encoding="utf-8") as f:
        rm = json.load(f)
    with open(path("python", name + ".json"), encoding="utf-8") as f:
        pm = json.load(f)
    counts["cases"] += 1
    if "error" in rm or "error" in pm:
        if not ("error" in rm and "error" in pm):
            fail(name, f"one language failed: R {rm.get('error')!r}, Python {pm.get('error')!r}")
        else:
            counts["errors"] += 1
        return
    r = pl.read_ipc(path("r", name + ".arrow"))
    p = pl.read_ipc(path("python", name + ".arrow"))
    if r.columns != p.columns:
        fail(name, f"columns: R {r.columns}, Python {p.columns}")
        return
    if r.height != p.height:
        fail(name, f"rows: R {r.height}, Python {p.height}")
        return
    for c in r.columns:
        counts["columns"] += 1
        a, b = r[c], p[c]
        if a.dtype != b.dtype:
            fail(name, f"{c}: dtype R {a.dtype!r}, Python {b.dtype!r}")
            continue
        if a.is_null().to_list() != b.is_null().to_list():
            fail(name, f"{c}: nulls R {a.is_null().to_list()}, Python {b.is_null().to_list()}")
            continue
        va, vb = cell_values(a), cell_values(b)
        counts["cells"] += len(va)
        if va != vb:
            rows = [i for i, (x, y) in enumerate(zip(va, vb)) if x != y]
            fail(name, f"{c}: valid cells differ at {rows[:5]}: R {va}, Python {vb}")
    compare_meta(name, rm, pm)


with open(path("cases.json"), encoding="utf-8") as f:
    todo = json.load(f)
for case in todo:
    compare_case(case)
print(f"Compared {counts['cases']} reads made by R and by Python ({counts['errors']} failing in both): "
      f"{counts['columns']} columns, {counts['cells']} valid cells, {counts['fields']} metadata fields; "
      f"polars {pl.__version__} in Python")
if failures:
    print(f"FAILED: {len(failures)} differences")
    for f_ in failures:
        print("  ", f_)
    sys.exit(1)
print("no differences")
