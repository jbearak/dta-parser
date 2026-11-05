# Julia: DtaParser.jl

DtaParser reads Stata `.dta` files into a Tables.jl table, which you can
turn into a DataFrame, and writes any Tables.jl table as a `.dta` file.
It reads every release from 104 to 119 and writes release 118. Numeric
columns keep Stata's missing values `.a` to `.z` through slicing,
sorting, filtering and writing, and labels travel as DataAPI metadata.
It also reads and writes [Parquet files](#parquet-files) that keep the
same labels and missing values.

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
[Parquet files](#parquet-files) ·
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

Run this from the directory you cloned into (the path is relative to
it), in the environment you want DtaParser in: your project's, after
`Pkg.activate("path/to/project")`, or the default one.

DtaParser depends on Tables.jl and DataAPI.jl. DataFrames (1.4 or
later) is optional: when it is loaded, `DataFrame(t)` carries the
labels across as metadata. CategoricalArrays.jl is needed only for the
categorical recipe under [Value labels](#value-labels).

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

The letter `c` has code `c - 'a' + 2` (`.a` is 2, `.d` is 5, `.z` is
27), and code `k` is the letter `'a' + k - 2`.

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

## Fixed-width files with a SAS setup file

Some surveys are published as fixed-width text with a SAS program, the
*setup file*, that says where each variable sits. CDC publishes the
National Survey of Family Growth this way, from 1973 to 2017-2019.
`read_fixed_width` reads such data through its setup file: columns from
`INPUT`, variable labels from `LABEL`, value labels from `PROC FORMAT`
and `FORMAT`, record types from
`IF rec_type < 5 THEN DELETE; ELSE INPUT ...`, and the setup's
*missing-value recodes*, such as `IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;`.

```julia
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
`missing` with code 1 (`.`), and the columns are as `read_dta` returns
them:

```julia
t = read_fixed_width("survey.dat", "survey.sas")
collect(t.KIDS)                           # Union{Missing, Int8}[2, missing, missing, 0]
colmetadata(t, :KIDS, "label")            # "Number of children"
```

`recodes=:tagged` keeps why each value is missing: per variable, the
codes recoded to `.` become `.a`, `.b`, ... (codes 2, 3, ...) in the
order the setup names them, and each code's value label moves to its
letter:

```julia
t = read_fixed_width("survey.dat", "survey.sas"; recodes=:tagged)
[stata_code(t.KIDS, i) for i in 1:4]      # UInt8[0, 2, 3, 0]
metadata(t, "value_labels")["kidsf"][stata_key(".a")]   # "(98) DK"
```

A letter means what that variable's labels say: `.a` is 98 "DK" here,
but in a variable whose setup recodes 97 "Refused" first, `.a` is
"Refused". `recodes=:none` ignores the recodes, keeping the codes as
numbers.

Numeric columns take the smallest storage type that holds their values,
and records shorter than the setup's columns read as blank (`missing`).
Statements the reader does not run, such as other data-step code or a
range in `VALUE`, are skipped with one warning; table metadata
`"warnings"` lists them all. A `LENGTH` statement for numbers, which sets only how SAS stores them, is skipped without one. A variable label with stray quotes inside
it, such as `X = "WHETHER " SAME AS LAST MONTH" WAS ANSWERED"` in CDC's
2011-2013 to 2015-2017 setups, is read from its first quote to its
last, without a warning. `cols`, `skip` and `n_max` work
as in `read_dta`, after the whole file is read.

CDC's setups from 2002 on differ in two ways, and `read_fixed_width`
reads both. The 2002 setups come in three files (`2002FemPregInput.sas`,
`2002FemPregVarLabel.sas`, `2002FemPregValueLabel.sas`); give `setup` a
vector of the paths in that order, and they are read as one setup. A
statement may not run from one file into the next, and errors and
warnings name a file by its place (`"file 2 line 8"`):

```julia
write("input.sas", "DATA;\nINPUT ID 1-3 KIDS 4-5;\nRUN;\n")
write("labels.sas", "PROC FORMAT;\n  VALUE kidsf 0='(0) None' 98='(98) DK';\nRUN;\nFORMAT KIDS kidsf.;\n")
t = read_fixed_width("survey.dat", ["input.sas", "labels.sas"]; recodes=:none)
metadata(t, "value_labels")["kidsf"]   # Dict(0.0 => "(0) None", 98.0 => "(98) DK")
```

From 2006-2010 on, CDC puts the `PROC FORMAT` step and the `FORMAT`
statement each in a block comment (`/* ... */`), so that SAS users
without CDC's format catalog can run the file as published. The value
labels are still there, so by default a comment that holds nothing but
a `PROC FORMAT` step or a `FORMAT` statement is read as code; a comment
that only mentions them stays a comment. `commented_formats=false`
reads every comment as a comment, and those files then have no value
labels:

```julia
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
t = read_fixed_width("survey.dat", "commented.sas"; recodes=:none)
colmetadata(t, :KIDS, "value_labels")   # "kidsf"
t = read_fixed_width("survey.dat", "commented.sas"; recodes=:none, commented_formats=false)
colmetadata(t, :KIDS, "value_labels")   # ""
```

## Parquet files

`read_parquet` and `write_parquet` read and write Parquet files that
keep what a `.dta` file says: value labels, variable labels, display
formats, `.a` to `.z`, the data label, notes and time stamp, and also
categorical levels and time zones. `read_parquet` returns the
`DtaTable` that `read_dta` returns, with the same column types and
metadata, and a table `read_dta` gave comes back `isequal` after
`write_parquet`. The files are plain Parquet that Parquet2.jl, DuckDB,
pyarrow, polars, arrow and nanoparquet read;
[docs/parquet.md](parquet.md) says what each of them sees, and gives the
file's specification. Only flat tables are read and written: for lists,
maps or structs, use DuckDB.jl.

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

Parquet needs nothing beyond DtaParser, which [Install](#install)
covers: it reads and writes through the same Rust library, with no
Arrow or other Parquet package. Two packages are optional, and DtaParser
uses them when they are loaded (as package extensions):

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

```julia
using DtaParser, DataFrames, Dates

t = read_dta("survey.dta")
write_parquet("survey.parquet", t)
p = read_parquet("survey.parquet")
isequal(collect(p.income), collect(t.income))   # true
[stata_code(p.income, i) for i in 1:6]         # UInt8[0, 5, 0, 1, 19, 0]: ., .d, .r kept
typeof(p.interviewed)                          # Vector{Date}
df = DataFrame(p)                              # labels come along as metadata
```

`read_parquet(source)` returns a `DtaTable`, as `read_dta` does, and
`DataFrame(p)` makes a DataFrame with the metadata. `source` is a path,
an `IO` (read to its end) or a `Vector{UInt8}` holding a whole file.
Numbers keep their own type (`Int8`, `Int16`, `Int32`, `Int64`,
`Float32`, `Float64`, unsigned integers, `Bool`), and a column with any
missing value is a `DtaColumn` that keeps `.` apart from `.a` to `.z`
(see [Missing values](#missing-values)). A `NaN` stays `NaN`, a value.
Dates are `Date`, timestamps `DateTime`, text `String` and bytes
`Vector{UInt8}`; missing dates, text and bytes are `missing` in a
`Union{Missing,T}` vector. [What each type becomes](#what-each-parquet-type-becomes-in-julia)
gives the type of every Parquet column.

### Read some columns of a Parquet file

`cols` takes names (`Symbol` or `String`) or positions, and returns the
columns in the order given; only those columns are read from the file:

```julia
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

```julia
read_parquet("survey.parquet"; skip = 2, n_max = 2).id   # Int8[3, 4]
nrow(read_parquet("survey.parquet"; skip = 10))          # 0: past the end is no error
```

To work through a file in pieces, take the row count and the row groups
from `read_meta` (below) and read one window at a time.

### A Parquet file's schema and metadata

`read_meta(source)` reads the footer only. It tells a Parquet file from
a `.dta` file by its first bytes, and gives what it gives for `.dta`
(the table metadata, `"nrows"`, `"columns"`) and more:

```julia
m = read_meta("survey.parquet")
m["format"]                              # :parquet
m["nrows"]                               # 6
m["compression"]                         # ["snappy"]
m["row_groups"]                          # [(rows = 6, compressed_bytes = 329, uncompressed_bytes = 329)]
m["created_by"]                          # "dta-parquet version 0.1.0"
m["label"]                               # "Household survey (example)"
[c["name"] for c in m["columns"]]        # ["id", "region", "age", "income", "interviewed", "comment"]
[c["eltype"] for c in m["columns"]]      # [Int8, Int8, Int8, Union{Missing, Float64}, Date, String]
[c["physical_type"] for c in m["columns"]]   # ["INT32", "INT32", "INT32", "DOUBLE", "INT32", "BYTE_ARRAY"]
[c["logical_type"] for c in m["columns"]]    # ["INT(8, signed)", "INT(8, signed)", "INT(8, signed)", "", "DATE", "STRING"]
```

Each column's `Dict` has `"name"`, `"role"` (`"data"`, or `"nested"`
for a list, map or struct, which is not read), `"physical_type"`,
`"logical_type"`, `"eltype"` (the element type `read_parquet` gives,
with `Missing` when the file's statistics show nulls; `nothing` for a
column it does not read), and the column metadata: `"label"`,
`"format"`, `"value_labels"` and `"storage"` (a text column's is `""`
until it is read). `m["warnings"]` lists anything wrong with the file's
dta profile.

### Labels in Parquet files

Labels are DataAPI metadata, with the same keys as for `.dta` files
(see [Metadata](#metadata) and [Value labels](#value-labels)):

```julia
colmetadata(p, :age, "label")                     # "Age in years"
colmetadata(p, :region, "value_labels")           # "region"
labels = metadata(p, "value_labels")["region"]    # Dict(1.0 => "North", 2.0 => "South", ...)
[labels[x] for x in p.region]                     # ["North", "South", "South", "East", "West", "North"]
metadata(p, "value_labels")["nonresponse"][stata_key(p.income, 2)]   # "Don't know"
metadata(p, "label"), metadata(p, "notes")        # ("Household survey (example)", ["Made up for the DtaParser documentation."])
```

To make a labelled column a categorical one, with every label as a
level in code order (with CategoricalArrays.jl loaded):

```julia
using CategoricalArrays
region = categorical([labels[x] for x in p.region]; levels = [labels[k] for k in sort(collect(keys(labels)))])
write_parquet("regions.parquet", (region = region,))
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

```julia
visits = (day = [Date(2024, 3, 1), Date(2024, 3, 4)],
          at = [DateTime(2024, 3, 1, 9, 30), DateTime(2024, 3, 4, 17, 5, 0, 250)])
write_parquet("visits.parquet", visits)
v = read_parquet("visits.parquet")
v.at                     # [DateTime("2024-03-01T09:30:00"), DateTime("2024-03-04T17:05:00.250")]
[c["logical_type"] for c in read_meta("visits.parquet")["columns"]]   # ["DATE", "TIMESTAMP(MILLIS, local)"]
```

A `ZonedDateTime` (with TimeZones.jl loaded) is written as an instant,
a TIMESTAMP adjusted to UTC, with its zone; it reads back in that zone.
pyarrow, polars and arrow read the zone too:

```julia
using TimeZones
zoned = (at = ZonedDateTime.([DateTime(2024, 3, 1, 9, 30), DateTime(2024, 7, 1, 9, 30)], tz"America/New_York"),)
write_parquet("zoned.parquet", zoned)
read_parquet("zoned.parquet").at   # [ZonedDateTime(2024, 3, 1, 9, 30, tz"America/New_York"), ZonedDateTime(2024, 7, 1, 9, 30, tz"America/New_York")]
```

All values of a `ZonedDateTime` column must be in one zone; convert
them with `astimezone` first if not.

Reading a timestamp: the zone is the one `write_parquet` recorded, else
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

A date column of a `.dta` file that holds `.a` to `.z` stays numbers
with its `%td` format in `read_dta`, and is written and read back that
way. A file from R's datakit may hold such a column as DOUBLE days since
1970 (`"logical"` `"date"` in its profile): it reads as `Date` when the
rows read hold no `.a` to `.z`, else as numbers, days since 1960 with a
`%td` format, as `read_dta` would give them. Timestamps the same way:
`DateTime`, else milliseconds since 1960 with `%tc`.

### Write a Parquet file

`write_parquet(path_or_io, table)` writes any Tables.jl table and
returns `path_or_io`. Compression is snappy by default, which pyarrow,
polars and DuckDB read fastest; `compression` takes `:snappy`, `:zstd`,
`:gzip`, `:lz4_raw` or `:none`, and `compression_level` the codec's
level (zstd 1 to 22, gzip 0 to 9). zstd makes survey files about a sixth
smaller and slower to read. Row groups hold up to 262,144 rows and about
1 GiB of values; `row_group_size` sets the rows:

```julia
write_parquet("small.parquet", t; compression = :zstd, compression_level = 9, row_group_size = 2)
[g.rows for g in read_meta("small.parquet")["row_groups"]]   # [2, 2, 2]
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
`write_dta`, `write_parquet` takes any column name. Files are written
beside the target and renamed into place, so a failed write leaves an
existing file alone. [docs/parquet.md](parquet.md#defaults-and-the-measurements-behind-them)
gives the measurements behind the defaults.

### Write labels to a Parquet file

Labels come from the table's metadata, as for `write_dta` (a
`DtaTable`, or a DataFrame made from one, has them), and from keyword
arguments, which take precedence: `label`, `notes`, `value_labels`,
`column_labels`, `column_formats` and `column_value_labels`, as in
[Write a file](#write-a-file). The table's `"timestamp"`,
`"characteristics"` and `"sorted_by"` metadata are kept too.

```julia
smoking = DataFrame(id = [1, 2, 3], smoker = DtaColumn(Int8[1, 0, 0], UInt8[0, 0, 5]))
write_parquet("smoking.parquet", smoking;
    label = "Smoking",
    notes = ["Wave 2 only."],
    value_labels = Dict("yesno" => Dict(0 => "No", 1 => "Yes", ".d" => "Don't know")),
    column_labels = Dict(:smoker => "Smokes daily"),
    column_value_labels = Dict(:smoker => "yesno"))

s = read_parquet("smoking.parquet")
metadata(s, "label")                       # "Smoking"
colmetadata(s, :smoker, "label")           # "Smokes daily"
yesno = metadata(s, "value_labels")["yesno"]
[get(yesno, stata_key(s.smoker, i), "") for i in 1:3]   # ["Yes", "No", "Don't know"]
```

### Keep .a to .z in a Parquet file

`.a` to `.z` are written as tagged NaNs, the bits R holds them in, so a
column holding any is DOUBLE, its storage type recorded in the file's
dta profile; it reads back as the same `DtaColumn` type with the same
codes:

```julia
[stata_code(p.income, i) for i in 1:6]                # UInt8[0, 5, 0, 1, 19, 0]
colmetadata(p, :income, "storage")                    # "double"
write_parquet("nulls.parquet", p; missing_letters = false)
[stata_code(read_parquet("nulls.parquet").income, i) for i in 1:6]   # UInt8[0, 1, 0, 1, 1, 0]
```

R's arrow, nanoparquet and datakit read the letters back. Other tools
see NaN: Parquet2.jl keeps the bits, and DuckDB SQL and polars count a
NaN as a value rather than a missing one ([docs/parquet.md](parquet.md#what-other-tools-see-in-our-files)
gives the query that treats them as missing). For files meant for those
tools, `missing_letters = false` writes `.a` to `.z` as plain nulls, as
above, and the letters are lost. An `Int64` or `Bool` column cannot hold
a tagged NaN, so `.a` to `.z` in one is an error unless
`missing_letters = false`.

### Parquet files from other tools

pandas and pyarrow write timestamps in microseconds, which a `DateTime`
cannot hold, so read their files with `timestamps = :truncate`. The
repository's compatibility tests include a file pyarrow wrote:

```julia
pyarrow_file = joinpath(pkgdir(DtaParser), "..", "..", "compat", "parquet", "fixtures", "pyarrow_default.parquet")
o = read_parquet(pyarrow_file; timestamps = :truncate)
o.ts_us_ny[2]          # ZonedDateTime(2019, 12, 31, 19, 0, 1, tz"America/New_York"), 3 microseconds dropped
String.(levels(o.cat)) # ["low", "mid", "high"]
read_meta(pyarrow_file)["created_by"]   # "parquet-cpp-arrow version 26.0.1"
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
gives them all. A file `write_parquet` wrote carries every level, in
order, whatever rows are read.

DECIMAL columns read as `Float64`, the nearest double to each value. A
value with more than 15 significant digits, which a double cannot give
back, is an error naming the column and row; `decimal = :string` reads
every digit as text:

```julia
types_file = joinpath(pkgdir(DtaParser), "..", "..", "compat", "parquet", "fixtures", "pyarrow_types.parquet")
read_parquet(types_file; cols = [:dec9], n_max = 2).dec9                     # [-3000.0, -2987.63]
read_parquet(types_file; cols = [:dec38], n_max = 2, decimal = :string).dec38 # ["-370370367037037036.7037037100", "-369135799146913579.9146913643"]
# read_parquet(types_file; cols = [:dec38]) is an error: row 1 has more than 15 significant digits
```

Nested columns (lists, maps, structs) are not read. A file that has
them is an error unless `cols` leaves them out or `nested = :skip` is
given, which leaves them out of a read of every column:

```julia
nested_file = joinpath(pkgdir(DtaParser), "..", "..", "compat", "parquet", "fixtures", "pyarrow_nested.parquet")
names(read_parquet(nested_file; nested = :skip))   # ["id", "name"]
# read_parquet(nested_file) is an error: the file has nested columns, which are not read: "tags", "point", "props"; ...
```

What this version does not read, each an error that names the column
and its type: FLOAT16, INTERVAL, the Hadoop framing of LZ4, LZO and
encrypted files. Datasets of many files, Hive partitions and filters
pushed into the read are not part of DtaParser; use DuckDB.jl for
those. What other tools see in files `write_parquet` writes is in
[docs/parquet.md](parquet.md#what-other-tools-see-in-our-files).

### What each Parquet type becomes in Julia

Every conversion is exact or an error that names the column, the row
and the option that keeps the value. A column with any missing value in
the rows read is a `DtaColumn{T}` for numbers, and a `Union{Missing,T}`
vector for the rest.

| Parquet | Julia |
|---|---|
| INT32: INT(8), INT(16) or none | `Int8`, `Int16`, `Int32` |
| INT64 | `Int64` |
| unsigned 8, 16, 32, 64 bits | `UInt8`, `UInt16`, `UInt32`, `UInt64` |
| FLOAT, DOUBLE | `Float32`, `Float64`; `.a` to `.z` (tagged NaNs) as `DtaColumn` codes, other NaN stay NaN |
| a DOUBLE `write_parquet` (or datakit) widened for `.a` to `.z` | its storage type again: `Int8`, `Int16`, `Int32` or `Float32`, a `DtaColumn` with the codes |
| DECIMAL | `decimal = :float` (default): `Float64`, the nearest to each value, and a value with more than 15 significant digits is an error naming `decimal = :string`; `:string` keeps every digit as text |
| BOOLEAN | `Bool` |
| DATE | `Date` |
| TIMESTAMP (milli-, micro-, nanoseconds), INT96 | `DateTime` (milliseconds): values that are not whole milliseconds are an error naming `timestamps = :truncate`; `ZonedDateTime` when the file gives a zone and TimeZones.jl is loaded, else `DateTime` in UTC with one warning |
| TIME (milli-, micro-, nanoseconds) | `Dates.Time` |
| STRING, ENUM, JSON | `String` |
| BYTE_ARRAY or FIXED_LEN_BYTE_ARRAY without a text annotation, UUID | `Vector{UInt8}` |
| a categorical `write_parquet` (or datakit) wrote | `CategoricalArray` with every level, ordered if it was, when CategoricalArrays.jl is loaded; else `String` with one warning |
| a dictionary of strings in the Arrow schema, with no levels in the profile (an arrow factor, a pandas `category`, a polars `Categorical`) | as above, unordered; levels are the distinct values of the rows read, in order of first appearance |
| a dictionary of another type in the Arrow schema | its values' type, by the rows above |
| FLOAT16, INTERVAL | not read: an error naming the column and type |

### Coming from Parquet2.jl

| Parquet2.jl | DtaParser | what changes |
|---|---|---|
| `DataFrame(Parquet2.Dataset(path))`, `Parquet2.readfile(path)` | `read_parquet(path)`, `DataFrame(read_parquet(path))` | the columns are read when called, not on use; labels, `.a` to `.z`, formats and notes kept |
| `ds \|> Parquet2.select(:a, :b)`, `Parquet2.load(ds, "a")` | `read_parquet(path; cols = [:a, :b])` | names or positions, in the order given; an unknown name lists the file's columns |
| `ds[i]`, row group `i` | `read_parquet(path; skip = 100, n_max = 50)` | any window of rows, not only whole row groups; only the pages that hold it are read |
| `Parquet2.metadata(ds)`, `Tables.schema(ds)` | `read_meta(path)` | one `Dict`: rows, row groups, codecs, labels, and the element type of each column |
| every TIMESTAMP as a UTC `DateTime`, zone dropped; units below a millisecond cut | `DateTime`, or `ZonedDateTime` in the file's zone (TimeZones.jl); an error, or `timestamps = :truncate`, for units below a millisecond | |
| DECIMAL as `DecFP.Dec64` | `Float64`, or `String` with `decimal = :string` | |
| a nested column anywhere in the file is an error | `nested = :skip` or `cols` leave nested columns out | |
| `Parquet2.writefile(path, tbl)` (snappy) | `write_parquet(path, tbl)` (snappy) | labels, `.a` to `.z`, zones and categoricals written, with statistics and page indexes |
| `compression_codec = :zstd` | `compression = :zstd, compression_level = 3` | levels |
| one row group per `Tables.partitions` partition | `row_group_size = n` | |
| `metadata = Dict(...)`, `column_metadata = ...` | `label`, `notes`, `value_labels`, `column_labels`, `column_formats`, `column_value_labels`, or the table's DataAPI metadata | read back as DataAPI metadata, not as key-value text |
| `CategoricalArray`, `ZonedDateTime` columns are errors | written, with their levels and zone | |

## Threads

Reading and writing large files uses up to three threads, which decode the rows; Julia receives the chunks in order on the calling task. On x86, where processors pair their hardware threads, the most is half the processor count, up to three. Reads that need a strL column, small reads and writes (under 16 MB of selected data) and every read on Windows use one thread. In our measurements the threads together used at most 15% more CPU time than one thread doing the same work. They are the library's own threads, not Julia's, so `julia -t` does not change them.

Set the `DTA_THREADS` environment variable to `1` to use one thread, or to another number to change the most; it is read at each call. While `write_dta` runs, nothing may change the arrays it writes.

Parquet reads and writes follow their own rule, measured on Parquet files: reads and writes under 16 MB use one thread, larger reads a thread per 176 MiB of decoded values (two to eight) and larger writes one per 256 MiB (two to six); `DTA_THREADS` sets the count instead ([docs/parquet.md](parquet.md#defaults-and-the-measurements-behind-them)). Text and categoricals arrive on the calling task, column chunk by column chunk. While `write_parquet` runs, nothing may change the table it writes.

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
dta profile (from `write_parquet`, datakit or the other packages here)
carry labels; see [docs/parquet.md](parquet.md#the-profile).

**`InexactError` in arithmetic on a column.** The column is `Int8` or
`Int16`, the file's storage type. Widen it: `Int.(col)` or
`Float64.(col)`.

## API reference

Every export has a docstring (`?read_dta` at the REPL):

- `read_dta(path; cols, skip, n_max, encoding, dates)`: read a file into
  a `DtaTable`.
- `read_fixed_width(path, setup; recodes, cols, skip, n_max,
  commented_formats)`: read fixed-width text through its SAS setup file,
  one path or a vector of paths, into a `DtaTable` (see
  [Fixed-width files](#fixed-width-files-with-a-sas-setup-file)).
- `read_meta(source; encoding)`: a `.dta` or Parquet file's metadata,
  `"nrows"`, `"format"` and `"columns"`, without rows (see
  [Schema and metadata](#a-parquet-files-schema-and-metadata) for
  Parquet's).
- `read_parquet(source; cols, skip, n_max, timestamps, decimal,
  nested)`: read a Parquet file into a `DtaTable` (see
  [Parquet files](#parquet-files)).
- `write_parquet(path_or_io, table; label, notes, compression,
  compression_level, row_group_size, missing_letters, value_labels,
  column_labels, column_formats, column_value_labels)`: write a Parquet
  file that keeps labels and `.a` to `.z`.
- `write_dta(path, table; label, notes, timestamp, value_labels,
  column_labels, column_formats, column_value_labels)`: write release 118.
- `DtaTable`: what `read_dta` and `read_parquet` return; Tables.jl and
  DataAPI metadata.
- `DtaColumn{T}(values, codes)`, `DtaColumn(x)`: numbers with missing
  codes.
- `stata_code(col, i)`, `set_stata_code!(col, i, code)`: read and set a
  missing code.
- `stata_key(x)`, `stata_key(col)`, `stata_key(col, i)`: `Float64`s that
  sort as Stata does.
