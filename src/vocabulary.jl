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
    :ring_cells, :ring_medium)

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

"""
State of one model build: the bound-variable and draw counter, the spatial dimension of
the lattice being declared (for `centroid()`, `displacement(c)`) and a one-shot flag set
just before an `@extend` base's constructor runs. Every constructor call gets its own state
(`_in_build`) except that base, so builds on other threads or tasks, or other models built
inside a model's body, never share or reset it.
"""
mutable struct _Build
    count::Int
    dim::Int
    enter::Bool
end
const _BUILD = Base.ScopedValues.ScopedValue{Union{Nothing, _Build}}(nothing)
"""The current build's state (task-local outside a constructor, e.g. at the REPL)."""
function _build()
    b = _BUILD[]
    b === nothing || return b
    return get!(() -> _Build(0, 0, false), task_local_storage(), :potts_build)::_Build
end
"""Run a model constructor body: a fresh build state unless it is an `@extend` base, which
continues the outer model's numbering."""
function _in_build(f)
    b = _BUILD[]
    b !== nothing && b.enter && (b.enter = false; return f())
    return Base.ScopedValues.with(f, _BUILD => _Build(0, 0, false))
end
"""`f(args...; kws...)` as an `@extend` base: numbering continues, and the outer model's
lattice dimension is kept. Only `f`'s own build continues the outer state; any other model
built meanwhile (in `f`'s body) gets its own."""
function _nested(f, args...; kws...)
    b = _build()
    dim = b.dim
    b.enter = true
    try
        return f(args...; kws...)
    finally
        b.enter = false
        b.dim = dim
    end
end
_set_dim!(d) = (_build().dim = d)
_next_number!() = (_build().count += 1)
_lattice_dim() = (d = _build().dim) > 0 ? d :
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
by `volume` for the mean). Read in an update block it is fresh: it reflects the
state after the copy sweep, and the new value of every variable of `x` written bare in the
same block (the reading update runs after the writer, and the integral is recomputed in
between). Recomputed at the start of the after-MCS phases, after each update that writes
one of its variables when something reads it later, and at the MCS boundary.
`integral(Pre(x))` (update blocks only) folds the values before the block. A fold over
`cells` or `sites` in `x` that does not read the site (e.g. `mean(volume[c] for c in
cells)`) is the same at every site: it is computed once per recomputation, not per site.
Folds that draw `rand()`, and folds nested inside a fold that reads the site, stay per site.
"""
cell_integral(x) = error("`integral` is symbolic-only")
Symbolics.@register_symbolic cell_integral(x)
"""Cell-state name of the tracker for `integral(x)`."""
_integral(x) = cell_integral(x isa Num ? x : Num(x))
# named by content (`_symkey`), not by Symbolics' hash, which differs between builds (D-107),
# of the operand as stored (its site-independent folds read from slots, D-110)
_integral_name(x) = Symbol(:integral_, string(_fnv64(_symkey(_integral_operand(x))); base = 62))

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
_pre(v::AbstractVector) = [_pre(x) for x in v]
_pre(v::AbstractVector, k::Integer) = [_pre(x, k) for x in v]
_pre(x, k::Integer) = (k >= 1 || throw(ArgumentError("Pre(x, k) needs k ≥ 1")); history_lag(x, Num(k)))

"""
`_nonzero(x)`: a Boolean node of a discrete component read from its slot (stored in the
model's scalar type as exact 0/1): `true` unless the stored value is zero. Symbolically it
has symtype `Bool`, so it stands in for the MTK `Bool` variable in the component's rules.
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
_rand() = random_uniform(Num(_next_number!()))

# ---------------------------------------------------------------------------------------
# Helpers the macro rewrites user syntax into

"""`x[i...]` inside a model: indexing of symbolic quantities, `getindex` otherwise."""
# a Bool quantity (a node of a discrete component) read at a cell stays a Bool (P6.0k)
_index(x::Num, i) = (_no_class_index(i); SymbolicUtils.symtype(Symbolics.unwrap(x)) === Bool ? _nonzero(at(x, i)) : at(x, i))
_index(x::QuantityVector, i::Num) = Num[at(c, i) for c in x.components]   # the vector at a cell/site
_index(x::QuantityVector, i::Integer) = x.components[i]
_index(x::Num, i, j) = (_no_class_index(i, j); at2(x, i, j))
_index(x, i...) = (_no_class_index(i...); getindex(x, i...))

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

# `div(a, b)` and `a ÷ b` in models: `div` rounding toward zero, registered (Symbolics has
# no `div` on `Num`). Floats use Base's generic formula, which stays in the operands' type
# (Base's `div` on Float32 goes through Float64, which GPUs reject): equal to Base's where
# the quotient is exact in the type (|a / b| < 2^24 in Float32). Integers keep `div`.
_intdiv(a, b) = div(a, b)
_intdiv(a::Integer, b::Integer) = div(a, b)
_intdiv(a::T, b::T) where {T <: AbstractFloat} = round((a - rem(a, b)) / b)
_intdiv(a::Real, b::Real) = _intdiv(promote(a, b)...)
Symbolics.@register_symbolic _intdiv(a, b)
# piecewise constant: zero derivative (as `floor`)
Symbolics.@register_derivative _intdiv(a, b) I Symbolics.unwrap(Num(0))

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
    k = _next_number!()
    role = d isa CellDomain ? :bound_cell : :bound_site
    kinds = d isa CellDomain ? d.kinds : Int[]
    n = _tag(_sym(Symbol(role === :bound_cell ? :c_ : :s_, k)), Info(role, :n, nothing, (; op, kinds)))
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

"""
    _gather(fold, body, around, cond)

`fold(body(n) for n in around if cond(n))` with a fresh bound site variable `n`.
"""
function _gather(fold, body, a::Around, cond = nothing)
    op = nameof(fold)
    op in FOLDS || throw(ArgumentError("`$op` is not a recognised fold over a relation; use one of $FOLDS"))
    n = _tag(_sym(Symbol(:n_, _next_number!())), Info(:bound, :n, nothing, (; relation = a.relation, op)))
    b = body(n)
    c = cond === nothing ? true : cond(n)
    return gather(n, a.anchor, b, c)
end

# ---------------------------------------------------------------------------------------
# Kind classes (D-135): a named set of cell kinds, declared in `@kinds` as `name = (k, …)`

"""
    KindClass

A named set of cell kinds, declared in `@kinds` as `name = (kind, …)` (members are kinds
or earlier classes, flattened in order). A class is usable wherever a list of kinds is:
`cells(g)`, `clusters(g)`, `connectivity(g)`, `Volume(g; …)`, `Surface(g; …)`,
`Chemotaxis(…; kinds = g)`, mixed with kinds (`cells(g, k)`). On a symbolic kind,
`kind[x] ∈ g` is `(kind[x] == k₁) | … | (kind[x] == kₙ)` in member order and `kind[x] ∉ g`
its negation, so a class costs nothing at run time. `∈ g` is meant for kind-valued
expressions (`kind`, `kind′`, `kind[new]`, `kind[c]`, …): on any other quantity it compares
that value with the kind numbers. `kind == g` is an error (a kind is never equal to a
set of kinds). A class is not an index into a kind table, and operating points and layouts
take kinds, not classes.

`PottsSystem(; kind_classes = [KindClass(:name, [k₁, …])])` declares classes
programmatically (kind numbers: the medium is 0, then the cell kinds in order).
"""
struct KindClass
    name::Symbol
    kinds::Vector{Int}
end
Base.iterate(g::KindClass, i...) = iterate(g.kinds, i...)
Base.length(g::KindClass) = length(g.kinds)
Base.isempty(g::KindClass) = isempty(g.kinds)
Base.eltype(::Type{KindClass}) = Int
Base.:(==)(g::KindClass, h::KindClass) = g.name === h.name && g.kinds == h.kinds
Base.hash(g::KindClass, h::UInt) = hash(g.kinds, hash(g.name, hash(KindClass, h)))
Base.show(io::IO, g::KindClass) = print(io, "kind class `", g.name, "` = ", Tuple(g.kinds))
Base.in(x::Integer, g::KindClass) = x in g.kinds
# `kind == g` would otherwise fall back to `===` and silently become `false` (`!=`: `true`)
_class_compare(g::KindClass) = throw(ArgumentError("`$(g.name)` is a kind class; test membership with `kind ∈ $(g.name)`"))
Base.:(==)(::Num, g::KindClass) = _class_compare(g)
Base.:(==)(g::KindClass, ::Num) = _class_compare(g)
Base.:(!=)(::Num, g::KindClass) = _class_compare(g)
Base.:(!=)(g::KindClass, ::Num) = _class_compare(g)
# on a symbolic kind: an unrolled `|` of equalities with constant kind numbers, folded left
# in member order (the same expression as the explicit `(x == k₁) || (x == k₂) || …`)
function Base.in(x::Num, g::KindClass)
    ks = g.kinds
    isempty(ks) && throw(ArgumentError("kind class `$(g.name)` is empty"))
    r = x == ks[1]
    for i in 2:length(ks)
        r = r | (x == ks[i])
    end
    return r
end

"""Build the class `name` from its members' names and values (kind numbers or classes)."""
function _kind_class(name::Symbol, names::Tuple, members::Tuple)
    isempty(members) && throw(ArgumentError("kind class `$name` is empty; list at least one kind"))
    ks = Int[]
    for (n, m) in zip(names, members)
        if m isa KindClass
            append!(ks, m.kinds)
        elseif m isa Integer && !(m isa Bool)
            m == 0 && throw(ArgumentError("kind class `$name` lists the medium `$n`, which is not a cell kind; " *
                                          "write `kind[x] == $n || kind[x] ∈ $name` instead"))
            push!(ks, m)
        else
            throw(ArgumentError("kind class `$name`: `$n` is not a kind or an earlier kind class"))
        end
    end
    allunique(ks) || throw(ArgumentError("kind class `$name` lists a kind twice (after flattening its classes): $(Tuple(ks))"))
    return KindClass(name, ks)
end
function _no_class_index(is...)
    for i in is
        i isa KindClass && throw(ArgumentError("`$(i.name)` is a kind class and cannot index a kind table; " *
                                               "index by a kind (e.g. `J[kind, kind′]`) and gate with `kind ∈ $(i.name)`"))
    end
    return nothing
end
"""Kind numbers of a list of kinds and classes, classes flattened in place."""
_flat_kinds(ks) = Int[k for x in ks for k in (x isa KindClass ? x.kinds : (x,))]
const _KindArg = Union{Integer, KindClass}

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
"""Compartment clusters whose root cell is of `kinds`: `clusters(k) => E(cluster_volume, …)`."""
struct ClusterDomain
    kinds::Vector{Int}
end

cells(kinds::_KindArg...) = CellDomain(_flat_kinds(kinds))
clusters(kinds::_KindArg...) = ClusterDomain(_flat_kinds(kinds))
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

- `rule = :local`: `local_components == 1`, the losing cell's sites around the target form
  exactly one piece (CompuCell3D `Connectivity`, which rejects `!= 1`). Zero pieces
  (the cell's last site, an isolated fragment) is rejected, so a cell under this rule
  cannot die by copies;
- `rule = :arc_or_pair`: `ring_arcs <= 1 || (ring_cells == 2 && ring_medium == 0)`, at
  most one arc of the neighbour ring, or else exactly two cells and no medium on it (TST's
  `ConnectivityPreservedP`, the Merks reference, as a hard veto). Out-of-domain sites
  (a closed face, outside a domain mask) are neither medium nor a cell; TST counts its
  frame as a cell, so at a closed edge the two rules can differ. Zero arcs pass, so the
  last site can be taken.

Both rules read the target's neighbour shell (8 sites on a square lattice, 6 on a hexagonal
one, 26 in 3D; see `CorePotts.ring_arcs`), so they hold on every geometry.

Other rules are expressions: a soft penalty is `@drive copy => λ * (local_components > 1)`.
The soft arc-or-pair rule (TST's `conn_diss`, Merks' E₀ threshold shift under Metropolis)
charges `E₀` to every copy the rule would refuse:

    @drive copy => E₀ * ((kind[old] == A) & !((ring_arcs <= 1) | ((ring_cells == 2) & (ring_medium == 0))))

Connectivity of the whole cell (not only around the target) is `components(x; scope =
Global())`, reserved until P6.9.
"""
function connectivity(kinds::_KindArg...; rule::Symbol = :local)
    rule in _CONNECTIVITY_RULES ||
        throw(ArgumentError("connectivity: unknown rule `:$rule` (one of $(join(repr.(_CONNECTIVITY_RULES), ", ")))"))
    test = rule === :local ? (B.local_components == 1) : ((B.ring_arcs <= 1) | ((B.ring_cells == 2) & (B.ring_medium == 0)))
    return Constraint(:connectivity, _flat_kinds(kinds), test)
end
"""
    Global(; window = nothing)

The global scope of [`components`](@ref): connectivity of the whole cell, not of the
target's neighbour shell. `window` is `nothing` or a positive number of MCS. A reserved
placeholder: using it in a model is an `ArgumentError` until P6.9.
"""
struct Global
    window::Union{Nothing, Int}
    function Global(; window = nothing)
        window === nothing || (window isa Integer && window > 0) ||
            throw(ArgumentError("Global: `window` must be `nothing` or a positive integer, got $(repr(window))"))
        return new(window === nothing ? nothing : Int(window))
    end
end

"""
    components(x; scope = Global())

The number of pieces of cell `x` (e.g. `old`) over `scope`. Only `Global()` is a scope, and
it is not available yet: a model that uses it raises an `ArgumentError` when it is built.
The local count around the target is the proposal value `local_components`.
"""
function components(x; scope = Global())
    scope isa Global || throw(ArgumentError("components: `scope` must be `Global()`, got $(repr(scope))"))
    throw(ArgumentError("global connectivity (`Global()`) is not available yet (P6.9); the local " *
                        "rules (`connectivity`, `local_components`, `ring_arcs`) read the target's neighbour shell"))
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
Bind each unscoped edge variable `x(edge)` of one model body, when the body is built
(before `@extend` merges it with others, so a base's `rest(edge)` stays its own
relationship's). A re-declaration of an edge variable of one of `bases` (the body's
`@extend`s) keeps that variable's relationship, whatever relationships the body declares;
only its default is the body's. A new one binds to the body's only relationship (marked
`implicit_relationship`, so a later functional `extend` over a base declaring it may still
re-bind it); a body declaring several leaves it unscoped, and `mtkcompile` reports it as
ambiguous. Two bases declaring one edge variable on different relationships is an
`ArgumentError`.
"""
function _bind_edge_scope(vars, rels, bases = ())
    # D-127: a payload column belongs to one relationship, so a re-declaration inherits it
    inherited = Dict{Symbol, Symbol}()
    from = Dict{Symbol, Symbol}()                      # edge variable → the base declaring it
    for b in bases, (n, r) in _edge_relationships(getfield(b, :variables))
        old = get!(inherited, n, r)
        old === r || throw(ArgumentError("bases `$(from[n])` and `$(nameof(b))` both declare edge variable " *
            "`$n`, on `$old` and `$r`; rename one (an edge variable belongs to one relationship)"))
        get!(from, n, nameof(b))
    end
    own = length(rels) == 1 ? only(rels).name : nothing
    isempty(inherited) && own === nothing && return vars
    return map(vars) do x
        i = info(x)
        (i !== nothing && i.role === :edge && !haskey(i.options, :relationship)) || return x
        r = get(inherited, i.name, nothing)
        r === nothing || return _tag(x, Info(:edge, i.name, i.default, (; i.options..., relationship = r)))
        own === nothing && return x
        return _tag(x, Info(:edge, i.name, i.default, (; i.options..., relationship = own, implicit_relationship = true)))
    end
end
"""Edge variable name → relationship, for the edge variables among `xs` bound to one."""
function _edge_relationships(xs)
    out = Dict{Symbol, Symbol}()
    for x in xs
        i = info(x)
        i !== nothing && i.role === :edge && haskey(i.options, :relationship) &&
            (out[i.name] = i.options.relationship)
    end
    return out
end
"""`x` with its relationship settled: the `implicit_relationship` mark dropped."""
function _settle_edge_scope(x)
    i = info(x)
    (i !== nothing && i.role === :edge && haskey(i.options, :implicit_relationship)) || return x
    return _tag(x, Info(:edge, i.name, i.default, _without_implicit(i.options)))
end
_without_implicit(o::NamedTuple) = (; (k => v for (k, v) in pairs(o) if k !== :implicit_relationship)...)
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
The cadence of a rule from its positional `Every(n)` or its `every = n` keyword (at
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

"""
    ExplicitEuler(; substeps = nothing, lower = nothing)

Explicit Euler over one MCS in `substeps` steps, clipping the result at `lower` after every
step if given (legacy Potts clips concentrations at 0). As a `field_solver` (a
`PottsProblem` keyword), `substeps = nothing` takes the smallest count `n` with
`mcs_duration / n · (D · Σ_d 4/h_d² + k) ≤ 1.8` (`CorePotts.stable_substeps`), from the
current parameters: `D` is the diffusion coefficient and `k` bounds the reaction's
`|∂f/∂c|` (for a reaction linear in the field, the size of its coefficient, indicators such
as `(kind == medium)` and `rand()` counting as 1 and a kind table `δ[kind]` as its largest
entry; a reaction nonlinear in the field is not counted, with a warning).
An explicit `n` is a minimum. As an `ode_solver` (the default), `nothing` is one step.
"""
Base.@kwdef struct ExplicitEuler
    substeps::Union{Nothing, Int} = nothing
    lower::Union{Nothing, Float64} = nothing
end

"""
    Adaptive(alg; kwargs...)

Cell and model ODEs integrated on the host by any SciML ODE algorithm (`Tsit5()`,
`Rodas5P()`, … from OrdinaryDiffEq, loaded by the user), with `kwargs` (`reltol`, `abstol`,
…) passed to `init`: a `PottsProblem`'s `ode_solver`, or a variable's entry in its
`solvers` map. One integrator is created on first use and re-initialized per cell and per
MCS over `[mcs, mcs + 1) × mcs_duration`: adaptive and stiff solvers for intracellular or
systemic models, at host speed (a device state is copied once per MCS).

Every keyword and algorithm field enters the problem fingerprint, so a checkpoint resumes
only under an equal solver. Values must be at most 8 levels deep and not cyclic (deeper
ones are an `ArgumentError` when the problem is built). An anonymous function or closure
(`isoutofdomain = (u, p, t) -> any(<(0), u)`, `Rodas5P(step_limiter! = …)`) is accepted, but
it has no name that survives the Julia session: its problem's checkpoints load only in the
session that made them. To resume in a new session, pass a named function defined at the
top level or an instance of a callable struct (or a stable wrapper such as `Returns(false)`).
"""
struct Adaptive{A, K}
    alg::A
    kwargs::K
end
Adaptive(alg; kwargs...) = Adaptive(alg, NamedTuple(kwargs))

"""Classic fourth-order Runge–Kutta for cell and model ODEs, `substeps` steps per MCS."""
Base.@kwdef struct RK4
    substeps::Int = 1
end

"""The sweep protocol: acceptance law, temperature expression and MCS duration. The solvers
are `PottsProblem` keywords, not part of the model."""
struct SweepSpec
    law::Symbol
    temperature::Any          # copy scope, or cell scope (`T[kind]`, a cell variable)
    combine::Any              # combines the source and target cells' temperatures
    offset::Float64
    mcs_duration::Float64
    # D-126: the `offset`, `combine` and `mcs_duration` checks live here, in that order, so a
    # hand-built `SweepSpec` passed to `PottsSystem(; sweep)` is checked as `@sweep` checks it
    function SweepSpec(law::Symbol, temperature, combine, offset, mcs_duration)
        o = _sweep_offset(offset)
        _sweep_combine(combine)
        return new(law, temperature, combine, o, _sweep_mcs_duration(mcs_duration))
    end
end
# D-123: a finite real, also after conversion to Float64
function _sweep_offset(offset)
    o = offset isa Real ? (try Float64(offset) catch; NaN end) : NaN
    isfinite(o) || throw(ArgumentError(
        "`@sweep`: `offset` must be a finite real number, got $(repr(offset))::$(typeof(offset)); " *
        "pass a finite number (`offset = 0` disables it)"))
    return o
end
# D-126: a positive, finite real, also after conversion to Float64 (a `BigFloat` can overflow
# to Inf or underflow to 0); a symbolic parameter does not convert and is rejected
function _sweep_mcs_duration(mcs_duration)
    md = mcs_duration isa Real ? (try Float64(mcs_duration) catch; NaN end) : NaN
    (isfinite(md) && md > 0) || throw(ArgumentError(
        "`@sweep`: `mcs_duration` must be a positive, finite real number, got $(repr(mcs_duration))::$(typeof(mcs_duration)); " *
        "it is the time one MCS stands for (default 1.0)"))
    return md
end
# D-123: `combine` is interpolated into the generated temperature code, whose printed form
# the fingerprint hashes, so it must print the same in every session. Test exactly that
# printed form: a compiler-generated name (`var"#…"`: an anonymous function, a closure, a
# local named function, a gensym'd module, or any of these inside a wrapper's type or
# fields) carries a session counter. Module paths such as Pluto's `var"workspace#3"` pass:
# stable within a session, the user's contract across sessions.
_stable_callable(f) = !occursin("var\"#", string(:($f(a, b))))
_sweep_combine(combine) = _stable_callable(combine) || throw(ArgumentError(
    "`@sweep`: `combine` must print without a compiler-generated name, got $combine: an anonymous " *
    "function or closure, or a wrapper holding one, is named differently in every session, so " *
    "checkpoints could not be matched. Use a top-level named function, `f(a, b) = …` and " *
    "`combine = f`, or a callable struct whose fields are values, not anonymous functions"))
"""
    sweep_spec(law; temperature, combine = min, offset = 0.0, mcs_duration = 1.0)

The `SweepSpec` built by `@sweep Metropolis(; …)` (`law = :metropolis`) or
`@sweep Barker(; …)` (`law = :barker`).

- `offset` must be finite; NaN and ±Inf are an `ArgumentError`.
- `mcs_duration`, the time one MCS stands for, must be a positive, finite real number; NaN,
  ±Inf, 0, negative values, a `BigFloat` beyond the `Float64` range, non-numbers and a
  symbolic parameter are an `ArgumentError`, so the system does not build. It is stored as
  `Float64(mcs_duration)`.
- `combine` must be a named function (`min`, `max`, or `amean(a, b) = (a + b) / 2` defined
  at the top level and passed as `combine = amean`), a composition of named functions
  (`min ∘ max`), or an instance of a callable struct whose fields are values. An anonymous
  function, a closure, a function defined inside another function, or a wrapper holding
  one (`Base.Fix2((a, b) -> a, 1)`, a struct with an anonymous-function field) is an
  `ArgumentError`: its compiler-generated name changes between Julia sessions, so a
  checkpoint written in one session would not load in the next. To carry parameters, use
  a callable struct (`struct Mix; w::Float64; end; (m::Mix)(a, b) = m.w * a + (1 - m.w) * b`).

A hand-built `SweepSpec(law, temperature, combine, offset, mcs_duration)` checks `offset`,
`combine` and `mcs_duration` the same way.
"""
function sweep_spec(law::Symbol; temperature, combine = min, offset = 0.0, mcs_duration = 1.0, kwargs...)
    for k in keys(kwargs)
        k in (:field_solver, :ode_solver, :solvers) && throw(ArgumentError(
            "`@sweep` no longer takes `$k`: pass it to the problem, " *
            "`PottsProblem(sys, op, tspan; $k = …)`"))
    end
    isempty(kwargs) || throw(ArgumentError("`@sweep`: unknown keyword(s) $(join(("`$k`" for k in keys(kwargs)), ", ")); " *
                                           "it takes `temperature`, `combine`, `offset` and `mcs_duration`"))
    # `offset`, `combine` and `mcs_duration` are checked by the constructor, in that order
    return SweepSpec(law, temperature, combine, offset, mcs_duration)
end

# ---------------------------------------------------------------------------------------
# Library one-liners (AUTHORING §4): functions returning the same `domain => expr` pairs

"""`Volume(kinds...; target, strength)` ≡ `cells(kinds...) => strength * (volume - target)^2`."""
Volume(kinds::_KindArg...; target, strength = 1) = cells(kinds...) => strength * (B.volume - target)^2
"""`Surface(kinds...; target, strength)` ≡ `cells(kinds...) => strength * (surface - target)^2`."""
Surface(kinds::_KindArg...; target, strength = 1) = cells(kinds...) => strength * (B.surface - target)^2
"""`Adhesion(J)` ≡ `contacts => J[kind, kind′]` for a kind table `J`."""
Adhesion(J) = contacts => _index(J, B.kind, B.kind′)
"""
    Chemotaxis(c; strength, response = identity, kinds = (), when = new != 0)

`copy => -strength * (r(c[target]) - r(c[source]))` with a response `r` applied to each
concentration (`identity`, `saturating(s)` = `c/(s + c)`, `saturating_linear(s)` =
`c/(s c + 1)`, or any function), on the copies where the copy condition `when` holds:
- the default `when = new != 0` acts when the gaining cell is a cell, so a retraction
  (`new == 0`) gets 0;
- `when = true` acts on every copy, retractions included; any other condition selects
  exactly its copies, e.g. `old == 0` for extensions into the medium only, or
  `(kind[new] == A) | (kind[old] == A)` for every copy involving kind `A`;
- `kinds` non-empty additionally requires the gaining cell to be of `kinds`
  (`kind[new] ∈ kinds`), so retractions stay 0 whatever `when` says.
"""
function Chemotaxis(c; strength, response::F = identity, kinds = (), when = (B.new != 0)) where {F}
    ks = _flat_kinds(kinds)          # kinds and kind classes, flattened in order
    gate = isempty(ks) ? when : (foldl(|, [_index(B.kind, B.new) == k for k in ks]) & when)
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

# ---------------------------------------------------------------------------------------
# Field boundaries (`@boundary`, D-145) and the phase order (`@schedule`)

"""
    Dirichlet(v)

A fixed value `v` of a field, in `@boundary`: on a face (`x => (Dirichlet(v), …)`) a ghost
value, the missing neighbour set to `2v − c` so that the face value `v` is reached midway
between the edge site and its ghost; on a site mask (`sites(pred) => Dirichlet(v)`) a node
value, every site where `pred` holds set to `v` after every explicit substep. `v` is a
number, a parameter or a parameter expression (a `remake` of the parameter keeps the code).
"""
struct Dirichlet{V}
    value::V
end

"""
    NoFlux()

A zero-flux face in `@boundary` (`x => (NoFlux(), …)`): the missing neighbour mirrors the
edge site. A closed axis without an entry is zero flux already.
"""
struct NoFlux end

"""
One entry of a `@boundary` block of field `field`: a face pair on axis `axis` (1, 2, 3 for
`x`, `y`, `z`) with `sides = (low, high)`, each `Dirichlet` or `NoFlux`; or, with `axis = 0`,
a site mask `sites(mask) => Dirichlet(value)`.
"""
struct BoundaryEntry
    field::Any                 # the field variable (symbolic)
    axis::Int
    sides::Tuple{Any, Any}
    mask::Any
    value::Any
end

const _AXIS_NAMES = (:x, :y, :z)

function _boundary_field(x)
    i = info(x)
    (i !== nothing && i.role === :field) || throw(ArgumentError(
        "@boundary `$(i === nothing ? x : i.name)`: boundaries are for field variables (`c(field)`), and " *
        "`$(i === nothing ? x : i.name)` is $(i === nothing ? "not a declared variable" : _with_article("$(i.role) variable"))"))
    return x
end
_boundary_side(s::Union{Dirichlet, NoFlux}, field, axis, what) = s isa Dirichlet ? Dirichlet(_boundary_value(s.value, field, "`$axis` $what face")) : s
_boundary_side(s, field, axis, what) = throw(ArgumentError(
    "@boundary $(info(field).name): the $what side of axis `$axis` is `$s`; each side is `Dirichlet(value)` or `NoFlux()`"))
function _boundary_value(v, field, what)
    u = _unwrap(v)
    u isa Real && return Float64(u)                  # a number (`Num` is a `Real` too: unwrapped first)
    u isa SymbolicUtils.BasicSymbolic || throw(ArgumentError(
        "@boundary $(info(field).name): the $what value is `$v`; give a number, a parameter or a parameter expression"))
    for y in _leaves(u)
        j = info(y)
        (j === nothing || j.role === :param) || throw(ArgumentError(
            "@boundary $(info(field).name): the $what value `$v` reads `$(j.name)`; a boundary value is a number, a " *
            "parameter or a parameter expression"))
    end
    return v
end

"""`x => (low, high)` of `@boundary field` (axis named `name`)."""
function boundary_face(field, name::Symbol, sides)
    _boundary_field(field)
    axis = findfirst(==(name), _AXIS_NAMES)
    axis === nothing && throw(ArgumentError("@boundary $(info(field).name): unknown axis `$name`; the axes are x, y, z"))
    (sides isa Tuple && length(sides) == 2) || throw(ArgumentError(
        "@boundary $(info(field).name): `$name => …` takes a pair of sides `(low, high)`, each `Dirichlet(value)` or `NoFlux()`"))
    return BoundaryEntry(field, axis, (_boundary_side(sides[1], field, name, "low"), _boundary_side(sides[2], field, name, "high")),
        nothing, nothing)
end

"""`sites(pred) => Dirichlet(v)` of `@boundary field`."""
function boundary_mask(field, pred, value)
    _boundary_field(field)
    value isa Dirichlet || throw(ArgumentError(
        "@boundary $(info(field).name): `sites(…) => $value`; a site mask takes `Dirichlet(value)`"))
    (pred isa Bool || _unwrap(pred) isa SymbolicUtils.BasicSymbolic) || throw(ArgumentError(
        "@boundary $(info(field).name): `sites($pred)` takes a site condition, e.g. `sites(kind == border)`"))
    return BoundaryEntry(field, 0, (nothing, nothing), pred, _boundary_value(value.value, field, "site-mask"))
end

"""The canonical phases of one MCS, in their default order (`@schedule`, D-145)."""
const SCHEDULE_PHASES = (:before_mcs, :sweep, :after_mcs, :fields, :components, :operators, :lifecycle, :end_mcs)

"""
    _placed_schedule(listed) -> Vector{Symbol}

The full phase order of `@schedule listed…` (D-145): the listed phases in the listed order;
each unlisted phase, in default order, right after the last placed phase that precedes it in
the default order (first if none). Checks the names and the order rules, naming the offender.
"""
function _placed_schedule(listed)
    seen = Symbol[]
    for n in listed
        n isa Symbol || throw(ArgumentError("@schedule lists phase names; got `$n`"))
        n in SCHEDULE_PHASES || throw(ArgumentError(
            "@schedule: unknown phase `$n`; the phases are $(join(SCHEDULE_PHASES, ", "))"))
        n in seen && throw(ArgumentError("@schedule: phase `$n` is listed twice"))
        push!(seen, n)
    end
    :end_mcs in seen && last(seen) !== :end_mcs && throw(ArgumentError(
        "@schedule: `end_mcs` must be last (the MCS boundary: history, callbacks, saving)"))
    seq = copy(seen)
    for (j, ph) in enumerate(SCHEDULE_PHASES)
        ph in seq && continue
        pos = maximum((findfirst(==(q), seq) for q in SCHEDULE_PHASES[1:(j - 1)] if q in seq); init = 0)
        insert!(seq, pos + 1, ph)
    end
    at(n) = findfirst(==(n), seq)
    at(:before_mcs) < at(:sweep) || throw(ArgumentError(
        "@schedule: `before_mcs` must come before `sweep` (the before-MCS updates precede the copy sweep, D-042)"))
    at(:after_mcs) > at(:sweep) || throw(ArgumentError(
        "@schedule: `after_mcs` must come after `sweep` (the after-MCS updates follow the copy sweep, D-042)"))
    return seq
end

"""Names bound inside `@potts_model` bodies (the modelling vocabulary, not exported)."""
const DSL = (; cells, clusters, contacts, sites, edges, new_contact, connectivity, no_extinction, Global, components,
    Volume, Surface, Adhesion, Chemotaxis, saturating, saturating_linear,
    principal_axis = _principal_axis, major_axis = _major_axis, minor_axis = _minor_axis,
    RandomPlane = _random_plane, Split, ExplicitEuler, RK4, Adaptive, Every, rand = _rand,
    centroid = _centroid, displacement = _displacement, integral = _integral,
    dot = _dot, norm = _norm, normalize = _normalize, geomean, log1p_geomean, mean, Δ, Dirichlet, NoFlux)

# ---------------------------------------------------------------------------------------
# Parameters object

"""
    PottsParameters

The parameter object of a generated problem: an isbits wrapper of a `NamedTuple` of
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
