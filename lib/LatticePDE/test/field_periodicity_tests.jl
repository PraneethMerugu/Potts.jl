# Periodicity per field and axis: a field wraps on the axes of its own periodic pairs and is
# closed (its face conditions, zero flux by default) on the others, whatever the other
# fields do. Two fields with different periodicity in one system step as the two
# one-field systems do. Base (1db3d3bf): refused ("periodicity is per axis").

@testsetup module LP_field_periodicity
using Test, LatticePDE
using ModelingToolkitBase: @parameters, @variables, PDESystem, t_nounits as t,
    D_nounits as D
using DomainSets: Interval
using SciMLBase: SciMLBase, remake
using ForwardDiff: ForwardDiff

@parameters x y Dc = 0.4 Dd = 0.3 kd = 0.2 kp = 0.3 chi = 0.05
@variables c(..) d(..) K(..) g(..) [input = true] dm(..)::Bool [input = true]
const ce, de, Ke, ge, dme = c(t, x, y), d(t, x, y), K(t, x, y), g(t, x, y), dm(t, x, y)
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
function prob(
        eqs, bcs, dvs, ps; T = Float64, tspan = (0.0, 0.2), inputs = nothing, kw...
    )
    disc = LatticeDiscretization(Grid((NX, NY)); T, kw...)
    sys = psys(eqs, bcs, dvs, ps)
    p = inputs === nothing ? discretize(sys, disc) : discretize(sys, disc; inputs)
    return remake(p; tspan)
end
# the message of the `ArgumentError` the call throws
function refusal(f::F) where {F}
    try
        f()
    catch e
        e isa ArgumentError && return e.msg
        rethrow()
    end
    return error("not refused")
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

@testitem "an aux field takes the periodicity of the fields it reads" setup = [
    LP_field_periodicity,
] tags = [:latticepde, :field_periodicity] begin
    alg = ExplicitEuler(; substeps = 16)
    # `K ~ kp * d` keeps `d`'s zero-flux face on x where `c` wraps (a wrapped `K` would
    # join the coefficient across the face)
    rk = DivKGrad(:arithmetic)(Ke, de) - kd * de
    mixed = prob(
        [D(ce) ~ RC, D(de) ~ rk, Ke ~ kp * de], [PC; PD], [ce, de, Ke], [Dc, kd, kp]
    )
    alone = prob([D(de) ~ rk, Ke ~ kp * de], PD, [de, Ke], [kd, kp])
    sb, sd = solve(mixed, alg; dt = 0.05), solve(alone, alg; dt = 0.05)
    @test sb[de, length(sb.t)] == sd[de, length(sd.t)]
    # control: `d` (and so `K`) wrapping on x differs
    wraps = prob(
        [D(de) ~ rk, Ke ~ kp * de], [d(t, 0, y) ~ d(t, 1, y); PD], [de, Ke], [kd, kp]
    )
    @test !isapprox(solve(wraps, alg; dt = 0.05)[de, 5], sd[de, 5]; rtol = 1.0e-6)
    # a neighbor read of `K` across `d`'s closed face has no value there
    @test occursin(
        "across a closed face of axis 1",
        refusal(
            () -> prob(
                [D(ce) ~ RC, D(de) ~ Dd * laplacian(Ke), Ke ~ kp * de],
                [PC; PD], [ce, de, Ke], [Dc, Dd, kp]
            )
        )
    )
    # control: with `d` wrapping on x too the read is a wrapped one
    @test prob(
        [D(ce) ~ RC, D(de) ~ Dd * laplacian(Ke), Ke ~ kp * de],
        [PC; d(t, 0, y) ~ d(t, 1, y); PD], [ce, de, Ke], [Dc, Dd, kp]
    ) isa SciMLBase.AbstractODEProblem
end

@testitem "an aux field of fields that wrap differently, read at a neighbor" setup = [
    LP_field_periodicity,
] tags = [:latticepde, :field_periodicity] begin
    # `K ~ c + d`: `c` wraps on x, `d` is closed there, so `K` beyond the x edge has no
    # single rule
    m = refusal(
        () -> prob(
            [D(ce) ~ RC + chi * laplacian(Ke), D(de) ~ RD, Ke ~ ce + de],
            [PC; PD], [ce, de, Ke], [Dc, Dd, kd, chi]
        )
    )
    @test occursin("`K`", m) && occursin("`c` wraps", m) && occursin("`d` is closed", m)
    # control: `K` read at its own site
    @test prob(
        [D(ce) ~ RC - chi * Ke, D(de) ~ RD, Ke ~ ce + de],
        [PC; PD], [ce, de, Ke], [Dc, Dd, kd, chi]
    ) isa SciMLBase.AbstractODEProblem
end

@testitem "an input read at a neighbor follows the fields' shared periodicity" setup = [
    LP_field_periodicity,
] tags = [:latticepde, :field_periodicity] begin
    G = [1.0 + 0.5 * sin(2pi * i / NX) + 0.1 * j for i in 1:NX, j in 1:NY]
    alg = ExplicitEuler(; substeps = 16)
    rg = DivKGrad(:arithmetic)(ge, de) - kd * de
    # `d`, closed on x, reads `g` across x as it does alone: `g` is closed where any field
    # is
    mixed = prob(
        [D(ce) ~ RC, D(de) ~ rg], [PC; PD], [ce, de, ge], [Dc, kd]; inputs = [ge => G]
    )
    alone = prob([D(de) ~ rg], PD, [de, ge], [kd]; inputs = [ge => G])
    sb, sd = solve(mixed, alg; dt = 0.05), solve(alone, alg; dt = 0.05)
    @test sb[de, length(sb.t)] == sd[de, length(sd.t)]
    # control: `g` wrapped on x (both fields wrap) changes `d`
    wraps = prob(
        [D(de) ~ rg], [d(t, 0, y) ~ d(t, 1, y); PD], [de, ge], [kd]; inputs = [ge => G]
    )
    @test !isapprox(solve(wraps, alg; dt = 0.05)[de, 5], sd[de, 5]; rtol = 1.0e-6)
    # `c` wraps on x, where `g` is closed: refused
    m = refusal(
        () -> prob(
            [D(ce) ~ DivKGrad(:arithmetic)(ge, ce), D(de) ~ RD], [PC; PD],
            [ce, de, ge], [Dd, kd]
        )
    )
    @test occursin("`c` reads `g` at a neighbor site on axis 1", m)
    # control: with every field wrapping, `c` reads `g` wrapped
    @test prob(
        [D(ce) ~ DivKGrad(:arithmetic)(ge, ce), D(de) ~ RD],
        [PC; d(t, 0, y) ~ d(t, 1, y); PD], [ce, de, ge], [Dd, kd]
    ) isa SciMLBase.AbstractODEProblem
end

@testitem "a domain mask with fields that wrap differently" setup = [
    LP_field_periodicity,
] tags = [:latticepde, :field_periodicity] begin
    m = refusal(
        () -> prob(
            [D(ce) ~ RC, D(de) ~ RD], [PC; PD], [ce, de, dme], [Dc, Dd, kd];
            domain = dm
        )
    )
    @test occursin("differ on axis 1", m)
    # control: one field (one periodicity) takes the mask
    @test prob([D(de) ~ RD], PD, [de, dme], [Dd, kd]; domain = dm) isa
        SciMLBase.AbstractODEProblem
end

@testitem "a read of another state field follows that field's conditions" setup = [
    LP_field_periodicity,
] tags = [:latticepde, :field_periodicity] begin
    # `c` wraps on x and `d` is closed there; each rate reads the other through a
    # Laplacian, which takes the read field's rule (as in MethodOfLines)
    eqs = [
        D(ce) ~ RC + chi * laplacian(de),
        D(de) ~ RD + chi * laplacian(ce),
    ]
    pp = (Dc = 0.4, Dd = 0.3, kd = 0.2, chi = 0.05)
    pb = prob(eqs, [PC; PD], [ce, de], [Dc, Dd, kd, chi])
    # one Euler step at a small dt: its rate at the x edges against a hand five-point rate
    dt = 1.0e-4
    s = solve(pb, ExplicitEuler(; substeps = 1); dt, tstops = [dt], saveat = [0.0, dt])
    c0, d0 = s[ce, 1], s[de, 1]
    rc, rd = (s[ce, 2] - c0) / dt, (s[de, 2] - d0) / dt
    hx, hy = 1 / NX, 1 / NY
    wrap(i, n) = mod1(i, n)
    mirror(i, n) = clamp(i, 1, n)   # zero flux: the ghost equals the edge site
    function lap(u, i, j, xi)
        return (u[xi(i + 1, NX), j] + u[xi(i - 1, NX), j] - 2u[i, j]) / hx^2 +
            (u[i, wrap(j + 1, NY)] + u[i, wrap(j - 1, NY)] - 2u[i, j]) / hy^2
    end
    # (the rows of both bumps)
    off = 0.0
    for i in (1, NX), j in (2, 7)
        hc = pp.Dc * lap(c0, i, j, wrap) + pp.chi * lap(d0, i, j, mirror)
        hd = pp.Dd * lap(d0, i, j, mirror) + pp.chi * lap(c0, i, j, wrap) -
            pp.kd * d0[i, j]
        @test rc[i, j] ≈ hc rtol = 1.0e-7
        @test rd[i, j] ≈ hd rtol = 1.0e-7
        # control: `c` read with `d`'s rule in `d`'s rate
        hm = pp.Dd * lap(d0, i, j, mirror) + pp.chi * lap(c0, i, j, mirror) -
            pp.kd * d0[i, j]
        off = max(off, abs(rd[i, j] - hm) / abs(hm))
    end
    @test off > 1.0e-2
    # explicit against BackwardEuler: both first order, so their gap shrinks as dt (one
    # substep: the coupled rows have no automatic bound, and these steps are stable)
    ee = ExplicitEuler(; substeps = 1)
    be = BackwardEuler(; linsolve = LatticePCG(; reltol = 1.0e-12))
    fin(s, u) = s[u, length(s.t)]
    function gap(dt)
        se, si = solve(pb, ee; dt), solve(pb, be; dt)
        return maximum(
            u -> sqrt(sum(abs2, fin(si, u) - fin(se, u)) / sum(abs2, fin(se, u))),
            (ce, de)
        )
    end
    g1, g2 = gap(1.0e-3), gap(2.5e-4)
    @test 3 < g1 / g2 < 5
    @test g2 < 2.0e-3
    se = solve(pb, ee; dt = 2.5e-4)
    # control: the uncoupled pair differs by far more than that
    pu = prob([D(ce) ~ RC, D(de) ~ RD], [PC; PD], [ce, de], [Dc, Dd, kd])
    su = solve(pu, ee; dt = 2.5e-4)
    @test !isapprox(fin(su, de), fin(se, de); rtol = 2.0e-2)
end
