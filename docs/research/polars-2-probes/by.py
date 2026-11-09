import struct, polars as pl
print("polars", pl.__version__)
NA = 0x7FF00000000007A2
def tagged(c): return struct.unpack("<d", struct.pack("<Q", NA | (ord(c) << 32)))[0]
x = pl.Series("x", [1.0, tagged("a"), tagged("b"), None, tagged("a"), 2.0, tagged("b")], pl.Float64)
df = pl.DataFrame({"x": x})
print("plain group_by groups:", df.group_by("x").len().height)
# key: bits 32-39 (the letter) where x is NaN, else null; sign and quiet bit ignored
letter = pl.when(pl.col("x").is_nan()).then((pl.col("x").reinterpret(dtype=pl.UInt64) // (1 << 32)) % 256).alias("x_letter")
g = df.group_by("x", letter, maintain_order=True).len()
print("group_by(x, letter) groups:", g.height); print(g)
neg = df.with_columns(-pl.col("x") * 2)
print("after -x*2, groups:", neg.group_by("x", letter).len().height)
