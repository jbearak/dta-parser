# Julia: DtaParser.jl

DtaParser reads Stata `.dta` files into a Tables.jl table, which you can
turn into a DataFrame, and writes any Tables.jl table as a `.dta` file.
It reads every release from 104 to 119 and writes release 118. Numeric
columns keep Stata's missing values `.a` to `.z` through slicing,
sorting, filtering and writing, and labels travel as DataAPI metadata.

Contents:
[Install](#install) ·
[The example file](#the-example-file) ·
[Read a file](#read-a-file) ·
[Select columns](#select-columns) ·
[Read some rows](#read-some-rows) ·
[Metadata](#metadata) ·
[Missing values](#missing-values) ·
[Value labels](#value-labels) ·
[Dates](#dates) ·
[Write a file](#write-a-file) ·
[Recipes](#recipes) ·
[Coming from ReadStatTables.jl](#coming-from-readstattablesjl) ·
[Troubleshooting](#troubleshooting) ·
[API reference](#api-reference)

The [guide](guide/README.md) explains the Stata concepts behind each
section.

## Install

DtaParser needs Julia 1.10 or later. It is not in the General registry
yet, and it builds its native library from a checkout of the repository
with Rust's `cargo` ([rustup.rs](https://rustup.rs)):

```sh
git clone https://github.com/jbearak/dta-parser
```

```julia norun
import Pkg
Pkg.develop(path="dta-parser/julia/DtaParser")
Pkg.build("DtaParser")      # runs cargo; takes a minute the first time
Pkg.add("DataFrames")       # optional: for DataFrame(t)
```

DtaParser depends on Tables.jl and DataAPI.jl. DataFrames (1.4 or
later) is optional: when it is loaded, `DataFrame(t)` carries the
labels across as metadata.

## The example file

Every example on this page reads `survey.dta`. This block makes it; run
it first. It also shows most of what writing can do, which
[Write a file](#write-a-file) explains.

```julia
using DtaParser, DataFrames, Dates

survey = DataFrame(
    id = 1:6,
    region = Int8[1, 2, 2, 3, 4, 1],
    age = Int8[34, 51, 29, 62, 45, 38],
    # codes: 0 a number, 1 `.`, 5 `.d` ("don't know"), 19 `.r` ("refused")
    income = DtaColumn([2100.0, NaN, 1850.0, NaN, NaN, 3200.0], UInt8[0, 5, 0, 1, 19, 0]),
    interviewed = Date.(["2024-03-01", "2024-03-01", "2024-03-02", "2024-03-04", "2024-03-04", "2024-03-05"]),
    comment = ["", "moved in 2023", "", "", "asked to call back", ""],
)
write_dta("survey.dta", survey;
    label = "Household survey (example)",
    notes = ["Made up for the DtaParser documentation."],
    value_labels = Dict(
        "region" => Dict(1 => "North", 2 => "South", 3 => "East", 4 => "West"),
        "nonresponse" => Dict(".d" => "Don't know", ".r" => "Refused")),
    column_labels = Dict(:region => "Region", :age => "Age in years", :income => "Monthly income"),
    column_value_labels = Dict(:region => "region", :income => "nonresponse"))
```

## Read a file

```julia
using DtaParser, DataFrames

t = read_dta("survey.dta")
df = DataFrame(t)
```

```text
6×6 DataFrame
 Row │ id    region  age   income     interviewed  comment
     │ Int8  Int8    Int8  Float64?   Date         String
─────┼───────────────────────────────────────────────────────────────
   1 │    1       1    34     2100.0  2024-03-01
   2 │    2       2    51  missing    2024-03-01   moved in 2023
   3 │    3       2    29     1850.0  2024-03-02
   4 │    4       3    62  missing    2024-03-04
   5 │    5       4    45  missing    2024-03-04   asked to call back
   6 │    6       1    38     3200.0  2024-03-05
```

`read_dta(path)` returns a `DtaTable`: a Tables.jl table, so any sink
(`DataFrame`, `CSV.write`, `Tables.columntable`) accepts it. `t.income`
or `t[:income]` is a column. `DataFrame(t)` copies the columns, and the
metadata comes along when DataFrames is loaded.

| in the file | in Julia |
|---|---|
| byte, int, long, float, double, no missing value | `Vector{Int8}`, `Vector{Int16}`, `Vector{Int32}`, `Vector{Float32}`, `Vector{Float64}` |
| the same with any missing value | `DtaColumn{T}`, an `AbstractVector{Union{Missing,T}}` that keeps each value's missing code |
| `%td` dates, `%tc` times | `Date`, `DateTime` (see [Dates](#dates)) |
| strN, strL text | `Vector{String}` |
| strL with binary values | `Vector{UInt8}` elements |

Every value converts exactly. The numeric types are the file's storage
types, so `df.age` is `Int8` and arithmetic on it can overflow; widen
first with `Int.(df.age)`.

## Select columns

```julia
t = read_dta("survey.dta"; cols = [:income, :id])
names(t)        # ["income", "id"]
```

`cols` takes names (`Symbol` or `String`) or 1-based positions, in the
order you want them back; a single name works too. A name the file does
not have, a position out of range or a column named twice throws an
`ArgumentError`.

## Read some rows

```julia
part = read_dta("survey.dta"; skip = 2, n_max = 3)
part.id         # Int8[3, 4, 5]
```

`skip` rows are skipped, then at most `n_max` are read (all when
`nothing`). Rows past the end give fewer rows, or none; it is not an
error. To work through a large file in pieces, take the row count from
`read_meta`:

```julia
nrows = read_meta("survey.dta")["nrows"]
for start in 0:4:nrows-1
    chunk = read_dta("survey.dta"; skip = start, n_max = 4)
    println(start, " ", length(chunk.id))
end
```

The reader seeks to row `skip`, so the last rows of a large file cost no
more than the first.

## Metadata

The file's metadata is DataAPI metadata on the table, and on a
DataFrame made from it:

```julia
using DtaParser, DataFrames   # DataFrames exports metadata and colmetadata (from DataAPI)
t = read_dta("survey.dta")
metadata(t, "label")                      # "Household survey (example)"
metadata(t, "notes")                      # ["Made up for the DtaParser documentation."]
colmetadata(t, :income, "label")          # "Monthly income"
colmetadata(t, :income, "format")         # "%10.0g"
colmetadata(t, :income, "storage")        # "double"
colmetadata(t, :income, "value_labels")   # "nonresponse"
df = DataFrame(t)
colmetadata(df, :region, "label")         # "Region"
```

Table metadata (`metadata(t, key)`):

| key | holds |
|---|---|
| `"label"` | the data label (`""` if none) |
| `"notes"` | the dataset's notes, in order |
| `"value_labels"` | every value label set: name to `Dict` from Stata key to text |
| `"characteristics"` | `(variable, name, value)` named tuples, without the notes |
| `"sorted_by"` | the columns the data is sorted by, as `Symbol`s |
| `"timestamp"`, `"release"`, `"byte_order"`, `"encoding"` | about the file |

Column metadata (`colmetadata(t, col, key)`): `"label"`, `"format"`,
`"storage"` (`"byte"`, `"str12"`, `"strL"`, ...) and `"value_labels"`
(the name of the column's set, or `""`).

`read_meta(path)` gives the same without reading rows: a `Dict` with the
table metadata, `"nrows"`, and `"columns"`, one `Dict` per variable with
`"name"` and its column metadata.

```julia
meta = read_meta("survey.dta")
meta["nrows"], [c["name"] for c in meta["columns"]]
```

DataFrames keeps metadata with style `:note` through most operations
(`select`, `subset`, `sort`, joins keep column metadata); see the
DataFrames manual on metadata.

## Missing values

Stata has 27 numeric missing values: `.` and `.a` to `.z` (see the
[guide](guide/missing-values.md)). Julia has one `missing`. A column
with any missing value is a `DtaColumn{T}`: its elements read as
`missing` like any `Union{Missing,T}` vector, and it stores a missing
code per row next to the values: 0 for a number, 1 for `.`, 2 to 27 for
`.a` to `.z`.

```julia
df = DataFrame(read_dta("survey.dta"))
df.income[2]                                  # missing
stata_code(df.income, 2)                      # 0x05, that is .d
[stata_code(df.income, i) for i in 1:6]       # UInt8[0, 5, 0, 1, 19, 0]
set_stata_code!(df.income, 4, 20)             # make row 4 .s
count(ismissing, df.income)                   # 3
```

`stata_code(col, i)` reads a code (on any vector: `missing` is 1 there),
and `set_stata_code!(col, i, code)` sets one; code 0 makes the stored
value visible again.

**What keeps the codes.** Bulk operations on a `DtaColumn`: indexing by
ranges, vectors or masks, `view`, `copy`, `similar`, `sort`, `permute!`,
`vcat` and `append!` of `DtaColumn`s, assigning a `DtaColumn` into a
slice of another, and Tables.jl conversion. DataFrames goes through
those for row selection, `sort`, `subset`, `filter`, `copy`, and
`select`/`transform` on grouped frames, so they keep the codes too.

**What loses them.** Assigning one element (`b[i] = a[i]`) copies
`missing`, which becomes `.`; copy codes with `set_stata_code!`.
DataFrames' `combine` on groups and `vcat` of two DataFrames build plain
vectors: `.` stays, the letters become `.`. Broadcasting arithmetic
(`df.income .+ 1`) gives a plain vector too. `groupby` on a `DtaColumn`
puts all its missing values in one group; to keep `.d` apart from
`.r`, add a key column and group on it:
`df.income_key = stata_key(df.income); groupby(df, :income_key)`.

**Order.** `sort(col)` on a `DtaColumn` follows Stata: numbers, then
`.`, `.a`, ..., `.z`. DataFrames' `sort(df, :income)` keeps each code
with its row but sees every missing value as `missing`, so it puts them
last in their original order. To sort a DataFrame in Stata's order, sort
by the keys. `stata_key(x)` turns a value into a `Float64` that sorts
that way: `stata_key(2.5) == 2.5`, `stata_key(missing)` and
`stata_key(".")` are `.`, `stata_key(".a")` is `.a`; `stata_key(col)`
gives every row's key.

```julia
s = df[sortperm(stata_key(df.income)), :]
[stata_code(s.income, i) for i in 1:6]        # UInt8[0, 0, 0, 5, 19, 20]
[stata_code(sort(df.income), i) for i in 1:6] # the same order
stata_key(".a") > stata_key(missing) > 1e300  # true
```

For several columns, add key columns and sort on them:
`df.income_key = stata_key(df.income); sort(df, [:region, :income_key])`.

The keys are the same in R, Python and TypeScript.

## Value labels

A column's set is named in its `"value_labels"` column metadata; the
sets are in the table metadata, keyed by Stata key:

```julia
t = read_dta("survey.dta")
set = colmetadata(t, :region, "value_labels")       # "region"
labels = metadata(t, "value_labels")[set]           # Dict(1.0 => "North", ...)
labels[2]                                           # "South"
[get(labels, x, string(x)) for x in t.region]       # ["North", "South", "South", "East", "West", "North"]
metadata(t, "value_labels")["nonresponse"][stata_key(".d")]   # "Don't know"
```

Keys are `Float64`, and Julia's `Dict` finds `1.0` when given `1`, so
`labels[2]` works on an `Int8` value. A missing value's key is
`stata_key(".d")`, or `stata_key(col, i)` for row `i`.

As a categorical vector, with every label as a level in code order (needs
CategoricalArrays.jl):

```julia norun
using CategoricalArrays
levels_in_order = [labels[k] for k in sort(collect(keys(labels)))]
region = categorical([labels[x] for x in t.region]; levels = levels_in_order)
```

## Dates

Columns with a `%td` (day) format become `Date`, and `%tc`
(millisecond) columns `DateTime`; `.` becomes `missing`.

```julia
using Dates
t = read_dta("survey.dta")
eltype(t.interviewed)                                # Date
dayname(t.interviewed[1])                            # "Friday"
raw = read_dta("survey.dta"; dates = false)
raw.interviewed[1]                                   # 23436, days since 1960-01-01
Date(1960) + Day(raw.interviewed[1])                 # 2024-03-01
```

A column stays numeric, with its format, if any value is not a whole
day (or millisecond), is out of range, or is one of `.a` to `.z`;
converting it would lose information. `%tC` (milliseconds with leap
seconds) always stays numeric, as do `%tw`, `%tm`, `%tq`, `%th` and
`%ty`. A `%tm` value `m` is the month `Date(1960) + Month(m)`.

## Write a file

```julia
write_dta("out.dta", df)
```

`write_dta(path, table; ...)` writes any Tables.jl table as release 118
and returns `path`. A `DtaTable`, or a DataFrame made from one, writes
back with its values, missing codes, numeric storage types, labels, value
labels, formats, notes, characteristics and sort order. String columns are written as narrow as their values allow ([storage types](guide/storage-types.md)).

Columns map to storage types:

| Julia | Stata |
|---|---|
| `Bool` | byte |
| integers | the smallest of byte, int, long that holds every value; else double; an error beyond ±2^53 |
| `Float32`, `Float64` | float, double; `NaN` is `.` |
| `DtaColumn` | its storage type and codes |
| `missing` in a numeric column | `.` |
| `Date`, `DateTime` | long `%td`, double `%tc` (milliseconds) |
| `String` | strN up to 2045 bytes, else strL; `missing` becomes `""` |
| `Vector{UInt8}` | binary strL |

Anything else, or a column name Stata cannot hold (1 to 32 letters,
digits or `_`, not starting with a digit, not a reserved word), throws an
error naming the column. A column whose metadata names a storage type
keeps it when the values fit.

Labels come from the table's metadata if it has any, and from keyword
arguments, which take precedence:

| keyword | gives |
|---|---|
| `label` | the data label |
| `notes` | a vector of notes |
| `timestamp` | the time stamp text; default now |
| `value_labels` | `Dict` of set name to `Dict` of value (a number or a name such as `".d"`) to text |
| `column_labels` | `Dict` of column to variable label |
| `column_formats` | `Dict` of column to display format |
| `column_value_labels` | `Dict` of column to the name of its set |

```julia
smokers = (id = [1, 2, 3], smoker = DtaColumn(Int8[1, 0, 0], UInt8[0, 0, 5]))
write_dta("smokers.dta", smokers;
    label = "Smoking",
    value_labels = Dict("yesno" => Dict(0 => "No", 1 => "Yes", ".d" => "Don't know")),
    column_labels = Dict(:smoker => "Smokes daily"),
    column_value_labels = Dict(:smoker => "yesno"))

back = read_dta("smokers.dta")
metadata(back, "label")                       # "Smoking"
colmetadata(back, :smoker, "label")           # "Smokes daily"
metadata(back, "value_labels")["yesno"][stata_key(".d")]   # "Don't know"
```

## Recipes

**Keep `.a` to `.z` through a filter, a sort and a write.**

```julia
df = DataFrame(read_dta("survey.dta"))
older = subset(df, :age => ByRow(>=(40)))
older = older[sortperm(stata_key(older.income)), :]
write_dta("older.dta", older)
back = read_dta("older.dta")
[stata_code(back.income, i) for i in 1:3]     # UInt8[1, 5, 19]: ., .d, .r
```

**Count each missing value, as Stata's `tab, missing` does.**

```julia
col = read_dta("survey.dta").income
counts = Dict{String,Int}()
for i in eachindex(col)
    c = stata_code(col, i)
    k = c == 0 ? string(col[i]) : c == 1 ? "." : string('.', Char('a' + c - 2))
    counts[k] = get(counts, k, 0) + 1
end
counts                                        # Dict(".d" => 1, ".r" => 1, "." => 1, ...)
```

**Copy codes element by element.** `b[i] = a[i]` loses the letter;
copy the code too:

```julia
a = read_dta("survey.dta").income
b = similar(a)
for i in eachindex(a)
    b[i] = a[i]
    set_stata_code!(b, i, stata_code(a, i))
end
[stata_code(b, i) for i in eachindex(b)] == [stata_code(a, i) for i in eachindex(a)]   # true
```

**Read a file from an old Stata in another encoding.** Files before
release 118 do not record their encoding. The default is Windows-1252;
pass `encoding = "latin1"` or `encoding = "utf-8"` if text looks wrong
(see the [guide](guide/encodings.md)).

## Coming from ReadStatTables.jl

| ReadStatTables | DtaParser |
|---|---|
| `readstat(path)` | `read_dta(path)` |
| `usecols = [:a, :b]` | `cols = [:a, :b]` |
| `row_offset = 100, row_limit = 50` | `skip = 100, n_max = 50` |
| `file_encoding = "latin1"` | `encoding = "latin1"` (`"windows-1252"`, `"latin1"`, `"utf-8"`) |
| `apply_value_labels = true`: a `LabeledArray` column | plain numbers; the labels are in metadata; see [Value labels](#value-labels) |
| tagged missing values read as `missing` | kept as codes in a `DtaColumn` |
| `colmetadata(tb, :x, "label")`, `"format"` | `colmetadata(t, :x, "label")`, `"format"` |
| the file label in table metadata | `metadata(t, "label")` |
| `writestat(path, table)` | `write_dta(path, table)`; always release 118 |
| `DataFrame(readstat(path))` | `DataFrame(read_dta(path))` |

What changes: numeric columns keep their storage type (`Int8` rather
than a wider type), dates are `Date`/`DateTime`, labelled columns stay
numbers, and old files decode as Windows-1252 unless you say otherwise.

## Troubleshooting

**`Pkg.build` fails, or "could not load library".** Building needs
`cargo`; install Rust from [rustup.rs](https://rustup.rs), then run
`Pkg.build("DtaParser")` again. On Windows the library is `dta_ffi.dll`;
on Linux, `libdta_ffi.so`.

**"unsupported .dta release".** The file is not a `.dta` file, or its
release is older than 104 or newer than 119. See
[Releases](guide/releases.md).

**Accented letters are wrong.** The file is older than release 118;
pass `encoding = "latin1"` or `encoding = "utf-8"`.

**`.a` became `.` after a DataFrames operation.** `combine` and `vcat`
of DataFrames build plain vectors; see [Missing values](#missing-values)
for what keeps the codes.

**`DataFrame(t)` has no column metadata.** Load DataFrames before
calling it (`using DataFrames`); the extension that copies metadata
loads with it.

**`InexactError` in arithmetic on a column.** The column is `Int8` or
`Int16`, the file's storage type. Widen it: `Int.(col)` or
`Float64.(col)`.

## API reference

Every export has a docstring (`?read_dta` at the REPL):

- `read_dta(path; cols, skip, n_max, encoding, dates)`: read a file into
  a `DtaTable`.
- `read_meta(path; encoding)`: metadata, `"nrows"` and `"columns"`,
  without rows.
- `write_dta(path, table; label, notes, timestamp, value_labels,
  column_labels, column_formats, column_value_labels)`: write release 118.
- `DtaTable`: what `read_dta` returns; Tables.jl and DataAPI metadata.
- `DtaColumn{T}(values, codes)`, `DtaColumn(x)`: numbers with missing
  codes.
- `stata_code(col, i)`, `set_stata_code!(col, i, code)`: read and set a
  missing code.
- `stata_key(x)`, `stata_key(col)`, `stata_key(col, i)`: `Float64`s that
  sort as Stata does.
