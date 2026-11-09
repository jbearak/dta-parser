# Parquet categoricals holding .a to .z (plan 0022): DOUBLE level numbers
# in the file, read as labelled numbers, since a CategoricalArray cannot
# hold the letters. The fixtures are TypeScript datakit's
# (fixtures/make_categorical_letters.js).

using Datakit, DataFrames, DataAPI, Test
using CategoricalArrays

cl_file(suffix="") = joinpath(@__DIR__, "fixtures", "categorical_letters$suffix.parquet")
native_info(path) = Datakit.with_parquet(Datakit.pq_info, path, false)

const GRADE_LABELS = Dict(1.0 => "low", 2.0 => "mid", 3.0 => "high")

@testset "categoricals holding .a to .z" begin

@testset "read as labelled numbers with their letters, without a warning" begin
    t = @test_logs read_parquet(cl_file())
    # low, .a, high, ., .z, mid
    @test t.grade isa DtaColumn{Float64}
    @test codes_of(t.grade) == UInt8[0, 2, 0, 1, 27, 0]
    @test t.grade.values[[1, 3, 6]] == [1.0, 3.0, 2.0]
    @test colmetadata(t, :grade, "value_labels") == "grade"
    @test colmetadata(t, :grade, "storage") == "double"
    @test metadata(t, "value_labels")["grade"] == GRADE_LABELS
    # A categorical without letters stays a CategoricalArray.
    @test t.region isa CategoricalArray
    @test levels(t.region) == ["north", "south"]
    @test isequal(collect(t.region), ["north", "south", "north", "south", missing, "north"])
    @test colmetadata(t, :region, "value_labels") == ""

    # A window, and the column alone: the same set.
    w = @test_logs read_parquet(cl_file(); cols = [:grade], skip = 1, n_max = 2)
    @test codes_of(w.grade) == UInt8[2, 0] && w.grade.values[2] == 3.0
    @test colmetadata(w, :grade, "value_labels") == "grade"
    @test metadata(w, "value_labels")["grade"] == GRADE_LABELS
end

@testset "the info calls say categorical, DOUBLE" begin
    c = native_info(cl_file())["columns"]
    @test c[1]["kind"] == "double" && c[1]["physical_type"] == "DOUBLE"
    @test c[1]["logical"] == "categorical"
    @test c[1]["categories"] == ["low", "mid", "high"] && c[1]["ordered"] === true
    @test c[1]["value_labels"] == "grade"
    @test c[2]["kind"] == "text" && c[2]["levels"] == "profile"
    m = @test_logs read_parquet_info(cl_file())
    @test isempty(m["warnings"])
    @test m["value_labels"]["grade"] == GRADE_LABELS
    cols = m["columns"]
    @test cols.physical_type[1] == "DOUBLE"
    @test cols.eltype[1] == Union{Missing,Float64}
    @test cols.value_labels[1] == "grade"
end

@testset "save_parquet writes it back as labelled numbers" begin
    t = read_parquet(cl_file())
    p = tempname() * ".parquet"
    save_parquet(p, t)
    r = @test_logs read_parquet(p)
    @test r.grade isa DtaColumn{Float64}
    @test codes_of(r.grade) == codes_of(t.grade)
    @test r.grade.values[[1, 3, 6]] == [1.0, 3.0, 2.0]
    @test colmetadata(r, :grade, "value_labels") == "grade"
    @test metadata(r, "value_labels")["grade"] == GRADE_LABELS
    @test r.region isa CategoricalArray && levels(r.region) == ["north", "south"]
    # Labelled numbers now, not a categorical.
    @test native_info(p)["columns"][1]["logical"] === nothing
    rm(p)
end

@testset "a value that is not a level number reads as . with one warning per call" begin
    # low, .a | high (made 1.5), mid, in two row groups.
    bad = cl_file("_bad")
    t = @test_logs read_parquet(bad; n_max = 2)
    @test codes_of(t.grade) == UInt8[0, 2]
    msg = r"column \"grade\": row 3 of the file holds a value that is not one of its 3 level numbers; it is read as `\.`"
    for _ in 1:2
        w = @test_logs (:warn, msg) read_parquet(bad; skip = 1, n_max = 3)
        @test w.grade isa DtaColumn{Float64}
        @test codes_of(w.grade) == UInt8[2, 1, 0]
        @test w.grade.values[3] == 2.0
        @test colmetadata(w, :grade, "value_labels") == "grade"
    end
    whole = @test_logs (:warn, msg) read_parquet(bad)
    @test codes_of(whole.grade) == UInt8[0, 2, 1, 0]
end

@testset "a set of the column's name that does not fit: the next free name" begin
    # A set "grade" labelling 1 as "yes", used by the column "other".
    t = @test_logs read_parquet(cl_file("_collide"))
    @test colmetadata(t, :grade, "value_labels") == "grade_2"
    @test colmetadata(t, :other, "value_labels") == "grade"
    sets = metadata(t, "value_labels")
    @test sets["grade"] == Dict(1.0 => "yes")
    @test sets["grade_2"] == GRADE_LABELS
    one = @test_logs read_parquet(cl_file("_collide"); cols = [:grade])
    @test colmetadata(one, :grade, "value_labels") == "grade_2"
    @test metadata(one, "value_labels")["grade_2"] == GRADE_LABELS

    p = tempname() * ".parquet"
    save_parquet(p, t)
    r = @test_logs read_parquet(p)
    @test colmetadata(r, :grade, "value_labels") == "grade_2"
    @test colmetadata(r, :other, "value_labels") == "grade"
    @test metadata(r, "value_labels")["grade"] == Dict(1.0 => "yes")
    @test metadata(r, "value_labels")["grade_2"] == GRADE_LABELS
    @test codes_of(r.grade) == codes_of(t.grade) && codes_of(r.other) == codes_of(t.other)
    rm(p)
end

end
