# Files going between the languages' datakits (plan 0019, "Across
# languages"). Julia's half:
#
#     julia --project=bench/julia compat/parquet/cross_language.jl check DIR   # reads DIR/from_r.parquet
#     julia --project=bench/julia compat/parquet/cross_language.jl write DIR   # writes DIR/from_julia.parquet
#
# compat/parquet/cross_language.sh runs both halves of each language in
# turn. The values are the literal data cross_language.R uses, so each
# side checks the other's file cell by cell: the value, the missing code
# (`.` or which of `.a` to `.z`), and the labels, formats and value
# labels. bench/julia's environment has Datakit, CategoricalArrays and
# TimeZones. Exits with status 1 if a check fails.

using CategoricalArrays, DataFrames, Dates, Datakit, TimeZones

const MODE, DIR = ARGS[1], ARGS[2]
mkpath(DIR)

codes(c) = UInt8[stata_code(c, i) for i in eachindex(c)]
const L = stata_key   # value label keys: L(".a")

if MODE == "write"
    df = DataFrame(
        id = Int32.(1:6),
        score = DtaColumn([1.5, 0, 0, -2.25, 0, 2.0^1000], UInt8[0, 1, 2, 0, 27, 0]),
        small = DtaColumn(Int8[1, 0, 0, 100, -127, 0], UInt8[0, 0, 5, 0, 0, 1]),
        long = DtaColumn(Int32[2147483620, -2147483647, 0, 0, 0, 7], UInt8[0, 0, 3, 0, 1, 0]),
        fl = DtaColumn(Float32[0.5, 0, 3.25, 0, -1, 2], UInt8[0, 4, 0, 1, 0, 0]),
        count = Union{Missing,Int32}[3, missing, 0, -5, 2147483647, 1],
        word = ["a", missing, "", "été", "x y", "z"],
        region = categorical(["N", "S", missing, "N", "E", "S"]; levels = ["S", "N", "E", "W"]),
        day = [Date(2024, 3, 1), missing, Date(1960), Date(1900, 2, 28), Date(2100, 12, 31), Date(1970)],
        when = [ismissing(ms) ? missing : ZonedDateTime(DateTime(1970) + Millisecond(ms), tz"America/New_York"; from_utc = true)
                for ms in (0, 1_709_285_400_250, missing, -1000, 86_400_000, 1_000_000_000_000)],
        # A date column holding letters, as Julia holds one: Stata's days
        # since 1960 with %td.
        seen = DtaColumn([23436.0, 0, 23437, 0, 0, 0], UInt8[0, 5, 0, 1, 0, 27]),
    )
    save_parquet(joinpath(DIR, "from_julia.parquet"), df;
                 label = "From Julia", notes = ["A note from Julia."],
                 value_labels = Dict("scorelab" => Dict(1.5 => "Low", ".a" => "Refused", ".z" => "Other"),
                                     "yn" => Dict(0 => "No", 1 => "Yes", ".d" => "Don't know")),
                 column_labels = Dict(:score => "A score", :long => "A long", :count => "A count"),
                 column_formats = Dict(:score => "%9.2f", :day => "%tdCCYY-NN-DD", :seen => "%td"),
                 column_value_labels = Dict(:score => "scorelab", :small => "yn"))
    println("Julia wrote ", joinpath(DIR, "from_julia.parquet"))
    exit(0)
end

MODE == "check" || error("the mode is check or write, not $MODE")
failures = String[]
checked = Ref(0)
function check(ok, what)
    checked[] += 1
    ok || push!(failures, what)
end

# Every row: the same missing code, and the same value where there is none.
function cells(x, want_values, want_codes, name)
    check(length(x) == length(want_codes), "$name: length")
    got = codes(x)
    for i in eachindex(want_codes)
        check(got[i] == want_codes[i], "$name row $i: code $(got[i]), not $(want_codes[i])")
        want_codes[i] == 0 && check(isequal(x[i], want_values[i]), "$name row $i: $(x[i]), not $(want_values[i])")
    end
end

path = joinpath(DIR, "from_r.parquet")
# The POSIXct that no whole number of milliseconds gives back is an error
# by default, naming the column, the row and the option.
err = try read_parquet(path) catch e e end
check(err isa Exception && occursin("column \"whenfrac\": row 1 is 1.0000001 seconds", sprint(showerror, err)) &&
      occursin("timestamps = :truncate", sprint(showerror, err)), "whenfrac: the error")
df = read_parquet(path; timestamps = :truncate)

check(metadata(df, "label") == "From R", "data label")
check(metadata(df, "notes") == ["First note.", "Second note."], "notes")
check(df.id == 1:6 && df.id isa Vector{Int32}, "id")

check(df.score isa DtaColumn{Float64}, "score: type")
cells(df.score, [1.5, 0, 0, -2.25, 0, 2.0^1000], [0, 1, 2, 0, 27, 0], "score")
check(colmetadata(df, :score, "label") == "A score", "score: label")
check(colmetadata(df, :score, "format") == "%9.2f", "score: format")
check(colmetadata(df, :score, "value_labels") == "scorelab", "score: set")
check(metadata(df, "value_labels")["scorelab"] == Dict(1.5 => "Low", L(".a") => "Refused", L(".z") => "Other"),
      "score: labels")

check(df.small isa DtaColumn{Int8}, "small: type (storage byte)")
cells(df.small, [1, 0, 0, 100, -127, 0], [0, 0, 5, 0, 0, 1], "small")
check(colmetadata(df, :small, "storage") == "byte", "small: storage")
check(metadata(df, "value_labels")[colmetadata(df, :small, "value_labels")] ==
      Dict(0.0 => "No", 1.0 => "Yes", L(".d") => "Don't know"), "small: labels")

# The long column with letters.
check(df.long isa DtaColumn{Int32}, "long: type (storage long)")
cells(df.long, [2147483620, -2147483647, 0, 0, 0, 7], [0, 0, 3, 0, 1, 0], "long")
check(colmetadata(df, :long, "label") == "A long", "long: label")

check(df.fl isa DtaColumn{Float32}, "fl: type (storage float)")
cells(df.fl, Float32[0.5, 0, 3.25, 0, -1, 2], [0, 4, 0, 1, 0, 0], "fl")

check(df.count isa Vector{Union{Missing,Int32}}, "count: type")
cells(df.count, [3, 0, 0, -5, 2147483647, 1], [0, 1, 0, 0, 0, 0], "count")
check(colmetadata(df, :count, "label") == "A count", "count: label")

check(isequal(df.word, ["a", missing, "", "été", "x y", "z"]), "word")
check(df.region isa CategoricalArray && levels(df.region) == ["S", "N", "E", "W"] && !isordered(df.region), "region: levels")
check(isequal(collect(passmissing(String).(df.region)), ["N", "S", missing, "N", "E", "S"]), "region: values")
check(isequal(df.day, [Date(2024, 3, 1), missing, Date(1960), Date(1900, 2, 28), Date(2100, 12, 31), Date(1970)]), "day")
check(colmetadata(df, :day, "format") == "%tdCCYY-NN-DD", "day: format")
utc_ms(t) = ismissing(t) ? missing : Dates.value(DateTime(t, UTC) - DateTime(1970))
check(all(t -> ismissing(t) || timezone(t) == tz"America/New_York", df.when), "when: zone")
check(isequal(utc_ms.(df.when), [0, 1_709_285_400_250, missing, -1000, 86_400_000, 1_000_000_000_000]), "when: instants")

# The Date with a fraction of a day: Stata's days since 1960 with %td,
# exactly.
check(df.dayfrac isa Vector{Union{Missing,Float64}}, "dayfrac: type")
cells(df.dayfrac, [19000.5 + 3653, 3653, 0, 3653 - 1.25, 3654, 3655], [0, 0, 1, 0, 0, 0], "dayfrac")
check(colmetadata(df, :dayfrac, "format") == "%td", "dayfrac: format")
# The POSIXct not whole microseconds, truncated to the millisecond.
check(isequal(utc_ms.(df.whenfrac), [1000, 2000, missing, 3500, -1, 6000]), "whenfrac: truncated")

println("Julia checked ", checked[], " values and labels in R's file")
if !isempty(failures)
    println("FAILED:")
    foreach(f -> println("  ", f), failures)
    exit(1)
end
