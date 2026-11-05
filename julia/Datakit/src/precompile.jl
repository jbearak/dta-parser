# A workload run while the package precompiles, so that the first
# read_parquet, read_parquet_info, save_parquet and read_fixed_width in a
# session do not wait for the compiler. It reads and saves a small file
# into a DataFrame. Skipped when DtaParser's library is not built.

function workload()
    dir = mktempdir()
    try
        pq = joinpath(dir, "w.parquet")
        df = DataFrame(b=Int8[1, 2], i=Int16[1, 1000], l=Int32[1, 100_000], f=Float32[1, 2], x=[1.5, 2.0],
                       n=[1, 2], bm=DtaColumn(Int8[1, 0], UInt8[0, 1]), im=DtaColumn(Int16[1000, 0], UInt8[0, 2]),
                       lm=DtaColumn(Int32[100_000, 0], UInt8[0, 1]), fm=DtaColumn(Float32[1, 0], UInt8[0, 1]),
                       xm=DtaColumn([1.5, 0.0], UInt8[0, 3]), xn=[1.5, missing], flag=[true, false],
                       s=["a", "bc"], sm=["a", missing], day=[Date(2024, 1, 1), Date(2024, 1, 2)],
                       time=[DateTime(2024, 1, 1, 12), DateTime(2024, 1, 2)])
        save_parquet(pq, df; label="workload", column_value_labels=Dict(:b => "yn"),
                     value_labels=Dict("yn" => Dict(1 => "yes", ".a" => "no answer")))
        p = read_parquet(pq)
        save_parquet(pq, p)
        read_parquet(pq; cols=[:x, :s], skip=1, n_max=1)
        read_parquet(read(pq); cols=["x"])
        read_parquet_info(pq)
        save_parquet(IOBuffer(), p; compression=:zstd)
        dat, sas = joinpath(dir, "w.dat"), joinpath(dir, "w.sas")
        write(sas, "PROC FORMAT; VALUE f 1='one';\nDATA; INPUT ID 1 X 2;\nIF X = 9 THEN X = .;\nFORMAT X f.;\n")
        write(dat, "11\n29\n")
        read_fixed_width(dat, sas; recodes=:tagged)
    finally
        rm(dir; recursive=true, force=true)
    end
    nothing
end

if ccall(:jl_generating_output, Cint, ()) == 1
    # As in DtaParser's precompile.jl: tag what the workload compiles, even
    # in other packages, so that this package's cache keeps it.
    tag = try
        cglobal(:jl_tag_newly_inferred_enable)
        true
    catch
        false
    end
    tag && ccall(:jl_tag_newly_inferred_enable, Cvoid, ())
    try
        built = try
            DtaParser.fn(:dta_abi_version)
            Internals.ABI_VERSION == DTAPARSER_ABI
        catch
            false
        end
        built && workload()
    finally
        tag && ccall(:jl_tag_newly_inferred_disable, Cvoid, ())
    end
end
