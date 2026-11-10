"""R's Parquet readers, first call against warm: datakit's read_parquet()
beside arrow and nanoparquet, each read timed twice over.

    python bench/parquet/warm.py [--family F ...] [--libs L ...] [--tasks T ...]
                                 [--inputs I ...] [--report]

bench/parquet/run.py times each case once per fresh process: the first
call a library gets, with whatever it sets up once (arrow starts its
threads; every library's code is paged in). That is what a script that
reads one file pays. A session that reads many files pays it once, so
this run also times the calls after the first, in the same process:
each case runs in one fresh process (bench/parquet/case.R with WARM),
which makes the first call and then up to seven more, with gc() before
each, and reports the first call and the median of the rest.

Files and cases are run.py's: the Parquet files it made in --data
(default /private/tmp/claude-501/pq-bench) of the synthetic, NSFG and
DHS files, as written by pyarrow and by our writer, read whole (full),
five columns (five), 1,000 rows from the middle (window) and whole with
a pass over every value (pass). The .dta files they were made from are
not needed. Peak memory is not measured here (a
process makes many reads); run.py's table has it.

Run it from the repository root with a Python that has pyarrow; R needs
datakit, arrow, nanoparquet and jsonlite (R_LIBS may point at a scratch
library). Measurements are cached under --out (default
/private/tmp/claude-501/pq-bench-warm); delete a file there to run it
again. Writes bench/results/parquet-r-warm.md.
"""

import argparse
import os
import statistics
from pathlib import Path

import pyarrow.parquet as pq

import run

LIBS = ["ours", "arrow", "nanoparquet"]
INPUTS = ["pyarrow", "ours"]
WARM = 7
NAMES = {"ours": "datakit", "arrow": "arrow", "nanoparquet": "nanoparquet"}


def find_files(data, families, inputs):
    """run.py's files, from the Parquet copies it made, with its cases'
    columns and window."""
    files = []
    for p in sorted((data / "ours").glob("*.parquet")):
        key = p.stem
        family = key.split("-")[0] if key.split("-")[0] in ("nsfg", "dhs") else "synthetic"
        paths = {i: data / i / p.name for i in inputs}
        if family not in families or not all(q.exists() for q in paths.values()):
            continue
        meta = pq.ParquetFile(p).metadata
        names = [meta.schema.column(i).name for i in range(meta.num_columns)]
        picks = sorted({round(k * (len(names) - 1) / 4) for k in range(5)})
        files.append({"family": family, "key": key, "label": key.split("-", 1)[-1], "files": paths,
                      "rows": meta.num_rows, "ncols": len(names), "cols": [names[i] for i in picks],
                      "skip": meta.num_rows // 2, "n": min(1000, meta.num_rows - meta.num_rows // 2)})
    return files


def run_all(files, out, libs, tasks, inputs):
    out.mkdir(parents=True, exist_ok=True)
    report = out / f"tmp-{os.getpid()}.json"
    for f in files:
        print(f"{f['family']} {f['label']}: {f['rows']:,} rows, {f['ncols']:,} columns", flush=True)
        for task in tasks:
            for inp in inputs:
                run.warm(f["files"][inp])
                for lib in libs:
                    cmd = run.case_cmd(lib, task, str(f["files"][inp]), str(report), ",".join(f["cols"]),
                                       str(f["skip"]), str(f["n"]), str(WARM))
                    path = out / "raw" / f["key"] / inp / f"{lib}-{task}.json"
                    m = run.cached(path, lambda: run.launch(cmd, report))
                    if "error" in m:
                        print(f"  {task} {inp} {lib}: {m['error'][:200]}", flush=True)


def ratio(pairs, key):
    ours, theirs = run.geomean([p[0][key] for p in pairs]), run.geomean([p[1][key] for p in pairs])
    return ours / theirs if ours and theirs else float("nan")


def report(files, out, dest, libs, tasks, inputs):
    loads, versions, threads = [], {}, {}
    lines = ["# Parquet benchmarks (R): the first call and the calls after it", "",
             "Written by `bench/parquet/warm.py`; bench/RESULTS.md says what the numbers mean.", ""]
    rows, worst = [], []
    for lib in [l for l in libs if l != "ours"]:
        for task in tasks:
            for inp in inputs:
                for fam in ("nsfg", "dhs", "synthetic"):
                    pairs = []
                    for f in [f for f in files if f["family"] == fam]:
                        o, t = run.load(out, f, inp, f"ours-{task}"), run.load(out, f, inp, f"{lib}-{task}")
                        if o and t:
                            pairs.append((o, t, f))
                            for m, name in ((o, "ours"), (t, lib)):
                                loads.append(m["load"])
                                versions[name] = m["version"]
                                threads[name] = m["threads"]
                    if not pairs:
                        continue
                    rows.append((lib, task, inp, fam, len(pairs), ratio(pairs, "wall"), ratio(pairs, "warm_wall"),
                                 ratio(pairs, "cpu"), ratio(pairs, "warm_cpu")))
                    if fam == "synthetic":
                        for o, t, f in pairs:
                            worst.append((lib, task, inp, f["label"], o, t))
    lines += [f"One-minute load average before each process: median {statistics.median(loads):.1f}, "
              f"range {min(loads):.1f} to {max(loads):.1f}.", "",
              "| library | version | threads |", "|---|---|---|"]
    lines += [f"| {NAMES[k]} | {versions[k]} | {threads[k]} |" for k in libs if k in versions]
    lines += ["", "## Ratios, datakit to the other library (geometric means)", "",
              "Below 1 is better for datakit. \"First\" is a fresh process's first call; \"warm\" is the median of "
              f"up to {WARM} further calls in that process.", "",
              "| against | case | input | family | files | wall, first | wall, warm | CPU, first | CPU, warm |",
              "|---|---|---|---|---|---|---|---|---|"]
    for lib, task, inp, fam, n, w1, w2, c1, c2 in rows:
        lines.append(f"| {NAMES[lib]} | {run.TASK_NAMES[task]} | {inp} | {run.FAMILIES[fam]} | {n} | {w1:.2f} | "
                     f"{w2:.2f} | {c1:.2f} | {c2:.2f} |")
    lines += ["", "## The synthetic files, each", "",
              "| against | case | input | file | datakit, first | datakit, warm | theirs, first | theirs, warm |",
              "|---|---|---|---|---|---|---|---|"]
    for lib, task, inp, label, o, t in worst:
        lines.append(f"| {NAMES[lib]} | {run.TASK_NAMES[task]} | {inp} | {label} | {run.fmt_s(o['wall'])} | "
                     f"{run.fmt_s(o['warm_wall'])} | {run.fmt_s(t['wall'])} | {run.fmt_s(t['warm_wall'])} |")
    dest.write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--family", nargs="*", default=list(run.FAMILIES))
    ap.add_argument("--libs", nargs="*", default=LIBS)
    ap.add_argument("--tasks", nargs="*", default=run.READS)
    ap.add_argument("--inputs", nargs="*", default=INPUTS)
    ap.add_argument("--data", default="/private/tmp/claude-501/pq-bench")
    ap.add_argument("--out", default="/private/tmp/claude-501/pq-bench-warm")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--dest", default=str(run.ROOT / "bench" / "results" / "parquet-r-warm.md"))
    a = ap.parse_args()
    files = find_files(Path(a.data), a.family, a.inputs)
    out = Path(a.out)
    if not a.report:
        run_all(files, out, a.libs, a.tasks, a.inputs)
    report(files, out, Path(a.dest), a.libs, a.tasks, a.inputs)


if __name__ == "__main__":
    main()
