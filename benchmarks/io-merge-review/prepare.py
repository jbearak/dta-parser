"""Prepare current-profile Arrow inputs and the published merge workload."""
import json
import os
from pathlib import Path
import subprocess

directory = Path(__file__).parent
config = json.loads((directory / "configuration.json").read_text())
env = os.environ.copy()
env.update(R_LIBS=config["baseline"], DTATOOLS_BENCH_LIB=config["baseline"],
           DTATOOLS_REVIEW_ROOT=config["root"])
for fixture in config["reads"]:
    command = ["Rscript", "--vanilla", str(directory / "worker.R"), "prepare-arrow", fixture["id"], fixture["dta"], fixture["arrow"]]
    with (directory / ("prepare-" + fixture["id"] + ".log")).open("w") as stream:
        subprocess.run(command, env=env, cwd=config["root"], stdout=stream, stderr=subprocess.STDOUT, check=True)
    print("Prepared " + fixture["id"], flush=True)
with (directory / "prepare-merge.log").open("w") as stream:
    subprocess.run(["Rscript", "--vanilla", str(directory / "prepare-merge.R"), config["merge_directory"]],
                   env=env, cwd=config["root"], stdout=stream, stderr=subprocess.STDOUT, check=True)
print("Prepared merge fixtures", flush=True)
