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
