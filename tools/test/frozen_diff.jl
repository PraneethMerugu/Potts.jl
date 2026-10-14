# Tests for tools/frozen_diff.jl (D-250, re-pins only): the one kind it lets through, negative
# controls for everything else, the command line end to end in a scratch repository, and the
# recorded re-freezes from the history.
#   julia --project=lib/PottsModels/test tools/test/frozen_diff.jl
using Test
const TOOL = normpath(joinpath(@__DIR__, "..", "frozen_diff.jl"))
include(TOOL)

const BASE = """
# A frozen acceptance file.
const P_IR_VERSION = v"1.12.6"
const P_IR = Dict(
    "GG" => "aaaa1111",
    "cubes" => "bbbb2222",
)
const P_N = Dict("GG" => 7)
const TOL = 0.05
helper(x) = 2x
@testset "first group" begin
    @test helper(3) == 6
    @test P_IR["GG"] isa String
end
"""
const PINS = Set([:P_IR])
verdict(new; pins = PINS, old = BASE) = classify("x.jl", old, new, pins)[1]
r(a, b; src = BASE) = (s = replace(src, a => b); s == src && error("pattern not found: $a"); s)
neg(new; kw...) = (new != BASE || error("negative control does not change the source"); verdict(new; kw...))

@testset "frozen_diff: what passes" begin
    @test verdict(BASE) === :auto
    @test verdict(r("\"aaaa1111\"", "\"cccc3333\"")) === :auto
    @test verdict(r("\"aaaa1111\",", "\"cccc3333\",   # re-pinned under D-x")) === :auto       # comment on a pin line
    @test verdict(r("\"bbbb2222\"", "\"dddd4444\""; src = r("\"aaaa1111\"", "\"cccc3333\""))) === :auto
    @test verdict(replace(r("\"aaaa1111\"", "\"cccc3333\""), "\n" => "\r\n")) === :auto
end

@testset "frozen_diff: negative controls (each needs the maintainer)" begin
    # outside the declared constants nothing may change, comments included (M3: Literate pages)
    @test neg(r("# A frozen", "# The frozen")) === :maintainer
    @test neg(r("helper(x) = 2x", "helper(x) = 2x #src")) === :maintainer
    @test neg(r("\"first group\"", "\"first group, renamed\"")) === :maintainer
    @test neg(r("0.05", "0.5")) === :maintainer
    @test neg(r("helper(3) == 6", "helper(3) >= 6")) === :maintainer
    @test neg(BASE * "@testset \"new\" begin\n    @test true\nend\n") === :maintainer
    @test neg(r("    @test helper(3) == 6\n", "")) === :maintainer
    @test neg(r("    @test helper(3) == 6\n    @test P_IR[\"GG\"] isa String\n",
                "    @test P_IR[\"GG\"] isa String\n    @test helper(3) == 6\n")) === :maintainer
    # inside a pinned constant: only String literals
    @test neg(r("\"GG\" =>", "\"GG2\" =>")) === :maintainer                                   # a key
    @test neg(r("    \"cubes\" => \"bbbb2222\",\n", "")) === :maintainer                       # an entry
    @test neg(r("\"bbbb2222\",\n", "\"bbbb2222\",\n    \"new\" => \"eeee5555\",\n")) === :maintainer
    @test neg(r("\"aaaa1111\"", "\"aa\$(helper(1))\"")) === :maintainer                       # interpolation
    @test neg(r("\"aaaa1111\"", "helper(1)")) === :maintainer                                  # a call
    @test neg(r("const P_IR = Dict(", "const P_IR = Base.ImmutableDict(")) === :maintainer
    @test neg(r("0.05", "0.5"; src = r("\"aaaa1111\"", "\"cccc3333\""))) === :maintainer
    # pins: undeclared, numbers, string macros, a different constant
    @test neg(r("\"aaaa1111\"", "\"cccc3333\""); pins = Set{Symbol}()) === :maintainer
    @test neg(r("\"GG\" => 7", "\"GG\" => 8"); pins = Set([:P_N])) === :maintainer             # Int pins
    @test neg(r("\"GG\" => 7", "\"GG\" => 7.0"); pins = Set([:P_N])) === :maintainer
    @test neg(r("v\"1.12.6\"", "v\"1.12.7\""); pins = Set([:P_IR, :P_IR_VERSION])) === :maintainer
    @test neg(r("const P_IR =", "const P_IR2 =")) === :maintainer
    @test neg(r("const P_IR = Dict(", "P_IR = Dict(")) === :maintainer                         # no longer const
    # files
    @test classify("x.jl", BASE, nothing, PINS)[1] === :maintainer
    @test classify("x.tsv", "a\t1\n", "a\t2\n", PINS)[1] === :maintainer
    @test neg(BASE * "@testset \"broken\" begin\n") === :maintainer
    @test_throws ToolError classify("x.jl", BASE, r("helper(3) == 6", "helper(3 == 6"), PINS)   # never AUTO
end

# The command line, end to end: a scratch repository with the tool at the base.
git!(args...) = Base.run(pipeline(`git $args`; stdout = devnull, stderr = devnull))
head() = readchomp(`git rev-parse HEAD`)
function commit!(path, content)
    write(path, content)
    git!("add", "-A")
    git!("commit", "-qm", "c")
    return head()
end
function cli(base, cand = nothing; tool = nothing)
    t = tool
    if t === nothing
        t = tempname() * ".jl"
        write(t, read(`git show $base:tools/frozen_diff.jl`, String))
    end
    out = IOBuffer()
    c = cand === nothing ? String[] : [cand]
    p = Base.run(pipeline(ignorestatus(`$(Base.julia_cmd()) --startup-file=no $t $base $c`); stdout = out, stderr = out))
    return p.exitcode, String(take!(out))
end

@testset "frozen_diff: the command line" begin
    mktempdir() do dir
        cd(dir) do
            git!("init", "-q")
            git!("config", "user.email", "t@t")
            git!("config", "user.name", "t")
            mkpath("lib/PottsModels/test/acceptance")
            mkpath("tools")
            cp(TOOL, "tools/frozen_diff.jl")
            a = "lib/PottsModels/test/acceptance/a.jl"
            write(a, BASE)
            write("lib/PottsModels/test/acceptance/b.jl", "@testset \"b\" begin\n    @test true\nend\n")
            toml = """
            [[file]]
            path = "acceptance/a.jl"
            sha256 = "x"
            decision = "D-1"
            pins = ["P_IR"]

            [[file]]
            path = "acceptance/b.jl"
            sha256 = "y"
            decision = "D-1"
            """
            write("lib/PottsModels/test/frozen.toml", toml)
            git!("add", "-A")
            git!("commit", "-qm", "base")
            base = head()

            @test cli(base, base) == (0, "no frozen file changed\n")
            c1 = commit!(a, r("\"aaaa1111\"", "\"cccc3333\""))
            code, out = cli(base, c1)
            @test code == 0 && occursin("AUTO        acceptance/a.jl", out)
            c2 = commit!(a, r("\"aaaa1111\"", "\"cccc3333\"") * "# a note\n")
            @test cli(base, c2)[1] == 1                                               # a line outside
            git!("checkout", "-q", base)
            c3 = commit!("lib/PottsModels/test/acceptance/b.jl", "@testset \"b\" begin\n    @test 1 == 1\nend\n")
            @test cli(base, c3)[1] == 1                                               # no pins declared
            git!("checkout", "-q", base)
            c4 = commit!("lib/PottsModels/test/frozen.toml", replace(toml, "pins = [\"P_IR\"]" => "pins = [\"P_IR\", \"TOL\"]"))
            code, out = cli(base, c4)
            @test code == 1 && occursin("pins", out)
            git!("checkout", "-q", base)
            c5 = commit!("tools/frozen_diff.jl", read("tools/frozen_diff.jl", String) * "\n# loosened\n")
            code, out = cli(base, c5)
            @test code == 1 && occursin("tools/frozen_diff.jl changed", out)          # the tool is guarded
            @test cli(base, c5; tool = joinpath(dir, "tools/frozen_diff.jl"))[1] == 2  # the candidate's copy refuses
            git!("checkout", "-q", base)
            c6 = commit!("lib/PottsModels/test/frozen.toml", split(toml, "\n\n")[1] * "\n")
            @test cli(base, c6)[1] == 1                                               # dropped entry
            git!("checkout", "-q", base)
            c7 = commit!(a, r("helper(3) == 6", "helper(3 == 6"))
            @test cli(base, c7)[1] == 2                                               # parse error: never AUTO
            @test cli(base, "no-such-ref")[1] == 2
            git!("checkout", "-q", base)
            git!("rm", "-q", "tools/frozen_diff.jl")
            git!("commit", "-qm", "no tool")
            notool = head()
            @test cli(notool, notool; tool = TOOL)[1] == 2                            # no tool at the base
        end
    end
end

@testset "frozen_diff: recorded re-freezes from the history" begin
    # (commit, file under lib/PottsModels/test, expected verdict, pins)
    cases = [
        ("3e0233ce", "acceptance/p6_0bk2_skip_interior.jl", :auto, [:P60BK2_IR]),         # D-237 IR re-pin
        ("3e0233ce", "acceptance/p6_0bk2_skip_interior.jl", :maintainer, Symbol[]),       # ... undeclared
        ("3e0233ce", "acceptance/p6_0p_cadence_fingerprint.jl", :maintainer, Symbol[]),   # output fingerprint
        ("ba0beaba", "../reproductions/10_akeeb.jl", :maintainer, Symbol[]),              # D-241 page wording
        ("0e2863ed", "reproductions/15_openvt_f1_f4.jl", :maintainer, Symbol[]),          # D-249 appended testset
        ("b373ef5e", "acceptance/p6_0v1_device_lifecycle.jl", :maintainer, Symbol[]),     # D-238
        ("63b0c0d7", "acceptance/p6_5a2_ref_helpers.jl", :maintainer, Symbol[]),          # P6.5a2 fix
        ("ff993a45", "reproductions/09_cell_sorting.jl", :maintainer, Symbol[]),          # D-239 targets
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
