# Decision 0033: Generic Hierarchical Authoring for Complex Phase 14 Models

Status: Accepted policy; exact constructor spellings remain Provisional

Date: 2026-07-25

## Context

Decision 0031 simplified Phase 14 runtime meaning to one seven-area semantic kernel. The first
exact Wang authoring sketch nevertheless flattened roughly twenty state, process, relationship,
field, observation, and plan declarations into one `PottsModel(...)` call.

Those values are order-independent declaration varargs rather than conventional positional
parameters, but the distinction does not make the API readable. The spelling scales with private
implementation leaves and repeats many processes inside the plan. A paper-specific Wang builder
would conceal the problem rather than establish a general API capable of supporting more complex
Morpheus-style workflows.

The existing Phase 11 `ModelFragment` already supplies immutable composition, lexical namespaces,
roles, private declarations, and normalized flattening. Its current anonymous export tuple and
limited binding ergonomics are the missing boundary.

## Decision

`ModelFragment` is the one generic hierarchical authoring unit for complex PottsToolkit models.
Phase 14 will extend its composition contract with named typed requirements and named typed
exports. The exact Julia value names remain Provisional until the Wang vertical authoring fixture
and the independent Morpheus fixtures prove the spelling.

Flat `PottsModel(declarations...)` remains supported and is preferred for small models. It is not
the required spelling for complex coupled models and cannot be the only evidence for Phase 14
authoring quality.

### Named typed requirements

A fragment requirement identifies a semantic contract rather than an untyped symbol. Binding
validates the applicable category, owner domain, schema, units, lifecycle obligations,
capabilities, and backend requirements before canonical lowering.

### Named typed exports

A fragment export maps a stable local authoring name to an admitted declaration or operation.
Plans and other fragments may reference exports without accessing private fragment internals.
Export access resolves to canonical qualified identity during lowering and never exposes mutable
runtime storage.

### One global plan

Fragments export process operations; one root plan defines their global order, cadence, stages,
snapshots, lifecycle commit, observations, and stable boundaries. Fragments do not own independent
clocks or schedulers.

A convenience façade may expand to plan entries only when the expansion is complete, inspectable,
and merged into the same root plan. Dependencies validate explicit order but do not silently sort
scientific execution.

### One canonical lowering

Fragment hierarchy is authoring structure, not a second model IR. Lowering resolves bindings,
qualifies private identities, expands admitted conveniences, and produces the one canonical
state/process/plan/lifecycle/observation model from Decision 0031.

Valid fragment packaging and equivalent explicit leaf construction have the same scientific
fingerprint. Composition paths remain visible in provenance and diagnostics.

### Genericity boundary

No selected paper or author name may become a stable CorePotts or PottsToolkit constructor merely
to make one example concise. Paper-specific builders may exist in tutorial or paper-example
modules, but:

- their complete expansion is inspectable;
- they use only the same generic public composition API;
- the generic construction is documented first; and
- they do not count as generic API conformance evidence.

The core does not add category buckets, a `CoupledModel`, independent domain runtimes, or hidden
model-local schedulers.

### Backend boundary

Composition occurs on the host before launch. Backend requirements are derived transitively from
the fully lowered canonical model. A fragment cannot hide a host fallback, unsupported law,
transfer, synchronization, or allocation.

Every stable or release fragment capability remains subject to Decision 0032: sequential CPU
reference plus backend-resident Metal and ROCm implementation and qualification.

Decision 0034 later introduces `ProcessBigraphs.jl` as the domain-neutral runtime beneath migrated
models. `ModelFragment` remains PottsToolkit's generic biological authoring and composition
surface; it may lower to runtime composites without becoming a second runtime IR. The runtime does
not authorize paper-specific builders, hidden schedules, or dual Potts execution authority.

## Consequences

- Root-model complexity scales with meaningful subsystems rather than private leaf declarations.
- Complex workflows retain an explicit globally inspectable schedule.
- Fragments are reusable, substitutable, and independently testable across paper and Morpheus
  fixtures.
- Private implementation names do not pollute the model namespace.
- Domain-specific biological façades remain available without becoming runtimes.
- Phase 13 flat models and fingerprints remain unchanged.
- The Wang authoring sketch must be rewritten before G3 implementation uses it as an API target.

## Alternatives Considered

### Paper-specific constructors

Rejected as the general solution. They are acceptable only as example-layer conveniences.

### Keyword category buckets

Rejected. They rearrange the flat list without supplying hierarchy, ports, reuse, or substitution.

### New subsystem hierarchy

Rejected. `Subsystem`, `FieldSystem`, `CellSystem`, and similar composition authorities would
duplicate `ModelFragment` and risk independent runtimes.

### Kernel-only authoring

Rejected for ordinary use. Direct `StateSpec`/`ProcessSpec`/`PlanSpec` construction remains
available for extension and conformance work.

### Automatic plan inference

Rejected. A dependency graph cannot choose source-faithful scientific order.

## Required Conformance Evidence

- nested-fragment name qualification and private-access rejection;
- named requirement/export binding and mismatch truth tables;
- direct-leaf versus fragment-packaged canonical fingerprint identity;
- fragment substitution and dependency diagnostics;
- one-plan validation after convenience expansion;
- backend requirement propagation and preflight before mutation;
- no paper-specific stable exports;
- unchanged Phase 13 flat-model normalization and fingerprints;
- generic fragment-based Wang, CNV, and Morpheus lowering fixtures; and
- sequential CPU, real Metal, and real ROCm evidence for every stable execution capability reached
  through those fixtures.
