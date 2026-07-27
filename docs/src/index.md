# Potts.jl

Potts.jl is a Cellular Potts modeling system built around two paper-core packages and one
Makie-native visualization extension:

- `PottsToolkit` is the biological authoring interface.
- `CorePotts` is the scientific execution and extension interface.
- `MakiePotts` converts explicit host observations into composable Makie recipes.

The current development and evidence target is Julia 1.12.6.

## Phase 13 evidence boundary

`SequentialCPM` implements the declared conventional sequential process.
`CheckerboardSweepCPM` is a distinct graph-colored scheduler: it is characterized explicitly and
does not inherit sequential kinetic, equilibrium, or stationary-distribution claims.
Use [`CorePotts.algorithm_guarantees`](@ref) and
[`CorePotts.scientific_contract_versions`](@ref) to inspect the
machine-readable status attached to an algorithm and the versions embedded in evidence.

Backend execution support and scientific qualification are separate claims. A successful
compatibility preflight does not imply that a backend is represented by the current Phase 13
evidence archive.

## Scope

Lottery and tiled checkerboard algorithms are later protocol consumers and are not part of the
initial Phase 13 paper-core qualification matrix. The Phase 14 model-driven manual, published-model
portfolio and any redesigned neural-model satellite are not part of this API-freeze documentation.
MakiePotts v0.2 is documented separately because its render-frame boundary never weakens the
frozen execution and observation contracts.

Start with [Getting Started](@ref), then consult the
[scientific contract identities and algorithm guarantees](@ref scientific-contract-identities).
