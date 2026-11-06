"""`letters_to_columns`: `.a` to `.z` from `meta.missing` into companion
columns, which follow their rows through polars operations."""

from __future__ import annotations

import polars as pl

from . import _frame as f
from ._meta import GUIDE


def _eligible(df, meta, name):
    t = df.schema[name]
    if isinstance(t, pl.Enum):
        # An Enum that factors=True made from a labelled column.
        return name in meta.columns and meta.columns[name].value_labels is not None
    return isinstance(t, pl.Datetime) or t in (pl.Int8, pl.Int16, pl.Int32, pl.Float32, pl.Float64, pl.Date)


def letters_to_columns(df, meta, columns=None, suffix="_letter"):
    """Move `.a` to `.z` from `meta.missing` into companion columns.

    Returns a new frame with a companion `x_letter` (dtype LETTERS) after
    each column, holding its letters and null elsewhere, and CHANGES
    `meta` IN PLACE: each column's letters leave `meta.missing`, and
    `meta.letter_columns["x"]` names its companion. Do this after the read
    and before rows change (filter, sort, join): a companion follows its
    rows, `meta.missing` does not.

    columns: None for every column that can hold a letter (byte, int,
        long, float, double, date or timestamp, or an Enum factors=True
        made), or a list of names.
    suffix: the companion's suffix.

    A column whose rows have changed since the read (by the same check
    save_parquet makes) is an error, so stale letters never become a
    companion. A companion name already in df is an error; a column
    already paired is left as it is.

    Guide: {guide}#labels-and-a-to-z-through-polars-operations
    """
    f.check_frame(df, "letters_to_columns")
    if not isinstance(suffix, str) or not suffix:
        raise ValueError(f"suffix must be non-empty text, not {suffix!r}")
    if columns is None:
        names = [c for c in df.columns if c not in meta.letter_columns.values() and _eligible(df, meta, c)]
    else:
        names = [columns] if isinstance(columns, str) else list(columns)
        for n in names:
            if n not in df.columns:
                raise KeyError(f'column "{n}" is not in the frame')
            if not _eligible(df, meta, n):
                raise ValueError(f'column "{n}" is {df.schema[n]}, which cannot hold .a to .z')
    names = [n for n in names if n not in meta.letter_columns]
    for n in names:
        if n in meta.missing:
            f.digest_check(df, meta, n, meta.missing[n])
    found = dict(meta.missing)
    out = f.add_companions(df, meta, names, suffix, found, what="suffix")
    for n in names:
        meta.missing.pop(n, None)
        meta._digests.pop(n, None)
    return out


letters_to_columns.__doc__ = letters_to_columns.__doc__.replace("{guide}", GUIDE)
