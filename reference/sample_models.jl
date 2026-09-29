# Legacy Merks and Wortel samples for parity tests (D-021/D-022).
# Writes reference/data/{merks,wortel}_parity.tsv: one row per (seed, mcs).
# usage: NSEEDS=64 julia --project=reference reference/sample_models.jl
using Potts, PottsModels

const TIMES = [2, 5, 10, 20, 40]
nseeds = parse(Int, get(ENV, "NSEEDS", "64"))

function sample(model, quantity, filename)
    rows = String[]
    for seed in 1:nseeds
        prob = PottsProblem(model.system, model.initial, (0, maximum(TIMES)); seed = UInt64(seed))
        sol = solve(prob, SequentialCPM(); backend = CPUBackend(), scalar_type = Float64,
            saveat = TIMES)
        failure_report(sol) === nothing || error("seed $seed failed: $(failure_report(sol))")
        for s in sol.u
            σ = s.ownership
            q = getproperty(s, quantity)
            vols = [count(==(c), σ) for c in 1:2]
            push!(rows, join((seed, s.mcs, vols..., sum(q), maximum(q)), '\t'))
        end
    end
    mkpath(joinpath(@__DIR__, "data"))
    open(joinpath(@__DIR__, "data", filename), "w") do io
        println(io, "# legacy Potts 427dc2e2 / PottsModels de97149 SequentialCPM, Float64")
        println(io, "seed\tmcs\tvolume1\tvolume2\t$(quantity)_sum\t$(quantity)_max")
        foreach(r -> println(io, r), rows)
    end
    println("wrote $(length(rows)) rows to $filename")
end

sample(merks_vasculogenesis(), :concentration, "merks_parity.tsv")
sample(wortel_migration(), :activity, "wortel_parity.tsv")
