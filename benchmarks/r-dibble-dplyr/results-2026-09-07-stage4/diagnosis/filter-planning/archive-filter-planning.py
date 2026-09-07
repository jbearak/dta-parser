#!/usr/bin/env python3
"""Copy the Stage 4 filter diagnosis without replacing earlier evidence."""
from pathlib import Path
import hashlib
import json

validation = Path("/private/tmp/dta-direct-stage4-validation")
destination = Path("/private/tmp/dta-direct-stage4/benchmarks/r-dibble-dplyr/"
                   "results-2026-09-07-stage4/diagnosis/filter-planning")
manifest_path = validation / "filter-planning-e343b3b-manifest.json"
manifest = json.loads(manifest_path.read_text())
inputs = [Path(record["path"]) for record in manifest["artifacts"]]
inputs += [manifest_path, Path(__file__).resolve()]
if len({path.name for path in inputs}) != len(inputs):
    raise SystemExit("Duplicate output basename")
if destination.exists():
    raise SystemExit("Existing diagnosis archive is immutable")
for record in manifest["artifacts"]:
    data = Path(record["path"]).read_bytes()
    if len(data) != record["bytes"] or hashlib.sha256(data).hexdigest() != record["sha256"]:
        raise SystemExit("Changed diagnosis input: " + record["path"])
destination.mkdir()
records = []
for source in inputs:
    data = source.read_bytes()
    target = destination / source.name
    with target.open("xb") as stream:
        stream.write(data)
    if target.read_bytes() != data:
        raise SystemExit("Copy mismatch: " + str(target))
    records.append({"source": str(source), "archive_path": target.name,
                    "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
with (destination / "archive-index.json").open("x") as stream:
    json.dump({"format": 1, "scope": "Supplemental filter diagnosis only; prior 247-artifact index unchanged",
               "files": records}, stream, indent=2)
    stream.write("\n")
print(len(records), "artifacts copied byte-for-byte")
