# What DataFrames' operations do to a DtaColumn's codes and to the
# metadata read_parquet attaches (plan 0019, "What keeps the codes").
# These are observations of DataFrames, not promises of ours; docs/julia.md,
# "Labels and .a to .z through DataFrames operations", lists the same
# results. Checked on DataFrames 1.8.2 and on the oldest version
# Project.toml allows.

using Datakit, DataFrames, Test

# A frame as read_parquet returns it: x holds ., .a and .z.
function letters_frame()
    p = tempname() * ".parquet"
    try
        save_parquet(p, DataFrame(id = 1:6, g = [1, 1, 2, 2, 2, 1],
                                  x = DtaColumn([1.0, 0, 0, 0, 5, 6], UInt8[0, 1, 2, 27, 0, 0]));
                     label = "T", column_labels = Dict(:x => "X"))
        return read_parquet(p)
    finally
        rm(p; force = true)
    end
end

const X = UInt8[0, 1, 2, 27, 0, 0]   # x's codes as read
const LOST = UInt8[0, 1, 1, 1, 0, 0] # the same with .a to .z become .

label(d, c) = colmetadata(d, c, "label", nothing)
table_label(d) = metadata(d, "label", nothing)

# Saved and read again, the codes are what the frame held.
function saved_codes(d, c)
    p = tempname() * ".parquet"
    try
        save_parquet(p, d)
        return codes_of(read_parquet(p)[!, c])
    finally
        rm(p; force = true)
    end
end

@testset "DataFrames operations" begin
    df = letters_frame()
    @test df.x isa DtaColumn{Float64} && codes_of(df.x) == X
    @test label(df, :x) == "X" && table_label(df) == "T"

    @testset "keep the codes" begin
        # Row selection: indexing, filter, sort, subset (and in place).
        @test codes_of(df[[6, 5, 4], :x]) == [0, 0, 27]
        @test codes_of(df[3:5, :].x) == [2, 27, 0]
        @test codes_of(view(df, 3:4, :).x) == [2, 27]
        for d in (filter(:id => >(2), df), subset(df, :id => ByRow(>=(3))), filter!(:id => >(2), copy(df)),
                  subset!(copy(df), :id => ByRow(>=(3))))
            @test d.x isa DtaColumn && codes_of(d.x) == [2, 27, 0, 0]
            @test label(d, :x) == "X" && table_label(d) == "T"
        end
        for d in (sort(df, :id; rev = true), sort!(copy(df), :id; rev = true))
            @test codes_of(d.x) == reverse(X) && label(d, :x) == "X"
        end
        # sort on x itself: every missing value is `missing` to DataFrames,
        # so they go last in their order, each with its code.
        @test codes_of(sort(df, :x).x) == [0, 0, 0, 1, 2, 27]
        @test codes_of(copy(df).x) == X

        # select, transform and transform! passing x through, by name or
        # through identity or copy; label kept, renamed or not.
        for (what, d, c) in (
            ("select :x", select(df, :x), :x),
            ("select :x => :y", select(df, :x => :y), :y),
            ("select identity", select(df, :x => identity => :x), :x),
            ("select identity, renamed", select(df, :x => identity => :y), :y),
            ("select copy", select(df, :x => copy => :x), :x),
            ("select copy, renamed", select(df, :x => copy => :y), :y),
            ("transform identity, renamed", transform(df, :x => identity => :y), :y),
            ("transform copy, renamed", transform(df, :x => copy => :y), :y),
            ("transform! identity", transform!(copy(df), :x => identity => :x), :x),
            ("transform! copy, renamed", transform!(copy(df), :x => copy => :y), :y),
        )
            ok = d[!, c] isa DtaColumn && codes_of(d[!, c]) == X && label(d, c) == "X" && table_label(d) == "T"
            ok || @info "expected to keep: $what" typeof(d[!, c]) codes_of(d[!, c]) label(d, c)
            @test ok
        end

        # The same through groupby, with identity (rows come back in order).
        gdf = groupby(df, :g)
        for (what, d, c) in (
            ("grouped select :x", select(gdf, :x), :x),
            ("grouped select identity", select(gdf, :x => identity => :x), :x),
            ("grouped transform identity, renamed", transform(gdf, :x => identity => :y), :y),
            ("grouped transform! identity, renamed", transform!(groupby(copy(df), :g), :x => identity => :y), :y),
        )
            ok = d[!, c] isa DtaColumn && codes_of(d[!, c]) == X && label(d, c) == "X"
            ok || @info "expected to keep: $what" typeof(d[!, c]) codes_of(d[!, c]) label(d, c)
            @test ok
        end
        # Each group's rows, as views.
        @test [stata_code(sdf.x, i) for sdf in gdf for i in 1:nrow(sdf)] == X[[1, 2, 6, 3, 4, 5]]

        # What is kept is saved.
        @test saved_codes(sort(df, :id; rev = true), :x) == reverse(X)
        @test saved_codes(select(df, :x => identity => :y), :y) == X
    end

    @testset "lose the codes: .a to .z become missing, saved as ." begin
        gdf = groupby(df, :g)
        for (what, d, c, keeps_label) in (
            # A function that builds a new vector, under the same name.
            ("transform, a function", transform(df, :x => (v -> v .+ 1) => :x), :x, true),
            ("transform!, a function", transform!(copy(df), :x => (v -> v .* 2) => :x), :x, true),
            ("transform, ByRow", transform(df, :x => ByRow(identity) => :x), :x, true),
            # ... or a new one, which starts without metadata.
            ("transform, a function, renamed", transform(df, :x => (v -> v .+ 0) => :y), :y, false),
            ("select, ByRow, renamed", select(df, :x => ByRow(v -> v) => :y), :y, false),
            # copy inside groupby builds a new vector per group.
            ("grouped transform copy, renamed", transform(gdf, :x => copy => :y), :y, true),
            ("grouped select copy", select(gdf, :x => copy => :x), :x, true),
            ("grouped transform! copy, renamed", transform!(groupby(copy(df), :g), :x => copy => :y), :y, true),
            # Concatenating DataFrames.
            ("vcat", vcat(df[1:3, :], df[4:6, :]), :x, true),
        )
            ok = codes_of(d[!, c]) == LOST && (label(d, c) == "X") == keeps_label
            ok || @info "expected to lose: $what" typeof(d[!, c]) codes_of(d[!, c]) label(d, c)
            @test ok
        end
        # combine of groups: rows in group order, the codes lost, the label kept.
        for d in (combine(gdf, :x), combine(gdf, :x => identity => :x))
            @test !(d.x isa DtaColumn)
            @test codes_of(d.x) == LOST[[1, 2, 6, 3, 4, 5]]
            @test label(d, :x) == "X"
        end
        # Broadcasting into a new column.
        d = copy(df)
        d.y = d.x .+ 0
        @test codes_of(d.y) == LOST && label(d, :y) === nothing
        # Saved: . where the letters were.
        @test saved_codes(vcat(df[1:3, :], df[4:6, :]), :x) == LOST
    end

    @testset "joins (tested, not promised)" begin
        r = DataFrame(id = [6, 5, 4, 3, 2, 1, 9], w = 1:7)
        for (what, d, want, keeps_table) in (
            ("innerjoin", innerjoin(df, r; on = :id), X, false),
            ("leftjoin", leftjoin(df, r; on = :id), X, true),
            ("rightjoin", rightjoin(df, r; on = :id), [X; 0x01], false),
            ("outerjoin", outerjoin(df, r; on = :id), [X; 0x01], false),
            ("innerjoin, letters on the right", innerjoin(r, df; on = :id), X[[6, 5, 4, 3, 2, 1]], false),
            ("leftjoin, letters on the right", leftjoin(r, df; on = :id), [X[[6, 5, 4, 3, 2, 1]]; 0x01], false),
        )
            ok = d.x isa DtaColumn && sort(codes_of(d.x)) == sort(want) && label(d, :x) == "X" &&
                 (table_label(d) == "T") == keeps_table
            # Each row's code is the one its id had (rows in DataFrames' order).
            byid = Dict(zip(df.id, X))
            ok &= all(i -> get(byid, d.id[i], 0x01) == stata_code(d.x, i), 1:nrow(d))
            ok || @info "join: $what" typeof(d.x) codes_of(d.x) d.id label(d, :x) table_label(d)
            @test ok
        end
    end

    @testset "set a letter (replace x = .d if age < 15)" begin
        p = tempname() * ".parquet"
        save_parquet(p, DataFrame(age = [12, 30, missing, 14], x = [1.0, 2.0, 3.0, 4.0]); label = "T",
                     column_labels = Dict(:x => "Score"))
        df = read_parquet(p)
        @test df.x isa Vector{Float64}   # no letters, so a plain column
        # The recipe, as docs/julia.md gives it.
        df.x isa DtaColumn || (df[!, :x] = DtaColumn(df.x))
        for i in findall(coalesce.(df.age .< 15, false))
            set_stata_code!(df.x, i, 5)   # codes: 1 is ., 2 to 27 are .a to .z; 5 is .d
        end
        @test df.x isa DtaColumn{Float64}
        @test codes_of(df.x) == [5, 0, 0, 5]
        @test isequal(collect(df.x), [missing, 2.0, 3.0, missing])
        @test colmetadata(df, :x, "label"; style = true) == ("Score", :note)
        @test colmetadata(df, :x, "storage") == "double"
        @test metadata(df, "label") == "T"
        save_parquet(p, df)
        back = read_parquet(p)
        @test codes_of(back.x) == [5, 0, 0, 5] && colmetadata(back, :x, "label") == "Score"
        # On a column that already is a DtaColumn, the recipe changes it in place.
        y = back.x
        back.x isa DtaColumn || (back[!, :x] = DtaColumn(back.x))
        set_stata_code!(back.x, 2, 2)
        @test back.x === y && codes_of(back.x) == [5, 2, 0, 5]
        # An Int column: DtaColumn keeps its type.
        d = DataFrame(n = [1, 2, 3])
        colmetadata!(d, :n, "label", "N"; style = :note)
        d[!, :n] = DtaColumn(d.n)
        set_stata_code!(d.n, 3, 27)
        @test d.n isa DtaColumn{Int64} && codes_of(d.n) == [0, 0, 27] && colmetadata(d, :n, "label") == "N"
        rm(p)
    end
end
