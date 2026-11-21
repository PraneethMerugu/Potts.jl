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
    @test rate(tprob(sign(ce - kd))) == sign.(U0 .- 0.3)
    @test rate(tprob(mod(ce, kd))) == mod.(U0, 0.3)
    @test rate(tprob(rem(ce, kd))) == rem.(U0, 0.3)
    @test rate(tprob(mod(ce, -kd))) == mod.(U0, -0.3)
    # bitwise, including the sign of a zero: Base's `ifelse` form, not `min(max(…))`
    r, b = rate(tprob(clamp(ce, lo, hi))), clamp.(U0, -0.25, 0.5)
    @test r == b && signbit.(r) == signbit.(b)
    # the calls lower in Float32 as Base computes them in Float32
    U32 = Float32.(U0)
    @test rate(tprob(mod(ce, kd); T = Float32)) == mod.(U32, 0.3f0)
    @test rate(tprob(rem(ce, kd) + sign(ce); T = Float32)) == rem.(U32, 0.3f0) .+ sign.(U32)
    @test rate(tprob(clamp(ce, lo, hi); T = Float32)) == clamp.(U32, -0.25f0, 0.5f0)
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
