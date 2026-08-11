# LW-R2B LocalWorksets Bounded-Mechanism Review

Date: 2026-08-11

Decision: **PASS**

Current severity count: P0 = 0, P1 = 0, P2 = 1 nonblocking debt

## Scope

LW-R2B reviews whether the bounded LW-4B mechanisms are correct, honestly described, portable in
source and qualified on the exact reviewed CPU/Apple M1 Metal environments. It separately asks
whether any present choice obstructs the later general LocalWorksets package. It does not freeze
Level-1 spelling, reopen the accepted architecture/lifecycle/naming, qualify CUDA or ROCm, remove
the specialized parity oracles, authorize a new execution family, begin LW-4C or begin LW-5.

The corrected candidate is identified by
[`lw4b-b5-final-hashes.sha256`](lw4b-b5-final-hashes.sha256). Requirement ownership and all 122
explicit row dispositions are in
[`lw4b-general-mechanism-implementation-matrix.md`](lw4b-general-mechanism-implementation-matrix.md).
Complete qualification is in
[`lw4b-b5-qualification-evidence.md`](lw4b-b5-qualification-evidence.md).

## Committee procedure

Three fresh-context reviewers independently inspected the first exact candidate before
deliberation:

- API, package boundary and cross-domain scope;
- numerical semantics, determinism and CorePotts preservation; and
- JuliaGPU lowering, KernelAbstractions ordering, admission and performance.

They verified the then-current manifest, reran relevant CPU/Metal suites, issued independent memos,
and then completed a contradiction/red-team round. The first candidate received no inherited
benefit from LW-R2A or earlier prototype audits.

## First-candidate veto

The first candidate's numerical and performance suites were green, but the committee vetoed it.
Two independently reproduced preparation-integrity defects survived contradiction:

1. a more-specific external operation method added after `prepare` could replace the exact method
   that validation had inspected; and
2. a mutable caller workspace holder could substitute a scratch-array reference after validation,
   so execution dereferenced a different array while identity checks inspected cached originals.

The numerical and JuliaGPU reviewers classified both as P0. The API reviewer retained the workspace
substitution as P0 and classified the method-substitution path as P1 while still requiring it to be
fixed. The classification disagreement is preserved; all three agreed the exact candidate could
not advance.

The committee also retained these P1 findings:

- an external fake combination-law subtype rejected only at `run!`, not at construction/planning;
- item, route, record, segment, byte and terminal-offset arithmetic did not consistently close the
  Int32 device ABI;
- `inspect(WorkPlan)` omitted planned phases and important per-port publication/failure facts;
- generic reads could not honor the accepted submission-bound storage contract;
- evidence prose incorrectly described failed provider tails as drained when leases and zero
  drained counters were intentionally retained; and
- the CPU performance script printed a failed report without failing the evidence process.

Exact-`UInt64` epochs, empty resolved-route names and duplicated mechanism machinery were retained
as P2 findings. No reviewer argued that these defects invalidated the accepted architecture or the
cross-domain value of LocalWorksets itself.

## Bounded remediation

| Finding | Corrected exact behavior | Executable evidence |
|---|---|---|
| operation method substitution | `prepare` records exact external operation and qualified deterministic-law methods; `run!` rechecks them before a new submission whenever Julia's method world changes; `wait` does not block draining an already submitted prefix | direct and buffered hostile late-method cases reject prelaunch with unchanged outputs, zero submissions, free leases and no poison |
| workspace reference substitution | workspace structural containers are recursively immutable; mutable array leaves remain legal and are identity/layout checked | mutable structural workspace rejects during `prepare`; all immutable NamedTuple workspaces execute on CPU/Metal |
| late fake-law rejection | `combined` requires the exact centrally defined concrete law and a closed deterministic/fast mode | external `_AbstractCombinationLaw` subtype rejects at construction |
| unchecked device bounds | checked Int/Int32 product/sum/count helpers cover item, destination, route, record, segment, byte, transfer and terminal-offset facts | lazy `typemax(Int32)+1` item and oversized two-record fixtures reject without allocation/indexing |
| incomplete plan inspection | plan evidence includes flattened phases and per-port publication phase, post-launch failure visibility and empty-destination behavior | direct, combined, resolved and sequence inspection assertions |
| missing generic dynamic reads | `storage_slot` freezes exact concrete array type plus backend/device/layout; warm submissions may use a distinct array identity of that same qualified representation | CPU generic dynamic-read test and CPU/real-Metal D2Q9 witness use distinct source arrays; view substitution rejects prelaunch |
| evidence/prose weakness | failed shared tails report zero drained counters and retained leases; CPU performance exits nonzero on a failed bound | provider-failure test plus process-enforced performance command |
| P2 closure | topology epoch is exactly `UInt64`; resolved route symbols are nonempty | focused negative tests |

The remediation adds no execution family, opaque callback, host fallback, synchronization or domain
semantics. External declarations still lower only through central package-owned admission.

The refreshed reviewers then withheld their final ballots for four additional bounded defects:

- plan inspection did not yet report every accepted per-port route/count/maximum/coverage-law and
  determinism fact;
- invariant `PreparedWork` fields remained assignable after preparation;
- preserved resolved/conjunctive profiles did not yet share the generic exact-`UInt64`, Int32 ABI
  and checked-byte admission; and
- a hostile method addition after submission could make `wait(event)` reject before synchronizing,
  stranding a real queued tail.

The final candidate completes the evidence, makes structural prepared fields `const`, applies the
same checked ABI to specialized profiles, and invokes the already-admitted wait path in the last
successfully validated submission world. Tests prove a post-submission hostile method cannot block
the one required synchronization and cumulative drain. Lease retention was narrowed to
submission-bound storage; prepared static storage, workspace and runtime remain retained directly.

The first ballot over that hash set still did not clear: the API reviewer reproduced `ports ===
nothing` for the preserved resolved-selection and conjunctive plans and found no explicit
empty-destination fact on direct independent ports. The numerical and JuliaGPU reviewers otherwise
passed the candidate. The final remediation completes every accepted specialized port's
route/count/bound/law/publication/failure/empty/determinism evidence and explicitly reports total-
coverage impossibility versus partial-coverage preservation for independent ports. The standalone
suite now asserts those facts rather than relying on inference.

The numerical reviewer then retained a second P1: literal-true and literal-false resolved masks
were indistinguishable because the evidence reported only the optional storage-mask binding, while
the item-aligned conjunctive loser value was incorrectly labeled as an empty keyed-destination
publication. The final correction reports actual emission mask separately from mask binding and
reports conjunctive item-result layout, empty loser result, absence of keyed public output, and the
private arbitration tables' exact no-winner sentinel state. Focused tests distinguish both literal
masks and every conjunctive state.

## Corrected exact evidence

| Lane | Exact result |
|---|---|
| standalone LocalWorksets | 511/511 |
| complete CorePotts CPU | 17,462/17,462 |
| authoritative PottsToolkit root | 2,232/2,232; wall time excluded because the laptop travelled during the run |
| CPU witnesses | D2Q9, spring deterministic/fast, matrix-free FEM and z-buffer references plus invalid cases pass |
| CPU direct parity | D2Q9 upper95 0.9691686842; z-buffer upper95 1.0111241115; threshold 1.05 |
| qualified real Metal | cross-domain 8/8; native components 37/37; all hostile/boundary/lifecycle/queued rows pass; exit 0 |
| Metal direct parity | final exact run D2Q9 upper95 1.0102096167 and z-buffer 1.0433520766; prior exact runs and isolated repeats also pass; threshold 1.05 |
| CorePotts Metal parity | upper95 1.0237674656; 600 submitted/drained; zero topology-transfer bytes; no poison |
| ordering/failure | one executable KA synchronize; implicit ordered launches; 12 MCSs queue behind one wait; failed shared tail retains leases with drained `(0,0)` |
| portability claim | vendor-neutral execution source; qualification limited to CPU and exact reviewed Apple M1/Metal metadata |

## Complexity and preservation disposition

LocalWorksets is preserved because D2Q9, spring, FEM, generic resolved selection and CorePotts are
unrelated consumers of the same validated topology/conflict/workspace/lifetime layer. Its 7,745
physical production lines are debt, not an achievement by themselves.

The accepted ownership boundary remains:

- KernelAbstractions owns portable kernel execution and implicit ordering;
- LocalWorksets owns validated local connectivity, conflict semantics, bounded lowering,
  workspace, lifetime and inspection; and
- domain packages own physics, clocks, RNG, solver behavior, transactions and checkpoints.

The single-resolved performance specialization has measured justification. Duplication among
generic buffered, specialized resolved and conjunctive machinery; dense topology/storage/workspace
construction; declaration count; and validation layering remain mandatory LW-4C consolidation
targets. Safety, admission and evidence guarantees cannot be removed merely to reduce line count.
No new execution family is admissible without two unrelated concrete consumers. LW-5 must show
that real CorePotts/PottsToolkit operations become materially smaller, clearer and easier to
inspect; otherwise the authoring surface or abstraction must be simplified before expansion.

## Refreshed independent ballots

All three reviewers verified the 61-row exact manifest and reran the standalone suite at 511/511.
Their independent decisive ballots were:

| Reviewer | P0 | P1 | P2 | Bounded correctness | Honest narrowness | Future mechanism room | Extraction obstruction | Open LW-4C |
|---|---:|---:|---:|---|---|---|---|---|
| API/package boundary | 0 | 0 | 1 debt | yes | yes | yes | none; medium-high consolidation effort | yes |
| numerical/CorePotts | 0 | 0 | 0 | yes | yes | yes | none | yes |
| JuliaGPU/backend | 0 | 0 | 1 debt | yes | yes | yes | none | yes |

The P2 entries are the same nonblocking 7,745-line consolidation/authoring debt, not a semantic or
source defect. The JuliaGPU reviewer additionally preserves a performance-monitoring warning: the
final Metal z-buffer upper-95 value is 1.043352 against 1.05. Qualification remains limited to the
reviewed CPU and Apple M1 Pro/Metal row; no CUDA/ROCm claim is inferred.

## Separate gate questions

1. **Is this a correct, bounded LW-4B implementation?** Yes, unanimously.
2. **Is it honestly narrow?** Yes. It implements the accepted mechanisms and exact qualified
   profiles, not the finished Level-1 authoring surface or arbitrary external laws.
3. **Does it leave room for independent, combined, heterogeneous and multi-destination work?**
   Yes. No accepted lifecycle or direct/buffered boundary obstructs those mechanisms.
4. **Does it materially obstruct extraction?** No. Extraction is complete; consolidation remains
   substantial but architectural ownership and dependency direction are sound.
5. **May LW-4C open?** Yes. This is not an API freeze and does not authorize LW-5 or G6.

## Gate disposition

LW-R2B passes on the exact manifest. LW-4B is complete and LW-4C may begin. LW-5 and G6 remain
closed until LW-4C and LW-R2 independently pass.
