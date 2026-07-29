# [Backends and performance](@id backends-and-performance)

Choose a backend after the model and algorithm are explicit. Backend compatibility, performance,
and scientific evidence are separate questions.

## Preflight the exact run

```@example backends-and-performance
using PottsToolkit
import CorePotts

# Preflight the exact model–algorithm pair before measuring or changing backends.
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
    tspan = (0, 1),
    seed = 19,
)
algorithm = SequentialCPM(temperature = 2.0f0)
report = backend_report(problem, algorithm)
profile = CorePotts.algorithm_guarantees(algorithm)
solution = CorePotts.solve(problem, algorithm; save_everystep = false)

@assert report.qualified
@assert solution.stats.completed_mcs == 1
result = (; report, profile, stats = solution.stats,
    contracts = CorePotts.scientific_contract_versions())

(result.report.qualified, result.profile.tested_backends,
    result.stats.completed_mcs)
```

`backend_report` checks declared requirements against the selected execution path. Read its errors
and warnings rather than substituting a component or precision silently.

## CPU first

CPU is the installation and learning baseline. Build and validate the study there before enabling
a device backend. Metal and AMDGPU support depends on the exact algorithm, scalar/index policy,
component set, dimensionality, and retained evidence. Consult the capability report rather than a
package-level “GPU supported” claim.

## Measure the right boundary

Separate:

- compilation and first-call latency;
- steady-state MCS time;
- host synchronization and transfer;
- observation/materialization cost;
- rendering and file encoding.

Warm benchmarks should reuse compiled state where the study permits and report lattice size,
population, capacity, component set, algorithm, attempt normalization, precision, backend runtime,
and observation policy.

## Reproducibility before speed

A faster run with a different algorithm or numerical policy is not automatically a drop-in
replacement. Compare applicable scientific evidence and record the execution identity. Performance
benchmarks establish cost, not kinetic or equilibrium equivalence.
