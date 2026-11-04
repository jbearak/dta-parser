# Write Parquet fixtures with Parquet2.jl, from data made here, into
# compat/parquet/fixtures/. Then run expected.py, which records what
# pyarrow reads from them.
#
# Run from the repository root, in a Julia environment with Parquet2,
# DataFrames and DecFP:
#
#     julia --project=SOME_ENV compat/parquet/make_fixtures.jl
#
# Parquet2 writes PLAIN and dictionary pages (v1), one page per column
# by default; these files cover its types (unsigned integers, Time,
# DateTime, decimals from DecFP, bytes) with missing values, snappy,
# zstd and brotli, and several pages.

using Dates
using DataFrames
using DecFP
using Parquet2

const OUT = joinpath(@__DIR__, "fixtures")
const N = 600

masked(v, every, offset=3) = [i % every == offset ? missing : x for (i, x) in zip(0:N-1, v)]

function table()
    r = 0:N-1
    DataFrame(
        i8=masked(Int8.(r .% 250 .- 125), 10),
        i32=masked(Int32.(r .* 700_001 .- 1_000_000_000), 12),
        i64=masked(Int64.(r .* 3_000_000_000_017 .- 5), 13),
        u8=masked(UInt8.(r .% 256), 11),
        u16=masked(UInt16.((r .* 109) .% 65536), 14),
        u32=masked(UInt32.((r .* 7_158_271) .% 4_294_967_296), 15),
        u64=masked([UInt64(i) * 0x006d36b1ef8a2c25 for i in r], 16),
        f32=masked(Float32.(r .* 0.25 .- 50), 17),
        f64=masked(r ./ 7, 18),
        flag=masked(r .% 3 .== 0, 19),
        word=masked(["word $(i % 40) ü" for i in r], 20),
        blob=masked([UInt8[i % 256, 7, 0] for i in r], 21),
        day=masked([Date(1960, 1, 1) + Day(9i) for i in r], 22),
        stamp=masked([DateTime(2020, 1, 1) + Millisecond(61_001i) for i in r], 23),
        clock=masked([Time(0) + Nanosecond(143_999_999_999i % 86_400_000_000_000) for i in r], 24),
        dec=masked([Dec64(i * 1237 - 300_000) / 100 for i in r], 25),
    )
end

function main()
    t = table()
    Parquet2.writefile(joinpath(OUT, "parquet2_default.parquet"), t)
    Parquet2.writefile(joinpath(OUT, "parquet2_zstd_pages.parquet"), t; compression_codec=:zstd, npages=7)
    Parquet2.writefile(joinpath(OUT, "parquet2_brotli.parquet"), t; compression_codec=:brotli, npages=3)
    println("Parquet2 ", pkgversion(Parquet2), ", Julia ", VERSION)
end

main()
