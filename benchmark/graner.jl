# Fresh-process Graner–Glazier timing (load, first MCS, remake, warm throughput).
# usage: julia -t auto --project=benchmark benchmark/graner.jl [seq|cpu|metal] [mcs] [scale]
const T0 = time()
include("models.jl")
using KernelAbstractions: CPU
const LOAD = time() - T0

which = get(ARGS, 1, "cpu")
nmcs = parse(Int, get(ARGS, 2, "200"))
scale = parse(Int, get(ARGS, 3, "1"))
backend = which == "metal" ? (@eval using Metal; Metal.MetalBackend()) : CPU()
T = which == "metal" ? Float32 : Float64
alg = which == "seq" ? SequentialCPM(; proposal = Moore(1)) : CheckerboardCPM(; proposal = Moore(1))

t = time()
prob = graner_problem(; scale, nmcs, T)
const BUILD = time() - t

t = time()
integ = init(prob, alg; backend, save_start = false)
step!(integ); integ.u
const FIRST = time() - t

t = time()
for _ in 2:nmcs
    step!(integ)
end
st = integ.u
const WARM = time() - t

t = time()
integ2 = init(remake(prob; p = merge(graner_params(T), (; λ = T(2))), seed = 1), alg;
    backend, save_start = false)
step!(integ2); integ2.u
const REMAKE = time() - t

nsite = length(st.σ)
println(rpad("$which $(size(st.σ)) $T $(Threads.nthreads())t", 30),
    " load=", round(LOAD; digits = 2), "s build=", round(BUILD; digits = 3),
    "s first_mcs=", round(FIRST; digits = 2), "s remake_first=", round(REMAKE; digits = 3),
    "s warm=", round((nmcs - 1) / WARM; digits = 1), " MCS/s (",
    round(WARM / (nmcs - 1) / nsite * 1e9; digits = 2), " ns/attempt) retcode=",
    integ.retcode, " total=", round(time() - T0; digits = 1), "s")
