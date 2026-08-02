# Symbolic Potts V1 Architecture-Freeze Implementation Specification

Status: implementation and local qualification complete; independent AF-Q review pending

Date: 2026-08-02

Authority: the owner accepted AFI-001 through AFI-007 in
`symbolic-potts-v1-architecture-freeze-review.md` without amendment.

## Objective

Freeze the V1 compiler boundary before proof-model migration. After this checkpoint, the compiler
must expose one structurally closed symbolic-to-evaluator path, prove binding and affected-anchor
facts before lowering, and admit built-in and external operations through one frozen contract.

This checkpoint does not authorize G6, Wortel or Merks migration, new scientific mechanisms,
documentation, wrappers, a new engine, a general query or transition DSL, or a new evidence system.

## AF-1 — Closed normalized grammar

Normalization may retain a compact host representation, but every normalized node must have an
exhaustively validated tag and payload schema. Admitted leaf payloads are limited to literals and
resolved parameter, state, resource, context, and anchor bindings. An unresolved symbolic leaf may
exist only long enough to produce a normalization diagnostic; it cannot enter `AnalyzedTermIR`.

Occurrence identity, source names, slots, and qualified binding names remain values. They must not
create a type per model occurrence. The implementation must not introduce a parametric AST
explosion.

## AF-2 — Complete operation admission contract

Every operation admitted before completion must freeze a complete, versioned contract containing:

- identity, version, serialization identity, owner, and concrete callable identity;
- operand constraints and result rule;
- unit rule, purity, and totality;
- footprint transfer and tracker requirements;
- CPU and backend capabilities; and
- the small legality contract `allowed_roles`, `allowed_phases`, and `required_context`.

Analysis validates this contract before lowering. Callable-context dispatch remains a final
technical defense, not the primary semantic legality check. The contract must not become a
role-by-phase-by-context permission lattice.

## AF-3 — Frozen registry and qualified binding authority

The production lifecycle is exactly:

```text
operation registration
    -> completion freezes a full immutable contract snapshot
    -> normalization resolves an operation to a schema in that snapshot
    -> the normalized node stores the resolved schema identity
    -> analysis and lowering never consult the live registry again
```

Late operation registration and changes to transfer/callable-resolution methods must not alter an
already completed model: its complete schema and selected concrete callable value are frozen.
Julia method tables themselves are process-global and mutable; redefining the call method of the
already selected callable type is a code change outside this snapshot guarantee and requires a new
completion/qualification cycle.

Surface capture may encode bindings with private `__potts_*` tokens. Normalization resolves those
tokens once to typed qualified binding/resource identities. Analysis, footprint derivation,
resource lowering, evaluator lowering, and diagnostics consume the resolved identities and must not
reparse token prefixes as semantic authority.

## AF-4 — Affected-anchor proof

V1 has one proposal-transition fact:

```text
CopyProposalTransition:
    ownership[target] changes old_owner -> new_owner
```

Affected-anchor derivation consumes the Hamiltonian domain, bound anchor, resolved expression-read
facts, materialized footprint facts, and this copy transition. Extension assertions may state an
expected affected plan but cannot substitute for compiler proof. Locality is an inspection result
derived from the proof, never an authoritative input.

The Hamiltonian domain algebra remains closed to sites, cells, canonical contacts, and bounded
canonical relationships. Stage iteration domains are separate and do not enlarge this algebra.

## AF-5 — Operation ownership

- Merks `LocalConnectivity` and Act are scientific registered operations owned by a PottsToolkit
  operation-library layer.
- Explicit field Euler is a numerical site-stage operation owned by a numerics/stage layer.
- All three use the same frozen operation-admission path as an external registered operation.
- No central compiler pass or CorePotts executor branches on these mechanism identities.

The checkpoint may move ownership and registration; it may not invent a reduction DSL or general
process/effect extension protocol.

## AF-6 — Vocabulary inventory and extension rule

CCI-009 narrowly supersedes CI-012 only at the pre-completion operation-registration boundary. The
normalized grammar and executable program remain closed; the executable receives no registry,
closure, callback, symbol switch, or host fallback.

The implementation must generate or maintain one literal V1 operation inventory row per operation
with all AF-2 fields. A future primitive is admissible only when scientifically necessary, supplied
with a complete versioned contract, qualified on the same CPU/backend/inference/diagnostic path,
and shown not to compose reasonably from the frozen vocabulary.

The V1 extensibility claim is limited to admitted operation, Hamiltonian, callable,
state/workspace, tracker, and existing stage-entry categories. Arbitrary new stage and effect
categories are not claimed.

## Exact acceptance tests

The gate adds exactly six focused semantic tests:

1. An unknown or malformed leaf cannot enter `AnalyzedTermIR`.
2. An operation in an illegal role or phase fails before lowering with a qualified diagnostic.
3. Renaming or nesting a resource cannot change binding resolution after normalization.
4. Site, cell, contact, and relationship Hamiltonians derive affected anchors from first-class
   domain, read, copy-transition, and footprint facts.
5. Merks connectivity, Act, and Euler compile without a central mechanism-name branch and use the
   frozen operation-admission contract.
6. An external registered operation receives the same CPU/backend, inference, and diagnostic path,
   and registration after completion cannot alter a frozen completed model.

Existing inference, allocation, generated-code/specialization-growth, root, and Metal qualification
remain authoritative. This checkpoint creates no second evaluator, performance oracle, or evidence
ledger.

## Bounded execution checkpoints

### AF-G1 — Grammar, schema, and identity

- close and validate normalized payloads;
- complete and freeze the operation contract;
- resolve qualified identities during normalization;
- prove the single production path is unbypassable; and
- land acceptance tests 1, 2, 3, and the frozen-registry part of 6.

Foundational failure stops the checkpoint before AF-G2.

### AF-G2 — Affected proof, ownership, and inventory

- introduce `CopyProposalTransition` as the only transition fact;
- derive affected anchors from the accepted first-class proof inputs;
- move the three named operations to their accepted ownership layers;
- freeze the literal V1 inventory; and
- land acceptance tests 4, 5, and the equal-treatment part of 6.

### AF-Q — Qualification and independent gate

- run the six focused tests;
- run existing inference, allocation, and specialization-growth checks touched by the work;
- run the existing root suite and Metal qualification once;
- obtain an independent review limited to AF-1 through AF-6 and their tests; and
- repair only P0/P1 findings.

P2 findings are recorded unless they falsify an accepted invariant. Stop immediately when the
review reports zero P0/P1. G6 remains closed until that result is recorded.

## Exit criteria

This checkpoint passes only when all six tests and existing qualification are green, the literal
operation inventory is complete, and an independent reviewer reports zero P0/P1 findings. Passing
freezes the architecture for the next owner decision; it does not itself authorize G6.

## Measured inventory-snapshot decision

The package vocabulary and per-model closure are intentionally separate:

- `_v1_builtin_operation_inventory()` materializes the package-level literal vocabulary for
  documentation and coverage audits without embedding it in completed models.
- `NormalizedTermGraph.operation_snapshot` contains only operations reachable from that model plus
  compiler-synthesized operations proven reachable from its stages, effects, and distribution
  families. Explicit Euler is included only for a resolved explicit field stage; relationship
  endpoint predicates only for relationship creation; and distribution checks only for the used
  family. Used external operations enter this same closure.

This was measured as an architectural hypothesis on the standard precompile workload. Embedding the
entire package inventory in every graph remained incomplete after 143 seconds and 153,610,031
allocations. Restoring the minimal closure completed package precompilation in approximately 42
seconds. An earlier 6.1-billion-allocation run was traced separately to accidentally serializing an
open-ended `UnitRange` as an array; inventory reports now encode arity as scalar minimum/maximum
bounds. The full-embedding result is therefore not conflated with that serialization defect.

After dependency-derived closure was implemented, the same package precompile completed in about
37 seconds. A warmed volume-only completion on the qualification Mac completed in about 4.8 ms,
allocated 642,336 bytes, and froze three reachable operations. Its focused regression budget is
2,000,000 bytes to allow ordinary Julia/version variance without accepting library-size scaling.

## Local qualification evidence

The exact candidate passed the following local qualification on the Apple Metal host:

- focused architecture-freeze suite: 98/98 assertions;
- root `Pkg.test`: 1,442/1,442 assertions in 19m03.2s;
- literal package inventory audit: 65/65 operations; and
- Metal descriptor, checkerboard, shape/workgroup, constraint, energy, and relationship-runtime
  qualification.

The root run first spent 50 seconds constructing and precompiling a newly resolved temporary test
environment. That cold dependency setup is reported separately from the 19m03.2s test duration and
from the warm completion measurements above.
