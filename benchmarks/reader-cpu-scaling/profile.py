#!/usr/bin/env python3
"""Optional macOS stack sampling. Run only after all clean timing batches."""
import argparse
import collections
import csv
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from run import HERE, sha, overlapping_paths

SAMPLER_TIMEOUT_SECONDS = 60


def leaf_counts(text):
    """Accept only the collapsed leaf section, with no paths or addresses."""
    active = False
    counts = collections.Counter()
    rejected = 0
    for line in text.splitlines():
        if line.startswith("Sort by top of stack"):
            active = True
            continue
        if not active:
            continue
        if line.startswith("Binary Images:"):
            break
        match = re.match(r"\s*(\d+)\s+(.+?)\s*$", line)
        if match:
            count, label = int(match.group(1)), match.group(2)
        else:
            match = re.match(r"\s*(.+?)\s+(\d+)\s*$", line)
            if not match:
                continue
            label, count = match.group(1), int(match.group(2))
        label = label.split(" (in ", 1)[0].strip()
        # No raw addresses, paths, runtime values or opaque unnamed frames are
        # published. Unknown formats remain in the private raw report only.
        if ("/" in label or "\\" in label or "0x" in label or
                not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_:<> ,~*&.\[\](){}+=$-]*", label)):
            rejected += count
            continue
        counts[label] += count
    return counts, rejected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("library", "dta", "output", "work", "timing-provenance"):
        parser.add_argument("--" + name, type=lambda x: Path(x).resolve(), required=True)
    parser.add_argument("--threads", choices=(0, 1), type=int, required=True)
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--columns", type=int, required=True)
    args = parser.parse_args()
    if overlapping_paths(args.output, args.work):
        parser.error("Keep public aggregates separate from private stacks")
    args.output.mkdir(parents=True, exist_ok=False)
    args.work.mkdir(parents=True, exist_ok=False)
    timing = json.loads(args.timing_provenance.read_text())
    completion_path = args.timing_provenance.with_name("completion.json")
    completion = json.loads(completion_path.read_text())
    if not completion["final_bindings_matched"] or completion["smoke"]:
        raise ValueError("Profile requires a completed non-smoke timing run")
    input_hash = sha(args.dta)
    package = args.library / "dtatools"

    def installed_inventory():
        return {str(path.relative_to(package)): sha(path)
                for path in sorted(package.rglob("*")) if path.is_file()}

    installed = installed_inventory()
    if (input_hash != timing["inputs"]["dta"]["sha256"] or
            installed != timing["installed"] or
            dict(rows=args.rows, columns=args.columns) != timing["protocol"]["dimensions"]):
        raise ValueError("Profile input or candidate DLL differs from the timing run")
    environment = {key: value for key, value in os.environ.items()
        if not key.startswith(("DTATOOLS_EXPERIMENT_", "DTA_READ_PERF_"))}
    environment.update(R_LIBS=str(args.library), DTATOOLS_BENCH_LIB=str(args.library))
    command = [shutil.which("Rscript"), "--vanilla", str(HERE / "profile.R"),
        str(args.dta), str(args.threads), str(args.rows), str(args.columns)]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, env=environment, cwd=args.work)
    raw = args.work / "sample.txt"
    worker_lines = []
    try:
        while True:
            line = process.stdout.readline()
            if not line:
                raise RuntimeError("Profile worker stopped before readiness")
            worker_lines.append(line)
            if line.strip() == "READY":
                break
        sampler_exit = None
        sampler_timed_out = False
        with (args.work / "sampler.log").open("w") as stream:
            try:
                sampler = subprocess.run(["/usr/bin/sample", str(process.pid), "5", "1",
                    "-mayDie", "-file", str(raw)], stdout=stream, stderr=subprocess.STDOUT,
                    timeout=SAMPLER_TIMEOUT_SECONDS)
                sampler_exit = sampler.returncode
            except subprocess.TimeoutExpired:
                sampler_timed_out = True
                stream.write("\nSampler exceeded the 60-second limit.\n")
        tail, _ = process.communicate(timeout=120)
        worker_lines.append(tail)
        if process.returncode:
            raise RuntimeError("Profile worker failed")
        if input_hash != sha(args.dta) or installed != installed_inventory():
            raise ValueError("Profile input or candidate DLL changed")
        counts, rejected = (leaf_counts(raw.read_text())
            if raw.exists() and not sampler_timed_out else ({}, 0))
        with (args.output / "leaf-functions.csv").open("w", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(("function", "stack_sample_count"))
            writer.writerows(sorted(counts.items(), key=lambda pair: (-pair[1], pair[0])))
        record = dict(available=sampler_exit == 0 and bool(counts),
            sampler_exit=sampler_exit, sampler_timed_out=sampler_timed_out,
            sampler_timeout_seconds=SAMPLER_TIMEOUT_SECONDS, requested_threads=args.threads,
            sample_seconds=5, sampling_interval_ms=1, worker_minimum_seconds=12,
            dimensions=dict(rows=args.rows, columns=args.columns),
            input_sha256=input_hash, package_dll_sha256=installed["libs/dtatools.so"],
            full_installed_inventory_matched=True,
            timing_provenance_sha256=sha(args.timing_provenance),
            timing_completion_sha256=sha(completion_path),
            final_bindings_matched=True,
            workers={name: sha(HERE / name) for name in ("profile.R", "profile.py")},
            excluded_opaque_stack_samples=rejected,
            interpretation="Repeated public reads include allocation, collection and loop overhead. All threads are sampled, including waits. Counts are not CPU-time percentages or energy measurements.")
        (args.output / "provenance.json").write_text(json.dumps(record, indent=2) + "\n")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        (args.work / "worker.log").write_text("".join(worker_lines))


if __name__ == "__main__":
    main()
