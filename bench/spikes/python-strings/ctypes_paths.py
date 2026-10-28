import time, numpy as np, sys
n = 10_000_000
rng = np.random.default_rng(1)
vals = rng.permutation(n)
# 9-byte values like long.dta's s2 ("id0000001"), contiguous, with u64 offsets
buf = b"".join(b"id%07d" % v for v in vals)
offs = np.arange(0, 9 * n + 1, 9, dtype=np.uint64)
def t(label, f):
    t0 = time.perf_counter(); r = f(); dt = time.perf_counter() - t0
    assert r[5] == "id%07d" % vals[5], (label, r[5]); print(f"{label}: {dt:.2f} s"); return r
mv = memoryview(buf); o = offs.tolist()
t("loop decode", lambda: [str(mv[o[i]:o[i+1]], "utf-8") for i in range(n)])
t("whole decode + slice (ascii)", lambda: (lambda s: [s[o[i]:o[i+1]] for i in range(n)])(buf.decode()))
arr = np.frombuffer(buf, dtype="S9")
t("numpy S fixed -> decode -> tolist", lambda: np.char.decode(arr, "utf-8").tolist())
t("numpy S -> astype(U) -> tolist", lambda: arr.astype("U9").tolist())
