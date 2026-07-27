# ProcessBigraphs Phase 15.B Open-Composition Closure Audit

Status: Phase 15.B passed

Date: 2026-07-26

Implementation commit: `cef128ac793b3e9a5fcc2875f5430d2a59efca12`

Authority:

- [Decision 0037](../../spec/decisions/0037-process-bigraph-open-composition.md)
- [owner interview](process-bigraph-phase15b-open-composition-owner-interview.md)
- [implementation plan](process-bigraph-phase15b-open-composition-plan.md)
- [runtime semantics](../../spec/process-bigraph-runtime-semantics.md)
- [evidence manifest](../evidence/process-bigraph-phase15b-evidence-v1.toml)

## Outcome

Phase 15.B closes as a bounded direct-evidence implementation. `ProcessBigraphs` 0.3.0 now supports
same-schema typed-store boundaries, real Catlab structured cospans, pure n-ary composition,
arbitrary-depth immutable hierarchy, flat plan lowering with hierarchical provenance, and a
lossless annotated directed-wiring profile.

The two Phase 15.B registry rows are now `implemented` with
`direct_passing_phase15b` evidence:

- `structured-cospan-open-composition`; and
- `derived-directed-wiring-view`.

This is not the complete serial internal alpha. Independent source-derived oracle passage remains
Phase 15.C.

## Requirement audit

| Slice | Result | Evidence |
|---|---|---|
| 15.B0 schema and API freeze | Passed | ACSet schema 1.1.0 adds composite definitions, mount keys, local paths, endpoints, boundary maps, junctions, and junction membership. Keyword-oriented typed declarations have canonical validation and structured failures. |
| 15.B1 boundary realization | Passed | Selected leaf stores lower to same-schema endpoint contracts with import/export/bidirectional roles and optional exact transfer metadata. Real Catlab structured multicospans are produced. The complete finite parent/internal role truth table is tested. |
| 15.B2 n-ary composition | Passed | `CompositionSpec` and `compose_open` provide explicit roots, named mounts, finite junctions, exports, and initialization overrides. Inputs are immutable, repeated definitions receive distinct mounted identities, collisions fail, and n-way provenance is retained. |
| 15.B3 hierarchy compilation | Passed | Static containment is canonical at arbitrary finite depth. Compilation validates the hierarchy, flattens stores/routes/actors into the existing indexed plan, and retains composite, endpoint, boundary, junction, and junction-endpoint provenance. Runtime and checkpoint code do not traverse authoring structures. |
| 15.B4 directed wiring profile | Passed | The versioned annotated ProcessBigraph profile derives a real Catlab directed wiring diagram and re-imports only with intact structure and annotation fingerprints. Generic or mutated diagrams fail closed. |
| 15.B5 integration matrix | Passed | 193 Phase 15.B assertions cover flat typed, hierarchical typed, direct-ACSet, structured-cospan, left/right-grouped four-way, and annotated-wiring authoring; row renumbering; repeated mounts; five-level nesting; a four-way junction; namespace privacy and collision rejection; exact compatibility; root-resolved initialization; malformed maps; wiring corruption; checkpoints; traces; and failure atomicity. |
| 15.B6 evidence and closure | Passed | Package docs contain ordinary and advanced authoring tracks; dependency bounds are recorded; this audit, the machine-readable evidence manifest, and the fail-closed checker exist; the checker is an explicit required CI step; PB0 and Phase 15.A baselines remain exact. |

## Architectural findings

There is still one structural authority. Typed builders, direct ACSet authoring, structured-cospan
access, pairwise grouping conveniences, and annotated wiring views all converge on
`ProcessBigraphACSet`. Cospans and diagrams are artifacts around that authority, not competing
runtime models.

Hierarchy is preserved where it is scientifically useful—identity, namespace, diagnostics, and
provenance—and removed from the ordinary hot path. `ExecutionPlan` contains no ACSet. Runtime and
checkpoint sources contain no ACSet, cospan, wiring-diagram, or `StaticComposite` traversal.

Endpoint compatibility is intentionally strict. Type, shape, units, ontology, update policy,
persistence, residency, and transfer requirements must match exactly. The composer neither
converts scientific values nor inserts implicit device bridges.

## Preserved evidence

- The Phase 14.PB0 model fingerprint remains
  `49614f983db7f29d5c19465db95f5a367211a2ddea514fbf6d653f1fbfc90e30`.
- The PB0 final snapshot fingerprint remains
  `20b33b31def9e172bc7c9a57d4915f18094689667338e0eed90b70aac9ae4a3a`.
- Existing PB0 and Phase 15.A tests pass unchanged except that the Phase 15.A epoch-version
  assertion now follows the exported schema-version constant.
- No Vivarium, Process-Bigraph Python, or Bigraph-Schema Python runtime was installed or executed.

## Remaining Phase 15 work

Phase 15.C must still build and pass the independent checked Julia specification oracle and close
the remaining semantic RNG, observer, continuation/invalidation, update-law, multirate,
failure-injection, and settled-restart matrices. Until that gate passes:

- `internal_alpha` remains false;
- no feature is `oracle_passing` or `qualified`;
- no GPU, Threads, Dagger, adapter, whole-cell, parity, or public-release claim is made; and
- dynamic add/remove/divide/move/rewire operations remain Phase 16 work.
