#!/usr/bin/env python3
"""Fresh-process, warm-filesystem reader CPU/thread scaling; no parity gate."""
import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import shutil
import signal
import statistics
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SETTINGS = ("stata-1", "dta-1", "dta-2", "dta-4", "dta-8", "dta-auto",
            "arrow-1", "arrow-auto", "stata-8")


def sha(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def orders(settings=SETTINGS):
    # Exact 5/5 pairwise precedence balance. Ten rounds with nine settings
    # cannot give equal frequencies at every position; retain each position.
    result = []
    for shift in range(5):
        offset = shift % len(settings)
        forward = settings[offset:] + settings[:offset]
        result.extend((forward, tuple(reversed(forward))))
    return result


def stata_string(value):
    value = str(value)
    if any(x in value for x in '\n\r"`$'):
        raise ValueError("Unsupported character in Stata benchmark path")
    return '"' + value + '"'


def overlapping_paths(first, second):
    return first == second or first.is_relative_to(second) or second.is_relative_to(first)


def stata_program(plugin, path, output, processors, rows, columns, empty=False):
    read = "" if empty else f"quietly use {stata_string(path)}, clear\n"
    check = "" if empty else f"assert _N == {rows}\nassert c(k) == {columns}\n"
    # The output handle is opened before timing, and no file output occurs
    # between start and stop. The plugin survives use, clear.
    return f'''version 18.0
clear all
set more off
set maxvar 32767
set processors {processors}
assert c(MP) == 1
assert c(processors) == {processors}
program cpuclock, plugin using({stata_string(plugin)})
file open results using {stata_string(output)}, write text replace
file write results "kind,index,wall,user,system,rows,columns,processors,MP,processors_lic,stata_version" _n
forvalues iteration = 1/{100 if empty else 1} {{
plugin call cpuclock, start
{read}plugin call cpuclock, stop
{check}file write results "{'empty' if empty else 'read'}," (`iteration') "," %21.12f (scalar(_dta_cpu_wall)) "," %21.12f (scalar(_dta_cpu_user)) "," %21.12f (scalar(_dta_cpu_system)) "," (_N) "," (c(k)) "," (c(processors)) "," (c(MP)) "," (c(processors_lic)) "," (c(stata_version)) _n
}}
file close results
exit, clear
'''


def child(command, directory, environment):
    started = time.monotonic()
    with (directory / "process.log").open("w") as stream:
        process = subprocess.Popen(command, cwd=directory, env=environment,
            stdout=stream, stderr=subprocess.STDOUT)
        try:
            _, status, usage = os.wait4(process.pid, 0)
        except BaseException:
            while True:
                try:
                    try:
                        os.kill(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    _, status, _ = os.wait4(process.pid, 0)
                    process.returncode = os.waitstatus_to_exitcode(status)
                    break
                except (InterruptedError, KeyboardInterrupt):
                    continue
                except ChildProcessError:
                    process.returncode = 1
                    break
            raise
        process.returncode = os.waitstatus_to_exitcode(status)
    if process.returncode:
        raise RuntimeError("Reader child failed; inspect private job " + directory.name)
    return dict(process_wall=time.monotonic() - started,
        process_user=usage.ru_utime, process_system=usage.ru_stime,
        process_cpu=usage.ru_utime + usage.ru_stime,
        peak_rss_bytes=usage.ru_maxrss * (1 if platform.system() == "Darwin" else 1024))


def write_csv(path, rows):
    temporary = path.with_suffix(".tmp")
    with temporary.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(path)


def source_binding():
    names = subprocess.check_output(["git", "ls-files", "-z", "r-package/dtatools/R",
        "r-package/dtatools/src", "r-package/dtatools/DESCRIPTION",
        "r-package/dtatools/NAMESPACE", "r-package/dtatools/configure",
        "r-package/dtatools/configure.win"], cwd=ROOT).decode().split("\0")
    return dict(commit=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT,
        text=True).strip(), files={str(Path(name).relative_to("r-package/dtatools")):
                                  sha(ROOT / name) for name in names if name})


def qualify_binding(binding, reference, records, case_id, rows, columns):
    candidate = reference["libraries"]["candidate"]
    if (not candidate["source_build_dll_equals_installed"] or
            binding["installed"] != candidate["installed_files"] or
            binding["source"]["files"] != candidate["production_source"] or
            binding["source"]["commit"] != reference["candidate_head"]):
        raise ValueError("Candidate differs from the recorded installation/source build")
    signatures = []
    for kind, reader in (("dta", "read_dta"), ("arrow", "read_arrow")):
        qualified_input = reference["inputs"][case_id + "-" + kind]
        actual = dict(binding["inputs"][kind], rows=rows, columns=columns)
        if actual != qualified_input:
            raise ValueError("Input differs from qualified case: " + kind)
        selected = [row for row in records if row["key"] == case_id + "-" + reader
                    and row["library"] == "candidate"]
        if len(selected) != 1 or len(selected[0]["records"]) != 1:
            raise ValueError("Missing unambiguous read qualification")
        fields = selected[0]["records"][0].split("\t")
        if fields[:4] != ["QUALIFIED", reader, str(rows), str(columns)] or len(fields) != 5:
            raise ValueError("Invalid read qualification")
        signatures.append(fields[4])
    if signatures[0] != signatures[1]:
        raise ValueError("DTA/Arrow qualification signatures differ")
    return dict(case_id=case_id, signature=signatures[0],
        install_log_sha256=candidate["install_log_sha256"],
        source_build_dll_equals_installed=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("library", "dta", "arrow", "plugin", "output", "work",
                 "reference-provenance", "qualification"):
        parser.add_argument("--" + name, type=lambda x: Path(x).resolve(), required=True)
    parser.add_argument("--case-id", required=True)
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--columns", type=int, required=True)
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--settings", nargs="+", choices=SETTINGS)
    parser.add_argument("--stata", type=lambda x: Path(x).resolve(),
        default=Path("/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp"))
    args = parser.parse_args()
    if args.rows <= 0 or args.columns <= 0 or overlapping_paths(args.output, args.work):
        parser.error("Positive dimensions and disjoint public/private directories required")
    settings = tuple(args.settings or SETTINGS)
    if len(set(settings)) != len(settings):
        parser.error("Duplicate settings")
    schedule = orders(settings)[:1] if args.smoke else orders(settings)
    args.output.mkdir(parents=True, exist_ok=False)
    args.work.mkdir(parents=True, exist_ok=False)
    rscript = Path(shutil.which("Rscript")).resolve()
    environment = {key: value for key, value in os.environ.items()
        if not key.startswith(("DTATOOLS_EXPERIMENT_", "DTA_READ_PERF_"))}
    environment.update(R_LIBS=str(args.library), DTATOOLS_BENCH_LIB=str(args.library))
    package = args.library / "dtatools"
    plugin_record = json.loads(args.plugin.with_suffix(".json").read_text())
    if sha(args.plugin) != plugin_record["plugin_sha256"] or sha(HERE / "cpuclock.c") != plugin_record["wrapper_sha256"]:
        raise ValueError("Sampler differs from its build record")

    def binding():
        return dict(source=source_binding(),
            installed={str(path.relative_to(package)): sha(path)
                for path in sorted(package.rglob("*")) if path.is_file()},
            inputs={kind: dict(sha256=sha(getattr(args, kind)), bytes=getattr(args, kind).stat().st_size)
                for kind in ("dta", "arrow")}, plugin=plugin_record,
            plugin_sha256=sha(args.plugin), stata_sha256=sha(args.stata), Rscript_sha256=sha(rscript),
            reference_provenance_sha256=sha(args.reference_provenance),
            qualification_sha256=sha(args.qualification),
            workers={path.name: sha(path) for path in sorted(HERE.iterdir()) if path.is_file()},
            host=platform.platform(), cpu_count=os.cpu_count(),
            thread_environment={key: environment[key] for key in ("OMP_NUM_THREADS", "RAYON_NUM_THREADS",
                "R_PARALLEL_NUM_THREADS", "OPENBLAS_NUM_THREADS", "VECLIB_MAXIMUM_THREADS") if key in environment})

    initial = binding()  # Full input hashes also warm the filesystem cache.
    qualification = qualify_binding(initial, json.loads(args.reference_provenance.read_text()),
        json.loads(args.qualification.read_text()), args.case_id, args.rows, args.columns)
    initial["qualification"] = qualification
    initial["protocol"] = dict(dimensions=dict(rows=args.rows, columns=args.columns),
        settings=settings, orders=schedule, smoke=args.smoke, cache="warm filesystem",
        process="one full read per fresh process, first reader initialization included",
        read_clock="Stata CLOCK_MONOTONIC/getrusage(RUSAGE_SELF); R proc.time user.self/sys.self/elapsed",
        process_clock="wait4 user/system CPU and max RSS; monotonic launch-to-reap wall",
        threads="requested limits, not measured worker counts; auto passes threads=0L",
        arrow_verify=True, qualification="separate fresh-process canonical signature for every R thread setting; dimensions each timed read; input and candidate build bound to supplied qualification records",
        empty_intervals=100, overhead_subtracted=False, release_gate=False)
    (args.output / "provenance.json").write_text(json.dumps(initial, indent=2) + "\n")
    observations, overhead, runtimes = [], [], {}

    thread_qualification = []
    for setting in settings:
        kind, limit = setting.split("-")
        if kind == "stata":
            continue
        threads = 0 if limit == "auto" else int(limit)
        directory = args.work / ("qualify-" + setting)
        directory.mkdir()
        command = [str(rscript), "--vanilla", str(HERE / "worker.R"),
            "qualify-" + kind, str(getattr(args, kind)), str(threads), str(args.rows), str(args.columns)]
        child(command, directory, environment)
        lines = (directory / "process.log").read_text().splitlines()
        records = [line.split("\t")[1:] for line in lines if line.startswith("QUALIFIED\t")]
        if records != [[str(threads), str(args.rows), str(args.columns), qualification["signature"]]]:
            raise ValueError("Thread-specific canonical signature differs: " + setting)
        thread_qualification.append(dict(setting=setting, threads_requested=threads,
            rows=args.rows, columns=args.columns, signature=qualification["signature"],
            log_sha256=sha(directory / "process.log")))
        print("QUALIFIED " + setting, flush=True)
    if thread_qualification:
        write_csv(args.output / "thread-qualification.csv", thread_qualification)

    def run(setting, iteration, position, empty=False):
        kind, limit = setting.split("-")
        threads = 0 if limit == "auto" else int(limit)
        job = ("empty-" if empty else f"{iteration:02d}-{position:02d}-") + setting
        directory = args.work / job
        directory.mkdir()
        if kind == "stata":
            output = directory / "result.csv"
            script = directory / "read.do"
            script.write_text(stata_program(args.plugin, args.dta, output, threads,
                args.rows, args.columns, empty))
            resources = child([str(args.stata), "-b", "do", str(script)], directory, environment)
            with output.open() as stream:
                values = list(csv.DictReader(stream))
            clocks = [dict(wall=float(row["wall"]), user=float(row["user"]),
                system=float(row["system"]), rows=int(row["rows"]), columns=int(row["columns"])) for row in values]
            configuration = {key: values[0][key].strip() for key in
                ("processors", "MP", "processors_lic", "stata_version")}
            if setting in runtimes and runtimes[setting] != configuration:
                raise ValueError("Stata configuration changed")
            runtimes[setting] = configuration
        else:
            command = [str(rscript), "--vanilla", str(HERE / "worker.R"),
                "empty" if empty else kind, str(getattr(args, kind)), str(threads), str(args.rows), str(args.columns)]
            resources = child(command, directory, environment)
            lines = (directory / "process.log").read_text().splitlines()
            runtime = [line.split("\t")[1:] for line in lines if line.startswith("RUNTIME\t")]
            if len(runtime) != 1 or ("R" in runtimes and runtimes["R"] != runtime[0]):
                raise ValueError("Missing or changing R runtime")
            runtimes["R"] = runtime[0]
            records = [line.split("\t")[1:] for line in lines
                if line.startswith("EMPTY\t" if empty else "READ\t")]
            clocks = [dict(wall=float(row[1]), user=float(row[2]), system=float(row[3]), rows=0, columns=0)
                if empty else dict(wall=float(row[0]), user=float(row[1]), system=float(row[2]),
                    rows=int(row[3]), columns=int(row[4])) for row in records]
        if len(clocks) != (100 if empty else 1):
            raise ValueError("Unexpected number of clock records")
        for index, clock in enumerate(clocks, 1):
            if any(not math.isfinite(clock[key]) or clock[key] < 0 for key in ("wall", "user", "system")):
                raise ValueError("Invalid same-interval clock")
            if empty:
                overhead.append(dict(setting=setting, sample=index, **clock))
                continue
            if (clock["rows"], clock["columns"]) != (args.rows, args.columns) or clock["wall"] <= 0:
                raise ValueError("Invalid shape or unresolved read interval")
            observations.append(dict(round=iteration, position=position, setting=setting,
                threads_requested=threads, read_wall=clock["wall"], read_user=clock["user"],
                read_system=clock["system"], read_cpu=clock["user"] + clock["system"],
                cpu_per_wall=(clock["user"] + clock["system"]) / clock["wall"],
                rows=clock["rows"], columns=clock["columns"], **resources))

    # Empty intervals exercise both processor settings and the R sampler without
    # reading input. No estimate is subtracted from the retained observations.
    for setting in ("stata-1", "stata-8", "dta-auto"):
        run(setting, 0, 0, empty=True)
    write_csv(args.output / "empty-intervals.csv", overhead)
    for iteration, schedule_row in enumerate(schedule, 1):
        for position, setting in enumerate(schedule_row, 1):
            print(f"START {iteration}/{len(schedule)} {position}/{len(settings)} {setting}", flush=True)
            run(setting, iteration, position)
            write_csv(args.output / "observations.csv", observations)
            print(f"DONE read_wall={observations[-1]['read_wall']:.6f} read_cpu={observations[-1]['read_cpu']:.6f}", flush=True)
    final = binding()
    if final != {key: value for key, value in initial.items() if key not in ("protocol", "qualification")}:
        raise ValueError("Source, installation, sampler, worker or input changed")
    summaries = []
    for setting in settings:
        rows = [row for row in observations if row["setting"] == setting]
        for metric in ("read_wall", "read_cpu", "cpu_per_wall", "process_wall", "process_cpu", "peak_rss_bytes"):
            values = [row[metric] for row in rows]
            summaries.append(dict(setting=setting, metric=metric, samples=len(values),
                median=statistics.median(values), minimum=min(values), maximum=max(values)))
    write_csv(args.output / "summary.csv", summaries)
    (args.output / "runtimes.json").write_text(json.dumps(runtimes, indent=2) + "\n")
    (args.output / "completion.json").write_text(json.dumps(dict(observations=len(observations),
        final_bindings_matched=True, smoke=args.smoke), indent=2) + "\n")


if __name__ == "__main__":
    main()
