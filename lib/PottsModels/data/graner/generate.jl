# Regenerates the Graner–Glazier initial condition (D-049 F-2) following Glazier & Graner,
# Phys. Rev. E 47, 2128 (1993), §II D3: rectangular cells of area 40 are relaxed as one
# type (J_ll = 2, J_lM = 8, T = 5, λ = 1) for 400 paper MCS (6400 here: a paper MCS is 16N
# copy attempts), then given random types, 32 dark and 32 light.
#
#     julia --project=lib/PottsModels/test lib/PottsModels/data/graner/generate.jl [outdir]
using Potts, PottsModels
using DelimitedFiles: writedlm
using Random: MersenneTwister, shuffle

const DIMS = (72, 72)
const NCELLS = 64
const SEED = 20260929

# 8×5 bricks on a grid; the 64 nearest the centre form a round aggregate
function brick_aggregate()
    σ = zeros(Int32, DIMS)
    c = (DIMS .+ 1) ./ 2
    slots = [(i, j) for i in 0:8:(DIMS[1] - 8), j in 0:5:(DIMS[2] - 5)]
    d(s) = hypot(s[1] + 4.5 - c[1], s[2] + 3 - c[2])
    for (k, (i, j)) in enumerate(sort(vec(slots); by = d)[1:NCELLS])
        σ[(i + 1):(i + 8), (j + 1):(j + 5)] .= k
    end
    return σ
end

function generate(outdir)
    σ0 = brick_aggregate()
    relax = PottsProblem(GranerGlazier(; name = :relax), [ownership => σ0, kind => fill(:light, NCELLS),
            :J => [0 8 8; 8 2 2; 8 2 2], :T => 5.0, :λ => 1.0, :V₀ => 40.0], (0, 6400); seed = SEED)
    σ = solve(relax, SequentialCPM(); saveat = 6400).u[end].σ
    all(c -> any(==(c), σ), 1:NCELLS) || error("a cell vanished during relaxation")
    kinds = shuffle(MersenneTwister(SEED + 1), [fill(1, NCELLS ÷ 2); fill(2, NCELLS ÷ 2)])
    writedlm(joinpath(outdir, "pre_equilibrated_ownership.tsv"), σ, '\t')
    writedlm(joinpath(outdir, "cell_kinds.tsv"), kinds, '\t')
    return σ, kinds
end

generate(isempty(ARGS) ? (@__DIR__) : ARGS[1])
