# G5H-1 quantitative memory and scaling evidence

Status: passed on exact G5H-1 through G5H-3 candidate

Recorded: 2026-08-08

Authority: G5H-1 in `spec/symbolic-potts-v1-hardening.md`, with particular coverage of DC08, PR07, F06, and F07 in `design/hardening/g5h0-baseline-and-preservation.md`

## Decision

The current CorePotts consolidation has replaced lifecycle mutation-plus-rollback with two-bank,
status-gated publication. The active and candidate scientific banks are distinct, while the
lifecycle workspace's staged scientific state aliases the candidate bank instead of retaining a
third scientific bank. Lifecycle request, conflict, and planning workspaces remain additional,
bounded memory and must stay visible in capacity planning.

Checkpoint and snapshot storage are approximately one logical scientific bank, not a copy of both
runtime banks. Relationship integrity validation and the complete create/remove/retune transaction
preparation path are allocation-free after warmup and remain bounded in the measured fixed-degree
fixtures. Their source-derived bounds are respectively `O(E*D + V*D)` and
`O(E + V*D + Q*log(Q) + Q*D)`, so this is not an unqualified linearity claim when maximum degree
`D` is allowed to grow.

The largest projected whole-cell memory risk in this evidence is native per-cell state, not the
Core substrate. A generic two-bank `Float64` component pool costs 16 bytes per
state-scalar-by-capacity-slot before solver caches or other native-runtime storage. Consequently,
10,000 cell slots with 1,000 state scalars per cell project to about 152.7 MiB, while 10,000 state
scalars per cell project to about 1.49 GiB. G5H-4 therefore still needs explicit state-capacity,
layout, device-residency, and solver-workspace evidence.

This record satisfies the G5H-1 quantitative evidence lane on exact clean candidate commit
`354469ec82f0daa481a82d982d975d7046f4b71e`, tree
`b5ef897a3872a2262112375278ca87d348886668`. It makes no GPU, throughput, latency, or
`PerformanceQualified` claim.

## Reproduction

Run from the repository root:

```sh
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia \
  --project=. \
  --startup-file=no \
  --threads=1 \
  scripts/measure_g5h1_memory_and_scaling.jl
```

The script constructs real CorePotts compiled programs, sequential CPU runtimes, lifecycle
workspaces, relationship stores, logical snapshots/checkpoints, lifecycle receipts, and generic
bulk component-state pools. Fixtures are deterministic and bounded for CI. It exits nonzero if:

- active and candidate scientific fields are not distinct;
- lifecycle staged scientific fields cease to alias the candidate bank;
- bulk component banks alias each other;
- measured two-bank `Float64` state storage ceases to be 16 bytes per state/cell slot;
- the relationship validator no longer has the reviewed traversal structure;
- the source-derived work bound fails to grow fourfold for a fourfold fixed-degree fixture; or
- either warmed relationship timing ratio exceeds the deliberately loose 10x regression guard;
  or
- relationship transaction preparation allocates after warmup.

The timing guards are only tripwires for an obvious accidental quadratic traversal. They are not
performance thresholds. The authoritative relationship evidence is the inspected traversal
shape, its source hash where applicable, the operation bounds, and zero warmed allocations;
timings remain environment sensitive.

## Closed registered-descriptor host-specialization finding

The first 2026-08-06 working-tree run incorrectly attributed the 24-declaration stall to
`PottsProblem` reference-descriptor construction. That scan was repaired to use the completion-owned
`Vector{QualifiedStatement}`, but a phase-separated rerun still exposed model-size-dependent Julia
specialization in completion and structural scheduling. The pre-repair diagnostic baseline was:

| External declarations | Model construction | `complete` | `mtkcompile` | `PottsProblem` |
|---:|---:|---:|---:|---:|
| 1 | 0.348 s | 18.90 s | 15.23 s | 0.198 s |
| 6 | 0.162 s | 24.02 s | 49.70 s | 0.044 s |
| 24 | 0.980 s | 126.43 s | 97.29 s | 0.134 s |

Those baseline values came from the Juliaup 1.12.6 launcher and are regression diagnostics, not
canonical qualification measurements. The 128-declaration point was not attempted because the
24-declaration path had already spent about 224 seconds in `complete` plus `mtkcompile`.

The cause was record-count-sized heterogeneous tuples retained in fully parametric completed and
scheduled carriers, plus canonical fingerprint methods specializing on the concrete topology of
large record, provenance, and analyzed-fact tuples. The repair establishes these boundaries:

- `CompletedPottsData` and `ScheduledPottsData` are stable, non-parametric carriers;
- completion records, schedules, schema tables, capability tables, provenance tables, and native
  component tables remain vector-backed internally;
- host coverage reads the completion-owned vector rather than calling public tuple inspection;
- immutable tuples are materialized only at the author-facing inspection boundary and while
  projecting the logical fingerprint schema; and
- the canonical codec frames tuple and container data through stable `Vector{String}` buffers with
  specialization disabled on value topology. A focused parity witness proves that its scheduled
  digest equals the legacy logical tuple encoding byte-for-byte.

Each row below is one fresh canonical Julia 1.12.1 process with `--startup-file=no --threads=1`.
Package loading and precompilation occur before the timers. The fixture is
`ExternalCompilerSPIFixture.model(n)`; the four timers cover exactly model construction,
`complete(...; registry=...)`, `mtkcompile`, and `PottsProblem` construction, in that order:

| External declarations | Qualified records | Model construction | `complete` | `mtkcompile` | `PottsProblem` | Four-phase total |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 9 | 0.786 s | 6.141 s | 0.175 s | 0.224 s | 7.326 s |
| 6 | 14 | 0.875 s | 6.576 s | 0.344 s | 0.220 s | 8.014 s |
| 24 | 32 | 1.661 s | 10.628 s | 1.364 s | 0.213 s | 13.867 s |
| 128 | 136 | 12.515 s | 64.333 s | 23.200 s | 0.306 s | 100.354 s |

The formerly infeasible 128-declaration point now completes. From one to 128 external declarations,
the complete four-phase path grows 13.7-fold for a 128-fold declaration increase; `PottsProblem`
construction remains essentially flat. At the directly comparable 24-declaration stress point,
canonical `complete` is 11.9 times faster and `mtkcompile` is 71.3 times faster than the earlier
noncanonical diagnostic values. Because the Julia patch versions differ, those speedups are useful
regression magnitude rather than benchmark-grade cross-version ratios.

This closes the host-specialization slope blocker: model size remains data and no longer changes the
completed or scheduled carrier types. The 128-declaration result is a cold stress point, not an
interactive-latency target or a general complexity proof. Its absolute latency remains eligible for
future fingerprint-throughput optimization, but it no longer blocks G5H-1's bounded host-scaling
disposition. The table above is the required fresh-process repetition on the exact clean candidate.

## Recorded environment

| Field | Value |
|---|---:|
| Julia | 1.12.1 |
| Machine | `arm64-apple-darwin24.0.0` |
| Kernel | Darwin |
| CPU | Apple M1 |
| Julia threads | 1 |
| Word size | 64 |
| Physical memory | 17,179,869,184 bytes (16 GiB) |
| Git HEAD | `354469ec82f0daa481a82d982d975d7046f4b71e` |
| Git tree | `b5ef897a3872a2262112375278ca87d348886668` |
| Working tree | clean |
| Script result | `pass`, `bounded_cpu_evidence_only` |

### Exact replay qualification identity

Replay qualification is deliberately narrower than functional execution. The only reviewed exact
environment row in this evidence is produced by:

```sh
env JULIA_DEPOT_PATH=/private/tmp/potts-julia-1121-depot:/Users/praneethmerugu/.julia \
  /Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia \
  --project=. \
  --startup-file=no \
  --threads=1
```

Its capability-environment digest is
`c869ed68289ea1a641d8ed8c05e684693b08b2bb0b90fc2cc211e0b9da48a969`. The authoritative
`Pkg.test` harness runs the same environment with `--check-bounds=yes`; that separately reviewed
row is `80d86547549b8803a75311c347e74e4e44fbe1c550e1f20bc937003d850baefe`. The two rows differ only
in the bound `check_bounds` policy and neither is derived dynamically from the running process.
The identity binds Julia
1.12.1 commit `ba1e628ee49351af0b704afd2b2903d253bd3564`, build-system commit
`b20808d2ea9e5870486190a21f5c29e3f354b825`, Darwin/aarch64, Apple M1, one Julia thread, LLVM
18.1.7, compiler/math flags, CorePotts 0.2.0, and the direct execution dependency versions:
AcceleratedKernels 0.4.3, Adapt 4.7.0, Atomix 1.1.3, KernelAbstractions 0.9.42, LinearAlgebra
1.12.0, and SHA 0.7.0.

Every future reviewed digest requires an equally explicit provenance row. A program that is
structurally admitted on any other environment remains `Supported` with exact `Functional`
protocol evidence, but is not `ReplayQualified` and cannot mint or restore a logical-continuation
checkpoint. This prevents the running machine or an external descriptor from self-asserting replay
authority.

## Core runtime memory

`Base.summarysize` traverses the reachable Julia heap graph and deduplicates shared objects. The
incremental lifecycle column is the shared-graph difference between `(engine_workspace,
lifecycle_workspace)` and `engine_workspace`, so aliased candidate-bank objects are not counted a
second time.

### Site-capacity axis

Cell and relationship capacities are fixed at 256.

| Sites | Runtime | Active bank | Candidate bank | Lifecycle incremental | Snapshot | Checkpoint | Serialized checkpoint |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 4,096 | 236,966 B | 63,376 B | 63,264 B | 95,220 B | 63,272 B | 64,859 B | 65,199 B |
| 9,216 | 457,126 B | 124,816 B | 124,704 B | 192,500 B | 124,712 B | 126,299 B | 126,631 B |
| 16,384 | 765,351 B | 210,832 B | 210,720 B | 328,692 B | 210,728 B | 212,316 B | 212,652 B |

The measured site slopes at the upper two points are 43.0001 bytes/site for the complete runtime,
12 bytes/site for either scientific bank, and 19 bytes/site for incremental lifecycle workspace.
The lifecycle site's dominant bounded layout is explicit: the 16,384-site fixture has 114,688
site-index slots.

### Cell/relationship-capacity axis

The lattice is fixed at 128 x 128 sites. Relationship edge capacity equals cell capacity and
maximum degree is four.

| Cell/edge capacity | Runtime | Active bank | Candidate bank | Lifecycle incremental | Snapshot | Checkpoint |
|---:|---:|---:|---:|---:|---:|---:|
| 256 | 765,351 B | 210,832 B | 210,720 B | 328,692 B | 210,728 B | 212,316 B |
| 1,024 | 922,313 B | 250,864 B | 250,752 B | 376,308 B | 250,760 B | 252,350 B |
| 4,096 | 1,550,153 B | 410,992 B | 410,880 B | 566,772 B | 410,888 B | 412,478 B |

The upper measured capacity slopes are 204.375 bytes/capacity slot for the runtime, 52.125
bytes/slot for either scientific bank, and 62 bytes/slot for incremental lifecycle workspace.

### Labeled planning projection

Linear projection from the two upper measured points to a 512 x 512 lattice with 10,000 bounded
cell and relationship slots gives:

| Object | Projected bytes | Approximate size |
|---|---:|---:|
| Complete Core runtime | 13,324,497 | 12.71 MiB |
| Active scientific bank | 3,667,858 | 3.50 MiB |
| Candidate scientific bank | 3,667,746 | 3.50 MiB |
| Incremental lifecycle workspace | 5,602,260 | 5.34 MiB |
| Logical snapshot | 3,667,754 | 3.50 MiB |
| Checkpoint heap graph | 3,669,378 | 3.50 MiB |
| Serialized checkpoint | 3,669,859 | 3.50 MiB |

This is a capacity-planning projection, not a benchmark or a whole-cell model estimate. It assumes
the measured fixed layouts and degree bound; it excludes native components and their solvers.

## Lifecycle receipts and generic component banks

### Receipt size

| Canonical transition events | Receipt heap graph | Julia-serialized bytes |
|---:|---:|---:|
| 0 | 64 B | 307 B |
| 64 | 8,774 B | 4,496 B |
| 256 | 34,774 B | 17,936 B |
| 1,024 | 88,984 B | 71,696 B |

The upper serialized interval is exactly 70 bytes/event for this transition-only fixture. Heap
sizes reflect Julia vector capacity and object sharing and should not be converted into a universal
per-event constant. Other receipt variants can have different payloads.

### Bulk component-state pool

The fixture uses the actual CorePotts `BulkComponentStatePool` and a generic component policy.
Each pool contains distinct active and inactive matrices.

| Capacity | State width | Pool | Active bank | Inactive bank | Staged transaction incremental | Warmed stage allocation |
|---:|---:|---:|---:|---:|---:|---:|
| 256 | 1 | 7,712 B | 3,840 B | 3,840 B | 72 B | 80 B |
| 1,024 | 1 | 29,408 B | 14,688 B | 14,688 B | 72 B | 80 B |
| 4,096 | 1 | 116,192 B | 58,080 B | 58,080 B | 72 B | 80 B |
| 1,024 | 16 | 275,168 B | 137,568 B | 137,568 B | 72 B | 80 B |
| 1,024 | 64 | 1,061,600 B | 530,784 B | 530,784 B | 72 B | 80 B |
| 1,024 | 256 | 4,207,328 B | 2,103,648 B | 2,103,648 B | 72 B | 80 B |

Measured slopes are 16 bytes per `Float64` state-scalar-by-capacity-slot across both banks and
12.25 bytes of pool metadata per capacity slot. Applying those slopes only to the pool gives:

| Capacity slots | State scalars/cell | Projected two-bank pool | Approximate size |
|---:|---:|---:|---:|
| 10,000 | 1,000 | 160,122,980 B | 152.7 MiB |
| 10,000 | 10,000 | 1,600,122,980 B | 1.49 GiB |

These rows deliberately expose the risk rather than asserting that either state width is a target
whole-cell architecture. They exclude solver caches, Jacobians, callback/event storage, coupling
buffers, observations, and device copies.

## Relationship integrity scaling

The fixture is a ring with one edge per vertex and fixed maximum degree two. The reviewed validator
body hash is
`1700517ba3b14c877bb244196f801c7cc5584613ccbd945faf14d2d1f71c93ad`.
For the present implementation, a conservative traversal bound is

```text
2E + V*D + 3E*D
```

covering two edge passes, the incident matrix pass, endpoint membership scans, and the bounded
duplicate scan. Scalar checks are omitted from the count.

| Vertices | Edges | Maximum degree | State | Work bound | Median validation | Warmed allocation |
|---:|---:|---:|---:|---:|---:|---:|
| 1,024 | 1,024 | 2 | 27,120 B | 10,240 | 8,159 ns | 0 B |
| 2,048 | 2,048 | 2 | 53,872 B | 20,480 | 16,118 ns | 0 B |
| 4,096 | 4,096 | 2 | 107,376 B | 40,960 | 32,441 ns | 0 B |

Fourfold `E` and `V` produced a fourfold structural work bound and a 3.976x observed timing ratio.
The gate's loose tripwire is 10x. Fixed-degree evidence does not prove linear behavior when `D`
grows; relationship-capacity and maximum-degree admission must therefore remain explicit.

### Relationship transaction preparation

The transaction fixture begins with the same fixed-degree ring and emits one reverse-ordered
retune request per edge. Reverse order exercises the canonical request sorter instead of handing
it already ordered input. The implementation uses allocation-free heap sorting, indexed duplicate
tracking, bounded incident scans, and monotonic free-slot admission. A conservative bound is

```text
2E + V*D + Q*log2(Q) + Q*D
```

for baseline integrity traversal, canonical ordering, duplicate/admission checks, and bounded
endpoint-degree work.

| Vertices | Edges | Requests | Maximum degree | Transaction object | Work bound | Median preparation | Warmed allocation |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1,024 | 1,024 | 1,024 | 2 | 73,312 B | 15,360 | 82,948 ns | 0 B |
| 2,048 | 2,048 | 2,048 | 2 | 146,144 B | 32,768 | 183,750 ns | 0 B |
| 4,096 | 4,096 | 4,096 | 2 | 291,808 B | 69,632 | 403,864 ns | 0 B |

Fourfold `E`, `V`, and `Q` produced the stated `Q*log(Q)` structural bound and a 4.869x observed
timing ratio, below the 10x regression tripwire. This evidence covers the transaction preparation
path that the integrity-only measurement does not exercise.

### F11 settled host transaction closure

The bounded transaction preparation above is now connected to one public, settled host mutation
boundary. `CellIdentity` carries slot, generation, and kind. The single
`relationship_transaction!(integrator, effects...)` entry accepts the existing `Create`, `Remove`,
and `Retune` effects, supports endpoint-pair remove/retune, requires exact generations when an
identity is supplied, and auto-stamps integer endpoints from the settled runtime. One Core-owned
host candidate applies the entire batch, rebuilds the runtime once, validates it, adapts it to the
selected backend, and only then publishes the replacement pointer. A failed callback set restores
the previously published runtime rather than exposing the candidate.

Those two names are the intentional `+2` stable PottsToolkit public-API delta from G5H-0. They
implement the frozen F11 host boundary and are not compatibility aliases or parallel authorities.

Exact-candidate evidence is:

- `test/test_relationship_host_transactions_v2.jl`: 22/22 passed, covering create, retune,
  remove, payload schema ordering, checkpoint continuation, batch rollback, stale generation,
  callback rollback, and checkerboard-bank rebuild;
- public API and named Core SPI boundary selection: 550/550 passed; and
- `lib/CorePotts/test/test_program_v1_relationships_checkpoint.jl`: package-owned settled-host
  candidate/rebuild assertions, including invalid batch, stale generation, unsettled-runtime
  rejection, and cross-store all-or-nothing failure.

This closes the F11 settled-host implementation gap for G5H-1/G5H-2. It is functional evidence,
not a new scaling or GPU claim. The full root and CorePotts suites passed on the exact clean
candidate. Device-resident compiled requests and no-hidden-transfer qualification remain owned by
G5H-4.

## Interpretation and limits

- DC08/F06 disposition: there are two distinct scientific banks, not active state plus rollback
  copy plus an independent lifecycle staged-state copy. Candidate-state alias assertions exercise
  ownership, kinds, generations, trackers, relationships, and descriptor state.
- F07/checkpoint disposition: snapshots and checkpoints materialize the active published logical
  state and measure at approximately one bank. Candidate and half-applied state are outside this
  artifact.
- PR07 disposition: integrity validation and complete transaction preparation have explicit
  bounded-degree traversal laws, measured fixed-degree scaling, and zero warmed allocations for
  these fixtures. Transaction request ordering is `O(Q*log(Q))`, not insertion-sort quadratic.
- Whole-cell risk disposition: Core runtime memory is bounded and modest in the planning fixture,
  but two-bank native per-cell state can dominate rapidly. Capacity is therefore a semantic and
  admission concern, not just an optimization concern.
- `Base.summarysize` is a reachable-heap estimate, not process RSS. Julia `Serialization` is used
  only to estimate payload size and is not a stable wire-format or cross-version guarantee.
- The evidence excludes JIT compilation, allocator fragmentation, initialization peaks, GPU
  residency/transfers, nonempty relationship payloads, high-degree graphs, native solver state,
  and coupled failure-path peaks.
- Final performance and GPU qualification belong to G5H-4/G5H-5. This lane supports only the
  bounded CPU architecture and scaling disposition required by G5H-1.
