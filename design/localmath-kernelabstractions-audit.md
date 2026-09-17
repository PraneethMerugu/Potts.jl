# LocalMath–KernelAbstractions optimization audit

Status: implementation audit completed on 2026-09-17. LocalMath PR22 and PR23
are merged with their complete hosted suites green. This record describes evidence and durable owner
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

| Boundary | Exact source | Contract and LocalMath consequence |
| --- | --- | --- |
| Host copy | `src/KernelAbstractions.jl:117-130` | KA documents ordinary `Base.copyto!` as synchronous and backend `copyto!` as asynchronous. LocalMath uses the former only where host visibility is intended. |
| Kernel identity | `src/KernelAbstractions.jl:692-717` | Backend, workgroup size, static `ndrange`, and callable are kernel type parameters. Runtime scientific extent must not enter the constructor. |
| Partitioning | `src/KernelAbstractions.jl:722-776`, `src/nditeration.jl:132-163` | Static range/workgroup facts become type-level iteration-space facts; dynamic values remain runtime indices. Dimension and a justified operation-family workgroup may specialize; extent/capacity remain data. |
| CPU launch | `src/cpu.jl:39-48` | A zero-block space returns without launching. LocalMath's `max(extent, 1)` launches are semantic validation/publication choices, not a KA requirement. |
| CPU scheduling | `src/cpu.jl:50-75`, `src/cpu.jl:97-149` | KA may create `@sync`/`Threads.@spawn` work for multithreaded launches. Remaining task/event allocation is a KA/Julia cost unless LocalMath submits unnecessary kernels. |
| CPU copy | `src/cpu.jl:19-32` | Same-backend CPU copies launch a KA copy kernel; cross-backend copies use `Base.copyto!`. LocalMath adds no transfer scheduler around it. |

Settlement also relies on a tested backend contract, not an invented universal
GPU rule. Metal 1.11.0 returns immediately for zero-length D2H copies
(`src/array.jl:351-359`) but synchronizes before nonempty D2H `memcpy`
(`src/array.jl:398-406`). Metal synchronization flushes, waits, cleans up and
surfaces device failures (`src/synchronization.jl:128-149`). Therefore only a
**nonempty** host-visible validation copy is a Metal completion operation.
Empty or aliased representations explicitly synchronize, and real Metal fault
tests defend the boundary.

## LocalMath boundary atlas

| Owner | Specialization facts | Runtime data | Result |
| --- | --- | --- | --- |
| `execution/launch_support.jl` and collection/reduction families | backend, dimension, operation family, bounded workgroup | extent, capacity, count, identities, values | C12 already correct after PR21; no further launch change |
| `execution/ordered_fold_stage.jl` | direct sparse source versus compacted canonical traversal | positions, mask/subset participation, count, values | C13 / PR22 qualified |
| `execution/stage_program.jl` preparation | genuine stage/evaluator/storage families | graph contents, names, slots, capacities | no broad payload or Adapt rewrite qualified |
| `execution.jl` receipts | prepared storage/backend family | dependencies, serials, ordinals, leases | C14 / PR23 qualified |
| `execution/stage_program_kernelabstractions.jl` lane | backend/storage family | submitted/settled ordinals | nonempty copy completion; empty/alias synchronize |
| `execution/validation_support.jl` | element/storage family | recorded stage, witness, lease | one device/host matrix transfer owner |
| `structural_binding.jl` fixed-relation admission | relation/storage family | relation contents and diagnostics | same transfer owner; duplicate synchronize removed |
| `execution/program_inspection.jl` | prepared plan family | counters and diagnostics | derives from production authorities; no second copy |
| Adapt/backend transfer paths | backend/storage family | values and sizes | preparation owns H2D; inspection owns requested D2H; no further change |

## Accepted changes

### C13 — direct SourceOrder recurrence

LocalMath PR22 (`36ff6aa`, merged as `dd5d2e0`) removes compaction and bitonic
sorting from `SourceOrder` while retaining canonical ordering on its existing
path. `_DirectSparseSourceTraversal` and `_CompactedPrefixTraversal` are the two
durable mathematical laws. Arbitrary canonical key/identity callbacks remain at
the sort/finalization owner and do not enter recurrence identity.

- launches at extents 32/300/301 fell from 21/51/51 to 6/6/6;
- warmed allocations fell from 7,792/77,712/77,712 to
  3,472/7,584/7,584 bytes;
- recurrence had one MethodInstance per traversal law, JET was clean,
  AllocCheck had no findings, and load added no LocalMath-owned invalidation;
- focused CPU passed 80/80, full CPU 1,917 assertions, focused real Metal
  63/63, full real Metal 568/568, and every hosted PR22 job passed.

Tests cover mask/subset participation, dense participating diagnostic ordinals,
halt, failure atomicity, empty input, canonical behavior, and distinct canonical
callable families without asserting private struct layout.

### C14 — validation-copy settlement

LocalMath PR23 (`a21856f`, merged as `a26cbfe4`) narrows every prepared program to its existing program-level
device/host validation matrix, removes heterogeneous status-tuple
reconstruction, and uses the nonempty host copy as provider-scope completion.
`wait` and `waitall` retain cumulative ordering, deterministic failure reporting
in argument order, exact failure caching and one-time lease release. Fixed-
relation validation reuses the same transfer primitive.

- pending wait fell from 208 to 176 bytes; combined and grouped waits improved
  by 32 bytes at dependency arities 0/1/2/4/17; execute stayed 416 and cached
  wait stayed zero bytes;
- broad `wait` typed IR improved from 131 statements / 76 calls / 36 `Any`
  slots to 130 / 75 / 35. A rejected outer-catch shape was 235 / 135 / 67;
- fresh KCT found one matching MethodInstance each for receipt, prepared-scope,
  and lane-tail settlement, with no arity growth; JET was clean and AllocCheck
  reported only the known `IdSet` insertion ccall;
- focused CPU passed 443 assertions, full CPU 1,943/1,943, focused real Metal
  137/137, and full real Metal 592/592; and
- a faulting Metal kernel proves the copy surfaces provider failure, caches the
  same error object and releases every requested lease once.

Existing `waitall` tuple-arity specializations were measured and left unchanged:
they were not worsened, and no evidence justified erased storage or a cache.

## Rejected and no-change hypotheses

- Further static/dynamic launch surgery beyond C12 was rejected: runtime
  extent/capacity identity is bounded and no dominant leak remained.
- Broad preparation, Adapt, workspace, and relation payload rewrites were
  rejected where MethodInstances plateaued or cost merely moved phases.
- Carrying arbitrary canonical callbacks into recurrence was rejected; the
  final two-tag law passes only semantics recurrence consumes.
- The first receipt draft was rejected despite lower allocation because KCT
  exposed its 131→235 statement and 76→135 call regression.
- A universal “every copy synchronizes” claim was rejected. Nonempty Metal D2H
  is tested as completion; empty/alias explicitly synchronizes.
- No cache, registry, event wrapper, autotuner, backend-specific scientific
  executor, or retained projection graph was justified or added.

## Remaining costs and downstream pressure

KA's multithreaded CPU scheduler can still allocate tasks/events, and first
`Base.IdSet` insertion remains visible to AllocCheck. Saved scientific
snapshots, requested inspection copies, and cold workspace/device
materialization remain intentional. They do not justify a second scheduler.

The combined C13/C14 stack passed canaries on CorePotts `b4e5bda5` and Potts
`40b2ddf3`: Core CPU 17,321/17,321, Potts CPU 274/274, six completed Core Metal
files 429/429 plus inventory 3/3, and five Potts Metal files 131/131. They cover
lifecycle reconstruction, maintained relationships,
sequential/checkerboard execution, compiler reuse, warm stepping, remake,
continuation, authoring equivalence, and affected real Metal. A broader Core
site-tracker Metal file is conservatively partial/inconclusive: 228 assertions
passed before its 20-minute cold-compile cutoff, with no failure but no clean
file exit; the directly affected lifecycle-relationship witness separately
passed 14/14. R49/R50 keep these canaries; G09 owns longitudinal trends.

The audit demonstrated two different reusable owner laws, so they remain two
dense companions. C13 owns mathematical traversal; C14 owns provider settlement
and validation transfer. Neither planning identity appears in live APIs.
