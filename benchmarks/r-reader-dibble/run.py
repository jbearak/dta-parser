#!/usr/bin/env python3
"""Compare installed readers in serial R children; retain raw time and RSS."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys
import time

parser = argparse.ArgumentParser()
parser.add_argument("baseline", type=Path)
parser.add_argument("candidate", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=False)
worker = Path(__file__).with_name("worker.R").resolve()
rscript = shutil.which("Rscript")
libraries = {k: str(getattr(args, k).resolve()) for k in ("baseline", "candidate")}
jobs = []


def child(mode, build, source, output):
    command = [rscript, "--vanilla", str(worker), mode, libraries[build], str(source), str(output)]
    log = output.with_suffix(".log")
    with log.open("wb") as stream:
        actions = [(os.POSIX_SPAWN_DUP2, stream.fileno(), 1),
                   (os.POSIX_SPAWN_DUP2, stream.fileno(), 2)]
        start = time.time()
        pid = os.posix_spawn(rscript, command, os.environ.copy(), file_actions=actions)
        _, status, usage = os.wait4(pid, 0)
    code = os.waitstatus_to_exitcode(status)
    rss = usage.ru_maxrss * (1 if sys.platform == "darwin" else 1024)
    jobs.append(dict(command=command, exit_code=code, peak_rss_bytes=rss,
                     start=start, duration=time.time() - start))
    (args.output / "jobs.json").write_text(json.dumps(jobs, indent=2) + "\n")
    if code:
        raise RuntimeError(f"{mode} {build} failed: {log.read_text()}")
    return rss


fixtures = args.output / "fixtures"
child("generate", "baseline", fixtures, args.output / "generate.csv")
cases = list(csv.DictReader((fixtures / "fixtures.csv").open()))
metadata = dict(platform=platform.platform(), machine=platform.machine(),
                processors=os.cpu_count(), python=sys.version, libraries=libraries,
                r=subprocess.check_output([rscript, "--vanilla", "-e",
                    'cat(R.version.string); print(sapply(c("dtatools", "tibble", "vctrs", "rlang"), '
                    'function(x) as.character(packageVersion(x))))'], text=True),
                sources={p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in (worker, Path(__file__))},
                fixtures={c["file"]: hashlib.sha256((fixtures / c["file"]).read_bytes()).hexdigest()
                          for c in cases})
(args.output / "environment.json").write_text(json.dumps(metadata, indent=2) + "\n")

# Validation is isolated from all measured children. Compare serialized values,
# classes, labels and other attributes, with only top-level attribute order sorted.
for case in cases:
    key = case["file"]
    snapshots = []
    for build in libraries:
        output = args.output / f"validate-{build}-{key}.rds"
        child("validate", build, fixtures / key, output)
        snapshots.append(output)
    subprocess.run([rscript, "--vanilla", "-e",
                    'a <- commandArgs(TRUE); stopifnot(identical(readRDS(a[1]), readRDS(a[2])))',
                    *map(str, snapshots)], check=True)

records = []
for repeat in range(1, 4):
    for i, case in enumerate(cases):
        builds = list(libraries)
        if (i + repeat) % 2 == 0:
            builds.reverse()
        for mode in ("time", "memory"):
            for build in builds:
                output = args.output / f"{mode}-{repeat}-{build}-{case['file']}.csv"
                rss = child(mode, build, fixtures / case["file"], output)
                rows = list(csv.DictReader(output.open()))
                if mode == "memory":
                    assert rows[0]["rows"] == case["rows"] and rows[0]["columns"] == case["columns"]
                for row in rows:
                    records.append(dict(case=case["case"], format=case["format"],
                        mode=mode, build=build, repeat=repeat,
                        sample=int(row.get("sample", 1)), iterations=int(row.get("iterations", 1)),
                        elapsed_seconds=row.get("elapsed_seconds", ""),
                        milliseconds=row.get("milliseconds", ""),
                        peak_rss_bytes=rss if mode == "memory" else ""))
        print(f"repeat {repeat}: {case['file']}", flush=True)


def write_csv(path, rows):
    with path.open("w") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)


write_csv(args.output / "observations.csv", records)
summary = []
for case in cases:
    item = {k: case[k] for k in ("case", "format", "rows", "columns", "file_bytes")}
    for mode, field, label in (("time", "milliseconds", "ms"), ("memory", "peak_rss_bytes", "rss_bytes")):
        for build in libraries:
            values = [float(r[field]) for r in records if r["case"] == case["case"]
                      and r["format"] == case["format"] and r["mode"] == mode and r["build"] == build]
            for stat, fn in (("median", statistics.median), ("min", min), ("max", max)):
                item[f"{build}_{label}_{stat}"] = fn(values)
        before, after = item[f"baseline_{label}_median"], item[f"candidate_{label}_median"]
        item[f"{label}_change"] = after - before
        item[f"{label}_percent_change"] = 100 * (after / before - 1)
    summary.append(item)
write_csv(args.output / "summary.csv", summary)
print(json.dumps(summary, indent=2))
