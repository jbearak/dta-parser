"""
    read_fixed_width(path, setup; recodes=:setup, cols=nothing, skip=0, n_max=nothing) -> DtaTable

Read a fixed-width text file through its SAS setup file: for data such
as the National Survey of Family Growth cycles of 1973 to 1995, which
CDC publishes as `.dat` files with a SAS setup file (`.sas`) each. The
setup gives each column's position (`INPUT`), label (`LABEL`), value
labels (`PROC FORMAT` and `FORMAT`), record-type selection
(`IF rec_type < 5 THEN DELETE; ELSE INPUT ...`) and missing-value
recodes (`IF (X = 98 OR X = 99) THEN X = .;`).

- `recodes`: what to do with the missing-value recodes. `:setup`
  applies them as written: a code recoded to `.` has `stata_code` 1,
  one recoded to `.A` has 2 (`.a`); both read as `missing`. `:tagged`
  keeps why each value is missing: per column, the codes recoded to `.`
  become `.a`, `.b`, ... (`stata_code` 2, 3, ...) in the order the setup
  names them, with their value labels on those letters. `:none` ignores
  them; the codes stay numbers.
- `cols`, `skip`, `n_max`: as in [`read_dta`](@ref); `skip` and `n_max`
  apply after the whole file is read.

Columns are as `read_dta` returns them; numeric columns take the
smallest storage type that holds their values. Statements the reader
does not run (other data-step code, ranges in `VALUE`) give one warning;
table metadata `"warnings"` lists them all.
"""
function read_fixed_width(path::AbstractString, setup::AbstractString; recodes::Symbol=:setup, cols=nothing,
                          skip::Integer=0, n_max::Union{Nothing,Integer}=nothing)
    recodes in (:setup, :tagged, :none) ||
        throw(ArgumentError("recodes must be :setup, :tagged or :none, not :$recodes"))
    isfile(path) || throw(ArgumentError("no such file: $path"))
    isfile(setup) || throw(ArgumentError("no such file: $setup"))
    dir = mktempdir(; cleanup=false)
    try
        out = joinpath(dir, "data.dta")
        err = zeros(UInt8, ERR_LEN)
        len = Ref{Csize_t}(0)
        s = ccall(fn(:dta_fixed_width_to_dta), Ptr{UInt8},
                  (Cstring, Cstring, Cstring, Cstring, Ref{Csize_t}, Ptr{UInt8}, Csize_t),
                  String(path), String(setup), out, String(recodes), len, err, ERR_LEN)
        s == C_NULL && throw(DtaError(error_text(err)))
        messages = try
            Vector{String}(parse_json(unsafe_string(s, len[])))
        finally
            ccall(fn(:dta_string_free), Cvoid, (Ptr{UInt8},), s)
        end
        t = read_dta(out; cols=cols, skip=skip, n_max=n_max, dates=false)
        if !isempty(messages)
            getfield(t, :meta)["warnings"] = messages
            shown = [length(m) <= 100 ? m : first(m, 97) * "..." for m in messages[1:min(8, end)]]
            length(messages) > 8 && push!(shown, "$(length(messages) - 8) more; see metadata(t, \"warnings\")")
            @warn "The setup file was read with warnings:\n" * join(("* " * m for m in shown), "\n")
        end
        t
    finally
        rm(dir; recursive=true, force=true)
    end
end
