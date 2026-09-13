#!/usr/bin/env python3
"""Compare two installed readers in alternating fresh and warm processes."""
import argparse
import csv
import json
import math
from pathlib import Path
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "benchmarks/reader-refresh"))
from driver_common import child_environment, read_cpu, require, run_child, sha, source_binding


def write_table(path, rows):
    """Persist all completed observations without rounding their clocks."""
    with path.open("w") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main():
    """Bind both installations and inputs, then alternate their read order."""
    parser = argparse.ArgumentParser(description=__doc__)
    for variant in ("baseline", "candidate"):
        for field in ("source", "library", "build"):
            parser.add_argument(f"--{variant}-{field}", type=Path, required=True)
    parser.add_argument("--cases", type=Path, required=True,
                        help="JSON list: id, path, reader, rows, columns, optional warm_calls")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repetitions", type=int, default=10)
    args = parser.parse_args()
    for variant in ("baseline", "candidate"):
        for field in ("source", "library", "build"):
            name = variant + "_" + field
            setattr(args, name, getattr(args, name).resolve())
    args.cases = args.cases.resolve()
    args.output = args.output.resolve()
    require(args.repetitions > 0 and args.repetitions % 2 == 0,
            "Use a positive even repetition count to balance order")
    cases = json.loads(args.cases.read_text())
    require(isinstance(cases, list) and len(cases) > 0, "Cases must be a nonempty list")
    require(len({c["id"] for c in cases}) == len(cases), "Duplicate case IDs")
    for case in cases:
        require(case["reader"] in ("read_dta", "read_arrow"), "Unknown reader")
        require(Path(case["path"]).is_absolute(), "Case paths must be absolute")
        require(all(type(case[field]) is int and case[field] >= 0 for field in ("rows", "columns")),
                "Case dimensions must be non-negative integers")
        require(type(case.get("warm_calls", 0)) is int and case.get("warm_calls", 0) >= 0,
                "warm_calls must be a non-negative integer")
    variants = ("baseline", "candidate")
    common = ROOT / "benchmarks/reader-refresh"
    scripts = [Path(__file__), Path(__file__).with_name("warm.R"), common / "driver_common.py",
               common / "workers/corpus.R", common / "workers/benchmark-common.R", common / "compare.R"]

    def binding():
        """Identify measured source, workers, installed files and dataset bytes."""
        value = {variant: source_binding(getattr(args, variant + "_source"),
                 getattr(args, variant + "_library"), getattr(args, variant + "_build"), scripts)
                 for variant in variants}
        value["cases_sha256"] = sha(args.cases)
        value["inputs"] = {c["id"]: dict(bytes=Path(c["path"]).stat().st_size,
                           sha256=sha(c["path"]), reader=c["reader"], rows=c["rows"],
                           columns=c["columns"], warm_calls=c.get("warm_calls", 0)) for c in cases}
        value["repetitions"] = args.repetitions
        return value

    initial = binding()
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / "binding.json").write_text(json.dumps(initial, indent=2) + "\n")
    observations = []
    for index, case in enumerate(cases):
        for mode in (["fresh", "warm"] if case.get("warm_calls", 0) else ["fresh"]):
            for repetition in range(args.repetitions):
                order = variants if (repetition + index) % 2 == 0 else tuple(reversed(variants))
                for position, variant in enumerate(order, 1):
                    if mode == "warm":
                        worker = Path(__file__).with_name("warm.R")
                        arguments = [case["reader"], case["path"], case["warm_calls"]]
                    elif case["reader"] == "read_dta":
                        worker, arguments = common / "workers/corpus.R", ["dtatools", case["path"]]
                    else:
                        worker, arguments = common / "compare.R", ["memory", case["path"]]
                    key = f"{index:02d}-{mode}-{repetition:02d}-{variant}"
                    job, text = run_child(args.output, key, worker, arguments,
                                          child_environment(getattr(args, variant + "_library")))
                    markers = [line.split("\t")[1:] for line in text.splitlines()
                               if line.startswith("DTATOOLS_BENCH\t")]
                    require(len(markers) == 1 and len(markers[0]) == 4, "Invalid result marker")
                    status, elapsed, rows, columns = markers[0]
                    require(status == "ok" and (int(rows), int(columns)) ==
                            (case["rows"], case["columns"]), "Read failed or returned wrong dimensions")
                    require(math.isfinite(float(elapsed)) and float(elapsed) >= 0,
                            "Invalid elapsed time")
                    observations.append(dict(id=case["id"], reader=case["reader"], mode=mode,
                        repetition=repetition + 1, position=position, variant=variant,
                        elapsed_seconds=float(elapsed), **read_cpu(text),
                        peak_rss_bytes=job["peak_rss_bytes"],
                        process_cpu_seconds=job["process_user_cpu_seconds"] + job["process_system_cpu_seconds"]))
                    write_table(args.output / "observations.csv", observations)
            print(f"Completed {case['id']} {mode}", flush=True)
    require(binding() == initial, "Source, installation or inputs changed during measurement")
    summaries = []
    for key in dict.fromkeys((r["id"], r["reader"], r["mode"], r["variant"]) for r in observations):
        selected = [r for r in observations if (r["id"], r["reader"], r["mode"], r["variant"]) == key]
        row = dict(zip(("id", "reader", "mode", "variant"), key))
        row["repetitions"] = len(selected)
        for field in ("elapsed_seconds", "cpu_seconds", "peak_rss_bytes", "process_cpu_seconds"):
            for label, fn in (("median", statistics.median), ("min", min), ("max", max)):
                row[f"{label}_{field}"] = fn(r[field] for r in selected)
        summaries.append(row)
    write_table(args.output / "summary.csv", summaries)
    (args.output / "COMPLETE").write_text("All reads succeeded; final bindings matched.\n")


if __name__ == "__main__":
    main()
