"""Marker for a versioned mapping from semantic random addresses to bits and distributions."""
abstract type AbstractRNGContract end

"""Accepted Philox4x32 ten-round contract with Potts semantic address packing v1."""
struct Philox4x32x10V1 <: AbstractRNGContract end

rng_contract_version(::Philox4x32x10V1) = RNG_CONTRACT_VERSION

"""Stable 128-bit identity for one extension-owned stochastic namespace."""
struct RNGNamespaceIdentity
    high::UInt64
    low::UInt64
end

function RNGNamespaceIdentity(value::Integer)
    0 <= value <= typemax(UInt128) || throw(ArgumentError(
        "RNG namespace identity must fit UInt128"))
    bits = UInt128(value)
    return RNGNamespaceIdentity(
        UInt64(bits >> 64), bits % UInt64)
end

Base.UInt128(identity::RNGNamespaceIdentity) =
    (UInt128(identity.high) << 64) | UInt128(identity.low)

struct RNGNamespaceCollisionError <: Exception
    left::RNGNamespaceIdentity
    right::RNGNamespaceIdentity
    operation::UInt16
end
function Base.showerror(io::IO, error::RNGNamespaceCollisionError)
    print(io, "RNG extension namespace collision at v1 operation ", error.operation,
        ": 0x", string(UInt128(error.left), base = 16, pad = 32), " and 0x",
        string(UInt128(error.right), base = 16, pad = 32))
end

"""Stable named stream families. Numeric values are part of the RNG contract."""
@enum RNGStream::UInt8 begin
    LayoutPlacementStream = 1
    LayoutPermutationStream = 2
    ProposalRecipientStream = 3
    ProposalDirectionStream = 4
    AcceptanceStream = 5
    LotteryActivationStream = 6
    LotteryPriorityStream = 7
    CheckerboardOrderStream = 8
    AuxiliaryEvolutionStream = 9
    RuleStream = 10
    EventStream = 11
    DivisionOrientationStream = 12
    PropertyInheritanceStream = 13
    StochasticRoundingStream = 14
    TypeTransitionStream = 15
    EnsembleStream = 16
    CheckerboardPriorityStream = 17
    AuxiliaryInitializationStream = 18
    TiledOrderStream = 19
    TiledProposalStream = 20
end

"""Semantic identity domain for an addressed random operation."""
@enum RNGEntityKind::UInt8 begin
    GlobalEntity = 0
    SiteEntity = 1
    CellEntity = 2
    EnsembleEntity = 3
end

const _RNG_MAX_MCS = UInt64(0x0000ffffffffffff)
const _RNG_MAX_OPERATION = UInt16(0x0fff)
const _RNG_MAX_DRAW = UInt16(0x03ff)

"""
    RNGAddress

Complete scheduling-independent coordinates for one block of four random `UInt32` values. Valid
addresses pack injectively into the Philox 128-bit counter for a fixed master seed and cell
generation. `invocation` is the local retry/invocation coordinate; `draw` distinguishes lexical or
algorithmic draws owned by one operation.
"""
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

    function RNGAddress(stream::RNGStream, mcs::UInt64, subround::UInt8,
            operation::UInt16, entity_kind::RNGEntityKind, entity::UInt32,
            generation::UInt64, invocation::UInt8, draw::UInt16)
        mcs <= _RNG_MAX_MCS || throw(ArgumentError(
            "RNG MCS exceeds the v1 48-bit address domain"))
        operation <= _RNG_MAX_OPERATION || throw(ArgumentError(
            "RNG operation ID exceeds the v1 12-bit address domain"))
        draw <= _RNG_MAX_DRAW || throw(ArgumentError(
            "RNG draw ID exceeds the v1 10-bit address domain"))
        entity_kind === CellEntity || generation == 0 || throw(ArgumentError(
            "only cell-addressed randomness may carry a slot generation"))
        return new(stream, mcs, subround, operation, entity_kind, entity, generation,
            invocation, draw)
    end

    function RNGAddress(stream::RNGStream, mcs::UInt64, subround::UInt8,
            operation::UInt16, entity_kind::RNGEntityKind, entity::UInt32,
            generation::UInt64, invocation::UInt8, draw::UInt16, ::Val{:unchecked})
        return new(stream, mcs, subround, operation, entity_kind, entity, generation,
            invocation, draw)
    end
end

@inline function _rng_address_unchecked(stream::RNGStream, mcs::UInt64,
        subround::UInt8, operation::UInt16, entity_kind::RNGEntityKind,
        entity::UInt32, generation::UInt64, invocation::UInt8, draw::UInt16)
    return RNGAddress(stream, mcs, subround, operation, entity_kind, entity,
        generation, invocation, draw, Val(:unchecked))
end

function RNGAddress(; stream::RNGStream, mcs::Integer = 0, subround::Integer = 0,
        operation::Integer = 0, entity_kind::RNGEntityKind = GlobalEntity,
        entity::Integer = 0, generation::Integer = 0, invocation::Integer = 0,
        draw::Integer = 0)
    all(>=(0), (mcs, subround, operation, entity, generation, invocation, draw)) ||
        throw(ArgumentError("RNG address coordinates must be non-negative"))
    mcs <= typemax(UInt64) && subround <= typemax(UInt8) &&
        operation <= typemax(UInt16) && entity <= typemax(UInt32) &&
        generation <= typemax(UInt64) && invocation <= typemax(UInt8) &&
        draw <= typemax(UInt16) || throw(ArgumentError(
        "RNG address coordinate exceeds its storage domain"))
    return RNGAddress(stream, UInt64(mcs), UInt8(subround), UInt16(operation),
        entity_kind, UInt32(entity), UInt64(generation), UInt8(invocation), UInt16(draw))
end

const _PHILOX_M4X32_0 = UInt32(0xd2511f53)
const _PHILOX_M4X32_1 = UInt32(0xcd9e8d57)
const _PHILOX_W32_0 = UInt32(0x9e3779b9)
const _PHILOX_W32_1 = UInt32(0xbb67ae85)
const _RNG_GENERATION_DOMAIN = UInt64(0xd2b74407b1ce6e93)
const _RNG_EXTENSION_DOMAIN = UInt64(0x706f7474732d6578)
const _F32_OPEN_SCALE = Float32(0x1.0p-24)

@inline function _philox_round(counter::NTuple{4, UInt32}, key::NTuple{2, UInt32})
    product0 = widemul(_PHILOX_M4X32_0, counter[1])
    product1 = widemul(_PHILOX_M4X32_1, counter[3])
    high0 = (product0 >> 32) % UInt32
    high1 = (product1 >> 32) % UInt32
    low0 = product0 % UInt32
    low1 = product1 % UInt32
    return (xor(xor(high1, counter[2]), key[1]), low1,
        xor(xor(high0, counter[4]), key[2]), low0)
end

@inline _philox_bump_key(key::NTuple{2, UInt32}) =
    (key[1] + _PHILOX_W32_0, key[2] + _PHILOX_W32_1)

"""Raw Random123-compatible Philox4x32-10 primitive."""
@inline function philox4x32_10(counter::NTuple{4, UInt32}, key::NTuple{2, UInt32})
    value = _philox_round(counter, key)
    key = _philox_bump_key(key)
    value = _philox_round(value, key)
    key = _philox_bump_key(key)
    value = _philox_round(value, key)
    key = _philox_bump_key(key)
    value = _philox_round(value, key)
    key = _philox_bump_key(key)
    value = _philox_round(value, key)
    key = _philox_bump_key(key)
    value = _philox_round(value, key)
    key = _philox_bump_key(key)
    value = _philox_round(value, key)
    key = _philox_bump_key(key)
    value = _philox_round(value, key)
    key = _philox_bump_key(key)
    value = _philox_round(value, key)
    key = _philox_bump_key(key)
    value = _philox_round(value, key)
    return value
end

@inline function philox4x32_10(counter0::UInt64, counter1::UInt64, key::UInt64)
    counter = (counter0 % UInt32, (counter0 >> 32) % UInt32, counter1 % UInt32,
        (counter1 >> 32) % UInt32)
    key_words = (key % UInt32, (key >> 32) % UInt32)
    return philox4x32_10(counter, key_words)
end

# SplitMix64's finalizer is a bijection on UInt64. It domain-separates reused cell generations for
# a fixed master seed without introducing mutable RNG state.
@inline function _rng_mix64(value::UInt64)
    value = xor(value, value >> 30) * UInt64(0xbf58476d1ce4e5b9)
    value = xor(value, value >> 27) * UInt64(0x94d049bb133111eb)
    return xor(value, value >> 31)
end

"""Stable v1 operation slot for a 128-bit extension namespace; collisions are rejected."""
@inline function extension_rng_operation(identity::RNGNamespaceIdentity)
    mixed = _rng_mix64(xor(identity.high, _rng_mix64(identity.low)))
    return UInt16(mixed & UInt64(_RNG_MAX_OPERATION))
end

"""Domain-separated trajectory seed for one extension instance."""
@inline function extension_rng_seed(master_seed::UInt64,
        identity::RNGNamespaceIdentity, instance::UInt64 = UInt64(0))
    return _rng_mix64(xor(master_seed, _RNG_EXTENSION_DOMAIN,
        _rng_mix64(identity.high), _rng_mix64(identity.low), _rng_mix64(instance)))
end
function extension_rng_seed(master_seed::Integer, identity::RNGNamespaceIdentity,
        instance::Integer = 0)
    0 <= master_seed <= typemax(UInt64) || throw(ArgumentError(
        "extension RNG master seed must fit UInt64"))
    0 <= instance <= typemax(UInt64) || throw(ArgumentError(
        "extension RNG instance identity must fit UInt64"))
    return extension_rng_seed(UInt64(master_seed), identity, UInt64(instance))
end

"""Validate and lower extension namespace identities without a runtime registry."""
function compile_rng_namespaces(identities::Tuple)
    seen_identities = Set{UInt128}()
    seen_operations = Dict{UInt16, RNGNamespaceIdentity}()
    operations = map(identities) do identity
        identity isa RNGNamespaceIdentity || throw(ArgumentError(
            "extension RNG namespaces must use RNGNamespaceIdentity"))
        bits = UInt128(identity)
        bits in seen_identities && throw(ArgumentError(
            "duplicate extension RNG namespace 0x$(string(bits, base = 16, pad = 32))"))
        push!(seen_identities, bits)
        operation = extension_rng_operation(identity)
        if haskey(seen_operations, operation)
            throw(RNGNamespaceCollisionError(seen_operations[operation], identity, operation))
        end
        seen_operations[operation] = identity
        operation
    end
    return operations
end

function extension_rng_address(identity::RNGNamespaceIdentity;
        mcs::Integer = 0, subround::Integer = 0,
        entity_kind::RNGEntityKind = GlobalEntity, entity::Integer = 0,
        generation::Integer = 0, invocation::Integer = 0, draw::Integer = 0)
    return RNGAddress(stream = RuleStream, mcs = mcs, subround = subround,
        operation = extension_rng_operation(identity), entity_kind = entity_kind,
        entity = entity, generation = generation, invocation = invocation, draw = draw)
end

"""Pack one valid semantic address into the exact Philox `(counter0, counter1, key)` input."""
@inline function rng_counter_key(::Philox4x32x10V1, master_seed::UInt64,
        address::RNGAddress)
    counter0 = address.mcs |
               (UInt64(address.subround) << 48) |
               (UInt64(address.invocation) << 56)
    counter1 = UInt64(address.entity) |
               (UInt64(address.operation) << 32) |
               (UInt64(address.stream) << 44) |
               (UInt64(address.entity_kind) << 52) |
               (UInt64(address.draw) << 54)
    generation_key = _rng_mix64(xor(address.generation, _RNG_GENERATION_DOMAIN))
    return counter0, counter1, xor(master_seed, generation_key)
end

@inline function rng_words(contract::Philox4x32x10V1, master_seed::UInt64,
        address::RNGAddress)
    counter0, counter1, key = rng_counter_key(contract, master_seed, address)
    return philox4x32_10(counter0, counter1, key)
end

@inline function rng_word(contract::Philox4x32x10V1, master_seed::UInt64,
        address::RNGAddress, lane::Integer = 1)
    1 <= lane <= 4 || throw(ArgumentError("Philox output lane must lie in 1:4"))
    return rng_words(contract, master_seed, address)[lane]
end

"""Portable uniform `Float32` or `Float64` variate strictly inside `(0, 1)`."""
@inline function uniform_open01(::Type{Float32}, contract::Philox4x32x10V1,
        master_seed::UInt64, address::RNGAddress; lane::Integer = 1)
    bits = rng_word(contract, master_seed, address, lane) >> 8
    return (Float32(bits) + 0.5f0) * _F32_OPEN_SCALE
end

@inline function uniform_open01(::Type{Float64}, contract::Philox4x32x10V1,
        master_seed::UInt64, address::RNGAddress; lane::Integer = 1)
    lane in (1, 3) || throw(ArgumentError(
        "Float64 uniform lanes must be 1 or 3 so two adjacent words are available"))
    words = rng_words(contract, master_seed, address)
    bits = (UInt64(words[lane]) << 21) | (UInt64(words[lane + 1]) >> 11)
    return (Float64(bits) + 0.5) * 0x1.0p-53
end

@inline function _with_invocation(address::RNGAddress, invocation::UInt8)
    return _rng_address_unchecked(address.stream, address.mcs, address.subround,
        address.operation, address.entity_kind, address.entity, address.generation,
        invocation, address.draw)
end

"""Unbiased integer in `0:(bound - 1)` using local retry-addressed rejection."""
function bounded_uint(contract::Philox4x32x10V1, master_seed::UInt64,
        address::RNGAddress, bound::UInt32)
    bound > 0 || throw(ArgumentError("bounded integer sampling requires a positive bound"))
    threshold = mod(-bound, bound)
    invocation = address.invocation
    while true
        word = rng_word(contract, master_seed, _with_invocation(address, invocation))
        word >= threshold && return mod(word, bound)
        invocation == typemax(UInt8) && throw(ArgumentError(
            "bounded integer rejection exhausted the v1 invocation domain"))
        invocation += UInt8(1)
    end
end

"""Portable Bernoulli variate with exact boundary behavior."""
@inline function bernoulli(contract::Philox4x32x10V1, master_seed::UInt64,
        address::RNGAddress, probability::T) where {T <: AbstractFloat}
    isfinite(probability) && zero(T) <= probability <= one(T) || throw(ArgumentError(
        "Bernoulli probability must be finite and lie in [0, 1]"))
    probability == zero(T) && return false
    probability == one(T) && return true
    return uniform_open01(T, contract, master_seed, address) < probability
end

"""Box–Muller standard normal; statistically portable because backend transcendentals may differ."""
@inline function normal_box_muller(::Type{Float32}, contract::Philox4x32x10V1,
        master_seed::UInt64, address::RNGAddress; component::Integer = 1)
    component in (1, 2) || throw(ArgumentError("normal component must be 1 or 2"))
    radius_uniform = uniform_open01(Float32, contract, master_seed, address; lane = 1)
    angle_uniform = uniform_open01(Float32, contract, master_seed, address; lane = 2)
    radius = sqrt(-2.0f0 * log(radius_uniform))
    angle = (2.0f0 * Float32(pi)) * angle_uniform
    return component == 1 ? radius * cos(angle) : radius * sin(angle)
end

@inline function normal_box_muller(::Type{Float64}, contract::Philox4x32x10V1,
        master_seed::UInt64, address::RNGAddress; component::Integer = 1)
    component in (1, 2) || throw(ArgumentError("normal component must be 1 or 2"))
    radius_uniform = uniform_open01(Float64, contract, master_seed, address; lane = 1)
    angle_uniform = uniform_open01(Float64, contract, master_seed, address; lane = 3)
    radius = sqrt(-2.0 * log(radius_uniform))
    angle = (2.0 * pi) * angle_uniform
    return component == 1 ? radius * cos(angle) : radius * sin(angle)
end

@inline function _with_draw(address::RNGAddress, draw::UInt16)
    return _rng_address_unchecked(address.stream, address.mcs, address.subround,
        address.operation, address.entity_kind, address.entity, address.generation,
        address.invocation, draw)
end

"""
    poisson_inversion(contract, seed, address, rate)

Exact inversion sampler for `0 ≤ rate ≤ 64`. It is intentionally domain-limited rather than
silently switching algorithms. Each loop iteration owns a distinct local draw address.
"""
function poisson_inversion(contract::Philox4x32x10V1, master_seed::UInt64,
        address::RNGAddress, rate::T) where {T <: AbstractFloat}
    isfinite(rate) && zero(T) <= rate <= T(64) || throw(ArgumentError(
        "poisson_inversion requires a finite rate in [0, 64]"))
    rate == zero(T) && return 0
    threshold = exp(-rate)
    product = one(T)
    count = 0
    draw = Int(address.draw)
    while product > threshold
        draw <= Int(_RNG_MAX_DRAW) || throw(ArgumentError(
            "Poisson inversion exhausted the v1 draw domain"))
        product *= uniform_open01(T, contract, master_seed,
            _with_draw(address, UInt16(draw)))
        count += 1
        draw += 1
    end
    return count - 1
end

"""Separately named nonnegative rounded-normal approximation to Poisson sampling."""
@inline function poisson_normal_approx(contract::Philox4x32x10V1, master_seed::UInt64,
        address::RNGAddress, rate::T) where {T <: AbstractFloat}
    isfinite(rate) && rate >= zero(T) || throw(ArgumentError(
        "approximate Poisson rate must be finite and non-negative"))
    rate == zero(T) && return 0
    draw = rate + sqrt(rate) * normal_box_muller(T, contract, master_seed, address)
    return max(0, round(Int, draw))
end

"""Validated immutable categorical cumulative weights suitable for compiled execution."""
struct CategoricalTable{T, N}
    cumulative::NTuple{N, T}
    total::T
end

function CategoricalTable(weights::Tuple{T, Vararg{T}}) where {T <: AbstractFloat}
    N = length(weights)
    all(weight -> isfinite(weight) && weight >= zero(T), weights) || throw(ArgumentError(
        "categorical weights must be finite and non-negative"))
    total = sum(weights)
    total > zero(T) || throw(ArgumentError("categorical weights must have positive total mass"))
    running = zero(T)
    cumulative = ntuple(N) do index
        running += weights[index]
        running
    end
    return CategoricalTable{T, N}(cumulative, total)
end

function CategoricalTable(weights::AbstractVector{T}) where {T <: AbstractFloat}
    return CategoricalTable(Tuple(weights))
end

"""One-based categorical index from a prevalidated immutable table."""
@inline function categorical_index(table::CategoricalTable{T, N},
        contract::Philox4x32x10V1, master_seed::UInt64,
        address::RNGAddress) where {T, N}
    target = uniform_open01(T, contract, master_seed, address) * table.total
    for index in 1:N
        target < table.cumulative[index] && return index
    end
    return N
end

"""
    small_permutation!(destination, contract, seed, address)

Exact Fisher–Yates permutation for small scientific schedules such as checkerboard colors. The
destination length is limited by the v1 draw domain; large layout permutations use a separately
compiled primitive.
"""
function small_permutation!(destination::AbstractVector{I}, contract::Philox4x32x10V1,
        master_seed::UInt64, address::RNGAddress) where {I <: Integer}
    length(destination) <= Int(_RNG_MAX_DRAW) + 2 || throw(ArgumentError(
        "small permutation exceeds the v1 draw domain"))
    for index in eachindex(destination)
        destination[index] = I(index)
    end
    base_draw = Int(address.draw)
    for index in length(destination):-1:2
        draw = base_draw + length(destination) - index
        draw <= Int(_RNG_MAX_DRAW) || throw(ArgumentError(
            "small permutation exhausted the v1 draw domain"))
        selected = Int(bounded_uint(contract, master_seed,
            _with_draw(address, UInt16(draw)), UInt32(index))) + 1
        destination[index], destination[selected] = destination[selected], destination[index]
    end
    return destination
end

distribution_profile(::Philox4x32x10V1, ::typeof(uniform_open01)) =
    (distribution = :uniform_open01, exact = true, portability = :bitwise)
distribution_profile(::Philox4x32x10V1, ::typeof(bounded_uint)) =
    (distribution = :bounded_uint, exact = true, portability = :bitwise)
distribution_profile(::Philox4x32x10V1, ::typeof(bernoulli)) =
    (distribution = :bernoulli, exact = true, portability = :bitwise)
distribution_profile(::Philox4x32x10V1, ::typeof(categorical_index)) =
    (distribution = :categorical, exact = true, portability = :bitwise)
distribution_profile(::Philox4x32x10V1, ::typeof(small_permutation!)) =
    (distribution = :small_permutation, exact = true, portability = :bitwise)
distribution_profile(::Philox4x32x10V1, ::typeof(normal_box_muller)) =
    (distribution = :normal_box_muller, exact = false, portability = :statistical)
distribution_profile(::Philox4x32x10V1, ::typeof(poisson_inversion)) =
    (distribution = :poisson_inversion, exact = true, portability = :statistical,
        rate_domain = (0, 64))
distribution_profile(::Philox4x32x10V1, ::typeof(poisson_normal_approx)) =
    (distribution = :poisson_normal_approx, exact = false, portability = :statistical)
