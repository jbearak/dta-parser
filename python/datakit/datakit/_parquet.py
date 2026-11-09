"""Parquet files into polars and back, keeping labels and `.a` to `.z`."""

from __future__ import annotations

import os

import polars as pl

from . import _frame as f
from ._meta import GUIDE, ParquetInfo
from ._native import native

_COMPRESSION = ("snappy", "zstd", "gzip", "lz4_raw", "none")
_UNITS = {"m": "ms", "u": "us", "n": "ns", "s": "ms"}


def read_parquet(source, columns=None, skip=0, n_max=None, factors=False, letters=True,
                 timestamps="error", nested="error"):
    """Read a Parquet file into a polars DataFrame and its Meta.

    Returns a tuple, `df, meta = read_parquet(path)`. In `df`, `.` is a
    polars null and `.a` to `.z` are tagged NaNs (see `letters`); `meta`
    holds the data label, notes, each column's variable label, display
    format and value label set, and the sets. A file with a "dta" profile (written by
    save_parquet, R's datakit or Julia's Datakit) gives back what was
    saved; any other Parquet file reads with an empty Meta.

    source: a path, the file as bytes, or a binary file object with read
        and seek.
    columns: names or 0-based positions of the file's data columns, in
        the order wanted; None reads every column. An unknown name is a
        KeyError listing the file's columns; a position out of range an
        IndexError.
    skip, n_max: skip that many rows, then read at most n_max (all when
        None). Only the pages holding those rows are read.
    factors: make each column with value labels an Enum of its labels, as
        R's datakit does with factors = TRUE. The codes are then gone from
        the frame, and codes sharing a label become one level; saving does
        not bring them back. An Enum cannot hold `.a` to `.z`: in a
        column made one they are nulls, with a warning, as in R's
        datakit. A categorical stored with letters stays its level
        numbers, as in R.
    letters: True (the default) keeps `.a` to `.z` in the frame: each
        column holding any in the rows read is Float64, each letter a NaN
        tagged with it (`na_tag` reads them, `tagged_na` makes one). An
        integer or Float32 column is cast; a date or timestamp becomes
        Stata's number (days, or milliseconds, since 1960) with a `%td` or
        `%tc` format; a categorical its level numbers from 1, labelled by
        its value label set. polars counts NaN as a value: use
        `fill_nan(None)` before `is_null`, `mean` or `count`. False reads
        `.a` to `.z` as nulls, like `.`, and the column keeps its dtype.
    timestamps: "error" (the default) or "truncate": what to do with a
        date held as a number of days with a fraction, or a timestamp held
        as seconds that no whole number of microseconds gives back
        exactly. Values out of polars' range are errors either way.
    nested: "error" (the default) or "skip" for files with list, map or
        struct columns, which are not read.

    Guide: {guide}#read-a-parquet-file
    """
    columns = f.check_columns(columns)
    f.check_window(skip, n_max)
    f.check_letters(letters)
    f.check_choice("timestamps", timestamps, ("error", "truncate"))
    f.check_choice("nested", nested, ("error", "skip"))
    if not isinstance(factors, bool):
        raise TypeError(f"factors must be True or False, not {factors!r}")
    src = f.source_of(source)
    frame, found, m = native.parquet_read_arrow(src, columns, skip, n_max, nested == "skip", timestamps)
    return f.finish(frame, found, m, factors=factors, letters=letters)


def _dtype(fmt, flag, levels):
    """The polars dtype of a column read with Arrow format `fmt`, as text."""
    if fmt is None:
        return None
    if levels is not None:
        return pl.Enum(levels)
    if flag == "categorical":
        return pl.Categorical()
    if flag is not None and flag.startswith("decimal("):
        p, s = map(int, flag[len("decimal("):-1].split(","))
        return pl.Decimal(p, s) if p <= 38 else pl.String()
    if fmt.startswith("ts"):
        zone = fmt[4:] or None
        return pl.Datetime(_UNITS[fmt[2]], zone)
    return {
        "c": pl.Int8, "s": pl.Int16, "i": pl.Int32, "l": pl.Int64,
        "C": pl.UInt8, "S": pl.UInt16, "I": pl.UInt32, "L": pl.UInt64,
        "b": pl.Boolean, "f": pl.Float32, "g": pl.Float64, "tdD": pl.Date, "ttn": pl.Time,
        "vu": pl.String, "vz": pl.Binary,
    }[fmt]()


def read_parquet_info(source):
    """Describe a Parquet file without reading its data: only the footer is
    read. Returns a ParquetInfo: rows, row_groups, compression,
    created_by, key_value, meta (the Meta a whole-file read gives) and
    columns (each column's polars dtype as read_parquet
    gives it, Parquet's types, label, value label set and storage).

    source: a path, the file as bytes, or a binary file object with read
        and seek.

    Guide: {guide}#a-parquet-files-schema-and-metadata
    """
    info = native.parquet_info_arrow(f.source_of(source))
    for w in info["meta"]["warnings"]:
        f.warn(w)
    cols = info["columns"]
    columns = pl.DataFrame(
        {
            "name": [c[0] for c in cols],
            "role": [c[1] for c in cols],
            "dtype": [None if c[2] is None else str(_dtype(c[2], c[3], c[4])) for c in cols],
            "physical_type": [c[5] for c in cols],
            "logical_type": [c[6] for c in cols],
            "label": [c[7] for c in cols],
            "value_labels": [c[8] for c in cols],
            "storage": [c[9] for c in cols],
        },
        schema={k: pl.String for k in ("name", "role", "dtype", "physical_type", "logical_type", "label",
                                         "value_labels", "storage")},
    )
    groups = info["row_groups"]
    return ParquetInfo(
        rows=info["rows"],
        row_groups=pl.DataFrame(
            {"rows": [g[0] for g in groups], "compressed_bytes": [g[1] for g in groups],
             "uncompressed_bytes": [g[2] for g in groups]},
            schema={"rows": pl.Int64, "compressed_bytes": pl.Int64, "uncompressed_bytes": pl.Int64},
        ),
        compression=list(info["compression"]),
        created_by=info["created_by"],
        key_value=dict(info["key_value"]),
        meta=f.meta_of(info["meta"]),
        columns=columns,
    )


def save_parquet(df, path=None, meta=None, *, compression="snappy", compression_level=None, row_group_size=None,
                 missing_letters=True, timestamps="error"):
    """Write a polars DataFrame as Parquet, with what `meta` says.

    The file keeps the data label, notes, characteristics, sort order,
    time stamp, variable labels, display formats and value labels in its
    "dta" profile, a JSON entry of the footer's key-value metadata, which
    R's and Julia's datakits read too. `.a` to `.z`, the tagged NaNs of a
    Float64 column, are written as they are: a DOUBLE whose letters R
    reads as tagged NAs and pyarrow, polars and DuckDB as NaN. A column
    that a read made Float64 to hold them is written with its file's
    storage type in the profile, when its values still fit it. Other
    tools read the file as plain Parquet. Returns None,
    or the file as bytes when path is None. The file is written beside
    `path` and renamed, so a failed write leaves an existing file as it
    was.

    df: a polars DataFrame (a LazyFrame is a TypeError: collect it first).
    meta: a Meta, or None. Entries for columns not in df are dropped.
    compression: "snappy" (the default), "zstd", "gzip", "lz4_raw" or
        "none"; compression_level sets zstd's (1 to 22) or gzip's (0 to 9).
    row_group_size: rows per row group (by default up to 262,144 rows and
        about 1 GiB of values).
    missing_letters: False writes `.a` to `.z` as plain nulls. A NaN that
        is not tagged is written as NaN, a value.
    timestamps: "error" or "truncate"; kept for files written with
        letters in a Datetime column by R, Julia or TypeScript.

    Every dtype polars has that Parquet and the profile can keep is
    written; Decimal, Duration, List, Array,
    Struct and Object are errors naming the column and what to cast to.

    Guide: {guide}#write-a-parquet-file
    """
    f.check_choice("compression", compression, _COMPRESSION)
    f.check_choice("timestamps", timestamps, ("error", "truncate"))
    if row_group_size is not None and (isinstance(row_group_size, bool) or not isinstance(row_group_size, int)
                                       or row_group_size < 1):
        raise ValueError(f"row_group_size must be a whole number of rows >= 1, not {row_group_size!r}")
    if not isinstance(missing_letters, bool):
        raise TypeError(f"missing_letters must be True or False, not {missing_letters!r}")
    out, profile = f.prepare(df, meta, missing_letters, "save_parquet")
    target = None if path is None else os.fsdecode(os.fspath(path))
    return native.parquet_write_arrow(out, target, profile, compression, compression_level, row_group_size,
                                      missing_letters, timestamps)


for _fn in (read_parquet, read_parquet_info, save_parquet):
    _fn.__doc__ = _fn.__doc__.replace("{guide}", GUIDE)
