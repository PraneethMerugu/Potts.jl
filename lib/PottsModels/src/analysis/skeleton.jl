# Skeletons of 2D masks: Zhang–Suen thinning, the skeleton graph (nodes, edges, loops) and
# its counts (tips, junctions, branches, loops).

"""
    skeletonize(mask::AbstractMatrix{Bool}) -> BitMatrix

Return the skeleton of a 2D mask by Zhang–Suen thinning.

The thinning removes boundary sites in two alternating sub-steps until none changes, and
keeps the connectivity of each component (8-connected). Sites outside the array count as
unset. The result is a one-site-wide line along the middle of each component, ending
about half a width short of each end, with a closed line around each hole. Like every
thinning on the square lattice, it has artifacts: a component of 2 × 2 sites vanishes,
and short spurs can grow at corners of thick shapes, so pass `min_length` to
[`skeleton_counts`](@ref) to ignore them.

# Arguments
- `mask::AbstractMatrix{Bool}`: the sites of the shape.

# Returns
- `BitMatrix`: the skeleton sites.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> m = falses(5, 9); m[2:4, 2:8] .= true;

julia> findall(skeletonize(m)) == CartesianIndex.(3, 3:6)
true
```

See also [`skeleton_graph`](@ref), [`skeleton_counts`](@ref).
"""
function skeletonize(mask::AbstractMatrix{Bool})
    s = BitMatrix(mask)
    m, n = size(s)
    at(i, j) = 1 <= i <= m && 1 <= j <= n && s[i, j]
    # P2..P9 clockwise from north (row - 1)
    offs = ((-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1))
    del = CartesianIndex{2}[]
    changed = true
    while changed
        changed = false
        for step in 1:2
            empty!(del)
            for x in CartesianIndices(s)
                s[x] || continue
                i, j = Tuple(x)
                p = ntuple(k -> at(i + offs[k][1], j + offs[k][2]), 8)
                b = count(p)
                2 <= b <= 6 || continue
                count(k -> !p[k] && p[mod1(k + 1, 8)], 1:8) == 1 || continue
                # p[1] = P2 (north), p[3] = P4 (east), p[5] = P6 (south), p[7] = P8 (west)
                if step == 1
                    (p[1] && p[3] && p[5]) || (p[3] && p[5] && p[7]) || push!(del, x)
                else
                    (p[1] && p[3] && p[7]) || (p[1] && p[5] && p[7]) || push!(del, x)
                end
            end
            isempty(del) || (changed = true)
            for x in del
                s[x] = false
            end
        end
    end
    return s
end

# The m-adjacent neighbors of site `x` of the skeleton `s`: the 4 face neighbors, and a
# diagonal neighbor only when neither of the two face neighbors it shares with `x` is set
# (so the line through a corner is not counted twice).
function _m_neighbors(s::AbstractMatrix{Bool}, x::CartesianIndex{2})
    m, n = size(s)
    at(i, j) = 1 <= i <= m && 1 <= j <= n && s[i, j]
    i, j = Tuple(x)
    out = CartesianIndex{2}[]
    for (a, b) in ((-1, 0), (0, 1), (1, 0), (0, -1))
        at(i + a, j + b) && push!(out, CartesianIndex(i + a, j + b))
    end
    for (a, b) in ((-1, -1), (-1, 1), (1, -1), (1, 1))
        at(i + a, j + b) && !at(i + a, j) && !at(i, j + b) &&
            push!(out, CartesianIndex(i + a, j + b))
    end
    return out
end

_step_length(x::CartesianIndex{2}, y::CartesianIndex{2}) = x[1] != y[1] && x[2] != y[2] ?
    sqrt(2.0) : 1.0

"""
    skeleton_graph(skel::AbstractMatrix{Bool}) -> (; nodes, edges, degree, loops)

Return the graph of a one-site-wide 2D skeleton, such as from [`skeletonize`](@ref).

Sites are neighbors under m-adjacency: the 4 face neighbors, and a diagonal neighbor only
when the two face neighbors that it shares with the site are unset. A site with one
neighbor or none is a *tip*, and a site with three or more is a *junction*. Junction sites
that touch form one node, and each tip is a node. An edge is a path of two-neighbor sites
between two nodes, and its length is the sum of its steps (1 face, √2 diagonal) from node
site to node site. A closed line with no node becomes one node with a self-loop.

# Arguments
- `skel::AbstractMatrix{Bool}`: the skeleton sites.

# Returns
A `NamedTuple`:
- `nodes::Vector{Vector{CartesianIndex{2}}}`: the sites of each node.
- `edges::Vector{Tuple{Int, Int, Float64}}`: `(a, b, length)` per edge, `a ≤ b`.
- `degree::Vector{Int}`: the edge ends at each node (a self-loop counts twice).
- `loops::Int`: the independent cycles, `edges − nodes + components`.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> ring = trues(5, 5); ring[2:4, 2:4] .= false;

julia> g = skeleton_graph(ring); (length(g.nodes), length(g.edges), g.loops)
(1, 1, 1)
```

See also [`skeleton_counts`](@ref), [`skeletonize`](@ref).
"""
function skeleton_graph(skel::AbstractMatrix{Bool})
    s = BitMatrix(skel)
    nbr = Dict(x => _m_neighbors(s, x) for x in findall(s))
    deg(x) = length(nbr[x])
    isnode(x) = deg(x) != 2
    # nodes: tips alone, touching junction sites merged
    node = Dict{CartesianIndex{2}, Int}()
    nodes = Vector{CartesianIndex{2}}[]
    for x in sort!(collect(keys(nbr)))
        (isnode(x) && !haskey(node, x)) || continue
        push!(nodes, [x])
        node[x] = length(nodes)
        if deg(x) >= 3
            stack = [x]
            while !isempty(stack)
                y = pop!(stack)
                for z in nbr[y]
                    (deg(z) >= 3 && !haskey(node, z)) || continue
                    node[z] = length(nodes)
                    push!(nodes[end], z)
                    push!(stack, z)
                end
            end
            sort!(nodes[end])
        end
    end
    edges = Tuple{Int, Int, Float64}[]
    visited = Set{CartesianIndex{2}}()
    direct = Set{Tuple{CartesianIndex{2}, CartesianIndex{2}}}()
    for x in sort!(collect(keys(node))), q in nbr[x]
        a = node[x]
        if haskey(node, q)                      # two node sites side by side
            node[q] == a && continue
            key = minmax(x, q)
            key in direct && continue
            push!(direct, key)
            push!(edges, (minmax(a, node[q])..., _step_length(x, q)))
            continue
        end
        q in visited && continue                # traced from the other end
        prev, cur, len = x, q, _step_length(x, q)
        while !haskey(node, cur)
            push!(visited, cur)
            nxt = nbr[cur][1] == prev ? nbr[cur][2] : nbr[cur][1]
            len += _step_length(cur, nxt)
            prev, cur = cur, nxt
        end
        push!(edges, (minmax(a, node[cur])..., len))
    end
    # closed lines with no node: one node with a self-loop each
    for x in sort!(collect(keys(nbr)))
        (deg(x) == 2 && !(x in visited)) || continue
        push!(nodes, [x])
        k = length(nodes)
        prev, cur, len = x, nbr[x][1], _step_length(x, nbr[x][1])
        push!(visited, x)
        while cur != x
            push!(visited, cur)
            nxt = nbr[cur][1] == prev ? nbr[cur][2] : nbr[cur][1]
            len += _step_length(cur, nxt)
            prev, cur = cur, nxt
        end
        push!(edges, (k, k, len))
    end
    degree = zeros(Int, length(nodes))
    adj = [Int[] for _ in nodes]
    for (a, b, _) in edges
        degree[a] += 1
        degree[b] += 1
        push!(adj[a], b)
        push!(adj[b], a)
    end
    ncomp = length(components(adj, eachindex(nodes)))
    return (; nodes, edges, degree, loops = length(edges) - length(nodes) + ncomp)
end

"""
    skeleton_counts(skel::AbstractMatrix{Bool}; min_length = 0)
        -> (; tips, junctions, branches, loops)

Return the tips, junctions, branches and loops of a 2D skeleton.

The counts are read from [`skeleton_graph`](@ref): `tips` are the nodes of degree 1,
`junctions` the nodes of degree 3 or more, and `loops` the independent cycles. A
*branch* is an edge from a tip to a junction, the side shoot of a branched line, and it
counts only when its length is at least `min_length`. Pass `min_length` in sites (for
example a bud length of 10 µm over the site size) to ignore short spurs.

# Arguments
- `skel::AbstractMatrix{Bool}`: the skeleton sites.

# Keywords
- `min_length::Real = 0`: the shortest branch that counts.

# Returns
- `NamedTuple{(:tips, :junctions, :branches, :loops), NTuple{4, Int}}`.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> plus = falses(9, 9); plus[5, 2:8] .= true; plus[2:8, 5] .= true;

julia> skeleton_counts(plus)
(tips = 4, junctions = 1, branches = 4, loops = 0)

julia> skeleton_counts(plus; min_length = 4)
(tips = 4, junctions = 1, branches = 0, loops = 0)
```

See also [`skeletonize`](@ref), [`skeleton_graph`](@ref).
"""
function skeleton_counts(skel::AbstractMatrix{Bool}; min_length::Real = 0)
    g = skeleton_graph(skel)
    tip(k) = g.degree[k] == 1
    junction(k) = g.degree[k] >= 3
    branches = count(g.edges) do (a, b, len)
        len >= min_length && (tip(a) && junction(b) || tip(b) && junction(a))
    end
    return (;
        tips = count(tip, eachindex(g.nodes)),
        junctions = count(junction, eachindex(g.nodes)),
        branches, g.loops,
    )
end
