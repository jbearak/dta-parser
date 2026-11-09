"""What every read and save shares: the frame and its `Meta` from the
native reads, `.a` to `.z` in `meta.missing` or companion columns,
`factors`, and the checks a save makes before handing the frame to the
native writers."""

from __future__ import annotations

import os
import re
import warnings

import polars as pl

from ._meta import LETTERS, Column, Meta
from ._native import native

# Dtypes a letter can be written to (plan 0019, "eligible"): byte, int,
# long, float and double; dates and timestamps.
_ELIGIBLE = (pl.Int8, pl.Int16, pl.Int32, pl.Float32, pl.Float64, pl.Date, pl.Datetime)


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


def check_letters(letters, letter_suffix):
    if not isinstance(letter_suffix, str) or not letter_suffix:
        raise ValueError(f"letter_suffix must be non-empty text, not {letter_suffix!r}")
    if letters is None or letters in ("meta", "columns"):
        return letters
    if isinstance(letters, str):
        raise ValueError(f'letters is "meta", "columns", None, or a list of column names, not {letters!r}')
    out = list(letters)
    if not all(isinstance(n, str) for n in out):
        raise TypeError("letters, as a list, holds column names")
    return out


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


def finish(native_frame, native_letters, m, *, factors, letters, letter_suffix, markers=False):
    """`(df, meta)` from a native read, letters placed as `letters` says.
    With `markers` (a .dta read), the columns marked `dtaparser_categorical`
    are Enums again first (`restore_categoricals`)."""
    for w in m["warnings"]:
        warn(w)
    df = frame_of(native_frame, m)
    meta = meta_of(m)
    if markers:
        df, stale = restore_categoricals(df, meta)
        if stale:
            shown = ", ".join(f'"{n}"' for n in stale)
            warn(f"{'column' if len(stale) == 1 else 'columns'} {shown} {'was' if len(stale) == 1 else 'were'} "
                 "written as categoricals, but the file has changed since: their value label set changed, a value "
                 "has no label, two codes share a text, a code is not a whole number, `.` is labelled, a date format "
                 "was given, or a column has both markers; read as unmarked columns")
    found = {}
    if native_letters is not None and letters is not None:
        ldf = pl.DataFrame(native_letters)
        found = {name: ldf.get_column(name) for name in ldf.columns}
    eligible = [c[0] for c in m["columns"] if c[7]]
    if factors:
        df = to_factors(df, meta)
    if letters in (None, "meta"):
        meta.missing = found
    else:
        wanted = eligible if letters == "columns" else letters
        if letters != "columns":
            ok = set(eligible)
            for n in wanted:
                if n not in df.columns:
                    raise KeyError(f'letters names "{n}", which is not a column read')
                if n not in ok:
                    raise ValueError(f'letters names "{n}", whose type cannot hold .a to .z '
                                     "(only byte, int, long, float, double, date and timestamp columns, "
                                     "and categoricals stored with letters, can)")
        df = add_companions(df, meta, wanted, letter_suffix, found)
        meta.missing = found
    meta._digests = {name: native.arrow_digest(df.get_column(name)) for name in meta.missing}
    return df, meta


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


def restore_categoricals(df, meta):
    """`df` with each column marked `dtaparser_categorical` that passes the
    checks of plan 0023 an Enum of its set's texts in code order, unused
    ones included; its `meta.columns[name].ordered` from the mark, its mark
    gone from `meta.characteristics`. Its `.a` to `.z` stay with the read's
    letters. The columns that fail (`marked_levels`, a column that is not
    numeric, as a `%td` one is once read, a value without a label, or both
    marks) are left as read, unmarked; their names are returned with
    `df`. `dtaparser_factor` alone is left as it is (an R factor; plan
    0020)."""
    changes = []
    stale = []
    for name in df.columns:
        chars = meta.characteristics.get(name) or {}
        if CATEGORICAL_MARK not in chars:
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


def add_companions(df, meta, names, suffix, found, *, what="letter_suffix"):
    """`df` with a companion after each column of `names`, from `found`
    (taken out of it) or all null; the pairs recorded in meta."""
    names = [n for n in dict.fromkeys(names) if n not in meta.letter_columns]
    if not names:
        return df
    taken = set(df.columns)
    pairs = {}
    for n in names:
        comp = n + suffix
        if comp in taken:
            raise ValueError(f'the companion of column "{n}" would be "{comp}", which is already a column; '
                             f"pass another {what}")
        taken.add(comp)
        pairs[n] = comp
    new = []
    for n, comp in pairs.items():
        s = found.pop(n, None)
        new.append(s.alias(comp) if s is not None else pl.lit(None, LETTERS).alias(comp))
    order = []
    for c in df.columns:
        order.append(c)
        if c in pairs:
            order.append(pairs[c])
    meta.letter_columns.update(pairs)
    return df.with_columns(new).select(order)


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


def digest_check(df, meta, name, series):
    """The checks a save makes on `meta.missing[name]`: the frame's height,
    and the column's digest as read."""
    if not isinstance(series, pl.Series):
        raise TypeError(f'meta.missing["{name}"] is not a polars Series')
    advice = (f'carry the letters with letters_to_columns before changing rows, or drop them with '
              f'meta.missing.pop("{name}")')
    if series.len() != df.height:
        raise ValueError(f'the letters of column "{name}" have {series.len()} rows, but the frame has {df.height}; '
                         + advice)
    want = meta._digests.get(name)
    if want is not None and native.arrow_digest(df.get_column(name)) != want:
        raise ValueError(f'column "{name}" has changed since it was read, so meta.missing["{name}"] may no longer '
                         "line up with its rows; " + advice)


def prepare(df, meta, missing_letters, who):
    """The frame to write (companions taken out), and what the native
    writer takes of meta: label, notes, characteristics, sort (checked),
    timestamp, columns, value_labels, and missing, the letters of each
    column from its companion or meta.missing."""
    check_frame(df, who)
    if meta is not None and not isinstance(meta, Meta):
        raise TypeError(f"meta is a datakit.Meta or None, not {type(meta).__name__}")
    names = set(df.columns)
    pairs = dict(meta.letter_columns) if meta is not None else {}
    companions = {}
    for x, comp in pairs.items():
        if comp in companions:
            raise ValueError(f'column "{comp}" is the companion of both "{companions[comp]}" and "{x}" '
                             "in meta.letter_columns")
        if comp in pairs:
            raise ValueError(f'column "{comp}" is both a companion and a column with a companion in meta.letter_columns')
        companions[comp] = x
    letters = {}
    drop = []
    for x, comp in pairs.items():
        if x in names:
            if comp not in names:
                if missing_letters:
                    raise ValueError(
                        f'column "{x}" is in the frame but its letters\' column "{comp}" is not; keep "{comp}", '
                        f'or remove the pair with del meta.letter_columns["{x}"], or pass missing_letters=False')
                continue
            drop.append(comp)
            if not missing_letters:
                continue
            s = df.get_column(comp)
            if s.dtype != LETTERS and s.dtype != pl.String:
                raise TypeError(f'column "{comp}", the letters of "{x}", is {s.dtype}, not datakit.LETTERS or String')
            if x in meta.missing:
                raise ValueError(f'column "{x}" has letters both in column "{comp}" and in meta.missing; '
                                 f'drop one (meta.missing.pop("{x}"))')
            letters[x] = s
        elif comp in names:
            raise ValueError(
                f'column "{comp}" holds the letters of column "{x}", which is not in the frame; drop "{comp}", '
                f'or remove the pair with del meta.letter_columns["{x}"]')
    if meta is not None and missing_letters:
        for x, s in meta.missing.items():
            if x in names:
                digest_check(df, meta, x, s)
                letters[x] = s
    stray = [c for c, t in df.schema.items() if t == LETTERS and c not in companions]
    if stray:
        shown = ", ".join(f'"{c}"' for c in stray)
        warn(f"{shown} {'is a column' if len(stray) == 1 else 'are columns'} of datakit.LETTERS that no pair in "
             "meta.letter_columns names, written as an ordinary categorical; its letters belong to no column")
    out = df.drop(drop) if drop else df
    if meta is None:
        return out, None
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
