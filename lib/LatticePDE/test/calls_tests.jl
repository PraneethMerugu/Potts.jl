# `sign`, `mod`, `rem` and `clamp` in field terms. `sign`, `mod` and `rem` lower to IR calls
# with Base's float methods as their bodies; `clamp(x, lo, hi)` lowers as Base defines it,
# `ifelse(x > hi, hi, ifelse(x < lo, lo, x))`. A special function (`erf`) or a registered
# function stays refused, and the message names the supported calls. Base (1db3d3bf): each
# of the four was refused ("has no lattice lowering").

@testsetup module LP_calls
using Test, LatticePDE
using ModelingToolkitBase: @parameters, @variables, PDESystem, t_nounits as t,
    D_nounits as D
using DomainSets: Interval
using SciMLBase: remake
using Symbolics: Symbolics, @register_symbolic
using ForwardDiff: ForwardDiff

@parameters x y kd = 0.3 lo = -0.25 hi = 0.5
@variables c(..)
const ce = c(t, x, y)
# values on both sides of 0 and of the bounds, both signed zeros and exact multiples of kd
const U0 = [
    -1.3, -0.6, -0.3, -0.0, 0.0, 0.1, 0.3, 0.5, 0.75, 1.9, -0.25, 0.6, 2.1, -2.0,
    0.45, -0.9,
]
function tsys(rhs, ps = [kd, lo, hi])
    return PDESystem(
        [D(ce) ~ rhs], [c(0, x, y) ~ 0.0],
        [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)],
        [t, x, y], [ce], ps; name = :calls
    )
end
function tprob(rhs; T = Float64, kw...)
    return discretize(tsys(rhs), LatticeDiscretization(Grid((4, 4)); T, kw...))
end
function rate(o, u0 = U0)
    u = convert.(eltype(o.u0), u0)
    du = similar(u)
    o.f(du, u, o.p, 0.0)
    return du
end
# a function with a numeric method that the lattice compiler does not take
mysq(v) = v * v
@register_symbolic mysq(v)
include("shared/export_all.jl")
end

@testitem "sign, mod, rem and clamp per site against Base" setup = [LP_calls] tags = [
    :latticepde, :calls,
] begin
    # bitwise, including the sign of a zero (`isequal` tells -0.0 from 0.0)
    @test all(isequal.(rate(tprob(sign(ce - kd))), sign.(U0 .- 0.3)))
    @test all(isequal.(rate(tprob(sign(ce))), sign.(U0)))      # (sign(-0.0) is -0.0)
    @test all(isequal.(rate(tprob(mod(ce, kd))), mod.(U0, 0.3)))
    @test all(isequal.(rate(tprob(rem(ce, kd))), rem.(U0, 0.3)))
    @test all(isequal.(rate(tprob(mod(ce, -kd))), mod.(U0, -0.3)))
    # Base's `ifelse` form for clamp, not `min(max(…))`
    @test all(isequal.(rate(tprob(clamp(ce, lo, hi))), clamp.(U0, -0.25, 0.5)))
    # the calls lower in Float32 as Base computes them in Float32
    U32 = Float32.(U0)
    @test all(isequal.(rate(tprob(mod(ce, kd); T = Float32)), mod.(U32, 0.3f0)))
    @test all(
        isequal.(
            rate(tprob(rem(ce, kd) + sign(ce); T = Float32)),
            rem.(U32, 0.3f0) .+ sign.(U32),
        )
    )
    @test all(
        isequal.(rate(tprob(clamp(ce, lo, hi); T = Float32)), clamp.(U32, -0.25f0, 0.5f0))
    )
end

@testitem "the new calls are on the one allowlist" setup = [LP_calls] tags = [
    :latticepde, :calls,
] begin
    @test all(LatticePDE.lowers_call, (sign, mod, rem, clamp))
    @test !any(LatticePDE.lowers_call, (Symbolics.SpecialFunctions.erf, mysq, hypot))
end

@testitem "a Dual parameter through mod and rem" setup = [LP_calls] tags = [
    :latticepde, :calls,
] begin
    # one explicit step: c(dt) = c(0) + dt f(c(0)), so the derivative in kd is Base's
    # (away from the jumps, where c / kd is an integer and the derivative is NaN)
    u0 = [
        -1.3, -0.7, -0.35, -0.1, 0.05, 0.1, 0.2, 0.5, 0.75, 1.9, -0.25, 0.65, 2.2, -2.0,
        0.45, -0.95,
    ]
    p = remake(tprob(mod(ce, kd) - rem(ce, 2kd)); u0, tspan = (0.0, 0.1))
    alg = ExplicitEuler(; substeps = 1)
    f(v) = sum(solve(remake(p; p = [kd => v]), alg; dt = 0.1).u[end])
    g(v) = sum(u0 .+ 0.1 .* (mod.(u0, v) .- rem.(u0, 2v)))
    @test ForwardDiff.derivative(f, 0.3) ≈ ForwardDiff.derivative(g, 0.3) rtol = 1.0e-12
end

@testitem "the stability bound reads sign, mod, rem and clamp" setup = [LP_calls] tags = [
    :latticepde, :calls,
] begin
    n(rhs, ps = []) = init(remake(tprob(rhs); p = ps), ExplicitEuler(); dt = 0.01).substeps
    base = n(1.0 * laplacian(ce))
    # clamp holds the coefficient at 1 for any kd above 1
    @test n(clamp(kd, 0.0, 1.0) * laplacian(ce), [kd => 100.0]) == base
    @test n(kd * laplacian(ce), [kd => 100.0]) > base       # control: no clamp
    # |mod(x, kd)| <= kd, |rem(x, kd)| <= kd and 0 <= 1 + sign(x - 1/2) <= 2
    @test n(mod(x, kd) * laplacian(ce), [kd => 1.0]) == base
    @test n(rem(x, kd) * laplacian(ce), [kd => 1.0]) == base
    @test n((1 + sign(x - 0.5)) * laplacian(ce) / 2) == base
    # controls: the bound follows kd up
    @test n(mod(x, kd) * laplacian(ce), [kd => 100.0]) > base
    @test n(rem(100x, kd) * laplacian(ce), [kd => 100.0]) > base
    # crossed bounds: the kernel's clamp gives `lo` (2) where x <= hi, so the bound is 2's
    @test n(clamp(kd, 2.0, 1.0) * laplacian(ce), [kd => 0.5]) == n(2.0 * laplacian(ce))
    @test n(2.0 * laplacian(ce)) > base                      # (control: 2 is above 1)
    # a divisor whose interval holds 0 bounds nothing; one that stays off 0 does
    @test_throws ArgumentError n(mod(1.0, x - 0.5) * laplacian(ce))
    @test_throws ArgumentError n(rem(1.0, x - 0.5) * laplacian(ce))
    @test n(mod(1.0, x + 0.5) * laplacian(ce)) >= base
end

@testitem "mod and rem on the implicit route equal the explicit one" setup = [
    LP_calls,
] tags = [:latticepde, :calls] begin
    # the local Jacobian takes `mod` and `rem` through `floor` and `ceil`; BackwardEuler and
    # explicit Euler at a small dt agree to first order
    rhs = 0.2 * laplacian(ce) + mod(ce, kd) - rem(ce, 2kd)
    u0 = [
        -1.3, -0.7, -0.35, -0.1, 0.05, 0.1, 0.2, 0.5, 0.75, 1.9, -0.25, 0.65, 2.2, -2.0,
        0.45, -0.95,
    ]
    p = remake(tprob(rhs); u0, tspan = (0.0, 0.2))
    se = solve(p, ExplicitEuler(); dt = 1.0e-4).u[end]
    si = solve(p, BackwardEuler(); dt = 1.0e-4).u[end]
    @test isapprox(si, se; rtol = 1.0e-3)
    # control: without the calls the run differs by far more
    p0 = remake(tprob(0.2 * laplacian(ce)); u0, tspan = (0.0, 0.2))
    s0 = solve(p0, ExplicitEuler(); dt = 1.0e-4).u[end]
    @test !isapprox(s0, se; rtol = 1.0e-2)
end

@testitem "a special or registered function stays refused" setup = [LP_calls] tags = [
    :latticepde, :calls,
] begin
    for rhs in (Symbolics.SpecialFunctions.erf(ce), mysq(ce))
        err = try
            tprob(rhs)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError && occursin("supported calls", sprint(showerror, err))
    end
end
