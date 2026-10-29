"""
    DtaColumn{T}(values::Vector{T}, codes::Vector{UInt8})

A numeric column with Stata missing values. Element `i` is `values[i]`
when `codes[i]` is 0, and `missing` otherwise: code 1 is `.`, 2 to 27
are `.a` to `.z`. `T` is the storage type (`Int8` for byte, `Int16` int,
`Int32` long, `Float32` float, `Float64` double).

Bulk operations keep the codes: indexing by ranges, vectors or masks,
`view`, `copy`, `similar`, `sort`, `permute!`, `vcat` and `append!` of
`DtaColumn`s, and assigning one `DtaColumn` into a slice of another.
Assigning single elements cannot: `b[i] = a[i]` copies `missing`, which
becomes `.`. Use [`stata_code`](@ref) and [`set_stata_code!`](@ref).
"""
struct DtaColumn{T<:Real} <: AbstractVector{Union{Missing,T}}
    values::Vector{T}
    codes::Vector{UInt8}
    function DtaColumn{T}(values::Vector{T}, codes::Vector{UInt8}) where {T<:Real}
        length(values) == length(codes) || throw(DimensionMismatch("values and codes differ in length"))
        any(>(0x1b), codes) && throw(ArgumentError("missing codes run from 0 to 27"))
        new{T}(values, codes)
    end
end

DtaColumn(values::Vector{T}, codes::Vector{UInt8}) where {T<:Real} = DtaColumn{T}(values, codes)

"""
    DtaColumn(x::AbstractVector)

A `DtaColumn` of `x`'s values, with `missing` as `.`.
"""
function DtaColumn(x::AbstractVector{<:Union{Missing,T}}) where {T<:Real}
    codes = UInt8[ismissing(v) ? 0x01 : 0x00 for v in x]
    values = T[ismissing(v) ? zero(T) : v for v in x]
    DtaColumn{T}(values, codes)
end
DtaColumn(x::DtaColumn) = copy(x)

Base.size(c::DtaColumn) = size(c.values)
Base.IndexStyle(::Type{<:DtaColumn}) = IndexLinear()

Base.@propagate_inbounds function Base.getindex(c::DtaColumn, i::Int)
    @boundscheck checkbounds(c, i)
    @inbounds c.codes[i] == 0x00 ? c.values[i] : missing
end

Base.@propagate_inbounds function Base.setindex!(c::DtaColumn{T}, x, i::Int) where {T}
    @boundscheck checkbounds(c, i)
    if ismissing(x)
        @inbounds c.codes[i] = 0x01
        @inbounds c.values[i] = blank(T)
    else
        @inbounds c.values[i] = convert(T, x)
        @inbounds c.codes[i] = 0x00
    end
    c
end

# The value stored where a code is not 0.
blank(::Type{T}) where {T<:AbstractFloat} = T(NaN)
blank(::Type{T}) where {T} = zero(T)

Base.getindex(c::DtaColumn, I::AbstractVector) = DtaColumn(c.values[I], c.codes[I])
Base.getindex(c::DtaColumn, ::Colon) = copy(c)

function Base.setindex!(c::DtaColumn, x::DtaColumn, I::AbstractVector)
    c.values[I] = x.values
    c.codes[I] = x.codes
    c
end
Base.setindex!(c::DtaColumn, x::DtaColumn, ::Colon) = setindex!(c, x, eachindex(c))

function Base.setindex!(c::DtaColumn, x::SubArray{<:Any,1,<:DtaColumn}, I::AbstractVector)
    setindex!(c, copy(x), I)
end

Base.copy(c::DtaColumn) = DtaColumn(copy(c.values), copy(c.codes))

function Base.similar(c::DtaColumn{T}, ::Type{Union{Missing,S}}, dims::Tuple{Int}) where {T,S<:Real}
    DtaColumn{S}(similar(Vector{S}, dims), zeros(UInt8, dims))
end
Base.similar(c::DtaColumn{T}, ::Type{S}, dims::Tuple{Int}) where {T,S<:Real} = similar(c, Union{Missing,S}, dims)

function Base.copyto!(dest::DtaColumn, doffs::Integer, src::DtaColumn, soffs::Integer, n::Integer)
    copyto!(dest.values, doffs, src.values, soffs, n)
    copyto!(dest.codes, doffs, src.codes, soffs, n)
    dest
end
Base.copyto!(dest::DtaColumn, src::DtaColumn) = copyto!(dest, 1, src, 1, length(src))

# Views of a DtaColumn, as `view` and some DataFrames operations make.
const DtaView = SubArray{<:Any,1,<:DtaColumn}
Base.copy(v::DtaView) = parent(v)[parentindices(v)[1]]
function Base.copyto!(dest::DtaColumn, src::DtaView)
    length(dest) == length(src) || throw(DimensionMismatch("lengths differ"))
    dest[eachindex(dest)] = copy(src)
end

function Base.vcat(a::DtaColumn, rest::DtaColumn...)
    T = promote_type(eltype(a.values), map(r -> eltype(r.values), rest)...)
    DtaColumn{T}(vcat(a.values, map(r -> r.values, rest)...), vcat(a.codes, map(r -> r.codes, rest)...))
end

function Base.append!(a::DtaColumn, b::DtaColumn)
    append!(a.values, b.values)
    append!(a.codes, b.codes)
    a
end

function Base.push!(c::DtaColumn{T}, x) where {T}
    if ismissing(x)
        push!(c.values, blank(T))
        push!(c.codes, 0x01)
    else
        push!(c.values, convert(T, x))
        push!(c.codes, 0x00)
    end
    c
end

function Base.resize!(c::DtaColumn{T}, n::Integer) where {T}
    m = length(c)
    resize!(c.values, n)
    resize!(c.codes, n)
    # New rows are `.`.
    for i in m+1:n
        c.values[i] = blank(T)
        c.codes[i] = 0x01
    end
    c
end

function Base.deleteat!(c::DtaColumn, i)
    deleteat!(c.values, i)
    deleteat!(c.codes, i)
    c
end

function Base.insert!(c::DtaColumn{T}, i::Integer, x) where {T}
    insert!(c.values, i, ismissing(x) ? blank(T) : convert(T, x))
    insert!(c.codes, i, ismissing(x) ? 0x01 : 0x00)
    c
end

Base.empty!(c::DtaColumn) = (empty!(c.values); empty!(c.codes); c)
Base.sizehint!(c::DtaColumn, n::Integer) = (sizehint!(c.values, n); sizehint!(c.codes, n); c)

function Base.permute!(c::DtaColumn, p::AbstractVector)
    c.values .= c.values[p]
    c.codes .= c.codes[p]
    c
end

function Base.invpermute!(c::DtaColumn, p::AbstractVector)
    c.values[p] = copy(c.values)
    c.codes[p] = copy(c.codes)
    c
end

Base.reverse(c::DtaColumn) = DtaColumn(reverse(c.values), reverse(c.codes))

# Sorting with no `by`, `lt` or `order` follows Stata: numbers, then `.`,
# `.a`, ..., `.z`.
const ORDER_KEYS = (:by, :lt, :order)

function Base.sortperm(c::DtaColumn; kws...)
    any(k -> haskey(kws, k), ORDER_KEYS) && return invoke(sortperm, Tuple{AbstractVector}, c; kws...)
    sortperm(stata_key(c); kws...)
end

function Base.sort!(c::DtaColumn; kws...)
    permute!(c, sortperm(c; kws...))
end

Base.sort(c::DtaColumn; kws...) = sort!(copy(c); kws...)

"""
    stata_code(col, i) -> UInt8

The missing code of `col[i]`: 0 for a value, 1 for `.`, 2 to 27 for `.a`
to `.z`. For a vector that is not a [`DtaColumn`](@ref), `missing` is `.`.
"""
stata_code(c::DtaColumn, i::Integer) = c.codes[i]
stata_code(v::DtaView, i::Integer) = stata_code(parent(v), parentindices(v)[1][i])
stata_code(v::AbstractVector, i::Integer) = ismissing(v[i]) ? 0x01 : 0x00

"""
    set_stata_code!(col::DtaColumn, i, code)

Make `col[i]` the missing value with this code (1 for `.`, 2 to 27 for
`.a` to `.z`), or a value again with code 0 (keeping the stored value).
"""
function set_stata_code!(c::DtaColumn{T}, i::Integer, code::Integer) where {T}
    0 <= code <= 27 || throw(ArgumentError("missing codes run from 0 to 27"))
    c.codes[i] = code
    code == 0 || (c.values[i] = blank(T))
    c
end
set_stata_code!(v::DtaView, i::Integer, code::Integer) = set_stata_code!(parent(v), parentindices(v)[1][i], code)

const MISSING_KEYS = Tuple(reinterpret(Float64, 0x7fe0000000000000 + UInt64(k) << 40) for k in 0:26)

"""
    stata_key(x)
    stata_key(col::AbstractVector)
    stata_key(col, i)

A Float64 that sorts and compares as Stata orders values: a number is
itself; `.`, `.a`, ..., `.z` come after every number, in that order.
They are the doubles Stata stores for those missing values, and the same
keys dtatools (R) and the npm package give.

`x` may be a number (`NaN` is `.`), `missing` (`.`), or a name such as
`".a"`. On a column it gives every row's key; value label sets use these
keys too.
"""
stata_key(x::Real) = isnan(x) ? MISSING_KEYS[1] : Float64(x)
stata_key(::Missing) = MISSING_KEYS[1]
function stata_key(name::AbstractString)
    name == "." && return MISSING_KEYS[1]
    (length(name) == 2 && name[1] == '.' && 'a' <= name[2] <= 'z') || throw(ArgumentError("\"$name\" is not a missing value"))
    MISSING_KEYS[name[2]-'a'+2]
end
stata_key(c::DtaColumn, i::Integer) = c.codes[i] == 0 ? Float64(c.values[i]) : MISSING_KEYS[c.codes[i]]
stata_key(c::AbstractVector, i::Integer) = stata_key(c[i])
stata_key(c::DtaColumn) = [stata_key(c, i) for i in eachindex(c)]
stata_key(v::AbstractVector) = [stata_key(x) for x in v]
stata_key(v::DtaView) = [stata_key(v, i) for i in eachindex(v)]
stata_key(v::DtaView, i::Integer) = stata_key(parent(v), parentindices(v)[1][i])

# The missing code a key stands for, or 0 for a number.
function key_code(k::Real)
    k isa AbstractFloat || return 0x00
    i = findfirst(==(Float64(k)), MISSING_KEYS)
    i === nothing ? 0x00 : UInt8(i)
end

missing_name(code::Integer) = code == 1 ? "." : string('.', Char('a' + code - 2))

function Base.show(io::IO, ::MIME"text/plain", c::DtaColumn{T}) where {T}
    n = length(c)
    print(io, n, "-element DtaColumn{", T, "}")
    n == 0 && return
    println(io, ":")
    rows = n <= 20 ? (1:n) : [1:10; n-9:n]
    for (k, i) in enumerate(rows)
        n > 20 && k == 11 && println(io, " ⋮")
        print(io, " ", c.codes[i] == 0 ? repr(c.values[i]) : missing_name(c.codes[i]))
        k < length(rows) && println(io)
    end
end
