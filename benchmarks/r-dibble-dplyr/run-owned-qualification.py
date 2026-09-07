"""Run an exact-source owned-double or memory matrix with persistent guards.

Coordinate a quiet measurement window before invocation. The R runners validate
installed package provenance; this driver validates their committed bytes and
outputs. Failed runs retain diagnostic files and must use a new output directory
for a retry. Python -O and PYTHONOPTIMIZE do not disable these checks.
"""
import argparse
import csv
import datetime
import hashlib
import json
import re
import subprocess
from pathlib import Path

def require(condition, message):
    """Keep integrity checks active even when Python optimization is enabled."""
    if not condition:
        raise RuntimeError(message)


parser = argparse.ArgumentParser()
parser.add_argument("kind", choices=["operations", "memory"])
parser.add_argument("repo", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("library", type=Path)
parser.add_argument("source_sha")
parser.add_argument("runner_sha")
parser.add_argument("mode", choices=["baseline", "candidate"])
args = parser.parse_args()
repo = args.repo.resolve()
output = args.output.resolve()
runner_dir = Path("benchmarks/r-dibble-dplyr")
paths = [runner_dir / name for name in ["helpers.R", "owned-double-helpers.R", "owned-double.R", "owned-double-memory.R"]]
source_bytes = {}
for path in paths:
    expected = subprocess.check_output(["git", "show", f"{args.runner_sha}:{path.as_posix()}"], cwd=repo)
    require((repo / path).read_bytes() == expected, f"Runner source mismatch: {path}")
    source_bytes[path] = expected
identities = {path.name: hashlib.sha256(data).hexdigest() for path, data in source_bytes.items()}
md5_lines = [f"runner_md5 {path.as_posix()} {hashlib.md5(data).hexdigest()}" for path, data in source_bytes.items()]
started = datetime.datetime.now(datetime.timezone.utc).isoformat()

def check_identity(text):
    found = re.findall(r"^runner_md5 .*", text, re.MULTILINE)
    require(found == md5_lines, (found, md5_lines))

def run(command, log):
    with log.open("x") as file:
        result = subprocess.run(command, cwd=repo, stdout=file, stderr=subprocess.STDOUT)
    require(result.returncode == 0, f"Exit {result.returncode}; see {log}")
    return log.read_text()

manifest_path = output / "root-manifest.json"
if args.kind == "operations":
    require(not output.exists(), f"Refusing to replace evidence: {output}")
    output.mkdir(parents=True)
    run(["Rscript", "--vanilla", str(runner_dir / "owned-double.R"), str(args.library.resolve()), str(output), args.source_sha, args.mode, "7"], output / "runner.log")
    check_identity((output / "owned-double-session.txt").read_text())
    manifest = {"source_sha": args.source_sha, "library": str(args.library.resolve()),
                "mode": args.mode, "iterations": 7, "runner_source_sha": args.runner_sha,
                "runner_sha256": identities, "started_utc": started,
                "measurement_window": "Implementation and reviewers paused builds/tests; benchmark processes ran sequentially.",
                "outputs": {}}
    for path in sorted(output.glob("*.csv")):
        with path.open() as file:
            rows = list(csv.DictReader(file))
        manifest["outputs"][path.name] = {"rows": len(rows), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    require(manifest["outputs"]["owned-double.csv"]["rows"] == 46, 'Qualification failed: manifest["outputs"]["owned-double.csv"]["rows"] == 46')
    require(manifest["outputs"]["owned-after-read.csv"]["rows"] == 30, 'Qualification failed: manifest["outputs"]["owned-after-read.csv"]["rows"] == 30')
    require(manifest["outputs"]["owned-double-writes.csv"]["rows"] == 6, 'Qualification failed: manifest["outputs"]["owned-double-writes.csv"]["rows"] == 6')
else:
    manifest = json.loads(manifest_path.read_text())
    require(manifest["source_sha"] == args.source_sha, 'Qualification failed: manifest["source_sha"] == args.source_sha')
    require(manifest["runner_source_sha"] == args.runner_sha, 'Qualification failed: manifest["runner_source_sha"] == args.runner_sha')
    require(manifest["library"] == str(args.library.resolve()), "Manifest library mismatch")
    require(manifest["mode"] == args.mode, "Manifest mode mismatch")
    require(manifest["runner_sha256"] == identities, 'Qualification failed: manifest["runner_sha256"] == identities')
    require(not manifest.get("memory_cases"), "Memory evidence already exists")
    manifest["memory_scope"] = "Whole-process RSS includes startup, fixtures and validation; retained vector heap is separate."
    manifest["memory_cases"] = []
    for rows in [100000, 1000000]:
        for operation in ["rename", "pipeline_five", "pipeline_50"]:
            filename = f"memory-{operation}-{rows}.log"
            log = output / filename
            require(not log.exists(), f"Refusing to replace evidence: {log}")
            text = run(["/usr/bin/time", "-l", "Rscript", "--vanilla", str(runner_dir / "owned-double-memory.R"), str(args.library.resolve()), args.source_sha, args.mode, operation, str(rows)], log)
            check_identity(text)
            peak = re.search(r"^\s+(\d+)\s+maximum resident set size\s*$", text, re.MULTILINE)
            require(peak, f"RSS missing: {log}")
            manifest["memory_cases"].append({"operation": operation, "rows": rows, "file": filename,
                "exit_code": 0, "maximum_resident_set_size_bytes": int(peak[1]),
                "sha256": hashlib.sha256(log.read_bytes()).hexdigest()})
            print(filename, "passed", flush=True)
for path, data in source_bytes.items():
    require((repo / path).read_bytes() == data, f"Runner changed during measurement: {path}")
manifest["manifest_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
with manifest_path.open("x" if args.kind == "operations" else "w") as file:
    file.write(json.dumps(manifest, indent=2) + "\n")
print(args.kind, args.mode, "complete:", output, flush=True)
