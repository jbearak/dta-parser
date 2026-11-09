"""Parquet files into pandas and back, keeping labels and `.a` to `.z`."""

from __future__ import annotations

import os

import pandas as pd

from . import _frame as f
from ._meta import GUIDE, ParquetInfo
from ._native import native

_COMPRESSION = ("snappy", "zstd", "gzip", "lz4_raw", "none")
_UNITS = {"s": "s", "m": "ms", "u": "us", "n": "ns"}


def read_parquet(source, columns=None, skip=0, n_max=None, factors=False, letters=True,
                 timestamps="error", nested="error"):
    """Read a Parquet file into a pandas DataFrame and its Meta.

    Returns a tuple, `df, meta = read_parquet(path)`. In `df`, each
    numeric column with a missing value in the rows read (a null, a NaN,
    `.`, or `.a` to `.z`) is a `DtaArray` (dtype `dta[byte]` ...
    `dta[double]`, after its storage type), which keeps `.a` to `.z` and
    compares as missing: `df.x != 1` is <NA> on a missing row, so a
    filter drops it, and `groupby` keeps `.`, `.a` and `.b` apart. A
    column without one keeps its numpy type. `meta` holds the data
    label, notes, each column's variable label, display format and value
    label set, and the sets. A file with a "dta" profile (written by
    save_parquet, R's datakit or Julia's Datakit) gives back what was
    saved; any other Parquet file reads with an empty Meta.

    Other types: INT64, unsigned and BOOLEAN columns with nulls are
    pandas' nullable `Int64`, `UInt8` ... `UInt64` and `boolean`; DATE is
    datetime64[s] (with the format `%td` in meta); TIMESTAMP and INT96
    datetime64 in the file's unit (INT96: ns), with its zone when
    adjusted to UTC; TIME timedelta64[ns]; text pandas' default text
    dtype; BYTE_ARRAY object of bytes; a categorical `category`;
    DECIMAL float64 up to 15 digits, `decimal.Decimal` objects above.

    source: a path, the file as bytes, or a binary file object with read
        and seek.
    columns: names or 0-based positions of the file's data columns, in
        the order wanted; None reads every column. An unknown name is a
        KeyError listing the file's columns; a position out of range an
        IndexError.
    skip, n_max: skip that many rows, then read at most n_max (all when
        None). Only the pages holding those rows are read.
    factors: make each column with value labels a category of its
        labels, as R's datakit does with factors = TRUE. The codes are then
        gone from the frame, and codes sharing a label become one level;
        saving does not bring them back. A category cannot hold `.a` to
        `.z`: in a column made one they are NaN, with a warning, as in R's
        datakit. A categorical stored with letters stays its level
        numbers, as in R.
    letters: True (the default) keeps `.a` to `.z` in the frame, in the
        column's `DtaArray` (`na_tag` reads them, `tagged_na` makes one).
        A date, timestamp or categorical cannot hold one: holding any in
        the rows read, a date or timestamp becomes Stata's number (days,
        or milliseconds, since 1960) with a `%td` or `%tc` format, and a
        categorical its level numbers from 1, labelled by its value label
        set, both `dta[double]`. So those columns change type with the
        rows read. False reads `.a` to `.z` as `.`.
    timestamps: "error" (the default) or "truncate": what to do with a
        date held as a number of days with a fraction, or a timestamp held
        as seconds that no whole number of microseconds gives back
        exactly. Values out of range are errors either way.
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
    frame, m = native.parquet_read_columns(src, columns, skip, n_max, nested == "skip", timestamps)
    return f.finish(frame, m, factors=factors, letters=letters)


_NUMPY = {"c": "int8", "s": "int16", "i": "int32", "f": "float32", "g": "float64",
          "l": "int64", "C": "uint8", "S": "uint16", "I": "uint32", "L": "uint64", "b": "bool"}
_STORAGE = {"c": "byte", "s": "int", "i": "long", "f": "float", "g": "double"}
_NULLABLE = {"l": "Int64", "C": "UInt8", "S": "UInt16", "I": "UInt32", "L": "UInt64", "b": "boolean"}


def _dtype(fmt, flag, levels, nulls):
    """The pandas dtype, as text, of a column read with format `fmt` when
    its rows hold no `.a` to `.z`; `nulls` when the footer allows a null."""
    if fmt is None:
        return None
    if levels is not None or flag == "categorical":
        return "category"
    if flag is not None and flag.startswith("decimal("):
        p = int(flag[len("decimal("):-1].split(",")[0])
        if p > 15:
            return "object"
        return "dta[double]" if nulls else "float64"
    if fmt.startswith("ts"):
        zone = fmt[4:]
        unit = _UNITS[fmt[2]]
        return f"datetime64[{unit}, {zone}]" if zone else f"datetime64[{unit}]"
    if fmt == "tdD":
        return "datetime64[s]"
    if fmt == "ttn":
        return "timedelta64[ns]"
    if fmt == "vu":
        return str(f.TEXT)
    if fmt == "vz":
        return "object"
    if fmt in _STORAGE:
        # A DOUBLE is read with a bitmap: the footer cannot rule out a NaN
        # or a letter, so its dtype is the one without them.
        return f"dta[{_STORAGE[fmt]}]" if nulls else _NUMPY[fmt]
    return _NULLABLE[fmt] if nulls else _NUMPY[fmt]


def read_parquet_info(source):
    """Describe a Parquet file without reading its data: only the footer is
    read. Returns a ParquetInfo: rows, row_groups, compression,
    created_by, key_value, meta (the Meta a whole-file read gives) and
    columns (each column's pandas dtype as read_parquet
    gives it, Parquet's types, label, value label set and storage).

    source: a path, the file as bytes, or a binary file object with read
        and seek.

    Guide: {guide}#a-parquet-files-schema-and-metadata
    """
    info = native.parquet_info_columns(f.source_of(source))
    for w in info["meta"]["warnings"]:
        f.warn(w)
    cols = info["columns"]
    text = {
        "name": [c[0] for c in cols],
        "role": [c[1] for c in cols],
        "dtype": [None if c[2] is None else _dtype(c[2], c[3], c[4], c[10]) for c in cols],
        "physical_type": [c[5] for c in cols],
        "logical_type": [c[6] for c in cols],
        "label": [c[7] for c in cols],
        "value_labels": [c[8] for c in cols],
        "storage": [c[9] for c in cols],
    }
    columns = pd.DataFrame({k: pd.Series(v, dtype=f.TEXT if f.TEXT != object else object) for k, v in text.items()})
    groups = info["row_groups"]
    meta = f.meta_of(info["meta"])
    for c in cols:
        if c[2] == "tdD":
            f.date_format(meta, c[0])
    return ParquetInfo(
        rows=info["rows"],
        row_groups=pd.DataFrame(
            {"rows": pd.Series([g[0] for g in groups], dtype="int64"),
             "compressed_bytes": pd.Series([g[1] for g in groups], dtype="int64"),
             "uncompressed_bytes": pd.Series([g[2] for g in groups], dtype="int64")}),
        compression=list(info["compression"]),
        created_by=info["created_by"],
        key_value=dict(info["key_value"]),
        meta=meta,
        columns=columns,
    )


def save_parquet(df, path=None, meta=None, *, compression="snappy", compression_level=None, row_group_size=None,
                 missing_letters=True, timestamps="error"):
    """Write a pandas DataFrame as Parquet, with what `meta` says.

    The file keeps the data label, notes, characteristics, sort order,
    time stamp, variable labels, display formats and value labels in its
    "dta" profile, a JSON entry of the footer's key-value metadata, which
    R's and Julia's datakits read too. `.a` to `.z` in a `DtaArray`
    column, or tagged NaNs in a plain float column, are written as they
    are: a DOUBLE whose letters R reads as tagged NAs and pyarrow, polars
    and DuckDB as NaN, with the column's storage type in the profile.
    Other tools read the file as plain Parquet. Returns None, or the
    file as bytes when path is None. The file is written beside `path`
    and renamed, so a failed write leaves an existing file as it was. The
    index is not written: `df.reset_index()` first to keep it.

    df: a pandas DataFrame.
    meta: a Meta, or None. Entries for columns not in df are dropped.
    compression: "snappy" (the default), "zstd", "gzip", "lz4_raw" or
        "none"; compression_level sets zstd's (1 to 22) or gzip's (0 to 9).
    row_group_size: rows per row group (by default up to 262,144 rows and
        about 1 GiB of values).
    missing_letters: False writes `.a` to `.z` as `.`, a null.
    timestamps: "error" or "truncate"; kept for symmetry with the reads.

    Columns: numpy integers, floats and bool as the Parquet type of the
    same width; nullable `Int*`, `UInt*`, `Float*` and `boolean` the
    same, `<NA>` written as `.`; a NaN in a float column is `.` (a tagged
    NaN its letter); a `DtaArray` in its storage type, or the next type
    that holds every value when one no longer fits; `category` as a
    categorical (its categories text), ordered kept; text (pandas' `str`,
    or object holding text) STRING; object of bytes BYTE_ARRAY;
    datetime64 TIMESTAMP in its unit (adjusted to UTC with its zone when
    tz-aware), or DATE when meta gives the column `%td` and every value
    is at midnight; timedelta64 TIME(NANOS) when every value is within a
    day. Anything else (Decimal objects, mixed object, complex, interval,
    period) is an error naming the column.

    Guide: {guide}#write-a-parquet-file
    """
    f.check_choice("compression", compression, _COMPRESSION)
    f.check_choice("timestamps", timestamps, ("error", "truncate"))
    if row_group_size is not None and (isinstance(row_group_size, bool) or not isinstance(row_group_size, int)
                                       or row_group_size < 1):
        raise ValueError(f"row_group_size must be a whole number of rows >= 1, not {row_group_size!r}")
    if not isinstance(missing_letters, bool):
        raise TypeError(f"missing_letters must be True or False, not {missing_letters!r}")
    specs, profile = f.prepare(df, meta, missing_letters, "save_parquet")
    target = None if path is None else os.fsdecode(os.fspath(path))
    return native.parquet_write_columns(specs, len(df), target, profile, compression, compression_level,
                                        row_group_size, missing_letters, timestamps)


for _fn in (read_parquet, read_parquet_info, save_parquet):
    _fn.__doc__ = _fn.__doc__.replace("{guide}", GUIDE)
