"""Benchmark tasks for Python's .dta readers; bench/run.py drives this.

    python bench/cases/case.py READER FILE OUT TASKS RUNS COLS SKIP N

READER is ours (dta_parser), pandas or pyreadstat. TASKS is a comma list
of 1 to 6 (see bench/run.py) or "check". RUNS 1 times one run; more
times a warm-up call, then RUNS calls. COLS (comma list), SKIP and N
are task 3's columns and task 4's window. OUT gets a JSON report.
"""

import hashlib
import json
import os
import sys
import time

import numpy as np
import pandas as pd


def ours():
    import dta_parser as dp

    def write(path, df):
        return lambda dst: dp.write_dta(df, dst)

    return {
        "version": dp.__version__ if hasattr(dp, "__version__") else "0.1.0",
        "read": lambda p: dp.read_dta(p, dates=False),
        "five": lambda p, cols: dp.read_dta(p, columns=cols, dates=False),
        "window": lambda p, skip, n: dp.read_dta(p, skip=skip, n_max=n, dates=False),
        "meta": dp.read_meta,
        "write": write,
        "frame": lambda r: r,
        "canon_meta": lambda p: canon_meta_ours(dp.read_meta(p)),
    }


def pandas_reader():
    opts = {"convert_dates": False, "convert_categoricals": False}

    def window(p, skip, n):
        # pandas has no row offset; its iterator reads past the skipped rows.
        with pd.read_stata(p, iterator=True, **opts) as r:
            if skip:
                r.read(nrows=skip)
            return r.read(nrows=n)

    def meta(p):
        with pd.io.stata.StataReader(p) as r:
            return r.variable_labels(), r.value_labels(), r.data_label

    def write(p, df):
        with pd.io.stata.StataReader(p) as r:
            labels = r.variable_labels()
            sets = r.value_labels()
            attached = dict(zip(r._varlist, r._lbllist))
            data_label = r.data_label
        value_labels = {c: sets[s] for c, s in attached.items() if s in sets and c in df}
        return lambda dst: df.to_stata(dst, version=118, write_index=False,
                                       variable_labels={k: v for k, v in labels.items() if v},
                                       data_label=data_label or None,
                                       value_labels=value_labels or None)

    return {
        "version": pd.__version__,
        "read": lambda p: pd.read_stata(p, **opts),
        "five": lambda p, cols: pd.read_stata(p, columns=cols, **opts),
        "window": window,
        "meta": meta,
        "write": write,
        "frame": lambda r: r,
        "canon_meta": canon_meta_pandas,
    }


def pyreadstat_reader():
    import pyreadstat

    opts = {"disable_datetime_conversion": True}

    def write(p, result):
        df, m = result
        return lambda dst: pyreadstat.write_dta(
            df, dst, file_label=m.file_label or "", column_labels=m.column_labels,
            version=14, variable_value_labels=m.variable_value_labels)

    return {
        "version": pyreadstat.__version__,
        "read": lambda p: pyreadstat.read_dta(p, **opts),
        "five": lambda p, cols: pyreadstat.read_dta(p, usecols=cols, **opts),
        "window": lambda p, skip, n: pyreadstat.read_dta(p, row_offset=skip, row_limit=n, **opts),
        "meta": lambda p: pyreadstat.read_dta(p, metadataonly=True),
        "write": write,
        "frame": lambda r: r[0],
        "canon_meta": canon_meta_pyreadstat,
    }


# In-process runs stop early, after at least three, once they pass this
# many seconds.
BUDGET = 60

READERS = {"ours": ours, "pandas": pandas_reader, "pyreadstat": pyreadstat_reader}


# Task 2: one pass over every value.
def checksum(df):
    total, missing, length = 0.0, 0, 0
    for name in df.columns:
        s = df[name]
        if is_text(s):
            length += int(s.str.len().fillna(0).sum())
            continue
        if hasattr(s.array, "codes"):  # a StataArray
            v, miss = s.array._values, s.array.codes != 0
        else:
            v = s.to_numpy(dtype=np.float64, na_value=np.nan)
            miss = np.isnan(v)
        total += float(v[~miss].sum())
        missing += int(miss.sum())
    return {"sum": total, "missing": missing, "length": length}


def is_text(s):
    """Text, or numbers? pyreadstat gives an all-missing numeric column as
    objects."""
    if s.dtype == object:
        return pd.api.types.infer_dtype(s, skipna=True) not in ("empty", "floating", "integer", "mixed-integer-float")
    return pd.api.types.is_string_dtype(s.dtype)


# Correctness: each column as a hash of its canonical cells.
def sha(*parts):
    h = hashlib.sha256()
    for p in parts:
        h.update(p)
    return h.hexdigest()[:16]


def canon_column(s):
    if is_text(s):
        cells = [b"" if v is None or v is pd.NA or (isinstance(v, float) and np.isnan(v))
                 else v if isinstance(v, bytes) else str(v).encode() for v in s]
        return {"kind": "str", "hash": sha(b"\0".join(cells), str(len(cells)).encode())}
    codes = None
    if hasattr(s.array, "codes"):
        v, miss = np.asarray(s.array._values, dtype=np.float64), s.array.codes != 0
        codes = sha(s.array.codes.tobytes())
    else:
        v = s.to_numpy(dtype=np.float64, na_value=np.nan)
        miss = np.isnan(v)
    v = np.where(miss, 0.0, v).astype("<f8")
    return {"kind": "num", "hash": sha(v.tobytes(), miss.astype(np.uint8).tobytes()), "codes": codes}


def canon_frame(df):
    return {"nrows": len(df), "columns": [canon_column(df[c]) for c in df.columns]}


def hash_text(x):
    return None if x is None else sha(str(x).encode())


def label_text(labels):
    """A value label set as text: one `key<TAB>text` line per label."""
    if labels is None:
        return None
    lines = []
    for k, v in labels.items():
        key = getattr(k, "name", None) or "%.17g" % float(k)
        lines.append(f"{key}\t{v}")
    return hash_text("\n".join(sorted(lines)))


NUMPY_STORAGE = {"int8": "byte", "int16": "int", "int32": "long", "float32": "float", "float64": "double",
                 "double": "double", "float": "float"}


def storage_of(t):
    if isinstance(t, (int, np.integer)):
        return "strL" if t == 32768 else f"str{int(t)}"
    t = str(t)
    if t in NUMPY_STORAGE:
        return NUMPY_STORAGE[t]
    if t == "string":
        return "str"
    return t


def canon_meta_ours(m):
    cols = []
    for name, c in m["columns"].items():
        sets = m["value_labels"]
        cols.append({"name": hash_text(name), "storage": c["storage"], "format": c["format"],
                     "label": hash_text(c["label"]),
                     "value_labels": label_text(sets.get(c["value_labels"], {}))})
    return {"label": hash_text(m["label"]), "columns": cols}


def canon_meta_pandas(p):
    with pd.io.stata.StataReader(p) as r:
        labels = r.variable_labels()
        sets = r.value_labels()
        cols = []
        for name, t, fmt, lbl in zip(r._varlist, r._typlist, r._fmtlist, r._lbllist):
            st = storage_of(t) if isinstance(t, (int, np.integer)) else storage_of(r._dtyplist[r._varlist.index(name)])
            cols.append({"name": hash_text(name), "storage": st, "format": fmt,
                         "label": hash_text(labels.get(name, "")),
                         "value_labels": label_text(sets.get(lbl, {}))})
        return {"label": hash_text(r.data_label), "columns": cols}


def canon_meta_pyreadstat(p):
    import pyreadstat

    _, m = pyreadstat.read_dta(p, metadataonly=True)
    cols = []
    for name, label in zip(m.column_names, m.column_labels):
        cols.append({"name": hash_text(name), "storage": storage_of(m.readstat_variable_types[name]),
                     "format": m.original_variable_types.get(name),
                     "label": hash_text(label or ""),
                     "value_labels": label_text(m.variable_value_labels.get(name, {}))})
    return {"label": hash_text(m.file_label or ""), "columns": cols}


def run_task(r, task, path, cols, skip, n, tmp):
    """One call of `task`; returns (seconds, checksum or None)."""
    if task == 6:
        result = r["read"](path)
        write = r["write"](path, result)
        dst = os.path.join(tmp, f"w{os.getpid()}.dta")
        t = time.perf_counter()
        write(dst)
        elapsed = time.perf_counter() - t
        os.remove(dst)
        return elapsed, None
    t = time.perf_counter()
    out = None
    if task == 1:
        r["read"](path)
    elif task == 2:
        out = checksum(r["frame"](r["read"](path)))
    elif task == 3:
        r["five"](path, cols)
    elif task == 4:
        r["window"](path, skip, n)
    elif task == 5:
        r["meta"](path)
    return time.perf_counter() - t, out


def check(r, path, cols, skip, n, tmp):
    """Canonical forms of every task's result, outside any timing."""
    out = {}

    def attempt(key, f):
        try:
            out[key] = f()
        except Exception as e:  # reported, not hidden
            out[key] = {"error": f"{type(e).__name__}: {e}"[:500]}

    full = {}

    def read_full():
        full["raw"] = r["read"](path)
        full["df"] = r["frame"](full["raw"])
        return canon_frame(full["df"])

    attempt("full", read_full)
    if "df" in full:
        attempt("checksum", lambda: dict(checksum(full["df"]), abs=abs_sum(full["df"])))
    attempt("five", lambda: canon_frame(r["frame"](r["five"](path, cols))))
    attempt("window", lambda: canon_frame(r["frame"](r["window"](path, skip, n))))
    attempt("meta", lambda: r["canon_meta"](path))
    if "df" in full:
        dst = os.path.join(tmp, f"check{os.getpid()}.dta")

        def written():
            r["write"](path, full["raw"])(dst)
            # Re-read by an open-source reader (pandas), as is the source.
            back = pd.read_stata(dst, convert_dates=False, convert_categoricals=False)
            return {"data": canon_frame(back), "meta": canon_meta_pandas(dst)}

        attempt("write", written)
        if os.path.exists(dst):
            os.remove(dst)
    return out


def abs_sum(df):
    total = 0.0
    for name in df.columns:
        s = df[name]
        if not is_text(s):
            v = s.array._values if hasattr(s.array, "codes") else s.to_numpy(dtype=np.float64, na_value=np.nan)
            total += float(np.nansum(np.abs(v)))
    return total


def main():
    reader, path, out_path, tasks, runs, cols, skip, n = sys.argv[1:9]
    r = READERS[reader]()
    report = {"loaded": time.time(), "version": r["version"]}
    cols = cols.split(",") if cols else []
    skip, n, runs = int(skip), int(n), int(runs)
    tmp = os.path.dirname(os.path.abspath(out_path))
    if tasks == "check":
        report["check"] = check(r, path, cols, skip, n, tmp)
    else:
        report["tasks"] = {}
        for task in [int(t) for t in tasks.split(",")]:
            entry = {}
            try:
                times = []
                if runs > 1:
                    entry["first"], entry["checksum"] = run_task(r, task, path, cols, skip, n, tmp)
                    if entry["first"] > BUDGET:  # too slow to repeat: the one run counts
                        times, runs = [entry["first"]], 0
                for _ in range(runs):
                    seconds, entry["checksum"] = run_task(r, task, path, cols, skip, n, tmp)
                    times.append(seconds)
                    if len(times) >= 3 and sum(times) > BUDGET:
                        break
                entry["times"] = times
            except Exception as e:
                entry["error"] = f"{type(e).__name__}: {e}"[:500]
            report["tasks"][str(task)] = entry
    with open(out_path, "w") as f:
        json.dump(report, f)


if __name__ == "__main__":
    main()
