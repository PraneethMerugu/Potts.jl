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
        reference isa ReferenceUnitDescriptor || throw(ArgumentError(
            "a dimensional value requires a compiled reference-unit descriptor"
        ))
        dimension = string(DynamicQuantities.dimension(value))
        dimension == reference.dimension || throw(ArgumentError(
            "expected dimensions $(reference.dimension), got $dimension"
        ))
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
    _is_quantity(anchor) || throw(ArgumentError(
        "reference unit `$name` must be a DynamicQuantities quantity"
    ))
    scale = abs(Float64(DynamicQuantities.ustrip(anchor)))
    scale > 0 && isfinite(scale) || throw(ArgumentError(
        "reference unit `$name` must have a finite nonzero scale"
    ))
    return ReferenceUnitDescriptor(
        name, string(DynamicQuantities.dimension(anchor)), scale
    )
end

function _declared_reference_anchors(system::PottsSystem)
    anchors = Pair{Symbol, Any}[]
    for statement in _all_system_statements(system)
        if statement isa LatticeDomain
            spacing = _statement_option(statement, :spacing, ())
            for (index, value) in enumerate(spacing)
                _is_quantity(value) &&
                    push!(anchors, Symbol(:length_axis_, index) => value)
            end
        elseif statement isa Protocol
            for stage in _statement_arguments(statement).stages
                stage isa SweepStage || continue
                haskey(stage.options, :temperature) &&
                    _is_quantity(stage.options.temperature) &&
                    push!(anchors, :energy => stage.options.temperature)
            end
            duration = _statement_option(
                statement, :duration_per_mcs, nothing
            )
            _is_quantity(duration) &&
                push!(
                    anchors,
                    Symbol(:time_, statement_id(statement)) => duration,
                )
        elseif statement isa EquationProcess
            duration = _statement_option(
                statement, :duration_per_mcs, nothing
            )
            _is_quantity(duration) &&
                push!(
                    anchors,
                    Symbol(:time_, statement_id(statement)) => duration,
                )
        elseif statement isa Union{
                SiteState, CellState, MediumState, ModelState, FieldState, HistoryState
            }
            initial = _statement_arguments(statement).initial
            _is_quantity(initial) &&
                push!(anchors, Symbol(:state_, statement_id(statement)) => initial)
        end
    end
    return anchors
end

function _build_reference_descriptors(system::PottsSystem)
    option = _completion_data(system).reference_units
    anchors = if option isa ReferenceUnits
        Pair{Symbol, Any}[
            name => getproperty(option.values, name) for name in keys(option.values)
        ]
    else
        _declared_reference_anchors(system)
    end
    descriptors = ReferenceUnitDescriptor[]
    by_dimension = Dict{String, ReferenceUnitDescriptor}()
    for (name, anchor) in anchors
        descriptor = _reference_descriptor(name, anchor)
        existing = get(by_dimension, descriptor.dimension, nothing)
        if existing !== nothing && existing.scale != descriptor.scale
            throw(ArgumentError(
                "ambiguous declared reference scale for dimension " *
                "$(descriptor.dimension): $(existing.name) and $(descriptor.name); " *
                "supply ReferenceUnits(...) explicitly"
            ))
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
    index === nothing && throw(ArgumentError(
        "no reference-unit anchor was declared for dimension $dimension"
    ))
    return reference_units[index]
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
    entries = RuntimeParameter[]
    names = Set{Symbol}()
    for (index, parameter) in enumerate(ModelingToolkitBase.parameters(system))
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
        for entry in _completion_data(system).parameter_roles.structural
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
        return CorePotts.CompiledScalar(fallback, index)
    end
    variables = try
        Symbolics.get_variables(value)
    catch
        ()
    end
    isempty(variables) || throw(ArgumentError(
        "runtime numerical expressions must be a literal or one declared parameter; " *
        "got $(repr(value))"
    ))
    resolved_reference = reference === nothing ?
                         _reference_for(manifest.reference_units, value) :
                         reference
    return CorePotts.CompiledScalar(T(_numeric_value(value, resolved_reference)))
end

function _default_parameter_buffer(manifest::ParameterManifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    return T[
        entry.required ? zero(T) : T(entry.default)
        for entry in manifest
    ]
end

function _normalize_parameter_pairs(values)
    values === nothing && return Pair[]
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
        executable::PottsExecutable, values
    )
    manifest = executable.parameter_manifest
    T = eltype(executable.core_program.parameter_defaults)
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
            throw(ArgumentError(
                "parameter `$structural_name` is structural; substitute it on " *
                "the incomplete system and recompile"
            ))
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
    isempty(missing) || throw(ArgumentError(
        "missing required runtime parameter$(length(missing) == 1 ? "" : "s"): " *
        join(string.(missing), ", ")
    ))
    names = Tuple(entry.name for entry in manifest)
    named = NamedTuple{names}(Tuple(buffer))
    return PottsParameters(buffer, named)
end

function _convert_parameter_value(entry::RuntimeParameter, value, ::Type{T}) where {
        T <: AbstractFloat,
    }
    converted = if entry.unit === nothing
        _is_quantity(value) && throw(ArgumentError(
            "parameter `$(entry.name)` is dimensionless"
        ))
        T(_numeric_value(value))
    else
        _is_quantity(value) || throw(ArgumentError(
            "parameter `$(entry.name)` requires units compatible with $(entry.unit)"
        ))
        T(_numeric_value(value, entry.unit))
    end
    isfinite(converted) ||
        throw(ArgumentError("parameter `$(entry.name)` must be finite"))
    return converted
end
