# Sources: D-159, D-165; research/mtk-native-plan.md §4 route A1, §5, §6.
# initialization equations that touch one cell (or the model) go through
# ModelingToolkit's initialization engine. Potts builds one MTK `System` per scope (cell,
# model) carrying that scope's `@initialization_equations` as MTK `initialization_eqs` (the
# per-cell template, as `ode_mtkcompile_tests.jl`'s ODE template), builds MTK's `InitializationProblem` from it
# when a problem is constructed, and solves it once per cell on the host, before the first
# MCS. The batched kernels are unchanged. This makes plan §5's "initialization ... parts of a
# model are ModelingToolkit systems" true for entity-local initialization. Cross-entity and
# lattice initialization (reads of other cells, gathers, folds, site and field variables)
# stay Potts' (R17, later work); until then they are refused.
#
# What is new for users:
#  - a `@potts_model` section `@initialization_equations` (MTK's `initialization_eqs`):
#    equations `lhs ~ rhs`, explicit or implicit, linear or nonlinear, between the cell's own
#    variables (read bare), its built-ins (`volume`, `id`), parameters, model variables, and
#    `D(x)` of a cell or model ODE variable `x` (its rate at the start: `D(x) ~ 0` is a
#    steady start);
#  - a guess for a variable that initialization solves for, written as MTK variable metadata:
#    `r(cell), [guess = -1.0]` (no value). It seeds the nonlinear solve and picks the root;
#  - an operating-point value for an algebraic variable (`ode_mtkcompile_tests.jl`'s `y ~ expr`) is now an
#    initial condition, `y ~ value`, as in MTK, which supersedes D-165's refusal. Its
#    definition's variables are then solved for.
#
# The contract pinned here (public API and run results only; how the template is built,
# whether non-ODE cell variables enter it as unknowns with `D(v) ~ 0` or otherwise, which
# nonlinear solver runs, whether the problem is built once and re-parameterized per cell, and
# where each rejection is raised — `@potts_model`, `mtkcompile` or `PottsProblem` — are the
# implementer's):
#  A. `Potts.initialization_system` is a public (not exported) name of Potts with a docstring.
#  S. `Potts.initialization_system(csys::CompiledPottsSystem, scope)` for `scope` in `:cell`,
#     `:model` returns a complete `ModelingToolkitBase.System` whose
#     `ModelingToolkitBase.initialization_equations` are that scope's `@initialization_equations`
#     (one per authored equation), or `nothing` when the scope has none (an operating-point
#     condition alone builds no template: it is per problem). Its unknowns include each
#     variable of the scope the equations name, under its declared name, with no initial value
#     when initialization solves for it (a fixed value would overdetermine it); each declared
#     parameter the equations read is a parameter under its declared name; a declared guess is
#     the template's guess for that variable (`ModelingToolkitBase.guesses` or the variable's
#     guess metadata). Other quantities (built-ins, model variables in a cell template) are
#     inputs, names not pinned. A template with no inputs is an ordinary MTK system: MTK's own
#     `InitializationProblem` solves it (oracle: the hand-solved value). Other scopes are an
#     ArgumentError naming the scope, and so is a `PottsSystem` that has not been through
#     `mtkcompile` (the message names `mtkcompile`).
#  I. Per-cell results (u0 of the problem, before any MCS) equal hand-solved values on two
#     cells of different volume (16 and 12 sites, ids 1 and 2), for: an explicit equation over
#     built-ins and a fixed variable (`Vt ~ 2volume + id + w`, also with `w` from the
#     operating point); a nonlinear equation whose root is chosen by the declared guess
#     (`r^2 ~ volume`: −√V with guess −1, +√V with guess +1; rtol 1e-9, the nonlinear
#     solver's tolerance); a coupled implicit pair (`a + b ~ volume; a − b ~ id`); a steady
#     start of a cell ODE (`D(xs) ~ 0` with `D(xs) ~ α·volume − κ·xs`: xs = α·volume/κ); a
#     model-scope equation read by a cell-scope one (`m ~ 3r0; z ~ m + volume`: the model is
#     initialized first); and an algebraic variable's operating-point value (`xd ~ 2x`,
#     `xd => [1, 3]` gives x = [0.5, 1.5]; the run then matches x0·0.8^N exactly under
#     explicit Euler, and `sol[:xd] = 2·sol[:x]`). Explicit and linear values at rtol 1e-12
#     (D-158: MTK's symbolic pass and solve are upstream). Initialization runs at problem
#     construction and again on `remake(prob; u0 = map)`; `remake(prob; u0 = state)` (a saved
#     state) keeps the state's values. Zero warm allocations per `step!` afterwards.
#  V. Values, MTK semantics made strict (`fully_determined`): a written value (`x(cell) = v`,
#     including `= 0.0`) or an operating-point value fixes a variable; a variable declared
#     without a value is solved for when the scope's initialization conditions name it, and
#     otherwise starts at 0.0 as before. Rejections (ArgumentError, the listed words appear):
#     a fixed variable that an equation also determines ("overdetermined" and its name: from
#     a written value, a written zero, or the operating point); an algebraic variable's value
#     whose definition reads only fixed variables ("overdetermined", its name: this keeps
#     `ode_mtkcompile_tests.jl`'s frozen R check, `x => [2, 3], xalias => [1, 1]`, an error naming `xalias`); too
#     few equations ("underdetermined" and a name of a free variable); an equation with no
#     solution (`rootless^2 ~ -volume`: "initialization" and the name).
#  X. Cross-entity equations are not given to MTK; until later work they are an ArgumentError
#     ("initialization" and the name read across entities, or the equation's variable): a read
#     of another cell's variable (`xr ~ partner[3 - id]`), a neighbour gather at a site, and a
#     field variable.
#  U. Unchanged: a model without `@initialization_equations` has no templates and starts from
#     its declared values; every published model has no template in either scope (their code
#     and fingerprints are pinned byte-identical by `abstract_system_tests.jl`, D-137 rule 7, not here). The F7
#     rejection of a component's own `initialization_eqs` is unchanged (checked in `component_rejections_tests.jl`).
#  N. Negative controls: a plain MTK `System` without `initialization_eqs` lists none (the S
#     detector can fail); wrong hand values (the other root, a wrong coefficient) do not match;
#     the rejection detector refuses a call that does not throw and a message without the word.
#
# On 2bcc4b75 (the tree before this item) every fixture that uses `@initialization_equations`
# or a guess without a value fails to define (an undefined macro, or "variables are declared
# with a scope"); the definitions are captured, so every A/S/I/V/X target fails or errors in
# its testset and the U and N checks pass.

@testsetup module InitializationSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
include(joinpath(@__DIR__, "..", "fixtures.jl"))
using Potts: CorePotts
const INITIALIZATION_M = Potts.ModelingToolkitBase
const SII = Potts.SymbolicIndexingInterface
initialization_name(x) = SII.getname(x)
initialization_names(xs) = Set{Symbol}(initialization_name(x) for x in xs)
byname(xs, n) = only(x for x in xs if initialization_name(x) === n)
initialization_init(c, scope) = Potts.initialization_system(c, scope)
unwrap_load_error(err) = err isa LoadError ? unwrap_load_error(err.error) : err
function clear(E::Type{<:Exception}, f, word = nothing)
    return try
        f()
        false
    catch err
        e = unwrap_load_error(err)
        ok = e isa E && (word === nothing || occursin(word, sprint(showerror, e)))
        ok || @info "expected $E$(word === nothing ? "" : " naming $word")" exception = e
        ok
    end
end
clear(f, word = nothing) = clear(ArgumentError, f, word)
# Fixtures are defined by evaluating their `@potts_model` here and capturing any error, so
# that a tree without the section fails in the testsets and not when this file loads.
const DEFINED = Dict{Symbol, Any}()
function define(name::Symbol, ex)
    DEFINED[name] = try
        Core.eval(@__MODULE__, ex)
        nothing
    catch err
        unwrap_load_error(err)
    end
    return nothing
end
function initialization_build(name::Symbol; kw...)
    err = DEFINED[name]
    err === nothing || throw(err)
    return Base.invokelatest(getfield(@__MODULE__, name); name = :x, kw...)
end
# ---------------------------------------------------------------------------------------
# Fixtures: two cells on a 12×8 lattice, cell 1 at x = 3:6, y = 3:6 (16 sites) and cell 2 at
# x = 7:10, y = 3:5 (12 sites). No energy reads an initialized variable.

# I: explicit, over built-ins and a fixed variable (w is written as 0.0: fixed)
define(
    :Target, quote
        @potts_model Target begin
            @kinds medium A
            @variables begin
                Vt(cell)
                w(cell) = 0.0
            end
            @lattice Lattice((12, 8))
            @energy cells => (volume - 14.0)^2
            @initialization_equations Vt ~ 2volume + id + w
            @sweep Metropolis(; temperature = 4.0)
        end
    end
)
# I: nonlinear, the root picked by the guess
define(
    :RootNeg, quote
        @potts_model RootNeg begin
            @kinds medium A
            @variables begin
                r(cell), [guess = -1.0]
            end
            @lattice Lattice((12, 8))
            @energy cells => (volume - 14.0)^2
            @initialization_equations r^2 ~ volume
            @sweep Metropolis(; temperature = 1.0)
        end
    end
)
define(
    :RootPos, quote
        @potts_model RootPos begin
            @kinds medium A
            @variables begin
                r(cell), [guess = 1.0]
            end
            @lattice Lattice((12, 8))
            @energy cells => (volume - 14.0)^2
            @initialization_equations r^2 ~ volume
            @sweep Metropolis(; temperature = 1.0)
        end
    end
)
# I: a coupled implicit pair
define(
    :InitializationPair, quote
        @potts_model InitializationPair begin
            @kinds medium A
            @variables begin
                a_u(cell)
                b_u(cell)
            end
            @lattice Lattice((12, 8))
            @energy cells => (volume - 14.0)^2
            @initialization_equations begin
                a_u + b_u ~ volume
                a_u - b_u ~ id
            end
            @sweep Metropolis(; temperature = 1.0)
        end
    end
)
# I: a steady start of a cell ODE
define(
    :Steady, quote
        @potts_model Steady begin
            @kinds medium A
            @parameters begin
                α = 0.1
                κ = 0.5
            end
            @variables xs(cell)
            @lattice Lattice((12, 8))
            @energy cells => (volume - 14.0)^2
            @equations D(xs) ~ α * volume - κ * xs
            @initialization_equations D(xs) ~ 0
            @sweep Metropolis(; temperature = 1.0)
        end
    end
)
# I: model scope first, read by a cell equation
define(
    :Model, quote
        @potts_model Model begin
            @kinds medium A
            @parameters r0 = 0.2
            @variables begin
                m(model)
                z(cell)
            end
            @lattice Lattice((12, 8))
            @energy cells => (volume - 14.0)^2
            @initialization_equations begin
                m ~ 3r0
                z ~ m + volume
            end
            @sweep Metropolis(; temperature = 1.0)
        end
    end
)
# S: a template without inputs (parameters only)
define(
    :Const, quote
        @potts_model Const begin
            @kinds medium A
            @parameters c0 = 3.0
            @variables rq(cell)
            @lattice Lattice((12, 8))
            @energy cells => (volume - 14.0)^2
            @initialization_equations rq ~ 3c0
            @sweep Metropolis(; temperature = 1.0)
        end
    end
)
# I, V: an algebraic variable (`ode_mtkcompile_tests.jl`) set from the operating point; no section needed, so
# this fixture defines on the tree before the item
define(
    :Alg, quote
        @potts_model Alg begin
            @kinds medium A
            @parameters k = 0.1
            @variables begin
                x(cell)
                xd(cell)
            end
            @lattice Lattice((12, 8))
            @energy cells => (volume - 14.0)^2
            @equations begin
                D(x) ~ -k * xd
                xd ~ 2x
            end
            @sweep Metropolis(; temperature = 1.0)
        end
    end
)
# U: no initialization equations
define(
    :None, quote
        @potts_model None begin
            @kinds medium A
            @variables begin
                Vt(cell) = 5.0
                w(cell)
            end
            @lattice Lattice((12, 8))
            @energy cells => (volume - 14.0)^2
            @sweep Metropolis(; temperature = 1.0)
        end
    end
)
# V: rejected
define(
    :Written, quote
        @potts_model Written begin
            @kinds medium A
            @variables Vt(cell) = 1.0
            @lattice Lattice((12, 8))
            @energy cells => (volume - 14.0)^2
            @initialization_equations Vt ~ 2volume
            @sweep Metropolis(; temperature = 1.0)
        end
    end
)
define(
    :WrittenZero, quote
        @potts_model WrittenZero begin
            @kinds medium A
            @variables Vt(cell) = 0.0
            @lattice Lattice((12, 8))
            @energy cells => (volume - 14.0)^2
            @initialization_equations Vt ~ 2volume
            @sweep Metropolis(; temperature = 1.0)
        end
    end
)
define(
    :Under, quote
        @potts_model Under begin
            @kinds medium A
            @variables begin
                alpha_u(cell)
                beta_u(cell)
            end
            @lattice Lattice((12, 8))
            @energy cells => (volume - 14.0)^2
            @initialization_equations alpha_u + beta_u ~ volume
            @sweep Metropolis(; temperature = 1.0)
        end
    end
)
define(
    :Rootless, quote
        @potts_model Rootless begin
            @kinds medium A
            @variables begin
                rootless(cell), [guess = 1.0]
            end
            @lattice Lattice((12, 8))
            @energy cells => (volume - 14.0)^2
            @initialization_equations rootless^2 ~ -volume
            @sweep Metropolis(; temperature = 1.0)
        end
    end
)
# X: cross-entity, refused until later work
define(
    :Cross, quote
        @potts_model Cross begin
            @kinds medium A
            @variables begin
                partner(cell) = 1.0
                xr(cell)
            end
            @lattice Lattice((12, 8))
            @energy cells => (volume - 14.0)^2
            @initialization_equations xr ~ partner[3 - id]
            @sweep Metropolis(; temperature = 1.0)
        end
    end
)
define(
    :Gather, quote
        @potts_model Gather begin
            @kinds medium A
            @variables xgather(cell)
            @lattice Lattice((12, 8))
            @energy cells => (volume - 14.0)^2
            @initialization_equations xgather ~ sum(volume[owner[n]] for n in Moore(1)(42))
            @sweep Metropolis(; temperature = 1.0)
        end
    end
)
define(
    :Field, quote
        @potts_model Field begin
            @kinds medium A
            @variables cfield(field) = 0.0
            @lattice Lattice((12, 8))
            @energy cells => (volume - 14.0)^2
            @initialization_equations cfield ~ 1.0
            @sweep Metropolis(; temperature = 1.0)
        end
    end
)
sigma() = (s = zeros(Int32, 12, 8); s[3:6, 3:6] .= 1; s[7:10, 3:5] .= 2; s)
sigma2() = (s = zeros(Int32, 12, 8); s[3:5, 3:6] .= 1; s[7:10, 3:6] .= 2; s)
# volumes 12, 16
initialization_op(extra...; σ = sigma()) = Any[ownership => σ, kind => [:A, :A], extra...]
const VOL = [16.0, 12.0]
const INITIALIZATION_ID = [1.0, 2.0]
const INITIALIZATION_N = 10
initialization_prob(name, op = initialization_op(); kw...) = PottsProblem(initialization_build(name), op, (0, INITIALIZATION_N); seed = 7, kw...)
initialization_u0(prob, n) = Vector{Float64}(Array(getproperty(prob.u0.cell, n)))
initialization_cells(sol, n) = [Vector{Float64}(Array(getproperty(u.cell, n))) for u in sol.u]
initialization_close(a, b; rtol = 1.0e-12) = length(a) == length(b) && all(i -> isapprox(a[i], b[i]; rtol), eachindex(a, b))
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
function initialization_guess(s, n)
    v = byname(INITIALIZATION_M.unknowns(s), n)
    g = try
        get(INITIALIZATION_M.guesses(s), v, nothing)
    catch
        nothing
    end
    g === nothing && (g = INITIALIZATION_M.getguess(v))
    g === nothing && return nothing
    g = Potts.Symbolics.value(g)
    return Float64(g isa Number ? g : Potts.SymbolicUtils.unwrap_const(g))
end
# every published model (small lattices; construction and `mtkcompile` only), as in `ode_mtkcompile_tests.jl`
const MODELS = [
    ("GranerGlazier", () -> GranerGlazier(; name = :gg)),
    ("WortelAct", () -> WortelAct(; name = :act, lattice = (8, 8))),
    ("WortelAct connected", () -> WortelAct(; name = :act, lattice = (8, 8), connected = true)),
    ("MerksVasculogenesis", () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8))),
    (
        "MerksVasculogenesis contact-inhibited",
        () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8), contact_inhibited = true),
    ),
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
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "initialization A: public name with a docstring" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # A. Public name
    @testset "initialization A: public name with a docstring" begin
        @test isdefined(Potts, :initialization_system) && Base.ispublic(Potts, :initialization_system)
        @test isdefined(Potts, :initialization_system) && Base.Docs.hasdoc(Potts, :initialization_system)
        @test !Base.isexported(Potts, :initialization_system)
    end
end

@testitem "initialization S: the cell template carries the initialization equations" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # S. The initialization part is an MTK System
    @testset "initialization S: the cell template carries the initialization equations" begin
        sys = initialization_build(:Target)
        for cs in (mtkcompile(sys),)
            s = initialization_init(cs, :cell)
            @test s isa INITIALIZATION_M.System && INITIALIZATION_M.iscomplete(s)
            @test length(INITIALIZATION_M.initialization_equations(s)) == 1
            @test :Vt in initialization_names(INITIALIZATION_M.unknowns(s))
            @test initialization_init(cs, :model) === nothing
        end
        s = initialization_init(mtkcompile(initialization_build(:InitializationPair)), :cell)
        @test length(INITIALIZATION_M.initialization_equations(s)) == 2
        @test issubset(Set([:a_u, :b_u]), initialization_names(INITIALIZATION_M.unknowns(s)))
    end
end

@testitem "initialization S: model and cell templates, guesses, parameters" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "initialization S: model and cell templates, guesses, parameters" begin
        cm = mtkcompile(initialization_build(:Model))
        sm = initialization_init(cm, :model)
        @test sm isa INITIALIZATION_M.System && INITIALIZATION_M.iscomplete(sm)
        @test length(INITIALIZATION_M.initialization_equations(sm)) == 1
        @test :m in initialization_names(INITIALIZATION_M.unknowns(sm)) && :r0 in initialization_names(INITIALIZATION_M.parameters(sm))
        sc = initialization_init(cm, :cell)
        @test sc isa INITIALIZATION_M.System && length(INITIALIZATION_M.initialization_equations(sc)) == 1
        @test :z in initialization_names(INITIALIZATION_M.unknowns(sc))
        @test !(:m in initialization_names(INITIALIZATION_M.unknowns(sc)))              # a model value is an input of a cell
        @test initialization_guess(initialization_init(mtkcompile(initialization_build(:RootNeg)), :cell), :r) == -1.0
        @test initialization_guess(initialization_init(mtkcompile(initialization_build(:RootPos)), :cell), :r) == 1.0
        # an operating-point condition alone builds no template
        ca = mtkcompile(initialization_build(:Alg))
        @test initialization_init(ca, :cell) === nothing && initialization_init(ca, :model) === nothing
    end
end

@testitem "initialization S: MTK's InitializationProblem solves a template without inputs" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "initialization S: MTK's InitializationProblem solves a template without inputs" begin
        s = initialization_init(mtkcompile(initialization_build(:Const)), :cell)
        @test :c0 in initialization_names(INITIALIZATION_M.parameters(s))
        rq = byname(INITIALIZATION_M.unknowns(s), :rq)
        c0 = byname(INITIALIZATION_M.parameters(s), :c0)
        ip = INITIALIZATION_M.InitializationProblem(s, 0.0, [c0 => 3.0])
        sol = Potts.SciMLBase.solve(ip)
        @test Potts.SciMLBase.successful_retcode(sol)
        @test isapprox(sol[rq], 9.0; rtol = 1.0e-12)                       # rq ~ 3c0, by hand
        # Potts' own run gives the same value in every cell
        @test initialization_close(initialization_u0(initialization_prob(:Const), :rq), [9.0, 9.0])
    end
end

@testitem "initialization S: scope and form errors" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "initialization S: scope and form errors" begin
        sys = initialization_build(:Target)
        cs = mtkcompile(sys)
        for sc in (:site, :field, :edge, :nonsense)
            @test clear(() -> Potts.initialization_system(cs, sc), String(sc))
        end
        @test clear(() -> Potts.initialization_system(sys, :cell), "mtkcompile")
    end
end

@testitem "initialization I: explicit, over built-ins and a fixed variable" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # I. Per-cell results equal the hand-solved values
    @testset "initialization I: explicit, over built-ins and a fixed variable" begin
        @test initialization_close(initialization_u0(initialization_prob(:Target), :Vt), 2 .* VOL .+ INITIALIZATION_ID)          # [33, 26]
        prob = initialization_prob(:Target, initialization_op(:w => [1.0, -1.0]))
        @test initialization_close(initialization_u0(prob, :Vt), 2 .* VOL .+ INITIALIZATION_ID .+ [1.0, -1.0])               # [34, 25]
        @test initialization_u0(prob, :w) == [1.0, -1.0]
    end
end

@testitem "initialization I: nonlinear, the root chosen by the guess" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "initialization I: nonlinear, the root chosen by the guess" begin
        neg = initialization_u0(initialization_prob(:RootNeg), :r)
        pos = initialization_u0(initialization_prob(:RootPos), :r)
        @test initialization_close(neg, -sqrt.(VOL); rtol = 1.0e-9)
        @test initialization_close(pos, sqrt.(VOL); rtol = 1.0e-9)
        @test !initialization_close(neg, sqrt.(VOL); rtol = 1.0e-3)            # negative control: the other root
    end
end

@testitem "initialization I: a coupled implicit pair" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "initialization I: a coupled implicit pair" begin
        prob = initialization_prob(:InitializationPair)
        @test initialization_close(initialization_u0(prob, :a_u), (VOL .+ INITIALIZATION_ID) ./ 2)                           # [8.5, 7.0]
        @test initialization_close(initialization_u0(prob, :b_u), (VOL .- INITIALIZATION_ID) ./ 2)                           # [7.5, 5.0]
    end
end

@testitem "initialization I: a steady start of a cell ODE" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "initialization I: a steady start of a cell ODE" begin
        prob = initialization_prob(:Steady)
        @test initialization_close(initialization_u0(prob, :xs), 0.1 .* VOL ./ 0.5)                                 # [3.2, 2.4]
        @test !initialization_close(initialization_u0(prob, :xs), 0.1 .* VOL ./ 0.4; rtol = 1.0e-3)
    end
end

@testitem "initialization I: the model first, then the cells" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "initialization I: the model first, then the cells" begin
        prob = initialization_prob(:Model)
        m = Float64(only(Array(prob.u0.model.m)))
        @test isapprox(m, 3 * 0.2; rtol = 1.0e-12)
        @test initialization_close(initialization_u0(prob, :z), m .+ VOL)                                           # [16.6, 12.6]
    end
end

@testitem "initialization I: an algebraic variable's operating-point value" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "initialization I: an algebraic variable's operating-point value" begin
        prob = initialization_prob(:Alg, initialization_op(:xd => [1.0, 3.0]))
        x0 = [0.5, 1.5]
        @test initialization_close(initialization_u0(prob, :x), x0)
        sol = solve(prob, SequentialCPM(; proposal = Moore(1)); saveat = 1)
        x = initialization_cells(sol, :x)
        @test sol.t == collect(0:INITIALIZATION_N)
        @test initialization_close(x, [x0 .* 0.8^N for N in 0:INITIALIZATION_N])           # explicit Euler of x' = −0.1·2x
        @test initialization_close([Vector{Float64}(Array(v)) for v in sol[:xd]], [2 .* v for v in x])
        @test !initialization_close(x, [x0 .* 0.9^N for N in 0:INITIALIZATION_N]; rtol = 1.0e-6)
        # untouched by any condition, a variable declared without a value starts at 0.0, as before
        @test initialization_u0(initialization_prob(:Alg), :x) == [0.0, 0.0]
    end
end

@testitem "initialization I: remake re-initializes from a map, not from a saved state" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "initialization I: remake re-initializes from a map, not from a saved state" begin
        prob = initialization_prob(:Target)
        p2 = remake(prob; u0 = initialization_op(; σ = sigma2()))
        @test initialization_close(initialization_u0(p2, :Vt), 2 .* [12.0, 16.0] .+ INITIALIZATION_ID)                             # [25, 34]
        sol = solve(prob, SequentialCPM(; proposal = Moore(1)))
        final = sol.u[end]
        vols = [Float64(count(==(c), final.ownership)) for c in 1:2]
        @test vols != VOL                                          # the sweep moved the cells
        p3 = remake(prob; u0 = final)
        @test initialization_u0(p3, :Vt) == Vector{Float64}(Array(final.cell.Vt))
        @test initialization_close(initialization_u0(p3, :Vt), 2 .* VOL .+ INITIALIZATION_ID)   # kept, not re-solved
    end
end

@testitem "initialization I: zero warm allocations after initialization" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "initialization I: zero warm allocations after initialization" begin
        for (name, op) in ((:Target, initialization_op()), (:Alg, initialization_op(:xd => [1.0, 3.0])), (:Steady, initialization_op())),
                alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
            prob = PottsProblem(initialization_build(name), op, (0, 100); seed = 7)
            a = warm_allocs(prob, alg)
            all(iszero, a) || @info "initialization: $name $(nameof(typeof(alg))) allocates $a"
            @test all(iszero, a)
        end
    end
end

@testitem "initialization V: rejections" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # V. Values: fixed, free, over- and underdetermined
    @testset "initialization V: rejections" begin
        attempt(name, op = initialization_op()) = () -> PottsProblem(initialization_build(name), op, (0, 1))
        @test clear(attempt(:Written), "Vt")
        @test clear(attempt(:WrittenZero), "Vt")
        @test clear(attempt(:Target, initialization_op(:Vt => [5.0, 5.0])), "Vt")
        @test clear(attempt(:Alg, initialization_op(:x => [2.0, 3.0], :xd => [1.0, 1.0])), "xd")
        @test clear(attempt(:Under), "underdetermined")
        @test clear(attempt(:Rootless), "rootless")
    end
end

@testitem "initialization X: cross-entity initialization is refused until" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # X. Cross-entity equations are not MTK's
    @testset "initialization X: cross-entity initialization is refused until" begin
        attempt(name) = () -> PottsProblem(initialization_build(name), initialization_op(), (0, 1))
        @test clear(Potts.PottsCompileError, attempt(:Cross), "partner")
        @test clear(Potts.PottsCompileError, attempt(:Gather), "xgather")
        @test clear(Potts.PottsCompileError, attempt(:Field), "cfield")
    end
end

@testitem "initialization U: no initialization equations, no templates, declared values" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # U. Unchanged
    @testset "initialization U: no initialization equations, no templates, declared values" begin
        c = mtkcompile(initialization_build(:None))
        @test initialization_init(c, :cell) === nothing && initialization_init(c, :model) === nothing
        prob = initialization_prob(:None)
        @test initialization_u0(prob, :Vt) == [5.0, 5.0] && initialization_u0(prob, :w) == [0.0, 0.0]
        @test initialization_u0(initialization_prob(:None, initialization_op(:Vt => [1.0, 2.0])), :Vt) == [1.0, 2.0]
    end
end

@testitem "initialization U: published models have no initialization template" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "initialization U: published models have no initialization template" begin
        @testset "$label" for (label, build) in MODELS
            cs = mtkcompile(build())
            @test initialization_init(cs, :cell) === nothing
            @test initialization_init(cs, :model) === nothing
        end
    end
end

@testitem "initialization N: detectors can fail" setup = [InitializationSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # N. Negative controls for the detectors
    @testset "initialization N: detectors can fail" begin
        t = Potts.t
        INITIALIZATION_M.@variables xs_plain(t) = 1.0
        plain = INITIALIZATION_M.System([Potts.D(xs_plain) ~ -xs_plain], t; name = :plain)
        @test isempty(INITIALIZATION_M.initialization_equations(plain))
        withinit = INITIALIZATION_M.System([Potts.D(xs_plain) ~ -xs_plain], t; name = :plain, initialization_eqs = [xs_plain ~ 2.0])
        @test length(INITIALIZATION_M.initialization_equations(withinit)) == 1
        @test !initialization_close([33.0, 26.0], [32.0, 26.0])
        @test !clear(() -> 1, "overdetermined")
        @test !clear(() -> throw(ArgumentError("something else")), "overdetermined")
        @test clear(() -> throw(ArgumentError("x is overdetermined")), "overdetermined")
        @test !clear(() -> throw(ErrorException("overdetermined")), "overdetermined")
    end
end
