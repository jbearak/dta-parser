module DtaParserDataFramesExt

using DataFrames
using DtaParser: DtaParser, DtaTable, read_dta, read_parquet, write_dta, write_parquet
import DataAPI, Tables

"""
    DataFrame(t::DtaTable; copycols=true)

A DataFrame of `t`'s columns, with its table and column metadata (style
`:note`, so it follows the columns through DataFrames' operations).
`DtaColumn`s stay `DtaColumn`s, keeping `.a` to `.z`.
"""
function DataFrames.DataFrame(t::DtaTable; copycols::Bool=true)
    names = Tables.columnnames(t)
    cols = [copycols ? copy(Tables.getcolumn(t, n)) : Tables.getcolumn(t, n) for n in names]
    df = DataFrame(cols, collect(names); copycols=false)
    for key in DataAPI.metadatakeys(t)
        metadata!(df, key, DataAPI.metadata(t, key); style=:note)
    end
    for n in names, key in DataAPI.colmetadatakeys(t, n)
        colmetadata!(df, n, key, DataAPI.colmetadata(t, n, key); style=:note)
    end
    df
end

# Loading DataFrames invalidates some of DtaParser's compiled code; run
# its workload again, with DataFrames, so that this extension's cache
# holds it and the first read in a session does not wait for the
# compiler.
# (As in DtaParser's precompile.jl, what the workload compiles is tagged
# so that the cache keeps it, DtaParser's methods included.)
function workload()
    DtaParser.workload()
    path = tempname() * ".parquet"
    try
        df = DataFrame((x=[1.5, 2.0], s=["a", "b"], i=Int8[1, 2]))
        write_parquet(path, df)
        DataFrame(read_parquet(path))
        write_dta(path, df)
        DataFrame(read_dta(path))
    finally
        rm(path; force=true)
    end
end

if ccall(:jl_generating_output, Cint, ()) == 1 && !isempty(DtaParser.FNS)
    tag = try
        cglobal(:jl_tag_newly_inferred_enable)
        true
    catch
        false
    end
    tag && ccall(:jl_tag_newly_inferred_enable, Cvoid, ())
    try
        workload()
    finally
        tag && ccall(:jl_tag_newly_inferred_disable, Cvoid, ())
    end
end

end
