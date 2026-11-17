# F3-13 (F3 design §3.10, FE-11): the interval bound. A coefficient that reads the coordinates or
# a field with declared `bounds = (lo, hi)` is bounded over those intervals by the interval
# evaluator of the implicit operator's bounds (`_interval`), upwind advection adds its CFL part
# `Σ_a 2 max|m v_a| / h_a`, a term that reads an aux field `K ~ rhs` is bounded through its
# definition, and a local term's Jacobian entries `∂f/∂u` are bounded over the intervals they read.
# The explicit count `⌈dt ρ / 1.8⌉` is then at least the spectral radius of the assembled Jacobian
# times dt / 1.8 and at most 1.1 times it; half the count's substeps blow up.
# Base (b41b73c1, ~/lpwork/f3b8-nc-base.log): every case below has no bound (`ρ = NaN`, the
# automatic count refused), so every testset fails or errors.

@testsetup module LP_bounds
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
include("shared/bounds.jl")
include("shared/export_all.jl")
end

@testitem "F3-13: counts against the spectral radius; half the count blows up" setup = [LP_bounds] tags = [:latticepde, :bounds] begin
@testset "F3-13: counts against the spectral radius; half the count blows up" begin
    per = [fc(t, x, 0) ~ fc(t, x, 1), fc(t, 0, y) ~ fc(t, 1, y)]
    cases = [("(1 + x) Δ(c)", D(fce) ~ (1 + x) * Δ(fce), [fc(0, x, y) ~ 0.5], 0.5),
             ("DivKGrad(1 + x, c)", D(fce) ~ DivKGrad(:harmonic)(1 + x, fce), [fc(0, x, y) ~ 0.5], 0.5),
             # c ∈ (0, 1) declared: the coefficient over [0, 1]; the Jacobian at c ≡ 1 is Δ's
             ("DivKGrad(c, c)", D(fce) ~ DivKGrad(:harmonic)(fce, fce), [fc(0, x, y) ~ 1.0], 1.0),
             ("Advect([0.3, 0.0], c)", D(fce) ~ -Advect(Upwind1())([0.3, 0.0], fce), [fc(0, x, y) ~ 0.5; per], 0.5)]
    for (name, eq, bcs, c0) in cases
        sys = fsys([eq], bcs, [fce])
        pr, po = fown(sys), fode(sys)
        u = fill(c0, length(po.u0))
        r = fradius(po, u)
        # a window whose count is about 60 at the radius
        dt = 60 * 1.8 / r
            n = LFP.substeps(pr, ExplicitEuler(), pr.p; dt)
        @test n >= r * dt / 1.8                              # the count is stable
        @test n <= 1.1 * r * dt / 1.8                        # and not over-pessimistic
        # (measured on 32²: (1 + x) Δ 1.070, DivKGrad(1 + x) 1.087, DivKGrad(c, c) 1.002, Advect 1.000)
        # the count's step stays bounded; twice its step (half the count) blows up from a small
        # perturbation of the worst mode's sign pattern
        w = c0 .- 0.01 .* [isodd(i + j) ? 1.0 : 0.0 for i in 1:32, j in 1:32][:]
        name == "Advect([0.3, 0.0], c)" && (w = c0 .+ 0.01 .* [sin(2π * i / 32 * 15) for i in 1:32, j in 1:32][:])
        @test feuler(po, copy(w), dt / n, 4n) <= 2 * maximum(abs, w)
        @test feuler(po, copy(w), 2dt / n, 2n) > 1e3
    end
end
end

@testitem "F3-13: aux fields, switches, declared intervals, site-varying velocities" setup = [LP_bounds] tags = [:latticepde, :bounds] begin
@testset "F3-13: aux fields, switches, declared intervals, site-varying velocities" begin
    s4 = 4 * 2 * 16^2                                         # Σ_a 4/h_a² on 16²
    b(sys) = (p = fown(sys, 16); p.stability(p.p))
    # an aux field through its definition (`K ~ k c`, `D(c) ~ D Δ(c) − K`): the decay `k`
    # (HANDOFF §5, batch 1 r2 record; base: no bound)
    aux = fsys([D(fue) ~ fx_D * Δ(fue) - fKe, fKe ~ fx_k * fue], [fu(0, x, y) ~ 0.5], [fue, fKe])
    @test b(aux) ≈ 0.1 * s4 + 2.0
    pa = fown(aux, 16)
        @test LFP.substeps(pa, ExplicitEuler(), pa.p; dt = 0.1) == ceil(Int, 0.1 * (0.1 * s4 + 2.0) / 1.8)
    # … and a write of `k` recounts through it
        @test LFP.substeps(remake(pa; p = [fx_k => 20.0]), ExplicitEuler(); dt = 0.1) == ceil(Int, 0.1 * (0.1 * s4 + 20.0) / 1.8)
    # an aux field that reads another field: a cross term of the row (`K ~ k o`, `D(u) ~ −K`)
    xaux = fsys([D(fue) ~ fx_D * Δ(fue) - fKe - fue, D(foe) ~ fx_D * Δ(foe) - foe, fKe ~ 0.5 * foe],
        [fu(0, x, y) ~ 0.5, fo(0, x, y) ~ 0.5], [fue, foe, fKe])
    @test b(xaux) ≈ 0.1 * s4 + 1.5
    # a switch `a max(c − c_T, 0)`: its Jacobian entry is `a` or 0 (no interval needed)
    @test b(fsys([D(fue) ~ fx_D * Δ(fue) - fx_a * max(fue - 0.3, 0)], [fu(0, x, y) ~ 0.5], [fue])) ≈ 0.1 * s4 + 3.0
    # a nonlinear local term over the declared interval: `∂(a c (1 − c))/∂c = a (1 − 2c)` over c ∈ [0, 1]
    @test b(fsys([D(fce) ~ fx_D * Δ(fce) + fx_a * fce * (1 - fce)], [fc(0, x, y) ~ 0.5], [fce])) ≈ 0.1 * s4 + 3.0
    # … with no declared interval, no bound (the term stays one the bound cannot see)
    nb = fsys([D(fue) ~ fx_D * Δ(fue) + fx_a * fue * (1 - fue)], [fu(0, x, y) ~ 0.5], [fue])
    @test isnan(b(nb))
    @test occursin("cannot see", LFP.unbounded_reason(fown(nb, 16).stability, fown(nb, 16).p))
    # a site-varying velocity (batch 3 review R2): `Σ_a 2 max|v_a| / h_a` over the box (16²:
    # x ∈ [−1/32, 1 + 1/32], a face mean reads a ghost site)
    v = fsys([D(fue) ~ 0.01 * Δ(fue) - Advect(Upwind1())([50 * (1 + x), 0.0], fue)], [fu(0, x, y) ~ 0.5], [fue])
    @test b(v) ≈ 0.01 * s4 + 2 * 50 * (2 + 1 / 32) * 16
    # a velocity that reads another field with a declared interval: its frozen velocity
    @test b(fsys([D(fue) ~ -Advect(Upwind1())([fce, 0.0], fue), D(fce) ~ 0.0 * fce], [fu(0, x, y) ~ 0.5, fc(0, x, y) ~ 0.5],
                 [fue, fce])) ≈ 2 * 1.0 * 16
end
end

# Batch 5 review M1: a velocity that reads the advected field (Burgers, `Advect([c, 0], c)`) is
# not bounded by its frozen velocity. The face-mean flux's Jacobian has the central part
# `∂v/∂c · c`, so the rows are not diagonally dominant and no step is certified; the term stays
# unseen, as in the implicit operator. Base 97045a1b (~/lpwork/b5r1-nc-m1.log): ρ = 64 (the
# frozen bound 2 max|c|/h), count 18, and that count amplifies (max|1 + hλ| = 1.78 at c ≡ 1).
@testitem "F3-13 M1: Burgers stays unseen; the frozen count amplifies" setup = [LP_bounds] tags = [:latticepde, :bounds] begin
@testset "F3-13 M1: Burgers stays unseen; the frozen count amplifies" begin
    per = [fc(t, x, 0) ~ fc(t, x, 1), fc(t, 0, y) ~ fc(t, 1, y)]
    burg = fsys([D(fce) ~ -Advect(Upwind1())([fce, 0.0], fce)], [fc(0, x, y) ~ 0.5 + 0.4 * sin(2π * x); per], [fce])
    pr, po = fown(burg), fode(burg)
    @test isnan(pr.stability(pr.p))
    @test "fc" in pr.stability.unbounded
    @test occursin("Advect", LFP.unbounded_reason(pr.stability, pr.p))
    # the automatic count is refused in words, with a route (not a silent count)
        @test_throws "Advect" LFP.substeps(pr, ExplicitEuler(), pr.p; dt = 0.5)
    # why: the count the frozen velocity gives (ρ = 2 · 1 · 32 = 64, n = ⌈0.5 · 64 / 1.8⌉ = 18)
    # amplifies at c ≡ 1 (the linearized face-mean scheme needs h ≲ Δx/4 there)
    J = fjac(po, fill(1.0, length(po.u0)))
    h = 0.5 / ceil(Int, 0.5 * 64 / 1.8)
    @test maximum(λ -> abs(1 + h * λ), eigvals(J)) > 1.5
    # with the user's count past that limit (h ≤ Δx/8), amplification ≤ 1 at c ≡ 1 and c ≡ 0.5
    hs = (1 / 32) / 8
    @test maximum(λ -> abs(1 + hs * λ), eigvals(J)) <= 1 + 1e-9
    @test maximum(λ -> abs(1 + hs * λ), eigvals(fjac(po, fill(0.5, length(po.u0))))) <= 1 + 1e-9
    # and the run with that count stays bounded (measured: max 0.902 from 0.9, the face mean's
    # small overshoot; 1.549 at 32 substeps and 1.0001 at 64)
        s = solve(pr, ExplicitEuler(; substeps = 128); dt = 0.5, saveat = 0.5)
    @test SciMLBase.successful_retcode(s.retcode)
    @test 0.1 - 1e-6 <= minimum(minimum, s.u) && maximum(maximum, s.u) <= 0.91
end
end

@testitem "F3-13: refusals and messages in the user's words" setup = [LP_bounds] tags = [:latticepde, :bounds] begin
@testset "F3-13: refusals and messages in the user's words" begin
    emsg(f) = try
        f(); ""
    catch e
        sprint(showerror, e)
    end
    # a diffusion coefficient whose interval holds negative values: no bound (not a refusal: the
    # enclosure does not show a negative value), the reason names it and its interval
    neg = fown(fsys([D(fue) ~ (x - 0.5) * Δ(fue)], [fu(0, x, y) ~ 0.5], [fue]), 16)
    @test isnan(neg.stability(neg.p))
        m = emsg(() -> solve(neg, ExplicitEuler(); dt = 0.001))
    @test occursin("may be negative over `x` ∈ [0.03125, 0.9688]", m) && occursin("needs it ≥ 0", m)
        @test occursin("ExplicitEuler(; substeps = n)", m)         # the route: an explicit count
    # a coefficient negative over its whole interval is negative diffusion: refused at any count
    m = emsg(() -> solve(fown(fsys([D(fue) ~ (x - 2) * Δ(fue)], [fu(0, x, y) ~ 0.5], [fue]), 16),
                ExplicitEuler(; substeps = 4); dt = 0.001
            )
        )
    @test occursin("is negative at these parameters (anti-diffusion", m)
    # an interval that is not finite (`1 / (x − 0.5)` over the box): no bound, named, never refused
    inf = fown(fsys([D(fue) ~ Δ(fue) - fue / (x - 0.5)], [fu(0, x, y) ~ 0.5], [fue]), 8)
    @test occursin("has no finite bound over `x` ∈ [0.0625, 0.9375]", LFP.unbounded_reason(inf.stability, inf.p))
    # a field that starts outside its declared bounds is refused, naming the site
    m = emsg(() -> fown(fsys([D(fce) ~ DivKGrad(:harmonic)(fce, fce)], [fc(0, x, y) ~ 1.5 * x], [fce]), 8))
    @test occursin("field `fc` starts at", m) && occursin("outside its declared bounds (0.0, 1.0)", m)
    # field-dependent diffusion with no declared interval: the term stays one the bound cannot see
    m = emsg(() -> solve(fown(fsys([D(fue) ~ DivKGrad(:harmonic)(fue, fue)], [fu(0, x, y) ~ 0.5], [fue]), 8),
                ExplicitEuler(); dt = 0.001
            )
        )
    @test occursin("DivKGrad", m) && occursin("cannot see", m)
end
end

# A condition's value with a derivative of the coordinates (`Dy(sin(x y))` on an `x` face): the
# derivative is worked out before the face's own coordinate is substituted, which `substitute`
# would not do inside a `Differential` (the steady.jl `_timed` pattern; coordinator ruling
# 2026-10-26). Base f5641ce1 (~/lpwork/f3b8-dprobe-base.log): every case refused, "cannot lower
# `Differential(y, 1)(x*y)`: a raw derivative that is not a flux form".
@testitem "F3-13: a derivative of the coordinates in a condition's value" setup = [LP_bounds] tags = [:latticepde, :bounds] begin
@testset "F3-13: a derivative of the coordinates in a condition's value" begin
    Dx, Dy = Differential(x), Differential(y)
    @variables fk(..) [input = true]
    run(g) = (p = fown(fsys([D(fue) ~ 0.1 * Δ(fue)], [fu(0, x, y) ~ 0.0, fu(t, 1, y) ~ g], [fue]), 8);
            solve(p, ExplicitEuler(); dt = 0.01)[:fu, end]
        )
    # `Dy(x y)` is `x`, which is 1 on the face x = 1: the run equals the plain value, bitwise
    @test run(Dy(x * y)) == run(1.0)
    @test maximum(abs, run(Dy(sin(x * y))) .- run(x * cos(x * y))) < 1e-14
    @test maximum(abs, run(Dx(x^2) / 2)) > 0 && run(Dx(x^2) / 2) == run(x)
    # … and in a Robin face's value and an initial value
    rob(g) = (p = fown(fsys([D(fue) ~ 0.1 * Δ(fue)], [fu(0, x, y) ~ Dy(x * y^2) / 2, fu(t, 1, y) + Dx(fu(t, 1, y)) ~ g], [fue]), 8);
            solve(p, ExplicitEuler(); dt = 0.01)[:fu, end]
        )
    @test rob(Dy(y^2)) == rob(2y)
    # a derivative of a field read stays unevaluated: refused in words
    m = try
        fown(PDESystem([D(fue) ~ 0.1 * Δ(fue)], [fu(0, x, y) ~ 0.0, fu(t, 1, y) ~ Dy(fk(t, x, y))], fdom(), [t, x, y],
            [fue, fk(t, x, y)], Any[]; name = :fb), 8)
        ""
    catch e
        sprint(showerror, e)
    end
    @test occursin("a derivative of a field; a condition's value may differentiate", m)
    # the route by the field read (batch 5 review N5): an input's derivative is an input of its own;
    # the condition's own field takes its flux form (`Dx(c) ~ g`), which then runs
    @test occursin("give the input's derivative as an input field of its own", m)
    m = try
        fown(PDESystem([D(fue) ~ 0.1 * Δ(fue)], [fu(0, x, y) ~ 0.0, fu(t, 1, y) ~ Dy(fu(t, 1, y))], fdom(), [t, x, y],
            [fue], Any[]; name = :fb), 8)
        ""
    catch e
        sprint(showerror, e)
    end
    @test occursin("the field's own normal derivative is its flux form", m) && occursin("`Dx(c) ~ g` (Neumann)", m)
    s = solve(fown(PDESystem([D(fue) ~ 0.1 * Δ(fue)], [fu(0, x, y) ~ 0.0, Dx(fu(t, 1, y)) ~ 1.0], fdom(), [t, x, y],
                    [fue], Any[]; name = :fb
                ), 8
            ), ExplicitEuler(); dt = 0.01
        )
    @test SciMLBase.successful_retcode(s.retcode) && maximum(s[:fu, end]) > 0
    # a face value that reads another field is a face value, not a periodic pair (N5): an input
    # runs; an aux field of the state is refused in words
    pk = fown(PDESystem([D(fue) ~ 0.1 * Δ(fue)], [fu(0, x, y) ~ 0.0, fu(t, 1, y) ~ fk(t, 1, y)], fdom(), [t, x, y],
        [fue, fk(t, x, y)], Any[]; name = :fb), 8)
        s = solve(remake(pk; inputs = [fk => fill(2.0, 8, 8)]), ExplicitEuler(); dt = 0.01)
    @test SciMLBase.successful_retcode(s.retcode) && maximum(s[:fu, end]) > 0
    m = try
        fown(PDESystem([D(fue) ~ 0.1 * Δ(fue), fKe ~ 2 * fue], [fu(0, x, y) ~ 0.0, fu(t, 1, y) ~ fK(t, 1, y)], fdom(),
            [t, x, y], [fue, fKe], Any[]; name = :fb), 8)
        ""
    catch e
        sprint(showerror, e)
    end
    @test occursin("reads a field of the state", m) && !occursin("periodic pair", m)
end
end

# Batch 5 review M2: the declared interval is checked after the build. A constant face value
# outside the bounds is refused at the build; `remake(; u0)`, `reinit!` and state writes take the
# start check; and a field that leaves the interval the bound used ends the run with
# `ReturnCode.Unstable` and one warning (checked at the saves and at the end). Base 97045a1b
# (~/lpwork/b5r1-nc-m2.log): the Dirichlet-3 case returns `Success` with max 3.587 (the
# reference 2.978), the source case `Unstable` with no warning, every write is accepted.
# Batch 5 review r2 S1: for an implicit group the declared interval sets only the solve's counts,
# so a leak warns once (the route `lower = lo` first) and the run goes on; an explicit leak still
# ends `Unstable` (the M2 testset's source drift). The reviewer's case: CrankNicolson and BDF2
# undershoot 0 by about 2% next to a step (6a46731f, ~/lpwork/f3rev11/p2.log: `Unstable` at
# window 2 with "-0.0207…" and "-0.0233…").
@testitem "F3-13 r2 S1: an implicit leak warns and goes on" setup = [LP_bounds] tags = [:latticepde, :bounds] begin
@testset "F3-13 r2 S1: an implicit leak warns and goes on" begin
    RC = SciMLBase.ReturnCode
    us = PDESystem([D(fce) ~ 0.01 * Δ(fce) - 10 * fce + 0.5 * fce * (1 - fce)], [fc(0, x, y) ~ ifelse(x < 0.5, 1.0, 0.0)],
        fdom(4.0), [t, x, y], [fce], Any[]; name = :us)
    pu = fown(us)
        for alg in (CrankNicolson(), BDF2())
            s = @test_logs (:warn, r"field `fc` left its declared bounds \(0\.0, 1\.0\): it holds -0\.02\d* at site .* Give `lower_bound = 0\.0` to the algorithm") solve(
                pu,
                alg; dt = 1.0, saveat = 1.0
            )
        @test s.retcode == RC.Success && s.t[end] == 4.0 && -0.03 < minimum(minimum, s.u) < 0
        @test s.stats.newton_budget == 0
        # following the route: no warning, the values stay ≥ 0
            a2 = alg isa BDF2 ? BDF2(; lower_bound = 0.0) : CrankNicolson(; lower_bound = 0.0)
            s2 = @test_logs solve(pu, a2; dt = 1.0, saveat = 1.0)
        @test s2.retcode == RC.Success && minimum(minimum, s2.u) >= 0
    end
    # Backward Euler keeps the values in (0, 1) here: no warning
        @test (@test_logs solve(pu, BackwardEuler(); dt = 1.0, saveat = 1.0)).retcode == RC.Success
    # a growth past the interval that the count did not see is caught by the solve's own check:
    # a source and `3c²` carry c above 1 (a blow-up), and with one Newton step per substep the
    # shift clamp warns (with `newton > 1` the Newton check counts it)
    gr = fown(PDESystem([D(fce) ~ 0.01 * Δ(fce) + 3 * fce^2 + 0.5], [fc(0, x, y) ~ 0.5], fdom(3.0), [t, x, y], [fce], Any[];
        name = :gr), 16)
    @test_logs (:warn, r"left its declared bounds .* Widen `bounds`") (:warn, r"the implicit shift was clamped") match_mode = :any solve(gr,
            BackwardEuler(); dt = 0.5, saveat = 0.5
        )
end
end

@testitem "F3-13 M2: declared intervals after the build" setup = [LP_bounds] tags = [:latticepde, :bounds] begin
@testset "F3-13 M2: declared intervals after the build" begin
    emsg(f) = try
        f(); ""
    catch e
        sprint(showerror, e)
    end
    RC = SciMLBase.ReturnCode
    # a Dirichlet value 3 outside c ∈ (0, 1): refused at the build, naming the face and the routes
    d3 = fsys([D(fce) ~ DivKGrad(:harmonic)(fce, fce)], [fc(0, x, y) ~ 0.5, fc(t, 1, y) ~ 3.0], [fce])
    m = emsg(() -> fown(d3))
    @test occursin("field `fc`: its condition on the face `x = 1.0` holds 3.0, outside the field's declared bounds (0.0, 1.0)", m)
    @test occursin("widen `bounds`", m) && occursin("or remove them", m)
    @test occursin("outside the field's declared bounds", emsg(() -> fode(d3)))
    # … a parameter face value, at the build and at `remake(; p)`
    @parameters fx_g = 0.5
    dg = fsys([D(fce) ~ DivKGrad(:harmonic)(fce, fce)], [fc(0, x, y) ~ 0.5, fc(t, 1, y) ~ fx_g], [fce], Any[fx_g])
    pg = fown(dg, 16)
    @test occursin("holds 2.0, outside", emsg(() -> remake(pg; p = [fx_g => 2.0])))
    # … a masked value
    dm = fsys([D(fce) ~ 0.1 * Δ(fce)], [fc(0, x, y) ~ 0.5, fc(t, x, y) ~ masked(x < 0.2, 1.5)], [fce])
    @test occursin("its masked condition holds 1.5", emsg(() -> fown(dm, 16)))
    # a value inside is accepted, and the run stays in [0.5, 1]
    s = solve(fown(fsys([D(fce) ~ DivKGrad(:harmonic)(fce, fce)], [fc(0, x, y) ~ 0.5, fc(t, 1, y) ~ 1.0], [fce]), 16),
            ExplicitEuler(); dt = 0.01, saveat = 0.1
        )
    @test s.retcode == RC.Success && 0.5 - 1e-12 <= minimum(minimum, s.u) && maximum(maximum, s.u) <= 1 + 1e-12
    # a source drives c out of (0, 1): `Unstable` with one warning that names the field and routes
    src = fown(fsys([D(fce) ~ DivKGrad(:harmonic)(fce, fce) + 20.0], [fc(0, x, y) ~ 0.5], [fce]), 16)
    s = @test_logs (:warn, r"field `fc` left its declared bounds \(0\.0, 1\.0\): it holds .* by the end of window .*`ReturnCode\.Unstable`, the run stops\. Give more substeps \(`substeps = n`\), or widen `bounds`") solve(src,
            ExplicitEuler(); dt = 0.01, saveat = 0.05
        )
    @test s.retcode == RC.Unstable && s.t[end] < 1.0 && maximum(s.u[end]) > 1
    # a source that keeps it inside runs to the end with no warning
    s = @test_logs solve(fown(fsys([D(fce) ~ DivKGrad(:harmonic)(fce, fce) + 0.2 * (1 - fce)], [fc(0, x, y) ~ 0.5], [fce]), 16),
            ExplicitEuler(); dt = 0.01, saveat = 0.05
        )
    @test s.retcode == RC.Success && s.t[end] == 1.0
    # a field with declared bounds that no coefficient reads is not checked in the run
    nu = fown(fsys([D(fce) ~ 0.1 * Δ(fce) + 20.0], [fc(0, x, y) ~ 0.5], [fce]), 16)
    @test isempty(nu.stability.used)
        @test solve(nu, ExplicitEuler(); dt = 0.01).retcode == RC.Success
    # the writes take the start check (values outside refused, naming the site)
    pr = fown(fsys([D(fce) ~ DivKGrad(:harmonic)(fce, fce)], [fc(0, x, y) ~ 0.5], [fce]), 16)
    @test occursin("field `fc` starts at 2.0 at site (1, 1), outside its declared bounds (0.0, 1.0)",
        emsg(() -> remake(pr; u0 = fill(2.0, 256))))
        ig = init(pr, ExplicitEuler(); dt = 0.01)
    @test occursin("field `fc` is written 2.0 at site (1, 1), outside its declared bounds", emsg(() -> (ig[fce] = fill(2.0, 16, 16))))
    @test occursin("field `fc` starts at 2.0 at site (1, 1)", emsg(() -> SciMLBase.reinit!(ig, fill(2.0, 256))))
    @test maximum(ig[fce]) == 0.5                                    # nothing changed
    ig[fce] = fill(0.75, 16, 16)                                     # a write inside is accepted
    @test maximum(ig[fce]) == 0.75
    # a state that is not finite warns once, naming the field (review N7)
    un = fown(fsys([D(fue) ~ 100 * fue^3], [fu(0, x, y) ~ 0.5], [fue]), 8)
    s = @test_logs (:warn, r"field `fu`: the state is not finite at t = .*`ReturnCode\.Unstable`, the run stops\. Give more substeps") match_mode = :any solve(un,
            ExplicitEuler(; substeps = 1); dt = 0.1, saveat = 0.1
        )
    @test s.retcode == RC.Unstable
end
end

# F3-ghost (user OK 2026-10-26): at a Dirichlet face, a face coefficient that reads the field
# takes the field's ghost value `2g − c`, the value the face rule gives the gradient, not the
# boundary site's value. The porous-medium equation `∂c/∂t = ∇·(c³ ∇c)` from `c = 0` with
# `c = 1` on the face `x = 0`: with the boundary site's value the face coefficient is
# `(0³ + 0³)/2 = 0` and nothing enters (base a40ff91b, ~/lpwork/b5r1-nc-ghost.log: c stays 0);
# with the ghost value the front enters and spreads as a fine 1D reference with the exact face
# value `K(1)` does. The automatic count bounds the coefficient over the ghost values too.
@testitem "F3-ghost: a Dirichlet face coefficient reads the ghost value" setup = [LP_bounds] tags = [:latticepde, :bounds] begin
@testset "F3-ghost: a Dirichlet face coefficient reads the ghost value" begin
    RC = SciMLBase.ReturnCode
    T = 0.05
    pm = PDESystem([D(fce) ~ DivKGrad(:arithmetic)(fce^3, fce)], [fc(0, x, y) ~ 0.0, fc(t, 0, y) ~ 1.0],
        fdom(T), [t, x, y], [fce], Any[]; name = :pm)
    n = 32
    po = fown(pm, n)
    # the count covers the ghost values (c ∈ (0, 1): ghosts 2 − c ∈ (1, 2), K up to 8): from
    # rough data inside the bounds the automatic count's run stays inside them (each explicit
    # update a convex combination; the run's check would end it `Unstable` otherwise). Also
    # `exp(3c)` with `c = 0` on the face (ghost −c ∈ (−1, 0)). Review r2 N3: the frozen-form
    # claim, not the linearized radius, which `K′(c)∇c` terms of rough states exceed (0.80 for
    # exp(3c)). The mutation that keeps the old bound gives 46 substeps where 114 are needed and
    # ends `Unstable` (~/lpwork/b5r1-mut-ghostbound.log).
    rough = vec([isodd(i + j) ? 1.0 : mod(7919i + 104729j, 101) / 100 for i in 1:n, j in 1:n])
    ex = PDESystem([D(fce) ~ DivKGrad(:arithmetic)(exp(3 * fce), fce)], [fc(0, x, y) ~ 0.5, fc(t, 0, y) ~ 0.0],
        fdom(T), [t, x, y], [fce], Any[]; name = :ex)
    for (name, pr) in (("c³, c = 1 on the face", po), ("exp(3c), c = 0 on the face", fown(ex, n)))
            sr = @test_logs solve(remake(pr; u0 = rough), ExplicitEuler(); dt = 0.01, saveat = T)
        @test sr.retcode == RC.Success && sr.t[end] == T
        @test all(u -> -1e-12 <= minimum(u) && maximum(u) <= 1 + 1e-12, sr.u)
    end
    # a coefficient that goes negative at the ghost (`c(1 − c) + 0.01`, ghost 2 − c): no bound,
    # and the reason names the ghost values (review r2 N4), not only c's interval
    neg = PDESystem([D(fce) ~ DivKGrad(:arithmetic)(fce * (1 - fce) + 0.01, fce)], [fc(0, x, y) ~ 0.5, fc(t, 0, y) ~ 1.0],
        fdom(T), [t, x, y], [fce], Any[]; name = :neg)
    mneg = try
            solve(fown(neg, 16), ExplicitEuler(); dt = 0.01); ""
    catch e
        sprint(showerror, e)
    end
    @info "F3-ghost N4" mneg
    @test occursin("may be negative", mneg) && occursin("ghost values of the faces", mneg) && occursin("`fc` → `", mneg)
        s = solve(po, ExplicitEuler(); dt = 0.01, saveat = T)
    @test s.retcode == RC.Success
    prof = vec(sum(reshape(s.u[end], n, n); dims = 2)) ./ n                 # the x profile
    # fine 1D reference: finite volumes, 12 cells per coarse cell, the face value K(1) = 1 at x = 0
    m = 12n
    h = 1 / m
    u = zeros(m)
    dt = 0.2 * h^2
    flux = zeros(m + 1)
    for _ in 1:round(Int, T / dt)
        flux[1] = 2 * (1 - u[1]) / h                              # K(1) (1 − u₁)/(h/2)
        for i in 2:m
            flux[i] = 0.5 * (u[i - 1]^3 + u[i]^3) * (u[i - 1] - u[i]) / h
        end
        @. u += dt / h * (flux[1:m] - flux[2:(m + 1)])
    end
    ref = vec(sum(reshape(u, 12, n); dims = 1)) ./ 12
    err = sum(abs, prof .- ref) / n
    @info "F3-ghost" maximum(prof) err ref[1:6] prof[1:6]
    @test maximum(prof) > 0.3 && err < 0.015                         # (measured 0.0068, max 0.977)
end
end

# F3-25 (review of F3-25/F3-26): a read through a coefficient bounded over a declared interval is
# an edge of the loop graph. `fc` reads `fo` by `5 fo` (no decay: not dominant); `fo` reads `fc`
# only through its face coefficient `DivKGrad(:harmonic)(fc, fo)`, so the two read each other in a
# loop and `fc`'s row is refused. With a coordinate coefficient instead, `fo` does not read `fc`:
# one way, bounded. Base 1ec7b424: the loop was missed (a bound)
@testitem "F3-25: a loop through a coefficient over a declared interval" setup = [LP_bounds] tags = [:latticepde, :bounds] begin
@testset "F3-25: a loop through a coefficient over a declared interval" begin
    ic = [fc(0, x, y) ~ 0.5, fo(0, x, y) ~ 0.0]
    loop = fown(fsys([D(fce) ~ 0.1 * Δ(fce) + 5 * foe, D(foe) ~ DivKGrad(:harmonic)(fce, foe) - foe], ic, [fce, foe]), 8)
    @test isnan(loop.stability(loop.p))
    one = fown(fsys([D(fce) ~ 0.1 * Δ(fce) + 5 * foe, D(foe) ~ DivKGrad(:harmonic)(1 + x, foe) - foe], ic, [fce, foe]), 8)
    @test isfinite(one.stability(one.p))
end
end
