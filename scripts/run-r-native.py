"""Verify installed native tests using prepared, isolated dependency libraries."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import time


def identity(path):
    path = Path(path)
    raw = path.read_bytes()
    info = path.stat()
    if not stat.S_ISREG(info.st_mode):
        raise ValueError(f"Not a regular file: {path}")
    return {"path": str(path.absolute()), "resolved": str(path.resolve(strict=True)),
            "bytes": len(raw), "mode": stat.S_IMODE(info.st_mode),
            "sha256": hashlib.sha256(raw).hexdigest()}


def write_json(path, value):
    with Path(path).open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.write("\n")


def error_record(error):
    return {"type": type(error).__name__, "message": str(error)}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def r_literal(value):
    # Trusted generated data only, never interpolate caller-provided R code.
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, str):
        require("\0" not in value, "NUL in configuration string")
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (int, float)):
        require(math.isfinite(value), "Non-finite configuration number")
        return repr(value)
    if isinstance(value, list):
        return "list(" + ",".join(map(r_literal, value)) + ")"
    if isinstance(value, dict):
        return "structure(list(" + ",".join(map(r_literal, value.values())) + \
            "),names=c(" + ",".join(map(r_literal, value.keys())) + "))"
    raise TypeError(type(value).__name__)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--config-sha256", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = Path(args.output).resolve()
    output.mkdir(parents=False, exist_ok=False)
    tracked = {}
    original_error = None
    returncode = None
    attempted = False
    command = None
    env_overrides = None
    started = time.time()

    def bind(path, expected=None):
        before = identity(path)
        if expected is not None:
            require(before["sha256"] == expected, f"Unapproved input: {path}")
        key = before["path"]
        require(key not in tracked or tracked[key] == before, f"Input changed: {path}")
        tracked[key] = before
        return before

    def read_json(selected):
        before = bind(selected["path"], selected["sha256"])
        raw = Path(selected["path"]).read_bytes()
        require(hashlib.sha256(raw).hexdigest() == before["sha256"], "Changed JSON read")
        require(identity(selected["path"]) == before, "Changed JSON after read")
        def unique_object(pairs):
            result = {}
            for key, value in pairs:
                require(key not in result, f"Duplicate JSON key: {key}")
                result[key] = value
            return result
        return json.loads(raw, object_pairs_hook=unique_object)

    def copy_bound(source, target, digest):
        before = bind(source, digest)
        raw = Path(source).read_bytes()
        require(hashlib.sha256(raw).hexdigest() == digest, "Changed source during copy")
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as stream:
            stream.write(raw)
        os.chmod(target, before["mode"])
        require(identity(source) == before, "Source changed after copy")
        bind(target, digest)

    try:
        bind(Path(__file__).resolve())
        bind(Path(sys.executable).resolve())
        cfg = read_json({"path": args.config, "sha256": args.config_sha256})
        require(cfg["schema_version"] == 1, "Unsupported configuration schema")
        plan = read_json(cfg["lane_plan"])
        lane = plan["lanes"][cfg["lane"]]
        manifest = read_json(cfg["manifest"])
        require(manifest["schema_version"] == 1, "Unsupported manifest schema")
        runtime = cfg["runtime"]
        require(Path(runtime["r"]["path"]).resolve() == Path(lane["r"]).resolve(),
                "Selected R differs from lane")
        require(runtime["version"] == lane["R"], "R version differs from lane")
        for endpoint in ("r", "child_r", "rscript"):
            bind(runtime[endpoint]["path"], runtime[endpoint]["sha256"])
        for selected in cfg["bindings"]:
            bind(selected["path"], selected["sha256"])
        installed = Path(cfg["package"]["path"]).resolve(strict=True)
        require(installed.name == "dtatools", "Expected installed dtatools directory")
        require(not (installed / "src").exists(), "Source/package-load shortcut is forbidden")
        require(bool(cfg["package"]["files"]), "Installed file bindings are required")
        for selected in cfg["package"]["files"]:
            path = Path(selected["path"]).resolve(strict=True)
            require(path.is_relative_to(installed), "Installed binding escapes package")
            bind(path, selected["sha256"])
        dll = Path(cfg["package"]["dll_path"]).resolve(strict=True)
        require(str(dll) in {str(Path(x["path"]).resolve(strict=True)) for x in cfg["package"]["files"]},
                "Selected installed DLL must be an explicit bound package file")

        libraries = [str(installed.parent), lane["tests"], lane["core"], lane["empty"], runtime["base_library"]]
        require(all(Path(p).is_dir() for p in libraries), "Missing library directory")
        libraries = [str(Path(p).resolve(strict=True)) for p in libraries]
        require(len(set(libraries)) == len(libraries), "Duplicate resolved libraries")
        expected = dict(lane["expected_packages"])
        require("dtatools" not in expected, "dtatools must have its own installed library")
        expected["dtatools"] = {"path": str(installed), "version": cfg["package"]["version"]}
        require(len(manifest["exports"]) == 106 and len(set(manifest["exports"])) == 106,
                "Explicit 106-name export manifest required")
        source_root = Path(cfg["source_root"]).resolve(strict=True)
        tools_dir = source_root / "tools"
        tool_files = cfg["tools"]
        require(set(tool_files) == {"run-native.R", "library-guard.R", "native-children.R"},
                "Exact native tool membership required")
        for name, digest in tool_files.items():
            copy_bound(tools_dir / name, output / "tools" / name, digest)

        generated = {"schema_version": 1, "lane": cfg["lane"], "libraries": libraries,
                     "expected_packages": expected, "runtime": runtime,
                     "package": cfg["package"], "forbidden": ["dplyr", "labelled", "dtplyr", "tidyr", "haven"],
                     "exports": manifest["exports"], "output": str(output),
                     "guard": str(output / "tools/library-guard.R"),
                     "children": str(output / "tools/native-children.R"), "families": []}
        family_ids = set()
        assigned_files = set()
        for family in manifest["families"]:
            name = family["id"]
            require(re.fullmatch(r"[a-z][a-z0-9_-]*", name) is not None, "Unsafe family id")
            require(name not in family_ids, "Duplicate family id")
            family_ids.add(name)
            require(bool(family["files"]) and bool(family["blocks"]), "Empty family")
            test_root = output / "families" / name / "tests/testthat"
            tests = set()
            for selected in [*manifest["helpers"], *manifest.get("fixtures", []), *family["files"]]:
                relative = Path(selected["path"])
                require(not relative.is_absolute() and ".." not in relative.parts, "Unsafe source member")
                source = (source_root / relative).resolve(strict=True)
                require(source.is_relative_to(source_root), "Source member escapes selected root")
                require(relative.parts[:2] == ("tests", "testthat"), "Expected testthat source member")
                target = output / "families" / name / relative
                copy_bound(source, target, selected["sha256"])
            for selected in family["files"]:
                filename = Path(selected["path"]).name
                require(filename.startswith("test-") and filename.endswith(".R"), "Test file name required")
                require(selected["path"] not in assigned_files, "A complete test file occurs in multiple families")
                assigned_files.add(selected["path"])
                tests.add(filename)
            pairs = [(b["file"], b["test"], b.get("occurrence", 1)) for b in family["blocks"]]
            require(len(pairs) == len(set(pairs)), "Ambiguous file/test block identity")
            require(set(b["file"] for b in family["blocks"]) == tests, "Block/file membership mismatch")
            for block in family["blocks"]:
                require(block["skip"] in ("forbid", "allow", "require"), "Explicit skip policy required")
                require(isinstance(block["min_pass"], int) and block["min_pass"] >= 0, "Invalid pass minimum")
                require(isinstance(block["warnings"], int) and block["warnings"] >= 0, "Invalid warning allowance")
                require(isinstance(block.get("occurrence", 1), int) and block.get("occurrence", 1) > 0,
                        "Invalid block occurrence")
                if block["skip"] != "forbid":
                    require(bool(block.get("reason")), "Explain optional/capability skip")
                    require(isinstance(block.get("min_pass_before_skip"), int) and
                            block["min_pass_before_skip"] >= 0,
                            "Explicit pre-skip assertion minimum required")
            child_ids = [c["id"] for c in family["children"]]
            require(len(child_ids) == len(set(child_ids)), "Duplicate child policy")
            for owner in [family, *family["children"]]:
                forks = owner.get("forks", [])
                require(isinstance(forks, list), "Fork policies must be a list")
                require(len({f["id"] for f in forks}) == len(forks), "Duplicate fork id")
                for fork in forks:
                    require(re.fullmatch(r"[a-z][a-z0-9_-]*", fork["id"]) is not None, "Unsafe fork id")
                    require(type(fork["minimum"]) is int and type(fork["maximum"]) is int and
                            0 <= fork["minimum"] <= fork["maximum"] <= 1, "Fork count must be zero or one")
                    require(fork["delay"] in (0.01, 0.05), "Only existing signal-helper delays are supported")
                owner["forks"] = forks
            for child in family["children"]:
                require(re.fullmatch(r"[a-z][a-z0-9_-]*", child["id"]) is not None, "Unsafe child id")
                require(child["kind"] in ("r", "r_bg", "rscript"), "Unknown child kind")
                require(child["completion"] in ("complete", "service"), "Unknown child completion")
                require(child["completion"] != "service" or child["kind"] == "r_bg", "Only background services may terminate")
                require(0 <= child["minimum"] <= child["maximum"], "Invalid child counts")
            generated["families"].append({**family, "test_root": str(test_root)})
        require(bool(generated["families"]), "No families selected")
        empty_startup = output / "empty-startup"
        empty_startup.write_bytes(b"")
        generated["empty_startup"] = str(empty_startup)
        generated_path = output / "configuration.R"
        generated_path.write_text(r_literal(generated) + "\n", encoding="utf-8")
        bind(generated_path)
        bind(empty_startup)
        env_overrides = {"R_LIBS": os.pathsep.join(libraries[:-1]),
                         "R_LIBS_USER": lane["empty"], "R_LIBS_SITE": lane["empty"],
                         "R_ENVIRON": str(empty_startup), "R_ENVIRON_USER": str(empty_startup),
                         "R_PROFILE": str(empty_startup), "R_PROFILE_USER": str(empty_startup),
                         "R_DEFAULT_PACKAGES": "utils,stats,methods", "R_TESTS": ""}
        # Endpoint-specific minimum-runtime loader policy is explicit caller data.
        extra_env = cfg.get("runtime_environment", {})
        require(not set(extra_env).intersection(env_overrides), "Runtime environment overrides isolation policy")
        require(all(isinstance(k, str) and (isinstance(v, str) or v is None)
                    for k, v in extra_env.items()), "Invalid runtime environment")
        env = os.environ.copy()
        for key, value in extra_env.items():
            if value is None:
                env.pop(key, None)
            else:
                env[key] = value
        env.update(env_overrides)
        command = [runtime["r"]["path"], "--vanilla", "--slave", "-f",
                   str(output / "tools/run-native.R"), "--args", str(generated_path)]
        require(isinstance(cfg["timeout_seconds"], (int, float)) and
                math.isfinite(cfg["timeout_seconds"]) and cfg["timeout_seconds"] > 0,
                "Finite positive parent timeout required")
        write_json(output / "invocation.json", {"argv": command, "cwd": str(output),
                   "started": started, "inputs": list(tracked.values()),
                   "environment_overrides": {**extra_env, **env_overrides},
                   "scope": "Selected inputs and installed native tests; no provisioning or complete image closure"})
        attempted = True
        with (output / "console.log").open("xb") as log:
            result = subprocess.run(command, cwd=output, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=cfg["timeout_seconds"])
        returncode = result.returncode
        require(returncode == 0, "Native R runner failed; preserve console and R records")
        require((output / "completed.R").is_file(), "Missing R completion record")
    except BaseException as error:
        original_error = error_record(error)
    finally:
        terminal = []
        changed = []
        for path, before in tracked.items():
            try:
                after = identity(path)
                terminal.append(after)
                if after != before:
                    changed.append(path)
            except Exception as error:
                terminal.append({"path": path, "error": error_record(error)})
                changed.append(path)
        write_json(output / "result.json", {"started": started, "finished": time.time(),
                   "attempted": attempted, "command": command, "returncode": returncode,
                   "original_error": original_error, "inputs_before": list(tracked.values()),
                   "inputs_after": terminal, "changed_inputs": changed,
                   "complete": original_error is None and returncode == 0 and not changed})
    return 0 if original_error is None and returncode == 0 and not changed else 1


if __name__ == "__main__":
    sys.exit(main())
