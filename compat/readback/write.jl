# Save every input again with DtaParser's read_dta and write_dta, for
# compat/readback/check.py to read with other readers. Inputs are the
# fixtures in compat/fixtures, and strls.dta and binary.dta in
# compat/readback.
#   julia --project=julia/DtaParser compat/readback/write.jl <out-dir>
using DtaParser

out = ARGS[1]
mkpath(out)
fixtures = filter(endswith(".dta"), readdir(joinpath("compat", "fixtures"); join=true))
for path in vcat(sort(fixtures), [joinpath("compat", "readback", f) for f in ("strls.dta", "binary.dta")])
    write_dta(joinpath(out, basename(path)), read_dta(path))
end
