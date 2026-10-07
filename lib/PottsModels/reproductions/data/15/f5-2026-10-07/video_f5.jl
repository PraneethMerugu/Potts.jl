# The video of case (b) run k = 1 (seed 15001) and of control run k = 1 (seed 15501): the
# colony from one cell to 1000, saved every 39 MCS (spec Q4) and at the stop, each site
# coloured by its cell's area from blue (20 px) to red (120 px) (spec §4.0.2 F1 convention),
# medium white, no cell outlines (D-156). The video is not committed (D-146): it is written
# to F5_VIDEO_DIR (default ./videos).
#     julia --project=docs lib/PottsModels/reproductions/data/15/f5-2026-10-07/video_f5.jl
using Potts, PottsModels, CairoMakie
using Potts: CorePotts

const L = 400
const OUT = get(ENV, "F5_VIDEO_DIR", joinpath(pwd(), "videos"))
mkpath(OUT)
sys = OpenVTReferenceMonolayer(; name = :p615e_vid, lattice = (L, L))
prob = PottsProblem(sys, openvt_reference_state(; lattice = (L, L)), (0, 100_000); capacity = 1500, seed = 1)
for (label, seed, γ) in (("b_run1_seed15001", 15_001, 0.0), ("control_gamma1e-4_run1_seed15501", 15_501, 1e-4))
    sol = solve(remake(prob; seed, p = [:γ => γ]), SequentialCPM(; proposal = Moore(1)); saveat = 39,
        callback = CorePotts.CallbackSet(PottsModels.stop_at_cells(1000), PottsModels.edge_guard(5; terminate = true)))
    frame(u) = (σ = Array(u.σ); v = Array(u.cell.volume);
        [s == 0 ? NaN : Float64(v[s]) for s in σ])
    img = Observable(frame(sol.u[1]))
    ttl = Observable("")
    fig = Figure(; size = (720, 760))
    ax = Axis(fig[1, 1]; aspect = DataAspect(), title = ttl)
    hidedecorations!(ax); hidespines!(ax)
    heatmap!(ax, img; colormap = :jet, colorrange = (20, 120), nan_color = :white)
    Colorbar(fig[2, 1], colormap = :jet, limits = (20, 120), vertical = false, label = "cell area (px)",
        flipaxis = false)
    path = joinpath(OUT, "15_openvt_f5_$(label).mp4")
    record(fig, path, eachindex(sol.u); framerate = 12) do i
        u = sol.u[i]
        img[] = frame(u)
        ttl[] = "Potts.jl $(γ == 0 ? "case (b)" : "control γ = 10⁻⁴"), seed $seed: MCS $(sol.t[i]) " *
                "($(round(sol.t[i] / 775; digits = 2)) cycles), N = $(count(>(0), u.cell.volume))"
    end
    println(path, " ", filesize(path))
end
