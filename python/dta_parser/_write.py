import datetime
import os
import re

import numpy as np
import pandas as pd

from . import _native
from ._array import StataDtype
from ._read import _EPOCH_DAYS, date_kind
from .missing import MissingValue

_RESERVED = {
    "_all", "_b", "byte", "_coef", "_cons", "double", "float", "if", "in", "int", "long", "_n", "_N",
    "_pi", "_pred", "_rc", "_skip", "strL", "using", "with",
}
# A letter or _, then up to 31 letters, digits or _.
_NAME = re.compile(r"[^\W\d]\w{0,31}")

_RANGES = {"byte": (-127, 100), "int": (-32767, 32740), "long": (-2147483647, 2147483620)}
_FLOAT_MAX = float(np.array([0x7EFFFFFF], dtype=np.uint32).view(np.float32)[0])
_DOUBLE_MAX = float(np.array([0x7FDFFFFFFFFFFFFF], dtype=np.uint64).view(np.float64)[0])
_EXACT = 2**53
_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
_DAY_MS = 86_400_000
# Milliseconds per unit of a datetime64, or for finer units, units per ms.
_COARSE = {"ms": 1, "s": 1000, "m": 60_000, "h": 3_600_000, "D": _DAY_MS, "W": 7 * _DAY_MS}
_FINE = {"us": 1000, "ns": 1_000_000}


def _check_name(name):
    if not isinstance(name, str) or not _NAME.fullmatch(name) or name in _RESERVED or re.fullmatch(r"str\d+", name):
        raise ValueError(
            f"column {name!r} is not a name Stata can hold: 1 to 32 letters, digits or _, "
            "not starting with a digit, and not a reserved word"
        )


def _fits(values, storage):
    """Whether every number in `values` fits `storage` exactly."""
    if values.size == 0:
        return True
    if storage in _RANGES:
        lo, hi = _RANGES[storage]
        if values.dtype.kind in "iub":
            return bool(values.min() >= lo and values.max() <= hi)
        return bool(np.all(values == np.floor(values)) and values.min() >= lo and values.max() <= hi)
    if values.dtype.kind in "iu":
        limit = 2**24 if storage == "float" else _EXACT
        return bool(values.min() >= -limit and values.max() <= limit)
    if storage == "float":
        return bool(np.all(np.abs(values) <= _FLOAT_MAX) and np.all(values.astype(np.float32) == values))
    return bool(np.all(np.abs(values) <= _DOUBLE_MAX))


def _integer_storage(name, values):
    """The smallest of byte, int and long holding every integer, else double."""
    for storage in ("byte", "int", "long"):
        if _fits(values, storage):
            return storage
    lo, hi = int(values.min()), int(values.max())
    if lo < -_EXACT or hi > _EXACT:
        bad = lo if lo < -_EXACT else hi
        raise ValueError(f"column {name!r}: {bad} is beyond ±2^53, which Stata cannot store exactly")
    return "double"


def _choose(name, values, missing, preferred, default):
    """`preferred` (from attrs) if every value fits it, else `default`."""
    present = values if missing is None else values[~missing]
    if values.dtype.kind in "iu" and present.size and (present.min() < -_EXACT or present.max() > _EXACT):
        _integer_storage(name, present)
    if preferred in ("byte", "int", "long", "float", "double") and _fits(present, preferred):
        return preferred
    if default is None:
        return _integer_storage(name, present)
    return default


def _native_array(values):
    values = np.ascontiguousarray(values)
    if not values.dtype.isnative:
        values = values.astype(values.dtype.newbyteorder("="))
    return values


def _datetimes(name, series, meta):
    """(values, codes, storage, format) of a datetime64 column."""
    if isinstance(series.dtype, pd.DatetimeTZDtype):
        raise TypeError(f"column {name!r}: cannot write time-zone-aware datetimes; convert them first")
    values = series.to_numpy()
    unit = np.datetime_data(values.dtype)[0]
    ints = values.view(np.int64)
    nat = np.isnat(values)
    present = ints[~nat]
    if unit in _FINE:
        if np.any(present % _FINE[unit]):
            raise ValueError(f"column {name!r}: times finer than a millisecond cannot be written")
        ms = present // _FINE[unit]
    elif unit in _COARSE:
        ms = present * _COARSE[unit]
    else:
        raise TypeError(f"column {name!r}: cannot write datetime64[{unit}]")
    kind = date_kind(meta.get("format", ""))
    preferred = meta.get("storage")
    out = np.zeros(len(values), dtype=np.int64)
    if not np.any(ms % _DAY_MS) and kind != "tc":
        out[~nat] = ms // _DAY_MS - _EPOCH_DAYS
        storage = _choose(name, out[~nat], None, preferred if kind == "td" else None, "long")
        fmt = meta["format"] if kind == "td" else "%td"
        return out, nat, storage, fmt
    out = out.astype(np.float64)
    out[~nat] = ms - _EPOCH_DAYS * _DAY_MS
    storage = _choose(name, out[~nat], None, preferred if kind == "tc" else None, "double")
    fmt = meta["format"] if kind == "tc" else "%tc"
    return out, nat, storage, fmt


def _column(name, series, meta, sets):
    """(storage, format, value label set, dtype code, data, codes) of one
    column; `sets` gains a value label set for a categorical."""
    dtype = series.dtype
    fmt = meta.get("format", "")
    set_name = meta.get("value_labels", "")
    preferred = meta.get("storage")
    missing = None
    if isinstance(dtype, StataDtype):
        arr = series.array
        values, codes = arr._values, arr._codes
        storage = _choose(name, values, codes != 0, dtype.storage, "double")
        missing = codes
    elif isinstance(dtype, pd.CategoricalDtype):
        cat = series.array
        values = cat.codes.astype(np.int32)
        nan = values == -1
        missing = nan if nan.any() else None
        storage = "long"
        set_name = name
        sets[name] = {i: str(c) for i, c in enumerate(cat.categories)}
        fmt = ""
    elif dtype.kind == "M":
        values, nat, storage, fmt = _datetimes(name, series, meta)
        missing = nat if nat.any() else None
    elif isinstance(series.array, (pd.arrays.BooleanArray, pd.arrays.IntegerArray, pd.arrays.FloatingArray)):
        arr = series.array
        nan = np.asarray(arr.isna())
        if dtype.kind == "f":
            values = arr.to_numpy(dtype=np.float64, na_value=np.nan)
            nan |= np.isnan(values)
            values = np.where(nan, 0.0, values)
            default = "float" if dtype == pd.Float32Dtype() else "double"
        else:
            values = arr.to_numpy(dtype=np.uint8 if dtype.kind == "b" else np.int64 if dtype.kind == "i" else np.uint64,
                                  na_value=0)
            default = "byte" if dtype.kind == "b" else None
        missing = nan if nan.any() else None
        storage = _choose(name, values, missing, preferred, default)
    elif isinstance(dtype, np.dtype) and dtype.kind in "biuf":
        values = series.to_numpy()
        if dtype.kind == "f":
            if dtype.itemsize < 4:
                values = values.astype(np.float32)
            nan = np.isnan(values)
            storage = _choose(name, values, nan, preferred, "float" if values.dtype.itemsize == 4 else "double")
        else:
            storage = _choose(name, values, None, preferred, "byte" if dtype.kind == "b" else None)
    elif isinstance(dtype, pd.StringDtype) or dtype == object:
        objects = series.to_numpy(dtype=object)
        nan = np.asarray(pd.isna(objects), dtype=bool)
        if nan.any():
            objects = objects.copy()
            objects[nan] = ""
        storage = "strL" if preferred == "strL" else "str"
        fmt = fmt if fmt.endswith("s") else ""
        return storage, fmt, set_name, "O", objects, None
    else:
        raise TypeError(f"column {name!r}: cannot write a column of dtype {dtype}")
    if fmt.endswith("s"):
        fmt = ""
    values = _native_array(values)
    if values.dtype.kind == "b":
        code = "b1"
    else:
        code = f"{values.dtype.kind}{values.dtype.itemsize}"
    codes = None if missing is None else _native_array(np.asarray(missing, dtype=np.uint8))
    return storage, fmt, set_name, code, values, codes


def _label_list(sets):
    out = []
    for name, table in sets.items():
        labels = []
        for key, text in table.items():
            if isinstance(key, MissingValue):
                labels.append((float("nan"), key.code, str(text)))
            elif key is None or key != key:
                labels.append((float("nan"), 1, str(text)))
            else:
                labels.append((float(key), 0, str(text)))
        out.append((name, labels))
    return out


def _timestamp(value):
    if value is None:
        value = datetime.datetime.now()
    if isinstance(value, str):
        return value
    return f"{value.day:02d} {_MONTHS[value.month - 1]} {value.year} {value.hour:02d}:{value.minute:02d}"


def write_dta(df, path, *, label=None, variable_labels=None, timestamp=None):
    """Write a DataFrame as a Stata .dta file, release 118.

    Labels, formats, storage types, value labels, notes, characteristics
    and the sort order come from `df.attrs["dta"]` where it has them (as
    `read_dta` leaves it); the rest is chosen from the dtypes:

    - bool: byte; integers: the smallest of byte, int and long that holds
      every value, else double (an error beyond ±2^53);
    - float32, float64: float, double, NaN as `.`; nullable dtypes: their
      values, NA as `.`; StataArray: its storage and missing codes;
    - category: its codes as long, its categories as value labels;
    - datetime64: %td (long) if every value is midnight, else %tc (double,
      milliseconds); NaT as `.`;
    - text: strN up to 2045 bytes, else strL; None, NaN and pd.NA as "";
      bytes: binary strL.

    Anything else, or a column name Stata cannot hold, is an error naming
    the column. The index is not written.

    label: the data label (default attrs["dta"]["label"]).
    variable_labels: a dict of column name to label, over attrs.
    timestamp: a datetime or text for the file's timestamp; default now.
    """
    if not isinstance(df, pd.DataFrame):
        raise TypeError("write_dta writes a pandas DataFrame")
    info = df.attrs.get("dta") or {}
    columns_meta = info.get("columns") or {}
    variable_labels = variable_labels or {}
    names = list(df.columns)
    for name in names:
        _check_name(name)
    if len(set(names)) != len(names):
        dup = next(n for n in names if names.count(n) > 1)
        raise ValueError(f"column {dup!r} appears more than once")
    sets = dict(info.get("value_labels") or {})
    made = {}
    specs = []
    keep = []
    for k, name in enumerate(names):
        meta = columns_meta.get(name) or {}
        storage, fmt, set_name, code, values, codes = _column(name, df.iloc[:, k], meta, made)
        keep.append((values, codes))
        var_label = variable_labels.get(name, meta.get("label", ""))
        specs.append((name, storage, fmt or "", var_label or "", set_name or "", code,
                      values.ctypes.data, 0 if codes is None else codes.ctypes.data))
    sets.update(made)

    present = set(names) | {"_dta"}
    characteristics = []
    for variable, table in (info.get("characteristics") or {}).items():
        if variable in present:
            characteristics.extend((variable, n, str(v)) for n, v in table.items())
    notes = info.get("notes") or []
    if notes:
        characteristics.append(("_dta", "note0", str(len(notes))))
        characteristics.extend(("_dta", f"note{i + 1}", str(n)) for i, n in enumerate(notes))

    sort_order = []
    for name in info.get("sort_order") or []:
        if name not in names:
            break
        sort_order.append(names.index(name))

    data_label = label if label is not None else info.get("label", "")
    _native.write(os.fspath(path), len(df), specs, _label_list(sets), characteristics, data_label or "",
                  _timestamp(timestamp), sort_order)
