#!/usr/bin/env python3
"""Build the sampler only when the benchmark machine is otherwise idle."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess

HERE = Path(__file__).resolve().parent
SDK = {
    "stplugin.c": "ab694f53e30a404bbfbe59d301a81b8bc59eeecf84bc5427eb65cbf0c5020d6d",
    "stplugin.h": "0d32086bfb7a621e30ed7fefa41b351b6733bb4561da28a4c581580d62c64e8b",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--compiler", default="clang")
    args = parser.parse_args()
    sdk = args.sdk.resolve()
    output = args.output.resolve()
    if output.exists() or output.with_suffix(".json").exists():
        raise ValueError("Sampler output or build record already exists")
    for name, expected in SDK.items():
        if digest(sdk / name) != expected:
            raise ValueError("Official SPI file hash differs: " + name)
    if platform.system() == "Darwin":
        flags = ["-bundle", "-DSYSTEM=APPLEMAC", "-target",
                 platform.machine() + "-apple-macos11"]
    elif platform.system() == "Linux":
        flags = ["-shared", "-fPIC", "-DSYSTEM=OPUNIX"]
    else:
        raise ValueError("Sampler supports macOS and Linux")
    output.parent.mkdir(parents=True, exist_ok=True)
    common = ["-O2", "-std=c11", "-D_POSIX_C_SOURCE=200809L"]
    command = [args.compiler] + common + flags + [
        "-I", str(sdk), str(sdk / "stplugin.c"), str(HERE / "cpuclock.c"),
        "-o", str(output)]
    subprocess.run(command, check=True)
    record = dict(sdk={name: dict(sha256=value,
        url="https://www.stata.com/plugins/" + name) for name, value in SDK.items()},
        wrapper_sha256=digest(HERE / "cpuclock.c"),
        builder_sha256=digest(Path(__file__)), plugin_sha256=digest(output),
        compiler=subprocess.check_output([args.compiler, "--version"], text=True).splitlines()[0],
        flags=common + flags, host=platform.platform())
    output.with_suffix(".json").write_text(json.dumps(record, indent=2) + "\n")


if __name__ == "__main__":
    main()
