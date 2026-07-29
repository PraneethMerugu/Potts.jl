# [Scientific guarantees](@id scientific-guarantees)

Potts.jl separates API status, execution compatibility, and scientific qualification.

## Contract identities

`scientific_contract_versions()` returns the independent frozen identities for:

- semantic RNG;
- PottsToolkit authoring;
- normalized authoring IR;
- canonical checkpoint schema;
- semantic and execution fingerprints;
- result/evidence schema;
- each execution algorithm or scheduler.

```@example guarantees
using CorePotts

versions = scientific_contract_versions()
(versions.freeze_status, versions.rng, versions.checkpoint_schema)
```

These identities allow evidence and persisted state to say which semantics they refer to. A package
version alone is not precise enough.

## Algorithm guarantee profiles

`algorithm_guarantees(algorithm)` returns an `AlgorithmGuaranteeProfile` with:

- a guarantee label from `algorithm_guarantee_taxonomy()`;
- the exact qualified domain;
- maximum retained discrepancy where applicable;
- backends represented by applicable evidence;
- evidence version;
- API and paper-scope status.

Empty evidence fields mean that qualification has not been established. They must not be populated
from intended support, successful compilation, or a performance benchmark.

```@example guarantees
profile = algorithm_guarantees(SequentialCPM())
(
    profile.guarantee_label,
    profile.qualified_domain,
    profile.tested_backends,
    profile.evidence_version,
)
```

## Compatibility is not qualification

`compatibility_report` answers whether the selected model, algorithm, dimension, numerical policy,
and backend satisfy declared execution requirements. Its `qualified` Boolean is a preflight result,
not a statement of equilibrium, kinetic, cross-backend, or physical-time equivalence.

The `backend_contract` describes intended support. `tested_backends` records backends represented by
applicable retained evidence. Keep those claims separate in papers and reports.

## Current algorithm boundary

The production sequential and ordinary checkerboard APIs retain scientifically conservative
profiles. The checkerboard scheduler does not inherit the sequential transition kernel.
`LotteryCPM` is a limited later protocol consumer. `SequentialEquilibrium` and
`TiledCheckerboardCPM` are experimental and outside the frozen paper-core scope.

When results depend on ordering or stochastic scheduling, record the exact algorithm contract and
do not substitute another implementation under the same informal label.
