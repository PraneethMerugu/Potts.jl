# Lineage trees from birth records.

"""
    lineage(records) -> (; parent, children, roots, founder, depth)

Return the lineage forest of the birth records `records`, pairs `child => parent`.

A pair `c => nothing` declares a founder with no parent. Every label in a record is a
node, and a node with no parent is a root. Labels must be unique per cell over the whole
run: a cell number that a later division reuses needs a new label, such as `(mcs, id)`.

# Arguments
- `records`: an iterable of `child => parent` pairs (`parent` may be `nothing`).

Throws an `ArgumentError` when a child has two different parents or the records hold a
cycle.

# Returns
A `NamedTuple`, with `T` the label type:
- `parent::Dict{T, T}`: the parent of each non-root node.
- `children::Dict{T, Vector{T}}`: the children of each node, in record order.
- `roots::Vector{T}`: the roots, sorted.
- `founder::Dict{T, T}`: the root of each node's tree (a root is its own founder).
- `depth::Dict{T, Int}`: the generations from the founder (0 for a root).

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> lin = lineage([1 => nothing, 3 => 1, 4 => 1, 5 => 3, 6 => 2]);

julia> lin.roots, lin.founder[5], lin.depth[5], lin.children[1]
([1, 2], 1, 2, [3, 4])
```

See also [`clone_sizes`](@ref).
"""
function lineage(records)
    ps = collect(records)
    T0 = mapreduce(
        p -> p.second === nothing ? typeof(p.first) : promote_type(typeof.((p.first, p.second))...),
        promote_type, ps; init = Union{}
    )
    T = T0 === Union{} ? Int : T0
    parent = Dict{T, T}()
    children = Dict{T, Vector{T}}()
    nodes = T[]
    seen = Set{T}()
    add(x) = (x in seen || (push!(seen, x); push!(nodes, x); children[x] = T[]); x)
    for p in ps
        c = add(T(p.first))
        p.second === nothing && continue
        a = add(T(p.second))
        if haskey(parent, c)
            parent[c] == a && continue
            throw(ArgumentError("lineage: $(repr(c)) has two parents, $(repr(parent[c])) \
                and $(repr(a))"))
        end
        parent[c] = a
        push!(children[a], c)
    end
    founder = Dict{T, T}()
    depth = Dict{T, Int}()
    path = T[]
    for x in nodes
        haskey(founder, x) && continue
        empty!(path)
        y = x
        while !haskey(founder, y) && haskey(parent, y)
            push!(path, y)
            length(path) > length(nodes) &&
                throw(ArgumentError("lineage: the records hold a cycle through $(repr(x))"))
            y = parent[y]
        end
        if !haskey(founder, y)                   # a root
            founder[y] = y
            depth[y] = 0
        end
        for z in Iterators.reverse(path)
            founder[z] = founder[parent[z]]
            depth[z] = depth[parent[z]] + 1
        end
    end
    roots = sort!([x for x in nodes if !haskey(parent, x)])
    return (; parent, children, roots, founder, depth)
end

"""
    clone_sizes(lin, cells) -> Dict

Return the number of `cells` descended from each founder of the lineage `lin`.

Each founder of `lin.roots` gets an entry, 0 when none of `cells` descends from it. A
founder counts itself when it is in `cells`. Pass the labels of the living cells for the
clone sizes at the end of a run.

# Arguments
- `lin`: a lineage from [`lineage`](@ref).
- `cells`: node labels of `lin`. Throws an `ArgumentError` for a label not in `lin`.

# Returns
- `Dict`: founder => count.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> lin = lineage([3 => 1, 4 => 1, 5 => 2]);

julia> sort(collect(clone_sizes(lin, [3, 4, 5])))
2-element Vector{Pair{Int64, Int64}}:
 1 => 2
 2 => 1
```

See also [`lineage`](@ref).
"""
function clone_sizes(lin, cells)
    out = Dict(r => 0 for r in lin.roots)
    for c in cells
        haskey(lin.founder, c) ||
            throw(ArgumentError("clone_sizes: $(repr(c)) is not in the lineage"))
        out[lin.founder[c]] += 1
    end
    return out
end
