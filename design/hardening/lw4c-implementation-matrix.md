# LW-4C consolidation and API-freeze implementation matrix

Status: complete; final LW-R2 passed and LW-4 frozen

Baseline: commit `44389fc`, manifest `design/hardening/lw4b-b5-final-hashes.sha256`

## Gate rules

- Execute C0, C1, C2, C3 and LW-R2 in order.
- Each production slice lands with focused tests and then runs the standalone package suite.
- C1 changes no public names, lifecycle, output laws, launch schedule or qualification claims.
- C2/C3 conveniences desugar into the same lifecycle and centrally admitted lowerings.
- No automatic allocation occurs in `plan`, `run!` or `inspect`; warm execution never grows.
- No new execution family is admitted without two unrelated complete consumers.
- LW-5 opens only after fresh LW-R2 passes and the exact bundle is sealed,
  committed, and accepted by `--verify-final`; G6 remains separately closed.

## LW-4C0 — internal complexity audit

| ID | Requirement | Authoritative evidence | Status |
|---|---|---|---|
| C0-01 | Preserve exact qualified baseline before edits | commit `44389fc`; 61-row manifest verifies | complete |
| C0-02 | Record source size and ownership inventory | `lw4c0-internal-complexity-audit.md` size/layer tables | complete |
| C0-03 | Map validation, topology, binding, workspace, evidence and lowering duplication | C1-A through C1-G in audit | complete |
| C0-04 | Justify every abstraction and specialization | ownership and specialization tables | complete |
| C0-05 | Preserve performance and semantic vetoes | audit non-regression contract | complete |
| C0-06 | Independent API, GPU and numerical advisory | audit reviewer findings and retained memos | complete |

## LW-4C1 — implementation consolidation

Status: complete. Exact evidence: `lw4c1-consolidation-evidence.md`.

| ID | Required production change | Focused tests | Broad gate |
|---|---|---|---|
| C1-01 | Central exact epoch/count/item-domain and dense route structural helpers | epoch type, lossless Int, Int32 terminal, wrong matrix/type/shape, negative/out-of-range route, full-coverage uniqueness | standalone + CPU witnesses |
| C1-02 | Private immutable binding requirements drive required names, access and common layout checks | static/mixed/all-submission-bound storage; missing/extra names; wrong type/shape/access; read/read alias allowed; writable alias rejected; sequence access merge | standalone + hostile admission |
| C1-03 | Private workspace specification drives validation, enumeration, checked bytes and inspection | direct empty; buffered values/valid/rank; winner pair; sequence; short/type/shape/stride/backend/device/alias rejection; exact bytes and identities | standalone + CPU/Metal |
| C1-04 | One static-topology payload drives prepare-time copies and checked transfer bytes | exact leaf names/types/bytes; CPU copy independence; Metal device arrays; stale mutation; conjunctive empty payload | standalone + CPU/Metal |
| C1-05 | Shared determinism and per-port evidence constructors retain complete semantic fields | all eight dimensions; direct/combined/resolved/conjunctive exact facts; specialized mask and conjunctive empty/private-key regression rows | standalone inspection tests |
| C1-06 | Share only typed sentinel/rank/identity/winner primitives across atomic arbitration profiles | min/max endpoints; canonical tie; zero/no claim; one-key and two-key parity; device compilation | standalone + Metal native rows |
| C1-07 | Prove generic resolved covers every legacy four-launch obligation | mask true/false/symbol, active 0/max, empty destination, static/dynamic storage, stale topology, invalid rank/identity, failure/poison/lease, CPU/Metal inspect parity | complete resolved equivalence runner |
| C1-08 | Remove legacy resolved lowering only if C1-07 and controlled performance pass; otherwise document the exact retained gap | source inventory excludes dead types/functions or records concrete veto | full qualification |
| C1-09 | Preserve exact launch/allocation/order/failure/security behavior | launch counts, zero warm growth, compiler-cache count, one wait, queued drain, preexisting provider-wait piracy rejects during preparation, post-submission changes to provider wait, lease release, lease indexing, and CorePotts' exact public run/wait adapters drain through the last admitted world, provider failure | full standalone/Core/root/CPU/Metal |

C1-01 through C1-06 and C1-09 pass. C1-07 proves generic resolved semantic and performance
coverage but not source-compatible preservation of the legacy named-family descriptor, flat
topology, eager mask, winner-table inspection and workspace shape. Under C1-08, the legacy path is
therefore retained as an isolated compatibility adapter with no CorePotts authority; the exact
gap and prohibition on new adoption are recorded in the C1 evidence.

## LW-4C2 — construction and authoring simplification

Status: complete. Exact evidence: `lw4c2-construction-evidence.md`.

| ID | Required behavior | Tests |
|---|---|---|
| C2-01 | Canonical generic topology construction derives only item count; epoch, routes, destination counts and resolved semantic IDs remain explicit | D2Q9, springs, FEM, z-buffer; empty FEM destination not inferred from route maximum; malformed names/shapes fail in plan |
| C2-02 | Storage remains an ordinary named tuple; diagnostics identify missing/extra binding, role and access | static, mixed and entirely submission-bound examples; alias and device mismatch errors |
| C2-03 | Package-owned automatic bounded workspace is optional; explicit caller workspace remains supported | auto/explicit parity for every retained lowering and sequence; exact arrays/bytes/backend/device/lease capacity; malformed explicit workspace still rejects |
| C2-04 | Automatic scratch uses `KernelAbstractions.allocate`, never zeros/host+Adapt/vendor constructors/fallback; allocation occurs only in prepare | source scan; allocation failure prelaunch; no hidden launch/wait; zero warm workspace growth; real Metal `allowscalar(false)` |
| C2-05 | Prepared inspection distinguishes automatic versus caller-owned workspace and reports exact bounded storage | non-synchronizing inspect/show; stable identities; bytes agree with plan specification |
| C2-06 | Tuple sequence sugar, if retained, is an exact tuple-to-varargs desugaring; no vectors/iterables/scheduler | type inference, visibility/order, no intermediate wait |

## LW-4C3 — public API reconciliation

Status: implementation complete; exact evidence:
`lw4c3-api-evidence.md`. Final all-layer qualification remains open.

| ID | Required behavior | Tests/evidence |
|---|---|---|
| C3-01 | Level 1 supports concise explicit-name single-output work without a second lowering or lifecycle | direct, combined and resolved do-block examples; wrapper is isbits/inferred/device-compilable; underlying method substitution guarded |
| C3-02 | Level 2 retains readable named heterogeneous outputs, explicit reads/routes/ports/active/masks/aliases/slots/laws/epochs/sequences | complete lattice-spring example and inspect parity |
| C3-03 | Extension API admits concrete isbits operations and declarative laws only through central lowering/qualification | external module example without LocalWorksets source edit; invalid custom capability cannot self-authorize |
| C3-04 | Intended names are public/documented; collision-safe conveniences are exported, while `inspect` stays qualified; compiler nodes remain private; semantic `propertynames` hide lowering/runtime/provider internals | exact names/exports/docs/property tests; combined PottsToolkit/LocalWorksets ambiguity witness |
| C3-05 | `LocalWorkValidationError` exposes stable stage/contract/port/binding/workspace-leaf/expected/actual/hint fields and occurs before launch when knowable; selected-device compiler faults follow the portable backend failure/poison contract unless a reviewed provider compile-validation protocol exists | field-based invalid declaration/topology/storage/workspace/operation/submission/backend/poison tests plus qualified backend failure witnesses |
| C3-06 | `show` is concise; `inspect` is non-synchronizing and derives author-oriented summary/output/execution/memory/qualification groups from the same authoritative facts | derivation equality, no wait-count change, output snapshots for all lifecycle values |
| C3-07 | Complete copy-pastable CPU examples cover D2Q9, springs, FEM, z-buffer, CorePotts arbitration and external operation; GPU change is backend/storage only | doctest/example runner plus qualified Metal mirror |
| C3-08 | No macro DSL, public compiler node, scheduler, pool, native event, vendor branch or hidden host fallback is introduced | source and public-surface scans |

## Pre-freeze usability and maintainability lens

Status: classifications and bounded remediation complete; exact-bundle ballots
passed and the final record is sealed. Pre-freeze authority:
`lw4c-usability-maintainability-audit.md`; final authority:
`lw4-final-qualification-bundle`.

| ID | Required behavior | Tests/evidence |
|---|---|---|
| U-01 | New code has one resolved language: `resolved` plus conditional `candidate`; legacy mask/descriptor/topology/workspace/four-launch surface is compatibility-only with no new consumers and explicit unit-removal criteria | README/audit migration rule; source/consumer inventory; generic resolved CPU/Metal parity |
| U-02 | Common mechanisms use package-owned automatic workspace; explicit lowering layouts remain expert, inspectable, and not an accidental second stable authoring API | automatic direct/buffered/single-resolved/legacy/conjunctive/sequence tests; exact bytes/identities; warm no-growth |
| U-03 | Inspection answers author questions without a second evidence graph | `summary`, `outputs`, `execution`, `memory`, `qualification` derived from flat facts and tested equal |
| U-04 | GPU state distinguishes structural validation, reviewed provider environment, host runtime or deferred selected-device compilation, unavailable provider preflight, and forbidden host fallback | CPU/Metal inspection plus first-run failure/poison and vendor-neutral source scans |
| U-05 | Ordinary external operations require zero LocalWorksets edits; change amplification for types, backends, families, and mechanisms is documented and bounded | external module witness; audit contributor table; capability-piracy tests |
| U-06 | Every attractive expansion is classified before freeze | decision table classifies required, bounded post-freeze, LW-5, and rejected items; no 10/10 claim |

## Qualification before LW-R2

| ID | Evidence | Admission |
|---|---|---|
| Q-01 | standalone LocalWorksets suite | all tests pass |
| Q-02 | CorePotts suite and LocalWorksets vertical | all tests pass; Hamiltonian/RNG/settlement/checkpoint ownership unchanged |
| Q-03 | PottsToolkit root suite | all tests pass; wall time is not performance evidence |
| Q-04 | five CPU witnesses and controlled direct parity | all results exact/tolerance-qualified and gates pass |
| Q-05 | complete real-Metal runner | cross-domain, native, hostile, lifecycle, queued settlement and performance rows pass |
| Q-06 | source/hash/footprint report | exact candidate hashes; before/after ownership and complexity disposition; no arbitrary line target |
| Q-07 | one reproducible qualification driver and immutable bundle | exact project/manifest/candidate hashes; commands/exact exits/raw logs; serialized witness/performance/counter/workspace results; machine/backend identity; unchanged candidate proof; exact-bundle ballots and seal manifest |

## LW-R2 — fresh public-surface freeze review

Fresh reviewers independently ballot on standalone independence, boundedness of every mechanism,
Level 1 readability, Level 2 completeness, extension safety, CPU/Metal qualification, CorePotts
parity/ownership and readiness for LW-5. Require independent memos before contradiction/red-team
deliberation. P0/P1 findings block; substantive P2 dissent is preserved with an explicit owner.

## Final disposition

All C0-C3 and Q-01-Q-07 obligations are complete. The sealed Freeze binds
product `ee395bd2f70d210fe98a0fb748e6530824c50671` to evidence digest
`49002d9542b64c4c03388ab9bbe30632dfe20a64eac6c2e4bbcb89c50a486641`.
All five specialty ballots passed with P0=0 and P1=0; the chair disposition is
`freeze`. Final seal commit `a65622a2` passes `--verify-final`. Two nonblocking
diagnostic P2s are carried into LW-5. LW-4 is complete and LW-5 is open; G6
remains closed.
