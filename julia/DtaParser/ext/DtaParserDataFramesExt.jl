module DtaParserDataFramesExt

using DataFrames
using DtaParser: DtaParser, DtaTable, DtaColumn, read_dta, write_dta
import DataAPI, Tables

# sort!, permute! and invpermute! of a DataFrame move each column's
# elements one at a time, through this internal function of DataFrames;
# element by element, a letter would become `.`. Move the codes too.
if isdefined(DataFrames, :_cycle_permute!)
    function DataFrames._cycle_permute!(v::DtaColumn, p::AbstractVector{<:Integer})
        DataFrames._cycle_permute!(v.values, p)
        DataFrames._cycle_permute!(v.codes, p)
        v
    end
end

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
    path = tempname() * ".dta"
    try
        df = DataFrame((x=[1.5, 2.0], s=["a", "b"], i=Int8[1, 2]))
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
