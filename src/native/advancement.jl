function _advance_native_cell_bank!(integrator, index, bank, descriptor_state,
        completed_mcs, snapshot)
    component = scheduled_native_components(integrator.prob.system)[index]
    declaration = getfield(component, :declaration)
    native_due(declaration, completed_mcs) || return bank
    runtime_state = integrator.native_states[index]
    profile = integrator.native_profiles[index]
    target = native_time_at(declaration, completed_mcs)
    slots = _native_due_cell_slots(
        integrator.plan, component, snapshot.cell_kinds
    )
    if profile.execution isa SerialNativeExecution
        for slot in slots
            state = _native_due_cell_state(runtime_state.policy, bank, slot,
                declaration, completed_mcs)
            candidate = _advance_native_logical_state(component, state, profile,
                _native_input_pairs(integrator.plan, descriptor_state, component; slot),
                target)
            _write_native_cell_state!(bank, slot, candidate)
        end
    else
        mode = profile.execution
        mode isa Union{BatchedNativeExecution, MetalNativeExecution} ||
            error("validated native execution mode reached no runtime branch")
        # A newly created or re-entering cell may have a shorter first
        # interval. All lanes of one native solve must share its start time.
        groups = Dict{typeof(target), Vector{Any}}()
        for slot in slots
            state = _native_due_cell_state(runtime_state.policy, bank, slot,
                declaration, completed_mcs)
            lane = (
                slot = Int(slot), state,
                inputs = _native_input_pairs(
                    integrator.plan, descriptor_state, component; slot),
            )
            push!(get!(groups, state.t, Any[]), lane)
        end
        for start_time in sort!(collect(keys(groups)))
            group = groups[start_time]
            for first_lane in 1:mode.width:length(group)
                last_lane = min(first_lane + mode.width - 1, length(group))
                lanes = group[first_lane:last_lane]
                results = mode isa BatchedNativeExecution ?
                    _advance_native_cell_batch(component, lanes, profile,
                        target; cache = integrator.native_solver_cache, index) :
                    _advance_native_cell_batch(component, lanes, profile, target)
                length(results) == length(lanes) || throw(NativeCapabilityError(
                    native_component_path(component), :native_execution_mode,
                    "native batch returned the wrong lane count"))
                for (lane, candidate) in zip(lanes, results)
                    candidate isa NativeLogicalState || throw(NativeCapabilityError(
                        native_component_path(component), :logical_state,
                        "native batch returned an invalid lane state"))
                    _write_native_cell_state!(bank, lane.slot, candidate)
                end
            end
        end
    end
    return bank
end

function _native_due_cell_state(policy, bank, slot, declaration, completed_mcs)
    state = native_cell_state(policy, bank, slot)
    # An explicit transition action owns its native clock. Only Preserve()
    # needs a cadence-boundary rebase after time spent outside the domain.
    policy.transition isa _NativePreserveAction || return state
    start_mcs = completed_mcs - native_cadence_stride(declaration)
    start_time = native_time_at(declaration, start_mcs)
    # A cell re-entering a filtered domain has no component evolution while
    # outside it; its next due interval begins at the current cadence boundary.
    state.t < start_time || return state
    return NativeLogicalState(state.path, state.u, state.p, state.du,
        start_time, state.retcode)
end

function _native_cell_output_updates(plan, component, runtime_state, bank, kinds)
    any(endpoint -> endpoint.port isa Union{NativeOutput, NativeFieldOutput},
        native_coupling_endpoints(component)) || return Any[]
    slots = _native_due_cell_slots(plan, component, kinds)
    updates = Any[]
    for slot in slots
        state = native_cell_state(runtime_state.policy, bank, slot)
        append!(updates, _native_output_updates(component, state; slot))
    end
    return updates
end

function _advance_native_before_lifecycle(integrator, descriptor_state,
        completed_mcs::Int, snapshot)
    components = scheduled_native_components(integrator.prob.system)
    staged = Any[nothing for _ in components]
    updates = Any[]
    # Each component reads the same pre-lifecycle descriptor snapshot.
    for index in eachindex(components)
        component = components[index]
        declaration = getfield(component, :declaration)
        getfield(declaration, :phase) isa BeforeLifecycle || continue
        runtime_state = integrator.native_states[index]
        if runtime_state isa NativeCellStatePool
            bank = CorePotts.BackendSPI.component_state_snapshot(
                runtime_state.storage)
            _advance_native_cell_bank!(integrator, index, bank, descriptor_state,
                completed_mcs, snapshot)
            staged[index] = bank
            if native_due(declaration, completed_mcs)
                append!(updates, _native_cell_output_updates(integrator.plan,
                    component, runtime_state, bank, snapshot.cell_kinds))
            end
        else
            candidate = native_due(declaration, completed_mcs) ?
                _advance_native_logical_state(component, runtime_state,
                    integrator.native_profiles[index],
                    _native_input_pairs(integrator.plan, descriptor_state, component),
                    native_time_at(declaration, completed_mcs)) : runtime_state
            staged[index] = candidate
            native_due(declaration, completed_mcs) &&
                append!(updates, _native_output_updates(component, candidate))
        end
    end
    return staged, updates
end

function _advance_native_candidates(integrator, descriptor_state,
        completed_mcs::Int, receipt, snapshot; staged_pre = nothing)
    components = scheduled_native_components(integrator.prob.system)
    candidates = copy(integrator.native_states)
    all_updates = Any[]
    component_transactions = Any[]
    try
        for index in eachindex(components)
            component = components[index]
            declaration = getfield(component, :declaration)
            pre = getfield(declaration, :phase) isa BeforeLifecycle
            runtime_state = integrator.native_states[index]
            if runtime_state isa NativeCellStatePool
                _prepare_native_creation_states!(runtime_state, component,
                    integrator.native_profiles[index], integrator.plan,
                    descriptor_state, receipt, completed_mcs, integrator.prob;
                    initial_mcs = (pre || !native_due(declaration, completed_mcs)) ?
                        completed_mcs : completed_mcs - 1)
                source_state = pre && staged_pre !== nothing ? staged_pre[index] : nothing
                component_transaction = CorePotts.BackendSPI.stage_lifecycle_receipt!(
                    runtime_state.storage, receipt; source_state)
                push!(component_transactions, component_transaction)
                bank = CorePotts.BackendSPI.component_transaction_state(
                    component_transaction)
                _rebase_native_domain_entries!(integrator.plan, component,
                    runtime_state.policy,
                    bank, receipt, completed_mcs)
                if !pre
                    _advance_native_cell_bank!(integrator, index, bank,
                        descriptor_state, completed_mcs, snapshot)
                    if native_due(declaration, completed_mcs)
                        append!(all_updates, _native_cell_output_updates(integrator.plan,
                            component, runtime_state, bank, snapshot.cell_kinds))
                    end
                end
            elseif pre
                staged_pre === nothing || (candidates[index] = staged_pre[index])
            else
                if native_due(declaration, completed_mcs)
                    candidates[index] = _advance_native_logical_state(component,
                        runtime_state, integrator.native_profiles[index],
                        _native_input_pairs(integrator.plan, descriptor_state, component),
                        native_time_at(declaration, completed_mcs))
                end
                native_due(declaration, completed_mcs) &&
                    append!(all_updates, _native_output_updates(component, candidates[index]))
            end
        end
    catch
        for component_transaction in component_transactions
            try
                CorePotts.BackendSPI.abort_component_state_transaction!(
                    component_transaction)
            catch
            end
        end
        rethrow()
    end
    return candidates, all_updates, component_transactions
end

function _rebase_native_domain_entries!(plan, component, policy, bank, receipt,
        completed_mcs)
    declaration = getfield(component, :declaration)
    kind_index = _native_domain_kind_index(plan, component)
    kind_index === nothing && return bank
    # ResetTo/Transform may intentionally assign the logical native time.
    # Rebase only the implicit Preserve action.
    policy.transition isa _NativePreserveAction || return bank
    phase = getfield(declaration, :phase)
    phase_start_mcs = phase isa BeforeLifecycle ||
        !native_due(declaration, completed_mcs) ?
        completed_mcs : completed_mcs - 1
    t = native_time_at(declaration, phase_start_mcs)
    for event in CorePotts.lifecycle_events(receipt)
        if event isa CorePotts.TransitionLifecycleEvent &&
                event.before.kind != kind_index && event.after.kind == kind_index
            bank.t[Int(event.after.slot)] = t
        end
    end
    return bank
end

function _native_due_cell_slots(plan, component, kinds)
    index = _native_domain_kind_index(plan, component)
    index === nothing && return findall(kind -> kind > 0, kinds)
    return findall(kind -> kind == index, kinds)
end

function _native_domain_kind_index(plan, component)
    identity = getfield(component, :domain_identity)
    identity === nothing && return nothing
    resource_identity = _qualified_resource_identity(identity)
    index = findfirst(entry -> entry.resource_identity == resource_identity,
        plan.kind_manifest)
    index === nothing && throw(ArgumentError(
        "native cell domain $(repr(identity)) has no compiled kind"
    ))
    return index
end

function _advance_native_logical_state(
        component, state, profile, inputs, target
    )
    candidate = try
        advance_native_component(component, state, profile, inputs, target)
    catch error
        error isa AbstractNativeRuntimeError && rethrow()
        throw(NativeExecutionError(
            native_component_path(component), :solve, error
        ))
    end
    candidate isa NativeLogicalState || throw(NativeCapabilityError(
        native_component_path(component), :logical_state,
        "native advance did not return NativeLogicalState",
    ))
    return candidate
end

function _prepare_native_creation_states!(
        pool::NativeCellStatePool,
        component,
        profile,
        plan,
        descriptor_state,
        receipt,
        completed_mcs,
        problem;
        initial_mcs = completed_mcs - 1,
    )
    action = pool.policy.creation
    action isa _NativePreparedCreationAction || return pool
    fill!(action.states, nothing)
    point = only(
        point for point in _problem_initial_state(problem).native
        if point.path == pool.path
    )
    declaration = getfield(component, :declaration)
    initial_time = native_time_at(declaration, initial_mcs)
    for event in CorePotts.lifecycle_events(receipt)
        event isa CorePotts.CreateLifecycleEvent || continue
        slot = Int(event.after.slot)
        action.states[slot] = _initialize_native_logical_state(
            component,
            point,
            profile,
            _native_input_pairs(plan, descriptor_state, component; slot),
            initial_time,
        )
    end
    return pool
end

function _copy_native_logical_state(state::NativeLogicalState)
    return NativeLogicalState(
        state.path,
        state.u,
        state.p,
        state.du,
        state.t,
        state.retcode,
    )
end

_copy_native_logical_state(state::NativeCellStatePool) =
    native_cell_state_snapshot(state)

function _copy_native_logical_state(state::NativeCellStateSnapshot)
    return NativeCellStateSnapshot(
        state.path,
        copy(state.active),
        copy(state.generations),
        copy(state.kinds),
        deepcopy(state.identities),
        Union{Nothing, NativeLogicalState}[
            value === nothing ? nothing : _copy_native_logical_state(value)
            for value in state.states
        ],
        state.capacity,
        state.completed_mcs,
        state.last_transaction_identity,
    )
end

function _native_state_by_path(states, path)
    normalized = _qualified_native_path(path, "native_state")
    matches = filter(state -> _native_runtime_path(state) == normalized, states)
    length(matches) == 1 || throw(ArgumentError(
        "native component path `$(_native_path_string(normalized))` is not present"
    ))
    return only(matches)
end

function _native_component_by_path(system::PottsSystem, path)
    normalized = _qualified_native_path(path, "native_state")
    matches = filter(
        component -> native_component_path(component) == normalized,
        scheduled_native_components(system),
    )
    length(matches) == 1 || throw(ArgumentError(
        "native component path `$(_native_path_string(normalized))` is not present"
    ))
    return only(matches)
end
