# A workload run while the package precompiles, so that the first
# read_dta, read_meta and write_dta in a session do not wait for the
# compiler (they took about 0.1 to 0.5 s before). Skipped when the
# library is not built yet.

function workload()
    path, io = mktemp()
    close(io)
    try
        # Every storage type, with and without missing values (integers
        # large enough not to fit a smaller type).
        table = (b=Int8[1, 2], i=Int16[1, 1000], l=Int32[1, 100_000], f=Float32[1, 2], x=[1.5, 2.0],
                 bm=DtaColumn(Int8[1, 0], UInt8[0, 1]), im=DtaColumn(Int16[1000, 0], UInt8[0, 2]),
                 lm=DtaColumn(Int32[100_000, 0], UInt8[0, 1]), fm=DtaColumn(Float32[1, 0], UInt8[0, 1]),
                 xm=[1.5, NaN], s=["a", "bc"], day=[Date(2024, 1, 1), Date(2024, 1, 2)],
                 time=[DateTime(2024, 1, 1, 12), DateTime(2024, 1, 2)])
        write_dta(path, table; label="workload", value_labels=Dict("yn" => Dict(1 => "yes", ".a" => "no answer")),
                  column_value_labels=Dict(:b => "yn"))
        t = read_dta(path)
        write_dta(path, t)
        read_dta(path; cols=[:x, :s], skip=1, n_max=1)
        read_dta(path; cols=["x"])
        read_dta(path; skip=1, n_max=1)
        read_dta(path; dates=false)
        read_meta(path)
    finally
        rm(path; force=true)
    end
    nothing
end

if ccall(:jl_generating_output, Cint, ()) == 1
    __init__()
    # Mark what the workload compiles, even in Base, for the package's cache
    # (as PrecompileTools does).
    ccall(:jl_tag_newly_inferred_enable, Cvoid, ())
    try
        isempty(FNS) || workload()
    finally
        ccall(:jl_tag_newly_inferred_disable, Cvoid, ())
    end
    # The library's addresses belong to this process; __init__ finds them again.
    empty!(FNS)
end
