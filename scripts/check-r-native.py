#!/usr/bin/env python3
"""Install an exact dtatools archive and run its complete native test manifest.

Upload NEW_OUTPUT/evidence only. NEW_OUTPUT/payload contains package code,
source and binary archives, installed libraries, and compiler output.
"""

import argparse
import copy
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import sys
import tarfile
import time
import zipfile


FORBIDDEN = {"dplyr", "labelled", "dtplyr", "tidyr", "haven"}
CAPABILITIES = {"arrow", "profmem", "posix", "mkfifo", "test"}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def identity(path):
    path = Path(path).absolute()
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        require(stat.S_ISREG(os.fstat(stream.fileno()).st_mode), f"Not a regular file: {path}")
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    info = path.stat()
    return dict(path=str(path), resolved=str(path.resolve(strict=True)), bytes=info.st_size,
                mode=stat.S_IMODE(info.st_mode), sha256=digest.hexdigest())


def inventory(root):
    root = Path(root)
    require(root.is_dir() and not root.is_symlink(), f"Invalid inventory root: {root}")
    rows = []
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(directory) / name
            mode = path.lstat().st_mode
            require(not path.is_symlink() and (stat.S_ISDIR(mode) or stat.S_ISREG(mode)),
                    f"Nonregular inventory member: {path}")
            if stat.S_ISREG(mode):
                rows.append({"relative": path.relative_to(root).as_posix(), **identity(path)})
    return sorted(rows, key=lambda row: row["relative"])


def write_json(path, value):
    with Path(path).open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.write("\n")


def error_record(error):
    return {"type": type(error).__name__, "message": str(error)}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def r_literal(value):
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, str):
        require("\0" not in value, "NUL in R configuration")
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (int, float)):
        require(math.isfinite(value), "Non-finite R configuration")
        return repr(value)
    if isinstance(value, list):
        return "list(" + ",".join(map(r_literal, value)) + ")"
    if isinstance(value, dict):
        return "structure(list(" + ",".join(map(r_literal, value.values())) + "),names=c(" + \
            ",".join(map(r_literal, value.keys())) + "))"
    raise TypeError(type(value).__name__)


def effective_manifest(source, capabilities):
    """Apply only source-declared policies selected before any test executes."""
    require(set(capabilities) == CAPABILITIES and all(type(x) is bool for x in capabilities.values()),
            "Incomplete independent capability probe")
    result = copy.deepcopy(source)
    applied = []
    assignments = {}
    for override in source.get("capability_overrides", []):
        require(set(override) <= {"when", "blocks", "children", "forks"}, "Unknown capability override field")
        when = override["when"]
        require(when and set(when) <= CAPABILITIES and all(type(x) is bool for x in when.values()),
                "Invalid declared capability condition")
        if not all(capabilities[name] == value for name, value in when.items()):
            continue
        for kind in ("blocks", "children", "forks"):
            for change in override.get(kind, []):
                candidates = []
                for family in result["families"]:
                    if kind == "blocks":
                        candidates.extend(block for block in family["blocks"]
                            if (block["file"], block["test"], block.get("occurrence", 1)) ==
                               (change["file"], change["test"], change.get("occurrence", 1)))
                    elif family["id"] == change["family"]:
                        owner = family
                        if kind == "forks" and change.get("child") is not None:
                            owners = [child for child in family["children"] if child["id"] == change["child"]]
                            require(len(owners) == 1, "Capability fork owner is ambiguous")
                            owner = owners[0]
                        candidates.extend(item for item in owner.get(kind, []) if item["id"] == change["id"])
                require(len(candidates) == 1, f"Capability override target is missing or ambiguous: {change}")
                fields = ("skip", "reason", "skip_message", "min_pass_before_skip", "warnings") if kind == "blocks" else ("minimum", "maximum")
                selectors = ("file", "test", "occurrence") if kind == "blocks" else ("family", "id", "child")
                require(set(change) <= set(fields) | set(selectors), "Unknown capability target field")
                update = {key: change[key] for key in fields if key in change}
                require(bool(update), "Empty capability override")
                for key, value in update.items():
                    assignment = (id(candidates[0]), key)
                    require(assignment not in assignments or assignments[assignment] == value,
                            "Conflicting capability overrides")
                    assignments[assignment] = value
                candidates[0].update(update)
        applied.append(override)
    return result, applied


PROBE_R = r'''
args <- commandArgs(TRUE)
cfg <- dget(args[[1L]])
output <- args[[2L]]
check <- function(ok, text) if (!isTRUE(ok)) stop(text, call. = FALSE)
path <- function(x) unname(normalizePath(x, winslash = "/", mustWork = TRUE))
chr <- function(x) unname(as.character(unlist(x, use.names = FALSE)))
libraries <- c(chr(cfg$libraries), path(.Library))
observe <- function() {
    actual <- path(.libPaths())
    check(identical(actual, libraries), "Probe startup/terminal libraries differ")
    check(!anyDuplicated(actual), "Probe duplicate libraries")
    check(identical(as.character(getRversion()), cfg$version), "Probe R version differs")
    members <- list()
    for (library in actual) for (candidate in list.dirs(library, recursive = FALSE, full.names = TRUE)) {
        desc <- file.path(candidate, "DESCRIPTION")
        if (!file.exists(desc)) next
        d <- read.dcf(desc)
        check(nrow(d) == 1L && all(c("Package", "Version") %in% colnames(d)), "Invalid probe DESCRIPTION")
        members[[length(members) + 1L]] <- list(name = unname(d[1L, "Package"]),
            version = unname(d[1L, "Version"]), path = path(candidate),
            priority = if ("Priority" %in% colnames(d)) unname(d[1L, "Priority"]) else NULL)
    }
    names_found <- vapply(members, `[[`, "", "name")
    check(!anyDuplicated(names_found) && !any(names_found %in% chr(cfg$forbidden)), "Duplicate or forbidden probe package")
    for (name in names(cfg$expected_packages)) {
        found <- members[names_found == name]
        selected <- cfg$expected_packages[[name]]
        check(length(found) == 1L && identical(found[[1L]]$path, path(selected$path)) &&
            identical(found[[1L]]$version, selected$version), paste("Probe package differs:", name))
    }
    for (member in members[!names_found %in% names(cfg$expected_packages)]) {
        check(identical(dirname(member$path), path(.Library)) &&
            (member$name == "translations" || member$priority %in% c("base", "recommended")),
            paste("Unexpected probe package:", member$name))
    }
    namespaces <- lapply(sort(loadedNamespaces()), function(name) {
        ns <- asNamespace(name)
        location <- if (identical(ns, .BaseNamespaceEnv)) file.path(.Library, "base") else getNamespaceInfo(ns, "path")
        version <- if (identical(ns, .BaseNamespaceEnv)) as.character(getRversion()) else as.character(getNamespaceVersion(ns))
        location <- path(location)
        check(!name %in% chr(cfg$forbidden), "Forbidden probe namespace")
        selected <- cfg$expected_packages[[name]]
        if (is.null(selected)) check(identical(dirname(location), path(.Library)), "Unexpected probe namespace")
        else check(identical(location, path(selected$path)) && identical(version, selected$version), "Probe namespace path/version differs")
        list(name = name, path = location, version = version)
    })
    list(libraries = actual, members = members, namespaces = namespaces,
        dlls = lapply(getLoadedDLLs(), function(x) list(name = x[["name"]], path = x[["path"]])))
}
original <- NULL
terminal <- NULL
tryCatch({
    before <- observe()
    dput(before, paste0(output, ".before.R"))
    loadNamespace("jsonlite", lib.loc = dirname(cfg$expected_packages$jsonlite$path))
    source_dcf <- read.dcf(cfg$source_description)
    check(nrow(source_dcf) == 1L && identical(unname(source_dcf[1L, "Package"]), "dtatools"), "Expected dtatools source")
    source_version <- unname(source_dcf[1L, "Version"])
    package <- NULL
    if (!is.null(cfg$package_path)) {
        installed_dcf <- read.dcf(file.path(cfg$package_path, "DESCRIPTION"))
        check(identical(unname(installed_dcf[1L, "Package"]), "dtatools") &&
            identical(unname(installed_dcf[1L, "Version"]), source_version), "Installed package version differs from source")
        ns <- loadNamespace("dtatools", lib.loc = dirname(cfg$package_path))
        check(identical(path(getNamespaceInfo(ns, "path")), path(cfg$package_path)), "Loaded dtatools path differs")
        dll <- getLoadedDLLs()[["dtatools"]]
        check(!is.null(dll), "Installed dtatools DLL missing")
        package <- list(path = path(cfg$package_path), version = source_version, dll_path = path(dll[["path"]]))
    }
    after <- observe()
    command_paths <- as.list(setNames(unname(Sys.which(c("mkfifo", "test"))), c("mkfifo", "test")))
    result <- list(complete = TRUE, before = before, after = after,
        runtime = list(version = as.character(getRversion()), platform = R.version$platform,
            home = path(R.home()), base_library = path(.Library),
            rscript = path(file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"))),
        capabilities = list(arrow = "arrow" %in% names(cfg$expected_packages),
            profmem = isTRUE(capabilities("profmem")), posix = .Platform$OS.type != "windows",
            mkfifo = nzchar(command_paths$mkfifo), test = nzchar(command_paths$test)),
        command_paths = command_paths, source_version = source_version, package = package)
    jsonlite::write_json(result, output, auto_unbox = TRUE, pretty = TRUE, null = "null")
}, error = function(e) { original <<- list(class = class(e), message = conditionMessage(e)) },
   interrupt = function(e) { original <<- list(class = class(e), message = conditionMessage(e)) })
terminal_error <- NULL
terminal <- tryCatch(observe(), error = function(e) { terminal_error <<- list(class = class(e), message = conditionMessage(e)); NULL })
dput(list(original_error = original, terminal_error = terminal_error, observation = terminal,
    complete = is.null(original) && is.null(terminal_error)), paste0(output, ".terminal.R"))
if (!is.null(original) || !is.null(terminal_error)) quit(status = 1L)
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_archive", type=Path)
    parser.add_argument("lane_plan", type=Path)
    parser.add_argument("lane")
    parser.add_argument("output", type=Path)
    parser.add_argument("--binary-archive", type=Path)
    parser.add_argument("--timeout-seconds", type=float, default=1800)
    parser.add_argument("--install-timeout-seconds", type=float, default=1800)
    args = parser.parse_args()
    for value in (args.timeout_seconds, args.install_timeout_seconds):
        require(math.isfinite(value) and value > 0, "Finite positive timeout required")
    output = args.output.resolve()
    output.mkdir(parents=False, exist_ok=False)
    evidence, payload = output / "evidence", output / "payload"
    evidence.mkdir(); payload.mkdir()
    tracked, trees, steps = {}, {}, []
    original, runner_status = None, None
    started = time.time()

    def bind(path, expected=None):
        row = identity(path)
        require(expected is None or row["sha256"] == expected, f"Input digest differs: {path}")
        require(row["path"] not in tracked or tracked[row["path"]] == row, f"Input changed: {path}")
        tracked[row["path"]] = row
        return row

    def read_json(path):
        before = bind(path)
        raw = Path(path).read_bytes()
        require(hashlib.sha256(raw).hexdigest() == before["sha256"] and identity(path) == before, "JSON changed during read")
        return json.loads(raw, object_pairs_hook=unique_object)

    def bind_tree(name, root):
        rows = inventory(root)
        trees[name] = dict(root=str(root), before=rows)
        write_json(evidence / (name + "-inventory-before.json"), rows)
        return rows

    def step(name, command, env, timeout):
        record = dict(name=name, command=list(map(str, command)), cwd=str(payload),
            started=time.time(), returncode=None, original_error=None)
        write_json(evidence / (name + "-invocation.json"), record)
        log = payload / (name + ".log")
        try:
            with log.open("xb") as stream:
                result = subprocess.run(command, cwd=payload, env=env, stdout=stream,
                    stderr=subprocess.STDOUT, timeout=timeout)
            record["returncode"] = result.returncode
        except BaseException as error:
            record["original_error"] = error_record(error)
            raise
        finally:
            try:
                record["log"] = identity(log)
            except Exception as error:
                record["log_error"] = error_record(error)
            record["finished"] = time.time()
            steps.append(record)
            write_json(evidence / (name + "-result.json"), record)
        require(record["returncode"] == 0, f"{name} failed with exit {record['returncode']}; see retained payload log")

    try:
        scripts = Path(__file__).resolve().parent
        for path in (Path(__file__).resolve(), Path(sys.executable).resolve(),
                     scripts / "check_r_package_archive.py", scripts / "archive_safety.py", scripts / "run-r-native.py"):
            bind(path)
        source_archive = args.source_archive.resolve(strict=True)
        bind(source_archive)
        plan_path = args.lane_plan.resolve(strict=True)
        plan = read_json(plan_path)
        lane = plan["lanes"][args.lane]
        if plan_path.parent.name == "evidence":
            require((plan_path.parent / "completed.R").is_file(), "Provisioner completion is missing")
            bind_tree("provisioner-evidence", plan_path.parent)
        expected = copy.deepcopy(lane["expected_packages"])
        require(not set(expected) & (FORBIDDEN | {"dtatools"}), "Forbidden dependency selection")
        require({"callr", "data.table", "bit64", "jsonlite"} <= set(expected), "Required native test dependencies missing")
        library = payload / "library"
        library.mkdir()
        library_paths = [str(library), *[str(Path(lane[key]).resolve(strict=True)) for key in ("tests", "core", "empty")]]
        require(len(set(library_paths)) == len(library_paths), "Duplicate selected libraries")
        for role in ("core", "tests", "empty"):
            root = Path(lane[role]).resolve(strict=True)
            names = {name for name, selected in expected.items() if Path(selected["path"]).resolve(strict=True).parent == root}
            require({item.name for item in root.iterdir()} == names, f"Unexpected {role} library membership")
            bind_tree(role + "-dependencies", root)
        for name, selected in expected.items():
            selected_path = Path(selected["path"]).resolve(strict=True)
            require(selected_path.name == name and str(selected_path.parent) in library_paths[1:3], "Dependency path escapes selected core/test libraries")
        selected_r = bind(Path(lane["r"]).resolve(strict=True))
        startup = payload / "empty-startup"
        startup.write_bytes(b"")
        bind(startup)
        environment = {"R_HOME": None, "R_LIBS": os.pathsep.join(library_paths),
            "R_LIBS_USER": library_paths[-1], "R_LIBS_SITE": library_paths[-1],
            "R_ENVIRON": str(startup), "R_ENVIRON_USER": str(startup), "R_PROFILE": str(startup),
            "R_PROFILE_USER": str(startup), "R_MAKEVARS_USER": str(startup), "R_MAKEVARS_SITE": str(startup),
            "R_DEFAULT_PACKAGES": "utils,stats,methods", "R_TESTS": ""}
        extra = lane.get("runtime_environment", {})
        require(not set(extra) & set(environment), "Lane environment overrides isolation policy")
        require(all(isinstance(k, str) and (v is None or isinstance(v, str)) for k, v in extra.items()), "Invalid lane environment")
        environment.update(extra)
        env = os.environ.copy()
        for key, value in environment.items():
            if value is None:
                env.pop(key, None)
            else:
                env[key] = value
        write_json(evidence / "environment.json", environment)
        step("source-archive-check", [sys.executable, str(scripts / "check_r_package_archive.py"), str(source_archive)], env, 120)
        bind(source_archive)
        source_directory = payload / "source"
        source_directory.mkdir()
        with tarfile.open(source_archive, "r:gz") as archive:
            for member in archive:
                relative = PurePosixPath(member.name.removesuffix("/"))
                require(not relative.is_absolute() and ".." not in relative.parts and relative.parts[0] == "dtatools", "Unsafe source member")
                target = source_directory.joinpath(*relative.parts)
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    require(member.isfile(), "Nonregular source member")
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with target.open("xb") as stream, archive.extractfile(member) as content:
                        shutil.copyfileobj(content, stream)
                    os.chmod(target, stat.S_IMODE(member.mode))
        bind(source_archive)
        source = source_directory / "dtatools"
        bind_tree("source", source)
        manifest_path = source / "tools/native-test-manifest.json"
        source_manifest = read_json(manifest_path)
        require(source_manifest["schema_version"] == 1, "Unsupported native manifest")
        probe_script = evidence / "probe.R"
        probe_script.write_text(PROBE_R, encoding="utf-8")
        bind(probe_script)

        def probe(name, package_path=None, version=None):
            members = copy.deepcopy(expected)
            if package_path is not None:
                members["dtatools"] = dict(path=str(package_path), version=version)
            configuration = dict(libraries=library_paths, version=lane["R"], expected_packages=members,
                forbidden=sorted(FORBIDDEN), source_description=str(source / "DESCRIPTION"),
                package_path=str(package_path) if package_path else None)
            config_path, result_path = evidence / (name + "-config.R"), evidence / (name + ".json")
            config_path.write_text(r_literal(configuration) + "\n", encoding="utf-8")
            bind(config_path)
            step(name, [selected_r["path"], "--vanilla", "--slave", "-f", str(probe_script), "--args", str(config_path), str(result_path)], env, 120)
            result = read_json(result_path)
            require(result["complete"] is True, "Probe did not complete")
            return result

        before_probe = probe("dependency-probe")
        runtime = copy.deepcopy(before_probe["runtime"])
        runtime.update(r=selected_r, child_r=selected_r, rscript=bind(runtime["rscript"]))
        for executable in before_probe["command_paths"].values():
            if executable:
                bind(executable)
        install_archive = source_archive
        if args.binary_archive:
            install_archive = args.binary_archive.resolve(strict=True)
            bind(install_archive)
            safety_path = scripts / "archive_safety.py"
            spec = importlib.util.spec_from_file_location("_native_archive_safety", safety_path)
            safety = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(safety)
            entries, keys = {}, set()

            def binary_member(name, is_file):
                name = name.removesuffix("/")
                relative = safety.canonical_relative_path(name)
                require(relative is not None and relative.parts[0] == "dtatools", "Unsafe binary member")
                key = safety.portable_extraction_key(relative)
                require(name not in entries and key not in keys, "Duplicate or aliased binary member")
                entries[name] = is_file
                keys.add(key)

            if zipfile.is_zipfile(install_archive):
                with zipfile.ZipFile(install_archive) as archive:
                    for member in archive.infolist():
                        mode = member.external_attr >> 16
                        require(not stat.S_ISLNK(mode) and stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR), "Special binary ZIP member")
                        binary_member(member.filename, not member.is_dir())
            else:
                with tarfile.open(install_archive, "r:gz") as archive:
                    for member in archive:
                        require(member.isdir() or member.isfile(), "Special binary TAR member")
                        binary_member(member.name, member.isfile())
            require(safety.parent_file_conflict(entries) is None and entries.get("dtatools/DESCRIPTION") is True, "Invalid binary package layout")
            require(not any(name.startswith("dtatools/src/") for name in entries), "Binary archive contains source installation tree")
            write_json(evidence / "binary-members.json", entries)
            bind(install_archive)
        install_command = [selected_r["path"], "CMD", "INSTALL", "--no-multiarch", "--install-tests",
            "--library=" + str(library), str(install_archive)]
        step("install", install_command, env, args.install_timeout_seconds)
        bind(install_archive)
        require({path.name for path in library.iterdir()} == {"dtatools"}, "Fresh library membership differs after installation")
        installed = library / "dtatools"
        require(not (installed / "src").exists(), "Installed package retains a source tree")
        installed_files = bind_tree("installed-package", installed)
        after_probe = probe("installed-probe", installed, before_probe["source_version"])
        require(after_probe["capabilities"] == before_probe["capabilities"] and after_probe["runtime"] == before_probe["runtime"], "Runtime/capabilities changed before tests")
        package = after_probe["package"]
        require(package["dll_path"] in {row["resolved"] for row in installed_files}, "Loaded DLL is not an inventoried installed member")
        package["files"] = installed_files
        effective, applied = effective_manifest(source_manifest, before_probe["capabilities"])
        effective_path = evidence / "effective-manifest.json"
        write_json(effective_path, effective)
        bind(effective_path)
        write_json(evidence / "capability-selection.json", dict(probe=identity(evidence / "dependency-probe.json"),
            source_manifest=identity(manifest_path), capabilities=before_probe["capabilities"], applied=applied))
        tool_names = ("run-native.R", "library-guard.R", "native-children.R")
        tools = {name: bind(source / "tools" / name)["sha256"] for name in tool_names}
        cfg = dict(schema_version=1, lane=args.lane, lane_plan=identity(plan_path),
            source_root=str(source), manifest=identity(effective_path), runtime=runtime,
            package=package, tools=tools, bindings=list(tracked.values()),
            runtime_environment={"R_HOME": None, **extra}, timeout_seconds=args.timeout_seconds)
        config = evidence / "native-config.json"
        write_json(config, cfg)
        bind(config)
        runner = scripts / "run-r-native.py"
        step("native-tests", [sys.executable, str(runner), "--config", str(config), "--config-sha256",
            identity(config)["sha256"], "--output", str(evidence / "native")], env, args.timeout_seconds + 60)
        runner_status = read_json(evidence / "native/result.json")
        require(runner_status["complete"] is True, "Native runner result is incomplete")
    except BaseException as error:
        original = error_record(error)
    finally:
        terminal, changed = [], []
        for path, before in tracked.items():
            try:
                after = identity(path)
                terminal.append(after)
                if after != before:
                    changed.append(path)
            except Exception as error:
                terminal.append(dict(path=path, error=error_record(error)))
                changed.append(path)
        tree_results = []
        for name, selected in trees.items():
            try:
                after = inventory(selected["root"])
                write_json(evidence / (name + "-inventory-after.json"), after)
                unchanged = after == selected["before"]
                tree_results.append(dict(name=name, unchanged=unchanged))
                if not unchanged:
                    changed.append(selected["root"])
            except Exception as error:
                tree_results.append(dict(name=name, error=error_record(error), unchanged=False))
                changed.append(selected["root"])
        write_json(evidence / "result.json", dict(started=started, finished=time.time(), original_error=original,
            steps=steps, inputs_before=list(tracked.values()), inputs_after=terminal, trees=tree_results,
            changed_inputs=changed, complete=original is None and runner_status is not None and not changed,
            scope="Exact archive installation and selected native manifest on observed runtime/dependencies; payload code and compiler logs are excluded from evidence publication"))
    return 0 if original is None and runner_status is not None and not changed else 1


if __name__ == "__main__":
    sys.exit(main())
