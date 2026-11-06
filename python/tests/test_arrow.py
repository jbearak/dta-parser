"""dta_parser's native Arrow functions for datakit (plan 0019, PR 2a):
Parquet and .dta read into Arrow memory polars adopts, written from
polars' own export, and the digests of finished columns. They are
internal (datakit is their only caller), so these tests drive them
directly, as datakit will.

Expected values come from dta_parser's pandas readers (themselves tested
against haven, pandas and ReadStat) and from polars and pyarrow.
"""

import datetime as dt
import gc
import io
import math
import os
import struct
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

pl = pytest.importorskip("polars")
pa = pytest.importorskip("pyarrow")
pq = pytest.importorskip("pyarrow.parquet")

import dta_parser as dp  # noqa: E402
from dta_parser import _native as native  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
DTA = sorted((ROOT / "compat" / "fixtures").glob("*.dta"))
PARQUET = sorted((ROOT / "compat" / "parquet" / "fixtures").glob("*.parquet"))
LETTERS = pl.Enum([f".{chr(c)}" for c in range(ord("a"), ord("z") + 1)])
EPOCH = dt.date(1960, 1, 1)


def read_parquet(source, **kw):
    frame, letters, meta = native.parquet_read_arrow(source, **kw)
    return pl.DataFrame(frame), (None if letters is None else pl.DataFrame(letters)), meta


def read_dta(path, **kw):
    frame, letters, meta = native.dta_read_arrow(str(path), **kw)
    return pl.DataFrame(frame), (None if letters is None else pl.DataFrame(letters)), meta


def test_the_abi_version_is_there():
    assert native.ABI_VERSION == 1


# ---------------------------------------------------------------- .dta


def cells_ours(df, letters, name):
    """Per row: ("v", value) or ("m", missing code)."""
    s = df[name]
    lt = letters[name].to_list() if letters is not None and name in letters.columns else None
    out = []
    for i, v in enumerate(s.to_list()):
        if v is None:
            code = 1 if lt is None or lt[i] is None else ord(lt[i][1]) - ord("a") + 2
            out.append(("m", code))
        else:
            out.append(("v", v))
    return out


def cells_pandas(series):
    arr = series.array
    if isinstance(series.dtype, dp.StataDtype):
        return [("m", int(c)) if c else ("v", v) for v, c in zip(arr._values, arr._codes)]
    out = []
    for v in series.to_numpy(dtype=object):
        if v is None or (isinstance(v, float) and math.isnan(v)) or v is pd.NaT or (isinstance(v, np.datetime64) and np.isnat(v)):
            out.append(("m", 1))
        else:
            out.append(("v", v))
    return out


def same_cell(ours, theirs, kind, numbers_as):
    if ours[0] != theirs[0]:
        return False
    if ours[0] == "m":
        return ours[1] == theirs[1]
    a, b = ours[1], theirs[1]
    if kind == "Date":
        if numbers_as:  # dta_parser kept the number (a fraction): truncated days
            return (a - EPOCH).days == math.floor(float(b))
        return pd.Timestamp(b) == pd.Timestamp(a)
    if kind == "Datetime":
        if numbers_as:
            return int((pd.Timestamp(a) - pd.Timestamp(EPOCH)) / pd.Timedelta(milliseconds=1)) == math.floor(float(b))
        return pd.Timestamp(b) == pd.Timestamp(a)
    if isinstance(a, bytes):
        return a == (b if isinstance(b, bytes) else str(b).encode())
    if isinstance(a, float):
        return struct.pack("<d", a) == struct.pack("<d", float(b)) or (math.isnan(a) and math.isnan(float(b)))
    return a == b


def compare_dta(path, timestamps="error", skip=0, n_max=None):
    ours, letters, meta = read_dta(path, skip=skip, n_max=n_max, timestamps=timestamps)
    theirs = dp.read_dta(path, skip=skip, n_max=n_max)
    assert ours.columns == list(theirs.columns)
    assert ours.height == len(theirs)
    for name in ours.columns:
        dtype = ours[name].dtype
        kind = "Date" if dtype == pl.Date else "Datetime" if isinstance(dtype, pl.Datetime) else None
        numbers_as = kind is not None and theirs[name].dtype.kind not in "M"
        o, t = cells_ours(ours, letters, name), cells_pandas(theirs[name])
        for i, (a, b) in enumerate(zip(o, t)):
            assert same_cell(a, b, kind, numbers_as), f"{path.name if hasattr(path, 'name') else path} {name} row {i}: {a} vs {b}"
    info = dp.read_meta(path) if skip == 0 and n_max is None else None
    if info is not None:
        cols = {c[0]: c for c in meta["columns"]}
        for name, c in info["columns"].items():
            assert (cols[name][1] or "") == c["label"]
            assert (cols[name][2] or "") == c["format"]
            assert (cols[name][3] or "") == c["value_labels"]
        assert meta["value_labels"] == info["value_labels"] | {} or meta["value_labels"].keys() == info["value_labels"].keys()
        assert meta["notes"] == info["notes"]
        assert meta["sort"] == info["sort_order"]
    return ours, letters, meta


@pytest.mark.parametrize("path", DTA, ids=lambda p: p.stem)
def test_dta_reads_as_read_dta_reads_it(path):
    compare_dta(path)
    n = dp.read_meta(path)["nobs"]
    compare_dta(path, skip=n // 2, n_max=3)


def missing_value(code):
    return dp.missing.from_code(code)


@pytest.fixture(scope="module")
def made_dta(tmp_path_factory):
    """A file with letters in every numeric type, dates and datetimes
    (whole and with fractions), long text and a strL mixing text and
    bytes, written by dta_parser.write_dta from data made here."""
    d = tmp_path_factory.mktemp("dta")
    n = 40
    df = pd.DataFrame({
        "b": dp.StataArray([i % 50 for i in range(n)], codes=[2 if i % 7 == 1 else 1 if i % 5 == 0 else 0 for i in range(n)], storage="byte"),
        "i": dp.StataArray([i * 300 for i in range(n)], codes=[27 if i % 9 == 2 else 0 for i in range(n)], storage="int"),
        "l": dp.StataArray([i * 100_000 for i in range(n)], codes=[3 if i % 4 == 3 else 0 for i in range(n)], storage="long"),
        "f": dp.StataArray([i / 4 for i in range(n)], codes=[4 if i == 6 else 0 for i in range(n)], storage="float"),
        "d": dp.StataArray([i / 3 for i in range(n)], codes=[5 if i == 8 else 0 for i in range(n)], storage="double"),
        "day": pd.to_datetime([dt.date(2000, 1, 1) + dt.timedelta(days=i * 37) for i in range(n)]),
        "when": pd.to_datetime([dt.datetime(1950, 1, 1) + dt.timedelta(milliseconds=i * 123_456_789) for i in range(n)]),
        "s": ["short" if i % 2 else f"a value longer than twelve bytes {i}" for i in range(n)],
        "mixed": [b"\x00\x01binary" if i % 3 == 0 else f"text {i}" for i in range(n)],
        "frac": [1.5 + i for i in range(n)],
    })
    df.attrs["dta"] = {"columns": {"frac": {"format": "%td", "storage": "double"}}, "notes": ["one", "two"],
                       "value_labels": {"lab": {1: "one", missing_value(2): "refused"}}}
    df.attrs["dta"]["columns"]["b"] = {"value_labels": "lab", "label": "small", "storage": "byte"}
    path = d / "made.dta"
    dp.write_dta(df, path)
    return path


def test_letters_dates_and_mixed_strls(made_dta):
    with pytest.raises(ValueError, match=r'column "frac", row 1: .*fraction of a day.*timestamps="truncate"'):
        read_dta(made_dta)
    ours, letters, meta = compare_dta(made_dta, timestamps="truncate")
    assert ours["day"].dtype == pl.Date
    assert ours["when"].dtype == pl.Datetime("ms")
    # A strL mixing text and bytes is Binary, the text as its UTF-8.
    assert ours["mixed"].dtype == pl.Binary
    assert ours["mixed"][1] == b"text 1"
    assert ours["s"].dtype == pl.String
    assert set(letters.columns) == {"b", "i", "l", "f", "d"}
    assert all(letters[c].dtype == LETTERS for c in letters.columns)
    assert meta["letter_columns"] == ["b", "i", "l", "f", "d"]
    assert meta["notes"] == ["one", "two"]
    assert meta["value_labels"]["lab"] == {1: "one", ".a": "refused"}
    cols = {c[0]: c for c in meta["columns"]}
    assert cols["b"][1:4] == ("small", None, "lab") or cols["b"][1] == "small"
    # Windows with and without letters.
    w, wl, _ = read_dta(made_dta, columns=["b", "day"], skip=2, n_max=3, timestamps="truncate")
    assert w.columns == ["b", "day"] and w.height == 3
    assert wl is None or wl.columns == ["b"]


def test_datetimes_out_of_range_are_errors_in_both_modes(tmp_path):
    df = pd.DataFrame({"t": [1e19, 0.0]})
    df.attrs["dta"] = {"columns": {"t": {"format": "%tc", "storage": "double"}}}
    p = tmp_path / "far.dta"
    dp.write_dta(df, p)
    for mode in ("error", "truncate"):
        with pytest.raises(ValueError, match="outside polars' Datetime range"):
            read_dta(p, timestamps=mode)


def write_dta_arrow(df, path, meta=None, **kw):
    native.dta_write_arrow(df, str(path), meta, **kw)


def test_save_dta_reads_back_with_read_dta(tmp_path):
    n = 30
    df = pl.DataFrame({
        "i8": pl.Series([i - 10 if i % 6 else None for i in range(n)], dtype=pl.Int8),
        "big8": pl.Series([127 - i for i in range(n)], dtype=pl.Int8),
        "i64": pl.Series([i * 10**6 for i in range(n)], dtype=pl.Int64),
        "f": pl.Series([i / 8 if i % 5 else None for i in range(n)], dtype=pl.Float32),
        "g": pl.Series([float("nan") if i == 3 else i / 7 for i in range(n)]),
        "b": [i % 2 == 0 for i in range(n)],
        "s": [None if i % 4 == 0 else f"text {i}" for i in range(n)],
        "day": [dt.date(2001, 2, 3) + dt.timedelta(days=i) for i in range(n)],
        "when": pl.Series([dt.datetime(2020, 1, 1) + dt.timedelta(milliseconds=i) for i in range(n)]).cast(pl.Datetime("us")),
        "e": pl.Series([["no", "yes"][i % 2] if i % 7 else None for i in range(n)], dtype=pl.Enum(["yes", "no"])),
    })
    meta = {
        "label": "made here", "notes": ["n1"], "sort": [], "timestamp": None, "characteristics": {"i8": {"note": "x"}},
        "columns": {"i8": ("small", "%9.0g", "lab", None)}, "value_labels": {"lab": {1: "one", ".b": "b"}},
        "missing": {"i8": pl.Series([".b" if i % 12 == 0 else None for i in range(n)], dtype=LETTERS),
                    "e": pl.Series([".a" if i % 7 == 0 else None for i in range(n)], dtype=LETTERS)},
    }
    p = tmp_path / "w.dta"
    write_dta_arrow(df, p, meta)
    back = dp.read_dta(p)
    info = back.attrs["dta"]
    assert info["label"] == "made here" and info["notes"] == ["n1"]
    assert info["columns"]["i8"]["storage"] == "byte" and info["columns"]["big8"]["storage"] == "int"
    assert info["columns"]["i64"]["storage"] == "long" and info["columns"]["f"]["storage"] == "float"
    assert info["columns"]["e"]["storage"] == "long" and info["value_labels"]["e"] == {1: "yes", 2: "no"}
    assert info["value_labels"]["lab"][missing_value(3)] == "b"
    codes = back["i8"].array._codes
    assert [int(c) for c in codes[:13]] == [3, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 3]
    assert [int(c) for c in back["e"].array._codes[:8]] == [2, 0, 0, 0, 0, 0, 0, 2]
    # As encode: "yes" is 1 and "no" 2, the Enum's order.
    assert list(back["e"].array._values[1:3]) == [1, 2]
    assert back["day"][0] == pd.Timestamp("2001-02-03")
    assert back["when"][1] == pd.Timestamp("2020-01-01 00:00:00.001")
    assert back["s"][1] == "text 1" and back["s"][0] == ""
    assert math.isnan(back["g"][3])
    # And our own reader gives the frame back.
    ours, letters, _ = read_dta(p)
    assert ours["e"].to_list()[1:3] == [1, 2]
    assert letters["i8"].to_list()[0] == ".b"


def test_save_dta_refuses_what_dta_cannot_hold(tmp_path):
    p = tmp_path / "x.dta"
    for df, match in [
        (pl.DataFrame({"t": [dt.time(1, 2)]}), "Time"),
        (pl.DataFrame({"x": pl.Series([2**60], dtype=pl.Int64)}), "beyond ±2\\^53"),
        # Just past, where the value as a double rounds to 2^53.
        (pl.DataFrame({"x": pl.Series([2**53 + 1], dtype=pl.Int64)}), "beyond ±2\\^53"),
        (pl.DataFrame({"x": pl.Series([2**53 + 1], dtype=pl.UInt64)}), "beyond ±2\\^53"),
        (pl.DataFrame({"when": pl.Series([2**53 + 1 - 3653 * 86_400_000], dtype=pl.Int64).cast(pl.Datetime("ms"))}), "too far from 1960"),
        (pl.DataFrame({"when": pl.Series([dt.datetime(2020, 1, 1)]).dt.replace_time_zone("UTC")}), "time zone"),
        (pl.DataFrame({"1bad": [1]}), "not a name Stata can hold"),
    ]:
        with pytest.raises((TypeError, ValueError), match=match):
            write_dta_arrow(df, p)
    ns = pl.DataFrame({"when": (pl.Series([dt.datetime(2020, 1, 1)]).cast(pl.Datetime("ns")).cast(pl.Int64) + 1000).cast(pl.Datetime("ns"))})
    with pytest.raises(ValueError, match="whole number of milliseconds"):
        write_dta_arrow(ns, p)
    write_dta_arrow(ns, p, timestamps="truncate")
    assert dp.read_dta(p)["when"][0] == pd.Timestamp("2020-01-01")


# ---------------------------------------------------------------- Parquet


@pytest.mark.parametrize("path", [p for p in PARQUET if "nested" not in p.stem], ids=lambda p: p.stem)
def test_parquet_reads_as_polars_reads_it(path):
    ours, _, _ = read_parquet(str(path))
    for name in ours.columns:
        try:
            b = pl.read_parquet(path, columns=[name])[name]
        except pl.exceptions.PolarsError:
            continue  # a column polars cannot read (BYTE_STREAM_SPLIT bytes, DECIMAL past 38 digits)
        a = ours[name]
        if isinstance(b.dtype, pl.Categorical) or isinstance(a.dtype, (pl.Enum, pl.Categorical)):
            a, b = a.cast(pl.String), b.cast(pl.String)
        elif isinstance(b.dtype, pl.Decimal) or a.dtype == pl.String and b.dtype != pl.String:
            continue  # DECIMAL reads as text for datakit to cast
        elif a.dtype != b.dtype:
            a = a.cast(b.dtype)
        assert a.equals(b, null_equal=True), f"{path.stem} {name}: {a.dtype} vs {b.dtype}"


def test_parquet_windows_and_columns():
    path = next(p for p in PARQUET if p.stem == "pyarrow_small_pages")
    whole, _, _ = read_parquet(str(path))
    for skip, n in [(0, 5), (7, 100), (whole.height - 3, 10)]:
        part, _, meta = read_parquet(str(path), skip=skip, n_max=n)
        assert part.equals(whole.slice(skip, n))
        assert meta["rows"] == part.height
    two, _, meta = read_parquet(str(path), columns=[whole.columns[1], whole.columns[0]])
    assert two.columns == [whole.columns[1], whole.columns[0]]


def frame_of_every_type(n=500):
    return pl.DataFrame({
        "i8": pl.Series([i % 100 - 50 if i % 7 else None for i in range(n)], dtype=pl.Int8),
        "i16": pl.Series([i * 3 for i in range(n)], dtype=pl.Int16),
        "i32": pl.Series([i * 100_003 if i % 3 else None for i in range(n)], dtype=pl.Int32),
        "i64": pl.Series([i * 10**12 for i in range(n)], dtype=pl.Int64),
        "u8": pl.Series([i % 256 for i in range(n)], dtype=pl.UInt8),
        "u16": pl.Series([65_535 - i for i in range(n)], dtype=pl.UInt16),
        "u32": pl.Series([2**32 - 1 - i if i % 4 else None for i in range(n)], dtype=pl.UInt32),
        "u64": pl.Series([2**64 - 1 - i for i in range(n)], dtype=pl.UInt64),
        "f32": pl.Series([i / 3 for i in range(n)], dtype=pl.Float32),
        "f64": pl.Series([float("nan") if i == 4 else i / 7 if i % 9 else None for i in range(n)]),
        "b": pl.Series([i % 2 == 0 if i % 11 else None for i in range(n)]),
        "s": [None if i % 13 == 0 else ("short" if i % 2 else f"a value longer than twelve {i}") for i in range(n)],
        "bin": pl.Series([None if i % 17 == 0 else bytes([i % 256, 0]) for i in range(n)], dtype=pl.Binary),
        "d": [dt.date(2000, 1, 1) + dt.timedelta(days=i) if i % 19 else None for i in range(n)],
        "tz": pl.Series([dt.datetime(2020, 1, 1) + dt.timedelta(seconds=i) for i in range(n)]).dt.replace_time_zone("America/New_York"),
        "ns": pl.Series([dt.datetime(2020, 1, 1) + dt.timedelta(microseconds=i) for i in range(n)]).cast(pl.Datetime("ns")),
        "t": [dt.time(i % 24, i % 60, i % 60, i) if i % 23 else None for i in range(n)],
        "e3": pl.Series([["a", "b", "c"][i % 3] if i % 29 else None for i in range(n)], dtype=pl.Enum(["c", "b", "a", "unused"])),
        "e300": pl.Series([f"l{i % 300}" for i in range(n)], dtype=pl.Enum([f"l{k}" for k in range(300)])),
        "e70k": pl.Series([f"l{i * 61}" for i in range(n)], dtype=pl.Enum([f"l{k}" for k in range(70_000)])),
        "cat": pl.Series([["x", "y"][i % 2] if i % 31 else None for i in range(n)], dtype=pl.Categorical),
        "null": pl.Series([None] * n),
    })


def test_every_polars_type_round_trips_through_several_chunks():
    base = frame_of_every_type()
    # polars exports these Enums with 8-, 16- and 32-bit keys.
    keys = {f.name: str(f.type.index_type) for f in pa.table(base).schema if pa.types.is_dictionary(f.type)}
    assert keys["e3"] == "uint8" and keys["e300"] == "uint16" and keys["e70k"] == "uint32"
    df = pl.concat([base.slice(0, 120), base.slice(120, 300), base.slice(420, 80)], rechunk=False)
    assert max(df.n_chunks("all")) > 1
    buf = native.parquet_write_arrow(df, None, None)
    back, _, _ = read_parquet(buf)
    expected = base.with_columns(pl.col("cat").cast(pl.String).cast(pl.Enum(["y", "x"])), pl.col("null").cast(pl.Float64))
    assert back.schema == expected.schema
    for name in base.columns:
        assert back[name].equals(expected[name], null_equal=True), name
    # Other readers see the types and the unsigned statistics.
    t = pq.read_table(io.BytesIO(buf))
    assert str(t.schema.field("u32").type) == "uint32" and str(t.schema.field("t").type) == "time64[ns]"
    stats = pq.ParquetFile(io.BytesIO(buf)).metadata.row_group(0).column(t.schema.get_field_index("u32")).statistics
    assert (stats.min, stats.max) == (2**32 - 500, 2**32 - 2)
    assert pl.read_parquet(io.BytesIO(buf))["u64"].to_list() == base["u64"].to_list()


def test_polars_takes_enums_through_their_field_metadata():
    # The route datakit uses (plan 0019: measured against a cast after
    # import). If polars stops honouring _PL_ENUM_VALUES2, the column
    # comes back Categorical and this fails: change the route.
    df = pl.DataFrame({"e": pl.Series(["b", "a", None], dtype=pl.Enum(["b", "a", "c"]))})
    back, _, _ = read_parquet(native.parquet_write_arrow(df, None, None))
    assert back["e"].dtype == pl.Enum(["b", "a", "c"]), back["e"].dtype
    assert back["e"].to_list() == ["b", "a", None]
    plain, _, _ = read_parquet(native.parquet_write_arrow(df, None, None), enum_metadata=False)
    assert isinstance(plain["e"].dtype, pl.Categorical)


def test_letters_meta_and_digests_round_trip():
    x = pl.DataFrame({"x": [1.0, None, 3.0, None], "n": pl.Series([1, None, 2, None], dtype=pl.Int16),
                      "ts": pl.Series([dt.datetime(2020, 1, 1), None, None, dt.datetime(2021, 1, 1)])})
    meta = {"label": "L", "notes": ["a"], "characteristics": {"x": {"c": "v"}}, "sort": [], "timestamp": "1 Jan 2020 00:00",
            "columns": {"x": ("lab", "%9.0g", "s", None)}, "value_labels": {"s": {1: "one", 2.5: "half", ".a": "refused", ".": "dot"}},
            "missing": {"x": pl.Series([None, ".a", None, ".z"], dtype=LETTERS), "n": pl.Series([None, ".c", None, None], dtype=LETTERS),
                        "ts": pl.Series([None, ".b", ".c", None], dtype=pl.String)}}
    buf = native.parquet_write_arrow(x, None, meta)
    back, letters, m = read_parquet(buf)
    assert back["n"].dtype == pl.Int16
    assert back["ts"].dtype == pl.Datetime("us") and back["ts"].to_list() == x["ts"].to_list()
    assert {k: letters[k].to_list() for k in letters.columns} == {
        "x": [None, ".a", None, ".z"], "n": [None, ".c", None, None], "ts": [None, ".b", ".c", None]}
    assert m["value_labels"] == {"s": {1: "one", 2.5: "half", ".a": "refused", ".": "dot"}}
    assert m["label"] == "L" and m["notes"] == ["a"] and m["characteristics"] == {"x": {"c": "v"}}
    assert [c[:4] for c in m["columns"] if c[0] == "x"] == [("x", "lab", "%9.0g", "s")]
    # The digest of a column read equals the digest of it written.
    assert native.arrow_digest(back["x"]) == native.arrow_digest(x["x"])


@pytest.mark.parametrize("bad, match", [
    ({"x": [".a", None, None, None]}, "holds a value and the letter"),
    ({"x": [None, ".q2", None, None]}, "not one of .a to .z"),
    ({"x": [None, None]}, "have 2 rows, but the frame has 4"),
])
def test_letters_are_checked(bad, match):
    x = pl.DataFrame({"x": [1.0, None, 3.0, None]})
    meta = {"missing": {k: pl.Series(v, dtype=pl.String) for k, v in bad.items()}}
    with pytest.raises(ValueError, match=match):
        native.parquet_write_arrow(x, None, meta)


def test_datetimes_with_letters_hold_whole_microseconds():
    ns = pl.DataFrame({"ts": (pl.Series([dt.datetime(2020, 1, 1), None]).cast(pl.Datetime("ns")).cast(pl.Int64) + 1).cast(pl.Datetime("ns"))})
    meta = {"missing": {"ts": pl.Series([None, ".a"], dtype=LETTERS)}}
    with pytest.raises(ValueError, match=r'column "ts", row 1: .*below a microsecond.*truncate'):
        native.parquet_write_arrow(ns, None, meta)
    back, _, _ = read_parquet(native.parquet_write_arrow(ns, None, meta, timestamps="truncate"))
    assert back["ts"][0] == dt.datetime(2020, 1, 1)
    far = pl.DataFrame({"ts": pl.Series([dt.datetime(2300, 1, 1, 0, 0, 0, 1), None])})
    # Past 2^53 microseconds, where the microseconds as a double round too.
    odd = pl.DataFrame({"ts": pl.Series([9007199254740995, None], dtype=pl.Int64).cast(pl.Datetime("us"))})
    # Far, but whole seconds a double holds exactly: written.
    whole = pl.DataFrame({"ts": pl.Series([9210000000000000000, None], dtype=pl.Int64).cast(pl.Datetime("us"))})
    for mode in ("error", "truncate"):
        written = native.parquet_write_arrow(whole, None, {"missing": {"ts": pl.Series([None, ".a"], dtype=LETTERS)}}, timestamps=mode)
        assert read_parquet(written)[0]["ts"].cast(pl.Int64)[0] == 9210000000000000000
    for frame in (far, odd):
        for mode in ("error", "truncate"):
            with pytest.raises(ValueError, match='column "ts", row 1: .*too far from 1970'):
                native.parquet_write_arrow(frame, None, {"missing": {"ts": pl.Series([None, ".a"], dtype=LETTERS)}}, timestamps=mode)


@pytest.mark.parametrize("df, what", [
    (pl.DataFrame({"x": pl.Series([1.5]).cast(pl.Decimal(10, 2))}), "Decimal.*Float64 or String"),
    (pl.DataFrame({"x": [[1, 2]]}), "List"),
    (pl.DataFrame({"x": [dt.timedelta(1)]}), "Duration"),
])
def test_types_not_written_are_errors(df, what):
    with pytest.raises(TypeError, match=f'column "x" is {what}'):
        native.parquet_write_arrow(df, None, None)


@pytest.mark.parametrize("dtype, value", [(pl.Int64, 1), (pl.UInt8, 1), (pl.Boolean, True), (pl.Enum(["a"]), "a")])
def test_letters_in_columns_that_cannot_hold_them_are_errors(dtype, value):
    df = pl.DataFrame({"x": pl.Series([value, None], dtype=dtype)})
    with pytest.raises(ValueError, match="cannot hold"):
        native.parquet_write_arrow(df, None, {"missing": {"x": pl.Series([None, ".a"], dtype=LETTERS)}})


def test_digests_are_the_same_across_lossless_casts_only():
    d = native.arrow_digest
    s = pl.Series("x", [1, 2, None, 4], dtype=pl.Int32)
    assert d(s) == d(s.cast(pl.Int64)) == d(s.cast(pl.Float64))
    assert d(s) != d(s.reverse())
    f = pl.Series([1.5, None, float("nan"), 2.0], dtype=pl.Float32)
    assert d(f) == d(f.cast(pl.Float64))
    big = pl.Series([2**53 + 1], dtype=pl.Int64)
    assert d(big) != d(big.cast(pl.Float64))
    assert d(pl.Series([0.1])) != d(pl.Series([0.1]).cast(pl.Float32))
    assert d(pl.Series([0.5])) == d(pl.Series([0.5]).cast(pl.Float32))
    e = pl.Series(["a", "b", None, "a"], dtype=pl.Enum(["b", "a"]))
    assert d(e) == d(e.cast(pl.String))
    t = pl.Series([dt.datetime(2020, 1, 1), None]).cast(pl.Datetime("ms"))
    assert d(t) == d(t.cast(pl.Datetime("ns")))
    day = pl.Series([dt.date(2020, 1, 1), None])
    assert d(day) == d(day.cast(pl.Int32))
    chunked = pl.concat([s.slice(0, 2), s.slice(2, 2)], rechunk=False)
    assert d(chunked) == d(s)
    # Equal values exchanged cannot be seen: validation, not proof.
    same = pl.Series([None, None], dtype=pl.Float64)
    assert d(same) == d(same.reverse())


def test_polars_takes_our_buffers_and_keeps_them():
    path = next(p for p in PARQUET if p.stem == "pyarrow_types")
    frame, _, _ = native.parquet_read_arrow(str(path))
    df = pl.DataFrame(frame)
    addresses = dict(zip(frame.names, frame.addresses))
    numeric = [c for c in df.columns if df[c].dtype in (pl.Int32, pl.Int64, pl.Float64)]
    assert numeric
    for c in numeric:
        assert df[c]._s.as_single_ptr() == addresses[c], c
    want = pl.read_parquet(path, columns=numeric)
    del frame
    gc.collect()
    junk = os.urandom(64 << 20)
    del junk
    for c in numeric:
        assert df[c].equals(want[c], null_equal=True)


def test_odd_row_groups_and_sliced_validity(tmp_path):
    n = 5003
    t = pa.table({"x": [i if i % 3 else None for i in range(n)], "s": [None if i % 5 == 0 else f"v{i}" for i in range(n)]})
    p = tmp_path / "odd.parquet"
    pq.write_table(t, p, row_group_size=1001)
    ours, _, _ = read_parquet(str(p))
    assert ours.equals(pl.read_parquet(p))
    part, _, _ = read_parquet(str(p), skip=999, n_max=1500)
    assert part.equals(pl.read_parquet(p).slice(999, 1500))
