module DtaParserDataFramesExt

using DataFrames
using DtaParser: DtaTable
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

end
