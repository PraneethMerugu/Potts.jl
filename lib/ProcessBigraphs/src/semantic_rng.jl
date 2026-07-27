const PHILOX4X32_M0 = UInt32(0xD2511F53)
const PHILOX4X32_M1 = UInt32(0xCD9E8D57)
const PHILOX4X32_W0 = UInt32(0x9E3779B9)
const PHILOX4X32_W1 = UInt32(0xBB67AE85)
const SEMANTIC_RNG_ALGORITHM = "philox4x32-10-v1"
const SEMANTIC_RNG_ADDRESS_SCHEMA = "process-bigraph-semantic-address-v1"

struct NormalizedRootSeed
    words::NTuple{4,UInt32}
end

function NormalizedRootSeed(seed::Integer)
    seed >= 0 || _fail(:negative_root_seed, "semantic root seed must be nonnegative")
    seed <= typemax(UInt128) ||
        _fail(:root_seed_overflow, "semantic root seed exceeds 128 bits")
    value = UInt128(seed)
    NormalizedRootSeed(ntuple(index ->
        UInt32((value >> (32 * (index - 1))) & UInt128(0xffffffff)), 4))
end

struct RNGAddress
    model_fingerprint::String
    root_seed::NormalizedRootSeed
    process_identity::String
    logical_time::LogicalTime
    event_identity::String
    lineage_identity::String
    draw_site::String
    draw_index::UInt64
    namespace::Symbol
end

function RNGAddress(
    model_fingerprint::AbstractString,
    root_seed::NormalizedRootSeed,
    process_identity::AbstractString,
    logical_time::LogicalTime,
    event_identity::AbstractString,
    lineage_identity::AbstractString,
    draw_site::Union{AbstractString,Symbol},
    draw_index::Integer;
    namespace::Symbol=:model,
)
    namespace in (:model, :observer) ||
        _fail(:invalid_rng_namespace, "RNG namespace must be model or observer"; namespace)
    draw_index >= 0 || _fail(:negative_draw_index,
        "semantic draw indices must be nonnegative"; draw_index)
    draw_index <= typemax(UInt64) ||
        _fail(:draw_index_overflow, "semantic draw index exceeds UInt64"; draw_index)
    isempty(process_identity) && _fail(:empty_rng_owner,
        "semantic RNG owner cannot be empty")
    isempty(event_identity) && _fail(:empty_rng_event,
        "semantic RNG event identity cannot be empty")
    isempty(lineage_identity) && _fail(:empty_rng_lineage,
        "semantic RNG lineage identity cannot be empty")
    site = String(draw_site)
    isempty(site) && _fail(:empty_draw_site,
        "semantic RNG draw site cannot be empty")
    RNGAddress(
        String(model_fingerprint),
        root_seed,
        String(process_identity),
        logical_time,
        String(event_identity),
        String(lineage_identity),
        site,
        UInt64(draw_index),
        namespace,
    )
end

abstract type AbstractSemanticRNGContext end

struct ModelRNGContext <: AbstractSemanticRNGContext
    model_fingerprint::String
    root_seed::NormalizedRootSeed
    owner::String
    logical_time::LogicalTime
    event_identity::String
end

struct ObserverRNGContext <: AbstractSemanticRNGContext
    model_fingerprint::String
    root_seed::NormalizedRootSeed
    owner::String
    logical_time::LogicalTime
    event_identity::String
end

const SemanticRNGContext = AbstractSemanticRNGContext

@inline function _mulhilo(left::UInt32, right::UInt32)
    value = UInt64(left) * UInt64(right)
    UInt32(value >> 32), UInt32(value & 0xffffffff)
end

function philox4x32_10(
    counter::NTuple{4,UInt32},
    key::NTuple{2,UInt32},
)
    c0, c1, c2, c3 = counter
    k0, k1 = key
    for round in 1:10
        hi0, lo0 = _mulhilo(PHILOX4X32_M0, c0)
        hi1, lo1 = _mulhilo(PHILOX4X32_M1, c2)
        c0, c1, c2, c3 = hi1 ⊻ c1 ⊻ k0, lo1, hi0 ⊻ c3 ⊻ k1, lo0
        if round != 10
            k0 += PHILOX4X32_W0
            k1 += PHILOX4X32_W1
        end
    end
    (c0, c1, c2, c3)
end

function _address_words(address::RNGAddress)
    digest = sha256(canonical_bytes((
        SEMANTIC_RNG_ADDRESS_SCHEMA,
        address.model_fingerprint,
        address.root_seed.words,
        address.process_identity,
        address.logical_time,
        address.event_identity,
        address.lineage_identity,
        address.draw_site,
        address.draw_index,
        address.namespace,
    )))
    word(offset) = UInt32(digest[offset]) |
        (UInt32(digest[offset + 1]) << 8) |
        (UInt32(digest[offset + 2]) << 16) |
        (UInt32(digest[offset + 3]) << 24)
    counter = (word(1), word(5), word(9), word(13))
    key = (
        word(17) ⊻ address.root_seed.words[1] ⊻ address.root_seed.words[3],
        word(21) ⊻ address.root_seed.words[2] ⊻ address.root_seed.words[4],
    )
    counter, key
end

function semantic_words(address::RNGAddress)
    counter, key = _address_words(address)
    philox4x32_10(counter, key)
end

function _counter_add(counter::NTuple{4,UInt32}, lane::UInt64)
    value = UInt64(counter[1]) + (UInt64(counter[2]) << 32)
    low = value + lane
    carry = low < value
    high = UInt64(counter[3]) + (UInt64(counter[4]) << 32) + UInt64(carry)
    (
        UInt32(low & 0xffffffff),
        UInt32(low >> 32),
        UInt32(high & 0xffffffff),
        UInt32(high >> 32),
    )
end

function _semantic_bits(address::RNGAddress, lane::UInt64)
    counter, key = _address_words(address)
    words = philox4x32_10(_counter_add(counter, lane), key)
    (UInt64(words[1]) << 32) | UInt64(words[2])
end

semantic_bits(address::RNGAddress) = _semantic_bits(address, UInt64(0))

function semantic_integer(address::RNGAddress, range::UnitRange{<:Integer})
    isempty(range) && _fail(:empty_rng_range, "semantic integer range cannot be empty")
    lower = Int128(first(range))
    upper = Int128(last(range))
    width = UInt128(upper - lower) + UInt128(1)
    full = UInt128(1) << 64
    width <= full ||
        _fail(:rng_range_overflow, "semantic integer range exceeds UInt64 width")
    limit = full - mod(full, width)
    lane = UInt64(0)
    value = UInt128(0)
    while true
        bits = UInt128(_semantic_bits(address, lane))
        if bits < limit
            value = bits
            break
        end
        lane == typemax(UInt64) &&
            _fail(:rng_rejection_overflow,
                "semantic integer rejection exhausted the lane counter")
        lane += UInt64(1)
    end
    result = lower + Int128(mod(value, width))
    convert(promote_type(typeof(first(range)), typeof(last(range))), result)
end

semantic_uniform(address::RNGAddress) =
    Float64(semantic_bits(address) >> 11) * 0x1.0p-53

function _rng_address(
    context::ModelRNGContext,
    site,
    index;
    lineage::AbstractString="root",
)
    RNGAddress(
        context.model_fingerprint,
        context.root_seed,
        context.owner,
        context.logical_time,
        context.event_identity,
        lineage,
        site,
        index;
        namespace=:model,
    )
end

function _rng_address(
    context::ObserverRNGContext,
    site,
    index;
    lineage::AbstractString="root",
)
    RNGAddress(
        context.model_fingerprint,
        context.root_seed,
        context.owner,
        context.logical_time,
        context.event_identity,
        lineage,
        site,
        index;
        namespace=:observer,
    )
end

semantic_bits(context::AbstractSemanticRNGContext, site, index; lineage="root") =
    semantic_bits(_rng_address(context, site, index; lineage))
semantic_integer(context::AbstractSemanticRNGContext, site, index, range; lineage="root") =
    semantic_integer(_rng_address(context, site, index; lineage), range)
semantic_uniform(context::AbstractSemanticRNGContext, site, index; lineage="root") =
    semantic_uniform(_rng_address(context, site, index; lineage))

function _canonical(io::IO, seed::NormalizedRootSeed)
    write(io, "RS")
    _canonical(io, seed.words)
end

function _canonical(io::IO, address::RNGAddress)
    write(io, "RA")
    _canonical(io, SEMANTIC_RNG_ADDRESS_SCHEMA)
    _canonical(io, address.model_fingerprint)
    _canonical(io, address.root_seed)
    _canonical(io, address.process_identity)
    _canonical(io, address.logical_time)
    _canonical(io, address.event_identity)
    _canonical(io, address.lineage_identity)
    _canonical(io, address.draw_site)
    _canonical(io, address.draw_index)
    _canonical(io, address.namespace)
end
