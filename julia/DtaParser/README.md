# DtaParser.jl

Read Stata `.dta` files (releases 104 to 119) and write release 118, from
Julia. The format is implemented once, in Rust (`crates/dta`), and
reached through a small C library (`crates/dta-ffi`, see its
`include/dta.h`).

## Install

DtaParser builds its library from a checkout of this repository, so it
needs Rust's `cargo`:

```julia
import Pkg
Pkg.develop(path="julia/DtaParser")
Pkg.build("DtaParser")
```

## Use

```julia
using DtaParser, DataFrames, Dates

t = read_dta("survey.dta")                 # a DtaTable: Tables.jl, DataAPI metadata
t = read_dta("survey.dta"; cols=[:age, :region], skip=100, n_max=1000)
df = DataFrame(t)                          # keeps DtaColumns and metadata
colmetadata(df, :region, "label")          # variable label
metadata(df, "value_labels")["yesno"][stata_key(".d")]

stata_code(df.answer, 3)                   # 0 for a value, 1 for ., 2 to 27 for .a to .z
set_stata_code!(df.answer, 3, 5)           # make row 3 .d
sort(df, :answer)                          # codes follow their rows

write_dta("out.dta", df)
write_dta("new.dta", (id=1:3, when=[Date(2024, 1, 1), Date(2024, 1, 2), missing], note=["a", "b", "c"]);
          label="Example", value_labels=Dict("yesno" => Dict(0 => "No", 1 => "Yes", ".d" => "Don't know")))
```

`read_meta(path)` gives the metadata without the data.

## How Stata's values arrive

- A numeric column is a `Vector` of its storage type (`Int8` byte,
  `Int16` int, `Int32` long, `Float32` float, `Float64` double). With
  any missing value it is a `DtaColumn{T}`: elements read as `missing`,
  and `stata_code` tells `.` from `.a` to `.z`.
- Slicing, `view`, `copy`, `similar`, `sort`, `permute!`, `vcat` and
  `append!` of `DtaColumn`s, and assigning a `DtaColumn` into a slice of
  another, keep the codes. So do DataFrames' row selection, `sort`,
  `subset`, `filter`, `copy`, and `select`/`transform` on grouped frames.
- Assigning a single element (`b[i] = a[i]`) copies `missing`, which
  becomes `.`. DataFrames' `combine` on groups and `vcat` of DataFrames
  build plain vectors: `.` is kept, the letters are lost. `groupby` on a
  `DtaColumn` puts all missing values in one group.
- `stata_key(x)` gives a `Float64` that sorts and compares as Stata does:
  numbers, then `.`, `.a`, ..., `.z` (the same keys as dtatools and the
  npm package).
- Strings are `Vector{String}`; binary strLs are `Vector{UInt8}`.
- `%td` and `%tc` columns become `Date` and `DateTime` (`dates=false`
  keeps numbers). A column with `.a` to `.z`, or values that are not
  whole numbers, stays numeric. `%tC`, which counts leap seconds, always
  stays numeric.

## Writing a table that did not come from `read_dta`

| Julia | Stata |
|---|---|
| `Bool` | byte |
| integers | the smallest of byte, int, long that holds every value, else double; an error beyond ±2^53 |
| `Float32`, `Float64` | float, double; `NaN` is `.` |
| `DtaColumn` | its storage type and codes |
| `missing` in a numeric column | `.` |
| `Date`, `DateTime` | long `%td`, double `%tc` |
| `String` | strN up to 2045 bytes, else strL; `missing` becomes `""` |
| `Vector{UInt8}` | binary strL |

Anything else, and any column name Stata cannot hold, is an error naming
the column.
