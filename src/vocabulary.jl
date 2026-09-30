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
    :weight, :source, :target, :old, :new, :mcs, :position, :a, :b, :distance, :cluster,
    :cluster_volume, :cluster_surface, :time, :site, :site′, :major_length, :local_components, :ring_arcs,
    :ring_cells)

"""Built-in symbols, one per name in `BUILTIN_NAMES` (shared by every model)."""
const B = NamedTuple{BUILTIN_NAMES}(map(n -> _tag(_sym(n), Info(:builtin, n, nothing, (;))), BUILTIN_NAMES))

# Tracker deltas substituted during ΔH derivation (not user-visible)
const DVOLUME = _tag(_sym(:δvolume), Info(:delta, :volume, nothing, (;)))
const DSURFACE = _tag(_sym(:δsurface), Info(:delta, :surface, nothing, (;)))
const DCSURFACE = _tag(_sym(:δcluster_surface), Info(:delta, :cluster_surface, nothing, (;)))
# not a delta: the cell's major length after the copy (not additive)
const DMAJOR = _tag(_sym(:δmajor_length), Info(:delta, :major_length, nothing, (;)))

# ---------------------------------------------------------------------------------------
# Declarations

"""`parameter(name, default; unit)`: a scalar model parameter (`unit`: MTK `VariableUnit`)."""
parameter(name::Symbol, default; unit = nothing) = _with_unit(_tag(_sym(name), Info(:param, name, default, (;))), unit)

_with_unit(x, ::Nothing) = x
_with_unit(x, u) = Symbolics.wrap(SymbolicUtils.setmetadata(Symbolics.unwrap(x), ModelingToolkitBase.VariableUnit, u))

"""`kind_parameter(name, values)`: a parameter indexed by kind (medium included)."""
kind_parameter(name::Symbol, values; unit = nothing) = _with_unit(_tag(_sym(name), Info(:kindtable, name, values, (;))), unit)

const SCOPES = (:site, :cell, :model, :field, :edge)

"""
`variable(x, scope; default, options...)`: tag an `x(t)` variable with its scope. A scope
outside `SCOPES` names a relationship: `rest(bond)` is an edge variable of `@relationship
bond` (option `relationship = :bond`; `mtkcompile` checks the name). `rest(edge)` belongs
to the model's only relationship.
"""
const _VARIABLE_OPTIONS = (:clear_on_ownership_change, :vector, :index, :relationship)

function variable(x, scope::Symbol; default = 0.0, unit = nothing, kwargs...)
    options = NamedTuple(kwargs)
    if !(scope in SCOPES)
        haskey(options, :relationship) && throw(ArgumentError("`relationship` is given twice"))
        options = (; options..., relationship = scope)
        scope = :edge
    end
    u = Symbolics.unwrap(x)
    name = SymbolicUtils.iscall(u) ? nameof(SymbolicUtils.operation(u)) : nameof(u)
    haskey(options, :relationship) && scope !== :edge &&
        throw(ArgumentError("variable `$name`: `relationship` applies to edge variables"))
    for (k, v) in pairs(options)
        k in _VARIABLE_OPTIONS || throw(ArgumentError("variable `$name`: unknown option `$k` " *
                                                      "(options: `unit`, `clear_on_ownership_change`)"))
        k === :clear_on_ownership_change && v === true && !(scope in (:site, :field)) &&
            throw(ArgumentError("variable `$name`: `clear_on_ownership_change` applies to site variables"))
    end
    return _with_unit(_tag(x, Info(scope, name, default, options)), unit)
end

# ---------------------------------------------------------------------------------------
# Vector quantities: `p(cell)[1:2]`, `d[1:3] = …` declare scalar components `p_1, p_2, …`
# (tagged `vector = :p, index = i`) and bind `p` to this vector of them.

"""
    QuantityVector

A declared vector quantity (`@variables p(cell)[1:2]`, `@parameters d[1:2]`): an
`AbstractVector` of its scalar components `p_1, p_2, …`, which are ordinary variables or
parameters. `p[i]` is component `i`; `p[new]` (a cell or site) the vector there; `Pre(p)`,
`p ~ rhs`, `dot`, `norm`, `normalize` and arithmetic act component-wise.
"""
struct QuantityVector <: AbstractVector{Num}
    name::Symbol
    components::Vector{Num}
end
Base.size(v::QuantityVector) = size(v.components)
Base.getindex(v::QuantityVector, i::Int) = v.components[i]

_component_name(name, i) = Symbol(name, :_, i)
_component(v, i) = v isa Union{AbstractVector, Tuple} ? v[i] : v
function _vector_length(r)
    r isa AbstractUnitRange && first(r) == 1 && return length(r)
    throw(ArgumentError("vector quantities are declared with a range `1:n`"))
end

"""`vector_variable(name, 1:n, scope; default, unit, options...)`: components `name_i` of a vector variable."""
function _check_components(name, v, n)
    v isa Union{AbstractVector, Tuple} && length(v) != n &&
        throw(ArgumentError("`$name` has $n components; got $(length(v)) values"))
    return v
end

function vector_variable(name::Symbol, r, scope::Symbol; default = 0.0, unit = nothing, options...)
    n = _vector_length(r)
    _check_components(name, default, n)
    return QuantityVector(name, [variable(only(Symbolics.@variables $(_component_name(name, i))(t)), scope;
                                     default = _component(default, i), unit = _component(unit, i),
                                     vector = name, index = i, options...) for i in 1:n])
end
"""`vector_parameter(name, 1:n, default; unit)`: components `name_i` of a vector parameter."""
function vector_parameter(name::Symbol, r, default; unit = nothing)
    n = _vector_length(r)
    _check_components(name, default, n)
    return QuantityVector(name, [_with_unit(_tag(_sym(_component_name(name, i)),
                                                 Info(:param, _component_name(name, i), _component(default, i), (; vector = name, index = i))),
                                            _component(unit, i)) for i in 1:n])
end

"""`lhs ~ rhs` in updates and equations: component-wise for vectors."""
_eq(a, b) = a ~ b
function _eq(a::AbstractVector, b)
    b isa AbstractVector || return [x ~ b for x in a]
    length(a) == length(b) || throw(DimensionMismatch("`~` between vectors of lengths $(length(a)) and $(length(b))"))
    return [x ~ y for (x, y) in zip(a, b)]
end
"""`D(x)`, component-wise for vectors."""
_D(x) = D(x)
_D(v::AbstractVector) = map(_D, v)

_dot(a::AbstractVector, b::AbstractVector) =
    (length(a) == length(b) || throw(DimensionMismatch("dot of vectors of lengths $(length(a)) and $(length(b))")); sum(a .* b))
_norm(a::AbstractVector) = sqrt(sum(abs2, a))
"""`normalize(v)`: `v / norm(v)`, and zero where `norm(v) == 0`."""
_normalize(a::AbstractVector) = (n = _norm(a); [ifelse(n > 0, x / n, zero(x)) for x in a])

"""Spatial dimension of the lattice being declared (for `centroid()`, `displacement(c)`)."""
const _DIM = Ref(0)
"""Depth of `@extend` bases being built inside another model's constructor."""
const _NESTING = Ref(0)
"""Build an `@extend` base: numbering continues, and the outer model's lattice dimension is kept."""
function _nested(f)
    dim = _DIM[]
    _NESTING[] += 1
    try
        return f()
    finally
        _NESTING[] -= 1
        _DIM[] = dim
    end
end
_lattice_dim() = _DIM[] > 0 ? _DIM[] :
                 throw(ArgumentError("`centroid()` and `displacement(c)` need the model's @lattice declared before them"))

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
"""`population(n, body, cond)`: fold of `body` over live cells or sites `n` (`n`'s metadata)."""
population(n, b, c) = error("`population` is symbolic-only")

Symbolics.@register_symbolic at(x, i)
Symbolics.@register_symbolic at2(x, i, j)
Symbolics.@register_symbolic gather(n, a, b, c)
Symbolics.@register_symbolic population(n, b, c)
Symbolics.@register_symbolic Δ(x)
"""`cell_centroid(k)`: coordinate `k` of the current cell's centroid (cell scope)."""
cell_centroid(k) = error("`cell_centroid` is symbolic-only")
"""`copy_displacement(c, k)`: change of cell `c`'s centroid along axis `k` by the copy (proposal scope)."""
copy_displacement(c, k) = error("`copy_displacement` is symbolic-only")
Symbolics.@register_symbolic cell_centroid(k)
Symbolics.@register_symbolic copy_displacement(c, k)

"""
`centroid(k)`: coordinate `k` of the cell's centroid (lattice units; periodic axes wrap
into the lattice). Cell scope: updates, equations, division conditions and rules, observed.
"""
_centroid(k::Integer) = cell_centroid(Num(k))
_centroid() = Num[_centroid(k) for k in 1:_lattice_dim()]
"""
`displacement(c, k)`: how far the copy moves the centroid of cell `c` (`new` or `old`) along
axis `k` (minimum image on periodic axes; zero for the medium or other cells). Proposal
scope: drives and on-copy updates, e.g. persistent motion
`copy => -μ * (px[new] * displacement(new, 1) + px[old] * displacement(old, 1) + …)`.
"""
_displacement(c, k::Integer) = copy_displacement(c, Num(k))
_displacement(c) = Num[_displacement(c, k) for k in 1:_lattice_dim()]

"""
`integral(x)`: the sum of the site expression `x` over the cell's sites (cell scope; divide
by `volume` for the mean). Recomputed at the start of the after-MCS phases (and of the
before-MCS phases when they read it), so it reflects the state after the copy sweep.
"""
cell_integral(x) = error("`integral` is symbolic-only")
Symbolics.@register_symbolic cell_integral(x)
"""Cell-state name of the tracker for `integral(x)`."""
_integral(x) = cell_integral(x isa Num ? x : Num(x))
_integral_name(x) = Symbol(:integral_, string(hash(Symbolics.unwrap(x)); base = 62))

"""`history_lag(x, k)`: `x` at the end of the MCS `k` before the current one."""
history_lag(x, k) = error("`history_lag` is symbolic-only")
Symbolics.@register_symbolic history_lag(x, k)

"""
`Pre(x)`: the value of `x` before the update being written (MTK). `Pre(x, k)`: the value of
the site, field or model quantity `x` at the end of the MCS `k` before the current one (the
MCS boundary, after the lifecycle), read from a ring buffer of depth `k`. `Pre(x, 1)` is
`Pre(x)` unless `x` changed earlier in the same MCS. Before the run started, the lag is the
initial value. Lags are available where the MCS clock is: updates, equations,
division conditions and rules, link rules.
"""
_pre(x) = ModelingToolkitBase.Pre(x)
_pre(v::AbstractVector, k...) = [_pre(x, k...) for x in v]
_pre(x, k::Integer) = (k >= 1 || throw(ArgumentError("Pre(x, k) needs k ≥ 1")); history_lag(x, Num(k)))

"""
`_nonzero(x)`: a Boolean node of a discrete component read from its slot (stored in the
model's scalar type as exact 0/1): `true` unless the stored value is zero. Symbolically it
has symtype `Bool`, so it stands in for the MTK `Bool` variable in the component's rules
(P6.0k).
"""
_nonzero(x::Real) = !iszero(x)
_nonzero(x::Bool) = x
Symbolics.@register_symbolic _nonzero(x)::Bool

"""`random_uniform(n)`: the `n`-th authored draw of a model, uniform in (0, 1)."""
random_uniform(n) = error("`random_uniform` is symbolic-only")
Symbolics.@register_symbolic random_uniform(n)

"""
`rand()` inside a model: a uniform draw in (0, 1), fresh per MCS and per cell (or site),
from its own counter-based stream (reproducible on any backend and schedule). Available in
updates, equations, division conditions and rules; not in energies, drives or constraints
(a random ΔH would break detailed balance).
"""
_rand() = (_GATHER_COUNT[] += 1; random_uniform(Num(_GATHER_COUNT[])))

# ---------------------------------------------------------------------------------------
# Helpers the macro rewrites user syntax into

"""`x[i...]` inside a model: indexing of symbolic quantities, `getindex` otherwise."""
# a Bool quantity (a node of a discrete component) read at a cell stays a Bool (P6.0k)
_index(x::Num, i) = SymbolicUtils.symtype(Symbolics.unwrap(x)) === Bool ? _nonzero(at(x, i)) : at(x, i)
_index(x::QuantityVector, i::Num) = Num[at(c, i) for c in x.components]   # the vector at a cell/site
_index(x::QuantityVector, i::Integer) = x.components[i]
_index(x::Num, i, j) = at2(x, i, j)
_index(x, i...) = getindex(x, i...)

"""
`x′` of a site (or field) variable `x`: its value at the other site `s′` of a contact pair
(`x′ ≡ x[site′]`; a bare `x` in a contact term is `x[site]`, the pair's first site).
"""
function _primed(x::Num)
    role(x) in (:site, :field) || throw(ArgumentError("`$(x)′`: only site and field variables have a value at `s′`"))
    return at(x, B.site′)
end
_primed(x::QuantityVector) = QuantityVector(Symbol(x.name, '′'), Num[at(c, B.site′) for c in x.components])

# `&&`, `||`, `!` in models become the symbolic `&`, `|`, `!` (operands are pure, so
# non-short-circuit evaluation is equivalent).
# `b` and the branches are thunks: short-circuit/lazy on real values, as in plain Julia.
_andq(a::Bool, b) = a && b()
_andq(a, b) = a & b()
_orq(a::Bool, b) = a || b()
_orq(a, b) = a | b()
_notq(a) = !a
_ifelseq(c::Bool, a, b) = c ? a() : b()
_ifelseq(c, a, b) = ifelse(c, a(), b())

"""Neighbours of `anchor` over a relation spec, as the iterator of a gather."""
struct Around{R}
    relation::R
    anchor::Any
end
_around(spec, anchor) = Around(spec, anchor)

"""`fold(body(n) for n in R(s) if cond(n))`: a gather when `R` is a relation, a population
fold for `cells(k)`, else plain Julia."""
function _fold_or_gather(fold, body, R, s, cond)
    R isa Union{CorePotts.RelationSpec, RelationRef} && return _gather(fold, body, Around(R, s), cond)
    R === cells && return _population(fold, body, cells(s), cond)
    return cond === nothing ? fold(body(n) for n in R(s)) : fold(body(n) for n in R(s) if cond(n))
end

"""`fold(body(n) for n in itr if cond(n))`: a population fold over `cells(…)`/`sites`, else plain Julia."""
function _fold_iter(fold, body, itr, cond)
    itr === cells && (itr = CellDomain(Int[]))
    itr isa Union{CellDomain, SiteDomain} && return _population(fold, body, itr, cond)
    return cond === nothing ? fold(body(n) for n in itr) : fold(body(n) for n in itr if cond(n))
end

const _POPULATION_FOLDS = (:sum, :mean, :minimum, :maximum, :count, :any, :all)

function _population(fold, body, d, cond)
    op = nameof(fold)
    op in _POPULATION_FOLDS || throw(ArgumentError("`$op` over a population is not supported; use one of $_POPULATION_FOLDS"))
    _GATHER_COUNT[] += 1
    role = d isa CellDomain ? :bound_cell : :bound_site
    kinds = d isa CellDomain ? d.kinds : Int[]
    n = _tag(_sym(Symbol(role === :bound_cell ? :c_ : :s_, _GATHER_COUNT[])), Info(role, :n, nothing, (; op, kinds)))
    return population(n, body(n), cond === nothing ? true : cond(n))
end

const FOLDS = (:sum, :prod, :mean, :geomean, :log1p_geomean, :minimum, :maximum, :count,
    :any, :all)

"""`log1p_geomean(itr)`: `exp(mean(log1p.(max.(itr, 0)))) − 1`."""
log1p_geomean(itr) = expm1(sum(v -> log1p(max(zero(v), v)), itr) / length(itr))
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
"""Compartment clusters (D-036) whose root cell is of `kinds`: `clusters(k) => E(cluster_volume, …)`."""
struct ClusterDomain
    kinds::Vector{Int}
end

cells(kinds::Integer...) = CellDomain(collect(Int, kinds))
clusters(kinds::Integer...) = ClusterDomain(collect(Int, kinds))
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
"""A hard constraint: `expr` (proposal scope) must hold, or a connectivity rule `expr` that
must hold when the losing cell is of `kinds`."""
struct Constraint
    kind::Symbol                   # :expr, :connectivity, :no_extinction
    kinds::Vector{Int}
    expr::Any
end
const _CONNECTIVITY_RULES = (:local, :arc_or_pair)
"""
    connectivity(kinds...; rule = :local)

Forbid copies that locally disconnect a cell of `kinds` (every kind if empty). Shorthand for
a constraint over the proposal-scope connectivity values, applied when the losing cell is of
`kinds`:

- `rule = :local`: `local_components <= 1`, the losing cell's sites around the target stay
  one piece (CompuCell3D `Connectivity`, Morpheus);
- `rule = :arc_or_pair`: `ring_arcs <= 1 || ring_cells == 2`, one arc of the neighbour
  ring, or else exactly two cells on it (a looser 2D ring rule).

Other rules are expressions: a soft penalty is `@drive copy => λ * (local_components > 1)`.
"""
function connectivity(kinds::Integer...; rule::Symbol = :local)
    rule in _CONNECTIVITY_RULES ||
        throw(ArgumentError("connectivity: unknown rule `:$rule` (one of $(join(repr.(_CONNECTIVITY_RULES), ", ")))"))
    test = rule === :local ? (B.local_components <= 1) : ((B.ring_arcs <= 1) | (B.ring_cells == 2))
    return Constraint(:connectivity, collect(Int, kinds), test)
end
"""`no_extinction`: forbid copies that remove a cell's last site."""
const no_extinction = Constraint(:no_extinction, Int[], nothing)

energy(p::Pair) = EnergyTerm(_domain(p.first), p.second)
# bare `cells`/`clusters` mean every kind
_domain(::typeof(cells)) = CellDomain(Int[])
_domain(::typeof(clusters)) = ClusterDomain(Int[])
_domain(d) = d

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
function link_rule(action::Symbol, r::RelationshipRef, args...; when, every = nothing)
    n, rest = _rule_cadence("@$action", args, every)
    isempty(rest) || throw(ArgumentError("@$action: `$(first(rest))` is not a cadence `Every(n)`"))
    return LinkRule(r.name, action, when, n)
end

"""
Bind each unscoped edge variable `x(edge)` of one model body to that body's only
relationship, when the body is built (before `@extend` merges it with others, so a base's
`rest(edge)` stays its own relationship's). A body declaring several relationships leaves
them unscoped; `mtkcompile` reports them as ambiguous.
"""
function _bind_edge_scope(vars, rels)
    length(rels) == 1 || return vars
    r = only(rels).name
    return map(vars) do x
        i = info(x)
        (i.role === :edge && !haskey(i.options, :relationship)) || return x
        return _tag(x, Info(:edge, i.name, i.default, (; i.options..., relationship = r)))
    end
end
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
"""`Every(n)`: the cadence of an update or rule (`@divide`, `@link`): it runs at MCS where `mcs % n == 0`."""
struct Every
    n::Int
    Every(n::Integer) = n >= 1 ? new(Int(n)) : throw(ArgumentError("Every(n) needs n ≥ 1; got $n"))
end
update(phase::Symbol, eq::Equation) = Update(phase, eq, 1)
update(phase::Symbol, e::Every, eq::Equation) = Update(phase, eq, e.n)
update(phase::Symbol, eqs::AbstractVector{<:Equation}) = [update(phase, eq) for eq in eqs]
update(phase::Symbol, e::Every, eqs::AbstractVector{<:Equation}) = [update(phase, e, eq) for eq in eqs]

"""
    @divide cells(kinds) [Every(n)] when = cond, along = normal, x => rule, …
    @divide clusters(kinds) [Every(n)] when = cond, along = normal, x => rule, …

A division rule: `when` (cell scope, may use `mcs`), `along` (`principal_axis()`,
`major_axis()`, `RandomPlane()`, or a vector expression), daughter state rules
`x => value` (applied to both parent and daughter) or `x => Split()`. With `clusters`,
a compartment cluster whose root is of `kinds` divides as a unit when `when` holds at the
root (`cluster_volume` is the cluster's); every member splits along one plane through the
cluster centroid and the state rules apply to every member.

`Every(n)` (or `every = n`) checks the rule only at MCS where `mcs % n == 0` (MCS are
numbered from 0, as for updates); the default is `Every(1)`, every MCS. Each rule of a model
has its own cadence.
"""
struct DivideRule
    domain::Union{CellDomain, ClusterDomain}
    when::Any
    along::Any
    rules::Vector{Pair{Any, Any}}
    every::Int
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

divide(d::Union{typeof(cells), typeof(clusters)}, args...; kw...) = divide(_domain(d), args...; kw...)
"""
The cadence of a rule (P6.0f) from its positional `Every(n)` or its `every = n` keyword (at
most one of them; default 1), and the other positional arguments. Every rule that takes a
cadence (`@divide`, `@link`/`@unlink`, and future lifecycle rules) parses it here.
"""
function _rule_cadence(what, args, every)
    cadences = Every[a for a in args if a isa Every]
    every === nothing || push!(cadences, every isa Every ? every : every isa Integer ? Every(every) :
                                         throw(ArgumentError("$what: `every = n` takes an integer n ≥ 1 or `Every(n)`; got $(repr(every))")))
    length(cadences) <= 1 || throw(ArgumentError("$what: a rule has one cadence; got " *
                                                 join(("Every($(e.n))" for e in cadences), " and ")))
    return (isempty(cadences) ? 1 : only(cadences).n), Any[a for a in args if !(a isa Every)]
end

function divide(d::Union{CellDomain, ClusterDomain}, args...; when, along = AlongMinor(), every = nothing)
    n, rest = _rule_cadence("@divide", args, every)
    rules = Pair{Any, Any}[]
    for a in rest
        a isa Pair || throw(ArgumentError("@divide: `$a` is neither a cadence `Every(n)` nor a state rule `x => rule`"))
        x, r = a       # vector quantities: component-wise (a scalar or `Split()` applies to all)
        x isa AbstractVector ? append!(rules, [c => (r isa AbstractVector ? r[i] : r) for (i, c) in enumerate(x)]) :
        push!(rules, x => r)
    end
    return DivideRule(d, when, along, rules, n)
end

# ---------------------------------------------------------------------------------------
# Lattice and sweep specifications

"""The lattice of a model: dims, boundaries, spacing, the contact neighborhood and an
optional irregular domain (a Bool mask, evaluated once from a predicate `x -> …`)."""
struct LatticeSpec{N, B, S, R, D, G}
    dims::NTuple{N, Int}
    boundary::B
    spacing::S
    neighborhood::R
    domain::D
    geometry::G                   # `Square()` or `Hexagonal()` (CorePotts)
end
function lattice_spec(dims; boundary = Periodic(), neighborhood = Moore(1), spacing = nothing, domain = nothing,
        geometry = CorePotts.Square())
    d = Tuple(Int.(dims))
    geometry isa CorePotts.Hexagonal && spacing !== nothing && length(unique(spacing)) > 1 &&
        throw(ArgumentError("a hexagonal lattice has one spacing"))
    return LatticeSpec(d, boundary, spacing, neighborhood, Lattice(d; boundary, domain, geometry).mask, geometry)
end
core_lattice(l::LatticeSpec) = Lattice(l.dims; boundary = l.boundary, domain = l.domain, geometry = l.geometry)
# by content (the domain is an array)
Base.:(==)(a::LatticeSpec, b::LatticeSpec) = a.dims == b.dims && a.boundary == b.boundary &&
    a.spacing == b.spacing && a.neighborhood == b.neighborhood && a.domain == b.domain && a.geometry == b.geometry
Base.hash(l::LatticeSpec, h::UInt) = hash((l.dims, l.boundary, l.spacing, l.neighborhood, l.domain, l.geometry), h)

"""Field solver of `@sweep`: explicit Euler with `substeps` (auto if `nothing`) and an
optional lower clip (legacy Potts clips concentrations at 0)."""
Base.@kwdef struct ExplicitEuler
    substeps::Union{Nothing, Int} = nothing
    lower::Union{Nothing, Float64} = nothing
end

"""
    Adaptive(alg; kwargs...)

Cell and model ODEs integrated on the host by any SciML ODE algorithm (`Tsit5()`,
`Rodas5P()`, … from OrdinaryDiffEq, loaded by the user), with `kwargs` (`reltol`, `abstol`,
…) passed to `init`. One integrator is created on first use and re-initialized per cell
and per MCS over `[mcs, mcs + 1) × mcs_duration`: adaptive and stiff solvers for
intracellular or systemic models, at host speed (a device state is copied once per MCS).
"""
struct Adaptive{A, K}
    alg::A
    kwargs::K
end
Adaptive(alg; kwargs...) = Adaptive(alg, NamedTuple(kwargs))

"""Classic fourth-order Runge–Kutta for cell ODEs, `substeps` steps per MCS."""
Base.@kwdef struct RK4
    substeps::Int = 1
end

"""The sweep protocol: acceptance law, temperature expression, MCS duration, field and
cell-ODE solvers."""
struct SweepSpec
    law::Symbol
    temperature::Any          # copy scope, or cell scope (`T[kind]`, a cell variable)
    combine::Any              # combines the source and target cells' temperatures
    offset::Float64
    mcs_duration::Float64
    field_solver::ExplicitEuler
    ode_solver::Union{ExplicitEuler, RK4, Adaptive}   # cell and model ODEs (`D(x) ~ …`, components)
end
sweep_spec(law::Symbol; temperature, combine = min, offset = 0.0, mcs_duration = 1.0,
    field_solver = ExplicitEuler(), ode_solver = ExplicitEuler()) = SweepSpec(law, temperature, combine, Float64(offset),
    Float64(mcs_duration), field_solver, ode_solver)

# ---------------------------------------------------------------------------------------
# Library one-liners (AUTHORING §4): functions returning the same `domain => expr` pairs

"""`Volume(kinds...; target, strength)` ≡ `cells(kinds...) => strength * (volume - target)^2`."""
Volume(kinds::Integer...; target, strength = 1) = cells(kinds...) => strength * (B.volume - target)^2
"""`Surface(kinds...; target, strength)` ≡ `cells(kinds...) => strength * (surface - target)^2`."""
Surface(kinds::Integer...; target, strength = 1) = cells(kinds...) => strength * (B.surface - target)^2
"""`Adhesion(J)` ≡ `contacts => J[kind, kind′]` for a kind table `J`."""
Adhesion(J) = contacts => _index(J, B.kind, B.kind′)
"""
    Chemotaxis(c; strength, response = identity, kinds = (), when = true)

`copy => -strength * (r(c[target]) - r(c[source]))` with a response `r` applied to each
concentration (`identity`, `saturating(s)` = `c/(s + c)`, `saturating_linear(s)` =
`c/(s c + 1)`, or any function). It acts when the gaining cell (`new`) is of `kinds` (any
cell if empty) and the copy condition `when` holds, e.g. `old == 0` for extensions into the
medium only, or `(kind[new] == a) | (kind[old] == a)` for copies involving kind `a`.
"""
function Chemotaxis(c; strength, response::F = identity, kinds = (), when = true) where {F}
    gain = isempty(kinds) ? (B.new != 0) : foldl(|, [_index(B.kind, B.new) == k for k in kinds])
    gate = when === true ? gain : gain & when
    return COPY => ifelse(gate, -strength * (response(_index(c, B.target)) - response(_index(c, B.source))), 0.0)
end

# ---------------------------------------------------------------------------------------
# Observed quantities

"""`@observed name ~ expr`: a derived quantity, evaluated on saved states (`sol[name]`)."""
observed_var(name::Symbol) = _tag(_sym(name), Info(:observed, name, nothing, (;)))
struct ObservedEq
    var::Any
    expr::Any
end

"""Names bound inside `@potts_model` bodies (the modelling vocabulary, not exported)."""
const DSL = (; cells, clusters, contacts, sites, edges, new_contact, connectivity, no_extinction,
    Volume, Surface, Adhesion, Chemotaxis, saturating, saturating_linear,
    principal_axis = _principal_axis, major_axis = _major_axis, minor_axis = _minor_axis,
    RandomPlane = _random_plane, Split, ExplicitEuler, RK4, Adaptive, Every, rand = _rand,
    centroid = _centroid, displacement = _displacement, integral = _integral,
    dot = _dot, norm = _norm, normalize = _normalize, geomean, log1p_geomean, mean, Δ)

# ---------------------------------------------------------------------------------------
# Parameters object

"""
    PottsParameters

The parameter object of a generated problem (D-012): an isbits wrapper of a `NamedTuple` of
scalars and kind tables in the model's scalar type. `p.λ` reads a parameter (generated code
does this); `remake(prob; p = [λ => 2.0])` changes values without changing the type, so
nothing recompiles.
"""
struct PottsParameters{NT <: NamedTuple}
    values::NT
end
@inline Base.getproperty(p::PottsParameters, s::Symbol) = getfield(getfield(p, :values), s)
Base.propertynames(p::PottsParameters) = propertynames(getfield(p, :values))
Base.getindex(p::PottsParameters, s::Symbol) = getfield(getfield(p, :values), s)
Base.NamedTuple(p::PottsParameters) = getfield(p, :values)
CorePotts.set_parameter(p::PottsParameters, v, i::Symbol) = PottsParameters(CorePotts.set_parameter(NamedTuple(p), v, i))
Base.:(==)(a::PottsParameters, b::PottsParameters) = NamedTuple(a) == NamedTuple(b)
Base.show(io::IO, p::PottsParameters) = print(io, "PottsParameters", NamedTuple(p))
