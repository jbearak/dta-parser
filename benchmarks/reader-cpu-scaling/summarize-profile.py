#!/usr/bin/env python3
"""Reprocess a retained private sample without repeating its workload."""
import argparse
import csv
import importlib.util
import json
from pathlib import Path

from run import HERE, overlapping_paths, sha

spec = importlib.util.spec_from_file_location("reader_profile", HERE / "profile.py")
profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile)

parser = argparse.ArgumentParser(description=__doc__)
for name in ("raw", "capture", "output"):
    parser.add_argument("--" + name, type=lambda value: Path(value).resolve(), required=True)
args = parser.parse_args()
if overlapping_paths(args.output, args.raw.parent):
    parser.error("Keep private stacks separate from public aggregates")
capture = json.loads(args.capture.read_text())
if capture["sampler_exit"] != 0 or not capture["final_bindings_matched"]:
    raise ValueError("Capture did not successfully sample a verified workload")
counts, rejected = profile.leaf_counts(args.raw.read_text())
if not counts:
    raise ValueError("No sanitized leaf counts found")
args.output.mkdir(parents=True, exist_ok=False)
with (args.output / "leaf-functions.csv").open("w", newline="") as stream:
    writer = csv.writer(stream)
    writer.writerow(("function", "stack_sample_count"))
    writer.writerows(sorted(counts.items(), key=lambda pair: (-pair[1], pair[0])))
capture.update(available=True, excluded_opaque_stack_samples=rejected,
    reprocessed_from_capture_sha256=sha(args.capture), raw_sample_sha256=sha(args.raw),
    postprocessor_sha256=sha(Path(__file__)), parser_sha256=sha(HERE / "profile.py"),
    workload_repeated=False)
(args.output / "provenance.json").write_text(json.dumps(capture, indent=2) + "\n")
