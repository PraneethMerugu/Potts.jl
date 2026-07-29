struct RelationshipCleanup{Relationships}
    name::Symbol
    version::VersionNumber
end

function RelationshipCleanup(
        name::Symbol,
        relationships::Union{
            Symbol, RelationshipSet};
        version::VersionNumber =
            DYNAMIC_STATE_CONTRACT_VERSION)
    isempty(String(name)) && throw(ArgumentError(
        "relationship-cleanup identity must not be empty"))
    target = relationships isa Symbol ?
        relationships : relationships.name
    return RelationshipCleanup{target}(
        name, version)
end

component_identity(process::RelationshipCleanup) =
    ComponentIdentity(
        process.name, process.version,
        :relationship_cleanup)
component_semantic_data(
        ::RelationshipCleanup{Relationships}) where {
        Relationships} = (
    relationships = Relationships,
    policy = :remove_stale_endpoint_generation,
    order = :canonical_compaction,
)
process_reads(
        ::RelationshipCleanup{
            Relationships}) where {
        Relationships} = (
    (:relationships, Relationships),
    (:ownership, :cells),
)
process_writes(
        ::RelationshipCleanup{
            Relationships}) where {
        Relationships} = (
    (:relationships, Relationships),)

struct RelationshipCleanupExecution{
        P <: RelationshipCleanup,
        W <: RelationshipTransactionWorkspace}
    process::P
    workspace::W
end

function RelationshipCleanupExecution(
        process::RelationshipCleanup{
            Relationships},
        state::RelationshipState) where {
        Relationships}
    state.declaration.name === Relationships ||
        throw(ArgumentError(
            "relationship-cleanup declaration and state identities differ"))
    return RelationshipCleanupExecution(
        process,
        RelationshipTransactionWorkspace(
            state; request_capacity = 1))
end

function realize_coupled_process(
        process::RelationshipCleanup{
            Relationships},
        state::CoupledState,
        scientific::CompiledScientificState) where {
            Relationships}
    relationships = _state_by_name(
        state.relationships, Relationships)
    return RelationshipCleanupExecution(
        process, relationships)
end

function Adapt.adapt_structure(
        to,
        execution::RelationshipCleanupExecution)
    return RelationshipCleanupExecution(
        Adapt.adapt(to, execution.process),
        Adapt.adapt(to, execution.workspace))
end

component_identity(
    execution::RelationshipCleanupExecution) =
    component_identity(execution.process)
component_semantic_data(
    execution::RelationshipCleanupExecution) =
    component_semantic_data(execution.process)
process_reads(
    execution::RelationshipCleanupExecution) =
    process_reads(execution.process)
process_writes(
    execution::RelationshipCleanupExecution) =
    process_writes(execution.process)
canonical_process_law(
    execution::RelationshipCleanupExecution) =
    execution.process

function cleanup_relationships!(
        state::RelationshipState,
        logical::LogicalPottsState)
    state.declaration.endpoint_lifecycle isa
        RemoveIncidentEdges ||
        throw(ArgumentError(
            "relationship cleanup requires RemoveIncidentEdges"))
    count = _relationship_count(state)
    index = 1
    while index <= count
        left = @inbounds state.endpoint_a[index]
        left_generation =
            @inbounds state.generation_a[index]
        right = @inbounds state.endpoint_b[index]
        right_generation =
            @inbounds state.generation_b[index]
        current =
            is_active(logical, CellID(left)) &&
            generation(logical, CellID(left)) ==
                CellGeneration(left_generation) &&
            is_active(logical, CellID(right)) &&
            generation(logical, CellID(right)) ==
                CellGeneration(right_generation)
        if current
            index += 1
            continue
        end
        for source in (index + 1):count
            _relationship_raw_copy!(
                state.endpoint_a,
                state.generation_a,
                state.endpoint_b,
                state.generation_b,
                state.payload, state.active,
                source - 1, source)
        end
        @inbounds state.active[count] = UInt8(0)
        count -= 1
    end
    state.count[1] = UInt32(count)
    state.publication_epoch[1] += UInt64(1)
    return state
end

function _execute_host_process!(
        candidate::CoupledState,
        snapshot::CoupledState,
        potts_candidate::LogicalPottsState,
        potts_snapshot::LogicalPottsState,
        scientific::CompiledScientificState,
        execution::RelationshipCleanupExecution,
        target_mcs, stage, interval)
    process = execution.process
    relationships =
        component_semantic_data(process).relationships
    source = _state_by_name(
        snapshot.relationships, relationships)
    target = _state_by_name(
        candidate.relationships, relationships)
    _publish_state!(target, source)
    cleanup_relationships!(
        target, potts_snapshot)
    return ()
end

function _execute_portable_process!(
        integrator::CoupledIntegrator,
        execution::RelationshipCleanupExecution,
        target_mcs, stage, interval)
    process = execution.process
    relationships =
        component_semantic_data(process).relationships
    state = _state_by_name(
        integrator.state.relationships,
        relationships)
    cleanup_relationships!(
        integrator.potts.plan,
        integrator.potts.state, state,
        execution.workspace)
    synchronize_relationship_status!(
        integrator.potts.plan,
        execution.workspace)
    return ()
end

@kernel function _relationship_cleanup_transaction!(
        candidate_endpoint_a, candidate_generation_a,
        candidate_endpoint_b, candidate_generation_b,
        candidate_payload, candidate_active, candidate_count,
        cell_active, cell_generations)
    lane = @index(Global, Linear)
    if lane == 1
        count = Int(@inbounds candidate_count[1])
        index = 1
        while index <= count
            left = @inbounds candidate_endpoint_a[index]
            left_generation =
                @inbounds candidate_generation_a[index]
            right = @inbounds candidate_endpoint_b[index]
            right_generation =
                @inbounds candidate_generation_b[index]
            current = _relationship_endpoint_is_current(
                cell_active, cell_generations,
                left, left_generation) &&
                _relationship_endpoint_is_current(
                    cell_active, cell_generations,
                    right, right_generation)
            if current
                index += 1
            else
                for source in (index + 1):count
                    _relationship_raw_copy!(
                        candidate_endpoint_a,
                        candidate_generation_a,
                        candidate_endpoint_b,
                        candidate_generation_b,
                        candidate_payload, candidate_active,
                        source - 1, source)
                end
                @inbounds candidate_active[count] = UInt8(0)
                count -= 1
            end
        end
        @inbounds candidate_count[1] = UInt32(count)
    end
end

function cleanup_relationships!(
        plan::ExecutionPlan,
        scientific::CompiledScientificState,
        state::RelationshipState,
        workspace::RelationshipTransactionWorkspace)
    state.declaration.endpoint_lifecycle isa RemoveIncidentEdges ||
        throw(ArgumentError(
            "portable relationship cleanup requires RemoveIncidentEdges"))
    execution = scientific_execution(scientific)
    core = execution.core
    capacity = length(state.active)
    initialize = _execution_kernel(
        plan, _relationship_initialize_transaction!, capacity)
    launch!(plan, initialize,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count,
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, state.active, state.count,
        workspace.status, workspace.failing_request;
        ndrange = capacity)
    cleanup = _execution_kernel(
        plan, _relationship_cleanup_transaction!, 1)
    launch!(plan, cleanup,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count,
        core.active, core.generations;
        ndrange = 1)
    _launch_relationship_commit!(plan, state, workspace, capacity)
    return state
end

"""Atomic relationship transaction planner over one common graph/cell snapshot."""
