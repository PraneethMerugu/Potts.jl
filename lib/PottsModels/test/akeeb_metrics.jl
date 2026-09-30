# Akeeb leader/follower invasion metrics for the model's mechanism tests. Base only.
#
# `akeeb_metrics(σ, isleader, n0)`:
#   σ         labels, x × y (0 = medium); x periodic, y closed
#   isleader  isleader[c] is true iff cell c is a leader (daughter ids default to follower
#             when c > length(isleader))
#   n0        initial number of cells
# Returns a NamedTuple:
#   divisions      live cells − n0 (both implementations forbid extinction)
#   outer_front    max y over non-medium sites
#   leader_front   max y over leader sites
#   leader_mean_y  mean y over leader sites
#   components     connected components of non-medium sites (von Neumann, x periodic)
function akeeb_metrics(σ::AbstractMatrix{<:Integer}, isleader::AbstractVector{Bool}, n0::Integer)
    X, Y = size(σ)
    leader(c) = c <= length(isleader) && isleader[c]
    live = Set{Int}()
    outer = 0; lfront = 0; lsum = 0; ln = 0
    for y in 1:Y, x in 1:X
        c = Int(σ[x, y]); c == 0 && continue
        push!(live, c)
        outer = max(outer, y)
        if leader(c)
            lfront = max(lfront, y); lsum += y; ln += 1
        end
    end
    seen = falses(X, Y)
    comps = 0
    stack = Tuple{Int, Int}[]
    for y in 1:Y, x in 1:X
        (σ[x, y] == 0 || seen[x, y]) && continue
        comps += 1
        seen[x, y] = true
        push!(stack, (x, y))
        while !isempty(stack)
            (i, j) = pop!(stack)
            for (ii, jj) in ((mod1(i + 1, X), j), (mod1(i - 1, X), j), (i, j + 1), (i, j - 1))
                1 <= jj <= Y || continue
                (σ[ii, jj] == 0 || seen[ii, jj]) && continue
                seen[ii, jj] = true
                push!(stack, (ii, jj))
            end
        end
    end
    return (divisions = length(live) - n0, outer_front = outer, leader_front = lfront,
        leader_mean_y = ln == 0 ? 0.0 : lsum / ln, components = comps)
end
