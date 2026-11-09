"""What every read and save shares: the pandas frame and its `Meta` from
the native reads, `.a` to `.z` in `DtaArray` columns, `factors`, and the
columns a save hands the native writers."""

from __future__ import annotations

import decimal as _decimal
import os
import re
import warnings

import numpy as np
import pandas as pd

from dta_parser import DtaArray, DtaDtype, missing
from dta_parser._array import dta_keys
from dta_parser._write import _fits

from . import _tagged
from ._meta import Column, Meta

# pandas' default dtype for text: `str` from pandas 3, object before.
TEXT = pd.Series(["a"]).dtype


def warn(message, category=UserWarning):
    """A warning pointing at the caller of the public function."""
    # _frame -> the public function -> its caller
    warnings.warn(message, category, stacklevel=4)


# ---------------------------------------------------------------- arguments

def check_window(skip, n_max):
    for name, v in (("skip", skip), ("n_max", n_max)):
        if v is None and name == "n_max":
            continue
        if isinstance(v, bool) or not isinstance(v, int) or v < 0:
            raise ValueError(f"{name} must be a whole number >= 0, not {v!r}")


def check_columns(columns):
    """None, or a list of names and 0-based positions."""
    if columns is None:
        return None
    if isinstance(columns, (str, int)) and not isinstance(columns, bool):
        columns = [columns]
    columns = list(columns)
    for c in columns:
        if isinstance(c, bool) or not isinstance(c, (str, int)):
            raise TypeError(f"columns are names or 0-based positions, not {c!r}")
    return columns


def check_letters(letters):
    if not isinstance(letters, bool):
        raise TypeError(f"letters must be True or False, not {letters!r}")


def check_choice(name, value, choices):
    if value not in choices:
        shown = ", ".join(f'"{c}"' for c in choices[:-1]) + f' or "{choices[-1]}"'
        raise ValueError(f"{name} is {shown}, not {value!r}")


def source_of(source):
    """A path (str), bytes, or a binary file object with read and seek."""
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


def path_of(path):
    path = os.fsdecode(os.fspath(path))
    if not os.path.exists(path):
        raise FileNotFoundError(2, "No such file or directory", path)
    return path


# ---------------------------------------------------------------- reads

def meta_of(m):
    """The Meta of a native read's dict."""
    return Meta(
        label=m["label"],
        notes=list(m["notes"]),
        characteristics=m["characteristics"],
        sort=list(m["sort"]),
        timestamp=m["timestamp"],
        columns={c[0]: Column(c[1], c[2], c[3], c[4]) for c in m["columns"]},
        value_labels=m["value_labels"],
        rows=m["rows"],
    )


def series(array, name):
    """A Series over `array` without a copy."""
    return pd.Series(array, name=name, copy=False)


def decimals(text, precision, name):
    """A DECIMAL column read as text (an object array, None for a null):
    float64 up to 15 digits of precision (a DtaArray when it has a null),
    else `decimal.Decimal` objects, every digit kept (plan 0018)."""
    if precision <= 15:
        null = pd.isna(text)
        values = np.zeros(len(text), dtype=np.float64)
        values[~null] = np.asarray(text[~null], dtype=np.float64)
        if null.any():
            return DtaArray(np.where(null, np.nan, values), null.astype(np.uint8))
        return values
    out = np.empty(len(text), dtype=object)
    for i, t in enumerate(text):
        out[i] = None if t is None else _decimal.Decimal(t)
    return out


def text_column(values, binary):
    """An object array of text as pandas' default text dtype; of bytes,
    as it is."""
    if binary or TEXT == object:
        return values
    return pd.array(values, dtype=TEXT)


def columns_of(frame, m, letters):
    """The pandas columns of a native read, as {name: Series}; the names
    of the columns holding `.a` to `.z`, and of those a categorical
    holding them made level numbers. Sets `meta`'s formats for dates and
    timestamps read as Stata's numbers."""
    texts = [np.empty(frame.rows, dtype=object) if f in ("vu", "vz") else None for f in frame.formats]
    taken = frame.take(letters, texts)
    flags = {c[0]: c[6] for c in m["columns"]}
    out = {}
    lettered = set()
    level_numbers = set()
    origins = {}
    for name, item, text in zip(frame.names, taken, texts):
        kind = item[0]
        if kind == "numpy":
            a = np.asarray(item[1])
            zone = item[2]
            if zone is not None:
                unit = np.datetime_data(a.dtype)[0]
                out[name] = series(a.view(np.int64), name).astype(pd.DatetimeTZDtype(unit, zone))
            else:
                out[name] = series(a, name)
        elif kind == "masked":
            values, mask = np.asarray(item[1]), np.asarray(item[2])
            if values.dtype == bool:
                array = pd.arrays.BooleanArray(values, mask)
            else:
                array = pd.arrays.IntegerArray(values, mask)
            out[name] = series(array, name)
        elif kind == "dta":
            _, values, codes, storage, origin, has = item
            out[name] = series(DtaArray._simple(np.asarray(values), np.asarray(codes), DtaDtype(storage)), name)
            if has:
                lettered.add(name)
            if origin is not None:
                origins[name] = origin
        elif kind == "category":
            _, codes, levels, ordered = item
            cat = pd.Categorical.from_codes(np.asarray(codes), dtype=pd.CategoricalDtype(levels, ordered=ordered),
                                            validate=False)
            out[name] = series(cat, name)
        else:
            flag = flags.get(name)
            if flag is not None and flag.startswith("decimal("):
                precision = int(flag[len("decimal("):-1].split(",")[0])
                out[name] = series(decimals(text, precision, name), name)
            elif flag == "categorical":
                present = text[~pd.isna(text)]
                levels = pd.unique(present) if len(present) else []
                cat = pd.Categorical(text, categories=pd.Index(levels, dtype=object), ordered=False)
                if len(levels) and TEXT != object:
                    cat = cat.set_categories(pd.Index(levels, dtype=TEXT))
                out[name] = series(cat, name)
            else:
                out[name] = series(text_column(text, item[1]), name)
    return out, lettered, origins


def finish(frame, m, *, factors, letters, markers=False):
    """`(df, meta)` from a native read. Each numeric column with a missing
    value in the rows read is a `DtaArray`, `.a` to `.z` in its codes
    (`letters=False` reads them as `.`). With `markers` (a .dta read), the
    columns marked `dtaparser_categorical` are categories again
    (`restore_categoricals`), unless they hold letters. `factors` makes
    labelled columns categories (`to_factors`), those holding letters
    too, as R's datakit does: their letters become NaN, with one
    warning."""
    for w in m["warnings"]:
        warn(w)
    meta = meta_of(m)
    cols, lettered, origins = columns_of(frame, m, letters)
    for name, origin in origins.items():
        if origin == "date":
            _set_format(meta, name, "%td")
        elif origin == "datetime":
            _set_format(meta, name, "%tc")
        else:
            col = meta.columns.get(name) or Column()
            if col.ordered is not None:
                meta.columns[name] = Column(col.label, col.format, col.value_labels, None)
    for name, f in zip(frame.names, frame.formats):
        if f == "tdD" and name not in origins:
            date_format(meta, name)
    if markers:
        stale = restore_categoricals(cols, meta, skip=set() if factors else lettered)
        if stale:
            shown = ", ".join(f'"{n}"' for n in stale)
            warn(f"{'column' if len(stale) == 1 else 'columns'} {shown} {'was' if len(stale) == 1 else 'were'} "
                 "written as categoricals, but the file has changed since: their value label set changed, a value "
                 "has no label, two codes share a text, a code is not a whole number, `.` is labelled, a date format "
                 "was given, or a column has both markers; read as unmarked columns")
    if factors:
        to_factors(cols, meta, skip=set(origins))
        lost = [n for n in lettered if n not in origins and isinstance(cols[n].dtype, pd.CategoricalDtype)]
        if lost:
            shown = ", ".join(f'"{n}"' for n in lost)
            warn(f".a to .z in {shown} are NaN in {'its category' if len(lost) == 1 else 'their categories'}; "
                 "read with factors=False to keep them")
    if cols:
        df = pd.DataFrame(cols, copy=False)
    else:
        df = pd.DataFrame(index=pd.RangeIndex(frame.rows))
    return df, meta


def date_format(meta, name):
    """Give a Parquet DATE column the format `%td` when it has none, so
    that saving it writes a DATE again (datetime64[s] holds it as
    seconds). read_parquet and read_parquet_info both use it."""
    col = meta.columns.get(name) or Column()
    if col.format is None:
        meta.columns[name] = Column(col.label, "%td", col.value_labels, col.ordered)


def _set_format(meta, name, fmt):
    col = meta.columns.get(name) or Column()
    if not (col.format or "").startswith(fmt):
        meta.columns[name] = Column(col.label, fmt, col.value_labels, col.ordered)


# The characteristics that mark a column written from a categorical:
# "ordered <set>" or "unordered <set>". R's factors (plan 0020), and
# categoricals (plan 0023), which may hold .a to .z.
FACTOR_MARK = "dtaparser_factor"
CATEGORICAL_MARK = "dtaparser_categorical"
_MARK = re.compile(r"(ordered|unordered) (.+)", re.DOTALL)
# The numbers a .dta long holds; a value label's code is one.
_LONG = (-2_147_483_647, 2_147_483_620)


def marked_levels(mark, set_name, value_labels):
    """The levels and order a `dtaparser_categorical` mark gives a column
    whose value label set is `set_name`, as `(codes, texts, ordered)`, or
    None when the file no longer holds what was written: the mark names
    another set or one the file lacks, the set labels `.`, a code is not
    a whole number within long's range, or two codes share a text."""
    m = _MARK.fullmatch(mark) if isinstance(mark, str) else None
    table = value_labels.get(set_name) if set_name else None
    if m is None or m.group(2) != set_name or table is None or "." in table:
        return None
    numeric = sorted((k, t) for k, t in table.items() if not isinstance(k, str))
    for k, _ in numeric:
        if not (float(k).is_integer() and _LONG[0] <= k <= _LONG[1]):
            return None
    texts = [t for _, t in numeric]
    if len(set(texts)) != len(texts):
        return None
    return [float(k) for k, _ in numeric], texts, m.group(1) == "ordered"


def numbers(s):
    """`(values, present)` of a numeric column: float64 values and where
    they are not missing; None for any other column."""
    a = s.array
    if isinstance(a, DtaArray):
        return a._values, a.codes == 0
    if s.dtype.kind in "iub" and not isinstance(s.dtype, pd.CategoricalDtype):
        values = s.to_numpy(dtype=np.float64, na_value=np.nan)
        return values, ~np.isnan(values)
    if s.dtype.kind == "f":
        values = s.to_numpy(dtype=np.float64, na_value=np.nan)
        return values, ~np.isnan(values)
    return None


def _is_integer(s):
    a = s.array
    if isinstance(a, DtaArray):
        return a.dtype.storage in ("byte", "int", "long")
    return s.dtype.kind in "iub"


def restore_categoricals(cols, meta, skip=()):
    """Each column marked `dtaparser_categorical` that passes the checks
    of plan 0023 made a category of its set's texts in code order, unused
    ones included; its `meta.columns[name].ordered` from the mark, its
    mark gone from `meta.characteristics`. The columns that fail
    (`marked_levels`, a column that is not numeric, as a `%td` one is
    once read, a value without a label, or both marks) are left as read,
    unmarked; their names are returned. A column of `skip` (one holding
    `.a` to `.z`, which a category cannot hold) is left as its numbers,
    its mark kept, without a warning. `dtaparser_factor` alone is left as
    it is (an R factor; plan 0020)."""
    stale = []
    for name in list(cols):
        chars = meta.characteristics.get(name) or {}
        if CATEGORICAL_MARK not in chars or name in skip:
            continue
        s = cols[name]
        col = meta.columns.get(name) or Column()
        levels = None
        got = numbers(s)
        if FACTOR_MARK not in chars and got is not None:
            levels = marked_levels(chars[CATEGORICAL_MARK], col.value_labels, meta.value_labels)
        at = None
        if levels is not None:
            codes, texts, ordered = levels
            values, present = got
            keys = np.asarray(codes, dtype=np.float64)
            if keys.size:
                at = np.minimum(np.searchsorted(keys, np.where(present, values, keys[0])), len(keys) - 1)
                if not (keys[at] == values)[present].all():
                    levels = None
            elif present.any():
                levels = None
        if levels is None:
            stale.append(name)
            continue
        codes, texts, ordered = levels
        present = got[1]
        codes_out = np.where(present, at, -1) if at is not None else np.full(len(s), -1)
        cat = pd.Categorical.from_codes(codes_out, dtype=pd.CategoricalDtype(texts, ordered=ordered))
        cols[name] = pd.Series(cat, name=name)
        meta.columns[name] = Column(col.label, col.format, col.value_labels, ordered)
        rest = {k: v for k, v in chars.items() if k != CATEGORICAL_MARK}
        if rest:
            meta.characteristics[name] = rest
        else:
            del meta.characteristics[name]
    return stale


def r_number(v):
    """A double as R's `as.character` writes it: 15 significant digits, in
    fixed or scientific notation, whichever is narrower (fixed on a tie)."""
    if v == 0:
        return "0"
    digits = 15
    for d in range(1, 16):
        if float(f"{v:.{d - 1}e}") == float(f"{v:.14e}"):
            digits = d
            break
    sci = f"{v:.{digits - 1}e}"
    mant, exp = sci.split("e")
    e = int(exp)
    sci = f"{mant}e{'-' if e < 0 else '+'}{abs(e):02d}"
    fixed = f"{float(f'{v:.14e}'):.{max(0, digits - 1 - e)}f}"
    return fixed if len(fixed) <= len(sci) else sci


def to_factors(cols, meta, skip=()):
    """Each labelled numeric column made a category, as R's datakit's
    `read_parquet(factors = TRUE)` makes a factor (`labelled_factor`):
    its levels the sorted values and codes, labelled where a label
    exists; codes sharing a label one level."""
    for name, col in meta.columns.items():
        if name not in cols or name in skip or col.value_labels is None:
            continue
        s = cols[name]
        got = numbers(s)
        if got is None or s.dtype.kind == "b":
            continue
        labels = {k: v for k, v in meta.value_labels.get(col.value_labels, {}).items() if not isinstance(k, str)}
        if not labels:
            continue
        values, present = got
        found = sorted({float(v) for v in np.unique(values[present])} | {float(k) for k in labels})
        integer = _is_integer(s)
        text = []
        for v in found:
            if v in labels:
                text.append(labels[v])
            elif integer:
                text.append(str(int(v)))
            else:
                text.append(r_number(v))
        levels = list(dict.fromkeys(text))
        index = {t: i for i, t in enumerate(levels)}
        keys = np.asarray(found, dtype=np.float64)
        code_of = np.asarray([index[t] for t in text], dtype=np.int64)
        codes = np.full(len(values), -1, dtype=np.int64)
        if keys.size:
            at = np.minimum(np.searchsorted(keys, values[present]), len(keys) - 1)
            codes[present] = code_of[at]
        cols[name] = pd.Series(pd.Categorical.from_codes(codes, dtype=pd.CategoricalDtype(levels)), name=name)


# ---------------------------------------------------------------- saves

def check_frame(df, who):
    if not isinstance(df, pd.DataFrame):
        raise TypeError(f"{who} takes a pandas DataFrame, not {type(df).__name__}")
    names = list(df.columns)
    for n in names:
        if not isinstance(n, str):
            raise TypeError(f"{who}: column names are text, not {n!r}; rename the column first")
    seen = set()
    for n in names:
        if n in seen:
            raise ValueError(f'{who}: column "{n}" appears more than once')
        seen.add(n)


_UNIT = {"s": "s", "ms": "m", "us": "u", "ns": "n"}
_PER_DAY = {"s": 86_400, "ms": 86_400_000, "us": 86_400_000_000, "ns": 86_400_000_000_000}
_NS = {"s": 1_000_000_000, "ms": 1_000_000, "us": 1_000, "ns": 1}
_STORAGE_FORMAT = {"byte": ("c", np.int8), "int": ("s", np.int16), "long": ("i", np.int32),
                   "float": ("f", np.float32), "double": ("g", np.float64)}
_WIDER = ("byte", "int", "long", "float", "double")
_NUMPY_FORMAT = {"i1": "c", "i2": "s", "i4": "i", "i8": "l", "u1": "C", "u2": "S", "u4": "I", "u8": "L",
                 "f4": "f", "f8": "g", "b1": "b"}


def _array(a, dtype):
    """`a` as a C-contiguous, aligned array of `dtype`, as the native
    writers take it."""
    return np.require(np.asarray(a, dtype=dtype), dtype=dtype, requirements=["C", "A"])


def stored(storage, values, present):
    """The storage a `DtaArray` of `storage` is written in: its own when
    every value fits it exactly, else the next of byte, int, long, float
    and double that holds every value."""
    v = values[present]
    for s in _WIDER[_WIDER.index(storage):]:
        if _fits(v, s):
            return s
    return "double"


def _date_kind(fmt):
    if fmt and re.match(r"%-?(td|d)", fmt):
        return "td"
    if fmt and re.match(r"%-?tc", fmt):
        return "tc"
    return None


def column_spec(name, s, fmt, missing_letters, who):
    """The tuple the native writers take for column `name` (`frame.rs`,
    `build`): `(name, format, values, mask, letters, levels, ordered)`."""
    dtype = s.dtype
    a = s.array
    none = None

    def letters_of(codes):
        if not missing_letters or not (codes > 1).any():
            return none
        return _array(np.where(codes > 1, codes, 0), np.uint8)

    if isinstance(a, DtaArray):
        codes = a.codes
        present = codes == 0
        storage = stored(a.dtype.storage, a._values, present)
        f, np_type = _STORAGE_FORMAT[storage]
        values = np.where(present, a._values, 0).astype(np_type)
        return (name, f, _array(values, np_type), _array(~present, bool), letters_of(codes), none, False)
    if isinstance(dtype, pd.CategoricalDtype):
        cats = dtype.categories
        if len(cats) and pd.api.types.infer_dtype(cats, skipna=False) != "string":
            raise TypeError(f'column "{name}" is a category of {cats.dtype}; {who} writes categories of text: '
                            f'make its categories text first (s.cat.rename_categories(str))')
        codes = s.cat.codes.to_numpy()
        f = _NUMPY_FORMAT[f"{codes.dtype.kind}{codes.dtype.itemsize}"]
        return (name, f, _array(codes, codes.dtype), _array(codes < 0, bool), none, [str(c) for c in cats],
                bool(dtype.ordered))
    if isinstance(dtype, pd.DatetimeTZDtype):
        if who == "save_dta":
            raise TypeError(f'column "{name}" has a time zone, which .dta cannot hold; make it naive with '
                            f'dt.tz_convert(zone).dt.tz_localize(None)')
        unit = dtype.unit
        values = a.asi8 if hasattr(a, "asi8") else s.to_numpy().view(np.int64)
        return (name, f"ts{_UNIT[unit]}:{dtype.tz}", _array(values, np.int64), _array(s.isna().to_numpy(), bool),
                none, none, False)
    if dtype.kind == "M":
        values = s.to_numpy()
        unit = np.datetime_data(values.dtype)[0]
        if unit not in _UNIT:
            values = values.astype("datetime64[s]" if unit in ("D", "h", "m") else "datetime64[ns]")
            unit = np.datetime_data(values.dtype)[0]
        ints = values.view(np.int64)
        nat = np.isnat(values)
        if _date_kind(fmt) == "td" and not (ints[~nat] % _PER_DAY[unit]).any():
            days = np.where(nat, 0, ints // _PER_DAY[unit])
            if days.size and (days.min() < np.iinfo(np.int32).min or days.max() > np.iinfo(np.int32).max):
                raise ValueError(f'column "{name}": a date is outside the range of dates')
            return (name, "tdD", _array(days, np.int32), _array(nat, bool), none, none, False)
        return (name, f"ts{_UNIT[unit]}:", _array(ints, np.int64), _array(nat, bool), none, none, False)
    if dtype.kind == "m":
        if who == "save_dta":
            raise TypeError(f'column "{name}" is {dtype}, which .dta cannot hold; convert it to numbers first')
        values = s.to_numpy()
        unit = np.datetime_data(values.dtype)[0]
        nat = np.isnat(values)
        ns = values.astype("timedelta64[ns]").view(np.int64)
        outside = ~nat & ((ns < 0) | (ns >= 86_400 * 1_000_000_000))
        if outside.any():
            r = int(np.argmax(outside))
            raise ValueError(f'column "{name}", row {r + 1}: {values[r]} is not a time of day (0 to 24 hours), '
                             "which Parquet's TIME holds")
        return (name, "ttn", _array(ns, np.int64), _array(nat, bool), none, none, False)
    if isinstance(a, pd.arrays.BooleanArray) or (isinstance(dtype, pd.api.extensions.ExtensionDtype)
                                                 and hasattr(a, "_mask") and hasattr(a, "_data")):
        values, mask = a._data, a._mask
        if values.dtype.kind == "f":
            mask = mask | np.isnan(values)
        key = f"{values.dtype.kind}{values.dtype.itemsize}"
        if key not in _NUMPY_FORMAT:
            raise TypeError(f'column "{name}" is {dtype}, which {who} does not write')
        return (name, _NUMPY_FORMAT[key], _array(values, values.dtype), _array(mask, bool), none, none, False)
    if isinstance(dtype, np.dtype) and dtype.kind in "iufb":
        key = f"{dtype.kind}{dtype.itemsize}"
        if key not in _NUMPY_FORMAT:
            raise TypeError(f'column "{name}" is {dtype}, which {who} does not write; convert it to float64')
        values = s.to_numpy()
        if dtype.kind == "f":
            values64 = values.astype(np.float64, copy=False)
            codes = _tagged.float_codes(values64)
            return (name, _NUMPY_FORMAT[key], _array(values, dtype), _array(codes != 0, bool), letters_of(codes),
                    none, False)
        return (name, _NUMPY_FORMAT[key], _array(values, dtype), none, none, none, False)
    if isinstance(dtype, pd.StringDtype) or dtype == object:
        values = s.to_numpy(dtype=object)
        null = pd.isna(values)
        kind = pd.api.types.infer_dtype(values, skipna=True)
        if kind in ("string", "empty"):
            return (name, "U", _array(values, object), _array(null, bool), none, none, False)
        if kind == "bytes":
            return (name, "Z", _array(values, object), _array(null, bool), none, none, False)
        if kind == "decimal":
            raise TypeError(f'column "{name}" holds decimal.Decimal values, which {who} does not write; '
                            "convert it to float (astype(float)) or to text (astype(str))")
        if any(isinstance(v, missing.MissingValue) for v in values):
            raise TypeError(f'column "{name}" is object and holds .a to .z (MissingValue); a numeric column '
                            f'keeps them as dta[double]: df["{name}"] = df["{name}"].astype("dta[double]")')
        raise TypeError(f'column "{name}" is object holding {kind} values, which {who} does not write; '
                        "make it text, bytes or numbers")
    raise TypeError(f'column "{name}" is {dtype}, which {who} does not write')


def prepare(df, meta, missing_letters, who):
    """The columns to write (`column_spec`), and what the native writer
    takes of meta: label, notes, characteristics, sort (checked),
    timestamp, columns (each category's `ordered` from its dtype) and
    value_labels."""
    check_frame(df, who)
    if meta is not None and not isinstance(meta, Meta):
        raise TypeError(f"meta is a datakit.Meta or None, not {type(meta).__name__}")
    entries = meta.columns if meta is not None else {}
    specs = []
    for name in df.columns:
        col = entries.get(name)
        specs.append(column_spec(name, df[name], col.format if col else None, missing_letters, who))
    has_letters = any(sp[4] is not None for sp in specs)
    ordered = {sp[0]: sp[6] for sp in specs if sp[5] is not None}
    if meta is None:
        if not has_letters and not any(ordered.values()):
            return specs, None
        meta = Meta()
    kept = set(df.columns)
    columns = {k: (c.label, c.format, c.value_labels, c.ordered) for k, c in meta.columns.items() if k in kept}
    for name, o in ordered.items():
        c = columns.get(name, (None, None, None, None))
        columns[name] = (c[0], c[1], c[2], o)
    profile = {
        "label": meta.label,
        "notes": list(meta.notes),
        "characteristics": {k: v for k, v in meta.characteristics.items() if k in kept or k == "_dta"},
        "sort": checked_sort(df, meta.sort, missing_letters),
        "timestamp": meta.timestamp,
        "columns": columns,
        "value_labels": meta.value_labels,
    }
    return specs, profile


def sort_key(s, missing_letters):
    """Arrays that sort the rows of `s` as Stata orders them, the first
    the most significant: values, then `.`, then `.a` to `.z`."""
    a = s.array
    dtype = s.dtype
    if isinstance(dtype, pd.CategoricalDtype):
        codes = s.cat.codes.to_numpy().astype(np.int64)
        return [codes < 0, codes]
    if dtype.kind in "Mm":
        # Exact int64 counts, `NaT` last: missingness first, so that no
        # value stands in for it.
        ints = a.asi8 if hasattr(a, "asi8") else s.to_numpy().view(np.int64)
        missing = s.isna().to_numpy()
        return [missing, np.where(missing, 0, ints)]
    if dtype.kind in "iu" and not isinstance(a, DtaArray):
        # Exact integers (a float64 key would merge values above 2^53),
        # missing values of a nullable column last.
        int_dtype = np.uint64 if dtype.kind == "u" else np.int64
        missing = s.isna().to_numpy()
        values = s.to_numpy(dtype=int_dtype, na_value=0) if missing.any() else s.to_numpy().astype(int_dtype)
        return [missing, values]
    if isinstance(dtype, np.dtype) and dtype.kind == "f":
        codes = _tagged.float_codes(s.to_numpy(dtype=np.float64))
        if not missing_letters:
            codes = np.minimum(codes, 1)
        return [dta_keys(DtaArray(s.to_numpy(dtype=np.float64), codes))]
    if isinstance(a, DtaArray) or dtype.kind in "iub":
        keys = dta_keys(s)
        if isinstance(a, DtaArray) and not missing_letters:
            keys = dta_keys(DtaArray(a._values, np.minimum(a.codes, 1)))
        return [np.asarray(keys, dtype=np.float64)]
    # Text (or bytes): a missing value sorts as empty text, as in Stata.
    values = s.to_numpy(dtype=object)
    null = pd.isna(values)
    present = values[~null]
    empty = b"" if len(present) and isinstance(present[0], bytes) else ""
    filled = values.copy()
    filled[null] = empty
    codes, _ = pd.factorize(filled, sort=True)
    return [codes]


def checked_sort(df, sort, missing_letters):
    """`sort` up to its first column not in `df`, if the rows are in that
    order as Stata orders them (values, then `.`, then `.a` to `.z`);
    otherwise [] with a warning."""
    keys = []
    for name in sort:
        if name not in df.columns:
            break
        keys.append(name)
    if not keys or len(df) < 2:
        return keys
    arrays = [a for k in keys for a in sort_key(df[k], missing_letters)]
    order = np.lexsort(arrays[::-1])
    if np.array_equal(order, np.arange(len(df))):
        return keys
    warn(f"meta.sort ({', '.join(keys)}) does not describe the order of the frame's rows, so it is not saved; "
         "sort with the guide's recipe (Stata's order: numbers, then `.`, then the letters) to keep it")
    return []
