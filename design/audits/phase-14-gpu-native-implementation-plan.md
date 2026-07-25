# Phase 14 GPU-Native Implementation and Qualification Plan

Status: Owner-directed and accepted for execution

Date: 2026-07-24

Governing decisions:

- [Decision 0013](../../spec/decisions/0013-current-backend-contract.md)
- [Decision 0031](../../spec/decisions/0031-phase-14-single-semantic-kernel.md)
- [Decision 0032](../../spec/decisions/0032-phase-14-gpu-native-promotion.md)

## Objective

Every Phase 14 capability that becomes stable or supports a release published model will execute
with backend-resident authoritative state on CPU, Metal, and ROCm. The CPU implementation remains
the semantic reference. GPU execution is a production implementation of the same canonical model,
not a second runtime or an approximate host-assisted mode.

CUDA remains deferred. Host-side authoring, lowering, explicit observations, checkpoints, and
analysis are outside the simulation data plane and follow the bounded synchronization rules below.

## Difficulty and schedule

Overall difficulty is **high (8/10)**.

For one experienced contributor, the expected implementation effort is approximately:

| Work | Engineering estimate | Principal risk |
| --- | ---: | --- |
| Common device state/workspace substrate | 1–2 weeks | type-stable adaptation across every state family |
| Wortel Act Metal/ROCm closure | 1–2 weeks | atomic accepted-copy coupling and Metal numerical profile |
| Wang history/ODE/relationship/multirate/secretome slice | 3–5 weeks | bounded dynamic graph, field kernels, and deterministic transactions |
| First additional field model | 1–2 weeks | broadening Wang's field substrate to new boundaries, splitting, and mass balance |
| Remaining lifecycle/event/mapping breadth | 2–4 weeks | bounded queues, conflicts, and deterministic reductions |
| Hardware qualification and performance closure | 1–2 weeks, overlapping | real-hardware availability and backend compiler defects |

The realistic total is **9–13 engineer-weeks**, or roughly **7–10 calendar weeks** with parallel
Metal/ROCm qualification and prompt hardware access. The Act slice alone is moderate: about
one week for a first correct device path and another several days for qualification and evidence.
Dynamic relationships and event/lifecycle queues dominate uncertainty.

These estimates exclude full Phase 14.3 paper ensembles and collaborator review.

## GPU-native invariant

During unobserved stepping:

- all future-relevant scientific state is backend resident;
- state transitions use KernelAbstractions kernels or separately qualified device primitives;
- no `Array` conversion, scalar host indexing, host callback, host reduction, implicit
  synchronization, or host fallback occurs;
- steady-state stepping allocates no host or device memory;
- device-to-host traffic is zero; and
- host-to-device traffic is limited to an explicit parameter update whose semantic boundary is
  declared and fingerprinted.

At an observation or checkpoint boundary, only the declared result or checkpoint payload may
transfer. Transfer and synchronization metrics are evidence, not implementation details.

## Qualification profiles

Each stable law/storage/backend tuple receives a profile containing:

- semantic-model fingerprint and contract versions;
- backend family, device identity, driver/runtime, Julia, and package versions;
- numeric policy and precision;
- exact supported dimensions and boundary/relation families;
- primitive and vertical-slice evidence IDs;
- same-backend replay status;
- cross-backend comparison method and tolerance;
- checkpoint/restart result;
- allocation, synchronization, transfer, memory, compile-time, and warm-step measurements;
- device-code inspection record; and
- exclusions and actionable preflight diagnostics.

Portable qualification targets CPU/Metal/ROCm `Float32`. CPU `Float64` is a separate reference and
paper-fidelity profile. Exact cross-backend equality is required only for integer state, semantic
RNG addresses, ordering identities, and laws whose arithmetic contract is exact. Floating-point
trajectories use preregistered local, invariant, and statistical comparisons.

## Work packages

### G0 — Contract and harness

Deliver:

- `GPUQualified`/`GPURequiredForPromotion` backend dispositions derived from `SemanticModel`;
- transitive backend requirements derived after generic `ModelFragment` requirement/export
  resolution, with no fragment-local override or fallback;
- capability reports at state/law/storage/backend granularity;
- residency, allocation, synchronization, and transfer instrumentation;
- reusable CPU/Metal/ROCm test matrix and artifact schema;
- explicit host-boundary records for observations and checkpoints; and
- CI routing to real Metal and ROCm runners.

Gate:

- a deliberately unsupported law fails before mutation;
- equivalent explicit-leaf and fragment-packaged models produce identical backend preflight and
  qualification requirements;
- an advertised law cannot pass without both hardware evidence records; and
- an uncoupled Phase 13 model remains byte- and result-identical.

### G1 — Common device substrate

Deliver:

- `Adapt` support for site, history, continuous, relationship, field, delay, event, observation
  reducer, and lifecycle-request storage;
- backend-valid structure-of-arrays layouts with bounded capacities;
- preallocated transaction, reduction, queue, and solver workspaces;
- device-safe invariants and error/status buffers;
- device-to-host logical snapshots only at explicit boundaries; and
- backend-independent checkpoint restore followed by adaptation.

Gate:

- storage-tree validation on CPU, Metal, and ROCm;
- no scalar indexing or implicit `Array` conversion;
- zero warm-step allocation; and
- round-trip restart on each backend.

### G2 — Wortel GPU closure

Deliver:

- device-resident activity values and accepted-copy workspace;
- Act geometric-neighborhood energy in the production proposal kernel;
- atomic accepted-copy activation committed with ownership;
- backend-native saturating decay kernel;
- device activity observation reduction;
- GPU-capable `BudgetedSequentialCPM`; and
- Metal/ROCm continuation and preflight profiles.

Gate:

- accepted/rejected/no-op truth table on CPU, Metal, and ROCm;
- geometric-mean and decay-order fixtures;
- same-backend replay and uninterrupted-versus-restart equality;
- zero hidden transfer over an unobserved run;
- device code inspection; and
- real-hardware paper-scale memory/performance report.

Only after G2 passes may Wang implementation begin.

### G3 — Wang CPU/Metal/ROCm closure

G3 includes every execution capability required by Wang. In particular, Wang's secretome field is
not deferred to G4. Each reusable law is implemented and proven first through the ordinary
sequential CPU reference, then through backend-resident Metal and ROCm production paths over the
same canonical plan.

Deliver:

- device cell state and bounded ring histories;
- fixed-step Euler/Heun/RK4 kernels for the admitted per-cell systems;
- synchronous rule and mapping kernels;
- ordinary CPU and backend-resident Metal/ROCm evolving-field state and preallocated solver
  workspaces for the Wang two-dimensional periodic secretome profile;
- the source-compatible scaled field step: diffusion followed by medium constant-concentration
  enforcement in every substep;
- deterministic secretome uptake and calibration reductions that publish before the same-MCS ODE;
- bounded relationship graph in canonical structure-of-arrays form;
- deterministic focal-topology request generation plus accepted-copy conflict resolution and
  commit with Potts ownership;
- ten-MCS relationship retuning distinct from accepted-copy topology mutation;
- device-safe endpoint retirement and lifecycle cleanup;
- exact Potts/field/history/uptake/ODE/focal/alignment/force launch schedule with device-resident
  process state; and
- bounded observation reducers.

Gate:

- analytic ODE/history fixtures on sequential CPU, Metal, and ROCm;
- periodic diffusion, per-substep constant concentration, uptake, calibration, and field-balance
  fixtures on sequential CPU, Metal, and ROCm;
- relationship create/remove/retune, accepted-copy visibility, and capacity truth tables on all
  three backends;
- lifecycle generation/reuse rejection on all three backends;
- exact source-order and MCS 120, 210, and 211 visibility fixtures on all three backends;
- restart from every declared stable boundary on all three backends;
- no unobserved transfer, scalar host loop, host callback, or host fallback on either GPU;
- device-code, allocation, synchronization, transfer, and memory evidence on real Metal and ROCm;
  and
- Wang bounded-model correctness and performance profiles on sequential CPU, Metal, and ROCm.

Failure of any required backend leaves Wang Provisional and prevents G4 from opening. CPU
correctness cannot compensate for a missing or host-assisted GPU path, and GPU agreement cannot
compensate for a missing CPU reference.

### G4 — General field-model CPU/Metal/ROCm closure

G4 reuses the field state, periodic stencil, constant-concentration, uptake, and split-order
substrate already qualified by Wang. It broadens field semantics for the next selected field model;
it is not the first implementation of fields and cannot retroactively supply a missing Wang
capability.

Deliver:

- reusable backend-resident evolving fields and solver workspaces beyond the Wang profile;
- additional boundary-aware diffusion/reaction stencils;
- deterministic or explicitly qualified secretion/uptake reductions;
- cell/field exchange kernels;
- exact split-order execution;
- steady-state convergence status without host polling; and
- device field/geometry observation reductions.

Gate:

- manufactured solutions and analytic decay/diffusion on sequential CPU, Metal, and ROCm;
- mass/source/sink balance on all three backends;
- periodic, no-flux, and admitted fixed boundary fixtures on all three backends;
- split-order, overlap, and empty-domain truth tables on all three backends;
- checkpoint/restart on all three backends; and
- bounded selected-field-model correctness and performance profiles on sequential CPU, Metal, and
  ROCm.

### G5 — Remaining selected-model capabilities

Deliver:

- degradable site structures;
- device lifecycle request buffers and conflict resolution;
- sampled events and bounded delay queues;
- typed cross-domain mappings and reductions;
- staged protocols with device-resident future state; and
- any membrane remapping required by the frozen portfolio.

Root events, adaptive integration, DAEs, SDEs, reactions, jumps, and hybrid systems remain
Experimental unless separately promoted through the same CPU/Metal/ROCm process.

Gate:

- source-backed truth tables and Morpheus/foreign-runtime microfixtures;
- bounded-capacity overflow diagnostics before corruption;
- deterministic conflict ordering;
- lifecycle and queue continuation; and
- real-hardware selected-model smokes.

### G6 — Portfolio and release qualification

Deliver:

- a backend support matrix generated from evidence, never handwritten claims;
- GPU-native tutorial and published-model variants;
- paper-scale residency/memory/performance reports;
- archived Metal and ROCm conformance artifacts;
- current hardware reruns for release candidates; and
- explicit CPU `Float64` versus GPU `Float32` numerical-profile labels.

Gate:

- every stable Phase 14 execution row is qualified on CPU, Metal, and ROCm;
- no published model silently falls back to host execution;
- all requested observation/checkpoint transfers are visible in metrics; and
- Phase 13 GPU performance and correctness gates remain green.

## Capability disposition

| Capability group | GPU difficulty | Required implementation |
| --- | --- | --- |
| spatial roles and attempt budget | Low–moderate | adapt relations; device attempt accounting and RNG continuation |
| accepted-copy site state and Act | Moderate | device workspace, transaction hook, decay/reduction kernels |
| fixed-step continuous state/history | Moderate | SoA state, bounded rings, solver kernels |
| mappings and observations | Moderate | device reductions with explicit bounded publication |
| evolving fields and exchange | High | stencils, source reductions, split execution |
| relationships | High | bounded graph, deterministic request resolution |
| lifecycle/degradation | High | request buffers, atomic commit, generation-safe cleanup |
| sampled events/delays | High | bounded device queues and trigger memory |
| adapters and model construction | Host control plane | lower fully before launch; no runtime authority |
| checkpoints and downstream analysis | Explicit host boundary | bounded transfer only at declared stable boundary |

## Plan enforcement

The Phase 14 architecture checker must reject:

- `metal = "not_claimed"` or `rocm = "not_claimed"` on a stable-target contract;
- a D9 work item that does not require Metal and ROCm qualification;
- a capability row that permits stable CPU-only execution;
- a published-model release manifest containing an unsupported stable Phase 14 execution row; or
- a support claim without real-hardware evidence.

Experimental capabilities may remain unsupported, but their public status and preflight report must
make that limitation explicit.
