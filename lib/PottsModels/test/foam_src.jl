# The exported `ShearedFoam` (src/foam.jl, Jiang et al. 1999) is the model of the frozen
# reproduction test `reproductions/04_foam.jl` (D-190), which keeps its own definitions:
# `P64RShearedFoam` (the sheared model, built from `P64R_SHEAR_EXPR`), `P64RFoam` (the same
# foam without the shear term) and `p64r_brick` (the brick-wall start). They are read from
# that file without running its testsets, by evaluating only those definitions in a module of
# their own, and pinned here:
# - the same problem as `P64RShearedFoam`: the checkpoint fingerprint (the generated code,
#   lattice and solvers), the parameter defaults, relations and initial state;
# - the same trajectory, bitwise, under boundary and bulk shear, steady and periodic;
# - without shear, the same trajectory as `P64RFoam`;
# - `sheared_foam_state` paints the frozen brick wall.
# Negative controls: a changed parameter default and a changed shear expression are told
# apart. The fingerprint hashes the generated code, not parameter values, so the changed
# default shows in the parameters and the trajectory, the changed expression in the
# fingerprint.
module FrozenFoam04
using Potts
const FILE = joinpath(@__DIR__, "reproductions", "04_foam.jl")
const WANTED = (:P64RFoam, :P64R_SHEAR_EXPR, :P64R_BRICK, :p64r_brick)
_defname(ex) = ex isa Expr && ex.head === :const ? _defname(ex.args[1]) :
               ex isa Expr && ex.head === :macrocall && ex.args[1] === Symbol("@potts_model") ? ex.args[3] :
               ex isa Expr && ex.head in (:(=), :function) ? (a = ex.args[1]; a isa Symbol ? a :
                                                              a isa Expr && a.head === :call ? a.args[1] : nothing) :
               nothing
for ex in Meta.parseall(read(FILE, String)).args
    _defname(ex) in WANTED && Core.eval(@__MODULE__, ex)
end
Core.eval(@__MODULE__, P64R_SHEAR_EXPR)
end

@testset "ShearedFoam is the frozen foam test's model" begin
    F = FrozenFoam04
    @test all(n -> isdefined(F, n), (:P64RFoam, :P64RShearedFoam, :p64r_brick))
    L = (64, 64)                                             # 16 bubbles of 16²
    alg = SequentialCPM(; skip_interior = true)
    op = [sheared_foam_state(; lattice = L); :ytop => 64.0; :ymid => 32.5]
    @test op[1].second == F.p64r_brick(L) && op[3].second == fill(256.0, 16)
    @test first(sheared_foam_state())[2] == F.p64r_brick((256, 256))      # the paper's 256²

    ours(; kw...) = ShearedFoam(; name = :foam, lattice = L, kw...)
    theirs(; kw...) = F.P64RShearedFoam(; name = :foam, lattice = L, kw...)
    problem(sys, op, tend = 1; kw...) = PottsProblem(sys, op, (0, tend); kw...)
    same(a, b) = a.f.fingerprint == b.f.fingerprint && a.p == b.p && a.lattice == b.lattice && a.contact == b.contact &&
                 a.proposal == b.proposal && a.relations == b.relations && a.frozen == b.frozen && a.u0.σ == b.u0.σ &&
                 a.u0.cell == b.u0.cell && a.u0.model == b.u0.model
    a, b = problem(ours(), op), problem(theirs(), op)
    @test a.f.fingerprint == b.f.fingerprint
    @test same(a, b)
    # the default lattice and parameters too (no `ytop`/`ymid` override)
    @test same(problem(ShearedFoam(; name = :foam), sheared_foam_state()),
        problem(F.P64RShearedFoam(; name = :foam), sheared_foam_state()))

    # bitwise trajectories: 30 MCS at T = 1 from the brick wall, one seed, every shear form
    σ_end(sys, p; seed = 7) = Array(solve(problem(sys, [op; p], 30; seed), alg).u[end].σ)
    shears = [
        ("steady boundary", [:γ0 => 4.0]),
        ("periodic boundary", [:γ0 => 4.0, :periodic => 1.0, :ω => 2π / 20]),
        ("steady bulk", [:β => 0.3, :bulk => 1.0]),
        ("periodic bulk", [:β => 0.3, :bulk => 1.0, :periodic => 1.0, :ω => 2π / 20]),
    ]
    @testset "$label" for (label, p) in shears
        p = [p; :T => 1.0]
        σa = σ_end(ours(), p)
        @test σa == σ_end(theirs(), p)
        @test σa != op[1].second                             # the run moved
    end
    # without shear, the frozen test's unsheared P64RFoam
    plain = [sheared_foam_state(; lattice = L); :T => 1.0]
    @test σ_end(ours(), [:T => 1.0]) ==
          Array(solve(problem(F.P64RFoam(; name = :foam, lattice = L), plain, 30; seed = 7), alg).u[end].σ)

    # negative controls
    # a changed parameter default: same code, so the same fingerprint, but another problem
    # and another trajectory
    j4 = problem(ours(; J = 4.0), op)
    @test j4.f.fingerprint == a.f.fingerprint && !same(j4, b)
    @test σ_end(ours(; J = 4.0), [:γ0 => 4.0, :T => 1.0]) != σ_end(theirs(), [:γ0 => 4.0, :T => 1.0])
    # a changed shear expression (the sign of the boundary term): another fingerprint
    src = string(F.P64R_SHEAR_EXPR)
    @test occursin("γ0 * (", src)
    Core.eval(F, Meta.parse(replace(src, "P64RShearedFoam" => "FlippedFoam", "γ0 * (" => "-γ0 * (")))
    flipped = Base.invokelatest(() -> problem(F.FlippedFoam(; name = :foam, lattice = L), op))
    @test flipped.f.fingerprint != a.f.fingerprint
    # another seed gives another trajectory, so the bitwise pins can fail
    @test σ_end(ours(), [:γ0 => 4.0, :T => 1.0]; seed = 8) != σ_end(ours(), [:γ0 => 4.0, :T => 1.0])
end
