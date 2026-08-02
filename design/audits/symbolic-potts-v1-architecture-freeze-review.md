# Symbolic Potts V1 Architecture-Freeze Review

Status: owner interview pending; no implementation authorized

Date: 2026-08-02

R2 authority: exact clean commit `82e3df435b5b6d89f2e4f7ccfbd0a86424dfed99` passed with
zero P0, zero P1, one nonblocking P2, and no P3 findings. G6 remains closed.

## Purpose

This review tests the compiler foundation before proof-model migration can make provisional choices
expensive to reverse. Every question below is a hypothesis, not a finding. The review compares the
accepted V1 decisions, the R2-cleared implementation, and the paper-level compiler thesis. It does
not authorize compiler changes, model migration, documentation work, wrappers, or G6.

## Controlling authority and one conflict to resolve

The accepted architecture requires:

- a qualified indexed host DAG with explicit fact tables;
- semantics-preserving ordered normalization;
- compiler-proven types, units, purity, totality, access, footprints, effects, trackers, stages,
  and backend legality;
- a generic CorePotts descriptor protocol with no biological mechanism inventory;
- a small versioned operation contract and one concrete evaluator path; and
- an external fixture that receives the same compiler and backend treatment as built-ins.

Two accepted decisions differ at the operation-extension boundary:

- CI-012 calls the Potts symbolic vocabulary closed and says third-party behavior enters through
  `RegisteredStatement`, not an open symbolic-operation registry.
- The later CCI-009 permits a frozen registered symbolic operation to supply a versioned host schema
  and concrete callable before completion freezes the registry snapshot.

The architecture freeze must resolve this intentionally. The executable remains closed in either
case: no registry, symbol switch, closure, callback, or host fallback crosses into CorePotts.

## Hypothesis audit

### AFH-001 — The normalized expression grammar is structurally closed

Assessment: **partially supported**.

`NormalizedTermGraph` is an indexed ordered DAG and unsupported calls are rejected. However,
`NormalizedTermNode` still stores `payload_kind::Symbol` and `payload::Any`, accepts a
`:symbolic_leaf` fallback, and does not validate every leaf kind and payload shape as one closed
grammar. Lowering eventually rejects an unresolved leaf, but late rejection is weaker than a
structurally closed normalized IR.

### AFH-002 — Every operation declares the complete semantic contract

Assessment: **partially supported**.

`OperationTransfer` declares identity, version, serialization identity, arity, result and unit
rules, purity, totality, footprint transfer, tracker requirements, and CPU/GPU support. It does not
explicitly declare operand type constraints or scientific role/stage/context legality. Some
legality is instead established by statement validation, affected-domain rejection, and concrete
callable context methods. That distribution can make an operation legal only accidentally.

### AFH-003 — Neither CorePotts nor the compiler privileges biological mechanisms

Assessment: **CorePotts yes; host compiler partially**.

CorePotts dispatches on generic roles, operations, accesses, trackers, effects, stages, and
transactions. The compiler still owns named `_potts_merks_local_connectivity`, `_potts_act_energy`,
and `_potts_explicit_field_euler` operation transfers and PottsToolkit callable implementations.
They use the single generic evaluator and introduce no engine branch, but their ownership must be
classified before the operation vocabulary freezes.

### AFH-004 — Affected anchors are proven from first-class facts

Assessment: **scientifically tested but structurally incomplete**.

The compiler stores energy domain and bound anchor, rejects proposal context, RNG, mutation, foreign
anchors, and false extension declarations, and passes independent local/global energy tests.
Nevertheless, `_affected_anchor_fact` selects the final plan from `EnergyDomainFact` plus a coarse
`locality::Symbol`; expression anchor reads are recovered from symbolic prefixes, and proposal
transition facts are implicit in fixed branches. The locality label is derived from the footprint,
not trusted from a user, but the final proof should consume the actual expression-read, transition,
and analyzed-footprint facts directly. `locality` should be a report derived from that proof.

### AFH-005 — Qualified binding identities are authoritative before analysis

Assessment: **not yet**.

The frozen source graph carries qualified statement identities, but normalization classifies Potts
tokens through `__potts_*` name prefixes. Footprint analysis and evaluator/resource lowering parse
those prefixes again. Prefixes are useful surface-capture encodings; they should not remain the
authority for resource or binding identity after normalization.

### AFH-006 — The V1 domain and operation vocabulary can freeze now

Assessment: **domain yes; operation vocabulary pending this interview**.

The minimal domain algebra—sites, cells, canonical contacts, and bounded relationship edges—is
appropriate to freeze. The ordinary operation vocabulary should freeze only after grammar closure,
operation legality, identity authority, and the three named-operation dispositions are decided.

### AFH-007 — A novel external term receives equal treatment

Assessment: **yes within the admitted V1 extension categories, not universally**.

The neutral external Hamiltonian, callable, payload, state/workspace, and tracker fixtures use the
same normalization, analysis, lowering, grouping, evaluator, CPU, Metal, inference, scheduling,
diagnostic, adaptation, and checkpoint boundaries without central executor edits. V1 has not proven
an unrestricted extension protocol for arbitrary new stage or effect categories, and it should not
claim one accidentally.

## Bounded architecture options

### Option A — Specification-minimal freeze

Treat the current implementation as satisfying V1 because the accepted contract explicitly permits
built-in lowering and requires mechanism neutrality primarily in CorePotts. Begin G6 immediately.

Cost: lowest. Risk: proof models cement prefix-based identity, implicit role legality, and named
compiler operations before the paper-level compiler claim is frozen.

### Option B — Bounded compiler hardening before G6

Freeze and implement only:

1. a closed normalized leaf and payload grammar;
2. explicit operation operand and role/stage/context legality;
3. qualified binding/resource identity before analysis;
4. affected-anchor proof from domain, expression reads, proposal transition, and footprint facts;
5. a deliberate disposition for Merks, Act, and native field Euler; and
6. a versioned vocabulary-admission rule with one focused independent review.

Cost: moderate and localized to G1/G2 host/compiler ownership. Benefit: G6 becomes model migration
over a frozen compiler rather than another architecture experiment.

### Option C — Full mechanism externalization before G6

Externalize every scientific operation and complete an open extension protocol for every descriptor,
process, effect, observation, and stage category before proof-model work.

Cost and risk: high. This exceeds accepted V1 scope, reopens the stage/effect taxonomy, and delays
the proof models without a demonstrated requirement.

Recommended option: **B**.

## Proposed essential boundary before G6

The following are proposed as essential:

- closed normalized grammar;
- explicit operation legality contract;
- typed qualified binding identities before analysis;
- affected-anchor derivation over first-class proof facts;
- named-operation and vocabulary freeze; and
- one independent architecture-freeze review with zero P0/P1.

The following are explicitly nonessential to this boundary:

- a general query or neighborhood-reduction DSL;
- a universal external process/effect API;
- new engines or schedulers;
- migration, wrappers, or documentation;
- Wortel, Merks, or focal reconstruction; and
- moving the CPU workgroup matrix into ordinary CI, which remains an independent nonblocking P2.

## Owner interview

Each recommendation is a proposal to accept, reject, or amend.

### AFI-001 — Closed normalized grammar

Recommended: replace free-form leaf classification with a closed discriminated payload grammar.
Host payload data may remain value-level and non-parametric, but every node kind, payload schema,
operand law, and permitted root role must be verified before analysis. `:symbolic_leaf` may exist
only as a normalization diagnostic state and cannot enter `AnalyzedTermIR`.

Alternative: retain `Symbol`/`Any` storage and add only a validator. This is cheaper but makes the
closed grammar conventional rather than structural.

### AFI-002 — Complete operation contract

Recommended: extend the versioned operation schema with closed operand/result constraints and
explicit legal roles, stages, and evaluation-context families. Preserve the existing unit, purity,
totality, footprint, tracker, CPU/GPU, serialization, and callable requirements. Compiler analysis
must validate the complete contract; callable context support remains defense in depth.

Alternative: retain distributed legality checks. Rejected by the recommendation because legality
would remain difficult to inspect and extend consistently.

### AFI-003 — Qualified binding authority

Recommended: resolve surface tokens to typed qualified binding/resource identities while creating
the normalized DAG. Analysis and lowering consume those identities directly. `__potts_*` prefixes
remain only a private surface-capture encoding and diagnostic aid.

Alternative: continue reparsing prefixes during each pass. Rejected by the recommendation because
namespace correctness should be established once before analysis.

### AFI-004 — Affected-anchor proof inputs

Recommended: make domain, bound-anchor identity, expression-read facts, proposal-transition facts,
and materialized footprint facts explicit inputs to one affected-anchor derivation. Extension
declarations may state an expected result but cannot replace proof. The coarse locality label is
derived afterward for inspection only.

Alternative: keep the current domain-plus-locality dispatch because existing tests prove accepted
terms. This is scientifically adequate for current fixtures but weaker for the compiler thesis.

### AFI-005 — Named-operation disposition

Recommended hybrid:

- Merks local connectivity remains available through `LocalConnectivity`, but the Merks collision
  theorem is an algorithm-specific registered operation outside the compiler core.
- Act remains a registered nonequilibrium scientific operation outside the compiler core. V1 does
  not invent a general reduction DSL solely to decompose it.
- Explicit field Euler remains a generic native numerical/stage primitive, outside biological
  mechanism ownership, with an explicit site-stage legality contract.

Alternative A: retain all three as compiler built-ins. Alternative B: generalize all three into a
new DSL. The recommendation avoids both mechanism privilege and premature abstraction.

### AFI-006 — Vocabulary and extension freeze

Recommended: freeze the minimal domain algebra and the ordinary V1 operation vocabulary after
AFI-001 through AFI-005. A future primitive requires scientific necessity, a versioned complete
operation contract, independent CPU/backend/inference/diagnostic conformance, and proof that the
behavior cannot reasonably compose existing primitives. Registered operations are admitted before
completion freezes the registry; no registry reaches the executable.

The V1 extensibility claim remains precise: admitted Hamiltonian, callable, state/workspace,
tracker, and existing stage-entry categories receive equal treatment without CorePotts edits. A
universal arbitrary-stage/effect claim is deferred.

Alternative: prohibit all registered symbolic operations and require every extension to lower only
to the fixed built-in vocabulary. This is simpler but conflicts with the later accepted CCI-009 and
the existing external-operation fixture.

### AFI-007 — Freeze gate

Recommended: create one bounded architecture-freeze gate after the owner accepts these decisions.
It owns only the six items above, their focused tests, and an independent zero-P0/P1 review. It does
not reopen R2 and does not permit proof-model migration until it passes.

Alternative: fold these checks into G6. Rejected by the recommendation because mechanism migration
would then be both the compiler test and the consumer of an unfrozen compiler.
