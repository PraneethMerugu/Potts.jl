# Paper run: Akeeb, Marcus & Jiang (2026) leader/follower tumour invasion.
#
# The authors' released reference sample `Sample/Multimodal_invasion` (J_LF = 2, λ = μ = 24,
# PP = 0.5): the published 500×300 slab (`akeeb_state`), run for the CompuCell3D source's
# 701 steps (MCS 0-700; one CC3D step is one MCS here). Paper Fig. 4 (bottom row) and
# S2 Video (D) show this multimodal phenotype at 0, 350 and 700 MCS.
# μ = 24 is passed explicitly: the constructor default is still 30, while D-050 (A5) and the
# authors' sample use 24.
#
#     julia --project=docs docs/paper_runs/akeeb_invasion.jl
include(joinpath(@__DIR__, "common.jl"))

const SEED = 1
const LATTICE = (500, 300)
const T_END = 701
const EVERY = 3                             # 234 frames + the start
const MU, JLF, PP = 24.0, 2.0, 0.5

state = akeeb_state(; lattice = LATTICE, pp = PP)            # default layout seed (authors' slab)
model = AkeebInvasion(; name = :akeeb, lattice = LATTICE)
prob = PottsProblem(model, [state; :μ => MU; :J => akeeb_contacts(JLF)], (0, T_END); seed = SEED, capacity = 4000)
alg = SequentialCPM()                       # the model declares VonNeumann(1) proposals (CC3D order 1)

title = "Akeeb, Marcus & Jiang (2026) leader/follower invasion — 500×300, $(T_END) MCS, seed $SEED\n" *
        "multimodal sample: J_LF = 2, μ = 24, PP = 0.5 (leaders red, followers green)"
paper_run("akeeb_invasion"; prob, alg, saveat = EVERY, title, framerate = 24,
    panels = [Panel(""; plot = (; category_palette = [:red3, :forestgreen],   # leader, follower (paper Fig. 4)
        medium_color = :white))],
    size = (1100, 720),
    meta = Dict{String, Any}("model" => "AkeebInvasion",
        "caption" => "Paper run — Akeeb, Marcus & Jiang (2026), multimodal sample (J_LF = 2, μ = 24, PP = 0.5): 500×300, 701 MCS (paper: 701 CC3D steps, MCS 0–700), seed 1. μ = 24 is passed explicitly (the constructor default is still 30).",
        "paper" => "Akeeb, Marcus & Jiang, PLoS Comput. Biol. (2026), Fig. 4 bottom row, S2 Video (D); authors' Sample/Multimodal_invasion (2, 24, 0.5)",
        "initial_state" => "akeeb_state(; lattice = (500, 300), pp = 0.5) (default layout seed 0x5cd2609, seeding = :authors)",
        "parameters" => "μ = 24, J = akeeb_contacts(2.0), other constructor defaults",
        "save_every_mcs" => EVERY,
        "notes" => "Hollow red rings inside the follower slab are real: trapped leaders that grew into a ring around a follower. The local one-arc connectivity rule (CC3D Connectivity) only checks each copy's 8-ring and cannot prevent rings.",
        "deviations" => "μ = 24 passed explicitly (constructor default 30; D-050 A5 sets 24, not yet in code). Dynamics seed differs from the authors' unseeded CC3D run."))
