"""Python's Parquet reads and writes at 1 to 16 threads (plan 0018,
"Threads"), to set Python's default by plan 0007's rule: CPU time at
most 1.15 times one thread's, and each thread added at least half
efficient. The Python counterpart of threads.R.

    python bench/parquet/threads_py.py DATA_DIR OUT.json KEY ...

For each KEY, reads DATA_DIR/ours/KEY.parquet whole and five columns of
it, and writes what it read, with DTA_THREADS set to each count. Each
case runs once to warm up, then nine times; the median wall and CPU
(user plus system) time are kept, with the one-minute load average.
THREAD_COUNTS (default 1,2,3,4,6,8,12,16), THREAD_RUNS (9) and
THREAD_TASKS (read,five,write) narrow a run. Run it holding the
benchmark lock.
"""

import gc
import json
import os
import resource
import statistics
import sys
import tempfile
import time

import dta_parser as dp


def env(name, default):
    return os.environ.get(name, default).split(",")


def cpu():
    r = resource.getrusage(resource.RUSAGE_SELF)
    return r.ru_utime + r.ru_stime


def time_it(f, runs):
    f()
    walls, cpus = [], []
    for _ in range(runs):
        gc.collect()
        t0, c0 = time.perf_counter(), cpu()
        f()
        walls.append(time.perf_counter() - t0)
        cpus.append(cpu() - c0)
    return statistics.median(walls), statistics.median(cpus)


def main():
    data_dir, out, keys = sys.argv[1], sys.argv[2], sys.argv[3:]
    counts = [int(n) for n in env("THREAD_COUNTS", "1,2,3,4,6,8,12,16")]
    runs = int(env("THREAD_RUNS", "9")[0])
    tasks = env("THREAD_TASKS", "read,five,write")
    results = []
    for key in keys:
        p = os.path.join(data_dir, "ours", key + ".parquet")
        names = list(dp.read_meta(p)["columns"])
        n = len(names)
        # As threads.R: seq(1, n, length.out = 5), rounded, 1-based.
        five = list(dict.fromkeys(names[round(1 + (n - 1) * i / 4) - 1] for i in range(5)))
        os.environ["DTA_THREADS"] = "1"
        data = dp.read_parquet(p) if "write" in tasks else None
        dst = os.path.join(tempfile.gettempdir(), f"threads{os.getpid()}.parquet")
        for count in counts:
            os.environ["DTA_THREADS"] = str(count)
            for task in tasks:
                f = {
                    "read": lambda: dp.read_parquet(p),
                    "five": lambda: dp.read_parquet(p, columns=five),
                    "write": lambda: dp.write_parquet(data, dst),
                }[task]
                wall, used = time_it(f, runs)
                results.append({"key": key, "task": task, "threads": count, "wall": wall, "cpu": used,
                                "load": os.getloadavg()[0]})
                print(f"{key:26} {task:5} {count:2} threads: {wall:.3f} s wall, {used:.3f} s CPU", flush=True)
        if os.path.exists(dst):
            os.unlink(dst)
        del data
        gc.collect()
    del os.environ["DTA_THREADS"]
    with open(out, "w") as f:
        json.dump(results, f, indent=1)


if __name__ == "__main__":
    main()
