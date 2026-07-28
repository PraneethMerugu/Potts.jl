# [Architecture](@id architecture)

Potts.jl separates authoring, execution, observation, and presentation so that each scientific
claim has one owner.

```text
PottsToolkit declarations
        │ normalize / validate / lower
        ▼
CorePotts problem + algorithm
        │ preflight / compile / execute
        ▼
logical state ── explicit snapshot policy ──► host observations
                                                  │
                                                  ▼
                                      analysis or MakiePotts
```

## PottsToolkit

PottsToolkit owns biological names and composition:

- model identities, parameters, properties, and pairwise laws;
- energies, constraints, drives, fields, lifecycle, and rules;
- domains and initial layouts;
- validation, lowering, fingerprints, manifests, and reference models;
- typed scientific observation requests.

Its output is declarative. It does not own an execution scheduler or backend storage.

## CorePotts

CorePotts owns the scientific engine:

- logical state and invariants;
- proposal, acceptance, energy, drive, constraint, and tracker protocols;
- sequential, checkerboard, lottery, and experimental tiled algorithms;
- semantic RNG addressing;
- backend capability preflight and compiled storage;
- lifecycle commit, observation boundaries, checkpoints, and SciML-facing solve integration.

The logical state is the semantic authority. Compiled arrays and device storage are execution
representations, not an alternate model.

## MakiePotts

MakiePotts owns visualization-neutral render-frame conversion and native Makie recipes. It consumes
explicit host data and never changes scheduling, synchronization, observation cadence, or random
streams.

## ProcessBigraphs

ProcessBigraphs is an independently testable internal runtime package. Phase 15 established its
serial, fixed-structure runtime foundation. Phase 16 adds dynamic structure and begins bounded
adapter cutover. Until a slice passes its cutover gate, CorePotts remains the authority for that
Potts behavior.

See [Runtime and Phase 16 boundary](@ref runtime-boundary) for the documentation rule during this
transition.
