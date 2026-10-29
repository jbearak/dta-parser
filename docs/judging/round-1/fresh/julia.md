# DtaParser.jl docs check: ten tasks

Source of truth: `docs.md` only. Julia 1.13.3 (juliaup), the checkout at
`/Users/jmb/repos/dta-parser.new/.claude/worktrees/agent-a2eb7dc5013b84836`. Scripts live next to this report
(`t01_install.jl`, `t02_04.jl`, `t05_07.jl`, `t08_10.jl`, `t10x.jl`). All `.dta` files were written by the library.
Julia depot (`JULIA_DEPOT_PATH`) and cargo home (`CARGO_HOME`) were set inside `scratch/` so nothing installed outside it.

Outcomes: 1 succeeded, 2 succeeded, 3 succeeded, 4 succeeded, 5 succeeded, 6 succeeded, 7 succeeded, 8 succeeded, 9 succeeded, 10 succeeded.
Every task worked as the docs describe. The problems below are gaps and unclear spots, not wrong statements.

## Task 1: install and load: succeeded

```julia
import Pkg
Pkg.activate("<scratch>")
Pkg.develop(path="<checkout>/julia/DtaParser")
Pkg.build("DtaParser")
Pkg.add("DataFrames"); Pkg.add("CategoricalArrays")
using DtaParser
```
Saw: `loaded: DtaParser`. Build (cargo) finished and the library loaded.

Environment note (not a docs problem): the first attempt inside the sandbox failed fetching the Julia registry
("SSL certificate ... unable to get local issuer certificate", then a segfault), because the sandbox proxy intercepts TLS. I reran
that one command outside the sandbox and it worked.

Doc issues:
- Install says `Pkg.develop(path="dta-parser/julia/DtaParser")`. That path is relative to the directory where you cloned; it is not stated.
  I used an absolute path to the checkout.
- No mention of creating or activating a project environment first. A user who runs the snippet in the default environment installs into the global one.
- "Pkg.add("DataFrames")  # optional" is listed, but `CategoricalArrays` (needed for the categorical recipe under Value labels) is not
  in the Install section; it is only named later ("needs CategoricalArrays.jl").
- "DtaParser needs Julia 1.10 or later" - I only tried 1.13.3, so I can't confirm the lower bound.

## Task 2: write a table, read it back, column types: succeeded

```julia
src = DataFrame(n=[10,20,30,40,50,60], x=[1.5,...], s=["a","bb",...], d=Date.([...]))
write_dta("t2.dta", src)          # returns "t2.dta"
t = read_dta("t2.dta"); df = DataFrame(t)
```
Saw: `read_dta` returns a `DtaTable`; columns are `n` `Vector{Int8}`, `x` `Vector{Float64}`, `s` `Vector{String}`, `d` `Vector{Date}`.
Matches the docs ("integers: the smallest of byte, int, long", "`Date` ... long `%td`", "`Vector{String}`").

Doc issues: none. (Worth knowing: an `Int` column becomes `Int8` on read; the docs say so, with the overflow warning, in "Read a file".)

## Task 3: two columns in reverse order; unknown column: succeeded

```julia
read_dta("t2.dta"; cols=[:x, :n])      # names: ["x","n"]
read_dta("t2.dta"; cols=["s","d"])     # ["s","d"]
read_dta("t2.dta"; cols=[3,1])         # ["s","n"]
read_dta("t2.dta"; cols=:s)            # ["s"]
read_dta("t2.dta"; cols=[:x,:nope])
```
Saw: columns come back in the order asked (reverse of file order). An unknown name throws
`ArgumentError: there is no column nope`. Also `ArgumentError: a column is selected twice` and
`ArgumentError: there is no column 9; the file has 4`. All as documented ("A name the file does not have ... throws an `ArgumentError`").

Doc issues: none.

## Task 4: rows 3 to 5; rows past the end: succeeded

```julia
read_dta("t2.dta"; skip=2, n_max=3)    # rows 3,4,5
read_dta("t2.dta"; skip=4, n_max=10)   # 2 rows
read_dta("t2.dta"; skip=10, n_max=3)   # 0 rows, all 4 column names present
read_dta("t2.dta"; skip=6)             # 0 rows (skip == nrows)
```
Saw: rows 3-5 exactly (`n` = 30, 40, 50). Asking beyond the end gives fewer rows, or an empty table with the columns intact; no error.
Matches "Rows past the end give fewer rows, or none; it is not an error."

Doc issues: the docs use 0-based `skip` with 1-based "rows 3 to 5" implied by the example (`skip = 2, n_max = 3`). It works but there is no explicit "rows 3 to 5 is `skip=2, n_max=3`" sentence; the example `part.id # Int8[3, 4, 5]` covers it.

## Task 5: variable labels, data label, formats, storage types, without data: succeeded

```julia
write_dta("t5.dta", src; label="Task five data", column_labels=Dict(...), column_formats=Dict(:x=>"%9.2f"),
          value_labels=..., column_value_labels=...)
m = read_meta("t5.dta")      # no rows read
m["label"]; for c in m["columns"] ... c["label"], c["format"], c["storage"], c["value_labels"]
```
Saw: `m["label"] == "Task five data"`; per column `n`: label "Count code", `%8.0g`, `byte`, set `grp`; `x`: "A float", `%9.2f`, `double`;
`s`: `str3`, `%-3s`; `d`: `%td`, `long`. Also `m["nrows"] == 5`, `release 118`, `encoding "utf-8"`. The same values come from
`metadata(t, "label")` and `colmetadata(t, c, "label"|"format"|"storage")` on a read table. `read_dta(...; n_max=0)` also works (0 rows, metadata present),
though the docs do not mention that.

Doc issues:
- `read_meta`'s return is described in prose ("a `Dict` with the table metadata, `"nrows"`, and `"columns"`") and the example only prints `nrows` and names.
  The per-column keys are said to be "`"name"` and its column metadata", which is enough, but a one-line example showing `c["label"]`, `c["format"]`, `c["storage"]` would help.
- Default display formats chosen by the writer (`%8.0g`, `%10.0g`, `%-3s`, ...) are not listed anywhere.

## Task 6: value label set, lookup, categorical: succeeded

```julia
write_dta("t5.dta", src; value_labels=Dict("grp"=>Dict(1=>"one",2=>"two",3=>"three")), column_value_labels=Dict(:n=>"grp"))
t = read_dta("t5.dta")
set = colmetadata(t, :n, "value_labels")             # "grp"
labels = metadata(t, "value_labels")[set]            # Dict(3.0=>"three", 2.0=>"two", 1.0=>"one")
labels[2]                                            # "two"
using CategoricalArrays
levels_in_order = [labels[k] for k in sort(collect(keys(labels)))]
cat = categorical([labels[x] for x in t.n]; levels=levels_in_order)
```
Saw: `labels[2] == "two"` (Int key finds the Float64 key, as documented); decoded vector `["one","two","three","one","two"]`; a
`CategoricalVector{String,UInt32,...}` with levels one, two, three. Printing `levels(cat)` shows `CategoricalValue`s in CategoricalArrays 1.1.1
(a CategoricalArrays change, nothing to do with DtaParser).

Doc issues:
- The categorical block is marked `julia norun` and so is never tested. It works as written, but it only handles columns whose every code has a label:
  a code without a label, or a `missing` (e.g. `.d`), makes `labels[x]` throw `KeyError` (or fail on `missing`). The recipe above it, `get(labels, x, string(x))`,
  is safe; the categorical recipe should use the same pattern.
- "Julia a comprehension over the column" (value-labels guide) and the language page are the only "conversion" help; there is no function for it. Not wrong, but the task's "turn the column into the categorical type" is manual.
- "Dict(1.0 => "North", ...)" - keys are `Float64`; `labels[2]` works. Clear.

## Task 7: date column as a date, then with conversion off: succeeded

```julia
t = read_dta("t5.dta");  eltype(t.d)           # Date
raw = read_dta("t5.dta"; dates=false)
eltype(raw.d), raw.d, colmetadata(raw, :d, "format")   # Int32, Int32[23376,...], "%td"
Date(1960) + Day(raw.d[1])                      # 2024-01-01
```
Saw: `Date` by default; with `dates=false`, `Int32[23376, 23377, 23378, 23407, 23436]` and format `%td`; `Date(1960)+Day(23376) == 2024-01-01`.
Matches the docs.

Doc issues: the docs' example `raw.interviewed[1]  # 23436` is for the survey file; fine. The raw column type (`Int32`, the long storage type) is not stated on the Dates section, only implied from the storage-types table.

## Task 8: release written, storage types, an error: succeeded

```julia
tab = DataFrame(flag=[true,false,true], small=[1,2,3], mid=[1000,2000,3000], big=[100_000,200_000,3_000_000_000],
                f32=Float32[...], f64=[0.1,...], txt=["x","yy","zzz"], day=Date(2020,1,1).+Day.(0:2), when=DateTime(2020,1,1,12).+Second.(0:2))
write_dta("t8.dta", tab); r = read_dta("t8.dta")
metadata(r, "release")                      # 118
colmetadata(r, c, "storage")
```
Saw: release 118, little-endian. Storage: `flag` byte, `small` byte, `mid` int, `big` **double** (3,000,000,000 exceeds long's 2,147,483,620),
`f32` float, `f64` double, `txt` str3, `day` long `%td`, `when` double `%tc`. All as the table in "Write a file" says.

Errors the docs say are errors, all raised (type `DtaParser.WriteError`):
- `"1abc"`, `"a b"`, `in` (reserved) and a 33-character name:
  `column name "1abc" is not a valid Stata name: 1 to 32 letters, digits or _, not starting with a digit, and not a reserved word`
- Int beyond ±2^53: `column a: 1152921504606846976 is beyond ±2^53, which Stata cannot hold exactly`
- Complex and Symbol columns: `column a: cannot write values of type Complex{Int64}`
- `DtaColumn(Int8[120, 1], UInt8[0, 0])` is an error too: `a row 1: 120 does not fit storage type byte`. 120 fits `Int8` but not Stata's byte,
  whose values run −127 to 100 (101-127 are reserved for missing values). That matches the storage-types guide ("a write fails with 'does not fit'").

Doc issues:
- The error type is never named. The docs say "throws an error naming the column" and the troubleshooting says "does not fit" (storage-types guide), but the types
  `DtaParser.WriteError` and `DtaParser.DtaError` are neither exported (`names(DtaParser)` lacks them) nor listed in the API reference, so `catch e; e isa WriteError` needs the
  qualified name and the user has to discover it.
- "1 to 32 letters, digits or `_`" doesn't say which letters (ASCII only?); I did not test non-ASCII names.
- The reserved word list is not given (`in` is rejected; I did not try others).

## Task 9: variable label, value label set, data label, check by reading back: succeeded

```julia
write_dta("t9.dta", (id=[1,2,3], sex=Int8[1,2,1]); label="My data label",
    column_labels=Dict(:id=>"Identifier", :sex=>"Sex of respondent"),
    value_labels=Dict("sexl"=>Dict(1=>"Female", 2=>"Male")), column_value_labels=Dict(:sex=>"sexl"))
b = read_dta("t9.dta")
```
Saw: `metadata(b,"label") == "My data label"`; `colmetadata(b,:id,"label") == "Identifier"`, `colmetadata(b,:sex,"label") == "Sex of respondent"`;
`colmetadata(b,:sex,"value_labels") == "sexl"`; `metadata(b,"value_labels") == Dict("sexl"=>Dict(2.0=>"Male", 1.0=>"Female"))`; decoded `["Female","Male","Female"]`.
Writing the read table back (`write_dta("t9b.dta", b)`), and writing `DataFrame(b)`, both kept all three kinds of label.

Doc issues: none. The keyword table and the `smokers.dta` example were enough.

## Task 10: ., .a, .z per value; filter, sort, write back: succeeded

```julia
col = DtaColumn([5.0, NaN, 7.5, NaN, 2.0, NaN, 9.0], UInt8[0, 1, 0, 2, 0, 27, 0])   # ordinary, ., ordinary, .a, ordinary, .z, ordinary
write_dta("t10.dta", (id=1:7, v=col)); r = read_dta("t10.dta"); v = r.v
letter(c) = c == 0 ? "" : c == 1 ? "." : string('.', Char('a' + c - 2))
[ismissing(v[i]) ? letter(stata_code(v, i)) : v[i] for i in eachindex(v)]
stata_key(v)
```
Saw: `v` is `DtaColumn{Float64}`; every missing prints as `missing`, but per value `stata_code` gives `5.0, ".", 7.5, ".a", 2.0, ".z", 9.0`; `stata_key` gives
`8.98846567431158e307`, `8.990660123939097e307`, `9.045521364627034e307` for `.`, `.a`, `.z` (all above every ordinary number).
- Filter (`subset(df, :id => ByRow(>=(2)))` and `filter(r -> r.id >= 2, df)`): codes kept (`[".z", 7.5, ".", 2.0, ".a", 9.0]` on a column ordered `.z, ., .a`).
- Sort: with the original order `.z, ., .a`, `sort(df, :v)` gives `2.0 5.0 7.5 9.0 .z . .a` (missing last, original order, as documented);
  `sort(df.v)` and `df[sortperm(stata_key(df.v)), :]` give `2.0 5.0 7.5 9.0 . .a .z` (Stata order).
- Write back sorted frame and read: `. .a .z` still distinct. Write back filtered frame: `[".", 7.5, ".a", 2.0, ".z", 9.0]` all letters survive.
- `vcat(df, df)` loses them: `.z` and `.a` become `.`, as the docs warn.
- `set_stata_code!(w2, 2, 3)` made row 2 `.b`.

Doc issues:
- To build a column with a specific letter you must know the numeric code (1 is `.`, 2 is `.a`, ..., 27 is `.z`). That is said ("1 for `.`, 2 to 27 for `.a` to `.z`") but there is no
  letter-to-code helper in the API reference. The `Char('a' + c - 2)` conversion appears only inside the "Count each missing value" recipe; a documented `stata_code("." / ".a")`-style helper
  or a note that the letters map by `Char('a' + code - 2)` would help. `stata_key(".a")` exists for the keys but not for the codes.
- The value under a missing code is a placeholder (`NaN` in the docs' own example); `DtaColumn([...], codes)` accepts it without comment.
- `DtaColumn(x)` on a vector with no missing values returns a `DtaColumn` (not a plain `Vector`), while "Read a file" says a column with no missing value is a plain `Vector{T}` on read.
  Reasonable but unstated.
