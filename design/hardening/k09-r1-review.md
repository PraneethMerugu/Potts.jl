# K09-R1 gated state-copy adoption review

Date: 2026-08-15  
Status: **K09-R1 PASSED; CORRECTED DIRECT PATH SEALED; LOCALWORKSETS ADOPTION REJECTED**

Review object:

- [authorized K09 plan](k09-adoption-plan.md);
- [corrected baseline and admission census](k09-r0-census-and-admission.md);
- the exact K09 production and test sources identified below; and
- the complete CPU and qualified real-Metal evidence recorded in this review.

Path-sensitive exact source/test identities from the repository root:

| Surface | SHA-256 |
|---|---|
| `lib/CorePotts/src` Julia | `eddb9d0aaf2cd6b12c9b07d65cf65bd41e178bf34bc889e649bfbdb21bdbc9bd` |
| `lib/CorePotts/test` Julia | `33971cb5f9dd1ffb9ed7b4c0a3ed15b78ecd142784037553b2c9493e592390a8` |
| `lib/LocalWorksets/src` Julia | `0bba1bb4f965c37825d39f41a63dd7dc7cc7e288bf252b36e90665cce3e99ce5` |
| `lib/LocalWorksets/test` Julia | `a97b3d7f471e083fa8d4499bef2800d222a4dfb1780b2e2304987b88debb772b` |
| Metal Julia/project/manifest | `b04789d1b962320d46a755af8367c0425d85073d7536f8399c4713a6acc96100` |

Passing K09-R1 does not mean a LocalWorksets candidate passed. The K09-1 stop
condition fired before K09-2, so K09-3 never opened. This review confirms that
stopping was correct, that the corrected direct implementation is safe to
seal, and that no disposable candidate remains.

## Committee and procedure

Three independent reviewers examined the exact worktree before deliberation:

1. Julia API, package boundary, deletion economics, and maintainability;
2. JuliaGPU, KernelAbstractions ordering, compilation, launch, allocation, and
   real-Metal qualification; and
3. CorePotts transactions, lifecycle gates, failure isolation, determinism,
   checkpoints, and capability identity.

The reviewers first received only the plan, source, tests, census, and reported
evidence. All three independently voted to stop LocalWorksets adoption. More
importantly, all three found the same P0 in the direct oracle: an unpacked CPU
relationship vector was treated as a terminal array, so element assignment
shallow-copied nested references between transaction banks.

The original ballot is preserved rather than overwritten:

| Reviewer | Freeze reported R0 | Open K09-2/K09-3 | P0 | Principal reason |
|---|---|---|---:|---|
| API/package | block | reject | 2 | unsupported non-isbits relationship unit and missing nested isolation |
| JuliaGPU | block | reject | 2 | reproduced cross-bank nested aliases; Metal packing hid the CPU defect |
| Core semantics | block | reject | 1 | rollback, failure containment, and checkpoints could observe corrupted bank isolation |

## Correctness remediation

The direct oracle was not weakened or excused. It was corrected before R0:

- copy units and physical leaves became separate concepts;
- unpacked `ProgramRelationshipState` vectors gained one CPU-qualified,
  field-wise gated KernelAbstractions copy kernel;
- complete copy-unit types, axes, backends, and nested fields are validated
  before any launch;
- physical bank validation checks all cross-bank pairs with identity or
  `Base.mightalias`, including cross-position and empty-array aliases;
- `BitArray` physical leaves are honestly classified as CPU storage instead of
  being passed to an unsupported KernelAbstractions backend query;
- the hot path retains concrete tuple recursion and does not construct the
  cold `Any[]` physical-leaf census; and
- the common gate predicate is shared by ordinary arrays and CPU relationship
  units without adding a wait.

Regression evidence was added for deep equality, destination mutation without
source mutation, mismatched nested axes and types before launch, closed-gate
preservation, forged cross-position and empty aliases, post-MCS checkerboard
bank isolation, and relationship-bearing checkpoint continuation.

The first remediation review found three additional seams: `BitVector` lacked
a provider query, unit validation had to finish globally before recursive
enqueue, and identity had to supplement `mightalias` for empty arrays. Each was
reproduced and fixed. The second remediation review found no remaining runtime
P0 or P1.

## Contradiction/red-team round

The required contradiction was stronger than the plan anticipated: reviewers
attempted to show that a smaller direct implementation was preferable before
any LocalWorksets candidate was built.

That attempt succeeded:

- the initial direct projection removed the old type-by-type recursive copier
  and the two redundant self-copy passes;
- the correct CPU relationship representation necessarily needs a specialized
  field-wise unit;
- LocalWorksets cannot bind the non-isbits relationship unit, while flattening
  exposes a `BitVector` rejected by the reviewed CPU root-storage policy;
- a CPU direct fallback would retain the copy projection, validator, special
  kernel, and scan-tail kernel while adding LocalWorksets preparation, leases,
  events, settlement, inspection, capability, and checkpoint plumbing; and
- the corrected direct code already uses KernelAbstractions implicit ordering
  with no intermediate synchronization.

The packed Metal `U=12` profile and its three preliminary length groups remain
interesting for a future direct compile-time grouped kernel, but they do not
justify a Metal-only LocalWorksets path. Such work is outside K09 and is not
authorized here.

## Final independent ballots

After the exact remediation and evidence-vocabulary corrections:

| Reviewer | Corrected direct K09 | LocalWorksets K09 | P0 | P1 | P2 | Preserved scope constraint |
|---|---|---|---:|---:|---:|---|
| API/package | freeze | reject | 0 | 0 | 0 | physical leaves and copy units must remain distinct in future evidence |
| JuliaGPU | freeze | reject | 0 | 0 | 0 | CUDA/ROCm remain unqualified; packed grouping is only diagnostic |
| Core semantics | freeze | reject | 0 | 0 | 0 | immutable relationship layout remains centrally constructed, not a public extension surface |

No reviewer asserted CUDA or ROCm support. No reviewer authorized a new
LocalWorksets mechanism, storage binding, execution identity, or operation
family. The final artifact sign-off found no P0, P1, or P2 finding; the final
column preserves explicit scope constraints for later work.

## Qualification

The exact corrected candidate received the following evidence:

| Lane | Result |
|---|---|
| focused CPU relationship copy/schema | deep copy, nested mutation isolation, malformed schema prelaunch rejection passed |
| K09 CPU alias/queue packet | `P=7`, `U=7`, twelve queued MCSs, ten warm submits at 67,200 bytes, one settlement, one synchronization, twelve commits |
| complete CorePotts CPU package | passed, including 17/17 relationship isolation, 53/53 atomic relationship runtime, 26/26 logical continuation, K09 35/35, and fresh-process adapter boundaries |
| complete LocalWorksets CPU package | passed; no K09 mechanism or admission row was added |
| authoritative PottsToolkit CPU package | 2,667/2,667 passed |
| targeted real-Metal K09 packet | passed: alias, 12-MCS queue, lifecycle parity, capacity failure, and canonical failure rows |
| complete real-Metal runner | exit 0; extension loading, cross-domain mechanisms, native components 37/37, promoted queue/failure, K09 alias/lifecycle/failure, policy, relationship, and negative-evidence rows passed |

The CPU K09 queue preserves KernelAbstractions implicit ordering and reports
one final provider synchronization. The removed self-copy passes add no waits.
The direct execution/capability/checkpoint identity is unchanged because the
change restores the already-declared transaction semantics rather than adding
an alternative engine.

The targeted real-Metal queue reported `P=7`, `U=7`, copy-unit lengths
`(36, 2, 2, 2, 4, 8, 2)`, one settlement, one synchronization, and twelve
commits. Its ten warm enqueue measurements were:

```text
1,075,344  1,075,264  1,076,016  1,075,408  1,075,152
1,076,304  1,075,712  1,074,960  1,076,016  1,075,712 bytes
```

## Source disposition

The initial direct cleanup reached `-65` raw production lines across the three
K09 files. The relationship isolation correction makes the final exact delta
`+74` relative to the opening audit. This is recorded as required correctness
cost, not hidden or credited as adoption success.

A LocalWorksets K09 candidate was never created. There is therefore no parallel
implementation, dormant selector, candidate capability, checkpoint branch,
inspection row, lease/event tail, or temporary source to delete.

## Final decision

K09-R1 passes with this bounded disposition:

- seal the corrected direct K09 implementation;
- retain the scan-tail copy as a direct CorePotts lifecycle mechanic;
- reject K09-2 and K09-3 under the common CPU/Metal and net-deletion rules;
- preserve K01 and L01 as closed;
- do not tune thresholds, weaken storage admission, or invent a new
  LocalWorksets mechanism; and
- leave G6 and the MethodOfLines input-field work exactly deferred.

Any future reconsideration requires a separately authorized gate with a new
storage representation or at least two unrelated consumers. This review is
not that authority.
