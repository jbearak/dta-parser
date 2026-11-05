# read_parquet, save_parquet and read_parquet_info (plans 0018 and 0019),
# moved from DtaParser's tests and rewritten for the DataFrame
# read_parquet returns. Every check DtaParser had is kept; the ones on
# read_meta are on read_parquet_info.
#
# The central check is the round trip: every fixture, as
# DataFrame(read_dta(f)), reads back from save_parquet with isequal
# values, the same missing code in every row and the same metadata,
# except what describes a .dta file rather than the data (release, byte
# order, encoding, and a string column's strN width, chosen again from
# the values). Files from other tools are compared with pyarrow's
# reading of them (compat/parquet/expected).

using Datakit, DataFrames, DataAPI, Dates, Tables, Test
using DtaParser: read_dta, read_meta
using CategoricalArrays, TimeZones

const PQ_DIR = joinpath(@__DIR__, "..", "..", "..", "compat", "parquet")

col(t, n) = Tables.getcolumn(t, Symbol(n))

# A DtaColumn holding only `.` reads back as a Vector{Union{Missing,T}}:
# a column is a DtaColumn only when the rows read hold .a to .z.
function same_type(y, x)
    typeof(y) == typeof(x) && return true
    x isa DtaColumn && !any(>(0x01), x.codes) && return typeof(y) == Vector{Union{Missing,eltype(x.values)}}
    false
end

# Every column of `b` as `a` has it: type, values, the missing code of
# every row, and metadata.
function same_table(b, a, what; storage_of_text=false)
    @test names(b) == names(a)
    for n in Symbol.(names(a))
        x, y = col(a, n), col(b, n)
        ok = same_type(y, x) && isequal(collect(y), collect(x))
        ok || @info "$what: column $n differs" typeof(x) typeof(y) first(collect(x), 5) first(collect(y), 5)
        @test ok
        @test codes_of(y) == codes_of(x)
        for key in ("label", "format", "value_labels", "storage")
            want, got = DataAPI.colmetadata(a, n, key), DataAPI.colmetadata(b, n, key)
            # A string column's strN width is chosen again from its values, and
            # DATE and TIMESTAMP have no storage type: a Date reads as long and
            # a DateTime as double, what write_dta writes.
            key == "storage" && !storage_of_text && (startswith(want, "str") || startswith(got, "str")) && continue
            key == "storage" && nonmissingtype(eltype(x)) <: Union{Date,DateTime} && continue
            want == got || @info "$what: column $n's $key differs" want got
            @test want == got
        end
    end
    for key in ("label", "notes", "characteristics", "sorted_by", "value_labels", "timestamp")
        want, got = DataAPI.metadata(a, key), DataAPI.metadata(b, key)
        isequal(want, got) || @info "$what: table metadata $key differs" want got
        @test isequal(want, got)
    end
    if b isa DataFrame
        @test all(k -> metadata(b, k; style=true)[2] === :note, metadatakeys(b))
        @test all(n -> all(k -> colmetadata(b, n, k; style=true)[2] === :note, colmetadatakeys(b, n)), names(b))
    end
end

function round_trip(t; kws...)
    p = tempname() * ".parquet"
    try
        save_parquet(p, t; kws...)
        return read_parquet(p)
    finally
        rm(p; force=true)
    end
end

# ---- files other tools wrote: values against pyarrow's reading of them

# The expected values, with integers of 16 digits or more as text, so
# that they are compared exactly.
function read_expected(path)
    text = read(path, String)
    text = replace(text, r"(?<=[,\[:])(-?[0-9]{16,})(?=[,\]}])" => s"\"\1\"")
    Datakit.Internals.parse_json(text)
end

const PER_NS = Dict("s" => 1_000_000_000, "ms" => 1_000_000, "us" => 1_000, "ns" => 1)
arrow_unit(t) = match(r"^[a-z0-9]+\[([a-z]+)", t)[1]
significant_digits(text) = length(replace(replace(replace(text, r"[-.]" => ""), r"^0+" => ""), r"0+$" => ""))

function same_value(want, got, arrow_type)
    want === nothing && return ismissing(got)
    ismissing(got) && return false
    want == "NaN" && return got isa AbstractFloat && isnan(got)
    if want isa Vector
        bytes = got isa AbstractString ? codeunits(got) : got
        return Int.(collect(bytes)) == Int.(want)
    end
    if got isa CategoricalValue
        got = String(got)
    end
    if startswith(arrow_type, "timestamp")
        ns = parse(BigInt, string(want isa AbstractFloat ? Int128(want) : want)) * PER_NS[arrow_unit(arrow_type)]
        t = got isa ZonedDateTime ? DateTime(got, UTC) : got
        return Dates.value(t) - Dates.value(DateTime(1970)) == fld(ns, 1_000_000)
    elseif startswith(arrow_type, "time")
        return Dates.value(got) == want * PER_NS[arrow_unit(arrow_type)]
    elseif startswith(arrow_type, "date32")
        return got == Date(1970) + Day(Int(want))
    elseif startswith(arrow_type, "decimal")
        got isa AbstractString && return got == want
        return got == parse(Float64, want)
    end
    got isa AbstractString && return got == want
    want isa AbstractString && return string(got) == want
    want isa AbstractFloat && want == 0 && got isa AbstractFloat && return got == 0 && signbit(got) == signbit(want)
    got == want
end

function check_fixture(path, expected, skip, n_max, what)
    total = Int(expected["rows"])
    rows = (min(skip, total) + 1):min(total, skip + n_max)
    nested = haskey(expected, "nested") ? :skip : :error
    # Decimals with more than 15 significant digits in the rows read are an
    # error with the default decimal = :float.
    wide = Set{String}()
    for spec in expected["columns"]
        startswith(spec["arrow_type"], "decimal") || continue
        any(v -> v !== nothing && significant_digits(v) > 15, spec["values"][rows]) && push!(wide, spec["name"])
    end
    ok = [spec["name"] for spec in expected["columns"] if !(spec["name"] in wide)]
    t = read_parquet(path; cols = ok, skip, n_max, timestamps = :truncate, nested)
    @test t isa DataFrame
    @test names(t) == ok
    for spec in expected["columns"]
        spec["name"] in wide && continue
        x = t[!, spec["name"]]
        want = spec["values"][rows]
        @test length(x) == length(want)
        bad = findfirst(i -> !same_value(want[i], x[i], spec["arrow_type"]), eachindex(want))
        bad === nothing || @info "$what: $(spec["name"]) row $bad" x[bad] want[bad] spec["arrow_type"]
        @test bad === nothing
        if startswith(spec["arrow_type"], "dictionary<values=string") || startswith(spec["arrow_type"], "dictionary<values=large_string")
            @test x isa CategoricalArray && !isordered(x)
            @test levels(x) == unique(String.(collect(skipmissing(x))))
        end
        if startswith(spec["arrow_type"], "timestamp") && occursin("tz=", spec["arrow_type"])
            zone = match(r"tz=([^\]]+)\]", spec["arrow_type"])[1]
            # A timestamp adjusted to UTC that names no zone (DuckDB's,
            # hyparquet's), which pyarrow shows as UTC, is a DateTime in UTC.
            @test all(v -> ismissing(v) || (v isa ZonedDateTime ? TimeZones.name(timezone(v)) == zone : zone == "UTC"), x)
        end
    end
    for name in wide
        err = try read_parquet(path; cols = [name], skip, n_max) catch e e end
        @test err isa Datakit.Internals.DtaError && occursin("decimal = :string", err.message)
        s = read_parquet(path; cols = [name], skip, n_max, decimal = :string)[!, name]
        spec = only(filter(s -> s["name"] == name, expected["columns"]))
        @test isequal(collect(s), [v === nothing ? missing : v for v in spec["values"][rows]])
    end
end

@testset "parquet" begin

@testset "every .dta fixture round-trips as a DataFrame" begin
    n = 0
    for file in sort(filter(endswith(".dta"), readdir(FIXTURES)))
        for dates in (true, false)
            t = read_dta(fixture(file); dates)
            df = DataFrame(t)
            r = round_trip(df)
            @test r isa DataFrame
            same_table(r, df, "$file, dates = $dates")
            # Saved again from the DataFrame read_parquet gave: everything
            # equal, the strN widths too.
            same_table(round_trip(r), r, "$file, dates = $dates, twice"; storage_of_text = true)
            # A DtaTable is a Tables.jl table too.
            same_table(round_trip(t), df, "$file, dates = $dates, from the DtaTable")
            n += 1
        end
    end
    @test n > 40
end

@testset "labels, letters, dates, categoricals and notes round-trip" begin
    t = (
        id = Int32[1, 2, 3, 4],
        score = DtaColumn([1.5, NaN, NaN, NaN], UInt8[0, 1, 2, 0]),
        smoker = DtaColumn(Int8[1, 0, 0, 0], UInt8[0, 0, 5, 1]),
        kids = Int16[0, 2, 300, 1],
        weight = DtaColumn(Float32[1.5, 0, 2.25, 0], UInt8[0, 27, 0, 1]),
        big = DtaColumn(Int64[2^62, 0, -1, 7], UInt8[0, 1, 0, 0]),
        word = ["a", "", "été", "x"],
        maybe = ["a", missing, "", "été"],
        flag = [true, false, true, true],
        seen = [Date(2024, 1, 15), Date(1960), Date(1900, 2, 28), Date(-50, 3, 1)],
        asked = [Date(2024), missing, Date(1999, 12, 31), missing],
        when = [DateTime(2024, 1, 15, 9, 30, 0, 125), DateTime(1960), DateTime(1600), DateTime(2100, 12, 31, 23, 59, 59, 999)],
        region = categorical(["N", "S", missing, "N"]; levels=["S", "N", "W"]),
        size = categorical(["lo", "hi", "hi", "lo"]; levels=["lo", "hi"], ordered=true),
        zoned = ZonedDateTime.([DateTime(2024, 3, 10, 6, 59), DateTime(2024, 3, 10, 7), DateTime(1970), DateTime(2024, 11, 3, 6)],
                               tz"America/New_York"; from_utc=true),
        blob = [UInt8[1, 2, 3], UInt8[], UInt8[255], UInt8[0]],
        tiny = UInt8[0, 1, 255, 7],
    )
    labels = Dict("yn" => Dict(0 => "No", 1 => "Yes", ".d" => "Don't know"))
    p = tempname() * ".parquet"
    save_parquet(p, t; label = "Smoking survey", notes = ["Wave 2 only.", "Second note"], value_labels = labels,
                  column_labels = Dict(:score => "Score", :region => "Region"), column_formats = Dict(:score => "%9.2f"),
                  column_value_labels = Dict(:smoker => "yn"))
    r = read_parquet(p)
    @test r isa DataFrame
    for n in keys(t)
        n === :tiny && continue
        @test isequal(collect(r[!, n]), collect(t[n]))
        @test same_type(r[!, n], t[n]) || (t[n] isa CategoricalArray && r[!, n] isa CategoricalArray)
    end
    # Only columns holding .a to .z are DtaColumns.
    @test r.score isa DtaColumn{Float64} && r.smoker isa DtaColumn{Int8} && r.weight isa DtaColumn{Float32}
    @test r.big isa Vector{Union{Missing,Int64}} && r.id isa Vector{Int32}
    @test r.tiny == Int16[0, 1, 255, 7]
    @test codes_of(r.score) == UInt8[0, 1, 2, 0]
    @test codes_of(r.smoker) == UInt8[0, 0, 5, 1]
    @test codes_of(r.weight) == UInt8[0, 27, 0, 1]
    @test isnan(r.score.values[2]) && r.score[1] == 1.5
    @test levels(r.region) == ["S", "N", "W"] && !isordered(r.region)
    @test levels(r.size) == ["lo", "hi"] && isordered(r.size)
    @test timezone(r.zoned[1]) == tz"America/New_York"
    @test DataAPI.metadata(r, "label") == "Smoking survey"
    @test DataAPI.metadata(r, "notes") == ["Wave 2 only.", "Second note"]
    @test DataAPI.metadata(r, "value_labels")["yn"][stata_key(".d")] == "Don't know"
    @test DataAPI.colmetadata(r, :smoker, "value_labels") == "yn"
    @test DataAPI.colmetadata(r, :score, "label") == "Score"
    @test DataAPI.colmetadata(r, :score, "format") == "%9.2f"
    @test DataAPI.colmetadata(r, :region, "label") == "Region"
    @test DataAPI.colmetadata(r, :smoker, "storage") == "byte"
    @test DataAPI.colmetadata(r, :weight, "storage") == "float"
    @test DataAPI.colmetadata(r, :word, "storage") == "str5"   # "été" is 5 bytes
    # The same with one row per row group, and with each codec.
    same_table(round_trip(r; row_group_size = 1), r, "one row per row group"; storage_of_text = true)
    for codec in (:zstd, :gzip, :lz4_raw, :none)
        same_table(round_trip(r; compression = codec), r, "$codec"; storage_of_text = true)
    end
    same_table(round_trip(r; compression = :zstd, compression_level = 9), r, "zstd 9"; storage_of_text = true)
    # From an IO and from bytes.
    io = IOBuffer()
    @test save_parquet(io, r) === io
    bytes = take!(io)
    same_table(read_parquet(bytes), r, "bytes"; storage_of_text = true)
    same_table(read_parquet(IOBuffer(bytes)), r, "IO"; storage_of_text = true)
    rm(p)
end

@testset "windows of rows and selections of columns" begin
    t = DataFrame(read_dta(fixture("haven_118.dta")))
    p = tempname() * ".parquet"
    save_parquet(p, t; row_group_size = 2)
    n = nrow(t)
    for (skip, n_max) in ((0, 2), (1, 3), (4, nothing), (5, 10), (6, 1), (0, 0), (100, 3))
        got = read_parquet(p; skip, n_max)
        rows = (min(skip, n) + 1):(n_max === nothing ? n : min(n, skip + n_max))
        @test nrow(got) == length(rows)
        for c in Symbol.(names(t))
            @test isequal(collect(got[!, c]), collect(t[!, c])[rows])
            @test codes_of(got[!, c]) == codes_of(t[!, c])[rows]
            # A DtaColumn exactly when the window holds a letter.
            @test (got[!, c] isa DtaColumn) == any(>(0x01), codes_of(t[!, c])[rows])
        end
    end
    first2 = Symbol.(names(t))[[2, 1]]
    @test Symbol.(names(read_parquet(p; cols = first2))) == first2
    @test names(read_parquet(p; cols = [2, 1])) == String.(first2)
    @test names(read_parquet(p; cols = String(first2[1]))) == [String(first2[1])]
    @test_throws ArgumentError read_parquet(p; cols = [:nope])
    err = try read_parquet(p; cols = [:nope]) catch e e end
    @test occursin("column \"nope\" is not in the file; its columns are", err.msg)
    @test_throws ArgumentError read_parquet(p; cols = [1, 1])
    @test_throws ArgumentError read_parquet(p; cols = [1000])
    rm(p)
    # A long text column, mostly distinct, across many row groups and pages.
    n = 30_000
    big = (distinct = ["value $(lpad(i, 6, '0'))" for i in 1:n],
           few = [("north", "south", missing)[i%3+1] for i in 1:n],
           mixed = [i > n ÷ 2 ? "late $i" : "early" for i in 1:n])
    r = round_trip(big; row_group_size = 1000)
    @test isequal(collect(r.distinct), big.distinct) && isequal(collect(r.few), big.few) && r.mixed == big.mixed
    p = tempname() * ".parquet"
    save_parquet(p, big; row_group_size = 1000)
    w = read_parquet(p; skip = 12_345, n_max = 2_500)
    @test isequal(collect(w.few), big.few[12_346:14_845]) && w.distinct == big.distinct[12_346:14_845]
    rm(p)
end

@testset "read_parquet_info describes a Parquet file" begin
    t = (id = Int32[1, 2, 3], smoker = DtaColumn(Int8[1, 0, 0], UInt8[0, 0, 5]), day = Date(2024) .+ Day.(0:2),
         region = categorical(["a", "b", "a"]), when = [DateTime(2024), missing, DateTime(2025)])
    p = tempname() * ".parquet"
    save_parquet(p, t; label = "Survey", notes = ["A note"], row_group_size = 2,
                 value_labels = Dict("yn" => Dict(0 => "No", 1 => "Yes")), column_labels = Dict(:smoker => "Smokes"),
                 column_value_labels = Dict(:smoker => "yn"))
    m = read_parquet_info(p)
    @test !haskey(m, "format")
    @test m["nrows"] == 3
    @test [g.rows for g in m["row_groups"]] == [2, 1]
    @test all(g -> g.compressed_bytes > 0, m["row_groups"])
    @test startswith(m["created_by"], "dta-parquet")
    @test m["compression"] == ["snappy"]
    @test m["label"] == "Survey" && m["notes"] == ["A note"]
    @test [kv.key for kv in m["key_value"]] == ["dta", "ARROW:schema"]
    @test occursin("\"Smokes\"", only(kv.value for kv in m["key_value"] if kv.key == "dta"))
    cols = m["columns"]
    @test cols isa DataFrame
    @test names(cols) == ["name", "role", "physical_type", "logical_type", "eltype", "label", "format", "value_labels",
                          "storage"]
    @test cols.name == ["id", "smoker", "day", "region", "when"]
    @test cols.role == fill("data", 5)
    @test cols.physical_type == ["INT32", "DOUBLE", "INT32", "BYTE_ARRAY", "INT64"]
    @test cols.logical_type == ["", "", "DATE", "STRING", "TIMESTAMP(MILLIS, local)"]
    @test cols.eltype == [Int32, Union{Missing,Int8}, Date, CategoricalValue{String,UInt32}, Union{Missing,DateTime}]
    @test cols.label[2] == "Smokes" && cols.value_labels[2] == "yn" && cols.storage[2] == "byte"
    @test isequal(read_parquet_info(read(p))["columns"], cols)
    @test open(read_parquet_info, p)["nrows"] == 3
    # The table metadata a whole-file read gives.
    r = read_parquet(p)
    for key in ("label", "notes", "characteristics", "sorted_by", "value_labels", "timestamp")
        @test isequal(m[key], metadata(r, key))
    end
    # A file from another tool: its key-value entries, no profile.
    other = read_parquet_info(joinpath(PQ_DIR, "fixtures", "pyarrow_default.parquet"))
    @test [kv.key for kv in other["key_value"]] == ["ARROW:schema"]
    @test other["label"] == "" && isempty(other["value_labels"])
    # DtaParser 0.3 reads .dta only, and says where Parquet went.
    err = try read_meta(p) catch e e end
    @test err isa ArgumentError && occursin("read_parquet_info", err.msg)
    @test_throws ArgumentError read_meta(read(p))
    rm(p)
end

@testset "a strL column mixing text and bytes reads back as bytes" begin
    # Parquet's BYTE_ARRAY is text or bytes for the whole column (plan 0018).
    t = (s = Union{String,Vector{UInt8}}["ab", UInt8[0, 1], "é"],)
    r = round_trip(t)
    @test r.s isa Vector{Vector{UInt8}}
    @test r.s == [codeunits("ab"), UInt8[0, 1], codeunits("é")]
end

@testset "without TimeZones and CategoricalArrays: DateTime in UTC and String, with one warning" begin
    p = tempname() * ".parquet"
    save_parquet(p, (when = [ZonedDateTime(2024, 1, 1, 12, tz"Europe/Paris")], region = categorical(["a"])))
    code = """
        using Datakit
        t = read_parquet(ARGS[1])
        print(typeof(t.when), " ", t.when[1], " ", typeof(t.region))
        """
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code $p`
    err = IOBuffer()
    out = read(pipeline(cmd; stderr=err), String)
    warnings = String(take!(err))
    @test out == "Vector{Dates.DateTime} 2024-01-01T11:00:00 Vector{String}"
    @test occursin("TimeZones.jl is not loaded", warnings) && occursin("when (Europe/Paris)", warnings)
    @test occursin("CategoricalArrays.jl is not loaded", warnings) && occursin("region", warnings)
    rm(p)
end

@testset "missing_letters = false writes .a to .z as nulls" begin
    t = (v = DtaColumn([1.0, NaN, NaN], UInt8[0, 2, 1]), b = DtaColumn(Int8[1, 0, 0], UInt8[0, 3, 0]))
    r = round_trip(t; missing_letters = false)
    @test codes_of(r.v) == UInt8[0, 1, 1]
    @test codes_of(r.b) == UInt8[0, 1, 0]
    # No letters left, so plain vectors.
    @test r.b isa Vector{Union{Missing,Int8}} && r.v isa Vector{Union{Missing,Float64}}
end

@testset "errors name the column and say what to do" begin
    p = tempname() * ".parquet"
    @test_throws ArgumentError save_parquet(p, (a = [1],); compression = :lzo)
    err = try save_parquet(p, (a = [1],); compression = :zstd, compression_level = 99) catch e e end
    @test occursin("zstd levels run from 1 to 22", sprint(showerror, err))
    err = try save_parquet(p, (a = [1],); compression = :snappy, compression_level = 2) catch e e end
    @test occursin("snappy has no compression levels", sprint(showerror, err))
    @test_throws ArgumentError save_parquet(p, (a = [1],); row_group_size = 0)
    err = try save_parquet(p, (t = [Time(1)],)) catch e e end
    @test occursin("column t: cannot write values of type Time", sprint(showerror, err))
    err = try save_parquet(p, (z = [1 + 2im],)) catch e e end
    @test occursin("column z: cannot write", sprint(showerror, err))
    err = try save_parquet(p, (c = categorical([1, 2]),)) catch e e end
    @test occursin("levels must be strings", sprint(showerror, err))
    err = try save_parquet(p, (u = UInt64[typemax(UInt64)],)) catch e e end
    @test occursin("more than a 64-bit integer holds", sprint(showerror, err))
    err = try save_parquet(p, (b = DtaColumn(Int64[1, 0], UInt8[0, 2]),)) catch e e end
    @test err isa Exception
    @test !isfile(p)
    save_parquet(p, (v = [1.0],))
    @test_throws ArgumentError read_parquet(p; timestamps = :round)
    @test_throws ArgumentError read_parquet(p; decimal = :double)
    @test_throws ArgumentError read_parquet(p; nested = :yes)
    @test_throws ArgumentError read_parquet(p; skip = -1)
    @test_throws Datakit.Internals.DtaError read_parquet(UInt8[])
    @test_throws Datakit.Internals.DtaError read_parquet(fixture("haven_118.dta"))
    @test_throws Exception read_parquet(tempname() * ".parquet")
    rm(p)
end

@testset "files other tools wrote read as pyarrow reads them" begin
    files = sort(filter(endswith(".parquet"), readdir(joinpath(PQ_DIR, "fixtures"))))
    @test length(files) > 20
    for file in files
        stem = replace(file, ".parquet" => "")
        expected = read_expected(joinpath(PQ_DIR, "expected", stem * ".json"))
        path = joinpath(PQ_DIR, "fixtures", file)
        check_fixture(path, expected, 0, typemax(Int), stem)
        for (skip, n_max) in ((0, 7), (150, 101), (599, 5), (250, 300))
            check_fixture(path, expected, skip, n_max, "$stem rows $(skip + 1) to $(skip + n_max)")
        end
    end
end

@testset "nested columns and nanoseconds" begin
    nested = joinpath(PQ_DIR, "fixtures", "pyarrow_nested.parquet")
    err = try read_parquet(nested) catch e e end
    @test err isa ArgumentError && occursin("nested = :skip", err.msg) && occursin("\"tags\"", err.msg)
    err = try read_parquet(nested; cols = [:tags]) catch e e end
    @test occursin("is nested", err.msg)
    info = read_parquet_info(nested)["columns"]
    @test "tags" in info.name
    @test only(info.role[info.name .== "tags"]) == "nested"
    @test only(info.eltype[info.name .== "tags"]) === nothing
    types = joinpath(PQ_DIR, "fixtures", "pyarrow_types.parquet")
    err = try read_parquet(types; cols = [:stamp]) catch e e end
    @test err isa Datakit.Internals.DtaError
    @test occursin("read with read_parquet(\"$types\"; cols = [:stamp], timestamps = :truncate)", err.message)
    @test eltype(read_parquet(types; cols = [:t_us]).t_us) <: Union{Missing,Time}
    @test eltype(read_parquet(types; cols = [:u64]).u64) <: Union{Missing,UInt64}
end

end
