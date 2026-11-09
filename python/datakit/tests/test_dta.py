"""read_dta and save_dta into polars (plan 0019, "`.dta` in polars"),
checked cell by cell against dta_parser's pandas reader, which is itself
tested against haven, pandas and ReadStat."""

import datetime as dt
import math
import struct
import warnings

import numpy as np
import polars as pl
import pytest
from polars.testing import assert_frame_equal

import datakit as dk
from conftest import assert_same, fixture_paths, tagged, tags

dp = pytest.importorskip("dta_parser")
pd = pytest.importorskip("pandas")

EPOCH_DAYS = 3653  # 1960-01-01 to 1970-01-01


def bits(x):
    return struct.pack("<d", float(x))


def ours(df, meta, name):
    """Per row: ("m", code) for a missing value, else ("v", value): a
    number, text, bytes, or days or milliseconds since 1960 for dates
    (a date column holding letters is those numbers already)."""
    s = df[name]
    letters = dk.na_tag(s).to_physical().to_list()
    out = []
    if s.dtype == pl.Date:
        values = [None if v is None else v + EPOCH_DAYS for v in s.to_physical().to_list()]
    elif s.dtype == pl.Datetime("ms"):
        values = [None if v is None else v + EPOCH_DAYS * 86_400_000 for v in s.to_physical().to_list()]
    else:
        values = s.to_list()
    for v, l in zip(values, letters):
        if l is not None:
            out.append(("m", l + 2))
        elif v is None:
            out.append(("m", 1))
        else:
            out.append(("v", v))
    return out


def theirs(df, name, fmt):
    """dta_parser's cells, in the same terms."""
    col = df[name]
    codes = dp.missing_codes(col).tolist()
    out = []
    if col.dtype.kind == "M":
        unit = np.datetime_data(col.dtype)[0]
        raw = col.to_numpy().astype(f"datetime64[{unit}]").view(np.int64)
        for c, r in zip(codes, raw):
            if c:
                out.append(("m", c))
            elif fmt.lstrip("%-").startswith(("td", "d")):
                out.append(("v", int(r // {"s": 86400, "ms": 86_400_000}[unit]) + EPOCH_DAYS))
            else:
                out.append(("v", int(r) * (1000 if unit == "s" else 1) + EPOCH_DAYS * 86_400_000))
        return out
    for c, v in zip(codes, col.tolist()):
        out.append(("m", c) if c else ("v", v))
    return out


def same(a, b):
    if a[0] != b[0]:
        return False
    if a[0] == "m":
        return a[1] == b[1]
    x, y = a[1], b[1]
    if isinstance(x, float) or isinstance(y, float):
        if isinstance(x, (int, float)) and isinstance(y, (int, float)):
            return bits(x) == bits(y) or (math.isnan(x) and math.isnan(y))
    if isinstance(x, bytes) and isinstance(y, str):
        return x == y.encode()
    return x == y


@pytest.mark.parametrize("path", fixture_paths(), ids=lambda p: p.stem)
def test_read_dta_agrees_with_dta_parser_per_cell(path):
    want = dp.read_dta(path)
    info = want.attrs["dta"]["columns"]
    try:
        got, meta = dk.read_dta(path)
        mode = "error"
    except ValueError as e:
        # A %td value with a fraction of a day, or a %tc value with a
        # fraction of a millisecond: an error naming the column and row by
        # default; truncated with timestamps="truncate".
        assert "fraction of a" in str(e) and "row" in str(e)
        got, meta = dk.read_dta(path, timestamps="truncate")
        mode = "truncate"
    assert got.columns == list(want.columns)
    for name in got.columns:
        a, b = ours(got, meta, name), theirs(want, name, info[name]["format"])
        fmt = info[name]["format"].lstrip("%-")
        if mode == "truncate" and fmt.startswith(("td", "d", "tc")):
            b = [x if x[0] == "m" or not isinstance(x[1], float) else ("v", math.floor(x[1])) for x in b]
        assert len(a) == len(b), name
        for i, (x, y) in enumerate(zip(a, b)):
            assert same(x, y), f"{path.stem}: {name} row {i + 1}: ours {x}, dta_parser's {y}"
    attrs = want.attrs["dta"]
    assert meta.label == (attrs["label"] or None)
    assert meta.notes == attrs["notes"]
    assert meta.sort == attrs["sort_order"]
    for name, c in attrs["columns"].items():
        assert meta.columns[name] == dk.Column(c["label"] or None, c["format"] or None, c["value_labels"] or None)


def test_save_dta_warns_once_about_a_name_stata_reserves(tmp_path):
    with pytest.warns(UserWarning, match='save_dta: "in" is a word Stata reserves; rename it before using the file in Stata'):
        dk.save_dta(pl.DataFrame({"in": [1], "ok": [2]}), tmp_path / "r.dta")
    df, _ = dk.read_dta(tmp_path / "r.dta")
    assert df.columns == ["in", "ok"]


@pytest.mark.parametrize("path", fixture_paths(), ids=lambda p: p.stem)
def test_save_dta_reads_back_with_dta_parser(path, tmp_path):
    df, meta = dk.read_dta(path, timestamps="truncate")
    out = tmp_path / "out.dta"
    dk.save_dta(df, out, meta=meta)
    back, back_meta = dk.read_dta(out, timestamps="truncate")
    assert_same(back, df)
    back_meta.timestamp = meta.timestamp
    assert back_meta == meta and back_meta._storage == meta._storage
    theirs_ = dp.read_dta(out)
    want = dp.read_dta(path)
    for name in df.columns:
        assert dp.missing_codes(theirs_[name]).tolist() == dp.missing_codes(want[name]).tolist(), name
    # A column a read made Float64 for its letters is written in its
    # file's storage type again.
    written, original = dp.read_meta(out)["columns"], dp.read_meta(path)["columns"]
    for name in meta._storage:
        assert written[name]["storage"] == original[name]["storage"], name


@pytest.mark.parametrize("path", fixture_paths(), ids=lambda p: p.stem)
def test_read_dta_letters_false_reads_them_as_nulls(path):
    df, meta = dk.read_dta(path, timestamps="truncate")
    got, gm = dk.read_dta(path, letters=False, timestamps="truncate")
    assert gm == meta and gm._storage == {}
    for name, t in df.schema.items():
        s = got[name]
        if name in meta._storage:
            assert s.dtype == meta._storage[name], name
        if t == pl.Float64 and dk.is_tagged_na(df[name]).any():
            assert s.is_null().to_list() == (df[name].is_null() | dk.is_tagged_na(df[name])).to_list(), name


def test_tc_fractions_and_range(tmp_path):
    # Built with dta_parser's pandas writer: %tc milliseconds since 1960.
    def write(name, values, fmt):
        frame = pd.DataFrame({name: values})
        frame.attrs["dta"] = {"columns": {name: {"format": fmt}}}
        dp.write_dta(frame, tmp_path / f"{name}.dta")

    write("t", [0.5, 1000.0], "%tc")
    with pytest.raises(ValueError, match='column "t", row 1: .*fraction of a millisecond.*timestamps="truncate"'):
        dk.read_dta(tmp_path / "t.dta")
    df, _ = dk.read_dta(tmp_path / "t.dta", timestamps="truncate")
    assert df["t"].dtype == pl.Datetime("ms") and df["t"].dt.epoch("ms").to_list() == [-EPOCH_DAYS * 86_400_000,
                                                                                      -EPOCH_DAYS * 86_400_000 + 1000]
    write("big", [1e300, 0.0], "%tc")
    for mode in ("error", "truncate"):
        with pytest.raises(ValueError, match="outside polars' Datetime range"):
            dk.read_dta(tmp_path / "big.dta", timestamps=mode)
    write("d", [1.25, 2.0], "%td")
    with pytest.raises(ValueError, match='column "d", row 1: the date 1.25 .*fraction of a day'):
        dk.read_dta(tmp_path / "d.dta")
    assert dk.read_dta(tmp_path / "d.dta", timestamps="truncate")[0]["d"].to_list() == [dt.date(1960, 1, 2),
                                                                                      dt.date(1960, 1, 3)]
    write("far", [3e9], "%td")
    for mode in ("error", "truncate"):
        with pytest.raises(ValueError, match="outside polars' Date range"):
            dk.read_dta(tmp_path / "far.dta", timestamps=mode)


def test_save_dta_types_and_errors(tmp_path):
    df = pl.DataFrame({
        "i": pl.Series([1, None, 300], dtype=pl.Int64), "u": pl.Series([1, 2, 3], dtype=pl.UInt8),
        "f": pl.Series([1.5, None, 2.0], dtype=pl.Float32), "b": [True, False, None],
        "s": ["a", None, "c" * 3000], "bin": [b"\x00\xff", None, b"x"],
        "d": [dt.date(2024, 1, 1), None, dt.date(1900, 1, 1)],
        "t": pl.Series([dt.datetime(2024, 1, 1, 1, 2, 3, 4000), None, dt.datetime(1960, 1, 1)]),
        "e": pl.Series(["lo", "hi", None], dtype=pl.Enum(["lo", "mid", "hi"])),
    })
    dk.save_dta(df, tmp_path / "x.dta", meta=dk.Meta(label="Types"))
    back, meta = dk.read_dta(tmp_path / "x.dta")
    assert back["i"].dtype == pl.Int16 and back["i"].to_list() == [1, None, 300]
    assert back["u"].dtype == pl.Int8 and back["f"].dtype == pl.Float32
    assert back["b"].to_list() == [1, 0, None]
    assert back["s"].to_list() == ["a", "", "c" * 3000]  # null text is "" in Stata
    assert back["bin"].to_list() == [b"\x00\xff", b"", b"x"]
    assert back["d"].to_list() == df["d"].to_list()
    assert back["t"].dtype == pl.Datetime("ms") and back["t"].to_list() == df["t"].to_list()
    assert back["e"].dtype == pl.Enum(["lo", "mid", "hi"]) and back["e"].to_list() == ["lo", "hi", None]
    assert meta.labels("e") == {1: "lo", 2: "mid", 3: "hi"} and meta.columns["e"].ordered is False
    assert meta.label == "Types" and meta.columns["d"].format == "%td" and meta.columns["t"].format == "%tc"
    us = pl.DataFrame({"t": [dt.datetime(2024, 1, 1, 0, 0, 0, 1)]})
    with pytest.raises(ValueError, match='"t", row 1: the datetime is not a whole number of milliseconds'):
        dk.save_dta(us, tmp_path / "y.dta")
    dk.save_dta(us, tmp_path / "y.dta", timestamps="truncate")
    for bad, what in [(pl.DataFrame({"t": [dt.time(1)]}), "Time"),
                      (pl.DataFrame({"t": [dt.timedelta(1)]}), "Duration"),
                      (pl.DataFrame({"t": pl.Series([2**53 + 1], dtype=pl.Int64)}), "2\\^53"),
                      (pl.DataFrame({"t": [dt.datetime(2024, 1, 1)]}).with_columns(pl.col("t").dt.replace_time_zone("UTC")),
                       "time zone"),
                      (pl.DataFrame({"1x": [1]}), "not a name Stata can hold")]:
        with pytest.raises((TypeError, ValueError), match=what):
            dk.save_dta(bad, tmp_path / "z.dta")
    with pytest.raises(TypeError, match="LazyFrame"):
        dk.save_dta(df.lazy(), tmp_path / "z.dta")


def test_save_dta_writes_tagged_nans_as_letters(tmp_path):
    df = pl.DataFrame({"x": tagged([1.0, None, None], [None, ".b", None]), "y": tagged([None, 2.0, None], [".z", None, None])})
    for meta in (None, dk.Meta()):
        dk.save_dta(df, tmp_path / "l.dta", meta=meta)
        back = dp.read_dta(tmp_path / "l.dta")
        assert dp.missing_codes(back["x"]).tolist() == [0, 3, 1]
        assert dp.missing_codes(back["y"]).tolist() == [27, 0, 1]
    got, _ = dk.read_dta(tmp_path / "l.dta")
    assert_same(got, df)
    dk.save_dta(df, tmp_path / "n.dta", missing_letters=False)
    assert dp.missing_codes(dp.read_dta(tmp_path / "n.dta")["x"]).tolist() == [0, 1, 1]


def test_storage_comes_back_only_when_the_values_fit(tmp_path):
    pdf = pd.DataFrame({
        "b": dp.DtaArray([1, None, 3], codes=[0, 2, 0], storage="byte"),
        "i": dp.DtaArray([300, None, 1], codes=[0, 27, 0], storage="int"),
        "l": dp.DtaArray([70000, None, 1], codes=[0, 3, 0], storage="long"),
        "f": dp.DtaArray([1.5, None, 2.25], codes=[0, 4, 0], storage="float"),
    })
    dp.write_dta(pdf, tmp_path / "s.dta")
    df, meta = dk.read_dta(tmp_path / "s.dta")
    assert all(t == pl.Float64 for t in df.schema.dtypes())
    assert meta._storage == {"b": pl.Int8, "i": pl.Int16, "l": pl.Int32, "f": pl.Float32}
    assert tags(df["b"]) == [None, ".a", None] and tags(df["i"]) == [None, ".z", None]
    dk.save_dta(df, tmp_path / "same.dta", meta=meta)
    storage = {k: v["storage"] for k, v in dp.read_meta(tmp_path / "same.dta")["columns"].items()}
    assert storage == {"b": "byte", "i": "int", "l": "long", "f": "float"}
    # Values the storage type cannot hold are written as double.
    changed = df.with_columns(pl.col("b") * 1000, pl.col("i") + 0.5, pl.col("f") + 0.1)
    dk.save_dta(changed, tmp_path / "wider.dta", meta=meta)
    storage = {k: v["storage"] for k, v in dp.read_meta(tmp_path / "wider.dta")["columns"].items()}
    assert storage == {"b": "double", "i": "double", "l": "long", "f": "double"}
    back, _ = dk.read_dta(tmp_path / "wider.dta")
    assert tags(back["b"]) == [None, ".a", None] and back["b"].fill_nan(None).to_list() == [1000.0, None, 3000.0]


def test_dates_with_letters_read_as_statas_numbers(tmp_path):
    pdf = pd.DataFrame({"d": dp.DtaArray([0.0, None, 3653.0], codes=[0, 2, 0], storage="long"),
                        "t": dp.DtaArray([1000.0, None, 0.0], codes=[0, 0, 27], storage="double"),
                        "plain": dp.DtaArray([1.0, None], codes=[0, 1], storage="long").repeat(2)[:3]})
    pdf.attrs["dta"] = {"columns": {"d": {"format": "%td"}, "t": {"format": "%tc"}, "plain": {"format": "%td"}}}
    dp.write_dta(pdf, tmp_path / "d.dta")
    df, meta = dk.read_dta(tmp_path / "d.dta")
    assert df["d"].dtype == pl.Float64 and df["d"].fill_nan(None).to_list() == [0.0, None, 3653.0]
    assert tags(df["d"]) == [None, ".a", None] and meta.columns["d"].format == "%td"
    assert df["t"].dtype == pl.Float64 and tags(df["t"]) == [None, None, ".z"] and meta.columns["t"].format == "%tc"
    assert df["plain"].dtype == pl.Date
    dk.save_dta(df, tmp_path / "again.dta", meta=meta)
    again, _ = dk.read_dta(tmp_path / "again.dta")
    assert_same(again, df)


def test_read_dta_arguments(tmp_path):
    path = fixture_paths()[0]
    df, _ = dk.read_dta(path)
    part, pm = dk.read_dta(path, columns=[df.columns[-1], 0], skip=1, n_max=2)
    assert part.columns == [df.columns[-1], df.columns[0]] and part.height == min(2, max(df.height - 1, 0))
    assert list(pm.columns) == part.columns
    with pytest.raises(KeyError, match='"nope" is not in the file'):
        dk.read_dta(path, columns=["nope"])
    with pytest.raises(FileNotFoundError):
        dk.read_dta(tmp_path / "none.dta")


def test_save_dta_enum_set_moves_aside_for_a_column_using_its_name(tmp_path):
    """x uses set f; the Enum f must not replace it."""
    df = pl.DataFrame({"f": pl.Series(["new"], dtype=pl.Enum(["new"])), "x": [1]})
    meta = dk.Meta(columns={"x": dk.Column(value_labels="f")}, value_labels={"f": {1: "original"}, "f_2": {5: "taken"}})
    path = tmp_path / "t.dta"
    dk.save_dta(df, path, meta)
    got = dp.read_meta(path)
    assert (got["columns"]["x"]["value_labels"], got["columns"]["f"]["value_labels"]) == ("f", "f_3")
    assert got["value_labels"]["f"] == {1: "original"} and got["value_labels"]["f_3"] == {1: "new"}


def test_save_dta_enum_set_replaces_its_own_name_when_no_other_column_uses_it(tmp_path):
    df = pl.DataFrame({"f": pl.Series(["new"], dtype=pl.Enum(["new"])), "x": [1]})
    meta = dk.Meta(columns={"f": dk.Column(value_labels="f")}, value_labels={"f": {1: "old"}})
    path = tmp_path / "t.dta"
    dk.save_dta(df, path, meta)
    assert dp.read_meta(path)["value_labels"] == {"f": {1: "new"}}
