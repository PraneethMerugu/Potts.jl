# Compare problem fingerprints between two checkouts (D-016, D-078, D-130).
#
#     julia tools/fingerprint_compare.jl [A] [B]
#
# A defaults to this repository. B defaults to a `git archive HEAD` copy of A in a temporary
# directory (A's gitignored workspace `Manifest.toml` is copied in), which is how the
# coordinator checks at merge that a fingerprint depends only on the source, not on the
# path, the build or the session. Each checkout runs in its own fresh `julia` process with
# its `lib/PottsModels/test` environment, builds the problems below and prints their
# fingerprints; the script lists every problem and exits 1 if any fingerprint differs.
using TOML: TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))

# run in each checkout's environment: name => repr(fingerprint)
const WORKER = raw"""
using Potts, PottsModels, TOML
using OrdinaryDiffEqRosenbrock: Rodas5P
two(dims, a, b) = (s = zeros(Int32, dims); s[a...] .= 1; s[b...] .= 2; s)
@potts_model FCPair begin
    @kinds medium A
    @parameters k = 0.3
    @variables begin
        y(cell) = 1.0
        s(cell) = 2.0
    end
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @equations begin
        D(y) ~ -k * y
        D(s) ~ -0.5 * s
    end
    @sweep Metropolis(; temperature = 1.0)
end
fc_op() = [ownership => two((12, 12), (2:4, 2:4), (7:9, 7:9)), kind => [:A, :A]]
problems = [
    "GranerGlazier" => () -> (s = graner_glazier_state(); PottsProblem(GranerGlazier(; name = :gg), [ownership => s[1], kind => s[2]], (0, 10))),
    "WortelAct" => () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8)),
        [ownership => two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (0, 10)),
    "WortelAct connected" => () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8), connected = true),
        [ownership => two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (0, 10)),
    "MerksVasculogenesis" => () -> PottsProblem(MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
        [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], (0, 10);
        field_solver = Potts.ExplicitEuler(substeps = 2, lower = 0.0)),
    "SingleDivisionFixture" => () -> PottsProblem(SingleDivisionFixture(; name = :fixture),
        [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [:epithelial]], (0, 10)),
    "OpenVTGrowingMonolayer" => () -> PottsProblem(OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)),
        openvt_monolayer_state(; lattice = (24, 24)), (0, 10); capacity = 64),
    "AkeebInvasion" => () -> PottsProblem(AkeebInvasion(; name = :akeeb, lattice = (60, 40)), akeeb_state(; lattice = (60, 40)),
        (0, 10); capacity = 256),
    "ODE pair RK4" => () -> PottsProblem(FCPair(; name = :pair), fc_op(), (0, 6); ode_solver = Potts.RK4()),
    "ODE pair Adaptive(Rodas5P())" => () -> PottsProblem(FCPair(; name = :pair), fc_op(), (0, 6);
        ode_solver = Potts.Adaptive(Rodas5P(); reltol = 1e-6)),
    "ODE pair Adaptive(Rodas5P()) Float32" => () -> PottsProblem(FCPair(; name = :pair), fc_op(), (0, 6); T = Float32,
        ode_solver = Potts.Adaptive(Rodas5P(); reltol = 1e-6)),
]
out = Dict{String, String}()
for (name, build) in problems
    out[name] = try
        repr(build().f.fingerprint)
    catch e
        "error: " * first(sprint(showerror, e), 200)
    end
end
TOML.print(stdout, out)
"""

function fingerprints(checkout)
    env = joinpath(checkout, "lib", "PottsModels", "test")
    isdir(env) || error("$checkout: no lib/PottsModels/test environment")
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$env -e $WORKER`
    return TOML.parse(read(cmd, String))
end

"""A `git archive HEAD` copy of `checkout` with its workspace Manifest, in a temporary
directory; the caller removes it (`main`). Removed here if building it fails."""
function archive_copy(checkout)
    dir = mktempdir(; cleanup = false)
    try
        run(pipeline(`git -C $checkout archive HEAD`, `tar -x -C $dir`))
        manifest = joinpath(checkout, "Manifest.toml")
        isfile(manifest) && cp(manifest, joinpath(dir, "Manifest.toml"))
        run(`$(Base.julia_cmd()) --startup-file=no --project=$dir -e "using Pkg; Pkg.instantiate()"`)
    catch
        rm(dir; recursive = true, force = true)
        rethrow()
    end
    return dir
end

"""Warn when `checkout` has uncommitted changes: they are in A but not in its HEAD archive,
so the problems they touch show as DIFFER."""
function warn_if_dirty(checkout)
    status = try
        read(pipeline(`git -C $checkout status --porcelain --untracked-files=no`; stderr = devnull), String)
    catch
        return nothing                                   # not a git checkout: nothing to compare
    end
    isempty(strip(status)) || @warn "$checkout has uncommitted changes; they are not in the `git archive HEAD` " *
                                    "copy B, so the problems they touch show as DIFFER" status
    return nothing
end

function main(args)
    a = abspath(get(args, 1, ROOT))
    auto = length(args) < 2
    auto && warn_if_dirty(a)
    b = auto ? archive_copy(a) : abspath(args[2])
    try
        println("A = $a\nB = $b")
        fa, fb = fingerprints(a), fingerprints(b)
        names = sort!(collect(union(keys(fa), keys(fb))))
        differ = 0
        for n in names
            x, y = get(fa, n, "missing"), get(fb, n, "missing")
            same = x == y && !startswith(x, "error")
            same || (differ += 1)
            println(rpad(n, 40), same ? "same  " : "DIFFER", "  ", x, same ? "" : "  vs  $y")
        end
        println(differ == 0 ? "all $(length(names)) fingerprints agree" : "$differ of $(length(names)) differ")
        return differ == 0
    finally
        auto && rm(b; recursive = true, force = true)   # the temporary archive copy
    end
end

if abspath(PROGRAM_FILE) == @__FILE__()
    exit(main(ARGS) ? 0 : 1)
end
