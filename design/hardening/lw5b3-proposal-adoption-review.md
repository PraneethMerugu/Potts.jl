# LW-5B3 proposal-only adoption review

Date: 2026-08-13

Status: **PASS after bounded remediation**. The original candidate failed the
frozen CPU performance gate; that failure is preserved below. The corrected
candidate passes exact CPU and qualified real-Metal semantics, lifetime and
the unchanged CPU/Metal noninferiority protocol. The candidate remains
private, experimental and non-promoted. The fresh
[B3 remediation review](lw5b3-proposal-adoption-remediation-review.md) clears
the performance block and opens `K02` as the non-promoted B4 second-use
witness. Production/default adoption, later operation-family migration,
LW-R3 and G6 remain closed.

## Bounded question and ruling

B3 changed exactly one checkerboard stage: compiled proposal evaluation. Both
arms retained the same direct CorePotts claim, accepted-copy, lifecycle,
publication, RNG, clock, checkpoint and settlement semantics. This avoids
mistaking a composite proposal-plus-claim migration for one-for-one evidence.

The original candidate was scientifically exact and its lifetime model was
sound, but it did not satisfy the predeclared CPU noninferiority requirement.
The bounded remediation did not weaken that threshold or change
LocalWorksets admission. It corrected a quadratic CorePotts adapter bridge,
then reran the exact protocol. B3 now passes only on the corrected evidence
and fresh review recorded below.

## Corrected remediation-file identity

The remediation review binds the following exact remediated source, test and
executable-evidence files:

```text
a84a877ec8b279fb2e4050bda596858b82495a7dd4a5896e2906315f77545a90  lib/CorePotts/src/execution/descriptor_plan.jl
554d73a622e35f52595d61f7edfcab9b457a4fb8260bae76590338f0c4205b32  lib/CorePotts/src/execution/localworksets_proposal_bridge.jl
70b7ff342396057b3f6c72d32cb6b7dc19de193c7a7f5f6a693a1c69f0753215  lib/CorePotts/test/test_program_v1_localworksets_vertical.jl
a6707aceafcc6a8612754ac60ca4635c85be7bc679c0c05609654374765e5570  benchmark/src/lw5b3_proposal_parity.jl
d9dce8c1db1d08568d97d687b916c2941171ac049bcdde3a7052ea66e56c4355  benchmark/backends/metal/lw5b3_probe.jl
541b8ac1dcccfe51dbd690c9c11c3e7fc2f85eea3df833a7f76996c410089dd0  benchmark/backends/metal/lw5b3_proposal_parity.jl
```

The worktree contains the preserved in-progress LW-5 candidate. These six
digests bind the bounded remediation delta and its executable evidence; they
do not claim to seal the entire dirty dependency product or replace a future
committed decisive-review manifest.

## Bounded performance remediation

The failure did **not** come primarily from LocalWorksets validation,
lifetime or KernelAbstractions submission. The CorePotts immutable proposal
bridge evaluated every canonical source by scanning every descriptor group
and instance. With `N` sources and `D` descriptors, this was `O(N*D)`, while
the frozen direct evaluator visits each descriptor once and folds once.

The correction derives a canonical source schedule from the compiler-owned
host descriptor plan during preparation. The private operation type carries
that schedule and its generated device body performs one constant-index
descriptor evaluation per populated source, folding in canonical source
order. Host preparation rejects out-of-range handles, duplicate sources,
missing coverage, invalid locations and duplicate scheduled locations.
Backend adaptation preserves group/instance layout. The compiled Metal
operation contains no host iteration, dynamically reachable host-only
failure path, scalar host fallback or vendor branch; its descriptor-type
assertion is statically discharged for compiler-owned concrete vectors.

The former immutable tuple path remains a test oracle. Hamiltonian authoring,
compiled descriptors, before/after proposal views, canonical floating-point
fold order, acceptance, semantic RNG addressing, claims, settlement,
checkpoints and LocalWorksets itself are unchanged. The correction adds no
launch, wait, output, workspace or execution family.

Diagnostic decomposition before implementation measured the repeated-search
bridge at approximately 5.59 microseconds per actionable scalar proposal
versus 2.66 microseconds for the caller-owned linear evaluator/fold. The
LocalWorksets wrapper and validation layers were only a few microseconds per
submission and could not explain the approximately 120-microsecond evaluator
kernel deficit. Those diagnostics locate the defect; only the frozen paired
results below are admission evidence.

## Same-scope lifetime amendment

Proposal evaluation alternates between two checkerboard state banks. Each
bank needs a statically bound `PreparedWork` so every kernel carries only the
active scientific view. The two preparations share the same
KernelAbstractions backend/owner-task synchronization scope but retain
separate lease ledgers.

LocalWorksets now provides the bounded additive operation
`waitall(events...)`:

- every event must belong to the current owner task and the same exact
  centrally admitted provider synchronization scope;
- each participating preparation snapshots its cumulative submitted tail;
- exactly one provider wait is performed;
- all participating tails are released only after successful completion;
- a failed wait poisons every active participating preparation and releases
  none of them; and
- already drained events are idempotent.

This is grouped settlement, not a scheduler. It creates no native queue,
stream, command buffer, dependency graph, transferable event or selective
completion claim. KernelAbstractions continues to own launch execution,
implicit ordering and the final portable `synchronize(backend)`.

The complete LocalWorksets CPU package suite passed. Real-Metal injected
failure evidence observed one `KernelException`, one synchronization, both
participating preparations poisoned and drained counts `(0, 0)`.

## Candidate shape

The private candidate prepares two type-identical, bank-local proposal phases:

- one `independent(...; coverage=:partial)` `UInt8` disposition port;
- one destination per active proposal;
- one LocalWorksets launch replacing the direct proposal-evaluation launch;
- immutable submission scalars `color`, `active_count` and destination-state
  `mcs`;
- no algorithmic workspace;
- direct CorePotts claim machinery in both arms; and
- one final `waitall` when both banks have submitted work, with no
  intermediate host wait.

CorePotts retains the proposal views, canonical source-order descriptor fold,
Hamiltonian authoring, acceptance, semantic RNG address, failure mapping,
bank transaction, commit cut and checkpoint mechanism identity.

## Corrections exposed by B3

B3 found and corrected three bounded implementation defects:

1. The initial proposal view captured its preparation-time MCS. A concrete
   per-submission overlay now supplies the immutable destination-state MCS to
   the existing semantic RNG address without reconstructing the full runtime
   view per item.
2. The initial bank selector compared the shared status array, which cannot
   distinguish checkerboard banks. It now uses exact ownership-array identity.
3. The first lease-capacity guard called full `inspect` on every MCS. Checked
   arithmetic over CorePotts' submitted/drained execution position and the
   predeclared per-bank capacity now performs the same prelaunch rejection.
   Inspection remains an evidence boundary rather than a hot-path counter.

These corrections preserve fail-closed admission and do not alter public
Hamiltonian or PottsToolkit authoring.

## Functional evidence

CPU evidence on the exact candidate includes:

- 84/84 B3 queued-execution, capability, checkpoint, continuation, RNG and
  direct-parity assertions;
- 7/7 whole-MCS lease-exhaustion assertions;
- 24/24 expected nonfinite-science failure and direct commit-cut assertions;
- 12 queued MCSs and 24 proposal submissions split evenly over both banks;
- one final provider synchronization, one LocalWorksets wait ledger entry in
  total and no intermediate wait; and
- the complete CorePotts package suite, including package-quality and fresh
  method-world attack tests.

Qualified real-Metal evidence reports:

```text
queued_mcs = 12
proposal_submissions = 24
proposal_launches_per_color = 1
waits = 1
scope_synchronizations = 1
algorithmic_workspace_bytes = 0
topology_transfer_bytes = 144
exact_receipt_parity = true
exact_rng_trajectory = true
expected_failure_parity = true
direct_claims_in_both_arms = true
intermediate_waits = 0
production_promoted = false
```

Metal functional success does not qualify CUDA/ROCm and does not override the
CPU performance gate.

## Original frozen performance failure

The authoritative CPU comparison retains the frozen 128×128 scientific
fixture, ten MCSs per batch, ten warm batches, 50 paired measured batches,
fixed randomized arm order, 10,000 paired bootstrap samples and seed, and the
`upper95 <= 1.05` admission rule.

The original candidate reported:

```text
direct median seconds            = 0.0259088125
candidate median seconds         = 0.028076521
median ratio                     = 1.0836668411568458
paired bootstrap upper 95%       = 1.0884425090195275
required upper 95%              <= 1.05
direct median allocated bytes    = 1,318,176
candidate median allocated bytes = 1,384,256
direct median allocations        = 10,227
candidate median allocations     = 10,630
```

The result was above the threshold, so that benchmark correctly failed. The
threshold and protocol were retained unchanged for remediation.

## Corrected frozen performance result

The final CPU rerun used the same 128x128 scientific fixture, registered
external Hamiltonian, ten MCSs per batch, ten warm batches, 50 randomized
paired measured batches, 10,000 paired bootstrap samples and seed, and
`upper95 <= 1.05` rule:

```text
direct median seconds            = 0.025743395500000002
candidate median seconds         = 0.025570416999999998
median ratio                     = 0.9932806649379253
paired bootstrap upper 95%       = 0.9970121927685043
required upper 95%              <= 1.05
direct median allocated bytes    = 1,318,176
candidate median allocated bytes = 1,384,256
direct median allocations        = 10,227
candidate median allocations     = 10,630
```

The exact real-Metal rerun used the same 50-pair/10,000-bootstrap protocol:

```text
direct median seconds            = 0.1246965835
candidate median seconds         = 0.124653292
median ratio                     = 0.999652825291721
paired bootstrap upper 95%       = 1.0052519529521557
required upper 95%              <= 1.05
direct median allocated bytes    = 17,679,040
candidate median allocated bytes = 17,860,768
direct median allocations        = 261,539
candidate median allocations     = 262,281
```

Both exact final runs pass with margin. Allocations remain higher in the
candidate and are retained as measured debt; they are not hidden or used to
change the threshold. Compile-footprint diagnostics over 5, 15 and 30 source
schedules produced one typed method per case and approximately linear native
text growth, with no evidence justifying an arbitrary source-count limit.

Final qualification also includes the complete CorePotts CPU package suite,
the focused real-Metal 12-queued-MCS witness, exact receipt/RNG trajectory,
expected-failure parity, one proposal launch per color, zero intermediate
waits, one final synchronization and zero algorithmic workspace.

## Disposition

- LocalWorksets `waitall`: **accepted as a bounded, backend-neutral lifetime
  capability**, subject to the normative same-scope restrictions and retained
  CPU/Metal tests.
- B3 corrected candidate: **PASS; retained as private experimental evidence**.
- B3 performance block: **cleared by the fresh exact-hash remediation review**.
- Direct proposal and claim execution: **remain authoritative and selected**.
- `K02`: **open only as the non-promoted B4 adapter-reuse witness**.
- Production/default promotion and later-family migration: **not started**.
- LW-R3 and G6: **closed**.

The next permissible work is `K02`: candidate generation constructed and
compiled through the same CorePotts adapter as a non-promoted second-use
witness. It may not add LocalWorksets functionality, replace production
candidate generation, duplicate the proposal execution-view framework or
skip the decisive pilot consolidation review.
