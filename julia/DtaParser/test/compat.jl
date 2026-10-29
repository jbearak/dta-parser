# Every fixture in compat/fixtures, read and compared with what
# ReadStatTables.jl reads. Where ReadStatTables is known to read a fixture
# wrongly, that comparison is skipped, with the reason, in KNOWN (see
# docs/adr/0005-oracles.md; ReadStatTables wraps ReadStat, as haven does).
#
# ReadStatTables reads every missing value as `missing`, so the codes are
# checked against what haven and pandas read (compat/expected).

using DtaParser, ReadStatTables, DataAPI, Dates, Test

const EXPECTED = joinpath(@__DIR__, "..", "..", "..", "compat", "expected")

# (fixture name prefix, field): why ReadStatTables is not the oracle there.
const KNOWN = [
    ("haven_", "text", "ReadStat drops trailing blanks from strN values, as haven 2.5.5 does"),
    ("pandas_119_le", "strl", "ReadStat splits 119 strL references as 118 does, as haven 2.5.5 does"),
    ("pandastest_be_", "dt", "ReadStatTables leaves the old %d date format as numbers; pandas reads it as %td"),
    ("pandastest_be_105", "value labels", "ReadStat does not read value labels before 108"),
    ("readstat_104", "value labels", "ReadStat does not read value labels before 108"),
    ("readstat_108", "value labels", "ReadStat misreads release 108 value label tables, as haven 2.5.5 does"),
    ("readstat_105", "file", "ReadStat fails on this release 105 file (\"Unable to allocate memory\")"),
]

known(file, field) = any(((p, f, _),) -> startswith(file, p) && f == field, KNOWN)

fixtures() = sort(filter(endswith(".dta"), readdir(FIXTURES)))

plain(x) = x isa AbstractString ? String(x) : x
theirs_values(c) = map(plain, collect(c isa LabeledArray ? refarray(c) : c))

@testset "fixtures read as ReadStatTables reads them" begin
    compared = 0
    for file in fixtures()
        path = joinpath(FIXTURES, file)
        ours = read_dta(path)
        if known(file, "file")
            @test_throws Exception readstat(path)
            continue
        end
        theirs = readstat(path)
        @testset "$file" begin
            @test DataAPI.metadata(ours, "label") == DataAPI.metadata(theirs, "file_label")
            @test DataAPI.metadata(ours, "notes") == DataAPI.metadata(theirs, "notes")
            @test DataAPI.nrow(ours) == DataAPI.metadata(theirs, "row_count")
            @test names(ours) == String.(collect(ReadStatTables.columnnames(theirs)))
            for n in Symbol.(names(ours))
                known(file, String(n)) && continue
                @test isequal(collect(ours[n]), theirs_values(getproperty(theirs, n)))
                @test DataAPI.colmetadata(ours, n, "label") == DataAPI.colmetadata(theirs, n, "label")
                @test DataAPI.colmetadata(ours, n, "format") == DataAPI.colmetadata(theirs, n, "format")
                @test DataAPI.colmetadata(ours, n, "value_labels") == string(DataAPI.colmetadata(theirs, n, "vallabel"))
            end
            if !known(file, "value labels")
                sets = DataAPI.metadata(ours, "value_labels")
                theirs_sets = getvaluelabels(theirs)
                @test Set(keys(sets)) == Set(String.(keys(theirs_sets)))
                for (name, labels) in theirs_sets
                    want = Dict((k isa Char ? stata_key(".$k") : Float64(k)) => v for (k, v) in labels)
                    @test sets[String(name)] == want
                end
            end
            compared += 1
        end
    end
    @test compared > 20
end

@testset "missing codes as haven and pandas read them" begin
    checked = 0
    for file in fixtures()
        ours = read_dta(joinpath(FIXTURES, file); dates=false)
        for reader in ("haven", "pandas")
            doc = DtaParser.parse_json(read(joinpath(EXPECTED, replace(file, ".dta" => ".$reader.json")), String))
            haskey(doc, "error") && continue
            for (name, cells) in doc["values"]
                col = ours[Symbol(name)]
                eltype(col) <: Union{Missing,Real} || continue
                for (i, cell) in enumerate(cells)
                    code = cell isa AbstractDict ? DtaParser.key_code(stata_key(cell["missing"])) : 0x00
                    @test stata_code(col, i) == code
                    checked += 1
                end
            end
        end
    end
    @test checked > 100
end
