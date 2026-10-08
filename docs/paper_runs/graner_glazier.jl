# Paper run: Graner & Glazier (1992 PRL; 1993 PRE) cell sorting, with reproduction 09's FULL
# fixture and the PRE's start and display protocols.
#
# PRE Fig. 12 / PRL Fig. 1: an aggregate of about 1000 cells (target area 40), dark and light
# randomly mixed, sorting parameters (J_dd = 2, J_dl = 11, J_ll = 14, J_cM = 16, λ = 1, T = 10;
# the `GranerGlazier` defaults), run to 10⁴ paper MCS. One paper MCS is 16 of ours, so 10⁴
# paper MCS = 160 000 MCS here.
#
# - Aggregate: reproduction 09's FULL replicate 1, `graner_glazier_aggregate(1000; seed = 1,
#   margin = 60)` on a periodic 347² lattice (the 60-site margin keeps the aggregate clear of
#   its periodic image over 10⁴ paper MCS).
# - Relaxed start (PRE §II D3; the recipe of `graner_glazier_state`, `data/graner/generate.jl`):
#   the aggregate is relaxed as one cell type (J_ll = 2, J_lM = 8, T = 5, λ = 1, V₀ = 40) for
#   400 paper MCS (6400 MCS), and only then does each cell take its dark or light kind.
# - Display: every frame is a copy annealed 2 paper MCS (32 MCS) at T = 0 with the run's own
#   energies (PRE p.2134, "We anneal the displayed data only"), as reproduction 09 measures.
#   The run itself is never annealed.
# Sorting is logarithmic in time, so frames are log-spaced: equal video time per decade.
#
#     julia --project=docs docs/paper_runs/graner_glazier.jl
include(joinpath(@__DIR__, "common.jl"))

const SEED = 1
const PAPER_MCS = 16                      # our MCS per paper MCS
const T_PAPER = 10_000                    # PRL Fig. 1(f), PRE Fig. 13 axis
const T_END = PAPER_MCS * T_PAPER
const T_RELAX = 400PAPER_MCS              # PRE §II D3
const NFRAMES = 240
const MARGIN = 60

σv, k0 = graner_glazier_aggregate(1000; seed = SEED, margin = MARGIN)
L = size(σv, 1)
gg = GranerGlazier(; name = :gg, lattice = size(σv))

## the relaxation: one cell type, the generator's energies
ncell = length(k0)
relax = PottsProblem(gg, [ownership => σv, kind => fill(:light, ncell),
        :J => [0 8 8; 8 2 2; 8 2 2], :T => 5.0, :λ => 1.0, :V₀ => 40.0], (0, T_RELAX); seed = SEED)
relax_wall = @elapsed σ0 = Array(solve(relax, SequentialCPM(; proposal = Moore(1)); saveat = T_RELAX).u[end].σ)
@assert all(>(0), [count(==(c), σ0) for c in 1:ncell]) "a cell vanished during relaxation"

prob = PottsProblem(gg, [ownership => σ0, kind => k0], (0, T_END); seed = SEED)
alg = SequentialCPM(; proposal = Moore(1))

## T = 0 annealed copy for display (reproduction 09's `annealed`)
function annealed(u)
    q = PottsProblem(GranerGlazier(; name = :anneal, lattice = size(u.σ)),
        [ownership => Array(u.σ), kind => k0, :T => 0.0], (0, 2PAPER_MCS); seed = 1)
    return solve(q, SequentialCPM(; proposal = Moore(1)); saveat = 2PAPER_MCS).u[end]
end
const ANNEALED = Dict{Int, Any}()
display_state(u, i) = get!(() -> annealed(u), ANNEALED, i)

# log-spaced saves from 1 paper MCS (16 MCS) to the end
saveat = unique(round.(Int, exp10.(range(log10(PAPER_MCS), log10(T_END); length = NFRAMES))))
title = "Graner & Glazier (1992) cell sorting — GranerGlazier, seed $SEED\n" *
        "$(L)×$(L), $(ncell) cells, $(T_END) MCS (10⁴ paper MCS); relaxed start\n" *
        "frames annealed 2 paper MCS at T = 0, log-spaced in time"

# phenotype colours: sorting is read by kind (dark, light)
panel = Panel(""; plot = (; category_palette = [:steelblue4, :lightgoldenrod1], medium_color = :white))
sol, info = paper_run("graner_glazier"; prob, alg, saveat, title, framerate = 24, panels = [panel],
    state = display_state,
    clock = t -> "t = $t MCS = $(round(t / PAPER_MCS; sigdigits = 3)) paper MCS",
    meta = Dict{String, Any}("model" => "GranerGlazier",
        "caption" => "Paper run — GranerGlazier with its defaults, the papers' sorting set (J_dd = 2, J_dl = 11, " *
                     "J_ll = 14, J_cM = 16, λ = 1, V₀ = 40, T = 10), reproduction 09's FULL fixture: 1000 cells " *
                     "(graner_glazier_aggregate(1000; seed = 1, margin = 60)) on a periodic $(L)×$(L) lattice, relaxed " *
                     "as one type for 400 paper MCS before the kinds are assigned (PRE §II D3), then 160 000 MCS = 10⁴ " *
                     "paper MCS (1 paper MCS = 16 MCS), seed 1, SequentialCPM(; proposal = Moore(1)). Each frame is a " *
                     "copy annealed 2 paper MCS at T = 0 (PRE: \"We anneal the displayed data only\"); frames are " *
                     "log-spaced in time. Dark cells blue, light cells yellow. " * rendered_on(),
        "paper" => "Graner & Glazier, PRL 69, 2013 (1992), Fig. 1; Glazier & Graner, PRE 47, 2128 (1993), Figs. 12-13; reproduction 09",
        "initial_state" => "graner_glazier_aggregate(1000; seed = $SEED, margin = $MARGIN), relaxed as one type (J_ll = 2, J_lM = 8, T = 5, λ = 1, V₀ = 40) for $T_RELAX MCS (400 paper MCS), seed $SEED; then the aggregate's kinds",
        "relax_wall_s" => round(relax_wall; digits = 1),
        "display" => "each frame annealed 2 paper MCS (32 MCS) at T = 0 with the run's energies, seed 1, on a copy",
        "paper_mcs" => T_PAPER, "mcs_per_paper_mcs" => PAPER_MCS,
        "frame_spacing" => "log",
        "deviations" => "Periodic lattice (paper unstated) with a 60-site medium margin; the relaxed aggregate starts from a centroidal Voronoi disk of 1000 cells rather than the PRE's staggered bricks; equal dark/light numbers (paper unstated). Reproduction 09 lists the rest (V-PRE5 late coarsening)."))
