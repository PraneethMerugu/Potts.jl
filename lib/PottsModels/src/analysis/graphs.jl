# Cell adjacency of a state: the contact graph as adjacency lists, breadth-first
# reachability, connected components of induced subgraphs, and cell centroids.

"""
    cell_graph(σ; periodic = (false, …),
        neighborhood = VonNeumann(1)) -> Vector{Vector{Int}}
    cell_graph(σ, lattice::Lattice; neighborhood = VonNeumann(1)) -> Vector{Vector{Int}}

Return the contact graph of the cells of σ as adjacency lists.

`g[c]` holds, sorted, the distinct cells that own a site neighboring (under
`neighborhood`) a site of cell `c`, for `c` in `1:maximum(σ)`. The medium (0) is not a
cell. It is built on CorePotts' [`contact_graph`](@ref).

# Arguments
- `σ::AbstractArray`: the ownership.
- `lattice::Lattice`: a CorePotts lattice of the size of `σ`, for a hexagonal lattice or a
  masked domain. Throws an `ArgumentError` for another size.

# Keywords
- `periodic = (false, …)`: one flag per axis of a square lattice. Throws an
  `ArgumentError` for another count.
- `neighborhood = VonNeumann(1)`: the neighbors that count as contacts.

# Returns
- `Vector{Vector{Int}}`: the adjacency lists.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> cell_graph([1 1 0; 2 0 3])
3-element Vector{Vector{Int64}}:
 [2]
 [1]
 []
```

See also [`reachable`](@ref), [`components`](@ref).
"""
function cell_graph(
        σ::AbstractArray; periodic = ntuple(_ -> false, ndims(σ)),
        neighborhood = VonNeumann(1)
    )
    length(periodic) == ndims(σ) ||
        throw(ArgumentError("cell_graph: σ is $(ndims(σ))D, got $(length(periodic)) \
            periodic flags"))
    lat = Lattice(size(σ); boundary = map(p -> p ? Periodic() : Closed(), Tuple(periodic)))
    return cell_graph(σ, lat; neighborhood)
end
function cell_graph(σ::AbstractArray, lat::Lattice; neighborhood = VonNeumann(1))
    size(σ) == lat.dims ||
        throw(ArgumentError("cell_graph: σ has size $(size(σ)), the lattice $(lat.dims)"))
    n = Int(maximum(σ; init = 0))
    cg = contact_graph(σ, lat, relation(neighborhood, lat), n)
    return [Vector{Int}(contact_neighbors(cg, c)) for c in 1:n]
end

"""
    reachable(g, seeds) -> Vector{Int}

Return the cells reachable in the adjacency lists `g` from any of `seeds`, the seeds
included, sorted.

The search is breadth-first.

# Arguments
- `g`: adjacency lists, as from [`cell_graph`](@ref).
- `seeds`: the starting cells.

# Returns
- `Vector{Int}`: the reachable cells.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> reachable([[2], [1], Int[]], [2])
2-element Vector{Int64}:
 1
 2
```

See also [`components`](@ref), [`cell_graph`](@ref).
"""
function reachable(g, seeds)
    seen = falses(length(g))
    queue = Int[]
    for s in seeds
        seen[s] || (seen[s] = true; push!(queue, s))
    end
    head = 1
    while head <= length(queue)
        c = queue[head]
        head += 1
        for d in g[c]
            seen[d] || (seen[d] = true; push!(queue, d))
        end
    end
    return findall(seen)
end

"""
    components(g, cells) -> Vector{Vector{Int}}

Return the connected components of the subgraph of `g` induced by `cells`.

Edges to cells outside `cells` are ignored. Each component is sorted, and the components
are ordered by their smallest member.

# Arguments
- `g`: adjacency lists, as from [`cell_graph`](@ref).
- `cells`: the cells of the subgraph.

# Returns
- `Vector{Vector{Int}}`: the components.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> components([[2], [1, 3], [2]], [1, 3])
2-element Vector{Vector{Int64}}:
 [1]
 [3]
```

See also [`reachable`](@ref), [`cell_graph`](@ref).
"""
function components(g, cells)
    inside = falses(length(g))
    for c in cells
        inside[c] = true
    end
    label = zeros(Int, length(g))
    out = Vector{Int}[]
    stack = Int[]
    for c in eachindex(inside)
        (inside[c] && label[c] == 0) || continue
        push!(out, Int[])
        k = length(out)
        label[c] = k
        push!(stack, c)
        while !isempty(stack)
            u = pop!(stack)
            push!(out[k], u)
            for d in g[u]
                (inside[d] && label[d] == 0) || continue
                label[d] = k
                push!(stack, d)
            end
        end
        sort!(out[k])
    end
    return out
end

"""
    centroids(σ; periodic = (false, …)) -> Vector{NTuple{N, Float64}}

Return the mean site coordinate (lattice indices) of each cell `1:maximum(σ)`.

A cell number that owns no site gets `NaN`s, so it cannot pass as a real position.

On a periodic axis `d`, a cell's sites are taken at their minimum image relative to the
cell's first site in column-major order, and the mean is wrapped into
`[1, size(σ, d) + 1)`, the convention of CorePotts' `centroid`: a cell owning columns 10
and 1 of a 10-wide periodic lattice has its centroid at 10.5. Non-periodic axes (the
default) take the plain mean of the indices, with no unwrapping. The minimum image is exact
for a cell at most half the lattice wide along `d`. A wider cell gets a result that depends
on where its first site (column-major) falls: on a 10-wide axis, a cell owning 5:10 reads
5.83, not 7.5.

# Arguments
- `σ::AbstractArray{<:Integer, N}`: the ownership.

# Keywords
- `periodic = (false, …)`: one `Bool` per axis, as in [`cell_graph`](@ref); a single
  `Bool` applies to every axis. Throws an `ArgumentError` for another count.

# Returns
- `Vector{NTuple{N, Float64}}`: the centroid of each cell.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> σ = zeros(Int, 10, 1); σ[[10, 1]] .= 1;

julia> centroids(σ; periodic = true), centroids(σ)
([(10.5, 1.0)], [(5.5, 1.0)])
```

See also [`cell_graph`](@ref), [`chain_centroids`](@ref).
"""
function centroids(
        σ::AbstractArray{<:Integer, N};
        periodic = ntuple(_ -> false, N)
    ) where {N}
    per = _periodic_axes(periodic, Val(N))
    dims = size(σ)
    n = Int(maximum(σ; init = 0))
    sums = fill(ntuple(_ -> 0.0, N), n)
    counts = zeros(Int, n)
    anchor = fill(ntuple(_ -> 0, N), n)
    for i in CartesianIndices(σ)
        c = σ[i]
        c > 0 || continue
        counts[c] == 0 && (anchor[c] = Tuple(i))
        a = anchor[c]
        x = ntuple(d -> per[d] ? a[d] + _min_image(i[d] - a[d], dims[d]) : i[d], N)
        sums[c] = sums[c] .+ x
        counts[c] += 1
    end
    return [ntuple(d -> _wrap(sums[c][d] / counts[c], dims[d], per[d]), N) for c in 1:n]
end

_periodic_axes(p::Bool, ::Val{N}) where {N} = ntuple(_ -> p, N)
function _periodic_axes(p, ::Val{N}) where {N}
    length(p) == N ||
        throw(ArgumentError("centroids: `periodic` needs one entry per axis ($N), \
            got $(repr(p))"))
    return ntuple(d -> Bool(p[d]), N)
end
# the offset δ taken modulo L into [-L ÷ 2, L - L ÷ 2)
_min_image(δ, L) = mod(δ + L ÷ 2, L) - L ÷ 2
_wrap(m, L, periodic) = periodic ? mod(m - 1, L) + 1 : m
