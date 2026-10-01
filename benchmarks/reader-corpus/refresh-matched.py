#!/usr/bin/env python3
"""Refresh only dtatools on the recovered historical 1,812-file comparison set."""
import argparse
import csv
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import importlib.util
import io
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
from run import parse_read
sys.path.insert(0, str(HERE.parent / "reader-refresh"))
from driver_common import child_environment, require, run_child, sha
SPEC = importlib.util.spec_from_file_location("matched_builds", HERE.parent / "r-file-readers/record-builds.py")
BUILDS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDS)
METHODS = ("read_dta_tibble", "read_arrow_tibble", "read_dta_dibble", "read_arrow_dibble")
EXPECTED = {"DHS": (641, 46903402101), "MICS": (949, 3690394621), "NSFG": (222, 5771879262)}
MEMBERSHIP_SHA = "bf18096a711e6cfd031e522d5ab4db0dfb6d97bdce057ba6f8680bdd36ff8aa4"
INVENTORY_SHA = "8f8964891ab2d9429988a8bcddf8ddb3a32338b3a4399ad154dc70df8a370367"
HISTORICAL = HERE / "results-2026-09-16-base-r"
SEAL_FILES = ("config-private.json", "inputs-private.json", "binding-before.json",
              "binding-qualified.json", "qualification.json", "protocol.json")
RECOVERY_FILES = ("audit.json", "inventory.csv", "matched.csv", "historical-format-summary.tsv")


def now():
    return datetime.now(timezone.utc).isoformat()


def write_json(path, value, public=True):
    path.write_bytes(BUILDS.public_bytes(value) if public else BUILDS.json_bytes(value))


def write_csv(path, rows):
    require(bool(rows), "Empty result table")
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def select_membership(path, recovery, smoke):
    require(sha(path) == MEMBERSHIP_SHA, "Recovered membership identity differs")
    audit = json.loads((recovery / "audit.json").read_text())
    require(audit["original_inventory_sha256"] == INVENTORY_SHA and
            audit["matched_files"] == 1812 and audit["original_raw_tsv_recovered"] is False,
            "Missing exact membership recovery proof")
    for filename, field in (("inventory.csv", "inventory_csv_sha256"), ("matched.csv", "matched_csv_sha256"),
                            ("historical-format-summary.tsv", "summary_sha256")):
        require(sha(recovery / filename) == audit[field], "Recovery evidence bytes differ")
    require(audit["retained_comparison_csv_sha256"] == sha(HISTORICAL / "corpus-summary.csv") and
            len(audit["groups"]) == 16 and all(g["matching_subsets"] == 1 for g in audit["groups"]),
            "Recovery is not unique or does not match retained comparator coverage")
    rows = json.loads(path.read_text())
    require(len(rows) == 1823 and len({r["id"] for r in rows}) == 1823, "Wrong recovered inventory")
    selected = [r for r in rows if r["common"] is True]
    for corpus, expected in EXPECTED.items():
        subset = [r for r in selected if r["corpus"] == corpus]
        require((len(subset), sum(int(r["bytes"]) for r in subset)) == expected,
                "Historical comparison count or bytes differ")
    require(len(selected) == 1812, "Wrong historical comparison count")
    with (recovery / "matched.csv").open() as stream:
        matched = list(csv.DictReader(stream))
    require({(r["id"], r["corpus"], int(r["bytes"])) for r in matched} ==
            {(r["id"], r["corpus"], int(r["bytes"])) for r in selected}, "Private and public membership differ")
    if smoke:
        ids = {min((r for r in selected if r["corpus"] == corpus), key=lambda r: int(r["bytes"]))["id"]
               for corpus in EXPECTED}
        selected = [r for r in selected if r["id"] in ids]
    return selected


def method_order(index):
    offset = (index // 2) % len(METHODS)
    order = METHODS[offset:] + METHODS[:offset]
    return tuple(reversed(order)) if index % 2 else order


def validate_qualification(record, identifier):
    require(record.get("id") == identifier and set(record.get("containers", {})) == {"tibble", "dibble"},
            "Incomplete qualification")
    shapes = []
    for output in ("tibble", "dibble"):
        result = record["containers"][output]
        shape = (result.get("rows"), result.get("columns"))
        require(all(type(v) is int and v >= 0 for v in shape) and shape[1] > 0,
                "Invalid qualified shape")
        require(isinstance(result.get("signature"), str) and bool(result["signature"]) and
                result.get("warnings") == [], "Missing signature or unexpected warnings")
        shapes.append(shape)
    require(shapes[0] == shapes[1], "Output container shapes differ")


def historical_comparators(raw):
    rows = list(csv.DictReader(io.StringIO(raw.decode())))
    require(len(rows) == 12, "Wrong historical table")
    retained = [r for r in rows if r["method"] in ("haven", "stata")]
    require({(r["corpus"], r["method"]) for r in retained} ==
            {(c, m) for c in EXPECTED for m in ("haven", "stata")} and len(retained) == 6,
            "Incomplete historical comparator cells")
    for row in retained:
        require((int(row["files"]), int(row["dta_bytes"])) == EXPECTED[row["corpus"]] and
                row["measurement_date"] == "2026-08-24", "Historical comparator membership or date differs")
    return retained


def aggregate(inputs, observations, date):
    expected = [(r["id"], method, position) for index, r in enumerate(inputs)
                for position, method in enumerate(method_order(index), 1)]
    require([(r["id"], r["method"], r["method_position"]) for r in observations] == expected,
            "Missing, duplicate, or reordered timed attempt")
    result = []
    for corpus in EXPECTED:
        files = [r for r in inputs if r["corpus"] == corpus]
        require(bool(files), "Missing survey corpus")
        for method in METHODS:
            rows = [r for r in observations if r["corpus"] == corpus and r["method"] == method]
            require(len(rows) == len(files) and all(r["status"] == "ok" for r in rows),
                    "Incomplete successful reads")
            result.append(dict(corpus=corpus, method=method, files=len(files),
                dta_bytes=sum(int(r["bytes"]) for r in files),
                wall_seconds=sum(r["elapsed_seconds"] for r in rows),
                read_cpu_seconds=sum(r["read_cpu_seconds"] for r in rows),
                process_cpu_seconds=sum(r["process_cpu_seconds"] for r in rows),
                max_peak_rss_bytes=max(r["peak_rss_bytes"] for r in rows), measurement_date=date))
    return result


def runtime(library):
    code = '''.libPaths(c(commandArgs(TRUE)[1], .libPaths()));
      stopifnot(requireNamespace("dtatools", quietly=TRUE));
      cat("RUNTIME", R.version.string, R.version$platform,
          normalizePath(file.path(R.home("bin"), "exec/R")), sep="\\t"); cat("\\n");
      for (p in sort(loadedNamespaces())) {
        path <- if (p == "base") file.path(R.home("library"), "base") else getNamespaceInfo(p,"path")
        cat("PACKAGE", p, as.character(packageVersion(p)), path, sep="\\t"); cat("\\n")
      }'''
    text = subprocess.check_output([shutil.which("Rscript"), "--vanilla", "-e", code, str(library)],
                                   env=child_environment(library), text=True)
    lines = [r.split("\t") for r in text.splitlines()]
    require(lines and len(lines[0]) == 4 and lines[0][0] == "RUNTIME", "Missing R runtime binding")
    result = dict(version=lines[0][1], platform=lines[0][2], r_executable_sha256=sha(lines[0][3]), packages={})
    for row in lines[1:]:
        require(len(row) == 4 and row[0] == "PACKAGE", "Invalid dependency binding")
        directory = Path(row[3])
        inventory = {p.relative_to(directory).as_posix(): sha(p) for p in sorted(directory.rglob("*")) if p.is_file()}
        result["packages"][row[1]] = dict(version=row[2], files=len(inventory),
            inventory_sha256=BUILDS.sha_bytes(BUILDS.json_bytes(inventory)))
    require("dtatools" in result["packages"] and "jsonlite" not in result["packages"],
            "Timed namespace setup differs")
    return result


def binding(config, inputs, arrows=False):
    work = Path(config["candidate_build_work"])
    receipt, _, receipt_sha = BUILDS.verified_receipt(work, "candidate")
    identities = {}
    for row in inputs:
        path = Path(row["dta"])
        info = path.stat()
        require(path.is_file() and not path.is_symlink() and info.st_size == int(row["bytes"]) and
                abs(info.st_mtime - float(row["mtime"])) < 1e-5, "Input differs from historical inventory")
        entry = dict(dta=dict(bytes=info.st_size, sha256=sha(path)))
        if arrows or row["reuse"]:
            arrow = Path(row["arrow"])
            require(arrow.is_file() and not arrow.is_symlink(), "Missing ordinary Arrow input")
            entry["arrow"] = dict(bytes=arrow.stat().st_size, sha256=sha(arrow))
        identities[row["id"]] = entry
    scripts = [Path(__file__), HERE / "refresh-matched-worker.R", HERE / "refresh-matched-prepare.R",
               HERE / "refresh-matched-monitor.py", HERE / "run.py", HERE.parent / "reader-refresh/driver_common.py",
               HERE.parent / "reader-refresh/workers/benchmark-common.R"]
    environment = child_environment(work / "library")
    return dict(build_receipt_sha256=receipt_sha, build_receipt=receipt, inputs=identities,
        workers={p.relative_to(ROOT).as_posix(): sha(p) for p in scripts}, build_verifier=BUILDS.artifact_hashes(),
        runtime=runtime(work / "library"), rscript_sha256=sha(Path(shutil.which("Rscript")).resolve()),
        host=platform.platform(), cpu_count=os.cpu_count(),
        recovery={name: sha(Path(config["recovery"]) / name) for name in RECOVERY_FILES},
        membership_sha256=sha(config["membership"]),
        historical={name: sha(HISTORICAL / name) for name in ("corpus-summary.csv", "provenance.json")},
        thread_environment={k: environment[k] for k in ("OMP_NUM_THREADS", "RAYON_NUM_THREADS", "R_PARALLEL_NUM_THREADS",
            "OPENBLAS_NUM_THREADS", "VECLIB_MAXIMUM_THREADS") if k in environment})


def prepare(args):
    require(not args.work.exists(), "Prepare requires a new work directory")
    selected = select_membership(args.membership, args.recovery, args.smoke)
    reused = json.loads(args.arrow_manifest.read_text()) if args.arrow_manifest else {}
    require(isinstance(reused, dict) and set(reused) <= {r["id"] for r in selected}, "Unknown Arrow reuse entry")
    args.work.mkdir(parents=True, mode=0o700)
    for name in ("arrow", "qualification-private", "prepare-jobs"):
        (args.work / name).mkdir()
    config = {k: str(v) if isinstance(v, Path) else v for k, v in vars(args).items() if k != "action"}
    inputs = [dict(row, dta=str(args.cache / row["relative_path"]),
                   arrow=str(Path(reused[row["id"]]).resolve()) if row["id"] in reused else
                       str(args.work / "arrow" / (row["id"] + ".arrow")), reuse=row["id"] in reused)
              for row in selected]
    for row in inputs:
        require(re.fullmatch(r"(?:DHS|MICS|NSFG)-[0-9]+", row["id"]) is not None and
                Path(row["relative_path"]).parts[0] == row["corpus"] and
                ".." not in Path(row["relative_path"]).parts, "Invalid recovered input identity")
    write_json(args.work / "config-private.json", config, public=False)
    write_json(args.work / "inputs-private.json", inputs, public=False)
    before = binding(config, inputs)
    write_json(args.work / "binding-before.json", before)
    write_json(args.work / "protocol.json", dict(smoke=args.smoke, files=len(inputs), methods=METHODS,
        calls_per_process=1, output="explicit tibble and dibble", threads="adaptive default 0", numeric_altrep=True,
        arrow_verify=True, timed_worker_jsonlite=False, cache="both complete files hashed before each group of four reads",
        wall="first public read; original base-R corpus timer, excluding process and namespace startup",
        read_cpu="user.self plus sys.self over the wall interval", process_cpu="wait4 user plus system whole process",
        peak_rss="wait4 maximum resident bytes of whole process", order="rotations each paired with its reverse by file",
        qualification="separate untimed DTA/Arrow complete signatures within each output; matching shapes; no warnings",
        preparation="Arrow saved from explicit tibble to preserve source declarations; converted before all timing",
        preparation_workers=args.prepare_workers,
        historical_comparator_date="2026-08-24", historical_comparators_run=False,
        original_raw_tsv_recovered=False, membership="uniquely recovered historical set, bound to exact inventory bytes"))
    qualifications = {}
    environment = child_environment(Path(config["candidate_build_work"]) / "library")
    def qualify(row):
        result_path = args.work / "qualification-private" / (row["id"] + ".json")
        job = dict(id=row["id"], dta=row["dta"], arrow=row["arrow"], reuse=row["reuse"],
                   library=str(Path(config["candidate_build_work"]) / "library"))
        job_path = args.work / "prepare-jobs" / (row["id"] + ".json")
        write_json(job_path, job, public=False)
        run_child(args.work / "prepare-jobs", row["id"], HERE / "refresh-matched-prepare.R",
                  [job_path, result_path], environment)
        record = json.loads(result_path.read_text())
        validate_qualification(record, row["id"])
        return row["id"], record

    # Only untimed preparation overlaps. Bound pending work to one batch so a
    # failure finishes at most the other children in that batch before stopping.
    with ThreadPoolExecutor(max_workers=args.prepare_workers) as pool:
        for start in range(0, len(inputs), args.prepare_workers):
            batch = inputs[start:start + args.prepare_workers]
            qualifications.update(pool.map(qualify, batch))
            completed = start + len(batch)
            if completed // 25 != start // 25 or completed == len(inputs):
                print(f"QUALIFIED {completed}/{len(inputs)} files", flush=True)
    write_json(args.work / "qualification.json", qualifications)
    require(binding(config, inputs) == before, "Bindings changed during preparation")
    qualified = binding(config, inputs, arrows=True)
    write_json(args.work / "binding-qualified.json", qualified)
    write_json(args.work / "QUALIFIED.json", dict(completed_utc=now(), files=len(inputs), smoke=args.smoke,
        artifacts={name: sha(args.work / name) for name in SEAL_FILES}))
    print("PREPARED: all files qualified; no timed reads started", flush=True)


def measure(args):
    work = args.work
    require(not (work / "MEASUREMENT_STARTED.json").exists() and not (work / "COMPLETE").exists(),
            "Measurements cannot restart or overwrite a prior attempt")
    seal = json.loads((work / "QUALIFIED.json").read_text())
    require(seal["artifacts"] == {name: sha(work / name) for name in SEAL_FILES}, "Qualification seal changed")
    config = json.loads((work / "config-private.json").read_text())
    inputs = json.loads((work / "inputs-private.json").read_text())
    qualifications = json.loads((work / "qualification.json").read_text())
    expected = json.loads((work / "binding-qualified.json").read_text())
    require(binding(config, inputs, arrows=True) == expected, "Bindings changed after preparation")
    observations = []
    environment = child_environment(Path(config["candidate_build_work"]) / "library")
    (work / "timed-private").mkdir()
    started = now()
    write_json(work / "MEASUREMENT_STARTED.json", dict(started_utc=started, expected_attempts=len(inputs) * 4))
    for index, row in enumerate(inputs):
        require({kind: dict(bytes=Path(row[kind]).stat().st_size, sha256=sha(row[kind])) for kind in ("dta", "arrow")} ==
                expected["inputs"][row["id"]], "Input changed before its timed reads")
        for position, method in enumerate(method_order(index), 1):
            reader, output = method.rsplit("_", 1)
            qualified = qualifications[row["id"]]["containers"][output]
            resources, log = run_child(work / "timed-private", row["id"] + "-" + method,
                HERE / "refresh-matched-worker.R", [reader, row["arrow" if reader == "read_arrow" else "dta"], output], environment)
            result = parse_read(log, reader, dict(status="ok", **qualified))
            cpu = resources["process_user_cpu_seconds"] + resources["process_system_cpu_seconds"]
            require(math.isfinite(cpu) and cpu > 0 and resources["peak_rss_bytes"] > 0, "Invalid process resources")
            observation = dict(id=row["id"], corpus=row["corpus"], method=method, method_position=position,
                status=result["status"], rows=result["rows"], columns=result["columns"],
                elapsed_seconds=result["elapsed_seconds"], read_cpu_seconds=result["read_cpu_seconds"],
                process_cpu_seconds=cpu, peak_rss_bytes=resources["peak_rss_bytes"])
            observations.append(observation)
            with (work / "observations.jsonl").open("a") as stream:
                stream.write(json.dumps(observation, sort_keys=True) + "\n")
        if (index + 1) % 25 == 0 or index + 1 == len(inputs):
            print(f"MEASURED {index + 1}/{len(inputs)} files; {len(observations)} successful reads", flush=True)
    finished = now()
    after = binding(config, inputs, arrows=True)
    write_json(work / "binding-after.json", after)
    require(after == expected, "Bindings changed during measurements")
    require(seal["artifacts"] == {name: sha(work / name) for name in SEAL_FILES}, "Qualification artifacts changed")
    summary = aggregate(inputs, observations, started[:10])
    write_csv(work / "observations.csv", observations)
    write_csv(work / "summary.csv", summary)
    historical_raw = (HISTORICAL / "corpus-summary.csv").read_bytes()
    (work / "historical-summary.csv").write_bytes(historical_raw)
    retained = historical_comparators(historical_raw)
    write_csv(work / "historical-comparators.csv", retained)
    if not config["smoke"]:
        write_csv(work / "comparison.csv", summary + retained)
    artifacts = ("binding-before.json", "binding-qualified.json", "binding-after.json", "protocol.json",
        "qualification.json", "QUALIFIED.json", "MEASUREMENT_STARTED.json", "observations.jsonl", "observations.csv",
        "summary.csv", "historical-summary.csv", "historical-comparators.csv") + (() if config["smoke"] else ("comparison.csv",))
    write_json(work / "completion.json", dict(started_utc=started, finished_utc=finished, smoke=config["smoke"],
        files=len(inputs), successful_reads=len(observations), qualification_reads=len(inputs) * 4,
        historical_comparator_invocations=0, final_bindings_matched=True,
        artifacts={name: sha(work / name) for name in artifacts}))
    (work / "COMPLETE").write_text(f"{len(observations)} successful reads; smoke={config['smoke']}; bindings matched.\n")
    print("COMPLETE: every observation retained; final bindings matched", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    preparation = sub.add_parser("prepare")
    for name in ("candidate-build-work", "membership", "recovery", "work"):
        preparation.add_argument("--" + name, type=lambda x: Path(x).resolve(), required=True)
    preparation.add_argument("--cache", type=lambda x: Path(x).resolve(), default=Path("/opt/aww_cache"))
    preparation.add_argument("--arrow-manifest", type=lambda x: Path(x).resolve())
    preparation.add_argument("--smoke", action="store_true")
    preparation.add_argument("--prepare-workers", type=int, choices=(1, 2, 4), default=4)
    measurement = sub.add_parser("measure")
    measurement.add_argument("--work", type=lambda x: Path(x).resolve(), required=True)
    args = parser.parse_args()
    (prepare if args.action == "prepare" else measure)(args)


if __name__ == "__main__":
    main()
