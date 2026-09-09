# Runtime-parameter lowering and reference-unit conversion.

function _symbolic_name(value; context = "symbolic value")
    value isa Symbol && return value
    return try
        Symbol(SymbolicIndexingInterface.getname(Symbolics.unwrap(value)))
    catch
        throw(ArgumentError("$context requires a stable symbolic name"))
    end
end

_parameter_name(parameter) =
    _symbolic_name(parameter; context = "runtime parameter")

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

function _build_reference_descriptors(system::PottsSystem)
    data = _completion_data(system)
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

function _completed_runtime_parameters(data::CompletedPottsData)
    result = Any[]
    for reference in data.source_graph.references
        reference.kind === :parameter || continue
        parameter = _qualified_source_reference(reference)
        any(candidate -> isequal(candidate, parameter), result) ||
            push!(result, parameter)
    end
    return result
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

function _parameter_default(parameter)
    if ModelingToolkitBase.hasdefault(parameter)
        return ModelingToolkitBase.getdefault(parameter), false
    end
    return nothing, true
end

function _build_parameter_manifest(system::PottsSystem, ::Type{T}) where {
        T <: AbstractFloat,
    }
    reference_units = _build_reference_descriptors(system)
    completion = _completion_data(system)
    entries = RuntimeParameter[]
    names = Set{Symbol}()
    for (index, parameter) in enumerate(_completed_runtime_parameters(completion))
        name = _parameter_name(parameter)
        name in names &&
            throw(ArgumentError("duplicate runtime parameter name `$name`"))
        push!(names, name)
        default, required = _parameter_default(parameter)
        unit = required ? nothing : _reference_for(reference_units, default)
        converted = required ? nothing : T(_numeric_value(default, unit))
        push!(entries, RuntimeParameter(name, converted, required, unit, index))
    end
    structural = Tuple(
        StructuralParameter(
                entry.name,
                _compiled_structural_value(entry.value, reference_units),
            )
            for entry in completion.parameter_roles.structural
    )
    return ParameterManifest(Tuple(entries), structural, reference_units)
end

function _compiled_structural_value(value, reference_units)
    if _is_quantity(value)
        reference = _reference_for(reference_units, value)
        return (
            value = Float64(_numeric_value(value, reference)),
            reference = reference.name,
            dimension = reference.dimension,
        )
    elseif value isa NamedTuple
        mapped = map(
            item -> _compiled_structural_value(item, reference_units),
            values(value),
        )
        return NamedTuple{keys(value)}(mapped)
    elseif value isa Tuple
        return map(item -> _compiled_structural_value(item, reference_units), value)
    elseif value isa AbstractArray
        return map(item -> _compiled_structural_value(item, reference_units), value)
    elseif value isa Union{Number, Symbol, String, Bool}
        return value
    end
    return string(value)
end

function _parameter_index(manifest::ParameterManifest, value)
    name = _try_symbolic_name(value)
    name === nothing && return nothing
    return findfirst(entry -> entry.name === name, manifest.entries)
end

function _compiled_scalar(
        value, manifest::ParameterManifest, ::Type{T}; reference = nothing
    ) where {T <: AbstractFloat}
    index = _parameter_index(manifest, value)
    if index !== nothing
        entry = manifest[index]
        fallback = entry.required ? zero(T) : T(entry.default)
        return CorePotts.CompilerSPI.CompiledScalar(fallback, index)
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
    buffer = Vector{T}(undef, length(manifest))
    for (index, entry) in enumerate(manifest)
        buffer[index] = entry.required ? zero(T) : T(entry.default)
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
    buffer = _default_parameter_buffer(manifest, T)
    assigned = falses(length(manifest))
    for (key, value) in _normalize_parameter_pairs(values)
        index = if key isa Symbol
            findfirst(entry -> entry.name === key, manifest.entries)
        else
            _parameter_index(manifest, key)
        end
        structural_name = key isa Symbol ? key : _try_symbolic_name(key)
        if index === nothing && structural_name !== nothing &&
                any(entry -> entry.name === structural_name, manifest.structural)
            throw(
                ArgumentError(
                    "parameter `$structural_name` is structural; substitute it on " *
                        "the incomplete system and recompile"
                )
            )
        end
        index === nothing &&
            throw(ArgumentError("unknown runtime parameter $(repr(key))"))
        assigned[index] &&
            throw(ArgumentError("duplicate runtime parameter $(repr(key))"))
        entry = manifest[index]
        converted = _convert_parameter_value(entry, value, T)
        buffer[index] = converted
        assigned[index] = true
    end
    missing = Symbol[
        entry.name for entry in manifest
            if entry.required && !assigned[entry.index]
    ]
    isempty(missing) || throw(
        ArgumentError(
            "missing required runtime parameter$(length(missing) == 1 ? "" : "s"): " *
                join(string.(missing), ", ")
        )
    )
    names = Tuple(entry.name for entry in manifest)
    named = NamedTuple{names}(Tuple(buffer))
    CorePotts.CompilerSPI.validate_parameters(
        plan.core_program.descriptor_plan, buffer
    )
    return PottsParameters(buffer, named)
end

function _convert_parameter_value(entry::RuntimeParameter, value, ::Type{T}) where {
        T <: AbstractFloat,
    }
    converted = if entry.unit === nothing
        _is_quantity(value) && throw(
            ArgumentError(
                "parameter `$(entry.name)` is dimensionless"
            )
        )
        T(_numeric_value(value))
    else
        _is_quantity(value) || throw(
            ArgumentError(
                "parameter `$(entry.name)` requires units compatible with $(entry.unit)"
            )
        )
        T(_numeric_value(value, entry.unit))
    end
    isfinite(converted) ||
        throw(ArgumentError("parameter `$(entry.name)` must be finite"))
    return converted
end
