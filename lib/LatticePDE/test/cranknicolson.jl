# F3-10 (F3 design §3.3, §5): `CrankNicolson` in front end B. Each substep solves
# `(u − uⁿ)/h = (r(uⁿ) + r(u))/2` (`r(uⁿ)` at tⁿ, `r(u)` at tⁿ⁺¹) through the implicit runtime with
# the shift `2/h`; a start (init, `reset!`) is damped: two Backward Euler steps of `h/2` at
# tⁿ + h/2 and tⁿ + h, with the same operator. The tests compare with the hand matrices, the
# exact semi-discrete solution, a manufactured solution, step data and OrdinaryDiffEq's
# `Trapezoid`. Base (69bef544, ~/lpwork/f3b4-nc10-base.log): `CrankNicolson` is not defined
# (every testset errors). Negative controls (mutations of this tree, ~/lpwork/f3b4-nc10-*.log):
# no damped start (nodamp), `r(uⁿ)` at tⁿ⁺¹ (stage).
using OrdinaryDiffEqSDIRK: Trapezoid

# the manufactured solution `u = e^{−t} sin(πx) sin(πy) + t` (its source, the face value `t`) on
# [0, 1]², `dims` sites
function mf_problem(dims; kind = :owned)
    src = -exp(-t) * sin(π * x) * sin(π * y) + 1 + 2π^2 * 0.1 * exp(-t) * sin(π * x) * sin(π * y)
    faces = [bc(t, 0, y) ~ t, bc(t, 1, y) ~ t, bc(t, x, 0) ~ t, bc(t, x, 1) ~ t]
    ms = bsys([D(bce) ~ 0.1 * Δ(bce) + src], [bc(0, x, y) ~ sin(π * x) * sin(π * y); faces], Any[]; T = 1.0, dvs = [bce])
    return discretize(ms, LatticeDiscretization(Grid(dims); T = Float64, problem = kind))
end
mf_src(xx, yy, tt) = -exp(-tt) * sin(π * xx) * sin(π * yy) + 1 + 2π^2 * 0.1 * exp(-tt) * sin(π * xx) * sin(π * yy)
mf_faces(tt) = Dict((a, s) => (:dir, tt) for a in 1:2, s in (-1, 1))
# the hand rate `(L, b)` of the manufactured system on BDIMS at time `tt`
mf_rate(tt) = hand_rate(; K = (x, y) -> 0.1, f = (xx, yy) -> mf_src(xx, yy, tt), faces = mf_faces(tt))
# the errors and orders of `alg(dt)` against the semi-discrete solution (the `:ode` path, Tsit5
# at 1e-12), `m²` sites
function mf_orders(alg, dts; m = 32)
    ref = solve(mf_problem((m, m); kind = :ode), Tsit5(); reltol = 1e-12, abstol = 1e-12).u[end]
    pm = mf_problem((m, m))
    es = [maximum(abs, vec(blast(solve(pm, alg(dt)))) .- ref) for dt in dts]
    return es, log2.(es[1:(end - 1)] ./ es[2:end])
end
# the heat eigenmode `sin(πx) sin(πy)` with Dirichlet 0 faces (`n²` sites): the semi-discrete
# solution is `e^{D λ t} u0`, so the error is the time error alone
function eig_problem(n; T = 0.4)
    dirs = [bc(t, 0, y) ~ 0.0, bc(t, 1, y) ~ 0.0, bc(t, x, 0) ~ 0.0, bc(t, x, 1) ~ 0.0]
    sys = bsys([D(bce) ~ bD * Δ(bce)], [bc(0, x, y) ~ sin(π * x) * sin(π * y); dirs], [bD]; T, dvs = [bce])
    p = discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64, problem = :owned))
    λ = 2 * (2cos(π / n) - 2) * n^2
    u0 = [sin(π * (i - 0.5) / n) * sin(π * (j - 0.5) / n) for i in 1:n, j in 1:n]
    return p, λ, u0
end
# 1D step data on `n` sites with zero-flux faces, `k` windows of `h`
@variables b1(..)
function step1d(n, h; k = 10)
    s = PDESystem([D(b1(t, x)) ~ Δ(b1(t, x))], [b1(0, x) ~ ifelse(x < 0.5, 1.0, 0.0)],
        [t ∈ Interval(0.0, k * h), x ∈ Interval(0.0, 1.0)], [t, x], [b1(t, x)], Any[]; name = :s1)
    return discretize(s, LatticeDiscretization(Grid((n,)); T = Float64, problem = :owned))
end
tv1(u) = sum(abs, diff(vec(u)))
# `1.5 c − rb ∂c/∂x = 0.2` at x = 1 (rb = −1: a positive diagonal, rb = +1 a negative one)
function robin_sys(v)
    @parameters crb = v
    return PDESystem([D(bce) ~ 0.3 * Δ(bce) - 2 * bce + 1],
        [bc(0, x, y) ~ x * y, 1.5 * bc(t, 1, y) - crb * Differential(x)(bc(t, 1, y)) ~ 0.2], bdom(1.0), [t, x, y], [bce],
        [crb]; name = :crob), crb
end
# `p`'s state after each of `k` windows of `alg`
function windows(p, alg, k)
    ig = init(p, alg)
    return [(step!(ig); copy(vec(ig[bce]))) for _ in 1:k], ig
end

@testset "F3-10: CrankNicolson: order 2, the manufactured solution, the stages" begin
    p, λ, u0 = eig_problem(16)
    err(dt) = maximum(abs, blast(solve(p, CrankNicolson(; dt, inner = BTIGHT))) .- exp(0.3λ * 0.4) .* u0)
    es = [err(0.4 / 2^k) for k in 2:5]
    @test all(o -> abs(o - 2) < 0.1, log2.(es[1:(end - 1)] ./ es[2:end]))       # (measured 2.02, 2.01, 2.00)
    # the manufactured solution: `r(uⁿ)` at tⁿ, `r(u)` at tⁿ⁺¹, the damped start at tⁿ + h/2 and tⁿ + h
    em, om = mf_orders(dt -> CrankNicolson(; dt, inner = BTIGHT), [0.1 / 2^k for k in 0:3])
    @test all(o -> abs(o - 2) < 0.1, om) || (println("CN manufactured orders ", om); false)
    # two windows against the hand matrices: the first is the damped start (two Backward Euler
    # steps of h/2 at h/2 and h), the second a Crank–Nicolson step (r(uⁿ) at h, r(u) at 2h)
    h = 0.1
    p8 = mf_problem(BDIMS)
    u0 = vec(init(p8, CrankNicolson(; dt = h))[bce])
    us, ig = windows(p8, CrankNicolson(; dt = h, inner = BTIGHT), 2)
    half(u, tt) = (Lb = mf_rate(tt); (I - h / 2 * Lb[1]) \ (u .+ h / 2 .* Lb[2]))
    w1 = half(half(u0, h / 2), h)
    @test maximum(abs, us[1] .- w1) < 1e-9
    function cn(u, ta, tb)
        La, ba = mf_rate(ta)
        Lb, bb = mf_rate(tb)
        return (I - h / 2 * Lb) \ (u .+ h / 2 .* (La * u .+ ba .+ bb))
    end
    want, wrong = cn(us[1], h, 2h), cn(us[1], 2h, 2h)
    @test maximum(abs, us[2] .- want) < 1e-9 && maximum(abs, us[2] .- wrong) > 1e-3
    @test only(ig.runtimes).cache.newton == 1 && ig.retcode == ReturnCode.Success
end

@testset "F3-10: the damped start: step data, `reset!`, no extra rebuild" begin
    # 1D step data at z = h/dx² = 400 (P1 (b)): the total variation after the first step stays
    # ≤ 1 (plain Crank–Nicolson rings, TV 2.86: the nodamp control)
    n = 200
    h = 400 / n^2
    p = step1d(n, h)
    ig = init(p, CrankNicolson(; dt = h, inner = BTIGHT))
    step!(ig)
    @test tv1(ig[b1(t, x)]) <= 1 + 1e-9 || (println("TV ", tv1(ig[b1(t, x)])); false)
    # no extra rebuild: the two half steps share the operator (shift 2/h) with the later steps
    c = only(ig.runtimes).cache
    @test c.rebuilds == 1 && !c.start
    for _ in 1:3
        step!(ig)
    end
    @test c.rebuilds == 1 && tv1(ig[b1(t, x)]) <= 1 + 1e-9
    # a state write re-damps (`reset!`): the next window equals a fresh problem's first window
    # from the written state (damped), bitwise
    pe, _, _ = eig_problem(16)
    us, ig = windows(pe, CrankNicolson(; dt = 0.05, inner = BTIGHT), 2)
    v = 0.5 .* reshape(us[2], 16, 16) .+ 0.1
    ig[bce] = v
    @test only(ig.runtimes).cache.start
    step!(ig)
    fresh = init(remake(pe; u0 = vec(v)), CrankNicolson(; dt = 0.05, inner = BTIGHT))
    step!(fresh)
    @test vec(ig[bce]) == vec(fresh[bce])
    # (a Crank–Nicolson step from the same state differs: the write did restart it)
    nd = init(remake(pe; u0 = vec(v)), CrankNicolson(; dt = 0.05, inner = BTIGHT))
    only(nd.runtimes).cache.start = false
    step!(nd)
    @test maximum(abs, vec(nd[bce]) .- vec(fresh[bce])) > 1e-6
    @test bwarm(ig) == 0                                       # the warm window allocates nothing
end

@testset "F3-10: SX-18: OrdinaryDiffEq's Trapezoid with the start replicated" begin
    # the `:ode` path: two ImplicitEuler steps of h/2 (the damped start), then Trapezoid at h
    sx = bsys([D(bce) ~ bD * Δ(bce) - bk * bce + sin(3t) * x], [bc(0, x, y) ~ x * y, bc(t, 0, y) ~ 1.0], [bD, bk];
        T = 0.4, dvs = [bce])
    po = discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :ode))
    h = 0.05
    s0 = solve(po, ImplicitEuler(); dt = h / 2, adaptive = false, abstol = 1e-12, reltol = 1e-12, tspan = (0.0, h))
    st = solve(remake(po; u0 = s0.u[end], tspan = (h, 0.4)), Trapezoid(); dt = h, adaptive = false, abstol = 1e-12,
        reltol = 1e-12)
    sb = solve(discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :owned)),
        CrankNicolson(; dt = h, inner = BTIGHT))
    @test maximum(abs, vec(blast(sb)) .- st.u[end]) < 1e-8
end

@testset "F3-10: counts, components, parameter writes, messages" begin
    # the growth rule with the shift 2/h: `+ g c` needs n ≥ ⌈2 · ½ · dt g⌉ (Backward Euler: ⌈2 dt g⌉)
    pg = bown(bsys([D(bce) ~ bD * Δ(bce) + bk * bce], [bc(0, x, y) ~ x], [bD, bk]))
    @test init(pg, CrankNicolson(; dt = 0.5)).substeps == 1 && init(pg, BackwardEuler(; dt = 0.5)).substeps == 2
    # components: the operator and the run of the scalar spelling, bitwise
    @variables bu(..)[1:2]
    bue = bu(t, x, y)
    comp = nlsys([D(bue[1]) ~ 0.05 * Δ(bue[1]) - 40 * bue[1] / (0.025 + bue[1]) + 20, D(bue[2]) ~ 0.05 * Δ(bue[2]) - bue[2] + bue[1]],
        [bu(0, x, y)[1] ~ 0.5, bu(0, x, y)[2] ~ 0.0], [bue]; T = 0.3)
    scal = nlsys([D(bce) ~ 0.05 * Δ(bce) - 40 * bce / (0.025 + bce) + 20, D(boe) ~ 0.05 * Δ(boe) - boe + bce],
        [bc(0, x, y) ~ 0.5, bo(0, x, y) ~ 0.0], [bce, boe]; T = 0.3)
    a = @test_logs min_level = WARN solve(nlown(comp), CrankNicolson(; dt = 0.05))
    b = solve(nlown(scal), CrankNicolson(; dt = 0.05))
    @test a.stats == b.stats && a.stats.solves > 0
    @test a[bue[1], length(a.t)] == b[bce, length(b.t)] && a[bue[2], length(a.t)] == b[boe, length(b.t)]
    # a parameter write reclassifies as a fresh problem (a Robin face's sign; the count) and
    # restarts (damped), so the written run equals the fresh one
    for alg in (CrankNicolson(; dt = 0.1, inner = BTIGHT),), (v0, v1) in ((-1.0, 1.0), (1.0, -1.0))
        sys0, rb = robin_sys(v0)
        ig = init(nlown(sys0; dims = (10, 8)), alg)
        step!(ig)
        u = vec(ig[bce])
        ig.ps[rb] = v1
        fresh = init(remake(nlown(first(robin_sys(v1)); dims = (10, 8)); u0 = u), alg)
        c, cf = only(ig.runtimes).cache, only(fresh.runtimes).cache
        @test (c.exact, c.seen, c.newton, c.check, c.start, c.γ) == (cf.exact, cf.seen, cf.newton, cf.check, cf.start, cf.γ)
        @test ig.substeps == fresh.substeps
        step!(ig)
        step!(fresh)
        @test maximum(abs, vec(ig[bce]) .- vec(fresh[bce])) < 1e-12
    end
    # the keywords and messages name the algorithm
    e(f) = try
        f(); ""
    catch err
        err isa ArgumentError ? err.msg : sprint(showerror, err)
    end
    @test startswith(e(() -> CrankNicolson(; newton = 0)), "CrankNicolson: newton = 0 is the Newton iterations")
    @test e(() -> CrankNicolson(; theta = 0.5)) ==
          "CrankNicolson: no keyword `theta`; its keywords are `dt`, `substeps`, `newton`, `lower`, `inner` and `solver_T`"
    a = CrankNicolson(; dt = 0.1, newton = 2, inner = DevicePCG(; budget = 12))
    @test repr(a) == "CrankNicolson(; dt = 0.1, newton = 2, inner = DevicePCG(; budget = 12))"
    @test eval(Meta.parse(repr(a))) == a
    @test LFP.canonical(CrankNicolson()) ==
          "CrankNicolson(inner=:auto,lower=nothing,newton=nothing,solver_T=:auto,substeps=nothing)"
    phex = discretize(bsys([D(bce) ~ bD * Δ(bce)], [bc(0, x, y) ~ x], [bD]; dvs = [bce]),
        LatticeDiscretization(Grid((8, 8); geometry = HEX); T = Float64, problem = :owned))
    @test startswith(e(() -> init(phex, CrankNicolson(; dt = 0.1))),
        "CrankNicolson: field `bc`: a hexagonal lattice has no implicit solve yet")
    p16 = discretize(bsys([D(bce) ~ bD * Δ(bce)], [bc(0, x, y) ~ x], [bD]; dvs = [bce]),
        LatticeDiscretization(Grid(BDIMS); T = Float16, problem = :owned))
    @test startswith(e(() -> init(p16, CrankNicolson(; dt = 0.1))), "CrankNicolson: the field `bc` is stored as Float16")
end

# Review r2 S2: in front end B a group's count reads the group's own fields: the damped start
# rule of CrankNicolson sees another group's field (it moves between windows, so the group's
# data jump) and the growth rule sees only the group's rows. Base (773f0957,
# ~/lpwork/f3b5-nc-r2-s2.log): the other-group read counts 1 (the jump missed) and the growth
# of `bo` raises both groups' counts to 2.
@testset "F3-10/11 (r2 S2): B counts read the group's own fields" begin
    rd = bsys([D(bce) ~ 0.3 * Δ(bce) - bce + boe, D(boe) ~ 0.3 * Δ(boe) - boe], [bc(0, x, y) ~ 0.0, bo(0, x, y) ~ 1.0], Any[];
        T = 0.4, dvs = [bce, boe])
    p = discretize(rd, LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :owned))
    @test [r.n for r in init(p, FieldGroups(bce => CrankNicolson(; dt = 0.1), boe => BackwardEuler(; dt = 0.1))).runtimes] == [2, 1]
    @test only(init(p, CrankNicolson(; dt = 0.1)).runtimes).n == 1          # (the same group: no jump)
    gr = bsys([D(bce) ~ 0.3 * Δ(bce) - bce + x, D(boe) ~ 0.3 * Δ(boe) + bk * boe], [bc(0, x, y) ~ 0.0, bo(0, x, y) ~ x], [bk];
        T = 1.0, dvs = [bce, boe])
    p = discretize(gr, LatticeDiscretization(Grid((8, 8)); T = Float64, problem = :owned))
    ig = init(p, FieldGroups(bce => BackwardEuler(; dt = 0.5), boe => BackwardEuler(; dt = 0.5, inner = BTIGHT)))
    @test [r.n for r in ig.runtimes] == [1, 2]
    ig.ps[bk] = 4.0                                    # (a write: the counts again, `⌈2 · 0.5 · 4⌉`)
    @test [r.n for r in ig.runtimes] == [1, 4]
end
