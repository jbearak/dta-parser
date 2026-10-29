"""read_dta's representation: dtypes, metadata, columns, row windows, dates."""

import numpy as np
import pandas as pd
import pytest

import dta_parser as dp
from conftest import FIXTURES, fixture_paths
from dta_parser import StataArray, missing, read_dta, read_meta

TEXT = pd.Series(["a"]).dtype


def test_numbers_keep_their_width_without_missing_values():
    df = read_dta(FIXTURES / "pandas_118_le.dta")
    assert df["i8"].dtype == np.int8
    assert df["i16"].dtype == np.int16
    assert df["i32"].dtype == np.int32
    assert df["f32"].dtype == np.float32
    assert df["f64"].dtype == np.float64
    assert df["s"].dtype == TEXT


def test_only_system_missing_gives_floats_with_nan():
    df = read_dta(FIXTURES / "readstat_111.dta")
    storage = {k: v["storage"] for k, v in df.attrs["dta"]["columns"].items()}
    assert storage["i"] == "int" and df["i"].dtype == np.float32
    assert storage["l"] == "long" and df["l"].dtype == np.float64
    assert storage["f"] == "float" and df["f"].dtype == np.float32
    assert storage["d"] == "double" and df["d"].dtype == np.float64
    assert df["i"].isna().tolist() == [False, False, True, False, False]
    # Exact: int16 and int32 values survive the float conversion.
    assert df["i"].tolist()[:2] == [1000.0, -32000.0]
    assert df["l"].tolist()[:3] == [1.0, -2000000000.0, 2000000000.0]


def test_extended_missing_values_give_a_stata_array():
    df = read_dta(FIXTURES / "haven_118.dta")
    num = df["num"]
    assert isinstance(num.array, StataArray)
    assert num.dtype == dp.StataDtype("double")
    assert num.array.codes.tolist() == [0, 0, 1, 2, 27, 0]
    assert num[0] == 1.5
    assert np.isnan(num[2])
    assert num[3] is missing.a
    assert num[4] is missing.z
    assert num.isna().tolist() == [False, False, True, True, True, False]


def test_metadata_is_in_attrs():
    df = read_dta(FIXTURES / "haven_118.dta")
    meta = df.attrs["dta"]
    assert meta["release"] == 118
    assert meta["label"] == "haven fixture"
    assert meta["columns"]["num"] == {
        "storage": "double", "format": "%10.0g",
        "label": "A double with extended missing values", "value_labels": "",
    }
    assert meta["columns"]["answer"]["value_labels"] == "answer"
    assert meta["value_labels"]["answer"] == {1: "Yes", 2: "No", missing.d: "Don't know", missing.g: "Not in universe"}
    assert list(meta["columns"]) == list(df.columns)


def test_read_meta_reads_no_data():
    meta = read_meta(FIXTURES / "haven_118.dta")
    assert meta["nobs"] == 6
    assert list(meta["columns"]) == ["row", "num", "answer", "count", "text", "day", "big"]
    assert meta["columns"]["big"]["storage"] == "strL"


def test_columns_by_name_or_index_in_the_order_given():
    path = FIXTURES / "haven_118.dta"
    full = read_dta(path)
    part = read_dta(path, columns=["text", 1, "row", "row"])
    assert list(part.columns) == ["text", "num", "row"]
    assert list(part.attrs["dta"]["columns"]) == ["text", "num", "row"]
    assert part["text"].tolist() == full["text"].tolist()
    assert part["num"].array.equals(full["num"].array)
    assert list(read_dta(path, columns="row").columns) == ["row"]
    with pytest.raises(ValueError, match="no column named 'nope'"):
        read_dta(path, columns=["nope"])
    with pytest.raises(IndexError):
        read_dta(path, columns=[7])
    with pytest.raises(TypeError):
        read_dta(path, columns=[True])


@pytest.mark.parametrize("path", fixture_paths(), ids=lambda p: p.stem)
def test_skip_and_n_max_read_a_window_of_rows(path):
    full = read_dta(path)
    n = len(full)
    for skip, n_max in [(0, None), (1, 2), (n - 1, 5), (n + 3, 1), (0, 0), (2, None)]:
        part = read_dta(path, skip=skip, n_max=n_max)
        rows = list(range(n))[skip:][: n if n_max is None else n_max]
        assert len(part) == len(rows)
        for name in full.columns:
            expected = full[name].iloc[rows].reset_index(drop=True)
            got = part[name]
            if isinstance(full[name].array, StataArray):
                codes = full[name].array.codes[rows]
                if isinstance(got.array, StataArray):
                    assert got.array.codes.tolist() == codes.tolist()
                else:
                    # A window without .a to .z reads narrower.
                    assert codes.max(initial=0) <= 1
                    assert got.isna().tolist() == (codes == 1).tolist()
            assert cells(got) == cells(expected), name


def cells(series):
    """Values as floats (a window may read a narrower dtype), NaN and NaT as None."""
    out = []
    for v in series.tolist():
        if isinstance(v, (int, float, np.number)) and not isinstance(v, bool):
            out.append(None if v != v else float(v))
        else:
            out.append(None if v is pd.NaT else v)
    return out


def test_bad_windows_are_errors():
    path = FIXTURES / "haven_118.dta"
    with pytest.raises(ValueError):
        read_dta(path, skip=-1)
    with pytest.raises(ValueError):
        read_dta(path, n_max=-2)
    with pytest.raises(TypeError):
        read_dta(path, skip="1")


def test_missing_file_and_bad_encoding():
    with pytest.raises(FileNotFoundError):
        read_dta(FIXTURES / "nope.dta")
    with pytest.raises(ValueError, match="unknown encoding"):
        read_dta(FIXTURES / "haven_113.dta", encoding="klingon")


def test_encoding_before_118():
    # haven stored the text as UTF-8; byte 0x87 (in 中文) differs between
    # Windows-1252 and Latin-1.
    path = FIXTURES / "haven_114.dta"
    assert read_dta(path, encoding="utf-8")["text"][2] == "中文"
    assert "‡" in read_dta(path)["text"][2]
    assert "\x87" in read_dta(path, encoding="latin1")["text"][2]


def test_dates_convert_unless_asked_not_to():
    path = FIXTURES / "haven_118.dta"
    df = read_dta(path)
    raw = read_dta(path, dates=False)
    assert df["day"].dtype == "datetime64[s]"
    days = raw["day"].to_numpy()
    expected = [pd.NaT if d != d else pd.Timestamp("1960-01-01") + pd.Timedelta(days=int(d)) for d in days]
    assert df["day"].tolist() == expected
    assert raw["day"].dtype.kind == "f"
    # pandas' reading of the same dates.
    theirs = pd.read_stata(path, convert_dates=True)["day"]
    assert [None if pd.isna(a) else pd.Timestamp(a) for a in df["day"]] == [
        None if pd.isna(b) else pd.Timestamp(b) for b in theirs
    ]

