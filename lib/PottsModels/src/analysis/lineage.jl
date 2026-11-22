# Lineage trees from birth records.

"""
    lineage(records) -> (; parent, children, roots, founder, depth)

Return the lineage forest of the birth records `records`, pairs `child => parent`.

A pair `c => nothing` declares a founder with no parent. Every label in a record is a
node, and a node with no parent is a root. Labels must be unique per cell over the whole
run: a cell number that a later division reuses needs a new label, such as `(mcs, id)`.

# Arguments
- `records`: an iterable of `child => parent` pairs (`parent` may be `nothing`).

Throws an `ArgumentError` when a record names a cell as its own parent, a child has two
different parents, or the records hold a cycle.

# Recording births in a model
The built-in `birth` of a cell is a serial that no other cell of the run shares; the
initial cells take 1, 2, … and each daughter the next free serial. A division rule copies
the parent's serial into a cell variable:

```julia
@variables mother(cell) = 0.0
@divide cells(cell) when = …, mother => birth
```

A division rule sets its value in both daughters, and the parent keeps its cell number
and its `birth`. After a division the parent therefore holds the self record
`birth => birth`, and its true record is the one saved before. Read the records from
saved states, and drop the self records:

```julia
recs = Pair{Int, Union{Int, Nothing}}[]
for k in eachindex(sol.u), c in findall(sol[:volume][k] .> 0)
    b, m = Int(sol[:birth][k][c]), Int(sol[:mother][k][c])
    b == m || push!(recs, b => (m == 0 ? nothing : m))
end
lin = lineage(unique!(recs))
```

Each cell must be saved at least once between its birth and its first division, so save
at least at every MCS where the rule can fire (the default `save_everystep = true` does
it). Pass the `birth` of the living cells to [`clone_sizes`](@ref).

For clone sizes alone, `lineage` is not needed: a cell variable that holds the founder's
label is copied to every daughter (state without a division rule is copied). `lineage`
adds the depth of each cell and the tree.

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
    label(p) = p.second === nothing ? typeof(p.first) :
        promote_type(typeof(p.first), typeof(p.second))
    T0 = mapreduce(label, promote_type, ps; init = Union{})
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
        c == a && throw(ArgumentError("lineage: a cell cannot be its own parent \
            ($(repr(c)) => $(repr(c))); drop the records with child == parent"))
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
