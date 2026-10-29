"""Every fixture in compat/fixtures reads as pandas and pyreadstat read it.

Expected values come only from those readers, compared cell by cell
(numbers exactly, missing values by code where the reader keeps the
code), with variable names, storage types, formats, labels and value
labels. Where a reader is known to read a fixture wrongly, that field is
skipped with the reason, in KNOWN (see docs/adr/0005-oracles.md).
"""

import math

import numpy as np
import pandas as pd
import pyreadstat
import pytest
from pandas.io.stata import StataMissingValue, StataReader

from conftest import fixture_paths
from dta_parser import StataArray, read_dta

LATIN1 = "pandas decodes text before 118 as Latin-1, not Windows-1252"

# (reader, fixture name prefix, field): why that reader's value is not an
# oracle there.
KNOWN = {
    ("pandas", "haven_113", "text"): LATIN1,
    ("pandas", "haven_114", "text"): LATIN1,
    ("pandas", "haven_115", "text"): LATIN1,
    ("pandas", "haven_117", "text"): LATIN1,
    ("pyreadstat", "haven_119", "big"): "haven 2.5.5 wrote 118-style strL references into a 119 file, "
    "which pyreadstat reads with the 119 layout, finding no text",
}
if int(pd.__version__.split(".")[0]) < 3:
    for stem in ("readstat_105", "readstat_108", "readstat_111"):
        for name in ("i", "l"):
            KNOWN[("pandas", stem, name)] = "pandas 2 reads the one missing value of int and long before 113 as .z"
    for stem in ("readstat_105", "readstat_108"):
        KNOWN[("pandas", stem, "b.labels")] = "pandas 2 reads value labels of releases 105 and 108 as empty"


def known(reader, stem, field):
    return any(r == reader and stem.startswith(p) and f == field for (r, p, f) in KNOWN)


def missing_name(code):
    return "." if code == 1 else "." + chr(ord("a") + code - 2)


def our_cells(series):
    array = series.array
    if isinstance(array, StataArray):
        return [v if c == 0 else missing_name(c) for v, c in zip(array.to_numpy().tolist(), array.codes.tolist())]
    if series.dtype.kind in "iuf":
        return ["." if v != v else float(v) for v in series.to_numpy().tolist()]
    return list(series.to_numpy(dtype=object))


def ours(path):
    df = read_dta(path, dates=False)
    meta = df.attrs["dta"]
    sets = meta["value_labels"]
    variables = {}
    for name, col in meta["columns"].items():
        table = sets.get(col["value_labels"], {})
        variables[name] = {
            "type": col["storage"],
            "format": col["format"],
            "label": col["label"],
            "labels": {(k.name if not isinstance(k, (int, float)) else float(k)): v for k, v in table.items()},
        }
    return {
        "names": list(df.columns),
        "nobs": len(df),
        "data_label": meta["label"],
        "timestamp": meta["timestamp"],
        "notes": meta["notes"],
        "variables": variables,
        "values": {name: our_cells(df[name]) for name in df.columns},
    }


PANDAS_TYPES = {"b": "byte", "h": "int", "l": "long", "f": "float", "d": "double",
                "int8": "byte", "int16": "int", "int32": "long", "float32": "float", "float64": "double"}


def pandas_type(t):
    if isinstance(t, int):
        return f"str{t}"
    if t in ("strL", "Q"):
        return "strL"
    return PANDAS_TYPES.get(str(t), str(t))


def pandas_cell(v):
    if isinstance(v, StataMissingValue):
        return v.string
    if isinstance(v, float) and math.isnan(v):
        return "."
    if isinstance(v, (int, float, np.number)) and not isinstance(v, bool):
        return float(v)
    return v


def pandas_label_key(k):
    # pandas keys labels on missing values by their stored long.
    k = int(k) if float(k).is_integer() else k
    if isinstance(k, int) and k >= 2147483621:
        return missing_name(k - 2147483621 + 1)
    return float(k)


def by_pandas(path):
    with StataReader(path, convert_categoricals=False, convert_dates=False, convert_missing=True) as r:
        data = r.read()
        sets = r.value_labels()
        var_labels = r.variable_labels()
        release = r._format_version
        formats, types, lbllist = r._fmtlist, r._typlist, r._lbllist
        data_label = r.data_label
        timestamp = r.time_stamp if release >= 105 else None
    variables = {}
    for i, name in enumerate(data.columns):
        variables[name] = {
            "type": pandas_type(types[i]),
            "format": formats[i],
            "label": var_labels.get(name, ""),
            "labels": {pandas_label_key(k): v for k, v in sets.get(lbllist[i], {}).items()},
        }
    return {
        "names": list(data.columns),
        "nobs": len(data),
        "data_label": data_label,
        "timestamp": timestamp,
        "notes": None,
        "variables": variables,
        "values": {name: [pandas_cell(v) for v in data[name].tolist()] for name in data.columns},
    }


PYREADSTAT_TYPES = {"int8": "byte", "int16": "int", "int32": "long", "float": "float", "double": "double"}


def by_pyreadstat(path):
    df, meta = pyreadstat.read_dta(str(path), user_missing=True, disable_datetime_conversion=True)
    variables = {}
    values = {}
    for i, name in enumerate(df.columns):
        kind = meta.readstat_variable_types[name]
        numeric = kind in PYREADSTAT_TYPES
        table = meta.variable_value_labels.get(name, {})
        variables[name] = {
            # pyreadstat does not give a string's width.
            "type": PYREADSTAT_TYPES[kind] if numeric else None,
            "format": meta.original_variable_types[name],
            "label": meta.column_labels[i] or "",
            "labels": {("." + k if isinstance(k, str) else float(k)): v for k, v in table.items()},
        }
        if numeric:
            values[name] = ["." + v if isinstance(v, str) else "." if v != v else float(v) for v in df[name].tolist()]
        else:
            values[name] = ["" if v is None or (isinstance(v, float) and v != v) else v for v in df[name].tolist()]
    return {
        "names": list(df.columns),
        "nobs": len(df),
        "data_label": meta.file_label or "",
        "timestamp": None,
        "notes": meta.notes,
        "variables": variables,
        "values": values,
    }


READERS = {"pandas": by_pandas, "pyreadstat": by_pyreadstat}


def differences(stem, reader, a, b):
    out = []

    def check(field, x, y):
        if y is not None and x != y and not known(reader, stem, field):
            if isinstance(x, list) and isinstance(y, list) and len(x) == len(y):
                i = next(i for i, (p, q) in enumerate(zip(x, y)) if p != q)
                x, y = f"row {i}: {x[i]!r:.80}", f"{y[i]!r:.80}"
            out.append(f"{stem}: {field} differs from {reader}: ours {x}, theirs {y}")

    for field in ("names", "nobs", "data_label", "timestamp", "notes"):
        check(field, a[field], b[field])
    for name, theirs in b["variables"].items():
        mine = a["variables"].get(name, {})
        for field in ("type", "format", "label", "labels"):
            check(f"{name}.{field}", mine.get(field), theirs[field])
        check(name, a["values"].get(name), b["values"][name])
    return out


@pytest.mark.parametrize("reader", sorted(READERS))
def test_reads_what_open_source_readers_read(fixture, reader):
    try:
        theirs = READERS[reader](fixture)
    except Exception as e:  # a reader that cannot read the file is no oracle for it
        pytest.skip(f"{reader} cannot read {fixture.name}: {e}")
    found = differences(fixture.stem, reader, ours(fixture), theirs)
    assert not found, "\n".join(found)


def test_missing_codes_match_pandas_and_pyreadstat():
    # The fixtures with .a to .z: both readers expose the codes.
    seen = 0
    for path in [p for p in fixture_paths() if p.stem.startswith("haven_1")]:
        df = read_dta(path, dates=False)
        for name in df.columns:
            if isinstance(df[name].array, StataArray):
                seen += 1
                ours_codes = df[name].array.codes
                assert ours_codes.max() > 1
                if not path.stem.startswith("haven_119"):
                    p = by_pandas(path)["values"][name]
                    assert [missing_name(c) if c else None for c in ours_codes] == [
                        v if isinstance(v, str) else None for v in p
                    ]
                r = by_pyreadstat(path)["values"][name]
                assert [missing_name(c) if c else None for c in ours_codes] == [
                    v if isinstance(v, str) else None for v in r
                ]
    assert seen > 0


def test_pandas_categoricals_match_value_labels(fixture):
    # pandas' own labelled reading, where it can make categoricals.
    try:
        theirs = pd.read_stata(fixture, convert_dates=False, convert_missing=False)
    except Exception as e:
        pytest.skip(f"pandas cannot make categoricals for {fixture.name}: {e}")
    df = read_dta(fixture, dates=False)
    sets = df.attrs["dta"]["value_labels"]
    for name, col in df.attrs["dta"]["columns"].items():
        table = sets.get(col["value_labels"])
        if not table or not isinstance(theirs[name].dtype, pd.CategoricalDtype):
            continue
        for value, label in zip(our_cells(df[name]), theirs[name].tolist()):
            if isinstance(value, float) and float(value).is_integer() and int(value) in table:
                assert label == table[int(value)]
