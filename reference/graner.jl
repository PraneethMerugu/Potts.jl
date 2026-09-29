# Legacy Graner–Glazier sorting run (reference stack, D-021), from the committed
# pre-equilibrated baseline in benchmark/data/graner. Mirrors SCDPotts/scripts/run_graner_paper.jl.
# usage: julia --project=reference reference/graner.jl [mcs] [seed]   (MCS = N attempts, as in CorePotts)
const T0 = time()
using Potts, DelimitedFiles
const LOAD = time() - T0

nmcs = parse(Int, get(ARGS, 1, "320"))
seed = parse(UInt64, get(ARGS, 2, "97329219"))
dir = joinpath(@__DIR__, "..", "benchmark", "data", "graner")
labels = Int.(readdlm(joinpath(dir, "pre_equilibrated_ownership.tsv"), '\t', Int))
kinds = vec(readdlm(joinpath(dir, "cell_kinds.tsv"), '\t', Int))

dark = CellKind(:dark; extinction = ForbidExtinction())
light = CellKind(:light; extinction = ForbidExtinction())
medium = MediumKind(:medium)
system = PottsSystem(name = :graner_sorting, statements = StatementSet((
    Lattice(size(labels); boundary = Periodic(), relations = (proposal = Moore(), contact = Moore())),
    dark, light, medium,
    Volume(dark; target = 40.0, strength = 1.0),
    Volume(light; target = 40.0, strength = 1.0),
    ContactEnergy([(dark ↔ dark) => 2.0, (dark ↔ light) => 11.0, (light ↔ light) => 14.0,
        (medium ↔ dark) => 16.0, (medium ↔ light) => 16.0]),
    Protocol(Sweep(; temperature = 10.0, attempts = AttemptsPerSite(1)); name = :main))))
t = time()
problem = PottsProblem(system, PottsInitialState(ownership = LabelledCells(labels;
        cells = [k == 1 ? dark : light for k in kinds], medium)), (0, nmcs); seed)
const BUILD = time() - t
t = time()
solution = solve(problem, SequentialCPM(); backend = CPUBackend(), scalar_type = Float64,
    saveat = [nmcs])
const SOLVE = time() - t
failure_report(solution) === nothing || error("legacy run failed: $(failure_report(solution))")

"""Heterotypic fraction of cell–cell Moore bonds (each unordered bond once)."""
function heterotypic_fraction(σ, kinds)
    nx, ny = size(σ); unlike = cell = 0
    for y in 1:ny, x in 1:nx, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
        a = σ[x, y]; b = σ[mod1(x + dx, nx), mod1(y + dy, ny)]
        (a == b || a == 0 || b == 0) && continue
        cell += 1; unlike += kinds[a] != kinds[b]
    end
    return unlike / cell
end
σ = last(solution).ownership
println("legacy graner 72² mcs=$nmcs load=", round(LOAD; digits = 1), "s build=",
    round(BUILD; digits = 1), "s solve=", round(SOLVE; digits = 1), "s hetero=",
    round(heterotypic_fraction(σ, kinds); digits = 4))
