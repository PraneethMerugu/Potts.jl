# Semantic RNG addressing owned by the compiled program runtime.

@inline function _trajectory_seed(
        seed::UInt64, replica::UInt32, repeat::UInt32
    )
    words = philox4x32_10(
        (
            replica,
            repeat,
            UInt32(0x74747332),
            UInt32(0x706f7474),
        ),
        (seed % UInt32, (seed >> 32) % UInt32),
    )
    return UInt64(words[1]) | (UInt64(words[2]) << 32)
end

@inline function _lifecycle_address(
        stream::RNGStream,
        runtime,
        operation::Integer,
        anchor::Integer,
        generation::Integer,
        occurrence::Integer;
        destination::Bool = false,
        draw::Integer = 0,
    )
    entity_kind = destination ? DestinationEntity :
        anchor > 0 ? CellEntity : ModelEntity
    return RNGAddress(
        stream = stream,
        mcs = runtime.mcs + 1,
        operation = operation,
        entity_kind = entity_kind,
        entity = max(anchor, 0),
        generation = generation,
        invocation = occurrence,
        draw = draw,
    )
end

@inline function _lifecycle_uniform(
        ::Type{T},
        runtime,
        stream::RNGStream,
        operation,
        anchor,
        generation,
        occurrence;
        destination = false,
        draw = 0,
    ) where {T}
    address = _lifecycle_address(
        stream,
        runtime,
        operation,
        anchor,
        generation,
        occurrence;
        destination,
        draw,
    )
    return uniform_open01(
        T,
        Philox4x32x10V2(),
        _trajectory_seed(runtime.seed, runtime.replica, runtime.repeat),
        address,
    )
end

"""Draw a deterministic initialization sample bounded by the supplied limits."""
function initialization_bounded(
        seed::UInt64,
        replica::UInt32,
        repeat::UInt32,
        operation::Integer,
        invocation::Integer,
        bound::Integer,
    )
    1 <= operation <= Int(_RNG_MAX_OPERATION) ||
        throw(ArgumentError("initialization operation is outside the RNG address domain"))
    invocation >= 0 ||
        throw(ArgumentError("initialization invocation must be nonnegative"))
    bound > 0 && bound <= typemax(UInt32) ||
        throw(ArgumentError("initialization draw bound is outside UInt32"))
    operation_offset, draw = divrem(invocation, Int(_RNG_MAX_DRAW) + 1)
    addressed_operation = operation + operation_offset
    addressed_operation <= Int(_RNG_MAX_OPERATION) ||
        throw(ArgumentError("initialization request exceeds the RNG address domain"))
    address = RNGAddress(
        stream = InitializationStream,
        mcs = 0,
        operation = addressed_operation,
        entity_kind = GlobalEntity,
        invocation = 0,
        draw = draw,
    )
    return Int(bounded_uint(
        Philox4x32x10V2(),
        _trajectory_seed(seed, replica, repeat),
        address,
        UInt32(bound),
    )) + 1
end

@inline function _program_address(
        stream::RNGStream, mcs::Int, operation::Integer, entity::Integer;
        subround::Integer = 0, draw::Integer = 0,
    )
    return RNGAddress(
        stream = stream,
        mcs = mcs,
        subround = subround,
        operation = operation,
        entity_kind = SiteEntity,
        entity = entity,
        draw = draw,
    )
end

@inline function _program_bounded(
        runtime, stream::RNGStream, operation, entity, bound;
        subround = 0, draw = 0,
    )
    address = _program_address(
        stream, runtime.mcs + 1, operation, entity; subround, draw
    )
    return Int(bounded_uint(
        Philox4x32x10V2(),
        _trajectory_seed(runtime.seed, runtime.replica, runtime.repeat),
        address,
        UInt32(bound),
    )) + 1
end

@inline function _program_uniform(
        ::Type{T}, runtime, stream::RNGStream, operation, entity;
        subround = 0, draw = 0,
    ) where {T}
    address = _program_address(
        stream, runtime.mcs + 1, operation, entity; subround, draw
    )
    return uniform_open01(
        T,
        Philox4x32x10V2(),
        _trajectory_seed(runtime.seed, runtime.replica, runtime.repeat),
        address,
    )
end
