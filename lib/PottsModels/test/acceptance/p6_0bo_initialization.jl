# P6.0bo (ROADMAP Phase 6, step 0; D-159, D-165; research/mtk-native-plan.md §4 route A1,
# §5, §6): initialization equations that touch one cell (or the model) go through
# ModelingToolkit's initialization engine. Potts builds one MTK `System` per scope (cell,
# model) carrying that scope's `@initialization_equations` as MTK `initialization_eqs` (the
# per-cell template, as P6.0bn's ODE template), builds MTK's `InitializationProblem` from it
# when a problem is constructed, and solves it once per cell on the host, before the first
# MCS. The batched kernels are unchanged. This makes plan §5's "initialization ... parts of a
# model are ModelingToolkit systems" true for entity-local initialization. Cross-entity and
# lattice initialization (reads of other cells, gathers, folds, site and field variables)
# stay Potts' (R17, P6.4a); until then they are refused.
# Decision: D-1xx (P6.0bo; the coordinator numbers it). Frozen (AUTONOMY §7.3).
#
# What is new for users:
#  - a `@potts_model` section `@initialization_equations` (MTK's `initialization_eqs`):
#    equations `lhs ~ rhs`, explicit or implicit, linear or nonlinear, between the cell's own
#    variables (read bare), its built-ins (`volume`, `id`), parameters, model variables, and
#    `D(x)` of a cell or model ODE variable `x` (its rate at the start: `D(x) ~ 0` is a
#    steady start);
#  - a guess for a variable that initialization solves for, written as MTK variable metadata:
#    `r(cell), [guess = -1.0]` (no value). It seeds the nonlinear solve and picks the root;
#  - an operating-point value for an algebraic variable (P6.0bn's `y ~ expr`) is now an
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
#     P6.0bn's frozen R check, `x => [2, 3], xalias => [1, 1]`, an error naming `xalias`); too
#     few equations ("underdetermined" and a name of a free variable); an equation with no
#     solution (`rootless^2 ~ -volume`: "initialization" and the name).
#  X. Cross-entity equations are not given to MTK; until P6.4a they are an ArgumentError
#     ("initialization" and the name read across entities, or the equation's variable): a read
#     of another cell's variable (`xr ~ partner[3 - id]`), a neighbour gather at a site, and a
#     field variable.
#  U. Unchanged: a model without `@initialization_equations` has no templates and starts from
#     its declared values; every published model has no template in either scope (their code
#     and fingerprints are pinned byte-identical by p6_0o, D-137 rule 7, not here). The F7
#     rejection of a component's own `initialization_eqs` is unchanged (frozen in p6_0k2).
#  N. Negative controls: a plain MTK `System` without `initialization_eqs` lists none (the S
#     detector can fail); wrong hand values (the other root, a wrong coefficient) do not match;
#     the rejection detector refuses a call that does not throw and a message without the word.
#
# On 2bcc4b75 (the tree before this item) every fixture that uses `@initialization_equations`
# or a guess without a value fails to define (an undefined macro, or "variables are declared
# with a scope"); the definitions are captured, so every A/S/I/V/X target fails or errors in
# its testset and the U and N checks pass.
using Potts: CorePotts

const P60BO_M = Potts.ModelingToolkitBase
const P60BO_SII = Potts.SymbolicIndexingInterface

p60bo_name(x) = P60BO_SII.getname(x)
p60bo_names(xs) = Set{Symbol}(p60bo_name(x) for x in xs)
p60bo_byname(xs, n) = only(x for x in xs if p60bo_name(x) === n)
p60bo_init(c, scope) = Potts.initialization_system(c, scope)

_p60bo_unwrap(err) = err isa LoadError ? _p60bo_unwrap(err.error) : err
p60bo_clear(f, words...) = try
    f()
    false
catch err
    e = _p60bo_unwrap(err)
    ok = e isa ArgumentError && all(w -> occursin(w, sprint(showerror, e)), words)
    ok || @info "P6.0bo: expected an ArgumentError naming $(words)" exception = e
    ok
end
# an ArgumentError naming `word` and at least one of `names`
p60bo_clear_any(f, word, names) = try
    f()
    false
catch err
    e = _p60bo_unwrap(err)
    msg = sprint(showerror, e)
    ok = e isa ArgumentError && occursin(word, msg) && any(n -> occursin(n, msg), names)
    ok || @info "P6.0bo: expected an ArgumentError with $(word) naming one of $(names)" exception = e
    ok
end

# Fixtures are defined by evaluating their `@potts_model` here and capturing any error, so
# that a tree without the section fails in the testsets and not when this file loads.
const P60BO_DEFINED = Dict{Symbol, Any}()
function p60bo_define(name::Symbol, ex)
    P60BO_DEFINED[name] = try
        Core.eval(@__MODULE__, ex)
        nothing
    catch err
        _p60bo_unwrap(err)
    end
    return nothing
end
function p60bo_build(name::Symbol; kw...)
    err = P60BO_DEFINED[name]
    err === nothing || throw(err)
    return Base.invokelatest(getfield(@__MODULE__, name); name = :x, kw...)
end

# ---------------------------------------------------------------------------------------
# Fixtures: two cells on a 12×8 lattice, cell 1 at x = 3:6, y = 3:6 (16 sites) and cell 2 at
# x = 7:10, y = 3:5 (12 sites). No energy reads an initialized variable.

# I: explicit, over built-ins and a fixed variable (w is written as 0.0: fixed)
p60bo_define(:P60boTarget, quote
    @potts_model P60boTarget begin
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
end)
# I: nonlinear, the root picked by the guess
p60bo_define(:P60boRootNeg, quote
    @potts_model P60boRootNeg begin
        @kinds medium A
        @variables begin
            r(cell), [guess = -1.0]
        end
        @lattice Lattice((12, 8))
        @energy cells => (volume - 14.0)^2
        @initialization_equations r^2 ~ volume
        @sweep Metropolis(; temperature = 1.0)
    end
end)
p60bo_define(:P60boRootPos, quote
    @potts_model P60boRootPos begin
        @kinds medium A
        @variables begin
            r(cell), [guess = 1.0]
        end
        @lattice Lattice((12, 8))
        @energy cells => (volume - 14.0)^2
        @initialization_equations r^2 ~ volume
        @sweep Metropolis(; temperature = 1.0)
    end
end)
# I: a coupled implicit pair
p60bo_define(:P60boPair, quote
    @potts_model P60boPair begin
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
end)
# I: a steady start of a cell ODE
p60bo_define(:P60boSteady, quote
    @potts_model P60boSteady begin
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
end)
# I: model scope first, read by a cell equation
p60bo_define(:P60boModel, quote
    @potts_model P60boModel begin
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
end)
# S: a template without inputs (parameters only)
p60bo_define(:P60boConst, quote
    @potts_model P60boConst begin
        @kinds medium A
        @parameters c0 = 3.0
        @variables rq(cell)
        @lattice Lattice((12, 8))
        @energy cells => (volume - 14.0)^2
        @initialization_equations rq ~ 3c0
        @sweep Metropolis(; temperature = 1.0)
    end
end)
# I, V: an algebraic variable (P6.0bn) set from the operating point; no section needed, so
# this fixture defines on the tree before the item
p60bo_define(:P60boAlg, quote
    @potts_model P60boAlg begin
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
end)
# U: no initialization equations
p60bo_define(:P60boNone, quote
    @potts_model P60boNone begin
        @kinds medium A
        @variables begin
            Vt(cell) = 5.0
            w(cell)
        end
        @lattice Lattice((12, 8))
        @energy cells => (volume - 14.0)^2
        @sweep Metropolis(; temperature = 1.0)
    end
end)

# V: rejected
p60bo_define(:P60boWritten, quote
    @potts_model P60boWritten begin
        @kinds medium A
        @variables Vt(cell) = 1.0
        @lattice Lattice((12, 8))
        @energy cells => (volume - 14.0)^2
        @initialization_equations Vt ~ 2volume
        @sweep Metropolis(; temperature = 1.0)
    end
end)
p60bo_define(:P60boWrittenZero, quote
    @potts_model P60boWrittenZero begin
        @kinds medium A
        @variables Vt(cell) = 0.0
        @lattice Lattice((12, 8))
        @energy cells => (volume - 14.0)^2
        @initialization_equations Vt ~ 2volume
        @sweep Metropolis(; temperature = 1.0)
    end
end)
p60bo_define(:P60boUnder, quote
    @potts_model P60boUnder begin
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
end)
p60bo_define(:P60boRootless, quote
    @potts_model P60boRootless begin
        @kinds medium A
        @variables begin
            rootless(cell), [guess = 1.0]
        end
        @lattice Lattice((12, 8))
        @energy cells => (volume - 14.0)^2
        @initialization_equations rootless^2 ~ -volume
        @sweep Metropolis(; temperature = 1.0)
    end
end)

# X: cross-entity, refused until P6.4a
p60bo_define(:P60boCross, quote
    @potts_model P60boCross begin
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
end)
p60bo_define(:P60boGather, quote
    @potts_model P60boGather begin
        @kinds medium A
        @variables xgather(cell)
        @lattice Lattice((12, 8))
        @energy cells => (volume - 14.0)^2
        @initialization_equations xgather ~ sum(volume[owner[n]] for n in Moore(1)(42))
        @sweep Metropolis(; temperature = 1.0)
    end
end)
p60bo_define(:P60boField, quote
    @potts_model P60boField begin
        @kinds medium A
        @variables cfield(field) = 0.0
        @lattice Lattice((12, 8))
        @energy cells => (volume - 14.0)^2
        @initialization_equations cfield ~ 1.0
        @sweep Metropolis(; temperature = 1.0)
    end
end)

p60bo_sigma() = (s = zeros(Int32, 12, 8); s[3:6, 3:6] .= 1; s[7:10, 3:5] .= 2; s)
p60bo_sigma2() = (s = zeros(Int32, 12, 8); s[3:5, 3:6] .= 1; s[7:10, 3:6] .= 2; s)   # volumes 12, 16
p60bo_op(extra...; σ = p60bo_sigma()) = Any[ownership => σ, kind => [:A, :A], extra...]
const P60BO_VOL = [16.0, 12.0]
const P60BO_ID = [1.0, 2.0]
const P60BO_N = 10

p60bo_prob(name, op = p60bo_op(); kw...) = PottsProblem(p60bo_build(name), op, (0, P60BO_N); seed = 7, kw...)
p60bo_u0(prob, n) = Vector{Float64}(Array(getproperty(prob.u0.cell, n)))
p60bo_cells(sol, n) = [Vector{Float64}(Array(getproperty(u.cell, n))) for u in sol.u]
p60bo_close(a, b; rtol = 1e-12) = length(a) == length(b) && all(i -> isapprox(a[i], b[i]; rtol), eachindex(a, b))

"""Bytes allocated by each of five warm `step!`s (after two warm-up steps)."""
function p60bo_warm_allocs(prob, alg)
    integ = init(prob, alg; save_start = false, save_end = false)
    step!(integ)
    step!(integ)
    out = Int[]
    for _ in 1:5
        push!(out, @allocated step!(integ))
    end
    return out
end

function p60bo_guess(s, n)
    v = p60bo_byname(P60BO_M.unknowns(s), n)
    g = try
        get(P60BO_M.guesses(s), v, nothing)
    catch
        nothing
    end
    g === nothing && (g = P60BO_M.getguess(v))
    g === nothing && return nothing
    g = Potts.Symbolics.value(g)
    return Float64(g isa Number ? g : Potts.SymbolicUtils.unwrap_const(g))
end

# every published model (small lattices; construction and `mtkcompile` only), as in p6_0bn
const P60BO_PUBLISHED = [
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

@testset "P6.0bo A: public name with a docstring" begin
    @test isdefined(Potts, :initialization_system) && Base.ispublic(Potts, :initialization_system)
    @test isdefined(Potts, :initialization_system) && Base.Docs.hasdoc(Potts, :initialization_system)
    @test !Base.isexported(Potts, :initialization_system)
end

# ---------------------------------------------------------------------------------------
# S. The initialization part is an MTK System

@testset "P6.0bo S: the cell template carries the initialization equations" begin
    sys = p60bo_build(:P60boTarget)
    for cs in (mtkcompile(sys), mtkcompile(complete(sys)))
        s = p60bo_init(cs, :cell)
        @test s isa P60BO_M.System && P60BO_M.iscomplete(s)
        @test length(P60BO_M.initialization_equations(s)) == 1
        @test :Vt in p60bo_names(P60BO_M.unknowns(s))
        @test p60bo_init(cs, :model) === nothing
    end
    s = p60bo_init(mtkcompile(p60bo_build(:P60boPair)), :cell)
    @test length(P60BO_M.initialization_equations(s)) == 2
    @test issubset(Set([:a_u, :b_u]), p60bo_names(P60BO_M.unknowns(s)))
end

@testset "P6.0bo S: model and cell templates, guesses, parameters" begin
    cm = mtkcompile(p60bo_build(:P60boModel))
    sm = p60bo_init(cm, :model)
    @test sm isa P60BO_M.System && P60BO_M.iscomplete(sm)
    @test length(P60BO_M.initialization_equations(sm)) == 1
    @test :m in p60bo_names(P60BO_M.unknowns(sm)) && :r0 in p60bo_names(P60BO_M.parameters(sm))
    sc = p60bo_init(cm, :cell)
    @test sc isa P60BO_M.System && length(P60BO_M.initialization_equations(sc)) == 1
    @test :z in p60bo_names(P60BO_M.unknowns(sc))
    @test !(:m in p60bo_names(P60BO_M.unknowns(sc)))              # a model value is an input of a cell
    @test p60bo_guess(p60bo_init(mtkcompile(p60bo_build(:P60boRootNeg)), :cell), :r) == -1.0
    @test p60bo_guess(p60bo_init(mtkcompile(p60bo_build(:P60boRootPos)), :cell), :r) == 1.0
    # an operating-point condition alone builds no template
    ca = mtkcompile(p60bo_build(:P60boAlg))
    @test p60bo_init(ca, :cell) === nothing && p60bo_init(ca, :model) === nothing
end

@testset "P6.0bo S: MTK's InitializationProblem solves a template without inputs" begin
    s = p60bo_init(mtkcompile(p60bo_build(:P60boConst)), :cell)
    @test :c0 in p60bo_names(P60BO_M.parameters(s))
    rq = p60bo_byname(P60BO_M.unknowns(s), :rq)
    c0 = p60bo_byname(P60BO_M.parameters(s), :c0)
    ip = P60BO_M.InitializationProblem(s, 0.0, [c0 => 3.0])
    sol = Potts.SciMLBase.solve(ip)
    @test Potts.SciMLBase.successful_retcode(sol)
    @test isapprox(sol[rq], 9.0; rtol = 1e-12)                       # rq ~ 3c0, by hand
    # Potts' own run gives the same value in every cell
    @test p60bo_close(p60bo_u0(p60bo_prob(:P60boConst), :rq), [9.0, 9.0])
end

@testset "P6.0bo S: scope and form errors" begin
    sys = p60bo_build(:P60boTarget)
    cs = mtkcompile(sys)
    for sc in (:site, :field, :edge, :nonsense)
        @test p60bo_clear(() -> Potts.initialization_system(cs, sc), String(sc))
    end
    @test p60bo_clear(() -> Potts.initialization_system(sys, :cell), "mtkcompile")
end

# ---------------------------------------------------------------------------------------
# I. Per-cell results equal the hand-solved values

@testset "P6.0bo I: explicit, over built-ins and a fixed variable" begin
    @test p60bo_close(p60bo_u0(p60bo_prob(:P60boTarget), :Vt), 2 .* P60BO_VOL .+ P60BO_ID)          # [33, 26]
    prob = p60bo_prob(:P60boTarget, p60bo_op(:w => [1.0, -1.0]))
    @test p60bo_close(p60bo_u0(prob, :Vt), 2 .* P60BO_VOL .+ P60BO_ID .+ [1.0, -1.0])               # [34, 25]
    @test p60bo_u0(prob, :w) == [1.0, -1.0]
end

@testset "P6.0bo I: nonlinear, the root chosen by the guess" begin
    neg = p60bo_u0(p60bo_prob(:P60boRootNeg), :r)
    pos = p60bo_u0(p60bo_prob(:P60boRootPos), :r)
    @test p60bo_close(neg, -sqrt.(P60BO_VOL); rtol = 1e-9)
    @test p60bo_close(pos, sqrt.(P60BO_VOL); rtol = 1e-9)
    @test !p60bo_close(neg, sqrt.(P60BO_VOL); rtol = 1e-3)            # negative control: the other root
end

@testset "P6.0bo I: a coupled implicit pair" begin
    prob = p60bo_prob(:P60boPair)
    @test p60bo_close(p60bo_u0(prob, :a_u), (P60BO_VOL .+ P60BO_ID) ./ 2)                           # [8.5, 7.0]
    @test p60bo_close(p60bo_u0(prob, :b_u), (P60BO_VOL .- P60BO_ID) ./ 2)                           # [7.5, 5.0]
end

@testset "P6.0bo I: a steady start of a cell ODE" begin
    prob = p60bo_prob(:P60boSteady)
    @test p60bo_close(p60bo_u0(prob, :xs), 0.1 .* P60BO_VOL ./ 0.5)                                 # [3.2, 2.4]
    @test !p60bo_close(p60bo_u0(prob, :xs), 0.1 .* P60BO_VOL ./ 0.4; rtol = 1e-3)
end

@testset "P6.0bo I: the model first, then the cells" begin
    prob = p60bo_prob(:P60boModel)
    m = Float64(only(Array(prob.u0.model.m)))
    @test isapprox(m, 3 * 0.2; rtol = 1e-12)
    @test p60bo_close(p60bo_u0(prob, :z), m .+ P60BO_VOL)                                           # [16.6, 12.6]
end

@testset "P6.0bo I: an algebraic variable's operating-point value (supersedes D-165's refusal)" begin
    prob = p60bo_prob(:P60boAlg, p60bo_op(:xd => [1.0, 3.0]))
    x0 = [0.5, 1.5]
    @test p60bo_close(p60bo_u0(prob, :x), x0)
    sol = solve(prob, SequentialCPM(; proposal = Moore(1)); saveat = 1)
    x = p60bo_cells(sol, :x)
    @test sol.t == collect(0:P60BO_N)
    @test p60bo_close(x, [x0 .* 0.8^N for N in 0:P60BO_N])           # explicit Euler of x' = −0.1·2x
    @test p60bo_close([Vector{Float64}(Array(v)) for v in sol[:xd]], [2 .* v for v in x])
    @test !p60bo_close(x, [x0 .* 0.9^N for N in 0:P60BO_N]; rtol = 1e-6)
    # untouched by any condition, a variable declared without a value starts at 0.0, as before
    @test p60bo_u0(p60bo_prob(:P60boAlg), :x) == [0.0, 0.0]
end

@testset "P6.0bo I: remake re-initializes from a map, not from a saved state" begin
    prob = p60bo_prob(:P60boTarget)
    p2 = remake(prob; u0 = p60bo_op(; σ = p60bo_sigma2()))
    @test p60bo_close(p60bo_u0(p2, :Vt), 2 .* [12.0, 16.0] .+ P60BO_ID)                             # [25, 34]
    sol = solve(prob, SequentialCPM(; proposal = Moore(1)))
    final = sol.u[end]
    vols = [Float64(count(==(c), final.σ)) for c in 1:2]
    @test vols != P60BO_VOL                                          # the sweep moved the cells
    p3 = remake(prob; u0 = final)
    @test p60bo_u0(p3, :Vt) == Vector{Float64}(Array(final.cell.Vt))
    @test p60bo_close(p60bo_u0(p3, :Vt), 2 .* P60BO_VOL .+ P60BO_ID)   # kept, not re-solved
end

@testset "P6.0bo I: zero warm allocations after initialization" begin
    for (name, op) in ((:P60boTarget, p60bo_op()), (:P60boAlg, p60bo_op(:xd => [1.0, 3.0])), (:P60boSteady, p60bo_op())),
        alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
        prob = PottsProblem(p60bo_build(name), op, (0, 100); seed = 7)
        a = p60bo_warm_allocs(prob, alg)
        all(iszero, a) || @info "P6.0bo: $name $(nameof(typeof(alg))) allocates $a"
        @test all(iszero, a)
    end
end

# ---------------------------------------------------------------------------------------
# V. Values: fixed, free, over- and underdetermined

@testset "P6.0bo V: rejections" begin
    attempt(name, op = p60bo_op()) = () -> PottsProblem(p60bo_build(name), op, (0, 1))
    @test p60bo_clear(attempt(:P60boWritten), "overdetermined", "Vt")
    @test p60bo_clear(attempt(:P60boWrittenZero), "overdetermined", "Vt")
    @test p60bo_clear(attempt(:P60boTarget, p60bo_op(:Vt => [5.0, 5.0])), "overdetermined", "Vt")
    @test p60bo_clear(attempt(:P60boAlg, p60bo_op(:x => [2.0, 3.0], :xd => [1.0, 1.0])), "overdetermined", "xd")
    @test p60bo_clear_any(attempt(:P60boUnder), "underdetermined", ("alpha_u", "beta_u"))
    @test p60bo_clear(attempt(:P60boRootless), "initialization", "rootless")
end

# ---------------------------------------------------------------------------------------
# X. Cross-entity equations are not MTK's

@testset "P6.0bo X: cross-entity initialization is refused until P6.4a" begin
    attempt(name) = () -> PottsProblem(p60bo_build(name), p60bo_op(), (0, 1))
    @test p60bo_clear(attempt(:P60boCross), "initialization", "partner")
    @test p60bo_clear(attempt(:P60boGather), "initialization", "xgather")
    @test p60bo_clear(attempt(:P60boField), "initialization", "cfield")
end

# ---------------------------------------------------------------------------------------
# U. Unchanged

@testset "P6.0bo U: no initialization equations, no templates, declared values" begin
    c = mtkcompile(p60bo_build(:P60boNone))
    @test p60bo_init(c, :cell) === nothing && p60bo_init(c, :model) === nothing
    prob = p60bo_prob(:P60boNone)
    @test p60bo_u0(prob, :Vt) == [5.0, 5.0] && p60bo_u0(prob, :w) == [0.0, 0.0]
    @test p60bo_u0(p60bo_prob(:P60boNone, p60bo_op(:Vt => [1.0, 2.0])), :Vt) == [1.0, 2.0]
end

@testset "P6.0bo U: published models have no initialization template" begin
    @testset "$label" for (label, build) in P60BO_PUBLISHED
        cs = mtkcompile(build())
        @test p60bo_init(cs, :cell) === nothing
        @test p60bo_init(cs, :model) === nothing
    end
end

# ---------------------------------------------------------------------------------------
# N. Negative controls for the detectors

@testset "P6.0bo N: detectors can fail" begin
    t = Potts.t
    P60BO_M.@variables xs_plain(t) = 1.0
    plain = P60BO_M.System([Potts.D(xs_plain) ~ -xs_plain], t; name = :plain)
    @test isempty(P60BO_M.initialization_equations(plain))
    withinit = P60BO_M.System([Potts.D(xs_plain) ~ -xs_plain], t; name = :plain, initialization_eqs = [xs_plain ~ 2.0])
    @test length(P60BO_M.initialization_equations(withinit)) == 1
    @test !p60bo_close([33.0, 26.0], [32.0, 26.0])
    @test !p60bo_clear(() -> 1, "overdetermined")
    @test !p60bo_clear(() -> throw(ArgumentError("something else")), "overdetermined")
    @test p60bo_clear(() -> throw(ArgumentError("x is overdetermined")), "overdetermined")
    @test !p60bo_clear(() -> throw(ErrorException("overdetermined")), "overdetermined")
end
