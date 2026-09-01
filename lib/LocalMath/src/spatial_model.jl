# Cold semantic descriptors for the LocalMath spatial waist. These values own
# identity and mathematical structure only. Storage, backends, prepared views,
# and runtime validation state belong to binding and preparation.

const _MAX_STATIC_COMPOSED_RELATION_DEGREE = 1024

_new_semantic_identity() = UUIDs.uuid4()

# One conservative storage-value predicate shared by semantic Fields and the
# stage model.  It deliberately excludes pointer/reference and metadata-rich
# values even when Julia reports them as isbits.
_storage_value_type(::Type{T}) where {T<:Union{Number,Bool,Enum}} =
    isconcretetype(T) && isbitstype(T)
@generated function _storage_value_type(::Type{T}) where {T<:Tuple}
    qualified = isconcretetype(T) && isbitstype(T) &&
        all(_storage_value_type, fieldtypes(T))
    return qualified ? :(true) : :(false)
end
function _storage_value_type(::Type{T}) where {T<:StaticArrays.StaticArray}
    isconcretetype(T) && isbitstype(T) || return false
    dimensions = Tuple(StaticArrays.Size(T))
    all(dimension -> 0 <= dimension <= 32, dimensions) || return false
    return _storage_value_type(eltype(T))
end

function _storage_type_parameter(value)
    value isa Bool && return true
    value isa Integer && return 0 <= value <= 32
    value isa Tuple && return all(_storage_type_parameter, value)
    value isa Type && return _storage_value_type(value)
    return false
end

@generated function _storage_value_type(::Type{T}) where {T}
    qualified = isconcretetype(T) && isbitstype(T) &&
        !(T <: Union{
            Symbol,UUIDs.UUID,Ptr,Ref,AbstractArray,NamedTuple,Val,Function,
        }) &&
        !(isdefined(Core, :LLVMPtr) && T <: Core.LLVMPtr) &&
        isstructtype(T) &&
        all(_storage_type_parameter, T.parameters) &&
        all(_storage_value_type, fieldtypes(T))
    return qualified ? :(true) : :(false)
end

function _checked_semantic_int(value::Integer, purpose::Symbol; positive = false)
    converted = try
        Int(value)
    catch
        throw(LocalMathValidationError(
            "$purpose does not fit the host index type";
            stage = :construct, contract = purpose,
            expected = :representable_integer, actual = value,
        ))
    end
    lower = positive ? 1 : 0
    lower <= converted <= typemax(Int32) || throw(LocalMathValidationError(
        "$purpose is outside the common Int32 execution-index ABI";
        stage = :construct, contract = purpose,
        expected = positive ? (1:typemax(Int32)) : (0:typemax(Int32)),
        actual = value,
    ))
    return converted
end

function _checked_semantic_product(values, purpose::Symbol)
    product = 1
    for value in values
        product = try
            Base.checked_mul(product, Int(value))
        catch
            throw(LocalMathValidationError(
                "$purpose overflows the common execution-index ABI";
                stage = :construct, contract = purpose,
                expected = 0:typemax(Int32), actual = values,
            ))
        end
        product <= typemax(Int32) || throw(LocalMathValidationError(
            "$purpose exceeds the common Int32 execution-index ABI";
            stage = :construct, contract = purpose,
            expected = 0:typemax(Int32), actual = product,
        ))
    end
    return product
end

function _checked_schema_epoch(value::Integer)
    value >= 0 || throw(LocalMathValidationError(
        "a relation schema epoch must be nonnegative";
        stage = :construct, contract = :relation_schema_epoch,
        expected = :uint64, actual = value,
    ))
    return try
        UInt64(value)
    catch
        throw(LocalMathValidationError(
            "a relation schema epoch does not fit UInt64";
            stage = :construct, contract = :relation_schema_epoch,
            expected = :uint64, actual = value,
        ))
    end
end

struct _PlainSpaceStructure end
struct _IndexSpaceKind end
struct _ProductSpaceKind end
struct _ProductSpaceStructure{F}
    factors::F
end

"""A typed finite semantic index domain with stable value-level identity."""
struct Space{K,N,S}
    id::UUIDs.UUID
    extent::NTuple{N,Int}
    structure::S
end

function Space(
        ::Type{K}, extent::Tuple{Vararg{Integer,N}};
        id::UUIDs.UUID = _new_semantic_identity(),
        structure = _PlainSpaceStructure(),
    ) where {K,N}
    N > 0 || throw(LocalMathValidationError(
        "a Space must have at least one dimension";
        stage = :construct, contract = :space_dimension,
        expected = :positive, actual = N,
    ))
    canonical = ntuple(
        axis -> _checked_semantic_int(extent[axis], :space_extent), Val(N)
    )
    _checked_semantic_product(canonical, :space_cardinality)
    return Space{K,N,typeof(structure)}(id, canonical, structure)
end

Space(::Type{K}, extent::Integer; kwargs...) where {K} =
    Space(K, (extent,); kwargs...)

"""Construct an ordinary anonymous finite index space."""
Space(extent::Tuple{Integer,Vararg{Integer}}; kwargs...) =
    Space(_IndexSpaceKind, extent; kwargs...)
Space(::Tuple{}; kwargs...) = Space(_IndexSpaceKind, (); kwargs...)
Space(extent::Integer; kwargs...) = Space(_IndexSpaceKind, extent; kwargs...)

_IndexSpace(extent; id::UUIDs.UUID = _new_semantic_identity()) =
    Space(_IndexSpaceKind, extent; id)

function _ProductSpace(
        factors::Tuple; id::UUIDs.UUID = _new_semantic_identity()
    )
    isempty(factors) && throw(LocalMathValidationError(
        "a product Space requires at least one factor";
        stage = :construct, contract = :product_space_factors,
        expected = :nonempty_space_tuple, actual = factors,
    ))
    all(factor -> factor isa Space, factors) || throw(LocalMathValidationError(
        "every product-space factor must be a Space";
        stage = :construct, contract = :product_space_factors,
        expected = Space, actual = map(typeof, factors),
    ))
    cardinality = _checked_semantic_product(
        map(length, factors), :product_space_cardinality
    )
    return Space(
        _ProductSpaceKind, cardinality;
        id, structure = _ProductSpaceStructure(factors),
    )
end

"""
    Space(factors::Tuple{Vararg{Space}})

Construct the Cartesian product of a nonempty tuple of finite spaces. Its
cardinality is the product of the factor cardinalities, and factor order is the
coordinate order used by `ProductRelation`.
"""
Space(factors::Tuple{Space,Vararg{Space}}; kwargs...) = _ProductSpace(factors; kwargs...)

semantic_identity(space::Space) = space.id
space_kind(::Space{K}) where {K} = K
Base.size(space::Space) = space.extent
Base.length(space::Space) = _checked_semantic_product(
    space.extent, :space_cardinality
)
_space_factors(space::Space{_ProductSpaceKind}) = space.structure.factors

function Base.:(==)(first::Space, second::Space)
    return first.id == second.id &&
        space_kind(first) === space_kind(second) &&
        first.extent == second.extent && first.structure == second.structure
end
Base.hash(space::Space, seed::UInt) = hash(
    (space.id, space_kind(space), space.extent, space.structure), seed
)

"""Exact isbits element placement on a semantic `Space`; never storage."""
struct Field{T,S<:Space}
    id::UUIDs.UUID
    space::S
end

function Field(
        space::S, ::Type{T}; id::UUIDs.UUID = _new_semantic_identity()
    ) where {S<:Space,T}
    _storage_value_type(T) || throw(LocalMathValidationError(
        "a Field requires an admitted storage value type";
        stage = :construct, contract = :field_element_type,
        expected = :numeric_bool_enum_tuple_or_static_array, actual = T,
    ))
    return Field{T,S}(id, space)
end

semantic_identity(field::Field) = field.id
Base.eltype(::Field{T}) where {T} = T
Base.:(==)(first::Field, second::Field) =
    first.id == second.id && eltype(first) === eltype(second) &&
    first.space == second.space
Base.hash(field::Field, seed::UInt) = hash(
    (field.id, eltype(field), field.space), seed
)

# Representation payload types encode only structural categories and concrete
# mathematical payload types. UUIDs, extents, epochs, degrees and capacities
# remain fields rather than specialization keys.
struct _IdentityRelation end
struct _AffineRelation{O,R}
    offsets::O
    origin::R
end
struct _FixedRelation
    degree::Int
end
struct _ProductRelation{F}
    factors::F
    degree::Int
end
struct _ComposedRelation{F}
    factors::F
    degree::Int
end

"""`StrictBoundary()` rejects every structured endpoint outside the domain."""
struct StrictBoundary end
"""`PeriodicBoundary(axes)` wraps the selected Cartesian axes."""
struct PeriodicBoundary{D}
    axes::NTuple{D,Bool}
end
"""`ExteriorBoundary()` represents out-of-domain lanes as absent samples."""
struct ExteriorBoundary end
struct MaskedBoundary{F,B}
    mask::F
    fallback::B
end
struct GhostBoundary{D,S<:Space}
    lower::NTuple{D,Int}
    upper::NTuple{D,Int}
    ghost_space::S
end
const _BoundaryPolicy = Union{
    StrictBoundary,PeriodicBoundary,ExteriorBoundary,
    MaskedBoundary,GhostBoundary,
}
struct _BoundaryRelation{R,P}
    base::R
    policy::P
    degree::Int
end

struct _RuntimeRelation{K}
    degree::Int
    key_type::Type{K}
    ownership::Symbol
end
struct _FieldIndexRelation{F}
    keys::F
    degree::Int
    optional::Bool
end
struct _MaskedRelation{R,F}
    base::R
    mask::F
    degree::Int
end
struct _SelectedRelation{R,I}
    base::R
    injection::I
    degree::Int
end
struct _InverseRelation{R}
    forward::R
    degree::Int
end
struct _PackedRelation
    degree::Int
    capacity::Int
    layout::Symbol
    ownership::Symbol
end

"""One storage-free semantic relation wrapper."""
struct Relation{R,D<:Space,C<:Space}
    id::UUIDs.UUID
    domain::D
    codomain::C
    representation::R
    schema_epoch::UInt64
end

semantic_identity(relation::Relation) = relation.id
domain(relation::Relation) = relation.domain
codomain(relation::Relation) = relation.codomain
schema_epoch(relation::Relation) = relation.schema_epoch
relation_representation(relation::Relation) = relation.representation
function Base.:(==)(first::Relation, second::Relation)
    return first.id == second.id && first.domain == second.domain &&
        first.codomain == second.codomain &&
        first.representation == second.representation &&
        first.schema_epoch == second.schema_epoch
end
Base.hash(relation::Relation, seed::UInt) = hash(
    (
        relation.id, relation.domain, relation.codomain,
        relation.representation, relation.schema_epoch,
    ), seed
)

degree_bound(::Relation{_IdentityRelation}) = 1
degree_bound(relation::Relation) = relation.representation.degree
degree_bound(relation::Relation{<:_AffineRelation}) =
    length(relation.representation.offsets)

function _relation(
        pair::Pair{<:Space,<:Space}, representation;
        id::UUIDs.UUID, schema_epoch::Integer,
    )
    epoch = _checked_schema_epoch(schema_epoch)
    return Relation(
        id, first(pair), last(pair), representation, epoch
    )
end

"""`IdentityRelation(space)` is the storage-free total self-map of `space`."""
function IdentityRelation(
        space::Space;
        id::UUIDs.UUID = _new_semantic_identity(), schema_epoch::Integer = 0,
    )
    return _relation(space => space, _IdentityRelation(); id, schema_epoch)
end

function _canonical_affine_offset(offset, dimensions::Int)
    values = try
        Tuple(offset)
    catch
        throw(LocalMathValidationError(
            "an affine offset must be an integer coordinate tuple";
            stage = :construct, contract = :affine_offset_type,
            expected = :integer_tuple, actual = typeof(offset),
        ))
    end
    length(values) == dimensions || throw(LocalMathValidationError(
        "an affine offset dimensionality does not match its source Space";
        stage = :construct, contract = :affine_offset_dimension,
        expected = dimensions, actual = length(values),
    ))
    all(value -> value isa Integer, values) || throw(LocalMathValidationError(
        "affine offsets must contain integers";
        stage = :construct, contract = :affine_offset_type,
        expected = Integer, actual = typeof(offset),
    ))
    return ntuple(axis -> begin
        value = Int(values[axis])
        typemin(Int32) <= value <= typemax(Int32) || throw(
            LocalMathValidationError(
                "an affine offset exceeds the Int32 execution ABI";
                stage = :construct, contract = :affine_offset_value,
                expected = typemin(Int32):typemax(Int32), actual = value,
            )
        )
        value
    end, dimensions)
end

"""
    AffineRelation(domain => codomain; offsets, origin=nothing)

Construct a storage-free fixed Cartesian offset gather.
"""
function AffineRelation(
        pair::Pair{<:Space,<:Space}; offsets,
        origin = nothing,
        id::UUIDs.UUID = _new_semantic_identity(), schema_epoch::Integer = 0,
    )
    ndims = length(size(first(pair)))
    length(size(last(pair))) == ndims || throw(LocalMathValidationError(
        "an affine relation requires equal domain/codomain dimensionality";
        stage = :construct, contract = :affine_endpoint_dimension,
        expected = ndims, actual = length(size(last(pair))),
    ))
    canonical = Tuple(
        _canonical_affine_offset(offset, ndims) for offset in offsets
    )
    isempty(canonical) && throw(LocalMathValidationError(
        "an affine relation requires at least one offset";
        stage = :construct, contract = :affine_degree_bound,
        expected = :positive, actual = 0,
    ))
    length(canonical) <= 32 || throw(LocalMathValidationError(
        "an affine relation is a small static stencil with at most 32 lanes";
        stage = :construct, contract = :affine_degree_bound,
        expected = 1:32, actual = length(canonical),
    ))
    canonical_origin = origin === nothing ? ntuple(_ -> 0, ndims) :
        _canonical_affine_offset(origin, ndims)
    return _relation(pair, _AffineRelation(canonical, canonical_origin);
        id, schema_epoch)
end

"""
    FixedRelation(domain => codomain; degree)

Declare stored fixed-degree topology. Bind `:endpoints` in lane-major order and
optionally `:counts` for incomplete rows.
"""
function FixedRelation(
        pair::Pair{<:Space,<:Space}; degree::Integer,
        id::UUIDs.UUID = _new_semantic_identity(), schema_epoch::Integer = 0,
    )
    representation = _FixedRelation(
        _checked_semantic_int(degree, :fixed_relation_degree; positive = true)
    )
    return _relation(pair, representation; id, schema_epoch)
end

"""
    ProductRelation(product_domain => product_codomain, factors::Tuple)

Form the Cartesian product of bounded relations. Endpoint spaces must be
product `Space`s whose factors match the relation domains and codomains. Lane
degree is the product of factor degrees.
"""
function ProductRelation(
        pair::Pair{<:Space,<:Space}, factors::Tuple;
        id::UUIDs.UUID = _new_semantic_identity(), schema_epoch::Integer = 0,
    )
    isempty(factors) && throw(LocalMathValidationError(
        "a product relation requires at least one factor";
        stage = :construct, contract = :product_relation_factors,
        expected = :nonempty_relation_tuple, actual = factors,
    ))
    all(factor -> factor isa Relation, factors) || throw(LocalMathValidationError(
        "every product factor must be a Relation";
        stage = :construct, contract = :product_relation_factors,
        expected = Relation, actual = map(typeof, factors),
    ))
    first(pair) isa Space{_ProductSpaceKind} &&
        last(pair) isa Space{_ProductSpaceKind} || throw(
        LocalMathValidationError(
            "a Cartesian product relation requires product-space endpoints";
            stage = :construct, contract = :product_relation_endpoints,
            expected = :product_spaces,
            actual = (space_kind(first(pair)), space_kind(last(pair))),
        )
    )
    domains = map(domain, factors)
    codomains = map(codomain, factors)
    _space_factors(first(pair)) == domains &&
        _space_factors(last(pair)) == codomains || throw(
        LocalMathValidationError(
            "product relation factors do not match its product-space endpoints";
            stage = :construct, contract = :product_relation_endpoints,
            expected = (domains, codomains),
            actual = (_space_factors(first(pair)), _space_factors(last(pair))),
        )
    )
    degree = _checked_semantic_product(
        map(degree_bound, factors), :product_relation_degree
    )
    return _relation(
        pair, _ProductRelation(factors, degree); id, schema_epoch
    )
end

"""Compose bounded relations left-to-right with first-factor-fastest lanes."""
function compose(
        first_relation::Relation, second_relation::Relation,
        remaining::Relation...;
        id::UUIDs.UUID = _new_semantic_identity(), schema_epoch::Integer = 0,
    )
    factors = (first_relation, second_relation, remaining...)
    for index in 1:(length(factors) - 1)
        codomain(factors[index]) == domain(factors[index + 1]) || throw(
            LocalMathValidationError(
                "adjacent composed Relations must share their intermediate Space";
                stage = :construct, contract = :composed_relation_adjacency,
                expected = codomain(factors[index]),
                actual = domain(factors[index + 1]),
            ))
    end
    degree = _checked_semantic_product(
        map(degree_bound, factors), :composed_relation_degree)
    degree <= _MAX_STATIC_COMPOSED_RELATION_DEGREE || throw(LocalMathValidationError(
        "a composed Relation degree product must fit the static Stage lane bound";
        stage = :construct, contract = :composed_relation_degree,
        expected = 1:_MAX_STATIC_COMPOSED_RELATION_DEGREE, actual = degree,
    ))
    return _relation(domain(first_relation) => codomain(last(factors)),
        _ComposedRelation(factors, degree); id, schema_epoch)
end

"""`MaskedBoundary(mask, fallback)` makes masked lanes absent before applying `fallback`."""
function MaskedBoundary(mask::Field{Bool}, fallback::_BoundaryPolicy)
    return MaskedBoundary{typeof(mask),typeof(fallback)}(mask, fallback)
end
"""`GhostBoundary(lower, upper, ghost_space)` routes exterior lanes to explicit ghost storage."""
function GhostBoundary(
        lower::Tuple{Vararg{Integer,D}},
        upper::Tuple{Vararg{Integer,D}},
        ghost_space::Space,
    ) where {D}
    canonical_lower = ntuple(
        axis -> _checked_semantic_int(lower[axis], :ghost_lower_depth), Val(D)
    )
    canonical_upper = ntuple(
        axis -> _checked_semantic_int(upper[axis], :ghost_upper_depth), Val(D)
    )
    return GhostBoundary(canonical_lower, canonical_upper, ghost_space)
end

_validate_boundary_policy(base::Relation, ::StrictBoundary) = nothing
_validate_boundary_policy(base::Relation, ::ExteriorBoundary) = nothing
function _validate_boundary_policy(base::Relation, policy::PeriodicBoundary{D}) where {D}
    length(size(codomain(base))) == D || throw(LocalMathValidationError(
        "periodic axes do not match the relation dimensionality";
        stage = :construct, contract = :periodic_boundary_dimension,
        expected = length(size(codomain(base))), actual = D,
    ))
    for axis in 1:D
        policy.axes[axis] && size(codomain(base))[axis] == 0 && throw(
            LocalMathValidationError(
                "a periodic axis cannot have zero extent";
                stage = :construct, contract = :periodic_boundary_extent,
                expected = :positive, actual = 0,
            )
        )
    end
    return nothing
end
function _validate_boundary_policy(base::Relation, policy::MaskedBoundary)
    policy.mask.space == codomain(base) || throw(LocalMathValidationError(
        "a boundary mask must be placed on the relation codomain";
        stage = :construct, contract = :masked_boundary_space,
        expected = semantic_identity(codomain(base)),
        actual = semantic_identity(policy.mask.space),
    ))
    _validate_boundary_policy(base, policy.fallback)
    return nothing
end
function _validate_boundary_policy(base::Relation, policy::GhostBoundary{D}) where {D}
    length(size(codomain(base))) == D || throw(LocalMathValidationError(
        "ghost depth does not match the relation dimensionality";
        stage = :construct, contract = :ghost_boundary_dimension,
        expected = length(size(codomain(base))), actual = D,
    ))
    padded = ntuple(
        axis -> size(codomain(base))[axis] + policy.lower[axis] +
            policy.upper[axis],
        Val(D),
    )
    padded_count = _checked_semantic_product(
        padded, :ghost_boundary_padded_cardinality
    )
    ghost_count = padded_count - length(codomain(base))
    length(policy.ghost_space) == ghost_count || throw(
        LocalMathValidationError(
            "the ghost Space must exactly cover the exterior padded region";
            stage = :construct, contract = :ghost_boundary_space,
            expected = ghost_count, actual = length(policy.ghost_space),
        )
    )
    return nothing
end

"""`BoundaryRelation(base, policy)` applies an explicit boundary policy to structured topology."""
function BoundaryRelation(
        base::Relation{<:_AffineRelation}, policy::_BoundaryPolicy;
        id::UUIDs.UUID = _new_semantic_identity(),
        schema_epoch::Integer = schema_epoch(base),
    )
    _validate_boundary_policy(base, policy)
    representation = _BoundaryRelation(base, policy, degree_bound(base))
    return _relation(
        domain(base) => codomain(base), representation; id, schema_epoch
    )
end

"""
    RuntimeRelation(domain => codomain; degree_bound, key_type, ownership=:local)

Declare storage-free bounded evaluator-provided routing using one-based
`Int32` or `UInt32` keys. Key zero denotes absence.
"""
function RuntimeRelation(
        pair::Pair{<:Space,<:Space}; degree_bound::Integer,
        key_type::Type{K}, ownership::Symbol = :local,
        id::UUIDs.UUID = _new_semantic_identity(), schema_epoch::Integer = 0,
    ) where {K}
    K in (Int32, UInt32) || throw(LocalMathValidationError(
        "a runtime relation currently uses one-based Int32/UInt32 ordinal keys";
        stage = :construct, contract = :runtime_relation_key_type,
        expected = (Int32, UInt32), actual = K,
    ))
    representation = _RuntimeRelation{K}(
        _checked_semantic_int(
            degree_bound, :runtime_relation_degree; positive = true
        ),
        K,
        ownership,
    )
    return _relation(pair, representation; id, schema_epoch)
end

_index_key_degree(::Type{K}) where {K<:Integer} = 1
function _index_key_degree(::Type{K}) where {K<:Tuple}
    types = fieldtypes(K)
    !isempty(types) && all(T -> T <: Integer && T !== Bool, types) || return 0
    return length(types)
end
function _index_key_degree(::Type{K}) where {K<:StaticArrays.StaticVector}
    eltype(K) <: Integer && eltype(K) !== Bool || return 0
    return length(K)
end
_index_key_degree(::Type) = 0

"""
    IndexRelation(keys => codomain; optional=false)

A storage-free bounded relation whose endpoints are read from an integer
`Field`. Scalar keys give degree one; tuples and static vectors give a fixed
lane degree. Strict relations reject out-of-range keys during execution,
whereas optional relations expose those lanes as absent samples.
"""
function IndexRelation(
        pair::Pair{<:Field,<:Space}; optional::Bool = false,
        id::UUIDs.UUID = _new_semantic_identity(), schema_epoch::Integer = 0,
    )
    keys = first(pair)
    degree = _index_key_degree(eltype(keys))
    1 <= degree <= 32 || throw(LocalMathValidationError(
        "IndexRelation keys must be integer scalars or fixed-width integer tuples/static vectors";
        stage = :construct, contract = :index_relation_key_type,
        expected = :bounded_integer_key, actual = eltype(keys),
    ))
    representation = _FieldIndexRelation(keys, degree, optional)
    return _relation(keys.space => last(pair), representation; id, schema_epoch)
end

"""`MaskedRelation(base, mask)` makes lanes from masked source items absent."""
function MaskedRelation(
        base::Relation, mask::Field{Bool};
        id::UUIDs.UUID = _new_semantic_identity(),
        schema_epoch::Integer = schema_epoch(base),
    )
    mask.space == domain(base) || throw(LocalMathValidationError(
        "a source mask must be placed on the base relation domain";
        stage = :construct, contract = :masked_relation_domain,
        expected = semantic_identity(domain(base)),
        actual = semantic_identity(mask.space),
    ))
    return _relation(
        domain(base) => codomain(base),
        _MaskedRelation(base, mask, degree_bound(base)); id, schema_epoch,
    )
end

"""`SelectedRelation(base, injection)` composes a bounded injection with `base`."""
function SelectedRelation(
        base::Relation, injection::Relation;
        id::UUIDs.UUID = _new_semantic_identity(),
        schema_epoch::Integer = max(schema_epoch(base), schema_epoch(injection)),
    )
    codomain(injection) == domain(base) || throw(LocalMathValidationError(
        "a selection injection must map its selected Space into the base domain";
        stage = :construct, contract = :selected_relation_injection,
        expected = semantic_identity(domain(base)),
        actual = semantic_identity(codomain(injection)),
    ))
    degree = _checked_semantic_product(
        (degree_bound(injection), degree_bound(base)),
        :selected_relation_degree,
    )
    return _relation(
        domain(injection) => codomain(base),
        _SelectedRelation(base, injection, degree); id, schema_epoch,
    )
end

"""
    InverseRelation(forward; degree_bound)

Declare a stored bounded inverse. Bind either `(:degrees, :incidents)` lane
storage or `(:offsets, :incidents)` grouped incidence storage for the inverse.
"""
function InverseRelation(
        forward::Relation; degree_bound::Integer,
        id::UUIDs.UUID = _new_semantic_identity(),
        schema_epoch::Integer = schema_epoch(forward),
    )
    representation = _InverseRelation(
        forward,
        _checked_semantic_int(
            degree_bound, :inverse_relation_degree; positive = true
        ),
    )
    return _relation(
        codomain(forward) => domain(forward), representation; id, schema_epoch
    )
end

"""
    PackedRelation(domain => codomain; degree_bound, capacity,
                   layout=:bounded_columns, ownership=:local)

Declare generation-qualified mutable packed topology with an explicit degree
bound and total endpoint capacity.
"""
function PackedRelation(
        pair::Pair{<:Space,<:Space}; degree_bound::Integer,
        capacity::Integer, layout::Symbol = :bounded_columns,
        ownership::Symbol = :local,
        id::UUIDs.UUID = _new_semantic_identity(), schema_epoch::Integer = 0,
    )
    layout === :bounded_columns || throw(
        LocalMathValidationError(
            "a packed relation has an unsupported semantic layout";
            stage = :construct, contract = :packed_relation_layout,
            expected = :bounded_columns, actual = layout,
        )
    )
    representation = _PackedRelation(
        _checked_semantic_int(
            degree_bound, :packed_relation_degree; positive = true
        ),
        _checked_semantic_int(capacity, :packed_relation_capacity),
        layout,
        ownership,
    )
    return _relation(pair, representation; id, schema_epoch)
end

# Relation proofs are validator-owned data. No public fact-injection helper may
# create a second authority for structural validity.
mutable struct _RelationProofSeal end
const _RELATION_PROOF_SEAL = _RelationProofSeal()

struct _ValidatedRelationEvidence{B,M,C,O,H}
    bounds::B
    multiplicity::M
    coverage::C
    canonical_order::O
    footprint::H

    function _ValidatedRelationEvidence(
            seal::_RelationProofSeal, bounds::B, multiplicity::M, coverage::C,
            canonical_order::O, footprint::H,
        ) where {B,M,C,O,H}
        seal === _RELATION_PROOF_SEAL || throw(ArgumentError(
            "validated relation evidence requires the planner-owned seal"
        ))
        return new{B,M,C,O,H}(
            bounds, multiplicity, coverage, canonical_order, footprint,
        )
    end
end

struct RelationProof{S,E}
    relation_id::UUIDs.UUID
    domain_id::UUIDs.UUID
    codomain_id::UUIDs.UUID
    schema_epoch::UInt64
    binding_schema::S
    evidence::E

    function RelationProof(
            seal::_RelationProofSeal, relation::Relation,
            binding_schema::S, evidence::_ValidatedRelationEvidence,
        ) where {S}
        seal === _RELATION_PROOF_SEAL || throw(ArgumentError(
            "RelationProof construction requires the planner-owned seal"
        ))
        return new{S,typeof(evidence)}(
            semantic_identity(relation),
            semantic_identity(domain(relation)),
            semantic_identity(codomain(relation)),
            schema_epoch(relation), binding_schema, evidence,
        )
    end
end
