"""read_parquet, read_parquet_info and save_parquet (plan 0019), in
pandas (plan 0024, stage 4).

- Every frame `read_dta` gives from compat/fixtures comes back from
  save_parquet and read_parquet equal (`assert_frame_equal`, dtypes
  checked, codes too) with an equal Meta, with letters=True and False.
- Constructed frames cover what fixtures do not: every row of the plan's
  read and write tables, and what save_parquet refuses.
- Every file in compat/parquet/fixtures (written by pyarrow, polars,
  DuckDB, arrow, nanoparquet, fastparquet, Parquet2.jl and
  hyparquet-writer) reads as compat/parquet/expected says (the values
  pyarrow reads).
- pyarrow, polars and DuckDB read back what save_parquet writes.
"""

import datetime as dt
import decimal
import io
import json
import math
import struct
import warnings

import numpy as np
import pandas as pd
import pytest

import datakit as dk
from conftest import PARQUET, assert_same, fixture_paths, is_text, lettered, tags
from dta_parser import DtaArray, missing


def quiet(fn, *args, **kw):
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        return fn(*args, **kw)


def round_trip(df, meta=None, **kw):
    read_kw = {k: kw.pop(k) for k in ("letters", "factors", "timestamps") if k in kw}
    return quiet(dk.read_parquet, quiet(dk.save_parquet, df, meta=meta, **kw), **read_kw)


def tagged_float(letter):
    return struct.unpack("<d", struct.pack("<Q", 0x7FF0_0000_0000_07A2 | (ord(letter[-1]) << 32)))[0]


@pytest.mark.parametrize("letters", [True, False])
@pytest.mark.parametrize("path", fixture_paths(), ids=lambda p: p.stem)
def test_every_fixture_round_trips(path, letters, tmp_path):
    df, meta = dk.read_dta(path, letters=letters, timestamps="truncate")
    out = tmp_path / "out.parquet"
    quiet(dk.save_parquet, df, out, meta=meta)
    back, back_meta = quiet(dk.read_parquet, out, letters=letters)
    assert_same(back, df)
    assert back_meta == meta


@pytest.mark.parametrize("path", fixture_paths(), ids=lambda p: p.stem)
def test_every_fixture_reads_a_window_as_read_dta_does(path, tmp_path):
    df, meta = dk.read_dta(path, timestamps="truncate")
    out = tmp_path / "out.parquet"
    dk.save_parquet(df, out, meta=meta, row_group_size=3)
    n = len(df)
    for skip, n_max in [(0, 1), (1, 4), (n // 2, 5), (max(n - 1, 0), 10), (n + 5, 2)]:
        a, am = dk.read_dta(path, skip=skip, n_max=n_max, timestamps="truncate")
        b, bm = dk.read_parquet(out, skip=skip, n_max=n_max)
        assert_same(b, a)
        assert bm == am


# ---------------------------------------------------------------- constructed

STORAGE = {"b": "byte", "i": "int", "l": "long", "f": "float", "d": "double"}


def labelled():
    """A frame of every Stata storage type with letters, as a read gives
    it (DtaArray columns of each storage type), and its Meta."""
    df = pd.DataFrame({
        "b": lettered([1, None, None, 3], [None, ".a", None, None], storage="byte"),
        "i": lettered([300, None, 2, None], [None, ".b", None, None], storage="int"),
        "l": lettered([70000, None, 1, 2], [None, ".z", None, None], storage="long"),
        "f": lettered([1.5, None, 2.25, None], [None, ".c", None, None], storage="float"),
        "d": lettered([1e300, None, None, -0.5], [None, ".d", None, None]),
        "small": np.array([1, 2, 3, 4], dtype=np.int8),
        "day": lettered([23436, None, 0, -21857], [None, ".e", None, None]),
        "when": pd.Series([dt.datetime(2024, 3, 1, 9, 30, 0, 125000), None, dt.datetime(1960, 1, 1),
                           dt.datetime(2001, 9, 9, 1, 46, 40)], dtype="datetime64[ms]"),
        "s": ["a", "bb", "", "é"],
    })
    meta = dk.Meta(
        label="Every storage type",
        timestamp="04 Nov 2026 10:00",
        notes=["first", "second"],
        characteristics={"_dta": {"origin": "made here"}, "b": {"source": "q1"}},
        sort=["small"],
        columns={
            "b": dk.Column("B", "%8.0g", "yn"), "i": dk.Column(None, "%8.0g"), "l": dk.Column(format="%12.0g"),
            "f": dk.Column(format="%9.0g"), "d": dk.Column(format="%10.0g", value_labels="yn"),
            "small": dk.Column(format="%8.0g"), "day": dk.Column("Day", "%td"), "when": dk.Column(format="%tc"),
            "s": dk.Column(format="%-9s"),
        },
        value_labels={"yn": {0: "No", 1: "Yes", 1.5: "half", ".a": "Skipped", ".d": "Don't know"}},
        rows=4,
    )
    return df, meta


def test_every_storage_type_with_letters_round_trips():
    df, meta = labelled()
    back, back_meta = round_trip(df, meta)
    assert_same(back, df)
    assert back_meta == meta
    assert {c: back[c].dtype.storage for c in STORAGE} == STORAGE
    assert back_meta.value_labels["yn"] == {0: "No", 1: "Yes", 1.5: "half", ".a": "Skipped", ".d": "Don't know"}
    assert list(back_meta.value_labels["yn"]) == [0, 1, 1.5, ".a", ".d"]
    assert tags(back["b"]) == [None, ".a", None, None]


def test_a_value_that_no_longer_fits_widens():
    df, meta = labelled()
    df.loc[0, "b"] = 1000.0  # past byte: int
    df.loc[0, "i"] = 0.5  # not whole: float
    df.loc[0, "f"] = 1 / 3  # not a float exactly: double
    back, _ = round_trip(df, meta)
    assert back["b"].dtype == "dta[int]" and back["i"].dtype == "dta[float]" and back["f"].dtype == "dta[double]"
    assert back["b"][0] == 1000 and back["i"][0] == 0.5 and back["f"][0] == 1 / 3
    assert tags(back["b"]) == [None, ".a", None, None]
    info = dk.read_parquet_info(dk.save_parquet(df, meta=meta)).columns.set_index("name")["storage"]
    assert (info["b"], info["i"]) == ("int", "float") and pd.isna(info["f"])


def test_letters_survive_pandas_row_operations():
    df, meta = labelled()
    changed = (df[df["small"] > 1]
               .sort_values("small", ascending=False)
               .merge(pd.DataFrame({"small": np.array([2, 3, 4], dtype=np.int8), "k": [1, 2, 3]}), on="small"))
    changed = pd.concat([changed, changed], ignore_index=True)
    assert tags(changed["b"]) == [None, None, ".a"] * 2
    assert tags(changed["day"]) == [None, None, ".e"] * 2
    meta.sort = []
    back, _ = round_trip(changed, meta.select(list(df.columns)))
    assert_same(back, changed)


def test_a_window_without_letters():
    df, meta = labelled()
    raw = dk.save_parquet(df, meta=meta)
    part, pm = dk.read_parquet(raw, skip=2, n_max=2)
    # Rows 3 and 4: no letters; l has no missing value, so it is its
    # numpy type; the others keep `.` in a DtaArray of their storage.
    assert part["l"].dtype == np.int32 and part["l"].tolist() == [1, 2]
    assert part["b"].dtype == "dta[byte]" and part["b"].array.codes.tolist() == [1, 0]
    assert part["f"].dtype == "dta[float]" and part["i"].dtype == "dta[int]"
    assert pm.rows == 2


def test_missing_letters_false_writes_dots():
    df, meta = labelled()
    back, bm = round_trip(df, meta, missing_letters=False)
    for c in ("b", "i", "l", "f", "d", "day"):
        assert back[c].array.codes.tolist() == [min(x, 1) for x in df[c].array.codes.tolist()], c
    assert bm == meta


def test_selection_by_name_and_position():
    df, meta = labelled()
    raw = dk.save_parquet(df, meta=meta)
    part, pm = dk.read_parquet(raw, columns=["s", 0, "s"])
    assert list(part.columns) == ["s", "b"] and list(pm.columns) == ["s", "b"]
    assert tags(part["b"]) == [None, ".a", None, None] and part["b"].dtype == "dta[byte]"
    assert list(dk.read_parquet(raw, columns="d")[0].columns) == ["d"]
    with pytest.raises(KeyError, match='"nope" is not in the file; its columns are "b", "i"'):
        dk.read_parquet(raw, columns=["nope"])
    with pytest.raises(IndexError, match="no column 99"):
        dk.read_parquet(raw, columns=[99])
    with pytest.raises(TypeError):
        dk.read_parquet(raw, columns=[True])


def test_sources_path_bytes_and_file_objects(tmp_path):
    df, meta = labelled()
    path = tmp_path / "x.parquet"
    assert dk.save_parquet(df, path, meta=meta) is None
    raw = path.read_bytes()
    with open(path, "rb") as fh:
        for source in (path, str(path), raw, bytearray(raw), memoryview(raw), io.BytesIO(raw), fh):
            got, gm = dk.read_parquet(source)
            assert_same(got, df)
            assert gm == meta
    assert dk.read_parquet_info(io.BytesIO(raw)).rows == 4
    with pytest.raises(FileNotFoundError):
        dk.read_parquet(tmp_path / "missing.parquet")
    with pytest.raises(TypeError):
        dk.read_parquet(42)


def test_a_read_returns_a_tuple():
    df, meta = labelled()
    with pytest.raises(AttributeError, match="tuple"):
        dk.read_parquet(dk.save_parquet(df, meta=meta)).query("b > 1")


def test_rows_past_the_end_and_empty_frames():
    df, meta = labelled()
    raw = dk.save_parquet(df, meta=meta)
    past, pm = dk.read_parquet(raw, skip=10)
    assert len(past) == 0 and list(past.columns) == list(df.columns) and pm.rows == 0
    # No row holds a missing value: the numpy types.
    assert past["b"].dtype == np.int8 and past["l"].dtype == np.int32
    empty, _ = round_trip(df.head(0))
    assert list(empty.columns) == list(df.columns) and len(empty) == 0


def test_the_write_table():
    nat = None
    df = pd.DataFrame({
        "i8": np.array([1, -2, 3], dtype=np.int8), "i16": np.array([1, 2, 3], dtype=np.int16),
        "i32": np.array([1, 2, 3], dtype=np.int32), "i64": np.array([2**62, 0, 1], dtype=np.int64),
        "u8": np.array([0, 255, 1], dtype=np.uint8), "u16": np.array([0, 65535, 1], dtype=np.uint16),
        "u32": np.array([0, 2**32 - 1, 1], dtype=np.uint32), "u64": np.array([0, 2**64 - 1, 1], dtype=np.uint64),
        "f32": np.array([1.5, 2, 3], dtype=np.float32), "f64": [1.5, 2.0, 0.1], "b": [True, False, True],
        "Int8": pd.array([1, None, -3], dtype="Int8"), "Int64": pd.array([2**62, None, 1], dtype="Int64"),
        "UInt16": pd.array([0, None, 65535], dtype="UInt16"), "UInt64": pd.array([2**64 - 1, None, 0], dtype="UInt64"),
        "Float64": pd.array([1.5, None, np.nan], dtype="Float64"), "boolean": pd.array([True, None, False]),
        "s": ["a", None, "x" * 40], "bin": [b"\x00", None, b"z" * 20],
        "d": pd.Series([dt.datetime(2024, 1, 1), nat, dt.datetime(1, 1, 1)], dtype="datetime64[s]"),
        "us": pd.Series([dt.datetime(2024, 1, 1, 1, 2, 3, 4), nat, dt.datetime(1900, 1, 1)], dtype="datetime64[us]"),
        "ns": pd.Series([dt.datetime(2024, 1, 1), nat, dt.datetime(1900, 1, 1)], dtype="datetime64[ns]"),
        "ms_paris": pd.Series([dt.datetime(2024, 1, 1), nat, dt.datetime(1900, 1, 1)],
                              dtype="datetime64[ms]").dt.tz_localize("Europe/Paris"),
        "us_utc": pd.Series([dt.datetime(2024, 1, 1), nat, nat], dtype="datetime64[us]").dt.tz_localize("UTC"),
        "time": pd.to_timedelta(["01:02:03.000004", None, "23:59:00"]),
        "cat": pd.Categorical(["b", None, "a"], categories=["c", "b", "a"], ordered=True),
        "x": lettered([1.0, None, None], [None, ".q", None], storage="byte"),
    })
    meta = dk.Meta(columns={"d": dk.Column(format="%td")})
    back, bm = round_trip(df, meta)
    # Without a missing value, numpy types come back as they are.
    for c in ("i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64", "b"):
        assert back[c].dtype == df[c].dtype and back[c].tolist() == df[c].tolist(), c
    # Nullable types: 8- to 32-bit integers and floats with a missing
    # value are DtaArrays; INT64, unsigned and BOOLEAN stay nullable.
    assert back["Int8"].dtype == "dta[byte]" and back["Int8"].array.codes.tolist() == [0, 1, 0]
    assert back["Int64"].dtype == "Int64" and back["Int64"].tolist() == [2**62, pd.NA, 1]
    assert back["UInt16"].dtype == "UInt16" and back["UInt64"].tolist() == [2**64 - 1, pd.NA, 0]
    assert back["Float64"].dtype == "dta[double]" and back["Float64"].array.codes.tolist() == [0, 1, 1]
    assert back["boolean"].dtype == "boolean" and back["boolean"].tolist() == [True, pd.NA, False]
    assert is_text(back["s"].dtype) and back["s"].isna().tolist() == [False, True, False]
    assert back["bin"].dtype == object and back["bin"].tolist()[0::2] == [b"\x00", b"z" * 20]
    # %td at midnight: DATE, read back datetime64[s] with its format.
    assert back["d"].dtype == "datetime64[s]" and bm.columns["d"].format == "%td"
    assert back["d"].tolist()[0::2] == df["d"].tolist()[0::2] and back["d"].isna().tolist()[1]
    for c in ("us", "ns", "ms_paris", "us_utc"):
        assert back[c].dtype == df[c].dtype, c
        pd.testing.assert_series_equal(back[c], df[c])
    assert back["time"].dtype == "timedelta64[ns]"
    pd.testing.assert_series_equal(back["time"], df["time"].astype("timedelta64[ns]"))
    assert list(back["cat"].dtype.categories) == ["c", "b", "a"] and back["cat"].dtype.ordered
    assert bm.columns["cat"].ordered is True
    assert back["x"].dtype == "dta[byte]" and tags(back["x"]) == [None, ".q", None]


def test_a_tagged_nan_in_a_plain_float_is_its_letter():
    df = pd.DataFrame({"x": [1.0, tagged_float(".k"), np.nan]})
    back, _ = round_trip(df)
    assert back["x"].dtype == "dta[double]" and tags(back["x"]) == [None, ".k", None]
    assert back["x"].array.codes.tolist() == [0, 12, 1]
    back, _ = round_trip(df, missing_letters=False)
    assert back["x"].array.codes.tolist() == [0, 1, 1]


def test_time_columns_come_back_as_nanoseconds(tmp_path):
    pa = pytest.importorskip("pyarrow")
    pq = pytest.importorskip("pyarrow.parquet")
    table = pa.table({"ms": pa.array([0, 1000, None], type=pa.time32("ms")),
                      "us": pa.array([5, None, 86_399_999_999], type=pa.time64("us")),
                      "ns": pa.array([None, 7, 1], type=pa.time64("ns"))})
    pq.write_table(table, tmp_path / "t.parquet")
    df, _ = quiet(dk.read_parquet, tmp_path / "t.parquet")
    assert all(df[c].dtype == "timedelta64[ns]" for c in df.columns)
    assert df["ms"].isna().tolist() == [False, False, True]  # NaT, not midnight
    assert df["us"].iloc[2] == pd.Timedelta(microseconds=86_399_999_999)
    back = pq.read_table(io.BytesIO(quiet(dk.save_parquet, df)))
    assert all(back.schema.field(c).type == pa.time64("ns") for c in df.columns)
    assert back.column("ms").to_pylist()[:2] == [dt.time(0), dt.time(0, 0, 1)]


def test_a_timedelta_outside_a_day_is_refused():
    for bad in (["-1s"], ["24h"], ["2 days"]):
        with pytest.raises(ValueError, match=r'column "x", row 1: .*not a time of day'):
            dk.save_parquet(pd.DataFrame({"x": pd.to_timedelta(bad)}))


def test_nulls_in_dates_timestamps_and_booleans_are_not_zeros(tmp_path):
    pa = pytest.importorskip("pyarrow")
    pq = pytest.importorskip("pyarrow.parquet")
    table = pa.table({"d": pa.array([None, 1], type=pa.date32()),
                      "t": pa.array([None, 1], type=pa.timestamp("us", "UTC")),
                      "n": pa.array([None, 1], type=pa.timestamp("ns")),
                      "b": pa.array([None, True], type=pa.bool_())})
    pq.write_table(table, tmp_path / "n.parquet")
    df, _ = dk.read_parquet(tmp_path / "n.parquet")
    assert df["d"].isna().tolist() == [True, False] and df["d"].iloc[1] == pd.Timestamp("1970-01-02")
    assert df["t"].isna().tolist() == [True, False] and str(df["t"].dtype) == "datetime64[us, UTC]"
    assert df["n"].isna().tolist() == [True, False]
    assert df["b"].dtype == "boolean" and df["b"].tolist() == [pd.NA, True]


def test_what_does_not_round_trip():
    # An object column of only missing values is text, every row missing.
    back, _ = round_trip(pd.DataFrame({"x": [1, 2], "n": [None, None]}))
    assert is_text(back["n"].dtype) and back["n"].isna().all()
    # Decimal objects are not written: convert them.
    with pytest.raises(TypeError, match='"x" holds decimal.Decimal values.*float.*text'):
        dk.save_parquet(pd.DataFrame({"x": [decimal.Decimal("1.5")]}))
    # A category of numbers is not written: its categories must be text.
    with pytest.raises(TypeError, match='"c" is a category of int64.*rename_categories'):
        dk.save_parquet(pd.DataFrame({"c": pd.Categorical([1, 2])}))


def test_unit_seconds_reads_as_milliseconds(tmp_path):
    pa = pytest.importorskip("pyarrow")
    pq = pytest.importorskip("pyarrow.parquet")
    table = pa.table({"t": pa.array([0, 1000, None], type=pa.timestamp("ms"))})
    profile = {"version": 1, "columns": {"t": {"unit": "s"}}}
    table = table.replace_schema_metadata({"dta": json.dumps(profile)})
    pq.write_table(table, tmp_path / "s.parquet")
    df, _ = dk.read_parquet(tmp_path / "s.parquet")
    assert df["t"].dtype == "datetime64[ms]"
    assert df["t"].tolist()[:2] == [pd.Timestamp("1970-01-01"), pd.Timestamp("1970-01-01 00:00:01")]
    assert df["t"].isna().tolist()[2]


def test_dtypes_that_are_errors():
    cases = {
        "complex": pd.DataFrame({"x": [1 + 2j]}),
        "interval": pd.DataFrame({"x": pd.arrays.IntervalArray.from_breaks([0, 1])}),
        "period": pd.DataFrame({"x": pd.period_range("2020-01", periods=1, freq="M")}),
        "mixed": pd.DataFrame({"x": pd.Series(["a", 1], dtype=object)}),
        "object": pd.DataFrame({"x": pd.Series([object()], dtype=object)}),
        "float16": pd.DataFrame({"x": np.array([1], dtype=np.float16)}),
    }
    for name, df in cases.items():
        with pytest.raises((TypeError, ValueError), match='column "x"'):
            dk.save_parquet(df)
    with pytest.raises(TypeError, match="pandas DataFrame"):
        dk.save_parquet({"x": [1]})
    with pytest.raises(TypeError, match="column names are text"):
        dk.save_parquet(pd.DataFrame({0: [1]}))
    with pytest.raises(ValueError, match='"x" appears more than once'):
        dk.save_parquet(pd.DataFrame([[1, 2]], columns=["x", "x"]))
    with pytest.raises(ValueError, match="compression is"):
        dk.save_parquet(pd.DataFrame({"x": [1]}), compression="lzo")
    with pytest.raises(ValueError, match="zstd levels"):
        dk.save_parquet(pd.DataFrame({"x": [1]}), compression="zstd", compression_level=99)
    with pytest.raises(ValueError, match="row_group_size"):
        dk.save_parquet(pd.DataFrame({"x": [1]}), row_group_size=0)
    with pytest.raises(KeyError, match='names the value label set "nope"'):
        dk.save_parquet(pd.DataFrame({"x": [1]}), meta=dk.Meta(columns={"x": dk.Column(value_labels="nope")}))
    with pytest.raises(ValueError, match="not finite or beyond"):
        dk.save_parquet(pd.DataFrame({"x": [1]}), meta=dk.Meta(value_labels={"v": {2**60: "big"}}))


def test_the_index_is_not_written():
    df = pd.DataFrame({"x": [1, 2]}, index=["a", "b"])
    back, _ = round_trip(df)
    assert list(back.columns) == ["x"] and back.index.tolist() == [0, 1]


def test_compression_row_groups_and_info(tmp_path):
    df = pd.DataFrame({"x": np.arange(10, dtype=np.int32), "s": [f"v{i % 3}" for i in range(10)]})
    for codec in ("snappy", "zstd", "gzip", "lz4_raw", "none"):
        raw = dk.save_parquet(df, compression=codec)
        assert dk.read_parquet_info(raw).compression == [codec]
        pd.testing.assert_frame_equal(dk.read_parquet(raw)[0], df)
    raw = dk.save_parquet(df, compression="zstd", compression_level=9, row_group_size=4)
    assert dk.read_parquet_info(raw).row_groups["rows"].tolist() == [4, 4, 2]


def test_read_parquet_info(tmp_path):
    df, meta = labelled()
    path = tmp_path / "x.parquet"
    dk.save_parquet(df, path, meta=meta)
    info = dk.read_parquet_info(path)
    assert info.rows == 4 and info.created_by.startswith("dta-parquet")
    assert set(info.key_value) >= {"dta", "ARROW:schema"}
    assert json.loads(info.key_value["dta"])["label"] == "Every storage type"
    read, read_meta = dk.read_parquet(path)
    assert info.meta == read_meta
    cols = info.columns
    assert list(cols.columns) == ["name", "role", "dtype", "physical_type", "logical_type", "label",
                                  "value_labels", "storage"]
    # The dtype a read gives when the rows hold no .a to .z: l and day hold
    # a letter but no `.` (a letter is a NaN in the file, not a null), so
    # the footer gives their numpy types where this read gives DtaArrays.
    want = [str(t) for t in read.dtypes]
    want[2], want[6] = "int32", "float64"
    assert cols["dtype"].tolist() == want
    b = {k: (None if pd.isna(v) else v) for k, v in cols.iloc[0].to_dict().items()}
    assert b == {"name": "b", "role": "data", "dtype": "dta[byte]", "physical_type": "DOUBLE",
                 "logical_type": None, "label": "B", "value_labels": "yn", "storage": "byte"}
    assert all(is_text(cols[c].dtype) for c in cols.columns)
    assert info == dk.read_parquet_info(path)
    assert info.row_groups["rows"].dtype == np.int64


def test_damaged_profile_is_a_warning(tmp_path):
    pq = pytest.importorskip("pyarrow.parquet")
    df, meta = labelled()
    raw = dk.save_parquet(df, meta=meta)
    table = pq.read_table(io.BytesIO(raw))
    kv = dict(pq.ParquetFile(io.BytesIO(raw)).metadata.metadata)
    profile = json.loads(kv[b"dta"])
    profile["columns"]["small"] = {"storage": "int"}  # not a DOUBLE column
    kv[b"dta"] = json.dumps(profile).encode()
    pq.write_table(table.replace_schema_metadata(kv), tmp_path / "edited.parquet")
    with pytest.warns(UserWarning, match='dropped "columns.small.storage"'):
        back, _ = dk.read_parquet(tmp_path / "edited.parquet")
    assert back["small"].dtype == np.int8
    kv[b"dta"] = b"{not json"
    pq.write_table(table.replace_schema_metadata(kv), tmp_path / "broken.parquet")
    with pytest.warns(UserWarning, match="not JSON"):
        _, bm = dk.read_parquet(tmp_path / "broken.parquet")
    # The labels are gone; the letters are in the values, so they are not.
    assert bm.label is None and bm.columns["b"] == dk.Column()
    assert tags(back["b"]) == [None, ".a", None, None]


def test_a_selection_reads_only_its_profile_entries():
    df, meta = labelled()
    meta.columns["i"].value_labels = "other"
    meta.value_labels["other"] = {1: "one"}
    raw = dk.save_parquet(df, meta=meta)
    _, whole = dk.read_parquet(raw)
    for cols in (["b", "s"], ["i"], ["small"]):
        _, part = dk.read_parquet(raw, columns=cols)
        assert part.columns == {c: whole.columns[c] for c in cols}


def test_not_parquet_and_bad_arguments():
    with pytest.raises(ValueError, match="not a Parquet file"):
        dk.read_parquet(b"PAR1 but not really a file at all PAR1x")
    df, meta = labelled()
    raw = dk.save_parquet(df, meta=meta)
    with pytest.raises(ValueError, match="nested is"):
        dk.read_parquet(raw, nested="maybe")
    with pytest.raises(ValueError, match="timestamps is"):
        dk.read_parquet(raw, timestamps="round")
    with pytest.raises(TypeError, match="letters must be True or False"):
        dk.read_parquet(raw, letters="meta")
    with pytest.raises(ValueError, match="skip"):
        dk.read_parquet(raw, skip=-1)
    with pytest.raises(TypeError, match="factors"):
        dk.read_parquet(raw, factors="yes")


def test_large_frames_on_threads(monkeypatch):
    monkeypatch.setenv("DTA_THREADS", "4")
    n = 200_000
    r = np.arange(n)
    a = (r % 200 - 100).astype(np.int8)
    codes = np.where(a > 50, np.where(r % 7 == 0, 2, 1), 0).astype(np.uint8)
    df = pd.DataFrame({
        "a": a,
        "b": np.sqrt(r.astype(np.float64)),
        "s": ["alpha", "beta", "gamma", "delta"] * (n // 4),
        "u": [f"id{i}" for i in range(n)],
        "c": DtaArray(np.where(codes == 0, np.sqrt(r), np.nan), codes),
    })
    assert dk.is_tagged_na(df["c"]).sum() > 1000 and (df["c"].array.codes == 1).sum() > 1000
    raw = dk.save_parquet(df, row_group_size=50_000)
    back, _ = dk.read_parquet(raw)
    assert_same(back, df)
    part, _ = dk.read_parquet(raw, skip=123_456, n_max=1000)
    assert_same(part, df.iloc[123_456:124_456].reset_index(drop=True))


# ---------------------------------------------------------------- timestamps held as doubles

def doubles_file(tmp_path, values, logical, tz=None):
    """A DOUBLE column the profile says is a date or timestamp, as R and
    our writers write one holding letters."""
    pa = pytest.importorskip("pyarrow")
    pq = pytest.importorskip("pyarrow.parquet")
    entry = {"logical": logical}
    if tz is not None:
        entry["tz"] = tz
    table = pa.table({"x": pa.array(values, type=pa.float64())})
    table = table.replace_schema_metadata({"dta": json.dumps({"version": 1, "columns": {"x": entry}})})
    path = tmp_path / f"{logical}.parquet"
    pq.write_table(table, path)
    return path


def epoch(s, unit):
    return [None if pd.isna(v) else v for v in s.dt.as_unit(unit).astype("int64", copy=False).where(s.notna())]


def test_seconds_that_whole_microseconds_give_back_read_exactly(tmp_path):
    # 0.1 s written from 100,000 µs, and R's 1709285400.25.
    path = doubles_file(tmp_path, [0.1, 1709285400.25, -1.5, None], "timestamp", "UTC")
    df, _ = quiet(dk.read_parquet, path)
    assert str(df["x"].dtype) == "datetime64[us, UTC]"
    assert df["x"].array.asi8[:3].tolist() == [100_000, 1_709_285_400_250_000, -1_500_000]
    assert df["x"].isna().tolist() == [False, False, False, True]


def test_seconds_not_whole_microseconds(tmp_path):
    path = doubles_file(tmp_path, [1.0000001, 2.0], "timestamp", "UTC")
    with pytest.raises(ValueError, match='column "x", row 1: .*not a whole number of microseconds.*timestamps="truncate"'):
        dk.read_parquet(path)
    df, _ = dk.read_parquet(path, timestamps="truncate")
    assert df["x"].array.asi8.tolist() == [1_000_000, 2_000_000]
    path = doubles_file(tmp_path, [-0.0000001], "timestamp", "UTC")
    assert dk.read_parquet(path, timestamps="truncate")[0]["x"].array.asi8.tolist() == [-1]


def test_days_with_a_fraction(tmp_path):
    path = doubles_file(tmp_path, [19000.5, 0.0, -1.25], "date")
    with pytest.raises(ValueError, match='column "x", row 1: the date 19000.5 .*fraction of a day'):
        dk.read_parquet(path)
    df, _ = dk.read_parquet(path, timestamps="truncate")
    assert df["x"].dtype == "datetime64[s]"
    assert (df["x"].to_numpy().view(np.int64) // 86400).tolist() == [19000, 0, -2]


@pytest.mark.parametrize("mode", ["error", "truncate"])
def test_doubles_out_of_range_are_errors_in_both_modes(tmp_path, mode):
    for values, logical, what in [([1e300], "timestamp", "outside the range of timestamps"),
                                  ([float("inf")], "timestamp", "is not a timestamp"),
                                  ([3e9], "date", "outside the range of dates"),
                                  ([float("-inf")], "date", "is not a date")]:
        path = doubles_file(tmp_path, values, logical, "UTC" if logical == "timestamp" else None)
        with pytest.raises(ValueError, match=what):
            dk.read_parquet(path, timestamps=mode)


def test_dates_and_timestamps_with_letters_read_as_statas_numbers(tmp_path):
    # R writes a Date or POSIXct holding tagged NAs as a DOUBLE of days or
    # seconds since 1970, tagged NaNs for the letters.
    a = tagged_float(".a")
    path = doubles_file(tmp_path, [0.0, a, -3653.0, None], "date")
    df, meta = quiet(dk.read_parquet, path)
    assert df["x"].dtype == "dta[double]" and meta.columns["x"].format == "%td"
    assert df["x"].array._values[[0, 2]].tolist() == [3653.0, 0.0] and tags(df["x"]) == [None, ".a", None, None]
    assert df["x"].array.codes.tolist() == [0, 2, 0, 1]
    path = doubles_file(tmp_path, [1.5, a, None], "timestamp", "UTC")
    df, meta = quiet(dk.read_parquet, path)
    assert df["x"].dtype == "dta[double]" and meta.columns["x"].format == "%tc"
    assert df["x"][0] == 315_619_201_500.0 and tags(df["x"]) == [None, ".a", None]
    # Without letters in the rows read, they are datetimes.
    assert str(dk.read_parquet(path, skip=2)[0]["x"].dtype) == "datetime64[us, UTC]"
    assert str(dk.read_parquet(path, letters=False)[0]["x"].dtype) == "datetime64[us, UTC]"
    assert dk.read_parquet(path, letters=False)[0]["x"].isna().tolist() == [False, True, True]


# ---------------------------------------------------------------- other writers

def expected_files():
    return sorted((PARQUET / "expected").glob("*.json"))


def as_expected(series, arrow_type):
    """Our column as compat/parquet/expected.py writes pyarrow's."""
    null = series.isna().to_numpy()
    if arrow_type.startswith("date32"):
        days = series.to_numpy().astype("datetime64[D]").view(np.int64)
        return [None if n else int(d) for d, n in zip(days, null)]
    if arrow_type.startswith("timestamp"):
        unit = arrow_type[len("timestamp["):].split(",")[0].rstrip("]")
        ints = series.dt.as_unit(unit).array.asi8
        return [None if n else int(v) for v, n in zip(ints, null)]
    if arrow_type.startswith(("time32", "time64")):
        unit = arrow_type.split("[")[1].rstrip("]")
        per = {"s": 10**9, "ms": 10**6, "us": 10**3, "ns": 1}[unit]
        ns = series.to_numpy().view(np.int64)
        return [None if n else int(v) // per for v, n in zip(ns, null)]
    out = []
    for v, n in zip(series.astype(object).tolist(), null):
        if n:
            out.append(None)
        elif isinstance(v, bytes):
            out.append(list(v))
        else:
            out.append(v)
    return out


@pytest.mark.parametrize("path", expected_files(), ids=lambda p: p.stem)
def test_files_from_other_tools_read_as_pyarrow_reads_them(path):
    expected = json.loads(path.read_text())
    source = PARQUET / "fixtures" / (path.stem + ".parquet")
    if expected.get("nested"):
        with pytest.raises(ValueError, match="nested"):
            dk.read_parquet(source)
        df, _ = quiet(dk.read_parquet, source, nested="skip")
        assert not set(expected["nested"]) & set(df.columns)
        info = dk.read_parquet_info(source)
        assert set(info.columns.loc[info.columns["role"] == "nested", "name"]) == set(expected["nested"])
    else:
        df, _ = quiet(dk.read_parquet, source)
    assert len(df) == expected["rows"]
    assert list(df.columns) == [c["name"] for c in expected["columns"]]
    info = dk.read_parquet_info(source)
    dtypes = dict(zip(info.columns["name"], info.columns["dtype"]))
    for col in expected["columns"]:
        name, arrow_type, want = col["name"], col["arrow_type"], col["values"]
        got = df[name]
        # A NaN is `.` (plan 0024): a float column holding one is a
        # DtaArray, which the footer cannot foresee.
        nan = any(w == "NaN" for w in want)
        if not nan:
            assert dtypes[name] == str(got.dtype), name
        if arrow_type.startswith(("decimal128(", "decimal256(")):
            precision, scale = map(int, arrow_type.split("(")[1].rstrip(")").split(","))
            if precision > 15:
                assert got.dtype == object, name
                for g, w in zip(got.tolist(), want):
                    assert (g is None and w is None) or g == decimal.Decimal(w), name
            else:
                for g, w in zip(got.tolist(), want):
                    assert (w is None and g != g) or g == float(w), name
            continue
        if arrow_type.startswith("dictionary<values=string"):
            assert isinstance(got.dtype, pd.CategoricalDtype), name
        mine = as_expected(got, arrow_type)
        if arrow_type in ("binary", "large_binary") and any(isinstance(v, str) for v in mine):
            # ENUM: pyarrow reads bytes, we read text.
            mine = [None if v is None else list(v.encode()) for v in mine]
        want = [None if w == "NaN" else w for w in want]
        assert mine == want, name


def test_a_window_of_another_tools_file():
    source = PARQUET / "fixtures" / "pyarrow_small_pages.parquet"
    whole, _ = dk.read_parquet(source)
    for skip, n_max in [(0, 7), (199, 3), (450, 400), (590, 100)]:
        part, _ = dk.read_parquet(source, skip=skip, n_max=n_max)
        want = whole.iloc[skip:skip + n_max]
        for name in whole.columns:
            a, b = part[name].astype(object).tolist(), want[name].astype(object).tolist()
            assert [None if pd.isna(x) else x for x in a] == [None if pd.isna(x) else x for x in b], name


# ---------------------------------------------------------------- other readers

def our_file():
    df, meta = labelled()
    df["cat"] = pd.Categorical(["b", None, "a", "b"], categories=["c", "b", "a"], ordered=True)
    df["zoned"] = pd.Series([dt.datetime(2024, 3, 1, 9, 30), None, dt.datetime(2024, 7, 1),
                             dt.datetime(2001, 1, 1)], dtype="datetime64[us]").dt.tz_localize("Asia/Tokyo")
    return dk.save_parquet(df, meta=meta)


def test_pyarrow_reads_our_files():
    pa = pytest.importorskip("pyarrow")
    pq = pytest.importorskip("pyarrow.parquet")
    raw = our_file()
    table = pq.read_table(io.BytesIO(raw))
    assert b"dta" in pq.ParquetFile(io.BytesIO(raw)).metadata.metadata
    assert table.schema.field("b").type == pa.float64()  # .a to .z: DOUBLE, NaN
    assert table.schema.field("small").type == pa.int8()
    assert table.schema.field("cat").type.ordered
    assert table.schema.field("zoned").type.tz == "Asia/Tokyo"
    assert table.column("b").is_null().to_pylist() == [False, False, True, False]
    assert math.isnan(table.column("b")[1].as_py())
    assert table.column("s").to_pylist() == ["a", "bb", "", "é"]


def test_polars_reads_our_files():
    pl = pytest.importorskip("polars")
    out = pl.read_parquet(io.BytesIO(our_file()))
    assert out["b"].null_count() == 1 and out["b"].is_nan().sum() == 1  # `.` null, .a NaN
    assert out["small"].dtype == pl.Int8
    assert out["s"].to_list() == ["a", "bb", "", "é"]
    assert out["zoned"].dtype == pl.Datetime("us", "Asia/Tokyo")


def test_duckdb_reads_our_files(tmp_path):
    duckdb = pytest.importorskip("duckdb")
    path = tmp_path / "x.parquet"
    path.write_bytes(our_file())
    con = duckdb.connect()
    nulls, missing_ = con.execute(
        "SELECT count(*) FILTER (WHERE b IS NULL), count(*) FILTER (WHERE b IS NULL OR isnan(b)) FROM read_parquet(?)",
        [str(path)]).fetchone()
    assert (nulls, missing_) == (1, 2)
    kinds = dict(con.execute("SELECT column_name, column_type FROM (DESCRIBE SELECT * FROM read_parquet(?))",
                             [str(path)]).fetchall())
    assert kinds["small"] == "TINYINT" and kinds["day"] == "DOUBLE" and kinds["s"] == "VARCHAR"


def test_missing_value_objects_are_refused_with_the_conversion():
    with pytest.raises(TypeError, match=r'astype\("dta\[double\]"\)'):
        dk.save_parquet(pd.DataFrame({"x": pd.Series([missing.b, 2.0], dtype=object)}))
