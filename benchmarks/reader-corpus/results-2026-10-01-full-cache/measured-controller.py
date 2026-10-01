#!/usr/bin/env python3
"""Qualify every cache DTA, then time current tibble/dibble reads without comparators."""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import stat
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
from run import parse_read
sys.path.insert(0, str(HERE.parent / "reader-refresh"))
from driver_common import child_environment, require, run_child, sha
SPEC = importlib.util.spec_from_file_location("cache_build_records", HERE.parent / "r-file-readers/record-builds.py")
BUILDS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDS)
OUTPUTS = ("tibble", "dibble")
QUALIFICATION_POLICY = "complete-signature-within-output-v2"
CONTROLLER = "benchmarks/reader-corpus/cache-run.py"
SOURCE_ARTIFACTS = ("config-private.json", "inventory-private.json", "inputs-private.json",
    "binding-before.json", "baseline-qualification-private.jsonl",
    "candidate-qualification-private.jsonl")
# Exact exclusions from r-corpus-roundtrip/common.R, including its stable ID contract.
KNOWN_EXCLUSIONS = {
    "MICS-9fcbb54ada2fcece459bca33": dict(corpus="MICS", bytes=0,
        sha256="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", reason="empty-source"),
    "MICS-8cb7d864111538cd2265198f": dict(corpus="MICS", bytes=27792,
        sha256="76b12af213a2e89d4ae241694a1d09dc06efbc5a36f6b85cb2d0257c89e1111a", reason="malformed-source"),
}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def write_csv(path, rows):
    require(bool(rows), "Cannot write an empty result table")
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def inventory(cache):
    require(cache.is_dir() and not cache.is_symlink(), "Cache root must be an ordinary directory")
    files, aliases = [], []
    def fail(error):
        raise error
    for parent, directories, names in os.walk(cache, followlinks=False, onerror=fail):
        for name in directories[:]:
            path = Path(parent) / name
            if path.is_symlink():
                aliases.append(str(path.relative_to(cache)))
                directories.remove(name)
        for name in names:
            path = Path(parent) / name
            if path.suffix.lower() != ".dta":
                continue
            info = path.lstat()
            if stat.S_ISLNK(info.st_mode):
                aliases.append(str(path.relative_to(cache)))
                continue
            require(stat.S_ISREG(info.st_mode), "DTA inventory contains a nonordinary file")
            relative = path.relative_to(cache).as_posix()
            corpus = relative.split("/", 1)[0]
            require(re.fullmatch(r"[A-Za-z0-9_-]+", corpus), "Invalid corpus name")
            with path.open("rb") as stream:
                prefix = stream.read(64)
            modern = re.search(rb"<release>([0-9]+)</release>", prefix)
            release = int(modern[1]) if modern else prefix[0] if prefix else None
            files.append(dict(id="D" + hashlib.sha256(relative.encode()).hexdigest()[:24],
                corpus=corpus, relative_path=relative, path=str(path), bytes=info.st_size,
                mtime_ns=info.st_mtime_ns, release=release))
    files.sort(key=lambda row: row["relative_path"])
    require(files and len({r["id"] for r in files}) == len(files), "Empty or duplicate inventory")
    return dict(files=files, skipped_symlinks=sorted(aliases),
        policy="Every regular case-insensitive .dta file; no file or directory symlinks")


def qualification_records(path, files):
    records = [json.loads(line) for line in path.read_text().splitlines()]
    expected = [(row["id"], output) for row in files for output in OUTPUTS]
    require([(row["id"], row["output"]) for row in records] == expected,
            "Incomplete, duplicate, or reordered qualification records")
    return {(row["id"], row["output"]): row for row in records}


def validate_inventory_count(files, expected):
    require(expected > 0 and len(files) == expected,
            "Full-cache inventory count differs from requested coverage")


def validate_qualification(files, baseline, candidate, known_errors):
    expected = {(row["id"], output) for row in files for output in OUTPUTS}
    require(set(baseline) == set(candidate) == expected, "Incomplete qualification matrix")
    differences = []
    for row in files:
        for output in OUTPUTS:
            require(baseline[(row["id"], output)] == candidate[(row["id"], output)],
                    "Value, metadata, warning, or error parity failed within output: " + row["id"])
        records = [baseline[(row["id"], output)] for output in OUTPUTS]
        # Dibble construction can widen a string's declared Stata storage to
        # fit decoded UTF-8. Its signature therefore need not equal a tibble's.
        comparable = [{k: v for k, v in record.items() if k not in ("output", "signature")}
                      for record in records]
        require(all(record == comparable[0] for record in comparable),
                "Shape, warning, or error parity failed across outputs: " + row["id"])
        for record in records:
            require(record["status"] in ("ok", "dta_error"), "Unknown qualification status")
            if record["status"] == "dta_error":
                require(row["id"] in known_errors, "Unexpected DTA failure: " + row["id"])
            else:
                require(row["id"] not in known_errors, "Historically malformed input changed status")
                require(all(type(record[k]) is int and record[k] >= 0 for k in ("rows", "columns")),
                        "Invalid qualified dimensions")
                require(isinstance(record["signature"], str) and record["signature"], "Missing complete signature")
            require(re.fullmatch(r"[a-f0-9]{64}", record["conditions_sha256"]), "Missing condition identity")
        if records[0].get("signature") != records[1].get("signature"):
            differences.append(dict(id=row["id"], tibble_signature=records[0]["signature"],
                dibble_signature=records[1]["signature"]))
    return differences


def validate_observations(rows, files):
    expected = {(row["id"], output) for row in files for output in OUTPUTS}
    require(len(rows) == len(expected) and {(r["id"], r["output"]) for r in rows} == expected,
            "Missing or duplicate timed attempts")


def parse_timed(log, qualification):
    result = parse_read(log, "read_dta", qualification)
    conditions = re.findall(r"^DTATOOLS_CONDITIONS\t([a-f0-9]{64})$", log, re.M)
    require(conditions == [qualification["conditions_sha256"]], "Timed warning/error contract differs")
    return result


def runtime(library):
    command = [shutil.which("Rscript"), "--vanilla", "-e",
        '.libPaths(c(Sys.getenv("DTATOOLS_BENCH_LIB"), .libPaths())); '
        'cat(R.version.string, R.version$platform, '
        'unname(tools::sha256sum(file.path(R.home("bin"), "exec/R"))), '
        'as.character(packageVersion("dtatools")), as.character(packageVersion("tibble")), sep="\\t")']
    fields = subprocess.check_output(command, env=child_environment(library), text=True).split("\t")
    require(len(fields) == 5, "Incomplete runtime provenance")
    return dict(zip(("r_version", "r_platform", "r_executable_sha256", "dtatools_version", "tibble_version"), fields))


def bindings(config, files):
    result = {"builds": {}}
    for variant in ("baseline", "candidate"):
        receipt, _, receipt_hash = BUILDS.verified_receipt(Path(config[variant + "_build_work"]), variant)
        result["builds"][variant] = dict(receipt_sha256=receipt_hash, receipt=receipt,
            runtime=runtime(Path(config[variant + "_build_work"]) / "library"))
    scripts = [Path(__file__), HERE / "cache-worker.R", HERE / "cache-qualify.R", HERE / "run.py",
        HERE.parent / "reader-refresh/driver_common.py",
        HERE.parent / "reader-refresh/workers/benchmark-common.R",
        HERE.parent / "r-corpus-roundtrip/common.R"]
    result.update(workers={p.relative_to(ROOT).as_posix(): sha(p) for p in scripts},
        inputs={r["id"]: dict(bytes=r["bytes"], sha256=sha(r["path"])) for r in files},
        rscript_sha256=sha(Path(shutil.which("Rscript")).resolve()))
    return result


def expected_exclusion(row, identity):
    canonical_id = row["corpus"] + "-" + hashlib.sha256(
        "\x1f".join((row["corpus"], row["relative_path"], identity["sha256"])).encode()).hexdigest()[:24]
    expected = KNOWN_EXCLUSIONS.get(canonical_id)
    if expected and all(expected[k] == value for k, value in
            (("corpus", row["corpus"]), ("bytes", row["bytes"]), ("sha256", identity["sha256"]))):
        return dict(canonical_id=canonical_id, reason=expected["reason"])
    return None


def selected_inputs(all_files, smoke):
    if not smoke:
        return all_files
    selected = {min((r for r in all_files if r["corpus"] == corpus and r["bytes"] > 0),
                    key=lambda r: r["bytes"])["id"] for corpus in {r["corpus"] for r in all_files}}
    for row in all_files:
        if row["corpus"] == "MICS" and row["bytes"] in (0, 27792):
            if expected_exclusion(row, dict(sha256=sha(row["path"]))):
                selected.add(row["id"])
    return [r for r in all_files if r["id"] in selected]


def qualified_seal(output):
    names = ("config-private.json", "inventory-private.json", "inputs-private.json",
        "binding-before.json", "baseline-qualification-private.jsonl",
        "candidate-qualification-private.jsonl", "qualification.json")
    config = json.loads((output / "config-private.json").read_text())
    if config.get("qualification_origin") == "revalidated-complete-records":
        names += ("revalidation.json", "original-controller.py", "original-binding.json")
    return {name: sha(output / name) for name in names}


def qualification_summary(files, qualified, known_errors, before, differences):
    return dict(files=len(files), attempts_per_library=len(files)*2,
        outputs=OUTPUTS, matched=True, policy=QUALIFICATION_POLICY,
        cross_output_signature_differences=differences,
        malformed=[dict(id=r["id"], **known_errors[r["id"]], **before["inputs"][r["id"]])
                   for r in files if r["id"] in known_errors],
        warning_files=[r["id"] for r in files
                       if qualified[(r["id"], "dibble")]["conditions"]["warnings"]])


def validate_revalidation_bindings(original, current, original_controller):
    require(sha(original_controller) == original["workers"][CONTROLLER],
            "Archived original controller does not match its binding")
    adjusted = dict(current, workers=dict(current["workers"]))
    adjusted["workers"][CONTROLLER] = original["workers"][CONTROLLER]
    require(adjusted == original, "Binding changed beyond the qualification controller")


def revalidation_source(source):
    require(source.is_dir() and not source.is_symlink(), "Need an ordinary source run directory")
    require(not any((source / name).exists() for name in
                    ("QUALIFIED", "MEASUREMENT_STARTED", "COMPLETE", "observations.jsonl",
                     "observations.csv", "summary.csv", "run.json")),
            "Revalidation requires an unsealed run without timing")
    require(all((source / name).is_file() and not (source / name).is_symlink()
                for name in SOURCE_ARTIFACTS), "Incomplete or nonordinary source qualification artifacts")
    return {name: sha(source / name) for name in SOURCE_ARTIFACTS}


def revalidate(args):
    source = args.source_output
    source_hashes = revalidation_source(source)
    config = json.loads((source / "config-private.json").read_text())
    require("qualification_origin" not in config, "Cannot chain revalidations")
    files = json.loads((source / "inputs-private.json").read_text())
    full_inventory = json.loads((source / "inventory-private.json").read_text())
    validate_inventory_count(full_inventory["files"], config["expected_files"])
    require(files == selected_inputs(full_inventory["files"], config["smoke"]), "Source selection changed")
    require(inventory(Path(config["cache"])) == full_inventory, "Cache inventory changed since source qualification")
    original = json.loads((source / "binding-before.json").read_text())
    before = bindings(config, files)
    validate_revalidation_bindings(original, before, args.original_controller)
    known_errors = {r["id"]: exclusion for r in files
        if (exclusion := expected_exclusion(r, before["inputs"][r["id"]]))}
    require(len(known_errors) == 2, "Both canonical hash-bound malformed inputs must be present")
    qualified = {variant: qualification_records(source / (variant + "-qualification-private.jsonl"), files)
                 for variant in ("baseline", "candidate")}
    differences = validate_qualification(files, qualified["baseline"], qualified["candidate"], known_errors)
    args.output.mkdir(parents=True, exist_ok=False, mode=0o700)
    for name in ("inventory-private.json", "inputs-private.json",
                 "baseline-qualification-private.jsonl", "candidate-qualification-private.jsonl"):
        shutil.copyfile(source / name, args.output / name)
        require(sha(args.output / name) == source_hashes[name], "Copied qualification artifact changed")
    config.update(qualification_policy=QUALIFICATION_POLICY,
                  qualification_origin="revalidated-complete-records")
    write_json(args.output / "config-private.json", config)
    write_json(args.output / "binding-before.json", before)
    shutil.copyfile(args.original_controller, args.output / "original-controller.py")
    shutil.copyfile(source / "binding-before.json", args.output / "original-binding.json")
    require(sha(args.output / "original-controller.py") == original["workers"][CONTROLLER],
            "Archived controller changed while copying")
    require(sha(args.output / "original-binding.json") == source_hashes["binding-before.json"],
            "Original binding changed while copying")
    write_json(args.output / "revalidation.json", dict(
        policy=QUALIFICATION_POLICY, revalidated_utc=datetime.now(timezone.utc).isoformat(),
        original_controller_sha256=original["workers"][CONTROLLER],
        current_controller_sha256=before["workers"][CONTROLLER],
        original_artifact_sha256=source_hashes,
        original_status="Complete qualification records; no qualification seal or timed reads",
        new_r_qualification_reads=0,
        rationale="Require complete baseline/candidate parity within each output. Dibble construction can widen string storage declarations to fit decoded UTF-8; cross-output signatures are recorded, while status, shape and conditions must match."))
    require(inventory(Path(config["cache"])) == full_inventory, "Cache inventory changed during revalidation")
    require(bindings(config, files) == before, "Binding changed during revalidation")
    require(revalidation_source(source) == source_hashes, "Original qualification artifacts changed")
    write_json(args.output / "qualification.json", qualification_summary(
        files, qualified["candidate"], known_errors, before, differences))
    write_json(args.output / "QUALIFIED", qualified_seal(args.output))
    print("Revalidated " + str(len(files)) + " files from unchanged complete records; timing has not started", flush=True)


def prepare(args):
    config = {name: str(getattr(args, name)) for name in
        ("baseline_build_work", "candidate_build_work", "cache")}
    config["smoke"] = args.smoke
    config["expected_files"] = args.expected_files
    config["qualification_policy"] = QUALIFICATION_POLICY
    config["qualification_origin"] = "fresh-r-reads"
    all_files = inventory(args.cache)
    validate_inventory_count(all_files["files"], args.expected_files)
    files = selected_inputs(all_files["files"], args.smoke)
    args.output.mkdir(parents=True, exist_ok=False, mode=0o700)
    write_json(args.output / "config-private.json", config)
    write_json(args.output / "inventory-private.json", all_files)
    write_json(args.output / "inputs-private.json", files)
    before = bindings(config, files)
    known_errors = {r["id"]: exclusion for r in files
        if (exclusion := expected_exclusion(r, before["inputs"][r["id"]]))}
    require(len(known_errors) == 2, "Both canonical hash-bound malformed inputs must be present")
    write_json(args.output / "binding-before.json", before)
    for variant in ("baseline", "candidate"):
        library = Path(config[variant + "_build_work"]) / "library"
        run_child(args.output, "qualify-" + variant, HERE / "cache-qualify.R",
            [library, args.output / "inputs-private.json", args.output / (variant + "-qualification-private.jsonl")],
            child_environment(library))
    qualified = {variant: qualification_records(args.output / (variant + "-qualification-private.jsonl"), files)
                 for variant in ("baseline", "candidate")}
    differences = validate_qualification(files, qualified["baseline"], qualified["candidate"], known_errors)
    require(inventory(args.cache) == all_files, "Cache inventory changed during qualification")
    require(bindings(config, files) == before, "Binding changed during qualification")
    write_json(args.output / "qualification.json", qualification_summary(
        files, qualified["candidate"], known_errors, before, differences))
    write_json(args.output / "QUALIFIED", qualified_seal(args.output))
    print("Qualified " + str(len(files)) + " files for both outputs; timing has not started", flush=True)


def measure(args):
    output = args.output
    require((output / "QUALIFIED").is_file() and not (output / "MEASUREMENT_STARTED").exists(),
            "Need a qualified directory without prior timing")
    config = json.loads((output / "config-private.json").read_text())
    require(config.get("qualification_policy") == QUALIFICATION_POLICY, "Unrecognized qualification policy")
    files = json.loads((output / "inputs-private.json").read_text())
    full_inventory = json.loads((output / "inventory-private.json").read_text())
    before = json.loads((output / "binding-before.json").read_text())
    seal = json.loads((output / "QUALIFIED").read_text())
    require(qualified_seal(output) == seal, "Qualification artifacts changed")
    require(files == selected_inputs(full_inventory["files"], config["smoke"]), "Qualified selection changed")
    require(inventory(Path(config["cache"])) == full_inventory, "Cache inventory changed before timing")
    require(bindings(config, files) == before, "Binding changed before timing")
    qualified = qualification_records(output / "candidate-qualification-private.jsonl", files)
    baseline = qualification_records(output / "baseline-qualification-private.jsonl", files)
    known_errors = {r["id"] for r in files if expected_exclusion(r, before["inputs"][r["id"]])}
    validate_qualification(files, baseline, qualified, known_errors)
    library = Path(config["candidate_build_work"]) / "library"
    environment = child_environment(library)
    observations = []
    started = datetime.now(timezone.utc).isoformat()
    (output / "MEASUREMENT_STARTED").write_text(started + "\n")
    for index, row in enumerate(files):
        require(sha(row["path"]) == before["inputs"][row["id"]]["sha256"], "Input changed before read")
        for position, container in enumerate(OUTPUTS if index % 2 == 0 else OUTPUTS[::-1], 1):
            resource, log = run_child(output, row["id"] + "-" + container, HERE / "cache-worker.R",
                [row["path"], container], environment)
            q = qualified[(row["id"], container)]
            result = parse_timed(log, q)
            observations.append(dict(id=row["id"], corpus=row["corpus"], output=container,
                position=position, status=result["status"], rows=result.get("rows"), columns=result.get("columns"),
                wall_seconds=result["elapsed_seconds"], read_cpu_seconds=result["read_cpu_seconds"],
                process_cpu_seconds=resource["process_user_cpu_seconds"]+resource["process_system_cpu_seconds"],
                peak_rss_bytes=resource["peak_rss_bytes"], log_sha256=resource["log_sha256"]))
            with (output / "observations.jsonl").open("a") as stream:
                stream.write(json.dumps(observations[-1], sort_keys=True) + "\n")
        if (index+1) % 25 == 0:
            print(f"Measured {index+1}/{len(files)} files", flush=True)
    validate_observations(observations, files)
    write_csv(output / "observations.csv", observations)
    require(inventory(Path(config["cache"])) == full_inventory, "Cache inventory changed during timing")
    after = bindings(config, files)
    require(after == before, "Binding changed during timing")
    write_json(output / "binding-after.json", after)
    summaries = []
    for corpus in sorted({r["corpus"] for r in files}) + ["ALL"]:
        selected = [r for r in files if corpus == "ALL" or r["corpus"] == corpus]
        ids = {r["id"] for r in selected}
        for container in OUTPUTS:
            rows = [r for r in observations if r["id"] in ids and r["output"] == container and r["status"] == "ok"]
            if not rows:
                continue
            ok_ids = {r["id"] for r in rows}
            summaries.append(dict(corpus=corpus, output=container,
                attempted_files=len(selected), readable_files=len(rows), excluded_files=len(selected)-len(rows),
                dta_bytes=sum(r["bytes"] for r in selected if r["id"] in ok_ids),
                wall_seconds=sum(r["wall_seconds"] for r in rows),
                read_cpu_seconds=sum(r["read_cpu_seconds"] for r in rows),
                process_cpu_seconds=sum(r["process_cpu_seconds"] for r in rows),
                max_peak_rss_bytes=max(r["peak_rss_bytes"] for r in rows)))
    require(qualified_seal(output) == seal, "Qualification artifacts changed during timing")
    write_csv(output / "summary.csv", summaries)
    write_json(output / "run.json", dict(started_utc=started, finished_utc=datetime.now(timezone.utc).isoformat(),
        smoke=config["smoke"], attempted_files=len(files), attempts=len(observations),
        outputs=OUTPUTS, threads=0, source_inventory_files=len(full_inventory["files"]),
        skipped_symlink_aliases=len(full_inventory["skipped_symlinks"]),
        platform=platform.platform(), logical_cpus=os.cpu_count(),
        qualification_policy=config["qualification_policy"],
        qualification_origin=config["qualification_origin"],
        protocol="One first read per fresh process/output; no forced pre-read GC; per-file hashing warms cache; output order alternates by file",
        haven_invocations=0, stata_invocations=0, arrow_invocations=0))
    (output / "COMPLETE").write_text("smoke\n" if config["smoke"] else "full-cache\n")
    print("Completed " + str(len(observations)) + " read_dta attempts", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="phase", required=True)
    prep = sub.add_parser("prepare")
    for name in ("baseline-build-work", "candidate-build-work", "cache", "output"):
        prep.add_argument("--"+name, type=lambda value: Path(value).resolve(), required=True)
    prep.add_argument("--smoke", action="store_true")
    prep.add_argument("--expected-files", type=int, required=True)
    audit = sub.add_parser("revalidate")
    for name in ("source-output", "original-controller", "output"):
        audit.add_argument("--"+name, type=lambda value: Path(value).resolve(), required=True)
    timed = sub.add_parser("measure")
    timed.add_argument("--output", type=lambda value: Path(value).resolve(), required=True)
    args = parser.parse_args()
    require(sys.platform in ("darwin", "linux"), "Unsupported wait4 RSS platform")
    require(shutil.which("Rscript") is not None, "Rscript unavailable")
    dict(prepare=prepare, revalidate=revalidate, measure=measure)[args.phase](args)


if __name__ == "__main__":
    main()
