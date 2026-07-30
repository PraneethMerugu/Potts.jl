# Symbolic Potts V1 Consolidation Readiness Audit

Date: 2026-07-30

Branch: `codex/symbolic-potts-v1`

Status: passed for owner send-off; production implementation remains prohibited until explicit
owner authorization

## Verdict

Symbolic Potts V1 is specified deeply enough for one autonomous clean-break implementation phase.
The audit found no unresolved product decision, scientific contradiction, package-ownership
blocker, or current public ModelingToolkit/SciML interface blocker.

The audit did find specification defects. They are resolved normatively in SPV1-050 through
SPV1-055 and the
[autonomous consolidation contract](../../spec/symbolic-potts-v1-consolidation.md). None is left
for an implementation agent to guess.

The verdict is therefore:

```text
OWNER INTERVIEWS                 PASS
IMPLEMENTATION-GRADE SPEC        PASS
REPOSITORY IMPACT MAP            PASS
SURVIVING-SCIENCE RECONCILIATION PASS
UPSTREAM PUBLIC-API FEASIBILITY  PASS
AUTONOMOUS STOPPING RULE         PASS
IMPLEMENTATION AUTHORIZATION     NOT YET GRANTED
MERGE READINESS                  BLOCKED BY DEFERRED DOCUMENTATION
```

The documentation result is an intentional downstream merge constraint, not an implementation
design blocker. The current docs use the old API and the docs workflow runs on pull requests.
This branch is explicitly forbidden from replacing those docs.

## Audit scope and method

The audit covered:

1. all accepted owner decisions CI-001 through CI-026;
2. every normative SPV1 clause;
3. the current PottsToolkit, CorePotts, ProcessBigraphs, MakiePotts, integration, docs, and workflow
   trees;
4. surviving scientific specifications for state, time, proposals, randomness, relationships,
   lifecycle, numerics, persistence, SciML, and published models;
5. current official ModelingToolkitBase, ModelingToolkit, Symbolics,
   SymbolicIndexingInterface, SciMLBase, DynamicQuantities, Julia, Pkg, Aqua, ExplicitImports, and
   PrecompileTools contracts; and
6. every known deletion, extraction, dependency, test, CI, and merge consequence.

The audit used source inspection and static repository queries. It did not change production code.
The local shell does not provide a Julia executable, and the workspace dependency runtime also
reported no bundled Julia. Runtime reflection and Julia package tests could therefore not be run
during this specification-only audit. This is an environment limitation to recheck at
implementation start, not evidence of an interface blocker.

## Repository inventory

The implementation is a real clean break, not a small authoring façade:

| Area | Files or lines observed | Audit consequence |
| --- | ---: | --- |
| root `src` | 37 files, 9,759 lines | broad public authoring layer is replaced |
| root `src/authoring` | 29 files, 7,701 lines | old model/rule/normalization authority is removed |
| root reference models | 4 files, 1,631 lines | hidden builders become visible fixtures |
| root tests | 14 files, 2,279 lines | authoring tests are rewritten, not wrapped |
| CorePotts source | 72 files, 32,305 lines | extraction and deletion must be staged carefully |
| CorePotts coupled tree | 35 files, 16,458 lines | largest dual-authority risk |
| CorePotts algorithms | 5 files, 3,114 lines | keep sequential/checkerboard; delete Lottery/tiled |
| CorePotts SciML | 1 file, 1,134 lines | useful behavior, wrong ownership and call surface |
| CorePotts tests | 47 files, 10,063 lines | scientific assertions are valuable rewrite inputs |
| ProcessBigraphs source/tests | 15,105 / 6,075 lines | independent runtime remains domain-neutral |
| MakiePotts source/tests | 1,595 / 1,527 lines | adapter update likely required |
| integration | 53 files, 8,776 lines | old evidence/oracle structure must be narrowed |

The current root module directly includes compatibility, the old authoring tree, hidden reference
models, public API documentation, and precompilation. It reexports a very broad CorePotts surface.
The current CorePotts root imports ProcessBigraphs, includes Lottery and tiled algorithms, coupled
semantic-kernel code, paper-specific assemblies, ProcessBigraph adapters, old persistence
conversion, and the old SciML interface.

Static search found old names or authorities across source, tests, integration, and 53 documentation
or example files. This supports the accepted decision to perform deletion only after a working V1
vertical path exists and confirms that the later documentation phase is mandatory before merge.

## Dependency audit

Current dependency direction conflicts with V1:

- PottsToolkit strongly depends on ProcessBigraphs and several execution/solver utilities while
  lacking the accepted symbolic foundation.
- CorePotts strongly depends on ProcessBigraphs.
- only Unitful currently uses the desired weak-extension pattern.

The accepted target is feasible with ordinary Julia package extensions:

- PottsToolkit strongly owns ModelingToolkitBase, Symbolics, SII, DynamicQuantities, SciMLBase, and
  CorePotts;
- full ModelingToolkit, ProcessBigraphs, and Unitful are weak dependencies;
- CorePotts loses ProcessBigraphs and every symbolic dependency; and
- ModelingToolkitStandardLibrary is test-only.

No dependency cycle is introduced. ProcessBigraphs remains independent. PottsToolkit becomes the
only package aware of both symbolic model meaning and the concrete Potts runtime.

## Upstream interface audit

### ModelingToolkitBase and ModelingToolkit

Current upstream source publicly provides `AbstractSystem`, system accessors, completion state,
composition/extension/flattening concepts, namespacing, IO, and SII integration. A custom
`PottsSystem <: ModelingToolkitBase.AbstractSystem` is therefore supported.

The important constraint is that generic ModelingToolkit completion expects ordinary system
fields/accessors and equation semantics. It cannot infer Potts effects, proposal contexts,
relationship transactions, bounded mutations, stochastic operation identity, or device storage.
Potts-owned `complete` is required, while the standard documented accessors remain required for
integration.

The audit found no need to depend on private concrete `System` fields, tearing state, caches, or
compiler passes. `EquationComponent` can inspect supported external systems through public
accessors and reject semantics outside the closed contract.

Primary sources:

- <https://raw.githubusercontent.com/SciML/ModelingToolkit.jl/master/lib/ModelingToolkitBase/src/ModelingToolkitBase.jl>
- <https://raw.githubusercontent.com/SciML/ModelingToolkit.jl/master/lib/ModelingToolkitBase/src/systems/abstractsystem.jl>
- <https://docs.sciml.ai/ModelingToolkit/dev/API/System/>

### SymbolicIndexingInterface and SciMLBase

SII publicly supports symbolic getters/setters and the complete indexing interface. SciMLBase
supports immutable problem `remake`, standard solution contracts, return codes, and symbolic maps.

One semantic mismatch required resolution: SII `setp` conventionally mutates a target, while
`PottsProblem` is immutable. SPV1-053 now allows `getp` on problem/integrator/solution, rejects
problem `setp` in favor of `remake`, and permits mutating `setp` only on a settled integrator.

Another ambiguity was partial `u0` remake. SPV1-053 now distinguishes preserving the old state,
overlaying symbolic values, and replacing ownership with a complete `PottsInitialState`.

Primary sources:

- <https://docs.sciml.ai/SymbolicIndexingInterface/stable/complete_sii/>
- <https://docs.sciml.ai/SciMLBase/dev/interfaces/Problems/>
- <https://docs.sciml.ai/SciMLBase/stable/interfaces/Solutions/>

### DynamicQuantities and units

DynamicQuantities supports symbolic units and preserves declared unit spelling and scale. The
official distinction between symbolic `us"..."` and eagerly expanded `u"..."` supports the
accepted authoring policy.

The specification previously named `DeclaredReferenceUnits()` without closing its behavior.
SPV1-051 now defines the accepted anchors, ambiguity behavior, explicit override, fingerprint
effect, and completion signature.

Primary source:

- <https://ai.damtp.cam.ac.uk/dynamicquantities/stable/symbolic_units/>

### Julia package/API quality

The repository requires Julia 1.12, so Julia's `public` declaration is available. Pkg weak
dependencies and extensions support the accepted optional integration topology. Aqua,
ExplicitImports, and PrecompileTools support an ordinary library QA path without a custom evidence
system.

Primary sources:

- <https://docs.julialang.org/en/v1/manual/modules/>
- <https://pkgdocs.julialang.org/v1/creating-packages/>
- <https://juliatesting.github.io/Aqua.jl/stable/>
- <https://juliatesting.github.io/ExplicitImports.jl/stable/api/>
- <https://julialang.github.io/PrecompileTools.jl/stable/>

## Specification defects found and resolved

| ID | Finding | Severity | Resolution |
| --- | --- | --- | --- |
| A-01 | SPV1-007 placed the selected engine and schedule in `PottsProblem`, contradicting SPV1-043 | blocking ambiguity | engine/backend/scalar/schedule now belong only to `PottsExecutable`; problem owns run data |
| A-02 | exact 23 stored statement kinds existed only in the interview | blocking omission | frozen in SPV1-016 and ACV1-005 |
| A-03 | `StatementID`, `UnknownSource`, `@statements`, and source-independent identity were not fully normative | high | frozen in SPV1-050 and ACV1-006 |
| A-04 | one `map_symbolics` traversal and rejection of a universal schema were not fully normative | high | frozen in SPV1-050 and ACV1-005 |
| A-05 | registry construction, default, snapshot, exact idempotence, and lookup lifetime were incomplete | high | frozen in SPV1-050 |
| A-06 | `DeclaredReferenceUnits()` had no exact selection contract | high | frozen in SPV1-051 |
| A-07 | `complete(completed)` and changed completion options were undefined | medium | identical completion is identity; different options error |
| A-08 | mandatory `scalar_type` coexisted with an open numerical-policy space | high | V1 fixes scalar-matched accumulation, accurate math, deterministic reductions, checked bounds |
| A-09 | solve controls were named but exact defaults were absent | high | defaults frozen in SPV1-053 |
| A-10 | saved-state ownership and observation selection were underspecified | high | defensive `PottsSavedState`; only executable-declared observations may be selected |
| A-11 | SII mutation of immutable problems was ambiguous | high | problem `setp` rejected; integrator-only boundary mutation; `remake` for problems |
| A-12 | partial `u0` remake could accidentally patch ownership | high | symbolic map overlays values only; ownership replacement requires a complete initial state |
| A-13 | new clean-break checkpoint seemed to conflict with HDF5/Zarr scientific storage | medium | in-memory V1 conformance is mandatory; retained optional codecs are rewritten against that schema, never migrated |
| A-14 | old optional seed default conflicts with mandatory V1 seed | high | explicitly superseded |
| A-15 | old ensembles derive replacement trajectory seeds, conflicting with addressed replica/repeat identity | high | explicitly superseded; one master seed is preserved |
| A-16 | Lottery/tiled clauses survived in time, RNG, SciML, and qualification specs | high | explicitly superseded in V1 scope |
| A-17 | old charter/API specs require broad first-class CorePotts authoring | high | explicitly superseded by the narrow compiler/runtime boundary |
| A-18 | checkerboard focal support could be inferred despite surviving rejection | scientific risk | initial focal fixture is sequential; checkerboard requires a complete proof and has no fallback |
| A-19 | inline full model assembly could be weakened into a hidden fixture helper | high | fixture source must visibly assemble the whole model; helpers may only provide literal data/assertions |
| A-20 | docs are excluded although current PR docs compile old APIs | merge risk | docs workflow is not weakened; code branch remains unmergeable until paired docs work |

No unresolved item remains in this table.

## Surviving scientific contract audit

The V1 clean break changes authoring and execution ownership, not accepted CPM science. These
contracts survive:

- lattice ownership, cell identity, slot generation, capacity, lifecycle, and logical-state
  invariants;
- accepted topology and spatial-relation semantics;
- proposal selection, copy staging, Hamiltonian evaluation, Metropolis acceptance, and normalized
  MCS;
- deterministic semantic RNG addresses and checkpoint continuation claims;
- sequential exact-attempt meaning and checkerboard's separately characterized kinetics;
- field, history, observation, contact, geometry, elongation, connectivity, activity, and
  chemotaxis meanings;
- typed create/remove/retune relationship transactions, degree/capacity/generation validation,
  lifecycle cleanup, and rollback;
- completed-MCS publication and checkpoint boundaries;
- numerical conversion, accurate default math, deterministic reductions, and checked bounds; and
- HDF5/Zarr equivalence to one in-memory logical checkpoint schema when those extensions remain.

The following are deliberately superseded:

- old authoring types, fragments, rule algebra, host escape hatches, and old compilation cache;
- Lottery and tiled engines;
- broad direct CorePotts authoring and extension APIs;
- CorePotts-owned ProcessBigraph integration;
- old authoring serialization and checkpoint migration;
- optional default seed and derived per-trajectory seed replacement;
- hidden Merks, Wortel, CNV, or paper-specific model constructors as public evidence; and
- custom evidence freshness, one-time qualification, or legacy parity machinery.

## Reuse, extraction, and deletion audit

### Reuse behind a new narrow authority

Current code contains implementation assets worth retaining after qualification:

- logical state, ownership, cell generations, free-list/capacity handling;
- topology and Cartesian relations;
- semantic Philox addressing;
- proposal and acceptance kernels;
- sequential and graph-colored checkerboard execution;
- field and history storage;
- observation and tracker mechanisms;
- lifecycle planning and atomic application;
- typed relationship requests, canonical deterministic ordering, validation, and transaction;
- logical initialization;
- checkpoint integrity and storage-adapter mechanisms; and
- backend capability and Makie adapter mechanisms.

These are not retained as public authoring authority. They are extracted behind
`CompiledPottsProgram`.

### Delete after replacement

- root compatibility code;
- root old authoring, normalization, rule, fragment, and model APIs;
- root hidden reference-model builders;
- old root precompile and public-doc surfaces;
- CorePotts Lottery and tiled algorithm source and tests;
- CorePotts ProcessBigraph adapter and persistence conversion;
- CorePotts paper-specific Merks/Shirinifard assemblies;
- old coupled declarations, schedules, plans, semantic-kernel authoring, and public dispatch;
- old SciML problem/algorithm ownership;
- old checkpoint readers, conversions, and Julia serialization;
- API ledgers, migration registries, evidence freshness, and obsolete parity gates; and
- stale tests that assert old names or compatibility.

### Keep out of scope

- user-facing docs and tutorials;
- native Makie animations for those docs;
- Dagger;
- third execution engine;
- Vivarium/Python transport;
- general PDE/discretization ingestion;
- SDESystem, jump, delay, noise, callback-affect, or opaque-simulator assimilation; and
- paper-scale production visualization and publication analyses.

## Compiler feasibility audit

The accepted compiler can be implemented without a novel symbolic compiler:

- Symbolics already owns scalar and array expression trees.
- PottsToolkit registers a closed set of domain operations and uses public expression traversal.
- typed statement values own mutation, iteration domains, phases, and effect bounds outside the
  expression tree;
- completion produces qualified immutable records;
- compilation lowers those records into concrete CorePotts data and KernelAbstractions-compatible
  kernels; and
- backend specialization occurs on immutable concrete types after semantic closure.

The difficult part is deterministic concurrent relationship mutation, not Symbolics syntax.
The specification avoids an unprovable V1 promise: sequential accepts the focal workload, while
checkerboard admits accepted-copy relationship mutation only after touched-set and conflict proof.
End-of-MCS ordered batches remain compatible with both engines.

This is technically demanding but bounded. It does not require ModelingToolkit to synthesize
arbitrary GPU mutation or to understand CorePotts internals.

## Model-fixture audit

### Wortel

The current code already demonstrates the required underlying mechanisms: site activity, geometric
reduction, accepted-copy activation, MCS decay, volume/contact energy, stochastic execution, and
observations. V1 must expose those mechanisms visibly through statements and operations, not
`Act()` or a hidden builder.

### Merks

The current model is split across root reference models, old authoring lowering, CorePotts
components/coupled code, and ProcessBigraph assembly. V1 must visibly assemble lattice, kinds,
field state/equations, equation process, chemotaxis, volume, elongation, contact, connectivity,
protocol, initial layout, stochastic problem, and observations in one fixture.

### Focal-point plasticity

Current CorePotts already contains fixed focal and dynamic relationship mechanisms. V1 needs the
symbolic binding, energy, contact creation, break process, retuning/lifecycle policies, and
deterministic request transaction. The first complete fixture is sequential because the accepted
checkerboard proof is not yet available.

All three fixtures can run bounded ordinary-test dimensions and MCS while retaining full mechanism
assembly and stochastic replay/divergence assertions. Paper-sized animations belong to the later
docs/reproduction phase.

## QA and CI audit

The current main CI is already close to a standard Julia library:

- four Linux package-test jobs;
- one integration job;
- macOS and Windows load-only smoke;
- a separate docs build;
- manual GPU and benchmark workflows.

V1 should simplify, not expand it:

- retain package and integration jobs;
- make platform smoke execute one tiny sequential trajectory;
- add Aqua, ExplicitImports, stale-surface, dependency-boundary, targeted inference, and targeted
  warmed-allocation checks inside ordinary tests;
- remove obsolete Lottery/tiled/oracle invocations;
- leave GPU and performance hardware-specific; and
- add no evidence freshness or one-time qualification system.

The docs workflow is the sole intentional red gate after old API deletion. Disabling it on this
branch would hide the real merge dependency and violate the accepted scope.

## Autonomous execution audit

The consolidation contract supplies:

- one exact public lifecycle;
- fixed dependency and extension ownership;
- a closed statement, operation, effect, and phase vocabulary;
- exact completion and compilation pass order;
- exact parameter, initial-state, problem, solve, save, SII, solution, and checkpoint contracts;
- a concrete source-disposition map;
- an ordinary test matrix;
- visible acceptance fixtures;
- ten internal vertical slices;
- explicit stopping rules; and
- phase exit conditions.

The implementation agent does not need owner review between slices and may reorganize in-scope work.
Only a genuinely new scientific/product decision triggers a stop.

## Residual risks

| Risk | Likelihood | Impact | Accepted control |
| --- | --- | --- | --- |
| custom `AbstractSystem` misses an accessor expected by current MTK | medium | high | integration matrix plus current upstream source audit; no private-field fallback |
| broad CorePotts deletion removes a surviving mechanism | medium | high | extract behind `CompiledPottsProgram`, qualify vertical fixture, then delete |
| compile-time type specialization causes latency | medium | medium | immutable executable reuse, targeted precompile workload, measured barriers |
| checkerboard effect proof is too conservative | high | medium | contextual rejection is correct V1 behavior; sequential remains available |
| dynamic relationships exceed static capacity | medium | high | capacity structural; preflight and atomic rollback |
| full inline fixtures make tests slow | medium | medium | full mechanism assembly with bounded PR dimensions/MCS |
| optional extensions accidentally become strong dependencies | medium | high | clean-session extension loading and dependency audits |
| old docs prevent merge | certain | high | intentionally pair later docs phase; do not weaken the workflow |
| GPU backends lag CPU V1 | high | medium | CPU is the ordinary gate; hardware qualification remains explicit and separate |

No residual risk requires an owner product decision before implementation.

## Clause trace

| Parent requirements | Consolidation authority | Primary acceptance evidence |
| --- | --- | --- |
| SPV1-001–006 | ACV1-002–007 | system lifecycle, composition, completion tests |
| SPV1-007–009 | ACV1-009, 012, 015 | RNG, engine, unit, and capability tests |
| SPV1-010–013 | ACV1-001–003, 018 | dependency and stale-source audits |
| SPV1-014–023 | ACV1-005–008, 015 | statement, operation, inference, relationship tests |
| SPV1-024–031 | ACV1-004–009, 016, 019 | equation ingestion and visible model fixtures |
| SPV1-032–033 | ACV1-019–023 | complete ordinary repository gate |
| SPV1-034–042 | ACV1-001, 004, 016, 019 | MTK/MTSL/PB/Unitful integration |
| SPV1-043–047 | ACV1-009–014 | executable, problem, solve, SII, solution, checkpoint |
| SPV1-048–049 | ACV1-017–020, 023 | API, source disposition, CI, final audit |
| SPV1-050–055 | ACV1-005–014, 019–023 | ambiguity closure and phase-exit audit |

## Final readiness statement

The design is ambitious but no longer vague. It has a bounded expression vocabulary, bounded
mutation language, deterministic transaction model, explicit ModelingToolkit seam, domain-neutral
ProcessBigraph boundary, immutable compiled product, two engines, and a standard Julia-library QA
gate.

The branch is ready for the owner to issue explicit implementation send-off. Until that message is
given, no production implementation is authorized.
