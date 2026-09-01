# Concrete, backend-neutral relation views. These are prepared execution values:
# descriptor identity and proof evidence stay cold, while extents, bounded
# geometry, and already-bound storage remain available to CPU and GPU kernels.

"""A stage-local Field tuple ordinal; never a structural/global binding slot."""
struct _PreparedFieldSlot{I}
    function _PreparedFieldSlot{I}() where {I}
        1 <= I <= typemax(Int32) || throw(LocalMathValidationError(
            "a prepared Field slot must fit the common Int32 execution ABI";
            stage = :prepare, contract = :prepared_field_slot,
            expected = 1:typemax(Int32), actual = I,
        ))
        return new{I}()
    end
end

_prepared_field_slot_index(::_PreparedFieldSlot{I}) where {I} = Int32(I)

function _PreparedFieldSlot(index::Integer)
    checked = _checked_relation_view_int32(
        index, :prepared_field_slot; positive = true
    )
    return Core.apply_type(_PreparedFieldSlot, Int(checked))()
end

@generated function _prepared_stage_field(
        fields::F, ::_PreparedFieldSlot{I}
    ) where {F<:Tuple,I}
    1 <= I <= fieldcount(F) || return :(throw(BoundsError(fields, $I)))
    return :(getfield(fields, $I))
end

"""A local endpoint. Its target is encoded by a typed stage-local Field slot."""
struct _RelationEndpoint{S<:_PreparedFieldSlot,I}
    index::I
    present::Bool
    exterior::Bool
end

abstract type _AbstractRelationDegree end

struct _StaticRelationDegree{K} <: _AbstractRelationDegree
    function _StaticRelationDegree(::Val{K}) where {K}
        1 <= K <= _MAX_STATIC_COMPOSED_RELATION_DEGREE || throw(LocalMathValidationError(
            "a static relation degree exceeds the supported composed bound";
            stage = :prepare, contract = :relation_view_static_degree,
            expected = 1:_MAX_STATIC_COMPOSED_RELATION_DEGREE, actual = K,
        ))
        return new{K}()
    end
end

struct _DynamicRelationDegree <: _AbstractRelationDegree
    bound::Int32

    function _DynamicRelationDegree(bound::Integer)
        checked = _checked_relation_view_int32(
            bound, :relation_view_dynamic_degree; positive = true
        )
        checked > 32 || throw(LocalMathValidationError(
            "a dynamic relation degree is reserved for bounds above 32";
            stage = :prepare, contract = :relation_view_dynamic_degree,
            expected = :greater_than_32, actual = bound,
        ))
        return new(checked)
    end
end

@inline _relation_degree_bound(::_StaticRelationDegree{K}) where {K} = Int32(K)
@inline _relation_degree_bound(degree::_DynamicRelationDegree) = degree.bound

function _checked_relation_view_int32(
        value::Integer, purpose::Symbol; positive::Bool = false,
    )
    converted = try
        Int32(value)
    catch
        throw(LocalMathValidationError(
            "$purpose does not fit the relation device-view Int32 ABI";
            stage = :prepare, contract = purpose,
            expected = :int32, actual = value,
        ))
    end
    lower = positive ? Int32(1) : Int32(0)
    converted >= lower || throw(LocalMathValidationError(
        "$purpose is outside the relation device-view domain";
        stage = :prepare, contract = purpose,
        expected = positive ? :positive_int32 : :nonnegative_int32,
        actual = value,
    ))
    return converted
end

function _checked_relation_view_signed_int32(value::Integer, purpose::Symbol)
    return try
        Int32(value)
    catch
        throw(LocalMathValidationError(
            "$purpose does not fit the relation device-view Int32 ABI";
            stage = :prepare, contract = purpose,
            expected = :int32, actual = value,
        ))
    end
end

function _checked_relation_view_extent(extent::NTuple{D,<:Integer}) where {D}
    D > 0 || throw(LocalMathValidationError(
        "a relation device view must have at least one dimension";
        stage = :prepare, contract = :relation_view_dimension,
        expected = :positive, actual = D,
    ))
    canonical = ntuple(
        axis -> _checked_relation_view_int32(
            extent[axis], :relation_view_extent
        ),
        Val(D),
    )
    count = foldl(canonical; init = Int128(1)) do product, value
        Base.checked_mul(product, Int128(value))
    end
    _checked_relation_view_int32(count, :relation_view_extent_product)
    return canonical
end

function _checked_relation_view_degree(::Val{K}) where {K}
    return _checked_relation_view_int32(
        K, :relation_view_degree; positive = true
    )
end

@inline _missing_relation_endpoint(
        slot::_PreparedFieldSlot{S}, ::Type{I} = Int32
    ) where {S,I} = _RelationEndpoint{typeof(slot),I}(zero(I), false, false)
@inline _exterior_relation_endpoint(
        slot::_PreparedFieldSlot{S}, ::Type{I} = Int32
    ) where {S,I} = _RelationEndpoint{typeof(slot),I}(zero(I), false, true)
@inline _physical_relation_endpoint(
        slot::_PreparedFieldSlot{S}, index::I
    ) where {S,I} = _RelationEndpoint{typeof(slot),I}(index, true, false)
@inline _relation_participates(endpoint::_RelationEndpoint) =
    endpoint.present | endpoint.exterior

@inline _relation_count(extent::Tuple) = prod(extent)
@inline _relation_count(extent::Integer) = extent

@generated function _relation_coordinates(
        index::Integer, extent::NTuple{D,Int32}) where {D}
    coordinates = map(1:D) do axis
        quotient = :(Int32(index - 1))
        for prior in 1:(axis - 1)
            quotient = :(div($quotient, getfield(extent, $prior)))
        end
        :(rem($quotient, getfield(extent, $axis)) + Int32(1))
    end
    return :(($(coordinates...),))
end

@inline function _relation_linear_index(
        coordinates::NTuple{D,<:Integer}, extent::NTuple{D,Int32}
    ) where {D}
    index = Int32(1)
    stride = Int32(1)
    for axis in 1:D
        index += Int32(coordinates[axis] - 1) * stride
        stride *= extent[axis]
    end
    return index
end

struct _IdentityRelationView{D,S<:_PreparedFieldSlot}
    extent::NTuple{D,Int32}
    field_slot::S
end

function _IdentityRelationView(
        extent::NTuple{D,<:Integer}, field_slot::_PreparedFieldSlot
    ) where {D}
    canonical = _checked_relation_view_extent(extent)
    return _IdentityRelationView{D,typeof(field_slot)}(canonical, field_slot)
end

@inline _relation_domain_extent(view::_IdentityRelationView) = view.extent
@inline _relation_codomain_extent(view::_IdentityRelationView) = view.extent
@inline _relation_degree_bound(::_IdentityRelationView) = Int32(1)
@inline function _relation_endpoint(
        view::_IdentityRelationView, item::Integer, lane::Integer = 1
    )
    valid = lane == 1 && 1 <= item <= _relation_count(view.extent)
    return valid ? _physical_relation_endpoint(view.field_slot, Int32(item)) :
                   _missing_relation_endpoint(view.field_slot)
end

struct _IndexRelationView{D,S<:_PreparedFieldSlot}
    extent::NTuple{D,Int32}
    field_slot::S
end

struct _FieldIndexRelationView{P<:_AbstractRelationDegree,D,C,K<:_PreparedFieldSlot,S<:_PreparedFieldSlot}
    degree::P
    domain_extent::D
    codomain_extent::C
    codomain_count::Int32
    key_slot::K
    field_slot::S
    optional::Bool
end

function _field_index_relation_view(degree::_AbstractRelationDegree,
        domain_extent::Tuple, codomain_extent::Tuple,
        key_slot::_PreparedFieldSlot, field_slot::_PreparedFieldSlot,
        optional::Bool)
    canonical = _checked_relation_view_extent(domain_extent)
    canonical_codomain = _checked_relation_view_extent(codomain_extent)
    count = _checked_relation_view_int32(
        _relation_count(canonical_codomain), :field_index_codomain_count)
    return _FieldIndexRelationView{typeof(degree),typeof(canonical),
        typeof(canonical_codomain),
        typeof(key_slot),typeof(field_slot)}(
        degree, canonical, canonical_codomain, count,
        key_slot, field_slot, optional)
end

@inline _relation_domain_extent(view::_FieldIndexRelationView) = view.domain_extent
@inline _relation_codomain_extent(view::_FieldIndexRelationView) =
    view.codomain_extent
@inline _relation_degree_bound(view::_FieldIndexRelationView) =
    _relation_degree_bound(view.degree)
@inline _field_index_key(value::Integer, lane::Integer) =
    lane == 1 ? value : zero(value)
@inline _field_index_key(value::Tuple, lane::Integer) = @inbounds value[lane]
@inline _field_index_key(value::StaticArrays.StaticVector, lane::Integer) =
    @inbounds value[lane]
@inline function _relation_endpoint(view::_FieldIndexRelationView,
        fields::Tuple, item::Integer, lane::Integer=1)
    valid_source = 1 <= item <= _relation_count(view.domain_extent)
    valid_lane = 1 <= lane <= _relation_degree_bound(view)
    valid_source && valid_lane || return _missing_relation_endpoint(view.field_slot)
    keys = _prepared_stage_field(fields, view.key_slot)
    key = _field_index_key(@inbounds(keys[item]), lane)
    valid = key >= one(key) && UInt64(key) <= UInt64(view.codomain_count)
    return valid ? _physical_relation_endpoint(view.field_slot, Int32(key)) :
        _missing_relation_endpoint(view.field_slot)
end
@inline _relation_endpoint(view::_FieldIndexRelationView,
        item::Integer, lane::Integer=1) =
    _missing_relation_endpoint(view.field_slot)
@inline function _relation_keys_valid(view::_FieldIndexRelationView,
        fields::Tuple, item::Integer)
    view.optional && return true
    1 <= item <= _relation_count(view.domain_extent) || return false
    keys = _prepared_stage_field(fields, view.key_slot)
    value = @inbounds keys[item]
    for lane in Int32(1):_relation_degree_bound(view)
        key = _field_index_key(value, lane)
        1 <= key <= view.codomain_count || return false
    end
    return true
end
@inline _relation_keys_valid(view, fields::Tuple, item::Integer) = true

function _IndexRelationView(
        extent::NTuple{D,<:Integer}, field_slot::_PreparedFieldSlot
    ) where {D}
    canonical = _checked_relation_view_extent(extent)
    return _IndexRelationView{D,typeof(field_slot)}(canonical, field_slot)
end

@inline _relation_domain_extent(view::_IndexRelationView) = view.extent
@inline _relation_codomain_extent(view::_IndexRelationView) = view.extent
@inline _relation_degree_bound(::_IndexRelationView) = Int32(1)
@inline function _relation_endpoint(
        view::_IndexRelationView, item::Integer, lane::Integer = 1
    )
    valid = lane == 1 && 1 <= item <= _relation_count(view.extent)
    return valid ? _physical_relation_endpoint(view.field_slot, Int32(item)) :
        _missing_relation_endpoint(view.field_slot)
end
@inline _relation_index(view::_IndexRelationView, coordinates::Tuple) =
    _relation_linear_index(coordinates, view.extent)
@inline _relation_coordinates(view::_IndexRelationView, item::Integer) =
    _relation_coordinates(item, view.extent)

struct _StrictRelationBoundary end
struct _PeriodicRelationBoundary{D}
    axes::NTuple{D,Bool}
end
struct _ExteriorRelationBoundary{T}
    value::T
end
struct _GhostRelationBoundary{D,G,S<:_PreparedFieldSlot}
    interior_extent::NTuple{D,Int32}
    lower::NTuple{D,Int32}
    upper::NTuple{D,Int32}
    indices::G
    ghost_count::Int32
    ghost_slot::S
    function _GhostRelationBoundary(
            interior_extent::NTuple{D,<:Integer},
            lower::NTuple{D,<:Integer}, upper::NTuple{D,<:Integer},
            indices::G, ghost_count::Integer, ghost_slot::S,
        ) where {D,G,S<:_PreparedFieldSlot}
        interior = _checked_relation_view_extent(interior_extent)
        lower_extent = _checked_relation_view_extent(lower)
        upper_extent = _checked_relation_view_extent(upper)
        padded = ntuple(Val(D)) do axis
            total = Int128(interior[axis]) + Int128(lower_extent[axis]) +
                Int128(upper_extent[axis])
            _checked_relation_view_int32(
                total, :relation_view_ghost_padded_extent
            )
        end
        padded_count = foldl(padded; init = Int128(1)) do product, value
            Base.checked_mul(product, Int128(value))
        end
        _checked_relation_view_int32(
            padded_count, :relation_view_ghost_padded_cardinality
        )
        length(indices) == padded_count || throw(LocalMathValidationError(
            "a ghost mapping must cover the exact padded relation extent";
            stage = :prepare, contract = :relation_view_ghost_mapping_length,
            expected = padded_count, actual = length(indices),
        ))
        count = _checked_relation_view_int32(
            ghost_count, :relation_view_ghost_count
        )
        all(index -> 0 <= index <= count, indices) || throw(
            LocalMathValidationError(
                "a ghost mapping endpoint is outside its bound ghost storage";
                stage = :prepare, contract = :relation_view_ghost_endpoint,
                expected = 0:count, actual = :out_of_range_endpoint,
            )
        )
        return new{D,G,S}(
            interior, lower_extent, upper_extent, indices, count, ghost_slot
        )
    end

    function _GhostRelationBoundary(
            proof::RelationProof, interior_extent::NTuple{D,Int32},
            lower::NTuple{D,Int32}, upper::NTuple{D,Int32}, indices::G,
            ghost_count::Int32, ghost_slot::S,
        ) where {D,G,S<:_PreparedFieldSlot}
        content_validation = proof.evidence.bounds.content_validation
        valid_authority = content_validation in (
            :immutable_host_borrow, :device_content_validation_required)
        valid_authority || throw(
            LocalMathValidationError(
                "prepared ghost storage requires proof-recorded exact content validation";
                stage = :prepare, contract = :ghost_relation_validation,
                expected = (:immutable_host_borrow,
                    :device_content_validation_required),
                actual = content_validation,
            ))
        padded = ntuple(
            axis -> interior_extent[axis] + lower[axis] + upper[axis], Val(D)
        )
        length(indices) == _relation_count(padded) || throw(
            LocalMathValidationError(
                "prepared ghost mapping cardinality changed after proof";
                stage = :prepare, contract = :ghost_relation_mapping,
                expected = _relation_count(padded), actual = length(indices),
            )
        )
        return new{D,G,S}(
            interior_extent, lower, upper, indices, ghost_count, ghost_slot
        )
    end
end
struct _MaskedRelationBoundary{M<:_PreparedFieldSlot,B}
    mask_slot::M
    fallback::B
end


@inline _relation_boundary_value(boundary::_ExteriorRelationBoundary) = boundary.value

@inline function _boundary_endpoint(
        ::_StrictRelationBoundary, coordinates::NTuple{D,<:Integer},
        extent::NTuple{D,Int32}, field_slot::S,
    ) where {D,S<:_PreparedFieldSlot}
    inside = all(axis -> 1 <= coordinates[axis] <= extent[axis], 1:D)
    return inside ? _physical_relation_endpoint(
        field_slot, _relation_linear_index(coordinates, extent)
    ) : _missing_relation_endpoint(field_slot)
end

@inline function _boundary_endpoint(
        boundary::_PeriodicRelationBoundary{D},
        coordinates::NTuple{D,<:Integer}, extent::NTuple{D,Int32},
        field_slot::S,
    ) where {D,S<:_PreparedFieldSlot}
    admissible = all(
        axis -> boundary.axes[axis] ? extent[axis] > 0 :
            1 <= coordinates[axis] <= extent[axis],
        1:D,
    )
    admissible || return _missing_relation_endpoint(field_slot)
    wrapped = ntuple(
        axis -> boundary.axes[axis] ?
            Int32(mod1(Int64(coordinates[axis]), Int64(extent[axis]))) :
            Int32(coordinates[axis]),
        Val(D),
    )
    return _physical_relation_endpoint(
        field_slot, _relation_linear_index(wrapped, extent)
    )
end

@inline function _boundary_endpoint(
        ::_ExteriorRelationBoundary, coordinates::NTuple{D,<:Integer},
        extent::NTuple{D,Int32}, field_slot::S,
    ) where {D,S<:_PreparedFieldSlot}
    inside = all(axis -> 1 <= coordinates[axis] <= extent[axis], 1:D)
    return inside ? _physical_relation_endpoint(
        field_slot, _relation_linear_index(coordinates, extent)
    ) : _exterior_relation_endpoint(field_slot)
end

@inline function _boundary_endpoint(
        boundary::_GhostRelationBoundary{D},
        coordinates::NTuple{D,<:Integer}, extent::NTuple{D,Int32},
        field_slot::S,
    ) where {D,S<:_PreparedFieldSlot}
    extent == boundary.interior_extent || return _missing_relation_endpoint(field_slot)
    inside = all(axis -> 1 <= coordinates[axis] <= extent[axis], 1:D)
    inside && return _physical_relation_endpoint(
        field_slot, _relation_linear_index(coordinates, extent)
    )
    within_halo = all(
        axis -> 1 - boundary.lower[axis] <= coordinates[axis] <=
            extent[axis] + boundary.upper[axis],
        1:D,
    )
    within_halo || return _missing_relation_endpoint(field_slot)
    padded_fits = all(
        axis -> Int64(extent[axis]) + Int64(boundary.lower[axis]) +
            Int64(boundary.upper[axis]) <= typemax(Int32),
        1:D,
    )
    padded_fits || return _missing_relation_endpoint(field_slot)
    padded_extent = ntuple(
        axis -> extent[axis] + boundary.lower[axis] + boundary.upper[axis],
        Val(D),
    )
    padded_coordinates = ntuple(
        axis -> Int32(coordinates[axis]) + boundary.lower[axis], Val(D)
    )
    position = _relation_linear_index(padded_coordinates, padded_extent)
    1 <= position <= length(boundary.indices) ||
        return _missing_relation_endpoint(field_slot)
    endpoint = Int32(@inbounds boundary.indices[position])
    return 0 < endpoint <= boundary.ghost_count ? _physical_relation_endpoint(
        boundary.ghost_slot, endpoint
    ) :
        _missing_relation_endpoint(field_slot)
end

@inline function _boundary_endpoint(
        boundary::_MaskedRelationBoundary, coordinates::Tuple, extent::Tuple,
        field_slot::_PreparedFieldSlot, fields::Tuple,
    )
    endpoint = _boundary_endpoint(
        boundary.fallback, coordinates, extent, field_slot
    )
    endpoint.present || return endpoint
    # This mask is placed on the base codomain. A nested ghost policy returns
    # an endpoint in a different bound Field slot and is therefore outside
    # the mask's mathematical domain.
    typeof(endpoint).parameters[1] === typeof(field_slot) || return endpoint
    mask = _prepared_stage_field(fields, boundary.mask_slot)
    1 <= endpoint.index <= length(mask) ||
        return _missing_relation_endpoint(field_slot, typeof(endpoint.index))
    return @inbounds(mask[endpoint.index]) ? endpoint :
        _missing_relation_endpoint(field_slot, typeof(endpoint.index))
end

struct _AffineRelationView{D,K,O,B,S<:_PreparedFieldSlot}
    domain_extent::NTuple{D,Int32}
    codomain_extent::NTuple{D,Int32}
    offsets::O
    boundary::B
    field_slot::S
end

function _AffineRelationView(
        domain_extent::NTuple{D,<:Integer},
        codomain_extent::NTuple{D,<:Integer}, offsets::NTuple{K}, boundary,
        field_slot::S,
    ) where {D,K,S<:_PreparedFieldSlot}
    _StaticRelationDegree(Val(K))
    domain = _checked_relation_view_extent(domain_extent)
    codomain = _checked_relation_view_extent(codomain_extent)
    canonical = ntuple(Val(K)) do lane
        ntuple(axis -> _checked_relation_view_signed_int32(
            offsets[lane][axis], :relation_view_affine_offset
        ), Val(D))
    end
    return _AffineRelationView{D,K,typeof(canonical),typeof(boundary),S}(
        domain, codomain, canonical, boundary, field_slot
    )
end

@inline _relation_domain_extent(view::_AffineRelationView) = view.domain_extent
@inline _relation_codomain_extent(view::_AffineRelationView) = view.codomain_extent
@inline _relation_degree_bound(::_AffineRelationView{D,K}) where {D,K} = Int32(K)
@inline function _relation_endpoint(
        view::_AffineRelationView{D,K}, item::Integer, lane::Integer,
    ) where {D,K}
    (1 <= item <= _relation_count(view.domain_extent) && 1 <= lane <= K) ||
        return _missing_relation_endpoint(view.field_slot)
    source = _relation_coordinates(item, view.domain_extent)
    target = ntuple(
        axis -> Int64(source[axis]) + Int64(view.offsets[lane][axis]), Val(D)
    )
    return view.boundary isa _MaskedRelationBoundary ?
        throw(LocalMathValidationError(
            "a masked boundary endpoint requires the prepared stage Field tuple";
            stage = :prepare, contract = :relation_view_fields,
        )) : _boundary_endpoint(
            view.boundary, target, view.codomain_extent, view.field_slot
        )
end

@inline function _relation_endpoint(
        view::_AffineRelationView{D,K}, fields::Tuple,
        item::Integer, lane::Integer,
    ) where {D,K}
    (1 <= item <= _relation_count(view.domain_extent) && 1 <= lane <= K) ||
        return _missing_relation_endpoint(view.field_slot)
    source = _relation_coordinates(item, view.domain_extent)
    target = ntuple(
        axis -> Int64(source[axis]) + Int64(view.offsets[lane][axis]), Val(D)
    )
    return view.boundary isa _MaskedRelationBoundary ?
        _boundary_endpoint(
            view.boundary, target, view.codomain_extent, view.field_slot, fields
        ) : _boundary_endpoint(
            view.boundary, target, view.codomain_extent, view.field_slot
        )
end

struct _FixedDegreeRelationView{P<:_AbstractRelationDegree,E,C,D,S<:_PreparedFieldSlot}
    degree::P
    endpoints::E
    counts::C
    domain_extent::D
    codomain_count::Int32
    field_slot::S
    function _FixedDegreeRelationView(
            degree::P, endpoints::E, counts::C,
            domain_extent::NTuple{N,<:Integer}, codomain_count::Integer,
            field_slot::S,
        ) where {P<:_AbstractRelationDegree,E,C,N,S<:_PreparedFieldSlot}
        canonical_extent = _checked_relation_view_extent(domain_extent)
        codomain = _checked_relation_view_int32(
            codomain_count, :relation_view_codomain_count
        )
        return new{P,E,C,typeof(canonical_extent),S}(
            degree, endpoints, counts, canonical_extent, codomain, field_slot
        )
    end
end

@inline _fixed_relation_count(::Nothing, item::Integer, degree::Int32) = degree
@inline _fixed_relation_count(counts, item::Integer, degree::Int32) =
    @inbounds Int32(counts[item])
@inline _fixed_counts_length(::Nothing) = typemax(Int32)
@inline _fixed_counts_length(counts) = Int32(length(counts))
@inline _fixed_lane_count(endpoints::Tuple) = Int32(length(endpoints))
@inline _fixed_lane_count(endpoints) = Int32(size(endpoints, 1))
@inline _fixed_lane_capacity(endpoints::Tuple, lane::Integer) =
    @inbounds Int32(length(endpoints[lane]))
@inline _fixed_lane_capacity(endpoints, lane::Integer) = Int32(size(endpoints, 2))
@inline _fixed_relation_endpoint(endpoints::Tuple, item::Integer, lane::Integer) =
    @inbounds endpoints[lane][item]
@inline _fixed_relation_endpoint(endpoints, item::Integer, lane::Integer) =
    @inbounds endpoints[lane, item]

@inline _relation_domain_extent(view::_FixedDegreeRelationView) = view.domain_extent
@inline _relation_codomain_extent(view::_FixedDegreeRelationView) =
    (view.codomain_count,)
@inline _relation_degree_bound(view::_FixedDegreeRelationView) =
    _relation_degree_bound(view.degree)
@inline function _relation_endpoint(
        view::_FixedDegreeRelationView, item::Integer, lane::Integer,
    )
    degree = _relation_degree_bound(view)
    (1 <= item <= min(
         _relation_count(view.domain_extent), _fixed_counts_length(view.counts)
     ) &&
     1 <= lane <= min(degree, _fixed_lane_count(view.endpoints)) &&
     item <= _fixed_lane_capacity(view.endpoints, lane) &&
     1 <= lane <= min(_fixed_relation_count(view.counts, item, degree), degree)) ||
        return _missing_relation_endpoint(view.field_slot)
    endpoint = Int32(_fixed_relation_endpoint(view.endpoints, item, lane))
    return 1 <= endpoint <= view.codomain_count ?
        _physical_relation_endpoint(view.field_slot, endpoint) :
        _missing_relation_endpoint(view.field_slot)
end

struct _ProductRelationView{F,S<:_PreparedFieldSlot}
    factors::F
    field_slot::S
    function _ProductRelationView(
            factors::F, field_slot::S
        ) where {F<:Tuple,S<:_PreparedFieldSlot}
        isempty(factors) && throw(LocalMathValidationError(
            "a product relation device view requires at least one factor";
            stage = :prepare, contract = :relation_view_product_factors,
            expected = :nonempty_tuple, actual = factors,
        ))
        _checked_relation_view_int32(
            _checked_relation_view_product(factors, _relation_domain_extent),
            :relation_view_product_domain,
        )
        _checked_relation_view_int32(
            _checked_relation_view_product(factors, _relation_codomain_extent),
            :relation_view_product_codomain,
        )
        _checked_relation_view_int32(
            _checked_relation_view_product(factors, _relation_degree_bound),
            :relation_view_product_degree; positive = true,
        )
        return new{F,S}(factors, field_slot)
    end
end


function _checked_relation_view_product(factors::Tuple, accessor)
    value = Int128(1)
    for factor in factors
        factor_value = accessor(factor)
        scalar = factor_value isa Tuple ? prod(Int128.(factor_value)) :
            Int128(factor_value)
        value = Base.checked_mul(value, scalar)
    end
    return value
end

@inline _relation_domain_extent(view::_ProductRelationView) =
    (_product_relation_domain_count(view.factors),)
@inline _relation_codomain_extent(view::_ProductRelationView) =
    (_product_relation_codomain_count(view.factors),)
@inline _relation_degree_bound(view::_ProductRelationView) =
    _product_relation_degree(view.factors)
@inline _product_relation_domain_count(::Tuple{}) = Int32(1)
@inline _product_relation_domain_count(factors::Tuple) =
    Int32(_relation_count(_relation_domain_extent(first(factors)))) *
    _product_relation_domain_count(Base.tail(factors))
@inline _product_relation_codomain_count(::Tuple{}) = Int32(1)
@inline _product_relation_codomain_count(factors::Tuple) =
    Int32(_relation_count(_relation_codomain_extent(first(factors)))) *
    _product_relation_codomain_count(Base.tail(factors))
@inline _product_relation_degree(::Tuple{}) = Int32(1)
@inline _product_relation_degree(factors::Tuple) =
    _relation_degree_bound(first(factors)) *
    _product_relation_degree(Base.tail(factors))

@inline _product_relation_endpoint(
    ::Tuple{}, item::Int32, lane::Int32, field_slot::_PreparedFieldSlot
) = _physical_relation_endpoint(field_slot, Int32(1))
@inline function _product_relation_endpoint(
        factors::Tuple, item::Int32, lane::Int32, field_slot::_PreparedFieldSlot,
    )
    factor = first(factors)
    domain_count = Int32(_relation_count(_relation_domain_extent(factor)))
    degree = _relation_degree_bound(factor)
    factor_item = rem(item - Int32(1), domain_count) + Int32(1)
    factor_lane = rem(lane - Int32(1), degree) + Int32(1)
    endpoint = _relation_endpoint(factor, factor_item, factor_lane)
    endpoint.present || return endpoint
    tail = _product_relation_endpoint(
        Base.tail(factors),
        div(item - Int32(1), domain_count) + Int32(1),
        div(lane - Int32(1), degree) + Int32(1),
        field_slot,
    )
    tail.present || return tail
    codomain_count = Int32(_relation_count(_relation_codomain_extent(factor)))
    return _physical_relation_endpoint(
        field_slot,
        endpoint.index + (tail.index - Int32(1)) * codomain_count,
    )
end

@inline function _product_relation_endpoint(
        factors::Tuple, fields::Tuple, item::Int32, lane::Int32,
        field_slot::_PreparedFieldSlot,
    )
    factor = first(factors)
    domain_count = Int32(_relation_count(_relation_domain_extent(factor)))
    degree = _relation_degree_bound(factor)
    factor_item = rem(item - Int32(1), domain_count) + Int32(1)
    factor_lane = rem(lane - Int32(1), degree) + Int32(1)
    endpoint = _relation_endpoint(factor, fields, factor_item, factor_lane)
    endpoint.present || return endpoint
    tail = _product_relation_endpoint(
        Base.tail(factors), fields,
        div(item - Int32(1), domain_count) + Int32(1),
        div(lane - Int32(1), degree) + Int32(1), field_slot,
    )
    tail.present || return tail
    codomain_count = Int32(_relation_count(_relation_codomain_extent(factor)))
    return _physical_relation_endpoint(
        field_slot,
        endpoint.index + (tail.index - Int32(1)) * codomain_count,
    )
end

@inline _product_relation_endpoint(
        ::Tuple{}, fields::Tuple, item::Int32, lane::Int32,
        field_slot::_PreparedFieldSlot,
    ) = _physical_relation_endpoint(field_slot, Int32(1))

@inline function _relation_endpoint(
        view::_ProductRelationView, item::Integer, lane::Integer,
    )
    (1 <= item <= _relation_count(_relation_domain_extent(view)) &&
     1 <= lane <= _relation_degree_bound(view)) ||
        return _missing_relation_endpoint(view.field_slot)
    return _product_relation_endpoint(
        view.factors, Int32(item), Int32(lane), view.field_slot
    )
end

@inline function _relation_endpoint(
        view::_ProductRelationView, fields::Tuple,
        item::Integer, lane::Integer,
    )
    (1 <= item <= _relation_count(_relation_domain_extent(view)) &&
     1 <= lane <= _relation_degree_bound(view)) ||
        return _missing_relation_endpoint(view.field_slot)
    return _product_relation_endpoint(
        view.factors, fields, Int32(item), Int32(lane), view.field_slot
    )
end

@inline _product_relation_keys_valid(
    ::Tuple{}, fields::Tuple, item::Int32) = true
@inline function _product_relation_keys_valid(
        factors::Tuple, fields::Tuple, item::Int32)
    factor = first(factors)
    domain_count = Int32(_relation_count(_relation_domain_extent(factor)))
    factor_item = rem(item - Int32(1), domain_count) + Int32(1)
    _relation_keys_valid(factor, fields, factor_item) || return false
    return _product_relation_keys_valid(
        Base.tail(factors), fields,
        div(item - Int32(1), domain_count) + Int32(1),
    )
end
@inline function _relation_keys_valid(view::_ProductRelationView,
        fields::Tuple, item::Integer)
    1 <= item <= _relation_count(_relation_domain_extent(view)) || return false
    return _product_relation_keys_valid(view.factors, fields, Int32(item))
end

struct _ComposedRelationView{F,S<:_PreparedFieldSlot}
    factors::F
    field_slot::S
    degree::Int32
    function _ComposedRelationView(
            factors::F, field_slot::S) where {F<:Tuple,S<:_PreparedFieldSlot}
        length(factors) >= 2 || throw(LocalMathValidationError(
            "a composed relation view requires at least two factors";
            stage = :prepare, contract = :relation_view_composed_factors,
            expected = :at_least_two, actual = length(factors),
        ))
        _require_composed_view_adjacency(factors)
        degree = _checked_relation_view_product(
            factors, _relation_degree_bound)
        1 <= degree <= _MAX_STATIC_COMPOSED_RELATION_DEGREE || throw(LocalMathValidationError(
            "a composed relation view exceeds the static Stage lane bound";
            stage = :prepare, contract = :relation_view_composed_degree,
            expected = 1:_MAX_STATIC_COMPOSED_RELATION_DEGREE, actual = degree,
        ))
        return new{F,S}(factors, field_slot, Int32(degree))
    end
end

@inline _composed_relation_keys_valid(
    ::Tuple{}, fields::Tuple, item::Int32) = true
@inline function _composed_relation_keys_valid(
        factors::Tuple, fields::Tuple, item::Int32)
    factor = first(factors)
    _relation_keys_valid(factor, fields, item) || return false
    tail = Base.tail(factors)
    isempty(tail) && return true
    for lane in Int32(1):_relation_degree_bound(factor)
        endpoint = _relation_endpoint(factor, fields, item, lane)
        endpoint.present || continue
        _composed_relation_keys_valid(
            tail, fields, Int32(endpoint.index)) || return false
    end
    return true
end
@inline function _relation_keys_valid(view::_ComposedRelationView,
        fields::Tuple, item::Integer)
    1 <= item <= _relation_count(_relation_domain_extent(view)) || return false
    return _composed_relation_keys_valid(view.factors, fields, Int32(item))
end

@inline _require_composed_view_adjacency(::Tuple{T}) where {T} = nothing
@inline function _require_composed_view_adjacency(factors::Tuple)
    _relation_codomain_extent(first(factors)) ==
        _relation_domain_extent(getfield(factors, 2)) || throw(
        LocalMathValidationError(
            "prepared composed relation factors have mismatched extents";
            stage = :prepare, contract = :relation_view_composed_adjacency,
            expected = _relation_codomain_extent(first(factors)),
            actual = _relation_domain_extent(getfield(factors, 2)),
        ))
    return _require_composed_view_adjacency(Base.tail(factors))
end

@inline _relation_domain_extent(view::_ComposedRelationView) =
    _relation_domain_extent(first(view.factors))
@inline _relation_codomain_extent(view::_ComposedRelationView) =
    _relation_codomain_extent(last(view.factors))
@inline _relation_degree_bound(view::_ComposedRelationView) = view.degree

@inline function _composed_relation_endpoint(::Tuple{}, fields,
        item::Int32, lane::Int32, field_slot::_PreparedFieldSlot)
    return lane == 1 ? _physical_relation_endpoint(field_slot, item) :
        _missing_relation_endpoint(field_slot)
end
@inline function _composed_relation_endpoint(factors::Tuple, fields,
        item::Int32, lane::Int32, field_slot::_PreparedFieldSlot)
    factor = first(factors)
    degree = _relation_degree_bound(factor)
    factor_lane = rem(lane - Int32(1), degree) + Int32(1)
    tail_lane = div(lane - Int32(1), degree) + Int32(1)
    endpoint = fields === nothing ?
        _relation_endpoint(factor, item, factor_lane) :
        _relation_endpoint(factor, fields, item, factor_lane)
    endpoint.exterior && return _exterior_relation_endpoint(field_slot)
    endpoint.present || return _missing_relation_endpoint(field_slot)
    return _composed_relation_endpoint(Base.tail(factors), fields,
        Int32(endpoint.index), tail_lane, field_slot)
end

@inline function _relation_endpoint(
        view::_ComposedRelationView, item::Integer, lane::Integer)
    (1 <= item <= _relation_count(_relation_domain_extent(view)) &&
        1 <= lane <= _relation_degree_bound(view)) ||
        return _missing_relation_endpoint(view.field_slot)
    return _composed_relation_endpoint(view.factors, nothing,
        Int32(item), Int32(lane), view.field_slot)
end
@inline function _relation_endpoint(view::_ComposedRelationView,
        fields::Tuple, item::Integer, lane::Integer)
    (1 <= item <= _relation_count(_relation_domain_extent(view)) &&
        1 <= lane <= _relation_degree_bound(view)) ||
        return _missing_relation_endpoint(view.field_slot)
    return _composed_relation_endpoint(view.factors, fields,
        Int32(item), Int32(lane), view.field_slot)
end

struct _PrefixInjectionRelationView{C,S<:_PreparedFieldSlot}
    count::C
    capacity::Int32
    codomain_count::Int32
    field_slot::S
end
struct _IndexInjectionRelationView{I,C,S<:_PreparedFieldSlot}
    indices::I
    count::C
    capacity::Int32
    codomain_count::Int32
    field_slot::S
end


function _PrefixInjectionRelationView(
        count, capacity::Integer, codomain_count::Integer,
        field_slot::S,
    ) where {S<:_PreparedFieldSlot}
    return _PrefixInjectionRelationView{typeof(count),S}(
        count,
        _checked_relation_view_int32(capacity, :relation_view_capacity),
        _checked_relation_view_int32(
            codomain_count, :relation_view_codomain_count
        ),
        field_slot,
    )
end


function _IndexInjectionRelationView(
        indices, count, capacity::Integer, codomain_count::Integer,
        field_slot::S,
    ) where {S<:_PreparedFieldSlot}
    return _IndexInjectionRelationView{typeof(indices),typeof(count),S}(
        indices, count,
        _checked_relation_view_int32(capacity, :relation_view_capacity),
        _checked_relation_view_int32(
            codomain_count, :relation_view_codomain_count
        ),
        field_slot,
    )
end

@inline _relation_scalar(value::Integer) = Int32(value)
@inline _relation_scalar(value) = @inbounds Int32(value[1])
@inline _relation_domain_extent(view::_PrefixInjectionRelationView) =
    (view.capacity,)
@inline _relation_codomain_extent(view::_PrefixInjectionRelationView) =
    (view.codomain_count,)
@inline _relation_degree_bound(::_PrefixInjectionRelationView) = Int32(1)
@inline function _relation_endpoint(
        view::_PrefixInjectionRelationView, item::Integer, lane::Integer,
    )
    accepted = lane == 1 && 1 <= item <= min(
        _relation_scalar(view.count), view.capacity, view.codomain_count
    )
    return accepted ? _physical_relation_endpoint(
        view.field_slot, Int32(item)
    ) :
        _missing_relation_endpoint(view.field_slot)
end

@inline _relation_domain_extent(view::_IndexInjectionRelationView) =
    (view.capacity,)
@inline _relation_codomain_extent(view::_IndexInjectionRelationView) =
    (view.codomain_count,)
@inline _relation_degree_bound(::_IndexInjectionRelationView) = Int32(1)
@inline function _relation_endpoint(
        view::_IndexInjectionRelationView, item::Integer, lane::Integer,
    )
    accepted = lane == 1 && 1 <= item <= min(
        _relation_scalar(view.count), view.capacity, Int32(length(view.indices))
    )
    accepted || return _missing_relation_endpoint(view.field_slot)
    endpoint = Int32(@inbounds view.indices[item])
    return 1 <= endpoint <= view.codomain_count ?
        _physical_relation_endpoint(view.field_slot, endpoint) :
        _missing_relation_endpoint(view.field_slot)
end

struct _SelectedRelationView{R,S}
    base::R
    injection::S
    function _SelectedRelationView(base::R, injection::S) where {R,S}
        _relation_codomain_extent(injection) == _relation_domain_extent(base) ||
            throw(LocalMathValidationError(
                "a selected relation view injection must target the base domain";
                stage = :prepare, contract = :relation_view_selected_injection,
                expected = _relation_domain_extent(base),
                actual = _relation_codomain_extent(injection),
            ))
        _checked_relation_view_int32(
            Base.checked_mul(
                Int128(_relation_degree_bound(injection)),
                Int128(_relation_degree_bound(base)),
            ),
            :relation_view_selected_degree; positive = true,
        )
        return new{R,S}(base, injection)
    end
end

@inline _relation_domain_extent(view::_SelectedRelationView) =
    _relation_domain_extent(view.injection)
@inline _relation_codomain_extent(view::_SelectedRelationView) =
    _relation_codomain_extent(view.base)
@inline _relation_degree_bound(view::_SelectedRelationView) =
    _relation_degree_bound(view.injection) * _relation_degree_bound(view.base)
@inline function _relation_endpoint(
        view::_SelectedRelationView, item::Integer, lane::Integer,
    )
    injection_degree = _relation_degree_bound(view.injection)
    injection_lane = rem(Int32(lane - 1), injection_degree) + Int32(1)
    base_lane = div(Int32(lane - 1), injection_degree) + Int32(1)
    1 <= lane <= _relation_degree_bound(view) || return _missing_relation_endpoint()
    intermediate = _relation_endpoint(
        view.injection, item, injection_lane
    )
    intermediate.present || return intermediate
    return _relation_endpoint(view.base, intermediate.index, base_lane)
end

@inline function _relation_endpoint(
        view::_SelectedRelationView, fields::Tuple,
        item::Integer, lane::Integer,
    )
    injection_degree = _relation_degree_bound(view.injection)
    injection_lane = rem(Int32(lane - 1), injection_degree) + Int32(1)
    base_lane = div(Int32(lane - 1), injection_degree) + Int32(1)
    1 <= lane <= _relation_degree_bound(view) ||
        return _missing_relation_endpoint(_relation_target_slot(view.base))
    intermediate = _relation_endpoint(
        view.injection, fields, item, injection_lane
    )
    intermediate.present || return intermediate
    return _relation_endpoint(view.base, fields, intermediate.index, base_lane)
end


struct _SourceMaskRelationView{R,M<:_PreparedFieldSlot}
    base::R
    mask_slot::M
    function _SourceMaskRelationView(
            base::R, mask_slot::M
        ) where {R,M<:_PreparedFieldSlot}
        return new{R,M}(base, mask_slot)
    end
end

@inline _relation_keys_valid(view::_SourceMaskRelationView,
    fields::Tuple, item::Integer) =
    _relation_keys_valid(view.base, fields, item)
@inline function _relation_keys_valid(view::_SelectedRelationView,
        fields::Tuple, item::Integer)
    _relation_keys_valid(view.injection, fields, item) || return false
    for lane in Int32(1):_relation_degree_bound(view.injection)
        endpoint = _relation_endpoint(view.injection, fields, item, lane)
        endpoint.present || continue
        _relation_keys_valid(view.base, fields, endpoint.index) || return false
    end
    return true
end


@inline _relation_domain_extent(view::_SourceMaskRelationView) =
    _relation_domain_extent(view.base)
@inline _relation_codomain_extent(view::_SourceMaskRelationView) =
    _relation_codomain_extent(view.base)
@inline _relation_degree_bound(view::_SourceMaskRelationView) =
    _relation_degree_bound(view.base)
@inline function _relation_endpoint(
        view::_SourceMaskRelationView, item::Integer, lane::Integer,
    )
    throw(LocalMathValidationError(
        "a source-masked relation endpoint requires the prepared stage Field tuple";
        stage = :prepare, contract = :relation_view_fields,
    ))
end

@inline function _relation_endpoint(
        view::_SourceMaskRelationView, fields::Tuple,
        item::Integer, lane::Integer,
    )
    mask = _prepared_stage_field(fields, view.mask_slot)
    (1 <= item <= length(mask) && @inbounds(mask[item])) ||
        return _missing_relation_endpoint(_relation_target_slot(view.base))
    return _relation_endpoint(view.base, fields, item, lane)
end

struct _PackedIncidenceRelationView{P<:_AbstractRelationDegree,A,E,O,C,G,D,S<:_PreparedFieldSlot}
    degree::P
    active::A
    endpoints::E
    offsets::O
    counts::C
    content_generations::G
    slot::Int32
    codomain_count::Int32
    capacity::D
    field_slot::S
    function _PackedIncidenceRelationView(
            degree::P, active::A, endpoints::E, offsets::O, counts::C,
            content_generations::G, slot::Integer, codomain_count::Integer,
            capacity::Integer, field_slot::S,
        ) where {P<:_AbstractRelationDegree,A,E,O,C,G,S<:_PreparedFieldSlot}
        checked_slot = _checked_relation_view_int32(
            slot, :relation_view_slot; positive = true
        )
        checked_slot <= length(offsets) && checked_slot <= length(counts) &&
            checked_slot <= length(content_generations) || throw(
            LocalMathValidationError(
                "a packed relation view slot is outside its bound schema arrays";
                stage = :prepare, contract = :relation_view_slot,
                expected = :bound_schema_slot, actual = checked_slot,
            )
        )
        codomain = _checked_relation_view_int32(
            codomain_count, :relation_view_codomain_count
        )
        checked_capacity = _checked_relation_view_int32(
            capacity, :relation_view_capacity
        )
        return new{P,A,E,O,C,G,Int32,S}(
            degree, active, endpoints, offsets, counts, content_generations,
            checked_slot, codomain, checked_capacity, field_slot,
        )
    end
end

@inline _packed_relation_offset(view::_PackedIncidenceRelationView) =
    @inbounds Int32(view.offsets[view.slot])
@inline _packed_relation_count(view::_PackedIncidenceRelationView) =
    @inbounds Int32(view.counts[view.slot])
@inline _relation_content_generation(view::_PackedIncidenceRelationView) =
    @inbounds UInt64(view.content_generations[view.slot])
@inline _relation_domain_extent(view::_PackedIncidenceRelationView) = (view.capacity,)
@inline _relation_codomain_extent(view::_PackedIncidenceRelationView) =
    (view.codomain_count,)
@inline _relation_degree_bound(view::_PackedIncidenceRelationView) =
    _relation_degree_bound(view.degree)
@inline _packed_lane_count(endpoints::Tuple) = Int32(length(endpoints))
@inline _packed_lane_count(endpoints) = Int32(size(endpoints, 1))
@inline _packed_endpoint_storage_length(::Tuple{}) = typemax(Int32)
@inline _packed_endpoint_storage_length(endpoints::Tuple) = min(
    Int32(length(first(endpoints))),
    _packed_endpoint_storage_length(Base.tail(endpoints)),
)
@inline _packed_endpoint_storage_length(endpoints) = Int32(size(endpoints, 2))
@inline _packed_relation_endpoint(endpoints::Tuple, lane, position) =
    @inbounds endpoints[lane][position]
@inline _packed_relation_endpoint(endpoints, lane, position) =
    @inbounds endpoints[lane, position]
@inline function _relation_endpoint(
        view::_PackedIncidenceRelationView, item::Integer, lane::Integer,
    )
    degree = _relation_degree_bound(view)
    (1 <= item <= min(_packed_relation_count(view), view.capacity) &&
     1 <= lane <= min(degree, _packed_lane_count(view.endpoints))) ||
        return _missing_relation_endpoint(view.field_slot)
    position = _packed_relation_offset(view) + Int32(item) - Int32(1)
    (1 <= position <= length(view.active) &&
     position <= _packed_endpoint_storage_length(view.endpoints)) ||
        return _missing_relation_endpoint(view.field_slot)
    @inbounds view.active[position] || return _missing_relation_endpoint(view.field_slot)
    endpoint = Int32(_packed_relation_endpoint(view.endpoints, lane, position))
    return 1 <= endpoint <= view.codomain_count ?
        _physical_relation_endpoint(view.field_slot, endpoint) :
        _missing_relation_endpoint(view.field_slot)
end

struct _InverseRelationView{P<:_AbstractRelationDegree,D,I,E,S<:_PreparedFieldSlot}
    degree::P
    degrees::D
    incidents::I
    domain_extent::E
    relation_count::Int32
    field_slot::S
    function _InverseRelationView(
            degree::P, degrees::D, incidents::I,
            domain_extent::NTuple{N,<:Integer}, relation_count::Integer,
            field_slot::S,
        ) where {P<:_AbstractRelationDegree,D,I,N,S<:_PreparedFieldSlot}
        canonical_extent = _checked_relation_view_extent(domain_extent)
        count = _checked_relation_view_int32(
            relation_count, :relation_view_relation_count
        )
        return new{P,D,I,typeof(canonical_extent),S}(
            degree, degrees, incidents, canonical_extent, count, field_slot
        )
    end
end

@inline _relation_domain_extent(view::_InverseRelationView) = view.domain_extent
@inline _relation_codomain_extent(view::_InverseRelationView) = (view.relation_count,)
@inline _relation_degree_bound(view::_InverseRelationView) =
    _relation_degree_bound(view.degree)
@inline _inverse_incident(incidents::Tuple, item::Integer, lane::Integer) =
    @inbounds incidents[lane][item]
@inline _inverse_incident(incidents, item::Integer, lane::Integer) =
    @inbounds incidents[lane, item]
@inline _inverse_lane_count(incidents::Tuple) = Int32(length(incidents))
@inline _inverse_lane_count(incidents) = Int32(size(incidents, 1))
@inline _inverse_lane_capacity(incidents::Tuple, lane::Integer) =
    @inbounds Int32(length(incidents[lane]))
@inline _inverse_lane_capacity(incidents, lane::Integer) =
    Int32(size(incidents, 2))
@inline function _relation_endpoint(
        view::_InverseRelationView, item::Integer, lane::Integer,
    )
    degree = _relation_degree_bound(view)
    (1 <= item <= min(_relation_count(view.domain_extent), length(view.degrees)) &&
     1 <= lane <= min(degree, _inverse_lane_count(view.incidents)) &&
     item <= _inverse_lane_capacity(view.incidents, lane) &&
     1 <= lane <= min(Int32(@inbounds(view.degrees[item])), degree)) ||
        return _missing_relation_endpoint(view.field_slot)
    incident = Int32(_inverse_incident(view.incidents, item, lane))
    return 1 <= incident <= view.relation_count ?
        _physical_relation_endpoint(view.field_slot, incident) :
        _missing_relation_endpoint(view.field_slot)
end


struct _GroupedInverseRelationView{P<:_AbstractRelationDegree,O,I,E,S<:_PreparedFieldSlot}
    degree::P
    offsets::O
    incidents::I
    domain_extent::E
    relation_count::Int32
    field_slot::S
    function _GroupedInverseRelationView(
            degree::P, offsets::O, incidents::I,
            domain_extent::NTuple{D,<:Integer}, relation_count::Integer,
            field_slot::S,
        ) where {P<:_AbstractRelationDegree,O,I,D,S<:_PreparedFieldSlot}
        canonical_extent = _checked_relation_view_extent(domain_extent)
        count = _checked_relation_view_int32(
            relation_count, :relation_view_relation_count
        )
        length(offsets) >= _relation_count(canonical_extent) + 1 || throw(
            LocalMathValidationError(
                "a grouped inverse view requires one terminal CSR offset";
                stage = :prepare, contract = :relation_view_csr_offsets,
                expected = _relation_count(canonical_extent) + 1,
                actual = length(offsets),
            )
        )
        return new{P,O,I,typeof(canonical_extent),S}(
            degree, offsets, incidents, canonical_extent, count, field_slot
        )
    end
end


@inline _relation_domain_extent(view::_GroupedInverseRelationView) =
    view.domain_extent
@inline _relation_codomain_extent(view::_GroupedInverseRelationView) =
    (view.relation_count,)
@inline _relation_degree_bound(view::_GroupedInverseRelationView) =
    _relation_degree_bound(view.degree)
@inline function _relation_endpoint(
        view::_GroupedInverseRelationView, item::Integer, lane::Integer,
    )
    1 <= item <= _relation_count(view.domain_extent) ||
        return _missing_relation_endpoint(view.field_slot)
    start = Int32(@inbounds view.offsets[item])
    stop = Int32(@inbounds view.offsets[item + 1]) - Int32(1)
    count = max(Int32(0), stop - start + Int32(1))
    (1 <= lane <= min(count, _relation_degree_bound(view))) ||
        return _missing_relation_endpoint(view.field_slot)
    position = start + Int32(lane) - Int32(1)
    1 <= position <= length(view.incidents) ||
        return _missing_relation_endpoint(view.field_slot)
    incident = Int32(@inbounds view.incidents[position])
    return 1 <= incident <= view.relation_count ?
        _physical_relation_endpoint(view.field_slot, incident) :
        _missing_relation_endpoint(view.field_slot)
end

struct _RuntimeKeyRelationView{P<:_AbstractRelationDegree,D,S<:_PreparedFieldSlot}
    degree::P
    domain_extent::D
    codomain_count::Int32
    field_slot::S
    function _RuntimeKeyRelationView(
            degree::P, domain_extent::NTuple{N,<:Integer},
            codomain_count::Integer, field_slot::S,
        ) where {P<:_AbstractRelationDegree,N,S<:_PreparedFieldSlot}
        canonical_extent = _checked_relation_view_extent(domain_extent)
        codomain = _checked_relation_view_int32(
            codomain_count, :relation_view_codomain_count
        )
        return new{P,typeof(canonical_extent),S}(
            degree, canonical_extent, codomain, field_slot
        )
    end
end

for view_type in (
        :_IdentityRelationView, :_IndexRelationView, :_FieldIndexRelationView,
        :_AffineRelationView,
        :_FixedDegreeRelationView, :_ProductRelationView,
        :_PrefixInjectionRelationView, :_IndexInjectionRelationView,
        :_SelectedRelationView, :_SourceMaskRelationView,
        :_PackedIncidenceRelationView, :_InverseRelationView,
        :_GroupedInverseRelationView, :_RuntimeKeyRelationView,
    )
    @eval Adapt.@adapt_structure $view_type
end

function Adapt.adapt_structure(to, view::_ComposedRelationView)
    factors = Adapt.adapt(to, view.factors)
    field_slot = Adapt.adapt(to, view.field_slot)
    return _ComposedRelationView(factors, field_slot)
end

@inline _relation_domain_extent(view::_RuntimeKeyRelationView) = view.domain_extent
@inline _relation_codomain_extent(view::_RuntimeKeyRelationView) =
    (view.codomain_count,)
@inline _relation_degree_bound(view::_RuntimeKeyRelationView) =
    _relation_degree_bound(view.degree)
@inline function _relation_runtime_endpoint(
        view::_RuntimeKeyRelationView, key::Union{Int32,UInt32},
    )
    valid = key >= one(key) && UInt64(key) <= UInt64(view.codomain_count)
    return valid ? _physical_relation_endpoint(
        view.field_slot, Int32(key)
    ) : _missing_relation_endpoint(view.field_slot)
end

# Cold construction convenience only. Every constructor immediately converts an
# ordinal to a typed local slot; no prepared view stores the integer.
_IdentityRelationView(extent, slot::Integer) =
    _IdentityRelationView(extent, _PreparedFieldSlot(slot))
_IndexRelationView(extent, slot::Integer) =
    _IndexRelationView(extent, _PreparedFieldSlot(slot))
_AffineRelationView(domain, codomain, offsets, boundary, slot::Integer) =
    _AffineRelationView(domain, codomain, offsets, boundary, _PreparedFieldSlot(slot))
_FixedDegreeRelationView(degree, endpoints, counts, domain, codomain, slot::Integer) =
    _FixedDegreeRelationView(
        degree, endpoints, counts, domain, codomain, _PreparedFieldSlot(slot)
    )
_ProductRelationView(factors, slot::Integer) =
    _ProductRelationView(factors, _PreparedFieldSlot(slot))
_ComposedRelationView(factors, slot::Integer) =
    _ComposedRelationView(factors, _PreparedFieldSlot(slot))
_PrefixInjectionRelationView(count, capacity, codomain, slot::Integer) =
    _PrefixInjectionRelationView(count, capacity, codomain, _PreparedFieldSlot(slot))
_IndexInjectionRelationView(indices, count, capacity, codomain, slot::Integer) =
    _IndexInjectionRelationView(
        indices, count, capacity, codomain, _PreparedFieldSlot(slot)
    )
_PackedIncidenceRelationView(
    degree, active, endpoints, offsets, counts, generations, bank_slot,
    codomain, capacity, slot::Integer,
) = _PackedIncidenceRelationView(
    degree, active, endpoints, offsets, counts, generations, bank_slot,
    codomain, capacity, _PreparedFieldSlot(slot),
)
_InverseRelationView(degree, degrees, incidents, domain, count, slot::Integer) =
    _InverseRelationView(
        degree, degrees, incidents, domain, count, _PreparedFieldSlot(slot)
    )
_GroupedInverseRelationView(degree, offsets, incidents, domain, count, slot::Integer) =
    _GroupedInverseRelationView(
        degree, offsets, incidents, domain, count, _PreparedFieldSlot(slot)
    )
_RuntimeKeyRelationView(degree, domain, codomain, slot::Integer) =
    _RuntimeKeyRelationView(degree, domain, codomain, _PreparedFieldSlot(slot))
_GhostRelationBoundary(interior, lower, upper, indices, count, slot::Integer) =
    _GhostRelationBoundary(
        interior, lower, upper, indices, count, _PreparedFieldSlot(slot)
    )

@inline _relation_field_slot(::_RelationEndpoint{S}) where {S} = S()
@inline _relation_field_slot_index(endpoint::_RelationEndpoint) =
    _prepared_field_slot_index(_relation_field_slot(endpoint))

@inline _relation_target_slot(view::Union{
    _IdentityRelationView,_IndexRelationView,_FieldIndexRelationView,_AffineRelationView,
    _FixedDegreeRelationView,_ProductRelationView,_ComposedRelationView,
    _PrefixInjectionRelationView,
    _IndexInjectionRelationView,_PackedIncidenceRelationView,
    _InverseRelationView,_GroupedInverseRelationView,_RuntimeKeyRelationView,
}) = view.field_slot
@inline _relation_target_slot(view::_SelectedRelationView) =
    _relation_target_slot(view.base)
@inline _relation_target_slot(view::_SourceMaskRelationView) =
    _relation_target_slot(view.base)

"""Evaluate a relation against its prepared stage-local Field tuple.

Views without Field-dependent policy ignore `fields`; masked views specialize
this method and load their masks through `_PreparedFieldSlot`.
"""
@inline _relation_endpoint(view, fields::Tuple, item::Integer, lane::Integer = 1) =
    _relation_endpoint(view, item, lane)
@inline _relation_runtime_endpoint(
        view, fields::Tuple, key::Union{Int32,UInt32},
    ) = _relation_runtime_endpoint(view, key)

# Cold proof/preparation facts and the immutable value recorded by warm device
# validation. They deliberately provide no host-side freshness comparison.
struct _RelationSchemaFacts{I,B,D,C,H}
    relation_identity::I
    schema_epoch::UInt64
    binding_identity::B
    domain_extent::D
    codomain_extent::C
    halo::H
end

struct _RelationContentGenerationRef{G}
    generations::G
    slot::Int32

    function _RelationContentGenerationRef(generations::G, slot::Integer) where {G}
        checked_slot = _checked_relation_view_int32(
            slot, :relation_view_generation_slot; positive = true
        )
        checked_slot <= length(generations) || throw(LocalMathValidationError(
            "a content-generation reference slot is outside its device storage";
            stage = :prepare, contract = :relation_view_generation_slot,
            expected = :bound_generation_slot, actual = checked_slot,
        ))
        return new{G}(generations, checked_slot)
    end
end
Adapt.@adapt_structure _RelationContentGenerationRef

@inline _relation_content_generation(reference::_RelationContentGenerationRef) =
    @inbounds UInt64(reference.generations[reference.slot])

struct _RelationStatusRef{S,G}
    statuses::S
    validated_generations::G
    slot::Int32

    function _RelationStatusRef(
            statuses::S, validated_generations::G, slot::Integer,
        ) where {S,G}
        checked_slot = _checked_relation_view_int32(
            slot, :relation_view_status_slot; positive = true
        )
        checked_slot <= length(statuses) || throw(LocalMathValidationError(
            "a relation status reference slot is outside its device storage";
            stage = :prepare, contract = :relation_view_status_slot,
            expected = :bound_status_slot, actual = checked_slot,
        ))
        validated_generations === nothing ||
            checked_slot <= length(validated_generations) || throw(
                LocalMathValidationError(
                    "a validated-generation reference slot is outside its device storage";
                    stage = :prepare,
                    contract = :relation_view_validated_generation_slot,
                    expected = :bound_status_slot, actual = checked_slot,
                )
            )
        return new{S,G}(statuses, validated_generations, checked_slot)
    end
end
Adapt.@adapt_structure _RelationStatusRef

@inline _relation_content_status(reference::_RelationStatusRef) =
    @inbounds reference.statuses[reference.slot]
@inline _relation_validated_generation(
        reference::_RelationStatusRef{S,Nothing},
    ) where {S} = nothing
@inline _relation_validated_generation(reference::_RelationStatusRef) =
    @inbounds UInt64(reference.validated_generations[reference.slot])
