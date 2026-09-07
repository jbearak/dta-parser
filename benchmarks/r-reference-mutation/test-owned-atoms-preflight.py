"""Exercise the real native runner's output preflight without its workloads.

Use an exact installed package and a new evidence directory. Only git is
synthetic: its sentinel proves whether preflight admitted the destination, then
fails before runner identity files or measured workloads can start. Inputs and
failed child logs remain available for inspection; no timing claim is made.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(directory):
    """Record fixture contents and modes so every rejected run proves no edits."""
    if not directory.exists():
        return None
    return [{"path": str(path.relative_to(directory)), "mode": path.lstat().st_mode,
             "sha256": digest(path) if path.is_file() else None}
            for path in sorted(directory.rglob("*"))]


def main():
    """Check stale, hidden and nested fixtures plus admitted/invalid controls.

    The runner validates the requested installation in every child. This probe
    records current runner/helper bytes, allowing development red/green runs;
    it does not turn a working source tree into an exact committed artifact.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=Path)
    parser.add_argument("source_sha")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output, library = args.output.resolve(), args.library.resolve()
    require(re.fullmatch("[0-9a-f]{40}", args.source_sha), "Use a full source commit")
    require(library.is_dir(), "Installed library is missing")
    require(not output.exists(), "Evidence destination already exists")
    runner = root / "benchmarks/r-reference-mutation/owned-atoms.R"
    paths = [Path(__file__).resolve(), runner, root / "benchmarks/r-dibble-dplyr/helpers.R"]
    identities = {str(path.relative_to(root)): digest(path) for path in paths}
    output.mkdir(parents=True)
    synthetic = output / "synthetic-bin"
    synthetic.mkdir()
    git = synthetic / "git"
    git.write_text('#!/bin/sh\nprintf called > "$PREFLIGHT_SENTINEL"\nexit 71\n')
    git.chmod(0o755)
    records = []
    for name in ["empty", "unrelated", "hidden", "nested", "empty-child",
                 "csv", "identity", "missing"]:
        destination = output / name
        if name != "missing":
            destination.mkdir()
        filenames = {"unrelated": "stale.txt", "hidden": ".stale",
                     "csv": "owned-native-atoms.csv", "identity": "owned-native-atoms-session.txt"}
        if name in filenames:
            (destination / filenames[name]).write_text("preserve me\n")
        if name in ["nested", "empty-child"]:
            (destination / "child").mkdir()
            if name == "nested":
                (destination / "child/stale.txt").write_text("preserve me\n")
        before = snapshot(destination)
        sentinel = output / (name + "-sentinel")
        environment = os.environ.copy()
        environment["PATH"] = str(synthetic) + os.pathsep + environment["PATH"]
        environment["PREFLIGHT_SENTINEL"] = str(sentinel)
        command = ["Rscript", "--vanilla", str(runner), str(library),
                   args.source_sha, str(destination)]
        result = subprocess.run(command, cwd=root, env=environment, capture_output=True)
        stdout, stderr = output / (name + ".stdout"), output / (name + ".stderr")
        stdout.write_bytes(result.stdout)
        stderr.write_bytes(result.stderr)
        unchanged = snapshot(destination) == before
        reached = sentinel.exists()
        diagnostic = (b"Output directory must be readable and empty before qualification" in result.stderr
                      if name in ["unrelated", "hidden", "nested", "empty-child"] else True)
        passed = result.returncode != 0 and unchanged and reached == (name == "empty") and diagnostic
        records.append({"case": name, "command": command, "exit_code": result.returncode,
                        "before": before, "after": snapshot(destination), "sentinel_reached": reached,
                        "unchanged": unchanged, "expected_diagnostic": diagnostic, "passed": passed,
                        "stdout_sha256": digest(stdout), "stderr_sha256": digest(stderr)})
    sources_unchanged = identities == {str(path.relative_to(root)): digest(path) for path in paths}
    manifest = {"scope": __doc__, "source_sha": args.source_sha, "library": str(library),
                "source_sha256": identities, "sources_unchanged": sources_unchanged,
                "synthetic_git_sha256": digest(git), "cases": records}
    with (output / "manifest.json").open("x") as file:
        json.dump(manifest, file, indent=2)
        file.write("\n")
    require(sources_unchanged, "Probe inputs changed during execution")
    require(all(record["passed"] for record in records), "Output preflight failed; see retained manifest/logs")
    print("All eight actual-runner preflight cases passed; no workloads ran")


if __name__ == "__main__":
    main()
