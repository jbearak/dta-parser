"""One timed read with pandas: print elapsed seconds.
    python3 bench/read_case.py <task> <file>
task: full, five, or touch (full, then compare every string value).
"""
import sys
import time

import pandas as pd

task, path = sys.argv[1], sys.argv[2]
cols = ["V1", "V100", "V200", "V300", "V400"] if task == "five" else None
start = time.perf_counter()
df = pd.read_stata(path, columns=cols, convert_categoricals=False, convert_dates=False)
if task == "touch":  # compare every value of every string column
    for c in df.columns:
        if df[c].dtype == object or str(df[c].dtype).startswith("str"):
            int((df[c] == "x").sum())
print(f"{time.perf_counter() - start:.2f}")
