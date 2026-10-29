# The native library (crates/dta-ffi, declared in its include/dta.h).

const ABI_VERSION = 1

const libname = Sys.iswindows() ? "dta_ffi.dll" : Sys.isapple() ? "libdta_ffi.dylib" : "libdta_ffi.so"

# Symbols, looked up when the package loads.
const SYMBOLS = (:dta_abi_version, :dta_open, :dta_close, :dta_meta_json, :dta_string_free, :dta_read, :dta_write)
const FNS = Dict{Symbol,Ptr{Cvoid}}()
const LOAD_ERROR = Ref{String}("")

function library_path()
    path = get(ENV, "DTA_PARSER_LIB", "")
    isempty(path) ? joinpath(@__DIR__, "..", "deps", "usr", "lib", libname) : path
end

function __init__()
    path = library_path()
    if !isfile(path)
        LOAD_ERROR[] = "the dta-parser library is not built: run `import Pkg; Pkg.build(\"DtaParser\")` (looked for $path)"
        return
    end
    handle = Base.Libc.Libdl.dlopen(path)
    for s in SYMBOLS
        FNS[s] = Base.Libc.Libdl.dlsym(handle, s)
    end
    version = ccall(FNS[:dta_abi_version], UInt32, ())
    if version != ABI_VERSION
        empty!(FNS)
        LOAD_ERROR[] = "$path has ABI version $version; DtaParser needs $ABI_VERSION. Rebuild with `Pkg.build(\"DtaParser\")`"
    end
end

function fn(s::Symbol)
    p = get(FNS, s, C_NULL)
    p == C_NULL && error(LOAD_ERROR[])
    p
end

# Must match dta_column in dta.h.
struct CColumn
    storage::UInt32
    value_type::UInt32
    values::Ptr{Cvoid}
    codes::Ptr{UInt8}
    bytes::Ptr{UInt8}
    offsets::Ptr{UInt64}
    binary::Ptr{UInt8}
end

const BYTE, INT, LONG, FLOAT, DOUBLE, STR, STRL = UInt32.(1:7)
const I8, I16, I32, I64, F32, F64, U8 = UInt32.(1:7)

const ERR_LEN = 2048

error_text(buf::Vector{UInt8}) = String(buf[1:something(findfirst(==(0x00), buf), length(buf) + 1)-1])

struct DtaError <: Exception
    message::String
end
Base.showerror(io::IO, e::DtaError) = print(io, e.message)

mutable struct File
    ptr::Ptr{Cvoid}
end

function open_file(path::AbstractString, encoding)
    err = zeros(UInt8, ERR_LEN)
    enc = encoding === nothing ? "" : String(encoding)
    ptr = ccall(fn(:dta_open), Ptr{Cvoid}, (Cstring, Cstring, Ptr{UInt8}, Csize_t), String(path), enc, err, ERR_LEN)
    ptr == C_NULL && throw(DtaError(error_text(err)))
    File(ptr)
end

function close_file(f::File)
    f.ptr == C_NULL || ccall(fn(:dta_close), Cvoid, (Ptr{Cvoid},), f.ptr)
    f.ptr = C_NULL
end

function with_file(g, path, encoding)
    f = open_file(path, encoding)
    try
        g(f)
    finally
        close_file(f)
    end
end

function meta_json(f::File)
    err = zeros(UInt8, ERR_LEN)
    len = Ref{Csize_t}(0)
    s = ccall(fn(:dta_meta_json), Ptr{UInt8}, (Ptr{Cvoid}, Ref{Csize_t}, Ptr{UInt8}, Csize_t), f.ptr, len, err, ERR_LEN)
    s == C_NULL && throw(DtaError(error_text(err)))
    try
        unsafe_string(s, len[])
    finally
        ccall(fn(:dta_string_free), Cvoid, (Ptr{UInt8},), s)
    end
end
