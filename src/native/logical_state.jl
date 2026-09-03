"""Logical, solver-independent state of one native component boundary."""
struct NativeLogicalState{P <: Tuple, U <: Tuple, Q <: Tuple, D, T}
    path::P
    u::U
    p::Q
    du::D
    t::T
    retcode::SciMLBase.ReturnCode.T
end

function _native_logical_value(value, path, label)
    if value isa AbstractFloat
        isfinite(value) || throw(NativeCapabilityError(
            path, :logical_checkpoint,
            "$label contains a nonfinite floating-point value",
        ))
        return value
    elseif value isa Union{Bool, Integer, Symbol, AbstractString, Enum}
        return value
    elseif value isa Tuple
        return map(item -> _native_logical_value(item, path, label), value)
    elseif value isa NamedTuple
        mapped = map(
            item -> _native_logical_value(item, path, label), values(value)
        )
        return NamedTuple{keys(value)}(mapped)
    elseif value isa AbstractArray
        isbitstype(eltype(value)) || throw(NativeCapabilityError(
            path, :logical_checkpoint,
            "$label array has non-isbits element type $(eltype(value))",
        ))
        all(item -> !(item isa AbstractFloat) || isfinite(item), value) ||
            throw(NativeCapabilityError(
                path, :logical_checkpoint,
                "$label array contains a nonfinite floating-point value",
            ))
        return copy(value)
    end
    throw(NativeCapabilityError(
        path,
        :logical_checkpoint,
        "$label has unsupported logical value type $(typeof(value))",
    ))
end

function NativeLogicalState(path, u, p, du, t, retcode)
    normalized_path = _qualified_native_path(path, "NativeLogicalState")
    u isa Tuple || throw(NativeCapabilityError(
        normalized_path, :logical_state, "state values must use scheduled tuple order"
    ))
    p isa Tuple || throw(NativeCapabilityError(
        normalized_path, :logical_state, "parameter values must use scheduled tuple order"
    ))
    normalized_u = _native_logical_value(u, normalized_path, "u")
    normalized_p = _native_logical_value(p, normalized_path, "p")
    normalized_du = du === nothing ? nothing :
                    _native_logical_value(du, normalized_path, "du")
    normalized_t = _native_logical_value(t, normalized_path, "time")
    retcode isa SciMLBase.ReturnCode.T || throw(ArgumentError(
        "native logical state requires a SciML ReturnCode"
    ))
    return NativeLogicalState(
        normalized_path,
        normalized_u,
        normalized_p,
        normalized_du,
        normalized_t,
        retcode,
    )
end
