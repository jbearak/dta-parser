using Datakit, Test

const FIXTURES = joinpath(@__DIR__, "..", "..", "..", "compat", "fixtures")

fixture(name) = joinpath(FIXTURES, name)
codes_of(c) = UInt8[stata_code(c, i) for i in eachindex(c)]

@testset "Datakit" begin
    include("load.jl")
    include("smoke.jl")
    include("parquet.jl")
    include("categorical_letters.jl")
    include("operations.jl")
    include("fixed_width.jl")
    include("docs.jl")
end
