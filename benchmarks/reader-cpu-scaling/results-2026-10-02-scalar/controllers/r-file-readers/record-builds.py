#!/usr/bin/env python3
"""Verify acceptance build receipts and publish source/library bindings.

Usage: record-builds.py PRIVATE_CONFIG.json NEW_PUBLIC_DIRECTORY
The configuration is {"baseline": "<build-work>", "candidate": "..."}.
Both directories must come from build-snapshot.py. Historical, post-hoc
source/binary associations are not accepted as acceptance build receipts.
"""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
HELPER_PATH = HERE.parent / "io-optimization" / "record-builds.py"
SPEC = importlib.util.spec_from_file_location("io_build_records", HELPER_PATH)
HELPERS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPERS)
PACKAGE = HELPERS.PACKAGE
require = HELPERS.require
sha_file = HELPERS.sha_file
sha_bytes = HELPERS.sha_bytes
PRIVATE_TEXT = re.compile(
    r"/(?:Users|private|home|tmp|var/folders)/|[A-Za-z]:[\\/](?:Users|Temp)[\\/]"
)


def json_bytes(value):
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode()


def public_bytes(value):
    data = json_bytes(value)
    require(not PRIVATE_TEXT.search(data.decode()), "Public record contains a private path")
    return data


def ordinary_files(directory):
    require(directory.is_dir() and not directory.is_symlink(), "Source directory is missing or symlinked")
    files = {}
    for parent, directories, names in os.walk(directory, followlinks=False):
        for name in directories:
            require(not (Path(parent) / name).is_symlink(), "Source tree contains a symlink")
        for name in names:
            path = Path(parent) / name
            require(stat.S_ISREG(path.lstat().st_mode), "Source tree contains a nonordinary file")
            relative = HELPERS.relative_name(path.relative_to(directory).as_posix())
            files[relative] = path
    return files


def generated_file(name):
    if name.startswith(("src/rust/target/", "src/rust/v/")):
        return True
    if name in ("src/Makevars", "src/Makevars.win", "src/symbols.rds"):
        return True
    path = Path(name)
    return path.parent.as_posix() == "src" and path.suffix in (".o", ".so", ".dll", ".dylib")


def source_inventory(directory, expected, allow_generated=False):
    files = ordinary_files(directory)
    require(set(expected) <= set(files), "Source tree is missing a recorded file")
    extra = set(files) - set(expected)
    if allow_generated:
        require(all(generated_file(name) for name in extra), "Build created an unexpected package input")
    else:
        require(not extra, "Source tree contains an unrecorded file")
    return {name: sha_file(files[name]) for name in sorted(expected)}


def base_source(revision):
    commit, files = HELPERS.base_files(ROOT, revision)
    modes = {}
    for entry in HELPERS.git(ROOT, "ls-tree", "-rz", commit, "--", PACKAGE).split(b"\0"):
        if entry:
            metadata, name = entry.split(b"\t", 1)
            modes[name.decode().removeprefix(PACKAGE + "/")] = int(metadata.split()[0], 8) & 0o777
    require(set(files) == set(modes), "Base mode inventory differs from source inventory")
    return commit, files, modes


def materialize(directory, files, modes):
    directory.mkdir(parents=True, exist_ok=False)
    for name, data in files.items():
        path = directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        path.chmod(modes[name])


def replay_patch(base, modes, patch, expected):
    # The previous recorder rejects binary changes and missing final newlines.
    # Replay verifies that the actual emitted artifact reproduces the snapshot.
    require(not PRIVATE_TEXT.search(patch), "Source patch contains a private path")
    with tempfile.TemporaryDirectory(prefix="reader-patch-replay-") as temporary:
        root = Path(temporary)
        package = root / PACKAGE
        materialize(package, base, modes)
        if patch:
            subprocess.run(["git", "apply", "--check", "--whitespace=nowarn", "-"],
                           cwd=root, input=patch.encode(), check=True, capture_output=True)
            subprocess.run(["git", "apply", "--whitespace=nowarn", "-"],
                           cwd=root, input=patch.encode(), check=True, capture_output=True)
        require(source_inventory(package, base) == expected, "Published patch does not reproduce source")


def source_modes(directory, names):
    return {name: stat.S_IMODE((directory / name).stat().st_mode) for name in sorted(names)}


def artifact_hashes():
    return {"recorder": sha_file(Path(__file__)), "builder": sha_file(HERE / "build-snapshot.py"),
            "existing_recorder_helpers": sha_file(HELPER_PATH)}


def verified_receipt(work, variant):
    require(work.is_dir() and not work.is_symlink(), "Build work directory is missing or symlinked")
    receipt_path = work / "build-receipt.json"
    raw = receipt_path.read_bytes()
    receipt = json.loads(raw)
    require(public_bytes(receipt) == raw, "Build receipt is not canonical public JSON")
    require(receipt.get("schema_version") == 1 and receipt.get("variant") == variant,
            "Build receipt has the wrong schema or variant")
    require(receipt.get("exit_code") == 0 and receipt.get("pre_post_source_equal") is True,
            "Build receipt does not prove a successful unchanged-source build")
    require(receipt["artifact_sha256"] == artifact_hashes(), "Build recorder sources changed")
    input_raw = (work / "input-record.json").read_bytes()
    require(sha_bytes(input_raw) == receipt["input_record_sha256"], "Pre-build public record changed")
    inputs = json.loads(input_raw)
    require(public_bytes(inputs) == input_raw, "Pre-build record is not canonical public JSON")
    require(sha_file(work / "input-record-private.json") == inputs["private_record_sha256"],
            "Private pre-build command/environment record changed")
    require(inputs["artifact_sha256"] == receipt["artifact_sha256"], "Pre-build recorder identity differs")
    require(inputs["variant"] == variant and inputs["base_commit"] == receipt["base_commit"],
            "Pre-build identity differs from receipt")
    require(inputs["source_inventory"] == receipt["source_inventory"], "Pre-build source inventory differs")
    require(inputs["source_modes"] == receipt["source_modes"], "Pre-build source modes differ")
    require(sha_file(work / "build.log") == receipt["build_log_sha256"], "Build log changed")
    commit, base, modes = base_source(receipt["base_commit"])
    require(commit == receipt["base_commit"], "Build base is not a full commit identity")
    expected = receipt["source_inventory"]
    require(set(expected) == set(base), "Build source file set differs from Git base")
    require(receipt["source_modes"] == modes, "Build modes differ from Git base")
    for directory, generated in ((work / "source", False), (work / "build", True)):
        require(source_inventory(directory, base, generated) == expected, "Build source changed after installation")
        require(source_modes(directory, base) == modes, "Build source permissions changed")
    if variant == "baseline":
        require(expected == {name: sha_bytes(data) for name, data in base.items()}, "Baseline contains source overlays")
    patch = (work / "source.patch").read_text()
    require(sha_bytes(patch.encode()) == receipt["source_patch_sha256"] == inputs["source_patch_sha256"],
            "Build patch changed")
    replay_patch(base, modes, patch, expected)
    installed = HELPERS.installed_inventory(work / "library")
    require(installed == receipt["installed_inventory"], "Installed library changed after build")
    require(sha_file(work / "build/src/dtatools.so") == installed["libs/dtatools.so"],
            "Source-build and installed native libraries differ")
    return receipt, patch, sha_bytes(raw)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    config_raw = args.configuration.read_bytes()
    config = json.loads(config_raw)
    require(set(config) == {"baseline", "candidate"}, "Configuration requires baseline/candidate work directories")
    work = {key: Path(value).resolve(strict=True) for key, value in config.items()}
    output = args.output.resolve()
    require(work["baseline"] != work["candidate"], "Build work directories must differ")
    require(all(output != path and output not in path.parents and path not in output.parents
                for path in work.values()), "Public output must be disjoint from private builds")
    before = {variant: verified_receipt(path, variant) for variant, path in work.items()}
    require(before["baseline"][0]["base_commit"] == before["candidate"][0]["base_commit"],
            "Acceptance builds must share one Git base")
    after = {variant: verified_receipt(path, variant) for variant, path in work.items()}
    require(before == after and args.configuration.read_bytes() == config_raw, "Artifacts changed during recording")
    record = {"schema_version": 1, "binding_kind": "successful pre/post verified acceptance builds",
              "base_commit": before["baseline"][0]["base_commit"],
              "artifact_sha256": artifact_hashes(), "private_configuration_sha256": sha_bytes(config_raw),
              "libraries": {variant: value[0]["installed_inventory"] for variant, value in before.items()},
              "builds": {variant: {"receipt": value[0], "receipt_sha256": value[2]} for variant, value in before.items()}}
    encoded = public_bytes(record)
    output.mkdir(parents=True, exist_ok=False)
    for variant, (_, patch, _) in before.items():
        (output / (variant + ".patch")).write_text(patch)
    (output / "build-bindings.json").write_bytes(encoded)
    print("Verified acceptance builds and replayed both source patches")


if __name__ == "__main__":
    main()
