"""Bindings and child accounting shared by the reader-only refresh drivers."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def tree_sha(directory):
    directory = Path(directory)
    assert directory.is_dir() and not directory.is_symlink(), directory
    files = sorted(p for p in directory.rglob("*") if p.is_file())
    assert files and not any(p.is_symlink() for p in files)
    return {str(p.relative_to(directory)): sha(p) for p in files}


def add_binding_arguments(parser):
    parser.add_argument("--source-root", type=Path, help="checkout used for the installed package")
    parser.add_argument("--data-root", type=Path, required=True,
                        help="original repository's target directory containing retained artifacts")
    parser.add_argument("--build-record", type=Path, required=True,
                        help="JSON linking source_commit, package_tree, and installed file SHA-256 hashes")


def child_environment(library):
    environment = {k: v for k, v in os.environ.items()
                   if not k.startswith(("DTATOOLS_EXPERIMENT_", "DTA_READ_PERF_"))}
    environment.update(DTATOOLS_BENCH_LIB=str(Path(library).resolve()),
                       R_ENVIRON_USER="/dev/null", R_PROFILE_USER="/dev/null")
    return environment


def source_binding(source_root, library, build_record, scripts):
    source_root, library, build_record = map(Path, (source_root, library, build_record))
    subprocess.run(["git", "diff", "--exit-code", "HEAD", "--", "r-package/dtatools"],
                   cwd=source_root, check=True)
    untracked = subprocess.check_output(
        ["git", "ls-files", "--others", "--exclude-standard", "r-package/dtatools"],
        cwd=source_root, text=True)
    assert not untracked.strip(), "untracked package source"
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source_root, text=True).strip()
    package_tree = subprocess.check_output(["git", "rev-parse", "HEAD:r-package/dtatools"],
                                           cwd=source_root, text=True).strip()
    record = json.loads(build_record.read_text())
    assert record["package_tree"] == package_tree, "build package tree differs"
    assert subprocess.check_output(
        ["git", "rev-parse", record["source_commit"] + ":r-package/dtatools"],
        cwd=source_root, text=True).strip() == package_tree
    installed = tree_sha(library / "dtatools")
    assert record["installed"] == installed, "build record must match the complete installed package"
    rscript = Path(shutil.which("Rscript")).resolve()
    return dict(commit=commit, source_tree=package_tree, library=str(library.resolve()),
                build_source_commit=record["source_commit"], build_record_sha256=sha(build_record),
                installed=installed, rscript_sha256=sha(rscript),
                experimental_environment="DTATOOLS_EXPERIMENT_* removed in every child",
                scripts={str(Path(p).resolve()): sha(p) for p in scripts})


def run_child(output, key, script, arguments, environment, cwd=None):
    output = Path(output)
    log = output / (key + ".log")
    rscript = shutil.which("Rscript")
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
                  start=started, duration=time.time() - started)
    with (output / "jobs.jsonl").open("a") as stream:
        stream.write(json.dumps(result) + "\n")
    if result["exit_code"]:
        raise RuntimeError(f"{key} failed; inspect {log}")
    return result, log.read_text()


def read_cpu(text):
    rows = [line.split("\t")[1:] for line in text.splitlines()
            if line.startswith("DTATOOLS_CPU\t")]
    assert len(rows) == 1 and len(rows[0]) == 2, "missing or duplicate read CPU marker"
    user, system = map(float, rows[0])
    assert user >= 0 and system >= 0
    return dict(user_cpu_seconds=user, system_cpu_seconds=system, cpu_seconds=user + system)
