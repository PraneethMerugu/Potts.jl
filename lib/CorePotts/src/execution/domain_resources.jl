# Value-level tables for resources selected by conservative-energy domains.

struct _ValidatedDomainResourceAdaptation end

struct HamiltonianDomainResources{
        O <: AbstractMatrix{Int8},
        V <: AbstractVector{Int32},
    }
    contact_offsets::O
    contact_starts::V
    contact_counts::V
    relationship_slots::V
    function HamiltonianDomainResources{O, V}(
            contact_offsets::O,
            contact_starts::V,
            contact_counts::V,
            relationship_slots::V,
        ) where {
            O <: AbstractMatrix{Int8},
            V <: AbstractVector{Int32},
        }
        length(contact_starts) == length(contact_counts) ==
            length(relationship_slots) || throw(ArgumentError(
            "Hamiltonian domain-resource tables must share one source-handle range"
        ))
        for handle in eachindex(contact_starts)
            start = contact_starts[handle]
            count = contact_counts[handle]
            count >= 0 || throw(ArgumentError(
                "a contact-domain offset count cannot be negative"
            ))
            if count == 0
                start == 0 || throw(ArgumentError(
                    "an unused contact-domain handle must have a zero start"
                ))
            else
                start > 0 && start + count - 1 <= size(contact_offsets, 2) ||
                    throw(ArgumentError(
                        "a contact-domain handle addresses offsets outside its table"
                    ))
            end
            relationship_slots[handle] >= 0 || throw(ArgumentError(
                "a relationship-domain slot cannot be negative"
            ))
        end
        return new{O, V}(
            contact_offsets,
            contact_starts,
            contact_counts,
            relationship_slots,
        )
    end

    function HamiltonianDomainResources{O, V}(
            contact_offsets::O,
            contact_starts::V,
            contact_counts::V,
            relationship_slots::V,
            ::_ValidatedDomainResourceAdaptation,
        ) where {
            O <: AbstractMatrix{Int8},
            V <: AbstractVector{Int32},
        }
        return new{O, V}(
            contact_offsets,
            contact_starts,
            contact_counts,
            relationship_slots,
        )
    end
end

function HamiltonianDomainResources(
        contact_offsets::AbstractMatrix{Int8},
        contact_starts::AbstractVector{<:Integer},
        contact_counts::AbstractVector{<:Integer},
        relationship_slots::AbstractVector{<:Integer},
    )
    starts = Int32.(contact_starts)
    counts = Int32.(contact_counts)
    slots = Int32.(relationship_slots)
    return HamiltonianDomainResources{
        typeof(contact_offsets), typeof(starts),
    }(contact_offsets, starts, counts, slots)
end

HamiltonianDomainResources(dimensions::Integer, source_count::Integer) =
    HamiltonianDomainResources(
        Matrix{Int8}(undef, dimensions, 0),
        zeros(Int32, source_count),
        zeros(Int32, source_count),
        zeros(Int32, source_count),
    )

@inline function _contact_domain_columns(
        resources::HamiltonianDomainResources,
        handle::Int32,
    )
    1 <= handle <= length(resources.contact_starts) || throw(ArgumentError(
        "contact energy domain references an unknown resource handle"
    ))
    start = @inbounds resources.contact_starts[handle]
    count = @inbounds resources.contact_counts[handle]
    start > 0 && count > 0 || throw(ArgumentError(
        "contact energy domain does not resolve to a finite offset table"
    ))
    return start, count
end

@inline function _relationship_domain_slot(
        resources::HamiltonianDomainResources,
        handle::Int32,
    )
    1 <= handle <= length(resources.relationship_slots) || throw(ArgumentError(
        "relationship energy domain references an unknown resource handle"
    ))
    slot = @inbounds resources.relationship_slots[handle]
    slot > 0 || throw(ArgumentError(
        "relationship energy domain does not resolve to runtime storage"
    ))
    return slot
end

function Adapt.adapt_structure(to, resources::HamiltonianDomainResources)
    offsets = Adapt.adapt(to, resources.contact_offsets)
    starts = Adapt.adapt(to, resources.contact_starts)
    counts = Adapt.adapt(to, resources.contact_counts)
    slots = Adapt.adapt(to, resources.relationship_slots)
    return HamiltonianDomainResources{
        typeof(offsets), typeof(starts),
    }(
        offsets,
        starts,
        counts,
        slots,
        _ValidatedDomainResourceAdaptation(),
    )
end
