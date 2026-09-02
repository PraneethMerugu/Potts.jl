# State Model

Status: Accepted

## Abstract State

A Potts simulation state contains at least:

```text
S = (L, C, M, A, F, G, P, D)
```

where:

- `L` maps every lattice site to a finite cell or medium domain.
- `C` stores finite-cell biological properties.
- `M` stores medium-type behavior and finite-domain occupancy.
- `A` identifies active finite-cell IDs.
- `F` identifies reusable finite-cell slots.
- `G` stores the generation of each finite-cell slot.
- `P` stores auxiliary physics state required by the model.
- `D` stores derived state or its incrementally maintained tracker representation.

This definition is logical. It does not require a particular Julia struct or physical storage
layout.

## Site Ownership

Every lattice site MUST have exactly one owner. Its owner MUST be either:

- One active finite cell, or
- One declared medium domain.

An empty or unassigned owner is not a valid simulation state.

The physical lattice encoding MUST distinguish all medium types that can simultaneously occupy the
lattice. The historical convention that one integer value denotes all medium sites is insufficient
for multiple media and is not normative.

## Finite Cells

A finite cell in a finalized or published state:

- MUST have a positive public cell ID.
- MUST own at least one lattice site while active.
- MUST have exactly one declared cell type.
- MUST occupy exactly one live storage slot.
- MUST NOT appear in the reusable-slot collection while active.
- MAY be disconnected unless a model explicitly applies a connectivity constraint.

Symbolic Potts V1 permits only one bounded pre-publication exception: a zero-occupancy active
identity whose resolved `RetireAtZero` transaction is due in the current lifecycle plan. It MUST be
retired before publication. A `ForbidExtinction` identity reaching zero occupancy is a
nonfilterable invariant failure, not an alternate retirement path. See CCV1-027 in the
[compiler construction contract](symbolic-potts-v1-compiler-construction.md).

Cell IDs are visible to users and MAY be used for selection and analysis. They are reusable storage
handles rather than permanent lineage identities.

## Cell Types and Compiled Type Indices

Biological models refer to symbolic cell types. Dense numerical type indices are assigned during
model compilation for device lookup.

User-facing biological rules SHOULD use symbolic cell types. An advanced read-only type-index query
MAY be provided for diagnostics and low-level extension work. Model semantics MUST NOT depend on a
user hardcoding an internal type index.

Changing a model's declaration order MAY change compiled indices but MUST NOT change rules expressed
using symbolic types.

## Medium Domains

Multiple medium types MAY exist simultaneously. Each medium type corresponds to one conceptual
medium domain, even if its lattice occupancy consists of disconnected regions.

A medium domain:

- MAY define adhesion, chemotaxis, external-field, custom-penalty, and property-rule behavior at the
  type level.
- MUST NOT define finite-cell instance properties such as target volume, finite volume, age, or
  pressure.
- MUST NOT divide, die, grow as a finite cell, or participate in finite-cell lifecycle transitions.
- MUST have measurable occupancy within the finite simulated lattice.
- Is conceptually spatially unbounded even though its in-domain occupancy is finite.

Medium occupancy is not finite-cell volume and MUST be exposed separately.

## Cell Counts and Capacity

The following quantities are semantically distinct:

- Active finite-cell count
- Fixed cell capacity
- Number of reusable slots
- Cell-ID high-water mark

`n_cells(state)` MUST mean the number of active finite cells. It MUST NOT mean capacity or the largest
cell ID ever allocated.

GPU execution uses fixed finite-cell capacity. Exceeding that capacity during a lifecycle transaction
MUST raise a structured capacity error and MUST NOT partially commit the transaction.

## Slot Reuse

Compiled storage MUST distinguish never-used, active, and reusable slots, or encode exactly the
same facts with a high-water mark and reusable collection. After retirement, a finite-cell ID MAY
be reused beginning at the next MCS. Reusable IDs MUST be selected in deterministic ascending
order before fresh IDs above the high-water mark.

Every slot maintains an internal generation counter. A never-used slot has no live generation and
its first identity receives generation one. Retirement preserves the consumed generation in the
reusable slot. Assigning that slot to a new cell MUST increment the counter exactly once, after
overflow preflight. RNG streams for cell-specific behavior MUST distinguish different generations
of the same cell ID.

Slot generation is not a public lineage identifier in specification version `0.2-draft`.

## Property Schema

The model compiler constructs a complete property schema before runtime execution. Every device
property declaration MUST identify at least:

- A logical name or key
- A GPU-compatible logical type
- Initialization behavior
- Mutability
- Division policy or derived-state invalidation behavior
- Type-transition policy or derived-state invalidation behavior
- Retirement policy or derived-state cleanup behavior
- Whether it is biological, derived, auxiliary, or transient
- The component or extension that requested it

The schema is the sole authority for property lifecycle behavior. Each property records separate
typed policy values for initialization, division, type transition, and retirement. A policy value
implements only its applicable operation through ordinary Julia methods; it is not required to
subtype or populate one universal lifecycle-policy object.

Built-in properties MAY supply documented policy values through their schemas. A custom property
MUST explicitly select a policy or explicitly declare the corresponding lifecycle operation
unsupported. Missing behavior, an unrecognized enum value, or an undocumented global default is a
model-construction error. An event-specific policy override is permitted only when it is explicit,
compatible with the property schema and transaction, and included in model provenance.

Behavioral policy enums, a parallel inheritance hierarchy, and central concrete-policy `isa`
switches are not part of the stable property interface. Host policy values MAY use convenient
authoring representations, but every GPU-qualified policy MUST lower to an immutable
bitstype-compatible descriptor and bounded storage.

Compatible requests for the same property MUST be deduplicated. Incompatible types, initializers,
inheritance rules, or transition rules MUST produce a model-construction error containing request
provenance. Silent last-write-wins merging is prohibited.

### Derived-property lifecycle

A derived property is never cloned, split, reset as biological inheritance, or transformed by an
ordinary property policy. Its family declares authoritative dependencies, invalidation scope,
reference recomputation, incremental-repair behavior where available, and execution capabilities.
After a lifecycle transaction commits its authoritative state, every invalidated derived property
MUST be repaired or recomputed before the completed boundary becomes observable.

An externally defined derived-property family follows the same open recomputation protocol and, when
GPU-qualified, supplies a concrete device-valid lowering. Engine ownership of recomputation is a
closed consistency invariant; the set of derived-property families remains open.

Stable device properties MAY include fixed-width scalars, isbits enums, tuples or named tuples of
supported values, small fixed-size vectors or tensors, and GPU-compatible immutable isbits structs.
Heap-backed or dynamically sized object graphs are not valid device state.

Logical fixed-size vectors and tensors MAY be lowered to component-wise physical storage. Physical
storage choices are implementation details provided that logical values and mutation semantics are
preserved.

## State Realization Layers

Potts.jl distinguishes three state layers:

1. **Logical state** is the authoritative scientific representation used for construction,
   validation, scalar reference execution, snapshots, and portable inspection.
2. **Compiled execution state** is an explicit lowering of logical state into backend-valid arrays,
   indices, and layouts. It MAY be specialized, but MUST round-trip to the same canonical logical
   snapshot under the applicable numerical contract.
3. **Execution workspace** contains scratch storage, queues, counters, launch resources, and other
   replaceable mutable machinery. Workspace content is not scientific state and MUST NOT be needed
   to interpret a saved model state.

The host logical state MUST NOT be adapted wholesale to a GPU. Compilation constructs the explicit
execution representation, and backend movement is centralized at that boundary. Optimized engines
MAY keep compiled state resident across steps and observations.

## Custom Properties

Potts MUST support user-declared custom per-cell properties through the same compiled schema
as built-in components. Custom properties MUST NOT bypass type, lifecycle, initialization, or GPU
compatibility validation.

Rich host-only metadata MAY be associated with cells through a separate facility. Host-only metadata
MUST NOT be visible to device-executed rules unless an explicit synchronizing transfer is performed.

## State Invariants

A conforming state MUST satisfy:

1. Every site has exactly one valid owner.
2. Every finite owner in the lattice is active.
3. Every active finite cell in finalized or published state owns at least one site; the only
   admitted pre-publication zero-occupancy transient is a due `RetireAtZero` transaction.
4. Every active finite cell has exactly one valid cell type.
5. No cell ID is both active and reusable.
6. No reusable ID occurs more than once.
7. Active count equals the cardinality of the active-ID set.
8. Tracked occupancy equals full lattice recomputation.
9. All required properties exist for every finite-cell slot.
10. Retired slots contain their schema-defined reset state.
11. Medium-domain occupancy equals full lattice recomputation.
12. No medium domain has finite-cell lifecycle or instance-property state.
13. Never-used, active, and reusable slot states are distinguishable, and no ID retired in MCS `t`
    is allocated again before MCS `t + 1`.

The conformance suite MUST provide full-state validators for these invariants.

## Initialization Finalization

### Open layout protocol

An initial layout is an ordinary Julia value implementing one minimal open protocol. It MUST:

- declare its domain, dimensional, topology, property, RNG, and execution requirements; and
- emit provisional entity declarations and ownership claims into compiler-owned storage.

Validation, overlap resolution, zero-occupancy removal, runtime ID assignment, property
initialization, derived-state reconstruction, compiled-state lowering, and backend adaptation are
generic engine responsibilities. A layout does not need separate source, rasterizer, placer,
manager, or factory objects unless a concrete implementation benefits from ordinary internal
composition.

The required paper built-ins accept dense ownership or masks, explicit coordinate ownership, and
the procedural shapes used by paper models and tutorials. File-format readers are not layout
protocols; external Julia packages MAY load images or tables into these ordinary inputs.

### Provisional entity identity

Every provisional finite entity has a stable semantic identity independent of declaration order,
container position, storage address, thread, and backend scheduling. Built-in labeled layouts derive
that identity canonically from the layout instance and logical label. Composed layouts MAY
explicitly refer to one shared provisional identity; incompatible declarations for that identity are
a construction error with provenance.

Provisional identities are not requested runtime cell IDs. After overlap resolution, provisional
entities with zero occupancy are removed. Survivors are ordered by canonical provisional identity
and assigned compact deterministic runtime IDs. Only survivors acquire runtime slots and slot
generations.

### Ownership claims and overlap

Ownership claims are logically unordered. If distinct finite entities claim one site, overlap is an
error unless the problem explicitly supplies a typed overlap policy. The required Phase 8 policies
are:

- reject every conflicting claim; and
- select by an explicit stable semantic priority, rejecting an unresolved tie.

Replacement or preservation spellings MUST identify their semantic claimant or priority relation;
they MUST NOT mean first declaration wins or last declaration wins. Tuple order, layout emission
order, runtime cell ID, thread scheduling, launch decomposition, and atomic arrival order never
resolve ownership.

Overlap resolution is a small open dispatch boundary, but Phase 8 does not implement general
composition, stochastic winners, adaptive packing, or geometric constraint solving.

### Finalization order

Initialization MUST proceed logically as follows:

1. Rasterize all layouts.
2. Apply an explicit overlap policy.
3. Determine which provisional finite cells own at least one site.
4. Remove zero-occupancy provisional cells.
5. Assign compact runtime cell IDs to surviving cells.
6. Validate fixed capacity.
7. Initialize schema-defined biological and auxiliary state.
8. Recompute derived state from the finalized lattice.
9. Validate all state invariants.
10. Lower the finalized logical state into an explicit compiled execution representation when an
    execution engine requires one.
11. Adapt only that compiled representation through the centralized backend boundary.

Layout overlap MUST default to an error. Replacement or preservation behavior MUST be explicitly
requested. Silent overwrite is prohibited.

Biological and auxiliary property initialization occurs only after overlap resolution,
zero-occupancy removal, deterministic runtime ID assignment, and capacity validation. A rejected or
empty provisional entity receives no runtime slot, generation, property state, or property-
initialization draw. Layout-placement randomness is instead addressed by stable layout and
provisional identities, so removing or reordering an unrelated claim cannot shift its draws.

### Host-finalized and device-native initialization

Initialization declares one of two explicit execution capabilities:

- **Host-finalized initialization** constructs and validates canonical logical state on the host,
  then lowers and transfers compiled state once before execution.
- **Device-native initialization** lowers claim emission and finalization into a complete qualified
  device path with concrete descriptors, bounded workspaces, and no hidden host completion.

Host finalization is a visible construction choice, not a fallback inside GPU simulation. It does
not weaken the requirement that a GPU MCS remain device-resident. Required large built-in layouts
SHOULD gain device-native implementations when construction benchmarks show a material time or
memory benefit; arbitrary custom layouts are not required to be device kernels.

Host-finalized and device-native implementations advertised as the same initialization algorithm
MUST produce the same canonical logical initial state under the same model, seed, RNG contract, and
accepted numerical profile. A faster method with observably different placement semantics requires
a separately named initialization algorithm or profile.

### Random placement algorithms

The unqualified concept `RandomLayout` is not a stable sampling law. Phase 8 distinguishes at least
uniform site seeding from sequential rejection placement of shapes. A future packing or approximate
placement process receives a separate name and guarantee profile.

#### Uniform site seeds

Uniform site seeding places labeled provisional entities by selecting a uniform injection into the
eligible logical sites. Eligible sites are mutable ownership sites inside the declared placement
domain after obstacles, fixed owners, and prior explicit claims are excluded.

Provisional entities, their cell types, and their property overrides are enumerated in canonical
semantic-identity order; dictionary iteration never defines their order. The selected sites are
sampled uniformly without replacement and assigned to that canonical entity sequence. If the number
of requested seeds exceeds the number of eligible sites, the complete placement fails before
publishing any claim.

The named implementation MUST specify and qualify its unbiased permutation or sampling algorithm.
A device implementation sharing the same algorithm name and RNG profile must produce the same
canonical claims as its host implementation. Stateful task-local RNG and scheduling-dependent
atomic selection are prohibited.

#### Sequential rejection placement

Sequential rejection placement is a distinct named algorithm, not a claim of uniform sampling over
all non-overlapping configurations. Provisional entities are processed in canonical semantic order
unless the model explicitly requests a semantically addressed permutation policy.

For each entity, the algorithm samples a center and any orientation or shape parameters from their
declared distributions. Candidate `a` uses a semantic address containing the layout instance,
provisional entity, attempt index, and draw role. A candidate is accepted only when its complete
raster is valid and does not conflict under the selected overlap policy. Accepted earlier entities
remain fixed; the basic algorithm performs no hidden backtracking.

Every entity has an explicit positive attempt bound. Exhausting it aborts the complete layout
transaction and reports the failed provisional identity, attempt bound, eligible domain, shape, and
accepted-claim count. It MUST NOT silently drop, shrink, clip, overlap, or relocate an entity through
an undocumented fallback.

### Periodic rasterization

A shape centered near a periodic boundary is evaluated in canonical lattice coordinates using the
domain's accepted minimum-image displacement on each periodic axis. Its ownership may therefore
wrap across the boundary while remaining one provisional entity.

The rasterizer MUST detect an unwrapped shape support that aliases itself onto one canonical site
because the requested shape is too large for the periodic domain. Stable built-ins reject such a
shape rather than silently changing its volume or weighting duplicated images.

On nonperiodic axes, out-of-domain support rejects by default. An explicitly named clipping policy
MAY create the in-domain intersection, but clipping changes geometry and appears in provenance. A
center distribution must state whether it samples all declared centers followed by geometric
rejection or only the precomputed set of fully valid centers.

### Dense and confluent initialization

Sequential rejection placement may jam and does not imply uniform sampling of feasible packings.
Phase 8 MUST NOT advertise it as a general confluent or packed-tissue initializer. Paper models that
require confluence use deterministic tiling, an explicit ownership mask, or a separately named and
validated packing algorithm. General stochastic packing is deferred.
