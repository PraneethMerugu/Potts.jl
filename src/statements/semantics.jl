abstract type AbstractEffectClass end
"""Effect class for expressions that only read scientific state."""
struct PureRead <: AbstractEffectClass end
"""Effect class for simultaneous assignment at a synchronous stage."""
struct SynchronousAssign <: AbstractEffectClass end
"""Effect class for updates conditioned on an accepted proposal."""
struct AcceptedCopyEffect <: AbstractEffectClass end
"""Effect class for canonically ordered bounded batches."""
struct OrderedBatchEffect <: AbstractEffectClass end

"""Phase in which copy proposals are evaluated."""
struct Proposal <: AbstractPottsPhase end
"""Phase in which accepted-copy effects are evaluated."""
struct AcceptedCopy <: AbstractPottsPhase end
"""Phase after one complete Monte Carlo step."""
struct AfterMCS <: AbstractPottsPhase end
"""Phase in which staged relationship changes settle."""
struct RelationshipCommit <: AbstractPottsPhase end
"""Phase owned by cell lifecycle transactions."""
struct Lifecycle <: AbstractPottsPhase end

"""`Before(phase)` places a stage immediately before `phase`."""
struct Before{P <: AbstractPottsPhase} <: AbstractPottsPhase
    phase::P
end
"""`After(phase)` places a stage immediately after `phase`."""
struct After{P <: AbstractPottsPhase} <: AbstractPottsPhase
    phase::P
end

abstract type AbstractCadence end
"""Cadence that is due on every Monte Carlo step."""
struct EveryMCS <: AbstractCadence end
"""`AtMCS(mcs)` is due once at the specified nonnegative step."""
struct AtMCS <: AbstractCadence
    mcs::Int
    function AtMCS(mcs::Integer)
        mcs >= 0 || throw(ArgumentError("AtMCS must be nonnegative"))
        new(Int(mcs))
    end
end
"""`Every(cadence)` is due at positive multiples of `cadence`."""
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
struct ModelDomain <: AbstractIterationDomain end

"""Construct the site iteration domain for a lattice domain."""
sites(domain) = Sites(domain)
"""Construct the finite-cell iteration domain for `kind`."""
cells(kind) = Cells(kind)
"""Construct the canonical-contact iteration domain for `relation`."""
contacts(relation) = Contacts(relation)
"""Construct the live-edge iteration domain for a relationship state."""
edges(relationship) = Edges(relationship)
"""Construct edges incident to `cell` within a relationship state."""
incident_edges(relationship, cell) = IncidentEdges(relationship, cell)
"""Construct the singleton model iteration domain."""
model() = ModelDomain()

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

"""`Assign(target, value)` publishes `value` to a declared state target."""
struct Assign{T, V} <: AbstractPottsEffect
    target::T
    value::V
end

"""Request relationship creation with optional payload and priority."""
struct Create{R, A, B, P, Q} <: AbstractPottsEffect
    relationship::R
    endpoint_a::A
    endpoint_b::B
    payload::P
    priority::Q
end
Create(relationship, a, b; payload = NamedTuple(), priority = 0) =
    Create(relationship, a, b, payload, priority)

"""Request removal of one relationship edge with optional priority."""
struct Remove{R, E, P} <: AbstractPottsEffect
    relationship::R
    edge::E
    priority::P
end
Remove(relationship, edge; priority = 0) = Remove(relationship, edge, priority)

"""Request replacement of an existing relationship payload."""
struct Retune{R, E, P, Q} <: AbstractPottsEffect
    relationship::R
    edge::E
    payload::P
    priority::Q
end
Retune(relationship, edge; payload, priority = 0) =
    Retune(relationship, edge, payload, priority)

abstract type AbstractBoundaryPolicy end
"""Periodic lattice boundary policy."""
struct Periodic <: AbstractBoundaryPolicy end
"""Closed lattice boundary policy with no wrapped neighbors."""
struct Closed <: AbstractBoundaryPolicy end
"""Boundary policy that reserves the border for the supplied cell kind."""
struct FrozenBorder{K} <: AbstractBoundaryPolicy
    kind::K
end

abstract type AbstractNeighborhood end
"""Axis-aligned neighborhood of positive Manhattan `radius`."""
struct VonNeumann <: AbstractNeighborhood
    radius::Int
end
VonNeumann(radius::Integer = 1) =
    radius > 0 ? VonNeumann(Int(radius)) :
    throw(ArgumentError("neighborhood radius must be positive"))
"""Full neighborhood of positive Chebyshev `radius`."""
struct Moore <: AbstractNeighborhood
    radius::Int
end
Moore(radius::Integer = 1) =
    radius > 0 ? Moore(Int(radius)) :
    throw(ArgumentError("neighborhood radius must be positive"))

abstract type AbstractOwnershipChangePolicy end
"""Reset associated state when its site's owner changes."""
struct ClearOnOwnershipChange <: AbstractOwnershipChangePolicy end
"""Preserve associated state when its site's owner changes."""
struct PreserveOnOwnershipChange <: AbstractOwnershipChangePolicy end

abstract type AbstractRelationshipEndpointPolicy end
"""Undirected endpoint-kind contract for a relationship state."""
struct Undirected{A, B} <: AbstractRelationshipEndpointPolicy
    kind_a::A
    kind_b::B
end
"""Remove incident relationship edges when an endpoint retires."""
struct RemoveWithEndpoint end
"""Reject endpoint retirement while an incident edge exists."""
struct RejectEndpointRetirement end

"""Built-in fixed-grid forward-Euler diffusion/decay/source field component."""
struct DiscreteFieldEuler end

abstract type AbstractChemotaxisMode end
"""Apply chemotactic response only to extension proposals."""
struct ExtensionsOnly <: AbstractChemotaxisMode end
"""Apply chemotactic response only to retraction proposals."""
struct RetractionsOnly <: AbstractChemotaxisMode end
"""Apply chemotactic response to extensions and retractions."""
struct ExtensionsAndRetractions <: AbstractChemotaxisMode end

abstract type AbstractInterpolationPolicy end
"""Nearest-sample field interpolation policy."""
struct Nearest <: AbstractInterpolationPolicy end
"""Multilinear field interpolation policy."""
struct Multilinear <: AbstractInterpolationPolicy end
"""Marker for fields sampled at lattice-cell centers."""
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

"""`AttemptsPerSite(count=1)` declares a positive proposal-attempt budget."""
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
"""Construct an unordered kind pair for `ContactEnergy` laws."""
(↔)(a, b) = SymmetricPair(a, b)

"""Declare a regular lattice and any named neighborhood relations."""
function Lattice(shape::Tuple{Vararg{Integer}};
        name::Symbol = :lattice,
        spacing = ntuple(_ -> 1.0, length(shape)),
        boundary::AbstractBoundaryPolicy = Periodic(),
        max_cells::Integer = prod(shape),
        relations = NamedTuple(),
    )
    all(>(0), shape) || throw(ArgumentError("lattice dimensions must be positive"))
    length(spacing) == length(shape) ||
        throw(ArgumentError("lattice spacing must match lattice dimensions"))
    0 < max_cells <= prod(shape) || throw(ArgumentError(
        "max_cells must be between one and the number of lattice sites"
    ))
    domain = LatticeDomain(
        name;
        shape = Tuple(Int.(shape)),
        spacing = Tuple(spacing),
        boundary,
        max_cells = Int(max_cells),
    )
    relation_statements = AbstractPottsStatement[]
    for (relation_name, neighborhood) in pairs(relations)
        push!(relation_statements, SpatialRelation(
            Symbol(relation_name); domain = name, neighborhood
        ))
    end
    return StatementSet((domain, relation_statements...))
end

"""Construct the standard quadratic cell-volume Hamiltonian term."""
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

"""Construct a contact-energy term from unordered kind-pair energy laws."""
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

"""Construct the standard quadratic cell-elongation Hamiltonian term."""
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

"""Construct a chemotactic proposal term sampling `field`."""
function Chemotaxis(kind, field; strength,
        mode::AbstractChemotaxisMode = ExtensionsOnly(),
        sample::AbstractInterpolationPolicy = Nearest(),
        name::Symbol = Symbol(:chemotaxis_, Symbol(statement_id(kind))))
    copy = ProposalContext(:copy)
    response = -strength * (
        field_value(field, copy.target_site) - field_value(field, copy.source_site)
    )
    expression = ifelse(
        copy.is_extension & (source_kind(copy) == _kind_token(kind)),
        response,
        zero(strength),
    )
    return ProposalDrive(
        name,
        expression;
        mechanism = :chemotaxis,
        drive_scale = :energy,
        kind,
        field,
        strength,
        mode,
        sample,
    )
end

"""Construct a local-connectivity proposal constraint for `kind`."""
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

"""Construct the activity proposal drive for a bounded activity state."""
function ActEnergy(kind, activity; maximum, strength,
        reduction::Symbol = :activity_neighborhood,
        name::Symbol = Symbol(:activity_, Symbol(statement_id(kind))))
    expression = _potts_act_energy(
        _kind_token(kind),
        activity,
        _spatial_relation_token(reduction),
        maximum,
        strength,
    )
    return ProposalDrive(
        name, expression;
        mechanism = :activity,
        drive_scale = :energy,
        kind,
        activity,
        maximum,
        strength,
        reduction,
    )
end

"""Construct a synchronous process containing one effect."""
Synchronous(id, effect; phase = AfterMCS(), kwargs...) =
    SynchronousProcess(id; effects = (effect,), phase, kwargs...)
AcceptedCopy(id::Symbol, effect; when = true, phase = AcceptedCopy(), kwargs...) =
    AcceptedCopyProcess(id; expression = when, effects = (effect,), phase, kwargs...)

"""One named CPM sweep stage with an attempt budget and options."""
struct SweepStage{A, O}
    name::Symbol
    attempts::A
    options::O
end
"""Construct a named `SweepStage` for a `Protocol`."""
Sweep(name::Symbol = :cpm; attempts = AttemptsPerSite(1), kwargs...) =
    SweepStage(name, attempts, (; kwargs...))

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

"""Construct a Hamiltonian term iterating over a relationship state."""
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
"""Construct a proposal constraint derived from relationship state."""
RelationshipConstraint(id, relationship, constraint; kwargs...) =
    ProposalConstraint(id, constraint; mechanism = :relationship, relationship, kwargs...)
