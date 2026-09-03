function _native_state_entry(plan::_PottsExecutionPlan, endpoint)
    endpoint.potts_kind in (:ModelState, :CellState, :FieldState) || throw(NativeCapabilityError(
        endpoint.component_path,
        :typed_io,
        "only ModelState, CellState, and checked field-output endpoints are admitted; got $(endpoint.potts_kind)",
    ))
    identity = _qualified_resource_identity(potts_endpoint(endpoint))
    matches = filter(entry -> entry.identity == identity, plan.reports.states)
    length(matches) == 1 || throw(NativeCapabilityError(
        endpoint.component_path,
        :typed_io,
        "resolved ModelState endpoint does not map to one runtime storage handle",
    ))
    entry = only(matches)
    expected_storage = endpoint.potts_kind === :ModelState ? :model :
        endpoint.potts_kind === :CellState ? :cell : :site
    entry.storage === expected_storage || throw(NativeCapabilityError(
        endpoint.component_path,
        :typed_io,
        "resolved endpoint is not $expected_storage storage",
    ))
    return entry
end

function _read_native_endpoint(plan, descriptor_state, endpoint; slot = nothing)
    entry = _native_state_entry(plan, endpoint)
    block = CorePotts.CompilerSPI.state_block(descriptor_state, entry.handle)
    if endpoint.potts_kind === :FieldState
        endpoint.port isa NativeFieldOutput || throw(NativeCapabilityError(
            endpoint.component_path, :typed_io,
            "FieldState is output-only and requires NativeFieldOutput",
        ))
        size(block.values) == getfield(endpoint.port, :shape) ||
            throw(NativeCapabilityError(
                endpoint.component_path, :field_grid,
                "native field grid shape does not equal the Potts lattice shape",
            ))
        return reshape(copy(block.values), getfield(endpoint.port, :shape))
    end
    index = if endpoint.potts_kind === :ModelState
        length(block.values) == 1 || throw(NativeCapabilityError(
            endpoint.component_path, :typed_io,
            "ModelState coupling requires one scalar value",
        ))
        firstindex(block.values)
    else
        slot isa Integer || throw(NativeCapabilityError(
            endpoint.component_path, :typed_io,
            "CellState coupling requires a generation-validated cell slot",
        ))
        checkbounds(block.values, slot)
        Int(slot)
    end
    T = native_value_type(endpoint)
    value = try
        convert(T, block.values[index])
    catch error
        throw(NativeExecutionError(endpoint.component_path, :input_conversion, error))
    end
    value isa AbstractFloat && !isfinite(value) && throw(NativeCapabilityError(
        endpoint.component_path, :typed_io, "native input is nonfinite"
    ))
    return value
end

function _native_input_pairs(plan, descriptor_state, component; slot = nothing)
    return Tuple(
        native_variable(endpoint) =>
            _read_native_endpoint(plan, descriptor_state, endpoint; slot)
        for endpoint in native_coupling_endpoints(component)
        if endpoint.port isa NativeInput
    )
end

function _native_output_updates(
        component, state::NativeLogicalState; slot = nothing
    )
    return Tuple(
        let value = try
                if endpoint.port isa NativeFieldOutput
                    values = map(
                        variable -> native_component_value(component, state, variable),
                        native_variables(endpoint.port),
                    )
                    reshape(collect(values), getfield(endpoint.port, :shape))
                else
                    native_component_value(component, state, native_variable(endpoint))
                end
            catch error
                error isa AbstractNativeRuntimeError && rethrow()
                throw(NativeExecutionError(
                    endpoint.component_path, :output_evaluation, error
                ))
            end
            T = native_value_type(endpoint)
            converted = try
                value isa AbstractArray ? T.(value) : convert(T, value)
            catch error
                throw(NativeExecutionError(
                    endpoint.component_path, :output_conversion, error
                ))
            end
            ((converted isa AbstractFloat && !isfinite(converted)) ||
                    (converted isa AbstractArray && !all(isfinite, converted))) &&
                throw(NativeCapabilityError(
                    endpoint.component_path, :typed_io,
                    "native output is nonfinite",
                ))
            (endpoint = endpoint, slot = slot, value = converted)
        end
        for endpoint in native_coupling_endpoints(component)
        if endpoint.port isa Union{NativeOutput, NativeFieldOutput}
    )
end

function _publish_native_outputs!(plan, descriptor_state, updates)
    isempty(updates) && return descriptor_state
    descriptor_state === nothing && throw(NativeCapabilityError(
        (:runtime, :native_components),
        :typed_io,
        "native coupling endpoints require a Core descriptor-state layout",
    ))
    for update in updates
        endpoint = update.endpoint
        value = update.value
        entry = _native_state_entry(plan, endpoint)
        block = CorePotts.CompilerSPI.state_block(descriptor_state, entry.handle)
        if endpoint.port isa NativeFieldOutput
            size(block.values) == size(value) || throw(NativeCapabilityError(
                endpoint.component_path, :field_grid,
                "native field output shape does not equal Potts field storage",
            ))
            converted = try
                eltype(block.values).(value)
            catch error
                throw(NativeExecutionError(
                    endpoint.component_path, :potts_output_conversion, error
                ))
            end
            all(isfinite, converted) || throw(NativeCapabilityError(
                endpoint.component_path, :typed_io,
                "converted Potts FieldState output is nonfinite",
            ))
            copyto!(block.values, converted)
            continue
        end
        converted = try
            convert(eltype(block.values), value)
        catch error
            throw(NativeExecutionError(
                endpoint.component_path, :potts_output_conversion, error
            ))
        end
        converted isa AbstractFloat && !isfinite(converted) &&
            throw(NativeCapabilityError(
                endpoint.component_path, :typed_io,
                "converted Potts ModelState output is nonfinite",
            ))
        index = if endpoint.potts_kind === :ModelState
            firstindex(block.values)
        else
            update.slot isa Integer || throw(NativeCapabilityError(
                endpoint.component_path, :typed_io,
                "CellState output publication requires a cell slot",
            ))
            checkbounds(block.values, update.slot)
            Int(update.slot)
        end
        block.values[index] = converted
    end
    return descriptor_state
end

function _validate_native_outputs(
    plan, descriptor_state, components, states
    )
    for (component, state) in zip(components, states)
        updates = if state isa NativeLogicalState
            _native_output_updates(component, state)
        elseif state isa NativeCellStatePool
            snapshot = native_cell_state_snapshot(state)
            Tuple(
                update
                for (slot, value) in enumerate(snapshot.states)
                if value !== nothing
                for update in _native_output_updates(component, value; slot)
            )
        else
            throw(NativeCapabilityError(
                native_component_path(component),
                :checkpoint_consistency,
                "checkpoint restoration produced an unknown native state representation",
            ))
        end
        for update in updates
            actual = _read_native_endpoint(
                plan, descriptor_state, update.endpoint; slot = update.slot
            )
            isequal(actual, update.value) || throw(NativeCapabilityError(
                update.endpoint.component_path,
                :checkpoint_consistency,
                "published Potts state does not match its native output",
            ))
        end
    end
    return nothing
end

