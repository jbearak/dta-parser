# Parquet2.jl reads the files DtaParser's write_parquet writes: every
# type DtaParser writes, with nulls, .a to .z, categoricals and a zone,
# in each codec, in one row group and in many. Values are checked
# against what was written, as Parquet2 sees them: .a to .z are NaN with
# the tagged bits (it keeps NaN payloads), a categorical is its text, a
# zoned time is its UTC DateTime, and the dta profile is a key-value
# entry it hands over without reading.
#
# Run from the repository root, in bench/julia's environment (it has
# DtaParser, Parquet2, CategoricalArrays and TimeZones):
#
#     julia --project=bench/julia compat/parquet/readback.jl
#
# Exits with status 1 if any check fails.

using CategoricalArrays, DataFrames, Dates, DtaParser, Parquet2, TimeZones

const N = 1_000
masked(v, every) = [i % every == 3 ? missing : x for (i, x) in zip(0:length(v)-1, v)]

function table()
    r = 0:N-1
    letters = UInt8[i % 7 == 1 ? 2 + i % 26 : i % 7 == 3 ? 1 : 0 for i in r]
    (
        byte = masked(Int8.(r .% 200 .- 100), 10),
        int = masked(Int16.(r .* 31 .- 9000), 11),
        long = masked(Int32.(r .* 70_001 .- 1_000_000), 12),
        big = masked(Int64.(r) .* 3_000_000_000_017 .- 5, 13),
        float = masked(Float32.(r .* 0.25 .- 50), 14),
        double = masked([i % 50 == 7 ? NaN : i / 7 for i in r], 15),
        flag = masked(r .% 3 .== 0, 16),
        word = masked(["word $(i % 40) é" for i in r], 17),
        unique = ["value $i" for i in r],
        blob = masked([UInt8[i % 256, 7, 0] for i in r], 18),
        day = masked([Date(1960) + Day(9i) for i in r], 19),
        clock = masked([DateTime(2020) + Millisecond(61_001i) for i in r], 20),
        # .a to .z in a byte column and a double column.
        tagged = DtaColumn(Int8.(r .% 100), letters),
        tagged_double = DtaColumn(Float64.(r) ./ 3, letters),
        region = categorical(masked([("North", "South", "East")[i%3+1] for i in r], 21); levels=["South", "North", "East", "West"]),
        size = categorical([("lo", "hi")[i%2+1] for i in r]; levels=["lo", "hi"], ordered=true),
        zoned = masked([ZonedDateTime(DateTime(2024, 3, 10) + Minute(7i), tz"America/New_York"; from_utc=true) for i in r], 22),
    )
end

failures = String[]
checked = Ref(0)
fail(file, what) = push!(failures, "$file: $what")

# What Parquet2 should give for row i of column `name`, from the value
# written.
function seen(t, name, i)
    x = t[name]
    if x isa DtaColumn
        c = stata_code(x, i)
        c == 0x00 && return Float64(x.values[i])
        c == 0x01 && return missing
        # A tagged NaN: R's NA_real_ with the letter in bits 32 to 39.
        return reinterpret(Float64, 0x7ff00000000007a2 | (UInt64('a' + c - 2) << 32))
    end
    v = x[i]
    ismissing(v) && return missing
    v isa CategoricalValue && return String(unwrap(v))
    v isa ZonedDateTime && return DateTime(v, UTC)
    v
end

function same(want, got)
    ismissing(want) && return ismissing(got)
    ismissing(got) && return false
    if want isa Float64 && isnan(want)
        return got isa AbstractFloat && reinterpret(UInt64, Float64(got)) == reinterpret(UInt64, want)
    end
    want isa AbstractVector && return collect(got) == want
    want == got
end

function check(file, t)
    ds = Parquet2.Dataset(file)
    d = DataFrame(ds; copycols=true)
    kv = Parquet2.metadata(ds)
    haskey(kv, "dta") || fail(file, "the dta key is not in the file's metadata")
    nrow(d) == N || fail(file, "$(nrow(d)) rows, not $N")
    for name in keys(t)
        hasproperty(d, name) || (fail(file, "no column $name"); continue)
        got = d[!, name]
        for i in 1:N
            want = seen(t, name, i)
            if !same(want, got[i])
                fail(file, "$name row $i is $(repr(got[i])), not $(repr(want))")
                break
            end
        end
        checked[] += 1
    end
    # Parquet's own types, as Parquet2 maps them.
    for (name, T) in ((:byte, Int8), (:int, Int16), (:long, Int32), (:big, Int64), (:float, Float32), (:double, Float64),
                      (:flag, Bool), (:day, Date), (:clock, DateTime), (:tagged, Float64))
        S = nonmissingtype(eltype(d[!, name]))
        S == T || fail(file, "$name is $S, not $T")
    end
end

t = table()
dir = mktempdir()
for (codec, rows) in ((:snappy, nothing), (:zstd, nothing), (:gzip, nothing), (:none, nothing), (:snappy, 100))
    file = joinpath(dir, "$(codec)$(rows === nothing ? "" : "_rows$rows").parquet")
    write_parquet(file, t; compression=codec, row_group_size=rows, label="Readback",
                  value_labels=Dict("yn" => Dict(0 => "No", 1 => "Yes", ".a" => "Refused")),
                  column_value_labels=Dict(:tagged => "yn"), column_labels=Dict(:word => "A word"))
    check(file, t)
end

println("Parquet2 ", pkgversion(Parquet2), ", DtaParser ", pkgversion(DtaParser), ": ", checked[], " columns checked")
if isempty(failures)
    println("every check passes")
else
    foreach(println, failures)
    exit(1)
end
