# Benchmark tasks for Julia's .dta readers; bench/run.py drives this.
#   julia --project=bench/julia bench/cases/case.jl READER FILE OUT TASKS RUNS COLS SKIP N
# READER is ours (DtaParser), readstattables or statfiles. The arguments
# are as in bench/cases/case.py. bench/julia's environment pins the
# readers and develops julia/DtaParser (build its library first:
# julia --project=bench/julia -e 'import Pkg; Pkg.build("DtaParser")').
reader, path, out_path, tasks, runs, cols, skip, n = ARGS
runs = parse(Int, runs); skip = parse(Int, skip); n = parse(Int, n)
cols = Symbol.(filter(!isempty, split(cols, ",")))
tmp = dirname(abspath(out_path))

using Dates, SHA, Tables, DataAPI
reader == "ours" && using DtaParser
reader == "statfiles" && using StatFiles, DataFrames
# The checks re-read written files with ReadStatTables.
(reader == "readstattables" || tasks == "check") && using ReadStatTables
const loaded = time()

const PKG = Dict("ours" => "DtaParser", "readstattables" => "ReadStatTables", "statfiles" => "StatFiles")[reader]
version() = string(pkgversion(getfield(Main, Symbol(PKG))))

statfiles_read(p) = DataFrame(load(p))
readers = Dict(
    "ours" => (
        read = p -> read_dta(p),
        five = (p, c) -> read_dta(p; cols=c),
        window = (p, s, k) -> read_dta(p; skip=s, n_max=k),
        meta = p -> read_meta(p),
        write = (t, dst) -> write_dta(dst, t)),
    "readstattables" => (
        read = p -> readstat(p),
        five = (p, c) -> readstat(p; usecols=c),
        window = (p, s, k) -> readstat(p; row_offset=s, row_limit=k),
        meta = p -> ReadStatTables.readstatallmeta(p),
        write = (t, dst) -> writestat(dst, t)),
    # StatFiles reads whole files only, has no metadata read and no writer.
    "statfiles" => (
        read = statfiles_read,
        five = (p, c) -> statfiles_read(p)[:, c],
        window = (p, s, k) -> statfiles_read(p)[s+1:min(s + k, end), :],
        meta = p -> error("StatFiles has no metadata-only read"),
        write = (t, dst) -> error("StatFiles has no writer")),
)
r = readers[reader]
# In-process runs stop early, after at least three, once they pass this
# many seconds.
const BUDGET = 60

# Plain values: ReadStatTables wraps labelled columns.
plain(col) = (reader == "readstattables" && col isa ReadStatTables.LabeledArray) ? DataAPI.refarray(col) : col

# A value as Stata stores it (dates convert to Date and DateTime).
stata(x::Real) = Float64(x)
stata(x::Date) = Float64(Dates.value(x - Date(1960, 1, 1)))
stata(x::DateTime) = Float64(Dates.value(x - DateTime(1960, 1, 1)))
stata(x::Dates.Time) = Float64(Dates.value(x)) / 1e6

is_text(col) = nonmissingtype(eltype(col)) <: Union{AbstractString,AbstractVector{UInt8}}

# Task 2: one pass over every value, a function per column so that each
# loop is compiled for the column's type.
function text_length(col)
    len = 0
    for s in col
        ismissing(s) || (len += length(s))
    end
    len
end

function number_sum(col)
    total = 0.0; nmissing = 0
    for x in col
        if ismissing(x)
            nmissing += 1
        else
            total += stata(x)
        end
    end
    total, nmissing
end

function checksum(t)
    total = 0.0; nmissing = 0; len = 0
    for col in Tables.columns(t)
        col = plain(col)
        if is_text(col)
            len += text_length(col)
        else
            s, m = number_sum(col)
            total += s; nmissing += m
        end
    end
    Dict("sum" => total, "missing" => nmissing, "length" => len)
end

function run_task(task)
    if task == 6
        reader == "statfiles" && r.write(nothing, "")  # no writer: fail before reading
        t = r.read(path)
        dst = joinpath(tmp, "w$(getpid()).dta")
        GC.gc()
        elapsed = @elapsed r.write(t, dst)
        rm(dst; force=true)
        return elapsed, nothing
    end
    GC.gc()
    out = nothing
    elapsed = @elapsed begin
        if task == 1
            r.read(path)
        elseif task == 2
            out = checksum(r.read(path))
        elseif task == 3
            r.five(path, cols)
        elseif task == 4
            r.window(path, skip, n)
        elseif task == 5
            r.meta(path)
        end
    end
    elapsed, out
end

# Correctness: each column as a hash of its canonical cells.
short(h) = bytes2hex(h)[1:16]
hash_text(s) = s === nothing ? nothing : short(sha256(string(s)))

function canon_column(col)
    col = plain(col)
    if is_text(col)
        io = IOBuffer()
        for s in col
            ismissing(s) || write(io, s isa AbstractString ? String(s) : s)
            write(io, 0x00)
        end
        write(io, string(length(col)))
        return Dict("kind" => "str", "hash" => short(sha256(take!(io))))
    end
    v = Float64[ismissing(x) ? 0.0 : stata(x) for x in col]
    miss = UInt8[ismissing(x) for x in col]
    ctx = SHA.SHA256_CTX()
    SHA.update!(ctx, reinterpret(UInt8, v))
    SHA.update!(ctx, miss)
    codes = reader == "ours" && col isa DtaColumn ? short(sha256(col.codes)) : nothing
    Dict("kind" => "num", "hash" => short(SHA.digest!(ctx)), "codes" => codes)
end

canon_frame(t) = Dict("nrows" => length(first(Tables.columns(t))),
                      "columns" => [canon_column(c) for c in Tables.columns(t)])

key_text(k::AbstractChar) = string('.', k)
key_text(k::Real) = reader == "ours" && DtaParser.key_code(k) > 1 ? string('.', Char('a' + DtaParser.key_code(k) - 2)) :
                    reader == "ours" && DtaParser.key_code(k) == 1 ? "." : fmt17(Float64(k))
fmt17(x) = (s = string(x); endswith(s, ".0") ? s[1:end-2] : s)

label_text(labels) = labels === nothing ? hash_text("") :
    hash_text(join(sort([string(key_text(k), "\t", v) for (k, v) in labels]), "\n"))

const RST_STORAGE = Dict("READSTAT_TYPE_INT8" => "byte", "READSTAT_TYPE_INT16" => "int", "READSTAT_TYPE_INT32" => "long",
                         "READSTAT_TYPE_FLOAT" => "float", "READSTAT_TYPE_DOUBLE" => "double",
                         "READSTAT_TYPE_STRING" => "str", "READSTAT_TYPE_STRING_REF" => "strL")

function canon_meta(p, who)
    if who == "ours"
        m = read_meta(p)
        sets = m["value_labels"]
        columns = [Dict("name" => hash_text(c["name"]), "storage" => c["storage"], "format" => c["format"],
                        "label" => hash_text(c["label"]),
                        "value_labels" => label_text(get(sets, c["value_labels"], nothing)))
                   for c in m["columns"]]
        return Dict("label" => hash_text(m["label"]), "columns" => columns)
    end
    m, names, cm, vl = ReadStatTables.readstatallmeta(p)
    columns = [Dict("name" => hash_text(names[i]), "storage" => RST_STORAGE[string(cm.type[i])],
                    "format" => cm.format[i], "label" => hash_text(cm.label[i]),
                    "value_labels" => label_text(get(vl, cm.vallabel[i], nothing)))
               for i in eachindex(names)]
    Dict("label" => hash_text(m.file_label), "columns" => columns)
end

function attempt(f)
    try
        f()
    catch e
        Dict("error" => first(sprint(showerror, e), 500))
    end
end

function check()
    out = Dict{String,Any}()
    t = nothing
    out["full"] = attempt(() -> (t = r.read(path); canon_frame(t)))
    if t !== nothing
        out["checksum"] = attempt(() -> begin
            s = checksum(t)
            s["abs"] = sum((sum(x -> ismissing(x) ? 0.0 : abs(stata(x)), plain(c); init=0.0)
                            for c in Tables.columns(t) if !is_text(plain(c))); init=0.0)
            s
        end)
    end
    if reader == "statfiles"
        # Its selections are slices of a full read; slice the one made above.
        t === nothing || (out["five"] = attempt(() -> canon_frame(t[:, cols])))
        t === nothing || (out["window"] = attempt(() -> canon_frame(t[skip+1:min(skip + n, end), :])))
    else
        out["five"] = attempt(() -> canon_frame(r.five(path, cols)))
        out["window"] = attempt(() -> canon_frame(r.window(path, skip, n)))
    end
    out["meta"] = reader == "statfiles" ? Dict("error" => "StatFiles has no metadata read") :
                  attempt(() -> canon_meta(path, reader))
    if t !== nothing
        dst = joinpath(tmp, "check$(getpid()).dta")
        out["write"] = attempt(() -> begin
            r.write(t, dst)
            # Re-read by an open-source reader (ReadStatTables), as is the source.
            back = readstat(dst)
            global reader = "readstattables"
            Dict("data" => canon_frame(back), "meta" => canon_meta(dst, "readstattables"))
        end)
        rm(dst; force=true)
    end
    out
end

# A small JSON writer: Dicts, vectors, strings, numbers, nothing.
json(io, x::AbstractDict) = (print(io, "{"); join(io, [sprint(json, string(k)) * ":" * sprint(json, v) for (k, v) in x], ","); print(io, "}"))
json(io, x::Union{AbstractVector,Tuple}) = (print(io, "["); join(io, [sprint(json, v) for v in x], ","); print(io, "]"))
json(io, x::AbstractString) = print(io, '"', replace(x, '\\' => "\\\\", '"' => "\\\"",
                                                        r"[\x00-\x1f]" => c -> "\\u" * string(UInt8(c[1]); base=16, pad=4)), '"')
json(io, x::Real) = isfinite(x) ? print(io, x) : print(io, "null")
json(io, ::Nothing) = print(io, "null")

report = Dict{String,Any}("loaded" => loaded, "version" => version())
if tasks == "check"
    report["check"] = check()
else
    report["tasks"] = Dict{String,Any}()
    for task in parse.(Int, split(tasks, ","))
        entry = Dict{String,Any}()
        try
            times = Float64[]
            n_runs = runs
            if runs > 1
                entry["first"], entry["checksum"] = run_task(task)
                # Too slow to repeat: the one run counts.
                entry["first"] > BUDGET && (push!(times, entry["first"]); n_runs = 0)
            end
            for _ in 1:n_runs
                seconds, entry["checksum"] = run_task(task)
                push!(times, seconds)
                length(times) >= 3 && sum(times) > BUDGET && break
            end
            entry["times"] = times
        catch e
            entry["error"] = first(sprint(showerror, e), 500)
        end
        report["tasks"][string(task)] = entry
    end
end
open(io -> json(io, report), out_path, "w")
