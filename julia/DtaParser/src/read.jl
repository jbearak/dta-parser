# Reading: the library calls `on_chunk` with each chunk of rows, and each
# column's builder copies its part into arrays sized for the whole read.

abstract type Builder end

mutable struct NumBuilder{T} <: Builder
    values::Vector{T}
    codes::Union{Nothing,Vector{UInt8}}
end

mutable struct StrBuilder <: Builder
    values::Vector{String}
    # Set once a binary strL appears.
    mixed::Union{Nothing,Vector{Union{String,Vector{UInt8}}}}
end

function builder(storage::AbstractString, n::Int)
    T = get(NUMBER_TYPES, storage, nothing)
    T === nothing ? StrBuilder(Vector{String}(undef, n), nothing) : NumBuilder{T}(Vector{T}(undef, n), nothing)
end

const NUMBER_TYPES = Dict("byte" => Int8, "int" => Int16, "long" => Int32, "float" => Float32, "double" => Float64)

function copy_chunk!(b::NumBuilder{T}, first::Int, n::Int, c::CColumn) where {T}
    n == 0 && return
    unsafe_copyto!(pointer(b.values, first + 1), Ptr{T}(c.values), n)
    if c.codes != C_NULL
        if b.codes === nothing
            b.codes = zeros(UInt8, length(b.values))
        end
        unsafe_copyto!(pointer(b.codes, first + 1), c.codes, n)
    end
end

function copy_chunk!(b::StrBuilder, first::Int, n::Int, c::CColumn)
    offsets = unsafe_wrap(Array, c.offsets, n + 1)
    if c.binary != C_NULL && b.mixed === nothing
        b.mixed = Vector{Union{String,Vector{UInt8}}}(undef, length(b.values))
        for i in 1:first
            b.mixed[i] = b.values[i]
        end
        b.values = String[]
    end
    out = b.mixed === nothing ? b.values : b.mixed
    @inbounds for i in 1:n
        start = offsets[i]
        len = offsets[i+1] - start
        if c.binary != C_NULL && unsafe_load(c.binary, i) != 0
            v = Vector{UInt8}(undef, len)
            len > 0 && unsafe_copyto!(pointer(v), c.bytes + start, len)
            out[first+i] = v
        else
            out[first+i] = unsafe_string(c.bytes + start, len)
        end
    end
end

finish(b::NumBuilder{T}) where {T} = b.codes === nothing ? b.values : DtaColumn{T}(b.values, b.codes)

function finish(b::StrBuilder)
    b.mixed === nothing && return b.values
    all(v -> v isa Vector{UInt8}, b.mixed) ? Vector{Vector{UInt8}}(b.mixed) : b.mixed
end

mutable struct ReadState
    builders::Vector{Builder}
    error::Any
end

function on_chunk(user::Ptr{Cvoid}, first::UInt64, n::UInt64, columns::Ptr{CColumn})::Cint
    state = unsafe_pointer_to_objref(user)::ReadState
    try
        for (k, b) in enumerate(state.builders)
            copy_chunk!(b, Int(first), Int(n), unsafe_load(columns, k))
        end
        return Cint(0)
    catch e
        # Exceptions must not unwind through the library.
        state.error = (e, catch_backtrace())
        return Cint(1)
    end
end

function read_rows!(f::File, cols::Vector{UInt32}, start::Int, count::Int, builders::Vector{Builder})
    state = ReadState(builders, nothing)
    err = zeros(UInt8, ERR_LEN)
    cb = @cfunction(on_chunk, Cint, (Ptr{Cvoid}, UInt64, UInt64, Ptr{CColumn}))
    n = GC.@preserve state ccall(fn(:dta_read), Int64,
        (Ptr{Cvoid}, Ptr{UInt32}, Csize_t, UInt64, UInt64, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{UInt8}, Csize_t),
        f.ptr, cols, length(cols), start, count, cb, pointer_from_objref(state), err, ERR_LEN)
    if state.error !== nothing
        e, bt = state.error
        Base.throw(CapturedException(e, bt))
    end
    n < 0 && throw(DtaError(error_text(err)))
    n
end

# The metadata JSON, as table and column metadata.
function metadata_of(doc)
    vars = doc["variables"]
    names = [Symbol(v["name"]) for v in vars]
    sets = Dict{String,Dict{Float64,String}}()
    for s in doc["valueLabels"]
        sets[s["name"]] = Dict{Float64,String}(stata_key(v) => text for (v, text) in s["labels"])
    end
    meta = Dict{String,Any}(
        "label" => doc["label"],
        "timestamp" => doc["timestamp"],
        "release" => Int(doc["release"]),
        "byte_order" => doc["byteOrder"],
        "encoding" => doc["encoding"],
        "notes" => Vector{String}(doc["notes"]),
        "characteristics" => [(variable=c["variable"], name=c["name"], value=c["value"]) for c in doc["characteristics"]],
        "sorted_by" => [names[Int(i)+1] for i in doc["sortedBy"]],
        "value_labels" => sets,
    )
    colmeta = Dict{Symbol,Dict{String,Any}}(
        Symbol(v["name"]) => Dict{String,Any}(
            "label" => v["label"], "format" => v["format"], "storage" => v["type"], "value_labels" => v["valueLabels"])
        for v in vars)
    names, meta, colmeta
end

"""
    read_meta(path; encoding=nothing) -> Dict{String,Any}

The file's metadata without its data: the table metadata [`DtaTable`](@ref)
lists, `"nrows"`, and `"columns"`, one `Dict` per variable with `"name"`
and the column metadata.
"""
function read_meta(path::AbstractString; encoding=nothing)
    doc = with_file(f -> parse_json(meta_json(f)), path, encoding)
    names, meta, colmeta = metadata_of(doc)
    meta["nrows"] = Int(doc["nobs"])
    meta["columns"] = [merge(Dict{String,Any}("name" => String(n)), colmeta[n]) for n in names]
    meta
end

"""
    read_dta(path; cols=nothing, skip=0, n_max=nothing, encoding=nothing, dates=true) -> DtaTable

Read a Stata `.dta` file of any release from 104 to 119.

- `cols`: the columns to read, by name (`Symbol` or `String`) or
  position, in the order wanted; all when `nothing`.
- `skip`, `n_max`: skip this many rows, then read at most `n_max`.
- `encoding`: how text in files before release 118 is decoded:
  `"windows-1252"` (the default), `"latin1"` or `"utf-8"`.
- `dates`: convert `%td` columns to `Date` and `%tc` columns to
  `DateTime`, `.` becoming `missing`. A column converts only when every
  value is a whole number in range and none is `.a` to `.z`; otherwise it
  stays numbers with its format. `%tC`, which counts leap seconds,
  always stays numbers.

Numeric columns are `Vector{T}` in their storage type (`Int8` byte,
`Int16` int, `Int32` long, `Float32` float, `Float64` double), or a
[`DtaColumn{T}`](@ref) when any value is missing. String columns are
`Vector{String}`; a strL column with binary values holds them as
`Vector{UInt8}`.
"""
function read_dta(path::AbstractString; cols=nothing, skip::Integer=0, n_max::Union{Nothing,Integer}=nothing,
                  encoding=nothing, dates::Bool=true)
    skip >= 0 || throw(ArgumentError("skip must be at least 0"))
    n_max === nothing || n_max >= 0 || throw(ArgumentError("n_max must be at least 0"))
    with_file(path, encoding) do f
        doc = parse_json(meta_json(f))
        all_names, meta, colmeta = metadata_of(doc)
        picked = select_columns(cols, all_names)
        nobs = Int(doc["nobs"])
        start = min(Int(skip), nobs)
        count = n_max === nothing ? nobs - start : min(Int(n_max), nobs - start)
        storage = [colmeta[all_names[i]]["storage"] for i in picked]
        builders = Builder[builder(s, count) for s in storage]
        read_rows!(f, UInt32.(picked .- 1), start, count, builders)
        names = all_names[picked]
        columns = AbstractVector[finish(b) for b in builders]
        if dates
            for (k, n) in enumerate(names)
                columns[k] = as_dates(columns[k], colmeta[n]["format"])
            end
        end
        kept = Dict(n => colmeta[n] for n in names)
        # The rows stay sorted by the leading sort keys that were read.
        sorted_by = meta["sorted_by"]
        cut = findfirst(!in(Set(names)), sorted_by)
        meta["sorted_by"] = cut === nothing ? sorted_by : sorted_by[1:cut-1]
        DtaTable(names, columns, count, meta, kept)
    end
end

function select_columns(cols, names::Vector{Symbol})
    cols === nothing && return collect(1:length(names))
    cols isa Union{Symbol,AbstractString,Integer} && (cols = [cols])
    lookup = Dict(n => i for (i, n) in enumerate(names))
    picked = map(collect(cols)) do c
        if c isa Integer
            1 <= c <= length(names) || throw(ArgumentError("there is no column $c; the file has $(length(names))"))
            Int(c)
        else
            get(lookup, Symbol(c)) do
                throw(ArgumentError("there is no column $c"))
            end
        end
    end
    allunique(picked) || throw(ArgumentError("a column is selected twice"))
    picked
end

const STATA_EPOCH_DATE = Date(1960, 1, 1)
const STATA_EPOCH = DateTime(1960, 1, 1)

# `%td` (and the older `%d`) and `%tc`, with or without `-` (left-aligned).
function date_kind(format::AbstractString)
    f = replace(format, r"^%-" => "%")
    startswith(f, "%td") || startswith(f, "%d") ? :date : startswith(f, "%tc") ? :datetime : nothing
end

function as_dates(col::AbstractVector, format::AbstractString)
    kind = date_kind(format)
    (kind === nothing || !(eltype(col) <: Union{Missing,Real})) && return col
    col isa DtaColumn && any(>(0x01), col.codes) && return col
    values = col isa DtaColumn ? col.values : col
    codes = col isa DtaColumn ? col.codes : nothing
    # Whole numbers small enough that the conversion is exact.
    limit = kind === :date ? 1.0e9 : 2.0^53
    for i in eachindex(values)
        (codes !== nothing && codes[i] != 0) && continue
        x = Float64(values[i])
        (isinteger(x) && abs(x) <= limit) || return col
    end
    T = kind === :date ? Date : DateTime
    convert1(x) = kind === :date ? STATA_EPOCH_DATE + Day(Int64(x)) : STATA_EPOCH + Millisecond(Int64(x))
    codes === nothing && return T[convert1(x) for x in values]
    Union{Missing,T}[codes[i] == 0 ? convert1(values[i]) : missing for i in eachindex(values)]
end
