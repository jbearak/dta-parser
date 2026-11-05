"""Benchmark our Parquet reader and writer against the other libraries
of one language, check plan 0018's speed and memory targets, and write
bench/results/parquet.md (R) or parquet-julia.md (Julia).

    python bench/parquet/run.py [--lang r|julia] [--family F ...] [--libs L ...]
                                [--tasks T ...] [--inputs I ...] [--only KEY ...] [--report]

R (the default): datakit's read_parquet() and save_parquet() against
arrow, nanoparquet and duckdb. Julia (--lang julia): Datakit's
read_parquet and save_parquet, into and from a DataFrame, against
Parquet2.jl and DuckDB.jl, in
bench/julia's environment (bench/parquet/case.jl). Target 4, other tools
reading our files, does not depend on the language that wrote them, so
the Julia run leaves it out.

Run it from the repository root with a Python that has pyarrow, polars
and duckdb; R needs datakit, arrow, nanoparquet, duckdb and jsonlite
(R_LIBS may point at a scratch library holding them).

Files (never committed): the synthetic long, wide and groups in BENCH_DIR
(bench/make_large.R), every NSFG .dta in NSFG_DIR (bench/nsfg/make.py),
and the ten DHS files bench/run.py uses under DTA_DHS_DIR (read only,
ADR 0013). Each is converted to Parquet four ways in --data (default
/private/tmp/claude-501/pq-bench): by our writer (convert.R), then from
that by pyarrow, polars and DuckDB with their defaults (convert.py).
Our writer also writes each with zstd 3 (ours_zstd), for the other
tools to read: the evidence for the default codec.

Cases. Reads, on the pyarrow, polars and our files: the whole file
(full), five columns spread over it (five), 1,000 rows from the middle
(window), and the whole file then a pass over every value (pass). Writes,
of the frame dtaparser::read_dta gives (every string made first): each
library's defaults (write) and zstd at level 3 (zstd). And pyarrow,
polars and DuckDB in Python reading our file and their own (tool).

Method (plan 0018): every case runs five times, each in a fresh process
under /usr/bin/time -l, with the file in the page cache; the medians of
wall time and CPU time (user plus system) of the task alone, and of the
process's peak RSS, are used. The one-minute load average is recorded
before each run. Every library uses its default thread count, recorded.

Measurements are cached under --out (default
/private/tmp/claude-501/pq-bench-out); delete a file there to run it
again. --report rebuilds the report from the cache.
"""

import argparse
import json
import math
import os
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

import pyarrow.parquet as pq

ROOT = Path(__file__).resolve().parent.parent.parent
HERE = ROOT / "bench" / "parquet"
MB = 1e6
MIB = 1 << 20
RUNS = 5
TIMEOUT = 20 * 60
LIBS_BY_LANG = {"r": ["ours", "arrow", "nanoparquet", "duckdb"], "julia": ["ours", "parquet2", "duckdb"]}
LIBS = LIBS_BY_LANG["r"]
LANG = "r"
READS = ["full", "five", "window", "pass"]
WRITES = ["write", "zstd"]
INPUTS = ["pyarrow", "polars", "ours"]
TOOLS = ["pyarrow", "polars", "duckdb"]
FAMILIES = {"synthetic": "Synthetic", "nsfg": "NSFG", "dhs": "DHS"}
DHS_SURVEYS = ["Senegal 2019", "Turkey 2013", "Tajikistan 2017", "Myanmar 2016", "Dominican Republic 2013"]
TASK_NAMES = {"full": "whole file", "five": "five columns", "window": "1,000 rows", "pass": "read + pass",
              "write": "write, defaults", "zstd": "write, zstd 3", "snappy": "write, snappy"}


def find_files(families):
    files = []
    synth = Path(os.environ.get("BENCH_DIR", "/private/tmp/claude-501/bigbench"))
    for stem in ["long", "wide", "groups"]:
        p = synth / f"{stem}.dta"
        if p.exists():
            files.append({"family": "synthetic", "key": stem, "dta": p, "label": f"{stem}.dta"})
    nsfg = Path(os.environ.get("NSFG_DIR", "/private/tmp/claude-501/nsfg-dta"))
    for p in sorted(nsfg.glob("*.dta")):
        files.append({"family": "nsfg", "key": "nsfg-" + p.stem, "dta": p, "label": p.stem})
    dhs = os.environ.get("DTA_DHS_DIR")
    if dhs:
        for survey in DHS_SURVEYS:
            for recode in ("wm", "bh"):
                p = Path(dhs) / survey / f"{recode}.dta"
                if p.exists():
                    key = "dhs-" + survey.lower().replace(" ", "-") + f"-{recode}"
                    files.append({"family": "dhs", "key": key, "dta": p, "label": f"{survey} {recode}"})
    return [f for f in files if f["family"] in families]


def prepare(files, data):
    """Make the four Parquet versions of each file, and its cases' columns
    and window."""
    todo = [f for f in files if not (data / "ours" / f"{f['key']}.parquet").exists()]
    if todo:
        print(f"converting {len(todo)} files with datakit", flush=True)
        subprocess.run(["Rscript", str(HERE / "convert.R"), str(data / "ours"),
                        *[f"{f['key']}={f['dta']}" for f in todo]], check=True, cwd=ROOT)
    missing = [f["key"] for f in files if any(not (data / t / f"{f['key']}.parquet").exists()
                                               for t in ("pyarrow", "polars", "duckdb"))]
    if missing:
        subprocess.run([sys.executable, str(HERE / "convert.py"), str(data), *missing], check=True, cwd=ROOT)
    todo =[f for f in files if not (data / "ours_zstd" / f"{f['key']}.parquet").exists()]
    if todo:
        subprocess.run(["Rscript", str(HERE / "convert.R"), str(data / "ours_zstd"),
                        *[f"{f['key']}={f['dta']}" for f in todo]], check=True, cwd=ROOT,
                       env={**os.environ, "CONVERT_COMPRESSION": "zstd"})
    for f in files:
        f["files"] = {i: data / i / f"{f['key']}.parquet" for i in [*INPUTS, "duckdb", "ours_zstd"]}
        meta = pq.ParquetFile(f["files"]["ours"]).metadata
        names = [meta.schema.column(i).name for i in range(meta.num_columns)]
        picks = sorted({round(k * (len(names) - 1) / 4) for k in range(5)})
        f.update(rows=meta.num_rows, ncols=len(names), cols=[names[i] for i in picks],
                 skip=meta.num_rows // 2, n=min(1000, meta.num_rows - meta.num_rows // 2),
                 size={i: p.stat().st_size for i, p in f["files"].items()}, dta_size=f["dta"].stat().st_size)
    return files


def warm(path):
    with open(path, "rb") as fh:
        while fh.read(1 << 24):
            pass


def launch(cmd, report, timeout=TIMEOUT):
    report.unlink(missing_ok=True)
    load = os.getloadavg()[0]
    spawn = time.time()
    p = subprocess.Popen(["/usr/bin/time", "-l", *cmd], cwd=ROOT, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True, errors="replace", start_new_session=True)
    try:
        _, err = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, 9)
        p.communicate()
        return {"error": f"timed out after {timeout // 60} minutes"}
    rss = re.search(r"(\d+)\s+maximum resident set size", err)
    if not report.exists():
        lines = [l for l in err.splitlines() if l.strip() and not re.match(r"\s+\d+\s+\w", l)
                 and "real" not in l and "OMP:" not in l]
        return {"error": f"exit {p.returncode}: " + " | ".join(lines[-4:])[-600:]}
    r = json.loads(report.read_text())
    report.unlink()
    r.update(rss=int(rss.group(1)) / MB if rss else None, load=load, startup=r.get("loaded", spawn) - spawn)
    return r


def measure(cmd, report):
    runs = []
    for _ in range(RUNS):
        r = launch(cmd, report)
        if "error" in r:
            return {"error": r["error"], "runs": runs}
        runs.append(r)
    med = lambda k: statistics.median(r[k] for r in runs)
    return {"wall": med("wall"), "cpu": med("cpu"), "rss": med("rss"), "load": med("load"),
            "spread": (max(r["wall"] for r in runs) - min(r["wall"] for r in runs)) / med("wall") if med("wall") else 0,
            "threads": runs[0].get("threads"), "version": runs[0].get("version"),
            "bytes": runs[0].get("bytes"), "checksum": runs[0].get("checksum"), "runs": runs}


def cached(path, make):
    if path.exists():
        return json.loads(path.read_text())
    value = make()
    path.parent.mkdir(parents=True, exist_ok=True)
    if "error" not in value:
        path.write_text(json.dumps(value))
    return value


def case_cmd(*args):
    if LANG == "julia":
        return ["julia", "--project=" + str(ROOT / "bench" / "julia"), "--startup-file=no",
                str(HERE / "case.jl"), *args]
    return ["Rscript", str(HERE / "case.R"), *args]


def run_all(files, out, libs, tasks, inputs, tools):
    report = out / f"tmp-{os.getpid()}.json"
    for f in files:
        print(f"{f['family']} {f['label']}: {f['dta_size'] / MB:,.0f} MB .dta, {f['rows']:,} rows, "
              f"{f['ncols']:,} columns", flush=True)
        for task in [t for t in tasks if t in READS]:
            for inp in inputs:
                warm(f["files"][inp])
                for lib in libs:
                    cmd = case_cmd(lib, task, str(f["files"][inp]), str(report),
                                   ",".join(f["cols"]), str(f["skip"]), str(f["n"]))
                    path = out / "raw" / f["key"] / inp / f"{lib}-{task}.json"
                    t = time.time()
                    m = cached(path, lambda: measure(cmd, report))
                    if time.time() - t > 1 or "error" in m:
                        shown = m["error"][:200] if "error" in m else f"{m['wall']:.4g} s, {m['rss']:.0f} MB"
                        print(f"  {task} {inp} {lib}: {shown}", flush=True)
        for task in [t for t in tasks if t in WRITES]:
            warm(f["dta"])
            for lib in libs:
                cmd = case_cmd(lib, task, str(f["dta"]), str(report), "", "0", "0")
                path = out / "raw" / f["key"] / "dta" / f"{lib}-{task}.json"
                t = time.time()
                m = cached(path, lambda: measure(cmd, report))
                if time.time() - t > 1 or "error" in m:
                    shown = m["error"][:200] if "error" in m else f"{m['wall']:.4g} s, {m['rss']:.0f} MB"
                    print(f"  {task} {lib}: {shown}", flush=True)
        if "snappy" in tasks and LANG == "r":
            warm(f["dta"])
            cmd = ["Rscript", str(HERE / "case.R"), "ours", "snappy", str(f["dta"]), str(report), "", "0", "0"]
            path = out / "raw" / f["key"] / "dta" / "ours-snappy.json"
            t = time.time()
            m = cached(path, lambda: measure(cmd, report))
            if time.time() - t > 1 or "error" in m:
                shown = m["error"][:200] if "error" in m else f"{m['wall']:.4g} s, {m['rss']:.0f} MB"
                print(f"  snappy ours: {shown}", flush=True)
        if "tool" in tasks and LANG == "r":
            for tool in tools:
                for inp in (tool, "ours", "ours_zstd"):
                    warm(f["files"][inp])
                    cmd = [sys.executable, str(HERE / "case.py"), tool, str(f["files"][inp]), str(report)]
                    path = out / "raw" / f["key"] / inp / f"py-{tool}.json"
                    t = time.time()
                    m = cached(path, lambda: measure(cmd, report))
                    if time.time() - t > 1 or "error" in m:
                        shown = m["error"][:200] if "error" in m else f"{m['wall']:.4g} s"
                        print(f"  {tool} on {inp}: {shown}", flush=True)


# ---------------------------------------------------------------- report

def load(out, f, inp, name):
    p = out / "raw" / f["key"] / inp / f"{name}.json"
    return json.loads(p.read_text()) if p.exists() else None


def geomean(xs):
    xs = [x for x in xs if x and x > 0]
    return math.exp(sum(math.log(x) for x in xs) / len(xs)) if xs else None


def fmt_s(x):
    if x is None:
        return "–"
    return f"{x * 1000:.0f} ms" if x < 1 else f"{x:.2f} s"


def evaluate(files, out):
    """Every target, per comparison: a list of rows and a list of misses."""
    rows, misses = [], []
    for lib in LIBS[1:]:
        for task in READS + WRITES:
            for inp in (INPUTS if task in READS else ["dta"]):
                pairs = []
                for f in files:
                    o = load(out, f, inp, f"ours-{task}")
                    t = load(out, f, inp, f"{lib}-{task}")
                    if o and t:
                        pairs.append((f, o, t))
                if not pairs:
                    continue
                for fam in ("nsfg", "dhs", "synthetic"):
                    fp = [p for p in pairs if p[0]["family"] == fam]
                    if not fp:
                        continue
                    gw = geomean([p[1]["wall"] for p in fp]) / geomean([p[2]["wall"] for p in fp])
                    gr = geomean([p[1]["rss"] for p in fp]) / geomean([p[2]["rss"] for p in fp])
                    gc = geomean([p[1]["cpu"] for p in fp]) / geomean([p[2]["cpu"] for p in fp])
                    rows.append({"lib": lib, "task": task, "input": inp, "family": fam, "n": len(fp),
                                 "wall": gw, "rss": gr, "cpu": gc})
                    if fam != "synthetic":
                        if gw > 1.05:
                            misses.append(f"1 wall: {lib} {task} {inp} {fam}: geometric mean {gw:.2f}x")
                        if gr > 1.05:
                            misses.append(f"1 RSS: {lib} {task} {inp} {fam}: geometric mean {gr:.2f}x")
                for f, o, t in pairs:
                    if o["wall"] > 1.25 * t["wall"] and o["wall"] - t["wall"] >= 0.020:
                        misses.append(f"2 wall: {lib} {task} {inp} {f['label']}: {fmt_s(o['wall'])} vs {fmt_s(t['wall'])}"
                                      f" ({o['wall'] / t['wall']:.2f}x)")
                    if o["rss"] > 1.25 * t["rss"] and (o["rss"] - t["rss"]) * MB >= 16 * MIB:
                        misses.append(f"2 RSS: {lib} {task} {inp} {f['label']}: {o['rss']:.0f} vs {t['rss']:.0f} MB"
                                      f" ({o['rss'] / t['rss']:.2f}x)")
                    s = t["wall"] / o["wall"]
                    allowed = t["cpu"] * max(1.15, s)
                    if o["cpu"] > allowed:
                        misses.append(f"3 CPU: {lib} {task} {inp} {f['label']}: {o['cpu']:.3f} s vs {t['cpu']:.3f} s, "
                                      f"speedup {s:.2f} allows {allowed:.3f} s")
    tool_rows = []
    for tool in TOOLS:
        for fam, inp in [(fam, inp) for inp in ("ours", "ours_zstd") for fam in ("nsfg", "dhs", "synthetic")]:
            pairs = []
            for f in [f for f in files if f["family"] == fam]:
                own = load(out, f, tool, f"py-{tool}")
                ours = load(out, f, inp, f"py-{tool}")
                if own and ours:
                    pairs.append((f, ours, own))
            if not pairs:
                continue
            g = geomean([p[1]["wall"] for p in pairs]) / geomean([p[2]["wall"] for p in pairs])
            worst = max(pairs, key=lambda p: p[1]["wall"] / p[2]["wall"])
            tool_rows.append({"tool": tool, "family": fam, "input": inp, "n": len(pairs), "ratio": g,
                              "worst": worst[0]["label"], "worst_ratio": worst[1]["wall"] / worst[2]["wall"]})
            if inp != "ours":
                continue
            if g > 1.10:
                misses.append(f"4: {tool} on {fam}: our files take {g:.2f}x its own")
            for f, ours, own in pairs:
                if ours["wall"] > 1.10 * own["wall"] and ours["wall"] - own["wall"] >= 0.020:
                    misses.append(f"4 file: {tool} on {f['label']}: {fmt_s(ours['wall'])} vs {fmt_s(own['wall'])} "
                                  f"({ours['wall'] / own['wall']:.2f}x)")
    return rows, tool_rows, misses


def report(files, out, dest):
    rows, tool_rows, misses = evaluate(files, out)
    lines = [f"# Parquet benchmarks ({'Julia' if LANG == 'julia' else 'R'})", "",
             "Written by `bench/parquet/run.py`; see bench/RESULTS.md for what the numbers mean.", ""]
    loads = []
    versions = {}
    for f in files:
        for p in (out / "raw" / f["key"]).rglob("*.json"):
            m = json.loads(p.read_text())
            loads.append(m.get("load", 0))
            lib = p.stem.split("-")[0] if not p.stem.startswith("py-") else p.stem
            versions.setdefault(lib, (m.get("version"), m.get("threads")))
    if loads:
        lines += [f"One-minute load average before the runs: median {statistics.median(loads):.1f}, "
                  f"range {min(loads):.1f} to {max(loads):.1f}.", ""]
    lines += ["| library | version | threads |", "|---|---|---|"]
    for lib, (v, t) in sorted(versions.items()):
        lines.append(f"| {lib} | {v} | {t} |")
    lines += ["", "## Ratios, ours to theirs (geometric means)", "",
              "Below 1 is better for us. Targets 1 and 2 hold where wall and RSS are at most 1.05 on NSFG and DHS.", "",
              "| against | case | input | family | files | wall | CPU | peak RSS |", "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append(f"| {r['lib']} | {TASK_NAMES[r['task']]} | {r['input']} | {FAMILIES[r['family']]} | {r['n']} | "
                     f"{r['wall']:.2f} | {r['cpu']:.2f} | {r['rss']:.2f} |")
    lines += ["", "## Other tools reading our files", "",
              "Time on our file ÷ time on the tool's own default output (target 4: at most 1.10).", "",
              "Our files with the default codec (snappy), and with zstd 3 (`ours_zstd`, not gated).", "",
              "| tool | our codec | family | files | geometric mean | worst file | its ratio |", "|---|---|---|---|---|---|---|"]
    for r in tool_rows:
        codec = "snappy" if r["input"] == "ours" else "zstd 3"
        lines.append(f"| {r['tool']} | {codec} | {FAMILIES[r['family']]} | {r['n']} | {r['ratio']:.2f} | {r['worst']} | "
                     f"{r['worst_ratio']:.2f} |")
    lines += ["", "## Our writes: zstd 3 against snappy (the default)", "",
              "Ratios of our zstd write to our snappy write (geometric means), and how "
              + ", ".join(LIBS[1:]) + " (their defaults) compare with each (wall time).", "",
              "| family | files | wall zstd/snappy | size zstd/snappy | " + " | ".join(f"vs {l} (zstd, snappy)" for l in LIBS[1:]) + " |",
              "|---|---|---|---|" + "---|" * len(LIBS[1:])]
    for fam in ("nsfg", "dhs", "synthetic"):
        fs = [f for f in files if f["family"] == fam]
        z = [load(out, f, "dta", "ours-zstd") for f in fs]
        sn = [load(out, f, "dta", "ours-write") for f in fs]
        keep = [(f, a, b) for f, a, b in zip(fs, z, sn) if a and b]
        if not keep:
            continue
        g = lambda xs: geomean(xs)
        wall = g([a["wall"] for _, a, _ in keep]) / g([b["wall"] for _, _, b in keep])
        size = g([a["bytes"] for _, a, _ in keep]) / g([b["bytes"] for _, _, b in keep])
        cells = []
        for lib in LIBS[1:]:
            t = [load(out, f, "dta", f"{lib}-write") for f, _, _ in keep]
            if all(t):
                tw = g([x["wall"] for x in t])
                cells.append(f"{g([a['wall'] for _, a, _ in keep]) / tw:.2f}, {g([b['wall'] for _, _, b in keep]) / tw:.2f}")
            else:
                cells.append("–")
        lines.append(f"| {FAMILIES[fam]} | {len(keep)} | {wall:.2f} | {size:.2f} | " + " | ".join(cells) + " |")
    lines += ["", "## Misses", ""]
    lines += [f"- {m}" for m in misses] or ["None: every target holds."]
    lines += ["", "## Every file", ""]
    for f in files:
        lines += [f"### {f['label']}", "",
                  f"{f['rows']:,} rows, {f['ncols']:,} columns; .dta {f['dta_size'] / MB:.1f} MB; Parquet "
                  + ", ".join(f"{i} {f['size'][i] / MB:.1f} MB" for i in [*INPUTS, 'duckdb', 'ours_zstd']) + ".", "",
                  "| case | input | " + " | ".join(LIBS) + " |", "|---|---|" + "---|" * len(LIBS)]
        for task in READS + WRITES:
            for inp in (INPUTS if task in READS else ["dta"]):
                cells = []
                for lib in LIBS:
                    m = load(out, f, inp, f"{lib}-{task}")
                    cells.append(f"{fmt_s(m['wall'])} / {m['cpu']:.2f} s / {m['rss']:.0f} MB" if m else "–")
                lines.append(f"| {TASK_NAMES[task]} | {inp} | " + " | ".join(cells) + " |")
        lines.append("")
    dest.write_text("\n".join(lines) + "\n")
    print("\n".join(misses) if misses else "every target holds")


def main():
    global LIBS, LANG
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", choices=sorted(LIBS_BY_LANG), default="r")
    ap.add_argument("--family", nargs="*", default=list(FAMILIES))
    ap.add_argument("--libs", nargs="*")
    ap.add_argument("--tasks", nargs="*", default=READS + WRITES + ["tool"])
    ap.add_argument("--inputs", nargs="*", default=INPUTS)
    ap.add_argument("--tools", nargs="*", default=TOOLS)
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--data", default="/private/tmp/claude-501/pq-bench")
    ap.add_argument("--out")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--dest")
    a = ap.parse_args()
    LANG = a.lang
    LIBS = LIBS_BY_LANG[LANG]
    julia = LANG == "julia"
    a.libs = a.libs or LIBS
    a.out = a.out or "/private/tmp/claude-501/pq-bench-out" + ("-julia" if julia else "")
    a.dest = a.dest or str(ROOT / "bench" / "results" / ("parquet-julia.md" if julia else "parquet.md"))
    files = find_files(a.family)
    if a.only:
        files = [f for f in files if f["key"] in a.only or f["label"] in a.only]
    files = prepare(files, Path(a.data))
    out = Path(a.out)
    if not a.report:
        run_all(files, out, a.libs, a.tasks, a.inputs, a.tools)
    report(files, out, Path(a.dest))


if __name__ == "__main__":
    main()
