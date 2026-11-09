# Writing Parquet files (plans 0018 and 0019): each column becomes a PqColumn
# pointing at Julia arrays (the column's own where its layout allows,
# such as a Vector{Float64} or a Vector{Date}, a converted copy
# otherwise), and one library call writes the file while GC.@preserve
# keeps them alive.

const W_KIND = Dict{DataType,UInt32}(Int8 => W_INT8, Int16 => W_INT16, Int32 => W_INT32, Int64 => W_INT64,
                                     Float32 => W_FLOAT, Float64 => W_DOUBLE, Bool => W_BOOL)

# A column ready to write: the C description, the arrays it points at,
# and what the metadata adds for it (levels, a zone).
struct PqPrepared
    col::PqColumn
    keep::Vector{Any}
    extra::Dict{String,Any}
end

pq_prepared(kind, values, codes; extra=Dict{String,Any}()) =
    PqPrepared(PqColumn(kind, values === nothing ? C_NULL : pointer(values),
                        codes === nothing ? C_NULL : pointer(codes), C_NULL, C_NULL),
               Any[values, codes], extra)

# The signed type an unsigned one is written as: one that holds every
# value.
wider(::Type{UInt8}) = Int16
wider(::Type{UInt16}) = Int32
wider(::Type{UInt32}) = Int64
wider(::Type{UInt64}) = Int64
wider(::Type{T}) where {T<:Integer} = Int64

function narrowed(name, values::AbstractVector{T}, codes) where {T<:Integer}
    T in keys(W_KIND) && values isa Vector && return values
    W = wider(T)
    out = Vector{W}(undef, length(values))
    for (i, v) in enumerate(values)
        if codes !== nothing && codes[i] != 0x00
            out[i] = zero(W)
        elseif typemin(W) <= v <= typemax(W)
            out[i] = W(v)
        else
            throw(WriteError("column $name: row $i holds $v, more than a 64-bit integer holds"))
        end
    end
    out
end

numbers_kind(::Type{T}) where {T} = W_KIND[T]

"""
    Datakit.prepare_parquet(name, x) -> PqPrepared

How `save_parquet` writes column `x`; the package's extensions add
methods for `CategoricalArray` and `ZonedDateTime` vectors. Internal.
"""
function prepare_parquet(name, x::DtaColumn{T}) where {T}
    if T <: AbstractFloat
        values = T === Float32 || T === Float64 ? x.values : Float64.(x.values)
        return pq_prepared(W_KIND[eltype(values)], values, x.codes)
    end
    values = narrowed(name, x.values, x.codes)
    pq_prepared(W_KIND[eltype(values)], values, x.codes)
end

prepare_parquet(name, x::SubArray) = prepare_parquet(name, copy(x))

function prepare_parquet(name, x::AbstractVector)
    T = eltype(x)
    S = nonmissingtype(T)
    n = length(x)
    if T === Missing || T === Union{}
        return pq_prepared(W_INT8, zeros(Int8, n), fill(0x01, n))
    elseif S <: Union{AbstractString,AbstractVector{UInt8}} || (S isa Union && all_text_or_bytes(S))
        return pq_strings(name, x, !(S <: AbstractString))
    elseif S <: Bool
        values, codes = split_missing(x, Bool)
        values isa Vector{Bool} || (values = Vector{Bool}(values .!= 0x00))
        return pq_prepared(W_BOOL, values, codes)
    elseif S <: Integer
        values, codes = split_missing(x, S)
        values = narrowed(name, values, codes)
        return pq_prepared(W_KIND[eltype(values)], values, codes)
    elseif S <: AbstractFloat
        F = S === Float32 ? Float32 : Float64
        S === F || S === Float16 || throw(WriteError("column $name: cannot write values of type $S; convert them to Float64"))
        values, codes = split_missing(x, F)
        return pq_prepared(W_KIND[F], values, codes)
    elseif S <: Date || S <: DateTime
        # Their memory is an Int64 count; a Vector{Date} or
        # Vector{DateTime} is written as it is.
        codes = missing_codes(x)
        values = x isa Vector{S} ? x : S[ismissing(d) ? S(1970) : d for d in x]
        return pq_prepared(S <: Date ? W_DATE : W_DATETIME, values, codes)
    end
    narrow = map(identity, x)
    if eltype(narrow) != T && !isabstracttype(nonmissingtype(eltype(narrow)))
        return prepare_parquet(name, narrow)
    end
    hint = S <: Dates.TimeType && S !== Time ? "; for a ZonedDateTime column, load TimeZones.jl" :
           S <: Time ? "; Parquet TIME columns are read, not written" : ""
    throw(WriteError("column $name: cannot write values of type $S$hint"))
end

# Text or bytes as one buffer of bytes and offsets. A column mixing text
# and bytes is written as bytes.
function pq_strings(name, x::AbstractVector, binary::Bool)
    n = length(x)
    total = 0
    for v in x
        ismissing(v) && continue
        total += v isa AbstractString ? ncodeunits(v) : length(v)
    end
    bytes = Vector{UInt8}(undef, total)
    offsets = Vector{UInt64}(undef, n + 1)
    codes = nothing
    at = 0
    offsets[1] = 0
    GC.@preserve bytes for (i, v) in enumerate(x)
        if ismissing(v)
            codes === nothing && (codes = zeros(UInt8, n))
            codes[i] = 0x01
        elseif v isa String
            len = ncodeunits(v)
            GC.@preserve v unsafe_copyto!(pointer(bytes, at + 1), pointer(v), len)
            at += len
        elseif v isa AbstractString
            s = String(v)
            len = ncodeunits(s)
            GC.@preserve s unsafe_copyto!(pointer(bytes, at + 1), pointer(s), len)
            at += len
        else
            copyto!(bytes, at + 1, v, 1, length(v))
            at += length(v)
        end
        offsets[i+1] = at
    end
    col = PqColumn(binary ? W_BINARY : W_TEXT, C_NULL, codes === nothing ? C_NULL : pointer(codes), pointer(bytes),
                   pointer(offsets))
    PqPrepared(col, Any[bytes, offsets, codes], Dict{String,Any}())
end

const COMPRESSIONS = (:snappy, :zstd, :gzip, :lz4_raw, :none)

"""
    save_parquet(path_or_io, table; label, notes, compression=:snappy, compression_level=nothing,
                 row_group_size=nothing, missing_letters=true, value_labels, column_labels,
                 column_formats, column_value_labels)

Write any Tables.jl table as a Parquet file that keeps its labels and
`.a` to `.z`, and return `path_or_io`. Every Parquet tool reads the
file; labels, formats, notes, value labels, factor levels and zones go
into the file's dta profile, which our readers read back. See
docs/julia.md, "Write a Parquet file".

Columns map to Parquet types:

- `Int8`, `Int16`: INT32 annotated INT(8) and INT(16); `Int32`: INT32;
  `Int64`: INT64. Unsigned integers are written as the next wider
  signed type (`UInt64` must fit an `Int64`).
- `Float32`, `Float64`: FLOAT, DOUBLE. `NaN` is a value, not missing.
- `Bool`: BOOLEAN.
- [`DtaColumn`](@ref): its type, with `.` as null and `.a` to `.z` as
  tagged NaNs; a column holding `.a` to `.z` is DOUBLE, its storage type
  recorded in the profile so that it reads back as it was.
- `Date`: DATE. `DateTime`: TIMESTAMP in milliseconds, not adjusted to
  UTC. `ZonedDateTime` (with TimeZones.jl loaded): TIMESTAMP in
  milliseconds, adjusted to UTC, with the zone in the profile.
- `String`: BYTE_ARRAY STRING; `Vector{UInt8}`: BYTE_ARRAY.
- `CategoricalArray` of strings (with CategoricalArrays.jl loaded):
  dictionary-encoded STRING with every level, in order, and whether it is
  ordered. A `CategoricalArray` cannot hold `.a` to `.z`; a
  categorical with them that [`read_parquet`](@ref) read as labelled
  numbers is written back as labelled numbers.
- `missing` in any column: a null.

Anything else is an error naming the column.

Metadata comes from the table through DataAPI when it has any (a
DataFrame from [`read_parquet`](@ref), `read_fixed_width` or
`DataFrame(read_dta(f))`, or a `DtaTable`): the table's
`"label"`, `"notes"`, `"timestamp"`, `"characteristics"`, `"sorted_by"`
and `"value_labels"`, and each column's `"label"`, `"format"` and
`"value_labels"`. The keyword arguments override it, as for DtaParser's
`write_dta`.

- `compression`: `:snappy` (default), `:zstd`, `:gzip`, `:lz4_raw` or
  `:none`; `compression_level` for zstd (1 to 22) and gzip (0 to 9).
- `row_group_size`: rows per row group; by default up to 262,144 rows
  and about 1 GiB of values.
- `missing_letters`: with `false`, `.a` to `.z` are written as plain
  nulls, for tools that count NaN as a value (DuckDB, polars, Spark);
  the letters are then lost.
"""
function save_parquet(dest, @nospecialize(table); label=nothing, notes=nothing, compression=:snappy,
                      compression_level=nothing, row_group_size=nothing, missing_letters::Bool=true,
                      value_labels=nothing, column_labels=nothing, column_formats=nothing, column_value_labels=nothing)
    Tables.istable(table) || throw(ArgumentError("save_parquet needs a Tables.jl table"))
    dest isa Union{AbstractString,IO} || throw(ArgumentError("save_parquet writes to a path or an IO, not $(typeof(dest))"))
    codec = Symbol(lowercase(string(compression)))
    codec in COMPRESSIONS ||
        throw(ArgumentError("compression must be :snappy, :zstd, :gzip, :lz4_raw or :none, not $(repr(compression))"))
    compression_level === nothing || compression_level isa Integer ||
        throw(ArgumentError("compression_level must be an integer or nothing"))
    row_group_size === nothing || (row_group_size isa Integer && row_group_size >= 1) ||
        throw(ArgumentError("row_group_size must be a whole number of rows, at least 1, or nothing"))

    cols = Tables.columns(table)
    names = [Symbol(n) for n in Tables.columnnames(cols)]
    T = typeof(table)
    has_meta = DataAPI.metadatasupport(T).read
    has_colmeta = DataAPI.colmetadatasupport(T).read
    tmeta(key, default) = has_meta ? DataAPI.metadata(table, key, default) : default
    cmeta(col, key) = has_colmeta ? string(DataAPI.colmetadata(table, col, key, "")) : ""
    pick(d, n, default) = d === nothing ? default : string(get(d, n, get(d, String(n), default)))

    columns = AbstractVector[Tables.getcolumn(cols, n) for n in names]
    nrows = isempty(columns) ? something(Tables.rowcount(cols), 0) : length(columns[1])
    prepared = PqPrepared[]
    described = Any[]
    for (n, x) in zip(names, columns)
        name = String(n)
        length(x) == nrows || throw(WriteError("column $name has $(length(x)) rows, not $nrows"))
        p = prepare_parquet(name, x)
        push!(prepared, p)
        d = Dict{String,Any}("name" => name,
                             "label" => pick(column_labels, n, cmeta(n, "label")),
                             "format" => pick(column_formats, n, cmeta(n, "format")),
                             "valueLabels" => pick(column_value_labels, n, cmeta(n, "value_labels")))
        merge!(d, p.extra)
        push!(described, d)
    end

    sets = value_labels === nothing ? tmeta("value_labels", Dict()) : value_labels
    present = Set(String.(names))
    chars = [Dict("variable" => string(c.variable), "name" => string(c.name), "value" => string(c.value))
             for c in tmeta("characteristics", []) if string(c.variable) == "_dta" || string(c.variable) in present]
    sorted = String[]
    for s in tmeta("sorted_by", Symbol[])
        string(s) in present || break
        push!(sorted, string(s))
    end
    doc = Dict(
        "label" => string(something(label, tmeta("label", ""))),
        "timestamp" => string(tmeta("timestamp", "")),
        "notes" => String[string(s) for s in something(notes, tmeta("notes", String[]))],
        "sort" => sorted,
        "characteristics" => chars,
        "valueLabels" => label_sets_json(sets),
        "columns" => described,
    )

    ccols = PqColumn[p.col for p in prepared]
    keep = [p.keep for p in prepared]
    target = dest isa AbstractString ? String(dest) : dest
    GC.@preserve keep ccols pq_write(target, nrows, ccols, json(doc); codec=String(codec), level=compression_level,
                                     rows=row_group_size === nothing ? 0 : Int(row_group_size),
                                     missing_letters=missing_letters)
    dest
end
