"""Exercise actual R qualification policies on tiny deterministic DTA/Arrow files."""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("reader_smoke_run", HERE / "run.py")
RUN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUN)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("baseline", "candidate", "work"):
        parser.add_argument("--" + name, type=lambda value: Path(value).resolve(), required=True)
    args = parser.parse_args()
    if args.baseline == args.candidate:
        parser.error("Use independently installed libraries")
    rscript = shutil.which("Rscript")
    if rscript is None:
        parser.error("Rscript is unavailable")
    args.work.mkdir(parents=True, exist_ok=False, mode=0o700)
    prepare = args.work / "prepare.R"
    prepare.write_text('''args <- commandArgs(TRUE)
.libPaths(c(Sys.getenv("DTATOOLS_BENCH_LIB"), .libPaths()))
value <- data.frame(count = c(-1L, 0L, 100L, NA_integer_),
    measure = c(-0.5, 0, 1.25, NA_real_), category = c("a", "bb", "ccc", "dddd"))
saveRDS(value, file.path(args[[1L]], "reference.rds"), version = 3L)
dtatools::save_dta(value, file.path(args[[1L]], "tiny.dta"), version = 19L)
imported <- dtatools::read_dta(file.path(args[[1L]], "tiny.dta"), output = "tibble")
dtatools::save_arrow(imported, file.path(args[[1L]], "tiny.arrow"),
    compression = "uncompressed", checksums = TRUE)
''')
    subprocess.run([rscript, "--vanilla", str(prepare), str(args.work)],
        env=RUN.environment(args.baseline), check=True)
    base_fixture = dict(id="tiny", rows=4, columns=3,
        dta=str(args.work / "tiny.dta"), arrow=str(args.work / "tiny.arrow"))
    outputs = {}
    methods = [name for name in RUN.METHODS if name.startswith("dtatools_")]
    for name, kind, modes in (("signature-read", "signature", ["read"]),
            ("signature-consume", "signature", ["read", "consume"]),
            ("values-read", "values", ["read"])):
        fixture = dict(base_fixture, qualification=kind)
        if kind == "values":
            fixture["reference"] = str(args.work / "reference.rds")
        manifest = args.work / (name + ".json")
        manifest.write_text(json.dumps(dict(reads=[fixture])) + "\n")
        work = args.work / name
        subprocess.run([sys.executable, str(HERE / "run.py"),
            "--baseline", str(args.baseline), "--candidate", str(args.candidate),
            "--fixtures", str(manifest), "--work", str(work),
            "--methods", *methods, "--threads", "1", "0", "--modes", *modes,
            "--qualify-only"], check=True)
        records = json.loads((work / "qualification.json").read_text())
        flat = [record for variants in records.values() for record in variants.values()]
        if len(flat) != 16:
            raise RuntimeError("Incomplete smoke method/library/thread matrix")
        omit = name == "signature-read"
        for record in flat:
            if record["consumption"] != ("omitted_read_only" if omit else "complete"):
                raise RuntimeError("Wrong smoke qualification policy")
            if (record["consumption_sha256"] is None) != omit:
                raise RuntimeError("Wrong smoke consumption hash presence")
        outputs[name] = flat
    signatures = {record["signature"] for records in outputs.values() for record in records}
    consumed = {record["consumption_sha256"] for records in outputs.values() for record in records
                if record["consumption_sha256"] is not None}
    if len(signatures) != 1 or len(consumed) != 1:
        raise RuntimeError("Smoke qualification results differ across policies")
    print("Passed: 48 fresh R qualifications; signature-only read, signature consume, and values read")


if __name__ == "__main__":
    main()
