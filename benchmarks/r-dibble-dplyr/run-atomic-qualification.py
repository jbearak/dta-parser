"""Run the Stage 4 matrix in a coordinated quiet window, preserving evidence.

Integrity checks are explicit exceptions and remain enabled under Python -O.
R verifies the exact installed package before and after each process. This driver
verifies every R dependency and its own committed bytes before and after the run.
"""
import argparse
import csv
import datetime
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


KINDS = ["string", "declared_character", "logical", "factor", "ordered"]
SIZES = [100000, 1000000]
R_NAMES = ["helpers.R", "owned-double-helpers.R", "owned-atomic-helpers.R",
           "owned-atomic.R", "owned-atomic-memory.R"]
SELECTORS = ["rename", "select", "relocate", "pipeline_five"]
COMMON_READS = ["any_na", "nonmissing_count", "coercion_character", "export_data_frame",
                "export_tibble", "filter_half", "row_subset", "read_dta", "write_dta",
                "read_arrow", "write_arrow"]
EXTRA_READS = {"string": ["byte_width"], "declared_character": ["byte_width"],
               "logical": ["coercion_integer", "sum", "mean"],
               "factor": ["coercion_integer"], "ordered": ["coercion_integer", "range"]}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_csv(path, fields, expected):
    with path.open() as file:
        rows = list(csv.DictReader(file))
    observed = [tuple(row[field] for field in fields) for row in rows]
    require(len(observed) == len(expected) and set(observed) == expected,
            f"Incomplete or duplicate case matrix: {path}")
    for row in rows:
        for field in ["r_allocated_bytes", "r_largest_allocation_bytes"]:
            number = float(row[field])
            require(math.isfinite(number) and number >= 0, f"Invalid {field}: {path}")
        if "median_ms" in row:
            require(math.isfinite(float(row["median_ms"])) and float(row["median_ms"]) >= 0,
                    f"Invalid median: {path}")
            require(int(row["iterations"]) == 7, f"Incomplete timing iterations: {path}")
    return len(rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=["operations", "memory"])
    parser.add_argument("repo", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("library", type=Path)
    parser.add_argument("source_sha")
    parser.add_argument("runner_sha")
    parser.add_argument("mode", choices=["baseline", "candidate"])
    args = parser.parse_args()
    repo, output, library = args.repo.resolve(), args.output.resolve(), args.library.resolve()
    runner_dir = Path("benchmarks/r-dibble-dplyr")
    driver_path = runner_dir / "run-atomic-qualification.py"
    require(Path(__file__).resolve() == repo / driver_path, "Run the driver from the specified repository")
    paths = [runner_dir / name for name in R_NAMES] + [driver_path]
    source_bytes = {}
    for path in paths:
        expected = subprocess.check_output(["git", "show", f"{args.runner_sha}:{path.as_posix()}"], cwd=repo)
        require((repo / path).read_bytes() == expected, f"Runner source mismatch: {path}")
        source_bytes[path] = expected
    identities = {path.name: hashlib.sha256(data).hexdigest() for path, data in source_bytes.items()}
    md5_lines = [f"runner_md5 {path.as_posix()} {hashlib.md5(source_bytes[path]).hexdigest()}"
                 for path in paths[:-1]]
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()

    def check_identity(text):
        require(re.findall(r"^runner_md5 .*", text, re.MULTILINE) == md5_lines,
                "Runtime runner dependency identity mismatch")
        for key, value in [("source_sha", args.source_sha), ("library", str(library)), ("mode", args.mode)]:
            require(re.findall(rf"^{key} (.*)$", text, re.MULTILINE) == [value],
                    f"Runtime {key} identity mismatch")

    def run(command, log):
        with log.open("x") as file:
            result = subprocess.run(command, cwd=repo, stdout=file, stderr=subprocess.STDOUT)
        require(result.returncode == 0, f"Exit {result.returncode}; see {log}")
        return log.read_text()

    manifest_path = output / "root-manifest.json"
    if args.kind == "operations":
        require(not output.exists(), f"Refusing to replace evidence: {output}")
        output.mkdir(parents=True)
        run(["Rscript", "--vanilla", str(runner_dir / "owned-atomic.R"), str(library), str(output),
             args.source_sha, args.mode, "7"], output / "runner.log")
        check_identity((output / "owned-atomic-session.txt").read_text())
        direct = {(kind, family, op, str(rows)) for kind in KINDS for rows in SIZES
                  for family in ["direct", "safe_delegation"] for op in SELECTORS}
        reads = {(kind, "read", op, str(rows)) for kind in KINDS for rows in SIZES
                 for op in COMMON_READS + EXTRA_READS[kind]}
        counts = {}
        counts["owned-atomic.csv"] = verify_csv(output / "owned-atomic.csv",
            ["kind", "family", "operation", "rows"], direct | reads)
        counts["owned-atomic-after-read.csv"] = verify_csv(output / "owned-atomic-after-read.csv",
            ["kind", "after_operation", "rows"], {(k, op, r) for k, _, op, r in reads})
        counts["owned-atomic-writes.csv"] = verify_csv(output / "owned-atomic-writes.csv",
            ["kind", "operation", "rows"], {(k, op, str(r)) for k in KINDS[:3] for r in SIZES
                for op in ["shared_sparse", "private_sparse", "full_replacement"]})
        manifest = {"source_sha": args.source_sha, "library": str(library), "mode": args.mode,
            "iterations": 7, "runner_source_sha": args.runner_sha, "runner_sha256": identities,
            "started_utc": started, "csv_rows": counts,
            "measurement_window": "Implementation and reviewers paused builds/tests; processes ran sequentially.",
            "files": {path.name: digest(path) for path in sorted(output.iterdir()) if path.is_file()}}
    else:
        manifest = json.loads(manifest_path.read_text())
        for key, value in [("source_sha", args.source_sha), ("runner_source_sha", args.runner_sha),
                           ("library", str(library)), ("mode", args.mode), ("runner_sha256", identities)]:
            require(manifest[key] == value, f"Manifest {key} mismatch")
        require(not manifest.get("memory_cases"), "Memory evidence already exists")
        for name, expected_hash in manifest["files"].items():
            require((output / name).is_file() and digest(output / name) == expected_hash,
                    f"Existing evidence changed: {name}")
        cases = [(kind, rows, operation) for kind in KINDS for rows in SIZES
                 for operation in ["rename", "pipeline_five", "pipeline_50"]]
        for kind, rows, operation in cases:
            require(not (output / f"memory-{kind}-{operation}-{rows}.log").exists(),
                    f"Memory log already exists: {kind} {operation} {rows}")
        manifest["memory_cases"] = []
        manifest["memory_scope"] = "Whole-process RSS includes startup, fixtures and validation; retained vector heap is separate."
        for kind, rows, operation in cases:
            filename = f"memory-{kind}-{operation}-{rows}.log"
            log = output / filename
            text = run(["/usr/bin/time", "-l", "Rscript", "--vanilla", str(runner_dir / "owned-atomic-memory.R"),
                        str(library), args.source_sha, args.mode, kind, operation, str(rows)], log)
            check_identity(text)
            metrics = {}
            for field in ["maximum resident set size", "retained_with_source_vector_heap_bytes",
                          "excess_after_drop_result_bytes", "released_with_last_result_bytes"]:
                pattern = rf"^\s*(\d+)\s+{field}\s*$" if field == "maximum resident set size" else rf"^{field} ([-+0-9.eE]+)\s*$"
                found = re.findall(pattern, text, re.MULTILINE)
                require(len(found) == 1, f"Missing/duplicate memory metric {field}: {log}")
                number = float(found[0])
                require(math.isfinite(number) and number.is_integer(), f"Invalid memory metric {field}: {log}")
                metrics[field.replace(" ", "_")] = int(number)
            manifest["memory_cases"].append({"kind": kind, "operation": operation, "rows": rows,
                "file": filename, "exit_code": 0, "metrics": metrics, "sha256": digest(log)})
            print(filename, "passed", flush=True)
    for path, data in source_bytes.items():
        require((repo / path).read_bytes() == data, f"Runner changed during measurement: {path}")
    manifest["manifest_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with manifest_path.open("x" if args.kind == "operations" else "w") as file:
        file.write(json.dumps(manifest, indent=2) + "\n")
    print(args.kind, args.mode, "complete:", output, flush=True)


if __name__ == "__main__":
    main()
