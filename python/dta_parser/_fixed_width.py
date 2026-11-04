import os
import tempfile
import warnings

from . import _native
from ._read import _open_path, read_dta

_RECODES = ("setup", "tagged", "none")


class FixedWidthWarning(UserWarning):
    """Warns that read_fixed_width skipped part of a setup file or data."""


def read_fixed_width(path, setup, recodes="setup", columns=None, skip=0, n_max=None, commented_formats=True):
    """Read a fixed-width text file through its SAS setup file into a DataFrame.

    For fixed-width ASCII data such as the National Survey of Family
    Growth files of 1973 to 2017-2019, which CDC publishes as .dat files
    with a SAS setup file (.sas) each. The setup gives each variable's
    columns (INPUT), label (LABEL), value labels (PROC FORMAT and FORMAT),
    record-type selection (IF rec_type < 5 THEN DELETE; ELSE INPUT ...)
    and missing-value recodes (IF (X = 98 OR X = 99) THEN X = .;).

    setup: the path to the setup file, or a list of paths read in order
        as one setup, such as CDC's 2002 files ["2002FemPregInput.sas",
        "2002FemPregVarLabel.sas", "2002FemPregValueLabel.sas"]. A
        statement may not run from one file into the next. With several,
        errors and warnings name a file by its place in the list
        ("file 2 line 8").
    recodes: what to do with the missing-value recodes. "setup" applies
        them as written: a code recoded to `.` is NaN, one recoded to `.A`
        is missing.a. "tagged" keeps why each value is missing: per
        variable, the codes recoded to `.` become missing.a, missing.b, ...
        in the order the setup names them, and their value labels move to
        those letters. "none" ignores them; the codes stay numbers.
    columns, skip, n_max: as in read_dta; skip and n_max apply after the
        whole file is read.
    commented_formats: whether to read a PROC FORMAT step or a FORMAT
        statement that the setup has put in a block comment (/* ... */)
        as code. CDC's setups from 2006-2010 on comment both out so that
        SAS users without CDC's format catalog can run the file as
        published; the value labels are still there, so this is True by
        default. Only a comment that holds nothing but such a step or
        statement is read; one that mentions PROC FORMAT in prose stays a
        comment. False reads every comment as a comment, so those files
        have no value labels.

    Columns are as read_dta returns them; numeric columns take the
    smallest storage type that holds their values. Statements the reader
    does not run (other data-step code, ranges in VALUE) give one
    FixedWidthWarning; df.attrs["warnings"] lists them all. A LENGTH statement for numbers, which sets only how SAS stores them, is skipped without one. A variable
    label with stray quotes inside it, such as
    X = "WHETHER " SAME AS LAST MONTH" WAS ANSWERED" in CDC's 2011-2013 to
    2015-2017 setups, is read from its first quote to its last, without a warning.
    """
    if recodes not in _RECODES:
        raise ValueError(f'recodes must be "setup", "tagged" or "none", not {recodes!r}')
    if not isinstance(commented_formats, bool):
        raise TypeError(f"commented_formats must be True or False, not {commented_formats!r}")
    path = _open_path(path)
    if isinstance(setup, (str, bytes, os.PathLike)):
        setup = [setup]
    setup = [_open_path(s) for s in setup]
    if not setup:
        raise ValueError("setup must be one or more paths")
    with tempfile.TemporaryDirectory(prefix="dta_parser") as tmp:
        out = os.path.join(tmp, "data.dta")
        messages = _native.fixed_width(path, setup, out, recodes, commented_formats)
        df = read_dta(out, columns=columns, skip=skip, n_max=n_max, dates=False)
    if messages:
        df.attrs["warnings"] = list(messages)
        shown = [m if len(m) <= 100 else m[:97] + "..." for m in messages[:8]]
        if len(messages) > 8:
            shown.append(f'{len(messages) - 8} more; see df.attrs["warnings"]')
        warnings.warn("The setup file was read with warnings:\n" + "\n".join("* " + m for m in shown),
                      FixedWidthWarning, stacklevel=2)
    return df
