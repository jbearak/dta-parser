"""read_dta and save_dta into pandas (plan 0019; plan 0024, stage 4),
checked against dta_parser's reader, which is itself tested against
haven, pandas and ReadStat: with default arguments both give the same
columns."""

import datetime as dt

import numpy as np
import pandas as pd
import pytest

import datakit as dk
import dta_parser as dp
from conftest import assert_same, fixture_paths, is_text, lettered, tags
from dta_parser import DtaArray

EPOCH_DAYS = 3653  # 1960-01-01 to 1970-01-01


def read_both(path, **kw):
    """datakit's and dta_parser's reads of `path`, and whether datakit
    had to truncate: a %td value with a fraction of a day, or a %tc value
    with a fraction of a millisecond, is an error by default."""
    want = dp.read_dta(path, **kw)
    try:
        got, meta = dk.read_dta(path, **kw)
        return got, meta, want, False
    except ValueError as e:
        assert "fraction of a" in str(e) and "row" in str(e)
        got, meta = dk.read_dta(path, timestamps="truncate", **kw)
        return got, meta, want, True


def assert_same_column(a, b, where):
    """datakit's column `a` and dta_parser's `b`: one dtype, and the same
    codes, values, categories and dates."""
    assert str(a.dtype) == str(b.dtype), f"{where}: {a.dtype} and {b.dtype}"
    if isinstance(b.array, DtaArray):
        assert np.array_equal(a.array.codes, b.array.codes), where
        assert np.array_equal(a.array._values, b.array._values, equal_nan=True), where
    elif isinstance(b.dtype, pd.CategoricalDtype):
        assert list(a.cat.categories) == list(b.cat.categories) and a.cat.ordered == b.cat.ordered, where
        assert a.cat.codes.tolist() == b.cat.codes.tolist(), where
    elif b.dtype == object:
        # A strL column with binary values: dta_parser gives its text rows
        # as str, datakit every row as bytes.
        # (Before pandas 3, object is also pandas' text dtype.)
        got = a.tolist()
        binary = any(isinstance(v, bytes) for v in got)
        want = [v.encode() if binary and isinstance(v, str) else v for v in b.tolist()]
        assert got == want, where
    else:
        pd.testing.assert_series_equal(a, b, check_names=False, obj=where)


def factor_columns(meta):
    return {n for n, c in meta.characteristics.items() if "dtaparser_factor" in c and n != "_dta"}


@pytest.mark.parametrize("path", fixture_paths(), ids=lambda p: p.stem)
def test_read_dta_gives_the_columns_dta_parser_gives(path):
    got, meta, want, truncated = read_both(path)
    info = want.attrs["dta"]["columns"]
    assert list(got.columns) == list(want.columns)
    # Expected differences: a dtaparser_factor column is a category in
    # dta_parser and labelled numbers in datakit (plan 0023); and a date
    # with a fraction, which dta_parser leaves as numbers.
    skip = factor_columns(meta)
    for name in got.columns:
        if name in skip:
            continue
        if truncated and dp.read_meta(path)["columns"][name]["format"].lstrip("%-").startswith(("td", "d", "tc")):
            continue
        assert_same_column(got[name], want[name], f"{path.stem}: {name}")
    attrs = want.attrs["dta"]
    assert meta.label == (attrs["label"] or None)
    assert meta.notes == attrs["notes"]
    assert meta.sort == attrs["sort_order"]
    for name, c in attrs["columns"].items():
        col = meta.columns[name]
        assert (col.label, col.format, col.value_labels) == (c["label"] or None, c["format"] or None,
                                                             c["value_labels"] or None)


@pytest.mark.parametrize("path", fixture_paths(), ids=lambda p: p.stem)
def test_windows_give_the_columns_dta_parser_gives(path):
    n = dp.read_meta(path)["nobs"]
    for skip, n_max in [(0, 1), (1, 3), (n // 2, 4), (max(n - 2, 0), 5)]:
        got, meta, want, truncated = read_both(path, skip=skip, n_max=n_max)
        if truncated:
            continue
        for name in got.columns:
            if name not in factor_columns(meta):
                assert_same_column(got[name], want[name], f"{path.stem}[{skip}:{skip + n_max}]: {name}")


def test_a_factor_mark_is_left_alone(tmp_path):
    # dta_parser's write_dta marks a category dtaparser_factor (plan 0020):
    # dta_parser reads it back a category; datakit leaves it labelled
    # numbers, the mark in meta.
    frame = pd.DataFrame({"f": pd.Categorical(["lo", "hi", None], categories=["lo", "hi"])})
    dp.write_dta(frame, tmp_path / "f.dta")
    assert isinstance(dp.read_dta(tmp_path / "f.dta")["f"].dtype, pd.CategoricalDtype)
    got, meta = dk.read_dta(tmp_path / "f.dta")
    assert got["f"].dtype == "dta[long]" or got["f"].dtype.kind in "iuf"
    assert "dtaparser_factor" in meta.characteristics["f"]
    assert meta.labels("f") == {0: "lo", 1: "hi"}


def test_letters_false_and_factors_true_are_datakits_own(tmp_path):
    pdf = pd.DataFrame({"x": dp.DtaArray([1.0, None, 2.0, None], codes=[0, 2, 0, 1], storage="byte")})
    pdf.attrs["dta"] = {"columns": {"x": {"value_labels": "xl"}}, "value_labels": {"xl": {1: "one", 2: "two"}}}
    dp.write_dta(pdf, tmp_path / "x.dta")
    df, _ = dk.read_dta(tmp_path / "x.dta", letters=False)
    assert df["x"].dtype == "dta[byte]" and df["x"].array.codes.tolist() == [0, 1, 0, 1]
    with pytest.warns(UserWarning, match=r'\.a to \.z in "x" are NaN'):
        df, _ = dk.read_dta(tmp_path / "x.dta", factors=True)
    assert list(df["x"].cat.categories) == ["one", "two"] and df["x"].cat.codes.tolist() == [0, -1, 1, -1]


def test_save_dta_warns_once_about_a_name_stata_reserves(tmp_path):
    with pytest.warns(UserWarning, match='save_dta: "in" is a word Stata reserves; rename it before using the file in Stata'):
        dk.save_dta(pd.DataFrame({"in": [1], "ok": [2]}), tmp_path / "r.dta")
    df, _ = dk.read_dta(tmp_path / "r.dta")
    assert list(df.columns) == ["in", "ok"]


@pytest.mark.parametrize("path", fixture_paths(), ids=lambda p: p.stem)
def test_save_dta_reads_back(path, tmp_path):
    df, meta = dk.read_dta(path, timestamps="truncate")
    out = tmp_path / "out.dta"
    dk.save_dta(df, out, meta=meta)
    back, back_meta = dk.read_dta(out, timestamps="truncate")
    assert_same(back, df)
    back_meta.timestamp = meta.timestamp
    assert back_meta == meta
    theirs_ = dp.read_dta(out)
    want = dp.read_dta(path)
    for name in df.columns:
        assert dp.missing_codes(theirs_[name]).tolist() == dp.missing_codes(want[name]).tolist(), name
    # A DtaArray is written in its storage type again.
    written, original = dp.read_meta(out)["columns"], dp.read_meta(path)["columns"]
    for name in df.columns:
        if isinstance(df[name].array, DtaArray) and df[name].dtype.storage != "double":
            assert written[name]["storage"] == original[name]["storage"], name


@pytest.mark.parametrize("path", fixture_paths(), ids=lambda p: p.stem)
def test_read_dta_letters_false_reads_them_as_dots(path):
    df, meta = dk.read_dta(path, timestamps="truncate")
    got, gm = dk.read_dta(path, letters=False, timestamps="truncate")
    assert gm.columns.keys() == meta.columns.keys()
    for name in df.columns:
        if isinstance(df[name].array, DtaArray) and (df[name].array.codes > 1).any():
            s = got[name]
            assert s.isna().tolist() == df[name].isna().tolist(), name
            if isinstance(s.array, DtaArray):
                assert (s.array.codes <= 1).all(), name


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
    assert df["t"].dtype == "datetime64[ms]"
    assert df["t"].array.asi8.tolist() == [-EPOCH_DAYS * 86_400_000, -EPOCH_DAYS * 86_400_000 + 1000]
    write("big", [1e300, 0.0], "%tc")
    for mode in ("error", "truncate"):
        with pytest.raises(ValueError, match="outside the range of datetimes"):
            dk.read_dta(tmp_path / "big.dta", timestamps=mode)
    write("d", [1.25, 2.0], "%td")
    with pytest.raises(ValueError, match='column "d", row 1: the date 1.25 .*fraction of a day'):
        dk.read_dta(tmp_path / "d.dta")
    got = dk.read_dta(tmp_path / "d.dta", timestamps="truncate")[0]["d"]
    assert got.dtype == "datetime64[s]" and got.tolist() == [pd.Timestamp("1960-01-02"), pd.Timestamp("1960-01-03")]
    write("far", [3e9], "%td")
    for mode in ("error", "truncate"):
        with pytest.raises(ValueError, match="outside the range of dates"):
            dk.read_dta(tmp_path / "far.dta", timestamps=mode)


def test_save_dta_types_and_errors(tmp_path):
    df = pd.DataFrame({
        "i": pd.array([1, None, 300], dtype="Int64"), "u": np.array([1, 2, 3], dtype=np.uint8),
        "f": pd.array([1.5, None, 2.0], dtype="Float32"), "b": pd.array([True, False, None], dtype="boolean"),
        "bn": [True, False, True],
        "s": ["a", None, "c" * 3000], "bin": [b"\x00\xff", None, b"x"],
        "d": pd.Series([dt.datetime(2024, 1, 1), None, dt.datetime(1900, 1, 1)], dtype="datetime64[s]"),
        "t": pd.Series([dt.datetime(2024, 1, 1, 1, 2, 3, 4000), None, dt.datetime(1960, 1, 1)],
                       dtype="datetime64[us]"),
        "e": pd.Categorical(["lo", "hi", None], categories=["lo", "mid", "hi"]),
    })
    meta = dk.Meta(label="Types", columns={"d": dk.Column(format="%td")})
    dk.save_dta(df, tmp_path / "x.dta", meta=meta)
    back, meta = dk.read_dta(tmp_path / "x.dta")
    assert back["i"].dtype == "dta[int]" and back["i"].tolist()[0::2] == [1, 300] and back["i"].isna().tolist()[1]
    assert back["u"].dtype == np.int8 and back["f"].dtype == "dta[float]"
    assert back["b"].dtype == "dta[byte]" and back["b"].array.codes.tolist() == [0, 0, 1]
    assert back["bn"].dtype == np.int8 and back["bn"].tolist() == [1, 0, 1]
    assert back["s"].tolist() == ["a", "", "c" * 3000]  # missing text is "" in Stata
    assert back["bin"].tolist() == [b"\x00\xff", b"", b"x"]
    assert back["d"].dtype == "datetime64[s]" and back["d"].tolist()[0::2] == df["d"].tolist()[0::2]
    assert back["t"].dtype == "datetime64[ms]" and back["t"].tolist()[0::2] == df["t"].tolist()[0::2]
    assert list(back["e"].cat.categories) == ["lo", "mid", "hi"] and back["e"].cat.codes.tolist() == [0, 2, -1]
    assert meta.labels("e") == {1: "lo", 2: "mid", 3: "hi"} and meta.columns["e"].ordered is False
    assert meta.label == "Types" and meta.columns["d"].format == "%td" and meta.columns["t"].format == "%tc"
    # A datetime without %td in meta, or not at midnight, is %tc.
    dk.save_dta(df[["d"]], tmp_path / "tc.dta")
    assert dp.read_meta(tmp_path / "tc.dta")["columns"]["d"]["format"] == "%tc"
    us = pd.DataFrame({"t": pd.Series([dt.datetime(2024, 1, 1, 0, 0, 0, 1)], dtype="datetime64[us]")})
    with pytest.raises(ValueError, match='"t", row 1: the datetime is not a whole number of milliseconds'):
        dk.save_dta(us, tmp_path / "y.dta")
    dk.save_dta(us, tmp_path / "y.dta", timestamps="truncate")
    for bad, what in [(pd.DataFrame({"t": pd.to_timedelta(["1h"])}), "timedelta64.*cannot hold"),
                      (pd.DataFrame({"t": np.array([2**53 + 1], dtype=np.int64)}), "2\\^53"),
                      (pd.DataFrame({"t": pd.Series([dt.datetime(2024, 1, 1)]).dt.tz_localize("UTC")}),
                       "time zone.*tz_localize\\(None\\)"),
                      (pd.DataFrame({"1x": [1]}), "not a name Stata can hold"),
                      (pd.DataFrame({"x": [1 + 1j]}), 'column "x"')]:
        with pytest.raises((TypeError, ValueError), match=what):
            dk.save_dta(bad, tmp_path / "z.dta")
    with pytest.raises(TypeError, match="pandas DataFrame"):
        dk.save_dta(df.to_dict(), tmp_path / "z.dta")


def test_save_dta_writes_letters(tmp_path):
    df = pd.DataFrame({"x": lettered([1.0, None, None], [None, ".b", None]),
                       "y": lettered([None, 2.0, None], [".z", None, None])})
    for meta in (None, dk.Meta()):
        dk.save_dta(df, tmp_path / "l.dta", meta=meta)
        back = dp.read_dta(tmp_path / "l.dta")
        assert dp.missing_codes(back["x"]).tolist() == [0, 3, 1]
        assert dp.missing_codes(back["y"]).tolist() == [27, 0, 1]
    got, _ = dk.read_dta(tmp_path / "l.dta")
    assert_same(got, df)
    dk.save_dta(df, tmp_path / "n.dta", missing_letters=False)
    assert dp.missing_codes(dp.read_dta(tmp_path / "n.dta")["x"]).tolist() == [0, 1, 1]
    # A tagged NaN in a plain float column is its letter too.
    import struct
    a = struct.unpack("<d", struct.pack("<Q", 0x7FF0_0061_0000_07A2))[0]
    dk.save_dta(pd.DataFrame({"x": [a, 1.0, np.nan]}), tmp_path / "f.dta")
    assert dp.missing_codes(dp.read_dta(tmp_path / "f.dta")["x"]).tolist() == [2, 0, 1]


def test_storage_round_trips_and_widens(tmp_path):
    pdf = pd.DataFrame({
        "b": dp.DtaArray([1, None, 3], codes=[0, 2, 0], storage="byte"),
        "i": dp.DtaArray([300, None, 1], codes=[0, 27, 0], storage="int"),
        "l": dp.DtaArray([70000, None, 1], codes=[0, 3, 0], storage="long"),
        "f": dp.DtaArray([1.5, None, 2.25], codes=[0, 4, 0], storage="float"),
    })
    dp.write_dta(pdf, tmp_path / "s.dta")
    df, meta = dk.read_dta(tmp_path / "s.dta")
    assert [str(t) for t in df.dtypes] == ["dta[byte]", "dta[int]", "dta[long]", "dta[float]"]
    assert tags(df["b"]) == [None, ".a", None] and tags(df["i"]) == [None, ".z", None]
    dk.save_dta(df, tmp_path / "same.dta", meta=meta)
    storage = {k: v["storage"] for k, v in dp.read_meta(tmp_path / "same.dta")["columns"].items()}
    assert storage == {"b": "byte", "i": "int", "l": "long", "f": "float"}
    # Values the storage type cannot hold: the next type that holds them.
    changed = df.copy()
    changed["b"] = (df["b"] * 1000).astype("dta[byte]")
    changed["i"] = (df["i"] + 0.5).astype("dta[int]")
    changed["f"] = (df["f"] + 0.1).astype("dta[float]")
    changed["l"] = (df["l"] * 1e5 + 0.1).astype("dta[long]")
    dk.save_dta(changed, tmp_path / "wider.dta", meta=meta)
    storage = {k: v["storage"] for k, v in dp.read_meta(tmp_path / "wider.dta")["columns"].items()}
    assert storage == {"b": "int", "i": "float", "l": "double", "f": "double"}
    back, _ = dk.read_dta(tmp_path / "wider.dta")
    assert tags(back["b"]) == [None, ".a", None] and back["b"].tolist()[0::2] == [1000.0, 3000.0]


def test_dates_with_letters_read_as_statas_numbers(tmp_path):
    pdf = pd.DataFrame({"d": dp.DtaArray([0.0, None, 3653.0], codes=[0, 2, 0], storage="long"),
                        "t": dp.DtaArray([1000.0, None, 0.0], codes=[0, 0, 27], storage="double"),
                        "plain": dp.DtaArray([1.0, None, 1.0], codes=[0, 1, 0], storage="long")})
    pdf.attrs["dta"] = {"columns": {"d": {"format": "%td"}, "t": {"format": "%tc"}, "plain": {"format": "%td"}}}
    dp.write_dta(pdf, tmp_path / "d.dta")
    df, meta = dk.read_dta(tmp_path / "d.dta")
    assert df["d"].dtype == "dta[long]" and df["d"].array._values[[0, 2]].tolist() == [0.0, 3653.0]
    assert tags(df["d"]) == [None, ".a", None] and meta.columns["d"].format == "%td"
    assert df["t"].dtype == "dta[double]" and tags(df["t"]) == [None, None, ".z"] and meta.columns["t"].format == "%tc"
    assert df["plain"].dtype == "datetime64[s]" and df["plain"].isna().tolist() == [False, True, False]
    dk.save_dta(df, tmp_path / "again.dta", meta=meta)
    again, _ = dk.read_dta(tmp_path / "again.dta")
    assert_same(again, df)
    # As dta_parser reads them.
    want = dp.read_dta(tmp_path / "d.dta")
    for name in df.columns:
        assert_same_column(df[name], want[name], name)


def test_a_binary_strl_round_trips(tmp_path):
    frame = pd.DataFrame({"b": pd.Series([b"\x00\x01", "text", b"\xff" * 3000], dtype=object)})
    frame.attrs["dta"] = {"columns": {"b": {"storage": "strL"}}}
    dp.write_dta(frame, tmp_path / "b.dta")
    df, meta = dk.read_dta(tmp_path / "b.dta")
    assert df["b"].dtype == object and df["b"].tolist() == [b"\x00\x01", b"text", b"\xff" * 3000]
    dk.save_dta(df, tmp_path / "again.dta", meta=meta)
    again, _ = dk.read_dta(tmp_path / "again.dta")
    assert again["b"].tolist() == df["b"].tolist()
    assert dp.read_meta(tmp_path / "again.dta")["columns"]["b"]["storage"] == "strL"


def test_read_dta_arguments(tmp_path):
    path = fixture_paths()[0]
    df, _ = dk.read_dta(path)
    part, pm = dk.read_dta(path, columns=[df.columns[-1], 0], skip=1, n_max=2)
    assert list(part.columns) == [df.columns[-1], df.columns[0]] and len(part) == min(2, max(len(df) - 1, 0))
    assert list(pm.columns) == list(part.columns)
    with pytest.raises(KeyError, match='"nope" is not in the file'):
        dk.read_dta(path, columns=["nope"])
    with pytest.raises(FileNotFoundError):
        dk.read_dta(tmp_path / "none.dta")


def test_text_is_pandas_default_text():
    for path in fixture_paths():
        df, _ = dk.read_dta(path, timestamps="truncate")
        for name in df.columns:
            if df[name].dtype != object and not isinstance(df[name].dtype, pd.CategoricalDtype) \
                    and df[name].dtype.kind not in "biufM" and not isinstance(df[name].array, DtaArray):
                assert is_text(df[name].dtype), (path.stem, name)


def test_save_dta_category_set_moves_aside_for_a_column_using_its_name(tmp_path):
    """x uses set f; the category f must not replace it."""
    df = pd.DataFrame({"f": pd.Categorical(["new"]), "x": [1]})
    meta = dk.Meta(columns={"x": dk.Column(value_labels="f")}, value_labels={"f": {1: "original"}, "f_2": {5: "taken"}})
    path = tmp_path / "t.dta"
    dk.save_dta(df, path, meta)
    got = dp.read_meta(path)
    assert (got["columns"]["x"]["value_labels"], got["columns"]["f"]["value_labels"]) == ("f", "f_3")
    assert got["value_labels"]["f"] == {1: "original"} and got["value_labels"]["f_3"] == {1: "new"}


def test_save_dta_category_set_replaces_its_own_name_when_no_other_column_uses_it(tmp_path):
    df = pd.DataFrame({"f": pd.Categorical(["new"]), "x": [1]})
    meta = dk.Meta(columns={"f": dk.Column(value_labels="f")}, value_labels={"f": {1: "old"}})
    path = tmp_path / "t.dta"
    dk.save_dta(df, path, meta)
    assert dp.read_meta(path)["value_labels"] == {"f": {1: "new"}}
