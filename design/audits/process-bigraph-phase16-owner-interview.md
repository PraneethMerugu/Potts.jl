# ProcessBigraphs Phase 16 Owner Interview

Status: Complete; all recommended choices accepted

Date: 2026-07-27

Decision count: 481

Post-interview refinement: the accepted
[Phase 16.HC high-level authoring interview](process-bigraph-phase16hc-high-level-authoring-owner-interview.md)
and [Decision 0040](../../spec/decisions/0040-process-bigraph-high-level-authoring.md) add the
mandatory authoring gate before 16.I without reopening this interview's compute-ownership,
solver-neutral, field, structure, device, or bounded-model decisions.

## Purpose

This interview resolves the architecture and evidence boundary needed to begin Phase 16 without
making G4 a separate prerequisite or turning ProcessBigraphs into a numerical kernel. The owner
accepted option A, or explicitly accepted the complete recommendation, for every question in all
eight rounds.

The governing principle is:

> ProcessBigraphs owns when and why computation occurs; optimized solver and CPM kernels retain
> control over how the heavy computation occurs.

The detailed normative result is
[`phase-16-engine-field-structural-and-adapter-semantics.md`](../../spec/phase-16-engine-field-structural-and-adapter-semantics.md).
This record preserves the interview topics, research basis, and accepted outcomes without
duplicating every normative sentence.

## Research basis

The interviews were prepared from primary documentation and papers:

- FMI 3.0 model-exchange and scheduled-execution lifecycle concepts:
  <https://fmi-standard.org/docs/3.0.2/>
- SciMLBase problem and solution interfaces:
  <https://docs.sciml.ai/SciMLBase/stable/>
- DifferentialEquations integrator interface:
  <https://docs.sciml.ai/DiffEqDocs/stable/basics/integrator/>
- CommonSolve solver-neutral vocabulary:
  <https://docs.sciml.ai/CommonSolve/>
- LinearSolve cache interface:
  <https://docs.sciml.ai/LinearSolve/stable/tutorials/caching_interface/>
- Julia package extensions:
  <https://docs.julialang.org/en/v1/manual/code-loading/>
- KernelAbstractions launch and synchronization semantics:
  <https://juliagpu.github.io/KernelAbstractions.jl/stable/quickstart/>
  and <https://juliagpu.github.io/KernelAbstractions.jl/stable/implementations/>
- DiffEqGPU backend constraints:
  <https://docs.sciml.ai/DiffEqGPU/stable/manual/choosing_ensembler/>
- Metal array and conversion behavior:
  <https://metal.juliagpu.org/stable/api/array/>
- AlgebraicRewriting concepts and executable examples:
  <https://algebraicjulia.github.io/AlgebraicRewriting.jl/dev/>
  and <https://algebraicjulia.github.io/AlgebraicRewriting.jl/dev/generated/full_demo/>
- Process Bigraph architectural paper:
  <https://pmc.ncbi.nlm.nih.gov/articles/PMC11312625.1/>
- Merks et al. 2006 primary paper:
  <https://biblio.ugent.be/publication/330448/file/2991951.pdf>
- Shirinifard et al. 2012 primary paper and supplements:
  <https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1002440>
- GitHub Actions self-hosted runner security and artifact attestations:
  <https://docs.github.com/en/actions/reference/security/secure-use>
  and
  <https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations>

These sources informed the options; they do not override the accepted Julia semantics.

## Round 1 — computation ownership

Accepted outcomes:

- ProcessBigraphs exclusively owns logical time, invocation reason, scheduling, identity,
  schemas, versions, visibility, authorization, publication, failure, and replay.
- Processes receive immutable versioned projections and explicit interval-input modes.
- Engines own arrays, caches, workspaces, low-level layout, buffering, streams, and kernels.
- The transaction is stage, complete, validate, authorize, then infallible allocation-free
  publication or abort.
- Large results may be an opaque versioned leaf candidate plus a small typed delta.
- Failures discard every candidate; engines surface typed early returns and global-impact events.
- Semantic RNG coordinates originate in ProcessBigraphs; optimized counters may implement them.

## Round 2 — arbitrary solver protocol

Accepted outcomes:

- The core defines a solver-neutral open Julia protocol with no hard SciML dependency.
- Operation families include interval advance, boundary solve, and discrete kernel or batch.
- An immutable adapter declaration creates a mutable, lineage-local opaque engine instance.
- The adapter owns construction, workspace, cache, buffers, algorithm resolution, and raw
  diagnostics; the runtime owns invocation and normalized outcomes.
- Solver internals may take arbitrary internal steps, iterations, callbacks, or launches but may
  not create ProcessBigraphs-visible state.
- Phase 16 proves the protocol with the native CorePotts field engine, one CPU SciML adapter, and
  one minimal independent custom adapter. Broader scientific solver families remain Phase 17.

## Round 3 — field state and coupling

Accepted outcomes:

- Logical field descriptors are separate from engine realizations.
- Phase 16 fields cover Cartesian 2D and 3D, cell-centered values, named species, explicit
  geometry, units, per-face boundary conditions, sampling, deposition, and exchange.
- Fields and the CPM may use independent grids connected by explicit physical-coordinate samplers
  and deposition laws.
- ProcessBigraphs owns the named operation split and visibility schedule; a solver may split only
  inside one invisible operation.
- Uptake, positivity, insufficiency, conservation, and nonconservative accounting are explicit.
- No undeclared algebraic loop, clipping, fallback, time interpolation, or field transfer is
  allowed.

## Round 4 — dynamic structure

Accepted outcomes:

- ProcessBigraphs maintains a canonical orchestration ACSet; CorePotts maintains optimized domain
  topology. Per-cell or per-voxel ACSet rows are not required.
- `AlgebraicRewriting.jl` is a direct Phase 16 dependency for orchestration add, remove, binary
  divide, move, and rewire.
- DPO-safe behavior is the default. Implicit SPO cascade and unrestricted raw rewriting are not
  stable APIs; SqPO cloning requires an explicit contract.
- Engines emit bounded typed structural requests. ProcessBigraphs owns matching identities,
  conflict selection, identity allocation, validation, authorization, and atomic structural epoch
  publication.
- CorePotts may compile high-volume lifecycle rules, but must match an independent small
  AlgebraicRewriting reference on bounded fixtures.
- Numeric and structural candidates commit together or not at all.

## Round 5 — Merks and CNV scope

Accepted outcomes:

- Both models must become runnable source-bounded reimplementations, not quantitative
  reproductions.
- Runnable means build, preflight, initialize, advance, observe, checkpoint, restart, and
  terminate through the generic ProcessBigraphs/CorePotts path.
- Merks targets the 2006 elongation/autocrine model in 2D. It includes the source-stated lattice,
  cell placement envelope, eight-neighbor CPM, local connectivity, inertia length, secretion,
  ECM-only decay, diffusion, chemotaxis, and 15 field steps per MCS.
- CNV targets scenario 38 and simulation 902 in 3D with its four fields, exact declared schedule,
  lifecycle, plastic relationships, and bounded Bruch's membrane state.
- Full paper figures, ensemble reproduction, classifier reconstruction, and publication analysis
  are explicitly outside Phase 16.

## Round 6 — devices and performance

Accepted outcomes:

- G4 is absorbed as the non-skippable Phase 16.C field-substrate gate.
- CPU, real Metal, and real ROCm qualify the native field engine; CUDA remains deferred.
- The SciML and independent custom adapters qualify on CPU in Phase 16.
- Every adapter publishes a backend, precision, problem, continuation, and residency matrix.
- Hidden host fallback, scalar host indexing, implicit transfers, implicit precision narrowing,
  and undeclared synchronization are forbidden.
- Float32 is the portable device policy; CPU Float64 is a separate profile, not universal truth.
- Future-state reductions are deterministic where exactness is claimed. Performance is guarded by
  frozen workload-specific regressions, not universal speedup claims.

## Round 7 — persistence, failure, observation, and migration

Accepted outcomes:

- Checkpoints occur only at settled ProcessBigraphs boundaries and use a new additive logical
  version containing topology, epochs, identities, lineage, schedules, and typed continuations.
- Existing attested readers remain. New writes use the ProcessBigraphs format; legacy CorePotts
  formats convert through pure, versioned, checksummed, non-destructive adapters.
- Replay is explicitly exact, numerical, statistical, or unsupported; a mixed checkpoint takes
  the weakest component class.
- Failure is deterministic fail-stop. Retry is explicit and only for pure/idempotent work from an
  unchanged boundary with the same semantic RNG identity.
- Required observations participate in publication. External sinks declare staging,
  idempotency, delivery, backpressure, and recovery.
- CorePotts migration is a strangler cutover: one production authority per slice, old/new
  differential evidence before cutover, and no silent fallback afterward.

## Round 8 — evidence and closure

Accepted outcomes:

- Phase 16 has subgates A through I and closes only as one internal-beta candidate.
- The machine-readable control plane consists of an entry contract, qualification ledger,
  capability/backend matrix, migration registry, and model-scope registry.
- Every requirement has a stable identity and evidence dimensions for semantics, dependencies,
  implementation, oracle, tests, failure, persistence, backend, documentation, and provenance.
- Ordinary CI runs entry/schema checks, clean package tests, CPU oracles, differential tests,
  bounded model fixtures, and static guards. Real Metal and ROCm are required for Phase 16.C and
  final closure but never run untrusted fork code.
- Closure requires an exact-head candidate, durable content-addressed evidence, a clean tree,
  exact merged-tree verification, and a metadata-only attestation.
- Internal beta is provisionally ProcessBigraphs `0.5.0`, remains unpublished, and does not claim
  full analysis, universal GPU solver support, Dagger, complete parity, or public release.

## Final disposition

The interviews are complete. G4 is no longer a pre-Phase-16 blocker; it is Phase 16.C and cannot be
skipped or compensated for by another gate. The repository is ready to begin Phase 16.A when the
entry checker for the accompanying specification packet passes. Implementation closure must remain
open until every required qualification row reaches `qualified`.
