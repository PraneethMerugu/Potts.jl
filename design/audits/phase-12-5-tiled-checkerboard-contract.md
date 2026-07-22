# Phase 12.5 Tiled Checkerboard Contract

Status: Accepted; project-owner interview decisions 1--45 complete

Date: 2026-07-21

## Purpose

Phase 12.5 determines whether Potts.jl can add a world-class tile-local CPM engine without weakening
its scientific, portability, reproducibility, extensibility, or usability goals. The candidate is
named `TiledCheckerboardCPM`. It is a distinct stochastic algorithm, not an invisible optimization
of `CheckerboardSweepCPM`.

The work is informed by Sultan et al., *A parallelized cellular Potts model that enables simulations
at tissue scale* ([arXiv:2312.09317](https://arxiv.org/abs/2312.09317)). Their reported 3--4-order
speedups are relative to specified serial implementations, not absolute throughput directly
comparable with current Potts.jl records. Their implementation combines local checkerboard regions,
shared-memory caching, extension-specialized kernels, atomics, and bounded use of out-of-date global
cell information. Phase 12.5 reconstructs matched workloads and studies those mechanisms, but does
not claim implementation identity.

## Accepted scope and disposition

1. Phase 12.5 must implement and evaluate a serious production candidate. A negative result is valid
   when retained evidence shows that the approach fails a scientific, portability, or performance
   gate.
2. The public algorithm name is `TiledCheckerboardCPM`.
3. The initial qualified physics set is volume, surface/perimeter, adhesion, prescribed-field
   chemotaxis, directional motility, and Act-like history-dependent motility. HST penalties and their
   required state are first-class component residents when applicable.
4. The engine is explicitly selected during Phase 12.5 and cannot become the automatic GPU default
   before validation and the Phase 13 API decision.
5. Closure assigns exactly one disposition: release-eligible public algorithm, explicitly
   experimental algorithm, or rejected research candidate. A rejected engine does not remain as an
   undocumented production path.
6. Production multi-GPU execution is deferred. Tile ownership and halo boundaries must leave a
   credible extension seam, but single-device excellence is the phase requirement.

## Execution and MCS semantics

1. A tile is an internal rectangular lattice region with a halo derived from the maximum dependency
   radius of the topology and active components.
2. Simultaneously active tiles have disjoint lattice write regions. Tile coloring and halo layout
   are implementation policies, not changes to the model Hamiltonian.
3. Proposals execute sequentially within a tile and concurrently across nonconflicting active tiles.
   Tile activation order is randomized deterministically.
4. Targets are sampled uniformly over the declared proposal domain. Sources follow the topology's
   declared neighbor distribution.
5. One public `step!` advances exactly one MCS using the accepted expected-proposal-budget
   normalization. Tile size, active fraction, sub-round count, and backend cannot redefine simulated
   time.
6. Each internal sub-round reads a deterministic snapshot of relevant cell statistics. Accepted
   copies emit exact additive deltas; reconciled values become visible to the next sub-round.
7. Lattice occupancy, integer cell statistics, and all declared exact sufficient statistics agree at
   every public MCS boundary. Diagnostic execution may check the same invariants after each
   sub-round.
8. Tile size and switching interval can affect local update waiting-time distributions. They are
   algorithm configuration and provenance, even when selected from validated defaults.
9. The initial policy uses offline validated defaults indexed by dimension, topology, precision, and
   backend class. Phase 12.5 adds no hidden runtime tuning search.
10. A device-global storage path may replace shared-memory storage only when it preserves these same
    semantics. The engine never silently changes to another algorithm.

## RNG and reproducibility

1. Random draws are counter-based and keyed by semantic identities including seed, MCS, sub-round,
   tile, local proposal index, and draw purpose.
2. A draw cannot depend on GPU scheduling, launch geometry, atomic completion order, observation, or
   profiling.
3. The same seed, model, initial state, algorithm contract, configuration, software version, and
   backend reproduce the same trajectory.
4. CPU, Metal, and ROCm require statistical agreement, not cross-backend trajectory or bitwise
   identity.
5. Tile dimensions, switching interval, backend policy, precision, and contract version are recorded
   in solution and benchmark provenance.

## Open physics and reconciliation protocol

1. Compatibility is an open protocol rather than a hard-coded built-in type list. A component
   declares its dependency radius, snapshot-visible cell statistics, scratch requirements,
   device-callable energy contribution, and reconciliation behavior.
2. Kernel execution contains no dynamic dispatch. Model lowering produces concrete typed component
   composition and ordinary Julia specialization; macros or generated functions require evidence
   that normal multiple dispatch is insufficient.
3. Additive state uses proposal-local deltas and deterministic sub-round reconciliation. Integer
   reductions are exact. Floating reductions document and test the strategy needed by the accepted
   reproducibility profile.
4. Non-additive or history-dependent state defines a bounded GPU-compatible snapshot, proposal, and
   reconciliation protocol. Centroids, polarity, Act-like state, and HST state cannot be implemented
   as host callbacks hidden inside stepping.
5. Fragmentation remains valid unless an explicit constraint prohibits it. A local connectivity
   constraint may participate when its dependency radius and device implementation are declared.
   Unbounded global graph traversal is outside the initial engine.
6. Unsupported or unsafe components fail during construction or lowering with an actionable
   capability error. Failure inside a launched GPU kernel and silent removal of physics are invalid.
7. The same component formulas are shared with other algorithms. Tiled execution cannot create a
   duplicated, drifting set of Hamiltonian implementations.

## Hardware and implementation contract

1. KernelAbstractions is the portable kernel language. CPU, Metal, and ROCm are the qualified
   backends under the current project contract.
2. Backend-specific tile sizes, shared-memory layouts, atomics, workgroups, and KernelIntrinsics are
   allowed only behind generic semantic boundaries and equivalence evidence.
3. Two-dimensional and three-dimensional models receive the same scientific contract but may use
   different kernels and storage policies. Three-dimensional execution may use smaller tiles,
   streamed halos, or device-global storage when shared memory is insufficient.
4. `shared_memory = :auto` selects a qualified storage policy. An expert may require shared memory;
   an unavailable required mode fails before execution. No fallback transfers execution to the host.
5. All steady-state workspaces are preallocated. Memory is bounded by `O(lattice sites + maximum
   cells)`. Snapshot and delta buffers may use bounded `O(maximum cells)` storage. Whole-lattice
   duplication requires measured end-to-end justification.
6. An unobserved MCS has zero engine-attributable allocations, host transfers, scalar indexing, and
   host synchronization. Launch count is tracked; there are no per-component or unobserved-reporting
   launches.
7. Launches correspond to necessary synchronization or execution stages and scale with internal
   sub-rounds, not lattice size or component count. Fusion continues only while end-to-end profiles
   justify its compilation and native-resource costs.
8. Observation and `current_mcs_report` are explicit synchronization/materialization boundaries.
   They return exact reconciled state and do not change the stochastic schedule.
9. `Float32` is qualified on CPU, Metal, and ROCm. CPU `Float64` supplies a higher-precision
   reference. GPU `Float64` is qualified where genuinely supported and otherwise fails explicitly;
   it is never silently downgraded or emulated on the host.

## Julia and PottsToolkit API

The ordinary public spelling is:

```julia
solve(model, TiledCheckerboardCPM(); mcs = 10_000)
```

The algorithm exposes a small expert configuration surface:

```julia
TiledCheckerboardCPM(;
    tile_size = nothing,
    switching_interval = nothing,
    shared_memory = :auto,
)
```

`nothing` selects a validated recorded default. At least 95% of compatible stable components receive
a natural PottsToolkit spelling without direct CorePotts construction. CorePotts owns the algorithm,
protocols, workspace, and execution. PottsToolkit owns high-level construction and DSL lowering, not
a duplicate engine.

Documentation explains the proposal process, snapshots, reconciliation, normalized MCS, RNG scope,
tile/switching effects, compatible-component protocol, backend guarantees, and differences from
sequential and ordinary Checkerboard algorithms. It teaches when the method is scientifically
appropriate, not only when it is fast.

## Scientific validation

1. Exact gates cover lattice/cell-volume agreement, identity validity, label bounds, sufficient
   statistics, legal neighbor proposals, report partitioning, and absence of conflicting lattice
   writes.
2. Statistical gates pre-register observables, effect-size tolerances, ensemble sizes, and seeds.
   Equivalence is not inferred from a nonsignificant null-hypothesis test.
3. Required stochastic measurements include proposal frequency, local waiting-time distributions,
   acceptance rate, and accepted-copy distribution.
4. Required emergent measurements include differential-adhesion sorting, prescribed-gradient
   chemotaxis, migration speed and persistence, morphology, Act-like polarization behavior, and a
   collective-order transition where the reference configuration applies.
5. Existing `SequentialCPM`, `SequentialEquilibrium`, `CheckerboardSweepCPM`, and `LotteryCPM`
   semantics remain unchanged. Shared changes fail on a regression above 5% geometric mean or 10%
   for an individual workload unless the owner accepts an evidence-backed exception.

## Performance and comparison gates

1. Activated attempts per second is the principal hardware-throughput metric. Reports also retain
   MCS/s, realized proposals/s, accepted copies/s, time per accepted copy, allocations, memory,
   launches, synchronization, compilation, first-MCS latency, and observation cost.
2. The candidate must improve at least two representative paper-scale GPU workloads by 2x over
   `CheckerboardSweepCPM` and improve the geometric mean over its supported GPU workload matrix.
3. Performance cannot compensate for failed invariants, statistical disagreement, changed physics,
   reduced precision, host fallback, or altered MCS normalization.
4. A retained optimization needs an end-to-end scientific workload benefit. A shared-memory,
   intrinsic, or isolated-kernel microbenchmark is insufficient.
5. Package load, precompilation, authoring/lowering, first kernel compilation, first MCS, and warm
   throughput remain independent measurements. Representative precompilation cannot expand into a
   combinatorial inventory of physics combinations.
6. Native evidence records code generation and chronological traces for CPU, Metal, and ROCm,
   including launches, synchronization, registers, spills, shared memory, traffic, and occupancy
   where the backend authoritatively exposes them.

## Sultan comparison boundary

The comparison suite contains a published-model reconstruction and a minimal tiled-engine benchmark.
It records lattice, neighborhood, Hamiltonian, parameters, proposal process, MCS definition,
precision, output boundary, hardware, software, and every reconstructed assumption.

A faster claim requires matched model semantics, algorithm class, hardware, precision, lattice,
timing boundary, and proposal accounting. Published speedup ratios on different hardware remain
descriptive context. Missing details are labeled unavailable; an approximation is never called an
exact reproduction. Final archived cross-library and publication rankings remain Phase 15 work.

## Closure

Phase 12.5 closes only after CPU, Metal, and ROCm provide repeated exact-revision correctness,
reproducibility, statistical, compilation, memory, native-profile, and performance evidence. The
Sultan reconstruction, raw configurations, seeds, records, and analysis programs remain separately
reproducible. Protected CI is green on the completion revision, documentation is updated, and the
owner records the promote, experimental, or reject decision before Phase 13 begins.

