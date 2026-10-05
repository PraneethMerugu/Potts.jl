# Chains of cells along a periodic axis and relaxation curves: centroids unwrapped along a
# chain, the chain's width, the first crossing of a level and the mean squared error
# against a reference curve on a rescaled time axis.

"""
    chain_centroids(σ) -> Vector{Float64}

The axis-1 centroid of every cell `1:maximum(σ)` on a lattice periodic along axis 1,
unwrapped along the chain the cells form. The centroids are
[`centroids`](@ref)`(σ; periodic = (true, …))`; the circle of length `L = size(σ, 1)` is
cut at the largest gap between cyclically consecutive centroids, and `L` is added to every
centroid before the cut. The chain then reads left to right with no jump at the seam, and
its leftmost cell lies in `[1, L + 1)`.

The result is the chain's geometry only while the chain is shorter than `L` minus its
largest internal gap, so that the medium gap between its ends is the largest. An
`ArgumentError` if some id owns no site.

```julia
σ = zeros(Int, 30, 5)
σ[[28, 29, 30, 1, 2], :] .= 1; σ[3:7, :] .= 2
chain_centroids(σ)                 # [30.0, 35.0]: cell 2 sits past the seam
```
"""
function chain_centroids(σ::AbstractArray{<:Integer})
    L = size(σ, 1)
    x = [c[1] for c in centroids(σ; periodic = true)]
    any(isnan, x) && throw(ArgumentError("chain_centroids: id $(findfirst(isnan, x)) owns no site"))
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

The extent of a chain of cells along axis 1, `(max − min)` of
[`chain_centroids`](@ref)`(σ)[cells]`, in units of `CD` lattice sites (a cell diameter).
`cells` picks a sub-chain, for example the inner cells of a longer chain.
"""
function chain_width(σ::AbstractArray{<:Integer}, cells = 1:Int(maximum(σ; init = 0)); CD = 10)
    xs = chain_centroids(σ)[cells]
    isempty(xs) && throw(ArgumentError("chain_width: no cells (σ owns no site, or `cells` is empty)"))
    return (maximum(xs) - minimum(xs)) / CD
end

"""
    crossing_time(t, w, level = 9.0)

`t[i]` for the first `i` with `w[i] ≥ level`, or `nothing` if `w` never reaches `level`.
Later dips below `level` do not matter.
"""
function crossing_time(t, w, level = 9.0)
    length(t) == length(w) ||
        throw(ArgumentError("crossing_time: t and w have different lengths ($(length(t)) and $(length(w)))"))
    i = findfirst(>=(level), w)
    return i === nothing ? nothing : t[firstindex(t) + (i - firstindex(w))]
end

"""
    relaxation_mse(t, w, T, ref_t, ref_w) -> Float64

The mean squared error of a curve `w(t)` against a reference `ref_w(ref_t)` whose time is
in units of `T`: the mean over `j` of `(ŵ(ref_t[j]) − ref_w[j])²`, where `ŵ` is the linear
interpolant of `w` against `t ./ T`. `t` must be ascending, and every `ref_t[j]` must lie
in `[t[1], t[end]] / T` (an `ArgumentError` otherwise).
"""
function relaxation_mse(t, w, T, ref_t, ref_w)
    s = collect(t) ./ T
    w = collect(w)
    length(s) == length(w) ||
        throw(ArgumentError("relaxation_mse: t and w have different lengths ($(length(s)) and $(length(w)))"))
    length(ref_t) == length(ref_w) ||
        throw(ArgumentError("relaxation_mse: ref_t and ref_w have different lengths"))
    isempty(s) && throw(ArgumentError("relaxation_mse: t is empty"))
    issorted(s) || throw(ArgumentError("relaxation_mse: t must be ascending"))
    acc = 0.0
    for (r, v) in zip(ref_t, ref_w)
        s[1] <= r <= s[end] ||
            throw(ArgumentError("relaxation_mse: reference time $r lies outside the run, [$(s[1]), $(s[end])] T"))
        j = searchsortedlast(s, r)
        ŵ = j == length(s) ? float(w[j]) : w[j] + (w[j + 1] - w[j]) * (r - s[j]) / (s[j + 1] - s[j])
        acc += (ŵ - v)^2
    end
    return acc / length(ref_t)
end
