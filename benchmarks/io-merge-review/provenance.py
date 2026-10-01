"""Bind the measured libraries, source files, workers and fixed inputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("configuration", type=Path)
parser.add_argument("phase", choices=("before", "after"))
args = parser.parse_args()
config = json.loads(args.configuration.read_text())
root = Path(config["root"])
directory = Path(config["directory"])
baseline_source = Path(config["baseline_source"])
package = Path("r-package/dtatools")

def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

def git(*words):
    return subprocess.check_output(["git", *words], cwd=root, text=True).strip()

def production(name):
    relative = str(Path(name).relative_to(package))
    return relative.startswith(("R/", "src/")) or relative in ("configure", "configure.win", "NAMESPACE", "DESCRIPTION")

def source_inventory(source, names):
    return {str(Path(name).relative_to(package)): sha(source / name) for name in names if production(name)}

baseline_entries = git("ls-tree", "-r", "v0.10.0", "--", str(package)).splitlines()
baseline_names = []
for entry in baseline_entries:
    metadata, name = entry.split("\t")
    _, kind, expected = metadata.split()
    if kind != "blob" or not production(name):
        continue
    data = (baseline_source / name).read_bytes()
    actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    if actual != expected:
        raise RuntimeError("Archived baseline differs from v0.10.0: " + name)
    baseline_names.append(name)
candidate_names = git("ls-files", "--", str(package)).splitlines()
record = dict(baseline_commit=git("rev-parse", "v0.10.0^{commit}"),
    baseline_package_tree=git("rev-parse", "v0.10.0:r-package/dtatools"),
    baseline_git_blob_verification=True, candidate_head=git("rev-parse", "HEAD"),
    platform=platform.platform(), machine=platform.machine(), logical_cpus=os.cpu_count(),
    libraries={}, inputs={}, harness={})
for variant, source, names, install_log in (
    ("baseline", baseline_source, baseline_names, Path(config["baseline_install_log"])),
    ("candidate", root, candidate_names, Path(config["candidate_install_log"]))):
    installed = Path(config[variant]) / "dtatools"
    source_dll = source / package / "src/dtatools.so"
    installed_dll = installed / "libs/dtatools.so"
    if sha(source_dll) != sha(installed_dll):
        raise RuntimeError(variant + " installed DLL differs from source-build DLL")
    env = os.environ.copy()
    env.update(R_LIBS=config[variant], DTATOOLS_BENCH_LIB=config[variant])
    observed = subprocess.check_output(["Rscript", "--vanilla", "-e",
        'library(dtatools); cat(R.version.string, "\\n"); cat("threads", getOption("dtatools.threads", 0L), "alloccol", getOption("dtatools.alloccol", 1024L), "\\n"); for (p in c("dtatools", "rlang", "vctrs", "tibble", "dplyr", "data.table")) if (requireNamespace(p, quietly=TRUE)) cat(p, as.character(packageVersion(p)), "\\n")'],
        env=env, cwd=root, text=True)
    record["libraries"][variant] = dict(production_source=source_inventory(source, names),
        installed_files={str(path.relative_to(installed)): sha(path) for path in sorted(installed.rglob("*")) if path.is_file()},
        source_build_dll_equals_installed=True, install_log_sha256=sha(install_log), observed=observed)
for fixture in config["reads"]:
    for suffix in ("dta", "arrow"):
        path = Path(fixture[suffix])
        record["inputs"][fixture["id"] + "-" + suffix] = dict(bytes=path.stat().st_size, sha256=sha(path),
            rows=fixture["rows"], columns=fixture["columns"])
for path in sorted(Path(config["merge_directory"]).iterdir()):
    if path.is_file():
        record["inputs"]["merge-" + path.name] = dict(bytes=path.stat().st_size, sha256=sha(path))
for path in sorted(directory.iterdir()):
    if path.suffix in (".R", ".py"):
        record["harness"][path.name] = sha(path)
for name in ("benchmarks/reader-corpus/worker.R", "benchmarks/reader-refresh/workers/benchmark-common.R",
             "benchmarks/large-scale/stata-generate-fixture.do", "benchmarks/large-scale/standard-r-write-fixture.R"):
    record["harness"][name] = sha(root / name)
destination = directory / ("provenance-" + args.phase + ".json")
if args.phase == "after":
    before = json.loads((directory / "provenance-before.json").read_text())
    for key in ("libraries", "inputs", "harness"):
        if before[key] != record[key]:
            raise RuntimeError("Pre/post provenance changed: " + key)
    record["pre_post_unchanged"] = True
destination.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
print("Captured " + args.phase + " provenance", flush=True)
