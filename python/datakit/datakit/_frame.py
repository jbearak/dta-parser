"""What every read and save shares: the frame and its `Meta` from the
native reads, `.a` to `.z` as tagged NaNs in the frame, `factors`, and
the checks a save makes before handing the frame to the native
writers."""

from __future__ import annotations

import os
import re
import warnings

import polars as pl

from . import _tagged
from ._meta import LETTERS, Column, Meta

# Stata's dates count from 1960, polars' from 1970.
_DAYS_1960 = 3653
_MS_1960 = _DAYS_1960 * 86_400_000
_UNIT_MS = {"ms": 1, "us": 1_000, "ns": 1_000_000}


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
    """The Meta of a native read's dict (without `missing`)."""
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


def frame_of(native_frame, m):
    """The polars frame of a native read, with the casts the read asks
    for: a categorical of the rows' values, and DECIMAL read as text."""
    df = pl.DataFrame(native_frame)
    casts = []
    for c in m["columns"]:
        flag = c[6]
        if flag is None:
            continue
        if flag == "categorical":
            casts.append(pl.col(c[0]).cast(pl.Categorical))
        elif flag.startswith("decimal("):
            precision, scale = map(int, flag[len("decimal("):-1].split(","))
            if precision <= 38:
                casts.append(decimal(df.get_column(c[0]), precision, scale))
    return df.with_columns(casts) if casts else df


def decimal(text, precision, scale):
    """A DECIMAL column read as text, as Decimal(precision, scale); as
    Decimal(38, scale) when a value has more digits than its precision
    allows (as some writers make), with a warning; else text."""
    try:
        return text.cast(pl.Decimal(precision, scale))
    except pl.exceptions.InvalidOperationError:
        pass
    try:
        out = text.cast(pl.Decimal(38, scale))
        kept = f"Decimal(38, {scale})"
    except pl.exceptions.InvalidOperationError:
        out, kept = text, "String"
    warn(f'column "{text.name}" holds values with more digits than its DECIMAL({precision}, {scale}) allows; '
         f"read as {kept}, every digit kept")
    return out


def finish(native_frame, native_letters, m, *, factors, letters, markers=False):
    """`(df, meta)` from a native read. With `letters`, each column holding
    `.a` to `.z` in the rows read is Float64 with them as tagged NaNs
    (`with_letters`); without, they are nulls like `.`. With `markers` (a
    .dta read), the columns marked `dtaparser_categorical` are Enums again
    (`restore_categoricals`), unless they hold letters. `factors` makes
    labelled columns Enums (`to_factors`), those holding letters too, as
    R's datakit does: their letters become nulls, with one warning."""
    for w in m["warnings"]:
        warn(w)
    df = frame_of(native_frame, m)
    meta = meta_of(m)
    found = {}
    if native_letters is not None and letters:
        ldf = pl.DataFrame(native_letters)
        found = {name: ldf.get_column(name) for name in ldf.columns if ldf.get_column(name).null_count() < ldf.height}
    enums = {n for n in found if isinstance(df.schema[n], pl.Enum)}
    if markers:
        df, stale = restore_categoricals(df, meta, skip=set() if factors else set(found))
        if stale:
            shown = ", ".join(f'"{n}"' for n in stale)
            warn(f"{'column' if len(stale) == 1 else 'columns'} {shown} {'was' if len(stale) == 1 else 'were'} "
                 "written as categoricals, but the file has changed since: their value label set changed, a value "
                 "has no label, two codes share a text, a code is not a whole number, `.` is labelled, a date format "
                 "was given, or a column has both markers; read as unmarked columns")
    if factors:
        df = to_factors(df, meta)
        lost = [n for n in found if n not in enums and isinstance(df.schema[n], pl.Enum)]
        if lost:
            shown = ", ".join(f'"{n}"' for n in lost)
            warn(f".a to .z in {shown} are nulls in {'its Enum' if len(lost) == 1 else 'their Enums'}; "
                 "read with factors=False to keep them")
            found = {n: v for n, v in found.items() if n not in lost}
    if found:
        df = with_letters(df, meta, found)
    return df, meta


def with_letters(df, meta, found):
    """`df` with each column of `found` (a Series of LETTERS per column)
    Float64, its letters tagged NaNs. Integers and Float32 are cast, and
    their dtype kept in `meta._storage`; a Date or Datetime becomes
    Stata's number (days, or milliseconds, since 1960) with a `%td` or
    `%tc` format; an Enum its level numbers from 1, its value label set
    labelling them."""
    changes = []
    for name, letters in found.items():
        s = df.get_column(name)
        t = s.dtype
        if t in (pl.Int8, pl.Int16, pl.Int32, pl.Float32):
            meta._storage[name] = t
            values = s.cast(pl.Float64)
        elif t == pl.Float64:
            values = s
        elif t == pl.Date:
            values = s.cast(pl.Int32).cast(pl.Float64) + _DAYS_1960
            _set_format(meta, name, "%td")
        elif isinstance(t, pl.Datetime):
            values = s.dt.epoch(t.time_unit).cast(pl.Float64) / _UNIT_MS[t.time_unit] + _MS_1960
            _set_format(meta, name, "%tc")
        elif isinstance(t, pl.Enum):
            values = s.to_physical().cast(pl.Float64) + 1
            col = meta.columns.get(name) or Column()
            if col.ordered is not None:
                meta.columns[name] = Column(col.label, col.format, col.value_labels, None)
        else:
            continue
        changes.append(_tagged.tag(values.alias(name), letters))
    return df.with_columns(changes) if changes else df


def _set_format(meta, name, fmt):
    col = meta.columns.get(name) or Column()
    if not (col.format or "").startswith(fmt):
        meta.columns[name] = Column(col.label, fmt, col.value_labels, col.ordered)


# The characteristics that mark a column written from a categorical:
# "ordered <set>" or "unordered <set>". R's factors (plan 0020), and
# Enums and Categoricals (plan 0023), which may hold .a to .z.
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


def restore_categoricals(df, meta, skip=()):
    """`df` with each column marked `dtaparser_categorical` that passes the
    checks of plan 0023 an Enum of its set's texts in code order, unused
    ones included; its `meta.columns[name].ordered` from the mark, its mark
    gone from `meta.characteristics`. Its `.a` to `.z` stay with the read's
    letters. The columns that fail (`marked_levels`, a column that is not
    numeric, as a `%td` one is once read, a value without a label, or both
    marks) are left as read, unmarked; their names are returned with
    `df`. A column of `skip` (one holding `.a` to `.z`, which an Enum
    cannot hold) is left as its numbers, its mark kept, without a
    warning. `dtaparser_factor` alone is left as it is (an R factor; plan
    0020)."""
    changes = []
    stale = []
    for name in df.columns:
        chars = meta.characteristics.get(name) or {}
        if CATEGORICAL_MARK not in chars or name in skip:
            continue
        s = df.get_column(name)
        col = meta.columns.get(name) or Column()
        levels = None
        if FACTOR_MARK not in chars and s.dtype.is_numeric():
            levels = marked_levels(chars[CATEGORICAL_MARK], col.value_labels, meta.value_labels)
        if levels is not None:
            codes, texts, ordered = levels
            present = s.drop_nulls()
            if s.dtype.is_float():
                present = present.filter(present.is_not_nan())
            if not present.cast(pl.Float64).is_in(codes).all():
                levels = None
        if levels is None:
            stale.append(name)
            continue
        changes.append(s.cast(pl.Float64).replace_strict(codes, texts, default=None, return_dtype=pl.Enum(texts))
                       .alias(name))
        meta.columns[name] = Column(col.label, col.format, col.value_labels, ordered)
        rest = {k: v for k, v in chars.items() if k != CATEGORICAL_MARK}
        if rest:
            meta.characteristics[name] = rest
        else:
            del meta.characteristics[name]
    return (df.with_columns(changes) if changes else df), stale


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


def to_factors(df, meta):
    """Each labelled numeric column as an Enum, as R's datakit's
    `read_parquet(factors = TRUE)` makes a factor (`labelled_factor`)."""
    changes = []
    for name, col in meta.columns.items():
        if name not in df.columns or col.value_labels is None:
            continue
        s = df.get_column(name)
        if not s.dtype.is_numeric():
            continue
        labels = {k: v for k, v in meta.value_labels.get(col.value_labels, {}).items() if not isinstance(k, str)}
        if not labels:
            continue
        present = s.drop_nulls()
        if s.dtype.is_float():
            present = present.filter(present.is_not_nan())
        values = sorted({float(v) for v in present.unique().to_list()} | {float(k) for k in labels})
        integer = s.dtype.is_integer()
        text = []
        for v in values:
            if v in labels:
                text.append(labels[v])
            elif integer:
                text.append(str(int(v)))
            else:
                text.append(r_number(v))
        levels = list(dict.fromkeys(text))
        changes.append(
            s.cast(pl.Float64).replace_strict(values, text, default=None, return_dtype=pl.Enum(levels)).alias(name)
        )
    return df.with_columns(changes) if changes else df


# ---------------------------------------------------------------- saves

def check_frame(df, who):
    if isinstance(df, pl.LazyFrame):
        raise TypeError(f"{who} takes a polars DataFrame, not a LazyFrame; call .collect() on it first")
    if not isinstance(df, pl.DataFrame):
        raise TypeError(f"{who} takes a polars DataFrame, not {type(df).__name__}")


_INT_RANGE = {pl.Int8: (-127, 100), pl.Int16: (-32_767, 32_740), pl.Int32: (-2_147_483_647, 2_147_483_620)}


def stored(values, storage):
    """`values` (Float64, its letters already null) as `storage`, the dtype
    the read widened it from, when every value fits that type exactly;
    else `values` as it is, written as double."""
    if storage is None:
        return values
    present = values.drop_nulls()
    if storage == pl.Float32:
        if present.is_nan().any() or not present.cast(pl.Float32).cast(pl.Float64).equals(present):
            return values
        return values.cast(pl.Float32)
    lo, hi = _INT_RANGE[storage]
    if present.is_nan().any() or not (present == present.round(0)).all() or present.is_infinite().any():
        return values
    if present.len() and (present.min() < lo or present.max() > hi):
        return values
    return values.cast(storage)


def prepare(df, meta, missing_letters, who):
    """The frame to write, and what the native writer takes of meta:
    label, notes, characteristics, sort (checked), timestamp, columns,
    value_labels, and missing, the letters of each Float64 column holding
    tagged NaNs (which the frame given the writer holds as nulls)."""
    check_frame(df, who)
    if meta is not None and not isinstance(meta, Meta):
        raise TypeError(f"meta is a datakit.Meta or None, not {type(meta).__name__}")
    storage = meta._storage if meta is not None else {}
    letters = {}
    changes = []
    for name, t in df.schema.items():
        if t != pl.Float64:
            continue
        s = df.get_column(name)
        plain, found = _tagged.untag(s)
        if found is not None and missing_letters:
            letters[name] = found
        out = stored(plain, storage.get(name))
        if found is not None or out.dtype != t:
            changes.append(out)
    out = df.with_columns(changes) if changes else df
    if meta is None:
        if not letters:
            return out, None
        meta = Meta()
    kept = set(out.columns)
    profile = {
        "label": meta.label,
        "notes": list(meta.notes),
        "characteristics": {k: v for k, v in meta.characteristics.items() if k in kept or k == "_dta"},
        "sort": checked_sort(out, meta.sort, letters),
        "timestamp": meta.timestamp,
        "columns": {k: (c.label, c.format, c.value_labels, c.ordered) for k, c in meta.columns.items() if k in kept},
        "value_labels": meta.value_labels,
        "missing": letters,
    }
    return out, profile


def checked_sort(df, sort, letters):
    """`sort` up to its first column not in `df`, if the rows are in that
    order as Stata orders them (values, then `.`, then `.a` to `.z`);
    otherwise [] with a warning."""
    keys = []
    for name in sort:
        if name not in df.columns:
            break
        keys.append(name)
    if not keys or df.height < 2:
        return keys
    parts = {}
    for i, k in enumerate(keys):
        s = df.get_column(k)
        if s.dtype == pl.String:
            parts[f"v{i}"] = s.fill_null("")
            continue
        if s.dtype == pl.Binary:
            parts[f"v{i}"] = s.fill_null(b"")
            continue
        nulls = s.is_null()
        if k in letters:
            code = letters[k].cast(LETTERS).to_physical().cast(pl.UInt8) + 2
            tier = pl.select(pl.when(nulls.not_()).then(0).otherwise(code.fill_null(1))).to_series()
        else:
            tier = nulls.cast(pl.UInt8)
        parts[f"t{i}"] = tier
        parts[f"v{i}"] = s.to_physical() if isinstance(s.dtype, (pl.Enum, pl.Categorical)) else s
    order = pl.DataFrame(parts).select(pl.arg_sort_by([pl.col(c) for c in parts], maintain_order=True)).to_series()
    if order.equals(pl.int_range(0, df.height, dtype=order.dtype, eager=True), check_names=False):
        return keys
    warn(f"meta.sort ({', '.join(keys)}) does not describe the order of the frame's rows, so it is not saved; "
         "sort with the guide's recipe (nulls last, then the letters) to keep it")
    return []
