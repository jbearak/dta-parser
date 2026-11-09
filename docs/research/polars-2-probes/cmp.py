import struct, polars as pl
print("polars", pl.__version__)
NA = 0x7FF00000000007A2
def tagged(c): return struct.unpack("<d", struct.pack("<Q", NA | (ord(c) << 32)))[0]
df = pl.DataFrame({"x": pl.Series([1.0, 5000.0, tagged("a"), tagged("b"), None], dtype=pl.Float64)})
rows = "1, 5000, .a, .b, ."
a = pl.lit(tagged("a"), pl.Float64)
exprs = {
 "x == 1": pl.col("x") == 1, "x != 1": pl.col("x") != 1, "!(x == 1)": ~(pl.col("x") == 1),
 "x > 3000": pl.col("x") > 3000, "x < 3000": pl.col("x") < 3000,
 "x == .a": pl.col("x") == a, "x.is_in([.a])": pl.col("x").is_in(pl.Series([tagged("a")])),
 "when(x>3000) 'hi' else 'lo'": pl.when(pl.col("x") > 3000).then(pl.lit("hi")).otherwise(pl.lit("lo")),
 "x.fill_nan(None) > 3000": pl.col("x").fill_nan(None) > 3000,
 "x.fill_nan(None) != 1": pl.col("x").fill_nan(None) != 1,
}
print(f"rows: {rows}")
for k, e in exprs.items(): print(f"{k:30s}", df.select(e.alias("r"))["r"].to_list())
print(f"{'filter(x != 1) rows':30s}", df.filter(pl.col("x") != 1).height)
print(f"{'sum(x > 3000)':30s}", df.select((pl.col("x") > 3000).sum())[0, 0])
print(f"{'x.max()':30s}", df.select(pl.col("x").max())[0, 0], " sort:", df.sort("x")["x"].to_list())
