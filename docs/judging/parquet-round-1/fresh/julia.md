# Julia docs check: Datakit Parquet, 11 tasks

Source of truth: `/private/tmp/claude-501/gate2/fresh/julia/docs.md` only. Julia 1.13.3, arm64 macOS.
Checkout: `/private/tmp/claude-501/gate2/fresh/julia/checkout`. Depot and project are under `scratch/`.
Scripts: `t1.jl` (install), `t2_5.jl`, `t6_10.jl`, `t11_write.R`, `t11.jl`, `t11b.jl`. Outputs are the `.out` files beside them.
No Stata was run. Every `.dta` and Parquet file was written by me: with Datakit and DtaParser, or with R's arrow for task 11.
I did not read the repo's `compat/parquet/fixtures` files that the docs' "other tools" example points at, because I did not write them.

## Environment notes (not doc problems)
- The sandbox proxy re-signs TLS, so Pkg's registry download failed with "unable to get local issuer certificate", and then hung or segfaulted.
  Fixed with `JULIA_SSL_CA_ROOTS_PATH=/etc/ssl/cert.pem`.
- Julia's REPL stdlib precompile prints "Failed to open ptm" stack traces in the sandbox, which has no pty. Harmless: the packages still load.
- Twice, `using TimeZones, CategoricalArrays` hung partway through a script (the stack was in macOS SystemConfiguration). A rerun worked. I treat this as an environment flake.

## Task 1: Install Parquet's packages and check they load. Succeeded
```julia
import Pkg
Pkg.activate(".../scratch/proj")
Pkg.develop(path=".../checkout/julia/DtaParser")
Pkg.develop(path=".../checkout/julia/Datakit")
Pkg.build("DtaParser")                       # cargo, a few minutes the first time
Pkg.add("DataFrames")
Pkg.add(["TimeZones", "CategoricalArrays"])  # optional
using Datakit, DataFrames; using TimeZones, CategoricalArrays
```
Saw: "loaded OK" and "optional loaded OK".
The docs' order (develop DtaParser, then Datakit, then build) worked. docs/parquet.md's "Nothing beyond the package" fits julia.md.
Doc gap: `Pkg.build` runs cargo, which is slow. The only hint is "takes a minute the first time", and for me it was several minutes with no output.

## Task 2: Write a small table and read it back. Succeeded
```julia
t = DataFrame(i=[1,2,3,4,5,6], f=[1.5,...], s=["a",...], b=[true,false,...], d=Date.(2024,3,1:6), ts=DateTime(2024,3,1,9,30).+Hour.(0:5))
save_parquet("t2.parquet", t); r = read_parquet("t2.parquet")
```
Saw: a `DataFrame` with `i` Int64, `f` Float64, `s` String, `b` Bool, `d` Date, `ts` DateTime. This matches "What each type becomes".
Doc gap: the "Read a Parquet file" examples use `survey.dta`, which comes from an "example file" section that is not in the docs I was given. They cannot be run as given.

## Task 3: Read two columns in reverse order. Succeeded
```julia
names(read_parquet("t2.parquet"; cols=[:s, :i]))   # ["s","i"]
names(read_parquet("t2.parquet"; cols=[6, 1]))     # ["ts","i"]
read_parquet("t2.parquet"; cols=[:i, :weight])
```
Saw: columns come back in the order given. An unknown name raises `ArgumentError: column "weight" is not in the file; its columns are "i", "f", "s", "b", "d", "ts"`, exactly as documented.
Unclear: the docs don't say whether names and positions can be mixed in one `cols`. I did not test it.

## Task 4: Read rows 3 to 5 only. Succeeded
```julia
read_parquet("t2.parquet"; skip=2, n_max=3)    # ids 3,4,5
nrow(read_parquet("t2.parquet"; skip=10))      # 0
nrow(read_parquet("t2.parquet"; skip=4, n_max=10))   # 2
```
Saw: rows 3 to 5 as expected. `skip` past the end gives a 0-row frame that keeps all the columns, with no error. An `n_max` that runs past the end just returns the rows left.
Doc gap: the docs state the `skip` past the end case ("past the end is no error") but not the `n_max` overrun. The behaviour is the sensible one.

## Task 5: Metadata without the data. Succeeded
```julia
m = read_parquet_info("t2.parquet")
m["columns"][:, [:name,:eltype,:physical_type,:logical_type]]; m["nrows"]; m["row_groups"]; m["compression"]; m["key_value"]
```
Saw:
- Columns: INT64, DOUBLE, BYTE_ARRAY/STRING, BOOLEAN, INT32/DATE, INT64/`TIMESTAMP(MILLIS, local)`.
- `nrows` = 6.
- `row_groups` = `[(rows = 6, compressed_bytes = 316, uncompressed_bytes = 337)]`.
- `compression` = `["snappy"]`.
- `key_value` = `dta` (`{"version":1}`) and `ARROW:schema`.
Doc gap: a file with no labels still gets a `{"version":1}` profile entry. That is probably fine, but the docs never say so.

## Task 6: `.dta` into Parquet, then labels and categorical. Succeeded
```julia
write_dta("task6.dta", (id=Int32[...], region=Int8[1,2,2,3,4,1], income=DtaColumn(...)); label="Task 6 data",
  value_labels=Dict("regionlbl"=>Dict(1=>"North",2=>"South",3=>"East",4=>"West")),
  column_labels=Dict(:id=>"Person id", :region=>"Region of residence", :income=>"Monthly income"),
  column_value_labels=Dict(:region=>"regionlbl"))
save_parquet("task6.parquet", DataFrame(read_dta("task6.dta"))); p = read_parquet("task6.parquet")
colmetadata(p,:region,"label")                          # "Region of residence"
labels = metadata(p,"value_labels")["regionlbl"]        # Dict{Float64,String}
labels[3.0]                                             # "East"
region = categorical([labels[x] for x in p.region]; levels=[labels[k] for k in sort(collect(keys(labels)))])
```
Saw: the variable label, the set name `regionlbl`, and `labels[3.0] == "East"`. The categorical has levels North, South, East, West.
`metadata(p,"label")` returned "Task 6 data".
Unclear (docs):
- The `write_dta` keyword shapes (`value_labels`, `column_labels`, and the rest) are not documented in what I was given. I copied them from the README and the Parquet "Write labels" example.
- `levels(region)` returns `CategoricalValue`s. The docs' example wraps it in `String.(...)`, which is needed to see plain text.
- The `Int32` `id` column came back as `Int8`: `write_dta` narrowed it to the "byte" storage type. The Julia docs I have don't say that `write_dta` narrows integer storage types.
- `labels` has `Float64` keys (stated in the docs as "a Dict from dta_key to text"). The key type is surprising, though `labels[3]` works as well.

## Task 7: Date, timestamp without zone, timestamp with zone. Succeeded
```julia
dts = DataFrame(day=[Date(2024,3,1),Date(2024,3,4)], naive=[DateTime(2024,3,1,9,30),DateTime(2024,3,4,17,5,0,250)],
  zoned=ZonedDateTime.([DateTime(2024,3,1,9,30),DateTime(2024,7,1,9,30)], tz"America/New_York"))
save_parquet("task7.parquet", dts); v = read_parquet("task7.parquet"); read_parquet_info("task7.parquet")
```
Saw:
- `day` is `Date`, written as INT32/DATE.
- `naive` is `DateTime`, written as `TIMESTAMP(MILLIS, local)`, milliseconds, no zone. The .250 survived.
- `zoned` is `ZonedDateTime` in America/New_York (offsets -05:00 and -04:00 kept), written as `TIMESTAMP(MILLIS, UTC)`, an instant adjusted to UTC. The profile holds `{"zoned":{"tz":"America/New_York"}}`.
- Without TimeZones.jl (checked in task 11), the warning is: "TimeZones.jl is not loaded, so these columns' times are DateTime in UTC, without their zones".
Doc gap: the info table's `logical_type` strings (`local`, `UTC`) are not explained. The write-side table says "not adjusted to UTC" and "adjusted to UTC", and the two do map onto each other.

## Task 8: Codec, row group size, and an error. Succeeded
```julia
save_parquet("task8.parquet", p; compression=:zstd, compression_level=9, row_group_size=4)
m = read_parquet_info("task8.parquet"); m["compression"]; m["row_groups"]
save_parquet("bad1.parquet", p; compression=:lzo)
save_parquet("bad2.parquet", p; compression=:zstd, compression_level=99)
save_parquet("bad3.parquet", p; compression=:snappy, compression_level=3)
save_parquet("bad4.parquet", DataFrame(t=[Time(1,2)]))
```
Saw: `compression` = `["zstd"]`. The row groups are `[(rows=4,...), (rows=2,...)]`, which is 6 rows at a size of 4. It reads back equal.
Errors:
- `:lzo` gives `ArgumentError: compression must be :snappy, :zstd, :gzip, :lz4_raw or :none, not :lzo`, exactly as documented.
- zstd level 99 gives `DtaParser.WriteError: zstd levels run from 1 to 22, not 99`.
- snappy with a level gives `WriteError: snappy has no compression levels`.
- A `Time` column gives `WriteError: column t: cannot write values of type Time; Parquet TIME columns are read, not written`, which matches the table.
- A failed write left no file behind.
Doc gap: the Julia docs name `ArgumentError` for `:lzo`, but the level errors and the `Time` error are `DtaParser.WriteError`, a type the Julia docs never mention. The level messages are documented only in the shared errors table, written with R argument names (`compression_level` and `NULL`).

## Task 9: Variable label, value labels, data label. Succeeded
The docs' "Write labels" example, run as written.
Saw: data label "Smoking", notes `["Wave 2 only."]`, `id` label "Person", `smoker` label "Smokes daily" with set `yesno`, and `["Yes","No","Don't know"]` looked up with `dta_key`.
The footer's profile JSON shows all of it. `smoker` is a `DtaColumn{Int8}`, codes `[0,0,5]`.
No doc problems.

## Task 10: `.`, `.a`, `.z`. Succeeded
In `task6.dta`, `income` has codes `UInt8[0,1,0,2,27,0]` (value, `.`, value, `.a`, `.z`, value). Directly: `DtaColumn([1.0,0,0,0], UInt8[0,1,2,27])`.
Saw after write and read:
- The column is `DtaColumn{Float64}`, codes `[0,1,0,2,27,0]`. `stata_code` tells `.` (1), `.a` (2) and `.z` (27) apart.
- `ismissing` is true for all three, as documented, and the values collect as `missing`.
- `dta_key` gives distinct numbers: `.` is 1.0, `.a` is about 8.9885e307, `.z` is about 9.0455e307.
- The file's column is DOUBLE; `colmetadata(:income,"storage")` is "double".
- `missing_letters=false` gives `Vector{Union{Missing,Float64}}`, codes 0 and 1 only, so the letters are lost.
Docs on other tools:
- In Julia: "Other tools see NaN: Parquet2.jl keeps the bits, and DuckDB SQL and polars count a NaN as a value rather than a missing one".
- docs/parquet.md also says pyarrow reads NaN, pandas reads missing, and R's arrow, nanoparquet and DuckDB in R read a tagged NA with the letter kept.
Doc gap: the docs give code numbers (1 is `.`, 2 to 27 are `.a` to `.z`) only inside a code comment in a different section.

## Task 11: A file another tool wrote. Succeeded
Tool: R arrow 26.0.0 (pyarrow, polars, DuckDB, fastparquet, nanoparquet and the duckdb CLI are not installed here; Python's pandas has no Parquet engine). I wrote `t11_arrow.parquet` (zstd, with an integer, double, string, factor, date, a microsecond timestamp, a Paris-zone timestamp and a logical), `t11_arrow_snappy.parquet` and `t11_nested.parquet` (a list column).
```julia
read_parquet("t11_arrow.parquet")                          # error
read_parquet("t11_arrow.parquet"; timestamps=:truncate)    # works
read_parquet("t11_nested.parquet")                         # error; nested=:skip and cols=[:id] work
```
Saw:
- The default read raises `DtaParser.DtaError: column "ts": row 2 is 1709285401000003 microseconds, which is not a whole number of milliseconds ... read with read_parquet("t11_arrow.parquet"; timestamps = :truncate)`, as the docs say.
- With `:truncate`, the types come out right.
- With neither TimeZones nor CategoricalArrays loaded, the zoned column reads as UTC `DateTime` and the factor as `String`, each with one warning.
- With both loaded, the zoned column is `ZonedDateTime` in Europe/Paris and the factor is a `CategoricalArray`. Its levels are in first-appearance order, `["lo","hi","mid"]` (arrow had lo, mid, hi), unordered, as documented.
- The nested file gives `ArgumentError: the file has nested columns, which are not read: "l"; select the columns wanted with cols, or pass nested = :skip`.
Docs on what this library does not read: nested columns (lists, maps, structs), FLOAT16, INTERVAL, the Hadoop framing of LZ4, LZO, encrypted files, datasets of many files, Hive partitions, and filters pushed into the read.
I did not make files with those types or codecs, except the nested one.
Doc gap: the error type for the timestamp case is `DtaParser.DtaError`, again not named in the Julia docs.
