"""Bindings and child accounting shared by the reader-only refresh drivers."""
import hashlib
import itertools
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


WARM_CASES = {"100mb": (11, 231956, 40), "1gb": (11, 2320123, 40),
              "india": (5, 724115, 5972)}
WARM_METHODS = ("read_dta", "read_arrow_verify", "read_arrow_noverify")


def require(condition, message="reader benchmark validation failed"):
    """Keep required validation active when Python runs in optimized mode."""
    if not condition:
        raise RuntimeError(message)


def warm_read_schedule():
    """Balance every method position and pairwise order within each input."""
    result = []
    cases = list(WARM_CASES)
    for cohort, methods in enumerate(itertools.permutations(WARM_METHODS), 1):
        shift = (cohort - 1) % len(cases)
        for case_position, case in enumerate(cases[shift:] + cases[:shift], 1):
            for method_position, method in enumerate(methods, 1):
                result.append(dict(key=f"warm-{cohort:02d}-{case}-{method}", cohort=cohort,
                    case=case, case_position=case_position, method=method,
                    method_position=method_position, scheduled_position=len(result) + 1,
                    iterations=WARM_CASES[case][0]))
    return result


def required_read_keys():
    """Return every job needed to finish the reader refresh phase."""
    return ({row["key"] for row in warm_read_schedule()} |
            {"compare-" + case for case in WARM_CASES} |
            {"spot-india", "spot-nsfg", "spot-india-arrow"} |
            {"projection-" + case for case in ("tall", "wide", "tall-wide", "india-2021-wm")})


def load_jobs(path):
    """Read the append-only attempt history; reject partial or malformed rows."""
    path = Path(path)
    if not path.exists():
        return []
    jobs = []
    for number, line in enumerate(path.read_text().splitlines(), 1):
        try:
            job = json.loads(line)
        except json.JSONDecodeError as error:
            raise ValueError(f"malformed job record at line {number}") from error
        if (not isinstance(job, dict) or not isinstance(job.get("key"), str) or
                not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", job["key"]) or
                type(job.get("exit_code")) is not int or not -127 <= job["exit_code"] <= 255 or
                not isinstance(job.get("command"), list) or len(job["command"]) < 3 or
                not all(isinstance(value, str) and value for value in job["command"])):
            raise ValueError(f"malformed job record at line {number}")
        if "log_file" in job and (not isinstance(job["log_file"], str) or
                not re.fullmatch(re.escape(job["key"]) + r"\.attempt-[0-9]{4,}\.log", job["log_file"])):
            raise ValueError(f"invalid attempt log at line {number}")
        jobs.append(job)
    return jobs


def latest_job_attempts(jobs, expected_keys=None):
    """Keep history intact, requiring the final attempt of every key to succeed."""
    latest = {job["key"]: job for job in jobs}
    if expected_keys is not None and set(latest) != set(expected_keys):
        raise ValueError("job keys differ from the required completed work")
    failed = [key for key, job in latest.items() if job["exit_code"] != 0]
    if failed:
        raise ValueError("latest job attempts failed: " + ", ".join(failed))
    return latest


def validate_read_commands(jobs, root):
    """Attest that every attempt used an allowed reader-only command."""
    directory = Path(root).resolve() / "benchmarks/reader-refresh"
    for job in jobs:
        command = job["command"]
        if Path(command[0]).name != "Rscript" or command[1] != "--vanilla":
            raise ValueError("unexpected reader command")
        script = Path(command[2]).resolve()
        valid = False
        if script == directory / "workers/corpus.R":
            valid = len(command) == 5 and command[3] == "dtatools"
        elif script == directory / "workers/arrow.R":
            valid = ((len(command) == 6 and command[3] == "read-dta") or
                     (len(command) == 7 and command[3] == "read-arrow" and
                      command[6] in ("verify", "noverify")))
        elif script == directory / "compare.R":
            valid = len(command) == 5
        elif script == directory / "workers/projection.R":
            valid = len(command) == 8
        if not valid:
            raise ValueError("unexpected reader worker or arguments")


def parse_warm_output(text, planned, actual_order):
    """Validate one worker's clocks and dimensions, retaining execution order."""
    count, expected_rows, expected_columns = WARM_CASES[planned["case"]]
    clocks, cpu = {}, {}
    for line in text.splitlines():
        fields = line.split("\t")
        if fields[0] not in ("iteration", "cpu"):
            continue
        if len(fields) != (5 if fields[0] == "iteration" else 4):
            raise ValueError("malformed warm-read marker")
        try:
            iteration = int(fields[1])
            values = tuple(float(value) for value in fields[2:])
        except ValueError as error:
            raise ValueError("malformed warm-read number") from error
        if not 1 <= iteration <= count or not all(math.isfinite(v) and v >= 0 for v in values):
            raise ValueError("invalid warm-read clocks or iteration")
        target = clocks if fields[0] == "iteration" else cpu
        if iteration in target:
            raise ValueError("duplicate warm-read iteration")
        target[iteration] = values
    expected = set(range(1, count + 1))
    if set(clocks) != expected or set(cpu) != expected:
        raise ValueError("missing warm-read iterations or CPU clocks")
    observations = []
    for iteration in range(1, count + 1):
        elapsed, rows, columns = clocks[iteration]
        if (rows, columns) != (expected_rows, expected_columns):
            raise ValueError("warm-read dimensions differ")
        user, system = cpu[iteration]
        if not math.isfinite(user + system):
            raise ValueError("invalid warm-read total CPU clock")
        observations.append(dict(case=planned["case"], method=planned["method"],
            cohort=planned["cohort"], case_position=planned["case_position"],
            method_position=planned["method_position"],
            scheduled_position=planned["scheduled_position"], execution_position=actual_order,
            iteration=iteration, elapsed_seconds=elapsed, rows=int(rows), columns=int(columns),
            user_cpu_seconds=user, system_cpu_seconds=system, cpu_seconds=user + system))
    return observations


def collect_warm_observations(directory, binding, jobs):
    """Read the complete balanced cohort from its actual, successful attempts."""
    schedule = binding.get("warm_schedule")
    if schedule != warm_read_schedule():
        raise ValueError("missing or altered balanced warm-read schedule")
    planned = {row["key"]: row for row in schedule}
    latest = latest_job_attempts(jobs)
    actual = {}
    execution_position = 0
    qualifications = {"compare-" + case for case in WARM_CASES}
    qualified = set()
    for job in jobs:
        if job["key"] in qualifications:
            if job["exit_code"] == 0:
                qualified.add(job["key"])
            else:
                qualified.discard(job["key"])
        if job["key"] not in planned:
            if "warm" in job:
                raise ValueError("unexpected warm job metadata")
            continue
        if qualified != qualifications:
            raise ValueError("warm reads started before all equality qualifications succeeded")
        row = planned[job["key"]]
        command = job["command"]
        expected_mode = "read-dta" if row["method"] == "read_dta" else "read-arrow"
        expected_size = 6 if expected_mode == "read-dta" else 7
        if (len(command) != expected_size or command[3] != expected_mode or
                command[5] != str(row["iterations"]) or
                (expected_mode == "read-arrow" and command[6] !=
                 ("verify" if row["method"] == "read_arrow_verify" else "noverify"))):
            raise ValueError("warm command differs from its planned method or iteration count")
        execution_position += 1
        expected = dict(planned[job["key"]], execution_position=execution_position)
        if job.get("warm") != expected:
            raise ValueError("warm job order or configuration differs from its recorded plan")
        actual[job["key"]] = execution_position
    if set(actual) != set(planned):
        raise ValueError("balanced warm cohort is incomplete")
    positions = [actual[row["key"]] for row in schedule]
    if positions != sorted(positions):
        raise ValueError("latest warm attempts do not follow the complete cohort schedule")
    observations = []
    for row in schedule:
        job = latest[row["key"]]
        # Immutable attempt logs prevent a later attempt from rewriting history.
        filename = job.get("log_file", row["key"] + ".log")
        path = Path(directory) / filename
        if "log_sha256" in job and sha(path) != job["log_sha256"]:
            raise ValueError("warm attempt log changed")
        observations.extend(parse_warm_output(path.read_text(), row, actual[row["key"]]))
    return observations


def sha(path):
    """Hash an artifact without loading a large input into memory."""
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def tree_sha(directory):
    """Bind every installed package file and reject symbolic-link files."""
    directory = Path(directory)
    require(directory.is_dir() and not directory.is_symlink(), f"invalid package directory: {directory}")
    files = sorted(p for p in directory.rglob("*") if p.is_file())
    require(files and not any(p.is_symlink() for p in files), "empty package or symbolic-link file")
    return {str(p.relative_to(directory)): sha(p) for p in files}


def add_binding_arguments(parser):
    """Add the shared source, retained-data and installation-record arguments."""
    parser.add_argument("--source-root", type=Path, help="checkout used for the installed package")
    parser.add_argument("--data-root", type=Path, required=True,
                        help="original repository's target directory containing retained artifacts")
    parser.add_argument("--build-record", type=Path, required=True,
                        help="JSON linking source_commit, package_tree, and installed file SHA-256 hashes")


def child_environment(library):
    """Select the isolated library and remove experimental reader overrides."""
    environment = {k: v for k, v in os.environ.items()
                   if not k.startswith(("DTATOOLS_EXPERIMENT_", "DTA_READ_PERF_"))}
    environment.update(DTATOOLS_BENCH_LIB=str(Path(library).resolve()),
                       R_ENVIRON_USER="/dev/null", R_PROFILE_USER="/dev/null")
    return environment


def source_binding(source_root, library, build_record, scripts):
    """Link clean tracked source, installed package contents and measured workers."""
    source_root, library, build_record = map(Path, (source_root, library, build_record))
    subprocess.run(["git", "diff", "--exit-code", "HEAD", "--", "r-package/dtatools"],
                   cwd=source_root, check=True)
    untracked = subprocess.check_output(
        ["git", "ls-files", "--others", "--exclude-standard", "r-package/dtatools"],
        cwd=source_root, text=True)
    require(not untracked.strip(), "untracked package source")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source_root, text=True).strip()
    package_tree = subprocess.check_output(["git", "rev-parse", "HEAD:r-package/dtatools"],
                                           cwd=source_root, text=True).strip()
    record = json.loads(build_record.read_text())
    require(record["package_tree"] == package_tree, "build package tree differs")
    require(subprocess.check_output(
        ["git", "rev-parse", record["source_commit"] + ":r-package/dtatools"],
        cwd=source_root, text=True).strip() == package_tree, "build source commit package tree differs")
    installed = tree_sha(library / "dtatools")
    require(record["installed"] == installed, "build record must match the complete installed package")
    rscript = shutil.which("Rscript")
    require(rscript, "Rscript was not found")
    rscript = Path(rscript).resolve()
    return dict(commit=commit, source_tree=package_tree, library=str(library.resolve()),
                build_source_commit=record["source_commit"], build_record_sha256=sha(build_record),
                installed=installed, rscript_sha256=sha(rscript),
                experimental_environment="DTATOOLS_EXPERIMENT_* removed in every child",
                scripts={str(Path(p).resolve()): sha(p) for p in scripts})


def run_child(output, key, script, arguments, environment, cwd=None, warm=None):
    """Record one isolated reader attempt without overwriting its historical log."""
    output = Path(output)
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", key):
        raise ValueError("invalid child key")
    previous_attempts = [int(match.group(1)) for path in output.glob(key + ".attempt-*.log")
                         if (match := re.fullmatch(re.escape(key) + r"\.attempt-([0-9]{4,})\.log", path.name))]
    attempt = max(previous_attempts, default=0) + 1
    log = output / f"{key}.attempt-{attempt:04d}.log"
    rscript = shutil.which("Rscript")
    require(rscript, "Rscript was not found")
    command = [rscript, "--vanilla", str(script), *map(str, arguments)]
    started = time.time()
    with log.open("wb") as stream:
        actions = [(os.POSIX_SPAWN_DUP2, stream.fileno(), 1),
                   (os.POSIX_SPAWN_DUP2, stream.fileno(), 2)]
        previous = Path.cwd()
        try:
            if cwd is not None:
                os.chdir(cwd)
            pid = os.posix_spawn(rscript, command, environment, file_actions=actions)
        finally:
            os.chdir(previous)
        _, status, usage = os.wait4(pid, 0)
    result = dict(key=key, command=command, exit_code=os.waitstatus_to_exitcode(status),
                  peak_rss_bytes=usage.ru_maxrss * (1 if sys.platform == "darwin" else 1024),
                  process_user_cpu_seconds=usage.ru_utime,
                  process_system_cpu_seconds=usage.ru_stime,
                  start=started, duration=time.time() - started,
                  attempt=attempt, log_file=log.name, log_sha256=sha(log))
    if warm is not None:
        result["warm"] = dict(warm)
    with (output / "jobs.jsonl").open("a") as stream:
        stream.write(json.dumps(result) + "\n")
    # Preserve the existing latest-log filename for other driver consumers.
    shutil.copyfile(log, output / (key + ".log"))
    if result["exit_code"]:
        raise RuntimeError(f"{key} failed; inspect {log}")
    return result, log.read_text()


def read_cpu(text):
    """Parse the single read-call CPU marker independently of process CPU."""
    rows = [line.split("\t")[1:] for line in text.splitlines()
            if line.startswith("DTATOOLS_CPU\t")]
    require(len(rows) == 1 and len(rows[0]) == 2, "missing or duplicate read CPU marker")
    try:
        user, system = map(float, rows[0])
    except ValueError as error:
        raise RuntimeError("nonnumeric read CPU marker") from error
    require(all(math.isfinite(value) and value >= 0 for value in (user, system, user + system)),
            "invalid read CPU marker")
    return dict(user_cpu_seconds=user, system_cpu_seconds=system, cpu_seconds=user + system)
