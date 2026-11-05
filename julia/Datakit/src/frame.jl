# A DataFrame of columns read, with the table's and the columns' metadata
# under DtaTable's keys, style :note, so that DataFrame(read_dta(f)) and
# read_parquet(g) look alike and the labels follow the columns through
# DataFrames' operations.

function frame(names::Vector{Symbol}, columns::Vector{AbstractVector}, meta::Dict{String,Any},
               colmeta::Dict{Symbol,Dict{String,Any}})
    df = DataFrame(columns, names; copycols=false)
    for (key, value) in meta
        metadata!(df, key, value; style=:note)
    end
    for (i, n) in enumerate(names)
        for (key, value) in colmeta[n]
            colmetadata!(df, i, key, value; style=:note)
        end
    end
    df
end
