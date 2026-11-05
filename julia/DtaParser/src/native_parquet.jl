# The library's Parquet and fixed-width calls, which Datakit uses through
# DtaParser.Internals (internals.jl). DtaParser itself reads and writes
# .dta files only; these wrappers keep every ccall into the library in
# this package, beside the ABI version they were written for.

# ---------------------------------------------------------------- structures

# Must match dta_pq_output in dta.h: where one selected column goes.
struct PqOutput
    kind::UInt32
    base::Int32
    null::Int32
    values::Ptr{Cvoid}
    codes::Ptr{UInt8}
end

# dta_pq_output.kind
const PQ_I8, PQ_I16, PQ_I32, PQ_I64, PQ_F32, PQ_F64, PQ_U8, PQ_U16, PQ_U32, PQ_U64, PQ_LEVELS, PQ_TEXT = UInt32.(1:12)

# Must match dta_pq_column in dta.h: one column to write.
struct PqColumn
    kind::UInt32
    values::Ptr{Cvoid}
    codes::Ptr{UInt8}
    bytes::Ptr{UInt8}
    offsets::Ptr{UInt64}
end

# dta_pq_column.kind
const W_INT8, W_INT16, W_INT32, W_INT64, W_FLOAT, W_DOUBLE, W_BOOL, W_DATE, W_DATETIME, W_ZONED, W_TEXT, W_BINARY,
      W_CATEGORICAL = UInt32.(1:13)

# ---------------------------------------------------------------- reading

const PAR1 = b"PAR1"

"""
    pq_open(path::String, nested_skip::Bool) -> Ptr{Cvoid}
    pq_open(ptr::Ptr{UInt8}, len::Integer, nested_skip::Bool) -> Ptr{Cvoid}

Open a Parquet file by path, or from `len` bytes at `ptr` (which must
stay alive until [`pq_close`](@ref)). Throws a `DtaError` with the
library's message.
"""
function pq_open(path::String, nested_skip::Bool)
    err = zeros(UInt8, ERR_LEN)
    h = ccall(fn(:dta_pq_open), Ptr{Cvoid}, (Cstring, Ptr{UInt8}, Csize_t, Cint, Ptr{UInt8}, Csize_t),
              path, C_NULL, 0, nested_skip, err, ERR_LEN)
    h == C_NULL && throw(DtaError(error_text(err)))
    h
end

function pq_open(ptr::Ptr{UInt8}, len::Integer, nested_skip::Bool)
    err = zeros(UInt8, ERR_LEN)
    h = ccall(fn(:dta_pq_open), Ptr{Cvoid}, (Ptr{UInt8}, Ptr{UInt8}, Csize_t, Cint, Ptr{UInt8}, Csize_t),
              C_NULL, ptr, len, nested_skip, err, ERR_LEN)
    h == C_NULL && throw(DtaError(error_text(err)))
    h
end

"Close a file [`pq_open`](@ref) opened."
pq_close(h::Ptr{Cvoid}) = (h == C_NULL || ccall(fn(:dta_pq_close), Cvoid, (Ptr{Cvoid},), h); nothing)

# A string the library allocated, copied and freed.
function take_string(s::Ptr{UInt8}, len::Integer)
    try
        unsafe_string(s, len)
    finally
        ccall(fn(:dta_string_free), Cvoid, (Ptr{UInt8},), s)
    end
end

"The footer of an open file, as the JSON text dta.h describes."
function pq_info_json(h::Ptr{Cvoid})
    err = zeros(UInt8, ERR_LEN)
    len = Ref{Csize_t}(0)
    s = ccall(fn(:dta_pq_info_json), Ptr{UInt8}, (Ptr{Cvoid}, Ref{Csize_t}, Ptr{UInt8}, Csize_t), h, len, err, ERR_LEN)
    s == C_NULL && throw(DtaError(error_text(err)))
    take_string(s, len[])
end

"""
    pq_read(h, columns, start, count, outputs, callback, user) -> (rows, text)

Read rows `start` to `start + count - 1` (0-based) of the columns
`columns` (0-based indices) into `outputs`; text columns go through
`callback`, called with `user`. Returns the rows read and the report as
JSON text, or `-1` and the library's message. The caller keeps the
buffers `outputs` point at alive (`GC.@preserve`).
"""
function pq_read(h::Ptr{Cvoid}, columns::Vector{UInt32}, start::Integer, count::Integer, outputs::Vector{PqOutput},
                 callback::Ptr{Cvoid}, user::Ptr{Cvoid})
    err = zeros(UInt8, ERR_LEN)
    report = Ref{Ptr{UInt8}}(C_NULL)
    rlen = Ref{Csize_t}(0)
    got = ccall(fn(:dta_pq_read), Int64,
                (Ptr{Cvoid}, Ptr{UInt32}, Csize_t, UInt64, UInt64, Ptr{PqOutput}, Ptr{Cvoid}, Ptr{Cvoid},
                 Ref{Ptr{UInt8}}, Ref{Csize_t}, Ptr{UInt8}, Csize_t),
                h, columns, length(columns), start, count, outputs, callback, user, report, rlen, err, ERR_LEN)
    got < 0 && return (got, error_text(err))
    (got, take_string(report[], rlen[]))
end

# ---------------------------------------------------------------- writing

"""
    pq_write(dest, nrows, columns, meta_json; codec, level, rows, missing_letters) -> dest

Write `columns` (`PqColumn`s) as a Parquet file to `dest`, a path or an
`IO`, with `meta_json` as the dta profile's source. `level` is `nothing`
for the codec's default; `rows` 0 for the default row group size.
Throws a `WriteError` with the library's message. The caller keeps the
arrays the columns point at alive (`GC.@preserve`).
"""
function pq_write(dest::Union{String,IO}, nrows::Integer, columns::Vector{PqColumn}, meta::String; codec::String,
                  level::Union{Nothing,Integer}, rows::Integer, missing_letters::Bool)
    err = zeros(UInt8, ERR_LEN)
    out = Ref{Ptr{UInt8}}(C_NULL)
    out_len = Ref{Csize_t}(0)
    lvl = level === nothing ? 0 : Int(level)
    rc = if dest isa String
        ccall(fn(:dta_pq_write), Cint,
              (Cstring, UInt64, Ptr{PqColumn}, Csize_t, Cstring, Cstring, Cint, Cint, UInt64, Cint,
               Ref{Ptr{UInt8}}, Ref{Csize_t}, Ptr{UInt8}, Csize_t),
              dest, nrows, columns, length(columns), meta, codec, lvl, level !== nothing, rows, missing_letters,
              out, out_len, err, ERR_LEN)
    else
        ccall(fn(:dta_pq_write), Cint,
              (Ptr{UInt8}, UInt64, Ptr{PqColumn}, Csize_t, Cstring, Cstring, Cint, Cint, UInt64, Cint,
               Ref{Ptr{UInt8}}, Ref{Csize_t}, Ptr{UInt8}, Csize_t),
              C_NULL, nrows, columns, length(columns), meta, codec, lvl, level !== nothing, rows, missing_letters,
              out, out_len, err, ERR_LEN)
    end
    rc == 0 || throw(WriteError(error_text(err)))
    if !(dest isa String)
        try
            unsafe_write(dest, out[], out_len[])
        finally
            ccall(fn(:dta_pq_bytes_free), Cvoid, (Ptr{UInt8}, Csize_t), out[], out_len[])
        end
    end
    dest
end

# ---------------------------------------------------------------- fixed width

"""
    fixed_width_to_dta(path, setups, out, recodes, commented_formats) -> Vector{String}

Convert fixed-width `path` through its SAS setup files `setups` into the
`.dta` file `out`; returns the warnings. Throws a `DtaError`.
"""
function fixed_width_to_dta(path::String, setups::Vector{String}, out::String, recodes::String,
                            commented_formats::Bool)
    err = zeros(UInt8, ERR_LEN)
    len = Ref{Csize_t}(0)
    s = ccall(fn(:dta_fixed_width_to_dta), Ptr{UInt8},
              (Cstring, Ptr{Cstring}, Csize_t, Cstring, Cstring, Cint, Ref{Csize_t}, Ptr{UInt8}, Csize_t),
              path, setups, length(setups), out, recodes, commented_formats, len, err, ERR_LEN)
    s == C_NULL && throw(DtaError(error_text(err)))
    Vector{String}(parse_json(take_string(s, len[])))
end
