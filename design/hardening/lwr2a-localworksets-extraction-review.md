# LW-R2A LocalWorksets Standalone Extraction Review

Date: 2026-08-10

Decision: **PASS, 3-0**

Final severity count: **P0=0, P1=0, P2=0**

Substantive final dissent: none. Substantive interim dissent is preserved below.

## Scope

LW-R2A reviews only whether the bounded LW-4A candidate was extracted correctly, remains honestly
narrow, preserves CorePotts semantics and fail-closed JuliaGPU execution, and leaves room for the
later general LocalWorksets mechanisms. It does not claim that independent, combined,
heterogeneous or general multi-destination work exists, freeze the eventual authoring API, start
LW-4B, promote the CorePotts candidate, remove the direct oracle or open G6.

The reviewed candidate is identified by
[`lw4a-final-hashes.sha256`](lw4a-final-hashes.sha256). Implementation traceability is in
[`lw4a-extraction-implementation-matrix.md`](lw4a-extraction-implementation-matrix.md), exact
evidence in [`lw4a-extraction-evidence.md`](lw4a-extraction-evidence.md), and command outcomes in
[`lw4a-command-outcomes.md`](lw4a-command-outcomes.md).

## Independent ballots

| Reviewer | Independent focus | P0 | P1 | P2 | Final ballot |
|---|---|---:|---:|---:|---|
| API/package-quality reviewer | public/private boundary, matrix accuracy, declaration closure, package quality, future family room | 0 | 0 | 0 | PASS |
| JuliaGPU/backend reviewer | KA implicit ordering, sole synchronization, shared failure scope, capability authority, source portability, real-Metal evidence | 0 | 0 | 0 | PASS |
| CorePotts preservation/trust reviewer | trusted adapter, scientific ownership, checkpoints, determinism identity, direct oracle and candidate status | 0 | 0 | 0 | PASS |

All three reviewers independently verified the refreshed hash inventory. The API and JuliaGPU
reviewers independently reran the standalone package suite. The downstream and performance suites
were then rerun once more after the final negative-validation guard, so the final evidence belongs
to the exact source hash rather than a neighboring candidate.

## Contradiction and remediation record

The committee did not inherit earlier ballots.

1. Security review first reproduced replaceable central-admission and cached-execution boundaries,
   incorrect preparation-local failure attribution, and interceptable Core public lifecycle calls.
   Package-owned exact method checks/invokes, shared backend/device/owner-task KA failure scope, and
   the Core trusted adapter closed those findings. Hostile and real-Metal witnesses were added.
2. API review then rejected A02, A04, A06 and A07 because the matrix claimed do-block equivalence,
   declaration validation, typed bounds and closed destination profiles that were missing or false.
   The candidate added exact tests and bounded declaration closure without adding an output family.
3. On re-review, the API reviewer retained one P1 because `storage_slot(Any[1]; access=:read)` still
   contradicted A06. The final guard rejects a non-concrete element type before backend/device
   probing, and an executable negative test proves it. Standalone qualification increased from
   354 to 355 assertions.
4. Documentation P2s concerning package inventory, roadmap status, evidence-file provenance and
   line-count provenance were corrected. Lowering/world-validation duplication remains an explicit
   bounded LW-4B consolidation item before a third family; it is not hidden extraction debt or an
   authorization to redesign the lifecycle.

The API reviewer issued two substantive interim rejection ballots. Both are retained as evidence
that the matrix, rather than the implementation, controlled admission. No reviewer weakened a row
or performance bound to obtain the final pass.

## Final evidence

| Lane | Exact result |
|---|---|
| standalone LocalWorksets | 355/355 |
| complete CorePotts CPU | 17,462/17,462 |
| authoritative PottsToolkit root | 2,198/2,198 in 18m35.9s |
| CPU direct/candidate parity | upper95 1.0123282545 <= 1.05; candidate allocation 1,303,296 < 1,318,176 bytes |
| qualified real Metal | extension 2/2; G5H-4 37/37; upper95 1.0052174352 <= 1.05 |
| Metal allocation/cache | candidate 17,149,648 < 17,678,968 bytes; cache 324 -> 324 |
| ordering and failure | no intermediate wait; one cumulative KA synchronize; isolated and shared asynchronous failure/poison witnesses pass |
| Core preservation | exact state, receipts, counters, trackers, checkpoint continuation, cross-lowering rejection and RNG mismatch rejection pass |

The package remains qualified only for CPU and the reviewed Apple M1/Metal environment. Hardware-
neutral KernelAbstractions source is not a CUDA or ROCm support claim.

## Separate gate questions

| Question | Committee result |
|---|---|
| Is this a correct, bounded LW-4A implementation? | PASS |
| Is the implemented surface described honestly? | PASS; it is the lifecycle plus one-key resolved and bounded conjunctive lowerings, not the general library |
| Does it preserve KernelAbstractions implicit ordering and portable failure semantics? | PASS |
| Does it preserve CorePotts scientific, RNG, Hamiltonian, checkpoint and settlement ownership? | PASS |
| Does it leave additive room for independent, combined, heterogeneous and later reviewed multi-destination families? | PASS |
| Does any current choice materially obstruct standalone extraction or the later API reconciliation? | NO |
| Does this review authorize LW-4B implementation automatically? | NO; it makes LW-4B eligible for a separately directed start |

## Gate disposition

LW-R2A is cleared for this exact candidate. LW-4A is complete.

LW-4B may begin only on explicit owner direction and under its existing bounded mechanism matrix.
LW-4C, LW-5 and G6 remain closed. The direct CorePotts implementation remains public/default and
`Supported`; the LocalWorksets checkerboard candidate remains private and `Experimental`, with
replay qualification reported separately.
