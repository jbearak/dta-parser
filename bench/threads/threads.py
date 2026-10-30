"""Wall and CPU time of one task in Python, with 1 to 4 threads and the
default (plan 0007): the median of five runs, CPU from resource.getrusage.

    python bench/threads/threads.py FILE.dta [read|columns|write] ...

The thread count is set through DTA_THREADS, which the core reads at
each call.
"""

import gc
import os
import resource
import statistics
import sys
import tempfile
import time

import dta_parser as dp


def cpu():
    r = resource.getrusage(resource.RUSAGE_SELF)
    return r.ru_utime, r.ru_stime


def main():
    path, tasks = sys.argv[1], sys.argv[2:]
    out = os.path.join(tempfile.mkdtemp(), "out.dta")
    data = dp.read_dta(path) if "write" in tasks else None
    first5 = list(dp.read_dta(path, n_max=0).columns[:5]) if "columns" in tasks else None
    run = {
        "read": lambda: dp.read_dta(path),
        "columns": lambda: dp.read_dta(path, columns=first5),
        "write": lambda: dp.write_dta(data, out),
    }
    for task in tasks:
        print(path, task)
        print("threads  wall s  user s  sys s  cpu/1-thread  speedup")
        base = None
        for threads in ["1", "2", "3", "4", None]:
            if threads is None:
                os.environ.pop("DTA_THREADS", None)
            else:
                os.environ["DTA_THREADS"] = threads
            runs = []
            for _ in range(5):
                gc.collect()
                u0, s0 = cpu()
                t = time.perf_counter()
                result = run[task]()
                wall = time.perf_counter() - t
                u1, s1 = cpu()
                del result
                runs.append((wall, u1 - u0, s1 - s0))
            wall, user, sys_ = sorted(runs)[2]
            if base is None:
                base = (wall, user + sys_)
            print(f"{threads or 'default':>7}  {wall:6.3f}  {user:6.3f}  {sys_:5.3f}  {(user + sys_) / base[1]:12.2f}  {base[0] / wall:7.2f}")


if __name__ == "__main__":
    main()
