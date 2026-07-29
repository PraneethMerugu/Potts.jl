struct ElasticLinkRetune{PROPERTY, S, T <: AbstractFloat}
    name::Symbol
    relationships::Symbol
    scope::S
    property::Symbol
    parameters::ElasticLinkParameters{T}
    version::VersionNumber
end
function ElasticLinkRetune(name::Symbol,
        relationships::Union{Symbol, RelationshipSet}, scope;
        property::Symbol, strength::T, target_length::T,
        maximum_length::T,
        version::VersionNumber = DYNAMIC_STATE_CONTRACT_VERSION) where {
        T <: AbstractFloat}
    parameters = ElasticLinkParameters(
        strength, target_length, maximum_length)
    return ElasticLinkRetune{
        property, typeof(scope), T}(
        name,
        relationships isa Symbol ? relationships : relationships.name,
        scope, property, parameters, version)
end
component_identity(process::ElasticLinkRetune) =
    ComponentIdentity(
        process.name, process.version, :relationship_retune)
component_semantic_data(process::ElasticLinkRetune) = (
    relationships = process.relationships,
    scope = process.scope, property = process.property,
    parameters = process.parameters)
process_reads(process::ElasticLinkRetune) = (
    (:relationships, process.relationships),
    (:ownership, :cells))
process_writes(process::ElasticLinkRetune) = (
    (:relationships, process.relationships),
    (:cell_property, process.property))

struct ElasticLinkRetuneWorkspace{
        P <: AbstractVector, T <: AbstractVector,
        C <: AbstractVector{UInt32}}
    candidate_property::P
    candidate_strength::T
    candidate_target_length::T
    candidate_maximum_length::T
    status::C
    failing_edge::C
end

function ElasticLinkRetuneWorkspace(
        state::RelationshipState{
            D, ElasticLinkParameters{T}},
        property_values::AbstractVector{T}) where {D, T}
    payload = state.payload
    payload isa ElasticLinkColumns || throw(ArgumentError(
        "elastic relationship state lacks SoA payload columns"))
    status = similar(state.count)
    failing_edge = similar(state.count)
    fill!(status, UInt32(0))
    fill!(failing_edge, UInt32(0))
    return ElasticLinkRetuneWorkspace(
        similar(property_values),
        similar(payload.strength),
        similar(payload.target_length),
        similar(payload.maximum_length),
        status, failing_edge)
end

function Adapt.adapt_structure(to,
        workspace::ElasticLinkRetuneWorkspace)
    return ElasticLinkRetuneWorkspace(
        Adapt.adapt(to, workspace.candidate_property),
        Adapt.adapt(to, workspace.candidate_strength),
        Adapt.adapt(to, workspace.candidate_target_length),
        Adapt.adapt(to, workspace.candidate_maximum_length),
        Adapt.adapt(to, workspace.status),
        Adapt.adapt(to, workspace.failing_edge))
end

"""
Compiled execution view for an immutable `ElasticLinkRetune` declaration.

The wrapper owns only bounded scratch storage. Relationship payload and cell properties remain
authoritative in `CoupledState` and `CompiledScientificState`, respectively.
"""
struct ElasticLinkRetuneExecution{
        P <: ElasticLinkRetune,
        W <: ElasticLinkRetuneWorkspace}
    process::P
    workspace::W
end

function ElasticLinkRetuneExecution(
        process::ElasticLinkRetune,
        relationships::RelationshipState,
        state::Union{
            LogicalPottsState,
            CompiledScientificState})
    property = _coupled_property_column(
        state, process.property)
    workspace = ElasticLinkRetuneWorkspace(
        relationships, property)
    return ElasticLinkRetuneExecution(
        process, workspace)
end

function realize_coupled_process(
        process::ElasticLinkRetune,
        state::CoupledState,
        scientific::CompiledScientificState)
    relationships = _state_by_name(
        state.relationships,
        process.relationships)
    return ElasticLinkRetuneExecution(
        process, relationships, scientific)
end

function Adapt.adapt_structure(
        to, execution::ElasticLinkRetuneExecution)
    return ElasticLinkRetuneExecution(
        Adapt.adapt(to, execution.process),
        Adapt.adapt(to, execution.workspace))
end

component_identity(
    execution::ElasticLinkRetuneExecution) =
    component_identity(execution.process)
component_semantic_data(
    execution::ElasticLinkRetuneExecution) =
    component_semantic_data(execution.process)
process_reads(execution::ElasticLinkRetuneExecution) =
    process_reads(execution.process)
process_writes(execution::ElasticLinkRetuneExecution) =
    process_writes(execution.process)
canonical_process_law(
    execution::ElasticLinkRetuneExecution) =
    execution.process

function apply_elastic_link_retune!(
        logical::LogicalPottsState,
        state::RelationshipState{
            D, ElasticLinkParameters{T}},
        process::ElasticLinkRetune,
        workspace::ElasticLinkRetuneWorkspace) where {D, T}
    return apply_elastic_link_retune!(
        logical, state, process,
        process.parameters, workspace)
end

function apply_elastic_link_retune!(
        logical::LogicalPottsState,
        state::RelationshipState{
            D, ElasticLinkParameters{T}},
        process::ElasticLinkRetune,
        parameters::ElasticLinkParameters{T},
        workspace::ElasticLinkRetuneWorkspace) where {D, T}
    process.relationships === state.declaration.name ||
        throw(ArgumentError(
            "elastic retune targets a different relationship set"))
    property = property_values(logical, process.property)
    length(property) == length(workspace.candidate_property) ||
        throw(DimensionMismatch(
            "elastic retune cell-property capacities differ"))
    payload = state.payload
    payload isa ElasticLinkColumns || throw(ArgumentError(
        "elastic relationship state lacks SoA payload columns"))
    copyto!(workspace.candidate_property, property)
    copyto!(workspace.candidate_strength, payload.strength)
    copyto!(
        workspace.candidate_target_length, payload.target_length)
    copyto!(
        workspace.candidate_maximum_length, payload.maximum_length)
    fill!(workspace.status, UInt32(0))
    fill!(workspace.failing_edge, UInt32(0))
    for index in 1:_relationship_count(state)
        edge = _relationship_edge(state, index)
        for endpoint in (edge.left, edge.right)
            if !is_active(logical, endpoint.cell) ||
                    generation(logical, endpoint.cell) !=
                        endpoint.generation
                workspace.status[1] = UInt32(1)
                workspace.failing_edge[1] = UInt32(index)
                throw(ArgumentError(
                    "elastic retune encountered a stale endpoint at edge $index"))
            end
        end
        @inbounds begin
            workspace.candidate_strength[index] =
                parameters.strength
            workspace.candidate_target_length[index] =
                parameters.target_length
            workspace.candidate_maximum_length[index] =
                parameters.maximum_length
        end
    end
    for slot in eachindex(property)
        cell = CellID(slot)
        is_active(logical, cell) || continue
        _cell_scope_matches_exchange(
            process.scope, logical, cell) || continue
        @inbounds workspace.candidate_property[slot] =
            parameters.strength
    end
    copyto!(property, workspace.candidate_property)
    copyto!(payload.strength, workspace.candidate_strength)
    copyto!(
        payload.target_length, workspace.candidate_target_length)
    copyto!(
        payload.maximum_length, workspace.candidate_maximum_length)
    state.publication_epoch[1] += UInt64(1)
    return state
end

@inline function _record_relationship_failure!(
        status, failing_edge, code, index)
    Atomix.@atomic max(status[1], UInt32(code))
    Atomix.@atomic min(failing_edge[1], UInt32(index))
    return nothing
end

@kernel function _elastic_retune_initialize!(
        candidate_property, property,
        candidate_strength, strength,
        candidate_target_length, target_length,
        candidate_maximum_length, maximum_length,
        status, failing_edge, edge_capacity)
    index = @index(Global, Linear)
    if index <= length(property)
        @inbounds candidate_property[index] = property[index]
    end
    if index <= edge_capacity
        @inbounds begin
            candidate_strength[index] = strength[index]
            candidate_target_length[index] = target_length[index]
            candidate_maximum_length[index] = maximum_length[index]
        end
    end
    if index == 1
        @inbounds begin
            status[1] = UInt32(0)
            failing_edge[1] = typemax(UInt32)
        end
    end
end

@kernel function _elastic_retune_apply!(
        candidate_property,
        candidate_strength, candidate_target_length,
        candidate_maximum_length,
        relationship_endpoint_a, relationship_generation_a,
        relationship_endpoint_b, relationship_generation_b,
        relationship_active, relationship_count,
        cell_active, cell_generations, cell_types, scope_type,
        strength, target_length, maximum_length,
        status, failing_edge)
    index = @index(Global, Linear)
    if index <= length(candidate_property)
        @inbounds if cell_active[index] != zero(eltype(cell_active)) &&
                _portable_cell_eligible(scope_type, cell_types[index])
            candidate_property[index] = strength
        end
    end
    if index <= Int(@inbounds relationship_count[1]) &&
            @inbounds(relationship_active[index] != UInt8(0))
        left = @inbounds relationship_endpoint_a[index]
        left_generation =
            @inbounds relationship_generation_a[index]
        right = @inbounds relationship_endpoint_b[index]
        right_generation =
            @inbounds relationship_generation_b[index]
        if _relationship_endpoint_is_current(
                cell_active, cell_generations,
                left, left_generation) &&
                _relationship_endpoint_is_current(
                    cell_active, cell_generations,
                    right, right_generation)
            @inbounds begin
                candidate_strength[index] = strength
                candidate_target_length[index] = target_length
                candidate_maximum_length[index] = maximum_length
            end
        else
            _record_relationship_failure!(
                status, failing_edge, 1, index)
        end
    end
end

@kernel function _elastic_retune_commit!(
        property, candidate_property,
        strength, candidate_strength,
        target_length, candidate_target_length,
        maximum_length, candidate_maximum_length,
        publication_epoch, status, edge_capacity)
    index = @index(Global, Linear)
    @inbounds if status[1] == UInt32(0)
        index <= length(property) &&
            (property[index] = candidate_property[index])
        if index <= edge_capacity
            strength[index] = candidate_strength[index]
            target_length[index] = candidate_target_length[index]
            maximum_length[index] =
                candidate_maximum_length[index]
        end
        index == 1 &&
            (publication_epoch[1] += UInt64(1))
    end
end

function apply_elastic_link_retune!(
        plan::ExecutionPlan,
        scientific::CompiledScientificState,
        state::RelationshipState{
            D, ElasticLinkParameters{T}},
        process::ElasticLinkRetune,
        workspace::ElasticLinkRetuneWorkspace) where {D, T}
    return apply_elastic_link_retune!(
        plan, scientific, state, process,
        process.parameters, workspace)
end

function apply_elastic_link_retune!(
        plan::ExecutionPlan,
        scientific::CompiledScientificState,
        state::RelationshipState{
            D, ElasticLinkParameters{T}},
        process::ElasticLinkRetune,
        parameters::ElasticLinkParameters{T},
        workspace::ElasticLinkRetuneWorkspace) where {D, T}
    process.relationships === state.declaration.name ||
        throw(ArgumentError(
            "elastic retune targets a different relationship set"))
    execution = scientific_execution(scientific)
    core = execution.core
    property = getproperty(core.properties, process.property)
    payload = state.payload
    payload isa ElasticLinkColumns || throw(ArgumentError(
        "elastic relationship state lacks SoA payload columns"))
    arrays = (
        property, payload.strength, payload.target_length,
        payload.maximum_length, state.endpoint_a,
        state.generation_a, state.endpoint_b,
        state.generation_b, state.active, state.count,
        state.publication_epoch,
        workspace.candidate_property,
        workspace.candidate_strength,
        workspace.candidate_target_length,
        workspace.candidate_maximum_length,
        workspace.status, workspace.failing_edge,
        core.active, core.generations, core.cell_types)
    all(array -> isbitstype(eltype(array)) &&
            isequal(KernelAbstractions.get_backend(array), plan.backend),
        arrays) || throw(ArgumentError(
        "portable elastic-retune storage has a backend mismatch"))
    length(property) == length(workspace.candidate_property) ||
        throw(DimensionMismatch(
            "portable elastic-retune cell capacities differ"))
    edge_capacity = length(state.active)
    all(==(edge_capacity), map(length, (
        payload.strength, payload.target_length,
        payload.maximum_length,
        workspace.candidate_strength,
        workspace.candidate_target_length,
        workspace.candidate_maximum_length))) ||
        throw(DimensionMismatch(
            "portable elastic-retune edge capacities differ"))
    ndrange = max(length(property), edge_capacity)
    initialize = _execution_kernel(
        plan, _elastic_retune_initialize!, ndrange)
    launch!(plan, initialize,
        workspace.candidate_property, property,
        workspace.candidate_strength, payload.strength,
        workspace.candidate_target_length, payload.target_length,
        workspace.candidate_maximum_length, payload.maximum_length,
        workspace.status, workspace.failing_edge, edge_capacity;
        ndrange)
    scope_type = _portable_scope_type(process.scope)
    apply = _execution_kernel(
        plan, _elastic_retune_apply!, ndrange)
    launch!(plan, apply,
        workspace.candidate_property,
        workspace.candidate_strength,
        workspace.candidate_target_length,
        workspace.candidate_maximum_length,
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.active, state.count,
        core.active, core.generations, core.cell_types,
        scope_type, parameters.strength,
        parameters.target_length,
        parameters.maximum_length,
        workspace.status, workspace.failing_edge;
        ndrange)
    commit = _execution_kernel(
        plan, _elastic_retune_commit!, ndrange)
    launch!(plan, commit,
        property, workspace.candidate_property,
        payload.strength, workspace.candidate_strength,
        payload.target_length,
        workspace.candidate_target_length,
        payload.maximum_length,
        workspace.candidate_maximum_length,
        state.publication_epoch, workspace.status,
        edge_capacity; ndrange)
    return state
end

function synchronize_elastic_retune_status!(
        plan::ExecutionPlan,
        workspace::ElasticLinkRetuneWorkspace)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
        record_transfer!(plan, :device_to_host)
    end
    status = only(Adapt.adapt(Array, workspace.status))
    iszero(status) && return workspace
    failing = only(Adapt.adapt(Array, workspace.failing_edge))
    failing == typemax(UInt32) && (failing = UInt32(0))
    throw(ArgumentError(
        "elastic relationship retune failed with status $status at edge $failing"))
end

function _execute_host_process!(
        candidate::CoupledState,
        snapshot::CoupledState,
        potts_candidate::LogicalPottsState,
        potts_snapshot::LogicalPottsState,
        scientific::CompiledScientificState,
        execution::ElasticLinkRetuneExecution,
        target_mcs, stage, interval)
    process = execution.process
    parameters = _elastic_retune_parameters(
        process, interval)
    source = _state_by_name(
        snapshot.relationships,
        process.relationships)
    target = _state_by_name(
        candidate.relationships,
        process.relationships)
    _publish_state!(target, source)
    apply_elastic_link_retune!(
        potts_candidate, target, process, parameters,
        execution.workspace)
    return (process.property,)
end

function _execute_portable_process!(
        integrator::CoupledIntegrator,
        execution::ElasticLinkRetuneExecution,
        target_mcs, stage, interval)
    process = execution.process
    parameters = _elastic_retune_parameters(
        process, interval)
    relationships = _state_by_name(
        integrator.state.relationships,
        process.relationships)
    apply_elastic_link_retune!(
        integrator.potts.plan,
        integrator.potts.state,
        relationships, process, parameters,
        execution.workspace)
    synchronize_elastic_retune_status!(
        integrator.potts.plan,
        execution.workspace)
    return ()
end

function _elastic_retune_parameters(
        process::ElasticLinkRetune,
        interval)
    interval === nothing &&
        return process.parameters
    interval isa typeof(process.parameters) ||
        throw(ArgumentError(
            "elastic retune scheduled value must match the declaration parameter type"))
    return interval
end

"""
Immutable declaration for canonical stale-endpoint relationship compaction.

The declaration carries only identity and the targeted relationship set. Bounded candidate
storage belongs to `RelationshipCleanupExecution`.
"""
