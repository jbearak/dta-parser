"""`.dta` files into polars and back, and fixed-width text through its
SAS setup file, with the same `(df, meta)` as Parquet."""

from __future__ import annotations

import os
import tempfile
import warnings

from . import _frame as f
from ._meta import GUIDE
from ._native import native
from dta_parser._names import reserved_warning


def read_dta(path, columns=None, skip=0, n_max=None, factors=False, letters="meta", letter_suffix="_letter",
             encoding=None, timestamps="error"):
    """Read a Stata .dta file (releases 104 to 119) into a polars DataFrame
    and its Meta, without pandas.

    Returns `df, meta`. byte, int, long, float and double become Int8,
    Int16, Int32, Float32 and Float64, with `.` and `.a` to `.z` as nulls;
    strN and text strLs String, binary strLs Binary (a strL column mixing
    the two is Binary, its text as UTF-8 bytes). A `%td` column is Date
    and a `%tc` column Datetime("ms"); `%tC` and the other `%t` formats
    stay numbers, with their format in meta.

    A column that save_dta (or TypeScript's saveDta) wrote from a
    categorical, marked by its dtaparser_categorical characteristic, is
    an Enum of its value labels in code order, whatever `factors` says,
    with meta.columns[name].ordered from the mark; its .a to .z go where
    `letters` puts them. The file must still hold what was written: the
    same value label set, a label on every value read, codes that are
    whole numbers within long's range with texts of their own, no label
    on `.`, no date format, and not also a dtaparser_factor mark.
    Otherwise the column is read as if unmarked, with one UserWarning
    per read naming such columns. dtaparser_factor (R's factors) is not
    read as a mark.

    columns, skip, n_max, factors, letters, letter_suffix: as in
        read_parquet.
    encoding: for text in files before release 118: "windows-1252" (the
        default), "latin1" or "utf-8".
    timestamps: "error" (the default) or "truncate": a `%td` value with a
        fraction of a day, or a `%tc` value with a fraction of a
        millisecond, is an error naming the column and row, or truncated.
        A value outside polars' range is an error either way.

    Guide: {guide}#dta-files-into-polars
    """
    columns = f.check_columns(columns)
    f.check_window(skip, n_max)
    letters = f.check_letters(letters, letter_suffix)
    f.check_choice("timestamps", timestamps, ("error", "truncate"))
    if not isinstance(factors, bool):
        raise TypeError(f"factors must be True or False, not {factors!r}")
    frame, found, m = native.dta_read_arrow(f.path_of(path), columns, skip, n_max, encoding, timestamps)
    return f.finish(frame, found, m, factors=factors, letters=letters, letter_suffix=letter_suffix, markers=True)


def save_dta(df, path, meta=None, *, missing_letters=True, timestamps="error"):
    """Write a polars DataFrame as a Stata .dta file (release 118), with
    what `meta` says, without pandas.

    Each column gets the smallest storage type that holds its values, as
    dta_parser's write_dta chooses: integers byte, int or long (double
    past long, an error past ±2^53), Float32 float, Float64 double,
    Boolean byte, String strN or strL, Binary strL. Date is `%td`;
    Datetime is `%tc`, which holds milliseconds: a value with a fraction
    of one is an error naming the column and row unless
    timestamps="truncate", and a time zone is an error. An Enum or
    Categorical is written as Stata's `encode` makes one: codes 1 to k,
    stored as long, labelled with its levels in order, its letters kept,
    in a value label set named after the column (replacing meta's set of
    that name), or name_2, name_3, ... when another column's labels use
    that name. The set also keeps the labels on .a to .z of the set
    meta.columns[name].value_labels names. A characteristic,
    dtaparser_categorical ("ordered <set>" or "unordered <set>", from
    meta.columns[name].ordered), marks it, so that read_dta gives the
    Enum back. A dtaparser_factor or dtaparser_categorical in
    meta.characteristics is not written, for any column.
    Time, Duration, Decimal and nested dtypes are errors naming the
    column, as is a name Stata cannot hold.

    Letters come from companion columns and meta.missing, as in
    save_parquet; missing_letters=False writes them as `.`, and a
    categorical's set without letter labels.

    Guide: {guide}#dta-files-into-polars
    """
    f.check_choice("timestamps", timestamps, ("error", "truncate"))
    if not isinstance(missing_letters, bool):
        raise TypeError(f"missing_letters must be True or False, not {missing_letters!r}")
    out, profile = f.prepare(df, meta, missing_letters, "save_dta")
    # The columns written: companion letter columns are not.
    reserved_warning(out.columns, "save_dta")
    native.dta_write_arrow(out, os.fsdecode(os.fspath(path)), profile, missing_letters, timestamps)


class FixedWidthWarning(UserWarning):
    """Warns that read_fixed_width skipped part of a setup file. Its
    `messages` attribute lists every statement skipped.

    Guide: {guide}#fixed-width-files-with-a-sas-setup-file
    """

    messages: list[str] = []


_RECODES = ("setup", "tagged", "none")


def read_fixed_width(path, setup, recodes="setup", columns=None, skip=0, n_max=None, commented_formats=True,
                     letters="meta", letter_suffix="_letter"):
    """Read a fixed-width text file through its SAS setup file into a
    polars DataFrame and its Meta.

    For fixed-width ASCII data such as the National Survey of Family
    Growth files of 1973 to 2017-2019, which CDC publishes as .dat files
    with a SAS setup file (.sas) each. The setup gives each variable's
    columns (INPUT), label (LABEL), value labels (PROC FORMAT and FORMAT),
    record-type selection (IF rec_type < 5 THEN DELETE; ELSE INPUT ...)
    and missing-value recodes (IF (X = 98 OR X = 99) THEN X = .;).

    setup: the path to the setup file, or a list of paths read in order
        as one setup, such as CDC's 2002 files ["2002FemPregInput.sas",
        "2002FemPregVarLabel.sas", "2002FemPregValueLabel.sas"]. A
        statement may not run from one file into the next; errors and
        warnings name a file by its place in the list ("file 2 line 8").
    recodes: "setup" applies the recodes as written: a code recoded to
        `.` is null, one recoded to `.A` is the letter `.a`. "tagged" keeps
        why each value is missing: per variable, the codes recoded to `.`
        become `.a`, `.b`, ... in the order the setup names them, and
        their value labels move to those letters. "none" ignores them.
    columns, skip, n_max: as in read_dta; skip and n_max apply after the
        whole file is read.
    commented_formats: read a PROC FORMAT step or FORMAT statement that
        the setup puts alone in a block comment (/* ... */) as code, as
        CDC's setups from 2006-2010 on do. True by default; False reads
        every comment as a comment, and those files then have no value
        labels.
    letters, letter_suffix: where `.a` to `.z` go, as in read_parquet.

    Numeric columns take the smallest storage type that holds their
    values. Statements the reader does not run give one
    FixedWidthWarning, whose `messages` lists them all.

    Guide: {guide}#fixed-width-files-with-a-sas-setup-file
    """
    f.check_choice("recodes", recodes, _RECODES)
    if not isinstance(commented_formats, bool):
        raise TypeError(f"commented_formats must be True or False, not {commented_formats!r}")
    data = f.path_of(path)
    if isinstance(setup, (str, bytes, os.PathLike)):
        setup = [setup]
    setup = [f.path_of(s) for s in setup]
    if not setup:
        raise ValueError("setup must be one or more paths")
    with tempfile.TemporaryDirectory(prefix="datakit") as tmp:
        out = os.path.join(tmp, "data.dta")
        messages = native.fixed_width(data, setup, out, recodes, commented_formats)
        result = read_dta(out, columns=columns, skip=skip, n_max=n_max, letters=letters, letter_suffix=letter_suffix)
    if messages:
        shown = [m if len(m) <= 100 else m[:97] + "..." for m in messages[:8]]
        if len(messages) > 8:
            shown.append(f"{len(messages) - 8} more; see the warning's messages")
        w = FixedWidthWarning("The setup file was read with warnings:\n" + "\n".join("* " + m for m in shown))
        w.messages = list(messages)
        warnings.warn(w, stacklevel=2)
    return result


for _fn in (read_dta, save_dta, read_fixed_width, FixedWidthWarning):
    _fn.__doc__ = _fn.__doc__.replace("{guide}", GUIDE)
