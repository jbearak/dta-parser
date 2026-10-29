# Build the native library (crates/dta-ffi) with cargo and copy it to
# deps/usr/lib, where DtaParser looks for it. CARGO names another cargo;
# CARGO_TARGET_DIR is honoured.

const repo = normpath(joinpath(@__DIR__, "..", "..", ".."))
const cargo = get(ENV, "CARGO", "cargo")
const name = Sys.iswindows() ? "dta_ffi.dll" : Sys.isapple() ? "libdta_ffi.dylib" : "libdta_ffi.so"

isfile(joinpath(repo, "crates", "dta-ffi", "Cargo.toml")) ||
    error("DtaParser builds from a checkout of dta-parser; $repo is not one")
run(`$cargo build --release -p dta-ffi --manifest-path $(joinpath(repo, "Cargo.toml"))`)
target = abspath(get(ENV, "CARGO_TARGET_DIR", joinpath(repo, "target")))
lib = joinpath(@__DIR__, "usr", "lib")
mkpath(lib)
cp(joinpath(target, "release", name), joinpath(lib, name); force=true)
