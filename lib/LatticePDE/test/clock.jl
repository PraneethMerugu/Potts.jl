# F2-08c: the discretization's clock (F2 design §2.6). `LatticeDiscretization(…; clock = τ)`
# sets the window of the owned steppers and the step index `k` that `step_index(t)` reads:
# an integer kept by the stepper (the clock boundaries reached since the start of the time
# span), never computed from a float time, so `k` does not depend on `dt` or `saveat`.
using LatticeFields: Problems as LFP
using LatticeFields.Compile: CompileOptions

@parameters kη = 0.5
@variables kc(..)
kce = kc(t, x, y)
kdom(T) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
kperiodic = [kc(t, 0, y) ~ kc(t, 1, y), kc(t, x, 0) ~ kc(t, x, 1)]
# the rate is the step index: c(T) = Σ over the windows of dt · k
ksys(T; rate = step_index(t)) = PDESystem([D(kce) ~ rate], [kc(0, x, y) ~ 0.0; kperiodic], kdom(T), [t, x, y], [kce], [kη];
    name = :k)
kdisc(; clock = 1.0, problem = :auto) = LatticeDiscretization(Grid((4, 4)); T = Float64, clock, problem)
kerr(f) = try
    f(); ""
catch e
    e isa ArgumentError || rethrow()
    sprint(showerror, e)
end

@testset "F2-08c: step_index(t) reads k by integer bookkeeping (B)" begin
    p = discretize(ksys(3.0), kdisc())
    @test p isa LFP.FieldProblem                                    # :auto takes the owned path
    finals = Float64[]
    for (dt, saveat) in ((0.1, 0.3), (0.1, 0.7), (0.25, 0.5), (0.25, 0.75))
        s = solve(p, ExplicitEuler(; dt); saveat)
        push!(finals, s[kce][end][1])
        # the state at each save time: Σ over the windows before it of dt · k
        per = round(Int, 1.0 / dt)                                  # windows per period
        for (tk, u) in zip(s.t, s[kce])
            want = sum(dt * div(j, per) for j in 0:(round(Int, tk / dt) - 1); init = 0.0)
            @test isapprox(u[1], want; atol = 1e-12)
        end
    end
    @test all(f -> isapprox(f, 3.0; rtol = 1e-12), finals)          # 0 · 1 + 1 · 1 + 2 · 1
    @test finals[1] == finals[2] && finals[3] == finals[4]          # the save times change nothing
    # the window of `ExplicitEuler()` without `dt` is the clock's period
    p2 = discretize(ksys(2.0), kdisc(; clock = 0.5))
    s = solve(p2, ExplicitEuler(); saveat = 0.5)
    @test s.t ≈ [0.0, 0.5, 1.0, 1.5, 2.0] && isapprox(s[kce][end][1], 0.5 * (0 + 1 + 2 + 3); rtol = 1e-12)
    # a `dt` that does not divide the period is refused, naming both (0.3 does not divide 0.5)
    e = kerr(() -> init(p2, ExplicitEuler(; dt = 0.3)))
    @test occursin("dt = 0.3", e) && occursin("period 0.5", e)
end

@testset "F2-08c: step_index refusals name their route (B)" begin
    @test occursin("clock = τ", kerr(() -> discretize(ksys(1.0), LatticeDiscretization(Grid((4, 4)); T = Float64))))
    @test occursin("F4", kerr(() -> discretize(ksys(1.0), kdisc(; problem = :ode))))
    @test occursin("argument", kerr(() -> discretize(ksys(1.0; rate = step_index(2t)), kdisc())))
    @parameters clock__tick = 1.0
    bad = PDESystem([D(kce) ~ clock__tick], [kc(0, x, y) ~ 0.0; kperiodic], kdom(1.0), [t, x, y], [kce], [clock__tick]; name = :b)
    @test occursin("reserved", kerr(() -> discretize(bad, kdisc())))
    @test occursin("clock", kerr(() -> LatticeDiscretization(Grid((4, 4)); clock = 0.0)))
    # the step index is the stepper's, not a parameter of the problem
    p = discretize(ksys(1.0), kdisc())
    @test !any(s -> occursin("clock__tick", string(s)), p.index.paramsyms)
end

# REAL forms of the step index over several windows, in the default and the debug emission
# modes: `η k` is hoisted into a derived parameter, `(1 + ε k)` multiplies the diffusion; a
# slot bound once would read the first window's `k` from the second window on
@testset "F2-08c: REAL forms of step_index over several windows (default and debug emission)" begin
    sysr = PDESystem([D(kce) ~ -kce + kη * step_index(t)], [kc(0, x, y) ~ 1.0; kperiodic], kdom(4.0), [t, x, y],
        [kce], [kη]; name = :r)
    p = discretize(sysr, kdisc())
    dbg = LFP.FieldProblem(p.group.spec, p.u0, p.tspan, p.p; index = p.index, options = CompileOptions(; debug = true))
    hand = 1.0
    for k in 0:3, _ in 1:4
        hand += 0.25 * (-hand + 0.5 * k)
    end
    for q in (p, dbg)
        s = solve(q, ExplicitEuler(; dt = 1.0, substeps = 4))
        @test all(v -> isapprox(v, hand; rtol = 1e-13), s[kce][end])
    end
    # the diffusion factor: a slow Fourier mode (it decays by about 0.12 per window, so each
    # window's factor shows), 16 substeps per window, hand FTCS on a periodic 4×4 grid of spacing 1
    c0 = [1.0 + cos(π * (i - 1) / 2) for i in 1:4, j in 1:4]
    sysd = PDESystem([D(kce) ~ (1 + kη * step_index(t)) * Δ(kce)], [kc(0, x, y) ~ 0.0; kc(t, 0, y) ~ kc(t, 4, y); kc(t, x, 0) ~ kc(t, x, 4)],
        [t ∈ Interval(0.0, 3.0), x ∈ Interval(0.0, 4.0), y ∈ Interval(0.0, 4.0)], [t, x, y], [kce], [kη]; name = :d)
    pd = discretize(sysd, LatticeDiscretization(Grid((4, 4)); T = Float64, clock = 1.0))
    pd = remake(pd; u0 = vec(c0))
    dd = LFP.FieldProblem(pd.group.spec, pd.u0, pd.tspan, pd.p; index = pd.index, options = CompileOptions(; debug = true))
    h = 1.0
    lap(c, i, j) = (c[mod1(i + 1, 4), j] + c[mod1(i - 1, 4), j] + c[i, mod1(j + 1, 4)] + c[i, mod1(j - 1, 4)] - 4c[i, j]) / h^2
    want = copy(c0)
    for k in 0:2, _ in 1:16
        want = [want[i, j] + (1 / 16) * (1 + 0.5 * k) * lap(want, i, j) for i in 1:4, j in 1:4]
    end
    for q in (pd, dd)
        s = solve(q, ExplicitEuler(; dt = 1.0, substeps = 16))
        @test isapprox(vec(s[kce][end]), vec(want); rtol = 1e-12)
    end
end

# Review round 1 of F2 batch 3: messages print `step_index(t)` (S1); a window that comes from
# the clock is named so, with routes that work when followed (S2); `step_index` with
# `FieldGroups` and with a map (S3); the clock's slot is not a parameter (N6)
@testset "F2-08c: messages and routes of the clock (B)" begin
    # S1: the slot prints as the user wrote it
    sysf = PDESystem([D(kce) ~ (1 + kη * step_index(t)) * Δ(kce)], [kc(0, x, y) ~ 0.0; kperiodic], kdom(2.0), [t, x, y],
        [kce], [kη]; name = :f)
    e = kerr(() -> solve(discretize(sysf, kdisc()), ExplicitEuler()))
    @test occursin("step_index(t)", e) && !occursin("clock__tick", e)
    sys0 = PDESystem([0 ~ -kce + step_index(t)], [kc(0, x, y) ~ 0.0; kperiodic], kdom(2.0), [t, x, y], [kce], [kη]; name = :z)
    e = kerr(() -> discretize(sys0, kdisc()))
    @test occursin("step_index(t)", e) && !occursin("clock__tick", e)
    # whole names only: a user parameter ending in `clock__tick` keeps its name
    @test LatticePDE._clocktext("`myclock__tick` and clock__tick") == "`myclock__tick` and step_index(t)"
    # S2: saveat against a window from the clock; the route works
    p = discretize(ksys(3.0), kdisc())
    e = kerr(() -> solve(p, ExplicitEuler(); saveat = 0.5))
    @test occursin("the clock's period, no `dt` given", e) && occursin("ExplicitEuler(; dt = 0.5)", e) && !occursin("dt = 1.0", e)
    @test solve(p, ExplicitEuler(; dt = 0.5); saveat = 0.5).t ≈ 0:0.5:3
    # a span of 2.5 periods; the route works
    p25 = discretize(ksys(2.5), kdisc())
    e = kerr(() -> solve(p25, ExplicitEuler()))
    @test occursin("the time span = 2.5", e) && occursin("ExplicitEuler(; dt = 0.5)", e)
    @test isapprox(solve(p25, ExplicitEuler(; dt = 0.5))[kce][end][1], 0.5 * (0 + 0 + 1 + 1 + 2); rtol = 1e-12)
    # two groups, one window from the clock and one `dt`; the route works, and `step_index`
    # reads the same `k` in both groups
    @variables kb(..)
    kbe = kb(t, x, y)
    sysg = PDESystem([D(kce) ~ step_index(t), D(kbe) ~ 2 * step_index(t)],
        [kc(0, x, y) ~ 0.0; kb(0, x, y) ~ 0.0; kperiodic; kb(t, 0, y) ~ kb(t, 1, y); kb(t, x, 0) ~ kb(t, x, 1)], kdom(3.0),
        [t, x, y], [kce, kbe], [kη]; name = :g)
    pg = discretize(sysg, kdisc())
    e = kerr(() -> solve(pg, FieldGroups(kbe => ExplicitEuler(; dt = 0.5); default = ExplicitEuler())))
    @test occursin("the clock's period, no `dt` given", e) && occursin("dt = 0.5", e)
    sg = solve(pg, FieldGroups(kbe => ExplicitEuler(; dt = 0.5, substeps = 2); default = ExplicitEuler(; dt = 0.5)))
    @test isapprox(sg[kce][end][1], 3.0; rtol = 1e-12) && isapprox(sg[kbe][end][1], 6.0; rtol = 1e-12)
    # a map: one step per unit of time; the clock is a whole number of map steps
    @variables km(..)
    kme = km(t, x, y)
    sysm(T) = PDESystem([Shift(t, 1)(kme) ~ kme + step_index(t)], [km(0, x, y) ~ 0.0; km(t, 0, y) ~ km(t, 1, y);
        km(t, x, 0) ~ km(t, x, 1)], kdom(T), [t, x, y], [kme], [kη]; name = :m)
    e = kerr(() -> solve(discretize(sysm(3.0), kdisc(; clock = 0.5))))
    @test occursin("whole number of map steps", e) && !occursin("dt", e)
    @test solve(discretize(sysm(3.0), kdisc(; clock = 1.0)))[kme][end][1] == 0 + 1 + 2      # k = 0, 1, 2
    @test solve(discretize(sysm(4.0), kdisc(; clock = 2.0)))[kme][end][1] == 0 + 0 + 1 + 1  # k = 0, 0, 1, 1
    # N6: the slot is not a parameter
    @test occursin("step_index(t)", kerr(() -> p.ps[:clock__tick]))
end
