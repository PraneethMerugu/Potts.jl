# The symbolic vocabulary of a Potts model: parameters, scoped variables, built-in names,
# kind tables, relation gathers and the helpers `@potts_model` rewrites expressions into.
#
# Every model quantity is a Symbolics expression carrying a `PottsInfo` metadata record
# (its role and options). Lowering (`lower.jl`) maps roles to state reads.

"""Metadata key for Potts symbolic quantities."""
struct PottsInfo end

"""
Role and options of a symbolic quantity:

- `:param` — scalar parameter (`default` value)
- `:kindtable` — kind-indexed parameter array (`J[kind, kind′]`), `default` an array over
  kinds including the medium
- `:site`, `:cell`, `:model`, `:field` — scoped state variables `x(t)`
- `:builtin` — names bound by domains (`volume`, `kind′`, `source`, …)
- `:bound` — the iteration variable of a relation gather (`options.relation`, `options.op`)
"""
struct Info
    role::Symbol
    name::Symbol
    default::Any
    options::NamedTuple
end

info(x) = (u = Symbolics.unwrap(x); u isa SymbolicUtils.BasicSymbolic ? SymbolicUtils.getmetadata(u, PottsInfo, nothing) : nothing)
role(x) = (i = info(x); i === nothing ? :none : i.role)
_tag(x, i::Info) = Symbolics.wrap(SymbolicUtils.setmetadata(Symbolics.unwrap(x), PottsInfo, i))

_sym(name::Symbol) = Symbolics.unwrap(only(Symbolics.@variables $name))

# ---------------------------------------------------------------------------------------
# Built-in names

const BUILTIN_NAMES = (:volume, :surface, :kind, :kind′, :owner, :owner′, :id, :generation,
    :weight, :source, :target, :old, :new, :mcs, :position, :a, :b, :distance)

"""Built-in symbols, one per name in `BUILTIN_NAMES` (shared by every model)."""
const B = NamedTuple{BUILTIN_NAMES}(map(n -> _tag(_sym(n), Info(:builtin, n, nothing, (;))), BUILTIN_NAMES))

# Tracker deltas substituted during ΔH derivation (not user-visible)
const DVOLUME = _tag(_sym(:δvolume), Info(:delta, :volume, nothing, (;)))
const DSURFACE = _tag(_sym(:δsurface), Info(:delta, :surface, nothing, (;)))

# ---------------------------------------------------------------------------------------
# Declarations

"""`parameter(name, default)`: a scalar model parameter."""
parameter(name::Symbol, default) = _tag(_sym(name), Info(:param, name, default, (;)))

"""`kind_parameter(name, values)`: a parameter indexed by kind (medium included)."""
kind_parameter(name::Symbol, values) = _tag(_sym(name), Info(:kindtable, name, values, (;)))

const SCOPES = (:site, :cell, :model, :field, :edge)

"""`variable(x, scope; default, options...)`: tag an `x(t)` variable with its scope."""
function variable(x, scope::Symbol; default = 0.0, options...)
    scope in SCOPES || throw(ArgumentError("unknown scope `$scope`; use one of $SCOPES"))
    u = Symbolics.unwrap(x)
    name = SymbolicUtils.iscall(u) ? nameof(SymbolicUtils.operation(u)) : nameof(u)
    return _tag(x, Info(scope, name, default, NamedTuple(options)))
end

# ---------------------------------------------------------------------------------------
# Symbolic operations recognised by lowering

"""`at(x, i...)`: `x` at an explicit site/cell (`act[target]`) or kind-table entry (`J[a, b]`)."""
function at end
"""`gather(n, anchor, body, cond)`: fold of `body` over relation neighbours `n` of `anchor`."""
function gather end
"""Lattice Laplacian of a field (zero-flux at closed boundaries)."""
function Δ end

at(x, i) = error("`at` is symbolic-only")
"""`at2(J, a, b)`: a two-index kind-table entry `J[a, b]`."""
at2(x, i, j) = error("`at2` is symbolic-only")
Δ(x) = error("`Δ` is symbolic-only")
gather(n, a, b, c) = error("`gather` is symbolic-only")

Symbolics.@register_symbolic at(x, i)
Symbolics.@register_symbolic at2(x, i, j)
Symbolics.@register_symbolic gather(n, a, b, c)
Symbolics.@register_symbolic Δ(x)

# ---------------------------------------------------------------------------------------
# Helpers the macro rewrites user syntax into

"""`x[i...]` inside a model: indexing of symbolic quantities, `getindex` otherwise."""
_index(x::Num, i) = at(x, i)
_index(x::Num, i, j) = at2(x, i, j)
_index(x, i...) = getindex(x, i...)

# `&&`, `||`, `!` in models become the symbolic `&`, `|`, `!` (operands are pure, so
# non-short-circuit evaluation is equivalent).
_andq(a, b) = a isa Bool && b isa Bool ? a && b : a & b
_orq(a, b) = a isa Bool && b isa Bool ? a || b : a | b
_notq(a) = !a

"""Neighbours of `anchor` over a relation spec, as the iterator of a gather."""
struct Around{R}
    relation::R
    anchor::Any
end
_around(spec, anchor) = Around(spec, anchor)

const FOLDS = (:sum, :prod, :mean, :geomean, :geomean_shifted, :minimum, :maximum, :count,
    :any, :all)

"""`geomean_shifted(itr)`: `exp(mean(log1p.(itr))) − 1` (the legacy Act mean, D-034)."""
geomean_shifted(itr) = expm1(sum(log1p, itr) / length(itr))
"""`geomean(itr)`: geometric mean, zero if any value is zero (Niculescu et al. 2015)."""
geomean(itr) = any(iszero, itr) ? zero(first(itr)) : exp(sum(log, itr) / length(itr))
"""`mean(itr)`: arithmetic mean (a fold over relations inside models)."""
mean(itr) = sum(itr) / length(itr)

const _GATHER_COUNT = Ref(0)

"""
    _gather(fold, body, around, cond)

`fold(body(n) for n in around if cond(n))` with a fresh bound site variable `n`.
"""
function _gather(fold, body, a::Around, cond = nothing)
    op = nameof(fold)
    op in FOLDS || throw(ArgumentError("`$op` is not a recognised fold over a relation; use one of $FOLDS"))
    _GATHER_COUNT[] += 1
    n = _tag(_sym(Symbol(:n_, _GATHER_COUNT[])), Info(:bound, :n, nothing, (; relation = a.relation, op)))
    b = body(n)
    c = cond === nothing ? true : cond(n)
    return gather(n, a.anchor, b, c)
end

# ---------------------------------------------------------------------------------------
# Domains, statements

"""Energy domains: `cells(kinds...)`, `contacts`, `contacts(relation)`, `sites`."""
struct CellDomain
    kinds::Vector{Int}
end
struct ContactDomain
    relation::Symbol                 # a named relation (`:contact` = the lattice neighborhood)
end
struct SiteDomain end
struct CopyDomain end

cells(kinds::Integer...) = CellDomain(collect(Int, kinds))
(d::ContactDomain)(relation::Symbol) = ContactDomain(relation)
const contacts = ContactDomain(:contact)
const sites = SiteDomain()
"""The copy-attempt domain of `@drive copy => expr`."""
const COPY = CopyDomain()

struct EnergyTerm
    domain::Any
    expr::Any
end
struct Drive
    expr::Any
end
"""A hard constraint: `expr` (proposal scope) must hold, or a built-in connectivity rule."""
struct Constraint
    kind::Symbol                   # :expr, :connectivity, :merks_connectivity, :no_extinction
    kinds::Vector{Int}
    expr::Any
end
"""`connectivity(kinds...; rule = :local)`: forbid copies that locally disconnect a cell of
those kinds (`rule = :merks` is the legacy Merks et al. 2006 ring rule)."""
connectivity(kinds::Integer...; rule::Symbol = :local) =
    Constraint(rule === :merks ? :merks_connectivity : :connectivity, collect(Int, kinds), nothing)
"""`no_extinction`: forbid copies that remove a cell's last site."""
const no_extinction = Constraint(:no_extinction, Int[], nothing)

energy(p::Pair) = EnergyTerm(p.first, p.second)

# ---------------------------------------------------------------------------------------
# Relationships (cell–cell links, CorePotts `relationships.jl`)

"""`@relationship name(cell, cell) capacity = k`: a symmetric link set, at most `k` per cell."""
struct RelationshipSpec
    name::Symbol
    capacity::Int
end
relationship(name::Symbol; capacity::Integer = 4) = RelationshipSpec(name, Int(capacity))
struct RelationshipRef
    name::Symbol
end
"""Energy domain `edges(rel)`: every link once; names `a`, `b` (cells), `distance`, edge variables."""
struct EdgeDomain
    relationship::Symbol
end
edges(r::RelationshipRef) = EdgeDomain(r.name)
"""`@link rel when = cond` / `@unlink rel when = cond`, checked every `every` MCS on the host."""
struct LinkRule
    relationship::Symbol
    action::Symbol          # :link or :unlink
    when::Any
    every::Int
end
link_rule(action::Symbol, r::RelationshipRef; when, every::Integer = 1) = LinkRule(r.name, action, when, Int(every))
"""`new_contact(a, b)`: the pair touches and is not yet linked (the candidates of `@link`)."""
new_contact(a, b) = true
drive(p::Pair{CopyDomain}) = Drive(p.second)
drive(p::Pair) = throw(ArgumentError("a drive must be `copy => expr`"))
constraint(c::Constraint) = c
constraint(x) = Constraint(:expr, Int[], x)

"""Synchronous or on-copy update `lhs ~ rhs` in `phase` (`:before_mcs`, `:after_mcs`, `:on_copy`)."""
struct Update
    phase::Symbol
    eq::Equation
    every::Int
end
"""`Every(n)`: update cadence."""
struct Every
    n::Int
end
update(phase::Symbol, eq::Equation) = Update(phase, eq, 1)
update(phase::Symbol, e::Every, eq::Equation) = Update(phase, eq, e.n)

"""
    @divide cells(kinds) when = cond, along = normal, x => rule, …

A division rule: `when` (cell scope, may use `mcs`), `along` (`principal_axis()`,
`major_axis()`, `RandomPlane()`, or a vector expression), daughter state rules
`x => value` (applied to both parent and daughter) or `x => Split()`.
"""
struct DivideRule
    domain::CellDomain
    when::Any
    along::Any
    rules::Vector{Pair{Any, Any}}
end
struct AlongMinor end
struct AlongMajor end
struct AlongRandom end
_principal_axis() = AlongMinor()     # divide across the long axis (CompuCell3D default)
_major_axis() = AlongMajor()
_minor_axis() = AlongMinor()
_random_plane() = AlongRandom()
"""Daughter state rule: halve the quantity between parent and daughter."""
struct Split end

function divide(d::CellDomain, args...; when, along = AlongMinor())
    rules = Pair{Any, Any}[a for a in args if a isa Pair]
    length(rules) == length(args) || throw(ArgumentError("@divide state rules must be `x => rule`"))
    return DivideRule(d, when, along, rules)
end

# ---------------------------------------------------------------------------------------
# Lattice and sweep specifications

"""The lattice of a model: dims, boundaries, spacing and the contact neighborhood."""
struct LatticeSpec{N, B, S, R}
    dims::NTuple{N, Int}
    boundary::B
    spacing::S
    neighborhood::R
end
lattice_spec(dims; boundary = Periodic(), neighborhood = Moore(1), spacing = nothing) =
    LatticeSpec(Tuple(Int.(dims)), boundary, spacing, neighborhood)
core_lattice(l::LatticeSpec) = Lattice(l.dims; boundary = l.boundary)

"""Field solver of `@sweep`: explicit Euler with `substeps` (auto if `nothing`) and an
optional lower clip (legacy Potts clips concentrations at 0)."""
Base.@kwdef struct ExplicitEuler
    substeps::Union{Nothing, Int} = nothing
    lower::Union{Nothing, Float64} = nothing
end

"""The sweep protocol: acceptance law, temperature expression, MCS duration, field solver."""
struct SweepSpec
    law::Symbol
    temperature::Any
    offset::Float64
    mcs_duration::Float64
    field_solver::ExplicitEuler
end
sweep_spec(law::Symbol; temperature, offset = 0.0, mcs_duration = 1.0,
    field_solver = ExplicitEuler()) = SweepSpec(law, temperature, Float64(offset),
    Float64(mcs_duration), field_solver)

"""Names bound inside `@potts_model` bodies (the modelling vocabulary, not exported)."""
const DSL = (; cells, contacts, sites, edges, new_contact, connectivity, no_extinction,
    principal_axis = _principal_axis, major_axis = _major_axis, minor_axis = _minor_axis,
    RandomPlane = _random_plane, Split, ExplicitEuler, Every, geomean, geomean_shifted, mean, Δ)
