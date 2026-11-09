"""dta_parser's native column functions for datakit (plan 0024, stage 4):
Parquet and .dta read into buffers numpy adopts without a copy, and
written from numpy arrays. They are internal (datakit is their only
caller), so these tests drive them directly: the shape of what `take`
gives, and the checks the writers make on the arrays they are given.
datakit's tests check the frames built from them against dta_parser's
reader and other tools.

Expected values come from dta_parser's pandas reader (itself tested
against haven, pandas and ReadStat).
"""

import gc
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

import dta_parser as dp
from dta_parser import _native as native

ROOT = Path(__file__).resolve().parents[2]
DTA = sorted((ROOT / "compat" / "fixtures").glob("*.dta"))


def take(frame, letters=True):
    texts = [np.empty(frame.rows, dtype=object) if f in ("vu", "vz") else None for f in frame.formats]
    return frame.take(letters, texts), texts


def test_the_abi_version_is_there():
    assert native.ABI_VERSION == 2
    assert not hasattr(native, "ArrowTable") and not hasattr(native, "parquet_read_arrow")


@pytest.mark.parametrize("path", DTA, ids=lambda p: p.stem)
def test_dta_numbers_and_codes_are_read_dtas(path):
    want = dp.read_dta(path)
    try:
        frame, meta = native.dta_read_columns(str(path))
    except ValueError as e:
        assert "fraction of a" in str(e)
        frame, meta = native.dta_read_columns(str(path), timestamps="truncate")
    assert frame.names == list(want.columns) and meta["names"] == frame.names
    cols, texts = take(frame)
    for name, item, text in zip(frame.names, cols, texts):
        w = want[name]
        if item[0] == "dta":
            values, codes = np.asarray(item[1]), np.asarray(item[2])
            assert codes.tolist() == dp.missing_codes(w).tolist(), name
            if isinstance(w.array, dp.DtaArray):
                assert np.array_equal(values, w.array._values, equal_nan=True), name
        elif item[0] == "numpy" and w.dtype.kind in "iuf":
            assert np.array_equal(np.asarray(item[1]), w.to_numpy()), name
        elif item[0] == "text":
            got = [v.decode() if isinstance(v, bytes) and isinstance(o, str) else v for v, o in zip(text, w)]
            assert got == w.tolist(), name


def test_a_frame_is_taken_once():
    frame, _ = native.dta_read_columns(str(DTA[0]))
    take(frame)
    with pytest.raises(ValueError, match="taken already"):
        take(frame)


def test_buffers_are_numpy_arrays_that_outlive_the_frame():
    frame, _ = native.dta_read_columns(str(DTA[0]))
    cols, _ = take(frame)
    arrays = [np.asarray(c[1]) for c in cols if c[0] in ("numpy", "dta")]
    assert arrays
    del frame, cols
    gc.collect()
    for a in arrays:
        assert a.flags.writeable and a.flags.c_contiguous
        assert a.base is not None and type(a.base).__name__ == "Buffer"
        a.sum() if a.dtype.kind in "iuf" else None


def test_text_targets_are_checked():
    frame, _ = native.dta_read_columns(str(DTA[0]))
    texts = [np.empty(frame.rows + 1, dtype=object) if f in ("vu", "vz") else None for f in frame.formats]
    if any(t is not None for t in texts):
        with pytest.raises(ValueError, match="shape"):
            frame.take(True, texts)


def spec(name, fmt, values, mask=None, letters=None, levels=None, ordered=False):
    return (name, fmt, values, mask, letters, levels, ordered)


@pytest.mark.parametrize("write", ["parquet", "dta"])
def test_the_writers_check_each_array(write, tmp_path):
    def run(columns, rows):
        if write == "parquet":
            return native.parquet_write_columns(columns, rows, None, None)
        return native.dta_write_columns(columns, rows, str(tmp_path / "x.dta"), None)

    good = np.arange(4, dtype=np.int32)
    run([spec("x", "i", good)], 4)
    with pytest.raises(ValueError, match="type <f8, not <i4"):
        run([spec("x", "i", np.arange(4, dtype=np.float64))], 4)
    with pytest.raises(ValueError, match=r"shape \[4\], not \(5,\)"):
        run([spec("x", "i", good)], 5)
    with pytest.raises(ValueError, match="not C-contiguous"):
        run([spec("x", "i", np.arange(8, dtype=np.int32)[::2])], 4)
    # A valid numpy array over a buffer at an odd offset: refused, since
    # the writers read through typed pointers.
    raw = np.zeros(4 * 4 + 1, dtype=np.uint8)
    unaligned = raw[1:].view(np.int32)
    assert unaligned.ctypes.data % 4 != 0
    with pytest.raises(ValueError, match="not aligned"):
        run([spec("x", "i", unaligned)], 4)
    # np.require makes it aligned, as datakit does before every call.
    run([spec("x", "i", np.require(unaligned, requirements=["C", "A"]))], 4)
    with pytest.raises(ValueError, match="mask.*type"):
        run([spec("x", "i", good, mask=np.zeros(4, dtype=np.uint8))], 4)
    with pytest.raises(ValueError, match="not a letter's code"):
        run([spec("x", "g", np.zeros(4), mask=np.ones(4, bool), letters=np.full(4, 1, np.uint8))], 4)
    with pytest.raises(TypeError, match="not a numpy array"):
        run([spec("x", "i", [1, 2, 3, 4])], 4)
    with pytest.raises(TypeError, match="row 2: a int in a column of text"):
        run([spec("x", "U", np.array(["a", 1, "c", "d"], dtype=object))], 4)


def test_the_writers_write_letters_on_missing_rows_only(tmp_path):
    values = np.array([1.0, 0.0, 0.0])
    mask = np.array([False, True, True])
    letters = np.array([0, 2, 0], dtype=np.uint8)
    native.dta_write_columns([spec("x", "g", values, mask, letters)], 3, str(tmp_path / "l.dta"), None)
    assert dp.missing_codes(dp.read_dta(tmp_path / "l.dta")["x"]).tolist() == [0, 2, 1]
    with pytest.raises(ValueError, match="row 1 holds a value and a letter"):
        native.dta_write_columns([spec("x", "g", values, mask, np.array([2, 0, 0], np.uint8))], 3,
                                 str(tmp_path / "bad.dta"), None)
    raw = native.parquet_write_columns([spec("x", "g", values, mask, letters)], 3, None, None)
    frame, _ = native.parquet_read_columns(raw)
    (item,), _ = take(frame)
    assert item[0] == "dta" and np.asarray(item[2]).tolist() == [0, 2, 1]


def test_a_categorical_is_written_with_every_level():
    codes = np.array([1, -1, 0], dtype=np.int8)
    raw = native.parquet_write_columns([spec("c", "c", codes, codes < 0, None, ["x", "y", "unused"], True)], 3,
                                       None, None)
    frame, _ = native.parquet_read_columns(raw)
    (item,), _ = take(frame)
    assert item[0] == "category" and item[2] == ["x", "y", "unused"]
    assert np.asarray(item[1]).tolist() == [1, -1, 0]


def test_pandas_text_and_bytes():
    s = pd.array(["a", None, "é" * 20], dtype=pd.Series(["a"]).dtype)
    values = np.asarray(s, dtype=object)
    raw = native.parquet_write_columns(
        [spec("s", "U", values, pd.isna(values)), spec("b", "Z", np.array([b"\x00", None, b"z"], dtype=object),
                                                         np.array([False, True, False]))], 3, None, None)
    frame, _ = native.parquet_read_columns(raw)
    cols, texts = take(frame)
    assert [c[0] for c in cols] == ["text", "text"] and [c[1] for c in cols] == [False, True]
    assert texts[0].tolist() == ["a", None, "é" * 20] and texts[1].tolist() == [b"\x00", None, b"z"]
