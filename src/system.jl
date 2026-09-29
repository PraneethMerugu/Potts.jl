# `PottsSystem`: the authored model (symbolic), produced by `@potts_model` or by the plain
# constructor. `mtkcompile` turns it into a `CompiledPottsSystem` (compile.jl).

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
    sweep::SweepSpec
    structural::NamedTuple = (;)
    sources::IdDict{Any, LineNumberNode} = IdDict{Any, LineNumberNode}()   # term → where it was written
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
    for d in sys.divisions
        println(io, "  divide  ", _domain_string(d.domain), " when ", d.when)
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
