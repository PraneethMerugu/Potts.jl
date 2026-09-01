# LM-2A publication and planning consolidation

Status: implemented; compiler, Metal, and independent review evidence are
recorded below when the gate completes.

## Result

LM-2A leaves the LM-1 stage-local executor as the only production path. It
does not introduce a publication IR, scheduler, alternate planner, backend
branch, compatibility layer, or new public API. The live LocalWorksets source
tree contains 17,356 lines in 34 Julia files. The working checkpoint recorded
immediately after LM-1 contained 17,875 lines in 36 files, a 519-line gross
decrease and two whole source files removed. Because that predecessor was a
working-tree checkpoint rather than a commit, this numeric delta is supporting
context, not gate evidence; the machine gate instead proves each deleted file,
symbol family, and surviving authority directly.

Line count is supporting evidence. The substantive result is the reduction in
semantic and mechanical authorities:

| Concern | LM-2A owner |
|---|---|
| publication dimensions | `_candidate_publication_dimensions` plus the typed law |
| Stage projection | `_StageProjection`, computed once during lowering |
| workspace schema and lifetime | one `_WorkspaceAuthority` |
| workspace allocation/reconstruction/validation/accounting | the same `_WorkspaceAuthority` leaves and template |
| plan inspection dependencies | cold projection from the semantic work and lowering entry |
| relation validity | sealed `RelationProof` plus queued relationship receipts |
| program failure closure | program gate plus law-specific validation/finalization barriers |
| execution | the sole stage-local KernelAbstractions path |

## Direct deletions

- Deleted `execution/evidence_support.jl`; it had no production callers and
  retained the last combined/conjunctive evidence authority.
- Deleted `execution/arbitration_support.jl`; it had no production callers.
- Deleted the duplicate `_stage_slots` projection family in `bound_work.jl`.
  `_StageProjection` is now the sole slot projection.
- Deleted `_StageProgramWorkspace` and its stage-local path rewriting,
  requirement, allocator, validator, and array-flattening methods.
- Deleted dead workspace spec reconstruction/byte helpers and the private
  Collect test allocator.
- Deleted obsolete combination capability predicates, component record-store
  probes, single-resolved probes, and `runtime_conjunctive_validation`.
- Deleted separate Reduce and Resolve dimension calculations. Unique, Reduce,
  and Resolve derive record capacity, destination extent, and publication
  width through one checked helper.

## Workspace consolidation

`_WorkspaceAuthority` now contains immutable leaves, the exact container
template, and alias scopes. One flattened program authority owns:

- a vector of per-stage templates;
- a vector of persistent relationship-receipt templates;
- the persistent program validation gate.

Per-stage scratch may reuse storage across distinct stage scopes, while
receipt and gate leaves are persistent and cannot alias any other leaf. The
same prepared authority drives automatic allocation, caller buffer
reconstruction, exact container validation, alias checking, backend checking,
byte accounting, and inspection. Caller-supplied multi-stage workspace is now
tested through the public `workspace_requirements` / `allocate_workspace` /
`prepare` lifecycle.

The erased vectors are intentional cold/prepared containers. They prevent a
return to whole-program tuple specialization; concrete stage and kernel
arguments are recovered at the stage-local dispatch boundary.

## Planning and inspection consolidation

Each stage performs `_stage_planning_entry` once for production lowering and
stores its typed `_StageProjection`. Inspection recomputes its descriptive
producer dependencies cold from the semantic work and actual lowering; it does
not store a second dependency authority in the entry or prepared runtime.
Planning and execution never consume inspection output.

## Physical execution and count terminology

No transaction barrier was fused or weakened. The four-stage synthetic
inventory remains:

```text
1 direct Unique + 7 Reduce + 7 Resolve + 6 Collect
= 21 stage-local physical phases
```

One program-scope validation reset precedes those phases, so the complete CPU
provider submission contains 22 base KernelAbstractions launches. Relationship
receipt phases are included in the affected stage's canonical phase tuple.
Only unresolved execution dependencies add the separately reported dynamic
join count.

## Correctness and package quality

The official `Pkg.test()` gate passes, including:

- Aqua and ExplicitImports package quality: 18/18;
- Unique, canonical and relaxed Reduce, Resolve, Collect, and OrderedFold;
- successful and deliberately failing transaction paths;
- dynamic relationship receipts and successor gating;
- structural binding, relation preparation, composition, and device views;
- caller-owned multi-stage workspace reconstruction;
- exact cold planning and inspection dependency ownership.

The edit also corrected stale tests that still treated raw `_bind_work` as a
validation boundary, expected the deleted tuple lowering identity, or claimed
that sealed proof minting had not landed. These are test-authority corrections,
not compatibility behavior.

## Machine evidence

- LM-1 predecessor gate: `LocalMath LM-1 machine gate: approved`.
- Frozen compiler matrix: `compiler-qualified-synthetic-current/manifest.toml`.
- Real Metal packet: recorded in this directory after execution.
- Independent committee decision: `final-review.md`.

The subsequent preparation cutover kept the common workspace authority while
erasing cold plan/workspace/callback graphs from `PreparedWork`, establishing
one cached callable-analysis authority, and narrowing common phase ABIs. The
raw current-source compiler matrix is the timing authority; historical focused
probes are diagnosis evidence, not qualification evidence.

Post-stabilization requalification records current fresh-process host
compilation of 2.411 s at one Stage and 11.304 s at four Stages. These pass the
frozen 2.851 s and 15.047 s ceilings, respectively. The direct fix replaces
tuple-specialized workspace-template discovery and deletes duplicate Stage
workspace validation; it does not add a cache, executor, or semantic authority.
