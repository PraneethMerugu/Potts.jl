# Paper run: Merks et al. (2006) vasculogenesis by chemotaxis with elongated cells.
#
# Merks, Brodsky, Goligorsky, Newman & Glazier, Dev. Biol. 289, 44 (2006), Fig. 4: 282 cells
# placed at random over 333×333 sites of a 500×500 lattice (`merks_state`), snapshots at 4,
# 9, 12, 24 and 48 h; Fig. 5 follows the network to 50 h. One MCS is 30 s (p. 50), so 50 h
# is 6000 MCS. The parameters are the 2006 set (D-050; spec 01_merks.md §3.1, longcells.par),
# passed explicitly so the run is the same before and after it becomes the constructor
# default: A = 100, λ = 50, λ_L = 5, L = 50 px ("about 100 µm"), χ = 1000, T = 50,
# J_cM = 20, J_cc = 40, D = 0.75 px²/MCS (10⁻¹³ m²/s), α = ε = 5.4·10⁻³ /MCS (1.8·10⁻⁴ /s),
# 15 field substeps per MCS (Δt = 2 s), 10×10 initial cells (≈ A).
#
#     julia --project=docs docs/paper_runs/merks_vasculogenesis.jl
include(joinpath(@__DIR__, "common.jl"))

const SEED = 1
const T_END = 6000                          # 50 h at 30 s/MCS
const EVERY = 25                            # 240 frames + the start

model = MerksVasculogenesis(; name = :merks, contact_inhibited = false, V₀ = 100.0, λ = 50.0, λ_L = 5.0,
    L = 50.0, χ = 1000.0, T = 50.0, Dc = 0.75, σc = 5.4e-3, δc = 5.4e-3, J = [0.0 20.0; 20.0 40.0])
prob = PottsProblem(model, merks_state(; seed = SEED, side = 10), (0, T_END); seed = SEED,
    field_solver = ExplicitEuler(substeps = 15, lower = 0.0))
alg = SequentialCPM()                       # the model declares Moore(1) proposals

title = "Merks et al. (2006) vasculogenesis — 500×500, 282 cells, $(T_END) MCS (50 h), seed $SEED\n" *
        "2006 set: A = 100, λ = 50, L = 50, λ_L = 5, χ = 1000, T = 50; one frame every $EVERY MCS (12.5 min)"
paper_run("merks_vasculogenesis"; prob, alg, saveat = EVERY, title, framerate = 24,
    panels = [Panel(""; plot = (; category_palette = [:firebrick3], medium_color = :white))],
    size = (760, 800),
    meta = Dict{String, Any}("model" => "MerksVasculogenesis",
        "caption" => "Paper run — Merks et al. (2006) vasculogenesis, the paper's 2006 parameter set: 282 cells on 500×500, 6000 MCS = 50 h (paper: Fig. 4 to 48 h, Fig. 5 to 50 h), seed 1. Remaining differences: a hard connectivity veto instead of the E₀ penalty; free closed walls instead of a frozen border with J_cB = 100; a zero-flux field boundary instead of an absorbing c = 0 ring; 10×10 initial cells (unstated in the paper).",
        "paper" => "Merks et al., Dev. Biol. 289, 44 (2006), Figs. 4-5",
        "initial_state" => "merks_state(; seed = $SEED, side = 10): 282 square 10×10 cells in the central 333×333 of 500×500",
        "parameters" => "V₀ = 100, λ = 50, λ_L = 5, L = 50, χ = 1000, T = 50, Dc = 0.75, σc = δc = 5.4e-3, J = [0 20; 20 40], contact_inhibited = false",
        "field_solver" => "ExplicitEuler(substeps = 15, lower = 0.0)",
        "save_every_mcs" => EVERY,
        "deviations" => "Hard one-arc connectivity veto (paper: E₀ > 2000 penalty); free closed walls (paper: frozen border, J_cB = 100); zero-flux field boundary (authors' code: absorbing c = 0 ring); initial cells 10×10 squares (paper unstated); L = 50 px from the paper text (longcells.par: 60)."))
