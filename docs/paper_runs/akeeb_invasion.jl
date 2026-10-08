# Paper run: Akeeb, Marcus & Jiang (2026) leader/follower tumour invasion.
#
# The authors' released reference sample `Sample/Multimodal_invasion` (J_LF = 2, λ = μ = 24,
# PP = 0.5): the published 500×300 slab (`akeeb_state`), run for the CompuCell3D source's
# 701 steps (MCS 0-700; one CC3D step is one MCS here). Paper Fig. 4 (bottom row) and
# S2 Video (D) show this multimodal phenotype at 0, 350 and 700 MCS.
# μ = 24 is the constructor default (D-142), the authors' sample value; only J_LF is passed.
#
#     julia --project=docs docs/paper_runs/akeeb_invasion.jl
include(joinpath(@__DIR__, "common.jl"))

const SEED = 1
const LATTICE = (500, 300)
const T_END = 701
const EVERY = 3                             # 234 frames + the start
const JLF, PP = 2.0, 0.5

state = akeeb_state(; lattice = LATTICE, pp = PP)            # default layout seed (authors' slab)
model = AkeebInvasion(; name = :akeeb, lattice = LATTICE)
prob = PottsProblem(model, [state; :J => akeeb_contacts(JLF)], (0, T_END); seed = SEED, capacity = 4000)
@assert getp(prob, :μ)(prob) == 24.0                  # the default (D-142)
alg = SequentialCPM()                       # the model declares VonNeumann(1) proposals (CC3D order 1)

title = "Akeeb, Marcus & Jiang (2026) leader/follower invasion — 500×300, $(T_END) MCS, seed $SEED\n" *
        "multimodal sample: J_LF = 2, μ = 24, PP = 0.5 (leaders red, followers green)"
paper_run("akeeb_invasion"; prob, alg, saveat = EVERY, title, framerate = 24,
    panels = [Panel(""; plot = (; category_palette = [:red3, :forestgreen],   # leader, follower (paper Fig. 4)
        medium_color = :white))],
    size = (1100, 720),
    meta = Dict{String, Any}("model" => "AkeebInvasion",
        "caption" => "Paper run — `AkeebInvasion` (Akeeb, Marcus & Jiang 2026), the authors' multimodal sample: J = akeeb_contacts(2.0) (J_LF = 2), default μ = 24, PP = 0.5, other constructor defaults; `akeeb_state(; lattice = (500, 300), pp = 0.5)`, 500×300, 701 MCS (paper: 701 CC3D steps, MCS 0–700), seed 1, `SequentialCPM`, one frame every 3 MCS. Leaders red, followers green. " * rendered_on(),
        "paper" => "Akeeb, Marcus & Jiang, PLoS Comput. Biol. (2026), Fig. 4 bottom row, S2 Video (D); authors' Sample/Multimodal_invasion (2, 24, 0.5)",
        "initial_state" => "akeeb_state(; lattice = (500, 300), pp = 0.5) (default layout seed 0x5cd2609, seeding = :authors)",
        "parameters" => "J = akeeb_contacts(2.0); constructor defaults otherwise, including μ = 24 (D-142)",
        "save_every_mcs" => EVERY,
        "notes" => "Hollow red rings inside the follower slab are real: trapped leaders that grew into a ring around a follower. The local one-arc connectivity rule (CC3D Connectivity) only checks each copy's 8-ring and cannot prevent rings.",
        "deviations" => "Dynamics seed differs from the authors' unseeded CC3D run. Reproduction 10 lists the rest."))
