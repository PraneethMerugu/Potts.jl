# F1: no silent wrong results from `discretize` (refusal inventory SD-04 … SD-12, V3, and the
# misleading messages of LatticePDE). Each testset has a negative control: the comment gives
# the wrong value the base f9a77dd3 returned, measured on the PC (probe of 2026-10-18).
using SciMLBase: SciMLBase, remake
using SymbolicIndexingInterface: SymbolicIndexingInterface, getp, setp
using OrdinaryDiffEqTsit5: Tsit5
using Serialization: Serialization

sdom(T = 1.0) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
ssys(eqs, bcs, dvs, ps; T = 1.0) = PDESystem(eqs, bcs, sdom(T), [t, x, y], dvs, ps; name = :s)
sown(sys; n = 4, inputs = (), kw...) =
    discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64, problem = :owned, kw...); inputs)
emsg(f) = try
    f(); ""
catch e
    sprint(showerror, e)
end

@variables mm(..) dm(..)::Bool [input = true] kq(..)::Int32 [input = true] Lc(..)
@variables dd(..)::Bool = true [input = true] kb(..)::Int32 [input = true, bounds = (1, 3)]
me, de, qe, Le, ddv, qb = mm(t, x, y), dm(t, x, y), kq(t, x, y), Lc(t, x, y), dd(t, x, y), kb(t, x, y)

@testset "SD-04: a rate and a map in one system are refused, naming both" begin
    # base: `ExplicitMap` stepped the rate at dt = 1: c(1) = −4.0 where exp(−5) ≈ 0.0067, Success
    sys = ssys([D(ce) ~ -5ce, Shift(t, 1)(me) ~ me + 1], [c(0, x, y) ~ 1.0, mm(0, x, y) ~ 0.0], [ce, me], Num[])
    err = emsg(() -> sown(sys))
    @test occursin("mixes rate equations", err) && occursin("`c`", err) && occursin("`mm`", err)
    # control: the map alone runs
    m = sown(ssys([Shift(t, 1)(me) ~ me + 1], [mm(0, x, y) ~ 0.0], [me], Num[]))
    @test solve(m, ExplicitMap())[:mm][end][1] == 1.0
end

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
    @test s[:c][end][1] ≈ 0.8^10
    err = emsg(() -> discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64)))
    @test occursin("`kz`", err) && occursin("no value", err)
    @test !occursin("remake", err) && occursin("initial_conditions", err)   # no problem exists yet (round 0: "remake")
    # setp to NaN is refused and leaves the integrator unchanged
    integ = init(remake(p; p = [kz => 2.0]), ExplicitEuler(; dt = 0.1))
    @test_throws ArgumentError setp(integ, kz)(integ, NaN)
    @test integ.p == [2.0]
end

@testset "SD-12: a computed default follows its parameters" begin
    # base: "Cannot convert Sym to Float64" from `_default`
    @parameters a0 = 1.0
    @parameters k2 = 2a0
    sys = ssys([D(ce) ~ -k2 * ce], [c(0, x, y) ~ 1.0], [ce], [a0, k2])
    p = sown(sys)
    alg = ExplicitEuler(; dt = 0.01, substeps = 1)
    @test solve(p, alg)[:c][end][1] ≈ (1 - 0.02)^100
    # a remake of a0 moves k2 (= 6), never leaving it stale
    @test solve(remake(p; p = [a0 => 3.0]), alg)[:c][end][1] ≈ (1 - 0.06)^100
    @test occursin("computed", emsg(() -> remake(p; p = [k2 => 5.0])))
    # the ODE path folds it too
    o = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64))
    os = SciMLBase.solve(o, Tsit5(); abstol = 1e-10, reltol = 1e-10)
    @test os.u[end][1] ≈ exp(-2) rtol = 1e-6
    # a field's `initial_conditions` value reads it too (round 0: "`k2` reads k2")
    s7 = PDESystem([D(ce) ~ -a0 * ce], Equation[], sdom(), [t, x, y], [ce], [a0, k2]; name = :s7,
        initial_conditions = Dict(ce => k2))
    @test solve(sown(s7), alg)[:c][1][1] == 2.0
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
    @test solve(pg, alg)[:c][end] == solve(p3, alg)[:c][end]
    @test solve(remake(pg; p = [g1 => 3.0]), alg)[:c][end] == solve(p5, alg)[:c][end]
    # the ODE integrator's `setp` of an input moves k2 at the next step (the right side derives it)
    oi = SciMLBase.init(o, Tsit5(); abstol = 1e-10, reltol = 1e-10)
    setp(oi, a0)(oi, 3.0)
    SciMLBase.step!(oi, 0.5, true)
    @test isapprox(oi.u[1], exp(-3); rtol = 1e-6) && oi.ps[k2] == 6.0
    # the message names the inputs and the route (D-F2-1)
    @test occursin("`k2` is computed from `a0` (`k2 = 2a0`): set `a0`", emsg(() -> remake(p; p = [k2 => 5.0])))
end

@testset "SD-09: negative diffusion is refused, with the route" begin
    # base: Dn = −0.01 ran (1 substep, Success): anti-diffusion over the run
    @parameters Dn = -0.01
    sys = ssys([D(ce) ~ Dn * Δ(ce)], [c(0, x, y) ~ x], [ce], [Dn])
    p = sown(sys)
    for alg in (ExplicitEuler(; dt = 0.1), ExplicitEuler(; dt = 0.1, substeps = 3))
        err = emsg(() -> solve(p, alg))
        @test occursin("negative", err) && occursin("`c`", err) && occursin("≥ 0", err)
    end
    @test occursin("negative", emsg(() -> discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64))))
    # setp into the negative range is refused atomically
    q = remake(p; p = [Dn => 0.01])
    integ = init(q, ExplicitEuler(; dt = 0.1))
    @test_throws ArgumentError setp(integ, Dn)(integ, -1.0)
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

@testset "SD-08: masks are evaluated at every step" begin
    # a time mask switches on (base: c(1) = 0.0, the mask frozen at t0)
    s = solve(sown(ssys([D(ce) ~ 0.0], [c(0, x, y) ~ 0.0, ce ~ masked(t > 0.5, 1.0)], [ce], Num[])),
        ExplicitEuler(; dt = 0.1); saveat = 0.1)
    @test all(==(1.0), s[:c][end])
    @test all(==(0.0), s[:c][2])                                 # t = 0.1: not yet
    # a field mask clamps (base: c(1) = 1.5, the clamp never engaged)
    s = solve(sown(ssys([D(ce) ~ 1.0], [c(0, x, y) ~ 0.5, ce ~ masked(ce > 0.9, 0.0)], [ce], Num[])),
        ExplicitEuler(; dt = 0.1); saveat = 0.1)
    @test maximum(u -> maximum(u), s.u) <= 1.0 + 1e-12
    @test any(u -> u[1] == 0.0, s.u[2:end])                      # the clamp engaged
end

@testset "SD-08: the masked values hold from t0 and right after an input write" begin
    # base: `s[:c][1]` all 0.0 at t0 under `masked(kq == 0, 1.0)`, and the first substep's flux
    # read that 0.0, so the neighbour of the masked site stayed 0.0 after step 1; an input
    # write kept the old values until the next step
    K = ones(Int32, 4, 4); K[1, 1] = 0
    sys = ssys([D(ce) ~ Δ(ce)], [c(0, x, y) ~ 0.0, ce ~ masked(qe == 0, 1.0)], [ce, qe], Num[])
    p = sown(sys; inputs = [qe => K])
    alg = ExplicitEuler(; dt = 0.001, substeps = 1)
    s = solve(p, alg; saveat = 0.001)
    @test s[:c][1][1, 1] == 1.0 && count(==(1.0), s[:c][1]) == 1
    @test s[:c][2][2, 1] > 0.01 && s[:c][2][2, 1] == s[:c][2][1, 2]   # substep 1 saw the 1.0
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
    @test ms[:mm][1][3, 3] == 1.0
    @test ms[:mm][end][2, 3] == ms[:mm][end][4, 3] == ms[:mm][end][3, 2] == 0.25 * 16    # 0.25 Δ of the 1.0 (h = 1/4)
    mi = init(mp, ExplicitMap())
    K4 = copy(K3); K4[1, 1] = 0
    mi[kq] = K4
    @test mi[me][1, 1] == 1.0 && mi[me][3, 3] == 1.0
    # `:auto` picks the owned path for masked conditions (round 0: refused, "need problem = :owned")
    @test discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64); inputs = [qe => K]) isa FieldProblem
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
    @test all(==(0.0), s0[:c][2])
end

@testset "V3: inputs are set, never read as zero" begin
    n = 4
    half = [i <= 2 for i in 1:n, j in 1:n]
    # a domain mask (base: the field never moved, extrema (0, 0)); `domain` takes the variable
    dsys = ssys([D(ce) ~ 1.0], [c(0, x, y) ~ 0.0], [ce, de], Num[])
    err = emsg(() -> solve(sown(dsys; domain = dm), ExplicitEuler(; dt = 0.1)))
    @test occursin("`dm`", err) && occursin("no value", err)
    s = solve(sown(dsys; domain = dm, inputs = [dm => half]), ExplicitEuler(; dt = 0.1))
    @test s[:c][end] ≈ Float64.(half)
    @test sown(dsys; domain = "dm", inputs = [dm => half]).inputs == sown(dsys; domain = dm, inputs = [dm => half]).inputs
    @test sown(dsys; domain = :dm, inputs = [dm => half]).inputs == sown(dsys; domain = dm, inputs = [dm => half]).inputs  # (round 0: MethodError)
    # a kind mask clamps only the kind-0 sites (base: every site clamped, extrema (1, 1))
    K = Int32[i <= 2 ? 1 : 0 for i in 1:n, j in 1:n]
    msys = ssys([D(ce) ~ 0.0], [c(0, x, y) ~ 0.0, ce ~ masked(qe == 0, 1.0)], [ce, qe], Num[])
    p = sown(msys; inputs = [qe => K])
    s = solve(p, ExplicitEuler(; dt = 0.1))
    @test s[:c][end] == Float64.(K .== 0)
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
    @test all(==(1.0), sv[:c][end])
    @test all(==(1.0), solve(remake(p; inputs = [qe => 0]), ExplicitEuler(; dt = 0.1))[:c][end])
    # a kind-coupled source (base: zero, extrema (0, 0)), owned and ODE
    ssrc = ssys([D(ce) ~ ifelse(qe == 1, 1.0, 0.0)], [c(0, x, y) ~ 0.0], [ce, qe], Num[])
    @test solve(sown(ssrc; inputs = [qe => K]), ExplicitEuler(; dt = 0.1))[:c][end] ≈ Float64.(K)
    o = discretize(ssrc, LatticeDiscretization(Grid((n, n)); T = Float64); inputs = [qe => K])
    @test reshape(SciMLBase.solve(o, Tsit5()).u[end], n, n) ≈ Float64.(K)
    err = emsg(() -> discretize(ssrc, LatticeDiscretization(Grid((n, n)); T = Float64)))
    @test occursin("`kq`", err) && !occursin("remake", err)        # an ODE problem's inputs are fixed (round 0: "remake")
    # a declared default needs no value
    s = solve(sown(ssys([D(ce) ~ 1.0], [c(0, x, y) ~ 0.0], [ce, ddv], Num[]); domain = dd), ExplicitEuler(; dt = 0.1))
    @test all(≈(1.0), s[:c][end])
    # wrong names and sizes are named
    @test occursin("not an input", emsg(() -> sown(msys; inputs = [ce => K])))
    @test occursin("the field has 16 (one per site)", emsg(() -> sown(msys; inputs = [qe => zeros(Int32, 3)])))
end

@testset "SD-07: lattice_level and lattice_placement are refused" begin
    # base: `lattice_level = 4` ran at full resolution (16 sites on a 4×4 grid)
    @variables cl(..) [lattice_level = 4] cp(..) [lattice_placement = :node]
    for (v, key) in ((cl, "lattice_level"), (cp, "lattice_placement"))
        err = emsg(() -> sown(ssys([D(v(t, x, y)) ~ -v(t, x, y)], [v(0, x, y) ~ 1.0], [v(t, x, y)], Num[])))
        @test occursin(key, err) && occursin("not lower", err)
    end
end

@testset "messages: no stale or misleading diagnosis (F1, M items)" begin
    # LP67: no "next commit (C7b)"
    err = emsg(() -> discretize(ssys([D(ce) ~ -ce], [c(0, x, y) ~ 1.0], [ce], Num[]),
        LatticeDiscretization(Grid((4, 4)); problem = :linear)))
    @test occursin("is planned (F4)", err) && occursin("solve(prob)", err) && !occursin("C7b", err)
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

@testset "SX-21: the other parts of a PDESystem are used or refused" begin
    @parameters kv
    eqs, d = [D(ce) ~ -kv * ce], sdom()
    # `initial_conditions` give parameter values (base, measured: p = [NaN], c(1) = NaN)
    s1 = PDESystem(eqs, [c(0, x, y) ~ 1.0], d, [t, x, y], [ce], [kv]; name = :s1, initial_conditions = Dict(kv => 2.0))
    @test solve(sown(s1), ExplicitEuler(; dt = 0.1, substeps = 1))[:c][end][1] ≈ 0.8^10
    # … and field initial values where no `c(0, …)` condition gives one (base: "field `c` has
    # no initial condition"); both given is refused (base: the 0.5 silently ignored, c(0) = 1.0)
    s2 = PDESystem(eqs, Equation[], d, [t, x, y], [ce], [kv]; name = :s2, initial_conditions = Dict(kv => 2.0, ce => 0.5))
    @test solve(sown(s2), ExplicitEuler(; dt = 0.1, substeps = 1))[:c][1][1] == 0.5
    s3 = PDESystem(eqs, [c(0, x, y) ~ 1.0], d, [t, x, y], [ce], [kv]; name = :s3, initial_conditions = Dict(kv => 2.0, ce => 0.5))
    @test occursin("give one", emsg(() -> sown(s3)))
    # a key that is neither a parameter nor a variable is named (round 0: ignored)
    @parameters zz
    s3b = PDESystem(eqs, [c(0, x, y) ~ 1.0], d, [t, x, y], [ce], [kv]; name = :s3b, initial_conditions = Dict(kv => 2.0, zz => 3.0))
    err = emsg(() -> sown(s3b))
    @test occursin("`zz`", err) && occursin("neither a parameter nor", err)
    # `ps = NullParameters()` (MTKBase's default) is no parameters (base: NullParameterIndexError)
    s4 = PDESystem([D(ce) ~ -ce], [c(0, x, y) ~ 1.0], d, [t, x, y], [ce]; name = :s4)
    @test solve(sown(s4), ExplicitEuler(; dt = 0.1, substeps = 1))[:c][end][1] ≈ 0.9^10
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

@testset "an input's names never shadow another name (F1 round 3)" begin
    # round 2: silently misrouted (an input named `c` took `ig[:c] = …`, `kp` read the input
    # array, the last of two inputs with one name won)
    @variables ka(..)::Int32 [input = true, lattice_input_name = "c"] kb(..)::Int32 [input = true, lattice_input_name = "kp"]
    @variables kb2(..)::Int32 [input = true, lattice_input_name = "kp"]
    @parameters kp = 1.0
    on(k) = ifelse(k(t, x, y) == 1, 1.0, 0.0)
    err = emsg(() -> sown(ssys([D(ce) ~ on(ka)], [c(0, x, y) ~ 0.0], [ce, ka(t, x, y)], Num[]); inputs = [ka => 0]))
    @test occursin("also a field", err) && occursin("`c`", err)
    err = emsg(() -> sown(ssys([D(ce) ~ -kp * ce + on(kb)], [c(0, x, y) ~ 0.0], [ce, kb(t, x, y)], [kp]); inputs = [kb => 0]))
    @test occursin("also a parameter", err) && occursin("`kp`", err)
    err = emsg(() -> sown(ssys([D(ce) ~ on(kb) + on(kb2)], [c(0, x, y) ~ 0.0], [ce, kb(t, x, y), kb2(t, x, y)], Num[]);
        inputs = [kb => 0, kb2 => 0]))
    @test occursin("two input fields", err) && occursin("kb", err) && occursin("kb2", err)
    # control: a name of its own is taken (`inputs = [:cc => …]`), and both unset are routed
    @variables kd2(..)::Int32 [input = true, lattice_input_name = "cc"]
    sk = ssys([D(ce) ~ on(kd2) + on(kq)], [c(0, x, y) ~ 0.0], [ce, kd2(t, x, y), qe], Num[])
    @test sown(sk; inputs = [:cc => 1, kq => 1]).inputs == sown(sk; inputs = [kd2 => 1, kq => 1]).inputs
    err = emsg(() -> solve(sown(sk), ExplicitEuler(; dt = 0.1)))
    @test occursin(":cc => values", err) && occursin(":kq => values", err)       # (round 2: a route for the first only)
end

@testset "a table on the ODE path is the table (F1 round 3)" begin
    # round 2 (both front ends): the ODE right side bound the table to the state: at u0 it was
    # −1 where −2, and Tsit5 gave c(1) = 0.5000 where exp(−2) = 0.1353
    @parameters Dq[1:2] = [1.0, 2.0]
    sys = ssys([D(ce) ~ -Dq[2] * ce], [c(0, x, y) ~ 1.0], [ce], [Dq])
    o = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64))
    du = similar(o.u0)
    o.f(du, o.u0, o.p, 0.0)
    @test all(≈(-2.0), du)
    @test SciMLBase.solve(o, Tsit5(); abstol = 1e-10, reltol = 1e-10).u[end][1] ≈ exp(-2) rtol = 1e-6
    # the owned path (right before too), and a new table through remake (round 2: "`Dq[1:2]`
    # is not a parameter of the problem")
    p = sown(sys)
    alg = ExplicitEuler(; dt = 0.01, substeps = 1)
    @test solve(p, alg)[:c][end][1] ≈ 0.98^100
    @test solve(remake(p; p = [Dq => [1.0, 5.0]]), alg)[:c][end][1] ≈ 0.95^100
    @test p.tables == ["Dq" => [1.0, 2.0]]                       # the source is unchanged
    @test occursin("has 2 entries", emsg(() -> remake(p; p = [Dq => [1.0]])))
    # where a table cannot change, the refusal names it (round 2: ODE remake a silent no-op;
    # setp "invalid index: nothing")
    @test occursin("is a table", emsg(() -> remake(o; p = [Dq => [1.0, 5.0]])))
    ig = init(p, alg)
    @test occursin("table", emsg(() -> setp(p, Dq)(p, [1.0, 5.0])))
    # an integrator's table is set through `setp` (and `integ.ps`, F2-13)
    setp(ig, Dq)(ig, [1.0, 5.0])
    @test ig.ps[Dq] == [1.0, 5.0]
    # a typo is named on the ODE path too (round 2: ignored)
    err = emsg(() -> remake(o; p = [:typo => 3.0]))
    @test occursin("`typo` is not a parameter", err)
end

@testset "parameter keys, tables and input lists (F1 round 4)" begin
    @parameters Dq[1:2] = [1.0, 2.0] kr = 0.5
    sys = ssys([D(ce) ~ -Dq[2] * ce - kr * ce + ifelse(qe == 1, 1.0, 0.0)], [c(0, x, y) ~ 1.0], [ce, qe], [Dq, kr])
    p = sown(sys; inputs = [qe => 0])
    ix = p.index
    # an integer key is a slot of the parameter vector; an expression is no index (round 3:
    # both threw "is not a parameter of the problem", so `remake(p; p = [1 => …])` failed)
    @test SymbolicIndexingInterface.parameter_index(ix, 1) == 1
    @test occursin("out of range", emsg(() -> SymbolicIndexingInterface.parameter_index(ix, 9)))
    @test SymbolicIndexingInterface.parameter_index(ix, 2ce) === nothing
    @test remake(p; p = [1 => 0.25]).p == [0.25]
    @test occursin("`typo` is not a parameter", emsg(() -> remake(p; p = [:typo => 3.0])))   # names still refused
    # the table refusal names the table and the owned route (round 3: "`Dq[1]` is a table …
    # `remake(prob::FieldProblem; p = [Dq[1] => values])`", a route that fails)
    ig = init(p, ExplicitEuler(; dt = 0.1, substeps = 1))
    err = emsg(() -> setp(p, Dq)(p, [1.0, 5.0]))
    @test occursin("`Dq` is a table", err) && occursin("remake(prob; p = [Dq => values])", err) && !occursin("Dq[1]", err)
    # an entry as a key is refused, not a whole table set from one value (round 3: "the table
    # `Dq[2]` has 2 entries")
    err = emsg(() -> remake(p; p = [Dq[2] => 5.0]))
    @test occursin("entry 2 of the table `Dq`", err) && occursin("Dq => values", err)
    # tables read back (round 3: "`:Dq` names nothing of this problem"; getp "Invalid symbol")
    @test ig.ps[:Dq] == [1.0, 2.0] && ig.ps[Dq] == [1.0, 2.0] && ig.ps[Dq[2]] == 2.0
    @test getp(p, Dq)(p) == [1.0, 2.0] && getp(ig, Dq[1])(ig) == 1.0
    p5 = remake(p; p = [Dq => [1.0, 5.0]])
    @test getp(p5, Dq)(p5) == [1.0, 5.0] && getp(p, Dq)(p5) == [1.0, 5.0]
    @test getp(p, kr)(p) == 0.5                                   # a scalar parameter as before
    # a list with an input reads (round 3: "`kq` names nothing of this problem; its names: …, `kq`")
    l = ig[[ce, qe]]
    @test length(l) == 2 && l[1] == ones(4, 4) && l[2] == zeros(Int32, 4, 4)
    @test occursin("names nothing", emsg(() -> ig[[ce, :typo]]))
    # a Bool input holds 0/1 only (round 3: 2 was taken, read as true)
    dsys = ssys([D(ce) ~ 1.0], [c(0, x, y) ~ 0.0], [ce, de], Num[])
    err = emsg(() -> sown(dsys; domain = dm, inputs = [dm => fill(2, 4, 4)]))
    @test occursin("`dm` holds a Bool mask", err) && occursin("got 2", err)
    @test sown(dsys; domain = dm, inputs = [dm => fill(1, 4, 4)]).inputs == sown(dsys; domain = dm, inputs = [dm => trues(4, 4)]).inputs
    # the collision message names the variable and its name (round 3: "the input field `c` has the name `c`")
    @variables ka4(..)::Int32 [input = true, lattice_input_name = "c"]
    err = emsg(() -> sown(ssys([D(ce) ~ ifelse(ka4(t, x, y) == 1, 1.0, 0.0)], [c(0, x, y) ~ 0.0], [ce, ka4(t, x, y)], Num[]);
        inputs = [ka4 => 0]))
    @test occursin("input field `ka4` has the name `c`", err) && occursin("also a field", err)
end

@testset "parameter keys, table lists and writes, input sites (F1 round 5)" begin
    @parameters Dq[1:2] = [1.0, 2.0] kr = 0.5
    sys = ssys([D(ce) ~ -Dq[2] * ce - kr * ce + ifelse(qe == 1, 1.0, 0.0)], [c(0, x, y) ~ 1.0], [ce, qe], [Dq, kr])
    alg = ExplicitEuler(; dt = 0.1, substeps = 1)
    # the ODE path refuses a key that is no parameter's name (round 4: `remake` skipped it
    # silently, the run kept kr = 0.5; `setp` gave "invalid index: nothing")
    o = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64); inputs = [qe => 0])
    for pm in ([kr + 1 => 1.0], [kr => 0.1, 2kr => 1.0], Dict(2kr => 1.0))
        err = emsg(() -> remake(o; p = pm))
        @test occursin("is not a parameter of the problem", err) && occursin("`kr`", err)
    end
    @test remake(o; p = [kr => 0.1]).p == [0.1]                  # control: a name is taken
    @test remake(o; p = Dict(kr => 0.2)).p == [0.2]
    err = emsg(() -> setp(o, 2kr))
    @test occursin("`2kr` is not a parameter", err) && !occursin("invalid index", err)
    p = sown(sys; inputs = [qe => 0])
    @test occursin("`2kr` is not a parameter", emsg(() -> remake(p; p = [2kr => 1.0])))
    # a Bool is no slot (round 4: `true` was taken as slot 1); one parameter is singular
    @test occursin("not a parameter", emsg(() -> SymbolicIndexingInterface.parameter_index(p.index, true)))
    @test occursin("not a parameter", emsg(() -> remake(p; p = [true => 0.3])))
    @test endswith(emsg(() -> SymbolicIndexingInterface.parameter_index(p.index, 9)), "has 1 parameter")
    # a list mixing tables and scalars reads (round 4: StackOverflowError)
    ig = init(p, alg)
    @test getp(p, [kr, Dq])(p) == [0.5, [1.0, 2.0]]
    @test getp(ig, (kr, Dq[1]))(ig) == (0.5, 1.0)
    @test occursin("`Dq`", emsg(() -> ig[:typo]))                # the names list the tables
    # an input value is named at its site (round 4: "at entry 7")
    K = zeros(4, 4); K[3, 2] = 2.5
    @test occursin("got 2.5 at site (3, 2)", emsg(() -> sown(sys; inputs = [qe => K])))
    # an integrator's table is written (round 4: "`Dq` names nothing of this problem"), and the
    # step reads it: c(0.1) = 1 − 0.1 (Dq[2] + kr)
    ig.ps[Dq[2]] = 4.0
    @test ig.ps[:Dq] == [1.0, 4.0] && p.tables == ["Dq" => [1.0, 2.0]]
    step!(ig)
    @test all(≈(1 - 0.1 * 4.5), ig[ce])
    ig.ps[Dq] = [1.0, 0.0]
    step!(ig)
    @test all(≈((1 - 0.45) * (1 - 0.05)), ig[ce])
    @test occursin("has 2 entries", emsg(() -> (ig.ps[Dq] = [1.0])))
end

@testset "table coefficients in the bound; problems built from ours (F1 round 6)" begin
    # round 5: the bound could not see `Dn[1] * Δ(c)`: Dn[1] = −1 ran (discretize, remake and
    # `ig[Dn] = …`), and `ig[Dn] = [1000, 2]` kept 1 substep (unstable, reported Success)
    @parameters Dn[1:2] = [1.0, 2.0] Dm[1:2] = [-1.0, 2.0]
    sys = ssys([D(ce) ~ Dn[1] * Δ(ce)], [c(0, x, y) ~ 1.0], [ce], [Dn])
    negsys = ssys([D(ce) ~ Dm[1] * Δ(ce)], [c(0, x, y) ~ 1.0], [ce], [Dm])
    alg = ExplicitEuler(; dt = 0.01, substeps = 1)
    neg(err) = occursin("is negative at these parameters", err)
    @test neg(emsg(() -> discretize(negsys, LatticeDiscretization(Grid((4, 4)); T = Float64))))   # ODE: at build
    @test neg(emsg(() -> solve(sown(negsys), alg)))                                            # owned: before a step
    p = sown(sys)
    @test neg(emsg(() -> solve(remake(p; p = [Dn => [-1.0, 2.0]]), alg)))
    ig = init(p, alg)
    @test neg(emsg(() -> (ig.ps[Dn] = [-1.0, 2.0]))) && ig.ps[Dn] == [1.0, 2.0]   # refused, nothing changed
    # the automatic count follows the table: ρ = Dn[1] · 4 Σ_d 1/h² = 128 Dn[1] (h = 1/4)
    n(D) = ceil(Int, 0.01 * 128 * D / 1.8)
    @test init(p, ExplicitEuler(; dt = 0.01)).substeps == n(1.0) == 1
    @test init(remake(p; p = [Dn => [1000.0, 2.0]]), ExplicitEuler(; dt = 0.01)).substeps == n(1000.0) == 712
    @test (ig.ps[Dn] = [1000.0, 2.0]; ig.substeps == 712)               # an explicit 1 is raised
    @test (ig.ps[Dn[1]] = 1.0; ig.substeps == 1)
    @test occursin("finite", emsg(() -> remake(p; p = [Dn => [NaN, 2.0]])))   # (round 5: taken)
    # writes: a Bool is no value, a tuple is a vector, `.=` names the table
    @test occursin("give one number", emsg(() -> (ig.ps[Dn[1]] = true)))
    @test (ig.ps[Dn] = (1.0, 3.0); ig.ps[Dn] == [1.0, 3.0])
    err = emsg(() -> (ig[Dn] .= 2.0))
    @test occursin("integ.ps[Dn] = values", err) && occursin("table", err) && !occursin("field", err)
    @test occursin("integ.ps[Dn] = values", emsg(() -> (ig.ps[Dn] .= 2.0)))
    # problems built from the ODE form refuse a key that names no parameter too (round 5: a
    # SteadyStateProblem and a NonlinearProblem of it kept the old value silently)
    @parameters k6 = 0.5
    o = discretize(ssys([D(ce) ~ -k6 * ce], [c(0, x, y) ~ 1.0], [ce], [k6]), LatticeDiscretization(Grid((4, 4)); T = Float64))
    ss = SciMLBase.SteadyStateProblem(o)
    nl = SciMLBase.NonlinearProblem(ss)
    for q in (ss, nl)
        @test occursin("`2k6` is not a parameter", emsg(() -> remake(q; p = [2k6 => 1.0])))
        @test remake(q; p = [k6 => 0.1]).p == [0.1]                    # control
    end
    # an untyped vector of pairs is a map (round 5: not checked)
    @test occursin("`2k6` is not a parameter", emsg(() -> remake(o; p = Any[k6 => 0.1, 2k6 => 1.0])))
    @test remake(o; p = Any[k6 => 0.1]).p == [0.1]
    # `setp` on an OrdinaryDiffEq integrator names it (round 5: "invalid index: nothing")
    oi = init(o, Tsit5())
    err = emsg(() -> setp(oi, 2k6))
    @test occursin("`2k6` is not a parameter", err) && !occursin("invalid index", err)
    setp(oi, k6)(oi, 0.2)
    @test oi.p == [0.2]
end

@testset "a table coefficient is bounded at every entry (F1 round 7)" begin
    # round 6: each read took only its smallest and largest entry, which under-bounds a
    # coefficient that is not affine in it: each run below was n = 1 and blew up with Success
    # (c(1) = 1.1e7, 1.2e24, 1.1e7); every site is kind 2 (entry 2), dt = 0.025. Index 0
    # reads 0 (round 8): `1 / at(Dv, …)` takes an index declared never 0 (`kb`, bounds (1, 3))
    @parameters Dq[1:3] = [0.0, 10.0, 20.0] Ds[1:3] = [0.0, π / 2, π] Dv[1:3] = [-1.0, 0.01, 1.0]
    K = fill(Int32(2), 4, 4)
    for (rate, tab, k, q) in ((-(at(Dq, qe) * (20 - at(Dq, qe))) * ce, Dq, 100.0, qe),   # values 0, 100, 0
                              (-(200 * sin(at(Ds, qe))) * ce, Ds, 200.0, qe),             # 0, 200, ≈0
                              (-(1 / at(Dv, qb)) * ce, Dv, 100.0, qb))                     # 1, −100, −1
        sys = ssys([D(ce) ~ rate], [c(0, x, y) ~ 1.0], [ce, q], [tab])
        sol = solve(sown(sys; inputs = [q => K]), ExplicitEuler(; dt = 0.025))
        @test sol.substeps == ceil(Int, 0.025 * k / 1.8)
        @test SciMLBase.successful_retcode(sol) && maximum(abs, sol[:c][end]) < 1e-20
    end
    # a zero entry under `1 / at(…)` that the inputs reach (a kind 1 at site (3, 2)) is not
    # finite: refused, naming the entry and saying to fix it (round 7: only "give an explicit
    # count"; F2 record (i): refused with or without a count). The entries the inputs do not
    # reach are not read (F2 record (h)): with kind 2 everywhere it runs
    @parameters Dz[1:3] = [0.0, 0.01, 1.0]
    K1 = copy(K); K1[3, 2] = 1
    sys = ssys([D(ce) ~ -(1 / at(Dz, qb)) * ce], [c(0, x, y) ~ 1.0], [ce, qb], [Dz])
    err = emsg(() -> solve(sown(sys; inputs = [qb => K1]), ExplicitEuler(; dt = 0.025)))
    @test occursin("not finite where the inputs reach", err)
    @test occursin("`Dz[1]`", err) && occursin("make it nonzero", err) && !occursin("index 0", err)
    @test count("make it nonzero", err) == 1                      # (round 8: said twice)
    @test solve(sown(sys; inputs = [qb => K]), ExplicitEuler(; dt = 0.025)).substeps == 2
    # … and with an index that is 0 at a site the message names both, with both routes
    # (49a986f1 named index 0 only and said "make the coefficient finite")
    sys = ssys([D(ce) ~ -(1 / at(Dz, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Dz])
    K10 = copy(K1); K10[1, 1] = 0
    err = emsg(() -> solve(sown(sys; inputs = [qe => K10]), ExplicitEuler(; dt = 0.025)))
    @test occursin("index 0", err) && occursin("`Dz[1]`", err) && occursin("make it nonzero", err) &&
          occursin("bounds = (1, n)", err) && occursin("index 0 reads 0", err)
    # a negative entry under `sqrt`: the route says so (round 8: "finite and nonzero")
    @parameters Dn9[1:3] = [-1.0, 1.0, 1.0]
    sys = ssys([D(ce) ~ -sqrt(at(Dn9, qb)) * ce], [c(0, x, y) ~ 1.0], [ce, qb], [Dn9])
    err = emsg(() -> solve(sown(sys; inputs = [qb => K1]), ExplicitEuler(; dt = 0.025)))
    @test occursin("`Dn9[1]`", err) && occursin("≥ 0", err) && occursin("sqrt", err) && !occursin("nonzero", err)
end

@testset "a table read takes index 0 and clamped indices as the kernel does (F1 round 8)" begin
    K5, K0 = fill(Int32(5), 4, 4), fill(Int32(0), 4, 4)
    # one index, tables of different lengths: the kernel clamps the index into each table's
    # own range, so at k = 5 `Db` reads 100 and `Da` its last entry 0 (round 7: the group took
    # the shortest table's entries: n = 1, Success, max|c(1)| = 1.1e7; f8f98e43: n = 2)
    @parameters Da[1:3] = [0.0, 0.0, 0.0] Db[1:5] = [0.0, 0.0, 0.0, 0.0, 100.0]
    sys = ssys([D(ce) ~ -(at(Db, qe) - at(Da, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Da, Db])
    sol = solve(sown(sys; inputs = [qe => K5]), ExplicitEuler(; dt = 0.025))
    @test sol.substeps == 2 && SciMLBase.successful_retcode(sol) && maximum(abs, sol[:c][end]) < 1e-20
    # index 0 (an input value 0, or a literal 0) reads 0, so `100 − at(T3, k)` is 100 there
    # (round 7 and f8f98e43: index 0 was not evaluated; n = 1, Success, max|c(1)| = 1.1e7 where
    # the exact value is exp(−100) = 3.7e-44)
    @parameters T3[1:3] = [100.0, 100.0, 100.0]
    for (rate, ins) in ((-(100 - at(T3, qe)) * ce, [ce, qe]), (-(100 - at(T3, 0)) * ce, [ce]))
        sys = ssys([D(ce) ~ rate], [c(0, x, y) ~ 1.0], ins, [T3])
        sol = solve(sown(sys; inputs = length(ins) == 2 ? [qe => K0] : ()), ExplicitEuler(; dt = 0.025))
        @test sol.substeps == 2 && SciMLBase.successful_retcode(sol) && maximum(abs, sol[:c][end]) < 1e-20
    end
    # the CPU `at` reads as the kernel does (round 7: `T[Int(k)]`, a BoundsError at 0)
    @test at([1.0, 2.0, 3.0], 0) == 0.0 && at([1.0, 2.0, 3.0], 5) == 3.0 && at([1.0, 2.0, 3.0], -1) == 1.0
    @test at([1.0, 2.0, 3.0], 2) == 2.0                                           # control
    # `1 / at(T, k)` with an index that is 0 at a site is not finite there: refused, saying so,
    # with the route (keep 0 out of the index); a count does not help (F2 record (i): 1fb097f2
    # ran a count). With no 0 in the map it takes an automatic count (F2 record (h))
    @parameters Dv8[1:3] = [-1.0, 0.01, 1.0]
    sys = ssys([D(ce) ~ -(1 / at(Dv8, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Dv8])
    Kz = fill(Int32(2), 4, 4); Kz[3, 2] = 0
    for alg in (ExplicitEuler(; dt = 0.025), ExplicitEuler(; dt = 0.025, substeps = 2))
        err = emsg(() -> solve(sown(sys; inputs = [qe => Kz]), alg))
        @test occursin("index 0", err) && occursin("(3, 2)", err) && occursin("bounds = (1, n)", err)
    end
    sol = solve(sown(sys; inputs = [qe => fill(Int32(2), 4, 4)]), ExplicitEuler(; dt = 0.025))
    @test sol.substeps == 2 && SciMLBase.successful_retcode(sol) && maximum(abs, sol[:c][end]) < 1e-20
    # a declared index range is checked: a 0 in a map declared (1, 3) is refused, naming the site
    sys = ssys([D(ce) ~ -(1 / at(Dv8, qb)) * ce], [c(0, x, y) ~ 1.0], [ce, qb], [Dv8])
    err = emsg(() -> sown(sys; inputs = [qb => Kz]))
    @test occursin("bounds (1, 3)", err) && occursin("(3, 2)", err)
    p8 = sown(sys; inputs = [qb => fill(Int32(2), 4, 4)])                          # control
    i8 = init(p8, ExplicitEuler(; dt = 0.025))
    @test occursin("bounds (1, 3)", emsg(() -> (i8[qb] = Kz)))
    @test (i8[qb] = fill(Int32(3), 4, 4); true)                                     # control
    # many index expressions: the evaluation count is a Float64 product (round 7: an Int
    # product, 16^16 == 0, passed the cap and the bound never finished). The index map holds
    # 0 … 15, so each read takes up to 16 entries
    @parameters T16[1:16] = collect(1.0:16.0)
    rate = -sum(at(T16, qe + i) for i in 1:16) * ce
    sys = ssys([D(ce) ~ rate], [c(0, x, y) ~ 1.0], [ce, qe], [T16]; T = 0.025)
    K015 = reshape(Int32.(0:15), 4, 4)
    err = emsg(() -> solve(sown(sys; inputs = [qe => K015]), ExplicitEuler(; dt = 0.025)))
    @test occursin("4096", err) && occursin("substeps = n", err)
    @test solve(sown(sys; inputs = [qe => K015]), ExplicitEuler(; dt = 0.025, substeps = 2)).substeps == 2
    # the interval of the index is over the current values: with 0 everywhere each read takes
    # one entry, under the cap (F2 record (m))
    @test solve(sown(sys; inputs = [qe => K0]), ExplicitEuler(; dt = 0.025)).substeps == ceil(Int, 0.025 * 136 / 1.8)
end

@testset "an explicit count is raised by every term with a bound (F1 round 9)" begin
    # 1fb097f2: a coefficient with a non-finite value (index 0) or over the cap made the whole
    # bound NaN, and an explicit count stayed as given: each run below ended Success and blew up.
    # Since F2 record (i) a value that is not finite where the inputs reach is refused with or
    # without a count (the new bound-coverage testset); over the cap is the case left
    K = fill(Int32(2), 4, 4)
    K16 = reshape(Int32.(mod.(0:255, 16)), 16, 16)               # index values 0 … 15
    # P1: `1 / at(Dv, k)` at every entry 200 (1fb097f2: n = 2, Success, 1.2e14): raised to 3,
    # with no warning (no 0 in the map: the bound is finite, F2 record (h))
    @parameters Dv9[1:3] = fill(0.005, 3)
    sys = ssys([D(ce) ~ -(1 / at(Dv9, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Dv9])
    sol = @test_logs solve(sown(sys; inputs = [qe => K]), ExplicitEuler(; dt = 0.025, substeps = 2))
    @test sol.substeps == 3 && SciMLBase.successful_retcode(sol) && maximum(abs, sol[:c][end]) < 1e-20
    @test solve(sown(sys; inputs = [qe => K]), ExplicitEuler(; dt = 0.025)).substeps == 3
    # P1x: diffusion of c on 16² needs 4; an unrelated field's term over the cap kept 2
    # (1fb097f2: 5.2e30)
    @parameters Dd9 = 0.125 Tw9[1:16] = zeros(16)
    sys = ssys([D(ce) ~ Dd9 * Δ(ce), D(oe) ~ -sum(at(Tw9, qe + i) for i in 1:4) * oe],
        [c(0, x, y) ~ 1.0 + sin(1000x + 700y), o(0, x, y) ~ 1.0], [ce, oe, qe], [Dd9, Tw9])
    sol = @test_logs (:warn, r"4096") match_mode = :any solve(sown(sys; n = 16, inputs = [qe => K16]),
        ExplicitEuler(; dt = 0.025, substeps = 2))
    @test sol.substeps == 4 && SciMLBase.successful_retcode(sol) && maximum(abs, sol[:c][end]) < 3
    # P2: over the cap, the diffusion still raises the count (1fb097f2: n = 2, 5.2e30)
    @parameters Tz9[1:16] = zeros(16)
    sys = ssys([D(ce) ~ Dd9 * Δ(ce) - sum(at(Tz9, qe + i) for i in 1:4) * ce], [c(0, x, y) ~ 1.0 + sin(1000x + 700y)], [ce, qe], [Dd9, Tz9])
    sol = @test_logs (:warn, r"4096") match_mode = :any solve(sown(sys; n = 16, inputs = [qe => K16]),
        ExplicitEuler(; dt = 0.025, substeps = 2))
    @test sol.substeps == 4 && SciMLBase.successful_retcode(sol) && maximum(abs, sol[:c][end]) < 3
end

@testset "warnings once per term and cause; messages name every cause (F2 records (a), (b), (e))" begin
    # (a) a sweep over the value of an entry the bound does not cover warned once per value
    # (bda31989: three here, and the set grew with every value). Since F2 record (i) such an
    # entry is refused at each value; a sweep past the cap (the cause left to warn) warns once:
    # the key is the program, the term and the cause, never a value
    K1 = fill(Int32(1), 4, 4)
    @parameters Ds2[1:3] = [-1.0, 1.0, 1.0]
    sys = ssys([D(ce) ~ -sqrt(at(Ds2, qb)) * ce], [c(0, x, y) ~ 1.0], [ce, qb], [Ds2])
    prob = sown(sys; inputs = [qb => K1])
    @test all(v -> occursin("`Ds2[1]` ($v)", emsg(() -> solve(remake(prob; p = [Ds2 => [v, 1.0, 1.0]]),
        ExplicitEuler(; dt = 0.025, substeps = 2)))), (-1.0, -2.0, -3.0))
    @parameters Dd2 = 0.125 Tc2[1:16] = zeros(16)
    sys = ssys([D(ce) ~ Dd2 * Δ(ce) - sum(at(Tc2, qe + i) for i in 1:4) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Dd2, Tc2])
    prob = sown(sys; inputs = [qe => reshape(Int32.(0:15), 4, 4)])
    logs, _ = Test.collect_test_logs() do
        for v in (0.125, 0.25, 0.5)
            solve(remake(prob; p = [Dd2 => v]), ExplicitEuler(; dt = 0.025, substeps = 2))
        end
    end
    @test count(l -> l.level == Base.CoreLogging.Warn && occursin("4096", string(l.message)), logs) == 1
    # (b) an unseen term and a coefficient with no finite bound in one rate: both are named
    # (bda31989: only the unseen term `-(c^3)`). A coefficient not finite where the inputs
    # reach is refused before (F2 record (i)); past the cap is the cause left here
    @parameters Tz2[1:16] = zeros(16)
    sys = ssys([D(ce) ~ -ce^3 - sum(at(Tz2, qe + i) for i in 1:4) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Tz2])
    err = emsg(() -> solve(sown(sys; inputs = [qe => reshape(Int32.(0:15), 4, 4)]), ExplicitEuler(; dt = 0.025)))
    @test occursin("c^3", err) && occursin("4096", err) && occursin("Tz2", err)
    # (e) index 0 is an input value 0, not a "kind map" value (a LatticePDE input is any map)
    @parameters Dz3[1:3] = [1.0, 1.0, 1.0]
    sys = ssys([D(ce) ~ -(1 / at(Dz3, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Dz3])
    Ke0 = fill(Int32(2), 4, 4); Ke0[2, 2] = 0
    err = emsg(() -> solve(sown(sys; inputs = [qe => Ke0]), ExplicitEuler(; dt = 0.025)))
    @test occursin("index 0 reads 0 (an input value 0", err) && !occursin("kind map", err)
end

# the spectral radius of a linear rate's Jacobian, by power iteration on the assembled
# operator (the ODE form's right side, column by column)
function sradius(sys, n, inputs; iters = 4000)
    o = discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64); inputs)
    N = length(o.u0)
    J = zeros(N, N)
    e, du = zero(o.u0), similar(o.u0)
    for j in 1:N
        fill!(e, 0); e[j] = 1
        o.f(du, e, o.p, 0.0)
        J[:, j] .= vec(du)
    end
    v = [1.0 + 0.1 * sin(3.7j) for j in 1:N]
    λ = 0.0
    for _ in 1:iters
        w = J * v
        λ = sqrt(sum(abs2, w)) / sqrt(sum(abs2, v))
        v = w ./ sqrt(sum(abs2, w))
    end
    return λ
end
checker(n, a, b) = [Int32(isodd(i + j) ? a : b) for i in 1:n, j in 1:n]

sok(sol) = SciMLBase.successful_retcode(sol) && all(isfinite, sol[:c][end])
# a run that grew without bound: not finite, or a million times its start (the owned path's
# `Unstable` fires on Inf/NaN only: a run at dt ρ / n = 2.1 reaches 2e130 and reports Success)
sgrew(sol) = (u = sol[:c][end]; !all(isfinite, u) || maximum(abs, u) > 1e6 * maximum(abs, sol[:c][1]))

@testset "F2 (g): a table-read diffusion multiplier takes an automatic count" begin
    # (g) a multiplier read from tables is site diffusion with a bound (bda31989: refused, "no
    # automatic substeps"); the count is within 10 % of the true one (8², every site kind 2)
    @parameters Da[1:2] = [1.0, 3.0] Db[1:2] = [0.5, 0.0]
    sys = ssys([D(ce) ~ (at(Da, qe) - at(Db, qe) + 2) * Δ(ce)], [c(0, x, y) ~ 1.0 + sin(1000x + 700y)], [ce, qe], [Da, Db];
        T = 0.02)
    K2 = fill(Int32(2), 8, 8)
    ρt = sradius(sys, 8, [qe => K2])
    sol = solve(sown(sys; n = 8, inputs = [qe => K2]), ExplicitEuler(; dt = 0.01))
    @test ceil(Int, 0.01 * ρt / 1.8) <= sol.substeps <= ceil(Int, 1.1 * 0.01 * ρt / 1.8) && sok(sol)
end

@testset "F2 (g): the anti-correlated multiplier and face coefficient are bounded independently" begin
    Dxs, Dys = Differential(x), Differential(y)
    # the anti-correlated case: m = 1/Dw at the site, K = the face mean of Dw over two sites; a
    # checkerboard puts m = 100 next to K ≈ 0.5 (row factor ≈ 50). One index for m and K would
    # give max_k Dw[k]/Dw[k] = 1, a count of 3 here; the bound takes max|m| · max K = 100
    @parameters Dw[1:2] = [0.01, 1.0]
    Kc = checker(8, 1, 2)
    grouped = ceil(Int, 0.01 * 1.0 * 4 * 2 * 64 / 1.8)
    for (name, rate) in (("DivKGrad", (1 / at(Dw, qe)) * DivKGrad(:arithmetic)(at(Dw, qe), ce)),
                         ("raw flux", (1 / at(Dw, qe)) * Dxs(at(Dw, qe) * Dxs(ce)) + (1 / at(Dw, qe)) * Dys(at(Dw, qe) * Dys(ce))))
        sys = ssys([D(ce) ~ rate], [c(0, x, y) ~ 1.0 + sin(1000x + 700y)], [ce, qe], [Dw]; T = 0.02)
        ρt = sradius(sys, 8, [qe => Kc])
        p = sown(sys; n = 8, inputs = [qe => Kc])
        sol = solve(p, ExplicitEuler(; dt = 0.01))
        @test grouped == 3 && sol.substeps >= ceil(Int, 0.01 * ρt / 1.8) && sol.substeps > grouped && sok(sol)
        # negative control: a count under the true limit (dt ρ / n = 3 > 2) grows without bound,
        # where the bound's count stays within the start's range. (Half the bound's count is
        # stable here: on these checkerboards the Gershgorin bound is about twice the true
        # radius.)
        nb = floor(Int, 0.01 * ρt / 3)
        pl = remake(p; tspan = (0.0, 0.01 * cld(2000, nb)))                                     # 2000 substeps
        ig = init(pl, ExplicitEuler(; dt = 0.01))
        ig.substeps = nb
        @test sgrew(solve!(ig)) && !sgrew(solve(pl, ExplicitEuler(; dt = 0.01)))
    end
end

@testset "F2 (g): an explicit count under a site-diffusion bound is raised" begin
    # an explicit count under the bound is raised (bda31989: n = 2 kept, 1.7e75, Success), and
    # the solution stays within its initial range
    @parameters Dw3[1:3] = [0.01, 1.0, 1.0]
    sys = ssys([D(ce) ~ (1 / at(Dw3, qb)) * Δ(ce)], [c(0, x, y) ~ 1.0 + sin(1000x + 700y)], [ce, qb], [Dw3])
    Kb = checker(4, 1, 2)
    p = sown(sys; inputs = [qb => Kb])
    sol = solve(p, ExplicitEuler(; dt = 0.025, substeps = 2))
    m0 = maximum(abs, sol[:c][1])
    @test sol.substeps == ceil(Int, 0.025 * 100 * 128 / 1.8) && sok(sol) && maximum(abs, sol[:c][end]) <= m0
    ρt = sradius(sys, 4, [qb => Kb])
    @test sol.substeps >= ceil(Int, 0.025 * ρt / 1.8)
    ig = init(p, ExplicitEuler(; dt = 0.025))
    ig.substeps = floor(Int, 0.025 * ρt / 3)                 # negative control: under the limit
    @test sgrew(solve!(ig)) && !sgrew(sol)
    # a negative entry is negative diffusion, refused
    @parameters Dwn[1:2] = [-0.01, 1.0]
    sys = ssys([D(ce) ~ (1 / at(Dwn, qe)) * Δ(ce)], [c(0, x, y) ~ 1.0], [ce, qe], [Dwn])
    @test occursin("is negative at these parameters", emsg(() -> solve(sown(sys; inputs = [qe => checker(4, 1, 2)]),
        ExplicitEuler(; dt = 0.025))))
    # a row of `M A` is balanced, so site diffusion with a cross term is checked by the rest of
    # its row (305be9ad: the diagonal took min m · min K against max m · max K, refused as
    # coupled whenever m varies); a constant multiplier is the control
    @parameters Dk2[1:2] = [0.01, 1.0]
    for m in (at(Dk2, qe), 1.0)
        sys = ssys([D(ce) ~ m * Δ(ce) - 0.2ce - 0.1oe, D(oe) ~ -oe], [c(0, x, y) ~ 1.0, o(0, x, y) ~ 1.0], [ce, oe, qe], [Dk2])
        @test sok(solve(sown(sys; inputs = [qe => checker(4, 1, 2)]), ExplicitEuler(; dt = 0.025)))
    end
    # … and a row that is not dominant (the cross term outweighs the reaction) is still refused
    sys = ssys([D(ce) ~ at(Dk2, qe) * Δ(ce) - 0.05ce - 0.1oe, D(oe) ~ -oe], [c(0, x, y) ~ 1.0, o(0, x, y) ~ 1.0], [ce, oe, qe], [Dk2])
    @test occursin("coupled", emsg(() -> solve(sown(sys; inputs = [qe => checker(4, 1, 2)]), ExplicitEuler(; dt = 0.025))))
end

@testset "F2 (j): an `ifelse` on an indicator takes its arm" begin
    # (j) an `ifelse` on an indicator takes its arm (bda31989: "Condition of `ifelse` must be a
    # `Bool`")
    @parameters kf = 100.0
    sys = ssys([D(ce) ~ -ifelse(qe == 2, kf, 0) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [kf])
    sol = solve(sown(sys; inputs = [qe => checker(4, 1, 2)]), ExplicitEuler(; dt = 0.025))
    @test sol.substeps >= ceil(Int, 0.025 * 100 / 1.8) && sok(sol)
    @test sradius(sys, 4, [qe => checker(4, 1, 2)]) ≈ 100                      # (the true radius)
end

@testset "F2 (m): index forms take intervals" begin
    # (m) index forms: `2kb` and `max(k, 1)` never read index 0 or entry 1 here (bda31989:
    # refused at index 0); a wrong interval would read the zero entry `Dz4[1]`
    @parameters Dz4[1:3] = [0.0, 1.0, 2.0] Dy4[1:2] = [1.0, 2.0]
    for (rate, q, K, tab) in ((-(1 / at(Dz4, 2qb)) * ce, qb, checker(4, 1, 2), Dz4),
                              (-(1 / at(Dy4, max(qe, 1))) * ce, qe, checker(4, 0, 2), Dy4))
        sys = ssys([D(ce) ~ rate], [c(0, x, y) ~ 1.0], [ce, q], [tab])
        sol = solve(sown(sys; inputs = [q => K]), ExplicitEuler(; dt = 0.025))
        @test sol.substeps == 1 && sok(sol)
    end
end

@testset "F2 (h): index intervals over the current input values; writes are rechecked" begin
    # (h) the interval of an index is over the current input values: an undeclared index map
    # with no 0 takes an automatic count (bda31989: refused at index 0) …
    @parameters Tq[1:2] = [0.01, 1.0]
    sys = ssys([D(ce) ~ -(1 / at(Tq, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Tq])
    p = sown(sys; inputs = [qe => checker(4, 1, 2)])
    sol = solve(p, ExplicitEuler(; dt = 0.025))
    @test sol.substeps == ceil(Int, 0.025 * 100 / 1.8) && sok(sol)
    # … and a write that brings index 0 is refused, naming the site; the run is unchanged
    ig, ref = init(p, ExplicitEuler(; dt = 0.025)), init(p, ExplicitEuler(; dt = 0.025))
    step!(ig); step!(ref)
    K0 = checker(4, 1, 2); K0[3, 2] = 0
    err = emsg(() -> (ig[qe] = K0))
    @test occursin("index 0", err) && occursin("(3, 2)", err) && ig[qe] == checker(4, 1, 2)
    step!(ig); step!(ref)
    @test ig.substeps == ref.substeps && ig[ce] == ref[ce]
end

@testset "F2 (h): `kb - 1` reaches index 0 where `kb` holds a 1" begin
    # `kb − 1` reaches index 0 where `kb` holds a 1, though `kb` never holds 0
    @parameters Tb[1:3] = [1.0, 1.0, 1.0]
    sys = ssys([D(ce) ~ -(1 / at(Tb, qb - 1)) * ce], [c(0, x, y) ~ 1.0], [ce, qb], [Tb])
    err = emsg(() -> solve(sown(sys; inputs = [qb => checker(4, 1, 2)]), ExplicitEuler(; dt = 0.025)))
    @test occursin("index 0", err) && occursin("at site", err)
    p = sown(sys; inputs = [qb => checker(4, 2, 3)])                              # control: kb ≥ 2
    @test sok(solve(p, ExplicitEuler(; dt = 0.025)))
    ig = init(p, ExplicitEuler(; dt = 0.025))
    err = emsg(() -> (ig[qb] = checker(4, 1, 2)))
    @test occursin("index 0", err) && occursin("(2, 1)", err) && ig[qb] == checker(4, 2, 3)
    # an `ifelse` index is decided at the sites where the host values give it: with no kind 1,
    # `ifelse(k == 1, 0, k)` never reads index 0 (305be9ad: refused, no site named, by the hull)
    @parameters Tz[1:2] = [1.0, 1.0]
    sys = ssys([D(ce) ~ -(1 / at(Tz, ifelse(qe == 1, 0, qe))) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Tz])
    @test sok(solve(sown(sys; inputs = [qe => fill(Int32(2), 4, 4)]), ExplicitEuler(; dt = 0.025)))
    K1 = fill(Int32(2), 4, 4); K1[3, 2] = 1
    err = emsg(() -> solve(sown(sys; inputs = [qe => K1]), ExplicitEuler(; dt = 0.025)))
    @test occursin("index 0", err) && occursin("(at site (3, 2))", err)
end

@testset "F2 (i): a coefficient not finite where the inputs reach is refused on every path" begin
    # (i) a coefficient that is not finite where the inputs reach is refused on every path:
    # the ODE form at discretize (bda31989: accepted, a rate of Inf) …
    @parameters Dz5[1:2] = [0.0, 1.0]
    sys = ssys([D(ce) ~ -(1 / at(Dz5, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Dz5])
    err = emsg(() -> discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64); inputs = [qe => checker(4, 1, 2)]))
    @test occursin("not finite", err) && occursin("`Dz5[1]`", err)
    @test discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64);              # control: no kind 1
        inputs = [qe => fill(Int32(2), 4, 4)]) isa SciMLBase.ODEProblem
    # … and the owned form with an explicit count (bda31989: warned and ran, probe P10)
    err = emsg(() -> solve(sown(sys; inputs = [qe => checker(4, 1, 2)]), ExplicitEuler(; dt = 0.025, substeps = 2)))
    @test occursin("not finite", err) && occursin("whatever the substep count", err)
end

@testset "F2 (l): the CPU `at2` reads as `at` does" begin
    # (l) the CPU `at2` reads as `at` does: index 0 reads 0, each index clamps into its axis
    # (bda31989: BoundsError)
    J3 = reshape(collect(1.0:9.0), 3, 3)
    @test at2(J3, 0, 1) == 0.0 && at2(J3, 1, 0) == 0.0 && at2(J3, 9, 1) == J3[end, 1] && at2(J3, -1, 9) == J3[1, end]
    @test at2(J3, 2, 3) == J3[2, 3]                                                  # control
end

@testset "F2-04: one ExplicitEuler; a FieldProblem needs its dt" begin
    @test ExplicitEuler === LatticePDE.Problems.ExplicitEuler
    @parameters kd = 0.5
    p = sown(ssys([D(ce) ~ -kd * ce], [c(0, x, y) ~ 1.0], [ce], [kd]))
    err = emsg(() -> solve(p, ExplicitEuler()))
    @test occursin("needs `dt`", err)
    # (F2-07: `lower` clips in B too; the clip's tests are in groups.jl)
    @test all(≈(0.95^10), solve(p, ExplicitEuler(; dt = 0.1, substeps = 1, lower = 0.0))[:c][end])
    @test occursin("`substeps = 0` is not a count", emsg(() -> ExplicitEuler(; dt = 0.1, substeps = 0)))
    @test all(≈(0.95^10), solve(p, ExplicitEuler(; dt = 0.1, substeps = 1))[:c][end])           # control
end

@testset "SX-37: trajectories on other tasks never share a right side's store" begin
    @parameters kx = 0.05
    sys = ssys([D(ce) ~ DivKGrad(:arithmetic)(Ke, ce) - ce, Ke ~ kx * (1 + ce^2)], [c(0, x, y) ~ 1.0 + x], [ce, Ke], [kx];
        T = 0.01)
    o = discretize(sys, LatticeDiscretization(Grid((16, 16)); T = Float64))
    f = o.f.f
    du, u = similar(o.u0), copy(o.u0)
    f(du, u, o.p, 0.0)                                            # the calling task owns the build
    @test (@allocated f(du, u, o.p, 0.0)) == 0                   # … and its calls stay allocation-free
    pk = [0.1]
    warm(fn, dd, uu, pp) = (fn(dd, uu, pp, 0.0); @allocated fn(dd, uu, pp, 0.0))   # (a function barrier)
    other(fn, uu, pp) = (dd = similar(uu); bytes = warm(fn, dd, uu, pp); (dd, task_local_storage(fn.owner).value, bytes))
    task = Threads.@spawn other(f, u, pk)                          # builds the task's copy, then a warm call
    d2, g, b = fetch(task)
    @test g isa typeof(f) && g.store !== f.store && g.owner[1] === task
    @test b == 0                                                   # (round 0: 16 B per call, a lock)
    @test d2 ≈ (h = similar(du); f(h, u, pk, 0.0); h)
    @test only(values(f.copies)) === g                             # the build holds the copy
    # a dropped build frees its copies while the other task lives on (round 1: the task's
    # local storage held them: 20 builds ≈ 11 MiB kept while the Task was reachable)
    function dropped(f, u, pk)
        r = Ref{Any}(deepcopy(f))
        r[](similar(u), u, pk, 0.0)                               # owned by this task
        t3 = Threads.@spawn (h3 = r[]; h3(similar(u), u, pk, 0.0); WeakRef(task_local_storage(h3.owner).value))
        w3 = fetch(t3)
        r[] = nothing
        return t3, w3
    end
    t3, w3 = dropped(f, u, pk)
    GC.gc(); GC.gc()
    @test istaskdone(t3) && w3.value === nothing
    # a deep copy (SciML's safetycopy) is a build of its own, with no owner; so is a serialized
    # one (round 0: "cannot serialize a running Task" once a task owned the build)
    @test deepcopy(f).owner[1] === nothing
    io = IOBuffer()
    Serialization.serialize(io, f)
    f2 = Serialization.deserialize(seekstart(io))
    @test f2.owner[1] === nothing && f.owner[1] === current_task()
    # with threads: a shared function (safetycopy = false) gives the serial results (base,
    # 4 threads, 48², 16 trajectories: max |threads − serial| = 0.053, or NaN)
    if Threads.nthreads() > 1
        ks = collect(range(0.01, 0.2; length = 8))
        pf(prob, a, rest...) = remake(prob; p = [ks[a isa Integer ? a : a.sim_id]])
        ep = SciMLBase.EnsembleProblem(o; prob_func = pf, safetycopy = false)
        kw = (; trajectories = 8, abstol = 1e-8, reltol = 1e-8, save_everystep = false)
        a = SciMLBase.solve(ep, Tsit5(), SciMLBase.EnsembleSerial(); kw...)
        b = SciMLBase.solve(ep, Tsit5(), SciMLBase.EnsembleThreads(); kw...)
        @test all(i -> a.u[i].u[end] == b.u[i].u[end], 1:8)
    end
end

# F3-05 (F3 design §3.2): the solvers' inner algorithms reach B by name, the same objects as
# A's (test/fields.jl): `DevicePCG`, `Multigrid` exported, `LatticePDE.V` public.
# Base (1079c4ff): `UndefVarError: DevicePCG`.
@testset "F3-05: the inner solvers in B" begin
    @test parentmodule(DevicePCG) === LatticePDE.Problems.Solvers && Multigrid === LatticePDE.Problems.Solvers.Multigrid
    @test DevicePCG(; precond = Multigrid(; cycle = LatticePDE.V(3, 3))).precond.cycle == LatticePDE.V(3, 3)
    @test Base.ispublic(LatticePDE, :V) && !Base.isexported(LatticePDE, :V)
end

# F3-05 review r1 M1: a linear solver given where a field algorithm goes is refused in B's
# words, naming it a linear solver (the `inner` of an implicit field solver), and the route
# works when followed. Base (9db10886, ~/lpwork/f3b2r1-nc-b.log, 6 of 8 fail;
# the 2 that pass are the followed routes): `solve(p, DevicePCG())`
# is "MethodError: no method matching init(::FieldProblem…, ::DevicePCG)", `FieldGroups` says
# "`c(t, x, y) => DevicePCG(Multigrid(LatticeFields.Solvers.V(2, 2), …` is not a field
# algorithm", and `ExplicitEuler(; dt, inner)` is a MethodError.
@testset "F3-05: a linear solver where B takes a field algorithm" begin
    @parameters Dm1 = 0.1
    p = discretize(psys([D(ce) ~ Dm1 * Δ(ce)], [c(0, x, y) ~ x], [Dm1]),
        LatticeDiscretization(Grid((8, 8)); T = Float32, problem = :owned))
    e(f) = try
        f(); ""
    catch err
        err isa ArgumentError ? err.msg : sprint(showerror, err)
    end
    lin = "is a linear solver: it is the `inner` of an implicit field solver, not a field solver"
    m = e(() -> solve(p, DevicePCG()))
    @test startswith(m, "`solve`/`init`: `DevicePCG()` " * lin) && occursin("give `solve(prob, ExplicitEuler(; dt))`", m)
    @test startswith(e(() -> init(p, Multigrid(; cycles = 3))), "`solve`/`init`: `Multigrid(; cycles = 3)` " * lin)
    @test solve(p, ExplicitEuler(; dt = 0.01)).retcode == SciMLBase.ReturnCode.Success           # the route
    m = e(() -> FieldGroups(ce => DevicePCG(; budget = 12)))
    @test startswith(m, "FieldGroups: the field `c(t, x, y)`: `DevicePCG(; budget = 12)` " * lin) &&
          occursin("give `c(t, x, y) => ExplicitEuler(…)`", m)
    @test startswith(e(() -> FieldGroups(; default = Multigrid())), "FieldGroups: `default`: `Multigrid()` " * lin)
    @test solve(p, FieldGroups(ce => ExplicitEuler(; dt = 0.01))).retcode == SciMLBase.ReturnCode.Success
    m = e(() -> ExplicitEuler(; dt = 0.01, inner = DevicePCG()))
    @test startswith(m, "ExplicitEuler: `inner = DevicePCG()`: `inner` is a keyword of the implicit field solvers") &&
          occursin("leave `inner` out", m)
    @test e(() -> ExplicitEuler(; dt = 0.01, step = 2)) ==
          "ExplicitEuler: no keyword `step`; its keywords are `dt`, `substeps` and `lower`"
end
