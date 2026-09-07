"""Measure both R heap components with unchanged historical memory workloads.

Run in a coordinated quiet window. Each case gets a fresh R process. Integrity
checks remain enabled under Python -O, and existing evidence is never replaced.
"""
import argparse
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


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


R_NAMES = ["helpers.R", "owned-double-helpers.R", "owned-atomic-helpers.R",
           "owned-double.R", "owned-double-memory.R", "owned-atomic.R",
           "owned-atomic-memory.R", "owned-heap.R"]
METRICS = ["header_bytes_per_cell", "retained_header_cells",
           "excess_header_cells_after_drop_result", "retained_tracked_heap_bytes",
           "excess_tracked_heap_bytes_after_drop_result",
           "released_tracked_heap_bytes_with_last_result"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("repo", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("library", type=Path)
    parser.add_argument("source_sha")
    parser.add_argument("runner_sha")
    parser.add_argument("mode", choices=["baseline", "candidate"])
    args = parser.parse_args()
    repo, output, library = args.repo.resolve(), args.output.resolve(), args.library.resolve()
    require(all(re.fullmatch("[0-9a-f]{40}", x) for x in [args.source_sha, args.runner_sha]),
            "Use full source and runner commit identities")
    require(not output.exists(), f"Refusing to replace evidence: {output}")
    relative = Path("benchmarks/r-dibble-dplyr")
    driver = relative / "run-heap-qualification.py"
    require(Path(__file__).resolve() == repo / driver, "Run the driver from the specified repository")
    paths = [relative / name for name in R_NAMES] + [driver]
    original = {}
    for path in paths:
        data = subprocess.check_output(["git", "show", f"{args.runner_sha}:{path.as_posix()}"], cwd=repo)
        require((repo / path).read_bytes() == data, f"Runner source mismatch: {path}")
        original[path] = data
    identities = {path.as_posix(): hashlib.sha256(data).hexdigest() for path, data in original.items()}
    md5_lines = [f"heap_runner_md5 {path.as_posix()} {hashlib.md5(original[path]).hexdigest()}"
                 for path in paths[:-1]]
    cases = [(kind, rows, operation)
             for kind in ["double", "string", "declared_character", "logical", "factor", "ordered"]
             for rows in [100000, 1000000]
             for operation in ["rename", "pipeline_five", "pipeline_50"]]
    output.mkdir(parents=True)
    manifest = {"source_sha": args.source_sha, "runner_source_sha": args.runner_sha,
                "library": str(library), "mode": args.mode, "runner_sha256": identities,
                "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "scope": "Fresh-process R header-cell and vector-heap retention; no timing or peak-RSS claim",
                "cases": []}
    for kind, rows, operation in cases:
        filename = f"heap-{kind}-{operation}-{rows}.log"
        log = output / filename
        command = ["Rscript", "--vanilla", str(relative / "owned-heap.R"), str(library),
                   args.source_sha, args.mode, kind, operation, str(rows)]
        with log.open("x") as file:
            result = subprocess.run(command, cwd=repo, stdout=file, stderr=subprocess.STDOUT)
        require(result.returncode == 0, f"Exit {result.returncode}; see {log}")
        text = log.read_text()
        require(re.findall(r"^heap_runner_md5 .*", text, re.MULTILINE) == md5_lines,
                f"Runtime runner identity mismatch: {log}")
        for key, value in [("source_sha", args.source_sha), ("library", str(library)),
                           ("mode", args.mode), ("kind", kind), ("operation", operation), ("rows", str(rows))]:
            require(re.findall(rf"^heap_{key} (.*?)\s*$", text, re.MULTILINE) == [value],
                    f"Runtime {key} mismatch: {log}")
        metrics = {}
        for field in METRICS:
            found = re.findall(rf"^heap_{field} ([-+0-9.eE]+)\s*$", text, re.MULTILINE)
            require(len(found) == 1, f"Missing or duplicate {field}: {log}")
            number = float(found[0])
            require(math.isfinite(number) and number.is_integer(), f"Invalid {field}: {log}")
            metrics[field] = int(number)
        require(0 < metrics["header_bytes_per_cell"] <= 1024, f"Invalid header size: {log}")
        if args.mode == "candidate":
            require(metrics["retained_tracked_heap_bytes"] < 1000000 and
                    metrics["excess_tracked_heap_bytes_after_drop_result"] < 1000000,
                    f"Tracked retained heap exceeds budget: {log}")
        for path, data in original.items():
            require((repo / path).read_bytes() == data, f"Runner changed during measurement: {path}")
        manifest["cases"].append({"kind": kind, "operation": operation, "rows": rows,
                                  "file": filename, "exit_code": 0, "sha256": digest(log), "metrics": metrics})
        print(filename, "passed", flush=True)
    require(len(manifest["cases"]) == 36, "Incomplete heap matrix")
    for case in manifest["cases"]:
        require(digest(output / case["file"]) == case["sha256"], f"Changed evidence: {case['file']}")
    manifest["completed_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with (output / "root-manifest.json").open("x") as file:
        json.dump(manifest, file, indent=2)
        file.write("\n")
    print(args.mode, "heap supplement complete:", output, flush=True)


if __name__ == "__main__":
    main()
