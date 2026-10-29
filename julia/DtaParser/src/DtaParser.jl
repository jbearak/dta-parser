"""
Read and write Stata `.dta` files, through dta-parser's Rust core.

`read_dta` returns a [`DtaTable`](@ref); `write_dta` writes any Tables.jl
table as release 118. Numeric columns with missing values are
[`DtaColumn`](@ref)s, which keep Stata's `.a` to `.z`.
"""
module DtaParser

using Dates
import DataAPI
import Tables

export read_dta, read_meta, write_dta, DtaTable, DtaColumn, stata_code, set_stata_code!, stata_key

include("lib.jl")
include("json.jl")
include("column.jl")
include("table.jl")
include("read.jl")
include("write.jl")

end
