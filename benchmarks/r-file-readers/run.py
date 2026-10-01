"""Fresh-process R reader comparison. Run without other builds or benchmarks."""
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

HERE = Path(__file__).resolve().parent
METHODS = {
    "base_csv": ("csv", "base"), "base_rds": ("rds", "base"),
    "fread": ("csv", "data.table"), "readr": ("csv", "readr"),
    "vroom_eager": ("csv", "vroom"), "vroom_lazy": ("csv", "vroom"),
    "haven": ("dta", "haven"), "arrow": ("feather", "arrow"),
    "fst": ("fst", "fst"), "qs2": ("qs2", "qs2"),
    "dtatools_dta_tibble": ("dta", "dtatools"),
    "dtatools_dta_dibble": ("dta", "dtatools"),
    "dtatools_arrow_tibble": ("arrow", "dtatools"),
    "dtatools_arrow_dibble": ("arrow", "dtatools"),
}
SERIAL = {"base_csv", "base_rds", "haven"}
METRICS = ("read_wall", "read_cpu", "consume_wall", "consume_cpu",
           "total_wall", "total_cpu", "process_wall", "process_cpu", "maxrss_bytes")


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def inventory(library):
    package = library / "dtatools"
    return {str(path.relative_to(package)): sha(path)
            for path in sorted(package.rglob("*")) if path.is_file()}


def environment(library):
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("DTATOOLS_EXPERIMENT_", "DTA_READ_PERF_"))}
    extra_libraries = env.get("R_LIBS", "")
    env.update(R_LIBS=str(library) + (os.pathsep + extra_libraries if extra_libraries else ""),
               DTATOOLS_BENCH_LIB=str(library))
    return env


def runtime(rscript, library):
    value = subprocess.check_output([rscript, "--vanilla", str(HERE / "runtime.R")],
        env=environment(library), text=True, stderr=subprocess.PIPE)
    result = {"packages": {}, "default_threads": {}}
    for line in value.splitlines():
        fields = line.split("\t")
        if fields[0] == "R":
            result.update(r_version=fields[1], r_platform=fields[2])
            executable = Path(fields[3]) / "exec/R"
            if executable.is_file():
                result["r_executable_sha256"] = sha(executable)
        elif fields[0] == "PACKAGE":
            result["packages"][fields[1]] = {"version": fields[2]}
            if fields[2] != "unavailable":
                result["packages"][fields[1]]["description_sha256"] = sha(Path(fields[3]) / "DESCRIPTION")
        elif fields[0] == "ALTREP":
            result["vroom_altrep_flags"] = int(fields[1])
        elif fields[0] == "THREADS":
            result["default_threads"][fields[1]] = int(fields[2])
    if "r_version" not in result or "dtatools" not in result["packages"]:
        raise RuntimeError("Incomplete runtime inventory")
    return result


def validate_record(fields, fixture):
    if len(fields) != 12:
        raise RuntimeError("Invalid measurement field count")
    values = list(map(float, fields[1:10]))
    if any(not math.isfinite(value) or value < 0 for value in values):
        raise RuntimeError("Invalid measurement clock")
    if tuple(map(int, fields[10:12])) != (fixture["rows"], fixture["columns"]):
        raise RuntimeError("Invalid measurement shape")
    return dict(read_wall=values[0], read_cpu=values[1] + values[2],
                consume_wall=values[3], consume_cpu=values[4] + values[5],
                total_wall=values[6], total_cpu=values[7] + values[8])


def write_summaries(work, rows, pairs):
    rng = random.Random(20261001)
    summaries = []
    paired = []
    for case in dict.fromkeys(row["case"] for row in rows):
        selected = [row for row in rows if row["case"] == case]
        for variant in dict.fromkeys(row["variant"] for row in selected):
            values = [row for row in selected if row["variant"] == variant]
            summaries.append(dict(case=case, variant=variant, observations=len(values),
                **{metric + "_median": statistics.median(row[metric] for row in values)
                   for metric in METRICS}))
        if {row["variant"] for row in selected} != {"baseline", "candidate"}:
            continue
        for metric in METRICS:
            old = {row["pair"]: row[metric] for row in selected if row["variant"] == "baseline"}
            new = {row["pair"]: row[metric] for row in selected if row["variant"] == "candidate"}
            ratios = [new[pair] / old[pair] for pair in old if old[pair] > 0 and new[pair] > 0]
            boot = sorted(statistics.median(rng.choices(ratios, k=len(ratios)))
                for _ in range(10000)) if len(ratios) == pairs else []
            paired.append(dict(case=case, metric=metric, pairs=pairs,
                baseline_median=statistics.median(old.values()),
                candidate_median=statistics.median(new.values()), resolved_pairs=len(ratios),
                paired_ratio=statistics.median(ratios) if boot else None,
                lower95=boot[249] if boot else None, upper95=boot[9749] if boot else None))
    for name, values in (("summary.csv", summaries), ("paired-summary.csv", paired)):
        if values:
            with (work / name).open("w", newline="") as stream:
                writer = csv.DictWriter(stream, fieldnames=list(values[0]))
                writer.writeheader()
                writer.writerows(values)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("baseline", "candidate", "fixtures", "work"):
        parser.add_argument("--" + name, type=lambda x: Path(x).resolve(), required=True)
    parser.add_argument("--methods", nargs="+", choices=tuple(METHODS), default=list(METHODS))
    parser.add_argument("--cases", nargs="+")
    parser.add_argument("--threads", nargs="+", type=int, default=[0])
    parser.add_argument("--modes", nargs="+", choices=("read", "consume"), default=["read", "consume"])
    parser.add_argument("--pairs", type=int, default=6)
    parser.add_argument("--qualify-only", action="store_true")
    parser.add_argument("--build-records", "--build-record", dest="build_record", type=lambda x: Path(x).resolve())
    args = parser.parse_args()
    if args.pairs <= 0 or args.pairs % 2 or any(n < 0 for n in args.threads):
        parser.error("Use a positive even pair count and nonnegative thread limits")
    if args.baseline == args.candidate:
        parser.error("Use independently installed libraries")
    for values in (args.methods, args.threads, args.modes):
        if len(set(values)) != len(values):
            parser.error("Methods, thread limits, and modes must be unique")
    if sys.platform not in ("darwin", "linux"):
        parser.error("wait4 RSS units are supported only on macOS and Linux")
    rscript = shutil.which("Rscript")
    if rscript is None:
        parser.error("Rscript is unavailable")
    rscript = str(Path(rscript).resolve())
    libraries = dict(baseline=args.baseline, candidate=args.candidate)
    for library in libraries.values():
        if not (library / "dtatools/DESCRIPTION").is_file():
            parser.error("Missing installed dtatools library")
    manifest = json.loads(args.fixtures.read_text())
    fixtures = manifest["reads"]
    if (not fixtures or len({item["id"] for item in fixtures}) != len(fixtures) or
            any(not re.fullmatch(r"[A-Za-z0-9_-]+", item["id"]) for item in fixtures)):
        parser.error("Provide unique, nonempty alphanumeric fixture identifiers")
    if args.cases:
        if set(args.cases) - {item["id"] for item in fixtures}:
            parser.error("Unknown fixture identifier")
        fixtures = [item for item in fixtures if item["id"] in args.cases]
    for item in fixtures:
        if any(not isinstance(item[field], int) or item[field] <= 0 for field in ("rows", "columns")):
            parser.error("Fixture dimensions must be positive integers")
        if item.get("qualification", "signature") not in ("values", "signature"):
            parser.error("Unknown qualification mode")
        if item.get("qualification") == "values" and not Path(item.get("reference", "")).is_file():
            parser.error("Values qualification requires an independent reference RDS")
    args.work.mkdir(parents=True, exist_ok=False, mode=0o700)

    def bindings():
        return dict(build_record_sha256=sha(args.build_record) if args.build_record else None,
            libraries={name: inventory(path) for name, path in libraries.items()},
            runtimes={name: runtime(rscript, path) for name, path in libraries.items()},
            rscript_sha256=sha(rscript),
            inputs={item["id"]: {key: dict(sha256=sha(Path(item[key])),
                        bytes=Path(item[key]).stat().st_size)
                    for key in sorted({value[0] for value in METHODS.values()} | {"reference"})
                    if key in item} for item in fixtures},
            workers={name: sha(HERE / name) for name in
                     ("run.py", "worker.R", "common.R", "runtime.R", "prepare.R", "prepare-wide.R")})

    before = bindings()
    if args.build_record:
        build_record = json.loads(args.build_record.read_text())
        if build_record.get("libraries") != before["libraries"]:
            raise RuntimeError("Build record installed libraries do not match supplied libraries")
    before.update(host=dict(platform=platform.platform(), machine=platform.machine(),
        logical_cpus=os.cpu_count(), thread_environment={key: os.environ.get(key) for key in (
            "OMP_NUM_THREADS", "OMP_THREAD_LIMIT", "OPENBLAS_NUM_THREADS", "ARROW_NUM_THREADS",
            "VECLIB_MAXIMUM_THREADS", "MKL_NUM_THREADS", "RCPP_PARALLEL_NUM_THREADS",
            "R_DATATABLE_NUM_THREADS", "R_DATATABLE_NUM_PROCS_PERCENT", "VROOM_THREADS")},
        vroom_altrep_environment={key: value for key, value in os.environ.items()
            if key.startswith("VROOM_USE_ALTREP")}),
        fixtures=[dict(id=item["id"], rows=item["rows"], columns=item["columns"],
            qualification=item.get("qualification", "signature")) for item in fixtures],
        generation=manifest.get("generation"),
        protocol=dict(pairs=args.pairs, threads=args.threads, modes=args.modes,
            methods=args.methods, cache="warm filesystem", reference_variants="baseline-library dependencies",
            boundary="first public reader call plus as_tibble where required for external readers; separate fresh read-only and full-consumption processes",
            endpoints="external readers return tibble; dtatools explicit tibble and dibble",
            clocks="R proc.time elapsed, user.self and sys.self in identical intervals; wait4 whole-process CPU/RSS",
            consumption="traversal of every cell with numeric sums/NA counts and string byte lengths",
            checksums="dtatools read_arrow verify=TRUE; qs2 validate_checksum=TRUE; generic Feather has no dtatools checksums",
            missing_packages="recorded unavailable; no substitution"))
    (args.work / "provenance-before.json").write_text(json.dumps(before, indent=2) + "\n")
    runtime_info = before["runtimes"]["baseline"]
    cases, unavailable = [], []
    for item in fixtures:
        for method in args.methods:
            key, package = METHODS[method]
            if package != "base" and runtime_info["packages"][package]["version"] == "unavailable":
                unavailable.append(dict(fixture=item["id"], method=method, reason="package unavailable"))
                continue
            if key not in item:
                unavailable.append(dict(fixture=item["id"], method=method, reason="input format not supplied"))
                continue
            if item.get("qualification", "signature") == "signature" and package != "dtatools":
                unavailable.append(dict(fixture=item["id"], method=method,
                    reason="private signature qualification compares dtatools variants only"))
                continue
            limits = args.threads[:1] if method in SERIAL else args.threads
            for threads in limits:
                for mode in args.modes:
                    cases.append((item, method, threads, mode))
    (args.work / "unavailable.json").write_text(json.dumps(unavailable, indent=2) + "\n")
    if not cases:
        raise RuntimeError("No runnable reader cases")

    def invoke(item, method, threads, mode, variant, key, qualify=False):
        path_key = METHODS[method][0]
        qual_mode = item.get("qualification", "signature")
        command = [rscript, "--vanilla", str(HERE / "worker.R"),
            "qualify-" + qual_mode if qualify else mode, method, item[path_key], str(threads),
            str(item["rows"]), str(item["columns"]), item.get("reference", "-")]
        log = args.work / (key + ".log")
        started = time.monotonic()
        with log.open("w") as stream:
            process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
                env=environment(libraries["baseline" if variant == "reference" else variant]))
            try:
                _, status, usage = os.wait4(process.pid, 0)
                process.returncode = os.waitstatus_to_exitcode(status)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
        process_wall = time.monotonic() - started
        if process.returncode:
            raise RuntimeError("Reader worker failed; inspect private log " + key)
        prefix = "QUALIFIED\t" if qualify else "MEASURE\t"
        records = [line.split("\t") for line in log.read_text().splitlines() if line.startswith(prefix)]
        if len(records) != 1:
            raise RuntimeError("Missing or duplicate worker record: " + key)
        if qualify:
            if len(records[0]) != 3 or not re.fullmatch(r"[a-f0-9]{64}", records[0][2]):
                raise RuntimeError("Invalid qualification consumption hash")
            return dict(qualification=qual_mode, signature=records[0][1],
                consumption_sha256=records[0][2], log_sha256=sha(log))
        return dict(**validate_record(records[0], item), process_wall=process_wall,
            process_cpu=usage.ru_utime + usage.ru_stime,
            maxrss_bytes=usage.ru_maxrss * (1 if sys.platform == "darwin" else 1024), log_sha256=sha(log))

    qualifications, signatures, consumption_signatures = {}, {}, {}
    for item, method, threads, _ in cases:
        key = f'{item["id"]}-{method}-t{threads}'
        if key in qualifications:
            continue
        variants = ("baseline", "candidate") if method.startswith("dtatools_") else ("reference",)
        qualifications[key] = {}
        for variant in variants:
            record = invoke(item, method, threads, "read", variant, "qualify-" + key + "-" + variant, True)
            qualifications[key][variant] = record
            if consumption_signatures.setdefault(item["id"], record["consumption_sha256"]) != record["consumption_sha256"]:
                raise RuntimeError("Full-consumption results differ: " + key)
            if method.startswith("dtatools_"):
                if signatures.setdefault(item["id"], record["signature"]) != record["signature"]:
                    raise RuntimeError("Complete dataset signatures differ: " + key)
        print("Qualified " + key, flush=True)
    (args.work / "qualification.json").write_text(json.dumps(qualifications, indent=2) + "\n")
    rows = []
    if not args.qualify_only:
        with (args.work / "raw.jsonl").open("w") as raw:
            for pair in range(1, args.pairs + 1):
                offset = (pair - 1) % len(cases)
                ordered = cases[offset:] + cases[:offset]
                if pair % 2 == 0:
                    ordered = list(reversed(ordered))
                for item, method, threads, mode in ordered:
                    case = f'{item["id"]}-{method}-t{threads}-{mode}'
                    variants = (["baseline", "candidate"] if method.startswith("dtatools_") else ["reference"])
                    if pair % 2 == 0:
                        variants.reverse()
                    for position, variant in enumerate(variants, 1):
                        row = dict(case=case, fixture=item["id"], method=method, threads=threads,
                            mode=mode, pair=pair, position=position, variant=variant,
                            **invoke(item, method, threads, mode, variant, f'{pair:02d}-{case}-{variant}'))
                        rows.append(row)
                        raw.write(json.dumps(row, sort_keys=True) + "\n")
                        raw.flush()
                        print(f'{pair:02d} {case} {variant}: read={row["read_wall"]:.6f} '
                            f'total={row["total_wall"]:.6f} cpu={row["total_cpu"]:.6f}', flush=True)
    after = bindings()
    for key in after:
        if after[key] != before[key]:
            raise RuntimeError("Measurement binding changed: " + key)
    (args.work / "provenance-after.json").write_text(json.dumps(after, indent=2) + "\n")
    if rows:
        write_summaries(args.work, rows, args.pairs)


if __name__ == "__main__":
    main()
