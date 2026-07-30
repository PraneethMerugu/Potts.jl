function _parameter_name(parameter)
    return try
        Symbol(Symbolics.getname(Symbolics.unwrap(parameter)))
    catch
        throw(ArgumentError("runtime parameters require a stable symbolic name"))
    end
end

_is_quantity(value) = value isa DynamicQuantities.UnionAbstractQuantity

function _quantity_unit(value)
    _is_quantity(value) || return nothing
    one_value = one(DynamicQuantities.ustrip(value))
    return value / DynamicQuantities.ustrip(value == zero(value) ? one_value * oneunit(value) : value)
end

function _numeric_value(value, reference = nothing)
    if _is_quantity(value)
        return reference === nothing ?
               DynamicQuantities.ustrip(value) :
               DynamicQuantities.ustrip(reference, value)
    elseif value isa Real
        return value
    end
    unwrapped = try
        Symbolics.value(value)
    catch
        value
    end
    unwrapped isa Real ||
        throw(ArgumentError("expected a concrete numerical value, got $(repr(value))"))
    return unwrapped
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
    entries = RuntimeParameter[]
    names = Set{Symbol}()
    for (index, parameter) in enumerate(ModelingToolkitBase.parameters(system))
        name = _parameter_name(parameter)
        name in names &&
            throw(ArgumentError("duplicate runtime parameter name `$name`"))
        push!(names, name)
        default, required = _parameter_default(parameter)
        unit = _is_quantity(default) ? _quantity_unit(default) : nothing
        converted = required ? nothing : T(_numeric_value(default))
        push!(entries, RuntimeParameter(
            parameter, name, converted, required, unit, index
        ))
    end
    return ParameterManifest(Tuple(entries))
end

function _parameter_index(manifest::ParameterManifest, value)
    return findfirst(entry -> isequal(entry.variable, value), manifest.entries)
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
    return CorePotts.CompiledScalar(T(_numeric_value(value, reference)))
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
        index === nothing &&
            throw(ArgumentError("unknown runtime parameter $(repr(key))"))
        assigned[index] &&
            throw(ArgumentError("duplicate runtime parameter $(repr(key))"))
        entry = manifest[index]
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

