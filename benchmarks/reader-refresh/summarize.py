#!/usr/bin/env python3
"""Publish aggregates; keep corpus paths, values and per-file records private."""
import argparse
import csv
from datetime import date
import hashlib
import json
from pathlib import Path
import statistics
import sys

from driver_common import (require, collect_warm_observations, latest_job_attempts, load_jobs,
                           required_read_keys, validate_read_commands)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("private", type=Path)
parser.add_argument("reads", type=Path)
parser.add_argument("public", type=Path)
parser.add_argument("--data-root", type=Path, required=True, help="original repository target directory")
parser.add_argument("--date", default=date.today().isoformat())
parser.add_argument("--warm-only", action="store_true",
                    help="publish the balanced warm cohort independently of older corpus results")
args = parser.parse_args()
private, reads, public = args.private, args.reads, args.public
public.mkdir(parents=True, exist_ok=True)
root = Path(__file__).resolve().parents[2]
data_root = args.data_root.resolve()
archive = data_root / "r-corpus-performance/20260824T142432Z"
require((reads / "COMPLETE").is_file(), 'reader phase is incomplete')
if not args.warm_only:
    require((private / "COMPLETE").is_file(), 'corpus phase is incomplete')


def table(path):
    """Read a retained tab-separated artifact without changing its fields."""
    with path.open() as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def publish(name, rows):
    """Write one public CSV from validated observations or aggregates."""
    with (public / name).open("w") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def digest(path):
    """Identify a small private result artifact in public provenance."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def publish_warm(warm):
    """Retain actual execution order and summarize calls and separate cohorts."""
    publish("warm-read-observations.csv", warm)
    pooled, per_cohort = [], []
    for case in ("100mb", "1gb", "india"):
        for method in ("read_dta", "read_arrow_verify", "read_arrow_noverify"):
            records = [r for r in warm if r["case"] == case and r["method"] == method]
            for cohort in [None, *sorted({r["cohort"] for r in records})]:
                selected = records if cohort is None else [r for r in records if r["cohort"] == cohort]
                result = dict(case=case, method=method, iterations=len(selected),
                    cohorts=len({r["cohort"] for r in selected}),
                    median_seconds=statistics.median(r["elapsed_seconds"] for r in selected),
                    min_seconds=min(r["elapsed_seconds"] for r in selected),
                    max_seconds=max(r["elapsed_seconds"] for r in selected),
                    rows=selected[0]["rows"], columns=selected[0]["columns"])
                for field in ("user_cpu_seconds", "system_cpu_seconds", "cpu_seconds"):
                    for label, fn in [("median", statistics.median), ("min", min), ("max", max)]:
                        result[label + "_" + field] = fn(r[field] for r in selected)
                if cohort is None:
                    pooled.append(result)
                else:
                    per_cohort.append(dict(result, cohort=cohort))
    publish("warm-read-summary.csv", pooled)
    publish("warm-cohort-summary.csv", per_cohort)


def public_binding(binding):
    """Remove local installation and worker paths from an already checked binding."""
    result = dict(binding)
    result.pop("library", None)
    result["scripts"] = {str(Path(p).relative_to(root)): h for p, h in result["scripts"].items()}
    return result


def public_csv_bindings(names):
    """Bind exported bytes without exposing the local output directory."""
    artifacts = []
    for name in names:
        path = (public / name).resolve()
        try:
            published_path = str(path.relative_to(root))
            path_base = "repository"
        except ValueError:
            published_path, path_base = name, "public output directory"
        artifacts.append(dict(path=published_path, path_base=path_base,
                              bytes=path.stat().st_size, sha256=digest(path)))
    return artifacts


read_jobs = load_jobs(reads / "jobs.jsonl")
validate_read_commands(read_jobs, root)
latest_reads = latest_job_attempts(read_jobs, required_read_keys())
read_binding = json.loads((reads / "binding.json").read_text())
warm = collect_warm_observations(reads, read_binding, read_jobs)
if args.warm_only:
    publish_warm(warm)
    publish("read-inputs.csv", table(reads / "read-inputs.tsv"))
    provenance = dict(binding=public_binding(read_binding),
        protocol="Six method permutations; rotated case order; all equality checks before warm reads",
        latest_successful_children=len(latest_reads),
        historical_failed_attempts=sum(j["exit_code"] != 0 for j in read_jobs),
        historical_failed_qualification_attempts=sum(j["exit_code"] != 0 and j["key"].startswith("compare-") for j in read_jobs),
        private_read_jobs_sha256=digest(reads / "jobs.jsonl"),
        published_csvs=public_csv_bindings(["warm-read-observations.csv", "warm-read-summary.csv",
                                           "warm-cohort-summary.csv", "read-inputs.csv"]),
        summarizer_sha256=digest(Path(__file__)), haven_invocations=0, stata_invocations=0)
    (public / "warm-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(f"Published {len(warm)} balanced warm-read observations.")
    sys.exit(0)

corpus_jobs = load_jobs(private / "jobs.jsonl")
validate_read_commands(corpus_jobs, root)
latest_corpus = latest_job_attempts(corpus_jobs)
jobs = corpus_jobs + read_jobs
preflight_failures = [j for j in jobs if j["exit_code"] != 0 and j["key"].startswith("compare-")]
by_key = dict(latest_corpus, **latest_reads)
inventory = table(data_root / "r-corpus-performance/20260824T201626Z/inventory.tsv")
raw = table(archive / "raw.tsv")
old = {(r["id"], r["reader"]): r for r in raw}
fresh = {r["id"]: r for r in table(private / "corpus.tsv")}
require(len(fresh) == len(inventory) == 1823, 'expected 1823 corpus attempts')
latest_job_attempts(corpus_jobs, set(fresh))
combined = table(private / "combined.tsv")
require([r for r in combined if r["reader"] in ("haven", "stata")] == [
    r for r in raw if r["reader"] in ("haven", "stata")], 'retained haven or Stata comparator rows changed')
require({r["id"]: r for r in combined if r["reader"] == "dtatools"} == {
    key: {field: value[field] for field in raw[0]} for key, value in fresh.items()}, 'combined dtatools rows differ from current corpus results')
common = []
for row in inventory:
    saved = [old[(row["id"], method)] for method in ("dtaparser", "haven", "stata")]
    if all(r["status"] == "ok" for r in saved) and len({(r["rows"], r["columns"]) for r in saved}) == 1:
        current = fresh[row["id"]]
        require(current["status"] == "ok", f"current read failed: {row['id']}")
        require((current["rows"], current["columns"]) == (saved[0]["rows"], saved[0]["columns"]), 'current corpus dimensions differ from the retained comparator')
        common.append(row)
require(len(common) == 1812, 'expected 1812 comparable corpus inputs')

summary = []
for corpus in ("DHS", "MICS", "NSFG"):
    all_rows = [r for r in inventory if r["corpus"] == corpus]
    for release in sorted({r["release"] for r in all_rows}, key=lambda x: (x == "NA", x)) + ["all"]:
        selected = [r for r in common if r["corpus"] == corpus and (release == "all" or r["release"] == release)]
        included = [r for r in all_rows if release == "all" or r["release"] == release]
        result = dict(corpus=corpus, release="unknown" if release == "NA" else release,
                      files=len(selected), excluded_files=len(included) - len(selected),
                      input_gb=sum(int(r["bytes"]) for r in selected) / 1e9)
        for method in ("dtatools", "haven", "stata"):
            records = [fresh[r["id"]] if method == "dtatools" else old[(r["id"], method)] for r in selected]
            result[f"{method}_seconds"] = sum(float(r["elapsed_seconds"]) for r in records) if records else ""
            result[f"{method}_peak_rss_gb"] = max(float(r["rss_bytes"]) for r in records) / 1e9 if records else ""
        for field in ("user_cpu_seconds", "system_cpu_seconds", "cpu_seconds"):
            result["dtatools_" + field] = sum(float(fresh[r["id"]][field]) for r in selected) if selected else ""
        for method in ("haven", "stata"):
            result[f"dtatools_to_{method}_time_ratio"] = result["dtatools_seconds"] / result[f"{method}_seconds"] if selected else ""
        summary.append(result)
publish("corpus-summary.csv", summary)

stats = {}
for label, rows in [("all", common), ("over_1mb", [r for r in common if int(r["bytes"]) > 1e6]),
                    ("DHS", [r for r in common if r["corpus"] == "DHS"])]:
    times = [(float(fresh[r["id"]]["elapsed_seconds"]), float(old[(r["id"], "haven")]["elapsed_seconds"])) for r in rows]
    stats[label] = dict(files=len(times), faster=sum(a < b - 1e-9 for a, b in times),
                       tied=sum(abs(a - b) < 1e-9 for a, b in times), slower=sum(a > b + 1e-9 for a, b in times))
    if all(a > 0 for a, b in times):
        stats[label].update(mean_file_speedup=statistics.mean(b / a for a, b in times),
                            median_file_speedup=statistics.median(b / a for a, b in times))
(public / "corpus-statistics.json").write_text(json.dumps(stats, indent=2) + "\n")

publish_warm(warm)

spot = []
for case, id in [("india", "DHS-0259"), ("nsfg", "NSFG-0206")]:
    for method in (["read_dta", "read_arrow", "haven", "stata"] if case == "india" else ["read_dta", "haven", "stata"]):
        if method.startswith("read_"):
            key = f"spot-{case}" + ("-arrow" if method == "read_arrow" else "")
            line = next(line for line in (reads / f"{key}.log").read_text().splitlines() if line.startswith("DTATOOLS_BENCH\t"))
            _, status, elapsed, rows, columns = line.split("\t")
            require(status == "ok", 'fresh reader spot check failed')
            rss = by_key[key]["peak_rss_bytes"]
            date = args.date
        else:
            row = old[(id, method)]
            elapsed, rows, columns, rss = [row[k] for k in ("elapsed_seconds", "rows", "columns", "rss_bytes")]
            date = "2026-08-24"
        require((int(rows), int(columns)) == (int(old[(id, "haven")]["rows"]),
                                            int(old[(id, "haven")]["columns"])), 'spot-check dimensions differ from the retained comparator')
        spot.append(dict(case=case, method=method, date=date, elapsed_seconds=float(elapsed),
                         peak_rss_gb=float(rss) / 1e9, rows=int(rows), columns=int(columns)))
publish("spot-comparison.csv", spot)

projected = []
for case in ("tall", "wide", "tall-wide", "india-2021-wm"):
    with (reads / f"projection-{case}.tsv").open() as stream:
        for method, iteration, elapsed, rows, columns, user, system, cpu in csv.reader(stream, delimiter="\t"):
            require((int(rows), int(columns)) == {
                "tall": (500000, 10), "wide": (50000, 10),
                "tall-wide": (250000, 10), "india-2021-wm": (724115, 100)
            }[case], 'projection dimensions differ from the expected selection')
            projected.append(dict(case=case, method=method, iteration=int(iteration),
                elapsed_seconds=float(elapsed), rows=int(rows), columns=int(columns), date=args.date,
                user_cpu_seconds=float(user), system_cpu_seconds=float(system), cpu_seconds=float(cpu)))
publish("projection-observations.csv", projected)
projection_summary = []
for case in ("tall", "wide", "tall-wide", "india-2021-wm"):
    directory = data_root / "projection-introspection" / ("run-india-20260828T203157Z" if case == "india-2021-wm" else "run-full-20260828T202309Z")
    for method in ("dtatools-any-of", "dtatools-all-of"):
        times = [r["elapsed_seconds"] for r in projected if r["case"] == case and r["method"] == method]
        require(len(times) == 11, 'expected eleven projection iterations')
        projection_summary.append(dict(case=case, method=method, median_seconds=statistics.median(times),
            min_seconds=min(times), max_seconds=max(times), date=args.date,
            **{label + "_" + field: fn([r[field] for r in projected if r["case"] == case and r["method"] == method])
               for field in ("user_cpu_seconds", "system_cpu_seconds", "cpu_seconds")
               for label, fn in [("median", statistics.median), ("min", min), ("max", max)]}))
    for r in table(directory / "summary.tsv"):
        if r["case"] == case and r["method"].startswith("stata-"):
            projection_summary.append(dict(r, date="2026-08-28",
                **{label + "_" + field: "" for field in ("user_cpu_seconds", "system_cpu_seconds", "cpu_seconds")
                   for label in ("median", "min", "max")}))
publish("projection-summary.csv", projection_summary)

bindings = {phase: json.loads((directory / "binding.json").read_text())
            for phase, directory in [("corpus", private), ("reads", reads)]}
for field in ("commit", "source_tree", "installed", "archived", "release_inventory_sha256"):
    require(bindings["corpus"][field] == bindings["reads"][field], 'corpus and reader source or installation bindings differ')
for binding in bindings.values():
    # Keep absolute paths and per-file corpus records in the private run directory.
    binding.pop("library")
    binding["scripts"] = {str(Path(p).relative_to(root)): h for p, h in binding["scripts"].items()}
provenance = dict(bindings=bindings, corpus_inventory_entries=len(inventory), common_files=len(common),
    included_successful_children=sum(j["exit_code"] == 0 for j in jobs),
    included_failed_qualification_children=len(preflight_failures),
    historical_failed_children=sum(j["exit_code"] != 0 for j in jobs),
    latest_successful_children=len(by_key),
    haven_invocations=0, stata_invocations=0,
    input_identity="original relative paths, byte sizes and modification times match before/after corpus run",
    private_results={name: digest(private / name) for name in ["corpus.tsv", "combined.tsv", "jobs.jsonl"]},
    private_read_jobs_sha256=digest(reads / "jobs.jsonl"),
    summarizer_sha256=digest(Path(__file__)))
(public / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
publish("read-inputs.csv", table(reads / "read-inputs.tsv"))
print(json.dumps(stats, indent=2))
