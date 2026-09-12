#!/usr/bin/env python3
"""Supplemental dtatools-only shape, metadata and fresh-process RSS coverage."""
import argparse
import csv
import json
from pathlib import Path
import statistics

from driver_common import add_binding_arguments, child_environment, run_child, sha, source_binding

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("library", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--phase", choices=["coverage", "fresh"], required=True)
parser.add_argument("--dibble-fixtures", type=Path,
                    default=Path("/private/tmp/direct-dibble-readers/run-01/fixtures"))
add_binding_arguments(parser)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
source = args.source_root.resolve() if args.source_root else root
base = Path(__file__).resolve().parent
args.library = args.library.resolve()
args.output = args.output.resolve()
data = args.data_root.resolve()
args.output.mkdir(parents=True, exist_ok=False)
env = child_environment(args.library)
scripts = [Path(__file__), base / "driver_common.py", *sorted((base / "workers").glob("*.R"))]
cases = []

def table(path, delimiter="\t"):
    with path.open() as stream:
        return list(csv.DictReader(stream, delimiter=delimiter))

def add(name, path, **fields):
    cases.append(dict(name=name, path=str(Path(path).resolve()), **fields))

synthetic = table(data / "large-scale/datasets.tsv")
for row in synthetic:
    assert sha(row["path"]) == row["sha256"]
    name = "synthetic-" + row["dataset"]
    if args.phase == "fresh":
        add(name + "-dta", row["path"], format="dta", rows=int(row["rows"]), columns=40)
        for verify in (True, False):
            add(name + "-arrow-" + ("verify" if verify else "noverify"),
                data / ("arrow-interchange/" + name + ".arrow"), format="arrow",
                verify=verify, rows=int(row["rows"]), columns=40)
    else:
        selection = ["id", "income", "age", "region", "interview_date", "case_code", "occupation", "description"]
        for workload, columns in [("full", None), ("projected-eight", selection)]:
            add(name + "-" + workload, row["path"], format="dta", rows=int(row["rows"]),
                columns=40 if columns is None else 8, selection=columns, mode="warm", iterations=7)

if args.phase == "fresh":
    add("india-arrow-noverify", data / "arrow-interchange/india-2021-wm.arrow",
        format="arrow", verify=False, rows=724115, columns=5972)
    for run, names in [("run-full-20260828T202309Z", ["tall", "wide", "tall-wide"]),
                       ("run-india-20260828T203157Z", ["india-2021-wm"])]:
        for name in names:
            directory = data / "projection-introspection" / run
            names_dir = directory / name if name == "india-2021-wm" else directory
            selected = (names_dir / "present.txt").read_text().split()
            add("projection-" + name, directory / name / "input.dta", format="dta",
                selection=selected, rows={"tall":500000, "wide":50000, "tall-wide":250000, "india-2021-wm":724115}[name],
                columns=len(selected))
    for case in cases:
        case.update(mode="fresh", iterations=1, repeats=3)
else:
    # Reuse the exact 15 inputs from the direct-dibble experiment. No writers run.
    reference = json.loads((root / "benchmarks/r-reader-dibble/results-2026-09-11/environment.json").read_text())
    for row in table(args.dibble_fixtures / "fixtures.csv", ","):
        path = args.dibble_fixtures / row["file"]
        assert sha(path) == reference["fixtures"][row["file"]], row["file"]
        add("dibble-" + row["case"] + "-" + row["format"], path, format=row["format"],
            rows=int(row["rows"]), columns=int(row["columns"]), mode="dibble", repeats=3,
            oracle=str(args.dibble_fixtures.parent / ("validate-candidate-" + row["file"] + ".rds")))
    for name, filename in [("modern-all-types", "all_types_v118.dta"), ("wide", "wide_v118.dta"),
                           ("strl", "strl_test_v118.dta"), ("legacy", "all_types_v115.dta")]:
        path = root / "tests/fixtures/dta" / filename
        for workload, extra in [("full", {}), ("window", dict(select_first_two=True, skip=1, n_max=16)),
                                ("metadata-only", dict(n_max=0))]:
            add("micro-" + name + "-" + workload, path, format="dta", mode="micro",
                iterations=1, batch=100, **extra)
    # Explicit metadata-only large cases; these do not stand in for data reads.
    india = next(r for r in table(data / "r-corpus-performance/20260824T142432Z/inventory.tsv") if r["id"] == "DHS-0259")
    add("metadata-india", Path("/opt/aww_cache") / india["relative_path"], format="dta",
        rows=0, columns=5972, mode="micro", iterations=1, batch=100, n_max=0)


def binding():
    result = source_binding(source, args.library, args.build_record, scripts)
    result["inputs"] = {case["name"]: dict(bytes=Path(case["path"]).stat().st_size,
                                         sha256=sha(case["path"])) for case in cases}
    result["oracles"] = {case["name"]: sha(case["oracle"]) for case in cases if "oracle" in case}
    result["cases"] = cases
    result["phase"] = args.phase
    return result

initial = binding()
(args.output / "binding.json").write_text(json.dumps(initial, indent=2) + "\n")
qualifications = {}
# Qualification for every case finishes before any timed child is launched.
for case in cases:
    key = case["name"]
    if case["mode"] == "dibble":
        output = args.output / (key + "-qualified.rds")
        run_child(args.output, key + "-qualify", base / "workers/dibble.R",
                  ["validate", args.library, case["path"], output], env)
        run_child(args.output, key + "-compare", base / "workers/dibble.R",
                  ["compare", args.library, case["oracle"], output], env)
        qualifications[key] = dict(snapshot_sha256=sha(output), rows=case["rows"], columns=case["columns"],
                                   retained_snapshot_equal=True)
    else:
        config = args.output / (key + "-qualify.json")
        config.write_text(json.dumps(dict(case, mode="qualify")) + "\n")
        output = args.output / (key + "-qualified.json")
        run_child(args.output, key + "-qualify", base / "workers/case.R", [config, output], env)
        qualifications[key] = json.loads(output.read_text())
(args.output / "qualifications.json").write_text(json.dumps(qualifications, indent=2) + "\n")
observations = []
for case in cases:
    key = case["name"]
    for repeat in range(1, case.get("repeats", 1) + 1):
        modes = ["time", "memory"] if case["mode"] == "dibble" else [case["mode"]]
        for mode in modes:
            job_key = f"{key}-{repeat}-{mode}"
            output = args.output / (job_key + ".csv")
            if case["mode"] == "dibble":
                job, _ = run_child(args.output, job_key, base / "workers/dibble.R",
                                   [mode, args.library, case["path"], output], env)
            else:
                config = args.output / (job_key + ".json")
                expected = qualifications[key]
                config.write_text(json.dumps(dict(case, rows=expected["rows"], columns=expected["columns"])) + "\n")
                job, _ = run_child(args.output, job_key, base / "workers/case.R", [config, output], env)
            for row in table(output, ","):
                count = int(row.get("iterations", 1)) if mode == "time" else 1
                record = dict(case=key, mode=mode, repeat=repeat,
                    sample=int(row.get("sample", row.get("iteration", 1))),
                    calls=int(row.get("iterations", row.get("calls", 1))),
                    rows=case.get("rows", qualifications[key]["rows"]),
                    columns=case.get("columns", qualifications[key]["columns"]),
                    peak_rss_bytes=job["peak_rss_bytes"],
                    process_user_cpu_seconds=job["process_user_cpu_seconds"],
                    process_system_cpu_seconds=job["process_system_cpu_seconds"])
                for field in ("elapsed_seconds", "user_cpu_seconds", "system_cpu_seconds", "cpu_seconds"):
                    record[field] = float(row[field]) / count if field in row else ""
                observations.append(record)
            print("completed", job_key, flush=True)
assert binding() == initial, "final bindings changed"
with (args.output / "observations.csv").open("w") as stream:
    writer = csv.DictWriter(stream, fieldnames=list(observations[0]));writer.writeheader();writer.writerows(observations)
summary = []
for case, mode in sorted(set((r["case"],r["mode"]) for r in observations)):
    selected = [r for r in observations if r["case"] == case and r["mode"] == mode]
    record = dict(case=case, mode=mode, count=len(selected))
    for field in ("elapsed_seconds", "user_cpu_seconds", "system_cpu_seconds", "cpu_seconds", "peak_rss_bytes"):
        values = [float(r[field]) for r in selected if r[field] != ""]
        for label, fn in [("median",statistics.median),("min",min),("max",max)]:
            record[label+"_"+field] = fn(values) if values else ""
    summary.append(record)
with (args.output / "summary.csv").open("w") as stream:
    writer=csv.DictWriter(stream, fieldnames=list(summary[0]));writer.writeheader();writer.writerows(summary)
(args.output / "COMPLETE").write_text("Supplemental reader cases completed; final bindings matched.\n")
