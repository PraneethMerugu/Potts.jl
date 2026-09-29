# Observables shared by the legacy sampler (reference/) and the parity tests: plain Julia.

"""Moore-bond statistics of a 2D periodic labelling: each unordered bond counted once."""
function observables(σ, kinds)
    nx, ny = size(σ)
    hetero = homo = edge = 0
    for y in 1:ny, x in 1:nx, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
        a = σ[x, y]; b = σ[mod1(x + dx, nx), mod1(y + dy, ny)]
        a == b && continue
        if a == 0 || b == 0
            edge += 1
        elseif kinds[a] != kinds[b]
            hetero += 1
        else
            homo += 1
        end
    end
    alive = length(unique(filter(!=(0), vec(σ))))
    return (; hetero_fraction = hetero / (hetero + homo), edge_bonds = edge,
        cell_bonds = hetero + homo, alive)
end
