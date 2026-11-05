"""
Read and write Stata `.dta` files, through dta-parser's Rust core.

`read_dta` returns a [`DtaTable`](@ref); `write_dta` writes any Tables.jl
table as release 118. `read_parquet` and `write_parquet` read and write
Parquet files that keep the same labels and missing values. Numeric columns with missing values are
[`DtaColumn`](@ref)s, which keep Stata's `.a` to `.z`.
"""
module DtaParser

using Dates
import DataAPI
import Tables

export read_dta, read_fixed_width, read_meta, read_parquet, write_dta, write_parquet, DtaTable, DtaColumn, stata_code,
       set_stata_code!, stata_key

include("lib.jl")
include("json.jl")
include("column.jl")
include("table.jl")
include("read.jl")
include("write.jl")
include("fixed_width.jl")
include("parquet.jl")
include("parquet_write.jl")
include("precompile.jl")

end
