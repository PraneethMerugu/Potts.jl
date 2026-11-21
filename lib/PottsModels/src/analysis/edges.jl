# Whether a state comes near the lattice edge (a domain guard for "unbounded" colonies).

"""
    near_edge(σ, margin) -> Bool

Return whether some site of a cell (`σ ≠ 0`) lies within `margin` sites of the lattice
edge: its index `i_d ≤ margin` or `i_d ≥ size(σ, d) − margin + 1` on some axis `d`.

A `margin ≤ 0` is never near. It works on GPU arrays too, with one reduction per face.

# Arguments
- `σ::AbstractArray`: the ownership, of any dimension.
- `margin::Integer`: the distance from the edge, in sites.

# Returns
- `Bool`: whether a cell is near the edge.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> σ = zeros(Int, 10, 10); σ[3, 5] = 1;

julia> near_edge(σ, 2), near_edge(σ, 3)
(false, true)
```

See also `PottsModels.edge_guard`.
"""
function near_edge(σ::AbstractArray, margin::Integer)
    margin <= 0 && return false
    for d in 1:ndims(σ)
        n = size(σ, d)
        k = min(Int(margin), n)
        any(!=(0), selectdim(σ, d, 1:k)) && return true
        any(!=(0), selectdim(σ, d, (n - k + 1):n)) && return true
    end
    return false
end
