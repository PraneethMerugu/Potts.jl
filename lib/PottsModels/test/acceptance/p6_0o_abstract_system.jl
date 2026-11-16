# P6.0o (ROADMAP Phase 6, step 0): `PottsSystem <: ModelingToolkitBase.AbstractSystem`.
# Decision: D-137 (implements D-075 §0.1); rewritten for the W-lite LA container (v3 §7.1,
# D-256, cutover C4; re-frozen under the list-A draft D-260).
#
# A `PottsSystem` is an MTK `AbstractSystem` that wraps a complete, flattened ModelingToolkitBase
# `System` (`Potts.inner(sys)`), a field `PDESystem` or `nothing` (`Potts.fields(sys)`) and the
# Potts payload. MTK's accessors, the metadata and `sys.x` are the inner System's; a model is
# complete (`complete` returns it); MTK's `extend` merges two Potts models, MTK's `compose`
# adds components and `rename` renames; `toggle_namespacing` is refused.
#
# The contract checked here:
#  S. Subtype and fields. `PottsSystem <: AbstractSystem`; its fields are exactly `name`,
#     `inner`, `fields`, `part`; the inner System is complete and flat and carries the model
#     name. The keyword constructor takes `checks` (default true): `checks = false` skips the
#     construction checks (a reserved kind name `a` is accepted), `checks = true` runs them;
#     both rebuild a model with the same fingerprint, and so does `Potts.wrap`. MTK's
#     `T(fields...; checks)` rebuild renames the model (MTK's `@set sys.name`).
#  A. Accessors (ModelingToolkitBase's generic functions), checked against Potts' own lists:
#     `equations` (the `@equations` as written, plus each component's equations flattened,
#     `dc₊y`), `unknowns` (`Potts.variables(sys)` in declaration order, plus each component's
#     unknowns, a discrete component's nodes among them; never the lattice ownership, kinds or
#     built-in cell properties; the compiled model's PottsSystem lists the same names once),
#     `parameters` (`Potts.parameters(sys)`, plus each component's), `observed` (one
#     `name ~ expr` per `@observed` quantity; `observe(prob, lhs) == observe(prob, rhs)`),
#     `nameof`. The sweep payload is the inner System's metadata; MTK's metadata functions on
#     the container read and set it. The `PottsSystem` docstring names the accessors and `Potts.inner`.
#  N. `sys.x` is MTK's `getproperty` on the complete inner System: the declared symbol itself
#     for parameters, variables of each scope, `@observed` names and names merged by
#     `@extend` (one and two levels); `sys.dc.y` is the flattened component quantity `dc₊y`;
#     an undeclared name is an `ArgumentError`. MTK's namespaced view
#     (`toggle_namespacing(Potts.inner(sys), true).λ`, `pr₊λ`) and the plain symbol both key
#     the operating point of `PottsProblem`.
#  C. MTK's `extend` merges two models; `show` is Potts' (text/plain starts with
#     "PottsSystem <name>", names the kinds and the inner System; the two-argument form does
#     not throw); MTK's `complete` returns the model, `toggle_namespacing` is an
#     `ArgumentError`, and `iscomplete(sys)` is true, as for the inner System.
#     `Potts.lattice(sys)` (public, not exported; D-137 rule 6) returns the lattice.
#  E. MTK's `compose` adds an MTK System to a PottsSystem; a Potts model with CPM statements as
#     a component, or a PottsSystem inside a plain System, is an `ArgumentError` (no recursion,
#     no build); `ODEProblem`/`JumpProblem` (plain and `{iip}`) on a PottsSystem or a compiled
#     one are `ArgumentError`s naming `PottsProblem`; MTK's `extend` between a PottsSystem and a
#     plain `System` is an `ArgumentError` naming `extend` and `@components` either way (D-039).
#  Q. Aqua ambiguities and piracy on Potts are clean.
#  G. A source scan: no property read `<x>sys.<field>`, `base.<field>`, `$bname.<field>`
#     (and per file `b.`, `m.`, `s.`, see P60O_RECEIVERS) of a PottsSystem or PottsPart field
#     name in src/ or ext/ outside comments.
#  P. Generated code is byte-identical and fingerprints are unchanged for every PottsModels
#     model (Float64 and Float32) and a representative fixture set (recorded on 33f681df and
#     unchanged by the container rewrite).
using Potts: CorePotts
using Aqua: Aqua

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

# a field with a drive, a frozen kind, per-kind temperature; the field `c` is a plain MTK
# PDESystem whose input `dark` (0/1) is bound at `@fields`
function p60o_field_pde()
    t, L = Potts.t, Potts.LatticePDE
    Potts.ModelingToolkitBase.@parameters x y
    Potts.ModelingToolkitBase.@variables c(..) dark(..)::Bool [input = true]
    C = c(t, x, y)
    return Potts.ModelingToolkitBase.PDESystem([Potts.D(C) ~ 0.1 * L.Δ(C) + 0.02 * dark(t, x, y) - 0.01 * C],
        [c(0, x, y) ~ 0.0], L.lattice_domain(t, (x, y), (16, 16)), [t, x, y], [C, dark(t, x, y)], Any[]; name = :p60o_field)
end
@potts_model P60oField begin
    @kinds medium wall[frozen] dark light
    @parameters begin
        Tk[kind] = [0.0, 0.0, 5.0, 20.0]
        J[kind, kind] = [0 30 16 16; 30 0 30 30; 16 30 2 11; 16 30 11 14]
        χ = 3.0
    end
    @lattice Lattice((16, 16); neighborhood = Moore(1))
    @fields c = p60o_field_pde() (:dark => kind == dark)
    @energy begin
        Volume(dark, light; target = 9.0, strength = 1.0)
        Adhesion(J)
    end
    @drive Chemotaxis(c; strength = χ, kinds = (dark,))
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

p60o_problem(sys, op, kw; T = Float64) = PottsProblem(sys, op, (0, 1); T, kw...)
p60o_fp(sys, op, kw; T = Float64) = p60o_problem(sys, op, kw; T).f.fingerprint

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
# S. Subtype, the four fields, the constructors

@testset "P6.0o S: PottsSystem <: AbstractSystem wraps a complete inner System" begin
    @test PottsSystem <: P60O_M.AbstractSystem
    @test GranerGlazier(; name = :gg) isa P60O_M.AbstractSystem
    @test fieldnames(PottsSystem) == (:name, :inner, :fields, :part)
    sys = P60oCell(; name = :pr)
    inner = Potts.inner(sys)
    @test inner isa P60O_M.System && P60O_M.iscomplete(inner) && isempty(P60O_M.get_systems(inner))
    @test nameof(inner) === :pr && Potts.fields(sys) === nothing
    # the keyword constructor, with and without the construction checks (a reserved kind `a`)
    part = getfield(sys, :part)
    kw = (f => getfield(part, f) for f in fieldnames(Potts.PottsPart))
    s2 = PottsSystem(; name = :pr, kw...)
    @test s2 isa PottsSystem && nameof(s2) === :pr && p60o_fp(s2, P60O_OP12, (;)) == p60o_fp(sys, P60O_OP12, (;))
    bad = (; (f => getfield(part, f) for f in fieldnames(Potts.PottsPart))..., kinds = [:medium, :a])
    @test PottsSystem(; name = :pr, bad..., checks = false) isa PottsSystem
    @test_throws ArgumentError PottsSystem(; name = :pr, bad..., checks = true)
    @test_throws ArgumentError PottsSystem(; name = :pr, bad...)
    # `Potts.wrap` with the same parts gives the same model
    w = Potts.wrap(:pr, inner, nothing, part)
    @test p60o_fp(w, P60O_OP12, (;)) == p60o_fp(sys, P60O_OP12, (;))
    @test_throws ArgumentError Potts.wrap(:other, inner, nothing, part)
    # MTK rebuilds a system as `T(fields...; checks)` (`@set sys.name = …`): the same model,
    # renamed when the name differs
    fs = [getfield(sys, f) for f in fieldnames(PottsSystem)]
    @test p60o_fp(PottsSystem(fs...; checks = false), P60O_OP12, (;)) == p60o_fp(sys, P60O_OP12, (;))
    @test nameof(PottsSystem(:other, fs[2:end]...; checks = false)) === :other
end

# ---------------------------------------------------------------------------------------
# A. Accessors: MTK's, answered by the inner System

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
    # site and edge variables are unknowns too; the lattice, built-ins and fields are not (a
    # field and its equation are in the model's PDESystem, `Potts.fields`)
    @test Set(p60o_names(U(P60oLife(; name = :life)))) == Set([:m, :q, :act, :total])
    @test isempty(U(P60oField(; name = :fld))) && isempty(E(P60oField(; name = :fld)))
    @test length(P60O_M.equations(Potts.fields(P60oField(; name = :fld)))) == 1
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
    # the published models have no components: the accessors are Potts' own lists (the
    # fields are in `Potts.fields`)
    for (label, build, _, _) in P60O_CASES[1:8]
        m = build()
        @test Set(p60o_names(U(m))) == Set(Potts.info(v).name for v in Potts.variables(m) if Potts.info(v).role !== :field)
        @test Set(p60o_names(P(m))) == Set(Potts.info(v).name for v in Potts.parameters(m))
    end
end

@testset "P6.0o A: nameof; the metadata is the inner System's" begin
    sys = P60oCell(; name = :pr)
    @test nameof(sys) === :pr
    @test P60O_M.getmetadata(Potts.inner(sys), Potts.PottsSweepSpec, nothing) isa Potts.PottsSweepSpec
    @test P60O_M.getmetadata(Potts.inner(sys), P60oKey, :none) === :none
    # MTK's metadata functions on the container read and set the inner System's
    @test P60O_M.getmetadata(sys, P60oKey, :none) === :none
    @test P60O_M.getmetadata(sys, Potts.PottsSweepSpec, nothing) isa Potts.PottsSweepSpec
    @test P60O_M.getmetadata(P60O_M.setmetadata(sys, P60oKey, 42), P60oKey, :none) == 42
    # documented
    doc = string(Base.Docs.doc(PottsSystem))
    for w in ("equations", "unknowns", "parameters", "observed", "nameof", "Potts.inner")
        @test occursin(w, doc)
    end
end

# ---------------------------------------------------------------------------------------
# N. `sys.x`: MTK's getproperty on the complete inner System

@testset "P6.0o N: sys.x is the declared symbol" begin
    sys = P60oCell(; name = :pr)
    for n in (:λ, :J, :x, :g, :total)
        @test p60o_name(getproperty(sys, n)) === n
    end
    @test isequal(sys.λ, p60o_named(Potts.parameters(sys), :λ)) && isequal(sys.x, p60o_named(Potts.variables(sys), :x))
    @test p60o_name(GranerGlazier(; name = :gg).V₀) === :V₀
    @test p60o_name(P60oLife(; name = :life).act) === :act
    @test p60o_name(P60oField(; name = :fld).c) === :c
    @test p60o_name(P60oSpring(; name = :sp).rest) === :rest
    # names merged by @extend, one and two levels
    ext = P60oSpringExt(; name = :ext)
    @test p60o_name(ext.k) === :k && p60o_name(ext.rest) === :rest && p60o_name(ext.len) === :len
    ext2 = P60oSpringExt2(; name = :ext2)
    @test p60o_name(ext2.k) === :k && p60o_name(ext2.len) === :len && p60o_name(ext2.χ) === :χ
    # component members, through the component: the flattened quantity
    comp = P60oComp(; name = :pr)
    @test p60o_name(comp.dc.y) === :dc₊y && p60o_name(comp.dc.k) === :dc₊k && p60o_name(comp.clk.m) === :clk₊m
    @test any(isequal(Potts.Symbolics.unwrap(comp.dc.y)), P60O_M.unknowns(comp))
    # an undeclared name
    @test_throws ArgumentError sys.nosuch
    @test_throws ArgumentError comp.dc.nosuch
    # MTK's namespaced view of the inner System
    @test p60o_name(P60O_M.toggle_namespacing(Potts.inner(sys), true).λ) === :pr₊λ
    # the symbols key the operating point, and so do the namespaced ones
    prob = PottsProblem(sys, [P60O_OP12..., sys.λ => 3.0, sys.x => 2.5], (0, 1))
    @test prob.p.λ == 3.0 && all(==(2.5), prob.u0.cell.x[1:2])
    ns = P60O_M.toggle_namespacing(Potts.inner(sys), true)
    @test PottsProblem(sys, [P60O_OP12..., ns.λ => 4.0], (0, 1)).p.λ == 4.0
end

# ---------------------------------------------------------------------------------------
# C. extend, show, lattice; MTK's complete returns the model, toggle_namespacing is refused

@testset "P6.0o C: extend and show; MTK's complete and toggle_namespacing on a PottsSystem" begin
    sys = P60oCell(; name = :pr)
    @test parentmodule(which(show, Tuple{IO, MIME"text/plain", PottsSystem})) === Potts
    # extend between Potts systems: a PottsSystem with the union of the declarations
    ext = extend(P60oExtra(; name = :extra), sys)
    @test ext isa PottsSystem && nameof(ext) === :extra
    @test Set(p60o_names(P60O_M.parameters(ext))) == Set([:λ, :T, :J, :μ])
    @test p60o_fp(ext, P60O_OP12, (;)) != p60o_fp(sys, P60O_OP12, (;))
    # MTK's `complete` returns the model, which is complete as its inner System is; MTK's
    # `extend` is the merge above; `toggle_namespacing` is refused
    @test P60O_M.complete(sys) === sys
    @test P60O_M.extend === extend
    @test_throws ArgumentError P60O_M.toggle_namespacing(sys, false)
    @test P60O_M.iscomplete(sys) && P60O_M.iscomplete(Potts.inner(sys))
    # show
    txt = sprint(show, MIME"text/plain"(), sys)
    @test startswith(txt, "PottsSystem pr")
    @test occursin("kinds: medium, host", txt) && occursin("inner: System pr", txt)
    two = sprint(show, sys)
    @test occursin("pr", two) && length(two) < 10_000
    @test startswith(sprint(show, MIME"text/plain"(), GranerGlazier(; name = :gg); context = :limit => true), "PottsSystem gg")
end

@testset "P6.0o C: Potts.lattice, the public lattice accessor (D-137 rule 6)" begin
    @test Base.ispublic(Potts, :lattice) && !Base.isexported(Potts, :lattice)
    for (label, build, _, _) in P60O_CASES[[1, 4, 9, 12]]
        s = build()
        @test Potts.lattice(s) === getfield(getfield(s, :part), :lattice)
    end
    @test Potts.lattice(GranerGlazier(; name = :gg)).dims == (72, 72)
    @test Potts.lattice(MerksVasculogenesis(; name = :m, lattice = (8, 8))).dims == (8, 8)
end

# ---------------------------------------------------------------------------------------
# E. Loud paths and refusals

@testset "P6.0o E: compose, ODEProblem, JumpProblem, extend with a System" begin
    sys = P60oCell(; name = :pr)
    other = P60oExtra(; name = :extra)
    mtk = p60o_decay()
    # MTK's compose adds an MTK System to a PottsSystem; a Potts model with CPM statements as a
    # component, or a PottsSystem inside a plain System, is refused (never recurses, never builds)
    @test P60O_M.compose(sys, [mtk]) isa PottsSystem
    for f in (
            () -> P60O_M.compose(sys, [other]), () -> P60O_M.compose(sys, other),
              () -> P60O_M.compose(mtk, [sys]), () -> P60O_M.compose(mtk, sys))
        @test_throws ArgumentError f()                  # a StackOverflowError (recursion) fails this
    end
    for s in (sys, mtkcompile(sys))
        @test p60o_clear(() -> P60O_M.ODEProblem(s, [], (0.0, 1.0)), "PottsProblem")
        @test p60o_clear(() -> P60O_M.ODEProblem(s, P60O_OP12, (0.0, 1.0)), "PottsProblem")
        @test p60o_clear(() -> P60O_M.JumpProblem(s, [], (0.0, 1.0)), "PottsProblem")
    end
    # the curly forms too (SciMLBase's `{iip}` constructors accept any `f`)
    @test p60o_clear(() -> P60O_M.ODEProblem{true}(sys, [], (0.0, 1.0)), "PottsProblem")
    @test p60o_clear(() -> Potts.SciMLBase.NonlinearProblem{true}(sys, [], (0.0, 1.0)), "PottsProblem")
    @test p60o_clear(() -> P60O_M.extend(sys, mtk), "extend", "@components")
    @test p60o_clear(() -> P60O_M.extend(mtk, sys), "extend", "@components")
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

const P60O_FIELDS = ("name", "inner", "part", "kinds", "frozen_kinds", "kind_classes", "lattice", "parameters", "variables",
    "relations", "energies", "drives", "constraints", "updates", "equations", "divisions", "relationships",
    "link_rules", "observed", "components", "discrete", "sweep", "structural", "sources", "eqs", "unknowns",
    "ps", "systems", "metadata", "namespacing", "complete", "iv", "var_to_name", "description", "bcs", "bindings")

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
