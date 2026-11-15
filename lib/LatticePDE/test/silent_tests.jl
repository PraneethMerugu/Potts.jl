# F1: no silent wrong results from `discretize` (refusal inventory SD-04 … SD-12, V3, and the
# misleading messages of LatticePDE). Each testset has a negative control: the comment gives
# the wrong value the base f9a77dd3 returned, measured on the PC (probe of 2026-10-18).

@testsetup module LP_silent
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
include("shared/silent.jl")
include("shared/export_all.jl")
end

@testitem "SD-04: a rate and a map in one system are refused, naming both" setup = [LP_silent] tags = [:latticepde, :silent] begin
@testset "SD-04: a rate and a map in one system are refused, naming both" begin
    # base: `ExplicitMap` stepped the rate at dt = 1: c(1) = −4.0 where exp(−5) ≈ 0.0067, Success
    sys = ssys([D(ce) ~ -5ce, Shift(t, 1)(me) ~ me + 1], [c(0, x, y) ~ 1.0, mm(0, x, y) ~ 0.0], [ce, me], Num[])
    err = emsg(() -> sown(sys))
    @test occursin("mixes rate equations", err) && occursin("`c`", err) && occursin("`mm`", err)
    # control: the map alone runs
    m = sown(ssys([Shift(t, 1)(me) ~ me + 1], [mm(0, x, y) ~ 0.0], [me], Num[]))
    @test solve(m, ExplicitMap())[:mm, end][1] == 1.0
end
end

@testitem "SD-05, SD-06: parameters with no value are named" setup = [LP_silent] tags = [:latticepde, :silent] begin
@testset "SD-05, SD-06: parameters with no value are named" begin
    # an array parameter with no default (base: a zero-length table; c stayed 1.0, Success)
    @parameters Dz[1:2]
    err = emsg(() -> sown(ssys([D(ce) ~ -Dz[2] * ce], [c(0, x, y) ~ 1.0], [ce], [Dz])))
    @test occursin("`Dz`", err) && occursin("no value", err)
    # a scalar with no default (base: p = [NaN], c = NaN, Unstable; the ODE path p = [NaN])
    @parameters kz
    sys = ssys([D(ce) ~ -kz * ce], [c(0, x, y) ~ 1.0], [ce], [kz])
    p = sown(sys)
    err = emsg(() -> solve(p, ExplicitEuler(; dt = 0.1)))
    @test occursin("`kz`", err) && occursin("no value", err)
    # … and remake gives it one (the owned route): c(1) = (1 − 0.1 k)^10
    s = solve(remake(p; p = [kz => 2.0]), ExplicitEuler(; dt = 0.1, substeps = 1))
    @test s[:c, end][1] ≈ 0.8^10
    # (F4-01: `discretize` returns the one problem, which `remake` gives a value; base: refused
    # at `discretize`, naming `initial_conditions`) an OrdinaryDiffEq solve names it
    err = emsg(() -> solve(discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64)), Tsit5()))
    @test occursin("`kz`", err) && occursin("no value", err)
    # setp to NaN is refused and leaves the integrator unchanged
    integ = init(remake(p; p = [kz => 2.0]), ExplicitEuler(; dt = 0.1))
        @test_throws ["ArgumentError", "`kz` has no value", "NaN"] setp(integ, kz)(integ, NaN)
    @test integ.p == [2.0]
end
end

@testitem "SD-12: a computed default follows its parameters" setup = [LP_silent] tags = [:latticepde, :silent] begin
@testset "SD-12: a computed default follows its parameters" begin
    # base: "Cannot convert Sym to Float64" from `_default`
    @parameters a0 = 1.0
    @parameters k2 = 2a0
    sys = ssys([D(ce) ~ -k2 * ce], [c(0, x, y) ~ 1.0], [ce], [a0, k2])
    p = sown(sys)
    alg = ExplicitEuler(; dt = 0.01, substeps = 1)
    @test solve(p, alg)[:c, end][1] ≈ (1 - 0.02)^100
    # a remake of a0 moves k2 (= 6), never leaving it stale
    @test solve(remake(p; p = [a0 => 3.0]), alg)[:c, end][1] ≈ (1 - 0.06)^100
    @test occursin("computed", emsg(() -> remake(p; p = [k2 => 5.0])))
    # the ODE path folds it too
    o = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64))
    os = SciMLBase.solve(o, Tsit5(); abstol = 1e-10, reltol = 1e-10)
    @test os.u[end][1] ≈ exp(-2) rtol = 1e-6
    # a field's `initial_conditions` value reads it too (round 0: "`k2` reads k2")
    s7 = PDESystem([D(ce) ~ -a0 * ce], Equation[], sdom(), [t, x, y], [ce], [a0, k2]; name = :s7,
        initial_conditions = Dict(ce => k2))
    @test solve(sown(s7), alg)[:c, 1][1] == 2.0
    # a computed parameter reads (round 1: reading threw the "computed" message)
    @test getp(o, k2)(o) == 2.0 && o.ps[k2] == 2.0 && os.ps[k2] == 2.0 && getp(os, k2)(os) == 2.0
    @test remake(o; p = [a0 => 3.0]).ps[k2] == 6.0
    @test getp(o, [a0, k2])(o) == [1.0, 2.0] && getp(o, (k2, a0))(o) == (2.0, 1.0)
    pi1 = init(p, alg)
    @test pi1[k2] == 2.0 && getp(pi1, k2)(pi1) == 2.0
    @test occursin("computed", emsg(() -> (pi1[:k2] = 5.0)))      # (round 2: "Invalid symbol k2 for `setsym`")
    # an unknown name lists the names (round 2: SII's "Invalid symbol")
    err = emsg(() -> pi1[:kd])
    @test occursin("`:kd` names nothing", err) && occursin("`a0`", err) && !occursin("Invalid symbol", err)
    ix = o.f.sys                                                  # SII: parameters agree with their list
    @test all(q -> SymbolicIndexingInterface.is_parameter(ix, q), SymbolicIndexingInterface.parameter_symbols(ix))
    @test !SymbolicIndexingInterface.is_parameter(ix, k2) && SymbolicIndexingInterface.is_observed(ix, k2)
    @test occursin("computed", emsg(() -> setp(pi1, k2)(pi1, 5.0)))
    # … and refuses a remake of k2 by name (round 0: a silent no-op, the run kept k2 = 2)
    err = emsg(() -> remake(o; p = [k2 => 5.0]))
    @test occursin("`k2`", err) && occursin("computed", err)
    # a face value may read a computed parameter (F2-15: a slot; before: refused, "`gs = g1 +
    # g2` … give `gs` a number"), equal to the number, and it follows its inputs
    @parameters g1 = 1.0 g2 = 2.0
    @parameters gs = g1 + g2
    pg = sown(ssys([D(ce) ~ Δ(ce)], [c(0, x, y) ~ 0.0, c(t, 0, y) ~ gs], [ce], [g1, g2, gs]))
    @parameters g3 = 3.0 g4 = 5.0
    p3 = sown(ssys([D(ce) ~ Δ(ce)], [c(0, x, y) ~ 0.0, c(t, 0, y) ~ g3], [ce], [g3]))
    p5 = sown(ssys([D(ce) ~ Δ(ce)], [c(0, x, y) ~ 0.0, c(t, 0, y) ~ g4], [ce], [g4]))
    @test solve(pg, alg)[:c, end] == solve(p3, alg)[:c, end]
    @test solve(remake(pg; p = [g1 => 3.0]), alg)[:c, end] == solve(p5, alg)[:c, end]
    # the ODE integrator's `setp` of an input moves k2 at the next step (the right side derives it)
    oi = SciMLBase.init(o, Tsit5(); abstol = 1e-10, reltol = 1e-10)
    setp(oi, a0)(oi, 3.0)
    SciMLBase.step!(oi, 0.5, true)
    @test isapprox(oi.u[1], exp(-3); rtol = 1e-6) && oi.ps[k2] == 6.0
    # the message names the inputs and the route (D-F2-1)
    @test occursin("`k2` is computed from `a0` (`k2 = 2a0`): set `a0`", emsg(() -> remake(p; p = [k2 => 5.0])))
end
end

@testitem "SD-09: negative diffusion is refused, with the route" setup = [LP_silent] tags = [:latticepde, :silent] begin
@testset "SD-09: negative diffusion is refused, with the route" begin
    # base: Dn = −0.01 ran (1 substep, Success): anti-diffusion over the run
    @parameters Dn = -0.01
    sys = ssys([D(ce) ~ Dn * Δ(ce)], [c(0, x, y) ~ x], [ce], [Dn])
    p = sown(sys)
    for alg in (ExplicitEuler(; dt = 0.1), ExplicitEuler(; dt = 0.1, substeps = 3))
        err = emsg(() -> solve(p, alg))
        @test occursin("negative", err) && occursin("`c`", err) && occursin("≥ 0", err)
    end
    # (F4-01: an OrdinaryDiffEq solve refuses it at its first call, as a field algorithm at `init`;
    # base: at `discretize` of the ODE problem)
    @test occursin("negative", emsg(() -> SciMLBase.solve(discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64)), Tsit5())))
    # setp into the negative range is refused atomically
    q = remake(p; p = [Dn => 0.01])
    integ = init(q, ExplicitEuler(; dt = 0.1))
        @test_throws ["ArgumentError", "is negative", "`c`"] setp(integ, Dn)(integ, -1.0)
    @test integ.p == [0.01]
    # the ODE path checks every new parameter value, not only at `discretize` (base: remake to
    # −1.0 gave Success with values of ±1e22; NaN through remake and setp were accepted)
    @parameters Dp = 0.01
    o = discretize(ssys([D(ce) ~ Dp * Δ(ce)], [c(0, x, y) ~ x], [ce], [Dp]; T = 0.1),
        LatticeDiscretization(Grid((4, 4)); T = Float64))
    @test SciMLBase.solve(o, Tsit5()).retcode == SciMLBase.ReturnCode.Success          # control
    @test SciMLBase.solve(remake(o; p = [Dp => 0.02]), Tsit5()).retcode == SciMLBase.ReturnCode.Success
    err = emsg(() -> SciMLBase.solve(remake(o; p = [Dp => -1.0]), Tsit5()))
    @test occursin("negative", err) && occursin("`c`", err)
    err = emsg(() -> SciMLBase.solve(remake(o; p = [Dp => NaN]), Tsit5()))
    @test occursin("`Dp`", err) && occursin("no value", err)
    f = o.f.f
    du = similar(o.u0)
    f(du, o.u0, o.p, 0.0)
    @test (@allocated f(du, o.u0, o.p, 0.0)) == 0                       # unchanged p: no check, no allocation
    ig = init(remake(o; p = [Dp => 0.01]), Tsit5())
    step!(ig)
    setp(ig, Dp)(ig, -1.0)
    @test occursin("negative", emsg(() -> step!(ig)))                # the next call refuses it
    ig2 = init(remake(o; p = [Dp => 0.01]), Tsit5())
    setp(ig2, Dp)(ig2, NaN)
    @test occursin("setp(integ, Dp)", emsg(() -> step!(ig2)))      # the route names setp (round 1: remake only)
    # the routes the messages give are LatticePDE's names too (round 1: not exported)
    @test LatticePDE.remake === SciMLBase.remake && LatticePDE.setp === setp && isdefined(LatticePDE, :getp) &&
          isdefined(LatticePDE, :getu)
end
end

@testitem "SD-08: masks are evaluated at every step" setup = [LP_silent] tags = [:latticepde, :silent] begin
@testset "SD-08: masks are evaluated at every step" begin
    # a time mask switches on (base: c(1) = 0.0, the mask frozen at t0)
    s = solve(sown(ssys([D(ce) ~ 0.0], [c(0, x, y) ~ 0.0, ce ~ masked(t > 0.5, 1.0)], [ce], Num[])),
        ExplicitEuler(; dt = 0.1); saveat = 0.1)
    @test all(==(1.0), s[:c, end])
    @test all(==(0.0), s[:c, 2])                                 # t = 0.1: not yet
    # a field mask clamps (base: c(1) = 1.5, the clamp never engaged)
    s = solve(sown(ssys([D(ce) ~ 1.0], [c(0, x, y) ~ 0.5, ce ~ masked(ce > 0.9, 0.0)], [ce], Num[])),
        ExplicitEuler(; dt = 0.1); saveat = 0.1)
    @test maximum(u -> maximum(u), s.u) <= 1.0 + 1e-12
    @test any(u -> u[1] == 0.0, s.u[2:end])                      # the clamp engaged
end
end

@testitem "SD-08: the masked values hold from t0 and right after an input write" setup = [LP_silent] tags = [:latticepde, :silent] begin
@testset "SD-08: the masked values hold from t0 and right after an input write" begin
    # base: `s[:c, 1]` all 0.0 at t0 under `masked(kq == 0, 1.0)`, and the first substep's flux
    # read that 0.0, so the neighbour of the masked site stayed 0.0 after step 1; an input
    # write kept the old values until the next step
    K = ones(Int32, 4, 4); K[1, 1] = 0
    sys = ssys([D(ce) ~ Δ(ce)], [c(0, x, y) ~ 0.0, ce ~ masked(qe == 0, 1.0)], [ce, qe], Num[])
    p = sown(sys; inputs = [qe => K])
    alg = ExplicitEuler(; dt = 0.001, substeps = 1)
    s = solve(p, alg; saveat = 0.001)
    @test s[:c, 1][1, 1] == 1.0 && count(==(1.0), s[:c, 1]) == 1
    @test s[:c, 2][2, 1] > 0.01 && s[:c, 2][2, 1] == s[:c, 2][1, 2]   # substep 1 saw the 1.0
    integ = init(p, alg)
    @test integ[ce][1, 1] == 1.0
    held = SymbolicIndexingInterface.state_values(integ)
    integ[kq] = zeros(Int32, 4, 4)
    @test all(==(1.0), integ[ce])                                     # clamped now, not at the next step
    @test SymbolicIndexingInterface.state_values(integ) === held      # no slot swap (round 1: the zero step swapped)
    # a map program too (round 1: maps were not clamped: m(t0)[3, 3] = 0.0, its neighbours 0.0
    # after step 1, a newly masked site 0.0 after an input write)
    K3 = ones(Int32, 4, 4); K3[3, 3] = 0
    msys = ssys([Shift(t, 1)(me) ~ me + 0.25Δ(me)],
        [mm(0, x, y) ~ 0.0, mm(t, 0, y) ~ mm(t, 1, y), mm(t, x, 0) ~ mm(t, x, 1), me ~ masked(qe == 0, 1.0)],
        [me, qe], Num[]; T = 1.0)
    mp = sown(msys; inputs = [qe => K3])
    ms = solve(mp, ExplicitMap())
    @test ms[:mm, 1][3, 3] == 1.0
    @test ms[:mm, end][2, 3] == ms[:mm, end][4, 3] == ms[:mm, end][3, 2] == 0.25 * 16    # 0.25 Δ of the 1.0 (h = 1/4)
    mi = init(mp, ExplicitMap())
    K4 = copy(K3); K4[1, 1] = 0
    mi[kq] = K4
    @test mi[me][1, 1] == 1.0 && mi[me][3, 3] == 1.0
    # masked conditions discretize (round 0: refused, "need problem = :owned"; F4-01: one problem)
    @test discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64); inputs = [qe => K]) isa SciMLBase.ODEProblem
    # the clamp at a step's start uses the parameters the steps are bound to (round 2: `integ.p`,
    # so a direct `integ.p[1] = v`, which the steps ignore, moved the masked value the fluxes read)
    @parameters mv = 1.0
    sv = ssys([D(ce) ~ Δ(ce)], [c(0, x, y) ~ 0.0, ce ~ masked(qe == 0, mv)], [ce, qe], [mv])
    pv = sown(sv; inputs = [qe => K])
    ia, ib = init(pv, alg), init(pv, alg)
    ib.p[1] = 7.0
    step!(ia); step!(ib)
    @test ib[ce] == ia[ce] && ia[ce][2, 1] > 0
    # control: with no mask the field stays 0.0
    s0 = solve(sown(ssys([D(ce) ~ Δ(ce)], [c(0, x, y) ~ 0.0], [ce], Num[])), alg; saveat = 0.001)
    @test all(==(0.0), s0[:c, 2])
end
end

@testitem "V3: inputs are set, never read as zero" setup = [LP_silent] tags = [:latticepde, :silent] begin
@testset "V3: inputs are set, never read as zero" begin
    n = 4
    half = [i <= 2 for i in 1:n, j in 1:n]
    # a domain mask (base: the field never moved, extrema (0, 0)); `domain` takes the variable
    dsys = ssys([D(ce) ~ 1.0], [c(0, x, y) ~ 0.0], [ce, de], Num[])
    err = emsg(() -> solve(sown(dsys; domain = dm), ExplicitEuler(; dt = 0.1)))
    @test occursin("`dm`", err) && occursin("no value", err)
    s = solve(sown(dsys; domain = dm, inputs = [dm => half]), ExplicitEuler(; dt = 0.1))
    @test s[:c, end] ≈ Float64.(half)
    @test sown(dsys; domain = "dm", inputs = [dm => half]).inputs == sown(dsys; domain = dm, inputs = [dm => half]).inputs
    @test sown(dsys; domain = :dm, inputs = [dm => half]).inputs == sown(dsys; domain = dm, inputs = [dm => half]).inputs  # (round 0: MethodError)
    # a kind mask clamps only the kind-0 sites (base: every site clamped, extrema (1, 1))
    K = Int32[i <= 2 ? 1 : 0 for i in 1:n, j in 1:n]
    msys = ssys([D(ce) ~ 0.0], [c(0, x, y) ~ 0.0, ce ~ masked(qe == 0, 1.0)], [ce, qe], Num[])
    p = sown(msys; inputs = [qe => K])
    s = solve(p, ExplicitEuler(; dt = 0.1))
    @test s[:c, end] == Float64.(K .== 0)
    # … set during a run (the mask follows) and through remake
    integ = init(p, ExplicitEuler(; dt = 0.1))
    step!(integ)
    # round 3: the `.=` message prints the name as written; a list's arrays are read-only too;
    # a fractional value for an integer input is named (round 2: a bare InexactError)
    @test occursin("integ[:kq] = values", emsg(() -> (integ[:kq] .= 1)))
    # a list's arrays are copies too: writing into one changes nothing (round 5: plain arrays,
    # SciML's convention; the `integ[c] = values` route is documented)
    (l = integ[[ce]]; l[1][1, 1] = 5.0)
    @test integ[ce][1, 1] != 5.0
    err = emsg(() -> (integ[kq] = fill(1.5, n, n)))
    @test occursin("`kq` holds integer values", err) && occursin("1.5", err) && !occursin("InexactError", err)
    integ[kq] = zeros(Int32, n, n)
    @test integ[kq] == zeros(Int32, n, n)
    # an in-place broadcast is named, not a silent no-op on a copy (round 0: no effect)
    @test occursin("integ[kq] = values", emsg(() -> (integ[kq] .= 1)))
    @test occursin("would write a copy", emsg(() -> (integ[ce] .= 7.0)))
    # a write into one entry of the copy changes nothing; `integ[c]` is a plain array
    v0 = integ[ce][1, 1]
    integ[ce][1, 1] = 5.0
    @test integ[ce][1, 1] == v0 && integ[ce] isa Matrix{Float64}
    sv = solve!(integ)
    @test all(==(1.0), sv[:c, end])
    @test all(==(1.0), solve(remake(p; inputs = [qe => 0]), ExplicitEuler(; dt = 0.1))[:c, end])
    # a kind-coupled source (base: zero, extrema (0, 0)), owned and ODE
    ssrc = ssys([D(ce) ~ ifelse(qe == 1, 1.0, 0.0)], [c(0, x, y) ~ 0.0], [ce, qe], Num[])
    @test solve(sown(ssrc; inputs = [qe => K]), ExplicitEuler(; dt = 0.1))[:c, end] ≈ Float64.(K)
    o = discretize(ssrc, LatticeDiscretization(Grid((n, n)); T = Float64); inputs = [qe => K])
    @test reshape(SciMLBase.solve(o, Tsit5()).u[end], n, n) ≈ Float64.(K)
    # (F4-01: an unset input is named at the solve, as on the owned path; base: at `discretize`)
    err = emsg(() -> SciMLBase.solve(discretize(ssrc, LatticeDiscretization(Grid((n, n)); T = Float64)), Tsit5()))
    @test occursin("`kq`", err)
    # a declared default needs no value
    s = solve(sown(ssys([D(ce) ~ 1.0], [c(0, x, y) ~ 0.0], [ce, ddv], Num[]); domain = dd), ExplicitEuler(; dt = 0.1))
    @test all(≈(1.0), s[:c, end])
    # wrong names and sizes are named
    @test occursin("not an input", emsg(() -> sown(msys; inputs = [ce => K])))
    @test occursin("the field has 16 (one per site)", emsg(() -> sown(msys; inputs = [qe => zeros(Int32, 3)])))
end
end

@testitem "SD-07: lattice_placement is refused; lattice_level takes a grid (F3-16)" setup = [LP_silent] tags = [:latticepde, :silent] begin
@testset "SD-07: lattice_placement is refused; lattice_level takes a grid (F3-16)" begin
    # base: `lattice_level = 4` ran at full resolution (16 sites on a 4×4 grid). Since F3-16 a
    # level is `Coarse(k)` (coarse.jl); a number is not a grid and is refused, naming `Coarse`
    @variables cl(..) [lattice_level = 4] cp(..) [lattice_placement = :node]
    err = emsg(() -> sown(ssys([D(cp(t, x, y)) ~ -cp(t, x, y)], [cp(0, x, y) ~ 1.0], [cp(t, x, y)], Num[])))
    @test occursin("lattice_placement", err) && occursin("not lower", err)
    err = emsg(() -> sown(ssys([D(cl(t, x, y)) ~ -cl(t, x, y)], [cl(0, x, y) ~ 1.0], [cl(t, x, y)], Num[])))
    @test occursin("`lattice_level = 4`", err) && occursin("`Coarse(4)`", err)
end
end

@testitem "messages: no stale or misleading diagnosis (F1, M items)" setup = [LP_silent] tags = [:latticepde, :silent] begin
@testset "messages: no stale or misleading diagnosis (F1, M items)" begin
    # LP67: no "next commit (C7b)"; F4-01: `problem` is deleted (a keyword it does not take)
    err = emsg(() -> LatticeDiscretization(Grid((4, 4)); problem = :linear))
    @test occursin("takes `methods`, `T`, `backend`, `domain` and `clock`; got `problem`", err) && !occursin("C7b", err)
    # LP45: a system with no time is a steady system (F3-12b); this one (no decay, no fixed
    # value) has no unique steady state, which its solve names (base 6b6bf089: "no time …
    # not supported in this version")
    st = PDESystem([0 ~ Δ(c(x, y))], Equation[], [x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [x, y], [c(x, y)],
        Num[]; name = :st)
    err = emsg(() -> solve(discretize(st, LatticeDiscretization(Grid((4, 4))))))
    @test occursin("has no unique steady state", err) && !occursin("1 spatial variables", err)
    # LP41: a steady equation is solved by `QuasiSteady`, never sent to a "solver group" (F3-12b)
    r = solve(discretize(ssys([0 ~ Δ(ce) - ce], [c(0, x, y) ~ 1.0], [ce], Num[]), LatticeDiscretization(Grid((4, 4)))),
        QuasiSteady(; dt = 0.1))
    @test r.retcode == SciMLBase.ReturnCode.Success
    # LF13: the substep refusal names the term the bound cannot see
    err = emsg(() -> solve(sown(ssys([D(ce) ~ Δ(ce) - ce^3], [c(0, x, y) ~ 0.0], [ce], Num[])), ExplicitEuler(; dt = 0.01)))
    @test occursin("^3", err) && occursin("cannot see", err)
    @test !occursin("`c: ", err) && !occursin("c(t, x, y)", err) && occursin("rate of `c`", err)   # (round 0: `c: -(c(t, x, y)^3)`)
    # an array input asks for each component (round 0: "`vel⋆` is not an input field")
    asys = ssys([D(ce) ~ -Advect(Upwind1())(ve, ce)], [c(0, x, y) ~ 1.0], [ce, ve], Num[])
    err = emsg(() -> sown(asys; inputs = [vel => zeros(4, 4, 2)]))
    @test occursin("give each component", err) && occursin("vel[1]", err) && !occursin("⋆", err)
    # LF48: algebraic fields that define each other are named, not "buffers = 2" alone
    err = emsg(() -> sown(ssys([D(ce) ~ Ke, Ke ~ Le + ce, Lc(t, x, y) ~ Ke], [c(0, x, y) ~ 0.0], [ce, Ke, Le], Num[])))
    @test occursin("define each other", err) && occursin("K", err) && occursin("Lc", err)
end
end

@testitem "SX-21: the other parts of a PDESystem are used or refused" setup = [LP_silent] tags = [:latticepde, :silent] begin
@testset "SX-21: the other parts of a PDESystem are used or refused" begin
    @parameters kv
    eqs, d = [D(ce) ~ -kv * ce], sdom()
    # `initial_conditions` give parameter values (base, measured: p = [NaN], c(1) = NaN)
    s1 = PDESystem(eqs, [c(0, x, y) ~ 1.0], d, [t, x, y], [ce], [kv]; name = :s1, initial_conditions = Dict(kv => 2.0))
    @test solve(sown(s1), ExplicitEuler(; dt = 0.1, substeps = 1))[:c, end][1] ≈ 0.8^10
    # … and field initial values where no `c(0, …)` condition gives one (base: "field `c` has
    # no initial condition"); both given is refused (base: the 0.5 silently ignored, c(0) = 1.0)
    s2 = PDESystem(eqs, Equation[], d, [t, x, y], [ce], [kv]; name = :s2, initial_conditions = Dict(kv => 2.0, ce => 0.5))
    @test solve(sown(s2), ExplicitEuler(; dt = 0.1, substeps = 1))[:c, 1][1] == 0.5
    s3 = PDESystem(eqs, [c(0, x, y) ~ 1.0], d, [t, x, y], [ce], [kv]; name = :s3, initial_conditions = Dict(kv => 2.0, ce => 0.5))
    @test occursin("give one", emsg(() -> sown(s3)))
    # a key that is neither a parameter nor a variable is named (round 0: ignored)
    @parameters zz
    s3b = PDESystem(eqs, [c(0, x, y) ~ 1.0], d, [t, x, y], [ce], [kv]; name = :s3b, initial_conditions = Dict(kv => 2.0, zz => 3.0))
    err = emsg(() -> sown(s3b))
    @test occursin("`zz`", err) && occursin("neither a parameter nor", err)
    # `ps = NullParameters()` (MTKBase's default) is no parameters (base: NullParameterIndexError)
    s4 = PDESystem([D(ce) ~ -ce], [c(0, x, y) ~ 1.0], d, [t, x, y], [ce]; name = :s4)
    @test solve(sown(s4), ExplicitEuler(; dt = 0.1, substeps = 1))[:c, end][1] ≈ 0.9^10
    @test discretize(s4, LatticeDiscretization(Grid((4, 4)); T = Float64)) isa SciMLBase.ODEProblem
    # subsystems and analytic solutions are refused by name (base: silently ignored, the run
    # gave c(1) = 0.9^10 = 0.3487 with either)
    sub = PDESystem([D(ce) ~ -ce], [c(0, x, y) ~ 1.0], d, [t, x, y], [ce]; name = :sub)
    s5 = PDESystem([D(ce) ~ -ce], [c(0, x, y) ~ 1.0], d, [t, x, y], [ce]; name = :s5, systems = [sub])
    @test occursin("subsystems", emsg(() -> sown(s5)))
    err = emsg(() -> sown(PDESystem([D(ce) ~ -ce], [c(0, x, y) ~ 1.0], d, [t, x, y], [ce]; name = :s6,
        analytic = [ce ~ exp(-t)])))
    @test occursin("analytic solutions", err) && occursin("does not use", err)
end
end
