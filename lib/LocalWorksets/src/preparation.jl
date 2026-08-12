function _validate_schema(schema::NamedTuple)
    for (name, slot) in pairs(schema)
        slot isa Union{_ValueSlot, _StorageSlot} ||
            throw(LocalWorkValidationError(
                "submission slot $name is not a value_slot or storage_slot"
            ))
    end
    return nothing
end

function _validate_active_schema(work::LocalWork, schema::NamedTuple)
    if work.operation isa _SequenceOperation
        for stage in work.operation.works
            invoke(
                _validate_active_schema,
                Tuple{LocalWork, NamedTuple},
                stage,
                schema,
            )
        end
        return nothing
    end
    work.active === nothing && return nothing
    work.active isa Symbol || throw(LocalWorkValidationError(
        "active selection must name one submission value slot"
    ))
    hasproperty(schema, work.active) || throw(LocalWorkValidationError(
        "active selection $(work.active) has no prepared submission slot"
    ))
    slot = getproperty(schema, work.active)
    slot isa _ValueSlot{Int32} ||
        throw(LocalWorkValidationError(
            "active selection requires an Int32 value slot"
        ))
    bounds = slot.bounds
    bounds isa AbstractUnitRange{Int32} && !isempty(bounds) &&
        first(bounds) >= Int32(0) &&
        last(bounds) <= Int32(length(work.items)) ||
        throw(LocalWorkValidationError(
            "active-selection bounds must fit the planned item capacity"
        ))
    return nothing
end

function _validate_array_backend(array, backend, name)
    KernelAbstractions.get_backend(array) == backend ||
        throw(LocalWorkValidationError(
            "binding $name belongs to a different backend"
        ))
    return nothing
end

function _dynamic_storage_names(schema::NamedTuple)
    return Tuple(
        name for (name, slot) in pairs(schema) if slot isa _StorageSlot
    )
end

function _validate_static_bindings(
        binding_names, storage::NamedTuple, schema::NamedTuple, backend
    )
    dynamic = invoke(_dynamic_storage_names, Tuple{NamedTuple}, schema)
    all(name -> name in binding_names, dynamic) ||
        throw(LocalWorkValidationError(
            "submission storage slots must correspond to declared logical bindings"
        ))
    expected_static = Tuple(
        name for name in binding_names if !(name in dynamic)
    )
    actual = Tuple(keys(storage))
    missing = Tuple(name for name in expected_static if !(name in actual))
    extra = Tuple(name for name in actual if !(name in expected_static))
    isempty(missing) && isempty(extra) || throw(LocalWorkValidationError(
        "static storage binding mismatch: missing=$(missing), extra=$(extra), expected=$(expected_static)";
        stage = :prepare, contract = :storage_binding_names,
        expected = expected_static, actual = actual,
        hint = "bind every static logical read and output exactly once",
    ))
    for name in expected_static
        invoke(
            _validate_array_backend,
            Tuple{Any, Any, Any},
            getproperty(storage, name),
            backend,
            name,
        )
    end
    return nothing
end

function _workspace_leases(workspace)
    hasproperty(workspace, :leases) || throw(LocalWorkValidationError(
        "prepared workspace requires prebound host lease slots";
        stage = :prepare, contract = :workspace_lease_capacity,
        workspace_leaf = :leases,
        expected = :positive_prebound_vector, actual = :missing,
    ))
    leases = getproperty(workspace, :leases)
    leases isa Vector{Any} || throw(LocalWorkValidationError(
        "prepared lease slots must be a Vector{Any}";
        stage = :prepare, contract = :workspace_lease_storage,
        workspace_leaf = :leases,
        expected = Vector{Any}, actual = typeof(leases),
    ))
    isempty(leases) && throw(LocalWorkValidationError(
        "prepared lease capacity must be positive";
        stage = :prepare, contract = :workspace_lease_capacity,
        workspace_leaf = :leases, expected = :positive, actual = 0,
    ))
    all(isnothing, leases) || throw(LocalWorkValidationError(
        "prepared lease slots must initially be empty";
        stage = :prepare, contract = :workspace_lease_initial_state,
        workspace_leaf = :leases,
        expected = :all_empty, actual = :occupied,
    ))
    return leases
end

function _validate_distinct_aliases(bindings::NamedTuple, access::NamedTuple)
    names = keys(bindings)
    for first_index in eachindex(names), second_index in eachindex(names)
        first_index < second_index || continue
        first_name = names[first_index]
        second_name = names[second_index]
        first_access = getproperty(access, first_name)
        second_access = getproperty(access, second_name)
        first_access === :read && second_access === :read && continue
        Base.mightalias(
            getproperty(bindings, first_name),
            getproperty(bindings, second_name),
        ) && throw(LocalWorkValidationError(
            "logical bindings $first_name and $second_name illegally alias";
            stage = :prepare, contract = :storage_alias,
            binding = first_name,
            expected = :nonaliasing_writable_bindings,
            actual = (first_name, second_name),
        ))
    end
    return nothing
end

function _workspace_arrays(lowering, work, workspace)
    spec = invoke(
        _centrally_owned_workspace_spec,
        Tuple{Any, Any},
        lowering,
        work,
    )
    return invoke(
        _workspace_arrays_from_spec,
        Tuple{Any, Tuple},
        workspace,
        spec,
    )
end

function _validate_workspace_structure(value, path = :workspace)
    value isa AbstractArray && return nothing
    ismutabletype(typeof(value)) && throw(LocalWorkValidationError(
        "workspace structural container $path must be immutable"
    ))
    for field_index in 1:fieldcount(typeof(value))
        field_name = fieldname(typeof(value), field_index)
        invoke(
            _validate_workspace_structure,
            Tuple{Any, Any},
            getfield(value, field_index),
            Symbol(path, :_, field_name),
        )
    end
    return nothing
end

_operation_call_facts(lowering, work, storage, schema) = ()

function _workspace_arrays(lowering::_SequenceLowering, work, workspace)
    stages = invoke(
        _sequence_stage_workspaces,
        Tuple{Any, Any},
        workspace,
        length(lowering.stages),
    )
    stage_arrays = map(eachindex(lowering.stages)) do index
        arrays = invoke(
            _centrally_admitted_lowering_call,
            Tuple{Function, Tuple, Symbol},
            _workspace_arrays,
            (
                lowering.stages[index],
                work.operation.works[index],
                stages[index],
            ),
            :workspace_arrays,
        )
        return map(arrays) do pair
            Symbol(:stage, index, :_, first(pair)) => last(pair)
        end
    end
    return reduce((left, right) -> (left..., right...), stage_arrays;
                  init = ())
end

function _validate_workspace_aliases(bindings, lowering, work, workspace)
    for (binding_name, binding) in pairs(bindings)
        arrays = invoke(
            _centrally_admitted_lowering_call,
            Tuple{Function, Tuple, Symbol},
            _workspace_arrays,
            (lowering, work, workspace),
            :workspace_arrays,
        )
        for (workspace_name, scratch) in arrays
            Base.mightalias(binding, scratch) &&
                throw(LocalWorkValidationError(
                    "logical binding $binding_name aliases workspace $workspace_name";
                    stage = :prepare, contract = :workspace_alias,
                    binding = binding_name,
                    workspace_leaf = workspace_name,
                    expected = :nonaliasing,
                    actual = (binding_name, workspace_name),
                ))
        end
    end
    return nothing
end

function _validate_device_coherence(storage, schema, lowering, work, workspace)
    identities = Any[
        invoke(_array_device_identity, Tuple{Any}, value)
        for value in values(storage)
    ]
    append!(identities, (
        slot.device_identity for slot in values(schema)
        if slot isa _StorageSlot
    ))
    append!(identities, (
        invoke(_array_device_identity, Tuple{Any}, array)
        for (_, array) in invoke(
            _centrally_admitted_lowering_call,
            Tuple{Function, Tuple, Symbol},
            _workspace_arrays,
            (lowering, work, workspace),
            :workspace_arrays,
        )
    ))
    isempty(identities) || all(==(first(identities)), identities) ||
        throw(LocalWorkValidationError(
            "storage, submission slots, and workspace span devices or contexts"
        ))
    return nothing
end

function _prepared_array_fact(array)
    return (
        identity = objectid(array),
        element_type = eltype(array),
        dimensions = ndims(array),
        size = size(array),
        strides = strides(array),
        backend = typeof(KernelAbstractions.get_backend(array)),
        device = invoke(_array_device_identity, Tuple{Any}, array),
    )
end

_static_identities(storage) = NamedTuple{keys(storage)}(map(
    array -> invoke(_prepared_array_fact, Tuple{Any}, array),
    values(storage),
))

_workspace_identities(lowering, work, workspace) = Tuple(
    name => invoke(_prepared_array_fact, Tuple{Any}, array)
    for (name, array) in
        invoke(
            _centrally_admitted_lowering_call,
            Tuple{Function, Tuple, Symbol},
            _workspace_arrays,
            (lowering, work, workspace),
            :workspace_arrays,
        )
)

function _validate_prepared_identities(prepared::PreparedWork)
    invoke(
        _validate_static_array_facts,
        Tuple{Tuple, Tuple, Tuple},
        values(prepared.storage),
        values(prepared.static_identities),
        keys(prepared.storage),
    )
    invoke(
        _validate_workspace_array_facts,
        Tuple{Tuple, Tuple},
        prepared.workspace_arrays, prepared.workspace_identities
    )
    return nothing
end

function _validate_static_array_facts(arrays::Tuple, facts::Tuple, names::Tuple)
    isempty(arrays) && return nothing
    length(arrays) == length(facts) == length(names) ||
        throw(LocalWorkValidationError(
            "prepared static-binding evidence has inconsistent arity"
        ))
    invoke(
        _validate_prepared_array_fact,
        Tuple{Any, Any, Any, Any},
        first(arrays), first(facts), first(names), :static_binding
    )
    return invoke(
        _validate_static_array_facts,
        Tuple{Tuple, Tuple, Tuple},
        Base.tail(arrays), Base.tail(facts), Base.tail(names)
    )
end


function _validate_workspace_array_facts(arrays::Tuple, facts::Tuple)
    isempty(arrays) && return nothing
    length(arrays) == length(facts) || throw(LocalWorkValidationError(
        "prepared workspace evidence has inconsistent arity"
    ))
    name, array = first(arrays)
    stored_name, fact = first(facts)
    name === stored_name || throw(LocalWorkValidationError(
        "prepared workspace names changed after preparation"
    ))
    invoke(
        _validate_prepared_array_fact,
        Tuple{Any, Any, Any, Any},
        array,
        fact,
        name,
        :workspace,
    )
    return invoke(
        _validate_workspace_array_facts,
        Tuple{Tuple, Tuple},
        Base.tail(arrays), Base.tail(facts)
    )
end

function _validate_prepared_array_fact(array, fact, name, role)
    objectid(array) == fact.identity || throw(LocalWorkValidationError(
        "prepared $role identity $name changed after preparation"
    ))
    eltype(array) === fact.element_type &&
        ndims(array) == fact.dimensions &&
        size(array) == fact.size &&
        strides(array) == fact.strides ||
        throw(LocalWorkValidationError(
            "prepared $role layout $name changed after preparation"
        ))
    # Preparation freezes the exact array object after validating its backend
    # and device/context. A warm submission cannot substitute another array;
    # the identity and complete layout checks above still catch replacement or
    # resizing. Re-querying the backend for that same object here adds no new
    # lifetime fact and is deliberately kept off the launch path.
    return nothing
end

"""
    prepare(workplan::WorkPlan, storage; workspace=nothing,
            lease_capacity=nothing, submission=(;))

Bind a validated plan to concrete storage, workspace, submission slots, and
one provider lane. When `workspace` is omitted, bounded algorithmic arrays are
allocated exactly once during preparation with `KernelAbstractions.allocate`;
`lease_capacity` defaults to one. An explicit caller workspace remains
supported and owns its `leases`. Preparation validates topology freshness,
backend/device/layout coherence, access and alias contracts, and fixed queue
capacity before execution.
"""
function prepare(
        workplan::WorkPlan,
        storage::NamedTuple;
        workspace = nothing,
        lease_capacity::Union{Nothing, Integer} = nothing,
        submission::NamedTuple = (;),
    )
    owned = function (callback::Function, signature::Type{<:Tuple}, args...)
        method = which(callback, signature)
        method.module === (@__MODULE__) || throw(LocalWorkValidationError(
            "the preparation implementation is not package-owned"
        ))
        return invoke(callback, signature, args...)
    end
    trusted = function (
            callback::Function, signature::Type{<:Tuple}, purpose::Symbol
        )
        method = which(callback, signature)
        method.module === (@__MODULE__) || throw(LocalWorkValidationError(
            "the $purpose implementation is not centrally admitted"
        ))
        return (; callback, signature, method, purpose)
    end

    owned(_validate_fresh_topology, Tuple{WorkPlan}, workplan)
    owned(_validate_schema, Tuple{NamedTuple}, submission)
    owned(
        _validate_active_schema,
        Tuple{LocalWork, NamedTuple},
        workplan.work,
        submission,
    )
    binding_names = owned(
        _centrally_admitted_lowering_call,
        Tuple{Function, Tuple, Symbol},
        _required_bindings,
        (workplan.lowering, workplan.work),
        :required_bindings,
    )
    binding_access = owned(
        _centrally_admitted_lowering_call,
        Tuple{Function, Tuple, Symbol},
        _binding_access,
        (workplan.lowering, workplan.work),
        :binding_access,
    )
    owned(
        _validate_static_bindings,
        Tuple{Any, NamedTuple, NamedTuple, Any},
        binding_names, storage, submission, workplan.backend
    )
    owned(
        _centrally_admitted_lowering_call,
        Tuple{Function, Tuple, Symbol},
        _validate_binding_schema,
        (
            workplan.lowering,
            workplan.work,
            storage,
            submission,
            workplan.backend,
        ),
        :binding_validation,
    )
    static_access_names = keys(storage)
    static_access = NamedTuple{static_access_names}(
        getproperty.(Ref(binding_access), static_access_names)
    )
    owned(
        _validate_distinct_aliases,
        Tuple{NamedTuple, NamedTuple},
        storage,
        static_access,
    )
    workspace_ownership = workspace === nothing ? :package : :caller
    if workspace === nothing
        capacity = lease_capacity === nothing ? 1 : owned(
            _bounded_count,
            Tuple{Any, Any},
            lease_capacity,
            :lease_capacity,
        )
        capacity > 0 || throw(LocalWorkValidationError(
            "lease_capacity must be positive";
            stage = :prepare, contract = :workspace_lease_capacity,
            workspace_leaf = :leases,
            expected = :positive, actual = capacity,
        ))
        workspace = owned(
            _automatic_workspace,
            Tuple{Any, Any, Any, Int},
            workplan.lowering,
            workplan.work,
            workplan.backend,
            capacity,
        )
    elseif lease_capacity !== nothing
        throw(LocalWorkValidationError(
            "lease_capacity is only valid when workspace is omitted";
            stage = :prepare, contract = :workspace_ownership,
            workspace_leaf = :leases,
            expected = :automatic_workspace, actual = :caller_workspace,
        ))
    end
    owned(
        _centrally_admitted_lowering_call,
        Tuple{Function, Tuple, Symbol},
        _validate_workspace,
        (
            workplan.lowering,
            workplan.work,
            workspace,
            workplan.backend,
        ),
        :workspace_validation,
    )
    owned(
        _validate_workspace_aliases,
        Tuple{Any, Any, Any, Any},
        storage, workplan.lowering, workplan.work, workspace
    )
    owned(
        _validate_workspace_structure,
        Tuple{Any, Any},
        workspace,
        :workspace,
    )
    owned(
        _validate_device_coherence,
        Tuple{Any, Any, Any, Any, Any},
        storage,
        submission,
        workplan.lowering,
        workplan.work,
        workspace,
    )
    leases = owned(_workspace_leases, Tuple{Any}, workspace)
    lane = owned(
        _central_make_provider_lane,
        Tuple{Any, Any},
        workplan.backend,
        storage,
    )
    owned(
        _centrally_admitted_provider_call,
        Tuple{Function, Tuple, Symbol},
        _validate_provider_capacity,
        (lane, workplan.evidence, length(leases)),
        :capacity_validation,
    )
    runtime = owned(
        _centrally_admitted_lowering_call,
        Tuple{Function, Tuple, Symbol},
        _prepare_lowering,
        (
            workplan.lowering,
            workplan.work,
            storage,
            workspace,
            workplan.backend,
        ),
        :preparation,
    )
    workspace_arrays = owned(
        _centrally_admitted_lowering_call,
        Tuple{Function, Tuple, Symbol},
        _workspace_arrays,
        (workplan.lowering, workplan.work, workspace),
        :workspace_arrays,
    )
    operation_callbacks = owned(
        _centrally_admitted_lowering_call,
        Tuple{Function, Tuple, Symbol},
        _operation_call_facts,
        (workplan.lowering, workplan.work, storage, submission),
        :operation_call_facts,
    )
    trusted_callbacks = (
        lane = trusted(
            _validate_lane_current!,
            Tuple{typeof(lane)},
            :lane_validation,
        ),
        wait = trusted(
            _wait_lane!,
            Tuple{typeof(lane)},
            :wait,
        ),
        workspace = trusted(
            _validate_workspace,
            Tuple{
                typeof(workplan.lowering),
                typeof(workplan.work),
                typeof(workspace),
                typeof(workplan.backend),
            },
            :workspace_validation,
        ),
        binding = trusted(
            _validate_binding_schema,
            Tuple{
                typeof(workplan.lowering),
                typeof(workplan.work),
                typeof(storage),
                typeof(submission),
                typeof(workplan.backend),
            },
            :binding_validation,
        ),
        workspace_arrays = trusted(
            _workspace_arrays,
            Tuple{
                typeof(workplan.lowering),
                typeof(workplan.work),
                typeof(workspace),
            },
            :workspace_arrays,
        ),
        topology = trusted(
            _validate_fresh_topology,
            Tuple{WorkPlan},
            :topology_validation,
        ),
        prepared_identities = trusted(
            _validate_prepared_identities,
            Tuple{PreparedWork},
            :prepared_identity_validation,
        ),
        canonical_submission = trusted(
            _canonical_submission,
            Tuple{NamedTuple, NamedTuple},
            :submission_validation,
        ),
        value_validation = trusted(
            _validate_value,
            Tuple{_ValueSlot, Any, Any},
            :value_validation,
        ),
        storage_validation = trusted(
            _validate_storage,
            Tuple{_StorageSlot, Any, Any},
            :storage_validation,
        ),
        bindings = trusted(
            _all_bindings,
            Tuple{PreparedWork, NamedTuple},
            :binding_derivation,
        ),
        dynamic_aliases = trusted(
            _validate_dynamic_aliases,
            Tuple{PreparedWork, Any},
            :dynamic_alias_validation,
        ),
        dynamic_names = trusted(
            _dynamic_storage_names,
            Tuple{NamedTuple},
            :dynamic_storage_names,
        ),
        cached_execution = trusted(
            _cache_execution_lowering!,
            Tuple{PreparedWork, Tuple},
            :cached_execution,
        ),
        provider_poison = trusted(
            _poison_lane!,
            Tuple{typeof(lane), Any},
            :provider_poison,
        ),
        lease_index = trusted(
            _lease_index,
            Tuple{PreparedWork, UInt64},
            :lease_index,
        ),
        release = trusted(
            _release_through!,
            Tuple{PreparedWork, UInt64},
            :lease_release,
        ),
        prepared_array_fact = trusted(
            _validate_prepared_array_fact,
            Tuple{Any, Any, Any, Any},
            :prepared_array_fact,
        ),
        static_array_facts = trusted(
            _validate_static_array_facts,
            Tuple{Tuple, Tuple, Tuple},
            :static_array_facts,
        ),
        workspace_array_facts = trusted(
            _validate_workspace_array_facts,
            Tuple{Tuple, Tuple},
            :workspace_array_facts,
        ),
        array_device_identity = trusted(
            _array_device_identity,
            Tuple{Any},
            :array_device_identity,
        ),
    )
    world = Base.get_world_counter()
    return PreparedWork(
        _CONSTRUCTION_TOKEN,
        workplan,
        storage,
        workspace,
        submission,
        lane,
        runtime,
        binding_names,
        binding_access,
        owned(_static_identities, Tuple{Any}, storage),
        owned(
            _workspace_identities,
            Tuple{Any, Any, Any},
            workplan.lowering, workplan.work, workspace
        ),
        workspace_arrays,
        workspace_ownership,
        trusted_callbacks,
        operation_callbacks,
        world,
        world,
        nothing,
        nothing,
        nothing,
        nothing,
        nothing,
        nothing,
        ReentrantLock(),
        current_task(),
        UInt64(0),
        UInt64(0),
        leases,
        false,
        nothing,
    )
end
