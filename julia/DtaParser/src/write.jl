# Writing: each column becomes a CColumn pointing at Julia arrays (the
# column's own where its layout allows, a converted copy otherwise), and
# one library call writes the file while GC.@preserve keeps them alive.

struct Prepared
    col::CColumn
    keep::Vector{Any}
    storage::String
    # The format to use when the metadata has none that suits: "" for the
    # storage type's default.
    format::String
end

value_type(::Type{Int8}) = I8
value_type(::Type{Int16}) = I16
value_type(::Type{Int32}) = I32
value_type(::Type{Int64}) = I64
value_type(::Type{Float32}) = F32
value_type(::Type{Float64}) = F64
value_type(::Type{UInt8}) = U8
value_type(::Type{Bool}) = U8
value_type(::Type) = nothing

const STORAGE_CODE = Dict("byte" => BYTE, "int" => INT, "long" => LONG, "float" => FLOAT, "double" => DOUBLE)

struct WriteError <: Exception
    message::String
end
Base.showerror(io::IO, e::WriteError) = print(io, e.message)

function numbers(storage::String, values::Vector, codes::Union{Nothing,Vector{UInt8}}, format="")
    vt = value_type(eltype(values))
    if vt === nothing
        values = Float64.(values)
        vt = F64
    end
    codes_ptr = codes === nothing ? Ptr{UInt8}(C_NULL) : pointer(codes)
    col = CColumn(STORAGE_CODE[storage], vt, pointer(values), codes_ptr, C_NULL, C_NULL, C_NULL)
    Prepared(col, Any[values, codes], storage, format)
end

# Whether storage `s` holds every whole number from lo to hi exactly (the
# top of each integer range is kept for missing values).
fits(s, lo, hi) = s == "byte" ? -127 <= lo && hi <= 100 :
                  s == "int" ? -32767 <= lo && hi <= 32_740 :
                  s == "long" ? -2_147_483_647 <= lo && hi <= 2_147_483_620 :
                  s == "float" ? -2^24 <= lo && hi <= 2^24 :
                  s == "double" ? -2^53 <= lo && hi <= 2^53 : false

# `hint` if it holds lo to hi, else the smallest storage that does.
function integer_storage(name, lo, hi, hint)
    lo > hi && return haskey(STORAGE_CODE, hint) ? hint : "byte"
    haskey(STORAGE_CODE, hint) && fits(hint, lo, hi) && return hint
    for s in ("byte", "int", "long", "double")
        fits(s, lo, hi) && return s
    end
    throw(WriteError("column $name: $(abs(lo) > abs(hi) ? lo : hi) is beyond ±2^53, which Stata cannot hold exactly"))
end

function integer_range(values, codes)
    lo, hi = typemax(Int128), typemin(Int128)
    for i in eachindex(values)
        codes === nothing || codes[i] == 0 || continue
        v = Int128(values[i])
        lo = min(lo, v)
        hi = max(hi, v)
    end
    lo, hi
end

float_storage(::Type{Float32}, hint) = hint == "double" ? "double" : "float"
float_storage(::Type, hint) = "double"

const STORAGE_OF = Dict(Int8 => "byte", Int16 => "int", Int32 => "long", Float32 => "float", Float64 => "double")

# A DtaColumn of a storage type keeps it; of other integers, as integers.
function prepare(name, x::DtaColumn{T}, hint) where {T}
    if T <: AbstractFloat
        return numbers(float_storage(T, hint), x.values, x.codes)
    end
    haskey(STORAGE_OF, T) && return numbers(STORAGE_OF[T], x.values, x.codes)
    lo, hi = integer_range(x.values, x.codes)
    numbers(integer_storage(name, lo, hi, hint), x.values, x.codes)
end

prepare(name, x::DtaView, hint) = prepare(name, copy(x), hint)

function prepare(name, x::AbstractVector, hint)
    T = eltype(x)
    S = nonmissingtype(T)
    if T === Missing || T === Union{}
        return numbers(integer_storage(name, 1, 0, hint), zeros(Int8, length(x)), fill(0x01, length(x)))
    elseif S <: Union{AbstractString,AbstractVector{UInt8}} || (S isa Union && all_text_or_bytes(S))
        return strings(name, x, hint)
    elseif S <: Real
        values, codes = split_missing(x, S)
        if S <: AbstractFloat
            return numbers(float_storage(S, hint), values, codes)
        end
        lo, hi = integer_range(values, codes)
        return numbers(integer_storage(name, lo, hi, hint), values, codes)
    elseif S <: Union{Date,DateTime}
        # Days or milliseconds since 1960, as long or double unless the
        # metadata's storage type holds them.
        epoch, default, format = S <: Date ? (STATA_EPOCH_DATE, "long", "%td") : (STATA_EPOCH, "double", "%tc")
        counts = Int64[ismissing(d) ? 0 : Dates.value(d - epoch) for d in x]
        codes = missing_codes(x)
        lo, hi = integer_range(counts, codes)
        storage = haskey(STORAGE_CODE, hint) && fits(hint, lo, hi) ? hint : default
        fits(storage, lo, hi) || throw(WriteError("column $name: a date is too far from 1960 for Stata"))
        return numbers(storage, counts, codes, format)
    end
    # A vector of a wider type whose values are all one kind, such as
    # Vector{Any} of strings.
    narrowed = map(identity, x)
    if eltype(narrowed) != T && !isabstracttype(nonmissingtype(eltype(narrowed)))
        return prepare(name, narrowed, hint)
    end
    throw(WriteError("column $name: cannot write values of type $T"))
end

all_text_or_bytes(S) = all(t -> t <: Union{AbstractString,AbstractVector{UInt8}}, Base.uniontypes(S))

function missing_codes(x)
    any(ismissing, x) || return nothing
    UInt8[ismissing(v) ? 0x01 : 0x00 for v in x]
end

# Values in a plain Vector of S, borrowing `x` when it is one, and codes
# for its missing values.
function split_missing(x::AbstractVector, ::Type{S}) where {S}
    x isa Vector{S} && return x, nothing
    codes = missing_codes(x)
    values = S === Bool ? UInt8[ismissing(v) ? 0x00 : UInt8(v) for v in x] :
             S[ismissing(v) ? zero(S) : v for v in x]
    values, codes
end

function strings(name, x::AbstractVector, hint)
    n = length(x)
    total = 0
    binary = false
    for v in x
        if v isa AbstractVector{UInt8}
            binary = true
            total += length(v)
        elseif !ismissing(v)
            total += ncodeunits(v)
        end
    end
    bytes = Vector{UInt8}(undef, total)
    offsets = Vector{UInt64}(undef, n + 1)
    flags = binary ? zeros(UInt8, n) : UInt8[]
    at = 0
    offsets[1] = 0
    for (i, v) in enumerate(x)
        if v isa AbstractVector{UInt8}
            copyto!(bytes, at + 1, v, 1, length(v))
            at += length(v)
            flags[i] = 0x01
        elseif !ismissing(v)
            s = v isa String ? v : String(v)
            len = ncodeunits(s)
            GC.@preserve s bytes unsafe_copyto!(pointer(bytes, at + 1), pointer(s), len)
            at += len
        end
        offsets[i+1] = at
    end
    storage = binary || hint == "strL" ? "strL" : "str"
    col = CColumn(storage == "strL" ? STRL : STR, 0, C_NULL, C_NULL, pointer(bytes), pointer(offsets),
                  binary ? pointer(flags) : C_NULL)
    Prepared(col, Any[bytes, offsets, flags], storage, "")
end

const RESERVED = Set(["_all", "_b", "byte", "_coef", "_cons", "double", "float", "if", "in", "int", "long", "_n", "_N",
                      "_pi", "_pred", "_rc", "_skip", "strL", "using", "with"])

function check_name(name::AbstractString)
    ok = 1 <= length(name) <= 32 && !isdigit(first(name)) && all(c -> c == '_' || isletter(c) || isdigit(c), name) &&
         !(name in RESERVED) && match(r"^str[0-9]+$", name) === nothing
    ok || throw(WriteError("column name \"$name\" is not a valid Stata name: 1 to 32 letters, digits or _, " *
                           "not starting with a digit, and not a reserved word"))
end

numeric_format(f) = !isempty(f) && !endswith(f, "s")
string_format(f) = !isempty(f) && endswith(f, "s")

function choose_format(p::Prepared, given::AbstractString)
    if p.format == "%td"
        date_kind(given) === :date ? given : p.format
    elseif p.format == "%tc"
        date_kind(given) === :datetime ? given : p.format
    elseif p.storage in ("str", "strL")
        string_format(given) ? given : ""
    else
        numeric_format(given) ? given : ""
    end
end

function label_sets_json(sets)
    out = Any[]
    for (name, labels) in sets
        pairs = Any[]
        for (k, text) in labels
            key = stata_key(k)
            push!(pairs, Any[key_code(key) > 0 ? missing_name(key_code(key)) : key, String(text)])
        end
        push!(out, Dict("name" => String(name), "labels" => pairs))
    end
    out
end

stata_timestamp(t::DateTime) = Dates.format(t, "dd u yyyy HH:MM")

"""
    write_dta(path, table; label, notes, timestamp, value_labels,
              column_labels, column_formats, column_value_labels)

Write any Tables.jl table as a Stata release 118 file.

Columns map to Stata storage types as follows:

- `Bool`: byte.
- Integers: the smallest of byte, int and long holding every value
  (the top of each range is kept for missing values), else double; an
  error beyond ±2^53.
- `Float32`, `Float64`: float, double; `NaN` is `.`.
- [`DtaColumn`](@ref): its storage type and missing codes.
- `missing` in a numeric column: `.`.
- `Date`: long with format `%td`; `DateTime`: double (milliseconds) with
  `%tc`.
- Strings: strN up to 2045 bytes, else strL; `missing` is written as `""`.
- `Vector{UInt8}` values: binary strLs.

Anything else is an error naming the column, as is a column name Stata
cannot hold.

Metadata comes from the table through DataAPI when it has any (as a
[`DtaTable`](@ref) or a DataFrame made from one does): the table's
`"label"`, `"notes"`, `"characteristics"`, `"sorted_by"` and
`"value_labels"`, and each column's `"label"`, `"format"`,
`"value_labels"` and `"storage"` (used when the values fit it). Keyword
arguments override it: `value_labels` is a `Dict` from set name to a
`Dict` from value (a number or [`stata_key`](@ref)) to text;
`column_labels`, `column_formats` and `column_value_labels` are `Dict`s
from column name to text.
"""
function write_dta(path::AbstractString, table; label=nothing, notes=nothing, timestamp=nothing, value_labels=nothing,
                   column_labels=nothing, column_formats=nothing, column_value_labels=nothing)
    Tables.istable(table) || throw(ArgumentError("write_dta needs a Tables.jl table"))
    cols = Tables.columns(table)
    names = [Symbol(n) for n in Tables.columnnames(cols)]
    T = typeof(table)
    has_meta = DataAPI.metadatasupport(T).read
    has_colmeta = DataAPI.colmetadatasupport(T).read
    tmeta(key, default) = has_meta ? DataAPI.metadata(table, key, default) : default
    cmeta(col, key) = has_colmeta ? string(DataAPI.colmetadata(table, col, key, "")) : ""
    pick(d, n, default) = d === nothing ? default : string(get(d, n, get(d, String(n), default)))

    columns = [Tables.getcolumn(cols, n) for n in names]
    nrows = isempty(columns) ? something(Tables.rowcount(cols), 0) : length(columns[1])
    prepared = Prepared[]
    variables = Any[]
    for (n, x) in zip(names, columns)
        name = String(n)
        check_name(name)
        length(x) == nrows || throw(WriteError("column $name has $(length(x)) rows, not $nrows"))
        p = prepare(name, x, cmeta(n, "storage"))
        push!(prepared, p)
        push!(variables, Dict(
            "name" => name,
            "format" => choose_format(p, pick(column_formats, n, cmeta(n, "format"))),
            "label" => pick(column_labels, n, cmeta(n, "label")),
            "valueLabels" => pick(column_value_labels, n, cmeta(n, "value_labels"))))
    end

    sets = value_labels === nothing ? tmeta("value_labels", Dict()) : value_labels
    present = Set(String.(names))
    chars = [Dict("variable" => string(c.variable), "name" => string(c.name), "value" => string(c.value))
             for c in tmeta("characteristics", []) if string(c.variable) == "_dta" || string(c.variable) in present]
    # The leading sort keys whose columns are written.
    sorted = Int[]
    for s in tmeta("sorted_by", Symbol[])
        i = findfirst(==(Symbol(s)), names)
        i === nothing && break
        push!(sorted, i)
    end
    doc = Dict(
        "label" => string(something(label, tmeta("label", ""))),
        "timestamp" => string(something(timestamp, stata_timestamp(Dates.now()))),
        "notes" => String[string(s) for s in something(notes, tmeta("notes", String[]))],
        "variables" => variables,
        "valueLabels" => label_sets_json(sets),
        "characteristics" => chars,
        "sortedBy" => any(isnothing, sorted) ? Int[] : sorted .- 1,
    )

    ccols = CColumn[p.col for p in prepared]
    keep = [p.keep for p in prepared]
    err = zeros(UInt8, ERR_LEN)
    rc = GC.@preserve keep ccols ccall(fn(:dta_write), Cint,
        (Cstring, UInt64, Ptr{CColumn}, Csize_t, Cstring, Ptr{UInt8}, Csize_t),
        String(path), nrows, ccols, length(ccols), json(doc), err, ERR_LEN)
    rc == 0 || throw(WriteError(error_text(err)))
    path
end
