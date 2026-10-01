import json
import os
from pathlib import Path
import subprocess

directory = Path(__file__).parent
config = json.loads((directory / "configuration.json").read_text())
records = []
for kind in ("typed", "ordinary", "one-column"):
    for direction in (("1:m",) if kind == "one-column" else ("1:m", "m:1")):
        expected = None
        for variant in ("baseline", "candidate"):
            env = os.environ.copy()
            env.update(R_LIBS=config[variant], DTATOOLS_BENCH_LIB=config[variant], DTATOOLS_REVIEW_ROOT=config["root"])
            result = subprocess.check_output(["Rscript", "--vanilla", str(directory / "qualify-merge.R"),
                kind, config["merge_directory"], direction], env=env, cwd=config["root"], text=True)
            if expected is None:
                expected = result
            if result != expected:
                raise RuntimeError("Repeated merge signature differs between builds")
            records.append(dict(kind=kind, direction=direction, variant=variant, result=result.strip()))
            print("Qualified repeated merge", kind, direction, variant, flush=True)
(directory / "merge-qualification.json").write_text(json.dumps(records, indent=2) + "\n")
