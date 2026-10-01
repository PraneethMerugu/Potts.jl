# P6.0c (ROADMAP Phase 6, step 0): solver placement, breaking batch part 2 (D-075 Q9 and the
# AUTHORING §6 / D-016 / D-038 amendments; api-synthesis §3.4). Frozen (AUTONOMY §7.3).
#
# Semantics pinned here:
#  1. `field_solver`, `ode_solver` and `solvers` are `PottsProblem` construction keywords.
#     `@sweep` no longer takes `field_solver` or `ode_solver`: building a model that puts one
#     there is an error (any exception, at expansion or at build) whose message names the
#     keyword.
#  2. `field_solver` is required when the model has a field: a bare
#     `PottsProblem(model_with_field, op, tspan)` throws an `ArgumentError` naming
#     `field_solver`. A model without a field needs none, and passing one to it is an
#     `ArgumentError` naming `field_solver` (a solver for a field that does not exist is a
#     mistake, as an operating-point key naming nothing is; it also keeps an unused spec out
#     of the D-016 fingerprint).
#  3. `ode_solver` defaults to `ExplicitEuler()` (D-038 as amended by D-075): no keyword and
#     `ode_solver = ExplicitEuler()` give the same fingerprint and the same trajectory.
#  4. `solvers = [x => solver]` is keyed by the symbolic variable and overrides `ode_solver`
#     for that variable only. A stiff ODE under `Adaptive(Rodas5P())` beside an explicit
#     field and an explicit-Euler ODE in one model: each part conforms to its solver alone
#     (closed-form oracles of the discrete schemes, the analytic solution for Rodas5P). A key
#     that is a parameter, not an integrated variable, is an `ArgumentError`.
#  5. Merks: a bare `PottsProblem(MerksVasculogenesis(…), …)` throws; with
#     `field_solver = ExplicitEuler(substeps = 2, lower = 0.0)` it builds and runs, and in a
#     configuration where they bind (c(0) = −0.05), `lower = 0.0` keeps the field ≥ 0 while
#     `ExplicitEuler()` does not. Bitwise equality with the pre-change (`@sweep`-placed)
#     result is checked by the coordinator at merge, not frozen here (digests would pin
#     floating-point operand order, which shifts with unrelated codegen edits; D-070). The
#     pre-change Merks fingerprint (recorded on 1092ada, Julia 1.12.6) no longer matches
#     (D-075: checkpoints from before the change fail by design).
#  6. D-016: the fingerprint hashes a canonical form of the solver spec. Problems differing
#     only in `field_solver` (substeps, `lower`), `ode_solver` or `solvers` (tolerances) have
#     different fingerprints, and a checkpoint of one fails to load into the other with an
#     `ArgumentError`. Equal specs built from fresh objects (a fresh model, fresh
#     `Adaptive(Rodas5P(); …)`) have equal fingerprints and load each other's checkpoints.
#  7. `remake(prob; field_solver | ode_solver | solvers = …)` equals constructing with that
#     keyword (same fingerprint, same trajectory for the same seed). It keeps `u0`, `p`,
#     the seed and the keywords it does not name. `remake(prob; p | u0 | seed)` never
#     regenerates code: the observable is `remake(…).f === prob.f`, with the negative control
#     that a solver remake gives a different `f`.
#  8. Ensembles: `EnsembleSerial()`, `EnsembleThreads()` and no ensemble algorithm (with and
#     without `backend = CPU()`) give the same trajectories, and repeat exactly.
# Not here: `track` (P6.3a), Metal.
using Potts: CorePotts
using OrdinaryDiffEqRosenbrock: Rodas5P

const p60c_EE = Potts.ExplicitEuler
const p60c_RK4 = Potts.RK4
const p60c_Adaptive = Potts.Adaptive

# A field `c` independent of σ (so its oracle is closed form) and two cell ODEs: `y`
# (non-stiff linear decay) and `s` (stiff, λ = 1000, forced by cos(t)).
@potts_model P60cMixed begin
    @kinds medium A
    @parameters begin
        k = 0.3
        Dc = 0.05
        δ = 0.1
    end
    @variables begin
        c(field) = 0.0
        y(cell) = 1.0
        s(cell) = 0.0
    end
    @lattice Lattice((20, 20))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(c) ~ Dc * Δ(c) - δ * c
        D(y) ~ -k * y
        D(s) ~ -1000 * (s - cos(time))
    end
    @sweep Metropolis(; temperature = 1.0)
end

# the same field alone, and the same ODEs alone (no field)
@potts_model P60cField begin
    @kinds medium A
    @parameters begin
        Dc = 0.05
        δ = 0.1
    end
    @variables c(field) = 0.0
    @lattice Lattice((20, 20))
    @energy cells => (volume - 16.0)^2
    @equations D(c) ~ Dc * Δ(c) - δ * c
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model P60cCells begin
    @kinds medium A
    @parameters k = 0.3
    @variables begin
        y(cell) = 1.0
        s(cell) = 0.0
    end
    @lattice Lattice((20, 20))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ -k * y
        D(s) ~ -1000 * (s - cos(time))
    end
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model P60cDecay begin
    @kinds medium A
    @parameters k = 0.3
    @variables y(cell) = 1.0
    @lattice Lattice((20, 20))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ -k * y
    @sweep Metropolis(; temperature = 1.0)
end

const p60c_N = 20
# one Fourier mode on the periodic 20² lattice: an eigenvector of the 5-point Laplacian
p60c_mode() = [sin(2π * x / p60c_N) * cos(2π * y / p60c_N) for x in 1:p60c_N, y in 1:p60c_N]
p60c_c0() = 1.0 .+ 0.5 .* p60c_mode()
function p60c_sigma(lo = 5)
    σ = zeros(Int32, p60c_N, p60c_N); σ[lo:(lo + 3), lo:(lo + 3)] .= 1
    return σ
end
p60c_op() = [ownership => p60c_sigma(), kind => [:A], :c => p60c_c0()]
p60c_cell_op() = [ownership => p60c_sigma(), kind => [:A]]

# Explicit Euler with m substeps per MCS (h = 1/m) for ∂c/∂t = Dc Δc − δ c on c0: the
# constant part scales by (1 − hδ) and the mode by (1 + h(Dc μ − δ)) per substep, with μ
# the mode's Laplacian eigenvalue 2(2cos(2π/N) − 2). Exact for the discrete scheme.
function p60c_field_oracle(m, n; Dc = 0.05, δ = 0.1)
    h = 1 / m
    μ = 2 * (2cos(2π / p60c_N) - 2)
    return (1 - h * δ)^(n * m) .+ 0.5 * (1 + h * (Dc * μ - δ))^(n * m) .* p60c_mode()
end
p60c_euler_decay(k, n) = (1 - k)^n                                  # ExplicitEuler(), 1 step/MCS
p60c_rk4_decay(k, n) = (1 - k + k^2 / 2 - k^3 / 6 + k^4 / 24)^n    # RK4(), 1 step/MCS
# s' = −1000 (s − cos t), s(0) = 0
p60c_stiff(t) = (1000 * (1000 * cos(t) + sin(t)) - 1000^2 * exp(-1000t)) / (1000^2 + 1)

p60c_rodas(; reltol = 1e-8) = p60c_Adaptive(Rodas5P(); reltol, abstol = 1e-10)
p60c_var(sys, n) = only(filter(x -> string(x) in (string(n), string(n, "(t)")), variables(sys)))

function p60c_error(f)
    try
        f()
        return nothing
    catch e
        while e isa LoadError
            e = e.error
        end
        return e
    end
end
p60c_message(e) = e === nothing ? "" : sprint(showerror, e)

p60c_final(prob, alg = SequentialCPM()) = solve(prob, alg).u[end]
p60c_same(a, b) = Array(a.σ) == Array(b.σ) && a.site == b.site && a.cell == b.cell && a.model == b.model

const p60c_MERKS_OLD_FINGERPRINT = UInt64(14430386590091383282)
const p60c_MERKS_SOLVER = p60c_EE(substeps = 2, lower = 0.0)
p60c_merks() = MerksVasculogenesis(; name = :m, lattice = (100, 100))
p60c_merks_op() = merks_state(; lattice = (100, 100), n = 50, side = 7)    # 7² seeds (D-098)
p60c_merks_sensitive_op() = [p60c_merks_op(); :Dc => 0.01; :c => fill(-0.05, 100, 100)]

# a model with a solver in @sweep, built from source (the error may come at expansion or build)
function p60c_sweep_error(kw::Symbol, solver)
    nm = Symbol(:P60cBadSweep_, kw)
    return p60c_error() do
        Core.eval(@__MODULE__, quote
            @potts_model $nm begin
                @kinds medium A
                @variables c(field) = 0.0
                @variables y(cell) = 1.0
                @lattice Lattice((12, 12))
                @energy cells => (volume - 9.0)^2
                @equations begin
                    D(c) ~ 0.1 * Δ(c)
                    D(y) ~ -y
                end
                @sweep Metropolis(; temperature = 1.0, $kw = $solver)
            end
        end)
        Base.invokelatest(Base.invokelatest(getglobal, @__MODULE__, nm); name = :bad)
    end
end

@testset "P6.0c: @sweep no longer takes solvers (D-075)" begin
    for (kw, solver) in ((:field_solver, :(Potts.ExplicitEuler(substeps = 2))), (:ode_solver, :(Potts.RK4())))
        e = p60c_sweep_error(kw, solver)
        @test e !== nothing
        @test occursin(string(kw), p60c_message(e))
    end
    # negative control: the same model source without the solver builds
    @test P60cMixed(; name = :ok) isa PottsSystem
end

@testset "P6.0c: field_solver is required with a field, rejected without" begin
    e = p60c_error(() -> PottsProblem(P60cMixed(; name = :m), p60c_op(), (0, 2)))
    @test e isa ArgumentError
    @test occursin("field_solver", p60c_message(e))
    sys = P60cMixed(; name = :m)          # other solver keywords do not stand in for it
    e = p60c_error(() -> PottsProblem(sys, p60c_op(), (0, 2); solvers = [p60c_var(sys, :s) => p60c_rodas()]))
    @test e isa ArgumentError && occursin("field_solver", p60c_message(e))
    # with the keyword it builds and runs
    prob = PottsProblem(P60cMixed(; name = :m), p60c_op(), (0, 2); field_solver = p60c_EE(substeps = 2))
    @test solve(prob, SequentialCPM()).t[end] == 2
    # no field: no keyword needed; a field solver is a mistake
    @test PottsProblem(P60cCells(; name = :c), p60c_cell_op(), (0, 2)) isa CorePotts.PottsProblem
    e = p60c_error(() -> PottsProblem(P60cCells(; name = :c), p60c_cell_op(), (0, 2); field_solver = p60c_EE()))
    @test e isa ArgumentError
    @test occursin("field_solver", p60c_message(e))
end

@testset "P6.0c: ode_solver defaults to ExplicitEuler() (D-038)" begin
    sys = P60cDecay(; name = :d)
    bare = PottsProblem(sys, p60c_cell_op(), (0, 5); seed = 3)
    expl = PottsProblem(sys, p60c_cell_op(), (0, 5); seed = 3, ode_solver = p60c_EE())
    rk4 = PottsProblem(sys, p60c_cell_op(), (0, 5); seed = 3, ode_solver = p60c_RK4())
    @test bare.f.fingerprint == expl.f.fingerprint
    @test bare.f.fingerprint != rk4.f.fingerprint
    for alg in (SequentialCPM(), CheckerboardCPM())
        ub, ue, ur = p60c_final(bare, alg), p60c_final(expl, alg), p60c_final(rk4, alg)
        @test p60c_same(ub, ue)
        @test ub.cell.y[1] ≈ p60c_euler_decay(0.3, 5) rtol = 1e-12
        @test ur.cell.y[1] ≈ p60c_rk4_decay(0.3, 5) rtol = 1e-12               # the keyword is honoured
    end
end

@testset "P6.0c: field solver substeps and lower are honoured (closed-form oracle)" begin
    sys = P60cField(; name = :f)
    for m in (2, 3)
        prob = PottsProblem(sys, p60c_op(), (0, 4); field_solver = p60c_EE(substeps = m))
        @test p60c_final(prob).site.c ≈ p60c_field_oracle(m, 4) atol = 1e-12
    end
    # lower: a field driven below zero is clipped at 0 after every substep
    neg = [ownership => p60c_sigma(), kind => [:A], :c => fill(-0.5, p60c_N, p60c_N)]
    clip = p60c_final(PottsProblem(sys, neg, (0, 2); field_solver = p60c_EE(substeps = 2, lower = 0.0)))
    free = p60c_final(PottsProblem(sys, neg, (0, 2); field_solver = p60c_EE(substeps = 2)))
    @test all(iszero, clip.site.c)
    @test free.site.c ≈ fill(-0.5 * (1 - 0.1 / 2)^4, p60c_N, p60c_N) rtol = 1e-12
end

@testset "P6.0c: solvers map — stiff Rodas5P ODE beside an explicit field and an Euler ODE" begin
    t = 5
    rodas = p60c_rodas()
    for alg in (SequentialCPM(), CheckerboardCPM())
        sys = P60cMixed(; name = :m)
        mixed = PottsProblem(sys, p60c_op(), (0, t); field_solver = p60c_EE(substeps = 2),
            solvers = [p60c_var(sys, :s) => rodas])
        u = p60c_final(mixed, alg)
        # each part against its own scheme's oracle
        @test u.site.c ≈ p60c_field_oracle(2, t) atol = 1e-12                    # explicit field, 2 substeps
        @test u.cell.y[1] ≈ p60c_euler_decay(0.3, t) rtol = 1e-12               # ode_solver default, y only
        @test u.cell.s[1] ≈ p60c_stiff(t) rtol = 1e-4                           # Rodas5P, s only
        # conformance against each solver alone
        field = p60c_final(PottsProblem(P60cField(; name = :f), p60c_op(), (0, t); field_solver = p60c_EE(substeps = 2)), alg)
        @test u.site.c ≈ field.site.c atol = 1e-13
        csys = P60cCells(; name = :c)
        adaptive = p60c_final(PottsProblem(csys, p60c_cell_op(), (0, t); ode_solver = rodas), alg)
        @test adaptive.cell.y[1] ≈ exp(-0.3t) rtol = 1e-6                       # all-Rodas: y is exact too
        @test u.cell.s[1] ≈ adaptive.cell.s[1] rtol = 1e-4
        euler = p60c_final(PottsProblem(csys, p60c_cell_op(), (0, t)), alg)
        @test u.cell.y[1] ≈ euler.cell.y[1] rtol = 1e-13
        # negative control: without the override s is integrated by explicit Euler (h = 1,
        # λ = 1000: unstable), far from the solution
        @test !isapprox(euler.cell.s[1], p60c_stiff(t); rtol = 1e-2)
    end
    # a key that is not an integrated variable
    sys = P60cMixed(; name = :m)
    k = only(filter(x -> string(x) == "k", parameters(sys)))
    e = p60c_error(() -> PottsProblem(sys, p60c_op(), (0, 2); field_solver = p60c_EE(), solvers = [k => rodas]))
    @test e isa ArgumentError
end

@testset "P6.0c: Merks needs its field solver explicitly; results unchanged" begin
    e = p60c_error(() -> PottsProblem(p60c_merks(), p60c_merks_op(), (0, 10)))
    @test e isa ArgumentError
    @test occursin("field_solver", p60c_message(e))
    prob = PottsProblem(p60c_merks(), p60c_merks_op(), (0, 10); field_solver = p60c_MERKS_SOLVER)
    for alg in (SequentialCPM(), CheckerboardCPM())
        u = p60c_final(prob, alg)
        @test all(isfinite, Array(u.site.c)) && maximum(Array(u.σ)) > 0
        sens = PottsProblem(p60c_merks(), p60c_merks_sensitive_op(), (0, 10); field_solver = p60c_MERKS_SOLVER)
        @test minimum(Array(p60c_final(sens, alg).site.c)) >= 0                  # lower = 0.0 binds
        dflt = PottsProblem(p60c_merks(), p60c_merks_sensitive_op(), (0, 10); field_solver = p60c_EE())
        @test minimum(Array(p60c_final(dflt, alg).site.c)) < 0                   # no clip without it
    end
    # D-075: a checkpoint from before the change fails the fingerprint check
    @test prob.f.fingerprint != p60c_MERKS_OLD_FINGERPRINT
end

@testset "P6.0c: the D-016 fingerprint hashes the solver spec" begin
    # every problem from a fresh model; `kw(sys)` gives the solver keywords (symbolic keys of that sys)
    mk(kw) = (sys = P60cMixed(; name = :m); PottsProblem(sys, p60c_op(), (0, 4); seed = 2, kw(sys)...))
    sv(sys, solver) = [p60c_var(sys, :s) => solver]
    base() = mk(sys -> (; field_solver = p60c_EE(substeps = 2), solvers = sv(sys, p60c_rodas())))
    a, a′ = base(), base()                                      # fresh model, fresh Adaptive(Rodas5P())
    @test a.f.fingerprint == a′.f.fingerprint
    others = [
        mk(sys -> (; field_solver = p60c_EE(substeps = 3), solvers = sv(sys, p60c_rodas()))),
        mk(sys -> (; field_solver = p60c_EE(substeps = 2, lower = 0.0), solvers = sv(sys, p60c_rodas()))),
        mk(sys -> (; field_solver = p60c_EE(substeps = 2), solvers = sv(sys, p60c_rodas(; reltol = 1e-6)))),
        mk(sys -> (; field_solver = p60c_EE(substeps = 2))),
        mk(sys -> (; field_solver = p60c_EE(substeps = 2), ode_solver = p60c_RK4(), solvers = sv(sys, p60c_rodas()))),
    ]
    for (i, b) in enumerate(others)
        @test b.f.fingerprint != a.f.fingerprint
        for (j, b2) in enumerate(others)
            i < j && @test b.f.fingerprint != b2.f.fingerprint
        end
    end
    integ = init(a, SequentialCPM()); step!(integ); step!(integ)
    ck = checkpoint(integ)
    @test ck.fingerprint == a.f.fingerprint
    for b in others
        e = p60c_error(() -> init(b, SequentialCPM(); checkpoint = ck))
        @test e isa ArgumentError
    end
    # an equal spec built afresh accepts it, and continues the run exactly
    cont = solve!(init(a′, SequentialCPM(); checkpoint = ck)).u[end]
    @test p60c_same(cont, p60c_final(a))
end

@testset "P6.0c: remake with a solver = construction with it; p/u0/seed never regenerate" begin
    sys = P60cMixed(; name = :m)
    s = p60c_var(sys, :s)
    prob = PottsProblem(sys, p60c_op(), (0, 4); seed = 11, field_solver = p60c_EE(substeps = 2))
    # p, u0 and seed: the same generated code
    c2 = 1.0 .- 0.25 .* p60c_mode()
    op2 = [ownership => p60c_sigma(9), kind => [:A], :c => c2, :y => 2.0]
    @test remake(prob; p = [:k => 0.2]).f === prob.f
    @test remake(prob; u0 = op2).f === prob.f
    @test remake(prob; seed = 5).f === prob.f
    # a remade problem carrying a changed p and u0, then a solver remake
    prob1 = remake(prob; p = [:k => 0.2], u0 = op2)
    cases = [
        ((; field_solver = p60c_EE(substeps = 3)), (; field_solver = p60c_EE(substeps = 3))),
        ((; ode_solver = p60c_RK4()), (; field_solver = p60c_EE(substeps = 2), ode_solver = p60c_RK4())),
        ((; solvers = [s => p60c_rodas()]), (; field_solver = p60c_EE(substeps = 2), solvers = [s => p60c_rodas()])),
    ]
    for (kw, full) in cases
        r = remake(prob1; kw...)
        d = PottsProblem(sys, [op2; :k => 0.2], (0, 4); seed = 11, full...)
        @test r.f !== prob1.f                                               # rebuilt (negative control)
        @test r.f.fingerprint == d.f.fingerprint
        @test r.seed == d.seed == 11
        @test r.p == d.p && r.p.k == 0.2
        @test p60c_same(r.u0, d.u0) && Array(r.u0.σ) == p60c_sigma(9) && r.u0.site.c == c2
        @test p60c_same(p60c_final(r), p60c_final(d))
    end
    # remake of the same spec matches the original problem
    @test remake(prob; field_solver = p60c_EE(substeps = 2)).f.fingerprint == prob.f.fingerprint
end

@testset "P6.0c: ensembles (serial, threads, default)" begin
    sys = P60cMixed(; name = :m)
    prob = PottsProblem(sys, p60c_op(), (0, 3); field_solver = p60c_EE(substeps = 2),
        solvers = [p60c_var(sys, :s) => p60c_rodas()])
    ens = EnsembleProblem(prob)
    alg = SequentialCPM()
    finals(sol) = [x.u[end] for x in sol.u]
    serial = finals(solve(ens, alg, EnsembleSerial(); trajectories = 3))
    @test length(serial) == 3
    @test Array(serial[1].σ) != Array(serial[2].σ)                          # independent replicas
    @test all(u -> isapprox(u.cell.s[1], p60c_stiff(3); rtol = 1e-4), serial)
    for other in (finals(solve(ens, alg, EnsembleThreads(); trajectories = 3)),
                  finals(solve(ens, alg; trajectories = 3)),
                  finals(solve(ens, alg; trajectories = 3, backend = CPU())),
                  finals(solve(ens, alg, EnsembleSerial(); trajectories = 3)))
        @test all(i -> p60c_same(other[i], serial[i]), 1:3)
    end
end
