# [Execution model](@id execution-model)

One Monte Carlo step is a normalized scheduling unit. It is not automatically physical time.

## From declarations to execution

The normal path is:

1. PottsToolkit validates and normalizes declarations.
2. `PottsProblem` realizes the domain, layout, fields, capacity, seed, and time span.
3. Compatibility preflight compares model requirements, algorithm behavior, dimensionality, and
   backend capabilities.
4. CorePotts compiles logical values into backend storage and allocates bounded workspaces.
5. The selected algorithm performs proposal, evaluation, acceptance, commit, lifecycle, and
   observation phases under its own contract.

Compilation must not change the scientific model. `semantic_fingerprint` identifies the normalized
model; the execution fingerprint additionally captures execution-relevant choices.

## Proposal and commit

A copy attempt identifies donor and recipient owners through the declared proposal relation.
Scientific components contribute energy differences, nonconservative work, constraints, and
kinetic modifiers through typed protocols. The acceptance law combines those values. Accepted
changes update ownership and derived trackers through staged commit.

This separation is why a downstream component must declare:

- required properties and spatial relations;
- effects and capabilities;
- RNG streams;
- supported dimensions and backends;
- validation and conformance behavior.

## Algorithm identity matters

`SequentialCPM` orders and commits proposals sequentially. `CheckerboardSweepCPM` is graph-colored
and has a different schedule. `LotteryCPM` and the tiled implementation have their own contracts.
Sharing a Hamiltonian does not make their transition kernels equivalent.

Use `algorithm_guarantees(algorithm)` for the semantic/evidence profile and
`compatibility_report(problem, algorithm, backend)` for executability.

## Lifecycle

Lifecycle triggers are evaluated against a declared snapshot, conflicts are resolved by an explicit
policy, and effects commit at the registered phase. Division, type transition, shrink death, and
immediate removal have typed property policies. Capacity and generation-aware identity are part of
the contract.

## Failure boundary

A failed proposal or lifecycle phase must not expose partially committed logical state. Persistence
and observation occur at explicit settled boundaries. An external callback or visualization layer
must not mutate authoritative state behind those boundaries.
