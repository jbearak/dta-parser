"""Benchmark every .dta reader in R, Python, Julia and TypeScript, check
that they agree, and write bench/RESULTS.md with a chart per dataset family.

    python bench/run.py [--family F ...] [--file KEY ...] [--report]

Run it from the repository root with the Python that has dta_parser,
pandas and pyreadstat installed. It needs R with dtatools, haven and
readstata13; Julia with bench/julia's environment instantiated and
DtaParser built; Node with js/ built and bench/node/ installed.

Files (never committed):
  synthetic  long, wide, groups and long_114/117/119 in BENCH_DIR
             (bench/make_large.R, bench/make_release_variants.py)
  nsfg       every .dta in NSFG_DIR (bench/nsfg/make.py)
  dhs        India <year>/{wm,bh}.dta under DTA_DHS_DIR, read only (ADR 0013)

Tasks: 1 full read; 2 full read, then a pass over every value (sum of
numbers, count of missing values, total string length); 3 five named
columns; 4 a 1,000-row window from the middle; 5 metadata only; 6 write
what was read (timing the write alone).

Method: each file is read once first (page cache warm). Files over
100 MB: a fresh process per run under /usr/bin/time -l, median of five
(three over 1 GB). Smaller files: one process per task times a warm-up
call, then up to 20 calls (stopping after 60 s once three ran; a warm-up
over 60 s is the only run); peak RSS from one more fresh process with one
call. Every process has 20 minutes. A reader that times out on a file is
not run on that family's larger files.

Every measurement is cached under --out (default
/private/tmp/claude-501/bench-out); delete a file there to run it again.
--report rebuilds RESULTS.md from the cache without running anything.
"""

import argparse
import json
import math
import os
import re
import signal
import statistics
import subprocess
import sys
import time
from pathlib import Path

import dta_parser

ROOT = Path(__file__).resolve().parent.parent
BENCH = ROOT / "bench"
MB = 1e6
TIMEOUT = 20 * 60

LANGS = {
    "R": {
        "cmd": ["Rscript", "bench/cases/case.R"],
        "readers": {"ours": "dtatools", "haven": "haven", "readstata13": "readstata13"},
        "oracle": "haven",
    },
    "Python": {
        "cmd": [sys.executable, "bench/cases/case.py"],
        "readers": {"ours": "dta_parser", "pandas": "pandas", "pyreadstat": "pyreadstat"},
        "oracle": "pandas",
    },
    "Julia": {
        "cmd": ["julia", "--project=bench/julia", "bench/cases/case.jl"],
        "readers": {"ours": "DtaParser.jl", "readstattables": "ReadStatTables.jl", "statfiles": "StatFiles.jl"},
        "oracle": "readstattables",
    },
    "TypeScript": {
        "cmd": ["node", "--expose-gc", "--max-old-space-size=32768", "bench/cases/case.mjs"],
        "readers": {"ours": "@jbearak/dta-parser", "statfmt": "@irbisadm/statfmt"},
        "oracle": "statfmt",
    },
}
TASKS = {1: "full read", 2: "read + pass", 3: "5 columns", 4: "1,000 rows", 5: "metadata", 6: "write"}
# Tasks that read the whole file whatever is asked, per reader: skipped
# where that reader's full read timed out.
FULL_READS = {"statfiles": {2, 3, 4, 6}, "statfmt": {2, 3, 6}}
FAMILIES = {"synthetic": "Synthetic", "nsfg": "NSFG (public use)", "dhs": "India DHS"}


# ---------------------------------------------------------------- files

def find_files():
    files = []
    synth = Path(os.environ.get("BENCH_DIR", "/private/tmp/claude-501/bigbench"))
    for stem in ["long", "long_114", "long_117", "long_119", "wide", "groups"]:
        p = synth / f"{stem}.dta"
        if p.exists():
            files.append({"family": "synthetic", "key": stem, "path": p, "label": f"{stem}.dta"})
    nsfg = Path(os.environ.get("NSFG_DIR", "/private/tmp/claude-501/nsfg-dta"))
    for p in sorted(nsfg.glob("*.dta")):
        files.append({"family": "nsfg", "key": p.stem, "path": p, "label": p.stem})
    dhs = os.environ.get("DTA_DHS_DIR")
    if dhs:
        for year in (1992, 1998, 2006, 2016, 2021):
            for recode in ("wm", "bh"):
                p = Path(dhs) / f"India {year}" / f"{recode}.dta"
                if p.exists():
                    files.append({"family": "dhs", "key": f"dhs-{year}-{recode}", "path": p,
                                  "label": f"{year} {recode}"})
    for f in files:
        meta = dta_parser.read_meta(str(f["path"]))
        names = list(meta["columns"])
        f.update(size=f["path"].stat().st_size, nobs=meta["nobs"], nvars=len(names),
                 release=meta["release"], names=names)
        # Five columns spread over the file; a window from the middle.
        picks = sorted({round(k * (len(names) - 1) / 4) for k in range(5)})
        f["cols"] = [names[i] for i in picks]
        f["skip"] = meta["nobs"] // 2
        f["n"] = min(1000, meta["nobs"] - f["skip"])
    files.sort(key=lambda f: (list(FAMILIES).index(f["family"]), f["size"]))
    return files


# ---------------------------------------------------------------- running

def launch(lang, reader, f, tasks, runs, out, timeout=TIMEOUT):
    """One process under /usr/bin/time -l: its JSON report, plus peak RSS
    and startup (seconds from spawn until its packages were loaded)."""
    report_path = out / f"tmp-{os.getpid()}.json"
    report_path.unlink(missing_ok=True)
    cmd = ["/usr/bin/time", "-l", *LANGS[lang]["cmd"], reader, str(f["path"]), str(report_path),
           tasks, str(runs), ",".join(f["cols"]), str(f["skip"]), str(f["n"])]
    spawn = time.time()
    p = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         start_new_session=True, errors="replace")
    try:
        _, err = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.communicate()
        return {"error": f"timed out after {timeout // 60} minutes", "timeout": True}
    rss = re.search(r"(\d+)\s+maximum resident set size", err)
    result = {"rss": int(rss.group(1)) / MB if rss else None, "wall": time.time() - spawn}
    if not report_path.exists():
        lines = [l for l in err.splitlines() if l.strip() and not re.match(r"\s+\d+\s+\w", l)
                 and "real" not in l and "OMP:" not in l]
        result["error"] = f"exit {p.returncode}: " + " | ".join(lines[-3:])[-500:]
        return result
    report = json.loads(report_path.read_text())
    report_path.unlink()
    result.update(report)
    result["startup"] = report["loaded"] - spawn
    return result


def cached(path, make):
    if path.exists():
        return json.loads(path.read_text())
    value = make()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value))
    return value


def measure(lang, reader, f, task, out):
    """Times, peak RSS and startup of one task, by the size rule."""
    def task_entry(r):
        if "error" in r:
            return {"error": r["error"], "timeout": r.get("timeout", False)}
        e = r["tasks"][str(task)]
        if "error" in e:
            return {"error": e["error"]}
        if not isinstance(e["times"], list):
            e["times"] = [e["times"]]
        return e

    if f["size"] > 100 * MB:
        runs = 3 if f["size"] > 1000 * MB else 5
        m = {"mode": "fresh", "times": [], "rss": [], "startup": []}
        for _ in range(runs):
            r = launch(lang, reader, f, str(task), 1, out)
            e = task_entry(r)
            if "error" in e:
                m.update(e, rss_at_error=r.get("rss"))
                break
            m["times"] += e["times"]
            m["rss"].append(r["rss"])
            m["startup"].append(r["startup"])
            m["checksum"] = e.get("checksum")
            m["version"] = r["version"]
        return m
    r = launch(lang, reader, f, str(task), 20, out)
    e = task_entry(r)
    if "error" in e:
        return {"mode": "loop", **e}
    m = {"mode": "loop", "times": e["times"], "first": e.get("first"), "startup": [r["startup"]],
         "checksum": e.get("checksum"), "version": r["version"]}
    fresh = launch(lang, reader, f, str(task), 1, out)
    m["rss"] = [fresh["rss"]] if "error" not in task_entry(fresh) else []
    return m


def run_all(files, out):
    slow = set()  # (family, lang, reader) that timed out on a smaller file
    for f in files:
        print(f"{f['family']} {f['label']}: {f['size'] / MB:,.0f} MB", flush=True)
        with open(f["path"], "rb") as fh:  # warm the page cache
            while fh.read(1 << 24):
                pass
        for lang, spec in LANGS.items():
            for reader in spec["readers"]:
                base = out / "raw" / f["key"] / f"{lang}-{reader}"
                if (f["family"], lang, reader) in slow:
                    for task in TASKS:
                        cached(base / f"{task}.json", lambda: {"error": "not run: timed out on a smaller file",
                                                               "skipped": True})
                    continue
                full_timed_out = False
                for task in TASKS:
                    def make():
                        if full_timed_out and task in FULL_READS.get(reader, {2, 6}):
                            return {"error": "not run: the full read timed out", "skipped": True}
                        t = time.time()
                        m = measure(lang, reader, f, task, out)
                        result = m["error"][:120] if "error" in m else f"{statistics.median(m['times']):.4g} s"
                        print(f"  {lang} {reader} task {task}: {result} ({time.time() - t:.0f} s)", flush=True)
                        return m
                    m = cached(base / f"{task}.json", make)
                    if task == 1 and m.get("timeout"):
                        full_timed_out = True
                        slow.add((f["family"], lang, reader))
                if full_timed_out:
                    cached(base / "check.json", lambda: {"error": "not run: the full read timed out"})
                    continue

                def check():
                    r = launch(lang, reader, f, "check", 1, out, timeout=3 * TIMEOUT)
                    return r.get("check") or {"error": r.get("error")}
                cached(base / "check.json", check)


# ---------------------------------------------------------------- correctness

def same_storage(a, b):
    if a == b:
        return True
    # Some readers say only "str" for strN.
    return (a == "str" and b.startswith("str") and b != "strL") or (b == "str" and a.startswith("str") and a != "strL")


def compare_frames(a, b, names):
    """Disagreements between two canonical frames, as (where, kind)."""
    if a["nrows"] != b["nrows"]:
        return [("all", f"rows {a['nrows']} vs {b['nrows']}")]
    if len(a["columns"]) != len(b["columns"]):
        return [("all", f"columns {len(a['columns'])} vs {len(b['columns'])}")]
    out = []
    for i, (x, y) in enumerate(zip(a["columns"], b["columns"])):
        if x["kind"] != y["kind"]:
            out.append((names(i), f"kind {x['kind']} vs {y['kind']}"))
        elif x["hash"] != y["hash"]:
            out.append((names(i), "values"))
        elif x.get("codes") and y.get("codes") and x["codes"] != y["codes"]:
            out.append((names(i), "missing codes"))
    return out


def compare_meta(a, b, names):
    out = []
    if a.get("label") is not None and b.get("label") is not None and a["label"] != b["label"]:
        out.append(("data", "data label"))
    if len(a["columns"]) != len(b["columns"]):
        return out + [("all", f"columns {len(a['columns'])} vs {len(b['columns'])}")]
    for i, (x, y) in enumerate(zip(a["columns"], b["columns"])):
        for field in ("name", "storage", "format", "label", "value_labels"):
            u, v = x.get(field), y.get(field)
            if u is None or v is None:
                continue
            if field == "storage" and same_storage(u, v):
                continue
            if u != v:
                out.append((names(i), field.replace("_", " ")))
    return out


def error_of(check, part, who):
    if "error" in check:
        return f"{who}: {check['error']}"
    if part is None:
        return f"{who}: not checked"
    if "error" in part:
        return f"{who}: {part['error']}"
    return None


def correctness(f, lang, out):
    """For one file and language: findings as (reader, item, status, details)."""
    spec = LANGS[lang]
    checks = {r: json.loads((out / "raw" / f["key"] / f"{lang}-{r}" / "check.json").read_text())
              for r in spec["readers"]
              if (out / "raw" / f["key"] / f"{lang}-{r}" / "check.json").exists()}
    private = f["family"] == "dhs"

    def namer(selected):
        if private:  # DHS: positions only (ADR 0013)
            return lambda i: f"column {f['names'].index(selected[i]) + 1}" if selected else f"column {i + 1}"
        return lambda i: selected[i] if selected and i < len(selected) else f"column {i + 1}"

    window_names = namer(f["names"])
    five_names = namer(f["cols"])
    findings = []
    ours = checks.get("ours", {})
    for reader in spec["readers"]:
        if reader == "ours" or reader not in checks:
            continue
        other = checks[reader]
        for item, names in (("full", window_names), ("five", five_names), ("window", window_names), ("meta", window_names)):
            a, b = ours.get(item), other.get(item)
            err = error_of(ours, a, "ours") or error_of(other, b, spec["readers"][reader])
            if err:
                findings.append((reader, item, "not compared", err))
                continue
            diffs = compare_meta(a, b, names) if item == "meta" else compare_frames(a, b, names)
            findings.append((reader, item, "agree" if not diffs else "differ", diffs))
        a, b = ours.get("checksum"), other.get("checksum")
        if a and b and "error" not in a and "error" not in b:
            ok = (abs(a["sum"] - b["sum"]) <= 1e-9 * max(a["abs"], 1) and a["missing"] == b["missing"]
                  and a["length"] == b["length"])
            diffs = [] if ok else [("all", k) for k in ("sum", "missing", "length")
                                   if (abs(a[k] - b[k]) > 1e-9 * max(a["abs"], 1) if k == "sum" else a[k] != b[k])]
            findings.append((reader, "checksum", "agree" if ok else "differ", diffs))
    # Written files, re-read by the language's open-source reader, against
    # that reader's read of the source.
    oracle = checks.get(spec["oracle"], {})
    for reader in spec["readers"]:
        w = checks.get(reader, {}).get("write")
        if not w:
            continue
        if "error" in w or "full" not in oracle or "error" in oracle.get("full", {"error": 1}):
            findings.append((reader, "write", "not compared", w.get("error") or "no source read"))
            continue
        diffs = compare_frames(w["data"], oracle["full"], window_names)
        if "meta" in oracle and "error" not in oracle["meta"] and "error" not in w["meta"]:
            diffs += compare_meta(w["meta"], oracle["meta"], window_names)
        findings.append((reader, "write", "agree" if not diffs else "differ", diffs))
    return findings


# ---------------------------------------------------------------- report

def load(out, f, lang, reader, task):
    p = out / "raw" / f["key"] / f"{lang}-{reader}" / f"{task}.json"
    return json.loads(p.read_text()) if p.exists() else None


def med(xs):
    xs = [x for x in xs or [] if x is not None]
    return statistics.median(xs) if xs else None


def fmt_s(x):
    if x is None:
        return "–"
    return f"{x:.3g}" if x < 100 else f"{x:.0f}"


def fmt_mb(x):
    return "–" if x is None else f"{x:,.0f}"


def cell(m):
    if m is None:
        return "–", None, None
    if "error" in m:
        if m.get("skipped"):
            return "skipped", None, None
        if m.get("timeout"):
            return "timeout", None, None
        msg = m["error"]
        short = ("no API" if "has no" in msg else "out of memory" if re.search(r"memory|heap|OOM|alloc", msg, re.I)
                 else "error")
        return short, None, None
    t, rss = med(m["times"]), med(m["rss"])
    return f"{fmt_s(t)} s / {fmt_mb(rss)} MB", t, rss


def geomean(xs):
    xs = [x for x in xs if x and x > 0]
    return math.exp(sum(math.log(x) for x in xs) / len(xs)) if xs else None


def versions(out, files):
    found = {}
    for f in files:
        for lang, spec in LANGS.items():
            for reader in spec["readers"]:
                for task in TASKS:
                    m = load(out, f, lang, reader, task)
                    if m and m.get("version"):
                        found[(lang, reader)] = m["version"]
    return found


def runtime_versions():
    def first_line(cmd, pattern=None):
        try:
            text = subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout
        except Exception:
            return "?"
        m = re.search(pattern, text) if pattern else None
        return m.group(1) if m else text.strip().splitlines()[0] if text.strip() else "?"
    return {
        "R": first_line(["Rscript", "-e", "cat(R.version.string)"]),
        "Python": sys.version.split()[0],
        "Julia": first_line(["julia", "--version"]),
        "Node": first_line(["node", "--version"]),
    }


def machine():
    def sysctl(name):
        try:
            return subprocess.run(["sysctl", "-n", name], capture_output=True, text=True).stdout.strip()
        except Exception:
            return ""
    cpu = sysctl("machdep.cpu.brand_string") or "Apple M4 Max"
    mem = sysctl("hw.memsize")
    mem = f"{int(mem) / 2**30:.0f} GB" if mem.isdigit() else "128 GB"
    os_version = subprocess.run(["sw_vers", "-productVersion"], capture_output=True, text=True).stdout.strip()
    return f"{cpu}, {mem}, macOS {os_version}"


def family_summary(fam_files, out):
    """Per language, task and reader: geometric mean over the family's
    files of the reader's time (and RSS) over ours, and how many files
    ours was fastest (within 5%) on."""
    rows = []
    for lang, spec in LANGS.items():
        for reader, name in spec["readers"].items():
            cells = []
            for task in TASKS:
                ratios, rss_ratios, ours_t, n_fail = [], [], [], 0
                for f in fam_files:
                    m, o = load(out, f, lang, reader, task), load(out, f, lang, "ours", task)
                    _, t, rss = cell(m)
                    _, ot, orss = cell(o)
                    if t is None:
                        n_fail += m is not None and "error" in m
                        continue
                    if ot:
                        ratios.append(t / ot)
                    if rss and orss:
                        rss_ratios.append(rss / orss)
                    ours_t.append(t)
                if reader == "ours":
                    g = geomean(ours_t)
                    text = f"{fmt_s(g)} s" if g else "–"
                else:
                    g = geomean(ratios)
                    text = f"{g:.2g}×" if g else "–"
                if n_fail:
                    text += f" ({n_fail} failed)"
                cells.append(text)
            rows.append(f"| {lang} | {name} | " + " | ".join(cells) + " |")
    head = "| language | reader | " + " | ".join(f"{k}. {v}" for k, v in TASKS.items()) + " |"
    return "\n".join([head, "|---|---|" + "---|" * len(TASKS), *rows])


def family_rss_summary(fam_files, out):
    rows = []
    for lang, spec in LANGS.items():
        for reader, name in spec["readers"].items():
            cells = []
            for task in TASKS:
                vals = []
                for f in fam_files:
                    _, _, rss = cell(load(out, f, lang, reader, task))
                    _, _, orss = cell(load(out, f, lang, "ours", task))
                    if rss and orss:
                        vals.append(rss if reader == "ours" else rss / orss)
                g = geomean(vals)
                cells.append("–" if not g else f"{g:,.0f} MB" if reader == "ours" else f"{g:.2g}×")
            rows.append(f"| {lang} | {name} | " + " | ".join(cells) + " |")
    head = "| language | reader | " + " | ".join(f"{k}. {v}" for k, v in TASKS.items()) + " |"
    return "\n".join([head, "|---|---|" + "---|" * len(TASKS), *rows])


def detail_tables(fam_files, out, private):
    parts = []
    for lang, spec in LANGS.items():
        parts.append(f"## {lang}\n")
        parts.append("Each cell: median seconds / peak RSS MB. Startup (process start to packages "
                     "loaded) and first call (warm-up, including Julia's compilation) are in the last columns, for ours.\n")
        readers = list(spec["readers"])
        head = "| file | task | " + " | ".join(spec["readers"][r] for r in readers) + " | ours: startup s | ours: first call s |"
        lines = [head, "|---|---|" + "---|" * (len(readers) + 2)]
        for f in fam_files:
            for task in TASKS:
                cells = [cell(load(out, f, lang, r, task))[0] for r in readers]
                o = load(out, f, lang, "ours", task) or {}
                lines.append(f"| {f['label']} | {task} | " + " | ".join(cells)
                             + f" | {fmt_s(med(o.get('startup')))} | {fmt_s(o.get('first'))} |")
        parts.append("\n".join(lines) + "\n")
    errors = []
    for f in fam_files:
        for lang, spec in LANGS.items():
            for r in spec["readers"]:
                for task in TASKS:
                    m = load(out, f, lang, r, task)
                    if m and "error" in m and not m.get("skipped"):
                        msg = m["error"]
                        if private:  # no names or values from DHS files in messages
                            msg = re.sub(r"'[^']*'|\"[^\"]*\"|`[^`]*`", "…", msg)
                        errors.append(f"- {f['label']}, {spec['readers'][r]}, task {task}: {msg.strip()[:300]}")
    if errors:
        parts.append("## Errors\n\n" + "\n".join(sorted(set(errors))) + "\n")
    return "\n".join(parts)


def targets(files, out):
    """The plan's targets: ours fastest at task 2 on every NSFG and DHS file
    and at tasks 3-5 everywhere (5% tie band); peak RSS within 1.5x of the
    lowest. Returns (hits, misses) lists of text."""
    hits, misses = 0, []
    for f in files:
        for lang, spec in LANGS.items():
            for task in TASKS:
                speed = task in (3, 4, 5) or (task == 2 and f["family"] in ("nsfg", "dhs"))
                o = cell(load(out, f, lang, "ours", task))
                others = [cell(load(out, f, lang, r, task)) for r in spec["readers"] if r != "ours"]
                if o[1] is None:
                    if load(out, f, lang, "ours", task):
                        misses.append((lang, task, f, "speed", f"ours failed: {o[0]}"))
                    continue
                best = [c[1] for c in others if c[1] is not None]
                if speed and best:
                    if o[1] <= 1.05 * min(best):
                        hits += 1
                    else:
                        misses.append((lang, task, f, "speed", f"{fmt_s(o[1])} s vs {fmt_s(min(best))} s"))
                rss = [c[2] for c in others if c[2] is not None]
                if rss and o[2] is not None:
                    if o[2] <= 1.5 * min(rss):
                        hits += 1
                    else:
                        misses.append((lang, task, f, "memory", f"{fmt_mb(o[2])} MB vs {fmt_mb(min(rss))} MB"))
    return hits, misses


def write_report(files, out):
    import charts

    by_family = {fam: [f for f in files if f["family"] == fam] for fam in FAMILIES}
    vers = versions(out, files)
    rt = runtime_versions()
    notes = (BENCH / "results-notes.md").read_text() if (BENCH / "results-notes.md").exists() else ""
    lines = ["# Benchmark results", "",
             "Generated by `bench/run.py`; the findings section is written by hand from these numbers.", ""]
    lines += [notes.strip(), ""] if notes else []
    lines += ["## Method", "",
              f"Machine: {machine()}. R {rt['R']}, Python {rt['Python']}, {rt['Julia']}, Node {rt['Node']}.", "",
              "| language | reader | version | options |", "|---|---|---|---|"]
    options = {
        ("R", "ours"): "`read_dta()`; strings come back packed, so task 2 pays for making them",
        ("R", "haven"): "`read_dta()`; converts `%td`/`%tc` (no option not to); converted back for checks",
        ("R", "readstata13"): "`read.dta13(convert.factors = FALSE, convert.dates = FALSE)`; task 5 reads one row (no metadata-only read)",
        ("Python", "ours"): "`read_dta(dates=False)`",
        ("Python", "pandas"): "`read_stata(convert_dates=False, convert_categoricals=False)`; task 4 reads up to the window with its iterator (no row offset)",
        ("Python", "pyreadstat"): "`read_dta(disable_datetime_conversion=True)`; writes with `version=14` (release 118)",
        ("Julia", "ours"): "`read_dta()` (dates converted, as ReadStatTables does)",
        ("Julia", "readstattables"): "`readstat()`, one thread (`julia` default)",
        ("Julia", "statfiles"): "`DataFrame(load(path))`; no selection, metadata read or writer",
        ("TypeScript", "ours"): "`openDtaFile().readColumns()`; task 6 turns columns into the arrays `writeDtaFile` takes, inside the timing",
        ("TypeScript", "statfmt"): "`readDta(bytes)` on the whole file in memory; no column selection; task 5 reads one row",
    }
    for lang, spec in LANGS.items():
        for reader, name in spec["readers"].items():
            lines.append(f"| {lang} | {name} | {vers.get((lang, reader), '?')} | {options[(lang, reader)]} |")
    lines += ["", (__doc__.split("Method: ")[1].split("Every measurement")[0]).replace("\n", " ").strip(), "",
              "Times are the task alone, from inside the process after its packages loaded (task 6: the write "
              "alone, after an untimed read). Peak RSS is the whole process's, from `/usr/bin/time -l`. Node "
              "runs with `--max-old-space-size=32768` so that its default heap limit is not what fails. "
              "Each task-2 pass is the same loop in every reader of a language (sum of numbers as float64, "
              "missing count, string length in characters; JavaScript counts UTF-16 units).", "",
              "Correctness, outside the timing: each reader's result is hashed per column (numbers as float64 "
              "with missing values as a mask, missing codes where the reader keeps `.a`–`.z`, strings as UTF-8), "
              "and ours is compared with each open-source reader in its language, on everything both expose; "
              "metadata (names, storage types, formats, variable labels, value labels, data label) likewise. "
              "Each writer's file is re-read by the language's open-source reader (haven, pandas, "
              "ReadStatTables, statfmt) and compared with that reader's read of the source. Task-2 sums agree "
              "within 1e-9 × Σ|x|; counts and lengths exactly.", ""]

    hits, misses = targets(files, out)
    lines += ["## Targets", "",
              "Ours fastest within its language at task 2 on every NSFG and DHS file and at tasks 3–5 on every "
              "file (5% tie band), with peak RSS within 1.5× of the lowest.", "",
              f"{hits} checks met, {len(misses)} missed.", ""]
    if misses:
        groups = {}
        for lang, task, f, kind, text in misses:
            groups.setdefault((lang, task, kind), []).append(f"{f['label']} ({text})")
        lines += ["| language | task | kind | files missed (ours vs best other) |", "|---|---|---|---|"]
        for (lang, task, kind), items in sorted(groups.items()):
            shown = "; ".join(items[:6]) + (f"; and {len(items) - 6} more" if len(items) > 6 else "")
            lines.append(f"| {lang} | {task}. {TASKS[task]} | {kind} | {shown} |")
        lines.append("")

    (BENCH / "results").mkdir(exist_ok=True)
    (BENCH / "charts").mkdir(exist_ok=True)
    for fam, fam_files in by_family.items():
        if not fam_files:
            continue
        private = fam == "dhs"
        lines += [f"## {FAMILIES[fam]}", ""]
        lines += ["| file | release | MB | rows | variables |", "|---|---|---|---|---|"]
        for f in fam_files:
            lines.append(f"| {f['label']} | {f['release']} | {f['size'] / MB:,.0f} | {f['nobs']:,} | {f['nvars']:,} |")
        lines += ["", f"![{FAMILIES[fam]}](charts/{fam}.svg)", "",
                  "Time: for ours, the geometric mean of its seconds over the files; for the others, the "
                  "geometric mean of their time over ours (above 1× means ours is faster).", "",
                  family_summary(fam_files, out), "", "Peak RSS, the same way:", "",
                  family_rss_summary(fam_files, out), "",
                  f"Per file: [results/{fam}.md](results/{fam}.md).", ""]
        charts.write(BENCH / "charts" / f"{fam}.svg", FAMILIES[fam], chart_data(fam_files, out))
        (BENCH / "results" / f"{fam}.md").write_text(
            f"# {FAMILIES[fam]}: every file\n\nGenerated by `bench/run.py`.\n\n"
            + detail_tables(fam_files, out, private))

    lines += ["## Correctness", ""]
    lines += correctness_section(files, out)
    (BENCH / "RESULTS.md").write_text("\n".join(lines).rstrip() + "\n")


def chart_data(fam_files, out):
    """Per language and task: each other reader's geometric-mean time over ours."""
    data = {}
    for lang, spec in LANGS.items():
        for reader, name in spec["readers"].items():
            if reader == "ours":
                continue
            for task in TASKS:
                ratios = []
                for f in fam_files:
                    _, t, _ = cell(load(out, f, lang, reader, task))
                    _, ot, _ = cell(load(out, f, lang, "ours", task))
                    if t and ot:
                        ratios.append(t / ot)
                data.setdefault(lang, {}).setdefault(name, {})[task] = geomean(ratios)
    return data


def correctness_section(files, out):
    lines = []
    for fam in FAMILIES:
        fam_files = [f for f in files if f["family"] == fam]
        if not fam_files:
            continue
        tally, details = {}, []
        for f in fam_files:
            for lang, spec in LANGS.items():
                for reader, item, status, info in correctness(f, lang, out):
                    key = (lang, spec["readers"][reader], item)
                    tally.setdefault(key, {"agree": 0, "differ": 0, "not compared": 0})[status] += 1
                    if status == "differ":
                        kinds = {}
                        for where, kind in info:
                            kinds.setdefault(kind, []).append(where)
                        text = "; ".join(f"{k}: {', '.join(v[:5])}{' …' if len(v) > 5 else ''} ({len(v)})"
                                         for k, v in kinds.items())
                        details.append(f"- {f['label']}, {lang}, {spec['readers'][reader]}, {item}: {text}")
                    elif status == "not compared":
                        msg = info if isinstance(info, str) else ""
                        if fam == "dhs":
                            msg = re.sub(r"'[^']*'|\"[^\"]*\"|`[^`]*`", "…", msg)
                        details.append(f"- {f['label']}, {lang}, {spec['readers'][reader]}, {item}: not compared ({msg.strip()[:200]})")
        lines += [f"### {FAMILIES[fam]}", "",
                  "Ours against each reader (write: each writer's file re-read by the open-source reader). "
                  "Counts are files.", "",
                  "| language | other reader | compared | agree | differ | not compared |", "|---|---|---|---|---|---|"]
        for (lang, name, item), c in tally.items():
            lines.append(f"| {lang} | {name} | {item} | {c['agree']} | {c['differ']} | {c['not compared']} |")
        lines.append("")
        if details:
            if fam == "dhs":
                lines.append("DHS disagreements by column position and kind only (ADR 0013).\n")
            lines += details + [""]
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--family", nargs="*", choices=list(FAMILIES))
    ap.add_argument("--file", nargs="*", help="file keys, such as long or 2002_Male")
    ap.add_argument("--out", default="/private/tmp/claude-501/bench-out")
    ap.add_argument("--report", action="store_true", help="only rebuild RESULTS.md from the cache")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    files = find_files()
    chosen = [f for f in files if (not args.family or f["family"] in args.family)
              and (not args.file or f["key"] in args.file)]
    if not args.report:
        start = time.time()
        run_all(chosen, out)
        print(f"done in {(time.time() - start) / 3600:.2f} h", flush=True)
    sys.path.insert(0, str(BENCH))
    write_report(files, out)


if __name__ == "__main__":
    main()
