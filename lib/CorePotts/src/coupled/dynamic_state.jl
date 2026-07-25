# Additive Phase 14 CPU reference state. These values deliberately do not modify LogicalPottsState
# or CanonicalCheckpoint v1; coupled execution and persistence own them as separately versioned
# state.

abstract type AbstractSiteInitializer end
struct FillSites{T} <: AbstractSiteInitializer
    value::T
end
struct SiteValues{A <: AbstractArray} <: AbstractSiteInitializer
    values::A
    checksum::String
end
SiteValues(values::AbstractArray; checksum::AbstractString = "") =
    SiteValues(values, String(checksum))
struct InitializeFromOwnership{L} <: AbstractSiteInitializer
    law::L
end

abstract type AbstractSiteOwnershipPolicy end
struct PreserveAtSite <: AbstractSiteOwnershipPolicy end
struct ResetChangedSites{T} <: AbstractSiteOwnershipPolicy
    value::T
end
struct AcceptedCopyManaged <: AbstractSiteOwnershipPolicy end

struct NoSiteInvariant end
site_value_valid(::NoSiteInvariant, value) = true
site_value_valid(invariant, value) = applicable(invariant, value) ?
    Bool(invariant(value)) : true

"""Declared lattice-site state with explicit initialization and ownership-change semantics."""
struct SiteProperty{I <: AbstractSiteInitializer, V, O <: AbstractSiteOwnershipPolicy, L, P}
    name::Symbol
    initial::I
    invariant::V
    ownership::O
    visibility::L
    persistence::P
    version::VersionNumber
end

function SiteProperty(name::Symbol; initial,
        invariant = NoSiteInvariant(),
        ownership::AbstractSiteOwnershipPolicy,
        visibility = :public,
        persistence = :checkpointed,
        version::VersionNumber = DYNAMIC_STATE_CONTRACT_VERSION)
    isempty(String(name)) && throw(ArgumentError("site-property identity must not be empty"))
    initializer = initial isa AbstractSiteInitializer ? initial : FillSites(initial)
    has_initial_value = initializer isa FillSites ||
        initializer isa SiteValues && !isempty(initializer.values)
    initial_value = initializer isa FillSites ? initializer.value :
        initializer isa SiteValues && !isempty(initializer.values) ?
        first(initializer.values) : nothing
    !has_initial_value || site_value_valid(invariant, initial_value) ||
        throw(ArgumentError("site-property initial value violates its invariant"))
    return SiteProperty(name, initializer, invariant, ownership,
        visibility, persistence, version)
end

component_identity(property::SiteProperty) =
    ComponentIdentity(property.name, property.version, :site_property)
component_semantic_data(property::SiteProperty) = (
    initializer = property.initial,
    invariant = property.invariant,
    ownership = property.ownership,
    visibility = property.visibility,
    persistence = property.persistence,
)
component_effects(::SiteProperty) = (:site_state,)

function _site_value_type(initializer::FillSites{T}) where {T}
    isbitstype(T) || throw(ArgumentError("site-property values must be isbits"))
    return T
end
function _site_value_type(initializer::SiteValues)
    T = eltype(initializer.values)
    isbitstype(T) || throw(ArgumentError("site-property values must be isbits"))
    return T
end
function _site_value_type(::InitializeFromOwnership)
    return nothing
end

mutable struct SitePropertyState{D <: SiteProperty, A <: AbstractArray, T}
    declaration::D
    values::A
    semantic_time::T
end

function initialize_site_property(property::SiteProperty,
        ownership::AbstractArray; semantic_time = 0)
    initializer = property.initial
    values = if initializer isa FillSites
        storage = similar(ownership, typeof(initializer.value), size(ownership))
        fill!(storage, initializer.value)
        storage
    elseif initializer isa SiteValues
        size(initializer.values) == size(ownership) || throw(ArgumentError(
            "SiteValues shape must exactly match the ownership lattice"))
        copy(initializer.values)
    else
        generated = map(initializer.law, ownership)
        size(generated) == size(ownership) || throw(ArgumentError(
            "InitializeFromOwnership must return one value per lattice site"))
        generated
    end
    # FillSites is validated once when the declaration is constructed. Revalidating the
    # materialized array is redundant and, on GPU backends, would compile a reduction whose
    # closure can accidentally retain host-only declaration metadata.
    if !(initializer isa FillSites)
        invariant = property.invariant
        all(value -> site_value_valid(invariant, value), values) ||
            throw(ArgumentError("site-property initialization violates its invariant"))
    end
    return SitePropertyState(property, values, semantic_time)
end

function Adapt.adapt_structure(to, state::SitePropertyState)
    return SitePropertyState(
        state.declaration, Adapt.adapt(to, state.values), state.semantic_time)
end

function site_property_value(state::SitePropertyState, site::Integer)
    checkbounds(state.values, site)
    return @inbounds state.values[site]
end

function _site_write!(state::SitePropertyState, site::Integer, value)
    converted = convert(eltype(state.values), value)
    site_value_valid(state.declaration.invariant, converted) || throw(
        SiteInvariantError(state.declaration.name, Int(site), converted))
    @inbounds state.values[site] = converted
    return state
end

struct SiteInvariantError{T} <: Exception
    property::Symbol
    site::Int
    value::T
end
Base.showerror(io::IO, error::SiteInvariantError) = print(io,
    "site property `", error.property, "` invariant failed at site ",
    error.site, " for value ", repr(error.value))

abstract type AbstractAcceptedCopyAssignment end
struct SetTo{T} <: AbstractAcceptedCopyAssignment
    value::T
end
struct PreserveSiteValue <: AbstractAcceptedCopyAssignment end

struct AlwaysAcceptedCopy end
(::AlwaysAcceptedCopy)(proposal, context) = true

"""Transaction-local site-property update for an already accepted actionable copy."""
struct AcceptedCopyUpdate{W, G <: AbstractAcceptedCopyAssignment,
        L <: AbstractAcceptedCopyAssignment}
    name::Symbol
    property::Symbol
    when::W
    gained::G
    lost::L
    version::VersionNumber
end

function AcceptedCopyUpdate(name::Symbol, property::Union{Symbol, SiteProperty};
        when = AlwaysAcceptedCopy(), gained::AbstractAcceptedCopyAssignment,
        lost::AbstractAcceptedCopyAssignment = PreserveSiteValue(),
        version::VersionNumber = COUPLED_EXECUTION_CONTRACT_VERSION)
    property_name = property isa Symbol ? property : property.name
    isempty(String(name)) && throw(ArgumentError(
        "accepted-copy update identity must not be empty"))
    return AcceptedCopyUpdate(name, property_name, when, gained, lost, version)
end

component_identity(update::AcceptedCopyUpdate) =
    ComponentIdentity(update.name, update.version, :accepted_copy_update)
component_semantic_data(update::AcceptedCopyUpdate) = (
    property = update.property, when = update.when,
    gained = update.gained, lost = update.lost)
component_effects(::AcceptedCopyUpdate) = (:accepted_copy_site_write,)

struct AcceptedCopyContext{S, T}
    state::S
    transaction::T
end

"""
Immutable, kernel-valid view of one site property.

The host-facing `SitePropertyState` remains mutable because it owns semantic time. Kernels receive
only this descriptor-free execution view, so after the backend's ordinary kernel-argument
adaptation a coupled attempt workspace is an isbits tree whose array storage remains on Metal or
ROCm.
"""
struct SitePropertyExecutionState{Name, O <: AbstractSiteOwnershipPolicy,
        A <: AbstractArray}
    ownership::O
    values::A
end
SitePropertyExecutionState(state::SitePropertyState) =
    SitePropertyExecutionState{state.declaration.name,
        typeof(state.declaration.ownership), typeof(state.values)}(
        state.declaration.ownership, state.values)

function Adapt.adapt_structure(to,
        state::SitePropertyExecutionState{Name}) where {Name}
    values = Adapt.adapt(to, state.values)
    return SitePropertyExecutionState{Name, typeof(state.ownership),
        typeof(values)}(state.ownership, values)
end

"""Kernel-valid accepted-copy effect with semantic metadata retained by the host declaration."""
struct AcceptedCopyExecutionEffect{Name, Property, W,
        G <: AbstractAcceptedCopyAssignment,
        L <: AbstractAcceptedCopyAssignment}
    when::W
    gained::G
    lost::L
end
AcceptedCopyExecutionEffect(effect::AcceptedCopyUpdate) =
    AcceptedCopyExecutionEffect{effect.name, effect.property,
        typeof(effect.when), typeof(effect.gained), typeof(effect.lost)}(
        effect.when, effect.gained, effect.lost)
@inline _effect_name(::AcceptedCopyExecutionEffect{Name}) where {Name} = Name
@inline _effect_property(
    ::AcceptedCopyExecutionEffect{Name, Property}) where {Name, Property} = Property

struct CoupledAttemptWorkspace{S <: Tuple, E <: Tuple}
    site_states::S
    effects::E
    CoupledAttemptWorkspace(site_states::S, effects::E, ::Val{:compiled}) where {
        S <: Tuple, E <: Tuple} = new{S, E}(site_states, effects)

    function CoupledAttemptWorkspace(site_states::Tuple, effects::Tuple)
        names = Tuple(state.declaration.name for state in site_states)
        length(unique(names)) == length(names) || throw(ArgumentError(
            "coupled attempt workspace site-property identities must be unique"))
        all(effect -> effect isa AcceptedCopyUpdate, effects) || throw(ArgumentError(
            "coupled attempt effects must be AcceptedCopyUpdate values"))
        all(effect -> effect.property in names, effects) || throw(ArgumentError(
            "every accepted-copy effect must target a workspace site property"))
        managed = Set(state.declaration.name for state in site_states
            if state.declaration.ownership isa AcceptedCopyManaged)
        covered = Set(effect.property for effect in effects)
        managed == intersect(managed, covered) || throw(ArgumentError(
            "every AcceptedCopyManaged site property requires a compatible accepted-copy writer"))
        for effect in effects
            state = first(item for item in site_states
                if item.declaration.name === effect.property)
            for assignment in (effect.gained, effect.lost)
                assignment isa SetTo || continue
                converted = convert(eltype(state.values), assignment.value)
                site_value_valid(state.declaration.invariant, converted) ||
                    throw(ArgumentError(
                        "accepted-copy literal write violates the target site-property invariant"))
            end
        end
        execution_states = map(SitePropertyExecutionState, site_states)
        execution_effects = map(AcceptedCopyExecutionEffect, effects)
        return new{typeof(execution_states), typeof(execution_effects)}(
            execution_states, execution_effects)
    end
end

function Adapt.adapt_structure(to, workspace::CoupledAttemptWorkspace)
    return CoupledAttemptWorkspace(
        Adapt.adapt(to, workspace.site_states), workspace.effects, Val(:compiled))
end

@inline _site_state_name(state::SitePropertyState) = state.declaration.name
@inline _site_state_name(
    ::SitePropertyExecutionState{Name}) where {Name} = Name

@inline function _find_site_state(states::Tuple, name::Symbol)
    state = first(states)
    _site_state_name(state) === name && return state
    return _find_site_state(Base.tail(states), name)
end
@noinline _find_site_state(::Tuple{}, name::Symbol) =
    throw(ArgumentError("site property `$name` is not present in the coupled workspace"))

@inline _assignment_value(::PreserveSiteValue, old) = old
@inline _assignment_value(assignment::SetTo, old) = assignment.value

@inline commit_accepted_copy_updates!(workspace,
    proposal, transaction, scientific_state) = nothing

function commit_accepted_copy_updates!(workspace::CoupledAttemptWorkspace,
        proposal, transaction, scientific_state)
    context = AcceptedCopyContext(scientific_state, transaction)
    site = proposal.recipient
    for state in workspace.site_states
        policy = state.ownership
        policy isa ResetChangedSites || continue
        @inbounds state.values[site] = convert(
            eltype(state.values), policy.value)
    end
    for effect in workspace.effects
        effect.when(proposal, context) || continue
        state = _find_site_state(
            workspace.site_states, _effect_property(effect))
        old = @inbounds state.values[site]
        value = _assignment_value(effect.gained, old)
        # Constructor/preflight validates literal writes. The hot path stays branch-free on both
        # host and device; dynamic invariant predicates remain a host-reference responsibility.
        @inbounds state.values[site] = convert(eltype(state.values), value)
    end
    return nothing
end

abstract type AbstractSiteUpdateLaw end
struct SaturatingSubtract{T} <: AbstractSiteUpdateLaw
    amount::T
    lower::T
end
SaturatingSubtract(amount::T; lower::T = zero(T)) where {T} =
    SaturatingSubtract(amount, lower)
struct SetSiteValue{T} <: AbstractSiteUpdateLaw
    value::T
end

struct SiteDynamics{U, S}
    name::Symbol
    property::Symbol
    update::U
    schedule::S
    version::VersionNumber
end

function SiteDynamics(name::Symbol, property::Union{Symbol, SiteProperty};
        update, schedule = EveryMCS(),
        version::VersionNumber = DYNAMIC_STATE_CONTRACT_VERSION)
    return SiteDynamics(name, property isa Symbol ? property : property.name,
        update, schedule, version)
end
component_identity(process::SiteDynamics) =
    ComponentIdentity(process.name, process.version, :site_dynamics)
component_semantic_data(process::SiteDynamics) = (
    property = process.property, update = process.update, schedule = process.schedule)
component_effects(::SiteDynamics) = (:site_phase_write,)

_updated_site_value(law::SaturatingSubtract, value) =
    max(law.lower, value - law.amount)
_updated_site_value(law::SetSiteValue, value) = law.value
_updated_site_value(law, value) = law(value)

@kernel function _site_dynamics_kernel!(values, update)
    index = @index(Global, Linear)
    @inbounds values[index] = convert(
        eltype(values), _updated_site_value(update, values[index]))
end

"""
Execute an independently site-local dynamics law on the selected backend without a host
materialization or steady-state allocation.
"""
function apply_site_dynamics!(plan::ExecutionPlan, state::SitePropertyState,
        process::SiteDynamics, target_mcs::Integer)
    process.property === state.declaration.name || throw(ArgumentError(
        "SiteDynamics targets a different site property"))
    is_due(process.schedule, target_mcs) || return false
    isequal(plan.backend, KernelAbstractions.get_backend(state.values)) ||
        throw(ArgumentError(
            "SiteDynamics storage backend does not match the execution plan"))
    kernel = _execution_kernel(
        plan, _site_dynamics_kernel!, length(state.values))
    launch!(plan, kernel, state.values, process.update;
        ndrange = length(state.values))
    state.semantic_time = target_mcs
    return true
end

function apply_site_dynamics!(state::SitePropertyState,
        process::SiteDynamics, target_mcs::Integer)
    process.property === state.declaration.name || throw(ArgumentError(
        "SiteDynamics targets a different site property"))
    is_due(process.schedule, target_mcs) || return false
    candidate = similar(state.values)
    for index in eachindex(state.values)
        value = _updated_site_value(process.update, @inbounds(state.values[index]))
        converted = convert(eltype(candidate), value)
        site_value_valid(state.declaration.invariant, converted) || throw(
            SiteInvariantError(state.declaration.name, Int(index), converted))
        @inbounds candidate[index] = converted
    end
    copyto!(state.values, candidate)
    state.semantic_time = target_mcs
    return true
end

struct Lag
    value::UInt32
    function Lag(value::Integer)
        0 <= value <= typemax(UInt32) || throw(ArgumentError(
            "history lag must be non-negative and fit UInt32"))
        return new(UInt32(value))
    end
end

struct HistoryValue{T}
    available::Bool
    value::T
end

struct HistoryLagUnavailableError <: Exception
    history::Symbol
    cell::CellID
    generation::CellGeneration
    lag::UInt32
end
Base.showerror(io::IO, error::HistoryLagUnavailableError) = print(io,
    "history `", error.history, "` has no lag ", error.lag,
    " for cell ", value(error.cell), " generation ", value(error.generation))

abstract type AbstractHistoryFill end
struct RepeatInitialSample <: AbstractHistoryFill end
struct MissingUntilFull <: AbstractHistoryFill end
struct ExplicitInitialHistory{V} <: AbstractHistoryFill
    values::V
end

abstract type AbstractHistoryDivisionPolicy end
struct ResetChildHistory <: AbstractHistoryDivisionPolicy end
struct CopyParentHistory <: AbstractHistoryDivisionPolicy end
abstract type AbstractHistoryTransitionPolicy end
struct PreserveHistory <: AbstractHistoryTransitionPolicy end
struct ResetHistory <: AbstractHistoryTransitionPolicy end

"""Bounded generation-aware cell history declaration."""
struct CellHistory{S, I <: AbstractHistoryFill, D <: AbstractHistoryDivisionPolicy,
        X <: AbstractHistoryTransitionPolicy}
    name::Symbol
    scope::Tuple
    source::S
    length::UInt32
    initial::I
    division::D
    transition::X
    retirement::ResetHistory
    version::VersionNumber
end

function CellHistory(name::Symbol, scope...; source, length::Integer,
        initial::AbstractHistoryFill,
        division::AbstractHistoryDivisionPolicy = ResetChildHistory(),
        transition::AbstractHistoryTransitionPolicy = PreserveHistory(),
        retirement::ResetHistory = ResetHistory(),
        version::VersionNumber = DYNAMIC_STATE_CONTRACT_VERSION)
    0 < length <= typemax(UInt32) || throw(ArgumentError(
        "cell-history length must be positive and fit UInt32"))
    return CellHistory(name, Tuple(scope), source, UInt32(length), initial, division,
        transition, retirement, version)
end
component_identity(history::CellHistory) =
    ComponentIdentity(history.name, history.version, :cell_history)
component_semantic_data(history::CellHistory) = (
    scope = history.scope, source = history.source, length = history.length,
    initial = history.initial,
    division = history.division, transition = history.transition,
    retirement = history.retirement)
component_effects(::CellHistory) = (:cell_history_state,)

struct HistorySample
    history::Symbol
end
HistorySample(history::Union{Symbol, CellHistory}) =
    HistorySample(history isa Symbol ? history : history.name)

mutable struct CellHistoryState{D <: CellHistory, T}
    declaration::D
    values::Matrix{T}
    heads::Vector{UInt32}
    fills::Vector{UInt32}
    generations::Vector{CellGeneration}
    latest_sample_mcs::UInt64
end

function initialize_cell_history(history::CellHistory, samples::AbstractVector{T},
        generations::AbstractVector{CellGeneration}) where {T}
    length(samples) == length(generations) || throw(ArgumentError(
        "history initial samples and generations must have equal capacity"))
    capacity = length(samples)
    width = Int(history.length)
    values = Matrix{T}(undef, capacity, width)
    heads = zeros(UInt32, capacity)
    fills = zeros(UInt32, capacity)
    for slot in 1:capacity
        if history.initial isa RepeatInitialSample
            @inbounds values[slot, :] .= samples[slot]
            heads[slot] = UInt32(width)
            fills[slot] = UInt32(width)
        elseif history.initial isa MissingUntilFull
            @inbounds values[slot, :] .= samples[slot]
        else
            explicit = history.initial.values
            size(explicit) == size(values) || throw(ArgumentError(
                "ExplicitInitialHistory must have capacity by history-length shape"))
            copyto!(values, explicit)
            heads[slot] = UInt32(width)
            fills[slot] = UInt32(width)
        end
    end
    return CellHistoryState(history, values, heads, fills,
        collect(generations), UInt64(0))
end

function _history_slot(state::CellHistoryState, cell::CellID,
        generation::CellGeneration)
    slot = Int(value(cell))
    checkbounds(state.generations, slot)
    state.generations[slot] == generation || throw(ArgumentError(
        "history access uses a stale cell generation"))
    return slot
end

function maybe_history_value(state::CellHistoryState, cell::CellID,
        generation::CellGeneration, lag::Lag)
    slot = _history_slot(state, cell, generation)
    lag.value < @inbounds(state.fills[slot]) ||
        return HistoryValue(false, @inbounds(state.values[slot, 1]))
    width = Int(state.declaration.length)
    head = Int(@inbounds state.heads[slot])
    column = mod1(head - Int(lag.value), width)
    return HistoryValue(true, @inbounds(state.values[slot, column]))
end

function history_value(state::CellHistoryState, cell::CellID,
        generation::CellGeneration, lag::Lag)
    result = maybe_history_value(state, cell, generation, lag)
    result.available || throw(HistoryLagUnavailableError(
        state.declaration.name, cell, generation, lag.value))
    return result.value
end

function sample_history!(state::CellHistoryState, samples::AbstractVector,
        active::AbstractVector{Bool}, generations::AbstractVector{CellGeneration},
        target_mcs::Integer)
    capacity = length(state.generations)
    length(samples) == capacity && length(active) == capacity &&
        length(generations) == capacity || throw(ArgumentError(
        "history sampling inputs must match history capacity"))
    candidate_values = copy(state.values)
    candidate_heads = copy(state.heads)
    candidate_fills = copy(state.fills)
    for slot in 1:capacity
        active[slot] || continue
        state.generations[slot] == generations[slot] || throw(ArgumentError(
            "history sampling uses a stale cell generation"))
        head = mod(Int(candidate_heads[slot]), Int(state.declaration.length)) + 1
        @inbounds candidate_values[slot, head] = convert(
            eltype(candidate_values), samples[slot])
        candidate_heads[slot] = UInt32(head)
        candidate_fills[slot] = min(state.declaration.length,
            candidate_fills[slot] + UInt32(1))
    end
    copyto!(state.values, candidate_values)
    copyto!(state.heads, candidate_heads)
    copyto!(state.fills, candidate_fills)
    state.latest_sample_mcs = UInt64(target_mcs)
    return state
end

struct CellEndpoint
    cell::CellID
    generation::CellGeneration
end
Base.isless(left::CellEndpoint, right::CellEndpoint) =
    (value(left.cell), value(left.generation)) <
    (value(right.cell), value(right.generation))

struct RelationshipCapacity
    value::UInt32
    function RelationshipCapacity(value::Integer)
        0 < value <= typemax(UInt32) || throw(ArgumentError(
            "relationship capacity must be positive and fit UInt32"))
        return new(UInt32(value))
    end
end

abstract type AbstractEndpointLifecyclePolicy end
struct RemoveIncidentEdges <: AbstractEndpointLifecyclePolicy end
struct RejectEndpointRetirement <: AbstractEndpointLifecyclePolicy end

"""Generation-aware bounded relationship declaration."""
struct RelationshipSet{T, E, L <: AbstractEndpointLifecyclePolicy}
    name::Symbol
    endpoint_scope::E
    edge_type::Type{T}
    directed::Bool
    maximum_degree::UInt32
    capacity::RelationshipCapacity
    endpoint_lifecycle::L
    version::VersionNumber
end

function RelationshipSet(name::Symbol, endpoint_scope = nothing;
        edge::Type{T}, directed::Bool = false,
        maximum_degree::Integer, capacity::RelationshipCapacity,
        endpoint_lifecycle::AbstractEndpointLifecyclePolicy = RemoveIncidentEdges(),
        version::VersionNumber = DYNAMIC_STATE_CONTRACT_VERSION) where {T}
    isbitstype(T) || throw(ArgumentError(
        "relationship payload type must be isbits"))
    0 < maximum_degree <= typemax(UInt32) || throw(ArgumentError(
        "maximum relationship degree must be positive and fit UInt32"))
    return RelationshipSet{T, typeof(endpoint_scope), typeof(endpoint_lifecycle)}(
        name, endpoint_scope, T, directed, UInt32(maximum_degree), capacity,
        endpoint_lifecycle, version)
end
component_identity(set::RelationshipSet) =
    ComponentIdentity(set.name, set.version, :relationship_set)
component_semantic_data(set::RelationshipSet) = (
    endpoint_scope = set.endpoint_scope, edge_type = set.edge_type, directed = set.directed,
    maximum_degree = set.maximum_degree, capacity = set.capacity,
    endpoint_lifecycle = set.endpoint_lifecycle)
component_effects(::RelationshipSet) = (:relationship_state,)

struct RelationshipEdge{T}
    left::CellEndpoint
    right::CellEndpoint
    payload::T
end

mutable struct RelationshipState{D <: RelationshipSet, T}
    declaration::D
    edges::Vector{RelationshipEdge{T}}
end
RelationshipState(set::RelationshipSet{T}) where {T} =
    RelationshipState(set, RelationshipEdge{T}[])

struct RelationshipCapacityError <: Exception
    relationship::Symbol
    requested::Int
    capacity::UInt32
end
Base.showerror(io::IO, error::RelationshipCapacityError) = print(io,
    "relationship `", error.relationship, "` capacity ", error.capacity,
    " cannot admit ", error.requested, " edges")

function _canonical_endpoints(set::RelationshipSet,
        left::CellEndpoint, right::CellEndpoint)
    left == right && throw(ArgumentError("relationship self-edges are not admitted"))
    return set.directed || isless(left, right) ? (left, right) : (right, left)
end

function _edge_index(state::RelationshipState,
        left::CellEndpoint, right::CellEndpoint)
    canonical = _canonical_endpoints(state.declaration, left, right)
    return findfirst(edge -> (edge.left, edge.right) == canonical, state.edges)
end

function _relationship_degree(edges, endpoint)
    return count(edge -> edge.left == endpoint || edge.right == endpoint, edges)
end

function create_relationship!(state::RelationshipState{D, T},
        left::CellEndpoint, right::CellEndpoint, payload::T) where {D, T}
    canonical = _canonical_endpoints(state.declaration, left, right)
    _edge_index(state, canonical...) === nothing || throw(ArgumentError(
        "duplicate relationship edge"))
    length(state.edges) < Int(state.declaration.capacity.value) || throw(
        RelationshipCapacityError(state.declaration.name,
            length(state.edges) + 1, state.declaration.capacity.value))
    for endpoint in canonical
        _relationship_degree(state.edges, endpoint) <
            Int(state.declaration.maximum_degree) || throw(ArgumentError(
                "relationship maximum degree exceeded"))
    end
    push!(state.edges, RelationshipEdge(canonical..., payload))
    sort!(state.edges; by = edge -> (
        value(edge.left.cell), value(edge.left.generation),
        value(edge.right.cell), value(edge.right.generation)))
    return state
end

function remove_relationship!(state::RelationshipState,
        left::CellEndpoint, right::CellEndpoint)
    index = _edge_index(state, left, right)
    index === nothing && return false
    deleteat!(state.edges, index)
    return true
end

function retune_relationship!(state::RelationshipState{D, T},
        left::CellEndpoint, right::CellEndpoint, payload::T) where {D, T}
    index = _edge_index(state, left, right)
    index === nothing && throw(ArgumentError("cannot retune an absent relationship"))
    edge = state.edges[index]
    state.edges[index] = RelationshipEdge(edge.left, edge.right, payload)
    return state
end

function relationship_edges(state::RelationshipState, endpoint::CellEndpoint)
    return Tuple(edge for edge in state.edges
        if edge.left == endpoint || edge.right == endpoint)
end

function relationship_payload(state::RelationshipState,
        left::CellEndpoint, right::CellEndpoint)
    index = _edge_index(state, left, right)
    index === nothing && throw(ArgumentError("relationship edge is absent"))
    return state.edges[index].payload
end

function retire_relationship_endpoint!(state::RelationshipState,
        endpoint::CellEndpoint)
    incident = findall(edge -> edge.left == endpoint || edge.right == endpoint,
        state.edges)
    isempty(incident) && return state
    state.declaration.endpoint_lifecycle isa RemoveIncidentEdges || throw(
        ArgumentError("relationship endpoint retirement rejected by policy"))
    deleteat!(state.edges, incident)
    return state
end
