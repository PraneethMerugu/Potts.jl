# Phase 14 Spatial Roles and Source Attempt Semantics

Status: Superseded by Decision 0031; retained as historical design and prototype evidence

GPU promotion note: Decision 0032 supersedes any CPU-only or optional-GPU promotion language in
this historical document; stable Phase 14 execution requires qualified Metal and ROCm paths.

Implementation maturity: Specified only

Date: 2026-07-24

Authority note: The focused spatial-role and algorithm requirements are preserved in the
`spatial-roles` and `potts-algorithm-identities` contracts of the
[Phase 14 Single Semantic Kernel](phase-14-semantic-kernel.md).

## Purpose

This document defines the additive authoring and algorithm contracts needed to reproduce published
models whose scientific neighborhoods or copy-attempt budgets differ from PottsToolkit's current
defaults. It specializes, but does not alter, the accepted
[Topology and Spatial Relations](topology-and-spatial-relations.md),
[Time and Monte Carlo Steps](time-and-mcs.md), and
[Randomness and Reproducibility](randomness-and-reproducibility.md) contracts.

Two invariants are absolute:

1. omitting every Phase 14 declaration lowers exactly as it did at the Phase 13 freeze; and
2. `SequentialCPM` version 1 continues to mean exactly `N` independent attempts per MCS.

## Explicit Spatial Roles

### Public declaration

PottsToolkit Level 2 gains one immutable aggregate:

```julia
SpatialRoles(;
    proposal,
    contact,
    surface,
    connectivity,
    query,
    field,
)
```

`conflict` is deliberately absent from the ordinary authoring constructor. The compiler derives an
algorithm-specific conservative conflict relation from complete read/write footprints. An expert
extension MAY provide a proven conflict relation through the existing CorePotts protocol, but it is
validated as an execution claim and never changes proposal, contact, surface, connectivity, query,
or field meaning.

Each value is a role-typed relation accepted by CorePotts. The same immutable relation MAY occupy
several roles, but every role remains present in the normalized model and manifest. A component may
override its model-level role only through an already accepted component-specific relation field.

### Defaults and partial declarations

For backward compatibility:

- no `SpatialRoles` declaration produces the exact existing first-shell lowering;
- a partial declaration replaces only the named roles;
- an omitted role receives the same default it would have received before Phase 14; and
- declaration order does not affect semantic identity.

There is no cascade such as “contact implies query” or “proposal implies surface.” Presets expand
into a complete role record before normalization. A preset version and the expanded descriptors are
both reported.

`connectivity = nothing` is distinct from omission: it explicitly disables an optional
connectivity constraint when the surrounding component permits that choice. Similar sentinel values
are accepted only where the existing role protocol defines them.

### Normalization and fingerprint

Normalization records for each role:

- role identity;
- relation type and contract version;
- dimension and directedness;
- canonical direction IDs, offsets, weights, and physical embedding;
- boundary realization and obstacle treatment;
- metric or discretization identity where applicable; and
- extension semantic identity.

Logically unordered direction sets are canonicalized by canonical direction identity. Order is
retained only when the relation contract gives order scientific meaning. Normalization rejects:

- dimensional mismatch;
- a directed relation used by a symmetric-only consumer;
- missing weights required by a metric;
- an invalid connectivity foreground/background pair;
- a field operator incompatible with the field placement or boundary; and
- a relation unavailable on the selected backend.

The model fingerprint includes the expanded role record. A model using omitted Phase 14 declarations
MUST retain its Phase 13 fingerprint byte for byte; the normalizer therefore uses the existing
legacy normalized representation for that case rather than inserting a new default-valued wrapper.

### Inspection

The compiled model report exposes:

```julia
spatial_roles(compiled)
relation_for(compiled, ProposalRole())
relation_for(compiled, ContactRole())
relation_for(compiled, SurfaceRole())
relation_for(compiled, ConnectivityRole())
relation_for(compiled, SpatialQueryRole())
relation_for(compiled, FieldDiscretizationRole())
conflict_relation(compiled, algorithm)
```

The first six are scientific model structure. The last is an algorithm-specific compiled execution
artifact with its derivation report. Paper manifests store all expanded scientific roles and the
realized conflict-relation identity used by the executed algorithm.

## Source-Specific Attempt Budgets

### Separate algorithm identity

The new CPU reference algorithm is:

```julia
BudgetedSequentialCPM(
    budget = AttemptsPerSite(16);
    proposal = SequentialReference(),
)
```

`AttemptsPerSite(k)` requires a positive integer `k`. For a realized domain with `N` mutable
recipient sites, one public MCS performs exactly `k*N` sequential copy attempts with replacement.
Each attempt observes all earlier committed attempts in the same MCS. Same-owner, invalid-boundary,
constraint-rejected, acceptance-rejected, and accepted attempts consume the budget exactly as in
`SequentialCPM`.

The initial stable contract supports only integer multipliers. Absolute counts, floating
multipliers, state-dependent budgets, and acceptance-dependent replacement work are outside this
contract because they either cease to scale with the realized domain or change time as the state
evolves.

`AttemptsPerSite(1)` is scientifically equivalent to the v1 `SequentialCPM` proposal process but
retains the new algorithm identity. Implementations MUST NOT silently rewrite one identity to the
other, because fingerprints, provenance, and source claims name the selected contract.

### MCS and observation meaning

For this algorithm one MCS is the source-defined compound step of `k*N` attempts. Public time remains
an integer MCS:

- `step!` performs the whole compound step;
- schedules at target MCS `m` run once, not once per `N`-attempt block;
- lifecycle and observation phases occur after all `k*N` attempts;
- a `ContinuousClock` interval associated with one MCS spans the entire compound step; and
- reports expose both public MCS and exact attempt counts.

This meaning is appropriate only when a source model defines its reported step using that budget.
It MUST NOT be described as kinetic equivalence to the `N`-attempt reference clock. Comparisons that
want reference-MCS units explicitly rescale by `k` in analysis and retain the original source clock
in provenance.

### RNG addressing

Attempt `a`, where `1 <= a <= k*N`, uses the existing sequential proposal stream family with the new
algorithm component identity and semantic attempt coordinate `a`. Addressing is a pure function of:

```text
(master seed, RNG contract version, algorithm identity,
 target MCS, attempt index, operation label, draw index)
```

The implementation MUST NOT nest `k` ordinary calls to `step!`, reuse attempt indices `1:N` in each
block, or derive streams from kernel launches. `AttemptsPerSite(1)` and `SequentialCPM` may therefore
produce different raw bits unless an explicit comparison fixture requests a mapped stream; their
separate identity is intentional.

There is no stable partial-MCS checkpoint. The current attempt index is execution workspace and a
failure before attempt `k*N` leaves the target MCS incomplete and the integrator terminal under the
coupled execution failure contract.

### Guarantee profile

The guarantee profile states:

- sequential current-state transaction semantics;
- uniform recipient sampling with replacement;
- the proposal relation and invalid-direction law;
- exact budget `k*N`;
- no claim of kinetic equivalence to `SequentialCPM` when `k != 1`;
- the applicable equilibrium claim of the selected acceptance law;
- strict CPU trajectory reproducibility under its continuation profile; and
- Metal and ROCm unsupported for the initial version.

The semantic fingerprint covers multiplier, proposal law, acceptance law, numerical policy, RNG
contract, and algorithm contract version. The execution fingerprint additionally covers CPU
execution identity and dependencies required by exact continuation.

## Source Mapping

The model source record, not a library default, chooses an attempt budget:

- Graner--Glazier 1992 uses `AttemptsPerSite(16)` if the audited 16N statement governs the continuing
  trajectory;
- every other paper uses its transcribed source budget;
- an unknown source budget remains a registered source ambiguity and blocks a close-reproduction
  claim; and
- absence of source evidence never defaults to 16N.

Paper assemblies MUST state both the source wording and the library interpretation. Observation-only
annealing or minimization uses `ObservationTransform`, not `BudgetedSequentialCPM`, unless it mutates
the continuing source trajectory.

## Backend and Failure Semantics

Explicit spatial roles follow per-relation backend qualification. Preflight reports the exact
unsupported role and consumer. It does not substitute a smaller stencil.

`BudgetedSequentialCPM` is initially a CPU-only scientific oracle. Requesting Metal or ROCm fails
before allocation or stepping. Integer overflow in `k*N`, a zero mutable-site domain, unsupported
proposal law, or incomplete semantic RNG namespace fails during problem construction.

## Required Conformance Evidence

### Spatial roles

- default-omission fingerprint and normalized-byte identity against Phase 13;
- partial and complete Level 2 lowering in 2D and 3D;
- canonical direction and declaration-order invariance;
- independent proposal/contact/surface/query fixtures;
- foreground/background connectivity fixtures;
- field-discretization compatibility fixtures;
- conflict derivation from extended component footprints; and
- manifest and compiled-report round trips.

### Attempt budgets

- exact `N`, `2N`, and `16N` disposition partitions over hand-worked domains;
- invalid-boundary and same-owner budget consumption;
- addressed-draw fixtures across Julia process and thread configurations;
- uninterrupted versus coupled-checkpoint continuation;
- observation, lifecycle, staged-protocol, and continuous-clock boundaries;
- explicit rejection on Metal and ROCm; and
- a Graner--Glazier source microfixture after the source-order audit closes.

## Acceptance Boundary

This contract may become accepted only after D10 records that the new algorithm identity is
additive and that `SequentialCPM` v1 remains frozen. Source-specific paper qualification is separate:
the reusable contract can be accepted while a paper remains blocked by an unknown neighborhood or
attempt-budget interpretation.
