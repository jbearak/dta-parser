# Reading Parquet files (plans 0018 and 0019). DtaParser's library
# decodes each column straight into vectors allocated here: numbers into
# a Vector of the element type returned (Date, DateTime and Time through
# their Int64 counts), categoricals as level numbers, and text one column
# chunk at a time through a callback, one String per distinct value of a
# dictionary-encoded chunk. What each Parquet type becomes is plan
# 0018's "Exactness" table, Julia column. The columns become a DataFrame
# (frame.jl).

const OUT_KIND = Dict{DataType,UInt32}(Int8 => PQ_I8, Int16 => PQ_I16, Int32 => PQ_I32, Int64 => PQ_I64,
                                       Float32 => PQ_F32, Float64 => PQ_F64, UInt8 => PQ_U8, UInt16 => PQ_U16,
                                       UInt32 => PQ_U32, UInt64 => PQ_U64, Bool => PQ_U8)

# Days from 0000-12-31 to 1970-01-01, and milliseconds; and from 1960 to
# 1970, Stata's epoch to Parquet's.
const DAYS_1970 = 719_163
const MS_1970 = 62_135_683_200_000
const DAYS_1960_TO_1970 = 3653
const SECONDS_1960_TO_1970 = 315_619_200

# ---------------------------------------------------------------- opening

mutable struct PqFile
    ptr::Ptr{Cvoid}
end

# Run g on the open file. `source` is a path, an IO (read whole) or bytes,
# which stay alive while g runs.
function with_parquet(g, source, nested_skip::Bool)
    if source isa AbstractString
        return with_pq_open(g, String(source), C_NULL, 0, nested_skip)
    end
    bytes = source isa Vector{UInt8} ? source :
            source isa AbstractVector{UInt8} ? Vector{UInt8}(source) :
            source isa IO ? read(source) :
            throw(ArgumentError("source must be a path, an IO or a Vector{UInt8}, not $(typeof(source))"))
    GC.@preserve bytes with_pq_open(g, nothing, pointer(bytes), length(bytes), nested_skip)
end

function with_pq_open(g, path, ptr, len, nested_skip)
    f = PqFile(path === nothing ? pq_open(ptr, len, nested_skip) : pq_open(path, nested_skip))
    try
        g(f)
    finally
        pq_close(f.ptr)
        f.ptr = C_NULL
    end
end

pq_info(f::PqFile) = parse_json(pq_info_json(f.ptr))

str_or(x, default="") = x === nothing ? default : String(x)

# ---------------------------------------------------------------- types

# How one column is read: the element type returned and the output the
# library fills.
struct Plan
    name::Symbol
    index::Int          # 0-based, in the file's columns
    info::Dict{String,Any}
    how::Symbol         # :number, :date, :timestamp, :time, :logical_date, :logical_timestamp, :levels,
                        # :letter_levels, :text, :binary
    T::DataType         # the element type of the values buffer
    codes::Bool         # whether a missing code per row is needed
end

const NUMBER_KIND = Dict("int8" => Int8, "int16" => Int16, "int32" => Int32, "int64" => Int64, "uint8" => UInt8,
                         "uint16" => UInt16, "uint32" => UInt32, "uint64" => UInt64, "float" => Float32,
                         "double" => Float64, "bool" => Bool)
const STORAGE_TYPE = Dict("byte" => Int8, "int" => Int16, "long" => Int32, "float" => Float32)

function plan_of(info, index::Int, decimal::Symbol)
    name = Symbol(info["name"])
    kind = info["kind"]::String
    nulls = info["nulls"] === true
    if kind == "nested"
        throw(ArgumentError("column \"$name\" is nested (a list, map or group), which is not read"))
    elseif kind == "unsupported"
        throw(DtaError("column \"$name\" is $(info["why"])"))
    elseif kind == "double"
        storage = info["storage"]
        logical = info["logical"]
        logical == "date" && return Plan(name, index, info, :logical_date, Float64, true)
        logical == "timestamp" && return Plan(name, index, info, :logical_timestamp, Float64, true)
        # A categorical holding .a to .z (plan 0022): level numbers from 1,
        # read as labelled numbers, since a CategoricalArray cannot hold
        # the letters.
        logical == "categorical" && return Plan(name, index, info, :letter_levels, Float64, true)
        T = storage === nothing ? Float64 : STORAGE_TYPE[storage]
        # A DOUBLE column may hold .a to .z as tagged NaNs.
        return Plan(name, index, info, :number, T, true)
    elseif haskey(NUMBER_KIND, kind)
        return Plan(name, index, info, :number, NUMBER_KIND[kind], nulls)
    elseif kind == "date"
        return Plan(name, index, info, :date, Int64, nulls)
    elseif kind == "timestamp"
        return Plan(name, index, info, :timestamp, Int64, nulls)
    elseif kind == "time"
        return Plan(name, index, info, :time, Int64, nulls)
    elseif kind == "decimal"
        decimal === :string && return Plan(name, index, info, :text, String, false)
        return Plan(name, index, info, :number, Float64, nulls)
    elseif kind == "text"
        info["levels"] === nothing || return Plan(name, index, info, :levels, UInt32, false)
        return Plan(name, index, info, :text, String, false)
    elseif kind == "binary"
        return Plan(name, index, info, :binary, Vector{UInt8}, false)
    end
    throw(DtaError("column \"$name\" has a type this version does not know: $kind"))
end

# ---------------------------------------------------------------- text

# The text of one column, gathered chunk by chunk.
mutable struct TextSink{T}
    values::Vector{T}
    missing::Union{Nothing,Vector{Bool}}
    width::Int
end

TextSink{T}(n::Int) where {T} = TextSink{T}(Vector{T}(undef, n), nothing, 0)

@inline function chunk_value(::Type{String}, bytes::Ptr{UInt8}, start::Int, len::Int)
    len == 0 ? "" : unsafe_string(bytes + start, len)
end
@inline function chunk_value(::Type{Vector{UInt8}}, bytes::Ptr{UInt8}, start::Int, len::Int)
    v = Vector{UInt8}(undef, len)
    len > 0 && unsafe_copyto!(pointer(v), bytes + start, len)
    v
end

empty_value(::Type{String}) = ""
empty_value(::Type{Vector{UInt8}}) = UInt8[]

function mark_missing!(s::TextSink{T}, i::Int) where {T}
    s.missing === nothing && (s.missing = zeros(Bool, length(s.values)))
    s.missing[i] = true
    s.values[i] = empty_value(T)
end

function add_chunk!(s::TextSink{T}, first::Int, rows::Int, bytes::Ptr{UInt8}, ends::Ptr{Csize_t}, nvalues::Int,
                    codes::Ptr{UInt32}, miss::Ptr{UInt8}) where {T}
    if codes != C_NULL
        # One value per distinct entry, shared by the rows that hold it.
        dict = Vector{T}(undef, nvalues)
        start = 0
        width = s.width
        @inbounds for i in 1:nvalues
            stop = Int(unsafe_load(ends, i))
            dict[i] = chunk_value(T, bytes, start, stop - start)
            width = max(width, stop - start)
            start = stop
        end
        s.width = width
        values = s.values
        @inbounds for r in 1:rows
            c = unsafe_load(codes, r)
            if c == typemax(UInt32)
                mark_missing!(s, first + r)
            else
                values[first+r] = dict[c+1]
            end
        end
    else
        start = 0
        width = s.width
        values = s.values
        @inbounds for r in 1:rows
            stop = Int(unsafe_load(ends, r))
            if miss != C_NULL && unsafe_load(miss, r) != 0x00
                mark_missing!(s, first + r)
            else
                values[first+r] = chunk_value(T, bytes, start, stop - start)
                width = max(width, stop - start)
            end
            start = stop
        end
        s.width = width
    end
    nothing
end

function finish(s::TextSink{T}) where {T}
    s.missing === nothing && return s.values
    out = Vector{Union{Missing,T}}(s.values)
    for i in eachindex(out)
        s.missing[i] && (out[i] = missing)
    end
    out
end

mutable struct PqReadState
    sinks::Vector{Any}
    error::Any
end

function on_pq_text(user::Ptr{Cvoid}, k::Csize_t, first::UInt64, rows::UInt64, bytes::Ptr{UInt8}, ends::Ptr{Csize_t},
                    nvalues::Csize_t, codes::Ptr{UInt32}, miss::Ptr{UInt8})::Cint
    state = unsafe_pointer_to_objref(user)::PqReadState
    try
        add_chunk!(state.sinks[k+1], Int(first), Int(rows), bytes, ends, Int(nvalues), codes, miss)
        return Cint(0)
    catch e
        # Exceptions must not unwind through the library.
        state.error = (e, catch_backtrace())
        return Cint(1)
    end
end

# ---------------------------------------------------------------- after the read

# Numbers: a DtaColumn when a row read holds .a to .z, which only it can
# keep; else a Vector{T}, or a Vector{Union{Missing,T}} when a row is `.`.
function numbers_of(values::Vector{T}, codes) where {T}
    codes === nothing && return values
    any(>(0x01), codes) && return DtaColumn{T}(values, codes)
    with_missing(values, codes)
end

# A vector of `T` from values, with missing where the code is not 0.
function with_missing(values::Vector{T}, codes) where {T}
    (codes === nothing || !any(!=(0x00), codes)) && return values
    out = Vector{Union{Missing,T}}(values)
    @inbounds for i in eachindex(codes)
        codes[i] == 0x00 || (out[i] = missing)
    end
    out
end

# Int64 counts read into the memory of a Vector{S} (Date, DateTime,
# Time), changed in place by `f`.
function counts_in_place!(f, v::Vector)
    GC.@preserve v begin
        p = Ptr{Int64}(pointer(v))
        @inbounds for i in 1:length(v)
            unsafe_store!(p, f(unsafe_load(p, i), i), i)
        end
    end
    v
end

const PER_MS = Dict("ms" => 1, "us" => 1_000, "ns" => 1_000_000)
const UNIT_NAME = Dict("us" => "microseconds", "ns" => "nanoseconds")

# The call that keeps a timestamp below a millisecond, for the error.
function truncate_call(source, kwargs)
    src = source isa AbstractString ? repr(String(source)) : "source"
    parts = String[]
    for (k, v) in pairs(kwargs)
        k === :timestamps && continue
        push!(parts, "$k = $(repr(v))")
    end
    push!(parts, "timestamps = :truncate")
    "read_parquet($src; $(join(parts, ", ")))"
end

# Milliseconds since 1970 of a TIMESTAMP's counts, as DateTime's
# milliseconds since 0000-12-31, in place.
function timestamps!(v::Vector{DateTime}, codes, unit::String, truncate::Bool, name, call)
    per = PER_MS[unit]
    counts_in_place!(v) do x, i
        if per != 1 && (codes === nothing || codes[i] == 0x00)
            if !truncate && x % per != 0
                throw(DtaError("column \"$name\": row $i is $x $(UNIT_NAME[unit]), which is not a whole number of " *
                               "milliseconds, all a DateTime holds; read with $call to drop what is below a millisecond"))
            end
            x = fld(x, per)
        elseif per != 1
            x = 0
        end
        x + MS_1970
    end
end

# Whether TimeZones.jl or CategoricalArrays.jl is loaded, through this
# package's extension for it.
tz_ext() = Base.get_extension(@__MODULE__, :DatakitTimeZonesExt)
cat_ext() = Base.get_extension(@__MODULE__, :DatakitCategoricalArraysExt)

const UTC_NAMES = ("UTC", "Etc/UTC", "Z", "+00:00", "GMT", "Etc/GMT", "UCT", "Universal", "Zulu")

# ---------------------------------------------------------------- metadata

function label_sets_of(doc)
    sets = Dict{String,Dict{Float64,String}}()
    for s in doc["valueLabels"]
        sets[s["name"]] = label_set(s["labels"])
    end
    sets
end

# Value labels apply to numbers that are not dates, times or categoricals,
# as read_dta keeps them, and to a categorical holding .a to .z, read as
# labelled numbers.
labels_apply(p::Plan) = p.how === :number || p.how === :letter_levels

function storage_of(p::Plan, width::Int=-1)
    p.how === :number && return get(STORAGE_OF, p.T, p.T === Bool ? "byte" : "")
    p.how === :letter_levels && return "double"
    p.how === :date && return "long"
    p.how === :timestamp && return "double"
    p.how === :text && return width < 0 ? "" : width > 2045 ? "strL" : "str$(max(width, 1))"
    p.how === :binary && return "strL"
    ""
end

function column_meta_of(p::Plan, sets, width::Int=-1)
    info = p.info
    set = str_or(info["value_labels"])
    Dict{String,Any}(
        "label" => str_or(info["label"]),
        "format" => str_or(info["format"]),
        "storage" => storage_of(p, width),
        "value_labels" => labels_apply(p) && haskey(sets, set) ? set : "",
    )
end

function table_meta_of(doc, names::Vector{Symbol})
    sets = label_sets_of(doc)
    sort = Symbol.(doc["sort"])
    cut = findfirst(!in(Set(names)), sort)
    Dict{String,Any}(
        "label" => str_or(doc["label"]),
        "timestamp" => str_or(doc["timestamp"]),
        "notes" => Vector{String}(doc["notes"]),
        "characteristics" => [(variable=c["variable"], name=c["name"], value=c["value"]) for c in doc["characteristics"]],
        "sorted_by" => cut === nothing ? sort : sort[1:cut-1],
        "value_labels" => sets,
    )
end

function warn_profile(doc)
    for w in doc["warnings"]
        @warn w
    end
end

# ---------------------------------------------------------------- selecting

function pick_columns(cols, doc, nested::Symbol)
    infos = doc["columns"]::Vector{Any}
    data = [i for i in eachindex(infos) if infos[i]["role"] == "data"]
    if cols === nothing
        nest = [infos[i]["name"] for i in eachindex(infos) if infos[i]["role"] != "data"]
        if !isempty(nest) && nested === :error
            throw(ArgumentError("the file has nested columns, which are not read: " *
                                join(("\"$n\"" for n in nest), ", ") *
                                "; select the columns wanted with cols, or pass nested = :skip"))
        end
        return data
    end
    cols isa Union{Symbol,AbstractString,Integer} && (cols = [cols])
    lookup = Dict{String,Int}()
    for i in reverse(eachindex(infos))
        lookup[infos[i]["name"]] = i
    end
    picked = map(collect(cols)) do c
        if c isa Integer
            1 <= c <= length(data) || throw(ArgumentError("there is no column $c; the file has $(length(data))"))
            data[c]
        else
            get(lookup, String(c)) do
                names = [infos[i]["name"] for i in data]
                shown = join(("\"$n\"" for n in first(names, 20)), ", ")
                more = length(names) > 20 ? " and $(length(names) - 20) more" : ""
                throw(ArgumentError("column \"$c\" is not in the file; its columns are $shown$more"))
            end
        end
    end
    allunique(picked) || throw(ArgumentError("a column is selected twice"))
    picked
end

# ---------------------------------------------------------------- read

"""
    read_parquet(source; cols=nothing, skip=0, n_max=nothing, timestamps=:error,
                 decimal=:float, nested=:error) -> DataFrame

Read a Parquet file into a `DataFrame`, keeping what
[`save_parquet`](@ref) (or R's and Python's datakit) stored: variable
and value labels, display formats, notes, `.a` to `.z` (as
[`DtaColumn`](@ref) codes), categoricals and time zones. Files from
other tools read too. See docs/julia.md, "Read a Parquet file".

Labels are metadata with style `:note`, under the keys
`DataFrame(read_dta(f))` has: `colmetadata(df, :x, "label")`,
`"format"`, `"value_labels"` (the name of the column's set) and
`"storage"`; `metadata(df, "label")`, `"notes"`, `"timestamp"`,
`"characteristics"`, `"sorted_by"` and `"value_labels"` (every set: a
`Dict` from set name to a `Dict` from [`dta_key`](@ref) to text).

`source` is a path, an `IO` (read to its end) or a `Vector{UInt8}`
holding a whole file.

- `cols`: names (`Symbol` or `String`) or positions, in the order wanted;
  every column when `nothing`. A name the file does not have is an
  `ArgumentError` listing the names it has.
- `skip`, `n_max`: skip this many rows, then read at most `n_max`. Only
  the row groups and pages holding the rows are read.
- `timestamps`: `:error` (default) or `:truncate`. A `DateTime` holds
  milliseconds; a microsecond or nanosecond timestamp that is not a
  whole number of milliseconds is an error naming the column and row,
  unless `:truncate` drops what is below a millisecond. pandas and
  pyarrow write microseconds, so files from them often need
  `timestamps = :truncate`.
- `decimal`: `:float` (default) reads DECIMAL as `Float64`, and a value
  with more than 15 significant digits is an error; `:string` keeps
  every digit as text.
- `nested`: `:error` (default) or `:skip`. Lists, maps and structs are
  not read; with `:skip`, a read of every column leaves them out.

Element types: Parquet's integers, floats and booleans as the same Julia
type (`Int8` to `Int64`, `UInt8` to `UInt64`, `Float32`, `Float64`,
`Bool`); a column our writer widened to DOUBLE for `.a` to `.z` as its
storage type again. A numeric column whose rows read hold any of `.a`
to `.z` is a [`DtaColumn`](@ref), which keeps them; any other column
with a missing value is a `Vector{Union{Missing,T}}`. A date or
timestamp column whose rows read hold `.a` to `.z` is a `DtaColumn` of
Stata's numbers: days since 1960 with a `%td` format, or milliseconds
since 1960 with `%tc`. DATE as `Date`, TIMESTAMP and INT96 as
`DateTime` (`ZonedDateTime` when the file gives a zone and TimeZones.jl
is loaded), TIME as `Dates.Time`, text as `String`, bytes as
`Vector{UInt8}`, categoricals as `CategoricalArray` when
CategoricalArrays.jl is loaded (else `String`, with one warning).

A categorical holding `.a` to `.z` (written by Python's or TypeScript's
datakit as DOUBLE level numbers) is labelled numbers, since a
`CategoricalArray` cannot hold the letters: the level numbers 1 to k as
`Float64` (a `DtaColumn` when the rows read hold a letter), with
`colmetadata(df, :x, "value_labels")` naming a set that labels 1 to k
with the levels (and any labels on letters). A value in such a column
that is not a level number reads as `.`, with one warning per call
naming the column and the first such row.
"""
function read_parquet(source; cols=nothing, skip::Integer=0, n_max::Union{Nothing,Integer}=nothing,
                      timestamps::Symbol=:error, decimal::Symbol=:float, nested::Symbol=:error)
    skip >= 0 || throw(ArgumentError("skip must be at least 0"))
    n_max === nothing || n_max >= 0 || throw(ArgumentError("n_max must be at least 0"))
    timestamps in (:error, :truncate) || throw(ArgumentError("timestamps must be :error or :truncate, not $(repr(timestamps))"))
    decimal in (:float, :string) || throw(ArgumentError("decimal must be :float or :string, not $(repr(decimal))"))
    nested in (:error, :skip) || throw(ArgumentError("nested must be :error or :skip, not $(repr(nested))"))
    kwargs = (; (k => v for (k, v) in ((:cols, cols), (:skip, skip), (:n_max, n_max), (:decimal, decimal), (:nested, nested))
                 if !(v === nothing || (k === :skip && v == 0) || (k === :decimal && v === :float) || (k === :nested && v === :error)))...)
    with_parquet(source, nested === :skip) do f
        doc = pq_info(f)
        warn_profile(doc)
        picked = pick_columns(cols, doc, nested)
        infos = doc["columns"]::Vector{Any}
        plans = Plan[plan_of(infos[i], i - 1, decimal) for i in picked]
        nrows = Int(doc["rows"])
        start = min(Int(skip), nrows)
        count = n_max === nothing ? nrows - start : min(Int(n_max), nrows - start)
        read_plans(f, plans, start, count, doc, timestamps === :truncate, truncate_call(source, kwargs))
    end
end

function read_plans(f::PqFile, plans::Vector{Plan}, start::Int, count::Int, doc, truncate::Bool, call)
    n = length(plans)
    buffers = Vector{Any}(undef, n)
    codes = Vector{Any}(nothing, n)
    sinks = Vector{Any}(nothing, n)
    outputs = Vector{PqOutput}(undef, n)
    for (k, p) in enumerate(plans)
        if p.how === :text || p.how === :binary
            sinks[k] = TextSink{p.T}(count)
            outputs[k] = PqOutput(PQ_TEXT, 0, 0, C_NULL, C_NULL)
            continue
        end
        buf = p.how === :date ? Vector{Date}(undef, count) :
              p.how === :timestamp ? Vector{DateTime}(undef, count) :
              p.how === :time ? Vector{Time}(undef, count) :
              Vector{p.T}(undef, count)
        buffers[k] = buf
        c = p.codes ? zeros(UInt8, count) : nothing
        codes[k] = c
        cptr = c === nothing ? Ptr{UInt8}(C_NULL) : pointer(c)
        outputs[k] = p.how === :levels ? PqOutput(PQ_LEVELS, 1, 0, pointer(buf), C_NULL) :
                     PqOutput(p.how in (:date, :timestamp, :time) ? PQ_I64 : OUT_KIND[p.T], 0, 0, pointer(buf), cptr)
    end
    state = PqReadState(sinks, nothing)
    cb = @cfunction(on_pq_text, Cint, (Ptr{Cvoid}, Csize_t, UInt64, UInt64, Ptr{UInt8}, Ptr{Csize_t}, Csize_t, Ptr{UInt32}, Ptr{UInt8}))
    idx = UInt32[p.index for p in plans]
    got, text = GC.@preserve buffers codes state outputs pq_read(f.ptr, idx, start, count, outputs, cb,
                                                                   pointer_from_objref(state))
    if state.error !== nothing
        e, bt = state.error
        Base.throw(CapturedException(e, bt))
    end
    got < 0 && throw(DtaError(read_error(text)))
    rep = parse_json(text)

    sets = label_sets_of(doc)
    names = Symbol[p.name for p in plans]
    columns = Vector{AbstractVector}(undef, n)
    colmeta = Dict{Symbol,Dict{String,Any}}()
    zoneless = String[]
    plain_cats = String[]
    bad = get(rep, "bad", nothing)
    for (k, p) in enumerate(plans)
        cm = column_meta_of(p, sets)
        columns[k] = if p.how === :number
            numbers_of(buffers[k], codes[k])
        elseif p.how === :text || p.how === :binary
            cm["storage"] = storage_of(p, sinks[k].width)
            finish(sinks[k])
        elseif p.how === :date
            v = counts_in_place!((x, _) -> x + DAYS_1970, buffers[k])
            with_missing(v, codes[k])
        elseif p.how === :time
            per = Dict("ms" => 1_000_000, "us" => 1_000, "ns" => 1)[p.info["unit"]]
            v = counts_in_place!((x, _) -> x * per, buffers[k])
            with_missing(v, codes[k])
        elseif p.how === :timestamp
            v = timestamps!(buffers[k], codes[k], p.info["unit"], truncate, p.name, call)
            zoned(v, codes[k], p, zoneless)
        elseif p.how === :logical_date
            logical_date(buffers[k], codes[k], p, cm)
        elseif p.how === :logical_timestamp
            logical_timestamp(buffers[k], codes[k], p, cm, truncate, call, zoneless)
        elseif p.how === :letter_levels
            # The library made each value that is not a level number `.`
            # and gives the first such row of the read.
            b = bad === nothing ? nothing : bad[k]
            if b !== nothing
                nlevels = length(get(p.info, "categories", ()))
                @warn "column \"$(p.name)\": row $(start + Int(b) + 1) of the file holds a value that is not one of " *
                      "its $nlevels level numbers; it is read as `.`"
            end
            numbers_of(buffers[k], codes[k])
        elseif p.how === :levels
            levels = p.info["levels"] == "profile" ? Vector{String}(p.info["categories"]) : Vector{String}(rep["levels"][k])
            ordered = p.info["levels"] == "profile" && p.info["ordered"] === true
            categorical_of(buffers[k], levels, ordered, String(p.name), plain_cats)
        end
        colmeta[p.name] = cm
    end
    isempty(zoneless) || @warn "TimeZones.jl is not loaded, so these columns' times are DateTime in UTC, " *
                               "without their zones: $(join(zoneless, ", ")). Load it (using TimeZones) to get ZonedDateTime."
    isempty(plain_cats) || @warn "CategoricalArrays.jl is not loaded, so these categorical columns are String: " *
                                 "$(join(plain_cats, ", ")). Load it (using CategoricalArrays) to get CategoricalArray."
    frame(names, columns, table_meta_of(doc, names), colmeta)
end

# The library's message, with the argument of read_parquet that keeps
# the value where the core names another way.
read_error(m) = replace(m, "read the column as text to keep every digit" => "read with decimal = :string to keep every digit")

function zone_of(p::Plan)
    z = p.info["zone"]
    z === nothing || isempty(z) ? nothing : String(z)
end

# DateTimes in UTC as ZonedDateTime when the column has a zone and
# TimeZones.jl is loaded.
function zoned(v::Vector{DateTime}, codes, p::Plan, zoneless)
    zone = zone_of(p)
    zone === nothing && return with_missing(v, codes)
    ext = tz_ext()
    if ext === nothing
        zone in UTC_NAMES || push!(zoneless, "$(p.name) ($zone)")
        return with_missing(v, codes)
    end
    ext.zoned(v, codes, zone)
end

# A DOUBLE column of days since 1970 that our writer used for a date
# holding .a to .z (or a fraction of a day): Date where every value read
# is a whole day, else numbers as read_dta keeps such a column, days
# since 1960 with a %td format.
function logical_date(v::Vector{Float64}, codes, p::Plan, cm)
    letters = any(>(0x01), codes)
    whole = !letters && all(i -> codes[i] != 0x00 || (isinteger(v[i]) && abs(v[i]) < 1e9), eachindex(v))
    if whole
        d = Vector{Date}(undef, length(v))
        @inbounds for i in eachindex(v)
            d[i] = Date(Dates.UTD(codes[i] == 0x00 ? Int64(v[i]) + DAYS_1970 : DAYS_1970))
        end
        return with_missing(d, codes)
    end
    @inbounds for i in eachindex(v)
        codes[i] == 0x00 && (v[i] += DAYS_1960_TO_1970)
    end
    date_kind(cm["format"]) === :date || (cm["format"] = "%td")
    cm["storage"] = "double"
    numbers_of(v, codes)
end

# The same for a timestamp, held as seconds since 1970: DateTime (or
# ZonedDateTime) where no row holds .a to .z, else milliseconds since
# 1960 with a %tc format.
function logical_timestamp(v::Vector{Float64}, codes, p::Plan, cm, truncate, call, zoneless)
    if any(>(0x01), codes)
        @inbounds for i in eachindex(v)
            codes[i] == 0x00 && (v[i] = (v[i] + SECONDS_1960_TO_1970) * 1000)
        end
        date_kind(cm["format"]) === :datetime || (cm["format"] = "%tc")
        cm["storage"] = "double"
        return numbers_of(v, codes)
    end
    t = Vector{DateTime}(undef, length(v))
    @inbounds for i in eachindex(v)
        if codes[i] != 0x00
            t[i] = DateTime(1970)
            continue
        end
        s = v[i]
        ms = round(s * 1000)
        if ms / 1000 != s
            truncate || throw(DtaError("column \"$(p.name)\": row $i is $s seconds, which is not a whole number of " *
                                       "milliseconds, all a DateTime holds; read with $call to drop what is below a millisecond"))
            ms = floor(s * 1000)
        end
        t[i] = DateTime(Dates.UTM(Int64(ms) + MS_1970))
    end
    cm["storage"] = "double"
    zoned(t, codes, p, zoneless)
end

function categorical_of(refs::Vector{UInt32}, levels::Vector{String}, ordered::Bool, name, plain)
    ext = cat_ext()
    ext === nothing || return ext.categorical(refs, levels, ordered)
    push!(plain, name)
    if any(==(0x00000000), refs)
        out = Vector{Union{Missing,String}}(undef, length(refs))
        @inbounds for i in eachindex(refs)
            out[i] = refs[i] == 0 ? missing : levels[refs[i]]
        end
        return out
    end
    String[levels[r] for r in refs]
end

# ---------------------------------------------------------------- meta

# The element type read_parquet gives a column with its defaults.
function eltype_of(info)
    info["role"] == "data" || return nothing
    p = try
        plan_of(info, 0, :float)
    catch
        return nothing
    end
    T = p.how === :number ? p.T :
        p.how === :date ? Date :
        p.how === :time ? Time :
        p.how === :timestamp || (p.how === :logical_timestamp) ?
            (zone_of(p) !== nothing && tz_ext() !== nothing ? tz_ext().ZonedDateTime : DateTime) :
        p.how === :logical_date ? Date :
        p.how === :levels ? (cat_ext() === nothing ? String : cat_ext().value_type()) :
        p.T
    widened = info["storage"] !== nothing || info["logical"] !== nothing
    info["nulls"] === true || widened ? Union{Missing,T} : T
end

"""
    read_parquet_info(source) -> Dict{String,Any}

A Parquet file's schema and metadata, from its footer only, without
reading rows. `source` is a path, an `IO` or a `Vector{UInt8}`. See
docs/julia.md, "A Parquet file's schema and metadata".

The table metadata [`read_parquet`](@ref) gives (`"label"`, `"notes"`,
`"timestamp"`, `"characteristics"`, `"sorted_by"`, `"value_labels"`),
and:

- `"nrows"`: the number of rows;
- `"row_groups"`: `(rows, compressed_bytes, uncompressed_bytes)` of each;
- `"compression"`: the codecs used; `"created_by"`: the writer;
- `"key_value"`: every key-value entry of the footer as a
  `(key, value)` named tuple, the value as text (`nothing` if the entry
  has none), the `dta` profile and `ARROW:schema` included;
- `"warnings"`: what is wrong with the file's dta profile, if anything;
- `"columns"`: a `DataFrame` with a row per column of the file and the
  columns `name`, `role` (`"data"`, or `"nested"` for a list, map or
  struct, which is not read), `physical_type`, `logical_type`, `eltype`
  (the element type `read_parquet` gives the column, with `Missing`
  when the file's statistics show nulls; `nothing` for a column it does
  not read), `label`, `format`, `value_labels` and `storage` (a text
  column's is `""` until it is read).
"""
function read_parquet_info(source)
    with_parquet(source, true) do f
        doc = pq_info(f)
        warn_profile(doc)
        infos = doc["columns"]::Vector{Any}
        names = Symbol[Symbol(c["name"]) for c in infos]
        meta = table_meta_of(doc, names)
        sets = meta["value_labels"]
        meta["nrows"] = Int(doc["rows"])
        meta["row_groups"] = [(rows=Int(g["rows"]), compressed_bytes=Int(g["compressed_bytes"]),
                               uncompressed_bytes=Int(g["uncompressed_bytes"])) for g in doc["row_groups"]]
        meta["compression"] = Vector{String}(doc["compression"])
        meta["created_by"] = str_or(doc["created_by"])
        meta["warnings"] = Vector{String}(doc["warnings"])
        meta["key_value"] = [(key=String(kv["key"]), value=kv["value"] === nothing ? nothing : String(kv["value"]))
                             for kv in doc["key_value"]]
        cols = map(infos) do info
            c = try
                column_meta_of(plan_of(info, 0, :float), sets)
            catch
                Dict{String,Any}("label" => str_or(info["label"]), "format" => str_or(info["format"]),
                                 "storage" => "", "value_labels" => "")
            end
            c
        end
        meta["columns"] = DataFrame(
            name = String[info["name"] for info in infos],
            role = String[info["role"] for info in infos],
            physical_type = String[str_or(info["physical_type"]) for info in infos],
            logical_type = String[str_or(info["logical_type"]) for info in infos],
            eltype = Any[eltype_of(info) for info in infos],
            label = String[c["label"] for c in cols],
            format = String[c["format"] for c in cols],
            value_labels = String[c["value_labels"] for c in cols],
            storage = String[c["storage"] for c in cols],
        )
        meta
    end
end
