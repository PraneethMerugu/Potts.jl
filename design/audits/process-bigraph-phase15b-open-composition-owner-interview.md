# ProcessBigraphs Phase 15.B Open-Composition Owner Interview

Status: Complete; all 22 owner decisions resolved

Date: 2026-07-26

This interview closes the remaining design choices needed to implement Phase 15.B structured-cospan
open composition. It refines, but does not reopen, the canonical-structure and runtime-authority
choices accepted by Decisions 0034 and 0036.

The accepted normative result is
[Decision 0037](../../spec/decisions/0037-process-bigraph-open-composition.md).

## Round 1: Boundary semantics

1. **A.** An open boundary is a constrained ProcessBigraph ACSet fragment with
   structure-preserving maps into the component's canonical ACSet. Typed Julia façades lower to
   this representation; no separate interface authority is retained.
2. **A.** Open composites expose selected typed stores as named endpoints. Internal process and
   step ports remain bound to stores; composition identifies compatible exposed stores rather than
   synthesizing state from direct actor-port connections.
3. **A.** Each endpoint is declared `import`, `export`, or `bidirectional`. The role constrains
   legal composition but does not create a second copy of committed state. Imports are
   consumer-capable, exports are provider-capable, and bidirectional endpoints are both; a private
   junction requires both capabilities, while an explicit parent import or export may supply the
   corresponding open side.
4. **A.** Composition uses explicit semantic endpoint wiring. Name-based convenience APIs may
   elaborate to explicit wiring, but names, declaration position, and ACSet row position never
   connect endpoints implicitly.
5. **A.** Joined endpoints require exact semantic compatibility for applicable value type and
   shape, units, ontology meaning, update law, persistence, residency, and transfer declarations.
   Conversion requires an explicit adapter process or step.
6. **A.** Composition is pure and candidate-based. It leaves inputs unchanged, validates the
   complete candidate, and publishes a result only on success.

## Round 2: Identity, namespaces, and ownership

7. **A.** Reusable component definitions and mounted instances have distinct identities. A mounted
   identity derives from the parent semantic identity and an explicit mount key, so repeated mounts
   of one definition remain distinct.
8. **A.** Mounting is namespaced by default. Child paths remain below the mount key; only explicitly
   exported endpoints enter the parent interface.
9. **A.** Duplicate mount keys, semantic identities, paths, or incompatible exports in one
   namespace fail. The composer never silently renames or selects a winner.
10. **A.** The author supplies the resulting root semantic identity. The structural fingerprint is
    computed from canonical semantic structure, not the construction tree.
11. **A.** Every wiring declaration supplies a semantic junction identity. The joined store takes
    its identity from the junction rather than left/right operand order, and a junction may join
    multiple compatible endpoints.
12. **A.** Initialization resolves at the composed root. Component values are defaults or
    requirements; identical compatible defaults may converge, conflicting defaults fail unless the
    parent explicitly overrides them, and every resulting store has one resolved initializer.
13. **A.** Joining retains many-to-one provenance: the junction, every originating
    component/store, every boundary map, and the final compiled index. Provenance is diagnostic and
    persistent compatibility data, not an execution-order input.

## Round 3: Lowering, views, persistence, and phase closure

14. **A.** The canonical semantic operation is n-ary: one root identity, named mounts, explicit
    junctions, and explicit exports. Binary composition and operator syntax may exist only as
    conveniences that lower to this form before canonicalization or fingerprinting.
15. **A.** The canonical ACSet preserves arbitrary-depth immutable hierarchy. Compilation flattens
    executable stores, routes, processes, and steps into indexed tables while retaining complete
    hierarchical provenance.
16. **A.** Equivalent mounts, junctions, exports, and root identity produce identical canonical
    structure, fingerprint, execution plan, runtime trace, and semantic provenance regardless of
    pairwise construction history. Optional construction logs are nonsemantic.
17. **A.** ProcessBigraphs derives a read-only directed wiring diagram. Re-import is accepted only
    for the lossless annotated ProcessBigraph profile carrying all required identities, schemas,
    boundaries, effects, and routes; generic information-losing diagrams remain inspection-only.
18. **A.** Checkpoints persist canonical structural identity, structural epoch, semantic identity
    maps, compiled-plan compatibility, and settled runtime continuation. Raw cospan expressions,
    binary construction trees, and wiring diagrams are optional interchange rather than checkpoint
    authority.
19. **A.** Phase 15 owns arbitrary-depth immutable open composition. Phase 16 begins when a running
    model adds, removes, divides, moves, or rewires structure and publishes a new epoch.
20. **A.** Phase 15 owns explicit bounded or convergence-checked iterative regions over fixed
    structure; undeclared cycles remain rejected. Phase 16 may admit structural transactions within
    or between those regions without redefining time, visibility, iteration, or commit semantics.
21. **A.** Ordinary authoring uses typed declarative records or a keyword-oriented builder for
    mounts, junctions, exports, and initialization overrides. Long positional constructors and
    category-theory vocabulary are not required. Direct ACSet and structured-cospan entry points
    form the advanced API.
22. **A.** Phase 15.B is a bounded structural closure. It requires open composition, the annotated
    wiring view, authoring convergence, invariance, fail-before-publication behavior, compiled-plan
    and runtime-trace equivalence, preserved PB0/15.A evidence, documentation, registry entries,
    evidence manifest, checker, and closure audit. Its rows may advance to implemented with direct
    evidence, but not independent-oracle-passing before Phase 15.C.

## Completion statement

No Phase 15.B architecture question remains open. The interview authorizes specification and
implementation work; it does not claim that structured-cospan composition, nested lowering,
directed wiring views, or their evidence have been implemented.
