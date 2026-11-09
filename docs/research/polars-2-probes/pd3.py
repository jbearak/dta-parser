import struct, numpy as np, pandas as pd
from pandas.arrays import FloatingArray
NA = 0x7FF00000000007A2
def tagged(c): return struct.unpack("<d", struct.pack("<Q", NA | (ord(c) << 32)))[0]
def tag(v):
    b = struct.unpack("<Q", struct.pack("<d", v))[0]
    if v != v and (b & 0xFFFFFFFF) == 0x7A2 and ((b >> 32) & 0xFF): return "." + chr((b >> 32) & 0xFF)
    return "." if v != v else f"{v:g}"
vals = np.array([1.0, 5000.0, tagged("a"), tagged("b"), np.nan, tagged("a")])
def fresh(): return pd.Series(FloatingArray(vals.copy(), np.isnan(vals)), name="x")
under = lambda s: " ".join(tag(v) for v in pd.Series(s).array._data)
masked = lambda s: " ".join("M" if m else "-" for m in pd.Series(s).array._mask)
ops = {
 "fillna(0)": lambda s: s.fillna(0), "where(x > 3000, 0)": lambda s: s.where(s > 3000, 0),
 "mask(x == 1, 7)": lambda s: s.mask(s == 1, 7), "combine_first": lambda s: s.combine_first(pd.Series([0.0]*6, dtype="Float64")),
 "copy(deep=True)": lambda s: s.copy(deep=True), "astype(Int64)": lambda s: s.astype("Int64"),
 "groupby.transform(first)": lambda s: s.groupby([0,0,1,1,2,2]).transform("first"),
 "apply(identity)": lambda s: s.apply(lambda v: v), "cumsum": lambda s: s.cumsum(),
 "to_frame().copy()": lambda s: s.to_frame().copy()["x"], "s.iloc[2:4]": lambda s: s.iloc[2:4],
 "pd.DataFrame({'x': s})": lambda s: pd.DataFrame({"x": s})["x"],
}
print(f"{'source as made':26s} data: {under(fresh())}   mask: {masked(fresh())}")
for k, f in ops.items():
    s = fresh(); r = f(s)
    print(f"{k:26s} result data: {under(r):26s} mask: {masked(r):12s} | source after: {under(s)}")
