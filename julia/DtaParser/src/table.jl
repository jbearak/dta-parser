"""
    DtaTable

What [`read_dta`](@ref) returns: columns by name, as a Tables.jl table,
with the file's metadata through DataAPI.

`t.x` or `t[:x]` is column `x`. `DataFrame(t)` gives a DataFrame that
keeps the columns and metadata.

Table metadata (`metadata(t, key)`): `"label"`, `"timestamp"`,
`"release"`, `"byte_order"`, `"encoding"`, `"notes"` (a vector of
strings), `"characteristics"` (`(variable, name, value)` named tuples,
without notes), `"sorted_by"` (column names) and `"value_labels"`: a
`Dict` from each value label set's name to a `Dict` from
[`stata_key`](@ref) to text.

Column metadata (`colmetadata(t, col, key)`): `"label"`, `"format"`,
`"storage"` (such as `"byte"`, `"str12"`, `"strL"`) and `"value_labels"`
(the name of the column's value label set, or `""`).
"""
struct DtaTable <: Tables.AbstractColumns
    names::Vector{Symbol}
    columns::Vector{AbstractVector}
    lookup::Dict{Symbol,Int}
    nrows::Int
    meta::Dict{String,Any}
    colmeta::Dict{Symbol,Dict{String,Any}}
end

function DtaTable(names::Vector{Symbol}, columns::Vector{AbstractVector}, nrows::Int, meta, colmeta)
    DtaTable(names, columns, Dict(n => i for (i, n) in enumerate(names)), nrows, meta, colmeta)
end

Tables.istable(::Type{DtaTable}) = true
Tables.columnaccess(::Type{DtaTable}) = true
Tables.columns(t::DtaTable) = t
Tables.columnnames(t::DtaTable) = getfield(t, :names)
Tables.getcolumn(t::DtaTable, i::Int) = getfield(t, :columns)[i]
Tables.getcolumn(t::DtaTable, n::Symbol) = getfield(t, :columns)[getfield(t, :lookup)[n]]
Tables.getcolumn(t::DtaTable, ::Type{T}, i::Int, ::Symbol) where {T} = getfield(t, :columns)[i]
function Tables.schema(t::DtaTable)
    Tables.Schema(getfield(t, :names), [eltype(c) for c in getfield(t, :columns)])
end
Tables.rowcount(t::DtaTable) = getfield(t, :nrows)

Base.getindex(t::DtaTable, n::AbstractString) = Tables.getcolumn(t, Symbol(n))
Base.haskey(t::DtaTable, n::Symbol) = haskey(getfield(t, :lookup), n)
Base.length(t::DtaTable) = length(getfield(t, :names))
Base.size(t::DtaTable) = (getfield(t, :nrows), length(t))
Base.names(t::DtaTable) = String.(getfield(t, :names))

DataAPI.nrow(t::DtaTable) = getfield(t, :nrows)
DataAPI.ncol(t::DtaTable) = length(t)

DataAPI.metadatasupport(::Type{DtaTable}) = (read=true, write=false)
DataAPI.colmetadatasupport(::Type{DtaTable}) = (read=true, write=false)
DataAPI.metadatakeys(t::DtaTable) = keys(getfield(t, :meta))
function DataAPI.metadata(t::DtaTable, key::AbstractString; style::Bool=false)
    v = getfield(t, :meta)[key]
    style ? (v, :note) : v
end
function DataAPI.metadata(t::DtaTable, key::AbstractString, default; style::Bool=false)
    v = get(getfield(t, :meta), key, default)
    style ? (v, :note) : v
end
DataAPI.colmetadatakeys(t::DtaTable, col) = keys(getfield(t, :colmeta)[colname(t, col)])
DataAPI.colmetadatakeys(t::DtaTable) = (n => keys(getfield(t, :colmeta)[n]) for n in getfield(t, :names))
function DataAPI.colmetadata(t::DtaTable, col, key::AbstractString; style::Bool=false)
    v = getfield(t, :colmeta)[colname(t, col)][key]
    style ? (v, :note) : v
end
function DataAPI.colmetadata(t::DtaTable, col, key::AbstractString, default; style::Bool=false)
    v = get(getfield(t, :colmeta)[colname(t, col)], key, default)
    style ? (v, :note) : v
end

colname(t::DtaTable, col::Integer) = getfield(t, :names)[col]
colname(t::DtaTable, col) = Symbol(col)

function Base.show(io::IO, ::MIME"text/plain", t::DtaTable)
    label = getfield(t, :meta)["label"]
    print(io, DataAPI.nrow(t), "×", length(t), " DtaTable", isempty(label) ? "" : ": $label")
    for (n, c) in zip(getfield(t, :names), getfield(t, :columns))
        cm = getfield(t, :colmeta)[n]
        print(io, "\n  ", n, " ", cm["storage"], " ", typeof(c))
        isempty(cm["label"]) || print(io, "  \"", cm["label"], "\"")
    end
end
Base.show(io::IO, t::DtaTable) = print(io, DataAPI.nrow(t), "×", length(t), " DtaTable")
