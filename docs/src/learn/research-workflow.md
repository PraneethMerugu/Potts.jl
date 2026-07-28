# [Research workflow](@id research-workflow)

A defensible Potts study treats model construction, execution, analysis, evidence, and publication
as connected but separately versioned stages.

## One repeatable workflow

1. State the biological question and measurable outcome.
2. Declare and validate the model.
3. Freeze domain, initialization distribution, algorithm, backend, precision, and observation
   policy.
4. Define burn-in, stopping rule, statistic, replicates, and uncertainty before interpreting
   output.
5. Run a seeded ensemble through the engine's semantic seed policy.
6. Retain fingerprints, contracts, environment, raw observations, and analysis code.
7. Admit a reproduction to Published Models only after its independent evidence gate passes.

```@example research-workflow
using PottsToolkit
import CorePotts

# Freeze one explicit problem before deriving independent ensemble trajectories.
medium = Medium(:Medium)
cell = CellType(:Cell)
model = PottsModel(medium, cell, Volume(cell => (target = 12, strength = 2)))
mask = falses(10, 10)
mask[4:6, 4:7] .= true
problem = PottsProblem(
    model,
    CartesianDomain(size(mask)),
    Layout(Place(cell, mask; identity = 1));
    capacity = 2,
    tspan = (0, 2),
    seed = 0x1234,
)
ensemble = CorePotts.EnsembleProblem(problem; seed = 0x5eed)
solutions = CorePotts.solve(
    ensemble,
    SequentialCPM(temperature = 2.0f0),
    CorePotts.EnsembleSerial();
    trajectories = 3,
    save_start = false,
    save_end = true,
)
seeds = [solution.provenance.seed for solution in solutions.u]

@assert length(unique(seeds)) == 3
@assert length(solutions.u) == 3
result = (; solutions, seeds,
    contracts = CorePotts.scientific_contract_versions())

(length(result.solutions.u), result.seeds, result.contracts.freeze_status)
```

The canonical program uses `EnsembleProblem` and `EnsembleSerial` to derive three distinct,
reproducible trajectory seeds. Do not generate ensemble seeds through incidental task order or ad
hoc arithmetic.

## Claims and evidence

Mechanism examples require quantitative assertions. Equilibrium, kinetic equivalence, cross-backend
agreement, published reproduction, and physical-time calibration each require their applicable
evidence contract. A successful smoke run or attractive animation is not a substitute.

## Archive enough to rerun

Store the normalized model and execution identities, exact environment, seed policy, observation
schema, analysis source, output metadata, and any deviations from the intended protocol. Prefer
small typed observations over opaque state dumps, while retaining checkpoints when exact
continuation matters.

The [Reproducible Ensemble](@ref reproducible-ensemble) example expands this pattern with final
volume statistics.
