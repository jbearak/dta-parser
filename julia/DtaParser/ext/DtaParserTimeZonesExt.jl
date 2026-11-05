module DtaParserTimeZonesExt

# read_parquet returns timestamps with a zone as ZonedDateTime, and
# write_parquet writes ZonedDateTime columns, when TimeZones.jl is
# loaded.

using Dates
using TimeZones
using DtaParser: DtaParser, PqPrepared, PqColumn, W_ZONED, WriteError

# A zone's name as the file gives it: an IANA name, or a fixed offset
# such as "+01:00" (as Arrow writes them).
function zone(name::String)
    try
        return TimeZone(name, TimeZones.Class(:ALL))
    catch
    end
    try
        return FixedTimeZone(name)
    catch
    end
    throw(DtaParser.DtaError("the time zone \"$name\" is not one TimeZones.jl knows"))
end

# DateTimes in UTC as ZonedDateTime in `name`, missing where the code is
# not 0.
function zoned(v::Vector{DateTime}, codes, name::String)
    tz = zone(name)
    if codes === nothing || !any(!=(0x00), codes)
        return ZonedDateTime[ZonedDateTime(t, tz; from_utc=true) for t in v]
    end
    Union{Missing,ZonedDateTime}[codes[i] == 0x00 ? ZonedDateTime(v[i], tz; from_utc=true) : missing for i in eachindex(v)]
end

function DtaParser.prepare_parquet(name, x::AbstractVector{<:Union{Missing,ZonedDateTime}})
    zones = unique(timezone(t) for t in x if !ismissing(t))
    length(zones) <= 1 ||
        throw(WriteError("column $name holds times in $(length(zones)) zones; a Parquet timestamp column has one. " *
                         "Convert them with astimezone(t, tz) first"))
    n = length(x)
    ms = Vector{Int64}(undef, n)
    codes = any(ismissing, x) ? zeros(UInt8, n) : nothing
    for (i, t) in enumerate(x)
        if ismissing(t)
            codes[i] = 0x01
            ms[i] = 0
        else
            ms[i] = Dates.value(DateTime(t, UTC))
        end
    end
    col = PqColumn(W_ZONED, pointer(ms), codes === nothing ? C_NULL : pointer(codes), C_NULL, C_NULL)
    PqPrepared(col, Any[ms, codes], Dict{String,Any}("zone" => isempty(zones) ? "UTC" : string(TimeZones.name(zones[1]))))
end

end
