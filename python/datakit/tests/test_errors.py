"""The exception type and message of each bad input the suites know
(plan 0025, stage 2a): written against the native code before the Arrow
modules were made free of pyo3, so that the move changes no error.

Parquet is read from a path, bytes and a file object; `.dta` from a path,
the only source `read_dta` takes. Some cases call dta_parser's native
functions directly, with what datakit's own checks would stop first or
what only a hand-made `meta` holds, so that each error the native code
raises is pinned. `{path}` in a message stands for the file's path.
"""

# pyright: reportArgumentType=false

import datetime as dt
import decimal
import io
import json

import polars as pl
import pytest

import datakit as dk
from datakit._native import native

dp = pytest.importorskip("dta_parser")
pd = pytest.importorskip("pandas")
pa = pytest.importorskip("pyarrow")
pq = pytest.importorskip("pyarrow.parquet")

SOURCES = ("path", "bytes", "file")
NOT_PARQUET = "not a Parquet file: it does not start and end with PAR1"
NO_FILE = "No such file or directory (os error 2)"


def source(path, kind):
    if kind == "path":
        return str(path)
    if kind == "bytes":
        return path.read_bytes()
    return io.BytesIO(path.read_bytes())


def by_source(kind, message):
    """`message` as a read from `kind` gives it: from a path, a ValueError
    raised once the file is open starts with the path."""
    return "{path}: " + message if kind == "path" else message


def raised(fn, *args, **kwargs):
    """The exception `fn` raises: its type and args."""
    try:
        fn(*args, **kwargs)
    except Exception as e:  # noqa: BLE001
        return type(e), e.args
    raise AssertionError("no exception")


def check(got, kind, message, path=None):
    want = message.replace("{path}", str(path)) if path is not None else message
    assert got == (kind, (want,)), got


@pytest.fixture
def files(tmp_path):
    """A small Parquet file, one that is not Parquet, a date with a
    fraction of a day, a nested column, a .dta file, a %td with a
    fraction, and a file that is not .dta."""
    out = {}
    df = pl.DataFrame({"b": pl.Series([1, 2], dtype=pl.Int8), "i": [1, 2]})
    out["parquet"] = tmp_path / "ok.parquet"
    dk.save_parquet(df, out["parquet"])
    out["not_parquet"] = tmp_path / "not.parquet"
    out["not_parquet"].write_bytes(b"this is not a Parquet file at all")
    table = pa.table({"x": pa.array([19000.5, 0.0], type=pa.float64())})
    table = table.replace_schema_metadata({"dta": json.dumps({"version": 1, "columns": {"x": {"logical": "date"}}})})
    out["fraction"] = tmp_path / "fraction.parquet"
    pq.write_table(table, out["fraction"])
    out["nested"] = tmp_path / "nested.parquet"
    pq.write_table(pa.table({"a": [1, 2], "l": pa.array([[1], [2, 3]])}), out["nested"])
    out["dta"] = tmp_path / "ok.dta"
    dp.write_dta(pd.DataFrame({"x": [1.0, 2.0], "s": ["a", "b"]}), out["dta"])
    day = pd.DataFrame({"d": [1.25, 2.0]})
    day.attrs["dta"] = {"columns": {"d": {"format": "%td"}}}
    out["day"] = tmp_path / "day.dta"
    dp.write_dta(day, out["day"])
    out["not_dta"] = tmp_path / "not.dta"
    out["not_dta"].write_bytes(b"this is not a .dta file at all, not even close")
    out["missing"] = tmp_path / "missing.file"
    out["no_dir"] = tmp_path / "no" / "such" / "dir" / "out"
    return out


# ---------------------------------------------------------------- Parquet reads

@pytest.mark.parametrize("kind", SOURCES)
def test_parquet_not_parquet(files, kind):
    p = files["not_parquet"]
    check(raised(dk.read_parquet, source(p, kind)), ValueError, by_source(kind, NOT_PARQUET), p)
    check(raised(dk.read_parquet_info, source(p, kind)), ValueError, by_source(kind, NOT_PARQUET), p)


@pytest.mark.parametrize("kind", SOURCES)
def test_parquet_unknown_column_name(files, kind):
    got = raised(dk.read_parquet, source(files["parquet"], kind), columns=["b", "nope"])
    check(got, KeyError, 'column "nope" is not in the file; its columns are "b", "i"')


@pytest.mark.parametrize("kind", SOURCES)
def test_parquet_position_out_of_range(files, kind):
    got = raised(dk.read_parquet, source(files["parquet"], kind), columns=[0, 99])
    check(got, IndexError, "there is no column 99; the file has 2 data columns")
    got = raised(dk.read_parquet, source(files["parquet"], kind), columns=[-1])
    check(got, IndexError, "there is no column -1; the file has 2 data columns")


@pytest.mark.parametrize("kind", SOURCES)
def test_parquet_column_neither_name_nor_position(files, kind):
    got = raised(native.parquet_read_arrow, source(files["parquet"], kind), [1.5])
    check(got, TypeError, "columns are names or 0-based positions")
    # On a file that does not open, the open's error comes first.
    got = raised(native.parquet_read_arrow, source(files["not_parquet"], kind), [1.5])
    check(got, ValueError, by_source(kind, NOT_PARQUET), files["not_parquet"])


@pytest.mark.parametrize("kind", SOURCES)
def test_parquet_bad_skip(files, kind):
    got = raised(dk.read_parquet, source(files["parquet"], kind), skip=-1)
    check(got, ValueError, "skip must be a whole number >= 0, not -1")
    got = raised(dk.read_parquet, source(files["parquet"], kind), n_max=1.5)
    check(got, ValueError, "n_max must be a whole number >= 0, not 1.5")


@pytest.mark.parametrize("kind", SOURCES)
def test_parquet_error_inside_the_read(files, kind):
    want = 'column "x", row 1: the date 19000.5 (days since 1970) has a fraction of a day; pass timestamps="truncate" to drop it'
    check(raised(dk.read_parquet, source(files["fraction"], kind)), ValueError, by_source(kind, want), files["fraction"])


@pytest.mark.parametrize("kind", SOURCES)
def test_parquet_nested_columns(files, kind):
    p = files["nested"]
    want = 'the file has nested columns, which are not read: "l"; select the columns wanted, or pass nested="skip"'
    check(raised(dk.read_parquet, source(p, kind)), ValueError, by_source(kind, want), p)
    want = 'column "l" is nested (a list, map or group), which is not read'
    check(raised(dk.read_parquet, source(p, kind), columns=["l"]), ValueError, by_source(kind, want), p)


def test_parquet_missing_file(files):
    p = files["missing"]
    assert raised(dk.read_parquet, p) == (FileNotFoundError, (2, "No such file or directory"))
    assert raised(dk.read_parquet_info, p) == (FileNotFoundError, (2, "No such file or directory"))
    check(raised(native.parquet_read_arrow, str(p)), ValueError, "{path}: " + NO_FILE, p)
    check(raised(native.parquet_info_arrow, str(p)), ValueError, "{path}: " + NO_FILE, p)


def test_parquet_bad_timestamps_argument(files):
    got = raised(native.parquet_read_arrow, str(files["parquet"]), timestamps="round")
    check(got, ValueError, 'timestamps is "error" or "truncate", not "round"')


class NoSeek(io.RawIOBase):
    def seek(self, *args):
        raise OSError("no seeking here")

    def read(self, *args):
        return b""


def test_file_objects_that_fail():
    got = raised(dk.read_parquet, io.StringIO("PAR1 text PAR1"))
    check(got, ValueError, "reading the file object: TypeError: read() did not return bytes")
    # The file object's own exception, as it raised it.
    assert raised(dk.read_parquet, NoSeek()) == (OSError, ("no seeking here",))


# ---------------------------------------------------------------- .dta reads

def test_dta_missing_file(files):
    p = files["missing"]
    assert raised(dk.read_dta, p) == (FileNotFoundError, (2, "No such file or directory"))
    check(raised(native.dta_read_arrow, str(p)), ValueError, "{path}: " + NO_FILE, p)


def test_dta_not_dta(files):
    check(raised(dk.read_dta, files["not_dta"]), ValueError, "{path}: unsupported .dta release 116 (at byte 0)",
          files["not_dta"])


def test_dta_unknown_column_name(files):
    check(raised(dk.read_dta, files["dta"], columns=["x", "nope"]), KeyError, 'column "nope" is not in the file')


def test_dta_position_out_of_range(files):
    check(raised(dk.read_dta, files["dta"], columns=[0, 99]), IndexError, "there is no column 99; the file has 2")
    check(raised(dk.read_dta, files["dta"], columns=[-1]), IndexError, "there is no column -1; the file has 2")
    check(raised(native.dta_read_arrow, str(files["dta"]), [1.5]), TypeError, "columns are names or 0-based positions")


def test_dta_bad_skip(files):
    check(raised(dk.read_dta, files["dta"], skip=-1), ValueError, "skip must be a whole number >= 0, not -1")


def test_dta_error_inside_the_read(files):
    want = ('{path}: column "d", row 1: the date 1.25 (days since 1960) has a fraction of a day; '
            'pass timestamps="truncate" to drop it')
    check(raised(dk.read_dta, files["day"]), ValueError, want, files["day"])


def test_dta_bad_encoding_and_timestamps(files):
    check(raised(dk.read_dta, files["dta"], encoding="klingon"), ValueError, 'unknown encoding "klingon"')
    got = raised(native.dta_read_arrow, str(files["dta"]), timestamps="round")
    check(got, ValueError, 'timestamps is "error" or "truncate", not "round"')


# ---------------------------------------------------------------- Parquet writes

def test_parquet_write_refused_types():
    for frame, dtype, to in [
        (pl.DataFrame({"x": [decimal.Decimal("1.5")]}), "Decimal", "Float64 or String"),
        (pl.DataFrame({"x": [dt.timedelta(seconds=1)]}), "Duration", "a type save_parquet writes"),
        (pl.DataFrame({"x": [[1, 2]]}), "List", "a type save_parquet writes"),
        (pl.DataFrame({"x": [{"a": 1}]}), "Struct", "a type save_parquet writes"),
    ]:
        want = f'column "x" is {dtype}, which save_parquet does not write; cast it to {to}'
        check(raised(dk.save_parquet, frame), TypeError, want)


def test_parquet_write_values_out_of_range(files):
    df = pl.DataFrame({"x": [1]})
    for sets, want in [
        ({"v": {2**60: "big"}}, 'value label set "v": the code 1152921504606847000 is not finite or beyond ±2^53'),
        ({"v": {float("nan"): "nan"}}, 'value label set "v": the code NaN is not finite or beyond ±2^53'),
        ({"v": {".A": "upper"}}, 'value label set "v": the code ".A" is not . or .a to .z'),
    ]:
        check(raised(dk.save_parquet, df, meta=dk.Meta(value_labels=sets)), ValueError, want)
    got = raised(dk.save_parquet, df, meta=dk.Meta(columns={"x": dk.Column(value_labels="nope")}))
    check(got, KeyError, 'column "x" names the value label set "nope", which meta.value_labels does not have')
    check(raised(dk.save_parquet, df, files["no_dir"]), ValueError, "{path}: " + NO_FILE, files["no_dir"])


def test_parquet_write_meta_of_the_wrong_types():
    df = pl.DataFrame({"x": [1]})
    for meta, want in [
        (dk.Meta(value_labels={"v": {1: 2}}), 'value label set "v": a label is not text'),
        (dk.Meta(value_labels={"v": {(1,): "a"}}), 'value label set "v": a code is not a number or a missing code'),
        (dk.Meta(value_labels={"v": [1]}), 'value label set "v" is not a dict'),
        (dk.Meta(characteristics={"x": {"a": 1}}), "'int' object cannot be cast as 'str'"),
        (dk.Meta(characteristics={"x": 1}), "a characteristics entry is not a dict"),
        (dk.Meta(columns={"x": dk.Column(label=1)}), "'int' object cannot be cast as 'str'"),
        (dk.Meta(label=1), "'int' object cannot be cast as 'str'"),
    ]:
        check(raised(dk.save_parquet, df, meta=meta), TypeError, want)


def test_parquet_write_native_meta():
    df = pl.DataFrame({"x": [1.0, None], "l": pl.Series([1, None], dtype=pl.Int64),
                       "c": pl.Series(["a", None], dtype=pl.Categorical)})
    letters = pl.Series([None, ".a"], dtype=pl.String)
    rows = ('the letters of column "x" have 3 rows, but the frame has 2; carry them with letters_to_columns '
            'before changing rows, or drop them with meta.missing.pop("x")')
    categorical = ('column "c" is a Categorical and has .a to .z, which a Categorical cannot hold; cast it to an '
                   'Enum and name its value label set in meta.columns["c"].value_labels, or drop its letters '
                   '(meta.missing.pop)')
    w = native.parquet_write_arrow
    for args, kind, want in [
        ((object(), None, None), TypeError, "the object does not export an Arrow stream (__arrow_c_stream__)"),
        ((df, None, {"missing": 1}), TypeError, "meta.missing is not a dict"),
        ((df, None, {"columns": 1}), TypeError, "meta.columns is not a dict"),
        ((df, None, {"value_labels": 1}), TypeError, "meta.value_labels is not a dict"),
        ((df, None, {"characteristics": 1}), TypeError, "meta.characteristics is not a dict"),
        ((df, None, {"missing": {"x": pl.Series([".a", None])}}), ValueError,
         'column "x": row 1 holds a value and the letter .a; set one of them to null'),
        ((df, None, {"missing": {"x": pl.Series([None, ".a", ".b"])}}), ValueError, rows),
        ((df, None, {"missing": {"x": pl.Series([None, "x"])}}), ValueError,
         'the letters of column "x" hold "x" in row 2, which is not one of .a to .z'),
        ((df, None, {"missing": {"x": pl.Series([None, 1])}}), TypeError,
         'the letters of column "x" are of Arrow type l, not LETTERS or String'),
        ((df, None, {"missing": {"x": object()}}), TypeError,
         "the object does not export an Arrow stream (__arrow_c_stream__)"),
        ((df, None, {"missing": {"l": letters}}), ValueError,
         'column "l" is Int64 and has .a to .z, which Int64 cannot hold; drop its letters or cast it'),
        ((df, None, {"missing": {"c": letters}}), ValueError, categorical),
        ((df, None, {"columns": {"x": (None, None, None)}}), ValueError,
         "expected tuple of length 4, but got tuple of length 3"),
    ]:
        check(raised(w, *args), kind, want)
    check(raised(w, df, None, None, compression="lzo"), ValueError,
          'unknown compression "lzo"; use one of "snappy", "zstd", "gzip", "lz4_raw" or "none"')
    check(raised(w, df, None, None, timestamps="round"), ValueError, 'timestamps is "error" or "truncate", not "round"')


# ---------------------------------------------------------------- .dta writes

def test_dta_write_refused_types_and_values(files, tmp_path):
    out = tmp_path / "w.dta"
    beyond = 'column "t": {} is beyond ±2^53, which Stata cannot store exactly'
    stata_name = 'column "{}" is not a name Stata can hold: 1 to 32 letters, digits or _, not starting with a digit'
    for frame, kind, want in [
        (pl.DataFrame({"t": [dt.time(1)]}), TypeError, 'column "t" is Time, which .dta cannot hold; cast it first'),
        (pl.DataFrame({"t": [dt.timedelta(1)]}), TypeError,
         'column "t" is Duration, which .dta cannot hold; cast it first'),
        (pl.DataFrame({"t": [decimal.Decimal("1.5")]}), TypeError,
         'column "t" is Decimal, which .dta cannot hold; cast it first'),
        (pl.DataFrame({"t": [dt.datetime(2024, 1, 1)]}).with_columns(pl.col("t").dt.replace_time_zone("UTC")),
         TypeError, 'column "t" has a time zone, which .dta cannot hold; convert it with '
                    'dt.replace_time_zone(None) or dt.convert_time_zone'),
        (pl.DataFrame({"t": pl.Series([2**53 + 1], dtype=pl.Int64)}), ValueError, beyond.format(2**53 + 1)),
        (pl.DataFrame({"t": pl.Series([-(2**53) - 1], dtype=pl.Int64)}), ValueError, beyond.format(-(2**53) - 1)),
        (pl.DataFrame({"t": [2.0**60]}).cast(pl.Int64), ValueError, beyond.format(2**60)),
        (pl.DataFrame({"t": [dt.datetime(2024, 1, 1, 0, 0, 0, 1)]}), ValueError,
         'column "t", row 1: the datetime is not a whole number of milliseconds, which a .dta datetime holds; '
         'pass timestamps="truncate" to drop the rest'),
        (pl.DataFrame({"1x": [1]}), ValueError, stata_name.format("1x")),
        (pl.DataFrame({"x" * 33: [1]}), ValueError, stata_name.format("x" * 33)),
    ]:
        check(raised(dk.save_dta, frame, out), kind, want)
    df = pl.DataFrame({"x": [1]})
    got = raised(dk.save_dta, df, out, meta=dk.Meta(columns={"x": dk.Column(value_labels="nope")}))
    check(got, KeyError, 'column "x" names the value label set "nope", which meta.value_labels does not have')
    got = raised(dk.save_dta, df, out, meta=dk.Meta(value_labels={"v": {2**60: "big"}}))
    check(got, ValueError, 'value label set "v": the code 1152921504606847000 is not finite or beyond ±2^53')
    check(raised(dk.save_dta, df, files["no_dir"]), ValueError, "{path}: " + NO_FILE, files["no_dir"])


def test_dta_write_native_meta(tmp_path):
    out = str(tmp_path / "w.dta")
    df = pl.DataFrame({"x": [1.0, None], "s": ["a", None]})
    letters = pl.Series([None, ".a"], dtype=pl.String)
    rows = ('the letters of column "x" have 3 rows, but the frame has 2; carry them with letters_to_columns '
            'before changing rows, or drop them with meta.missing.pop("x")')
    w = native.dta_write_arrow
    for args, kind, want in [
        ((object(), out, None), TypeError, "the object does not export an Arrow stream (__arrow_c_stream__)"),
        ((df, out, {"missing": 1}), TypeError, "meta.missing is not a dict"),
        ((df, out, {"columns": 1}), TypeError, "meta.columns is not a dict"),
        ((df, out, {"value_labels": 1}), TypeError, "meta.value_labels is not a dict"),
        ((df, out, {"characteristics": 1}), TypeError, "meta.characteristics is not a dict"),
        ((df, out, {"characteristics": {"x": 1}}), TypeError, "'int' object cannot be cast as 'dict'"),
        ((df, out, {"missing": {"x": pl.Series([".a", None])}}), ValueError,
         'column "x": row 1 holds a value and a letter; set one of them to null'),
        ((df, out, {"missing": {"x": pl.Series([None, ".a", ".b"])}}), ValueError, rows),
        ((df, out, {"missing": {"s": letters}}), ValueError,
         'column "s" is text and has .a to .z, which text cannot hold'),
        ((df, out, {"columns": {"x": (None, None, None)}}), ValueError,
         "expected tuple of length 4, but got tuple of length 3"),
        ((df, out, {"notes": 1}), TypeError, "'int' object cannot be cast as 'Sequence'"),
        ((df, out, {"sort": [1]}), TypeError, "'int' object cannot be cast as 'str'"),
    ]:
        check(raised(w, *args), kind, want)
    check(raised(w, df, out, None, timestamps="round"), ValueError, 'timestamps is "error" or "truncate", not "round"')
