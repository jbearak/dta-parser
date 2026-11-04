# read_fixed_width reads fixed-width text through a SAS setup file (plan
# 0009). What each value should be follows from the setup text written
# here.

using DtaParser, DataAPI, Test

const FW_SETUP = """
/* A setup in CDC's style */
libname "data-file-path";
PROC FORMAT;
  VALUE sexf  1='(1) Boy' 2='(2) Girl' ;
  VALUE kidsf 0='(0) None' 98='(98) DK' 99='(99) Not ascertained' ;
DATA ;
INFILE "c:\\temp\\x.dat" LRECL=6;
INPUT ID 1-3 SEX 4 KIDS 5-6 ;
LABEL ID = 'Case number' SEX = "R's sex"
  KIDS = '$("k" ^ 200)' ;
IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;
FORMAT SEX sexf. KIDS kidsf. ;
RUN ;
"""
const FW_DATA = "0011 2\n002298\n003199\n004199\n0052 0\n"

function fw_files(setup=FW_SETUP, data=FW_DATA)
    dir = mktempdir()
    write(joinpath(dir, "x.sas"), setup)
    write(joinpath(dir, "x.dat"), data)
    joinpath(dir, "x.dat"), joinpath(dir, "x.sas")
end

@testset "read_fixed_width" begin
    dat, sas = fw_files()
    t = read_fixed_width(dat, sas)
    @test names(t) == ["ID", "SEX", "KIDS"]
    @test t.ID == Int8[1, 2, 3, 4, 5]
    @test codes_of(t.KIDS) == UInt8[0, 1, 1, 1, 0]
    @test DataAPI.colmetadata(t, :SEX, "label") == "R's sex"
    @test DataAPI.colmetadata(t, :KIDS, "label") == "k"^200
    sets = DataAPI.metadata(t, "value_labels")
    @test sets[DataAPI.colmetadata(t, :KIDS, "value_labels")] == Dict(0.0 => "(0) None")
    @test !("warnings" in DataAPI.metadatakeys(t))

    t = read_fixed_width(dat, sas; recodes=:tagged)
    @test codes_of(t.KIDS) == UInt8[0, 2, 3, 3, 0]
    @test count(ismissing, t.KIDS) == 3
    labels = DataAPI.metadata(t, "value_labels")["kidsf"]
    @test labels[stata_key(".a")] == "(98) DK" && labels[stata_key(".b")] == "(99) Not ascertained"

    t = read_fixed_width(dat, sas; recodes=:none)
    @test t.KIDS == Int8[2, 98, 99, 99, 0]

    t = read_fixed_width(dat, sas; cols=[:KIDS, :ID], skip=1, n_max=2)
    @test names(t) == ["KIDS", "ID"] && t.ID == Int8[2, 3]

    @test_throws ArgumentError read_fixed_width(dat, sas; recodes=:letters)
    @test_throws ArgumentError read_fixed_width("no such file.dat", sas)
end

@testset "read_fixed_width warnings and errors" begin
    setup = "PROC FORMAT; VALUE f 1-5='low';\nDATA; INPUT X 1;\n" * join(("y$i = x * 2;" for i in 1:10), "\n")
    dat, sas = fw_files(setup, "1\n2\n")
    t = @test_logs (:warn, r"3 more") read_fixed_width(dat, sas)
    @test length(DataAPI.metadata(t, "warnings")) == 11

    dat, sas = fw_files("DATA;\nINPUT X 1. ;", "1\n")
    before = readdir(tempdir())
    err = try
        read_fixed_width(dat, sas)
        nothing
    catch e
        e
    end
    @test err isa DtaParser.DtaError
    @test occursin("setup line 2: INPUT form not supported", sprint(showerror, err))
    @test readdir(tempdir()) == before
end

# CDC's setups from 2006-2010 on put the PROC FORMAT step and the FORMAT
# statement each in a block comment; their lines end in CRLF until
# 2011-2013.
const FW_COMMENTED = [
    "/*-----------------------------------------------",
    " | PROC FORMAT:  creates user-defined formats; FORMAT: attaches them.",
    " | Sections for PROC FORMAT and FORMAT have been commented out.",
    " |----------------------------------------------*/",
    "* SAS PROC FORMAT;",
    "/*",
    "PROC FORMAT;",
    "VALUE sexf 1 = 'Boy' 2 = 'Girl' ;",
    "VALUE kidsf 0 = 'None' 98 = 'DK' ;",
    "QUIT;",
    "*/",
    "* SAS DATA, INFILE, INPUT STATEMENTS;",
    "DATA;",
    "INFILE \"data-filename\" LRECL=5;",
    "INPUT ID 1-2 SEX 3 KIDS 4-5 ;",
    "* SAS LABEL STATEMENT;",
    "LABEL ID = 'Case' SEX = 'Sex' KIDS = 'Kids' ;",
    "* SAS FORMAT STATEMENT;",
    "/*",
    "FORMAT",
    "   SEX sexf.",
    "   KIDS kidsf. ;",
    "*/",
    "RUN ;",
]
const FW_COMMENTED_DATA = ["01100", "02298"]

write_crlf(path, lines) = (write(path, join(lines .* "\r\n")); path)

function crlf_files(setup=FW_COMMENTED)
    dir = mktempdir()
    write_crlf(joinpath(dir, "x.dat"), FW_COMMENTED_DATA), write_crlf(joinpath(dir, "x.sas"), setup)
end

function kids_labels(t)
    name = DataAPI.colmetadata(t, :KIDS, "value_labels")
    isempty(name) ? nothing : DataAPI.metadata(t, "value_labels")[name]
end

@testset "read_fixed_width commented-out formats" begin
    dat, sas = crlf_files()
    t = read_fixed_width(dat, sas; recodes=:none)
    @test !("warnings" in DataAPI.metadatakeys(t))
    @test kids_labels(t) == Dict(0.0 => "None", 98.0 => "DK")
    off = read_fixed_width(dat, sas; recodes=:none, commented_formats=false)
    @test kids_labels(off) === nothing
    @test isempty(DataAPI.metadata(off, "value_labels"))
    @test off.KIDS == t.KIDS == Int8[0, 98]
    @test DataAPI.colmetadata(off, :KIDS, "label") == "Kids"

    # A commented PROC FORMAT alone, then a commented FORMAT alone.
    for setup in (FW_COMMENTED[setdiff(1:end, [19, 23])], FW_COMMENTED[setdiff(1:end, [6, 11])])
        dat, sas = crlf_files(setup)
        @test kids_labels(read_fixed_width(dat, sas; recodes=:none)) == Dict(0.0 => "None", 98.0 => "DK")
        @test kids_labels(read_fixed_width(dat, sas; recodes=:none, commented_formats=false)) === nothing
    end

    # Comments that mention PROC FORMAT stay comments; read as code, each
    # would end the DATA step before LABEL, or fail.
    for comment in ["/* PROC FORMAT: see the codebook; */", "/* PROC FORMAT; VALUE labels are below */",
                    "/* FORMAT statements: below; */"]
        dat, sas = crlf_files([FW_COMMENTED[1:15]; comment; FW_COMMENTED[17:end]])
        t = read_fixed_width(dat, sas; recodes=:none)
        @test !("warnings" in DataAPI.metadatakeys(t))
        @test DataAPI.colmetadata(t, :KIDS, "label") == "Kids"
    end
end

@testset "read_fixed_width with a setup in several files" begin
    # CDC's 2002 setups: the DATA step, LABEL, then PROC FORMAT and FORMAT.
    parts = [
        ["FILENAME datafile 'x.dat' ;", "DATA &dataset ;", "INFILE datafile LRECL=5;",
         "INPUT ID \$ 1-2 SEX 3 KIDS 4-5 ;", "RUN;"],
        ["LABEL", " /* SECTION A */", "  ID = \"RESPONDENT ID\"", "  KIDS = \"NUMBER OF KIDS\"", "  ;"],
        ["PROC FORMAT;", "VALUE SEXF 1 = \"BOY\" 2 = \"GIRL\" ;", "VALUE KIDSF 98 = \"DK\" ;", "RUN;",
         "FORMAT SEX SEXF. KIDS KIDSF. ;", "RUN;"],
    ]
    dir = mktempdir()
    paths = [write_crlf(joinpath(dir, "$i.sas"), p) for (i, p) in enumerate(parts)]
    joined = write_crlf(joinpath(dir, "all.sas"), reduce(vcat, parts))
    dat = write_crlf(joinpath(dir, "x.dat"), FW_COMMENTED_DATA)
    files = read_fixed_width(dat, paths; recodes=:none)
    one = read_fixed_width(dat, joined; recodes=:none)
    @test names(files) == names(one) == ["ID", "SEX", "KIDS"]
    @test all(isequal(getproperty(files, Symbol(c)), getproperty(one, Symbol(c))) for c in names(one))
    @test DataAPI.metadata(files, "value_labels") == DataAPI.metadata(one, "value_labels")
    @test DataAPI.metadata(files, "value_labels")["SEXF"] == Dict(1.0 => "BOY", 2.0 => "GIRL")
    for c in names(one)
        @test DataAPI.colmetadata(files, c, "label") == DataAPI.colmetadata(one, c, "label")
    end
    @test DataAPI.colmetadata(files, :KIDS, "label") == "NUMBER OF KIDS"
    @test !("warnings" in DataAPI.metadatakeys(files))
    write_crlf(paths[2], ["LABEL KIDS 3;"])
    err = try
        read_fixed_width(dat, paths)
        nothing
    catch e
        e
    end
    @test occursin("setup file 2 line 1: LABEL KIDS", sprint(showerror, err))
    @test_throws ArgumentError read_fixed_width(dat, String[])
end

@testset "read_fixed_width: QUIT ends a PROC step like RUN" begin
    dat, sas = fw_files("DATA; INPUT X 1;\nPROC FORMAT; VALUE f 1='one'; QUIT;\nFORMAT X f.;", "1\n2\n")
    t = read_fixed_width(dat, sas; recodes=:none)
    @test !("warnings" in DataAPI.metadatakeys(t))
    @test DataAPI.colmetadata(t, :X, "value_labels") == "f"
    @test DataAPI.metadata(t, "value_labels")["f"] == Dict(1.0 => "one")
end

@testset "read_fixed_width labels with stray quotes" begin
    setup = [
        "DATA; INPUT SALMX1 1 RING 2 C 3;",
        "LABEL",
        "  SALMX1 = \"FLAG INDICATING WHETHER \" SAME AS LAST MONTH\" WAS ORIGINAL ANSWER\"",
        "  RING = \"EVER USED RING OR \"NUVARING\"?\"",
        "  C 'no equals' ;",
    ]
    dir = mktempdir()
    sas = write_crlf(joinpath(dir, "x.sas"), setup)
    dat = write_crlf(joinpath(dir, "x.dat"), ["123"])
    t = @test_logs read_fixed_width(dat, sas)
    @test DataAPI.colmetadata(t, :SALMX1, "label") == "FLAG INDICATING WHETHER \" SAME AS LAST MONTH\" WAS ORIGINAL ANSWER"
    @test DataAPI.colmetadata(t, :RING, "label") == "EVER USED RING OR \"NUVARING\"?"
    @test DataAPI.colmetadata(t, :C, "label") == "no equals"
    @test !("warnings" in DataAPI.metadatakeys(t))
end
