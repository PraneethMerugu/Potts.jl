# Decision 0039: Phase 16 Compute Ownership, Field Coupling, and Internal-Beta Scope

Status: Accepted architecture; Phase 16.A/B/D/E/F/G/H qualified, C hardware and I open

Date: 2026-07-27

## Context

ProcessBigraphs 0.4.0 has qualified its immutable-topology serial internal alpha. The next work
needs dynamic structure, a CorePotts adapter, arbitrary field-solver coupling, and real
CPU/Metal/ROCm field evidence. The previous roadmap treated G4 as a prerequisite and deferred
SciML integration to Phase 17. That ordering would freeze the adapter before the field and solver
protocols had been pressure-tested, and it obscured who controls computation.

The owner completed eight researched interviews and accepted all 481 recommended choices. The
interview record is
[`process-bigraph-phase16-owner-interview.md`](../../design/audits/process-bigraph-phase16-owner-interview.md).
The exact scope and evidence obligations are machine-readable in
[`process-bigraph-phase16-entry-v1.toml`](../process-bigraph-phase16-entry-v1.toml) and
[`process-bigraph-phase16-qualification-v1.toml`](../process-bigraph-phase16-qualification-v1.toml).

## Decision

### Authority boundary

ProcessBigraphs exclusively owns **when and why** computation occurs: logical time, scheduling,
invocation reason, stable identities, schemas, immutable input visibility, conflict policy,
authorization, publication, failure, observation, checkpoint, and replay.

An engine or solver owns **how** one authorized heavy operation occurs: algorithms, internal
steps, iterations, workspaces, caches, memory layout, device arrays, streams, launches,
preconditioners, and backend-specific optimization.

The runtime passes immutable versioned projections and an explicit operation contract to an
engine. The engine returns a completion handle and a staged opaque candidate or typed early
return. ProcessBigraphs validates and authorizes the result. Publication is allocation-free and
does no numerical work. A failed invocation publishes nothing.

### Solver-neutral protocol

ProcessBigraphs defines an open, solver-neutral Julia protocol without a hard SciML dependency.
Adapters declare supported operation families, field/problem envelopes, backends, precisions,
input modes, continuation/replay classes, residency, cancellation, and failure behavior.
Unsupported combinations fail at preflight.

Phase 16 proves the abstraction with:

1. the native CorePotts Cartesian field engine;
2. a CPU SciML field adapter; and
3. a minimal independent CPU custom adapter.

Broader ODE/DAE, ModelingToolkit, Catalyst/JumpProcesses, COBREXA/JuMP, FBA, and SBML ecosystem
work remains Phase 17. “Arbitrary solver” means an open protocol and independently qualified
adapters, not a claim that every solver works on every device.

The CPU SciML proof MUST inject a real solver algorithm and bounded canonical options. The adapter
MUST hand a real SciML problem to methods owned by the selected solver ecosystem; ProcessBigraphs
MUST NOT define a numerical `solve(::SciMLBase.ODEProblem, ...)` implementation. ProcessBigraphs
owns exact target authorization and transactional publication, while the selected algorithm owns
internal numerical steps, adaptivity, convergence, and caches. The initial generic continuation
policy reconstructs from published canonical state and claims numerical replay. Retained
integrators require a separately qualified codec/clone and invalidation contract.

The independent custom adapter is an external-style conformance fixture, not a second numerical
implementation shipped in ProcessBigraphs core. Cross-adapter proof uses analytic/manufactured and
convergence evidence rather than agreement between duplicated stepping loops. These refinements
are recorded in
[`process-bigraph-phase16f-solver-integration-consolidation-research.md`](../../design/audits/process-bigraph-phase16f-solver-integration-consolidation-research.md).

### Fields and splitting

Phase 16 admits prescribed, evolving, and externally supplied Cartesian 2D/3D fields with
separate logical descriptors and engine-owned realizations. It standardizes named species,
cell-centered geometry, units, physical-coordinate sampling and deposition, explicit per-face
boundary conditions, exchange and uptake laws, positivity and insufficiency policies,
conservation accounting, and exact logical clocks.

ProcessBigraphs owns the named operation schedule and visible split. Engines may fuse or internally
split computation only when the published boundary result remains equivalent. Undeclared
algebraic loops, hidden interpolation, clipping, transfer, fallback, and precision conversion are
errors.

### Dynamic hierarchy and CorePotts

The canonical ProcessBigraph ACSet stores orchestration topology. CorePotts retains optimized
domain topology for cells, lattice sites, materials, and relationships; Phase 16 does not create
one ACSet row per cell or voxel.

`AlgebraicRewriting.jl` becomes a direct bounded dependency. Stable structural operations are add,
remove, binary divide, move, and rewire. Typed structural requests are staged with numerical
results. ProcessBigraphs owns identity allocation, match identity, conflict selection,
preconditions, authorization, and publication of one immutable structural epoch. DPO-safe behavior
is the default. Raw unrestricted rewrites, implicit SPO cascade, merge, engulf, and burst are not
stable Phase 16 APIs.

CorePotts may execute compiled high-volume lifecycle kernels, but the behavior must agree with an
independent small AlgebraicRewriting reference on bounded fixtures. There is one lifecycle,
scheduler, state-publication, failure, and persistence authority.

### G4 disposition and devices

G4 is absorbed into Phase 16.C as the native field-substrate qualification gate. It is no longer a
precondition to starting Phase 16, but it remains mandatory for closure and cannot be replaced by
SciML, model-level evidence, or CPU-only tests.

The native field engine qualifies on sequential CPU, real Metal, and real ROCm. CUDA remains
deferred. SciML and the independent custom adapter qualify on CPU for their declared envelopes.
Every adapter publishes an honest backend/precision/problem/continuation/residency matrix.

Hidden host fallback, undeclared transfers, scalar host indexing, implicit narrowing, and
undeclared synchronization are forbidden. ProcessBigraphs authorizes placement and transfer;
engines own buffers and execution. Float32 is the portable device profile; CPU Float64 is separate.

### Merks and CNV

Phase 16 requires runnable source-bounded reimplementations of:

- the Merks et al. 2006 elongation/autocrine vasculogenesis model in 2D; and
- the Shirinifard et al. 2012 CNV scenario 38, including simulation-902 source tracing, in 3D.

Both models use the same generic field, solver, lifecycle, observation, checkpoint, and adapter
protocols. “Runnable” means build, preflight, initialize, advance, observe, checkpoint, restart,
and terminate. It does not mean full Figure 5/Figure 7 reproduction, full ensembles, recovered
analysis pipelines, or a publication claim.

### Persistence, failure, observation, and migration

Checkpoints are canonical logical ProcessBigraphs envelopes captured only at settled boundaries.
The Phase 16 format adds topology, epochs, identities, lineage, schedules, continuations, engine
descriptors, replay classes, and observation positions. Existing attested readers remain.
CorePotts legacy checkpoints convert non-destructively through registered versioned adapters.

Failures are deterministic fail-stop. Numeric and structural candidates, clocks, continuations,
RNG position, required observations, and records publish together or not at all. Retry is explicit
and limited to declared pure/idempotent work from the unchanged boundary.

Migration proceeds slice by slice. Each slice has one production authority. Old/new execution is
allowed only in differential qualification. After cutover there is no silent fallback; frozen
fixtures, legacy readers, and test-only oracles remain.

### Subgates

Phase 16 executes in this order:

- **16.A** — entry contract, dependency bounds, API claim, qualification ledgers, and checkers;
- **16.B** — solver-neutral engine protocol, field descriptors, exchange, splitting, continuation;
- **16.C** — absorbed G4 native field qualification on CPU, real Metal, and real ROCm;
- **16.D** — AlgebraicRewriting-backed dynamic hierarchy;
- **16.E** — CorePotts adapter, structural requests, checkpoint conversion, first cutover;
- **16.F** — CPU SciML and independent custom adapters plus cross-adapter evidence;
- **16.G** — runnable bounded Merks 2006 model;
- **16.H** — runnable bounded CNV scenario 38/model 902;
- **16.I** — reconciliation, documentation, compatibility, performance, exact-tree evidence, and
  internal-beta attestation.

After 16.B, 16.C and 16.D may proceed concurrently. Each retains independent evidence. No gate can
compensate for another.

### Maturity and closure

Phase 16 targets an unpublished ProcessBigraphs `0.5.0` internal beta. Closure requires every
required ledger row to be `qualified`, real-hardware Metal and ROCm evidence, independent dynamic
and field oracles, failure and restart evidence, at least one completed CorePotts cutover, runnable
Merks and CNV bounds, clean independent package tests, durable content-addressed evidence, and
exact merged-tree attestation.

The phase does not claim public release, complete pinned parity, Dagger, universal solver GPU
support, source-faithful assembled-model GPU support, full paper analysis, or whole-cell
qualification.

## Consequences

- Phase 16 can begin immediately without pretending G4 is already complete.
- Field coupling is a generic runtime/engine contract rather than a Merks- or CNV-specific loop.
- Optimized kernels retain device and numerical control without becoming schedule or publication
  authorities.
- SciML validates the open protocol early while broad scientific ecosystem work remains bounded.
- Dynamic orchestration topology and high-volume Potts domain topology remain distinct.
- The two required models pressure-test the architecture without expanding into full analyses.

## Supersession

This decision supersedes conflicting provisional roadmap or specification language that:

- makes G4 a prerequisite to starting Phase 16;
- freezes the generic field adapter only after an external G4 gate;
- defers the bounded CPU SciML field adapter to Phase 17; or
- implies CorePotts rather than ProcessBigraphs owns lifecycle scheduling or publication.

It does not alter frozen Phase 13, G3-B, Phase 15.C, published-source, or historical evidence.

## Rejected alternatives

- Completing G4 entirely before beginning the runtime adapter design.
- Moving optimized solver stepping or CPM lifecycle authority into ProcessBigraphs.
- Giving arbitrary callbacks direct published-state mutation.
- Requiring one universal solver API or universal GPU support.
- Representing every cell and voxel as orchestration ACSet structure.
- Letting CorePotts and ProcessBigraphs both schedule or persist a migrated slice.
- Calling either required model reproduced based on a bounded runnable implementation.
- Allowing a CPU, SciML, or model test to substitute for real Metal and ROCm G4 evidence.
