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
study = include(joinpath(
    ENV["POTTS_DOCS_ROOT"], "models", "tutorials",
    "research_workflow.jl"))
(length(study.solutions.u), study.seeds,
    study.contracts.freeze_status)
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
