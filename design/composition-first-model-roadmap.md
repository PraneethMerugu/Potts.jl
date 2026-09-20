# Composition-first roadmap for the fourteen model witnesses

Prepared 2026-09-10. Status: accepted by the user on 2026-09-10, including the
four additional deliveries and confirmed COBREXA.jl dependency. This is scope
acceptance, not implementation evidence or new publication/merge authority.

## Accepted direction

Keep the existing spine and breadth commitments, strengthen their composition
contracts, and explicitly deliver the fourteen models in PottsModels. The user
accepted four additional repository PRs: R51 Potts metabolic integration, R52
Models FBCA, R53 Models vascular corpus, and R54 Models multiscale tumor corpus.
The canonical allocation is **69 identified PRs: 54 planned + fifteen companions**.
The all-in repository totals are Potts 22, CorePotts 17, LocalMath 15,
MakiePotts 2 and PottsModels 13. This is not a verified ceiling; R01–R50 retain
their identities.

Only the metabolic pair represents clearly additional integration functionality.
The two paper-corpus PRs separate substantial scientific implementation/review
from R35's field-library integration. The user accepted those separate deliveries;
the earlier 58-PR bundling alternative is not the selected allocation. Do not make
PR count an acceptance criterion.

The [canonical map](consolidated-pr-dependency-map.md) owns the current
69-PR allocation, R51–R54/E13–E16 identities and dependencies. The [compiler amendment](compiler-contract-chain-amendment.md)
remains accepted; [progress](pr-chain-progress.md) owns implementation status.
R01–R07 and twelve completed companions are now recorded merged;
the G07 ordered-fold validation companion C07 is LocalMath
PR18 and its complete hosted suite passed after merge. The G05 exact
keyed-reduction companion C08 is LocalMath PR19, merged as `7082ed84`, and
precedes Core R10/Potts R11 relation-query completion.
The R10 consumer additionally demonstrated C09, a narrow LocalMath atomic
keyed-rebuild publication law, merged as LocalMath PR20; it also precedes
R10/R11 completion.
The maintained-query audit additionally demonstrated C10/C11: CorePotts and
Potts must establish durable fixed-exterior/obstacle domain ownership and
mutable-site semantics before R10/R11 can claim the accepted wall/domain query
surface. C10 replaces/extends the existing owner authority rather than adding a
second decoder; C11 migrates current `FrozenBorder` no-flux consumers to
`Closed` before deleting that ambiguous spelling, never reinterpreting it as a
fixed owner. These two companions are identified but not implemented.
C12 is the merged LocalMath bounded runtime collection-launch cutover at
`12b3fa98`; it keeps extent/capacity as runtime `ndrange` data across the shared
collection families and specializes only on their semantic workgroup. It adds no
model/compiler path and changes none of the composition ownership below.
C13 is the merged LocalMath direct source-order recurrence law at `dd5d2e0`;
it removes canonical sorting machinery only where `SourceOrder` does not
consume it. C14 is the merged provider-settlement law in LocalMath PR23 at
`a26cbfe`: compact program-level validation payloads, nonempty blocking copy
completion, explicit empty/alias synchronization and exact receipt failure
ownership. C15 is the separately demonstrated pointwise temporary-identity
segmentation boundary after C14: one small graph-aware wrapper extracts the
runtime temporary-identity set, and the reusable semantic segmentation law
receives only that set. It preserves the bounded pointwise laws and one
KernelAbstractions path without a cache, retained table, second graph
representation or executor. LocalMath PR24 has now merged as `a1d60d1a`, with
green Potts 99/99 and
downstream Metal Core checkerboard 83/83 plus continuation 116/116 canaries.
At observation, hosted `changes`, `macos-smoke`, `docs` and `scientific` are
green; `package` and `metal` are pending, and conditional `macos-package` is
skipped. LocalMath `main` now requires pull requests with zero approving
reviews, enforces protection for administrators, and uses strict required
checks `changes`, `package`, `scientific`, `macos-smoke`, `docs` and `metal`.
The [exact KA audit](localmath-kernelabstractions-audit.md)
records the earlier C13/C14 owner-law evidence.
G04 onward is incomplete,
with active candidates. This amendment does not reopen merged work or
change another worker's candidate interfaces. Implementation must inspect the
current sibling mains/candidates, not treat this older planning checkout as main.

## 1. Scientific scope and corrections

The rows below retain the conversation's numbering. They identify requirements,
not fourteen completed paper reproductions. OpenVT entries are reference-model
classes rather than uniquely specified papers. Full methods were accessible for
Merks 2008, Bauer 2009, Jafari Nivlouei 2021, and the compartment-migration
papers; several other entries were checked through primary abstracts, indexed
methods, and reference-model descriptions. In particular, foam, FBCA, segmented
rods, and the 2026 invasion paper still need the equation/code checks specified
below. Do not fill these gaps with plausible-looking authoring syntax.

| # | Selected model and primary source | Required scientific composition and important boundary |
|---|---|---|
| 1 | [Merks et al. 2008, contact-inhibited chemotaxis](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1000163), including its [correction](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1004163) | Adhesion/size mechanics, autocrine field production/diffusion/decay, and interface-dependent chemotactic drive. Preserve the selected extension/retraction response. This is the user's extension, not an automatic substitution of the 2006 elongation model. |
| 2 | [OpenVT monolayer growth](https://www.openvt.org/pages/working-groups/reference-models-wg.html) | Growth, division and mechanical exclusion starting from one cell. The reference specifies neither signaling nor cell-cell adhesion. An exposure-controlled growth law is a separate variant, not its definition. |
| 3 | [OpenVT single-cell migration](https://www.openvt.org/pages/working-groups/reference-models-wg.html) | Biased stochastic motility, with no signaling required. Fix the selected bias/persistence process before calibration. Preserve the existing activity-memory model as an additional composition witness; do not silently replace this entry with Wortel/Act migration. |
| 4 | [Jiang et al. 1999, foam hysteresis and avalanches](https://journals.aps.org/pre/abstract/10.1103/PhysRevE.59.5819) | Interface and area terms, prescribed loading, the paper's attempted-move/acceptance law, and rheological measurements. Equilibrium auxiliary mechanics or OU fluctuations alone do not reproduce driven foam. Full proposal normalization and loading transcriptions remain required. |
| 5 | [Bauer et al. 2009, ECM topography and angiogenesis](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1000445) | Chemical guidance, heterogeneous matrix/tissue interactions, matrix degradation, and endothelial growth/migration. Branching should emerge from the stated interactions, not an invented branching command. Preserve which cells degrade which matrix sites. |
| 6 | [Jiang et al. 2005, avascular tumor growth](https://pubmed.ncbi.nlm.nih.gov/16199495/) | 3D CPM, intracellular Boolean cell-cycle regulation, extracellular nutrient/waste/growth-signal fields, phenotype-dependent growth and death. Resolve the complete field equations, thresholds, network update schedule and necrotic-state treatment from the methods, not a generic tumor factory. |
| 7 | [Bauer et al. 2007, tumor-induced angiogenesis](https://laro.lanl.gov/esploro/outputs/journalArticle/A-Cell-Based-Model-Exhibiting-Branching-and/9916363433903761) | Pro-angiogenic field diffusion/uptake/decay, endothelial migration/growth/division, and heterogeneous stroma. Branching and anastomosis are emergent in this model; neither implies a prescribed branch event or biological-cell fusion. |
| 8 | [Graudenzi, Maspero and Damiani 2020, FBCA](https://boa.unimib.it/handle/10281/255735) | Spatial CPM plus per-cell flux-balance metabolism and crypt population dynamics. A steady-state constrained optimization is not an ODE. The detailed metabolic network, environmental coupling, phenotype rules and recurrence experiment require the full paper/model assets before a reproduction claim. |
| 9 | [OpenVT sorting reference](https://www.openvt.org/pages/working-groups/reference-models-wg.html), in the Graner–Glazier CPM family | Two populations, differential adhesion, size control and stochastic copies. State the chosen Chaste/OpenVT initialization and parameter convention; a visually similar sorting image is not cross-framework equivalence. |
| 10 | Akeeb, Marcus and Jiang, *Clusters, fingers, and singles: A mechanical landscape of tumor invasion*: [identified 2026 DOI](https://doi.org/10.1371/journal.pcbi.1014747), [author preprint](https://doi.org/10.1101/2025.11.20.689434) | Leader/follower invasion and mechanical parameter experiments, with cluster/finger/single-cell measurements. The final publisher methods could not be retrieved in this review. Author identity/title are resolved; exact law and final-paper/preprint differences remain unverified. Do not claim an exhaustive parameter-landscape reproduction. |
| 11 | [Jafari Nivlouei et al. 2021, tumor growth, angiogenesis and targeted therapy](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1009081) | Boolean receptor/pathway regulation, nutrient and VEGF reaction–diffusion, tumor/host/endothelial interactions, phenotype and treatment changes. Not the previously illustrated receptor ODE. Vascular geometry is not by itself a hemodynamic flow solver. |
| 12 | [Zajac, Jones and Glazier 2003, convergent extension](https://pubmed.ncbi.nlm.nih.gov/12727459/) | Anisotropic differential adhesion dependent on cell orientation/shape. Full candidate geometry and energy dependencies matter. The paper does not require adding active polarity to make extension happen. Verify the exact contact/orientation formula in the implementing PR. |
| 13 | [Starruß et al. 2007, collective migration of myxobacteria](https://link.springer.com/article/10.1007/s10955-007-9298-9) | Segmented rod shape/stiffness, active motion and exclusion. Pair springs alone do not establish the bending law. Verify ordered segment dependencies, end conditions and group identity; this is not necessarily geometric containment. Diffusive signaling is not a requirement. |
| 14 | [Fortuna et al. 2020, compartmental migration](https://pmc.ncbi.nlm.nih.gov/articles/PMC7264849/), with the [Dal-Castel et al. chemotaxis preprint](https://arxiv.org/html/2312.00776v1) | 3D nucleus/cytoplasm/lamellipodium, substrate contacts, protrusive drive and stochastic compartment-site conversion. Keep the base and extension as explicitly distinct scientific variants. The extension adds spatial sensing and retained volume history; it is not just an extra chemotactic force. |

Two details of #14 materially reduce speculative scope. The 2020 field source
is substrate-contact dependent and the methods acknowledge small field leakage
removed by decay; imposing moving impermeable boundaries changes that model.
The extension describes a discrete actin indicator and a history-controlled
conversion response: do not automatically copy the base PDE into it. Resolve
zero-variance sensing, equality in the history switch, and history warm-up from
the source implementation before declaring numerical behavior. Neither variant
justifies silently adding an exact 3D nuclear-enclosure constraint.

## 2. Architecture to commit to

**Scientific models are compositions, not compiler cases.** PottsModels owns
biological equations, parameter sets, initializers, experiments and scientific
analysis. Potts owns symbolic authoring, validation, composition and lowering.
Core owns CPM identity, transitions, acceptance and settlement. LocalMath owns
reusable spatial/publication mathematics and shared KernelAbstractions execution.
MTK/SciML/MethodOfLines and the metabolic solver stack keep their native numerical
ownership. That does not mean external ODE or LP solvers execute inside CPM's
KernelAbstractions kernels.

The useful reusable contracts are:

1. Scoped component identity, parameters, structured state, initialization and
   ordinary constructor equivalence.
2. Relations, geometry and quantities, including contact-weighted versus
   distinct-neighbor sensing, candidate reads and retained history.
3. Conservative energy, nonequilibrium proposal drive and exact proposal
   constraints as different meanings, with transitive conflict dependencies.
4. Accepted-copy effects, scheduled processes and lifecycle settlement, including
   bounded compartment-site reassignment where demonstrated by #14.
5. Native systems with explicit bindings, units, cadence, solver ownership,
   initialization, publication and failure behavior.
6. Field sampling/deposition with explicit measures and material availability.
7. The concrete mechanical relationship and optimization boundaries demonstrated
   by rods and FBCA, rather than speculative general-purpose frameworks.

These are refinements of existing owners, not seven new intermediate
representations. A new abstraction must remove duplicate authority or serve a
demonstrated consumer. Reusable biological helpers may have scientific names;
their implementation must expand into ordinary public composition, without a
privileged runtime operation recognizing the helper or the paper.

The execution-facing refinement is common to every composition:

```text
authoring → semantic analysis → validated normalization → operational recipes
→ narrow typed state views → small concrete kernels
```

PottsModels never owns a parallel compiler or executor. Its models are demanding
public workloads that prove rich host semantics normalize into reusable Potts/
Core/LocalMath operation families. Package factories and interactively assembled
equivalents must converge before the prepared boundary; paper names, component
names and source locations remain diagnostics rather than specialization facts.

### ModelingToolkit-like, without fake compatibility

R09 should deliver named nested components, shared symbolic parameters, ordinary
equations where equations apply, structural arguments separated from numerical
parameters, and direct references for bindings/inspection. Component assembly
should enroll declarations once; users should not maintain parallel inventories.
R15 supplies the corresponding native composition, not a second hierarchy of
translated MTK equations.

Upstream's [MTK language documentation](https://docs.sciml.ai/ModelingToolkit/stable/basics/MTKLanguage/)
establishes component-oriented authoring, but is not proof that its macros
already accept every Potts statement. Check the supported upstream extension
surface on the actual dependency range. Prefer that surface; otherwise keep a
small Potts authoring layer over the same constructors. Do not fork the MTK
parser or manufacture unsupported `@mtkmodel` syntax in documentation. A needed
upstream change is a separately counted external contribution, not an assumed
free dependency.

## 3. Changes to existing PRs

Every row below is an accepted scope clarification/extension, not a status update.
Share concrete candidate interfaces with active owners before incorporating it.

| Existing delivery | Required change or explicit preservation |
|---|---|
| G01–G03 / R01–R07 | Preserve merged extraction and ownership preparation. Inspect actual active Models consumers before removing remaining special operations. No repeat extraction PR. |
| G04 / R08–R09 | Make MTK-like composition an executable authoring requirement. Exercise nested repeated instances, parameter sharing, lexical scope, typed state/units, history, compound effects and addressed process randomness. Boolean regulation uses ordinary state/process expressions with an explicit update law, not a Boolean compiler subsystem. |
| G05 / C10–C11 / R10–R11 | Establish durable fixed-exterior/obstacle owners and the authoritative mutable-site attempt set before completing the explicit `over=...` spatial-query surface. Defend neighborhood geometric means/zero behavior for activity, geometry-dependent adhesion, substrate-restricted moments and sensing, source-aware matrix updates, and multiple consumers of shared quantities. Keep existing maintained-minimum and numerical obligations. Preserve explicit checkerboard rejection for unsupported moment, shared-owner, relationship and derived-dependency conjunctions until G06 proves complete closure; do not partially admit or add a temporary path. Only add missing reusable mathematics in its true owner. |
| G05C / R49–R50 | Keep the accepted pair and strengthen its downstream canaries. Add actual model-derived cases to the existing criteria: geometry-dependent contact energy and field/history consumption. The G06 canary must carry an immutable batch snapshot plus enough normalized transitive dependency/effect identity to reject an apparently site-disjoint periodic/shared-owner/relation conflict while preserving shared-read and owner-proven commutative/associative compatibility, without retaining or interpreting the author graph. R49 establishes canonical Core executor identity across author-only renames, numerical value changes and bounded entry-count ladders; R50 removes author identity/irregular graph structure before that boundary and proves package-declared and interactive compositions share it. No third compiler rewrite, model tag, retained builder graph or parallel dependency authority. |
| G06 / R12–R13 | Primary owner of complete checkerboard conflict closure. Demonstrate ordinary activity and chemotaxis drives, anisotropic contact energy and coupled mechanical deltas. Evaluate each batch from one immutable entry snapshot and derive complete transitive footprints including periodic aliases and shared logical owners. Read/read overlap is compatible; incompatible read/write, write/write and noncommuting effects arbitrate; owner-proven commutative/associative effects may share. Choose deterministic backend-independent winners, admit independent proposals, and atomically commit/roll back each winner. Distinguish scheduled attempts, non-no-op proposals, losers and winners: no no-op/loser/reject mutates state or receives a compensating attempt. Preserve declared semantic RNG addressing and unrelated-stream invariance without asserting unused draws; use realized color-fraction time. Include shared-read and commutative positive controls, exact shared-owner conflicts, and periodic-moment gauge cases with identical physical observables/energies/closure/winners and gauge-equivalent state; require raw identity only for a unique G05 gauge. Core R12 owns evaluation/arbitration/commit on the single CPU/GPU KernelAbstractions path; Potts R13 owns conservative analysis, admission and source-linked diagnostics. Sequential/full-state evaluation is only an isolated-winner oracle, not a checkerboard trajectory or kinetics oracle. Atomically delete G05 rejection only for qualified conjunctions. These are semantic outcomes, not a prescribed graph, coloring or data structure. |
| G07 / R14–R16 | Complete native expression/structured IO, reciprocal field feedback, native unknown/observed initialization, explicit physical-time mapping, solver/lifecycle ownership and failure semantics. Keep upstream MTK systems native. Include a maintained MethodOfLines path and selected SBML-imported native systems. Add held/native batch state to the G06 conflict-closure pressure fixture and verify snapshot isolation, loser accounting and atomic failure on each claimed checkerboard/backend conjunction. R16 remains a small reusable coupling witness, not a substitute for #6 or #11. |
| G08 / R17–R19 | R17 delivers small public compositions, component substitution and the early models below. R18/R19 derive inspection/rendering from public quantities, lineage and committed state. No reporting-only copy of scientific state. Documentation distinguishes executable examples from unimplemented contracts. |
| G09 / R20 | Establish Chairmarks benchmarks early for composition/compilation, quantity fan-out, warm stepping, allocation count/bytes, lifecycle and native coupling. Preserve R49/R50 focused AllocCheck and warmed fixed-capacity zero-allocation evidence separately from empirical benchmark samples. Add the small public cold-latency corpus and stage decomposition assigned by the compiler amendment, including the canonical changing-field → aggregate → intracellular dynamics → conservative exchange/motion → division → observation → checkpoint workflow with multiple consumers and finite-resource contention. Retain the G06 conflict corpus and measure dependency preparation, arbitration and commit compilation/allocation/specialization separately without brittle count or timing gates. Later model PRs extend the same corpus in their own diffs; no uncounted final benchmark PR. |
| E01 / R21–R22 | Exercise real 3D geometry, native fields and lifecycle needed by #6/#14, including a checkerboard conflict created by a periodic alias or shared cell-wide dependency between geometrically separated sites. Preserve selected device commitments; do not infer exact 3D topology support. |
| E02 / R23–R25 | Preserve equilibrium auxiliary and driven OU families. Add a bounded foam-law compatibility check before freezing R23/R24. R25 owns foam composition only after its actual law works; a different driven example cannot close #4. Split a missing independent proposal implementation rather than hide it inside OU work. |
| E03 / R26–R27 | Test ordered multi-segment bending through actual public traversal/relations and inverse dependencies, including opposite-endpoint checkerboard proposals whose site claims appear disjoint. A pair-endpoint contract alone is insufficient. Extend the existing contract only if coherent; otherwise count the demonstrated owner companion(s). |
| E04 / R28–R30 | Distinguish biological grouping from containment. Add bounded parent-preserving site conversion, absent-compartment activation, quantity invalidation and failure-atomic publication for #14. R30 delivers segmented rods and compartment mechanics. Do not generalize this into arbitrary ownership mutation or fusion. |
| E05 / R31 | Preserve localized native event semantics. Add SBML event cases only for importer-supported semantics; do not claim parsing proves event execution. Ordinary MCS Boolean updates do not require root localization. |
| E06 / R32–R33 | Preserve separately qualified SDE and jump families. Share native infrastructure, not scientific meanings. Include imported stochastic examples only where the importer actually supports that representation; deterministic SBML and Boolean networks do not automatically exercise these families. |
| E07 / R34–R35 | Expand the native field bridge to the selected multispecies/reciprocal-IO and fixed cross-grid cases. Test source masks, transport coefficients, sampling/deposition, units and boundaries independently of biological formulas. R35 owns reusable field components and the complete #14 integration join. Add E04 as an explicit prerequisite for that R35 join. |
| E08 / R36–R38 | Keep exact topology and sampled morphology distinct. For an exact predicate admitted under checkerboard, test locally disjoint proposals sharing its global/component dependency; otherwise reject that conjunction precisely. A sampled observation is not a conflict footprint. R38 completes the invasion-analysis witness #10 using the actual published measures. Do not impose topology constraints merely to stabilize angiogenesis or compartment pictures. Any morphological algorithm beyond the selected invariant must have an identified owner and test. |
| E09–E10 / R39–R44 | Reuse unchanged Models factories for actual CUDA/ROCm tests. State CPM-device and native-solver-device support separately. No automatic GPU FBA, stochastic native integration or exact replay claim. |
| E11–E12 / R45–R48 | Preserve swap and static weighted-graph commitments. Test copy-versus-swap and swap-versus-swap atomic closure, then graph conflicts induced by weighted adjacency, shared logical ownership or relationships rather than Cartesian proximity. Require deterministic winner/commit parity on claimed backends. None of these fourteen papers automatically witnesses them: add explicitly labeled feature combinations, not altered paper reproductions. |

Across these rows, checkerboard generality comes from compact runtime graph data
and reusable operation-family laws. R13 may analyze a rich model, but names,
owners, graph contents, adjacency and ordinary counts remain values in the R12
executor; they are not nested tuple/type structure, `Val` axes, generated
functions or per-model kernels. Qualification compares renamed, isomorphically
renumbered, structurally different and bounded count-ladder graphs for shared
execution identity.

### Concrete special-machinery cutovers

These names are found in this planning checkout; inspect their current owning
implementations before editing active repositories.

Concrete inspection points are [scientific operations](../src/operation_library/scientific.jl),
[field numerics](../src/operation_library/numerics.jl),
[statement semantics](../src/statements/semantics.jl), and the
[MethodOfLines extension](../ext/PottsMethodOfLinesExt.jl). The latter already
uses upstream discretization and produces a native component, but its inspected
profile is narrow: one selected field output, no native inputs, and specific
2D CPU numerical combinations. Preserve that real integration while expanding
and testing it; do not describe all reciprocal/multispecies cases as existing.

| Displaced special machinery | Sole replacement and cutover responsibility |
|---|---|
| `ActEnergy`, `_potts_act_energy`, dedicated activity callable/lowering | PottsModels activity composition over state, neighborhood quantities, ordinary proposal drive, accepted-copy activation and aging. R11/R13 supply missing public expression support; R17 updates all Models consumers. Remove special exports, registrations and lowerings with the coordinated consumer cutover. |
| `DiscreteFieldEuler` biological diffusion/decay/secretion bundle | Biological source/reaction equations in Models; supported upstream MOL/SciML integration through Potts native bindings. R15 owns the bridge, R34 its later expansion. If preserving an admitted fixed-grid update needs reusable numerical primitives, implement those in the existing numerical owner—not a Merks solver. |
| Merks-specific connectivity helper/operation | Retain the actual mathematical predicate only under a truthful reusable contract and its stated adjacency/law. If it decomposes into existing public math, remove the special operation; if it needs a real algorithm, keep one algorithm owner. Renaming it “generic connectivity” does not prove equivalence to exact global topology. |
| Paper-specific branch, growth, network or invasion logic in compiler/runtime | Ordinary Models equations/processes and analysis over public state. No paper identifiers or hidden callbacks selecting biological execution paths. |

The existing Euler bundle clamps negative output. A new integrator is not
automatically behavior-equivalent: test the update rule, substeps, splitting,
boundary discretization, units and positivity treatment. Preserve admitted
science or record an explicitly accepted numerical/scientific change. Do not
delete the current consumer before its replacement exists, retain a compatibility
alias, or disguise a second implementation as a migration mode. Across separate
repositories, prepare the full candidate tuple and use coherent version bounds
and upstream-first integration; independent Git merges are not atomic.

## 4. Four accepted additional PRs

The canonical map allocates R51–R54 in E13–E16. These are planning identities,
not GitHub PR numbers or live API names.

| New repository PR | Scope and dependency | Why separate |
|---|---|---|
| **R51 / E13 — Potts: COBREXA optimization coupling** | After G07's stable publication/lifecycle boundary. Bind environmental snapshots to a selected upstream FBA model, execute its public solver API, validate result status and publish metabolic outputs. Exercise bound updates, workspace ownership, sampling cadence, division/retirement and failure. Environmental withdrawals reuse G07/E07 accounting. | Optimization has result status, feasibility and alternative optima; pretending it is an ODE misses its real contract. No generic optimizer framework is needed. |
| **R52 / E14 — Models: FBCA crypt model and metabolic compositions** | After the metabolic bridge, its selected environmental coupling (R35 for the accepted field-integrated delivery), G08's public composition/inspection surface and G09's benchmark workflow. Own #8's scientific formulas, assets, parameters, experiments, tutorial and benchmark. | A solver adapter is not the scientific model. This is a real downstream delivery, not a free compatibility tail. |
| **R53 / E15 — Models: vascular growth paper corpus** | After R17, R35 and G09's shared runner. Deliver #1, #5 and #7 with shared mechanical/field building blocks, distinct source laws, scientific tests, experiments and public compiler-corpus cases. | Keeps three related paper implementations and their validation out of the already broad field-binding PR. Early bounded components may still ship in R17; Models adds cases, not compiler machinery. |
| **R54 / E16 — Models: multiscale tumor paper corpus** | After R35, G09 and the vascular corpus where its public components are reused. Deliver #6 and #11, Boolean rules, coupled environments, phenotype/lifecycle, treatment experiments and shared-runner cases. | Separates model transcription/calibration from native infrastructure. No new tumor runtime, signaling framework or bespoke benchmark runner. |

The last two are accepted delivery splits, not evidence that existing
abstractions cannot express the models. Do not duplicate implementations between
R17/R35 and the new corpus: earlier PRs own reusable components; later factories
compose them and own paper-specific choices.

### SBMLToolkit and the metabolic ecosystem

Use [SBMLToolkit's public importer and support checks](https://docs.sciml.ai/SBMLToolkit/stable/api/),
then the same native binding route used by authored MTK systems. This is now
an explicit selected-workflow obligation in
R15/R16, with event/stochastic extensions in their actual later owners where
supported. This does not promise every SBML level/package or round-trip export.
Preserve identifier mapping, amounts versus concentrations, compartment volume,
units, initial assignments and supported event semantics. A chemical compartment
does not automatically become a spatial CPM compartment. Cell growth and division
must handle dilution and partitioning consistently.

The user confirmed **[COBREXA.jl](https://cobrexa.github.io/COBREXA.jl/stable/structure/)**
on 2026-09-10. R51 targets its public model/constraint/solver stack, and R52
supplies the FBCA scientific consumer. The earlier “ExaCobra.jl” ambiguity is
resolved. Select and test the supported dependency range; this confirmation
is not evidence that the coupling already exists.

For FBA, distinguish optimization flux bounds from physical uptake already
settled against a finite extracellular pool. If two cells compete for one pool,
blind post-solve clipping can invalidate metabolic balance and growth. Select
and test an allocation/re-solve policy; preserve the paper's environment law as
its own variant. Reject unsupported solver outcomes, and specify treatment of
alternative optima and tolerances. External solver warm starts are not portable
checkpoint guarantees. SBML kinetic import and SBML-FBC metabolic import are
different workflows and may have different upstream owners.

## 5. Conditional additions—not preapproved abstractions

| Demonstrated gap | Owner/addition if it cannot fit its still-open owner PR |
|---|---|
| Foam's actual proposal selection, normalization or loading cannot use current public transition contracts | A focused Core proposal-law PR and Potts authoring companion before R25. Up to two additional repository PRs, not an “OU foam” workaround. |
| Segmented bending cannot express ordered dependencies and correct candidate geometry through E03 | The minimum Core/Potts relation companion(s), before R30. No arbitrary-arity relation framework without that demonstration. |
| Parent-preserving compartment conversion cannot be coherently delivered in E04 | Explicit Core/Potts transition companion(s), before #14. Compound scalar assignment is not proof of ownership-transition support. |
| Actual field/native/optimization consumer lacks public reusable settlement or transfer math | A companion in Core or LocalMath as demonstrated. Potts must not reach private buffers or grow its own executor. |
| Selected SBML or MTK frontend behavior is absent upstream | A bounded upstream fix/extension, or a documented narrower supported workflow. Count actual repository contributions separately. |
| Paper's required morphology is not provided by E08's selected algorithm/public observations | Put a sampled analysis in its scientific owner where sufficient; count an engine/math companion only when that real contract is missing. |
| A promised new conjunction requires changing a Models PR that has already closed | Count the actual downstream companion. Do not call it free compatibility or verification work. |

Do not add dynamic remeshing, arbitrary 3D exact topology, cell fusion,
hemodynamics, off-lattice mechanics, dynamic capacity, parameter fitting,
multi-device execution, or a general hybrid scheduler solely to accommodate
these fourteen. They remain separate scope decisions unless paper inspection
demonstrates otherwise. Large parameter studies can use the established
experiment/ensemble workflow; they do not by themselves require a fitting API.

## 6. Final PottsModels delivery ownership

“Final” below means the chosen scientific variant, initializer, executable
tutorial, ordinary tests and reproducible experiment are delivered—not merely
that its ingredients have appeared. Allocation is accepted and subject to the
unresolved scientific checks in section 1.

| # | Early reusable delivery | Final paper/reference-model owner | Main prerequisites |
|---|---|---|---|
| 1 | R17 bounded chemotaxis/field composition | R53 vascular corpus | R17, R35; selected connectivity law if the variant requires it; G09 shared runner |
| 2 | R16 lifecycle components | R17 | G04–G07 |
| 3 | G04/G06 public motility examples | R17 | G04–G06; chosen OpenVT bias law |
| 4 | G06 drive and E02 law example | R25 | G06, E02; foam proposal-law resolution |
| 5 | R35 field/matrix components | R53 vascular corpus | R17, R35; G09 shared runner |
| 6 | R16 regulation/coupling; R35 fields | R54 tumor corpus | E01, R35, G09, E15/shared vascular components; paper network/lifecycle transcription |
| 7 | R35 fields; shared vascular components | R53 vascular corpus | R17, R35; G09 shared runner |
| 8 | R51 COBREXA integration | R52 FBCA corpus | G07, metabolic bridge, R35, G08, G09; paper model assets |
| 9 | Existing extracted sorting fixtures | R17 | G06, explicit reference conventions |
| 10 | R17 mechanical invasion composition | R38 | G06/G08 and selected E08 measurements; final-paper verification |
| 11 | R16 coupling; R33 reusable intracellular library | R54 tumor corpus | R35, G09, E15/shared vascular components; Boolean and treatment semantics |
| 12 | G05 geometry/G06 energy example | R17 | G05C, G06; full anisotropic formula |
| 13 | E03 public bending example | R30 | E03/E04; correct ordered segment dependencies |
| 14 | R30 compartment mechanics | R35 | E01, E04, E07; G04 history and actual site conversion |

Accepted graph changes are small and explicit (the canonical map owns them):

- Add **E04 → E07 completion** for R35's #14 integration. R34 field-engine work
  can start under its existing prerequisites. This is an integration join, not
  a claim that all field mathematics requires compartments.
- Add **G07 → E13/R51**, and **E13 + E07 + G08 + G09 → E14/R52**.
  G08 is also transitively upstream of G09, but remains explicit because E14
  consumes both the authoring/inspection surface and the benchmark workflow.
- Add **G08 + E07 + G09 → E15/R53** and **E07 + E15 + G09 → E16/R54**.
- Conditional law companions precede their named consumer. Preserve all other
  existing edges, including correct G05 → G05C → G06/G07.

These edges are acyclic. Do not make G07 wait for a completed paper corpus or
E04 wait for R35's field-integrated model. The existing E07/E06 edge remains a
declared integration join; it does not mean Boolean tumor models require SDEs.
The new tumor delivery can start #6 independently but completes its combined
scope only when its #11 vascular dependencies are available.

This puts the simple models into G08, mechanical/compartment models into
E02/E04, field-integrated models after E07, and invasion analysis into E08.
There is no final “implement all the models” phase. A later corpus PR does not
excuse missing executable public examples in earlier semantic-owner PRs.

## 7. Keeping the code maintainable and the science defensible

Every behavior must be navigable through public entrypoint → semantic owner →
validation and dependency/effect analysis → normalization/lowering → operational
recipe → state view → execution kernel → inspection → ordinary owning tests.
Use durable filenames, nearest documentation and short invariant comments;
remove replaced helpers, duplicate explanations and tests of obsolete paths.

Each model delivery includes:

- A compiler-impact declaration (`none`, `host-only`, or `device-reachable`).
  Classification follows the composed execution path, not repository ownership.
  A model that enters a supported device-specialized path supplies Kaimon
  before/after evidence through separate canonical public-model diagnostics,
  outside ordinary `Pkg.test`, and the applicable real-device witness. CPU-only
  native/optimization solvers name their host boundary and do not inherit a
  device claim from CPM execution.

- For deliveries after R20, a repeated-instance control through the canonical
  G09 public runner. Earlier model PRs provide public fixtures and feature-local
  evidence that R20 later consumes; they do not depend backward on that runner.
  Authored spelling and model cardinality must reuse established families. A
  truly new mathematical, storage, dimension or execution-law family is
  declared and compared with an unchanged control. PottsModels contributes
  public models and expected science; it does not inspect private upstream
  MethodInstances, kernel objects or prepared structs and never owns
  compiler/executor machinery.

- One public composition/factory and an explicit initializer. No private Core
  state access, cloned numerical solver, biological compiler switch or required
  side-effecting setup callback.
- A source-linked specification of the selected equations, update order,
  geometry, parameter units, initialization and deviations. This belongs in
  the normal model documentation, not a parallel registry/reporting framework.
- Small deterministic scientific oracles where applicable: full energy
  differences, Boolean truth tables, diffusion/transfer limits, rod bending
  and independently solvable FBA cases. These do not become second executors.
- Coupled tests for source changes, division/retirement, retained samples,
  late failure and continuation. Tests assert the declared guarantee; they do
  not infer exact replay of external solvers from restored CPM arrays.
- A bounded routine test plus a documented larger experiment for scientific
  observables. Report statistical tolerances and calibration choices. A unit
  test passing is not a reproduced paper figure; a movie is not a law test.
- A composition substitution test: replace the growth law, reuse one field
  with two components, exchange the native signaling system, or alter a drive
  without compiler edits. Share symbolic definitions across cell instances;
  independently own/reset mutable numerical workspaces.
- Executable documentation, ordinary package/quality tests, clean optional
  dependency loading, supported dependency-range tests, and applicable actual
  CPU/GPU integration. Use Aqua/ExplicitImports where already appropriate.
- Reproducible measurements of construction, compilation, warm execution,
  allocations, quantity fan-out, native solves and host/device transfers.
  Neither wall-time gates nor a clean architecture diagram prove performance.
  Use Chairmarks in the separate benchmark environment for comparable
  runtime/allocation samples. Extend focused diagnostic AllocCheck coverage only
  when the model introduces a genuinely new hot execution family; ordinary model
  variation should reuse the established
  R49/R50 payload and allocation contract.
  Include an unchanged control when the model adds a new specialization family;
  unexplained growth in that control is specialization coupling, not a model
  cost to hide in the later G09 rollup.
- A public compiler-health workload declaration recording the expected
  operation families, first/warm public latency, warmed allocations and
  throughput. Vary author names, parameter values and bounded repeated
  components independently so accidental coupling is visible. Private recipe,
  payload, IR and specialization attribution remains in the owning engine
  package when the workload demonstrates a new family. Later corpus PRs extend
  the same runner rather than creating paper-specific benchmarks or another
  execution authority.

The fourteen are a scientific reuse corpus, not exhaustive feature coverage.
Preserve additional honest witnesses for equilibrium sampling, OU mechanics,
root events, SDE/jumps, cross-grid conservative exchange, swaps, graph domains
and each supported device conjunction. Label these as feature demonstrations,
not changes to the selected papers.

## 8. Acceptance and remaining implementation decisions

The user accepted composition as the implementation rule, the existing-owner
changes, selected SBML integration, confirmed COBREXA coupling, four additional
deliveries, and the model ownership/dependency table on 2026-09-10. The canonical
map, planning instructions and nearest authoring documents have been synchronized.
Progress notes retain status authority. Implementation workers must read the
shared documents and reconcile actual public candidate interfaces before changes;
this amendment does not authorize overwriting another worker's active work.

Do not promise that all fourteen are already expressible, executable or fully
verified. The remaining bounded decisions are the two OpenVT variant conventions,
the exact foam law, the final 2026 invasion methods, FBCA model assets/coupling,
rod bending dependencies, and the compartment-conversion/numerical edge cases.
They have owners and delivery slots now, instead of being hidden behind invented
API. This planning change modifies no runtime code and establishes no new
package-test or paper-reproduction result.
