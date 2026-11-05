# The documentation's Julia examples run, and every export is documented.
#
# Every ```julia block of docs/julia.md runs, in order, in one module,
# in a fresh temporary directory: DtaParser's blocks and Datakit's
# (marked `julia datakit`, which DtaParser's own docs test skips), since
# the Datakit sections read the files the earlier ones write. Then
# julia/Datakit/README.md's blocks, the same way. Blocks whose info
# string says `norun` (installation) are skipped. The docs live in the
# repository; outside a checkout this skips.

using Datakit, Test

const DOCS_ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))
const DOCS_PAGE = joinpath(DOCS_ROOT, "docs", "julia.md")

"(line, code) of each julia block in a Markdown file."
function code_blocks(path)
    lines = split(read(path, String), '\n')
    out = Tuple{Int,String}[]
    i = 1
    while i <= length(lines)
        m = match(r"^(`{3,})\s*([A-Za-z]*)(.*)$", lines[i])
        if m === nothing
            i += 1
            continue
        end
        stop = i + 1
        while stop <= length(lines) && !startswith(lines[stop], m[1])
            stop += 1
        end
        if m[2] == "julia" && !occursin("norun", m[3])
            push!(out, (i, join(lines[i+1:stop-1], '\n')))
        end
        i = stop + 1
    end
    out
end

if isfile(DOCS_PAGE)
    @testset "docs" begin
        @testset "examples in $(relpath(path, DOCS_ROOT)) run" for path in
                (DOCS_PAGE, joinpath(DOCS_ROOT, "julia", "Datakit", "README.md"))
            blocks = code_blocks(path)
            @test !isempty(blocks)
            mod = Module(:DocExamples)
            Core.eval(mod, :(include(x) = Base.include($mod, x)))
            cd(mktempdir()) do
                for (line, code) in blocks
                    ok = try
                        redirect_stdout(devnull) do
                            include_string(mod, code, "$(basename(path)):$line")
                        end
                        true
                    catch e
                        @error "$(basename(path)):$line failed" exception = (e, catch_backtrace())
                        false
                    end
                    @test ok
                end
            end
        end

        @testset "every export has a docstring and appears in docs/julia.md" begin
            page = read(DOCS_PAGE, String)
            for name in names(Datakit)
                name === :Datakit && continue
                # The re-exports' docstrings are DtaParser's; Binding
                # resolves to the module that defines the name.
                b = Base.Docs.Binding(Datakit, name)
                @test haskey(Base.Docs.meta(b.mod), b)
                @test occursin("`$name", page) || occursin("$name(", page)
            end
        end
    end
else
    @info "docs/julia.md is not here; skipping the documentation checks"
end
