# Regenerates the Graner–Glazier initial condition (D-049 F-2) following Glazier & Graner,
# Phys. Rev. E 47, 2128 (1993), §II D3 and Figs. 4–5:
#
# 1. a square aggregate of staggered rectangular cells of equal height and various widths
#    (mean area 40), so the relaxation must break the parallel walls and round the square;
# 2. relaxed as one type (J_ll = 2, J_lM = 8, T = 5, λ = 1) for 400 paper MCS (6400 here:
#    a paper MCS is 16N copy attempts), checking that total boundary length and the
#    cell–medium fraction are flat over the last 100 paper MCS (Fig. 5);
# 3. each cell dark or light with probability ½ (separately seeded).
#
#     julia --project=lib/PottsModels/test lib/PottsModels/data/graner/generate.jl [outdir]
using Potts, PottsModels
using DelimitedFiles: writedlm
using Random: MersenneTwister, shuffle!

const DIMS = (72, 72)
const SEED = 20260929
const HEIGHT = 5                       # rows of cells, all 5 sites tall
const ROWS = 10                        # 10 rows × 5 = 50 tall
const WIDTH = 51                       # 51 wide: a 51 × 50 square block
const PER_ROW = (6, 7, 6, 7, 6, 7, 6, 7, 6, 6)    # 64 cells, alternating: staggered walls

"""Random positive integer widths in `lo:hi` summing to `total`."""
function widths(rng, n, total; lo = 5, hi = 12)
    for _ in 1:100_000
        w = rand(rng, lo:hi, n - 1)
        last = total - sum(w)
        lo <= last <= hi && return shuffle!(rng, [w; last])
    end
    error("no widths")
end

function brick_aggregate(rng)
    σ = zeros(Int32, DIMS)
    x0 = (DIMS[1] - WIDTH) ÷ 2
    y0 = (DIMS[2] - ROWS * HEIGHT) ÷ 2
    c = 0
    for (r, n) in enumerate(shuffle!(rng, collect(PER_ROW)))
        x = x0
        for w in widths(rng, n, WIDTH)
            c += 1
            σ[(x + 1):(x + w), (y0 + (r - 1) * HEIGHT + 1):(y0 + r * HEIGHT)] .= c
            x += w
        end
    end
    return σ
end

# mismatched Moore bonds (each pair once) and the cell–medium share of them
function boundary(σ)
    n = m = 0
    X, Y = size(σ)
    for y in 1:Y, x in 1:X, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
        a = σ[x, y]; b = σ[mod1(x + dx, X), mod1(y + dy, Y)]
        a == b && continue
        n += 1
        (a == 0 || b == 0) && (m += 1)
    end
    return n, m / n
end

function generate(outdir)
    rng = MersenneTwister(SEED)
    σ0 = brick_aggregate(rng)
    n = maximum(σ0)
    relax = PottsProblem(GranerGlazier(; name = :relax), [ownership => σ0, kind => fill(:light, n),
            :J => [0 8 8; 8 2 2; 8 2 2], :T => 5.0, :λ => 1.0, :V₀ => 40.0], (0, 6400); seed = SEED)
    sol = solve(relax, SequentialCPM(); saveat = 0:100:6400)
    σ = sol.u[end].σ
    all(c -> any(==(c), σ), 1:n) || error("a cell vanished during relaxation")
    # equilibrated (Fig. 5): over the last 100 paper MCS neither the total boundary nor the
    # cell–medium fraction drifts by more than 2%
    late = [boundary(u.σ) for u in sol.u[(end - 16):end]]
    for f in (first, last)
        v = f.(late)
        drift = abs(sum(v[(end - 3):end]) - sum(v[1:4])) / 4
        drift <= 0.02 * sum(v) / length(v) || error("not equilibrated: $(f === first ? "total boundary" : "medium fraction") drifts by $drift")
    end
    @info "relaxed" cells = n boundary_start = boundary(σ0) boundary_end = boundary(σ)
    trng = MersenneTwister(SEED + 1)
    kinds = [rand(trng, Bool) ? 1 : 2 for _ in 1:n]
    writedlm(joinpath(outdir, "pre_equilibrated_ownership.tsv"), σ, '\t')
    writedlm(joinpath(outdir, "cell_kinds.tsv"), kinds, '\t')
    return σ, kinds
end

generate(isempty(ARGS) ? (@__DIR__) : ARGS[1])
