# The documentation's Julia examples run, and every export is documented.
#
# Each ```julia block of README.md, docs/guide/*.md and docs/julia.md
# runs, in order, in one module per file, in a fresh temporary
# directory. Blocks whose info string says `norun` (installation) are
# skipped. The docs live in the repository; outside a checkout this
# skips.

using DtaParser, Test

const DOCS_ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))
const DOCS_PAGE = joinpath(DOCS_ROOT, "docs", "julia.md")

function doc_files()
    guide = joinpath(DOCS_ROOT, "docs", "guide")
    [joinpath(DOCS_ROOT, "README.md"); sort(filter(endswith(".md"), readdir(guide; join=true))); DOCS_PAGE]
end

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
        @testset "examples in $(relpath(path, DOCS_ROOT)) run" for path in doc_files()
            blocks = code_blocks(path)
            isempty(blocks) && continue
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
            for name in names(DtaParser)
                name === :DtaParser && continue
                # Base.Docs.hasdoc needs Julia 1.11; this works on 1.10 too.
                @test haskey(Base.Docs.meta(DtaParser), Base.Docs.Binding(DtaParser, name))
                @test occursin("`$name", page) || occursin("$name(", page)
            end
        end
    end
else
    @info "docs/julia.md is not here; skipping the documentation checks"
end
