"""Paired isolated I/O and merge observations. No competitor timings."""
import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import random
import statistics
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("configuration", type=Path)
parser.add_argument("phase", choices=("reads", "writes", "merges"))
parser.add_argument("--pairs", type=int)
arguments = parser.parse_args()
config = json.loads(arguments.configuration.read_text())
root = Path(config["root"]).resolve()
directory = Path(config["directory"]).resolve()
worker = Path(__file__).with_name("worker.R")
libraries = {name: Path(config[name]).resolve() for name in ("baseline", "candidate")}
for name, path in libraries.items():
    if not (path / "dtatools/libs/dtatools.so").is_file():
        raise RuntimeError(f"Missing {name} library")
if libraries["baseline"] == libraries["candidate"]:
    raise RuntimeError("Libraries must differ")
logs = directory / (arguments.phase + "-logs")
logs.mkdir(exist_ok=False)
outputs = directory / "outputs"
outputs.mkdir(exist_ok=True)

cases = []
if arguments.phase == "reads":
    for fixture in config["reads"]:
        for method, suffix in (("read_dta", "dta"), ("read_arrow", "arrow")):
            cases.append(dict(id=f'{fixture["id"]}-{method}', method=method,
                command=[str(root / "benchmarks/reader-corpus/worker.R"), method, fixture[suffix]],
                rows=fixture["rows"], columns=fixture["columns"]))
elif arguments.phase == "writes":
    for fixture in config["writes"]:
        for method in ("save_dta", "save_arrow"):
            cases.append(dict(id=f'{fixture["id"]}-{method}', method=method,
                kind=fixture["kind"], input=str(fixture["input"]),
                rows=fixture["rows"], columns=40))
else:
    for kind in ("typed", "ordinary", "one-column"):
        for direction in (("1:m",) if kind == "one-column" else ("1:m", "m:1")):
            cases.append(dict(id=f'merge-{kind}-{direction.replace(":", "")}', method="merge",
                command=[str(worker), "merge", kind, config["merge_directory"], direction],
                rows=440044, columns=3 if kind == "one-column" else 201))
pairs = arguments.pairs or (8 if arguments.phase == "writes" else 10)
if pairs < 1:
    raise RuntimeError("Positive pair count required")

def environment(library):
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("DTATOOLS_EXPERIMENT_", "DTA_READ_PERF_"))}
    env.update(R_LIBS=str(library), DTATOOLS_BENCH_LIB=str(library), DTATOOLS_REVIEW_ROOT=str(root))
    return env

def run(case, variant, pair, position):
    key = f'{pair:02d}-{position:02d}-{case["id"]}-{variant}'
    log = logs / (key + ".log")
    output = None
    if case["method"].startswith("save_"):
        extension = ".dta" if case["method"] == "save_dta" else ".arrow"
        output = outputs / (key + extension)
        if output.exists():
            raise RuntimeError("Output already exists")
        command = [str(worker), case["method"], case["kind"], case["input"], str(output)]
    else:
        command = case["command"]
    command = ["Rscript", "--vanilla"] + command
    started = time.monotonic()
    with log.open("w") as stream:
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
            env=environment(libraries[variant]), cwd=root)
        _, status, usage = os.wait4(process.pid, 0)
        process.returncode = os.waitstatus_to_exitcode(status)
    duration = time.monotonic() - started
    if process.returncode:
        raise RuntimeError(f"Worker failed: {log}")
    lines = log.read_text().splitlines()
    if arguments.phase == "reads":
        clocks = [line.split("\t") for line in lines if line.startswith("DTATOOLS_BENCH\t")]
        cpus = [line.split("\t") for line in lines if line.startswith("DTATOOLS_CPU\t")]
        if len(clocks) != 1 or len(cpus) != 1 or clocks[0][1] != "ok":
            raise RuntimeError(f"Bad reader record: {log}")
        wall, rows, columns = map(float, clocks[0][2:])
        user, system = map(float, cpus[0][1:])
        size = None
    else:
        records = [line.split("\t") for line in lines if line.startswith("RESULT\t")]
        if len(records) != 1:
            raise RuntimeError(f"Bad worker record: {log}")
        record = records[0]
        wall, user, system, rows, columns = map(float, record[3:8])
        size = None if record[8] == "NA" else int(record[8])
    if rows != case["rows"] or columns != case["columns"] or any(
            not math.isfinite(x) or x < 0 for x in (wall, user, system)):
        raise RuntimeError(f"Invalid clocks or shape: {log}")
    row = dict(case=case["id"], method=case["method"], variant=variant,
        pair=pair, position=position, call_wall=wall, call_user=user, call_system=system,
        call_cpu=user + system, process_wall=duration, process_user=usage.ru_utime,
        process_system=usage.ru_stime, process_cpu=usage.ru_utime + usage.ru_stime,
        maxrss_bytes=usage.ru_maxrss, rows=int(rows), columns=int(columns),
        output_bytes=size, output=str(output) if output else None, command=command,
        log_sha256=hashlib.sha256(log.read_bytes()).hexdigest())
    with (directory / (arguments.phase + "-raw.jsonl")).open("a") as stream:
        stream.write(json.dumps(row, sort_keys=True) + "\n")
    print(f'{key} wall={wall:.6f} cpu={user + system:.6f}', flush=True)
    return row

rows = []
latest_outputs = {}
for pair in range(1, pairs + 1):
    offset = (pair - 1) % len(cases)
    ordered = cases[offset:] + cases[:offset]
    for position, case in enumerate(ordered, 1):
        variants = ("baseline", "candidate") if pair % 2 else ("candidate", "baseline")
        for variant in variants:
            row = run(case, variant, pair, position)
            rows.append(row)
            if row["output"]:
                key = (case["id"], variant)
                previous = latest_outputs.get(key)
                if previous and previous["output_bytes"] != row["output_bytes"]:
                    raise RuntimeError("Writer output size changed between repetitions")
                # Keep the first and final sample for full readback qualification.
                # Intermediate private outputs have their dimensions/size recorded.
                if previous and previous["pair"] > 1:
                    old_output = Path(previous["output"])
                    if old_output.parent != outputs or not old_output.is_file():
                        raise RuntimeError("Unexpected intermediate output path")
                    old_output.unlink()
                latest_outputs[key] = row

summary = []
random_source = random.Random(20261001)
for case in cases:
    for metric in ("call_wall", "call_cpu", "process_wall", "process_cpu", "maxrss_bytes"):
        old = {r["pair"]: r[metric] for r in rows if r["case"] == case["id"] and r["variant"] == "baseline"}
        new = {r["pair"]: r[metric] for r in rows if r["case"] == case["id"] and r["variant"] == "candidate"}
        ratios = [new[pair] / old[pair] for pair in old if old[pair] > 0]
        bootstrap = sorted(statistics.median(random_source.choices(ratios, k=len(ratios)))
                           for _ in range(10000)) if ratios else []
        summary.append(dict(case=case["id"], metric=metric, pairs=len(old),
            baseline_median=statistics.median(old.values()), candidate_median=statistics.median(new.values()),
            paired_ratio_median=statistics.median(ratios) if ratios else None,
            paired_ratio_bootstrap95_low=bootstrap[249] if bootstrap else None,
            paired_ratio_bootstrap95_high=bootstrap[9749] if bootstrap else None,
            baseline_min=min(old.values()), baseline_max=max(old.values()),
            candidate_min=min(new.values()), candidate_max=max(new.values())))
with (directory / (arguments.phase + "-summary.csv")).open("w", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=list(summary[0]))
    writer.writeheader()
    writer.writerows(summary)
print(json.dumps(summary, indent=2))
