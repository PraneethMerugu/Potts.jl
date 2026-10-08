# Paper run: the OpenVT monolayer reference model of the consortium manuscript (Table S1),
# `OpenVTReferenceMonolayer`, case (b) of reproduction 15: β = γ = 0 (no contact inhibition),
# stochastic division threshold X ~ N(2, 0.4), one disc-shaped cell of area A*(0) = 50 at the
# centre of a closed 1400² lattice, grown until the end of the first MCS with N ≥ 10⁴ cells.
# Reproduction 15 runs case (b) to 10³ cells (Figures 3 and 5) and the same parameters to 10⁴
# as case (a); this video follows the 10⁴ stop. The problem is the reproduction's
# (`p615f_problem` in its frozen test; `video_f3_f8.jl` in `data/15/f3-f8-2026-10-08/`):
# SequentialCPM(; proposal = Moore(1)), `edge_guard(5; terminate = true)`, run seed 15001
# (case (b), run 1). Frames are recorded during the run (no states kept), one every 39 MCS
# (≈ 1/20 cycle) and at the stop; the view zooms out with the colony.
#
#     julia --project=docs docs/paper_runs/openvt_monolayer.jl
include(joinpath(@__DIR__, "common.jl"))
using Potts: CorePotts

const SEED = 15_001
const L = 1400
const N_STOP = 10_000
const EVERY = 39
const CYCLE = 775                                     # 5T = A*(0)/α MCS

sys = OpenVTReferenceMonolayer(; name = :openvt_ref, lattice = (L, L))
prob = PottsProblem(sys, openvt_reference_state(; lattice = (L, L)), (0, 100_000);
    capacity = ceil(Int, 1.3N_STOP) + 100, seed = SEED)
prob = remake(prob; p = [:β => 0.0, :γ => 0.0, :σ_X => 0.4])
alg = SequentialCPM(; proposal = Moore(1))
ncells(u) = count(>(0), u.cell.volume)

solve(remake(prob; tspan = (0, 2)), alg)                                   # compile

fig = Figure(; size = (720, 760), fontsize = 14, backgroundcolor = :white)
Label(fig[0, 1], "OpenVT reference monolayer (Table S1), case (b): β = γ = 0, X ~ N(2, 0.4)\n" *
                 "OpenVTReferenceMonolayer, closed $(L)×$(L), seed $SEED; one frame every $EVERY MCS";
    fontsize = 15, font = :bold, tellwidth = false)
ax = Axis(fig[1, 1]; aspect = DataAspect())
hidedecorations!(ax)
frame = Observable(renderframe(prob.u0; mcs = 0))
pottsplot!(ax, frame; encoding = CellIdentityEncoding(), boundaries = false, medium_color = :white)
clk = Observable("")
Label(fig[2, 1], clk; fontsize = 15, tellwidth = false)
half = Ref(25.0)
mid = (L + 1) / 2
vs = Makie.VideoStream(fig; framerate = 24)
nframes = Ref(0)
rec_wall = Ref(0.0)
function rec(integ)
    rec_wall[] += @elapsed begin
        u = integ.u
        frame[] = renderframe(u; mcs = integ.t)
        I = findall(!=(0), u.σ)
        ext = maximum(max(abs(J[1] - mid), abs(J[2] - mid)) for J in I)
        half[] = max(half[], 1.15ext + 10)
        limits!(ax, mid - half[], mid + half[], mid - half[], mid + half[])
        clk[] = "t = $(integ.t) MCS = $(round(integ.t / CYCLE; digits = 2)) cell cycles, N = $(ncells(u)) cells"
        recordframe!(vs)
        nframes[] += 1
    end
    return nothing
end
cb = CorePotts.DiscreteCallback((u, t, integ) -> t % EVERY == 0 || ncells(u) >= N_STOP, rec;
    initialize = (cb, u, t, integ) -> rec(integ), save_positions = (false, false))
wall = @elapsed sol = solve(prob, alg; save_start = false,
    callback = CorePotts.CallbackSet(cb, PottsModels.stop_at_cells(N_STOP), PottsModels.edge_guard(5; terminate = true)))
wall -= rec_wall[]
mp4 = joinpath(ASSETS, "openvt_monolayer.mp4")
save(mp4, vs)
reencode(mp4)
u = sol.u[end]
N, T_STOP = ncells(u), Int(sol.t[end])
@assert N >= N_STOP "stopped at N = $N ($(sol.retcode))"
info = run_info("openvt_monolayer"; wall, rec = rec_wall[], mp4)
merge!(info, Dict{String, Any}(
    "model" => "OpenVTReferenceMonolayer",
    "title" => "OpenVT reference monolayer (Table S1), case (b)",
    "lattice" => [L, L], "tspan" => [0, T_STOP], "frames" => nframes[], "framerate" => 24,
    "recorded_mcs" => [0, T_STOP], "save_every_mcs" => EVERY, "seed" => SEED,
    "algorithm" => string(alg), "retcode" => string(sol.retcode),
    "final_cells" => N, "final_mcs" => T_STOP, "final_cycles" => round(T_STOP / CYCLE; digits = 2),
    "parameters" => "Table S1 defaults: A*(0) = 50, λ = 2, T = 20, α = 50/775, J_cc = 20, J_cM = 10, μ_X = 2, σ_X = 0.4; β = γ = 0",
    "initial_state" => "openvt_reference_state(; lattice = ($L, $L)): one disc of area A*(0) at the centre",
    "stop_rule" => "end of the first MCS with N ≥ $N_STOP (stop_at_cells), edge_guard(5; terminate = true)",
    "paper" => "OpenVT consortium, Reference Model for the Simulation of a Growing Tissue Monolayer with Contact Inhibition (in preparation), §2.1 and Table S1; reproduction 15, case (b)",
    "deviations" => "None in the model (Table S1). The unbounded plane is a closed 1400² lattice the colony never reaches (edge guard). The full list is on reproduction page 15.",
    "caption" => "Paper run — OpenVTReferenceMonolayer (the manuscript's Table S1: A*(0) = 50, λ = 2, T = 20, " *
                 "α = 50/775 per MCS, J_cc = 20, J_cM = 10, X ~ N(2, 0.4)), case (b) of reproduction 15 " *
                 "(β = γ = 0, no contact inhibition): one cell to N = $N cells at MCS $T_STOP " *
                 "($(round(T_STOP / CYCLE; digits = 2)) cell cycles of 775 MCS) on a closed $(L)×$(L) lattice, seed $SEED, " *
                 "SequentialCPM(; proposal = Moore(1)), one frame every $EVERY MCS. Each cell has its own colour. " *
                 rendered_on()))
write_sidecar("openvt_monolayer", info)
