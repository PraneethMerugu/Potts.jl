# [Backends and performance](@id backends-and-performance)

Choose a backend after the model and algorithm are explicit. Backend compatibility, performance,
and scientific evidence are separate questions.

## Preflight the exact run

```@example backends-and-performance
performance = include(joinpath(
    ENV["POTTS_DOCS_ROOT"], "models", "tutorials",
    "backends_and_performance.jl"))
(performance.report.qualified, performance.profile.tested_backends,
    performance.stats.completed_mcs)
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
