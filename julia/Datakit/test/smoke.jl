# A quick check that Datakit loads on DtaParser's library and handles
# paths with non-ASCII characters: Parquet written, read and described,
# and fixed-width text read. CI runs it on Windows after building
# DtaParser, and runtests.jl runs it everywhere.

using Datakit, DataFrames, DataAPI, Test

@testset "smoke" begin
    dir = joinpath(mktempdir(), "données ü 文件")
    mkpath(dir)

    path = joinpath(dir, "café.parquet")
    df = DataFrame(x=DtaColumn([1.5, 0.0, -2.0], UInt8[0, 2, 0]), s=["a", "é", "中文"])
    colmetadata!(df, :x, "label", "Größe", style=:note)
    save_parquet(path, df; compression=:zstd)
    t = read_parquet(path)
    @test isequal(collect(t.x), [1.5, missing, -2.0])
    @test stata_code(t.x, 2) == 2
    @test t.s == ["a", "é", "中文"]
    @test colmetadata(t, :x, "label") == "Größe"
    @test read_parquet_info(path)["nrows"] == 3

    dat, sas = joinpath(dir, "données.dat"), joinpath(dir, "données.sas")
    write(sas, "PROC FORMAT; VALUE f 1='un';\nDATA; INPUT ID 1 X 2;\nIF X = 9 THEN X = .;\nFORMAT X f.;\n")
    write(dat, "11\n29\n")
    fw = read_fixed_width(dat, sas)
    @test fw.ID == [1, 2]
    @test isequal(collect(fw.X), [1, missing])
end

@testset "precompile workload" begin
    # It runs while the package precompiles; it must work on its own too.
    @test Datakit.workload() === nothing
end
