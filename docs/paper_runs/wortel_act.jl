# Paper run: the Act model of actin-driven migration (Niculescu, Textor & de Boer 2015;
# Wortel et al. 2021).
#
# Niculescu et al. (PLoS Comput. Biol. 11, e1004280), single-cell runs (Figs. 2-4): one cell
# (A = 500, λ_A = 50, P = 340, λ_P = 2) on a wrapped 200×200 lattice, no chemotaxis, runs of
# 30 000 MCS. The `WortelAct` defaults are the amoeboid set (λ_act = 200, max_act = 20, T = 20).
# The cell starts as a 23×23 square (area 529) at the centre, as in `test/papers.jl`.
#
#     julia --project=docs docs/paper_runs/wortel_act.jl
include(joinpath(@__DIR__, "common.jl"))

const SEED = 1
const G = 200
const T_END = 30_000
const EVERY = 100                          # 300 frames

σ0 = zeros(Int32, G, G)
σ0[89:111, 89:111] .= 1
model = WortelAct(; name = :act, lattice = (G, G))
prob = PottsProblem(model, [ownership => σ0, kind => [:cell]], (0, T_END); seed = SEED)
alg = SequentialCPM()                      # the model declares Moore(1) proposals

title = "Niculescu et al. (2015) Act model, amoeboid cell — $(G)×$(G) torus, $(T_END) MCS, seed $SEED\n" *
        "λ_act = 200, max_act = 20; one frame every $EVERY MCS"
act_key = SiteChannelKey(:act, Float64)
panels = [Panel("cell"; plot = (; category_palette = [:orangered3], medium_color = :white)),
    Panel("actin activity (act)"; encoding = ChannelEncoding(act_key),
        plot = (; colormap = :inferno, colorrange = (0, 20), nan_color = :white),
        # medium sites (always 0) are left blank so the cell's inactive body shows dark
        channels = u -> (RenderChannel(act_key, ifelse.(u.σ .== 0, NaN, Float64.(u.site.act))),),
        colorbar = ("act", :inferno, (0, 20)))]
paper_run("wortel_act"; prob, alg, saveat = EVERY, title, framerate = 30, panels, size = (1300, 720),
    meta = Dict{String, Any}("model" => "WortelAct",
        "caption" => "Paper run — Niculescu et al. (2015) Act model, amoeboid cell (λ_act = 200, max_act = 20): 200×200 torus, 30 000 MCS (paper: same), seed 1. Initial shape: 23×23 square (unstated in the paper).",
        "paper" => "Niculescu, Textor & de Boer, PLoS Comput. Biol. 11, e1004280 (2015), single-cell runs (Figs. 2-4, 30 000 MCS); Wortel et al., Biophys. J. 120, 2609 (2021)",
        "initial_state" => "one 23×23 square cell (area 529) at the lattice centre",
        "save_every_mcs" => EVERY,
        "deviations" => "Initial cell shape not stated in the paper (a 23×23 square here)."))
