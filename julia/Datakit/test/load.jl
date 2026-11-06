# Loading: the check of DtaParser's library interface, the re-exports,
# and the precompile workload.

using Datakit, DtaParser, Test

@testset "load" begin
    @test Datakit.DTAPARSER_ABI == DtaParser.Internals.ABI_VERSION
    @test Datakit.check_abi() === true
    # A DtaParser whose library interface differs stops with a message
    # naming both versions and the reinstall.
    err = try Datakit.check_abi(Datakit.DTAPARSER_ABI + 1) catch e e end
    msg = sprint(showerror, err)
    @test occursin("version $(Datakit.DTAPARSER_ABI)", msg) && occursin("has version $(Datakit.DTAPARSER_ABI + 1)", msg)
    @test occursin("Pkg.develop(path=\"julia/DtaParser\")", msg) && occursin("Pkg.build(\"DtaParser\")", msg)
    # The re-exports are DtaParser's own.
    @test Datakit.DtaColumn === DtaParser.DtaColumn && Datakit.stata_code === DtaParser.stata_code
    @test Datakit.set_stata_code! === DtaParser.set_stata_code! && Datakit.stata_key === DtaParser.stata_key
    # Every DtaParser export is Datakit's, the same object, so `using
    # Datakit` alone reads and writes .dta.
    for name in names(DtaParser)
        name === :DtaParser && continue
        @test name in names(Datakit) && getfield(Datakit, name) === getfield(DtaParser, name)
    end
    script = """
        using Datakit, DataFrames
        p = tempname() * ".dta"
        write_dta(p, DataFrame(id = [1, 2]))
        t = read_dta(p)
        print(t isa DtaTable, " ", DataFrame(t).id, " ", isdefined(Main, :DtaParser))
    """
    out = read(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $script`, String)
    @test out == "true Int8[1, 2] false"
    # DtaParser no longer exports Parquet.
    @test !(:read_parquet in names(DtaParser)) && !(:write_parquet in names(DtaParser))
    @test !(:read_fixed_width in names(DtaParser))
    # The workload runs while the package precompiles; it must work on
    # its own too.
    @test Datakit.workload() === nothing
end
