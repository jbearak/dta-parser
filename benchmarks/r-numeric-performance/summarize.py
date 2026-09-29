#!/usr/bin/env python3
"""Pool the two batches per version; emit medians and matched runtime ratios."""
import argparse
import csv
import statistics
from collections import defaultdict
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("batches", nargs=4, type=Path, help="main, candidate, candidate, main")
args = parser.parse_args()
fields = ("n", "width", "groups", "mode", "scenario", "engine")
values = defaultdict(list)
gcs = defaultdict(int)
for batch, version in zip(args.batches, ("main", "candidate", "candidate", "main")):
    with (batch / "raw.csv").open(newline="") as source:
        for row in csv.DictReader(source):
            key = (version,) + tuple(row[f] for f in fields)
            values[key].append(float(row["us"]))
            gcs[key] += float(row["gc_seconds"]) > 0
medians = {key: statistics.median(samples) for key, samples in values.items()}
args.output.mkdir(parents=True, exist_ok=True)
with (args.output / "medians.csv").open("w", newline="") as target:
    writer = csv.writer(target)
    writer.writerow(("version",) + fields + ("samples", "median_us", "timed_gc_calls"))
    for key in sorted(values):
        writer.writerow(key + (len(values[key]), medians[key], gcs[key]))
with (args.output / "comparisons.csv").open("w", newline="") as target:
    writer = csv.writer(target)
    writer.writerow(fields + ("main_us", "candidate_us", "main_over_candidate",
                              "candidate_over_dplyr", "candidate_over_data_table"))
    for key in sorted(medians):
        version, *condition, engine = key
        if version != "candidate" or engine in ("dplyr_plain", "data_table_plain"):
            continue
        prefix = ("candidate",) + tuple(condition)
        before = medians[("main",) + tuple(condition) + (engine,)]
        after = medians[key]
        writer.writerow(tuple(condition) + (engine, before, after, before / after,
            after / medians[prefix + ("dplyr_plain",)],
            after / medians[prefix + ("data_table_plain",)]))
print(f"Summarized {sum(map(len, values.values()))} calls; {sum(gcs.values())} observed GC")
