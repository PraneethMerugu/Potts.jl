# P6.0bn (ROADMAP Phase 6, step 0; D-159, D-162; research/mtk-native-plan.md §4 route A2,
# §5, §6): a model's own cell- and model-scope ODEs go through ModelingToolkit's
# `mtkcompile` before Potts lowers them. Potts builds one MTK `System` per scope from the
# `@equations` of that scope (the per-cell template: one cell's equations, compiled once,
# advanced for every cell by Potts' batched kernel as before), lets MTK's structural
# simplification eliminate the algebraic (observed) variables, and lowers the simplified
# equations. This makes plan §5's sentence true for ODEs: "The continuous ... parts of a
# model are ModelingToolkit systems compiled by `mtkcompile`". Fields (lattice PDEs) are not
# in this item; they stay Potts' `FieldStep`.
# Decision: D-1xx (P6.0bn; the coordinator numbers it). Frozen (AUTONOMY §7.3).
#
# What is new for users: `@equations` accepts explicit algebraic equations `y ~ expr` for a
# declared cell or model variable `y`. MTK eliminates `y` as an observed variable; it is no
# longer a stored state, reads everywhere as its definition (MTK observed semantics), and
# stays readable through SymbolicIndexingInterface (`sol[:y]`). Before this item, Potts
# rejects every non-differential equation in `@equations` ("equations are `D(x) ~ rhs`").
#
# The contract pinned here (public API only; the template's construction, input
# placeholders, storage of the compiled systems, and whether the lowering reads MTK's
# equations or re-substitutes MTK's observed are the implementer's):
#  A. `Potts.ode_system` is a public (not exported) name of Potts with a docstring.
#  S. `Potts.ode_system(csys::CompiledPottsSystem, scope)` for `scope` in `:cell`, `:model`
#     returns the `ModelingToolkitBase.System` that `mtkcompile` produced for that scope's
#     `@equations`, or `nothing` when the scope has none. It is complete and scheduled (MTK's
#     own mark of an `mtkcompile` result). Its unknowns are the scope's differential
#     variables (by declared name), each algebraic variable is an `observed` equation and not
#     an unknown, and each declared parameter the equations read is a parameter under its
#     declared name. Other quantities the ODEs read (built-ins such as `volume`, other scopes'
#     variables, gathers, population folds, cross-cell reads `y[3 - id]`) are inputs: further
#     parameters, names not pinned. A template with no inputs is an ordinary MTK system: MTK's
#     own `ODEProblem` solves it (oracle: the analytic solution). Other scopes (`:site`,
#     `:field`, anything else) are an `ArgumentError`, and so is a `PottsSystem` that has not
#     been through `mtkcompile` (the message names `mtkcompile`).
#  E. Elimination shows up in the run: a model with `D(x) ~ -k*xalias; xalias ~ x` runs
#     exactly like its hand-substituted twin `D(x) ~ -k*x` (same seed, every save, rtol 1e-12:
#     D-158's tolerance for values that pass through upstream code; MTK's symbolic pass is
#     upstream), matches the exact discrete oracle of explicit Euler (x0·0.9^N) and the
#     analytic one under RK4 (x0·e^(−0.1N), rtol 1e-7), and `sol[:xalias] ≈ sol[:x]`. An
#     `@after_mcs` update reading `xalias` reads `x` (oracle: Σ x0·0.9^j). The same for a chain
#     of algebraic variables that read built-ins and a neighbour gather (P6.0x's shape:
#     `w ~ volume`, `g ~ sum(volume[owner[n]] for n in Moore(1)(42))`, `h ~ g − w`, written
#     out of order), with `sol[:w]` equal to the cell volumes counted on the saved lattice and
#     `sol[:g]` one value per cell (an algebraic variable's values have its declared shape), and
#     for a model-scope pair `D(m) ~ r*gap; gap ~ 1 − m` (oracles 1 − 0.8^N and 1 − e^(−0.2N)).
#     Zero warm allocations per `step!` (the fixed-step gate) for these models.
#  U. Unchanged: models whose `@equations` are all differential keep their results (recorded
#     on 4b81dd79, the tree before this item: a gather rate and a cross-cell rate, both CPM
#     algorithms, explicit Euler and RK4; rtol 1e-12) and have no observed variables in their
#     template. Every published model has no cell or model ODE, so both its templates are
#     `nothing`; the published model with ODEs (Merks, field PDEs) runs bitwise as recorded on
#     4b81dd79 (our own field step, D-158). Generated code and fingerprints of all-differential
#     models are pinned byte-identical by p6_0o (D-137 rule 7), not here.
#  R. Rejections, at `mtkcompile` (ArgumentError; the words listed must appear): an implicit
#     equation (`xalias + x ~ 1`: "algebraic"); an algebraic equation for a field
#     ("algebraic", the name); a variable with both `D(·)` and an algebraic equation, two
#     algebraic equations for one variable, a self-reference, and a cycle through two
#     equations ("algebraic", the name where there is one); an update writing an algebraic
#     variable ("algebraic", the name). Whether ModelingToolkit (full, with tearing) is loaded
#     must not change what is accepted. An operating-point value for an algebraic variable is
#     an ArgumentError naming it.
#  N. Negative controls: a plain MTK `System` with the same alias keeps `xalias` as an
#     unknown under `complete` and is not scheduled (the detector used in S can fail), and
#     loses it under `mtkcompile` (the detector can pass); an oracle with a wrong rate does
#     not match the run.
#
# On 4b81dd79 every A/S/E target errors (`Potts.ode_system` is undefined, and every fixture
# with an algebraic equation is rejected by `mtkcompile`), R fails on the missing word
# "algebraic", and the U pins, the N controls and the operating-point rejection pass.
using Potts: CorePotts
using OrdinaryDiffEqRosenbrock: Rodas5P

const P60BN_M = Potts.ModelingToolkitBase
const P60BN_S = Potts.Symbolics
const P60BN_SII = Potts.SymbolicIndexingInterface

p60bn_name(x) = P60BN_SII.getname(x)
p60bn_names(xs) = Set{Symbol}(p60bn_name(x) for x in xs)
p60bn_ode(c, scope) = Potts.ode_system(c, scope)
# MTK's mark of an `mtkcompile` result (`complete` alone does not set it)
p60bn_scheduled(s) = P60BN_M.isscheduled(s)
p60bn_observed_names(s) = Set{Symbol}(p60bn_name(o.lhs) for o in P60BN_M.observed(s))
p60bn_byname(xs, n) = only(x for x in xs if p60bn_name(x) === n)

p60bn_clear(f, words...) = try
    f()
    false
catch err
    ok = err isa ArgumentError && all(w -> occursin(w, sprint(showerror, err)), words)
    ok || @info "P6.0bn: expected an ArgumentError naming $(words)" exception = err
    ok
end

# ---------------------------------------------------------------------------------------
# Fixtures: two 4×4 cells side by side (x = 3:6 and 7:10, y = 3:6) on a 12×8 lattice, as in
# p6_0x. Site 42 is (6, 4), on their interface. No energy reads an ODE variable, so a model
# and its twin see the same sweep for the same seed.

# E: an alias of the differential variable, read by the ODE and by an update
@potts_model P60bnAlias begin
    @kinds medium A
    @parameters k = 0.1
    @variables begin
        x(cell) = 2.0
        xalias(cell) = 0.0
        acc(cell) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(x) ~ -k * xalias
        xalias ~ x
    end
    @after_mcs acc ~ Pre(acc) + xalias
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P60bnAliasHand begin
    @kinds medium A
    @parameters k = 0.1
    @variables begin
        x(cell) = 2.0
        acc(cell) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(x) ~ -k * x
    @after_mcs acc ~ Pre(acc) + x
    @sweep Metropolis(; temperature = 1.0)
end

# E: a chain of algebraic variables reading built-ins and a gather, written out of order
@potts_model P60bnInputs begin
    @kinds medium A
    @variables begin
        y(cell) = 0.0
        w(cell) = 0.0
        g(cell) = 0.0
        h(cell) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ 0.01 * h - 0.1y
        h ~ g - w
        g ~ sum(volume[owner[n]] for n in Moore(1)(42))
        w ~ volume
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P60bnInputsHand begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.01 * (sum(volume[owner[n]] for n in Moore(1)(42)) - volume) - 0.1y
    @sweep Metropolis(; temperature = 1.0)
end

# E: model scope
@potts_model P60bnModel begin
    @kinds medium A
    @parameters r = 0.2
    @variables begin
        m(model) = 0.0
        gap(model) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(m) ~ r * gap
        gap ~ 1 - m
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P60bnModelHand begin
    @kinds medium A
    @parameters r = 0.2
    @variables m(model) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(m) ~ r * (1 - m)
    @sweep Metropolis(; temperature = 1.0)
end

# U: a cross-cell read of the template's own unknown (P6.0n's Jacobi path)
@potts_model P60bnPair begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.5 * (y[3 - id] - y)
    @sweep Metropolis(; temperature = 1.0)
end

# R: rejected models (built in the testsets; the macro accepts them, `mtkcompile` decides)
@potts_model P60bnImplicit begin
    @kinds medium A
    @parameters k = 0.1
    @variables begin
        x(cell) = 2.0
        xalias(cell) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(x) ~ -k * x
        xalias + x ~ 1.0
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P60bnFieldAlg begin
    @kinds medium A
    @variables cfield(field) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations cfield ~ 1.0
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P60bnBoth begin
    @kinds medium A
    @variables begin
        x(cell) = 2.0
        xalias(cell) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(x) ~ -0.1x
        D(xalias) ~ 1.0
        xalias ~ x
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P60bnTwice begin
    @kinds medium A
    @variables begin
        x(cell) = 2.0
        xalias(cell) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(x) ~ -0.1xalias
        xalias ~ x
        xalias ~ 2x
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P60bnSelf begin
    @kinds medium A
    @variables begin
        x(cell) = 2.0
        xalias(cell) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(x) ~ -0.1xalias
        xalias ~ 0.5xalias + x
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P60bnCycle begin
    @kinds medium A
    @variables begin
        x(cell) = 2.0
        p(cell) = 0.0
        q(cell) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(x) ~ -0.1p
        p ~ q + x
        q ~ p - x
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P60bnWrite begin
    @kinds medium A
    @variables begin
        x(cell) = 2.0
        xalias(cell) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(x) ~ -0.1xalias
        xalias ~ x
    end
    @after_mcs xalias ~ 1.0
    @sweep Metropolis(; temperature = 1.0)
end

p60bn_sigma() = (s = zeros(Int32, 12, 8); s[3:6, 3:6] .= 1; s[7:10, 3:6] .= 2; s)
p60bn_op(extra...) = Any[ownership => p60bn_sigma(), kind => [:A, :A], extra...]
const P60BN_X0 = [2.0, 3.0]
const P60BN_N = 10                                     # MCS per run
const P60BN_ALGS = (("SequentialCPM", SequentialCPM(; proposal = Moore(1))), ("CheckerboardCPM", CheckerboardCPM(; proposal = Moore(1))))
const P60BN_SOLVERS = (("ExplicitEuler()", (;)), ("RK4(substeps = 4)", (; ode_solver = Potts.RK4(substeps = 4))))

p60bn_solve(M, op, alg, kw) = solve(PottsProblem(M(; name = :x), op, (0, P60BN_N); seed = 7, kw...), alg; saveat = 1)
p60bn_cells(sol, n) = [Vector{Float64}(Array(getproperty(u.cell, n))) for u in sol.u]
p60bn_series(sol, n) = [Vector{Float64}(Array(v)) for v in sol[n]]
p60bn_volumes(sol) = [[Float64(count(==(c), u.σ)) for c in 1:2] for u in sol.u]
p60bn_close(a, b; rtol = 1e-12) = length(a) == length(b) && all(i -> isapprox(a[i], b[i]; rtol), eachindex(a, b))

"""Bytes allocated by each of five warm `step!`s (after two warm-up steps)."""
function p60bn_warm_allocs(prob, alg)
    integ = init(prob, alg; save_start = false, save_end = false)
    step!(integ)
    step!(integ)
    out = Int[]
    for _ in 1:5
        push!(out, @allocated step!(integ))
    end
    return out
end

# the alias as a plain MTK system (negative controls)
function p60bn_plain()
    t = Potts.t
    P60BN_M.@variables xs(t) = 2.0 xa(t)
    P60BN_M.@parameters ks = 0.1
    return P60BN_M.System([Potts.D(xs) ~ -ks * xa, xa ~ xs], t; name = :plain)
end

# every published model (small lattices; construction and `mtkcompile` only)
const P60BN_PUBLISHED = [
    ("GranerGlazier", () -> GranerGlazier(; name = :gg)),
    ("WortelAct", () -> WortelAct(; name = :act, lattice = (8, 8))),
    ("WortelAct connected", () -> WortelAct(; name = :act, lattice = (8, 8), connected = true)),
    ("MerksVasculogenesis", () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8))),
    ("MerksVasculogenesis contact-inhibited",
        () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8), contact_inhibited = true)),
    ("Merks2006", () -> Merks2006(; name = :m6, lattice = (16, 16))),
    ("Merks2006 hard", () -> Merks2006(; name = :m6, lattice = (16, 16), rule = :hard)),
    ("Merks2008", () -> Merks2008(; name = :m8, lattice = (16, 16))),
    ("Merks2008 extension only", () -> Merks2008(; name = :m8, lattice = (16, 16), mode = :extension_only)),
    ("SingleDivisionFixture", () -> SingleDivisionFixture(; name = :fixture)),
    ("OpenVTGrowingMonolayer", () -> OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24))),
    ("AkeebInvasion", () -> AkeebInvasion(; name = :akeeb, lattice = (60, 40))),
    ("OpenVTChain", () -> OpenVTChain(; name = :chain)),
    ("OpenVTReferenceMonolayer", () -> OpenVTReferenceMonolayer(; name = :ref, lattice = (24, 24))),
]

# ---------------------------------------------------------------------------------------
# A. Public name

@testset "P6.0bn A: public name with a docstring" begin
    @test isdefined(Potts, :ode_system) && Base.ispublic(Potts, :ode_system)
    @test isdefined(Potts, :ode_system) && Base.Docs.hasdoc(Potts, :ode_system)
    @test !Base.isexported(Potts, :ode_system)
end

# ---------------------------------------------------------------------------------------
# S. The ODE part is an MTK System compiled by mtkcompile

@testset "P6.0bn S: the cell template of the alias model" begin
    sys = P60bnAlias(; name = :alias)
    for cs in (mtkcompile(sys), mtkcompile(complete(sys)))
        s = p60bn_ode(cs, :cell)
        @test s isa P60BN_M.System
        @test P60BN_M.iscomplete(s) && p60bn_scheduled(s)
        @test p60bn_names(P60BN_M.unknowns(s)) == Set([:x])          # xalias eliminated
        @test :xalias in p60bn_observed_names(s)
        @test p60bn_names(P60BN_M.parameters(s)) == Set([:k])        # no inputs: k only
        eqs = P60BN_M.equations(s)
        @test length(eqs) == 1 && p60bn_name(only(Potts.SymbolicUtils.arguments(P60BN_S.unwrap(only(eqs).lhs)))) === :x
        @test p60bn_ode(cs, :model) === nothing
        # the compiled model lists xalias as observed, not as a state (MTK semantics)
        @test !(:xalias in p60bn_names(P60BN_M.unknowns(getfield(cs, :sys))))
        @test :x in p60bn_names(P60BN_M.unknowns(getfield(cs, :sys)))
    end
end

@testset "P6.0bn S: MTK solves the template itself (analytic oracle)" begin
    s = p60bn_ode(mtkcompile(P60bnAlias(; name = :alias)), :cell)
    x = p60bn_byname(P60BN_M.unknowns(s), :x)
    k = p60bn_byname(P60BN_M.parameters(s), :k)
    prob = P60BN_M.ODEProblem(s, [x => 2.0, k => 0.1], (0.0, 10.0))
    @test prob isa Potts.SciMLBase.ODEProblem
    @test only(prob.f(prob.u0, prob.p, 0.0)) ≈ -0.2                 # −k·xalias = −k·x
    sol = Potts.SciMLBase.solve(prob, Rodas5P(); abstol = 1e-12, reltol = 1e-12)
    @test isapprox(sol[x][end], 2.0 * exp(-1.0); rtol = 1e-8)
    xalias = only(o.lhs for o in P60BN_M.observed(s) if p60bn_name(o.lhs) === :xalias)
    @test p60bn_close(sol[xalias], sol[x])                           # the observed value is available
end

@testset "P6.0bn S: built-in, gather and model-scope templates" begin
    cs = mtkcompile(P60bnInputs(; name = :inp))
    s = p60bn_ode(cs, :cell)
    @test s isa P60BN_M.System && P60BN_M.iscomplete(s) && p60bn_scheduled(s)
    @test p60bn_names(P60BN_M.unknowns(s)) == Set([:y])
    @test issubset(Set([:w, :g, :h]), p60bn_observed_names(s))
    @test isempty(intersect(Set([:w, :g, :h]), p60bn_names(P60BN_M.unknowns(s))))
    @test length(P60BN_M.equations(s)) == 1
    @test p60bn_ode(cs, :model) === nothing

    cm = mtkcompile(P60bnModel(; name = :mod))
    s = p60bn_ode(cm, :model)
    @test s isa P60BN_M.System && P60BN_M.iscomplete(s) && p60bn_scheduled(s)
    @test p60bn_names(P60BN_M.unknowns(s)) == Set([:m])
    @test :gap in p60bn_observed_names(s)
    @test p60bn_names(P60BN_M.parameters(s)) == Set([:r])
    @test p60bn_ode(cm, :cell) === nothing
end

@testset "P6.0bn S: all-differential models have templates without observed variables" begin
    for (M, scope, n) in ((P60bnAliasHand, :cell, :x), (P60bnInputsHand, :cell, :y), (P60bnModelHand, :model, :m), (P60bnPair, :cell, :y))
        s = p60bn_ode(mtkcompile(M(; name = :h)), scope)
        @test s isa P60BN_M.System && p60bn_scheduled(s)
        @test p60bn_names(P60BN_M.unknowns(s)) == Set([n])       # a cross-cell `y[3 - id]` is an input
        @test isempty(P60BN_M.observed(s))
        @test length(P60BN_M.equations(s)) == 1
    end
    @test p60bn_names(P60BN_M.parameters(p60bn_ode(mtkcompile(P60bnAliasHand(; name = :h)), :cell))) == Set([:k])
end

@testset "P6.0bn S: scope and form errors" begin
    sys = P60bnAlias(; name = :alias)
    cs = mtkcompile(sys)
    for sc in (:site, :field, :edge, :nonsense)
        @test p60bn_clear(() -> Potts.ode_system(cs, sc), String(sc))
    end
    @test p60bn_clear(() -> Potts.ode_system(sys, :cell), "mtkcompile")
end

# ---------------------------------------------------------------------------------------
# E. Elimination in the run

@testset "P6.0bn E: alias model = its hand-substituted twin, and the oracles" begin
    op = p60bn_op(:x => P60BN_X0)
    for (alab, alg) in P60BN_ALGS, (slab, kw) in P60BN_SOLVERS
        @testset "$alab, $slab" begin
            sa = p60bn_solve(P60bnAlias, op, alg, kw)
            sh = p60bn_solve(P60bnAliasHand, op, alg, kw)
            @test sa.t == sh.t == collect(0:P60BN_N)
            xa = p60bn_cells(sa, :x)
            @test p60bn_close(xa, p60bn_cells(sh, :x))
            @test p60bn_close(p60bn_cells(sa, :acc), p60bn_cells(sh, :acc))
            @test p60bn_close(p60bn_series(sa, :xalias), p60bn_series(sa, :x))   # observed value
            if kw == (;)
                # exact discrete oracle of one explicit Euler step per MCS: x_N = x0·0.9^N
                @test p60bn_close(xa, [P60BN_X0 .* 0.9^N for N in 0:P60BN_N])
                # the update reads xalias = x before each step: acc_N = Σ_{j<N} x0·0.9^j
                @test p60bn_close(p60bn_cells(sa, :acc)[end], P60BN_X0 .* ((1 - 0.9^P60BN_N) / 0.1))
                # negative control: a wrong rate does not match
                @test !p60bn_close(xa, [P60BN_X0 .* 0.89^N for N in 0:P60BN_N]; rtol = 1e-6)
            else
                @test p60bn_close(xa, [P60BN_X0 .* exp(-0.1N) for N in 0:P60BN_N]; rtol = 1e-7)
                @test !p60bn_close(xa, [P60BN_X0 .* exp(-0.11N) for N in 0:P60BN_N]; rtol = 1e-7)
            end
        end
    end
end

@testset "P6.0bn E: algebraic chain over built-ins and a gather = its twin" begin
    op = p60bn_op()
    for (alab, alg) in P60BN_ALGS, (slab, kw) in P60BN_SOLVERS
        @testset "$alab, $slab" begin
            si = p60bn_solve(P60bnInputs, op, alg, kw)
            sh = p60bn_solve(P60bnInputsHand, op, alg, kw)
            @test [u.σ for u in si.u] == [u.σ for u in sh.u]                  # the same sweep
            @test p60bn_close(p60bn_cells(si, :y), p60bn_cells(sh, :y))
            vols = p60bn_volumes(si)
            @test p60bn_series(si, :w) == vols                                  # w ~ volume, counted
            # values have the declared shape: one per cell for a cell variable, even when the
            # definition reads no cell quantity (g reads a gather at a literal site)
            @test all(v -> length(v) == 2 && v[1] == v[2], p60bn_series(si, :g))
            @test p60bn_close(p60bn_series(si, :h), p60bn_series(si, :g) .- p60bn_series(si, :w))
            @test !all(v -> v == [16.0, 16.0], vols)                            # volumes do change
        end
    end
end

@testset "P6.0bn E: model scope = its twin, and the oracles" begin
    op = p60bn_op()
    for (alab, alg) in P60BN_ALGS, (slab, kw) in P60BN_SOLVERS
        @testset "$alab, $slab" begin
            sm = p60bn_solve(P60bnModel, op, alg, kw)
            sh = p60bn_solve(P60bnModelHand, op, alg, kw)
            m = Float64.(sm[:m])
            @test p60bn_close(m, Float64.(sh[:m]))
            @test p60bn_close(Float64.(sm[:gap]), 1 .- m)
            want = kw == (;) ? [1 - 0.8^N for N in 0:P60BN_N] : [1 - exp(-0.2N) for N in 0:P60BN_N]
            @test p60bn_close(m[2:end], want[2:end]; rtol = kw == (;) ? 1e-12 : 1e-7) && m[1] == 0.0
        end
    end
end

@testset "P6.0bn E: zero warm allocations (fixed-step solvers)" begin
    for (M, op) in ((P60bnAlias, p60bn_op(:x => P60BN_X0)), (P60bnInputs, p60bn_op()), (P60bnModel, p60bn_op())),
        (alab, alg) in P60BN_ALGS, (slab, kw) in P60BN_SOLVERS
        prob = PottsProblem(M(; name = :x), op, (0, 100); seed = 7, kw...)
        a = p60bn_warm_allocs(prob, alg)
        all(iszero, a) || @info "P6.0bn: $(nameof(M)) $alab $slab allocates $a"
        @test all(iszero, a)
    end
end

# ---------------------------------------------------------------------------------------
# U. Unchanged

# recorded on 4b81dd79 (the tree before this item), CPU, seed 7, 10 MCS: y after 10 MCS
const P60BN_RECORDED = Dict{Tuple{Symbol, String, String}, Vector{Float64}}(
    (:P60bnInputsHand, "SequentialCPM", "ExplicitEuler()") => [6.74381984037, 6.75316997648],
    (:P60bnInputsHand, "CheckerboardCPM", "ExplicitEuler()") => [4.73414836762, 4.71787373483],
    (:P60bnInputsHand, "SequentialCPM", "RK4(substeps = 4)") => [6.548518825367238, 6.557115366735856],
    (:P60bnInputsHand, "CheckerboardCPM", "RK4(substeps = 4)") => [4.617565307710102, 4.602331340036558],
    (:P60bnPair, "SequentialCPM", "ExplicitEuler()") => [1.5, 1.5],
    (:P60bnPair, "CheckerboardCPM", "ExplicitEuler()") => [1.5, 1.5],
    (:P60bnPair, "SequentialCPM", "RK4(substeps = 4)") => [1.4999999036073224, 1.5000000963926776],
    (:P60bnPair, "CheckerboardCPM", "RK4(substeps = 4)") => [1.4999999036073224, 1.5000000963926776],
)

@testset "P6.0bn U: all-differential cell ODEs keep their results" begin
    for (M, op) in ((P60bnInputsHand, p60bn_op()), (P60bnPair, p60bn_op(:y => [1.0, 2.0]))),
        (alab, alg) in P60BN_ALGS, (slab, kw) in P60BN_SOLVERS
        got = p60bn_cells(p60bn_solve(M, op, alg, kw), :y)[end]
        want = P60BN_RECORDED[(nameof(M), alab, slab)]
        p60bn_close(got, want) || @info "P6.0bn: $(nameof(M)) $alab $slab => $(repr(got))"
        @test p60bn_close(got, want)
    end
    # the explicit Euler oracle of the Jacobi pair: both cells reach the mean in one step
    @test P60BN_RECORDED[(:P60bnPair, "SequentialCPM", "ExplicitEuler()")] == [1.5, 1.5]
end

@testset "P6.0bn U: published models have no cell or model template" begin
    @testset "$label" for (label, build) in P60BN_PUBLISHED
        cs = mtkcompile(build())
        @test p60bn_ode(cs, :cell) === nothing
        @test p60bn_ode(cs, :model) === nothing
    end
end

# recorded on 4b81dd79: MerksVasculogenesis (8×8, one 3×3 cell), seed 11, 3 MCS, explicit
# Euler fields with two substeps (as in runtests.jl): the lattice bitwise, the field total to
# rtol 1e-12
const P60BN_MERKS_σ = Int32[0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 0, 1,
    0, 1, 1, 1, 1, 0, 1, 0, 0, 0, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0]
const P60BN_MERKS_CSUM = 0.2911437711992861

@testset "P6.0bn U: the published model with ODEs (Merks fields) runs as recorded" begin
    s = zeros(Int32, 8, 8)
    s[3:5, 3:5] .= 1
    prob = PottsProblem(MerksVasculogenesis(; name = :merks, lattice = (8, 8)), [ownership => s, kind => [:endothelial]], (0, 3);
        seed = 11, field_solver = ExplicitEuler(substeps = 2, lower = 0.0))
    u = solve(prob, SequentialCPM()).u[end]
    @test vec(Array(u.σ)) == P60BN_MERKS_σ
    # the sum's SIMD association differs between CPUs (Mac 0.2911437711992861, PC …860)
    @test isapprox(sum(Float64.(Array(u.site.c))), P60BN_MERKS_CSUM; rtol = 1e-12)
end

# ---------------------------------------------------------------------------------------
# R. Rejections

@testset "P6.0bn R: rejected algebraic equations" begin
    @test p60bn_clear(() -> mtkcompile(P60bnImplicit(; name = :r)), "algebraic")
    @test p60bn_clear(() -> mtkcompile(P60bnFieldAlg(; name = :r)), "algebraic", "cfield")
    @test p60bn_clear(() -> mtkcompile(P60bnBoth(; name = :r)), "algebraic", "xalias")
    @test p60bn_clear(() -> mtkcompile(P60bnTwice(; name = :r)), "algebraic", "xalias")
    @test p60bn_clear(() -> mtkcompile(P60bnSelf(; name = :r)), "algebraic", "xalias")
    @test p60bn_clear(() -> mtkcompile(P60bnCycle(; name = :r)), "algebraic")
    @test p60bn_clear(() -> mtkcompile(P60bnWrite(; name = :r)), "algebraic", "xalias")
end

@testset "P6.0bn R: no initial value for an algebraic variable" begin
    @test p60bn_clear(() -> PottsProblem(P60bnAlias(; name = :x), p60bn_op(:x => P60BN_X0, :xalias => [1.0, 1.0]), (0, 1)),
        "xalias")
end

# ---------------------------------------------------------------------------------------
# N. Negative controls for the detectors

@testset "P6.0bn N: complete keeps the alias, mtkcompile eliminates it" begin
    plain = p60bn_plain()
    c = complete(plain)
    @test P60BN_M.iscomplete(c) && !p60bn_scheduled(c)
    @test :xa in p60bn_names(P60BN_M.unknowns(c)) && !(:xa in p60bn_observed_names(c))
    s = P60BN_M.mtkcompile(plain)
    @test P60BN_M.iscomplete(s) && p60bn_scheduled(s)
    @test p60bn_names(P60BN_M.unknowns(s)) == Set([:xs]) && :xa in p60bn_observed_names(s)
end
