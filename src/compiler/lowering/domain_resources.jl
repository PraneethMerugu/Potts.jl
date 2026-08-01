# Conservative-energy resource tables. Counts and identities remain values.

function _offset_matrix(offsets, dimensions)
    isempty(offsets) &&
        throw(ArgumentError("a spatial relation requires at least one offset"))
    result = Matrix{Int8}(undef, dimensions, length(offsets))
    for (column, offset) in enumerate(offsets), dimension in 1:dimensions
        typemin(Int8) <= offset[dimension] <= typemax(Int8) ||
            throw(ArgumentError("V1 relation radius exceeds Int8 storage"))
        result[dimension, column] = Int8(offset[dimension])
    end
    return result
end

function _neighborhood_offsets(neighborhood::VonNeumann, dimensions::Int)
    radius = neighborhood.radius
    offsets = NTuple{dimensions, Int}[]
    for dimension in 1:dimensions, distance in 1:radius
        push!(offsets, ntuple(i -> i == dimension ? distance : 0, dimensions))
        push!(offsets, ntuple(i -> i == dimension ? -distance : 0, dimensions))
    end
    return _offset_matrix(offsets, dimensions)
end

function _neighborhood_offsets(neighborhood::Moore, dimensions::Int)
    radius = neighborhood.radius
    ranges = ntuple(_ -> (-radius):radius, dimensions)
    offsets = NTuple{dimensions, Int}[]
    for candidate in Iterators.product(ranges...)
        all(iszero, candidate) && continue
        push!(offsets, Tuple(candidate))
    end
    sort!(offsets)
    return _offset_matrix(offsets, dimensions)
end

function _hamiltonian_domain_resources(
        ir::AnalyzedTermIR,
        relationship_endpoint_policies,
    )
    source_count = length(ir.source.records)
    dimensions = length(_lattice_shape(ir))
    contact_starts = zeros(Int32, source_count)
    contact_counts = zeros(Int32, source_count)
    relationship_slots = zeros(Int32, source_count)

    relation_offsets = Matrix{Int8}[]
    total_offsets = 0
    for (handle, record) in enumerate(ir.source.records)
        if record.kind === :SpatialRelation
            options = _record_options(record)
            neighborhood = get(options, :neighborhood, nothing)
            neighborhood isa Union{VonNeumann, Moore} || continue
            offsets = _neighborhood_offsets(neighborhood, dimensions)
            push!(relation_offsets, offsets)
            contact_starts[handle] = Int32(total_offsets + 1)
            contact_counts[handle] = Int32(size(offsets, 2))
            total_offsets += size(offsets, 2)
        elseif record.kind === :RelationshipState
            relationship_slots[handle] = _relationship_endpoint_policy(
                relationship_endpoint_policies, record.identity
            ).slot
        end
    end

    offsets = Matrix{Int8}(undef, dimensions, total_offsets)
    cursor = 1
    for relation in relation_offsets
        count = size(relation, 2)
        offsets[:, cursor:(cursor + count - 1)] .= relation
        cursor += count
    end
    return CorePotts.HamiltonianDomainResources(
        offsets,
        contact_starts,
        contact_counts,
        relationship_slots,
    )
end
