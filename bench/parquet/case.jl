# One Parquet benchmark case in Julia, in a fresh process;
# bench/parquet/run.py --lang julia runs it under /usr/bin/time -l, five
# times per case.
#
#   julia --project=bench/julia bench/parquet/case.jl LIB TASK FILE OUT COLS SKIP N
#
# LIB is ours (Datakit), parquet2 (Parquet2.jl) or duckdb (DuckDB.jl).
# Every read gives a DataFrame (plan 0019): Datakit's read_parquet returns
# one, with its metadata; Parquet2's and DuckDB's are collected into one.
# TASK is one of
#   full    read the whole file into a DataFrame
#   five    read five named columns (COLS, comma-separated)
#   window  read N rows from row SKIP (0-based)
#   pass    read the whole file, then one pass over every value
#   write   read FILE (a .dta) with DtaParser into a DataFrame, then time
#           writing it with LIB's defaults
#   zstd    the same, with zstd at level 3 (Parquet2 has no levels: its
#           zstd default)
# Only the task is timed (wall time, and CPU time of the process and its
# threads, user plus system); OUT gets a JSON report. Each library runs
# with its default threads: Julia's (one thread unless JULIA_NUM_THREADS
# says otherwise), which Parquet2 uses, DuckDB's own, and ours.

const lib, task, path, out_path = ARGS[1], ARGS[2], ARGS[3], ARGS[4]
const cols = filter(!isempty, split(ARGS[5], ","))
const skip, n = parse(Int, ARGS[6]), parse(Int, ARGS[7])

using DataFrames, Dates, DtaParser
import Tables
if lib == "ours"
    using Datakit
end
if lib == "parquet2"
    using Parquet2
elseif lib == "duckdb"
    using DuckDB
end
const loaded = time()

cpu() = ccall(:clock, Culong, ()) / 1e6
quoted(x) = "\"" * replace(x, "\"" => "\"\"") * "\""
sql_path(p) = "'" * replace(p, "'" => "''") * "'"

# The window: Parquet2 reads whole row groups, so the shortest route reads
# the row groups that hold the rows and keeps the rows.
function parquet2_window(p, skip, n)
    ds = Parquet2.Dataset(p)
    parts = DataFrame[]
    first = 0
    for g in 1:length(ds)
        rows = nrow(ds[g])
        if first + rows > skip && first < skip + n
            push!(parts, DataFrame(ds[g]; copycols=false))
        elseif first >= skip + n
            break
        end
        first += rows
    end
    d = vcat(parts...)
    start = skip - (first - sum(nrow, parts; init=0)) + 1
    d[start:min(start + n - 1, nrow(d)), :]
end

function run_duck(sql)
    db = DuckDB.DB()
    con = DBInterface.connect(db)
    DataFrame(DBInterface.execute(con, sql))
end

function read_case(lib, task, p)
    if lib == "ours"
        task == "five" && return read_parquet(p; cols, timestamps=:truncate)
        task == "window" && return read_parquet(p; skip, n_max=n, timestamps=:truncate)
        return read_parquet(p; timestamps=:truncate)
    elseif lib == "parquet2"
        task == "five" && return DataFrame(Parquet2.Dataset(p) |> Parquet2.select(Symbol.(cols)...); copycols=false)
        task == "window" && return parquet2_window(p, skip, n)
        return DataFrame(Parquet2.Dataset(p); copycols=false)
    else
        task == "five" && return run_duck("SELECT " * join(quoted.(cols), ", ") * " FROM read_parquet(" * sql_path(p) * ")")
        task == "window" && return run_duck("SELECT * FROM read_parquet($(sql_path(p))) LIMIT $n OFFSET $skip")
        return run_duck("SELECT * FROM read_parquet($(sql_path(p)))")
    end
end

# One pass over every value: the sum of the numbers, the count of missing
# values and the total length of text and bytes, the same loop for every
# library, so that deferred work is done.
function pass_column(v)
    total, missings, len = 0.0, 0, 0
    for x in v
        if ismissing(x)
            missings += 1
        elseif x isa Real
            total += Float64(x)
        elseif x isa AbstractString
            len += ncodeunits(x)
        elseif x isa Dates.TimeType
            total += Float64(Dates.value(x))
        elseif x isa AbstractVector{UInt8}
            len += length(x)
        end
    end
    total, missings, len
end

function pass(t)
    total, missings, len = 0.0, 0, 0
    for name in Tables.columnnames(t)
        a, b, c = pass_column(Tables.getcolumn(t, name))
        total += a
        missings += b
        len += c
    end
    Dict("sum" => total, "missing" => missings, "length" => len)
end

function write_case(lib, task, d, dst)
    if lib == "ours"
        task == "zstd" ? save_parquet(dst, d; compression=:zstd, compression_level=3) : save_parquet(dst, d)
    elseif lib == "parquet2"
        task == "zstd" ? Parquet2.writefile(dst, d; compression_codec=:zstd) : Parquet2.writefile(dst, d)
    else
        db = DuckDB.DB()
        con = DBInterface.connect(db)
        DuckDB.register_data_frame(con, d, "t")
        opts = task == "zstd" ? "(FORMAT parquet, COMPRESSION zstd, COMPRESSION_LEVEL 3)" : "(FORMAT parquet)"
        DBInterface.execute(con, "COPY t TO $(sql_path(dst)) $opts")
    end
end

# A frame as each library takes it: ours the DataFrame of read_dta's
# table, with its DtaColumns and metadata; the others a DataFrame of
# plain vectors (not timed), since a DtaColumn is not a type they know.
function frame_for(lib, t)
    d = DataFrame(t; copycols=false)
    lib == "ours" && return d
    for name in names(d)
        x = d[!, name]
        x isa DtaColumn && (d[!, name] = collect(x))
    end
    d
end

const versions = Dict("ours" => () -> string(pkgversion(Datakit)),
                      "parquet2" => () -> string(pkgversion(Parquet2)),
                      "duckdb" => () -> string(pkgversion(DuckDB)))
threads = lib == "ours" ? get(ENV, "DTA_THREADS", "default") :
          lib == "parquet2" ? string(Threads.nthreads()) :
          string(only(run_duck("SELECT current_setting('threads') AS t").t))

result = Dict{String,Any}("loaded" => loaded, "version" => versions[lib](), "threads" => threads)
if task in ("write", "zstd")
    d = frame_for(lib, read_dta(path))
    dst = joinpath(dirname(abspath(out_path)), "w$(getpid()).parquet")
    GC.gc()
    t0, c0 = time(), cpu()
    write_case(lib, task, d, dst)
    result["wall"], result["cpu"] = time() - t0, cpu() - c0
    result["bytes"] = filesize(dst)
    rm(dst; force=true)
else
    GC.gc()
    t0, c0 = time(), cpu()
    out = task == "pass" ? pass(read_case(lib, "full", path)) : read_case(lib, task, path)
    result["wall"], result["cpu"] = time() - t0, cpu() - c0
    if task == "pass"
        result["checksum"] = out
    else
        result["rows"] = Tables.rowcount(out)
    end
end
write(out_path, DtaParser.json(result))
