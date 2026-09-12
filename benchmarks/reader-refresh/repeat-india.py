#!/usr/bin/env python3
"""Ten alternating fresh-process India reads, dtatools only, with retained inputs."""
import argparse
import csv
import json
from pathlib import Path
import statistics

from driver_common import (add_binding_arguments, child_environment, read_cpu,
                           run_child, sha, source_binding)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("library", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--dta", type=Path, required=True)
parser.add_argument("--arrow", type=Path, required=True)
parser.add_argument("--dtatools-only", action="store_true", required=True,
                    help="required acknowledgement: no haven or Stata execution")
add_binding_arguments(parser)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
source_root = args.source_root.resolve() if args.source_root else root
for name in ("library", "output", "dta", "arrow", "data_root", "build_record"):
    setattr(args, name, getattr(args, name).resolve())
args.output.mkdir(parents=True, exist_ok=True)
environment = child_environment(args.library)
scripts = [Path(__file__), root / "benchmarks/reader-refresh/driver_common.py",
           root / "benchmarks/reader-refresh/workers/corpus.R",
           root / "benchmarks/reader-refresh/workers/benchmark-common.R",
           root / "benchmarks/reader-refresh/compare.R"]


def binding():
    value = source_binding(source_root, args.library, args.build_record, scripts)
    value["inputs"] = {name: dict(bytes=path.stat().st_size, sha256=sha(path))
                       for name, path in [("dta", args.dta), ("arrow", args.arrow)]}
    value["protocol"] = "Ten alternating fresh-process reads per reader; no warmup or added pre-read GC; default Arrow verification; result retained through exit."
    value["comparators"] = "Retain September 12 haven and Stata observations without execution."
    return value


def publish(path, rows):
    temporary = path.with_suffix(".tmp")
    with temporary.open("w") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(path)


initial = binding()
with (root / "benchmarks/reader-refresh/results-2026-09-12/read-inputs.csv").open() as stream:
    india = next(r for r in csv.DictReader(stream) if r["case"] == "india")
for name in ("dta", "arrow"):
    assert initial["inputs"][name] == dict(bytes=int(india[f"{name}_bytes"]), sha256=india[f"{name}_sha256"])
binding_file = args.output / "binding.json"
if binding_file.exists():
    assert json.loads(binding_file.read_text()) == initial, "resume binding changed"
else:
    binding_file.write_text(json.dumps(initial, indent=2) + "\n")
raw_file = args.output / "observations.csv"
observations = list(csv.DictReader(raw_file.open())) if raw_file.exists() else []
completed = {(int(r["iteration"]), r["method"]) for r in observations}
assert len(completed) == len(observations)
methods = ["read_dta", "read_arrow"]
assert all(1 <= i <= 10 and method in methods for i, method in completed)
for iteration in range(1, 11):
    order = methods if iteration % 2 else list(reversed(methods))
    for position, method in enumerate(order, 1):
        if (iteration, method) in completed:
            continue
        key = f"{iteration:02d}-{method}"
        script, arguments = (
            ("workers/corpus.R", ["dtatools", args.dta]) if method == "read_dta" else
            ("compare.R", ["memory", args.arrow]))
        print(f"START {key}, position {position}/2", flush=True)
        job, text = run_child(args.output, key, root / "benchmarks/reader-refresh" / script,
                              arguments, environment)
        fields = [line.split("\t")[1:] for line in text.splitlines()
                  if line.startswith("DTATOOLS_BENCH\t")]
        assert len(fields) == 1 and len(fields[0]) == 4 and fields[0][0] == "ok"
        _, elapsed, rows, columns = fields[0]
        assert (int(rows), int(columns)) == (724115, 5972)
        observations.append(dict(iteration=iteration, position=position, method=method,
            elapsed_seconds=float(elapsed), peak_rss_bytes=job["peak_rss_bytes"],
            rows=int(rows), columns=int(columns), **read_cpu(text),
            process_user_cpu_seconds=job["process_user_cpu_seconds"],
            process_system_cpu_seconds=job["process_system_cpu_seconds"]))
        publish(raw_file, observations)
        print(f"DONE {key}: {float(elapsed):.3f} s, {job['peak_rss_bytes']/1e9:.3f} GB peak RSS; {len(observations)}/20 reads", flush=True)
assert len(observations) == 20
assert binding() == initial, "bindings changed during measurement"
summary = []
for method in methods:
    selected = [r for r in observations if r["method"] == method]
    elapsed = [float(r["elapsed_seconds"]) for r in selected]
    memory = [float(r["peak_rss_bytes"]) / 1e9 for r in selected]
    record = dict(method=method, iterations=len(selected), median_seconds=statistics.median(elapsed),
        mean_seconds=statistics.mean(elapsed), sd_seconds=statistics.stdev(elapsed),
        min_seconds=min(elapsed), max_seconds=max(elapsed), median_peak_rss_gb=statistics.median(memory),
        min_peak_rss_gb=min(memory), max_peak_rss_gb=max(memory))
    for field in ("user_cpu_seconds", "system_cpu_seconds", "cpu_seconds"):
        values = [float(r[field]) for r in selected]
        for label, fn in [("median", statistics.median), ("min", min), ("max", max)]:
            record[f"{label}_{field}"] = fn(values)
    summary.append(record)
publish(args.output / "summary.csv", summary)
(args.output / "COMPLETE").write_text("20 successful dtatools reads; final bindings matched.\n")
print("COMPLETE: 10 successful reads per dtatools reader; final bindings match.", flush=True)
