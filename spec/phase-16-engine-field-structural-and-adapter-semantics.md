# Phase 16 Engine, Field, Structural, and Adapter Semantics

Status: Normative pre-implementation specification

Version: 1.0.0

Date: 2026-07-27

Authority: Decision 0039, the Phase 16 owner interview, entry contract, qualification ledger,
backend matrix, and migration registry

## 1. Purpose and claim boundary

This specification defines the Phase 16 internal-beta contract. It extends the qualified
immutable-topology serial semantics; it does not replace them. Phase 15.C exact time, common
snapshot visibility, deterministic reconciliation, semantic RNG, transactional failure,
observation, continuation, checkpoint, and independent-oracle rules remain normative.

Phase 16 is complete only when every required row in the qualification ledger is qualified.
Specification passage means implementation may start. It is not implementation evidence.

The keywords MUST, MUST NOT, REQUIRED, SHOULD, SHOULD NOT, and MAY are normative.

## 2. Ownership invariant

ProcessBigraphs MUST be the only authority for:

- logical time, invocation selection, invocation reason, and interval;
- stable process, field, structural, lineage, event, and observation identities;
- logical schemas, versions, epochs, fingerprints, and visibility;
- immutable input projections and declared input-time interpretation;
- structural conflict selection and identity allocation;
- result validation, authorization, atomic publication, and abort;
- semantic RNG addressing;
- required observation, checkpoint, failure, and replay classification.

An engine MUST retain control over:

- numerical algorithm and low-level discretization;
- internal steps, iterations, convergence tests, callbacks, and preconditioners;
- arrays, layout, caches, workspaces, scratch, double buffering, and opaque handles;
- device buffers, kernels, queues or streams, launches, fusion, and local synchronization;
- raw diagnostics and engine-specific continuation representation.

No adapter, solver, CorePotts kernel, AlgebraicRewriting operation, observer, or emitter may become
a second scheduler, lifecycle, publication, or persistence authority.

## 3. Transactional engine invocation

### 3.1 Declaration and instance

An engine adapter has:

1. an immutable declaration that contributes to model and runtime fingerprints; and
2. a mutable opaque instance owned per lineage or explicitly declared sharing domain.

The declaration MUST identify adapter type and semantic version, operation families, problem
envelope, algorithms or algorithm-resolution policy, precisions, backends, residency, input modes,
boundary support, continuation and replay classes, cancellation, diagnostics, failure behavior,
and required bridges.

Adapter construction and problem lowering occur outside the numerical hot path. Runtime dispatch
MUST be type-stable for the qualified path. Extension adapters use ordinary Julia dispatch and MAY
use Julia package extensions; ProcessBigraphs core MUST NOT hard-depend on SciML.

### 3.2 Operation contract

Stable operation families are:

- `interval_advance` — advance from exact logical start to target;
- `boundary_solve` — solve a declared steady or boundary problem for one event;
- `discrete_batch` — perform one bounded kernel or batch operation; and
- operation-specific extensions that preserve the same transaction.

An invocation includes stable identity, canonical reason, exact start and target times, structural
epoch, immutable versioned input projections, input-time mode, semantic RNG root/address context,
resource authorization, and expected output/diagnostic schemas.

The engine returns either:

- a completion handle for a staged opaque candidate and small typed effects;
- a typed early return with actual reached time and reason;
- a typed global-impact event request; or
- a structured failure.

The runtime follows:

`stage -> complete -> validate -> authorize -> publish`

or:

`stage -> complete/fail -> discard -> abort`

Publication MUST be allocation-free, transfer-free, synchronization-free, and free of numerical
work. A candidate may not be externally visible before authorization. Failure discards numeric,
field, structural, continuation, RNG, clock, observation, and required-record candidates together.

### 3.3 Solver control and early returns

An engine controls internal steps and iterations. An internal callback may alter only engine-local
candidate state. A callback that changes global scheduling or structure MUST surface a typed event
request; it cannot mutate published state.

An interval operation MUST reach the exact target or return a typed early result. Silent
overshoot, undershoot, extrapolation, or target rounding is forbidden. ProcessBigraphs determines
what the early result means for scheduling.

### 3.4 Capabilities and unsupported combinations

Preflight MUST reject unsupported combinations before mutation. Capability declarations are
specific to adapter, semantic version, problem envelope, backend, precision, continuation/replay
class, residency, and bridge set. Compilation or successful method dispatch is not qualification.

“Arbitrary solver” means any third party may implement the protocol and qualify a declared
envelope. It does not mean every solver, algorithm, callback, or backend is supported.

## 4. State, continuation, and diagnostics

ProcessBigraphs owns logical field identity, schema, version, time, publication, and canonical
serialization. Engines own bulk realizations and transient state.

Engine state is classified:

- **canonical logical state** — serialized by ProcessBigraphs;
- **typed continuation** — engine representation with runtime-owned identity, schema, version,
  codec, compatibility, replay class, and invalidation policy;
- **reconstructible cache/workspace** — not serialized;
- **diagnostic state** — normalized status plus preserved raw adapter diagnostics; or
- **opaque unsupported state** — disqualifies checkpoint/restart for that envelope.

Continuation actions are `preserve`, `transform`, `reinitialize`, `reconstruct`, or `reject`.
Resize and topology changes require an explicit capability. Silent cache reuse after an invalidating
change is forbidden.

Replay classes are `exact`, `numerical`, `statistical`, and `unsupported`. Aggregate replay takes
the weakest component class.

## 5. Field contract

### 5.1 Descriptor and realization

A field consists of:

- an immutable semantic descriptor;
- a published logical state/version; and
- an engine-owned realization.

Prescribed, evolving, and external fields share the descriptor. The Phase 16 stable envelope is
Cartesian 2D and 3D with named species and native cell-centered placement. Other placements,
unstructured meshes, FEM, AMR, and moving meshes are reserved.

The descriptor MUST include:

- stable field and species identities;
- rank, dimensions, numeric type, and units or declared dimensionless normalization;
- physical origin, spacing, extent, and axis order;
- placement and interpolation/sampling law;
- per-face boundary condition and parameters;
- governing operation/problem identity;
- positivity, conservation, insufficiency, and accounting policies;
- backend/residency requirements; and
- semantic field time and version.

Symbolic or geometric incompatibility MUST fail before execution.

### 5.2 Boundaries

Phase 16 admits periodic, Dirichlet, Neumann, and explicitly declared mixed faces. Field boundaries
are independent from CPM boundaries. Every face is explicit; no solver default becomes semantic.

### 5.3 Sampling, deposition, and exchange

Sampling and deposition use physical coordinates and named laws. A CPM lattice and field grid MAY
differ in shape and spacing. Grid equality cannot be assumed by a generic adapter.

PDE evolution, secretion/deposition, uptake/exchange, reservoir behavior, and sampling are separate
operation concepts. For every exchange the model declares:

- source and destination quantities and units;
- spatial footprint and weighting;
- allocation when consumers compete;
- insufficient-material behavior;
- positivity behavior;
- conservative or nonconservative classification; and
- accounting residual and tolerance.

Secretions are ephemeral forcing unless a durable accumulator is explicitly modeled. Silent
clipping is forbidden. A nonconservative operation reports the declared source or sink.

### 5.4 Time and splitting

Field time is explicit and may differ from CPM substep time while sharing exact ProcessBigraphs
logical clocks. An input is frozen, interpolated, event-updated, or continuously callable only if
declared and supported.

ProcessBigraphs owns the globally visible operation graph and split. Presets lower to canonical
named operations. A solver owns internal numerical splitting that is invisible outside its
invocation. Fusion is allowed only with evidence of boundary equivalence.

An algebraic feedback loop must be represented as a named bounded iterative region or rejected.
There is no universal default CPM/field split.

## 6. Structural transactions

### 6.1 Two topology layers

The canonical orchestration topology is a ProcessBigraph ACSet containing composites, stores,
processes, ports, links, containment, schedules, and stable identities. CorePotts domain topology
contains cells, sites, relationships, and materials in optimized leaf representations.

Both layers are under ProcessBigraphs transaction authority. Domain topology does not require
per-cell or per-site ACSet rows. A derived read-only inspection view MAY expose it. Per-cell
ProcessBigraph promotion is explicit and opt-in.

### 6.2 Stable operations and rewrite semantics

Stable structural operations are:

- add;
- remove with explicit owned closure;
- binary divide;
- move without identity change; and
- rewire without implicit movement.

Orchestration operations lower to `AlgebraicRewriting.jl` rules. DPO-safe behavior is the default.
Implicit SPO cascade is forbidden. SqPO contextual cloning requires an explicit rule and
qualification. Raw unrestricted rule execution is experimental and not an internal-beta API.

AlgebraicRewriting may discover or apply a staged candidate, but ProcessBigraphs assigns semantic
match identity, validates application conditions and resource constraints, selects conflicts,
allocates identities, authorizes the result, and publishes one immutable structural epoch.

### 6.3 Structural requests

An engine emits a bounded typed request containing operation/rule identity, source and target
identities and generations, source epoch, payload, dependencies, and requested policies. Bulk
device buffers are allowed behind a declared adapter boundary. Engines cannot publish topology.

Requests observe the common pre-structural snapshot unless the schedule explicitly stages them.
Semantic match identity derives from rule, epoch, and stable model identities; discovery order and
ACSet row order are nonsemantic.

Independent matches MAY commit in one transaction. Conflicts use an explicit stable priority or
composition law. An unresolved conflict aborts.

### 6.4 Identity and lifecycle

ProcessBigraphs owns a deterministic identity allocator that MAY be compiled into an engine
kernel. Identity is stable ID plus generation. Lineage records birth/division event and parent;
ancestry observations are optional.

An ID is not reused at the same settled boundary. On binary division the parent retains its
identity and one daughter receives a fresh identity. Daughter state, relationships, schedule,
bindings, and continuation use explicit policies. Insufficient capacity aborts the whole batch
unless a qualified resize policy exists.

Add initializes state, bindings, schedule, and continuation; its first run occurs at the next
scheduler selection. Remove declares owned closure and resource cleanup; no implicit cascade is
permitted. Numeric and structural candidates validate and publish atomically.

### 6.5 Compiled CorePotts lifecycle

CorePotts MAY evaluate heavy geometry, trigger, relationship, and lifecycle kernels using
ProcessBigraphs-declared semantics. It returns requests plus an opaque candidate. High-volume
compiled rules MUST agree with an independent AlgebraicRewriting reference on exhaustive small
fixtures, including candidate-order invariance, conflicts, capacity failure, and restart.

Bruch's membrane degradation is bounded domain material state unless a registered source operation
explicitly changes orchestration topology.

## 7. Backend, precision, residency, and performance

### 7.1 Qualification matrices

Every adapter publishes a matrix over:

- operation/problem envelope;
- backend;
- precision;
- residency;
- continuation/replay class;
- transfer/bridge requirements; and
- status and evidence.

The minimum stable Phase 16 envelopes are:

| Adapter | CPU | Metal | ROCm |
| --- | --- | --- | --- |
| Native CorePotts field engine | required | required on real hardware | required on real hardware |
| SciML field adapter | required | not claimed | not claimed |
| Independent custom field adapter | required | not claimed | not claimed |
| Merks full source-faithful assembly | required | not claimed | not claimed |
| CNV full source-faithful assembly | required | not claimed | not claimed |

Reusable Merks/CNV mechanisms must separately qualify on every applicable native backend.

### 7.2 Residency and synchronization

One engine instance uses one device in Phase 16. Distributed and multi-GPU execution remain
deferred. Unified memory is experimental and explicit.

Engine instances own device buffers. ProcessBigraphs owns placement and transfer authorization.
During an unobserved interval all future state remains at declared residency. Hidden `Array`
conversion, scalar host indexing, host fallback, implicit narrowing, and undeclared transfer are
forbidden.

High-frequency exchange is co-resident or uses a qualified measured device bridge. Borrowing is
typed, backend-specific, immutable by default, and lifetime-bounded. Observation and checkpoint
may transfer only their declared payloads.

Completion handles are asynchronous. The runtime waits only at declared semantic boundaries;
engines own streams and local dependencies. Device-side validation must not allocate or transfer.

### 7.3 Precision and reproducibility

Float32 is the portable device profile. CPU Float64 is a separate declared profile. Fast math is a
named non-default profile.

Integers, identities, exact clocks, schedules, topology, semantic RNG coordinates, and canonical
serialization are exact across qualified backends. Floating results use per-quantity declared
tolerances unless an algorithm explicitly qualifies exact equality. Future-state reductions use a
deterministic law for strict profiles; unordered floating atomics cannot support an exact claim.

Preflight checks range and overflow. CPU Float64 is a reference profile, not an unquestioned truth
oracle.

### 7.4 Performance

The native field engine must have zero steady-state allocation in its qualified hot loop.
External adapters declare and measure allocation rather than inheriting that claim. Workspaces are
created before timed steady execution.

Evidence distinguishes cold construction, compilation, initialization, warm execution,
observation, and checkpoint. GPU timing synchronizes correctly and records hardware, driver,
runtime, memory, and compilation metadata. Regression budgets are frozen per workload; no
universal speedup is required. Tuning cannot weaken semantics.

## 8. Persistence, failure, and observation

### 8.1 Checkpoint

ProcessBigraphs alone authorizes checkpoints, after every migrated slice is settled. A checkpoint
cannot capture an in-flight solver operation, partial MCS, or partial rewrite.

The Phase 16 logical checkpoint version includes committed logical state and time, orchestration
and domain topology, structural epoch, stable identities and generations, lineage, schedules,
typed continuations, semantic RNG position, observer positions, engine declarations, replay
classes, fingerprints, and registered identity maps. It excludes transient arrays, caches,
workspaces, streams, tasks, and backend memory layouts.

All attested readers remain supported until an explicit incompatible release decision.
New writes use the ProcessBigraphs format. Legacy CorePotts readers live behind adapter
conversions. Conversion is pure, registered, versioned, checksummed, transactional,
non-destructive, and changes only execution/checkpoint evidence when scientific meaning is exact.

Load validates schemas, bounds, checksums, compatibility, capacities, and migrations before
mutating a destination. Failed load leaves the destination unchanged. Cross-backend or
cross-precision import has an explicit replay downgrade.

### 8.2 Failure

Default failure is deterministic fail-stop with no implicit retry. A failure records schema
version, code, stage, owner, logical time, event identity, last stable fingerprint, raw diagnostic
reference, retry class, and ordered secondary failures.

An engine that may be poisoned after failure is reconstructed. Cancellation is cooperative and
adapter timeouts are explicit. Cleanup cannot mutate published state. External side effects
declare idempotency or compensation.

Retry is allowed only by an explicit runtime policy for pure/idempotent work from the unchanged
settled boundary with unchanged semantic RNG coordinates.

### 8.3 Observation

Observers are read-only, use an isolated RNG namespace, and cannot trigger lifecycle. Required
observations participate in atomic publication; telemetry follows a bounded declared drop or
backpressure policy.

Every logical record has an idempotency identity derived from run, observer, schema, event, time,
epoch, and result. External sinks declare staging, delivery semantics, idempotency, backpressure,
and recovery. Core claims exactly-once logical record formation, not universal transactional
external delivery.

Observation schemas include units, axes, provenance, and numeric policy. Device reductions happen
on device; full snapshots require an explicit budget. Observer continuation is checkpointed.

## 9. CorePotts strangler migration

Migration is registered per vertical slice:

1. freeze the old path and fixtures;
2. implement the ProcessBigraphs lowering;
3. run old and new paths only in differential tests;
4. compare state, time, ordering, RNG, lifecycle, topology, observations, failures, diagnostics,
   checkpoints, and remaining trajectory after every restart cut;
5. qualify the declared exact or numerical/statistical relation;
6. cut over to one production authority; and
7. remove the old production implementation while retaining frozen fixtures, readers, and
   test-only oracles.

There is no automatic fallback to the old path after cutover. Rollback is a release/code rollback,
not simultaneous dual authority. `ProcessBigraphs.jl` MUST NOT depend on CorePotts or PottsToolkit.

## 10. Required model envelopes

### 10.1 Merks 2006

The required model is the 2006 elongation/autocrine vasculogenesis model, not the distinct 2008
contact-inhibition model. Its source-bounded assembly includes:

- a 500 by 500 2D lattice at 2 micrometers per site;
- 282 endothelial cells placed in the central 333 by 333 region;
- eight-neighbor copy relation and one attempt per lattice site per MCS;
- temperature 50, contact values `Jcc = 40`, `JcM = 20`, and frozen-border `JcB = 100`;
- area, inertia-based length, and the paper's local-connectivity rejection behavior;
- cell-site secretion, ECM-only decay, diffusion, chemotaxis, and matched field geometry;
- 15 field steps per MCS, 2 seconds per field step, and 30 seconds per MCS;
- `D = 1e-13 m^2/s` and secretion/decay rates `1.8e-4 /s`; and
- explicit named reference split plus sensitivity profiles where source ordering remains
  ambiguous.

Required evidence includes source traceability, mechanism microfixtures, canonical-domain startup,
a bounded scheduled trajectory, native/SciML field execution, invariants, field balance, shape and
connectivity observations, checkpoint/restart, and failure rollback. Unknown original seed and
placement algorithm remain explicit profiles. Full Figure 5 ensembles and image-analysis
reconstruction are not required.

### 10.2 CNV scenario 38

The required model is Shirinifard et al. scenario 38 with simulation 902 as the source microfixture:

- 40 by 40 by 35 voxels at 3 micrometers, periodic x/y and no-flux z;
- oxygen, RPE VEGF, EC VEGF, and MMP fields;
- oxygen steady-state solve and the source field schedule including 12 extra VEGF2 steps;
- tip/stalk phenotypes, hypoxia timers, growth, contact inhibition, division, phenotype change,
  and death;
- dynamic breakable plastic relationships;
- bounded Bruch's membrane material/degradation state;
- source seed 498377 for simulation 902;
- full configuration capable of 146000 MCS and observations every 100 MCS; and
- reduced deterministic fixtures that cover transitions including MCS 400.

The source archive is fetched and checksum-verified in a separate source lane and is not vendored.
Ordinary CI uses generated clean-room fixtures. Required evidence includes machine-readable
source/mechanism traceability, reduced lifecycle/relationship/degradation fixtures, full-domain
startup and bounded advance, checkpoint/restart, rollback, and raw/mechanistic observations.
The full ten-replicate analysis, morphology classifier, and full-year CI run are not required.

## 11. Evidence, CI, and closure

Every requirement has a stable ledger identity and statuses `not_started`, `specified`,
`implemented`, `oracle_passing`, `qualified`, `blocked`, or `excluded`. Tests alone cannot produce
`qualified`.

Required methods include:

- analytic and manufactured field solutions, refinement, boundary, conservation, and split tests;
- native/SciML/custom cross-adapter comparisons;
- independent Julia structural oracle and exhaustive bounded rule cases;
- property, metamorphic, fuzz with recorded seed and shrink, and targeted mutation tests;
- failure injection at every stage;
- restart at every reachable settled boundary in bounded fixtures;
- old/new CorePotts differential execution;
- negative capability and hidden-transfer tests;
- source microfixtures separately from assembled-model tests; and
- package-independent clean installation and tests.

Ordinary CI MUST be network-free for scientific assets and MUST NOT run untrusted forks on
self-hosted hardware. Real Metal and ROCm evidence is required before Phase 16.C and Phase 16.I
qualification. If hardware is unavailable the relevant gate remains open; CPU work may continue.
CUDA is diagnostic and non-gating.

Closure uses an exact-head candidate artifact followed by merged-tree verification and a
metadata-only attestation. Evidence is content-addressed and records repository tree, Julia and
package resolution, OS, architecture, CPU/GPU model, memory, driver, runtime, backend, precision,
algorithm, workload, model/runtime/observation fingerprints, seeds, tolerances, results, commands,
and CI identity. Provenance attestation supports artifact origin; it does not prove scientific
validity.

## 12. Subgate entry and exit

- **16.A** exits when this packet, dependency bounds, bounded API claim, checker, and registries
  agree.
- **16.B** exits when the generic engine and field protocols pass CPU microfixtures and failure,
  continuation, and restart tests.
- **16.C** exits only with native field CPU, real Metal, and real ROCm qualification.
- **16.D** exits with the stable structural set, independent rewrite oracle, fuzz, failure, and
  exact restart.
- **16.E** exits with the first CorePotts cutover and legacy checkpoint conversion.
- **16.F** exits with CPU SciML, independent custom adapter, and cross-adapter evidence.
- **16.G** exits with the bounded runnable Merks contract.
- **16.H** exits with the bounded runnable CNV contract.
- **16.I** exits with full ledger reconciliation, documentation, performance evidence, clean
  dependency resolution, exact-tree candidate, and internal-beta attestation.

After 16.B, 16.C and 16.D may overlap. No subgate substitutes for another.

## 13. Explicit exclusions

Phase 16 excludes public release, complete pinned parity, Dagger or distributed qualification,
multi-GPU execution, CUDA qualification, universal third-party solver GPU support, moving mesh,
FEM, AMR, merge/engulf/burst/general rewrite, implicit structural cascade, arbitrary mid-event
restart, full Merks or CNV publication analysis, full source-ensemble reproduction, mandatory
source-faithful assembled-model GPU execution, AlgebraicDynamics, broad biochemical/FBA/SBML
adapters, and whole-cell qualification.
