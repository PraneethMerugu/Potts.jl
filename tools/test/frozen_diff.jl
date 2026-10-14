# Tests for tools/frozen_diff.jl (D-250): each kind it lets through, and a negative control
# for every way a re-freeze could weaken a test while looking harmless, including every
# exploit from the first adversarial review (A1–A28, C1–C5, H1, M1).
#   julia --project=lib/PottsModels/test tools/test/frozen_diff.jl
using Test
include(joinpath(@__DIR__, "..", "frozen_diff.jl"))

const BASE = """
const TOL = 0.05
const P_IR = Dict("GG" => "aaaa1111", "cubes" => "bbbb2222")
const CASES = [:a, :b]
helper(x) = 2x
function within(a, b)
    d = abs(a - b)
    d <= TOL
end
\"\"\"Docstring for check.\"\"\"
check(x) = x > 0
page = md"| a | value |"
table = Markdown.parse(\"\"\"
| a | \$(helper(1)) | value |
\"\"\")
# Prose comment.
# ```jldoctest
# julia> helper(1)
# 2
# ```
@testset "first group" begin
    y = helper(3)
    @test y == 6
    @test within(y, 6.0)
    @test isapprox(y, 6; atol = TOL)
    println("progress: done")
    println(io_check("targets_strict.toml"))
    @info "ran" r = run_check(:strict, "paper")
end
@testset "cases \$c" for c in CASES
    @test c isa Symbol
    @test check(1)
end
open(f -> println(f, "const LIMIT = 1"), "gen.jl", "w")
"""

# `fresh`: the names the caller would find nowhere in the repository (main computes it)
cls(new; pins = Symbol[], fresh = Symbol[], old = BASE) = classify("x.jl", old, new, Set(pins); fresh = Set(fresh))
verdict(new; kw...) = cls(new; kw...)[1]
kinds(new; kw...) = cls(new; kw...)[2]
r(a, b) = (s = replace(BASE, a => b); s == BASE && error("pattern not found: $a"); s)
ins_top(s) = r("@testset \"first group\"", s * "\n@testset \"first group\"")
ins_inner(s) = r("    @test y == 6\n", "    @test y == 6\n    " * s * "\n")
append(s) = BASE * "\n" * s * "\n"

# a negative control must change the source, or it would pass vacuously
neg(new; kw...) = (new != BASE || error("negative control does not change the source"); verdict(new; kw...))

@testset "frozen_diff: what passes" begin
    @test verdict(BASE) === :auto
    @test kinds(BASE) == Set([:comments])
    @test kinds(r("# Prose comment.", "# Better prose, (p.11).")) == Set([:comments])
    @test kinds(replace(BASE, "\n" => "\r\n")) == Set([:comments])
    @test kinds(r("\"first group\"", "\"first group, renamed\"")) == Set([:wording])
    @test kinds(r("Docstring for", "Better docstring for")) == Set([:wording])
    @test kinds(r("progress: done", "progress: finished")) == Set([:wording])
    @test kinds(r("\$(helper(1)) | value |", "\$(helper(1)) | value (p.11) |")) == Set([:wording])
    @test kinds(append("@testset \"new\" begin\n    z = helper(4)\n    @test z == 8\nend")) == Set([:additive])
    @test kinds(ins_inner("@test y > 0")) == Set([:additive])
    @test kinds(ins_inner("@test isapprox(y, 6.0, atol = 0.1)")) == Set([:additive])
    @test kinds(ins_inner("@test y ≈ 6 atol = 0.1")) == Set([:additive])
    @test kinds(ins_inner("@test_throws ArgumentError helper(\"x\")")) == Set([:additive])
    # a new testset may use locals, local functions, closures and the library under test
    t = """@testset "new" begin
        σ, frame = helper(1), helper(2)
        inh = Dict(id => isodd(id) for id in unique(filter(>(0), [σ, frame])))
        ax() = Makie.Axis(Makie.Figure()[1, 1])
        @test PottsModels.openvt_colony_panel!(ax(), frame; color = :area) !== nothing
        v = Int[]
        push!(v, 1)
        @test_deprecated PottsModels.old_name(1)
        @test v == [1] && occursin(r"a+", "aa") && v"1.2" < v"1.3"
    end"""
    @test kinds(append(t)) == Set([:additive])
    # a new function whose name the repository has never used
    @test kinds(append("brand_new_helper(x) = 3x\n@testset \"n\" begin\n    @test brand_new_helper(1) == 3\nend");
                fresh = [:brand_new_helper]) == Set([:additive])
    @test kinds(r("\"aaaa1111\"", "\"cccc3333\""); pins = [:P_IR]) == Set([:pin])
end

@testset "frozen_diff: negative controls (each needs the maintainer)" begin
    # targets, tolerances, expectations
    @test neg(r("0.05", "0.5")) === :maintainer
    @test neg(r("y == 6", "y == 7")) === :maintainer
    @test neg(r("y == 6", "y >= 6")) === :maintainer
    @test neg(r("atol = TOL", "atol = 10TOL")) === :maintainer
    @test neg(r("x > 0", "x >= 0")) === :maintainer
    # removing, skipping, reordering
    @test neg(r("    @test y == 6\n", "")) === :maintainer
    @test neg(r("@test y == 6", "@test_skip y == 6")) === :maintainer
    @test neg(r("@test y == 6", "@test_broken y == 6")) === :maintainer
    @test neg(r("    @test y == 6\n    @test within(y, 6.0)\n", "    @test within(y, 6.0)\n    @test y == 6\n")) === :maintainer
    @test neg(r("[:a, :b]", "[:a, :b, :c]")) === :maintainer                         # widen a list
    @test neg(r("[:a, :b]", "[:a]")) === :maintainer
    # strings that are code (C5, A11–A16): nested in a prose call, string macros, file writers
    @test neg(r("targets_strict.toml", "targets_loose.toml")) === :maintainer
    @test neg(r("\"paper\"", "\"fast\"")) === :maintainer
    @test neg(r("const LIMIT = 1", "const LIMIT = 0.6")) === :maintainer
    @test neg(r("md\"| a | value |\"", "md\"| a | value (p.11) |\"")) === :maintainer
    @test neg(r("md\"| a | value |\"", "md\"| a | \$(empty!(CASES)) |\"")) === :maintainer
    @test neg(r("\$(helper(1))", "\$(helper(2))")) === :maintainer                  # prose interpolation
    @test neg(r("\"cases \$c\"", "\"cases \$(empty!(CASES))\"")) === :maintainer
    # executable Documenter blocks in comments and docstrings (M1)
    @test neg(r("# julia> helper(1)\n# 2", "# julia> helper(1)\n# 3")) === :maintainer
    @test neg(r("\"\"\"Docstring for check.\"\"\"", "\"\"\"\n```jldoctest\njulia> 1\n1\n```\n\"\"\"")) === :maintainer
    # pins: undeclared, a key, structure, a different constant
    @test neg(r("\"aaaa1111\"", "\"cccc3333\"")) === :maintainer
    @test neg(r("\"GG\" =>", "\"GG2\" =>"); pins = [:P_IR]) === :maintainer
    @test neg(r(", \"cubes\" => \"bbbb2222\"", ""); pins = [:P_IR]) === :maintainer
    @test neg(r("0.05", "0.5"); pins = [:P_IR]) === :maintainer
    # insertions into function bodies change what the old tests see (A3–A5, C2)
    @test neg(r("    d <= TOL\nend", "    d <= TOL\n    @inferred identity(true)\nend")) === :maintainer
    @test neg(r("    d = abs(a - b)\n", "    @assert (return true)\n    d = abs(a - b)\n")) === :maintainer
    @test neg(r("    d <= TOL\nend", "    d <= TOL\n    @test_nowarn true\nend")) === :maintainer
    @test neg(r("    @test c isa Symbol\n", "    @assert (break; true)\n    @test c isa Symbol\n")) === :maintainer
    # lines added to an existing testset: only @test / @test_throws, no assignment (A9, A10, A23, A24)
    @test neg(ins_inner("@test (g = pop!; g(CASES); true)")) === :maintainer
    @test neg(ins_inner("@test (s = setindex!; s(P_IR, \"z\", \"GG\"); true)")) === :maintainer
    @test neg(ins_inner("@test (y = 6; true)")) === :maintainer
    @test neg(ins_inner("@test_skip y == 7")) === :maintainer
    @test neg(ins_inner("@test_nowarn true")) === :maintainer
    @test neg(ins_inner("y = 6")) === :maintainer
    @test neg(ins_inner("@test (break; true)")) === :maintainer
    @test neg(ins_inner("@test (return true)")) === :maintainer
    # top-level insertions other than a testset or a new function (A2, A6–A8, A16, A18–A22, A25, A26)
    for s in ["const _BOOT = Base.exit(0)", "const _X = CASES |> empty!", "const _X = foreach(empty!, (CASES,))",
              "const _X = empty!.((CASES,))", "const _P = md\"\$(empty!(CASES))\"", "macro test(ex)\n    :(true)\nend",
              "const _E = getfield(Core, :eval)(Main, :(TOL = 1.0))", "const _E = Base.@eval(Main, nothing)",
              "const _I = Base.include(Main, \"evil.jl\")", "const _R = run(`true`)", "const _E = Main.eval(:(TOL = 1.0))",
              "const _W = (within = nothing)", "TOL = 1.0", "global TOL = 1.0", "include(\"other.jl\")", "using Random",
              "Random.seed!(1)", "exit(0)", "helper(x::Int) = 6", "Base.isapprox(a, b; kw...) = true",
              "struct NewType end", "module M end", "@eval check(x) = true"]
        @test neg(ins_top(s); fresh = [:_BOOT, :_X, :_P, :_E, :_I, :_R, :_W, :NewType, :M]) === :maintainer
    end
    # inside a new testset (C1, C3, A1, A27)
    for body in ["exit(0)", "Base.exit(0)", "quit()", "run(`true`)", "cd(\"..\")", "rm(\"x.jl\")", "Random.seed!(1)",
                 "empty!(CASES)", "push!(CASES, :c)", "CASES |> empty!", "foreach(empty!, (CASES,))", "empty!.((CASES,))",
                 "g = pop!; g(CASES)", "P_IR[\"GG\"] = \"z\"", "global TOL = 1", "TOL2 = getfield(Core, :eval)",
                 "Main.eval(:(TOL = 1))", "Core.eval(Main, :(TOL = 1))", "eval(:(TOL = 1))", "include(\"evil.jl\")",
                 "Base.include(Main, \"evil.jl\")", "@eval TOL = 1", "invokelatest(exit, 0)", "Base.setindex!(P_IR, \"z\", \"GG\")",
                 "empty!(Test.get_testset().results)", "ENV[\"X\"] = \"1\"", "x = md\"\$(empty!(CASES))\"", "x = :(a + b)",
                 "try\n        exit(0)\n    catch\n    end", "f = exit; f(0)", "setindex!(P_IR, \"z\", \"GG\")", "(exit)(0)",
                 "open(\"x\", \"w\") do io\n        write(io, \"x\")\n    end", "@test (return true)"]
        @test neg(append("@testset \"t\" begin\n    " * body * "\n    @test true\nend")) === :maintainer
    end
    # a new function: the name must be new to the whole repository (H1), its body is checked
    @test neg(append("akeeb_metrics(args...; kw...) = (; ok = true)")) === :maintainer       # not fresh
    @test neg(append("isapprox(a, b) = true"); fresh = [:isapprox]) === :maintainer          # bound in Base
    @test neg(append("brand_new(x) = empty!(CASES)"); fresh = [:brand_new]) === :maintainer
    @test neg(append("brand_new(x = exit(0)) = x"); fresh = [:brand_new]) === :maintainer   # default value
    @test neg(append("brand_new(x) = 1\nbrand_new(x::Int) = 2"); fresh = [:brand_new]) === :maintainer
    @test neg(r("check(x) = x > 0", "check(x) = x > 0\n\"\"\"doc\"\"\"\ncheck2(x) = 1")) === :maintainer   # not declared fresh
    # files and formats
    @test classify("x.jl", BASE, nothing, Set{Symbol}())[1] === :maintainer
    @test classify("x.tsv", "a\t1\n", "a\t1 \n", Set{Symbol}())[1] === :maintainer
    @test neg(append("@testset \"broken\" begin")) === :maintainer
    @test neg(r("\"first group\"", "\"first group \$(TOL)\"")) === :maintainer               # name gains code
end

@testset "frozen_diff: recorded re-freezes from the history" begin
    # (commit, file under lib/PottsModels/test, expected verdict, pins)
    cases = [
        ("ba0beaba", "../reproductions/10_akeeb.jl", :auto, Symbol[]),                    # D-241 wording
        ("0e2863ed", "reproductions/15_openvt_f1_f4.jl", :auto, Symbol[]),                # D-249 appended testset
        ("3e0233ce", "acceptance/p6_0bk2_skip_interior.jl", :auto, [:P60BK2_IR]),         # D-237 IR re-pin, if declared
        ("3e0233ce", "acceptance/p6_0bk2_skip_interior.jl", :maintainer, Symbol[]),       # ... and if not
        ("3e0233ce", "acceptance/p6_0p_cadence_fingerprint.jl", :maintainer, Symbol[]),   # output fingerprint
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
            @test_skip false     # a shallow clone without this history
            continue
        end
        @test classify(p, old, new, Set(pins))[1] === want
    end
end
