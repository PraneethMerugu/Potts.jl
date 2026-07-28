# Potts.jl

Potts.jl is a Cellular Potts modeling system for building biological models, running them on an
explicit execution algorithm, and retaining enough provenance to interpret or reproduce the
result.

The package family separates three responsibilities:

| Package | Use it for |
|:--|:--|
| `PottsToolkit` | Biological identities, constraints, fields, lifecycle, layouts, observations, and reusable models |
| `CorePotts` | Execution algorithms, scientific state, backends, persistence, and extension protocols |
| `MakiePotts` | Visualization of explicit host observations through native Makie recipes |

This manual targets Julia 1.12.6 and the implementation on the current development branch.

## Choose a path

- **New to the package:** [install and verify Potts.jl](@ref install-and-verify), then run the
  [first simulation](@ref first-simulation).
- **Building a study:** follow [Compose a biological model](@ref build-model),
  [Algorithms and guarantees](@ref algorithms-and-guarantees), and
  [Observe and analyze](@ref observe-and-analyze).
- **Looking for working programs:** start in the [Example gallery](@ref example-gallery).
- **Evaluating a scientific claim:** read [Scientific guarantees](@ref scientific-guarantees)
  before comparing algorithms or backends.
- **Extending the engine:** begin with [Architecture](@ref architecture) and the
  [Extension author reference](@ref extension-author-reference).
- **Upgrading or diagnosing a failure:** use the
  [Version and migration guide](@ref version-and-migration),
  [Glossary](@ref glossary), and [Troubleshooting](@ref troubleshooting).

## Support boundary

`SequentialCPM` and `CheckerboardSweepCPM` are distinct algorithms with distinct guarantee
profiles. Backend compatibility and scientific qualification are also separate claims. Always
inspect `backend_report` or `compatibility_report` together with `algorithm_guarantees` for the
exact model, algorithm, and backend you intend to use.

ProcessBigraphs is an internal runtime foundation. Phase 16 develops dynamic hierarchy,
structural transactions, and the first Potts adapter slices in a separate workstream. This manual
does not present unfinished Phase 16 behavior as part of the supported Potts path; see
[Runtime and Phase 16 boundary](@ref runtime-boundary).
