# G5H implementation control

Status: G5H-0 through G5H-3 passed; R2H-A and R2H-B passed; G5H-4 matrix complete and implementation not begun

Authority: [Symbolic Potts V1 G5H Hardening Contract](../../spec/symbolic-potts-v1-hardening.md)

This is the sole living status record for G5H. It records outcomes and exact evidence; it does not
repeat or amend gate requirements.

## Gate state

| Boundary | State | Evidence or blocker |
|:--|:--|:--|
| G5H-0 — authority, baseline, preservation | `passed` | Corrected candidate `9afcf6f1ec44cf84525d8b023c2d1b705560e365`, tree `a8b0ce43489e558e1770f4982dece97ef4c6eca7`, cleared R2H-A with no carried finding. |
| R2H-A — authority and preservation review | `passed` | Fresh independent read-only review of the exact corrected candidate returned `PASS`: P0=0, P1=0, P2=0, P3=0. |
| G5H-1 — semantic and CorePotts consolidation | `passed` | Exact implementation candidate `354469ec82f0daa481a82d982d975d7046f4b71e`, tree `b5ef897a3872a2262112375278ca87d348886668`; CorePotts 952/952, retained package witnesses, named SPIs, exact quantitative evidence, and qualification tools passed. The bounded G5H-3 correction does not touch those authorities. |
| G5H-2 — pure-Potts authoring and SciML lifecycle | `passed` | Corrected candidate `f2d438acf3707125d2f839c3834d505535e627ea`, tree `1f3dc10e3814e43e69dd20c10d634d81d23bdf89`, passed the complete 1,348-assertion authoring, completion, scheduling, problem, SciML lifecycle, SII, checkpoint, diagnostics, scientific-witness, and API surface. |
| G5H-3 — native global MTK integration | `passed` | The corrected candidate's pinned full-MTK suite passed 141/141, covering native retention, upstream structural compilation, preflight-before-execution, exact-only replay reporting, bidirectional ODE coupling, order, restart/remake/failure behavior, MTKStandardLibrary, Catalyst, Unitful, event retention/rejection, and honest DAE runtime rejection. |
| R2H-B — cohesion and real-MTK review | `passed` | Fresh independent read-only rereview of corrected candidate `c0f9f3dc91d2bb29557e36abfab3ec3417ba14d4`, tree `355e8fdaa0dc11dd5130b786b3e8229ea2372693`, returned `PASS`: P0=0, P1=0, P2=0, P3=0. |
| G5H-4 — dynamic components, fields, ensembles, profiles | `pending` | Unblocked by R2H-B. The implementation matrix below is complete; no G5H-4 implementation has begun. |
| G5H-5 — product qualification and docs | `pending` | Depends on G5H-4. |
| R2H-C — hardening exit review | `pending` | Opens only after G5H-5 passes. |
| G6 owner decision | `pending` | G6 remains closed; it requires cleared R2H-C and explicit owner send-off. |

## Review results

The first formal R2H-A review inspected candidate
`6e8ea1c5e68a5a69f51f9c69249b1b756b4fb28c`, tree
`ca052bf1d719cdd48caea4a126fd630a895df5b8`, read-only and returned `PASS` with P0=0, P1=0,
P2=4, and P3=1. It verified the deletion/recovery boundary and found bounded record defects:
incomplete qualification-tool inventory, an invalid control-state spelling and insufficiently
exact command record, the exported `compile` generic mislabeled unexported, stale backend/audit
wording in one active standard, and one dangling historical trace locator.

The contract permitted those P2s to be carried, but the project elected to repair every finding
before clearance. Therefore the first result did not advance G5H-0, and the corrected candidate
required a new exact-commit R2H-A review. Separate request, copied-log, or freshness-ledger files
are not created.

The fresh formal rereview then inspected corrected candidate
`9afcf6f1ec44cf84525d8b023c2d1b705560e365`, tree
`a8b0ce43489e558e1770f4982dece97ef4c6eca7`, read-only and returned `PASS` with P0=0, P1=0,
P2=0, and P3=0. It independently reproduced the authority order, complete preservation and
tooling partitions, all 356 deletion/recovery witnesses, the archive hash and entry count, public
declaration ranges and digests, active-link/TOML/local-path checks, fresh package boundaries, and
closure of every first-review finding. G5H-0 and R2H-A therefore pass with no carried P2.

G5H-1 through G5H-3 were then implemented and frozen on branch `codex/symbolic-potts-v1` as exact
candidate `354469ec82f0daa481a82d982d975d7046f4b71e`, tree
`b5ef897a3872a2262112375278ca87d348886668`. The complete matrix below ran on that clean commit on
the target Mac with Julia 1.12.1 on 2026-08-08. R2H-B reviews this vertical slice; no G5H-4 work
has begun.

The first formal R2H-B review inspected candidate
`e979b6982b000d3f87cf70a3907e3e64bb12e1ad`, tree
`f7711112f1f78284a62452b4cc6bb3a677b37847`, read-only and returned `FAIL` with P0=0, P1=1,
P2=1, and P3=0. It independently reran the pinned full-MTK integration suite at 135/135 and
confirmed the remainder of the vertical slice, but found that an unqualified native solve profile
could reach upstream problem construction and `SciMLBase.init` before evidence rejection. It also
found that the public `NativeSolveProfile` documentation and replay inspection/checkpoint branches
advertised a portable native restart class that no G5H-3 executable evidence row admits. Both
findings belong to G5H-3 and affect the profile interface consumed by G5H-4, so neither is carried.

The bounded correction moves closed native evidence admission ahead of native problem construction
and solver initialization, adds an adversarial invalid-solver-option witness proving preflight
rejection wins, and makes the public inspection, solution provenance, and checkpoint codec state
the exact-configuration-only native contract. Focused pinned integration passes 141/141 after the
repair. The correction is frozen as exact candidate
`f2d438acf3707125d2f839c3834d505535e627ea`, tree
`1f3dc10e3814e43e69dd20c10d634d81d23bdf89`. Its root suite passed runner closure 325/325 and
the authoritative surface 1,348/1,348 in 17m40.8s; pinned integration passed 141/141; strict docs,
fresh PottsToolkit/CorePotts boundaries, 258 Julia parses, 148 TOML parses, the retired-name scan,
and diff integrity passed.

The fresh formal R2H-B rereview then inspected corrected evidence-record candidate
`c0f9f3dc91d2bb29557e36abfab3ec3417ba14d4`, tree
`355e8fdaa0dc11dd5130b786b3e8229ea2372693`, read-only and returned `PASS` with P0=0, P1=0,
P2=0, and P3=0. It independently reran pinned integration at 141/141. Static and dynamic review
proved that closed native evidence is now required before native problem construction or
`SciMLBase.init`, and that public inspection, capability composition, solution provenance,
checkpoint creation, validation, and restoration expose only the reachable exact-configuration
native replay class. No regression, weakened admission semantic, or carried P2 remains. R2H-B
therefore clears and G5H-4 is unblocked but not begun.

## G5H-1 through G5H-3 exact-candidate evidence

Rows below name the corrected candidate when they were rerun after review. Unaffected CorePotts,
MakiePotts, quantitative, and compiler-qualifier rows remain exact evidence from implementation
candidate `354469ec82f0daa481a82d982d975d7046f4b71e`; the bounded correction does not touch their
authorities. Together the rows close the normative G5H-1 through G5H-3 exit conditions; R2H-B was
separately cleared by the independent decision recorded above.

| Obligation | Implemented authority | Exact result | Scope boundary |
|:--|:--|:--|:--|
| F11 settled host relationship mutation | Public `CellIdentity` and `relationship_transaction!(integrator, effects...)` reuse the existing `Create`, `Remove`, and `Retune` effects. Endpoint-pair remove/retune, exact generation checks, integer endpoint auto-stamping, canonical Core validation, one host-candidate rebuild, backend adaptation, and pointer publication form one atomic boundary. Callback failure retains the previously published runtime. | `test/test_relationship_host_transactions_v2.jl`: 22/22 passed. The public API and Core SPI boundary selection passed 550/550. `lib/CorePotts/test/test_program_v1_relationships_checkpoint.jl` supplies package-owned settled-host rebuild, invalid-batch, stale-generation, unsettled-runtime, and cross-store all-or-nothing witnesses. | GPU-resident descriptor requests and no-hidden-transfer backend claims remain G5H-4 obligations; this row proves the settled host path. |

### Exact qualification matrix

| Lane | Reproduction command | Exact result |
|:--|:--|:--|
| PottsToolkit package | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=. --startup-file=no --threads=1 -e 'using Pkg; Pkg.test("PottsToolkit")'` | Corrected candidate: runner closure 325/325; authoritative G5H-1 through G5H-3 surface 1,348/1,348 in 17m40.8s. The re-resolved compatibility lane used ModelingToolkit 11.38.0, ModelingToolkitBase 1.59.0, SciMLBase 3.41.0, Symbolics 7.35.0, and Unitful 1.28.0. |
| CorePotts package | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=lib/CorePotts --startup-file=no --threads=1 -e 'using Pkg; Pkg.test("CorePotts")'` | 952/952 passed, including 10 Aqua assertions; no PottsToolkit, MTK, SciML solver, Makie, or vendor dependency is present. |
| Pinned full-MTK integration | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=integration --startup-file=no --threads=1 integration/runtests.jl` | Corrected candidate: 141/141 passed, including the adversarial preflight-before-initialization and exact-only inspection/checkpoint witnesses, on ModelingToolkit 11.37.1, ModelingToolkitBase 1.58.1, ModelingToolkitStandardLibrary 2.29.5, SciMLBase 3.39.1, Symbolics 7.34.1, DynamicQuantities 1.13.0, and Unitful 1.28.0. |
| MakiePotts preservation | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=lib/MakiePotts --startup-file=no --threads=1 -e 'using Pkg; Pkg.test("MakiePotts")'` | 501/501 passed after rebinding its fixture to the final public lifecycle; its 3D frame witness remains independent of the intentionally unsupported 3D CPM runtime row. |
| Quantitative evidence | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=. --startup-file=no --threads=1 scripts/measure_g5h1_memory_and_scaling.jl` plus four fresh 1/6/24/128-declaration processes | `pass`, `bounded_cpu_evidence_only`; clean commit and tree matched; relationship validation and transaction preparation allocated 0 B after warmup and stayed below the 10x guard; the 128-declaration four-phase path completed in 100.354s. Exact tables are in `g5h1-quantitative-memory-and-scaling-evidence.md`. |
| Compiler/operation qualifiers | The same Julia prefix with `scripts/check_v1_operation_inventory.jl`, `scripts/qualify_specialization_growth.jl`, and `scripts/qualify_static_evaluator.jl` | 68 operations qualified; specialization growth 12/12; independent static evaluator exited zero with exact ordered semantics, inferred `Float32`, zero warmed allocation for the selected representation, fixed occurrence specialization through 1,024 occurrences, and bounded group growth. |
| Strict documentation | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=docs --startup-file=no --threads=1 docs/make.jl` | Corrected candidate: doctests, cross-references, document checks, and HTML rendering passed with `warnonly=false`. |
| Static and fresh boundaries | `git diff --check HEAD^..HEAD`; parse every tracked `.jl` with `Meta.parseall`; parse every tracked TOML; retired-name scan; explicit fresh PottsToolkit/CorePotts load commands | Corrected candidate: clean diff; 258 tracked Julia files and 148 tracked TOMLs parsed; no active retired-package match; no empty maintained directory; PottsToolkit loaded without full ModelingToolkit and CorePotts loaded without PottsToolkit, MTK, SciML, Makie, or the retired package. |

### Gate-specific closure

| Gate | Normative delivery | Authoritative evidence |
|:--|:--|:--|
| G5H-1 | Shared acceptance; consolidated traversal/facts/lifecycle/capability/checkpoint authorities; receipts and bulk component state; honest profile admission; Core-owned settlement/rejection suites; named compiler/backend SPIs and narrow Core API; measured memory/scaling. | `lib/CorePotts/src/{compiler_spi,backend_spi}.jl`, the split Core program/execution sources, all 952 Core assertions, `test/test_source_traversal_authority.jl`, `test/test_core_spi_boundary.jl`, public API and runner-closure tests, the three live qualifier results, and the exact quantitative record. |
| G5H-2 | One functional and `@named` authoring path; composition/namespacing/completion/diagnostics/inspection; base-package structural `mtkcompile`; scheduled system → problem → SciML lifecycle; late profile selection; remake/SII/saving/callback/checkpoint/restore; one API inventory. | `test/test_{system_contract,statements_and_traversal,completion_and_diagnostics,mtkcompile,fresh_process_v2,sciml_lifecycle_v2,lifecycle_public_v2,public_api_v2}.jl` plus the scheduled scientific witnesses, all within the corrected 1,348/1,348 root result. Major invalid construction families assert source-located diagnostics. |
| G5H-3 | Native declarations and typed ports; hierarchy/default/event/observed/SII retention; upstream `mtkcompile` and native problems; explicit MCS/time/order semantics; bidirectional ODE coupling; honest DAE/event boundary; MTKStandardLibrary and Catalyst; coupled restart/remake/error/cancellation/atomicity. | `src/native/*`, `ext/PottsToolkitModelingToolkitExt.jl`, `integration/test_modelingtoolkit_retention_and_structural_scheduling.jl`, `integration/test_modelingtoolkit_standard_library.jl`, and `integration/test_native_runtime.jl`, all within the corrected 141/141 pinned result. Copied `EquationComponent` assimilation is deleted; the Core fresh-load boundary remains MTK free. |

## G5H-4 implementation matrix

This matrix is the implementation plan for G5H-4. It specializes the accepted contract without
creating another semantic authority. The hold points are bounded implementation reviews inside
G5H-4, not new formal R2H gates and not substitutes for G5H-5 or R2H-C. Work may move within one
slice to keep it coherent, but a dependent slice does not claim support before its hold point
passes on an exact commit.

Existing authorities remain authoritative:

- CorePotts owns lifecycle requests, conflict resolution, generation-safe receipts, generic bulk
  slot movement, settlement, backend status, and the logical checkpoint envelope;
- PottsToolkit owns native component values, component policies, fields, coupled publication,
  public capability composition, SciML lifecycle, SII, and ensembles;
- `PottsSystem` remains the only public model, integer completed MCS remains the master time, and
  `CPMThenComponents` remains the default coupled order;
- the existing `NativeComponent` declaration is extended with per-cell and field scopes and their
  policies; G5H-4 does not add parallel component constructors or another subsystem inventory;
- fixed-capacity lifecycle operations are the admitted structural-rewrite boundary; G5H-4 does not
  introduce an unrestricted graph-rewrite engine; and
- the current serial/threaded `EnsembleProblem` implementation is extended, not replaced, while
  per-cell batching remains a separate execution-profile dimension.

### Ordered slices and hold points

| Slice | State | Owned delivery | Planned implementation authority | Mandatory executable evidence | Hold point |
|:--|:--|:--|:--|:--|:--|
| H4-A — component identity and pools | `pending` | Extend the existing native declaration with a namespaced per-cell scope and explicit lifecycle policy; compile-once fixed-capacity structure-of-arrays pools keyed by Core slot and generation; active/generation/kind masks; initial component state; create, delete/remove, retire, divide/duplicate, and transition behavior; stale-generation rejection; one inactive candidate bank and atomic publication. Policies admit only explicit initialize, delete, copy, reset, transform, split, or reject behavior. | Reuse `lib/CorePotts/src/program/{bulk_component_state,lifecycle_receipt}.jl` unchanged as the generic seam. Potts-owned authority is confined to new focused files under `src/native/` for component-pool schema/policy and under `src/runtime/` for coupled component state/publication. Existing completion/namespacing owns declaration validation. `src/runtime/{integrator,checkpoint,saved_state,symbolic_indexing}.jl` integrate the result without adding another lifecycle or codec. | Core receipt/bulk-state suites remain green; new root authoring/pool/lifecycle tests cover functional and `@named` construction, composition/namespacing, capacity exhaustion, generation reuse, every lifecycle variant and policy, division parent/daughter roles, transition transforms, exact-once receipt application, failed-batch atomicity, observation/SII visibility, checkpoint/restore, and source-located invalid declarations. A coupled integration witness proves Core and component candidates publish together. | H4-A passes only when no runtime lifecycle event compiles code or resizes storage; stale identities cannot read/write/inherit state; every reachable settled state checkpoints; failure preserves the prior published bank and emits no receipt/observation. This freezes the component state layout consumed by H4-B/H4-C. |
| H4-B — serial and vectorized CPU components | `pending` | One serial CPU semantic reference for global and per-cell components and one explicitly named vectorized/batched CPU mode for per-cell pools; multiple global islands share the existing simultaneous-island schedule rather than pretending to be a cell batch. The first admitted subset is fixed-shape fixed-step ODE, with deterministic lane assignment, observation/checkpoint parity, and clear separation from trajectory ensembles. | New focused component execution/lowering files under `src/native/`; late selection remains in `src/runtime/integrator.jl`; public conjunctions remain in `src/runtime/capabilities.jl`; MTK construction remains in `ext/PottsToolkitModelingToolkitExt.jl`. No public executable or per-cell `PottsSystem` copy is introduced. | Black-box global and per-cell fixtures compare serial and vectorized per-cell results against an independent small-system oracle across create/delete/divide/transition and checkpoint continuation. Tests cover zero/one/capacity live cells, partial final batches, kind transitions, callback/event/DAE/adaptive/shape rejections, allocation bounds after warmup, and failure atomicity. Benchmarks record compile-once behavior, memory by capacity/state width, and throughput by live density/batch width. | H4-B passes only after serial semantics are complete, vectorized CPU parity is demonstrated for the admitted per-cell subset, model size remains data rather than generated type topology, and all unsupported numerical/lifecycle combinations reject before native problem or solver execution. This freezes the batched execution contract consumed by Metal. |
| H4-C — real GPU and backend profiles | `pending` | Bounded real-Metal component execution for both global and per-cell scopes, using the compile-once fixed-shape device-total fixed-step subset; checkerboard CPM integration; device-resident lifecycle/component requests where admitted; complete negative dispositions for unsupported algorithms, scalars, callbacks, events, allocation, and vendors. | `ext/PottsToolkitMetalExt.jl`, `lib/CorePotts/src/backend_spi.jl`, the existing Core lifecycle/backend kernels, `test/backend_conformance/*`, `scripts/qualify_descriptor_metal.jl`, and `benchmark/backends/metal/runtests.jl`. CUDA/AMDGPU runners remain evidence environments only and cannot create public support without equivalent extensions and rows. | Target-Mac Metal witnesses cover global and per-cell correctness, lifecycle receipts, component pools, relationship/component request publication, checkpoint continuation, 2D and admitted 3D cases, device failure status, no scalar indexing, no host fallback, no hidden transfer, bounded synchronization, warmed allocations, memory, and throughput. CPU reference and Metal results use the same independent scientific oracle without claiming sequential/checkerboard trajectory identity. Missing Metal, CUDA, ROCm, adaptive, DAE, root-event, callback, dynamic-dispatch, unsupported-scalar, and capacity combinations have typed preflight rejections. | H4-C passes only when at least one exact real-GPU row for each global and per-cell scope is `ReplayQualified`, performance claims have measurements, and transfer/synchronization instrumentation proves the advertised device boundary. Compilation alone is never support. CUDA/ROCm remain unsupported unless they independently meet the same bar. |
| H4-D — fields and MethodOfLines | `pending` | Native prescribed fields; an honestly named built-in discrete-field component; explicit coordinate/boundary/topology semantics; CPU and applicable Metal field profiles; a separate MethodOfLines weak extension using `symbolic_discretize`, real upstream `mtkcompile`, standard problem construction, and an explicit checked coordinate-to-lattice grid map. | New field declaration/grid-map/runtime authority under `src/fields/`; migrate the Euler stencil from `src/operation_library/numerics.jl` behind the built-in discrete-field component; add `MethodOfLines` as a weak dependency and `ext/PottsToolkitMethodOfLinesExt.jl` rather than placing PDE dependencies in base. Native MTK ownership remains in the ModelingToolkit extension and the field component supplies only the cross-domain map/schedule. | Prescribed/discrete-field tests cover periodic/closed/frozen boundaries, dimensions, topology, units, interpolation/read/write phases, atomic CPM-field publication, checkpoint/SII/observations, CPU/Metal parity for advertised rows, and an independent stencil oracle. Integration constructs a real MethodOfLines discretization, runs `symbolic_discretize` then upstream structural compilation and a standard problem, proves every grid-map coordinate, and rejects name/shape coincidence, incompatible grids, unsupported events/solvers/backends, and hidden remeshing. | H4-D passes only after the old explicit diffusion behavior has an equivalence witness through the discrete-field component. The standalone kernel/spelling may then be removed if no other accepted witness owns it. MethodOfLines CPU support is promoted only for exact evidenced rows; GPU MethodOfLines remains explicitly unsupported unless separately qualified. |
| H4-E — SciML ensembles and Dagger disposition | `pending` | Complete whole-trajectory `EnsembleProblem` behavior for serial, threaded, and distributed execution; `prob_func`, `output_func`, reduction, retry, failure, cancellation, and deterministic replica/repeat identity; an evidence-based Dagger adopt-or-defer decision that cannot change runtime semantics. | Extend the existing authority in `src/runtime/{problem,solution}.jl` and `test/test_sciml_lifecycle_v2.jl`; add distributed clean-worker/load-order witnesses without introducing a second ensemble wrapper. Dagger evaluation lives in an isolated benchmark environment. Adoption, if justified, requires an optional extension; defer requires no package dependency. | Serial/threaded/distributed results agree per replica under addressed RNG and preserve replica/repeat through remake, checkpoint, retry, output, and reduction. Tests cover worker initialization, worker loss/error propagation, cancellation, nonserializable callbacks, nested unsupported profiles, and prove that ensemble execution neither changes per-cell batch identity nor implies GPU support. Dagger measurements compare representative independent trajectories and coarse islands against SciML/stdlib baselines and record overhead, scaling, memory, failure, and semantic fit. | H4-E passes with all three SciML ensemble lanes qualified and one measured Dagger decision. Dagger may own only optional coarse scheduling; it never owns MCS order, coupling visibility, lifecycle commit, RNG identity, or checkpoint meaning. A measured defer is a complete result. |
| H4-Q — gate qualification | `pending` | One exhaustive capability/support matrix and exact-candidate evidence for every advertised algorithm × backend/device × dimension/topology × scalar policy × component scope/family × lifecycle feature × checkpoint/replay × observation/event mode conjunction. Preserve all G5H-1–G5H-3 witnesses touched by the work. | `src/runtime/capabilities.jl`, `src/inspection.jl`, Core backend reports, root/integration/backend tests, qualification scripts, benchmark evidence, and this living control record. New stable public names must be the minimal author-facing set and join the authoritative API inventory; compatibility aliases and duplicate constructors are forbidden. | Full root/Core/Makie/integration suites; strict docs landing; fresh base/Core/extension orders; Aqua/ExplicitImports; all CPU/Metal conformance lanes; operation/static-evaluator/specialization checks; exact memory, allocation, synchronization, transfer, compile-time, checkpoint, and throughput records; stale-name/private-upstream scans; explicit negative tests for every unqualified row. | G5H-4 passes only on a clean exact commit with no unsupported public claim, silent fallback, unresolved touched-preservation row, or known in-scope correctness defect. G5H-5 then owns final-interface documentation, Wortel/Merks product programs, final performance comparison, and R2H-C preparation. |

### Minimum capability dispositions

Every row below must end G5H-4 as either an evidenced supported/experimental conjunction or an
explicit tested rejection. The required rows cannot be satisfied by combining evidence from
different algorithms, devices, component scopes, or replay classes.

| Profile family | Required G5H-4 disposition |
|:--|:--|
| Existing global native CPU | Preserve the G5H-3 exact fixed-step ODE row and rerun it after component-pool/capability changes; do not broaden DAE/event support by implication. |
| Per-cell serial CPU | Required functional and replay-qualified reference with full admitted lifecycle, observation, SII, and checkpoint behavior. |
| Per-cell vectorized CPU | Required separately identified functional and replay-qualified fixed-shape row, with parity and measured benefit relative to the serial component reference. |
| Global native Metal | Required bounded real-Metal row for the fixed-shape device-total fixed-step subset, or G5H-4 does not satisfy the global GPU target. |
| Per-cell native Metal | Required bounded real-Metal batched row with fixed capacity and lifecycle masks, or G5H-4 does not satisfy the per-cell GPU target. |
| Checkerboard CPU with components | Must be independently qualified or explicitly rejected for each component scope; sequential evidence cannot be reused as checkerboard evidence. |
| Built-in prescribed/discrete fields | Required CPU reference and applicable real-Metal row with explicit boundary/topology/grid semantics. The Euler stencil is a named component implementation, not a generic PDE solver. |
| MethodOfLines | Required exact CPU extension row using `symbolic_discretize`, upstream compilation, a standard problem, and a checked grid map. GPU, remeshing, unsupported PDE/event, and solver combinations reject unless independently qualified. |
| SciML trajectory ensembles | Serial, threaded, and distributed CPU lanes are required. Their inner trajectory must itself be an admitted profile; distributed or threaded execution does not imply component batching or GPU support. |
| CUDA and ROCm | Remain publicly unsupported until their own extensions pass the same correctness, replay, no-fallback, transfer, synchronization, and performance evidence as Metal. Vendor runner compilation is insufficient. |
| Dagger | Must end with a measured adopt-or-defer record. Adoption is optional and coarse-grained; deferral is nonblocking. |

### Cross-slice acceptance and preservation

- H4-A owns F06/F07 and PR02/PR06/PR09/PR11/PR24/PR29 for component state. H4-B/H4-C may
  optimize application of the receipt but may not reinterpret lifecycle identity, ordering, or
  publication.
- H4-B/H4-C own F08/F09/F13/F14 and PR04/PR17/PR22/PR24/PR28/PR30 for their exact CPU/GPU
  conjunctions. The sequential CPU oracle remains decisive for shared laws; stochastic algorithms
  retain distinct trajectory semantics.
- H4-D owns F17 and PR14/PR20/PR27, while preserving the field-related scientific witnesses in
  PR15/PR30. Grid identity joins scheduled-system, capability, checkpoint, and provenance
  fingerprints.
- H4-E owns F16/F17/F18 and PR10/PR12/PR24. Replica identifies a trajectory and repeat identifies
  its retry in every execution lane; worker or scheduler order never supplies semantic identity.
- H4-Q must close PR28's 2D/3D dispositions and every touched PR row as preserved, replaced by a
  passing witness, removed by an already accepted disposition, or explicitly left unsupported.
- Applicable correctness, replay, allocation, synchronization, transfer, and performance evidence
  is conjunctive. A fast row with missing semantics, a correct compile-only row, or a CPU fallback
  cannot be promoted.
- Performance thresholds and measurement fixtures are frozen before optimization for each slice;
  thresholds are not selected after seeing the optimized result. Evidence records exact commit,
  tree, Julia/package/device identity, commands, warmup, sample definition, and claim boundary.

### Intentional stable public-API delta from G5H-0

F11 adds exactly two PottsToolkit stable public names relative to the G5H-0 surface:
`CellIdentity` and `relationship_transaction!`. This `+2` is the minimal author-facing realization
of the already frozen F11 settled-host relationship contract. Neither name is a compatibility alias
or an alternate transaction authority. The exact inventory in `test/test_public_api_v2.jl` names
both additions; any further stable F11 spelling is drift and requires review.

## G5H-0 candidate evidence

All commands completed on the target Mac with Julia 1.12.1 on 2026-08-06.

| Obligation | Reproduction command or exact artifact | Exact result |
|:--|:--|:--|
| PottsToolkit full package suite | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=. --startup-file=no -e 'using Pkg; Pkg.test("PottsToolkit")'` | 1,989/1,989 passed in 35m54s. |
| CorePotts package suite | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=lib/CorePotts --startup-file=no -e 'using Pkg; Pkg.test("CorePotts")'` | 233/233 passed: 223 functional and 10 Aqua assertions. |
| MakiePotts package suite | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=lib/MakiePotts --startup-file=no -e 'using Pkg; Pkg.test("MakiePotts")'` | 501/501 passed. |
| Optional integration suite | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=integration --startup-file=no integration/runtests.jl` | 22/22 passed: 12 legacy MTK-assimilation, 4 ModelingToolkitStandardLibrary, 4 Unitful, and 2 load-order assertions. The first two groups preserve existing behavior only and do not qualify the G5H-3 native-island target. The ignored local environment resolved ModelingToolkit 11.37.1, ModelingToolkitBase 1.58.1, ModelingToolkitStandardLibrary 2.29.5, SciMLBase 3.39.1, SymbolicIndexingInterface 0.3.51, Symbolics 7.34.1, DynamicQuantities 1.13.0, and Unitful 1.28.0. |
| Documentation | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=docs --startup-file=no docs/make.jl`; `warnonly=false` is fixed in `docs/make.jl` | Strict four-page temporary manual passed; the exact local-link command below covered 208 active manual/authority Markdown files with zero missing targets. |
| Fresh package boundaries | The two exact loaded-module commands below; the CI platform command `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --startup-file=no -e 'using Pkg; Pkg.activate(; temp=true); Pkg.develop(path=pwd()); include("test/platform_smoke.jl")'` | PottsToolkit loaded without full ModelingToolkit or the retired package; CorePotts loaded without PottsToolkit, ModelingToolkitBase, ModelingToolkit, SciML, or Makie; the public platform smoke trajectory passed. |
| Inventory and static integrity | `git diff --check 3591eccd6820bf51c185cf631c75467114319332..9afcf6f1ec44cf84525d8b023c2d1b705560e365`; `shasum -a 256 src/PottsToolkit.jl lib/CorePotts/src/CorePotts.jl lib/MakiePotts/src/MakiePotts.jl`; exact path-set comparisons against the baseline tables | All 115 production source files, 58 package/integration test-support files, three vendor runners, six live qualification/benchmark tools, and seven historical checkers are partitioned. Public declarations are 299 unique PottsToolkit names (300 declarations), 479 CorePotts names, and 74 MakiePotts names with the baseline digests. |
| Retirement and environments | `diff -u <(git diff --name-only --diff-filter=D 3591eccd6820bf51c185cf631c75467114319332..9afcf6f1ec44cf84525d8b023c2d1b705560e365 \| sort) <(awk -F '\t' '!/^#/ && NF==3 {print $3}' design/hardening/g5h0-deletion-inventory.tsv \| sort)` plus retired-name `rg` scans over active code, projects, manifests, workflows, and docs | All 356 tracked deletions match the inventory; active surfaces contain no retired dependency or hook; stale application manifests were regenerated from surviving projects. |
| Recovery | `git cat-file -e 3591eccd6820bf51c185cf631c75467114319332^{commit}`; `shasum -a 256 '/Users/praneethmerugu/Documents/Jiang/CPM 1.6/ProcessBigraphs-retired-20260805.tar.gz'`; `tar -tzf '/Users/praneethmerugu/Documents/Jiang/CPM 1.6/ProcessBigraphs-retired-20260805.tar.gz' \| awk 'index($0,"./lib/ProcessBigraphs/")==1 {n++} END {print n+0}'` | Git recovers every tracked deletion. The archive checksum is `338d74d39aa46c2610f49bfc55cfb48ce60e86d12113b337d7d669af8a2007bd` and it contains 16,294 entries under `lib/ProcessBigraphs/`. |

The fresh loaded-module checks were:

```sh
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=. --startup-file=no -e 'using PottsToolkit; loaded = Set(pkgid.name for pkgid in keys(Base.loaded_modules)); @assert "ModelingToolkitBase" in loaded; @assert !("ModelingToolkit" in loaded); @assert !("ProcessBigraphs" in loaded); @assert :compile in names(PottsToolkit)'
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=lib/CorePotts --startup-file=no -e 'using CorePotts; loaded = Set(pkgid.name for pkgid in keys(Base.loaded_modules)); forbidden = Set(["PottsToolkit", "ModelingToolkitBase", "ModelingToolkit", "SciMLBase", "Makie", "MakiePotts", "ProcessBigraphs"]); @assert isempty(intersect(loaded, forbidden))'
```

The exact static checks, run from the repository root with reviewed candidate
`9afcf6f1ec44cf84525d8b023c2d1b705560e365` checked out, were:

```sh
test "$(git rev-parse HEAD)" = 9afcf6f1ec44cf84525d8b023c2d1b705560e365
git diff --check 3591eccd6820bf51c185cf631c75467114319332..9afcf6f1ec44cf84525d8b023c2d1b705560e365
diff -u <(git diff --name-only --diff-filter=D 3591eccd6820bf51c185cf631c75467114319332..9afcf6f1ec44cf84525d8b023c2d1b705560e365 | LC_ALL=C sort) <(awk -F '\t' '!/^#/ && NF==3 {print $3}' design/hardening/g5h0-deletion-inventory.tsv | LC_ALL=C sort)
awk -F '\t' '!/^#/ && NF==3 {print $3}' design/hardening/g5h0-deletion-inventory.tsv | while IFS= read -r file; do git cat-file -e "3591eccd6820bf51c185cf631c75467114319332:$file" && test ! -e "$file" || exit 1; done
shasum -a 256 src/PottsToolkit.jl lib/CorePotts/src/CorePotts.jl lib/MakiePotts/src/MakiePotts.jl
! rg -n -i 'processbigraphs|process[- ]bigraph|PottsToolkitProcessBigraphsExt|process_component|efcc6515-205e-41e3-b553-f38f05ad529c' .github src ext test integration lib/CorePotts lib/MakiePotts benchmark examples paper Project.toml docs/Project.toml docs/Manifest.toml docs/make.jl docs/README.md docs/src/index.md docs/src/concepts/architecture.md docs/src/concepts/runtime-boundary.md docs/src/concepts/capability-status.md README.md CONTRIBUTING.md --glob '*.jl' --glob '*.toml' --glob '*.yml' --glob '*.yaml' --glob '*.md'
test "$(find src ext lib/CorePotts/src lib/MakiePotts/src -type f -name '*.jl' | wc -l | tr -d ' ')" = 115
test "$(find test integration lib/CorePotts/test lib/MakiePotts/test -type f -name '*.jl' | wc -l | tr -d ' ')" = 58
test "$(find benchmark/backends -mindepth 2 -maxdepth 2 -type f -name 'runtests.jl' | wc -l | tr -d ' ')" = 3
test "$({ find scripts -maxdepth 1 -type f -name '*.jl'; find benchmark/src lib/MakiePotts/benchmark -type f -name '*.jl'; } | wc -l | tr -d ' ')" = 6
test "$(find scripts/archive/potts-history -type f -name '*.jl' | wc -l | tr -d ' ')" = 7
find src ext lib/CorePotts/src lib/MakiePotts/src -type f -name '*.jl' | LC_ALL=C sort
find test integration lib/CorePotts/test lib/MakiePotts/test -type f -name '*.jl' | LC_ALL=C sort
{ find benchmark/backends -mindepth 2 -maxdepth 2 -type f -name 'runtests.jl'; find scripts -maxdepth 1 -type f -name '*.jl'; find benchmark/src lib/MakiePotts/benchmark -type f -name '*.jl'; find scripts/archive/potts-history -type f -name '*.jl'; } | LC_ALL=C sort
find src ext lib/CorePotts/src lib/MakiePotts/src test integration lib/CorePotts/test lib/MakiePotts/test scripts benchmark/src benchmark/backends lib/MakiePotts/benchmark -type f -name '*.jl' -print | while IFS= read -r file; do count=$(awk 'NF && $1 !~ /^#/' "$file" | wc -l | tr -d ' '); test "$count" -le 1000 || printf '%s\t%s\n' "$count" "$file"; done | sort -nr
```

R2H-A compares the three sorted path-set outputs line-for-line against the source, test, and
tooling rows. The last command must emit exactly the nine-file responsibility table. Generated
captures under `benchmark/results/**` are intentionally outside that maintained-source universe.

Declaration count, uniqueness, row-count, and nonoverlapping range coverage use:

```sh
ruby <<'RUBY'
specs = {
  "src/PottsToolkit.jl" => [300, 299, [[74,84,43],[85,95,36],[96,104,46],[105,109,26],[110,124,49],[125,130,25],[131,135,14],[137,156,34],[157,166,27]]],
  "lib/CorePotts/src/CorePotts.jl" => [479, 479, [[33,39,15],[40,51,24],[52,52,2],[53,86,66],[87,94,14],[95,105,24],[106,134,57],[135,156,54],[157,177,43],[178,194,35],[195,208,26],[209,268,119]]],
  "lib/MakiePotts/src/MakiePotts.jl" => [74, 74, [[23,29,22],[31,35,18],[37,40,14],[42,46,13],[48,49,7]]],
}
specs.each do |path, spec|
  raw_expected, unique_expected, ranges = spec
  rows = []
  File.readlines(path).each_with_index do |line, index|
    match = line.match(/^\s*(?:export|public)\s+(.+?)\s*$/)
    rows << [index + 1, match[1].split(",").map(&:strip)] if match
  end
  names = rows.map(&:last).flatten
  abort("#{path}: raw") unless names.length == raw_expected
  abort("#{path}: unique") unless names.uniq.length == unique_expected
  covered = []
  ranges.each do |first, last, count|
    selected = rows.select { |line, _| (first..last).cover?(line) }
    abort("#{path}: range #{first}-#{last}") unless
      selected.inject(0) { |sum, pair| sum + pair.last.length } == count
    covered.concat(selected.map(&:first))
  end
  abort("#{path}: coverage") unless
    covered.sort == rows.map(&:first).sort && covered.uniq.length == covered.length
end
RUBY
```

The local-link traversal was:

```sh
ruby <<'RUBY'
require "uri"
all = IO.popen(["git", "ls-files", "-co", "--exclude-standard"], &:read)
    .lines.map(&:chomp).select { |path| path.end_with?(".md") && File.file?(path) }
active_docs = [
  "docs/src/index.md",
  "docs/src/concepts/architecture.md",
  "docs/src/concepts/runtime-boundary.md",
  "docs/src/concepts/capability-status.md",
]
files = all.select { |path| !path.start_with?("docs/src/") || active_docs.include?(path) }
missing = []
files.each do |path|
  text = File.read(path)
  targets = text.scan(/\]\(([^)\n]+)\)/).flatten
  targets.concat(text.scan(/^\s*\[[^\]]+\]:\s*(\S+)/).flatten)
  targets.each do |raw|
    target = raw.strip
    target = target[1...target.index(">")].to_s if target.start_with?("<") && target.include?(">")
    target = target.split(/\s+/, 2).first.to_s
    next if target.empty? || target.start_with?("#", "@", "http://", "https://", "mailto:", "data:", "git:", "/")
    target = target.split("#", 2).first.split("?", 2).first
    next if target.empty?
    target = URI::DEFAULT_PARSER.unescape(target)
    missing << [path, raw] unless File.exist?(File.expand_path(target, File.dirname(path)))
  end
end
abort(missing.inspect) unless files.length == 208 && missing.empty?
RUBY
```

All tracked TOMLs and local dependency paths were checked with:

```sh
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --startup-file=no <<'JULIA'
using TOML
tracked = filter(isfile, readlines(`git ls-files`));
tomls = filter(path -> endswith(path, ".toml"), tracked);
foreach(TOML.parsefile, tomls);
projects = filter(path -> basename(path) in ("Project.toml", "Manifest.toml"), tomls);
local_path_count = Ref(0);
function check_local_paths(value, base, count)
    if value isa AbstractDict
        for (key, child) in value
            if key == "path" && child isa AbstractString
                count[] += 1
                @assert ispath(normpath(joinpath(base, child)))
            end
            check_local_paths(child, base, count)
        end
    elseif value isa AbstractVector
        foreach(child -> check_local_paths(child, base, count), value)
    end
end;
foreach(path -> check_local_paths(
    TOML.parsefile(path), dirname(path), local_path_count
), projects);
@assert length(tomls) == 150
@assert length(projects) == 23
@assert local_path_count[] == 50
JULIA
```

## Control rules

- A gate becomes `passed` only when every normative exit condition has executable or static
  evidence and the exact checkpoint is recorded.
- A later regression marks the earliest owning gate `reopened` and invalidates downstream review
  clearance as specified by the contract.
- P2 findings may be carried through R2H-A or R2H-B only with an explicit owning gate. R2H-C closes
  every in-scope P2.
- Historical audit results qualify only their recorded repository state.
