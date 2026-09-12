#!/usr/bin/env python3
"""Ten fresh-process India reads per tool, including haven and native Stata."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("library", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--dta", type=Path, required=True)
parser.add_argument("--arrow", type=Path, required=True)
parser.add_argument("--stata", type=Path, default=Path(
    "/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp"))
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
for name in ("library", "output", "dta", "arrow", "stata"):
    setattr(args, name, getattr(args, name).resolve())
args.output.mkdir(parents=True, exist_ok=True)
env = os.environ.copy()
env.update(DTATOOLS_BENCH_LIB=str(args.library),
           R_ENVIRON_USER="/dev/null", R_PROFILE_USER="/dev/null")
rscript = shutil.which("Rscript")
assert rscript and args.stata.is_file()


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def tree_sha(directory):
    return {str(p.relative_to(directory)): sha(p)
            for p in sorted(directory.rglob("*")) if p.is_file()}


def publish(path, rows):
    temporary = path.with_suffix(".tmp")
    with temporary.open("w") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(path)


haven_path = Path(subprocess.check_output([rscript, "--vanilla", "-e",
    '.libPaths(c(Sys.getenv("DTATOOLS_BENCH_LIB"), .libPaths())); cat(find.package("haven"))'],
    env=env, text=True))
scripts = [Path(__file__), root / "benchmarks/r-corpus-performance/worker.R",
           root / "benchmarks/r-corpus-performance/stata-worker.do",
           root / "benchmarks/reader-refresh/compare.R",
           root / "benchmarks/benchmark-common.R"]


def binding():
    return dict(
        source_commit=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        package_tree=subprocess.check_output(["git", "rev-parse", "HEAD:r-package/dtatools"], cwd=root, text=True).strip(),
        dtatools=tree_sha(args.library / "dtatools"), haven=tree_sha(haven_path),
        stata={p.name: sha(p) for p in (args.stata, args.stata.parent / "libstata-mp.dylib")},
        rscript_sha256=sha(Path(rscript)),
        scripts={str(p.relative_to(root)): sha(p) for p in scripts},
        inputs={name: dict(bytes=path.stat().st_size, sha256=sha(path))
                for name, path in [("dta", args.dta), ("arrow", args.arrow)]})


initial = binding()
previous = json.loads((root / "benchmarks/reader-refresh/results-2026-09-12/provenance.json").read_text())
subprocess.run(["git", "diff", "--exit-code", previous["bindings"]["reads"]["commit"], "HEAD", "--",
                "r-package/dtatools/R", "r-package/dtatools/src",
                "r-package/dtatools/DESCRIPTION", "r-package/dtatools/NAMESPACE"], cwd=root, check=True)
assert all(initial["dtatools"][name] == digest
           for name, digest in previous["bindings"]["reads"]["installed"].items())
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
if raw_file.exists():
    with raw_file.open() as stream:
        observations = list(csv.DictReader(stream))
else:
    observations = []
completed = {(int(r["iteration"]), r["method"]) for r in observations}
assert len(completed) == len(observations)
methods = ["read_dta", "read_arrow", "haven", "stata"]

for iteration in range(1, 11):
    shift = (iteration - 1) % len(methods)
    order = methods[shift:] + methods[:shift]
    for position, method in enumerate(order, 1):
        if (iteration, method) in completed:
            continue
        key = f"{iteration:02d}-{method}"
        work = args.output / key
        work.mkdir(exist_ok=True)
        if method == "stata":
            link = work / "input.dta"
            if not link.exists():
                link.symlink_to(args.dta)
            shutil.copyfile(root / "benchmarks/r-corpus-performance/stata-worker.do", work / "stata-worker.do")
            command = [str(args.stata), "-q", "-b", "do", "stata-worker.do"]
        elif method == "read_arrow":
            command = [rscript, "--vanilla", str(root / "benchmarks/reader-refresh/compare.R"),
                       "memory", str(args.arrow)]
        else:
            command = [rscript, "--vanilla", str(root / "benchmarks/r-corpus-performance/worker.R"),
                       "dtatools" if method == "read_dta" else "haven", str(args.dta)]
        print(f"START {key}, position {position}/4", flush=True)
        log = work / "process.log"
        started = time.time()
        with log.open("wb") as stream:
            actions = [(os.POSIX_SPAWN_DUP2, stream.fileno(), 1),
                       (os.POSIX_SPAWN_DUP2, stream.fileno(), 2)]
            old_cwd = Path.cwd()
            os.chdir(work)
            try:
                pid = os.posix_spawn(command[0], command, env, file_actions=actions)
            finally:
                os.chdir(old_cwd)
            (args.output / "active.json").write_text(json.dumps(dict(key=key, pid=pid, started=started)) + "\n")
            _, status, usage = os.wait4(pid, 0)
        job = dict(key=key, command=command, exit_code=os.waitstatus_to_exitcode(status),
                   peak_rss_bytes=usage.ru_maxrss * (1 if sys.platform == "darwin" else 1024),
                   started=started, duration=time.time() - started)
        with (args.output / "jobs.jsonl").open("a") as stream:
            stream.write(json.dumps(job) + "\n")
        assert job["exit_code"] == 0, f"worker failed: {key}"
        if method == "stata":
            fields = [s.strip() for s in (work / "result.tsv").read_text().strip().split("\t")]
        else:
            markers = [line.split("\t")[1:] for line in log.read_text().splitlines()
                       if line.startswith("DTATOOLS_BENCH\t")]
            assert len(markers) == 1
            fields = markers[0]
        assert len(fields) == 4 and fields[0] == "ok", f"read failed: {key}"
        _, elapsed, rows, columns = fields
        assert (int(rows), int(columns)) == (724115, 5972), f"dimensions differ: {key}"
        observations.append(dict(iteration=iteration, position=position, method=method,
            elapsed_seconds=float(elapsed), peak_rss_bytes=job["peak_rss_bytes"],
            rows=int(rows), columns=int(columns)))
        publish(raw_file, observations)
        print(f"DONE {key}: {float(elapsed):.3f} s, {job['peak_rss_bytes']/1e9:.3f} GB peak RSS; "
              f"{len(observations)}/40 reads", flush=True)

assert len(observations) == 40
assert binding() == initial, "inputs, library or runtime changed during measurements"
summary = []
for method in methods:
    selected = [r for r in observations if r["method"] == method]
    assert len(selected) == 10
    elapsed = [float(r["elapsed_seconds"]) for r in selected]
    memory = [float(r["peak_rss_bytes"]) / 1e9 for r in selected]
    summary.append(dict(method=method, iterations=len(selected),
        median_seconds=statistics.median(elapsed), mean_seconds=statistics.mean(elapsed),
        sd_seconds=statistics.stdev(elapsed), min_seconds=min(elapsed), max_seconds=max(elapsed),
        median_peak_rss_gb=statistics.median(memory), min_peak_rss_gb=min(memory), max_peak_rss_gb=max(memory)))
publish(args.output / "summary.csv", summary)
(args.output / "active.json").unlink()
print("COMPLETE: 10 successful reads per tool; final input and installation hashes match.", flush=True)
