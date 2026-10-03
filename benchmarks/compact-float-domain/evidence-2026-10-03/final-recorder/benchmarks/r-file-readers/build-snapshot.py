#!/usr/bin/env python3
"""Build a fresh, source-bound acceptance library without touching the checkout.

Baseline uses exactly --base-commit. Candidate additionally requires --source,
the working package directory, whose file set must exactly match the Git base.
--work must be a new private directory. No historical installation is reused.
"""

import argparse
from datetime import datetime, timezone
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("reader_build_records", HERE / "record-builds.py")
RECORDS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RECORDS)
require = RECORDS.require

# Do not copy credentials or unrelated application environment. Private records
# retain every key/value actually passed to the compiler.
ENVIRONMENT_KEYS = {
    "PATH", "HOME", "TMPDIR", "TMP", "TEMP", "LANG", "TZ", "USER", "LOGNAME",
    "R_LIBS", "R_LIBS_USER", "R_LIBS_SITE", "R_MAKEVARS_USER", "R_MAKEVARS_SITE",
    "MAKE", "MAKEFLAGS", "MFLAGS", "CC", "CXX", "FC", "F77", "AR", "RANLIB",
    "CFLAGS", "CPPFLAGS", "CXXFLAGS", "FFLAGS", "FCFLAGS", "LDFLAGS", "LIBS",
    "SDKROOT", "MACOSX_DEPLOYMENT_TARGET", "PKG_CONFIG_PATH", "PKG_CONFIG_LIBDIR",
    "LD_LIBRARY_PATH", "DYLD_LIBRARY_PATH", "DYLD_FALLBACK_LIBRARY_PATH",
    "CARGO_HOME", "RUSTUP_HOME", "RUSTUP_TOOLCHAIN", "RUSTFLAGS", "RUSTC",
    "RUSTC_WRAPPER", "RUSTC_WORKSPACE_WRAPPER", "CARGO_ENCODED_RUSTFLAGS",
    "CARGO_BUILD_TARGET", "CARGO_BUILD_JOBS", "CARGO_NET_OFFLINE",
}


def now():
    return datetime.now(timezone.utc).isoformat()


def sanitize(value):
    if RECORDS.PRIVATE_TEXT.search(value):
        return {"value": "<private>", "sha256": RECORDS.sha_bytes(value.encode())}
    return {"value": value, "sha256": RECORDS.sha_bytes(value.encode())}


def executable(name, env):
    found = shutil.which(name, path=env.get("PATH"))
    require(found is not None, "A required build executable is unavailable")
    # rustup dispatches by argv[0]; resolving the rustc/cargo symlink would
    # execute "rustup --version" instead of the selected compiler's version.
    return os.path.abspath(found)


def toolchain(r, env):
    result = {}
    for name, args in (("R", [r, "--version"]), ("rustc", [executable("rustc", env), "--version"]),
                       ("cargo", [executable("cargo", env), "--version"]),
                       ("clang", [executable("clang", env), "--version"])):
        output = subprocess.check_output(args, env=env, text=True, stderr=subprocess.STDOUT).strip()
        result[name] = {"version": sanitize(output), "launcher_sha256": RECORDS.sha_file(Path(args[0]))}
    r_home = Path(subprocess.check_output([r, "RHOME"], env=env, text=True).strip())
    result["R_runtime_sha256"] = RECORDS.sha_file(r_home / "bin/exec/R")
    configs = {}
    for name in ("Makeconf", "Renviron", "Makevars.site", "Renviron.site", "Rprofile.site"):
        path = r_home / "etc" / name
        if path.is_file():
            configs["R_etc_" + name] = RECORDS.sha_file(path)
    home = Path(env.get("HOME", ""))
    for key, fallback in (("R_MAKEVARS_USER", home / ".R/Makevars"),
                          ("R_MAKEVARS_SITE", r_home / "etc/Makevars.site")):
        path = Path(env[key]) if key in env else fallback
        if path.is_file():
            configs[key] = RECORDS.sha_file(path)
    cargo_home = Path(env.get("CARGO_HOME", str(home / ".cargo")))
    for name in ("config", "config.toml"):
        path = cargo_home / name
        if path.is_file():
            configs["cargo_home_" + name] = RECORDS.sha_file(path)
    result["external_config_sha256"] = configs
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", choices=("baseline", "candidate"), required=True)
    parser.add_argument("--base-commit", required=True)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--r", default="R")
    args = parser.parse_args()
    require((args.variant == "candidate") == (args.source is not None),
            "Only candidate builds require --source")
    commit, base, modes = RECORDS.base_source(args.base_commit)
    if args.source is None:
        files = base
    else:
        source = args.source.resolve(strict=True)
        observed = RECORDS.source_inventory(source, base)
        require(RECORDS.source_modes(source, base) == modes, "Working-source modes differ from Git base")
        files = {name: (source / name).read_bytes() for name in base}
        require(observed == {name: RECORDS.sha_bytes(data) for name, data in files.items()},
                "Working sources changed while being captured")
    expected = {name: RECORDS.sha_bytes(data) for name, data in files.items()}
    patch = RECORDS.HELPERS.text_patch(base, files)
    RECORDS.replay_patch(base, modes, patch, expected)
    work = args.work.resolve()
    if args.source:
        require(work != source and work not in source.parents and source not in work.parents,
                "Build output must be disjoint from working sources")
    work.mkdir(parents=True, exist_ok=False, mode=0o700)
    RECORDS.materialize(work / "source", files, modes)
    RECORDS.materialize(work / "build", files, modes)
    (work / "library").mkdir()
    (work / "source.patch").write_text(patch)
    env = {key: value for key, value in os.environ.items()
           if key in ENVIRONMENT_KEYS or key.startswith("LC_")}
    env.update(R_ENVIRON_USER="/dev/null", R_PROFILE_USER="/dev/null")
    r = executable(args.r, env)
    command = [r, "CMD", "INSTALL", "--preclean", "--install-tests",
               "--library=" + str(work / "library"), str(work / "build")]
    tools_before = toolchain(r, env)
    private = {"command": command, "environment": env, "cwd": str(work),
               "source_origin": str(args.source.resolve()) if args.source else commit,
               "toolchain": tools_before}
    private_raw = RECORDS.json_bytes(private)
    (work / "input-record-private.json").write_bytes(private_raw)
    inputs = {"schema_version": 1, "variant": args.variant, "base_commit": commit,
              "created_utc": now(), "source_inventory": expected, "source_modes": modes,
              "source_patch_sha256": RECORDS.sha_bytes(patch.encode()),
              "artifact_sha256": RECORDS.artifact_hashes(),
              "private_record_sha256": RECORDS.sha_bytes(private_raw),
              "build_command": ["<R>", "CMD", "INSTALL", "--preclean", "--install-tests",
                                "--library=<library>", "<build-source>"],
              "environment": {key: ({"value": "<private>", "sha256": RECORDS.sha_bytes(value.encode())}
                                     if key in ("USER", "LOGNAME") else sanitize(value))
                              for key, value in sorted(env.items())},
              "toolchain": tools_before}
    public_raw = RECORDS.public_bytes(inputs)
    (work / "input-record.json").write_bytes(public_raw)
    for directory in (work / "source", work / "build"):
        require(RECORDS.source_inventory(directory, base) == expected, "Source changed before build")
        require(RECORDS.source_modes(directory, base) == modes, "Source modes changed before build")
    started = now()
    with (work / "build.log").open("wb") as log:
        process = subprocess.run(command, cwd=work, env=env, stdout=log, stderr=subprocess.STDOUT)
    finished = now()
    require(process.returncode == 0, "R CMD INSTALL failed; inspect the private build.log")
    for directory, generated in ((work / "source", False), (work / "build", True)):
        require(RECORDS.source_inventory(directory, base, generated) == expected, "Source changed during build")
        require(RECORDS.source_modes(directory, base) == modes, "Source modes changed during build")
    require(tools_before == toolchain(r, env), "Build toolchain/configuration changed")
    require(inputs["artifact_sha256"] == RECORDS.artifact_hashes(), "Build recorder changed during installation")
    installed = RECORDS.HELPERS.installed_inventory(work / "library")
    require(RECORDS.sha_file(work / "build/src/dtatools.so") == installed["libs/dtatools.so"],
            "Installed and source-build native libraries differ")
    receipt = {"schema_version": 1, "variant": args.variant, "base_commit": commit,
               "started_utc": started, "finished_utc": finished, "exit_code": process.returncode,
               "pre_post_source_equal": True, "source_inventory": expected, "source_modes": modes,
               "source_patch_sha256": inputs["source_patch_sha256"],
               "artifact_sha256": inputs["artifact_sha256"],
               "input_record_sha256": RECORDS.sha_bytes(public_raw),
               "build_log_sha256": RECORDS.sha_file(work / "build.log"),
               "installed_inventory": installed, "build_command": inputs["build_command"],
               "environment": inputs["environment"], "toolchain": tools_before}
    (work / "build-receipt.json").write_bytes(RECORDS.public_bytes(receipt))
    print("Built and verified " + args.variant + "; private work directory contains the library and receipt")


if __name__ == "__main__":
    main()
