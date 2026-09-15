# Compiler-contract amendment to the PR chain

Status: accepted into the delivery plan by the user on 2026-09-09.
This is implementation scope, not a claim of implementation, qualification,
opened PRs, or new merge/release authority.

## Start here

The [consolidated dependency map](consolidated-pr-dependency-map.md) owns the
allocation and dependency graph: **65 identified PRs = 54 planned + eleven
demonstrated companions**, following the accepted 2026-09-10
[composition-first amendment](composition-first-model-roadmap.md). R51–R54 add
COBREXA/model deliveries, not another compiler-contract PR. R01–R48 retain
their identities. The **G05C** group
contains **R49 Core** and **R50 Potts**, depends on a correct G05 baseline, and
precedes G06/G07 completion. R49 integrates before its R50 consumer.
The seventh companion, **C07**, is the G07 LocalMath ordered-fold step-validation owner
identified by the real finite-resource exchange design. It merged as LocalMath
PR18 with local and hosted CPU/Metal evidence and adds a generic late-validation
channel to the existing executor rather than a transfer framework or another
compiler layer.
The eighth, **C08**, is a G05 LocalMath exact keyed-reduction owner, demonstrated by the
maintained spatial-query design after PR18. Existing destination grouping
requires a pre-existing dense destination and cannot exactly intern sparse,
generation-aware owner pairs with O(E) storage. Its bounded `KeyedReduce`
contract precedes Core R10 pair multiplicity and Potts R11 lowering; it extends
the sole collection executor with canonical ordering and atomic publication,
not with Potts scientific semantics or a second query authority.
The ninth, **C09**, is the demonstrated G05 LocalMath atomic keyed-rebuild owner.
R10's maintained relationship consumer proved that C08's incremental law must
include prior records, while a complete rebuild must ignore them and replace the
bounded collection atomically. Collection clearing/aliasing is not a valid
consumer workaround. C09 adds only that reusable seed/update policy to the same
prepared stages and KernelAbstractions executor, with inclusion carried as
runtime data and no specialization on a completed model claim graph.
The tenth and eleventh, **C10 CorePotts** and **C11 Potts**, are the demonstrated
Cartesian domain-ownership pair. The accepted fixed-exterior/obstacle contract
cannot be represented by the current finite-cell/medium-only runtime and crosses
proposal sampling, relation realization, immutable mutation admission,
checkpoint identity and inspection rather than query mathematics alone. C10
atomically replaces or extends the existing owner classification and owner-at-
site authority with one compact runtime domain-owner/mutable-site
representation; C11 owns its typed authoring and lowering. Face kinds and owner
handles, domain identities/categories, masks and mutable-site counts remain
runtime data. Different face configurations and obstacle masks receive
before/after Kaimon/`code_typed` specialization and IR-shape evidence. Neither
query execution nor checkerboard arbitration specializes on the completed
model's owner graph.

Agents assigned chain work must read the current
[shared map](consolidated-pr-dependency-map.md) and this note before selecting
work or designing a shared interface. Existing worktrees may contain older
copies; repository-relative documents in this `design/` directory are the
portable planning authority.

Use [progress notes](pr-chain-progress.md) for implementation status, not the
existence of a design document. Communicate the actual selected public
interface and candidate package revisions to affected workers. Do not dispatch
opposite sides to invent separate contracts.

G05C, R49 and R50 are planning labels, never live public type names, serialized
modes or runtime branches. Research/implementation experiments remain isolated;
this shared amendment does not authorize modifications to another active
worker's implementation tree.

## Cross-chain compiler-tractability standard

The target architecture is one traceable lowering ladder:

```text
expressive authoring
→ rich semantic IR
→ validated and normalized IR
→ compact operational recipes
→ narrow typed state views
→ small concrete runtime kernels
```

The compiler may remain sophisticated and heterogeneous before preparation; the
prepared program should be deliberately boring. An **operational recipe** is the
sole lowered description consumed by execution: a compact sequence/family of
already validated semantic operations such as read a bound source, compute an
old/new contribution, update an accumulator, or publish a staged value. It is
private preparation output, not another public IR, registry, executor, or copy
of scientific meaning. Its entries refer to the authoritative analyzed facts,
compiled expressions and update laws instead of reinterpreting them.

Stable operation families should expose durable execution meaning rather than
the authoring construct that happened to produce them. Representative families
include ownership transfer, maintained-site sum transfer, cell-state assignment,
relationship creation/removal, lifecycle transition, conserved field transfer
and staged publication. These names are illustrative rather than a required
class hierarchy: add a family only when it removes runtime interpretation or is
shared by demonstrated consumers. Scientific ordering, atomicity, rollback and
publication remain owned by the existing transaction and LocalMath contracts.

A **typed state view** presents only the arrays, scalar parameters, geometry and
staged values required by one recipe family. It must not carry a broad program,
runtime, tracker store or lifecycle workspace merely because those objects own
the data on the host. Kernel signatures should make their tracker/update
semantics apparent to a contributor. Split a kernel only at a durable operation,
publication or transaction boundary; do not shard code solely to improve an LLVM
snapshot.

At a repeatedly executed boundary, the target is concrete arguments and return,
concrete or deliberately narrow-union intermediates, no accidental dynamic
dispatch, zero or explicitly justified allocation, locally proportional typed
IR, and a bounded specialization family. Any unavoidable dynamic boundary is
named and kept on the host. Global zero-`Any` SSA is not a goal: intentional
heterogeneous host orchestration may remain rich when it stops before the
prepared execution boundary.

The contributor workflow owns the general declaration: every PR is `none`,
`host-only`, or `device-reachable`. For this chain, Kaimon is the primary evidence
for device-reachable changes and for host-only changes that alter lowering,
generated execution types, specialization-heavy generic code, runtime payload
shape, or compiler preparation. When Kaimon cannot attach to the exact candidate
worktree, optimized `code_typed`/KernelAbstractions typed-code evidence is an
accepted rapid-development fallback if the reason, exact candidate tuple,
unchanged control, common metric schema and checked-in reproducible runner are
recorded. It is not a universal optimization requirement, and neither tool
qualifies a backend.

### Measured baseline and architectural fitness target

The first canonical accepted-owner-change baseline is retained as a durable
comparison point, not a permanent threshold:

| Observation | G05 baseline |
| --- | ---: |
| Optimized typed statements | 3,730 |
| Calls in typed IR | 2,112 |
| `Any`-typed SSA values | 1,017 |
| `Any` argument slots | 0 |
| Typed method matches for the queried exact signature | 1 |
| Structure runtime summary size | 480 B |
| Structure plan summary size | 232 B |
| Lifecycle workspace summary size | 9,600 B |
| Tracker source summary size | 392 B |

The return is concrete `Bool`; only the mode, indices and owner scalars are
isbits. The architectural finding is therefore broader than inference quality:
one accepted transition crosses a boundary containing too much heterogeneous
state and retains too much semantic responsibility. R49/R50 use this exact
fixture and an unchanged control to test whether normalization moves decisions
earlier, recipes become explicit, state views become narrower, entry-count and
author-name changes reuse execution identity, and the generated kernel becomes
smaller or at least more locally proportional to its real operation family.

The length of an optimized `code_typed` result is a typed method-match count for
the exact queried signature. It is **not** evidence that value, name, count or
model variants reuse one MethodInstance. Specialization-family claims require a
separate identity probe across those variants and a record of the signature
facts that did or did not change. Historical progress notes written as “one
exact specialization” from `length(code_typed(...))` are interpreted only as
“one typed method match” unless they cite such an identity probe.

No single count is the goal. A change that eliminates `Any` while preserving a
multi-thousand-statement kernel or exploding specializations is not sufficient.
Likewise, a readability or ABI cut may be valuable before its typed-IR count
moves, provided the remaining compiler cost is localized and actual execution
still passes. Track inference roots, statement/call count, specialization/code
shape and compile latency together; add allocation and throughput evidence at
declared hot boundaries.

When `Any` appears, identify the earliest owned erasure rather than repairing
every propagated SSA value. Classify it as intentional heterogeneous host data,
an abstract container, erased plan/source storage, captured state, or a hostile
helper boundary. The preferred correction order is normalization, operational
recipe construction, state binding, then a local implementation fix. Generated
functions, `Val`, assertions or unrolled tuples are not first-line substitutes
for a smaller semantic boundary.

Before/after evidence names the exact source/dependency tuple and includes both
the changed boundary and an unchanged control. Report typed-statement and call
counts, inference/result concreteness, specialization or generated-code growth,
root `Any`/dynamic-dispatch sources, runtime-boundary summary size and field
provenance, and compile allocation/time where practical. Record whether recipe
shape/count, author identity or numerical values create new MethodInstances.
Separate construction/preparation,
first compilation or launch, warm execution, allocations and transfers. Actual
Metal execution remains authoritative; Kaimon does not qualify a backend.

Inspect LLVM or backend GPU IR when typed-code evidence or a failed device
compile leaves a compiler-hostile construct unresolved. Record the exact
device-reachable entrypoint inspected and the surviving dynamic call, iterator,
reflection, tuple construction or broad payload that motivated the inspection.
Cleaner LLVM/GPU IR is localization evidence, not the end goal: the scientific
contract, one CPU/GPU semantic path and actual Metal compile and behavior remain
authoritative.

Use AllocCheck as a focused static diagnostic and regression check for exact
concrete hot-boundary signatures, including allocation sites, allocating runtime
calls and dynamic dispatch. Pair it with warmed observed-allocation tests; a
static result alone does not establish the complete runtime path. Use Chairmarks
for reproducible time, allocation-count and allocation-byte measurements. Keep
both packages in test/benchmark environments rather than production dependencies.
TestNoAllocations is not selected because it adds no distinct authority beyond
the warmed observed-call tests.

The allocation-free contract applies only to declared warmed, fixed-capacity CPU
execution boundaries and device kernels. Preparation, compilation, authoring,
resizing, checkpoint creation, diagnostic materialization and transfers are
measured separately. Backend host-launch allocations are not confused with
device-kernel dynamic allocation. Do not gate machine-dependent timing or total
cold allocation with brittle thresholds.

There is no fixed IR-reduction quota. Growth is acceptable only when it is
localized and proportional to the reachable contract. Material unexplained
growth in an unrelated control is specialization coupling. Newly reachable host
work or allocation, lost inference, a changed specialization class, or compiler
resource failure may block independently of a raw count.

Fix inference at its earliest owned cause. Dynamic tuple construction,
reflection, iterator machinery, captured heterogeneous values and broad abstract
containers are evidence to trace back to normalization, recipe construction or
state binding; downstream assertions and LLVM tricks are not substitutes. A
narrowing that materially improves typed IR but still fails Metal selects the
next surviving semantic boundary. Preserve that evidence and continue narrowing
there rather than layering speculative micro-optimizations.

### Device-reachable PR acceptance template

Every PR that creates or changes a device-reachable operation family records
the exact preparation entrypoint and every changed device-reachable entrypoint
it measures; a broad host orchestration wrapper is not a substitute for the
kernel boundary that actually changed. It also records:

1. the public authoring example and sole scientific owner;
2. the semantic decision moved from runtime to normalization/preparation, the
   normalized fact, operational recipe family and narrow state view that connect
   it to execution, and the displaced broad authority/path deleted in the same
   cutover;
3. the durable facts permitted to specialize and the author/model facts required
   to remain values;
4. exact before/after Kaimon, or the documented exact-typed fallback above,
   statement, call, inference and specialization evidence at the changed
   preparation and device boundaries plus an unchanged control;
5. runtime-boundary summary size and provenance for every field crossing it;
6. preparation, first CPU execution, first backend compile/link, warm execution,
   allocations and transfer measurements as applicable;
7. observable scientific, allocation, rollback/continuation and CPU/GPU parity
   tests, including the declared bitwise or replay guarantee where one is
   claimed; and
8. actual Metal compile and behavioral results for every claimed Metal profile.

Host-only PRs use the same template when they alter normalization, recipe shape,
generated execution types or preparation. A PR that merely reuses an established
family may cite its contract and prove identity/reuse rather than duplicate the
whole benchmark. Readability is part of acceptance: current source and tests must
show public entrypoint → owner → validation and dependency/effect analysis →
normalization → recipe → state view → kernel → inspection → owning test without
relying on historical planning labels.

Use one small canonical probe family rather than ad hoc experiments per PR:

1. an unchanged built-in proposal/structural control;
2. structural lifecycle with retained history and compound effects;
3. source-aware maintained sum/minimum contribution and settlement;
4. the G06 checkerboard transition/relational-dependency canary, including
   transitive effects, periodic aliases and shared logical ownership; and
5. the existing G07 held/native-snapshot canary.

G04 records the first exact structural baseline; G05 records the next delta;
R49/R50 make these probes reproducible through a checked-in, durably named
ordinary benchmark runner with the canonical fixture, unchanged control and
machine-readable output. It is evidence infrastructure, not a pass/fail policy
gate. Add a probe only when a later PR introduces a genuinely new compiler
family or supported conjunction. Do not create a second IR, compiler registry,
optimization framework, or policy-gate script.

### Cold-compilation and cache-reuse contract

The 2026-09-11 cold-compilation audit of ModelingToolkit/Symbolics, SciMLBase/
OrdinaryDiffEq, Lux, StaticArrays and the KernelAbstractions/GPUCompiler/Metal
stack reinforces the existing owner split. The common successful pattern is an
explicit preparation boundary, a small reusable execution signature, bounded
static structure, and representative rather than combinatorial precompilation.
PrecompileTools, package images, runtime-generated functions, backend caches and
developer sysimages can preserve work only after equivalent public models reach
equivalent MethodInstances and compiler configurations. They do not repair an
author-specific executor surface.

R49 therefore owns the canonical Core execution identity. Within one admitted
execution class, changing author names, quantity keys, tracker keys or numerical
parameter values must not change the prepared hot payload type or code-instance
class. Entry count and composition are value-level up to the declared bounded
capacity unless a measured semantic ABI distinction justifies specialization.
Durable physical facts such as backend, scalar representation, dimensionality,
algorithm and a demonstrated bounded value shape may distinguish execution
classes. Record every additional specialization fact and the evidence that its
runtime value exceeds its cold-compile and cache-fragmentation cost.

R50 owns erasure of author-facing identity and irregular analyzed-model structure
before Core preparation. Rich names, scopes and source locations remain available
to inspection and diagnostics on the host; they are not kernel arguments or hot
type parameters. Package-declared PottsModels models and interactively constructed
equivalent models use the same lowering and execution path.

Measure a fresh process as separate stages: package load, public construction,
completion/validation, lowering, preparation/binding, first CPU execution, first
backend compilation/link, and warm execution. Also compare numerical remake,
author-only rename and structural rebuild. Record MethodInstance/generated-code
growth and package-cache size where practical. Do not collapse dependency
precompilation, Julia inference, LLVM/backend compilation, device linking and
ordinary initialization into one unexplained cold-time number.

Research references: [ModelingToolkit precompilation-friendly components](https://docs.sciml.ai/ModelingToolkit/dev/basics/PrecompileComponents/),
[SciMLBase specialization controls](https://docs.sciml.ai/SciMLBase/dev/interfaces/Problems/),
[OrdinaryDiffEq v7 migration](https://docs.sciml.ai/DiffEqDocs/stable/migration/ordinarydiffeq_v7/),
[Lux compiled models](https://lux.csail.mit.edu/dev/manual/compiling_lux_models),
[StaticArrays compiler-size guidance](https://github.com/JuliaArrays/StaticArrays.jl),
[PrecompileTools](https://github.com/JuliaLang/PrecompileTools.jl), and the
[JuliaGPU compiler stack](https://github.com/JuliaGPU/GPUCompiler.jl).

### Rejected latency shortcuts

The following are explicit design constraints, not unallocated future options:

- Do not encode arbitrary author names, symbols, model graph identities,
  component counts or tracker counts in `Val` or type parameters.
- Do not replace dynamic tuples with large StaticArrays or other fully unrolled
  structures. Static representation is reserved for genuinely small, bounded
  mathematical values with measured benefit.
- Do not build an exhaustive PrecompileTools workload matrix. Precompile a small
  public corpus after its executor signatures are stable.
- Do not expose `NoSpecialize`/`AutoSpecialize`/`FullSpecialize`-like public
  modes without demonstrated user workloads that cannot share one strong
  default. A compiler-development choice is not automatically product semantics.
- Do not introduce runtime-generated functions, `@generated` functions or giant
  emitted evaluators inside the device path merely to conceal broad payloads.
  If LLVM cost remains after canonicalization, shard only at an existing semantic
  owner boundary and defend identical behavior.
- Do not create a GPU-only scientific shortcut, alternate executor or traced/AOT
  model path to improve latency. CPU and qualified GPUs retain one semantic
  KernelAbstractions path unless a demonstrated backend contract requires a
  backend-specific implementation of the same operation.
- Do not treat PackageCompiler, GPU disk caching, longer CI caches or larger
  package images as substitutes for a stable executor boundary. These may be
  opt-in developer/deployment accelerators and must report rebuild and artifact
  costs.
- Do not serialize live device modules, compiler handles or backend caches in
  checkpoints or portable model state. Persist logical scientific and prepared
  host identity only where its continuation contract permits it.

## R49 — Core quantity consumption and maintenance contract coherence

- Derive direct executable requirements and maintenance-source queries from
  their authoritative representations.
- Validate qualified consumption against the actual published/hypothetical
  context and law-specific update contract.
- Preserve coherent snapshot reads and physical source-parent validation through
  existing storage/BackendSPI machinery.
- Clarify proposal-evaluation versus accepted-maintenance/reconstruction costs.
- Keep descriptors, closed update/storage strategies, capability/profile
  validation and public extension protocols truthful and consistent.
- Include ordinary Core tests, public construction/extension examples,
  source-aware failures, nearest docs and applicable real-device qualification.

Do not implement generic mutations, swaps, topology, a new snapshot framework,
a global capability registry or speculative numerical modes in this PR.

### First measured device-boundary cut

The first R49 implementation candidate replaces only the structural-lifecycle
kernel's broad `TrackerKernelPlan + TrackerState` accepted-update boundary. Cold
preparation derives one compact accepted-update recipe from the authoritative
`TrackerExecutionPlan` and `TrackerContract`; launch binding supplies only the
staged values, source arrays and parameters required by those prepared entries.
The device path must not reconstruct `TrackerContract`, carry author quantity
identities, or traverse reconstruction-only trackers merely to reject an
incremental update law.

Prepared incremental entries retain the existing scientific owners:

- ownership count carries its values and delta meaning;
- moments carry values with dimension and leaf type in the entry type;
- surface updates carry values, relation handle and neighbor bound;
- site sums carry values, the already compiled expression, exact bound source
  arrays, parameters and parameter arity/type; and
- admitted external old/new trackers carry adapted descriptors, values and the
  once-resolved storage semantics required by `tracker_ownership_delta`.

Common launch data is limited to ownership geometry and the old/new ownership
transition. Author-facing quantity keys, tolerances, checkpoint/support/cost
metadata, and unrelated program/runtime objects stay on the host side.
Full-lattice reconstruction entries are excluded: the existing LocalMath
snapshot, structural mutation and reconstruction law remains their sole update
owner. This payload is private lowering, not a public IR or built-in-only closed
executor.

The cut must preserve the existing entry preflight, validation, application,
completion preflight, finish, rollback and device-status translation semantics.
It must use the same prepared entry methods for host and backend paths. Ordinary
checkerboard accepted-copy lowering is already host-lowered into LocalMath laws
and is outside this first replacement; use it as an unrelated control rather
than rewriting it.

Before adopting the candidate, compare exact sum-only and mixed minimum+sum
structural lifecycle tuples at the complete commit and `_stage_owner_change!`
boundaries; retain leaf contribution and entry/completion preflight probes plus
unchanged ownership+moments and accepted-copy controls. Compare one, two, four,
eight and sixteen incremental entries within the same declared capacity, and two
otherwise identical sums with distinct author quantity keys: their bound update
payload types/code instances should be identical while host lookup and diagnostics
remain distinct. Compare a parameter-value remake without rebuilding executable
identity and record any permitted structural rebuild. Measure cold recipe
construction separately from per-launch binding, inference, Julia/LLVM code
generation, first backend compile/link, warm execution, specialization count and
type size. Real CPU behavior and Metal sum/grouped/mixed-minimum/overflow/recovery/
rollback/checkpoint fixtures remain authoritative. If typed IR narrows but Metal
still fails, localize the next surviving semantic boundary from that evidence;
do not substitute speculative micro-optimization.

The focused R49 allocation target covers lifecycle planning, ownership count,
moments, surface updates, standalone/grouped sums, the complete owner-change
boundary and unchanged accepted-copy controls. Warm each fixture before its
observed-allocation assertion. AllocCheck failures identify the reachable call
chain; Kaimon determines whether the correction also changes inference,
statement/call counts or specialization. Do not apply AllocCheck to the complete
package indiscriminately or move host-only diagnostics into kernels merely to
satisfy an allocation check.

## R50 — Potts resolved quantity and dependency lowering cutover

- Resolve aggregate contribution, scoped bindings, policy and maintenance
  dependencies once in analyzed IR, using existing identities/value facts.
- Cut over tracker, evaluator and read lowering together; delete repeated source
  interpretation and displaced handle bookkeeping.
- Preserve direct reads alongside aggregate reads and dependencies through
  ordinary finalized expressions such as mean over shared mass/count.
- Preserve relation multiplicity/measure, numerical identity and declared
  temporal use. Historical/held values are not freely reconstructible caches.
- Retain source provenance for construction/use failures, and validate the public
  operation extension path without private execution access.
- Measure host compilation and source-update fan-out; do not assert performance
  from structural simplification alone.
- Extend the R49 allocation probes through public Potts authoring. Two programs
  differing only in author-facing quantity identity must lower to the same hot
  payload type/code-instance class while preserving distinct host diagnostics.
  Record Chairmarks preparation, first-execution and warmed allocation samples.
- Prove that a package-declared PottsModels composition and an equivalent
  interactive composition reach the same analyzed fact, bounded semantic payload
  and Core execution path. Author names and source provenance remain host facts;
  parameter values remain data; only documented semantic ABI facts specialize.
- Keep author-specific construction/lowering cheap and measurable before the
  reusable deep executor boundary. If a large evaluator remains expensive after
  this cutover, localize its semantic groups before considering bounded sharding.

Do not materialize every derived expression or introduce a general optimizer,
pass manager, second host IR, second executor or compatibility implementation.

## Defending workflow and completion boundary

Use public authoring for the canonical end-to-end compiler-health workload:

changing field → maintained per-cell aggregate → intracellular dynamics →
conservative exchange/motion consumer → division → observation → checkpoint
continuation, with multiple consumers and finite-resource contention.

The smaller shared mass/count → mean workflow remains a focused R49/R50 probe;
it does not replace the complete R16/R17/R20 public workload.

Include aggregate-only and mixed direct reads, distinct/same semantic identity,
empty finalization, coherent snapshot publication, source-parent invalidation,
and rejection of unsupported hypothetical minimum use. Public examples cannot
be replaced by manually constructed Core fixtures. Preserve existing admitted
science, history, RNG addressing, identities and continuation.

Candidates may develop alongside G05. R10/R11 must still finish their required
sum/minimum, geometry/relations, numerical, source-mutation and lifecycle
correctness; do not defer these failures to G05C. G06/G07 can explore early but
complete only after the coordinated contract cutover. Test the actual complete
candidate dependency selection and use appropriate version/compat ordering:
LocalMath → Core → Potts → Models/Makie. No temporary aliases or parallel
production implementations bridge incompatible package versions.

## Explicit R49/R50 acceptance criteria

R49 and R50 remain the only additional compiler-contract PRs. Do not add a
third speculative compiler/framework PR or preallocate cosmetic cleanup.
The following work belongs inside their implementation and completion criteria:

- Defend the complete public vertical workflow above, including aggregate-only
  and mixed direct/aggregate reads, distinct and shared semantic identities,
  empty finalization, coherent publication, source-parent invalidation and
  rejection of unsupported hypothetical minimum reads.
- Exercise current settled consumption, transaction-entry/candidate or
  hypothetical consumption, held/native-sampled consumption and historical/
  retained consumption explicitly. Positive cases use admitted contracts;
  unsupported hypothetical contexts get negative tests. Held/history values
  must not be collapsed into reconstructible caches.
- Include a concrete deletion/cutover inventory in ordinary PR descriptions:
  list displaced aggregate interpretation, duplicate handle bookkeeping,
  compatibility paths and lowerings, their sole replacement owner, and the
  defending tests. Remove the displaced paths in the cutover. This is normal
  review evidence, not a new registry or mandatory policy script.
- Measure before/after host specialization and generated-code growth,
  construction/preparation, source-update fan-out, relevant allocations and
  transfers, and warm execution. Fresh-process evidence separates package load,
  construction, completion/validation, lowering, preparation, first CPU
  execution, first backend compile/link and warm execution. Include numerical
  remake, author-only rename and structural rebuild, plus MethodInstance/code and
  package-cache growth where practical. Record the candidate/dependency profile
  and limitations; use no brittle wall-time gates and infer no speedup merely
  from structural simplification.
- Require focused AllocCheck success and warmed zero-observed-allocation tests
  only for the explicitly declared fixed-capacity Core/Potts hot boundaries.
  Preserve Chairmarks samples for those boundaries and their public-model
  consumers. A failure is localized and fixed in its scientific/execution owner;
  it is not waived by a faster median or transformed into a global zero-allocation
  claim.
- Include the canonical host and device-reachable Kaimon probes, with an
  unchanged control, and leave a reproducible ordinary runner for later owner
  PRs. CI may fail on unsuccessful canonical compilation or applicable actual
  device execution; raw statement/call deltas remain review evidence rather
  than fixed thresholds.
- Before freezing the R49→R50 interface, run two bounded downstream canaries
  against the actual candidate package tuple: one G06-oriented transition/
  relational-dependency case and one G07-oriented held/native-snapshot case.
  The G06 canary uses one immutable batch snapshot and includes two proposals
  whose site claims appear disjoint but whose transitive read/write/effect
  footprints meet through a maintained value, incident relation, periodic alias
  or shared logical owner. Positive controls share only read state or an effect
  whose owner proves commutative, associative composition, so the boundary must
  retain compatibility as well as conflict facts. The canary must preserve
  G05's explicit rejection because R12/R13 do not exist yet, while proving
  R49/R50 retain enough normalized
  transition, dependency and source identity for the later owner to make the
  decision without recovering an author graph at runtime. Select a real existing
  admitted operation/context and an explicit rejection where appropriate.
  Exercise dependency/snapshot meaning, not just construction. These test the
  interface; they do not implement G06/G07 early or establish their full
  scientific qualification.
- Make the external-operation trust boundary explicit: contextual sources are
  declared, hostile captured mutable-state cases reject where detectable, and
  the public extension example uses no private execution API. Do not claim
  arbitrary Julia callables are proven pure.
- Update source maps and nearest docs; defend actionable source-linked errors.
  Require full changed-owner, integration, docs and applicable actual-device
  validation for the complete candidate, in addition to focused tests.

R49 owns Core consumption/context/maintenance coherence; R50 owns Potts
analyzed facts, transitive dependencies and atomic lowering cutover. Existing
G05–G09 and breadth owners retain all scientific obligations. At post-G08/G09
closure, audit actual cross-family usage and measurements: a concrete remaining
correctness, readability or measured cost problem triggers a targeted owner
follow-up and an explicit count update if needed. The audit does not presume a
third compiler PR, a cosmetic cleanup train or a framework rewrite.

### Checkerboard conflict-closure evidence

G06 R12/R13 must demonstrate the semantic outcome without freezing a conflict
graph, coloring, footprint encoding, winner-selection data structure or kernel
decomposition. Evidence covers:

- one immutable entry snapshot for every evaluation in a batch;
- complete transitive read/write/effect closure across direct site state,
  maintained quantities, relationships, lifecycle effects, periodic aliases
  and shared logical owners;
- explicit compatibility classification: read/read overlap is compatible;
  incompatible read/write and write/write overlap and noncommuting effects
  arbitrate; shared effects are compatible only when their owner proves
  commutative, associative composition under the declared numerical, ordering
  and publication contract;
- a deterministic backend-independent winner set, with specified accounting for
  scheduled attempts, non-no-op proposals, conflict losers and winners;
- joint admission of proposals whose complete footprints are independent, so a
  conflict-everything implementation cannot satisfy the contract;
- failure-atomic compound commit/rollback for every winning transition; and
- actionable admission/runtime diagnostics derived from the production
  dependency authority rather than a reporting copy.

At each device-reachable boundary, normalize author structure on the host and
pass only the bounded semantic payload needed for snapshot evaluation,
dependency closure, arbitration or commit. Do not pass a broad program/runtime
object, reconstruct the authored dependency graph, reflect over dynamic tuples
or iterators, or duplicate conflict facts for diagnostics. Narrowing may split
semantic phases, but it must not create another executor or a GPU-only scientific
shortcut.

The completed model's claim graph is runtime data, not executor identity.
Lower its normalized vertices, edges, compatibility classes and source handles
into compact bounded arrays/tables consumed by reusable operation-family laws.
Author names, concrete graph contents, owner identities, adjacency and ordinary
entry counts must not appear in hot type parameters, nested tuple types, `Val`
axes, generated functions or emitted model-specific kernels. Specialization is
limited to measured durable facts such as backend, scalar representation,
dimension, operation family and genuinely small bounded value shape. Compare
MethodInstance/code-shape identity across author-only renames, isomorphic graph
renumberings, distinct graph contents and bounded entry-count ladders; a new
specialization requires evidence that its runtime value exceeds compile/cache
fragmentation cost.

Use exhaustive tiny batches and an independent full-state oracle for isolated
winners and their compound effects. Sequential application is not a checkerboard
trajectory, ordering or kinetics oracle. Add randomized small-batch differential
tests, permutation/metamorphic cases and exact CPU-versus-
claimed-device winner/commit comparisons. Exercise the sole KernelAbstractions
semantic path on real hardware. Kaimon or matched `code_typed` evidence compares
dependency preparation, arbitration and commit statement/call counts, type
stability and specialization growth against the G05C canary and an unchanged
control; inspect LLVM/GPU IR when it locates remaining hostile constructs.
Warmed allocation and payload-size checks apply at the declared fixed-capacity
hot boundaries. Raw compiler counts and timings are trend evidence, while real
backend compile and behavioral results are authoritative.

Include positive shared-read-only and owner-proven commutative/associative-effect
controls alongside every conflict class. For an admitted batch, a no-op,
conflict loser or semantically rejected proposal leaves state unchanged and
does not receive a compensating attempt; a statically rejected conjunction does
not launch. Preserve declared semantic RNG addressing and prove unrelated-stream
invariance under filtering, arbitration and permitted launch permutations.
Assert only draws required by the realized semantic categories, not consumption
of unused draws. Advance subround time by the realized checkerboard color
fraction, independent of winner count.

G07 adds held/native snapshot state to the same batch-pressure fixture. G09
retains it in the public compiler-health corpus. E01, E03, E08, E11 and E12 add,
respectively, 3D periodic/shared-owner, opposite relationship endpoint, global
predicate, compound swap and weighted-graph pressure cases. A failing later
case first returns to R12/R13's Core/Potts owner unless it demonstrates a
genuinely reusable LocalMath mathematical law. Only that narrow demonstrated
gap may add a LocalMath companion. R10 has now demonstrated exactly one such
gap: C09 atomic keyed rebuild, raising the allocation to 63. The later
maintained-query audit demonstrated C10/C11 Cartesian domain ownership, raising
the allocation to 65. This does not authorize additional companions without
another real consumer and a coherent owner-law gap.

The owning G06 suite includes exact shared-owner conflicts and positive
independence controls. Periodic moment cases whose image labels differ only by
gauge must yield identical canonical physical observables and energies, closure
and winner identities, and gauge-equivalent committed moment state. Require raw
image-label or moment-state identity only if G05 establishes a unique canonical
gauge. R12/R13 atomically remove the corresponding G05 rejection only for newly
qualified conjunctions; unchanged unsupported conjunctions continue to reject
rather than fall back or enter a compatibility path.

## Retrospective compiler-debt sweep

Do not grandfather merged compiler-sensitive work, and do not reopen every
completed PR. Before R49/R50 freeze their baseline, run one bounded comparison:

| Completed work | Initial impact | Required retrospective treatment |
| --- | --- | --- |
| R01/R02 model ownership and public compositions | Host-owned consumer surface; device-reachable where a selected model enters a supported device path | Include representative public models in the baseline corpus; no per-commit archaeology unless a regression appears. |
| R03-R05 and the Models timeout companion | None; CI/workflow only | No Kaimon debt sweep. |
| R06 Potts operation contracts | Device/compiler-sensitive | Compare operation/executable lowering and one unrelated device control before/after the merge. |
| R07 Core scientific contexts | Device-reachable | Compare proposal/context and scientific-geometry boundaries plus an unchanged control. |
| LocalMath PR12, PR13, PR14, PR16, PR17, PR18, PR19/C08 and C09 | Device/compiler-sensitive | Compare the pre-companion and current merged tuples; bisect the linear companion sequence only if growth or a failure appears. PR19 supplied its feature-local Kaimon, allocation, CPU and real-Metal comparison before merge; C09 supplied the corresponding incremental-versus-rebuild comparison before merge. |

The remaining chain applies the ladder prospectively rather than accumulating a
second retrospective tail:

| Delivery owners | Compiler-boundary obligation |
| --- | --- |
| R08–R09 | Keep rich component identity, scopes, provenance and structured authoring in semantic analysis; normalize them before preparation and prove constructor-equivalent programs reach the same recipe families. |
| R10–R11 | Express maintained sum/minimum work as validated contribution, update, reconstruction and publication operations; do not pass quantity declarations or broad stores into device code. |
| R49–R50 | Establish the canonical recipe/state-view boundary, specialization policy, boundary-size baseline, root-inference audit and reusable probes. Delete the displaced runtime interpretation in the same cutover. |
| R12–R13 | Lower energy, drive and dependency meaning into bounded operation families with explicit transition/context inputs and unchanged scientific semantics. |
| R14–R16 | Give native/lifecycle/coupling operations narrow cadence, binding, snapshot, settlement and publication views; external solvers retain their native owner outside CPM kernels. |
| R17–R20 | Exercise public model compositions through the same path and maintain the compiler-health corpus, fresh-process latency stages and longitudinal specialization/allocation records. |
| R21–R48 and R51 | Each new dimension, mechanic, solver, backend, move, graph or optimization boundary either reuses an established recipe family or supplies feature-local evidence for a genuinely new one. |
| R52–R54 | Treat the FBCA, vascular and tumor corpora as realistic compiler-health workloads; package and interactive equivalents must share preparation and execution identity. |

This assignment adds no PR. A distinct, measured semantic boundary that cannot
fit its scientific owner may earn a counted companion under the ordinary rule;
mere IR size, chronology or desire for cleanup does not.

Existing CPU and actual-Metal results remain valid for their exact revisions;
this sweep addresses missing specialization-coupling baselines rather than
discarding prior qualification. Fix a discovered problem in a coherent open
owner PR where possible. If that would hide unrelated work, add and count a
narrow targeted owner companion. No additional compiler PR is presumed.

## Pressure-test findings retained in later owner PRs

| Contract distinction | Required case / implementation obligation | Owner |
| --- | --- | --- |
| Copy versus compound transition | A swap is one atomic transition; individual deltas need not sum to a joint delta. Bind proofs to admitted transitions. | G06; actual swap E11 |
| Measure and relation multiplicity | Count differs from volume; repeated contacts differ from distinct neighbors; preserve weights and pair conventions. | G05, E03, E12 |
| Inverse and changing dependencies | Directed reads require inverse traversal; membership/endpoint changes can invalidate without a field-value write. | G06, E03, E04 |
| Current versus held/hypothetical use | Preserve sampling cadence and snapshot meaning; don't refresh held native inputs as if stale caches. | G05C, G07, E05/E06 |
| Coherent derived expressions | New mass over old volume is invalid; share sufficient statistics only where meaning agrees. | G05/G05C, G07 |
| Measurement versus exact predicate | A sampled connectivity value cannot validate a hypothetical deletion. Supply the actual algorithm. | E08 |
| Publication versus conservation | Valid-shaped concentration increments can create mass; transfers own measure/availability/positivity. | G07, E07 |
| Algebra versus numerical/replay policy | Float reduction order, precision and permitted reconstruction affect values and sharing. | G05, G05C, E09/E10 |
| Shape genericity versus geometry | Periodic seam centers, anisotropic measures and 3D/graph conventions need scientific tests. | G05, E01, E12 |
| Array rollback versus full logical rollback | Restore clocks, event state, solver state, RNG and slot generations; state failure guarantees precisely. | G07, E05/E06 |
| Marginal support versus full conjunction | Independent engine/backend flags do not prove every combination; reuse actual capability authority. | Every execution owner, E09/E10 |
| Per-law bounds versus program cost | Measure fan-out, preparation, parent snapshots, transfers and compile specialization separately. | Owner PRs; G09 consolidation |
| Energy versus sampling law | Correct energy alone does not establish forward/reverse proposal probabilities or equilibrium semantics. | E02, E11, E12 |
| Concrete callable versus purity | Declared extension effects are a trust boundary; hidden mutable dependencies cannot be inferred from argument syntax alone. | G05C, G06, G08 |

These obligations do not expand every earlier group to implement later breadth.
Unsupported combinations must reject now; their promised later owners must
eventually implement them rather than claim completion through rejection alone.

## Evidence and guardrails

The isolated conceptual Julia script passed **60 assertions in 14 testsets**.
It imports only Test. It demonstrates counterexamples to simplifying assumptions;
it does not qualify any package, prove the proposed SPI correct, establish
race freedom, or benchmark performance. Preserve ordinary scientific oracles,
full relevant package/integration/docs checks and applicable actual hardware
evidence in the implementing PRs.

The retained pressure-test findings and counterexamples are summarized in this
amendment. A developer-local investigation checkout is not active provenance or
a prerequisite for understanding the plan. Transient research paths are not
runtime dependencies; transplant a qualified prototype result into the sole
production path and delete the displaced prototype when appropriate.

No extra framework, cosmetic cleanup, or placeholder vendor PR is allocated.
A demonstrated missing event-settlement or reusable transfer/publication
primitive earns a companion in its actual owner and updates the count.
Existing companions are already counted in the **65 currently
identified PRs**. That identified count is not a ceiling.

A world-class completion means promised public science actually works, laws are
independently tested, extensions are documented, errors are actionable, source
is navigable, continuation is coherent, and compile/runtime costs are measured.
Neither a clean diagram nor a fixed PR count substitutes for those outcomes.
