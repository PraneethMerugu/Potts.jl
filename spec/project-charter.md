# Project Charter

Status: Accepted

## Mission

This repository develops a scientifically trustworthy, high-performance, and approachable
Cellular Potts modeling ecosystem for Julia.

The active package family has three responsibilities:

1. PottsToolkit is the primary biological and symbolic authoring interface.
2. CorePotts is the independently usable scientific execution engine and extension boundary.
3. MakiePotts converts explicit host-owned observations into visualization recipes.

The ecosystem must remain architecturally hardware agnostic. Stable scientific features target
CPU execution and explicitly qualified accelerator backends. Backend availability must never
silently change model semantics.

Stable Potts scientific features must support both two- and three-dimensional models unless an
accepted capability row and user-facing contract explicitly documents a narrower dimensional
scope. Dimensionality and topology are capability dimensions, not implicit backend facts.

## Primary user experience

PottsToolkit acts as a high-level declarative language and model compiler for CorePotts. It should
allow computational biologists, statistical physicists, HPC researchers, and Julia developers to
express models without depending on CorePotts internals.

Advanced users may extend or use CorePotts directly through its public protocols. PottsToolkit
must not duplicate the numerical engine or make private storage part of its authoring contract.

## Core engine

CorePotts defines the scientific execution contracts, fundamental state model, reference engine,
optimized algorithms, checkpoints, observations, and backend extension interfaces. It must remain
usable independently of PottsToolkit and visualization packages.

Optimized execution is judged against explicit scientific contracts. Performance improvements
must not silently redefine model behavior.

## ModelingToolkit and SciML integration

PottsToolkit owns ModelingToolkit-facing symbolic completion and compilation. CorePotts execution
is exposed through genuine SciML problem, algorithm, integrator, solution, remake, checkpoint, and
ensemble conventions where applicable.

`complete` and `mtkcompile` are structural operations on `PottsSystem`; numerical engine, backend,
scalar, and device specialization occurs during problem materialization, `init`, or `solve`.
External ModelingToolkit systems remain native component islands with explicit scope, IO, cadence,
and coupling policies. They are not copied field by field into a Potts surrogate.

The completed integer MCS remains the master CPM clock and lifecycle boundary. Native component
time is related through an explicit duration-per-MCS map and named split policy. Integration must
use public package interfaces. Lattice sites and stochastic copy attempts are not misrepresented
as ordinary ODE unknowns merely to obtain superficial API compatibility, and CorePotts remains free
of MTK dependencies.

## Algorithms and scientific guarantees

Reference and approximate algorithms must be separately identified and must report their kinetic,
equilibrium, attempt-normalization, reproducibility, topology, precision, and backend guarantees.

The unqualified word “exact” is not a technical guarantee. Documentation must state the specific
property being claimed. All user-visible algorithms use comparable normalized Monte Carlo step
units.

Auxiliary constraint and fluctuating mechanical-state components remain a defining project
capability. They participate through the same component, capability, backend, semantic-randomness,
checkpoint, and lifecycle contracts as other scientific families. Equilibrium auxiliary
constraints and nonequilibrium fluctuating-pressure or fluctuating-tension mechanics are separately
named and qualified; a historical name or superficial storage resemblance cannot imply an
equilibrium claim.

## Performance and portability

The project aims to be among the fastest Cellular Potts implementations while remaining
scientifically auditable. Performance claims require reproducible benchmarks.

Hardware portability requires more than successful compilation. Each supported backend needs a
capability policy, conformance tests, numerical expectations, and measured execution evidence.
Backend-specific code may optimize a shared semantic operation but cannot define that operation.

## Compatibility and release goal

The immediate target is a paper-quality research release. There are no external API compatibility
requirements for the current pre-1.0 redesign. Breaking changes are permitted when they materially
improve scientific correctness, API cohesion, execution portability, extensibility, or
maintainability.

External orchestration is not an active product responsibility. A future adapter must be proposed
and reviewed independently and cannot become a prerequisite for PottsToolkit or CorePotts.

## Semantic naming and direct cutovers

Development chronology is never product semantics. Phase, gate, migration,
provisional, and generation labels may organize specifications, design history,
reviews, and development work, but live product code must use durable
scientific, mathematical, numerical, hardware, protocol, ownership, or
execution terminology.

When a temporary product name or representation is replaced, the replacement
is one direct cutover across implementation, tests, current documentation,
examples, configuration, serialization boundaries, extensions, and downstream
consumers. The old name or representation is deleted in the same change. The
repository does not retain forwarding aliases, deprecations, feature flags,
old/new selectors, compatibility states, or parallel production paths whose
only purpose is migration between development milestones.

This rule does not remove genuine features. Scientific phases, mathematical
candidates, distinct algorithms, backend implementations of one shared law,
checkpoint and importer semantics, test-only independent oracles, package
versions, and durable wire or schema versions remain when their distinction can
be explained without reference to development history. A word is not banned by
spelling; its semantic ownership determines whether it belongs in the product.

## Quality principles

- Scientific semantics precede optimization.
- The sequential reference engine is the executable scientific baseline.
- Public APIs require documentation, validation, and extension examples.
- State mutations require explicit ownership and invariants.
- Semantic duplication is eliminated.
- Hardware specialization is documented rather than hidden.
- Tests validate laws and observable behavior rather than incidental layouts.
- Current behavior, intended behavior, and compatibility behavior are documented separately.
- Development milestones never become product identities or runtime modes.

## Development workflow

Development uses the ordinary Julia package workflow: focused and complete
tests, integration tests, documentation builds, applicable GPU tests, and
reproducible benchmarks proportional to the change. There are no evidence
hashes, milestone scripts, frozen pass/fail timing gates, or committee
paperwork.

Technical review may challenge semantics, architecture, performance, and
maintainability, but it does not create a second qualification system.
Benchmarks remain required to substantiate performance claims and useful for
detecting regressions; machine-dependent wall-clock observations inform
engineering rather than acting as brittle development thresholds. Historical
specifications, audits, and evidence remain records of earlier repository
states and do not override this active workflow.
