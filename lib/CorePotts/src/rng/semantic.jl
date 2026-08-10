"""The immutable Philox contract used by V1 compiled programs."""
struct Philox4x32x10V1 end

# Values 3–5 preserve the accepted V1 semantic-address contract.
@enum RNGStream::UInt8 begin
    ProposalRecipientStream = 3
    ProposalDirectionStream = 4
    AcceptanceStream = 5
    ExplicitProposalDrawStream = 6
    InitializationStream = 7
    CheckerboardPriorityStream = 8
    LifecycleTriggerStream = 9
    LifecyclePlacementStream = 10
    LifecyclePartitionStream = 11
    LifecycleStateStream = 12
    CheckerboardColorOrderStream = 13
end

@enum RNGEntityKind::UInt8 begin
    GlobalEntity = 0
    SiteEntity = 1
    ModelEntity = 2
    CellEntity = 3
    DestinationEntity = 4
end

const _RNG_MAX_MCS = UInt64(0x0000ffffffffffff)
const _RNG_MAX_OPERATION = UInt16(0x0fff)
const _RNG_MAX_DRAW = UInt16(0x03ff)
const _PHILOX_M4X32_0 = UInt32(0xd2511f53)
const _PHILOX_M4X32_1 = UInt32(0xcd9e8d57)
const _PHILOX_W32_0 = UInt32(0x9e3779b9)
const _PHILOX_W32_1 = UInt32(0xbb67ae85)
const _RNG_GENERATION_DOMAIN = UInt64(0xd2b74407b1ce6e93)
const _F32_OPEN_SCALE = Float32(0x1.0p-24)

"""Largest operation identity admitted by the versioned V1 RNG address."""
rng_operation_limit(::Philox4x32x10V1 = Philox4x32x10V1()) =
    _RNG_MAX_OPERATION

struct RNGAddress
    stream::RNGStream
    mcs::UInt64
    subround::UInt8
    operation::UInt16
    entity_kind::RNGEntityKind
    entity::UInt32
    generation::UInt64
    invocation::UInt8
    draw::UInt16

    function RNGAddress(
            stream::RNGStream,
            mcs::UInt64,
            subround::UInt8,
            operation::UInt16,
            entity_kind::RNGEntityKind,
            entity::UInt32,
            generation::UInt64,
            invocation::UInt8,
            draw::UInt16,
        )
        mcs <= _RNG_MAX_MCS ||
            throw(ArgumentError("RNG MCS exceeds the V1 address domain"))
        operation <= _RNG_MAX_OPERATION ||
            throw(ArgumentError("RNG operation exceeds the V1 address domain"))
        draw <= _RNG_MAX_DRAW ||
            throw(ArgumentError("RNG draw exceeds the V1 address domain"))
        entity_kind in (SiteEntity, CellEntity, DestinationEntity) ||
            generation == 0 || throw(ArgumentError(
                "only site, cell, or destination addresses may carry a generation"
            ))
        return new(
            stream,
            mcs,
            subround,
            operation,
            entity_kind,
            entity,
            generation,
            invocation,
            draw,
        )
    end

    function RNGAddress(
            stream::RNGStream,
            mcs::UInt64,
            subround::UInt8,
            operation::UInt16,
            entity_kind::RNGEntityKind,
            entity::UInt32,
            generation::UInt64,
            invocation::UInt8,
            draw::UInt16,
            ::Val{:unchecked},
        )
        return new(
            stream,
            mcs,
            subround,
            operation,
            entity_kind,
            entity,
            generation,
            invocation,
            draw,
        )
    end
end

function RNGAddress(;
        stream::RNGStream,
        mcs::Integer = 0,
        subround::Integer = 0,
        operation::Integer = 0,
        entity_kind::RNGEntityKind = GlobalEntity,
        entity::Integer = 0,
        generation::Integer = 0,
        invocation::Integer = 0,
        draw::Integer = 0,
    )
    all(>=(0), (mcs, subround, operation, entity, generation, invocation, draw)) ||
        throw(ArgumentError("RNG address coordinates must be nonnegative"))
    mcs <= typemax(UInt64) && subround <= typemax(UInt8) &&
        operation <= typemax(UInt16) && entity <= typemax(UInt32) &&
        generation <= typemax(UInt64) && invocation <= typemax(UInt8) &&
        draw <= typemax(UInt16) ||
        throw(ArgumentError("RNG address coordinate exceeds its storage domain"))
    return RNGAddress(
        stream,
        UInt64(mcs),
        UInt8(subround),
        UInt16(operation),
        entity_kind,
        UInt32(entity),
        UInt64(generation),
        UInt8(invocation),
        UInt16(draw),
    )
end

@inline function _rng_address_unchecked(
        stream,
        mcs,
        subround,
        operation,
        entity_kind,
        entity,
        generation,
        invocation,
        draw,
    )
    return RNGAddress(
        stream,
        mcs,
        subround,
        operation,
        entity_kind,
        entity,
        generation,
        invocation,
        draw,
        Val(:unchecked),
    )
end

@inline function _philox_round(
        counter::NTuple{4, UInt32}, key::NTuple{2, UInt32}
    )
    product0 = widemul(_PHILOX_M4X32_0, counter[1])
    product1 = widemul(_PHILOX_M4X32_1, counter[3])
    high0 = (product0 >> 32) % UInt32
    high1 = (product1 >> 32) % UInt32
    low0 = product0 % UInt32
    low1 = product1 % UInt32
    return (
        xor(xor(high1, counter[2]), key[1]),
        low1,
        xor(xor(high0, counter[4]), key[2]),
        low0,
    )
end

@inline _philox_bump_key(key::NTuple{2, UInt32}) =
    (key[1] + _PHILOX_W32_0, key[2] + _PHILOX_W32_1)

@inline function philox4x32_10(
        counter::NTuple{4, UInt32}, key::NTuple{2, UInt32}
    )
    value = counter
    round_key = key
    for _ in 1:10
        value = _philox_round(value, round_key)
        round_key = _philox_bump_key(round_key)
    end
    return value
end

@inline function _rng_mix64(value::UInt64)
    value = xor(value, value >> 30) * UInt64(0xbf58476d1ce4e5b9)
    value = xor(value, value >> 27) * UInt64(0x94d049bb133111eb)
    return xor(value, value >> 31)
end

@inline function _rng_words(
        ::Philox4x32x10V1, master_seed::UInt64, address::RNGAddress
    )
    counter0 = address.mcs |
               (UInt64(address.subround) << 48) |
               (UInt64(address.invocation) << 56)
    counter1 = UInt64(address.entity) |
               (UInt64(address.operation) << 32) |
               (UInt64(address.stream) << 44) |
               (UInt64(address.entity_kind) << 52) |
               (UInt64(address.draw) << 54)
    generation_key =
        _rng_mix64(xor(address.generation, _RNG_GENERATION_DOMAIN))
    key = xor(master_seed, generation_key)
    counter = (
        counter0 % UInt32,
        (counter0 >> 32) % UInt32,
        counter1 % UInt32,
        (counter1 >> 32) % UInt32,
    )
    key_words = (key % UInt32, (key >> 32) % UInt32)
    return philox4x32_10(counter, key_words)
end

@inline function _rng_word(
        contract::Philox4x32x10V1,
        master_seed::UInt64,
        address::RNGAddress,
        lane::Integer = 1,
    )
    1 <= lane <= 4 ||
        throw(ArgumentError("Philox output lane must lie in 1:4"))
    return _rng_words(contract, master_seed, address)[lane]
end

@inline function uniform_open01(
        ::Type{Float32},
        contract::Philox4x32x10V1,
        master_seed::UInt64,
        address::RNGAddress,
    )
    bits = _rng_word(contract, master_seed, address) >> 8
    return (Float32(bits) + 0.5f0) * _F32_OPEN_SCALE
end

@inline function uniform_open01(
        ::Type{Float64},
        contract::Philox4x32x10V1,
        master_seed::UInt64,
        address::RNGAddress,
    )
    words = _rng_words(contract, master_seed, address)
    bits = (UInt64(words[1]) << 21) | (UInt64(words[2]) >> 11)
    return (Float64(bits) + 0.5) * 0x1.0p-53
end

@inline function _with_invocation(
        address::RNGAddress, invocation::UInt8
    )
    return _rng_address_unchecked(
        address.stream,
        address.mcs,
        address.subround,
        address.operation,
        address.entity_kind,
        address.entity,
        address.generation,
        invocation,
        address.draw,
    )
end

function bounded_uint(
        contract::Philox4x32x10V1,
        master_seed::UInt64,
        address::RNGAddress,
        bound::UInt32,
    )
    bound > 0 ||
        throw(ArgumentError("bounded sampling requires a positive bound"))
    threshold = mod(-bound, bound)
    invocation = address.invocation
    while true
        word = _rng_word(
            contract, master_seed, _with_invocation(address, invocation)
        )
        word >= threshold && return mod(word, bound)
        invocation == typemax(UInt8) &&
            throw(ArgumentError("bounded rejection exhausted the V1 address domain"))
        invocation += UInt8(1)
    end
end
