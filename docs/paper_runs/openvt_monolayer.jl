# Paper run: the OpenVT growing-monolayer reference model (OpenVT reference models,
# `monolayer/`), Artistoo parameter set (`OpenVTGrowingMonolayer` defaults: A₀ = 25, λ = 20,
# τ = 84, T = 20, J_cc = J_cM = 20).
#
# The benchmark grows one cell into a colony "until N = 10⁴ cells" (OpenVT monolayer
# specification, R. Vetter, 12 Oct 2024), with three cases: no contact inhibition, type 1
# (β = 0.8) and type 2 (γ = 0.5). This is the uninhibited baseline (β = 0, the default).
# A 10⁴-cell colony (≈ 2.4·10⁵ sites) does not fit the constructor's default 400×400 lattice,
# so the lattice is 800×800. The run goes to 1500 MCS; the video stops at the first save with
# N ≥ 10⁴.
#
#     julia --project=docs docs/paper_runs/openvt_monolayer.jl
include(joinpath(@__DIR__, "common.jl"))

const SEED = 1
const LATTICE = (800, 800)
const T_END = 1500
const EVERY = 5
const N_STOP = 10_000

model = OpenVTGrowingMonolayer(; name = :monolayer, lattice = LATTICE)
prob = PottsProblem(model, openvt_monolayer_state(; lattice = LATTICE), (0, T_END); seed = SEED, capacity = 20_000)
alg = SequentialCPM()                       # the model declares Moore(1) proposals

ncells(u) = count(>(0), u.cell.volume)
stop_at(sol) = something(findfirst(u -> ncells(u) >= N_STOP, sol.u), lastindex(sol.u))
frames(sol) = firstindex(sol.u):stop_at(sol)
title(sol, idx) = "OpenVT growing monolayer (Artistoo set, no contact inhibition) — " *
                  "$(LATTICE[1])×$(LATTICE[2]), seed $SEED\none cell to N = $(ncells(sol.u[last(idx)])) cells " *
                  "at $(sol.t[last(idx)]) MCS; one frame every $EVERY MCS"
paper_run("openvt_monolayer"; prob, alg, saveat = EVERY, title, frames, framerate = 24,
    panels = [Panel(""; encoding = CellIdentityEncoding(),
        plot = (; medium_color = :white, boundaries = true, boundary_width = 0.2, boundary_color = :gray20))],
    size = (760, 800),
    meta = (sol, idx) -> Dict{String, Any}("model" => "OpenVTGrowingMonolayer",
        "caption" => "Paper run — OpenVT growing monolayer, Artistoo set, no contact inhibition: one cell to N = $(ncells(sol.u[last(idx)])) cells (benchmark: until N = 10⁴) at $(sol.t[last(idx)]) MCS on 800×800 (constructor default 400×400 is too small for 10⁴ cells), seed 1.",
        "paper" => "OpenVT reference models, monolayer growth (github.com/OpenVT/reference_models, monolayer/; spec email R. Vetter 2024-10-12): grow until N = 10^4 cells",
        "initial_state" => "openvt_monolayer_state(; lattice = $LATTICE): one 5×5 cell at the centre",
        "stop_rule" => "video ends at the first save with N ≥ $N_STOP",
        "final_cells" => ncells(sol.u[last(idx)]), "final_mcs" => sol.t[last(idx)],
        "save_every_mcs" => EVERY,
        "deviations" => "Lattice 800×800 (constructor default 400×400 cannot hold 10^4 cells; the benchmark fixes no lattice). Uninhibited case only (β = 0)."))
