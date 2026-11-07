# Review F4 b2 (#2, #5): `remake(prob; callback = cb)` keeps the built-in callbacks of the ODE path
# (the clock's step index, the masks) and adds `cb`; an owned solve honors `dense = false`; a warm
# window with a discrete or a continuous callback that does not fire allocates nothing (CPU).
# Negative control at 70400aba (~/lpwork/f4b2-rev2/nc-remakecb.log): the remade step_index model
# under Tsit5 is off by 0.139, `sol.dense` is true, the warm windows allocate 240 B and 2.7 KB.
using OrdinaryDiffEqTsit5: Tsit5

@parameters rD = 0.2
@variables rc(..) rq(..)::Int32 [input = true]
rce, rqe = rc(t, x, y), rq(t, x, y)
rdom(T) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]

@testset "review b2 #2: remake(prob; callback) keeps the clock and the masks" begin
    nop() = SciMLBase.DiscreteCallback((u, t, i) -> false, i -> nothing)
    tol = (; abstol = 1e-10, reltol = 1e-10)
    sk = PDESystem([D(rce) ~ -rce + 0.1 * step_index(t)], [rc(0, x, y) ~ x], rdom(1.0), [t, x, y], [rce], Num[]; name = :rk)
    p = discretize(sk, LatticeDiscretization(Grid((4, 3)); T = Float64, clock = 0.25))
    ref = solve(p, Tsit5(); tol...).u[end]
    @test maximum(abs, solve(remake(p; callback = nop()), Tsit5(); tol...).u[end] .- ref) < 1e-8
    @test maximum(abs, solve(remake(p; callback = nothing), Tsit5(); tol...).u[end] .- ref) < 1e-8
    # the given callback runs too, once (on the ODE path and on the owned one)
    n = Ref(0)
    cnt = SciMLBase.DiscreteCallback((u, t, i) -> true, i -> (n[] += 1; SciMLBase.derivative_discontinuity!(i, false));
        save_positions = (false, false))
    q = remake(p; callback = cnt)
    solve(q, ExplicitEuler(; dt = 0.125))
    @test n[] == 8
    @test count(LFP._builtin, (q.kwargs[:callback].discrete_callbacks..., q.kwargs[:callback].continuous_callbacks...)) ==
          count(LFP._builtin, (p.kwargs[:callback].discrete_callbacks..., p.kwargs[:callback].continuous_callbacks...))
    # a mask that switches on over a quiet state, remade with a callback: the mask still applies
    K = Int32[i == 1 ? 1 : 0 for i in 1:4, j in 1:3]
    ms = PDESystem([D(rce) ~ rD * Δ(rce) - rce], [rc(0, x, y) ~ 0.0, rce ~ masked((t > 0.3) & (rqe == 1), 2.0)],
        rdom(1.0), [t, x, y], [rce, rqe], [rD]; name = :rm)
    pm = discretize(ms, LatticeDiscretization(Grid((4, 3)); T = Float64); inputs = [rqe => K])
    o = solve(pm, ExplicitEuler(; dt = 1e-4)).u[end]
    b = solve(remake(pm; callback = nop()), Tsit5(); tol...).u[end]
    @test unique(b[vec(K .== 1)]) == [2.0] && maximum(abs, b .- o) < 1e-3
end

@testset "review b2 #5: dense = false; a warm window with callbacks allocates nothing" begin
    gs = PDESystem([D(rce) ~ rD * Δ(rce) - rce], [rc(0, x, y) ~ x * y], rdom(0.2), [t, x, y], [rce], [rD]; name = :rw)
    p = discretize(gs, LatticeDiscretization(Grid((16, 16)); T = Float64))
    @test !solve(p, ExplicitEuler(; dt = 0.01); saveat = 0.1, dense = false).dense
    @test solve(p, ExplicitEuler(; dt = 0.01); saveat = 0.1).dense
    warm(i) = (for _ in 1:5; step!(i); end; @allocated(step!(i)); @allocated(step!(i)))
    for cb in (SciMLBase.DiscreteCallback((u, t, i) -> false, i -> nothing),
            SciMLBase.ContinuousCallback((u, t, i) -> u[1] - 10.0, i -> nothing),
            SciMLBase.CallbackSet(SciMLBase.ContinuousCallback((u, t, i) -> u[1] - 10.0, i -> nothing),
                SciMLBase.VectorContinuousCallback((out, u, t, i) -> (out[1] = u[1] - 10.0; out[2] = u[2] - 10.0; nothing),
                    (i, k) -> nothing, 2),
                SciMLBase.DiscreteCallback((u, t, i) -> false, i -> nothing)))
        i = init(remake(p; tspan = (0.0, 100.0)), ExplicitEuler(; dt = 1e-3); callback = cb)
        @test warm(i) == 0 || (println("b2 #5 warm ", typeof(cb).name.name, " ", warm(i)); false)
    end
end
