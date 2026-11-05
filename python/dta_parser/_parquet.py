"""Parquet files that keep what a .dta file says (plan 0018).

`read_parquet` returns the DataFrame `read_dta` returns: numpy columns in
the storage types' widths, a `StataArray` where a column holds `.a` to
`.z`, and `df.attrs["dta"]` with labels, formats, notes and value
labels. `write_parquet` writes such a frame back. What Parquet has no
place for goes into the file's `dta` metadata entry, the dta profile
(docs/parquet.md).
"""

import datetime
import decimal
import os
import tempfile
import warnings

import numpy as np
import pandas as pd

from . import _native
from ._array import StataArray, StataDtype
from ._read import _EPOCH_DAYS, _TEXT, DtaInfo, _as_dates, _count, date_kind
from ._read import read_meta as _read_dta_meta
from ._write import _label_list

_NUMPY = {"byte": np.int8, "int": np.int16, "long": np.int32, "float": np.float32, "double": np.float64}
_DAY = {"s": 86_400, "ms": 86_400_000, "us": 86_400_000_000, "ns": 86_400_000_000_000}
# Milliseconds from 1960-01-01 to 1970-01-01, Stata's epoch to Unix's.
_EPOCH_MS = -_EPOCH_DAYS * 86_400_000
_INT64_MAX = 2**63 - 1

try:
    import pyarrow as _pa
except ImportError:  # pragma: no cover - pandas without pyarrow
    _pa = None

# Text goes straight into Arrow memory when pandas' str dtype keeps it
# there (pandas 3 with pyarrow installed); otherwise into str objects.
_ARROW_TEXT = _pa is not None and getattr(_TEXT, "storage", None) == "pyarrow"


def _alloc(dtype, n, count):
    """A new array for the reader to fill, and its address: of `n`
    elements, or with `count` > 0, a 2D array of `count` columns of `n`
    (pandas' layout of a block), with a view of each column."""
    if count:
        a = np.empty((count, n), dtype=dtype)
        return a, a.__array_interface__["data"][0], list(a)
    if dtype == "codes":
        a = np.zeros(n, dtype=np.uint8)
    elif dtype == "object":
        a = np.empty(n, dtype=object)
    else:
        a = np.empty(n, dtype=dtype)
    return a, a.__array_interface__["data"][0]


def _source(source):
    """A path (str), the file's bytes, or a binary file object with seek."""
    if isinstance(source, (str, os.PathLike)):
        path = os.fsdecode(os.fspath(source))
        if not os.path.exists(path):
            raise FileNotFoundError(2, "No such file or directory", path)
        return path
    if isinstance(source, bytes):
        return source
    if isinstance(source, (bytearray, memoryview)):
        return bytes(source)
    if hasattr(source, "read") and hasattr(source, "seek"):
        return source
    raise TypeError(f"source is a path, bytes, or a binary file object with read and seek, not {type(source).__name__}")


def _head(src):
    """The first four bytes of a source from `_source`."""
    if isinstance(src, (str, bytes)):
        return _native.magic(src)
    at = src.tell()
    try:
        return src.read(4)
    finally:
        src.seek(at)


def _warn(messages):
    for m in messages:
        warnings.warn(m, UserWarning, stacklevel=3)


def _int_values(values, codes):
    """An int8, int16 or int32 column: float32 (8, 16 bits) or float64 with
    NaN where the rows read hold a null, as read_dta gives `.`."""
    if codes is None or not codes.any():
        return values
    out = values.astype(np.float32 if values.itemsize <= 2 else np.float64)
    out[codes.view(bool)] = np.nan
    return out


def _double(item, fmt):
    """A DOUBLE column: (values, display format)."""
    _, values, codes, storage, logical, nan = item
    if logical == "date":
        # R's Date written as days since 1970 because it holds .a to .z
        # (or a fraction of a day): Stata days, as read_dta gives %td.
        values += -_EPOCH_DAYS
        fmt = fmt or "%td"
        if codes is not None:
            return StataArray(values, codes, storage or "double"), fmt
        dates = _as_dates(values, np.isnan(values) if nan else None, "td")
        return (values if dates is None else dates), fmt
    if logical == "timestamp":
        # R's POSIXct as seconds since 1970: Stata's milliseconds since
        # 1960 where each value is a whole millisecond R's division gives
        # back exactly; otherwise the seconds as they are.
        present = ~np.isnan(values)
        ms = np.round(values[present] * 1000)
        if np.array_equal(ms / 1000, values[present]):
            values[present] = ms + _EPOCH_MS
            fmt = fmt or "%tc"
            if codes is None:
                dates = _as_dates(values, ~present if nan else None, "tc")
                if dates is not None:
                    return dates, fmt
    if codes is not None:
        return StataArray(values, codes, storage or "double"), fmt
    if storage in ("byte", "int", "long"):
        if nan:
            return (values.astype(np.float32) if storage != "long" else values), fmt
        return values.astype(_NUMPY[storage]), fmt
    if storage == "float":
        return values.astype(np.float32), fmt
    return values, fmt


def _arrow_text(item):
    _, data, offsets, validity, nulls = item
    buffers = [None if validity is None else _pa.foreign_buffer(validity.address, validity.size, base=validity),
               _pa.foreign_buffer(offsets.address, offsets.size, base=offsets),
               _pa.foreign_buffer(data.address, data.size, base=data)]
    arr = _pa.Array.from_buffers(_pa.large_string(), offsets.size // 8 - 1, buffers, null_count=nulls)
    return _TEXT.__from_arrow__(_pa.chunked_array([arr], type=_pa.large_string()))


def _levels(levels):
    return pd.Index(levels, dtype=_TEXT if _TEXT != object else object)


def _make_column(item, storage, fmt):
    """The pandas column of one tuple from _native.parquet_read, and its
    display format."""
    tag = item[0]
    if tag == "float_int":
        # Read as floats, since the footer did not rule out nulls; integers
        # again where the rows read hold none, as read_dta gives them.
        _, values, nulls, int_dtype = item
        return (values if nulls else values.astype(int_dtype)), fmt
    if tag == "int":
        return _int_values(item[1], item[2]), fmt
    if tag == "uint":
        values, codes = item[1], item[2]
        if codes is None or not codes.any():
            return values, fmt
        if values.itemsize == 8:
            return pd.arrays.IntegerArray(values, codes.view(bool)), fmt
        out = values.astype(np.float32 if values.itemsize <= 2 else np.float64)
        out[codes.view(bool)] = np.nan
        return out, fmt
    if tag == "int64":
        values, codes = item[1], item[2]
        if codes is None or not codes.any():
            return values, fmt
        return pd.arrays.IntegerArray(values, codes.view(bool)), fmt
    if tag == "bool":
        values, codes = item[1].view(bool), item[2]
        if codes is None or not codes.any():
            return values, fmt
        return pd.arrays.BooleanArray(values, codes.view(bool)), fmt
    if tag == "float32":
        return item[1], fmt
    if tag == "double":
        return _double(item, fmt)
    if tag == "datetime":
        _, values, unit, tz = item
        values = values.view(f"datetime64[{unit}]")
        if tz is None:
            return values, fmt
        index = pd.DatetimeIndex(values).tz_localize("UTC")
        if tz != "UTC":
            index = index.tz_convert(tz)
        return index.array, fmt
    if tag == "timedelta":
        return item[1].view(f"timedelta64[{item[2]}]"), fmt
    if tag == "category":
        _, codes, levels, ordered = item
        dtype = pd.CategoricalDtype(_levels(levels), ordered=ordered)
        return pd.Categorical.from_codes(codes, dtype=dtype, validate=False), fmt
    if tag == "arrow_text":
        return _arrow_text(item), fmt
    if tag == "decimal":
        values = item[1]
        return np.array([None if v is None else decimal.Decimal(v) for v in values], dtype=object), fmt
    # objects: text where pandas keeps str as objects, or bytes.
    values = item[1]
    if storage == "str" and _TEXT != object:
        return pd.array(values, dtype=_TEXT), fmt
    return values, fmt


def _attrs(profile, names, storage, formats):
    """The attrs["dta"] dictionary for the columns `names`."""
    p = profile if profile.get("present") else {}
    pcols = p.get("columns") or {}
    kept = set(names) | {"_dta"}
    notes = list(p.get("notes") or [])
    characteristics = {}
    for variable, name, value in p.get("characteristics") or []:
        if variable == "_dta" and name.startswith("note") and name[4:].isdigit():
            continue
        if variable in kept:
            characteristics.setdefault(variable, {})[name] = value
    columns = {}
    for name, st, fmt in zip(names, storage, formats):
        entry = pcols.get(name) or {}
        columns[name] = {
            "storage": st,
            "format": fmt or "",
            "label": entry.get("label") or "",
            "value_labels": entry.get("value_labels") or "",
        }
    return {
        "label": p.get("label") or "",
        "timestamp": p.get("timestamp") or "",
        "notes": notes,
        "characteristics": characteristics,
        "sort_order": list(p.get("sort") or []),
        "value_labels": p.get("value_labels") or {},
        "columns": columns,
    }


def read_parquet(source, columns=None, skip=0, n_max=None, nested="error"):
    """Read a Parquet file into a pandas DataFrame, as `read_dta` reads a
    .dta file.

    A file `write_parquet` wrote reads back as the frame it was given:
    the same dtypes, `StataArray` columns with their `.a` to `.z`, and
    `df.attrs["dta"]` with variable labels, display formats, value
    labels, notes and the data label. A file another tool wrote reads
    with the types below; its labels are empty.

    What each Parquet type becomes:

    - INT32, INT(8), INT(16): int32, int8, int16 (Stata's long, byte,
      int); where the rows read hold a null, float64 (32 bits) or
      float32 (8, 16), with NaN, as `read_dta` gives `.`.
    - unsigned 8, 16, 32, 64 bits: uint8 ... uint64; with nulls float32,
      float32, float64 or `UInt64`.
    - INT64: int64; with nulls `Int64`.
    - FLOAT, DOUBLE: float32, float64, null as NaN. A DOUBLE holding
      `.a` to `.z` (tagged NaNs) in the rows read is a `StataArray` of
      the storage type the file records; without them, that storage
      type's dtype, as `read_dta` gives it.
    - DECIMAL: float64 (the nearest double) up to 15 digits of
      precision; above, `decimal.Decimal` objects, every digit kept.
    - BOOLEAN: bool; with nulls `boolean`.
    - DATE: datetime64[s]. TIMESTAMP: datetime64 in the file's unit
      (seconds where `write_parquet` wrote datetime64[s]), tz-aware
      where the file stores instants (adjusted to UTC), in the zone the
      file records, else UTC. INT96: datetime64[ns]. TIME: timedelta64
      in the file's unit. Null is NaT.
    - STRING, ENUM, JSON: pandas' default text dtype (`str` on pandas
      3), null as NaN. BYTE_ARRAY or FIXED_LEN_BYTE_ARRAY without a text
      type: object, holding `bytes`, None for null.
    - a categorical `write_parquet` wrote: `category`, every level, in
      order, ordered if it was. A dictionary of text that pandas,
      polars or arrow wrote: `category`, unordered, with the distinct
      values of the rows read as levels, in order of first appearance.

    source: a path (str or os.PathLike), the file as bytes, or a binary
        file object with read and seek.
    columns: names or 0-based positions of data columns, read in the
        order given; all when None. An unknown name raises KeyError
        listing the file's columns; a position out of range IndexError.
    skip, n_max: skip that many rows, then read at most n_max (all when
        None). Only the row groups and pages that hold them are read.
    nested: "error" (the default) raises on a file with list, map or
        struct columns, which are not read, unless `columns` leaves them
        out; "skip" leaves them out.

    The index is a default RangeIndex. Damage to the dta profile is a
    warning, never an error: the values are read, the entry is not.
    The guide is docs/python.md, "Parquet files".
    """
    if nested not in ("error", "skip"):
        raise ValueError(f'nested must be "error" or "skip", not {nested!r}')
    src = _source(source)
    if columns is not None and isinstance(columns, (str, int, np.integer)):
        columns = [columns]
    if columns is not None:
        columns = list(columns)
        for c in columns:
            if isinstance(c, (bool, np.bool_)) or not isinstance(c, (str, int, np.integer)):
                raise TypeError(f"columns are names or 0-based positions, not {c!r}")
        columns = [c if isinstance(c, str) else int(c) for c in columns]
    skip = _count(skip, "skip", 0)
    n_max = _count(n_max, "n_max", None)
    raw = _native.parquet_read(src, columns, skip, n_max, nested == "skip", _alloc, _ARROW_TEXT)
    _warn(raw["warnings"])
    names = raw["names"]
    storage = raw["storage"]
    pcols = (raw["profile"].get("columns") or {}) if raw["profile"].get("present") else {}
    data = {}
    formats = []
    for name, item, st in zip(names, raw["columns"], storage):
        fmt = (pcols.get(name) or {}).get("format") or ""
        data[name], fmt = _make_column(item, st, fmt)
        formats.append(fmt)
    df = _frame(data, raw["blocks"], raw["rows"])
    df.attrs["dta"] = DtaInfo(_attrs(raw["profile"], names, storage, formats))
    return df


try:
    from pandas.api.internals import create_dataframe_from_blocks as _from_blocks
except ImportError:  # pandas before 3
    _from_blocks = None


def _frame(data, blocks, rows):
    """The DataFrame of the columns `data` (name to array). Columns read
    into one 2D array per dtype keep it as their pandas block, without a
    copy: each run of columns still in it (a column leaves when its dtype
    changed after the read) is one block."""
    names = list(data)
    if not names:
        return pd.DataFrame(index=pd.RangeIndex(rows))
    if _from_blocks is None:
        return pd.DataFrame(data, copy=False)
    columns = list(data.values())
    placed = [False] * len(columns)
    out = []
    for block, members in blocks:
        start = None
        for j, k in enumerate(members + [None]):
            live = k is not None and columns[k] is not None and isinstance(columns[k], np.ndarray) \
                and columns[k].base is block and np.shares_memory(columns[k], block[j])
            if live and start is None:
                start = j
            if not live and start is not None:
                out.append((block[start:j], np.array(members[start:j], dtype=np.intp)))
                for m in members[start:j]:
                    placed[m] = True
                start = None
    for k, values in enumerate(columns):
        if placed[k]:
            continue
        if isinstance(values, np.ndarray):
            values = values.reshape(1, -1)
            if values.dtype.kind in "Mm":
                values = pd.array(values[0])
        out.append((values, np.array([k], dtype=np.intp)))
    return _from_blocks(out, index=pd.RangeIndex(rows), columns=pd.Index(names))


def _parquet_meta(src):
    raw = _native.parquet_meta(src)
    _warn(raw["warnings"])
    data = [c for c in raw["columns"] if c[1] == "data"]
    names = [c[0] for c in data]
    pcols = (raw["profile"].get("columns") or {}) if raw["profile"].get("present") else {}
    formats = [(pcols.get(n) or {}).get("format") or "" for n in names]
    info = _attrs(raw["profile"], names, [c[5] for c in data], formats)
    columns = {}
    for name, role, physical, logical, dtype, storage, _, _ in raw["columns"]:
        entry = info["columns"].get(name) if role == "data" else None
        if entry is None:
            entry = {"storage": None, "format": "", "label": "", "value_labels": ""}
        if dtype == "str":
            # pandas' default text dtype: `str` from pandas 3, object before.
            dtype = str(_TEXT)
        columns[name] = {**entry, "role": role, "physical_type": physical, "logical_type": logical, "dtype": dtype}
    info["columns"] = columns
    info["nobs"] = raw["rows"]
    info["format"] = "parquet"
    info["row_groups"] = [{"rows": r, "compressed_bytes": c, "uncompressed_bytes": u} for r, c, u in raw["row_groups"]]
    info["compression"] = raw["compression"]
    info["created_by"] = raw["created_by"]
    return info


def read_meta(source, encoding=None):
    """What a .dta or Parquet file says about itself, without its data:
    the dictionary `read_dta` or `read_parquet` puts in
    `df.attrs["dta"]`, for every column, plus "nobs", the number of rows.
    The file's first bytes say which it is.

    For a Parquet file it also has "format" ("parquet"), "row_groups"
    (a list of {"rows", "compressed_bytes", "uncompressed_bytes"}),
    "compression" (the codecs used, such as ["snappy"]) and "created_by"
    (the writer), and each column's entry has "role" ("data", or
    "nested" for a list, map or struct, which is not read),
    "physical_type" and "logical_type" (Parquet's, such as "INT32" and
    "INT(8, signed)"), and "dtype", the pandas dtype `read_parquet`
    gives it when reading every row ("stata[byte]" for a column that
    holds `.a` to `.z`). Only the footer is read.

    source: a path, the file as bytes, or a binary file object with read
        and seek.
    encoding: for .dta files before release 118: "windows-1252" (the
        default), "latin1" or "utf-8".
    """
    src = _source(source)
    if _head(src) == b"PAR1":
        return _parquet_meta(src)
    if isinstance(src, str):
        return _read_dta_meta(src, encoding)
    data = src if isinstance(src, bytes) else src.read()
    fd, tmp = tempfile.mkstemp(suffix=".dta")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        return _read_dta_meta(tmp, encoding)
    finally:
        os.unlink(tmp)


# ---------------------------------------------------------------- write

def _zone(tz):
    """The IANA name (or +HH:MM offset) of a pandas time zone."""
    key = getattr(tz, "key", None) or getattr(tz, "zone", None)
    if key:
        return str(key)
    if isinstance(tz, datetime.timezone):
        offset = tz.utcoffset(None)
        if not offset:
            return "UTC"
        minutes = int(offset.total_seconds() // 60)
        sign = "-" if minutes < 0 else "+"
        return f"{sign}{abs(minutes) // 60:02d}:{abs(minutes) % 60:02d}"
    return str(tz)


def _native_array(values):
    values = np.ascontiguousarray(values)
    if not values.dtype.isnative:
        values = values.astype(values.dtype.newbyteorder("="))
    return values


def _code(values):
    if values.dtype.kind == "b":
        return "b1"
    return f"{values.dtype.kind}{values.dtype.itemsize}"


_INT_KIND = {"i1": "int8", "i2": "int16", "i4": "int32", "i8": "int64", "u1": "int16", "u2": "int32",
             "u4": "int64", "u8": "int64"}


def _check_uint64(name, values):
    if values.dtype == np.uint64 and values.size and values.max() > _INT64_MAX:
        bad = int(np.argmax(values > _INT64_MAX))
        raise ValueError(f"column {name!r}: row {bad + 1} holds {int(values[bad])}, more than a 64-bit "
                         "integer holds; Parquet files here hold signed 64-bit integers")


def _datetimes(name, arr, meta, keep):
    """(kind, data, dtype, codes, extra, unit for the profile) of a
    datetime64 column."""
    tz = getattr(arr.dtype, "tz", None)
    values = np.asarray(arr.tz_convert(None) if tz is not None else arr)
    unit = np.datetime_data(values.dtype)[0]
    ints = _native_array(values.view(np.int64))
    nat = ints == np.iinfo(np.int64).min
    if date_kind(meta.get("format") or "") == "td":
        if tz is not None:
            first = int(np.argmax(~nat)) if (~nat).any() else 0
            raise ValueError(f"column {name!r}: row {first + 1} has a time zone, but the column's format "
                             f"{meta['format']!r} says it is a date; drop the format from "
                             "attrs['dta']['columns'] to write it as a timestamp")
        day = _DAY[unit]
        off = (ints % day != 0) & ~nat
        if off.any():
            first = int(np.argmax(off))
            raise ValueError(f"column {name!r}: row {first + 1} is not midnight, but the column's format "
                             f"{meta['format']!r} says it is a date; drop the format from "
                             "attrs['dta']['columns'] to write it as a timestamp")
        days = np.where(nat, 0, ints // day)
        if days.size and (days.min() < -(2**31) or days.max() >= 2**31):
            raise ValueError(f"column {name!r}: a date is too far from 1970 for a Parquet DATE")
        days = days.astype(np.int32)
        codes = nat.astype(np.uint8) if nat.any() else None
        keep += [days, codes]
        return "date", days, "i4", codes, None, None
    scale, out_unit, profile_unit = 1, unit, None
    if unit == "s":
        scale, out_unit, profile_unit = 1000, "ms", "s"
        present = ints[~nat]
        if present.size and np.abs(present).max() > _INT64_MAX // 1000:
            raise ValueError(f"column {name!r}: a time is too far from 1970 to write in milliseconds")
    elif unit not in ("ms", "us", "ns"):
        raise TypeError(f"column {name!r}: cannot write datetime64[{unit}]")
    keep.append(ints)
    zone = _zone(tz) if tz is not None else None
    return "timestamp", ints, "i8", None, (out_unit, tz is not None, zone, scale), profile_unit


_STORAGE_KIND = {"byte": "int8", "int": "int16", "long": "int32", "float": "float", "double": "double"}
_MASKED = (pd.arrays.BooleanArray, pd.arrays.IntegerArray, pd.arrays.FloatingArray)


def _numbers(values, codes, kind, keep, check=None):
    values = _native_array(values)
    keep.append(values)
    if codes is not None:
        codes = _native_array(np.asarray(codes, dtype=np.uint8))
        keep.append(codes)
    return [kind, values.ctypes.data, _code(values), 0 if codes is None else codes.ctypes.data, None, None, check]


def _column(name, arr, meta, keep):
    """[kind, data address, dtype, codes address, extra, unit, check] of
    one column, `arr` its values (a numpy or extension array); `keep`
    gains the arrays the addresses point into. `check` is (storage, kind
    otherwise): write as `kind` if every value fits the storage type,
    else as the other, as write_dta chooses."""
    dtype = arr.dtype
    if isinstance(arr, np.ndarray) and dtype.kind in "iufb":
        if dtype.kind == "f":
            values = arr if dtype.itemsize >= 4 else arr.astype(np.float32)
            kind = "float" if values.dtype.itemsize == 4 else "double"
            preferred = meta.get("storage")
            if preferred in ("byte", "int", "long"):
                return _numbers(values, None, _STORAGE_KIND[preferred], keep, (preferred, kind))
            return _numbers(values, None, kind, keep)
        if dtype.kind == "b":
            return _numbers(arr, None, "bool", keep)
        _check_uint64(name, arr)
        return _numbers(arr, None, _INT_KIND[_code(arr)], keep)
    if isinstance(dtype, StataDtype):
        codes = arr._codes
        storage = dtype.storage
        check = (storage, "double") if storage != "double" else None
        return _numbers(arr._values, codes if codes.any() else None, _STORAGE_KIND[storage], keep, check)
    if isinstance(dtype, pd.CategoricalDtype):
        levels = arr.categories
        if not (levels.dtype == object or pd.api.types.is_string_dtype(levels.dtype)) or not all(
                isinstance(v, str) for v in levels):
            raise TypeError(f"column {name!r}: a category whose categories are {levels.dtype}, not text; "
                            "Parquet categoricals here have text levels: convert with .astype(str), "
                            "or write the values")
        spec = _numbers(arr.codes, None, "category", keep)
        spec[4] = ([str(v) for v in levels], bool(dtype.ordered))
        return spec
    if dtype.kind == "M":
        kind, values, code, codes, extra, unit = _datetimes(name, arr, meta, keep)
        return [kind, values.ctypes.data, code, 0 if codes is None else codes.ctypes.data, extra, unit, None]
    if dtype.kind == "m":
        raise TypeError(f"column {name!r}: cannot write timedelta64 columns; convert them to numbers first")
    if isinstance(arr, _MASKED):
        nan = np.asarray(arr.isna())
        codes = nan.astype(np.uint8) if nan.any() else None
        if dtype.kind == "f":
            values = arr.to_numpy(dtype=np.float64 if dtype.itemsize == 8 else np.float32, na_value=np.nan)
            return _numbers(values, codes, "double" if dtype.itemsize == 8 else "float", keep)
        if dtype.kind == "b":
            return _numbers(arr.to_numpy(dtype=np.uint8, na_value=0), codes, "bool", keep)
        values = arr.to_numpy(dtype=dtype.numpy_dtype, na_value=0)
        _check_uint64(name, values)
        return _numbers(values, codes, _INT_KIND[_code(values)], keep)
    if isinstance(dtype, pd.StringDtype) or dtype == object:
        if getattr(dtype, "storage", None) == "pyarrow" and _pa is not None:
            arrow = arr.__arrow_array__()
            if not isinstance(arrow, _pa.ChunkedArray):
                arrow = _pa.chunked_array([arrow])
            if arrow.type not in (_pa.string(), _pa.large_string()):
                arrow = arrow.cast(_pa.large_string())
            chunks = []
            for c in arrow.chunks:
                bufs = c.buffers()
                width = 8 if c.type == _pa.large_string() else 4
                chunks.append((0 if bufs[0] is None or c.null_count == 0 else bufs[0].address,
                               bufs[1].address, width, 0 if bufs[2] is None else bufs[2].address, len(c), c.offset))
            keep.append(arrow)
            return ["arrow_text", 0, "", 0, chunks, None, None]
        objects = np.asarray(arr, dtype=object)
        nan = np.asarray(pd.isna(objects), dtype=bool)
        if nan.any():
            objects = objects.copy()
            objects[nan] = None
        keep.append(objects)
        return ["objects", objects.ctypes.data, "O", 0, None, None, None]
    raise TypeError(f"column {name!r}: cannot write a column of dtype {dtype}")


def _arrays(df):
    """Each column's values, without making a Series per column (pandas'
    block manager gives them directly; a frame of thousands of columns
    took tens of milliseconds the other way)."""
    mgr = getattr(df, "_mgr", None)
    get = getattr(mgr, "iget_values", None)
    if get is not None:
        try:
            return [get(k) for k in range(df.shape[1])]
        except Exception:  # pragma: no cover - another pandas
            pass
    return [df.iloc[:, k].array for k in range(df.shape[1])]


def _is_default_index(index):
    return (isinstance(index, pd.RangeIndex) and index.start == 0 and index.step == 1
            and index.name is None)


def write_parquet(df, path=None, *, label=None, variable_labels=None, compression="snappy",
                  compression_level=None, row_group_size=None, missing_letters=True):
    """Write a DataFrame as a Parquet file that keeps what `read_dta` read.

    Labels, display formats, value labels, notes, characteristics, the
    sort order and the time stamp come from `df.attrs["dta"]`, as
    `write_dta` takes them, and go into the file's dta profile. A frame
    `read_dta` or `read_parquet` returned reads back from
    `read_parquet` as it was.

    What each dtype becomes:

    - int8, int16, int32, int64: INT(8), INT(16), INT32, INT64; uint8,
      uint16, uint32: INT(16), INT32, INT64; uint64: INT64 (an error
      from 2^63 up); nullable Int*, UInt*: the same, with nulls.
    - float32, float64 (and Float32, Float64): FLOAT, DOUBLE, NaN as
      null. A float column whose storage in attrs is byte, int or long
      (as `read_dta` gives a column holding `.`) is that integer type,
      if every value fits it.
    - StataArray: its storage type with its missing codes: `.` as null,
      `.a` to `.z` as tagged NaNs in a DOUBLE column, the storage type
      in the profile. With missing_letters=False, `.a` to `.z` are
      nulls and every column keeps its type.
    - bool, boolean: BOOLEAN.
    - datetime64 with a %td format in attrs: DATE (an error, naming the
      column and row, for a value that is not midnight or a time zone).
      Other datetime64: TIMESTAMP in the column's unit (seconds as
      milliseconds, read back as seconds), adjusted to UTC with the zone
      kept if tz-aware, local time if not.
    - text (str, object of str): STRING, null for None and NaN; bytes:
      BYTE_ARRAY; a column mixing str and bytes: BYTE_ARRAY, every value
      read back as bytes.
    - category of text: a dictionary-encoded STRING with every level, in
      order, and whether it is ordered.

    Any other dtype (timedelta64, a category of numbers, objects that
    are not text) raises TypeError naming the column.

    path: where to write (str or os.PathLike); None returns the file as
        bytes. The file is written beside the target and renamed, so a
        failed write leaves an existing file as it was.
    label: the data label (default attrs["dta"]["label"]).
    variable_labels: a dict of column name to variable label, over attrs.
    compression: "snappy" (the default), "zstd", "gzip", "lz4_raw" or
        "none". compression_level: the codec's level (zstd 1 to 22, gzip
        0 to 9), or None for its default.
    row_group_size: rows per row group; None for up to 262,144 rows and
        about 1 GiB of values.
    missing_letters: write `.a` to `.z` as tagged NaNs (True), or as
        nulls (False) for tools that count NaN as a value.

    Only columns are written: an index other than a default RangeIndex
    gives a warning; call df.reset_index() first to keep it. The arrays
    are read in place, by several threads on large frames: nothing may
    change them until write_parquet returns.
    """
    if not isinstance(df, pd.DataFrame):
        raise TypeError("write_parquet writes a pandas DataFrame")
    if not isinstance(compression, str):
        raise TypeError("compression is a codec's name, such as \"snappy\" or \"zstd\"")
    if compression_level is not None:
        if isinstance(compression_level, (bool, np.bool_)) or not isinstance(compression_level, (int, np.integer)):
            raise TypeError("compression_level is a whole number or None")
        compression_level = int(compression_level)
    if row_group_size is not None:
        if isinstance(row_group_size, (bool, np.bool_)) or not isinstance(row_group_size, (int, np.integer)) \
                or row_group_size < 1:
            raise ValueError("row_group_size is a whole number of rows, at least 1, or None")
        row_group_size = int(row_group_size)
    if not _is_default_index(df.index):
        name = f"the index {df.index.name!r}" if df.index.name is not None else f"the {type(df.index).__name__}"
        warnings.warn(f"write_parquet writes columns only, not {name}; call df.reset_index() first to keep it",
                      UserWarning, stacklevel=2)
    info = df.attrs.get("dta") or {}
    columns_meta = info.get("columns") or {}
    variable_labels = variable_labels or {}
    names = list(df.columns)
    for name in names:
        if not isinstance(name, str):
            raise TypeError(f"column names must be text, not {name!r}")
    if len(set(names)) != len(names):
        dup = next(n for n in names if names.count(n) > 1)
        raise ValueError(f"column {dup!r} appears more than once")
    keep = []
    specs = []
    entries = []
    checks = []
    for k, (name, arr) in enumerate(zip(names, _arrays(df))):
        meta = columns_meta.get(name) or {}
        spec = _column(name, arr, meta, keep)
        if spec[6] is not None:
            checks.append(k)
        specs.append(spec)
        var_label = variable_labels.get(name, meta.get("label"))
        entries.append((name, var_label or None, meta.get("format") or None, meta.get("value_labels") or None,
                        spec[5]))
    if checks:
        # Each storage type is used where every value fits it, else the
        # wider type, as write_dta chooses.
        fits = _native.parquet_fits([(specs[k][1], specs[k][2], specs[k][3], specs[k][6][0]) for k in checks],
                                    len(df))
        for k, ok in zip(checks, fits):
            if not ok:
                specs[k][0] = _STORAGE_KIND[specs[k][6][1]] if specs[k][6][1] in _STORAGE_KIND else specs[k][6][1]
    specs = [(name, spec[0], spec[1], spec[2], spec[3], spec[4]) for name, spec in zip(names, specs)]
    present = set(names) | {"_dta"}
    characteristics = []
    for variable, table in (info.get("characteristics") or {}).items():
        if variable in present:
            characteristics.extend((variable, str(n), str(v)) for n, v in table.items())
    sort = []
    for name in info.get("sort_order") or []:
        if name not in names:
            break
        sort.append(name)
    data_label = label if label is not None else info.get("label")
    profile = {
        "label": data_label or None,
        "timestamp": info.get("timestamp") or None,
        "notes": [str(n) for n in info.get("notes") or []],
        "characteristics": characteristics,
        "sort": sort,
        "value_labels": _label_list(dict(info.get("value_labels") or {})),
        "columns": entries,
    }
    target = None if path is None else os.fsdecode(os.fspath(path))
    return _native.parquet_write(target, len(df), specs, profile, compression, compression_level, row_group_size,
                                 bool(missing_letters))
