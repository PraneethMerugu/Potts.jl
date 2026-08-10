# Unresolved Semantic Questions

Status: Under Investigation

Current disposition: historical registry under G5H revalidation. Only an item explicitly admitted
by the [G5H Hardening Contract](symbolic-potts-v1-hardening.md) or a later accepted decision may
drive current implementation. References to `PottsModel`, `ModelFragment`, Lottery, old phase
ordering, or earlier capability claims are not active requirements.

This registry prevents open questions from being silently resolved by implementation convenience.
Identifiers remain stable when a question is moved into an accepted specification or decision
record.

## Randomness and Reproducibility

Public seed ownership, named semantic streams, scheduling-independent draws, distribution contracts,
checkpoint requirements, and cross-backend raw-stream guarantees are accepted in
[Randomness and Reproducibility](randomness-and-reproducibility.md).

### SEM-RNG-004: Algorithm trajectory-reproducibility profiles

Classify each algorithm by whether identical trajectories are guaranteed across workgroup sizes,
device models within one backend family, deterministic optimization changes, and package versions.
This classification must account for reductions, atomics, floating-point modes, and state races in
addition to random-number generation.

### SEM-RNG-005: Portable distribution transforms

Select and validate the exact normal, Poisson, permutation, bounded-integer, and categorical
transforms. Specify which transforms are bitwise portable and which are only statistically portable.

### SEM-RNG-006: Default generator implementation

Resolved by `Philox4x32x10V1`, current RNG contract version `1.2.0`, and lowering identity
`philox4x32x10_semantic_address_fisher_yates_v1`. Known-answer vectors, semantic-address packing,
compilation, raw-word identity, and the checkerboard color-permutation lowering are qualified only
for the backend/environment conjunctions admitted by the current CorePotts capability matrix. CUDA
remains outside the current first-class backend contract and does not block the accepted default.

## Energy, Proposals, and Trackers

The neighbor-site proposal ratio, conventional and Metropolis-Hastings acceptance, zero-temperature
limits, component taxonomy, local/global energy law, and tracker transaction are accepted in
[Energy, Proposals, Acceptance, and Trackers](energy-proposals-and-trackers.md).

### SEM-ENG-004: Symmetric distinct-neighbor proposal

Derive the exact selection probability, reverse-support conditions, extinction behavior, and
connectivity requirements for a proposal that samples distinct neighboring owner identities.

### SEM-COMP-001: Cross-simulator conversion registry

Validate versioned CC3D, Morpheus, and Artistoo parameter conversions, acceptance variants,
neighborhood conventions, and fixture corpora before advertising compatibility presets.

## Auxiliary-State Semantics

The accepted category, naming, state ownership, normalized-time, RNG, backend, and lifecycle
architecture is defined in [Auxiliary Constraints and Mechanical State](auxiliary-state-semantics.md).
The historical `HST...Penalty` names and implementations are not normative.

### SEM-HST-001: Augmented Hamiltonian

Resolved by [Auxiliary Constraints and Mechanical State](auxiliary-state-semantics.md). The
historical real `HST...Penalty` law is not a valid Gibbs augmentation: its conditional-mean and copy-
work signs cannot arise from one real joint density, while the genuine positive-quadratic Gaussian
identity has an imaginary linear coupling. Stable equilibrium support therefore remains the exact
classical quadratic Hamiltonian. Stable stateful support is separately named fluctuating volume-
pressure and surface-tension mechanics with no marginal-equivalence or detailed-balance claim.

### SEM-HST-002: MCS integration

Resolved for stable volume and surface mechanics by
[Auxiliary Constraints and Mechanical State](auxiliary-state-semantics.md). The accepted law is the
exact frozen-observable OU transition under symmetric composition. Algorithm sub-round intervals sum
to one MCS: sequential `1`, checkerboard realized color fractions, and lottery `1 / (Delta + 1)`.
Backend and statistical qualification remain conformance work rather than open semantics.

### SEM-HST-003: Lifecycle distributions

Resolved for the stable fluctuating volume-pressure and surface-tension families by
[Auxiliary Constraints and Mechanical State](auxiliary-state-semantics.md) and Decision 0023.
Constitutive reset is the default division policy; intensive preservation and independent stationary
redraw are explicit alternatives. Transition continuity, death clearing, and generation-safe reuse
are specified. Dynamic link lifecycle remains deferred with the experimental focal family.

## Topology

### SEM-TOP-001: Neighborhood purposes

Resolved by [Topology and Spatial Relations](topology-and-spatial-relations.md): lattice geometry,
domain, proposal, energy, surface, connectivity, spatial-query, field, and conflict relations are
separate semantic roles.

### SEM-TOP-002: Offset ordering and weights

Resolved in part by [Topology and Spatial Relations](topology-and-spatial-relations.md): explicit
stencils, distance-shell constructors, canonical direction ordering, relation-specific weights,
periodic displacement, and alias rejection are accepted. Numerical quadrature choices remain under
`SEM-TOP-004`.

### SEM-TOP-003: Custom topology interface

Resolved in part by [Topology and Spatial Relations](topology-and-spatial-relations.md): custom
regular stencils and explicit graph lattices are separate compiled families with common relation
laws. Detailed graph capabilities remain under `SEM-TOP-007`.

### SEM-TOP-004: Surface quadrature and isotropy presets

Resolved semantically by
[Cartesian Surface, Queries, and Fields](cartesian-surface-queries-and-fields.md): raw, weighted,
normalized-kernel, and physical measures are separate; the literature-backed normalized-kernel
family is the native reference; Crofton estimators remain Experimental. Exact calibration tables
and anisotropy results are required conformance evidence rather than open semantics.

### SEM-TOP-005: Obstacles and exterior ownership

Resolved for the paper Cartesian engine by
[Cartesian Surface, Queries, and Fields](cartesian-surface-queries-and-fields.md). Arbitrary custom
boundaries remain Deferred.

### SEM-TOP-006: Hexagonal geometry

Define canonical 2D hexagonal and 3D rhombic-dodecahedral coordinates, boundaries, site measures,
distance shells, direction IDs, and compatibility conversions.

### SEM-TOP-007: Irregular and graph lattices

Define graph construction, embedding, edge measures, proposal probabilities, boundary meaning,
device representation, and statistical conformance for experimental graph-lattice CPMs.

### SEM-TOP-008: Spatial-query relations

Resolved for the core query vocabulary by
[Cartesian Surface, Queries, and Fields](cartesian-surface-queries-and-fields.md). Additional query
operators require their own explicit aggregation semantics.

### SEM-TOP-009: Field-discretization relations

Resolved for field identity, geometry, sampling, boundary independence, and immutable transaction
snapshots by [Cartesian Surface, Queries, and Fields](cartesian-surface-queries-and-fields.md).
Operator splitting, secretion, uptake, and PDE substeps remain unresolved for the general case. A
selected Phase 14 published model promotes only its required subset through the source audit,
single-kernel semantics, sequential CPU reference, backend-resident Metal/ROCm qualification, and
conformance process in Decisions 0029, 0031, and 0032.

## Algorithms

### SEM-ALG-001: Checkerboard equilibrium guarantee

The accepted `CheckerboardSweepCPM` process schedules every mutable site once without replacement in
randomized color order and does not claim sequential kinetics. Determine whether any equilibrium
variant preserves its intended invariant distribution in the presence of shared cell-wide state.

### SEM-ALG-002: Lottery equilibrium and kinetic guarantee

The accepted `LotteryCPM` clock gives every mutable site one activated opportunity in expectation
from a static topology-qualified schedule; activated dynamic-conflict losers consume their attempt.
Derive or statistically characterize the resulting equilibrium status, waiting-time law, spatial
correlations, and kinetics.

### SEM-ALG-003: Intrinsic implementation equivalence

Determine the exact operation implemented by subgroup reductions and establish equivalence to a
named generic algorithm before making scientific claims.

## PottsToolkit Rule Language

### SEM-DSL-001: Rule snapshot behavior

Resolved by
[PottsToolkit Rule and Model Semantics](pottstoolkit-rule-and-model-semantics.md): all outputs in one
rule phase read one snapshot and commit simultaneously after successful validation.

### SEM-DSL-002: Supported language subset

Resolved by the accepted Julia-first Level 1 language in
[PottsToolkit Rule and Model Semantics](pottstoolkit-rule-and-model-semantics.md). Rules use thin
`@rule`/`@rules` syntax over ordinary builders, callable typed references, Julia conditionals and
local expressions, explicit interpolation, declarative `draw`, lazy query reductions, and no general
dynamic loops or collections. The exact registered method list is maintained as a release inventory.

### SEM-DSL-003: Spatial query definitions

Resolved for the core vocabulary by
[Cartesian Surface, Queries, and Fields](cartesian-surface-queries-and-fields.md) and incorporated
into [PottsToolkit Rule and Model Semantics](pottstoolkit-rule-and-model-semantics.md).

### SEM-DSL-004: Extension and escape-hatch contract

Resolved by Decisions
[0017](decisions/0017-open-protocol-extensibility.md) and
[0026](decisions/0026-phase-10-typed-api-and-compiler.md): Level 2 and Level 3 extensions use ordinary
Julia dispatch and public protocols; registration is required only for Level 1 spelling, durable
semantic serialization, or compatibility aliases. Components declare effects, requirements,
reference behavior, and backend capabilities before portable lowering.

### SEM-DSL-005: Compilation cache identity

Resolved by
[Decision 0026](decisions/0026-phase-10-typed-api-and-compiler.md): semantic fingerprints cover
normalized scientific meaning, execution fingerprints add algorithm/backend/numerical/RNG and
relevant code identities, and checkpoint identity additionally records state and time. Source
paths, declaration order, object identity, and unstable object-memory hashing are excluded.

### SEM-DSL-006: Authoring and composition architecture

Resolved by
[PottsToolkit Authoring, Composition, and API Semantics](pottstoolkit-authoring-composition-and-api-semantics.md):
macros are optional sugar over a complete programmatic interface; models are immutable; declarations
are order-independent outside explicit phases; fragments are namespaced and composable; validation
is staged; inspection and semantic manifests are required; reconstructable serialization is
opt-in; and DSL/IR versions are independent of package versions. PottsToolkit DSL and typed
authoring forms share normalized semantic IR;
CorePotts remains an independently usable, first-class scientific and execution API governed by the
same scientific contracts rather than forced through PottsToolkit IR.

### SEM-DSL-007: Exact surface syntax and usability contract

Resolved by the accepted Level 1 surface in
[PottsToolkit Authoring, Composition, and API Semantics](pottstoolkit-authoring-composition-and-api-semantics.md)
and [PottsToolkit Rule and Model Semantics](pottstoolkit-rule-and-model-semantics.md). The contract
defines top-level declarations, typed properties and parameters, fields, pairwise laws, model and
problem construction, rule/trigger/query/random-draw syntax, explicit phases, fragments and roles,
inspection, diagnostics, observables, optional units, persistence, and editor independence.

Breaking changes remain allowed during Phase 11 implementation. DSL/IR 1.0 freezes only after the
accepted reference-model, backend, custom-extension, documentation, legacy-deletion, usability, and
performance evidence gate passes.

## CorePotts Public Interfaces

### SEM-API-001: Scientific and execution extension protocols

Resolved by
[CorePotts Public Scientific and Execution Interfaces](corepotts-public-interface-semantics.md).
CorePotts uses meaningful scientific categories, immutable structs, ordinary public functions,
multiple dispatch, typed requirements and capabilities, stable state accessors, reference behavior,
package extensions, centralized workspaces, preflight validation, and category conformance helpers.
Direct CorePotts use is first-class and does not require PottsToolkit authoring IR.

## SciML Integration

### SEM-SCI-001: Supported SciMLBase contract

Resolved by
[SciML Problem, Integrator, Solution, and Ensemble Semantics](sciml-interface-semantics.md):
Potts problems and solutions participate in SciMLBase; `solve` is behaviorally `solve!(init(...))`;
public stepping uses integer MCS; `remake`, callbacks, saving, return codes, and ensembles follow the
accepted Potts-specific SciML contract.

### SEM-SCI-002: Observation synchronization

Resolved by
[SciML Problem, Integrator, Solution, and Ensemble Semantics](sciml-interface-semantics.md): host
callbacks and observations synchronize only at declared MCS boundaries when their requested data
requires materialization; qualified device observations may remain resident; displays never trigger
hidden synchronization.

## Persistence and Initialization

### SEM-IO-001: Snapshot versus checkpoint

Resolved by [Snapshots, Checkpoints, Restore, and Logical Storage](persistence.md): stable capture is
limited to finalized MCS boundaries; snapshots and exact checkpoints are distinct immutable values;
compatible resume and explicit logical import have separate guarantee semantics.

### SEM-IO-002: Storage equivalence

Resolved by [Snapshots, Checkpoints, Restore, and Logical Storage](persistence.md): memory, HDF5, and
Zarr implement one versioned canonical logical schema and share conformance evidence through package
extensions.

### SEM-INIT-001: Coordinate and rasterization semantics

Resolved by [State Model](state-model.md), Decisions 0021 and 0024, the accepted Cartesian coordinate
contract, and [Auxiliary Constraints and Mechanical State](auxiliary-state-semantics.md). Layouts emit
semantic claims; uniform site seeding and sequential rejection are separately named; periodic shapes
use minimum-image rasterization with self-alias rejection; property and auxiliary initialization
occur only after canonical ownership finalization.

## Numerical and Backend Semantics

### SEM-NUM-001: Precision policy

Resolved by
[Numerical and Cross-Backend Semantics](numerical-and-cross-backend-semantics.md): generic Julia
source lowers to concrete compiled types; the visible portable default is `Float32`; explicit wider
precision is preserved or rejected; storage, accumulation, integer widths, overflow, mixed precision,
and conversions are governed by a typed numerical policy.

### SEM-NUM-002: Cross-backend conformance

Resolved by
[Numerical and Cross-Backend Semantics](numerical-and-cross-backend-semantics.md): exact integers,
raw RNG output, semantic IDs, schedules, and canonical topology data match bit-for-bit; floating
state follows per-quantity numerical, invariant, trajectory, or statistical contracts; every
release backend runs the same visible conformance matrix.

### SEM-NUM-003: Reduction ordering

Resolved by
[Numerical and Cross-Backend Semantics](numerical-and-cross-backend-semantics.md): every reduction
defines types, initial and neutral values, empty behavior, algebraic requirements, and ordering;
deterministic state-affecting reductions fix the contracted grouping independently of workgroup
decomposition; schedule-dependent floating atomics are excluded from strict paths.
