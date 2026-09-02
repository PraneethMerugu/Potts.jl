# LM-1 Kaimon compiler investigation

Date: 2026-08-22

Disposition: **evidence recorded before edits; targeted remediation remains
compiler-gate red**.

This investigation used Kaimon session `a0735027` (`Potts-LM1`) connected to
the repository root. The session reported PottsToolkit 0.2.0, the exact local
CorePotts checkout, and active Revise. All measurements below were made in the
shared persistent Julia 1.12 REPL. They distinguish the first specialization
observed in that session from a repeated warm call; they are not substituted
for the frozen fresh-process LM-0 gate.

## Narrow timings

The corrected LM-0 witness was loaded without invoking its command-line main.
The first one-stage specialization observed in the session measured:

| Boundary | First elapsed | Compilation | Allocated | Warm elapsed | Warm compilation |
|---|---:|---:|---:|---:|---:|
| `plan(bound; backend=CPU())` | 4.048 s | 4.038 s | 596.6 MB | 2.04 ms | 0 |
| `prepare(plan)` | 5.132 s | 5.129 s | 1.103 GB | 0.592 ms | 0 |
| first `run!` + `wait` | 114.4 ms | 114.3 ms | 18.59 MB | 2.91 ms | 1.60 ms |

The prepared one-stage Unique program contains 12 physical
KernelAbstractions launches.

For a heterogeneous eight-stage program cycling Unique, Reduce, Resolve,
Collect, OrderedFold, Unique, Reduce, Resolve, the first full `plan` observed
after the one-stage probes still took 20.691 s, of which 20.677 s was
compilation. Its lowering type renders to 64,506 characters; its two groups
render to 24,502 and 22,858 characters. The repeated warm plan took 14.15 ms
with no compilation.

Preparation was then decomposed on that exact eight-stage lowering:

| Concrete operation | First elapsed | Compilation | Allocated | Warm elapsed |
|---|---:|---:|---:|---:|
| `_automatic_workspace` | 19.410 s | 19.405 s | 35.54 MB | 1.67 ms |
| `_prepare_stage_program` | 9.151 s | 9.147 s | 214.95 MB | 1.48 ms |
| `_stage_program_callback_facts` | 2.920 s | 2.919 s | 25.27 MB | 0.214 ms |
| `_prepared_freshness_authority` | 0.199 s | 0.199 s | 13.50 MB | not material |
| `_qualify_stage_backend!` | 5.053 s | 5.051 s | 876.68 MB | 0.316 ms |

These timings are narrow first-specialization probes in one persistent
session, so they are not additive cold-process totals. Their purpose is to
identify concrete compiler boundaries. Warm and Revise-aware iteration is
fast once the exact program types exist; first-call specialization is the
blocker.

## Planning decomposition

For a new four-stage concrete type, structural validation cost 1.485 s of
compilation and `_stage_planning` cost only 0.203 s. The four calls to
`_stage_lowering_group_input` cost 1.679, 1.544, 0.431, and 0.728 s of
compilation. `_stage_lowering_group` then cost another 5.734 s of compilation
and produced a 24,502-character group type.

Evaluator admission is not the dominant isolated operation. For the first
OrderedFold stage, `_admit_stage_evaluator` cost 0.081 s of compilation and
`_stage_lowering_entry` cost 0.045 s after draft construction. A singleton
`_stage_lowering_group` then cost 0.022 s, whereas a new four-entry group cost
3.208 s. The expensive boundary is the heterogeneous tuple/group
specialization and the workspace types it carries, not semantic projection or
the scalar evaluator protocol.

`@code_typed` and `@code_warntype` make the loss of precision explicit:

- `_stage_lowering_entry` returns a `UnionAll` because its workspace type `W`
  is not inferred exactly;
- `_stage_lowering_group` also returns a `UnionAll`, with an 11,044-character
  inferred return type, although the realized value has a concrete
  22,858-character type;
- `_automatic_workspace` infers
  `NamedTuple{(:groups, :execution_gate, :leases),
  <:Tuple{Tuple, Any, Vector{Any}}}` with 70 `Any` SSA values;
- `_prepare_stage_lowering_group`, a generated function, has observed method
  instances whose specialization signatures render to 26,206 and 26,191
  characters;
- `_stage_lowering_group` has observed method instances with 11,025- and
  10,620-character specialization signatures.

The warm executor itself is type-stable: the concrete Unique
`_execute_candidate_stage!` body has a concrete return type, and its
`@code_warntype` report contains no unstable body value. This rules out moving
semantics into a runtime interpreter as a response to a cold compiler problem.

## Root type-identity defect

`_WorkspaceLeafSlot{Name}` puts a generated diagnostic/allocation name in a
type parameter. The name includes the runtime stage index. Kaimon inspection
of otherwise identical Unique stages 1 and 6 showed:

```text
typeof(entry1.admission) === typeof(entry6.admission)  # true
typeof(entry1.workspace) === typeof(entry6.workspace)  # false
typeof(entry1)           === typeof(entry6)             # false

_WorkspaceLeafSlot{:stage_1_publication_1_grouping_destinations}
_WorkspaceLeafSlot{:stage_6_publication_1_grouping_destinations}
```

The stage number has no execution meaning. It is cold diagnostic/allocation
identity and violates the frozen specialization rule that names and runtime
IDs remain values. It also forces repeat specializations of the same
scientific and physical law at every position. `_WorkspaceLeafSlot` should be
a concrete value slot carrying `name::Symbol`; template shape may remain a
typed tuple or named tuple. This is authority-preserving type erasure, not a
second representation.

## One-stage physical expansion

For the one-stage Unique/identity witness (16 items, one publication, no
dynamic relation receipt), the 12 launches are, in queue order:

1. destination-grouping reset;
2. candidate-stage status/route reset;
3. candidate payload reset;
4. evaluator/candidate production;
5. destination validation;
6. block-local stable sort;
7. destination directory construction;
8. publication conflict/coverage validation;
9. publication settlement;
10. relaxed-atomic publication;
11. deterministic diagnostic/program-status finalization;
12. gated publication.

There is no merge launch at this size and no relation-receipt launch for the
computed Identity relation.

Three scheduled phases are provably empty for Unique:

- `_reset_candidate_payload!(::_RoutedCandidateWorkspace, ...) = nothing`;
- `_settle_publication!(... <:_UniqueLaw, ...) = nothing`;
- `_atomic_publication!(... <:_UniqueLaw, ...) = nothing`.

They are nevertheless wrapped in and submitted as distinct KA kernels.
Canonical Reduce and Resolve likewise have no atomic phase; their settlement
phases remain meaningful. RelaxedAtomic Reduce requires its atomic phase.

The three reset launches can become one domain-neutral candidate reset kernel
over the maximum bounded extent by factoring grouping and payload reset into
device-inline, index-wise operations. That preserves one CPU/GPU KA path and
all status semantics while deleting two barriers. Static phase requirements
can elide genuinely empty settlement and atomic launches inside the same
candidate executor; this is physical law specialization, not an alternate
execution architecture. Unique would fall from 12 to 8 launches.

The following barriers are semantically necessary and are not fusion targets:

- candidate evaluation must finish before grouping;
- grouping sort/directory must finish before conflict and coverage checks;
- settlement must follow validation for laws that require it;
- deterministic finalization must observe all validation work before
  publication and before a later Stage consumes program status;
- publication must remain gated and ordered after finalization.

Dynamic relation content validation also retains reset, parallel validation,
finalize-generation, and Stage receipt barriers. Their grid-wide ordering and
generation receipt meaning are real. A special single-dependency fusion would
multiply physical paths and is not justified by this evidence.

Backend qualification remains the exact same physical program under a closed
gate. Deleting it before equivalent real-device compilation evidence exists
would weaken the GPU contract and is out of scope.

## Ordered edit sequence

1. Make `_WorkspaceLeafSlot` name identity a value, update its structural
   validation and array-extraction consumers, and remeasure before changing
   grouping policy or generated preparation.
2. If the concrete return types remain excessively large, simplify the
   generated `_prepare_stage_lowering_group` boundary using the measured types;
   do not introduce an abstract executable container.
3. Replace the three candidate reset submissions with one index-wise KA reset
   kernel and statically omit only law phases whose methods are identically
   `nothing`.
4. Re-run the corrected one/four/eight/thirty-two-stage compiler matrix, exact
   physical launch inventory, focused CPU laws, and real-GPU witnesses. The
   frozen LM-0 envelope is not refit.

## Post-evidence direct edits

The investigation then made only edits justified by the evidence above:

- `_WorkspaceLeafSlot` now carries `name::Symbol` as a value. Identical stage
  laws at different source positions consequently share workspace-slot types.
- Candidate reset work is one KA launch. Empty Unique settlement and atomic
  phases, and empty canonical Reduce/Resolve atomic phases, are no longer
  submitted. The one-stage Unique expansion is now eight launches.
- Collect scan hierarchy scratch is two packed buffers (`prefix` and `sums`)
  addressed through an isbits `_CollectScanLevel` view. Runtime scan-level
  counting is allocation-free; no extent-dependent `prefix_1`, `prefix_2`, …
  field hierarchy remains.
- Candidate, Resolve, and Collect workspace constructors now build fixed
  shapes directly instead of through inference-erasing comprehensions.
- Inspection-only field dependencies and relation proofs were removed from
  executable lowering entries. `inspect` recomputes them through the same cold
  stage-planning authority.
- Package-owned automatic workspace skips validation intended for untrusted
  caller-owned workspace. Caller workspace retains the complete validation.
- `_StageEntryContext` is a host-only, value-erased diagnostic record. Exact
  publication and origin values remain available to inspection and errors but
  no longer parameterize executable types.
- `_WorkspaceLeaf` is now a host-only schema record: element type,
  dimensionality, path, shape, strides, and role remain exact values instead
  of six compiler-specialization axes. Runtime arrays and Stage/law types
  remain concrete and fully specialized.

Two hypotheses were tested and rejected rather than retained:

- Replacing `Any[]` orchestration with new generated tuple wrappers did not
  restore inference because `_materialize_workspace` deliberately returns a
  value-shaped tree. It slightly worsened the narrow measurements and was
  removed.
- Reducing compiler-group width from four to one produced four singleton
  groups but did not materially reduce four-stage cold time (15.54 s plan,
  20.21 s prepare, 0.53 s first execution). The bound was restored to four.

## Post-edit Kaimon evidence

All Unique, Reduce, Resolve, and Collect lowering entries in the four-stage
case now have concrete types. The exact lowering type rendered at 10,225
characters, down from 22,790 after the initial slot/Collect fixes and from
24,502 for the original four-entry group. The prepared type rendered at 8,741
characters. Its physical launch inventory is 33: 8 Unique, 9 Reduce, 9
Resolve, and 7 Collect.

A fresh Kaimon session after the cold-schema erasure measured:

| Boundary | Elapsed | Compilation | Allocated |
|---|---:|---:|---:|
| four-stage `plan` | 17.58 s | 17.55 s | 901.4 MB |
| four-stage `prepare` | 25.80 s | 25.79 s | 1.621 GB |
| first `run!` + `wait` | 0.358 s | 0.358 s | 63.86 MB |

Cold orchestration function barriers reduced the following preparation sample
to 1.549 GB but did not reduce wall time: 17.35 s plan, 26.81 s prepare, and
0.283 s first execution. They are retained only at the already inference-
erased internal boundaries; exact generated Stage preparation and KA kernels
remain specialized.

Warm/revised iteration on the same exact four-stage program is fast and has no
compilation: 15.52 ms plan, 2.57 ms prepare, and 0.082 ms execution. Thus the
remaining failure is exclusively first-specialization cost. The exact backend
qualification accounts for compiling the real 33-launch program under a
closed gate; it is not deleted or weakened.

The edits materially reduce compiler type surface and allocation volume, but
they do **not** yet satisfy the frozen LM-0 cold-compilation envelope. No
four/eight/thirty-two-stage pass is claimed and the compiler review remains
red pending further architectural deletion.
