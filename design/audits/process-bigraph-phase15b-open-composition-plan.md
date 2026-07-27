# ProcessBigraphs Phase 15.B Open-Composition Implementation Plan

Status: Implemented and directly passing; closed by the Phase 15.B audit and evidence record

Date: 2026-07-26

Authority:

- [Decision 0037](../../spec/decisions/0037-process-bigraph-open-composition.md)
- [Phase 15.B owner interview](process-bigraph-phase15b-open-composition-owner-interview.md)
- [ProcessBigraphs runtime semantics](../../spec/process-bigraph-runtime-semantics.md)
- [Parity registry](../../spec/process-bigraph-parity-registry-v1.toml)

## Objective

Implement immutable, arbitrary-depth open composition over the canonical ProcessBigraph ACSet.
Typed Julia, direct ACSet, structured-cospan, pairwise convenience, and the supported annotated
wiring profile must converge on one semantic model, fingerprint, compiled plan, provenance, and
runtime trace. The slice does not implement dynamic rewriting or claim independent-oracle passage.

## Non-goals

- dynamic add, remove, divide, move, or rewire transactions;
- AlgebraicRewriting adoption;
- a second interface or hierarchy authority;
- implicit scientific conversions;
- generic information-losing wiring-diagram import;
- runtime traversal of authoring structures;
- semantic RNG, observer, or complete specification-oracle closure; and
- complete Phase 15 internal-alpha or public-release claims.

## 15.B0: Schema and API freeze

- Extend the versioned ACSet schema with the minimum same-schema boundary, endpoint-role, export,
  mount, junction, and provenance information required by Decision 0037.
- Define typed semantic records for mounts, junctions, exports, initialization overrides, and the
  n-ary composition declaration.
- Keep the ordinary API declarative and keyword-oriented; keep Catlab-specific construction in an
  advanced namespace or clearly advanced entry point.
- Define versioned structured failures for invalid roles, missing endpoints, incompatible schema,
  collisions, unresolved initialization, and lossy wiring import.
- Update canonical encodings and schema-version checks before implementing composition.

Exit: every new semantic value has one canonical encoding, validation rule, failure code, and
documented lowering target; no implementation path requires a parallel structural model.

## 15.B1: Boundary realization and validation

- Construct same-schema interface fragments and structure-preserving maps into canonical component
  ACSets.
- Validate endpoint existence, visibility, role legality, exact semantic compatibility, and map
  naturality.
- Implement the closed-junction and parent-re-export role truth table: private junctions require
  provider and consumer capability; parent imports may supply the missing provider; parent exports
  may supply the missing consumer; explicitly bidirectional parent endpoints supply both.
- Prove that boundary row order and declaration order do not affect identity.
- Add focused finite truth tables for import/export/bidirectional compatibility and malformed maps.

Exit: a closed Phase 15.A component can be exposed as a validated immutable open component without
changing its internal fingerprint or runtime behavior.

## 15.B2: N-ary composition and identity

- Implement pure candidate composition from one root identity, named mounts, explicit junctions,
  exports, and initialization overrides.
- Derive instance identities from parent identity plus explicit mount key.
- Preserve child namespaces and reject collisions without repair.
- Join any finite number of compatible endpoints under one explicit junction identity.
- Resolve initialization at the composed root and retain complete many-to-one provenance.
- Permit binary or operator conveniences only by lowering to the n-ary declaration before
  canonicalization.

Exit: valid composition publishes one canonical ACSet; every invalid case leaves all inputs
unchanged and returns a deterministic structured failure.

## 15.B3: Hierarchy compilation

- Extend canonical validation from the Phase 15.A single-root restriction to arbitrary finite
  immutable containment.
- Preserve hierarchy, mounted identities, local paths, boundary maps, and exports in the canonical
  structural epoch.
- Flatten executable stores, routes, processes, and steps into existing indexed plan forms.
- Extend provenance to map every canonical hierarchical identity and junction origin to compiled
  locations.
- Keep runtime and checkpoint paths free of ACSet, cospan, wiring-view, or authoring-tree traversal.

Exit: nested and equivalent manually flat declarations compile to equivalent plans and produce
identical serial traces.

## 15.B4: Derived directed wiring profile

- Define the versioned annotated ProcessBigraph directed-wiring profile.
- Derive it read-only from canonical structure.
- Re-import only when all required semantic annotations are present and valid.
- Reject generic or information-losing diagrams for compilation while allowing inspection and
  visualization.
- Establish exact supported-profile round trips and document which generic Catlab views are lossy.

Exit: canonical ACSet to annotated wiring view to canonical ACSet preserves semantic identity;
inspection-only diagrams cannot acquire invented runtime meaning.

## 15.B5: Invariance and integration matrix

Build one non-Potts fork/join biochemical fixture through:

1. flat typed construction;
2. direct canonical ACSet authoring;
3. n-ary typed composition;
4. differently parenthesized pairwise conveniences; and
5. annotated wiring-profile import.

Require identical canonical fingerprints, compiled plans, semantic provenance, initialized state,
settled checkpoints, and serial runtime traces. Add property and metamorphic coverage for:

- ACSet row renumbering;
- declaration, mount, endpoint, and junction order;
- repeated mounts of one definition;
- arbitrary finite nesting depth within test limits;
- public/private endpoint behavior and explicit re-export;
- duplicate identity, path, mount-key, and export rejection;
- n-way junctions;
- compatible defaults, conflicting defaults, and explicit overrides;
- incompatible type, shape, unit, ontology, update, persistence, residency, and transfer metadata;
- malformed boundary maps and incomplete wiring annotations; and
- failure before publication at each composition stage.

Exit: construction history and storage order are observably nonsemantic, and invalid composition
cannot expose partial structure or state.

## 15.B6: Evidence and closure

- Add package-local ordinary-authoring and advanced-AlgebraicJulia documentation.
- Record exact ACSets/Catlab versions and accepted compatibility bounds.
- Create a machine-readable Phase 15.B evidence manifest and a fail-closed checker.
- Run the independent ProcessBigraphs package suite plus PB0 and Phase 15.A evidence checkers.
- Audit exports, dependency direction, runtime structural traversal, repository independence, and
  the absence of upstream Python execution.
- Advance only `structured-cospan-open-composition` and
  `derived-directed-wiring-view` to implemented/direct-passing when all evidence exists.
- Publish a Phase 15.B closure audit that explicitly leaves the independent Julia oracle and
  complete internal alpha open.

Exit: every Decision 0037 obligation points to executable or archived evidence, registry claims
match that evidence, and no later-phase capability is implied.

## Required implementation order

`15.B0 -> 15.B1 -> 15.B2 -> 15.B3 -> 15.B4 -> 15.B5 -> 15.B6`

Schema and identity work cannot be parallelized with composition code because it defines the
canonical encodings. After 15.B2 stabilizes, hierarchy compilation and the derived wiring profile
may be developed independently against the frozen representation, then join for the common
invariance fixture.

## Closure boundary

Phase 15.B is structurally complete when its two registry rows have direct passing evidence. Phase
15.C remains responsible for the independent checked Julia specification oracle, semantic RNG,
read-only observer completion, continuation/invalidation, remaining multirate and update-law
truth tables, failure injection, settled restart, and the final serial internal-alpha gate.
