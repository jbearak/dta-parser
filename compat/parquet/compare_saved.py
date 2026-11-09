"""Compare the .dta files save_dta_compare.sh makes: TypeScript's
saveDta (DIR/saved_typescript.dta) against Python datakit's save_dta
(DIR/saved_python.dta) for storage types, display formats, values,
missing codes and value labels, and against R's save_dta
(DIR/saved_r.dta) for the factor marker. Values are read with pandas'
read_stata, an open-source reader; types, formats, labels and
characteristics with dta_parser's read_meta. Prints each difference and
exits with status 1 if there is any not listed in EXPECTED.
"""

import math
import os
import sys

import pandas as pd

import dta_parser

d = sys.argv[1]
# Where TypeScript differs from Python on purpose (plan 0021, "saveDta"):
# a column read with a .dta storage type (Parquet's dta profile keeps it)
# is written with that type, where Python's polars datakit takes the
# smallest type that holds the values.
EXPECTED = {("id", "storage"), ("id", "format")}


def meta(who):
    return dta_parser.read_meta(os.path.join(d, f"saved_{who}.dta"))


def values(who):
    with pd.io.stata.StataReader(os.path.join(d, f"saved_{who}.dta")) as r:
        return r.read(convert_missing=True, convert_categoricals=False, convert_dates=False)


diffs = []


def differ(col, what, a, b):
    if (col, what) not in EXPECTED:
        diffs.append(f"{col}: {what}: TypeScript {a!r}, Python {b!r}")


tm, pm = meta("typescript"), meta("python")
tv, pv = values("typescript"), values("python")
if list(tm["columns"]) != list(pm["columns"]):
    differ("*", "columns", list(tm["columns"]), list(pm["columns"]))
for c, t in tm["columns"].items():
    p = pm["columns"].get(c, {})
    for what in ("storage", "format", "label"):
        if t[what] != p.get(what):
            differ(c, what, t[what], p.get(what))
    sets = [m["value_labels"].get(x["value_labels"]) if x["value_labels"] else None for m, x in ((tm, t), (pm, p))]
    if {str(k): v for k, v in (sets[0] or {}).items()} != {str(k): v for k, v in (sets[1] or {}).items()}:
        differ(c, "value labels", sets[0], sets[1])
    for i, (a, b) in enumerate(zip(tv[c], pv[c])):
        same = a == b or (isinstance(a, float) and isinstance(b, float) and math.isnan(a) and math.isnan(b)) or str(a) == str(b)
        if not same:
            differ(c, f"row {i}", a, b)
if tm["label"] != pm["label"] or tm["notes"] != pm["notes"]:
    differ("*", "label, notes", (tm["label"], tm["notes"]), (pm["label"], pm["notes"]))

# The factor marker, against R's.
rm = meta("r")
mark = lambda m: {c: x["dtaparser_factor"] for c, x in m["characteristics"].items() if "dtaparser_factor" in x}  # noqa: E731
if mark(tm) != mark(rm):
    diffs.append(f"factor markers: TypeScript {mark(tm)}, R {mark(rm)}")

print(f"compared {len(tm['columns'])} columns of TypeScript's saveDta with Python's save_dta"
      f" ({len(EXPECTED)} expected differences), and factor markers with R's: {mark(tm)}")
if diffs:
    print("DIFFERENT:")
    for x in diffs:
        print("  ", x)
    sys.exit(1)
