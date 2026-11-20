# `split_ids(σ, periodic)` and `split_cells(σ, periodic)`: the cells of an ownership matrix whose
# sites are not one 8-connected piece, by flood fill.
"""Cells whose sites are not one 8-connected piece (axes periodic as given)."""
function split_ids(σ, periodic)
    X, Y = size(σ); out = eltype(σ)[]
    for c in unique(σ)
        c == 0 && continue
        idx = findall(==(c), σ); seen = Set([idx[1]]); st = [idx[1]]
        while !isempty(st)
            q = pop!(st)
            for dx in -1:1, dy in -1:1
                x, y = q[1] + dx, q[2] + dy
                periodic[1] ? (x = mod1(x, X)) : (1 <= x <= X || continue)
                periodic[2] ? (y = mod1(y, Y)) : (1 <= y <= Y || continue)
                p = CartesianIndex(x, y)
                (σ[p] == c && !(p in seen)) && (push!(seen, p); push!(st, p))
            end
        end
        length(seen) < length(idx) && push!(out, c)
    end
    return out
end
split_cells(σ, periodic) = length(split_ids(σ, periodic))
