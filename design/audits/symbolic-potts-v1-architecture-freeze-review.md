# Symbolic Potts V1 Architecture-Freeze Review

Status: owner accepted all seven recommendations; bounded architecture-hardening implementation authorized

Date: 2026-08-02

Owner decision: **accept AFI-001 through AFI-007 without amendment**. This authorizes only the
bounded architecture-freeze implementation and qualification described here. G6, proof-model
migration, wrappers, and documentation remain closed until the independent gate reports zero
P0/P1 findings.

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

The amended recommendation resolves this by making the later CCI-009 decision supersede CI-012 only
at this narrow boundary:

> The structural normalized grammar is closed. The operation vocabulary may be extended only before
> completion through a versioned schema and concrete callable contract. Completion materializes an
> immutable registry snapshot. No dynamic registry enters analysis, lowering, or execution after
> completion.

The executable therefore remains closed: no registry, symbol switch, closure, callback, or host
fallback crosses into CorePotts.

## Hypothesis audit

### AFH-001 — The normalized expression grammar is structurally closed

Assessment: **partially supported**.

`NormalizedTermGraph` is an indexed ordered DAG and unsupported calls are rejected. However,
`NormalizedTermNode` still stores `payload_kind::Symbol` and `payload::Any`, accepts a
`:symbolic_leaf` fallback, and does not validate every leaf kind and payload shape as one closed
grammar. Lowering eventually rejects an unresolved leaf, but late rejection is weaker than a
structurally closed normalized IR. Semantic closure does not require a type for every grammar
production: a compact tagged node with value-level payloads remains acceptable when its tag,
payload schema, operand law, and root legality are exhaustively validated.

### AFH-002 — Every operation declares the complete semantic contract

Assessment: **partially supported**.

`OperationTransfer` declares identity, version, serialization identity, arity, result and unit
rules, purity, totality, footprint transfer, tracker requirements, and CPU/GPU support. It does not
explicitly declare operand type constraints or scientific role/stage/context legality. Some
legality is instead established by statement validation, affected-domain rejection, and concrete
callable context methods. That distribution can make an operation legal only accidentally. The
repair must remain a small contract—`allowed_roles`, `allowed_phases`, and `required_context`—rather
than a complete role × phase × context permission lattice.

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
5. a deliberate module and admission disposition for Merks, Act, and native field Euler;
6. an exact versioned V1 operation inventory and admission rule; and
7. six decisive focused tests plus one bounded independent review.

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

- semantically closed, exhaustively validated normalized grammar without requiring a parametric AST
  type explosion;
- a small explicit operation legality contract;
- typed qualified binding identities before analysis;
- affected-anchor derivation over first-class proof facts;
- named-operation and vocabulary freeze; and
- one independent architecture-freeze review with zero P0/P1.

The following are explicitly nonessential to this boundary:

- a general query, transition, or neighborhood-reduction DSL;
- a universal external process/effect API;
- new engines or schedulers;
- migration, wrappers, or documentation;
- Wortel, Merks, or focal reconstruction; and
- moving the CPU workgroup matrix into ordinary CI, which remains an independent nonblocking P2.

## Owner interview

Each recommendation is a proposal to accept, reject, or amend.

### AFI-001 — Closed normalized grammar

Recommended: replace free-form leaf classification with a semantically closed, exhaustively
validated discriminated payload grammar. Its physical representation may remain a compact tagged
host node with value-level payloads; `payload::Any` is not itself a defect in a host-only compiler
graph. A suitable payload boundary is equivalent to:

```julia
Union{
    LiteralPayload,
    ParameterBinding,
    StateBinding,
    ResourceBinding,
    ContextBinding,
    AnchorBinding,
}
```

Every tag, payload schema, operand law, and permitted root role must be verified before analysis.
`:symbolic_leaf` may exist only as a normalization diagnostic state and cannot enter
`AnalyzedTermIR`. Do not create dozens of occurrence- or identity-parameterized node types.

Alternative: retain unchecked `Symbol`/`Any` storage and rely on eventual lowering rejection.
Rejected because this does not establish semantic closure.

### AFI-002 — Complete operation contract

Recommended: extend the versioned operation schema with closed operand/result constraints and the
small legality contract `allowed_roles`, `allowed_phases`, and `required_context`. Only populate
facts relevant to the operation. Preserve the existing unit, purity, totality, footprint, tracker,
CPU/GPU, serialization, and callable requirements. Compiler analysis validates the complete
contract; concrete callable-context dispatch remains the final technical defense.

Alternative: retain distributed legality checks. Rejected by the recommendation because legality
would remain difficult to inspect and extend consistently.

### AFI-003 — Qualified binding authority

Recommended: resolve surface tokens to typed qualified binding/resource identities while creating
the normalized DAG. Analysis and lowering consume those identities directly. `__potts_*` prefixes
remain only a private surface-capture encoding and diagnostic aid.

Alternative: continue reparsing prefixes during each pass. Rejected by the recommendation because
namespace correctness should be established once before analysis.

### AFI-004 — Affected-anchor proof inputs

Recommended: make domain, bound-anchor identity, expression-read facts, one closed
`CopyProposalTransition` fact, and materialized footprint facts explicit inputs to affected-anchor
derivation. The V1 transition means only that `ownership[target]` changes from `old_owner` to
`new_owner`. Division, retirement, relationship creation, and field stepping do not enter this
Hamiltonian proof. Extension declarations may state an expected result but cannot replace proof.
The coarse locality label is derived afterward for inspection only.

Alternative: keep the current domain-plus-locality dispatch because existing tests prove accepted
terms. This is scientifically adequate for current fixtures but weaker for the compiler thesis.

### AFI-005 — Named-operation disposition

Recommended hybrid:

- Merks local connectivity remains available through `LocalConnectivity`, while its collision
  theorem becomes a scientific registered operation in a PottsToolkit operation-library layer.
- Act becomes a scientific registered drive operation in that same operation-library layer. V1
  does not invent a general reduction DSL solely to decompose it.
- Explicit field Euler remains a generic numerical site-stage operation in a numerics/stage layer,
  with an explicit site-stage legality contract.
- None appears in `compiler/host/coverage.jl` or another central compiler pass as a
  mechanism-identity branch. All three enter through the same frozen operation-admission contract
  used by an external operation.

Alternative A: retain all three as compiler built-ins. Alternative B: generalize all three into a
new DSL. The recommendation avoids both mechanism privilege and premature abstraction.

### AFI-006 — Vocabulary and extension freeze

Recommended: explicitly declare that CCI-009 supersedes CI-012 at the narrow pre-completion
operation-registration boundary quoted above. Freeze the four Hamiltonian domains—sites, cells,
canonical contacts, and bounded relationship edges—separately from other stage-iteration surfaces
such as `IncidentEdges`.

Produce a literal V1 operation inventory with one row per operation containing:

- identity and version;
- owner module;
- legal roles and phases;
- required evaluation context;
- operand and result rules;
- units, purity, and totality;
- footprint rule and tracker requirements;
- CPU/GPU support; and
- concrete callable identity.

A future primitive requires scientific necessity, a versioned complete operation contract,
independent CPU/backend/inference/diagnostic conformance, and proof that the behavior cannot
reasonably compose existing primitives. Registered operations are admitted before completion
freezes an immutable registry snapshot; no registry reaches later analysis, lowering, or execution.

The V1 extensibility claim remains precise: admitted Hamiltonian, callable, state/workspace,
tracker, and existing stage-entry categories receive equal treatment without CorePotts edits. A
universal arbitrary-stage/effect claim is deferred.

Alternative: prohibit all registered symbolic operations and require every extension to lower only
to the fixed built-in vocabulary. This is simpler but conflicts with the later accepted CCI-009 and
the existing external-operation fixture.

### AFI-007 — Freeze gate

Recommended: create one bounded architecture-freeze gate after the owner accepts these decisions.
It has one predeclared review scope and owns only AFI-001 through AFI-006, the six focused tests
below, and an independent zero-P0/P1 review. It does not reopen R2 and does not permit proof-model
migration until it passes.

Execution-control rules:

- repair only P0/P1 findings;
- record P2 for later unless it directly falsifies an accepted invariant;
- add no mechanism, domain, engine, optimizer, evidence ledger, or performance oracle;
- do not repeat the full suite after documentation-only changes;
- use focused tests plus existing root and Metal qualification; and
- stop immediately when the independent review reports zero P0/P1.

Alternative: fold these checks into G6. Rejected by the recommendation because mechanism migration
would then be both the compiler test and the consumer of an unfrozen compiler.

## Decisive acceptance tests

The architecture-freeze gate adds exactly these six semantic tests:

1. An unknown or malformed leaf cannot enter `AnalyzedTermIR`.
2. An operation used in an illegal role or phase fails before lowering with a qualified diagnostic.
3. Renaming or nesting a resource cannot change binding resolution after normalization.
4. Site, cell, contact, and relationship Hamiltonians derive their affected anchors from
   first-class domain, read, copy-transition, and footprint facts.
5. Merks connectivity, Act, and Euler compile without a mechanism-name branch in the central
   compiler and pass through the frozen operation-admission contract.
6. A registered external operation receives the same CPU/GPU, inference, and diagnostic path, and
   registration after completion cannot alter a frozen completed model.

These are focused compiler tests, not a second semantic oracle or a new evidence system.
