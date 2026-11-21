# Periodicity per field and axis: a field wraps on the axes of its own periodic pairs and is
# closed (its face conditions, zero flux by default) on the others, whatever the other
# fields do. Two fields with different periodicity in one system step as the two
# one-field systems do. Base (1db3d3bf): refused ("periodicity is per axis").

@testsetup module LP_field_periodicity
using Test, LatticePDE
using ModelingToolkitBase: @parameters, @variables, PDESystem, t_nounits as t,
    D_nounits as D
using DomainSets: Interval
using SciMLBase: remake
using ForwardDiff: ForwardDiff

@parameters x y Dc = 0.4 Dd = 0.3 kd = 0.2
@variables c(..) d(..)
const ce, de = c(t, x, y), d(t, x, y)
const NX, NY = 12, 8
# a bump off center on both axes, so a wrap and a closed face give different values
bump(x0, y0) = exp(-((x - x0)^2 + (y - y0)^2) / 0.02)
const RC = Dc * laplacian(ce)
const RD = Dd * laplacian(de) - kd * de
# `c` wraps on both axes; `d` wraps on y and is closed on x (zero flux by default, or the
# given faces)
const PC = [c(t, 0, y) ~ c(t, 1, y), c(t, x, 0) ~ c(t, x, 1), c(0, x, y) ~ bump(0.1, 0.9)]
const PD = [d(t, x, 0) ~ d(t, x, 1), d(0, x, y) ~ bump(0.85, 0.2)]
function psys(eqs, bcs, dvs, ps)
    return PDESystem(
        eqs, bcs,
        [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)],
        [t, x, y], dvs, ps; name = :per
    )
end
function prob(eqs, bcs, dvs, ps; T = Float64, tspan = (0.0, 0.2), kw...)
    p = discretize(psys(eqs, bcs, dvs, ps), LatticeDiscretization(Grid((NX, NY)); T, kw...))
    return remake(p; tspan)
end
# `ExplicitEuler(; substeps = 16)` is above the stability count of each system here, so
# every system takes 16 substeps and the runs compare bitwise
both(; kw...) = prob([D(ce) ~ RC, D(de) ~ RD], [PC; PD], [ce, de], [Dc, Dd, kd]; kw...)
onlyc(; kw...) = prob([D(ce) ~ RC], PC, [ce], [Dc]; kw...)
onlyd(; kw...) = prob([D(de) ~ RD], PD, [de], [Dd, kd]; kw...)
include("shared/export_all.jl")
end

@testitem "two fields of different periodicity equal the one-field systems" setup = [
    LP_field_periodicity,
] tags = [:latticepde, :field_periodicity] begin
    alg = ExplicitEuler(; substeps = 16)
    sb = solve(both(), alg; dt = 0.05)
    sc, sd = solve(onlyc(), alg; dt = 0.05), solve(onlyd(), alg; dt = 0.05)
    @test sb[ce, length(sb.t)] == sc[ce, length(sc.t)]
    @test sb[de, length(sb.t)] == sd[de, length(sd.t)]
    # the periodic field keeps its mass to round-off; `d` decays
    @test sum(sb[ce, length(sb.t)]) ≈ sum(sb[ce, 1]) rtol = 1.0e-13
    # control: `d` closed on x differs from `d` periodic on x
    dx = prob(
        [D(de) ~ RD], [d(t, 0, y) ~ d(t, 1, y); PD], [de], [Dd, kd]
    )
    @test !isapprox(solve(dx, alg; dt = 0.05)[de, 5], sd[de, 5]; rtol = 1.0e-6)
end

@testitem "a field closed by its own faces on an axis another field wraps" setup = [
    LP_field_periodicity,
] tags = [:latticepde, :field_periodicity] begin
    # `d` with a Dirichlet face at x = 0 and the default zero flux at x = 1
    fd = [d(t, 0, y) ~ 0.0; PD]
    alg = ExplicitEuler(; substeps = 16)
    pb = prob([D(ce) ~ RC, D(de) ~ RD], [PC; fd], [ce, de], [Dc, Dd, kd])
    sb = solve(pb, alg; dt = 0.05)
    sd = solve(prob([D(de) ~ RD], fd, [de], [Dd, kd]), alg; dt = 0.05)
    @test sb[de, length(sb.t)] == sd[de, length(sd.t)]
end

@testitem "implicit solves of a mixed group equal the one-field systems" setup = [
    LP_field_periodicity,
] tags = [:latticepde, :field_periodicity] begin
    # PCG with multigrid (deflated for the unanchored periodic field) and the stationary
    # multigrid, each per field with its own constant mode
    for ls in (
            LatticePCG(; reltol = 1.0e-12, maxiters = 64),
            LatticeMultigrid(; reltol = 1.0e-12, maxiters = 64),
        )
        alg = BackwardEuler(; linsolve = ls)
        sb = solve(both(), alg; dt = 0.05)
        sc, sd = solve(onlyc(), alg; dt = 0.05), solve(onlyd(), alg; dt = 0.05)
        @test isapprox(sb[ce, length(sb.t)], sc[ce, length(sc.t)]; rtol = 1.0e-10)
        @test isapprox(sb[de, length(sb.t)], sd[de, length(sd.t)]; rtol = 1.0e-10)
        @test sum(sb[ce, length(sb.t)]) ≈ sum(sb[ce, 1]) rtol = 1.0e-9
    end
end

@testitem "per-field periodicity in Float32 and with a Dual parameter" setup = [
    LP_field_periodicity,
] tags = [:latticepde, :field_periodicity] begin
    alg = ExplicitEuler(; substeps = 16)
    s64 = solve(both(), alg; dt = 0.05)
    s32 = solve(both(; T = Float32), alg; dt = 0.05f0)
    @test eltype(s32[ce, 1]) == Float32
    @test isapprox(s32[de, length(s32.t)], s64[de, length(s64.t)]; rtol = 1.0e-5)
    @test isapprox(s32[ce, length(s32.t)], s64[ce, length(s64.t)]; rtol = 1.0e-5)
    # the derivative in kd of the mixed system equals the one-field system's
    p, q = both(), onlyd()
    f(v) = sum(solve(remake(p; p = [kd => v]), alg; dt = 0.05).u[end])
    g(v) = sum(solve(remake(q; p = [kd => v]), alg; dt = 0.05).u[end])
    @test ForwardDiff.derivative(f, 0.2) ≈ ForwardDiff.derivative(g, 0.2) rtol = 1.0e-12
end

@testitem "periodicity conditions that stay refused" setup = [LP_field_periodicity] tags = [
    :latticepde, :field_periodicity,
] begin
    # a face condition on an axis the same field's pair makes periodic
    @test_throws ArgumentError prob(
        [D(ce) ~ RC], [PC; c(t, 0, y) ~ 1.0], [ce], [Dc]
    )
    # a pair that joins two different fields
    @test_throws ArgumentError prob(
        [D(ce) ~ RC, D(de) ~ RD], [c(t, 0, y) ~ d(t, 1, y)], [ce, de], [Dc, Dd, kd]
    )
end
