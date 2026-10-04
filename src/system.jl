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
                constraints, updates, equations, divisions, sweep, structural)

A cellular Potts model: kinds (the first is the medium), a lattice, parameters, scoped
variables, Hamiltonian terms, drives, constraints, synchronous/on-copy updates, field
equations (MTK syntax), lifecycle rules and the sweep protocol.
"""
Base.@kwdef struct PottsSystem
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
    observed::Vector{ObservedEq} = ObservedEq[]
    components::Vector{Any} = Any[]            # `ComponentSpec`s: MTK systems instantiated per cell
    discrete::Vector{DiscreteBlock} = DiscreteBlock[]   # bound discrete components (`_bind_components`)
    sweep::SweepSpec
    structural::NamedTuple = (;)
    sources::IdDict{Any, LineNumberNode} = IdDict{Any, LineNumberNode}()   # term → where it was written
    PottsSystem(args...) = _check_primed_names(_check_name_categories(_check_reserved_names(new(args...))))
end

# The link endpoints `a`, `b` (bound in edge terms and link rules) are reserved globally
# (D-075 Q8); `@potts_model` rejects them at expansion (`_declare!`), this at construction.
const _ENDPOINT_NAMES = (:a, :b)
_endpoint_message(what, k) = "$what `$k`: `$k` is reserved (`a` and `b` are the link endpoints in edge terms and " *
                             "link rules); choose another name, e.g. `$(k)₀`"

function _check_reserved_names(sys)
    check(what, n) = n in _ENDPOINT_NAMES && throw(ArgumentError(_endpoint_message(what, n)))
    foreach(k -> check("kind", k), sys.kinds)
    for (what, xs) in (("parameter", sys.parameters), ("variable", sys.variables))
        for x in xs
            i = info(x)
            i === nothing && continue
            check(what, i.name)
            _check_internal_suffix(what, i.name)
            v = get(i.options, :vector, nothing)
            v === nothing || check(what, v)
        end
    end
    foreach(o -> (i = info(o.var); i === nothing || check("observed quantity", i.name)), sys.observed)
    foreach(k -> check("relation", k), keys(sys.relations))
    foreach(r -> check("relationship", r.name), sys.relationships)
    foreach(c -> check("component", c.name), sys.components)
    foreach(k -> check("structural parameter", k), keys(sys.structural))
    _check_kind_classes(sys)
    return sys
end

# A class is a non-empty set of cell kinds of this system (D-135); `@kinds` checks the same
# at expansion, this catches programmatic builds.
function _check_kind_classes(sys)
    ncell = length(sys.kinds) - 1
    for (i, g) in enumerate(sys.kind_classes)
        n = g.name
        n in _ENDPOINT_NAMES && throw(ArgumentError(_endpoint_message("kind class", n)))
        any(h -> h.name === n, view(sys.kind_classes, 1:(i - 1))) &&
            throw(ArgumentError("kind class `$n` is declared twice in $(sys.name)"))
        isempty(g.kinds) && throw(ArgumentError("kind class `$n` is empty; list at least one kind"))
        allunique(g.kinds) || throw(ArgumentError("kind class `$n` lists a kind twice: $(Tuple(g.kinds))"))
        for k in g.kinds
            1 <= k <= ncell || throw(ArgumentError("kind class `$n` lists kind number $k, which is not a cell kind of " *
                                                   "$(sys.name) (cell kinds are 1:$ncell; 0 is the medium)"))
        end
    end
    return nothing
end

# Suffixes of the state slots Potts adds (ODE and tick scratch, double-buffered fields): a
# declared name ending in one would collide with them.
const _INTERNAL_SUFFIXES = ("__ode", "__tick", "__next")
function _check_internal_suffix(what, n::Symbol)
    for suf in _INTERNAL_SUFFIXES
        endswith(String(n), suf) && throw(ArgumentError(
            "$what `$n`: names ending in `$suf` are reserved for Potts' internal state slots; choose another name"))
    end
    return nothing
end

Base.nameof(sys::PottsSystem) = sys.name
ModelingToolkitBase.get_name(sys::PottsSystem) = sys.name

"""Parameter symbols of a model (scalars and kind tables)."""
parameters(sys::PottsSystem) = sys.parameters
"""Scoped state variables of a model."""
variables(sys::PottsSystem) = sys.variables

function Base.show(io::IO, ::MIME"text/plain", sys::PottsSystem)
    println(io, "PottsSystem ", sys.name, " on ", join(sys.lattice.dims, "×"), " (", ndims(sys), "D)")
    println(io, "  kinds: ", join(sys.kinds, ", "))
    isempty(sys.parameters) || println(io, "  parameters: ", join(map(p -> info(p).name, sys.parameters), ", "))
    isempty(sys.variables) || println(io, "  variables: ",
        join(map(v -> string(info(v).name, "(", info(v).role, ")"), sys.variables), ", "))
    for e in sys.energies
        println(io, "  energy  ", _domain_string(e.domain), " => ", e.expr)
    end
    for d in sys.drives
        println(io, "  drive   copy => ", d.expr)
    end
    for c in sys.constraints
        println(io, "  constraint ", c.kind === :expr ? c.expr : string(c.kind, c.kinds))
    end
    for u in sys.updates
        println(io, "  @", u.phase, " ", u.eq)
    end
    for e in sys.equations
        println(io, "  equation ", e)
    end
    for b in sys.discrete
        println(io, "  tick    ", b.name, b.scope === :model ? " (model)" : "", b.every == 1 ? "" : " every $(b.every) MCS",
            ": ", join((string(info(x).name, " ← ", y) for (x, y) in zip(b.slots, b.next)), ", "))
    end
    for d in sys.divisions
        println(io, "  divide  ", _domain_string(d.domain), _cadence_string(d.every), " when ", d.when)
    end
    print(io, "  sweep: ", sys.sweep.law, "(temperature = ", sys.sweep.temperature, ")")
end
Base.ndims(sys::PottsSystem) = length(sys.lattice.dims)

_domain_string(d::CellDomain) = isempty(d.kinds) ? "cells" : "cells(" * join(d.kinds, ", ") * ")"
_domain_string(d::ClusterDomain) = isempty(d.kinds) ? "clusters" : "clusters(" * join(d.kinds, ", ") * ")"
_domain_string(d::ContactDomain) = d.relation === :contact ? "contacts" : "contacts($(d.relation))"
_domain_string(::SiteDomain) = "sites"
_domain_string(d::EdgeDomain) = "edges($(d.relationship))"
_domain_string(d) = string(d)
