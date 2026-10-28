"""Dump what pandas reads from each fixture to JSON, as expected values
for this library's tests.

Run from the repository root: python3 compat/expected.py [fixture.dta ...]
A field pandas does not expose is null.
"""

import glob
import json
import math
import os
import sys

import pandas as pd
from pandas.io.stata import StataMissingValue, StataReader

TYPES = {"b": "byte", "h": "int", "l": "long", "f": "float", "d": "double"}


def type_name(t) -> str:
    if isinstance(t, int):
        return f"str{t}"
    if t in ("strL", "Q"):
        return "strL"
    return TYPES.get(str(t), {"int8": "byte", "int16": "int", "int32": "long",
                              "float32": "float", "float64": "double"}.get(str(t), str(t)))


def cell(v):
    if isinstance(v, StataMissingValue):
        return {"missing": v.string}
    if isinstance(v, float) and math.isnan(v):
        return {"missing": "."}
    if hasattr(v, "item"):
        v = v.item()
    return v


def label_code(value):
    # pandas keys labels on missing values by their stored long.
    if isinstance(value, int) and value >= 2147483621:
        k = value - 2147483621
        return "." if k == 0 else "." + chr(ord("a") + k - 1)
    return value


def dump(path: str) -> dict:
    with StataReader(path, convert_categoricals=False, convert_dates=False,
                     convert_missing=True) as reader:
        data = reader.read()
        sets = reader.value_labels()
        var_labels = reader.variable_labels()
        release = reader._format_version
        formats = reader._fmtlist
        typlist = reader._typlist
        lbllist = reader._lbllist
        data_label = reader.data_label
        timestamp = reader.time_stamp
    variables = []
    for i, name in enumerate(data.columns):
        set_name = lbllist[i]
        table = sets.get(set_name, {})
        variables.append({
            "name": name,
            "type": type_name(typlist[i]),
            "format": formats[i],
            "label": var_labels.get(name, ""),
            "value_labels": set_name,
            "labels": [[label_code(int(k) if float(k).is_integer() else k), v]
                       for k, v in table.items()],
        })
    return {
        "reader": f"pandas {pd.__version__}",
        "release": release,
        "nobs": len(data),
        "data_label": data_label,
        "timestamp": timestamp,
        "variables": variables,
        "values": {name: [cell(v) for v in data[name].tolist()] for name in data.columns},
    }


paths = sys.argv[1:] or sorted(glob.glob("compat/fixtures/*.dta"))
for path in paths:
    stem = os.path.splitext(os.path.basename(path))[0]
    try:
        result = dump(path)
    except Exception as e:  # recorded, so a reader's failure is visible
        result = {"reader": f"pandas {pd.__version__}", "error": str(e)}
    with open(f"compat/expected/{stem}.pandas.json", "w") as f:
        json.dump(result, f, indent=2, ensure_ascii=False, allow_nan=False)
        f.write("\n")
