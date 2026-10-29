using DtaParser, Test

const FIXTURES = joinpath(@__DIR__, "..", "..", "..", "compat", "fixtures")

fixture(name) = joinpath(FIXTURES, name)
codes_of(c) = [stata_code(c, i) for i in eachindex(c)]

@testset "DtaParser" begin
    include("column.jl")
    include("read.jl")
    include("compat.jl")
    include("dataframes.jl")
    include("write.jl")
end
