# `QuasiSteady` in standalone LatticePDE. Each window solves `0 = r(u)` at the
# window's start time, `−J̃ δ = r(u_k)` from the field's current values (no time-step term),
# one linear solve for a linear exact group, a checked budget of 8 Newton iterations
# otherwise. It refuses a growth the operator sees and a field with no decay and no fixed
# value (at build and at every parameter write); a region with neither that the inputs cut
# off (an island) is found on the device: a budget hit with no real reduction is
# `ConvergenceFailure`. The windows are checked against the hand steady matrix of
# `hand_rate` (implicit.jl). Base (the guard commit b32d9112): `QuasiSteady` is not defined
# (every testset errors). Negative controls (mutations): the steady failure test left out
# (noreduce), the growth refusal left out (nogrowth).

# the steady state of the hand rate `(L, b)`: `L u = −b`, the masked sites holding `mval`

@testsetup module LP_quasisteady
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables,
    Differential, PDESystem,
    System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex,
    Shift, Pre,
    t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
include("shared/lp_runner.jl")
include("shared/discretize.jl")
include("shared/problems.jl")
include("shared/bounds.jl")
include("shared/silent.jl")
include("shared/groups.jl")
include("shared/families.jl")
include("shared/odepath.jl")
include("shared/precond.jl")
include("shared/groups_coupling.jl")
include("shared/implicit.jl")
include("shared/robin_site.jl")
include("shared/grids.jl")
include("shared/remakecb.jl")
include("shared/maskswitch.jl")
function qs_hand(; mask = nothing, mval = nothing, kw...)
    L, b = hand_rate(; kw...)
    A, rhs = copy(L), -b
    if mask !== nothing
        for r in eachindex(rhs)
            mask[r] || continue
            A[r, :] .= 0
            A[r, r] = 1
            rhs[r] = mval[r]
        end
    end
    return A \ rhs
end
qs_window(p, alg) = (ig = init(p, alg; dt = 0.1); step!(ig); (ig, vec(ig[bce])))
function qmsg(f)
    return try
        f()
        ""
    catch err
        err isa ArgumentError ? err.msg : sprint(showerror, err)
    end
end
@parameters qg = 1.0

# Steady rows `0 ~ rhs` in B, time-free systems through the steady
# solve, the QuasiSteady groups first. A steady row is lowered as the rate row of the field
# it determines (`steady_rows`) and takes `QuasiSteady` only, by default too; a system with
# no time is solved once (`solve(prob)`, the inner solver to rtol 1e-6 within 64
# iterations). Before the fix (6b6bf089): `0 ~ rhs` is refused ("not lowered in this
# version") and a system with no time too (every testset errors). (the owned problem field
# algorithms step, `LFP.field_problem` of the problem `discretize` returns)
function qown(
        sys;
        dims = BDIMS
    )
    return LFP.field_problem(
        discretize(sys, LatticeDiscretization(Grid(dims); T = Float64))
    )
end
include("shared/export_all.jl")
end

@testitem "one QuasiSteady window is the steady state (the hand matrix)" setup = [
    LP_quasisteady,
] tags = [
    :latticepde, :quasisteady,
] begin
    @testset "one QuasiSteady window is the steady state (the hand matrix)" begin
        alg = QuasiSteady(; linsolve = BTIGHT)
        # a numeric operator: diffusion, decay, a source, a Dirichlet face, a mask with its
        # value
        p = bown(
            bsys(
                [D(bce) ~ bD * laplacian(bce) - bk * bce + x], [
                    bc(0, x, y) ~ x * y, bc(t, 0, y) ~ 1.0,
                    bce ~ masked(bqe == 2, 1.5),
                ],
                [bD, bk]
            )
        )
        ig, u = qs_window(p, alg)
        mk = vec(BKIND .== 2)
        want = qs_hand(;
            K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x, faces = Dict(
                (1, -1) =>
                    (:dir, 1.0)
            ),
            mask = mk, mval = fill(1.5, 48)
        )
        @test maximum(abs, u .- want) < 1.0e-9 && all(u[mk] .== 1.5)
        rt = only(ig.runtimes)
        @test rt.cache.newton == 1 && rt.cache.exact && rt.totals.solves == 1 &&
            SciMLBase.check_error(ig) == ReturnCode.Success
        @test ig.substeps == 1                                     # (one solve per window)
        # the window's start time: a source `x + t` is read at t = 0, then at t = 0.1; the
        # start state does not matter (a steady solve)
        p = bown(
            bsys(
                [D(bce) ~ bD * laplacian(bce) - bk * bce + x + t],
                [bc(0, x, y) ~ 5.0, bc(t, 0, y) ~ 1.0], [bD, bk]
            )
        )
        ig = init(p, alg; dt = 0.1)
        step!(ig)
        w1 = qs_hand(;
            K = (x, y) -> 0.3, k = (x, y) -> 2.0,
            f = (x, y) -> x, faces = Dict((1, -1) => (:dir, 1.0))
        )
        @test maximum(abs, vec(ig[bce]) .- w1) < 1.0e-9
        step!(ig)
        w2 = qs_hand(;
            K = (x, y) -> 0.3, k = (x, y) -> 2.0,
            f = (x, y) -> x + 0.1, faces = Dict((1, -1) => (:dir, 1.0))
        )
        @test maximum(abs, vec(ig[bce]) .- w2) < 1.0e-9
        # the default inner solver from a cold start, and warm: the next window starts at
        # the last solution, so its solve is done at its setup
        ig = init(p, QuasiSteady(); dt = 0.1, save_everystep = false)
        step!(ig)
        @test maximum(abs, vec(ig[bce]) .- w1) < 1.0e-4
        @test bwarm(ig) == 0
        @test LSB.iterations(ig.runtimes[1].cache.rows[1].solver) <= 8
    end
end

@testitem "the solver capabilities in a QuasiSteady group" setup = [LP_quasisteady] tags = [
    :latticepde, :quasisteady,
] begin
    @testset "the solver capabilities in a QuasiSteady group" begin
        alg = QuasiSteady(; linsolve = BTIGHT)
        xs = bxs()
        # a Robin face, positive part
        p = bown(
            bsys(
                [D(bce) ~ bD * laplacian(bce) - bk * bce + x], [
                    bc(0, x, y) ~ 0.0,
                    2.0 * bc(t, x, 0) - Differential(y)(bc(t, x, 0)) ~ bg,
                ],
                [bD, bk, bg]
            )
        )
        ig, u = qs_window(p, alg)
        want = qs_hand(;
            K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x,
            faces = Dict((2, -1) => (:robin, 2.0, -1.0, 0.5))
        )
        @test maximum(abs, u .- want) < 1.0e-10 && only(ig.runtimes).cache.newton == 1
        # opposite signs: a steady solve takes the Robin face's negative part into its
        # operator (it is diagonal, so the operator stays symmetric): one exact solve,
        # newton 1, the hand matrix to 1e-9, for the well-posed faces (max Re λ of the
        # steady Jacobian −0.68 at decay 2, −0.18 at 1.5). Before the fix (e7068add): the
        # defect correction, newton 40 and ~20 solves a window
        function rob(kd, β)
            return remake(
                bown(
                    bsys(
                        [D(bce) ~ bD * laplacian(bce) - bk * bce + x],
                        [
                            bc(0, x, y) ~ 0.0, 2.0 * bc(t, x, 0) +
                                β * Differential(y)(bc(t, x, 0)) ~ bg,
                        ], [
                            bD, bk, bg,
                        ]
                    )
                ); p = [bk => kd]
            )
        end
        for kd in (2.0, 1.5)
            p = rob(kd, 1.0)
            want = qs_hand(;
                K = (x, y) -> 0.3, k = (x, y) -> kd, f = (x, y) -> x,
                faces = Dict((2, -1) => (:robin, 2.0, 1.0, 0.5))
            )
            ig = init(p, alg; dt = 0.1)
            @test_logs min_level = WARN step!(ig)
            rt = only(ig.runtimes)
            @test rt.cache.newton == 1 && rt.cache.exact && rt.totals.solves == 1 &&
                SciMLBase.check_error(ig) == ReturnCode.Success
            @test maximum(abs, vec(ig[bce]) .- want) < 1.0e-9
        end
        # the faces that make the steady problem indefinite (max Re λ +3.4, +0.82, +1.1,
        # +5.4) are refused at build, as a growth is, with the eigenvalue and the route; and
        # at a write
        for (kd, β) in ((2.0, 0.5), (0.5, 1.0), (0.2, 1.0), (0.05, 0.5))
            @test_throws ArgumentError init(rob(kd, β), alg; dt = 0.1)
        end
        ig = init(rob(2.0, 1.0), alg; dt = 0.1)
        @test_throws ArgumentError (ig.ps[bk] = 0.5)
        # (the route builds)
        @test init(rob(2.0, 0.5), BackwardEuler(); dt = 0.1) isa Any
        # a field face coefficient with a face-Dirichlet value that varies along the face
        p = bown(
            bsys(
                [D(bce) ~ DivKGrad(:harmonic)(1 + x * y, bce) - bk * bce],
                [bc(0, x, y) ~ 0.0, bc(t, 0, y) ~ 1.0 + y], [bk]
            )
        )
        ig, u = qs_window(p, alg)
        @test only(ig.runtimes).cache.rows[1].op.field
        want = qs_hand(;
            K = (x, y) -> 1 + x * y, k = (x, y) -> 2.0,
            faces = Dict((1, -1) => (:dir, (x, y) -> 1.0 + y))
        )
        @test maximum(abs, u .- want) < 1.0e-10
        # a mask whose value is a field
        p = bown(
            bsys(
                [D(bce) ~ bD * laplacian(bce) - bk * bce],
                [bc(0, x, y) ~ 0.0, bce ~ masked(bqe == 2, 1 + x)], [bD, bk]
            )
        )
        ig, u = qs_window(p, alg)
        mk = vec(BKIND .== 2)
        want = qs_hand(;
            K = (x, y) -> 0.3, k = (x, y) -> 2.0, mask = mk, mval = vec(
                1 .+
                    xs
            )
        )
        @test maximum(abs, u .- want) < 1.0e-10 && all(u[mk] .== vec(1 .+ xs)[mk])
        # an input bound by aliasing: a write of the input between windows changes the next
        # solve
        p = bown(
            bsys(
                [D(bce) ~ value_at(bW, bqe) * laplacian(bce) - bk * bce + 1],
                [bc(0, x, y) ~ 0.0], [bW, bk]
            )
        )
        ig = init(p, alg; dt = 0.1, save_everystep = false)
        step!(ig)
        step!(ig)
        @test bwarm(ig) == 0
        K2 = Int32[(i * j) % 2 for i in 1:8, j in 1:6]
        ig[bqe] = K2
        step!(ig)
        want = qs_hand(;
            K = (x, y) -> 1.0, m = (i, j) -> (0.0, 0.5, 2.0)[K2[i, j] + 1],
            k = (x, y) -> 2.0, f = (x, y) -> 1.0
        )
        @test maximum(abs, vec(ig[bce]) .- want) < 1.0e-10
    end
end

@testitem "nonlinear rows: Michaelis–Menten within the default 8 iterations" setup = [
    LP_quasisteady,
] tags = [
    :latticepde, :quasisteady,
] begin
    @testset "nonlinear rows: Michaelis–Menten within the default 8 iterations" begin
        sys = nlsys(
            [D(bce) ~ 0.05 * laplacian(bce) - 40 * bce / (0.025 + bce) + 20],
            [bc(0, x, y) ~ 0.5, bc(t, 0, y) ~ 1.0], [bce]; T = 0.3
        )
        ig = init(nlown(sys), QuasiSteady(; linsolve = BTIGHT); dt = 0.1)
        step!(ig)
        rt = only(ig.runtimes)
        @test rt.cache.newton == 8 && rt.cache.check &&
            SciMLBase.check_error(ig) == ReturnCode.Success
        # (the host stop: converged before the budget)
        @test rt.totals.newton_budget == 0 && rt.totals.solves < 8
        po = discretize(sys, LatticeDiscretization(Grid((16, 16)); T = Float64))
        du = similar(po.u0)
        po.f(du, vec(ig[bce]), po.p, 0.0)
        # the steady residual against the uptake's scale (40): ε_N = 1e-3 of the field
        @test maximum(abs, du) < 1.0e-3 * 40 ||
            (println("MM steady residual ", maximum(abs, du)); false)
        # the second window starts converged: one iteration
        s0 = rt.totals.solves
        step!(ig)
        @test rt.totals.solves - s0 <= 2
    end
end

@testitem "the refusals: growth, no unique steady state; keywords, show" setup = [
    LP_quasisteady,
] tags = [
    :latticepde, :quasisteady,
] begin
    @testset "the refusals: growth, no unique steady state; keywords, show" begin
        # a growth the operator sees, at build and at a parameter write
        pg = bown(
            bsys(
                [D(bce) ~ bD * laplacian(bce) + qg * bce],
                [bc(0, x, y) ~ x, bc(t, 0, y) ~ 1.0], [bD, qg]
            )
        )
        @test_throws ArgumentError init(pg, QuasiSteady(); dt = 0.1)
        @test init(pg, BackwardEuler(); dt = 0.1) isa Any                  # (the route)
        pd = bown(
            bsys(
                [D(bce) ~ bD * laplacian(bce) - qg * bce + x], [bc(0, x, y) ~ x], [
                    bD, qg,
                ]
            )
        )
        ig = init(pd, QuasiSteady(); dt = 0.1)
        step!(ig)
        @test_throws ArgumentError (ig.ps[qg] = -2.0)
        # no decay and no fixed value: pure Neumann (refused), at build and when a write
        # takes the decay away; a Dirichlet face anchors it (accepted with no decay)
        pn = bown(bsys([D(bce) ~ bD * laplacian(bce) + x], [bc(0, x, y) ~ x], [bD]))
        @test_throws ArgumentError init(pn, QuasiSteady(); dt = 0.1)
        ig = init(pd, QuasiSteady(); dt = 0.1)
        @test_throws ArgumentError (ig.ps[qg] = 0.0)
        pa = bown(
            bsys(
                [D(bce) ~ bD * laplacian(bce) - qg * bce + x],
                [bc(0, x, y) ~ x, bc(t, 0, y) ~ 1.0], [bD, qg]
            )
        )
        ig = init(pa, QuasiSteady(; linsolve = BTIGHT); dt = 0.1)
        ig.ps[qg] = 0.0
        step!(ig)
        @test maximum(
            abs,
            vec(ig[bce]) .-
                qs_hand(;
                K = (x, y) -> 0.3, f = (x, y) -> x, faces = Dict(
                    (1, -1) =>
                        (:dir, 1.0)
                )
            )
        ) < 1.0e-9
        # a mask anchors it too
        pm = bown(
            bsys(
                [D(bce) ~ bD * laplacian(bce) + x],
                [bc(0, x, y) ~ x, bce ~ masked(bqe == 2, 1.0)], [bD]
            )
        )
        @test qmsg(() -> init(pm, QuasiSteady(); dt = 0.1)) == ""
        # the keywords
        @test_throws ArgumentError QuasiSteady(; substeps = 2)
        @test_throws ArgumentError QuasiSteady(; lower_bound = 0.0)
        @test_throws ArgumentError QuasiSteady(; theta = 1)
        @test_throws ArgumentError QuasiSteady(; nlsolve = 0)
        a = QuasiSteady(; nlsolve = LatticeNewton(; max_iter = 3))
        @test eval(Meta.parse(repr(a))) == a
    end
end

@testitem "budget hits: a real reduction stays Success, none (an island) is \
    ConvergenceFailure" setup = [LP_quasisteady] tags = [
    :latticepde, :quasisteady,
] begin
    @testset "budget hits: a real reduction stays Success, none (an island) is \
        ConvergenceFailure" begin
        # a budget of 2 PCG iterations on 32²: the residual falls by more than half but not
        # to the tolerance; counted and warned with the route, `Success`
        p = discretize(
            bsys(
                [D(bce) ~ bD * laplacian(bce) - 0.01 * bce + x], [
                    bc(0, x, y) ~ 0.0, bc(t, 0, y) ~ 1.0,
                ], [bD]
            ),
            LatticeDiscretization(Grid((32, 32)); T = Float64); inputs = [
                bqe =>
                    zeros(Int32, 32, 32),
            ]
        )
        ig = init(p, QuasiSteady(; linsolve = LatticePCG(; maxiters = 2)); dt = 0.1)
        @test_logs (
            :warn,
            r"field `bc`: the linear solve reached its budget 1 time so far .*a larger linear budget",
        ) step!(ig)
        sc = LSB.scalars(only(ig.runtimes).cache.rows[1].solver)
        @test sc.status === :budget && sc.rnorm < sc.bnorm / 2 &&
            SciMLBase.check_error(ig) == ReturnCode.Success   # (3.9 of 614)
        s = solve(p, QuasiSteady(; linsolve = LatticePCG(; maxiters = 2)); dt = 0.1)
        @test s.retcode == ReturnCode.Success && s.stats.budget > 0
        # an island: the domain (a Bool input) is two strips; the low one touches the
        # Dirichlet face at y = 0, the high one touches no condition and the field has no
        # decay, so the high strip's steady state is not unique (a source of 1 everywhere:
        # none), and the solve cannot reduce the residual there. The build sees the
        # Dirichlet face and accepts the group.
        @variables bdm(..)::Bool [input = true]
        bdme = bdm(t, x, y)
        dm = [j <= 2 || j >= 5 for i in 1:8, j in 1:6]
        si = PDESystem(
            [D(bce) ~ bD * laplacian(bce) + 1.0], [bc(0, x, y) ~ 0.0, bc(t, x, 0) ~ 0.0],
            bdom(1.0), [t, x, y], [bce, bdme], [bD];
            name = :island
        )
        pi = discretize(
            si, LatticeDiscretization(Grid(BDIMS); T = Float64, domain = bdm);
            inputs = [bdme => dm]
        )
        ig = init(pi, QuasiSteady(; linsolve = LatticePCG(; maxiters = 16)); dt = 0.1)
        @test_logs (
            :warn,
            r"field `bc`: the solve failed in window 1 \(t = 0\.0\) \(the steady solve made no real reduction: a region has no decay and no fixed value.*give that region a decay or a fixed value, or step the field with `BackwardEuler`",
        ) step!(ig)
        sc = LSB.scalars(only(ig.runtimes).cache.rows[1].solver)
        # the status the island produces (recorded: `:floor` after 7 iterations, the stall
        # test, with the residual grown to 3.7e9 against ‖b‖ = 1: no reduction)
        @test sc.status === :floor && sc.rnorm > sc.bnorm / 2 ||
            (println("island status ", sc); false)
        s = solve(pi, QuasiSteady(; linsolve = LatticePCG(; maxiters = 16)); dt = 0.1)
        @test s.retcode == ReturnCode.ConvergenceFailure && length(s.t) == 2
        # the same strips with a decay in each: unique, solved
        sd = PDESystem(
            [D(bce) ~ bD * laplacian(bce) - 0.5 * bce + 1.0], [
                bc(0, x, y) ~ 0.0, bc(t, x, 0) ~ 0.0,
            ], bdom(1.0), [t, x, y],
            [bce, bdme], [bD]; name = :island2
        )
        pd = discretize(
            sd, LatticeDiscretization(Grid(BDIMS); T = Float64, domain = bdm);
            inputs = [bdme => dm]
        )
        @test solve(pd, QuasiSteady(; linsolve = BTIGHT); dt = 0.1).retcode ==
            ReturnCode.Success
    end
end

@testitem "components equal scalars; a hexagonal lattice runs QuasiSteady" setup = [
    LP_quasisteady,
] tags = [
    :latticepde, :quasisteady,
] begin
    @testset "components equal scalars; a hexagonal lattice runs QuasiSteady" begin
        @variables bu(..)[1:2]
        bue = bu(t, x, y)
        comp = nlsys(
            [
                D(bue[1]) ~ 0.05 * laplacian(bue[1]) - 2 * bue[1] + 1,
                D(bue[2]) ~ 0.05 * laplacian(bue[2]) - bue[2] + bue[1],
            ],
            [bu(0, x, y)[1] ~ 0.5, bu(0, x, y)[2] ~ 0.0], [bue]; T = 0.3
        )
        scal = nlsys(
            [
                D(bce) ~ 0.05 * laplacian(bce) - 2 * bce + 1,
                D(boe) ~ 0.05 * laplacian(boe) - boe + bce,
            ],
            [bc(0, x, y) ~ 0.5, bo(0, x, y) ~ 0.0], [bce, boe]; T = 0.3
        )
        a = solve(nlown(comp), QuasiSteady(); dt = 0.1)
        b = solve(nlown(scal), QuasiSteady(); dt = 0.1)
        @test LatticePDE.Problems.field_stats(a) == LatticePDE.Problems.field_stats(b) &&
            a.stats.solves > 0
        @test a[bue[1], length(a.t)] == b[bce, length(b.t)] &&
            a[bue[2], length(a.t)] == b[boe, length(b.t)]
        hs = PDESystem(
            [D(bce) ~ laplacian(bce) - bce], [bc(0, x, y) ~ 0.0],
            bdom(1.0), [t, x, y], [bce], Any[]; name = :hex
        )
        ph = discretize(
            hs,
            LatticeDiscretization(Grid((6, 6); geometry = HEX); T = Float64)
        )
        @test solve(ph, QuasiSteady(); dt = 0.1).retcode == ReturnCode.Success
    end
end

# A QuasiSteady group in a loop of groups takes its gain in the coupling
# rule, κ_QS = dt · Σ k_in · gain · k_out ≤ 1 (gain 1/δ here, the decay's); past it the loop
# is refused, with the routes (one Backward Euler group; Backward Euler for the steady
# field; a smaller dt); a steady group another group reads one way stays accepted. The cases
# are the the loop `q1`: `0 = 0.1Δa − δa + s k b` steady, `b' = 0.1Δb − b − k a`, whose lag
# of one window grew to 1e37 (δ = 0.1, k = 5: κ = 25). Before the fix (773f0957): every loop
# accepted (the refusal tests fail).
@testitem "a QuasiSteady group in a loop past its gain is refused, with its routes" setup =
    [LP_quasisteady] tags = [
    :latticepde, :quasisteady,
] begin
    @testset "a QuasiSteady group in a loop past its gain is refused, with its routes" begin
        @variables qa(..) qb(..)
        qae, qbe = qa(t, x, y), qb(t, x, y)
        function loop(δ, k, s)
            return discretize(
                PDESystem(
                    [
                        D(qae) ~ 0.1 * laplacian(qae) - δ * qae + s * k * qbe,
                        D(qbe) ~ 0.1 * laplacian(qbe) - qbe - k * qae,
                    ],
                    [qa(0, x, y) ~ 0.0, qb(0, x, y) ~ 1.0], bdom(1.0), [t, x, y], [
                        qae, qbe,
                    ], Any[]; name = :loop
                ),
                LatticeDiscretization(Grid((8, 8)); T = Float64)
            )
        end
        for (δ, k, s, κ) in (
                (0.1, 5.0, 1.0, "25.0"), (0.1, 5.0, -1.0, "25.0"),
                (1.0, 5.0, 1.0, "2.5"), (0.1, 9.0, 1.0, "81.0"),
            )
            p = loop(δ, k, s)
            @test_throws ArgumentError init(
                p, FieldGroups(qae => QuasiSteady(), qbe => BackwardEuler()); dt = 0.1
            )
            # the routes: one group, or Backward Euler for the steady field
            for alg in (
                    BackwardEuler(), FieldGroups(
                        qae => BackwardEuler(), qbe =>
                            BackwardEuler()
                    ),
                )
                r = solve(p, alg; dt = 0.1)
                # (`s = −1` grows: `a`, `b` have an eigenvalue `k − (1 + δ)/2` > 0; the
                # others decay)
                @test r.retcode == ReturnCode.Success &&
                    all(isfinite, r[qbe, length(r.t)]) &&
                    (s < 0 || maximum(abs, r[qbe, length(r.t)]) < 1) || (
                    println(
                        "route ", (δ, k, s), " ", r.retcode,
                        " ", maximum(abs, r[qbe, length(r.t)])
                    );
                    false
                )
            end
        end
        # the loop in one steady group: a well-posed system (max Re λ −0.55) whose block
        # iteration does not contract (≈ k/√(δμ) = 15.8): solved together (coupled.jl:
        # against the dense steady solve; until then `ConvergenceFailure`, naming the
        # coupling)
        p = loop(0.1, 5.0, 1.0)
        r = solve(p, QuasiSteady(); dt = 0.1)
        @test r.retcode == ReturnCode.Success
        # a steady linear divergence has its own cause (32) and words, apart from no
        # reduction (16)
        @test LFP.status_route(QuasiSteady(), :failure, 0x21) ==
            "step the field with `BackwardEuler`, or give each region a decay or a fixed \
                value"
        @test occursin(
            "may be indefinite (a growth, or a Robin face whose α and β have opposite \
                signs) or have an island",
            last(LFP.STATUS_CAUSES[6])
        )
        # one way: `qb` reads the steady `qa`, `qa` reads no other group: accepted, the
        # steady state
        pw = discretize(
            PDESystem(
                [
                    D(qae) ~ 0.1 * laplacian(qae) - qae + x,
                    D(qbe) ~ 0.1 * laplacian(qbe) - qbe - 5 * qae,
                ],
                [qa(0, x, y) ~ 0.0, qb(0, x, y) ~ 1.0], bdom(1.0), [t, x, y], [qae, qbe],
                Any[]; name = :oneway
            ),
            LatticeDiscretization(Grid((8, 8)); T = Float64)
        )
        r = solve(
            pw, FieldGroups(
                qae => QuasiSteady(; linsolve = BTIGHT), qbe =>
                    BackwardEuler()
            ); dt = 0.1
        )
        @test r.retcode == ReturnCode.Success
        p1 = discretize(
            PDESystem(
                [D(qae) ~ 0.1 * laplacian(qae) - qae + x], [qa(0, x, y) ~ 0.0], bdom(1.0), [
                    t, x, y,
                ], [qae], Any[];
                name = :alone
            ), LatticeDiscretization(Grid((8, 8)); T = Float64)
        )
        # (the steady field alone)
        rs = solve(p1, QuasiSteady(; linsolve = BTIGHT); dt = 0.1)
        @test maximum(abs, r[qae, length(r.t)] .- rs[qae, length(rs.t)]) < 1.0e-12
    end
end

# The QuasiSteady gain in the coupling rule. A steady group answers its
# lagged inputs at once with gain G (≤ 1/s_min, and ≤ max (s + A_a)⁻¹1 along an axis with a
# face anchor; a mask does not count), so a group that reads it sees the rate Σ k_in · G ·
# k_out: accepted when dt times that is ≤ 1, and the run is the split scheme (the hand
# recursion to 1e-9), which tends to the coupled solution at first order in dt. Before the
# fix (932c12ce): every loop with a QuasiSteady group refused ("does not bound that gain
# yet"). Negative controls (mutations): the gain left out of the rate (G · k_out = 1): the
# q1 loops, the face-anchored k = 4 loop and the write past the limit are accepted (6 fail);
# the face anchors left out of the gain: the zero-shift loop has no bound and is refused (1
# fails, 1 errors).
@testitem "the QuasiSteady gain in the coupling rule: accepted loops match the coupled \
    solution" setup = [LP_quasisteady] tags = [
    :latticepde, :quasisteady,
] begin
    @testset "the QuasiSteady gain in the coupling rule: accepted loops match the coupled \
        solution" begin
        @variables qa(..) qb(..)
        qae, qbe = qa(t, x, y), qb(t, x, y)
        function own8(sys)
            return LFP.field_problem(
                discretize(sys, LatticeDiscretization(Grid((8, 8)); T = Float64))
            )
        end
        function gl()
            return FieldGroups(
                qae => QuasiSteady(; linsolve = BTIGHT), qbe =>
                    BackwardEuler(; linsolve = BTIGHT)
            )
        end
        # the decay sets the gain (1/δ = 1): κ = 0.1 · 0.5 · 1 · 0.5 = 0.025. Uniform data
        # stay uniform (no flux faces): a = (k/δ) b at the window's start, then b's step, b⁺
        # = (b − dt k a)/(1 + dt); the coupled solution b(1) = exp(−(1 + k²/δ))
        p = own8(
            PDESystem(
                [
                    D(qae) ~ 0.1 * laplacian(qae) - qae + 0.5 * qbe,
                    D(qbe) ~ 0.1 * laplacian(qbe) - qbe - 0.5 * qae,
                ],
                [qa(0, x, y) ~ 0.0, qb(0, x, y) ~ 1.0], bdom(1.0), [t, x, y], [qae, qbe],
                Any[]; name = :g1
            )
        )
        err = map((0.1, 0.01)) do dt
            r = solve(p, gl(); dt)
            @test r.retcode == ReturnCode.Success
            n = round(Int, 1 / dt)
            @test maximum(abs, r[qbe, length(r.t)] .- ((1 - dt * 0.25) / (1 + dt))^n) <
                1.0e-9
            @test maximum(
                abs, r[qae, length(r.t)] .-
                    0.5 * ((1 - dt * 0.25) / (1 + dt))^(n - 1)
            ) < 1.0e-9
            abs(r[qbe, length(r.t)][1] - exp(-1.25))
        end
        @test err[2] < 2.0e-3 && 8 < err[1] / err[2] < 12 ||
            (println("12c order ", err); false)       # (first order)
        # a face-anchored steady field with no decay (S4, S-b): `0 = 0.1Δa + k b`, `a = 0`
        # at x = 0, 1; its gain is max (A_x)⁻¹1 = 1.25 (the cell-centered Dirichlet line,
        # L²/(8D)), finite
        function fa(k)
            return own8(
                PDESystem(
                    [
                        D(qae) ~ 0.1 * laplacian(qae) + k * qbe,
                        D(qbe) ~ 0.1 * laplacian(qbe) - qbe - k * qae,
                    ],
                    [
                        qa(0, x, y) ~ 0.0, qb(0, x, y) ~ 1.0,
                        qa(t, 0, y) ~ 0.0, qa(t, 1, y) ~ 0.0,
                    ], bdom(1.0), [t, x, y], [qae, qbe], Any[];
                    name = :g2
                )
            )
        end
        @test_throws ArgumentError init(fa(4.0), gl(); dt = 0.1)
        # k = 1: κ = 0.125, accepted. The hand split (a from b at the window's start, then
        # b's Backward Euler step) and the coupled solution `b' = (L_b − I + k² L_a⁻¹) b`,
        # `exp`
        La, _ = hand_rate(;
            dims = (8, 8), K = (x, y) -> 0.1,
            faces = Dict((1, -1) => (:dir, 0.0), (1, 1) => (:dir, 0.0))
        )
        Lb, _ = hand_rate(; dims = (8, 8), K = (x, y) -> 0.1)
        Mb = Lb - I
        coupled = exp(Mb + inv(La)) * ones(64)
        err = map((0.1, 0.025)) do dt
            r = solve(fa(1.0), gl(); dt)
            bh = ones(64)
            for _ in 1:round(Int, 1 / dt)
                ah = -(La \ bh)
                bh = (I - dt * Mb) \ (bh - dt * ah)
            end
            @test r.retcode == ReturnCode.Success &&
                maximum(abs, vec(r[qbe, length(r.t)]) .- bh) < 1.0e-9
            maximum(abs, vec(r[qbe, length(r.t)]) .- coupled) / maximum(abs, coupled)
        end
        @test err[2] < 0.02 && 3 < err[1] / err[2] < 5 ||
            (println("12c face order ", err); false)   # (first order)
        # a steady field anchored only by a mask has no bounded gain (a mask moves with the
        # inputs): its loop is refused, with the routes
        @variables qm(..)::Int32 [input = true]
        qme = qm(t, x, y)
        sm = PDESystem(
            [
                D(qae) ~ 0.1 * laplacian(qae) + 0.1 * qbe,
                D(qbe) ~ 0.1 * laplacian(qbe) - qbe - 0.1 * qae,
            ],
            [qa(0, x, y) ~ 0.0, qb(0, x, y) ~ 1.0, qae ~ masked(qme == 1, 0.0)], bdom(1.0),
            [
                t, x, y,
            ], [qae, qbe, qme], Any[];
            name = :g3
        )
        pm = discretize(
            sm, LatticeDiscretization(Grid((8, 8)); T = Float64);
            inputs = [qme => Int32[i == 1 ? 1 : 0 for i in 1:8, j in 1:8]]
        )
        @test_throws ArgumentError init(pm, gl(); dt = 0.1)
        # (the route)
        @test solve(pm, BackwardEuler(); dt = 0.1).retcode == ReturnCode.Success
        # two steady groups in a loop with a transient one: a steady field that reads a
        # steady field of the loop is refused, the groups named (the verb agrees); one way,
        # the cascade is accepted
        @variables qc(..)
        qce = qc(t, x, y)
        function cas(k)
            return own8(
                PDESystem(
                    [
                        0 ~ 0.1 * laplacian(qae) - qae + k * qbe,
                        0 ~ 0.1 * laplacian(qce) - qce + 0.5 * qae,
                        D(qbe) ~ 0.1 * laplacian(qbe) - qbe - 0.5 * qce,
                    ],
                    [qa(0, x, y) ~ 0.0, qc(0, x, y) ~ 0.0, qb(0, x, y) ~ 1.0], bdom(1.0), [
                        t, x, y,
                    ], [qae, qce, qbe], Any[]; name = :cas
                )
            )
        end
        # (by default the steady rows of `qa`, `qc` are one QuasiSteady group, whose gains
        # compose, so the loop is accepted; as two steady groups it is refused, with the
        # route of one)
        @test solve(cas(0.3), BackwardEuler(); dt = 0.1).retcode == ReturnCode.Success
        two = FieldGroups(
            qae => QuasiSteady(),
            qce => QuasiSteady(; nlsolve = LatticeNewton(; max_iter = 3));
            default = BackwardEuler()
        )
        @test_throws ArgumentError init(cas(0.3), two; dt = 0.1)
        @test solve(cas(0.0), BackwardEuler(); dt = 0.1).retcode == ReturnCode.Success
        # a parameter write is checked again: past the limit it is refused, and nothing
        # changes
        @parameters gk = 0.5
        pg = own8(
            PDESystem(
                [
                    D(qae) ~ 0.1 * laplacian(qae) - qae + gk * qbe,
                    D(qbe) ~ 0.1 * laplacian(qbe) - qbe - gk * qae,
                ],
                [qa(0, x, y) ~ 0.0, qb(0, x, y) ~ 1.0], bdom(1.0), [t, x, y], [qae, qbe],
                [gk]; name = :g4
            )
        )
        ig = init(pg, gl(); dt = 0.1)
        @test_throws ArgumentError (ig.ps[gk] = 4.0)
        @test ig.ps[gk] == 0.5
    end
end

# `init = :steady` on every algorithm. Before the first window (and at
# `reinit!`) each such group's steady state is solved once by `QuasiSteady`, with the
# algorithm's `inner` (`:auto`: LatticePCG to rtol 1e-6 within 64 iterations); its refusals
# name `init`; a failed steady start ends the run. Before the fix (932c12ce): `init` is no
# keyword (the testset errors). Negative control (mutation, nc-12c-reinit): `reinit!`
# without the steady starts keeps the zero start (1 fails).
@testitem "`init = :steady`: every algorithm starts at the steady state" setup = [
    LP_quasisteady,
] tags = [
    :latticepde, :quasisteady,
] begin
    @testset "`init = :steady`: every algorithm starts at the steady state" begin
        sys = bsys(
            [D(bce) ~ bD * laplacian(bce) - bk * bce + x],
            [bc(0, x, y) ~ 0.0, bc(t, 0, y) ~ 1.0], [bD, bk]; T = 0.3
        )
        p = bown(sys)
        want = qs_hand(;
            K = (x, y) -> 0.3, k = (x, y) -> 2.0,
            f = (x, y) -> x, faces = Dict((1, -1) => (:dir, 1.0))
        )
        for (alg, dt) in (
                (ExplicitEuler(; init = :steady), 0.01),
                (BackwardEuler(; init = :steady), 0.1),
                (CrankNicolson(; init = :steady), 0.1), (BDF2(; init = :steady), 0.1), (
                    QuasiSteady(; init = :steady), 0.1,
                ),
            )
            ig = init(p, alg; dt)
            # (the default inner solver: rtol 1e-6; one solve, the group's operator being
            # exact)
            @test maximum(abs, ig.sol.u[1] .- want) < 1.0e-5 &&
                SciMLBase.check_error(ig) == ReturnCode.Success ||
                (println("12c init ", alg); false)
            @test LFB.field_stats(ig).solves == 1
            s = solve!(ig)
            # (it stays there)
            @test s.retcode == ReturnCode.Success && maximum(abs, s.u[end] .- want) < 1.0e-5
        end
        # without it, the start is the initial state; with a tight `inner` the start is the
        # hand steady state to 1e-9 (the algorithm's own `inner`)
        @test init(p, BackwardEuler(); dt = 0.1).sol.u[1] == zeros(48)
        @test maximum(
            abs,
            init(
                p, BackwardEuler(; init = :steady, linsolve = BTIGHT);
                dt = 0.1
            ).sol.u[1] .-
                want
        ) < 1.0e-9
        # the PCG count of `ExplicitEuler(init = :steady)` from zero (design §5): one
        # solve on the start's own runtime, 5 iterations of the default inner (rtol 1e-6) on
        # the CPU (the design's "6, as C7b": at most 6)
        ig = init(p, ExplicitEuler(; init = :steady); dt = 0.01)
        ne = LSB.iterations(only(ig.starts).cache.rows[1].solver)
        @test only(ig.starts).totals.solves == 1 && 1 <= ne <= 6 ||
            (println("EE start PCG ", ne); false)
        # `reinit!` solves again, at the current parameters
        ig = init(p, BackwardEuler(; init = :steady, linsolve = BTIGHT); dt = 0.1)
        solve!(ig)
        ig.ps[bk] = 3.0
        reinit!(ig)
        w3 = qs_hand(;
            K = (x, y) -> 0.3, k = (x, y) -> 3.0,
            f = (x, y) -> x, faces = Dict((1, -1) => (:dir, 1.0))
        )
        @test maximum(abs, ig.sol.u[1] .- w3) < 1.0e-9 && length(ig.sol.u) == 1
        # a steady row beside it starts at the steady state too (its `QuasiSteady` takes
        # `init`)
        ps = bown(
            bsys(
                [0 ~ bD * laplacian(bce) - bk * bce + x], [bc(t, 0, y) ~ 1.0], [
                    bD, bk,
                ]; T = 0.3
            )
        )
        @test maximum(
            abs,
            init(ps, QuasiSteady(; init = :steady, linsolve = BTIGHT); dt = 0.1).sol.u[1] .-
                want
        ) < 1.0e-9
        # the refusals: a growth has no stable steady state (named with `init` and its
        # route); the step alone is accepted
        pg = bown(
            bsys(
                [D(bce) ~ bD * laplacian(bce) + 0.5 * bce],
                [bc(0, x, y) ~ 0.0, bc(t, 0, y) ~ 1.0], [bD]; T = 0.3
            )
        )
        @test_throws ArgumentError init(pg, BackwardEuler(; init = :steady); dt = 0.1)
        @test init(pg, BackwardEuler(); dt = 0.1) isa Any
        @test_throws ArgumentError BackwardEuler(; init = :cold)
        # the canonical text: `init` only when set (a default keeps every fingerprint)
        @test LFB.canonical(BackwardEuler(; init = :steady)) !=
            LFB.canonical(BackwardEuler())
        @test LFB.canonical(ExplicitEuler(; init = :steady)) !=
            LFB.canonical(ExplicitEuler())
        # a steady start that fails (an island: the high strip has no decay and no fixed
        # value) ends the run before its first window, named
        @variables bdm(..)::Bool [input = true]
        bdme = bdm(t, x, y)
        dm = [j <= 2 || j >= 5 for i in 1:8, j in 1:6]
        si = PDESystem(
            [D(bce) ~ bD * laplacian(bce) + 1.0], [bc(0, x, y) ~ 0.0, bc(t, x, 0) ~ 0.0],
            bdom(1.0), [t, x, y], [bce, bdme], [bD];
            name = :island
        )
        pi = discretize(
            si, LatticeDiscretization(Grid(BDIMS); T = Float64, domain = bdm);
            inputs = [bdme => dm]
        )
        ig = @test_logs (
            :warn,
            r"field `bc`: the solve failed in the steady start \(`init = :steady`, t = 0\.0\)",
        ) match_mode = :any init(
            pi,
            BackwardEuler(; init = :steady, linsolve = LatticePCG(; maxiters = 16));
            dt = 0.1
        )
        @test ig.retcode == ReturnCode.ConvergenceFailure
        s = solve!(ig)
        @test s.retcode == ReturnCode.ConvergenceFailure && s.t == [0.0]
    end
end

@testitem "steady rows `0 ~ rhs`: the rate row's solve, QuasiSteady only, the steady \
    groups first" setup = [LP_quasisteady] tags = [
    :latticepde, :quasisteady,
] begin
    @testset "steady rows `0 ~ rhs`: the rate row's solve, QuasiSteady only, the steady \
        groups first" begin
        alg = QuasiSteady(; linsolve = BTIGHT)
        s0 = bsys(
            [0 ~ bD * laplacian(bce) - bk * bce + x + t], [bc(t, 0, y) ~ 1.0], [
                bD, bk,
            ]; T = 0.3
        )
        s1 = bsys(
            [D(bce) ~ bD * laplacian(bce) - bk * bce + x + t],
            [bc(0, x, y) ~ 0.0, bc(t, 0, y) ~ 1.0], [bD, bk]; T = 0.3
        )
        p0, p1 = bown(s0), bown(s1)
        @test p0.group.spec.steady == ["bc"] && !p0.group.spec.timefree &&
            p1.group.spec.steady == String[]
        # the choice shown: an accessor and the problem's display
        @test steady_fields(p0) == ["bc"] && steady_fields(p1) == String[]
        @test occursin(
            "steady rows `0 ~ rhs` (`QuasiSteady`), solved for `bc`",
            sprint(show, MIME"text/plain"(), p0)
        )
        r0 = solve(p0, alg; dt = 0.1)
        # (the cold start: 0)
        @test r0.u == solve(p1, alg; dt = 0.1).u && r0.retcode == ReturnCode.Success
        # (`QuasiSteady` by default)
        @test solve(p0, QuasiSteady(; linsolve = BTIGHT); dt = 0.1).u == r0.u
        @test_throws ArgumentError solve(p0, BackwardEuler(); dt = 0.1)
        # a transient field `bo` (first in dvs) reads the steady `bc`: `bc` takes
        # `QuasiSteady` at the window of the given algorithm and steps first; a pair for it
        # must be `QuasiSteady`
        sm = bsys(
            [
                D(boe) ~ 0.1 * laplacian(boe) - boe + bce, 0 ~
                    bD * laplacian(bce) - bk * bce +
                    x,
            ], [
                bc(t, 0, y) ~ 1.0, bo(0, x, y) ~ 0.0,
            ],
            [bD, bk]; T = 0.3, dvs = [boe, bce]
        )
        pm = qown(sm)
        for a in (
                BackwardEuler(), FieldGroups(boe => BackwardEuler()),
                FieldGroups(bce => QuasiSteady(), boe => BackwardEuler()),
            )
            ig = init(pm, a; dt = 0.1)
            @test [(typeof(r.alg), r.keys) for r in ig.runtimes] ==
                [(QuasiSteady, ["bc"]), (BackwardEuler, ["bo"])]
        end
        @test_throws ArgumentError init(
            pm, FieldGroups(bce => BackwardEuler(), boe => BackwardEuler()); dt = 0.1
        )
        # the steady field is solved first in each window: `bo` reads this window's `bc`
        ig = init(pm, BackwardEuler(; linsolve = BTIGHT); dt = 0.1)
        step!(ig)
        want = qs_hand(;
            K = (x, y) -> 0.3, k = (x, y) -> 2.0,
            f = (x, y) -> x, faces = Dict((1, -1) => (:dir, 1.0))
        )
        @test maximum(abs, vec(ig[bce]) .- want) < 1.0e-9
        @test maximum(abs, vec(ig[boe])) > 0
        # the field a row is solved for: the one its operator acts on; a row that reads no
        # free field
        @variables qf(..)
        qfe = qf(t, x, y)
        sw = PDESystem(
            [0 ~ 0.1 * laplacian(qfe) - qfe + bce, 0 ~ bD * laplacian(bce) - bk * bce + x],
            [
                bc(t, 0, y) ~
                    1.0,
            ], bdom(0.3), [
                t, x, y,
            ],
            [bce, qfe], [bD, bk]; name = :which
        )
        @test last(LatticePDE.steady_rows(sw)) == ["qf", "bc"] &&
            qown(sw).group.spec.steady == ["bc", "qf"]   # (rows; state order)
        @test_throws ArgumentError qown(
            bsys(
                [0 ~ x - 1, D(bce) ~ -bce], [bc(0, x, y) ~ 0.0], Any[]; dvs = [bce]
            )
        )
        # a row's sign does not matter: the elliptic form `0 ~ k c − D laplacian(c) − s` is
        # the row with its operator a diffusion, and a local row `0 ~ qf − c²` (for `qf`) is
        # `0 ~ c² − qf`; a row whose operator and local term disagree is refused as
        # indefinite. Before the fix (e7068add): "the diffusion coefficient … is negative",
        # and the growth refusal
        se = bsys(
            [0 ~ bk * bce - bD * laplacian(bce) - x], [bc(t, 0, y) ~ 1.0], [bD, bk];
            T = 0.3
        )
        re = solve(bown(se), alg; dt = 0.1)
        want = qs_hand(;
            K = (x, y) -> 0.3, k = (x, y) -> 2.0,
            f = (x, y) -> x, faces = Dict((1, -1) => (:dir, 1.0))
        )
        @test re.retcode == ReturnCode.Success &&
            maximum(abs, re[bce, 2] .- reshape(want, BDIMS)) < 1.0e-9
        @test LatticePDE.steady_sign(
            unwrap(bk * bce - bD * laplacian(bce) - x),
            unwrap(bce)
        ) ==
            -1 &&
            LatticePDE.steady_sign(
            unwrap(bD * laplacian(bce) - bk * bce + x),
            unwrap(bce)
        ) ==
            1
        @variables qf2(..)
        qe2 = qf2(t, x, y)
        sq = PDESystem(
            [D(bce) ~ 0.1 * laplacian(bce) - bce + 1, 0 ~ qe2 - bce^2], [bc(0, x, y) ~ 0.5],
            bdom(0.3), [
                t, x, y,
            ], [bce, qe2],
            Any[]; name = :sq
        )
        rq = solve(qown(sq), BackwardEuler(; linsolve = BTIGHT); dt = 0.1, saveat = 0.1)
        @test rq.retcode == ReturnCode.Success
        # (`qf2` is solved at each window's start, from the `bc` of that start: the window
        # before the end)
        @test maximum(abs, rq[qe2, length(rq.t)] .- rq[bce, length(rq.t) - 1] .^ 2) < 1.0e-6
        @test_throws ArgumentError init(
            bown(
                bsys(
                    [0 ~ -bD * laplacian(bce) - bk * bce + x], [bc(t, 0, y) ~ 1.0], [
                        bD, bk,
                    ]
                )
            ),
            alg;
            dt = 0.1
        )
        # an OrdinaryDiffEq solver: a steady row is a row of the mass matrix (base: "the
        # steady rows of `bc` make the system a DAE", refused); the field algorithms step
        # the same problem
        psm = discretize(sm, LatticeDiscretization(Grid(BDIMS); T = Float64))
        @test psm isa SciMLBase.ODEProblem &&
            count(iszero, psm.f.mass_matrix.diag) == prod(BDIMS)
    end
end

@testitem "a steady row's time source is read at the window's start" setup = [
    LP_quasisteady,
] tags = [
    :latticepde, :quasisteady,
] begin
    @testset "a steady row's time source is read at the window's start" begin
        # `0 = 0.1 Δu − u + f(t)` with `u = (1 + t) sin(πx) sin(πy)` (zero faces) on 32²:
        # window k solves at its start time t_{k−1}, so the field is the solution at
        # t_{k−1}, not at t_k
        n = 32
        f = (1 + t) * (0.1 * 2π^2 + 1) * sin(π * x) * sin(π * y)
        faces = [bc(t, 0, y) ~ 0.0, bc(t, 1, y) ~ 0.0, bc(t, x, 0) ~ 0.0, bc(t, x, 1) ~ 0.0]
        p = discretize(
            bsys([0 ~ 0.1 * laplacian(bce) - bce + f], faces, Any[]; T = 1.0, dvs = [bce]),
            LatticeDiscretization(Grid((n, n)); T = Float64)
        )
        ig = init(
            p, QuasiSteady(;
                linsolve = LatticePCG(; reltol = 1.0e-12, maxiters = 200)
            ); dt = 0.5
        )
        xs = [(i - 0.5) / n for i in 1:n, j in 1:n]
        ys = [(j - 0.5) / n for i in 1:n, j in 1:n]
        u(tt) = (1 + tt) .* sin.(π .* xs) .* sin.(π .* ys)
        for k in 1:2
            step!(ig)
            e0, e1 = maximum(abs, ig[bce] .- u(0.5(k - 1))),
                maximum(abs, ig[bce] .- u(0.5k))
            @test e0 < 2.0e-3 && e1 > 0.4 ||
                (println("12b start-time read ", (k, e0, e1)); false)
        end
    end
end

@testitem "a system with no time: one steady solve from a cold start; Helmholtz is order \
    2" setup = [LP_quasisteady] tags = [
    :latticepde, :quasisteady,
] begin
    @testset "a system with no time: one steady solve from a cold start; Helmholtz is \
        order 2" begin
        @variables fc(..)
        fce = fc(x, y)
        fdom = [x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
        sf = PDESystem(
            [0 ~ bD * laplacian(fce) - bk * fce + x], [fc(0, y) ~ 1.0],
            fdom, [x, y], [fce], [bD, bk]; name = :free
        )
        pf = qown(sf)
        @test pf isa LFP.FieldProblem && pf.tspan == (0.0, 0.0) && pf.group.spec.timefree &&
            pf.group.spec.steady == ["fc"]
        # (the cold start)
        @test all(iszero, pf.u0)
        s = solve(pf)
        want = qs_hand(;
            K = (x, y) -> 0.3, k = (x, y) -> 2.0,
            f = (x, y) -> x, faces = Dict((1, -1) => (:dir, 1.0))
        )
        @test s.retcode == ReturnCode.Success && s.t == [0.0] && length(s.u) == 1 &&
            s.stats.solves == 1
        @test maximum(abs, s.u[1] .- want) < 1.0e-5 * maximum(abs, want)
        # (the time-free symbol reads)
        @test s[fce, 1] == s[:fc, 1] == reshape(s.u[1], BDIMS)
        @test maximum(abs, solve(pf, QuasiSteady(; linsolve = BTIGHT)).u[1] .- want) <
            1.0e-9
        # what a steady system refuses: stepping, a window, a time span, save keywords, a
        # time stepper
        @test_throws ArgumentError init(pf)
        @test_throws ArgumentError solve(pf, QuasiSteady(); dt = 0.1)
        @test_throws ArgumentError solve(pf; saveat = 0.1)
        @test_throws ArgumentError solve(pf, BackwardEuler(); dt = 0.1)
        @test_throws ArgumentError discretize(
            sf, LatticeDiscretization(Grid(BDIMS); T = Float64); tspan = (0, 1)
        )
        # the `LinearProblem` of a linear system with no time, `A u = b` at the steady state
        # (base: `problem = :ode` gave a `SteadyStateProblem`)
        ps = discretize(sf, LatticeDiscretization(Grid(BDIMS); T = Float64))
        @test ps isa SciMLBase.LinearProblem
        # SciML's `hasTime` matches the problem type: `Val(false)` without a time
        @test !(
            LFP.lattice_metadata(ps) isa
                SciMLBase.AbstractDiscretizationMetadata{Val(true)}
        )
        @test maximum(abs, ps.A * want .- ps.b) < 1.0e-10
        # Helmholtz `0 = Δu − 4u + (2π² + 4) sin(πx) sin(πy)` with zero faces: order 2 over
        # three grids
        errs = map((16, 32, 64)) do n
            sh = PDESystem(
                [0 ~ laplacian(fce) - 4 * fce + (2π^2 + 4) * sin(π * x) * sin(π * y)],
                [fc(0, y) ~ 0.0, fc(1, y) ~ 0.0, fc(x, 0) ~ 0.0, fc(x, 1) ~ 0.0], fdom, [
                    x, y,
                ], [fce], Any[]; name = :helm
            )
            r = solve(
                discretize(sh, LatticeDiscretization(Grid((n, n)); T = Float64)),
                QuasiSteady(; linsolve = LatticePCG(; reltol = 1.0e-12, maxiters = 200))
            )
            xs = [(i - 0.5) / n for i in 1:n, j in 1:n]
            ys = [(j - 0.5) / n for i in 1:n, j in 1:n]
            maximum(abs, r[fce, 1] .- sin.(π .* xs) .* sin.(π .* ys))
        end
        ord = log2.(errs[1:(end - 1)] ./ errs[2:end])
        @test all(o -> abs(o - 2) < 0.1, ord) ||
            (println("Helmholtz orders ", ord, " errors ", errs); false)  # (1.99, 2.00)
    end
end

# The boundary and input capabilities of the time-dependent solves, through the steady solve
# of a system with no time, each against the hand steady matrix to 1e-9: a Robin face of
# each sign, a field face with a face-Dirichlet value, a mask value field, an input bound by
# aliasing (a new input changes the next solve)
@testitem "the solver capabilities in a system with no time" setup = [
    LP_quasisteady,
] tags = [
    :latticepde, :quasisteady,
] begin
    @testset "the solver capabilities in a system with no time" begin
        @variables zc(..) zq(..)::Int32 [input = true]
        zce, zqe = zc(x, y), zq(x, y)
        fdom = [x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
        function free(eqs, bcs, ps; q = false)
            return discretize(
                PDESystem(
                    eqs, bcs, fdom, [x, y], q ? [zce, zqe] : [zce], ps; name = :free2
                ),
                LatticeDiscretization(Grid(BDIMS); T = Float64); (
                    if q
                        (;
                            inputs = [zqe => BKIND],
                        )
                    else
                        (;)
                    end
                )...
            )
        end
        alg = QuasiSteady(; linsolve = BTIGHT)
        xs = bxs()
        for β in (-1.0, 1.0)
            pf = free(
                [0 ~ bD * laplacian(zce) - bk * zce + x],
                [2.0 * zc(x, 0) + β * Differential(y)(zc(x, 0)) ~ bg], [bD, bk, bg]
            )
            want = qs_hand(;
                K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x,
                faces = Dict((2, -1) => (:robin, 2.0, β, 0.5))
            )
            s = solve(pf, alg)
            @test s.retcode == ReturnCode.Success &&
                maximum(abs, s.u[1] .- want) < 1.0e-9 ||
                (println("free robin ", β); false)
        end
        pf = free(
            [0 ~ DivKGrad(:harmonic)(1 + x * y, zce) - bk * zce], [
                zc(0, y) ~
                    1.0 + y,
            ], [bk]
        )
        want = qs_hand(;
            K = (x, y) -> 1 + x * y, k = (x, y) -> 2.0,
            faces = Dict((1, -1) => (:dir, (x, y) -> 1.0 + y))
        )
        @test maximum(abs, solve(pf, alg).u[1] .- want) < 1.0e-9
        pf = free(
            [0 ~ bD * laplacian(zce) - bk * zce], [zce ~ masked(zqe == 2, 1 + x)], [
                bD, bk,
            ]; q = true
        )
        mk = vec(BKIND .== 2)
        u = solve(pf, alg).u[1]
        want = qs_hand(;
            K = (x, y) -> 0.3, k = (x, y) -> 2.0, mask = mk, mval = vec(
                1 .+
                    xs
            )
        )
        @test maximum(abs, u .- want) < 1.0e-9 && all(u[mk] .== vec(1 .+ xs)[mk])
        pf = free(
            [0 ~ value_at(bW, zqe) * laplacian(zce) - bk * zce + 1], Equation[], [
                bW, bk,
            ]; q = true
        )
        function hand(Kq)
            return qs_hand(;
                K = (x, y) -> 1.0, m = (i, j) -> (0.0, 0.5, 2.0)[Kq[i, j] + 1],
                k = (x, y) -> 2.0, f = (x, y) -> 1.0
            )
        end
        @test maximum(abs, solve(pf, alg).u[1] .- hand(BKIND)) < 1.0e-9
        K2 = Int32[(i * j) % 2 for i in 1:8, j in 1:6]
        @test maximum(abs, solve(remake(pf; inputs = [zqe => K2]), alg).u[1] .- hand(K2)) <
            1.0e-9
    end
end
