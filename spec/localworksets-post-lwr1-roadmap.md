# LocalWorksets Post-LW-R1 Extraction and Adoption Roadmap

Qualification and review mechanics are governed by
`design/hardening/lw4q-qualification.md`. LW-4Q does not change this roadmap's
architecture or phase boundaries.

Date: 2026-08-10

Status: LW-4A, LW-4B, LW-4C, and final LW-R2 complete; LW-4 frozen; LW-5 open;
G6 closed

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
  -> LW-5 compiled local-operation adoption -> LW-R3
  -> explicit owner G6 send-off
```

LW-4 establishes a coherent standalone execution package. LW-5 makes PottsToolkit and CorePotts
ordinary consumers of that package by lowering eligible compiled operations into local work. No
gate transfers domain physics, clocks, RNG identity, scientific transactions, checkpoint meaning,
solver semantics or ModelingToolkit ownership into LocalWorksets.

No later subgate begins early. P0/P1 findings block advancement. Every P2 requires an explicit
owner and disposition before the next review boundary.

## Preserved architecture

The following decisions remain closed unless an executable extracted-package prototype exposes a
genuine contradiction:

- package name `LocalWorksets.jl`;
- public mental model `LocalWork -> WorkPlan -> PreparedWork -> WorkEvent`;
- lifecycle `localwork -> plan -> prepare -> run! -> wait`;
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

No public production promotion or LW-5 adoption begins before LW-R2 clears.

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

### LW-5A — Representability and preservation inventory

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

### LW-5D — Adoption qualification

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

A fresh committee reviews semantic preservation, compiler cohesion, LocalWorksets generality,
JuliaGPU performance, MTK/SciML boundaries and the public Potts authoring experience. It must verify
that adoption removed bespoke execution machinery where justified without moving domain semantics
downward or turning LocalWorksets into the hidden CorePotts engine.

LW-R3 may authorize a later public/default promotion decision. It does not automatically delete the
direct oracle or open G6.

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
