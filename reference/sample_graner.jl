# Legacy Graner–Glazier samples for parity tests (D-021/D-022). Writes
# reference/data/graner_parity.tsv: one row per seed of the observables in `observables`.
# usage: julia --project=reference reference/sample_graner.jl [nseeds] [mcs]
empty!(ARGS)
push!(ARGS, "1")
include(joinpath(@__DIR__, "graner.jl"))          # defines system, labels, kinds, …
include(joinpath(@__DIR__, "..", "test", "parity", "observables.jl"))

nseeds = parse(Int, get(ENV, "NSEEDS", "16"))
nmcs = parse(Int, get(ENV, "MCS", "320"))
rows = map(1:nseeds) do seed
    pr = PottsProblem(system, PottsInitialState(ownership = LabelledCells(labels;
        cells = [k == 1 ? dark : light for k in kinds], medium)), (0, nmcs); seed = UInt64(seed))
    sol = solve(pr, SequentialCPM(); backend = CPUBackend(), scalar_type = Float64, saveat = [nmcs])
    failure_report(sol) === nothing || error("seed $seed failed")
    observables(last(sol).ownership, kinds)
end
mkpath(joinpath(@__DIR__, "data"))
open(joinpath(@__DIR__, "data", "graner_parity.tsv"), "w") do io
    println(io, "# legacy Potts 427dc2e2 SequentialCPM, Moore proposal+contact, 72² baseline, mcs=$nmcs")
    println(io, join(keys(first(rows)), '\t'))
    for r in rows
        println(io, join(values(r), '\t'))
    end
end
println("wrote $(length(rows)) legacy samples")
