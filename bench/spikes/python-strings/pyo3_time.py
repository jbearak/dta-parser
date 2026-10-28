import time, numpy as np, pyo3s
n = 10_000_000
vals = np.random.default_rng(1).permutation(n)
buf = b"".join(b"id%07d" % v for v in vals)
offs = list(range(0, 9 * n + 1, 9))
t0 = time.perf_counter(); r = pyo3s.strings(buf, offs); dt = time.perf_counter() - t0
assert r[5] == "id%07d" % vals[5]; print(f"pyo3 (incl. offsets list conversion): {dt:.2f} s")
