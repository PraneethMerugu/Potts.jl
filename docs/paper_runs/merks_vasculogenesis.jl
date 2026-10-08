# Paper run: Merks et al. (2006) vasculogenesis by autocrine chemotaxis of elongated cells,
# the published constructor `Merks2006` (D-153) as reproduction 01 runs it.
#
# Merks, Brodsky, Goligorsky, Newman & Glazier, Dev. Biol. 289, 44 (2006), Fig. 4: 282 cells
# placed at random over the central 333×333 sites of a 500×500 lattice, snapshots to 48 h;
# Fig. 5 follows the network to 50 h. One MCS is 30 s (p. 50), so 50 h is 6000 MCS.
# `Merks2006` defaults are the paper's set: the frozen one-site border with J_cB = 100, the
# soft connectivity penalty E₀ = 5000 (`rule = :soft`), the absorbing c = 0 border, A = 100,
# λ = 50, λ_L = 5, L = 50, χ = 1000, T = 50, D = 0.75, α = ε = 5.4·10⁻³, and 15 explicit field
# substeps of 2 s per MCS before each sweep. The start is `merks2006_layout()` (282 squares of
# 10², the paper's shape is unstated). The clock shows both MCS and hours.
#
#     julia --project=docs docs/paper_runs/merks_vasculogenesis.jl
include(joinpath(@__DIR__, "common.jl"))

const SEED = 1
const T_END = 6000                          # 50 h at 30 s/MCS
const EVERY = 25                            # 240 frames + the start (12.5 min)
const LAT = (500, 500)

model = Merks2006(; name = :m6, lattice = LAT)
prob = PottsProblem(model, layout(merks2006_layout(; lattice = LAT, seed = SEED), LAT), (0, T_END);
    field_solver = ExplicitEuler(substeps = 15), seed = SEED)
alg = SequentialCPM()                       # the model declares Moore(1) proposals

hours(t) = round(t / 120; digits = 1)
title = "Merks et al. (2006) vasculogenesis — Merks2006, 500×500, 282 cells, $(T_END) MCS (50 h), seed $SEED\n" *
        "A = 100, λ = 50, L = 50, λ_L = 5, χ = 1000, T = 50, E₀ = 5000 (soft); one frame every $EVERY MCS (12.5 min)"
sol, info = paper_run("merks_vasculogenesis"; prob, alg, saveat = EVERY, title, framerate = 24,
    # each cell its own colour (D-172); the one-site frozen border is cropped from the view
    panels = [Panel(""; encoding = CellIdentityEncoding(), plot = (; medium_color = :white),
        limits = (1.5, LAT[1] - 0.5, 1.5, LAT[2] - 0.5))],
    size = (760, 800),
    clock = t -> "t = $t MCS = $(hours(t)) h",
    meta = Dict{String, Any}("model" => "Merks2006",
        "caption" => "Paper run — `Merks2006` (Merks et al. 2006, Figs. 4–5) with its defaults, the paper's set: " *
                     "A = 100, λ = 50, λ_L = 5, L = 50, χ = 1000, T = 50, D = 0.75, α = ε = 5.4·10⁻³, soft connectivity " *
                     "penalty E₀ = 5000, frozen border (J_cB = 100) with c = 0, 15 field substeps per MCS. 282 cells of 10² " *
                     "(`merks2006_layout`) on 500×500, 6000 MCS = 50 h (paper: Fig. 4 to 48 h, Fig. 5 to 50 h), seed 1, " *
                     "`SequentialCPM`, one frame every 25 MCS; the clock shows MCS and hours. Each cell has its own colour. " *
                     rendered_on(),
        "paper" => "Merks et al., Dev. Biol. 289, 44 (2006), Figs. 4-5; reproduction 01",
        "initial_state" => "layout(merks2006_layout(; lattice = (500, 500), seed = $SEED), (500, 500)): 282 square 10×10 cells in the central 333×333, one-site frozen border",
        "parameters" => "Merks2006 defaults (rule = :soft): T = 50, λ = 50, A = 100, λ_L = 5, L = 50, E₀ = 5000, χcM = χcc = 1000, s = 0, Dc = 0.75, α = ε = 5.4e-3, J = [0 20 0; 20 40 100; 0 100 0]",
        "field_solver" => "ExplicitEuler(substeps = 15)",
        "save_every_mcs" => EVERY,
        "deviations" => "As reproduction 01 lists them: L = 50 px from the paper text (files: 60; provisional); E₀ = 5000 (paper > 2000; files 2000 or 5000); 10² square seeding (paper unstated; files: Eden); unsplit explicit Euler (TST: operator-split, 0.11 % of max c per MCS)."))
