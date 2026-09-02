# G5H-0 baseline, architecture freeze, and preservation map

Date: 2026-08-06

Status: Review candidate; R2H-A pending

Authority: [Symbolic Potts V1 G5H Hardening Contract](../../spec/symbolic-potts-v1-hardening.md)

Decision basis: [Decision 0043](../../spec/decisions/0043-retire-processbigraphs.md) and
[Decision 0044](../../spec/decisions/0044-pre-g6-cohesion-and-mtk-hardening.md)

Baseline parent: `3591eccd6820bf51c185cf631c75467114319332`

Baseline parent tree: `26993838c79538377317f14b4abe7da40aee73d2`

This is the G5H-0 candidate freeze and preservation artifact. It becomes binding only when the
exact commit containing it passes R2H-A; a commit cannot contain its own hash. Current progress and
review clearance are recorded only in [`g5h-control.md`](g5h-control.md).

## Scope and reading rule

This freeze records what exists before consolidation, what must survive, what is deliberately
retired, and the architectural choices that later G5H gates implement. It is not evidence that a
future interface already exists.

Every current public declaration, major internal protocol, test family, and working feature
receives exactly one primary disposition:

- `keep`: preserve the public meaning and a black-box witness;
- `merge`: preserve the admitted behavior while removing duplicate implementation authorities;
- `replace`: preserve the stated outcome through the accepted replacement boundary;
- `remove`: delete a false, retired, or unsupported surface without a compatibility shim; or
- `defer`: retain only as experimental or future work, with no stable support claim.

For `keep`, `merge`, and `replace`, the successor witness named below must pass before the old
authority is removed. A later change to this freeze reopens R2H-A.

## Repository baseline

### Package ownership

| Package | Frozen responsibility | Forbidden responsibility |
|:--|:--|:--|
| `PottsToolkit` | Symbolic Potts authoring, completion, structural scheduling, native-component coupling, public SciML lifecycle, capability reporting, and late lowering into CorePotts | CPM kernel execution, a second checkpoint authority, or a general orchestration engine |
| `CorePotts` | MTK-free compiled runtime, algorithms, semantic RNG, bounded storage, trackers, lifecycle and relationships, settlement, logical snapshots, and backend contracts | ModelingToolkit/SciML authoring, native-system ownership, biological model policy, or visualization |
| `MakiePotts` | Render-data contracts, encodings, Makie recipes, recording, and interactive exploration over settled public observations | Simulation semantics, private runtime access, or ownership inference from display conventions |

The dependency direction is `MakiePotts -> PottsToolkit -> CorePotts`. CorePotts must remain
independently loadable and testable.

### Measured source and test footprint

Counts are physical Julia lines in the G5H-0 candidate tree.

| Area | Files | Lines |
|:--|--:|--:|
| `src/` | 63 | 18,016 |
| `ext/` | 3 | 128 |
| `lib/CorePotts/src/` | 37 | 18,295 |
| `lib/MakiePotts/src/` | 12 | 1,512 |
| Production total | 115 | 37,951 |
| `test/` | 35 | 14,551 |
| `integration/` | 5 | 126 |
| `lib/CorePotts/test/` | 2 | 1,426 |
| `lib/MakiePotts/test/` | 16 | 1,348 |
| Package/integration test total | 58 | 17,451 |
| `benchmark/backends/*/runtests.jl` | 3 | 207 |
| Test/qualification-runner total | 61 | 17,658 |

Within the 58 package/integration files, static source inspection finds 87 root test sets and 1,462
test macros, 4 integration test sets and 22 macros, 15 CorePotts test sets and 164 macros, and 15
MakiePotts test sets and 169 macros. The
imbalance is material: most CorePotts semantics are currently tested from the parent package and
must move to CorePotts ownership in G5H-1.

### Dependency inventory

| Environment | Direct dependencies | Disposition |
|:--|:--|:--|
| PottsToolkit | `CorePotts`, `DynamicQuantities`, `ModelingToolkitBase`, `SciMLBase`, `SHA`, `SymbolicIndexingInterface`, `Symbolics` | Keep the layer; reassess only unused dependencies after G5H-3 |
| PottsToolkit weak extensions | `Metal`, `ModelingToolkit`, `Unitful` | Keep weak; no unconditional vendor or full-MTK load |
| CorePotts | `AcceleratedKernels`, `Adapt`, `Atomix`, `KernelAbstractions`, `LinearAlgebra`, `SHA` | Keep MTK/SciML-free |
| MakiePotts | `Makie`, `PottsToolkit`, `PrecompileTools` | Keep |
| `integration/` | `DynamicQuantities`, `ModelingToolkit`, `ModelingToolkitBase`, `ModelingToolkitStandardLibrary`, `PottsToolkit`, `Symbolics`, `Test`, `Unitful` | Keep the upstream load-order and Unitful harness. The assimilation and StandardLibrary fixtures exercise the superseded surrogate bridge and are replacement targets in G5H-3, not qualification for F02/F03. |
| `docs/` | `CairoMakie`, `CorePotts`, `Documenter`, `MakiePotts`, `PottsToolkit` | Keep the strict temporary hardening manual; replace its content in G5H-5 after the final interface exists. |
| `benchmark/backends/metal/` | `CorePotts`, `Metal`, `ModelingToolkitBase`, `PottsToolkit`, `Symbolics`, `Test` | Preserve as the target-Mac hardware harness; requalify against the final capability row in G5H-4. |
| `benchmark/backends/cuda/` | `CUDA`, `CorePotts`, `ModelingToolkitBase`, `PottsToolkit`, `Symbolics`, `Test` | Quarantine as development evidence; it is not a public backend claim until its extension and G5H-4 profile qualify. |
| `benchmark/backends/amdgpu/` | `AMDGPU`, `CorePotts`, `ModelingToolkitBase`, `PottsToolkit`, `Symbolics`, `Test` | Quarantine as development evidence; it is not a public backend claim until its extension and G5H-4 profile qualify. |
| `examples/` | Potts/Core/Makie/SciML plus GLMakie, Metal, and support packages | Preserve as historical rewrite material, not current qualification; audit or replace every entry in G5H-5. |
| `examples/dashboards/` | Potts/Core/Makie/SciML plus dashboard support packages | Preserve as historical rewrite material; no release claim before G5H-5 visual and interface review. |
| `examples/notebooks/` | Potts/Core/Makie/SciML plus notebook/data support packages | Preserve as historical rewrite material; no release claim before G5H-5 executable review. |
| `paper/` | `CorePotts`, `PottsToolkit` | Preserve as reproduction material; rebind to the final public lifecycle in G5H-5. |
| `lib/MakiePotts/benchmark/` | `BenchmarkTools`, `MakiePotts`, `TOML` | Preserve the visualization benchmark harness; rebind thresholds and invocation to the final public observation path in G5H-5. |
| `lib/MakiePotts/test/backends/` | Potts/Core/Makie plus CairoMakie, GLMakie, WGLMakie, image IO, and KernelIntrinsics | Preserve as optional visual-backend QA; it does not alter MakiePotts semantic ownership and is requalified in G5H-5. |

The ignored local integration manifest used during G5H-0 resolved ModelingToolkit `11.37.1`; the
candidate pins only the `ModelingToolkit = "11"` compatibility range, so exact resolved versions
belong in the review evidence rather than this tree. The five formerly stale application/Makie
backend manifests were regenerated from their current projects with Julia 1.12.1; they now resolve
PottsToolkit/CorePotts/MakiePotts 0.2 path packages and contain no orphaned AlgebraicJulia stack.
Neither ProcessBigraphs, Mermaid, Vivarium, Dagger, Catalyst, nor MethodOfLines is an active
dependency. Catalyst and MethodOfLines may enter only as weak, separately tested adapters in their
owning gates. Dagger is deferred by F18 below.

### Known nonconforming baseline surfaces

G5H-0 inventories these surfaces; it does not mistake their current tests for the accepted design.
They must be replaced atomically at their owning gate, while their currently working outcomes are
covered by the preservation rows below.

| Surface | Why it is nonconforming | Required disposition |
|:--|:--|:--|
| `EquationComponent` assimilation and both MTK integration fixtures | Copy equations, unknowns, parameters, defaults, and metadata into a Potts surrogate | Remove the surrogate and replace with F03 native component islands in G5H-3 |
| Current `PottsSystem` child restrictions | Admit only the existing Potts-shaped child representation and reject the native heterogeneous system composition required by F03 | Replace the child/schedule boundary in G5H-3 |
| Public `compile`/`PottsExecutable` and early engine/backend specialization | Freeze runtime choices before problem construction and expose the intermediate artifact as the user lifecycle | Preserve current consumers until G5H-2 atomically replaces the complete problem/materialization spine |
| Direct `init`/`solve` wrappers over the frozen executable | Provide useful SciML-shaped behavior without a late algorithm/backend selection boundary | Preserve observable saving/SII/remake behavior, then replace with genuine SciML dispatch in G5H-2 |

## Exhaustive public-name disposition

The declaration ranges below are non-overlapping and cover every `export` or `public` declaration
in the three package modules at this baseline. The SHA-256 digests make the range partition
auditable:

| Declaration file | SHA-256 |
|:--|:--|
| `src/PottsToolkit.jl` | `87937678d476120702f00a097e21f686df719ec8d3ed0bb709734861abf7c082` |
| `lib/CorePotts/src/CorePotts.jl` | `0de18122dc7799f4be3a27148fb4244c4fc57591abab2f74a9c545d835935f5e` |
| `lib/MakiePotts/src/MakiePotts.jl` | `965d680731f746400b2a4acaaa171c01b8c1dd210ba01202888f2d91c821aab9` |

A named exception overrides its row default. There are 299 unique PottsToolkit declarations (300
raw declarations because `RelationshipBinding` is redundantly exported in PT02 and PT03), 479
unique CorePotts declarations, and 74 unique MakiePotts declarations. G5H-1 may remove that
duplicate spelling without observable API change.

### PottsToolkit — 299 unique names / 300 declarations

| ID | Declaration lines | Count | Default disposition | Exceptions and exact disposition | Witness rows |
|:--|:--|--:|:--|:--|:--|
| PT01 | `src/PottsToolkit.jl:74-84` | 43 | `keep` | Registry/traversal names are `merge` into one normalized source authority; `EquationProcess` is `replace` by either PR14's bounded discrete field or PR27's native component declaration, never by a generic copied-equation surrogate | PR01, PR21, PR22, PR27 |
| PT02 | `src/PottsToolkit.jl:85-95` | 36 | `keep` | `compile`, `PottsExecutable`, current engine/backend selector types, `PottsParameters`, `PottsCheckpoint`, and `checkpoint` are `replace` at the final lifecycle boundaries; `CUDABackend` and `ROCmBackend` are `remove` until real extensions qualify them | PR03–PR05, PR09–PR12, PR17–PR19, PR24, PR25 |
| PT03 | `src/PottsToolkit.jl:96-104` | 46 | `keep` | The repeated `RelationshipBinding` declaration is `merge`; `boundary_measure`, `neighbor_count`, `neighbor_sum`, `neighbor_mean`, and `neighbor_geomean` are `replace` with the explicit `boundary_site_count`, `neighbor_cells`, `neighbor_cell_count`, `neighbor_property_sum`, `neighbor_property_mean`, and `global_interface_measure` vocabulary; `contact_measure` retains its accepted meaning | PR02, PR07, PR08, PR20, PR21, PR28 |
| PT04 | `src/PottsToolkit.jl:105-109` | 26 | `keep` | `EquationStep` is `remove`; `Observe` is `replace` by the settled observation/save contract | PR07, PR09, PR10, PR21 |
| PT05 | `src/PottsToolkit.jl:110-124` | 49 | `keep` | Implementations are `merge` through one resolved lifecycle IR without removing admitted vocabulary; `Directed` is `remove` until directed storage and lifecycle conformance exist | PR06, PR07, PR21, PR29 |
| PT06 | `src/PottsToolkit.jl:125-130` | 25 | `keep` | `ExplicitDiffusion` is `replace` by an honestly named discrete-field component; `ExplicitEuler`, `Heun`, `RK4`, and `ObserveStage` are `remove` | PR14, PR15, PR20, PR21, PR28 |
| PT07 | `src/PottsToolkit.jl:131-135` | 14 | `keep` | `Capabilities`, `StoragePlan`, `Kernels`, and `LifecyclePlans` are `merge` into one schema/capability inspection authority; `EquationComponent` is `remove` | PR03, PR07, PR08, PR15, PR17, PR23, PR27, PR29 |
| PT08 | `src/PottsToolkit.jl:137-156` | 34 | `merge` | Necessary behavior moves behind the explicit compiler SPI; no name is stable end-user API by declaration alone | PR05, PR06, PR08, PR20, PR22 |
| PT09 | `src/PottsToolkit.jl:157-166` | 27 | `merge` | Diagnostics and unit conversions are `keep`; `ExecutableFingerprint` and `executable_fingerprint` are `replace` by a private execution-profile fingerprint while public checkpoint/provenance identities remain distinct; `stage_external_inputs!` is `replace` by typed component IO | PR05, PR10, PR13, PR17, PR18, PR23–PR25 |

The currently exported `compile` generic is a live compatibility debt, not the accepted public
lifecycle. G5H-2 replaces all callers and removes that export and user entry point in the same
change that installs late private materialization; private lowering may use a differently scoped
implementation detail.

### CorePotts — 479 names

CorePotts currently marks its implementation graph `public` wholesale. The row dispositions cover
every name, but they do not promote those names to end-user stability.

| ID | Declaration lines | Count | Disposition | Required destination | Witness rows |
|:--|:--|--:|:--|:--|:--|
| CP01 | `lib/CorePotts/src/CorePotts.jl:33-39` | 15 | `merge` | Algorithm/backend implementation behind `BackendSPI`; preserve checkerboard behavior | PR03, PR04, PR17 |
| CP02 | `lib/CorePotts/src/CorePotts.jl:40-51` | 24 | `merge` | Settlement runtime; retain one operational receipt and explicit backend SPI | PR04, PR06, PR09, PR17, PR24 |
| CP03 | `lib/CorePotts/src/CorePotts.jl:52` | 2 | `merge` | `CompiledPottsProgram` remains compiler SPI; relationship schema joins the schema authority | PR05, PR07, PR22 |
| CP04 | `lib/CorePotts/src/CorePotts.jl:53-86` | 66 | `merge` | Tracker protocol/implementation behind compiler and backend SPIs | PR08, PR11, PR22 |
| CP05 | `lib/CorePotts/src/CorePotts.jl:87-94` | 14 | `keep` | Relationship transaction semantics; helpers may move behind runtime/backend SPIs | PR07, PR09, PR11 |
| CP06 | `lib/CorePotts/src/CorePotts.jl:95-105` | 24 | `merge` | Narrow runtime API, one materializer, one logical snapshot/checkpoint authority | PR02–PR05, PR09, PR11, PR17, PR19, PR24 |
| CP07 | `lib/CorePotts/src/CorePotts.jl:106-134` | 57 | `merge` | Kernel-safe evaluator compiler/backend SPI | PR02, PR06, PR07, PR20–PR22, PR29 |
| CP08 | `lib/CorePotts/src/CorePotts.jl:135-156` | 54 | `merge` | One state/output/workspace schema and checkpoint codec | PR05, PR08, PR09, PR11, PR22, PR29 |
| CP09 | `lib/CorePotts/src/CorePotts.jl:157-177` | 43 | `merge` | Admitted descriptor/footprint compiler SPI; private implementation otherwise | PR05, PR20, PR22, PR23, PR28 |
| CP10 | `lib/CorePotts/src/CorePotts.jl:178-194` | 35 | `merge` | Proposal/Hamiltonian compiler and backend SPIs | PR03, PR07, PR08, PR20, PR22, PR29 |
| CP11 | `lib/CorePotts/src/CorePotts.jl:195-208` | 26 | `merge` | One stage IR and one acceptance authority | PR03, PR04, PR07, PR09, PR21, PR22, PR24, PR29 |
| CP12 | `lib/CorePotts/src/CorePotts.jl:209-268` | 119 | `merge` | One lifecycle IR, workspace, status, receipt, and execution authority | PR02, PR06–PR09, PR11, PR19, PR22, PR24, PR29 |

G5H-1 must leave package-level `public` declarations only for a narrow runtime boundary:
`ProgramInitialState`, `ProgramSnapshot`, `ProgramRuntime`, `ProgramFailureReport`,
`program_failed`, `program_failure_report`, `ProgramSettlementReceipt`, `initialize_program`,
`program_snapshot`, `advance_mcs!`, `update_program_parameters!`, `program_execution_report`,
`program_capability_report`, `ProgramCheckpoint`, `program_checkpoint`, and
`restore_program_checkpoint`, plus the new generation-safe identity and lifecycle receipt types.
`CompiledPottsProgram` and lowering inputs belong to `CompilerSPI`; device adaptation, queuing, and
kernel launch belong to `BackendSPI`. G5H-1 may narrow these sets further but may not expand stable
package-level API without reopening R2H-A.

### MakiePotts — 74 names

| ID | Declaration lines | Count | Disposition | Qualification | Witness rows |
|:--|:--|--:|:--|:--|:--|
| MP01 | `lib/MakiePotts/src/MakiePotts.jl:23-29` | 22 | `keep` | Render-frame conformance against final settled observations | PR16 |
| MP02 | `lib/MakiePotts/src/MakiePotts.jl:31-35` | 18 | `keep` | Typed extents, channels, requests, and materialization | PR16 |
| MP03 | `lib/MakiePotts/src/MakiePotts.jl:37-40` | 14 | `keep` | Encoding contract | PR16 |
| MP04 | `lib/MakiePotts/src/MakiePotts.jl:42-46` | 13 | `keep` | Recipes, legend, inspection, and recording | PR16, PR25 |
| MP05 | `lib/MakiePotts/src/MakiePotts.jl:48-49` | 7 | `defer` | Retain explorer/rerun behavior as experimental through G5H-5; no stable promotion at G5H-0 | PR26 |

## Feature disposition and preservation witnesses

| ID | Current strength | Disposition | Current evidence | Required successor witness and owning gate |
|:--|:--|:--|:--|:--|
| PR01 | Functional symbolic Potts DSL, source locations, hierarchy, composition, completion | `merge` | `src/systems.jl`; `test/test_system_contract.jl`, `test/test_statements_and_traversal.jl`, `test/test_completion_and_diagnostics.jl` | Compact black-box `@named` construction, `compose`/`extend`, completion idempotence, namespaces, provenance, and source-located errors — G5H-2 |
| PR02 | Counter-based semantic RNG and replica/repeat identity | `keep` | `lib/CorePotts/src/rng/semantic.jl`; raw-word and replay tests in `test/test_sequential_reference.jl` and `test/test_runtime_solution_sii.jl` | Core-owned known-answer vectors plus serial/threaded/distributed replica, repeat, checkpoint continuation, and retry witness — G5H-1/G5H-4 |
| PR03 | Sequential CPU scientific reference | `keep` | Independent three-site transition matrix, detailed-balance, symmetry, energy, and tracker oracles in `test/test_sequential_reference.jl` and descriptor/tracker tests | Core-owned analytic oracle plus final public scheduled-system-to-solution witness — G5H-1/G5H-2 |
| PR04 | Checkerboard coloring, claims, deterministic commit, and settlement | `keep` | Core program tests and `test/backend_conformance/checkerboard_execution.jl` | CPU parity/invariant tests and exact real-Metal no-fallback profile; retain distinct stochastic identity — G5H-1/G5H-4 |
| PR05 | Owned, logically immutable compiled plans and fingerprints | `keep` | `CompiledPottsProgram`, defensive-copy/reuse and fingerprint tests | Construction ownership, mutation exclusion, deterministic fingerprint, reuse, and adapted-copy tests through compiler SPI; no public executable stage — G5H-1/G5H-2 |
| PR06 | Generation-stamped create, delete, retire, transition, and divide transactions | `merge` | `test/test_lifecycle_sequential.jl` and lifecycle backend conformance | Core-owned generation and atomic-staging suite, the exact F06 receipt variants, bulk component-state application, stale-generation rejection, and checkpoint continuation — G5H-1/G5H-4 |
| PR07 | Relationship transactions and bounded stores | `keep` | Core relationship suite, `test/test_relationship_runtime.jl`, relationship backend conformance | Public create/remove/retune/filter/overflow/checkpoint witness and measured integrity/scaling — G5H-1 |
| PR08 | Tracker deltas and independent recomputation | `keep` | Core tracker tests, `test/test_surface_tracker.jl`, GPU surface conformance | Independent equality after accepted-copy, relationship, and lifecycle commits and again at every completed-MCS publication/checkpoint; queued settlement cannot weaken the invariant — G5H-1/G5H-4 |
| PR09 | Failure atomicity and settled publication | `merge` | Lifecycle failure tests and settlement paths | Receipt/counter black-box tests for callback, observation, component exchange, checkpoint, and index mutation failures — G5H-1/G5H-3 |
| PR10 | SII, remake, saving, observation, and solution behavior | `replace` | `test/test_runtime_solution_sii.jl`, `test/test_initial_problem_remake.jl`, Wortel save tests | Scheduled `PottsSystem` remains symbolic authority through problem/remake/init/solve, saved and unsaved indexing, termination, and settled observations — G5H-2 |
| PR11 | Exact continuation checkpoint intent | `merge` | Core program checkpoint and root checkpoint tests | One logical codec and explicit replay class covering every reachable settled state, relationships, trackers, generations, replica/repeat, native components, and failure rejection — G5H-1/G5H-3 |
| PR12 | SciML ensemble serial/thread behavior | `keep` | `test/test_runtime_solution_sii.jl` | `prob_func`, `output_func`, reduction, serial/threaded/distributed replay and failure witnesses; distinct from per-cell batching — G5H-4 |
| PR13 | External staged-input mechanism | `replace` | `stage_external_inputs!` exists and `ExternalIO()` is inspectable, but no live test calls the staging function after retired bridge removal | Typed native-component IO with a new black-box atomic CPM/component publication and checkpoint/restart witness — G5H-3 |
| PR14 | Explicit lattice diffusion stencil | `replace` | `src/operation_library/numerics.jl` | Honestly named built-in discrete-field component with CPU/GPU profile; never claimed as generic ODE/PDE solving — G5H-4 |
| PR15 | Wortel, Merks, and focal scientific fixtures | `replace` | Root fixture tests | Preserve admitted scientific outcomes through final black-box authoring; executable Wortel and Merks serial docs on the target Mac — G5H-2/G5H-5 |
| PR16 | Makie frame/request/channel/encoding/recipe boundary | `keep` | MakiePotts semantic and downstream conformance tests | Consume only final public host observations; cover named channels, multiple media, generation reuse, and settled GPU-to-host frames — G5H-5 |
| PR17 | MTK-free Core and no-fallback backend reporting | `merge` | Dependency boundary, compile coverage, Metal extension, vendor harnesses | Structured conjunction capability report, unsupported preflight, no scalar indexing/hidden transfer/fallback, and independent Core load/test — G5H-1/G5H-4 |
| PR18 | Reference units, Unitful conversion, and runtime parameter semantics | `keep` | `test/test_units_and_parameters.jl`, `integration/test_unitful_extension.jl`, `ext/PottsToolkitUnitfulExt.jl` | Unit inference, dimension errors, reference conversion, parameter update/remake, and weak-extension load-order witnesses — G5H-2/G5H-3 |
| PR19 | Initial layouts, cell/medium placement, procedural placement, and initialization identity | `keep` | `src/runtime/initial_state.jl`, `test/test_initial_problem_remake.jl`, Core initialization RNG tests | Deterministic validation and initialization for explicit and procedural layouts, with replica/repeat identity and generation-safe state — G5H-2 |
| PR20 | Topology, boundaries, neighborhoods, bindings, fields, and spatial queries | `merge` | Host/compiler spatial analysis, query operations, surface/descriptor tests | Exact accepted query vocabulary, periodic/closed/frozen semantics, binding validity, field maps, and independent spatial oracle across admitted profiles — G5H-1/G5H-2/G5H-4 |
| PR21 | Typed statements, effects, phases, schedules, and distributions | `keep` | Statement/symbolic source plus traversal, sequential, lifecycle, and relationship tests | Every admitted vocabulary family constructs, completes, lowers, diagnoses invalid use, and executes through a black-box witness; removed spellings fail clearly — G5H-1/G5H-2 |
| PR22 | Open registered-operation/descriptor/evaluator compiler SPI | `merge` | Compiler fixtures; descriptor, footprint, specialization, and backend-boundary tests | One documented SPI with external fixture conformance, closed device lowering, specialization bounds, and no private cross-package reach — G5H-1 |
| PR23 | Diagnostics, inspection, manifests, identities, and capability reports | `merge` | Completion diagnostics, compilation/inspection tests, Core reports | One schema family with source-located diagnostics and distinct semantic, execution-profile, and checkpoint/provenance identities — G5H-1/G5H-2 |
| PR24 | Queued execution, settlement consumers, and runtime mutation boundaries | `merge` | Asynchronous lifecycle testset, Core barrier tests, parameter/index mutation tests | Submit/settle/cancel/fail semantics for every consumer, typed receipts, synchronization evidence, and mutation only at admitted boundaries — G5H-1/G5H-4 |
| PR25 | Package quality, fresh-process loading, weak-extension order, platform smoke, and precompile | `keep` | Aqua/ExplicitImports tests, platform smoke, optional-extension integration, package precompile files | Fresh isolated base/Core/Makie loads, all extension orders, supported platform CI, and reproducible active environments — G5H-5 |
| PR26 | Makie explorer and rerun controller | `defer` | `lib/MakiePotts/src/explorer.jl`; package-level exercise is limited | Retain experimental only; either qualify cancellation/error/rerun ownership through public problem/solution APIs in G5H-5 or remove from the stable surface |
| PR27 | ModelingToolkit structural compilation and native component islands | `replace` | Current `EquationComponent` assimilation and MTK/MTKStandardLibrary integration tests are explicitly superseded evidence | Base-package `ModelingToolkitBase.mtkcompile(::PottsSystem)` for pure Potts in G5H-2; full-MTK weak extension for native islands, MTKStandardLibrary, and explicit Catalyst conversion in G5H-3; MethodOfLines remains PR14/G5H-4 |
| PR28 | Two- and three-dimensional stable scientific behavior | `replace` | Much lowering is rank-generic and Makie frames cover 3D, but no runtime test constructs a 3D lattice; elongation and lifecycle geometry contain narrower paths | Add dimension/topology to capability admission; every stable family passes 2D and 3D CPU plus applicable GPU witnesses, or carries an explicit accepted narrower row — G5H-1/G5H-4 |
| PR29 | Auxiliary state and fluctuating pressure/tension mechanics | `merge` | Generic `AuxiliaryState` storage/checkpoint/lifecycle substrate exists; no named fluctuating-pressure/tension implementation or live test exists | Preserve generic substrate; add separately named equilibrium/mechanical component semantics, lifecycle, RNG, checkpoint, CPU, and applicable GPU witnesses without false equilibrium claims — G5H-3/G5H-4 |
| PR30 | Scientific operation families: volume, contact, elongation, chemotaxis, connectivity, activity, and relationship energy/constraints | `keep` | `src/operation_library/scientific.jl`; sequential, tracker, relationship, Wortel, Merks, and focal tests | Independent energy/effect oracle and black-box authoring/execution witnesses for each family across every admitted dimensional/backend profile — G5H-1/G5H-2/G5H-4 |

Private-field compiler assertions are not preservation witnesses by themselves. Existing tests that
enter `PottsToolkit._...`, `CorePotts._...`, or `.core_program` must either move to the owning
package/SPI or be replaced by a black-box row above.

## Exhaustive source and internal-protocol inventory

The path sets below partition all 115 production Julia files. A row disposition applies to every
file in its set; deleting or moving one requires the named PR witness. README files remain
subordinate explanation, never a second protocol authority.

| ID | Exact source set | Primary disposition and witnesses |
|:--|:--|:--|
| PT-S00 | `src/PottsToolkit.jl`, `src/precompile.jl` | `merge`; PR25 |
| PT-S01 | `src/statements/*.jl`, `src/symbolics/*.jl`, `src/systems.jl` | `merge`; PR01, PR06, PR07, PR19–PR22, PR27, PR30 |
| PT-S02 | `src/completion/*.jl` | `merge`; PR01, PR05, PR06, PR18, PR20, PR23 |
| PT-S03 | `src/compiler/host/*.jl` | `merge`; PR05, PR06, PR08, PR20, PR22, PR23, PR28 |
| PT-S04 | `src/operation_library/*.jl` | `merge`; PR03, PR07, PR08, PR14, PR20–PR22, PR29, PR30 |
| PT-S05 | `src/compiler/execution/*.jl`, `src/compiler/compile.jl` | `replace` public artifact boundary while preserving behavior; PR05, PR07, PR10, PR13, PR17, PR23, PR24, PR27 |
| PT-S06 | `src/compiler/lowering/*.jl` | `merge`; PR03, PR05–PR09, PR11, PR18, PR20, PR22, PR28–PR30 |
| PT-S07 | `src/runtime/*.jl` | `replace` lifecycle boundary while preserving outcomes; PR02, PR09–PR13, PR18, PR19, PR24 |
| PT-S08 | `src/inspection.jl` | `merge`; PR23 |
| PT-X01 | `ext/PottsToolkitMetalExt.jl` | `keep` as weak extension; PR04, PR17, PR25 |
| PT-X02 | `ext/PottsToolkitModelingToolkitExt.jl` | `replace` copied assimilation with native islands; PR27 |
| PT-X03 | `ext/PottsToolkitUnitfulExt.jl` | `keep` as weak extension; PR18, PR25 |
| CP-S00 | `lib/CorePotts/src/CorePotts.jl`, `lib/CorePotts/src/program/v1.jl` | `merge` module/ownership aggregation; PR25 and all Core rows |
| CP-S01 | `lib/CorePotts/src/rng/*.jl`, `lib/CorePotts/src/execution/program_rng.jl` | `keep`; PR02 |
| CP-S02 | `lib/CorePotts/src/execution/{static_evaluator,storage_schema,storage_runtime,descriptor_protocol,domain_resources,descriptor_plan}.jl`, `lib/CorePotts/src/program/types.jl` | `merge` into runtime/compiler/backend SPIs; PR05, PR11, PR17, PR20, PR22, PR23 |
| CP-S03 | `lib/CorePotts/src/execution/tracker_plan.jl` | `merge`; PR08, PR11, PR22 |
| CP-S04 | `lib/CorePotts/src/program/checkerboard_plan.jl`, `lib/CorePotts/src/execution/{checkerboard_program,checkerboard_kernels}.jl` | `keep` behavior and consolidate protocol; PR04, PR09, PR17, PR24 |
| CP-S05 | `lib/CorePotts/src/program/relationships.jl` | `keep` behavior and narrow API; PR07, PR09, PR11 |
| CP-S06 | `lib/CorePotts/src/execution/{stage_plan,stage_runtime,proposal_context,hamiltonian_runtime,sequential_program}.jl` | `merge`; PR03, PR04, PR07–PR09, PR20–PR22, PR29, PR30 |
| CP-S07 | `lib/CorePotts/src/execution/lifecycle_*.jl` | `merge` into one lifecycle transaction protocol; PR02, PR06–PR09, PR11, PR17, PR22, PR24, PR29 |
| CP-S08 | `lib/CorePotts/src/program/runtime.jl`, `lib/CorePotts/src/execution/program_settlement.jl` | `merge`; PR02, PR09, PR11, PR17, PR24 |
| MP-S00 | `lib/MakiePotts/src/{MakiePotts,errors,requests,frames,encodings,adapters,recipes,inspection,recording,public_api_docs,precompile}.jl` | `keep` public-observation visualization boundary; PR16, PR25 |
| MP-S01 | `lib/MakiePotts/src/explorer.jl` | `defer` as experimental; PR26 |

The major internal protocols are separately dispositioned so a file move cannot hide competing
semantic authorities.

| ID | Protocol | Current owners | Disposition / witness |
|:--|:--|:--|:--|
| IP01 | Statement/source identity, registry, traversal | statements, systems, completion, source graph | `merge`; PR01, PR22 |
| IP02 | Operations, bindings, distributions, unit inference | symbolics, operation library, parameter lowering | `merge`; PR02, PR18, PR20, PR21 |
| IP03 | Completion, qualified IR, fingerprints, lifecycle resolution | completion | `merge`; PR01, PR05, PR06, PR23 |
| IP04 | Normalization, closure, footprints, host analysis | compiler host | `merge`; PR20, PR22 |
| IP05 | Descriptor/evaluator compiler SPI | Potts lowering and Core evaluator/descriptor files | `merge`; PR05, PR22 |
| IP06 | Storage schemas, banks, logical codecs | lowering and Core storage | `merge`; PR05, PR11, PR22, PR29 |
| IP07 | Tracker protocol | Potts lowering and Core tracker plan | `keep` invariant, `merge` implementation; PR08 |
| IP08 | Proposal, Hamiltonian, and acceptance | operation library and Core executors | `merge`; PR03, PR04, PR20, PR22, PR30 |
| IP09 | Stage, effect, and relationship requests | Potts relationship effects and Core stages/relationships | `merge`; PR07, PR09, PR21, PR22 |
| IP10 | Lifecycle transaction/status/backend protocol | completion/lowering and Core lifecycle files | `merge`; PR06, PR07, PR09, PR11, PR22, PR24, PR29 |
| IP11 | Semantic RNG | Core RNG | `keep`; PR02 |
| IP12 | Checkerboard scheduling and queued settlement | Core checkerboard/settlement, Metal extension | `keep` behavior, `merge` protocol; PR04, PR09, PR17, PR24 |
| IP13 | SciML runtime, SII, ensemble, checkpoint | root runtime | `replace` lifecycle, preserve outcomes; PR10–PR12, PR19, PR24 |
| IP14 | External IO and native MTK components | manifests/stages/MTK extension | `replace`; PR13, PR27 |
| IP15 | Inspection, capability, identities, manifests | root inspection/manifests and Core reports | `merge`; PR17, PR23 |
| IP16 | Initialization and procedural placement | root initial state | `keep`; PR19 |
| IP17 | Unitful boundary | Unitful extension | `keep`; PR18, PR25 |
| IP18 | Visualization frames, requests, encodings, adapters, recipes | MakiePotts | `keep`; PR16 |
| IP19 | Explorer/rerun control | MakiePotts explorer | `defer`; PR26 |
| IP20 | Package loading, weak extensions, precompile | modules, extensions, CI | `keep`; PR25 |

## Exhaustive test-family inventory

These rows partition all 58 surviving package/integration Julia test/support files plus the three
manual vendor runners, for 61 files total. “Manual” means the file exists but is not invoked by
normal `Pkg.test`; it cannot qualify a support claim until its gate wires a lane.

| ID | Exact test/support set | Disposition and witness |
|:--|:--|:--|
| PT-T00 | `test/{setup,runtests,platform_smoke}.jl`, `test/fast/runtests.jl` | `merge` runner/support; PR25. Platform smoke keeps the current public lifecycle until G5H-2 replaces it atomically. |
| PT-T01 | `test/test_system_contract.jl`, `test/test_statements_and_traversal.jl`, `test/test_completion_and_diagnostics.jl` | `keep` behavior; PR01, PR21, PR23 |
| PT-T02 | `test/test_host_compiler_facts.jl`, `test/test_descriptor_compiler.jl`, `test/test_compiler_boundary_repairs.jl`, `test/test_architecture_freeze.jl`, `test/test_lifecycle_compiler.jl` | Move Core laws/narrow SPI assertions to owners, retain black-box compiler behavior; PR05, PR06, PR20, PR22, PR23 |
| PT-T03 | `test/test_sequential_reference.jl` | Move Core law oracles to Core, retain public witness; PR02, PR03, PR07, PR08, PR22, PR30 |
| PT-T04 | `test/test_relationship_runtime.jl` | Move runtime law to Core and retain public authoring witness; PR07 |
| PT-T05 | `test/test_surface_tracker.jl` | Move tracker law to Core and retain public authoring witness; PR08, PR20, PR22 |
| PT-T06 | `test/test_lifecycle_sequential.jl` | Move transaction laws to Core and retain public lifecycle authoring witness; PR06, PR07, PR09, PR11, PR21, PR22, PR29 |
| PT-T07 | `test/test_units_and_parameters.jl` | `keep`; PR18, PR24 |
| PT-T08 | `test/test_compilation_and_inspection.jl` | Replace executable-bound assertions with final compiler/inspection boundary; PR05, PR13, PR17, PR22–PR24 |
| PT-T09 | `test/test_initial_problem_remake.jl` | `keep` outcomes through new lifecycle; PR02, PR10, PR19 |
| PT-T10 | `test/test_runtime_solution_sii.jl` | `keep` outcomes through genuine SciML lifecycle; PR02, PR10, PR12, PR24 |
| PT-T11 | `test/test_checkpoint.jl` | Merge codec/layer duplication and preserve continuation; PR02, PR05, PR11 |
| PT-T12 | `test/test_{wortel,merks,focal}_fixture.jl` | Replace private/executable setup with final black-box programs, preserve scientific outcomes; PR14, PR15, PR20, PR27, PR30 |
| PT-T13 | `test/test_package_quality.jl` | `keep`; PR25 |
| PT-T14 | `test/backend_conformance/{descriptor_boundary,checkerboard_execution,relationship_execution,surface_execution,lifecycle_execution,lifecycle_policy_execution}.jl` | Move Core laws to Core; retain backend instantiations. Lifecycle-policy is currently Metal-runner-only. PR04, PR06–PR09, PR17, PR22, PR24 |
| PT-T15 | `test/fixtures/{DescriptorSpecializationFixtures,ExternalSurfaceOperationFixture,LifecycleOperationFixtures,NeutralExternalTerms}.jl` | Retain as compiler-SPI conformance fixtures; PR03, PR06–PR08, PR22 |
| CP-T00 | `lib/CorePotts/test/runtests.jl` | `keep` runner/Aqua; PR25 |
| CP-T01 | `lib/CorePotts/test/test_program_v1.jl` | Split its fourteen RNG, checkerboard, tracker, checkpoint, interface, arbitration, barrier, relationship, initialization, descriptor, storage-bank, and specialization families without weakening them; PR02–PR11, PR17, PR19, PR22, PR24 |
| MP-T00 | `lib/MakiePotts/test/{runtests,downstream_fixture,test_downstream_conformance,test_adversarial,allocation_fixture,test_allocations}.jl` | `keep` active package tests; PR16, PR25 |
| MP-T01 | `lib/MakiePotts/test/{measure_allocations,clean_install_smoke}.jl` | Manual; wire or classify in G5H-5; PR16, PR25 |
| MP-T02 | `lib/MakiePotts/test/backends/{common,cairo,gl,wgl}.jl`, its `Project.toml`/`Manifest.toml` | Manual optional-backend lane; requalify in G5H-5; PR16, PR25 |
| MP-T03 | `lib/MakiePotts/test/{render_audit,visual_audit_b,visual_reference_scene,visual_regression}.jl`, `lib/MakiePotts/test/reference/makiepotts-v02.png` | Manual visual evidence; wire or retire in G5H-5; PR16 |
| IN-T00 | `integration/{runtests,test_unitful_extension,test_optional_extension_loading}.jl` | Keep upstream extension/load-order evidence; PR18, PR25 |
| IN-T01 | `integration/test_modelingtoolkit_assimilation.jl`, `integration/test_modelingtoolkit_standard_library.jl` | Replace; these qualify only the superseded copied-assimilation path, not F02/F03; PR27 |
| GPU-T00 | `benchmark/backends/{metal,cuda,amdgpu}/runtests.jl` | Manual vendor runners. Metal is broadest; CUDA/AMDGPU do not currently prove device lifecycle/relationship mutation. Requalify per row in G5H-4; PR04, PR06–PR09, PR17, PR22, PR24, PR28–PR30 |

## Qualification, benchmark, and historical-tooling inventory

These rows partition the four live top-level qualification scripts, the two live benchmark source
files outside test trees, and the seven surviving archived Julia checkers. The three vendor
`runtests.jl` files are already counted in GPU-T00. Generated code and result captures under
`benchmark/results/**` are historical outputs, not executable source or current qualification.

| ID | Exact tooling set | Disposition and owning witness/gate |
|:--|:--|:--|
| QL01 | `scripts/check_v1_operation_inventory.jl` | `merge`; preserve the operation-identity/transfer check through the documented compiler SPI and final public inspection, without private package reach — PR21–PR23, G5H-1/G5H-2 |
| QL02 | `scripts/qualify_descriptor_metal.jl` | `merge`; this one-line launcher joins the explicit Metal hardware lane and cannot qualify another vendor — PR17, PR22, PR25, G5H-4 |
| QL03 | `scripts/qualify_specialization_growth.jl` | `keep` the specialization/code-growth measurement and rebase its fixtures and thresholds after compiler-SPI consolidation — PR22, G5H-1 |
| QL04 | `scripts/qualify_static_evaluator.jl` | `keep` the independent semantic/evaluator oracle while splitting host oracle, generated-code measurement, and optional Metal execution responsibilities — PR22, G5H-1/G5H-4 |
| BM01 | `benchmark/src/lifecycle_performance.jl` | `keep` as baseline evidence only; update for the F06 inactive-bank lifecycle and rerun final lifecycle memory/performance measurements — PR06, PR09, PR24, G5H-1/G5H-5 |
| BM02 | `lib/MakiePotts/benchmark/benchmarks.jl` | `keep`; rebind to final public observation/materialization paths and thresholds — PR16, PR25, G5H-5 |
| AR01 | `scripts/archive/potts-history/*.jl` (7 files) | `defer` as historical reproduction tooling; it is not current qualification, and G5H-5 either retains the clearly archived set or removes it with Git recovery |
| AR02 | `benchmark/results/**` | `keep` as historical generated evidence only; it neither enters source/responsibility counts nor qualifies the changed G5H implementation, and G5H-5 records fresh measurements separately |

## Consolidation register

| ID | Duplicate or risk | Frozen disposition | Owning gate |
|:--|:--|:--|:--|
| DC01 | Sequential and checkerboard acceptance implementations differ at finite validation and zero temperature | `merge` into one validated, kernel-safe law with algorithm parity and rejection tests | G5H-1 |
| DC02 | `_all_system_statements`, completion qualification, and source-graph freezing independently traverse/reify declarations | `merge` into one traversal and normalized source record | G5H-1 |
| DC03 | Completion, analysis, lowering, and inspection reconstruct lifecycle meaning separately | `merge` into one resolved lifecycle IR that derives plan and report | G5H-1 |
| DC04 | Completion flags, executable manifests, compile coverage, and Core runtime reports compete as capability/schema authorities | `merge` into one schema family and structured capability lattice | G5H-1 |
| DC05 | Problem construction, `init`, SII reads, and restore materialize Core runtime through overlapping paths | `replace` with validation-only problem construction and one materializer per profile | G5H-1/G5H-2 |
| DC06 | Program snapshot/checkpoint, auxiliary codec hooks, saved state, and Potts checkpoint layer codecs/checksums | `merge` into one logical schema/codec with distinct view types and replay classes | G5H-1/G5H-3 |
| DC07 | 479 Core public names and 61 additional PottsToolkit public compiler names expose implementation topology | `replace` with narrow runtime API plus explicit compiler/backend SPIs | G5H-1 |
| DC08 | Sequential lifecycle rollback holds whole-state copies while lifecycle workspaces hold additional staged state | `replace` mutation-and-rollback with F06 inactive-bank/status-gated publication; measure and bound memory | G5H-1 |
| DC09 | Copied `EquationComponent` state and native MTK state would create two equation/parameter/event authorities | `remove` copied assimilation and retain native component islands | G5H-3 |
| DC10 | Public `compile`/executable construction and runtime initialization both own materialization choices | `replace` with F14 validation-only problem plus one late materializer | G5H-2 |
| DC11 | Ambiguous spatial query aliases overlap the accepted explicit incidence/cell/global vocabulary | `replace` aliases as specified by PT03/PR20, preserving the unambiguous operations | G5H-2 |
| DC12 | Root tests duplicate Core runtime laws and use private Core topology | Move the independent laws to Core, retain black-box scheduled-system witnesses at root, and preserve intentionally independent analytic oracles | G5H-1/G5H-2 |
| DC13 | Application manifests carry orphaned dependencies after package retirement | Regenerate from each current project or remove the manifest; no name-scrubbing substitute | G5H-0 |
| DC14 | Manual visual/backend lanes exist outside ordinary package tests | Classify explicitly in the test inventory, then wire or retire at their owning qualification gate | G5H-4/G5H-5 |
| DC15 | `RelationshipBinding` is exported twice in the PottsToolkit declaration block | Remove the duplicate declaration with no API or behavior change | G5H-1 |

DC01 and the reachable-state checkpoint mismatch in F07 are mandatory correctness repairs, not
optional line-count cleanup.

This register is the exhaustive G5H-0 responsibility-level duplication inventory: searches over
definitions, include topology, public declarations, codec/fingerprint/checkpoint paths, traversal,
materialization, settlement, acceptance, lifecycle, MTK assimilation, and test ownership found no
additional competing semantic authority. Ordinary helper repetition is not a consolidation target
unless a later gate demonstrates divergent meaning or measurable cost.

### Decision 0041 file-responsibility reviews

Nine active production/test/qualification source files exceed 1,000 nonblank, noncomment lines.
Generated code captures under `benchmark/results/**` are evidence artifacts rather than maintained
source and are excluded. None of the nine receives a permanent waiver at G5H-0; its owning gate
must split coherent responsibilities or record a measured, reviewed waiver without inventing
abstractions.

| File | Count | Responsibility decision |
|:--|--:|:--|
| `test/test_lifecycle_sequential.jl` | 1,739 | Split Core transaction laws from public authoring/lifecycle witnesses — G5H-1/G5H-2 |
| `test/test_sequential_reference.jl` | 1,555 | Split analytic Core oracle from public lowering witness; keep independence — G5H-1/G5H-2 |
| `src/completion/completion.jl` | 1,402 | Split traversal/normalization/lifecycle responsibilities only after DC02/DC03 establish one IR — G5H-1 |
| `lib/CorePotts/src/execution/tracker_plan.jl` | 1,369 | Split protocol, plan construction, and runtime operations behind named SPI boundaries — G5H-1 |
| `lib/CorePotts/test/test_program_v1.jl` | 1,362 | Split its fourteen test families along the CP-T01 inventory — G5H-1 |
| `test/test_descriptor_compiler.jl` | 1,285 | Move Core descriptor laws to Core and keep external compiler-SPI conformance at root — G5H-1 |
| `scripts/qualify_static_evaluator.jl` | 1,185 | Split the independent host semantic oracle, generated-code/specialization measurement, and optional Metal execution without sharing decisive oracle logic — G5H-1/G5H-4 |
| `lib/CorePotts/src/execution/lifecycle_commit.jl` | 1,153 | Separate canonical validation/staging/publication responsibilities under F06 — G5H-1 |
| `lib/CorePotts/src/program/relationships.jl` | 1,148 | Separate schema/store, request validation, and transaction commit without duplicating integrity law — G5H-1 |

## Frozen architecture decisions

These decisions close the material choices required for G5H-0. Later gates choose implementation
details only within them.

### F01 — Public lifecycle

The only public lifecycle is incomplete `PottsSystem -> complete -> mtkcompile -> scheduled
PottsSystem -> PottsProblem -> init/solve -> PottsIntegrator/PottsSolution`. There is no public
`compile` or `PottsExecutable` authoring stage. Algorithm, backend, scalar policy, seed, replica,
and runtime state are late inputs, never arguments to structural `mtkcompile`. Because
ModelingToolkitBase is a direct dependency, the pure-Potts
`ModelingToolkitBase.mtkcompile(::PottsSystem)` method lives in base PottsToolkit and works after
`using PottsToolkit` alone. The weak full-ModelingToolkit extension is reserved for native external
component integration.

### F02 — Structural MTK behavior

`PottsSystem` remains an `AbstractSystem`. `complete` closes authoring meaning. `mtkcompile` may
complete, simplify Potts structure, compile native child structure through public upstream APIs,
and build a deterministic coupling schedule, but returns a `PottsSystem`. Repeated completion and
structural compilation are idempotent by semantic fingerprint. G5H-2 proves the pure-Potts base
method in a fresh process without loading full ModelingToolkit; G5H-3 owns heterogeneous native
children through the weak extension.

### F03 — Native components

External MTK systems remain native component islands. PottsToolkit stores their identity,
hierarchy, scope, typed IO, cadence, time map, problem family, algorithm policy, lifecycle policy,
and capability requirement. It never copies their equations, unknowns, parameters, defaults,
initialization equations, observations, or events into a Potts-shaped surrogate.

### F04 — Core API separation

CorePotts exposes a narrow runtime API at package level and explicit `CompilerSPI` and `BackendSPI`
namespaces. End users do not receive evaluator, handle, workspace, descriptor, kernel-plan, or
lifecycle-implementation types merely because PottsToolkit needs them. Cross-package tests may use
only stable runtime names or a named SPI.

### F05 — Compiled-plan immutability

Compiled plans are *owned and logically immutable*, not necessarily recursively immutable Julia
objects. Construction defensively owns mutable buffers; no supported accessor permits mutation;
fingerprints cover logical contents; adaptation creates an independent target-owned plan. Deep
field immutability is not required.

### F06 — Lifecycle receipt and component-state seam

CorePotts produces one immutable, generation-safe `LifecycleReceipt` only after a successful
settled lifecycle transaction. A standalone Core run may then publish it; in a coupled run it
remains staged until the whole coupled boundary succeeds. It is distinct from the operational
`ProgramSettlementReceipt`. The lifecycle receipt contains completed MCS, transaction/source identity, canonical event order,
and one typed variant per structural outcome:

- `Create`: no before identity and exactly one after `(slot, generation, kind)`;
- `RemoveCell`: exactly one before identity and no after identity;
- `Retire`: exactly one before identity, no after identity, and retained retirement cause/policy
  identity distinct from removal;
- `Transition`: exactly one before and one after identity for the same slot/generation, with the
  before/after kinds explicit; and
- `Divide`: exactly one parent-before identity plus role-tagged parent-after and daughter-after
  identities, where the daughter has a distinct generation-stamped identity.

A failed transaction publishes no receipt and changes no active state. CorePotts owns generic bulk
slot/generation validation and movement; PottsToolkit owns native component values and applies one
receipt exactly once as part of the coupled settlement.

After conflict resolution, surviving requests and receipt entries are canonically ordered by
qualified request identity: qualified source identity, action identity, anchor identity, and
generation. Explicit lifecycle priority participates only in conflict-winner selection; it is not
publication order, and declaration/tuple/launch order never supplies priority. Core and component
candidates both stage in inactive banks. A single status-gated swap publishes them only after the
whole coupled boundary succeeds; mutation followed by rollback is not the implementation model.
Any Core or component failure leaves the active pre-MCS bank unchanged, publishes neither
observations nor a receipt/checkpoint, and makes the integrator terminal with the last fully
published state recoverable. Retry is available only through an explicit later policy that
advances `repeat`; it is not the default. Checkpoint encodes only the active published bank, and
restore never replays a half-applied transaction.

### F07 — Reachable states and checkpoints

Every reachable settled state admitted by a capability profile is checkpointable, and every active
cell in a finalized, observable, or checkpointed state owns at least one site. `ForbidExtinction`
rejects loss of the final site. `RetireAtZero` may expose one private zero-occupancy transient, but
its due lifecycle transaction must consume that transient before completed-MCS publication. A Core
program without either behavior must reject the last-site transition before settlement; accepting
it and failing only when checkpointing is not admitted behavior.

### F08 — Capability lattice

Capability is one structured conjunction over algorithm, backend and concrete device, dimension
and topology, scalar/math policy, component scope, native problem family, lifecycle features,
checkpoint/replay class, and observation/event mode. Each row has `Supported`, `Experimental`, or `Unsupported` status, a
reason, exact evidence identity, and a maturity of `InterfaceOnly`, `Compiles`, `Functional`,
`ReplayQualified`, or `PerformanceQualified`. Admission requires one evidenced row to cover the
complete requirement; unrelated rows cannot be combined into an implicit claim. CorePotts reports
mechanism facts; PottsToolkit composes the public report. Boolean feature flags and compilation
success alone are not support claims. `Unsupported`, `InterfaceOnly`, and `Compiles` never
authorize execution. Ordinary execution requires `Supported + Functional` or stronger;
`Experimental + Functional` requires explicit user opt-in and remains outside stable claims.
Checkpoint or exact-continuation requests require `ReplayQualified`. `PerformanceQualified` adds a
measured claim but cannot compensate for missing functional or replay evidence.

### F09 — Algorithms and GPU evidence

Sequential CPU is the complete semantic reference. Checkerboard CPU and GPU are separate
stochastic algorithms. Metal on the target Mac is the first required real-GPU evidence lane.
The first global and per-cell component GPU rows are compile-once, fixed-shape, device-total,
fixed-step ODE subsets; adaptive solvers, DAEs, root events, arbitrary callbacks, dynamic dispatch,
allocation, and unsupported scalars reject during preflight. CUDA and ROCm public selectors remain
removed/unsupported until their own extensions pass the same applicable evidence. No vendor
absence weakens qualified CPU or Metal claims, and no path may fall back to host execution silently.

### F10 — Time and publication

The master Potts time is integer completed MCS. Each time-dependent native component declares a
positive physical duration per MCS. The default `CPMThenComponents` step uses settled inputs,
executes the CPM into an inactive bank, applies its staged lifecycle receipt to inactive component
pools, advances native components over their physical interval, then publishes Core state,
component state, receipt, outputs, and the new MCS through one status-gated commit. The computation
order is CPM-then-components; public visibility is all-or-nothing. An MTK discrete clock does not
own CPM time.

### F11 — Relationship semantics

V1 admits bounded typed undirected cell relationships, with at most one edge per unordered
generation-stamped endpoint pair per schema. User-authored external mutations enter on the host at
a settled boundary. Admitted compiled descriptors may emit bounded device-resident requests;
validation, canonical conflict selection, capacity handling, commit, and typed status publication
execute on the selected backend for every qualified profile. Device kernels receive immutable
views for reads, and no qualified GPU row may hide host mutation or transfer. `Directed` and
daughter-link inheritance are removed/deferred until their own storage, lifecycle, and conformance
contracts are qualified; MTK component wiring is not a Core relationship store.

### F12 — Observation and Makie boundary

A settled logical observation carries MCS, ownership, cell slot/generation/kind metadata, named
site/cell/model channels, and provenance. SII names derive from the scheduled `PottsSystem`.
MakiePotts consumes only this public host representation. Owner value alone never classifies a
site as medium, cell, or obstacle; kind/domain metadata does, including multiple media.

### F13 — Acceptance law

There is one law for sequential and checkerboard execution. Host preflight validates static
parameters and a finite nonnegative temperature; production draws are not host-prevalidated.
Semantic RNG transforms addressed words to a draw in `(0, 1)` by construction. Data-dependent
nonfinite energy, bias, or modifier values produce a typed device-visible failure status without a
kernel throw or fallback. Constraints reject. At zero temperature, conservative effective energy
`delta_h + drive_energy <= 0` accepts and positive energy rejects; nonzero log bias or kinetic
modifier is unsupported and rejects before execution. At positive temperature, the log ratio is
`-(delta_h + drive_energy)/T + drive_log_bias + kinetic_modifier`, with the same strict addressed-
draw threshold on every engine/backend.

### F14 — Late materialization and cache

`PottsProblem` stores a scheduled system plus immutable initial values, parameters, MCS span, seed,
replica/repeat identity, and run policies; construction validates but does not allocate Core runtime.
`init`/`solve` selects algorithm/backend/scalar profile and invokes the single private materializer.
An optional cache is keyed by scheduled-system fingerprint and the full capability specialization;
it is not a public artifact, semantic authority, or checkpoint payload. `remake` invalidates exactly
the affected key dimensions.

### F15 — Test ownership

CorePotts owns RNG, acceptance, sequential/checkerboard execution, trackers, lifecycle,
relationships, settlement, logical checkpoint, and backend-contract tests. PottsToolkit owns
authoring, completion, schedules, late lowering, SciML lifecycle, SII, components, and black-box
scientific workflows. MakiePotts owns frame/channel/recipe conformance. Integration owns real
upstream package interaction and extension load order. Root tests may not reach unscoped Core
private fields after G5H-1.

### F16 — Replica and repeat identity

`replica` identifies a logical ensemble trajectory; `repeat` identifies a retry of that same
trajectory. Both participate in semantic RNG addressing, including initialization, and both persist
through checkpoints. `prob_func` assigns replica deterministically. A retry increments repeat
without changing replica. No initialization path hard-codes repeat `1` after problem identity is
known.

### F17 — Fields, MethodOfLines, and ensembles

The existing Euler lattice stencil is retained only as a built-in discrete-field component.
MethodOfLines is a separate weak extension using `symbolic_discretize`, real upstream structural
compilation, and an explicit coordinate-to-lattice grid map. Whole-trajectory SciML ensembles and
within-trajectory per-cell batching remain distinct APIs, evidence, and capability dimensions.

### F18 — Dagger

Dagger is deferred as a dependency and execution authority. G5H-4 may benchmark an optional coarse
scheduler for independent trajectories or component islands, but Dagger may never own MCS order,
publication, lifecycle commit, RNG identity, or checkpoint meaning. A measured defer result passes
the gate; adoption requires an optional extension and a demonstrated benefit.

### F19 — Documentation product

The active manual remains the four-page honest hardening landing until G5H-5. Legacy manual source
is rewrite material only. G5H-5 rebuilds executable final-interface documentation and serial Wortel
and Merks programs; it does not mechanically restore the old `PottsModel`, `EquationComponent`, or
public-executable manual.

## Destructive-cleanup and recoverability map

Decision 0043/G5H-0 cleanup deletes 356 tracked files. Every path is listed in the
[`g5h0-deletion-inventory.tsv`](g5h0-deletion-inventory.tsv) with an ordered group and disposition.
All are recoverable from parent commit `3591eccd6820bf51c185cf631c75467114319332`
(tree `26993838c79538377317f14b4abe7da40aee73d2`) and remain outside the active authority chain.

| Group | Files | Disposition | Reason and recovery |
|:--|--:|:--|:--|
| `lib/ProcessBigraphs/**` | 165 | `remove` | Retired package, tests, extension, and manual. Recover an individual file with `git show 3591ecc:<path>` or inspect the parent in a separate worktree. |
| `scripts/archive/process-bigraphs/**` | 36 | `remove` | Checkers for the retired runtime and its obsolete gates; executable only against deleted inputs. |
| Other paths explicitly named for ProcessBigraphs | 78 | `remove` | Adapter, bridge tests, decisions, specifications, audits, evidence, and qualification tied to the retired package. |
| Three surviving-G5 control/review records | 3 | `replace` | Async settlement review is carried by the retained G5-L exit and R2 review; execution control is carried by the compiler-construction clauses plus R2; implementation control is carried by those exact reviews plus `g5h-control.md`. The retained R2 request records their parent-commit locations. |
| Other mixed consolidation/symbolic audits | 14 | `remove` | Interviews/reviews for the abandoned ProcessBigraph-centered consolidation, copied assimilation, or public-executable program; conclusions remain in Git history. |
| Mixed consolidation/Phase 16-17 evidence | 31 | `remove` | Evidence binds deleted specs, paths, package identities, or support claims and cannot qualify the clean baseline. |
| `scripts/archive/consolidation/**` | 17 | `remove` | Archived scripts reference deleted consolidation registries/evidence and otherwise fail; retaining broken executable archaeology is less recoverable than Git history. |
| Two Phase-13 API scripts | 2 | `remove` | They require the deleted ProcessBigraph Phase-16 API registry and enforce the superseded export freeze. |
| Mixed consolidation/Phase-16 specifications, decisions, and obsolete documentation target | 10 | `remove` | Competing architecture/phase authority tied to the retired engine or superseded public executable/manual boundary. Decision 0041 is retained with its surviving repository-wide rules and a scoped historical banner. |

The TSV classification is deterministic in this order: package prefix (D01), retired-script
prefix (D02), an explicit ProcessBigraph path token (D03), the three exact replacement audits
(D04A), other deleted audits (D04B), deleted evidence (D05), consolidation scripts (D06), the two
exact Phase-13 scripts (D07), then the ten enumerated residual specifications/decisions (D08).
The group counts sum to 356, so no deleted tracked path can fall outside the map.

A pre-removal archive that also contains formerly untracked ProcessBigraph work is retained outside
the repository at
`/Users/praneethmerugu/Documents/Jiang/CPM 1.6/ProcessBigraphs-retired-20260805.tar.gz`, SHA-256
`338d74d39aa46c2610f49bfc55cfb48ce60e86d12113b337d7d669af8a2007bd`. It contains 16,294 entries
under `lib/ProcessBigraphs/`. The archive is recovery material, not candidate authority or an active
dependency; R2H-A verifies the path and checksum without indexing its contents into the package.

No scientific contract in the `spec/README.md` surviving-contract list is deleted. Active source,
tests, manifests, workflows, and the temporary documentation build contain no retired dependency,
hook, UUID, or link. Historical retirement mentions in Decision 0043, Decision 0044, the authority
indexes, and subordinate architecture guidance are intentional boundary statements.

## G5H-0 review-readiness obligations

The candidate may be submitted to R2H-A only when the living control record links exact passing evidence
for all of the following:

1. PottsToolkit, CorePotts, and MakiePotts full package tests;
2. the integration suite with exact locally resolved upstream versions recorded;
3. the strict temporary documentation build;
4. local active-authority links and `git diff --check`;
5. fresh-process PottsToolkit and CorePotts dependency-boundary checks;
6. zero active retired-package references, with intentional historical mentions classified;
7. exact public declaration counts, uniqueness, range coverage, source/test/protocol partitions,
   deletion classification, and application-manifest resolution above.

## R2H-A clearance

After review readiness is proven, an independent reviewer inspects the exact candidate read-only.
G5H-0 clears only with zero P0/P1 findings, every P2 assigned to an owning later gate, and the exact
reviewed commit recorded in `g5h-control.md`. This review result is a clearance condition, not a
prerequisite for opening the review.

The baseline records existing correctness debts openly. It does not permit G5H-1 work before
R2H-A clearance.
