"""Plan 0019's Python benchmark: datakit's read_parquet and save_parquet
(and read_dta, save_dta), against polars and pyarrow; check plan 0018's
targets 1 to 3 and write bench/results/parquet-datakit.md (PR 2a's run,
through a stand-in for datakit, is in bench/results/parquet-polars.md).

    python bench/parquet/run_polars.py [--family F ...] [--libs L ...] [--tasks T ...]
                                       [--inputs I ...] [--only KEY ...] [--report]

Run it from the repository root with a Python that has dta_parser and
datakit installed from this checkout, polars and pyarrow. The inputs are bench/parquet/
run.py's (every file converted to Parquet by our writer, and from that by
pyarrow and polars with their defaults, in --data).

Gated (bench/parquet/case_polars.py, each case in a fresh process):
reads (full, five, window, pass) of the pyarrow, polars and our files by
ours, pl.read_parquet (the window as pl.scan_parquet(...).slice().
collect()) and pyarrow.parquet.read_table (the window as the row groups
holding it, sliced); writes of the frame pl.read_parquet gives of our
file, before timing, by ours, DataFrame.write_parquet and pq.write_table
of df.to_arrow(), with each library's defaults (write) and zstd level 3
(zstd). Published, not gated: the .dta read and write (dtaread,
dtawrite) against dta_parser's pandas reader and writer.

Method as bench/parquet/run.py's: five runs per case (three for files
over 1 GB), each in a fresh process under /usr/bin/time -l, medians of
wall and CPU time of the task alone and of peak RSS; the one-minute load
average recorded before each run. Each file's cases run while this holds
the lock directory /tmp/claude-501/bench.lock, released between files.
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
LOCK = Path("/tmp/claude-501/bench.lock")
GATED = ["polars", "pyarrow"]
LIBS = ["ours", *GATED]
READS = base.READS
WRITES = base.WRITES
DTA_TASKS = ["dtaread", "dtawrite"]
INPUTS = base.INPUTS
MB, MIB = base.MB, base.MIB
LIB_NAMES = {"ours": "datakit", "polars": "polars", "pyarrow": "pyarrow (Table)",
             "pandas": "dta_parser (pandas)"}
TASK_NAMES = dict(base.TASK_NAMES, dtaread=".dta read", dtawrite=".dta write")


class Lock:
    """The shared benchmark lock: a directory, with our name and PID."""

    def __enter__(self):
        while True:
            try:
                LOCK.mkdir()
                break
            except FileExistsError:
                time.sleep(30)
        (LOCK / "owner").write_text(f"plan 0019 Python benchmark (bench/parquet/run_polars.py), pid {os.getpid()}\n")
        return self

    def __exit__(self, *exc):
        shutil.rmtree(LOCK, ignore_errors=True)
        # A gap before taking it again, so an agent waiting for it gets a turn.
        time.sleep(45)


def run_all(files, out, libs, tasks, inputs):
    out.mkdir(parents=True, exist_ok=True)
    report = out / f"tmp-{os.getpid()}.json"
    case = HERE / "case_polars.py"
    for f in files:
        base.RUNS = 3 if f["dta_size"] > 1e9 else 5
        todo = []
        for task in [t for t in tasks if t in READS]:
            for inp in inputs:
                for lib in libs:
                    path = out / "raw" / f["key"] / inp / f"{lib}-{task}.json"
                    if not path.exists():
                        todo.append((f["files"][inp], path, [sys.executable, str(case), lib, task, str(f["files"][inp]),
                                                             str(report), ",".join(f["cols"]), str(f["skip"]), str(f["n"])]))
        for task in [t for t in tasks if t in WRITES]:
            for lib in libs:
                path = out / "raw" / f["key"] / "write" / f"{lib}-{task}.json"
                if not path.exists():
                    todo.append((f["files"]["ours"], path, [sys.executable, str(case), lib, task, str(f["files"]["ours"]),
                                                            str(report), "", "0", "0"]))
        for task in [t for t in tasks if t in DTA_TASKS]:
            for lib in ("ours", "pandas"):
                path = out / "raw" / f["key"] / "dta" / f"{lib}-{task}.json"
                if not path.exists():
                    todo.append((f["dta"], path, [sys.executable, str(case), lib, task, str(f["dta"]), str(report),
                                                  "", "0", "0"]))
        if not todo:
            continue
        print(f"{f['family']} {f['label']}: {f['rows']:,} rows, {f['ncols']:,} columns, {len(todo)} cases", flush=True)
        with Lock():
            warmed = set()
            for source, path, cmd in todo:
                if source not in warmed:
                    base.warm(source)
                    warmed.add(source)
                t = time.time()
                m = base.cached(path, lambda: base.measure(cmd, report))
                if time.time() - t > 5 or "error" in m:
                    shown = m["error"][:300] if "error" in m else f"{m['wall']:.4g} s, {m['rss']:.0f} MB"
                    print(f"  {path.parent.name}/{path.stem}: {shown}", flush=True)


def pairs_of(files, out, inp, task, lib, against):
    pairs = []
    for f in files:
        o = base.load(out, f, inp, f"{lib}-{task}")
        t = base.load(out, f, inp, f"{against}-{task}")
        if o and t:
            pairs.append((f, o, t))
    return pairs


def evaluate(files, out):
    rows, misses = [], []
    cases = [(task, inp) for task in READS for inp in INPUTS] + [(task, "write") for task in WRITES]
    for lib in GATED:
        for task, inp in cases:
            pairs = pairs_of(files, out, inp, task, "ours", lib)
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
    for task in DTA_TASKS:
        pairs = pairs_of(files, out, "dta", task, "ours", "pandas")
        for fam in ("nsfg", "dhs", "synthetic"):
            fp = [p for p in pairs if p[0]["family"] == fam]
            if fp:
                g = lambda k, i: base.geomean([p[i][k] for p in fp])
                published.append({"task": task, "family": fam, "n": len(fp), "wall": g("wall", 1) / g("wall", 2),
                                  "rss": g("rss", 1) / g("rss", 2), "cpu": g("cpu", 1) / g("cpu", 2)})
    return rows, published, misses


def report(files, out, dest):
    rows, published, misses = evaluate(files, out)
    lines = ["# Parquet benchmarks (Python, datakit into polars)", "",
             "Written by `bench/parquet/run_polars.py`; bench/RESULTS.md says what the numbers mean.", ""]
    loads, versions = [], {}
    for f in files:
        d = out / "raw" / f["key"]
        if not d.exists():
            continue
        for p in d.rglob("*.json"):
            m = json.loads(p.read_text())
            loads.extend(r.get("load", 0) for r in m.get("runs", []))
            lib = p.stem.rsplit("-", 1)[0]
            versions.setdefault(lib, (m.get("version"), m.get("threads")))
    if loads:
        lines += [f"One-minute load average before each run: median {statistics.median(loads):.1f}, "
                  f"range {min(loads):.1f} to {max(loads):.1f} (plan 0018 asks for under 2).", ""]
    lines += ["| library | version | threads |", "|---|---|---|"]
    for lib, (v, t) in sorted(versions.items()):
        lines.append(f"| {LIB_NAMES.get(lib, lib)} | {v} | {t} |")
    lines += ["", "## Ratios, ours to theirs (geometric means), gated", "",
              "Below 1 is better for us. Target 1 holds where wall and RSS are at most 1.05 on NSFG and DHS. "
              "Writes are of the frame pl.read_parquet gives of our file.", "",
              "| against | case | input | family | files | wall | CPU | peak RSS |", "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append(f"| {LIB_NAMES[r['lib']]} | {TASK_NAMES[r['task']]} | {r['input']} | {base.FAMILIES[r['family']]} | "
                     f"{r['n']} | {r['wall']:.2f} | {r['cpu']:.2f} | {r['rss']:.2f} |")
    lines += ["", "## .dta into polars against dta_parser's pandas path (published, not gated)", "",
              "| case | family | files | wall | CPU | peak RSS |", "|---|---|---|---|---|---|"]
    for r in published:
        lines.append(f"| {TASK_NAMES[r['task']]} | {base.FAMILIES[r['family']]} | {r['n']} | {r['wall']:.2f} | "
                     f"{r['cpu']:.2f} | {r['rss']:.2f} |")
    lines += ["", "## Misses", ""]
    lines += [f"- {m}" for m in misses] or ["None: every target holds."]
    lines += ["", "## Every file", "", "Each cell: wall / CPU / peak RSS (median of the runs).", ""]
    libs = ["ours", "polars", "pyarrow"]
    for f in files:
        lines += [f"### {f['label']}", "", f"{f['rows']:,} rows, {f['ncols']:,} columns; .dta {f['dta_size'] / MB:.1f} MB.", "",
                  "| case | input | " + " | ".join(LIB_NAMES[l] for l in libs) + " |", "|---|---|" + "---|" * len(libs)]
        for task, inp in [(t, i) for t in READS for i in INPUTS] + [(t, "write") for t in WRITES] + [(t, "dta") for t in DTA_TASKS]:
            cells = []
            for lib in (libs if inp != "dta" else ["ours", "pandas", None]):
                m = base.load(out, f, inp, f"{lib}-{task}") if lib else None
                cells.append(f"{base.fmt_s(m['wall'])} / {m['cpu']:.2f} s / {m['rss']:.0f} MB" if m else "–")
            name = TASK_NAMES[task] + (" (ours, pandas)" if inp == "dta" else "")
            lines.append(f"| {name} | {inp} | " + " | ".join(cells) + " |")
        lines.append("")
    dest.write_text("\n".join(lines) + "\n")
    print("\n".join(misses) if misses else "every target holds")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--family", nargs="*", default=list(base.FAMILIES))
    ap.add_argument("--libs", nargs="*", default=LIBS)
    ap.add_argument("--tasks", nargs="*", default=READS + WRITES + DTA_TASKS)
    ap.add_argument("--inputs", nargs="*", default=INPUTS)
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--data", default="/private/tmp/claude-501/pq-bench")
    ap.add_argument("--out", default="/private/tmp/claude-501/pq-bench-datakit-out")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--dest", default=str(ROOT / "bench" / "results" / "parquet-datakit.md"))
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
