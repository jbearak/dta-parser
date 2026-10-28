"""Rewrite the read benchmark's long.dta with pandas as releases 114, 117
and 119, so the benchmarks exercise those read paths too.

    python bench/make_release_variants.py [DIR]

DIR (default /private/tmp/claude-501/bigbench) holds long.dta, made by
bench/make_large.R; this writes long_114.dta, long_117.dta and
long_119.dta beside it (never committed). pandas is the writer on purpose:
an implementation independent of this repository. Each file is read back
and compared with the source; anything pandas cannot carry is printed.
"""

import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

NULLABLE = {"int8": "Int8", "int16": "Int16", "int32": "Int32"}


def read(path):
    """long.dta as pandas sees it, with each column back in its storage type
    (pandas turns an integer column with `.` into float64), plus the parts
    of the metadata pandas can write."""
    with pd.io.stata.StataReader(path) as r:
        df = r.read(convert_dates=False, convert_categoricals=False,
                    convert_missing=False, preserve_dtypes=True)
        storage = dict(zip(r._varlist, r._dtyplist))
        labels = r.variable_labels()
        data_label = r.data_label
        value_labels = r.value_labels()
        formats = dict(zip(r._varlist, r._fmtlist))
    for c in df.columns:
        st = storage[c]
        name = st.name if isinstance(st, np.dtype) else None
        if name in NULLABLE and df[c].dtype.kind == "f":
            df[c] = df[c].astype(NULLABLE[name])
    return df, labels, data_label, value_labels, formats


def special_missing(path, cols):
    """How many `.a`-`.z` values the numeric columns hold (pandas writes
    every missing value as `.`)."""
    df = pd.read_stata(path, columns=cols, convert_missing=True,
                       convert_dates=False, convert_categoricals=False)
    n = 0
    for c in cols:
        if df[c].dtype == object:
            n += int(df[c].map(lambda v: isinstance(v, pd.io.stata.StataMissingValue)
                               and v.value != 0 and str(v) != ".").sum())
    return n


def main():
    d = Path(sys.argv[1] if len(sys.argv) > 1 else "/private/tmp/claude-501/bigbench")
    src = d / "long.dta"
    t0 = time.time()
    df, labels, data_label, value_labels, formats = read(src)
    print(f"read {src}: {df.shape[0]:,} rows x {df.shape[1]} in {time.time() - t0:.0f} s")
    numeric = [c for c in df.columns if pd.api.types.is_numeric_dtype(df[c].dtype)]
    lost = special_missing(src, [c for c in numeric if df[c].isna().any()])
    print(f"  .a-.z values (pandas writes them as `.`): {lost}")
    if value_labels:
        print(f"  value labels: {len(value_labels)} sets (pandas writes them only for "
              "columns it is given them for; not carried)")
    for release in (114, 117, 119):
        out = d / f"long_{release}.dta"
        t = time.time()
        df.to_stata(out, version=release, write_index=False,
                    variable_labels={k: v for k, v in labels.items() if v},
                    data_label=data_label or None)
        back, *_ = read(out)
        same = back.equals(df) and list(back.dtypes) == list(df.dtypes)
        with pd.io.stata.StataReader(out) as r:
            r.variable_labels()  # reads the header
            fmt_out = dict(zip(r._varlist, r._fmtlist))
        changed = {c: (formats[c], fmt_out[c]) for c in formats if formats[c] != fmt_out[c]}
        print(f"wrote {out.name}: {out.stat().st_size / 1e6:,.0f} MB in {time.time() - t:.0f} s; "
              f"values and storage types {'match' if same else 'DIFFER'}; "
              f"formats changed: {changed or 'none'}")
        if not same:
            for c in df.columns:
                if not back[c].equals(df[c]) or back[c].dtype != df[c].dtype:
                    print(f"  {c}: {df[c].dtype} -> {back[c].dtype}")
            sys.exit(1)


if __name__ == "__main__":
    main()
