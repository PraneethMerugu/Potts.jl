# P6.1h (spec 09 §8.5/§9.1 V-PRE7; D-151 outcome): one replicate of the reproduction-09 FULL
# fixture at temperature T, for the sorting temperature regimes of PRE Fig. 15.
#
# Fixture: the page's FULL replicate, `graner_glazier_aggregate(1000; seed = start_seed,
# margin = 60)` with the published `GranerGlazier` and only T changed,
# `SequentialCPM(; proposal = Moore(1))`, problem seed `run_seed`, 1 paper MCS = 16 MCS, saves
# on the page's FULL grid up to 10⁴ paper MCS.
# Measurement: the page's. At each save, a copy annealed 2 paper MCS at T = 0 with the run's
# J, λ and V₀ (seed 1), Moore bonds once, all mismatched bonds as denominator; the raw state
# gives the alive-cell counts (cells with volume > 0) and the isolation guard.
#
# usage: julia -t 1 --project=docs replicate.jl <outfile> <start_seed> <run_seed> <T> [t_end]
#   (t_end, default 10⁴, truncates the save grid; used only for the pre-launch probe)
using Potts, PottsModels

const PAPER_MCS = 16
const MARGIN = 60
const NCELLS = 1000
const TS_ALL = [1, 2, 3, 4, 5, 6, 8, 10, 13, 16, 20, 25, 32, 40, 50, 64, 80, 100, 128, 160, 200, 256, 320,
    400, 500, 640, 800, 1000, 1280, 1600, 2000, 2560, 3200, 4000, 5000, 6400, 8000, 10_000]

out = ARGS[1]
start_seed, run_seed = parse.(Int, ARGS[2:3])
T = parse(Float64, ARGS[4])
const TS = filter(<=(length(ARGS) >= 5 ? parse(Int, ARGS[5]) : 10_000), TS_ALL)

# --- page helpers (verbatim from lib/PottsModels/reproductions/09_cell_sorting.jl) ---
function cell_areas(σ, k)
    a = zeros(Int, length(k))
    for c in σ
        c > 0 && (a[c] += 1)
    end
    return a
end
function bond_counts(σ, k)
    n = Dict(:dd => 0, :ll => 0, :dl => 0, :dM => 0, :lM => 0)
    nx, ny = size(σ)
    for y in 1:ny, x in 1:nx, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
        a = σ[x, y]
        b = σ[mod1(x + dx, nx), mod1(y + dy, ny)]
        a == b && continue
        a == 0 && ((a, b) = (b, a))
        key = b == 0 ? (k[a] == 1 ? :dM : :lM) : k[a] == k[b] ? (k[a] == 1 ? :dd : :ll) : :dl
        n[key] += 1
    end
    return n
end
function annealed(σ, k, run; seed = 1)
    q = PottsProblem(GranerGlazier(; name = :anneal, lattice = size(σ)),
        [ownership => copy(σ), kind => k, :J => getp(run, :J)(run), :λ => getp(run, :λ)(run),
            :V₀ => getp(run, :V₀)(run), :T => 0.0], (0, 2PAPER_MCS); seed)
    return ownership(solve(q, SequentialCPM(); saveat = 2PAPER_MCS).u[end])
end
isolated(σ) = any(x -> all(==(0), view(σ, x, :)), axes(σ, 1)) && any(y -> all(==(0), view(σ, :, y)), axes(σ, 2))
# ---

alg = SequentialCPM(; proposal = Moore(1))
σ0, k0 = graner_glazier_aggregate(NCELLS; seed = start_seed, margin = MARGIN)
prob = PottsProblem(GranerGlazier(; name = :gg, lattice = size(σ0)),
    [ownership => σ0, kind => k0, :T => T], (0, PAPER_MCS * last(TS)); seed = run_seed)
solve(remake(prob; tspan = (0, 1)), alg)                # compile
wall = @elapsed sol = solve(prob, alg; saveat = PAPER_MCS .* TS)
open(out * ".part", "w") do io
    println(io, join(("start_seed", "run_seed", "T", "paper_mcs", "F_dl", "F_dd", "F_ll", "F_dM", "F_lM",
        "N_dl", "N_dd", "N_ll", "N_dM", "N_lM", "mismatched_bonds", "alive_dark", "alive_light",
        "cells_dark", "cells_light", "isolated", "wall_s"), '\t'))
    for t in TS
        σ = ownership(sol.u[findfirst(==(PAPER_MCS * t), sol.t)])
        b = bond_counts(annealed(σ, k0, prob), k0)
        N = sum(values(b))
        a = cell_areas(σ, k0)
        keys5 = (:dl, :dd, :ll, :dM, :lM)
        println(io, join((start_seed, run_seed, T, t,
            (N == 0 ? NaN : round(b[key] / N; digits = 6) for key in keys5)...,
            (b[key] for key in keys5)..., N,
            count(c -> k0[c] == 1 && a[c] > 0, eachindex(k0)), count(c -> k0[c] == 2 && a[c] > 0, eachindex(k0)),
            count(==(1), k0), count(==(2), k0), isolated(σ), round(wall; digits = 1)), '\t'))
    end
end
mv(out * ".part", out; force = true)
@info "done" out wall
