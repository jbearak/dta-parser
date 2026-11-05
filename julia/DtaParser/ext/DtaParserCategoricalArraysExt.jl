module DtaParserCategoricalArraysExt

# read_parquet returns categorical columns as CategoricalArrays, and
# write_parquet writes them, when CategoricalArrays.jl is loaded.

using CategoricalArrays
using DtaParser: DtaParser, PqPrepared, PqColumn, W_CATEGORICAL, WriteError

# The element type of a categorical column read_parquet gives.
value_type() = CategoricalValue{String,UInt32}

# A CategoricalArray of `levels`, from level numbers (0 for missing).
function categorical(refs::Vector{UInt32}, levels::Vector{String}, ordered::Bool)
    pool = CategoricalPool{String,UInt32}(levels, ordered)
    any(==(0x00000000), refs) ? CategoricalArray{Union{Missing,String},1}(refs, pool) :
                                CategoricalArray{String,1}(refs, pool)
end

function DtaParser.prepare_parquet(name, x::CategoricalArray)
    lv = unwrap.(levels(x))
    all(l -> l isa AbstractString, lv) ||
        throw(WriteError("column $name: a categorical column is written as text, so its levels must be strings, " *
                         "not $(eltype(lv)); convert it with categorical(string.(x))"))
    refs = Vector{UInt32}(x.refs)
    col = PqColumn(W_CATEGORICAL, pointer(refs), C_NULL, C_NULL, C_NULL)
    PqPrepared(col, Any[refs], Dict{String,Any}("levels" => String.(lv), "ordered" => isordered(x)))
end

end
