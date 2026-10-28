"""One timed read with pandas: print elapsed seconds.
    python3 bench/read_case.py <task> <file>
"""
import sys
import time

import pandas as pd

task, path = sys.argv[1], sys.argv[2]
cols = ["V1", "V100", "V200", "V300", "V400"] if task == "five" else None
start = time.perf_counter()
pd.read_stata(path, columns=cols, convert_categoricals=False, convert_dates=False)
print(f"{time.perf_counter() - start:.2f}")
