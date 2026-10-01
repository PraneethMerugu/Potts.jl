# Paper run: Merks et al. (2006) vasculogenesis by chemotaxis with elongated cells.
#
# Merks, Brodsky, Goligorsky, Newman & Glazier, Dev. Biol. 289, 44 (2006), Fig. 4: 282 cells
# placed at random over 333×333 sites of a 500×500 lattice (`merks_state`), snapshots at 4,
# 9, 12, 24 and 48 h; Fig. 5 follows the network to 50 h. One MCS is 30 s (p. 50), so 50 h
# is 6000 MCS. Parameters are the `MerksVasculogenesis` defaults.
#
#     julia --project=docs docs/paper_runs/merks_vasculogenesis.jl
include(joinpath(@__DIR__, "common.jl"))

const SEED = 1
const T_END = 6000                          # 50 h at 30 s/MCS
const EVERY = 25                            # 240 frames + the start

model = MerksVasculogenesis(; name = :merks)
prob = PottsProblem(model, merks_state(; seed = SEED), (0, T_END); seed = SEED,
    field_solver = ExplicitEuler(substeps = 2, lower = 0.0))
alg = SequentialCPM()                       # the model declares Moore(1) proposals

title = "Merks et al. (2006) vasculogenesis — 500×500, 282 cells, $(T_END) MCS (50 h), seed $SEED\n" *
        "one frame every $EVERY MCS (12.5 min)"
paper_run("merks_vasculogenesis"; prob, alg, saveat = EVERY, title, framerate = 24,
    panels = [Panel(""; plot = (; category_palette = [:firebrick3], medium_color = :white,
        boundaries = true, boundary_width = 0.3, boundary_color = :gray15))],
    size = (760, 800),
    meta = Dict{String, Any}("model" => "MerksVasculogenesis",
        "caption" => "Paper run — Merks et al. (2006) vasculogenesis, constructor defaults (contact_inhibited = false): 282 cells (merks_state) on 500×500, 6000 MCS = 50 h (paper: Fig. 4 to 48 h, Fig. 5 to 50 h), seed 1. Differences from the authors' setup: cell size A = 50, λ = 25 here vs A = 100, λ = 50 (longcells.par); zero-flux field boundary here vs an absorbing c = 0 ring; free closed walls here vs a frozen border with J_cB = 100; hard connectivity veto vs the E₀ penalty; 2 field substeps vs 15.",
        "paper" => "Merks et al., Dev. Biol. 289, 44 (2006), Figs. 4-5",
        "initial_state" => "merks_state(; seed = $SEED): 282 square 7×7 cells in the central 333×333 of 500×500",
        "field_solver" => "ExplicitEuler(substeps = 2, lower = 0.0)",
        "save_every_mcs" => EVERY,
        "deviations" => "Shipped constructor defaults, not yet the D-050 2006 set: A = 50, λ = 25, L = 30 px (longcells.par: A = 100, λ = 50; paper L ≈ 50 px); zero-flux field boundary (authors: absorbing c = 0 ring); free closed walls (paper: frozen border, J_cB = 100); hard one-arc connectivity veto (paper: E₀ > 2000 penalty); fewest stable field substeps (2) instead of 15; initial cells 7×7 squares (paper unstated). Observed: a sparse network forms by ~1000-2000 MCS, then breaks into islands; the paper's stable polygonal network is not reproduced."))
