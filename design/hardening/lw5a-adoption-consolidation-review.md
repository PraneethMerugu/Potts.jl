# LW-5A focused adoption-and-consolidation review

Status: PASS; revised LW-5A clears; only non-promoted B0 is opened

Date: 2026-08-13

Reviewed specification:
[LW-5A adoption-and-consolidation amendment](lw5a-adoption-consolidation-amendment.md)

Reviewed production source commit: `bc5729f3db636c936ad2dfee46c5d1f1ced56059`

Reviewed production source tree: `b30a56cc84395225d292a2eca175c8f4e15e99d9`

Qualified behavioral product: `8b710692a84f79b1411a1443a27a9ee099327bcf`

Qualified behavioral tree: `b360f2b06b404b34d448c75f3bdd5b012d839dc7`

Final amendment SHA-256:
`3e3ecd23c8d63e1a4d7d6ef4662f52d5c044d3c1f67cff4f9d700114206254b0`

## Review boundary

This is a focused specification and source audit. It does not rerun runtime
qualification because no production or test execution source changed. It
does not implement B0, the proposal pilot or LW-5B. The last qualified
CPU/Metal behavioral evidence remains attached to the unchanged source
product above; it is not presented as evidence for an unimplemented adapter.

The review does not reopen LocalWorksets architecture, naming, lifecycle,
output families, central lowering or ownership. It asks whether the amended
gate is complete, honest and decisive enough to authorize only B0.

## Exact review checks

The review inspected:

- all 36 inventory IDs: C00-C08, K01-K12, L01-L12, T01-T02 and R01;
- the inherited 41-kernel census and the non-kernel execution/compiler rows;
- all three amendment matrices, in which every ID occurs exactly once;
- `_checkerboard_evaluate_kernel!`, its factory and its per-color call;
- `CheckerboardExecutionState`, `_ProposalEvaluationContext`,
  `ResourceAccess`, descriptor evaluation and canonical folding;
- LocalWorksets direct/heterogeneous declaration, lowering, preparation,
  binding/access validation and execution; and
- the frozen oracle, checkpoint, launch, allocation and performance
  obligations.

The working tree has no execution-source difference from the qualified
product across `lib/CorePotts/src`, `lib/CorePotts/test`,
`lib/LocalWorksets/src`, `lib/LocalWorksets/test`, the root `src`/`test`,
`integration` and the qualified Metal runner.

## Reviewer-role memos

### Scientific ownership reviewer

**Ruling: PASS.**

Every row identifies its scientific owner and retained semantics. The
amendment keeps proposal views, descriptor evaluation, Hamiltonian source
order, `OrderedFold`, tracker views, acceptance and addressed RNG in
CorePotts. It also rejects or retains the rows whose principal meaning is
scheduling, publication, settlement, lifecycle planning/commit,
relationships or checkpoints.

The proposed return bridge does not transfer scientific authority. It is a
CorePotts representation of the same bounded descriptor results for the
generic LocalWorksets call convention. Its exact equivalence is a pilot
oracle obligation.

### Execution-consolidation reviewer

**Ruling: PASS WITH VALUE HOLD.**

The decisive pilot names a real deletion unit: the custom evaluation kernel
wrapper, its factory and its per-color positional launch call. It also
requires generic topology, bindings, access/alias validation, preparation,
lifetime, backend admission and inspection to replace their bespoke
equivalents. One launch replaces one launch. Calling the old kernel from a
LocalWork operation is vetoed.

Substantive caution: the existing kernel occupies lines 232-308 of
`checkerboard_kernels.jl`, 77 lines including the scientific body. The
execution-only wrapper is therefore small. A large projection or return
framework would lose the deletion test even with perfect parity. The ledger,
second-use witness and hard veto make this a pilot failure rather than a
success by assertion.

### Julia derivability reviewer

**Ruling: PASS TO IMPLEMENTATION WITH DISSENT.**

The derivation sources are real: `ResourceAccess`, compiled domain resources,
the proposal ABI and output metadata jointly contain the necessary authority.
The generic LocalWorksets operation receives validated array bindings plus
bounded submission values and supports a concrete isbits callable and named
heterogeneous result.

However, derivability is not yet proved. `CheckerboardExecutionState` is a
nested runtime object, while LocalWorksets validates array storage bindings;
the current `evaluate_proposal_contributions!` also mutates an
`AbstractVector`, while the generic kernel requires a concrete inferred
returned `NamedTuple`. The amendment now forbids capturing array-backed state,
hidden output mutation and undeclared output reads, and requires a bounded
type-stable return bridge.

The dissent is substantive: B0 can prove ordinary binding derivation but
cannot prove this scientific execution-view/return bridge. The decisive pilot
must be rejected—not broadened—if inference or exact CPU/Metal compilation
fails. This is an assigned implementation blocker, not evidence that a new
LocalWorksets family is needed.

### JuliaGPU and performance reviewer

**Ruling: PASS WITH QUALIFICATION HOLD.**

The amendment preserves backend-neutral source, KernelAbstractions implicit
ordering, one-for-one launch replacement, queueable MCSs and one settlement
boundary. It prohibits vendor branches, host callbacks, hidden waits, device
allocation and a new scheduler. CPU and real Metal are required before any
pilot pass; CUDA/ROCm are not claimed.

The accepted generic direct lowering already executes one kernel and zero
algorithmic-workspace phases for independent outputs. That makes the proposed
shape credible. It does not prove the CorePotts callable will infer or compile,
nor that a bounded contribution result will avoid specialization or register
cost. The unchanged paired noninferiority protocol and compile-footprint
ledger correctly retain those as evidence requirements.

### Product-value and red-team reviewer

**Ruling: CONDITIONAL PASS.**

The amendment no longer treats representability as adoption. The deletion,
derivation and second-use tests directly target the failure mode in which
LocalWorksets becomes another wrapper. The K02 non-promoted witness is a
credible same-domain reuse test, while existing LBM/spring/FEM evidence
continues to establish cross-domain mechanism scope.

No current evidence proves that CorePotts or PottsToolkit is smaller or
clearer. The gate instead defines a falsifiable way to learn that. Later
families are conditional, individually reviewable and stoppable. This is the
correct strength of claim before implementation.

## Findings and dispositions

| ID | Priority | Finding | Owner and disposition |
| --- | --- | --- | --- |
| F1 | P1 implementation hold | The shared execution-view and fixed-size return derivation are not yet implemented or device-qualified. | CorePotts B0/pilot owner. B0 may establish the shared binding skeleton; the proposal pilot must prove the full bridge on CPU/Metal. Failure rejects the pilot and does not authorize a LocalWorksets extension. |
| F2 | P2 value risk | The 77-line direct evaluation unit contains mostly retained science, so its removable wrapper is small relative to a potentially complex adapter. | Proposal-pilot ledger owner. Shared and family-specific source, compilation footprint and direct-oracle cost must be reported; the large-adapter veto is binding. |
| F3 | P2 cleanup risk | A disposable B0 could become permanent duplicate plumbing despite being non-decisive. | B0 owner. Its review must explicitly remove it or promote only genuinely shared derivation code before the proposal pilot is reviewed. |

There are no P0 findings and no unowned P1 findings. F1 is intentionally open
as an implementation hold; it cannot be waived by documentation or by B0.

## Seven-question ballot

| Question | Ballot | Basis and preserved dissent |
| --- | --- | --- |
| Inventory completeness | **PASS** | All inherited stage IDs are present once in each of matrices A-C, with owner, machinery, retained semantics, replacement, representation, deletion, adapter, oracle, blocker and one closed disposition. The 41-kernel census remains evidence. |
| Scientific ownership preservation | **PASS** | Domain science, scheduling, transactions, publication cuts, settlement and checkpoints stay in CorePotts; PottsToolkit keeps authoring/MTK/SciML ownership. |
| Credible execution-machinery replacement | **PASS WITH VALUE HOLD** | The proposal pilot replaces a named kernel wrapper/factory/call and generic support machinery, with one launch for one and a mandatory ledger. F2 cautions that the actual deletion unit is small. |
| Adapter derivability | **PASS TO IMPLEMENTATION WITH DISSENT** | Authoritative metadata exists and the accepted mechanism can carry validated arrays and a typed callable/result. F1 records that nested-state projection and mutation-to-return conversion remain unproved and are hard vetoes at the pilot. |
| Pilot decisiveness | **PASS** | Exact semantic/RNG/checkpoint parity alone cannot pass; deletion, derivation, second use, one-launch parity, CPU/Metal qualification, performance and direct/reference disposition are all required. |
| Conditional later-family roadmap | **PASS** | Candidate generation, clears/copies, counters, assignments, trackers, bounded emissions and conflict mechanisms have explicit conditional rows; domain orchestration and unsupported scans/sorts are retained or rejected. |
| Can the work make CorePotts/PottsToolkit materially smaller and clearer? | **CONDITIONAL PASS; NO ACHIEVEMENT CLAIM** | The tests can demonstrate this outcome and force a stop if they do not. No reduction is claimed before the pilot ledger passes. Potts authors remain insulated from LocalWorksets. |

## Freeze ruling

The revised LW-5A passes as an adoption-and-consolidation specification gate.
It opens only the disposable, non-promoted B0 integration probe. A passing B0
may open implementation of the decisive proposal-evaluation pilot under a
separate hold; it does not itself establish adoption value.

No production migration, default switch, direct-oracle retirement or later
family is authorized by this review. LW-5B remains limited to the ordered B0
then conditional-pilot work defined by the amendment. The MethodOfLines input
field integration and G6 remain deferred.

The review's controlling interpretation is:

> Potts authors see no LocalWorksets API; CorePotts owns the complete science;
> and a candidate passes only when reusable, inspectable LocalWorksets
> machinery actually replaces eligible bespoke execution code.
