#!/usr/bin/env python3
"""Run or summarize the six public-operation cases with preinstalled libraries."""
import argparse
import csv
import datetime
import hashlib
import json
import math
from pathlib import Path
import shutil
import statistics
import subprocess

HERE = Path(__file__).resolve().parent
CASES = {(width, missing, operation)
    for width, missing, operation in (
        ("int", "FALSE", "reverse_divide"),
        ("int", "TRUE", "reverse_divide"),
        ("int", "TRUE", "mixed_add"),
        ("int", "TRUE", "mixed_multiply"),
        ("float", "FALSE", "reverse_divide"),
        ("float", "TRUE", "reverse_divide"))}
REPRESENTATIONS = {"compact", "typed_double", "ordinary"}
STABLE = ("result_sha256", "missing_sha256", "missing_count", "result_storage",
          "input_sha256", "y_sha256", "mutation_checked", "cleared_sha256")


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def library_binding(library):
    package = library.resolve() / "dtatools"
    dlls = [p for p in (package / "libs").rglob("*")
            if p.is_file() and p.suffix in (".so", ".dll", ".dylib")]
    require(len(dlls) == 1, "Expected exactly one dtatools native library")
    files = [dlls[0], package / "DESCRIPTION", package / "NAMESPACE",
             package / "R/dtatools.rdb", package / "R/dtatools.rdx"]
    require(all(p.is_file() for p in files), "Installed package is incomplete")
    return {str(p.relative_to(package)): sha(p) for p in files}


def summarize(output, rounds):
    observations = {}
    stable = {}
    for variant in ("baseline", "candidate"):
        for round_number in range(1, rounds + 1):
            path = output / f"balanced-{variant}-round{round_number}.csv"
            with path.open(newline="") as stream:
                rows = list(csv.DictReader(stream))
            require(len(rows) == 18, "Expected 18 observations in " + str(path))
            seen = set()
            orders = {}
            for row in rows:
                case = tuple(row[k] for k in ("width", "missing", "operation"))
                representation = row["representation"]
                key = case + (representation,)
                require(case in CASES and representation in REPRESENTATIONS,
                        "Unexpected case in " + str(path))
                require(key not in seen, "Duplicate observation in " + str(path))
                seen.add(key)
                require(int(row["round"]) == round_number and int(row["n"]) == 1000000,
                        "Round or fixture length differs")
                orders.setdefault(case, []).append(int(row["order"]))
                reps = int(row["iterations"])
                require(reps > 0, "Invalid iteration count")
                require(int(row["native_calls"]) == (0 if representation == "ordinary" else reps),
                        "Native route was not qualified")
                for operand in ("", "y_"):
                    for state in ("compact", "materialized"):
                        require(row[operand + state + "_before"] == row[operand + state + "_after"],
                                "Operand state changed")
                require(row["compact_before"] == ("TRUE" if representation == "compact" else "FALSE"),
                        "Unexpected compact input state")
                require(row["materialized_before"] == "FALSE", "Input was materialized")
                require(row["mutation_checked"] == ("FALSE" if representation == "ordinary" else "TRUE"),
                        "Mutation qualification differs")
                facts = tuple(row[k] for k in STABLE)
                require(key not in stable or stable[key] == facts,
                        "Qualified results differ across rounds or variants")
                stable[key] = facts
                cpu = float(row["cpu"]) / reps
                require(math.isfinite(cpu) and cpu > 0, "Invalid CPU observation")
                observations[(variant, round_number) + key] = cpu
            require(all(sorted(values) == [1, 2, 3] for values in orders.values()),
                    "Representation order is incomplete")
    result = []
    median = statistics.median
    for case in sorted(CASES):
        values = lambda variant, representation: [
            observations[(variant, number) + case + (representation,)]
            for number in range(1, rounds + 1)]
        baseline = values("baseline", "compact")
        candidate = values("candidate", "compact")
        typed = values("candidate", "typed_double")
        ordinary = values("candidate", "ordinary")
        typed_baseline = values("baseline", "typed_double")
        ratios = [x / y for x, y in zip(candidate, typed)]
        result.append(dict(zip(("width", "missing", "operation"), case),
            baseline_ms=median(baseline) * 1000, candidate_ms=median(candidate) * 1000,
            gain=median(x / y for x, y in zip(baseline, candidate)),
            compact_typed=median(ratios),
            compact_ordinary=median(x / y for x, y in zip(candidate, ordinary)),
            typed_drift=median(x / y for x, y in zip(typed_baseline, typed)),
            typed_round_ratios=ratios))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--baseline-library", type=Path)
    parser.add_argument("--candidate-library", type=Path)
    parser.add_argument("--rounds", type=int, default=6)
    parser.add_argument("--summarize-only", action="store_true")
    args = parser.parse_args()
    require(args.rounds > 0 and args.rounds % 2 == 0, "Use a positive even number of balanced rounds")
    output = args.output.resolve()
    if args.summarize_only:
        require(output.is_dir(), "Existing observation directory required")
        write_json(output / "balanced-summary.json", summarize(output, args.rounds))
        print("Summarized", args.rounds * 36, "observations")
        return
    require(args.baseline_library and args.candidate_library, "Both installed library paths are required")
    libraries = {"baseline": args.baseline_library.resolve(), "candidate": args.candidate_library.resolve()}
    require(libraries["baseline"] != libraries["candidate"], "Use separate installed libraries")
    executable = shutil.which("Rscript")
    require(executable is not None, "Rscript is required")
    worker = HERE / "worker.R"
    binding = {name: library_binding(path) for name, path in libraries.items()}
    output.mkdir(parents=True, exist_ok=False)
    receipt = dict(started=now(), worker_sha256=sha(worker), controller_sha256=sha(Path(__file__)),
        libraries={name: str(path) for name, path in libraries.items()},
        library_before=binding, commands=[],
        protocol="Sequential fresh-R workers; six cases, three representations; alternating AB/BA rounds; CPU per call.")
    for number in range(1, args.rounds + 1):
        variants = ("baseline", "candidate") if number % 2 else ("candidate", "baseline")
        for variant in variants:
            path = output / f"balanced-{variant}-round{number}.csv"
            command = [executable, "--vanilla", str(worker), str(libraries[variant]),
                       str(number), str(path), variant, "timed"]
            started = now()
            run = subprocess.run(command, text=True, capture_output=True)
            receipt["commands"].append(dict(round=number, variant=variant, command=command,
                started=started, ended=now(), exit_code=run.returncode,
                stdout=run.stdout, stderr=run.stderr))
            write_json(output / "balanced-run-receipt.json", receipt)
            require(run.returncode == 0, "Worker failed; see balanced-run-receipt.json")
            print(variant, "round", number, run.stdout.strip(), flush=True)
    receipt["library_after"] = {name: library_binding(path) for name, path in libraries.items()}
    require(receipt["library_after"] == binding, "Installed library changed during timing")
    require(sha(worker) == receipt["worker_sha256"], "Worker changed during timing")
    require(sha(Path(__file__)) == receipt["controller_sha256"], "Controller changed during timing")
    write_json(output / "balanced-summary.json", summarize(output, args.rounds))
    receipt.update(ended=now(), observations=args.rounds * 36, exit_code=0)
    write_json(output / "balanced-run-receipt.json", receipt)


if __name__ == "__main__":
    main()
