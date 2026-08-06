# Decision 0025: Phase 9 SciML and GPU Interface Contract

Status: Accepted

Current disposition: superseded in part by [Decision 0044](0044-pre-g6-cohesion-and-mtk-hardening.md)
for problem ownership, late numerical lowering, ensemble integration, and capability profiles.
Compatible integer-MCS SciML semantics survive.

Date: 2026-07-19

## Context

Phase 9 introduces the final `PottsProblem`, `PottsIntegrator`, and `PottsSolution` interface over
the qualified CorePotts engine. The interface must be genuinely useful in the SciML ecosystem
without pretending that integer-MCS Cellular Potts dynamics are adaptive differential equations.
It must preserve GPU residency, semantic RNG addressing, scientific ownership, open extension
protocols, and the replacement engine's performance.

The current repository still contains historical types with the final public names, a frozen
PottsToolkit compiler bridge, closed concrete-family dispatch in several paths, and no complete
SciML problem/solve/solution implementation. Implementing the surface in one change would mix name
ownership, scientific state, execution, observation, persistence, and ensemble risks.

## Decision

### Ownership and construction

- Historical `PottsProblem`, `PottsIntegrator`, and `PottsSolution` types are renamed to internal
  legacy names before the replacement receives those names permanently. The frozen PottsToolkit
  bridge may return legacy values until Phase 10 parity, but gains no new behavior.
- `PottsModel` is reusable scientific meaning. Immutable `PottsProblem` binds `model`, `u0`,
  geometry, nonnegative integer `tspan`, typed parameters, fixed capacity, and a master seed.
- The canonical constructor defaults to deterministic `seed = 0`. Mutable host `u0` is copied;
  expert device state has explicit copy or restricted alias ownership.
- Capacity may be inferred exactly only when the model cannot create cells. Creation-capable models
  require it explicitly, and live GPU state never resizes.
- Construction and `init` use staged aggregate validation. Parameters are classified as runtime,
  shape, structural, or measured compile-time-static data.

### Execution and extension protocols

- `solve(prob, alg)` is behaviorally `solve!(init(prob, alg))`; `init` performs no MCS. The default
  algorithm is sequential and the default portable backend is CPU. GPU use never silently changes
  scientific dynamics and receives one pre-execution informational notice when sequential is used.
- One public `step!` completes exactly one full MCS including mechanics, lifecycle, observations,
  saves, callbacks, and bookkeeping. `solve!` loops that same operation. Adaptive/tolerance options,
  floating steps, unknown keywords, and solve-time seed overrides are rejected.
- Algorithms, proposal laws, backend requirements, RNG extension namespaces, and compiled
  components use open typed dispatch. Device lowering produces concrete bounded descriptors and
  workspaces; kernels contain no dynamic host machinery.
- `PottsIntegrator` implements the applicable common SciML surface but is not represented as a
  `DEIntegrator`. Terminal stepping throws; solving an already terminal integrator is idempotent.

### Reuse, output, callbacks, and persistence

- `remake` returns a new problem and uses distinct scientific fingerprints and structural
  compilation keys. An optional explicit thread-safe `PottsCompilationCache` contains reusable
  compilation artifacts only, with no global singleton, disk cache, trajectory state, or automatic
  eviction in the first version.
- Saving defaults to start and end snapshots only. Exact integer `saveat` is supported; interpolation
  is not. Default snapshots are independent copies on the execution backend, so GPU snapshots stay
  resident. `PottsSolution` provides exact saved-index/time lookup, structured retcodes, statistics,
  provenance, and storage metadata without hidden observation.
- Standard `DiscreteCallback` and `CallbackSet` values are host callbacks and share one immutable
  host snapshot and synchronization boundary per due MCS. Typed device callbacks declare bounded
  observations and control effects and remain resident. Biological events are model components,
  not callbacks; callback controls cannot mutate raw biological state.
- Exact checkpoint restore returns a normal `PottsIntegrator` through the same initialization path
  after complete compatibility checks. Checkpoints are separate from solution snapshots. Logical
  import creates a new portable problem and does not claim exact continuation.

### Ensembles and ecosystem boundaries

- A thin Potts adapter delegates scheduling to SciMLBase ensembles. `EnsembleSeedDerivationV1`
  derives schedule-independent trajectory seeds from a realized master seed, trajectory identity,
  rerun identity, and version. The user `prob_func` runs before automatic seed remake unless an
  explicit user-managed policy is selected.
- CPU serial, threaded, and distributed execution, plus serial independent Metal and ROCm
  trajectories, are the initial qualified ensemble modes. Same-device threaded GPU, multi-GPU, and
  whole-ensemble batched kernels require separately named qualification.
- Typed parameter and observable handles support applicable symbolic indexing without device
  dictionaries. Generic AD through `solve` is rejected. Portable problems may be distributed;
  integrators, device workspaces, and live caches are not serialization formats.
- Phase 9 carries accepted static/exogenous field state but does not invent PDE evolution,
  secretion, uptake, or operator-splitting APIs. Those belong to a separate evolving-field phase
  after the paper core unless explicitly promoted by a required paper experiment.

### Performance and qualification

- A warm unobserved SciML MCS adds zero kernel launches, synchronizations, transfers, device
  allocations, state copies, or RNG draws over the direct engine. After initialization and warmup,
  ordinary MCS execution allocates no host or device memory except for requested outputs.
- Benchmarks separate load, construction, cold/warm initialization, first/warm MCS, direct-versus-
  SciML overhead, solve, observations, callbacks, checkpoints, remake, and ensembles.
- Structural performance budgets are hard pull-request gates. Timing distributions use dedicated
  runners; after baselines are accepted, a supported workload may not regress by more than 5%
  without an explicitly reviewed scientific or engineering reason.
- Qualification targets Julia 1.12.6 on Linux x86_64 CPU, macOS arm64 CPU/Metal, and Linux
  x86_64/ROCm, in 2D and 3D with scalar indexing disabled and representative paper workloads. CUDA
  remains deferred until separately added to the backend contract.

## Consequences

- Phase 9 is a staged replacement of ownership and execution contracts, not a compatibility layer
  over the old API.
- SciML users receive familiar construction, solving, remaking, callback, solution, ensemble, and
  symbolic-index behavior where it is scientifically meaningful.
- GPU execution remains resident by default; transfers and synchronizations arise only from declared
  host observations, persistence, or explicitly synchronized modes.
- Open protocols remain extensible Julia dispatch on the host and concrete bounded data on devices.
- Evolving PDE fields and generic differentiation cannot silently expand or delay the paper-core
  refactor.

## Alternatives Considered

- Keep the legacy final names and introduce a temporary `ScientificPottsProblem` family.
- Copy generic ODE solver keywords and callback behavior even where CPM semantics are undefined.
- Store backend, algorithm, or tuning policy inside immutable scientific model meaning.
- Use global caches, mutable problem state, task-local RNGs, or scheduler-dependent ensemble seeds.
- Materialize every save or callback state on the host.
- Implement Phase 9 as one large change or include speculative PDE coupling in the same phase.

These alternatives increase ambiguity, GPU synchronization, invalid reuse, reproducibility risk, or
legacy coupling without improving the scientific interface.

## Required Conformance Evidence

- The Phase 9.0 legacy-containment and open-protocol gate passes before final public names appear.
- `solve(prob, alg)` and `solve!(init(prob, alg))` agree for normal, manually stepped, terminated,
  max-iteration, callback, save, and restored execution.
- Ownership, remake, cache-invalidation, capacity, exact-time lookup, persistence-failure, and
  ensemble-seed fixtures cover valid and invalid cases.
- Direct-engine versus SciML structural counters prove the zero-extra-work warm-MCS contract.
- CPU, Metal, and ROCm qualification covers 2D/3D algorithms and applicable saves, callbacks,
  checkpoints, imports, remakes, ensembles, and scalar-indexing prohibition.
- The Phase 9 completion audit finds no final-name ambiguity, hidden host boundary, global cache,
  closed algorithm/backend dispatch, silent option acceptance, or speculative evolving-field API.
