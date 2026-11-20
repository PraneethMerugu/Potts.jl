# solver placement, breaking batch part 2 (D-075 Q9 and the
# AUTHORING §6 / D-016 / D-038 amendments; api-synthesis §3.4).
#
# Semantics pinned here:
#  1. `field_solver`, `ode_solver` and `solvers` are `PottsProblem` construction keywords.
#     `@sweep` no longer takes `field_solver` or `ode_solver`: building a model that puts one
#     there is an error (any exception, at expansion or at build) whose message names the
#     keyword.
#  2. `field_solver` defaults to `ExplicitEuler()` when the model has a field (the field-solver default ruling,
#     amending D-075): a bare `PottsProblem(model_with_field, op, tspan)` builds, with the
#     fingerprint of `field_solver = ExplicitEuler()`. A model without a field needs none,
#     and passing one to it is an `ArgumentError` naming `field_solver` (a solver for a
#     field that does not exist is a mistake, as an operating-point key naming nothing is;
#     it also keeps an unused spec out of the D-016 fingerprint).
#  3. `ode_solver` defaults to `ExplicitEuler()` (D-038 as amended by D-075): no keyword and
#     `ode_solver = ExplicitEuler()` give the same fingerprint and the same trajectory.
#  4. `solvers = [x => solver]` is keyed by the symbolic variable and overrides `ode_solver`
#     for that variable only. A stiff ODE under `Adaptive(Rodas5P())` beside an explicit
#     field and an explicit-Euler ODE in one model: each part conforms to its solver alone
#     (closed-form oracles of the discrete schemes, the analytic solution for Rodas5P). A key
#     that is a parameter, not an integrated variable, is an `ArgumentError`.
#  5. Merks: a bare `PottsProblem(MerksVasculogenesis(…), …)` throws; with
#     `field_solver = ExplicitEuler(substeps = 2, lower_bound = 0.0)` it builds and runs, and in a
#     configuration where they bind (c(0) = −0.05), `lower_bound = 0.0` keeps the field ≥ 0 while
#     `ExplicitEuler()` does not. Bitwise equality with the pre-change (`@sweep`-placed)
#     result is checked by the coordinator at merge, not checked here (digests would pin
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
# Not here: `track` (`topology_tracking_tests.jl`), Metal.

@testsetup module SolverPlacementSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
using OrdinaryDiffEqRosenbrock: Rodas5P
const placement_EE = Potts.ExplicitEuler
const placement_RK4 = Potts.RK4
const placement_Adaptive = Potts.Adaptive
# The field `c` as a plain MTK PDESystem on `dims`, coupled with `@fields`: `Dc Δc − δ c`
# (`decay = true`, its parameters `Dc`, `δ`), or `0.1 Δc`
function field_pde(dims = (20, 20); decay = true)
    t, L = Potts.t, Potts.LatticePDE
    Potts.ModelingToolkitBase.@parameters x y Dc = 0.05 δ = 0.1
    Potts.ModelingToolkitBase.@variables c(..)
    C = c(t, x, y)
    rate, ps = decay ? (Dc * L.laplacian(C) - δ * C, [Dc, δ]) : (0.1 * L.laplacian(C), Any[])
    return Potts.ModelingToolkitBase.PDESystem(
        [Potts.D(C) ~ rate], [c(0, x, y) ~ 0.0],
        L.lattice_domain(t, (x, y), dims), [t, x, y], [C], ps; name = :placement_field
    )
end
# A field `c` independent of σ (so its oracle is closed form) and two cell ODEs: `y`
# (non-stiff linear decay) and `s` (stiff, λ = 1000, forced by cos(t)).
@potts_model PlacementMixed begin
    @kinds medium A
    @parameters k = 0.3
    @lattice Lattice((20, 20))
    @fields field_pde()
    @variables begin
        y(cell) = 1.0
        s(cell) = 0.0
    end
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ -k * y
        D(s) ~ -1000 * (s - cos(time))
    end
    @sweep Metropolis(; temperature = 1.0)
end
# the same field alone, and the same ODEs alone (no field)
@potts_model Field begin
    @kinds medium A
    @lattice Lattice((20, 20))
    @fields field_pde()
    @energy cells => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model Cells begin
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
@potts_model Decay begin
    @kinds medium A
    @parameters k = 0.3
    @variables y(cell) = 1.0
    @lattice Lattice((20, 20))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ -k * y
    @sweep Metropolis(; temperature = 1.0)
end
const placement_N = 20
# one Fourier mode on the periodic 20² lattice: an eigenvector of the 5-point Laplacian
mode() = [sin(2π * x / placement_N) * cos(2π * y / placement_N) for x in 1:placement_N, y in 1:placement_N]
placement_c0() = 1.0 .+ 0.5 .* mode()
function sigma(lo = 5)
    σ = zeros(Int32, placement_N, placement_N); σ[lo:(lo + 3), lo:(lo + 3)] .= 1
    return σ
end
placement_op() = [ownership => sigma(), kind => [:A], :c => placement_c0()]
cell_op() = [ownership => sigma(), kind => [:A]]
# Explicit Euler with m substeps per MCS (h = 1/m) for ∂c/∂t = Dc Δc − δ c on c0: the
# constant part scales by (1 − hδ) and the mode by (1 + h(Dc μ − δ)) per substep, with μ
# the mode's Laplacian eigenvalue 2(2cos(2π/N) − 2). Exact for the discrete scheme.
function field_oracle(m, n; Dc = 0.05, δ = 0.1)
    h = 1 / m
    μ = 2 * (2cos(2π / placement_N) - 2)
    return (1 - h * δ)^(n * m) .+ 0.5 * (1 + h * (Dc * μ - δ))^(n * m) .* mode()
end
euler_decay(k, n) = (1 - k)^n
# ExplicitEuler(), 1 step/MCS
rk4_decay(k, n) = (1 - k + k^2 / 2 - k^3 / 6 + k^4 / 24)^n
# Potts.RK4(), 1 step/MCS
# s' = −1000 (s − cos t), s(0) = 0
placement_stiff(t) = (1000 * (1000 * cos(t) + sin(t)) - 1000^2 * exp(-1000t)) / (1000^2 + 1)
placement_rodas(; reltol = 1.0e-8) = placement_Adaptive(Rodas5P(); reltol, abstol = 1.0e-10)
placement_var(sys, n) = only(filter(x -> string(x) in (string(n), string(n, "(t)")), Potts.declared_variables(sys)))
function placement_error(f)
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
message(e) = e === nothing ? "" : sprint(showerror, e)
final(prob, alg = SequentialCPM()) = solve(prob, alg).u[end]
same(a, b) = Array(a.ownership) == Array(b.ownership) && a.site == b.site && a.cell == b.cell && a.model == b.model
const MERKS_SOLVER = placement_EE(substeps = 2, lower_bound = 0.0)
merks() = MerksVasculogenesis(; name = :m, lattice = (100, 100))
merks_op() = merks_state(; lattice = (100, 100), n = 50, side = 7)
# 7² seeds (D-098)
merks_sensitive_op() = [merks_op(); :Dc => 0.01; :c => fill(-0.05, 100, 100)]
# a model with a solver in @sweep, built from source (the error may come at expansion or build)
function sweep_error(kw::Symbol, solver)
    nm = Symbol(:BadSweep_, kw)
    return placement_error() do
        Core.eval(
            @__MODULE__, quote
                @potts_model $nm begin
                    @kinds medium A
                    @lattice Lattice((12, 12))
                    @fields field_pde((12, 12); decay = false)
                    @variables y(cell) = 1.0
                    @energy cells => (volume - 9.0)^2
                    @equations D(y) ~ -y
                    @sweep Metropolis(; temperature = 1.0, $kw = $solver)
                end
            end
        )
        Base.invokelatest(Base.invokelatest(getglobal, @__MODULE__, nm); name = :bad)
    end
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "solver placement: @sweep no longer takes solvers" setup = [SolverPlacementSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "solver placement: @sweep no longer takes solvers" begin
        for (kw, solver) in ((:field_solver, :(Potts.ExplicitEuler(substeps = 2))), (:ode_solver, :(Potts.RK4())))
            e = sweep_error(kw, solver)
            @test e !== nothing
            @test occursin(string(kw), message(e))
        end
        # negative control: the same model source without the solver builds
        @test PlacementMixed(; name = :ok) isa PottsSystem
    end
end

@testitem "solver placement: field_solver defaults to ExplicitEuler with a field, rejected without" setup = [SolverPlacementSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "solver placement: field_solver defaults to ExplicitEuler() with a field, rejected without" begin
        d = PottsProblem(PlacementMixed(; name = :m), placement_op(), (0, 2))      # the default ExplicitEuler()
        @test d.f.fingerprint == PottsProblem(PlacementMixed(; name = :m), placement_op(), (0, 2); field_solver = placement_EE()).f.fingerprint
        sys = PlacementMixed(; name = :m)          # with other solver keywords too
        d = PottsProblem(sys, placement_op(), (0, 2); solvers = [placement_var(sys, :s) => placement_rodas()])
        @test d.f.fingerprint == PottsProblem(
            sys, placement_op(), (0, 2); field_solver = placement_EE(),
            solvers = [placement_var(sys, :s) => placement_rodas()]
        ).f.fingerprint
        # with the keyword it builds and runs
        prob = PottsProblem(PlacementMixed(; name = :m), placement_op(), (0, 2); field_solver = placement_EE(substeps = 2))
        @test solve(prob, SequentialCPM()).t[end] == 2
        # no field: no keyword needed; a field solver is a mistake
        @test PottsProblem(Cells(; name = :c), cell_op(), (0, 2)) isa CorePotts.PottsProblem
        e = placement_error(() -> PottsProblem(Cells(; name = :c), cell_op(), (0, 2); field_solver = placement_EE()))
        @test e isa ArgumentError
        @test occursin("field_solver", message(e))
    end
end

@testitem "solver placement: ode_solver defaults to ExplicitEuler" setup = [SolverPlacementSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "solver placement: ode_solver defaults to ExplicitEuler()" begin
        sys = Decay(; name = :d)
        bare = PottsProblem(sys, cell_op(), (0, 5); seed = 3)
        expl = PottsProblem(sys, cell_op(), (0, 5); seed = 3, ode_solver = placement_EE())
        rk4 = PottsProblem(sys, cell_op(), (0, 5); seed = 3, ode_solver = placement_RK4())
        @test bare.f.fingerprint == expl.f.fingerprint
        @test bare.f.fingerprint != rk4.f.fingerprint
        for alg in (SequentialCPM(), CheckerboardCPM())
            ub, ue, ur = final(bare, alg), final(expl, alg), final(rk4, alg)
            @test same(ub, ue)
            @test ub.cell.y[1] ≈ euler_decay(0.3, 5) rtol = 1.0e-12
            @test ur.cell.y[1] ≈ rk4_decay(0.3, 5) rtol = 1.0e-12               # the keyword is honoured
        end
    end
end

@testitem "solver placement: field solver substeps and lower are honoured (closed-form oracle)" setup = [SolverPlacementSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "solver placement: field solver substeps and lower are honoured (closed-form oracle)" begin
        sys = Field(; name = :f)
        for m in (2, 3)
            prob = PottsProblem(sys, placement_op(), (0, 4); field_solver = placement_EE(substeps = m))
            @test final(prob).site.c ≈ field_oracle(m, 4) atol = 1.0e-12
        end
        # lower: a field driven below zero is clipped at 0 after every substep
        neg = [ownership => sigma(), kind => [:A], :c => fill(-0.5, placement_N, placement_N)]
        clip = final(PottsProblem(sys, neg, (0, 2); field_solver = placement_EE(substeps = 2, lower_bound = 0.0)))
        free = final(PottsProblem(sys, neg, (0, 2); field_solver = placement_EE(substeps = 2)))
        @test all(iszero, clip.site.c)
        @test free.site.c ≈ fill(-0.5 * (1 - 0.1 / 2)^4, placement_N, placement_N) rtol = 1.0e-12
    end
end

@testitem "solver placement: solvers map — stiff Rodas5P ODE beside an explicit field and an Euler ODE" setup = [SolverPlacementSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "solver placement: solvers map — stiff Rodas5P ODE beside an explicit field and an Euler ODE" begin
        t = 5
        rodas = placement_rodas()
        for alg in (SequentialCPM(), CheckerboardCPM())
            sys = PlacementMixed(; name = :m)
            mixed = PottsProblem(
                sys, placement_op(), (0, t); field_solver = placement_EE(substeps = 2),
                solvers = [placement_var(sys, :s) => rodas]
            )
            u = final(mixed, alg)
            # each part against its own scheme's oracle
            @test u.site.c ≈ field_oracle(2, t) atol = 1.0e-12                    # explicit field, 2 substeps
            @test u.cell.y[1] ≈ euler_decay(0.3, t) rtol = 1.0e-12               # ode_solver default, y only
            @test u.cell.s[1] ≈ placement_stiff(t) rtol = 1.0e-4                           # Rodas5P, s only
            # conformance against each solver alone
            field = final(PottsProblem(Field(; name = :f), placement_op(), (0, t); field_solver = placement_EE(substeps = 2)), alg)
            @test u.site.c ≈ field.site.c atol = 1.0e-13
            csys = Cells(; name = :c)
            adaptive = final(PottsProblem(csys, cell_op(), (0, t); ode_solver = rodas), alg)
            @test adaptive.cell.y[1] ≈ exp(-0.3t) rtol = 1.0e-6                       # all-Rodas: y is exact too
            @test u.cell.s[1] ≈ adaptive.cell.s[1] rtol = 1.0e-4
            euler = final(PottsProblem(csys, cell_op(), (0, t)), alg)
            @test u.cell.y[1] ≈ euler.cell.y[1] rtol = 1.0e-13
            # negative control: without the override s is integrated by explicit Euler (h = 1,
            # λ = 1000: unstable), far from the solution
            @test !isapprox(euler.cell.s[1], placement_stiff(t); rtol = 1.0e-2)
        end
        # a key that is not an integrated variable
        sys = PlacementMixed(; name = :m)
        k = only(filter(x -> string(x) == "k", Potts.declared_parameters(sys)))
        e = placement_error(() -> PottsProblem(sys, placement_op(), (0, 2); field_solver = placement_EE(), solvers = [k => rodas]))
        @test e isa ArgumentError
    end
end

@testitem "solver placement: Merks with its field solver; the bare problem takes the default; results unchanged" setup = [SolverPlacementSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "solver placement: Merks with its field solver; the bare problem takes the default; results unchanged" begin
        d = PottsProblem(merks(), merks_op(), (0, 10))      # the default ExplicitEuler()
        @test d.f.fingerprint == PottsProblem(merks(), merks_op(), (0, 10); field_solver = placement_EE()).f.fingerprint
        prob = PottsProblem(merks(), merks_op(), (0, 10); field_solver = MERKS_SOLVER)
        for alg in (SequentialCPM(), CheckerboardCPM())
            u = final(prob, alg)
            @test all(isfinite, Array(u.site.c)) && maximum(Array(u.ownership)) > 0
            sens = PottsProblem(merks(), merks_sensitive_op(), (0, 10); field_solver = MERKS_SOLVER)
            @test minimum(Array(final(sens, alg).site.c)) >= 0                  # lower_bound = 0.0 binds
            dflt = PottsProblem(merks(), merks_sensitive_op(), (0, 10); field_solver = placement_EE())
            @test minimum(Array(final(dflt, alg).site.c)) < 0                   # no clip without it
        end
    end
end

@testitem "solver placement: the fingerprint hashes the solver spec" setup = [SolverPlacementSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "solver placement: the fingerprint hashes the solver spec" begin
        # every problem from a fresh model; `kw(sys)` gives the solver keywords (symbolic keys of that sys)
        mk(kw) = (sys = PlacementMixed(; name = :m); PottsProblem(sys, placement_op(), (0, 4); seed = 2, kw(sys)...))
        sv(sys, solver) = [placement_var(sys, :s) => solver]
        base() = mk(sys -> (; field_solver = placement_EE(substeps = 2), solvers = sv(sys, placement_rodas())))
        a, a′ = base(), base()                                      # fresh model, fresh Adaptive(Rodas5P())
        @test a.f.fingerprint == a′.f.fingerprint
        others = [
            mk(sys -> (; field_solver = placement_EE(substeps = 3), solvers = sv(sys, placement_rodas()))),
            mk(sys -> (; field_solver = placement_EE(substeps = 2, lower_bound = 0.0), solvers = sv(sys, placement_rodas()))),
            mk(sys -> (; field_solver = placement_EE(substeps = 2), solvers = sv(sys, placement_rodas(; reltol = 1.0e-6)))),
            mk(sys -> (; field_solver = placement_EE(substeps = 2))),
            mk(sys -> (; field_solver = placement_EE(substeps = 2), ode_solver = placement_RK4(), solvers = sv(sys, placement_rodas()))),
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
            e = placement_error(() -> init(b, SequentialCPM(); checkpoint = ck))
            @test e isa ArgumentError
        end
        # an equal spec built afresh accepts it, and continues the run exactly
        cont = solve!(init(a′, SequentialCPM(); checkpoint = ck)).u[end]
        @test same(cont, final(a))
    end
end

@testitem "solver placement: remake with a solver = construction with it; p/u0/seed never regenerate" setup = [SolverPlacementSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "solver placement: remake with a solver = construction with it; p/u0/seed never regenerate" begin
        sys = PlacementMixed(; name = :m)
        s = placement_var(sys, :s)
        prob = PottsProblem(sys, placement_op(), (0, 4); seed = 11, field_solver = placement_EE(substeps = 2))
        # p, u0 and seed: the same generated code
        c2 = 1.0 .- 0.25 .* mode()
        op2 = [ownership => sigma(9), kind => [:A], :c => c2, :y => 2.0]
        @test remake(prob; p = [:k => 0.2]).f === prob.f
        @test remake(prob; u0 = op2).f === prob.f
        @test remake(prob; seed = 5).f === prob.f
        # a remade problem carrying a changed p and u0, then a solver remake
        prob1 = remake(prob; p = [:k => 0.2], u0 = op2)
        cases = [
            ((; field_solver = placement_EE(substeps = 3)), (; field_solver = placement_EE(substeps = 3))),
            ((; ode_solver = placement_RK4()), (; field_solver = placement_EE(substeps = 2), ode_solver = placement_RK4())),
            ((; solvers = [s => placement_rodas()]), (; field_solver = placement_EE(substeps = 2), solvers = [s => placement_rodas()])),
        ]
        for (kw, full) in cases
            r = remake(prob1; kw...)
            d = PottsProblem(sys, [op2; :k => 0.2], (0, 4); seed = 11, full...)
            @test r.f !== prob1.f                                               # rebuilt (negative control)
            @test r.f.fingerprint == d.f.fingerprint
            @test r.seed == d.seed == 11
            @test r.p == d.p && r.p.k == 0.2
            @test same(r.u0, d.u0) && Array(r.u0.ownership) == sigma(9) && r.u0.site.c == c2
            @test same(final(r), final(d))
        end
        # remake of the same spec matches the original problem
        @test remake(prob; field_solver = placement_EE(substeps = 2)).f.fingerprint == prob.f.fingerprint
    end
end

@testitem "solver placement: ensembles (serial, threads, default)" setup = [SolverPlacementSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "solver placement: ensembles (serial, threads, default)" begin
        sys = PlacementMixed(; name = :m)
        prob = PottsProblem(
            sys, placement_op(), (0, 3); field_solver = placement_EE(substeps = 2),
            solvers = [placement_var(sys, :s) => placement_rodas()]
        )
        ens = EnsembleProblem(prob)
        alg = SequentialCPM()
        finals(sol) = [x.u[end] for x in sol.u]
        serial = finals(solve(ens, alg, EnsembleSerial(); trajectories = 3))
        @test length(serial) == 3
        @test Array(serial[1].ownership) != Array(serial[2].ownership)                          # independent replicas
        @test all(u -> isapprox(u.cell.s[1], placement_stiff(3); rtol = 1.0e-4), serial)
        for other in (
                finals(solve(ens, alg, EnsembleThreads(); trajectories = 3)),
                finals(solve(ens, alg; trajectories = 3)),
                finals(solve(ens, alg; trajectories = 3, backend = CPU())),
                finals(solve(ens, alg, EnsembleSerial(); trajectories = 3)),
            )
            @test all(i -> same(other[i], serial[i]), 1:3)
        end
    end
end
