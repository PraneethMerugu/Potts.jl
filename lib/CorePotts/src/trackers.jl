# Site-sum and site-minimum trackers over each cell's sites.

"""
    commit_site_sum!(sum, prop, v) -> nothing

Keep the tracker `sum[c] = Σ_{s ∈ c} v[s]` up to date: move the target's value `v` from
the losing to the gaining cell.

Any additive isbits type works, for example an `SVector` for vector-valued sums. The
medium (`0`) has no entry. The update is not atomic.

# Arguments
- `sum::AbstractVector`: the tracker, one entry per cell.
- `prop::Proposal`: the accepted copy.
- `v`: the target site's value.

# Returns
- `nothing`.

See also [`recompute_site_sum`](@ref), [`commit_site_min!`](@ref).
"""
@inline function commit_site_sum!(sum, prop, v)
    # bounds: nonzero owners are cell ids ≤ capacity = length(sum)
    prop.old != 0 && @inbounds(sum[prop.old] -= v)
    prop.new != 0 && @inbounds(sum[prop.new] += v)
    return nothing
end

"""
    recompute_site_sum(σ, values, ncell; T = eltype(values)) -> Vector{T}

Compute `sum[c] = Σ_{σ[s] = c} values[s]` for every cell from scratch.

# Arguments
- `σ`: the `ownership` array, on the host.
- `values`: the site values, shaped like `σ`.
- `ncell::Integer`: the number of cell slots.

# Keywords
- `T::Type = eltype(values)`: the element type of the sums.

# Returns
- `Vector{T}`: one sum per cell slot.

# Examples
```jldoctest
julia> using CorePotts

julia> recompute_site_sum(Int32[1 2; 1 0], [1.0 2.0; 3.0 4.0], 2)
2-element Vector{Float64}:
 4.0
 2.0
```

See also [`commit_site_sum!`](@ref).
"""
function recompute_site_sum(σ, values, ncell::Integer; T::Type = eltype(values))
    S = zeros(T, ncell)
    for i in eachindex(σ, values)
        σ[i] != 0 && (S[σ[i]] += values[i])
    end
    return S
end

"""
    commit_site_min!(minimum, stale, prop, v) -> nothing

Keep the tracker `minimum[c] = min_{s ∈ c} v[s]` up to date for an accepted copy.

Gaining a site is exact. When the losing cell loses a value `≤` its minimum, the cell is
marked `stale`, since its true minimum can only rise. [`recompute_site_min!`](@ref)
restores the stale minima at the next synchronization point.

# Arguments
- `minimum::AbstractVector`: the tracker, one entry per cell.
- `stale::AbstractVector{Bool}`: the stale flags, one per cell.
- `prop::Proposal`: the accepted copy.
- `v`: the target site's value.

# Returns
- `nothing`.

See also [`recompute_site_min!`](@ref), [`commit_site_sum!`](@ref).
"""
@inline function commit_site_min!(minimum, stale, prop, v)
    if prop.new != 0
        # bounds: nonzero owners are cell ids ≤ capacity = length(minimum) = length(stale)
        @inbounds minimum[prop.new] = min(minimum[prop.new], v)
    end
    if prop.old != 0 && v <= @inbounds(minimum[prop.old])
        @inbounds stale[prop.old] = true
    end
    return nothing
end

"""
    recompute_site_min!(minimum, stale, σ, values; all = false) -> minimum

Recompute the stale entries of the site-minimum tracker on the host, and clear `stale`.

A cell with no sites gets `typemax(eltype(minimum))`.

# Arguments
- `minimum::AbstractVector`: the tracker, updated in place.
- `stale::AbstractVector{Bool}`: the stale flags; all set to `false` on return.
- `σ`: the `ownership` array.
- `values`: the site values, shaped like `σ`.

# Keywords
- `all::Bool = false`: recompute every entry, not only the stale ones.

# Returns
- `minimum`.

# Examples
```jldoctest
julia> using CorePotts

julia> σ = Int32[1 2; 1 0]; v = [1.0 2.0; 3.0 4.0];

julia> recompute_site_min!(zeros(2), falses(2), σ, v; all = true)
2-element Vector{Float64}:
 1.0
 2.0
```

See also [`commit_site_min!`](@ref).
"""
function recompute_site_min!(minimum, stale, σ, values; all::Bool = false)
    for c in eachindex(minimum)
        (all || stale[c]) && (minimum[c] = typemax(eltype(minimum)))
    end
    for i in eachindex(σ, values)
        c = σ[i]
        (c != 0 && (all || stale[c])) || continue
        minimum[c] = min(minimum[c], values[i])
    end
    fill!(stale, false)
    return minimum
end
