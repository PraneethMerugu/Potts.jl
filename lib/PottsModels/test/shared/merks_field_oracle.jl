# The Merks field oracle, shared by merks_split_tests.jl (`Merks2006`, `Merks2008`) and
# merks_vasculogenesis_field_tests.jl (`MerksVasculogenesis`).
#
# Explicit Euler (spec 01 §2.7, §7.4), h = 1/n per substep, 5-point Laplacian with zero flux
# at the lattice faces, then the clip `max(c, lower_bound)` (if any), then c set to 0 on the
# ring after every substep (the order of the field step: write, clip, mask). The ring is the
# sites whose kind code is 2 (the frame of the 2006/2008 models), or the Bool mask `ring`.
# `stencil = :nine` is a negative-control 9-point Laplacian; `clamp = false` drops the ring.
# `kindof` maps an owner to a kind code: 0 medium, 1 endothelial, 2 frame. (TST splits each
# substep into secrete/decay, then diffuse; the models take the unsplit step, a deviation
# row of the reproduction page.)

# The 8 Moore offsets
const MERKS_SPLIT_N8 = [(dx, dy) for dx in -1:1 for dy in -1:1 if (dx, dy) != (0, 0)]

function merks_split_field(
        c0, σ, kindof, p; n = 15, clamp = true, stencil = :five,
        lower_bound = nothing, ring = nothing
    )
    c = copy(c0)
    X, Y = size(c)
    h = 1 / n
    isEC = [kindof(σ[x, y]) == 1 for x in 1:X, y in 1:Y]
    isM = [σ[x, y] == 0 for x in 1:X, y in 1:Y]
    ring = something(ring, [kindof(σ[x, y]) == 2 for x in 1:X, y in 1:Y])
    offs = stencil === :five ? [(1, 0), (-1, 0), (0, 1), (0, -1)] : MERKS_SPLIT_N8
    wts = if stencil === :five
        ones(4)
    else
        [abs(a) + abs(b) == 1 ? 0.5 : 0.25 for (a, b) in MERKS_SPLIT_N8]
    end
    function lap(c, x, y)
        return sum(
            k -> wts[k] * (
                if 1 <= x + offs[k][1] <= X && 1 <= y + offs[k][2] <= Y
                    c[x + offs[k][1], y + offs[k][2]] - c[x, y]
                else
                    0.0
                end
            ), eachindex(offs)
        )
    end
    for _ in 1:n
        c = [
            c[x, y] +
                h * (p.Dc * lap(c, x, y) + p.α * isEC[x, y] - p.ε * c[x, y] * isM[x, y])
                for x in 1:X, y in 1:Y
        ]
        lower_bound === nothing || (c .= max.(c, lower_bound))
        clamp && (c[ring] .= 0.0)
    end
    return c
end
