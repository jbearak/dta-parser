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
CHECKPOINTS = ["prefixture", "prior", "after_result", "after_drop_source", "after_drop_result"]


def verify_metrics(text, log):
    """Recompute retained heap from five ordered checkpoints and raw cell counts.

    Infer the unique header-cell size consistent with R's rounded MB reports,
    then verify every reported delta independently. These retained-heap values
    do not measure peak RSS or elapsed time.
    """
    metrics = {}
    for field in METRICS:
        found = re.findall(rf"^heap_{field} ([-+0-9.eE]+)\s*$", text, re.MULTILINE)
        require(len(found) == 1, f"Missing or duplicate {field}: {log}")
        number = float(found[0])
        require(math.isfinite(number) and number.is_integer(), f"Invalid {field}: {log}")
        metrics[field] = int(number)
    records = re.findall(r"^heap_checkpoint (\w+) header_cells (\d+) vector_bytes (\d+) header_reported_mb ([0-9.eE+]+)\s*$", text, re.MULTILINE)
    require([row[0] for row in records] == CHECKPOINTS, f"Incomplete or duplicate checkpoints: {log}")
    points = {name: {"header_cells": int(n), "vector_bytes": int(v), "header_reported_mb": float(mb)}
              for name, n, v, mb in records}
    require(all(x["header_cells"] > 0 and x["vector_bytes"] > 0 and x["vector_bytes"] % 8 == 0 and
                math.isfinite(x["header_reported_mb"]) and x["header_reported_mb"] > 0 for x in points.values()),
            f"Invalid heap checkpoint: {log}")
    sizes = [size for size in range(1, 1025) if all(
        abs(math.ceil(10 * x["header_cells"] / 1024**2 * size) / 10 - x["header_reported_mb"]) < 1e-9
        for x in points.values())]
    require(sizes == [metrics["header_bytes_per_cell"]], f"Header size inference mismatch: {log}")
    for point in points.values():
        point["tracked_heap_bytes"] = point["header_cells"] * sizes[0] + point["vector_bytes"]
    expected = {"retained_header_cells": ("after_result", "prior", "header_cells"),
                "excess_header_cells_after_drop_result": ("after_drop_result", "prefixture", "header_cells"),
                "retained_tracked_heap_bytes": ("after_result", "prior", "tracked_heap_bytes"),
                "excess_tracked_heap_bytes_after_drop_result": ("after_drop_result", "prefixture", "tracked_heap_bytes"),
                "released_tracked_heap_bytes_with_last_result": ("after_drop_source", "after_drop_result", "tracked_heap_bytes")}
    for metric, (after, before, field) in expected.items():
        require(metrics[metric] == points[after][field] - points[before][field],
                f"Derived {metric} mismatch: {log}")
    return metrics, points


def main():
    """Bind source/runner identities and retain all 36 fresh-process heap cases.

    Each R child checks the requested installation and emits its dependency
    identity. Failed logs survive; a manifest is published only after the full
    case matrix, derived metrics and unchanged source/output hashes pass.
    """
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
        metrics, points = verify_metrics(text, log)
        if args.mode == "candidate":
            require(metrics["retained_tracked_heap_bytes"] < 1000000 and
                    metrics["excess_tracked_heap_bytes_after_drop_result"] < 1000000,
                    f"Tracked retained heap exceeds budget: {log}")
        for path, data in original.items():
            require((repo / path).read_bytes() == data, f"Runner changed during measurement: {path}")
        manifest["cases"].append({"kind": kind, "operation": operation, "rows": rows,
                                  "file": filename, "exit_code": 0, "sha256": digest(log),
                                  "metrics": metrics, "checkpoints": points})
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
