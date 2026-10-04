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
equations (MTK syntax), lifecycle rules and the sweep protocol.

`PottsSystem <: ModelingToolkitBase.AbstractSystem` (D-137); `sys.x` is the namespaced
symbolic `sys₊x` (a parameter, variable or `@observed` quantity, or a `@components` system:
`sys.dc.y` is `sys₊dc₊y`), as in MTK. A completed system (`complete(sys)`) or one with
namespacing off (`toggle_namespacing(sys, false)`) returns the declared symbol itself, which
keys the operating point of `PottsProblem`. Any other name is an `ArgumentError`.

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
  MTK's typed metadata. It survives `complete`, `mtkcompile` and `extend`, and never enters
  the generated code or the fingerprint.

`complete`, `extend(::PottsSystem, ::PottsSystem)` and `show` are Potts'. `compose` (Potts
models do not compose, D-039: use `@components` or `extend`), `ODEProblem`/`JumpProblem`
(use `PottsProblem`) and `extend` with a plain MTK `System` are `ArgumentError`s.
`Potts.lattice(sys)` is the model's lattice.

The positional constructor takes every field in order (`fieldnames(PottsSystem)`) and the
keyword `checks = true`; `checks = false` skips the construction checks (reserved and
clashing names). The MTK mirror fields `eqs`, `unknowns`, `ps` and `systems` are derived from
`equations`, `variables`, `parameters` and `components`; values passed for them are ignored.
"""
struct PottsSystem <: ModelingToolkitBase.AbstractSystem
    name::Symbol
    kinds::Vector{Symbol}
    frozen_kinds::Vector{Int}                  # obstacle kinds: their sites never change owner
    kind_classes::Vector{KindClass}            # named sets of kinds (D-135); not hashed: lowered into the statements
    lattice::LatticeSpec
    parameters::Vector{Any}
    variables::Vector{Any}
    relations::Dict{Symbol, Any}
    energies::Vector{EnergyTerm}
    drives::Vector{Drive}
    constraints::Vector{Constraint}
    updates::Vector{Update}
    equations::Vector{Equation}
    divisions::Vector{DivideRule}
    relationships::Vector{RelationshipSpec}
    link_rules::Vector{LinkRule}
    observed::Vector{ObservedEq}               # also MTK's `observed` field (D-137): `observed(sys)` gives `name ~ expr`
    components::Vector{Any}                    # `ComponentSpec`s: MTK systems instantiated per cell
    discrete::Vector{DiscreteBlock}            # bound discrete components (`_bind_components`)
    sweep::SweepSpec
    structural::NamedTuple
    sources::IdDict{Any, LineNumberNode}       # term → where it was written
    # The MTK `System` fields MTK's generic accessors read (D-137). `eqs`, `unknowns` and `ps`
    # are the `equations`, `variables` and `parameters` vectors themselves, `systems` the
    # component systems; none of these, nor the metadata and flags, enter code or fingerprint.
    eqs::Vector{Equation}
    unknowns::Vector{Any}
    ps::Vector{Any}
    systems::Vector{ModelingToolkitBase.AbstractSystem}
    metadata::Base.ImmutableDict{DataType, Any}
    namespacing::Bool
    complete::Bool
    function PottsSystem(name, kinds, frozen_kinds, kind_classes, lattice, parameters, variables, relations, energies,
            drives, constraints, updates, equations, divisions, relationships, link_rules, observed, components,
            discrete, sweep, structural, sources, eqs, unknowns, ps, systems, metadata, namespacing, complete;
            checks::Bool = true)
        # the mirrors share the Potts vectors (converted once, so both fields hold one object)
        equations = convert(Vector{Equation}, equations)
        variables = convert(Vector{Any}, variables)
        parameters = convert(Vector{Any}, parameters)
        components = convert(Vector{Any}, components)
        sys = new(name, kinds, frozen_kinds, kind_classes, lattice, parameters, variables, relations, energies, drives,
            constraints, updates, equations, divisions, relationships, link_rules, observed, components, discrete,
            sweep, structural, sources, equations, variables, parameters, _component_systems(components), metadata,
            namespacing, complete)
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

function PottsSystem(; name::Symbol, kinds, lattice, sweep, frozen_kinds = Int[], kind_classes = KindClass[],
        parameters = Any[], variables = Any[], relations = Dict{Symbol, Any}(), energies = EnergyTerm[], drives = Drive[],
        constraints = Constraint[], updates = Update[], equations = Equation[], divisions = DivideRule[],
        relationships = RelationshipSpec[], link_rules = LinkRule[], observed = ObservedEq[], components = Any[],
        discrete = DiscreteBlock[], structural = (;), sources = IdDict{Any, LineNumberNode}(),
        metadata = _EMPTY_METADATA, namespacing::Bool = true, complete::Bool = false, checks::Bool = true)
    return PottsSystem(name, kinds, frozen_kinds, kind_classes, lattice, parameters, variables, relations, energies,
        drives, constraints, updates, equations, divisions, relationships, link_rules, observed, components, discrete,
        sweep, structural, sources, nothing, nothing, nothing, nothing, metadata, namespacing, complete; checks)
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

Base.nameof(sys::PottsSystem) = getfield(sys, :name)
ModelingToolkitBase.get_name(sys::PottsSystem) = getfield(sys, :name)

"""Parameter symbols of a model (scalars and kind tables)."""
parameters(sys::PottsSystem) = getfield(sys, :parameters)
"""Scoped state variables of a model."""
variables(sys::PottsSystem) = getfield(sys, :variables)

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
    print(io, "  sweep: ", getfield(sys, :sweep).law, "(temperature = ", getfield(sys, :sweep).temperature, ")")
end
Base.ndims(sys::PottsSystem) = length(getfield(sys, :lattice).dims)

_domain_string(d::CellDomain) = isempty(d.kinds) ? "cells" : "cells(" * join(d.kinds, ", ") * ")"
_domain_string(d::ClusterDomain) = isempty(d.kinds) ? "clusters" : "clusters(" * join(d.kinds, ", ") * ")"
_domain_string(d::ContactDomain) = d.relation === :contact ? "contacts" : "contacts($(d.relation))"
_domain_string(::SiteDomain) = "sites"
_domain_string(d::EdgeDomain) = "edges($(d.relationship))"
_domain_string(d) = string(d)
