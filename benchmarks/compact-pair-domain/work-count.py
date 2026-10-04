#!/usr/bin/env python3
"""Check current mixed-pair headers with a small independent oracle.

R allocation, ownership and callback boundaries are mocked by the existing
domain probe. This is a semantic/work diagnostic, not a package or timing test.
"""
import argparse
import csv
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SPEC = importlib.util.spec_from_file_location(
    "domain_probe", HERE.parent / "compact-float-domain/work-count.py")
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(root, commit=None):
    src = root / "r-package/dtatools/src"
    files = sorted(src.glob("numeric-arithmetic*.h")) + [
        src / "numeric-payload.c", src / "dtatools-internal.h",
        root / "benchmarks/compact-float-domain/work-count.c",
        root / "benchmarks/compact-float-domain/work-count.py",
        HERE / "work-count.py", HERE / "work-count.c"]
    result = {str(path.relative_to(root)): sha(path) for path in files}
    if commit is not None:
        BASE.require(len(commit) == 40 and all(c in "0123456789abcdef" for c in commit),
                     "Expected a full immutable source commit")
        for path, digest in result.items():
            original = subprocess.check_output(["git", "--no-replace-objects", "show",
                commit + ":" + path], cwd=root)
            BASE.require(hashlib.sha256(original).hexdigest() == digest,
                         "Source differs from immutable commit: " + path)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--root", default=ROOT, type=Path)
    parser.add_argument("--commit", help="Optional full immutable source commit")
    parser.add_argument("--require-proved", action="store_true")
    args = parser.parse_args()
    compiler = shutil.which("cc")
    BASE.require(compiler is not None, "C compiler cc is required")
    compiler = Path(compiler).resolve()
    root = args.root.resolve()
    before = inventory(root, args.commit)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    src = root / "r-package/dtatools/src"
    for path in src.glob("numeric-arithmetic*.h"):
        (output / path.name).write_bytes(path.read_bytes())
    arithmetic = (src / "numeric-arithmetic.h").read_text()
    begin = arithmetic.index("typedef struct {\n    double minimum;")
    end = arithmetic.index("/* Missing-bearing same-width", begin)
    common = arithmetic[begin:end]
    for name in ("numeric_strict_modern_float", "numeric_float_bounds_known",
                 "numeric_zero_count_known"):
        common += "\n" + BASE.function((src / "dtatools-internal.h").read_text(), name)
    for name, path in [
        ("arithmetic_promoted_kind", "numeric-arithmetic.h"),
        ("numeric_float_observed_limit", "numeric-payload.c"),
        ("scalar_arithmetic_result_valid", "numeric-payload.c"),
        ("arithmetic_integer_missing", "numeric-arithmetic-integer.h"),
        ("arithmetic_scale_float_invalid_modern", "numeric-arithmetic-scale.h"),
        ("arithmetic_scale_float_invalid_legacy", "numeric-arithmetic-scale.h")]:
        common += "\n" + BASE.function((src / path).read_text(), name)
    (output / "production-common.h").write_text(common)
    pair = output / "numeric-arithmetic-pair.h"
    pair.write_text(BASE.replace_once(pair.read_text(), "        (void) policy;",
        "        exact_float_rows++;                                       \\\n        (void) policy;"))
    canonical = output / "numeric-arithmetic-pair-long-float.h"
    canonical.write_text(BASE.replace_once(canonical.read_text(),
        "        (void) policy;",
        "        canonical_rows++;                                         \\\n        (void) policy;"))
    narrowed = output / "numeric-arithmetic-pair-float.h"
    continuation = " " + chr(92) + "\n"
    narrowed.write_text(BASE.replace_once(narrowed.read_text(),
        "            if (!(RANGE_PROVED)) {",
        "            if (RANGE_PROVED) pair_range_proved_rows++;" + continuation +
        "            if (!(RANGE_PROVED)) {"))
    narrowed.write_text(BASE.replace_once(narrowed.read_text(),
        "                maximum = bits > maximum ? bits : maximum;",
        "                pair_maximum_rows++;" + continuation +
        "                maximum = bits > maximum ? bits : maximum;"))
    command = [str(compiler), "-std=c11", "-O1", "-ffp-contract=off",
        "-frounding-math", "-Wall", "-Wextra", "-Werror",
        "-Wno-unused-function", "-I", str(output), str(HERE / "work-count.c"),
        "-lm", "-o", str(output / "probe")]
    compiler_before = sha(compiler)
    compiled = subprocess.run(command, text=True, capture_output=True, cwd=root)
    (output / "compile.log").write_text(compiled.stdout + compiled.stderr)
    BASE.require(compiled.returncode == 0, "Compilation failed; see compile.log")
    run = subprocess.run([str(output / "probe")], text=True, capture_output=True, cwd=root)
    (output / "cases.csv").write_text(run.stdout)
    (output / "probe.log").write_text(run.stderr)
    rows = list(csv.DictReader(io.StringIO(run.stdout)))
    expected = [(str(mode), pattern, str(strict), str(chunked), str(reverse), op, "1", "legacy")
        for mode in range(4) for pattern in ("ordinary", "sparse", "tags", "edges",
            "limit_above", "limit_below", "cancel")
        for strict in range(2) if pattern != "edges" or strict == 0
        for chunked in range(2) for reverse in range(2) for op in ("+", "-", "*")]
    # Preserve the original 624-case matrix, then qualify facts separately.
    for mode in range(4):
        for kind in (0, 1, 3):
            for pattern in ("ordinary", "sparse", "tags", "cancel"):
                modes = ("known", "conservative", "subset", "unknown", "outside") \
                    if pattern in ("ordinary", "tags") else ("known",)
                expected.extend((str(mode), pattern, "1", str(chunked), str(reverse), op,
                                 str(kind), facts)
                    for facts in modes for chunked in range(2) for reverse in range(2)
                    for op in ("+", "-", "*"))
        for kind, patterns in ((1, ("limit_above", "limit_below", "physical_min", "endpoint")),
                               (3, ("sum_inside", "product_inside", "product_endpoint",
                                    "product_outside", "endpoint"))):
            expected.extend((str(mode), pattern, "1", str(chunked), str(reverse), op,
                             str(kind), facts)
                for pattern in patterns for facts in ("known", "unknown")
                for chunked in range(2) for reverse in range(2) for op in ("+", "-", "*"))
    keys = [tuple(row[k] for k in ("mode", "pattern", "strict", "chunked", "reverse", "op",
                                   "left_kind", "facts"))
            for row in rows]
    BASE.require(keys == expected, "Incomplete, duplicated or reordered matrix")
    semantics = sum(int(row["semantic_failures"]) for row in rows)
    work = sum(int(row["work_failure"]) for row in rows)
    BASE.require(run.returncode == (1 if semantics else 0), "Unexpected probe status")
    BASE.require(before == inventory(root, args.commit), "Consumed source changed during probe")
    BASE.require(compiler_before == sha(compiler), "Compiler changed during probe")
    status = 1 if semantics or (args.require_proved and work) else 0
    production = {Path(path).name: digest for path, digest in before.items()
                  if path.startswith("r-package/dtatools/src/")}
    record = dict(source_sha256=production, consumed_source_sha256=before,
        source_before_after_equal=True,
        head=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        commit=args.commit, compiler_sha256=compiler_before, command=command, cwd=str(root),
        cases=len(rows), semantic_failures=semantics, work_failures=work,
        original_cases=624, fact_cases=len(rows) - 624,
        range_proved_rows=sum(int(row["range_proved_rows"]) for row in rows),
        maximum_reduction_rows=sum(int(row["maximum_rows"]) for row in rows),
        require_proved=args.require_proved, exit_code=status,
        scope="Actual mixed pair headers; independent binary64-then-binary32 oracle. "
              "Mocked R boundaries; no package ownership, runtime or performance claim.",
        artifact_sha256={path.name: sha(path) for path in output.iterdir() if path.is_file()})
    (output / "receipt.json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"{'FAIL' if status else 'PASS'}: {semantics} semantic failures, "
          f"{work} work failures across {len(rows)} cases")
    print("Receipt:", output / "receipt.json")
    raise SystemExit(status)


if __name__ == "__main__":
    main()
