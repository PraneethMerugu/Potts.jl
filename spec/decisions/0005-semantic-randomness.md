# Decision 0005: Semantically Addressed Counter-Based Randomness

Status: Accepted

Date: 2026-07-17

## Context

The historical implementation has no public simulation seed, mixes Julia's default RNG with custom
hash-derived values, partitions mechanisms with magic numeric offsets, aliases random expressions in
the rule language, and does not save enough information for exact continuation. Stateful per-thread
RNGs would also make results dependent on work partitioning and scheduling.

## Decision

Each problem has one realized master seed covering stochastic initialization and dynamics. Potts.jl
model randomness never depends on Julia's global or task-local RNG.

Random draws use a versioned counter-based mapping from semantic identity. Named streams isolate
layout, proposal, acceptance, algorithm scheduling, auxiliary mechanics, rules, events, lifecycle, inheritance, and
ensemble randomness. Thread identity, workgroup structure, launch order, and asynchronous scheduling
do not define draws.

Raw addressed bits match only across backend profiles that explicitly carry
that current guarantee. CPU is qualified and bounded Metal rows are exercised
by the real-device runner; AMDGPU has no current public PottsToolkit backend
profile. Cross-backend simulations must be
statistically equivalent but need not follow identical trajectories. Trajectory reproducibility is a
separate algorithm-specific claim that also depends on numerical and transactional determinism.

Exact and approximate distributions are separately named. Exact checkpoints record the master seed,
RNG version, semantic counters, cell generations, complete state, model fingerprint, and execution
provenance.

`Philox4x32x10V2` is the accepted default contract after compilation,
known-answer, semantic-address, trajectory-identity, and open-uniform endpoint
validation. Its public RNG contract version is `2.0.0` and its lowering identity
is `philox4x32x10_semantic_address_fisher_yates_v2`.

## Consequences

- Existing `pcg_hash` offsets and default-RNG layout calls cannot define the future contract.
- Random calls require semantic component and draw identities generated during model compilation.
- Cell slot generations become part of both lifecycle and RNG correctness.
- Model and solution provenance must include RNG metadata.
- Distribution algorithms become versioned scientific behavior.
- Kernel restructuring can preserve random streams when semantic operations are unchanged.
- Exact trajectory claims require deterministic reductions and state transactions beyond RNG.

## Alternatives Considered

Stateful RNGs per host task, GPU thread, or workgroup were rejected because work partitioning and
scheduling would alter stream consumption. Julia's default RNG was rejected as the scientific stream
contract because its precise generated sequence is not a stable language guarantee. Vendor RNG
libraries remain useful references but do not define Potts.jl stream ordering.

## Required Evidence

- Generator known-answer tests on all first-class backends
- Semantic-address collision and stream-isolation tests
- Workgroup and scheduling invariance tests
- Distribution-specific statistical validation
- Ensemble seed-derivation tests
- Exact checkpoint continuation tests
- Algorithm-specific trajectory-reproducibility profiles
