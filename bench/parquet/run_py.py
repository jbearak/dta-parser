"""Benchmark dta_parser's Parquet reader and writer against pyarrow,
pandas, fastparquet and polars (into pandas), check plan 0018's speed
and memory targets 1 to 3 for Python, and write
bench/results/parquet-python.md.

    python bench/parquet/run_py.py [--family F ...] [--libs L ...] [--tasks T ...]
                                   [--inputs I ...] [--only KEY ...] [--report]

Run it from the repository root with a Python that has dta_parser
installed (the wheel), pyarrow, pandas, fastparquet, polars and duckdb.
The inputs are the ones bench/parquet/run.py makes (the R run): every
file converted to Parquet by our writer and from that by pyarrow and
polars with their defaults, in --data.

Cases, each run by bench/parquet/case_py.py in a fresh process:
reads (full, five, window, pass) on the pyarrow, polars and our files by
ours and, into pandas, pyarrow (read_table().to_pandas()), pandas
(read_parquet), fastparquet and polars (.to_pandas()): these are gated.
pyarrow's Table, polars' DataFrame and DuckDB fetched to Arrow (full,
five, window, on pyarrow's files) are published, not gated: they are
not pandas. Writes of
the frame dta_parser.read_dta gives, with each library's defaults and
with zstd 3: ours, DataFrame.to_parquet (pyarrow), fastparquet and
polars (from_pandas().write_parquet()).

Method as bench/parquet/run.py's: five runs per case (three for files
over 1 GB), each in a fresh process under /usr/bin/time -l, medians of
wall and CPU time of the task alone and of peak RSS; the one-minute load
average recorded before each run. The machine is shared: each file's
cases run while this holds the lock directory /private/tmp/claude-501/
bench.lock, released between files.
"""

import argparse
import json
import os
import shutil
import statistics
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run as base  # noqa: E402

ROOT = base.ROOT
HERE = base.HERE
LOCK = Path("/private/tmp/claude-501/bench.lock")
GATED = ["pyarrow", "pandas", "fastparquet", "polars"]
PUBLISHED = ["pyarrow-table", "polars-df", "duckdb-arrow"]
LIBS = ["ours", *GATED, *PUBLISHED]
WRITE_LIBS = ["ours", "pyarrow", "fastparquet", "polars"]
READS = base.READS
WRITES = base.WRITES
INPUTS = base.INPUTS
MB, MIB = base.MB, base.MIB
LIB_NAMES = {"ours": "dta_parser", "pyarrow": "pyarrow → pandas", "pandas": "pandas.read_parquet",
             "fastparquet": "fastparquet", "polars": "polars → pandas", "pyarrow-table": "pyarrow Table",
             "polars-df": "polars DataFrame", "duckdb-arrow": "DuckDB → Arrow"}


class Lock:
    """The shared benchmark lock: a directory, with our name and PID."""

    def __enter__(self):
        while True:
            try:
                LOCK.mkdir()
                break
            except FileExistsError:
                time.sleep(30)
        (LOCK / "owner").write_text(f"python-parquet benchmark (bench/parquet/run_py.py), pid {os.getpid()}\n")
        return self

    def __exit__(self, *exc):
        shutil.rmtree(LOCK, ignore_errors=True)
        # Leave a gap before taking it again for the next file, so that an
        # agent waiting for it (polling every 30 s) gets a turn.
        time.sleep(45)


def run_all(files, out, libs, tasks, inputs):
    report = out / f"tmp-{os.getpid()}.json"
    case = HERE / "case_py.py"
    for f in files:
        base.RUNS = 3 if f["dta_size"] > 1e9 else 5
        todo = []
        for task in [t for t in tasks if t in READS]:
            for inp in inputs:
                for lib in libs:
                    # The published libraries (not gated) on pyarrow's files only.
                    if lib in PUBLISHED and (task == "pass" or inp != "pyarrow"):
                        continue
                    path = out / "raw" / f["key"] / inp / f"{lib}-{task}.json"
                    if not path.exists():
                        todo.append((task, inp, lib, path, [sys.executable, str(case), lib, task, str(f["files"][inp]),
                                                            str(report), ",".join(f["cols"]), str(f["skip"]),
                                                            str(f["n"])]))
        for task in [t for t in tasks if t in WRITES]:
            for lib in [l for l in libs if l in WRITE_LIBS]:
                path = out / "raw" / f["key"] / "dta" / f"{lib}-{task}.json"
                if not path.exists():
                    todo.append((task, "dta", lib, path, [sys.executable, str(case), lib, task, str(f["dta"]),
                                                          str(report), "", "0", "0"]))
        if not todo:
            continue
        print(f"{f['family']} {f['label']}: {f['rows']:,} rows, {f['ncols']:,} columns, {len(todo)} cases",
              flush=True)
        with Lock():
            warmed = set()
            for task, inp, lib, path, cmd in todo:
                source = f["dta"] if inp == "dta" else f["files"][inp]
                if source not in warmed:
                    base.warm(source)
                    warmed.add(source)
                t = time.time()
                m = base.cached(path, lambda: base.measure(cmd, report))
                if time.time() - t > 2 or "error" in m:
                    shown = m["error"][:200] if "error" in m else f"{m['wall']:.4g} s, {m['rss']:.0f} MB"
                    print(f"  {task} {inp} {lib}: {shown}", flush=True)


def evaluate(files, out):
    rows, misses = [], []
    for lib in GATED:
        for task in READS + WRITES:
            if task in WRITES and lib not in WRITE_LIBS:
                continue
            for inp in (INPUTS if task in READS else ["dta"]):
                pairs = []
                for f in files:
                    o = base.load(out, f, inp, f"ours-{task}")
                    t = base.load(out, f, inp, f"{lib}-{task}")
                    if o and t:
                        pairs.append((f, o, t))
                if not pairs:
                    continue
                for fam in ("nsfg", "dhs", "synthetic"):
                    fp = [p for p in pairs if p[0]["family"] == fam]
                    if not fp:
                        continue
                    g = lambda k, i: base.geomean([p[i][k] for p in fp])
                    gw, gr, gc = (g(k, 1) / g(k, 2) for k in ("wall", "rss", "cpu"))
                    rows.append({"lib": lib, "task": task, "input": inp, "family": fam, "n": len(fp),
                                 "wall": gw, "rss": gr, "cpu": gc})
                    if fam != "synthetic":
                        if gw > 1.05:
                            misses.append(f"1 wall: {lib} {task} {inp} {fam}: geometric mean {gw:.2f}x")
                        if gr > 1.05:
                            misses.append(f"1 RSS: {lib} {task} {inp} {fam}: geometric mean {gr:.2f}x")
                for f, o, t in pairs:
                    if o["wall"] > 1.25 * t["wall"] and o["wall"] - t["wall"] >= 0.020:
                        misses.append(f"2 wall: {lib} {task} {inp} {f['label']}: {base.fmt_s(o['wall'])} vs "
                                      f"{base.fmt_s(t['wall'])} ({o['wall'] / t['wall']:.2f}x)")
                    if o["rss"] > 1.25 * t["rss"] and (o["rss"] - t["rss"]) * MB >= 16 * MIB:
                        misses.append(f"2 RSS: {lib} {task} {inp} {f['label']}: {o['rss']:.0f} vs {t['rss']:.0f} MB"
                                      f" ({o['rss'] / t['rss']:.2f}x)")
                    s = t["wall"] / o["wall"]
                    allowed = t["cpu"] * max(1.15, s)
                    if o["cpu"] > allowed:
                        misses.append(f"3 CPU: {lib} {task} {inp} {f['label']}: {o['cpu']:.3f} s vs {t['cpu']:.3f} s, "
                                      f"speedup {s:.2f} allows {allowed:.3f} s")
    published = []
    for lib in PUBLISHED:
        for task in ("full", "five", "window"):
            for inp in ["pyarrow"]:
                for fam in ("nsfg", "dhs", "synthetic"):
                    fp = [(base.load(out, f, inp, f"ours-{task}"), base.load(out, f, inp, f"{lib}-{task}"))
                          for f in files if f["family"] == fam]
                    fp = [p for p in fp if p[0] and p[1]]
                    if fp:
                        g = lambda k, i: base.geomean([p[i][k] for p in fp])
                        published.append({"lib": lib, "task": task, "input": inp, "family": fam, "n": len(fp),
                                          "wall": g("wall", 0) / g("wall", 1), "rss": g("rss", 0) / g("rss", 1),
                                          "cpu": g("cpu", 0) / g("cpu", 1)})
    return rows, published, misses


def report(files, out, dest):
    rows, published, misses = evaluate(files, out)
    lines = ["# Parquet benchmarks (Python)", "",
             "Written by `bench/parquet/run_py.py`; bench/RESULTS.md says what the numbers mean.", ""]
    loads, versions = [], {}
    for f in files:
        d = out / "raw" / f["key"]
        if not d.exists():
            continue
        for p in d.rglob("*.json"):
            m = json.loads(p.read_text())
            loads.append(m.get("load", 0))
            lib = p.stem.rsplit("-", 1)[0]
            versions.setdefault(lib, (m.get("version"), m.get("threads")))
    if loads:
        lines += [f"One-minute load average before the runs: median {statistics.median(loads):.1f}, "
                  f"range {min(loads):.1f} to {max(loads):.1f}.", ""]
    lines += ["| library | version | threads |", "|---|---|---|"]
    for lib, (v, t) in sorted(versions.items()):
        lines.append(f"| {LIB_NAMES.get(lib, lib)} | {v} | {t} |")
    lines += ["", "## Ratios, ours to theirs (geometric means), gated", "",
              "Below 1 is better for us. Target 1 holds where wall and RSS are at most 1.05 on NSFG and DHS.", "",
              "| against | case | input | family | files | wall | CPU | peak RSS |", "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append(f"| {LIB_NAMES[r['lib']]} | {base.TASK_NAMES[r['task']]} | {r['input']} | "
                     f"{base.FAMILIES[r['family']]} | {r['n']} | {r['wall']:.2f} | {r['cpu']:.2f} | {r['rss']:.2f} |")
    lines += ["", "## Ratios against reads into Arrow and polars types (published, not gated)", "",
              "| against | case | input | family | files | wall | CPU | peak RSS |", "|---|---|---|---|---|---|---|---|"]
    for r in published:
        lines.append(f"| {LIB_NAMES[r['lib']]} | {base.TASK_NAMES[r['task']]} | {r['input']} | "
                     f"{base.FAMILIES[r['family']]} | {r['n']} | {r['wall']:.2f} | {r['cpu']:.2f} | {r['rss']:.2f} |")
    lines += ["", "## Misses", ""]
    lines += [f"- {m}" for m in misses] or ["None: every target holds."]
    lines += ["", "## Every file", "", "Each cell: wall / CPU / peak RSS (median of the runs).", ""]
    for f in files:
        lines += [f"### {f['label']}", "",
                  f"{f['rows']:,} rows, {f['ncols']:,} columns; .dta {f['dta_size'] / MB:.1f} MB.", "",
                  "| case | input | " + " | ".join(LIB_NAMES[l] for l in LIBS) + " |",
                  "|---|---|" + "---|" * len(LIBS)]
        for task in READS + WRITES:
            for inp in (INPUTS if task in READS else ["dta"]):
                cells = []
                for lib in LIBS:
                    p = out / "raw" / f["key"] / inp / f"{lib}-{task}.json"
                    m = json.loads(p.read_text()) if p.exists() else None
                    cells.append(f"{base.fmt_s(m['wall'])} / {m['cpu']:.2f} s / {m['rss']:.0f} MB" if m else "–")
                lines.append(f"| {base.TASK_NAMES[task]} | {inp} | " + " | ".join(cells) + " |")
        lines.append("")
    dest.write_text("\n".join(lines) + "\n")
    print("\n".join(misses) if misses else "every target holds")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--family", nargs="*", default=list(base.FAMILIES))
    ap.add_argument("--libs", nargs="*", default=LIBS)
    ap.add_argument("--tasks", nargs="*", default=READS + WRITES)
    ap.add_argument("--inputs", nargs="*", default=INPUTS)
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--data", default="/private/tmp/claude-501/pq-bench")
    ap.add_argument("--out", default="/private/tmp/claude-501/pq-bench-py-out")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--dest", default=str(ROOT / "bench" / "results" / "parquet-python.md"))
    a = ap.parse_args()
    files = base.find_files(a.family)
    if a.only:
        files = [f for f in files if f["key"] in a.only or f["label"] in a.only]
    files = base.prepare(files, Path(a.data))
    out = Path(a.out)
    if not a.report:
        run_all(files, out, a.libs, a.tasks, a.inputs)
    report(files, out, Path(a.dest))


if __name__ == "__main__":
    main()
