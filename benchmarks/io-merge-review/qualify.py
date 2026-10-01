"""Untimed full signatures and input preservation checks for measured cases."""
import argparse
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("configuration", type=Path)
parser.add_argument("phase", choices=("inputs", "outputs"))
arguments = parser.parse_args()
config = json.loads(arguments.configuration.read_text())
directory = Path(config["directory"])
worker = Path(__file__).with_name("worker.R")
records = []

def check(key, variant, command):
    env = os.environ.copy()
    env.update(R_LIBS=config[variant], DTATOOLS_BENCH_LIB=config[variant], DTATOOLS_REVIEW_ROOT=config["root"])
    process = subprocess.run(["Rscript", "--vanilla", str(worker)] + command, cwd=config["root"],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    log = directory / ("qualification-" + key + "-" + variant + ".log")
    log.write_text(process.stdout)
    if process.returncode:
        raise RuntimeError(f"Qualification failed: {log}")
    qualified = [line for line in process.stdout.splitlines() if line.startswith(("QUALIFIED\t", "WARNINGS\t"))]
    records.append(dict(key=key, library=variant, records=qualified))
    print("Qualified " + key + " " + variant, flush=True)
    return qualified

if arguments.phase == "inputs":
    for fixture in config["reads"]:
        signatures = []
        for reader, suffix in (("read_dta", "dta"), ("read_arrow", "arrow")):
            results = [check(fixture["id"] + "-" + reader, variant,
                ["qualify-read", reader, fixture[suffix], "unused"]) for variant in ("baseline", "candidate")]
            if results[0] != results[1]:
                raise RuntimeError("Reader baseline/candidate mismatch")
            signatures.append(results[0][0].split("\t")[-1])
        if signatures[0] != signatures[1]:
            raise RuntimeError("DTA/Arrow signature mismatch")
    for kind in ("typed", "ordinary", "one-column"):
        for direction in (("1:m",) if kind == "one-column" else ("1:m", "m:1")):
            key = "merge-" + kind + "-" + direction.replace(":", "")
            results = [check(key, variant, ["qualify-merge", kind, config["merge_directory"], direction])
                       for variant in ("baseline", "candidate")]
            if results[0] != results[1]:
                raise RuntimeError("Merge baseline/candidate mismatch")
else:
    raw = [json.loads(line) for line in (directory / "writes-raw.jsonl").read_text().splitlines()]
    groups = {}
    for row in raw:
        groups.setdefault(row["case"], {}).setdefault(row["variant"], []).append(row)
    for case, variants in groups.items():
        expected = None
        for variant, rows in variants.items():
            rows.sort(key=lambda row: row["pair"])
            for row in (rows[0], rows[-1]):
                reader = "read_dta" if row["method"] == "save_dta" else "read_arrow"
                result = check(f'{case}-{variant}-{row["pair"]}', "baseline",
                    ["qualify-read", reader, row["output"], "unused"])
                if expected is None:
                    expected = result
                if result != expected:
                    raise RuntimeError("Writer first/final baseline/candidate mismatch")
    for fixture in config["writes"]:
        for method in ("save_dta", "save_arrow"):
            for variant in ("baseline", "candidate"):
                key = fixture["id"] + "-" + method + "-preservation"
                output = directory / "outputs" / (key + "-" + variant + (".dta" if method == "save_dta" else ".arrow"))
                check(key, variant, ["qualify-" + method, fixture["kind"], str(fixture["input"]), str(output)])
(directory / (arguments.phase + "-qualification.json")).write_text(json.dumps(records, indent=2) + "\n")
