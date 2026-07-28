# [Algorithms and guarantees](@id algorithms-and-guarantees)

The algorithm is part of the scientific run definition. Algorithms that share energies do not
therefore share proposal distributions, transaction semantics, kinetics, or evidence.

## Inspect before running

```@example algorithms-and-guarantees
algorithms = include(joinpath(
    ENV["POTTS_DOCS_ROOT"], "models", "tutorials",
    "algorithms_and_guarantees.jl"))
algorithms.guarantee_labels
```

The canonical source compares `SequentialCPM` with `CheckerboardSweepCPM` and asserts that their
proposal processes differ. Both can pass compatibility preflight while retaining different
scientific interpretations.

## Current algorithm families

| Algorithm | Intended interpretation | Status |
|:--|:--|:--|
| `SequentialCPM` | Conventional ``N`` ordered attempts per MCS | Stable |
| `BudgetedSequentialCPM` | Explicit integer attempts-per-site budget | Stable source-budgeted path |
| `CheckerboardSweepCPM` | Graph-colored snapshot/commit schedule | Stable, distinct semantics |
| `LotteryCPM` | Topology-calibrated parallel lottery | Limited |
| `SequentialEquilibrium` | Metropolis-Hastings equilibrium path | Experimental |
| `TiledCheckerboardCPM` | Tiled device scheduler | Experimental |

Consult `algorithm_guarantees(algorithm)` for the machine-readable profile. `api_status` describes
support; `guarantee_label`, `qualified_domain`, `tested_backends`, and `evidence_version` describe
scientific evidence.

## Compatibility is narrower than qualification

`backend_report(problem, algorithm)` answers whether the declared combination can execute under
the backend contract. It does not establish equilibrium, kinetics, physical-time calibration, or
cross-backend agreement.

Never replace an algorithm, precision, boundary, or unsupported component solely to make preflight
pass. Change the run definition deliberately and record it.
