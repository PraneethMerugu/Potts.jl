# F3-07 (F3 design §3.3, §3.4): `BackwardEuler` in front end B for linear groups. The rate
# program is the residual (`fuse_residual`), the operator `J̃` comes from the linearity table
# (`OperatorSpec`, built at the first implicit use only), and each substep solves
# `(I/h − J̃) δ = G(uⁿ)`, `u = uⁿ + δ` at `tⁿ⁺¹`. The tests compare one window with the hand BE
# matrix of the same stencil (faces, ghosts, masks), the order with the exact semi-discrete
# solution, a manufactured solution, a stiff case and OrdinaryDiffEq's `ImplicitEuler`.
# Base (437a84ef, ~/lpwork/f3b3-nc-base.log): `BackwardEuler` is not defined (every testset
# errors); the negative controls below are mutations of this tree (~/lpwork/f3b3-nc-*.log).

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

@testitem "F3-07: one BackwardEuler window equals the hand BE matrix" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
@testset "F3-07: one BackwardEuler window equals the hand BE matrix" begin
    h = 0.05
        alg = BackwardEuler(; linsolve = BTIGHT)
    # a numeric operator: diffusion, decay, a source, a Dirichlet face, a mask with its value
        p = bown(
            bsys(
                [D(bce) ~ bD * laplacian(bce) - bk * bce + x], [
                    bc(0, x, y) ~ x * y, bc(t, 0, y) ~ 1.0,
        bce ~ masked(bqe == 2, 1.5)], [bD, bk]))
        ig, u0, u = be_window(p, alg; dt = h)
    want = be_hand(u0, h; K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x, faces = Dict((1, -1) => (:dir, 1.0)),
        mask = vec(BKIND .== 2), mval = fill(1.5, 48))
    @test maximum(abs, u .- want) < 1e-9
    rt = only(ig.runtimes)
        @test rt.cache.newton == 1 && rt.cache.exact && SciMLBase.check_error(ig) == ReturnCode.Success
    @test all(u[vec(BKIND .== 2)] .== 1.5)                     # the mask value written back (SD-11)
    @test rt.totals.solves == 1                                # one solve per substep (exact operator)
end
end

@testitem "F3-07: the solver capabilities in a BackwardEuler group (F3-05 in B)" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
@testset "F3-07: the solver capabilities in a BackwardEuler group (F3-05 in B)" begin
    h = 0.05
    xs, ys = bxs(), bys()
    # a Robin face, positive part (α and β of the same sign with the outward normal)
        p = bown(
            bsys(
                [D(bce) ~ bD * laplacian(bce) - bk * bce + x], [bc(0, x, y) ~ 0.0, 2.0 * bc(t, x, 0) - Differential(y)(bc(t, x, 0)) ~ bg],
        [bD, bk, bg]))
        ig, u0, u = be_window(p, BackwardEuler(; linsolve = BTIGHT); dt = h)
    want = be_hand(u0, h; K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x, faces = Dict((2, -1) => (:robin, 2.0, -1.0, 0.5)))
    @test maximum(abs, u .- want) < 1e-10 && only(ig.runtimes).cache.newton == 1
    # opposite signs: the negative part stays in the residual (a defect correction), so the
    # automatic Newton count is more than one (from its bound `w |d⁻|`, S1: 5 here); `newton = k`
    # converges it to the hand matrix
        p = bown(
            bsys(
                [D(bce) ~ bD * laplacian(bce) - bk * bce + x], [bc(0, x, y) ~ 0.0, 2.0 * bc(t, x, 0) + Differential(y)(bc(t, x, 0)) ~ bg],
        [bD, bk, bg]))
    want = be_hand(zeros(48), h; K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = (x, y) -> x, faces = Dict((2, -1) => (:robin, 2.0, 1.0, 0.5)))
        ig, _, u4 = be_window(p, BackwardEuler(; linsolve = BTIGHT); dt = h)
    @test only(ig.runtimes).cache.newton == 5 && only(ig.runtimes).cache.seen && maximum(abs, u4 .- want) < 1e-3
        ig, _, u = be_window(p, BackwardEuler(; newton = 30, linsolve = BTIGHT); dt = h)
    @test maximum(abs, u .- want) < 1e-10 && only(ig.runtimes).totals.solves == 30
    # a field face coefficient (`DivKGrad(k(x, y), c)`) with a face-Dirichlet value that varies along the face
    p = bown(bsys([D(bce) ~ DivKGrad(:harmonic)(1 + x * y, bce) - bk * bce], [bc(0, x, y) ~ 0.0, bc(t, 0, y) ~ 1.0 + y], [bk]))
        ig, u0, u = be_window(p, BackwardEuler(; linsolve = BTIGHT); dt = h)
    rt = only(ig.runtimes)
    @test rt.cache.rows[1].op.field && rt.cache.op.jac !== nothing
    want = be_hand(u0, h; K = (x, y) -> 1 + x * y, k = (x, y) -> 2.0, faces = Dict((1, -1) => (:dir, (x, y) -> 1.0 + y)))
    @test maximum(abs, u .- want) < 1e-10
    # a mask whose value is a field (`masked(pred, 1 + x)`): each masked site takes its own value
        p = bown(bsys([D(bce) ~ bD * laplacian(bce) - bk * bce], [bc(0, x, y) ~ 0.0, bce ~ masked(bqe == 2, 1 + x)], [bD, bk]))
        ig, u0, u = be_window(p, BackwardEuler(; linsolve = BTIGHT); dt = h)
    mk = vec(BKIND .== 2)
    want = be_hand(u0, h; K = (x, y) -> 0.3, k = (x, y) -> 2.0, mask = mk, mval = vec(1 .+ xs))
    @test maximum(abs, u .- want) < 1e-10 && all(u[mk] .== vec(1 .+ xs)[mk])
    # the face and mask value fields stepped explicitly too: one ExplicitEuler window is
    # `u0 + h r(u0)` off the mask, the mask value on it
    p = bown(bsys([D(bce) ~ DivKGrad(:harmonic)(1 + x * y, bce) - bk * bce],
        [bc(0, x, y) ~ x, bc(t, 0, y) ~ 1.0 + y, bce ~ masked(bqe == 2, 1 + x)], [bk]))
        ig = init(p, ExplicitEuler(; substeps = 1); dt = 1.0e-3)
    u0 = copy(vec(ig[bce]))
    step!(ig)
    L, bb = hand_rate(; K = (x, y) -> 1 + x * y, k = (x, y) -> 2.0, faces = Dict((1, -1) => (:dir, (x, y) -> 1.0 + y)))
    want = ifelse.(mk, vec(1 .+ xs), u0 .+ 1e-3 .* (L * u0 .+ bb))
    @test u0[mk] == vec(1 .+ xs)[mk] && maximum(abs, vec(ig[bce]) .- want) < 1e-12
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
    @test maximum(abs, vec(ig[bce]) .- want) < 1e-10
    @test bwarm(ig) == 0
end
end

@testitem "F3-07: SiteDiffusion rows (row scaling; m = 0 rows in two stages)" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
@testset "F3-07: SiteDiffusion rows (row scaling; m = 0 rows in two stages)" begin
    h = 0.05
        # `value_at(W, q) laplacian(c)`: the row scaled by 1/m keeps the faces symmetric (q = 0 reads 0: m = 0 rows)
        p = bown(bsys([D(bce) ~ value_at(bW, bqe) * laplacian(bce) - bk * bce + 1], [bc(0, x, y) ~ x], [bW, bk]))
        ig, u0, u = be_window(p, BackwardEuler(; linsolve = BTIGHT); dt = h)
    mm = (i, j) -> (0.0, 0.5, 2.0)[BKIND[i, j] + 1]
    want = be_hand(u0, h; m = mm, k = (x, y) -> 2.0, f = (x, y) -> 1.0)
    @test maximum(abs, u .- want) < 1e-12
    @test only(ig.runtimes).cache.rows[1].op.scaled && only(ig.runtimes).cache.exact
    # a multiplier that is 0 on some rows (`ifelse(kind == 1, 0, D)`): the two-stage solve
        p = bown(bsys([D(bce) ~ ifelse(bqe == 1, 0.0, 0.7) * laplacian(bce) - 50.0 * bce], [bc(0, x, y) ~ 1.0 + x], Any[]))
        ig, u0, u = be_window(p, BackwardEuler(; linsolve = BTIGHT); dt = 0.1)
    want = be_hand(u0, 0.1; m = (i, j) -> BKIND[i, j] == 1 ? 0.0 : 0.7, k = (x, y) -> 50.0)
    @test maximum(abs, u .- want) < 1e-12
    # (the pinned-row rule `δ = G h` is a forward Euler step there: off by about 4 at decay 50)
    @test maximum(abs, u[vec(BKIND .== 1)] .- (u0[vec(BKIND .== 1)] ./ (1 + 0.1 * 50))) < 1e-12
        # `m laplacian(c) + D laplacian(c)` is `(m + D) laplacian(c)`, exact
        p = bown(bsys([D(bce) ~ value_at(bW, bqe) * laplacian(bce) + bD * laplacian(bce) - bk * bce], [bc(0, x, y) ~ x], [bW, bD, bk]))
        ig, u0, u = be_window(p, BackwardEuler(; linsolve = BTIGHT); dt = h)
    want = be_hand(u0, h; m = (i, j) -> mm(i, j) + 0.3, k = (x, y) -> 2.0)
    @test maximum(abs, u .- want) < 1e-12 && only(ig.runtimes).cache.exact
    # two face coefficients: one stays in the residual with its bound, the operator is inexact
    # (more Newton iterations, from the bound, which converge to the BE step)
        p = bown(bsys([D(bce) ~ value_at(bW, bqe) * laplacian(bce) + bD * DivKGrad(:harmonic)(1 + x, bce) - bk * bce], [bc(0, x, y) ~ x], [bW, bD, bk]))
        ig = init(p, BackwardEuler(; newton = 40, linsolve = BTIGHT); dt = h)
    rt = only(ig.runtimes)
    @test !rt.cache.op.rows[1].exact && !isempty(rt.cache.op.rows[1].inexact)
        @test init(p, BackwardEuler(); dt = h).runtimes[1].cache.newton == 10 && init(p, BackwardEuler(); dt = h).runtimes[1].cache.seen
end
end

@testitem "F3-07: order 1, the manufactured solution, the stage tⁿ⁺¹" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
@testset "F3-07: order 1, the manufactured solution, the stage tⁿ⁺¹" begin
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
    @test maximum(abs, u .- want) < 1e-9 && maximum(abs, u .- wrong) > 1e-2
end
end

@testitem "F3-07: a stiff case, OrdinaryDiffEq's ImplicitEuler (SX-18)" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
@testset "F3-07: a stiff case, OrdinaryDiffEq's ImplicitEuler (SX-18)" begin
    # D h/dx² = 10⁴: BackwardEuler stays bounded and monotone; ExplicitEuler with one substep
    # (forced) blows up (`Unstable`)
    n = 16
        step0 = PDESystem(
            [D(bce) ~ bD * laplacian(bce)], [bc(0, x, y) ~ ifelse(x < 0.5, 1.0, 0.0)], bdom(80 * 1.0e4 / (0.3 * n^2)),
        [t, x, y], [bce], [bD]; name = :stiff)
    p = discretize(step0, LatticeDiscretization(Grid((n, n)); T = Float64))
    hs = 1e4 / (0.3 * n^2)
        s = solve(p, BackwardEuler(); dt = hs, saveat = 8hs)
    @test s.retcode == ReturnCode.Success && all(u -> all(v -> -1e-6 <= v <= 1 + 1e-6, u), s.u)
    @test all(k -> maximum(s.u[k + 1]) <= maximum(s.u[k]) + 1e-6 && minimum(s.u[k + 1]) >= minimum(s.u[k]) - 1e-6, 1:(length(s.u) - 1))
        ig = init(p, ExplicitEuler(); dt = hs)
    ig.substeps = 1
    solve!(ig)
    @test ig.retcode == ReturnCode.Unstable
    # the `:ode` path with OrdinaryDiffEq's ImplicitEuler (fixed steps, tight Newton) at equal dt
        sx = bsys(
            [D(bce) ~ bD * laplacian(bce) - bk * bce + sin(3t) * x], [bc(0, x, y) ~ x * y, bc(t, 0, y) ~ 1.0], [bD, bk];
        T = 0.4, dvs = [bce])
    po = discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64))
    # (the Newton tolerance follows abstol and reltol, 1e-12; the rate is linear, so a Newton step is exact)
    so = solve(po, ImplicitEuler(); dt = 0.05, adaptive = false, abstol = 1e-12, reltol = 1e-12)
    sb = solve(discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64)),
            BackwardEuler(; linsolve = BTIGHT); dt = 0.05
        )
    @test maximum(abs, vec(blast(sb)) .- so.u[end]) < 1e-8
end
end

@testitem "F3-07: newton = nothing, the operator built only for implicit groups (S12)" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
@testset "F3-07: newton = nothing, the operator built only for implicit groups (S12)" begin
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
        [bc(0, x, y) ~ 0.0, bo(0, x, y) ~ 0.0], [bD, bk]; dvs = [bce, boe]), LatticeDiscretization(Grid(BDIMS); T = Float64))
        ig = init(p2, BackwardEuler(; linsolve = BTIGHT); dt = 0.1)
    @test only(ig.runtimes).cache.newton == 1 && [r.key for r in only(ig.runtimes).cache.rows] == ["bo", "bc"]
    step!(ig)
    o1 = be_hand(zeros(48), 0.1; K = (x, y) -> 0.5, k = (x, y) -> 1.0, f = (x, y) -> x)
    c1 = be_hand(zeros(48), 0.1; K = (x, y) -> 0.3, k = (x, y) -> 2.0, f = let o = reshape(o1, BDIMS)
        (xx, yy) -> 0.7 * o[round(Int, xx * 8 + 0.5), round(Int, yy * 6 + 0.5)]
    end)
    @test maximum(abs, vec(ig[boe]) .- o1) < 1e-10 && maximum(abs, vec(ig[bce]) .- c1) < 1e-10
    # the substep count: 1, raised only by a positive local derivative (`+ g c`: n ≥ ⌈2 dt g⌉)
        @test init(p, BackwardEuler(); dt = 0.5).substeps == 1
        pg = bown(bsys([D(bce) ~ bD * laplacian(bce) + bk * bce], [bc(0, x, y) ~ x], [bD, bk]))
        @test init(pg, BackwardEuler(); dt = 0.5).substeps == 2 && init(pg, BackwardEuler(; substeps = 5); dt = 0.5).substeps == 5
end
end

@testitem "F3-07: messages, the `:ode` path, `show`" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
@testset "F3-07: messages, the `:ode` path, `show`" begin
    e(f) = try
        f(); ""
    catch err
        err isa ArgumentError ? err.msg : sprint(showerror, err)
    end
        p = bown(bsys([D(bce) ~ bD * laplacian(bce)], [bc(0, x, y) ~ x], [bD]))
        # M1: a linear solver where a field solver goes names `BackwardEuler(; linsolve = …)`, which works
        m = e(() -> solve(p, DevicePCG(; maxiters = 12)))
        @test occursin("give it to one, `BackwardEuler(; linsolve = DevicePCG(; maxiters = 12))`", m)
        @test solve(p, BackwardEuler(; linsolve = DevicePCG(; maxiters = 12)); dt = 0.01).retcode == ReturnCode.Success
        m = e(() -> ExplicitEuler(; linsolve = Multigrid()))
        @test occursin("give it to an implicit field solver, `BackwardEuler(; linsolve = Multigrid())`", m)
        @test solve(p, BackwardEuler(; linsolve = Multigrid()); dt = 0.01).retcode == ReturnCode.Success
    # the `:ode` path: a field or linear solver given to an `ODEProblem`
        po = discretize(
            bsys([D(bce) ~ bD * laplacian(bce)], [bc(0, x, y) ~ x], [bD]; dvs = [bce]),
        LatticeDiscretization(Grid(BDIMS); T = Float64))
    m = e(() -> solve(po, DevicePCG()))
        @test occursin("give it to one, `BackwardEuler(; linsolve = DevicePCG())`", m)
    # (F4-01: the field solvers step the problem `discretize` returns; base: refused, "discretize
    # with `LatticeDiscretization(…; problem = :owned)`")
        @test init(po, BackwardEuler(); dt = 0.1).sol.t == [0.0]
    @test solve(po, ImplicitEuler(); dt = 0.01, adaptive = false).retcode == ReturnCode.Success   # the route
    # the keywords
        for (f, want) in (
                (() -> BackwardEuler(; newton = 0), "BackwardEuler: newton = 0 is the Newton iterations"),
            (() -> BackwardEuler(; substeps = true), "BackwardEuler: substeps = true must be an integer ≥ 1"),
                (() -> BackwardEuler(; linsolve = :pcg), "BackwardEuler: `linsolve` takes `:auto`, a `DevicePCG(…)` or a `Multigrid(…)`"),
                (() -> BackwardEuler(; solver_type = BigFloat), "BackwardEuler: `solver_type` takes `:auto`"),
                (() -> BackwardEuler(; theta = 1), "BackwardEuler: no keyword `theta`; its keywords are `substeps`, `newton`, `lower_bound`, `linsolve`, `solver_type`, `init` and `compute_type`"),
            )
        @test startswith(e(f), want) || (println("MSG: ", e(f)); false)
    end
        a = BackwardEuler(; newton = 2, linsolve = DevicePCG(; maxiters = 12))
    @test eval(Meta.parse(repr(a))) == a
    # a map group has no implicit operator
    pm = discretize(PDESystem([Shift(t, 1)(bce) ~ 0.5 * bce], [bc(0, x, y) ~ x], bdom(), [t, x, y], [bce], Any[]; name = :m),
        LatticeDiscretization(Grid(BDIMS); T = Float64))
        @test occursin("a map program is stepped by ExplicitMap()", e(() -> init(pm, BackwardEuler(); dt = 1.0)))
end
end

@testitem "R1: StalledSuccess does not skip the later groups" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
@testset "R1: StalledSuccess does not skip the later groups" begin
    p = gown(gsys())
    for (code, moves) in ((ReturnCode.StalledSuccess, true), (ReturnCode.ConvergenceFailure, false))
            ig = init(p, FieldGroups(gce => StallStub(code); default = ExplicitEuler()); dt = 0.01)
        o0 = copy(ig[goe])
        step!(ig)
        @test (ig[goe] != o0) == moves && ig.retcode == code
    end
end
end
