"""write_dta: round trips, what pandas and pyreadstat read back, the type
mapping for frames that did not come from read_dta, and its errors."""

import datetime

import numpy as np
import pandas as pd
import pyreadstat
import pytest
from pandas.io.stata import StataReader

import dta_parser as dp
from dta_parser import StataArray, missing, read_dta, read_meta, write_dta
from test_compat import READERS, known

TEXT = pd.Series(["a"]).dtype


def same_column(a, b):
    """Values and missing codes equal, whatever the dtype."""
    assert len(a) == len(b)
    assert dp.missing_codes(a).tolist() == dp.missing_codes(b).tolist()
    if a.dtype.kind == "M" or b.dtype.kind == "M":
        assert a.tolist() == b.tolist()
    elif a.dtype.kind in "iuf" or isinstance(a.dtype, dp.StataDtype):
        x, y = np.asarray(a, dtype=np.float64), np.asarray(b, dtype=np.float64)
        assert np.array_equal(x, y, equal_nan=True)
    else:
        assert a.tolist() == b.tolist()


def test_every_fixture_round_trips(fixture, tmp_path):
    original = read_dta(fixture)
    path = tmp_path / "out.dta"
    write_dta(original, path)
    back = read_dta(path)
    assert list(back.columns) == list(original.columns)
    for name in original.columns:
        same_column(original[name], back[name])
        assert back[name].dtype == original[name].dtype, name
    a, b = original.attrs["dta"], back.attrs["dta"]
    assert b["release"] == 118
    for key in ("label", "notes", "characteristics", "sort_order", "value_labels"):
        assert a[key] == b[key], key
    for name, col in a["columns"].items():
        other = b["columns"][name]
        assert (col["format"], col["label"], col["value_labels"]) == (
            other["format"], other["label"], other["value_labels"]), name
        if col["storage"].startswith("str"):
            assert other["storage"].startswith("strL" if col["storage"] == "strL" else "str")
        else:
            assert col["storage"] == other["storage"], name


@pytest.mark.parametrize("reader", sorted(READERS))
def test_pandas_and_pyreadstat_read_back_what_they_read(fixture, reader, tmp_path):
    read = READERS[reader]
    try:
        theirs = read(fixture)
    except Exception as e:
        pytest.skip(f"{reader} cannot read {fixture.name}: {e}")
    path = tmp_path / "out.dta"
    write_dta(read_dta(fixture), path)
    again = read(path)
    assert again["names"] == theirs["names"]
    assert again["nobs"] == theirs["nobs"]
    assert again["data_label"] == theirs["data_label"]
    for name, var in theirs["variables"].items():
        mine = again["variables"][name]
        for field in ("format", "label", "labels"):
            if not known(reader, fixture.stem, f"{name}.{field}"):
                assert mine[field] == var[field], f"{name}.{field}"
        if var["type"] and not var["type"].startswith("str"):
            assert mine["type"] == var["type"], name
        if not known(reader, fixture.stem, name):
            assert again["values"][name] == theirs["values"][name], name


def written(df, tmp_path, **kw):
    path = tmp_path / "t.dta"
    write_dta(df, path, **kw)
    return path


def pandas_types(path):
    with StataReader(path) as r:
        r.read()
        return dict(zip(r._varlist, (r._typlist[i] for i in range(len(r._varlist)))))


def storage(path):
    return {k: v["storage"] for k, v in read_meta(path)["columns"].items()}


def test_type_mapping_for_numbers(tmp_path):
    df = pd.DataFrame({
        "flag": [True, False, True],
        "small": np.array([-127, 0, 100], dtype=np.int64),
        "mid": np.array([-32767, 0, 32740], dtype=np.int32),
        "big": np.array([-2147483647, 0, 2147483620], dtype=np.int64),
        "huge": np.array([2**53, 0, -(2**53)], dtype=np.int64),
        "over": np.array([101, 0, 1], dtype=np.int8),
        "u": np.array([0, 40000, 1], dtype=np.uint16),
        "f": np.array([1.5, np.nan, -2.0], dtype=np.float32),
        "d": [0.1, np.nan, 1e300],
        "nullable": pd.array([1, None, 300], dtype="Int64"),
        "nb": pd.array([True, None, False], dtype="boolean"),
        "nf": pd.array([0.5, None, 2.0], dtype="Float64"),
    })
    path = written(df, tmp_path)
    assert storage(path) == {
        "flag": "byte", "small": "byte", "mid": "int", "big": "long", "huge": "double", "over": "int",
        "u": "long", "f": "float", "d": "double", "nullable": "int", "nb": "byte", "nf": "double",
    }
    # pandas reads the same types and values.
    types = pandas_types(path)
    assert [types[k] for k in ("flag", "mid", "big", "huge", "f")] == ["b", "h", "l", "d", "f"]
    theirs = pd.read_stata(path, convert_missing=True)
    assert theirs["huge"].tolist() == [2.0**53, 0.0, -(2.0**53)]
    assert theirs["flag"].tolist() == [1, 0, 1]
    assert [str(v) for v in theirs["f"].tolist()] == ["1.5", ".", "-2.0"]
    assert [str(v) for v in theirs["nullable"].tolist()] == ["1", ".", "300"]
    assert [str(v) for v in theirs["nb"].tolist()] == ["1", ".", "0"]
    assert [str(v) for v in theirs["nf"].tolist()] == ["0.5", ".", "2.0"]


def test_integers_beyond_2_53_are_an_error(tmp_path):
    df = pd.DataFrame({"x": np.array([2**53 + 1], dtype=np.int64)})
    with pytest.raises(ValueError, match="'x'.*2\\^53"):
        written(df, tmp_path)
    df = pd.DataFrame({"x": np.array([2**64 - 1], dtype=np.uint64)})
    with pytest.raises(ValueError, match="'x'"):
        written(df, tmp_path)


def test_stata_array_keeps_storage_and_codes(tmp_path):
    x = StataArray([1.0, np.nan, np.nan, 4.0], [0, 1, 3, 0], storage="int")
    path = written(pd.DataFrame({"x": x}), tmp_path)
    assert storage(path) == {"x": "int"}
    back = read_dta(path)
    assert back["x"].array.codes.tolist() == [0, 1, 3, 0]
    theirs = pd.read_stata(path, convert_missing=True)["x"].tolist()
    assert [str(v) for v in theirs] == ["1", ".", ".b", "4"]
    df, _ = pyreadstat.read_dta(str(path), user_missing=True)
    assert df["x"].tolist()[2] == "b"


def test_category_writes_codes_and_value_labels(tmp_path):
    df = pd.DataFrame({"c": pd.Categorical(["lo", "hi", None, "lo"], categories=["lo", "hi"])})
    path = written(df, tmp_path)
    assert storage(path) == {"c": "long"}
    theirs = pd.read_stata(path)
    assert theirs["c"].tolist()[:2] == ["lo", "hi"] and pd.isna(theirs["c"][2])
    _, meta = pyreadstat.read_dta(str(path))
    assert meta.variable_value_labels["c"] == {0: "lo", 1: "hi"}


def test_datetimes(tmp_path):
    df = pd.DataFrame({
        "day": pd.to_datetime(["1960-01-02", None, "2026-10-28"]),
        "when": pd.to_datetime(["1960-01-01 00:00:00.001", "2026-10-28 14:38:05", None], format="ISO8601"),
        "s": np.array(["2000-01-01", "1959-12-31"], dtype="datetime64[s]").repeat([2, 1]),
    })
    path = written(df, tmp_path)
    meta = read_meta(path)["columns"]
    assert (meta["day"]["storage"], meta["day"]["format"]) == ("long", "%td")
    assert (meta["when"]["storage"], meta["when"]["format"]) == ("double", "%tc")
    assert (meta["s"]["storage"], meta["s"]["format"]) == ("long", "%td")
    theirs = pd.read_stata(path)
    assert theirs["day"][0] == pd.Timestamp("1960-01-02") and pd.isna(theirs["day"][1])
    assert theirs["when"][1] == pd.Timestamp("2026-10-28 14:38:05")
    assert theirs["s"][2] == pd.Timestamp("1959-12-31")
    raw = pd.read_stata(path, convert_dates=False)
    assert raw["day"].tolist()[0] == 1 and raw["when"].tolist()[0] == 1.0
    back = read_dta(path)
    assert back["day"].tolist() == df["day"].tolist()
    assert back["when"].tolist() == df["when"].tolist()
    with pytest.raises(ValueError, match="finer than a millisecond"):
        written(pd.DataFrame({"t": pd.to_datetime(["2000-01-01 00:00:00.0000001"])}), tmp_path)
    with pytest.raises(TypeError, match="time-zone"):
        written(pd.DataFrame({"t": pd.to_datetime(["2000-01-01"]).tz_localize("UTC")}), tmp_path)


def test_text(tmp_path):
    long = "x" * 2046
    df = pd.DataFrame({
        "s": ["a", None, "ünï", ""],
        "o": pd.Series(["b", np.nan, pd.NA, "c"], dtype=object),
        "l": [long, "short", None, long],
        "bin": [b"\x00\xff", b"text", b"", b"\x00\xff"],
    })
    path = written(df, tmp_path)
    assert storage(path) == {"s": "str5", "o": "str1", "l": "strL", "bin": "strL"}
    theirs = pd.read_stata(path)
    assert theirs["s"].tolist() == ["a", "", "ünï", ""]
    assert theirs["o"].tolist() == ["b", "", "", "c"]
    assert theirs["l"].tolist() == [long, "short", "", long]
    back = read_dta(path)
    assert back["bin"].dtype == object
    assert back["bin"].tolist() == [b"\x00\xff", b"text", b"", b"\x00\xff"]
    # Text and binary strLs in one column round-trip as such.
    mixed = pd.DataFrame({"m": pd.Series(["t", b"\x01"], dtype=object)})
    assert read_dta(written(mixed, tmp_path))["m"].tolist() == ["t", b"\x01"]


def test_metadata_from_attrs(tmp_path):
    df = pd.DataFrame({
        "a": StataArray([1.0, 2.0, np.nan], [0, 0, 5], storage="byte"),
        "b": ["x", "y", "z"],
        "c": [0.25, 0.5, 1.0],
    })
    df.attrs["dta"] = {
        "label": "a data label",
        "notes": ["first note", "second note"],
        "characteristics": {"_dta": {"origin": "test"}, "a": {"note1": "about a"}, "gone": {"x": "y"}},
        "sort_order": ["a", "gone", "b"],
        "value_labels": {"ab": {1: "one", 2: "two", missing.d: "dunno"}},
        "columns": {
            "a": {"storage": "byte", "format": "%9.2f", "label": "Label of a", "value_labels": "ab"},
            "b": {"storage": "str3", "format": "%-5s", "label": "Label of b", "value_labels": ""},
            "c": {"storage": "float", "format": "%6.3f", "label": "", "value_labels": ""},
        },
    }
    path = written(df, tmp_path, timestamp=datetime.datetime(2026, 10, 28, 14, 38))
    _, meta = pyreadstat.read_dta(str(path))
    assert meta.file_label == "a data label"
    assert meta.notes == ["first note", "second note"]
    assert meta.column_labels == ["Label of a", "Label of b", None]
    assert meta.original_variable_types == {"a": "%9.2f", "b": "%-5s", "c": "%6.3f"}
    assert meta.variable_value_labels["a"] == {1: "one", 2: "two", "d": "dunno"}
    with StataReader(path) as r:
        r.read()
        assert r.time_stamp == "28 Oct 2026 14:38"
        assert r._typlist[2] == "f"
    back = read_dta(path).attrs["dta"]
    assert back["characteristics"] == {"_dta": {"origin": "test"}, "a": {"note1": "about a"}}
    assert back["sort_order"] == ["a"]
    assert write_dta(df, path, label="override", variable_labels={"c": "now c"}) is None
    _, meta = pyreadstat.read_dta(str(path))
    assert meta.file_label == "override" and meta.column_labels[2] == "now c"


def test_stored_storage_used_only_when_values_fit(tmp_path):
    df = pd.DataFrame({"x": [1.0, 300.0], "y": [1.0, np.nan]})
    df.attrs["dta"] = {"columns": {"x": {"storage": "byte"}, "y": {"storage": "byte"}}}
    assert storage(written(df, tmp_path)) == {"x": "double", "y": "byte"}


def test_errors_name_the_column(tmp_path):
    for name in ["1st", "has space", "x" * 33, "_n", "int", "str12", 3, ""]:
        with pytest.raises(ValueError, match="not a name Stata can hold"):
            written(pd.DataFrame({name: [1]}), tmp_path)
    with pytest.raises(ValueError, match="more than once"):
        written(pd.DataFrame([[1, 2]], columns=["a", "a"]), tmp_path)
    with pytest.raises(ValueError, match="obj row 2"):
        written(pd.DataFrame({"obj": pd.Series(["a", 3], dtype=object)}), tmp_path)
    with pytest.raises(TypeError, match="'td'"):
        written(pd.DataFrame({"td": pd.to_timedelta([1], unit="D")}), tmp_path)
    with pytest.raises(TypeError, match="'cx'"):
        written(pd.DataFrame({"cx": [1 + 2j]}), tmp_path)
    with pytest.raises(ValueError, match="text"):
        written(pd.DataFrame({"text": ["a\0b"]}), tmp_path)
    assert not (tmp_path / "t.dta").exists()


def test_a_frame_without_rows_or_columns(tmp_path):
    empty = pd.DataFrame({"x": np.array([], dtype=np.float64), "s": pd.Series([], dtype=object)})
    back = read_dta(written(empty, tmp_path))
    assert len(back) == 0 and list(back.columns) == ["x", "s"]
    assert len(read_dta(written(pd.DataFrame(index=range(3)), tmp_path))) == 3


def test_a_failed_write_leaves_the_existing_file(tmp_path):
    path = tmp_path / "keep.dta"
    dp.write_dta(pd.DataFrame({"x": [1.5, 2.5]}), path)
    before = path.read_bytes()
    with pytest.raises(Exception):
        dp.write_dta(pd.DataFrame({"x": [float("inf")]}), path)
    assert path.read_bytes() == before
    assert list(tmp_path.iterdir()) == [path]


def test_dates_too_far_from_1960_are_an_error(tmp_path):
    far = pd.DataFrame({"t": np.array(["1000000000-01-01T00:00:01"], dtype="datetime64[s]")})
    with pytest.raises(ValueError, match="cannot be written exactly"):
        dp.write_dta(far, tmp_path / "far.dta")
