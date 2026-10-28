"""Write .dta fixtures with pandas from data made here.

Run from the repository root: python3 compat/make_fixtures.py
"""

import numpy as np
import pandas as pd

OUT = "compat/fixtures"
LONG = "long text " * 300  # 3000 bytes: needs a strL


def frame(with_strl: bool) -> pd.DataFrame:
    df = pd.DataFrame(
        {
            "i8": np.array([1, -127, 100, 0, 5], dtype=np.int8),
            "i16": np.array([1, -32767, 32740, 0, 5], dtype=np.int16),
            "i32": np.array([1, -2147483647, 2147483620, 0, 5], dtype=np.int32),
            "f32": np.array([1.5, -3.25, np.nan, 1e30, 0], dtype=np.float32),
            "f64": np.array([1.5, np.nan, -1e300, 1 / 3, 0], dtype=np.float64),
            "s": ["a", "bé", "", "longer string", "z"],
            "labelled": np.array([1, 2, 1, 3, 2], dtype=np.int32),
        }
    )
    if with_strl:
        df["strl"] = [LONG, "short", "", LONG + "!", LONG]
    return df


def write(release: int, byteorder: str) -> None:
    with_strl = release >= 117
    df = frame(with_strl)
    kwargs = dict(
        write_index=False,
        data_label="pandas fixture",
        variable_labels={"i8": "An int8", "f64": "A float64"},
        version=release,
        byteorder=byteorder,
        value_labels={"labelled": {1: "one", 2: "two", 3: "three"}},
    )
    if with_strl:
        kwargs["convert_strl"] = ["strl"]
    suffix = "le" if byteorder == "<" else "be"
    df.to_stata(f"{OUT}/pandas_{release}_{suffix}.dta", **kwargs)


for release in (114, 117, 118, 119):
    for byteorder in ("<", ">"):
        write(release, byteorder)
