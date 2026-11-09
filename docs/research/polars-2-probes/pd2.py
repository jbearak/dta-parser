import struct, numpy as np, pandas as pd
NA = 0x7FF00000000007A2
def tagged(c): return struct.unpack("<d", struct.pack("<Q", NA | (ord(c) << 32)))[0]
def tag(v):
    b = struct.unpack("<Q", struct.pack("<d", v))[0]
    if v != v and (b & 0xFFFFFFFF) == 0x7A2 and ((b >> 32) & 0xFF): return "." + chr((b >> 32) & 0xFF)
    return "." if v != v else ("0!" if v == 0 else f"{v:g}")
vals = np.array([1.0, 5000.0, tagged("a"), tagged("b"), np.nan, tagged("a")])
under = lambda s: " ".join(tag(v) for v in pd.Series(s).array._data)
print("expect: 1 5000 .a .b . .a   (0! = a zero written under the mask)")
print(f"{'pd.array(numpy, Float64)':34s}", under(pd.array(vals, dtype="Float64")))
from pandas.arrays import FloatingArray
s = pd.Series(FloatingArray(vals.copy(), np.isnan(vals)), name="x")
print(f"{'FloatingArray(values, mask)':34s}", under(s))
df = pd.DataFrame({"x": s, "g": list("ppqqrr"), "y": [1, 2, 3, 4, 5, 6]})
tests = {
 "-x": lambda: -s, "abs(x)": lambda: s.abs(), "round(x)": lambda: s.round(), "x ** 2": lambda: s ** 2,
 "x + y (other col)": lambda: s + df["y"], "x * NA-free Int64": lambda: s * pd.array([1]*6, dtype="Int64"),
 "astype(float32)->Float64": lambda: s.astype("Float32").astype("Float64"),
 "astype(Int64) (fails?)": lambda: s.astype("Int64"),
 "where(x > 3000, 0)": lambda: s.where(s > 3000, 0),
 "mask(x == 1, 7)": lambda: s.mask(s == 1, 7),
 "loc[y > 5, x] = 9": lambda: (lambda d: (d.__setitem__("x", d["x"].copy()), d.loc.__setitem__((d.y > 5, "x"), 9), d["x"])[2])(df.copy()),
 "shift(1)": lambda: s.shift(1), "reindex": lambda: s.reindex([5, 4, 3, 2, 1, 0]),
 "clip(0, 10)": lambda: s.clip(0, 10), "cumsum": lambda: s.cumsum(),
 "groupby(g).transform('first')": lambda: df.groupby("g")["x"].transform("first"),
 "groupby(g).x.shift()": lambda: df.groupby("g")["x"].shift(),
 "fillna(0) then nothing": lambda: s.fillna(0),
 "combine_first": lambda: s.combine_first(pd.Series([0.0]*6, dtype="Float64")),
 "pd.concat axis=1 + stack": lambda: pd.concat([s, s], axis=1).stack(),
 "to_numpy(na_value=nan) -> Float64": lambda: pd.array(s.to_numpy(dtype=float, na_value=np.nan), dtype="Float64"),
 "pyarrow round trip": None,
 "parquet (pyarrow) round trip": None,
 "copy / deep copy": lambda: s.copy(deep=True),
 "apply(lambda v: v)": lambda: s.apply(lambda v: v),
 "map(lambda v: v)": lambda: s.map(lambda v: v),
}
for k, f in tests.items():
    if f is None: continue
    try: print(f"{k:34s}", under(f()))
    except Exception as e: print(f"{k:34s} error: {type(e).__name__}: {str(e)[:70]}")
print(f"{'count, mean, sum':34s}", s.count(), s.mean(), s.sum())
print(f"{'value_counts(dropna=False)':34s}", s.value_counts(dropna=False).to_dict())
print(f"{'x == x':34s}", (s == s).tolist())
print(f"{'pd.NA in s.isin([..])':34s}", s.isin([1.0]).tolist())
print(f"{'df.query(\"x != 1\") rows':34s}", len(df.query("x != 1")))
