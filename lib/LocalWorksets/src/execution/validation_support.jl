# Structural validation shared by admitted lowerings. These helpers validate
# representation and bounded kernel-ABI facts only; output-family semantics
# remain with the lowering that owns them.

function _require_properties(value, names::Tuple, context)
    all(name -> hasproperty(value, name), names) || throw(
        LocalWorkValidationError(
            "$context requires $(join(string.(names), ", "))";
            stage = :plan,
            contract = :required_properties,
            expected = names,
            actual = propertynames(value),
        )
    )
    return nothing
end

function _exact_host_int(value, purpose)
    try
        return Int(value)
    catch
        throw(LocalWorkValidationError(
            "$purpose must be exactly representable as Int";
            stage = :plan,
            contract = :exact_host_integer,
            expected = Int,
            actual = value,
        ))
    end
end

function _bounded_count(
        value,
        purpose;
        positive::Bool = false,
        terminal::Bool = false,
    )
    count = invoke(_exact_host_int, Tuple{Any, Any}, value, purpose)
    valid = positive ? count > 0 : count >= 0
    valid || throw(LocalWorkValidationError(
        "$purpose must be $(positive ? "positive" : "nonnegative")";
        stage = :plan,
        contract = :bounded_count,
        expected = positive ? :positive : :nonnegative,
        actual = count,
    ))
    return invoke(
        _checked_int32_count,
        Tuple{Integer, Any},
        count,
        purpose;
        terminal,
    )
end

function _validate_topology_epoch(topology, context)
    hasproperty(topology, :epoch) || throw(LocalWorkValidationError(
        "$context topology requires epoch";
        stage = :plan,
        contract = :topology_epoch,
        expected = UInt64,
        actual = :missing,
    ))
    typeof(topology.epoch) === UInt64 || throw(LocalWorkValidationError(
        "$context topology epoch must be exactly UInt64";
        stage = :plan,
        contract = :topology_epoch,
        expected = UInt64,
        actual = typeof(topology.epoch),
    ))
    return topology.epoch
end

function _validate_item_domain(work::LocalWork, item_count::Int, context)
    work.items == (1:item_count) || throw(LocalWorkValidationError(
        "LocalWork items must exactly cover the $context item domain"
    ))
    return nothing
end

function _validate_dense_route(
        topology,
        name::Symbol,
        output,
        item_count::Int;
        context::Symbol,
        terminal_capacity::Bool,
    )
    hasproperty(topology.routes, output.route) || throw(
        LocalWorkValidationError(
            "$context port $name has no topology route $(output.route)";
            stage = :plan,
            contract = :route_presence,
            port = name,
            expected = output.route,
            actual = keys(topology.routes),
        )
    )
    hasproperty(topology.destination_counts, name) || throw(
        LocalWorkValidationError(
            "$context port $name has no destination count";
            stage = :plan,
            contract = :destination_count,
            port = name,
            expected = name,
            actual = keys(topology.destination_counts),
        )
    )
    route = getproperty(topology.routes, output.route)
    maximum = typeof(output).parameters[2]
    route isa AbstractMatrix || throw(LocalWorkValidationError(
        "$context route $(output.route) must be a matrix";
        stage = :plan,
        contract = :route_layout,
        port = name,
        expected = AbstractMatrix,
        actual = typeof(route),
    ))
    isconcretetype(eltype(route)) && eltype(route) <: Integer || throw(
        LocalWorkValidationError(
            "$context route $(output.route) requires a concrete integer element type";
            stage = :plan,
            contract = :route_element_type,
            port = name,
            expected = Integer,
            actual = eltype(route),
        )
    )
    size(route) == (maximum, item_count) || throw(LocalWorkValidationError(
        "$context route $(output.route) must have exact shape ($maximum, $item_count)";
        stage = :plan,
        contract = :route_shape,
        port = name,
        expected = (maximum, item_count),
        actual = size(route),
    ))
    destination_count = invoke(
        _bounded_count,
        Tuple{Any, Any},
        getproperty(topology.destination_counts, name),
        Symbol(name, :_destination_count),
    )
    capacity = invoke(
        _checked_int_product,
        Tuple{Integer, Integer, Any},
        item_count,
        maximum,
        Symbol(name, :_route_capacity),
    )
    capacity == length(route) || throw(LocalWorkValidationError(
        "$context route $(output.route) has inconsistent capacity"
    ))
    terminal_capacity && invoke(
        _checked_int32_count,
        Tuple{Integer, Any},
        capacity,
        Symbol(name, :_record_capacity);
        terminal = true,
    )
    for value in route
        destination = invoke(
            _exact_host_int,
            Tuple{Any, Any},
            value,
            Symbol(name, :_route_destination),
        )
        0 <= destination <= destination_count || throw(
            LocalWorkValidationError(
                "$context route $(output.route) contains an out-of-domain destination";
                stage = :plan,
                contract = :route_destination_domain,
                port = name,
                expected = 0:destination_count,
                actual = destination,
            )
        )
    end
    return route, destination_count
end

struct _BindingRequirement{T, N, S}
    name::Symbol
    size::S
    access::Symbol
    allow_readwrite::Bool
    role::Symbol
end

function _binding_requirement(
        name::Symbol,
        ::Type{T},
        size::NTuple{N, Int},
        access::Symbol;
        allow_readwrite::Bool = false,
        role::Symbol,
    ) where {T, N}
    access in (:read, :write, :readwrite) || error(
        "invalid package-owned binding requirement"
    )
    return _BindingRequirement{T, N, typeof(size)}(
        name,
        size,
        access,
        allow_readwrite,
        role,
    )
end

function _validate_binding_requirement(
        storage,
        schema,
        requirement::_BindingRequirement{T, N},
    ) where {T, N}
    name = requirement.name
    facts = invoke(
        _binding_facts,
        Tuple{Any, Any, Any},
        storage,
        schema,
        name,
    )
    facts.element_type === T || throw(LocalWorkValidationError(
        "$(requirement.role) binding $name must have element type $T";
        stage = :prepare,
        contract = :binding_element_type,
        binding = name,
        expected = T,
        actual = facts.element_type,
    ))
    facts.dimensions == N && facts.size == requirement.size || throw(
        LocalWorkValidationError(
            "$(requirement.role) binding $name must have exact size $(requirement.size)";
            stage = :prepare,
            contract = :binding_shape,
            binding = name,
            expected = requirement.size,
            actual = facts.size,
        )
    )
    access_ok = facts.access === nothing ||
        facts.access === requirement.access ||
        requirement.allow_readwrite && facts.access === :readwrite
    access_ok || throw(LocalWorkValidationError(
        "$(requirement.role) binding $name requires $(requirement.access) access";
        stage = :prepare,
        contract = :binding_access,
        binding = name,
        expected = requirement.access,
        actual = facts.access,
    ))
    return nothing
end

function _validate_binding_requirements(storage, schema, requirements::Tuple)
    for requirement in requirements
        invoke(
            _validate_binding_requirement,
            Tuple{Any, Any, _BindingRequirement},
            storage,
            schema,
            requirement,
        )
    end
    return nothing
end
