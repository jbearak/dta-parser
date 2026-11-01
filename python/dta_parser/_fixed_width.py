import os
import tempfile
import warnings

from . import _native
from ._read import _open_path, read_dta

_RECODES = ("setup", "tagged", "none")


class FixedWidthWarning(UserWarning):
    """Warns that read_fixed_width skipped part of a setup file or data."""


def read_fixed_width(path, setup, recodes="setup", columns=None, skip=0, n_max=None):
    """Read a fixed-width text file through its SAS setup file into a DataFrame.

    For fixed-width ASCII data such as the National Survey of Family
    Growth cycles of 1973 to 1995, which CDC publishes as .dat files with
    a SAS setup file (.sas) each. The setup gives each variable's columns
    (INPUT), label (LABEL), value labels (PROC FORMAT and FORMAT),
    record-type selection (IF rec_type < 5 THEN DELETE; ELSE INPUT ...)
    and missing-value recodes (IF (X = 98 OR X = 99) THEN X = .;).

    recodes: what to do with the missing-value recodes. "setup" applies
        them as written: a code recoded to `.` is NaN, one recoded to `.A`
        is missing.a. "tagged" keeps why each value is missing: per
        variable, the codes recoded to `.` become missing.a, missing.b, ...
        in the order the setup names them, and their value labels move to
        those letters. "none" ignores them; the codes stay numbers.
    columns, skip, n_max: as in read_dta; skip and n_max apply after the
        whole file is read.

    Columns are as read_dta returns them; numeric columns take the
    smallest storage type that holds their values. Statements the reader
    does not run (other data-step code, ranges in VALUE) give one
    FixedWidthWarning; df.attrs["warnings"] lists them all.
    """
    if recodes not in _RECODES:
        raise ValueError(f'recodes must be "setup", "tagged" or "none", not {recodes!r}')
    path = _open_path(path)
    setup = _open_path(setup)
    with tempfile.TemporaryDirectory(prefix="dta_parser") as tmp:
        out = os.path.join(tmp, "data.dta")
        messages = _native.fixed_width(path, setup, out, recodes)
        df = read_dta(out, columns=columns, skip=skip, n_max=n_max, dates=False)
    if messages:
        df.attrs["warnings"] = list(messages)
        shown = [m if len(m) <= 100 else m[:97] + "..." for m in messages[:8]]
        if len(messages) > 8:
            shown.append(f'{len(messages) - 8} more; see df.attrs["warnings"]')
        warnings.warn("The setup file was read with warnings:\n" + "\n".join("* " + m for m in shown),
                      FixedWidthWarning, stacklevel=2)
    return df
