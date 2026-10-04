#!/usr/bin/env python3
"""Exercise actual descriptor and span sources without loading or compiling R."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent


def function(source, name):
    begin = source.index("void " + name + "(")
    opening = source.index("{", begin)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[begin:end]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    source = args.root.resolve() / "r-package/dtatools/src"
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    internal = source / "dtatools-internal.h"
    payload = source / "numeric-payload.c"
    paths = [internal, payload, HERE / "metadata-span.c", Path(__file__).resolve()]
    before = {str(path): sha(path) for path in paths}
    header = internal.read_text()
    begin = header.index("typedef struct {\n    void *values;\n    size_t length;\n    int kind;")
    end = header.index("/* One contiguous plain span", begin)
    # Keep the production callback type, which immediately follows the owner predicate.
    end = header.index("typedef struct {", end)
    (output / "production-descriptor.h").write_text(header[begin:end])
    (output / "production-span.h").write_text(function(payload.read_text(), "numeric_for_each_span"))
    compile_args = ["clang", "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2",
                    "-I", str(output), str(HERE / "metadata-span.c"),
                    "-o", str(output / "metadata-span")]
    subprocess.run(compile_args, cwd=output, check=True, capture_output=True, text=True)
    result = subprocess.run([str(output / "metadata-span")], cwd=output,
                            check=True, capture_output=True, text=True)
    after = {str(path): sha(path) for path in paths}
    if before != after:
        raise RuntimeError("source changed during the probe")
    receipt = {"source_sha256": before, "command": compile_args, "cwd": str(output),
               "stdout": result.stdout.strip(), "exit_code": result.returncode}
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(result.stdout.strip())


if __name__ == "__main__":
    main()
