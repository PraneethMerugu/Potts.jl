# G5H-5 preservation and removal closure

Status: G5H-5 passed on exact candidate; R2H-C audit pending

Date: 2026-08-08

Authority: the PR01--PR30 register in
[`g5h0-baseline-and-preservation.md`](g5h0-baseline-and-preservation.md).

`Preserved` means the successor witness exercises the final public or owning
package boundary. `Replaced` means the old implementation/API is gone and the
accepted successor passes. `Deferred` is not a support claim and retains no
unstated compatibility surface.

| ID | Closure | Final witness or accepted boundary |
|:--|:--|:--|
| PR01 | preserved/merged | System, traversal, completion/diagnostic, source-authority, fresh-process, and executable authoring-doc suites cover construction, hierarchy, namespaces, idempotence, provenance, and source-located failures. |
| PR02 | preserved | Core semantic-RNG known-answer tests plus root serial/threaded retry, integration distributed identity, and checkpoint continuation witnesses. |
| PR03 | preserved | Core analytic sequential reference/oracles and final public `PottsSystem -> PottsProblem -> solve` programs. |
| PR04 | preserved | Core checkerboard laws, CPU backend conformance, and exact real-Metal no-fallback runner; checkerboard remains a distinct stochastic algorithm. |
| PR05 | preserved/merged | Core-owned immutable compiled-program/fingerprint tests and Potts semantic/completed/scheduled fingerprint tests; the old public executable stage is removed. |
| PR06 | preserved/merged | Core lifecycle event/receipt/atomicity suites, public create-transition-divide-remove-reuse program, generation reuse/stale rejection, per-cell component pools, checkpoint continuation, and Metal lifecycle runner. |
| PR07 | preserved | Core bounded relationship/integrity/scaling suites and public generation-safe create/remove/retune/filter/overflow/checkpoint transaction witnesses. |
| PR08 | preserved | Core tracker recomputation tests and CPU/Metal surface, accepted-copy, relationship, lifecycle, settlement, and checkpoint conformance. |
| PR09 | preserved/merged | Callback, observation, relationship, lifecycle, native exchange/solve, checkpoint, and index-mutation failures retain last settled state and publish typed failure state. |
| PR10 | replaced | Final scheduled-system problem/remake/init/solve/SII/saving/termination behavior and executable Wortel observation program replace overlapping legacy lifecycle paths. |
| PR11 | preserved/merged | One Core logical checkpoint plus the Potts extension block covers trackers, relationships, generations, replica/repeat, native global/per-cell/field state, and explicit replay rejection. |
| PR12 | preserved | Standard SciML `EnsembleProblem` serial/threaded/distributed, retry, reduction, early-stop, and failure witnesses; per-cell batching remains distinct. |
| PR13 | replaced | Typed `NativeInput`/`NativeOutput`/`NativeFieldOutput`, simultaneous island staging, atomic publication, failure, and restart replace external staged-input assimilation. |
| PR14 | replaced | `DiscreteFieldEuler` CPU topology/restart oracle and checked Metal native-field row replace the falsely generic diffusion spelling; MethodOfLines is a separate checked extension. |
| PR15 | replaced | Final black-box Wortel, Merks, and focal witnesses plus complete serial Wortel/Merks reusable programs executed by root tests, strict docs, fresh processes, and directly on the target Mac. No G7 scientific claim is made. |
| PR16 | preserved | MakiePotts package, downstream, adversarial, channel, multiple-media, generation, allocation, and recipe suites consume only public settled host frames/solutions. |
| PR17 | preserved/merged | Independent Core load/test, structured conjunction reports, explicit unsupported preflight, CPU/Metal evidence identities, device transfer/synchronization counters, and no-fallback rows. |
| PR18 | preserved | Unit inference/errors, DynamicQuantities/Unitful conversion, parameter update/remake, integration extension behavior, and both Unitful load orders. |
| PR19 | preserved | Explicit, structural, and procedural placement validation with deterministic replica/repeat initialization and generation-safe state. |
| PR20 | preserved/merged | Spatial query vocabulary, periodic/closed/frozen boundaries, relations/bindings, field maps, independent CPU oracles, and qualified Metal rows. Unsupported 3D execution rejects explicitly. |
| PR21 | preserved | Authoritative API/operation inventories and construction/completion/lowering/diagnostic/execution witnesses cover the admitted statement, effect, phase, schedule, and distribution families; retired spellings are absent. |
| PR22 | preserved/merged | Named compiler/backend SPIs, external fixtures, device rejection/admission, specialization 12/12, independent static evaluator, and private-boundary scan. |
| PR23 | preserved/merged | Source-located diagnostics, shared inspection schemas, semantic/completed/scheduled/profile/checkpoint identities, and capability reports with composed native evidence identity. |
| PR24 | preserved/merged | Core submit/settle/fail/cancel receipts, lifecycle/component publication barriers, host mutation boundaries, and measured Metal synchronization/transfer counts. |
| PR25 | preserved | Aqua, ExplicitImports, platform smoke, isolated Core/base/Makie loads, CPU and Metal extension-order matrices, strict docs, manifests, precompile, and dependency-boundary checks. |
| PR26 | owner-deferred experimental | Makie explorer/rerun controller remains explicitly experimental. Its package tests cover rerun, cancellation, failure, closure, and retained result/error ownership; it is absent from stable docs and gains no support claim. |
| PR27 | replaced | Base `ModelingToolkitBase.mtkcompile(::PottsSystem)`, full-MTK retained native islands, MTKStandardLibrary, Catalyst conversion, and checked MethodOfLines extension replace lossy equation assimilation. |
| PR28 | replaced by narrower explicit capability | Runtime is qualified only for 2D. Public 3D construction reaches structural compilation and then rejects at `init`; Makie 3D rendering remains separately supported. No rank-generic implementation fact is a 3D execution claim. |
| PR29 | substrate preserved; new named physics owner-deferred | Generic auxiliary/component state, lifecycle transfer, RNG identity, checkpoint, CPU batching, and applicable Metal component storage are preserved. No prior named fluctuating-pressure/tension model existed; adding and scientifically naming such physics is deferred rather than presenting a generic component as equilibrium evidence. |
| PR30 | preserved | Independent scientific operation oracles and scheduled volume, contact, elongation, chemotaxis, connectivity, activity, relationship-energy/constraint, Wortel, Merks, and focal black-box witnesses across each admitted profile. |

## Retired-path proof

| Retired surface | Disposition and proof |
|:--|:--|
| `ProcessBigraphs`, its adapter, dependency, extension, and manual | Removed under accepted Decision 0043; active package, extension, test, integration, benchmark, example, workflow, and final-doc scans contain no dependency or invocation. Exact Git/archive recovery remains recorded by G5H-0. |
| `PottsModel` and the unpublished legacy manual | Removed without migration compatibility. All excluded `docs/models` and stale Markdown pages were deleted; every remaining docs page is in the strict curated build. |
| Public `compile` / `PottsExecutable` / early engine constructors | Removed; `mtkcompile` plus late `init`/`solve` specialization is the only public lifecycle, enforced by API inventory and stale-invocation scans. |
| `ExplicitDiffusion` and generic PDE implication | Removed; `DiscreteFieldEuler` and the separately qualified MethodOfLines adapter are documented and tested. |
| `CUDABackend` / `ROCmBackend` | Removed until real extensions qualify them; vendor projects cannot create public support by compilation. |
| `Directed`, unqualified integrator spellings, observation stages, and other retired V1 names | Absent from the authoritative public inventory and tested as undefined. |
| Dagger execution authority | Deferred after measurement; isolated benchmark dependency only, with SciML retaining ensemble semantics. |

## Final closure rule

Implementation candidate `08b2bf0707810461c6f5a970fd2e1aee7ba81806`, tree
`cda132fbeec402a159ce6a9552a63d3a77d9764d`, passed with root runner closure 411/411 and
authoritative surface 2,190/2,190, CorePotts 956/956, MakiePotts 503/503,
pinned integration 278/278, the complete real-Metal runner, strict docs, and
all static qualifiers. R2H-C now audits every disposition. Any finding against
a row above reopens its earliest owning gate.
