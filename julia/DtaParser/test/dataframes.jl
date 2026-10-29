# A DataFrame made from a DtaTable keeps its DtaColumns, so their codes,
# and its metadata, through the operations the docs list.

using DtaParser, DataFrames, Tables, Test

@testset "DataFrame conversion" begin
    t = read_dta(fixture("haven_118.dta"))
    num = codes_of(t.num)
    @test num == [0, 0, 1, 2, 27, 0]
    df = DataFrame(t)
    @test df.num isa DtaColumn{Float64}
    @test codes_of(df.num) == num
    @test df.num !== t.num
    @test DataFrame(t; copycols=false).num === t.num
    @test colmetadata(df, :num, "label") == "A double with extended missing values"
    @test colmetadata(df, :answer, "value_labels") == "answer"
    @test colmetadata(df, :day, "format") == "%td"
    @test metadata(df, "label") == "haven fixture"
    @test metadata(df, "value_labels")["answer"][stata_key(".d")] == "Don't know"

    # Tables.jl conversion hands over the columns themselves.
    @test Tables.columntable(t).num === t.num
    @test codes_of(Tables.columntable(df).num) == num

    @test codes_of(copy(df).num) == num
    @test codes_of(df[[6, 5, 4], :].num) == [0, 27, 2]
    @test codes_of(df[3:5, :].num) == [1, 2, 27]
    @test codes_of(view(df, 3:4, :).num) == [1, 2]
    @test codes_of(subset(df, :row => ByRow(>=(4))).num) == [2, 27, 0]
    @test codes_of(filter(:row => >(2), df).num) == [1, 2, 27, 0]
    @test codes_of(sort(df, :row; rev=true).num) == reverse(num)
    s = sort(df, :num)
    @test codes_of(s.num) == [0, 0, 0, 1, 2, 27]
    @test colmetadata(s, :num, "label") == "A double with extended missing values"

    df.g = [1, 1, 2, 2, 2, 1]
    gdf = groupby(df, :g)
    @test codes_of(select(gdf, :num).num) == num
    @test codes_of(transform(gdf, :num => identity => :n2).n2) == num
    @test [stata_code(sdf.num, i) for sdf in gdf for i in 1:nrow(sdf)] == [0, 0, 0, 1, 2, 27]
    @test codes_of(transform(df, :num => (x -> x) => :copy).copy) == num

    # combine collects each group's result into a vector DataFrames
    # allocates, and concatenating DataFrames does the same: `.` is kept,
    # the letters are lost. The docs say so.
    lost = [min(c, 0x01) for c in num]
    g = combine(gdf, :num)
    @test !(g.num isa DtaColumn)
    @test sort(codes_of(g.num)) == sort(lost)
    v = vcat(df[1:3, :], df[4:6, :])
    @test isequal(collect(v.num), collect(df.num))
    @test codes_of(v.num) == lost
end
