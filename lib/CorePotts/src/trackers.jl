# Site-sum and site-minimum trackers over each cell's sites.

"""
`sum[c] = Σ_{s ∈ c} v[s]`: move the target's value `v` from the old to the new cell. Any
additive isbits type works, e.g. `SVector` for structured (vector-valued) owner sums.
"""
@inline function commit_site_sum!(sum, prop, v)
    prop.old != 0 && @inbounds(sum[prop.old] -= v)
    prop.new != 0 && @inbounds(sum[prop.new] += v)
    return nothing
end

"""Site sums from scratch: `sum[c] = Σ_{σ[s] = c} values[s]`."""
function recompute_site_sum(σ, values, ncell::Integer; T::Type = eltype(values))
    S = zeros(T, ncell)
    for i in eachindex(σ, values)
        σ[i] != 0 && (S[σ[i]] += values[i])
    end
    return S
end

"""
    commit_site_min!(minimum, stale, prop, v)

`minimum[c] = min_{s ∈ c} v[s]`. Gaining a site is exact; losing the site that holds the
minimum marks the cell `stale` (the true minimum can only rise), and
`recompute_site_min!` restores it at the next synchronization point.
"""
@inline function commit_site_min!(minimum, stale, prop, v)
    if prop.new != 0
        @inbounds minimum[prop.new] = min(minimum[prop.new], v)
    end
    if prop.old != 0 && v <= @inbounds(minimum[prop.old])
        @inbounds stale[prop.old] = true
    end
    return nothing
end

"""Recompute the stale minima (all of them with `all = true`) on the host."""
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
