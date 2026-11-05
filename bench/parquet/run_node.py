"""Benchmark the npm package's Parquet reader and writer against
hyparquet, hyparquet-writer and parquet-wasm in Node, check plan 0018's
targets 1 to 3, and write bench/results/parquet-node.md.

    python bench/parquet/run_node.py [--family F ...] [--libs L ...] [--tasks T ...]
                                     [--inputs I ...] [--only KEY ...] [--report]

Run it from the repository root with a Python that has pyarrow (for the
files' column names), after `scripts/build-wasm.sh`, `npm run build` in
js/ and `npm ci` in bench/node. The inputs are the ones bench/parquet/run.py
makes (the NSFG, DHS and synthetic files, converted to Parquet by our
writer, pyarrow and polars, in --data); this script does not make them.

Cases (bench/parquet/case.mjs): reads of the whole file (full), five
columns spread over it (five), 1,000 rows from the middle (window), and
the whole file then one pass over every value (pass), into JavaScript
columns, on the pyarrow, polars and our files; writes of the .dta file's
columns, already in memory in each library's own table, with its
defaults (write) and with zstd (zstd; level 3 for ours, parquet-wasm's
default level, which it does not let a caller set; hyparquet-writer has
no zstd of its own).

Method, as run.py: every case five times, each in a fresh process under
/usr/bin/time -l, the file in the page cache; medians of wall time and
CPU time (user plus system, all threads) of the task alone, and of peak
RSS; the one-minute load average before each run is recorded. The
machine is shared, so each file's runs hold the lock directory
/tmp/claude-501/bench.lock (mkdir), released as soon as they end.
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
MB = base.MB
MIB = base.MIB
LIBS = ["ours", "hyparquet", "parquet-wasm"]
WRITE_LIBS = {"hyparquet": "hyparquet-writer", "parquet-wasm": "parquet-wasm"}
READS = base.READS
WRITES = base.WRITES
INPUTS = base.INPUTS
TIMEOUT = 10 * 60
LOCK = Path("/tmp/claude-501/bench.lock")
GAP = 45  # seconds between releasing the lock and taking it again


class Lock:
    """The shared benchmark lock: a directory made with mkdir."""

    def __enter__(self):
        while True:
            try:
                LOCK.mkdir()
                break
            except FileExistsError:
                time.sleep(30)
        (LOCK / "owner").write_text(f"TypeScript Parquet benchmarks (bench/parquet/run_node.py), pid {os.getpid()}\n")
        return self

    def __exit__(self, *exc):
        shutil.rmtree(LOCK, ignore_errors=True)
        # Others wait on the lock by polling; leave them room to take it
        # before this script takes it again for its next file.
        if exc[0] is None:
            time.sleep(GAP)


def node_case(lib, task, path, report, f):
    return ["node", str(HERE / "case.mjs"), lib, task, str(path), str(report), ",".join(f["cols"]), str(f["skip"]), str(f["n"])]


def measure(cmd, report, runs):
    saved = base.RUNS
    base.RUNS = runs
    try:
        return base.measure(cmd, report)
    finally:
        base.RUNS = saved


def run_all(files, out, libs, tasks, inputs, runs):
    out.mkdir(parents=True, exist_ok=True)
    report = out / f"tmp-{os.getpid()}.json"
    for f in files:
        todo = []
        for task in [t for t in tasks if t in READS]:
            for inp in inputs:
                for lib in libs:
                    path = out / "raw" / f["key"] / inp / f"{lib}-{task}.json"
                    if not path.exists():
                        todo.append((path, f["files"][inp], node_case(lib, task, f["files"][inp], report, f)))
        for task in [t for t in tasks if t in WRITES]:
            for lib in libs:
                wlib = WRITE_LIBS.get(lib, lib)
                if wlib == "hyparquet-writer" and task == "zstd":
                    continue
                path = out / "raw" / f["key"] / "dta" / f"{lib}-{task}.json"
                if not path.exists():
                    todo.append((path, f["dta"], ["node", str(HERE / "case.mjs"), wlib, task, str(f["dta"]), str(report), "", "0", "0"]))
        if not todo:
            continue
        print(f"{f['family']} {f['label']}: {f['rows']:,} rows, {f['ncols']:,} columns, {len(todo)} cases", flush=True)
        with Lock():
            for path, warm, cmd in todo:
                base.warm(warm)
                t = time.time()
                m = measure(cmd, report, runs)
                if "error" not in m and m.get("rss") is None:
                    m = {"error": "no peak RSS from /usr/bin/time -l (run outside a sandbox)"}
                if "error" not in m:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(json.dumps(m))
                if time.time() - t > 2 or "error" in m:
                    shown = m["error"][:200] if "error" in m else f"{m['wall']:.4g} s, {m['rss']:.0f} MB"
                    print(f"  {cmd[2]} {cmd[3]} {path.parent.name}: {shown}", flush=True)
                if "error" in m:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.with_suffix(".error").write_text(m["error"])


def load(out, f, inp, name):
    p = out / "raw" / f["key"] / inp / f"{name}.json"
    return json.loads(p.read_text()) if p.exists() else None


def errored(out, f, inp, name):
    p = out / "raw" / f["key"] / inp / f"{name}.error"
    return p.read_text().strip() if p.exists() else None


def evaluate(files, out):
    """Targets 1 to 3 against each library, as plan 0018 states them."""
    rows, misses, notes = [], [], []
    for lib in LIBS[1:]:
        for task in READS + WRITES:
            for inp in (INPUTS if task in READS else ["dta"]):
                pairs = []
                for f in files:
                    o = load(out, f, inp, f"ours-{task}")
                    t = load(out, f, inp, f"{lib}-{task}")
                    if o and t:
                        pairs.append((f, o, t))
                    elif o and errored(out, f, inp, f"{lib}-{task}"):
                        notes.append(f"{lib} {task} {inp} {f['label']}: {errored(out, f, inp, f'{lib}-{task}')[:160]}")
                if not pairs:
                    continue
                for fam in ("nsfg", "dhs", "synthetic"):
                    fp = [p for p in pairs if p[0]["family"] == fam]
                    if not fp:
                        continue
                    gw = base.geomean([p[1]["wall"] for p in fp]) / base.geomean([p[2]["wall"] for p in fp])
                    gr = base.geomean([p[1]["rss"] for p in fp]) / base.geomean([p[2]["rss"] for p in fp])
                    gc = base.geomean([p[1]["cpu"] for p in fp]) / base.geomean([p[2]["cpu"] for p in fp])
                    rows.append({"lib": lib, "task": task, "input": inp, "family": fam, "n": len(fp), "wall": gw, "rss": gr, "cpu": gc})
                    if fam != "synthetic":
                        if gw > 1.05:
                            misses.append(f"1 wall: {lib} {task} {inp} {fam}: geometric mean {gw:.2f}x")
                        if gr > 1.05:
                            misses.append(f"1 RSS: {lib} {task} {inp} {fam}: geometric mean {gr:.2f}x")
                for f, o, t in pairs:
                    if o["wall"] > 1.25 * t["wall"] and o["wall"] - t["wall"] >= 0.020:
                        misses.append(f"2 wall: {lib} {task} {inp} {f['label']}: {base.fmt_s(o['wall'])} vs {base.fmt_s(t['wall'])} ({o['wall'] / t['wall']:.2f}x)")
                    if o["rss"] > 1.25 * t["rss"] and (o["rss"] - t["rss"]) * MB >= 16 * MIB:
                        misses.append(f"2 RSS: {lib} {task} {inp} {f['label']}: {o['rss']:.0f} vs {t['rss']:.0f} MB ({o['rss'] / t['rss']:.2f}x)")
                    s = t["wall"] / o["wall"]
                    allowed = t["cpu"] * max(1.15, s)
                    if o["cpu"] > allowed:
                        misses.append(f"3 CPU: {lib} {task} {inp} {f['label']}: {o['cpu']:.3f} s vs {t['cpu']:.3f} s, speedup {s:.2f} allows {allowed:.3f} s")
    return rows, misses, notes


def report(files, out, dest):
    rows, misses, notes = evaluate(files, out)
    names = {"hyparquet": "hyparquet (writes: hyparquet-writer)", "parquet-wasm": "parquet-wasm"}
    lines = ["# Parquet benchmarks (TypeScript, Node)", "",
             "Written by `bench/parquet/run_node.py`; see bench/RESULTS.md for what the numbers mean.", ""]
    loads, versions = [], {}
    for f in files:
        d = out / "raw" / f["key"]
        if not d.exists():
            continue
        for p in d.rglob("*.json"):
            m = json.loads(p.read_text())
            loads.extend(r.get("load", 0) for r in m.get("runs", []))
            lib = p.stem.rsplit("-", 1)[0]
            if p.parent.name == "dta":
                lib = WRITE_LIBS.get(lib, lib)
            versions.setdefault(lib, (m.get("version"), m.get("threads"), m["runs"][0].get("node") if m.get("runs") else None))
    if loads:
        lines += [f"One-minute load average before each run: median {statistics.median(loads):.1f}, "
                  f"range {min(loads):.1f} to {max(loads):.1f}, over {len(loads):,} runs.", ""]
    lines += ["| library | version | threads | Node |", "|---|---|---|---|"]
    for lib, (v, t, n) in sorted(versions.items()):
        lines.append(f"| {lib} | {v} | {t} | {n} |")
    lines += ["", "## Ratios, ours to theirs (geometric means)", "",
              "Below 1 is better for us. Target 1 holds where wall and RSS are at most 1.05 on NSFG and DHS.", "",
              "| against | case | input | family | files | wall | CPU | peak RSS |", "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append(f"| {names[r['lib']]} | {base.TASK_NAMES[r['task']]} | {r['input']} | {base.FAMILIES[r['family']]} | {r['n']} | "
                     f"{r['wall']:.2f} | {r['cpu']:.2f} | {r['rss']:.2f} |")
    lines += ["", "## Misses", ""]
    lines += [f"- {m}" for m in misses] or ["None: targets 1 to 3 hold against every library, case, input and family."]
    lines += ["", "## Cases another library could not run", ""]
    lines += [f"- {n}" for n in sorted(set(notes))] or ["None."]
    lines += ["", "## Every file", ""]
    for f in files:
        lines += [f"### {f['label']}", "",
                  f"{f['rows']:,} rows, {f['ncols']:,} columns; Parquet " + ", ".join(f"{i} {f['size'][i] / MB:.1f} MB" for i in INPUTS) + ".", "",
                  "| case | input | " + " | ".join(LIBS) + " |", "|---|---|" + "---|" * len(LIBS)]
        for task in READS + WRITES:
            for inp in (INPUTS if task in READS else ["dta"]):
                cells = []
                for lib in LIBS:
                    m = load(out, f, inp, f"{lib}-{task}")
                    cells.append(f"{base.fmt_s(m['wall'])} / {m['cpu']:.2f} s / {m['rss']:.0f} MB" if m else ("failed" if errored(out, f, inp, f"{lib}-{task}") else "–"))
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
    ap.add_argument("--skip", nargs="*", default=[])
    ap.add_argument("--runs", type=int, default=base.RUNS)
    ap.add_argument("--data", default="/private/tmp/claude-501/pq-bench")
    ap.add_argument("--out", default="/private/tmp/claude-501/pq-bench-node")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--dest", default=str(ROOT / "bench" / "results" / "parquet-node.md"))
    a = ap.parse_args()
    base.TIMEOUT = TIMEOUT
    files = base.find_files(a.family)
    if a.only:
        files = [f for f in files if f["key"] in a.only or f["label"] in a.only]
    files = [f for f in files if f["key"] not in a.skip]
    files = base.prepare(files, Path(a.data))
    out = Path(a.out)
    if not a.report:
        run_all(files, out, a.libs, a.tasks, a.inputs, a.runs)
    report(files, out, Path(a.dest))


if __name__ == "__main__":
    main()
