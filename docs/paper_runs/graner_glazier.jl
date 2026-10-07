# Paper run: Graner & Glazier (1992 PRL; 1993 PRE) cell sorting.
#
# PRE Fig. 12 / PRL Fig. 1: an aggregate of about 1000 cells (target area 40), dark and light
# randomly mixed, sorting parameters (J_dd = 2, J_dl = 11, J_ll = 14, J_cM = 16, λ = 1, T = 10;
# the `GranerGlazier` defaults), run to 10⁴ paper MCS. One paper MCS is 16 of ours
# (`GranerGlazier` docstring), so 10⁴ paper MCS = 160 000 MCS here.
# Sorting is logarithmic in time, so frames are log-spaced: equal video time per decade.
#
#     julia --project=docs docs/paper_runs/graner_glazier.jl
include(joinpath(@__DIR__, "common.jl"))

const SEED = 1
const PAPER_MCS = 16                      # our MCS per paper MCS
const T_PAPER = 10_000                    # PRL Fig. 1(f), PRE Fig. 13 axis
const T_END = PAPER_MCS * T_PAPER
const NFRAMES = 240

# paper-size aggregate. The lattice is periodic (the paper does not say): with the default
# 10-site margin the aggregate deforms enough over 10⁴ paper MCS to join its periodic image,
# so the margin is 60 sites (a 120-site gap to the image).
const MARGIN = 60
σ0, k0 = graner_glazier_aggregate(1000; seed = SEED, margin = MARGIN)
gg = GranerGlazier(; name = :gg, lattice = size(σ0))
prob = PottsProblem(gg, [ownership => σ0, kind => k0], (0, T_END); seed = SEED)
alg = SequentialCPM(; proposal = Moore(1))

# log-spaced saves from 1 paper MCS (16 MCS) to the end
saveat = unique(round.(Int, exp10.(range(log10(PAPER_MCS), log10(T_END); length = NFRAMES))))
L = size(σ0, 1)
title = "Graner & Glazier (1992) cell sorting — $(L)×$(L), $(length(k0)) cells, " *
        "$(T_END) MCS (10⁴ paper MCS), seed $SEED\nframes log-spaced in time"

panel = Panel(""; plot = (; category_palette = [:steelblue4, :lightgoldenrod1],   # dark, light cells
    medium_color = :white))
paper_run("graner_glazier"; prob, alg, saveat, title, framerate = 24, panels = [panel],
    clock = t -> "t = $t MCS = $(round(t / PAPER_MCS; sigdigits = 3)) paper MCS",
    meta = Dict{String, Any}("model" => "GranerGlazier",
        "caption" => "Paper run — Graner & Glazier (1992, 1993) cell sorting: 1000 cells on $(L)×$(L) (paper: ≈ 1000 cells, lattice unstated), 160 000 MCS = 10⁴ paper MCS (paper: same; 1 paper MCS = 16 MCS), seed 1, frames log-spaced in time. Start: an unrelaxed Voronoi aggregate (the paper relaxes it 400 paper MCS first).",
        "paper" => "Graner & Glazier, PRL 69, 2013 (1992), Fig. 1; Glazier & Graner, PRE 47, 2128 (1993), Figs. 12-13",
        "initial_state" => "graner_glazier_aggregate(1000; seed = $SEED, margin = $MARGIN)",
        "paper_mcs" => T_PAPER, "mcs_per_paper_mcs" => PAPER_MCS,
        "frame_spacing" => "log",
        "deviations" => "Initial aggregate is a centroidal Voronoi disk, not Potts-relaxed (PRE §II D3 relaxes 400 paper MCS); periodic lattice (paper unstated) with a 60-site medium margin so the aggregate never meets its periodic image; no T=0 annealing of displayed frames."))
