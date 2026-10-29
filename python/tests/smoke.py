"""Smoke test for an installed wheel: write a small frame under a
non-ASCII path, read it back, check values and a `.a` code.

Run from outside the checkout so the installed package is imported:
python path/to/smoke.py
"""

import os
import tempfile

import numpy as np
import pandas as pd

import dta_parser as dp

with tempfile.TemporaryDirectory() as tmp:
    folder = os.path.join(tmp, "dátá 数据")
    os.mkdir(folder)
    path = os.path.join(folder, "smoke ü.dta")
    df = pd.DataFrame({
        "n": [1, 2, 3],
        "x": dp.StataArray([1.5, np.nan, np.nan], [0, 2, 1]),
        "s": ["a", "é", "中文"],
    })
    dp.write_dta(df, path)
    back = dp.read_dta(path)
    assert back["n"].tolist() == [1, 2, 3], back["n"]
    assert back["s"].tolist() == ["a", "é", "中文"], back["s"]
    assert back["x"].array.codes.tolist() == [0, 2, 1], back["x"]
    assert back["x"][1] is dp.missing.a
    assert back["x"][0] == 1.5
    assert dp.read_meta(path)["nobs"] == 3
print("smoke test passed")
