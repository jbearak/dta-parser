# A quick check that the library loads and handles a path with non-ASCII
# characters: CI runs it on Windows after Pkg.build, and runtests.jl runs
# it everywhere.

using DtaParser, Test

@testset "smoke" begin
    dir = joinpath(mktempdir(), "données ü 文件")
    mkpath(dir)
    path = joinpath(dir, "café.dta")
    write_dta(path, (x=DtaColumn([1.5, 0.0, -2.0], UInt8[0, 2, 0]), s=["a", "é", "中文"]))
    t = read_dta(path)
    @test isequal(collect(t.x), [1.5, missing, -2.0])
    @test stata_code(t.x, 2) == 2
    @test t.s == ["a", "é", "中文"]
end

@testset "precompile workload" begin
    # It runs while the package precompiles; it must work on its own too.
    @test DtaParser.workload() === nothing
end
