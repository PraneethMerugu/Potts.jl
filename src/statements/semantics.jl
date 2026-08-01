abstract type AbstractEffectClass end
struct PureRead <: AbstractEffectClass end
struct SynchronousAssign <: AbstractEffectClass end
struct AcceptedCopyEffect <: AbstractEffectClass end
struct OrderedBatchEffect <: AbstractEffectClass end

struct Proposal <: AbstractPottsPhase end
struct AcceptedCopy <: AbstractPottsPhase end
struct AfterMCS <: AbstractPottsPhase end
struct RelationshipCommit <: AbstractPottsPhase end
struct Lifecycle <: AbstractPottsPhase end
struct EquationStep <: AbstractPottsPhase end
struct Observe <: AbstractPottsPhase end

struct Before{P <: AbstractPottsPhase} <: AbstractPottsPhase
    phase::P
end
struct After{P <: AbstractPottsPhase} <: AbstractPottsPhase
    phase::P
end

abstract type AbstractCadence end
struct EveryMCS <: AbstractCadence end
struct AtMCS <: AbstractCadence
    mcs::Int
    function AtMCS(mcs::Integer)
        mcs >= 0 || throw(ArgumentError("AtMCS must be nonnegative"))
        new(Int(mcs))
    end
end
struct Every{T <: Integer} <: AbstractCadence
    cadence::T
    function Every(cadence::Integer)
        cadence > 0 || throw(ArgumentError("cadence must be positive"))
        new{typeof(cadence)}(cadence)
    end
end

abstract type AbstractIterationDomain end
struct Sites{D} <: AbstractIterationDomain
    domain::D
end
struct Cells{K} <: AbstractIterationDomain
    kind::K
end
struct Contacts{R} <: AbstractIterationDomain
    relation::R
end
struct Edges{R} <: AbstractIterationDomain
    relationship::R
end
struct IncidentEdges{R, C} <: AbstractIterationDomain
    relationship::R
    cell::C
end

sites(domain) = Sites(domain)
cells(kind) = Cells(kind)
contacts(relation) = Contacts(relation)
edges(relationship) = Edges(relationship)
incident_edges(relationship, cell) = IncidentEdges(relationship, cell)

function HamiltonianTerm(
        id::Union{Symbol, StatementID};
        domain::AbstractIterationDomain,
        anchor,
        expression,
        source = UnknownSource(),
        kwargs...,
    )
    return HamiltonianTerm(_statement_core(
        id,
        (; domain, anchor, expression),
        (; kwargs...),
        source,
    ))
end

struct Assign{T, V} <: AbstractPottsEffect
    target::T
    value::V
end

struct Create{R, A, B, P, Q} <: AbstractPottsEffect
    relationship::R
    endpoint_a::A
    endpoint_b::B
    payload::P
    priority::Q
end
Create(relationship, a, b; payload = NamedTuple(), priority = 0) =
    Create(relationship, a, b, payload, priority)

struct Remove{R, E, P} <: AbstractPottsEffect
    relationship::R
    edge::E
    priority::P
end
Remove(relationship, edge; priority = 0) = Remove(relationship, edge, priority)

struct Retune{R, E, P, Q} <: AbstractPottsEffect
    relationship::R
    edge::E
    payload::P
    priority::Q
end
Retune(relationship, edge; payload, priority = 0) =
    Retune(relationship, edge, payload, priority)

struct Transition{C, K} <: AbstractPottsEffect
    cell::C
    kind::K
end
struct Divide{C, P} <: AbstractPottsEffect
    cell::C
    policy::P
end
Divide(cell; policy = nothing) = Divide(cell, policy)
struct Retire{C} <: AbstractPottsEffect
    cell::C
end

abstract type AbstractBoundaryPolicy end
struct Periodic <: AbstractBoundaryPolicy end
struct Closed <: AbstractBoundaryPolicy end
struct FrozenBorder{K} <: AbstractBoundaryPolicy
    kind::K
end

abstract type AbstractNeighborhood end
struct VonNeumann <: AbstractNeighborhood
    radius::Int
end
VonNeumann(radius::Integer = 1) =
    radius > 0 ? VonNeumann(Int(radius)) :
    throw(ArgumentError("neighborhood radius must be positive"))
struct Moore <: AbstractNeighborhood
    radius::Int
end
Moore(radius::Integer = 1) =
    radius > 0 ? Moore(Int(radius)) :
    throw(ArgumentError("neighborhood radius must be positive"))

abstract type AbstractOwnershipChangePolicy end
struct ClearOnOwnershipChange <: AbstractOwnershipChangePolicy end
struct PreserveOnOwnershipChange <: AbstractOwnershipChangePolicy end

abstract type AbstractRelationshipEndpointPolicy end
struct Undirected{A, B} <: AbstractRelationshipEndpointPolicy
    kind_a::A
    kind_b::B
end
struct Directed{A, B} <: AbstractRelationshipEndpointPolicy
    kind_a::A
    kind_b::B
end
struct RemoveWithEndpoint end
struct RejectEndpointRetirement end

abstract type AbstractSolverPolicy end
struct ExplicitDiffusion <: AbstractSolverPolicy end
struct ExplicitEuler <: AbstractSolverPolicy end
struct Heun <: AbstractSolverPolicy end
struct RK4 <: AbstractSolverPolicy end

abstract type AbstractChemotaxisMode end
struct ExtensionsOnly <: AbstractChemotaxisMode end
struct RetractionsOnly <: AbstractChemotaxisMode end
struct ExtensionsAndRetractions <: AbstractChemotaxisMode end

abstract type AbstractInterpolationPolicy end
struct Nearest <: AbstractInterpolationPolicy end
struct Multilinear <: AbstractInterpolationPolicy end
struct CellCentered end

function _symbolic_local_name(value)
    return try
        Symbol(SymbolicIndexingInterface.getname(Symbolics.unwrap(value)))
    catch
        throw(ArgumentError(
            "a state declared from a symbolic value requires an explicit `name`"
        ))
    end
end

for state_type in (
        SiteState, CellState, MediumState, ModelState, FieldState, HistoryState
    )
    @eval function (::Type{$state_type})(
            variable::Union{Symbolics.Num, Symbolics.Arr};
            name::Symbol = _symbolic_local_name(variable),
            initial = nothing,
            source = UnknownSource(),
            kwargs...,
        )
        return $state_type(_statement_core(
            name, (; variable, initial), (; kwargs...), source
        ))
    end
end

struct AttemptsPerSite
    count::Int
    function AttemptsPerSite(count::Integer = 1)
        count > 0 || throw(ArgumentError("attempt count must be positive"))
        new(Int(count))
    end
end

struct SymmetricPair{A, B}
    first::A
    second::B
end
(↔)(a, b) = SymmetricPair(a, b)

function Lattice(shape::Tuple{Vararg{Integer}};
        name::Symbol = :lattice,
        spacing = ntuple(_ -> 1.0, length(shape)),
        boundary::AbstractBoundaryPolicy = Periodic(),
        relations = NamedTuple(),
    )
    all(>(0), shape) || throw(ArgumentError("lattice dimensions must be positive"))
    length(spacing) == length(shape) ||
        throw(ArgumentError("lattice spacing must match lattice dimensions"))
    domain = LatticeDomain(
        name; shape = Tuple(Int.(shape)), spacing = Tuple(spacing), boundary
    )
    relation_statements = AbstractPottsStatement[]
    for (relation_name, neighborhood) in pairs(relations)
        push!(relation_statements, SpatialRelation(
            Symbol(relation_name); domain = name, neighborhood
        ))
    end
    return StatementSet((domain, relation_statements...))
end

function Volume(kind; target, strength,
        name::Symbol = Symbol(:volume_, Symbol(statement_id(kind))))
    cell = CellBinding(:cell)
    expression = strength * (cell_volume(cell) - target)^2
    return HamiltonianTerm(
        name;
        domain = cells(kind),
        anchor = cell,
        expression,
        mechanism = :volume,
        kind,
        target,
        strength,
    )
end

function ContactEnergy(laws;
        relation = :contact,
        name::Symbol = :contact_energy,
    )
    normalized = Tuple(
        law isa Pair && first(law) isa SymmetricPair ? law :
        throw(ArgumentError("contact laws use `(kind_a ↔ kind_b) => energy`"))
        for law in laws
    )
    contact = ContactBinding(:contact, relation)
    expression = 0.0
    for law in reverse(normalized)
        pair = first(law)
        kind_a = _kind_token(pair.first)
        kind_b = _kind_token(pair.second)
        matching_kinds =
            ((contact.kind_a == kind_a) & (contact.kind_b == kind_b)) |
            ((contact.kind_a == kind_b) & (contact.kind_b == kind_a))
        expression = ifelse(
            (contact.owner_a != contact.owner_b) & matching_kinds,
            last(law),
            expression,
        )
    end
    return HamiltonianTerm(
        name;
        domain = contacts(relation),
        anchor = contact,
        expression,
        mechanism = :contact,
        relation,
        laws = normalized,
    )
end

function Elongation(kind; target, strength,
        name::Symbol = Symbol(:elongation_, Symbol(statement_id(kind))))
    cell = CellBinding(:cell)
    return HamiltonianTerm(
        name;
        domain = cells(kind),
        anchor = cell,
        expression = strength * (cell_elongation(cell) - target)^2,
        mechanism = :elongation,
        kind,
        target,
        strength,
    )
end

function Chemotaxis(kind, field; strength,
        mode::AbstractChemotaxisMode = ExtensionsOnly(),
        sample::AbstractInterpolationPolicy = Nearest(),
        name::Symbol = Symbol(:chemotaxis_, Symbol(statement_id(kind))))
    copy = ProposalContext(:copy)
    expression = -strength * (
        field_value(field, copy.target_site) -
        field_value(field, copy.source_site)
    )
    return ProposalDrive(
        name, expression; mechanism = :chemotaxis, kind, field, strength, mode, sample
    )
end

function LocalConnectivity(kind;
        foreground::Symbol = :connectivity,
        background::Symbol = :connectivity_background,
        name::Symbol = Symbol(:connectivity_, Symbol(statement_id(kind))))
    expression = _potts_merks_local_connectivity(
        _kind_token(kind),
        _spatial_relation_token(foreground),
        _spatial_relation_token(background),
    )
    return ProposalConstraint(
        name,
        expression;
        mechanism = :local_connectivity,
        kind,
        foreground,
        background,
        theorem = :merks_2006_local_collision,
    )
end

function ActEnergy(kind, activity; maximum, strength, reduction = Moore(1),
        name::Symbol = Symbol(:activity_, Symbol(statement_id(kind))))
    return ProposalDrive(
        name, 0.0;
        mechanism = :activity,
        kind,
        activity,
        maximum,
        strength,
        reduction,
    )
end

Synchronous(id, effect; phase = AfterMCS(), kwargs...) =
    SynchronousProcess(id; effects = (effect,), phase, kwargs...)
AcceptedCopy(id::Symbol, effect; when = true, phase = AcceptedCopy(), kwargs...) =
    AcceptedCopyProcess(id; expression = when, effects = (effect,), phase, kwargs...)

struct SweepStage{A, O}
    name::Symbol
    attempts::A
    options::O
end
Sweep(name::Symbol = :cpm; attempts = AttemptsPerSite(1), kwargs...) =
    SweepStage(name, attempts, (; kwargs...))

struct ObserveStage{C, O}
    name::Symbol
    cadence::C
    options::O
end
ObserveStage(name::Symbol; every::Integer = 1, kwargs...) =
    ObserveStage(name, Every(every), (; kwargs...))

function _map_symbolic_fields(f, value)
    mapped = map(
        field -> _map_symbolic_payload(f, getfield(value, field)),
        fieldnames(typeof(value)),
    )
    return typeof(value)(mapped...)
end

# Typed effects, bounded iteration domains, and protocol stages are part of a
# statement's semantic payload. They therefore participate in the same single
# symbolic traversal as direct expression fields.
_map_symbolic_payload(f, value::AbstractPottsEffect) =
    _map_symbolic_fields(f, value)
_map_symbolic_payload(f, value::AbstractIterationDomain) =
    _map_symbolic_fields(f, value)
_map_symbolic_payload(f, value::AbstractBoundaryPolicy) =
    _map_symbolic_fields(f, value)
_map_symbolic_payload(f, value::AbstractRelationshipEndpointPolicy) =
    _map_symbolic_fields(f, value)
_map_symbolic_payload(f, value::SweepStage) =
    _map_symbolic_fields(f, value)
_map_symbolic_payload(f, value::ObserveStage) =
    _map_symbolic_fields(f, value)
_map_symbolic_payload(f, value::SymmetricPair) =
    _map_symbolic_fields(f, value)
_map_symbolic_payload(f, value::ProposalContext) =
    map_symbolics(f, value)
_map_symbolic_payload(f, value::SiteBinding) =
    map_symbolics(f, value)
_map_symbolic_payload(f, value::CellBinding) =
    map_symbolics(f, value)
_map_symbolic_payload(f, value::ContactBinding) =
    map_symbolics(f, value)
_map_symbolic_payload(f, value::RelationshipBinding) =
    map_symbolics(f, value)

Protocol(stages...; name::Symbol = :protocol, source = UnknownSource(), kwargs...) =
    Protocol(name; stages, source, kwargs...)

RelationshipEnergy(id, edge::RelationshipBinding, expression; kwargs...) =
    HamiltonianTerm(
        id;
        domain = edges(edge.relationship),
        anchor = edge,
        expression,
        mechanism = :relationship,
        relationship = edge.relationship,
        kwargs...,
    )
RelationshipConstraint(id, relationship, constraint; kwargs...) =
    ProposalConstraint(id, constraint; mechanism = :relationship, relationship, kwargs...)
