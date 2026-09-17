#!/usr/bin/env python3
"""Refresh tools/native-test-manifest.json from an installed package's test run.

The native CI lane copies every test file the manifest lists, refuses a file
whose sha256 differs from the manifest, and requires each test block's title,
passing-assertion count and warning count to match the manifest's policy. After
editing tests, run this script to bring the manifest back in line:

    python scripts/refresh-r-native-manifest.py r-package/dtatools --library /path/to/lib

The package must already be installed in `--library` (or the default R
library). The script runs the complete testthat suite once, then

* recomputes the sha256 of every helper, fixture and test file it lists;
* for each test file whose contents changed, reconciles that file's blocks
  with the tests observed in it: an existing block keeps its skip policy,
  reason and skip message, lowers `min_pass` if the test now passes fewer
  assertions (a minimum that still holds is left alone, since some counts
  depend on the machine), and takes the observed warning count; a new test
  becomes a `forbid` block with the observed counts, placed after the file's
  last block; a test that no longer exists is dropped. Files whose contents
  did not change keep their blocks as they are;
* checks that every capability override still names an existing block.

Pass `--observations results.csv` to reuse a previous run's observations
instead of running the suite again.

A new test that skipped locally cannot be given a policy automatically; the
script reports it and exits non-zero so the block can be written by hand.
Exports are not touched: the manifest's export list is a separate contract.
"""
import argparse
import csv
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict
from pathlib import Path

R_SCRIPT = r"""
args <- commandArgs(trailingOnly = TRUE)
suppressMessages(library(testthat))
results <- testthat::test_dir(args[[1L]], package = "dtatools", load_package = "installed",
                              reporter = "silent", stop_on_failure = FALSE)
frame <- as.data.frame(results)
utils::write.csv(frame[c("file", "test", "passed", "failed", "error", "skipped", "warning")],
                 args[[2L]], row.names = FALSE)
"""


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def observe(package, library, observations):
    if observations is None or not observations.exists():
        env = dict(os.environ)
        if library:
            env["R_LIBS"] = library
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / "observe.R"
            output = observations or Path(directory) / "results.csv"
            script.write_text(R_SCRIPT, encoding="utf-8")
            subprocess.run(["Rscript", str(script), str(package / "tests/testthat"), str(output)],
                           check=True, env=env, cwd=str(package))
            rows = list(csv.DictReader(output.open(newline="", encoding="utf-8")))
    else:
        rows = list(csv.DictReader(observations.open(newline="", encoding="utf-8")))
    observed = []
    seen = Counter()
    for row in rows:
        key = (row["file"], row["test"])
        seen[key] += 1
        observed.append({
            "file": row["file"], "test": row["test"], "occurrence": seen[key],
            "passed": int(row["passed"]), "failed": int(row["failed"]),
            "error": row["error"] == "TRUE", "skipped": row["skipped"] == "TRUE",
            "warnings": int(row["warning"]),
        })
    return observed


def block_key(block):
    return (block["file"], block["test"], block.get("occurrence", 1))


def main():
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n\n")[0])
    parser.add_argument("package", type=Path)
    parser.add_argument("--library", help="R library holding the installed package")
    parser.add_argument("--observations", type=Path,
                        help="CSV of a previous run's results to reuse, or where to save this run's")
    args = parser.parse_args()
    package = args.package.resolve()
    manifest_path = package / "tools/native-test-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    observed = observe(package, args.library, args.observations)
    broken = [o for o in observed if o["failed"] or o["error"]]
    if broken:
        for o in broken:
            print(f"failing test: {o['file']} :: {o['test']}", file=sys.stderr)
        return 1
    by_file = defaultdict(list)
    for o in observed:
        by_file[o["file"]].append(o)

    rehashed = 0
    changed_files = set()
    for entry in [*manifest["helpers"], *manifest.get("fixtures", []),
                  *(f for family in manifest["families"] for f in family["files"])]:
        digest = sha256(package / entry["path"])
        if digest != entry["sha256"]:
            entry["sha256"] = digest
            rehashed += 1
            changed_files.add(Path(entry["path"]).name)

    added, removed, changed, unresolved = [], [], [], []
    for family in manifest["families"]:
        files = [Path(f["path"]).name for f in family["files"]]
        observed_keys = {(o["file"], o["test"], o["occurrence"]): o
                         for name in files for o in by_file.get(name, [])}
        blocks = []
        for block in family["blocks"]:
            key = block_key(block)
            if block["file"] not in changed_files:
                blocks.append(block)
                continue
            o = observed_keys.pop(key, None)
            if o is None:
                removed.append(key)
                continue
            before = (block["min_pass"], block["warnings"])
            block["min_pass"] = min(block["min_pass"], o["passed"])
            if block["skip"] == "forbid":
                block["warnings"] = o["warnings"]
            if before != (block["min_pass"], block["warnings"]):
                changed.append(key)
            blocks.append(block)
        for key, o in observed_keys.items():
            if o["file"] not in changed_files:
                continue
            if o["skipped"]:
                unresolved.append(key)
                continue
            block = {"file": o["file"], "test": o["test"], "occurrence": o["occurrence"],
                     "skip": "forbid", "min_pass": o["passed"], "warnings": o["warnings"]}
            last = max((i for i, b in enumerate(blocks) if b["file"] == o["file"]), default=None)
            blocks.insert(len(blocks) if last is None else last + 1, block)
            added.append(key)
        family["blocks"] = blocks

    known = {block_key(b) for family in manifest["families"] for b in family["blocks"]}
    dangling = [block_key(b) for override in manifest.get("capability_overrides", [])
                for b in override.get("blocks", []) if block_key(b) not in known]

    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"rehashed files: {rehashed}")
    print(f"blocks added: {len(added)}, removed: {len(removed)}, counts changed: {len(changed)}")
    for key in removed:
        print(f"  removed: {key[0]} :: {key[1]}")
    for key in added:
        print(f"  added:   {key[0]} :: {key[1]}")
    status = 0
    for key in unresolved:
        print(f"new test skipped locally; write its block by hand: {key[0]} :: {key[1]}", file=sys.stderr)
        status = 1
    for key in dangling:
        print(f"capability override names a missing block: {key[0]} :: {key[1]}", file=sys.stderr)
        status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
