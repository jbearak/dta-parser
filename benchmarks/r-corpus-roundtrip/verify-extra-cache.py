"""Run the canonical live-Stata oracle on ENADID, WFS and CFR, without Haven tests.

This supplements, and never replaces, verify.R's unchanged 1,823-file full gate.
It stages the canonical verifier and comparator, changing only the corpus list
and exact expected counts. A run must pass all 59 supplementary files with no
exclusions. The same public-default DTA/Arrow round trips are retained.

Use --prepare-only to inspect the staged patch and records without starting R
or Stata. Actual execution requires a fresh --work directory. Private command,
logs and inventory stay there; adapter.patch and adapter-record.json contain no
private paths and may accompany sanitized verification evidence.
"""
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FILES = (
    "benchmarks/benchmark-common.R",
    "benchmarks/r-corpus-roundtrip/common.R",
    "benchmarks/r-corpus-roundtrip/verify.R",
    "benchmarks/r-corpus-roundtrip/verify-worker.R",
    "benchmarks/r-corpus-roundtrip/stata-compare.do",
)
COUNTS = {"ENADID": 17, "WFS": 41, "CFR": 1}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    hashed = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            hashed.update(block)
    return hashed.hexdigest()


def package_inventory(library):
    package = library / "dtatools"
    result = {}
    for path in sorted(package.rglob("*")):
        if path.is_symlink():
            raise ValueError("Installed package contains a symlink")
        if path.is_file():
            result[str(path.relative_to(package))] = file_digest(path)
    if "DESCRIPTION" not in result:
        raise ValueError("Installed package is incomplete")
    return result


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError("Canonical verifier changed; review the adapter before running")
    return text.replace(old, new, 1)


def adapt_common(text):
    return replace_once(text,
        'roundtrip_corpora <- c("DHS", "MICS", "NSFG")',
        'roundtrip_corpora <- c("ENADID", "WFS", "CFR")')


def adapt_verifier(text):
    text = replace_once(text,
        'selected <- roundtrip_select_verification(inventory, selection, argument)',
        '''if (!identical(selection, "full")) stop("supplement requires full verification")
extra_counts <- as.integer(table(factor(
    inventory$corpus, levels = c("ENADID", "WFS", "CFR")
)))
if (!identical(extra_counts, c(17L, 41L, 1L)) ||
    nrow(inventory) != 59L || anyNA(inventory$release) ||
    any(inventory$release != 118L)) {
    stop("supplement requires exactly 17 ENADID, 41 WFS and 1 CFR release-118 files")
}
selected <- roundtrip_select_verification(inventory, selection, argument)''')
    text = replace_once(text,
        '''!(nrow(results) == 1823L && sum(results$status == "pass") == 1821L &&
      sum(results$status == "expected-exclusion") == 2L)''',
        '''!(nrow(results) == 59L && sum(results$status == "pass") == 59L &&
      sum(results$status == "expected-exclusion") == 0L)''')
    return replace_once(text,
        'stop("full verification did not achieve 1,821 passes and two bound exclusions")',
        'stop("supplement did not achieve all 59 passes with zero exclusions")')


def stage_sources(source_root, work):
    """Copy exact source bytes, retaining their directory relationships."""
    before, after, patch = {}, {}, []
    for relative in FILES:
        source = source_root / relative
        if source.is_symlink() or not source.is_file():
            raise ValueError("Canonical source must be an ordinary file: " + relative)
        original = source.read_bytes()
        adapted = original
        if relative.endswith("/r-corpus-roundtrip/common.R"):
            adapted = adapt_common(original.decode("utf-8")).encode("utf-8")
        elif relative.endswith("/r-corpus-roundtrip/verify.R"):
            adapted = adapt_verifier(original.decode("utf-8")).encode("utf-8")
        target = work / "harness" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(adapted)
        before[relative], after[relative] = digest(original), digest(adapted)
        if adapted != original:
            patch.extend(difflib.unified_diff(
                original.decode("utf-8").splitlines(keepends=True),
                adapted.decode("utf-8").splitlines(keepends=True),
                fromfile="a/" + relative, tofile="b/" + relative))
    return before, after, "".join(patch)


def verify_staged(work, expected):
    for relative, expected_hash in expected.items():
        path = work / "harness" / relative
        if path.is_symlink() or not path.is_file() or digest(path.read_bytes()) != expected_hash:
            raise ValueError("Staged oracle source changed: " + relative)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=lambda value: Path(value).resolve(), required=True)
    parser.add_argument("--work", type=lambda value: Path(value).resolve(), required=True)
    parser.add_argument("--build-records", type=lambda value: Path(value).resolve(), required=True,
        help="Successful source-bound build record whose candidate inventory matches --library")
    parser.add_argument("--cache", type=lambda value: Path(value).resolve(), default=Path("/opt/aww_cache"))
    parser.add_argument("--stata", type=lambda value: Path(value).resolve(),
        default=Path("/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp"))
    parser.add_argument("--jobs", type=int, default=16)
    parser.add_argument("--memory-gib", type=float, default=96)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    if args.jobs < 1 or not 0 < args.memory_gib < float("inf"):
        parser.error("Use positive jobs and finite memory limits")
    if any(os.environ.get(key) for key in ("CI", "GITHUB_ACTIONS", "GITHUB_RUN_ID", "GITHUB_WORKFLOW")):
        parser.error("Private corpus verification refuses CI")
    if not args.stata.is_file() or not os.access(args.stata, os.X_OK):
        parser.error("Stata executable is missing or not executable")
    if not all((args.cache / name).is_dir() for name in COUNTS):
        parser.error("Cache must contain ENADID, WFS and CFR directories")
    rscript = shutil.which("Rscript")
    if rscript is None:
        parser.error("Rscript is unavailable")
    if not args.prepare_only and not (args.library / "dtatools/DESCRIPTION").is_file():
        parser.error("Use an installed, source-bound dtatools library")
    if not args.build_records.is_file():
        parser.error("Build record is missing")
    os.umask(0o077)
    args.work.mkdir(parents=True, exist_ok=False, mode=0o700)
    before, after, patch = stage_sources(ROOT, args.work)
    patch_path = args.work / "adapter.patch"
    patch_path.write_text(patch)
    command = [rscript, "--vanilla",
        str(args.work / "harness/benchmarks/r-corpus-roundtrip/verify.R"),
        str(args.cache), str(args.work / "results"), "full"]
    overrides = dict(DTATOOLS_BENCH_LIB=str(args.library), STATA_BIN=str(args.stata),
        R_ENVIRON_USER="/dev/null", R_PROFILE_USER="/dev/null",
        DTATOOLS_VERIFY_JOBS=str(args.jobs), DTATOOLS_VERIFY_MEMORY_GIB=str(args.memory_gib))
    private = args.work / "command.private.json"
    private.write_text(json.dumps(dict(command=command, environment_overrides=overrides), indent=2) + "\n")
    record = dict(schema_version=1,
        scope="Supplement only; unchanged canonical full gate remains required separately",
        expected_files=COUNTS, expected_passes=59, expected_exclusions=0,
        supported_source_releases=[118],
        output_container="public default: dibble; Arrow restores saved container",
        haven="No Haven reader or test invocation; shared runtime binding fingerprints installed package",
        canonical_source_sha256=before, staged_source_sha256=after,
        adapter_runner_sha256=digest(Path(__file__).read_bytes()),
        adapter_patch_sha256=digest(patch_path.read_bytes()),
        build_record_sha256=file_digest(args.build_records),
        private_command_sha256=digest(private.read_bytes()),
        command=["<Rscript>", "--vanilla", "<staged verify.R>", "<cache root>", "<results directory>", "full"],
        jobs=args.jobs, memory_gib=args.memory_gib,
        prepared_only=args.prepare_only)
    record_path = args.work / "adapter-record.json"
    record_path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    verify_staged(args.work, after)
    if args.prepare_only:
        print("Prepared the exact 59-file supplement; no R or Stata process started.")
        return
    env = os.environ.copy()
    env.update(overrides)
    r_bin = Path(subprocess.check_output(
        [rscript, "--vanilla", "-e", 'cat(R.home("bin"))'], env=env, text=True))

    def bindings():
        executables = {"Rscript": Path(rscript), "Stata": args.stata, "R": r_bin / "R"}
        if (r_bin / "exec/R").is_file():
            executables["R_native"] = r_bin / "exec/R"
        return dict(installed_inventory=package_inventory(args.library),
            canonical_source_sha256={name: file_digest(ROOT / name) for name in FILES},
            executable_sha256={name: file_digest(path) for name, path in executables.items()},
            adapter_runner_sha256=file_digest(Path(__file__)),
            build_record_sha256=file_digest(args.build_records))

    binding_before = bindings()
    build_record = json.loads(args.build_records.read_text())
    if build_record.get("libraries", {}).get("candidate") != binding_before["installed_inventory"]:
        raise ValueError("Installed candidate does not match source-bound build record")
    (args.work / "bindings-before.json").write_text(json.dumps(binding_before, indent=2) + "\n")
    with (args.work / "verification.log").open("w") as log:
        completed = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT)
    verify_staged(args.work, after)
    audit = args.work / "audit-inputs.R"
    audit.write_text('''args <- commandArgs(TRUE)
script_dir <- args[[1L]]
source(file.path(script_dir, "common.R"), local = TRUE)
inventory <- roundtrip_cached_inventory(args[[2L]], args[[3L]])
stopifnot(nrow(inventory) == 59L)
cat("POST_INPUT_REHASH_PASS\\n")
''')
    with (args.work / "post-input-audit.log").open("w") as log:
        audit_result = subprocess.run([rscript, "--vanilla", str(audit),
            str(args.work / "harness/benchmarks/r-corpus-roundtrip"),
            str(args.cache), str(args.work / "results/inventory.tsv")],
            env=env, stdout=log, stderr=subprocess.STDOUT)
    binding_after = bindings()
    (args.work / "bindings-after.json").write_text(json.dumps(binding_after, indent=2) + "\n")
    record.update(exit_code=completed.returncode,
        input_rehash_exit_code=audit_result.returncode,
        pre_post_bindings_equal=binding_before == binding_after,
        input_audit_source_sha256=file_digest(audit),
        input_audit_log_sha256=file_digest(args.work / "post-input-audit.log"),
        verification_log_sha256=digest((args.work / "verification.log").read_bytes()))
    for name in ("verification.tsv", "verification-binding.tsv"):
        path = args.work / "results" / name
        if path.is_file():
            record[name.replace(".", "_") + "_sha256"] = digest(path.read_bytes())
    record_path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    if completed.returncode or audit_result.returncode or binding_before != binding_after:
        raise SystemExit(completed.returncode or audit_result.returncode or 1)
    print("Supplement complete: 59 passes, zero exclusions; canonical full gate remains separate.")


if __name__ == "__main__":
    main()
