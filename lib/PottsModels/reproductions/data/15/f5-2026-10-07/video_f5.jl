# The videos of case (b) run k = 1 (seed 15001) and of control run k = 1 (seed 15501): the
# colony from one cell to 1000, saved every 39 MCS (spec Q4) and at the stop. Every cell gets
# its own categorical colour (MakiePotts' default per-cell palette, `CellIdentityEncoding`),
# medium dark grey, no cell outlines (D-156), no colour bar. The videos are not committed
# (D-146): they are written to F5_VIDEO_DIR (default ./videos).
#     julia --project=docs lib/PottsModels/reproductions/data/15/f5-2026-10-07/video_f5.jl
using Potts, PottsModels, CairoMakie, MakiePotts
using Potts: CorePotts

const L = 400
const OUT = get(ENV, "F5_VIDEO_DIR", joinpath(pwd(), "videos"))
mkpath(OUT)
sys = OpenVTReferenceMonolayer(; name = :p615e_vid, lattice = (L, L))
prob = PottsProblem(sys, openvt_reference_state(; lattice = (L, L)), (0, 100_000); capacity = 1500, seed = 1)
for (label, seed, γ) in (("b_run1_seed15001_cells", 15_001, 0.0), ("control_gamma1e-4_run1_seed15501_cells", 15_501, 1e-4))
    sol = solve(remake(prob; seed, p = [:γ => γ]), SequentialCPM(; proposal = Moore(1)); saveat = 39,
        callback = CorePotts.CallbackSet(PottsModels.stop_at_cells(1000), PottsModels.edge_guard(5; terminate = true)))
    frames = renderframes(sol)
    frame = Observable(first(frames))
    ttl = Observable("")
    fig = Figure(; size = (720, 720))
    ax = Axis(fig[1, 1]; aspect = DataAspect(), title = ttl)
    hidedecorations!(ax); hidespines!(ax)
    pottsplot!(ax, frame; encoding = CellIdentityEncoding(), boundaries = false)
    path = joinpath(OUT, "15_openvt_f5_$(label).mp4")
    record(fig, path, eachindex(frames); framerate = 12) do i
        frame[] = frames[i]
        ttl[] = "Potts.jl $(γ == 0 ? "case (b)" : "control γ = 10⁻⁴"), seed $seed: MCS $(sol.t[i]) " *
                "($(round(sol.t[i] / 775; digits = 2)) cycles), N = $(count(>(0), sol.u[i].cell.volume))"
    end
    println(path, " ", filesize(path))
end
