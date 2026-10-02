#!/usr/bin/env python3
"""Separate fresh-process Stata use/save controls for prepared synthetic fixtures."""
import argparse
import csv
import importlib.util
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import statistics

HERE = Path(__file__).resolve().parent
SCALING = HERE.parent / "reader-cpu-scaling"


def load_helper(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


readers = load_helper("reader_comparison", HERE / "run.py")
scaling = load_helper("reader_cpu_scaling", SCALING / "run.py")


def stata_program(plugin, source, output, saved, operation, rows, columns):
    quote = scaling.stata_string
    setup = f"quietly use {quote(source)}, clear\n" if operation == "save" else ""
    command = (f"quietly use {quote(source)}, clear" if operation == "use" else
               f"quietly save {quote(saved)}")
    # One operation per process. Save's source load and both result-file open
    # and write are outside the plugin interval. Each save targets a new path.
    return f'''version 18.0
clear all
set more off
set maxvar 32767
set processors 1
assert c(MP) == 1
assert c(processors) == 1
program cpuclock, plugin using({quote(plugin)})
{setup}file open results using {quote(output)}, write text
file write results "wall,user,system,rows,columns,processors,MP,processors_lic,stata_version" _n
plugin call cpuclock, start
{command}
plugin call cpuclock, stop
assert _N == {rows}
assert c(k) == {columns}
file write results %21.12f (scalar(_dta_cpu_wall)) "," %21.12f (scalar(_dta_cpu_user)) "," %21.12f (scalar(_dta_cpu_system)) "," (_N) "," (c(k)) "," (c(processors)) "," (c(MP)) "," (c(processors_lic)) "," (c(stata_version)) _n
file close results
exit, clear
'''


def qualify(rscript, fixture, path, directory, environment):
    directory.mkdir()
    scaling.child([str(rscript), "--vanilla", str(HERE / "worker.R"),
        "qualify-signature-read", "dtatools_dta_tibble", str(path), "1",
        str(fixture["rows"]), str(fixture["columns"]), "-"], directory, environment)
    records = [line.split("\t") for line in (directory / "process.log").read_text().splitlines()
               if line.startswith("QUALIFIED\t")]
    if len(records) != 1:
        raise RuntimeError("Missing qualification record in private job " + directory.name)
    return readers.validate_qualification(records[0],
        dict(qualification="signature", consumption="omitted_read_only"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("fixtures", "plugin", "library", "work"):
        parser.add_argument("--" + name, type=lambda value: Path(value).resolve(), required=True)
    parser.add_argument("--stata", type=lambda value: Path(value).resolve(),
        default=Path("/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp"))
    parser.add_argument("--pairs", type=int, default=6)
    parser.add_argument("--cases", nargs="+")
    args = parser.parse_args()
    if args.pairs <= 0 or args.pairs % 2:
        parser.error("Use a positive even pair count to balance use/save precedence")
    if platform.system() not in ("Darwin", "Linux"):
        parser.error("wait4 RSS units are supported only on macOS and Linux")
    executable = shutil.which("Rscript")
    if executable is None:
        parser.error("Rscript is unavailable")
    rscript = Path(executable).resolve()
    if not (args.library / "dtatools/DESCRIPTION").is_file():
        parser.error("Missing installed dtatools library")
    if not args.plugin.is_file() or not args.stata.is_file():
        parser.error("Missing Stata binary or clock plugin")
    fixtures = json.loads(args.fixtures.read_text())["reads"]
    if (not fixtures or len({item["id"] for item in fixtures}) != len(fixtures) or
            any(not re.fullmatch(r"[A-Za-z0-9_-]+", item["id"]) for item in fixtures)):
        parser.error("Provide unique, nonempty alphanumeric fixture identifiers")
    if args.cases:
        if len(set(args.cases)) != len(args.cases) or set(args.cases) - {item["id"] for item in fixtures}:
            parser.error("Unknown or duplicate fixture identifier")
        fixtures = [item for item in fixtures if item["id"] in args.cases]
    for item in fixtures:
        if (item.get("qualification") != "values" or
                any(type(item.get(field)) is not int or item[field] <= 0 for field in ("rows", "columns")) or
                item["columns"] > 32767 or not Path(item.get("dta", "")).is_file()):
            parser.error("Use prepared synthetic value fixtures with valid DTA files and dimensions")
        item["dta"] = str(Path(item["dta"]).resolve())
        scaling.stata_string(item["dta"])
    scaling.stata_string(args.plugin)
    scaling.stata_string(args.work)
    args.work.mkdir(parents=True, exist_ok=False, mode=0o700)
    jobs = args.work / "private-jobs"
    jobs.mkdir(mode=0o700)
    environment = readers.environment(args.library)
    plugin_record_path = args.plugin.with_suffix(".json")
    plugin_record = json.loads(plugin_record_path.read_text())
    if (readers.sha(args.plugin) != plugin_record["plugin_sha256"] or
            readers.sha(SCALING / "cpuclock.c") != plugin_record["wrapper_sha256"]):
        raise ValueError("Clock plugin differs from its build record")

    def bindings():
        return dict(fixtures_manifest_sha256=readers.sha(args.fixtures),
            inputs={item["id"]: dict(rows=item["rows"], columns=item["columns"],
                sha256=readers.sha(item["dta"]), bytes=Path(item["dta"]).stat().st_size)
                for item in fixtures}, installed=readers.inventory(args.library),
            plugin_sha256=readers.sha(args.plugin), plugin_record_sha256=readers.sha(plugin_record_path),
            stata_sha256=readers.sha(args.stata), Rscript_sha256=readers.sha(rscript),
            runtime=readers.runtime(str(rscript), args.library), host=platform.platform(),
            cpu_count=os.cpu_count(), workers={str(path.relative_to(HERE.parent)): readers.sha(path)
                for path in (Path(__file__).resolve(), HERE / "run.py", HERE / "worker.R",
                             HERE / "common.R", HERE / "runtime.R", SCALING / "run.py", SCALING / "cpuclock.c")})

    def write_json(name, value):
        (args.work / name).write_text(json.dumps(value, indent=2) + "\n")

    before = bindings()  # Input hashing warms the filesystem cache.
    write_json("provenance-before.json", before)
    write_json("protocol.json", dict(pairs=args.pairs, cases=[item["id"] for item in fixtures],
        processors=1, operations=["use", "save"], process="one operation per fresh Stata process",
        clocks="same-interval plugin CLOCK_MONOTONIC and getrusage(RUSAGE_SELF)",
        rss="whole Stata process wait4 peak; save includes untimed setup use",
        cache="warm filesystem; no explicit fsync or cold-storage claim",
        qualification="dtatools datasig on each source and every saved output outside timing",
        ordering="case rotation; use/save order reversed between repetitions",
        overhead_subtracted=False))
    references, qualifications, observations = {}, [], []
    for item in fixtures:
        record = qualify(rscript, item, item["dta"], jobs / ("source-" + item["id"]), environment)
        references[item["id"]] = record["signature"]
        qualifications.append(dict(case=item["id"], operation="source", pair=0, **record))
    configuration = None
    for pair in range(1, args.pairs + 1):
        offset = (pair - 1) % len(fixtures)
        ordered = fixtures[offset:] + fixtures[:offset]
        operations = ("use", "save") if pair % 2 else ("save", "use")
        for case_position, item in enumerate(ordered, 1):
            for operation_position, operation in enumerate(operations, 1):
                directory = jobs / f"{pair:02d}-{item['id']}-{operation}"
                directory.mkdir()
                result, saved = directory / "result.csv", directory / "saved.dta"
                script = directory / "control.do"
                script.write_text(stata_program(args.plugin, item["dta"], result, saved,
                    operation, item["rows"], item["columns"]))
                resources = scaling.child([str(args.stata), "-b", "do", str(script)], directory, environment)
                if not result.is_file():
                    raise RuntimeError("Stata produced no clock record in private job " + directory.name)
                with result.open() as stream:
                    rows = list(csv.DictReader(stream))
                if len(rows) != 1:
                    raise ValueError("Unexpected Stata clock record count")
                row = rows[0]
                clocks = {key: float(row[key]) for key in ("wall", "user", "system")}
                if (any(not math.isfinite(value) or value < 0 for value in clocks.values()) or
                        clocks["wall"] <= 0 or (int(row["rows"]), int(row["columns"])) !=
                        (item["rows"], item["columns"])):
                    raise ValueError("Invalid Stata clock or shape")
                runtime = {key: row[key].strip() for key in
                    ("processors", "MP", "processors_lic", "stata_version")}
                if runtime["processors"] != "1" or runtime["MP"] != "1":
                    raise ValueError("Unexpected Stata processor setting")
                if configuration is not None and configuration != runtime:
                    raise ValueError("Stata runtime changed")
                configuration = runtime
                observation = dict(case=item["id"], operation=operation, pair=pair,
                    case_position=case_position, operation_position=operation_position,
                    call_wall=clocks["wall"], call_user=clocks["user"], call_system=clocks["system"],
                    call_cpu=clocks["user"] + clocks["system"], rows=item["rows"], columns=item["columns"],
                    **resources)
                if operation == "save":
                    record = qualify(rscript, item, saved, directory / "qualification", environment)
                    if record["signature"] != references[item["id"]]:
                        raise ValueError("Stata save changed the dataset signature: " + item["id"])
                    qualifications.append(dict(case=item["id"], operation="save", pair=pair,
                        output_sha256=readers.sha(saved), output_bytes=saved.stat().st_size, **record))
                    saved.unlink()
                observations.append(observation)
                with (args.work / "raw.jsonl").open("a") as stream:
                    stream.write(json.dumps(observation) + "\n")
                write_json("qualification.json", qualifications)
                print(f"DONE {pair}/{args.pairs} {item['id']} {operation} "
                      f"wall={observation['call_wall']:.6f} cpu={observation['call_cpu']:.6f}", flush=True)
    after = bindings()
    write_json("provenance-after.json", after)
    if before != after:
        raise ValueError("Input, runtime, installation, sampler or worker changed during controls")
    summaries = []
    for item in fixtures:
        for operation in ("use", "save"):
            rows = [row for row in observations if row["case"] == item["id"] and row["operation"] == operation]
            for metric in ("call_wall", "call_cpu", "process_wall", "process_cpu", "peak_rss_bytes"):
                values = [row[metric] for row in rows]
                summaries.append(dict(case=item["id"], operation=operation, metric=metric,
                    observations=len(values), median=statistics.median(values), minimum=min(values), maximum=max(values)))
    scaling.write_csv(args.work / "summary.csv", summaries)
    write_json("stata-runtime.json", configuration)
    write_json("completion.json", dict(observations=len(observations), bindings_matched=True,
        saved_outputs_qualified=sum(record["operation"] == "save" for record in qualifications)))


if __name__ == "__main__":
    main()
