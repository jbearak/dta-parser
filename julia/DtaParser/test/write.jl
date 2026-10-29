# Round trips (read, write, read again, and re-read by ReadStatTables),
# the type mapping for tables that did not come from read_dta, and errors.

# Uses fixtures, known and theirs_values from compat.jl.

using DtaParser, DataAPI, DataFrames, Dates, ReadStatTables, Test

@testset "every fixture round trips" begin
    dir = mktempdir()
    for file in fixtures()
        a = read_dta(joinpath(FIXTURES, file))
        out = joinpath(dir, file)
        write_dta(out, a)
        b = read_dta(out)
        @testset "$file" begin
            @test DataAPI.metadata(b, "release") == 118
            @test names(a) == names(b)
            for n in Symbol.(names(a))
                x, y = a[n], b[n]
                @test isequal(collect(x), collect(y))
                @test codes_of(x) == codes_of(y)
                @test typeof(x) == typeof(y)
                for key in ("label", "format", "value_labels")
                    @test DataAPI.colmetadata(a, n, key) == DataAPI.colmetadata(b, n, key)
                end
                sa, sb = DataAPI.colmetadata(a, n, "storage"), DataAPI.colmetadata(b, n, "storage")
                startswith(sa, "str") || @test sa == sb
            end
            for key in ("label", "notes", "characteristics", "sorted_by", "value_labels")
                @test DataAPI.metadata(a, key) == DataAPI.metadata(b, key)
            end
            # Through a DataFrame too.
            c = read_dta(write_dta(joinpath(dir, "df_" * file), DataFrame(a)))
            @test all(n -> isequal(collect(a[n]), collect(c[n])) && codes_of(a[n]) == codes_of(c[n]), Symbol.(names(a)))
            @test DataAPI.metadata(c, "value_labels") == DataAPI.metadata(a, "value_labels")
            # ReadStatTables reads what we wrote as it reads the original.
            if !known(file, "file")
                r0, r1 = readstat(joinpath(FIXTURES, file)), readstat(out)
                for n in Symbol.(names(a))
                    known(file, String(n)) && continue
                    @test isequal(theirs_values(getproperty(r1, n)), theirs_values(getproperty(r0, n)))
                end
            end
        end
    end
end

storage(t, n) = DataAPI.colmetadata(t, n, "storage")

@testset "type mapping" begin
    dir = mktempdir()
    p = joinpath(dir, "map.dta")
    big = "x"^3000
    write_dta(p, (
        bool=[true, false, true],
        b=[-127, 0, 100], i=[-127, 0, 101], l=[1, 2, 40_000], d=[1, 2, 3_000_000_000], s53=[0, 2^53, -2^53],
        i8=Int8[1, 2, 3], u16=UInt16[1, 2, 60_000],
        f32=Float32[1.5, NaN, 2], f64=[1.5, NaN, 2],
        mi=[1, missing, 3], mf=[missing, 1.5, 2.0], mb=Union{Missing,Bool}[true, missing, false],
        date=[Date(2020, 1, 1), Date(1960), Date(1900, 1, 1)],
        dt=[DateTime(2020, 1, 1, 12, 30, 15, 250), DateTime(1960), missing],
        s=["a", "bcd", ""], ms=["a", missing, "c"], longtext=["x", big, ""],
        bin=[UInt8[0, 1], UInt8[], UInt8[0xff]], mixed=Union{String,Vector{UInt8}}["text", UInt8[0], ""],
        any=Any["p", "q", "r"], none=[missing, missing, missing],
    ))
    t = read_dta(p)
    want = Dict(:bool => "byte", :b => "byte", :i => "int", :l => "long", :d => "double", :s53 => "double",
                :i8 => "byte", :u16 => "long", :f32 => "float", :f64 => "double", :mi => "byte", :mf => "double",
                :mb => "byte", :date => "long", :dt => "double", :s => "str3", :ms => "str1", :longtext => "strL",
                :bin => "strL", :mixed => "strL", :any => "str1", :none => "byte")
    for (n, s) in want
        @test storage(t, n) == s
    end
    @test t.bool == [1, 0, 1]
    @test t.s53 == [0, 2^53, -2^53]
    @test t.u16 == [1, 2, 60_000]
    @test codes_of(t.f32) == [0, 1, 0] && codes_of(t.f64) == [0, 1, 0]
    @test isequal(collect(t.mi), [1, missing, 3]) && codes_of(t.mi) == [0, 1, 0]
    @test isequal(collect(t.mb), [1, missing, 0])
    @test t.date == [Date(2020, 1, 1), Date(1960), Date(1900, 1, 1)]
    @test DataAPI.colmetadata(t, :date, "format") == "%td"
    @test isequal(t.dt, [DateTime(2020, 1, 1, 12, 30, 15, 250), DateTime(1960), missing])
    @test DataAPI.colmetadata(t, :dt, "format") == "%tc"
    @test t.ms == ["a", "", "c"]
    @test t.longtext[2] == big
    @test t.bin == [UInt8[0, 1], UInt8[], UInt8[0xff]]
    @test t.mixed == ["text", UInt8[0], ""]
    @test codes_of(t.none) == [1, 1, 1]

    # A DtaColumn keeps its storage type and codes.
    write_dta(p, (x=DtaColumn(Int16[1, 0, 3], UInt8[0, 5, 0]), y=DtaColumn(Float32[1, 0], UInt8[0, 27])[[2, 1, 1]]))
    t = read_dta(p)
    @test storage(t, :x) == "int" && codes_of(t.x) == [0, 5, 0]
    @test storage(t, :y) == "float" && codes_of(t.y) == [27, 0, 0]
end

@testset "metadata from keywords and DataFrames" begin
    dir = mktempdir()
    p = joinpath(dir, "meta.dta")
    write_dta(p, DataFrame(x=[1, 2, missing], s=["a", "b", "c"]);
              label="A label", notes=["one", "two"],
              value_labels=Dict("yn" => Dict(1 => "Yes", 2 => "No", stata_key(".a") => "Refused", ".b" => "Skipped")),
              column_labels=Dict(:x => "Answer"), column_value_labels=Dict("x" => "yn"),
              column_formats=Dict(:x => "%9.2f", :s => "%-5s"), timestamp="01 Jan 2020 00:00")
    t = read_dta(p)
    @test DataAPI.metadata(t, "label") == "A label"
    @test DataAPI.metadata(t, "notes") == ["one", "two"]
    @test DataAPI.metadata(t, "timestamp") == "01 Jan 2020 00:00"
    @test DataAPI.metadata(t, "value_labels")["yn"] ==
          Dict(1.0 => "Yes", 2.0 => "No", stata_key(".a") => "Refused", stata_key(".b") => "Skipped")
    @test DataAPI.colmetadata(t, :x, "label") == "Answer"
    @test DataAPI.colmetadata(t, :x, "value_labels") == "yn"
    @test DataAPI.colmetadata(t, :x, "format") == "%9.2f"
    @test DataAPI.colmetadata(t, :s, "format") == "%-5s"

    # Labels set on a DataFrame are written.
    df = DataFrame(x=[1, 2])
    colmetadata!(df, :x, "label", "From colmetadata"; style=:note)
    metadata!(df, "label", "From metadata"; style=:note)
    t = read_dta(write_dta(p, df))
    @test DataAPI.colmetadata(t, :x, "label") == "From colmetadata"
    @test DataAPI.metadata(t, "label") == "From metadata"

    # A format that does not suit the column's new type is not kept.
    df = DataFrame(read_dta(write_dta(p, (x=[1.5, 2.0],); column_formats=Dict(:x => "%9.2f"))))
    df.x = ["now", "text"]
    @test DataAPI.colmetadata(read_dta(write_dta(p, df)), :x, "format") == "%-4s"
    # A storage type from the metadata is kept when the values fit it.
    df = DataFrame(read_dta(write_dta(p, (x=Int32[1, 40_000],))))
    df.x = Int32[1, 2]
    @test storage(read_dta(write_dta(p, df)), :x) == "long"
    df.x = [1, 2^40]
    @test storage(read_dta(write_dta(p, df)), :x) == "double"
end

@testset "write errors" begin
    dir = mktempdir()
    p = joinpath(dir, "bad.dta")
    message(f) = try
        f()
        ""
    catch e
        sprint(showerror, e)
    end
    for bad in ("1x", "if", "_n", "str12", "a b", "x"^33, "")
        @test occursin("\"$bad\" is not a valid Stata name", message(() -> write_dta(p, NamedTuple{(Symbol(bad),)}(([1],)))))
    end
    @test occursin("column big", message(() -> write_dta(p, (big=[2^53 + 1],))))
    @test occursin("column z: cannot write values of type ComplexF64", message(() -> write_dta(p, (z=[1.0im],))))
    @test occursin("column v", message(() -> write_dta(p, (v=[[1, 2]],))))
    @test occursin("NUL", message(() -> write_dta(p, (s=["a\0b"],))))
    @test occursin("labels `.`", message(() -> write_dta(p, (x=[1],); value_labels=Dict("l" => Dict(missing => "dot")))))
    @test !isfile(p)
    @test_throws ArgumentError write_dta(p, 42)
end
