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

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("private", type=Path)
parser.add_argument("reads", type=Path)
parser.add_argument("public", type=Path)
parser.add_argument("--data-root", type=Path, required=True, help="original repository target directory")
parser.add_argument("--date", default=date.today().isoformat())
args = parser.parse_args()
private, reads, public = args.private, args.reads, args.public
public.mkdir(parents=True, exist_ok=True)
root = Path(__file__).resolve().parents[2]
data_root = args.data_root.resolve()
archive = data_root / "r-corpus-performance/20260824T142432Z"
assert (private / "COMPLETE").is_file() and (reads / "COMPLETE").is_file()


def table(path):
    with path.open() as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def publish(name, rows):
    with (public / name).open("w") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


inventory = table(data_root / "r-corpus-performance/20260824T201626Z/inventory.tsv")
raw = table(archive / "raw.tsv")
old = {(r["id"], r["reader"]): r for r in raw}
fresh = {r["id"]: r for r in table(private / "corpus.tsv")}
assert len(fresh) == len(inventory) == 1823
combined = table(private / "combined.tsv")
assert [r for r in combined if r["reader"] in ("haven", "stata")] == [
    r for r in raw if r["reader"] in ("haven", "stata")]
assert {r["id"]: r for r in combined if r["reader"] == "dtatools"} == {
    key: {field: value[field] for field in raw[0]} for key, value in fresh.items()}
common = []
for row in inventory:
    saved = [old[(row["id"], method)] for method in ("dtaparser", "haven", "stata")]
    if all(r["status"] == "ok" for r in saved) and len({(r["rows"], r["columns"]) for r in saved}) == 1:
        current = fresh[row["id"]]
        assert current["status"] == "ok", f"current read failed: {row['id']}"
        assert (current["rows"], current["columns"]) == (saved[0]["rows"], saved[0]["columns"])
        common.append(row)
assert len(common) == 1812

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

corpus_jobs = [json.loads(line) for line in (private / "jobs.jsonl").read_text().splitlines()]
read_jobs = [json.loads(line) for line in (reads / "jobs.jsonl").read_text().splitlines()]
jobs = corpus_jobs + read_jobs
preflight_failures = [j for j in jobs if j["exit_code"] != 0]
assert all(j["key"].startswith("compare-") for j in preflight_failures)
assert all(j["exit_code"] == 0 for j in read_jobs)
assert {j["key"] for j in corpus_jobs if j["key"] in fresh} == set(fresh)
for job in jobs:
    command = job["command"]
    assert Path(command[0]).name == "Rscript"
    script = Path(command[2]).relative_to(root).as_posix()
    if script == "benchmarks/reader-refresh/workers/corpus.R":
        assert command[3] == "dtatools"
    elif script == "benchmarks/reader-refresh/workers/arrow.R":
        assert command[3] in ("read-dta", "read-arrow")
    else:
        assert script in ("benchmarks/reader-refresh/compare.R",
                          "benchmarks/reader-refresh/workers/projection.R")
by_key = {j["key"]: j for j in jobs}
assert all(by_key[j["key"]]["exit_code"] == 0 for j in preflight_failures)
warm = []
for case, count in [("100mb", 11), ("1gb", 11), ("india", 5)]:
    for method, key in [("read_dta", f"read-dta-{case}"),
                        ("read_arrow_verify", f"read-arrow-{case}-verify"),
                        ("read_arrow_noverify", f"read-arrow-{case}-noverify")]:
        lines = (reads / f"{key}.log").read_text().splitlines()
        markers = [line.split("\t") for line in lines if line.startswith("iteration\t")]
        assert len(markers) == count
        cpu_markers = [line.split("\t") for line in lines if line.startswith("cpu\t")]
        assert len(cpu_markers) == count
        cpu = {int(r[1]): (float(r[2]), float(r[3])) for r in cpu_markers}
        assert set(cpu) == set(range(1, count + 1))
        for _, iteration, elapsed, rows, columns in markers:
            assert (int(rows), int(columns)) == {
                "100mb": (231956, 40), "1gb": (2320123, 40), "india": (724115, 5972)
            }[case]
            warm.append(dict(case=case, method=method, iteration=int(iteration),
                             elapsed_seconds=float(elapsed), rows=int(rows), columns=int(columns),
                             user_cpu_seconds=cpu[int(iteration)][0], system_cpu_seconds=cpu[int(iteration)][1],
                             cpu_seconds=sum(cpu[int(iteration)])))
publish("warm-read-observations.csv", warm)
warm_summary = []
for case in ("100mb", "1gb", "india"):
    for method in ("read_dta", "read_arrow_verify", "read_arrow_noverify"):
        records = [r for r in warm if r["case"] == case and r["method"] == method]
        times = [r["elapsed_seconds"] for r in records]
        warm_summary.append(dict(case=case, method=method, iterations=len(times),
            median_seconds=statistics.median(times), min_seconds=min(times), max_seconds=max(times),
            rows=records[0]["rows"], columns=records[0]["columns"],
            **{label + "_" + field: fn([r[field] for r in records])
               for field in ("user_cpu_seconds", "system_cpu_seconds", "cpu_seconds")
               for label, fn in [("median", statistics.median), ("min", min), ("max", max)]}))
publish("warm-read-summary.csv", warm_summary)

spot = []
for case, id in [("india", "DHS-0259"), ("nsfg", "NSFG-0206")]:
    for method in (["read_dta", "read_arrow", "haven", "stata"] if case == "india" else ["read_dta", "haven", "stata"]):
        if method.startswith("read_"):
            key = f"spot-{case}" + ("-arrow" if method == "read_arrow" else "")
            line = next(line for line in (reads / f"{key}.log").read_text().splitlines() if line.startswith("DTATOOLS_BENCH\t"))
            _, status, elapsed, rows, columns = line.split("\t")
            assert status == "ok"
            rss = by_key[key]["peak_rss_bytes"]
            date = args.date
        else:
            row = old[(id, method)]
            elapsed, rows, columns, rss = [row[k] for k in ("elapsed_seconds", "rows", "columns", "rss_bytes")]
            date = "2026-08-24"
        assert (int(rows), int(columns)) == (int(old[(id, "haven")]["rows"]),
                                            int(old[(id, "haven")]["columns"]))
        spot.append(dict(case=case, method=method, date=date, elapsed_seconds=float(elapsed),
                         peak_rss_gb=float(rss) / 1e9, rows=int(rows), columns=int(columns)))
publish("spot-comparison.csv", spot)

projected = []
for case in ("tall", "wide", "tall-wide", "india-2021-wm"):
    with (reads / f"projection-{case}.tsv").open() as stream:
        for method, iteration, elapsed, rows, columns, user, system, cpu in csv.reader(stream, delimiter="\t"):
            assert (int(rows), int(columns)) == {
                "tall": (500000, 10), "wide": (50000, 10),
                "tall-wide": (250000, 10), "india-2021-wm": (724115, 100)
            }[case]
            projected.append(dict(case=case, method=method, iteration=int(iteration),
                elapsed_seconds=float(elapsed), rows=int(rows), columns=int(columns), date=args.date,
                user_cpu_seconds=float(user), system_cpu_seconds=float(system), cpu_seconds=float(cpu)))
publish("projection-observations.csv", projected)
projection_summary = []
for case in ("tall", "wide", "tall-wide", "india-2021-wm"):
    directory = data_root / "projection-introspection" / ("run-india-20260828T203157Z" if case == "india-2021-wm" else "run-full-20260828T202309Z")
    for method in ("dtatools-any-of", "dtatools-all-of"):
        times = [r["elapsed_seconds"] for r in projected if r["case"] == case and r["method"] == method]
        assert len(times) == 11
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
    assert bindings["corpus"][field] == bindings["reads"][field]
for binding in bindings.values():
    # Keep absolute paths and per-file corpus records in the private run directory.
    binding.pop("library")
    binding["scripts"] = {str(Path(p).relative_to(root)): h for p, h in binding["scripts"].items()}
provenance = dict(bindings=bindings, corpus_inventory_entries=len(inventory), common_files=len(common),
    included_successful_children=sum(j["exit_code"] == 0 for j in jobs),
    included_failed_qualification_children=len(preflight_failures),
    haven_invocations=0, stata_invocations=0,
    input_identity="original relative paths, byte sizes and modification times match before/after corpus run",
    private_results={name: digest(private / name) for name in ["corpus.tsv", "combined.tsv", "jobs.jsonl"]},
    private_read_jobs_sha256=digest(reads / "jobs.jsonl"),
    summarizer_sha256=digest(Path(__file__)))
(public / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
publish("read-inputs.csv", table(reads / "read-inputs.tsv"))
print(json.dumps(stats, indent=2))
