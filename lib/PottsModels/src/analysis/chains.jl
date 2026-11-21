# Chains of cells along a periodic axis and relaxation curves: centroids unwrapped along a
# chain, the chain's width, the first crossing of a level and the mean squared error
# against a reference curve on a rescaled time axis.

"""
    chain_centroids(σ) -> Vector{Float64}

Return the axis-1 centroid of every cell `1:maximum(σ)` on a lattice periodic along
axis 1, unwrapped along the chain the cells form.

The centroids are [`centroids`](@ref)`(σ; periodic = (true, …))`. The circle of length
`L = size(σ, 1)` is cut at the largest gap between cyclically consecutive centroids, and
`L` is added to every centroid before the cut. The chain then reads left to right with no
jump at the seam, and its leftmost cell lies in `[1, L + 1)`.

The result is the chain's geometry only while the chain is shorter than `L` minus its
largest internal gap, so that the medium gap between its ends is the largest.

# Arguments
- `σ::AbstractArray{<:Integer}`: the ownership. Throws an `ArgumentError` when a cell
  number up to `maximum(σ)` owns no site.

# Returns
- `Vector{Float64}`: the unwrapped centroid of each cell.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> σ = zeros(Int, 30, 5); σ[[28, 29, 30, 1, 2], :] .= 1; σ[3:7, :] .= 2;

julia> chain_centroids(σ)    # cell 2 sits past the seam
2-element Vector{Float64}:
 30.0
 35.0
```

See also [`chain_width`](@ref).
"""
function chain_centroids(σ::AbstractArray{<:Integer})
    L = size(σ, 1)
    x = [c[1] for c in centroids(σ; periodic = true)]
    any(isnan, x) &&
        throw(ArgumentError("chain_centroids: id $(findfirst(isnan, x)) owns no site"))
    n = length(x)
    n <= 1 && return x
    p = sortperm(x)
    s = x[p]
    k, gap = n, s[1] + L - s[n]                     # the gap across the seam
    for i in 1:(n - 1)
        if s[i + 1] - s[i] > gap
            k, gap = i, s[i + 1] - s[i]
        end
    end
    for i in 1:k
        k == n && break
        x[p[i]] += L
    end
    return x
end

"""
    chain_width(σ, cells = 1:maximum(σ); CD = 10) -> Float64

Return the extent of a chain of cells along axis 1, `(max − min)` of
[`chain_centroids`](@ref)`(σ)[cells]`, in units of `CD` lattice sites (a cell diameter).

# Arguments
- `σ::AbstractArray{<:Integer}`: the ownership.
- `cells = 1:maximum(σ)`: the cells of the chain, for example the inner cells of a longer
  chain. Throws an `ArgumentError` when empty or when `σ` owns no site.

# Keywords
- `CD = 10`: the cell diameter, in sites.

# Returns
- `Float64`: the width, in cell diameters.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> σ = zeros(Int, 30, 5); σ[[28, 29, 30, 1, 2], :] .= 1; σ[3:7, :] .= 2;

julia> chain_width(σ)
0.5
```

See also [`chain_centroids`](@ref), [`crossing_time`](@ref).
"""
function chain_width(
        σ::AbstractArray{<:Integer}, cells = 1:Int(maximum(σ; init = 0));
        CD = 10
    )
    xs = chain_centroids(σ)[cells]
    isempty(xs) &&
        throw(ArgumentError("chain_width: no cells (σ owns no site, or `cells` is empty)"))
    return (maximum(xs) - minimum(xs)) / CD
end

"""
    crossing_time(t, w, level = 9.0)

Return `t[i]` for the first `i` with `w[i] ≥ level`, or `nothing` if `w` never reaches
`level`.

Later dips below `level` do not matter.

# Arguments
- `t`: the times.
- `w`: the values, as many as `t`. Throws an `ArgumentError` otherwise.
- `level = 9.0`: the level.

# Returns
- The element of `t` at the first crossing, or `nothing`.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> crossing_time(0:4, [5.0, 8.0, 9.5, 8.9, 10.0])
2
```

See also [`relaxation_mse`](@ref), [`chain_width`](@ref).
"""
function crossing_time(t, w, level = 9.0)
    length(t) == length(w) ||
        throw(ArgumentError("crossing_time: t and w have different lengths ($(length(t)) \
            and $(length(w)))"))
    i = findfirst(>=(level), w)
    return i === nothing ? nothing : t[firstindex(t) + (i - firstindex(w))]
end

"""
    relaxation_mse(t, w, T, ref_t, ref_w) -> Float64

Return the mean squared error of a curve `w(t)` against a reference `ref_w(ref_t)` whose
time is in units of `T`.

The error is the mean over `j` of `(ŵ(ref_t[j]) − ref_w[j])²`, where `ŵ` is the linear
interpolant of `w` against `t ./ T`.

# Arguments
- `t`: the times of the curve, ascending.
- `w`: the curve, as many values as `t`.
- `T`: the time unit of the reference.
- `ref_t`: the reference times, in units of `T`. Each must lie in `[t[1], t[end]] / T`.
- `ref_w`: the reference values, as many as `ref_t`.

Throws an `ArgumentError` for mismatched lengths, an empty or unsorted `t`, or a reference
time outside the run.

# Returns
- `Float64`: the mean squared error.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> relaxation_mse([0, 100, 200], [5.0, 7.0, 9.0], 100, [0.5, 1.5], [6.0, 8.5])
0.125
```

See also [`crossing_time`](@ref), `spring_dashpot_width`.
"""
function relaxation_mse(t, w, T, ref_t, ref_w)
    s = collect(t) ./ T
    w = collect(w)
    length(s) == length(w) ||
        throw(ArgumentError("relaxation_mse: t and w have different lengths ($(length(s)) \
            and $(length(w)))"))
    length(ref_t) == length(ref_w) ||
        throw(ArgumentError("relaxation_mse: ref_t and ref_w have different lengths"))
    isempty(s) && throw(ArgumentError("relaxation_mse: t is empty"))
    issorted(s) || throw(ArgumentError("relaxation_mse: t must be ascending"))
    acc = 0.0
    for (r, v) in zip(ref_t, ref_w)
        s[1] <= r <= s[end] ||
            throw(ArgumentError("relaxation_mse: reference time $r lies outside the run, \
                [$(s[1]), $(s[end])] T"))
        j = searchsortedlast(s, r)
        ŵ = if j == length(s)
            float(w[j])
        else
            w[j] + (w[j + 1] - w[j]) * (r - s[j]) / (s[j + 1] - s[j])
        end
        acc += (ŵ - v)^2
    end
    return acc / length(ref_t)
end
