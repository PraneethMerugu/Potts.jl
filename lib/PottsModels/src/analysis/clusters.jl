# Site clusters and percolation on a predicate, and the cluster graph of a pairwise
# predicate.

"""
    spanning_cluster(mask::AbstractArray{Bool}; axis = 1, adjacency = :face,
        periodic = false) -> BitArray
    spanning_cluster(f, σ::AbstractArray; kwargs...) -> BitArray

Return the sites of the clusters of `mask` that span the array along `axis`.

A cluster is a connected set of set sites: face neighbors under `adjacency = :face`, also
edge and corner neighbors under `:full`. It *spans* when it holds a site in the first and
a site in the last slice along `axis`. The second form uses the mask `f.(σ)`, the sites
where the predicate `f` holds, for example `c -> c in vessel_cells` on an ownership array.
Other axes can be periodic; the spanning axis cannot, since it has no first slice.

# Arguments
- `mask::AbstractArray{Bool}`: the sites.
- `f`: a predicate on the entries of `σ` (second form).

# Keywords
- `axis::Integer = 1`: the spanning axis.
- `adjacency = :face`: `:face` or `:full`.
- `periodic = false`: one `Bool` per axis, or one for all.

Throws an `ArgumentError` for an axis out of range, another `adjacency`, or a periodic
spanning axis.

# Returns
- `BitArray`: the sites of the spanning clusters (all false when none spans).

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> m = Bool[1 0 0; 1 1 0; 0 1 1];

julia> spanning_cluster(m; axis = 2) == m
true

julia> percolates(Bool[1 0 0; 0 1 0; 0 0 1]; axis = 2)
false
```

See also [`percolates`](@ref), [`pair_graph`](@ref).
"""
function spanning_cluster(
        mask::AbstractArray{Bool, N}; axis::Integer = 1, adjacency::Symbol = :face,
        periodic = false
    ) where {N}
    1 <= axis <= N ||
        throw(ArgumentError("spanning_cluster: `axis` must be in 1:$N, got $axis"))
    adjacency in (:face, :full) ||
        throw(ArgumentError("spanning_cluster: `adjacency` must be :face or :full, got \
            $(repr(adjacency))"))
    per = _periodic_axes(periodic, Val(N))
    per[axis] &&
        throw(ArgumentError("spanning_cluster: the spanning axis $axis is periodic, so it \
            has no first or last slice; span along a closed axis"))
    offs = [
        o for o in CartesianIndices(ntuple(_ -> -1:1, Val(N)))
            if o != zero(o) && (adjacency === :full || sum(abs, Tuple(o)) == 1)
    ]
    dims = size(mask)
    label = zeros(Int, dims)
    out = falses(dims)
    stack = CartesianIndex{N}[]
    members = CartesianIndex{N}[]
    k = 0
    for x in CartesianIndices(mask)
        (mask[x] && label[x] == 0) || continue
        k += 1
        label[x] = k
        push!(stack, x)
        empty!(members)
        lo = hi = false
        while !isempty(stack)
            y = pop!(stack)
            push!(members, y)
            lo |= y[axis] == 1
            hi |= y[axis] == dims[axis]
            for o in offs
                z = Tuple(y + o)
                all(d -> per[d] || 1 <= z[d] <= dims[d], 1:N) || continue
                w = CartesianIndex(ntuple(d -> per[d] ? mod1(z[d], dims[d]) : z[d], Val(N)))
                (mask[w] && label[w] == 0) || continue
                label[w] = k
                push!(stack, w)
            end
        end
        lo && hi && (out[members] .= true)
    end
    return out
end
function spanning_cluster(f::F, σ::AbstractArray; kwargs...) where {F}
    return spanning_cluster(map(x -> f(x)::Bool, σ); kwargs...)
end

"""
    percolates(mask::AbstractArray{Bool}; kwargs...) -> Bool
    percolates(f, σ::AbstractArray; kwargs...) -> Bool

Return whether a cluster of `mask` (or of the sites where `f` holds) spans the array along
`axis`, with the keywords of [`spanning_cluster`](@ref).

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> percolates(iseven, [2 4 1; 1 6 8]; axis = 2)
true
```

See also [`spanning_cluster`](@ref).
"""
percolates(mask::AbstractArray{Bool}; kwargs...) = any(spanning_cluster(mask; kwargs...))
function percolates(f::F, σ::AbstractArray; kwargs...) where {F}
    return any(spanning_cluster(f, σ; kwargs...))
end

"""
    pair_graph(pred, n::Integer) -> Vector{Vector{Int}}

Return the graph on the items `1:n` with an edge between `i` and `j` wherever
`pred(i, j)` holds, as adjacency lists.

`pred` is called once per pair `i < j` and must be symmetric. Pass the result to
[`components`](@ref) for the clusters under the transitive closure of `pred`, for
example cells whose centroids are close and whose directions align.

# Arguments
- `pred`: a symmetric predicate on two item numbers.
- `n::Integer`: the number of items (non-negative).

# Returns
- `Vector{Vector{Int}}`: the sorted neighbors of each item.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> x = [0.0, 1.0, 5.0, 5.5];

julia> components(pair_graph((i, j) -> abs(x[i] - x[j]) < 2, 4), 1:4)
2-element Vector{Vector{Int64}}:
 [1, 2]
 [3, 4]
```

See also [`components`](@ref), [`cell_graph`](@ref).
"""
function pair_graph(pred::F, n::Integer) where {F}
    n >= 0 || throw(ArgumentError("pair_graph: `n` must be non-negative, got $n"))
    g = [Int[] for _ in 1:n]
    for i in 1:n, j in (i + 1):n
        if pred(i, j)::Bool
            push!(g[i], j)
            push!(g[j], i)
        end
    end
    return g
end
