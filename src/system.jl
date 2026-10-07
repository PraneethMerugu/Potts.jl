# `PottsSystem`: the authored model (symbolic), produced by `@potts_model` or by the plain
# constructor. `mtkcompile` turns it into a `CompiledPottsSystem` (compile.jl).

"""
    DiscreteBlock

A discrete-time (clocked, `Shift`) MTK component lowered into Potts terms:
one tick replaces every slot (`slots[j]`, a cell or model variable holding the node's latest
value) by `next[j]`, an expression of the pre-tick state (Jacobi reads: every `next` sees the
values before the tick). A tick follows MCS `m` when `(m + 1 - offset) % every == 0` (MTK
clock time `t = offset + k·every` MCS; `t = 0` is the initial state). `scope` is `:cell`
(for the live cells of `kinds`; empty: every kind) or `:model`.
"""
struct DiscreteBlock
    name::Symbol
    scope::Symbol
    kinds::Vector{Int}
    slots::Vector{Any}
    next::Vector{Any}
    every::Int
    offset::Int
end

"""
    PottsSystem(; name, kinds, lattice, parameters, variables, relations, energies, drives,
                constraints, updates, equations, divisions, sweep, structural, …)

A cellular Potts model: kinds (the first is the medium), a lattice, parameters, scoped
variables, Hamiltonian terms, drives, constraints, synchronous/on-copy updates, field
equations (MTK syntax), lifecycle rules and the sweep protocol. `boundaries` holds the
`@boundary` entries of the fields (`Potts.boundary_face`, `Potts.boundary_mask`) and
`schedule` the `@schedule` phases as listed (empty: the default MCS order).

`PottsSystem <: ModelingToolkitBase.AbstractSystem` (D-137); `sys.x` is the namespaced
symbolic `sys₊x` (a parameter, variable or `@observed` quantity, or a `@components` system:
`sys.dc.y` is `sys₊dc₊y`), as in MTK. A completed system (`complete(sys)`) or one with
namespacing off (`toggle_namespacing(sys, false)`) returns the declared symbol itself. Either
works as a key wherever a model quantity is named (operating point, `remake`, `getu`/`setu`/
`getp`, `observe`, `prob[…]`/`sol[…]`, `solvers`): a key namespaced by the model's own name
(`sys₊x`) means the declared `x`; one namespaced by another name is an `ArgumentError`. A
name that is not a parameter, variable, observed quantity or component (a kind, a vector
quantity, a relation, a field) is an `ArgumentError` naming what it is.

MTK's accessors:
- `equations(sys)`: the `@equations` as written, plus each component's equations namespaced
  (`dc₊y`). Hamiltonian terms, drives, updates, lifecycle rules and `@observed` are not
  equations.
- `unknowns(sys)`: the declared variables of every scope (cell, model, site, field, edge),
  plus each component's unknowns namespaced; never the lattice ownership, kinds or built-in
  cell properties.
- `parameters(sys)`: the declared parameters (scalars and kind tables), plus each component's
  parameters namespaced. (`Potts.parameters(sys)` and `Potts.variables(sys)` are the model's
  own declarations.)
- `observed(sys)`: one `name ~ expr` per `@observed` quantity.
- `nameof(sys)`: the model name.
- `getmetadata(sys, key, default)`, `setmetadata(sys, key, value)`, `hasmetadata(sys, key)`:
  MTK's typed metadata. It survives `complete` and `extend`, and `mtkcompile`: read it from
  the `CompiledPottsSystem` or its `.sys` (a compiled system is read-only, so
  `setmetadata` on it is an `ArgumentError`: set metadata before `mtkcompile`). It never
  enters the generated code or the fingerprint. The key [`Potts.PottsSweepSpec`](@ref) is
  always present and derived from the model on read (the sweep's Hamiltonian, drives,
  constraints, temperature and proposal); setting it is an `ArgumentError`.
- `constraints(sys)`: the `@constraint` entries (the entry type is not public).

[`Potts.hamiltonian(sys)`](@ref Potts.hamiltonian) gives the `@energy` terms as
`domain => expr` pairs and [`Potts.drives(sys)`](@ref Potts.drives) the `@drive`
expressions.

`complete` (exported, MTK's function), `extend(::PottsSystem, ::PottsSystem)` and `show` are
Potts'; `independent_variables(sys)` is `[t]`. `compose` (Potts
models do not compose, D-039: use `@components` or `extend`), `ODEProblem`/`JumpProblem`
(use `PottsProblem`) and `extend` with a plain MTK `System` are `ArgumentError`s.
`Potts.lattice(sys)` is the model's lattice.

The positional constructor takes every field in order (`fieldnames(PottsSystem)`) and the
keyword `checks = true`; `checks = false` skips the construction checks (reserved and
clashing names). The MTK mirror fields `eqs`, `unknowns`, `ps` and `systems` are derived from
`equations`, `variables`, `parameters` and `components`; values passed for them to a
constructor are ignored. `@set sys.eqs = …` (Setfield) sets `equations` (likewise `unknowns`
→ `variables`, `ps` → `parameters`); setting `systems`, or `observed` to MTK equations, is an
`ArgumentError`.
"""
Base.@kwdef struct PottsSystem <: ModelingToolkitBase.AbstractSystem
    name::Symbol
    kinds::Vector{Symbol}
    frozen_kinds::Vector{Int} = Int[]          # obstacle kinds: their sites never change owner
    kind_classes::Vector{KindClass} = KindClass[]   # named sets of kinds (D-135); not hashed: lowered into the statements
    lattice::LatticeSpec
    parameters::Vector{Any} = Any[]
    variables::Vector{Any} = Any[]
    relations::Dict{Symbol, Any} = Dict{Symbol, Any}()
    energies::Vector{EnergyTerm} = EnergyTerm[]
    drives::Vector{Drive} = Drive[]
    constraints::Vector{Constraint} = Constraint[]
    updates::Vector{Update} = Update[]
    equations::Vector{Equation} = Equation[]
    divisions::Vector{DivideRule} = DivideRule[]
    relationships::Vector{RelationshipSpec} = RelationshipSpec[]
    link_rules::Vector{LinkRule} = LinkRule[]
    observed::Vector{ObservedEq} = ObservedEq[]   # also MTK's `observed` field (D-137): `observed(sys)` gives `name ~ expr`
    components::Vector{Any} = Any[]            # `ComponentSpec`s: MTK systems instantiated per cell
    discrete::Vector{DiscreteBlock} = DiscreteBlock[]   # bound discrete components (`_bind_components`)
    sweep::SweepSpec
    boundaries::Vector{BoundaryEntry} = BoundaryEntry[]   # `@boundary` faces and site masks (D-145)
    schedule::Vector{Symbol} = Symbol[]        # `@schedule` as listed; empty: the default phase order
    structural::NamedTuple = (;)
    sources::IdDict{Any, LineNumberNode} = IdDict{Any, LineNumberNode}()   # term → where it was written
    # The MTK `System` fields MTK's generic accessors read (D-137); they stay the last seven
    # (the constructor copies the fields before them). `eqs`, `unknowns` and `ps`
    # are the `equations`, `variables` and `parameters` vectors themselves, `systems` the
    # component systems (the constructor derives all four; values given for them are
    # ignored); none of these, nor the metadata and flags, enter code or fingerprint.
    eqs::Vector{Equation} = Equation[]
    unknowns::Vector{Any} = Any[]
    ps::Vector{Any} = Any[]
    systems::Vector{ModelingToolkitBase.AbstractSystem} = ModelingToolkitBase.AbstractSystem[]
    metadata::Base.ImmutableDict{DataType, Any} = Base.ImmutableDict{DataType, Any}()
    namespacing::Bool = true
    complete::Bool = false
    function PottsSystem(args...; checks::Bool = true)
        s = new(args...)
        # the mirrors share the Potts vectors (and the component systems), whatever was given
        sys = new(ntuple(i -> getfield(s, i), Val(fieldcount(PottsSystem) - 7))..., getfield(s, :equations), getfield(s, :variables),
            getfield(s, :parameters), _component_systems(getfield(s, :components)), getfield(s, :metadata),
            getfield(s, :namespacing), getfield(s, :complete))
        checks || return sys
        return _check_primed_names(_check_name_categories(_check_reserved_names(sys)))
    end
end

const _EMPTY_METADATA = Base.ImmutableDict{DataType, Any}()

# The `@components` systems, each under its component name (MTK's `sys.dc` finds it by name).
function _component_systems(components)
    out = ModelingToolkitBase.AbstractSystem[]
    for c in components
        c isa ComponentSpec && c.system isa ModelingToolkitBase.AbstractSystem || continue
        push!(out, nameof(c.system) === c.name ? c.system : Symbolics.rename(c.system, c.name))
    end
    return out
end

# The link endpoints `a`, `b` (bound in edge terms and link rules) are reserved globally
# (D-075 Q8); `@potts_model` rejects them at expansion (`_declare!`), this at construction.
const _ENDPOINT_NAMES = (:a, :b)
_endpoint_message(what, k) = "$what `$k`: `$k` is reserved (`a` and `b` are the link endpoints in edge terms and " *
                             "link rules); choose another name, e.g. `$(k)₀`"

function _check_reserved_names(sys)
    check(what, n) = n in _ENDPOINT_NAMES && throw(ArgumentError(_endpoint_message(what, n)))
    foreach(k -> check("kind", k), getfield(sys, :kinds))
    for (what, xs) in (("parameter", getfield(sys, :parameters)), ("variable", getfield(sys, :variables)))
        for x in xs
            i = info(x)
            i === nothing && continue
            check(what, i.name)
            _check_internal_suffix(what, i.name)
            v = get(i.options, :vector, nothing)
            v === nothing || (check(what, v); _check_internal_suffix(what, v))
        end
    end
    foreach(o -> (i = info(o.var); i === nothing || (check("observed quantity", i.name);
                                                     _check_internal_suffix("observed quantity", i.name))), getfield(sys, :observed))
    foreach(k -> check("relation", k), keys(getfield(sys, :relations)))
    foreach(r -> check("relationship", r.name), getfield(sys, :relationships))
    foreach(c -> check("component", c.name), getfield(sys, :components))
    foreach(k -> check("structural parameter", k), keys(getfield(sys, :structural)))
    _check_kind_classes(sys)
    return sys
end

# A class is a non-empty set of cell kinds of this system (D-135); `@kinds` checks the same
# at expansion, this catches programmatic builds.
function _check_kind_classes(sys)
    ncell = length(getfield(sys, :kinds)) - 1
    for (i, g) in enumerate(getfield(sys, :kind_classes))
        n = g.name
        n in _ENDPOINT_NAMES && throw(ArgumentError(_endpoint_message("kind class", n)))
        n in _reserved_names() && throw(ArgumentError(
            "kind class `$n` has the name of a built-in (`$n` means something else in @potts_model); choose another name"))
        any(h -> h.name === n, view(getfield(sys, :kind_classes), 1:(i - 1))) &&
            throw(ArgumentError("kind class `$n` is declared twice in $(getfield(sys, :name))"))
        isempty(g.kinds) && throw(ArgumentError("kind class `$n` is empty; list at least one kind"))
        allunique(g.kinds) || throw(ArgumentError("kind class `$n` lists a kind twice: $(Tuple(g.kinds))"))
        for k in g.kinds
            1 <= k <= ncell || throw(ArgumentError("kind class `$n` lists kind number $k, which is not a cell kind of " *
                                                   "$(getfield(sys, :name)) (cell kinds are 1:$ncell; 0 is the medium)"))
        end
    end
    return nothing
end

# Suffixes of the state slots Potts adds (ODE and tick scratch, double-buffered fields): a
# declared name ending in one would collide with them. Every declared name is checked
# (D-130): scalar and vector variables and parameters and `@observed` names here, component
# names when components are bound (`_bind_components`, and the rebuilt system's names).
const _INTERNAL_SUFFIXES = ("__ode", "__tick", "__next")
function _check_internal_suffix(what, n::Symbol)
    for suf in _INTERNAL_SUFFIXES
        endswith(String(n), suf) && throw(ArgumentError(
            "$what `$n`: names ending in `$suf` are reserved for Potts' internal state slots; choose another name"))
    end
    return nothing
end

# `nameof` and `get_name` are MTK's (`getfield(sys, :name)`); defining them here only invalidated MTK code

"""Parameter symbols of a model (scalars and kind tables)."""
parameters(sys::PottsSystem) = getfield(sys, :parameters)
"""Scoped state variables of a model."""
variables(sys::PottsSystem) = getfield(sys, :variables)

"""
    Potts.lattice(sys::PottsSystem)

The lattice of a model (its `LatticeSpec`: `dims`, neighbourhood, boundary). `sys.lattice`
is not a field read: `sys.<name>` is a declared symbol (D-137).
"""
lattice(sys::PottsSystem) = getfield(sys, :lattice)

# --- MTK's AbstractSystem interface (D-137). `equations`, `unknowns`, `parameters`, `nameof`,
# the metadata and `toggle_namespacing` are MTK's generic methods on the mirror fields; the
# `observed` field holds Potts' `ObservedEq`s, so `observed`, `getvar` (which `sys.x` calls)
# and `propertynames` read it here.

ModelingToolkitBase.observed(sys::PottsSystem) = Equation[o.var ~ o.expr for o in getfield(sys, :observed)]

# `sys.x`: a component system, a declared variable or parameter, or an observed quantity,
# namespaced as MTK does (`renamespace`) unless `namespace = false` (a completed system)
function ModelingToolkitBase.getvar(sys::PottsSystem, name::Symbol; namespace::Bool = getfield(sys, :namespacing))
    for s in getfield(sys, :systems)
        nameof(s) === name && return namespace ? ModelingToolkitBase.renamespace(sys, s) : s
    end
    for xs in (getfield(sys, :variables), getfield(sys, :parameters)), x in xs
        _declared_name(x) === name && return namespace ? ModelingToolkitBase.renamespace(sys, x) : x
    end
    for o in getfield(sys, :observed)
        _declared_name(o.var) === name && return namespace ? ModelingToolkitBase.renamespace(sys, o.var) : o.var
    end
    throw(ArgumentError("System $(nameof(sys)): " * _property_category(sys, name) * "; `sys.<name>` covers variables, " *
                        "parameters, observed quantities and components (`Potts.lattice(sys)` is the lattice)"))
end
_declared_name(x) = (i = info(x); i === nothing ? nothing : i.name)

# what `name` is in `sys` when it is not a property (D-137 review N1)
function _property_category(sys::PottsSystem, name::Symbol)
    name in getfield(sys, :kinds) && return "`$name` is a kind"
    any(g -> g.name === name, getfield(sys, :kind_classes)) && return "`$name` is a kind class"
    comps = Symbol[]
    for x in Iterators.flatten((getfield(sys, :variables), getfield(sys, :parameters)))
        i = info(x)
        i !== nothing && get(i.options, :vector, nothing) === name && push!(comps, i.name)
    end
    isempty(comps) || return "`$name` is a vector quantity: its components are $(join(("`$n`" for n in comps), ", "))"
    haskey(getfield(sys, :relations), name) && return "`$name` is a relation"
    any(r -> r.name === name, getfield(sys, :relationships)) && return "`$name` is a relationship"
    name in fieldnames(PottsSystem) && return "`$name` is a field, not a property (read it with `getfield`)"
    return "variable $name does not exist"
end

ModelingToolkitBase.independent_variables(::PottsSystem) = Any[_unwrap(t)]

# `@set sys.eqs = …` (Setfield, `ConstructionBase.setproperties`): the MTK mirror names set
# the Potts fields they mirror, so the derived mirrors follow (D-137 review SF3); `systems`
# is derived from `@components` and `observed` holds Potts' `ObservedEq`s, so neither is
# settable as MTK's.
const _MIRROR_FIELDS = (eqs = :equations, unknowns = :variables, ps = :parameters)
function ConstructionBase.setproperties(sys::PottsSystem, patch::NamedTuple)
    haskey(patch, :systems) && throw(ArgumentError("setting `systems` of a PottsSystem: its subsystems are its " *
                                                   "`@components`; build the model with them instead"))
    if haskey(patch, :observed) && !(patch.observed isa AbstractVector{ObservedEq})
        throw(ArgumentError("setting `observed` of a PottsSystem: it holds the model's `@observed` quantities " *
                            "(`ObservedEq`s), not MTK observed equations"))
    end
    pairs_ = Pair{Symbol, Any}[]
    for (k, v) in pairs(patch)
        f = get(_MIRROR_FIELDS, k, k)
        f !== k && haskey(patch, f) && throw(ArgumentError("setting both `$k` and `$f` of a PottsSystem: `$k` is `$f`"))
        push!(pairs_, f => v)
    end
    return invoke(ConstructionBase.setproperties, Tuple{ModelingToolkitBase.AbstractSystem, NamedTuple}, sys,
        NamedTuple(pairs_))
end

# --- Keys namespaced by the model itself (D-137 review SF1). `sys.x` of an uncompleted `sys`
# is `pr₊x`; wherever a key names a model quantity (operating point, `remake`, `getu`/`setu`/
# `getp`, `observe`, `prob[…]`/`sol[…]`, `solvers`) it means the declared `x`. A key
# namespaced by another name names nothing here: with `strict`, an `ArgumentError`.

# the name of a symbolic key (`x` of `x` or `x(t)`), or `nothing` for other expressions
function _key_name(u)
    u isa SymbolicUtils.BasicSymbolic || return nothing
    (issym(u) || (iscall(u) && issym(operation(u)))) || return nothing
    return SymbolicIndexingInterface.getname(u)
end
_namespaced(n::Symbol) = occursin('₊', String(n))
_declared_quantities(sys::PottsSystem) = Dict{Symbol, Any}(i.name => _unwrap(x) for x in Iterators.flatten((
    getfield(sys, :parameters), getfield(sys, :variables), (o.var for o in getfield(sys, :observed))))
                                                           for i in (info(x),) if i !== nothing)
# `pr₊x` → `:x` when `x` is declared and `pr₊x` is not; otherwise `nothing`
function _own_name(sys::PottsSystem, n::Symbol, declared)
    haskey(declared, n) && return nothing
    pre = string(nameof(sys), '₊')
    s = String(n)
    startswith(s, pre) || return nothing
    m = Symbol(SubString(s, ncodeunits(pre) + 1))
    return haskey(declared, m) ? m : nothing
end
function _foreign_key(sys::PottsSystem, n::Symbol, declared)
    haskey(declared, n) && return nothing
    throw(ArgumentError("`$n` is namespaced by another system: model `$(nameof(sys))` declares no such quantity; " *
                        "key by this model's own symbols, `complete(sys).x` (or `sys.x`, `$(nameof(sys))₊x`)"))
end

# `k` (after `_localize`) is a single symbol namespaced by another system: its name has a
# `₊` and names no declared quantity
function _foreign(sys::PottsSystem, k)
    n = k isa Symbol ? k : _key_name(_unwrap(k))
    n isa Symbol && _namespaced(n) || return false
    return !haskey(_declared_quantities(sys), n)
end

"""The key `k` with this model's namespace (`pr₊x`) removed: the declared quantity (or its
name, for a `Symbol` key); in an expression, every such symbol. Other keys are returned as
they are, or with `strict` a key namespaced by another name is an `ArgumentError`."""
function _localize(sys::PottsSystem, k; strict::Bool = false)
    if k isa Symbol
        _namespaced(k) || return k
        declared = _declared_quantities(sys)
        m = _own_name(sys, k, declared)
        m === nothing || return m
        strict && _foreign_key(sys, k, declared)
        return k
    end
    u = _unwrap(k)
    u isa SymbolicUtils.BasicSymbolic || return k
    n = _key_name(u)
    if n !== nothing
        n isa Symbol && _namespaced(n) || return k
        declared = _declared_quantities(sys)
        m = _own_name(sys, n, declared)
        m === nothing || return declared[m]
        strict && _foreign_key(sys, n, declared)
        return k
    end
    iscall(u) || return k
    found = Any[]
    _walk_all(y -> ((ny = _key_name(y)) isa Symbol && _namespaced(ny) && push!(found, y)), u)
    isempty(found) && return k
    declared = _declared_quantities(sys)
    subs = Dict{Any, Any}()
    for y in found
        n = _key_name(y)
        m = _own_name(sys, n, declared)
        if m !== nothing
            subs[y] = declared[m]
        elseif strict
            _foreign_key(sys, n, declared)
        end
    end
    isempty(subs) && return k
    return Symbolics.substitute(u, subs; fold = Val(false))
end

function Base.propertynames(sys::PottsSystem; private::Bool = false)
    private && return fieldnames(PottsSystem)
    names = Symbol[nameof(s) for s in getfield(sys, :systems)]
    for x in Iterators.flatten((getfield(sys, :variables), getfield(sys, :parameters), (o.var for o in getfield(sys, :observed))))
        n = _declared_name(x)
        n === nothing || push!(names, n)
    end
    return names
end

"""
    complete(sys::PottsSystem)

`sys` marked complete (MTK's `complete`): `sys.x` returns the declared symbol, not the
namespaced one. The generated code and the fingerprint are unchanged; MTK's keywords are
accepted and ignored (a Potts model is compiled by `mtkcompile`).
"""
ModelingToolkitBase.complete(sys::PottsSystem; kw...) = _with_flags(sys; complete = true, namespacing = false)

# `sys` with some of its MTK flags (`complete`, `namespacing`) replaced; the checks ran already
function _with_flags(sys::PottsSystem; kw...)
    vals = Any[get(kw, f, getfield(sys, f)) for f in fieldnames(PottsSystem)]
    return PottsSystem(vals...; checks = false)
end

Base.show(io::IO, sys::PottsSystem) = print(io, "PottsSystem ", nameof(sys))

function Base.show(io::IO, ::MIME"text/plain", sys::PottsSystem)
    println(io, "PottsSystem ", getfield(sys, :name), " on ", join(getfield(sys, :lattice).dims, "×"), " (", ndims(sys), "D)")
    println(io, "  kinds: ", join(getfield(sys, :kinds), ", "))
    isempty(getfield(sys, :parameters)) || println(io, "  parameters: ", join(map(p -> info(p).name, getfield(sys, :parameters)), ", "))
    isempty(getfield(sys, :variables)) || println(io, "  variables: ",
        join(map(v -> string(info(v).name, "(", info(v).role, ")"), getfield(sys, :variables)), ", "))
    for e in getfield(sys, :energies)
        println(io, "  energy  ", _domain_string(e.domain), " => ", e.expr)
    end
    for d in getfield(sys, :drives)
        println(io, "  drive   copy => ", d.expr)
    end
    for c in getfield(sys, :constraints)
        println(io, "  constraint ", c.kind === :expr ? c.expr : string(c.kind, c.kinds))
    end
    for u in getfield(sys, :updates)
        println(io, "  @", u.phase, " ", u.eq)
    end
    for e in getfield(sys, :equations)
        println(io, "  equation ", e)
    end
    for b in getfield(sys, :discrete)
        println(io, "  tick    ", b.name, b.scope === :model ? " (model)" : "", b.every == 1 ? "" : " every $(b.every) MCS",
            ": ", join((string(info(x).name, " ← ", y) for (x, y) in zip(b.slots, b.next)), ", "))
    end
    for d in getfield(sys, :divisions)
        println(io, "  divide  ", _domain_string(d.domain), _cadence_string(d.every), " when ", d.when)
    end
    for b in getfield(sys, :boundaries)
        println(io, "  boundary ", info(b.field).name, " ", b.axis == 0 ? "sites($(b.mask)) => Dirichlet($(b.value))" :
                                                          "$(_AXIS_NAMES[b.axis]) => ($(_side_string(b.sides[1])), $(_side_string(b.sides[2])))")
    end
    isempty(getfield(sys, :schedule)) || println(io, "  schedule ", join(getfield(sys, :schedule), ", "))
    print(io, "  sweep: ", getfield(sys, :sweep).law, "(temperature = ", getfield(sys, :sweep).temperature, ")")
end
Base.ndims(sys::PottsSystem) = length(getfield(sys, :lattice).dims)

_side_string(s::Dirichlet) = "Dirichlet($(s.value))"
_side_string(::NoFlux) = "NoFlux()"

_domain_string(d::CellDomain) = isempty(d.kinds) ? "cells" : "cells(" * join(d.kinds, ", ") * ")"
_domain_string(d::ClusterDomain) = isempty(d.kinds) ? "clusters" : "clusters(" * join(d.kinds, ", ") * ")"
_domain_string(d::ContactDomain) = d.relation === :contact ? "contacts" : "contacts($(d.relation))"
_domain_string(::SiteDomain) = "sites"
_domain_string(d::EdgeDomain) = "edges($(d.relationship))"
_domain_string(d) = string(d)
