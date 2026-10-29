# The JSON the library exchanges metadata in: objects become
# Dict{String,Any}, arrays Vector{Any}, numbers Float64.

function parse_json(s::String)
    v, i = json_value(s, json_space(s, 1))
    json_space(s, i) > ncodeunits(s) || throw(DtaError("bad JSON from the library at byte $i"))
    v
end

function json_space(s, i)
    while i <= ncodeunits(s) && codeunit(s, i) in (0x20, 0x09, 0x0a, 0x0d)
        i += 1
    end
    i
end

function json_value(s, i)
    c = codeunit(s, i)
    if c == UInt8('{')
        d = Dict{String,Any}()
        i = json_space(s, i + 1)
        codeunit(s, i) == UInt8('}') && return d, i + 1
        while true
            k, i = json_string(s, json_space(s, i))
            i = json_space(s, i) + 1 # the colon
            d[k], i = json_value(s, json_space(s, i))
            i = json_space(s, i)
            codeunit(s, i) == UInt8('}') && return d, i + 1
            i += 1 # the comma
        end
    elseif c == UInt8('[')
        a = Any[]
        i = json_space(s, i + 1)
        codeunit(s, i) == UInt8(']') && return a, i + 1
        while true
            v, i = json_value(s, json_space(s, i))
            push!(a, v)
            i = json_space(s, i)
            codeunit(s, i) == UInt8(']') && return a, i + 1
            i += 1
        end
    elseif c == UInt8('"')
        json_string(s, i)
    elseif startswith(SubString(s, i), "true")
        true, i + 4
    elseif startswith(SubString(s, i), "false")
        false, i + 5
    elseif startswith(SubString(s, i), "null")
        nothing, i + 4
    else
        j = i
        while j <= ncodeunits(s) && codeunit(s, j) in b"+-.eE0123456789"
            j += 1
        end
        parse(Float64, SubString(s, i, j - 1)), j
    end
end

function json_string(s, i)
    io = IOBuffer()
    i += 1
    while true
        c = codeunit(s, i)
        if c == UInt8('"')
            return String(take!(io)), i + 1
        elseif c == UInt8('\\')
            e = Char(codeunit(s, i + 1))
            if e == 'u'
                u = parse(UInt32, SubString(s, i + 2, i + 5); base=16)
                i += 6
                if 0xd800 <= u < 0xdc00 && codeunit(s, i) == UInt8('\\')
                    low = parse(UInt32, SubString(s, i + 2, i + 5); base=16)
                    u = 0x10000 + ((u - 0xd800) << 10) + (low - 0xdc00)
                    i += 6
                end
                print(io, Char(u))
            else
                write(io, get(Dict('n' => '\n', 't' => '\t', 'r' => '\r', 'b' => '\b', 'f' => '\f'), e, e))
                i += 2
            end
        else
            write(io, c)
            i += 1
        end
    end
end

json(io::IO, x::AbstractString) = (print(io, '"'); json_escape(io, x); print(io, '"'))
json(io::IO, x::Real) = isinteger(x) && abs(x) < 2^53 ? print(io, Int64(x)) : print(io, Float64(x))
json(io::IO, ::Nothing) = print(io, "null")
json(io::IO, x::Symbol) = json(io, String(x))
function json(io::IO, x::AbstractVector)
    print(io, '[')
    for (k, v) in enumerate(x)
        k > 1 && print(io, ',')
        json(io, v)
    end
    print(io, ']')
end
function json(io::IO, x::Union{AbstractDict,NamedTuple})
    print(io, '{')
    for (k, (key, v)) in enumerate(pairs(x))
        k > 1 && print(io, ',')
        json(io, string(key))
        print(io, ':')
        json(io, v)
    end
    print(io, '}')
end
json(x) = sprint(json, x)

function json_escape(io::IO, s::AbstractString)
    for c in s
        if c == '"'
            print(io, "\\\"")
        elseif c == '\\'
            print(io, "\\\\")
        elseif c < ' '
            print(io, "\\u", string(UInt32(c); base=16, pad=4))
        else
            print(io, c)
        end
    end
end
