"""Bind a paired writer run to installed libraries, fixed inputs and scripts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", type=Path)
    parser.add_argument("phase", choices=("before", "after"))
    args = parser.parse_args()
    config = json.loads(args.configuration.read_text())
    root = Path(config["root"]).resolve()
    directory = Path(config["directory"]).resolve()
    executable = shutil.which("Rscript")
    if executable is None:
        parser.error("Rscript is unavailable")
    rscript = Path(executable).resolve()
    record = dict(libraries={}, inputs={}, scripts={}, rscript_sha256=sha(rscript),
        host=dict(platform=platform.platform(), logical_cpus=os.cpu_count()),
        thread_environment={key: os.environ.get(key) for key in (
            "OMP_NUM_THREADS", "OMP_THREAD_LIMIT", "OPENBLAS_NUM_THREADS",
            "VECLIB_MAXIMUM_THREADS", "MKL_NUM_THREADS", "RCPP_PARALLEL_NUM_THREADS")})
    for variant in ("baseline", "candidate"):
        library = Path(config[variant]).resolve()
        package = library / "dtatools"
        if not (package / "libs/dtatools.so").is_file():
            parser.error("Missing installed package library")
        env = {key: value for key, value in os.environ.items()
            if not key.startswith(("DTATOOLS_EXPERIMENT_", "DTA_READ_PERF_"))}
        env.update(R_LIBS=str(library), DTATOOLS_BENCH_LIB=str(library))
        runtime = subprocess.check_output([str(rscript), "--vanilla", "-e",
            'library(dtatools); stopifnot(normalizePath(find.package("dtatools")) == '
            'normalizePath(file.path(Sys.getenv("DTATOOLS_BENCH_LIB"), "dtatools"))); sessionInfo()'],
            env=env, text=True, timeout=60)
        record["libraries"][variant] = dict(runtime=runtime, installed_files={
            str(path.relative_to(package)): sha(path)
            for path in sorted(package.rglob("*")) if path.is_file()})
    for item in config["writes"]:
        if item["id"] in record["inputs"]:
            parser.error("Duplicate writer fixture identifier")
        value = dict(kind=item["kind"], rows=item["rows"], columns=40)
        if item["kind"] == "primary":
            source = Path(item["input"])
            value.update(sha256=sha(source), bytes=source.stat().st_size)
        elif item["kind"] == "ordinary":
            if int(item["input"]) != item["rows"]:
                parser.error("Ordinary fixture row count differs")
        else:
            parser.error("Unknown writer fixture kind")
        record["inputs"][item["id"]] = value
    for name in ("benchmarks/io-merge-review/run.py", "benchmarks/io-merge-review/worker.R",
                 "benchmarks/io-merge-review/qualify.py",
                 "benchmarks/reader-refresh/workers/benchmark-common.R",
                 "benchmarks/large-scale/standard-r-write-fixture.R",
                 "benchmarks/io-optimization/write-provenance.py"):
        record["scripts"][name] = sha(root / name)
    destination = directory / ("writes-provenance-" + args.phase + ".json")
    if destination.exists():
        parser.error("Refusing to overwrite a provenance record")
    if args.phase == "after":
        before = json.loads((directory / "writes-provenance-before.json").read_text())
        if before != record:
            raise RuntimeError("Writer measurement binding changed")
    destination.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    print("Captured writer provenance " + args.phase, flush=True)


if __name__ == "__main__":
    main()
