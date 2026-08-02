# Symbolic Potts V1 lifecycle language — owner interview

Status: owner interview complete; Rounds 1 through 4 accepted, consolidation pending  
Scope: a bounded, fully implemented lifecycle language with configurability analogous to symbolic Hamiltonians  
Gate: proposed G5 lifecycle completion before the final R2 execution review  

## Purpose

The current runtime retires zero-volume cells through an unconditional CorePotts scan. Public
syntax already contains `Retire`, `Transition`, and `Divide`, but V1 compilation does not yet admit
those cell lifecycle effects. This interview determines whether V1 replaces that split authority
with one compiler-owned lifecycle language before R2.

The target is not arbitrary mutation. The Hamiltonian analogy is:

| Hamiltonian | Lifecycle |
|---|---|
| finite domain and bound anchor | finite event domain and bound entity |
| arbitrary admitted pure expression | arbitrary admitted Boolean trigger and value expressions |
| closed operation contracts | closed structural-effect contracts |
| compiler-derived affected anchors | compiler-derived read/write and topology footprints |
| immutable local evaluator | immutable trigger/effect evaluators |
| local contribution folding | canonical transactional request folding |

The desired thesis is:

> Lifecycle models may freely compose symbolic triggers, state, fields, relationships, histories,
> parameters, cadence, and explicit stochastic draws around a small closed algebra of structural
> effects. The compiler proves boundedness and emits deterministic transactions; CorePotts does
> not know named biological mechanisms.

## Research baseline

Primary framework documentation and CPM literature repeatedly expose a compact family of lifecycle
behaviors:

- growth by changing target volume;
- apoptosis by shrinking target volume and retiring or deleting the resulting cell;
- division triggered by size, time, state, geometry, or stochastic conditions;
- random, major-axis, minor-axis, or specified-axis division;
- explicit parent/daughter state mapping;
- conditional cell-kind transition; and
- conditional cell death and, in some environments, explicit cell addition.

References used for the interview:

- CompuCell3D cell death: <https://compucell3dreferencemanual.readthedocs.io/en/latest/cell_death.html>
- CompuCell3D mitosis: <https://compucell3dreferencemanual.readthedocs.io/en/latest/mitosis.html>
- Morpheus crypt lifecycle example: <https://morpheus.gitlab.io/model/m0026/>
- Artistoo post-MCS biological processes: <https://artistoo.net/manual/simulationConfig2.html>
- CPM tumor-model review: <https://pmc.ncbi.nlm.nih.gov/articles/PMC3627127/>
- Parallel CPM growth/division/death description: <https://pmc.ncbi.nlm.nih.gov/articles/PMC2139985/>

## Owner constraints already stated

These are interview premises rather than open questions:

1. The result must be bounded but fully implemented, not a decorative API over hardcoded runtime
   behavior.
2. Lifecycle authoring should approach the configurability of symbolic Hamiltonians.
3. Named literature recipes may exist only as expansions over generic compiler primitives.
4. No arbitrary mutation callbacks, hidden RNG, runtime registry lookup, or silent host fallback.
5. The gate placement must be decided before implementation; the current recommendation is before
   the final R2 because R2 owns G5 lifecycle, concurrency, checkpoint, and backend behavior.
6. Every structural lifecycle effect admitted into V1-L must be functionally implemented on the
   selected real GPU witness before R2. CPU-only admission is not an acceptable V1-L completion.
   The semantic harness must remain backend-neutral so Metal, CUDA, and AMDGPU can occupy the same
   later release matrix without vendor-specific lifecycle definitions.

## Interview plan

1. **Round 1 — language boundary:** admitted effects, authoring surface, symbolic openness, extension
   boundary, and R2 placement.
2. **Round 2 — scientific policies:** extinction, transition, division geometry, state inheritance,
   relationships, and literature recipes.
3. **Round 3 — transaction law:** snapshot timing, conflicts, capacity, identity/generation,
   checkpointing, and failure atomicity.
4. **Round 4 — portability and qualification:** sequential/checkerboard behavior, GPU capability,
   external extensions, diagnostics, performance, and exact acceptance tests.
5. **Consolidation:** amend the authoritative construction spec only after all owner decisions and a
   focused independent specification review.

## Round 1 — language boundary

### LCI-R1-01 — Initial structural-effect vocabulary

**Option A — `Retire`, `Transition`, and `Divide` only.**

Admit the three structural cell effects already present in public syntax. Growth and apoptotic
shrinkage use existing state/equation assignments. Positive-volume immediate deletion, independent
cell creation, fusion, and engulfment remain outside V1-L.

This covers conventional shrink-to-extinction death, differentiation, symmetric/asymmetric
division, timers, sizers, signaling triggers, and stochastic division without introducing a
general topology-rewrite language.

**Option B — add `RemoveCell`.**

Also admit atomic positive-volume removal with explicit ownership replacement. This reproduces
threshold deletion and immediate cell death directly, but adds whole-cell ownership rewriting,
tracker reconstruction, relationship consequences, and a larger GPU transaction surface.

**Option C — complete the closed five-effect cell-structure algebra (accepted).**

Admit `Retire`, `RemoveCell`, `Transition`, `Divide`, and `CreateCell` together. They must lower
through one closed cell-structure transaction IR rather than five unrelated executors:

| Effect | Identity arity | Ownership meaning |
|---|---:|---|
| `CreateCell` | 0 -> 1 | initialize a new finite occupied identity |
| `RemoveCell` | 1 -> 0 | transfer all owned sites to a declared medium and consume the identity |
| `Retire` | 1 -> 0 | consume an already empty identity without an ownership rewrite |
| `Transition` | 1 -> 1 | retain identity and ownership while changing kind/state mapping |
| `Divide` | 1 -> 2 | partition one identity's sites between parent and daughter |

V1-L still rejects fusion, fragmentation, engulfment, arbitrary source/destination cardinalities,
recursive rewrite emission, and general graph rewriting. Creation geometry, division geometry,
state mapping, and relationship consequences remain closed typed policy families decided in Round
2.

Revised recommendation rationale: leaving the 0 -> 1 and occupied 1 -> 0 cases unimplemented would
leave allocation, placement, whole-cell ownership rewrite, and their GPU conflict semantics outside
the supposedly frozen transaction architecture. Those are exactly the dimensions most likely to
force later redesign. Option C is larger than the original three-effect proposal, but it remains
bounded by the literal five-effect inventory, closed policy families, and the requirement that every
effect pass the same real GPU transaction path before R2.

Decision: accepted by owner.

Owner concern recorded during Round 1: accepting only three effects would create prospective
engineering debt by freezing R2 before the transaction IR had proved cell creation and occupied-cell
removal. The recommendation was changed from Option A to Option C in response. The owner then added
fusion and bounded fragmentation temporarily, then withdrew both before consolidation.

### LCI-R1-02 — Raw authoring surface

**Option A — retain `LifecycleProcess` (recommended).**

Make the existing form authoritative:

```julia
LifecycleProcess(
    :divide_large_cells;
    domain = cells(epithelial),
    anchor = cell,
    expression = cell_volume(cell) >= division_volume,
    effects = (Divide(cell; policy = division_policy),),
    phase = Lifecycle(),
    cadence = EveryMCS(),
)
```

Do not introduce a synonymous `LifecycleRule` AST node.

**Option B — replace it with `LifecycleRule`.**

Use terminology closer to a rule language, at the cost of another public concept and migration
inside the branch.

**Option C — macro-only DSL.**

Introduce `@lifecycle` syntax. This may become attractive later, but it would conceal the ordinary
composable Julia representation during the compiler's first qualification.

Recommendation rationale: Option A matches the existing statement system, ModelingToolkit-style
composition, qualified completion, and direct inspectability.

Decision: accepted by owner.

### LCI-R1-03 — Symbolic configurability

**Option A — open symbolic triggers and values over admitted operations (recommended).**

Lifecycle predicates may compose parameters, units, cell/site/model state, fields, histories,
relationships, geometry trackers, explicit stable draws, and registered pure operations. Analysis
must prove a Boolean trigger, valid units, a finite domain, bounded reads, bounded emission, and
backend capability.

**Option B — predefined trigger families only.**

Provide size, timer, threshold, and probability trigger structs. This is simpler but materially less
configurable than Hamiltonians and would push novel literature mechanisms into callbacks.

**Option C — arbitrary Julia predicates.**

Allow callable predicates. This maximizes surface flexibility but loses symbolic analysis,
serialization stability, device qualification, and deterministic registry freezing.

Recommendation rationale: Option A is the direct Hamiltonian analogue and reuses the cleared
expression compiler.

Decision: accepted by owner.

### LCI-R1-04 — Extension boundary

**Option A — closed structural verbs, open composition and registered pure policies
(recommended).**

External packages may define recipes freely by composing public rules. New trigger operations and
pure partition/state-transform policies may enter through versioned, frozen, capability-declared
registration. Adding a new structural mutation verb requires a new compiler/runtime contract.

**Option B — closed everything for V1.**

Only package-defined operations and policies are admitted. This is simpler but falls short of the
external extensibility expected from the Hamiltonian compiler.

**Option C — external structural-effect registration.**

Allow extensions to register arbitrary new mutation verbs. This would require an effect-IR plugin
system, conflict algebra, checkpoint contract, and device transaction protocol and is not bounded
for V1.

Recommendation rationale: Option A opens scientific composition and pure computation while keeping
mutation semantics compiler-verifiable.

Decision: accepted by owner.

### LCI-R1-05 — Placement relative to R2

**Option A — complete V1-L before the one authoritative R2 (recommended).**

Finish and checkpoint the current surface-binding repair, implement and qualify V1-L, then run one
fresh R2 over the complete G5 execution boundary. Every admitted lifecycle effect must first pass
the shared CPU/backend semantic harness and the selected real GPU witness. G6 remains closed.

**Option B — clear current R2, then reopen G5 and rerun R2.**

This produces an intermediate clearance for an execution path already selected for replacement and
duplicates the expensive review.

**Option C — defer lifecycle language until after G6/G7.**

This lets proof models depend on the hardcoded retirement path and makes later replacement more
expensive.

Recommendation rationale: Option A follows the accepted gate definition. R2 explicitly owns G5
lifecycle, checkpoint, concurrency, and GPU legality.

Decision: accepted by owner.

## Decision ledger

| ID | Decision | Status |
|---|---|---|
| LCI-R1-01 | Initial structural-effect vocabulary | Accepted: five-effect closed rewrite algebra |
| LCI-R1-02 | Raw authoring surface | Accepted: retain `LifecycleProcess` |
| LCI-R1-03 | Symbolic configurability | Accepted: open admitted symbolic expressions |
| LCI-R1-04 | Extension boundary | Accepted: closed verbs, open composition and pure policies |
| LCI-R1-05 | Placement relative to R2 | Accepted: complete and GPU-qualify before final R2 |

## Round 2 research — scientific policy boundary

Repository research found that the earlier lifecycle specifications already contain several useful
constraints that remain compatible with the accepted V1-L direction:

- fixed finite-cell capacity, deterministic ascending free-slot selection, generation-aware reuse,
  and complete-batch capacity failure;
- one common pre-lifecycle snapshot;
- schema-owned, operation-specific initialization, division, transition, and retirement policies;
- explicit compatible event overrides recorded in provenance;
- no undocumented copy, reset, zero, or conservation default for custom or auxiliary state;
- derived trackers reconstruct or repair from committed authoritative ownership rather than using
  biological inheritance policies; and
- GPU policies lower to immutable bounded device descriptors without host fallback.

Framework and literature findings sharpen the minimum policy vocabulary:

- CompuCell3D separates shrinkage apoptosis from explicit deletion below a chosen volume and makes
  parent/daughter attribute updates explicit.
- CompuCell3D exposes random, major-axis, minor-axis, and specified-normal division and warns that
  fixed parent-side assignment can bias simulations.
- Morpheus division and type transition combine symbolic conditions with explicit property rules;
  common properties may be preserved while new properties receive declared defaults.
- Morpheus `AddCell` uses a condition plus spatial placement distribution, supporting a creation
  primitive whose placement is separate from its trigger.

### LCI-R2-01 — Property-policy authority and precedence

**Option A — schema defaults plus explicit compatible event overrides (recommended).**

Every authoritative cell state declares separate policies for creation, removal/retirement,
transition, and division. A lifecycle effect may explicitly override compatible policies. Completion
resolves exactly one policy per affected state using `event override -> schema default -> fail` and
freezes the complete plan with provenance. Derived trackers use reconstruction/repair contracts,
never ordinary inheritance.

**Option B — event-owned mappings only.**

Every event repeats the full state map. This is explicit but makes adding one state force edits to
every lifecycle rule and encourages inconsistent model families.

**Option C — package-global defaults.**

Implicitly copy or reset unspecified state. This is concise but assigns undocumented scientific
meaning and recreates a central policy authority.

Decision: accepted by owner.

### LCI-R2-02 — Extinction, occupied removal, and retirement

**Option A — distinct `RemoveCell` and `Retire` transactions (recommended).**

`Retire(cell)` requires zero authoritative volume and no owned sites. `RemoveCell(cell; replacement
= medium)` atomically transfers every owned site to one declared medium, applies removal policies,
handles incident relationships, and retires the consumed identity. Completion synthesizes ordinary
zero-volume `Retire` rules for cell kinds that permit stochastic extinction.

**Option B — one overloaded removal effect.**

One verb decides at runtime whether ownership rewriting is necessary. This reduces syntax but hides
different footprints, costs, invariants, and scientific causes behind one descriptor.

**Option C — shrink-to-zero only.**

Omit occupied removal. This is narrower but fails the accepted five-effect vocabulary and cannot
express immediate or threshold deletion directly.

Decision: accepted by owner.

### LCI-R2-03 — Creation placement

**Option A — closed finite placement policies (recommended).**

Admit `SeedAt(site_expression)` and `SeedStencil(site_expression, finite_offsets)`. The compiler
proves a finite maximum footprint. Runtime requires every selected site to be in bounds, admissible,
and available in the common snapshot; clipping and partial creation are forbidden. Site conflicts
use canonical transaction arbitration. The stencil must be connected under one explicitly bound
creation relation.

**Option B — single-site creation only.**

This is simpler and can grow afterward through CPM dynamics, but makes initialized finite shapes and
some recruitment models unnecessarily awkward.

**Option C — arbitrary placement sampler/callback.**

This resembles flexible framework scripting but loses static bounds, device qualification, and
deterministic conflict analysis.

Decision: accepted by owner.

### LCI-R2-04 — Division geometry and daughter-side identity

**Option A — explicit plane policies with validation and explicit side assignment (recommended).**

Admit random plane, principal-axis plane, and symbolic specified-normal plane policies. Normalize
all policies to a plane point and normal so `major`/`minor` terminology cannot hide whether an axis
names the plane or its normal. Division binds an explicit finite spatial relation used for daughter
connectivity. Both partitions must be nonempty and connected; invalid geometry rejects that request
without a fallback partition.

Parent-versus-daughter side assignment must be explicit: canonical side or stable keyed random side.
No hidden default may introduce directional bias.

**Option B — random plane only.**

Smaller implementation, but insufficient for polarity-directed and principal-axis division common
in CPM models.

**Option C — arbitrary partition callback.**

Maximum flexibility, but not symbolically analyzable or safely GPU-qualified.

Decision: accepted by owner.

### LCI-R2-05 — Stable state-policy families

**Option A — small operation-specific typed families (recommended).**

The stable V1-L vocabulary is:

- creation: `InitializeFrom(expression)` or `Unsupported()`;
- removal/retirement: `RetireTo(expression)` or `Unsupported()`;
- transition: `Preserve()`, `ResetTo(expression)`, `Transform(expression)`, or `Unsupported()`;
- division: `CopyToDaughters()`, `PreserveParentResetDaughter(expression)`, `ResetBoth(...)`,
  `SplitConservatively(...)`, `TransformDaughters(...)`, `RedrawDaughters(...)`, or
  `Unsupported()`.

Stochastic rounding/redraw uses explicit lifecycle draw identities. Every stable built-in policy
must be functional on the real GPU witness. External registered pure policies carry frozen version,
units/types, purity, totality, bounds, RNG requirements, and backend capabilities.

**Option B — only copy and reset.**

Easy to implement but insufficient for conserved molecular content, asymmetric division, timers,
lineage state, and source-qualified stochastic inheritance.

**Option C — arbitrary property callback.**

Expressive but bypasses the compiler and cannot satisfy GPU, replay, or frozen-completion claims.

Decision: accepted by owner.

### LCI-R2-06 — Relationship consequences

**Option A — closed operation-specific policies, with transfer deferred (recommended).**

- creation starts with no incident relationships;
- removal/retirement selects `RejectWhileLinked()` or `RemoveIncident()`;
- transition selects `PreserveCompatible()`, `RemoveIncompatible()`, or `RejectIncompatible()`;
- division selects `RejectWhileLinked()` or `RemoveIncident()` in V1-L.

Relationship inheritance/transfer to daughters is deferred because it requires a scientifically
defined endpoint-assignment law and may depend on spatial attachment data absent from generic
relationships. Every selected policy participates in the same atomic transaction.

**Option B — always remove incident relationships.**

Simple but silently imposes a scientific choice and prevents persistent compatible relationships
across type transitions.

**Option C — include daughter relationship transfer now.**

More immediately configurable, but requires endpoint allocation laws, duplicate resolution,
payload transformation, attachment geometry, and additional GPU conflict classes before R2.

Decision: accepted by owner.

## Round 2 decision ledger

| ID | Decision | Status |
|---|---|---|
| LCI-R2-01 | Property-policy authority and precedence | Accepted: schema default, explicit override, fail closed |
| LCI-R2-02 | Extinction, occupied removal, and retirement | Accepted: distinct `RemoveCell` and `Retire` |
| LCI-R2-03 | Creation placement | Accepted: finite `SeedAt` and `SeedStencil` policies |
| LCI-R2-04 | Division geometry and daughter-side identity | Accepted: explicit planes, relation, validation, and side assignment |
| LCI-R2-05 | Stable state-policy families | Accepted: operation-specific typed policies |
| LCI-R2-06 | Relationship consequences | Accepted: closed V1 policies; daughter transfer deferred |

## Round 3 research — transaction law

The repository already contains a strong historical transaction contract, but the current V1
runtime does not implement it as one lifecycle authority. The Round 3 audit found:

- completion defines the semantic order `Proposal -> AcceptedCopy -> AfterMCS ->
  RelationshipCommit -> Lifecycle -> EquationStep -> Observe`;
- the accepted lifecycle specification requires all due triggers to read one immutable
  `PreLifecycleSnapshot` and forbids declaration order, tuple order, thread scheduling, or atomic
  arrival from deciding biological conflicts;
- the accepted relationship transaction already uses typed requests, canonical identities,
  explicit priority, complete preflight, staged state, and one publication step;
- the accepted state model distinguishes active count, fixed capacity, reusable slots, and the
  cell-ID high-water mark, but the current runtime represents only kinds and generations;
- the accepted state model increments a generation when a retired slot is reused, whereas the
  current hardcoded retirement scan increments it at retirement; these cannot both remain
  authoritative;
- exact checkpoints are already restricted to settled completed-MCS boundaries and include
  ownership, kinds, generations, trackers, relationships, state, parameters, RNG seed, counters,
  and fingerprints; and
- the current concrete RNG address has only global and site entity tags even though the accepted
  randomness contract requires cell-addressed draws to include cell ID and slot generation.

Portable implementation research supports a planned multi-kernel transaction rather than one
monolithic kernel. KernelAbstractions launches are asynchronous and provide a backend-neutral
synchronization boundary. AcceleratedKernels provides reusable-buffer prefix scans and stable
sorting primitives on CPU and GPU; its default scan avoids device-level lookback assumptions that
are unavailable on Metal. Those primitives are suitable for bounded request compaction, canonical
ordering, allocation ranks, and validation flags, while custom KernelAbstractions kernels retain
ownership of lifecycle-specific evaluation and commit.

References:

- KernelAbstractions quickstart and synchronization:
  <https://juliagpu.github.io/KernelAbstractions.jl/stable/quickstart/>
- AcceleratedKernels prefix scan:
  <https://juliagpu.github.io/AcceleratedKernels.jl/stable/api/accumulate/>
- AcceleratedKernels sorting and reusable temporary storage:
  <https://juliagpu.github.io/AcceleratedKernels.jl/stable/api/sort/>

### LCI-R3-01 — Phase location and snapshot authority

**Option A — preserve the closed phase order and capture one lifecycle snapshot (recommended).**

The ordinary completed-MCS plan is:

```text
Potts proposals and AcceptedCopy commits
    -> AfterMCS processes
    -> RelationshipCommit
    -> capture immutable PreLifecycleSnapshot
    -> evaluate, plan, and publish one Lifecycle transaction
    -> EquationStep
    -> Observe
    -> settled completed-MCS boundary
```

All due lifecycle triggers and policy expressions read that one snapshot. No request may observe
another lifecycle outcome from the same boundary, and newly created daughters cannot trigger again
until a later lifecycle invocation. Zero-volume retirement is an ordinary compiler-synthesized
`LifecycleProcess`, not an executor prepass. `Lifecycle` becomes a distinct compiled stage instead
of being folded into the generic `AfterMCSStage` tuple.

**Option B — capture immediately after Potts attempts.**

This makes lifecycle ignore declared `AfterMCS` and relationship updates and contradicts the
accepted phase ordering.

**Option C — let each lifecycle rule choose its phase position.**

This is expressive but multiplies snapshot, conflict, checkpoint, and backend laws and is outside a
bounded V1-L.

Decision: accepted by owner.

### LCI-R3-02 — Request canonicalization and biological conflict resolution

**Option A — reject ambiguity by default; require explicit semantic priority (recommended).**

Every emitted request carries a qualified rule identity, source anchor and generation when
applicable, structural effect, read/write/topology footprint, explicit signed-integer semantic
priority, and canonical occurrence identity. Exact duplicate requests are deduplicated. Requests
whose identity, ownership, state, site, or relationship write footprints overlap incompatibly form
one conflict set.

The default `RejectLifecycleAmbiguity()` aborts an activated ambiguous phase. An explicitly selected
`StableLifecyclePriority()` keeps the unique greatest semantic priority in each conflict set; an
equal greatest priority remains an error. Priority is declared model meaning, not statement order,
cell ID, slot number, compiler grouping, kernel launch order, or atomic arrival. There is no
universal `death > division > transition` category order. A model requiring combined behavior must
express one admitted composed effect rather than relying on two coincident requests.

**Option B — break equal priorities by canonical request identity.**

This is deterministic but silently turns a compiler identity into biological precedence.

**Option C — install a fixed effect-category hierarchy.**

This is convenient for some recipes but hardcodes one biology into the engine and makes the
configuration surface misleading.

Decision: accepted by owner.

### LCI-R3-03 — Local inadmissibility, integrity failure, and capacity

**Option A — distinguish expected request rejection from phase failure (recommended).**

An effect declares a typed `on_inadmissible` disposition. Expected snapshot-relative failures such
as an invalid division partition, unavailable creation stencil, nonempty `Retire`, or a linked cell
under `RejectWhileLinked()` either filter that request with a bounded diagnostic or fail the phase,
as explicitly selected. Filtering one request does not suppress unrelated valid requests.

Stale generations, illegal or missing policies, nonfinite evaluator results, request-buffer
overflow, generation overflow, internal footprint violations, and failed post-plan invariants are
integrity errors and always abort the complete phase before publication. After geometry and
conflict filtering, insufficient cell or relationship capacity aborts the complete valid batch with
a structured capacity error; no deterministic subset is committed. A model may explicitly select
a bounded biological subset before capacity preflight, but physical capacity exhaustion is never
reinterpreted as selection semantics.

**Option B — filter every invalid request.**

This keeps runs alive but can hide compiler bugs and corrupt scientific intent.

**Option C — abort the phase for every locally invalid request.**

This is strict but makes ordinary geometry-dependent division and stochastic placement brittle.

Decision: accepted by owner.

### LCI-R3-04 — Cell-slot allocation and generation law

**Option A — explicit slot status; generation advances on reuse (recommended).**

Compiled state distinguishes `NeverUsed`, `Active`, and `Reusable` slots, or an equivalent
high-water-plus-reusable representation. Valid `CreateCell` and `Divide` requests are ordered by
canonical request identity after conflict resolution. They receive ascending slots from the
pre-lifecycle free pool: reusable IDs first in ascending order, then fresh IDs above the high-water
mark. IDs retired or removed in MCS `t` are not eligible until MCS `t + 1`.

A fresh slot begins at generation one. Assigning a reusable slot advances its generation exactly
once during allocation, after overflow preflight. Retirement/removal makes the slot reusable but
does not advance it. `Transition` and the parent side of `Divide` retain ID and generation; the
daughter receives its allocated ID and generation. This conforms the current implementation to the
accepted state model and gives allocation one authority for new identity.

**Option B — advance generation at retirement.**

This matches the current hardcoded scan and immediately invalidates stale endpoints, but it makes an
inactive slot carry the next identity before that identity exists and conflicts with the accepted
state-model wording.

**Option C — advance at both retirement and reuse.**

This is safe against aliasing but skips generations without semantic value and creates two identity
authorities.

Decision: accepted by owner.

### LCI-R3-05 — Failure atomicity and physical commit

**Option A — fully preflighted staged transaction with one publication point (recommended).**

The logical implementation pipeline is:

1. evaluate bounded trigger masks from `PreLifecycleSnapshot`;
2. emit and compact typed requests;
3. canonicalize, deduplicate, and resolve conflicts;
4. plan ownership, identity, property, relationship, history, and tracker consequences;
5. validate all plans and preflight storage, capacity, generations, and workspace;
6. execute a commit path that cannot encounter a modeled validation failure;
7. repair or reconstruct derived trackers and relationship indexes; and
8. validate device status flags, publish the complete state, and publish diagnostics.

Authoritative values are never mutated and rolled back. Scratch buffers stage any destination for
which partial visibility would violate the contract. No model code, observation, snapshot, or
checkpoint can see an intermediate kernel. A hardware/backend failure during the commit is terminal
and recovers from the preceding completed-MCS checkpoint; semantic atomicity is not advertised as
crash-consistent device rollback.

**Option B — shadow the complete runtime and swap it after every lifecycle phase.**

This gives a simple publication proof but duplicates unrelated lattice, field, history, and graph
storage and imposes a high steady-state memory/copy cost.

**Option C — mutate in place and undo on validation failure.**

This is difficult to prove on asynchronous devices and creates a second inverse lifecycle language.

Decision: accepted by owner.

### LCI-R3-06 — Lifecycle RNG identities

**Option A — extend the versioned semantic address explicitly (recommended).**

The RNG contract gains an explicit cell entity tag and closed lifecycle stream families for event
triggers, conflict priority when selected, division geometry, property inheritance, conserved
rounding, transition, creation placement, and initialization. A cell-addressed draw includes the
source cell ID and generation. A site-addressed draw uses the canonical logical site. A model-domain
creation uses its qualified rule and bounded occurrence identity before a runtime cell exists.

Trigger and geometry draws are addressed from the pre-lifecycle source/request identity. Property
initialization draws occur only for surviving allocated destinations and include their allocated
ID, generation, descendant role, policy identity, and lexical draw identity. Branching, filtered
requests, conflict loss, declaration permutation, workgroup tuning, and backend launch decomposition
cannot shift unrelated draws. The frozen operation/stream mapping is fingerprinted. If the existing
packed address cannot represent this injectively, its RNG contract version changes rather than
aliasing a site address.

**Option B — encode cells as generational `SiteEntity` addresses.**

This minimizes code changes but lies about semantic identity and risks future namespace collision.

**Option C — use one global lifecycle stream with sequential counters.**

This makes trajectories depend on request order and is incompatible with parallel replay.

Decision: accepted by owner.

### LCI-R3-07 — Checkpoint, continuation, and diagnostic publication

**Option A — checkpoint only the settled semantic state (recommended).**

Stable checkpoint capture remains limited to finalized MCS `0` and the completed boundary after
Lifecycle, EquationStep, and required observation publication. It stores or fingerprints every
future-relevant lifecycle fact: ownership, slot status/high-water and reusable state, kinds,
generations, schema-owned cell state and histories, relationships with endpoint generations,
trackers under their checkpoint policies, MCS, parameters, seed/RNG contract, lifecycle policy and
stream identities, and the completed executable fingerprint. Replaceable request buffers, compaction
scratch, sort/scan temporaries, and backend events are reconstructed.

Diagnostics for filtered requests, conflicts, capacity failures, divisions, creations, removals,
retirements, transitions, and reuse publish only with the transaction outcome. Counters that affect
future semantics must be checkpointed; purely observational counters need not be. Exact same-profile
continuation must reproduce the uninterrupted trajectory and lifecycle trace. A failed lifecycle
phase leaves no new stable checkpoint and resumes only from the preceding completed boundary.

**Option B — serialize lifecycle queues and backend scratch.**

This permits mid-phase restart but freezes replaceable implementation details and contradicts the
accepted completed-MCS checkpoint boundary.

**Option C — checkpoint only ownership and biological properties.**

This is compact but cannot guarantee generation-safe relationships, RNG continuation, or exact
replay.

Decision: accepted by owner.

## Round 3 decision ledger

| ID | Decision | Status |
|---|---|---|
| LCI-R3-01 | Phase location and snapshot authority | Accepted: closed phase order and one lifecycle snapshot |
| LCI-R3-02 | Canonicalization and conflict resolution | Accepted: reject ambiguity; explicit semantic priority |
| LCI-R3-03 | Inadmissibility, integrity, and capacity | Accepted: typed local rejection; phase-level integrity and capacity failure |
| LCI-R3-04 | Slot allocation and generation | Accepted: explicit slot status; generation advances on reuse |
| LCI-R3-05 | Failure atomicity and commit | Accepted: complete preflight, staged commit, one publication point |
| LCI-R3-06 | Lifecycle RNG identities | Accepted: explicit versioned lifecycle semantic addresses |
| LCI-R3-07 | Checkpoint and diagnostics | Accepted: settled future-relevant semantic state only |

## Round 4 research — portability and qualification

The implementation and test audit found a good existing portability boundary to preserve:

- CorePotts already depends directly on KernelAbstractions, AcceleratedKernels, Atomix, and Adapt;
  CUDA, AMDGPU, and Metal remain outside the core package;
- the current backend harnesses already share model construction, seeds, and scientific assertions,
  while vendor runners inject only device arrays, conversion, synchronization, and discovery;
- the current G5 relationship GPU fixture explicitly qualifies immutable relationship reads, not
  device-resident relationship mutation, so it is insufficient for lifecycle removal and division
  consequences;
- the accepted construction spec requires every GPU compiler, semantic, conformance, stochastic,
  replay, checkpoint, and execution test to be authored once against a backend-neutral contract;
- ordinary package tests currently mix cheap semantic tests with expensive compilation and
  inspection work, despite the accepted spec saying package-wide JET, compile-latency, device-code,
  and similar qualification must not become universal blocking PR work; and
- the existing diagnostic system already provides stable categories, qualified identities, source
  provenance, expected/actual facts, alternatives, and deterministic ordering, but device runtime
  lifecycle failures still need a bounded payload and translation contract.

Official tooling supports this division. Julia package extensions load from declared weak
dependencies without making vendor packages base dependencies. CUDA exposes device-code type and
compiler inspection as focused developer tooling. KernelAbstractions and AcceleratedKernels provide
the shared execution surface; vendor runners should not fork scientific fixtures.

References:

- Julia package extensions: <https://docs.julialang.org/en/v1/manual/code-loading/#man-extensions>
- CUDA device compiler inspection:
  <https://cuda.juliagpu.org/stable/api/compiler/>
- KernelAbstractions execution and synchronization:
  <https://juliagpu.github.io/KernelAbstractions.jl/stable/quickstart/>
- AcceleratedKernels backend-neutral test philosophy:
  <https://juliagpu.github.io/AcceleratedKernels.jl/stable/>

### LCI-R4-01 — Engine ownership of lifecycle execution

**Option A — one engine-neutral lifecycle execution plan (recommended).**

Compilation produces one immutable `LifecycleExecutionPlan` containing descriptor groups, request
layouts, conflict/capacity plans, state and relationship consequences, tracker repairs, workspace
bounds, RNG identities, and diagnostics. Sequential and checkerboard engines invoke that same plan
at the accepted `Lifecycle` phase after producing their respective pre-lifecycle state. There is no
sequential lifecycle executor and checkerboard lifecycle executor with duplicated semantics.

Given an identical `PreLifecycleSnapshot`, parameters, seed, and compiled plan, direct lifecycle
execution must produce the same canonical discrete transaction on sequential CPU and checkerboard
CPU. The engines may produce different upstream snapshots because they define different CPM
dynamics; lifecycle does not erase that documented distinction. V1-L does not add a sequential GPU
algorithm claim—the functional GPU witness uses the accepted checkerboard GPU boundary plus the
shared lifecycle plan.

**Option B — separate engine-specialized lifecycle implementations.**

This may eventually improve performance, but it creates two transaction authorities before a
single generic implementation is qualified.

**Option C — lifecycle only on the sequential reference engine.**

This leaves checkerboard and GPU literature models incomplete and contradicts the accepted gate.

Decision: accepted by owner.

### LCI-R4-02 — Functional GPU meaning before R2

**Option A — full device-resident transaction on one real witness (recommended).**

Before R2, the shared backend-neutral harness must execute all five effects and every stable built-in
lifecycle policy family on the selected real GPU witness. The witness must exercise actual trigger
evaluation, request emission/compaction, conflict handling, capacity preflight, slot allocation,
ownership rewrite, cell-state policies, relationship consequences, generation handling, tracker and
incident-index repair, device status, and publication. A compile-only probe or read-only
relationship kernel does not qualify the effect.

GPU scalar indexing remains disabled. No lifecycle descriptor, request, state, relationship, or
tracker value may be transferred to the host for semantic computation. One explicit phase-end
synchronization and bounded device-status transfer are permitted to surface a structured error or
confirm publication; checkpoint/snapshot transfer remains a declared later host boundary. Metal may
serve as V1's functional witness on the available machine. CUDA and AMDGPU runners must invoke the
same harness later, but unavailable extra vendors do not block R2 after one witness passes.

**Option B — require only device compilation before R2.**

This catches illegal IR but does not prove transaction mutation, ordering, capacity, or tracker
behavior.

**Option C — device triggers with host planning and commit.**

This is a host fallback split across an obscure synchronization boundary and is not GPU lifecycle
support.

Decision: accepted by owner.

### LCI-R4-03 — External lifecycle-extension conformance

**Option A — one downstream module covering every claimed pure extension boundary (recommended).**

A test-only module outside CorePotts source defines:

- one versioned registered pure trigger operation;
- one non-built-in finite creation-placement policy;
- one non-built-in binary partition/geometry policy; and
- one non-built-in pure state-transform policy.

Two compact lifecycle rules may cover those contracts without manufacturing one unrealistic event.
They must complete through the public registry, freeze complete schemas and concrete callable values,
lower through the same plan/groups as built-ins, run on sequential CPU and checkerboard CPU, adapt
and run on the functional GPU witness, checkpoint/replay, and produce qualified inspection and
diagnostics. The fixture may compose the closed structural verbs but may not register a new mutation
verb. Passing it must require zero edits to CorePotts program types, proposal loops, lifecycle
executor, checkpoint machinery, effect switch, descriptor union, or mechanism branch.

**Option B — test only an external trigger operation.**

This proves expression registration but leaves the advertised placement, partition, and state-policy
extension boundaries untested.

**Option C — use Wortel or Merks as the extension fixture.**

Those are valuable G7 science fixtures but cannot prove that a biologically neutral downstream
extension receives equal treatment.

Decision: accepted by owner.

### LCI-R4-04 — Diagnostics and inspection contract

**Option A — stable host diagnostics plus bounded device status (recommended).**

Construction and lowering failures use the existing `PottsDiagnostic`/`PottsValidationError`
contract with stable lifecycle categories, qualified statement and policy identity, source
provenance, expected and actual facts, actionable alternatives, and deterministic ordering.
Required categories cover at least missing/unsupported policy, illegal operation or phase,
unbounded emission/footprint, unresolved conflict law, non-device callable, missing capability,
and insufficient declared workspace.

Device execution writes a fixed-size status record containing a closed status code, lifecycle plan
entry, canonical offending request/entity identity and generation where applicable, required and
available capacity, and bounded counters. Concurrent failures select the canonical first semantic
failure, never atomic arrival order. Host translation produces structured conflict, capacity,
generation, evaluator, invariant, and backend errors. Filtered inadmissibility counters and samples
publish only with a successful transaction; unbounded per-cell logging is excluded.

`inspect` reports lifecycle groups, effect/policy inventory, read/write/topology footprints, maximum
requests, persistent and scratch memory, RNG namespaces, required trackers/relationships,
checkpoint policy, kernel families, and backend support/rejection reasons. It does not expose live
registries, backend events, or private compiler object layout.

**Option B — throw generic `ArgumentError` values.**

This is easy but loses source-qualified compiler diagnostics and bounded device translation.

**Option C — retain a complete per-cell lifecycle event log by default.**

This creates large runtime storage, checkpoint questions, and performance overhead for diagnostics
that most runs do not need.

Decision: accepted by owner.

### LCI-R4-05 — Performance and specialization contract

**Option A — structural and allocation guarantees with measured timing (recommended).**

Compilation sizes reusable trigger masks, request buffers, canonical keys, scan/sort temporaries,
allocation maps, ownership staging, property/relationship staging, tracker repair, and device status
from finite model bounds. Warm lifecycle execution performs zero host and device allocations. The
normalized report exposes persistent, scratch, and peak lifecycle memory and the expected kernel
launch/synchronization boundary.

The batch implementation must avoid one whole-lattice scan per request. Creation touches its bounded
stencil; retire and transition are cell-local; relationship consequences scale with incident degree;
and one fused lattice pass may apply an entire valid remove/divide batch. Principal-axis geometry
uses declared generic geometry trackers or one shared batch reduction, not a separate lattice scan
for every parent. Complexity tests use counting sentinels rather than wall-clock assertions.

Effect, policy, evaluator, and storage structure may define descriptor groups; rule names, cell IDs,
state names, request occurrences, and capacities remain value-level. Fixed-group occurrence tests at
`1`, `32`, and `1024` must preserve plan type depth, evaluator signatures, and kernel-family count.
AcceleratedKernels primitives receive supplied reusable temporaries; a custom KernelAbstractions
scan/sort is added only with an equivalence test and measured reason.

End-to-end and kernel benchmarks report compilation, first invocation, warm phase time, memory,
allocations, transfers, synchronizations, and launches separately. R2 blocks on correctness,
boundedness, inference, allocation, or catastrophic measured regression—not a brittle absolute
wall-clock threshold tied to one laptop.

**Option B — impose absolute lifecycle timing thresholds in ordinary tests.**

This is machine-sensitive and recreates the expensive, finicky CI behavior already rejected.

**Option C — postpone every performance contract until after G7.**

This risks freezing an allocation-heavy or request-times-lattice transaction architecture.

Decision: accepted by owner.

### LCI-R4-06 — Test tiers and DRYness

**Option A — shared conformance modules with fast and qualification profiles (recommended).**

The default ordinary `Pkg.test` profile contains focused compiler rejection tests, CPU reference
microfixtures, sequential/checkerboard direct-phase equivalence, independent recomputation,
conflict/capacity/generation properties, checkpoint replay, one warm allocation assertion, and
compact external-extension CPU coverage. These are deterministic, small, and use Julia `Test`.

An explicit lifecycle qualification profile—invoked through the same package test entry point or a
small repository-owned qualification runner—adds the `1/32/1024` growth panel, full inference and
device compilation inspection, workgroup/boundary shapes, real-GPU execution, no-fallback checks,
and synchronized allocation/performance reports. Vendor environments inject only backend discovery,
arrays, conversion, synchronization, and capability/error translation into the same shared
conformance functions.

CorePotts tests transaction primitives once. PottsToolkit tests symbolic admission, lowering, and
public execution once. Shared fixtures and assertion functions prevent repeating the same lifecycle
trajectory in both packages or every vendor runner. Every effect and stable policy receives an
isolated exact test, while interactions use a risk-based covering matrix instead of the exhaustive
effect-by-policy-by-engine-by-backend Cartesian product. No evidence freshness, copied CI logs,
manual attestation renewal, or package-wide JET gate is introduced.

**Option B — put every compiler, GPU, and performance qualification in default `Pkg.test`.**

This maximizes immediate coverage but makes ordinary iteration slow and repeats hardware work on
unrelated changes.

**Option C — keep separate vendor-specific scientific suites.**

This duplicates semantics and lets GPU backends quietly qualify different models.

Decision: accepted by owner.

### LCI-R4-07 — Exact lifecycle exit matrix and R2 stopping rule

**Option A — bounded conformance matrix followed by the existing R2 review (recommended).**

G5-L implementation is complete only when the following pass:

1. syntax, completion, closure freezing, analysis, policy resolution, bounds, capability, and
   negative diagnostic fixtures;
2. one exact CPU microfixture for each of the five effects and every stable built-in placement,
   division, state, relationship, conflict, and inadmissibility policy;
3. common-snapshot, declaration/request permutation, conflict tie, complete-batch capacity,
   same-MCS non-reuse, ascending allocation, generation overflow, stale identity, and failure-
   atomicity properties;
4. ownership conservation/transfer and independent tracker, relationship-index, and post-lifecycle
   invariant recomputation after every structural effect;
5. exact semantic RNG addresses, unrelated-stream isolation, deterministic replay, independent
   replica divergence, and uninterrupted-versus-checkpointed continuation;
6. direct lifecycle equivalence on sequential CPU and checkerboard CPU from identical snapshots;
7. the downstream extension module through completion, execution, adaptation, checkpoint, replay,
   inference, and the real GPU witness with zero central CorePotts edits;
8. functional Metal execution of every lifecycle kernel/effect/policy family through the shared
   backend harness with scalar indexing disabled and no host semantic work; and
9. warm allocation, bounded workspace, locality, fixed-group specialization, compiler inspection,
   and measured performance reports.

After the current surface repair and G5-L both satisfy this matrix, one fresh independent
`R2Execution` reviews the complete G5 boundary: surface and other generic trackers, relationship
transactions, lifecycle, checkpoint, sequential/checkerboard behavior, adaptation, GPU legality,
and fallback absence. If R2 clears, work stops before G6 as previously agreed. A blocker returns
only to its earliest responsible gate; it does not authorize proof-model work or a new general
oracle/evidence system.

**Option B — exhaustively test every policy cross-product on every backend.**

This is stronger in raw case count but computationally wasteful and unlikely to find more defects
than isolated policy tests plus targeted interaction coverage.

**Option C — use Wortel and Merks reconstruction to decide whether lifecycle is complete.**

This moves G7 biology ahead of R2 and permits proof-model needs to shape the generic executor.

Decision: accepted by owner.

## Round 4 decision ledger

| ID | Decision | Status |
|---|---|---|
| LCI-R4-01 | Engine ownership | Accepted: one engine-neutral lifecycle execution plan |
| LCI-R4-02 | Functional GPU meaning | Accepted: complete device-resident transaction on one real witness |
| LCI-R4-03 | External extension conformance | Accepted: neutral downstream coverage of every claimed pure extension boundary |
| LCI-R4-04 | Diagnostics and inspection | Accepted: stable host diagnostics and bounded deterministic device status |
| LCI-R4-05 | Performance and specialization | Accepted: structural/allocation guarantees with measured timing |
| LCI-R4-06 | Test tiers and DRYness | Accepted: shared fast and qualification profiles |
| LCI-R4-07 | Exit matrix and R2 stopping rule | Accepted: bounded matrix, existing R2, stop before G6 on clearance |

## Accepted cross-round owner decision

### LCI-X-01 — GPU completeness before R2

Accepted: every structural lifecycle effect admitted into V1-L must be functionally supported on
the selected real GPU witness before R2. Merely declaring `gpu = false`, rejecting GPU compilation,
or falling back to host execution does not satisfy the gate.

The permanent conformance body must be backend-neutral. The available Apple Silicon environment may
qualify Metal as the functional witness; CUDA and AMDGPU remain unclaimed local hardware rows but
must invoke the same semantics from repository-owned environments for a later release matrix.

### LCI-X-02 — Fusion and fragmentation proposal

Withdrawn by owner before consolidation. V1-L does not admit `Fuse` (2 -> 1), `Fragment`
(1 -> N), arbitrary M -> N rewrites, or a general graph-rewrite surface. Their temporary
consideration establishes no future compatibility or IR requirement.

## Change isolation

This interview document is intentionally separate from the active surface-tracker implementation.
Until consolidation, it does not amend accepted compiler authority, open G6, change production code,
or authorize lifecycle implementation.

## Post-review owner disposition

The owner accepted the complete bounded repair package proposed after the first independent G5-L0
review. These decisions resolve the review's remaining owner questions without expanding V1-L:

| ID | Accepted disposition |
|---|---|
| LCI-R5-01 | A `ForbidExtinction` kind prevents ordinary final-site loss. Zero occupancy for such an active identity at lifecycle planning is a nonfilterable invariant failure. Only `RetireAtZero` synthesizes ordinary retirement, and no settled active zero-volume cell is publishable. |
| LCI-R5-02 | `on_inadmissible` is mandatory on all five structural effects. No omitted effect-specific disposition acquires scientific meaning. |
| LCI-R5-03 | V1-L event domains are `cells(kind)` and singleton `model()` only; placement may use finite site expressions without adding a site-iterated event domain. |
| LCI-R5-04 | Pure trigger, placement, binary-partition, and state-transform extensions require one complete versioned lifecycle-policy ABI and the existing frozen evaluator path. |
| LCI-R5-05 | Completion freezes registry/schema/callable selection, not Julia's future method table. Executable environment identity governs compatibility and requalification. |
| LCI-R5-06 | Relationship overrides normalize to canonical tuples before completion and fingerprinting. |
| LCI-R5-07 | The spec defines a complete host/device failure mapping and responsibility ownership, while concrete private view types and an exact file tree remain implementation choices. |

This acceptance authorizes specification consolidation and a fresh independent G5-L0 review only.
It does not authorize production lifecycle implementation, R2 handoff, G6, or proof-model migration.
