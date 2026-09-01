# Cold physical validation shared by the sole Stage planning/preparation path.

function _validate_array_backend(array, backend, name)
    _require_stable_array_representation(array, :prepare, Symbol(:binding_, name))
    _array_backend(array) == backend || throw(LocalMathValidationError(
        "binding $name belongs to a different backend";
        stage = :prepare, contract = :binding_backend, binding = name,
        expected = typeof(backend), actual = typeof(_array_backend(array))))
    return nothing
end

function _workspace_leases(workspace)
    hasproperty(workspace, :leases) || throw(LocalMathValidationError(
        "prepared workspace requires prebound host lease slots";
        stage = :prepare, contract = :workspace_lease_capacity,
        workspace_leaf = :leases, expected = :positive_prebound_vector,
        actual = :missing))
    leases = getproperty(workspace, :leases)
    leases isa Vector{Any} || throw(LocalMathValidationError(
        "prepared lease slots must be a Vector{Any}";
        stage = :prepare, contract = :workspace_lease_storage,
        workspace_leaf = :leases, expected = Vector{Any}, actual = typeof(leases)))
    isempty(leases) && throw(LocalMathValidationError(
        "prepared lease capacity must be positive";
        stage = :prepare, contract = :workspace_lease_capacity,
        workspace_leaf = :leases, expected = :positive, actual = 0))
    all(isnothing, leases) || throw(LocalMathValidationError(
        "prepared lease slots must initially be empty";
        stage = :prepare, contract = :workspace_lease_initial_state,
        workspace_leaf = :leases, expected = :all_empty, actual = :occupied))
    return leases
end

_physical_alias_leaves(name::Symbol, value) = _binding_physical_leaves(name, value)

function _arrays_mightalias(
        first_name::Symbol, first_array, second_name::Symbol, second_array)
    for first_leaf in _physical_alias_leaves(first_name, first_array)
        for second_leaf in _physical_alias_leaves(second_name, second_array)
            Base.mightalias(last(first_leaf), last(second_leaf)) &&
                return (first(first_leaf), first(second_leaf))
        end
    end
    return nothing
end

function _workspace_arrays(lowering, workspace, lease_capacity::Int)
    authority = _prepared_workspace_authority(lowering.workspace, lease_capacity)
    return _typed_workspace_arrays(workspace, authority.template)
end

function _validate_workspace_structure(value, path = :workspace)
    value isa AbstractArray && return nothing
    ismutabletype(typeof(value)) && throw(LocalMathValidationError(
        "workspace structural container $path must be immutable";
        stage = :prepare, contract = :workspace_structure,
        workspace_leaf = path, expected = :immutable_container,
        actual = typeof(value)))
    for index in 1:fieldcount(typeof(value))
        name = fieldname(typeof(value), index)
        _validate_workspace_structure(getfield(value, index), Symbol(path, :_, name))
    end
    return nothing
end

function _prepared_array_fact(array)
    bytes = _checked_int_product(length(array), sizeof(eltype(array)),
        :prepared_array_bytes)
    fact = (identity = objectid(array), array_type = typeof(array),
        element_type = eltype(array), dimensions = ndims(array), size = size(array),
        strides = _array_strides(array), bytes,
        backend = typeof(_array_backend(array)),
        address_space = _array_address_space(array),
        device = _array_device_identity(array))
    array isa StructArrays.StructArray || return fact
    components = map(_prepared_array_fact, StructArrays.components(array))
    return merge(fact, (layout = :structarray_soa, logical_bytes = bytes,
        bytes = sum(component.bytes for component in values(components)),
        physical_components = components))
end

function _validate_cached_static_array_fact(array, fact, name)
    objectid(array) == fact.identity || throw(LocalMathValidationError(
        "prepared static-binding identity $name changed after preparation"))
    typeof(array) === fact.array_type || throw(LocalMathValidationError(
        "prepared static-binding concrete array type $name changed after preparation"))
    eltype(array) === fact.element_type && ndims(array) == fact.dimensions ||
        throw(LocalMathValidationError(
            "prepared static-binding element layout $name changed after preparation"))
    if array isa StructArrays.StructArray
        components = StructArrays.components(array)
        hasproperty(fact, :physical_components) &&
            keys(components) == keys(fact.physical_components) ||
            throw(LocalMathValidationError(
                "prepared static-binding component schema $name changed after preparation"))
        for (index, (component, component_fact)) in enumerate(zip(
                values(components), values(fact.physical_components)))
            _validate_cached_static_array_fact(
                component, component_fact, Symbol(name, :_, index))
        end
    else
        size(array) == fact.size && _array_strides(array) == fact.strides ||
            throw(LocalMathValidationError(
                "prepared static-binding layout $name changed after preparation"))
    end
    return nothing
end
