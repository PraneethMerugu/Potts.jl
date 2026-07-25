struct StableRelationshipPriority end

abstract type AbstractRelationshipRequest end
struct CreateRelationship{T} <: AbstractRelationshipRequest
    left::CellEndpoint
    right::CellEndpoint
    payload::T
    priority::Int32
end
CreateRelationship(left, right, payload; priority::Integer = 0) =
    CreateRelationship(left, right, payload, Int32(priority))
struct RemoveRelationship <: AbstractRelationshipRequest
    left::CellEndpoint
    right::CellEndpoint
    priority::Int32
end
RemoveRelationship(left, right; priority::Integer = 0) =
    RemoveRelationship(left, right, Int32(priority))
struct RetuneRelationship{T} <: AbstractRelationshipRequest
    left::CellEndpoint
    right::CellEndpoint
    payload::T
    priority::Int32
end
RetuneRelationship(left, right, payload; priority::Integer = 0) =
    RetuneRelationship(left, right, payload, Int32(priority))

"""Atomic relationship transaction planner over one common graph/cell snapshot."""
struct RelationshipDynamics{L, C}
    name::Symbol
    relationships::Symbol
    law::L
    conflicts::C
    version::VersionNumber
end
function RelationshipDynamics(name::Symbol,
        relationships::Union{Symbol, RelationshipSet};
        law = nothing, create = nothing, remove = nothing, update = nothing,
        conflicts = StableRelationshipPriority(),
        version::VersionNumber = DYNAMIC_STATE_CONTRACT_VERSION)
    supplied = count(value -> value !== nothing, (create, remove, update))
    if law !== nothing && supplied > 0
        throw(ArgumentError(
            "RelationshipDynamics accepts either law or create/remove/update policies"))
    end
    law isa Function && throw(ArgumentError(
        "stable relationship laws must use DirectLaw with explicit identity"))
    for policy in (create, remove, update)
        policy isa Function && throw(ArgumentError(
            "stable relationship policies must use DirectLaw with explicit identity"))
    end
    resolved_law = law === nothing ?
        RelationshipPolicyBundle(create, remove, update) : law
    return RelationshipDynamics(name,
        relationships isa Symbol ? relationships : relationships.name,
        resolved_law, conflicts, version)
end

struct RelationshipPolicyBundle{C, R, U}
    create::C
    remove::R
    update::U
end

component_identity(process::RelationshipDynamics) =
    ComponentIdentity(process.name, process.version, :relationship_dynamics)
component_semantic_data(process::RelationshipDynamics) = (
    relationships = process.relationships,
    law = process.law, conflicts = process.conflicts)
component_effects(::RelationshipDynamics) = (:relationship_phase_write,)
process_reads(process::RelationshipDynamics) =
    ((:relationships, process.relationships), (:ownership, :cells))
process_writes(process::RelationshipDynamics) =
    ((:relationships, process.relationships),)

function _relationship_requests(law, relationships, potts_snapshot,
        target_mcs, stage)
    applicable(law, relationships, potts_snapshot, target_mcs, stage) &&
        return Tuple(law(relationships, potts_snapshot, target_mcs, stage))
    applicable(law, relationships, potts_snapshot, target_mcs) &&
        return Tuple(law(relationships, potts_snapshot, target_mcs))
    applicable(law, relationships, potts_snapshot) &&
        return Tuple(law(relationships, potts_snapshot))
    throw(ArgumentError(
        "relationship law must return typed requests from a supported snapshot signature"))
end

function _relationship_requests(law::DirectLaw, relationships,
        potts_snapshot, target_mcs, stage)
    function_value = law.function_value
    applicable(function_value, relationships, potts_snapshot, target_mcs, stage) &&
        return Tuple(function_value(
            relationships, potts_snapshot, target_mcs, stage))
    applicable(function_value, relationships, potts_snapshot, target_mcs) &&
        return Tuple(function_value(
            relationships, potts_snapshot, target_mcs))
    applicable(function_value, relationships, potts_snapshot) &&
        return Tuple(function_value(relationships, potts_snapshot))
    throw(ArgumentError(
        "relationship law `$(law.name)` has no supported snapshot signature"))
end

function _relationship_requests(bundle::RelationshipPolicyBundle,
        relationships, potts_snapshot, target_mcs, stage)
    requests = ()
    for policy in (bundle.remove, bundle.update, bundle.create)
        policy === nothing && continue
        produced = _relationship_requests(
            policy, relationships, potts_snapshot, target_mcs, stage)
        requests = (requests..., produced...)
    end
    return requests
end

_request_key(request::AbstractRelationshipRequest) = (
    -Int(request.priority),
    value(request.left.cell), value(request.left.generation),
    value(request.right.cell), value(request.right.generation),
    request isa RemoveRelationship ? 1 :
    request isa RetuneRelationship ? 2 : 3)

function apply_relationship_dynamics!(state::RelationshipState,
        process::RelationshipDynamics, potts_snapshot,
        target_mcs::Integer; stage = nothing)
    process.relationships === state.declaration.name || throw(ArgumentError(
        "RelationshipDynamics targets a different RelationshipSet"))
    requests = collect(_relationship_requests(
        process.law, deepcopy(state), potts_snapshot, target_mcs, stage))
    all(request -> request isa AbstractRelationshipRequest, requests) ||
        throw(ArgumentError(
            "relationship dynamics produced an untyped transaction request"))
    sort!(requests; by = _request_key)
    candidate = deepcopy(state)
    touched = Set{Tuple{CellEndpoint, CellEndpoint}}()
    for request in requests
        endpoints = _canonical_endpoints(
            candidate.declaration, request.left, request.right)
        endpoints in touched && throw(ArgumentError(
            "relationship transaction contains conflicting requests for one edge"))
        push!(touched, endpoints)
        if request isa RemoveRelationship
            remove_relationship!(candidate, endpoints...)
        elseif request isa RetuneRelationship
            retune_relationship!(
                candidate, endpoints..., request.payload)
        else
            create_relationship!(
                candidate, endpoints..., request.payload)
        end
    end
    _publish_state!(state, candidate)
    return state
end

function execute_process!(candidate::CoupledState, snapshot::CoupledState,
        potts_snapshot, process::RelationshipDynamics,
        target_mcs, stage, interval)
    source = _state_by_name(snapshot.relationships, process.relationships)
    target = _state_by_name(candidate.relationships, process.relationships)
    _publish_state!(target, source)
    apply_relationship_dynamics!(
        target, process, potts_snapshot, target_mcs; stage)
    return nothing
end

function _apply_site_lifecycle!(state::SitePropertyState,
        before::LogicalPottsState, after::LogicalPottsState)
    policy = state.declaration.ownership
    policy isa PreserveAtSite && return state
    before_owners = lattice_storage(before)
    after_owners = lattice_storage(after)
    for site in eachindex(before_owners)
        before_owners[site] == after_owners[site] && continue
        if policy isa ResetChangedSites
            _site_write!(state, site, policy.value)
        else
            throw(ArgumentError(
                "AcceptedCopyManaged does not define lifecycle-driven ownership changes; declare a coupled lifecycle site policy"))
        end
    end
    return state
end

function _apply_history_lifecycle!(state::CellHistoryState,
        before::LogicalPottsState, after::LogicalPottsState)
    for slot in eachindex(state.generations)
        cell = CellID(slot)
        active_after = is_active(after, cell)
        next_generation = generation(after, cell)
        if !active_after || state.generations[slot] != next_generation
            state.heads[slot] = UInt32(0)
            state.fills[slot] = UInt32(0)
            state.generations[slot] = next_generation
        end
    end
    return state
end

function _apply_relationship_lifecycle!(state::RelationshipState,
        before::LogicalPottsState, after::LogicalPottsState)
    stale = CellEndpoint[]
    for edge in state.edges, endpoint in (edge.left, edge.right)
        cell = endpoint.cell
        if !is_active(after, cell) || generation(after, cell) != endpoint.generation
            endpoint in stale || push!(stale, endpoint)
        end
    end
    for endpoint in stale
        retire_relationship_endpoint!(state, endpoint)
    end
    return state
end

function _apply_membrane_lifecycle!(state::MembranePropertyState,
        before::LogicalPottsState, after::LogicalPottsState)
    initial = state.declaration.initial.value
    for slot in axes(state.values, 1)
        cell = CellID(slot)
        active_after = is_active(after, cell)
        generation_after = generation(after, cell)
        if !active_after
            fill!(@view(state.values[slot, :]), initial)
            state.active[slot] = false
            state.generations[slot] = generation_after
        elseif !state.active[slot] ||
                state.generations[slot] != generation_after
            fill!(@view(state.values[slot, :]), initial)
            state.active[slot] = true
            state.generations[slot] = generation_after
        end
    end
    return state
end

"""Apply coupled-state cleanup after one accepted CorePotts lifecycle transaction."""
function apply_coupled_lifecycle!(state::CoupledState,
        before::LogicalPottsState, after::LogicalPottsState)
    candidate = deepcopy(state)
    foreach(item -> _apply_site_lifecycle!(item, before, after),
        candidate.site_states)
    foreach(item -> _apply_history_lifecycle!(item, before, after),
        candidate.histories)
    foreach(item -> _apply_relationship_lifecycle!(item, before, after),
        candidate.relationships)
    foreach(item -> _apply_membrane_lifecycle!(item, before, after),
        candidate.membranes)
    publish_coupled_state!(state, candidate)
    return state
end
