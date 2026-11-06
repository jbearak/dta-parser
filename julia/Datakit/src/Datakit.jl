"""
Data preparation in Julia: Parquet files and
fixed-width text read into DataFrames, keeping Stata's labels and its
missing values `.a` to `.z`.

[`read_parquet`](@ref) and [`read_fixed_width`](@ref) return a
`DataFrames.DataFrame`, its labels in `metadata` and `colmetadata`
(style `:note`); a column holding `.a` to `.z` is a [`DtaColumn`](@ref).
[`save_parquet`](@ref) writes any Tables.jl table, and
[`read_parquet_info`](@ref) reads a file's footer. `.dta` files are
DtaParser's: `DataFrame(read_dta(path))` gives the same kind of frame.
See docs/julia.md, "Parquet files".
"""
module Datakit

using Dates
using DataFrames
import DataAPI
import Tables
using DtaParser: DtaParser, DtaColumn, DtaTable, stata_code, set_stata_code!, dta_key, read_dta, read_meta, write_dta
using DtaParser.Internals

# DtaParser's exports too, so `using Datakit` alone reads and writes .dta.
export read_parquet, read_parquet_info, save_parquet, read_fixed_width, DtaColumn, stata_code, set_stata_code!,
       dta_key, read_dta, read_meta, write_dta, DtaTable

# The version of DtaParser's C interface this package was written for.
const DTAPARSER_ABI = 5

function abi_message(found)
    "Datakit $(pkgversion(@__MODULE__)) needs DtaParser's library interface version $DTAPARSER_ABI, but the " *
    "DtaParser loaded ($(pkgversion(DtaParser)), at $(pkgdir(DtaParser))) has version $found. Install both " *
    "from the same checkout: `import Pkg; Pkg.develop(path=\"julia/DtaParser\"); " *
    "Pkg.develop(path=\"julia/Datakit\"); Pkg.build(\"DtaParser\")`, then restart Julia."
end

check_abi(found=Internals.ABI_VERSION) = found == DTAPARSER_ABI || error(abi_message(found))

function __init__()
    check_abi()
end

include("frame.jl")
include("parquet.jl")
include("parquet_write.jl")
include("fixed_width.jl")
include("precompile.jl")

end
