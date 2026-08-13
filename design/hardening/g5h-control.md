# G5H implementation control

Status: G5H-0 through G5H-5, LocalWorksets LW-0 through LW-R2, and bounded
ED-R0 passed; bounded IC-R0 candidate under qualification; LW-5 held; G6 closed

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
| G5H-4 — dynamic components, fields, ensembles, profiles | `passed` | Exact implementation candidate `901faa546d0b21acca5dd56ecfd42f1ffae8dd64`, tree `e935bf919e59c86baa3f23a394d1eb06d497bc61`; H4-A through H4-E passed their implementation hold points, and H4-Q froze the exhaustive conjunction matrix with passing qualification evidence. |
| G5H-5 — product qualification and docs | `passed` | Corrected implementation candidate `06741e681cc1a5cacbbc4f56ac8a412401e4ee52`, tree `19a8ca73145412b0efa060845ae56fd929605a19`, removes the surviving `EquationProcess` surrogate, corrects the page count, records the owner-required Wortel/Merks substrate dispositions, and passes every affected qualification lane. |
| R2H-C — hardening exit review | `passed` | Final fresh rereview cleared implementation `06741e681cc1a5cacbbc4f56ac8a412401e4ee52`, tree `19a8ca73145412b0efa060845ae56fd929605a19`, against record `f3e527cf1bb1c083574fd682b6fd4576ebccf120`, tree `6b6701159a425de2c1c6832d935b75bb26b0d8a7`: P0=0, P1=0, P2=0, P3=0. |
| LocalWorksets LW-0 and LW-R0 | `passed` | CP-B1--CP-B3, complete CorePotts CPU, qualified real Metal, quantitative baselines, and the exact preservation review passed with P0=0, P1=0, P2=0, P3=0 and no dissent. Evidence: [LW-0 corrected CorePotts baseline](lw0-corrected-corepotts-baseline.md). |
| LocalWorksets LW-1 through LW-R1 | `passed` | The fresh exact-hash committee separately passed bounded LW-1 correctness, found no future-library obstruction, passed the bounded two-key conjunction and LW-3 Q01--Q10 on qualified CPU/Metal, and cleared LW-R1 with P0=0, P1=0, P2=0 and no dissent. Evidence: [implementation matrix](lw1-implementation-matrix.md), [bounded amendment](lw2-bounded-conjunctive-amendment.md), [LW-3 parity](lw3-localworksets-parity.md), and [LW-R1 review](lwr1-localworksets-review.md). |
| LocalWorksets LW-4 through LW-R2 | `passed` | Standalone extraction, bounded general mechanisms, consolidation, construction simplification, API reconciliation, CPU/real-Metal Freeze, and the five-role LW-R2 review passed. Product `ee395bd2f70d210fe98a0fb748e6530824c50671`, evidence digest `49002d9542b64c4c03388ab9bbe30632dfe20a64eac6c2e4bbcb89c50a486641`, and final seal commit `a65622a2` pass `--verify-final`. Authority: [sealed bundle](lw4-final-qualification-bundle/README.txt) and [post-LW-R1 roadmap](../../spec/localworksets-post-lwr1-roadmap.md). |
| ED-0/ED-1 engineering-debt hold | `passed` | The [three-package audit](ed0-ed1-engineering-debt-audit.md) found no safe production deletion and bounded the work. Exact product `da80a0ec1f6b52321973872066e02632124ec0f4` then passed complete PottsToolkit/CorePotts/LocalWorksets CPU suites, qualified integration/docs/real Metal, static seals, and focused ED-R0 review with P0=0, P1=0, P2=0. Evidence: [ED-R0 review](edr0-engineering-debt-review.md). |
| IC-0/IC-1 internal-complexity hold | `qualifying` | The bounded [IC-R0 record](icr0-internal-complexity-review.md) audits Julia abstractions, all extension-facing surfaces, active verification cost, and confirmed internal duplication without adding features or changing public contracts. Complete CPU/integration/docs/real-Metal evidence is required before clearance. |
| LocalWorksets LW-5 through LW-R3 | `held` | ED-R0 cleared engineering debt, but the owner inserted IC-R0 before source migration. After IC-R0 passes, begin with the existing representability inventory and one evidence-bearing pilot; domain semantics remain in PottsToolkit/CorePotts. |
| G6 owner decision | `blocked` | G6 requires LW-R2, LW-R3, disposition of every carried finding, and a separate explicit owner send-off. |

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
therefore clears and G5H-4 is unblocked. H4-A implementation began after the matrix was frozen.

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

## G5H-5 implementation qualification

The final manual is a curated replacement, not a translation of unpublished
`PottsModel` pages. Every remaining Markdown source is in `docs/make.jl`; the
obsolete model scripts and empty documentation directories are removed.
Complete Wortel and Merks programs use only the final public lifecycle and are
product/integration witnesses, not G7 paper-source reproduction claims.
Their successful execution is not by itself sufficient for H5-B: the owner
reopened the row for a mechanism-by-mechanism substrate audit. R2H-C must
verify that only CPM/lattice semantics remain Potts-native, that applicable
equation-defined biology uses ModelingToolkit, Catalyst, or MethodOfLines, and
that MTK composition owns connections internal to native symbolic systems.
Every retained PottsToolkit numerical component requires an exact limitation
or missing-adapter disposition and an explicit block/non-block decision.

| Lane | Exact result on the freeze worktree |
|:--|:--|
| PottsToolkit package | Corrected runner closure 411/411 and authoritative surface 2,189/2,189 passed in 17m38.2s. Aqua, ExplicitImports, retired invocation, private-upstream, dependency/weakdep, exact docs-set, fresh-process, scientific, and public API checks are included. |
| CorePotts package | 956/956 passed, including package-owned scientific, lifecycle, relationship, checkpoint, capability, allocation, API, and Aqua evidence. |
| Pinned MTK integration | 278/278 passed: retained MTK/MTKStandardLibrary, native runtime and batching, MethodOfLines, distributed ensembles, Unitful, optional loading, and CPU weak-extension orders 3/3. |
| MakiePotts | 503/503 passed, including Aqua, downstream/adversarial/allocation suites and both fresh load orders in the exact resolved test environment. |
| Real Metal | Complete runner exited zero. Fresh extension orders passed 2/2 and the native component block 37/37; all retained lifecycle, relationship, surface, replay, transfer, synchronization, rejection, and performance witnesses passed without fallback. |
| Strict manual | Doctests, executable expansion, cross-references, document checks, index population, and HTML rendering passed with `warnonly=false`; the exact Wortel and Merks files execute inside their pages. |
| Quantitative comparison | Exact G5H-0 source candidate and final worktree measured through one common 32 x 32 fixture. Four-phase first-use time is 0.877x baseline and median MCS time 0.934x; allocation and checkpoint regressions remain explicitly reported. Final component-pool and lifecycle absolute evidence is attached. |
| Static/repository integrity | Operation inventory 68; specialization growth 12/12; independent static evaluator exited zero; 251 tracked Julia files and 150 tracked TOMLs parsed; `git diff --check` passed; no maintained empty directory remains. Only explicit negative retirement assertions mention `EquationProcess`. |

The first formal R2H-C review inspected implementation candidate
`08b2bf0707810461c6f5a970fd2e1aee7ba81806`, tree
`cda132fbeec402a159ce6a9552a63d3a77d9764d`, read-only and returned `FAIL`
with P0=0, P1=1, P2=1, and P3=0. It found that `EquationProcess` survived as
an exported generic copied-equation surrogate despite PT01's accepted
replacement disposition, and that H5-A said twelve learn/concept pages when
the exact category set is ten learn/concept, two published-model, and three
API pages.
No checkpoint cleared. The earliest repair boundary is H4-D/G5H-5; a new
candidate and fresh independent rereview are mandatory.

The corrected worktree then passed root 411/411 + 2,189/2,189, CorePotts
956/956, pinned integration 278/278, MakiePotts 503/503, strict docs, the
complete real-Metal runner including 2/2 extension orders and 37/37 native
components, operation inventory 68, specialization growth 12/12, the static
evaluator, both direct product executions, and repository integrity. A fresh
advisory audit found no product-code substrate blocker: Wortel's activity is
intrinsically site/copy/MCS-owned, while Merks retains the bounded stencil
because the qualified MethodOfLines adapter is output-only and cannot accept
its moving-occupancy secretion forcing. The published pages record that
disposition; formal R2H-C must verify it on the exact corrected candidate.

The first corrected-candidate rereview inspected implementation candidate
`06741e681cc1a5cacbbc4f56ac8a412401e4ee52`, tree
`19a8ca73145412b0efa060845ae56fd929605a19`, and returned `FAIL` with P0=0,
P1=0, P2=1, and P3=0. It closed the `EquationProcess` finding, passed the
owner-added Wortel/Merks substrate audit, and confirmed MTK ownership of
native internal connections. Its sole finding was record-only: the corrected
H5-A category count omitted `docs/src/index.md`. The exact curated source set
is one home page, ten learn/concept pages, two published-model pages, and three
API pages, for 16 total. No checkpoint cleared; a fresh rereview is required.

The final fresh R2H-C rereview then inspected the same exact implementation
candidate against qualification record
`f3e527cf1bb1c083574fd682b6fd4576ebccf120`, tree
`6b6701159a425de2c1c6832d935b75bb26b0d8a7`, and returned `PASS` with P0=0,
P1=0, P2=0, and P3=0. It independently reproduced the complete 16-page
inventory, closure of `EquationProcess`, the 9/9 product suite, the
Wortel/Merks upstream-substrate disposition, MTK ownership of native internal
connections, PR01--PR30 closure, and the fail-closed capability boundary.
R2H-C is cleared. LocalWorksets subsequently passed LW-0 through LW-R1; its owner-authorized LW-4
and LW-5 successor route is now governed by the post-LW-R1 roadmap. G6 remains closed until that
route and a separate explicit owner authorization clear.

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
| H4-A — component identity and pools | `passed` | Extend the existing native declaration with a namespaced per-cell scope and explicit lifecycle policy; compile-once fixed-capacity structure-of-arrays pools keyed by Core slot and generation; active/generation/kind masks; initial component state; create, delete/remove, retire, divide/duplicate, and transition behavior; stale-generation rejection; one inactive candidate bank and atomic publication. Policies admit only explicit initialize, delete, copy, reset, transform, split, or reject behavior. | CorePotts continues to own the generic two-bank receipt seam; its sole addition is a copy-returning metadata snapshot needed by the logical checkpoint codec. Potts-owned policy/storage lives in `src/native/component_pools.jl`; coupled publication remains in the existing runtime/checkpoint/saved-state authorities; MTK symbolic lifecycle maps compile once in the ModelingToolkit extension. | Focused authoring passed 12/12, retained global authoring 16/16, API inventory 5/5, pool lifecycle/atomicity 32/32, Core receipt tests 38/38, and the authoritative fast surface 1,324/1,324. Pinned integration passed 221/221: its per-cell rows passed 15/15 and 65/65, including real create/transition/divide/remove/reuse receipts, symbolic reset/daughter lowering, zero-live publication, generation reuse, stale live/saved identity rejection, serial/batched parity, output/SII access, and exact checkpoint continuation. | Hold point passed on the active worktree. Lifecycle events consume fixed-capacity compiled policies; receipt staging and all solver work finish before assignment-only publication; failed staging/solve aborts both candidate domains; logical checkpoints retain inactive generations and all live lane state. The component pool layout is frozen for H4-B/H4-C. |
| H4-B — serial and vectorized CPU components | `passed` | One serial CPU semantic reference for global and per-cell components and one explicitly named vectorized/batched CPU mode for per-cell pools; multiple global islands share the existing simultaneous-island schedule rather than pretending to be a cell batch. The first admitted subset is fixed-shape fixed-step ODE, with deterministic lane assignment, observation/checkpoint parity, and clear separation from trajectory ensembles. | New focused component execution/lowering files under `src/native/`; late selection remains in `src/runtime/integrator.jl`; public conjunctions remain in `src/runtime/capabilities.jl`; MTK construction remains in `ext/PottsToolkitModelingToolkitExt.jl`. No public executable or per-cell `PottsSystem` copy is introduced. | `SerialNativeExecution()` and `BatchedNativeExecution(width)` are frozen late solve-profile dimensions. Pinned integration passed 257/257; the dedicated four-thread batched lane passed 26/26; the authoritative fast surface passed 1,330/1,330. Exact serial/batched parity, observed-value access, checkpoint continuation, live counts 0/1/2/4, partial/full fixed capacities, heterogeneous CellState inputs, deterministic lane order, DAE/event/callback/scalar preflight rejection, and distinct evidence/capability identities are covered. Quantitative width-8 and width-16 rows improve the 32-cell serial reference by 17.3%/16.8% throughput while reducing allocations 10.5%/11.2%; fixed-capacity pool memory remains linear in capacity and component width. | Hold point passed on the active worktree. Model size and live count remain data, not generated tuple/type topology. A rejected per-thread implementation and its measurements are retained in `g5h4-native-cpu-evidence.md`; the admitted flat fixed-shape solve is explicit rather than automatic. This freezes the CPU execution contract consumed by Metal. |
| H4-C — real GPU and backend profiles | `passed` | Bounded real-Metal component execution for both global and per-cell scopes, using the compile-once fixed-shape device-total fixed-step subset; checkerboard CPM integration; device-resident lifecycle/component requests where admitted; complete negative dispositions for unsupported algorithms, scalars, callbacks, events, allocation, and vendors. | `ext/PottsToolkitMetalExt.jl`, `ext/PottsToolkitMetalNativeExt.jl`, Core lifecycle/backend kernels, migrated `test/backend_conformance/*`, and `benchmark/backends/metal/*`. CUDA/AMDGPU runners remain non-authorizing evidence environments. | Real Apple M1 Pro execution passed 37/37 for global, per-cell, checked-field, closed-stack, composed-identity, and final negative native rows using DiffEqGPU 3.16.0, Metal 1.10.0, `GPUTsit5`, and `EnsembleGPUKernel(MetalBackend())`. Sequential-on-Metal and MethodOfLines-field profiles reject explicitly; unreviewed dependency stacks cannot manufacture evidence. The exact final Metal runner then passed every built-in checkerboard/lifecycle row and explicit external-code rejection. Six warmed per-cell MCS took 0.108327792 s and recorded exactly two synchronizations plus one control/snapshot/lifecycle transfer per boundary. | Hold point passed on the active worktree. `MetalNativeExecution(width)` is a distinct late profile; exact evidence is closed over algorithm, scalar, topology, mechanism authority, replay, device, dependency stack, and native evidence identity. One-lane solves are padded to prevent DiffEqGPU CPU fallback. CUDA/ROCm remain unsupported. Evidence: `g5h4-metal-native-evidence.md`. |
| H4-D — fields and MethodOfLines | `passed` | Checked native field outputs; an honestly named built-in discrete-field component; explicit coordinate/boundary/topology semantics; CPU and applicable Metal field profiles; a separate MethodOfLines weak extension using `symbolic_discretize`, real upstream `mtkcompile`, standard problem construction, and a checked coordinate-to-lattice grid map. | `NativeFieldOutput` extends the existing native declaration/runtime authority; `DiscreteFieldEuler` owns the legacy stencil; `ext/PottsToolkitMethodOfLinesExt.jl` owns the optional PDE adapter without adding PDE dependencies to base. | The CPU stencil oracle passes periodic, closed, and frozen-border topology plus exact restart. The real-Metal 4 x 4 native-field row passes publication, scalar-grid agreement, evidence identity, and restart. Pinned integration passes a real 4 x 4 MethodOfLines discretization through `symbolic_discretize`, upstream compilation, standard solve, checked coordinates, and shape rejection. | Hold point passed on the active worktree. The misleading `ExplicitDiffusion` spelling is retired. MethodOfLines is exact CPU-only evidence; GPU MethodOfLines, remeshing, incompatible grids, and unreviewed solver/event rows reject. |
| H4-E — SciML ensembles and Dagger disposition | `passed` | Complete whole-trajectory `EnsembleProblem` behavior for serial, threaded, and distributed execution; callback/reduction/retry/failure behavior and deterministic replica/repeat identity; an evidence-based Dagger adopt-or-defer decision. | The single authority remains `SciMLBase.EnsembleProblem(::PottsProblem)` in `src/runtime/solution.jl`; clean-worker distributed evidence is in `integration/test_ensemble_distributed.jl`; Dagger remains isolated under `benchmark/dagger/`. | Existing serial/threaded rows prove exact addressed parity and retry. Pinned integration passed distributed replica/repeat parity, reduction early stop, and worker exception propagation. The measured 8-trajectory comparison was 2.744703 s serial, 0.699338 s SciML threads, and 1.013743 s Dagger with exact final states. | Hold point passed with measured defer. Dagger adds no package dependency and may be used only as user-owned coarse orchestration. SciML remains authoritative for ensemble callbacks, reductions, identity, cancellation, and failures. Evidence: `g5h4-dagger-evidence.md`. |
| H4-Q — gate qualification | `passed` | One exhaustive capability/support matrix and exact-candidate evidence for every advertised algorithm × backend/device × dimension/topology × scalar policy × component scope/family × lifecycle feature × checkpoint/replay × observation/event mode conjunction. Preserve all G5H-1–G5H-3 witnesses touched by the work. | `src/runtime/capabilities.jl`, `src/inspection.jl`, Core backend reports, root/integration/backend tests, qualification scripts, benchmark evidence, `g5h4-capability-matrix.md`, and this living control record. New stable public names are limited to the inventoried author-facing set; compatibility aliases and duplicate constructors are forbidden. | CorePotts passed; the exact pinned integration suite passed 275/275 after final generic-field, checkerboard-CPU, and composed-evidence hardening; the complete root package surface passed 1,446/1,446, including its 404/404 runner-closure surface; MakiePotts passed 501/501; strict docs, 68-operation inventory, 12/12 specialization growth, the independent static evaluator, scientific witnesses, and the exact complete Metal runner with its 37/37 native block passed. Final parse/TOML/manifest/retired-name/empty-directory checks pass on the exact candidate. | Passed on exact implementation candidate `901faa546d0b21acca5dd56ecfd42f1ffae8dd64`, tree `e935bf919e59c86baa3f23a394d1eb06d497bc61`. G5H-5 now owns final-interface documentation, Wortel/Merks product programs, final performance comparison, and R2H-C preparation. |

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
