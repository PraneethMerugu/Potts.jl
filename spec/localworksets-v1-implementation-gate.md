# LocalWorksets V1 Implementation and Review Gate

Date: 2026-08-09

Status: Accepted; LW-0 and LW-R0 passed, LW-1 not begun, G6 remains closed

Authority: [LocalWorksets V1 Normative Contract](localworksets-v1.md)

## Purpose

This gate converts the accepted LocalWorksets architecture into the smallest internal-first
implementation while preserving CorePotts behavior and direct performance. It does not reopen
architecture or public language and does not authorize a broad rewrite or standalone package
release before parity.

The mandatory order is:

```text
LW-0 corrected CorePotts baseline -> LW-R0
  -> LW-1 smallest internal LocalWorksets slice
  -> LW-2 migrate one checkerboard stage sequence
  -> LW-3 direct-parity qualification -> LW-R1
  -> LW-4 bounded expansion decision
```

No later gate may begin early. G6 remains closed until this route, its reviews, and explicit owner
send-off clear.

## Frozen evidence boundary

The final architecture decision is **pass**. The corrected disposable reconciliation witnesses
established:

- separate active-item selection and eager output-lane masking on CPU and real Metal;
- exact static binding plus explicit submission-bound storage slots;
- exact-name/type/bounds/backend/device/shape/layout/alias validation before launch;
- direct launch plus lease/event allocation parity: CPU 208/208 bytes and Metal 2,736/2,736 bytes,
  with zero device workspace growth;
- lease retention after dropped prepared/event references and owner-task exit;
- changed SciML `x`/`y` identities with one plan, one preparation, unchanged two-entry Metal compiler
  cache, and an actual Krylov CG relative error of `6.38e-7`; and
- the failure, topology, determinism, scale, and capability qualifications recorded by the final
  capability-preservation report.

These research witnesses are not production conformance. Each implementation gate must produce
repository-owned exact-candidate evidence.

## LW-0 — Corrected CorePotts baseline

No LocalWorksets implementation begins until CP-B1 through CP-B3 are resolved and the corrected
baseline is frozen.

The normative planning/preparation spelling used by every later gate is:

```julia
workplan = plan(work, topology; backend)
prepared = prepare(workplan, storage; workspace)
```

`WorkPlan` owns topology identity, epoch, bounds, and backend-qualified lowering. `PreparedWork`
fixes concrete storage, workspace, device/context, and one execution lane without redefining that
topology. No competing `prepare(work, backend; ...)` public spelling is admitted by this gate.

### CP-B1 — Checkerboard color order

Reconcile the specified randomized checkerboard color order with the current deterministic
`1:color_count` executor. The accepted resolution MUST name the scientific algorithm, RNG address,
checkpoint effect, CPU/Metal behavior, and compatibility disposition. Silent mismatch is forbidden.

### CP-B2 — Attempt budgets

Reject unsupported non-unit attempts-per-site values under current algorithm identities, or define
and qualify a new algorithm whose normalization, kinetics, RNG address, and capability identity
cover them. A parameter MUST NOT silently change algorithm meaning.

### CP-B3 — RNG provenance

Add the explicit RNG contract/version and lowering identity to capability and checkpoint identity.
Restore or continuation under a mismatched identity MUST fail closed.

### LW-0 evidence

- full CorePotts CPU and qualified Metal suites;
- sequential/checkerboard scientific comparison;
- exact checkpoint continuation and mismatch rejection;
- randomized-color or accepted replacement trajectory evidence;
- attempt-budget rejection or newly named algorithm evidence;
- allocation, launch, throughput, and capability-environment baseline; and
- clean statement of submitted/drained/committed/materialized and failure behavior.

### Preserved CorePotts boundaries

The corrected checkerboard baseline retains the existing asynchronous contract: it adds no
intermediate waits; multiple MCSs remain queueable on one lane; color-order generation uses
preallocated host storage; every launch receives an immutable scalar color argument; and
arbitration, publication, settlement, and commit remain CorePotts-owned.

Hamiltonian authoring is also frozen. `HamiltonianTerm`, `Volume`, `ContactEnergy`, `Elongation`,
and registered external Hamiltonians retain their public surface. `complete` and `mtkcompile`
continue proving purity, domains, and bounded affected anchors. Proposal before/after views remain
CorePotts-owned, and canonical source-order Hamiltonian folding may not become an unordered
LocalWorksets reduction. Any later LocalWorksets vertical sits beneath compiled descriptor
evaluation and is invisible to Hamiltonian authors.

### LW-R0 review

An independent preservation reviewer MUST confirm CP-B1–CP-B3 closure on the exact candidate and
freeze the direct implementation baseline used by LW-3. P0/P1 findings block entry to LW-1.

Recorded outcome: the fresh independent read-only review passed the exact LW-0 candidate with
P0=0, P1=0, P2=0, P3=0, and no substantive dissent. The frozen evidence is recorded in
[LW-0 corrected CorePotts baseline](../design/hardening/lw0-corrected-corepotts-baseline.md).
LW-1 is eligible to begin but has not begun.

## LW-1 — Smallest internal-first slice

Implement LocalWorksets internally to CorePotts first. Do not create a standalone package, public
dependency, domain framework, or second engine yet.

The slice is limited to:

- `LocalWork`, optional `WorkPlan`, `PreparedWork`, and `WorkEvent`;
- `localwork`, `plan`, `prepare`, `run!`, `sequence`, and `wait`;
- the single public lifecycle `plan(work, topology; backend)` then
  `prepare(workplan, storage; workspace)`;
- the one output mechanism needed by the selected checkerboard sequence;
- static storage, named value slots, and only the submission storage slots required by conformance;
- active-item selection distinct from eager output-lane masking;
- one bound lane using KernelAbstractions implicit ordering;
- prebound workspace, submission leases, poison state, and inspection; and
- central validation/lowering with no external opaque execution hook.

Every unused generality remains unimplemented. Domain semantics stay in CorePotts.

## LW-2 — One checkerboard stage sequence

Migrate exactly one existing CorePotts checkerboard stage sequence. Preserve its current
evaluate/accept-before-arbitration order and Core-owned RNG, acceptance, claims, trackers,
double-buffer publication, sticky failure, checkpoint, and commit semantics.

The vertical MUST exercise:

- dynamic named bindings for MCS, RNG address, bank, count/ordinal, and status epoch;
- at least ten queued MCSs before one settlement;
- deterministic early failure with later work already encoded;
- active/destination banks and failure-atomic Core publication;
- same-lane shared-workspace reuse;
- CPU and real Metal; and
- every rejection currently enforced by CorePotts capability admission.

Do not migrate another stage until LW-3 and LW-R1 pass.

## LW-3 — Direct-parity qualification

Compare the extracted vertical against the frozen LW-0 direct implementation on the exact same
scientific inputs, environment, backend, and measurement method.

Required parity rows are:

| Dimension | Required result |
|---|---|
| scientific state and trackers | exact where the baseline promises exactness |
| RNG/checkpoint continuation | identical accepted trajectory and identity |
| queued failure/publication | same sticky status and logical commit cut |
| launch sequence/count | identical or an explicitly reviewed provider event/validation delta |
| device workspace | no growth during warm `run!`; exact inspected formula |
| host allocation | direct-launch-plus-equivalent-lease/event parity |
| compilation | no new specialization for same schema/types/bounds |
| throughput | statistically indistinguishable, or a bounded explained regression accepted by owner |
| capability/rejections | no promoted backend, type, operation, address space, or scientific claim |

Invalid binding, stale topology, alias, cross-device, wrong-lane, poison, abandoned-event,
active-selection, eager-output-mask, and external-mutation-contract cases MUST be executable tests.

### LW-R1 review

A fresh reviewer evaluates the exact LW-0 baseline and LW-3 candidate. The review MUST preserve
substantive performance, determinism, lifecycle, and scientific dissent. P0/P1 findings block LW-4;
P2 findings require an explicit disposition before expansion.

## LW-4 — Bounded expansion decision

After LW-R1, the owner may authorize only one of:

1. continue internal-first with the next smallest CorePotts mechanism;
2. extract a standalone LocalWorksets package after package-boundary tests prove independence;
3. defer extraction while retaining the internal slice; or
4. reject the implementation and restore the frozen direct path.

Expansion to LBM, lattice-spring, FEM, graph, particle, or cellular-automata conformance requires
separate implementation evidence but not renewed architecture or naming research.

## Scope vetoes

This phase MUST NOT add distributed memory, multi-GPU scheduling, cancellation, a general AD
framework, a solver/runtime, domain physics, a mutable global ownership registry, mandatory
SciMLOperators/MTK dependencies, or broad CorePotts migration before parity.

## Exit and closure

The architecture and API-language audit program is closed. This gate is complete only when LW-R1
passes and the owner records an LW-4 disposition. Until then, LocalWorksets is accepted architecture,
not a qualified production capability.
