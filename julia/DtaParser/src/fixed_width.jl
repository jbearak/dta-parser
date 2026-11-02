"""
    read_fixed_width(path, setup; recodes=:setup, cols=nothing, skip=0, n_max=nothing,
                     commented_formats=true) -> DtaTable

Read a fixed-width text file through its SAS setup file: for data such
as the National Survey of Family Growth files of 1973 to 2017-2019,
which CDC publishes as `.dat` files with a SAS setup file (`.sas`) each.
The setup gives each column's position (`INPUT`), label (`LABEL`), value
labels (`PROC FORMAT` and `FORMAT`), record-type selection
(`IF rec_type < 5 THEN DELETE; ELSE INPUT ...`) and missing-value
recodes (`IF (X = 98 OR X = 99) THEN X = .;`).

- `setup`: the path to the setup file, or a vector of paths read in
  order as one setup, such as CDC's 2002 files `["2002FemPregInput.sas",
  "2002FemPregVarLabel.sas", "2002FemPregValueLabel.sas"]`. A statement
  may not run from one file into the next. With several, errors and
  warnings name a file by its place in the vector (`"file 2 line 8"`).
- `recodes`: what to do with the missing-value recodes. `:setup`
  applies them as written: a code recoded to `.` has `stata_code` 1,
  one recoded to `.A` has 2 (`.a`); both read as `missing`. `:tagged`
  keeps why each value is missing: per column, the codes recoded to `.`
  become `.a`, `.b`, ... (`stata_code` 2, 3, ...) in the order the setup
  names them, with their value labels on those letters. `:none` ignores
  them; the codes stay numbers.
- `cols`, `skip`, `n_max`: as in [`read_dta`](@ref); `skip` and `n_max`
  apply after the whole file is read.
- `commented_formats`: whether to read a `PROC FORMAT` step or a
  `FORMAT` statement that the setup has put in a block comment
  (`/* ... */`) as code. CDC's setups from 2006-2010 on comment both out
  so that SAS users without CDC's format catalog can run the file as
  published; the value labels are still there, so this is `true` by
  default. Only a comment that holds nothing but such a step or
  statement is read; one that mentions `PROC FORMAT` in prose stays a
  comment. `false` reads every comment as a comment, so those files have
  no value labels.

Columns are as `read_dta` returns them; numeric columns take the
smallest storage type that holds their values. Statements the reader
does not run (other data-step code, ranges in `VALUE`) give one warning;
table metadata `"warnings"` lists them all. A variable label with stray
quotes inside it, such as `X = "WHETHER " SAME AS LAST MONTH" WAS
ANSWERED"` in CDC's 2011-2013 to 2015-2017 setups, is read from its
first quote to its last, with a warning naming its line.
"""
function read_fixed_width(path::AbstractString, setup::Union{AbstractString,AbstractVector{<:AbstractString}};
                          recodes::Symbol=:setup, cols=nothing, skip::Integer=0,
                          n_max::Union{Nothing,Integer}=nothing, commented_formats::Bool=true)
    recodes in (:setup, :tagged, :none) ||
        throw(ArgumentError("recodes must be :setup, :tagged or :none, not :$recodes"))
    setups = setup isa AbstractString ? [String(setup)] : String.(setup)
    isempty(setups) && throw(ArgumentError("setup must be one or more paths"))
    isfile(path) || throw(ArgumentError("no such file: $path"))
    for s in setups
        isfile(s) || throw(ArgumentError("no such file: $s"))
    end
    dir = mktempdir(; cleanup=false)
    try
        out = joinpath(dir, "data.dta")
        err = zeros(UInt8, ERR_LEN)
        len = Ref{Csize_t}(0)
        s = ccall(fn(:dta_fixed_width_to_dta), Ptr{UInt8},
                  (Cstring, Ptr{Cstring}, Csize_t, Cstring, Cstring, Cint, Ref{Csize_t}, Ptr{UInt8}, Csize_t),
                  String(path), setups, length(setups), out, String(recodes), commented_formats, len, err, ERR_LEN)
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
