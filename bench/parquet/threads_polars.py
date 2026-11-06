"""Plan 0019 PR 2a, step 3: the Arrow path's reads and writes at fixed
thread counts (DTA_THREADS) against polars, to choose its thread rule
(bench/RESULTS.md, "Threads for polars"). Fresh processes, medians of
RUNS runs, the benchmark lock held throughout; appends JSON lines to OUT.

    threads_polars.py FILES TASKS THREADS RUNS OUT
    e.g. threads_polars.py dhs-tajikistan-2017-wm,nsfg-2002_FemResp,long,groups \
         full,window,five,write 1,2,4,8,12,16 3 threads.jsonl

FILES are keys of the Parquet copies run_polars.py prepares (DATA below)."""
import tempfile
import json, os, re, statistics, subprocess, sys, time
from pathlib import Path
import pyarrow.parquet as pq
ROOT = Path(__file__).resolve().parents[2]
DATA = "/private/tmp/claude-501/pq-bench"
CASE = ROOT / "bench/parquet/case_polars.py"
LOCK = Path("/tmp/claude-501/bench.lock")
FILES = sys.argv[1].split(",")
TASKS = sys.argv[2].split(",")
THREADS = [int(x) for x in sys.argv[3].split(",")]
RUNS = int(sys.argv[4])
OUT = Path(sys.argv[5])
WRITERS = ["ours", "pyarrow", "polars"]
def lock():
    while True:
        try:
            LOCK.mkdir(); (LOCK / "owner").write_text(f"bench/parquet/threads_polars.py, pid {os.getpid()}\n"); return
        except FileExistsError:
            time.sleep(15)
def unlock():
    (LOCK / "owner").unlink(missing_ok=True); LOCK.rmdir()
rep = str(Path(tempfile.mkdtemp()) / "case.json")
def one(lib, task, p, cols, skip, n, env):
    runs = []
    for _ in range(RUNS):
        r = subprocess.run(["/usr/bin/time", "-l", sys.executable, str(CASE), lib, task, p, rep, cols, str(skip), str(n)],
                           capture_output=True, text=True, env=env)
        if r.returncode:
            return {"error": r.stderr[-500:]}
        d = json.load(open(rep)); d["rss"] = int(re.search(r"(\d+)\s+maximum resident", r.stderr).group(1)) / 1e6
        d["load"] = os.getloadavg()[0]; runs.append(d)
    return {k: statistics.median(r[k] for r in runs) for k in ("wall", "cpu", "rss", "load")}
lock()
try:
    with open(OUT, "a") as out:
        for f in FILES:
            md = pq.ParquetFile(f"{DATA}/ours/{f}.parquet").metadata
            names = [md.schema.column(i).name for i in range(md.num_columns)]
            cols = ",".join(names[i] for i in sorted({round(k * (len(names) - 1) / 4) for k in range(5)}))
            skip = md.num_rows // 2; n = min(1000, md.num_rows - skip)
            for task in TASKS:
                writers = ["ours"] if task in ("write", "zstd") else WRITERS
                for w in writers:
                    p = f"{DATA}/{w}/{f}.parquet"
                    base = one("polars", task, p, cols, skip, n, dict(os.environ))
                    out.write(json.dumps({"file": f, "writer": w, "task": task, "lib": "polars", **base}) + "\n"); out.flush()
                    for t in THREADS:
                        r = one("ours", task, p, cols, skip, n, dict(os.environ, DTA_THREADS=str(t)))
                        out.write(json.dumps({"file": f, "writer": w, "task": task, "lib": "ours", "threads": t, **r}) + "\n"); out.flush()
                        print(f, w, task, t, r, flush=True)
finally:
    unlock()
