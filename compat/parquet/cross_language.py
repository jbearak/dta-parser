"""Files going between the languages' datakits (plan 0019, "Across
languages"). Python's half:

    python compat/parquet/cross_language.py write DIR   # writes DIR/from_python*.parquet
    python compat/parquet/cross_language.py check DIR   # reads DIR/from_r.parquet, DIR/from_julia.parquet

compat/parquet/cross_language.sh runs every language's halves in turn.
The values are the literal data cross_language.R and cross_language.jl
use, so each side checks the other's file cell by cell: the value, the
missing code (`.` or which of `.a` to `.z`), and the labels, formats and
value labels. Python's letters are in DtaArray columns (ADR 0040), so
its date, timestamp and categorical holding letters are written as
Stata's numbers, as Julia writes them. `factors` levels are compared with R's: R writes the levels and values
its `read_parquet(factors = TRUE)` gives for its file and for Python's
(DIR/factors_r.json), and Python checks its own against them. Exits
with status 1 if a check fails.

Needs dta_parser and datakit installed (pip install ./python
./python/datakit).
"""

import datetime as dt
import json
import os
import sys
import warnings

import numpy as np
import pandas as pd

import datakit as dk
from dta_parser import DtaArray

MODE, DIR = sys.argv[1], sys.argv[2]
os.makedirs(DIR, exist_ok=True)
NY = "America/New_York"
NA = dk.tagged_na
MS1960 = 3653 * 86_400_000


def stamps(seconds, zone):
    us = pd.Series([None if s is None else round(s * 1_000_000) for s in seconds], dtype="Int64")
    t = pd.Series(us.to_numpy(dtype="int64", na_value=np.iinfo(np.int64).min).view("datetime64[us]"))
    return t.dt.tz_localize("UTC").dt.tz_convert(zone) if zone else t


def dta(values, storage="double"):
    return pd.Series(values, dtype=f"dta[{storage}]")


if MODE == "write":
    df = pd.DataFrame({
        "id": np.arange(1, 7, dtype=np.int32),
        "score": dta([1.5, None, NA(".a"), -2.25, NA(".z"), 2.0**1000]),
        # Columns holding letters are DtaArrays of their storage type, as
        # a read of a byte, long or float column gives them.
        "small": dta([1.0, 0.0, NA(".d"), 100.0, -127.0, None], "byte"),
        "long": dta([2147483620.0, -2147483647.0, NA(".b"), 0.0, None, 7.0], "long"),
        "fl": dta([0.5, NA(".c"), 3.25, None, -1.0, 2.0], "float"),
        "count": dta([3, None, 0, -5, 2147483647, 1], "long"),
        "word": ["a", None, "", "été", "x y", "z"],
        "region": pd.Categorical(["N", "S", None, "N", "E", "S"], categories=["S", "N", "E", "W"]),
        "day": pd.Series(["2024-03-01", None, "1960-01-01", "1900-02-28", "2100-12-31", "1970-01-01"],
                         dtype="datetime64[s]"),
        "when": stamps([0, 1709285400.25, None, -1, 86400, 1e9], NY),
        # A date and a timestamp holding letters: no datetime64 can hold
        # them, so they are Stata's days and milliseconds since 1960,
        # with %td and %tc, as a read gives them.
        "seen": dta([23436.0, NA(".d"), 23437.0, None, 0.0, NA(".z")]),
        "stamp": dta([MS1960 + 500.0, NA(".k"), MS1960 + 1e12, None, MS1960 - 86_400_250.0,
                      1_000_001 / 1000 + MS1960]),
        # For factors: two codes sharing a text, and numbers as R writes them.
        "dup": dta([1, 2, 3, 1, 5, None], "byte"),
        "w": [0.5, 2.0, 100000.0, None, 1e-4, 3.0],
        # A categorical holding letters (plan 0022): a category cannot
        # hold them, so it is its level numbers with its set, as a read
        # gives it.
        "grade": dta([1.0, NA(".a"), 3.0, None, NA(".z"), 2.0]),
    })
    meta = dk.Meta(
        label="From Python", notes=["A note from Python."],
        columns={c: dk.Column() for c in df.columns},
        value_labels={"scorelab": {1.5: "Low", ".a": "Refused", ".z": "Other"},
                      "yn": {0: "No", 1: "Yes", ".d": "Don't know"},
                      "dupl": {1: "Yes", 2: "No", 3: "Yes"}, "wl": {3: "three"},
                      "grade": {1: "low", 2: "mid", 3: "high"}},
        rows=6,
    )
    meta.columns["score"] = dk.Column("A score", "%9.2f", "scorelab")
    meta.columns["small"] = dk.Column(value_labels="yn")
    meta.columns["long"].label = "A long"
    meta.columns["count"].label = "A count"
    meta.columns["day"].format = "%tdCCYY-NN-DD"
    meta.columns["dup"].value_labels = "dupl"
    meta.columns["w"].value_labels = "wl"
    meta.columns["seen"].format = "%td"
    meta.columns["stamp"].format = "%tc"
    meta.columns["grade"] = dk.Column(value_labels="grade")
    dk.save_parquet(df, os.path.join(DIR, "from_python.parquet"), meta=meta)
    print("Python wrote", os.path.join(DIR, "from_python.parquet"))
    sys.exit(0)

if MODE != "check":
    sys.exit(f"the mode is check or write, not {MODE}")

failures = []
checked = [0]


def check(ok, what):
    checked[0] += 1
    if not ok:
        failures.append(what)


def cells(df, meta, name, values, codes):
    """Every row: the same missing code (0 none, 1 `.`, 2 to 27 `.a` to
    `.z`), and the same value where there is none. A column with a
    missing value is a DtaArray, its codes beside its values."""
    s = df[name]
    if isinstance(s.array, DtaArray):
        got, got_codes = s.array._values.tolist(), s.array.codes.tolist()
    else:
        got = s.tolist()
        got_codes = [1 if pd.isna(v) else 0 for v in got]
    check(len(got) == len(codes), f"{name}: length")
    for i, (v, code) in enumerate(zip(got, got_codes)):
        check(code == codes[i], f"{name} row {i + 1}: code {code}, not {codes[i]}")
        if codes[i] == 0:
            check(v == values[i], f"{name} row {i + 1}: {v!r}, not {values[i]!r}")


def storage(s):
    return s.dtype.storage if isinstance(s.array, DtaArray) else None


def dates(s):
    return [None if pd.isna(v) else v.date() for v in s]


def epoch(s, unit):
    """A datetime column's counts of `unit` since 1970, None for NaT."""
    ints = s.dt.as_unit(unit).array.asi8
    return [None if n else int(v) for v, n in zip(ints, s.isna())]


def texts(s):
    return [None if pd.isna(v) else v for v in s.astype(object)]


def errors(fn, *args, **kw):
    try:
        fn(*args, **kw)
    except Exception as e:  # noqa: BLE001
        return str(e)
    return ""


# ---------------------------------------------------------------- R's file

path = os.path.join(DIR, "from_r.parquet")
# R's exactness edges: a Date with a fraction of a day, and a POSIXct no
# whole number of microseconds gives back, are errors naming the column,
# the row and timestamps="truncate"; with it, truncated.
e = errors(dk.read_parquet, path, columns=["dayfrac"])
check('column "dayfrac", row 1: the date 19000.5' in e and 'timestamps="truncate"' in e, f"dayfrac: the error ({e})")
e = errors(dk.read_parquet, path, columns=["whenfrac"])
check('column "whenfrac", row 1: the timestamp 1.0000001' in e and 'timestamps="truncate"' in e,
      f"whenfrac: the error ({e})")
plain, _ = dk.read_parquet(path, timestamps="truncate", letters=False)
check((storage(plain["small"]), storage(plain["long"]), storage(plain["fl"])) == ("byte", "long", "float")
      and (plain["small"].array.codes <= 1).all(), "letters=False: the storage types, letters as .")
df, meta = dk.read_parquet(path, timestamps="truncate")
check(meta.label == "From R", "data label")
check(meta.notes == ["First note.", "Second note."], "notes")
check(df["id"].dtype == np.int32 and df["id"].tolist() == [1, 2, 3, 4, 5, 6], "id")
cells(df, meta, "score", [1.5, 0, 0, -2.25, 0, 2.0**1000], [0, 1, 2, 0, 27, 0])
check(meta.columns["score"] == dk.Column("A score", "%9.2f", "scorelab"), "score: label, format, set")
check(meta.value_labels["scorelab"] == {1.5: "Low", ".a": "Refused", ".z": "Other"}, "score: labels")
check(storage(df["small"]) == "byte", "small: dta[byte]")
cells(df, meta, "small", [1, 0, 0, 100, -127, 0], [0, 0, 5, 0, 0, 1])
check(meta.labels("small") == {0: "No", 1: "Yes", ".d": "Don't know"}, "small: labels")
check(storage(df["long"]) == "long", "long: dta[long]")
cells(df, meta, "long", [2147483620, -2147483647, 0, 0, 0, 7], [0, 0, 3, 0, 1, 0])
check(meta.columns["long"].label == "A long", "long: label")
check(storage(df["fl"]) == "float", "fl: dta[float]")
cells(df, meta, "fl", [0.5, 0, 3.25, 0, -1.0, 2.0], [0, 4, 0, 1, 0, 0])
check(storage(df["count"]) == "long", "count: dta[long]")
cells(df, meta, "count", [3, 0, 0, -5, 2147483647, 1], [0, 1, 0, 0, 0, 0])
check(meta.columns["count"].label == "A count", "count: label")
check(texts(df["word"]) == ["a", None, "", "été", "x y", "z"], "word")
check(df["region"].cat.categories.tolist() == ["S", "N", "E", "W"], "region: levels")
check(texts(df["region"]) == ["N", "S", None, "N", "E", "S"] and meta.columns["region"].ordered is False
      and not df["region"].cat.ordered, "region: values, not ordered")
check(dates(df["day"]) == [dt.date(2024, 3, 1), None, dt.date(1960, 1, 1), dt.date(1900, 2, 28),
                           dt.date(2100, 12, 31), dt.date(1970, 1, 1)], "day")
check(meta.columns["day"].format == "%tdCCYY-NN-DD", "day: format")
check(str(df["when"].dtype) == f"datetime64[us, {NY}]", "when: zone")
check(epoch(df["when"], "us") == [0, 1_709_285_400_250_000, None, -1_000_000, 86_400_000_000,
                                  1_000_000_000_000_000], "when: instants")
check(df["dayfrac"].dtype == "datetime64[s]" and
      [None if v is None else v // 86400 for v in epoch(df["dayfrac"], "s")] == [19000, 0, None, -2, 1, 2],
      "dayfrac: truncated")
check(epoch(df["whenfrac"], "us") == [1_000_000, 2_000_000, None, 3_500_000, -1, 6_000_000],
      "whenfrac: truncated")

# factors, against the levels and values R's read_parquet(factors = TRUE)
# gives for the same file.
with open(os.path.join(DIR, "factors_r.json"), encoding="utf-8") as f:
    want = json.load(f)
for which, file in (("from_r", "from_r.parquet"), ("from_python", "from_python.parquet")):
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        df, meta = dk.read_parquet(os.path.join(DIR, file), factors=True, timestamps="truncate")
    for name, w in want[which].items():
        got = df[name]
        check(isinstance(got.dtype, pd.CategoricalDtype) and list(got.cat.categories) == w["levels"],
              f"{which} {name}: levels {got.dtype}, not {w['levels']}")
        check(texts(got) == w["values"], f"{which} {name}: values {texts(got)}, not {w['values']}")
    # As in R, a category loses the letters, with a warning naming the column.
    if which == "from_r":
        check(any('"score"' in str(w.message) and "are NaN" in str(w.message) for w in caught),
              "factors: the warning about score's letters")

# ---------------------------------------------------------------- Julia's file

path = os.path.join(DIR, "from_julia.parquet")
if os.path.exists(path):
    df, meta = dk.read_parquet(path)
    check(meta.label == "From Julia" and meta.notes == ["A note from Julia."], "julia: data label and notes")
    check(df["id"].tolist() == [1, 2, 3, 4, 5, 6], "julia: id")
    cells(df, meta, "score", [1.5, 0, 0, -2.25, 0, 2.0**1000], [0, 1, 2, 0, 27, 0])
    check(meta.labels("score") == {1.5: "Low", ".a": "Refused", ".z": "Other"}, "julia: score labels")
    check(meta.columns["score"] == dk.Column("A score", "%9.2f", "scorelab"), "julia: score column")
    cells(df, meta, "small", [1, 0, 0, 100, -127, 0], [0, 0, 5, 0, 0, 1])
    check(meta.labels("small") == {0: "No", 1: "Yes", ".d": "Don't know"}, "julia: small labels")
    cells(df, meta, "long", [2147483620, -2147483647, 0, 0, 0, 7], [0, 0, 3, 0, 1, 0])
    cells(df, meta, "fl", [0.5, 0, 3.25, 0, -1.0, 2.0], [0, 4, 0, 1, 0, 0])
    cells(df, meta, "count", [3, 0, 0, -5, 2147483647, 1], [0, 1, 0, 0, 0, 0])
    check(texts(df["word"]) == ["a", None, "", "été", "x y", "z"], "julia: word")
    check(df["region"].cat.categories.tolist() == ["S", "N", "E", "W"], "julia: region levels")
    check(dates(df["day"])[0] == dt.date(2024, 3, 1) and meta.columns["day"].format == "%tdCCYY-NN-DD",
          "julia: day")
    # Julia writes milliseconds, so they read as datetime64[ms].
    check(str(df["when"].dtype) == f"datetime64[ms, {NY}]" and epoch(df["when"], "ms") ==
          [0, 1_709_285_400_250, None, -1000, 86_400_000, 1_000_000_000_000], "julia: when")
    # Julia's date with letters is Stata's days since 1960, %td.
    cells(df, meta, "seen", [23436.0, 0, 23437.0, 0, 0.0, 0], [0, 5, 0, 1, 0, 27])
    check(meta.columns["seen"].format == "%td", "julia: seen format")
else:
    print("no from_julia.parquet in", DIR, "(run Julia's write first); Julia's file not checked")

# ---------------------------------------------------------------- TypeScript's file

# The same data as Python's own file (plan 0021).
path = os.path.join(DIR, "from_typescript.parquet")
if os.path.exists(path):
    df, meta = dk.read_parquet(path)
    check(meta.label == "From TypeScript" and meta.notes == ["A note from TypeScript."], "ts: data label and notes")
    check(df["id"].dtype == np.int32 and df["id"].tolist() == [1, 2, 3, 4, 5, 6], "ts: id")
    cells(df, meta, "score", [1.5, 0, 0, -2.25, 0, 2.0**1000], [0, 1, 2, 0, 27, 0])
    check(meta.labels("score") == {1.5: "Low", ".a": "Refused", ".z": "Other"}, "ts: score labels")
    check(meta.columns["score"] == dk.Column("A score", "%9.2f", "scorelab"), "ts: score column")
    check(storage(df["small"]) == "byte", "ts: small, dta[byte]")
    cells(df, meta, "small", [1, 0, 0, 100, -127, 0], [0, 0, 5, 0, 0, 1])
    check(meta.labels("small") == {0: "No", 1: "Yes", ".d": "Don't know"}, "ts: small labels")
    check(storage(df["long"]) == "long", "ts: long, dta[long]")
    cells(df, meta, "long", [2147483620, -2147483647, 0, 0, 0, 7], [0, 0, 3, 0, 1, 0])
    check(storage(df["fl"]) == "float", "ts: fl, dta[float]")
    cells(df, meta, "fl", [0.5, 0, 3.25, 0, -1.0, 2.0], [0, 4, 0, 1, 0, 0])
    cells(df, meta, "count", [3, 0, 0, -5, 2147483647, 1], [0, 1, 0, 0, 0, 0])
    check(texts(df["word"]) == ["a", None, "", "été", "x y", "z"], "ts: word")
    check(df["region"].cat.categories.tolist() == ["S", "N", "E", "W"] and
          texts(df["region"]) == ["N", "S", None, "N", "E", "S"], "ts: region")
    check(dates(df["day"]) == [dt.date(2024, 3, 1), None, dt.date(1960, 1, 1), dt.date(1900, 2, 28),
                               dt.date(2100, 12, 31), dt.date(1970, 1, 1)], "ts: day")
    check(meta.columns["day"].format == "%tdCCYY-NN-DD", "ts: day format")
    check(str(df["when"].dtype) == f"datetime64[us, {NY}]" and epoch(df["when"], "us") ==
          [0, 1_709_285_400_250_000, None, -1_000_000, 86_400_000_000, 1_000_000_000_000_000], "ts: when")
    # A date and a timestamp holding letters: Stata's days and
    # milliseconds since 1960, with %td and %tc.
    cells(df, meta, "seen", [23436.0, 0, 23437.0, 0, 0.0, 0], [0, 5, 0, 1, 0, 27])
    check(meta.columns["seen"].format == "%td", "ts: seen format")
    cells(df, meta, "stamp", [MS1960 + 500.0, 0, MS1960 + 1e12, 0, MS1960 - 86_400_250.0, 1_000_001 / 1000 + MS1960],
          [0, 12, 0, 1, 0, 0])
    check(meta.columns["stamp"].format == "%tc", "ts: stamp format")
    cells(df, meta, "dup", [1, 2, 3, 1, 5, 0], [0, 0, 0, 0, 0, 1])
    # A categorical holding letters (plan 0022): its level numbers
    # with the letters, as R and Julia read it, and its set (made by
    # the writer: TypeScript names none).
    cells(df, meta, "grade", [1.0, 0, 3.0, 0, 0, 2.0], [0, 2, 0, 1, 27, 0])
    check(meta.columns["grade"].value_labels == "grade" and
          meta.value_labels["grade"] == {1: "low", 2: "mid", 3: "high"}, "ts: grade set")
else:
    print("no from_typescript.parquet in", DIR, "(run TypeScript's write first); TypeScript's file not checked")

print(f"Python checked {checked[0]} values and labels in R's, Julia's and TypeScript's files")
if failures:
    print("FAILED:")
    for f_ in failures:
        print("  ", f_)
    sys.exit(1)
