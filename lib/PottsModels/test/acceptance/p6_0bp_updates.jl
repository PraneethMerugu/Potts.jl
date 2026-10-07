# P6.0bp (ROADMAP Phase 6, step 0; D-159 as amended by D-162; research/mtk-native-plan.md
# §5, §6): a model's update rules as an MTK-inspectable object. A public
# `Potts.updates(sys)` lists every `@before_mcs`, `@after_mcs` and `@on_copy` statement as
# written: its phase, its scope (the declared scope of the variable it writes), its cadence
# `Every(n)` and its `Equation` in ModelingToolkit's `Pre` form. This is the D-162 sentence
# "a model's update rules are Symbolics equations in ModelingToolkit's `Pre` form that MTK's
# generic tools can inspect". Events as MTK `SymbolicDiscreteCallback`s are P6.4c's, not
# this item's (D-162 ruling 2): MTK's `discrete_events`/`continuous_events` stay empty.
# Decision: D-1xx (P6.0bp; the coordinator numbers it). Frozen (AUTONOMY §7.3).
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
#     Oracles (fixture P60bpAll, every phase and scope): the phase/scope/cadence table as
#     written; per statement, exactly the symbols written; exactly the `Pre` arguments
#     written (MTK's own `Pre` operator); the value of the right-hand side at fixed points
#     (MTK's generic `Symbolics.substitute`, `Pre(x)` substituted first); for the plain
#     statements, structural equality with the equation rebuilt from the completed system's
#     declared symbols and `ModelingToolkitBase.Pre`.
#  F. The four forms: `updates` is the same (`isequal` equations, equal phase/scope/
#     cadence) on the plain system, `complete(sys)`, and `mtkcompile(sys)` (the authored
#     model, D-160), and after `extend` it lists the merged model's statements. With
#     `@components`, the compiled system reports the statements as written (reading the
#     component's coupled parameter and observed quantity), not the lowered ones; the
#     negative control is `.sys`, the lowered model, whose statement differs. An edge-scope
#     update is pinned on the plain and completed forms only (`mtkcompile` of an edge
#     update is a pre-existing gap, not this item's).
#  P. Published models: their statements as declared (Wortel act: `@on_copy` at site scope,
#     then `@after_mcs` at site scope; Akeeb: two cell-scope `@after_mcs`; OpenVT growing
#     monolayer: one cell-scope `@after_mcs`; OpenVT reference: one cell-scope
#     `@before_mcs`, two cell-scope `@after_mcs`); every other published model has none.
#     Compiled equals authored on each.
#  N. Negative controls and regression guards (pass before this item):
#     - a model without updates returns an empty vector (also compiled);
#     - MTK's `discrete_events(sys)` and `continuous_events(sys)` are empty on every form of
#       every fixture and published model: UNTIL P6.4c, which stores `@discrete_events`/
#       `@terminate` as `SymbolicDiscreteCallback`s (D-162 ruling 2) and re-freezes this
#       check. Per-entity, per-copy and structural rules are never callbacks;
#     - `PottsSweepSpec` is still present, and `ODEProblem`/`JumpProblem` still refuse
#       naming `PottsProblem` (D-137 rule 5);
#     - behaviour (a timing oracle, not a numeric pin, D-158): a model-scope
#       `@after_mcs Every(5)` counter fires after MCS 0, 5 and 10, i.e. its saved value
#       steps at t = 1, 6, 11 over 12 MCS, and a `@before_mcs Every(5)` one at the same
#       saves; `updates` reports both as `Every(5)`.
#
# Not pinned here: generated code and fingerprints (byte-identical; `updates` never enters
# code, D-137 rule 2: the p6_0o and fingerprint suites check that); the element type; the
# order of `extend`'s merge (compared as a multiset); field-variable updates' scope.
#
# On fe7269cf every A/U/F/P target errors (`Potts.updates` is undefined, `Potts.Every` is
# not public); the N controls pass.
using Potts: CorePotts

const P60BP_M = Potts.ModelingToolkitBase
const P60BP_S = Potts.Symbolics
const P60BP_SU = Potts.SymbolicUtils
const P60BP_SII = Potts.SymbolicIndexingInterface

p60bp_updates(s) = Potts.updates(s)
p60bp_name(x) = P60BP_SII.getname(x)
# the names of the symbols in `e` (`x(t)` is `x`; through `Pre`, indexing and calls)
function p60bp_names(e)
    out = Set{Symbol}()
    walk(y) = (y = P60BP_S.unwrap(y);
               y isa P60BP_SU.BasicSymbolic || return;
               if P60BP_SU.issym(y)
                   push!(out, p60bp_name(y))
               elseif P60BP_SU.iscall(y)
                   op = P60BP_SU.operation(y)
                   op isa P60BP_SU.BasicSymbolic && P60BP_SU.issym(op) ? push!(out, p60bp_name(op)) :
                   foreach(walk, P60BP_SU.arguments(y))
               end)
    walk(e)
    return out
end
p60bp_isPre(y) = P60BP_SU.iscall(y) && P60BP_SU.operation(y) isa P60BP_M.Pre
# the names of the variables read through MTK's `Pre` in `e`
function p60bp_pre_args(e)
    out = Set{Symbol}()
    walk(y) = (y = P60BP_S.unwrap(y);
               y isa P60BP_SU.BasicSymbolic || return;
               p60bp_isPre(y) && union!(out, p60bp_names(P60BP_SU.arguments(y)[1]));
               P60BP_SU.iscall(y) && foreach(walk, P60BP_SU.arguments(y)))
    walk(e)
    return out
end
# the value of `e` with `Pre(x)` => vals[Symbol(:Pre_, x)] first, then every symbol by name
function p60bp_eval(e, vals::AbstractDict{Symbol})
    x = P60BP_S.unwrap(e)
    pre = Dict{Any, Any}()
    walk(y) = (y = P60BP_S.unwrap(y);
               y isa P60BP_SU.BasicSymbolic || return;
               if p60bp_isPre(y)
                   pre[y] = vals[Symbol(:Pre_, only(p60bp_names(P60BP_SU.arguments(y)[1])))]
               elseif P60BP_SU.iscall(y)
                   foreach(walk, P60BP_SU.arguments(y))
               end)
    walk(x)
    isempty(pre) || (x = P60BP_S.unwrap(P60BP_S.substitute(x, pre)))
    vs = P60BP_S.get_variables(x)
    isempty(vs) || (x = P60BP_S.unwrap(P60BP_S.substitute(x, Dict{Any, Any}(v => vals[p60bp_name(v)] for v in vs))))
    v = P60BP_S.value(x)
    # a numeric term left unfolded by `substitute` (e.g. `ifelse(3.0 != 0, 2.0, 0.0)`): evaluate it
    return Float64(v isa Number ? v : Core.eval(@__MODULE__, P60BP_S.toexpr(v)))
end
p60bp_row(u) = (u.phase, u.scope, u.every)
p60bp_same(a, b) = length(a) == length(b) &&
                   all(i -> p60bp_row(a[i]) == p60bp_row(b[i]) && isequal(a[i].eq, b[i].eq), eachindex(a, b))
p60bp_clear(f, words...) = try
    f()
    false
catch err
    err isa ArgumentError && all(w -> occursin(w, sprint(showerror, err)), words)
end

# ---------------------------------------------------------------------------------------
# Fixtures

# every phase and the cell, site and model scopes, with cadences and a compound write; the
# phases are interleaved so declaration order differs from any grouping by phase or scope
@potts_model P60bpAll begin
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

# the oracle table for P60bpAll: (phase, scope, n, symbols written, Pre arguments, rhs value
# at P60BP_POINT or `nothing` where the rhs indexes at a proposal site)
const P60BP_TABLE = [
    (:before_mcs, :model, 1, Set([:m, :α]), Set([:m]), 3.0 + 0.5),
    (:after_mcs, :cell, 5, Set([:w, :β, :volume]), Set([:w]), 7.0 + 2.0 * 9.0),
    (:after_mcs, :cell, 1, Set([:g, :α]), Set([:g]), 4.0 + 0.5),
    (:after_mcs, :site, 1, Set([:s]), Set([:s]), 6.0 * 0.5),
    (:on_copy, :site, 1, Set([:s, :target, :new, :β]), Set{Symbol}(), nothing),
    (:on_copy, :cell, 1, Set([:w, :new]), Set([:w]), nothing),
    (:before_mcs, :model, 3, Set([:k, :m]), Set([:k]), 5.0 + 1.5),
]
const P60BP_POINT = Dict(:α => 0.5, :β => 2.0, :volume => 9.0, :m => 1.5, :new => 3.0,
    :Pre_m => 3.0, :Pre_w => 7.0, :Pre_g => 4.0, :Pre_s => 6.0, :Pre_k => 5.0)

# no updates at all
@potts_model P60bpNone begin
    @kinds medium A
    @parameters T = 1.0
    @lattice Lattice((8, 8))
    @energy cells(A) => (volume - 9.0)^2
    @sweep Metropolis(; temperature = T)
end

# an extension with one update of its own (for `extend`)
@potts_model P60bpExtra begin
    @kinds medium A
    @parameters ρ = 0.25
    @variables h(cell) = 0.0
    @lattice Lattice((8, 8))
    @energy cells(A) => ρ * volume
    @after_mcs Every(2) h ~ Pre(h) + ρ
    @sweep Metropolis(; temperature = 1.0)
end

# an edge-scope update (a `@relationship` variable)
@potts_model P60bpEdge begin
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
const _p60bp_t = Potts.t
P60BP_M.@variables p60bp_cm(_p60bp_t) = 0.0 p60bp_cy(_p60bp_t)
P60BP_M.@parameters p60bp_cτ = 20.0 p60bp_cr = 1.0
@named p60bp_clock = P60BP_M.System([Potts.D(p60bp_cm) ~ p60bp_cr / p60bp_cτ, p60bp_cy ~ 3p60bp_cm], _p60bp_t)

@potts_model P60bpComp begin
    @kinds medium A
    @parameters T = 1.0
    @variables w(cell) = 0.0
    @components cells(A) clock = p60bp_clock
    @equations clock.p60bp_cr ~ volume / 25
    @lattice Lattice((12, 12))
    @energy begin
        cells(A) => (volume - 9.0)^2
        contacts => 1.0
    end
    @after_mcs w ~ Pre(w) + clock.p60bp_cy + clock.p60bp_cr
    @sweep Metropolis(; temperature = T)
end

# the timing fixture: model-scope counters only
@potts_model P60bpTiming begin
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
const P60BP_PUBLISHED = [
    ("GranerGlazier", () -> GranerGlazier(; name = :gg), []),
    ("WortelAct", () -> WortelAct(; name = :act, lattice = (8, 8)),
        [(:on_copy, :site, 1, :act), (:after_mcs, :site, 1, :act)]),
    ("WortelAct connected", () -> WortelAct(; name = :act, lattice = (8, 8), connected = true),
        [(:on_copy, :site, 1, :act), (:after_mcs, :site, 1, :act)]),
    ("MerksVasculogenesis", () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8)), []),
    ("MerksVasculogenesis contact-inhibited",
        () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8), contact_inhibited = true), []),
    ("Merks2006", () -> Merks2006(; name = :m6, lattice = (16, 16)), []),
    ("Merks2006 hard", () -> Merks2006(; name = :m6, lattice = (16, 16), rule = :hard), []),
    ("Merks2008", () -> Merks2008(; name = :m8, lattice = (16, 16)), []),
    ("Merks2008 extension only", () -> Merks2008(; name = :m8, lattice = (16, 16), mode = :extension_only), []),
    ("SingleDivisionFixture", () -> SingleDivisionFixture(; name = :fixture), []),
    ("OpenVTGrowingMonolayer", () -> OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)),
        [(:after_mcs, :cell, 1, :V_target)]),
    ("AkeebInvasion", () -> AkeebInvasion(; name = :akeeb, lattice = (60, 40)),
        [(:after_mcs, :cell, 1, :V_target), (:after_mcs, :cell, 1, :clock)]),
    ("OpenVTChain", () -> OpenVTChain(; name = :chain), []),
    ("OpenVTReferenceMonolayer", () -> OpenVTReferenceMonolayer(; name = :ref, lattice = (24, 24)),
        [(:before_mcs, :cell, 1, :X), (:after_mcs, :cell, 1, :f), (:after_mcs, :cell, 1, :A_star)]),
]

# the written variable of a statement: the left side's variable (at a site for `@on_copy`)
p60bp_target(u) = only(setdiff(p60bp_names(u.eq.lhs), (:target, :source, :new, :old)))

# ---------------------------------------------------------------------------------------
# A. Public names

@testset "P6.0bp A: public names with docstrings" begin
    for n in (:updates, :Every)
        @test isdefined(Potts, n) && Base.ispublic(Potts, n)
        @test isdefined(Potts, n) && Base.Docs.hasdoc(Potts, n)
    end
end

# ---------------------------------------------------------------------------------------
# U. The fixture's statements as written

@testset "P6.0bp U: phase, scope and cadence in declaration order" begin
    U = p60bp_updates(P60bpAll(; name = :pa))
    @test U isa AbstractVector && length(U) == length(P60BP_TABLE)
    @test [u.phase for u in U] == [r[1] for r in P60BP_TABLE]
    @test [u.scope for u in U] == [r[2] for r in P60BP_TABLE]
    @test [u.every for u in U] == [Potts.Every(r[3]) for r in P60BP_TABLE]
    @test all(u -> u.every isa Potts.Every, U)
    @test all(u -> u.eq isa P60BP_S.Equation, U)
    # the written variables, in order
    @test [p60bp_target(u) for u in U] == [:m, :w, :g, :s, :s, :w, :k]
end

@testset "P6.0bp U: the equations as written, in Pre form" begin
    U = p60bp_updates(P60bpAll(; name = :pa))
    @testset "statement $i" for (i, (u, r)) in enumerate(zip(U, P60BP_TABLE))
        names, pres, val = r[4], r[5], r[6]
        @test union(p60bp_names(u.eq.lhs), p60bp_names(u.eq.rhs)) == names    # exactly the symbols written
        @test p60bp_pre_args(u.eq.rhs) == pres                                 # Pre exactly where written
        @test isempty(p60bp_pre_args(u.eq.lhs))                                # the new value on the left
        val === nothing || @test isapprox(p60bp_eval(u.eq.rhs, P60BP_POINT), val; rtol = 1e-12)
    end
    # structural: rebuilt from the completed system's declared symbols and MTK's `Pre`
    c = complete(P60bpAll(; name = :pa))
    Pre = P60BP_M.Pre
    uw(x) = P60BP_S.unwrap(x)
    @test isequal(uw(U[1].eq.lhs), uw(c.m)) && isequal(uw(U[1].eq.rhs), uw(Pre(c.m) + c.α))
    @test isequal(uw(U[3].eq.lhs), uw(c.g)) && isequal(uw(U[3].eq.rhs), uw(Pre(c.g) + c.α))   # `g += α`
    @test isequal(uw(U[4].eq.lhs), uw(c.s)) && isequal(uw(U[4].eq.rhs), uw(Pre(c.s) * 0.5))
    @test isequal(uw(U[7].eq.lhs), uw(c.k)) && isequal(uw(U[7].eq.rhs), uw(Pre(c.k) + c.m))   # bare `m`: its new value
    # the on-copy rhs: β at a copy that is not to medium, 0 at one that is
    @test p60bp_eval(U[5].eq.rhs, merge(P60BP_POINT, Dict(:new => 3.0))) == 2.0
    @test p60bp_eval(U[5].eq.rhs, merge(P60BP_POINT, Dict(:new => 0.0))) == 0.0
    # negative control for the oracle: a statement with its Pre dropped fails it
    @test p60bp_pre_args(P60BP_S.unwrap(c.m + c.α)) != P60BP_TABLE[1][5]
end

# ---------------------------------------------------------------------------------------
# F. The four forms

@testset "P6.0bp F: plain, complete and mtkcompile agree" begin
    sys = P60bpAll(; name = :pa)
    U = p60bp_updates(sys)
    cs = mtkcompile(sys)
    @test p60bp_same(p60bp_updates(complete(sys)), U)
    @test p60bp_same(p60bp_updates(cs), U)
    @test p60bp_same(p60bp_updates(mtkcompile(complete(sys))), U)
end

@testset "P6.0bp F: extend lists the merged model's statements" begin
    base = P60bpAll(; name = :pa)
    extra = P60bpExtra(; name = :extra)
    ext = extend(extra, base)
    U = p60bp_updates(ext)
    @test length(U) == length(P60BP_TABLE) + 1
    key(u) = (u.phase, u.scope, u.every, string(u.eq))
    @test sort(map(key, U); by = string) == sort(map(key, [p60bp_updates(base); p60bp_updates(extra)]); by = string)
    h = only(filter(u -> p60bp_target(u) === :h, U))
    @test h.phase === :after_mcs && h.scope === :cell && h.every == Potts.Every(2)
    @test p60bp_pre_args(h.eq.rhs) == Set([:h]) && p60bp_eval(h.eq.rhs, Dict(:Pre_h => 1.0, :ρ => 0.25)) == 1.25
    @test p60bp_same(p60bp_updates(mtkcompile(ext)), U)
end

@testset "P6.0bp F: an edge-scope update (plain and complete)" begin
    sys = P60bpEdge(; name = :pe)
    U = p60bp_updates(sys)
    @test length(U) == 1
    u = only(U)
    @test u.phase === :after_mcs && u.scope === :edge && u.every == Potts.Every(1)
    @test p60bp_target(u) === :rest && p60bp_pre_args(u.eq.rhs) == Set([:rest])
    @test p60bp_eval(u.eq.rhs, Dict(:Pre_rest => 10.0)) == 9.0
    @test p60bp_same(p60bp_updates(complete(sys)), U)
end

@testset "P6.0bp F: a compiled model with components reports the statement as written" begin
    sys = P60bpComp(; name = :pc)
    cs = mtkcompile(sys)
    U, Uc = p60bp_updates(sys), p60bp_updates(cs)
    @test length(U) == 1 && p60bp_same(U, Uc)
    u = only(U)
    @test u.phase === :after_mcs && u.scope === :cell && u.every == Potts.Every(1)
    # it reads the component's coupled parameter and observed quantity as written
    nm = string.(collect(p60bp_names(u.eq.rhs)))
    @test any(n -> occursin("p60bp_cr", n), nm) && any(n -> occursin("p60bp_cy", n), nm)
    @test !any(n -> n == "volume" || occursin("p60bp_cm", n), nm)
    # negative control: `.sys` is the lowered model (cr ↦ volume/25, cy ↦ 3cm)
    @test !p60bp_same(p60bp_updates(cs.sys), U)
end

# ---------------------------------------------------------------------------------------
# P. Published models

@testset "P6.0bp P: published models list their updates as declared" begin
    @testset "$label" for (label, build, want) in P60BP_PUBLISHED
        sys = build()
        U = p60bp_updates(sys)
        @test U isa AbstractVector && length(U) == length(want)
        @test [(u.phase, u.scope, u.every, p60bp_target(u)) for u in U] ==
              [(w[1], w[2], Potts.Every(w[3]), w[4]) for w in want]
        @test all(u -> u.eq isa P60BP_S.Equation, U)
        # every symbol is a parameter or unknown of the system (MTK's accessors) or a built-in
        declared = Set{Symbol}(p60bp_name(x) for x in [P60BP_M.parameters(sys); P60BP_M.unknowns(sys)])
        builtins = Set([:volume, :surface, :kind, :kind′, :owner, :owner′, :target, :source, :new, :old,
            :mcs, :medium, :cell, :leader, :follower])
        for u in U
            extra = setdiff(union(p60bp_names(u.eq.lhs), p60bp_names(u.eq.rhs)), declared, builtins)
            isempty(extra) || @info "P6.0bp: $label update reads $(collect(extra))"
        end
        @test p60bp_same(p60bp_updates(mtkcompile(sys)), U)
    end
    # Wortel as written: `act[target] ~ ifelse(new != 0, max_act, 0.0)`, `act ~ max(Pre(act) - 1, 0)`
    Uw = p60bp_updates(WortelAct(; name = :act, lattice = (8, 8)))
    @test isempty(p60bp_pre_args(Uw[1].eq.rhs)) && p60bp_names(Uw[1].eq.rhs) == Set([:new, :max_act])
    @test p60bp_eval(Uw[1].eq.rhs, Dict(:new => 2.0, :max_act => 20.0)) == 20.0
    @test p60bp_pre_args(Uw[2].eq.rhs) == Set([:act])
    @test p60bp_eval(Uw[2].eq.rhs, Dict(:Pre_act => 0.5)) == 0.0 && p60bp_eval(Uw[2].eq.rhs, Dict(:Pre_act => 7.0)) == 6.0
    # OpenVT growing monolayer: V_target grows by A₀/τ while volume ≥ β·Pre(V_target)
    Uo = only(p60bp_updates(OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24))))
    @test p60bp_pre_args(Uo.eq.rhs) == Set([:V_target])
    pt = Dict(:Pre_V_target => 100.0, :A₀ => 84.0, :τ => 84.0, :β => 0.5, :volume => 60.0)
    @test p60bp_eval(Uo.eq.rhs, pt) == 101.0
    @test p60bp_eval(Uo.eq.rhs, merge(pt, Dict(:volume => 40.0))) == 100.0
    # Akeeb: the clock runs once started
    Ua = p60bp_updates(AkeebInvasion(; name = :akeeb, lattice = (60, 40)))
    @test p60bp_eval(Ua[2].eq.rhs, Dict(:Pre_clock => 3.0)) == 4.0 && p60bp_eval(Ua[2].eq.rhs, Dict(:Pre_clock => -1.0)) == -1.0
end

# ---------------------------------------------------------------------------------------
# N. Negative controls and regression guards

@testset "P6.0bp N: a model without updates" begin
    sys = P60bpNone(; name = :none)
    @test isempty(p60bp_updates(sys)) && p60bp_updates(sys) isa AbstractVector
    @test isempty(p60bp_updates(complete(sys))) && isempty(p60bp_updates(mtkcompile(sys)))
end

@testset "P6.0bp N: no MTK events until P6.4c (D-162)" begin
    # MTK's accessors take an `AbstractSystem`: the compiled model's `.sys` (D-137)
    forms(s) = (s, complete(s), getfield(mtkcompile(s), :sys))
    fixtures = [P60bpAll(; name = :pa), P60bpNone(; name = :none), P60bpComp(; name = :pc),
        P60bpTiming(; name = :pt), extend(P60bpExtra(; name = :extra), P60bpAll(; name = :pa))]
    for sys in [fixtures; [b() for (_, b, _) in P60BP_PUBLISHED]], s in forms(sys)
        @test isempty(P60BP_M.discrete_events(s))
        @test isempty(P60BP_M.continuous_events(s))
    end
    e = P60bpEdge(; name = :pe)
    @test isempty(P60BP_M.discrete_events(e)) && isempty(P60BP_M.discrete_events(complete(e)))
end

@testset "P6.0bp N: the sweep payload and the D-137 rule 5 refusals are unaffected" begin
    for sys in (P60bpAll(; name = :pa), P60bpComp(; name = :pc), WortelAct(; name = :act, lattice = (8, 8)))
        @test P60BP_M.hasmetadata(sys, Potts.PottsSweepSpec)
        @test P60BP_M.getmetadata(mtkcompile(sys), Potts.PottsSweepSpec, nothing) isa Potts.PottsSweepSpec
        @test p60bp_clear(() -> P60BP_M.ODEProblem(sys, [], (0.0, 1.0)), "ODEProblem", "PottsProblem")
        @test p60bp_clear(() -> P60BP_M.JumpProblem(sys, [], (0.0, 1.0)), "JumpProblem", "PottsProblem")
    end
end

@testset "P6.0bp N: update timing (behaviour unchanged)" begin
    sys = complete(P60bpTiming(; name = :pt))
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
