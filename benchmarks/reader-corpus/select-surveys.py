#!/usr/bin/env python3
"""Derive survey-only aggregates from an unchanged, completed private cache run."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("survey_cache_run", HERE / "cache-run.py")
CACHE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CACHE)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def select(files, observations, expected_files):
    CACHE.validate_observations(observations, files)
    CACHE.require(len({f["id"] for f in files}) == len(files), "Duplicate source input IDs")
    selected = [f for f in files if f["corpus"] in CACHE.SURVEY_CORPORA]
    CACHE.validate_inventory_count(selected, expected_files)
    CACHE.require({f["corpus"] for f in selected} == set(CACHE.SURVEY_CORPORA),
                  "All five survey roots must be represented")
    ids = {f["id"] for f in selected}
    kept = [r for r in observations if r["id"] in ids]
    excluded = [r for r in observations if r["id"] not in ids]
    CACHE.validate_observations(kept, selected)
    return selected, kept, excluded


def summaries(files, observations):
    result = []
    for corpus in sorted({f["corpus"] for f in files}) + ["ALL"]:
        selected = [f for f in files if corpus == "ALL" or f["corpus"] == corpus]
        ids = {f["id"] for f in selected}
        for output in CACHE.OUTPUTS:
            rows = [r for r in observations if r["id"] in ids and r["output"] == output and r["status"] == "ok"]
            CACHE.require(bool(rows), "A selected corpus has no successful observations")
            successful = {r["id"] for r in rows}
            result.append(dict(corpus=corpus, output=output, attempted_files=len(selected),
                readable_files=len(rows), excluded_files=len(selected)-len(rows),
                dta_bytes=sum(f["bytes"] for f in selected if f["id"] in successful),
                wall_seconds=sum(r["wall_seconds"] for r in rows),
                read_cpu_seconds=sum(r["read_cpu_seconds"] for r in rows),
                process_cpu_seconds=sum(r["process_cpu_seconds"] for r in rows),
                max_peak_rss_bytes=max(r["peak_rss_bytes"] for r in rows)))
    return result


def verify_source_provenance(source, provenance_path):
    provenance = json.loads(provenance_path.read_text())
    expected = dict(provenance["private_artifact_sha256"])
    for name in ("summary.csv", "run.json", "revalidation.json"):
        expected[name] = provenance["public_artifact_sha256"][name]
    CACHE.require(all(Path(name).name == name and digest(source / name) == value
                      for name, value in expected.items()), "Original published provenance does not match source artifacts")


def derive(source, source_provenance, output, expected_files):
    verify_source_provenance(source, source_provenance)
    CACHE.require((source / "COMPLETE").read_text() == "full-cache\n", "Source is not a completed full run")
    read = lambda name: json.loads((source / name).read_text())
    before, after = read("binding-before.json"), read("binding-after.json")
    CACHE.require(before == after, "Source completion bindings differ")
    seal = read("QUALIFIED")
    CACHE.require(all(Path(name).name == name and digest(source / name) == value
                      for name, value in seal.items()), "Source qualification seal changed")
    files = read("inputs-private.json")
    raw = (source / "observations.jsonl").read_bytes().splitlines(keepends=True)
    observations = [json.loads(line) for line in raw]
    selected, kept, excluded = select(files, observations, expected_files)
    ids = {f["id"] for f in selected}
    CACHE.require(not read("run.json")["smoke"], "Smoke observations cannot establish survey totals")
    CACHE.require(len(files) == read("run.json")["attempted_files"] and
                  len(observations) == read("run.json")["attempts"], "Source run counts differ")
    names = ("inputs-private.json", "observations.jsonl", "observations.csv", "summary.csv",
        "run.json", "binding-before.json", "binding-after.json", "QUALIFIED", "COMPLETE",
        "baseline-qualification-private.jsonl", "candidate-qualification-private.jsonl")
    source_hashes = {name: digest(source / name) for name in names}
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    CACHE.write_json(output / "selected-inputs-private.json", selected)
    (output / "selected-observations-private.jsonl").write_bytes(
        b"".join(line for line, row in zip(raw, observations) if row["id"] in ids))
    (output / "excluded-observations-private.jsonl").write_bytes(
        b"".join(line for line, row in zip(raw, observations) if row["id"] not in ids))
    CACHE.write_csv(output / "summary.csv", summaries(selected, kept))
    excluded_inputs = [f for f in files if f["id"] not in ids]
    record = dict(schema_version=1, derived_utc=datetime.now(timezone.utc).isoformat(),
        policy="Select only observations whose input corpus is in the exact survey-root allowlist; preserve source order and every selected observation",
        survey_roots=list(CACHE.SURVEY_CORPORA), new_read_attempts=0,
        original=dict(input_files=len(files), attempts=len(observations),
            successful_attempts=sum(r["status"] == "ok" for r in observations)),
        selected=dict(input_files=len(selected), attempts=len(kept),
            successful_attempts=sum(r["status"] == "ok" for r in kept),
            error_attempts=sum(r["status"] != "ok" for r in kept),
            source_bytes=sum(f["bytes"] for f in selected)),
        excluded_scope=dict(input_files=len(excluded_inputs), attempts=len(excluded),
            successful_attempts=sum(r["status"] == "ok" for r in excluded),
            source_bytes=sum(f["bytes"] for f in excluded_inputs),
            reason="Input is outside the five survey roots; project names and identities remain private"),
        source_artifact_sha256=source_hashes,
        original_published_provenance_sha256=digest(source_provenance),
        derived_artifact_sha256={name: digest(output / name) for name in
            ("selected-inputs-private.json", "selected-observations-private.jsonl",
             "excluded-observations-private.jsonl", "summary.csv")},
        derivation_script_sha256=digest(Path(__file__)),
        survey_controller_sha256=digest(HERE / "cache-run.py"),
        measured_controller_sha256=before["workers"][CACHE.CONTROLLER],
        source_observations_unchanged=True, selected_observations_copied_byte_for_byte=True)
    CACHE.require(all(digest(source / name) == value for name, value in source_hashes.items()),
                  "Source artifacts changed during derivation")
    CACHE.write_json(output / "selection.json", record)
    print(f"Selected {len(selected)} survey inputs and {len(kept)} unchanged attempts", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-output", type=Path, required=True)
    parser.add_argument("--source-provenance", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-files", type=int, required=True)
    args = parser.parse_args()
    derive(args.source_output, args.source_provenance, args.output, args.expected_files)
