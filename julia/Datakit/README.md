# Datakit.jl

Data preparation for Stata do-files translated to Julia. Datakit reads
Parquet files and fixed-width text into a `DataFrame` and saves any
table as Parquet, keeping Stata's value labels, variable labels, display
formats, notes and the missing values `.a` to `.z`. It is the Julia
counterpart of R's datakit: files go between the two with their labels
and letters. `.dta` files are [DtaParser](../DtaParser)'s, on which
Datakit is built.

A column holding `.a` to `.z` is a `DtaColumn`, which keeps each row's
code. A function over the column builds a new vector, and the letters
in it become `.` without a warning:

```julia
using Datakit, DataFrames

df = DataFrame(id = 1:4, income = DtaColumn([2100.0, 0, 1850, 0], UInt8[0, 5, 0, 19]))  # .d, .r
save_parquet("survey.parquet", df; column_labels = Dict(:income => "Monthly income"))

p = read_parquet("survey.parquet")
[stata_code(p.income, i) for i in 1:4]           # UInt8[0, 5, 0, 19]: .d and .r kept
yearly = p.income .* 12
[stata_code(yearly, i) for i in 1:4]             # UInt8[0, 1, 0, 1]: both are . now
colmetadata(p, :income, "label")                 # "Monthly income"
```

Filtering, sorting, joins and `select` of the column as it is keep the
codes; `combine`, `vcat` of DataFrames and any function over the column
lose them. The list, and how to set a letter, are in
[docs/julia.md](../../docs/julia.md#labels-and-a-to-z-through-dataframes-operations).

## Install

Datakit and DtaParser are not in the General registry yet. Install both
from a checkout of the repository; building DtaParser's library needs
Rust's `cargo` ([rustup.rs](https://rustup.rs)) and Julia 1.10 or later.

```sh
git clone https://github.com/jbearak/dta-parser
```

```julia norun
import Pkg
Pkg.develop(path="dta-parser/julia/DtaParser")   # first: Datakit needs DtaParser 0.3
Pkg.develop(path="dta-parser/julia/Datakit")
Pkg.build("DtaParser")                            # runs cargo
Pkg.add("DataFrames")                             # for `using DataFrames` in your scripts
```

Run this from the directory you cloned into, in the environment you
want the packages in. Datakit depends on DataFrames 1.4 or later and
loads it; add it to your environment as well to call its functions
(`nrow`, `colmetadata`, ...) by name.

TimeZones.jl and CategoricalArrays.jl are optional: with them loaded,
zoned timestamps and categorical columns read and write as
`ZonedDateTime` and `CategoricalArray`.

## Use

- `read_parquet(source; cols, skip, n_max, timestamps, decimal, nested)`
  reads a Parquet file into a `DataFrame`, labels in `metadata` and
  `colmetadata`.
- `read_parquet_info(source)` reads its schema and metadata, without
  rows.
- `save_parquet(path_or_io, table; ...)` writes any Tables.jl table,
  taking labels from its metadata and from keyword arguments.
- `read_fixed_width(path, setup; ...)` reads fixed-width text, such as
  the NSFG files, through its SAS setup file.

Datakit also exports DtaParser's `DtaColumn`, `stata_code`,
`set_stata_code!` and `stata_key`. The guide is
[docs/julia.md](../../docs/julia.md#datakit-parquet-and-fixed-width-text-into-dataframes);
the file format is [docs/parquet.md](../../docs/parquet.md).
