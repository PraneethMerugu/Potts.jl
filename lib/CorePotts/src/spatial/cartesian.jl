abstract type AbstractBoundaryCondition end

"""A paired axis wraps through the opposite face."""
struct PeriodicBoundary <: AbstractBoundaryCondition end

"""An ownership relation leaving this face realizes no edge."""
struct ClosedBoundary <: AbstractBoundaryCondition end

"""An immutable medium or wall domain beyond one Cartesian face."""
struct FixedExterior <: AbstractBoundaryCondition
    owner::OwnerRef

    function FixedExterior(owner::OwnerRef)
        is_medium_owner(owner) || throw(ArgumentError(
            "fixed exterior owners must be conceptual medium or wall domains"))
        return new(owner)
    end
end

"""Negative and positive face behavior for one Cartesian axis."""
struct AxisBoundary{L <: AbstractBoundaryCondition, U <: AbstractBoundaryCondition}
    negative::L
    positive::U
end

function AxisBoundary(boundary::B) where {B <: AbstractBoundaryCondition}
    AxisBoundary(boundary, boundary)
end

function _periodic_axis_valid(boundary::AxisBoundary)
    negative = boundary.negative isa PeriodicBoundary
    positive = boundary.positive isa PeriodicBoundary
    return negative == positive
end

function _default_boundaries(::Val{N}) where {N}
    return ntuple(_ -> AxisBoundary(PeriodicBoundary()), Val(N))
end

"""
    CartesianDomain(dims; spacing, boundaries, obstacles)

Host scientific description of a rectangular ownership domain. `obstacles` is an iterable of
`site => MediumOwner(...)` pairs. Obstacle sites remain in rectangular storage but are excluded from
the mutable recipient set.
"""
struct CartesianDomain{N, T <: AbstractFloat, B <: Tuple, M <: BitArray{N},
    A <: Array{UInt8, N}, I <: Array{UInt32, N}}
    dims::NTuple{N, Int}
    spacing::SVector{N, T}
    boundaries::B
    mutable_mask::M
    immutable_tags::A
    immutable_ids::I
end

function _obstacle_index(site::Integer, dims::NTuple)
    1 <= site <= prod(dims) || throw(BoundsError(LinearIndices(dims), site))
    return Int(site)
end

function _obstacle_index(site::CartesianIndex{N}, dims::NTuple{N, Int}) where {N}
    checkbounds(Bool, CartesianIndices(dims), site) ||
        throw(BoundsError(CartesianIndices(dims), site))
    return LinearIndices(dims)[site]
end

function _obstacle_index(site::NTuple{N, <:Integer}, dims::NTuple{N, Int}) where {N}
    return _obstacle_index(CartesianIndex(site), dims)
end

function CartesianDomain(dims::NTuple{N, <:Integer};
        spacing = ntuple(_ -> 1.0, Val(N)), boundaries = _default_boundaries(Val(N)),
        obstacles = ()) where {N}
    N in (2, 3) ||
        throw(ArgumentError("Cartesian ownership domains support two or three dimensions"))
    normalized_dims = ntuple(i -> Int(dims[i]), Val(N))
    all(>(0), normalized_dims) ||
        throw(ArgumentError("Cartesian dimensions must be positive"))
    all(<=(typemax(Int32)), normalized_dims) || throw(ArgumentError(
        "Cartesian dimensions must fit the compiled Int32 coordinate representation"))
    site_count = UInt64(1)
    for extent in normalized_dims
        site_count <= UInt64(typemax(UInt32)) ÷ UInt64(extent) || throw(ArgumentError(
            "Cartesian site count must fit the compiled UInt32 site representation"))
        site_count *= UInt64(extent)
    end
    length(boundaries) == N ||
        throw(ArgumentError("one boundary pair is required per axis"))
    boundary_tuple = Tuple(boundaries)
    all(boundary -> boundary isa AxisBoundary, boundary_tuple) || throw(ArgumentError(
        "Cartesian boundaries must be AxisBoundary values"))
    all(_periodic_axis_valid, boundary_tuple) || throw(ArgumentError(
        "periodic boundary faces must occur as a paired axis"))

    T = float(promote_type(map(typeof, spacing)...))
    normalized_spacing = SVector{N, T}(ntuple(i -> convert(T, spacing[i]), Val(N)))
    all(value -> isfinite(value) && value > zero(T), normalized_spacing) ||
        throw(ArgumentError(
            "Cartesian spacing must be positive and finite"))

    mutable_mask = trues(normalized_dims)
    immutable_tags = zeros(UInt8, normalized_dims)
    immutable_ids = zeros(UInt32, normalized_dims)
    for obstacle in obstacles
        obstacle isa Pair || throw(ArgumentError("each obstacle must be `site => owner`"))
        owner = last(obstacle)
        owner isa OwnerRef && is_medium_owner(owner) || throw(ArgumentError(
            "obstacle owners must be conceptual medium or wall domains"))
        index = _obstacle_index(first(obstacle), normalized_dims)
        mutable_mask[index] ||
            throw(ArgumentError("an obstacle site may be declared only once"))
        mutable_mask[index] = false
        immutable_tags[index] = owner.tag
        immutable_ids[index] = owner.value
    end
    any(mutable_mask) ||
        throw(ArgumentError("a Cartesian ownership domain requires a mutable site"))
    return CartesianDomain(
        normalized_dims, normalized_spacing, boundary_tuple, mutable_mask,
        immutable_tags, immutable_ids)
end

mutable_site_count(domain::CartesianDomain) = count(domain.mutable_mask)
domain_dimensions(domain::CartesianDomain) = domain.dims
domain_spacing(domain::CartesianDomain) = Tuple(domain.spacing)
domain_boundaries(domain::CartesianDomain) = domain.boundaries

function immutable_owner(domain::CartesianDomain, site)
    index = _obstacle_index(site, domain.dims)
    domain.mutable_mask[index] && return nothing
    return OwnerRef(domain.immutable_tags[index], domain.immutable_ids[index])
end

"""Device-safe domain metadata required to interpret compiled storage."""
struct CartesianDomainDescriptor{N, T <: AbstractFloat, B <: Tuple}
    dims::NTuple{N, Int32}
    spacing::SVector{N, T}
    boundaries::B
end

"""Device-adaptable mutable-site and immutable-owner domain storage."""
struct CompiledCartesianDomainStorage{M, S, T, I}
    mutable_mask::M
    mutable_sites::S
    immutable_tags::T
    immutable_ids::I
end

function Adapt.adapt_structure(to, storage::CompiledCartesianDomainStorage)
    return CompiledCartesianDomainStorage(
        Adapt.adapt(to, storage.mutable_mask),
        Adapt.adapt(to, storage.mutable_sites),
        Adapt.adapt(to, storage.immutable_tags),
        Adapt.adapt(to, storage.immutable_ids)
    )
end

struct CompiledCartesianDomain{D <: CartesianDomainDescriptor,
    S <: CompiledCartesianDomainStorage}
    descriptor::D
    storage::S
end

function Adapt.adapt_structure(to, domain::CompiledCartesianDomain)
    return CompiledCartesianDomain(domain.descriptor, Adapt.adapt(to, domain.storage))
end

function compile_domain(domain::CartesianDomain)
    device_dims = ntuple(i -> Int32(domain.dims[i]), Val(length(domain.dims)))
    descriptor = CartesianDomainDescriptor(device_dims, domain.spacing, domain.boundaries)
    mutable_sites = UInt32.(findall(vec(domain.mutable_mask)))
    storage = CompiledCartesianDomainStorage(
        UInt8.(domain.mutable_mask), mutable_sites,
        copy(domain.immutable_tags), copy(domain.immutable_ids))
    return CompiledCartesianDomain(descriptor, storage)
end

function domain_storage_valid(storage::CompiledCartesianDomainStorage)
    arrays = (storage.mutable_mask, storage.mutable_sites,
        storage.immutable_tags, storage.immutable_ids)
    all(array -> array isa AbstractArray && isbitstype(eltype(array)), arrays) ||
        return false
    backends = map(KernelAbstractions.get_backend, arrays)
    return all(isequal(first(backends)), backends)
end

_boundary_semantics(::PeriodicBoundary) = (kind = :periodic,)
_boundary_semantics(::ClosedBoundary) = (kind = :closed,)
function _boundary_semantics(boundary::FixedExterior)
    return (kind = :fixed_exterior, owner_kind = :medium, owner_id = boundary.owner.value)
end

"""Host report containing every scientific choice in one Cartesian ownership domain."""
function domain_semantics_report(domain::CartesianDomain)
    obstacles = map(findall(!, vec(domain.mutable_mask))) do site
        owner = OwnerRef(domain.immutable_tags[site], domain.immutable_ids[site])
        (site = site, owner_kind = :medium, owner_id = owner.value)
    end
    return (
        dimensions = length(domain.dims),
        shape = domain.dims,
        spacing = Tuple(domain.spacing),
        boundaries = map(
            axis -> (
                negative = _boundary_semantics(axis.negative),
                positive = _boundary_semantics(axis.positive)),
            domain.boundaries),
        mutable_site_count = mutable_site_count(domain),
        obstacles = Tuple(obstacles)
    )
end

abstract type AbstractSpatialRole end
struct ProposalRole <: AbstractSpatialRole end
struct ContactRole <: AbstractSpatialRole end
struct SurfaceRole <: AbstractSpatialRole end
struct ConnectivityRole <: AbstractSpatialRole end
struct SpatialQueryRole <: AbstractSpatialRole end
struct FieldDiscretizationRole <: AbstractSpatialRole end
struct ConflictRole <: AbstractSpatialRole end

_requires_symmetry(::ProposalRole) = true
_requires_symmetry(::ContactRole) = true
_requires_symmetry(::SurfaceRole) = true
_requires_symmetry(::ConnectivityRole) = true
_requires_symmetry(::ConflictRole) = true
_requires_symmetry(::Union{SpatialQueryRole, FieldDiscretizationRole}) = false

_allows_fixed_owner(::Union{ContactRole, SurfaceRole, SpatialQueryRole}) = true
_allows_fixed_owner(::AbstractSpatialRole) = false

"""Device-safe semantic version for relation canonicalization rules."""
struct RelationCanonicalizationVersion
    major::UInt16
    minor::UInt16
    patch::UInt16
end

function RelationCanonicalizationVersion(version::VersionNumber)
    isempty(version.prerelease) && isempty(version.build) || throw(ArgumentError(
        "relation canonicalization versions cannot contain prerelease or build identifiers"))
    values = (version.major, version.minor, version.patch)
    all(value -> 0 <= value <= typemax(UInt16), values) || throw(ArgumentError(
        "relation canonicalization version components must fit UInt16"))
    return RelationCanonicalizationVersion(UInt16.(values)...)
end

function Base.VersionNumber(version::RelationCanonicalizationVersion)
    VersionNumber(
        Int(version.major), Int(version.minor), Int(version.patch))
end

"""Canonical, isbits Cartesian relation whose direction IDs are semantic."""
struct StaticCartesianRelation{R <: AbstractSpatialRole, N, K, T <: AbstractFloat,
    O <: NTuple{K, SVector{N, Int32}}, W <: SVector{K, T}, P <: SVector{K, UInt16}}
    role::R
    offsets::O
    weights::W
    opposite::P
    symmetric::Bool
    version::RelationCanonicalizationVersion
end

"""Host report preserving role, direction IDs, weights, and canonicalization version."""
function relation_semantics_report(relation::StaticCartesianRelation)
    return (
        role = nameof(typeof(relation.role)),
        dimensions = length(first(relation.offsets)),
        direction_count = direction_count(relation),
        canonicalization_version = canonicalization_version(relation),
        offsets = map(Tuple, relation.offsets),
        weights = Tuple(relation.weights),
        opposite_directions = Tuple(relation.opposite),
        symmetric = relation.symmetric
    )
end

direction_count(::StaticCartesianRelation{R, N, K}) where {R, N, K} = K
function relation_offset(relation::StaticCartesianRelation, direction::Integer)
    relation.offsets[direction]
end
function relation_weight(relation::StaticCartesianRelation, direction::Integer)
    relation.weights[direction]
end
function opposite_direction(relation::StaticCartesianRelation, direction::Integer)
    relation.opposite[direction]
end
function canonicalization_version(relation::StaticCartesianRelation)
    VersionNumber(relation.version)
end

function static_relation(role::R, offsets;
        spacing = nothing, weights = nothing, symmetric::Bool = _requires_symmetry(role),
        canonicalization_version::VersionNumber = v"1.0.0") where {R <: AbstractSpatialRole}
    raw_offsets = collect(offsets)
    isempty(raw_offsets) &&
        throw(ArgumentError("a Cartesian relation requires at least one offset"))
    N = length(first(raw_offsets))
    N in (2, 3) ||
        throw(ArgumentError("Cartesian relation offsets must be two- or three-dimensional"))
    all(offset -> length(offset) == N, raw_offsets) || throw(ArgumentError(
        "every Cartesian relation offset must have the same dimension"))
    converted = [SVector{N, Int32}(Tuple(Int32.(offset))) for offset in raw_offsets]
    all(offset -> any(!iszero, offset), converted) || throw(ArgumentError(
        "Cartesian relation offsets must be nonzero"))
    length(unique(converted)) == length(converted) || throw(ArgumentError(
        "duplicate Cartesian relation offsets are invalid"))

    spacing_values = spacing === nothing ? ntuple(_ -> 1.0, Val(N)) : spacing
    length(spacing_values) == N ||
        throw(ArgumentError("relation spacing dimension mismatch"))
    S = float(promote_type(map(typeof, spacing_values)...))
    physical_spacing = SVector{N, S}(Tuple(S.(spacing_values)))
    all(value -> isfinite(value) && value > zero(S), physical_spacing) ||
        throw(ArgumentError(
            "relation spacing must be positive and finite"))

    raw_weights = weights === nothing ? ones(S, length(converted)) : collect(weights)
    length(raw_weights) == length(converted) || throw(ArgumentError(
        "one relation weight is required per offset"))
    T = float(promote_type(S, map(typeof, raw_weights)...))
    typed_weights = T.(raw_weights)
    all(value -> isfinite(value) && value >= zero(T), typed_weights) || throw(ArgumentError(
        "relation weights must be finite and non-negative"))

    order = sortperm(eachindex(converted);
        by = i -> (sum(abs2, converted[i] .* physical_spacing), Tuple(converted[i])))
    K = length(order)
    canonical_offsets = ntuple(i -> converted[order[i]], K)
    canonical_weights = SVector{K, T}(ntuple(i -> typed_weights[order[i]], K))

    symmetric && all(offset -> -offset in canonical_offsets, canonical_offsets) ||
        !symmetric ||
        throw(ArgumentError("a symmetric relation requires every opposite offset"))
    _requires_symmetry(role) && !symmetric &&
        throw(ArgumentError(
            "$(nameof(R)) requires a symmetric relation"))
    opposite = SVector{K, UInt16}(ntuple(K) do i
        index = findfirst(isequal(-canonical_offsets[i]), canonical_offsets)
        index === nothing ? UInt16(0) : UInt16(index)
    end)
    symmetric && any(iszero, opposite) &&
        error("internal opposite-direction construction failed")
    symmetric &&
        any(
            index -> canonical_weights[index] != canonical_weights[Int(opposite[index])], 1:K) &&
        throw(ArgumentError(
            "a symmetric relation requires equal weights for opposite offsets"))
    version = RelationCanonicalizationVersion(canonicalization_version)
    return StaticCartesianRelation(role, canonical_offsets, canonical_weights, opposite,
        symmetric, version)
end

"""
    static_relation(role, topology; spacing=nothing, weights=nothing)

Construct a canonical spatial relation from a supported Cartesian topology
without exposing its offset representation. `spacing` must match the topology
dimension; `weights`, when supplied, must contain one finite non-negative value
per direction.
"""
function static_relation(
        role::R,
        topology::AbstractTopology{N};
        spacing=nothing,
        weights=nothing,
) where {R<:AbstractSpatialRole,N}
    N in (2, 3) || throw(ArgumentError(
        "Cartesian topology relations support two or three dimensions"))
    resolved_spacing =
        spacing === nothing ? ntuple(_ -> 1.0, Val(N)) : spacing
    return static_relation(
        role,
        offsets(topology);
        spacing=resolved_spacing,
        weights,
        symmetric=_requires_symmetry(role),
    )
end

function first_shell_relation(
        role::AbstractSpatialRole, ::Val{N}; spacing = ntuple(_ -> 1.0, Val(N)),
        weights = nothing, symmetric::Bool = _requires_symmetry(role)) where {N}
    offsets = Tuple(vcat(
        [ntuple(axis -> axis == dimension ? -1 : 0, Val(N)) for dimension in 1:N],
        [ntuple(axis -> axis == dimension ? 1 : 0, Val(N)) for dimension in 1:N]))
    return static_relation(role, offsets; spacing, weights, symmetric)
end

function _normalized_kernel_offsets(::Val{2})
    return Tuple(offset
    for offset in Iterators.product(-2:2, -2:2)
    if 0 < sum(abs2, offset) <= 5 && sum(abs2, offset) != 8)
end

function _normalized_kernel_offsets(::Val{3})
    return Tuple(offset
    for offset in Iterators.product(-2:2, -2:2, -2:2)
    if 0 < sum(abs2, offset) <= 6)
end

"""
    normalized_kernel_relation(Val(N); spacing)

Published square-order-4 (`N == 2`) or cubic-order-6 (`N == 3`) surface stencil. The
corresponding correction factor belongs to `NormalizedKernelMeasure`, not to relation weights.
"""
function normalized_kernel_relation(::Val{N};
        spacing = ntuple(_ -> 1.0, Val(N))) where {N}
    N in (2, 3) || throw(ArgumentError(
        "normalized Cartesian kernels support two or three dimensions"))
    offsets = _normalized_kernel_offsets(Val(N))
    T = float(promote_type(map(typeof, spacing)...))
    weights = ntuple(_ -> one(T), length(offsets))
    return static_relation(SurfaceRole(), offsets; spacing, weights, symmetric = true)
end

@enum NeighborKind::UInt8 begin
    MutableNeighbor = 1
    FixedNeighbor = 2
    ExteriorNeighbor = 3
    AbsentNeighbor = 4
    InvalidNeighbor = 5
end

"""One role-filtered realized neighbor. Fixed owners are carried without a union field."""
struct RealizedNeighbor
    kind::NeighborKind
    site::UInt32
    owner_tag::UInt8
    owner_id::UInt32
end

function fixed_owner(neighbor::RealizedNeighbor)
    neighbor.kind in (FixedNeighbor, ExteriorNeighbor) ?
    OwnerRef(neighbor.owner_tag, neighbor.owner_id) :
    throw(ArgumentError(
        "the realized neighbor does not carry a fixed owner"))
end

@inline _fixed_owner_unchecked(neighbor::RealizedNeighbor) =
    _owner_ref_unchecked(neighbor.owner_tag, neighbor.owner_id)

@inline function _linear_index(coordinates::SVector{N, Int32},
        dims::Tuple{I, Vararg{I}}) where {N, I <: Integer}
    length(dims) == N || throw(DimensionMismatch(
        "coordinate and lattice dimensions differ"))
    index = Int32(0)
    stride = Int32(1)
    for dimension in 1:N
        index += coordinates[dimension] * stride
        stride *= Int32(dims[dimension])
    end
    return Base.unsafe_trunc(UInt32, index + Int32(1))
end

@inline function _site_coordinates(
        site::Integer, dims::Tuple{I, Vararg{I}}) where {I <: Integer}
    N = length(dims)
    coordinates = idx_to_coord(Base.unsafe_trunc(UInt32, site), dims)
    return SVector{N, Int32}(ntuple(
        i -> Base.unsafe_trunc(Int32, coordinates[i]), Val(N)))
end

struct BoundaryResolution{N}
    coordinates::SVector{N, Int32}
    closed::Bool
    fixed::Bool
    invalid::Bool
    owner_tag::UInt8
    owner_id::UInt32
end

@inline function _resolve_face(::PeriodicBoundary, value::Int32, extent::Integer,
        state::BoundaryResolution{N}, ::Val{D}) where {N, D}
    extent32 = Base.unsafe_trunc(Int32, extent)
    wrapped = value
    while wrapped < Int32(0)
        wrapped += extent32
    end
    while wrapped >= extent32
        wrapped -= extent32
    end
    coordinates = setindex(state.coordinates, wrapped, D)
    return BoundaryResolution(coordinates, state.closed, state.fixed, state.invalid,
        state.owner_tag, state.owner_id)
end

@inline function _resolve_face(::ClosedBoundary, value::Int32, extent::Integer,
        state::BoundaryResolution{N}, ::Val{D}) where {N, D}
    return BoundaryResolution(state.coordinates, true, state.fixed,
        state.invalid | state.fixed, state.owner_tag, state.owner_id)
end

@inline function _resolve_face(face::FixedExterior, value::Int32, extent::Integer,
        state::BoundaryResolution{N}, ::Val{D}) where {N, D}
    owner = face.owner
    incompatible_owner = state.fixed &
                         ((state.owner_tag != owner.tag) | (state.owner_id != owner.value))
    return BoundaryResolution(state.coordinates, state.closed, true,
        state.invalid | state.closed | incompatible_owner, owner.tag, owner.value)
end

@inline _resolve_axes(::Tuple{}, candidate::SVector{N, Int32},
    dims::Tuple{I, Vararg{I}},
    state::BoundaryResolution{N}, ::Val{D}) where {N, I <: Integer, D} = state

@inline function _resolve_axes(boundaries::Tuple, candidate::SVector{N, Int32},
        dims::Tuple{I, Vararg{I}}, state::BoundaryResolution{N}, ::Val{D}) where {
        N, I <: Integer, D}
    axis = first(boundaries)
    value = candidate[D]
    next_state = if value < 0
        _resolve_face(axis.negative, value, dims[D], state, Val(D))
    elseif value >= dims[D]
        _resolve_face(axis.positive, value, dims[D], state, Val(D))
    else
        state
    end
    return _resolve_axes(Base.tail(boundaries), candidate, dims, next_state, Val(D + 1))
end

@inline function _realize_neighbor_unchecked(dims::Tuple{I, Vararg{I}}, boundaries,
        mutable_mask, immutable_tags, immutable_ids,
        relation::StaticCartesianRelation{R, N, K, T, O, W, P},
        site::Integer, direction::Integer) where {
        R, N, K, T, O, W, P, I <: Integer}
    # Preconditions are established by CartesianDomain, relation validation, and the caller's
    # checked public boundary. Keeping them out of this path avoids device exception branches.
    coordinates = _site_coordinates(site, dims)
    candidate = coordinates + @inbounds(relation.offsets[direction])
    initial = BoundaryResolution(candidate, false, false, false, UInt8(0), UInt32(0))
    resolution = _resolve_axes(boundaries, candidate, dims, initial, Val(1))
    if resolution.invalid
        return RealizedNeighbor(InvalidNeighbor, 0, 0, 0)
    elseif resolution.closed
        return RealizedNeighbor(AbsentNeighbor, 0, 0, 0)
    elseif resolution.fixed
        _allows_fixed_owner(relation.role) ||
            return RealizedNeighbor(AbsentNeighbor, 0, 0, 0)
        return RealizedNeighbor(ExteriorNeighbor, 0,
            resolution.owner_tag, resolution.owner_id)
    end
    neighbor_site = _linear_index(resolution.coordinates, dims)
    if @inbounds(mutable_mask[neighbor_site]) != 0
        return RealizedNeighbor(MutableNeighbor, neighbor_site, 0, 0)
    elseif _allows_fixed_owner(relation.role)
        return RealizedNeighbor(FixedNeighbor, neighbor_site,
            @inbounds(immutable_tags[neighbor_site]),
            @inbounds(immutable_ids[neighbor_site]))
    else
        return RealizedNeighbor(AbsentNeighbor, 0, 0, 0)
    end
end

@inline function _realize_neighbor(dims::Tuple{I, Vararg{I}}, boundaries, mutable_mask,
        immutable_tags, immutable_ids,
        relation::StaticCartesianRelation{R, N, K, T, O, W, P},
        site::Integer, direction::Integer) where {
        R, N, K, T, O, W, P, I <: Integer}
    1 <= site <= prod(dims) || throw(BoundsError(1:prod(dims), site))
    1 <= direction <= direction_count(relation) ||
        throw(BoundsError(relation.offsets, direction))
    return _realize_neighbor_unchecked(dims, boundaries, mutable_mask,
        immutable_tags, immutable_ids, relation, site, direction)
end

@inline function _realize_neighbor_unchecked(
        domain::Union{CartesianDomain, CompiledCartesianDomain},
        relation::StaticCartesianRelation, site::Integer, direction::Integer)
    if domain isa CartesianDomain
        return _realize_neighbor_unchecked(domain.dims, domain.boundaries,
            domain.mutable_mask, domain.immutable_tags, domain.immutable_ids,
            relation, site, direction)
    end
    return _realize_neighbor_unchecked(domain.descriptor.dims,
        domain.descriptor.boundaries, domain.storage.mutable_mask,
        domain.storage.immutable_tags, domain.storage.immutable_ids,
        relation, site, direction)
end

function realize_neighbor(domain::CartesianDomain, relation::StaticCartesianRelation,
        site::Integer, direction::Integer)
    return _realize_neighbor(domain.dims, domain.boundaries, domain.mutable_mask,
        domain.immutable_tags, domain.immutable_ids, relation, site, direction)
end

function realize_neighbor(
        domain::CompiledCartesianDomain, relation::StaticCartesianRelation,
        site::Integer, direction::Integer)
    return _realize_neighbor(domain.descriptor.dims, domain.descriptor.boundaries,
        domain.storage.mutable_mask, domain.storage.immutable_tags,
        domain.storage.immutable_ids, relation, site, direction)
end

function _validate_relation_geometry(dims, boundaries, relation, ::Val{N},
        ::Val{M}) where {N, M}
    N == M || throw(ArgumentError("relation and Cartesian domain dimensions must match"))
    for site in 1:prod(dims)
        realized_sites = UInt32[]
        for direction in 1:direction_count(relation)
            coordinates = _site_coordinates(site, dims)
            candidate = coordinates + relation_offset(relation, direction)
            initial = BoundaryResolution(candidate, false, false, false, UInt8(0), UInt32(0))
            resolution = _resolve_axes(boundaries, candidate, dims, initial, Val(1))
            resolution.invalid && throw(ArgumentError(
                "a relation crosses incompatible boundary faces at site $site"))
            (resolution.closed || resolution.fixed) && continue
            neighbor_site = _linear_index(resolution.coordinates, dims)
            neighbor_site == site && throw(ArgumentError(
                "a nonzero relation offset realizes a self-edge at site $site"))
            neighbor_site in realized_sites && throw(ArgumentError(
                "distinct relation offsets realize the same neighbor at site $site"))
            push!(realized_sites, neighbor_site)
        end
    end
    return relation
end

"""Reject self-edges, periodic aliases, ambiguous corners, and role/domain dimension mismatch."""
function validate_relation_domain(domain::CartesianDomain{N},
        relation::StaticCartesianRelation{R, M}) where {N, R, M}
    return _validate_relation_geometry(
        domain.dims, domain.boundaries, relation, Val(N), Val(M))
end

function validate_relation_domain(domain::CompiledCartesianDomain{<:CartesianDomainDescriptor{N}},
        relation::StaticCartesianRelation{R, M}) where {N, R, M}
    descriptor = domain.descriptor
    return _validate_relation_geometry(
        descriptor.dims, descriptor.boundaries, relation, Val(N), Val(M))
end
