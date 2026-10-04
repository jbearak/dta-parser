"""Record frozen source/build bindings without publishing private paths.

Usage: python3 record-builds.py PRIVATE_CONFIG.json NEW_OUTPUT_DIRECTORY
The config names root, base_commit, equivalent_commits, baseline (library and
record), and candidates (id, source package directory, library, build_log and
native_mode: compiled or reused-baseline). No benchmark inputs are read.
"""
import argparse
import difflib
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys

PACKAGE = "r-package/dtatools"
PRIVATE_TEXT = re.compile(r"/(?:Users|private|home)/|/opt/aww_cache/|[A-Za-z]:\\Users\\")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def digest_map(inventory):
    return sha_bytes(json.dumps(inventory, sort_keys=True, separators=(",", ":")).encode())


def relative_name(name):
    path = PurePosixPath(name)
    require(not path.is_absolute() and ".." not in path.parts and str(path) == name,
            "Artifact names must be normalized relative paths")
    return name


def production(name):
    return name.startswith(("R/", "src/")) or name in (
        "configure", "configure.win", "NAMESPACE", "DESCRIPTION")


def git(root, *arguments):
    return subprocess.check_output(["git", *arguments], cwd=root)


def base_files(root, revision):
    commit = git(root, "rev-parse", revision + "^{commit}").decode().strip()
    entries = []
    for entry in git(root, "ls-tree", "-rz", commit, "--", PACKAGE).split(b"\0"):
        if not entry:
            continue
        metadata, name = entry.split(b"\t", 1)
        mode, kind, object_id = metadata.split()
        require(kind == b"blob" and mode in (b"100644", b"100755"),
                "Source tree must contain ordinary files")
        relative = relative_name(name.decode().removeprefix(PACKAGE + "/"))
        entries.append((relative, object_id))
    require(entries, "Base package tree is empty")
    output = subprocess.check_output(["git", "cat-file", "--batch"], cwd=root,
        input=b"".join(object_id + b"\n" for _, object_id in entries))
    offset = 0
    files = {}
    for name, object_id in entries:
        end = output.index(b"\n", offset)
        actual_id, kind, length = output[offset:end].split()
        require(actual_id == object_id and kind == b"blob", "Git object mismatch")
        length = int(length)
        files[name] = output[end + 1:end + 1 + length]
        offset = end + 2 + length
    require(offset == len(output), "Unexpected trailing Git object data")
    return commit, files


def installed_inventory(library):
    package = library / "dtatools"
    require(package.is_dir(), "Installed package directory is missing")
    files = {}
    for path in sorted(package.rglob("*")):
        require(not path.is_symlink(), "Installed inventory cannot contain symlinks")
        if path.is_file():
            files[relative_name(path.relative_to(package).as_posix())] = sha_file(path)
    require("libs/dtatools.so" in files, "Installed package DLL is missing")
    return files


def text_patch(base, actual):
    parts = []
    for name, data in sorted(actual.items()):
        if data == base[name]:
            continue
        require(b"\0" not in data and b"\0" not in base[name],
                "Changed binary sources need a separate reproducible artifact")
        old, new = base[name].decode("utf-8"), data.decode("utf-8")
        # Current candidate text files end in LF. Refuse ambiguous patches.
        require((not old or old.endswith("\n")) and (not new or new.endswith("\n")),
                "Changed source text must end in a newline")
        label = PACKAGE + "/" + name
        parts.extend(difflib.unified_diff(old.splitlines(keepends=True),
            new.splitlines(keepends=True), fromfile="a/" + label, tofile="b/" + label))
    patch = "".join(parts)
    require(not PRIVATE_TEXT.search(patch), "Source patch contains a private absolute path")
    return patch


def source_record(specification, base):
    source = Path(specification["source"]).resolve()
    mode = specification["native_mode"]
    require(mode in ("compiled", "reused-baseline"), "Unknown native binding mode")
    # These are the package-owned compilation directories. Dependency trees
    # and target directories are bound by their tracked archives/lockfiles,
    # not by generated or unpacked build products.
    for directory in ("R", "src", "src/rust/src", "src/dta-tools/src"):
        path = source / directory
        if not path.is_dir():
            continue
        paths = path.iterdir() if directory == "src" else path.rglob("*")
        for file in paths:
            if file.is_file() and file.suffix in (".R", ".c", ".h", ".inc", ".rs"):
                require(file.relative_to(source).as_posix() in base,
                        "Candidate contains an unrecorded package source file")
    actual, missing = {}, []
    for name in base:
        path = source / name
        require(not path.is_symlink(), "Source inventory cannot contain symlinks")
        if path.is_file():
            actual[name] = path.read_bytes()
        else:
            missing.append(name)
    if mode == "compiled":
        require(not missing, "Compiled candidate is missing tracked source files")
    else:
        require(all(name in actual for name in base
                    if name.startswith("R/") or name in ("DESCRIPTION", "NAMESPACE")),
                "R-only candidate is missing an R source or package definition")
        require(all(actual[name] == base[name] for name in actual if name.startswith("src/")),
                "Reused native library cannot claim modified native source")
    hashes = {name: sha_bytes(data) for name, data in actual.items()}
    changed = sorted(name for name, data in actual.items() if data != base[name])
    if "expected_overlays" in specification:
        require(changed == sorted(specification["expected_overlays"]),
                "Candidate overlays differ from the configured source set")
    return dict(files=hashes, file_count=len(hashes), inventory_sha256=digest_map(hashes),
                changed_files=changed, omitted_base_files=sorted(missing)), text_patch(base, actual)


def toolchain():
    # These versions are observed when recording, not inferred historical
    # compiler identities. Build logs are independently hashed below.
    commands = {"rustc": ["rustc", "--version"], "cargo": ["cargo", "--version"],
                "clang": ["clang", "--version"], "R": ["R", "--version"],
                "macos_sdk": ["xcrun", "--show-sdk-version"]}
    result = {}
    for name, command in commands.items():
        if shutil.which(command[0]):
            process = subprocess.run(command, capture_output=True, text=True, check=False)
            if process.returncode == 0 and process.stdout.strip():
                line = process.stdout.strip().splitlines()[0]
                require(not PRIVATE_TEXT.search(line), "Toolchain version contains a private path")
                result[name] = line
    return result


def capture(config, base):
    baseline = config["baseline"]
    prior_path = Path(baseline["record"])
    prior = json.loads(prior_path.read_text(encoding="utf-8"))["libraries"]["candidate"]
    production_hashes = {name: sha_bytes(data) for name, data in base.items() if production(name)}
    require(prior["production_source"] == production_hashes,
            "Retained baseline production sources differ from the base Git tree")
    installed = installed_inventory(Path(baseline["library"]).resolve())
    require(installed == prior["installed_files"],
            "Retained baseline installed files differ from their earlier record")
    if "expected_dll_sha256" in baseline:
        require(installed["libs/dtatools.so"] == baseline["expected_dll_sha256"],
                "Retained baseline DLL differs from the configured identity")
    result = dict(baseline=dict(production_source=production_hashes,
        production_file_count=len(production_hashes), installed_files=installed,
        installed_inventory_sha256=digest_map(installed), retained_record_sha256=sha_file(prior_path),
        retained_install_log_sha256=prior["install_log_sha256"],
        retained_installed_inventory_verified=True, base_git_production_verified=True), candidates={})
    patches = {}
    for candidate in config["candidates"]:
        name = candidate["id"]
        require(re.fullmatch(r"[a-z][a-z0-9-]*", name) is not None,
                "Candidate identifiers must be lowercase alphanumeric labels")
        require(name not in result["candidates"], "Duplicate candidate identifier")
        status = candidate.get("status", "provisional")
        require(status in ("provisional", "retained", "rejected", "superseded"),
                "Unknown candidate decision status")
        source, patch = source_record(candidate, base)
        if "source_commit" in candidate:
            revision, committed = base_files(Path(config["root"]), candidate["source_commit"])
            require(source["files"] == {name: sha_bytes(data) for name, data in committed.items()},
                    "Frozen source differs from its exact Git commit")
            source["verified_commit"] = revision
        current = installed_inventory(Path(candidate["library"]).resolve())
        if candidate["native_mode"] == "compiled":
            source_dll = Path(candidate["source"]) / "src/dtatools.so"
            require(sha_file(source_dll) == current["libs/dtatools.so"],
                    "Installed DLL differs from its frozen source-build DLL")
            native = dict(mode="compiled", source_build_dll_equals_installed=True)
        else:
            require(current["libs/dtatools.so"] == installed["libs/dtatools.so"],
                    "R-only candidate did not reuse the retained baseline DLL")
            source_dll = Path(candidate["source"]) / "inst/libs/dtatools.so"
            require(sha_file(source_dll) == installed["libs/dtatools.so"],
                    "R-only source DLL differs from the retained baseline DLL")
            native = dict(mode="reused-baseline", baseline_dll_identity_verified=True,
                          source_reused_dll_equals_installed=True)
        native["dll_sha256"] = current["libs/dtatools.so"]
        result["candidates"][name] = dict(source=source, installed_files=current,
            status=status, status_reason=candidate.get("status_reason", ""),
            build_recipe=candidate.get("build_recipe", {
                "basis": "not recorded; consult the separately hashed build log"}),
            installed_inventory_sha256=digest_map(current), native=native,
            build_log_sha256=sha_file(Path(candidate["build_log"])),
            patch=dict(file=name + ".patch", sha256=sha_bytes(patch.encode())))
        patches[name + ".patch"] = patch
    return result, patches


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    configuration = args.configuration.resolve()
    output = args.output.resolve()
    recorder = Path(__file__).resolve()
    recorder_hash = sha_file(recorder)
    raw_config = configuration.read_bytes()
    config = json.loads(raw_config)
    root = Path(config["root"]).resolve()
    base_commit, base = base_files(root, config.get("base_commit", "78050a30"))
    require(not output.exists(), "Output directory already exists")
    private_paths = [configuration, Path(config["baseline"]["library"]).resolve()]
    for candidate in config["candidates"]:
        private_paths.extend(Path(candidate[key]).resolve() for key in
                             ("source", "library", "build_log"))
    require(all(output != path and output not in path.parents and path not in output.parents
                for path in private_paths), "Public output and private artifacts must be disjoint")
    equivalents = {}
    for revision in config.get("equivalent_commits", []):
        commit, files = base_files(root, revision)
        require({n: d for n, d in files.items() if production(n)} ==
                {n: d for n, d in base.items() if production(n)},
                "A claimed equivalent commit has different production sources")
        equivalents[commit] = "production sources equal base"
    before, patches = capture(config, base)
    versions = toolchain()
    after, after_patches = capture(config, base)
    require(before == after and patches == after_patches, "Artifacts changed during recording")
    require(configuration.read_bytes() == raw_config, "Configuration changed during recording")
    require(sha_file(recorder) == recorder_hash, "Recorder changed during recording")
    result = dict(schema_version=1, base_commit=base_commit,
        base_tracked_file_count=len(base), equivalent_commits=equivalents,
        inventory_digest_algorithm="SHA256 of sorted-key compact UTF-8 JSON path-to-SHA256 map",
        toolchain_observed_at_recording=versions, recorder_sha256=recorder_hash,
        private_configuration_sha256=sha_bytes(raw_config), pre_post_artifacts_unchanged=True,
        **before)
    encoded = json.dumps(result, sort_keys=True, indent=2) + "\n"
    require(not PRIVATE_TEXT.search(encoded), "Public record contains a private absolute path")
    output.mkdir(parents=True)
    for name, patch in patches.items():
        (output / name).write_bytes(patch.encode("utf-8"))
    (output / "build-bindings.json").write_bytes(encoded.encode("utf-8"))
    print("Recorded", len(patches), "candidate bindings; source and installed files unchanged")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as error:
        # The private CLI can show diagnostics, but never include raw exception
        # paths in the public JSON or patches.
        detail = str(error) if isinstance(error, ValueError) else type(error).__name__
        print("Binding verification failed:", detail, file=sys.stderr)
        sys.exit(1)
