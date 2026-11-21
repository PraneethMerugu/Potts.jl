# Sources: D-159, D-162; research/mtk-native-plan.md §4 route A2, §5, §6.
# a model's own cell- and model-scope ODEs go through ModelingToolkit's
# `mtkcompile` before Potts lowers them. Potts builds one MTK `System` per scope from the
# `@equations` of that scope (the per-cell template: one cell's equations, compiled once,
# advanced for every cell by Potts' batched kernel as before), lets MTK's structural
# simplification eliminate the algebraic (observed) variables, and lowers the simplified
# equations. This makes plan §5's sentence true for ODEs: "The continuous ... parts of a
# model are ModelingToolkit systems compiled by `mtkcompile`". Fields (lattice PDEs) are not
# in this item; they stay Potts' `FieldStep`.
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
#     `@equations`, or `nothing` when the scope has none. It is complete and scheduled
#     (MTK's own mark of an `mtkcompile` result). Its unknowns are the scope's differential
#     variables (by declared name), each algebraic variable is an `observed` equation and
#     not an unknown, and each declared parameter the equations read is a parameter under
#     its declared name. Other quantities the ODEs read (built-ins such as `volume`, other
#     scopes' variables, gathers, population folds, cross-cell reads `y[3 - id]`) are
#     inputs: further parameters, names not pinned. A template with no inputs is an ordinary
#     MTK system: MTK's own `ODEProblem` solves it (oracle: the analytic solution). Other
#     scopes (`:site`, `:field`, anything else) are an `ArgumentError`, and so is a
#     `PottsSystem` that has not been through `mtkcompile` (the message names `mtkcompile`).
#  E. Elimination shows up in the run: a model with `D(x) ~ -k*xalias; xalias ~ x` runs
#     exactly like its hand-substituted twin `D(x) ~ -k*x` (same seed, every save, rtol
#     1e-12: D-158's tolerance for values that pass through upstream code; MTK's symbolic
#     pass is upstream), matches the exact discrete oracle of explicit Euler (x0·0.9^N) and
#     the analytic one under RK4 (x0·e^(−0.1N), rtol 1e-7), and `sol[:xalias] ≈ sol[:x]`. An
#     `@after_mcs` update reading `xalias` reads `x` (oracle: Σ x0·0.9^j). The same for a
#     chain of algebraic variables that read built-ins and a neighbour gather
#     (`gather_ode_allocations_tests.jl`'s shape: `w ~ volume`, `g ~ sum(volume[owner[n]]
#     for n in Moore(1)(42))`, `h ~ g − w`, written out of order), with `sol[:w]` equal to
#     the cell volumes counted on the saved lattice and `sol[:g]` one value per cell (an
#     algebraic variable's values have its declared shape), and for a model-scope pair `D(m)
#     ~ r*gap; gap ~ 1 − m` (oracles 1 − 0.8^N and 1 − e^(−0.2N)). Zero warm allocations per
#     `step!` (the fixed-step gate) for these models.
#  U. Unchanged: models whose `@equations` are all differential keep their results (recorded
#     on 4b81dd79, the tree before this item: a gather rate and a cross-cell rate, both CPM
#     algorithms, explicit Euler and RK4; rtol 1e-12) and have no observed variables in
#     their template. Every published model has no cell or model ODE, so both its templates
#     are `nothing`; the published model with ODEs (Merks, field PDEs) runs bitwise as
#     recorded on 4b81dd79 (our own field step, D-158). Generated code and fingerprints of
#     all-differential models are pinned byte-identical by `abstract_system_tests.jl` (D-137
#     rule 7), not here.
#  R. Rejections, at `mtkcompile` (`PottsCompileError`; the words listed must appear): an
#     implicit equation (`xalias + x ~ 1`: "algebraic"); an algebraic equation for a field
#     ("algebraic", the name); a variable with both `D(·)` and an algebraic equation, two
#     algebraic equations for one variable, a self-reference, and a cycle through two
#     equations ("algebraic", the name where there is one); an update writing an algebraic
#     variable ("algebraic", the name). Whether ModelingToolkit (full, with tearing) is
#     loaded must not change what is accepted. An operating-point value for an algebraic
#     variable is an ArgumentError naming it.
#  N. Negative controls: a plain MTK `System` with the same alias keeps `xalias` as an
#     unknown under `complete` and is not scheduled (the detector used in S can fail), and
#     loses it under `mtkcompile` (the detector can pass); an oracle with a wrong rate does
#     not match the run.
#
# On 4b81dd79 every A/S/E target errors (`Potts.ode_system` is undefined, and every fixture
# with an algebraic equation is rejected by `mtkcompile`), R fails on the missing word
# "algebraic", and the U pins, the N controls and the operating-point rejection pass.

@testsetup module ODEMTKCompileSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
include(joinpath(@__DIR__, "..", "fixtures.jl"))
using Potts: CorePotts
using OrdinaryDiffEqRosenbrock: Rodas5P
const ODE_M = Potts.ModelingToolkitBase
const ODE_S = Potts.Symbolics
const SII = Potts.SymbolicIndexingInterface
ode_name(x) = SII.getname(x)
ode_names(xs) = Set{Symbol}(ode_name(x) for x in xs)
ode(c, scope) = Potts.ode_system(c, scope)
# MTK's mark of an `mtkcompile` result (`complete` alone does not set it)
scheduled(s) = ODE_M.isscheduled(s)
observed_names(s) = Set{Symbol}(ode_name(o.lhs) for o in ODE_M.observed(s))
byname(xs, n) = only(x for x in xs if ode_name(x) === n)
clear(f, words...) = clear(ArgumentError, f, words...)
function clear(E::Type{<:Exception}, f, words...)
    return try
        f()
        false
    catch err
        ok = err isa E && (isempty(words) || occursin(first(words), sprint(showerror, err)))
        ok || @info "expected $(nameof(E))" exception = err
        ok
    end
end
# ---------------------------------------------------------------------------------------
# Fixtures: two 4×4 cells side by side (x = 3:6 and 7:10, y = 3:6) on a 12×8 lattice, as in
# `gather_ode_allocations_tests.jl`. Site 42 is (6, 4), on their interface. No energy reads
# an ODE variable, so a model and its twin see the same sweep for the same seed.

# E: an alias of the differential variable, read by the ODE and by an update
@potts_model Alias begin
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
@potts_model AliasHand begin
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
@potts_model Inputs begin
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
@potts_model InputsHand begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.01 * (sum(volume[owner[n]] for n in Moore(1)(42)) - volume) - 0.1y
    @sweep Metropolis(; temperature = 1.0)
end
# E: model scope
@potts_model Model begin
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
@potts_model ModelHand begin
    @kinds medium A
    @parameters r = 0.2
    @variables m(model) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(m) ~ r * (1 - m)
    @sweep Metropolis(; temperature = 1.0)
end
# U: a cross-cell read of the template's own unknown (`cell_ode_jacobi_tests.jl`'s Jacobi
# path)
@potts_model OdePair begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.5 * (y[3 - id] - y)
    @sweep Metropolis(; temperature = 1.0)
end
# R: rejected models (built in the testsets; the macro accepts them, `mtkcompile` decides)
@potts_model Implicit begin
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
# an aux field `cfield ~ 1.0`, a plain MTK PDESystem coupled with `@fields`
function aux_pde()
    t, L = Potts.t, Potts.LatticePDE
    Potts.ModelingToolkitBase.@parameters x y
    Potts.ModelingToolkitBase.@variables cfield(..)
    C = cfield(t, x, y)
    return Potts.ModelingToolkitBase.PDESystem(
        [C ~ 1.0], [cfield(0, x, y) ~ 0.0], L.lattice_domain(t, (x, y), (12, 8)),
        [t, x, y], [C], Any[]; name = :aux
    )
end
@potts_model FieldAlg begin
    @kinds medium A
    @lattice Lattice((12, 8))
    @fields aux_pde()
    @energy cells => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model Both begin
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
@potts_model Twice begin
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
@potts_model Self begin
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
@potts_model OdeCycle begin
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
@potts_model Write begin
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
sigma() = (s = zeros(Int32, 12, 8); s[3:6, 3:6] .= 1; s[7:10, 3:6] .= 2; s)
ode_op(extra...) = Any[ownership => sigma(), kind => [:A, :A], extra...]
const ODE_X0 = [2.0, 3.0]
const ODE_N = 10
# MCS per run
const ALGS = (
    ("SequentialCPM", SequentialCPM(; proposal = Moore(1))),
    ("CheckerboardCPM", CheckerboardCPM(; proposal = Moore(1))),
)
const SOLVERS = (
    ("ExplicitEuler()", (;)),
    ("RK4(substeps = 4)", (; ode_solver = Potts.RK4(substeps = 4))),
)
function ode_solve(M, op, alg, kw)
    return solve(
        PottsProblem(M(; name = :x), op, (0, ODE_N); seed = 7, kw...), alg; saveat = 1
    )
end
ode_cells(sol, n) = [Vector{Float64}(Array(getproperty(u.cell, n))) for u in sol.u]
ode_series(sol, n) = [Vector{Float64}(Array(v)) for v in sol[n]]
ode_volumes(sol) = [[Float64(count(==(c), u.ownership)) for c in 1:2] for u in sol.u]
function ode_close(a, b; rtol = 1.0e-12)
    return length(a) == length(b) &&
        all(i -> isapprox(a[i], b[i]; rtol), eachindex(a, b))
end
"""Bytes allocated by each of five warm `step!`s (after two warm-up steps)."""
function warm_allocs(prob, alg)
    integ = init(prob, alg; save_start = false, save_end = false, save_everystep = false)
    step!(integ)
    step!(integ)
    out = Int[]
    for _ in 1:5
        push!(out, @allocated step!(integ))
    end
    return out
end
# the alias as a plain MTK system (negative controls)
function ode_plain()
    t = Potts.t
    ODE_M.@variables xs(t) = 2.0 xa(t)
    ODE_M.@parameters ks = 0.1
    return ODE_M.System([Potts.D(xs) ~ -ks * xa, xa ~ xs], t; name = :plain)
end
# every published model (small lattices; construction and `mtkcompile` only)
const MODELS = [
    ("GranerGlazier", () -> GranerGlazier(; name = :gg)),
    ("WortelAct", () -> WortelAct(; name = :act, lattice = (8, 8))),
    (
        "WortelAct connected",
        () -> WortelAct(; name = :act, lattice = (8, 8), connected = true),
    ),
    ("MerksVasculogenesis", () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8))),
    (
        "MerksVasculogenesis contact-inhibited",
        () -> MerksVasculogenesis(;
            name = :merks, lattice = (8, 8),
            contact_inhibited = true
        ),
    ),
    ("Merks2006", () -> Merks2006(; name = :m6, lattice = (16, 16))),
    ("Merks2006 hard", () -> Merks2006(; name = :m6, lattice = (16, 16), rule = :hard)),
    ("Merks2008", () -> Merks2008(; name = :m8, lattice = (16, 16))),
    (
        "Merks2008 extension only",
        () -> Merks2008(; name = :m8, lattice = (16, 16), mode = :extension_only),
    ),
    ("SingleDivisionFixture", () -> SingleDivisionFixture(; name = :fixture)),
    (
        "OpenVTGrowingMonolayer",
        () -> OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)),
    ),
    ("AkeebInvasion", () -> AkeebInvasion(; name = :akeeb, lattice = (60, 40))),
    ("OpenVTChain", () -> OpenVTChain(; name = :chain)),
    (
        "OpenVTReferenceMonolayer",
        () -> OpenVTReferenceMonolayer(; name = :ref, lattice = (24, 24)),
    ),
]
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "ode mtkcompile A: public name with a docstring" setup = [
    ODEMTKCompileSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # A. Public name
    @testset "ode mtkcompile A: public name with a docstring" begin
        @test isdefined(Potts, :ode_system) && Base.ispublic(Potts, :ode_system)
        @test isdefined(Potts, :ode_system) && Base.Docs.hasdoc(Potts, :ode_system)
        @test !Base.isexported(Potts, :ode_system)
    end
end

@testitem "ode mtkcompile S: the cell template of the alias model" setup = [
    ODEMTKCompileSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # S. The ODE part is an MTK System compiled by mtkcompile
    @testset "ode mtkcompile S: the cell template of the alias model" begin
        sys = Alias(; name = :alias)
        for cs in (mtkcompile(sys),)
            s = ode(cs, :cell)
            @test s isa ODE_M.System
            @test ODE_M.iscomplete(s) && scheduled(s)
            @test ode_names(ODE_M.unknowns(s)) == Set([:x])          # xalias eliminated
            @test :xalias in observed_names(s)
            @test ode_names(ODE_M.parameters(s)) == Set([:k])        # no inputs: k only
            eqs = ODE_M.equations(s)
            @test length(eqs) == 1 &&
                ode_name(
                only(Potts.SymbolicUtils.arguments(ODE_S.unwrap(only(eqs).lhs)))
            ) ===
                :x
            @test ode(cs, :model) === nothing
            # the compiled model lists xalias as observed, not as a state (MTK semantics)
            @test !(:xalias in ode_names(ODE_M.unknowns(getfield(cs, :sys))))
            @test :x in ode_names(ODE_M.unknowns(getfield(cs, :sys)))
        end
    end
end

@testitem "ode mtkcompile S: MTK solves the template itself (analytic oracle)" setup = [
    ODEMTKCompileSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "ode mtkcompile S: MTK solves the template itself (analytic oracle)" begin
        s = ode(mtkcompile(Alias(; name = :alias)), :cell)
        x = byname(ODE_M.unknowns(s), :x)
        k = byname(ODE_M.parameters(s), :k)
        prob = ODE_M.ODEProblem(s, [x => 2.0, k => 0.1], (0.0, 10.0))
        @test prob isa Potts.SciMLBase.ODEProblem
        @test only(prob.f(prob.u0, prob.p, 0.0)) ≈ -0.2                 # −k·xalias = −k·x
        sol = Potts.SciMLBase.solve(prob, Rodas5P(); abstol = 1.0e-12, reltol = 1.0e-12)
        @test isapprox(sol[x][end], 2.0 * exp(-1.0); rtol = 1.0e-8)
        xalias = only(o.lhs for o in ODE_M.observed(s) if ode_name(o.lhs) === :xalias)
        # the observed value is available
        @test ode_close(sol[xalias], sol[x])
    end
end

@testitem "ode mtkcompile S: built-in, gather and model-scope templates" setup = [
    ODEMTKCompileSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "ode mtkcompile S: built-in, gather and model-scope templates" begin
        cs = mtkcompile(Inputs(; name = :inp))
        s = ode(cs, :cell)
        @test s isa ODE_M.System && ODE_M.iscomplete(s) && scheduled(s)
        @test ode_names(ODE_M.unknowns(s)) == Set([:y])
        @test issubset(Set([:w, :g, :h]), observed_names(s))
        @test isempty(intersect(Set([:w, :g, :h]), ode_names(ODE_M.unknowns(s))))
        @test length(ODE_M.equations(s)) == 1
        @test ode(cs, :model) === nothing

        cm = mtkcompile(Model(; name = :mod))
        s = ode(cm, :model)
        @test s isa ODE_M.System && ODE_M.iscomplete(s) && scheduled(s)
        @test ode_names(ODE_M.unknowns(s)) == Set([:m])
        @test :gap in observed_names(s)
        @test ode_names(ODE_M.parameters(s)) == Set([:r])
        @test ode(cm, :cell) === nothing
    end
end

@testitem "ode mtkcompile S: all-differential models have templates without observed \
    variables" setup = [ODEMTKCompileSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "ode mtkcompile S: all-differential models have templates without observed \
        variables" begin
        for (M, scope, n) in (
                (AliasHand, :cell, :x), (InputsHand, :cell, :y),
                (ModelHand, :model, :m), (OdePair, :cell, :y),
            )
            s = ode(mtkcompile(M(; name = :h)), scope)
            @test s isa ODE_M.System && scheduled(s)
            # a cross-cell `y[3 - id]` is an input
            @test ode_names(ODE_M.unknowns(s)) == Set([n])
            @test isempty(ODE_M.observed(s))
            @test length(ODE_M.equations(s)) == 1
        end
        @test ode_names(ODE_M.parameters(ode(mtkcompile(AliasHand(; name = :h)), :cell))) ==
            Set([:k])
    end
end

@testitem "ode mtkcompile S: scope and form errors" setup = [ODEMTKCompileSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "ode mtkcompile S: scope and form errors" begin
        sys = Alias(; name = :alias)
        cs = mtkcompile(sys)
        for sc in (:site, :field, :edge, :nonsense)
            @test clear(() -> Potts.ode_system(cs, sc), String(sc))
        end
        @test clear(() -> Potts.ode_system(sys, :cell), "mtkcompile")
    end
end

@testitem "ode mtkcompile E: alias model = its hand-substituted twin, and the \
    oracles" setup = [ODEMTKCompileSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # E. Elimination in the run
    @testset "ode mtkcompile E: alias model = its hand-substituted twin, and the \
        oracles" begin
        op = ode_op(:x => ODE_X0)
        for (alab, alg) in ALGS, (slab, kw) in SOLVERS
            @testset "$alab, $slab" begin
                sa = ode_solve(Alias, op, alg, kw)
                sh = ode_solve(AliasHand, op, alg, kw)
                @test sa.t == sh.t == collect(0:ODE_N)
                xa = ode_cells(sa, :x)
                @test ode_close(xa, ode_cells(sh, :x))
                @test ode_close(ode_cells(sa, :acc), ode_cells(sh, :acc))
                # observed value
                @test ode_close(ode_series(sa, :xalias), ode_series(sa, :x))
                if kw == (;)
                    # exact discrete oracle of one explicit Euler step per MCS: x_N =
                    # x0·0.9^N
                    @test ode_close(xa, [ODE_X0 .* 0.9^N for N in 0:ODE_N])
                    # the update reads xalias = x before each step: acc_N = Σ_{j<N} x0·0.9^j
                    @test ode_close(
                        ode_cells(sa, :acc)[end], ODE_X0 .*
                            ((1 - 0.9^ODE_N) / 0.1)
                    )
                    # negative control: a wrong rate does not match
                    @test !ode_close(xa, [ODE_X0 .* 0.89^N for N in 0:ODE_N]; rtol = 1.0e-6)
                else
                    @test ode_close(
                        xa, [ODE_X0 .* exp(-0.1N) for N in 0:ODE_N];
                        rtol = 1.0e-7
                    )
                    @test !ode_close(
                        xa, [ODE_X0 .* exp(-0.11N) for N in 0:ODE_N];
                        rtol = 1.0e-7
                    )
                end
            end
        end
    end
end

@testitem "ode mtkcompile E: algebraic chain over built-ins and a gather = its twin" setup =
    [ODEMTKCompileSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "ode mtkcompile E: algebraic chain over built-ins and a gather = its \
        twin" begin
        op = ode_op()
        for (alab, alg) in ALGS, (slab, kw) in SOLVERS
            @testset "$alab, $slab" begin
                si = ode_solve(Inputs, op, alg, kw)
                sh = ode_solve(InputsHand, op, alg, kw)
                # the same sweep
                @test [u.ownership for u in si.u] == [u.ownership for u in sh.u]
                @test ode_close(ode_cells(si, :y), ode_cells(sh, :y))
                vols = ode_volumes(si)
                # w ~ volume, counted
                @test ode_series(si, :w) == vols
                # values have the declared shape: one per cell for a cell variable, even
                # when the definition reads no cell quantity (g reads a gather at a literal
                # site)
                @test all(v -> length(v) == 2 && v[1] == v[2], ode_series(si, :g))
                @test ode_close(
                    ode_series(si, :h), ode_series(si, :g) .-
                        ode_series(si, :w)
                )
                # volumes do change
                @test !all(v -> v == [16.0, 16.0], vols)
            end
        end
    end
end

@testitem "ode mtkcompile E: model scope = its twin, and the oracles" setup = [
    ODEMTKCompileSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "ode mtkcompile E: model scope = its twin, and the oracles" begin
        op = ode_op()
        for (alab, alg) in ALGS, (slab, kw) in SOLVERS
            @testset "$alab, $slab" begin
                sm = ode_solve(Model, op, alg, kw)
                sh = ode_solve(ModelHand, op, alg, kw)
                m = Float64.(sm[:m])
                @test ode_close(m, Float64.(sh[:m]))
                @test ode_close(Float64.(sm[:gap]), 1 .- m)
                want = if kw == (;)
                    [1 - 0.8^N for N in 0:ODE_N]
                else
                    [1 - exp(-0.2N) for N in 0:ODE_N]
                end
                @test ode_close(
                    m[2:end], want[2:end]; rtol = kw == (;) ? 1.0e-12 :
                        1.0e-7
                ) && m[1] == 0.0
            end
        end
    end
end

@testitem "ode mtkcompile E: zero warm allocations (fixed-step solvers)" setup = [
    ODEMTKCompileSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "ode mtkcompile E: zero warm allocations (fixed-step solvers)" begin
        for (M, op) in (
                    (Alias, ode_op(:x => ODE_X0)), (Inputs, ode_op()), (
                        Model, ode_op(),
                    ),
                ),
                (alab, alg) in ALGS, (slab, kw) in SOLVERS
            prob = PottsProblem(M(; name = :x), op, (0, 100); seed = 7, kw...)
            a = warm_allocs(prob, alg)
            all(iszero, a) || @info "ode mtkcompile: $(nameof(M)) $alab $slab allocates $a"
            @test all(iszero, a)
        end
    end
end

@testitem "ode mtkcompile U: the Jacobi pair reaches the mean" setup = [
    ODEMTKCompileSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # U. The Jacobi pair
    @testset "ode mtkcompile U: the Jacobi pair reaches the mean" begin
        # hand oracle: two all-differential cells of y = (1, 2) exchange until both are the
        # mean
        for (_, alg) in ALGS
            got = ode_cells(ode_solve(OdePair, ode_op(:y => [1.0, 2.0]), alg, (;)), :y)
            @test ode_close(got[end], [1.5, 1.5])
        end
    end
end

@testitem "ode mtkcompile U: published models have no cell or model template" setup = [
    ODEMTKCompileSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "ode mtkcompile U: published models have no cell or model template" begin
        @testset "$label" for (label, build) in MODELS
            cs = mtkcompile(build())
            @test ode(cs, :cell) === nothing
            @test ode(cs, :model) === nothing
        end
    end
end

@testitem "ode mtkcompile R: rejected algebraic equations" setup = [
    ODEMTKCompileSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # R. Rejections
    @testset "ode mtkcompile R: rejected algebraic equations" begin
        @test clear(
            Potts.PottsCompileError, () -> mtkcompile(Implicit(; name = :r)),
            "algebraic"
        )
        # an aux-only field model builds (the auxiliary-field ruling): its field phase
        # evaluates `cfield ~ 1.0`
        let s = zeros(Int32, 12, 8)
            s[3:6, 3:6] .= 1
            u = solve(
                PottsProblem(
                    FieldAlg(; name = :r), [ownership => s, kind => [:A]], (0, 1);
                    seed = 1
                ),
                SequentialCPM()
            ).u[end]
            @test all(==(1.0), Array(u.site.cfield))
        end
        @test clear(
            Potts.PottsCompileError, () -> mtkcompile(Both(; name = :r)),
            "algebraic", "xalias"
        )
        @test clear(
            Potts.PottsCompileError, () -> mtkcompile(Twice(; name = :r)),
            "algebraic", "xalias"
        )
        @test clear(
            Potts.PottsCompileError, () -> mtkcompile(Self(; name = :r)),
            "algebraic", "xalias"
        )
        @test clear(
            Potts.PottsCompileError, () -> mtkcompile(OdeCycle(; name = :r)),
            "algebraic"
        )
        @test clear(
            Potts.PottsCompileError, () -> mtkcompile(Write(; name = :r)),
            "algebraic", "xalias"
        )
    end
end

@testitem "ode mtkcompile R: no initial value for an algebraic variable" setup = [
    ODEMTKCompileSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "ode mtkcompile R: no initial value for an algebraic variable" begin
        @test clear(
            () -> PottsProblem(
                Alias(; name = :x), ode_op(
                    :x => ODE_X0, :xalias =>
                        [1.0, 1.0]
                ), (0, 1)
            ),
            "xalias"
        )
    end
end

@testitem "ode mtkcompile N: complete keeps the alias, mtkcompile eliminates it" setup = [
    ODEMTKCompileSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # N. Negative controls for the detectors
    @testset "ode mtkcompile N: complete keeps the alias, mtkcompile eliminates it" begin
        plain = ode_plain()
        c = ODE_M.complete(plain)
        @test ODE_M.iscomplete(c) && !scheduled(c)
        @test :xa in ode_names(ODE_M.unknowns(c)) && !(:xa in observed_names(c))
        s = ODE_M.mtkcompile(plain)
        @test ODE_M.iscomplete(s) && scheduled(s)
        @test ode_names(ODE_M.unknowns(s)) == Set([:xs]) && :xa in observed_names(s)
    end
end
