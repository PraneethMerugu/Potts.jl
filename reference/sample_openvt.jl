# Legacy OpenVT monolayer samples (division) for parity (D-021/D-022).
using Potts, PottsModels
const TIMES = [1, 2, 3, 5, 10, 20]
nseeds = parse(Int, get(ENV, "NSEEDS", "64"))
m = openvt_monolayer()
rows = String[]
for seed in 1:nseeds
    prob = PottsProblem(m.system, m.initial, (0, maximum(TIMES)); seed = UInt64(seed))
    sol = solve(prob, SequentialCPM(); backend = CPUBackend(), scalar_type = Float64, saveat = TIMES)
    failure_report(sol) === nothing || error("seed $seed failed: $(failure_report(sol))")
    for s in sol.u
        s.mcs in TIMES || continue
        σ = s.ownership
        vols = [count(==(c), σ) for c in 1:2]
        push!(rows, join((seed, s.mcs, vols..., count(>(0), unique(vec(σ)))), '\t'))
    end
    seed == 1 && println(propertynames(last(sol)), " ", last(sol).volumes)
end
open(joinpath(@__DIR__, "data", "openvt_parity.tsv"), "w") do io
    println(io, "# legacy Potts 427dc2e2 / PottsModels de97149 openvt_monolayer SequentialCPM, Float64")
    println(io, "seed\tmcs\tvolume1\tvolume2\tncells")
    foreach(r -> println(io, r), rows)
end
println("wrote $(length(rows)) rows")
