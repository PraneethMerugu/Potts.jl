# `BackwardEuler` in standalone LatticePDE for linear groups. The rate
# program is the residual (`fuse_residual`), the operator `J̃` comes from the linearity table
# (`OperatorSpec`, built at the first implicit use only), and each substep solves
# `(I/h − J̃) δ = G(uⁿ)`, `u = uⁿ + δ` at `tⁿ⁺¹`. The tests compare one window with the hand BE
# matrix of the same stencil (faces, ghosts, masks), the order with the exact semi-discrete
# solution, a manufactured solution, a stiff case and OrdinaryDiffEq's `ImplicitEuler`.
# Before the fix (437a84ef): `BackwardEuler` is not defined (every testset
# errors); the negative controls below are mutations of this tree.

@testsetup module LP_implicit
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables, Differential, PDESystem,
    System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex, Shift, Pre,
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
function r2m1_prob(W, rate)
    @variables r2q(..)::Int32 [input = true]
    r2qe = r2q(t, x, y)
    kind = Int32[(i + j) % 2 for i in 1:16, j in 1:16]
    @parameters r2W[1:2] = W
    sys = PDESystem([D(bce) ~ rate(r2W, r2qe)], [bc(0, x, y) ~ x], bdom(0.5), [t, x, y], [bce, r2qe], [r2W]; name = :r2)
    return sys, discretize(sys, LatticeDiscretization(Grid((16, 16)); T = Float64); inputs = [r2qe => kind]), r2qe, kind
end
include("shared/export_all.jl")
end

@testitem "one BackwardEuler window equals the hand BE matrix" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "one BackwardEuler window equals the hand BE matrix" begin
        h = 0.05
        alg = BackwardEuler(; linsolve = BTIGHT)
        # a numeric operator: diffusion, decay, a source, a Dirichlet face, a mask with its value
        p = bown(
            bsys(
                [D(bce) ~ bD * laplacian(bce) - bk * bce + x], [
                    bc(0, x, y) ~ x * y, bc(t, 0, y) ~ 1.0,
                    bce ~ masked(bqe == 2, 1.5),
                ], [bD, bk]
            )
        )
        ig, u0, u = be_window(p, alg; dt = h)
        want = be_hand(
            u0, h; K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x, faces = Dict((1, -1) => (:dir, 1.0)),
            mask = vec(BKIND .== 2), mval = fill(1.5, 48)
        )
        @test maximum(abs, u .- want) < 1.0e-9
        rt = only(ig.runtimes)
        @test rt.cache.newton == 1 && rt.cache.exact && SciMLBase.check_error(ig) == ReturnCode.Success
        @test all(u[vec(BKIND .== 2)] .== 1.5)                     # the mask value written back (SD-11)
        @test rt.totals.solves == 1                                # one solve per substep (exact operator)
    end
end

@testitem "the solver capabilities in a BackwardEuler group" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "the solver capabilities in a BackwardEuler group" begin
        h = 0.05
        xs, ys = bxs(), bys()
        # a Robin face, positive part (α and β of the same sign with the outward normal)
        p = bown(
            bsys(
                [D(bce) ~ bD * laplacian(bce) - bk * bce + x], [bc(0, x, y) ~ 0.0, 2.0 * bc(t, x, 0) - Differential(y)(bc(t, x, 0)) ~ bg],
                [bD, bk, bg]
            )
        )
        ig, u0, u = be_window(p, BackwardEuler(; linsolve = BTIGHT); dt = h)
        want = be_hand(u0, h; K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x, faces = Dict((2, -1) => (:robin, 2.0, -1.0, 0.5)))
        @test maximum(abs, u .- want) < 1.0e-10 && only(ig.runtimes).cache.newton == 1
        # opposite signs: the negative part stays in the residual (a defect correction), so the
        # automatic Newton count is more than one (from its bound `w |d⁻|`, S1: 5 here); `LatticeNewton`
        # converges it to the hand matrix
        p = bown(
            bsys(
                [D(bce) ~ bD * laplacian(bce) - bk * bce + x], [bc(0, x, y) ~ 0.0, 2.0 * bc(t, x, 0) + Differential(y)(bc(t, x, 0)) ~ bg],
                [bD, bk, bg]
            )
        )
        want = be_hand(zeros(48), h; K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x, faces = Dict((2, -1) => (:robin, 2.0, 1.0, 0.5)))
        ig, _, u4 = be_window(p, BackwardEuler(; linsolve = BTIGHT); dt = h)
        @test only(ig.runtimes).cache.newton == 5 && only(ig.runtimes).cache.seen && maximum(abs, u4 .- want) < 1.0e-3
        ig, _, u = be_window(p, BackwardEuler(; nlsolve = LatticeNewton(; max_iter = 30), linsolve = BTIGHT); dt = h)
        @test maximum(abs, u .- want) < 1.0e-3 && only(ig.runtimes).totals.solves < 30 && only(ig.runtimes).totals.newton_budget == 0
        # a field face coefficient (`DivKGrad(k(x, y), c)`) with a face-Dirichlet value that varies along the face
        p = bown(bsys([D(bce) ~ DivKGrad(:harmonic)(1 + x * y, bce) - bk * bce], [bc(0, x, y) ~ 0.0, bc(t, 0, y) ~ 1.0 + y], [bk]))
        ig, u0, u = be_window(p, BackwardEuler(; linsolve = BTIGHT); dt = h)
        rt = only(ig.runtimes)
        @test rt.cache.rows[1].op.field && rt.cache.op.jac !== nothing
        want = be_hand(u0, h; K = (x, y) -> 1 + x * y, k = (x, y) -> 2.0, faces = Dict((1, -1) => (:dir, (x, y) -> 1.0 + y)))
        @test maximum(abs, u .- want) < 1.0e-10
        # a mask whose value is a field (`masked(pred, 1 + x)`): each masked site takes its own value
        p = bown(bsys([D(bce) ~ bD * laplacian(bce) - bk * bce], [bc(0, x, y) ~ 0.0, bce ~ masked(bqe == 2, 1 + x)], [bD, bk]))
        ig, u0, u = be_window(p, BackwardEuler(; linsolve = BTIGHT); dt = h)
        mk = vec(BKIND .== 2)
        want = be_hand(u0, h; K = (x, y) -> 0.3, k = (x, y) -> 2.0, mask = mk, mval = vec(1 .+ xs))
        @test maximum(abs, u .- want) < 1.0e-10 && all(u[mk] .== vec(1 .+ xs)[mk])
        # the face and mask value fields stepped explicitly too: one ExplicitEuler window is
        # `u0 + h r(u0)` off the mask, the mask value on it
        p = bown(
            bsys(
                [D(bce) ~ DivKGrad(:harmonic)(1 + x * y, bce) - bk * bce],
                [bc(0, x, y) ~ x, bc(t, 0, y) ~ 1.0 + y, bce ~ masked(bqe == 2, 1 + x)], [bk]
            )
        )
        ig = init(p, ExplicitEuler(; substeps = 1); dt = 1.0e-3)
        u0 = copy(vec(ig[bce]))
        step!(ig)
        L, bb = hand_rate(; K = (x, y) -> 1 + x * y, k = (x, y) -> 2.0, faces = Dict((1, -1) => (:dir, (x, y) -> 1.0 + y)))
        want = ifelse.(mk, vec(1 .+ xs), u0 .+ 1.0e-3 .* (L * u0 .+ bb))
        @test u0[mk] == vec(1 .+ xs)[mk] && maximum(abs, vec(ig[bce]) .- want) < 1.0e-12
        # an input bound by aliasing: the operator reads the problem's own input array, and a write
        # of the input between windows changes the next solve (no copy; the warm window 0 B)
        p = bown(bsys([D(bce) ~ value_at(bW, bqe) * laplacian(bce) - bk * bce + 1], [bc(0, x, y) ~ 0.0], [bW, bk]))
        ig = init(p, BackwardEuler(; linsolve = BTIGHT); dt = h, save_everystep = false)
        rt = only(ig.runtimes)
        r = rt.cache.rows[1]
        qid = fieldid(rt.program, "bq")
        jst = rt.cache.jac[1].launches                      # (the operator's launches read the store's array)
        @test LSB.field(r.solver, "in.f") === r.f && LSB.field(r.solver, "s") === r.s && r.f !== nothing
        @test any(l -> any(a -> a === rt.store.bufs[qid][1], Iterators.flatten(l.launch.params[2][1])), jst)
        step!(ig); step!(ig)
        @test bwarm(ig) == 0
        K2 = Int32[(i * j) % 2 for i in 1:8, j in 1:6]
        u1 = copy(vec(ig[bce]))
        ig[bqe] = K2
        step!(ig)
        want = be_hand(u1, h; K = (x, y) -> 1.0, m = (i, j) -> (0.0, 0.5, 2.0)[K2[i, j] + 1], k = (x, y) -> 2.0, f = (x, y) -> 1.0)
        @test maximum(abs, vec(ig[bce]) .- want) < 1.0e-10
        @test bwarm(ig) == 0
    end
end

@testitem "SiteDiffusion rows (row scaling; m = 0 rows in two stages)" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "SiteDiffusion rows (row scaling; m = 0 rows in two stages)" begin
        h = 0.05
        # `value_at(W, q) laplacian(c)`: the row scaled by 1/m keeps the faces symmetric (q = 0 reads 0: m = 0 rows)
        p = bown(bsys([D(bce) ~ value_at(bW, bqe) * laplacian(bce) - bk * bce + 1], [bc(0, x, y) ~ x], [bW, bk]))
        ig, u0, u = be_window(p, BackwardEuler(; linsolve = BTIGHT); dt = h)
        mm = (i, j) -> (0.0, 0.5, 2.0)[BKIND[i, j] + 1]
        want = be_hand(u0, h; m = mm, k = (x, y) -> 2.0, f = (x, y) -> 1.0)
        @test maximum(abs, u .- want) < 1.0e-12
        @test only(ig.runtimes).cache.rows[1].op.scaled && only(ig.runtimes).cache.exact
        # a multiplier that is 0 on some rows (`ifelse(kind == 1, 0, D)`): the two-stage solve
        p = bown(bsys([D(bce) ~ ifelse(bqe == 1, 0.0, 0.7) * laplacian(bce) - 50.0 * bce], [bc(0, x, y) ~ 1.0 + x], Any[]))
        ig, u0, u = be_window(p, BackwardEuler(; linsolve = BTIGHT); dt = 0.1)
        want = be_hand(u0, 0.1; m = (i, j) -> BKIND[i, j] == 1 ? 0.0 : 0.7, k = (x, y) -> 50.0)
        @test maximum(abs, u .- want) < 1.0e-12
        # (the pinned-row rule `δ = G h` is a forward Euler step there: off by about 4 at decay 50)
        @test maximum(abs, u[vec(BKIND .== 1)] .- (u0[vec(BKIND .== 1)] ./ (1 + 0.1 * 50))) < 1.0e-12
        # `m laplacian(c) + D laplacian(c)` is `(m + D) laplacian(c)`, exact
        p = bown(bsys([D(bce) ~ value_at(bW, bqe) * laplacian(bce) + bD * laplacian(bce) - bk * bce], [bc(0, x, y) ~ x], [bW, bD, bk]))
        ig, u0, u = be_window(p, BackwardEuler(; linsolve = BTIGHT); dt = h)
        want = be_hand(u0, h; m = (i, j) -> mm(i, j) + 0.3, k = (x, y) -> 2.0)
        @test maximum(abs, u .- want) < 1.0e-12 && only(ig.runtimes).cache.exact
        # two face coefficients: one stays in the residual with its bound, the operator is inexact
        # (more Newton iterations, from the bound, which converge to the BE step)
        p = bown(bsys([D(bce) ~ value_at(bW, bqe) * laplacian(bce) + bD * DivKGrad(:harmonic)(1 + x, bce) - bk * bce], [bc(0, x, y) ~ x], [bW, bD, bk]))
        ig = init(p, BackwardEuler(; nlsolve = LatticeNewton(; max_iter = 40), linsolve = BTIGHT); dt = h)
        rt = only(ig.runtimes)
        @test !rt.cache.op.rows[1].exact && !isempty(rt.cache.op.rows[1].inexact)
        @test init(p, BackwardEuler(); dt = h).runtimes[1].cache.newton == 10 && init(p, BackwardEuler(); dt = h).runtimes[1].cache.seen
    end
end

@testitem "order 1, the manufactured solution, the stage tⁿ⁺¹" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "order 1, the manufactured solution, the stage tⁿ⁺¹" begin
        # the discrete sine is an eigenvector of the lattice Laplacian with Dirichlet 0 faces: the
        # semi-discrete solution is `e^{D λ t} u0`, so the BE error is the time error alone
        n = 16
        λ = 2 * (2cos(π / n) - 2) * n^2
        dirs = [bc(t, 0, y) ~ 0.0, bc(t, 1, y) ~ 0.0, bc(t, x, 0) ~ 0.0, bc(t, x, 1) ~ 0.0]
        sys = bsys([D(bce) ~ bD * laplacian(bce)], [bc(0, x, y) ~ sin(π * x) * sin(π * y); dirs], [bD]; T = 0.4, dvs = [bce])
        p = discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64))
        u0 = [sin(π * (i - 0.5) / n) * sin(π * (j - 0.5) / n) for i in 1:n, j in 1:n]
        err(dt) = maximum(abs, blast(solve(p, BackwardEuler(; linsolve = BTIGHT); dt)) .- exp(0.3λ * 0.4) .* u0)
        es = [err(0.4 / 2^k) for k in 2:5]
        ord = log2.(es[1:(end - 1)] ./ es[2:end])
        @test all(o -> abs(o - 1) < 0.1, ord)
        # exactly the BE map: (1 − h D λ)^{-m}
        @test maximum(abs, blast(solve(p, BackwardEuler(; linsolve = BTIGHT); dt = 0.05)) .- (1 - 0.05 * 0.3λ)^-8 .* u0) < 1.0e-12
        # a manufactured solution `u = e^{−t} sin(πx) sin(πy) + t`: its source and the face value `t`
        # are read at tⁿ⁺¹; observed order 1 over four dt (the space error is below the time error)
        m = 64
        src = -exp(-t) * sin(π * x) * sin(π * y) + 1 + 2π^2 * 0.1 * exp(-t) * sin(π * x) * sin(π * y)
        faces = [bc(t, 0, y) ~ t, bc(t, 1, y) ~ t, bc(t, x, 0) ~ t, bc(t, x, 1) ~ t]
        ms = bsys([D(bce) ~ 0.1 * laplacian(bce) + src], [bc(0, x, y) ~ sin(π * x) * sin(π * y); faces], Any[]; T = 1.0, dvs = [bce])
        pm = discretize(ms, LatticeDiscretization(Grid((m, m)); T = Float64))
        exact = [exp(-1.0) * sin(π * (i - 0.5) / m) * sin(π * (j - 0.5) / m) + 1.0 for i in 1:m, j in 1:m]
        em = [maximum(abs, blast(solve(pm, BackwardEuler(; linsolve = BTIGHT); dt = 0.1 / 2^k)) .- exact) for k in 0:3]
        om = log2.(em[1:(end - 1)] ./ em[2:end])
        @test all(o -> abs(o - 1) < 0.1, om)
        # one window at the stage tⁿ⁺¹: the time-dependent source and face value of the hand matrix
        # at t = h (at t = 0, the wrong stage, it is off by about h)
        h = 0.1
        pm8 = discretize(ms, LatticeDiscretization(Grid(BDIMS); T = Float64))
        ig, u0, u = be_window(pm8, BackwardEuler(; linsolve = BTIGHT); dt = h)
        s1(xx, yy, tt) = -exp(-tt) * sin(π * xx) * sin(π * yy) + 1 + 2π^2 * 0.1 * exp(-tt) * sin(π * xx) * sin(π * yy)
        fc(tt) = Dict((a, s) => (:dir, tt) for a in 1:2, s in (-1, 1))
        want = be_hand(u0, h; K = (x, y) -> 0.1, f = (xx, yy) -> s1(xx, yy, h), faces = fc(h))
        wrong = be_hand(u0, h; K = (x, y) -> 0.1, f = (xx, yy) -> s1(xx, yy, 0.0), faces = fc(0.0))
        @test maximum(abs, u .- want) < 1.0e-9 && maximum(abs, u .- wrong) > 1.0e-2
    end
end

@testitem "a stiff case, OrdinaryDiffEq's ImplicitEuler" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "a stiff case, OrdinaryDiffEq's ImplicitEuler" begin
        # D h/dx² = 10⁴: BackwardEuler stays bounded and monotone; ExplicitEuler with one substep
        # (forced) blows up (`Unstable`)
        n = 16
        step0 = PDESystem(
            [D(bce) ~ bD * laplacian(bce)], [bc(0, x, y) ~ ifelse(x < 0.5, 1.0, 0.0)], bdom(80 * 1.0e4 / (0.3 * n^2)),
            [t, x, y], [bce], [bD]; name = :stiff
        )
        p = discretize(step0, LatticeDiscretization(Grid((n, n)); T = Float64))
        hs = 1.0e4 / (0.3 * n^2)
        s = solve(p, BackwardEuler(); dt = hs, saveat = 8hs)
        @test s.retcode == ReturnCode.Success && all(u -> all(v -> -1.0e-6 <= v <= 1 + 1.0e-6, u), s.u)
        @test all(k -> maximum(s.u[k + 1]) <= maximum(s.u[k]) + 1.0e-6 && minimum(s.u[k + 1]) >= minimum(s.u[k]) - 1.0e-6, 1:(length(s.u) - 1))
        ig = init(p, ExplicitEuler(); dt = hs)
        ig.substeps = 1
        solve!(ig)
        @test ig.retcode == ReturnCode.Unstable
        # the `:ode` path with OrdinaryDiffEq's ImplicitEuler (fixed steps, tight Newton) at equal dt
        sx = bsys(
            [D(bce) ~ bD * laplacian(bce) - bk * bce + sin(3t) * x], [bc(0, x, y) ~ x * y, bc(t, 0, y) ~ 1.0], [bD, bk];
            T = 0.4, dvs = [bce]
        )
        po = discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64))
        # (the Newton tolerance follows abstol and reltol, 1e-12; the rate is linear, so a Newton step is exact)
        so = solve(po, ImplicitEuler(); dt = 0.05, adaptive = false, abstol = 1.0e-12, reltol = 1.0e-12)
        sb = solve(
            discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64)),
            BackwardEuler(; linsolve = BTIGHT); dt = 0.05
        )
        @test maximum(abs, vec(blast(sb)) .- so.u[end]) < 1.0e-8
    end
end

@testitem "nlsolve = nothing, the operator built only for implicit groups (S12)" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "nlsolve = nothing, the operator built only for implicit groups (S12)" begin
        p = bown(bsys([D(bce) ~ bD * laplacian(bce) - bk * bce], [bc(0, x, y) ~ x], [bD, bk]))
        b0 = LatticePDE.OPERATOR_BUILDS[]
        solve(p, ExplicitEuler(); dt = 0.01)
        @test LatticePDE.OPERATOR_BUILDS[] == b0                   # an explicit group builds none
        ig = init(p, BackwardEuler(); dt = 0.01)
        @test LatticePDE.OPERATOR_BUILDS[] == b0 + 1 && only(ig.runtimes).cache.newton == 1
        init(p, BackwardEuler(); dt = 0.02)
        @test LatticePDE.OPERATOR_BUILDS[] == b0 + 1               # once per group
        # an acyclic pair in one group (c reads o): one Newton step in topological order is exact
        p2 = discretize(
            bsys(
                [D(bce) ~ bD * laplacian(bce) - bk * bce + 0.7 * boe, D(boe) ~ 0.5 * laplacian(boe) - boe + x],
                [bc(0, x, y) ~ 0.0, bo(0, x, y) ~ 0.0], [bD, bk]; dvs = [bce, boe]
            ), LatticeDiscretization(Grid(BDIMS); T = Float64)
        )
        ig = init(p2, BackwardEuler(; linsolve = BTIGHT); dt = 0.1)
        @test only(ig.runtimes).cache.newton == 1 && [r.key for r in only(ig.runtimes).cache.rows] == ["bo", "bc"]
        step!(ig)
        o1 = be_hand(zeros(48), 0.1; K = (x, y) -> 0.5, k = (x, y) -> 1.0, f = (x, y) -> x)
        c1 = be_hand(
            zeros(48), 0.1; K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = let o = reshape(o1, BDIMS)
                (xx, yy) -> 0.7 * o[round(Int, xx * 8 + 0.5), round(Int, yy * 6 + 0.5)]
            end
        )
        @test maximum(abs, vec(ig[boe]) .- o1) < 1.0e-10 && maximum(abs, vec(ig[bce]) .- c1) < 1.0e-10
        # the substep count: 1, raised only by a positive local derivative (`+ g c`: n ≥ ⌈2 dt g⌉)
        @test init(p, BackwardEuler(); dt = 0.5).substeps == 1
        pg = bown(bsys([D(bce) ~ bD * laplacian(bce) + bk * bce], [bc(0, x, y) ~ x], [bD, bk]))
        @test init(pg, BackwardEuler(); dt = 0.5).substeps == 2 && init(pg, BackwardEuler(; substeps = 5); dt = 0.5).substeps == 5
    end
end

@testitem "messages, the `:ode` path, `show`" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "messages, the `:ode` path, `show`" begin
        function e(f)
            return try
                f(); ""
            catch err
                err isa ArgumentError ? err.msg : sprint(showerror, err)
            end
        end
        p = bown(bsys([D(bce) ~ bD * laplacian(bce)], [bc(0, x, y) ~ x], [bD]))
        # M1: a linear solver where a field solver goes names `BackwardEuler(; linsolve = …)`, which works
        m = e(() -> solve(p, LatticePCG(; maxiters = 12)))
        @test occursin("give it to one, `BackwardEuler(; linsolve = LatticePCG(; maxiters = 12))`", m)
        @test solve(p, BackwardEuler(; linsolve = LatticePCG(; maxiters = 12)); dt = 0.01).retcode == ReturnCode.Success
        m = e(() -> ExplicitEuler(; linsolve = LatticeMultigrid()))
        @test occursin("give it to an implicit field solver, `BackwardEuler(; linsolve = LatticeMultigrid())`", m)
        @test solve(p, BackwardEuler(; linsolve = LatticeMultigrid()); dt = 0.01).retcode == ReturnCode.Success
        # the `:ode` path: a field or linear solver given to an `ODEProblem`
        po = discretize(
            bsys([D(bce) ~ bD * laplacian(bce)], [bc(0, x, y) ~ x], [bD]; dvs = [bce]),
            LatticeDiscretization(Grid(BDIMS); T = Float64)
        )
        m = e(() -> solve(po, LatticePCG()))
        @test occursin("give it to one, `BackwardEuler(; linsolve = LatticePCG())`", m)
        # (the field solvers step the problem `discretize` returns; base: refused, "discretize
        # with `LatticeDiscretization(…; problem = :owned)`")
        @test init(po, BackwardEuler(); dt = 0.1).sol.t == [0.0]
        @test solve(po, ImplicitEuler(); dt = 0.01, adaptive = false).retcode == ReturnCode.Success   # the route
        # the keywords
        for (f, want) in (
                (() -> BackwardEuler(; nlsolve = 0), "BackwardEuler: nlsolve = 0 must be `nothing`"),
                (() -> BackwardEuler(; substeps = true), "BackwardEuler: substeps = true must be an integer ≥ 1"),
                (() -> BackwardEuler(; linsolve = :pcg), "BackwardEuler: `linsolve` takes `:auto`, a `LatticePCG(…)` or a `LatticeMultigrid(…)`"),
                (() -> BackwardEuler(; solver_type = BigFloat), "BackwardEuler: `solver_type` takes `:auto`"),
                (() -> BackwardEuler(; theta = 1), "BackwardEuler: no keyword `theta`; its keywords are `substeps`, `nlsolve`, `lower_bound`, `linsolve`, `solver_type`, `init` and `compute_type`"),
            )
            @test startswith(e(f), want) || (println("MSG: ", e(f)); false)
        end
        a = BackwardEuler(; nlsolve = LatticeNewton(; max_iter = 2), linsolve = LatticePCG(; maxiters = 12))
        @test eval(Meta.parse(repr(a))) == a
        # a map group has no implicit operator
        pm = discretize(
            PDESystem([Shift(t, 1)(bce) ~ 0.5 * bce], [bc(0, x, y) ~ x], bdom(), [t, x, y], [bce], Any[]; name = :m),
            LatticeDiscretization(Grid(BDIMS); T = Float64)
        )
        @test occursin("a map program is stepped by ExplicitMap()", e(() -> init(pm, BackwardEuler(); dt = 1.0)))
    end
end

@testitem "StalledSuccess does not skip the later groups" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "StalledSuccess does not skip the later groups" begin
        p = gown(gsys())
        for (code, moves) in ((ReturnCode.StalledSuccess, true), (ReturnCode.ConvergenceFailure, false))
            ig = init(p, FieldGroups(gce => StallStub(code); default = ExplicitEuler()); dt = 0.01)
            o0 = copy(ig[goe])
            step!(ig)
            @test (ig[goe] != o0) == moves && ig.retcode == code
        end
    end
end

@testitem "LatticeNewton NLNewton semantics, host factorizations, and refusals" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    using LinearSolve: KLUFactorization, LUFactorization, UMFPACKFactorization
    using LatticeFields.Solvers: BoundOperator
    @testset "LatticeNewton keywords and NLNewton semantics" begin
        function e(f)
            return try
                f(); ""
            catch err
                err isa ArgumentError ? err.msg : sprint(showerror, err)
            end
        end
        @test repr(LatticeNewton()) == "LatticeNewton()"
        @test repr(LatticeNewton(; κ = 1 // 100, max_iter = 10, check_div = true)) == "LatticeNewton()"
        @test repr(LatticeNewton(; κ = 1.0e-4)) == "LatticeNewton(; κ = 0.0001)"
        @test repr(LatticeNewton(; max_iter = 4)) == "LatticeNewton(; max_iter = 4)"
        @test repr(LatticeNewton(; check_div = false)) == "LatticeNewton(; check_div = false)"
        @test LatticeNewton().κ == 1 // 100 && LatticeNewton().max_iter == 10 && LatticeNewton().check_div
        # Unsupported NLNewton keywords throw ArgumentError with explanation
        for kw in (
                (; fast_convergence_cutoff = 0.2),
                (; new_W_dt_cutoff = 0.5),
                (; always_new = true),
                (; relax = 0.5),
                (; predictor = Val(true)),
                (; bogus = 1),
            )
            @test_throws ArgumentError LatticeNewton(; kw...)
            m = e(() -> LatticeNewton(; kw...))
            @test occursin(string(first(keys(kw))), m)
        end
        for bad_k in (0, -0.1, NaN, Inf, true)
            @test_throws ArgumentError LatticeNewton(; κ = bad_k)
            @test occursin("κ", e(() -> LatticeNewton(; κ = bad_k)))
        end
        for bad_it in (0, nothing)
            @test_throws ArgumentError LatticeNewton(; max_iter = bad_it)
            @test occursin("max_iter", e(() -> LatticeNewton(; max_iter = bad_it)))
        end
        @test_throws ArgumentError LatticeNewton(; check_div = 1)
        @test occursin("check_div", e(() -> LatticeNewton(; check_div = 1)))

        # max_iter = k runs at most k, stops early when converged, and returns ConvergenceFailure on budget hit
        sys_adv = PDESystem(
            [D(bce) ~ 0.01 * laplacian(bce) - Advect(Upwind1())([1.0, 0.5], bce) + 1 + sin(4t) * x],
            [bc(0, x, y) ~ x * y], bdom(0.25), [t, x, y], [bce], Any[]; name = :nl_adv,
        )
        p_adv = discretize(sys_adv, LatticeDiscretization(Grid((16, 16)); T = Float64))
        s_conv = solve(p_adv, BackwardEuler(; linsolve = BTIGHT, nlsolve = LatticeNewton(; max_iter = 30)); dt = 0.25)
        s_def = solve(p_adv, BackwardEuler(; linsolve = BTIGHT, nlsolve = LatticeNewton()); dt = 0.25)
        nsteps_conv = s_conv.stats.nf * only(s_conv.stats.counts)
        @test s_conv.retcode == ReturnCode.Success && s_conv.stats.newton_budget == 0
        @test s_conv.stats.solves < 30 * nsteps_conv && s_conv.stats.solves == s_def.stats.solves
        s_mid = solve(p_adv, BackwardEuler(; linsolve = BTIGHT, nlsolve = LatticeNewton(; max_iter = 10)); dt = 0.25)
        @test s_mid.retcode == ReturnCode.Success && s_mid.stats.solves < 10 * nsteps_conv
        s_fail = @test_logs (:warn, r"reached its budget.*ConvergenceFailure") solve(
            p_adv, BackwardEuler(; linsolve = BTIGHT, nlsolve = LatticeNewton(; max_iter = 2)); dt = 0.25
        )
        nsteps_fail = s_fail.stats.nf * only(s_fail.stats.counts)
        @test s_fail.retcode == ReturnCode.ConvergenceFailure && s_fail.stats.newton_budget > 0
        @test s_fail.stats.solves <= 2 * nsteps_fail

        # Smaller κ yields smaller error against exact unsplit Backward Euler step and monotone non-decreasing solves
        u_ref = direct_be(sys_adv, (16, 16), 0.25, 0.25, 24)
        kappas = (1.0e-1, 1.0e-2, 1.0e-4, 1.0e-6)
        sols_k = [
            solve(
                p_adv,
                BackwardEuler(; substeps = 24, linsolve = BTIGHT, nlsolve = LatticeNewton(; κ = kv, max_iter = 30));
                dt = 0.25,
            ) for kv in kappas
        ]
        errs_k = [maximum(abs, vec(s[bce, end]) .- u_ref) for s in sols_k]
        solves_k = [s.stats.solves for s in sols_k]
        @test all(s -> s.retcode == ReturnCode.Success && s.stats.newton_budget == 0, sols_k)
        @test all(i -> errs_k[i + 1] <= errs_k[i] + 1.0e-14, 1:(length(kappas) - 1))
        @test errs_k[end] < errs_k[1] / 100
        @test all(i -> solves_k[i + 1] >= solves_k[i], 1:(length(kappas) - 1))
        @test solves_k[end] > solves_k[1]

        # abstol / reltol solve keywords control the scaled norm; invalid tolerances throw ArgumentError
        s_loose_tol = solve(
            p_adv, BackwardEuler(; substeps = 24, linsolve = BTIGHT, nlsolve = LatticeNewton(; max_iter = 30));
            dt = 0.25, abstol = 1.0e-2, reltol = 1.0e-1,
        )
        s_tight_tol = solve(
            p_adv, BackwardEuler(; substeps = 24, linsolve = BTIGHT, nlsolve = LatticeNewton(; max_iter = 30));
            dt = 0.25, abstol = 1.0e-10, reltol = 1.0e-8,
        )
        @test s_tight_tol.retcode == ReturnCode.Success && s_loose_tol.retcode == ReturnCode.Success
        @test s_tight_tol.stats.solves > s_loose_tol.stats.solves
        @test maximum(abs, vec(s_tight_tol[bce, end]) .- u_ref) < maximum(abs, vec(s_loose_tol[bce, end]) .- u_ref) / 100
        @test_throws ArgumentError solve(p_adv, BackwardEuler(; nlsolve = LatticeNewton()); dt = 0.25, abstol = 0.0, reltol = 0.0)
        @test_throws ArgumentError solve(p_adv, BackwardEuler(; nlsolve = LatticeNewton()); dt = 0.25, reltol = -1.0e-3)

        # Coupled QuasiSteady uses one global RMS norm over all coupled unknowns; smaller κ lowers error vs exact solution
        sys_cpl = PDESystem(
            [
                D(bce) ~ 0.1 * laplacian(bce) - 2.0 * bce + 0.5 * boe + x,
                D(boe) ~ 0.1 * laplacian(boe) - 2.0 * boe + 0.5 * bce - 0.5 * bce^2 + y,
            ],
            [bc(0, x, y) ~ 0.2 + x, bo(0, x, y) ~ 0.1 + y], bdom(0.1), [t, x, y], [bce, boe], Any[]; name = :nl_cpl,
        )
        p_cpl = discretize(sys_cpl, LatticeDiscretization(Grid((10, 10)); T = Float64))
        s_cpl_ref = solve(
            p_cpl,
            QuasiSteady(; linsolve = LatticeGMRES(; reltol = 1.0e-13, maxiters = 200), nlsolve = LatticeNewton(; κ = 1.0e-4, max_iter = 30));
            dt = 0.1, abstol = 1.0e-10, reltol = 1.0e-10,
        )
        @test s_cpl_ref.retcode == ReturnCode.Success
        s_cpl_loose = solve(
            p_cpl,
            QuasiSteady(; linsolve = LatticeGMRES(; reltol = 1.0e-13, maxiters = 200), nlsolve = LatticeNewton(; κ = 1.0e-1, max_iter = 30));
            dt = 0.1,
        )
        s_cpl_tight = solve(
            p_cpl,
            QuasiSteady(; linsolve = LatticeGMRES(; reltol = 1.0e-13, maxiters = 200), nlsolve = LatticeNewton(; κ = 1.0e-6, max_iter = 30));
            dt = 0.1, abstol = 1.0e-8, reltol = 1.0e-6,
        )
        @test s_cpl_tight.retcode == ReturnCode.Success && s_cpl_loose.retcode == ReturnCode.Success
        @test s_cpl_tight.stats.solves >= s_cpl_loose.stats.solves
        @test maximum(abs, [vec(s_cpl_tight[bce, end]); vec(s_cpl_tight[boe, end])] .- [vec(s_cpl_ref[bce, end]); vec(s_cpl_ref[boe, end])]) <
            maximum(abs, [vec(s_cpl_loose[bce, end]); vec(s_cpl_loose[boe, end])] .- [vec(s_cpl_ref[bce, end]); vec(s_cpl_ref[boe, end])])

        # Generic number types: Float32 and Float16 storage with LatticeNewton(; κ)
        p32_adv = discretize(sys_adv, LatticeDiscretization(Grid((16, 16)); T = Float32))
        s32_adv = solve(
            p32_adv,
            BackwardEuler(; substeps = 24, linsolve = LatticePCG(; reltol = 1.0f-6, maxiters = 64), nlsolve = LatticeNewton(; κ = 1.0f-2, max_iter = 20));
            dt = 0.25,
        )
        @test s32_adv.retcode == ReturnCode.Success && eltype(s32_adv[bce, end]) == Float32
        @variables bc16(..) [lattice_storage = Float16]
        sys16 = PDESystem(
            [D(bc16(t, x, y)) ~ 0.05 * laplacian(bc16(t, x, y)) - bc16(t, x, y)^2 + 1],
            [bc16(0, x, y) ~ 0.5 + 0.2 * x], bdom(0.1), [t, x, y], [bc16(t, x, y)], Any[]; name = :nl_f16,
        )
        p16 = discretize(sys16, LatticeDiscretization(Grid((8, 8)); T = Float32))
        s16 = solve(p16, BackwardEuler(; nlsolve = LatticeNewton(; κ = 1 // 100, max_iter = 10)); dt = 0.1)
        @test SciMLBase.successful_retcode(s16.retcode) && eltype(s16[bc16(t, x, y), end]) == Float16

        # check_div = true stops a diverging solve early with ConvergenceFailure;
        # check_div = false disables divergence-growth aborts and accepts budget hits as Success (as NLNewton)
        sys_div = PDESystem(
            [D(bce) ~ 0.01 * laplacian(bce) - Advect(Upwind1())([50 * (1 + x) + t, 0.0], bce)],
            [bc(0, x, y) ~ x * y], bdom(1.0), [t, x, y], [bce], Any[]; name = :nl_div,
        )
        p_div = discretize(sys_div, LatticeDiscretization(Grid((16, 16)); T = Float64))
        ig_true = init(
            p_div, BackwardEuler(; nlsolve = LatticeNewton(; max_iter = 10, check_div = true));
            dt = 1.0, abstol = 1.0, reltol = 1.0e-8,
        )
        @test_logs (:warn, r"diverged") solve!(ig_true)
        @test ig_true.retcode == ReturnCode.ConvergenceFailure
        @test only(ig_true.runtimes).totals.cause & 0x02 != 0
        @test ig_true.stats.solves < 10
        ig_false = init(
            p_div, BackwardEuler(; nlsolve = LatticeNewton(; max_iter = 3, check_div = false));
            dt = 1.0, abstol = 1.0, reltol = 1.0e-8,
        )
        @test_logs (:warn, r"reached its budget") solve!(ig_false)
        @test ig_false.retcode == ReturnCode.Success
        @test ig_false.stats.newton_budget > 0
        @test only(ig_false.runtimes).totals.cause & 0x02 == 0
        @test ig_false.stats.solves == 3

        # max_iter = 1 is checked under LatticeNewton (check_div = true fails unless ndz < 1e-5; check_div = false accepts)
        s_one_fail = @test_logs (:warn, r"reached its budget") solve(
            p_adv, BackwardEuler(; linsolve = BTIGHT, nlsolve = LatticeNewton(; max_iter = 1, check_div = true)); dt = 0.25,
        )
        @test s_one_fail.retcode == ReturnCode.ConvergenceFailure && s_one_fail.stats.newton_budget > 0
        s_one_ok = @test_logs (:warn, r"reached its budget") solve(
            p_adv, BackwardEuler(; linsolve = BTIGHT, nlsolve = LatticeNewton(; max_iter = 1, check_div = false)); dt = 0.25,
        )
        @test s_one_ok.retcode == ReturnCode.Success && s_one_ok.stats.newton_budget > 0

        # Iteration-1 rule: a state already at its steady state finishes in 1 solve per substep
        sys_ss = PDESystem(
            [D(bce) ~ 0.1 * laplacian(bce) - bce^2 + 1.0],
            [bc(0, x, y) ~ 1.0], bdom(0.2), [t, x, y], [bce], Any[]; name = :nl_ss,
        )
        p_ss = discretize(sys_ss, LatticeDiscretization(Grid((8, 8)); T = Float64))
        s_ss = solve(p_ss, BackwardEuler(; substeps = 2, linsolve = BTIGHT, nlsolve = LatticeNewton(; κ = 1.0e-8, max_iter = 1)); dt = 0.1)
        @test s_ss.retcode == ReturnCode.Success && s_ss.stats.newton_budget == 0 && s_ss.stats.solves == 4

        # Automatic mode (nlsolve = nothing) refuses abstol/reltol and routes to LatticeNewton()
        @test_throws ArgumentError init(p_adv, BackwardEuler(); dt = 0.25, abstol = 1.0e-8)
        @test_throws ArgumentError init(p_adv, BackwardEuler(); dt = 0.25, reltol = 1.0e-6)
        @test occursin("LatticeNewton()", e(() -> init(p_adv, BackwardEuler(); dt = 0.25, abstol = 1.0e-8)))
        sys_qs_tf = PDESystem(
            [0.0 ~ 0.1 * laplacian(bc(x, y)) - bc(x, y) + 1.0], Equation[],
            [x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [x, y], [bc(x, y)], Any[]; name = :qs_tf,
        )
        p_qs_tf = LFP.field_problem(discretize(sys_qs_tf, LatticeDiscretization(Grid((8, 8)); T = Float64)))
        @test_throws ArgumentError solve(p_qs_tf, QuasiSteady(); abstol = 1.0e-8)
        ig_opts = init(p_adv, BackwardEuler(; nlsolve = LatticeNewton()); dt = 0.25)
        @test ig_opts.opts.abstol == 1 // 10^6 && ig_opts.opts.reltol == 1 // 10^3

        # Non-coupled multi-row group: one global group norm avoids spurious ndz/0 divergence when one field hits zero update
        sys_m3 = PDESystem(
            [
                D(bce) ~ 0.1 * laplacian(bce) - bce,
                D(boe) ~ 0.05 * laplacian(boe) - Advect(Upwind1())([0.8, 0.0], boe) - boe^2 + 0.5,
            ],
            [bc(0, x, y) ~ 0.0, bo(0, x, y) ~ 0.3 + 0.5 * x], bdom(0.2), [t, x, y], [bce, boe], Any[]; name = :m3_grp,
        )
        p_m3 = discretize(sys_m3, LatticeDiscretization(Grid((12, 12)); T = Float64))
        s_m3 = solve(p_m3, BackwardEuler(; linsolve = BTIGHT, nlsolve = LatticeNewton(; κ = 1.0e-3, max_iter = 20)); dt = 0.1)
        @test s_m3.retcode == ReturnCode.Success && s_m3.stats.newton_budget == 0 && maximum(abs, s_m3[bce, end]) == 0.0

        # Precision-limit branch: at Float32 rounding (κ = 1e-12 impossible via η*ndz < κ, and it > 1),
        # only the precision-limit window (|θ - 1| ≤ 100*sqrt(eps(T)), ndz ≤ 1) can stop early with Success;
        # below Float32 rounding (ndz > 1) check_div = true stops with ConvergenceFailure.
        sys_pl = PDESystem(
            [D(bce) ~ 0.1f0 * laplacian(bce) - 0.5f0 * bce^2 + 0.2f0],
            [bc(0, x, y) ~ 0.5f0 + 0.2f0 * x], [t ∈ Interval(0.0f0, 0.1f0), x ∈ Interval(0.0f0, 1.0f0), y ∈ Interval(0.0f0, 1.0f0)],
            [t, x, y], [bce], Any[]; name = :nl_pl,
        )
        p_pl = discretize(sys_pl, LatticeDiscretization(Grid((8, 8)); T = Float32))
        s_pl = solve(
            p_pl, BackwardEuler(; linsolve = LatticePCG(; reltol = 1.0f-7, maxiters = 64), nlsolve = LatticeNewton(; κ = 1.0f-12, max_iter = 10));
            dt = 0.1, abstol = 1.0f-7, reltol = 1.0f-7,
        )
        @test s_pl.retcode == ReturnCode.Success && s_pl.stats.newton_budget == 0 && s_pl.stats.solves < 10
        s_pl_div = @test_logs (:warn, r"diverged") solve(
            p_pl, BackwardEuler(; linsolve = LatticePCG(; reltol = 1.0f-7, maxiters = 64), nlsolve = LatticeNewton(; κ = 1.0f-12, max_iter = 10));
            dt = 0.1, abstol = 1.0f-12, reltol = 1.0f-12,
        )
        @test s_pl_div.retcode == ReturnCode.ConvergenceFailure && s_pl_div.stats.solves < 10

        # OrdinaryDiffEq NLNewton oracle on a 1D nonlinear reaction-diffusion problem (per-step counts and states)
        @variables u1(..)
        u1e = u1(t, x)
        for ic_zero in (false, true)
            sys1d = PDESystem(
                [D(u1e) ~ 0.05 * laplacian(u1e) - 0.5 * u1e^2 + 0.2],
                [u1(0, x) ~ ic_zero ? 0.0 : 0.1 * sin(2π * x), u1(t, 0) ~ u1(t, 1)],
                [t ∈ Interval(0.0, 0.5), x ∈ Interval(0.0, 1.0)], [t, x], [u1e], Any[]; name = ic_zero ? :ode1d0 : :ode1d,
            )
            p_ode = discretize(sys1d, LatticeDiscretization(Grid((16,)); T = Float64))
            p_own = LFP.field_problem(p_ode)
            for kv in (1.0e-1, 1.0e-2, 1.0e-5)
                igo = init(
                    p_ode,
                    ImplicitEuler(; linsolve = LUFactorization(), nlsolve = OrdinaryDiffEqSDIRK.NLNewton(; κ = kv, always_new = true));
                    dt = 0.05, adaptive = false, abstol = 1.0e-7, reltol = 1.0e-4,
                )
                igb = init(
                    p_own,
                    BackwardEuler(; substeps = 1, linsolve = LUFactorization(), nlsolve = LatticeNewton(; κ = kv));
                    dt = 0.05, abstol = 1.0e-7, reltol = 1.0e-4,
                )
                prev_o, prev_b = 0, 0
                for _ in 1:10
                    step!(igo); step!(igb)
                    @test igb.stats.solves - prev_b == igo.stats.nsolve - prev_o
                    prev_o, prev_b = igo.stats.nsolve, igb.stats.solves
                end
                so, sb = solve!(igo), solve!(igb)
                @test sb.retcode == ReturnCode.Success && so.retcode == ReturnCode.Success
                @test vec(sb[u1e, end]) ≈ Array(so.u[end]) rtol = 1.0e-12 atol = 1.0e-12
                @test sb.stats.solves == so.stats.nsolve
            end
        end
        # Two uncoupled fields of very different magnitudes share one group norm: the per-step solve counts follow
        # NLNewton's single norm, and the group stops sooner than the large field alone would under a per-row norm
        sys2d = PDESystem(
            [
                D(bce) ~ 0.05 * laplacian(bce) - bce + 1.0e-4 * (1.0 + x),
                D(boe) ~ 0.05 * laplacian(boe) - 0.5 * boe^2 + 100.0,
            ],
            [
                bc(0, x, y) ~ 0.0, bo(0, x, y) ~ 0.0, bc(t, 0, y) ~ bc(t, 1, y), bc(t, x, 0) ~ bc(t, x, 1),
                bo(t, 0, y) ~ bo(t, 1, y), bo(t, x, 0) ~ bo(t, x, 1),
            ],
            [t ∈ Interval(0.0, 0.5), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [bce, boe], Any[]; name = :ode2d,
        )
        sys_bo = PDESystem(
            [D(boe) ~ 0.05 * laplacian(boe) - 0.5 * boe^2 + 100.0],
            [bo(0, x, y) ~ 0.0, bo(t, 0, y) ~ bo(t, 1, y), bo(t, x, 0) ~ bo(t, x, 1)],
            [t ∈ Interval(0.0, 0.5), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [boe], Any[]; name = :ode_bo,
        )
        p2_ode = discretize(sys2d, LatticeDiscretization(Grid((6, 6)); T = Float64))
        p2_own = LFP.field_problem(p2_ode)
        p_bo = LFP.field_problem(discretize(sys_bo, LatticeDiscretization(Grid((6, 6)); T = Float64)))
        for kv in (1.0e-2, 1.0e-3, 1.0e-5)
            igo = init(
                p2_ode,
                ImplicitEuler(; linsolve = LUFactorization(), nlsolve = OrdinaryDiffEqSDIRK.NLNewton(; κ = kv, always_new = true));
                dt = 0.05, adaptive = false, abstol = 1.0e-7, reltol = 1.0e-4,
            )
            igb = init(
                p2_own,
                BackwardEuler(; substeps = 1, linsolve = LUFactorization(), nlsolve = LatticeNewton(; κ = kv));
                dt = 0.05, abstol = 1.0e-7, reltol = 1.0e-4,
            )
            prev_o, prev_b = 0, 0
            for _ in 1:10
                step!(igo); step!(igb)
                @test igb.stats.solves - prev_b == 2 * (igo.stats.nsolve - prev_o)
                prev_o, prev_b = igo.stats.nsolve, igb.stats.solves
            end
            so, sb = solve!(igo), solve!(igb)
            @test sb.retcode == ReturnCode.Success && so.retcode == ReturnCode.Success
            @test vcat(vec(sb[bce, end]), vec(sb[boe, end])) ≈ Array(so.u[end]) rtol = 1.0e-12 atol = 1.0e-12
            if kv >= 1.0e-3
                s_bo = solve(
                    p_bo, BackwardEuler(; substeps = 1, linsolve = LUFactorization(), nlsolve = LatticeNewton(; κ = kv));
                    dt = 0.05, abstol = 1.0e-7, reltol = 1.0e-4,
                )
                @test div(sb.stats.solves, 2) < s_bo.stats.solves
            end
        end
    end
    @testset "Host CSC factorizations (KLUFactorization, UMFPACKFactorization) match LatticePCG" begin
        using LinearSolve: KrylovJL_CG, LUFactorization, PureKLUFactorization
        @parameters kd = 0.3 kk = 2.0
        for (name, sys) in (
                (:num, bsys([D(bce) ~ kd * laplacian(bce) - kk * bce + x], [bc(0, x, y) ~ x * y, bc(t, 0, y) ~ 1.0], [kd, kk])),
                (:field, bsys([D(bce) ~ DivKGrad(:harmonic)(kd * (1 + x * y), bce) - kk * bce + x], [bc(0, x, y) ~ x * y, bce ~ masked(bqe == 2, 1.0 + x)], [kd, kk])),
            )
            p = bown(sys)
            ref = solve(p, BackwardEuler(; linsolve = LatticePCG(; reltol = 1.0e-12, maxiters = 64)); dt = 0.05)
            for fact in (KLUFactorization(), UMFPACKFactorization())
                got = solve(p, BackwardEuler(; linsolve = fact); dt = 0.05)
                @test got.retcode == ReturnCode.Success
                @test maximum(abs, got[bce, end] .- ref[bce, end]) < 1.0e-10
            end
            # Parameter writes update the concrete CSC matrix cleanly
            ig_p = init(p, BackwardEuler(; linsolve = LatticePCG(; reltol = 1.0e-12, maxiters = 64)); dt = 0.05)
            ig_k = init(p, BackwardEuler(; linsolve = KLUFactorization()); dt = 0.05)
            step!(ig_p); step!(ig_k)
            ig_p.ps[kd] = 0.6; ig_k.ps[kd] = 0.6
            ig_p.ps[kk] = 4.0; ig_k.ps[kk] = 4.0
            step!(ig_p); step!(ig_k)
            @test maximum(abs, ig_k[bce] .- ig_p[bce]) < 1.0e-10
            # Float32 state: Float64-only factorizations assemble Float64 CSC automatically under :auto and with solver_type = Float64
            p32 = bown(sys; T = Float32)
            ref32 = solve(p32, BackwardEuler(; linsolve = LatticePCG(; reltol = 1.0e-7, maxiters = 64), solver_type = Float64); dt = 0.05)
            for alg in (
                    BackwardEuler(; linsolve = KLUFactorization()),
                    BackwardEuler(; linsolve = KLUFactorization(), solver_type = Float64),
                    BackwardEuler(; linsolve = UMFPACKFactorization()),
                    BackwardEuler(; linsolve = LUFactorization()),
                    BackwardEuler(; linsolve = PureKLUFactorization()),
                )
                got32 = solve(p32, alg; dt = 0.05)
                @test got32.retcode == ReturnCode.Success && eltype(got32[bce, end]) == Float32
                @test maximum(abs, got32[bce, end] .- ref32[bce, end]) < 1.0e-5
            end
            @test_throws ArgumentError init(p32, BackwardEuler(; linsolve = KLUFactorization(), solver_type = Float32); dt = 0.05)
            msg = try
                init(p32, BackwardEuler(; linsolve = KLUFactorization(), solver_type = Float32); dt = 0.05)
                ""
            catch err
                sprint(showerror, err)
            end
            @test occursin("Float64", msg)
        end
        # KrylovJL_CG with precs = LatticeMultigrid on a time-varying field reuses its held FieldSolver across rebuilds
        sys_t = bsys([D(bce) ~ (0.3 + 0.1 * sin(5t)) * laplacian(bce) - 2.0 * bce + x], [bc(0, x, y) ~ x * y], [])
        pt = bown(sys_t)
        mg = LatticeMultigrid()
        ig_t = init(pt, BackwardEuler(; linsolve = KrylovJL_CG(; precs = mg)); dt = 0.05)
        step!(ig_t)
        sv1 = only(values(mg.engines))[]
        step!(ig_t); step!(ig_t)
        @test only(values(mg.engines))[] === sv1
    end
end
