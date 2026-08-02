# Symbolic Potts V1 lifecycle language — G5-L0 rereview

Status: complete fresh-context read-only specification rereview

Review boundary: repaired G5-L lifecycle-language contract only

Verdict: **Clear**

## 1. Verdict

G5-L0 clears. The final working-tree authority contains no remaining P0 or P1 contradiction and no
localized P2/P3 defect requiring disposition before G5-L1. The accepted five-effect structural
algebra, two-domain event surface, pure-policy extension ABI, common-snapshot transaction law,
identity/generation rules, failure translation, checkpoint scope, backend contract, and semantic
ownership boundaries are mutually consistent.

This is specification clearance only. It establishes that G5-L1 is bounded and implementable; it
does not claim that lifecycle production execution, GPU qualification, or the G5-L exit matrix has
already been implemented or passed.

## 2. Review basis

The rereview read every required input completely and treated the candidate, amendment, and first
review as hypotheses until checked against the accepted owner decisions and governing specifications.
It also inspected the complete final working-tree diff, including the amendments to:

- `spec/symbolic-potts-v1-compiler-construction.md`;
- `spec/state-model.md`;
- `spec/lifecycle.md`;
- `spec/randomness-and-reproducibility.md`; and
- decisions 0004, 0006, and 0019.

The decisive authority is CCV1-027 together with the compatible generic compiler invariants in
CCV1-001, CCV1-003, CCV1-006--013, CCV1-017--024, the repaired scientific specifications, and
LCI-R1-01 through LCI-R5-07. The final diff passes `git diff --check`.

## 3. Disposition of every first-review finding

| Prior finding | Disposition | Independent verification |
|---|---|---|
| P0-01 — `RetireAtZero` versus `ForbidExtinction` | **Cleared** | CCV1-027, `state-model.md`, `lifecycle.md`, and Decision 0004 now agree: `ForbidExtinction` prevents ordinary final-site loss and makes an impossible zero-occupancy identity a nonfilterable invariant failure; only a due synthesized `RetireAtZero` transaction may consume the bounded pre-publication zero; no active zero-volume identity is publishable. Generation advances on later allocation, not retirement. |
| P1-01 — unaccepted `sites(lattice)` domain | **Cleared** | The authoritative event inventory is exactly finite `cells(kind)` and singleton `model()`. Site expressions occur only inside bounded placement. CCV1-027 explicitly excludes a site-iterated lifecycle event domain. |
| P1-02 — incomplete pure lifecycle-policy ABI | **Cleared** | CCV1-027 now gives a literal role-by-role context/result ABI for trigger, placement, binary partition, and state transform; requires type/shape/units, purity, totality, finite reads/footprints/emission/workspace, relations/trackers, RNG identity, capabilities, concrete callable, serialization, validators, provenance, and inspection; and routes every role through CCV1-009's sole frozen evaluator path. Public external placement and partition slots are explicit, while trigger and state-transform operations occupy existing expression slots. |
| P1-03 — callable freeze versus Julia method tables | **Cleared** | Completion freezes registry membership, schema versions, and callable selection and forbids later live-registry consultation. The contract makes no method-table immutability claim: Julia/package/dependency/compiler environment identity governs executable compatibility, recompilation, and requalification. |
| P1-04 — owner authority for `on_inadmissible` | **Cleared** | LCI-R5-02 and CCV1-027 require every structural effect to contain an explicit `FilterInadmissible()` or `ErrorOnInadmissible()` value; omission fails construction. Synthesized `RetireAtZero` carries a frozen `ErrorOnInadmissible()` value. |
| P2-01 — mandatory exact file tree | **Cleared** | CCV1-027 makes compiler-stage and runtime responsibilities normative while leaving private filenames, directory layout, and concrete view/type names non-normative. Mechanism-named modules and a central catch-all executor remain prohibited. |
| P2-02 — incomplete public failure mapping | **Cleared** | The closed mapping now covers filtered inadmissibility, phase-failing `ErrorOnInadmissible`, static construction/admission failures, runtime conflict, both capacities, stale generation, generation exhaustion, evaluator failure, bound/footprint failure, invariant failure, and host-observed backend failure. Device `LifecycleInadmissibilityFailure` closes the previously omitted phase-failing path. Translation occurs once at the phase boundary without host reinterpretation of device science. |
| P2-03 — relationship override representation | **Cleared** | State and relationship overrides normalize to canonical tuples before completion. Any scalar convenience must normalize before frozen source and fingerprinting; missing reachable relationship behavior fails construction. |

All eight dispositions are consistent across the amended authorities, rather than being supported
only by candidate prose.

## 4. New findings

None. There are no P0, P1, P2, or P3 findings in the final reviewed tree.

Because there are no blockers, governing-clause/counterexample/violated-invariant/repair-checkpoint
records are not applicable.

## 5. Literal accepted V1 event/effect/policy inventory audit

| Category | Exact accepted V1 inventory | Audit result |
|---|---|---|
| Cell-lifecycle event domains | `cells(kind)`; singleton `model()` | Closed and finite. Relationship domains remain under their existing contract. No `sites(lattice)` domain. |
| Structural effects | `CreateCell` (0 -> 1), `RemoveCell` (1 -> 0 with ownership transfer), `Retire` (empty 1 -> 0), `Transition` (1 -> 1), `Divide` (1 -> 2) | Literally closed. All five lower to one cell-structure transaction IR. Fusion, fragmentation, arbitrary M-to-N rewriting, recursive emission, and structural registration are excluded. |
| Built-in creation placement | `SeedAt(site_expression)`; `SeedStencil(site_expression, finite_offsets; relation)` | Complete built-in list. One typed external placement value may occupy the same `placement` field only through the pure ABI. |
| Built-in binary partition | `RandomPlane`; `PrincipalAxisPlane(:major)`; `PrincipalAxisPlane(:minor)`; `SpecifiedNormalPlane` | Complete built-in list. One typed external binary-partition value may occupy the same `geometry` field only through the pure ABI. Every partition remains binary, conservative, nonempty, and connected under the explicit relation. |
| Division side identity | `CanonicalSide()`; `StableRandomSide(draw_identity)` | Closed and explicit; no directional default hidden in CorePotts. |
| Division descendant kind | `PreserveKind()`; `SetKind(kind)` independently for parent and daughter | Closed built-in mapping. Omission realizes concrete frozen `PreserveKind()` values before completion. |
| Creation state | `InitializeFrom`; `Unsupported` | Complete built-in family. |
| Removal/retirement state | `RetireTo`; `Unsupported` | Complete built-in family. |
| Transition state | `Preserve`; `ResetTo`; `Transform`; `Unsupported` | Complete built-in family. |
| Division state | `CopyToDaughters`; `PreserveParentResetDaughter`; `ResetBoth`; `SplitConservatively`; `TransformDaughters`; `RedrawDaughters`; `Unsupported` | Complete built-in family, with explicit conservation/rounding and draw identities where applicable. |
| Site ownership-change state | `PreserveOnOwnershipChange()`; `ClearOnOwnershipChange()` | Exact existing policies are named; missing reachable behavior fails construction. Fields are not rewritten by ownership change. |
| Extinction | `RetireAtZero`; `ForbidExtinction` | Exactly one is required for every finite kind; neither is legal for medium. |
| Relationship consequences | Creation: no incident relationships. Removal/retirement: `RejectWhileLinked`, `RemoveIncident`. Transition: `PreserveCompatible`, `RemoveIncompatible`, `RejectIncompatible`. Division: `RejectWhileLinked`, `RemoveIncident`. | Closed V1 consequence families; daughter transfer is deferred. Overrides are canonical tuples. |
| Phase conflict | `RejectLifecycleAmbiguity`; `StableLifecyclePriority` | Closed built-in phase policy; unique greatest signed-`Int32` semantic priority wins, and equal greatest priority fails. |
| Local inadmissibility | `FilterInadmissible`; `ErrorOnInadmissible` | Closed, mandatory per effect, and distinct from nonfilterable integrity failure. |
| Pure extension roles | registered trigger, placement, binary partition, state transform | Open only through the versioned frozen operation ABI. No role can emit or register a structural verb, mutate state, allocate identity, commit ownership, consult a live registry, or install an executor callback. |

The existing integer-MCS schedule protocol remains authoritative: MCS zero is initialization, and
V1-L adds neither a sub-MCS clock nor host lifecycle actions.

## 6. One-path evaluator audit

There is one contractual route for every admitted symbolic lifecycle expression and registered pure
policy:

```text
LifecycleProcess / typed policy value
    -> qualified frozen source and binding identities
    -> minimal reachable versioned schema/callable closure
    -> CCV1-003 analyzed facts and compiler proof
    -> CCV1-009 concrete operation_callable/static evaluator
    -> compiler-owned lifecycle descriptor groups
    -> one immutable LifecycleExecutionPlan
    -> shared sequential/checkerboard transaction machinery
```

The route is unbypassable for the following reasons:

- CCV1-006 forbids an alternate lifecycle trigger/policy evaluator and requires external roles to
  enter CCV1-009's frozen operation-schema/callable route.
- The ABI fixes role-specific immutable contexts and concrete results. Whole-partition validation is
  part of the same resolved plan, not a second evaluator or trusted extension callback.
- Qualified identities precede analysis. Compiler analysis, not extension labels, derives and
  validates types, units, totality, reads, exact finite footprints, emissions, conflicts, trackers,
  workspace, RNG identities, and backend capability.
- Completion freezes only the minimal reachable schema/callable closure and never consults the live
  registry afterward. Executable-environment identity handles later Julia method changes honestly.
- Request-local placement/partition inadmissibility and exact footprints are resolved before
  biological conflict selection, while allocation-dependent initialization occurs only for surviving
  winners. An invalid high-priority request therefore cannot filter out after suppressing a valid
  competitor.

## 7. CorePotts mechanism-neutrality audit

The contract preserves a mechanism-neutral CorePotts boundary.

- CorePotts owns only the closed structural transaction primitives, generic request/footprint,
  conflict, allocation, capacity, staging, publication, adaptation, and checkpoint machinery.
- PottsToolkit or a downstream module owns scientific trigger and policy callables.
- The five verbs are structural identity/ownership arities, not named biological mechanisms.
- Named mechanisms, mechanism enums/tags/switches, biological `isa` ladders, callbacks, descriptor
  unions, and model-identity specialization remain forbidden by CCV1-006 and CCV1-027.
- The neutral downstream fixture must add trigger, placement, partition, and state-transform
  behavior and pass CPU, GPU, inference, adaptation, checkpoint, replay, inspection, and diagnostics
  without edits to CorePotts programs, engines, lifecycle executor, checkpoint machinery, effect
  switch, descriptor union, or mechanism branch.

The contract therefore admits new pure scientific computation while keeping structural mutation
closed and executor semantics generic.

## 8. Architecture-question disposition

| Question | Result | Basis |
|---|---|---|
| 1. Exactly one production evaluator route? | **Yes** | CCV1-006/009/027 require the sole frozen operation-callable/static-evaluator route and compiler-owned lifecycle descriptors. |
| 2. Closed structural algebra with real pure extension? | **Yes** | Five structural verbs are closed; four typed pure roles have explicit public slots/contexts/results and a zero-Core-edit conformance fixture. |
| 3. Novel extensions use the same machinery without CorePotts executor edits? | **Yes, contractually; evidence is due at G5-L4.** | The ABI, shared plan, backend-neutral harness, adaptation/checkpoint rules, and external fixture impose equal lowering and qualification. |
| 4. Qualified identity and compiler-proven facts? | **Yes** | CCV1-001/003/027 resolve identities first and reject trusted assertions as substitutes for proof. |
| 5. Minimal closure immune to registry redirection without false method-table claims? | **Yes** | Only reachable schemas/callables freeze; no live lookup occurs; executable environment identity governs code changes. |
| 6. Identity/generation/conflict/capacity/RNG/checkpoint/publication laws complete? | **Yes** | Slot states, generation-one/reuse, no same-MCS reuse, canonical conflict/allocation, batch capacity failure, semantic RNG, settled checkpoints, and staged publication agree across authorities. |
| 7. Deterministic failure source, representation, and translation? | **Yes** | The closed host/device map includes both inadmissibility dispositions and every declared integrity/capacity/backend class; canonical semantic offender selection and single host translation are required. |
| 8. Ownership boundaries prevent hardcoding/monolith/duplicate evaluators without freezing files? | **Yes** | Responsibility boundaries are normative; private files/types are not. Mechanism branches, catch-all executors, and alternate evaluators are prohibited. |
| 9. Bounded for G5-L1--L5 without hidden G6/proof-model work? | **Yes** | The six lifecycle checkpoints, exit evidence, stop-before-G6 rule, and explicit non-goals are finite and scoped. |
| 10. Rigorous but DRY tests? | **Yes** | Exact isolated policy tests and targeted interactions share fixtures; expensive compiler/GPU/performance qualification stays in the explicit qualification profile. |

## 9. G5-L1 implementation readiness

The specification is ready for **G5-L1 only**: public syntax and exact policy values, qualified
binding, canonical tuple normalization, minimal frozen closure, lifecycle ABI facts, analysis,
negative diagnostics, status/inspection metadata, and compiler verifiers are now sufficiently
specified to implement without choosing new scientific semantics.

G5-L1 must leave runtime execution unchanged until those compiler facts pass. This rereview does
not certify or authorize G5-L2 transaction execution, G5-L3 checkerboard execution, G5-L4 GPU
qualification, G5-L5/R2 handoff, or any production result beyond the separately controlled gate
process.

## 10. Clearance boundary

This `Clear` verdict clears G5-L0 only. It does **not** authorize R2, G6, proof-model migration,
Wortel/Merks/focal reconstruction, broader lifecycle vocabulary, a second evaluator, or a new
evidence system.
