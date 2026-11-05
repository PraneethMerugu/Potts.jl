# P6.0o (ROADMAP Phase 6, step 0): `PottsSystem <: ModelingToolkitBase.AbstractSystem`.
# Decision: D-137 (implements D-075 §0.1; MTK-native review, research/mtk-native-review.md).
# Frozen (AUTONOMY §7.3).
#
# On 33f681df `PottsSystem` is a plain `Base.@kwdef` struct. Subtyping `AbstractSystem` puts
# MTK's `getproperty` (getvar) in charge of `sys.<name>`, so Potts' own field reads must go
# through `getfield` or accessors, and MTK's generic `complete`/`compose`/`extend`/`show`,
# `ODEProblem`/`JumpProblem` and the accessors would otherwise reach a Potts model.
#
# The contract pinned here (S, A, N, C, E, Q-ambiguities and G fail on 33f681df for the
# reasons named; P and Q-piracy are regression guards that pass there):
#  S. Subtype and fields. `PottsSystem <: AbstractSystem`; its field names include the
#     `System` names read by the MTK accessors it supports (`eqs`, `unknowns`, `ps`,
#     `observed`, `name`, `systems`, `metadata`, `namespacing`, `complete`). Potts-owned
#     fields (e.g. `kinds`, `lattice`, P6.0g's `kind_classes`) are not constrained here.
#     An all-fields positional constructor takes `checks` (default true): `checks = false`
#     skips the construction checks (a reserved kind name `a` is accepted), `checks = true`
#     runs them; both rebuild a system with the same code and fingerprint.
#  A. Accessors (ModelingToolkitBase's generic functions), each a documented value:
#     - `equations(sys)`: `Vector{Equation}`, the model's `@equations` (cell and model ODEs,
#       field PDEs, component couplings as written; `@extend` merged), plus each
#       `@components` system's equations namespaced by the component name (`dc₊y`), as MTK
#       returns subsystem equations. Energies, drives, constraints, updates, lifecycle
#       rules and `@observed` are not equations.
#     - `unknowns(sys)`: the declared state variables of every scope (cell, model, site,
#       field, edge), plus each component's unknowns namespaced (`dc₊y`); it excludes the
#       lattice ownership, kinds and built-in cell properties (volume, surface, …). On the
#       compiled system's PottsSystem (`mtkcompile(sys).sys`, components bound) it lists
#       the same names once (no double count).
#     - `parameters(sys)`: the declared parameters (scalars and kind tables), plus each
#       component's parameters namespaced.
#     - `observed(sys)`: `Vector{Equation}`, one `name ~ expr` per `@observed` quantity;
#       `observe(prob, lhs) == observe(prob, rhs)`.
#     - `nameof(sys)`: the model name; `getmetadata(sys, K, default)`,
#       `setmetadata(sys, K, v)` (out of place, returns a PottsSystem), `hasmetadata`:
#       MTK's typed metadata; it survives `complete`, `mtkcompile(sys).sys` and `extend` (of
#       the extension's own key), and never changes the code or fingerprint.
#     - The `PottsSystem` docstring names all seven accessors.
#  N. `sys.x` returns the namespaced symbolic, as in MTK: `getname(sys.λ) === :pr₊λ` for
#     parameters, variables of each scope, `@observed` names, names merged by `@extend`
#     (one and two levels) and component members (`sys.dc.y` → `pr₊dc₊y`); a completed
#     system (or `toggle_namespacing(sys, false)`) returns the declared symbol itself, which
#     works as an operating-point key of `PottsProblem`; an undeclared name is an
#     `ArgumentError`. What `sys.<Potts field name>` returns for a name that is not a
#     declared symbol (e.g. `sys.lattice`) is NOT pinned here (D-137 decides; six frozen
#     files read such properties on 33f681df).
#  C. Potts-owned `complete` (returns a completed PottsSystem, idempotent, same code and
#     fingerprint), `extend(::PottsSystem, ::PottsSystem)` and `show` (text/plain starts
#     with "PottsSystem <name>"; the two-argument form does not throw). `Potts.lattice(sys)`
#     (public, not exported; D-137 rule 6) returns the system's lattice.
#  E. Clear errors (`ArgumentError`, message naming the operation and the Potts route):
#     `compose` with a PottsSystem on either side (D-039: names `compose` and
#     `@components`); `ODEProblem`/`JumpProblem` on a PottsSystem or a compiled one (names
#     `PottsProblem`); `extend` between a PottsSystem and a plain `System` either way (names
#     `extend` and `@components`).
#  Q. Aqua ambiguities and piracy on Potts are clean (33f681df has one ambiguity, `_pre`
#     in src/vocabulary.jl, which this item must fix). JET and ExplicitImports stay in the
#     Potts suite (test/qa.jl).
#  G. A source scan: no property read `<x>sys.<field>`, `base.<field>`, `$bname.<field>`
#     (and per file `b.`, `m.`, `s.`, see P60O_RECEIVERS) of a PottsSystem field name
#     (current or mirrored) in src/ or ext/ outside comments: a heuristic floor for "every
#     internal read uses getfield or an accessor"; 33f681df has 357.
#  P. Generated code is byte-identical and fingerprints are unchanged for every PottsModels
#     model (Float64 and Float32) and a representative fixture set: per case the problem
#     fingerprint, the SHA-256 of `generated_code` printed without line numbers ("raw"),
#     and the same in the fingerprint's canonical operand order ("canon"), recorded on
#     33f681df (Julia 1.12.6). The published-model fingerprints duplicate pins of p6_0p,
#     p6_0aq, p6_0c2 and others (D-136 keeps one copy); the Float32, Merks
#     contact-inhibited and fixture pins are new.
#
# On 33f681df: 39 fail and 52 error of the 200 tests that run (every target; the 101 pin
# tests and 8 controls pass). A stub (subtype, mirrored fields, accessor methods, `complete`, the
# error methods, the `_pre` fix, every listed property read rewritten to `getfield`, and
# MTK's strict `getproperty`) passes every test here, with identical pins; with a
# field-name fallback in `getproperty` instead it passes too, and so do the six frozen
# files that read PottsSystem properties.
using Potts: CorePotts
using Aqua: Aqua
using SHA: sha256

const P60O_M = Potts.ModelingToolkitBase
const P60O_SII = Potts.SymbolicIndexingInterface
p60o_name(x) = P60O_SII.getname(x)
p60o_names(xs) = Symbol[p60o_name(x) for x in xs]
p60o_named(xs, n) = only(filter(x -> Potts.info(x).name === n, collect(xs)))

# ---------------------------------------------------------------------------------------
# Fixtures

p60o_two(dims, a, b) = (s = zeros(Int32, dims); s[a...] .= 1; s[b...] .= 2; s)
const P60O_OP12 = [ownership => p60o_two((12, 12), (2:4, 2:4), (7:9, 7:9)), kind => [:host, :host]]

# cell and model variables, a kind table, an ODE, an after-MCS update and an observed sum
@potts_model P60oCell begin
    @kinds medium host
    @parameters begin
        λ = 2.0
        T = 1.0
        J[kind, kind] = [0.0 4.0; 4.0 2.0]
    end
    @variables begin
        x(cell) = 1.5
        g(model) = 0.0
    end
    @lattice Lattice((12, 12); neighborhood = Moore(1))
    @energy begin
        cells(host) => λ * (volume - 9.0)^2
        contacts => J[kind, kind′]
    end
    @equations D(x) ~ -0.1 * x
    @after_mcs g ~ g + 1.0
    @observed total ~ sum(x for n in cells)
    @sweep Metropolis(; temperature = T)
end

# an extension that adds a parameter and an energy (for `extend` and its metadata)
@potts_model P60oExtra begin
    @kinds medium host
    @parameters μ = 0.5
    @lattice Lattice((12, 12); neighborhood = Moore(1))
    @energy cells(host) => μ * volume
    @sweep Metropolis(; temperature = 1.0)
end

# continuous MTK components, per cell and per model (`@potts_model` reads the Ref at
# construction)
const P60O_DECAY = Ref{Any}(nothing)
const P60O_CLOCK = Ref{Any}(nothing)
function p60o_decay()
    t = Potts.t
    P60O_M.@variables y(t) = 1.0
    P60O_M.@parameters k = 0.1
    return P60O_M.System([Potts.D(y) ~ -k * y], t; name = :decay)
end
function p60o_clock()
    t = Potts.t
    P60O_M.@variables m(t) = 0.0
    P60O_M.@parameters τ = 20.0
    return P60O_M.System([Potts.D(m) ~ 1.0 / τ], t; name = :clock)
end
P60O_DECAY[] = p60o_decay()
P60O_CLOCK[] = p60o_clock()
@potts_model P60oComp begin
    @kinds medium host
    @parameters λ = 2.0
    @variables x(cell) = 1.5
    @components cells(host) dc = P60O_DECAY[]
    @components model clk = P60O_CLOCK[]
    @lattice Lattice((12, 12))
    @energy cells => λ * (volume - 9.0)^2
    @equations D(x) ~ -0.1 * x
    @sweep Metropolis(; temperature = 1.0)
end

# a discrete (clocked) component, coupled to a cell variable
const P60O_NET = Ref{Any}(nothing)
function p60o_network()
    t = Potts.t
    k = P60O_M.ShiftIndex(t, 0)
    P60O_M.@variables A(t)::Bool = false B(t)::Bool = false C(t)::Bool = false
    P60O_M.@parameters wnt::Bool = false
    return P60O_M.System([A(k) ~ wnt | (B(k - 1) & !C(k - 1)), B(k) ~ A(k - 1), C(k) ~ !(A(k - 1) | B(k - 1))], t;
        name = :grn)
end
P60O_NET[] = p60o_network()
@potts_model P60oNet begin
    @kinds medium host
    @variables input(cell) = 0.0
    @components cells(host) grn = P60O_NET[]
    @equations grn.wnt ~ input > 0.5
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0e-6)
end

# a relationship with an edge variable, extended once and twice (`@extend` merges names)
@potts_model P60oSpring begin
    @kinds medium host
    @parameters begin
        T = 10.0
        k = 2.0
    end
    @variables rest(edge) = 12.0
    @relationship bond(cell, cell) capacity = 1
    @lattice Lattice((30, 20); neighborhood = Moore(1))
    @energy begin
        cells(host) => (volume - 9.0)^2
        contacts => 16.0
        edges(bond) => k * (distance - rest)^2
    end
    @link bond when = new_contact(a, b)
    @sweep Metropolis(; temperature = T)
end
@potts_model P60oSpringExt begin
    @extend base = P60oSpring()
    @variables len(tether) = 18.0
    @relationship tether(cell, cell) capacity = 1
    @energy edges(tether) => 1.5 * (distance - len)^2
end
@potts_model P60oSpringExt2 begin
    @extend host = base = P60oSpringExt()
    @parameters χ = 0.25
    @energy cells(host) => χ * surface
end
const P60O_OP_SPRING = [ownership => p60o_two((30, 20), (3:5, 3:5), (12:14, 3:5)), kind => [:host, :host]]

# a field with a drive, a frozen kind, per-kind temperature
@potts_model P60oField begin
    @kinds medium wall[frozen] dark light
    @parameters begin
        Tk[kind] = [0.0, 0.0, 5.0, 20.0]
        J[kind, kind] = [0 30 16 16; 30 0 30 30; 16 30 2 11; 16 30 11 14]
        χ = 3.0
    end
    @variables c(field) = 0.0
    @lattice Lattice((16, 16); neighborhood = Moore(1))
    @energy begin
        Volume(dark, light; target = 9.0, strength = 1.0)
        Adhesion(J)
    end
    @drive Chemotaxis(c; strength = χ, kinds = (dark,))
    @equations D(c) ~ 0.1 * Δ(c) + 0.02 * (kind == dark) - 0.01 * c
    @sweep Metropolis(; temperature = Tk[kind], combine = min)
end
const P60O_OP_FIELD = [ownership => (s = zeros(Int32, 16, 16); s[:, 1] .= 1; s[4:6, 4:6] .= 2; s[10:12, 10:12] .= 3; s),
    kind => [:wall, :dark, :light]]
const P60O_EULER = (; field_solver = ExplicitEuler(substeps = 2, lower = 0.0))

# divisions, an on-copy write, a site variable, model folds and a constraint
@potts_model P60oLife begin
    @kinds medium A B
    @parameters begin
        T = 5.0
        J[kind, kind] = [0 10 10; 10 2 6; 10 6 2]
    end
    @variables begin
        m(cell) = 8.0
        q(cell) = 5.0
        act(site) = 0.0
        total(model) = 0.0
    end
    @lattice Lattice((24, 24); neighborhood = Moore(1))
    @energy begin
        cells(A, B) => (volume - 9.0)^2
        contacts => J[kind, kind′]
    end
    @on_copy act[target] ~ 1.0
    @after_mcs total ~ sum(act[s] for s in sites)
    @divide cells(A) when = mcs == 0, m => Split()
    @divide cells(B) when = mcs == 1000, q => 0.0
    @constraint no_extinction
    @observed big ~ volume > 9
    @sweep Metropolis(; temperature = T)
end
const P60O_OP_LIFE = [ownership => p60o_two((24, 24), (3:6, 3:6), (12:15, 12:15)), kind => [:A, :B]]

# two cell ODEs under RK4 (the fingerprint_compare tool's pair)
@potts_model P60oPair begin
    @kinds medium host
    @parameters k = 0.3
    @variables begin
        y(cell) = 1.0
        s(cell) = 2.0
    end
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @equations begin
        D(y) ~ -k * y
        D(s) ~ -0.5 * s
    end
    @sweep Metropolis(; temperature = 1.0)
end

# (label, system builder, operating point, problem keywords, generated_code keywords)
const P60O_GG = graner_glazier_state()
const P60O_CASES = [
    ("GranerGlazier", () -> GranerGlazier(; name = :gg), [ownership => P60O_GG[1], kind => P60O_GG[2]], (;)),
    ("WortelAct", () -> WortelAct(; name = :act, lattice = (8, 8)),
        [ownership => p60o_two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (;)),
    ("WortelAct connected", () -> WortelAct(; name = :act, lattice = (8, 8), connected = true),
        [ownership => p60o_two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (;)),
    ("MerksVasculogenesis", () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
        [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], P60O_EULER),
    ("MerksVasculogenesis contact-inhibited", () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8), contact_inhibited = true),
        [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], P60O_EULER),
    ("SingleDivisionFixture", () -> SingleDivisionFixture(; name = :fixture),
        [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [:epithelial]], (;)),
    ("OpenVTGrowingMonolayer", () -> OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)),
        openvt_monolayer_state(; lattice = (24, 24)), (; capacity = 64)),
    ("AkeebInvasion", () -> AkeebInvasion(; name = :akeeb, lattice = (60, 40)), akeeb_state(; lattice = (60, 40)),
        (; capacity = 256)),
    ("fixture cell", () -> P60oCell(; name = :pr), P60O_OP12, (;)),
    ("fixture components", () -> P60oComp(; name = :pr), P60O_OP12, (;)),
    ("fixture discrete component", () -> P60oNet(; name = :net), P60O_OP12, (;)),
    ("fixture spring", () -> P60oSpring(; name = :sp), P60O_OP_SPRING, (;)),
    ("fixture spring @extend", () -> P60oSpringExt(; name = :ext), P60O_OP_SPRING, (;)),
    ("fixture spring @extend²", () -> P60oSpringExt2(; name = :ext2), P60O_OP_SPRING, (;)),
    ("fixture field", () -> P60oField(; name = :fld), P60O_OP_FIELD, P60O_EULER),
    ("fixture lifecycle", () -> P60oLife(; name = :life), P60O_OP_LIFE, (;)),
    ("fixture ODE pair RK4", () -> P60oPair(; name = :pair), P60O_OP12, (; ode_solver = Potts.RK4())),
]
# the published models are also pinned in Float32
const P60O_FLOAT32 = ("GranerGlazier", "WortelAct", "WortelAct connected", "MerksVasculogenesis",
    "MerksVasculogenesis contact-inhibited", "SingleDivisionFixture", "OpenVTGrowingMonolayer", "AkeebInvasion")

p60o_problem(sys, op, kw; T = Float64) = PottsProblem(sys, op, (0, 1); T, kw...)
p60o_fp(sys, op, kw; T = Float64) = p60o_problem(sys, op, kw; T).f.fingerprint

# `generated_code` as text: line numbers stripped (also those macro calls carry), and in the
# "canon" form flattened `+`/`*` operands sorted by their printed form (the fingerprint's
# canonical order, src/codegen.jl `_commutative_order!`, re-implemented here)
function p60o_strip!(ex)
    ex isa Expr || return ex
    Base.remove_linenums!(ex)
    ex.head === :macrocall && length(ex.args) >= 2 && ex.args[2] isa LineNumberNode && (ex.args[2] = nothing)
    foreach(p60o_strip!, ex.args)
    return ex
end
function p60o_canon!(ex)
    ex isa Expr || return ex
    foreach(p60o_canon!, ex.args)
    if ex.head === :call && length(ex.args) > 2 && any(f -> ex.args[1] === f, (:+, :*, +, *))
        op = ex.args[1]
        flat = Any[]
        for a in @view ex.args[2:end]
            if a isa Expr && a.head === :call && length(a.args) > 2 && a.args[1] === op
                append!(flat, @view a.args[2:end])
            else
                push!(flat, a)
            end
        end
        sort!(flat; by = string)
        resize!(ex.args, 1)
        append!(ex.args, flat)
    end
    return ex
end
p60o_exprs(x::Expr) = Any[x]
p60o_exprs(::Nothing) = Any[]
p60o_exprs(x::Union{Tuple, AbstractVector, NamedTuple}) = reduce(vcat, map(p60o_exprs, collect(values(x))); init = Any[])
p60o_exprs(x) = Any[x]
function p60o_code_hashes(sys, kw; T = Float64)
    gkw = (; (k => v for (k, v) in pairs(kw) if k in (:field_solver, :ode_solver, :solvers))...)
    exprs = p60o_exprs(generated_code(sys; T, gkw...))
    raw = [string(p60o_strip!(deepcopy(e))) for e in exprs]
    canon = [string(p60o_canon!(p60o_strip!(deepcopy(e)))) for e in exprs]
    return (; n = length(exprs), raw = bytes2hex(sha256(join(raw, "\n"))), canon = bytes2hex(sha256(join(canon, "\n"))))
end

# `f()` throws an ArgumentError whose message contains every word
function p60o_clear(f, words...)
    err = try
        f()
        nothing
    catch e
        e
    end
    err isa ArgumentError || (@info "P6.0o: expected an ArgumentError, got $(err === nothing ? "no error" : typeof(err))"; return false)
    msg = sprint(showerror, err)
    ok = all(w -> occursin(w, msg), words)
    ok || @info "P6.0o: message lacks one of $(words): $(first(msg, 300))"
    return ok
end

# `compose(a, b)` gives a clear error. Called only when the method it reaches is not MTK's
# varargs `compose(syss...)`: on a type without its own method that one recurses without end
# (`compose(x, [y])` → `compose(x, [[y]])` → …), as on 33f681df.
function p60o_compose_clear(a, b)
    args = b isa AbstractArray ? Tuple{typeof(a), typeof(b)} : Tuple{typeof(a), Vector{typeof(b)}}
    m = which(P60O_M.compose, args)
    if m.isva
        @info "P6.0o: compose$(args) reaches MTK's varargs compose (unbounded recursion); not called"
        return false
    end
    return p60o_clear(() -> P60O_M.compose(a, b), "compose", "@components")
end

struct P60oKey end
struct P60oOtherKey end

# ---------------------------------------------------------------------------------------
# S. Subtype, mirrored fields, the `checks` constructor

@testset "P6.0o S: PottsSystem <: AbstractSystem, mirrored fields, checks constructor" begin
    @test PottsSystem <: P60O_M.AbstractSystem
    @test GranerGlazier(; name = :gg) isa P60O_M.AbstractSystem
    for f in (:eqs, :unknowns, :ps, :observed, :name, :systems, :metadata, :namespacing, :complete)
        @test f in fieldnames(PottsSystem)
    end
    sys = P60oCell(; name = :pr)
    fp = p60o_fp(sys, P60O_OP12, (;))
    vals = Any[getfield(sys, f) for f in fieldnames(PottsSystem)]
    for checks in (false, true)
        s2 = PottsSystem(vals...; checks)
        @test s2 isa PottsSystem
        @test nameof(s2) === :pr
        @test p60o_fp(s2, P60O_OP12, (;)) == fp
    end
    # `checks` decides whether the construction checks run (a reserved kind name `a`)
    bad = copy(vals)
    bad[findfirst(==(:kinds), fieldnames(PottsSystem))] = [:medium, :a]
    @test PottsSystem(bad...; checks = false) isa PottsSystem
    @test_throws ArgumentError PottsSystem(bad...; checks = true)
    @test_throws ArgumentError PottsSystem(bad...)
end

# ---------------------------------------------------------------------------------------
# A. Accessors

@testset "P6.0o A: equations, unknowns, parameters, observed" begin
    E, U, P, O = P60O_M.equations, P60O_M.unknowns, P60O_M.parameters, P60O_M.observed
    # a model without ODEs, components or observed quantities
    gg = GranerGlazier(; name = :gg)
    @test E(gg) isa AbstractVector{P60O_M.Equation} && isempty(E(gg))
    @test isempty(U(gg))
    @test Set(p60o_names(P(gg))) == Set([:λ, :V₀, :T, :J]) && length(P(gg)) == 4
    @test O(gg) isa AbstractVector{P60O_M.Equation} && isempty(O(gg))
    # the declared ones, in every scope
    sys = P60oCell(; name = :pr)
    x = p60o_named(Potts.variables(sys), :x)
    @test length(E(sys)) == 1 && isequal(only(E(sys)), Potts.D(x) ~ -0.1 * x)
    @test p60o_names(U(sys)) == [:x, :g]
    @test all(isequal.(U(sys), Potts.variables(sys)))
    @test Set(p60o_names(P(sys))) == Set([:λ, :T, :J]) && length(P(sys)) == 3
    @test all(isequal.(P(sys), Potts.parameters(sys)))
    obs = O(sys)
    @test obs isa AbstractVector{P60O_M.Equation} && length(obs) == 1 && p60o_name(only(obs).lhs) === :total
    prob = p60o_problem(sys, P60O_OP12, (;))
    @test observe(prob, only(obs).lhs) == observe(prob, only(obs).rhs) == 3.0       # x = 1.5 on two cells
    # site, field and edge variables are unknowns too; the lattice and built-ins are not
    @test Set(p60o_names(U(P60oLife(; name = :life)))) == Set([:m, :q, :act, :total])
    @test p60o_names(U(P60oField(; name = :fld))) == [:c] && length(E(P60oField(; name = :fld))) == 1
    @test p60o_names(U(P60oSpring(; name = :sp))) == [:rest]
    @test Set(p60o_names(U(P60oSpringExt2(; name = :ext2)))) == Set([:rest, :len])
    @test Set(p60o_names(P(P60oSpringExt2(; name = :ext2)))) == Set([:T, :k, :χ])
    @test !any(n -> n in (:volume, :surface, :kind, :ownership), p60o_names(U(P60oLife(; name = :life))))
    @test [p60o_name(eq.lhs) for eq in O(P60oLife(; name = :life))] == [:big]
end

@testset "P6.0o A: accessors include components namespaced, never twice" begin
    E, U, P = P60O_M.equations, P60O_M.unknowns, P60O_M.parameters
    sys = P60oComp(; name = :pr)
    @test Set(p60o_names(U(sys))) == Set([:x, :dc₊y, :clk₊m]) && length(U(sys)) == 3
    @test Set(p60o_names(P(sys))) == Set([:λ, :dc₊k, :clk₊τ]) && length(P(sys)) == 3
    @test length(E(sys)) == 3
    @test count(eq -> occursin("dc₊y", string(eq.lhs)), E(sys)) == 1
    @test count(eq -> occursin("clk₊m", string(eq.lhs)), E(sys)) == 1
    # the compiled model's PottsSystem has the components bound: the same names, once
    cs = getfield(mtkcompile(sys), :sys)
    @test Set(p60o_names(U(cs))) == Set(p60o_names(U(sys))) && length(U(cs)) == length(U(sys))
    @test Set(p60o_names(U(cs))) == Set(Potts.info(v).name for v in Potts.variables(cs))
    # a discrete component's nodes and parameter
    net = P60oNet(; name = :net)
    @test issubset([:input, :grn₊A, :grn₊B, :grn₊C], p60o_names(U(net)))
    @test :grn₊wnt in p60o_names(P(net))
    # the published models have no components: the accessors are Potts' own lists
    for (label, build, _, _) in P60O_CASES[1:8]
        m = build()
        @test Set(p60o_names(U(m))) == Set(Potts.info(v).name for v in Potts.variables(m))
        @test Set(p60o_names(P(m))) == Set(Potts.info(v).name for v in Potts.parameters(m))
    end
end

@testset "P6.0o A: nameof, getmetadata, setmetadata" begin
    sys = P60oCell(; name = :pr)
    @test nameof(sys) === :pr
    @test nameof(P60O_M.complete(sys)) === :pr
    @test P60O_M.getmetadata(sys, P60oKey, :none) === :none
    @test !P60O_M.hasmetadata(sys, P60oKey)
    s2 = P60O_M.setmetadata(sys, P60oKey, 42)
    @test s2 isa PottsSystem
    @test P60O_M.getmetadata(s2, P60oKey, :none) == 42 && P60O_M.hasmetadata(s2, P60oKey)
    @test P60O_M.getmetadata(sys, P60oKey, :none) === :none          # out of place
    s3 = P60O_M.setmetadata(s2, P60oOtherKey, "b")
    @test P60O_M.getmetadata(s3, P60oKey, :none) == 42 && P60O_M.getmetadata(s3, P60oOtherKey, nothing) == "b"
    # metadata never changes the code
    @test p60o_fp(s3, P60O_OP12, (;)) == p60o_fp(sys, P60O_OP12, (;))
    @test p60o_code_hashes(s3, (;)) == p60o_code_hashes(sys, (;))
    # it survives complete, mtkcompile and extend (the extension's key)
    @test P60O_M.getmetadata(P60O_M.complete(s2), P60oKey, :none) == 42
    @test P60O_M.getmetadata(getfield(mtkcompile(s2), :sys), P60oKey, :none) == 42
    ext = extend(P60O_M.setmetadata(P60oExtra(; name = :extra), P60oKey, 7), sys)
    @test ext isa PottsSystem && P60O_M.getmetadata(ext, P60oKey, :none) == 7
    # documented
    doc = string(Base.Docs.doc(PottsSystem))
    for w in ("equations", "unknowns", "parameters", "observed", "nameof", "getmetadata", "setmetadata")
        @test occursin(w, doc)
    end
end

# ---------------------------------------------------------------------------------------
# N. `sys.x`: the namespaced symbolic

@testset "P6.0o N: sys.x namespaces as in MTK" begin
    sys = P60oCell(; name = :pr)
    @test p60o_name(sys.λ) === :pr₊λ
    @test p60o_name(sys.J) === :pr₊J
    @test p60o_name(sys.x) === :pr₊x
    @test p60o_name(sys.g) === :pr₊g
    @test p60o_name(sys.total) === :pr₊total
    @test p60o_name(GranerGlazier(; name = :gg).V₀) === :gg₊V₀
    @test p60o_name(P60oLife(; name = :life).act) === :life₊act
    @test p60o_name(P60oField(; name = :fld).c) === :fld₊c
    @test p60o_name(P60oSpring(; name = :sp).rest) === :sp₊rest
    # names merged by @extend, one and two levels
    ext = P60oSpringExt(; name = :ext)
    @test p60o_name(ext.k) === :ext₊k && p60o_name(ext.rest) === :ext₊rest && p60o_name(ext.len) === :ext₊len
    ext2 = P60oSpringExt2(; name = :ext2)
    @test p60o_name(ext2.k) === :ext2₊k && p60o_name(ext2.len) === :ext2₊len && p60o_name(ext2.χ) === :ext2₊χ
    # component members, through the component
    comp = P60oComp(; name = :pr)
    @test p60o_name(comp.dc.y) === :pr₊dc₊y
    @test p60o_name(comp.dc.k) === :pr₊dc₊k
    @test p60o_name(comp.clk.m) === :pr₊clk₊m
    @test p60o_name(P60oNet(; name = :net).grn.A) === :net₊grn₊A
    # an undeclared name
    @test_throws ArgumentError sys.nosuch
    @test_throws ArgumentError comp.dc.nosuch
    # completed, or namespacing off: the declared symbol itself
    cs = P60O_M.complete(sys)
    @test p60o_name(cs.λ) === :λ && isequal(cs.λ, p60o_named(Potts.parameters(sys), :λ))
    @test isequal(cs.x, p60o_named(Potts.variables(sys), :x))
    @test p60o_name(P60O_M.complete(comp).dc.y) === :dc₊y
    @test :dc₊y in [Potts.info(v).name for v in Potts.variables(getfield(mtkcompile(comp), :sys))]
    off = P60O_M.toggle_namespacing(sys, false)
    @test off isa PottsSystem && p60o_name(off.λ) === :λ
    @test p60o_name(P60O_M.toggle_namespacing(cs, true).λ) === :pr₊λ
    # a completed system's symbols key the operating point
    prob = PottsProblem(cs, [P60O_OP12..., cs.λ => 3.0, cs.x => 2.5], (0, 1))
    @test prob.p.λ == 3.0
    @test all(==(2.5), prob.u0.cell.x[1:2])
end

# ---------------------------------------------------------------------------------------
# C. Potts-owned complete, extend, show

@testset "P6.0o C: complete, extend and show are Potts'" begin
    sys = P60oCell(; name = :pr)
    @test parentmodule(which(P60O_M.complete, Tuple{PottsSystem})) === Potts
    @test parentmodule(which(P60O_M.extend, Tuple{PottsSystem, PottsSystem})) === Potts
    @test parentmodule(which(show, Tuple{IO, MIME"text/plain", PottsSystem})) === Potts
    cs = P60O_M.complete(sys)
    @test cs isa PottsSystem && P60O_M.iscomplete(cs) && !P60O_M.iscomplete(sys)
    @test P60O_M.iscomplete(P60O_M.complete(cs))
    for (label, build, op, kw) in P60O_CASES[[1, 4, 8, 9, 10, 11, 13]]
        s = build()
        c = P60O_M.complete(s)
        @test p60o_fp(c, op, kw) == p60o_fp(s, op, kw)
        @test p60o_code_hashes(c, kw) == p60o_code_hashes(s, kw)
        @test mtkcompile(c) isa CompiledPottsSystem
    end
    # extend between Potts systems: a PottsSystem with the union of the declarations
    ext = extend(P60oExtra(; name = :extra), sys)
    @test ext isa PottsSystem && nameof(ext) === :extra
    @test Set(p60o_names(P60O_M.parameters(ext))) == Set([:λ, :T, :J, :μ])
    @test p60o_fp(ext, P60O_OP12, (;)) != p60o_fp(sys, P60O_OP12, (;))
    # show
    txt = sprint(show, MIME"text/plain"(), sys)
    @test startswith(txt, "PottsSystem pr")
    @test occursin("kinds: medium, host", txt)
    @test startswith(sprint(show, MIME"text/plain"(), P60O_M.complete(sys)), "PottsSystem pr")
    two = sprint(show, sys)
    @test occursin("pr", two) && length(two) < 10_000
    @test startswith(sprint(show, MIME"text/plain"(), GranerGlazier(; name = :gg); context = :limit => true), "PottsSystem gg")
end

@testset "P6.0o C: Potts.lattice, the public lattice accessor (D-137 rule 6)" begin
    @test Base.ispublic(Potts, :lattice) && !Base.isexported(Potts, :lattice)
    for (label, build, _, _) in P60O_CASES[[1, 4, 9, 12]]
        s = build()
        @test Potts.lattice(s) === getfield(s, :lattice)
    end
    @test Potts.lattice(GranerGlazier(; name = :gg)).dims == (72, 72)
    @test Potts.lattice(MerksVasculogenesis(; name = :m, lattice = (8, 8))).dims == (8, 8)
end

# ---------------------------------------------------------------------------------------
# E. Clear errors

@testset "P6.0o E: compose, ODEProblem, JumpProblem, extend with a System" begin
    sys = P60oCell(; name = :pr)
    other = P60oExtra(; name = :extra)
    mtk = p60o_decay()
    @test p60o_compose_clear(sys, [mtk])
    @test p60o_compose_clear(sys, [other])
    @test p60o_compose_clear(sys, other)
    @test p60o_compose_clear(mtk, [sys])
    @test p60o_compose_clear(mtk, sys)
    for s in (sys, mtkcompile(sys))
        @test p60o_clear(() -> P60O_M.ODEProblem(s, [], (0.0, 1.0)), "PottsProblem")
        @test p60o_clear(() -> P60O_M.ODEProblem(s, P60O_OP12, (0.0, 1.0)), "PottsProblem")
        @test p60o_clear(() -> P60O_M.JumpProblem(s, [], (0.0, 1.0)), "PottsProblem")
    end
    @test p60o_clear(() -> extend(sys, mtk), "extend", "@components")
    @test p60o_clear(() -> extend(mtk, sys), "extend", "@components")
    # controls: MTK's own extend and compose still work on plain Systems
    @test P60O_M.extend(p60o_clock(), mtk) isa P60O_M.System
    @test P60O_M.compose(p60o_clock(), [mtk]) isa P60O_M.System
end

# ---------------------------------------------------------------------------------------
# Q. Aqua on Potts

@testset "P6.0o Q: Aqua ambiguities and piracy (Potts)" begin
    Aqua.test_ambiguities(Potts)
    Aqua.test_piracies(Potts)
end

# ---------------------------------------------------------------------------------------
# G. No PottsSystem field read by property in src/ or ext/

const P60O_FIELDS = ("name", "kinds", "frozen_kinds", "kind_classes", "lattice", "parameters", "variables",
    "relations", "energies", "drives", "constraints", "updates", "equations", "divisions", "relationships",
    "link_rules", "observed", "components", "discrete", "sweep", "structural", "sources", "eqs", "unknowns",
    "ps", "systems", "metadata", "namespacing", "complete", "iv", "var_to_name", "description")

# short receivers that hold a PottsSystem on 33f681df, per file (a base in the code
# `@potts_model` generates, the rebuilt model in `_bind_components`, …)
const P60O_RECEIVERS = Dict("src/macro.jl" => ["b"], "src/vocabulary.jl" => ["b"], "src/components.jl" => ["m"],
    "src/observed.jl" => ["m"], "src/codegen.jl" => ["s"], "src/compose.jl" => ["s"])

function p60o_property_reads()
    root = joinpath(pkgdir(Potts))
    hits = String[]
    for dir in ("src", "ext"), f in sort(readdir(joinpath(root, dir)))
        endswith(f, ".jl") || continue
        extra = join(("\\b" * r for r in get(P60O_RECEIVERS, "$dir/$f", String[])), "|")
        rx = Regex("(\\b[A-Za-z_]*sys|\\bbase|\\\$bname" * (isempty(extra) ? "" : "|" * extra) * ")\\.(" *
                   join(P60O_FIELDS, "|") * ")\\b")
        indoc = false
        for (i, line) in enumerate(eachline(joinpath(root, dir, f)))
            s = strip(line)
            if count("\"\"\"", line) == 1
                indoc = !indoc
                continue
            end
            (indoc || startswith(s, "#")) && continue
            code = replace(line, r"\s#\s.*$" => "")          # a trailing comment
            for m in eachmatch(rx, code)
                push!(hits, "$dir/$f:$i: $(m.match)")
            end
        end
    end
    return hits
end

@testset "P6.0o G: internal reads use getfield or an accessor" begin
    hits = p60o_property_reads()
    isempty(hits) || @info "P6.0o: $(length(hits)) property reads of PottsSystem fields, e.g. $(first(hits, 5))"
    @test isempty(hits)
end

# ---------------------------------------------------------------------------------------
# P. Byte-identical generated code, unchanged fingerprints (recorded on 33f681df)

# recorded on 33f681df (Julia 1.12.6); the Float64 fingerprints of the published models and
# of the ODE pair duplicate the pins of p6_0p/p6_0aq/p6_0c2 (one copy kept by D-136)
const P60O_PINS = Dict{String, Any}(
    "AkeebInvasion Float32" => (fp = 0x7699cb850035a4db, n = 10, raw = "773eb7c3d960a8adb425acc3e22743e7cf4aeebe6bc4ce99c62b0d5a1f03eee9", canon = "11d343e5dcf4f9463c2370774517be4090dffc7c0b7c5bbccf33c15ce1e4cb8a"),   # re-pinned under D-237 (cell draws by id and generation)
    "AkeebInvasion Float64" => (fp = 0x72ced0fc70498f16, n = 10, raw = "fc2b870dce37df33e2405b688d4f5e578587b6bcfab3729f229e3c599b5212c2", canon = "a2d38a6eb64bc5f62c5a0acb86d5b3370b33b0ec33880813fe793bd52ea73a2c"),   # re-pinned under D-237 (cell draws by id and generation)
    "GranerGlazier Float32" => (fp = 0x526093de596ed924, n = 5, raw = "5477c81b88cda45820a0705515b1bcbe664db3cfc9b3942db64791f9b64f5f23", canon = "e25b1f0e742c50f2a75f7d07a05f8b53595a51a957faa1ba29b60da0d49d24f4"),
    "GranerGlazier Float64" => (fp = 0xe6e09483034b4193, n = 5, raw = "b205076896aabdd3c41c3eeaa5b95632b6673a3da0c83147e6508806aa1db524", canon = "b2204f30bb454da6f2ed6dbd5a05601a0a402d0d488416269920e0c132739196"),
    "MerksVasculogenesis Float32" => (fp = 0x32e3a82e6f4ebcd9, n = 8, raw = "fa55b2134c2941f880e4ce34609d726f1fbb9bf70377c2ce818cee0b358533e2", canon = "cc4fe54da52d54c9370d1ef7c6eb30be3a534137495186bd033fd8cdd28daf06"),   # re-pinned under D-189 rulings 3 and 10: dynamics change (gain test, full-shell refusal under Moore(1) copies)
    "MerksVasculogenesis Float64" => (fp = 0xeb4c1851b0fe68da, n = 8, raw = "69906271ee07cedbc0cebcc0a74f74d277a93d8d1f2110920da15e69ee092346", canon = "c1fad1a705f23edeee76a0787b364b39ca4f21081d0ce943484b86769e65637e"),   # re-pinned under D-189 rulings 3 and 10: dynamics change (gain test, full-shell refusal under Moore(1) copies)
    "MerksVasculogenesis contact-inhibited Float32" => (fp = 0x0cef1a1d77e7e5b5, n = 8, raw = "ee05a537c47074d38154ebc05b9b7392dc2c29fa49cd33e7357d6f0a4b995db4", canon = "9dfd980826a22348555f024747a2e7d0d4c447ea98a64034434d00e97e6c7d82"),   # re-pinned under D-189 rulings 3 and 10: dynamics change (gain test, full-shell refusal under Moore(1) copies)
    "MerksVasculogenesis contact-inhibited Float64" => (fp = 0x6c9b003ccb05acd1, n = 8, raw = "e0f0fd7b1b7ab6c1220398f46147ef628a7d2f1a988d471e9d0524f55304878a", canon = "abcbbe9908371936d996f995dee75370a104a6b8f4d0b66fe830a7d421a663e8"),   # re-pinned under D-189 rulings 3 and 10: dynamics change (gain test, full-shell refusal under Moore(1) copies)
    "OpenVTGrowingMonolayer Float32" => (fp = 0x5cd51ad3b52ddac0, n = 9, raw = "32d919af1bca7393d78557fac5344a4c76f030f69e5e62aaabb7095281a28f8c", canon = "aa8ebd9313be975cb5dd21b83a5a026c7357688f87326f43d1ec37f839f7cd82"),
    "OpenVTGrowingMonolayer Float64" => (fp = 0x34b40af65c56a113, n = 9, raw = "3884cacea09298421c5053db40366dca6ca02868f10dd70627257ae549088da0", canon = "3acc5f836bfb69fcaa4bb00516fb93b5f4a0b1c6dda1722d6ad83e449ce88060"),
    "SingleDivisionFixture Float32" => (fp = 0x8f8dd0a3b1295f9f, n = 9, raw = "6d144ef9a2779aa5d862528b3d0650856a5a491064c5ae6899c82aa8a0da9c2f", canon = "e003f6d1eaf87453cdf8825480c80e3746ef5fcdfacffb430174e6bae77fa538"),
    "SingleDivisionFixture Float64" => (fp = 0xd2bed53e2590b709, n = 9, raw = "ae0779c004147ff3de8c5a2bf655b1d23db98199a41b9c36685f76b8bc73b155", canon = "f139f5ceca75ca70b8679fbbd2586014bbcb6a63a824ba10dd6bc3166237099a"),
    "WortelAct Float32" => (fp = 0xaf0ab7a4bc4e3cad, n = 6, raw = "768284b74c0ac624bd092fd91b5976215805ddc5790f1f91af3e3d437dc613c5", canon = "43772d5743a4e68487ee4e20de26ccb09f08dd8859bb2143e64a64e2c10be685"),
    "WortelAct Float64" => (fp = 0x9a9fcac5fc22b7c5, n = 6, raw = "36fb8f7bba3dbe17f0ff6a15b744beec8714119cb42f99a004e159cae7e571a5", canon = "5a9b4566bc34d2e7dbbec4b760e6ef91521bd61471465d07d35e43e5d6d92e98"),
    "WortelAct connected Float32" => (fp = 0x3d018595ea6a08b8, n = 7, raw = "d22e2c4d6a9fe83f62fbf159a7a709dc8e9367b64e51ea1fe86bf68ad5f00b06", canon = "182bbcd4a31e39507fbabac71f5f0931c03f434fcbf13b998ae4f389d0defc0f"),   # re-pinned under P6.3g (D-193): fingerprint only
    "WortelAct connected Float64" => (fp = 0xe1e52da078e581c9, n = 7, raw = "8d13b3d76189d4828236a92a7bc937f5f96d0618d91a5744f986efd262ad11c0", canon = "a2e51ecfd88dfc9ba260b7dba9efbe178e0ffa99160dc68ef69533b70468c9c8"),   # re-pinned under P6.3g (D-193): fingerprint only
    "fixture ODE pair RK4 Float64" => (fp = 0xd8f2c0ff64142fdc, n = 6, raw = "d90e47de8b369e88ca0a4fc7219b3479cf69d5eec674551694c29c8cbb2655b7", canon = "3e175adc02ea555eac5c7ba167813096c2f0fc22ec744221cb0635cd70203fde"),
    "fixture cell Float64" => (fp = 0xa939abe5fad3e067, n = 7, raw = "53078687891393fbd1969563164dbd956bd0c205707dd561204d89139e26ae16", canon = "ada834b39ee612bdef456fdf17eb96cdc0a1fdd6341502ecd4763f1fda81b477"),
    "fixture components Float64" => (fp = 0x96340d875f856e41, n = 7, raw = "d9e8f5d163ecbd4fee155f134149b72031e3786264ce387c385190c8e998c530", canon = "cdfe12f8a60f3f0658face0c118673019854835ef130f7fa4067845d2b3adf50"),
    "fixture discrete component Float64" => (fp = 0x7a057644bac18a54, n = 6, raw = "68b600c6209283ebe839457fe1e9c821d7f9c5833383bb365c81e72260bc77a3", canon = "68b600c6209283ebe839457fe1e9c821d7f9c5833383bb365c81e72260bc77a3"),
    "fixture field Float64" => (fp = 0xde174fb968cfb2e4, n = 7, raw = "8a78ae15c9c0e797d954b642a64456e3ff0ec4cb7dd8a6debe9aa6ec38f628cf", canon = "013f017bfe7c89727a6c87be81296cd6f15ca5214598602e648b4e526e59a5fc"),
    "fixture lifecycle Float64" => (fp = 0x8e8713c64b478b07, n = 10, raw = "e9cd0028afa47e6ae958841e04334be1ac4ab2073c40c08f2d4342b6cee5f4ba", canon = "15679caf1855ee0a9f937b7c799e079276a1da1693a7ea74dcf021afb77e36c1"),
    "fixture spring @extend Float64" => (fp = 0x2a32a89f5fccab80, n = 6, raw = "69680d0cbd5f22148cbb9d1c6d0beaec60840b4be5475bc097057f5a63d12c55", canon = "cfce48cb0a7057273238bea6cf19ecfbaa1d0b2625cf2b590793d78ae1f69e03"),
    "fixture spring @extend² Float64" => (fp = 0xcaa95f46e7a347cd, n = 6, raw = "6e13d26c7b2d5bec48536f49e9aed7aefa30518e65680ab541bbc780b40b9fa1", canon = "536f87d77219a0bc122a59139f70208f521f4e0fa4ed33ca3a0eee978d761d75"),
    "fixture spring Float64" => (fp = 0x60c84fa4ec79b68f, n = 6, raw = "f29fea752e2b0696327a7528141474ec8902b4477b6eff3ef7670d5fb1dc2856", canon = "b7b8192b054884894332cdd61d9a2a5672fe4f5f0d465343a5e0727dc328e440"),
)

@testset "P6.0o P: generated code and fingerprints unchanged" begin
    got = Dict{String, Any}()
    for (label, build, op, kw) in P60O_CASES, T in (Float64, Float32)
        T === Float32 && !(label in P60O_FLOAT32) && continue
        key = "$label $T"
        sys = build()
        h = p60o_code_hashes(sys, kw; T)
        got[key] = (; fp = p60o_fp(sys, op, kw; T), h...)
    end
    @test Set(keys(got)) == Set(keys(P60O_PINS))
    for key in sort(collect(keys(got)))
        pin = get(P60O_PINS, key, nothing)
        ok = pin !== nothing && got[key].fp == pin.fp && got[key].n == pin.n && got[key].raw == pin.raw &&
             got[key].canon == pin.canon
        ok || @info "P6.0o: pin $(repr(key)) => $(repr(got[key]))"
        @test pin !== nothing && got[key].fp == pin.fp
        @test pin !== nothing && got[key].n == pin.n
        @test pin !== nothing && got[key].canon == pin.canon
        @test pin !== nothing && got[key].raw == pin.raw
    end
end
