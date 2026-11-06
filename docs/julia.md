# Julia: DtaParser.jl and Datakit

Two packages:

- **DtaParser** reads Stata `.dta` files into a Tables.jl table, which
  you can turn into a DataFrame, and writes any Tables.jl table as a
  `.dta` file. It reads every release from 104 to 119 and writes release
  118. Numeric columns keep Stata's missing values `.a` to `.z` through
  slicing, sorting, filtering and writing, and labels travel as DataAPI
  metadata.
- **Datakit** is for data preparation: it reads
  [fixed-width `.dat` files](#fixed-width-files-with-a-sas-setup-file)
  through their SAS setup files, and [Parquet files](#parquet-files),
  into a DataFrame, and saves any table as Parquet, keeping the same
  labels and missing values. Its Parquet files go between Julia, R,
  Python, and TypeScript with them
  ([Datakit](#datakit-parquet-and-fixed-width-text-into-dataframes)).

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
[Datakit](#datakit-parquet-and-fixed-width-text-into-dataframes) ·
[Labels and .a to .z through DataFrames operations](#labels-and-a-to-z-through-dataframes-operations) ·
[Fixed-width files](#fixed-width-files-with-a-sas-setup-file) ·
[Parquet files](#parquet-files) ·
[Troubleshooting](#troubleshooting) ·
[API reference](#api-reference)

The [guide](guide/README.md) explains the Stata concepts behind each
section.

## Install

DtaParser and Datakit need Julia 1.10 or later, on Linux, macOS or
Windows. Neither is in the General registry yet. DtaParser builds its
native library from a checkout of the repository with Rust's `cargo`
([rustup.rs](https://rustup.rs)), and Datakit uses that library:

```sh
git clone https://github.com/jbearak/dta-parser
```

```julia norun
import Pkg
Pkg.develop(path="dta-parser/julia/DtaParser")
Pkg.develop(path="dta-parser/julia/Datakit")   # optional: Parquet and fixed-width text
Pkg.build("DtaParser")      # runs cargo; takes a minute the first time
Pkg.add("DataFrames")       # for DataFrame(t), and `using DataFrames` beside Datakit
```

Run this from the directory you cloned into (the paths are relative to
it), in the environment you want the packages in: your project's, after
`Pkg.activate("path/to/project")`, or the default one. Develop
DtaParser before Datakit: Datakit needs DtaParser 0.3, which is not
registered, so Julia must already know where it is. (On Julia 1.11 and
later, Datakit's `Project.toml` also names DtaParser's path, under
`[sources]`.)

DtaParser depends on Tables.jl and DataAPI.jl. DataFrames (1.4 or
later) is optional: when it is loaded, `DataFrame(t)` carries the
labels across as metadata. CategoricalArrays.jl is needed only for the
categorical recipe under [Value labels](#value-labels). Datakit depends
on DtaParser, DataFrames, DataAPI and Tables.jl; TimeZones.jl and
CategoricalArrays.jl are optional ([Parquet: install](#parquet-install)).

If `Pkg.build` fails, see [Troubleshooting](#troubleshooting). Datakit
checks, when it loads, that DtaParser's library has the interface it
was written for; if not, it stops with a message naming both versions:
develop both packages from the same checkout and build again.

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
DataFrames manual on metadata, and
[Labels and .a to .z through DataFrames operations](#labels-and-a-to-z-through-dataframes-operations).

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

The letter `c` has code `c - 'a' + 2` (`.a` is 2, `.d` is 5, `.z` is
27), and code `k` is the letter `'a' + k - 2`.

`stata_code(col, i)` reads a code (on any vector: `missing` is 1 there),
and `set_stata_code!(col, i, code)` sets one; code 0 makes the stored
value visible again.

**What keeps the codes.** Bulk operations on a `DtaColumn`: indexing by
ranges, vectors or masks, `view`, `copy`, `similar`, `sort`, `permute!`,
`vcat` and `append!` of `DtaColumn`s, assigning a `DtaColumn` into a
slice of another, and Tables.jl conversion. DataFrames goes through
those for row selection, `filter`, `subset`, `sort` and `sort!`, `copy`,
joins, and `select` or `transform` that pass the column through.

**What loses them.** Assigning one element (`b[i] = a[i]`) copies
`missing`, which becomes `.`; copy codes with `set_stata_code!`.
Anything that builds a new vector from the elements: broadcasting
(`df.income .+ 1`), a function in `transform`, `ByRow`, DataFrames'
`combine` on groups and `vcat` of two DataFrames. `.` stays; the
letters become `.`. The full list, as the tests observe it, is under
[Labels and .a to .z through DataFrames operations](#labels-and-a-to-z-through-dataframes-operations).
`groupby` on a `DtaColumn` puts all its missing values in one group; to
keep `.d` apart from `.r`, add a key column and group on it:
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
text(x) = ismissing(x) ? missing : get(labels, x, string(x))
region = categorical(text.(t.region); levels = union(levels_in_order, skipmissing(text.(t.region))))
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
eltype(raw.interviewed)                              # Int32: the column's storage type (long)
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

## Datakit: Parquet and fixed-width text into DataFrames

Datakit is a second package, for data preparation. It reads Parquet files and
fixed-width text into a `DataFrame` and saves any table as Parquet,
keeping what a `.dta` file says: value labels, variable labels, display
formats, notes and `.a` to `.z`. It is the Julia counterpart of R's
datakit, and its files go between the two: what one writes, the other
reads with the same labels and letters.

| function | does |
|---|---|
| `read_parquet(source; ...)` | reads a Parquet file into a `DataFrame` |
| `read_parquet_info(source)` | reads a Parquet file's schema and metadata, not its rows |
| `save_parquet(path_or_io, table; ...)` | writes any Tables.jl table as Parquet |
| `read_fixed_width(path, setup; ...)` | reads fixed-width text through its SAS setup file into a `DataFrame` |

It also re-exports `DtaColumn`, `stata_code`, `set_stata_code!` and
`stata_key` from DtaParser, so `using Datakit, DataFrames` is all a
script needs. `.dta` files stay DtaParser's: `DataFrame(read_dta(f))`
gives a frame with the same metadata keys as `read_parquet(g)`.

What a DataFrame from Datakit holds:

- A numeric column whose rows read hold any of `.a` to `.z` is a
  `DtaColumn`, which keeps each row's code (see
  [Missing values](#missing-values)). Every other column is a plain
  `Vector{T}`, or `Vector{Union{Missing,T}}` when a row is missing.
  `ismissing`, `skipmissing`, `dropmissing` and `mean` treat `.a` to
  `.z` as missing, as Stata does.
- Labels are DataFrames metadata with style `:note`, under the keys
  `DataFrame(read_dta(f))` uses: `colmetadata(df, :x, "label")`,
  `"format"`, `"value_labels"` (the name of the column's set) and
  `"storage"`; `metadata(df, "label")`, `"notes"`, `"timestamp"`,
  `"characteristics"`, `"sorted_by"` and `"value_labels"` (every set).
  Style `:note` makes them follow their columns through DataFrames'
  operations, as [the next section](#labels-and-a-to-z-through-dataframes-operations)
  shows.

A function over a column builds a new vector, and nothing warns that
the letters are gone from it:

```julia datakit
using Datakit, DataFrames

save_parquet("survey.parquet", DataFrame(read_dta("survey.dta")))
df = read_parquet("survey.parquet")
[stata_code(df.income, i) for i in 1:6]            # UInt8[0, 5, 0, 1, 19, 0]: ., .d, .r
yearly = df.income .* 12
[stata_code(yearly, i) for i in 1:6]               # UInt8[0, 1, 0, 1, 1, 0]: .d and .r became .
```

### Labels and .a to .z through DataFrames operations

Metadata follows DataFrames' own rule for style `:note`. The codes live
in the `DtaColumn`. When DataFrames moves that column or indexes it,
they come along. When DataFrames or your function builds a new vector
from its elements, they are gone: each element is `missing`, and a new
vector stores it as `.`.

The lists below are what `julia/Datakit/test/operations.jl` observes on
DataFrames 1.8.2 and on 1.4.0, the oldest version Datakit allows. They
describe DataFrames' behaviour, which Datakit does not control.

**Keep the codes and the labels:**

- indexing rows (`df[rows, :]`, `view`), `filter`, `filter!`, `subset`,
  `subset!`, `sort`, `sort!`, `copy`;
- `select`, `transform` and `transform!` that pass the column through,
  by name or through `identity` or `copy`, under its own name or a new
  one: `:x`, `:x => :y`, `:x => identity => :x`, `:x => copy => :y`;
- the same after `groupby` with `:x` or `identity` (not `copy`, below);
- joins: `innerjoin`, `leftjoin`, `rightjoin` and `outerjoin` kept every
  row's code on both sides, with `.` for rows without a match. The
  column's label is kept; the table's metadata follows DataFrames' join
  rule (`leftjoin` keeps the left frame's; the others keep only what
  both frames share).

**Lose the codes** (`.a` to `.z` become `missing`, which saves as `.`):

- any function that builds a new vector, under any name: broadcasting
  (`df.x .+ 1`), arithmetic, `ByRow`, `transform(df, :x => f => :x)`;
- `copy` after `groupby` (`transform(groupby(df, :g), :x => copy => :y)`,
  and grouped `select` and `transform!`): DataFrames builds the result
  group by group;
- `combine` of groups, and `vcat` of DataFrames.

**Labels.** A column passed through keeps its label, renamed or not, as
does a function's result under the column's own name
(`:x => f => :x`). A function's result under a new name
(`:x => f => :y`, `df.y = df.x .+ 0`) starts without one; set it with
`colmetadata!(df, :y, "label", "..."; style = :note)`.

```julia datakit
df = read_parquet("survey.parquet")
older = sort(subset(df, :age => ByRow(>=(40))), :id; rev = true)
[stata_code(older.income, i) for i in 1:3]          # UInt8[19, 1, 5]: .r, ., .d
colmetadata(older, :income, "label")                # "Monthly income"
kept = select(groupby(df, :region), :income => identity => :income)
[stata_code(kept.income, i) for i in 1:6]           # UInt8[0, 5, 0, 1, 19, 0]
lost = combine(groupby(df, :region), :income)
count(i -> stata_code(lost.income, i) > 1, 1:6)     # 0: no letters left
```

To keep why a value is missing through an aggregation, aggregate a key
column made with `stata_key` (see [Missing values](#missing-values)),
or count the codes before combining.

**Set a letter** (`replace x = .d if age < 15` in a do-file).
`set_stata_code!` needs a `DtaColumn`. A column read without letters
is a plain vector, so convert it first; assigning with `df[!, :x] = ...`
replaces the column in place and keeps its metadata:

```julia datakit
df = read_parquet("survey.parquet")
df.age isa DtaColumn || (df[!, :age] = DtaColumn(df.age))
for i in findall(coalesce.(df.age .> 60, false))
    set_stata_code!(df.age, i, 19)   # codes: 1 is ., 2 to 27 are .a to .z; 19 is .r
end
[stata_code(df.age, i) for i in 1:6]                # UInt8[0, 0, 0, 19, 0, 0]
colmetadata(df, :age, "label")                      # "Age in years"
save_parquet("survey2.parquet", df)
[stata_code(read_parquet("survey2.parquet").age, i) for i in 1:6]   # UInt8[0, 0, 0, 19, 0, 0]
```

To replace a letter with a value, assign the value
(`df.age[4] = 62`), which sets the row's code to 0.

## Fixed-width files with a SAS setup file

Some surveys are published as fixed-width text with a SAS program, the
*setup file*, that says where each variable sits. CDC publishes the
National Survey of Family Growth this way, from 1973 to 2017-2019.
Datakit's `read_fixed_width` reads such data through its setup file
into a `DataFrame`: columns from `INPUT`, variable labels from `LABEL`,
value labels from `PROC FORMAT` and `FORMAT`, record types from
`IF rec_type < 5 THEN DELETE; ELSE INPUT ...`, and the setup's
*missing-value recodes*, such as `IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;`.

```julia datakit
using Datakit, DataFrames

write("survey.sas", """
PROC FORMAT;
  VALUE kidsf 0='(0) None' 98='(98) DK' 99='(99) Not ascertained';
DATA;
INPUT ID 1-3 KIDS 4-5;
LABEL KIDS = 'Number of children';
IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;
FORMAT KIDS kidsf.;
""")
write("survey.dat", "001 2\n00298\n00399\n004 0\n")
```

By default the recodes apply as the setup writes them, so 98 and 99 are
`missing` with code 1 (`.`):

```julia datakit
fw = read_fixed_width("survey.dat", "survey.sas")
fw.KIDS                                    # Union{Missing, Int8}[2, missing, missing, 0]
colmetadata(fw, :KIDS, "label")            # "Number of children"
```

The result is a `DataFrame` with `read_parquet`'s metadata keys, so
`save_parquet(path, fw)` keeps the labels. Columns are as
`DataFrame(read_dta(f))` gives them.

`recodes=:tagged` keeps why each value is missing: per variable, the
codes recoded to `.` become `.a`, `.b`, ... (codes 2, 3, ...) in the
order the setup names them, and each code's value label moves to its
letter:

```julia datakit
fw = read_fixed_width("survey.dat", "survey.sas"; recodes=:tagged)
[stata_code(fw.KIDS, i) for i in 1:4]      # UInt8[0, 2, 3, 0]
metadata(fw, "value_labels")["kidsf"][stata_key(".a")]   # "(98) DK"
```

A letter means what that variable's labels say: `.a` is 98 "DK" here,
but in a variable whose setup recodes 97 "Refused" first, `.a` is
"Refused". `recodes=:none` ignores the recodes, keeping the codes as
numbers.

Numeric columns take the smallest storage type that holds their values,
and records shorter than the setup's columns read as blank (`missing`).
Statements the reader does not run, such as other data-step code or a
range in `VALUE`, are skipped with one warning; table metadata
`"warnings"` lists them all. A `LENGTH` statement for numbers, which
sets only how SAS stores them, is skipped without one. A variable label
with stray quotes inside it, such as
`X = "WHETHER " SAME AS LAST MONTH" WAS ANSWERED"` in CDC's 2011-2013
to 2015-2017 setups, is read from its first quote to its last, without
a warning. `cols`, `skip` and `n_max` work as in `read_dta`, after the
whole file is read.

CDC's setups from 2002 on differ in two ways, and `read_fixed_width`
reads both. The 2002 setups come in three files (`2002FemPregInput.sas`,
`2002FemPregVarLabel.sas`, `2002FemPregValueLabel.sas`); give `setup` a
vector of the paths in that order, and they are read as one setup. A
statement may not run from one file into the next, and errors and
warnings name a file by its place (`"file 2 line 8"`):

```julia datakit
write("input.sas", "DATA;\nINPUT ID 1-3 KIDS 4-5;\nRUN;\n")
write("labels.sas", "PROC FORMAT;\n  VALUE kidsf 0='(0) None' 98='(98) DK';\nRUN;\nFORMAT KIDS kidsf.;\n")
fw = read_fixed_width("survey.dat", ["input.sas", "labels.sas"]; recodes=:none)
metadata(fw, "value_labels")["kidsf"]   # Dict(0.0 => "(0) None", 98.0 => "(98) DK")
```

From 2006-2010 on, CDC puts the `PROC FORMAT` step and the `FORMAT`
statement each in a block comment (`/* ... */`), so that SAS users
without CDC's format catalog can run the file as published. The value
labels are still there, so by default a comment that holds nothing but
a `PROC FORMAT` step or a `FORMAT` statement is read as code; a comment
that only mentions them stays a comment. `commented_formats=false`
reads every comment as a comment, and those files then have no value
labels:

```julia datakit
write("commented.sas", """
/*
PROC FORMAT;
  VALUE kidsf 0='(0) None' 98='(98) DK';
*/
DATA;
INPUT ID 1-3 KIDS 4-5;
/*
FORMAT KIDS kidsf.;
*/
""")
fw = read_fixed_width("survey.dat", "commented.sas"; recodes=:none)
colmetadata(fw, :KIDS, "value_labels")   # "kidsf"
fw = read_fixed_width("survey.dat", "commented.sas"; recodes=:none, commented_formats=false)
colmetadata(fw, :KIDS, "value_labels")   # ""
```

## Parquet files

Datakit's `read_parquet` and `save_parquet` read and write Parquet
files that keep what a `.dta` file says: value labels, variable labels,
display formats, `.a` to `.z`, the data label, notes and time stamp,
and also categorical levels and time zones. `read_parquet` returns a
`DataFrame` with the metadata keys of `DataFrame(read_dta(f))`, and a
frame `read_dta` gave comes back `isequal`, with the same codes and
labels, after `save_parquet`. The files are plain Parquet that
Parquet2.jl, DuckDB, pyarrow, polars, arrow and nanoparquet read;
[docs/parquet.md](parquet.md) says what each of them sees, and gives
the file's specification. Only flat tables are read and written: for
lists, maps or structs, use DuckDB.jl.

Use Parquet2.jl or DuckDB.jl instead for files that carry no labels and
no `.a` to `.z` when you want what they add: DuckDB's SQL over many
files and partitions, filters pushed into the read, or nested columns.

Contents:
[Install](#parquet-install) ·
[Read a Parquet file](#read-a-parquet-file) ·
[Read some columns](#read-some-columns-of-a-parquet-file) ·
[Read a range of rows](#read-a-range-of-rows-of-a-parquet-file) ·
[Schema and metadata](#a-parquet-files-schema-and-metadata) ·
[Labels](#labels-in-parquet-files) ·
[Dates and time zones](#dates-and-time-zones-in-parquet-files) ·
[Write a Parquet file](#write-a-parquet-file) ·
[Write labels](#write-labels-to-a-parquet-file) ·
[Keep .a to .z](#keep-a-to-z-in-a-parquet-file) ·
[Files from other tools](#parquet-files-from-other-tools) ·
[What each type becomes](#what-each-parquet-type-becomes-in-julia) ·
[Coming from Parquet2.jl](#coming-from-parquet2jl)

### Parquet: install

Parquet is in Datakit, which [Install](#install) covers: it reads and
writes through DtaParser's Rust library, with no Arrow or other Parquet
package. Datakit depends on DataFrames (1.4 or later), so
`using Datakit` loads it. Two packages are optional, and Datakit uses
them when they are loaded (as package extensions):

- [TimeZones.jl](https://github.com/JuliaTime/TimeZones.jl), to read a
  timestamp with a zone as `ZonedDateTime` and to write `ZonedDateTime`
  columns. Without it, such a timestamp reads as a `DateTime` in UTC,
  with one warning naming the columns.
- [CategoricalArrays.jl](https://github.com/JuliaData/CategoricalArrays.jl),
  to read categorical columns as `CategoricalArray` and to write them.
  Without it, they read as `String`, with one warning.

```julia norun
import Pkg
Pkg.add(["TimeZones", "CategoricalArrays"])   # optional
```

### Read a Parquet file

This writes the example file as Parquet and reads it back:

```julia datakit
using Datakit, DataFrames, Dates

t = DataFrame(read_dta("survey.dta"))
save_parquet("survey.parquet", t)
p = read_parquet("survey.parquet")
isequal(p.income, t.income)                    # true
[stata_code(p.income, i) for i in 1:6]         # UInt8[0, 5, 0, 1, 19, 0]: ., .d, .r kept
typeof(p.income), typeof(p.interviewed)        # (DtaColumn{Float64}, Vector{Date})
colmetadata(p, :income, "label")               # "Monthly income"
```

```text
6×6 DataFrame
 Row │ id    region  age   income     interviewed  comment
     │ Int8  Int8    Int8  Float64?   Date         String
─────┼────────────────────────────────────────────────────────────────
   1 │    1       1    34     2100.0  2024-03-01
   2 │    2       2    51  missing    2024-03-01   moved in 2023
   3 │    3       2    29     1850.0  2024-03-02
   4 │    4       3    62  missing    2024-03-04
   5 │    5       4    45  missing    2024-03-04   asked to call back
   6 │    6       1    38     3200.0  2024-03-05
```

`read_parquet(source)` returns a `DataFrame`. `source` is a path, an
`IO` (read to its end) or a `Vector{UInt8}` holding a whole file.
Numbers keep their own type (`Int8`, `Int16`, `Int32`, `Int64`,
`Float32`, `Float64`, unsigned integers, `Bool`). A numeric column
whose rows read hold any of `.a` to `.z` is a `DtaColumn` that keeps
them apart from `.` (see [Missing values](#missing-values)); any other
column with missing values is a `Vector{Union{Missing,T}}`. A `NaN`
stays `NaN`, a value. Dates are `Date`, timestamps `DateTime`, text
`String` and bytes `Vector{UInt8}`.
[What each type becomes](#what-each-parquet-type-becomes-in-julia)
gives the type of every Parquet column. What the frame keeps through
`filter`, `sort`, joins and the rest is in
[Labels and .a to .z through DataFrames operations](#labels-and-a-to-z-through-dataframes-operations).

### Read some columns of a Parquet file

`cols` takes names (`Symbol` or `String`) or positions, and returns the
columns in the order given; only those columns are read from the file:

```julia datakit
names(read_parquet("survey.parquet"; cols = [:income, :id]))   # ["income", "id"]
names(read_parquet("survey.parquet"; cols = [1, 4]))           # ["id", "income"]
```

A name the file does not have is an `ArgumentError` that lists the
file's columns: `column "weight" is not in the file; its columns are
"id", "region", "age", "income", "interviewed", "comment"`. A position
out of range, or a column given twice, is an `ArgumentError` too.

### Read a range of rows of a Parquet file

`skip` rows are skipped, then at most `n_max` are read, as in
`read_dta`. Only the row groups that hold the rows are read, and within
them only the pages that do, so a window of a large file is quick:

```julia datakit
read_parquet("survey.parquet"; skip = 2, n_max = 2).id   # Int8[3, 4]
nrow(read_parquet("survey.parquet"; skip = 10))          # 0: past the end is no error
w = read_parquet("survey.parquet"; skip = 4, n_max = 2)
w.income                                                 # DtaColumn: row 5 is .r
read_parquet("survey.parquet"; skip = 5).income          # Vector{Float64}: no missing value in the row read
```

A column's type depends on the rows read: the same column can be a
`DtaColumn` in one window and a plain vector in another. Code that
sets letters should convert first (see the recipe under
[Labels and .a to .z](#labels-and-a-to-z-through-dataframes-operations)).
To work through a file in pieces, take the row count and the row groups
from `read_parquet_info` (below) and read one window at a time.

### A Parquet file's schema and metadata

`read_parquet_info(source)` reads the footer only:

```julia datakit
m = read_parquet_info("survey.parquet")
m["nrows"]                               # 6
m["compression"]                         # ["snappy"]
m["row_groups"]                          # [(rows = 6, compressed_bytes = 329, uncompressed_bytes = 329)]
m["created_by"]                          # "dta-parquet version 0.1.0"
m["label"]                               # "Household survey (example)"
[kv.key for kv in m["key_value"]]        # ["dta", "ARROW:schema"]
m["columns"][:, [:name, :eltype, :physical_type, :logical_type, :label]]
```

```text
6×5 DataFrame
 Row │ name         eltype                   physical_type  logical_type    label
     │ String       Any                      String         String          String
─────┼──────────────────────────────────────────────────────────────────────────────────
   1 │ id           Int8                     INT32          INT(8, signed)
   2 │ region       Int8                     INT32          INT(8, signed)  Region
   3 │ age          Int8                     INT32          INT(8, signed)  Age in years
   4 │ income       Union{Missing, Float64}  DOUBLE                         Monthly income
   5 │ interviewed  Date                     INT32          DATE
   6 │ comment      String                   BYTE_ARRAY     STRING
```

It returns a `Dict` with the table metadata `read_parquet` gives
(`"label"`, `"notes"`, `"timestamp"`, `"characteristics"`,
`"sorted_by"`, `"value_labels"`) and `"nrows"`, `"row_groups"`,
`"compression"` (the codecs used), `"created_by"`, `"key_value"`
(every key-value entry of the footer as a `(key, value)` named tuple,
the value as text: the dta profile, pyarrow's `ARROW:schema`, pandas'
metadata, anything another writer put there) and `"warnings"` (anything
wrong with the file's dta profile). `"columns"` is a `DataFrame` with a
row per column: `name`, `role` (`"data"`, or `"nested"` for a list,
map or struct, which is not read), `physical_type`, `logical_type`,
`eltype` (the element type `read_parquet` gives, with `Missing` when
the file's statistics show nulls; `nothing` for a column it does not
read), `label`, `format`, `value_labels` and `storage` (a text column's
is `""` until it is read).

### Labels in Parquet files

Labels are DataFrames metadata, with the same keys as for `.dta` files
(see [Metadata](#metadata) and [Value labels](#value-labels)):

```julia datakit
colmetadata(p, :age, "label")                     # "Age in years"
colmetadata(p, :region, "value_labels")           # "region"
labels = metadata(p, "value_labels")["region"]    # Dict(1.0 => "North", 2.0 => "South", ...)
[labels[x] for x in p.region]                     # ["North", "South", "South", "East", "West", "North"]
metadata(p, "value_labels")["nonresponse"][stata_key(p.income, 2)]   # "Don't know"
metadata(p, "label"), metadata(p, "notes")        # ("Household survey (example)", ["Made up for the DtaParser documentation."])
```

To make a labelled column a categorical one, with every label as a
level in code order (with CategoricalArrays.jl loaded):

```julia datakit
using CategoricalArrays
region = categorical([labels[x] for x in p.region]; levels = [labels[k] for k in sort(collect(keys(labels)))])
save_parquet("regions.parquet", DataFrame(region = region))
String.(levels(read_parquet("regions.parquet").region))   # ["North", "South", "East", "West"]
```

A `CategoricalArray` is written with every level, in order, and whether
it is ordered, and reads back the same. Other tools see the codes and
no labels; a file another tool wrote has no labels, unless it carries
the `dta` entry (see [docs/parquet.md](parquet.md#the-profile)).

### Dates and time zones in Parquet files

A `Date` is written as a Parquet DATE and a `DateTime` as a TIMESTAMP
in milliseconds, a clock time without zone; they read back as `Date`
and `DateTime`:

```julia datakit
visits = DataFrame(day = [Date(2024, 3, 1), Date(2024, 3, 4)],
                   at = [DateTime(2024, 3, 1, 9, 30), DateTime(2024, 3, 4, 17, 5, 0, 250)])
save_parquet("visits.parquet", visits)
v = read_parquet("visits.parquet")
v.at                     # [DateTime("2024-03-01T09:30:00"), DateTime("2024-03-04T17:05:00.250")]
read_parquet_info("visits.parquet")["columns"].logical_type   # ["DATE", "TIMESTAMP(MILLIS, local)"]
```

A `ZonedDateTime` (with TimeZones.jl loaded) is written as an instant,
a TIMESTAMP adjusted to UTC, with its zone; it reads back in that zone.
pyarrow, polars and arrow read the zone too:

```julia datakit
using TimeZones
zoned = DataFrame(at = ZonedDateTime.([DateTime(2024, 3, 1, 9, 30), DateTime(2024, 7, 1, 9, 30)], tz"America/New_York"))
save_parquet("zoned.parquet", zoned)
read_parquet("zoned.parquet").at   # [ZonedDateTime(2024, 3, 1, 9, 30, tz"America/New_York"), ZonedDateTime(2024, 7, 1, 9, 30, tz"America/New_York")]
```

All values of a `ZonedDateTime` column must be in one zone; convert
them with `astimezone` first if not.

Reading a timestamp: the zone is the one `save_parquet` recorded, else
the one in the file's Arrow schema (what pyarrow, polars and arrow
write), and the result is a `ZonedDateTime` in it when TimeZones.jl is
loaded. Without TimeZones.jl, or when the file names no zone, it is a
`DateTime`: in UTC for an instant (adjusted to UTC), as written for a
clock time. A `DateTime` holds milliseconds, so a timestamp in
microseconds or nanoseconds that is not a whole number of milliseconds
is an error naming the column and the row and giving the call that reads
it, with `timestamps = :truncate`, which drops what is below a
millisecond (see the next sections). INT96 timestamps (older Spark and
Impala files) read the same way. A TIME (a time of day) reads as
`Dates.Time`, to the nanosecond.

**A date or timestamp column holding `.a` to `.z`.** A `Vector{Date}`
cannot hold the letters, so such a column is numbers, as `read_dta`
reads a `%td` column with letters: a `DtaColumn{Float64}` of Stata's
numbers, days since 1960 with a `%td` format for a date, milliseconds
since 1960 with `%tc` for a timestamp. That happens when the rows read
hold a letter; a window without one reads as `Date` or `DateTime`. In
the file such a column is DOUBLE, days or seconds since 1970 with
`"logical"` in its profile, which is how R's datakit writes a `Date` or
`POSIXct` with tagged NAs. `save_parquet` writes the `DtaColumn` back
as numbers with its `%td` or `%tc` format, as `write_dta` would. To get
a date, `Date(1960) + Day(x)` for a value `x`.

```julia datakit
dates = DataFrame(seen = DtaColumn([23436.0, 0.0, 23437.0], UInt8[0, 5, 0]))   # 2024-03-01, .d, 2024-03-02
save_parquet("dates.parquet", dates; column_formats = Dict(:seen => "%td"))
d = read_parquet("dates.parquet")
d.seen, colmetadata(d, :seen, "format")         # (DtaColumn: 23436.0, missing, 23437.0; "%td")
Date(1960) + Day(d.seen[1])                     # 2024-03-01
```

### Write a Parquet file

`save_parquet(path_or_io, table)` writes any Tables.jl table (a
`DataFrame`, a `DtaTable`, a named tuple of vectors) and returns
`path_or_io`. Compression is snappy by default, which pyarrow, polars
and DuckDB read fastest; `compression` takes `:snappy`, `:zstd`,
`:gzip`, `:lz4_raw` or `:none`, and `compression_level` the codec's
level (zstd 1 to 22, gzip 0 to 9). zstd makes survey files about a sixth
smaller and slower to read. Row groups hold up to 262,144 rows and about
1 GiB of values; `row_group_size` sets the rows:

```julia datakit
save_parquet("small.parquet", p; compression = :zstd, compression_level = 9, row_group_size = 2)
[g.rows for g in read_parquet_info("small.parquet")["row_groups"]]   # [2, 2, 2]
```

Columns map to Parquet types:

| Julia | Parquet |
|---|---|
| `Int8`, `Int16` | INT32 annotated INT(8), INT(16) |
| `Int32`, `Int64` | INT32, INT64 |
| `UInt8`, `UInt16`, `UInt32`, `UInt64` | the next wider signed type (INT(16), INT32, INT64); a `UInt64` above `typemax(Int64)` is an error |
| `Float32`, `Float64` | FLOAT, DOUBLE; `NaN` is a value |
| `Bool` | BOOLEAN |
| `DtaColumn` | its type, `.` as null; with any `.a` to `.z`, DOUBLE with tagged NaNs (see [Keep .a to .z](#keep-a-to-z-in-a-parquet-file)) |
| `missing` in any column | null |
| `Date` | DATE |
| `DateTime` | TIMESTAMP(MILLIS), not adjusted to UTC |
| `ZonedDateTime` (TimeZones.jl) | TIMESTAMP(MILLIS), adjusted to UTC, with its zone |
| `String` | BYTE_ARRAY STRING |
| `Vector{UInt8}` | BYTE_ARRAY |
| a column mixing `String` and `Vector{UInt8}` (a strL with binary values) | BYTE_ARRAY; every value reads back as bytes |
| `CategoricalArray` of strings (CategoricalArrays.jl) | BYTE_ARRAY STRING, dictionary-encoded, every level in order |

Any other type (`Dates.Time`, complex numbers, a categorical of
numbers, nested vectors) is an error naming the column. Unlike
`write_dta`, `save_parquet` takes any column name. Files are written
beside the target and renamed into place, so a failed write leaves an
existing file alone. [docs/parquet.md](parquet.md#defaults-and-the-measurements-behind-them)
gives the measurements behind the defaults.

### Write labels to a Parquet file

Labels come from the table's metadata (a DataFrame from `read_parquet`,
`read_fixed_width` or `DataFrame(read_dta(f))` has them, and
`colmetadata!` and `metadata!` add them), and from keyword arguments,
which take precedence: `label`, `notes`, `value_labels`,
`column_labels`, `column_formats` and `column_value_labels`, as in
[Write a file](#write-a-file). The table's `"timestamp"`,
`"characteristics"` and `"sorted_by"` metadata are kept too.

```julia datakit
smoking = DataFrame(id = [1, 2, 3], smoker = DtaColumn(Int8[1, 0, 0], UInt8[0, 0, 5]))
colmetadata!(smoking, :id, "label", "Person"; style = :note)
save_parquet("smoking.parquet", smoking;
    label = "Smoking",
    notes = ["Wave 2 only."],
    value_labels = Dict("yesno" => Dict(0 => "No", 1 => "Yes", ".d" => "Don't know")),
    column_labels = Dict(:smoker => "Smokes daily"),
    column_value_labels = Dict(:smoker => "yesno"))

s = read_parquet("smoking.parquet")
metadata(s, "label")                       # "Smoking"
colmetadata(s, :id, "label")               # "Person"
colmetadata(s, :smoker, "label")           # "Smokes daily"
yesno = metadata(s, "value_labels")["yesno"]
[get(yesno, stata_key(s.smoker, i), "") for i in 1:3]   # ["Yes", "No", "Don't know"]
```

### Keep .a to .z in a Parquet file

`.a` to `.z` are written as tagged NaNs, the bits R holds them in, so a
column holding any is DOUBLE, its storage type recorded in the file's
dta profile; it reads back as a `DtaColumn` of the same type with the
same codes:

```julia datakit
[stata_code(p.income, i) for i in 1:6]                # UInt8[0, 5, 0, 1, 19, 0]
colmetadata(p, :income, "storage")                    # "double"
save_parquet("nulls.parquet", p; missing_letters = false)
n = read_parquet("nulls.parquet")
[stata_code(n.income, i) for i in 1:6]                # UInt8[0, 1, 0, 1, 1, 0]
typeof(n.income)                                      # Vector{Union{Missing, Float64}}: no letters left
```

R's datakit, arrow, nanoparquet and Python's datakit read the letters
back. Other tools see NaN: Parquet2.jl keeps the bits, and DuckDB SQL
and polars count a NaN as a value rather than a missing one
([docs/parquet.md](parquet.md#what-other-tools-see-in-our-files)
gives the query that treats them as missing). For files meant for those
tools, `missing_letters = false` writes `.a` to `.z` as plain nulls, as
above, and the letters are lost. An `Int64` or `Bool` column cannot hold
a tagged NaN, so `.a` to `.z` in one is an error unless
`missing_letters = false`.

### Parquet files from other tools

pandas and pyarrow write timestamps in microseconds, which a `DateTime`
cannot hold, so read their files with `timestamps = :truncate`. The
repository's compatibility tests include a file pyarrow wrote:

```julia datakit
pyarrow_file = joinpath(pkgdir(Datakit), "..", "..", "compat", "parquet", "fixtures", "pyarrow_default.parquet")
o = read_parquet(pyarrow_file; timestamps = :truncate)
o.ts_us_ny[2]          # ZonedDateTime(2019, 12, 31, 19, 0, 1, tz"America/New_York"), 3 microseconds dropped
String.(levels(o.cat)) # ["low", "mid", "high"]
read_parquet_info(pyarrow_file)["created_by"]   # "parquet-cpp-arrow version 26.0.1"
```

Without `timestamps = :truncate` the read stops at the first value that
is not a whole number of milliseconds, and the message gives the call:

```text
column "ts_us_ny": row 2 is 1577836801000003 microseconds, which is not a whole number of
milliseconds, all a DateTime holds; read with read_parquet(".../pyarrow_default.parquet";
timestamps = :truncate) to drop what is below a millisecond
```

`read_parquet` reads the files pyarrow, pandas, polars, DuckDB, arrow,
nanoparquet, fastparquet, Parquet2.jl and hyparquet write: every
encoding (dictionary, PLAIN, RLE, the DELTA encodings,
BYTE_STREAM_SPLIT), data pages v1 and v2, and the codecs none, snappy,
gzip, zstd, lz4_raw and brotli. A column that pandas, polars or arrow
wrote as a category or factor (a dictionary of strings in the file's
Arrow schema) reads as a categorical. Its levels are the distinct values
of the rows read, in the order they first appear, and it is not
ordered: the file does not say which levels the writer had, or in what
order. Another window of rows can give other levels; reading every row
gives them all. A file `save_parquet` wrote carries every level, in
order, whatever rows are read.

DECIMAL columns read as `Float64`, the nearest double to each value. A
value with more than 15 significant digits, which a double cannot give
back, is an error naming the column and row; `decimal = :string` reads
every digit as text:

```julia datakit
types_file = joinpath(pkgdir(Datakit), "..", "..", "compat", "parquet", "fixtures", "pyarrow_types.parquet")
read_parquet(types_file; cols = [:dec9], n_max = 2).dec9                     # [-3000.0, -2987.63]
read_parquet(types_file; cols = [:dec38], n_max = 2, decimal = :string).dec38 # ["-370370367037037036.7037037100", "-369135799146913579.9146913643"]
# read_parquet(types_file; cols = [:dec38]) is an error: row 1 has more than 15 significant digits
```

Nested columns (lists, maps, structs) are not read. A file that has
them is an error unless `cols` leaves them out or `nested = :skip` is
given, which leaves them out of a read of every column:

```julia datakit
nested_file = joinpath(pkgdir(Datakit), "..", "..", "compat", "parquet", "fixtures", "pyarrow_nested.parquet")
names(read_parquet(nested_file; nested = :skip))   # ["id", "name"]
# read_parquet(nested_file) is an error: the file has nested columns, which are not read: "tags", "point", "props"; ...
```

What this version does not read, each an error that names the column
and its type: FLOAT16, INTERVAL, the Hadoop framing of LZ4, LZO and
encrypted files. Datasets of many files, Hive partitions and filters
pushed into the read are not part of Datakit; use DuckDB.jl for
those. What other tools see in files `save_parquet` writes is in
[docs/parquet.md](parquet.md#what-other-tools-see-in-our-files).

### What each Parquet type becomes in Julia

Every conversion is exact or an error that names the column, the row
and the option that keeps the value. A numeric column whose rows read
hold any of `.a` to `.z` is a `DtaColumn{T}`; any other column with a
missing value is a `Vector{Union{Missing,T}}`.

| Parquet | Julia |
|---|---|
| INT32: INT(8), INT(16) or none | `Int8`, `Int16`, `Int32` |
| INT64 | `Int64` |
| unsigned 8, 16, 32, 64 bits | `UInt8`, `UInt16`, `UInt32`, `UInt64` |
| FLOAT, DOUBLE | `Float32`, `Float64`; `.a` to `.z` (tagged NaNs) as `DtaColumn` codes, other NaN stay NaN |
| a DOUBLE `save_parquet` (or R's datakit) widened for `.a` to `.z` | its storage type again: `Int8`, `Int16`, `Int32` or `Float32`, a `DtaColumn` with the codes when the rows read hold letters |
| a DOUBLE date or timestamp (profile `"logical"`) | `Date` or `DateTime` when the rows read hold no `.a` to `.z`; else a `DtaColumn{Float64}` of Stata's numbers: days since 1960 with `%td`, milliseconds since 1960 with `%tc` |
| DECIMAL | `decimal = :float` (default): `Float64`, the nearest to each value, and a value with more than 15 significant digits is an error naming `decimal = :string`; `:string` keeps every digit as text |
| BOOLEAN | `Bool` |
| DATE | `Date` |
| TIMESTAMP (milli-, micro-, nanoseconds), INT96 | `DateTime` (milliseconds): values that are not whole milliseconds are an error naming `timestamps = :truncate`; `ZonedDateTime` when the file gives a zone and TimeZones.jl is loaded, else `DateTime` in UTC with one warning |
| TIME (milli-, micro-, nanoseconds) | `Dates.Time` |
| STRING, ENUM, JSON | `String` |
| BYTE_ARRAY or FIXED_LEN_BYTE_ARRAY without a text annotation, UUID | `Vector{UInt8}` |
| a categorical `save_parquet` (or R's datakit) wrote | `CategoricalArray` with every level, ordered if it was, when CategoricalArrays.jl is loaded; else `String` with one warning |
| a dictionary of strings in the Arrow schema, with no levels in the profile (an arrow factor, a pandas `category`, a polars `Categorical`) | as above, unordered; levels are the distinct values of the rows read, in order of first appearance |
| a dictionary of another type in the Arrow schema | its values' type, by the rows above |
| FLOAT16, INTERVAL | not read: an error naming the column and type |

### Coming from Parquet2.jl

| Parquet2.jl | Datakit | what changes |
|---|---|---|
| `DataFrame(Parquet2.Dataset(path))`, `Parquet2.readfile(path)` | `read_parquet(path)` | a `DataFrame` read when called, not on use; labels, `.a` to `.z`, formats and notes kept as metadata |
| `ds \|> Parquet2.select(:a, :b)`, `Parquet2.load(ds, "a")` | `read_parquet(path; cols = [:a, :b])` | names or positions, in the order given; an unknown name lists the file's columns |
| `ds[i]`, row group `i` | `read_parquet(path; skip = 100, n_max = 50)` | any window of rows, not only whole row groups; only the pages that hold it are read |
| `Parquet2.metadata(ds)`, `Tables.schema(ds)` | `read_parquet_info(path)` | rows, row groups, codecs, key-value entries, labels, and the element type of each column in a `DataFrame` |
| every TIMESTAMP as a UTC `DateTime`, zone dropped; units below a millisecond cut | `DateTime`, or `ZonedDateTime` in the file's zone (TimeZones.jl); an error, or `timestamps = :truncate`, for units below a millisecond | |
| DECIMAL as `DecFP.Dec64` | `Float64`, or `String` with `decimal = :string` | |
| a nested column anywhere in the file is an error | `nested = :skip` or `cols` leave nested columns out | |
| `Parquet2.writefile(path, tbl)` (snappy) | `save_parquet(path, tbl)` (snappy) | labels, `.a` to `.z`, zones and categoricals written, with statistics and page indexes |
| `compression_codec = :zstd` | `compression = :zstd, compression_level = 3` | levels |
| one row group per `Tables.partitions` partition | `row_group_size = n` | |
| `metadata = Dict(...)`, `column_metadata = ...` | `label`, `notes`, `value_labels`, `column_labels`, `column_formats`, `column_value_labels`, or the table's DataAPI metadata | read back as DataFrames metadata, not as key-value text |
| `CategoricalArray`, `ZonedDateTime` columns are errors | written, with their levels and zone | |

## Threads

Reading and writing large files uses up to three threads, which decode the rows; Julia receives the chunks in order on the calling task. On x86, where processors pair their hardware threads, the most is half the processor count, up to three. Reads that need a strL column, small reads and writes (under 16 MB of selected data) and every read on Windows use one thread. In our measurements the threads together used at most 15% more CPU time than one thread doing the same work. They are the library's own threads, not Julia's, so `julia -t` does not change them.

Set the `DTA_THREADS` environment variable to `1` to use one thread, or to another number to change the most; it is read at each call. While `write_dta` runs, nothing may change the arrays it writes.

Datakit's Parquet reads and writes follow their own rule, measured on Parquet files: reads and writes under 16 MB use one thread, larger reads a thread per 176 MiB of decoded values (two to eight) and larger writes one per 256 MiB (two to six); `DTA_THREADS` sets the count instead ([docs/parquet.md](parquet.md#defaults-and-the-measurements-behind-them)). Text and categoricals arrive on the calling task, column chunk by column chunk. While `save_parquet` runs, nothing may change the table it writes.

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

**`.a` became `.` after a DataFrames operation.** `combine`, `vcat` of
DataFrames, and any function over the column build plain vectors; see
[Labels and .a to .z through DataFrames operations](#labels-and-a-to-z-through-dataframes-operations)
for what keeps the codes.

**`set_stata_code!` fails with a `MethodError`.** The column is a plain
vector: Datakit returns a `DtaColumn` only when the rows read hold
`.a` to `.z`. Convert it in place first:
`df[!, :x] = DtaColumn(df.x)`.

**"Datakit ... needs DtaParser's library interface version".** The
DtaParser that loaded is from another checkout, or was not rebuilt.
Develop both packages from the same checkout, run
`Pkg.build("DtaParser")`, and restart Julia.

**`read_parquet`, `write_parquet` or `read_fixed_width` is not defined
after `using DtaParser`.** They moved to Datakit in DtaParser 0.3 (see
[docs/migration.md](migration.md#dtaparser-02-to-03)): `using Datakit`,
and `write_parquet` is now `save_parquet`. `read_meta` on a Parquet file
is `read_parquet_info`.

**`DataFrame(t)` has no column metadata.** Load DataFrames before
calling it (`using DataFrames`); the extension that copies metadata
loads with it.

**"is not a whole number of milliseconds".** A Parquet timestamp in
microseconds or nanoseconds, as pandas, pyarrow and polars write them,
holds more than a `DateTime` can. Pass `timestamps = :truncate`, as the
message says, to drop what is below a millisecond.

**"TimeZones.jl is not loaded" or "CategoricalArrays.jl is not loaded"
when reading Parquet.** The file has zoned timestamps or categorical
columns. Add and load the package (`using TimeZones`,
`using CategoricalArrays`) and read again; without them the values are
`DateTime` in UTC and `String`.

**"the file has nested columns, which are not read".** Pass
`nested = :skip`, or name the columns wanted with `cols`. For the
nested data itself, use DuckDB.jl.

**"has more than 15 significant digits".** A Parquet DECIMAL value a
`Float64` cannot give back; read with `decimal = :string`.

**A Parquet file from another tool has no labels.** Only files with the
dta profile (from `save_parquet`, R's or Python's datakit or the npm package)
carry labels; see [docs/parquet.md](parquet.md#the-profile).

**`InexactError` in arithmetic on a column.** The column is `Int8` or
`Int16`, the file's storage type. Widen it: `Int.(col)` or
`Float64.(col)`.

## API reference

Every export has a docstring (`?read_dta` at the REPL).

DtaParser:

- `read_dta(path; cols, skip, n_max, encoding, dates)`: read a file into
  a `DtaTable`.
- `read_meta(source; encoding)`: a `.dta` file's metadata, `"nrows"`,
  `"format"` and `"columns"`, without rows.
- `write_dta(path, table; label, notes, timestamp, value_labels,
  column_labels, column_formats, column_value_labels)`: write release 118.
- `DtaTable`: what `read_dta` returns; Tables.jl and DataAPI metadata.
- `DtaColumn{T}(values, codes)`, `DtaColumn(x)`: numbers with missing
  codes.
- `stata_code(col, i)`, `set_stata_code!(col, i, code)`: read and set a
  missing code.
- `stata_key(x)`, `stata_key(col)`, `stata_key(col, i)`: `Float64`s that
  sort as Stata does.

Datakit (which also exports `DtaColumn`, `stata_code`,
`set_stata_code!` and `stata_key`):

- `read_parquet(source; cols, skip, n_max, timestamps, decimal,
  nested)`: read a Parquet file into a `DataFrame` (see
  [Parquet files](#parquet-files)).
- `read_parquet_info(source)`: a Parquet file's schema and metadata
  without rows (see [Schema and metadata](#a-parquet-files-schema-and-metadata)).
- `save_parquet(path_or_io, table; label, notes, compression,
  compression_level, row_group_size, missing_letters, value_labels,
  column_labels, column_formats, column_value_labels)`: write a Parquet
  file that keeps labels and `.a` to `.z` (see
  [Write a Parquet file](#write-a-parquet-file)).
- `read_fixed_width(path, setup; recodes, cols, skip, n_max,
  commented_formats)`: read fixed-width text through its SAS setup file,
  one path or a vector of paths, into a `DataFrame` (see
  [Fixed-width files](#fixed-width-files-with-a-sas-setup-file)).
