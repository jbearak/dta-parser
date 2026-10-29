# Column selection, row windows, dates, representations and errors.

using DtaParser, DataAPI, Dates, Test

@testset "representations" begin
    t = read_dta(fixture("haven_118.dta"); dates=false)
    @test t.row isa Vector{Int32}
    @test t.num isa DtaColumn{Float64}
    @test t.count isa DtaColumn{Int32}
    @test t.text isa Vector{String}
    @test t.day isa DtaColumn{Float64}
    @test t.big isa Vector{String}
    @test DataAPI.colmetadata(t, :big, "storage") == "strL"
    @test DataAPI.colmetadata(t, :text, "storage") == "str10"
    @test DataAPI.metadata(t, "release") == 118
    @test DataAPI.metadata(t, "byte_order") == "little"
    @test DataAPI.nrow(t) == 6 && DataAPI.ncol(t) == 7
    @test t["row"] === t.row
    p = fixture("pandas_118_le.dta")
    u = read_dta(p)
    @test u.i8 isa Union{Vector{Int8},DtaColumn{Int8}}
    @test u.f32 isa Union{Vector{Float32},DtaColumn{Float32}}
    m = read_meta(p)
    @test m["nrows"] == DataAPI.nrow(u)
    @test [c["name"] for c in m["columns"]] == names(u)
    @test m["columns"][1]["storage"] == DataAPI.colmetadata(u, 1, "storage")
end

@testset "columns and rows" begin
    p = fixture("haven_118.dta")
    all = read_dta(p)
    t = read_dta(p; cols=[:text, "row", 2])
    @test names(t) == ["text", "row", "num"]
    @test t.text == all.text
    @test isequal(collect(read_dta(p; cols=:num).num), collect(all.num))
    w = read_dta(p; skip=2, n_max=3)
    @test DataAPI.nrow(w) == 3
    @test w.row == all.row[3:5]
    @test [stata_code(w.num, i) for i in 1:3] == [stata_code(all.num, i) for i in 3:5]
    @test w.big == all.big[3:5]
    @test DataAPI.nrow(read_dta(p; skip=4)) == 2
    @test DataAPI.nrow(read_dta(p; skip=10)) == 0
    @test DataAPI.nrow(read_dta(p; n_max=0)) == 0
    @test read_dta(p; n_max=100).row == all.row
    # A window without missing values is a plain vector.
    @test read_dta(p; n_max=2).num isa Vector{Float64}
    @test_throws ArgumentError read_dta(p; cols=[:nope])
    @test_throws ArgumentError read_dta(p; cols=[99])
    @test_throws ArgumentError read_dta(p; cols=[:row, 1])
    @test_throws ArgumentError read_dta(p; skip=-1)
    @test_throws ArgumentError read_dta(p; n_max=-1)
end

@testset "errors and encodings" begin
    @test_throws DtaParser.DtaError read_dta("/no/such/file.dta")
    err = try
        read_dta("/no/such/file.dta")
    catch e
        sprint(showerror, e)
    end
    @test occursin("/no/such/file.dta", err)
    p = fixture("haven_114.dta")
    @test_throws DtaParser.DtaError read_dta(p; encoding="ebcdic")
    @test DataAPI.metadata(read_dta(p), "encoding") == "windows-1252"
    @test DataAPI.metadata(read_dta(p; encoding="latin1"), "encoding") == "latin1"
    # haven wrote UTF-8 into this release 114 file.
    @test read_dta(p; encoding="utf-8").text[2] == "café"
    notdta = joinpath(mktempdir(), "x.dta")
    write(notdta, "not a dta file")
    @test_throws DtaParser.DtaError read_dta(notdta)
end
