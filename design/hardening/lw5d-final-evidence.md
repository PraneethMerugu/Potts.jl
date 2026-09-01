# LW-5D checkerboard-execution convergence qualification

Date: 2026-08-14

Status: **LW-5D SEALED; PROMOTED DEFAULT QUALIFIED AFTER LW-R3**

This packet seals the production LW-5D candidate defined by the
[frozen promotion matrix](lw5d-promotion-matrix.md). LW-R3 passed with
P0=0/P1=0, the bounded selector/checkpoint/inspection delta was applied, and
the complete CPU, product, real-Metal and performance qualification was
repeated. This packet does not authorize another operation family, G6, or the
deferred MethodOfLines input-field work.

## Exact review candidate

Composite digests hash the sorted `shasum -a 256` records of every selected
Julia/project file, binding both paths and contents.

| Surface | SHA-256 |
|---|---|
| `lib/LocalWorksets/src` Julia | `bc2f1a66f6499b90da4503a2e7590e1dc359b1ecd34130df2a5cfc040649c4bf` |
| `lib/LocalWorksets/test` Julia | `55bc71385481a032b821afce7d969fce624c8d2e5d5f5795243a215553188b72` |
| `lib/CorePotts/src` Julia | `8406188c0f996893acae2921ed1cb8a89ca15e7353bfd66af6bc0612e37d060e` |
| `lib/CorePotts/test` Julia | `8163cfb28d5e5d502f092d4c3acf01878f8184f9375540fdbf1717c57dce583c` |
| root `src` Julia | `c307aa522502a967bd8b060eb48e4424af28bdc7064a4fd89ae59d99aafe3ede` |
| root `test` Julia | `68431e77a14dced8b60c1ca99d185f776a73f50e597f65750df07f09f42c8fb9` |
| `benchmark/src` Julia | `cabd23ceb1d1f01dfb633961cc32d3e70450264211d1004ddfc123d20802bf99` |
| Metal Julia/project/manifest | `964b3d8e7467bf8bff22a9d5f24814989292069c6d4c1432aa00b050d7e0ceca` |
| root `Project.toml` | `dff6aba68029e2a5260422239d11bd346ce84dd7fd075e287e46a7d68d1179de` |
| `lib/CorePotts/Project.toml` | `acb0b9e2f2cf125329395bf90a210a47a8c8de6a322ea8f3e9d500af76e49033` |
| `lib/LocalWorksets/Project.toml` | `a71dabb4f3bc0e38b7572d5e23826075b354f0e9d50fc2daf4be6dae371b6e4f` |

Final non-self-referential control-record identities:

```text
a1402466187a14e59768003d06d029f2e3f489d829dd8ebdde3ef145e95cb1cc  design/hardening/lw5d-promotion-matrix.md
65b9120b284d899378c34b0460bb36c36c3dfb569c6f8a309ab3f03a758c8bda  design/hardening/lw5d-review.md
2d642d58966547374390c54121b8a34b4612ab4c30fe2e822184a6b714bcd2f0  spec/localworksets-post-lwr1-roadmap.md
b20d84e2366afdf92017a463c4c4f9a037a09343afddbd18a816aa45d110bec1  design/hardening/g5h-control.md
```

Selected identities:

```text
4c4f48bccc4afd10a292ecdaebc03e0f9260b385a9cd6ad84f4197d552e003f8  lib/CorePotts/src/execution/checkerboard_kernels.jl
fdd8d6a3ca5b455df9d2e13a87c21b9b996d314df1e8b6e0c9430a4622448a4a  benchmark/src/lw5b3_proposal_parity.jl
e77a889704c3f0d77753e4a74c30089258dc04b9ddaf812142458179cfa130f1  benchmark/backends/metal/lw5c_probe.jl
52204aac927944e57ad8b183080d7ff1d0817caeefc286cbc579fb5e04f2f1f3  benchmark/backends/metal/runtests.jl
```

The frozen direct K02/K03 oracle remains byte-for-byte identical to LW-5C.

The composite recipe is intentionally reproducible and path-sensitive. Every
command was executed from the repository root
`/Users/praneethmerugu/Documents/Jiang/CPM 1.6/Potts.jl`; for example:

```sh
find lib/CorePotts/src -type f -name '*.jl' -print0 |
  sort -z |
  xargs -0 shasum -a 256 |
  shasum -a 256
```

The other directory surfaces use the identical command with only the leading
directory changed. The Metal surface uses maximum depth one and selects
`*.jl`, `Project.toml`, and `Manifest.toml`. Consequently, the hashed record
contains the repository-relative path as printed by `find` and the file
content digest; invoking the recipe from an inner directory is not equivalent.

## Convergence and deletion ledger

CorePotts now has one concrete private checkerboard execution shell with
concrete core, claims, proposal-stage, and capability-report parameters. The
direct reference and K02→K03 LocalWorksets candidate share construction,
execution-position ownership, capacity preflight, the MCS loop, completion
collection, settlement publication, checkpoint-block construction, backend
adaptation selection, and inspection entrypoints.

The following temporary LW-5C lifecycle is absent from production and test
source:

- `_LocalWorksetsAdoptedCheckerboardWorkspace`;
- every `_localworksets_adopted_*` constructor, execute, enqueue, wait,
  checkpoint, restore, capability, and inspection path;
- an ordinary runtime union that enumerates the proposal candidate as a
  second coequal engine; and
- freely supplied execution position, mechanism identity, or queue capacity
  outside the concrete proposal-stage strategy.

The common shell does not use `Any`, abstract fields, a symbol-selected hot
branch, mutable registry, or callback. Queue and
per-bank lease capacity live in the concrete LocalWorksets proposal-stage
object; `core.execution` is the only mutable execution position. A legacy
private `getproperty` compatibility shim remains outside the selected hot path
and is recorded as P2 cleanup debt rather than part of the public contract.
The retained two-key LocalWorksets claims mechanism now uses the same common
shell and settlement/checkpoint/adaptation machinery, but remains a disjoint
qualified profile. No supported selector, restore, adaptation, checkpoint, or
host-transaction path combines it with the proposal-stage strategy. A caller
deliberately forging private underscored objects can still construct the
unreviewed combination; explicit cold-path rejection is retained as P2 debt.

## Selection, fallback and reconstruction

One central selector is used for direct/candidate selection and is preserved
through settled adaptation and host relationship reconstruction. The internal
promotion entrypoint selects LocalWorksets only for the complete admitted
conjunction. A selected LocalWorksets preparation failure propagates; the
stale-topology test proves that the original direct runtime is not silently
mutated or substituted.

| Profile | Candidate disposition | Qualified evidence |
|---|---|---|
| exact CPU/Metal, one attempt/site, no accepted-copy or host stage | LocalWorksets K02→K03 | CPU and real-Metal science, queue, failure, replay and performance |
| inert lifecycle transaction plan containing only proposal-science extinction state | LocalWorksets K02→K03 | focused four-case lifecycle admission test plus complete PottsToolkit CPU and Metal product execution |
| active lifecycle descriptors, evaluators, state, relationship or ownership rules | explicit direct fallback | focused admission rejection and complete SciML/real-Metal lifecycle suites |
| registered external CPU Hamiltonian with only Functional evidence | explicit direct fallback | authoring and canonical evaluation remain supported; benchmark proves it cannot self-authorize promotion |
| accepted-copy stage | explicit direct fallback | focused one-MCS direct/fallback state and ownership parity |
| host `after_mcs` stage | explicit direct fallback | focused one-MCS direct/fallback state and ownership parity |
| nonunit attempt budget | rejected by the current algorithm identity before runtime | existing Core and root rejection tests |
| unsupported adapted provider/type/device | fail closed | CPU `Array` adaptation rejection and complete Metal negative rows |
| settled CPU candidate adapted to Metal | freshly adapt Core storage, then reprepare same strategy | new real-Metal bridge-identity and zero-submission witness |
| direct legacy checkpoint | direct replay | complete checkpoint continuation suite |
| promoted checkpoint | public exact reconstruction of the promoted identity | focused 17/17 continuation and mismatch-rejection tests |
| experimental candidate checkpoint | private reconstruction only | public boundary recognizes only direct legacy or exact promoted identities |

Prepared work, workspaces, leases, and events are neither adapted nor
serialized. Host relationship mutation reconstructs the currently selected
profile through the central selector and preserves the concrete runtime type.

The qualification identity is a concrete type parameter of the proposal-stage
execution object. Selection, preflight, enqueue and the host wait path infer
without `Any`; settlement has a bounded scientific-result union. Replacing the
trusted LocalWorksets `run!` method in a fresh method world cannot bypass the
exact-invoke boundary.

## Ownership and execution facts

- CorePotts still owns color/attempt orchestration, immutable scalar color,
  proposal before/after views, canonical Hamiltonian source-order folding,
  semantic Philox addresses, acceptance, conjunctive owner claims,
  accepted-copy commit, trackers, lifecycle, transactions, publication cuts,
  clocks, failures, checkpoints, and settlement.
- LocalWorksets owns the prepared two-stage K02→K03 sequence, bounded leases,
  central validation/lowering, same-scope completion, and inspection.
- KernelAbstractions owns launches, implicit in-order visibility, and the one
  provider synchronization boundary.
- The candidate performs two LocalWorksets launches per color with no
  intermediate host wait, queues twelve MCSs on one lane, and performs one
  final cumulative wait.
- Capacity exhaustion rejects the thirteenth queued MCS before launch and
  without poisoning; the admitted tail drains and the workspace is reusable.
- Scientific failure does not publish a partial MCS and does not relabel an
  expected CorePotts failure as provider poison.
- Complete preflight occurs while the runtime is settled. A complete
  prelaunch rejection appends nothing and remains settled. If a failure is
  discovered only after the Core state-copy prefix has been enqueued, the
  runtime remains unsettled until its real cumulative prefix is synchronized;
  checkpoint and adaptation reject in that interval.
- A real-Metal provider failure after K02 admission poisons both prepared
  proposal banks, publishes and commits zero MCS, records one portable
  synchronization, and leaves the Core runtime unsettled.
- Exact candidate-specific tests compare the complete K02 proposal record,
  canonical source-ordered K03 contribution tuple and scheduled fold,
  disposition, and direction/priority/acceptance semantic RNG coordinates and
  draws. Separate witnesses cover negative, zero and positive energies at
  zero temperature.

## Complete final qualification

All commands used Julia 1.12.6, one Julia thread, and the Apple M1 Pro host.

| Lane | Result |
|---|---|
| focused Core program | all LW-5D selection, disjoint fallback, topology, 12-MCS, exhaustion, failure and checkpoint testsets passed |
| complete CorePotts package | `CorePotts tests passed`, including the fresh-process trusted-adapter boundary |
| complete LocalWorksets package | `LocalWorksets tests passed`, including API, heterogeneous families, implicit ordering, StaticArrays/StructArrays, admission and method-world tests |
| authoritative root PottsToolkit package | 2,667/2,667 passed; MTK compilation, SciML lifecycle, Hamiltonians, registered external operations, relationships, checkpoints and product witnesses included |
| complete real-Metal runner | exit 0; extension load order, cross-domain mechanisms, native components, LW-5D, provider failure, checkerboard, lifecycle and fail-closed rows passed |

The root test environment performed its expected compatibility re-resolution
while preserving the exact StaticArrays 1.9.18 and StructArrays 0.7.3 replay
pins. Test-suite wall time is not a performance signal.

The real-Metal persistent probe reported:

```text
schema = :lw5d_proposal_stages_promoted_v1
queued_mcs = 12
colors = 2
launches_per_color = 2
submissions = 24
waits = 1
scope_synchronizations = 1
algorithmic_workspace_bytes = 0
topology_transfer_bytes = 0
warm_host_allocations = 231328
compiler_cache_before = 322
compiler_cache_after_first_execution = 356
compiler_cache_after_changed_storage = 356
compiler_cache_after_changed_scalars = 356
compiler_cache_after_second_schedule = 376
second_schedule_compilations = 20
compiler_cache_warm = 400
compiler_cache_after = 400
exact_receipt_parity = true
exact_rng_trajectory = true
expected_failure_parity = true
intermediate_waits = 0
settled_repreparation = true
production_default = true
```

Absolute compiler-cache counts and warmed host allocations are diagnostics.
The normative specialization facts are zero additional compilations for a new
storage instance of the same schema and for changed scalar/MCS values. A
genuinely different second descriptor schedule compiled twenty additional
entries and is reported rather than hidden.

## Paired performance and allocation gates

The frozen protocol is 128×128, ten warm batches, fifty paired measured
ten-MCS batches, deterministic alternating arm order, 10,000 paired bootstrap
resamples, candidate/direct upper-95 threshold 1.05, and candidate/frozen
LW-5C upper-95 threshold 1.02.

| Measure | CPU | real Metal |
|---|---:|---:|
| direct median seconds | 0.0248937710 | 0.1124195625 |
| candidate median seconds | 0.0257987710 | 0.1126361460 |
| median ratio | 1.0363544760 | 1.0019265642 |
| candidate/direct bootstrap upper 95% | 1.0436276785 | 1.0080434979 |
| candidate/frozen-LW-5C upper 95% | 1.0016188968 | 1.0047467390 |
| candidate median bytes | 1,461,536 | 17,985,672 |
| frozen byte ceiling | 1,508,896 | 17,986,160 |
| candidate median allocations | 11,280 | 263,908.5 |
| frozen allocation ceiling | 11,500 | 263,919 |

Both throughput and frozen allocation gates pass on both backends. Allocation
parity with direct is not claimed; the candidate remains +185,280 CPU
bytes/+1,263 CPU allocations and +280,952 Metal bytes/+2,370.5 Metal allocations
per measured batch in this run.

## Portability and boundary audit

- Reusable execution and adapter source contains no vendor dispatch branch,
  native queue, stream, command buffer, scheduler, or host fallback.
- Vendor names occur only in centrally reviewed, inert Metal qualification
  metadata. CPU and this exact Metal profile are qualified; CUDA and ROCm are
  unclaimed.
- LocalWorksets contains one provider synchronization site:
  `KernelAbstractions.synchronize(scope.backend)`.
- A sequence adds no host wait or fabricated barrier/event. `waitall` drains
  the cumulative submitted prefix through that one provider boundary.
- LocalWorksets remains domain-neutral. No CPM, Hamiltonian, RNG, clock,
  checkpoint, lifecycle, transaction, or solver meaning entered it.
- Potts/MTK authors see no LocalWorksets vocabulary; Hamiltonian authoring and
  `complete`/`mtkcompile` contracts are unchanged.

## Honest environment diagnostics outside the LW-5D gate

- An explicit Julia 1.10 attempt cannot load the current Julia 1.12-resolved
  manifest because dependencies use `Base.StaticData`; it failed before any
  project code and is not candidate evidence.
- Sandboxed fresh-process Metal load-order checks could not see the GPU even
  though the parent was functional. The unchanged authoritative runner was
  repeated with direct hardware permission and exited zero. This is process
  isolation evidence, not an LW-5D failure.
- An optional `LW4_PERF_SAMPLES=1000` run reached an unrelated pre-existing
  LW-4 D2Q9 performance fixture and rejected it because the generic operation
  result name did not match the declared `populations` output port. Validation
  was not weakened and that optional fixture is not used as LW-5D evidence.

## Seal boundary

The fresh LW-R3 committee passed D0-D3 and the narrow promotion delta with
P0=0/P1=0 after independent memos and a contradiction round. The final delta
then passed the complete LocalWorksets, CorePotts, PottsToolkit 2,667/2,667,
real-Metal, checkpoint, RNG, failure, allocation and paired-performance gates
recorded above. The direct oracle remains reference/fallback/legacy replay.

Carried P2 debt remains: the broad private `getproperty` compatibility shim,
future retention of raw paired samples as a stable artifact, and cold-path
rejection of a deliberately forged simultaneous private claims/proposal
profile. No supported construction path reaches the forged profile. G6 and
all later operation-family work remain closed pending separate owner action.
