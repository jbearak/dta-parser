"""read_parquet, read_parquet_info and save_parquet (plan 0019), moved
from dta_parser's pandas tests and rewritten for polars.

- Every frame `read_dta` gives from compat/fixtures comes back from
  save_parquet and read_parquet equal (`assert_frame_equal`, dtypes
  checked, letters too) with an equal Meta, with letters=True and
  False.
- Constructed frames cover what fixtures do not: every polars dtype
  save_parquet writes, and those it refuses.
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
import warnings

import polars as pl
import pytest
from polars.testing import assert_frame_equal

import datakit as dk
from conftest import PARQUET, assert_same, fixture_paths, tagged, tags


def quiet(fn, *args, **kw):
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        return fn(*args, **kw)


def round_trip(df, meta=None, **kw):
    read_kw = {k: kw.pop(k) for k in ("letters", "factors", "timestamps") if k in kw}
    return quiet(dk.read_parquet, quiet(dk.save_parquet, df, meta=meta, **kw), **read_kw)


@pytest.mark.parametrize("letters", [True, False])
@pytest.mark.parametrize("path", fixture_paths(), ids=lambda p: p.stem)
def test_every_fixture_round_trips(path, letters, tmp_path):
    df, meta = dk.read_dta(path, letters=letters, timestamps="truncate")
    out = tmp_path / "out.parquet"
    quiet(dk.save_parquet, df, out, meta=meta)
    back, back_meta = quiet(dk.read_parquet, out, letters=letters)
    assert_same(back, df)
    assert back_meta == meta and back_meta._storage == meta._storage
    if not letters:
        assert meta._storage == {}


@pytest.mark.parametrize("path", fixture_paths(), ids=lambda p: p.stem)
def test_every_fixture_reads_a_window_as_read_dta_does(path, tmp_path):
    df, meta = dk.read_dta(path, timestamps="truncate")
    out = tmp_path / "out.parquet"
    dk.save_parquet(df, out, meta=meta, row_group_size=3)
    n = df.height
    for skip, n_max in [(0, 1), (1, 4), (n // 2, 5), (max(n - 1, 0), 10), (n + 5, 2)]:
        a, am = dk.read_dta(path, skip=skip, n_max=n_max, timestamps="truncate")
        b, bm = dk.read_parquet(out, skip=skip, n_max=n_max)
        assert_same(b, a)
        assert bm == am


# ---------------------------------------------------------------- constructed

STORAGE = {"b": pl.Int8, "i": pl.Int16, "l": pl.Int32, "f": pl.Float32}


def labelled():
    """A frame of every Stata storage type with letters, as a read gives
    it (the letters tagged NaNs in Float64, the storage types in meta),
    and its Meta."""
    df = pl.DataFrame({
        "b": tagged([1, None, None, 3], [None, ".a", None, None]),
        "i": tagged([300, None, 2, None], [None, ".b", None, None]),
        "l": tagged([70000, None, 1, 2], [None, ".z", None, None]),
        "f": tagged([1.5, None, 2.25, None], [None, ".c", None, None]),
        "d": tagged([1e300, None, None, -0.5], [None, ".d", None, None]),
        "small": pl.Series([1, 2, 3, 4], dtype=pl.Int8),
        "day": tagged([23436, None, 0, -21857], [None, ".e", None, None]),
        "when": pl.Series([dt.datetime(2024, 3, 1, 9, 30, 0, 125000), None, dt.datetime(1960, 1, 1),
                           dt.datetime(2001, 9, 9, 1, 46, 40)]).cast(pl.Datetime("ms")),
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
    meta._storage = dict(STORAGE)
    return df, meta


def test_every_storage_type_with_letters_round_trips():
    df, meta = labelled()
    back, back_meta = round_trip(df, meta)
    assert_same(back, df)
    assert back_meta == meta and back_meta._storage == STORAGE
    assert back_meta.value_labels["yn"] == {0: "No", 1: "Yes", 1.5: "half", ".a": "Skipped", ".d": "Don't know"}
    assert list(back_meta.value_labels["yn"]) == [0, 1, 1.5, ".a", ".d"]
    assert tags(back["b"]) == [None, ".a", None, None]


def test_letters_survive_polars_row_operations():
    df, meta = labelled()
    changed = (df.filter(pl.col("small") > 1)
               .sort("small", descending=True)
               .join(pl.DataFrame({"small": pl.Series([2, 3, 4], dtype=pl.Int8), "k": [1, 2, 3]}), on="small", maintain_order="left"))
    changed = pl.concat([changed, changed])
    assert tags(changed["b"]) == [None, None, ".a"] * 2
    assert tags(changed["day"]) == [None, None, ".e"] * 2
    meta.sort = []
    back, _ = round_trip(changed, meta.select(list(df.columns)))
    assert_same(back, changed)


def test_a_window_without_letters_reads_the_storage_types():
    df, meta = labelled()
    raw = dk.save_parquet(df, meta=meta)
    part, pm = dk.read_parquet(raw, skip=2, n_max=2)
    # No letters in rows 3 and 4: b, i, l and f are their storage types.
    assert part.schema == {**df.schema, **STORAGE}
    assert pm._storage == {} and pm.rows == 2
    assert part["b"].to_list() == [None, 3]


def test_missing_letters_false_writes_nulls():
    df, meta = labelled()
    back, bm = round_trip(df, meta, missing_letters=False)
    want = df.with_columns(pl.when(dk.is_tagged_na(c)).then(None).otherwise(pl.col(c)).alias(c)
                           for c in ("b", "i", "l", "f", "d", "day")).with_columns(pl.col(c).cast(t) for c, t in STORAGE.items())
    assert_frame_equal(back, want)
    assert bm == meta and bm._storage == {}


def test_selection_by_name_and_position():
    df, meta = labelled()
    raw = dk.save_parquet(df, meta=meta)
    part, pm = dk.read_parquet(raw, columns=["s", 0, "s"])
    assert part.columns == ["s", "b"] and list(pm.columns) == ["s", "b"]
    assert tags(part["b"]) == [None, ".a", None, None] and pm._storage == {"b": pl.Int8}
    assert dk.read_parquet(raw, columns="d")[0].columns == ["d"]
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
        dk.read_parquet(dk.save_parquet(df, meta=meta)).filter(pl.col("b") > 1)


def test_rows_past_the_end_and_empty_frames():
    df, meta = labelled()
    raw = dk.save_parquet(df, meta=meta)
    past, pm = dk.read_parquet(raw, skip=10)
    assert past.height == 0 and past.schema == {**df.schema, **STORAGE} and pm.rows == 0
    empty, _ = round_trip(df.head(0))
    assert empty.schema == df.schema and empty.height == 0


def test_every_dtype_save_parquet_writes():
    df = pl.DataFrame({
        "i8": pl.Series([1, None, -3], dtype=pl.Int8), "i16": pl.Series([1, 2, None], dtype=pl.Int16),
        "i32": pl.Series([1, 2, 3], dtype=pl.Int32), "i64": pl.Series([2**62, None, 1]),
        "u8": pl.Series([0, 255, None], dtype=pl.UInt8), "u16": pl.Series([0, 65535, 1], dtype=pl.UInt16),
        "u32": pl.Series([0, 2**32 - 1, 1], dtype=pl.UInt32), "u64": pl.Series([0, 2**64 - 1, None], dtype=pl.UInt64),
        "f32": pl.Series([1.5, float("nan"), None], dtype=pl.Float32), "f64": [1.5, float("nan"), None],
        "b": [True, None, False], "s": ["a", None, "x" * 40], "bin": [b"\x00", None, b"z" * 20],
        "d": [dt.date(2024, 1, 1), None, dt.date(1, 1, 1)],
        "us": [dt.datetime(2024, 1, 1, 1, 2, 3, 4), None, dt.datetime(1900, 1, 1)],
        "ns": pl.Series([dt.datetime(2024, 1, 1), None, dt.datetime(1900, 1, 1)]).cast(pl.Datetime("ns")),
        "ms_paris": pl.Series([dt.datetime(2024, 1, 1), None, dt.datetime(1900, 1, 1)]).cast(
            pl.Datetime("ms", "Europe/Paris")),
        "us_utc": pl.Series([dt.datetime(2024, 1, 1), None, None]).cast(pl.Datetime("us", "UTC")),
        "time": [dt.time(1, 2, 3, 4), None, dt.time(23, 59)],
        "en": pl.Series(["b", None, "a"], dtype=pl.Enum(["c", "b", "a"])),
    })
    back, _ = round_trip(df)
    assert_frame_equal(back, df)
    # NaN stays a value in Float32 and Float64; it is not a letter.
    assert back["f64"].is_nan().to_list() == [False, True, None]


def test_what_does_not_round_trip():
    # A Categorical comes back as an Enum of the levels it used.
    cat = pl.DataFrame({"c": pl.Series(["y", None, "x", "y"], dtype=pl.Categorical)})
    back, _ = round_trip(cat)
    assert back["c"].dtype == pl.Enum(["y", "x"]) and back["c"].to_list() == ["y", None, "x", "y"]
    # An all-null column (pl.lit(None)) is written as a DOUBLE of nulls.
    back, _ = round_trip(pl.DataFrame({"x": [1, 2]}).with_columns(n=pl.lit(None)))
    assert back["n"].dtype == pl.Float64 and back["n"].null_count() == 2
    # Decimal is not written: cast it.
    with pytest.raises(TypeError, match='"x" is Decimal.*cast it to Float64 or String'):
        dk.save_parquet(pl.DataFrame({"x": [decimal.Decimal("1.5")]}))


def test_unit_seconds_reads_as_milliseconds(tmp_path):
    pa = pytest.importorskip("pyarrow")
    pq = pytest.importorskip("pyarrow.parquet")
    table = pa.table({"t": pa.array([0, 1000, None], type=pa.timestamp("ms"))})
    profile = {"version": 1, "columns": {"t": {"unit": "s"}}}
    table = table.replace_schema_metadata({"dta": json.dumps(profile)})
    pq.write_table(table, tmp_path / "s.parquet")
    df, _ = dk.read_parquet(tmp_path / "s.parquet")
    assert df["t"].dtype == pl.Datetime("ms") and df["t"].to_list() == [dt.datetime(1970, 1, 1),
                                                                      dt.datetime(1970, 1, 1, 0, 0, 1), None]


def test_dtypes_that_are_errors():
    cases = {
        "Duration": pl.DataFrame({"x": [dt.timedelta(seconds=1)]}),
        "List": pl.DataFrame({"x": [[1, 2]]}),
        "Array": pl.DataFrame({"x": [[1, 2]]}, schema={"x": pl.Array(pl.Int64, 2)}),
        "Struct": pl.DataFrame({"x": [{"a": 1}]}),
        "Object": pl.DataFrame({"x": pl.Series([object()], dtype=pl.Object)}),
        "Int128": pl.DataFrame({"x": pl.Series([1], dtype=pl.Int128)}),
    }
    for name, df in cases.items():
        with pytest.raises((TypeError, ValueError), match='column "x"'):
            dk.save_parquet(df)
    with pytest.raises(TypeError, match="LazyFrame.*collect"):
        dk.save_parquet(pl.LazyFrame({"x": [1]}))
    with pytest.raises(TypeError, match="polars DataFrame"):
        dk.save_parquet({"x": [1]})
    with pytest.raises(ValueError, match="compression is"):
        dk.save_parquet(pl.DataFrame({"x": [1]}), compression="lzo")
    with pytest.raises(ValueError, match="zstd levels"):
        dk.save_parquet(pl.DataFrame({"x": [1]}), compression="zstd", compression_level=99)
    with pytest.raises(ValueError, match="row_group_size"):
        dk.save_parquet(pl.DataFrame({"x": [1]}), row_group_size=0)
    with pytest.raises(KeyError, match='names the value label set "nope"'):
        dk.save_parquet(pl.DataFrame({"x": [1]}), meta=dk.Meta(columns={"x": dk.Column(value_labels="nope")}))
    with pytest.raises(ValueError, match="not finite or beyond"):
        dk.save_parquet(pl.DataFrame({"x": [1]}), meta=dk.Meta(value_labels={"v": {2**60: "big"}}))


def test_compression_row_groups_and_info(tmp_path):
    df = pl.DataFrame({"x": pl.Series(range(10), dtype=pl.Int32), "s": [f"v{i % 3}" for i in range(10)]})
    for codec in ("snappy", "zstd", "gzip", "lz4_raw", "none"):
        raw = dk.save_parquet(df, compression=codec)
        assert dk.read_parquet_info(raw).compression == [codec]
        assert_frame_equal(dk.read_parquet(raw)[0], df)
    raw = dk.save_parquet(df, compression="zstd", compression_level=9, row_group_size=4)
    assert dk.read_parquet_info(raw).row_groups["rows"].to_list() == [4, 4, 2]


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
    assert cols.columns == ["name", "role", "dtype", "physical_type", "logical_type", "label", "value_labels",
                            "storage"]
    # The dtype without letters: b, i, l and f are Float64 here only
    # because the rows read hold letters.
    assert cols["dtype"].to_list() == [str(STORAGE.get(n, t)) for n, t in read.schema.items()]
    b = cols.row(0, named=True)
    assert b == {"name": "b", "role": "data", "dtype": "Int8", "physical_type": "DOUBLE", "logical_type": None,
                 "label": "B", "value_labels": "yn", "storage": "byte"}
    assert info == dk.read_parquet_info(path)


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
    assert back["small"].dtype == pl.Int8
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
    df = pl.DataFrame({
        "a": (pl.int_range(n, eager=True) % 200 - 100).cast(pl.Int8),
        "b": pl.int_range(n, eager=True).cast(pl.Float64).sqrt(),
        "s": pl.Series(["alpha", "beta", "gamma", "delta"] * (n // 4)),
        "u": pl.Series([f"id{i}" for i in range(n)]),
    }).with_columns(c=pl.when(pl.col("a") > 50).then(pl.when(pl.int_range(n) % 7 == 0).then(dk.tagged_na(".a")))
                    .otherwise(pl.col("b")))
    assert dk.is_tagged_na(df["c"]).sum() > 1000 and df["c"].null_count() > 1000
    raw = dk.save_parquet(df, row_group_size=50_000)
    back, _ = dk.read_parquet(raw)
    assert_same(back, df)
    part, _ = dk.read_parquet(raw, skip=123_456, n_max=1000)
    assert_same(part, df.slice(123_456, 1000))


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


def test_seconds_that_whole_microseconds_give_back_read_exactly(tmp_path):
    # 0.1 s written from 100,000 µs, and R's 1709285400.25.
    path = doubles_file(tmp_path, [0.1, 1709285400.25, -1.5, None], "timestamp", "UTC")
    df, _ = quiet(dk.read_parquet, path)
    assert df["x"].dtype == pl.Datetime("us", "UTC")
    assert df["x"].dt.epoch("us").to_list() == [100_000, 1_709_285_400_250_000, -1_500_000, None]


def test_seconds_not_whole_microseconds(tmp_path):
    path = doubles_file(tmp_path, [1.0000001, 2.0], "timestamp", "UTC")
    with pytest.raises(ValueError, match='column "x", row 1: .*not a whole number of microseconds.*timestamps="truncate"'):
        dk.read_parquet(path)
    df, _ = dk.read_parquet(path, timestamps="truncate")
    assert df["x"].dt.epoch("us").to_list() == [1_000_000, 2_000_000]
    path = doubles_file(tmp_path, [-0.0000001], "timestamp", "UTC")
    assert dk.read_parquet(path, timestamps="truncate")[0]["x"].dt.epoch("us").to_list() == [-1]


def test_days_with_a_fraction(tmp_path):
    path = doubles_file(tmp_path, [19000.5, 0.0, -1.25], "date")
    with pytest.raises(ValueError, match='column "x", row 1: the date 19000.5 .*fraction of a day'):
        dk.read_parquet(path)
    df, _ = dk.read_parquet(path, timestamps="truncate")
    assert df["x"].dtype == pl.Date
    assert df["x"].to_physical().to_list() == [19000, 0, -2]


@pytest.mark.parametrize("mode", ["error", "truncate"])
def test_doubles_out_of_range_are_errors_in_both_modes(tmp_path, mode):
    for values, logical, what in [([1e300], "timestamp", "outside polars' Datetime range"),
                                  ([float("inf")], "timestamp", "is not a timestamp"),
                                  ([3e9], "date", "outside polars' Date range"),
                                  ([float("-inf")], "date", "is not a date")]:
        path = doubles_file(tmp_path, values, logical, "UTC" if logical == "timestamp" else None)
        with pytest.raises(ValueError, match=what):
            dk.read_parquet(path, timestamps=mode)


def test_dates_and_timestamps_with_letters_read_as_statas_numbers(tmp_path):
    # R writes a Date or POSIXct holding tagged NAs as a DOUBLE of days or
    # seconds since 1970, tagged NaNs for the letters.
    a = dk.tagged_na(".a")
    path = doubles_file(tmp_path, [0.0, a, -3653.0, None], "date")
    df, meta = quiet(dk.read_parquet, path)
    assert df["x"].dtype == pl.Float64 and meta.columns["x"].format == "%td"
    assert df["x"].fill_nan(None).to_list() == [3653.0, None, 0.0, None] and tags(df["x"]) == [None, ".a", None, None]
    path = doubles_file(tmp_path, [1.5, a, None], "timestamp", "UTC")
    df, meta = quiet(dk.read_parquet, path)
    assert df["x"].dtype == pl.Float64 and meta.columns["x"].format == "%tc"
    assert df["x"].fill_nan(None).to_list() == [315_619_201_500.0, None, None] and tags(df["x"]) == [None, ".a", None]
    # Without letters in the rows read, they are a Date and a Datetime.
    assert dk.read_parquet(path, skip=2)[0]["x"].dtype == pl.Datetime("us", "UTC")
    assert dk.read_parquet(path, letters=False)[0]["x"].dtype == pl.Datetime("us", "UTC")


# ---------------------------------------------------------------- other writers

def expected_files():
    return sorted((PARQUET / "expected").glob("*.json"))


def as_expected(series, arrow_type):
    """Our column as compat/parquet/expected.py writes pyarrow's."""
    t = series.dtype
    if arrow_type.startswith("date32"):
        return series.to_physical().to_list()
    if arrow_type.startswith("timestamp"):
        unit = arrow_type[len("timestamp["):].split(",")[0].rstrip("]")
        return series.dt.epoch(unit).to_list()
    if arrow_type.startswith(("time32", "time64")):
        unit = arrow_type.split("[")[1].rstrip("]")
        per = {"s": 10**9, "ms": 10**6, "us": 10**3, "ns": 1}[unit]
        return [None if v is None else v // per for v in series.to_physical().to_list()]
    if isinstance(t, (pl.Enum, pl.Categorical)):
        series = series.cast(pl.String)
    out = []
    for v in series.to_list():
        if isinstance(v, bytes):
            out.append(list(v))
        elif isinstance(v, float) and math.isnan(v):
            out.append("NaN")
        else:
            out.append(v)
    return out


@pytest.mark.filterwarnings("ignore:column \"dec\" holds values with more digits")
@pytest.mark.parametrize("path", expected_files(), ids=lambda p: p.stem)
def test_files_from_other_tools_read_as_pyarrow_reads_them(path):
    expected = json.loads(path.read_text())
    source = PARQUET / "fixtures" / (path.stem + ".parquet")
    if expected.get("nested"):
        with pytest.raises(ValueError, match="nested"):
            dk.read_parquet(source)
        df, _ = dk.read_parquet(source, nested="skip")
        assert not set(expected["nested"]) & set(df.columns)
        info = dk.read_parquet_info(source)
        assert set(info.columns.filter(pl.col("role") == "nested")["name"]) == set(expected["nested"])
    else:
        df, _ = dk.read_parquet(source)
    assert df.height == expected["rows"]
    assert df.columns == [c["name"] for c in expected["columns"]]
    info = dk.read_parquet_info(source)
    dtypes = dict(zip(info.columns["name"], info.columns["dtype"]))
    for col in expected["columns"]:
        name, arrow_type, want = col["name"], col["arrow_type"], col["values"]
        got = df[name]
        if not isinstance(got.dtype, pl.Categorical) and not (path.stem.startswith("parquet2_") and name == "dec"):
            assert dtypes[name] == str(got.dtype), name
        if arrow_type.startswith(("decimal128(", "decimal256(")):
            precision, scale = map(int, arrow_type.split("(")[1].rstrip(")").split(","))
            if precision > 38:
                assert got.dtype == pl.String, name
            elif path.stem.startswith("parquet2_"):
                # Parquet2.jl writes DECIMAL(13, 13) holding values such as
                # -3000, which do not fit it: widened, with a warning.
                assert got.dtype == pl.Decimal(38, scale), name
            else:
                assert got.dtype == pl.Decimal(precision, scale), name
            for g, w in zip(got.to_list(), want):
                assert (g is None and w is None) or decimal.Decimal(g) == decimal.Decimal(w), name
            continue
        if arrow_type.startswith("dictionary<values=string"):
            assert isinstance(got.dtype, pl.Categorical), name
        mine = as_expected(got, arrow_type)
        if arrow_type in ("binary", "large_binary") and any(isinstance(v, str) for v in mine):
            # ENUM: pyarrow reads bytes, we read text.
            mine = [None if v is None else list(v.encode()) for v in mine]
        assert mine == want, name


def test_a_window_of_another_tools_file():
    source = PARQUET / "fixtures" / "pyarrow_small_pages.parquet"
    whole, _ = dk.read_parquet(source)
    for skip, n_max in [(0, 7), (199, 3), (450, 400), (590, 100)]:
        part, _ = dk.read_parquet(source, skip=skip, n_max=n_max)
        want = whole.slice(skip, n_max)
        for name in whole.columns:
            a, b = part[name], want[name]
            if isinstance(a.dtype, pl.Categorical):
                a, b = a.cast(pl.String), b.cast(pl.String)
            assert a.equals(b), name


# ---------------------------------------------------------------- other readers

def our_file():
    df, meta = labelled()
    df = df.with_columns(
        cat=pl.Series(["b", None, "a", "b"], dtype=pl.Enum(["c", "b", "a"])),
        zoned=pl.Series([dt.datetime(2024, 3, 1, 9, 30), None, dt.datetime(2024, 7, 1), dt.datetime(2001, 1, 1)])
        .dt.replace_time_zone("Asia/Tokyo"),
    )
    meta.columns["cat"] = dk.Column(ordered=True)
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
    out = pl.read_parquet(io.BytesIO(our_file()))
    assert out["b"].null_count() == 1 and out["b"].is_nan().sum() == 1  # `.` null, .a NaN
    assert (out["b"].is_null() | out["b"].is_nan()).to_list() == [False, True, True, False]
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
