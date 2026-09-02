# LW-5B3 bounded performance-remediation review

Date: 2026-08-13

Status: **PASS**. The focused fresh review clears the B3 performance block
and opens `K02` only as the non-promoted LW-5B4 second-use witness.
Production/default promotion, later-family migration, LW-R3 and G6 remain
closed.

## Scope

This focused review asks only whether the exact corrected B3 candidate:

1. preserves the already-qualified proposal-only scientific and lifetime
   boundary;
2. corrects the frozen performance failure without weakening admission,
   changing LocalWorksets or adding an execution family;
3. honestly passes the unchanged CPU and qualified real-Metal evidence; and
4. may open `K02` as the non-promoted B4 second-use witness.

It does not authorize production/default promotion, migration of a later
operation family, LW-R3 or G6.

## Exact candidate and evidence

The exact file hashes, original failed result, corrected CPU/Metal results,
functional qualification and cause analysis are recorded in the
[B3 evidence record](lw5b3-proposal-adoption-review.md). Reviewers must
reproduce those digests before balloting.

The remediation is limited to the CorePotts descriptor-to-LocalWorksets
bridge and its tests. LocalWorksets execution, admission, synchronization,
leases, output algebra and public API are unchanged.

## Independent ballots

| Reviewer | Scientific preservation | JuliaGPU/performance | Consolidation/scope | Findings | Ballot |
|:--|:--|:--|:--|:--|:--|
| Scientific semantics, RNG and checkpoint reviewer | PASS | nonvoting | PASS | P0=0, P1=0, P2=0 | **PASS** |
| JuliaGPU, KernelAbstractions and performance reviewer | PASS | PASS | PASS | P0=0, P1=0, P2=1 | **PASS** |
| CorePotts adapter consolidation and red-team reviewer | PASS | PASS | PASS | P0=0, P1=0, P2=3 | **PASS** |

All three reviewers reproduced the six recorded SHA-256 digests. No reviewer
found changed science, weakened validation, hidden synchronization, host
fallback, vendor-specific execution or a new LocalWorksets mechanism.

## Independent evidence and conclusions

The scientific reviewer confirmed that the corrected schedule evaluates each
compiler-owned descriptor once and folds populated entries in canonical
source order. Both arms retain the same proposal evaluator, Hamiltonian
before/after views, acceptance function and semantic RNG address. External
Hamiltonians retain the registered `StaticEvaluator` route. Direct claims,
state copy, lifecycle, publication, transactions, commit cuts and checkpoint
meaning remain CorePotts-owned. The reviewer reproduced the complete focused
vertical and a fresh 50-pair CPU result with median ratio `0.9923383` and
bootstrap `upper95=0.9997226 <= 1.05`.

The JuliaGPU/performance reviewer confirmed that the host-derived schedule is
validated before adaptation, the generated device operation uses canonical
constant indexing, the descriptor guard is statically discharged, and no
host fallback or vendor branch is introduced. Launch count, final-only
settlement, KernelAbstractions implicit ordering and fail-closed capability
admission remain unchanged. A separate fresh 50-pair CPU reproduction
reported median ratio `0.9937048` and `upper95=1.0020627 <= 1.05` with the
recorded allocation counts.

The red-team reviewer confirmed the original `O(N*D)` descriptor search and
the corrected `O(N+D)` preparation/evaluation shape. The performance defect
was in the CorePotts adapter bridge, not LocalWorksets validation. The fix is
bounded to the private CorePotts descriptor schedule and bridge: it changes no
LocalWorksets validation, output algebra, workspace, launch, wait, public API
or execution family.

The exact qualified real-Metal result remains the hash-bound 50-pair run in
the B3 evidence record: median ratio `0.999652825291721` and
`upper95=1.0052519529521557 <= 1.05`, plus the 12-queued-MCS functional
witness. The fresh reviewers inspected the exact Metal runners and portable
device path, but did not independently duplicate that hardware run in their
review sandboxes. This is an evidence-provenance qualification, not a
performance blocker or a claim of CUDA/ROCm qualification.

## Findings and disposition

The reviewers returned no P0 or P1 findings. Their four P2 findings are
preserved rather than collapsed:

1. The compile-footprint check shows one typed method per schedule and
   approximately linear native-text growth, but is not yet retained as a
   durable automated harness. **Owner:** CorePotts B4 qualification.
   **Disposition:** carry; required before any production promotion, not a B3
   blocker.
2. B3 performance success does not prove downstream consolidation or value.
   `K02` must still demonstrate a materially smaller second use and close the
   composite science-read and adapter-complexity questions. **Owner:** `K02`/
   B4 and the decisive pilot review. **Disposition:** carry; failure returns
   adapter derivability to LW-5A.
3. Active records temporarily declared B3 passed while this review still said
   ballots were pending. **Owner:** this review seal. **Disposition:** closed
   by the atomic roadmap, control-record and README reconciliation after all
   ballots arrived.
4. The six hashes bind the bounded remediation source and executable evidence,
   not the entire dirty product. **Owner:** B3 evidence record.
   **Disposition:** closed by the explicit scope wording; a future committed
   decisive-review manifest must seal the complete product candidate.

The scientific reviewer also noted that its sandbox could not launch the
complete package suite through `Pkg.test` because Aqua was unavailable and
Pkg logging was unwritable; the relevant focused suite passed. The exact
candidate's complete CorePotts CPU suite and qualified real-Metal suite remain
recorded in the B3 evidence record. This review does not convert those runs
into independent reviewer reruns.

## Opening rule

`K02`/B4 opens only if all three reviewers return PASS with P0=0 and P1=0,
the corrected evidence hashes reproduce, and no reviewer finds that the
performance recovery came from weakened validation, changed science, hidden
synchronization, host fallback, vendor-specific execution or a new
LocalWorksets mechanism.

P2 findings require an explicit owner and disposition here. Any P0/P1 keeps
B3 blocked and leaves `K02` closed.

The opening rule is satisfied: all ballots are PASS, all hashes reproduce,
P0=0 and P1=0, and every P2 has an owner and disposition. Therefore:

- the corrected B3 candidate passes as private, non-promoted evidence;
- the B3 performance block is cleared;
- direct production execution remains selected; and
- `K02` opens only as the bounded, non-promoted LW-5B4 adapter-reuse witness.
