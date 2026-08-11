function _validate_value(slot::_ValueSlot{T}, value, name) where {T}
    typeof(value) === T || throw(LocalWorkValidationError(
        "submission value $name has type $(typeof(value)); expected $T"
    ))
    slot.bounds === nothing || value in slot.bounds ||
        throw(LocalWorkValidationError(
            "submission value $name is outside its prepared bounds"
        ))
    return nothing
end

function _validate_storage(slot::_StorageSlot{T, N}, value, name) where {T, N}
    typeof(value) === slot.array_type || throw(LocalWorkValidationError(
        "submission storage $name has the wrong concrete array type"
    ))
    eltype(value) === T || throw(LocalWorkValidationError(
        "submission storage $name has the wrong element type"
    ))
    ndims(value) == N || throw(LocalWorkValidationError(
        "submission storage $name has the wrong dimensionality"
    ))
    size(value) == slot.size || throw(LocalWorkValidationError(
        "submission storage $name has the wrong shape"
    ))
    strides(value) == slot.strides || throw(LocalWorkValidationError(
        "submission storage $name has the wrong layout"
    ))
    backend = KernelAbstractions.get_backend(value)
    typeof(backend) === slot.backend_type ||
        throw(LocalWorkValidationError(
            "submission storage $name belongs to a different backend"
        ))
    (backend isa KernelAbstractions.CPU ||
        invoke(_array_device_identity, Tuple{Any}, value) ==
            slot.device_identity) ||
        throw(LocalWorkValidationError(
            "submission storage $name belongs to a different device/context"
        ))
    return nothing
end

@generated function _canonical_submission(
        schema::S, submission::Q
    ) where {S <: NamedTuple, Q <: NamedTuple}
    schema_names = S.parameters[1]
    submission_names = Q.parameters[1]
    length(schema_names) == length(submission_names) &&
        Set(schema_names) == Set(submission_names) || return :(
        throw(LocalWorkValidationError(
            "submission names do not exactly match the prepared schema"
        ))
    )
    slot_types = S.parameters[2].parameters
    submission_types = Q.parameters[2].parameters
    value_types = Dict(
        name => submission_types[index]
        for (index, name) in pairs(submission_names)
    )
    validations = Expr[]
    values = Expr[]
    for (index, name) in pairs(schema_names)
        slot_type = slot_types[index]
        value_type = value_types[name]
        slot = :(getproperty(schema, $(QuoteNode(name))))
        value = :(getproperty(submission, $(QuoteNode(name))))
        push!(values, value)
        if slot_type <: _ValueSlot
            expected_type = slot_type.parameters[1]
            push!(validations, quote
                typeof($value) === $expected_type || throw(
                    LocalWorkValidationError(
                        $("submission value $name has the wrong type")
                    )
                )
                $slot.bounds === nothing || $value in $slot.bounds || throw(
                    LocalWorkValidationError(
                        $("submission value $name is outside its prepared bounds")
                    )
                )
            end)
        elseif slot_type <: _StorageSlot
            expected_type = slot_type.parameters[1]
            expected_dimensions = slot_type.parameters[2]
            push!(validations, quote
                typeof($value) === $slot.array_type || throw(
                    LocalWorkValidationError(
                        $("submission storage $name has the wrong concrete array type")
                    )
                )
                eltype($value) === $expected_type || throw(
                    LocalWorkValidationError(
                        $("submission storage $name has the wrong element type")
                    )
                )
                ndims($value) == $expected_dimensions || throw(
                    LocalWorkValidationError(
                        $("submission storage $name has the wrong dimensionality")
                    )
                )
                size($value) == $slot.size || throw(
                    LocalWorkValidationError(
                        $("submission storage $name has the wrong shape")
                    )
                )
                strides($value) == $slot.strides || throw(
                    LocalWorkValidationError(
                        $("submission storage $name has the wrong layout")
                    )
                )
                local backend = KernelAbstractions.get_backend($value)
                typeof(backend) === $slot.backend_type || throw(
                    LocalWorkValidationError(
                        $("submission storage $name belongs to a different backend")
                    )
                )
                (backend isa KernelAbstractions.CPU || invoke(
                    _array_device_identity, Tuple{Any}, $value
                ) == $slot.device_identity) || throw(
                    LocalWorkValidationError(
                        $("submission storage $name belongs to a different device/context")
                    )
                )
            end)
        else
            return :(
                throw(LocalWorkValidationError(
                    $("submission slot $name is not centrally recognized")
                ))
            )
        end
    end
    values_tuple = Expr(:tuple, values...)
    return quote
        $(validations...)
        return NamedTuple{$schema_names}($values_tuple)
    end
end

function _all_bindings(prepared::PreparedWork, submission::NamedTuple)
    dynamic = invoke(
        _dynamic_storage_names,
        Tuple{NamedTuple},
        prepared.submission_schema,
    )
    isempty(dynamic) && return prepared.storage
    dynamic_values = map(
        name -> getproperty(submission, name), dynamic
    )
    bindings = merge(
        prepared.storage, NamedTuple{dynamic}(dynamic_values)
    )
    length(bindings) == length(prepared.binding_names) &&
        all(name -> hasproperty(bindings, name), prepared.binding_names) ||
        throw(LocalWorkValidationError(
            "bound storage names changed after preparation"
        ))
    return bindings
end

function _validate_dynamic_aliases(prepared::PreparedWork, bindings)
    dynamic = invoke(
        _dynamic_storage_names,
        Tuple{NamedTuple},
        prepared.submission_schema,
    )
    isempty(dynamic) && return nothing
    names = keys(bindings)
    for dynamic_name in dynamic
        binding = getproperty(bindings, dynamic_name)
        dynamic_access = getproperty(prepared.binding_access, dynamic_name)
        for other_name in names
            other_name === dynamic_name && continue
            other_access = getproperty(prepared.binding_access, other_name)
            dynamic_access === :read && other_access === :read && continue
            Base.mightalias(binding, getproperty(bindings, other_name)) &&
                throw(LocalWorkValidationError(
                    "logical bindings $dynamic_name and $other_name illegally alias"
                ))
        end
        for (workspace_name, scratch) in prepared.workspace_arrays
            Base.mightalias(binding, scratch) && throw(
                LocalWorkValidationError(
                    "logical binding $dynamic_name aliases workspace $workspace_name"
                )
            )
        end
    end
    return nothing
end

function _cache_execution_lowering!(
        prepared::PreparedWork, arguments::Tuple
    )
    signature = typeof(arguments)
    if prepared.execution_signature !== signature
        method = which(_execute_lowering!, signature)
        method.module === (@__MODULE__) || throw(LocalWorkValidationError(
            "the execution lowering implementation is not centrally admitted"
        ))
        prepared.execution_signature = signature
        prepared.execution_method = method
    end
    return signature
end

function _lease_index(prepared::PreparedWork, serial::UInt64)
    return Int(mod(serial - UInt64(1), UInt64(length(prepared.leases)))) + 1
end

"""
    run!(prepared::PreparedWork, submission=(;)) -> WorkEvent

Validate and append one execution to the prepared provider lane. The call is
asynchronous where the backend supports it, performs no host wait, and retains
submission arguments and workspace through the returned cumulative event.
"""
function run!(prepared::PreparedWork, submission::NamedTuple = (;))
    current_task() === prepared.owner || throw(LocalWorkValidationError(
        "PreparedWork submission is bound to its preparing host task"
    ))
    prepared.poisoned && throw(LocalWorkValidationError(
        "PreparedWork is poisoned; inspect and drain before re-preparing"
    ))
    world = Base.get_world_counter()
    if world != prepared.operation_world
        for entry in prepared.operation_callbacks
            which(entry.callback, entry.signature) === entry.method ||
                throw(LocalWorkValidationError(
                    "the prepared $(entry.purpose) method changed after preparation"
                ))
        end
        prepared.operation_world = world
    end
    if world != prepared.trusted_world
        for entry in values(prepared.trusted_callbacks)
            which(entry.callback, entry.signature) === entry.method ||
                throw(LocalWorkValidationError(
                    "the cached $(entry.purpose) implementation changed after preparation"
                ))
        end
        if prepared.execution_method !== nothing
            which(_execute_lowering!, prepared.execution_signature) ===
                prepared.execution_method || throw(LocalWorkValidationError(
                    "the cached execution implementation changed after preparation"
                ))
        end
        if prepared.binding_method !== nothing
            which(_all_bindings, prepared.binding_signature) ===
                prepared.binding_method || throw(LocalWorkValidationError(
                    "the cached binding derivation changed after preparation"
                ))
        end
        if prepared.submission_method !== nothing
            which(_canonical_submission, prepared.submission_signature) ===
                prepared.submission_method || throw(LocalWorkValidationError(
                    "the cached submission validation changed after preparation"
                ))
        end
        prepared.trusted_world = world
    end
    invoke(
        _validate_fresh_topology,
        Tuple{WorkPlan},
        prepared.workplan;
        structural = false,
    )
    invoke(
        _validate_lane_current!,
        Tuple{typeof(prepared.lane)},
        prepared.lane,
    )
    invoke(
        _validate_prepared_identities, Tuple{PreparedWork}, prepared
    )
    submission_signature = Tuple{
        typeof(prepared.submission_schema), typeof(submission)
    }
    if prepared.submission_signature !== submission_signature
        submission_method = which(
            _canonical_submission, submission_signature
        )
        submission_method.module === (@__MODULE__) || throw(
            LocalWorkValidationError(
                "the submission validation implementation is not centrally admitted"
            )
        )
        prepared.submission_signature = submission_signature
        prepared.submission_method = submission_method
    end
    canonical = invoke(
        _canonical_submission,
        submission_signature,
        prepared.submission_schema,
        submission,
    )
    binding_signature = Tuple{typeof(prepared), typeof(canonical)}
    if prepared.binding_signature !== binding_signature
        binding_method = which(_all_bindings, binding_signature)
        binding_method.module === (@__MODULE__) || throw(
            LocalWorkValidationError(
                "the binding derivation implementation is not centrally admitted"
            )
        )
        prepared.binding_signature = binding_signature
        prepared.binding_method = binding_method
    end
    bindings = invoke(
        _all_bindings, binding_signature, prepared, canonical
    )
    invoke(
        _validate_dynamic_aliases,
        Tuple{PreparedWork, Any},
        prepared,
        bindings,
    )
    execution_arguments = (
        prepared.runtime,
        prepared.workplan.lowering,
        prepared.workplan.work,
        bindings,
        prepared.workspace,
        canonical,
    )
    execution_signature = invoke(
        _cache_execution_lowering!,
        Tuple{PreparedWork, Tuple},
        prepared,
        execution_arguments,
    )
    outstanding = prepared.submitted - prepared.drained
    outstanding < UInt64(length(prepared.leases)) ||
        throw(LocalWorkValidationError(
            "PreparedWork submission lease capacity is exhausted"
        ))

    lock(prepared.append_lock)
    try
        current_task() === prepared.owner || throw(LocalWorkValidationError(
            "PreparedWork host ownership changed during submission"
        ))
        serial = prepared.submitted + UInt64(1)
        lease_index = invoke(
            _lease_index,
            Tuple{PreparedWork, UInt64},
            prepared,
            serial,
        )
        # PreparedWork's const structural fields already retain static storage,
        # workspace, and runtime. A per-submission lease need retain only the
        # canonical submission, including any dynamically supplied arrays.
        prepared.leases[lease_index] = canonical
        try
            invoke(
                _execute_lowering!,
                execution_signature,
                execution_arguments...,
            )
        catch error
            # All schema, topology, binding, alias, method-ownership, and
            # lowering-dispatch checks finish before this boundary. A throw
            # after entering an admitted lowering may follow an appended
            # launch, so conservatively poison the complete shared provider
            # scope and retain the lease until that scope is discarded.
            invoke(
                _poison_lane!,
                Tuple{typeof(prepared.lane), Any},
                prepared.lane,
                error,
            )
            prepared.poisoned = true
            prepared.poison_reason = error
            rethrow()
        end
        prepared.submitted = serial
        return WorkEvent(_CONSTRUCTION_TOKEN, prepared, serial)
    finally
        unlock(prepared.append_lock)
    end
end

function _release_through!(prepared::PreparedWork, serial::UInt64)
    target = min(serial, prepared.submitted)
    while prepared.drained < target
        next_serial = prepared.drained + UInt64(1)
        prepared.leases[invoke(
            _lease_index,
            Tuple{PreparedWork, UInt64},
            prepared,
            next_serial,
        )] = nothing
        prepared.drained = next_serial
    end
    return nothing
end

function Base.wait(event::WorkEvent)
    prepared = event.prepared
    current_task() === prepared.owner || throw(LocalWorkValidationError(
        "this WorkEvent has a same-owner-task wait scope"
    ))
    UInt64(1) <= event.serial <= prepared.submitted ||
        throw(LocalWorkValidationError(
            "this WorkEvent serial was not issued by its PreparedWork"
        ))
    event.serial <= prepared.drained && return event
    # A provider lane-tail wait is cumulative and nonselective. Snapshot the
    # complete submitted prefix before waiting and reclaim that whole prefix
    # only after the tail wait succeeds, even when an older receipt is waited.
    target = prepared.submitted
    try
        # A method-table change after submission must not prevent mandatory
        # synchronization. The last successful run! recorded a validated
        # package-owned world; drain in that world so later external methods
        # cannot strand the already submitted asynchronous tail.
        Base.invoke_in_world(
            prepared.trusted_world,
            _centrally_admitted_provider_call,
            _wait_lane!,
            (prepared.lane,),
            :wait,
        )
    catch error
        prepared.poisoned = true
        prepared.poison_reason = error
        rethrow()
    end
    invoke(
        _release_through!,
        Tuple{PreparedWork, UInt64},
        prepared,
        target,
    )
    return event
end
