#!/usr/bin/env python3
"""Refresh India DTA/Arrow timings; retain dated comparator results unchanged."""
import argparse
import csv
from datetime import datetime, timezone
import importlib.util
import io
import json
import math
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
from run import absolute_path, child, sha, write_csv

SPEC = importlib.util.spec_from_file_location(
    "india_refresh_builds", HERE.parent / "r-file-readers/record-builds.py")
BUILDS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDS)
require = BUILDS.require
METHODS = ("read_dta_tibble", "read_arrow_tibble", "read_dta_dibble", "read_arrow_dibble")
HISTORICAL = HERE / "results-2026-09-16-india"
EXPECTED_INPUTS = {
    "dta": dict(bytes=5196403097, sha256="53acf9bc37e4c207e026379f156758bfc47020cbdbf0aa26667e9e1a617ab3fc"),
    "arrow": dict(bytes=5559834970, sha256="f1449a871b3fabbeed303b04a2dc0b884e4a76c7f213d7f095e0b25acd76dfcc"),
}


def now():
    return datetime.now(timezone.utc).isoformat()


def write_public(path, value):
    path.write_bytes(BUILDS.public_bytes(value))


def round_orders():
    result = []
    for shift in range(5):
        offset = shift % len(METHODS)
        forward = METHODS[offset:] + METHODS[:offset]
        result.extend((forward, tuple(reversed(forward))))
    return result


def identity(path):
    require(path.is_file() and not path.is_symlink(), "Input must be an ordinary file")
    return dict(bytes=path.stat().st_size, sha256=sha(path))


def validate_inputs(inputs, rows, columns, smoke):
    require(type(rows) is int and rows > 0 and type(columns) is int and columns > 0,
            "Expected dimensions must be positive integers")
    if not smoke:
        require(inputs == EXPECTED_INPUTS and (rows, columns) == (724115, 5972),
                "Full refresh requires the exact historical India files and dimensions")


def validate_qualification(records, rows, columns):
    require(set(records) == set(METHODS), "Incomplete semantic qualification")
    for method, record in records.items():
        output = method.rsplit("_", 1)[1]
        require((record.get("rows"), record.get("columns"), record.get("output")) ==
                (rows, columns, output), "Qualification dimensions or container differ")
        require(record.get("warnings") == [], "Qualification produced warnings")
        signature = record.get("signature")
        require(isinstance(signature, str) and bool(signature), "Missing complete signature")
    for output in ("tibble", "dibble"):
        require(records["read_dta_" + output]["signature"] ==
                records["read_arrow_" + output]["signature"],
                "DTA/Arrow values or metadata differ within output container")


def validate_observation(record, rows, columns, output, smoke):
    require((record.get("rows"), record.get("columns"), record.get("output")) ==
            (rows, columns, output), "Timed dimensions or container differ")
    for name in ("elapsed_seconds", "read_cpu_seconds", "process_cpu_seconds", "peak_rss_bytes"):
        value = record.get(name)
        require(type(value) in (int, float) and math.isfinite(value) and value >= 0,
                "Invalid timing or resource value")
        if name in ("process_cpu_seconds", "peak_rss_bytes") or (name == "elapsed_seconds" and not smoke):
            require(value > 0, "Required measurement is zero")


def summarize(observations, schedule):
    expected = [(iteration, position, method) for iteration, order in enumerate(schedule, 1)
                for position, method in enumerate(order, 1)]
    require([(r["iteration"], r["position"], r["method"]) for r in observations] == expected,
            "Incomplete, duplicate, or reordered observations")
    result = []
    for method in METHODS:
        rows = [r for r in observations if r["method"] == method]
        wall = [r["elapsed_seconds"] for r in rows]
        result.append(dict(method=method, observations=len(rows),
            median_seconds=statistics.median(wall), min_seconds=min(wall), max_seconds=max(wall),
            median_read_cpu_seconds=statistics.median(r["read_cpu_seconds"] for r in rows),
            median_process_cpu_seconds=statistics.median(r["process_cpu_seconds"] for r in rows),
            median_peak_rss_bytes=statistics.median(r["peak_rss_bytes"] for r in rows)))
    return result


def historical_comparators(summary_bytes):
    rows = list(csv.DictReader(io.StringIO(summary_bytes.decode())))
    require(len(rows) == 4 and {r["method"] for r in rows} == {"read_dta", "read_arrow", "haven", "stata"},
            "Unexpected historical comparison table")
    retained = [dict(row, measurement_date="2026-09-16")
                for row in rows if row["method"] in ("haven", "stata")]
    require(len(retained) == 2 and all(r["observations"] == "10" for r in retained),
            "Historical comparator observations differ")
    return retained


def runtime(rscript, library, environment):
    code = '''jsonlite::toJSON(NULL); .libPaths(c(commandArgs(TRUE)[1], .libPaths()));
      stopifnot(requireNamespace("dtatools", quietly=TRUE));
      packages <- sort(loadedNamespaces());
      cat("\\nRUNTIME\\t", jsonlite::toJSON(list(R=R.version.string,
        platform=R.version$platform, executable=normalizePath(file.path(R.home("bin"), "exec/R")),
        packages=setNames(lapply(packages, function(x) list(version=as.character(packageVersion(x)),
          path=if (x == "base") file.path(R.home("library"), "base")
            else getNamespaceInfo(x, "path"))), packages)), auto_unbox=TRUE), sep="")'''
    output = subprocess.check_output([str(rscript), "--vanilla", "-e", code, str(library)],
                                     env=environment, text=True)
    records = [line.removeprefix("RUNTIME\t") for line in output.splitlines() if line.startswith("RUNTIME\t")]
    require(len(records) == 1, "Missing runtime binding")
    value = json.loads(records[0])
    value["r_executable_sha256"] = sha(Path(value.pop("executable")))
    for package in value["packages"].values():
        directory = Path(package.pop("path"))
        files = {p.relative_to(directory).as_posix(): sha(p)
                 for p in sorted(directory.rglob("*")) if p.is_file()}
        package["installed_inventory_sha256"] = BUILDS.sha_bytes(BUILDS.json_bytes(files))
        package["installed_files"] = len(files)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("candidate-build-work", "dta", "arrow", "output"):
        parser.add_argument("--" + name, type=absolute_path, required=True)
    parser.add_argument("--rows", type=int, default=724115)
    parser.add_argument("--columns", type=int, default=5972)
    parser.add_argument("--smoke", action="store_true", help="One round on a small fixture; not publishable timings")
    args = parser.parse_args()
    require(not args.output.exists(), "Output must be a new directory")
    require(args.candidate_build_work.is_dir(), "Missing candidate build")
    library = args.candidate_build_work / "library"
    rscript = Path(shutil.which("Rscript")).resolve()
    environment = {k: v for k, v in os.environ.items()
                   if not k.startswith(("DTATOOLS_EXPERIMENT_", "DTA_READ_PERF_"))}
    scripts = (Path(__file__), HERE / "refresh-india.R", HERE / "run.py")
    schedule = round_orders()[:1] if args.smoke else round_orders()

    def binding():
        receipt, _, receipt_hash = BUILDS.verified_receipt(args.candidate_build_work, "candidate")
        inputs = {kind: identity(getattr(args, kind)) for kind in ("dta", "arrow")}
        validate_inputs(inputs, args.rows, args.columns, args.smoke)
        return dict(build_receipt_sha256=receipt_hash, build_receipt=receipt, inputs=inputs,
            workers={p.relative_to(ROOT).as_posix(): sha(p) for p in scripts},
            build_verifier=BUILDS.artifact_hashes(), Rscript_sha256=sha(rscript),
            runtime=runtime(rscript, library, environment), host=platform.platform(), cpu_count=os.cpu_count(),
            historical_artifacts={name: sha(HISTORICAL / name)
                                  for name in ("summary.csv", "provenance.json", "qualification.json")},
            thread_environment={k: environment[k] for k in ("OMP_NUM_THREADS", "RAYON_NUM_THREADS",
                "R_PARALLEL_NUM_THREADS", "OPENBLAS_NUM_THREADS", "VECLIB_MAXIMUM_THREADS") if k in environment})

    initial = binding()  # Full input hashing also warms the filesystem cache.
    args.output.mkdir(parents=True, mode=0o700)
    (args.output / "config-private.json").write_text(json.dumps({k: str(v) if isinstance(v, Path) else v
        for k, v in vars(args).items()}, indent=2) + "\n")
    write_public(args.output / "binding-before.json", initial)
    write_public(args.output / "protocol.json", dict(smoke=args.smoke, rounds=len(schedule), orders=schedule,
        calls_per_process=1, cache="warm filesystem; hashing before qualification and before timing",
        read_wall="public reader call including first initialization; no GC or compiled timing closure",
        read_cpu="user.self plus sys.self over exactly the read-wall interval",
        process_cpu="wait4 user plus system CPU for the whole fresh process",
        peak_rss="wait4 maximum resident bytes for the whole fresh process",
        initialization="jsonlite job parsing before dtatools namespace loading, matching historical india.R",
        threads=0, use_numeric_altrep=True, arrow_verify=True, arrow_profile=True,
        output_containers=["tibble", "dibble"], dimensions=dict(rows=args.rows, columns=args.columns),
        historical_comparators_run=False, historical_comparator_date="2026-09-16",
        conversion="none; supplied smoke Arrow" if args.smoke else "none; exact historical Arrow bytes",
        qualification="full DTA/Arrow signatures within each output; zero warnings; separate untimed processes"))

    def execute(method, mode, key):
        reader, container = method.rsplit("_", 1)
        directory = args.output / key
        directory.mkdir()
        job = dict(library=str(library), method=reader, output=container, mode=mode,
                   path=str(args.arrow if reader == "read_arrow" else args.dta),
                   rows=args.rows, columns=args.columns)
        (directory / "job-private.json").write_text(json.dumps(job))
        result_path = directory / "result.json"
        resources = child([str(rscript), "--vanilla", str(HERE / "refresh-india.R"),
            str(directory / "job-private.json"), str(result_path)], directory, environment)
        result = json.loads(result_path.read_text())
        return result, resources

    qualifications = {method: execute(method, "qualify", "qualify-" + method)[0] for method in METHODS}
    validate_qualification(qualifications, args.rows, args.columns)
    write_public(args.output / "qualification.json", qualifications)
    require(binding() == initial, "Bindings changed during qualification")
    write_public(args.output / "QUALIFIED.json", dict(completed_utc=now(),
        qualification_sha256=sha(args.output / "qualification.json"), binding_sha256=sha(args.output / "binding-before.json")))
    started = now()
    write_public(args.output / "MEASUREMENT_STARTED.json", dict(started_utc=started))
    observations = []
    for iteration, order in enumerate(schedule, 1):
        for position, method in enumerate(order, 1):
            print(f"START {iteration}/{len(schedule)} {method} position {position}/4", flush=True)
            result, resources = execute(method, "read", f"{iteration:02d}-{method}")
            row = dict(iteration=iteration, position=position, method=method, **result, **resources)
            validate_observation(row, args.rows, args.columns, method.rsplit("_", 1)[1], args.smoke)
            observations.append(row)
            temporary = args.output / "observations.tmp"
            write_csv(temporary, observations)
            temporary.replace(args.output / "observations.csv")
            print(f"DONE {len(observations)}/{4 * len(schedule)}: {row['elapsed_seconds']:.3f}s, "
                  f"{row['process_cpu_seconds']:.3f}s process CPU, {row['peak_rss_bytes'] / 1e9:.3f} GB RSS", flush=True)
    finished = now()
    final = binding()
    write_public(args.output / "binding-after.json", final)
    require(final == initial, "Source, library, runtime, input, historical table, or worker binding changed")
    summary = summarize(observations, schedule)
    for row in summary:
        row["measurement_date"] = started[:10]
    write_csv(args.output / "summary.csv", summary)
    historical_bytes = (HISTORICAL / "summary.csv").read_bytes()
    (args.output / "historical-summary.csv").write_bytes(historical_bytes)
    write_csv(args.output / "historical-comparators.csv", historical_comparators(historical_bytes))
    write_public(args.output / "completion.json", dict(started_utc=started, finished_utc=finished,
        smoke=args.smoke, successful_reads=len(observations), qualification_reads=len(qualifications),
        final_bindings_matched=True, artifacts={name: sha(args.output / name) for name in
            ("binding-before.json", "binding-after.json", "protocol.json", "qualification.json", "QUALIFIED.json",
             "MEASUREMENT_STARTED.json", "observations.csv", "summary.csv", "historical-summary.csv", "historical-comparators.csv")}))
    (args.output / "COMPLETE").write_text(f"{len(observations)} successful fresh reads; smoke={args.smoke}; bindings matched.\n")
    print("COMPLETE: all observations retained; final bindings matched", flush=True)


if __name__ == "__main__":
    main()
