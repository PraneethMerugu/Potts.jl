# LM-1 production stage-local spine cutover

Date: 2026-08-22

## Decision

The qualified host-erased prototype has replaced the production tuple/group
spine. There is no old/new selector, compatibility representation, or retained
prototype runtime.

Production now uses:

```text
LocalWork
  -> globally validated structural binding
  -> one compact Stage-local compiler slice per occurrence
  -> Vector{_AbstractStageLoweringEntry}
  -> one concrete admission/executor per entry
  -> Vector{_AbstractPreparedStageLaunch}
  -> concrete `_enqueue_stage!` dispatch
  -> KernelAbstractions
```

The abstract vectors are host-only. Kaimon typed inspection of the concrete
`_enqueue_stage!` boundary returned `Nothing` with no `Any` slots. Kernel
arguments remain concrete and adapted before KA submission.

## Direct deletions

The cutover deleted:

- `_StageLoweringGroup`;
- `_PreparedStageGroup`;
- `_StagePreparationGroupInput`;
- `_STAGE_COMPILER_GROUP_SIZE`;
- generated `_stage_lowering_group`;
- generated `_prepare_stage_lowering_group`;
- tuple-recursive `_execute_stage_group!` / `_execute_stage_groups!`;
- grouped workspace-root ownership and indexed group rewriting;
- `_StagePlanning` and the complete-program projection/dependency tuples;
- `benchmark/lm0/host_erased_spine_prototype.jl`.

Inspection derives dependencies one Stage at a time. Workspace ownership is
one Stage authority per erased entry plus the shared execution gate.

## Physical identity Unique form

The pointwise form is a physical layout of the Candidate family, not a public
executor. It is admitted only for:

- one plain width-one `Unique` publication;
- total coverage and unreachable empty behavior;
- identity publication;
- no controls or dynamic relation dependencies;
- no Collection accesses;
- exact item-local identity reads.

All other Unique forms remain buffered. The direct form has no Stage-private
validation workspace because its admission proves that no Stage-local runtime
failure remains. It still checks the shared predecessor/program gate and uses
one KA kernel.

## Evidence

Kaimon inspection of a production one-stage preparation reported:

- lowering storage: `Vector{_AbstractStageLoweringEntry}`;
- runtime storage: `Vector{_AbstractPreparedStageLaunch}`;
- concrete launch recovered before enqueue;
- concrete `_enqueue_stage!` return type `Nothing`;
- no `Any` slot in the concrete typed body.

A 32-stage production plan contained five distinct entry types for five law
schemas. Repeated entries 1/6, 2/7, and 3/8 had identical concrete types.
Compilation therefore scales by distinct schema rather than occurrence count.

The initial fresh-process CPU compiler observations after the cutover were:

| stages | construction | binding | planning | preparation | first run | total |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 0.1670 | 0.1445 | 2.1714 | 0.7015 | 0.1236 | 3.3134 |
| 4 | 1.1978 | 0.2400 | 9.5052 | 9.2744 | 0.1322 | 20.3496 |

These observations motivated LM-1B and the final concrete tuple-preparation
work. The closing three-replicate matrix now passes the frozen ceilings; see
`compiler-closure.md`.

Warm CPU observations were approximately:

- one stage: 4.7 microseconds median, 1,200 host bytes;
- four stages: 48.6 microseconds median, 10,944 host bytes;
- zero Julia compilation.

The production eight-stage program executed Unique, Reduce, Resolve, Collect,
and OrderedFold on a real Apple Metal device through the same spine. A focused
Candidate plus dynamic relation-receipt Metal witness passed 5/5 numerical and
lifecycle assertions. The direct item-local kernel also previously produced
exactly `Int32.(2:17)` on Metal.

## Completed follow-up

LM-1B completed the narrow Candidate/Collect phase ABI and the proven
settlement/projection launch deletions. Concrete tuple-local preparation then
closed the remaining compiler gap without a new cache, scheduler, or IR. See
`lm1b-physical-abi.md` and `compiler-closure.md`.
