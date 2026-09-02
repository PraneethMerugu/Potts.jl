# Symbolic Potts V1 lifecycle language — independent review

Status: complete fresh-context read-only review  
Review boundary: G5-L0 specification clearance  
Verdict: **Blocked**  
Implementation authorization: **none**

## 1. Verdict

The consolidation candidate contains a coherent, bounded five-effect transaction architecture and
faithfully carries most accepted owner decisions. It is not yet one implementable authoritative
contract. One direct accepted-contract contradiction remains unresolved, two public extension
invariants are not specified strongly enough to implement or test, and one new scientific event
domain plus several constructor defaults exceed the owner decisions from which the candidate claims
to derive.

The review therefore finds one P0, four P1, and three P2 issues. G5-L0 does not clear. Production
implementation must not begin. The bounded remedy is to resolve the two owner questions identified
below, repair the candidate, and perform the one authoritative consolidation edit described in the
amendment map. No production implementation, proof-model migration, G6 work, or broadened lifecycle
algebra is authorized by this review.

The positive architectural conclusion is also explicit: after those specification repairs, nothing
in the accepted five-effect algebra, staged scientific-publication atomicity, bounded workspace
model, or functional-Metal requirement is statically infeasible. The current code demonstrates the
necessary generic evaluator, relationship transaction, tracker, adaptation, RNG, and checkpoint
authorities that the lifecycle plan should extend rather than replace.

## 2. Review basis and current-authority static proof

All required documents and all minimum implementation files in the review request were read in
full. Directly relevant operation-normalization and static-evaluator code was additionally inspected
to test the registry-freeze and downstream-policy claims.

The current split authority is concrete:

- `src/statements/semantics.jl:110-120` exposes `Transition`, `Divide`, and `Retire`, but not the
  candidate's complete effect/policy surface.
- `src/compiler/lowering/stage_plan.jl:65-82` lowers only relationship `Remove`/`Retune` from both
  `RelationshipProcess` and `LifecycleProcess`, and `stage_plan.jl:163-182` places them in the
  after-MCS groups.
- `lib/CorePotts/src/execution/sequential_program.jl:208-227` performs an unconditional zero-volume
  scan, increments generation at retirement, and zeroes all cell state; lines 229-232 run that scan
  before the current after-MCS stage.
- `lib/CorePotts/src/program/runtime.jl:3-28` and `254-277` have kinds and generations but no
  never-used/reusable status or high-water fact; the checkpoint cannot distinguish those states.
- `lib/CorePotts/src/rng/semantic.jl:4-17` has neither lifecycle streams nor a cell entity kind, and
  lines 61-63 permit generations only on site addresses.
- `lib/CorePotts/src/execution/checkerboard_program.jl:338-348` explicitly rejects after-MCS and
  accepted-copy stage buffers on device; the current Metal witness in
  `benchmark/backends/metal/runtests.jl:6-44` exercises descriptor, checkerboard, relationship-read,
  and surface paths, not lifecycle mutation.
- `test/backend_conformance/g5_relationship_execution.jl:68-76` itself correctly states that its
  GPU witness qualifies immutable incident reads and not relationship mutation.

Those are expected G5-L1 through G5-L4 implementation gaps, not independent findings against a
pre-implementation candidate. They establish why the candidate must be exact before implementation.

## 3. Accepted-decision traceability audit

| Accepted decision | Candidate location | Audit result |
|---|---|---|
| LCI-R1-01 | 1, 2.2 | Five verbs and excluded fusion/fragmentation are traced. The extra `sites(lattice)` event domain is not part of this decision; see P1-01. |
| LCI-R1-02 | 3 | `LifecycleProcess` remains the sole public lifecycle statement. Traced. |
| LCI-R1-03 | 4, 10 | Open admitted symbolic expressions and addressed RNG are traced. Executable policy-context details remain blocked by P1-02. |
| LCI-R1-04 | 2, 4, 13 | Closed structural verbs/open pure policies are traced. Equal downstream treatment remains blocked by P1-02 and P1-03. |
| LCI-R1-05 | 14, 16, 19 | G5-L before one final R2 and stop before G6 are traced. |
| LCI-R2-01 | 2.5, 2.7 | Schema policy, explicit compatible override, fail closed, and derived-state repair are traced. |
| LCI-R2-02 | 2.2, 2.6 | Separate remove/retire is traced. Kind-specific extinction is directionally traced but conflicts with accepted normative text; see P0-01. |
| LCI-R2-03 | 2.3 | `SeedAt`/finite connected `SeedStencil`, no clipping, and snapshot availability are traced. |
| LCI-R2-04 | 2.4 | Plane normalization, explicit relation, two nonempty connected partitions, and explicit side identity are traced. |
| LCI-R2-05 | 2.5 | All accepted state-policy families, explicit stochastic identities, and no implicit custom-state law are traced. |
| LCI-R2-06 | 2.7 | Closed relationship consequences and deferred daughter transfer are traced. Public tuple spelling needs P2-03. |
| LCI-R3-01 | 5 | Closed phase order, one pre-lifecycle snapshot, no same-boundary retrigger, and a distinct stage are traced. |
| LCI-R3-02 | 2.8, 7.1-7.2 | Duplicate removal, footprint conflicts, default ambiguity rejection, semantic priority, and tie failure are traced. |
| LCI-R3-03 | 2.8, 7.3 | Local inadmissibility, nonfilterable integrity failures, and complete-batch capacity failure are traced. Unaccepted omission defaults are P1-04. |
| LCI-R3-04 | 6 | Slot status/equivalent high-water form, ascending allocation, delayed reuse, and generation-on-creation are traced. |
| LCI-R3-05 | 8 | Complete preflight, staged commit, one publication boundary, and terminal hardware-failure recovery are traced without claiming device rollback. |
| LCI-R3-06 | 10 | Lifecycle stream families, cell ID/generation, destination identities, isolation, and version change on packing failure are traced. |
| LCI-R3-07 | 12 | Settled checkpoints, future-relevant state, reconstructible workspace, trace continuation, and failed-phase exclusion are traced. |
| LCI-R4-01 | 5, 8 | One shared lifecycle plan for sequential/checkerboard CPU and no sequential-GPU claim are traced. |
| LCI-R4-02 | 11 | Full device-resident functional witness and bounded phase-end status transfer are traced. |
| LCI-R4-03 | 13 | The requested neutral downstream trigger/placement/partition/transform fixture is named, but the ABI needed to make it zero-Core-edit is missing; see P1-02. |
| LCI-R4-04 | 12 | Stable host diagnostics, bounded device status, deterministic offender selection, and inspection are traced. Status mapping needs P2-02. |
| LCI-R4-05 | 9 | Zero warm allocation, bounded storage reports, locality, fixed-group growth, and measured rather than absolute timing are traced. |
| LCI-R4-06 | 14.1 | Shared fast/qualification fixtures, isolated policy tests, risk-based interactions, and no evidence bureaucracy are traced. |
| LCI-R4-07 | 14.2, 16, 19 | The nine-part exit evidence, one R2, failure routing, and stop-before-G6 rule are traced. |
| LCI-X-01 | 11, 14 | Every admitted effect/policy family must execute on one real GPU witness. Traced. |
| LCI-X-02 | 1, 19 | Fusion, fragmentation, and general M-to-N rewriting are absent. Traced. |

Traceability is therefore complete at the identifier level, but not yet semantically closed because
the findings below affect R1-01, R1-04, R2-02, R3-03, and R4-03/R4-04.

## 4. Disposition of the seven consolidator-derived clarifications

1. **Singleton `model()` domain — Essential clarification.** The accepted lifecycle specification
   already says there is one global model target. A qualified singleton anchor makes global
   creation finite and compositional. The amendment must say whether the singleton is the root
   completed model identity and how a nested source qualifies references to it; it must not imply
   one singleton per child system.

2. **`RetireAtZero()` versus `ForbidExtinction()` kind law — Essential clarification.** The owner
   accepted synthesis only for kinds that permit stochastic extinction. A closed, explicit law is
   needed to keep that phrase from becoming a hidden executor decision. The clarification cannot be
   authoritative until the contradictory unconditional-retirement clauses receive the explicit
   supersession in P0-01.

3. **Exactly one structural cell effect per process — Essential clarification.** The accepted
   conflict law permits a combined outcome only as one admitted effect with a proven internal law,
   and general effect composition is deferred. Kind, state, site-ownership, and relationship
   consequences are policies inside the one transaction; allowing a free tuple of cell structural
   effects would reopen the composition algebra.

4. **Immutable lifecycle before/after policy views — Compatible implementation choice.** The
   semantic capability to read immutable pre-state and validated planned-result values is necessary
   for accepted post-partition mathematics. The exact type names and whether one or two concrete
   views are used are private implementation choices. The authoritative text should specify the
   available facts and isolation law, not freeze these Julia type names.

5. **Never-used/active/reusable slot status — Essential clarification.** It is required to make the
   accepted generation-on-reuse law, first generation, high-water allocation, same-MCS non-reuse,
   stale endpoint behavior, and checkpoint continuation simultaneously exact. The accepted
   equivalent high-water-plus-reusable representation remains valid.

6. **Concrete frozen constructor defaults — Owner question required.** Materializing every realized
   policy is essential, and the already accepted defaults (`RejectLifecycleAmbiguity()` and
   preserve-kind division) may be frozen directly. The candidate additionally chooses default
   filter/error behavior for each structural effect. LCI-R3-03 says the disposition is explicitly
   selected; it does not ballot those omission semantics. Silent filtering versus phase failure
   changes a trajectory and diagnostics. The owner must either accept the exact per-effect defaults
   or require `on_inadmissible` explicitly. Until then, only already accepted defaults may be
   normative.

7. **Closed device statuses and stage-owned folder layout — Reject as a bundled normative
   clarification.** A closed bounded status code and responsibility ownership are compatible and
   useful; the exact status-to-integrity mapping needs P2-02. The mandated multi-file tree and the
   prohibition on recombining any responsibility are not required by an owner decision or compiler
   invariant. They turn private organization into specification and risk duplicating generic
   authorities. Retain ownership constraints and anti-monolith guidance; remove exact filenames and
   file-count requirements from normative authority.

## 5. Findings, ordered by severity

### P0-01 — Extinction has two contradictory accepted outcomes

- **Candidate clause:** 2.6, plus the incomplete reconciliation table in 17.
- **Governing accepted clause:** LCI-R2-02 says completion synthesizes retirement for kinds that
  permit stochastic extinction. In conflict, `spec/lifecycle.md` “Extinction and Retirement” says
  every active zero-occupancy cell must be retired, and Decision 0004 says any zero-volume finite
  cell is retired. `spec/state-model.md` additionally requires every active finite cell to own a
  site at conforming publication boundaries.
- **Smallest location:** `spec/lifecycle.md:326-346`,
  `spec/decisions/0004-lifecycle-transactions.md:21-25`, and candidate `2.6`/`17`.
- **Static counterexample:** a completed kind selects `ForbidExtinction()`, but a zero-occupancy
  active identity is present in `PreLifecycleSnapshot` because of an integrity defect or an
  incorrectly admitted batch. The accepted lifecycle text requires retirement; the candidate
  synthesizes no retire request and forbids an unconditional scan. Both outcomes cannot be true.
- **Consequence:** an implementation must either preserve a hidden retirement authority, leave an
  invalid active identity, or silently choose invariant failure. That is a direct accepted-contract
  contradiction with scientific state and checkpoint consequences.
- **Bounded repair:** amend the lifecycle and Decision 0004 clauses explicitly: ordinary last-site
  loss is prevented for `ForbidExtinction`; a zero-occupancy `ForbidExtinction` identity at lifecycle
  planning is a nonfilterable invariant failure; only `RetireAtZero` synthesizes ordinary retirement;
  no settled boundary may publish an active zero-occupancy identity. Also state that the transient
  pre-lifecycle snapshot may contain zero occupancy only for a due `RetireAtZero` transaction.
  If the owner wants a different treatment of an impossible `ForbidExtinction` zero, that is one
  bounded owner decision.
- **Earliest repair checkpoint:** G5-L0.

### P1-01 — `sites(lattice)` is an unaccepted V1 event-domain expansion

- **Candidate clause:** 2.1.
- **Governing accepted clause:** `spec/lifecycle.md` “Event Structure and Pre-Event Snapshot” names
  active finite cells and one global model target as the required domains; extra domains are merely
  allowed by the open protocol. LCI-R1-01 and LCI-R2-03 accept `CreateCell` and finite placement,
  not one lifecycle request opportunity per lattice site.
- **Smallest location:** candidate `2.1`; `spec/lifecycle.md:61-73`.
- **Microfixture:** `LifecycleProcess(domain = sites(lattice), expression = true,
  effects = (CreateCell(...),))` emits up to lattice volume requests from one rule. A semantically
  equivalent model-domain rule emits one. The choice changes birth multiplicity, conflict sets,
  request capacity, RNG occurrence identities, and memory scaling.
- **Consequence:** this is a public scientific-scope and compiler-bound expansion, not a spelling
  required by site-addressed placement.
- **Bounded repair:** remove `sites(lattice)` from the stable V1-L event-domain inventory and keep
  site expressions inside `SeedAt`/`SeedStencil`, or obtain one explicit owner decision defining
  site-domain emission, occurrence identity, and bound. `cells(kind)` and singleton `model()` are
  sufficient for the accepted effects.
- **Earliest repair checkpoint:** G5-L0.

### P1-02 — External placement/partition/state policies have no complete lifecycle ABI

- **Candidate clause:** 4, 8, and 13.
- **Governing accepted clause:** LCI-R1-04 and LCI-R4-03 require frozen pure-policy extension with
  equal CPU/GPU/inference/checkpoint treatment and zero central executor edits. CCV1-003 requires
  explicit analyzed facts; CCV1-006 and CCV1-009 require the generic descriptor/operation path and
  sole versioned `operation_callable` route.
- **Smallest location:** candidate `4`/`13`; current
  `src/compiler/host/analysis.jl:96-108`, where lifecycle expressions are assigned a relationship
  evaluation context; `src/compiler/host/operations.jl:27-47`, whose transfer has no lifecycle
  policy input/output contract; and `src/compiler/lowering/evaluator_protocols.jl:224-268`.
- **Microfixture:** an external binary partition policy needs the qualified parent, each parent-owned
  site, selected relation, immutable snapshot, planned plane/side, bounded output label, and a proof
  that the two labels conserve ownership and are connected. The candidate does not say which of
  those are evaluator inputs, which result type is required, how bounds/footprints are transferred,
  or how the same callable is invoked in inference, CPU planning, and a device kernel. Implementing
  it today requires a new central context or a policy-specific executor method, while the test
  promises neither.
- **Consequence:** the claimed extension can compile through an alternate or partial path, fail on
  GPU, or force CorePotts edits. The “one unbypassable path” and R4-03 proof are not implementable
  from the candidate.
- **Bounded repair:** add one lifecycle policy/evaluator protocol table to the authoritative
  construction amendment. For trigger, placement, partition, and state transform, specify concrete
  input context, result type/shape, totality, footprint/emission transfer, RNG labels, policy
  identity/provenance, backend capability, and invariant validator. Require all built-in and
  external pure policy expressions to enter through the same frozen operation closure and resolved
  lifecycle evaluator groups; policy values may not introduce executor dispatch or mutation.
- **Earliest repair checkpoint:** G5-L0 for the ABI; implementation begins at G5-L1.

### P1-03 — A frozen callable does not make a completed model immune to Julia method additions

- **Candidate clause:** 4, especially the statement that later method additions cannot alter a
  completed model.
- **Governing accepted clause:** CCV1-002, CCV1-009, CCV1-019, and the accepted replay/fingerprint
  laws require complete structural identity, one frozen callable route, and explicit executable
  compatibility. They do not claim that Julia's global method table is frozen.
- **Smallest location:** candidate `4`; current
  `src/compiler/host/normalization.jl:213-245` freezes a callable value and `331-389` fingerprints
  its type/identity, while `lib/CorePotts/src/execution/static_evaluator.jl:446-463` still invokes
  ordinary Julia dispatch on that value.
- **Static counterexample:** complete a model with isbits callable `ExternalTransform()` and a
  general call method, then load a package defining a more-specific method for the same callable
  and argument types before a new executable invocation. The stored callable value is unchanged,
  but dispatch and therefore semantics can change. Its type string in the current fingerprint does
  not encode method bodies or world age.
- **Consequence:** the candidate overstates completion freeze and can make replay/checkpoint claims
  false or impossible to enforce.
- **Bounded repair:** state the enforceable invariant: registry contents and callable selection are
  frozen; no live registry is consulted; callable/schema/version and executable environment identity
  are fingerprinted; code/method-table changes invalidate exact executable compatibility and require
  recompilation/requalification. Do not promise method-table immutability from a concrete value.
- **Earliest repair checkpoint:** G5-L0.

### P1-04 — New omission defaults select scientific failure semantics without an owner decision

- **Candidate clause:** 2.8, 3, and clarification 20.6.
- **Governing accepted clause:** LCI-R3-03 requires each effect to declare a typed disposition and
  says local invalidity is filtered or fails “as explicitly selected.” The owner separately accepted
  default ambiguity rejection and preserve-kind division, but did not accept the candidate's full
  per-effect `on_inadmissible` default table.
- **Smallest location:** candidate `2.8` and the five constructor signatures in `3`.
- **Microfixture:** omit `on_inadmissible` on a division whose plane produces a disconnected
  daughter. The candidate silently filters and continues; an explicit error aborts the phase. Those
  runs have different diagnostics and future trajectories despite identical visible scientific
  declarations.
- **Consequence:** the public constructor acquires unballoted scientific failure meaning.
- **Bounded repair:** ask the owner to accept the exact default table, or make
  `on_inadmissible` mandatory for the five structural constructors. Continue to freeze and inspect
  whichever concrete value is realized. Already accepted defaults remain unchanged.
- **Earliest repair checkpoint:** G5-L0.

### P2-01 — Exact folder/file layout is overprescribed as normative architecture

- **Candidate clause:** 15 and clarification 20.7.
- **Governing accepted clause:** CCV1-004 keeps compiler machinery private; CCV1-006, CCV1-012,
  CCV1-017, CCV1-018, and CCV1-019 assign generic evaluator, storage, tracker, relationship, and
  checkpoint ownership by protocol, not filename.
- **Smallest location:** candidate `15`.
- **Static proof:** the candidate mandates roughly twenty named files and says responsibilities may
  not be recombined even if a bounded implementation needs only a few cohesive modules. It also
  names lifecycle checkpoint/tracker files while simultaneously requiring generic checkpoint and
  tracker modules to remain authoritative.
- **Consequence:** avoidable subsystem ceremony and a risk of duplicate authorities, without a
  scientific, GPU, or compiler benefit.
- **Bounded repair:** retain a short responsibility/ownership table, prohibit named-biological and
  catch-all executor branches, and state that exact modules/files are private implementation choices
  reviewed for cohesion and authority reuse.
- **Earliest repair checkpoint:** G5-L0.

### P2-02 — Closed device statuses do not map every declared integrity failure

- **Candidate clause:** 7.3 and 12.
- **Governing accepted clause:** LCI-R4-04 and CCV1-011 require stable bounded device failure identity
  and translation after synchronization.
- **Smallest location:** candidate `7.3`/`12`.
- **Microfixture:** a request-buffer/emission-bound violation, missing resolved policy, and backend
  hardware failure all appear in 7.3, but 12 does not say whether they map to evaluator, footprint,
  invariant, or backend status; a hardware failure may be unable to write any device record.
- **Consequence:** backends can translate the same integrity event differently and tests cannot
  assert the promised closed diagnostic contract.
- **Bounded repair:** add a one-row-per-integrity-class mapping to either a device-written code or a
  host-synthesized backend failure. The exact enum names may remain private if stable public
  categories and fields are specified.
- **Earliest repair checkpoint:** G5-L1.

### P2-03 — Relationship override cardinality has two public spellings

- **Candidate clause:** 2.7 and 3.
- **Governing accepted clause:** LCI-R2-01 and LCI-R2-06 require explicit compatible overrides,
  unambiguous resolution, and frozen provenance.
- **Smallest location:** candidate `2.7` says the effect-level value is a tuple, while the division
  example and constructor prose use `relationships = RejectWhileLinked()` as a scalar.
- **Microfixture:** the representative `Divide` form is rejected by a tuple-only constructor or is
  normalized through an undocumented scalar convenience, producing inconsistent inspection and
  serialization.
- **Consequence:** localized public API/diagnostic ambiguity.
- **Bounded repair:** choose one canonical tuple representation. If scalar convenience is retained,
  specify construction-time normalization to a singleton tuple before completion and fingerprinting.
- **Earliest repair checkpoint:** G5-L0.

## 6. Answers to the ten required review questions

1. **Is the structural algebra closed, sufficient, and free of named biological privilege?** Yes.
   The five identity/ownership arities cover the accepted V1 structural boundary without named
   biology. Fusion, fragmentation, arbitrary M-to-N rewriting, and daughter-link transfer remain
   excluded. Sufficiency does not justify the unaccepted site event domain in P1-01.

2. **Does the extinction law genuinely remove hardcoded retirement?** Architecturally yes: an
   explicit kind law synthesized through ordinary compiler primitives removes the central scan.
   Normatively not yet: the unconditional retirement text must be superseded and impossible
   `ForbidExtinction` zero state must have one specified integrity outcome (P0-01).

3. **Are domains, policies, conflicts, capacity, generation, RNG, and checkpoints exact and
   coherent?** Policies, conflicts, complete-batch capacity, delayed reuse, generation-on-creation,
   RNG identities, and settled checkpoints form a coherent set. Domain scope is not exact because
   `sites(lattice)` is new (P1-01); failure defaults need owner authority (P1-04); status mapping and
   relationship override cardinality need P2 repairs.

4. **Is there one unbypassable symbolic-to-resolved-policy/evaluator path with no live registry
   after completion?** The candidate requires no live registry, but it does not yet define the
   lifecycle policy ABI needed to prove a sole route (P1-02). Its method-addition immunity claim is
   unenforceable and must become an executable-compatibility rule (P1-03).

5. **Can external pure policies receive equal CPU/GPU/inference/checkpoint treatment without central
   executor edits?** They can under the existing frozen-operation/static-evaluator architecture,
   but only after the lifecycle contexts, result contracts, transfer facts, and validators in
   P1-02 are normative. The current code has no such complete lifecycle context.

6. **Can the transaction be implemented on Metal with bounded workspaces, no host semantic work,
   and honest scientific publication atomicity?** Yes in principle. Bounded request banks,
   scan/sort workspaces, staged touched destinations, complete preflight, one phase-end status
   transfer, and no observer during commit are compatible with Metal. The candidate correctly does
   not promise crash-consistent rollback; backend failure is terminal and recovery starts from the
   preceding settled checkpoint. Functional evidence is still required at G5-L4.

7. **Does any requirement force request-times-lattice work, identity specialization, dynamic
   dispatch, device exception, or per-MCS allocation?** No. The locality clauses forbid
   request-times-lattice behavior; identities/counts/capacities remain values; device exceptions and
   warm allocation are forbidden. `sites(lattice)` would add a whole-lattice event domain and
   request capacity, though not request-times-lattice work, which is another reason it needs owner
   authority. External policy execution must use concrete evaluator groups rather than new dynamic
   executor dispatch.

8. **Does the test plan prove each claim without an exhaustive matrix or evidence bureaucracy?**
   Yes after the findings are repaired. Isolated exact policy tests plus targeted interaction
   coverage, shared CPU/backend fixtures, explicit qualification, exact properties, and one real
   witness are proportionate. P1-02 must make the external fixture assert a real ABI, and P2-02 must
   make failure-status expectations portable.

9. **Does folder ownership preserve existing generic authorities?** The prose says it does, and the
   existing generic evaluator, storage, relationship, tracker, RNG, checkpoint, and Adapt boundaries
   are suitable authorities. The exact mandatory tree undermines that assurance. Apply P2-01 and
   keep responsibility ownership normative while filenames remain private.

10. **Which clauses must change, and which historical clauses should be superseded?** The exact map
    follows. Normative contradictions must be amended or marked superseded once; historical host
    callbacks, multirate lifecycle, open structural effects, generation-at-retirement, optional
    division connectivity, and current read-only GPU witnesses must not be copied into the new
    authority.

## 7. Exact authoritative amendment map

### `spec/symbolic-potts-v1-compiler-construction.md`

| Location | Required one-time amendment |
|---|---|
| Authority | Cite the accepted lifecycle owner interview and cleared lifecycle consolidation. State that the new V1-L clauses supersede conflicting lower-authority lifecycle implementation wording, while this review remains provenance only. |
| CCV1-003 | Add lifecycle domain/binding, Boolean/unit/type, purity/totality, snapshot read, write/topology footprint, finite emission, policy resolution/provenance, conflict, capacity, generation, RNG, tracker, workspace, and backend facts. Add the P1-02 policy ABI table. |
| CCV1-006 and CCV1-009 | State that the five cell structural verbs are closed structural primitives, while triggers and pure policies use the sole frozen versioned operation/evaluator path. Add explicit lifecycle contexts and forbid policy-owned mutation/executor dispatch. Replace method-table-immunity language per P1-03. |
| CCV1-011 | Add lifecycle preflight/publication and the P2-02 status translation map; distinguish device-written semantic status from host-synthesized terminal backend failure. |
| CCV1-012 | Add never-used/active/reusable or equivalent high-water representation; first generation one; generation advances once on allocation; inactive state follows schema retirement values; site ownership-change policy is explicit. |
| CCV1-013 | Add persistent lifecycle request, key, compaction, sort, allocation, staging, tracker/relationship, and status workspace bounds with zero warm allocation. |
| CCV1-017 and CCV1-018 | Require lifecycle invalidation/repair through generic trackers and cell-transaction relationship consequences through the existing canonical relationship authority, with complete joint capacity preflight and publication. |
| CCV1-019 | Add slot status/high-water/reusable facts, lifecycle policy/stream identity, and future-semantic counters; exclude request/sort/staging workspace. |
| CCV1-020 and CCV1-021 | Add functional execution of all five effects and stable built-in policy families on the shared GPU witness, plus the neutral downstream lifecycle policy fixture through CPU, GPU, inference, adaptation, checkpoint, replay, inspection, and diagnostics. |
| CCV1-022 G5 | Insert G5-L0 through G5-L5 as bounded sub-checkpoints of G5. State that the current authorized effort stops after cleared R2 and before G6; future G6 remains a separate owner action. |
| CCV1-023/024 | Add the nine lifecycle exit-evidence rows, failure routing to G5-L1 through G5-L5, fixed-group `1/32/1024` checks, locality sentinels, exact lifecycle RNG/checkpoint properties, and shared fast/qualification profile rule. |
| CCV1-026 | Add neutral exact microfixtures for create/remove/retire/transition/divide and every stable policy family; do not add proof-model migration. |

### Conflicting accepted specifications and decisions

| Authority | Exact amendment or supersession |
|---|---|
| `spec/state-model.md` “Finite Cells” and “State Invariants” | Qualify positive occupancy as a settled/public-state invariant; define the bounded pre-lifecycle transient for `RetireAtZero`; forbid publication of any active zero-volume identity. |
| `spec/state-model.md` “Cell Counts and Capacity” / “Slot Reuse” | Add never-used versus reusable/high-water facts, generation-one first allocation, generation-on-reallocation after overflow preflight, no same-MCS reuse, and checkpoint persistence. Retain ascending reusable IDs. |
| `spec/state-model.md` “Property Schema” | Name separate creation, removal/retirement, transition, and division values; add `override -> schema -> fail`, provenance, site ownership-change law, and derived repair. Do not add a behavioral superclass or central policy switch. |
| `spec/lifecycle.md` “Lifecycle Phase” | Supersede the old numbered category-order algorithm with the closed phase order and common snapshot followed by canonical request/conflict/plan/preflight/commit/repair/publication. Remove hardcoded retirement ordering. |
| `spec/lifecycle.md` “Event Structure” | Retain active-cell and singleton-global domains. Do not add `sites(lattice)` unless P1-01 receives an owner decision. State structural verbs closed and pure policy operations open through frozen schemas. |
| `spec/lifecycle.md` “Division Eligibility/Identity/Geometry” | Replace ascending-parent-ID compaction with canonical request identity after conflict resolution; retain lowest available allocation. Require explicit relation and two connected nonempty partitions. Materialize preserve-kind defaults for both descendants. Mark optional connectivity and permanently-open/nonplanar geometry wording superseded for V1-L while preserving later-scope provenance. |
| `spec/lifecycle.md` “Property Inheritance” / “Auxiliary State” | Replace illustrative policy language with the accepted literal families and external pure-policy ABI; retain schema authority and family-specific mathematics. |
| `spec/lifecycle.md` “Extinction and Retirement” | Apply P0-01: replace unconditional retirement with explicit kind law, synthesized ordinary `Retire`, nonfilterable impossible-state handling, schema cleanup, and generation-on-next-allocation. |
| `spec/lifecycle.md` “Lifecycle Execution Locations” / “Phase 8 Minimal Implementation Boundary” | Exclude host-only triggers/actions, multirate boundaries, open structural effects, nonbinary division, and callbacks from stable V1-L/R2 claims. Preserve them only as historical/later-scope text. |
| Decision 0004 | Supersede “any zero-volume” and “carry an incremented generation” with the explicit extinction law and generation-on-later-allocation. Replace stable parent-ID batch ordering with canonical request ordering while retaining lowest-slot allocation and complete-batch failure. |
| Decision 0019 | Retain as compatible authority; sharpen creation/removal policy slots, explicit override precedence, lifecycle planned-result inputs, and the sole frozen pure-policy ABI. |
| Decision 0006 | Retain as compatible authority. Cross-reference lifecycle footprint conflicts, semantic priority, no atomic-arrival meaning, and declared numerical/replay profile. |
| `spec/randomness-and-reproducibility.md` | Version the concrete address; add honest `CellEntity`, lifecycle streams, model/site/cell occurrence rules, destination/descendant/policy/draw identities, stochastic remainder/redraw rules, injectivity, fingerprinting, and checkpoint continuation. Mark the old global/site-only packed address superseded for lifecycle draws. |

### Historical/current clauses to mark superseded, not duplicate

- Open registration of structural lifecycle effects: superseded by five closed verbs; pure
  operation/policy registration remains.
- Host-only synchronized lifecycle triggers/actions as a stable alternative: excluded from V1-L and
  R2 claims.
- Multirate or sub-MCS lifecycle clocks: deferred.
- Optional division connectivity and broader open/nonbinary geometry catalogs: historical later
  scope, not V1-L behavior.
- Generation increment at retirement and unconditional executor retirement: superseded.
- Current after-MCS folding of lifecycle relationship work and current read-only relationship GPU
  evidence: implementation history only, not functional lifecycle qualification.
- Exact filenames in candidate section 15: non-authoritative implementation guidance after P2-01.

## 8. Bounded implementation readiness: G5-L1 through G5-L5

| Checkpoint | Readiness disposition |
|---|---|
| G5-L1 — surface, schemas, compiler facts | **Not authorized.** Technically bounded after G5-L0 resolves P1-01, P1-02, P1-03, P1-04, and P2-03. The current traversal/frozen-operation machinery is reusable; a distinct lifecycle context and exact policy transfer facts are required. |
| G5-L2 — transaction IR and sequential reference | **Not authorized.** The closed effects, slot law, state/relationship policies, staged commit, and checkpoint facts are implementable after P0-01. Replace, do not wrap, the current scan and zeroing path. |
| G5-L3 — shared checkerboard CPU | **Not authorized.** One plan is feasible, but it must use canonical conflict/allocation and reusable workspaces and must not reuse the current after-MCS lifecycle folding as a second authority. |
| G5-L4 — functional GPU and external extension | **Not authorized.** Metal is a plausible witness, but current device code rejects stage buffers and proves relationship reads only. All effects/policies and the repaired external ABI must execute device-resident before clearance. |
| G5-L5 — qualification and R2 handoff | **Not authorized.** The proposed DRY fast/qualification split and exit matrix are adequate after the earlier gates. R2 must be fresh and work stops before G6 if it clears. |

## 9. Implementation authorization

**Implementation may not begin.** The verdict is **Blocked** at G5-L0. Resolve P0-01 and all P1
findings, disposition the P2 amendments in the one authoritative consolidation edit, and then obtain
fresh G5-L0 clearance. This review authorizes no production edits, model migrations, broadened V1
features, proof-model work, G6 work, or second evaluator.
