"""Paired public-reader screen. Run without competing builds or benchmarks."""
import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import re
import shutil
import statistics
import subprocess
import sys
import time


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def inventory(library):
    package = library / "dtatools"
    return {str(path.relative_to(package)): sha(path)
            for path in sorted(package.rglob("*")) if path.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("baseline", "candidate", "fixtures", "work"):
        parser.add_argument("--" + name, type=lambda x: Path(x).resolve(), required=True)
    parser.add_argument("--methods", nargs="+", choices=("dta", "arrow"), default=["dta", "arrow"])
    parser.add_argument("--cases", nargs="+")
    parser.add_argument("--threads", nargs="+", type=int, default=[1, 0])
    parser.add_argument("--pairs", type=int, default=10)
    args = parser.parse_args()
    if args.pairs <= 0 or args.pairs % 2 or any(n < 0 for n in args.threads):
        parser.error("Use a positive even pair count and nonnegative thread limits")
    if args.baseline == args.candidate:
        parser.error("Use independently installed libraries")
    if len(set(args.methods)) != len(args.methods) or len(set(args.threads)) != len(args.threads):
        parser.error("Reader methods and thread limits must be unique")
    if sys.platform not in ("darwin", "linux"):
        parser.error("RSS units are supported only on macOS and Linux")
    rscript = shutil.which("Rscript")
    if rscript is None:
        parser.error("Rscript is unavailable")
    rscript = str(Path(rscript).resolve())
    args.work.mkdir(parents=True, exist_ok=False)
    root = Path(__file__).resolve().parents[2]
    worker = root / "benchmarks/reader-cpu-scaling/worker.R"
    fixtures = json.loads(args.fixtures.read_text())["reads"]
    if (not fixtures or len({item["id"] for item in fixtures}) != len(fixtures) or
            any(not re.fullmatch(r"[A-Za-z0-9_-]+", item["id"]) for item in fixtures)):
        parser.error("Provide unique, nonempty alphanumeric fixture identifiers")
    if args.cases:
        if set(args.cases) - {item["id"] for item in fixtures}:
            parser.error("Unknown fixture identifier")
        fixtures = [item for item in fixtures if item["id"] in args.cases]
    libraries = dict(baseline=args.baseline, candidate=args.candidate)

    def environment(library):
        env = {key: value for key, value in os.environ.items()
            if not key.startswith(("DTATOOLS_EXPERIMENT_", "DTA_READ_PERF_"))}
        env.update(R_LIBS=str(library), DTATOOLS_BENCH_LIB=str(library))
        return env

    def runtimes():
        return {name: subprocess.check_output([rscript, "--vanilla", "-e",
            'library(dtatools); sessionInfo()'], env=environment(path), text=True)
            for name, path in libraries.items()}

    for library in libraries.values():
        if not (library / "dtatools/libs/dtatools.so").is_file():
            parser.error("Missing installed package library")
    before = dict(libraries={name: inventory(path) for name, path in libraries.items()},
        runtimes=runtimes(), rscript_sha256=sha(Path(rscript)),
        host=dict(platform=platform.platform(), machine=platform.machine(), logical_cpus=os.cpu_count(),
            thread_environment={key: os.environ.get(key) for key in (
                "OMP_NUM_THREADS", "OMP_THREAD_LIMIT", "OPENBLAS_NUM_THREADS",
                "VECLIB_MAXIMUM_THREADS", "MKL_NUM_THREADS", "RCPP_PARALLEL_NUM_THREADS")}),
        inputs={item["id"] + "-" + method: dict(sha256=sha(Path(item[method])),
            bytes=Path(item[method]).stat().st_size, rows=item["rows"], columns=item["columns"])
            for item in fixtures for method in args.methods},
        workers={"read-screen.py": sha(Path(__file__)), "worker.R": sha(worker)},
        protocol=dict(pairs=args.pairs, threads=args.threads, methods=args.methods,
            cache="warm filesystem", boundary="first read in each fresh process"))
    (args.work / "provenance-before.json").write_text(json.dumps(before, indent=2) + "\n")

    def invoke(item, method, threads, variant, key, qualify=False):
        command = [rscript, "--vanilla", str(worker),
            ("qualify-" if qualify else "") + method, item[method], str(threads),
            str(item["rows"]), str(item["columns"])]
        log = args.work / (key + ".log")
        started = time.monotonic()
        with log.open("w") as stream:
            process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
                env=environment(libraries[variant]))
            try:
                _, status, usage = os.wait4(process.pid, 0)
                process.returncode = os.waitstatus_to_exitcode(status)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
        process_wall = time.monotonic() - started
        if process.returncode:
            raise RuntimeError("Reader worker failed: " + key)
        prefix = "QUALIFIED\t" if qualify else "READ\t"
        records = [line.split("\t") for line in log.read_text().splitlines() if line.startswith(prefix)]
        if len(records) != 1:
            raise RuntimeError("Missing or duplicate worker record: " + key)
        value = records[0]
        if qualify:
            return dict(signature=value[4], log_sha256=sha(log))
        wall, user, system = map(float, value[1:4])
        if (any(not math.isfinite(n) or n < 0 for n in (wall, user, system)) or
                tuple(map(int, value[4:6])) != (item["rows"], item["columns"])):
            raise RuntimeError("Invalid timing record: " + key)
        return dict(call_wall=wall, call_cpu=user + system, process_wall=process_wall,
            process_cpu=usage.ru_utime + usage.ru_stime,
            maxrss_bytes=usage.ru_maxrss * (1 if sys.platform == "darwin" else 1024), log_sha256=sha(log))

    cases = [(item, method, threads) for item in fixtures for method in args.methods for threads in args.threads]
    qualified = {}
    fixture_signatures = {}
    for item, method, threads in cases:
        key = f'{item["id"]}-{method}-{threads}'
        values = {variant: invoke(item, method, threads, variant,
            "qualify-" + key + "-" + variant, True) for variant in libraries}
        if values["baseline"]["signature"] != values["candidate"]["signature"]:
            raise RuntimeError("Reader signatures differ: " + key)
        signature = values["baseline"]["signature"]
        if fixture_signatures.setdefault(item["id"], signature) != signature:
            raise RuntimeError("Reader format or thread signatures differ: " + key)
        qualified[key] = values
    (args.work / "qualification.json").write_text(json.dumps(qualified, indent=2) + "\n")
    rows = []
    with (args.work / "raw.jsonl").open("w") as raw:
        for pair in range(1, args.pairs + 1):
            offset = (pair - 1) % len(cases)
            for item, method, threads in cases[offset:] + cases[:offset]:
                case = f'{item["id"]}-{method}-{threads}'
                order = ("baseline", "candidate") if pair % 2 else ("candidate", "baseline")
                for position, variant in enumerate(order, 1):
                    row = dict(case=case, pair=pair, position=position, variant=variant,
                        **invoke(item, method, threads, variant, f'{pair:02d}-{case}-{variant}'))
                    rows.append(row)
                    raw.write(json.dumps(row, sort_keys=True) + "\n")
                    raw.flush()
                    print(f'{pair:02d} {case} {variant}: wall={row["call_wall"]:.6f} cpu={row["call_cpu"]:.6f}', flush=True)
    after = dict(libraries={name: inventory(path) for name, path in libraries.items()},
        runtimes=runtimes(), rscript_sha256=sha(Path(rscript)),
        inputs={item["id"] + "-" + method: dict(sha256=sha(Path(item[method])),
            bytes=Path(item[method]).stat().st_size, rows=item["rows"], columns=item["columns"])
            for item in fixtures for method in args.methods}, workers={"read-screen.py": sha(Path(__file__)), "worker.R": sha(worker)})
    for key in after:
        if after[key] != before[key]:
            raise RuntimeError("Measurement binding changed: " + key)
    (args.work / "provenance-after.json").write_text(json.dumps(after, indent=2) + "\n")
    rng = random.Random(20261001)
    summary = []
    for case in dict.fromkeys(row["case"] for row in rows):
        for metric in ("call_wall", "call_cpu", "process_wall", "process_cpu", "maxrss_bytes"):
            old = {r["pair"]: r[metric] for r in rows if r["case"] == case and r["variant"] == "baseline"}
            new = {r["pair"]: r[metric] for r in rows if r["case"] == case and r["variant"] == "candidate"}
            ratios = [new[pair] / old[pair] for pair in old if old[pair] > 0 and new[pair] > 0]
            boot = sorted(statistics.median(rng.choices(ratios, k=len(ratios)))
                for _ in range(10000)) if len(ratios) == args.pairs else []
            summary.append(dict(case=case, metric=metric, pairs=args.pairs,
                baseline_median=statistics.median(old.values()), candidate_median=statistics.median(new.values()),
                resolved_pairs=len(ratios), paired_ratio=statistics.median(ratios) if boot else None,
                lower95=boot[249] if boot else None, upper95=boot[9749] if boot else None))
    with (args.work / "summary.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(summary[0]))
        writer.writeheader()
        writer.writerows(summary)


if __name__ == "__main__":
    main()
