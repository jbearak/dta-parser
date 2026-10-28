"""Check that pandas reads each file dtatools wrote (compat/readback.R)
as it reads the fixture it came from (compat/expected/<name>.pandas.json).

Run from the repository root: python3 compat/readback.py <dir>
"""

import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from expected import dump  # noqa: E402

# Fixtures whose text pandas decodes as Latin-1 (before 118); dtatools
# decoded them as Windows-1252 and wrote UTF-8, so their text differs.
LATIN1 = {"haven_113", "haven_114", "haven_115", "haven_117"}

failures = []
checked = 0
for path in sorted(glob.glob(os.path.join(sys.argv[1], "*.dta"))):
    stem = os.path.splitext(os.path.basename(path))[0]
    with open(f"compat/expected/{stem}.pandas.json") as f:
        theirs = json.load(f)
    if "error" in theirs:
        continue  # pandas cannot read the original
    ours = dump(path)
    checked += 1
    if ours["release"] != 118:
        failures.append(f"{stem}: written as release {ours['release']}")
    if ours["data_label"] != theirs["data_label"]:
        failures.append(f"{stem}: data label {ours['data_label']!r} != {theirs['data_label']!r}")
    for a, b in zip(ours["variables"], theirs["variables"]):
        name = b["name"]
        for field in ("name", "format", "label", "labels"):
            if a[field] != b[field]:
                failures.append(f"{stem}.{name}: {field} {a[field]!r} != {b[field]!r}")
        if a["type"] != b["type"] and not b["type"].startswith("str"):
            failures.append(f"{stem}.{name}: type {a['type']} != {b['type']}")
        if b["type"].startswith("str") and stem in LATIN1:
            continue
        if ours["values"][name] != theirs["values"][name]:
            failures.append(f"{stem}.{name}: values differ")

print(f"pandas read back {checked} files")
if failures:
    print("\n".join(failures))
    sys.exit(1)
