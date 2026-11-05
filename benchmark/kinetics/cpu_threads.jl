#     julia --project=benchmark -t <threads> benchmark/kinetics/cpu_threads.jl [<nmcs>]
# CheckerboardCPM on the CPU (P6.0bl): MCS per second of SequentialCPM, the checkerboard with its
# phases inline (one after another) and with each phase one threaded KA launch, on
# Graner–Glazier tiles in 2D and cubes in 3D. Sets `CorePotts.BLOCK_GRAIN` (the phase size
# below which the CPU runs a phase inline).
using CorePotts, Printf
include(joinpath(@__DIR__, "..", "models.jl"))
const NMCS = parse(Int, get(ARGS, 1, "20"))

function cubes(L, a)
    σ = zeros(Int32, L, L, L)
    c = 0
    for i in 1:a:(L - a + 1), j in 1:a:(L - a + 1), k in 1:a:(L - a + 1)
        σ[i:(i + a - 2), j:(j + a - 2), k:(k + a - 2)] .= (c += 1)
    end
    return σ, Int32[isodd(i) ? 1 : 2 for i in 1:c]
end
problem3(L) = (s = cubes(L, 5); PottsProblem(GRANER, initial_state(s...), Lattice((L, L, L)), (0, NMCS),
    merge(graner_params(), (; V0 = 64.0)); contact = Moore(1), seed = 5))

function rate(prob, alg; inline = false, threaded = false)
    CorePotts.BLOCK_GRAIN[] = inline ? typemax(Int) : 2048
    CorePotts._FORCE_BLOCK_KERNEL[] = threaded
    try
        integ = init(prob, alg; save_start = false, save_end = false)
        step!(integ); step!(integ)                             # compile, warm
        t = @elapsed for _ in 1:NMCS
            step!(integ)
        end
        return NMCS / t, integ
    finally
        CorePotts.BLOCK_GRAIN[] = 2048
        CorePotts._FORCE_BLOCK_KERNEL[] = false
    end
end

println("threads = $(Threads.nthreads())")
@printf("%-14s %9s %8s %10s %10s %10s %8s\n", "case", "sites", "blocks", "seq", "cb inline", "cb thread", "speedup")
for (label, prob) in [("2D 144²", graner_problem(; scale = 2)), ("2D 288²", graner_problem(; scale = 4)),
        ("2D 576²", graner_problem(; scale = 8)), ("2D 1152²", graner_problem(; scale = 16)),
        ("3D 40³", problem3(40)), ("3D 80³", problem3(80)), ("3D 160³", problem3(160))]
    cb = CheckerboardCPM(; proposal = Moore(1))
    s, _ = rate(prob, SequentialCPM(; proposal = Moore(1)))
    i, integ = rate(prob, cb; inline = true)
    t, _ = rate(prob, cb; threaded = true)
    nb = CorePotts.nblocks(integ.cache.layout)
    @printf("%-14s %9d %8d %10.1f %10.1f %10.1f %7.2fx\n", label, length(prob.u0.σ), nb, s, i, t, t / i)
end
