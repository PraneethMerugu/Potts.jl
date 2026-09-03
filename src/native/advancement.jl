function _advance_native_candidates(
        integrator,
        descriptor_state,
        completed_mcs::Int,
        receipt,
        snapshot,
    )
    components = scheduled_native_components(integrator.prob.system)
    candidates = copy(integrator.native_states)
    all_updates = Any[]
    component_transactions = Any[]
    # `descriptor_state` is one staged Core snapshot. This loop only reads it;
    # all island outputs are accumulated and published after every solve. This
    # makes due islands simultaneous/Jacobi and independent of tuple order.
    for index in eachindex(components)
        component = components[index]
        declaration = getfield(component, :declaration)
        runtime_state = integrator.native_states[index]
        if runtime_state isa NativeCellStatePool
            _prepare_native_creation_states!(
                runtime_state,
                component,
                integrator.native_profiles[index],
                integrator.plan,
                descriptor_state,
                receipt,
                completed_mcs,
                integrator.prob,
            )
            component_transaction =
                CorePotts.BackendSPI.stage_lifecycle_receipt!(
                    runtime_state.storage, receipt
                )
            push!(component_transactions, component_transaction)
            candidate_bank = CorePotts.BackendSPI.component_transaction_state(
                component_transaction
            )
            if native_due(declaration, completed_mcs)
                target = native_time_at(declaration, completed_mcs)
                profile = integrator.native_profiles[index]
                live_slots = findall(kind -> kind > 0, snapshot.cell_kinds)
                if profile.execution isa SerialNativeExecution
                    for slot in live_slots
                        state = native_cell_state(
                            runtime_state.policy, candidate_bank, slot
                        )
                        candidate = _advance_native_logical_state(
                            component,
                            state,
                            profile,
                            _native_input_pairs(
                                integrator.plan, descriptor_state, component; slot
                            ),
                            target,
                        )
                        _write_native_cell_state!(candidate_bank, slot, candidate)
                    end
                elseif profile.execution isa BatchedNativeExecution
                    mode = profile.execution
                    for first_lane in 1:mode.width:length(live_slots)
                        last_lane = min(
                            first_lane + mode.width - 1, length(live_slots)
                        )
                        slots = live_slots[first_lane:last_lane]
                        lanes = [(
                            slot = Int(slot),
                            state = native_cell_state(
                                runtime_state.policy, candidate_bank, slot
                            ),
                            inputs = _native_input_pairs(
                                integrator.plan,
                                descriptor_state,
                                component;
                                slot,
                            ),
                        ) for slot in slots]
                        results = _advance_native_cell_batch(
                            component, lanes, profile, target
                        )
                        length(results) == length(lanes) || throw(
                            NativeCapabilityError(
                                path,
                                :native_execution_mode,
                                "batched native execution returned the wrong lane count",
                            )
                        )
                        for (lane, candidate) in zip(lanes, results)
                            candidate isa NativeLogicalState || throw(
                                NativeCapabilityError(
                                    path,
                                    :logical_state,
                                    "batched native execution returned an invalid lane state",
                                )
                            )
                            _write_native_cell_state!(
                                candidate_bank, lane.slot, candidate
                            )
                        end
                    end
                else
                    mode = profile.execution
                    mode isa MetalNativeExecution || error(
                        "validated native execution mode reached no runtime branch"
                    )
                    for first_lane in 1:mode.width:length(live_slots)
                        last_lane = min(
                            first_lane + mode.width - 1, length(live_slots)
                        )
                        slots = live_slots[first_lane:last_lane]
                        lanes = [(
                            slot = Int(slot),
                            state = native_cell_state(
                                runtime_state.policy, candidate_bank, slot
                            ),
                            inputs = _native_input_pairs(
                                integrator.plan,
                                descriptor_state,
                                component;
                                slot,
                            ),
                        ) for slot in slots]
                        results = _advance_native_cell_batch(
                            component, lanes, profile, target
                        )
                        length(results) == length(lanes) || throw(
                            NativeCapabilityError(
                                path,
                                :native_execution_mode,
                                "Metal native execution returned the wrong lane count",
                            )
                        )
                        for (lane, candidate) in zip(lanes, results)
                            _write_native_cell_state!(
                                candidate_bank, lane.slot, candidate
                            )
                        end
                    end
                end
            end
            for slot in eachindex(snapshot.cell_kinds)
                snapshot.cell_kinds[slot] > 0 || continue
                state = native_cell_state(
                    runtime_state.policy, candidate_bank, slot
                )
                append!(all_updates,
                    _native_output_updates(component, state; slot))
            end
        elseif native_due(declaration, completed_mcs)
            inputs = _native_input_pairs(
                integrator.plan, descriptor_state, component
            )
            target = native_time_at(declaration, completed_mcs)
            candidate = _advance_native_logical_state(
                component, runtime_state, integrator.native_profiles[index],
                inputs, target,
            )
            candidates[index] = candidate
        end
        runtime_state isa NativeCellStatePool || append!(
            all_updates, _native_output_updates(component, candidates[index])
        )
    end
    return candidates, all_updates, component_transactions
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
        problem,
    )
    action = pool.policy.creation
    action isa _NativePreparedCreationAction || return pool
    fill!(action.states, nothing)
    point = only(
        point for point in _problem_initial_state(problem).native
        if point.path == pool.path
    )
    declaration = getfield(component, :declaration)
    initial_time = native_time_at(declaration, completed_mcs - 1)
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
