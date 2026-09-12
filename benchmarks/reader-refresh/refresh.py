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

parser = argparse.ArgumentParser()
parser.add_argument("library", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--cache", type=Path, default=Path("/opt/aww_cache"))
parser.add_argument("--phase", choices=["corpus", "reads"], required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
os.chdir(root)
args.output = args.output.resolve()
args.library = args.library.resolve()
args.output.mkdir(parents=True, exist_ok=True)
archive = root / "target/r-corpus-performance/20260824T142432Z"
release_inventory = root / "target/r-corpus-performance/20260824T201626Z/inventory.tsv"
environment = os.environ.copy()
environment.update(DTATOOLS_BENCH_LIB=str(args.library),
                   R_ENVIRON_USER="/dev/null", R_PROFILE_USER="/dev/null")
rscript = shutil.which("Rscript")


def table(path):
    with path.open() as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_table(path, rows):
    with path.open("w") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def child(key, script, *arguments):
    log = args.output / f"{key}.log"
    command = [rscript, "--vanilla", str(root / script), *map(str, arguments)]
    with log.open("wb") as stream:
        actions = [(os.POSIX_SPAWN_DUP2, stream.fileno(), 1),
                   (os.POSIX_SPAWN_DUP2, stream.fileno(), 2)]
        start = time.time()
        pid = os.posix_spawn(rscript, command, environment, file_actions=actions)
        _, status, usage = os.wait4(pid, 0)
    result = dict(key=key, command=command, exit_code=os.waitstatus_to_exitcode(status),
                  peak_rss_bytes=usage.ru_maxrss * (1 if sys.platform == "darwin" else 1024),
                  start=start, duration=time.time() - start)
    with (args.output / "jobs.jsonl").open("a") as stream:
        stream.write(json.dumps(result) + "\n")
    if result["exit_code"]:
        raise RuntimeError(f"{key} failed; inspect {log}")
    return result, log.read_text()


inventory = table(archive / "inventory.tsv")
release_rows = {r["id"]: r for r in table(release_inventory)}
raw = table(archive / "raw.tsv")
old = {(r["id"], r["reader"]): r for r in raw}
for row in inventory:
    release = release_rows[row["id"]]
    assert all(row[k] == release[k] for k in ("corpus", "relative_path", "bytes", "mtime"))
    row["release"] = release["release"]
    path = args.cache / row["relative_path"]
    stat = path.stat()
    assert path.is_file() and not path.is_symlink()
    assert stat.st_size == int(row["bytes"]) and abs(stat.st_mtime - float(row["mtime"])) < 1e-5

binding = dict(commit=subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
    source_tree=subprocess.check_output(["git", "rev-parse", "HEAD:r-package/dtatools"], text=True).strip(),
    library=str(args.library), archived={p.name: sha(p) for p in
        [archive / "inventory.tsv", archive / "raw.tsv"]},
    release_inventory_sha256=sha(release_inventory),
    installed={s: sha(args.library / "dtatools" / s) for s in
        ["DESCRIPTION", "R/dtatools.rdb", "R/dtatools.rdx", "libs/dtatools.so"]},
    scripts={str(p): sha(p) for p in [Path(__file__),
        root / "benchmarks/reader-refresh/compare.R",
        root / "benchmarks/r-corpus-performance/worker.R",
        root / "benchmarks/arrow-interchange/worker.R",
        root / "benchmarks/projection-introspection/r-worker.R",
        root / "benchmarks/benchmark-common.R"]})
binding_path = args.output / "binding.json"
if binding_path.exists():
    assert json.loads(binding_path.read_text()) == binding, "run binding changed"
else:
    binding_path.write_text(json.dumps(binding, indent=2) + "\n")

if args.phase == "corpus":
    output = args.output / "corpus.tsv"
    fresh = table(output) if output.exists() else []
    completed = {r["id"] for r in fresh}
    for index, row in enumerate(inventory):
        if row["id"] in completed:
            continue
        result, text = child(row["id"], "benchmarks/r-corpus-performance/worker.R",
                             "dtatools", args.cache / row["relative_path"])
        marker = [s.split("\t")[1:] for s in text.splitlines() if s.startswith("DTATOOLS_BENCH\t")]
        assert len(marker) == 1 and len(marker[0]) == 4
        status, elapsed, rows, columns = marker[0]
        fresh.append(dict(corpus=row["corpus"], id=row["id"], reader="dtatools",
            reader_order=1, status=status, elapsed_seconds=elapsed, rows=rows, columns=columns,
            rss_bytes=result["peak_rss_bytes"], footprint_bytes="NA"))
        write_table(output, fresh)
        if (index + 1) % 25 == 0:
            print(f"corpus: {index + 1}/{len(inventory)}", flush=True)
    assert len(fresh) == len(inventory)
    for row in inventory:
        stat = (args.cache / row["relative_path"]).stat()
        assert stat.st_size == int(row["bytes"]) and abs(stat.st_mtime - float(row["mtime"])) < 1e-5
    # Archived comparator rows are copied without rerunning either executable.
    combined = [r for r in raw if r["reader"] in ("haven", "stata")] + fresh
    write_table(args.output / "combined.tsv", combined)
    print("corpus complete", flush=True)
else:
    # The existing Arrow files correspond to the Stata-first-save fixtures.
    # Their rows differ from the older haven-generated synthetic read matrix.
    datasets = table(root / "target/large-scale/datasets.tsv")
    for row in datasets:
        assert sha(Path(row["path"])) == row["sha256"]
    india = next(r for r in inventory if r["id"] == "DHS-0259")
    nsfg = next(r for r in inventory if r["id"] == "NSFG-0206")
    cases = [(r["dataset"], Path(r["path"]), root / f"target/arrow-interchange/synthetic-{r['dataset']}.arrow", 11)
             for r in datasets]
    cases.append(("india", args.cache / india["relative_path"],
                  root / "target/arrow-interchange/india-2021-wm.arrow", 5))
    identities = []
    for case, dta, arrow, count in cases:
        identities.append(dict(case=case, dta_bytes=dta.stat().st_size, dta_sha256=sha(dta),
                               arrow_bytes=arrow.stat().st_size, arrow_sha256=sha(arrow)))
        child(f"compare-{case}", "benchmarks/reader-refresh/compare.R", dta, arrow)
        child(f"read-dta-{case}", "benchmarks/arrow-interchange/worker.R", "read-dta", dta, count)
        for verify in ("verify", "noverify"):
            child(f"read-arrow-{case}-{verify}", "benchmarks/arrow-interchange/worker.R",
                  "read-arrow", arrow, count, verify)
        print(f"warm reads: {case}", flush=True)
    write_table(args.output / "read-inputs.tsv", identities)
    # Preserve the fresh-process spot-check design, separately from warm medians.
    for case, row in [("india", india), ("nsfg", nsfg)]:
        child(f"spot-{case}", "benchmarks/r-corpus-performance/worker.R",
              "dtatools", args.cache / row["relative_path"])
    child("spot-india-arrow", "benchmarks/reader-refresh/compare.R",
          "memory", root / "target/arrow-interchange/india-2021-wm.arrow")
    for run, names in [("run-full-20260828T202309Z", ["tall", "wide", "tall-wide"]),
                       ("run-india-20260828T203157Z", ["india-2021-wm"])]:
        directory = root / "target/projection-introspection" / run
        for name in names:
            case_dir = directory / name
            names_dir = case_dir if name == "india-2021-wm" else directory
            child(f"projection-{name}", "benchmarks/projection-introspection/r-worker.R",
                  case_dir / "input.dta", names_dir / "present.txt", names_dir / "union.txt",
                  11, args.output / f"projection-{name}.tsv")
            print(f"projection: {name}", flush=True)

assert binding["installed"] == {s: sha(args.library / "dtatools" / s) for s in binding["installed"]}
