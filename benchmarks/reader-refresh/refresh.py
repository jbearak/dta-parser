#!/usr/bin/env python3
"""Refresh dtatools measurements using archived, unchanged comparators."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from driver_common import (require, add_binding_arguments, child_environment, latest_job_attempts,
                           load_jobs, read_cpu, required_read_keys, run_child,
                           source_binding, warm_read_schedule)

parser = argparse.ArgumentParser()
parser.add_argument("library", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--cache", type=Path, default=Path("/opt/aww_cache"))
parser.add_argument("--phase", choices=["corpus", "reads"], required=True)
add_binding_arguments(parser)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
os.chdir(root)
source_root = args.source_root.resolve() if args.source_root else root
data_root = args.data_root.resolve()
subprocess.run(["git", "diff", "--exit-code", "HEAD", "--", "r-package/dtatools"],
               cwd=source_root, check=True)
args.output = args.output.resolve()
args.library = args.library.resolve()
args.output.mkdir(parents=True, exist_ok=True)
archive = data_root / "r-corpus-performance/20260824T142432Z"
release_inventory = data_root / "r-corpus-performance/20260824T201626Z/inventory.tsv"
environment = child_environment(args.library)
rscript = shutil.which("Rscript")


def table(path):
    """Read a retained tab-separated inventory or measurement artifact."""
    with path.open() as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def sha(path):
    """Hash retained inputs without loading the whole file into memory."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_table(path, rows):
    """Persist corpus progress using the existing tab-separated schema."""
    with path.open("w") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def child(key, script, *arguments, warm=None):
    """Launch a local reader worker with optional balanced-cohort metadata."""
    return run_child(args.output, key, root / script, arguments, environment, warm=warm)


inventory = table(archive / "inventory.tsv")
release_rows = {r["id"]: r for r in table(release_inventory)}
raw = table(archive / "raw.tsv")
old = {(r["id"], r["reader"]): r for r in raw}
for row in inventory:
    release = release_rows[row["id"]]
    require(all(row[k] == release[k] for k in ("corpus", "relative_path", "bytes", "mtime")), 'retained corpus inventory differs from the release inventory')
    row["release"] = release["release"]
    path = args.cache / row["relative_path"]
    stat = path.stat()
    require(path.is_file() and not path.is_symlink(), 'corpus input is not a regular file')
    require(stat.st_size == int(row["bytes"]) and abs(stat.st_mtime - float(row["mtime"])) < 1e-5, 'corpus input size or modification time changed')

# Bind every retained read/projection input before any timed child starts.
phase_inputs = {}
phase_artifacts = {"inventory": archive / "inventory.tsv", "raw_comparators": archive / "raw.tsv",
                   "release_inventory": release_inventory}
if args.phase == "reads":
    phase_artifacts["synthetic_manifest"] = data_root / "large-scale/datasets.tsv"
    for row in table(data_root / "large-scale/datasets.tsv"):
        phase_inputs[f"{row['dataset']}-dta"] = Path(row["path"])
        phase_inputs[f"{row['dataset']}-arrow"] = data_root / f"arrow-interchange/synthetic-{row['dataset']}.arrow"
    phase_inputs["india-dta"] = args.cache / next(r["relative_path"] for r in inventory if r["id"] == "DHS-0259")
    phase_inputs["india-arrow"] = data_root / "arrow-interchange/india-2021-wm.arrow"
    phase_inputs["nsfg-dta"] = args.cache / next(r["relative_path"] for r in inventory if r["id"] == "NSFG-0206")
    for run, names in [("run-full-20260828T202309Z", ["tall", "wide", "tall-wide"]),
                       ("run-india-20260828T203157Z", ["india-2021-wm"])]:
        directory = data_root / "projection-introspection" / run
        phase_artifacts[run + "-summary"] = directory / "summary.tsv"
        for name in names:
            names_dir = directory / name if name == "india-2021-wm" else directory
            phase_inputs[f"projection-{name}-dta"] = directory / name / "input.dta"
            for kind in ("present", "union"):
                phase_inputs[f"projection-{name}-{kind}"] = names_dir / f"{kind}.txt"

scripts = [Path(__file__), root / "benchmarks/reader-refresh/driver_common.py",
           root / "benchmarks/reader-refresh/compare.R",
           *sorted((root / "benchmarks/reader-refresh/workers").glob("*.R"))]
base_binding = source_binding(source_root, args.library, args.build_record, scripts)
binding = dict(base_binding, archived={p.name: sha(p) for p in
    [archive / "inventory.tsv", archive / "raw.tsv"]},
    release_inventory_sha256=sha(release_inventory))
binding["artifacts"] = {name: sha(p) for name, p in phase_artifacts.items()}
binding["read_inputs"] = {name: dict(bytes=p.stat().st_size, sha256=sha(p)) for name, p in phase_inputs.items()}
if args.phase == "reads":
    binding["warm_schedule"] = warm_read_schedule()
binding_path = args.output / "binding.json"
if binding_path.exists():
    require(json.loads(binding_path.read_text()) == binding, "run binding changed")
else:
    binding_path.write_text(json.dumps(binding, indent=2) + "\n")
(args.output / "COMPLETE").unlink(missing_ok=True)

if args.phase == "corpus":
    output = args.output / "corpus.tsv"
    fresh = table(output) if output.exists() else []
    completed = {r["id"] for r in fresh}
    for index, row in enumerate(inventory):
        if row["id"] in completed:
            continue
        result, text = child(row["id"], "benchmarks/reader-refresh/workers/corpus.R",
                             "dtatools", args.cache / row["relative_path"])
        marker = [s.split("\t")[1:] for s in text.splitlines() if s.startswith("DTATOOLS_BENCH\t")]
        require(len(marker) == 1 and len(marker[0]) == 4, 'missing or malformed corpus result marker')
        status, elapsed, rows, columns = marker[0]
        fresh.append(dict(corpus=row["corpus"], id=row["id"], reader="dtatools",
            reader_order=1, status=status, elapsed_seconds=elapsed, rows=rows, columns=columns,
            rss_bytes=result["peak_rss_bytes"], footprint_bytes="NA", **read_cpu(text)))
        write_table(output, fresh)
        if (index + 1) % 25 == 0:
            print(f"corpus: {index + 1}/{len(inventory)}", flush=True)
    require(len(fresh) == len(inventory) == 1823, 'expected 1823 corpus attempts')
    require(len({r["id"] for r in fresh}) == 1823, 'duplicate or missing corpus IDs')
    current = {r["id"]: r for r in fresh}
    common = [r for r in inventory if all(old[(r["id"], m)]["status"] == "ok"
              for m in ("dtaparser", "haven", "stata")) and
              len({(old[(r["id"], m)]["rows"], old[(r["id"], m)]["columns"])
                   for m in ("dtaparser", "haven", "stata")}) == 1]
    require(len(common) == 1812, 'expected 1812 comparable corpus inputs')
    for row in common:
        now, previous = current[row["id"]], old[(row["id"], "haven")]
        require(now["status"] == "ok" and (now["rows"], now["columns"]) == (previous["rows"], previous["columns"]), 'current corpus status or dimensions differ from the retained comparator')
    require(all(all(key in r for key in ("user_cpu_seconds", "system_cpu_seconds", "cpu_seconds")) for r in fresh), 'corpus read CPU measurements are missing')
    for row in inventory:
        stat = (args.cache / row["relative_path"]).stat()
        require(stat.st_size == int(row["bytes"]) and abs(stat.st_mtime - float(row["mtime"])) < 1e-5, 'corpus input changed during the run')
    # Archived comparator rows are copied without rerunning either executable.
    combined = [r for r in raw if r["reader"] in ("haven", "stata")] + [
        {key: r[key] for key in raw[0]} for r in fresh]
    write_table(args.output / "combined.tsv", combined)
    print("corpus complete", flush=True)
else:
    # The existing Arrow files correspond to the Stata-first-save fixtures.
    # Their rows differ from the older haven-generated synthetic read matrix.
    datasets = table(data_root / "large-scale/datasets.tsv")
    for row in datasets:
        require(sha(Path(row["path"])) == row["sha256"], 'synthetic input checksum differs from the retained manifest')
    india = next(r for r in inventory if r["id"] == "DHS-0259")
    nsfg = next(r for r in inventory if r["id"] == "NSFG-0206")
    cases = [(r["dataset"], Path(r["path"]), data_root / f"arrow-interchange/synthetic-{r['dataset']}.arrow", 11)
             for r in datasets]
    cases.append(("india", args.cache / india["relative_path"],
                  data_root / "arrow-interchange/india-2021-wm.arrow", 5))
    identities = []
    for case, dta, arrow, count in cases:
        identities.append(dict(case=case, dta_bytes=dta.stat().st_size, dta_sha256=sha(dta),
                               arrow_bytes=arrow.stat().st_size, arrow_sha256=sha(arrow)))
        child(f"compare-{case}", "benchmarks/reader-refresh/compare.R", dta, arrow)
    write_table(args.output / "read-inputs.tsv", identities)
    # Finish every equality check before the first timed worker. Each worker
    # retains its existing warmup, iteration count and GC placement.
    paths = {case: (dta, arrow, count) for case, dta, arrow, count in cases}
    previous_warm_attempts = sum("warm" in job for job in load_jobs(args.output / "jobs.jsonl"))
    for scheduled in binding["warm_schedule"]:
        dta, arrow, count = paths[scheduled["case"]]
        require(count == scheduled["iterations"], 'warm iteration count differs from the bound schedule')
        warm = dict(scheduled, execution_position=previous_warm_attempts + scheduled["scheduled_position"])
        if scheduled["method"] == "read_dta":
            arguments = ("read-dta", dta, count)
        else:
            verify = "verify" if scheduled["method"] == "read_arrow_verify" else "noverify"
            arguments = ("read-arrow", arrow, count, verify)
        child(scheduled["key"], "benchmarks/reader-refresh/workers/arrow.R", *arguments, warm=warm)
        print(f"warm cohort {scheduled['cohort']}, execution {warm['execution_position']}: "
              f"{scheduled['case']} {scheduled['method']}", flush=True)
    # Preserve the fresh-process spot-check design, separately from warm medians.
    for case, row in [("india", india), ("nsfg", nsfg)]:
        child(f"spot-{case}", "benchmarks/reader-refresh/workers/corpus.R",
              "dtatools", args.cache / row["relative_path"])
    child("spot-india-arrow", "benchmarks/reader-refresh/compare.R",
          "memory", data_root / "arrow-interchange/india-2021-wm.arrow")
    for run, names in [("run-full-20260828T202309Z", ["tall", "wide", "tall-wide"]),
                       ("run-india-20260828T203157Z", ["india-2021-wm"])]:
        directory = data_root / "projection-introspection" / run
        for name in names:
            case_dir = directory / name
            names_dir = case_dir if name == "india-2021-wm" else directory
            child(f"projection-{name}", "benchmarks/reader-refresh/workers/projection.R",
                  case_dir / "input.dta", names_dir / "present.txt", names_dir / "union.txt",
                  11, args.output / f"projection-{name}.tsv")
            print(f"projection: {name}", flush=True)

require(binding["installed"] == {s: sha(args.library / "dtatools" / s) for s in binding["installed"]}, 'installed package changed during the run')

require(binding["read_inputs"] == {name: dict(bytes=p.stat().st_size, sha256=sha(p)) for name, p in phase_inputs.items()}, 'read or projection inputs changed during the run')
require(binding["scripts"] == {p: sha(Path(p)) for p in binding["scripts"]}, 'benchmark scripts changed during the run')
require(binding["commit"] == subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source_root, text=True).strip(), 'source commit changed during the run')
subprocess.run(["git", "diff", "--exit-code", "HEAD", "--", "r-package/dtatools"], cwd=source_root, check=True)
require(binding["artifacts"] == {name: sha(p) for name, p in phase_artifacts.items()}, 'retained benchmark artifacts changed during the run')
require(source_binding(source_root, args.library, args.build_record, scripts) == base_binding, 'source or installation binding changed during the run')
latest_job_attempts(load_jobs(args.output / "jobs.jsonl"),
                    {row["id"] for row in inventory} if args.phase == "corpus" else required_read_keys())
(args.output / "COMPLETE").write_text("Source, input, build, installation and worker bindings matched.\n")
print("Final source, input and installation checks passed.", flush=True)
