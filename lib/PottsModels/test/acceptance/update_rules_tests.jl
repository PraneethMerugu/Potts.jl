# `update_rules_tests.jl` (ROADMAP Phase 6, step 0; D-159 as amended by D-162; research/mtk-native-plan.md
# §5, §6): a model's update rules as an MTK-inspectable object. A public
# `Potts.updates(sys)` lists every `@before_mcs`, `@after_mcs` and `@on_copy` statement as
# written: its phase, its scope (the declared scope of the variable it writes), its cadence
# `Every(n)` and its `Equation` in ModelingToolkit's `Pre` form. This is the D-162 sentence
# "a model's update rules are Symbolics equations in ModelingToolkit's `Pre` form that MTK's
# generic tools can inspect". Events as MTK `SymbolicDiscreteCallback`s are later work, not
# this item's (D-162 ruling 2): MTK's `discrete_events`/`continuous_events` stay empty.
# Decision: D-1xx (`update_rules_tests.jl`; the coordinator numbers it).
#
# The contract pinned here (public API only; the element type, storage and caching are the
# implementer's):
#  A. `Potts.updates` and `Potts.Every` are public names of Potts with docstrings (`Every`
#     is the cadence value `updates` returns, so it is public with it).
#  U. `updates(sys)` is an `AbstractVector`, one element per update statement, in
#     declaration order across all three phases (not grouped by phase or scope). Each
#     element `u` has the properties
#       - `u.phase`: `:before_mcs`, `:after_mcs` or `:on_copy`;
#       - `u.scope`: `:cell`, `:site`, `:model` or `:edge`, the declared scope of the
#         variable written (for `@on_copy x[target] ~ …` the scope of `x`);
#       - `u.every`: the cadence, `Potts.Every(n)` (`Every(1)` when none is written, and
#         always for `@on_copy`);
#       - `u.eq`: a Symbolics `Equation`, the statement as written in MTK `Pre` form: the
#         written variable on the left (at `target`/`new` for `@on_copy`), `Pre(x)` where the
#         user wrote it, and a compound write `x += e` as `x ~ Pre(x) + e` (D-042).
#     Oracles (fixture All, every phase and scope): the phase/scope/cadence table as
#     written; per statement, exactly the symbols written; exactly the `Pre` arguments
#     written (MTK's own `Pre` operator); the value of the right-hand side at fixed points
#     (MTK's generic `Symbolics.substitute`, `Pre(x)` substituted first); for the plain
#     statements, structural equality with the equation rebuilt from the system's declared
#     symbols (`sys.x`, the complete inner System's; D-256) and
#     `ModelingToolkitBase.Pre`.
#  F. The forms: `updates` is the same (`isequal` equations, equal phase/scope/cadence) on
#     the plain system and `mtkcompile(sys)` (the authored model, D-160), and after
#     `extend` it lists the merged model's statements (MTK's `complete` of a
#     `PottsSystem` is refused since C4: the model already wraps a complete System). With
#     `@components`, the compiled system reports the statements as written (reading the
#     component's coupled parameter and observed quantity), not the lowered ones; the
#     negative control is `.sys`, the lowered model, whose statement differs. An edge-scope
#     update is pinned on the plain form only (`mtkcompile` of an edge update is a
#     pre-existing gap, not this item's).
#  P. Published models: their statements as declared (Wortel act: `@on_copy` at site scope,
#     then `@after_mcs` at site scope; Akeeb: two cell-scope `@after_mcs`; OpenVT growing
#     monolayer: one cell-scope `@after_mcs`; OpenVT reference: one cell-scope
#     `@before_mcs`, two cell-scope `@after_mcs`); every other published model has none.
#     Compiled equals authored on each.
#  N. Negative controls and regression guards (pass before this item):
#     - a model without updates returns an empty vector (also compiled);
#     - MTK's `discrete_events` and `continuous_events` of `Potts.inner(sys)` are empty on
#       every form of every fixture and published model: UNTIL symbolic events land, which store `@discrete_events`/
#       `@terminate` as `SymbolicDiscreteCallback`s (D-162 ruling 2) and amends this
#       check. Per-entity, per-copy and structural rules are never callbacks;
#     - `PottsSweepSpec` is still present, and `ODEProblem`/`JumpProblem` still refuse
#       naming `PottsProblem` (D-137 rule 5);
#     - behaviour (a timing oracle, not a numeric pin, D-158): a model-scope
#       `@after_mcs Every(5)` counter fires after MCS 0, 5 and 10, i.e. its saved value
#       steps at t = 1, 6, 11 over 12 MCS, and a `@before_mcs Every(5)` one at the same
#       saves; `updates` reports both as `Every(5)`.
#
# Not pinned here: generated code and fingerprints (byte-identical; `updates` never enters
# code, D-137 rule 2: the `abstract_system_tests.jl` and fingerprint suites check that); the element type; the
# order of `extend`'s merge (compared as a multiset); field-variable updates' scope.
#
# On fe7269cf (PC): 133 pass, 4 fail and 23 error of 160. Every error is an UndefVarError
# for `updates`; the failures are `updates`/`Every` not public or documented and the timing
# set's `updates` check. The events, payload, refusal and timing controls pass. A stub
# (`updates` from the stored statements, `Every` made public) passes 261/261.

@testsetup module UpdateRulesSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
include(joinpath(@__DIR__, "..", "fixtures.jl"))
using Potts: CorePotts
const UPDATE_M = Potts.ModelingToolkitBase
const UPDATE_S = Potts.Symbolics
const UPDATE_SU = Potts.SymbolicUtils
const SII = Potts.SymbolicIndexingInterface
update_updates(s) = Potts.updates(s)
update_name(x) = SII.getname(x)
# the names of the symbols in `e` (`x(t)` is `x`; through `Pre`, indexing and calls)
function update_names(e)
    out = Set{Symbol}()
    walk(y) = (
        y = UPDATE_S.unwrap(y);
        y isa UPDATE_SU.BasicSymbolic || return;
        if UPDATE_SU.issym(y)
            push!(out, update_name(y))
        elseif UPDATE_SU.iscall(y)
            op = UPDATE_SU.operation(y)
            op isa UPDATE_SU.BasicSymbolic && UPDATE_SU.issym(op) ? push!(out, update_name(op)) :
                foreach(walk, UPDATE_SU.arguments(y))
        end
    )
    walk(e)
    return out
end
isPre(y) = UPDATE_SU.iscall(y) && UPDATE_SU.operation(y) isa UPDATE_M.Pre
# the names of the variables read through MTK's `Pre` in `e`
function pre_args(e)
    out = Set{Symbol}()
    walk(y) = (
        y = UPDATE_S.unwrap(y);
        y isa UPDATE_SU.BasicSymbolic || return;
        isPre(y) && union!(out, update_names(UPDATE_SU.arguments(y)[1]));
        UPDATE_SU.iscall(y) && foreach(walk, UPDATE_SU.arguments(y))
    )
    walk(e)
    return out
end
# the value of `e` with `Pre(x)` => vals[Symbol(:Pre_, x)] first, then every symbol by name
function update_eval(e, vals::AbstractDict{Symbol})
    x = UPDATE_S.unwrap(e)
    pre = Dict{Any, Any}()
    walk(y) = (
        y = UPDATE_S.unwrap(y);
        y isa UPDATE_SU.BasicSymbolic || return;
        if isPre(y)
            pre[y] = vals[Symbol(:Pre_, only(update_names(UPDATE_SU.arguments(y)[1])))]
        elseif UPDATE_SU.iscall(y)
            foreach(walk, UPDATE_SU.arguments(y))
        end
    )
    walk(x)
    isempty(pre) || (x = UPDATE_S.unwrap(UPDATE_S.substitute(x, pre)))
    vs = UPDATE_S.get_variables(x)
    isempty(vs) || (x = UPDATE_S.unwrap(UPDATE_S.substitute(x, Dict{Any, Any}(v => vals[update_name(v)] for v in vs))))
    v = UPDATE_S.value(x)
    # a numeric term left unfolded by `substitute` (e.g. `ifelse(3.0 != 0, 2.0, 0.0)`): evaluate it
    return Float64(v isa Number ? v : Core.eval(@__MODULE__, UPDATE_S.toexpr(v)))
end
row(u) = (u.phase, u.scope, u.every)
same(a, b) = length(a) == length(b) &&
    all(i -> row(a[i]) == row(b[i]) && isequal(a[i].eq, b[i].eq), eachindex(a, b))
clear(f, words...) = try
    f()
    false
catch err
    err isa Union{ArgumentError, Potts.PottsCompileError} &&
        (isempty(words) || occursin(first(words), sprint(showerror, err)))
end
# ---------------------------------------------------------------------------------------
# Fixtures

# every phase and the cell, site and model scopes, with cadences and a compound write; the
# phases are interleaved so declaration order differs from any grouping by phase or scope
@potts_model All begin
    @kinds medium A
    @parameters begin
        α = 0.5
        β = 2.0
        T = 1.0
    end
    @variables begin
        w(cell) = 1.0
        g(cell) = 0.0
        s(site) = 0.0
        m(model) = 0.0
        k(model) = 0.0
    end
    @lattice Lattice((8, 8))
    @energy begin
        cells(A) => (volume - 9.0)^2
        contacts => 1.0
    end
    @before_mcs m ~ Pre(m) + α
    @after_mcs Every(5) w ~ Pre(w) + β * volume
    @after_mcs begin
        g += α
        s ~ Pre(s) * 0.5
    end
    @on_copy s[target] ~ ifelse(new != 0, β, 0.0)
    @on_copy w[new] ~ Pre(w[new]) + 1
    @before_mcs Every(3) k ~ Pre(k) + m
    @sweep Metropolis(; temperature = T)
end
# the oracle table for All: (phase, scope, n, symbols written, Pre arguments, rhs value
# at POINT or `nothing` where the rhs indexes at a proposal site)
const TABLE = [
    (:before_mcs, :model, 1, Set([:m, :α]), Set([:m]), 3.0 + 0.5),
    (:after_mcs, :cell, 5, Set([:w, :β, :volume]), Set([:w]), 7.0 + 2.0 * 9.0),
    (:after_mcs, :cell, 1, Set([:g, :α]), Set([:g]), 4.0 + 0.5),
    (:after_mcs, :site, 1, Set([:s]), Set([:s]), 6.0 * 0.5),
    (:on_copy, :site, 1, Set([:s, :target, :new, :β]), Set{Symbol}(), nothing),
    (:on_copy, :cell, 1, Set([:w, :new]), Set([:w]), nothing),
    (:before_mcs, :model, 3, Set([:k, :m]), Set([:k]), 5.0 + 1.5),
]
const POINT = Dict(
    :α => 0.5, :β => 2.0, :volume => 9.0, :m => 1.5, :new => 3.0,
    :Pre_m => 3.0, :Pre_w => 7.0, :Pre_g => 4.0, :Pre_s => 6.0, :Pre_k => 5.0
)
# no updates at all
@potts_model None begin
    @kinds medium A
    @parameters T = 1.0
    @lattice Lattice((8, 8))
    @energy cells(A) => (volume - 9.0)^2
    @sweep Metropolis(; temperature = T)
end
# an extension with one update of its own (for `extend`)
@potts_model Extra begin
    @kinds medium A
    @parameters ρ = 0.25
    @variables h(cell) = 0.0
    @lattice Lattice((8, 8))
    @energy cells(A) => ρ * volume
    @after_mcs Every(2) h ~ Pre(h) + ρ
    @sweep Metropolis(; temperature = 1.0)
end
# an edge-scope update (a `@relationship` variable)
@potts_model Edge begin
    @kinds medium blob
    @parameters T = 1.0
    @variables rest(edge) = 12.0
    @relationship bond(cell, cell) capacity = 1
    @lattice Lattice((20, 20); neighborhood = Moore(1))
    @energy begin
        cells(blob) => (volume - 36.0)^2
        contacts => 16.0
        edges(bond) => (distance - rest)^2
    end
    @after_mcs rest ~ Pre(rest) * 0.9
    @sweep Metropolis(; temperature = T)
end
# a component whose coupled parameter and observed quantity an update reads
const clock_time = Potts.t
UPDATE_M.@variables update_cm(clock_time) = 0.0 update_cy(clock_time)
UPDATE_M.@parameters update_cτ = 20.0 update_cr = 1.0
@named update_clock = UPDATE_M.System([Potts.D(update_cm) ~ update_cr / update_cτ, update_cy ~ 3update_cm], clock_time)
@potts_model Comp begin
    @kinds medium A
    @parameters T = 1.0
    @variables w(cell) = 0.0
    @components cells(A) clock = update_clock
    @equations clock.update_cr ~ volume / 25
    @lattice Lattice((12, 12))
    @energy begin
        cells(A) => (volume - 9.0)^2
        contacts => 1.0
    end
    @after_mcs w ~ Pre(w) + clock.update_cy + clock.update_cr
    @sweep Metropolis(; temperature = T)
end
# the timing fixture: model-scope counters only
@potts_model Timing begin
    @kinds medium A
    @parameters T = 1.0
    @variables begin
        n_after(model) = 0.0
        n_before(model) = 0.0
    end
    @lattice Lattice((8, 8))
    @energy contacts => 1.0
    @after_mcs Every(5) n_after ~ Pre(n_after) + 1
    @before_mcs Every(5) n_before ~ Pre(n_before) + 1
    @sweep Metropolis(; temperature = T)
end
# every published model (small lattices; construction only), with its updates as declared
# in lib/PottsModels/src: (phase, scope, n, the written variable)
const MODELS = [
    ("GranerGlazier", () -> GranerGlazier(; name = :gg), []),
    (
        "WortelAct", () -> WortelAct(; name = :act, lattice = (8, 8)),
        [(:on_copy, :site, 1, :act), (:after_mcs, :site, 1, :act)],
    ),
    (
        "WortelAct connected", () -> WortelAct(; name = :act, lattice = (8, 8), connected = true),
        [(:on_copy, :site, 1, :act), (:after_mcs, :site, 1, :act)],
    ),
    ("MerksVasculogenesis", () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8)), []),
    (
        "MerksVasculogenesis contact-inhibited",
        () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8), contact_inhibited = true), [],
    ),
    ("Merks2006", () -> Merks2006(; name = :m6, lattice = (16, 16)), []),
    ("Merks2006 hard", () -> Merks2006(; name = :m6, lattice = (16, 16), rule = :hard), []),
    ("Merks2008", () -> Merks2008(; name = :m8, lattice = (16, 16)), []),
    ("Merks2008 extension only", () -> Merks2008(; name = :m8, lattice = (16, 16), mode = :extension_only), []),
    ("SingleDivisionFixture", () -> SingleDivisionFixture(; name = :fixture), []),
    (
        "OpenVTGrowingMonolayer", () -> OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)),
        [(:after_mcs, :cell, 1, :V_target)],
    ),
    (
        "AkeebInvasion", () -> AkeebInvasion(; name = :akeeb, lattice = (60, 40)),
        [(:after_mcs, :cell, 1, :V_target), (:after_mcs, :cell, 1, :clock)],
    ),
    ("OpenVTChain", () -> OpenVTChain(; name = :chain), []),
    (
        "OpenVTReferenceMonolayer", () -> OpenVTReferenceMonolayer(; name = :ref, lattice = (24, 24)),
        [(:before_mcs, :cell, 1, :X), (:after_mcs, :cell, 1, :f), (:after_mcs, :cell, 1, :A_star)],
    ),
]
# the written variable of a statement: the left side's variable (at a site for `@on_copy`)
update_target(u) = only(setdiff(update_names(u.eq.lhs), (:target, :source, :new, :old)))
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "update rules A: public names with docstrings" setup = [UpdateRulesSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # A. Public names
    @testset "update rules A: public names with docstrings" begin
        for n in (:updates, :Every)
            @test isdefined(Potts, n) && Base.ispublic(Potts, n)
            @test isdefined(Potts, n) && Base.Docs.hasdoc(Potts, n)
        end
    end
end

@testitem "update rules U: phase, scope and cadence in declaration order" setup = [UpdateRulesSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # U. The fixture's statements as written
    @testset "update rules U: phase, scope and cadence in declaration order" begin
        U = update_updates(All(; name = :pa))
        @test U isa AbstractVector && length(U) == length(TABLE)
        @test [u.phase for u in U] == [r[1] for r in TABLE]
        @test [u.scope for u in U] == [r[2] for r in TABLE]
        @test [u.every for u in U] == [Potts.Every(r[3]) for r in TABLE]
        @test all(u -> u.every isa Potts.Every, U)
        @test all(u -> u.eq isa UPDATE_S.Equation, U)
        # the written variables, in order
        @test [update_target(u) for u in U] == [:m, :w, :g, :s, :s, :w, :k]
    end
end

@testitem "update rules U: the equations as written, in Pre form" setup = [UpdateRulesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "update rules U: the equations as written, in Pre form" begin
        U = update_updates(All(; name = :pa))
        @testset "statement $i" for (i, (u, r)) in enumerate(zip(U, TABLE))
            names, pres, val = r[4], r[5], r[6]
            @test union(update_names(u.eq.lhs), update_names(u.eq.rhs)) == names    # exactly the symbols written
            @test pre_args(u.eq.rhs) == pres                                 # Pre exactly where written
            @test isempty(pre_args(u.eq.lhs))                                # the new value on the left
            val === nothing || @test isapprox(update_eval(u.eq.rhs, POINT), val; rtol = 1.0e-12)
        end
        # structural: rebuilt from the system's declared symbols and MTK's `Pre`
        c = All(; name = :pa)
        Pre = UPDATE_M.Pre
        uw(x) = UPDATE_S.unwrap(x)
        @test isequal(uw(U[1].eq.lhs), uw(c.m)) && isequal(uw(U[1].eq.rhs), uw(Pre(c.m) + c.α))
        @test isequal(uw(U[3].eq.lhs), uw(c.g)) && isequal(uw(U[3].eq.rhs), uw(Pre(c.g) + c.α))   # `g += α`
        @test isequal(uw(U[4].eq.lhs), uw(c.s)) && isequal(uw(U[4].eq.rhs), uw(Pre(c.s) * 0.5))
        @test isequal(uw(U[7].eq.lhs), uw(c.k)) && isequal(uw(U[7].eq.rhs), uw(Pre(c.k) + c.m))   # bare `m`: its new value
        # the on-copy rhs: β at a copy that is not to medium, 0 at one that is
        @test update_eval(U[5].eq.rhs, merge(POINT, Dict(:new => 3.0))) == 2.0
        @test update_eval(U[5].eq.rhs, merge(POINT, Dict(:new => 0.0))) == 0.0
        # negative control for the oracle: a statement with its Pre dropped fails it
        @test pre_args(UPDATE_S.unwrap(c.m + c.α)) != TABLE[1][5]
    end
end

@testitem "update rules F: plain and mtkcompile agree" setup = [UpdateRulesSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # F. The four forms
    @testset "update rules F: plain and mtkcompile agree" begin
        sys = All(; name = :pa)
        U = update_updates(sys)
        cs = mtkcompile(sys)
        @test same(update_updates(cs), U)
    end
end

@testitem "update rules F: extend lists the merged model's statements" setup = [UpdateRulesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "update rules F: extend lists the merged model's statements" begin
        base = All(; name = :pa)
        extra = Extra(; name = :extra)
        ext = extend(extra, base)
        U = update_updates(ext)
        @test length(U) == length(TABLE) + 1
        key(u) = (u.phase, u.scope, u.every, string(u.eq))
        @test sort(map(key, U); by = string) == sort(map(key, [update_updates(base); update_updates(extra)]); by = string)
        h = only(filter(u -> update_target(u) === :h, U))
        @test h.phase === :after_mcs && h.scope === :cell && h.every == Potts.Every(2)
        @test pre_args(h.eq.rhs) == Set([:h]) && update_eval(h.eq.rhs, Dict(:Pre_h => 1.0, :ρ => 0.25)) == 1.25
        @test same(update_updates(mtkcompile(ext)), U)
    end
end

@testitem "update rules F: an edge-scope update" setup = [UpdateRulesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "update rules F: an edge-scope update" begin
        sys = Edge(; name = :pe)
        U = update_updates(sys)
        @test length(U) == 1
        u = only(U)
        @test u.phase === :after_mcs && u.scope === :edge && u.every == Potts.Every(1)
        @test update_target(u) === :rest && pre_args(u.eq.rhs) == Set([:rest])
        @test update_eval(u.eq.rhs, Dict(:Pre_rest => 10.0)) == 9.0
    end
end

@testitem "update rules F: a compiled model with components reports the statement as written" setup = [UpdateRulesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "update rules F: a compiled model with components reports the statement as written" begin
        sys = Comp(; name = :pc)
        cs = mtkcompile(sys)
        U, Uc = update_updates(sys), update_updates(cs)
        @test length(U) == 1 && same(U, Uc)
        u = only(U)
        @test u.phase === :after_mcs && u.scope === :cell && u.every == Potts.Every(1)
        # it reads the component's coupled parameter and observed quantity as written
        nm = string.(collect(update_names(u.eq.rhs)))
        @test any(n -> occursin("update_cr", n), nm) && any(n -> occursin("update_cy", n), nm)
        @test !any(n -> n == "volume" || occursin("update_cm", n), nm)
        # negative control: `.sys` is the lowered model (cr ↦ volume/25, cy ↦ 3cm)
        @test !same(update_updates(getfield(cs, :sys)), U)
    end
end

@testitem "update rules P: published models list their updates as declared" setup = [UpdateRulesSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # P. Published models
    @testset "update rules P: published models list their updates as declared" begin
        @testset "$label" for (label, build, want) in MODELS
            sys = build()
            U = update_updates(sys)
            @test U isa AbstractVector && length(U) == length(want)
            @test [(u.phase, u.scope, u.every, update_target(u)) for u in U] ==
                [(w[1], w[2], Potts.Every(w[3]), w[4]) for w in want]
            @test all(u -> u.eq isa UPDATE_S.Equation, U)
            # every symbol is a parameter or unknown of the system (MTK's accessors) or a built-in
            declared = Set{Symbol}(update_name(x) for x in [UPDATE_M.parameters(sys); UPDATE_M.unknowns(sys)])
            builtins = Set(
                [
                    :volume, :surface, :kind, :neighbor_kind, :owner, :neighbor_owner, :target, :source, :new, :old,
                    :mcs, :medium, :cell, :leader, :follower,
                ]
            )
            for u in U
                extra = setdiff(union(update_names(u.eq.lhs), update_names(u.eq.rhs)), declared, builtins)
                isempty(extra) || @info "update rules: $label update reads $(collect(extra))"
            end
            @test same(update_updates(mtkcompile(sys)), U)
        end
        # Wortel as written: `act[target] ~ ifelse(new != 0, max_act, 0.0)`, `act ~ max(Pre(act) - 1, 0)`
        Uw = update_updates(WortelAct(; name = :act, lattice = (8, 8)))
        @test isempty(pre_args(Uw[1].eq.rhs)) && update_names(Uw[1].eq.rhs) == Set([:new, :max_act])
        @test update_eval(Uw[1].eq.rhs, Dict(:new => 2.0, :max_act => 20.0)) == 20.0
        @test pre_args(Uw[2].eq.rhs) == Set([:act])
        @test update_eval(Uw[2].eq.rhs, Dict(:Pre_act => 0.5)) == 0.0 && update_eval(Uw[2].eq.rhs, Dict(:Pre_act => 7.0)) == 6.0
        # OpenVT growing monolayer: V_target grows by A₀/τ while volume ≥ β·Pre(V_target)
        Uo = only(update_updates(OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24))))
        @test pre_args(Uo.eq.rhs) == Set([:V_target])
        pt = Dict(:Pre_V_target => 100.0, :A₀ => 84.0, :τ => 84.0, :β => 0.5, :volume => 60.0)
        @test update_eval(Uo.eq.rhs, pt) == 101.0
        @test update_eval(Uo.eq.rhs, merge(pt, Dict(:volume => 40.0))) == 100.0
        # Akeeb: the clock runs once started
        Ua = update_updates(AkeebInvasion(; name = :akeeb, lattice = (60, 40)))
        @test update_eval(Ua[2].eq.rhs, Dict(:Pre_clock => 3.0)) == 4.0 && update_eval(Ua[2].eq.rhs, Dict(:Pre_clock => -1.0)) == -1.0
    end
end

@testitem "update rules N: a model without updates" setup = [UpdateRulesSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # N. Negative controls and regression guards
    @testset "update rules N: a model without updates" begin
        sys = None(; name = :none)
        @test isempty(update_updates(sys)) && update_updates(sys) isa AbstractVector
        @test isempty(update_updates(mtkcompile(sys)))
    end
end

@testitem "update rules N: no MTK events until" setup = [UpdateRulesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "update rules N: no MTK events until" begin
        # MTK's event accessors read the complete System a `PottsSystem` wraps (D-256), for
        # the authored model and the compiled model's `.sys` (D-137)
        forms(s) = (Potts.inner(s), Potts.inner(getfield(mtkcompile(s), :sys)))
        fixtures = [
            All(; name = :pa), None(; name = :none), Comp(; name = :pc),
            Timing(; name = :pt), extend(Extra(; name = :extra), All(; name = :pa)),
        ]
        for sys in [fixtures; [b() for (_, b, _) in MODELS]], s in forms(sys)
            @test isempty(UPDATE_M.discrete_events(s))
            @test isempty(UPDATE_M.continuous_events(s))
        end
        e = Edge(; name = :pe)
        @test isempty(UPDATE_M.discrete_events(Potts.inner(e))) && isempty(UPDATE_M.continuous_events(Potts.inner(e)))
    end
end

@testitem "update rules N: the sweep payload and the rule 5 refusals are unaffected" setup = [UpdateRulesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "update rules N: the sweep payload and the rule 5 refusals are unaffected" begin
        for sys in (All(; name = :pa), Comp(; name = :pc), WortelAct(; name = :act, lattice = (8, 8)))
            @test UPDATE_M.hasmetadata(Potts.inner(sys), Potts.PottsSweepSpec)
            @test UPDATE_M.getmetadata(mtkcompile(sys), Potts.PottsSweepSpec, nothing) isa Potts.PottsSweepSpec
            @test clear(() -> UPDATE_M.ODEProblem(sys, [], (0.0, 1.0)), "ODEProblem", "PottsProblem")
            @test clear(() -> UPDATE_M.JumpProblem(sys, [], (0.0, 1.0)), "JumpProblem", "PottsProblem")
        end
    end
end

@testitem "update rules N: update timing (behaviour unchanged)" setup = [UpdateRulesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "update rules N: update timing (behaviour unchanged)" begin
        sys = Timing(; name = :pt)
        σ = zeros(Int32, 8, 8)
        σ[3:5, 3:5] .= 1
        prob = PottsProblem(sys, [ownership => σ, kind => [:A]], (0, 12))
        sol = solve(prob, SequentialCPM(); saveat = 1)
        @test sol.t == 0:12
        steps(v) = [sol.t[i + 1] for i in 1:(length(v) - 1) if v[i + 1] != v[i]]
        @test steps(sol[sys.n_after]) == [1, 6, 11]          # after MCS 0, 5, 10 (mcs % 5 == 0)
        @test steps(sol[sys.n_before]) == [1, 6, 11]         # before MCS 0, 5, 10; seen at the next save
        @test sol[sys.n_after][end] == 3.0 && sol[sys.n_before][end] == 3.0
        # negative control: an MTK period of 5 would fire at t = 5, 10
        @test steps(sol[sys.n_after]) != [5, 10]
        # and `updates` reports both cadences as written
        if isdefined(Potts, :updates)
            U = Potts.updates(sys)
            @test [(u.phase, u.scope, u.every) for u in U] ==
                [(:after_mcs, :model, Potts.Every(5)), (:before_mcs, :model, Potts.Every(5))]
        else
            @test isdefined(Potts, :updates)
        end
    end
end
