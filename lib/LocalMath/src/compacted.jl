# Typed semantic and storage foundation for bounded canonical materialization.
# Execution algorithms are deliberately absent from this unit: these values
# describe scientific meaning, storage ownership, and downstream references.

struct _OneGroup end
struct _GroupBy{E}
    extractor::E
    count::Int32
end
"""Dense group keys are supplied independently by each emitted record."""
struct _RoutedGroups
    count::Int32
end
_is_grouped(::_OneGroup) = false
_is_grouped(::Union{_GroupBy,_RoutedGroups}) = true

struct _NoPersistentProjection end
struct _PersistentSourcePosition end

const _COMPACTED_MAX_ORDINAL = Int32(typemax(Int32) - 1)

"""
    BoundedGroupView{K,T}

Finite read-only view of one dynamic compacted group. `K` is the declared
positive Int32 occupancy bound, not a register-tuple size. Iteration and indexed
reads visit only the device-produced live segment.
"""
struct BoundedGroupView{K, T, R, V}
    records::R
    first::Int32
    count::Int32
    validation::V

    function BoundedGroupView(
            ::_ConstructionToken,
            ::Val{K},
            ::Type{T},
            records::R,
            first::Int32,
            count::Int32,
            validation::V,
        ) where {K, T, R, V}
        return new{K, T, R, V}(records, first, count, validation)
    end
end

function Base.getproperty(::BoundedGroupView, name::Symbol)
    throw(ArgumentError(
        "bounded Collection groups expose only length, indexing, and iteration"))
end


function _bounded_group_view(
        records,
        first::Int32,
        count::Int32,
        ::Val{K},
    ) where {K}
    1 <= K <= _COMPACTED_MAX_ORDINAL || throw(ArgumentError(
        "a bounded group view requires a positive nonterminal Int32 bound"
    ))
    0 <= count <= K || throw(ArgumentError(
        "a bounded group view count exceeds its declared occupancy bound"
    ))
    record_count = length(records)
    1 <= first <= record_count + 1 || throw(ArgumentError(
        "a bounded group view start lies outside its record storage"
    ))
    Int64(first) + Int64(count) - 1 <= record_count || throw(ArgumentError(
        "a bounded group view segment lies outside its record storage"
    ))
    return BoundedGroupView(_CONSTRUCTION_TOKEN, Val(K), eltype(records),
        records, first, count, _NoEvaluationValidation())
end

Base.eltype(::Type{BoundedGroupView{K, T}}) where {K, T} = T
Base.eltype(::BoundedGroupView{K, T}) where {K, T} = T
Base.length(view::BoundedGroupView) = Int(getfield(view, :count))
Base.firstindex(::BoundedGroupView) = 1
Base.lastindex(view::BoundedGroupView) = Int(getfield(view, :count))
@inline function Base.getindex(view::BoundedGroupView{K}, index::Integer) where {K}
    count = getfield(view, :count)
    first = getfield(view, :first)
    records = getfield(view, :records)
    @boundscheck begin
        0 <= count <= K || throw(BoundsError(view, index))
        1 <= index <= count || throw(BoundsError(view, index))
        1 <= first || throw(BoundsError(view, index))
        Int64(first) + Int64(count) - 1 <= length(records) ||
            throw(BoundsError(view, index))
    end
    return @inbounds records[Int(first) + Int(index) - 1]
end
@inline Base.iterate(view::BoundedGroupView, index::Int32 = Int32(1)) =
    index > getfield(view, :count) ? nothing :
        (@inbounds(view[index]), index + Int32(1))
@inline Base.iterate(view::BoundedGroupView, index::Int) =
    index > Int(getfield(view, :count)) ? nothing :
        (@inbounds(view[index]), index + 1)

"""
    CompactedStorage

One logical storage authority for a compacted port. `records` is bounded
component storage, `count` is one device-resident `Int32`, `segment_starts` is
either `nothing` or a device `Int32[G+1]` directory, and `source_item` plus
`source_lane` retain provenance. `source_position` is present only when a
typed downstream request demands that projection. This value is not an
`AbstractArray`; its inactive record tail has no value semantics.
"""
struct CompactedStorage{R, C, S, I, L, P}
    records::R
    count::C
    segment_starts::S
    source_item::I
    source_lane::L
    source_position::P

    function CompactedStorage(
            ::_ConstructionToken,
            records::R,
            count::C,
            segment_starts::S,
            source_item::I,
            source_lane::L,
            source_position::P,
        ) where {R, C, S, I, L, P}
        return new{R, C, S, I, L, P}(
            records, count, segment_starts, source_item, source_lane,
            source_position,
        )
    end
end

CompactedStorage(records, count, segment_starts, source_item, source_lane,
        source_position) = CompactedStorage(
    _CONSTRUCTION_TOKEN, records, count, segment_starts, source_item,
    source_lane, source_position)

function _compacted_positive_int32(value, purpose)
    value isa Bool && throw(ArgumentError("$purpose must be an integer"))
    value isa Integer || throw(ArgumentError("$purpose must be an integer"))
    1 <= value <= _COMPACTED_MAX_ORDINAL || throw(ArgumentError(
        "$purpose must be a positive nonterminal Int32 bound"
    ))
    return Int32(value)
end

"""`one_group()` declares one dense result group with key `Int32(1)`."""
one_group() = _OneGroup()

"""
    group_by(extractor; count)

Declare dense exact group keys `1:count`. `extractor` is a concrete
storage-free callable or an exact emitted-field symbol. Runtime keys outside
that closed bound are structural errors; zero is not a group.
"""
function group_by(extractor; count)
    return _GroupBy(
        _ordering_extractor(extractor, "group extractor"),
        _compacted_positive_int32(count, "group count"),
    )
end
_routed_groups(count) = _RoutedGroups(
    _compacted_positive_int32(count, "routed group count"))

"""
    persistent_source_position()

Demand a persistent inverse source-position projection for a Stage `Collect`
law. The projection remains part of the collection's sole `CompactedStorage`
authority and is consumed through typed `SourcePositionAccess`.
"""
persistent_source_position() = _PersistentSourcePosition()

function _compacted_group_count(::_OneGroup)
    return Int32(1)
end
_compacted_group_count(groups::_GroupBy) = groups.count
_compacted_group_count(groups::_RoutedGroups) = groups.count

function _allocate_compacted_records(backend, ::Type{T}, capacity::Int) where {T}
    fieldcount(T) == 0 && return KernelAbstractions.allocate(
        backend, T, (capacity,)
    )
    isconcretetype(T) && isbitstype(T) && _storage_free_type(T) || throw(
        ArgumentError(
            "compacted records must have a concrete device-safe storage-free isbits type"
        )
    )
    component_values = ntuple(fieldcount(T)) do index
        _allocate_compacted_records(backend, fieldtype(T, index), capacity)
    end
    components = T <: Tuple ? component_values :
        NamedTuple{fieldnames(T)}(component_values)
    records = StructArrays.StructArray{T}(components)
    allocated = values(components)
    retained = values(StructArrays.components(records))
    all(index -> retained[index] === allocated[index], eachindex(allocated)) ||
        throw(ArgumentError(
            "compacted StructArray construction must retain zero-copy component identity"
        ))
    return records
end

function CompactedStorage(
        backend::KernelAbstractions.Backend, ::Type{T}, capacity::Integer;
        group_count::Union{Nothing,Integer} = nothing,
        source_items::Integer = capacity,
        source_position::Bool = false,
    ) where {T}
    capacity isa Bool && throw(ArgumentError("capacity must be an integer"))
    source_items isa Bool && throw(ArgumentError("source_items must be an integer"))
    capacity >= 0 || throw(ArgumentError("capacity must be nonnegative"))
    source_items >= 0 || throw(ArgumentError("source_items must be nonnegative"))
    group_count === nothing || (group_count isa Integer && !(group_count isa Bool) &&
        group_count >= 0) || throw(ArgumentError(
        "group_count must be a nonnegative integer or nothing"))
    count = KernelAbstractions.allocate(backend, Int32, (1,))
    segments = group_count === nothing ? nothing :
        KernelAbstractions.allocate(backend, Int32, (Int(group_count) + 1,))
    source_item = KernelAbstractions.allocate(backend, Int32, (Int(capacity),))
    source_lane = KernelAbstractions.allocate(backend, Int32, (Int(capacity),))
    projection = source_position ?
        KernelAbstractions.allocate(backend, Int32, (Int(source_items),)) : nothing
    return CompactedStorage(_CONSTRUCTION_TOKEN,
        _allocate_compacted_records(backend, T, Int(capacity)), count, segments,
        source_item, source_lane, projection)
end

function _compacted_binding_components(storage::CompactedStorage)
    return _compacted_binding_components(
        storage, storage.segment_starts, storage.source_position
    )
end
_compacted_binding_components(storage, ::Nothing, ::Nothing) = (
    records = storage.records, count = storage.count,
    source_item = storage.source_item, source_lane = storage.source_lane,
)
_compacted_binding_components(storage, segment_starts, ::Nothing) = (
    records = storage.records, count = storage.count,
    segment_starts, source_item = storage.source_item,
    source_lane = storage.source_lane,
)
_compacted_binding_components(storage, ::Nothing, source_position) = (
    records = storage.records, count = storage.count,
    source_item = storage.source_item, source_lane = storage.source_lane,
    source_position,
)
_compacted_binding_components(storage, segment_starts, source_position) = (
    records = storage.records, count = storage.count,
    segment_starts, source_item = storage.source_item,
    source_lane = storage.source_lane, source_position,
)

_compacted_physical_leaves(storage::CompactedStorage) =
    _binding_physical_leaves(:compacted, storage)

function _validate_compacted_record_storage(records, ::Type{T}, capacity) where {T}
    eltype(records) === T && size(records) == (capacity,) || throw(
        ArgumentError(
            "compacted record storage must preserve its exact type and capacity"
        )
    )
    if fieldcount(T) == 0
        records isa AbstractArray || throw(ArgumentError(
            "primitive compacted records require array storage"
        ))
        return nothing
    end
    records isa StructArrays.StructArray{T} || throw(ArgumentError(
        "composite compacted records require recursive StructArray storage"
    ))
    components = StructArrays.components(records)
    length(components) == fieldcount(T) || throw(ArgumentError(
        "compacted StructArray has the wrong component arity"
    ))
    T <: Tuple || keys(components) == fieldnames(T) || throw(ArgumentError(
        "compacted StructArray fields do not match the record type"
    ))
    for index in 1:fieldcount(T)
        _validate_compacted_record_storage(
            values(components)[index], fieldtype(T, index), capacity
        )
    end
    rebuilt = StructArrays.StructArray{T}(components)
    rebuilt_components = values(StructArrays.components(rebuilt))
    all(index -> rebuilt_components[index] === values(components)[index],
        eachindex(rebuilt_components)) || throw(ArgumentError(
            "compacted StructArray components must be zero-copy"
        ))
    return nothing
end

Adapt.adapt_structure(to, storage::CompactedStorage) = CompactedStorage(
    _CONSTRUCTION_TOKEN,
    Adapt.adapt(to, storage.records),
    Adapt.adapt(to, storage.count),
    Adapt.adapt(to, storage.segment_starts),
    Adapt.adapt(to, storage.source_item),
    Adapt.adapt(to, storage.source_lane),
    Adapt.adapt(to, storage.source_position),
)

Adapt.adapt_structure(to, view::BoundedGroupView{K}) where {K} =
    BoundedGroupView(_CONSTRUCTION_TOKEN, Val(K), eltype(view),
        Adapt.adapt(to, getfield(view, :records)), getfield(view, :first),
        getfield(view, :count), Adapt.adapt(to, getfield(view, :validation)))

Base.show(io::IO, ::CompactedStorage) = print(io, "CompactedStorage(",
    "records, count, directory, provenance, source_position)")
