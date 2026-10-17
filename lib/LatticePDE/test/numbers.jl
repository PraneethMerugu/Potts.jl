# Number types through problems (P5 role model, test matrix rows of C5/C6/C7a): Dual
# derivatives against finite differences on the owned and ODE paths, Rodas5P (Jacobian and
# time gradient through the right side), the BigFloat reference, promotion and plan reuse,
# and hoisted time. Each row has a negative control.
using ForwardDiff: ForwardDiff
using OrdinaryDiffEqRosenbrock: Rodas5P
using LatticeFields: Compile
using SciMLStructures: SciMLStructures, Tunable

@parameters Dn = 0.5 kn = 0.3 gn = 1.0 ωn = 3.0 K0n = 0.2
nsys(; T = 0.1) = psys([D(ce) ~ Dn * Δ(ce) - kn * ce],
    [c(0, x, y) ~ 0.0, c(t, 0, y) ~ gn, Differential(x)(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)],
    [Dn, kn, gn]; T)
fd(f, x; h = 1e-6) = (f(x + h) - f(x - h)) / (2h)
pidx(prob, s) = LatticePDE.Problems.SII.parameter_index(prob, s)
withp(p, i, v) = (q = collect(promote_type(eltype(p), typeof(v)), p); q[i] = v; q)

@testset "AD vs FD: owned path (∂J/∂D, ∂J/∂k, ∂J/∂g)" begin
    prob = owned(nsys(), 8, 4)
    alg = ExplicitEuler(; dt = 0.01)
    for s in (Dn, kn, gn)
        i = pidx(prob, s)
        Jo(v) = sum(solve(remake(prob; p = withp(prob.p, i, v)), alg).u[end])
        v0 = prob.p[i]
        d = ForwardDiff.derivative(Jo, v0)
        @test d isa Float64 && isapprox(d, fd(Jo, v0); rtol = 1e-6)
        @test d != 0
        # pairs form promotes the vector too
        Jp(v) = sum(solve(remake(prob; p = [s => v]), alg).u[end])
        @test ForwardDiff.derivative(Jp, v0) ≈ d
    end
    # negative control: a remake that drops the derivative parts gives 0
    i = pidx(prob, Dn)
    Jdrop(v) = sum(solve(remake(prob; p = withp(prob.p, i, ForwardDiff.value(v))), alg).u[end])
    @test ForwardDiff.derivative(Jdrop, prob.p[i]) == 0
    # Float32 state: the derivative in Dual{Float32} agrees to Float32 accuracy
    p32 = owned(nsys(), 8, 4; T = Float32)
    J32(v) = sum(solve(remake(p32; p = withp(p32.p, i, v)), alg).u[end])
    J64(v) = sum(solve(remake(prob; p = withp(prob.p, i, v)), alg).u[end])
    @test isapprox(ForwardDiff.derivative(J32, p32.p[i]), ForwardDiff.derivative(J64, prob.p[i]); rtol = 1e-3)
    # the substep count is a policy on the primal values: unchanged under Duals
    @test solve(remake(prob; p = withp(prob.p, i, ForwardDiff.Dual(prob.p[i], 1.0))), alg).substeps ==
          solve(prob, alg).substeps
end

@testset "AD vs FD: ODE path, with an aux field" begin
    @variables K(..)
    Kn = K(t, x, y)
    sys = psys([D(ce) ~ Dn * Δ(ce) - Kn * ce, Kn ~ K0n * (1 + gn)],
        [c(0, x, y) ~ 0.0, c(t, 0, y) ~ gn, Differential(x)(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)],
        [Dn, gn, K0n]; dvs = [ce, Kn])
    ode = discretize(sys, LatticeDiscretization(Grid((8, 4)); T = Float64, problem = :ode))
    for s in (Dn, gn, K0n)
        i = pidx(ode.f.sys, s)
        Jd(v) = (pv = withp(ode.p, i, v);
                sum(solve(remake(ode; p = pv, u0 = eltype(pv).(ode.u0)), Tsit5(); abstol = 1e-12,
                          reltol = 1e-12).u[end]))
        v0 = ode.p[i]
        d = ForwardDiff.derivative(Jd, v0)
        @test isapprox(d, fd(Jd, v0); rtol = 1e-6) && d != 0
    end
    # Dual parameters through `remake(; p)` alone (SciMLBase promotes `u0` or the right side
    # runs its Dual variant)
    i = pidx(ode.f.sys, Dn)
    J2(v) = sum(solve(remake(ode; p = withp(ode.p, i, v)), Tsit5(); abstol = 1e-12, reltol = 1e-12).u[end])
    @test isapprox(ForwardDiff.derivative(J2, ode.p[i]), fd(J2, ode.p[i]); rtol = 1e-6)
end

@testset "Rodas5P (Jacobian and time gradient through the right side)" begin
    sys = psys([D(ce) ~ Dn * Δ(ce) - kn * ce + 0.1 * sin(ωn * t)],
        [c(0, x, y) ~ 0.0, c(t, 0, y) ~ gn, Differential(x)(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)],
        [Dn, kn, gn, ωn])
    for T in (Float64, Float32)
        ode = discretize(sys, LatticeDiscretization(Grid((8, 4)); T, problem = :ode))
        tol = T == Float64 ? 1e-8 : 1e-4
        r = solve(ode, Rodas5P(); abstol = tol, reltol = tol)
        ts = solve(ode, Tsit5(); abstol = tol, reltol = tol)
        @test SciMLBase.successful_retcode(r) && eltype(r.u[end]) == T
        @test isapprox(r.u[end], ts.u[end]; rtol = 100tol)
    end
end

@testset "BigFloat reference (host)" begin
    sys = nsys()
    alg = ExplicitEuler(; dt = 0.01)
    p64, pb, p32 = owned(sys, 8, 4), owned(sys, 8, 4; T = BigFloat), owned(sys, 8, 4; T = Float32)
    @test eltype(pb) == BigFloat && eltype(pb.u0) == BigFloat
    ib = init(pb, alg)
    @test all(a -> eltype(a) == BigFloat, ib.store.flat)
    @test all(b -> all(a -> !(eltype(a) <: AbstractFloat) || eltype(a) == BigFloat, b), ib.store.bufs)
    sb, s64, s32 = solve!(ib), solve(p64, alg), solve(p32, alg)
    @test eltype(sb.u[end]) == BigFloat
    err(a) = maximum(abs, Float64.(a.u[end]) .- s64.u[end]) / maximum(abs, s64.u[end])
    @test err(sb) <= 1e-12
    @test err(s32) >= 1e-9                    # negative control: Float32 storage (the old F32 lane)
    # a BigFloat `p` is kept, not cut to Float64; it is rounded once to the compute type
    rb = remake(p64; p = big.(p64.p))
    @test eltype(rb.p) == BigFloat && eltype(rb) == Float64
    @test isapprox(solve(rb, alg).u[end], s64.u[end]; rtol = 1e-14)
    # an unsupported state type is refused by name
    @test_throws ArgumentError owned(sys, 8, 4; T = Int)
end

@testset "promotion and plan reuse" begin
    sys = nsys()
    alg = ExplicitEuler(; dt = 0.01)
    p32, p64 = owned(sys, 8, 4; T = Float32), owned(sys, 8, 4; T = Float64)
    up = remake(p32; u0 = Float64.(p32.u0))
    @test eltype(up) == Float64 && up.step !== p32.step
    @test isapprox(solve(up, alg).u[end], solve(p64, alg).u[end]; rtol = 1e-12)
    @test maximum(abs, solve(p32, alg).u[end] .- solve(p64, alg).u[end]) > 1e-9   # control
    # value-only remakes reuse the plans (no emission, no compile); a type comes back cached
    @test remake(p32; p = 2 .* p32.p).step === p32.step
    @test remake(p32; u0 = Float64.(p32.u0)).step === up.step
    # plain Float64 parameters never promote a Float32 state
    @test eltype(remake(p32; p = Float64.(p32.p))) == Float32
    # ODE: a Float32 build solved from a Float64 `u0` computes in Float64 (its own bodies)
    o32 = discretize(sys, LatticeDiscretization(Grid((8, 4)); T = Float32, problem = :ode))
    o64 = discretize(sys, LatticeDiscretization(Grid((8, 4)); T = Float64, problem = :ode))
    a = solve(remake(o32; u0 = Float64.(o32.u0)), Tsit5(); abstol = 1e-12, reltol = 1e-12).u[end]
    b = solve(o64, Tsit5(); abstol = 1e-12, reltol = 1e-12).u[end]
    @test eltype(a) == Float64 && isapprox(a, b; rtol = 1e-10)
end

@testset "SciMLStructures: p is a plain vector (Tunable = the scalars)" begin
    prob = owned(nsys(), 8, 4)
    @test SciMLStructures.isscimlstructure(prob.p)
    v, re, _ = SciMLStructures.canonicalize(Tunable(), prob.p)
    @test v == prob.p
    Jθ(θ) = sum(solve(remake(prob; p = SciMLStructures.replace(Tunable(), prob.p, θ)), ExplicitEuler(; dt = 0.01)).u[end])
    g = ForwardDiff.gradient(Jθ, v)
    i = pidx(prob, kn)
    @test isapprox(g[i], fd(x -> Jθ(withp(v, i, x)), v[i]); rtol = 1e-6)
end

@testset "hoisted time: sin(ω t) at t = 1e5 in Float32" begin
    T0 = 1e5
    sys = PDESystem([D(ce) ~ sin(ωn * t)], [c(T0, x, y) ~ 0.0, c(t, x, 0) ~ c(t, x, 1), c(t, 0, y) ~ c(t, 1, y)],
        [t ∈ Interval(T0, T0 + 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [ce], [ωn]; name = :tt)
    alg = ExplicitEuler(; dt = 0.01)
    a = solve(owned(sys, 4, 4; T = Float32), alg).u[end][1]
    b = solve(owned(sys, 4, 4; T = Float64), alg).u[end][1]
    @test abs(a - b) <= 1e-6
    # control: `sin(ω t)` evaluated with `t` in Float32 is off by more than 1e-3 at these times
    @test abs(sin(3.0f0 * Float32(T0 + 0.01)) - sin(3.0 * (T0 + 0.01))) > 1e-3
end
