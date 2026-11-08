import copy
import os
import re
import tempfile
import warnings

import numpy as np
import pandas as pd

from . import _native
from ._array import DtaArray
from .missing import MissingValue, from_code

_NUMPY = {"byte": np.int8, "int": np.int16, "long": np.int32, "float": np.float32, "double": np.float64}

# pandas' default dtype for text: `str` from pandas 3, object before.
_TEXT = pd.Series(["a"]).dtype

# Days from 1970-01-01 back to Stata's epoch, 1960-01-01.
_EPOCH_DAYS = -3653
_EXACT = 2.0**53


def date_kind(fmt):
    """"td" for a daily date format, "tc" for milliseconds without leap
    seconds, else None. `%tC` (with leap seconds) is not a date here."""
    if re.match(r"%-?(td|d)", fmt):
        return "td"
    if re.match(r"%-?tc", fmt):
        return "tc"
    return None


class DtaInfo(dict):
    """The dict in `df.attrs["dta"]`. pandas deep-copies `attrs` into every
    frame and column it derives (`df[c]`, `df.loc[...]`, `sort_values`),
    which for a file of thousands of variables costs milliseconds each
    time; this dict is shared instead. Give a frame its own with
    `sub.attrs["dta"] = df.attrs["dta"].copy()`."""

    def __deepcopy__(self, memo):
        return self

    def copy(self):
        """A deep copy: one frame's metadata to change without the others'."""
        return DtaInfo(copy.deepcopy(dict(self)))


def _open_path(path):
    path = os.fspath(path)
    if not os.path.exists(path):
        raise FileNotFoundError(2, "No such file or directory", path)
    return path


def _value_labels(sets):
    out = {}
    for name, labels in sets:
        table = {}
        for value, code, text in labels:
            if code:
                key = from_code(code)
            else:
                key = int(value) if float(value).is_integer() else value
            table[key] = text
        out[name] = table
    return out


def _info(raw, cols):
    """The attrs["dta"] dictionary for the variables at `cols`."""
    variables = raw["variables"]
    names = [variables[i][0] for i in cols]
    kept = set(names) | {"_dta"}
    notes = {}
    characteristics = {}
    for variable, name, value in raw["characteristics"]:
        n = re.fullmatch(r"note(\d+)", name)
        if variable == "_dta" and n:
            if int(n.group(1)) > 0:
                notes[int(n.group(1))] = value
            continue
        if variable in kept:
            characteristics.setdefault(variable, {})[name] = value
    columns = {}
    for i in cols:
        name, storage, fmt, label, set_name = variables[i]
        columns[name] = {"storage": storage, "format": fmt, "label": label, "value_labels": set_name}
    return {
        "release": raw["release"],
        "byte_order": raw["byte_order"],
        "encoding": raw["encoding"],
        "label": raw["label"],
        "timestamp": raw["timestamp"],
        "notes": [notes[k] for k in sorted(notes)],
        "characteristics": characteristics,
        "sort_order": [variables[i][0] for i in raw["sort_order"]],
        "value_labels": _value_labels(raw["value_labels"]),
        "columns": columns,
    }


# The characteristic that marks a column written from a categorical
# (plan 0020): "ordered" or "unordered", a space, and its label set.
FACTOR_MARK = "dtaparser_factor"


def _marked_factor(mark, set_name, sets, values, codes, flag):
    """The categorical a column marked with `mark` was written from, or
    None when the file no longer holds it: its label set changed, a
    value has no label, two codes share a text, or it holds .a to .z."""
    m = re.fullmatch(r"(ordered|unordered) (.+)", mark)
    table = sets.get(set_name)
    if m is None or m.group(2) != set_name or table is None or flag > 1:
        return None
    labels = sorted((float(k), t) for k, t in table.items() if not isinstance(k, MissingValue))
    texts = [t for _, t in labels]
    if len(set(texts)) != len(texts):
        return None
    ordered = m.group(1) == "ordered"
    present = codes == 0
    if not labels:
        # A category with no categories holds only missing values.
        return None if present.any() else pd.Categorical.from_codes(np.full(len(codes), -1), categories=[], ordered=ordered)
    keys = np.asarray([k for k, _ in labels])
    at = np.searchsorted(keys, values.astype(np.float64))
    at = np.minimum(at, len(keys) - 1)
    if not (keys[at] == values)[present].all():
        return None
    return pd.Categorical.from_codes(np.where(present, at, -1), categories=texts, ordered=ordered)


def read_meta(source, encoding=None):
    """What a .dta file says about itself, without its data: the
    dictionary `read_dta` puts in `df.attrs["dta"]`, for every column,
    plus "nobs", the number of rows.

    source: a path, the file as bytes, or a binary file object with read.
    encoding: decodes text in files older than release 118:
        "windows-1252" (the default), "latin1" or "utf-8".

    Parquet files are datakit's: `datakit.read_parquet_info` describes
    one (docs/python.md, "A Parquet file's schema and metadata").
    """
    if isinstance(source, (str, os.PathLike)):
        path = _open_path(source)
        with open(path, "rb") as f:
            _not_parquet(f.read(4))
        raw = _native.meta(path, encoding)
    else:
        data = bytes(source) if isinstance(source, (bytes, bytearray, memoryview)) else source.read()
        _not_parquet(data[:4])
        fd, tmp = tempfile.mkstemp(suffix=".dta")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(data)
            raw = _native.meta(tmp, encoding)
        finally:
            os.unlink(tmp)
    info = _info(raw, range(len(raw["variables"])))
    info["nobs"] = raw["nobs"]
    return info


def _not_parquet(head):
    if head == b"PAR1":
        raise ValueError("this is a Parquet file; dta_parser 0.3 reads .dta files only. "
                         "Use datakit.read_parquet_info (pip install ./python/datakit)")


def _select(columns, names):
    if columns is None:
        return list(range(len(names)))
    if isinstance(columns, (str, int, np.integer)):
        columns = [columns]
    index = {n: i for i, n in enumerate(names)}
    out = []
    for c in columns:
        if isinstance(c, (bool, np.bool_)):
            raise TypeError(f"columns are names or 0-based indices, not {c!r}")
        if isinstance(c, (int, np.integer)):
            if not 0 <= c < len(names):
                raise IndexError(f"there is no column {c}; the file has {len(names)}")
            i = int(c)
        elif isinstance(c, str):
            if c not in index:
                raise ValueError(f"the file has no column named {c!r}")
            i = index[c]
        else:
            raise TypeError(f"columns are names or 0-based indices, not {c!r}")
        if i not in out:
            out.append(i)
    return out


def _count(value, what, default):
    if value is None:
        return default
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, (int, np.integer, float)):
        raise TypeError(f"{what} must be a whole number >= 0")
    if value != value or value < 0:
        raise ValueError(f"{what} must be a whole number >= 0")
    return default if value == float("inf") else int(value)


def _as_dates(values, missing, kind):
    """A datetime64 array of a date column, or None if any value is not a
    whole day (td) or millisecond (tc) that numpy holds exactly."""
    numbers = values[~missing].astype(np.float64) if missing is not None else values.astype(np.float64)
    if not np.all(np.isfinite(numbers)) or not np.all(numbers == np.floor(numbers)):
        return None
    limit = _EXACT / 86400 if kind == "td" else _EXACT
    if numbers.size and np.abs(numbers).max() > limit:
        return None
    ints = np.zeros(len(values), dtype=np.int64)
    good = slice(None) if missing is None else ~missing
    ints[good] = numbers.astype(np.int64)
    if kind == "td":
        out = ((ints + _EPOCH_DAYS) * 86400).view("datetime64[s]")
    else:
        out = (ints + _EPOCH_DAYS * 86_400_000).view("datetime64[ms]")
    if missing is not None:
        out[missing] = np.datetime64("NaT", "s" if kind == "td" else "ms")
    return out


def read_dta(path, columns=None, skip=0, n_max=None, encoding=None, dates=True):
    """Read a Stata .dta file (releases 104 to 119) into a pandas DataFrame.

    Numeric columns keep their storage width (int8, int16, int32, float32,
    float64) when no value is missing; with only `.` missing they become
    float32 (byte, int, float) or float64 (long, double) with NaN; with any
    of `.a` to `.z` they are a DtaArray, which keeps each row's code.
    Text is pandas' default string dtype; a strL column holding binary
    values is object, with `bytes` for those values.

    Labels, display formats, storage types, value labels, notes,
    characteristics and the sort order are in `df.attrs["dta"]` (see
    `read_meta`).

    A column that write_dta wrote from a category (or R's save_dta from
    a factor) is a category again, ordered if it was, with its value
    labels as categories in order of code. It is marked by a
    characteristic, and read as a category only if the file still holds
    what it held: the same label set, a label on every non-missing
    value, no two codes with the same text, and no .a to .z. Otherwise
    it is read as it would be unmarked, with one warning naming such
    columns.

    columns: names or 0-based indices, read in the order given; all when None.
    skip, n_max: skip that many rows, then read at most n_max (all when None).
    encoding: for files before release 118: "windows-1252" (the default),
        "latin1" or "utf-8".
    dates: convert %td columns to datetime64[s] and %tc to datetime64[ms],
        `.` to NaT, when every value converts exactly and none is `.a` to
        `.z`. %tC stays numbers.
    """
    path = _open_path(path)
    raw = _native.meta(path, encoding)
    variables = raw["variables"]
    cols = _select(columns, [v[0] for v in variables])
    nobs = raw["nobs"]
    start = min(_count(skip, "skip", 0), nobs)
    count = min(_count(n_max, "n_max", nobs), nobs - start)

    targets = []
    arrays = []
    for i in cols:
        storage = variables[i][1]
        if storage in _NUMPY:
            values = np.empty(count, dtype=_NUMPY[storage])
            codes = np.zeros(count, dtype=np.uint8)
            arrays.append((values, codes))
            targets.append((values.ctypes.data, codes.ctypes.data))
        else:
            objects = np.empty(count, dtype=object)
            arrays.append((objects, None))
            targets.append((objects.ctypes.data, 0))
    flags = _native.read(path, encoding, cols, start, count, targets)

    marks = {v: value for v, n, value in raw["characteristics"] if n == FACTOR_MARK}
    sets = _value_labels(raw["value_labels"]) if marks else {}
    stale = []
    data = {}
    for i, (values, codes), flag in zip(cols, arrays, flags):
        name, storage, fmt = variables[i][:3]
        if codes is None:
            data[name] = values if flag else pd.array(values, dtype=_TEXT) if _TEXT != object else values
            continue
        if name in marks:
            factor = _marked_factor(marks[name], variables[i][4], sets, values, codes, flag)
            if factor is not None:
                data[name] = factor
                continue
            stale.append(name)
        kind = date_kind(fmt) if dates else None
        if kind and flag <= 1:
            converted = _as_dates(values, codes == 1 if flag else None, kind)
            if converted is not None:
                data[name] = converted
                continue
        if flag == 0:
            data[name] = values
        elif flag == 1:
            if storage in ("byte", "int"):
                values = values.astype(np.float32)
            elif storage == "long":
                values = values.astype(np.float64)
            if storage in ("byte", "int", "long"):
                values[codes == 1] = np.nan
            data[name] = values
        else:
            data[name] = DtaArray(values.astype(np.float64, copy=False), codes, storage)
    if stale:
        shown = ", ".join(stale)
        warnings.warn(f"write_dta wrote {shown} as categories, but the file has changed since: their value "
                      "label set changed, a value has no label or shares its text, or they hold .a to .z; "
                      "read as unmarked columns", UserWarning, stacklevel=2)
    df = pd.DataFrame(data, copy=False)
    if not data:
        df = pd.DataFrame(index=pd.RangeIndex(count))
    df.attrs["dta"] = DtaInfo(_info(raw, cols))
    return df
