"""Files going between the languages' datakits (plan 0019, "Across
languages"). Python's half:

    python compat/parquet/cross_language.py write DIR   # writes DIR/from_python*.parquet
    python compat/parquet/cross_language.py check DIR   # reads DIR/from_r.parquet, DIR/from_julia.parquet

compat/parquet/cross_language.sh runs every language's halves in turn.
The values are the literal data cross_language.R and cross_language.jl
use, so each side checks the other's file cell by cell: the value, the
missing code (`.` or which of `.a` to `.z`), and the labels, formats and
value labels. Python writes its file twice, with the letters taken from
`meta.missing` and from companion columns; R and Julia check both.
`factors` levels are compared with R's: R writes the levels and values
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

import polars as pl

import datakit as dk

MODE, DIR = sys.argv[1], sys.argv[2]
os.makedirs(DIR, exist_ok=True)
NY = "America/New_York"


def L(*v, name):
    return pl.Series(name, list(v), dtype=dk.LETTERS)


def stamps(seconds, zone):
    us = [None if s is None else round(s * 1_000_000) for s in seconds]
    return pl.Series(us, dtype=pl.Int64).cast(pl.Datetime("us")).dt.replace_time_zone("UTC").dt.convert_time_zone(zone) \
        if zone else pl.Series(us, dtype=pl.Int64).cast(pl.Datetime("us"))


if MODE == "write":
    df = pl.DataFrame({
        "id": pl.Series(range(1, 7), dtype=pl.Int32),
        "score": [1.5, None, None, -2.25, None, 2.0**1000],
        "small": pl.Series([1, 0, None, 100, -127, None], dtype=pl.Int8),
        "long": pl.Series([2147483620, -2147483647, None, 0, None, 7], dtype=pl.Int32),
        "fl": pl.Series([0.5, None, 3.25, None, -1, 2], dtype=pl.Float32),
        "count": pl.Series([3, None, 0, -5, 2147483647, 1], dtype=pl.Int32),
        "word": ["a", None, "", "été", "x y", "z"],
        "region": pl.Series(["N", "S", None, "N", "E", "S"], dtype=pl.Enum(["S", "N", "E", "W"])),
        "day": [dt.date(2024, 3, 1), None, dt.date(1960, 1, 1), dt.date(1900, 2, 28), dt.date(2100, 12, 31),
                dt.date(1970, 1, 1)],
        "when": stamps([0, 1709285400.25, None, -1, 86400, 1e9], NY),
        # A date and a timestamp holding letters: written as DOUBLE days
        # and seconds since 1970, with "logical" in the profile.
        "seen": [dt.date(2024, 3, 1), None, dt.date(2024, 3, 2), None, dt.date(1960, 1, 1), None],
        "stamp": stamps([0.5, None, 1e9, None, -86400.25, 1.000001], "UTC"),
        # For factors: two codes sharing a text, and numbers as R writes them.
        "dup": pl.Series([1, 2, 3, 1, 5, None], dtype=pl.Int8),
        "w": [0.5, 2.0, 100000.0, None, 1e-4, 3.0],
    })
    meta = dk.Meta(
        label="From Python", notes=["A note from Python."],
        columns={c: dk.Column() for c in df.columns},
        value_labels={"scorelab": {1.5: "Low", ".a": "Refused", ".z": "Other"},
                      "yn": {0: "No", 1: "Yes", ".d": "Don't know"},
                      "dupl": {1: "Yes", 2: "No", 3: "Yes"}, "wl": {3: "three"}},
        missing={
            "score": L(None, None, ".a", None, ".z", None, name="score"),
            "small": L(None, None, ".d", None, None, None, name="small"),
            "long": L(None, None, ".b", None, None, None, name="long"),
            "fl": L(None, ".c", None, None, None, None, name="fl"),
            "seen": L(None, ".d", None, None, None, ".z", name="seen"),
            "stamp": L(None, ".k", None, None, None, None, name="stamp"),
        },
        rows=6,
    )
    meta.columns["score"] = dk.Column("A score", "%9.2f", "scorelab")
    meta.columns["small"] = dk.Column(value_labels="yn")
    meta.columns["long"].label = "A long"
    meta.columns["count"].label = "A count"
    meta.columns["day"].format = "%tdCCYY-NN-DD"
    meta.columns["dup"].value_labels = "dupl"
    meta.columns["w"].value_labels = "wl"
    dk.save_parquet(df, os.path.join(DIR, "from_python.parquet"), meta=meta)
    companions = meta.copy()
    with_companions = dk.letters_to_columns(df, companions)
    dk.save_parquet(with_companions, os.path.join(DIR, "from_python_columns.parquet"), meta=companions)
    print("Python wrote", os.path.join(DIR, "from_python.parquet"), "and from_python_columns.parquet")
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
    `.z`), and the same value where there is none."""
    s = df[name]
    if name in meta.letter_columns:
        letters = df[meta.letter_columns[name]].to_physical().to_list()
    else:
        letters = meta.letters(name).to_physical().to_list()
    got = s.to_list()
    check(len(got) == len(codes), f"{name}: length")
    for i, (v, l) in enumerate(zip(got, letters)):
        code = 0 if v is not None else (1 if l is None else l + 2)
        check(code == codes[i], f"{name} row {i + 1}: code {code}, not {codes[i]}")
        if codes[i] == 0:
            check(v == values[i] and type(v) is type(values[i]), f"{name} row {i + 1}: {v!r}, not {values[i]!r}")


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
for mode in ("meta", "columns"):
    df, meta = dk.read_parquet(path, timestamps="truncate", letters=mode)
    check(meta.label == "From R", "data label")
    check(meta.notes == ["First note.", "Second note."], "notes")
    check(df["id"].dtype == pl.Int32 and df["id"].to_list() == [1, 2, 3, 4, 5, 6], "id")
    cells(df, meta, "score", [1.5, 0, 0, -2.25, 0, 2.0**1000], [0, 1, 2, 0, 27, 0])
    check(meta.columns["score"] == dk.Column("A score", "%9.2f", "scorelab"), "score: label, format, set")
    check(meta.value_labels["scorelab"] == {1.5: "Low", ".a": "Refused", ".z": "Other"}, "score: labels")
    check(df["small"].dtype == pl.Int8, "small: Int8 (storage byte)")
    cells(df, meta, "small", [1, 0, 0, 100, -127, 0], [0, 0, 5, 0, 0, 1])
    check(meta.labels("small") == {0: "No", 1: "Yes", ".d": "Don't know"}, "small: labels")
    check(df["long"].dtype == pl.Int32, "long: Int32 (storage long)")
    cells(df, meta, "long", [2147483620, -2147483647, 0, 0, 0, 7], [0, 0, 3, 0, 1, 0])
    check(meta.columns["long"].label == "A long", "long: label")
    check(df["fl"].dtype == pl.Float32, "fl: Float32")
    cells(df, meta, "fl", [0.5, 0, 3.25, 0, -1.0, 2.0], [0, 4, 0, 1, 0, 0])
    check(df["count"].dtype == pl.Int32, "count: Int32")
    cells(df, meta, "count", [3, 0, 0, -5, 2147483647, 1], [0, 1, 0, 0, 0, 0])
    check(meta.columns["count"].label == "A count", "count: label")
    check(df["word"].to_list() == ["a", None, "", "été", "x y", "z"], "word")
    check(df["region"].dtype == pl.Enum(["S", "N", "E", "W"]), "region: levels")
    check(df["region"].to_list() == ["N", "S", None, "N", "E", "S"] and meta.columns["region"].ordered is False,
          "region: values, not ordered")
    check(df["day"].to_list() == [dt.date(2024, 3, 1), None, dt.date(1960, 1, 1), dt.date(1900, 2, 28),
                                  dt.date(2100, 12, 31), dt.date(1970, 1, 1)], "day")
    check(meta.columns["day"].format == "%tdCCYY-NN-DD", "day: format")
    check(df["when"].dtype == pl.Datetime("us", NY), "when: zone")
    check(df["when"].dt.epoch("us").to_list() == [0, 1_709_285_400_250_000, None, -1_000_000, 86_400_000_000,
                                                 1_000_000_000_000_000], "when: instants")
    check(df["dayfrac"].dtype == pl.Date and df["dayfrac"].to_physical().to_list() == [19000, 0, None, -2, 1, 2],
          "dayfrac: truncated")
    check(df["whenfrac"].dt.epoch("us").to_list() == [1_000_000, 2_000_000, None, 3_500_000, -1, 6_000_000],
          "whenfrac: truncated")

# factors, against the levels and values R's read_parquet(factors = TRUE)
# gives for the same file.
with open(os.path.join(DIR, "factors_r.json"), encoding="utf-8") as f:
    want = json.load(f)
for which, file in (("from_r", "from_r.parquet"), ("from_python", "from_python.parquet")):
    df, meta = dk.read_parquet(os.path.join(DIR, file), factors=True, timestamps="truncate")
    for name, w in want[which].items():
        got = df[name]
        check(isinstance(got.dtype, pl.Enum) and list(got.dtype.categories) == w["levels"],
              f"{which} {name}: levels {got.dtype}, not {w['levels']}")
        check(got.cast(pl.String).to_list() == w["values"], f"{which} {name}: values {got.to_list()}, not {w['values']}")
    # The letters are not lost.
    if which == "from_r":
        check(meta.missing["score"].to_list() == [None, None, ".a", None, ".z", None], "factors: score's letters")

# ---------------------------------------------------------------- Julia's file

path = os.path.join(DIR, "from_julia.parquet")
if os.path.exists(path):
    for mode in ("meta", "columns"):
        df, meta = dk.read_parquet(path, letters=mode)
        check(meta.label == "From Julia" and meta.notes == ["A note from Julia."], "julia: data label and notes")
        check(df["id"].to_list() == [1, 2, 3, 4, 5, 6], "julia: id")
        cells(df, meta, "score", [1.5, 0, 0, -2.25, 0, 2.0**1000], [0, 1, 2, 0, 27, 0])
        check(meta.labels("score") == {1.5: "Low", ".a": "Refused", ".z": "Other"}, "julia: score labels")
        check(meta.columns["score"] == dk.Column("A score", "%9.2f", "scorelab"), "julia: score column")
        cells(df, meta, "small", [1, 0, 0, 100, -127, 0], [0, 0, 5, 0, 0, 1])
        check(meta.labels("small") == {0: "No", 1: "Yes", ".d": "Don't know"}, "julia: small labels")
        cells(df, meta, "long", [2147483620, -2147483647, 0, 0, 0, 7], [0, 0, 3, 0, 1, 0])
        cells(df, meta, "fl", [0.5, 0, 3.25, 0, -1.0, 2.0], [0, 4, 0, 1, 0, 0])
        cells(df, meta, "count", [3, 0, 0, -5, 2147483647, 1], [0, 1, 0, 0, 0, 0])
        check(df["word"].to_list() == ["a", None, "", "été", "x y", "z"], "julia: word")
        check(df["region"].dtype == pl.Enum(["S", "N", "E", "W"]), "julia: region levels")
        check(df["day"].to_list()[0] == dt.date(2024, 3, 1) and meta.columns["day"].format == "%tdCCYY-NN-DD",
              "julia: day")
        # Julia writes milliseconds, so they read as Datetime("ms").
        check(df["when"].dtype == pl.Datetime("ms", NY) and df["when"].dt.epoch("ms").to_list() ==
              [0, 1_709_285_400_250, None, -1000, 86_400_000, 1_000_000_000_000], "julia: when")
        # Julia's date with letters is Stata's days since 1960, %td.
        cells(df, meta, "seen", [23436.0, 0, 23437.0, 0, 0.0, 0], [0, 5, 0, 1, 0, 27])
        check(meta.columns["seen"].format == "%td", "julia: seen format")
else:
    print("no from_julia.parquet in", DIR, "(run Julia's write first); Julia's file not checked")

print(f"Python checked {checked[0]} values and labels in R's and Julia's files")
if failures:
    print("FAILED:")
    for f_ in failures:
        print("  ", f_)
    sys.exit(1)
