# The exported `ShearedFoam` (src/foam.jl, Jiang et al. 1999) is the model of the foam
# reproduction test `reproductions/04_foam_tests.jl` (D-190), whose definitions are in
# `shared/foam.jl`: `ReferenceShearedFoam` (the sheared model, built from `SHEAR_EXPR`),
# `ReferenceUnshearedFoam` (the same foam without the shear term) and `brick` (the brick-wall
# start). That file is loaded into a module of its own and compared here:
# - the same problem as `ReferenceShearedFoam`: the checkpoint fingerprint (the generated code,
#   lattice and solvers), the parameter defaults, relations and initial state;
# - the same trajectory, bitwise, under boundary and bulk shear, steady and periodic;
# - without shear, the same trajectory as `ReferenceUnshearedFoam`;
# - `sheared_foam_state` paints the reference brick wall.
# Negative controls: a changed parameter default and a changed shear expression are told
# apart. The fingerprint hashes the generated code, not parameter values, so the changed
# default shows in the parameters and the trajectory, the changed expression in the
# fingerprint.

@testsetup module FoamModelSourceSetup
include(joinpath(@__DIR__, "shared", "common.jl"))
module FoamReproduction
    include(joinpath(@__DIR__, "shared", "foam.jl"))
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "ShearedFoam is the foam reproduction's model" setup = [FoamModelSourceSetup] tags = [:pottsmodels, :core] begin
    @testset "ShearedFoam is the foam reproduction's model" begin
        F = FoamReproduction
        @test all(n -> isdefined(F, n), (:ReferenceUnshearedFoam, :ReferenceShearedFoam, :brick))
        L = (64, 64)                                             # 16 bubbles of 16²
        alg = SequentialCPM(; skip_interior = true)
        op = [sheared_foam_state(; lattice = L); :ytop => 64.0; :ymid => 32.5]
        @test op[1].second == F.brick(L) && op[3].second == fill(256.0, 16)
        @test first(sheared_foam_state())[2] == F.brick((256, 256))      # the paper's 256²

        ours(; kw...) = ShearedFoam(; name = :foam, lattice = L, kw...)
        theirs(; kw...) = F.ReferenceShearedFoam(; name = :foam, lattice = L, kw...)
        problem(sys, op, tend = 1; kw...) = PottsProblem(sys, op, (0, tend); kw...)
        function same(a, b)
            return a.f.fingerprint == b.f.fingerprint && a.p == b.p && a.lattice == b.lattice && a.contact == b.contact &&
                a.proposal == b.proposal && a.relations == b.relations && a.frozen == b.frozen && a.u0.ownership == b.u0.ownership &&
                a.u0.cell == b.u0.cell && a.u0.model == b.u0.model
        end
        a, b = problem(ours(), op), problem(theirs(), op)
        @test a.f.fingerprint == b.f.fingerprint
        @test same(a, b)
        # the default lattice and parameters too (no `ytop`/`ymid` override)
        @test same(
            problem(ShearedFoam(; name = :foam), sheared_foam_state()),
            problem(F.ReferenceShearedFoam(; name = :foam), sheared_foam_state())
        )

        # bitwise trajectories: 30 MCS at T = 1 from the brick wall, one seed, every shear form
        σ_end(sys, p; seed = 7) = Array(solve(problem(sys, [op; p], 30; seed), alg).u[end].ownership)
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
        # without shear, the reproduction's unsheared model
        plain = [sheared_foam_state(; lattice = L); :T => 1.0]
        @test σ_end(ours(), [:T => 1.0]) ==
            Array(solve(problem(F.ReferenceUnshearedFoam(; name = :foam, lattice = L), plain, 30; seed = 7), alg).u[end].ownership)

        # negative controls
        # a changed parameter default: same code, so the same fingerprint, but another problem
        # and another trajectory
        j4 = problem(ours(; J = 4.0), op)
        @test j4.f.fingerprint == a.f.fingerprint && !same(j4, b)
        @test σ_end(ours(; J = 4.0), [:γ0 => 4.0, :T => 1.0]) != σ_end(theirs(), [:γ0 => 4.0, :T => 1.0])
        # a changed shear expression (the sign of the boundary term): another fingerprint
        src = string(F.SHEAR_EXPR)
        @test occursin("γ0 * (", src)
        Core.eval(F, Meta.parse(replace(src, "ReferenceShearedFoam" => "FlippedFoam", "γ0 * (" => "-γ0 * (")))
        flipped = Base.invokelatest(() -> problem(F.FlippedFoam(; name = :foam, lattice = L), op))
        @test flipped.f.fingerprint != a.f.fingerprint
        # another seed gives another trajectory, so the bitwise pins can fail
        @test σ_end(ours(), [:γ0 => 4.0, :T => 1.0]; seed = 8) != σ_end(ours(), [:γ0 => 4.0, :T => 1.0])
    end
end
