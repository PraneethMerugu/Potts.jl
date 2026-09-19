# LocalMath–KernelAbstractions optimization audit

Status: implementation audit completed on 2026-09-17. LocalMath PR22 is merged
with its complete hosted suite green. LocalMath PR23 is locally qualified and
awaiting its hosted suite. This record describes evidence and durable owner
contracts; it does not freeze private layouts or create another execution
authority.

## Exact baseline and method

The audit used Julia 1.12.6, KaimonCompilerTools 0.1.1, merged LocalMath PR21
`12b3fa986a8600dc2b53bd8fae28af88a8ae7480`, and KernelAbstractions 0.9.42 at
tree `a5b87110fa95d711355af44832497745aa93fb52`. The resolved KA source was
copied to a temporary read-only tree and compared with Julia's loaded package
path. No upstream version was patched or substituted.

Every compiler claim came from a fresh Kaimon session with KCT registered
before loading LocalMath. The audit used `compiler_snoop_inference`,
`compiler_methodinstances`, `compiler_jet`, `compiler_alloccheck`, and fresh
load invalidations where applicable. Repeated warmed allocations and ordinary
CPU/Metal tests remained the behavioral authorities. Construction and cold
compilation stayed outside warmed measurements.

## KA 0.9.42 source contract

The exact source establishes these boundaries:

| Boundary | KA source | Contract and consequence for LocalMath |
| --- | --- | --- |
| Host copy | `src/KernelAbstractions.jl:117-130` | KA documents ordinary `Base.copyto!` as the synchronous host-visible operation and its backend `copyto!` as asynchronous. LocalMath uses the former only where host visibility is the intended boundary. |
| Kernel identity | `src/KernelAbstractions.jl:692-717` | Backend, workgroup size, static `ndrange`, and callable are type parameters of `Kernel`. Supplying runtime scientific extent to the constructor therefore creates avoidable execution identities. C12 already cut collection families over to runtime launch `ndrange`. |
| Partitioning | `src/KernelAbstractions.jl:722-776`, `src/nditeration.jl:132-163` | Static workgroup/range facts become type-level iteration-space facts; dynamic values remain runtime `CartesianIndices`. Dimension and a justified operation-family workgroup may specialize, but extent/capacity must remain data. |
| CPU launch | `src/cpu.jl:39-48` | A zero-block iteration space returns without launching work. LocalMath's `max(extent, 1)` launches remain semantic validation/publication choices, not a KA requirement. |
| CPU scheduling | `src/cpu.jl:50-75`, `src/cpu.jl:97-149` | KA chooses a CPU workgroup and may create `@sync`/`Threads.@spawn` work for a multithreaded launch. The remaining CPU task/event allocation is a KA/Julia scheduling cost unless LocalMath submits unnecessary kernels. |
| CPU copy | `src/cpu.jl:19-32` | Same-backend CPU copies launch a KA copy kernel; cross-backend copies use `Base.copyto!`. LocalMath must not add another transfer scheduler around this behavior. |

The settlement optimization additionally relies on an observed, tested backend
contract, not on a universal KA assertion. Metal 1.11.0 returns immediately for
zero-length D2H copies (`src/array.jl:351-359`) but synchronizes before every
nonempty D2H `memcpy` (`src/array.jl:398-406`). Metal synchronization flushes,
waits, cleans up, and surfaces device failures (`src/synchronization.jl:128-149`).
Therefore only a **nonempty** host-visible validation copy is a Metal completion
operation. Empty or aliased representations explicitly synchronize, and real
Metal fault tests defend this boundary.

## LocalMath boundary atlas

| LocalMath owner | Specialization facts | Runtime data | Completion/movement law | Audit result |
| --- | --- | --- | --- | --- |
| `execution/launch_support.jl` and collection/reduction families | backend, dimension, operation family, bounded workgroup | extent, capacity, count, identities, values | runtime `ndrange`; no launch cache | C12 was already correct after PR21; no further launch change |
| `execution/ordered_fold_stage.jl` | direct sparse source traversal versus compacted canonical traversal | physical source positions, mask/subset participation, count, values | SourceOrder scans ascending physical positions directly; canonical orders retain compaction/sort | Qualified as C13 / LocalMath PR22 |
| `execution/stage_program.jl` preparation | genuine stage/evaluator/storage families | graph contents, names, slot indices, capacities | preparation owns adaptation and workspace materialization | No broad payload or adaptation change qualified |
| `execution.jl` receipts | prepared storage/backend family | dependency tuple contents, serials, ordinals, lease indices | execution enqueues; settlement owns one cumulative provider completion and exact failure cache | Qualified as C14 / LocalMath PR23 |
| `execution/stage_program_kernelabstractions.jl` provider lane | backend/storage family | submitted and settled ordinals | nonempty validation copy completes the queued prefix; empty/alias falls back to synchronize | Qualified with exact CPU/Metal failure tests |
| `execution/validation_support.jl` | element/storage family only | recorded stage, witness, lease | one device/host matrix transfer primitive | Compact payload qualified; tuple reconstruction removed |
| `structural_binding.jl` fixed-relation admission | relation/storage family | relation contents and diagnostic values | same validation transfer owner; no surrounding duplicate synchronize | Qualified inside C14 |
| `execution/program_inspection.jl` | none beyond prepared plan family | counters and diagnostics | derives from production lane/status authorities | Terminology cut over; no second copy |
| Adapt and backend-owned transfer paths | backend and storage family | scientific values and runtime sizes | preparation owns H2D materialization; inspection owns requested D2H views | No additional change qualified |

## Accepted changes

### C13 — direct SourceOrder recurrence

LocalMath PR22 (`36ff6aa`, merged as `dd5d2e0`) removes compaction and bitonic
sorting from `SourceOrder` while retaining canonical ordering on the existing
path. Two durable tags express the mathematical traversal law:
`_DirectSparseSourceTraversal` and `_CompactedPrefixTraversal`. Arbitrary
canonical key/identity callbacks remain at the sort/finalization owner and do
not enter recurrence identity.

Evidence:

- launches at extents 32/300/301 fell from 21/51/51 to 6/6/6;
- warmed allocations fell from 7,792/77,712/77,712 to
  3,472/7,584/7,584 bytes;
- the recurrence had one MethodInstance per traversal law, JET was clean,
  AllocCheck returned no findings, and package loading introduced no
  LocalMath-owned invalidation;
- focused CPU passed 80/80, full CPU 1,917 assertions, focused real Metal
  63/63, and full real Metal 568/568; and
- every hosted PR22 package, scientific, docs, macOS, and real-Metal job passed.

The tests cover mask/subset participation, dense participating ordinals in
diagnostics, halt, failure atomicity, empty input, canonical behavior, and two
different canonical callable families without asserting private struct layout.

### C14 — validation-copy settlement

LocalMath PR23 narrows every prepared program to its existing program-level
device/host validation matrix, removes heterogeneous status-tuple
reconstruction, and uses the nonempty host copy as the provider-scope
completion. `wait` and `waitall` retain cumulative scope ordering, deterministic
failure reporting in argument order, exact failure caching, and one-time lease
release. The fixed-relation validator now reuses the same transfer primitive.

Evidence on the rebased PR23 tip `a21856f`:

- pending wait allocation fell from 208 to 176 bytes; combined and grouped
  waits improved by 32 bytes at dependency arities 0/1/2/4/17; execute stayed
  416 bytes and cached wait stayed zero;
- broad `wait` typed IR improved from 131 statements / 76 calls / 36 `Any`
  slots to 130 / 75 / 35. A rejected intermediate outer `try` shape measured
  235 / 135 / 67 and was not retained;
- fresh KCT found one matching MethodInstance each for receipt settlement,
  prepared-scope settlement, and lane-tail settlement, with no arity growth;
  concrete JET was clean and AllocCheck reported only the known `IdSet`
  insertion ccall;
- focused CPU passed 443 assertions, full CPU 1,943/1,943, focused real Metal
  137/137, and full real Metal 592/592; and
- a deliberately faulting Metal kernel proves the validation copy surfaces the
  provider error, caches the same error object, and releases each requested
  lease exactly once.

The existing `waitall` tuple-arity specializations were measured and left
unchanged. They were not worsened by C14, and no evidence justified a broader
dynamic receipt container or erased cache.

## Rejected and no-change hypotheses

- Further static/dynamic launch surgery beyond C12 was rejected: operation
  families now reuse runtime extent/capacity identities, zero-extent behavior
  is explicit, and no new dominant identity leak was demonstrated.
- Broad stage-preparation, Adapt, workspace, and relation payload rewrites were
  rejected because measured MethodInstance populations plateaued or cost could
  not be reduced without displacement into preparation/execution.
- A single traversal type carrying arbitrary canonical callbacks into ordered
  recurrence was rejected during review. The final two-tag law keeps only
  semantics consumed by the recurrence.
- The first receipt settlement draft was rejected even though allocations fell:
  KCT exposed its 131→235 statement and 76→135 call regression. Moving the
  failure boundary into `_settle_receipt_statuses!` retained the allocation win
  and reduced the broad caller below baseline.
- A universal “copy synchronizes every backend” rule was rejected. The code and
  claims are exact: nonempty Metal D2H is tested as completion; empty/alias uses
  explicit synchronize; future backends must satisfy the same observable
  contract or take their admitted fallback.
- New caches, registries, event wrappers, autotuners, backend-specific
  scientific executors, and retained projection graphs were unnecessary and
  were not added.

## Remaining costs and downstream pressure

KA's multithreaded CPU scheduler can still allocate tasks/events, and
`Base.IdSet` insertion remains visible to AllocCheck during first settlement.
Saved scientific snapshots, explicit inspection copies, and cold
workspace/device materialization remain intentional allocations. These costs
are not evidence for a second scheduler or cached executor.

The combined C13/C14 stack must retain exact downstream canaries on CorePotts
`b4e5bda5` and Potts `40b2ddf3`: lifecycle reconstruction, maintained
relationships, sequential/checkerboard execution, compiler-boundary reuse,
warm stepping, remake, continuation, authoring equivalence, and affected real
Metal behavior. R49/R50 keep these canaries, while G09 owns longitudinal
compiler/allocation/transfer trends.

The audit demonstrated two different reusable owner laws, so they remain two
dense LocalMath companions rather than one mixed PR. C13 owns ordered-fold
mathematical traversal; C14 owns provider settlement and validation transfer.
Neither identity appears in live APIs.
