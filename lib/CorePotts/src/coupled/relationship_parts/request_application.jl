function rebuild_accepted_copy_effect(
        transaction::ContactRelationshipTransaction{Name},
        coupled_state::CoupledState) where {Name}
    state = _state_by_name(
        coupled_state.relationships, Name)
    return ContactRelationshipTransaction(
        transaction.component, state)
end

@kernel function _relationship_initialize_transaction!(
        candidate_endpoint_a, candidate_generation_a,
        candidate_endpoint_b, candidate_generation_b,
        candidate_payload, candidate_active, candidate_count,
        endpoint_a, generation_a, endpoint_b, generation_b,
        payload, active, count, status, failing_request)
    index = @index(Global, Linear)
    @inbounds begin
        candidate_endpoint_a[index] = endpoint_a[index]
        candidate_generation_a[index] = generation_a[index]
        candidate_endpoint_b[index] = endpoint_b[index]
        candidate_generation_b[index] = generation_b[index]
        candidate_payload[index] = payload[index]
        candidate_active[index] = active[index]
        if index == 1
            candidate_count[1] = count[1]
            status[1] = UInt32(0)
            failing_request[1] = UInt32(0)
        end
    end
end

@kernel function _relationship_apply_transaction!(
        candidate_endpoint_a, candidate_generation_a,
        candidate_endpoint_b, candidate_generation_b,
        candidate_payload, candidate_active, candidate_count,
        request_kind, request_endpoint_a, request_generation_a,
        request_endpoint_b, request_generation_b, request_payload,
        request_count, cell_active, cell_generations,
        directed, maximum_degree, status, failing_request)
    lane = @index(Global, Linear)
    if lane == 1
        count = Int(@inbounds candidate_count[1])
        prior_a = UInt32(0)
        prior_ga = UInt64(0)
        prior_b = UInt32(0)
        prior_gb = UInt64(0)
        for request_index in 1:Int(@inbounds request_count[1])
            kind = @inbounds request_kind[request_index]
            left = @inbounds request_endpoint_a[request_index]
            left_generation =
                @inbounds request_generation_a[request_index]
            right = @inbounds request_endpoint_b[request_index]
            right_generation =
                @inbounds request_generation_b[request_index]
            if !directed && _relationship_raw_less(
                    right, right_generation, left, left_generation,
                    left, left_generation, right, right_generation)
                left, right = right, left
                left_generation, right_generation =
                    right_generation, left_generation
            end
            code = UInt32(0)
            if left == right && left_generation == right_generation
                code = UInt32(1)
            elseif !_relationship_endpoint_is_current(
                    cell_active, cell_generations, left, left_generation) ||
                    !_relationship_endpoint_is_current(
                        cell_active, cell_generations, right, right_generation)
                code = UInt32(2)
            elseif request_index > 1 &&
                    left == prior_a && left_generation == prior_ga &&
                    right == prior_b && right_generation == prior_gb
                code = UInt32(3)
            else
                edge_index = _relationship_raw_edge_index(
                    candidate_endpoint_a, candidate_generation_a,
                    candidate_endpoint_b, candidate_generation_b,
                    candidate_active, count,
                    left, left_generation, right, right_generation)
                if kind == RELATIONSHIP_REMOVE_REQUEST
                    if edge_index != 0
                        for source in (edge_index + 1):count
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
                elseif kind == RELATIONSHIP_RETUNE_REQUEST
                    if edge_index == 0
                        code = UInt32(4)
                    else
                        @inbounds candidate_payload[edge_index] =
                            request_payload[request_index]
                    end
                elseif kind == RELATIONSHIP_CREATE_REQUEST
                    if edge_index != 0
                        code = UInt32(5)
                    elseif count >= length(candidate_active)
                        code = UInt32(6)
                    elseif _relationship_raw_degree(
                            candidate_endpoint_a, candidate_generation_a,
                            candidate_endpoint_b, candidate_generation_b,
                            candidate_active, count,
                            left, left_generation) >= maximum_degree ||
                            _relationship_raw_degree(
                                candidate_endpoint_a, candidate_generation_a,
                                candidate_endpoint_b, candidate_generation_b,
                                candidate_active, count,
                                right, right_generation) >= maximum_degree
                        code = UInt32(7)
                    else
                        insertion = count + 1
                        for index in 1:count
                            @inbounds if _relationship_raw_less(
                                    left, left_generation,
                                    right, right_generation,
                                    candidate_endpoint_a[index],
                                    candidate_generation_a[index],
                                    candidate_endpoint_b[index],
                                    candidate_generation_b[index])
                                insertion = index
                                break
                            end
                        end
                        for destination in (count + 1):-1:(insertion + 1)
                            _relationship_raw_copy!(
                                candidate_endpoint_a,
                                candidate_generation_a,
                                candidate_endpoint_b,
                                candidate_generation_b,
                                candidate_payload, candidate_active,
                                destination, destination - 1)
                        end
                        @inbounds begin
                            candidate_endpoint_a[insertion] = left
                            candidate_generation_a[insertion] =
                                left_generation
                            candidate_endpoint_b[insertion] = right
                            candidate_generation_b[insertion] =
                                right_generation
                            candidate_payload[insertion] =
                                request_payload[request_index]
                            candidate_active[insertion] = UInt8(1)
                        end
                        count += 1
                    end
                else
                    code = UInt32(8)
                end
            end
            if code != UInt32(0)
                @inbounds begin
                    status[1] = code
                    failing_request[1] = UInt32(request_index)
                end
                break
            end
            prior_a, prior_ga, prior_b, prior_gb =
                left, left_generation, right, right_generation
        end
        @inbounds candidate_count[1] = UInt32(count)
    end
end

@kernel function _relationship_commit_transaction!(
        endpoint_a, generation_a, endpoint_b, generation_b,
        payload, active, count, publication_epoch,
        candidate_endpoint_a, candidate_generation_a,
        candidate_endpoint_b, candidate_generation_b,
        candidate_payload, candidate_active, candidate_count, status)
    index = @index(Global, Linear)
    @inbounds if status[1] == UInt32(0)
        endpoint_a[index] = candidate_endpoint_a[index]
        generation_a[index] = candidate_generation_a[index]
        endpoint_b[index] = candidate_endpoint_b[index]
        generation_b[index] = candidate_generation_b[index]
        payload[index] = candidate_payload[index]
        active[index] = candidate_active[index]
        if index == 1
            count[1] = candidate_count[1]
            publication_epoch[1] += UInt64(1)
        end
    end
end

function apply_relationship_requests!(
        plan::ExecutionPlan, scientific::CompiledScientificState,
        state::RelationshipState,
        workspace::RelationshipTransactionWorkspace)
    execution = scientific_execution(scientific)
    core = execution.core
    arrays = (
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, state.active, state.count,
        state.publication_epoch,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count,
        workspace.request_kind,
        workspace.request_endpoint_a,
        workspace.request_generation_a,
        workspace.request_endpoint_b,
        workspace.request_generation_b,
        workspace.request_payload,
        workspace.request_count, workspace.status,
        workspace.failing_request,
        core.active, core.generations)
    all(array -> isbitstype(eltype(array)) &&
            isequal(KernelAbstractions.get_backend(array), plan.backend),
        arrays) || throw(ArgumentError(
        "portable relationship storage has a backend mismatch"))
    capacity = length(state.active)
    all(==(capacity), map(length, (
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active))) ||
        throw(DimensionMismatch(
            "portable relationship capacities differ"))
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
    apply = _execution_kernel(
        plan, _relationship_apply_transaction!, 1)
    launch!(plan, apply,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count,
        workspace.request_kind,
        workspace.request_endpoint_a,
        workspace.request_generation_a,
        workspace.request_endpoint_b,
        workspace.request_generation_b,
        workspace.request_payload,
        workspace.request_count, core.active, core.generations,
        state.declaration.directed,
        Int(state.declaration.maximum_degree),
        workspace.status, workspace.failing_request;
        ndrange = 1)
    _launch_relationship_commit!(plan, state, workspace, capacity)
    return state
end

function _launch_relationship_commit!(plan, state, workspace, capacity)
    commit = _execution_kernel(plan, _relationship_commit_transaction!, capacity)
    launch!(plan, commit,
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, state.active, state.count,
        state.publication_epoch,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count, workspace.status;
        ndrange = capacity)
    return nothing
end

function synchronize_relationship_status!(
        plan::ExecutionPlan,
        workspace::RelationshipTransactionWorkspace)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
        record_transfer!(plan, :device_to_host)
    end
    status = only(Adapt.adapt(Array, workspace.status))
    iszero(status) && return workspace
    failing = only(Adapt.adapt(Array, workspace.failing_request))
    throw(ArgumentError(
        "relationship transaction failed with status $status at request $failing"))
end
