# ProcessBigraphs Phase 15.B Open-Composition Closure Audit

Status: Phase 15.B passed

Date: 2026-07-26

Implementation slice commit: `5caff0ce5e87b001a7abe3a77d1be422daf56d76`

Qualified PR head: `fc3ff11373b979b4d443f0d192d7bf6b8c444a47`

Merged runtime commit: `5643a1e8ca8c3dfc2d1cb124274823beae206dd3`

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

This Phase 15.B slice alone was not the complete serial internal alpha. Phase 15.C subsequently
supplied independent source-derived oracle qualification without changing the Phase 15.B
structural claim.

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

## Post-merge provenance and maintenance disposition

Pull request [#21](https://github.com/PraneethMerugu/Potts.jl/pull/21) qualified the exact head
`fc3ff11373b979b4d443f0d192d7bf6b8c444a47` in CI run
[`30230566611`](https://github.com/PraneethMerugu/Potts.jl/actions/runs/30230566611). The required
aggregate job and the dedicated `Enforce ProcessBigraphs Phase 15.B open composition` step passed.
GitHub squash-merged that head as `5643a1e8ca8c3dfc2d1cb124274823beae206dd3`. The qualified head
and merge commit have the identical Git tree
`a32f86db29dc82276df8fe6e81a6a64bf837e916`; the merge changed history shape, not the qualified
Phase 15.B contents.

The host-side authoring implementation remains intentionally outside runtime hot paths, but its
internal organization carries maintenance debt: `composition.jl` and the central `compose_open`
lowering are large. A later behavior-preserving cleanup should separate validation, mounting,
initializer resolution, ACSet assembly, and provenance construction behind the existing public
API. That cleanup is not required to establish Phase 15.B semantics and must preserve the complete
invariance and failure matrix.

## Subsequent Phase 15.C disposition

Phase 15.C subsequently built and passed the independent checked Julia specification oracle and
closed the semantic RNG, observer, continuation/invalidation, update-law, multirate,
failure-injection, and settled-restart matrices. The closure attestation therefore:

- sets `internal_alpha = true` for ProcessBigraphs 0.4.0;
- qualifies only the 15 target and seven supporting serial-runtime rows;
- retains the four Phase 15.A/B structural rows as direct evidence;
- no GPU, Threads, Dagger, adapter, whole-cell, parity, or public-release claim is made; and
- dynamic add/remove/divide/move/rewire operations remain Phase 16 work.
