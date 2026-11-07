# Problems from `discretize` (C7a): the owned FieldProblem (ExplicitEuler, ExplicitMap) and
# the SciML ODEProblem, solved through `solve`; analytic oracles (Fourier decay, steady
# profiles, conservation), symbolic indexing of solutions and integrators, the stability
# bound, the parameter checks of `remake`/`setp`, and negative controls for each claim.
using OrdinaryDiffEqTsit5: Tsit5
using ForwardDiff: ForwardDiff
using SymbolicIndexingInterface: getp, setp, getsym
using SciMLBase: SciMLBase, ODEProblem, remake

@parameters kr = 0.0 Dr = 1.0 gr = 0.0 βr = -0.5
pdom(T = 1.0) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
psys(eqs, bcs, ps; T = 1.0, dvs = [ce]) = PDESystem(eqs, bcs, pdom(T), [t, x, y], dvs, ps; name = :p)
# (F4-01: the owned problem field algorithms step, `LFP.field_problem` of the problem `discretize` returns)
owned(sys, n, m = n; T = Float64, inputs = (), kw...) =
    LFP.field_problem(discretize(sys, LatticeDiscretization(Grid((n, m)); T, kw...); inputs))
fgrid(v, n, m) = reshape(v, n, m)

@testset "Fourier mode decay through solve (owned and ODE)" begin
    n, m, kx, ky = 16, 8, 1, 2
    per = [c(t, x, 0) ~ c(t, x, 1), c(t, 0, y) ~ c(t, 1, y)]
    sys = psys([D(ce) ~ Dr * Δ(ce) - kr * ce], [c(0, x, y) ~ cos(2π * kx * x) * cos(2π * ky * y); per], [Dr, kr])
    prob = owned(sys, n, m)
    @test prob isa LFP.FieldProblem && prob.stability(prob.p) ≈ 4 * (n^2 + m^2)            # D Σ 4/h² + |k|
    xc, yc = ((1:n) .- 0.5) ./ n, ((1:m) .- 0.5) ./ m
    mode = [cos(2π * kx * a) * cos(2π * ky * b) for a in xc, b in yc]
    λ = 4n^2 * sin(π * kx / n)^2 + 4m^2 * sin(π * ky / m)^2                     # discrete eigenvalue
    dt = 0.25 / (n^2 + m^2) / 2
    sol = solve(prob, ExplicitEuler(; dt); saveat = 10dt)
    @test sol.substeps == 1                                       # dt is inside the bound
    for (i, ti) in enumerate(sol.t)
        k = round(Int, ti / dt)
        @test maximum(abs, sol[c(t, x, y), i] .- (1 - dt * λ)^k .* mode) < 1e-12
    end
    # negative control: the continuous rate misses the discrete oracle
    @test maximum(abs, sol[c(t, x, y), 2] .- exp(-4π^2 * (kx^2 + ky^2) * sol.t[2]) .* mode) > 1e-2
    # the ODE path: Tsit5 at tight tolerance follows the semi-discrete exp(−λ t)
    ode = discretize(sys, LatticeDiscretization(Grid((n, m)); T = Float64))
    @test ode isa ODEProblem
    os = SciMLBase.solve(ode, Tsit5(); abstol = 1e-12, reltol = 1e-12, saveat = 0.25)
    @test all(i -> maximum(abs, os[c(t, x, y)][i] .- exp(-λ * os.t[i]) .* mode) < 1e-9, eachindex(os.t))
    @test size(os[:c][end]) == (n, m)
    # the right side allocates nothing warm
    du, u = similar(ode.u0), copy(ode.u0)
    ode.f(du, u, ode.p, 0.0)
    @test (@allocated ode.f(du, u, ode.p, 0.0)) == 0
    @test maximum(abs, fgrid(du, n, m) .+ λ .* mode) < 1e-9          # f(mode) = −λ mode
end

@testset "steady profiles and conservation through solve" begin
    n = 8
    # linear steady profile between two Dirichlet faces (y periodic): cell-centered FV is exact
    lin = psys([D(ce) ~ Δ(ce)], [c(0, x, y) ~ 0.0, c(t, 0, y) ~ 1.0, c(t, 1, y) ~ gr, c(t, x, 0) ~ c(t, x, 1)], [gr]; T = 4.0)
    sol = solve(owned(lin, n, 2), ExplicitEuler(; dt = 1 / 4n^2 / 2))
    xc = ((1:n) .- 0.5) ./ n
    @test maximum(abs, sol[c(t, x, y)][end][:, 1] .- (1 .- xc)) < 1e-9
    # the reaction-diffusion steady state D c″ = k c with c(0) = 1, c′(1) = 0 (discrete oracle)
    rd = psys([D(ce) ~ Dr * Δ(ce) - kr * ce],
        [c(0, x, y) ~ 0.0, c(t, 0, y) ~ 1.0, Differential(x)(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)], [Dr, kr]; T = 6.0)
    pr = remake(owned(rd, n, 2); p = [kr => 4.0])
    sr = solve(pr, ExplicitEuler(; dt = 1e-3))
    A = zeros(n, n)                                               # −D Δ_h + k, ghost rows
    for i in 1:n
        A[i, i] = 2n^2 + 4.0
        i > 1 && (A[i, i - 1] = -n^2)
        i < n && (A[i, i + 1] = -n^2)
    end
    A[1, 1] += n^2                                                # Dirichlet ghost −c + 2
    A[n, n] -= n^2                                                # no-flux ghost c
    b = zeros(n); b[1] = 2n^2
    @test maximum(abs, sr[:c][end][:, 1] .- A \ b) < 1e-9
    @test maximum(abs, sr[:c][end][:, 1] .- (cosh.(2 .* (1 .- xc)) ./ cosh(2))) > 1e-4   # (negative control: continuous)
    # conservation: periodic and no-flux faces keep Σ c to roundoff; a Dirichlet face does not
    cons(bcs) = (s = solve(owned(psys([D(ce) ~ Δ(ce)], [c(0, x, y) ~ x + y^2; bcs], Num[]; T = 0.05), 8, 6),
                     ExplicitEuler(; dt = 1e-3)); (sum(s[:c][1]), sum(s[:c][end])))
    m0, m1 = cons([c(t, x, 0) ~ c(t, x, 1), Differential(x)(c(t, 0, y)) ~ 0.0, Differential(x)(c(t, 1, y)) ~ 0.0])
    @test abs(m1 - m0) < 1e-12 * abs(m0)
    m0, m1 = cons([c(t, x, 0) ~ c(t, x, 1), c(t, 0, y) ~ 0.0])
    @test abs(m1 - m0) > 1e-3 * abs(m0)
end

@testset "stability bound and substeps (§6.2)" begin
    n = 32
    S = LatticePDE.Problems.substeps
    sys = psys([D(ce) ~ Dr * Δ(ce) - kr * ce], [c(0, x, y) ~ 1.0; c(t, 0, y) ~ 0.0; c(t, 1, y) ~ 0.0;
                                                 c(t, x, 0) ~ c(t, x, 1)], [Dr, kr]; T = 0.1)
    base = owned(sys, n)
    @test base.stability(base.p) ≈ 8n^2                          # D Σ 4/h² at the defaults
    prob = remake(base, p = [kr => 3.0])
    @test prob.stability(prob.p) ≈ 8n^2 + 3                       # recomputed at the new values
    @test S(prob, ExplicitEuler(; dt = 0.01)) == ceil(Int, 0.01 * (8n^2 + 3) / 1.8)
    @test S(prob, ExplicitEuler(; dt = 0.01, substeps = 100)) == 100   # a user count above the bound is kept
    # a user count is a minimum (ruling Q2, F1): below the bound, the bound's count (on
    # f9a77dd3 the count 1 was used as given)
    @test S(prob, ExplicitEuler(; dt = 0.01, substeps = 1)) == ceil(Int, 0.01 * (8n^2 + 3) / 1.8)
    sol = solve(prob, ExplicitEuler(; dt = 0.01))
    @test SciMLBase.successful_retcode(sol)
    @test all(isfinite, sol[:c][end]) && 0 <= minimum(sol[:c][end]) && maximum(sol[:c][end]) < 1
    # regression (review probe): D 1 → 4 through remake raises the substeps; the run stays finite
    p4 = remake(base, p = [Dr => 4.0])
    s4 = solve(p4, ExplicitEuler(; dt = 0.01))
    @test s4.substeps == ceil(Int, 0.01 * 32n^2 / 1.8) && SciMLBase.successful_retcode(s4) &&
          all(isfinite, s4[:c][end])
    # … and through setp on an integrator
    integ = init(base, ExplicitEuler(; dt = 0.01))
    m1 = integ.substeps
    setp(integ, Dr)(integ, 4.0)
    @test integ.substeps == s4.substeps > m1
    si = solve!(integ)
    @test SciMLBase.successful_retcode(si) && all(isfinite, si[:c][end])
    # negative control: one substep per dt (the bound ignored, forced on the integrator) blows
    # up, and the retcode says so
    integ = init(remake(prob; tspan = (0.0, 4.0)), ExplicitEuler(; dt = 0.01); saveat = 0.1)
    integ.substeps = 1
    bad = solve!(integ)
    @test bad.retcode == SciMLBase.ReturnCode.Unstable && !all(isfinite, bad.u[end])
    @test bad.t[end] < 4.0                                        # the solve stopped there
    # a parameter without a value: no bound, so automatic substeps are refused until it has one
    @parameters Dn
    nd = owned(psys([D(ce) ~ Dn * Δ(ce)], [c(0, x, y) ~ 1.0; c(t, 0, y) ~ 0.0; c(t, x, 0) ~ c(t, x, 1)], [Dn]; T = 0.1), 16)
    @test isnan(nd.stability(nd.p))
    @test_throws ArgumentError solve(nd, ExplicitEuler(; dt = 0.01))
    snd = solve(remake(nd; p = [Dn => 1.0]), ExplicitEuler(; dt = 0.01))
    @test snd.substeps == ceil(Int, 0.01 * 8 * 16^2 / 1.8) && all(isfinite, snd[:c][end])
    # rate terms the bound cannot see (nonlinear, advection) need a user count
    nl = owned(psys([D(ce) ~ Δ(ce) - ce^3], [c(0, x, y) ~ 0.0], Num[]), 8)
    @test isnan(nl.stability(nl.p))
    @test_throws ArgumentError solve(nl, ExplicitEuler(; dt = 0.01))
    @test SciMLBase.successful_retcode(solve(nl, ExplicitEuler(; dt = 0.01, substeps = 4)))
    adv = discretize(psys([D(ce) ~ -Advect(Upwind1())(ve, ce)], [c(0, x, y) ~ x; c(t, x, 0) ~ c(t, x, 1)], Num[];
                          dvs = [ce, ve]), LatticeDiscretization(Grid((8, 4)); T = Float64);
                     inputs = ["vel[1]" => 1.0, "vel[2]" => 0.0])
    @test_throws ArgumentError solve(adv, ExplicitEuler(; dt = 0.01))
    @test SciMLBase.successful_retcode(solve(adv, ExplicitEuler(; dt = 0.01, substeps = 2)))
end

@testset "bound: kind-gated terms, cross coupling, array coefficients (review round 2)" begin
    n = 16
    S = LatticePDE.Problems.substeps
    @parameters ε = 0.5 α = 1.0 D2 = 1.0 kc = 0.0 a = 100.0 Dk[1:3] = [1.0, 2.0, 3.0]
    per = [c(t, x, 0) ~ c(t, x, 1), c(t, 0, y) ~ c(t, 1, y)]
    per2 = [per; o(t, x, 0) ~ o(t, x, 1); o(t, 0, y) ~ o(t, 1, y)]
    s4 = 4 * 2n^2                                                 # Σ_d 4/h_d²
    # kind-gated decay (the CPM coupling): the input `kind` is not a second field, and the
    # indicator is bounded by 1
    for gate in (ismember(ke, (1,)), ke == 1)
        g = owned(psys([D(ce) ~ Dr * Δ(ce) + α * ismember(ke, (2,)) - ε * ce * gate], [c(0, x, y) ~ 1.0; per],
                       [Dr, ε, α]; T = 0.1, dvs = [ce, ke]), n; inputs = [ke => 0])
        @test g.stability(g.p) ≈ s4 + 0.5
        @test S(g, ExplicitEuler(; dt = 0.01)) == ceil(Int, 0.01 * (s4 + 0.5) / 1.8)
    end
    # negative control: a decay rate that reads a second state field is nonlinear, so refused
    nl = owned(psys([D(ce) ~ Dr * Δ(ce) - ε * ce * oe, D(oe) ~ Δ(oe)], [c(0, x, y) ~ 1.0; o(0, x, y) ~ 1.0; per2],
                    [Dr, ε]; T = 0.1, dvs = [ce, oe]), n)
    @test isnan(nl.stability(nl.p))
    @test_throws ArgumentError S(nl, ExplicitEuler(; dt = 0.01))
    # cross-diffusion one way (`o` does not read `c`): the Jacobian is block triangular, its
    # eigenvalues those of each row's own block, so the bound is the Gershgorin row sum with no
    # dominance test (F3-22 review r1, D-C7a item 2 amended; base 9afaac05: refused)
    x1 = owned(psys([D(ce) ~ Dr * Δ(ce) + D2 * Δ(oe), D(oe) ~ Δ(oe)], [c(0, x, y) ~ 1.0; o(0, x, y) ~ cos(2π * x); per2],
                    [Dr, D2]; T = 0.1, dvs = [ce, oe]), n)
    @test x1.stability(x1.p) ≈ 2 * s4                             # |Dr| s4 + |D2| s4
    s1 = solve(x1, ExplicitEuler(; dt = 0.01))
    @test SciMLBase.successful_retcode(s1) && s1.substeps == ceil(Int, 0.01 * 2 * s4 / 1.8)
    # a loop of cross-diffusion (`o` reads `c` back): no throw from the bound; the rows are not
    # diagonally dominant, so automatic substeps are refused and a user count runs
    xd = owned(psys([D(ce) ~ Dr * Δ(ce) + D2 * Δ(oe), D(oe) ~ Δ(oe) + 0.1 * Δ(ce)], [c(0, x, y) ~ 1.0; o(0, x, y) ~ cos(2π * x); per2],
                    [Dr, D2]; T = 0.1, dvs = [ce, oe]), n)
    @test isnan(xd.stability(xd.p))
    @test_throws ArgumentError solve(xd, ExplicitEuler(; dt = 0.01))
    px = remake(xd; p = [D2 => 50.0])
    sx = solve(px, ExplicitEuler(; dt = 0.01, substeps = 50))
    # the count is a minimum (Q2): raised to the bound over the terms it sees (Gershgorin row sum)
    @test SciMLBase.successful_retcode(sx) &&
          sx.substeps == max(50, ceil(Int, 0.01 * LatticePDE.bound_parts(px.stability, px.p).ρ / 1.8)) > 50
    # … with a decay strong enough for dominance the bound is the Gershgorin row sum:
    # |Dr| s4 + |k| + |D2| s4 for the c row
    # (a loop: `o` reads `c` back through a small reaction it dominates by its decay)
    xk = owned(psys([D(ce) ~ Dr * Δ(ce) + D2 * Δ(oe) - kc * ce, D(oe) ~ Δ(oe) - kc * oe + 0.5 * ce],
                    [c(0, x, y) ~ 1.0; o(0, x, y) ~ cos(2π * x); per2], [Dr, D2, kc]; T = 0.1, dvs = [ce, oe]), n)
    pk = remake(xk; p = [D2 => 0.5, kc => 3000.0])
    @test pk.stability(pk.p) ≈ s4 + 3000 + 0.5 * s4
    @test SciMLBase.successful_retcode(solve(pk, ExplicitEuler(; dt = 0.01)))
    @test isnan(xk.stability(xk.p))                               # kc = 0: not dominant
    # a rotation c' = a o, o' = −a c (imaginary spectrum): refused under automatic substeps;
    # forced to one substep, Euler grows the norm (the case the refusal guards)
    rot = owned(psys([D(ce) ~ a * oe, D(oe) ~ -a * ce], [c(0, x, y) ~ 1.0, o(0, x, y) ~ 0.0], [a];
                     T = 0.1, dvs = [ce, oe]), 4)
    @test isnan(rot.stability(rot.p))
    err = try solve(rot, ExplicitEuler(; dt = 0.01)); "" catch e; sprint(showerror, e) end
    @test occursin("substeps = n", err) && occursin("diagonally dominant", err)
    @test maximum(abs, solve(rot, ExplicitEuler(; dt = 0.01, substeps = 1)).u[end]) > 10
    # negative control: a decaying, dominant coupling (c' = −a c + o/2) keeps automatic substeps
    dom = owned(psys([D(ce) ~ -a * ce + 0.5 * oe, D(oe) ~ -a * oe], [c(0, x, y) ~ 1.0, o(0, x, y) ~ 1.0], [a];
                     T = 0.1, dvs = [ce, oe]), 4)
    @test dom.stability(dom.p) ≈ 100.5
    # indicators are 0 or 1 per site, and a coefficient need not be largest at 1 (review
    # round 3): kind = 0 everywhere makes `1 − χ` = 1, so the rate is k = 1000 on every site
    @parameters kk = 1000.0 bb = 990.0 ee = 1000.0
    for (rhs, ρ) in ((Dr * Δ(ce) - kk * (1 - ismember(ke, (1,))) * ce, 512 + 1000),
                     (Dr * Δ(ce) - (kk - bb * ismember(ke, (1,))) * ce, 512 + 1000),
                     (Dr * Δ(ce) - (kk - bb * (ke == 1)) * ce, 512 + 1000),
                     (Dr * Δ(ce) - kk * ce, 512 + 1000))                 # control: no indicator
        g = owned(psys([D(ce) ~ rhs], [c(0, x, y) ~ 1.0; per], [Dr, kk, bb]; T = 0.1, dvs = [ce, ke]), 8; inputs = [ke => 0])
        @test g.stability(g.p) ≈ ρ
        sg = solve(g, ExplicitEuler(; dt = 0.01); saveat = 0.05)
        @test SciMLBase.successful_retcode(sg) && maximum(abs, sg.u[end]) <= 1
    end
    # a gated rotation: the cross coefficient e (1 − χ) is e at χ = 0, so the rows are not
    # dominant and automatic substeps are refused
    grot = owned(psys([D(ce) ~ -a * ce + ee * (1 - ismember(ke, (1,))) * oe,
                       D(oe) ~ -a * oe - ee * (1 - ismember(ke, (1,))) * ce],
                      [c(0, x, y) ~ 1.0; o(0, x, y) ~ 0.0; per2], [a, ee]; T = 0.1, dvs = [ce, oe, ke]), 4; inputs = [ke => 0])
    @test isnan(grot.stability(grot.p))
    @test_throws ArgumentError solve(grot, ExplicitEuler(; dt = 0.01))
    # an `ifelse` gate that reads no field is bounded arm by arm (C8 review round 2): the
    # decaying arm never certifies the rotation of the other, never active at the same time
    @parameters t0 = 1000.0 kr = 4.0
    gr = owned(psys([D(ce) ~ ifelse(t >= t0, -10 * ce, -kr * oe), D(oe) ~ ifelse(t >= t0, -10 * oe, kr * ce)],
                    [c(0, x, y) ~ 1.0, o(0, x, y) ~ 0.0], [t0, kr]; T = 0.1, dvs = [ce, oe]), 4)
    @test isnan(gr.stability(gr.p))
    @test_throws ArgumentError solve(gr, ExplicitEuler(; dt = 0.01))
    # control: both arms dominant: accepted, and the bound is the worst arm (10 + 1)
    gd = owned(psys([D(ce) ~ ifelse(t >= t0, -10 * ce - oe, -10 * ce + oe), D(oe) ~ ifelse(t >= t0, -10 * oe, -5 * oe)],
                    [c(0, x, y) ~ 1.0, o(0, x, y) ~ 1.0], [t0]; T = 0.1, dvs = [ce, oe]), 4)
    @test gd.stability(gd.p) ≈ 11
    @test SciMLBase.successful_retcode(solve(gd, ExplicitEuler(; dt = 0.01)))
    # an aux field in an arm (C8 review round 3): `K ~ −1000 c` is an unknown of the states,
    # so the arm's term `K` is not a source (before C8: ρ = Dr·Σ4/h², one substep, silent
    # divergence); F3-13 bounds it through its definition, the arm `−1000 c`: ρ = Dr·Σ4/h² + 1000
    # (base b41b73c1: no bound)
    # (the bound is checked on the symbolic form; the owned problem reads K of another field.
    # Before F3-02 an owned `K ~ −1000 c` read in c's rate was refused as a read cycle)
    sa = psys([D(ce) ~ Dr * Δ(ce) + ifelse(t >= t0, Ke, 0.0), Ke ~ -1000 * ce], [c(0, x, y) ~ 1.0; per], [Dr, t0];
              T = 0.1, dvs = [ce, Ke])
    cfa = symbolic_discretize(sa, LatticeDiscretization(Grid((4, 4)); T = Float64); update = LatticePDE.euler_update)
    @test stability_bound(cfa, sa)([1.0, 0.0]) ≈ 4 * 2 * 16 + 1000
    ga = owned(psys([D(ce) ~ Dr * Δ(ce) + ifelse(t >= t0, Ke, 0.0), D(oe) ~ -oe, Ke ~ -1000 * oe],
                    [c(0, x, y) ~ 1.0; o(0, x, y) ~ 1.0; per2], [Dr, t0]; T = 0.1, dvs = [ce, oe, Ke]), 4)
    ga = remake(ga; p = [t0 => 0.0])
    # (`o` does not read `c` back: one way, so the arm's `−1000` needs no dominance; F3-22 review r1,
    # D-C7a item 2 amended; base 9afaac05: no bound)
    @test ga.stability(ga.p) ≈ 4 * 2 * 16 + 1000
    @test SciMLBase.successful_retcode(solve(ga, ExplicitEuler(; dt = 0.01)))
    # … and a condition reading an aux field is not a gate; F3-13 bounds the switch through K's
    # definition by its Jacobian entries: `∂/∂c` is −1 or 0, and the condition's `o` enters through
    # its arms only (0): ρ = Dr·Σ4/h² + 1 (base b41b73c1: no bound)
    gc = owned(psys([D(ce) ~ Dr * Δ(ce) + ifelse(Ke >= 0, -ce, 0.0), D(oe) ~ -oe, Ke ~ oe - 1],
                    [c(0, x, y) ~ 1.0; o(0, x, y) ~ 1.0; per2], [Dr]; T = 0.1, dvs = [ce, oe, Ke]), 4)
    @test gc.stability(gc.p) ≈ 4 * 2 * 16 + 1
    # an array-element coefficient is bounded at its entry (F1 round 6; it was refused):
    # ρ = Dk[2] · 4 Σ_d 1/h² = 2 · 512 on 8×8 (h = 1/8); with no tables given there is no bound
    ae = owned(psys([D(ce) ~ Dk[2] * Δ(ce)], [c(0, x, y) ~ 1.0; per], [Dk]; T = 0.1), 8)
    @test ae.stability(LatticePDE.Problems.with_tables(ae.p, ae.tables)) ≈ 1024
    @test isnan(ae.stability(ae.p))
    s_ae = solve(ae, ExplicitEuler(; dt = 0.01))                     # the automatic count
    @test SciMLBase.successful_retcode(s_ae) && s_ae.substeps == ceil(Int, 0.01 * 1024 / 1.8)
end

@testset "setp is atomic; init checks the faces (review round 2)" begin
    per = [c(t, x, 0) ~ c(t, x, 1), c(t, 0, y) ~ c(t, 1, y)]
    prob = owned(psys([D(ce) ~ Dr * Δ(ce)], [c(0, x, y) ~ cos(2π * x); per], [Dr]; T = 0.1), 32)
    integ = init(prob, ExplicitEuler(; dt = 0.01))
    m = integ.substeps
    @test_throws ArgumentError setp(integ, Dr)(integ, NaN)        # no bound at NaN
    @test integ.p == [1.0] && integ.substeps == m                 # unchanged
    s = solve!(integ)
    @test SciMLBase.successful_retcode(s) && all(isfinite, s[:c][end])
    # a direct write to integ.p is not a parameter update (documented): the run is unchanged
    i2 = init(prob, ExplicitEuler(; dt = 0.01))
    i2.p[1] = 4.0
    @test solve!(i2)[:c][end] ≈ s[:c][end]
    # a degenerate face on a problem set through setp: refused at init with the face message
    rsys = psys([D(ce) ~ Δ(ce)], [c(0, x, y) ~ 0.0, c(t, 0, y) + βr * Differential(x)(c(t, 0, y)) ~ 1.0,
                                  c(t, x, 0) ~ c(t, x, 1)], [βr])
    rp = owned(rsys, 4)
    ri = init(rp, ExplicitEuler(; dt = 1e-3))
    @test_throws ArgumentError setp(ri, βr)(ri, 0.125)
    @test ri.p == [-0.5]                                          # restored after the face check
    setp(rp, βr)(rp, 0.125)
    err = try init(rp, ExplicitEuler(; dt = 1e-3, substeps = 4)); "" catch e; sprint(showerror, e) end
    @test occursin("ghost value undefined", err)
end

@testset "symbolic indexing: solutions, integrators, problems" begin
    n, m = 6, 4
    sys = psys([D(ce) ~ Dr * Δ(ce) - kr * ce], [c(0, x, y) ~ x; c(t, x, 0) ~ c(t, x, 1)], [Dr, kr]; T = 0.01)
    prob = owned(sys, n, m)
    sol = solve(prob, ExplicitEuler(; dt = 1e-3); saveat = 5e-3)
    @test sol.t ≈ [0.0, 0.005, 0.01]
    @test sol[c(t, x, y)] == sol[:c] && size(sol[:c, 2]) == (n, m) && sol[:c, 2] == sol[:c][2]
    @test sol[:c][1] ≈ repeat(((1:n) .- 0.5) ./ n, 1, m)        # cell-centered initial value
    @test getp(sol, Dr)(sol) == 1.0 && sol[kr] == 0.0
    @test_throws Exception sol[o(t, x, y)]                       # negative control: not a field
    @test getsym(prob, :c)(prob) == fgrid(prob.u0, n, m)
    integ = init(prob, ExplicitEuler(; dt = 1e-3))
    @test integ[c(t, x, y)] == sol[:c][1]
    integ[c(t, x, y)] = fill(2.0, n, m)                           # setsym writes the current state
    step!(integ)
    @test integ[:c] ≈ fill(2.0, n, m)                             # flat field: no flux, no decay
    setp(integ, kr)(integ, 10.0)                                  # rebinds the launches
    step!(integ)
    @test integ[:c] ≈ fill(2.0 * (1 - 1e-2), n, m)                # c ← c (1 − dt k)
    @test (@allocated step!(integ)) == 0                          # warm step: no allocation
end

@testset "parameter updates re-check degenerate Robin faces" begin
    n = 4                                                         # h = 1/4: β = −h/2 at the low face
    sys = psys([D(ce) ~ Δ(ce)], [c(0, x, y) ~ 0.0, c(t, 0, y) + βr * Differential(x)(c(t, 0, y)) ~ 1.0,
                                 c(t, x, 0) ~ c(t, x, 1)], [βr])
    prob = owned(sys, n)                                          # default −0.5: fine
    @test_throws ArgumentError remake(prob; p = [βr => 0.125])      # α/2 + β/h = 1/2 − 1/2 = 0
    @test remake(prob; p = [βr => 0.25]) isa LFP.FieldProblem
    @test_throws ArgumentError remake(prob; p = [βr => 0.125 * (1 + 1e-9)])   # relative tolerance
    # near-degenerate (review probe βr = 0.1249): the face stiffens the boundary row; the
    # bound sees it, so the run stays finite
    near = remake(prob; p = [βr => 0.1249])
    @test near.stability(near.p) > 100 * prob.stability(prob.p)
    sn = solve(near, ExplicitEuler(; dt = 1e-2))
    @test SciMLBase.successful_retcode(sn) && maximum(abs, sn.u[end]) < 10
    integ = init(prob, ExplicitEuler(; dt = 1e-3))
    @test_throws ArgumentError setp(integ, βr)(integ, 0.125)
    ode = discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64))
    @test_throws ArgumentError ode.f(similar(ode.u0), ode.u0, [0.125], 0.0)
    ode.f(similar(ode.u0), ode.u0, [0.25], 0.0)                   # negative control: fine
    # F2 record (f): a part of a row that is not finite (the degenerate face's excess) never
    # drops the row from the seen bound, which keeps the diffusion Σ 4/h² = 128 (bda31989: the
    # row summed to Inf and counted 0, so an explicit count stayed as given)
    r = LatticePDE.bound_parts(prob.stability, [0.125])
    @test !isfinite(r.ρ) && r.seen >= 128
    @test LatticePDE.bound_parts(prob.stability, [0.25]).seen >= 128          # control: a finite face
end

@testset "discrete maps: ExplicitMap" begin
    @parameters dx [lattice_spacing = 1]
    @variables N(..)
    Ne = N(t, x, y)
    sys = psys([Shift(t, 1)(Ne) ~ (N(t, x + dx, y) + N(t, x - dx, y)) / 2], [N(0, x, y) ~ x], [dx];
        T = 3.0, dvs = [Ne])
    prob = discretize(sys, LatticeDiscretization(Grid((8, 2)); T = Float64))     # a map: a DiscreteProblem (F4-01)
    @test prob isa SciMLBase.DiscreteProblem && LFP.field_problem(prob).kind == :map
    sol = solve(prob, ExplicitMap(); saveat = 1)
    u = sol[Ne][1][:, 1]
    for k in 1:3
        u = [((i < 8 ? u[i + 1] : 0.0) + (i > 1 ? u[i - 1] : 0.0)) / 2 for i in 1:8]   # reads 0 outside
        @test sol[Ne][k + 1][:, 1] ≈ u
    end
    @test_throws ArgumentError solve(prob, ExplicitEuler(; dt = 1.0))   # a map is not a rate
end

@testset "refusals" begin
    sys = psys([D(ce) ~ Δ(ce)], [c(0, x, y) ~ 0.0], Num[])
    @test_throws ArgumentError LatticeDiscretization(Grid((4, 4)); problem = :linear)
    # (F4-03) a span that is not a whole number of windows ends by one shortened window
    s3 = solve(owned(sys, 4), ExplicitEuler(; dt = 0.3))
    @test s3.retcode == SciMLBase.ReturnCode.Success && s3.t[end] ≈ 1.0
    @test_throws ArgumentError solve(owned(sys, 4), ExplicitMap())
    @test_throws ArgumentError owned(psys([D(ce) ~ Δ(ce)], Equation[], Num[]), 4)  # no initial value
    # (F4-01: a masked condition discretizes to the one problem; base, with `problem = :ode`: refused)
    @test discretize(psys([D(ce) ~ Δ(ce)], [c(0, x, y) ~ 0.0, ce ~ masked(ke == 3, 0.0)], Num[];
        dvs = [ce, ke]), LatticeDiscretization(Grid((4, 4)); T = Float64)) isa SciMLBase.ODEProblem
end

# F2-10 (F2 design §2.11): the one operator allowlist (`lowers_call`, which Potts `@equations`
# asks too), and `Advect` with a velocity written as a vector of terms (`[ux, 0.0]`), equal to
# the same velocity given as an array input. Base (c2583722): no `lowers_call`; the vector
# velocity refused ("`Advect` takes the velocity array field").
@testset "F2-10: one allowlist; Advect with a vector velocity" begin
    for f in (+, -, *, /, ^, min, max, abs, sqrt, exp, log, ifelse, ==, !=, <, <=, >, >=, !, &, |,
        sin, cos, tan, tanh, sinh, cosh, cbrt, exp2, log2, log10, expm1, log1p, atan, floor, ceil, round)
        @test LatticePDE.lowers_call(f)
    end
    @test !any(LatticePDE.lowers_call, (Δ, at, ismember, masked, sum, getindex))       # control: terms of their own
    @parameters uxv = 0.3
    vsys = psys([D(ce) ~ -Advect(Upwind1())([uxv, 0.0], ce)], [c(0, x, y) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)], [uxv])
    asys = psys([D(ce) ~ -Advect(Upwind1())(ve, ce)], [c(0, x, y) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)], Num[]; dvs = [ce, ve])
    u0 = vec([sin(π * i / 8) for i in 1:8, j in 1:4])
    alg = ExplicitEuler(; dt = 0.1, substeps = 2)
    sv = solve(remake(owned(vsys, 8, 4); u0), alg)
    sa = solve(remake(owned(asys, 8, 4; inputs = [ve[1] => 0.3, ve[2] => 0.0]); u0), alg)
    @test sv.u[end] == sa.u[end] && sv.u[end] != u0
    # a constant velocity vector (review M2 of F2 batch 4; base: refused, its route `[ux, uy]`)
    csys = psys([D(ce) ~ -Advect(Upwind1())([0.3, 0.0], ce)], [c(0, x, y) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)], Num[])
    @test solve(remake(owned(csys, 8, 4); u0), alg).u[end] == sv.u[end]
    # the velocity's length is checked against the grid's axes
    @test_throws ArgumentError owned(psys([D(ce) ~ -Advect(Upwind1())([uxv], ce)], [c(0, x, y) ~ 0.0], [uxv]), 8, 4)
end

# F2-12 (F2 design §2.8, SX-03): `discretize(…; u0, p, tspan)` on both problem kinds equals the
# `remake` route; any other keyword is an `ArgumentError` naming it. Base (c2583722): the
# keywords were a `MethodError` (`discretize` took `inputs` only).
@testset "F2-12: discretize keywords" begin
    pidx(prob, s) = LatticePDE.Problems.SII.parameter_index(prob, s)
    withp(p, i, v) = (q = collect(promote_type(eltype(p), typeof(v)), p); q[i] = v; q)
    emsg(f) = try
        f(); ""
    catch e
        sprint(showerror, e)
    end
    @parameters kd = 1.0 Dd = 0.1
    @parameters Td[1:2] = [0.5, 1.0]
    sys = psys([D(ce) ~ Dd * Δ(ce) - kd * ce - at(Td, ke) * ce], [c(0, x, y) ~ 1.0], [kd, Dd, Td]; dvs = [ce, ke])
    K = fill(Int32(1), 4, 4)
    # (F4-01: one problem; the field algorithm and an OrdinaryDiffEq solver both step it)
    disc = LatticeDiscretization(Grid((4, 4)); T = Float64)
    base = discretize(sys, disc; inputs = [ke => K])
    i = pidx(base.f.sys, kd)
    a = discretize(sys, disc; inputs = [ke => K], p = [kd => 2], u0 = [ce => 0.5], tspan = (0, 2))
    r = remake(base; p = withp(base.p.values, i, 2.0), u0 = fill(0.5, 16), tspan = (0.0, 2.0))
    @test a.p == r.p && collect(a.u0) == collect(r.u0) && a.tspan == r.tspan == (0.0, 2.0)
    for (sa, sr) in ((solve(a, ExplicitEuler(; dt = 0.1)), solve(r, ExplicitEuler(; dt = 0.1))),
            (solve(a, Tsit5(); abstol = 1e-10, reltol = 1e-10), solve(r, Tsit5(); abstol = 1e-10, reltol = 1e-10)))
        @test sa.u[end] == sr.u[end] && sa.t[end] == 2.0
    end
    # a flat `u0`, a parameter vector and an array `u0` per field
    v = discretize(sys, disc; inputs = [ke => K], p = collect(a.p.values), u0 = fill(0.5, 16), tspan = (0, 2))
    @test v.p == a.p && collect(v.u0) == collect(a.u0)
    @test collect(discretize(sys, disc; inputs = [ke => K], u0 = [ce => fill(0.25, 4, 4)]).u0) == fill(0.25, 16)
    # a table through `p` (the owned problem keeps it; `remake` gives the same)
    disc = LatticeDiscretization(Grid((4, 4)); T = Float64)
    pt = discretize(sys, disc; inputs = [ke => K], p = [Td => [0.25, 1.0]])
    @test getp(pt, Td)(pt) == [0.25, 1.0] && getp(pt, Td)(pt) == getp(remake(discretize(sys, disc; inputs = [ke => K]);
        p = [Td => [0.25, 1.0]]), Td)(pt)
    # … and a `remake` of the problem gives it a new table (F4-00; base: on the ODE path refused,
    # "an ODE problem's tables are fixed")
    o = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64); inputs = [ke => K],
        p = [Td => [0.25, 1.0]])
    @test o.ps[Td] == [0.25, 1.0] && remake(o; p = [Td => [0.5, 1.0]]).ps[Td] == [0.5, 1.0]
    # review S7: a Dual in `u0` promotes the state (base: `MethodError: no method matching
    # Float64(::Dual)`); an input in `u0` says it is an input and prints its name as written
    dU = discretize(sys, disc; inputs = [ke => K], u0 = [ce => ForwardDiff.Dual(0.5, 1.0)])
    @test eltype(dU.u0) <: ForwardDiff.Dual && ForwardDiff.value(dU.u0[1]) == 0.5
    err = emsg(() -> discretize(sys, disc; inputs = [ke => K], u0 = [ke => 1]))
    @test occursin("`kindₛ` is an input", err) && occursin("inputs = [kindₛ => values]", err) && !occursin("⋆", err)
    # any other keyword names itself (base: a `MethodError`)
    err = emsg(() -> discretize(sys, disc; inputs = [ke => K], jac = true))
    @test occursin("`discretize` takes `inputs`, `u0`, `p`, `tspan`; got `jac`", err) && occursin("planned", err)
    @test occursin("got `saveat`", emsg(() -> discretize(sys, disc; inputs = [ke => K], saveat = 0.1)))
    # misshapen values are named
    @test occursin("`u0` has 3 values; the state has 16", emsg(() -> discretize(sys, disc; inputs = [ke => K], u0 = [1.0, 2, 3])))
    @test occursin("`u0`: `nope` is not a field", emsg(() -> discretize(sys, disc; inputs = [ke => K], u0 = [:nope => 1.0])))
    @test occursin("`tspan` is `(t₀, t₁)`", emsg(() -> discretize(sys, disc; inputs = [ke => K], tspan = 3)))
end

# F3-00 (F3 design §3.12, review r1 M1 and R2-M2): a system whose only equations are aux fields
# `K ~ rhs` has one group with no state, evaluated once per window (0 substeps); the aux fields
# of any system are evaluated at each save, before the copy, and at each `integ[K]` read, so a
# saved or read `K` is `rhs` of the state at that time. Base (743ab0a0): `sol[K]` was "Invalid
# symbol K(t, x, y) for `getsym`" and an aux-only solve saved empty states (reviewer probe
# `r1_auxonly_b`); `integ[K]` failed the same way, also for a system with states.
@testset "F3-00: aux fields in B (aux-only systems, sol[K], integ[K])" begin
    emsg(f) = try
        f(); ""
    catch e
        sprint(showerror, e)
    end
    @parameters Kb = 2.0 Da = 0.1 ka = 1.0
    xc = ((1:4) .- 0.5) ./ 4
    # aux only: `:auto` gives the owned problem; `K` at every save (saves every second window)
    sys = psys([Ke ~ Kb + t + x], Equation[], [Kb]; dvs = [Ke])
    p = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64))
    @test p isa SciMLBase.ODEProblem && isempty(p.u0)                    # (F4-01: one problem with no state)
    sol = solve(p, ExplicitEuler(; dt = 0.25); saveat = 0.5)
    @test sol.retcode == SciMLBase.ReturnCode.Success && sol.t == [0.0, 0.5, 1.0]
    @test LatticePDE.Problems.substep_counts(sol) == [0]          # no state: no substep
    @test all(isempty, sol.u)                                        # the aux field is not state
    for (i, ti) in enumerate(sol.t)
        @test sol[Ke][i] ≈ [2.0 + ti + a for a in xc, _ in 1:4] && sol[Ke, i] == sol[Ke][i]
    end
    @test sol[:K] == sol[Ke]                                         # by name too
    ig = init(p, ExplicitEuler(; dt = 0.25))
    step!(ig)
    @test ig[Ke] ≈ [2.25 + a for a in xc, _ in 1:4]                  # read at t = 0.25
    # FieldGroups: `default` sets the window (a pair names no state field: refused naming it)
    @test solve(p, FieldGroups(; default = ExplicitEuler(; dt = 0.25)); saveat = 0.5)[Ke] == sol[Ke]
    @test occursin("FieldGroups: `K", emsg(() -> solve(p, FieldGroups(Ke => ExplicitEuler(; dt = 0.25)))))
    # with states: `K ~ 2c + t` is saved from the saved state at the save time (two substeps per
    # window, so the substep's own aux value, computed from the state before it, would lag)
    sys2 = psys([D(ce) ~ Da * Δ(ce) - ka * ce, Ke ~ 2ce + t], [c(0, x, y) ~ 1.0 + x], [Da, ka]; dvs = [ce, Ke])
    p2 = owned(sys2, 4)
    s2 = solve(p2, ExplicitEuler(; dt = 0.25); saveat = 0.5)
    @test s2.substeps == 2 && s2.t == [0.0, 0.5, 1.0]
    for i in eachindex(s2.t)
        @test s2[Ke][i] ≈ 2 .* s2[ce][i] .+ s2.t[i] rtol = 1e-14
    end
    ig2 = init(p2, ExplicitEuler(; dt = 0.25))
    step!(ig2)
    @test ig2[Ke] ≈ 2 .* ig2[ce] .+ 0.25 rtol = 1e-14
    # an aux field is not written: the error names it (base: "Invalid symbol")
    @test occursin("`K` is an aux field", emsg(() -> (ig2[Ke] = zeros(4, 4))))
    # … and an unknown name lists it among the names
    @test occursin("`K`", emsg(() -> ig2[:nope]))
    # the `:ode` path (review r1 M1): `:auto` gives the ODEProblem for a system with states, and
    # `K` is an observed quantity, `rhs` at the state and time read: `sol[K]` at every save and
    # `integ[K]`, equal to the owned path at t0 (base 8f658abd: "Invalid symbol K(t, x, y)", reviewer
    # probe u2_b)
    po = discretize(sys2, LatticeDiscretization(Grid((4, 4)); T = Float64))
    @test po isa ODEProblem
    so = SciMLBase.solve(po, Tsit5(); abstol = 1e-10, reltol = 1e-10, saveat = 0.5)
    @test so.t == [0.0, 0.5, 1.0]
    for i in eachindex(so.t)
        @test so[Ke][i] ≈ 2 .* so[ce][i] .+ so.t[i] rtol = 1e-14
        @test so[Ke, i] == so[Ke][i] && size(so[:K][i]) == (4, 4)
    end
    @test so[ce][1] == s2[ce][1]
    @test so[Ke][1] ≈ s2[Ke][1] rtol = 1e-14                         # the owned path at t0
    io = init(po, Tsit5(); abstol = 1e-10, reltol = 1e-10)
    # a write of `K` on the ODE path is refused in the user's words (review r2 nit; base
    # e0347d1a: "Invalid symbol K(t, x, y) for `setsym`")
    e = emsg(() -> (io[Ke] = zeros(16)))
    @test occursin("`K` is an aux field (`K ~ rhs`)", e) && occursin("cannot be written", e) && !occursin("Invalid symbol", e)
    @test io[Ke] ≈ 2 .* io[ce] .+ io.t rtol = 1e-14                 # at t0
    step!(io)
    @test io.t > 0
    @test io[Ke] ≈ 2 .* io[ce] .+ io.t rtol = 1e-14
    @test SciMLBase.successful_retcode(SciMLBase.solve!(io))
end
