# The videos of run 1 of case (f) (seed 15201), case (b) (15001), case (a) (15701) and case (e)
# (15801): the colony from one cell to the stop (1000 or 10⁴ cells), one frame every 39 MCS
# (spec Q4) and at the stop, the same runs as the record's run 1 (same problem, seed and
# parameters). Every cell gets its own categorical colour (`CellIdentityEncoding`, with the
# D-172 fix), the medium is dark, no cell outlines (D-156), no colour bar; the view zooms out
# with the colony. Frames are recorded during the run, so no state is retained. The videos are
# not committed (D-146): they go to F3F8_VIDEO_DIR (default ./videos).
#     julia --project=docs lib/PottsModels/reproductions/data/15/f3-f8-2026-10-08/video_f3_f8.jl [f b a e]
using Potts, PottsModels, CairoMakie, MakiePotts
using Potts: CorePotts

const OUT = get(ENV, "F3F8_VIDEO_DIR", joinpath(pwd(), "videos"))
mkpath(OUT)
const RUNS = Dict(
    "f" => (; label = "f_sigmaX0_run1_seed15201", seed = 15_201, beta = 0.0, sigma_X = 0.0, L = 400, cells = 1000,
        title = "case (f), σ_X = 0"),
    "b" => (; label = "b_run1_seed15001", seed = 15_001, beta = 0.0, sigma_X = 0.4, L = 400, cells = 1000,
        title = "case (b)"),
    "a" => (; label = "a_run1_seed15701", seed = 15_701, beta = 0.0, sigma_X = 0.4, L = 1400, cells = 10_000,
        title = "case (a)"),
    "e" => (; label = "e_beta0.8_run1_seed15801", seed = 15_801, beta = 0.8, sigma_X = 0.4, L = 1400, cells = 10_000,
        title = "case (e), β = 0.8"))
const EVERY = 39

function video(c)
    L = c.L
    # the record's problem (the frozen test's p615f_problem)
    sys = OpenVTReferenceMonolayer(; name = Symbol(:p615f_m, L), lattice = (L, L))
    prob = PottsProblem(sys, openvt_reference_state(; lattice = (L, L)), (0, 100_000);
        capacity = ceil(Int, 1.3c.cells) + 100, seed = 1)
    fig = Figure(; size = (900, 900), backgroundcolor = :black)
    ttl = Observable("")
    ax = Axis(fig[1, 1]; aspect = DataAspect(), title = ttl, titlecolor = :white, backgroundcolor = :black)
    hidedecorations!(ax); hidespines!(ax)
    frame = Observable(renderframe(prob.u0; mcs = 0))
    pottsplot!(ax, frame; encoding = CellIdentityEncoding(), boundaries = false)
    half = Ref(25.0)
    mid = (L + 1) / 2
    vs = Makie.VideoStream(fig; framerate = 15)
    function rec(integ)
        u = integ.u
        frame[] = renderframe(u; mcs = integ.t)
        I = findall(!=(0), u.σ)
        ext = maximum(max(abs(J[1] - mid), abs(J[2] - mid)) for J in I)
        half[] = max(half[], 1.15ext + 10)
        limits!(ax, mid - half[], mid + half[], mid - half[], mid + half[])
        ttl[] = "Potts.jl $(c.title), seed $(c.seed): MCS $(integ.t) ($(round(integ.t / 775; digits = 2)) cycles), " *
                "N = $(count(>(0), u.cell.volume))"
        recordframe!(vs)
        return nothing
    end
    cb = Potts.DiscreteCallback((u, t, integ) -> t % EVERY == 0 || count(>(0), u.cell.volume) >= c.cells, rec;
        initialize = (cb, u, t, integ) -> rec(integ), save_positions = (false, false))
    sol = solve(remake(prob; seed = c.seed, p = [:β => c.beta, :γ => 0.0, :σ_X => c.sigma_X]),
        SequentialCPM(; proposal = Moore(1)); save_start = false,
        callback = CorePotts.CallbackSet(cb, PottsModels.stop_at_cells(c.cells), PottsModels.edge_guard(5; terminate = true)))
    path = joinpath(OUT, "15_openvt_f3f8_$(c.label)_cells.mp4")
    save(path, vs)
    println(path, " ", filesize(path), " ", sol.retcode, " MCS ", sol.t[end])
end
for k in (isempty(ARGS) ? ["f", "b", "a", "e"] : ARGS)
    video(RUNS[k])
end
