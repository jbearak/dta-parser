import struct, numpy as np, pandas as pd
from pandas.arrays import FloatingArray
print("pandas", pd.__version__, "numpy", np.__version__)
NA = 0x7FF00000000007A2
def tagged(c): return struct.unpack("<d", struct.pack("<Q", NA | (ord(c) << 32)))[0]
def tag(v):
    b = struct.unpack("<Q", struct.pack("<d", v))[0]
    if v != v and (b & 0xFFFFFFFF) == 0x7A2 and ((b >> 32) & 0xFF): return "." + chr((b >> 32) & 0xFF)
    return "." if v != v else f"{v:g}"
rows = "1, 5000, .a, .b, ., .a"
vals = np.array([1.0, 5000.0, tagged("a"), tagged("b"), np.nan, tagged("a")])
print("rows:", rows)
print("== numpy float64 column ==")
s = pd.Series(vals, name="x")
for k, r in {"isna": s.isna(), "x == 1": s == 1, "x != 1": s != 1, "x > 3000": s > 3000}.items(): print(f"  {k:24s}", r.tolist())
print("  count, mean            ", s.count(), s.mean())
print("  df[x != 1] rows        ", len(s[s != 1]))
df = pd.DataFrame({"x": s, "w": 1})
print("  groupby(dropna=False)  ", df.groupby("x", dropna=False).size().to_dict())
print("  unique                 ", [tag(v) for v in s.unique()])
print("  sort_values keeps tags ", [tag(v) for v in s.sort_values()])
print("  s * 2 keeps tags       ", [tag(v) for v in (s * 2)])
print("== nullable Float64 from the same values ==")
f = pd.array(vals, dtype="Float64")
print("  isna                   ", pd.isna(f).tolist(), " (NaN read as NA?)")
print("  x == 1                 ", (f == 1).tolist())
print("== FloatingArray, letters' bits under the mask ==")
mask = np.isnan(vals)
fa = FloatingArray(vals.copy(), mask.copy())
print("  x == 1                 ", (fa == 1).tolist())
print("  x != 1                 ", (fa != 1).tolist())
print("  x > 3000               ", (fa > 3000).tolist())
ps = pd.Series(fa)
print("  s[x != 1] rows         ", len(ps[ps != 1]))
under = lambda a: [tag(v) for v in a._data]
print("  bits as made           ", under(fa))
print("  after take([5,2,0])    ", under(fa.take([5, 2, 0])))
print("  after filter           ", under(ps[ps.index > 0].array))
print("  after sort_values      ", under(ps.sort_values().array))
print("  after concat           ", under(pd.concat([ps, ps]).array))
print("  after x * 2            ", under((ps * 2).array))
print("  after x + 0            ", under((ps + 0).array))
d2 = pd.DataFrame({"x": ps, "g": list("pqrstu")})
print("  after merge            ", under(d2.merge(pd.DataFrame({"g": list("utsrqp")}), on="g")["x"].array))
print("  groupby(dropna=False)  ", d2.groupby("x", dropna=False).size().to_dict())
