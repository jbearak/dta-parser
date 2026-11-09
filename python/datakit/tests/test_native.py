"""The native buffers under a read's frame (plan 0024, stage 4, "Native
arrays"): numpy adopts them without a copy, they live as long as any
array, slice or frame using them, each read has its own, and the
writers take any numpy array datakit normalises."""

import datetime as dt
import gc
import warnings

import numpy as np
import pandas as pd
import pytest

import datakit as dk
from conftest import lettered, tags
from dta_parser import DtaArray

PANDAS_3 = int(pd.__version__.split(".")[0]) >= 3


def native_base(a):
    """The object at the bottom of an array's `base` chain."""
    a = np.asarray(a)
    while isinstance(a.base, np.ndarray):
        a = a.base
    return a.base


def is_native(a):
    return type(native_base(a)).__name__ == "Buffer"


def sample():
    """A file with a column of each kind a read hands over."""
    n = 1000
    r = np.arange(n)
    df = pd.DataFrame({
        "i8": (r % 100).astype(np.int8),
        "i32": r.astype(np.int32),
        "f64": r / 7,
        "i64": r.astype(np.int64) * 2**40,
        "u16": (r % 60000).astype(np.uint16),
        "b": r % 3 == 0,
        "ts": pd.Series(r * 1_000_000, dtype="datetime64[us]"),
        "tz": pd.Series(r * 1_000_000, dtype="datetime64[us]").dt.tz_localize("UTC").dt.tz_convert("Asia/Tokyo"),
        "time": pd.to_timedelta(r, unit="s"),
        "cat": pd.Categorical(np.array(["a", "b", "c"])[r % 3]),
        "dot": DtaArray(np.where(r % 5 == 0, np.nan, r / 3), (r % 5 == 0).astype(np.uint8)),
        "byte_dot": DtaArray(np.where(r % 5 == 0, np.nan, r % 100), (r % 5 == 0).astype(np.uint8), storage="byte"),
        "I64": pd.array(np.where(r % 4 == 0, None, r), dtype="Int64"),
        "day": pd.Series(r * 86400, dtype="datetime64[s]"),
        "s": np.array(["x", "y"], dtype=object)[r % 2],
    })
    meta = dk.Meta(columns={"day": dk.Column(format="%td")})
    return dk.save_parquet(df, meta=meta), df


# Every buffer pandas holds for these columns is a native one: the read's
# own memory, or a buffer the native side made once (a DtaArray's codes,
# the float64 values of a DtaArray of byte, int, long or float, DATE's
# int64 seconds), handed over without a copy.
NATIVE = {
    "i8": lambda s: s.to_numpy(), "i32": lambda s: s.to_numpy(), "f64": lambda s: s.to_numpy(),
    "i64": lambda s: s.to_numpy(), "u16": lambda s: s.to_numpy(), "b": lambda s: s.to_numpy(),
    "ts": lambda s: s.array._ndarray, "time": lambda s: s.array._ndarray, "day": lambda s: s.array._ndarray,
    "cat": lambda s: s.array._codes, "dot": lambda s: s.array._values, "dot codes": lambda s: s.array.codes,
    "byte_dot": lambda s: s.array._values, "I64": lambda s: s.array._data, "I64 mask": lambda s: s.array._mask,
}


def test_pandas_takes_the_native_buffers_without_a_copy():
    raw, _ = sample()
    df, _ = dk.read_parquet(raw)
    for name, get in NATIVE.items():
        assert is_native(get(df[name.split()[0]])), name
    # A tz-aware timestamp: pandas 3 makes it from the int64 view without
    # a copy; pandas 2.2's astype copies.
    assert is_native(df["tz"].array._ndarray) == PANDAS_3
    # Text is a str per row, in an object array pandas holds.
    assert not is_native(df["s"].to_numpy())


def test_no_warning_reaches_the_user():
    raw, _ = sample()
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        dk.read_parquet(raw)
        dk.read_parquet(raw, skip=10, n_max=50)


@pytest.mark.parametrize("window", [{}, {"skip": 123, "n_max": 400}])
def test_arrays_outlive_the_native_frame(window):
    raw, want = sample()
    df, _ = dk.read_parquet(raw, **window)
    skip = window.get("skip", 0)
    n = len(df)
    whole = df["i32"].to_numpy()
    part = whole[10:20]
    col = df["f64"]
    sub = df[["dot", "cat"]].iloc[5:9]
    del df
    gc.collect()
    garbage = [np.ones(10_000) for _ in range(50)]
    assert whole.tolist() == list(range(skip, skip + n))
    assert part.tolist() == list(range(skip + 10, skip + 20))
    assert col.tolist() == (want["f64"].iloc[skip:skip + n]).tolist()
    assert sub["cat"].tolist() == want["cat"].iloc[skip + 5:skip + 9].tolist()
    assert sub["dot"].array.codes.tolist() == want["dot"].array.codes[skip + 5:skip + 9].tolist()
    del garbage


def test_writing_into_one_frame_changes_only_that_frame():
    raw, _ = sample()
    a, _ = dk.read_parquet(raw)
    b, _ = dk.read_parquet(raw)
    assert not np.shares_memory(a["i32"].to_numpy(), b["i32"].to_numpy())
    a.loc[0, "i32"] = 99
    a.loc[1, "dot"] = dk.tagged_na(".q")
    assert a["i32"][0] == 99 and b["i32"][0] == 0
    assert tags(a["dot"])[1] == ".q" and tags(b["dot"])[1] is None


def test_the_writers_take_an_unaligned_column(tmp_path):
    # A valid numpy array over a buffer at an odd offset: datakit makes it
    # aligned (np.require) before the native writers see it.
    raw = np.zeros(8 * 5 + 1, dtype=np.uint8)
    unaligned = raw[1:].view(np.float64)
    unaligned[:] = [1.5, 2.5, 3.5, 4.5, 5.5]
    strided = np.arange(10, dtype=np.int32)[::2]
    assert unaligned.ctypes.data % 8 != 0 and not strided.flags.c_contiguous
    df = pd.DataFrame({"x": pd.Series(unaligned, copy=False), "y": pd.Series(strided, copy=False)})
    back, _ = dk.read_parquet(dk.save_parquet(df))
    assert back["x"].tolist() == [1.5, 2.5, 3.5, 4.5, 5.5] and back["y"].tolist() == [0, 2, 4, 6, 8]
    dk.save_dta(df, tmp_path / "u.dta")
    back, _ = dk.read_dta(tmp_path / "u.dta")
    assert back["x"].tolist() == [1.5, 2.5, 3.5, 4.5, 5.5] and back["y"].tolist() == [0, 2, 4, 6, 8]


def test_dta_columns_share_too(tmp_path):
    df = pd.DataFrame({"x": np.arange(5, dtype=np.int16), "d": lettered([1.0, None, 3, None, 5], [None, ".a"] + [None] * 3),
                       "t": pd.Series([dt.datetime(2020, 1, 1)] * 5, dtype="datetime64[ms]")})
    dk.save_dta(df, tmp_path / "s.dta")
    back, _ = dk.read_dta(tmp_path / "s.dta")
    assert is_native(back["x"].to_numpy()) and is_native(back["d"].array._values)
    assert is_native(back["t"].array._ndarray)
