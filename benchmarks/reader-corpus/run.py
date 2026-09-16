#!/usr/bin/env python3
"""Qualify Arrow copies, then measure full corpus reads in fresh R processes."""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import platform
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "benchmarks/reader-refresh"))
from driver_common import child_environment, read_cpu, require, run_child, sha, source_binding


def table(file):
    with file.open() as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def write_json(file, value):
    file.write_text(json.dumps(value, indent=2) + "\n")


def csv_file(file, rows):
    require(bool(rows), "cannot publish an empty table")
    with file.open("w") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def common_rows(inventory, archived):
    previous = {(row["id"], row["reader"]): row for row in archived}
    return [row for row in inventory if
            all(previous[(row["id"], method)]["status"] == "ok"
                for method in ("dtaparser", "haven", "stata")) and
            len({(previous[(row["id"], method)]["rows"],
                  previous[(row["id"], method)]["columns"])
                 for method in ("dtaparser", "haven", "stata")}) == 1]


def validate_clock(value):
    require(type(value) in (int, float) and math.isfinite(value) and value >= 0,
            "invalid worker clock")
    return value


def parse_read(log, method, qualification):
    """Validate base-R output before retaining a read observation."""
    markers = [line.split("\t") for line in log.splitlines()
               if line.startswith("DTATOOLS_BENCH\t")]
    require(len(markers) == 1 and len(markers[0]) == 5,
            "missing, duplicate or malformed read marker")
    _, status, elapsed, rows, columns = markers[0]
    expected = qualification["status"]
    if expected == "dta_error":
        require(method == "read_dta" and status == "error" and
                rows == columns == "NA", "expected malformed DTA error")
        result = dict(status="dta_error")
    else:
        require(expected == "ok" and status == "ok", "qualified input failed to read")
        require((int(rows), int(columns)) ==
                (qualification["rows"], qualification["columns"]),
                "timed read dimensions differ from qualification")
        result = dict(status="ok", rows=int(rows), columns=int(columns))
    result.update(elapsed_seconds=validate_clock(float(elapsed)),
                  read_cpu_seconds=read_cpu(log)["cpu_seconds"])
    return result


def aggregate(inventory, common_ids, observations, archived):
    """Use the frozen comparable set for both new readers and old comparators."""
    expected = {(row["id"], method) for row in inventory if row["id"] in common_ids
                for method in ("read_dta", "read_arrow")}
    selected = [row for row in observations if row["id"] in common_ids]
    require(len(selected) == len(expected) and
            {(row["id"], row["method"]) for row in selected} == expected,
            "missing or duplicate common-file measurement")
    require(all(row["status"] == "ok" for row in selected), "common-file read failed")
    result = []
    for corpus in ("DHS", "MICS", "NSFG"):
        files = [row for row in inventory if row["corpus"] == corpus and row["id"] in common_ids]
        if not files:
            continue
        ids = {row["id"] for row in files}
        for method in ("read_dta", "read_arrow", "haven", "stata"):
            rows = ([row for row in selected if row["id"] in ids and row["method"] == method]
                    if method.startswith("read_") else
                    [row for row in archived if row["id"] in ids and row["reader"] == method])
            require(len(rows) == len(ids), "incomplete corpus aggregate")
            new = method.startswith("read_")
            result.append(dict(corpus=corpus, method=method, files=len(files),
                dta_bytes=sum(int(row["bytes"]) for row in files),
                wall_seconds=sum(validate_clock(float(row["elapsed_seconds"])) for row in rows),
                read_cpu_seconds=sum(row["read_cpu_seconds"] for row in rows) if new else "",
                process_cpu_seconds=sum(row["process_cpu_seconds"] for row in rows) if new else "",
                max_peak_rss_bytes=max(int(row["peak_rss_bytes"] if new else row["rss_bytes"]) for row in rows),
                measurement_date=datetime.now(timezone.utc).date().isoformat() if new else "2026-08-24"))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ("library", "build-record", "source-root", "data-root", "output"):
        parser.add_argument("--" + arg, type=Path, required=True)
    parser.add_argument("--cache", type=Path, default=Path("/opt/aww_cache"))
    parser.add_argument("--smoke", action="store_true", help="subset check; not a corpus result")
    args = parser.parse_args()
    require(not args.output.exists(), "output must be a new directory")
    archive = args.data_root / "r-corpus-performance/20260824T142432Z"
    inventory_file = archive / "inventory.tsv"
    archived_file = archive / "raw.tsv"
    inventory, archived = table(inventory_file), table(archived_file)
    require(len(inventory) == len({r["id"] for r in inventory}) == 1823,
            "expected original 1823-file inventory")
    comparable = common_rows(inventory, archived)
    require(len(comparable) == 1812, "expected original 1812-file comparison set")
    common_ids = {row["id"] for row in comparable}
    old = {(row["id"], row["reader"]): row for row in archived}
    if args.smoke:
        ids = {next(row["id"] for row in comparable if row["corpus"] == corpus)
               for corpus in ("DHS", "MICS", "NSFG")}
        ids.add("DHS-0259")
        ids.update(row["id"] for row in inventory
                   if old[(row["id"], "dtaparser")]["status"] != "ok")
        inventory = [row for row in inventory if row["id"] in ids]
        common_ids &= ids

    def check_inventory():
        for row in inventory:
            file = args.cache / row["relative_path"]
            stat = file.stat()
            require(file.is_file() and not file.is_symlink() and
                    stat.st_size == int(row["bytes"]) and
                    abs(stat.st_mtime - float(row["mtime"])) < 1e-5,
                    "input differs from retained corpus inventory")

    check_inventory()
    scripts = [Path(__file__), ROOT / "benchmarks/reader-refresh/driver_common.py",
               ROOT / "benchmarks/reader-corpus/prepare.R", ROOT / "benchmarks/reader-corpus/worker.R",
               ROOT / "benchmarks/reader-refresh/workers/benchmark-common.R"]
    binding = source_binding(args.source_root, args.library, args.build_record, scripts)
    binding.update(inventory_sha256=sha(inventory_file), archived_sha256=sha(archived_file))
    args.output.mkdir(parents=True)
    for directory in ("arrow", "qualification", "jobs", "results"):
        (args.output / directory).mkdir()
    write_json(args.output / "binding.json", binding)
    inputs = []
    for row in inventory:
        previous = old[(row["id"], "haven")]
        inputs.append(dict(id=row["id"], path=str(args.cache / row["relative_path"]),
                           common=row["id"] in common_ids,
                           rows=int(previous["rows"]) if row["id"] in common_ids else None,
                           columns=int(previous["columns"]) if row["id"] in common_ids else None))
    write_json(args.output / "inputs.json", inputs)
    environment = child_environment(args.library)
    started = datetime.now(timezone.utc).isoformat()
    run_child(args.output, "prepare", scripts[2],
              [args.library, args.output / "inputs.json", args.output / "arrow",
               args.output / "qualification"], environment)
    qualifications = {row["id"]: json.loads((args.output / "qualification" / (row["id"] + ".json")).read_text())
                      for row in inventory}
    require(all(q["status"] == "ok" for key, q in qualifications.items() if key in common_ids),
            "common input failed Arrow qualification")
    check_inventory()
    require(source_binding(args.source_root, args.library, args.build_record, scripts) ==
            {k: v for k, v in binding.items() if k not in ("inventory_sha256", "archived_sha256")},
            "source or installation changed during preparation")
    observations, identities = [], []
    print("All Arrow copies qualified; starting timed reads", flush=True)
    for index, row in enumerate(inventory):
        q = qualifications[row["id"]]
        paths = {"read_dta": args.cache / row["relative_path"]}
        if q["status"] == "ok":
            paths["read_arrow"] = Path(q["arrow"])
        # Hash both formats immediately before the pair, warming their file bytes.
        identity = dict(id=row["id"], corpus=row["corpus"], common=row["id"] in common_ids,
                        qualification=q["status"])
        for method, file in paths.items():
            identity[method + "_bytes"] = file.stat().st_size
            identity[method + "_sha256"] = sha(file)
        identities.append(identity)
        methods = list(paths)
        if index % 2:
            methods.reverse()
        for position, method in enumerate(methods, 1):
            key = row["id"] + "-" + method
            jobfile, resultfile = args.output / "jobs" / (key + ".json"), args.output / "results" / (key + ".json")
            write_json(jobfile, dict(library=str(args.library), path=str(paths[method]), method=method,
                                    expected_status=q["status"], rows=q.get("rows"), columns=q.get("columns")))
            resource, log = run_child(args.output, key, scripts[3], [method, paths[method]], environment)
            result = parse_read(log, method, q)
            write_json(resultfile, result)
            observations.append(dict(id=row["id"], corpus=row["corpus"], method=method,
                method_position=position, status=result["status"], rows=result.get("rows", ""),
                columns=result.get("columns", ""), elapsed_seconds=validate_clock(result["elapsed_seconds"]),
                read_cpu_seconds=validate_clock(result["read_cpu_seconds"]),
                process_cpu_seconds=resource["process_user_cpu_seconds"] + resource["process_system_cpu_seconds"],
                peak_rss_bytes=resource["peak_rss_bytes"]))
        if (index + 1) % 25 == 0:
            print(f"measured: {index + 1}/{len(inventory)}", flush=True)
    # Rehash every measured input only after all timing is finished.
    for row, identity in zip(inventory, identities):
        q = qualifications[row["id"]]
        paths = {"read_dta": args.cache / row["relative_path"]}
        if q["status"] == "ok":
            paths["read_arrow"] = Path(q["arrow"])
        for method, file in paths.items():
            require(sha(file) == identity[method + "_sha256"], "input changed during measurement")
    check_inventory()
    require(source_binding(args.source_root, args.library, args.build_record, scripts) ==
            {k: v for k, v in binding.items() if k not in ("inventory_sha256", "archived_sha256")},
            "source or installation changed during measurement")
    require(sha(inventory_file) == binding["inventory_sha256"] and sha(archived_file) == binding["archived_sha256"],
            "archived evidence changed")
    summary = aggregate(inventory, common_ids, observations, archived)
    csv_file(args.output / "observations.csv", observations)
    csv_file(args.output / "summary.csv", summary)
    write_json(args.output / "identities.json", identities)
    write_json(args.output / "run.json", dict(started=started, finished=datetime.now(timezone.utc).isoformat(),
        smoke=args.smoke, attempted_dta=len(inventory),
        qualified_arrow=sum(q["status"] == "ok" for q in qualifications.values()), comparable=len(common_ids),
        measured_reads=len(observations), system=platform.platform(), machine=platform.machine(),
        protocol="One full read per fresh process; input hashing warms each pair; reader order alternates by file; base-R worker I/O",
        timed_worker_jsonlite=False, arrow_verification=True, haven_invocations=0, stata_invocations=0))
    (args.output / "COMPLETE").write_text("smoke\n" if args.smoke else "corpus\n")
    print(json.dumps(summary, indent=2), flush=True)


if __name__ == "__main__":
    main()
