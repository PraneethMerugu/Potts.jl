# Consolidated PR dependency map

Status: Proposed delivery map, not opened PRs or authorization to publish/merge.
Prepared 2026-09-08.

## 1. The concrete allocation

**48 planned repository PRs in 21 delivery groups: 20 main-spine PRs and 28
breadth PRs.** This replaces the earlier conversational 60–80 estimate with an
enumerated base allocation. It is not a guaranteed final count or a ceiling on
scientific discoveries.

The [feature plan](authoring-and-model-ecosystem-plan.md) and
[ideal authoring spec](../spec/ideal_api_vision.md) continue to define scope and
scientific requirements. This document owns the proposed grouping, dependency
map and count. P01–P16 and B1–B8 remain coverage labels, not additional PRs to open
on top of this map. R01–R48 are planning identifiers, not existing GitHub numbers
or prescribed branch names; their numbering is not a chronological merge order.

| Repository | Main spine | Breadth | Planned total |
| --- | ---: | ---: | ---: |
| Potts.jl | 7 | 12 | 19 |
| CorePotts.jl | 6 | 9 | 15 |
| LocalMath.jl | 1 | 2 | 3 |
| MakiePotts.jl | 2 | 0 | 2 |
| PottsModels.jl | 4 | 5 | 9 |
| **Total** | **20** | **28** | **48** |

Abbreviations below: Potts, Core, LocalMath, Makie and Models denote those five
repositories. One repository entry is one PR containing its implementation,
removed representations, ordinary tests, public example, diagnostics and nearest
documentation. A multi-repository group is a coordinated delivery, not a claim
that independent Git repositories can merge atomically.

### Why this is denser

- Make structured values, scoped identity and component imports one public
  cutover, instead of redesigning references again after structured state ships.
- Change relation projection and source maintenance together where they use the
  same quantity contract.
- Ship native publication with its complete supported lifecycle, avoiding a
  second port/settlement redesign immediately afterward.
- Put related model components, tutorials and integration cases in the same
  Models PR; do not allocate a Models PR to every upstream implementation.
- Backend support does not automatically require model-factory changes.
- Keep behavior-preserving preparation and review-heavy energy/conflict proofs
  separately understandable. Density does not justify mixing every concern.
- Measure early and fix measured issues in their still-open owning PRs. Do not
  invent one speculative optimization PR per repository.

No feature is considered implemented merely because it appears in a group.
Conditional companions and undefined extensions are explicit in section 6.

## 2. Main-spine PRs

| Group | Planned repository PRs | Depends on | Previous scope |
| --- | --- | --- | --- |
| **G01 Ecosystem workspace and CI** | R01 Models; R02 Potts; R03 Core; R04 LocalMath; R05 Makie | None | P01–P02 |
| **G02 Potts construction and operational ownership** | R06 Potts | None | P03 + P05 |
| **G03 Core scientific-context ownership** | R07 Core | None | P04 |
| **G04 Structured authoring and component identity** | R08 Core; R09 Potts | G02, G03 | P06–P07 + P11 identity/scope |
| **G05 Maintained quantities and relational mathematics** | R10 Core; R11 Potts | G04 | P08–P09 + P11 quantity consumers |
| **G06 Conservative energy and parallel dependencies** | R12 Core; R13 Potts | G05 | P10 |
| **G07 Native transport and lifecycle composition** | R14 Core; R15 Potts; R16 Models | G01, G05 | P12–P13 + focused P14 model |
| **G08 Model corpus, observation and scientific inspection** | R17 Models; R18 Potts; R19 Makie | G01, G06, G07 | P14–P15 + completed P11 workflows |
| **G09 Reproducible authoring and runtime benchmarks** | R20 Models | G08 | P16 measurements; owner fixes conditional |

### Complete outcomes and validation

**G01 — Workspace, model ownership and CI.** R01 creates Models with bounded
Wortel/Merks/OpenVT model factories, initializers, tutorials and scientific tests
using public APIs. R02 removes the displaced full model ownership from Potts,
preserves minimal Potts contract fixtures, and updates documentation references.
R02–R05 align existing owner workflows, contributor commands and candidate
sibling selection; R01 follows the same pattern. Verify clean install, intended
loaded paths, unchanged bounded model behavior, optional dependency loading,
and required-check behavior. Do not turn Potts/Core runtime dependencies toward
Models. Port the current planning documents from this older workspace to the
appropriate active Potts documentation as part of R02, retaining their proposed
status and preserving unrelated changes.

**G02 — Potts preparation.** R06 combines named operation construction,
source-located diagnostic display and the replacement of mixed operational
`reports` ownership. These are related compiler/runtime-boundary clarity
changes with behavior-preserving commits, not the introduction of new scientific
laws. Cut over every live consumer, including initialization, observation,
native mapping and continuation. An external public custom-operation example
and current scientific results must work without retaining compatibility
forwarders or duplicate report state.

**G03 — Core preparation.** R07 unifies cold read-group/decoder construction and
verified pure geometry formulas, preserves concrete hot contexts and optional
read groups, and updates the execution source map. Check independent geometry
oracles, inference/allocation behavior and current CPU/Metal results. G02 and
G03 are independent and need not merge simultaneously.

**G04 — Structured authoring.** R08 implements structured logical state and
failure-atomic compound publication through the existing execution path.
R09 implements scoped references, one-time declaration assembly, ordinary
constructor equivalence, typed initialization/units, basic retained values,
component identity/imports and explicit structural replacement. Include fixed
vectors/tensors/products, runtime history with declared lag/retention, and the
addressed user-process draws required by real polarity/mechanical consumers.
Individual state lifecycle and persistence are complete here; G07 adds the
cross-native composition, not a repair of missing state semantics.
Demonstrate a public vector-polarity model, simultaneous swap/reset effects,
late failure, two independent component instances sharing a parameter/input,
and rejected scope/shape/unknown-name/writer errors. Do not add a retained builder
graph or make numerical remake silently alter structural arguments.

**G05 — Maintained quantities.** R10 owns source-aware maintenance and relation
contracts; R11 owns ordinary quantity/gather/reduction authoring and lowering.
Deliver additive scalar/vector/tensor statistics, scientific geometry over
shared sufficient statistics, distinct-cell versus contact-weighted sensing,
multiple quantity consumers, and invalidation for every admitted source
mutation, including runtime parameter changes and existing native output.
Non-invertible operations require an explicit supported maintenance/rebuild law;
unsupported algebras receive an actionable rejection. Base delivery includes a
maintained minimum with a declared bounded rebuild law and an ordinary test that
removes the current minimum. A bounded gathered minimum alone does not satisfy
this requirement, nor do additive happy paths.
Test periodic/degenerate geometry, empty reductions, full-field updates without
copies, floating accumulation/rebuild policy, division and restore.
Introduce a LocalMath companion only for a demonstrated missing reusable law.

**G06 — Energies and conflicts.** R12 supplies needed Core evaluation/arbitration;
R13 supplies conservative dependency analysis and author-facing explanations.
Test full tiny-system energy differences for neighbor-dependent and spring/shape
energies. Include opposite-endpoint simultaneous proposals and shared mutable
reads. A correct individual delta does not establish parallel independence.
Unsupported combinations reject without silently changing the algorithm.
Keep this proof-heavy work separate from G05 maintenance.

**G07 — Native transport with lifecycle.** R14 supplies the necessary public
settlement/exchange/lifecycle contracts. R15 supplies expression/structured
native bindings, direct component references, explicit coupling clocks, native
initialization and current-profile expansion. R16 supplies the reusable bounded
field → intracellular signaling → sampled division/retirement model and its
tutorial. Validate availability, positivity and material balance; actual
scaled-unit values; native unknown versus observed-output initialization;
shared batch snapshots; compound events and capacity; runtime history and
off-cadence held-value restore; late failure with clocks/RNG unchanged.
Use sequential CPU as the complete reference workflow. Checkerboard/native and
Metal combinations need their own complete positive/negative cases.
Root-localized events, SDE/jumps and different field grids are not hidden here.
G07 can proceed alongside G06 because this reference workflow does not require
new spring-energy closure.

**G08 — Scientific use and inspection.** R17 assembles the broader mechanism
corpus and progressive modification/extraction tutorials through public
interfaces already exercised by earlier owner examples. Include explicit
mask/label-data initialization and scientific assumptions. R18 integrates
source-to-failure explanation, retained quantity references, lineage, low-memory
statistics and recording sinks; R19 consumes those public protocols for
structured rendering and inspection. Test diagnosis/repair, ambiguous/missing
saved references, stale identities, recorder failure policy and observation/RNG
noninterference. Keep one tutorial source; do not copy scientific implementations
into rendering tests. Core failure information needed here should be included
where it is produced in G06/G07, or receive an explicit companion if missing.

**G09 — Measurements.** R20 adds reproducible public-model benchmark scenarios
and documentation covering load, construction, compilation, first/warm step,
remake, source-update fan-out and capacity scaling. Profile throughout G04–G08;
G09 consolidates the usable measurement workflow, not the first opportunity to
discover a problem. Actual Potts/Core performance fixes are absorbed into
appropriate open PRs or counted as new owner PRs when warranted. No brittle
machine-time acceptance threshold or claim that measurements alone optimize code.

## 3. Breadth PRs

| Group | Planned repository PRs | Depends on | Previous scope |
| --- | --- | --- | --- |
| **E01 Three-dimensional CPM** | R21 Core; R22 Potts | G06, G07 | B1 |
| **E02 Equilibrium and fluctuating mechanical components** | R23 Core; R24 Potts; R25 Models | G01, G06, G07 | B2 |
| **E03 Directed and anchored relationships** | R26 Core; R27 Potts | G06, G07 | B3 endpoint contracts |
| **E04 Containment and compartment modeling** | R28 Core; R29 Potts; R30 Models | G08, E01, E02, E03 | B3 containment + related model library |
| **E05 Localized native events** | R31 Potts | G07 | B4 deterministic events |
| **E06 Stochastic native integration and intracellular models** | R32 Potts; R33 Models | G08, E05 | B4 SDE/jump laws + model library |
| **E07 Multispecies fields and conservative cross-grid exchange** | R34 Potts; R35 Models | E01, E06 | B5 |
| **E08 Global morphology and exact topology contracts** | R36 Core; R37 Potts; R38 Models | G06, G07, E04, E07 | B6 |
| **E09 CUDA integration and conformance** | R39 LocalMath; R40 Core; R41 Potts | G08, E01 | B7 CUDA |
| **E10 ROCm integration and conformance** | R42 LocalMath; R43 Core; R44 Potts | G08, E01 | B7 ROCm |
| **E11 Conservative swap transitions** | R45 Core; R46 Potts | G07, E02 | B8 swap/multisite move law |
| **E12 Static weighted-graph CPM domains** | R47 Core; R48 Potts | G05, G06, G07, E11 | B8 non-Cartesian domain + graph swap |

Dependencies are completion dependencies for the entire group. Some are
intentional integration joins: E04 combines 3D, mechanics and compartment
tutorials; E07 tests 3D transfer and an admitted stochastic/native chemistry
consumer; E08 closes selected morphology/compartment/field interactions.
The underlying engine subtask may start earlier, but the group is not complete
until its named public interactions pass. No bundle waits on its own downstream
consumer, and no graph edge means two agents must edit the same checkout.

### Complete breadth outcomes

**E01 — 3D (R21–R22).** Core adds the complete regular-3D ownership/proposal,
geometry, lifecycle and supported device path; Potts adds declaration,
initialization, field/native/observation binding and admission. Use ordinary
public 3D examples and unchanged dimension-generic model factories where
applicable. Exercise selected CPU and actual Metal 3D field/native/division
combinations. This does not qualify every global topology algorithm in 3D.
Makie already has public 3D frames/slicing/volume rendering; do not add a Makie
PR unless its actual protocol needs to change.

**E02 — Mechanical families (R23–R25).** Core/Potts implement an explicitly stated
equilibrium auxiliary sampling law and its probability/initialization contracts.
Models implements the corresponding factories plus separately named
nonequilibrium OU pressure/tension components using G04/G07 addressed draws and
state/process/lifecycle laws. This library consolidation does not conflate
equilibrium and driven mechanics: use independent distribution/balance tests
for the former and stochastic response/correlation tests for the latter.
No new Core/Potts implementation is presumed necessary for the OU model;
a missing real primitive triggers a companion rather than hidden host RNG.

**E03 — Rich links (R26–R27).** Extend actual endpoint, payload, relation,
identity/lifecycle and conflict meaning for directed cell links and fixed
anchors. Public owning-package examples cover directed exchange and anchored
springs, including removal, division and parallel conflicts. Do not create a
new Models PR solely to repeat these fixtures.

**E04 — Compartments and their model library (R28–R30).** Core/Potts add explicit
containment and coordinated compartment lifecycle. Models adds the related
directed-link/spring/nucleus–cytoplasm factories and tutorials together.
Exercise conservation, lineage, endpoint updates, late failure, and the chosen
3D compartment-division and mechanical combination. Fusion is not inferred
from division: its conditional status is listed below.

**E05 — Native events (R31).** Potts adds root localization, latching, timestamped
delivery at declared CPM boundaries, reinitialization and request arbitration
using G07 public settlement. Test a root near a boundary, off-tick division,
competing requests and restore. If Core needs a new settlement contract, add
that public companion; do not call private lifecycle mutation routines.

**E06 — Stochastic native integration (R32–R33).** One Potts PR reuses common
native IO, pool, RNG-ownership and settlement infrastructure for separately
defined SDE and jump methods. Each has its own numerical interpretation,
state/event/solver admission, scientific tests and restart limits. Models adds
the related intracellular components and native-event tutorials together.
Do not force two unrelated implementations into R32: split it and update the
count if the implementation does not actually share a coherent boundary.
Initial support names actual CPU solver profiles; GPU stochastic/event support
is not inherited automatically from ODE or vendor support.

**E07 — Fields (R34–R35).** Potts adds fixed cross-grid bindings and explicit
sampling/deposition, scale, availability and conservation contracts using
prepared publication. Models supplies multispecies/nonlinear same-grid
chemistry and a cross-grid exchange model in the same field-library PR.
Exercise nonnegative material accounting, boundaries, selected 3D transfer and
a specifically admitted native stochastic/reaction combination. Cross-grid
storage/publication missing from Core or LocalMath requires its actual owner
companion. Dynamic remeshing is not included.

**E08 — Morphology/topology (R36–R38).** Core/Potts implement one owned global
invariant algorithm and public access contract. Both sampled measurements and
exact proposal constraints use that mathematics through distinct timing and
evaluation methods. Models adds the matching components and explanatory
models, including selected 2D compartment/field interactions. Specify digital
foreground/background adjacency and test connectivity/hole cases against a
tiny independent scan. Exact proposal support begins with its stated CPU law;
sampled measurement is not a substitute for exact acceptance. Do not assume
G07 scheduled publication provides arbitrary global algorithms or host
callbacks; R36/R37 contain the missing real algorithm. 3D/parallel topology
needs separately demonstrated scientific scope.

**E09/E10 — CUDA/ROCm (R39–R44).** For each vendor, LocalMath owns mathematical
real-device environments/conformance; Core owns adaptation, lifetime,
admission and execution integration; Potts owns public backend integration
and model-level tests/docs. Start from existing Adapt/KernelAbstractions
interfaces, not a presumed need for a new vendor executor. The present
LocalMath project is backend-generic and has no vendor extension directory.
Run public structured-state, relation/aggregate, rollback, checkpoint and
selected 3D/native combinations on the actual device. State numerical/replay
limits. Reuse unchanged Models factories as downstream consumers without
inventing a model implementation PR. Actual supported hardware/toolchains are
prerequisites; CPU checks or another vendor's results cannot substitute.

**E11 — Moves (R45–R46).** Core/Potts add a concrete conservative swap
proposal/acceptance law, normalization, compound ownership effects and
dependency maintenance. Reuse E02 probability-accounting machinery where its
meaning agrees. Test reverse probabilities, conserved occupancy, failure and
conflicts with public fixtures. A two-site move is not a claim that arbitrary
multisite programs are supported.

**E12 — Domains (R47–R48).** Core/Potts add a concrete static finite undirected
weighted-graph domain: site measures, interface weights, proposal law, boundaries,
initialization and supported geometry with explicit embedding where needed.
Include the actual swap-on-graph interaction now that E11 exists. This is not
arbitrary evolving meshes or automatic graph-native PDE/GPU support. A missing
reusable LocalMath graph law or new rendering protocol gets a real companion.

### No uncounted model-library or compatibility tail

The five breadth Models PRs are R25, R30, R33, R35 and R38. Each bundles related
scientific factories, tutorials and composition tests. Earlier upstream PRs
already have executable public examples; these library PRs do not excuse missing
authoring or defending tests there.

The omission of Models from E01/E09/E10/E11/E12 assumes the relevant existing
factory remains correct without implementation changes. Verify that assumption.
If a real model change is needed, absorb it into a related still-open Models
PR with that dependency, or add and count a Models companion. Do not silently
claim a later compatibility/tutorial PR is free.

Likewise, a later feature introducing a new supported conjunction owns that
conjunction's test in its actual PR. If the needed consumer repo is already
closed and must change, count that companion. The dependency map is not an
excuse to omit new-vendor tests from later changes to a supported device path.

## 4. Dependency graph and agent scheduling

The graph below is the enumerated group dependency graph. The tables above
give the actual repository members; one graph node is not necessarily one PR.

```mermaid
flowchart TD
  G01["G01: Ecosystem workspace and CI"]
  G02["G02: Potts construction and operational ownership"]
  G03["G03: Core scientific-context ownership"]
  G04["G04: Structured authoring and component identity"]
  G05["G05: Maintained quantities and relational mathematics"]
  G06["G06: Conservative energy and parallel dependencies"]
  G07["G07: Native transport and lifecycle composition"]
  G08["G08: Model corpus, observation and scientific inspection"]
  G09["G09: Reproducible authoring and runtime benchmarks"]
  E01["E01: Three-dimensional CPM"]
  E02["E02: Equilibrium and fluctuating mechanical components"]
  E03["E03: Directed and anchored relationships"]
  E04["E04: Containment and compartment modeling"]
  E05["E05: Localized native events"]
  E06["E06: Stochastic native integration and intracellular models"]
  E07["E07: Multispecies fields and conservative cross-grid exchange"]
  E08["E08: Global morphology and exact topology contracts"]
  E09["E09: CUDA integration and conformance"]
  E10["E10: ROCm integration and conformance"]
  E11["E11: Conservative swap transitions"]
  E12["E12: Static weighted-graph CPM domains"]
  G02 --> G04
  G03 --> G04
  G04 --> G05
  G05 --> G06
  G01 --> G07
  G05 --> G07
  G01 --> G08
  G06 --> G08
  G07 --> G08
  G08 --> G09
  G06 --> E01
  G07 --> E01
  G01 --> E02
  G06 --> E02
  G07 --> E02
  G06 --> E03
  G07 --> E03
  G08 --> E04
  E01 --> E04
  E02 --> E04
  E03 --> E04
  G07 --> E05
  G08 --> E06
  E05 --> E06
  E01 --> E07
  E06 --> E07
  G06 --> E08
  G07 --> E08
  E04 --> E08
  E07 --> E08
  G08 --> E09
  E01 --> E09
  G08 --> E10
  E01 --> E10
  G07 --> E11
  E02 --> E11
  G05 --> E12
  G06 --> E12
  G07 --> E12
  E11 --> E12
```


### Four-slot execution policy

Use the root as coordinator/integrator and at most three bounded workers:

1. Upstream semantic implementation.
2. Downstream public authoring/model consumer.
3. Independent scientific tests, documentation and review.

Roles rotate with the work. For independent early tasks, the three workers
can own G01, G02 and G03. For G04/G05, use a Core owner, a Potts owner and an
independent reviewer. After G05, one worker can own the G06 bundle and another
the G07 bundle in isolated worktrees, with the third reviewing/testing; the
root serializes integration on overlapping repositories. Later select only
ready graph nodes and avoid more simultaneous implementations than the team
can independently review.

Each active repository task uses its own worktree and task-specific development
environment. Give one writer ownership of each responsibility/file set. Agree
the actual shared public interface with its first concrete consumer before
workers implement opposite sides; do not let separate agents invent competing
contracts. Record current dependency selections and links in ordinary PR
descriptions, not a new project-management or qualification system.

Semantic dependency does not imply an exclusive editing order. Conversely,
two independent PRs touching the same repository still need normal rebasing and
integration. Agent-local green tests do not establish the integrated result.
Before starting actual work, recheck the sibling mains, repository instructions,
loaded Julia paths and pre-existing changes. This older checkout remains the
planning workspace, not the package implementation baseline.

### CI and merge process

- During edits, use focused owning tests and small public consumers; cancel
  superseded CI. Budget Julia compilation/test workers separately from agent
  slots, and serialize competing jobs on one real device.
- For the integrated final candidate, run each changed owner's full ordinary
  suite, strict relevant docs, affected public integration, and applicable real
  GPU/replay tests. Select from the whole PR diff and changed sibling revisions,
  not merely the latest commit.
- One concrete reviewed dependency selection connects companion PRs. Reuse
  results only when source, dependencies and the relevant execution profile
  still match; caching never substitutes for a new result after a meaningful
  change.
- Prepare every required consumer before a direct cutover. When authorized to
  publish/merge, use normal version/compat bounds and upstream-first ordering:
  LocalMath → Core → Potts → Models/Makie. Revalidate affected results after
  merge/squash changes the selected revisions. G01's Models extraction needs
  the new public model location available before removing its old owner.
- Independent mains cannot change atomically. Supported package resolutions
  must remain coherent; do not bridge the merge window with compatibility
  aliases, old/new selectors or a second implementation.
- Missing hardware, unresolved scientific choices or missing publication
  authority are explicit blockers, not reasons to mark a group complete.
  The map itself opens no PR, creates no remote repository and grants no merge
  or release authority.

Probe CUDA/ROCm/Metal resource availability early while G01–G05 proceed.
Vendor implementation can begin on stable main-spine contracts; E09/E10's full
declared model validation still waits for their graph prerequisites. This
avoids discovering unavailable hardware only at the end.

## 5. Coverage: nothing disappears inside consolidation

| Original obligation | Delivery owner(s) |
| --- | --- |
| P01–P02 package/dev/CI | G01 |
| P03/P05 Potts readability and operational ownership | G02 |
| P04 Core context/geometry ownership | G03 |
| P06–P07 structured values, scope, compound effects | G04 |
| P08–P09 relations, maintenance and geometry | G05 |
| P10 energy and parallel conflict closure | G06 |
| P11 composition | G04 identity/imports/replacement; G05 derived consumers; G08 complete library workflows |
| P12–P13 native/field/lifecycle | G07 |
| P14–P15 corpus, diagnostics, observation | G07 focused model; G08 broader use/inspection; feature-local docs/errors in every earlier group |
| P16 performance | Early owner measurements/fixes; G09 reproducible corpus; counted owner companions when needed |
| B1 | E01 |
| B2 | E02 |
| B3 | E03–E04 |
| B4 | E05–E06 |
| B5 | E07 |
| B6 | E08 |
| B7 | E09–E10 |
| B8 | E11–E12 |

| Easily lost cross-cutting requirement | Explicit home and defending case |
| --- | --- |
| F1 component composition | G04/G05/G08; two independent instances share one input; explicit replacement and typo/default errors |
| F2 value shape, units and precision | G04/G07; fixed vectors/tensors/products and integer counts; real scale conversion at native boundaries |
| F3 scientific neighborhood meaning | G05/E03/E12; repeated bonds, distinct cells, weights, direction and absent/empty cases |
| F4 history and maintained values | G04 history; G05 live maintenance; G07 off-tick sample/history/native restart |
| Non-invertible statistics and floating drift | G05 supported rebuild/retraction contract, removing current minimum, accumulator/order/rebuild tests |
| Parameter-triggered invalidation and update fan-out | G05/G09; remake a derived parameter, update an entire field without ownership changes, measure scaling |
| F5 energy versus drive | G06/E02/E11; full-system deltas, reverse probabilities, and opposite-endpoint conflicts |
| F6 process/publication timing | G04/G07/E08; simultaneous versus sequential effects, global algorithm publication, late failure |
| F7 native scope/IO/initialization | G07/E05/E06; actual unknown versus observed output, shared snapshots, roots and distinct stochastic laws |
| F8 fields/material accounting | G07/E07; extensive pools, nonnegative finite transfer, cross-grid scales and separate sample/deposit meaning |
| F9 identity and lifecycle | G04/G07/E04; creation/division/retirement/transition, generation reuse, lineages, capacity and cross-component rollback |
| F10 relationships/compartments | G05/G06/E03/E04; payloads, incident energy, containment and endpoint lifecycle |
| F11 process and lifecycle randomness | G04/G07 component-addressed draws and rollback; E02/E06 add distinct mechanical/SDE/jump laws |
| F12 dimension/global algorithms | E01/E08/E12; stated 3D, digital adjacency and graph-domain meanings, with explicit unsupported profiles |
| F13 observations/experiments/persistence | G04/G07/G08; retained refs, ordinary SciML ensembles, low-memory statistics and recorder IO failure/noninterference |
| Mask/image/data initialization | G01/G04/G08; tiny local label/mask input with coordinate/scale/overlap validation, no hidden downloads |
| F14 useful diagnostics/edit loop | G02 onward; source-local failure/repair and ordinary remake versus source rebuild |
| F15 readability/compilation | G02/G03 plus owner source maps in each change; G09 measured costs, no incidental-layout tests |
| F16 hardware/profile conjunctions | Every changed execution owner; E09/E10 add vendors, not blanket compatibility guarantees |

Existing supported science is preservation input: activity, connectivity,
current field Euler and MethodOfLines paths, native solver choices, sequential
reference execution, generations and SciML ensembles must not disappear because
their new generalizations occur later.

At least these complete interactions have named owners: structured late-failure
publication (G04); field → aggregate → ODE → division → restore (G07); incident
spring conflicts (G06/E03); 3D native/field/division (E01); 3D compartment
mechanics (E04); native events/stochastic lifecycle (E05/E06); 3D cross-grid
chemistry (E07); 2D global morphology with compartment/field changes (E08);
actual vendor-selected models (E09/E10); graph swaps (E12).

No finite suite proves every Cartesian product of dimension, topology, solver,
precision, algorithm, model family and hardware. Each claimed conjunction
gets its own appropriate evidence; excluded combinations get precise admission
behavior. Additional scientifically distinct moves, domains, PDE solvers or
topological guarantees are not automatically delivered by one representative.

## 6. Count risks and explicitly unpriced work

### Conditional owner PRs, not silently omitted features

| Discovery | Action before declaring the group complete |
| --- | --- |
| Structured storage/gather/publication needs a missing reusable LocalMath law | Add a LocalMath companion to G04/G05 at its first real consumer |
| G08 needs failure information not already exposed by G06/G07 | Add a Core companion, or include the fact in its still-open owning PR |
| Profiling identifies a material Potts/Core defect | Fix in a coherent open owner PR or count a measured optimization PR; G09 measurement alone is insufficient |
| 3D or graph results need a new public rendering protocol | Add Makie; existing 3D support is inspected first, graph rendering is not presumed |
| OU mechanics cannot use actual prepared process/RNG contracts | Add the real Core/Potts public primitive; no hidden host callback or RNG |
| Directed, 3D, global or graph traversal requires a missing LocalMath operation | Add the owning reusable law with its first real consumer, not one adapter per model |
| Native event or stochastic settlement needs a new Core contract | Add the necessary companion; share one boundary only when meanings actually agree |
| Native SDE and jump integrations do not form a coherent common implementation | Split R32; this adds one Potts PR, with no change in scientific scope |
| Different-grid exchange needs new Core storage/transaction or LocalMath transfer support | Add the actual owner companion; a Potts constructor cannot substitute for missing execution |
| A supposedly unchanged Models factory actually needs a dimension/backend/move change | Include it in a dependent open library PR or add and count a Models companion |

These are not pre-created placeholder PRs and do not form a guaranteed numerical
upper bound. The planned **48** counts the identified base work; discoveries
can increase it. Absorb a required change only where it belongs coherently and
before that PR closes. Do not expand another PR solely to preserve the headline
count, omit needed work, or move an engine fact into Models.

### Mentioned but not fully scoped projects

The following were explicitly conditional or deferred in the prior plan and are
**not claimed complete by these 48 PRs**:

| Project | Likely ownership and prerequisite | What must be decided first |
| --- | --- | --- |
| Settled capacity growth | Core/Potts after G07 and measured workload | Resizing pools/relationships/history atomically, identity and checkpoint behavior |
| Cell fusion/merge beyond division | Core/Potts/Models after E04 | Conserved pools, native merging, lineage and relationship arbitration |
| Fitting and inference | Application/Models integration over G08/G09 | Statistical objective, parameterization, estimator and stochastic treatment; no blanket pathwise-gradient promise |
| SBML or other model interchange | Optional adapter over G07/E06 | Exact format/features, units, events and initialization preservation |
| Dynamic remeshing | Domain/solver owners after E07/E12 | Geometry evolution, conservative transfer and topology/identity semantics |
| Hybrid off-lattice mechanics | New scientific coupling work after E03/E07 | Force/contact law, time coupling, ownership and numerical reference |
| Multi-device domain decomposition | LocalMath/Core/Potts after stable single-device profiles | Real workload/hardware, halo/identity/conflict/commit and continuation contracts |

Broad goals such as every model or every combination are not finite acceptance
criteria. New concrete requirements from this list require explicit scopes and
additional counted work; clean extension boundaries do not implement them.

## 7. Start order and completion boundary

Start with G01, G02 and G03 in separate worktrees, then deliver G04 and G05.
Branch into G06/G07; close G08 and the usable G09 measurement workflow while
starting ready breadth groups. E01 and E02 are high-priority breadth because
3D and mechanical families are charter goals. Native, relationship, field and
domain work then follows the graph rather than a fixed numerical PR sequence.

Before assigning a group for implementation, instantiate its actual public
interface and scientific witness from the referenced spec; resolve concrete
solver/law/hardware choices rather than allowing competing agent inventions.
This document is the delivery dependency map, not a frozen full implementation
specification for every research-dependent breadth algorithm.

The complete defined delivery means all base groups and any required companions
have their implementation, public use, ordinary validation and direct cutovers
finished, with supported profiles stated accurately. Review-ready, merged, and
released remain different states. The eventual execution instruction must set
that authority/finish line; this map does not infer it.
