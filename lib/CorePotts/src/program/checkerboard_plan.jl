# Deterministic realized-domain coloring for the portable checkerboard engine.

abstract type AbstractCheckerboardPlan end

struct NoCheckerboardPlan <: AbstractCheckerboardPlan end

struct CheckerboardPlan{
        S <: AbstractVector{Int32},
        O <: AbstractVector{Int32},
        D <: AbstractMatrix{Int16},
    } <: AbstractCheckerboardPlan
    sites::S
    color_offsets::O
    conflict_displacements::D
    color_count::Int32
    maximum_color_size::Int32
end

function _canonical_conflict_displacements(
        displacements::AbstractMatrix{<:Integer},
        dimensions::Integer,
    )
    size(displacements, 1) == dimensions || throw(ArgumentError(
        "checkerboard conflict displacements have the wrong dimensionality"
    ))
    values = NTuple{dimensions, Int}[]
    for column in axes(displacements, 2)
        displacement = ntuple(
            dimension -> Int(displacements[dimension, column]), dimensions
        )
        all(iszero, displacement) && continue
        all(value -> typemin(Int16) <= value <= typemax(Int16), displacement) ||
            throw(ArgumentError(
                "checkerboard conflict displacement exceeds Int16"
            ))
        push!(values, displacement)
        push!(values, ntuple(index -> -displacement[index], dimensions))
    end
    sort!(unique!(values))
    result = Matrix{Int16}(undef, dimensions, length(values))
    for (column, displacement) in enumerate(values)
        for dimension in 1:dimensions
            result[dimension, column] = Int16(displacement[dimension])
        end
    end
    return result
end

@inline function _realized_conflict_site(
        shape::NTuple{N, Int},
        periodic::NTuple{N, Bool},
        indices::CartesianIndices{N},
        linear::LinearIndices{N},
        site::Int,
        displacements::Matrix{Int16},
        column::Int,
    ) where {N}
    coordinates = Tuple(indices[site])
    neighbor = ntuple(N) do dimension
        value = coordinates[dimension] + Int(displacements[dimension, column])
        if periodic[dimension]
            mod1(value, shape[dimension])
        elseif 1 <= value <= shape[dimension]
            value
        else
            0
        end
    end
    any(iszero, neighbor) && return 0
    return linear[CartesianIndex(neighbor)]
end

function CheckerboardPlan(
        shape::NTuple{N, Int},
        periodic::NTuple{N, Bool},
        displacements::AbstractMatrix{<:Integer},
    ) where {N}
    all(>(0), shape) || throw(ArgumentError(
        "checkerboard dimensions must be positive"
    ))
    canonical = _canonical_conflict_displacements(displacements, N)
    site_count = prod(shape; init = 1)
    indices = CartesianIndices(shape)
    linear = LinearIndices(shape)
    colors = zeros(Int32, site_count)
    forbidden = falses(size(canonical, 2) + 1)
    maximum_color = 0
    for site in 1:site_count
        fill!(forbidden, false)
        for column in axes(canonical, 2)
            neighbor = _realized_conflict_site(
                shape, periodic, indices, linear, site, canonical, column
            )
            (neighbor == 0 || neighbor >= site) && continue
            color = Int(@inbounds colors[neighbor])
            color > 0 && (forbidden[color] = true)
        end
        color = something(findfirst(!, forbidden), length(forbidden) + 1)
        color <= typemax(Int32) || throw(ArgumentError(
            "checkerboard coloring exceeds Int32"
        ))
        colors[site] = Int32(color)
        maximum_color = max(maximum_color, color)
    end

    for site in 1:site_count, column in axes(canonical, 2)
        neighbor = _realized_conflict_site(
            shape, periodic, indices, linear, site, canonical, column
        )
        (neighbor == 0 || neighbor == site) && continue
        @inbounds colors[neighbor] != colors[site] || error(
            "checkerboard realized-domain coloring verification failed"
        )
    end

    sites = Int32[]
    offsets = Int32[1]
    maximum_color_size = 0
    for color in 1:maximum_color
        first_index = length(sites) + 1
        for site in 1:site_count
            @inbounds colors[site] == color && push!(sites, Int32(site))
        end
        push!(offsets, Int32(length(sites) + 1))
        maximum_color_size = max(
            maximum_color_size, length(sites) - first_index + 1
        )
    end
    length(sites) == site_count || error(
        "checkerboard coloring did not schedule every site exactly once"
    )
    return CheckerboardPlan(
        sites,
        offsets,
        canonical,
        Int32(maximum_color),
        Int32(maximum_color_size),
    )
end

function checkerboard_plan_report(plan::CheckerboardPlan)
    return (
        algorithm = :canonical_realized_greedy_v1,
        color_count = Int(plan.color_count),
        maximum_color_size = Int(plan.maximum_color_size),
        site_count = length(plan.sites),
        conflict_displacements = Tuple(
            Tuple(plan.conflict_displacements[:, column])
            for column in axes(plan.conflict_displacements, 2)
        ),
    )
end

checkerboard_plan_report(::NoCheckerboardPlan) = nothing

Adapt.@adapt_structure CheckerboardPlan
