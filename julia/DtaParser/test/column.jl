# DtaColumn keeps its missing codes through the bulk operations the docs
# list, and stata_key gives the doubles R and npm give.

using DtaParser, Test

# 1.5, ., .a, -2, .z
sample() = DtaColumn([1.5, NaN, NaN, -2.0, NaN], UInt8[0, 1, 2, 0, 27])

@testset "elements" begin
    c = sample()
    @test isequal(collect(c), [1.5, missing, missing, -2.0, missing])
    @test eltype(c) == Union{Missing,Float64}
    @test codes_of(c) == [0, 1, 2, 0, 27]
    c[1] = missing
    @test stata_code(c, 1) == 1
    c[2] = 3
    @test (c[2], stata_code(c, 2)) == (3.0, 0)
    set_stata_code!(c, 4, 5)
    @test ismissing(c[4]) && stata_code(c, 4) == 5
    @test_throws ArgumentError set_stata_code!(c, 4, 28)
    @test_throws ArgumentError DtaColumn([1], UInt8[30])
    # Copying single elements keeps `.` but not the letter.
    d = sample()
    d[1] = c[3]
    @test stata_code(d, 1) == 1
    e = DtaColumn(Union{Missing,Int32}[1, missing, 3])
    @test e isa DtaColumn{Int32} && codes_of(e) == [0, 1, 0]
end

@testset "bulk operations keep codes" begin
    c = sample()
    @test codes_of(c[2:3]) == [1, 2]
    @test codes_of(c[[5, 3, 1]]) == [27, 2, 0]
    @test codes_of(c[[false, false, true, true, true]]) == [2, 0, 27]
    @test c[:] isa DtaColumn && codes_of(c[:]) == codes_of(c)
    v = view(c, 3:5)
    @test codes_of(v) == [2, 0, 27]
    set_stata_code!(v, 2, 3)
    @test stata_code(c, 4) == 3
    @test codes_of(copy(view(sample(), 2:3))) == [1, 2]
    @test codes_of(copy(c)) == codes_of(c) && copy(c).codes !== c.codes
    s = similar(c)
    @test s isa DtaColumn{Float64} && length(s) == 5
    @test similar(c, Union{Missing,Int8}, 2) isa DtaColumn{Int8}
    @test similar(c, String, 2) isa Vector{String}
    # Stata order: numbers, then ., .a, ..., .z.
    @test codes_of(sort(sample())) == [0, 0, 1, 2, 27]
    @test isequal(collect(sort(sample()))[1:2], [-2.0, 1.5])
    @test codes_of(sort(sample(); rev=true)) == [27, 2, 1, 0, 0]
    @test sortperm(sample()) == [4, 1, 2, 3, 5]
    p = permute!(sample(), [5, 4, 3, 2, 1])
    @test codes_of(p) == [27, 0, 2, 1, 0]
    @test codes_of(invpermute!(p, [5, 4, 3, 2, 1])) == codes_of(sample())
    @test codes_of(reverse(sample())) == [27, 0, 2, 1, 0]
    @test codes_of(vcat(sample(), sample()[1:2])) == [0, 1, 2, 0, 27, 0, 1]
    @test vcat(DtaColumn(Int8[1], UInt8[2]), DtaColumn([2.5], UInt8[0])) isa DtaColumn{Float64}
    a = sample()
    a[1:2] = sample()[4:5]
    @test codes_of(a) == [0, 27, 2, 0, 27]
    a[[true, false, false, false, true]] = sample()[2:3]
    @test codes_of(a) == [1, 27, 2, 0, 2]
    a[1:2] = view(sample(), 3:4)
    @test codes_of(a)[1:2] == [2, 0]
    b = sample()
    b .= sample()[[5, 4, 3, 2, 1]]
    @test codes_of(b) == [27, 0, 2, 1, 0]
    b = sample()
    copyto!(b, 1, sample(), 3, 2)
    @test codes_of(b)[1:2] == [2, 0]
    @test codes_of(append!(sample(), sample()[3:3])) == [0, 1, 2, 0, 27, 2]
    @test codes_of(push!(sample(), missing)) == [0, 1, 2, 0, 27, 1]
    @test codes_of(resize!(sample(), 6)) == [0, 1, 2, 0, 27, 1]
    @test codes_of(deleteat!(sample(), 1)) == [1, 2, 0, 27]
    @test codes_of(insert!(sample(), 1, missing)) == [1, 0, 1, 2, 0, 27]
end

@testset "stata_key" begin
    bits(x) = reinterpret(UInt64, x)
    # The doubles dtatools and the npm package use: 0x7fe0000000000000 + (code - 1) << 40.
    @test bits(stata_key(missing)) == 0x7fe0000000000000
    @test bits(stata_key(".")) == 0x7fe0000000000000
    @test bits(stata_key(".a")) == 0x7fe0010000000000
    @test bits(stata_key(".z")) == 0x7fe01a0000000000
    @test bits(stata_key(NaN)) == 0x7fe0000000000000
    @test stata_key(3) === 3.0
    @test_throws ArgumentError stata_key(".A")
    keys = stata_key(sample())
    @test keys[1] == 1.5 && keys[4] == -2.0
    @test keys[2] < keys[3] < keys[5]
    @test all(k -> k > floatmax(Float64) / 2, keys[[2, 3, 5]])
    @test stata_key(sample(), 3) == stata_key(".a")
    @test stata_key([1, missing]) == [1.0, stata_key(".")]
    @test stata_key(view(sample(), 3:3)) == [stata_key(".a")]
end
