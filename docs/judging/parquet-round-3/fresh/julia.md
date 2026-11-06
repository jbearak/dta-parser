# Julia Parquet docs check (Datakit), fresh3

Source of truth: only `julia/docs.md`. Julia 1.13.3 on macOS arm64, with depot and project under `scratch/` (`depot/`, `proj/`).
Scripts are in `scratch/` (`t1.jl`, `t02.jl`, `t03_05.jl`, `t06.jl` … `t11.jl`, `t11w.R`); outputs in `t*.out`. `run.sh` sets the depot and project.
Every file read was written by me: with Datakit/DtaParser, and for task 11 with R's arrow (`t11w.R`). No Stata was run.

## Environment notes (not doc problems, but they cost time)

- This sandbox's network proxy breaks Julia's built-in git (libgit2) and its downloader. Pkg segfaulted cloning the registry. `JULIA_PKG_USE_CLI_GIT=true` fixed that, and `JULIA_SSL_CA_ROOTS_PATH=/etc/ssl/cert.pem` fixed the TimeZones artifact download. This is environment-specific.
- Every `using Datakit` printed `Failed to open ptm` stack traces from a REPL-stdlib precompile workload. They are harmless. Loading took about 15 s warm and about 65 s after a package change.
- Two runs hung until their timeout (the first `t07`, and one `t11`). I think a stale precompile pidfile left by a process I had killed was the cause. Re-running worked.

## Task 1 — succeeded

```julia
import Pkg; Pkg.activate(".../scratch/proj")
Pkg.develop(path=".../checkout/julia/DtaParser")
Pkg.develop(path=".../checkout/julia/Datakit")
Pkg.build("DtaParser")
Pkg.add("DataFrames"); Pkg.add(["TimeZones", "CategoricalArrays"])
using Datakit; using DataFrames, TimeZones, CategoricalArrays
```

Everything loaded ("loaded Datakit", "loaded all"). `Pkg.build` ran cargo with no output, as the docs warn.
Docs gap: the Install text says cargo and a C compiler are needed, but not that the build needs network access to crates.io. It also does not say that the first `using Datakit` after install precompiles for about a minute.

## Task 2 — succeeded

```julia
t = DataFrame(i=Int32[1:6;], f=[1.5,...], s=["a",...], b=[true,...], d=[Date(2024,3,k) for k in 1:6], ts=[DateTime(2024,3,1,9,30)+Hour(k) for k in 1:6])
save_parquet("t02.parquet", t); p = read_parquet("t02.parquet")
```

Types: `i` Vector{Int32}, `f` Float64, `s` String, `b` Bool, `d` Date, `ts` DateTime. `isequal(p, t)` is true. This matches the docs.

## Task 3 — succeeded

- `read_parquet(f; cols=[:s,:i])` gives `["s","i"]`, the reverse of file order. Strings (`["f","i"]`) and positions (`[6,1]` gives `["ts","i"]`) work too.
- A missing name raises `ArgumentError: column "weight" is not in the file; its columns are "i", "f", "s", "b", "d", "ts"`, as documented.

## Task 4 — succeeded

- `skip=2, n_max=3` gives rows 3 to 5 (i = 3, 4, 5).
- `skip=10` gives a 0×6 frame with all column names and types kept, no error (as documented).
- `skip=4, n_max=10` gives the 2 remaining rows, no error.
- Docs gap, minor: "past the end is no error" is shown only for `skip`. That `n_max` past the end returns what is left is implied by "at most n_max" and is not shown.

## Task 5 — succeeded

```julia
m = read_parquet_info("t02.parquet")
```

- `nrows` 6.
- `row_groups` `[(rows=6, compressed_bytes=300, uncompressed_bytes=313)]`.
- `compression` `["snappy"]`.
- `created_by` "dta-parquet version 0.1.0".
- `key_value` keys `["dta","ARROW:schema"]`; the `dta` value is `{"version":1}`.
- `columns` DataFrame with name, eltype, physical_type and logical_type (INT32, DOUBLE, BYTE_ARRAY/STRING, BOOLEAN, INT32/DATE, INT64/`TIMESTAMP(MILLIS, local)`).
- `warnings` is `String[]`.

## Task 6 — succeeded

```julia
survey = (id=Int32[1:6;], region=Int8[1,2,2,3,4,1], income=DtaColumn([2100.0,0,1850,0,0,3200.0], UInt8[0,5,0,1,27,0]))
write_dta("t06.dta", survey; label=..., column_labels=Dict(:region=>"Region of residence", ...),
  value_labels=Dict("region"=>Dict(1=>"North",...), "nonresponse"=>Dict(".d"=>"Don't know", ".z"=>"Zed")),
  column_value_labels=Dict(:region=>"region", :income=>"nonresponse"))
save_parquet("t06.parquet", DataFrame(read_dta("t06.dta"))); p = read_parquet("t06.parquet")
```

- `colmetadata(p,:region,"label")` is "Region of residence".
- `colmetadata(p,:region,"value_labels")` is "region".
- `labels = metadata(p,"value_labels")["region"]` is `Dict(3.0=>"East", 2.0=>"South", 1.0=>"North", 4.0=>"West")`. `labels[3.0]` and `labels[dta_key(3)]` both give "East".
- Categorical, with CategoricalArrays loaded: `categorical([labels[x] for x in p.region]; levels=[labels[k] for k in sort(collect(keys(labels)))])` gives a `CategoricalVector{String,UInt32}`, levels North, South, East, West.
- Doc problem (small): in the categorical recipe, bare `levels(region)` returns `CategoricalValue`s, not strings. The docs' `String.(levels(...))` form is needed, and the prose does not say why.

## Task 7 — succeeded

```julia
d = DataFrame(day=[Date(2024,3,1),Date(2024,3,4)], local_ts=[DateTime(2024,3,1,9,30),DateTime(2024,3,4,17,5,0,250)])
d.zoned = ZonedDateTime.([DateTime(2024,3,1,9,30),DateTime(2024,7,1,9,30)], tz"America/New_York")
save_parquet("t07.parquet", d); v = read_parquet("t07.parquet")
```

| column | reads back as | file |
|---|---|---|
| `day` | `Date` | INT32 DATE |
| `local_ts` | `DateTime`, 17:05:00.250 kept | INT64 `TIMESTAMP(MILLIS, local)` |
| `zoned` | `ZonedDateTime`, 2024-03-01T09:30-05:00 and 2024-07-01T09:30-04:00, `timezone` is America/New_York | INT64 `TIMESTAMP(MILLIS, UTC)`, i.e. adjusted to UTC |

The profile holds `{"version":1,"columns":{"zoned":{"tz":"America/New_York"}}}`. Reading the zoned file without TimeZones loaded gives a `DateTime` in UTC (14:30 and 13:30) plus the documented warning: "TimeZones.jl is not loaded, so these columns' times are DateTime in UTC, without their zones: zoned (America/New_York)".
There is no doc problem. The docs' "TIMESTAMP(MILLIS, local)" label matches.

## Task 8 — succeeded

```julia
save_parquet("t08.parquet", p; compression=:zstd, compression_level=5, row_group_size=4)
```

- Metadata shows `compression ["zstd"]` and row groups `[4, 2]` (6 rows).
- `compression=:lzo` raises `ArgumentError: compression must be :snappy, :zstd, :gzip, :lz4_raw or :none, not :lzo`, as documented.
- `:zstd, compression_level=99` raises `DtaParser.WriteError: zstd levels run from 1 to 22, not 99`.
- `:snappy` with a level raises `WriteError: snappy has no compression levels`.
- A `Time` column raises `WriteError: column t: cannot write values of type Time; Parquet TIME columns are read, not written`.
- A `UInt64` above `typemax(Int64)` raises `WriteError: column x: row 1 holds 18446744073709551615, more than a 64-bit integer holds`.
- No partial file was left behind (`bad.parquet` does not exist).
- Docs gap: the Julia docs name `ArgumentError` for the compression error but never name `DtaParser.WriteError` as the type of the others, and the exported name is not shown. The level errors appear only in the R-flavoured shared table in `parquet.md`, as "`zstd levels run from 1 to 22, not 99`", with no mention of Julia's `compression_level`.

## Task 9 — succeeded

The docs' "Write labels" example, run as written (`t09.jl`). Read back:

- `metadata(s,"label")` "Smoking"; `notes` `["Wave 2 only."]`.
- `colmetadata(s,:id,"label")` "Person"; `(s,:smoker,"label")` "Smokes daily"; `:smoker` value_labels "yesno".
- `yesno = Dict(1.0=>"Yes", 8.99724347282165e307=>"Don't know", 0.0=>"No")`.
- `[get(yesno, dta_key(s.smoker,i), "") for i in 1:3]` gives `["Yes","No","Don't know"]`.
- The dta profile JSON in the footer shows the labels and value labels.
- Note: `s.smoker` is a `DtaColumn{Int8}` (codes 0, 0, 5), and `id` comes back as `Int64`.

## Task 10 — succeeded

```julia
x = DataFrame(v = DtaColumn([1.5,0,0,0,7.0], UInt8[0,1,2,27,0]))   # 1.5, ., .a, .z, 7
save_parquet("t10.parquet", x); r = read_parquet("t10.parquet")
```

- `r.v` is a `DtaColumn{Float64}`.
- `stata_code` gives `[0,1,2,27,0]`, so `.`, `.a` and `.z` are told apart; `ismissing` is true for all three.
- `dta_key` gives `[1.5, 8.988e307, 8.9907e307, 9.0455e307, 7.0]`.
- `colmetadata(r,:v,"storage")` is "double", and the file column is DOUBLE.
- With `missing_letters=false`, all three read back as code 1 (`.`) in a `Vector{Union{Missing,Float64}}`, as documented.
- The docs say other tools see NaN in place of `.a` to `.z`.
  - Parquet2.jl keeps the bits.
  - DuckDB SQL and polars count NaN as a value (`IS NULL` false, `count(x)` counts them, `mean(x)` is NaN).
  - R's datakit, arrow, nanoparquet and Python's datakit read the letters back.
  - For files meant for other tools, use `missing_letters = false`, which writes nulls and loses the letters.
- Doc gap, small: the code numbering (1 is `.`, 2 to 27 are `.a` to `.z`) is stated only in a comment in the `set_stata_code!` recipe. A reader building a `DtaColumn` for the first time has to find that comment.

## Task 11 — succeeded

No pyarrow, polars, duckdb or fastparquet is installed here (pandas has no Parquet engine), so I used R's arrow 26.0.0 (`t11w.R`): `write_parquet(df, "t11_arrow.parquet")` with integer, double with NA, character with NA, logical, Date, POSIXct with microseconds and a factor.

- `read_parquet(f)` fails as the docs show: `column "ts": row 1 is 1709285400123456 microseconds, which is not a whole number of milliseconds, all a DateTime holds; read with read_parquet("t11_arrow.parquet"; timestamps = :truncate) ...`.
- With `timestamps=:truncate` it reads. `ts` is a `DateTime` with 09:30:00.123, the microseconds cut. `x`, `s` and `b` are `Union{Missing,T}`.
- The factor `f` is a `String` plus the documented CategoricalArrays warning. With `using CategoricalArrays` it is a `CategoricalArray` with levels low, mid, high, unordered. `skip=1, n_max=2` gives levels `["mid","high"]`, as the docs warn.
- The docs list what this version does not read:
  - nested columns (an error unless `cols` leaves them out or `nested = :skip`);
  - FLOAT16 and INTERVAL;
  - the Hadoop framing of LZ4;
  - LZO;
  - encrypted files;
  - values encoded BIT_PACKED;
  - datasets of many files, Hive partitions and filters pushed into the read.
- Doc problem, minor: `docs/parquet.md`'s general error table tells readers to "check the name against `read_parquet_info(file)$columns$name`". That is R syntax, and in Julia it is `read_parquet_info(f)["columns"].name`.
