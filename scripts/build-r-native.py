#!/usr/bin/env python3
"""Build dtatools with physically isolated native dependencies.

Usage: build-r-native.py PACKAGE_SOURCE LANE_PLAN LANE NEW_OUTPUT
Feed NEW_OUTPUT/payload/dtatools_VERSION.tar.gz to check-r-native.py.
Upload only NEW_OUTPUT/evidence; source, archives and build logs stay in payload.
"""

import argparse
import copy
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package_source", type=Path)
    parser.add_argument("lane_plan", type=Path)
    parser.add_argument("lane")
    parser.add_argument("output", type=Path)
    parser.add_argument("--timeout-seconds", type=float, default=1800)
    args = parser.parse_args()
    if not math.isfinite(args.timeout_seconds) or args.timeout_seconds <= 0:
        raise ValueError("Finite positive timeout required")

    scripts = Path(__file__).resolve().parent
    helper_path = scripts / "check-r-native.py"
    helper_bytes = helper_path.read_bytes()
    spec = importlib.util.spec_from_file_location("_native_build_helpers", helper_path)
    helper = importlib.util.module_from_spec(spec)
    # Execute the selected source bytes without producing an untracked pyc file.
    exec(compile(helper_bytes, str(helper_path), "exec"), helper.__dict__)
    require, identity = helper.require, helper.identity
    write_json, inventory = helper.write_json, helper.inventory
    source = args.package_source.resolve(strict=True)
    output = args.output.resolve()
    require(output != source and source not in output.parents, "Output must be outside package source")
    output.mkdir(parents=False, exist_ok=False)
    evidence, payload = output / "evidence", output / "payload"
    evidence.mkdir()
    payload.mkdir()
    tracked, trees, steps = {}, {}, []
    original, post_error, archive_record = None, None, None
    started = time.time()

    def bind(path):
        row = identity(path)
        require(row["path"] not in tracked or tracked[row["path"]] == row, f"Input changed: {path}")
        tracked[row["path"]] = row
        return row

    def read_json(path):
        before = bind(path)
        raw = Path(path).read_bytes()
        require(hashlib.sha256(raw).hexdigest() == before["sha256"] and identity(path) == before,
                "JSON changed during read")
        return json.loads(raw, object_pairs_hook=helper.unique_object)

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
            record["original_error"] = helper.error_record(error)
            raise
        finally:
            try:
                record["log"] = identity(log)
            except Exception as error:
                record["log_error"] = helper.error_record(error)
            record["finished"] = time.time()
            steps.append(record)
            write_json(evidence / (name + "-result.json"), record)
        require(record["returncode"] == 0,
                f"{name} failed with exit {record['returncode']}; see retained payload log")

    try:
        for path in (Path(__file__).resolve(), Path(sys.executable).resolve(), helper_path,
                     scripts / "check_r_package_archive.py", scripts / "archive_safety.py"):
            bind(path)
        require(bind(helper_path)["sha256"] == hashlib.sha256(helper_bytes).hexdigest(),
                "Imported helper changed during load")
        source_files = bind_tree("source", source)
        require((source / "DESCRIPTION").is_file(), "Package DESCRIPTION is missing")
        plan_path = args.lane_plan.resolve(strict=True)
        plan = read_json(plan_path)
        lane = plan["lanes"][args.lane]
        if plan_path.parent.name == "evidence":
            require((plan_path.parent / "completed.R").is_file(), "Provisioner completion is missing")
            bind_tree("provisioner-evidence", plan_path.parent)
        expected = copy.deepcopy(lane["expected_packages"])
        require(not set(expected) & (helper.FORBIDDEN | {"dtatools"}), "Forbidden dependency selection")
        require("jsonlite" in expected, "Native probe dependency jsonlite is missing")
        library = payload / "library"
        library.mkdir()
        roots = [Path(lane[key]).resolve(strict=True) for key in ("tests", "core", "empty")]
        library_paths = [str(library), *map(str, roots)]
        require(len(set(library_paths)) == len(library_paths), "Duplicate selected libraries")
        for role, root in zip(("tests", "core", "empty"), roots):
            require(output != root and root not in output.parents, "Output overlaps dependency library")
            names = {name for name, selected in expected.items()
                     if Path(selected["path"]).resolve(strict=True).parent == root}
            require({item.name for item in root.iterdir()} == names,
                    f"Unexpected {role} library membership")
            bind_tree(role + "-dependencies", root)
        for name, selected in expected.items():
            selected_path = Path(selected["path"]).resolve(strict=True)
            require(selected_path.name == name and selected_path.parent in roots[:2],
                    "Dependency path escapes selected core/test libraries")
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
        require(all(isinstance(k, str) and (v is None or isinstance(v, str)) for k, v in extra.items()),
                "Invalid lane environment")
        environment.update(extra)
        env = os.environ.copy()
        for key, value in environment.items():
            if value is None:
                env.pop(key, None)
            else:
                env[key] = value
        write_json(evidence / "environment.json", environment)
        staged = payload / "source" / "dtatools"
        shutil.copytree(source, staged)
        staged_files = bind_tree("staged-source", staged)
        selected_fields = ("relative", "bytes", "mode", "sha256")
        project = lambda rows: [{key: row[key] for key in selected_fields} for row in rows]
        require(project(staged_files) == project(source_files), "Staged source differs from selected source")
        probe_script = evidence / "probe.R"
        probe_script.write_text(helper.PROBE_R, encoding="utf-8")
        bind(probe_script)

        def probe(name):
            configuration = dict(libraries=library_paths, version=lane["R"], expected_packages=expected,
                forbidden=sorted(helper.FORBIDDEN), source_description=str(staged / "DESCRIPTION"),
                package_path=None)
            config_path, result_path = evidence / (name + "-config.R"), evidence / (name + ".json")
            config_path.write_text(helper.r_literal(configuration) + "\n", encoding="utf-8")
            bind(config_path)
            step(name, [selected_r["path"], "--vanilla", "--slave", "-f", str(probe_script),
                        "--args", str(config_path), str(result_path)], env, 120)
            result = read_json(result_path)
            require(result["complete"] is True, "Probe did not complete")
            for suffix in (".before.R", ".terminal.R"):
                bind(Path(str(result_path) + suffix))
            return result

        before_probe = probe("pre-build-probe")
        bind(before_probe["runtime"]["rscript"])
        try:
            step("build", [selected_r["path"], "CMD", "build", str(staged)], env, args.timeout_seconds)
            archives = list(payload.glob("dtatools_*.tar.gz"))
            require(len(archives) == 1, "Expected exactly one built source archive")
            archive = archives[0]
            require(archive.name == "dtatools_" + before_probe["source_version"] + ".tar.gz",
                    "Built archive version differs")
            archive_record = bind(archive)
            step("source-archive-check", [sys.executable, str(scripts / "check_r_package_archive.py"),
                                          str(archive)], env, 120)
            bind(archive)
        finally:
            try:
                after_probe = probe("post-build-probe")
                for key in ("runtime", "capabilities", "source_version", "before", "after"):
                    require(after_probe[key] == before_probe[key], f"Build probe state changed: {key}")
                require(not list(library.iterdir()), "Build installed an unexpected package")
            except BaseException as error:
                post_error = helper.error_record(error)
    except BaseException as error:
        original = helper.error_record(error)
    finally:
        terminal, changed = [], []
        for path, before in tracked.items():
            try:
                after = identity(path)
                terminal.append(after)
                if after != before:
                    changed.append(path)
            except Exception as error:
                terminal.append(dict(path=path, error=helper.error_record(error)))
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
                tree_results.append(dict(name=name, error=helper.error_record(error), unchanged=False))
                changed.append(selected["root"])
        complete = original is None and post_error is None and archive_record is not None and not changed
        write_json(evidence / "result.json", dict(started=started, finished=time.time(),
            original_error=original, post_build_error=post_error, steps=steps,
            inputs_before=list(tracked.values()), inputs_after=terminal, trees=tree_results,
            changed_inputs=changed, archive=archive_record, complete=complete,
            scope="Source build with selected isolated libraries and independent pre/post probes; no installation or native test qualification"))
    return 0 if complete else 1


if __name__ == "__main__":
    raise SystemExit(main())
