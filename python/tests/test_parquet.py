"""read_parquet, write_parquet and read_meta on Parquet files (plan 0018).

- Every frame read_dta returns from compat/fixtures comes back from
  write_parquet and read_parquet equal (assert_frame_equal, and the
  attrs), except what Parquet does not record: a string column's strN
  width or strL, and the storage type of a %td or %tc column.
- Constructed frames cover what fixtures do not: every storage type with
  `.a` to `.z`, dates, time zones, categoricals, nullable dtypes, bytes.
- Every file in compat/parquet/fixtures (written by pyarrow, polars,
  DuckDB, arrow, nanoparquet, fastparquet, Parquet2.jl and
  hyparquet-writer) reads as compat/parquet/expected says, the values
  pyarrow reads.
- pyarrow, polars and DuckDB read back what write_parquet writes, where
  they are installed.
"""

import datetime
import decimal
import io
import json
import math
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

import dta_parser as dp
from conftest import fixture_paths
from dta_parser import StataArray, missing

ROOT = Path(__file__).resolve().parents[2]
PARQUET = ROOT / "compat" / "parquet"
TEXT = pd.Series(["a"]).dtype


def round_trip(df, **kw):
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        return dp.read_parquet(dp.write_parquet(df, **kw))


def same_attrs(a, b):
    """attrs["dta"] equal, but for what Parquet does not record."""
    a, b = dict(a), dict(b)
    for key in ("release", "byte_order", "encoding"):
        a.pop(key, None)
    assert set(a) == set(b)
    for key in a:
        if key == "columns":
            assert list(a[key]) == list(b[key])
            for name, col in a[key].items():
                other = dict(b[key][name])
                col = dict(col)
                if col["storage"].startswith("str"):
                    # The strN width, or strL, is chosen again for .dta.
                    assert other.pop("storage") in ("str", "strL"), name
                    col.pop("storage")
                elif dp.read_dta is not None and col.get("format", "").startswith(("%td", "%tc", "%-td", "%-tc")) \
                        and other["storage"] in ("long", "double"):
                    # A DATE or TIMESTAMP has no Stata storage type.
                    col.pop("storage")
                    other.pop("storage")
                assert col == other, name
        elif key == "value_labels":
            assert repr(a[key]) == repr(b[key])
        else:
            assert a[key] == b[key], key


@pytest.fixture(params=fixture_paths(), ids=lambda p: p.stem)
def dta(request):
    return request.param


def test_every_fixture_round_trips(dta, tmp_path):
    original = dp.read_dta(dta)
    path = tmp_path / "out.parquet"
    dp.write_parquet(original, path)
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        back = dp.read_parquet(path)
    pd.testing.assert_frame_equal(back, original)
    assert dp.missing_codes(back.iloc[:, 0]).tolist() == dp.missing_codes(original.iloc[:, 0]).tolist() \
        if len(original.columns) else True
    for name in original.columns:
        assert dp.missing_codes(back[name]).tolist() == dp.missing_codes(original[name]).tolist(), name
    same_attrs(original.attrs["dta"], back.attrs["dta"])


def test_every_fixture_reads_a_window_as_read_dta_does(dta, tmp_path):
    original = dp.read_dta(dta)
    path = tmp_path / "out.parquet"
    dp.write_parquet(original, path, row_group_size=3)
    n = len(original)
    for skip, n_max in [(0, 1), (1, 4), (n // 2, 5), (n - 1, 10), (n + 5, 2)]:
        a = dp.read_dta(dta, skip=skip, n_max=n_max)
        b = dp.read_parquet(path, skip=skip, n_max=n_max)
        pd.testing.assert_frame_equal(b, a)


def test_a_dta_frame_written_back_to_dta_matches(dta, tmp_path):
    """read_parquet's frame writes the same .dta file values as read_dta's."""
    original = dp.read_dta(dta)
    back = dp.read_parquet(dp.write_parquet(original))
    dp.write_dta(back, tmp_path / "again.dta")
    again = dp.read_dta(tmp_path / "again.dta")
    pd.testing.assert_frame_equal(again, original)


# ---------------------------------------------------------------- constructed

def labelled():
    df = pd.DataFrame({
        "b": pd.Series([1.0, missing.a, None, 3.0], dtype="stata[byte]"),
        "i": pd.Series([300.0, missing.b, 2.0, None], dtype="stata[int]"),
        "l": pd.Series([70000.0, missing.z, 1.0, 2.0], dtype="stata[long]"),
        "f": pd.Series([1.5, missing.c, 2.25, None], dtype="stata[float]"),
        "d": pd.Series([1e300, missing.d, None, -0.5], dtype="stata[double]"),
        "small": np.array([1, 2, 3, 4], dtype=np.int8),
        "byte_dot": np.array([1, np.nan, 3, 4], dtype=np.float32),
        "long_dot": np.array([1, np.nan, 3, 70000], dtype=np.float64),
        "day": pd.to_datetime(["2024-03-01", None, "1960-01-01", "1900-02-28"], format="ISO8601").astype("datetime64[s]"),
        "when": pd.to_datetime(["2024-03-01 09:30:00.125", None, "1960-01-01", "2001-09-09 01:46:40"], format="ISO8601").astype(
            "datetime64[ms]"),
        "s": ["a", "bb", "", "é"],
    })
    df.attrs["dta"] = {
        "label": "Every storage type",
        "timestamp": "04 Nov 2026 10:00",
        "notes": ["first", "second"],
        "characteristics": {"_dta": {"origin": "made here"}, "b": {"source": "q1"}},
        "sort_order": ["small"],
        "columns": {
            "b": {"storage": "byte", "format": "%8.0g", "label": "B", "value_labels": "yn"},
            "i": {"storage": "int", "format": "%8.0g", "label": "", "value_labels": ""},
            "l": {"storage": "long", "format": "%12.0g", "label": "", "value_labels": ""},
            "f": {"storage": "float", "format": "%9.0g", "label": "", "value_labels": ""},
            "d": {"storage": "double", "format": "%10.0g", "label": "", "value_labels": "yn"},
            "small": {"storage": "byte", "format": "%8.0g", "label": "", "value_labels": ""},
            "byte_dot": {"storage": "byte", "format": "%8.0g", "label": "", "value_labels": ""},
            "long_dot": {"storage": "long", "format": "%12.0g", "label": "", "value_labels": ""},
            "day": {"storage": "long", "format": "%td", "label": "Day", "value_labels": ""},
            "when": {"storage": "double", "format": "%tc", "label": "", "value_labels": ""},
            "s": {"storage": "str2", "format": "%-9s", "label": "", "value_labels": ""},
        },
        "value_labels": {"yn": {0: "No", 1: "Yes", 1.5: "half", missing.a: "Skipped", missing.d: "Don't know"}},
    }
    return df


def test_every_storage_type_with_letters_round_trips():
    df = labelled()
    back = round_trip(df)
    pd.testing.assert_frame_equal(back, df)
    for name in ("b", "i", "l", "f", "d"):
        assert back[name].dtype == df[name].dtype
        assert back[name].array.codes.tolist() == df[name].array.codes.tolist()
    info = back.attrs["dta"]
    assert info["label"] == "Every storage type"
    assert info["timestamp"] == "04 Nov 2026 10:00"
    assert info["notes"] == ["first", "second"]
    assert info["characteristics"] == {"_dta": {"origin": "made here"}, "b": {"source": "q1"}}
    assert info["sort_order"] == ["small"]
    assert info["value_labels"]["yn"][missing.a] == "Skipped"
    assert list(info["value_labels"]["yn"]) == [0, 1, 1.5, missing.a, missing.d]
    assert info["columns"]["b"] == {"storage": "byte", "format": "%8.0g", "label": "B", "value_labels": "yn"}
    assert info["columns"]["s"]["storage"] == "str"


def test_a_window_without_letters_has_the_storage_types_dtype():
    path = dp.write_parquet(labelled())
    part = dp.read_parquet(path, skip=2, n_max=2)
    assert part["b"].dtype == np.float32  # `.` in row 3
    assert part["l"].dtype == np.int32
    assert part["f"].dtype == np.float32
    assert part["d"].dtype == np.float64
    assert part["byte_dot"].dtype == np.int8
    assert part.attrs["dta"]["columns"]["l"]["storage"] == "long"


def test_missing_letters_false_writes_nulls():
    back = dp.read_parquet(dp.write_parquet(labelled(), missing_letters=False))
    assert back["b"].dtype == np.float32
    assert back["b"].isna().tolist() == [False, True, True, False]
    assert back["d"].dtype == np.float64


def test_selection_by_name_and_position():
    raw = dp.write_parquet(labelled())
    df = dp.read_parquet(raw, columns=["s", 0, "s"])
    assert list(df.columns) == ["s", "b"]
    assert list(df.attrs["dta"]["columns"]) == ["s", "b"]
    assert list(dp.read_parquet(raw, columns="d").columns) == ["d"]
    with pytest.raises(KeyError, match='"nope" is not in the file; its columns are "b", "i"'):
        dp.read_parquet(raw, columns=["nope"])
    with pytest.raises(IndexError, match="no column 99"):
        dp.read_parquet(raw, columns=[99])
    with pytest.raises(TypeError):
        dp.read_parquet(raw, columns=[True])


def test_sources_path_bytes_and_file_objects(tmp_path):
    df = labelled()
    path = tmp_path / "x.parquet"
    assert dp.write_parquet(df, path) is None
    raw = path.read_bytes()
    for source in (path, str(path), raw, bytearray(raw), io.BytesIO(raw), open(path, "rb")):
        pd.testing.assert_frame_equal(dp.read_parquet(source), df)
    assert dp.read_meta(io.BytesIO(raw))["nobs"] == 4
    with pytest.raises(FileNotFoundError):
        dp.read_parquet(tmp_path / "missing.parquet")
    with pytest.raises(TypeError):
        dp.read_parquet(42)


def test_rows_past_the_end_and_empty_frames():
    raw = dp.write_parquet(labelled())
    assert len(dp.read_parquet(raw, skip=10)) == 0
    assert list(dp.read_parquet(raw, skip=10).columns) == list(labelled().columns)
    empty = labelled().iloc[:0]
    back = round_trip(empty.reset_index(drop=True))
    assert len(back) == 0 and list(back.columns) == list(empty.columns)
    nothing = pd.DataFrame(index=range(3))
    assert dp.read_parquet(dp.write_parquet(nothing)).shape == (3, 0)


def test_other_dtypes():
    df = pd.DataFrame({
        "i64": np.array([1, -(2**62), 3], dtype=np.int64),
        "I64": pd.array([1, None, 3], dtype="Int64"),
        "I8": pd.array([1, None, 3], dtype="Int8"),
        "u8": np.array([0, 255, 3], dtype=np.uint8),
        "u64": np.array([0, 2**63 - 1, 3], dtype=np.uint64),
        "flag": np.array([True, False, True]),
        "flag_na": pd.array([True, None, False], dtype="boolean"),
        "F32": pd.array([1.5, None, 2.0], dtype="Float32"),
        "half": np.array([1, 2, 3], dtype=np.float16),
        "cat": pd.Categorical(["b", None, "a"], categories=["c", "b", "a"]),
        "ord": pd.Categorical(["lo", "hi", "lo"], categories=["lo", "mid", "hi"], ordered=True),
        "zoned": pd.to_datetime(["2024-03-01 09:30", None, "2024-07-01 12:00"], format="ISO8601").tz_localize("America/New_York"),
        "utc_us": pd.to_datetime(["2024-03-01 09:30:00.000001", None, "1960-01-01"], format="ISO8601").tz_localize("UTC")
        .astype("datetime64[us, UTC]"),
        "naive_ns": pd.to_datetime(["2024-03-01 09:30:00.000000001", None, "1960-01-01"], format="ISO8601").astype("datetime64[ns]"),
        "secs": pd.to_datetime(["2024-03-01 09:30:01", None, "1900-01-01"], format="ISO8601").astype("datetime64[s]"),
        "blob": np.array([b"\x00\x01", None, b""], dtype=object),
        "mixed": np.array(["text", b"\xff", None], dtype=object),
        "text_na": pd.array(["x", None, "z"], dtype=TEXT),
    })
    back = round_trip(df)
    assert back["i64"].dtype == np.int64 and back["i64"].tolist() == df["i64"].tolist()
    assert back["I64"].dtype == pd.Int64Dtype() and back["I64"].isna().tolist() == [False, True, False]
    assert back["I8"].dtype == np.float32  # INT(8) with a null, as read_dta gives `.`
    assert back["u8"].dtype == np.int16 and back["u8"].tolist() == [0, 255, 3]
    assert back["u64"].dtype == np.int64 and back["u64"].tolist() == [0, 2**63 - 1, 3]
    assert back["flag"].dtype == bool and back["flag"].tolist() == [True, False, True]
    assert back["flag_na"].dtype == pd.BooleanDtype() and back["flag_na"].isna().tolist() == [False, True, False]
    assert back["F32"].dtype == np.float32 and np.isnan(back["F32"][1])
    assert back["half"].dtype == np.float32
    pd.testing.assert_series_equal(back["cat"], df["cat"])
    pd.testing.assert_series_equal(back["ord"], df["ord"])
    for name in ("zoned", "utc_us", "naive_ns", "secs"):
        pd.testing.assert_series_equal(back[name], df[name], check_names=True)
    assert back["blob"].tolist() == [b"\x00\x01", None, b""]
    assert back["mixed"].tolist() == [b"text", b"\xff", None]
    assert back["text_na"].dtype == TEXT and back["text_na"].isna().tolist() == [False, True, False]
    meta = dp.read_meta(dp.write_parquet(df))
    for name in df.columns:
        if name != "mixed":
            assert meta["columns"][name]["dtype"] == str(back[name].dtype), name


def test_zones_of_every_kind():
    for tz in ("UTC", "Europe/Paris", datetime.timezone.utc, datetime.timezone(datetime.timedelta(hours=5, minutes=30))):
        s = pd.Series(pd.to_datetime(["2024-03-01 09:30"], format="ISO8601").tz_localize(tz))
        back = round_trip(pd.DataFrame({"t": s}))["t"]
        assert back.iloc[0] == s.iloc[0]
        assert back.dt.tz is not None


def test_errors_on_write():
    with pytest.raises(ValueError, match="row 2 is not midnight.*drop the format"):
        df = pd.DataFrame({"d": pd.to_datetime(["2024-01-01", "2024-01-01 12:00"], format="ISO8601")})
        df.attrs["dta"] = {"columns": {"d": {"format": "%td"}}}
        dp.write_parquet(df)
    with pytest.raises(ValueError, match="time zone"):
        df = pd.DataFrame({"d": pd.to_datetime(["2024-01-01"], format="ISO8601").tz_localize("UTC")})
        df.attrs["dta"] = {"columns": {"d": {"format": "%td"}}}
        dp.write_parquet(df)
    with pytest.raises(TypeError, match="'t'.*timedelta64"):
        dp.write_parquet(pd.DataFrame({"t": pd.to_timedelta([1], unit="s")}))
    with pytest.raises(TypeError, match="'c'.*not text"):
        dp.write_parquet(pd.DataFrame({"c": pd.Categorical([1, 2])}))
    with pytest.raises(TypeError, match='"o": row 2 holds a int'):
        dp.write_parquet(pd.DataFrame({"o": np.array(["a", 1], dtype=object)}))
    with pytest.raises(ValueError, match="unknown compression"):
        dp.write_parquet(pd.DataFrame({"x": [1]}), compression="lzo")
    with pytest.raises(ValueError, match="zstd levels"):
        dp.write_parquet(pd.DataFrame({"x": [1]}), compression="zstd", compression_level=99)
    with pytest.raises(ValueError, match="more than a 64-bit integer holds"):
        dp.write_parquet(pd.DataFrame({"u": np.array([2**63], dtype=np.uint64)}))
    with pytest.raises(ValueError, match="appears more than once"):
        dp.write_parquet(pd.DataFrame([[1, 2]], columns=["a", "a"]))
    with pytest.raises(TypeError, match="column names must be text"):
        dp.write_parquet(pd.DataFrame({0: [1]}))
    with pytest.raises(ValueError, match="row_group_size"):
        dp.write_parquet(pd.DataFrame({"x": [1]}), row_group_size=0)
    with pytest.raises(TypeError, match='"x": row 1 holds a MissingValue'):
        dp.write_parquet(pd.DataFrame({"x": pd.Series([missing.a], dtype="stata[double]")}).astype(object))


def test_compression_and_row_groups(tmp_path):
    df = pd.DataFrame({"x": np.arange(10, dtype=np.int32), "s": [f"v{i % 3}" for i in range(10)]})
    for codec in ("snappy", "zstd", "gzip", "lz4_raw", "none"):
        raw = dp.write_parquet(df, compression=codec)
        assert dp.read_meta(raw)["compression"] == [codec]
        pd.testing.assert_frame_equal(dp.read_parquet(raw), df, check_dtype=False)
    raw = dp.write_parquet(df, compression="zstd", compression_level=9, row_group_size=4)
    assert [g["rows"] for g in dp.read_meta(raw)["row_groups"]] == [4, 4, 2]


def test_the_index_rule():
    df = pd.DataFrame({"x": [1, 2]}, index=pd.Index(["a", "b"], name="key"))
    with pytest.warns(UserWarning, match="not the index 'key'; call df.reset_index"):
        raw = dp.write_parquet(df)
    assert dp.read_parquet(raw).index.equals(pd.RangeIndex(2))
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        dp.write_parquet(df.reset_index())
    pandas_written = io.BytesIO()
    pytest.importorskip("pyarrow")
    df.to_parquet(pandas_written)
    back = dp.read_parquet(pandas_written.getvalue())
    assert list(back.columns) == ["x", "key"]
    assert back.set_index("key").index.tolist() == ["a", "b"]


def test_meta_of_both_formats(tmp_path):
    df = labelled()
    del df.attrs["dta"]["value_labels"]["yn"][1.5]  # .dta labels only integers
    dp.write_parquet(df, tmp_path / "x.parquet")
    dp.write_dta(df, tmp_path / "x.dta")
    m = dp.read_meta(tmp_path / "x.parquet")
    d = dp.read_meta(tmp_path / "x.dta")
    assert m["nobs"] == d["nobs"] == 4
    assert m["format"] == "parquet" and "format" not in d
    assert m["compression"] == ["snappy"] and m["created_by"].startswith("dta-parquet")
    assert m["row_groups"] == [{"rows": 4, "compressed_bytes": m["row_groups"][0]["compressed_bytes"],
                                "uncompressed_bytes": m["row_groups"][0]["uncompressed_bytes"]}]
    b = m["columns"]["b"]
    assert b["role"] == "data" and b["physical_type"] == "DOUBLE" and b["dtype"] == "stata[byte]"
    assert b["label"] == "B" and b["value_labels"] == "yn" and b["storage"] == "byte"
    assert m["columns"]["small"]["logical_type"] == "INT(8, signed)"
    assert m["columns"]["day"]["dtype"] == "datetime64[s]" and m["columns"]["day"]["logical_type"] == "DATE"
    assert m["columns"]["s"]["dtype"] == "str"
    assert m["label"] == d["label"] and m["notes"] == d["notes"]
    assert dp.read_meta((tmp_path / "x.dta").read_bytes())["nobs"] == 4
    assert dp.read_meta(open(tmp_path / "x.dta", "rb"))["nobs"] == 4


def test_damaged_profile_is_a_warning(tmp_path):
    pq = pytest.importorskip("pyarrow.parquet")
    raw = dp.write_parquet(labelled())
    table = pq.read_table(io.BytesIO(raw))
    meta = dict(pq.ParquetFile(io.BytesIO(raw)).metadata.metadata)
    profile = json.loads(meta[b"dta"])
    profile["columns"]["small"] = {"storage": "int"}  # not a DOUBLE column
    meta[b"dta"] = json.dumps(profile).encode()
    pq.write_table(table.replace_schema_metadata(meta), tmp_path / "edited.parquet")
    with pytest.warns(UserWarning, match='dropped "columns.small.storage"'):
        back = dp.read_parquet(tmp_path / "edited.parquet")
    assert back["small"].dtype == np.int8
    meta[b"dta"] = b"{not json"
    pq.write_table(table.replace_schema_metadata(meta), tmp_path / "broken.parquet")
    with pytest.warns(UserWarning, match="not JSON"):
        back = dp.read_parquet(tmp_path / "broken.parquet")
    assert back.attrs["dta"]["label"] == ""


def test_not_parquet():
    with pytest.raises(ValueError, match="not a Parquet file"):
        dp.read_parquet(b"PAR1 but not really a file at all PAR1x")
    with pytest.raises(ValueError, match="nested"):
        dp.read_parquet(dp.write_parquet(labelled()), nested="maybe")


def test_letters_keep_their_order_through_polars_style_sort():
    df = pd.DataFrame({"x": pd.Series([missing.z, 1.0, missing.a, None], dtype="stata[double]")})
    back = round_trip(df.sort_values("x").reset_index(drop=True))
    assert [str(v) for v in back["x"]] == ["1.0", "nan", ".a", ".z"]


def test_large_frames_on_threads(monkeypatch):
    monkeypatch.setenv("DTA_THREADS", "4")
    n = 200_000
    rng = np.random.default_rng(1)
    df = pd.DataFrame({
        "a": rng.integers(-100, 100, n).astype(np.int8),
        "b": rng.normal(size=n),
        "c": pd.Series(np.where(rng.random(n) < 0.1, np.nan, rng.normal(size=n))),
        "s": pd.array(np.array(["alpha", "beta", "gamma", "delta"], dtype=object)[rng.integers(0, 4, n)],
                      dtype=TEXT),
        "u": pd.array([f"id{i}" for i in range(n)], dtype=TEXT),
        "m": StataArray(np.where(rng.random(n) < 0.05, np.nan, 1.0), np.where(rng.random(n) < 0.05, 3, 0)),
    })
    back = dp.read_parquet(dp.write_parquet(df, row_group_size=50_000))
    pd.testing.assert_frame_equal(back, df)
    part = dp.read_parquet(dp.write_parquet(df, row_group_size=50_000), skip=123_456, n_max=1000)
    pd.testing.assert_frame_equal(part, df.iloc[123_456:124_456].reset_index(drop=True))


# ---------------------------------------------------------------- other writers

def expected_files():
    return sorted((PARQUET / "expected").glob("*.json"))


def as_expected(series, arrow_type):
    """Our column as compat/parquet/expected.py writes pyarrow's."""
    out = []
    if arrow_type.startswith("date32"):
        for v in series:
            out.append(None if pd.isna(v) else int(np.datetime64(v, "s").astype(np.int64) // 86400))
        return out
    if arrow_type.startswith("timestamp"):
        unit = arrow_type[len("timestamp["):].split(",")[0].rstrip("]")
        values = series.array
        if getattr(series.dtype, "tz", None) is not None:
            values = values.tz_convert(None)
        values = np.asarray(values).astype(f"datetime64[{unit}]")
        nat = np.isnat(values)
        return [None if n else int(v) for v, n in zip(values.view(np.int64), nat)]
    if arrow_type.startswith(("time32", "time64")):
        return [None if pd.isna(v) else int(v.astype(np.int64)) for v in series.to_numpy()]
    if arrow_type.startswith("decimal"):
        return [None if v is None or (isinstance(v, float) and math.isnan(v)) else v for v in series]
    for v in series.astype(object):
        if v is None or (isinstance(v, float) and math.isnan(v)) or v is pd.NA:
            out.append(None)
        elif isinstance(v, (bytes, bytearray)):
            out.append(list(v))
        elif isinstance(v, (bool, np.bool_)):
            out.append(bool(v))
        elif isinstance(v, (int, np.integer)):
            out.append(int(v))
        elif isinstance(v, (float, np.floating)):
            out.append(float(v))
        else:
            out.append(v)
    return out


@pytest.mark.parametrize("path", expected_files(), ids=lambda p: p.stem)
def test_files_from_other_tools_read_as_pyarrow_reads_them(path):
    expected = json.loads(path.read_text())
    source = PARQUET / "fixtures" / (path.stem + ".parquet")
    if expected.get("nested"):
        with pytest.raises(ValueError, match="nested"):
            dp.read_parquet(source)
        df = dp.read_parquet(source, nested="skip")
        assert not set(expected["nested"]) & set(df.columns)
        meta = dp.read_meta(source)
        assert {n for n, c in meta["columns"].items() if c["role"] == "nested"} == set(expected["nested"])
    else:
        df = dp.read_parquet(source)
    assert len(df) == expected["rows"]
    assert list(df.columns) == [c["name"] for c in expected["columns"]]
    meta = dp.read_meta(source)
    try:
        import pyarrow.parquet as pq
        footer = pq.ParquetFile(source).metadata
    except ImportError:
        footer = None
    for col in expected["columns"]:
        name, arrow_type, want = col["name"], col["arrow_type"], col["values"]
        got = df[name]
        # read_meta's dtype comes from the footer's null counts, where the
        # writer gave them.
        counted = footer is not None and name in footer.schema.names and all(
            s is not None and s.has_null_count
            for s in (footer.row_group(g).column(footer.schema.names.index(name)).statistics
                      for g in range(footer.num_row_groups)))
        if counted or not any(v is None for v in want):
            assert meta["columns"][name]["dtype"] == str(got.dtype) or got.dtype == object, name
        if arrow_type.startswith(("decimal128(", "decimal256(")):
            precision = int(arrow_type.split("(")[1].split(",")[0])
            for g, w in zip(got, want):
                if w is None:
                    assert g is None or (isinstance(g, float) and math.isnan(g)), name
                elif precision <= 15:
                    assert g == float(decimal.Decimal(w)), name
                else:
                    assert isinstance(g, decimal.Decimal) and g == decimal.Decimal(w), name
            continue
        if arrow_type.startswith("dictionary<values=string"):
            assert isinstance(got.dtype, pd.CategoricalDtype) and not got.dtype.ordered
            seen = []
            for v in want:
                if v is not None and v not in seen:
                    seen.append(v)
            assert got.cat.categories.tolist() == seen, name
        mine = as_expected(got, arrow_type)
        if arrow_type in ("binary", "large_binary") and got.dtype != object:
            # ENUM: pyarrow reads bytes, we read text.
            mine = [None if v is None else list(v.encode()) for v in mine]
        if arrow_type in ("float", "double") or (got.dtype.kind == "f" and arrow_type != "x"):
            # A null and NaN are both NaN in a pandas float column.
            mine = ["NaN" if v is None else v for v in mine]
            want = ["NaN" if v is None else v for v in want]
        assert mine == want, name


def test_a_window_of_another_tools_file(tmp_path):
    source = PARQUET / "fixtures" / "pyarrow_small_pages.parquet"
    whole = dp.read_parquet(source)
    for skip, n_max in [(0, 7), (199, 3), (450, 400), (590, 100)]:
        part = dp.read_parquet(source, skip=skip, n_max=n_max)
        for name in whole.columns:
            a, b = part[name], whole[name].iloc[skip:skip + n_max].reset_index(drop=True)
            if isinstance(a.dtype, pd.CategoricalDtype):
                a, b = a.astype(object), b.astype(object)
            assert as_expected(a, "x") == as_expected(b, "x") or a.dtype.kind in "fiu" and np.allclose(
                a.astype(float), b.astype(float), equal_nan=True), name


# ---------------------------------------------------------------- other readers

def test_pyarrow_reads_our_files():
    pa = pytest.importorskip("pyarrow")
    pq = pytest.importorskip("pyarrow.parquet")
    df = labelled()
    for name in ("cat", "ord"):
        df[name] = pd.Categorical(["b", None, "a", "b"], categories=["c", "b", "a"], ordered=name == "ord")
    df["zoned"] = pd.to_datetime(["2024-03-01 09:30", None, "2024-07-01", "2001-01-01"], format="ISO8601").tz_localize("Asia/Tokyo")
    raw = dp.write_parquet(df)
    table = pq.read_table(io.BytesIO(raw))
    assert b"dta" in pq.ParquetFile(io.BytesIO(raw)).metadata.metadata
    assert table.schema.field("b").type == pa.float64()  # .a to .z: DOUBLE, NaN
    assert table.schema.field("small").type == pa.int8()
    assert table.schema.field("ord").type.ordered
    assert table.schema.field("zoned").type.tz == "Asia/Tokyo"
    pdf = table.to_pandas()
    assert pdf["b"].isna().tolist() == [False, True, True, False]
    assert pdf["ord"].cat.categories.tolist() == ["c", "b", "a"]
    assert pdf["s"].tolist() == df["s"].tolist()
    assert np.isnan(table.column("b").to_numpy(zero_copy_only=False)[1])


def test_polars_reads_our_files():
    pl = pytest.importorskip("polars")
    df = labelled()
    df["cat"] = pd.Categorical(["b", None, "a", "b"], categories=["c", "b", "a"])
    out = pl.read_parquet(io.BytesIO(dp.write_parquet(df)))
    assert out["b"].null_count() == 1 and out["b"].is_nan().sum() == 1  # `.` null, .a NaN
    assert (out["b"].is_null() | out["b"].is_nan()).to_list() == [False, True, True, False]
    assert out["small"].dtype == pl.Int8
    assert out["s"].to_list() == ["a", "bb", "", "é"]
    assert out["cat"].dtype == pl.Categorical


def test_duckdb_reads_our_files(tmp_path):
    duckdb = pytest.importorskip("duckdb")
    path = tmp_path / "x.parquet"
    dp.write_parquet(labelled(), path)
    con = duckdb.connect()
    nulls, missing_ = con.execute(
        "SELECT count(*) FILTER (WHERE b IS NULL), count(*) FILTER (WHERE b IS NULL OR isnan(b)) FROM read_parquet(?)",
        [str(path)]).fetchone()
    assert (nulls, missing_) == (1, 2)
    kinds = dict(con.execute("SELECT column_name, column_type FROM (DESCRIBE SELECT * FROM read_parquet(?))",
                             [str(path)]).fetchall())
    assert kinds["small"] == "TINYINT" and kinds["day"] == "DATE" and kinds["s"] == "VARCHAR"
