# Tests for tools/frozen_diff.jl (D-250): each kind it lets through, and a negative control
# for every way a re-freeze could weaken a test while looking harmless.
#   julia --project=lib/PottsModels/test tools/test/frozen_diff.jl
using Test
include(joinpath(@__DIR__, "..", "frozen_diff.jl"))

verdict(old, new; pins = Symbol[]) = classify("x.jl", old, new, Set(pins))[1]
kinds(old, new; pins = Symbol[]) = classify("x.jl", old, new, Set(pins))[2]

const BASE = """
const TOL = 0.05
const P_IR = Dict("GG" => "aaaa1111", "cubes" => "bbbb2222")
const CASES = [:a, :b]
helper(x) = 2x
\"\"\"Docstring for check.\"\"\"
check(x) = x > 0
@testset "first group" begin
    y = helper(3)
    @test y == 6
    @test isapprox(y, 6; atol = TOL)
    @test occursin("needle", "haystack with needle")
    println("progress: done")
end
@testset "cases \$c" for c in CASES
    @test c isa Symbol
end
page = Markdown.parse(\"\"\"
| a | \$(helper(1)) | value |
\"\"\")
"""

@testset "frozen_diff: what passes" begin
    @test verdict(BASE, BASE) === :auto
    @test kinds(BASE, BASE) == Set([:comments])
    @test verdict(BASE, replace(BASE, "const TOL" => "# tolerance (D-1)\nconst TOL")) === :auto       # comment
    @test verdict(BASE, replace(BASE, "\"first group\"" => "\"first group, renamed\"")) === :auto     # testset name
    @test kinds(BASE, replace(BASE, "Docstring for" => "Better docstring for")) == Set([:wording])
    @test verdict(BASE, replace(BASE, "progress: done" => "progress: finished")) === :auto
    @test verdict(BASE, replace(BASE, "| value |" => "| value (p.11) |")) === :auto                   # page prose
    added = BASE * "\n@testset \"new\" begin\n    z = helper(4)\n    @test z == 8\nend\n"
    @test kinds(BASE, added) == Set([:additive])
    fresh = BASE * "\nnew_helper(x) = 3x\n@testset \"new\" begin\n    @test new_helper(1) == 3\nend\n"
    @test verdict(BASE, fresh) === :auto
    inner = replace(BASE, "    @test y == 6\n" => "    @test y == 6\n    @test y > 0\n")
    @test kinds(BASE, inner) == Set([:additive])                                                    # new @test line
    pinned = replace(BASE, "\"aaaa1111\"" => "\"cccc3333\"")
    @test verdict(BASE, pinned; pins = [:P_IR]) === :auto
    @test kinds(BASE, pinned; pins = [:P_IR]) == Set([:pin])
end

# a negative control must actually change the source, or it would pass vacuously
neg(old, new; kw...) = (new != old || error("negative control does not change the source"); verdict(old, new; kw...))

@testset "frozen_diff: negative controls (each needs the maintainer)" begin
    # targets, tolerances and expectations
    @test neg(BASE, replace(BASE, "0.05" => "0.5")) === :maintainer
    @test neg(BASE, replace(BASE, "y == 6" => "y == 7")) === :maintainer
    @test neg(BASE, replace(BASE, "y == 6" => "y >= 6")) === :maintainer
    @test neg(BASE, replace(BASE, "\"needle\"" => "\"need\"")) === :maintainer                  # string in @test
    @test neg(BASE, replace(BASE, "atol = TOL" => "atol = 10TOL")) === :maintainer
    # removing or skipping tests
    @test neg(BASE, replace(BASE, "    @test y == 6\n" => "")) === :maintainer
    @test neg(BASE, replace(BASE, "@test y == 6" => "@test_skip y == 6")) === :maintainer
    @test neg(BASE, replace(BASE, "@test y == 6" => "@test_broken y == 6")) === :maintainer
    # widening a list or a mapping
    @test neg(BASE, replace(BASE, "[:a, :b]" => "[:a, :b, :c]")) === :maintainer
    @test neg(BASE, replace(BASE, "[:a, :b]" => "[:a]")) === :maintainer
    # pins: undeclared, a key, or structure
    pinned = replace(BASE, "\"aaaa1111\"" => "\"cccc3333\"")
    @test neg(BASE, pinned) === :maintainer
    @test neg(BASE, replace(BASE, "\"GG\" =>" => "\"GG2\" =>"); pins = [:P_IR]) === :maintainer
    @test neg(BASE, replace(BASE, ", \"cubes\" => \"bbbb2222\"" => ""); pins = [:P_IR]) === :maintainer
    @test neg(BASE, replace(BASE, "0.05" => "0.5"); pins = [:P_IR]) === :maintainer          # pins are per constant
    # prose with a changed interpolation
    @test neg(BASE, replace(BASE, "\$(helper(1))" => "\$(helper(2))")) === :maintainer
    # insertions that change what the old tests see
    @test neg(BASE, BASE * "\nconst TOL2 = 1\nTOL = 1.0\n") === :maintainer                    # reassign
    @test neg(BASE, BASE * "\nhelper(x::Int) = 6\n") === :maintainer                           # method extension
    @test neg(BASE, BASE * "\nBase.isapprox(a, b; kw...) = true\n") === :maintainer             # qualified method
    @test neg(BASE, BASE * "\n@testset \"x\" begin\n    push!(CASES, :c)\nend\n") === :maintainer
    @test neg(BASE, BASE * "\n@testset \"x\" begin\n    P_IR[\"GG\"] = \"z\"\nend\n") === :maintainer
    @test neg(BASE, BASE * "\n@testset \"x\" begin\n    global TOL = 1\nend\n") === :maintainer
    @test neg(BASE, BASE * "\n@eval check(x) = true\n") === :maintainer
    @test neg(BASE, BASE * "\ninclude(\"other.jl\")\n") === :maintainer
    @test neg(BASE, BASE * "\nusing Random\n") === :maintainer
    @test neg(BASE, BASE * "\nRandom.seed!(1)\n") === :maintainer                               # bare top-level call
    @test neg(BASE, replace(BASE, "    y = helper(3)\n" => "    y = helper(3)\n    y = 6\n")) === :maintainer
    # moved statements, files and formats
    @test neg(BASE, replace(BASE, "    @test y == 6\n    @test isapprox(y, 6; atol = TOL)\n" =>
                                      "    @test isapprox(y, 6; atol = TOL)\n    @test y == 6\n")) === :maintainer
    @test classify("x.jl", BASE, nothing, Set{Symbol}())[1] === :maintainer
    @test classify("x.tsv", "a\t1\n", "a\t1 \n", Set{Symbol}())[1] === :maintainer
    @test neg(BASE, BASE * "\n@testset \"broken\" begin\n") === :maintainer                    # parse error
end

@testset "frozen_diff: recorded re-freezes from the history" begin
    # each pair is (commit, file under lib/PottsModels/test, expected verdict, pins)
    cases = [
        ("ba0beaba", "../reproductions/10_akeeb.jl", :auto, Symbol[]),                    # D-241 wording
        ("0e2863ed", "reproductions/15_openvt_f1_f4.jl", :auto, Symbol[]),                # D-249 appended testset
        ("3e0233ce", "acceptance/p6_0bk2_skip_interior.jl", :auto, [:P60BK2_IR]),         # D-237 IR re-pin, if declared
        ("3e0233ce", "acceptance/p6_0bk2_skip_interior.jl", :maintainer, Symbol[]),       # ... and if not
        ("b373ef5e", "acceptance/p6_0v1_device_lifecycle.jl", :maintainer, Symbol[]),     # D-238 mapping entry
        ("7de7e488", "acceptance/p6_5b_convert.jl", :maintainer, Symbol[]),               # P6.5b fixture-order fix
        ("63b0c0d7", "acceptance/p6_5a2_ref_helpers.jl", :maintainer, Symbol[]),          # P6.5a2 one-line fix
        ("ff993a45", "reproductions/09_cell_sorting.jl", :maintainer, Symbol[]),          # D-239 targets
        ("1c9c0bb9", "reproductions/01_merks.jl", :maintainer, Symbol[]),                 # D-240 targets
        ("84485560", "acceptance/p6_5a_cell_refs.jl", :maintainer, Symbol[]),             # D-231 swapped expectations
    ]
    root = normpath(joinpath(@__DIR__, "..", ".."))
    for (c, f, want, pins) in cases
        p = normpath(joinpath(TESTDIR, f))
        old, new = cd(() -> (gitshow("$c^", p), gitshow(c, p)), root)
        if old === nothing || new === nothing
            @test_skip false     # shallow clone without this history
            continue
        end
        @test classify(p, old, new, Set(pins))[1] === want
    end
end
