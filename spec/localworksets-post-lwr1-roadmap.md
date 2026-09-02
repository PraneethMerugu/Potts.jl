# LocalWorksets Post-LW-R1 Extraction and Adoption Roadmap

Qualification and review mechanics are governed by
`design/hardening/lw4q-qualification.md`. LW-4Q does not change this roadmap's
architecture or phase boundaries.

Date: 2026-08-15

Current disposition: historical adoption and qualification evidence. Its
execution-selection and closed-adoption clauses are superseded by
[Execution Architecture Consolidation](execution-architecture-consolidation.md),
which defines the sole current production graph.

Status: LW-4A through final LW-R2, bounded ED-R0 and bounded IC-R0 complete;
LW-4 frozen; revised LW-5A, non-promoted LW-5B0, bounded LW-5B2, corrected
isolated B3, non-promoted K02/B4, and mandatory LW-5B4O passed; bounded LW-5C
K02→K03 adoption, LW-5D convergence/promotion, and fresh LW-R3 passed exact
CPU/real-Metal qualification with P0=0/P1=0; the separately authorized
post-simplification K09 gate completed K09-R1 with the corrected direct path
sealed and LocalWorksets adoption rejected; G6 and all other later operation
families remain closed pending a separate owner send-off

Authority:

- [LocalWorksets V1 normative contract](localworksets-v1.md)
- [LocalWorksets V1 implementation gate](localworksets-v1-implementation-gate.md)
- [LW-R1 exact-candidate review](../design/hardening/lwr1-localworksets-review.md)

## Decision and purpose

The owner selects standalone extraction as the LW-4 disposition. Extraction is architectural
hardening, not a claim that the general LocalWorksets library is already complete.

The mandatory continuation is:

```text
LW-4A exact standalone extraction -> LW-R2A package-boundary review
  -> LW-4B bounded general mechanisms -> LW-R2B mechanism review
  -> LW-4C Julian/JuliaGPU API reconciliation -> LW-R2 public-surface freeze
  -> ED-0 inventory -> bounded ED-1 hygiene -> ED-R0
  -> IC-0 complexity/SPI/verification audit -> bounded IC-1 consolidation -> IC-R0
  -> LW-5 compiled local-operation adoption -> K02/B4 baseline
  -> LW-5B4O mandatory layout/execution optimization -> LW-5B4O-R
  -> bounded LW-5C adoption and stop review
  -> separately authorized LW-5D -> LW-R3
  -> post-CA simplification
  -> separately authorized K09-0 -> K09-R0 -> K09-1/K09-2/K09-3 -> K09-R1
  -> explicit owner G6 send-off
```

LW-4 establishes a coherent standalone execution package. LW-5 makes PottsToolkit and CorePotts
ordinary consumers of that package by lowering eligible compiled operations into local work. No
gate transfers domain physics, clocks, RNG identity, scientific transactions, checkpoint meaning,
solver semantics or ModelingToolkit ownership into LocalWorksets.

No later subgate begins early. P0/P1 findings block advancement. Every P2 requires an explicit
owner and disposition before the next review boundary.

The [ED-0/ED-1 engineering-debt audit](../design/hardening/ed0-ed1-engineering-debt-audit.md)
inserts one bounded pre-adoption hygiene gate after the sealed LW-R2 baseline.
It may repair confirmed dispatch/diagnostic defects, ordinary package CI and
living repository status without reopening this architecture or deleting
direct/reference oracles. The non-promoted LW-5B0 adapter/clear probe is not a
migrated production operation; proposal evaluation remains the first
evidence-bearing operation and decides deeper consolidation.

ED-R0 passed on exact product commit
`da80a0ec1f6b52321973872066e02632124ec0f4`; see the
[qualification record](../design/hardening/edr0-engineering-debt-review.md).

The owner subsequently inserted a bounded internal-complexity hold before
substantive LW-5 migration. IC-0 audits abstraction ownership, Julia design,
SPI organization, active verification cost, and a bounded Symbolics-generated
evaluator feasibility question. IC-1 may consolidate only confirmed
behavior-preserving duplication; it adds no feature and reopens no accepted
LocalWorksets architecture. The Symbolics sub-gate may reject adoption and
must not alter CorePotts/LocalWorksets dependency ownership. The single authoritative
[IC-R0 record](../design/hardening/icr0-internal-complexity-review.md) defines
the matrix and exact qualification. IC-R0 passed on exact product commit
`8b710692a84f79b1411a1443a27a9ee099327bcf`, tree
`b360f2b06b404b34d448c75f3bdd5b012d839dc7`, with P0=0, P1=0, and P2=0.
The prior [LW-5A representability and preservation inventory](../design/hardening/lw5a-representability-and-preservation.md)
is preserved as evidence and its completion ruling remains withdrawn. The
authoritative [LW-5A adoption-and-consolidation amendment](../design/hardening/lw5a-adoption-consolidation-amendment.md)
and [focused review](../design/hardening/lw5a-adoption-consolidation-review.md)
passed. They open only the disposable, non-promoted B0 integration probe. The
non-promoted [B0 probe](../design/hardening/lw5b0-integration-probe-review.md)
subsequently passed exact CPU/real-Metal qualification and its focused hold.
The bounded [B2 proposal bridge](../design/hardening/lw5b2-proposal-bridge-review.md)
subsequently passed exact CPU/real-Metal qualification. It proved the shared
science projection and inferred canonical source tuple without selecting a
production path. The isolated
[B3 one-for-one proposal comparison](../design/hardening/lw5b3-proposal-adoption-review.md)
passed full semantic/RNG/checkpoint/failure and CPU/real-Metal lifetime
evidence. Its original candidate failed the frozen CPU noninferiority
threshold; a bounded canonical-schedule correction to the quadratic
CorePotts adapter bridge then passed the unchanged CPU and real-Metal
protocol and a fresh
[remediation review](../design/hardening/lw5b3-proposal-adoption-remediation-review.md).
At that historical gate, direct execution remained selected and `K02` passed
as the non-promoted B4 second-use witness. The later execution architecture
consolidation supersedes that selection and closed-adoption disposition.

The owner subsequently authorized the single bounded
[LW-5B4O mandatory layout and execution optimization](../design/hardening/lw5b4o-mandatory-layout-and-execution-optimization.md).
It makes StructArrays and StaticArrays direct, always-loaded dependencies of
CorePotts and LocalWorksets, repairs the outstanding B4 topology/count
admission gaps, consolidates the proposal record/schema and qualified host
submission path, and ended in the fresh
[LW-5B4O-R review](../design/hardening/lw5b4o-review.md), which passed the
sealed candidate with P0=0 and P1=0. It explicitly
supersedes the earlier conditional dependency clauses and the B4 no-
LocalWorksets-change veto only for its enumerated rows after the exact B4
baseline is preserved. It did not promote K02 and cleared only the then-active
LW-5C pre-migration preservation hold; later gates still required their own
authorization.

The bounded [LW-5C adoption matrix](../design/hardening/lw5c-adoption-matrix.md)
then selected K02 candidate generation and K03 proposal evaluation as one
ordered `LocalWorksets.sequence`. The exact
[qualification packet](../design/hardening/lw5c-final-evidence.md) passed the
complete CorePotts, LocalWorksets, PottsToolkit 2,664/2,664 and real-Metal
suites. Its paired upper-95 ratios were `1.0423004818` on CPU and
`1.0043324310` on Metal against the unchanged `1.05` threshold. The fresh
[LW-5C committee review](../design/hardening/lw5c-review.md) returned P0=0 and
P1=0 and froze only this bounded, non-default candidate. LW-5D subsequently
absorbed the approximately 339-line parallel candidate lifecycle into the
common execution shell, requalified allocations/performance, and promoted
only the exact K02→K03 conjunction after LW-R3. No later family opened.

## Preserved architecture

The following decisions remain closed unless an executable extracted-package prototype exposes a
genuine contradiction:

- package name `LocalWorksets.jl`;
- public mental model `LocalWork -> WorkPlan -> PreparedWork -> WorkEvent`;
- lifecycle `localwork -> plan -> prepare -> run! -> wait / waitall`, where
  `waitall` is restricted to one exact provider synchronization scope;
- topology ownership in `WorkPlan` and concrete storage/workspace/lane ownership in `PreparedWork`;
- named output meanings `independent`, `combined` and `resolved`;
- central validation and lowering;
- prebound bounded workspace;
- declarative extension mechanisms with no opaque external executor;
- KernelAbstractions implicit ordering and asynchronous submission where supported; and
- domain ownership of physics, clocks, RNG, solvers, transactions and checkpoints.

LW-4C may consolidate constructors, conveniences, composition, error reporting, inspection and the
extension-authoring surface using real implementation evidence. It may not create a competing
lifecycle, reopen naming by preference alone, or expose internal execution-family/compiler nodes.

## Cross-cutting admission rule

New LocalWorksets functionality is admitted only when it is general and bounded. A mechanism must:

1. describe a finite item domain and topology epoch;
2. declare all logical reads, destinations, writes and alias rules;
3. bound emissions, temporary records, workspace and launch structure during planning;
4. define output coverage, empty behavior, conflict behavior and visibility;
5. qualify determinism and numerical reproducibility honestly;
6. lower centrally to an inspectable execution plan;
7. execute without hidden host fallback, device allocation, synchronization or opaque callbacks;
8. state backend support as backend x element type x operation x address space;
9. preserve static dispatch and concrete GPU-compilable device arguments; and
10. demonstrate reuse in at least two unrelated domains before being described as general.

An external declaration cannot authorize its own backend execution. Collective, segmented,
iterative/frontier, multi-pass or other execution families remain deferred until two concrete
unrelated witnesses prove that the admitted mechanisms cannot express them safely.

## LW-4A — Exact standalone extraction

### Objective

Move the exact LW-R1 implementation into a standalone experimental package without changing its
scientific behavior, launch structure, output claims or qualification scope.

### Package boundary

`LocalWorksets.jl` owns only:

- the four lifecycle values and their public operations;
- topology validation, planning and binding;
- named value/storage slots and alias validation;
- workspace sizing, ownership and reuse;
- leases, poison state, events, waiting and inspection;
- the hardware-neutral KernelAbstractions provider;
- the reviewed one-key resolved lowering;
- the reviewed bounded conjunctive lowering as a general two-key item-result mechanism; and
- package-owned central lowering and admission machinery.

It must not depend on CorePotts, PottsToolkit, ModelingToolkit, SciMLOperators, Metal, CUDA or
AMDGPU. KernelAbstractions, Adapt and qualified portable atomic/reduction dependencies are allowed
when their exact need is documented.

CorePotts becomes an ordinary downstream package. Its adapter owns CPM operation descriptors,
semantic identities, RNG addresses, capability composition and checkpoint lowering identity.
PottsToolkit continues to depend on CorePotts and does not re-export LocalWorksets automatically.

### Trust and qualification

The current CorePotts UUID-based trusted boundary must be replaced. The standalone package owns a
closed compiler/admission root that recognizes package-defined lowering primitives. External
packages may contribute concrete declarations and operation functors through documented protocols,
but they cannot add opaque launches, override central validation, or return an unreviewed
"supported" trait.

Mechanism support and reviewed environment qualification must be separate facts:

- mechanism support describes what central lowering can generate;
- environment qualification identifies reviewed backend/device/type/operation combinations; and
- a downstream domain composes those facts with its scientific capability identity.

The extracted package remains qualified only on CPU and the reviewed Apple M1/Metal environment
until new exact evidence is accepted. Hardware-neutral source is not CUDA or ROCm qualification.

### Required evidence

- exact public-name and dependency inventories;
- absence of CorePotts/PottsToolkit/domain identities in package source and tests;
- absence of vendor branches and backend extensions containing LocalWorksets execution code;
- hostile-method tests proving external methods cannot bypass validation or admission;
- package-owned plan, prepare, run, wait, lease, poison and inspection tests;
- standalone CPU and real-Metal z-buffer witnesses;
- CorePotts checkerboard parity through the package API;
- exact checkpoint continuation and cross-lowering rejection;
- unchanged KernelAbstractions implicit-order launch/wait behavior;
- unchanged warm workspace, allocation, compiler-cache and throughput evidence; and
- package loading and testing without PottsToolkit or ModelingToolkit present.

The direct CorePotts implementation remains `Supported` and default. The LocalWorksets path remains
private and experimental through LW-R2 unless the final review explicitly authorizes otherwise.

### LW-R2A — Package-boundary review

Independent reviewers cover package/API boundaries, trust/admission security, JuliaGPU execution
and CorePotts preservation. The review separately answers:

1. Is the extraction behaviorally identical to the LW-R1 candidate?
2. Is the package genuinely independent of CorePotts and PottsToolkit?
3. Did extraction preserve fail-closed qualification and direct-oracle parity?
4. Did any package-boundary choice make the later general API materially harder?

No bounded capability expansion begins until all four answers pass.

## LW-4B — Bounded general mechanism completion

### Objective

Implement the smallest domain-neutral mechanism set needed for realistic external use and the
later Potts operation inventory. Do not recreate Kokkos or prebuild speculative execution families.

### Required output mechanisms

1. **Independent output**
   - planning proves required coverage and one writer per selected destination;
   - missing and duplicate writers reject;
   - masking and selected-item semantics remain distinct.
2. **Deterministic combined output**
   - explicit identity and canonical semantic order;
   - destinations with no contribution receive the identity;
   - floating-point order is fixed and reported.
3. **Explicitly fast combined output**
   - qualified backend reduction tree or atomic behavior is named;
   - nondeterminism/reproducibility limitations are public;
   - bare floating-point `+` never selects this mode implicitly.
4. **Resolved output**
   - retain explicit empty result, total rank and canonical semantic tie break;
   - generalize only through reviewed concrete types and layouts.
5. **Named heterogeneous output ports**
   - one operation may independently write edge state, combine vertex forces and resolve cell
     proposals;
   - each port owns its route, semantics, storage, workspace and inspection facts;
   - concise single-output sugar remains available.
6. **Bounded multi-destination emission**
   - per-item maximum is statically planned;
   - false lanes emit nothing;
   - record capacity and overflow rejection are exact;
   - the reviewed conjunctive lowering becomes an instance, not a hidden CPM special case.
7. **Ordered composition**
   - `sequence` communicates order and visibility;
   - stages share one admitted lane and use provider implicit ordering;
   - no intermediate host wait or fabricated dependency event is introduced.

Generic keyed arbitration may be implemented as a lower-level internal primitive reused by
resolved and bounded multi-destination outputs. It is not a public scheduler or solver.

### Required cross-domain witnesses

All witnesses are complete and runnable, including declaration, topology, planning, storage,
workspace, execution, wait and inspection:

- D2Q9 LBM stream/collide with an external exclusive/permutation operation;
- lattice-spring edge state, deterministic/fast vertex force assembly and resolved fracture;
- matrix-free FEM element application with mixed-arity scatter;
- deterministic z-buffer selection; and
- CorePotts two-key proposal-claim arbitration without embedding CPM semantics.

The witnesses test mechanisms. They do not add domain physics or solver APIs to LocalWorksets.

### Witness lifecycle and repository ownership

Cross-domain witnesses are evidence consumers of LocalWorksets, not production implementations
owned by LocalWorksets. Their required disposition is:

1. During mechanism design, a witness may begin as a disposable temporary project. Temporary
   results guide implementation but do not satisfy LW-R2B evidence and are not retained as package
   functionality.
2. Before LW-R2B, every accepted cross-domain witness must be preserved as a durable external-
   consumer test or witness project outside `LocalWorksets/src`. It must load LocalWorksets through
   its public package boundary and may not use private LocalWorksets bindings.
3. Minimal domain-neutral contract tests for independent, combined, resolved, heterogeneous,
   multi-destination and ordered mechanisms belong in the LocalWorksets package test suite. These
   fixtures test mechanism laws and must not present themselves as domain solvers.
4. CorePotts proposal-claim arbitration belongs in downstream CorePotts integration and parity
   tests because CorePotts owns proposal meaning, semantic identities, capability composition,
   checkpoints and commit semantics.
5. Direct-kernel launch, allocation, compilation and throughput comparisons belong in benchmark
   or evidence projects rather than production source.
6. After LW-4C reconciles the API, selected witnesses may be promoted into polished documentation
   examples. Documentation helpers may remove repetition but may not hide topology, storage
   binding, output semantics, workspace, execution, synchronization or inspection.

No LBM, lattice-spring, FEM, z-buffer or CPM physics, solver loop, domain-named execution type or
domain-named kernel is admitted to `LocalWorksets/src`. Only the domain-neutral mechanism proven by
a witness may enter production LocalWorksets code.

A witness is "complete and runnable" only when an exact recorded command constructs its
declaration and topology, plans it, binds real storage and workspace, executes and waits, inspects
the resulting plan, and compares the result with an independently implemented reference. It must
also exercise relevant invalid declarations, record launches and warm allocations, and run on CPU
plus every hardware environment claimed by its evidence row. Source portability alone does not
make an untested backend part of the witness claim.

### LW-R2B — Mechanism review

Independent reviewers cover numerical laws, cross-domain generality, GPU compilation/performance,
invalid combinations and false unification. The review must reject:

- decorative declaration fields;
- a mechanism that works only for one witness;
- silent floating-point order;
- specialization explosion from composable policy parts;
- unbounded emission or workspace;
- hidden launches, waits, allocation or fallback;
- backend claims based only on source portability; and
- any mechanism that turns LocalWorksets into a scheduler or domain framework.

## LW-4C — Julian and JuliaGPU API reconciliation

### Objective

Freeze a public authoring surface that is pleasant for domain-package authors while remaining
statically compilable, inspectable and fail-closed on GPUs. This is an implementation-backed API
consolidation, not another open-ended naming audit.

LocalWorksets is preserved as the validated topology/conflict/workspace/lifetime/inspection layer
above KernelAbstractions, while its current complexity is treated as debt. LW-4C must evaluate
whether every abstraction, specialized lowering, declaration and validation layer earns its cost,
consolidate duplicated machinery without removing proven safety, and make topology, storage and
workspace construction substantially easier without hiding their semantics. No new execution
family is admitted without two unrelated concrete consumers.

LW-5 is the downstream value test: real CorePotts/PottsToolkit operations must become materially
smaller, clearer and easier to inspect. If adoption still requires large custom adapters per
operation, simplify the abstraction or authoring surface before adding mechanisms.

### Required order inside LW-4C

LW-4C is not one undifferentiated API pass. The qualified LW-R2B candidate is first preserved as
the behavioral and performance baseline, then work proceeds in this order:

1. **LW-4C0 — internal complexity audit.** Map duplicated validation, topology handling, binding,
   workspace calculation, evidence construction and lowering machinery. Every abstraction and
   specialization must state its safety, performance or multi-consumer justification. C0 changes
   no production execution.
2. **LW-4C1 — implementation consolidation.** Consolidate common internal machinery while
   preserving semantics, admission, launch counts, allocations, KernelAbstractions implicit
   ordering, determinism and controlled CPU/Metal performance. A specialization is removed only
   after an executable replacement proves its complete behavior and performance obligations.
3. **LW-4C2 — construction and authoring simplification.** Make topology, storage, workspace and
   binding construction substantially easier without hiding topology epochs, access, aliases,
   output laws, capacities, device ownership or queue bounds.
4. **LW-4C3 — public API reconciliation.** Finalize Level 1, Level 2 and extension APIs,
   diagnostics, inspection, examples and JuliaGPU ergonomics against complete witnesses.
5. **LW-R2 — fresh committee freeze review.** No public production promotion or LW-5 adoption
   begins until this review clears.

Line reduction is an outcome of clearer ownership, not an admission criterion. Proven safeguards
must not be weakened to shrink the package, and performance-qualified specialization is retained
where measurements justify it. Priority C1 seams are shared per-port evidence, checked count/byte/
route/capacity validation, binding and workspace specifications, topology copy/fingerprint/
transfer accounting, common arbitration primitives, and obsolete specialized lowerings.

### Three authoring levels

**Level 1 conveniences** cover common single- and multi-output work through ordinary Julia
constructors, keyword arguments, do-blocks, tuples and named tuples. Common authors do not construct
workspace formulas, lowering nodes, atomic primitives, capability certificates or backend-specific
objects.

**Level 2 declarations** expose explicit reads, routes, ports, active selection, masks, aliases,
submission slots, deterministic/fast numerical semantics, resolution laws, topology epochs and
ordered composition. This is the primary package-author/compiler-facing surface.

**Extension API** admits concrete isbits operation functors and declarative combination/resolution
components that lower through package-owned primitives. It provides validation and inspection
metadata but no opaque executor or self-issued qualification.

### Julian requirements

- one obvious lifecycle and one unambiguous owner for every value;
- ordinary functions, immutable structs, multiple dispatch, keywords, tuples and named tuples;
- do-block authoring for local operations;
- no mandatory macro DSL;
- concise single-output sugar and readable heterogeneous named ports;
- type-constrained `Base.wait` and concise, non-synchronizing `show`;
- discoverable exports, docstrings, `propertynames` and complete examples;
- errors naming the declaration, port, binding and violated contract;
- internal `Val`, traits, compiler nodes and launch primitives hidden from common users; and
- no boolean-option pile or symbol-based mode switch where semantic types are clearer.

### JuliaGPU requirements

- concrete callable structs or isbits closures for device operations;
- tuple/NamedTuple specialization without runtime dictionaries or abstract containers;
- `Adapt`-compatible device representations;
- KernelAbstractions backends and implicit ordering, with no vendor branch in core execution;
- central selection of qualified atomics/reductions;
- prelaunch rejection of every statically knowable declaration, schema,
  capability, binding and workspace fault; selected-device compiler rejection
  before launch is required only when the provider exposes a separately
  reviewed, backend-neutral compile-validation protocol;
- no scalar indexing, dynamic dispatch, host fallback or warm workspace growth;
- asynchronous `run!` where supported and exactly the promised portable wait behavior; and
- `inspect` reports launches, workspace, transfers, determinism and qualification without waiting.

### Concrete API questions to settle

- whether Level 1 may provide a convenience that internally performs `plan` then `prepare` without
  creating a second semantic lifecycle;
- the final constructors for named heterogeneous ports and single-output sugar;
- whether ordered stages use only `sequence(a, b, ...)` or additionally accept tuple sugar;
- how operation functors receive item identity, gathered reads and submission values;
- how automatic bounded workspace selection coexists with explicit caller workspace;
- how deterministic and fast combination types are named and displayed;
- how external extensions provide evidence without central source edits or self-authorization; and
- which declarations are public values versus package-internal lowering components.

No answer is frozen from aesthetics alone. Every decision is tested against the complete witnesses.

### Authoring-experience evidence

For LBM, lattice springs, matrix-free FEM, z-buffer, CorePotts and one separate external extension,
the review receives copy-pastable code showing every difficult mapping. Helper functions may remove
repetition but may not hide topology, storage binding, output semantics, synchronization or
inspection.

The API candidate must prove:

- ordinary examples require no internal compiler type;
- CPU-to-GPU movement changes backend/storage, not the scientific operation;
- common automatic workspace preparation is bounded and inspectable;
- multi-output work is materially clearer than separate hidden passes;
- invalid GPU code is rejected during planning/preparation when it is
  statically knowable through the portable interface; otherwise a
  selected-device compiler failure at first provider invocation is reported as
  a backend failure, conservatively poisons the cumulative scope, and obeys the
  inspected partial-visibility contract;
- error messages identify the exact rejected port/operation;
- an external package adds a qualified operation without editing LocalWorksets source;
- `@inferred`, device compilation, warm allocation and specialization-count tests pass; and
- docstrings and `show`/`inspect` tell the same lifecycle and guarantee story.

### LW-R2 — Standalone package and public-surface freeze

A fresh committee includes scientific usability, Julia multiple dispatch/package API, JuliaGPU
lowering/performance, numerical determinism, and an external extension author. Require independent
memos before contradiction/red-team deliberation.

The committee may reject the public API even when the kernels are correct. It separately ballots:

1. standalone package independence;
2. generality and boundedness of every executable mechanism;
3. Level 1 readability;
4. Level 2 completeness and inspectability;
5. extension-authoring safety and usability;
6. CPU and qualified real-Metal correctness/performance;
7. CorePotts parity and ownership preservation; and
8. readiness to begin LW-5.

The sealed LW-R2 record satisfies this freeze condition. The bounded ED-R0
hold above now controls substantive LW-5 source migration.

## LW-5 — Compiled local-operation adoption

### Objective

Lower eligible PottsToolkit/CorePotts compiled execution mechanisms onto the frozen LocalWorksets
API without requiring Potts model authors to write LocalWorksets declarations.

The intended compiler path is:

```text
PottsToolkit authoring
  -> complete / mtkcompile
  -> qualified operation and descriptor IR
  -> CorePotts-owned semantic phase
  -> LocalWork declaration and plan
  -> PreparedWork / KernelAbstractions execution
```

LocalWorksets executes local mechanisms. PottsToolkit remains the symbolic/MTK authoring compiler,
and CorePotts remains the CPM runtime and scientific transaction authority.

### LW-5A — Adoption-and-consolidation inventory

Before migration, classify every CorePotts execution stage as:

- directly representable;
- representable after independent output;
- representable after deterministic or fast combination;
- representable after heterogeneous ports;
- representable after bounded multi-destination resolution;
- domain orchestration that must remain outside LocalWorksets; or
- not appropriate for LocalWorksets.

An eligible stage has bounded local reads/emissions/workspace, explicit output/conflict behavior,
an inspectable launch sequence and no hidden global iteration. Classification alone does not
authorize migration.

Freeze public authoring, direct execution, checkpoint, RNG, capability and performance oracles for
each selected family. A preservation review must approve this inventory before compiler work.

The original preservation inventory remains evidence, but its completion
ruling is superseded. The authoritative
[amendment](../design/hardening/lw5a-adoption-consolidation-amendment.md)
classifies every CorePotts semantic execution stage and all 41 current
device-kernel declarations by scientific owner, current custom machinery,
retained semantics, replaceable machinery, LocalWork representation,
deletion/demotion target, adapter, oracle, blocker and closed disposition.
Its [focused review](../design/hardening/lw5a-adoption-consolidation-review.md)
passes the revised gate with an owned derivability hold and opened only the
non-decisive B0 independent-clear integration probe. The one-launch proposal-
evaluation pilot was conditional on B0 and must replace rather than wrap its
custom execution unit. The
[B0 focused hold](../design/hardening/lw5b0-integration-probe-review.md) passed;
the bounded [B2 bridge](../design/hardening/lw5b2-proposal-bridge-review.md)
then passed without production promotion. The isolated
[B3 comparison](../design/hardening/lw5b3-proposal-adoption-review.md) passed
after its original performance failure was corrected in the CorePotts
descriptor bridge and cleared by fresh review. `K02`/B4 is authorized only as
the non-promoted adapter-reuse witness. No production migration or later
family is authorized.

### Ownership boundary

| Mechanism | LocalWorksets may execute | Retained owner |
|---|---|---|
| bulk clear/copy | validated independent writes | CorePotts phase and bank choice |
| proposal-local descriptor evaluation | local reads and per-proposal results | PottsToolkit terms; CorePotts proposal views and order |
| drives/modifiers/constraints | admitted compiled local operations | CorePotts acceptance and failure semantics |
| Hamiltonian evaluation | per-term or per-proposal local evaluation | public authoring and canonical source-order fold |
| accepted-copy effects | independent/combined/resolved staging | CorePotts eligibility and commit |
| tracker contributions | qualified combination | tracker meaning and publication |
| relationship proposals | bounded emission/resolution | relationship identity and transaction law |
| lifecycle request emission | bounded local emission | clocks, generations and request meaning |
| lifecycle arbitration | conflict-resolution mechanics | validation and atomic lifecycle commit |
| field deposition/local updates | independent/combined execution | MTK equations, coupling and solver lifecycle |

LocalWorksets must not own MCS clocks, phase schedules, RNG addressing, Metropolis acceptance,
canonical Hamiltonian ordering, generation/slot-reuse laws, lifecycle transaction atomicity,
inactive-bank publication, checkpoint identity, settlement, SciML integration or MTK compilation.

### LW-5B — Compiler adapter

Build one adapter from qualified CorePotts operation/descriptor IR to public LocalWorksets
declarations. It must:

- use only the standalone public/extension API;
- preserve descriptor identities, domains, footprints and source order;
- preserve external-operation purity and bounded-anchor proofs from `complete`/`mtkcompile`;
- compose LocalWorksets mechanism capability with CorePotts scientific capability;
- preserve direct/candidate checkpoint mechanism identity;
- avoid per-model generated package code or private cross-package reach; and
- produce inspection that links each semantic stage to its LocalWork plan and launches.

Hamiltonian authors and ordinary PottsToolkit users never see LocalWorksets declarations unless
they explicitly inspect the lowered execution.

The B0 adapter skeleton and probe frozen by amended LW-5A passed their
[focused hold](../design/hardening/lw5b0-integration-probe-review.md).
The bounded [B2 bridge](../design/hardening/lw5b2-proposal-bridge-review.md)
then proved an inferred fixed-source return, compiler-derived read manifest,
shared device science projection and one-launch CPU/Metal execution without
production promotion. The contribution matrix was confirmed to be transient
scratch, so canonical contribution folding remains inside the CorePotts
operation and only the disposition is published through LocalWorksets.

The isolated B3 one-for-one proposal-evaluation comparison has passed after
bounded remediation. "One adapter" means one CorePotts-owned lowering authority using
ordinary multiple dispatch over qualified IR, not one monolithic function or
one bespoke adapter per operation. The pilot must preserve CorePotts proposal science,
derive a bounded type-stable return bridge without hidden output mutation,
and replace the existing evaluation launch one-for-one without an intermediate
wait. Failure does not authorize a new LocalWorksets mechanism.

B3 must compare the frozen direct launch and isolated LocalWorksets launch on
exact contributions/dispositions, failure classes, RNG addresses, state,
trackers, checkpoint continuation and cross-mechanism rejection. It must also
record launch, wait, allocation, workspace, transfer, queued-MCS and throughput
ledgers. Passing B3 does not itself promote the path: the `K02` second-use
witness and decisive pilot review remain required. B3 now passes; `K02` opens
only under the bounded B4 hold below.

### K02 / LW-5B4 — non-promoted adapter-reuse witness

`K02` remains the operation name and is the only work opened by corrected B3.
B4 must construct and compile checkerboard candidate generation through the
same CorePotts adapter as a non-promoted second-use witness. It must:

- reuse topology, binding, capability, inspection and execution-view
  derivation from the proposal pilot;
- require materially less family-specific integration than K03 proposal
  evaluation;
- retain production candidate generation and the direct oracle unchanged;
- add no LocalWorksets mechanism, family, vendor branch, synchronization or
  scheduling authority;
- avoid copying K03 named bindings, creating a second execution-view
  framework or adding a family-symbol registry; and
- pass focused CPU and real-Metal compilation, exact candidate-array/RNG
  parity, launch/wait/allocation inspection and adapter-consolidation review.

B4 success is evidence for the decisive proposal-pilot review, not production
promotion. Failure closes broader migration and returns adapter derivability
to LW-5A; it does not authorize per-operation frameworks or LocalWorksets
expansion.

### LW-5B4O — mandatory layout and execution optimization

After preserving the exact B4 candidate and evidence, execute the single
[LW-5B4O matrix](../design/hardening/lw5b4o-mandatory-layout-and-execution-optimization.md).
Both CorePotts and LocalWorksets receive direct StructArrays and StaticArrays
dependencies and distinct base-package integrations. The same phase owns the
bounded identity-route/component-publication and static-submission
optimizations plus the independent B4 topology/count repair. One final
The [LW-5B4O-R committee review](../design/hardening/lw5b4o-review.md) closed
the phase with P0=0 and P1=0; no intermediate product gate or broader feature
phase was introduced. Its carried P2 ledger remains binding on LW-5C/LW-5D.

Mandatory integration does not predetermine K02's performance disposition.
K02 retains the direct oracle and requires the unchanged noninferiority rule
for any later promotion claim.

### LW-5C — Bounded migration order

Migrate one family at a time, retaining its direct oracle:

1. bulk independent operations;
2. proposal-local descriptor evaluation;
3. tracker or field contributions;
4. accepted-copy effects;
5. lifecycle request emission; and
6. lifecycle conflict arbitration.

Each family receives a pre-migration preservation hold and a post-migration parity review. A failed
family does not justify weakening LocalWorksets semantics or migrating later families.

The phase stopped after the K02→K03 proposal-local pair. The remaining rows
were evaluated and explicitly retained in CorePotts because they did not yet
prove an independent deletion unit, an unrelated consumer, or a complete
CPU/real-Metal oracle. This stop is part of the frozen LW-5C result, not
authority to continue the list.

### LW-5D — Adoption qualification

**State: passed and sealed.** The bounded LW-5C candidate was converged into
one CorePotts execution shell, passed complete final CPU/product/real-Metal
and performance qualification, and was promoted only for the exact admitted
K02→K03 conjunction. Evidence: [LW-5D packet](../design/hardening/lw5d-final-evidence.md).

The final candidate must prove:

- exact scientific state, tracker and lifecycle parity where the direct oracle is exact;
- identical RNG addresses, accepted trajectories and checkpoint continuation;
- canonical Hamiltonian folding and external operation behavior;
- unchanged failure/poison/publication boundaries;
- no new intermediate waits;
- bounded launch, workspace, allocation, transfer, specialization and throughput results;
- CPU and qualified real-Metal execution;
- full CorePotts and PottsToolkit suites, including MTK and SciML integration; and
- honest fallback/rejection for every unqualified operation, type, backend and lifecycle family.

### LW-R3 — Adoption review

**State: passed.** The fresh committee returned P0=0/P1=0 after independent
memos and a contradiction round, then the bounded promotion delta passed its
post-review seal. Review: [LW-R3 record](../design/hardening/lw5d-review.md).

A fresh committee reviews semantic preservation, compiler cohesion, LocalWorksets generality,
JuliaGPU performance, MTK/SciML boundaries and the public Potts authoring experience. It must verify
that adoption removed bespoke execution machinery where justified without moving domain semantics
downward or turning LocalWorksets into the hidden CorePotts engine.

LW-R3 authorized and LW-5D sealed the narrow public/default promotion. The
direct oracle remains reference/fallback/legacy replay. G6 did not open.

### LocalWorksets construction amendment — CA-0 through CA-4

**State: complete and qualified on 2026-08-15; focused committee PASS.** The
[construction-pain audit](../design/hardening/localworksets-construction-pain-audit.md)
found no contradiction in the accepted lifecycle or execution-family algebra,
and its bounded prepared-state, topology, workspace-construction and adapter
debt has been remediated. Complete LocalWorksets CPU, complete exact-source
CorePotts CPU, qualified real-Metal, and fresh reviewer evidence passed with
P0=0/P1=0/P2=0. The sealed LW-5D CPU/Metal behavior, launch, allocation,
throughput, RNG, checkpoint, Hamiltonian, failure and settlement evidence
remains the baseline.

Work proceeds in this exact order:

1. **CA-0 — prepared-state and topology integrity.** Freeze nested prepared
   runtime/provider references, qualify stable array representations, define
   canonical and prepared topology-leaf evidence, reject non-host plan-time
   topology, and strengthen retained checkerboard-claim provenance.
2. **CA-1 — construction evidence and caller workspace.** Expose complete
   binding and workspace requirements from the same authority used by
   validation; provide a mechanical caller-workspace construction path without
   exposing lowering internals or hiding lease capacity.
3. **CA-2 — topology authoring.** Add an allocation-free explicit identity
   route and declarative topology-backed reads. Epochs, destination counts,
   non-identity routes, semantic IDs, and ownership remain explicit.
4. **CA-3 — CorePotts adapter consolidation.** Reuse one WorkPlan across
   concrete bank preparations and derive structural inspection from
   LocalWorksets rather than maintaining a parallel descriptive ledger.
   CorePotts retains capability provenance, world-age trust, science, RNG,
   clocks, Hamiltonian folding, transactions, settlement and checkpoints.
5. **CA-4 — diagnostics, documentation and qualification.** Complete stable
   validation fields, reconcile executable documentation, and prove unchanged
   standalone/CorePotts CPU and qualified real-Metal behavior and performance.

No CA slice introduced a second lifecycle, provider scheduler, vendor branch,
new execution family, dynamic lease growth, warm allocation/transfer, hidden
wait, host fallback or domain semantics. The fresh focused review is recorded in
the construction-pain audit. The next fixed-topology adoption witness may now be
considered as a separate bounded gate. Dynamic owner-keyed CPM statistics remain
deferred unless they are representable without per-MCS replanning.

### Post-CA simplification — S0 through S2

**State: S0-S2 sealed on 2026-08-15; further operation migration remains a
separate decision.** The committee-reviewed
[full simplification audit](../design/hardening/post-ca-full-simplification-audit.md)
found 4,067 nonblank/non-comment production lines of LocalWorksets/CorePotts
growth since IC-R0. It authorizes only the common zero-loss intersection below.
The exact pre-edit source, tests, benchmark harnesses, and environment
identities are fingerprinted by the
[baseline content manifest](../design/hardening/post-ca-simplification-baseline.sha256).

Work proceeds in this exact order:

1. **S0 — proven dead-code deletion.** Remove only the reviewed unreachable
   LocalWorksets validation/extraction helpers, ungated CorePotts lifecycle-copy
   family, superseded CorePotts construction overloads, and unreachable old
   checkerboard advance tail. The reviewed direct-deletion floor is 295–305 raw
   production lines.
2. **S1 — LocalWorksets internal deduplication.** Reuse one centrally admitted
   workspace-array traversal, centrally admitted binding/access derivation, one
   typed workspace-tree constructor, and immutable evidence constants. Concrete
   active-prefix, static-topology, topology-transfer/compiler-evidence, and
   execution-family methods remain with their ownership and validation order.
3. **S2 — CorePotts profile and preparation consolidation.** Make one exact
   LocalWorksets execution-lowering profile drive capability and checkpoint
   construction, reuse one CorePotts-owned checkerboard preparation result, and
   materialize the canonical proposal descriptor identity once. Direct and
   LocalWorksets scientific calculation and publication remain independent.

The arithmetic implementation forecast was 533–607 raw production lines, with
an original acceptance band of 500–600. The committee explicitly amended that
numerical criterion after implementation: the floor and ceiling were waived in
favor of independently net-negative slices plus the complete zero-loss evidence
matrix. The
[final implementation review](../design/hardening/post-ca-simplification-review.md)
records the smaller safe result: 367 raw and 358 nonblank/non-comment production
lines removed. Exact slice results are S0 -313/-289, narrowed S1 -30/-34, and
hardened S2 -24/-35 raw/executable lines. The original numerical criterion was
not met; reviewers retained apparent duplication where factoring would weaken
family admission, validation order, backend authority, or specialization.

S0–S2 must preserve public API and diagnostics, inspection tuple order,
capability/checkpoint/report/fingerprint bytes, RNG addresses, Hamiltonian
folding, direct-oracle independence, KernelAbstractions implicit ordering,
launch and synchronization counts, allocation/inference/device-code behavior,
CPU/qualified-Metal results, and cross-domain witnesses. Smoke tests cannot
mint evidence. Complete package CPU and qualified real-Metal review remains the
exit authority.

The S3 CompilerSPI ownership proposal, recursive topology/fact walkers,
settlement/gate factoring, legacy resolved retirement, claim-only candidate
retirement, and direct-oracle demotion remain held. No operation migration or
new LocalWorksets capability is authorized by passing S0–S2. Either requires a
separate explicit gate and owner decision; the simplification seal alone cannot
start it.

### K09 post-simplification adoption gate

**State: K09-R1 sealed on 2026-08-15; corrected direct path retained.** The
owner separately authorized the
[K09 gated state-copy plan](../design/hardening/k09-adoption-plan.md) after the
[K01/K09/L01 suitability audit](../design/hardening/k01-k09-l01-suitability-audit.md).
This is not a continuation or amendment of the sealed LW-5C/LW-5D candidate.

Work proceeds only in this order:

1. **K09-0:** prove the lifecycle staged/science alias invariant and directly
   remove the two recursive selected-state self-copies;
2. **K09-R0:** freeze the corrected direct CPU/real-Metal semantic, launch,
   allocation, queueing, transfer, throughput, capability, and checkpoint
   baseline;
3. **K09-1:** census physical leaves and exact compatible capacity groups;
4. **K09-2:** freeze a grouped independent-copy design using only existing
   LocalWorksets mechanisms, if and only if the census predicts material
   simplification;
5. **K09-3:** build and qualify one private production-shaped candidate only
   after K09-2 admission; and
6. **K09-R1:** conduct a fresh adoption review and either adopt the exact
   candidate or delete it and seal the corrected direct path.

The scan-tail K09 copy remains direct. K01 and L01 remain closed. The two
self-copy passes (`2U` launches in the corrected copy-unit vocabulary) and
their source deletion belong to K09-0 and cannot be credited to
LocalWorksets. K09-R1 requires material net source deletion, a material
`U -> g` direct copy-unit launch reduction, exact no-/inert-/active-lifecycle behavior, twelve
queued MCSs with one final synchronization, CPU/real-Metal noninferiority, and
an exact new capability/checkpoint identity. A failed hold closes K09 without
weakening LocalWorksets or opening another family.

The completed [K09 census](../design/hardening/k09-r0-census-and-admission.md)
found that CPU relationship storage requires a specialized field-wise direct
copy unit and cannot satisfy the reviewed independent-output storage profile.
The [K09-R1 committee](../design/hardening/k09-r1-review.md) therefore sealed
the corrected direct implementation with P0=0/P1=0 and rejected K09-2/K09-3.
No candidate, mechanism, capability identity, or checkpoint branch was added.

## Scope vetoes

LW-4 and LW-5 must not add distributed-memory orchestration, multi-GPU scheduling, cancellation, a
general AD system, solver ownership, scientific clocks, domain physics, a mutable global storage
registry, opaque host callbacks, mandatory MTK/SciMLOperators dependencies, or unbounded graph/
frontier execution. SciMLOperators integration remains an optional wrapper outside the base package.

The deferred MethodOfLines input-field integration remains deferred and is not reopened by this
roadmap.

## Start and exit conditions

LW-4A may begin only from the exact LW-R1-reviewed artifacts. Its first implementation artifact is
the [LW-4A standalone extraction implementation matrix](../design/hardening/lw4a-extraction-implementation-matrix.md),
which covers dependency direction, every public type/function, trust/admission, package loading,
CorePotts parity, CPU and qualified real Metal. The matrix is complete; extraction source work must
follow its ordered holds and exact evidence rows.

G6 remains closed until LW-R2 and LW-R3 pass, the owner records all carried dispositions, and the
owner gives a separate explicit G6 send-off.
