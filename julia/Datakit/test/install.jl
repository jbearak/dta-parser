# Installing from a checkout, as docs/julia.md says: in a fresh depot and
# a new environment, develop DtaParser, then Datakit, build DtaParser's
# library, add DataFrames, load Datakit and read back a file it saved.
# Needs the network (the General registry and Datakit's dependencies)
# and cargo.
#
#     julia julia/Datakit/test/install.jl
#
# Exits with status 1 if any step fails. Not part of runtests.jl, since
# it downloads packages into a new depot; CI runs it as its own step.

const REPO = normpath(joinpath(@__DIR__, "..", "..", ".."))

depot = mktempdir()
env = mktempdir()
code = """
import Pkg
Pkg.activate($(repr(env)))
Pkg.develop(path=$(repr(joinpath(REPO, "julia", "DtaParser"))))
Pkg.develop(path=$(repr(joinpath(REPO, "julia", "Datakit"))))
Pkg.build("DtaParser")
Pkg.add("DataFrames")
using Datakit, DataFrames
p = tempname() * ".parquet"
save_parquet(p, DataFrame(x = DtaColumn([1.5, 0.0], UInt8[0, 2])); column_labels = Dict(:x => "X"))
df = read_parquet(p)
df.x isa DtaColumn && stata_code(df.x, 2) == 2 && colmetadata(df, :x, "label") == "X" ||
    error("the file did not read back")
println("installed in a fresh depot: Datakit ", pkgversion(Datakit), ", DtaParser ", pkgversion(Datakit.DtaParser),
        ", DataFrames ", pkgversion(DataFrames), ", Julia ", VERSION)
"""
# The depot first, then Julia's own (the trailing separator), so that
# nothing comes from the user's depot.
sep = Sys.iswindows() ? ";" : ":"
cmd = addenv(`$(Base.julia_cmd()) --startup-file=no -e $code`, "JULIA_DEPOT_PATH" => depot * sep,
             "JULIA_PROJECT" => nothing, "JULIA_LOAD_PATH" => nothing)
ok = success(pipeline(cmd; stdout=stdout, stderr=stderr))
rm(depot; recursive=true, force=true)
rm(env; recursive=true, force=true)
ok || exit(1)
