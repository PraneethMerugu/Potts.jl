# Decision 0037: ProcessBigraphs Open-Composition Semantics

Status: Accepted

Date: 2026-07-26

Implementation disposition: Implemented and directly passing in ProcessBigraphs 0.3.0, then
requalified through the independent Phase 15.C Julia specification oracle. ProcessBigraphs 0.4.0
is now a qualified immutable-topology serial internal alpha. Dynamic structural rewriting remains
Phase 16; complete parity and public release remain unclaimed.

## Context

Phase 15.A established one canonical `ProcessBigraphACSet`, stable semantic identities independent
of ACSet rows, and compilation to an immutable structural epoch and indexed execution plan.
Decision 0036 selected structured cospans for open composition and directed wiring diagrams for
derived inspection, but did not specify the boundary algebra, identity and namespace rules,
initialization ownership, lossless wiring profile, or exact Phase 15/16 boundary.

Those details determine whether reusable components compose without introducing a second
structural authority, construction-order-dependent fingerprints, silent scientific coercion, or
hierarchy traversal in runtime hot paths. They were resolved through the accepted 22-choice
[Phase 15.B owner interview](../../design/audits/process-bigraph-phase15b-open-composition-owner-interview.md).

## Decision

### Boundary representation and compatibility

1. An open boundary is a constrained ProcessBigraph ACSet fragment with structure-preserving maps
   into the component's canonical ACSet. Typed Julia declarations lower to that representation; no
   separate interface model is authoritative.
2. Open composites expose selected typed stores as named endpoints. Internal actor ports remain
   bound to stores.
3. Endpoints declare `import`, `export`, or `bidirectional` roles. Roles constrain legal
   composition without duplicating committed state. `import` is consumer-capable, `export` is
   provider-capable, and `bidirectional` is both. A junction hidden inside the result requires at
   least one provider-capable and one consumer-capable endpoint. A junction re-exported as a parent
   `import` may omit an internal provider; one re-exported as a parent `export` may omit an internal
   consumer; an explicitly declared parent `bidirectional` endpoint supplies both external
   capabilities. Multiple providers or consumers are permitted only after exact compatibility and
   initialization validation. These roles describe composition exposure, not actor read/write
   effects.
4. Composition wiring is explicit and semantic. Name-matching conveniences must elaborate to an
   explicit recorded mapping before validation. Position, row order, and declaration order never
   imply a connection.
5. Joined endpoints must agree exactly on every applicable semantic property, including value
   type and shape, units, ontology meaning, update law, persistence, residency, and transfer
   requirements. Conversion is an explicit process or step, never a composer inference.
6. Composition is a pure candidate operation. Input structures are unchanged, complete validation
   precedes publication, and failure yields no partially composed structure.

### Identity, namespaces, initialization, and provenance

7. A reusable component definition and each mounted instance have distinct identities. Instance
   identity derives from the parent semantic identity and an explicit mount key.
8. Mounts are namespaced. Internal child paths remain below the mount key, and only explicit
   exports enter the parent boundary.
9. Duplicate mount keys, semantic identities, paths, or incompatible exports in one namespace fail
   before publication. Silent suffixing, precedence, and collision repair are forbidden.
10. The author supplies the resulting root semantic identity. Canonical identity does not derive
    from a binary composition tree.
11. Every wiring declaration supplies a semantic junction identity. A joined store takes its
    identity from that junction, which may connect any finite number of compatible endpoints.
12. Initialization resolves once at the composed root. Identical compatible component defaults may
    converge; conflicting defaults fail unless explicitly overridden by the parent; every final
    store has exactly one resolved initializer.
13. A join preserves many-to-one semantic provenance from the junction and every originating
    component, store, and boundary map to the final compiled location. Provenance cannot influence
    execution order.

### Canonical composition and compilation

14. The semantic composition form is n-ary: a root identity, named mounts, explicit junctions,
    explicit exports, and initialization overrides. Pairwise composition and operator syntax may
    exist only as lowering conveniences.
15. The canonical ACSet retains arbitrary finite immutable composite hierarchy. Compilation
    flattens executable stores, routes, processes, and steps into indexed tables with exact
    hierarchical provenance.
16. Equivalent root identity, mounts, junctions, exports, and initialization produce identical
    canonical structure, fingerprint, execution plan, runtime trace, and semantic provenance
    regardless of ACSet rows, declaration order, mount order, or pairwise parenthesization.
    Authoring-operation logs are optional and nonsemantic.
17. Runtime and checkpoint paths consume the compiled epoch and plan. They do not traverse a
    cospan, wiring diagram, authoring hierarchy, or composition history during ordinary execution.

### Wiring views, persistence, and public authoring

18. Directed wiring diagrams are read-only derived views. ProcessBigraphs defines a lossless
    annotated profile containing every identity, schema, endpoint, effect, and route required for
    exact re-import. Generic diagrams missing required semantics are inspection-only and fail
    closed if submitted for compilation.
19. Checkpoints persist canonical structural fingerprints, the structural epoch, semantic identity
    maps, compiled-plan compatibility, committed state, and settled continuation. Raw cospan
    expressions, construction trees, and wiring diagrams are optional interchange artifacts.
20. Ordinary APIs use typed declarative records or keyword-oriented builders for mounts, junctions,
    exports, and initialization overrides. Long positional constructors and category-theory
    vocabulary are not required. Direct ACSet and structured-cospan APIs remain available as an
    advanced track.

### Phase boundary and evidence

21. Phase 15 owns arbitrary-depth immutable open composition and explicit bounded or
    convergence-checked iterative regions over fixed structure. Undeclared cycles remain invalid.
    Phase 16 owns runtime structural add, remove, divide, move, and rewire transactions and new
    structural epochs; it may not redefine Phase 15 time, visibility, iteration, or commit
    semantics.
22. Phase 15.B closes only with typed/ACSet/cospan/wiring authoring convergence; row, declaration,
    mount-order, isomorphism, and parenthesization invariance; boundary privacy and compatibility;
    failure atomicity; hierarchy-to-plan provenance; runtime-trace equivalence; preserved PB0 and
    Phase 15.A evidence; package documentation; registry updates; a machine-readable evidence
    manifest; a checker; and a closure audit. Direct evidence established the Phase 15.B
    implementation; Phase 15.C subsequently supplied the independent-oracle qualification.

## Consequences

- Reusable components can be mounted repeatedly without identity collision or namespace leakage.
- Shared state remains explicit: composition joins exposed stores, while processes continue to
  access state through typed ports and bindings.
- Scientific conversion cannot hide inside structural composition.
- Parenthesization invariance is achievable because semantic identity is n-ary and junction-based,
  not inherited from a binary construction tree.
- Static hierarchy remains visible for authoring, diagnostics, and provenance but is compiled out
  of runtime routing.
- Direct Catlab use remains available without forcing ordinary users to understand structured
  cospans.
- Phase 15.B closed honestly before the independent Julia runtime oracle; Phase 15.C subsequently
  supplied the remaining serial-alpha qualification without redefining this composition contract.

## Rejected alternatives

- A permanent bespoke interface structure beside the canonical ACSet.
- Direct actor-port composition that implicitly synthesizes state.
- Implicit name-, order-, or row-based wiring.
- Automatic unit, type, shape, or ontology coercion during composition.
- In-place or progressively published composition.
- Silent collision renaming or left/right precedence.
- Binary composition trees as semantic identity.
- Initialization through mounting order or update-law reconciliation.
- Flattening away semantic hierarchy or traversing it in runtime hot paths.
- Treating arbitrary information-losing wiring diagrams as compilable declarations.
- Deferring all nested static structure or iteration semantics to Phase 16.
- A long positional or category-theory-first ordinary API.

## Required evidence

- same-schema boundary validity and structure-preserving boundary maps;
- exact endpoint-role and semantic-compatibility truth tables;
- pure failure behavior for every invalid composition stage;
- repeated-definition mounting, namespace privacy, collision rejection, and explicit re-export;
- n-way junction identity, initialization resolution, and many-to-one provenance;
- flat typed, direct ACSet, n-ary cospan, pairwise façade, and annotated-wiring round trips;
- row-renumbering, declaration-order, mount-order, isomorphism, and parenthesization invariance;
- arbitrary-depth static hierarchy compilation with flat-plan equivalence;
- identical model fingerprints, plans, settled checkpoints, and traces for equivalent declarations;
- fail-closed rejection of incomplete generic wiring diagrams;
- absence of cospan, wiring-view, and authoring-hierarchy traversal in ordinary runtime paths; and
- preserved PB0 and Phase 15.A tests, fingerprints, traces, and evidence checks.
