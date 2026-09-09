# Runtime-parameter lowering and reference-unit conversion.

function _symbolic_name(value; context = "symbolic value")
    value isa Symbol && return value
    return try
        Symbol(SymbolicIndexingInterface.getname(Symbolics.unwrap(value)))
    catch
        throw(ArgumentError("$context requires a stable symbolic name"))
    end
end

function _try_symbolic_name(value)
    return try
        _symbolic_name(value)
    catch
        nothing
    end
end

_is_quantity(value) = value isa DynamicQuantities.UnionAbstractQuantity

function _numeric_value(value, reference = nothing)
    if _is_quantity(value)
        reference isa ReferenceUnitDescriptor || throw(
            ArgumentError(
                "a dimensional value requires a compiled reference-unit descriptor"
            )
        )
        dimension = string(DynamicQuantities.dimension(value))
        dimension == reference.dimension || throw(
            ArgumentError(
                "expected dimensions $(reference.dimension), got $dimension"
            )
        )
        return DynamicQuantities.ustrip(value) / reference.scale
    elseif value isa Real &&
            SymbolicIndexingInterface.symbolic_type(value) isa
            SymbolicIndexingInterface.NotSymbolic
        return value
    end
    unwrapped = try
        Symbolics.value(Symbolics.unwrap(value))
    catch
        value
    end
    unwrapped isa Real ||
        throw(ArgumentError("expected a concrete numerical value, got $(repr(value))"))
    return unwrapped
end

function _reference_descriptor(name::Symbol, anchor)
    _is_quantity(anchor) || throw(
        ArgumentError(
            "reference unit `$name` must be a DynamicQuantities quantity"
        )
    )
    scale = abs(Float64(DynamicQuantities.ustrip(anchor)))
    scale > 0 && isfinite(scale) || throw(
        ArgumentError(
            "reference unit `$name` must have a finite nonzero scale"
        )
    )
    dimension = DynamicQuantities.dimension(anchor)
    dimension == one(dimension) && scale != 1 && throw(
        ArgumentError(
            "dimensionless reference unit `$name` must have scale one; plain numbers and indices are unscaled"
        )
    )
    return ReferenceUnitDescriptor(
        name, string(DynamicQuantities.dimension(anchor)), scale
    )
end

_build_reference_descriptors(system::PottsSystem) = _build_reference_descriptors(_completion_data(system))
function _build_reference_descriptors(data::CompletedPottsData)
    # Retain type-erased traversal while sharing completion's reference owner.
    anchors = _completion_reference_anchors(
        (record.normalized_statement for record in data.source_graph.records),
        data.reference_units,
    )
    descriptors = ReferenceUnitDescriptor[]
    by_dimension = Dict{String, ReferenceUnitDescriptor}()
    for (name, anchor) in anchors
        descriptor = _reference_descriptor(name, anchor)
        existing = get(by_dimension, descriptor.dimension, nothing)
        if existing !== nothing && existing.scale != descriptor.scale
            throw(
                ArgumentError(
                    "ambiguous declared reference scale for dimension " *
                        "$(descriptor.dimension): $(existing.name) and $(descriptor.name); " *
                        "supply ReferenceUnits(...) explicitly"
                )
            )
        end
        existing === nothing || continue
        by_dimension[descriptor.dimension] = descriptor
        push!(descriptors, descriptor)
    end
    sort!(descriptors; by = descriptor -> descriptor.dimension)
    return Tuple(descriptors)
end

function _reference_for(reference_units, value)
    _is_quantity(value) || return nothing
    dimension = string(DynamicQuantities.dimension(value))
    index = findfirst(reference -> reference.dimension == dimension, reference_units)
    index === nothing && throw(
        ArgumentError(
            "no reference-unit anchor was declared for dimension $dimension"
        )
    )
    return reference_units[index]
end

# An intermediate dimension need not have a stored state or declared parameter.
# Such expressions use SI scale one without adding a second reference inventory.
function _expression_reference_scale(unit, manifest::ParameterManifest)
    unit in (:dimensionless, :polymorphic_zero) && return 1.0
    dimension = _is_native_dimension(unit) ? string(unit) :
        unit isa Tuple && first(unit) === :declared_dimension ? last(unit) : nothing
    dimension === nothing && return 1.0
    index = findfirst(reference -> reference.dimension == dimension, manifest.reference_units)
    return index === nothing ? 1.0 : manifest.reference_units[index].scale
end

function _parameter_selection(manifest::ParameterManifest, value)
    if value isa Integer && !(value isa Bool)
        1 <= value <= length(manifest) || throw(BoundsError(manifest.entries, value))
        return Int(value)
    elseif value isa ParameterComponentIndex
        _parameter_slots(manifest, value)
        return value
    end
    index = value isa Symbol ? findfirst(entry -> entry.name === value, manifest.entries) :
        findfirst(entry -> isequal(Symbolics.unwrap(entry.symbolic), Symbolics.unwrap(value)), manifest.entries)
    index === nothing || return index
    expression = Symbolics.unwrap(value)
    if Symbolics.iscall(expression) && Symbolics.operation(expression) === getindex
        arguments = Symbolics.arguments(expression)
        length(arguments) == 2 || return nothing
        owner = findfirst(entry -> isequal(Symbolics.unwrap(entry.symbolic), first(arguments)), manifest.entries)
        owner === nothing && return nothing
        component = _compiler_literal(last(arguments))
        component isa Integer && !(component isa Bool) || throw(ArgumentError("parameter indexing requires a literal non-Boolean integer"))
        isempty(manifest[owner].shape) && throw(ArgumentError("scalar parameters do not have component indices"))
        selected = ParameterComponentIndex(owner, Int(component))
        _parameter_slots(manifest, selected)
        return selected
    end
    return nothing
end

function _parameter_index(manifest::ParameterManifest, value)
    # Numerical literals are not logical indices in scientific expressions.
    value isa Number && SymbolicIndexingInterface.symbolic_type(value) isa SymbolicIndexingInterface.NotSymbolic && return nothing
    selected = _parameter_selection(manifest, value)
    return selected === nothing ? nothing : _parameter_owner(selected)
end

function _compiled_scalar(
        value, manifest::ParameterManifest, ::Type{T}; reference = nothing
    ) where {T <: AbstractFloat}
    index = _parameter_index(manifest, value)
    if index !== nothing
        entry = manifest[index]
        selected = _parameter_selection(manifest, value)
        selected isa Integer && !isempty(entry.shape) && throw(ArgumentError("a scalar policy requires one parameter component, not whole vector `$(entry.name)`"))
        slot = only(_parameter_slots(manifest, selected))
        converted = entry.required ? nothing : _convert_parameter_value(entry, entry.default, T; finite = false)
        fallback = entry.required ? zero(T) : selected isa ParameterComponentIndex ? converted[selected.component] : converted
        return CorePotts.CompilerSPI.CompiledScalar(fallback, slot)
    end
    variables = try
        Symbolics.get_variables(value)
    catch
        ()
    end
    isempty(variables) || throw(
        ArgumentError(
            "runtime numerical expressions must be a literal or one declared parameter; " *
                "got $(repr(value))"
        )
    )
    resolved_reference = reference === nothing ?
        _reference_for(manifest.reference_units, value) :
        reference
    return CorePotts.CompilerSPI.CompiledScalar(T(_numeric_value(value, resolved_reference)))
end

function _default_parameter_buffer(manifest::ParameterManifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    buffer = zeros(T, _parameter_slot_count(manifest))
    for entry in manifest
        entry.required && continue
        converted = _convert_parameter_value(entry, entry.default, T; finite = false)
        buffer[_parameter_slots(entry)] .= isempty(entry.shape) ? (converted,) : converted
    end
    return buffer
end

function _normalize_parameter_pairs(values)
    values === nothing && return Pair[]
    values isa PottsParameters && return Pair[
        name => getproperty(values.named, name) for name in keys(values.named)
    ]
    values isa NamedTuple && return Pair[
        key => getproperty(values, key) for key in keys(values)
    ]
    values isa AbstractDict && return collect(pairs(values))
    values isa Pair && return Pair[values]
    values isa AbstractVector{<:Pair} && return collect(values)
    values isa Tuple && all(value -> value isa Pair, values) &&
        return Pair[values...]
    isempty(values) && return Pair[]
    throw(ArgumentError("`p` must be symbolic pairs, a dictionary, or a named tuple"))
end

function _normalize_parameters(
        plan::_PottsExecutionPlan, values
    )
    manifest = plan.parameter_manifest
    T = eltype(plan.core_program.parameter_defaults)
    logical = _normalize_parameter_values(manifest, values)
    buffer = zeros(T, _parameter_slot_count(manifest))
    for (index, value) in enumerate(logical.values)
        _write_parameter_value!(buffer, manifest, index, value)
    end
    CorePotts.CompilerSPI.validate_parameters(
        plan.core_program.descriptor_plan, buffer
    )
    return _saved_parameters(manifest, buffer)
end

function _parameter_reference(references, value)
    leaves = value isa AbstractArray ? Tuple(value) : (value,)
    units = map(leaf -> _reference_for(references, leaf), leaves)
    all(unit -> isequal(unit, first(units)), units) || throw(ArgumentError("runtime vector parameters require homogeneous units"))
    return first(units)
end

function _parameter_numeric_leaf(entry::RuntimeParameter, value; finite = true)
    numeric = if entry.unit === nothing
        _is_quantity(value) && throw(
            ArgumentError(
                "parameter `$(entry.name)` is dimensionless"
            )
        )
        _numeric_value(value)
    else
        _is_quantity(value) || throw(
            ArgumentError(
                "parameter `$(entry.name)` requires units compatible with $(entry.unit)"
            )
        )
        _numeric_value(value, entry.unit)
    end
    numeric isa Real && (!finite || isfinite(numeric)) || throw(ArgumentError("parameter `$(entry.name)` must be finite and real"))
    return numeric
end

function _validate_parameter_value(entry::RuntimeParameter, value; component = false, finite = true)
    if component || isempty(entry.shape)
        _parameter_numeric_leaf(entry, value; finite)
        return _defensive_copy(value)
    end
    _validate_parameter_shape(entry.name, entry.shape, value)
    for leaf in value
        _parameter_numeric_leaf(entry, leaf; finite)
    end
    return _parameter_logical_value(entry, value)
end

function _convert_parameter_value(entry::RuntimeParameter, value, ::Type{T}; component = false, finite = true) where {T <: AbstractFloat}
    validated = _validate_parameter_value(entry, value; component, finite)
    convert_leaf = leaf -> begin
        converted = T(_parameter_numeric_leaf(entry, leaf; finite))
        !finite || isfinite(converted) || throw(ArgumentError("parameter `$(entry.name)` must remain finite at selected precision"))
        converted
    end
    return component || isempty(entry.shape) ? convert_leaf(validated) : map(convert_leaf, validated)
end

function _write_parameter_value!(buffer::AbstractVector{T}, manifest, selected, value) where {T <: AbstractFloat}
    entry = manifest[_parameter_owner(selected)]
    component = selected isa ParameterComponentIndex
    converted = _convert_parameter_value(entry, value, T; component)
    buffer[_parameter_slots(manifest, selected)] .= component || isempty(entry.shape) ? (converted,) : converted
    return nothing
end

function _normalize_parameter_values(manifest::ParameterManifest, supplied; base = nothing)
    buffer = Any[nothing for _ in 1:_parameter_slot_count(manifest)]
    for (index, entry) in enumerate(manifest)
        value = base === nothing ? entry.default : base.values[index]
        value === nothing && continue
        # Declaration fallbacks may be replaced by supplied values. Validate
        # finiteness only after overlays; shape and units stay structural.
        validated = _validate_parameter_value(entry, value; finite = false)
        buffer[_parameter_slots(entry)] .= isempty(entry.shape) ? (validated,) : validated
    end
    assigned = falses(length(buffer))
    for (key, value) in _normalize_parameter_pairs(supplied)
        selected = _parameter_selection(manifest, key)
        if selected === nothing
            name = _try_symbolic_name(key)
            any(entry -> entry.name === name, manifest.structural) && throw(ArgumentError("parameter `$name` is structural; substitute it before mtkcompile"))
            throw(ArgumentError("unknown runtime parameter $(repr(key))"))
        end
        slots = _parameter_slots(manifest, selected)
        any(view(assigned, slots)) && throw(ArgumentError("runtime parameter selections overlap at $(repr(key))"))
        entry = manifest[_parameter_owner(selected)]
        component = selected isa ParameterComponentIndex
        validated = _validate_parameter_value(entry, value; component)
        buffer[slots] .= component || isempty(entry.shape) ? (validated,) : validated
        assigned[slots] .= true
    end
    missing = [entry.name for entry in manifest if any(isnothing, view(buffer, _parameter_slots(entry)))]
    isempty(missing) || throw(ArgumentError("missing required runtime parameters: " * join(string.(missing), ", ")))
    values = _parameter_values(manifest, buffer)
    for (entry, value) in zip(manifest, values)
        _validate_parameter_value(entry, value)
    end
    return PottsParameters(values, NamedTuple{Tuple(entry.name for entry in manifest)}(values))
end
