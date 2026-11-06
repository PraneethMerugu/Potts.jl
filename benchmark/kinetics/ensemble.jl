#     julia --project=lib/PottsModels/test -t <threads> benchmark/kinetics/ensemble.jl <repo> <n,...>   # ROCm
# GPU ensembles (D-273): the OpenVT monolayer case (b) (1400², to 1000 cells) as an
# EnsembleProblem with EnsembleThreads, n trajectories per ensemble (one Julia task and one device
# queue each); prints the total MCS/s. Results 2026-11-06 in DECISIONS D-273.
include(joinpath(ARGS[1], "lib/PottsModels/reproductions/data/15/checkerboard-2026-10-10/run_checkerboard.jl"))
using Printf
const ALG = CheckerboardCPM(; proposal = Moore(1))
α = A0 / P615M_CYCLE_SEQ
c = P615F_CASES.b
base(L) = remake(cb_problem(L); p = [:β => c.beta, :γ => c.gamma, :σ_X => c.sigma_X, :α => α])
cbs(cells) = Potts.CorePotts.CallbackSet(PottsModels.stop_at_cells(cells), PottsModels.edge_guard(P615F_GUARD; terminate = true))
out(sol, i) = ((Int(sol.t[end]), sol.stats.lifecycle.divisions + 1 - count(>(0), Array(sol.u[end].cell.volume))), false)
ens(L, cells, n) = solve(EnsembleProblem(base(L); output_func = out), ALG, EnsembleThreads(); backend = cb_backend(),
    trajectories = n, callback = cbs(cells), save_start = false)
t = @elapsed ens(400, 2, 2 * Threads.nthreads())      # cold: compiled inside the concurrent trajectories
@info "cold ensemble (compile in the trajectories)" t threads = Threads.nthreads()
for n in parse.(Int, split(ARGS[2], ','))
    t = @elapsed r = ens(c.L, c.cells, n)
    s = sum(first, r.u)
    @printf("in flight %2d (threads %d)  %5.1f s  %6.0f MCS/s total  %4.0f per run  lost %s\n", min(n, Threads.nthreads()),
        Threads.nthreads(), t, s / t, s / t / min(n, Threads.nthreads()), string(last.(r.u)))
end
