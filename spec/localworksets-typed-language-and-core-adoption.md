# Typed LocalWork and CorePotts Adoption

Date: 2026-08-17

Status: completed implementation record through Gate 8C.4; package identity,
public authoring grammar, and future work order are superseded by the
committee-accepted [LocalMath Direct Cutover](../design/evidence/localmath/localmath-direct-cutover.md)

## Successor program

The LocalMath direct cutover is the accepted next immediate architectural
program. This file remains authoritative evidence for completed LocalWorksets
execution adoption, packed runtime state, deterministic ordering, one prepared
pipeline, KernelAbstractions execution, and the unresolved compiler-health
finding. Do not continue Tranche 5 before the successor specification is
implemented from LM-0.

## Decision

The implementation strengthens the existing LocalWorksets hourglass:

```text
typed or programmatic domain authoring
                |
                v
             LocalWork
                |
                v
           _LoweredWork
                |
                v
   one concrete ordered phase tuple
                |
                v
       one prepared-phase runner
                |
                v
 KernelAbstractions and admitted private primitives
                |
                v
           CPU and GPU
```

`LocalWork` remains the sole common semantic IR. `_LoweredWork` remains the
sole private planning envelope. `WorkPlan`, `_PreparedPipeline`, concrete
prepared phases, provider leases, failure poisoning, and the one recursive
phase runner remain the execution lifecycle.

The implementation MUST NOT introduce:

- a persistent phase DAG;
- an SSA, def-use, or general liveness graph;
- a public scheduler or task graph;
- a generic runtime phase interpreter;
- a second scalar, tensor, stage, or port IR;
- runtime symbolic expression objects on device paths;
- an old/new execution selector, compatibility shim, or migration layer;
- LocalWorksets ownership of Hamiltonians, semantic RNG, Metropolis
  acceptance, MCS scheduling, lifecycle meaning, scientific transactions, or
  checkpoint continuation.

## Phase 0 baseline

The baseline is the current working tree rooted at Git commit
`bc5729f3db636c936ad2dfee46c5d1f1ced56059`. It contains substantial
uncommitted architectural work and is therefore treated as authoritative;
later edits preserve unrelated changes rather than reconstructing from HEAD.

Because the baseline includes untracked source that cannot be reconstructed
from Git HEAD, the complete working tree excluding `.git` was preserved before
Phase 1 at:

```text
/tmp/potts-localwork-phase0-20260817.tar.gz
sha256 6eedc42f025e3facbd6e083b8ee54dfd9a23fda237944576c1126a1d0d61cb54
```

This snapshot is recovery evidence only. It is not a migration artifact or a
production execution alternative.

Initial production census:

| Measure | Baseline |
|---|---:|
| LocalWorksets source lines | 11,849 |
| CorePotts direct `@kernel` definitions | 40 |
| CorePotts production mechanical `@kernel` definitions | 37 |
| CorePotts compiler/device probe kernels | 3 |
| LocalWorksets source `@kernel` definitions | 14 |
| Combined production source kernels | 51 |
| Persistent common semantic IRs | 1 (`LocalWork`) |
| Persistent private lowering envelopes | 1 (`_LoweredWork`) |
| Prepared pipeline envelopes | 1 (`_PreparedPipeline`) |
| Phase execution families | 1 |
| Retired mathematical authoring macros | 1 |
| Publicly constructible semantic/authoring value types | 28 |
| Lowering/composer/auxiliary strategy representations | 9 |
| Semantic leaf strategies / execution profiles / composers | 4 / 6 / 1 |
| Plan phase / prepared phase types | 14 / 14 |
| Prepared phase executor methods | 14 |
| Distinct `_validate_...` validator names | 45 |
| LocalWorksets nonblank / code-like source lines | 11,196 / 11,098 |

The CorePotts production denominator excludes only
`descriptor_group_probe_kernel!`, `evaluator_probe_kernel!`, and
`descriptor_probe_kernel!`. The host sequential CPM engine is a scientifically
distinct state-dependent algorithm and is not a device-mechanical kernel
candidate.

Phase 0 committee disposition:

- compiler/Julia baseline and kill-criteria review: pass;
- scientific/maintainability census and recovery review: pass after the
  complete working-tree snapshot above was verified; and
- GPU/provider review: pass for beginning architectural work, with release
  qualification deliberately still closed beyond the reviewed Apple-M1 CPU
  and Apple-M1-Pro Metal environments.

CUDA and AMDGPU currently have partial downstream runners but no reviewed
LocalWorksets admission row; oneAPI has no dedicated runner. Later phase gates
MUST NOT claim those backends until the full provider, workspace, failure,
LocalWorksets, lifecycle, and scalar-disabled hardware evidence exists. The
two direct CorePotts transaction synchronizations and keyed-work
`lease_capacity == 1` restriction are also recorded later deletion targets.

## Cross-phase rules

Every phase is a direct pre-release edit. The superseded implementation and
its tests are removed in the same phase. Independent scientific reference
implementations may remain in tests, but no parallel production path remains.

Each phase ends with an independent compiler/Julia, GPU/performance, and
scientific/maintainability review. A gate is an evidence boundary, not a
migration mechanism. A phase fails if it:

1. adds a semantic authority or execution family;
2. accepts a feature through a fallback path;
3. adds a persistent runtime IR for authoring syntax;
4. changes deterministic order, RNG addressing, transaction meaning, or
   checkpoint continuation without an explicit scientific decision;
5. adds a public mechanism without two unrelated witnesses or an immediate
   CorePotts deletion target;
6. retains the superseded production implementation;
7. hides workspace, launches, dependency versions, or failure visibility from
   inspection; or
8. fails actual compilation on every backend for which support is claimed.

## Phase 1 -- typed authoring foundation

Add one syntax-only `@localwork` macro that lowers immediately to an ordinary
concrete isbits callable and existing `LocalWork` declarations. Delete the
retired scalar-authoring macro and envelope directly while retaining
`SourceOrigin` and direct operation qualification.

The initial grammar owns ordinary scalar assignments, typed static local
tensor equations, explicit typed port laws, bounded emission lanes, and
publication contributions. Syntax markers disappear during macro expansion.
No authoring type survives in `LocalWork`, planning, preparation, inspection,
or execution.

### Closed Phase 1 grammar

```text
@localwork item in items begin
    declaration-preamble
    scalar-or-tensor-calculation
    publication-contributions
end

declaration :=
    @read local
  | @read local = source
  | @value local
  | @value local = submission_name
  | @axis index in 1:positive_literal
  | @active active_selection
  | @gate binding_name
  | @port name::T = output_declaration

calculation :=
    scalar_name = eager_expression
  | tensor[declared_axes...]::T := eager_expression

publication :=
    port ← contribution
  | port[positive_literal_lane] ← contribution
  | port[declared_axes...] ← contribution
```

Declarations form one preamble. Scalar and tensor calculation precedes all
publication. Port declarations use existing `independent`, `combined`, or
`resolved` values and must state the same exact value type as the annotation.
Every declared port has exactly its statically declared maximum number of
contribution lanes.

Output brackets denote authoritative local lane positions only. Literal lanes
and expanded Cartesian lane families must produce each position in
`1:maximum` exactly once. Runtime destinations remain arguments of keyed
`emit` or `candidate` values; a local tensor or port index never changes into a
global destination.

Tensor storage is one exact `StaticArrays.SArray`. Its axes are positive
one-based literal ranges, the first declared axis varies fastest, every
element is evaluated once in Cartesian order, and every element has the exact
declared type. Tensor reads admit only correct-rank in-bounds literal indices
or declared axes that the translator replaces with literals. Runtime local
tensor indexing rejects.

Conditions on `emit` and `candidate` control participation only. Value, rank,
payload, and condition expressions are evaluated eagerly and exactly once in
written order. Scalar statements and contribution right-hand sides execute in
source order; construction of the final canonical named tuple occurs only
after those values have been bound.

Phase 1 admits only reviewed nested expression macros, initially
`Base.@inbounds`. Syntax forms for dynamic control flow, short-circuiting,
nested or mutation assignment, loops, comprehensions, generators, functions,
closures, `let`, `try`, tasks, explicit `return`, and unreviewed macros reject.
Ordinary call expressions are opaque to this syntax translator and may have
effects; the operation trace deliberately uses one such call to prove ordering.
Capture qualification, callable inference, and selected-device compilation
remain authoritative for whether an ordinary call is admissible.

Static budgets are:

| Budget | Limit |
|---|---:|
| axes | 4 |
| extent of one axis | 32 |
| materialized local tensors | 1 |
| cells in that tensor | 64 |
| total emission lanes | 32 |
| named ports | 8 |

The resulting operation must be concrete and isbits. Recognized captured
memory authorities are forbidden: Julia and LLVM pointers, references, every
`AbstractArray` except a reviewed static array, and isbits wrappers recursively
containing those values cannot bypass declared reads. This structural check
does not claim to recognize every possible third-party provider handle. Scalar
values, immutable tuples and named tuples, reviewed static arrays, and
recursively safe isbits callable state remain valid captures. Preparation and
actual device compilation remain the final authority for callable ABI,
provider-specific values, and backend legality.

### Phase 1 implementation ledger

- Both lattice-spring stages, matrix-free FEM, and fixed-route z-buffer use
  typed authoring and keep independent numerical oracles. Historical
  correction: D2Q9 still used an explicit operation object at this gate; its
  typed-authoring conversion and deletion occurred in Phase 7.
- Runtime-keyed particle/contact and fragment-raster witnesses use explicit
  zero-field isbits callables pending the Phase 5/6 grouping and validation
  gates.
- Programmatic compilers pass `origin=SourceOrigin(...)` directly to
  `localwork`.
- The retired scalar-authoring entrypoints and envelope have no compatibility
  alias or production/test/documentation reference.
- LocalWorksets source changed from 11,849 / 11,196 / 11,098
  physical/nonblank/code-like lines to 12,510 / 11,832 / 11,734 after the
  focused gate corrections. The typed authoring implementation occupies 804
  physical lines. This phase establishes a language and is not yet a net
  source-deletion result; Phase 2 is therefore required to delete duplicated
  execution glue rather than merely adding another abstraction.
- Public semantic/authoring value types fell from 28 to 27.
- Textual kernels, plan phase types, prepared phase types, and prepared phase
  executor methods remain 14 / 14 / 14 / 14.
- Semantic IR, lowering-envelope, prepared-pipeline, and executor-family counts
  remain one each.

Focused Phase 1 evidence:

- the LocalWorksets API file passed 273/273 assertions, including 88/88 typed
  authoring assertions;
- the independent CPU cross-domain witness runner passed D2Q9,
  lattice-spring deterministic and fast modes, matrix-free FEM, z-buffer, and
  both explicit runtime-keyed named-port witnesses;
- a scalar-disabled Apple-Metal run passed all 17/17 cross-domain witness
  assertions and compiled 42 Metal specializations;
- the broader Metal runner was intentionally stopped after that bounded Phase
  1 witness block, so this evidence is not represented as a full-suite result;
- the initial Julia 1.10 invocation failed in dependency precompilation because
  the repository declares Julia 1.12; the successful hardware run used the
  declared Julia 1.12 environment; and
- `git diff --check` is clean and active source, test, and authoritative-spec
  references to the retired authoring API are zero.

The first GPU review rejected unrestricted nested macros, isbits memory
captures, insufficient tensor-index validation, and missing evaluation-order
proofs. Direct corrections close those paths: only normalized
`Base.@inbounds` survives nested syntax; captures are recursively checked;
declared tensors cannot escape through `getindex`, helper calls, aliases, or
self-reference; and traces prove both host declaration order and eager
contribution order. The final independent GPU/capture and
maintainability/specification re-reviews both report no remaining P0/P1
finding. Phase 1 is closed; its net-positive line count is an explicit deletion
obligation for Phase 2, not a claim that authoring alone simplified the
implementation.

## Phase 2 -- bounded execution-glue consolidation

Centralize per-port execution facts, binding/access validation, workspace
derivation, preparation accessors, and inspection without replacing
`_LoweredWork`. Retain genuinely different direct, buffered, keyed, and
conjunctive strategies. Ordered internal visibility uses linear
latest-prior-producer resolution and stage-qualified workspace leaves, not a
general graph.

### Phase 2 implementation ledger

The direct-edit implementation and its independent gate are complete.

- `_BindingAuthority` is now the sole stored authority for binding name,
  access, element type, shape, representation, and component layout.
  Mechanisms construct that authority once; preparation and inspection project
  names and access from it. The duplicate `PreparedWork.binding_names` and
  `PreparedWork.binding_access` fields were deleted.
- Generic direct, buffered, and runtime-keyed mechanisms share one operation
  result-schema validator selected by typed topology-route dispatch. The
  direct pointwise effect proof remains a separate additional check because it
  is a genuinely different semantic obligation.
- Ordered sequences perform visibility, unique-writer, access merging, and
  binding compatibility in one transient host-only fold. Reads resolve only
  against the latest preceding producer. The fold persists no graph or new IR;
  execution remains the flattened phase tuple in declared order.
- `_WorkspaceAuthority` remains the sole stored workspace schema. Allocation,
  caller-buffer reconstruction, validation, array enumeration, byte evidence,
  and inspection consume it directly. Redundant `work` pass-through arguments
  and central pass-through wrappers were deleted.
- Sequence workspace evidence selects the already-qualified canonical leaves
  by structured `(:stages, index, ...)` paths. The former helper that parsed
  generated `stageN_` names and rebuilt `_WorkspaceLeaf` values was deleted.
- Output bindings and prepared bounded-read routes use small shared accessors.
  Unused storage plumbing was removed from preparation. Distinct direct,
  buffered, keyed, and conjunctive preparation and execution strategies remain
  intact.
- Port evidence has one top-level authority. The duplicate
  `capability.ports` copies were deleted from direct, buffered, and keyed
  evidence; those capability records retain only backend/compiler facts and
  aggregate mechanism limits. `inspect(plan).ports` remains the public
  per-port evidence view.

Phase 2 source census, measured over every Julia file below
`lib/LocalWorksets/src`:

| Measure | Phase 1 gate | Phase 2 candidate | Change |
|---|---:|---:|---:|
| physical lines | 12,510 | 12,352 | -158 |
| nonblank lines | 11,832 | 11,677 | -155 |
| code-like lines | 11,734 | 11,579 | -155 |
| textual kernels | 14 | 14 | 0 |
| plan phase types | 14 | 14 | 0 |
| prepared phase types | 14 | 14 | 0 |
| prepared phase executor methods | 14 | 14 | 0 |
| persistent semantic/planning/prepared IRs | 1 / 1 / 1 | 1 / 1 / 1 | 0 / 0 / 0 |

Focused evidence after the final deletions:

- the package loads and precompiles successfully;
- the focused API file passes 273/273 assertions;
- the integrated mechanism, generic, and consolidation sequence passes all 368
  assertions, including ordered provider visibility, shared binding authority,
  canonical nested workspace evidence, direct/buffered/resolved/keyed
  preparation, and automatic workspace behavior;
- focused direct, buffered, and runtime-keyed evidence tests pass after adding
  explicit assertions that `capability` has no `:ports` field while top-level
  port order and facts remain exact;
- active source and test searches find no stale prepared binding fields,
  retired workspace wrappers,
  reconstructed stage-workspace helper, `capability.ports`, separate sequence
  validator, or retired read/output access authority; and
- `git diff --check` is clean.

No broad benchmark or full-suite rerun is claimed for this bounded
consolidation gate. The edit introduces no kernel argument, backend branch,
execution selector, persistent port-plan type, or second executor family.
The first gate pass rejected duplicated `capability.ports` views in direct,
buffered, and keyed evidence. Those views were removed; keyed aggregate
capability facts and per-port facts are now separate, and direct, buffered, and
keyed regressions prove that capability evidence has no `ports` field. The
final independent GPU/runtime and maintainability re-reviews both pass with no
remaining P0/P1 finding.

## Phase 3 -- publication and mathematical laws

Add proved multi-port pointwise read/modify/write, general deterministic
seeding, lexicographic tuple ranks with payload and canonical tie identity,
and record-valued routed publication. A heterogeneous product fold is admitted
only if two consumers prove fewer declarations, launches, or production lines.
The general seeded path replaces the specialized fixed-count implementation.

### Phase 3 implementation ledger

The direct edit keeps the same `LocalWork -> _LoweredWork ->
_PreparedPipeline` waist and extends four existing laws:

- Pointwise read/modify/write now admits multiple distinct scalar targets.
  Ordered role-to-target mappings are derived from `LocalWork.reads`; no
  duplicate lowering field or pointwise mechanism type remains. Every target
  proves identity routing, one partial independent lane, matching item and
  destination counts, qualified load/store, no ordinary read alias, and one
  unconditional replacement. All old values are gathered before the single
  operation call and before any port publication.
- `combined(..., initial=:existing)` is the sole seed law. The fixed-count
  plan tag, prepared phase, executor, generated kernels, topology/evidence
  branches, lowering profile, include, source file, and strategy-specific
  tests were deleted. Fixed routes now use the existing apply plus canonical
  publisher; runtime keys retain their existing seed snapshot. The qualified
  deterministic catalog is integer addition/minimum/maximum/bitwise folds,
  `Float32` addition, and `UInt64` addition.
- Resolved publication admits scalar `Int32`/`UInt32` ranks and flat tuples of
  two through four `Int32`/`UInt32` fields, bounded to 16 bytes and alignment
  four. One generated lexicographic comparison authority supplies bounds,
  equality, minimum, and maximum selection to fixed buffered, singleton, and
  runtime-keyed execution. Canonical `UInt32` identity remains a separate tie
  field; payload never participates in selection.
- Record publication remains a storage capability, not another output law.
  Mixed buffered independent ports now use the same qualified component-store
  and `StructArray` boundary as direct independent publication. Resolved and
  runtime-keyed record payloads retain their existing narrow-record workspace
  and coherent final component publication.

The heterogeneous product fold is rejected: no two unrelated consumers
delete a production declaration, executor, or kernel by introducing it.

Current production census is 12,178 physical, 11,508 nonblank, and 11,414
code-like LocalWorksets source lines. Relative to the Phase 2 gate census this
is a deletion of 174 physical, 169 nonblank, and 165 code-like lines. Plan
phase tags, prepared phase types, executor methods, and textual kernel sources
are each 13, down from 14. Case-insensitive repository search finds no retired
fixed-count-seed identifier in source, tests, backend conformance, Metal
runners, or specifications.

Focused CPU evidence passes for the complete seed suite and for multi-target
pointwise snapshots, fixed and runtime-keyed tuple ranks (including min, max,
and canonical ties), general canonical seed fallback, mixed buffered
`StructArray` publication, and record payload/provenance coherence. The same
bounded Phase 3 conformance function is wired into the Metal runner. A real
Apple-M1-Pro Metal run with scalar indexing disabled passes the multi-target
pointwise, fixed tuple-rank, keyed tuple-rank, record-publication, and general
seeded conformance blocks. The general seeded witness uses the ordinary two
launches and 135 workspace bytes. Independent compiler/Julia, GPU/performance,
and simplification/scientific-boundary reviewers report no P0/P1 finding.
They independently reconfirm exact tuple inference, complete pointwise
snapshots, allocation-free device execution, the 13/13/13/13 execution-family
census, zero retired specialization, and the 165-code-line net deletion.
Phase 3 therefore passes its gate.

## Phase 4 -- bounded spatial reads

Phase 4 admits exactly two executable route authorities under
`bounded_read(binding, route; maximum=K)`:

- `fixed_offset_route(item_shape, source_shape, offsets; origin=ones)` for
  `D=1:4`, `K=1:32`, exact `Int32` geometry, Julia column-major item identity,
  and strict-in-bounds addressing; and
- an ordinary host `Matrix{Int32}` of shape `K × item_count`, with a positive
  prefix followed by zero padding in every column.

Planning validates route structure exhaustively. Preparation validates the
exact fixed source shape or every positive incidence endpoint against the
exact bound source length before topology transfer, workspace allocation,
provider construction, or any kernel. The operation receives only
`GatheredValues{K,T}`. One generated `_materialize_operation_reads` boundary,
invoked after selection, serves direct, buffered, keyed, and singleton-resolved
execution. Raw topology reads are removed.

`active_indices(route; prefix=nothing)` references a topology-owned host
`Vector{Int32}`. Planning proves it strictly increasing and in range; it is
fingerprinted and copied once. The optional existing `Int32` value-slot prefix
selects its first entries. Central slot-to-item, item-membership, and extent
helpers preserve logical item identity and canonical order in the same phase
and kernel families. No mutable run-time index list, validation phase, dense
membership workspace, or second executor exists.

Inspection derives exact lower and upper halo depths from fixed offsets,
reports `owner_intersection_required` for incidence, and marks ordinary reads
opaque. LocalWorksets does not own partitions, exchange, MPI, boundary models,
or distributed conflict settlement. Footprints remain stage-local.

The gate requires the 13/13/13/13 plan-phase/prepared-phase/executor/kernel
family census to remain unchanged. Focused CPU evidence covers a 3D asymmetric
fixed route, sparse empty/nonempty prefixes, deterministic buffered sparse
publication, incidence zero padding, plan-time structural faults, and
prepare-time endpoint faults; the expanded focused block passes 32/32 and also
covers singleton-resolved and runtime-keyed sparse execution. Scalar-disabled
Apple-Metal execution passes fixed 3D gathers, empty and nonempty sparse
prefixes, buffered incidence, singleton resolution, and runtime-keyed
publication. The latter gate caught and corrected an early slot/item mix-up:
keyed initialization again clears full record capacity, while only keyed
evaluation maps a sparse slot to its logical item.

Current production census is 12,787 physical, 12,088 nonblank, and 11,994
code-like LocalWorksets source lines. Relative to the Phase 3 gate this adds
609 physical and 580 code-like lines while adding no kernel, plan phase,
prepared phase, executor family, lowering envelope, scheduler, or workspace.
There are zero raw `topology_read`/`_TopologyRead` paths. Independent committee
review remains the final Phase 4 gate.

The first gate review rejected the phase. Remediation now bounds both item and
source linear domains to the exact `Int32` route ABI, excludes pointwise reads
from ordinary same-stage alias rejection, iterates sparse singleton resolution
by selected slot rather than the full item domain, and obtains the previous
conjunctive identity directly from the sparse predecessor slot. The fixed
overflow and pointwise regressions are permanent focused tests.

The D2Q9 witness now uses a strict three-dimensional fixed-offset pull route
over LBM-owned periodic padding; a separate five-point structured witness uses
the same law with an independent oracle. Lattice-spring damage/mechanics and
matrix-free FEM use bounded incidence gathers, and LBM, LSM, and FEM use
topology-owned sparse indices. Their bounded CPU witnesses pass against their
independent numerical references with no retained parallel production form.
The converted D2Q9, lattice-spring, and FEM witnesses also pass their
independent references on real Apple Metal with scalar indexing disabled.

`run_localworksets_phase4_spatial_conformance` is the shared backend-parametric
gate. It is invoked from the CPU test suite and the scalar-disabled Metal
runner, covering fixed 3D and halo facts, empty/nonempty sparse prefixes,
buffered incidence, singleton resolution, and runtime-keyed publication. The
bounded CPU invocation passes 11/11 and the actual Metal invocation reports
all five capability flags true. Independent compiler/Julia, GPU/performance,
and simplification/scientific-boundary re-reviewers report no P0/P1 finding.
They reconfirm the Int32 geometry bounds, sparse asymptotics, cross-domain
reuse, reproducible runner wiring, honest topology evidence, and unchanged
13/13/13/13 execution census. Phase 4 therefore passes its gate.

## Phase 5 -- stable indexing and AcceleratedKernels

Admit AcceleratedKernels privately in two steps:

1. exact `Int32`/`UInt32` `ScanPrefixes` for stable compaction;
2. merge sort of unique total `UInt64` keys for stable grouping.

All temporary arrays remain planner-owned. The private adapter forces the
KernelAbstractions implementation, performs no execution allocation or hidden
synchronization, and is represented in workspace and execution evidence.
Floating scientific folds, `DecoupledLookback`, allocating overloads, radix
sort, custom comparators, and silent fallbacks are outside the admitted set.

### Phase 5 gate disposition

AcceleratedKernels 0.4.3 is **not admitted**. Its `ScanPrefixes` and merge-sort
KernelAbstractions kernels are declared with `cpu=false`; forcing that family
therefore fails on CPU, while selecting its threaded CPU implementation would
introduce a second algorithm and may allocate host scratch. A GPU-only feature,
fallback, provider selector, or vendored duplicate would violate the common
execution-path contract.

The alternatives also fail the simplification gate. A scan-only wrapper would
delete no complete mechanism. Replacing the existing exact `O(R + D)` keyed
counting/grouping phase would add physical launches and full-capacity scratch,
complicate canonical invalid/duplicate/missing diagnostics, and retain rather
than reduce semantic authority. Core lifecycle scan/sort additionally remains
predicated on device-resident transaction gates and cannot call a generic
collective without synchronization or unconditional persistent mutation.

Consequently Phase 5 makes no speculative production addition: the one
existing CPU/GPU keyed path remains authoritative, and no public type,
fallback, selector, wrapper, or parallel implementation is added. The unused
CorePotts dependency, import, compatibility entry, and capability fingerprint
are deleted so the repository no longer advertises a provider it does not use.

The dependency may be reconsidered only after a version proves one qualified
CPU/GPU KernelAbstractions family, caller-owned exact scratch, no hidden
synchronization or allocation, exact diagnostic parity, inspectable internal
launches, and net deletion of a complete mechanism. Independent compiler,
GPU, and maintainability reviewers unanimously approved this negative
qualification as the Phase 5 gate. Phase 6 therefore proceeds with the
LocalWork execution contract frozen and the provider decision deliberately
open to future evidence.

## Phase 6 -- validated publication and conflict footprints

Add bounded candidate storage, a shared pre-publication validation gate, and
conditional named-port publication. The guarantee is no external write before
all pre-publication validation succeeds; it is not rollback after a device
failure during publication. Add bounded domain-neutral resource footprints,
capacity demands, deterministic rejection witnesses, and private
generalization of conjunctive arbitration when demanded by two domains.

### Phase 6 implementation ledger

Phase 6 retains the four existing leaf mechanisms and the one recursive phase
runner. It adds no semantic IR, lowering envelope, scheduler, executor family,
phase type, kernel family, provider selector, or fallback. The resulting
execution census is exactly 13 plan phases, 13 prepared phases, 13 executors,
and 13 textual KernelAbstractions kernels.

Candidate-capacity arithmetic now has one checked authority. Every port exposes
derived `publication_footprint`, `capacity_demand`, and `rejection` evidence;
top-level inspection views project those same facts rather than declaring a
second authority. Static routing reports canonical record provenance for
domain, uniqueness, coverage, and semantic-identity failures.

The package-owned two-owner operation object and exported
`conjunctive_selection` constructor are deleted. The retained output law is a
bounded `K = 1:32` runtime resource footprint evaluated by an ordinary concrete
callable returning `candidate(rank, value, when)`. A participating candidate
succeeds exactly when its canonical rank and identity win every independently
resolved positive resource. This is not greedy scheduling or capacity
allocation. Disabled candidates preserve their item, an empty footprint
succeeds, and a participating loser receives the declared losing value.
Domains retain eligibility, priority construction, resource meaning, and the
scientific consequences of selection.

The four existing conjunctive phases materialize bounded private candidates,
validate resource/rank/identity facts, resolve claims, and publish through a
private gate. Phases one through three cannot write the output. Every logical
same-output read must be `pointwise_read(output)`; raw and bounded aliases
reject, callable state must be recursively storage-free, and provider-qualified
typed IR must prove a load-only operation. Runtime-keyed work uses the same
callable-effect qualification. Candidate reset and the unreachable partial-
materialization status were deleted, giving the honest work bound
`O(D + A*K)` for `D` resources and `A` selected candidates.

Runtime-keyed and resource-footprint validation now share one private
`_ValidatedPublicationStatus`: a five-word `UInt32` column per workspace lease,
with one device ring and one prepared host mirror per validating stage. The
keyed-only completion type, ten scalar status leaves, keyed transfer traversal,
and keyed single-lease restriction are deleted. The existing lease index is
threaded through all phase executors. Settlement performs one cumulative
provider wait, one deduplicated completion-transfer boundary, then chooses the
earliest submission serial and stage. `wait`, `waitall`, retaining settlement,
releasing retry, and repeated errors preserve the exact sourced diagnostic.
Warm single, grouped, and reentrant settlement allocate zero bytes.

Independent scientific witnesses use the same production law and scalar
oracles for two-particle contacts (`K=2`) and triangular FEM conflict-free
element batching (`K=3`). CorePotts K05 compiles accepted-candidate meaning into
the same law with a scalar pointwise disposition snapshot; Core retains
proposal eligibility, priority, semantic identity, scheduling, and commit
meaning. The old Core-specific claim operation/type and direct K05 path are not
retained.

Focused evidence passed:

- static/direct/buffered/keyed evidence and diagnostic suites;
- keyed and conjunctive valid/invalid multi-lease queues, including retaining
  fences, releasing retries, slot reuse, and repeated exact errors;
- all 144 focused runtime assertions and all 46 expansion assertions;
- all 88 focused resource-law mechanism assertions and Core K05 construction
  and parity assertions;
- scalar-disabled Apple Metal `K=2` and `K=3` valid/invalid witnesses, a
  valid--invalid--valid three-lease ring with all leases drained, and stable
  compiler-cache evidence; and
- zero warmed allocations for single, distinct-group, and reentrant-group
  settlement.

The exact Metal capability digest was requalified after Phase 5 removed the
unused AcceleratedKernels dependency; inserting only that removed dependency
reproduces the retired digest. The full Metal runner now passes capability
preflight and reaches a separate frozen-reference classifier failure involving
`LifecycleEvaluatorBank`; no Phase 6 capability claim relies on the blocked
remainder.

Final recursive LocalWorksets census is 13,761 physical, 13,036 nonblank, and
12,927 code-like source lines, versus 12,787 / 12,088 / 11,994 at the Phase 4/5
gate. The phase therefore adds 974 physical and 933 code-like lines. This is not
claimed as a line-count reduction. The accepted simplification is deletion of
the public CPM-shaped operation object, duplicated completion machinery,
single-lease keyed restriction, and parallel semantic/status authorities while
adding genuine `K=2`/`K=3`/Core reuse without another execution path. Net source
deletion remains an explicit Phase 8 obligation.

The final compiler, GPU, and scientific/maintainability reviews found no code
blocker after remediation. Phase 6 therefore passes its gate.

## Phase 7 -- complete language and cross-domain closure

Expose the admitted Phase 3--6 laws through the same `@localwork` translator.
Complete D2Q9, lattice-spring/fracture, matrix-free FEM, runtime-keyed
deposition/rendering, and CorePotts proposal witnesses. Each witness has one
production form and one independent test oracle.

### Phase 7 implementation ledger

The front end remains syntax translation into one ordinary concrete isbits
callable and the existing `LocalWork`; no authoring value, symbolic tree,
LocalLaw object, scheduler, plan phase, kernel, or authored execution path was
added. Conjunctive declarations are admitted through the ordinary port grammar
with exactly one candidate lane: their `K` parameter is resource-footprint
width, never emission-lane arity.

The only tensor-language extension is closed translation of qualified
`Base.sum(tensor)` and `Base.sum(f, tensor)` when `tensor` is the one
translator-owned static tensor. It expands to a tuple of the canonical static
elements. Unqualified `sum`, arbitrary helpers, aliases, wrapping, invalid
arity, dynamic indexing, and every other whole-tensor escape still reject.
This is not a reduction IR or an `@reduce` sublanguage.

The following now have one authored production form and an independent oracle:

| Domain witness | Authored form | Independent evidence |
|---|---|---|
| D2Q9 collide/stream and structured average | two `@localwork` blocks | loop population, density, norm, and stencil references |
| lattice spring/fracture | ordered authored stages | constitutive/mechanical/fracture reference |
| matrix-free FEM application | authored bounded gather/fold | element and assembly reference |
| fixed z-buffer | authored resolved publication | scalar visibility reference |
| runtime-keyed particle/contact and fragment raster | two authored named-port blocks | exact keyed vector references and invalid no-write cases |
| bounded K-resource selection | one authored fixture at `K=2` and `K=3` | separate scalar resource oracle |
| CorePotts K05 claims | internal authored compiler block | independent conjunctive dispositions and continuation evidence |

Seven primary operation-object families and their call methods were deleted:
D2Q9 collide, structured average, particle/contact named ports, fragment-raster
named ports, `_ResourceWitnessOperation`, `_ConjunctiveCandidateOperation`, and
the Core K05 claim candidate. Two additional compact test operation structs,
`_PointwisePairSnapshot` and `_TupleWinner`, were deleted while converting
authored pointwise and tuple-rank coverage, for nine removed operation structs
in total.
Seeded publication, multi-target pointwise update, tuple-rank resolution, and
runtime-keyed independent assignment also use authored coverage through the
same production lowerings.

`_FusedCheckerboardProposalOperation{Schedule}` deliberately remains the one
explicit Core compiler callable. Its schedule selects Core-owned canonical
Hamiltonian evaluation, semantic RNG, extinction rules, Metropolis acceptance,
and disposition construction. Wrapping that scalar scientific compiler in
`@localwork` would delete no machinery and would weaken the rule that ordinary
concrete callables remain first-class. It still targets the same LocalWork
waist; ordinary Potts authors do not author either internal block.

Fixed direct/buffered inspection now distinguishes deterministic publication
order from domain-owned local calculation replay. Ordinary calls may contain
domain effects, as the Phase 1 grammar already states; inspection does not
claim replay for them. Strict storage-free/load-only qualification remains on
pointwise, runtime-keyed, and K-resource mechanisms because their validation
or alias guarantees require it. The only verifier extension admits exact
`const`, recursively storage-free values in source and optimized typed
IR; mutable globals, arrays, references, pointers, mutation, foreign calls,
and opaque invocation remain rejected.

Focused CPU evidence passes the seven-model scientific witness runner, typed
authoring/inference/evaluation-order suites, seeded/pointwise/tuple-rank/keyed
mechanism suites, K-resource oracles, and Core initialization through the fused
proposal and authored K05 claim. Scalar-disabled Metal evidence passes authored
heterogeneous record/scalar ports, bounded gather, pointwise replacement,
runtime-keyed Boolean publication, reusable sequence, reusable K-resource
selection, D2Q9, keyed scientific witnesses, and Core checkerboard preparation.

The final LocalWorksets production census is 13,827 physical, 13,098 nonblank,
and 12,989 code-like lines, a Phase 7 delta of +66 / +62 / +62. The authoring
implementation grew by 47 physical lines; Core K05/proposal production fell by
14; the two newly converted external witness files fell by 34, for a narrow
authoring+Core+converted-witness delta of -1 physical line. Nine operation
structs were deleted, but the complete evidence-bearing surface grew through tests. No
all-surface or final ten-percent line reduction is claimed. Execution remains
exactly 13 plan phases, 13 prepared phases, 13 executors, and 13 kernels.

Independent compiler, GPU, and scientific/maintainability review found no code
or architectural blocker after the documentation correction above. Phase 7
therefore passes its gate.

## Phase 8 -- CorePotts adoption

The pre-implementation gate rejected the original unconditional 37-to-zero
kernel target.  The exact census is 37 production mechanical kernels and the
three named compiler/device probes.  Deleting kernel syntax by placing the
same mutation inside an effectful singleton callable is not adoption and is
forbidden.

The authoritative target is every operation that LocalWorksets can represent
with identical scientific meaning and no regression in launches, scratch,
ordering, workgroup behavior, or failure visibility.  The first direct tranche
established that boundary with executable evidence:

- K01 report clear is one direct independent LocalWork launch and the old
  `_checkerboard_clear_mcs_kernel!` is deleted;
- K04 acceptance failure selection is one single-destination resolved
  LocalWork launch and the old `_checkerboard_acceptance_status_kernel!` is
  deleted;
- all backend-resident program, lifecycle, and candidate status storage now
  uses one component-backed `StructArray{ProgramStatus}` representation while
  `ProgramStatus` remains Core's sole scientific status value;
- the only new alias rule admits a read-only work gate that aliases its
  preserve-on-empty output for the already existing one-thread
  `_PlanResolveSingle` phase, whose kernel reads the gate before publication;
  every other writable alias remains rejected; and
- the attempted K08 report conversion was removed after preparation proved
  that its dynamic canonical fold cannot use the strict pointwise path.  The
  buffered alternative adds launches and scratch, so the original one-launch
  Core kernel remains until a genuine fused fold law exists.

The focused CPU witness initializes and advances a two-attempt checkerboard
program through settlement with the new K01/K04 preparations.  The execution
and checkpoint schema is version 4 and inspection exposes both mechanical
lowerings.  Core production kernels are therefore 35, not zero.

This is not yet a Phase 8 deletion pass.  Relative to the reviewed Phase 7
boundary, LocalWorksets production source is 13,827 to 13,847 lines and
CorePotts production source is 24,242 to 24,453 lines: +231 lines combined,
while two production kernels disappeared.  The increase establishes shared
status storage, preparation, capacity, receipt, inspection, and exact alias
proof needed by later status conversions, but the tranche has not amortized
that machinery through source deletion.  Phase 8 therefore remains in
progress and MUST NOT pass its final gate unless subsequent direct conversions
delete more production machinery than the complete Phase 8 addition.

The independent compiler, GPU, and scientific reviewers require the following
Core mechanisms to remain explicit under current laws: greedy variable-width
lifecycle conflict selection; stable compaction and permutation; ordered
relationship preparation/publication; heterogeneous staged bank transactions;
and any conversion that would add scratch, launches, synchronization, or hide
mutation.  Further deletion requires demonstrated domain-neutral laws, not a
Core-named adapter or a relaxed verifier.

## Phase 8A -- transactions as an emergent composition

### Research decision

`Transaction` is not a LocalWorksets law, IR node, executor, scheduler, status,
receipt, or public authoring construct.  The transaction-like behavior needed
by CorePotts is the following ordinary composition:

```text
selected items
    -> optional canonicalization
    -> ordered state recurrence into explicit staged bindings
    -> ordinary validation/status work
    -> ordinary scalar gate
    -> ordinary guarded multi-port publication
```

Snapshot-only coherent publication is already composed from the current
selection, named-port, independent/combined/resolved/conjunctive, runtime
validation, `when`, publication, and `sequence` semantics.  A separate
`validated_together` law would duplicate those authorities.  It may exist as a
private recipe or documentation term only if inspection expands it into the
constituent laws.  It MUST NOT add a mechanism, phase family, publisher, or
failure model.

The one missing mathematical capability is a bounded ordered state fold:

\[
A_0 = \operatorname{initialize}(X), \qquad
A_{k+1} = T(A_k, x_{\pi(k)}, R),
\]

where `R` denotes ordinary immutable reads and a later selected item observes
the accumulator produced by all earlier items in the declared order `pi`.
Current output laws calculate item contributions from immutable pre-state and
then resolve or fold those contributions.  They cannot express this recurrence.
`sequence` supplies finite stage order, not a runtime-length recurrence, and
unrolling one stage per item would change both the program size and launch
count.

The capability is named `ordered_fold`, not `transaction`, `staged_fold`,
`commit`, `rollback`, or `atomic`.  The name states its complete mathematical
meaning without importing storage or database promises.  A transaction-like
domain operation emerges only when an `ordered_fold` into staged bindings is
followed by separately declared validation and guarded publication.

### Minimal semantic contract

An `ordered_fold` MUST have the following exact semantics:

1. The normal `LocalWork` operation evaluates each reached selected item once
   and emits zero or one typed fold value.  False conditional emissions do not
   invoke the transition.
2. The accumulator is a concrete named bundle of declared component bindings.
   Each component has an explicit target and either an explicit initialization
   source or an in-place initial value.
3. Initialization completes in canonical component order before the first
   transition.
4. The transition reads a typed read-only view of the current accumulator plus
   declared ordinary reads and returns one concrete, statically bounded fold
   step.
5. A fold step contains a fixed tuple or named tuple of component/key/value
   updates and optional typed evidence.  It is kernel-local and applied
   immediately; it is not a persistent patch AST, public command hierarchy, or
   runtime object graph.
6. The engine validates every destination in the step before applying any of
   that step's updates, then applies them in canonical schema order.  User
   transitions receive no writable arrays, pointers, atomics, or hidden
   mutation escape hatch.
7. The next transition observes the newly applied accumulator state.  The fold
   is sequential and generally non-associative; the planner MUST NOT reassociate
   or parallelize a group.
8. The first admitted implementation is `one_group()`. Independent groups may
   be added only when planning has explicit group-to-target partition metadata
   proving their accumulator slices disjoint. A group spanning owners or
   partitions is not admitted without that ownership proof; group concurrency
   is not inferred from a domain claim.
9. A typed halt result may stop traversal at a canonical prefix.  Halt means
   only that later items are not visited.  It does not mean abort, rollback,
   failure, or restoration of the initial value.
10. The resulting accumulator is an ordinary produced binding visible to later
    `sequence` stages.  Publication, rejection, scientific status, and
    checkpoint meaning remain separate work or domain state.
11. Provider failure can leave the fold target or a later publication partially
    updated.  Inspection and documentation MUST NOT claim hardware atomicity.

For small isbits accumulators, whole-component replacement is one schema-level
update under the same ABI.  It MUST NOT create a second scalar-state execution
family.  If a large bounded patch shape causes unacceptable register pressure,
the affected adoption is delayed; the verifier is not relaxed to admit opaque
mutation.

### Order law

Order changes the scientific result and is part of the declaration and its
fingerprint.  The initial admitted policies are:

- `canonical_order()`: the existing selected item order after prefix or mask;
- `canonical_by(key, identity)`: ascending lexicographic order of a closed,
  GPU-qualified exact key followed by a stable semantic identity.

`canonical_by` accepts concrete storage-free extraction callables or exact
emitted fields.  The initial key vocabulary is restricted to bounded tuples of
qualified integer fields; identity is an exact integer.  It does not accept an
arbitrary comparator, caller-certified `isless`, provider enumeration order, or
an unspecified tie.  Equal `(key, identity)` values either fail validation or
require a separately proved observational-equivalence rule.  Inspection exposes
the exact tie policy.

Selection, compaction, key extraction, canonicalization, initialization, and
recurrence remain separately identifiable semantic facts.  A singleton or
statically segmented lowering may fuse all of them into one kernel.  Such
fusion is an execution strategy for one declared fold, not a public sort,
permutation IR, scheduler, or second path.  The fused strategy may reuse an
explicit caller-owned prepared order buffer but MUST NOT allocate hidden
scratch or launch a separate sort merely to recover Core parity. Runtime-sized
`canonical_by` requires that explicit buffer so the operation is still
evaluated exactly once. `canonical_order()` may fold directly without it.

### Illustrative explicit surface

The names are provisional until the witness suite passes.  The intended shape
is an ordinary output law inside `LocalWork`, not a parallel program object:

```julia
admission = ordered_fold(
    accumulator = initialized_state(
        :next_relationships;
        from = :relationships,
        schema = relationship_state_schema,
    );
    value_type = RelationshipRequest,
    step = AdmitRelationship(schema),
    active = active_mask(:enabled),
    order = canonical_by(RequestOrder(), RequestIdentity()),
)

fold_work = @localwork request in 1:capacity begin
    @read requests
    @port next_relationships::RelationshipRequest = admission
    next_relationships ← emit(requests[request], enabled[request])
end

work = sequence(
    fold_work,
    validation_work,
    guarded_publication_work,
)
```

The authored spelling above is deliberately not frozen.  There is no
`@transaction`.  If later sugar is justified, it translates only into the same
`ordered_fold`, status, gate, and publication declarations, and inspection still
shows those declarations rather than a transaction mode.  Ordinary authors
should continue to need only reads, mathematical expressions, ports, and
explicit conflict laws; ordered recurrence is an advanced package-author tool.

### Lowering and execution

The implementation budget is one `_OrderedFoldLowering` beneath the existing
`_LoweredWork`, one plan phase, one prepared phase, one `_execute_phase!`
method, and one KernelAbstractions kernel using the existing recursive runner.
It adds no plan/prepare/run family.

The lowering derives binding authorities directly from the accumulator schema:
initial sources are read-only, targets are write or read-write, ordinary reads
retain their existing access, and target/source aliases reject except for an
explicit in-place initial component.  All component types, shapes, devices,
capacities, group ownership, selected-item bounds, update bounds, and order
buffer bounds are validated at prepare time.

The ordered-fold phase owns no commit gate, transaction status, bank selector,
rollback image, or publication receipt.  Structural order/update validation
reuses the existing lease-indexed validation status.  Domain failures use
domain-owned values such as `ProgramStatus`.  A following ordinary resolved
stage may combine group outcomes, and a following ordinary `when`-gated direct
multi-port work publishes staged components.

The transition returns one fixed schema-named update bundle. Each component
uses a statically bounded `(count, indices, values)` record. The engine checks
the count, every destination, and duplicate destinations for the entire step
before applying any update, then applies components in canonical schema order.
The update bound is a type parameter; runtime-sized tuples and writable patch
workspaces are not admitted.

For the Core accepted-relationship-specific subpipeline, excluding the
existing request-evaluation and ordinary accepted-state work, the performance
target is exactly:

1. one fused select--compact--canonicalize--initialize--fold launch; and
2. one existing guarded heterogeneous multi-port publication launch.

The target permits no atomics, grid barriers, host wait, hidden synchronization,
new publisher, hidden scratch, or backend-specific semantic branch. It must
reuse or replace the current request/order and staged-relationship storage; an
explicit prepared order buffer counts as inspected binding storage. A separate
sorting launch fails the adoption gate.

Inspection MUST report:

- the `:ordered_state_fold` law and its non-associative sequential semantics;
- group ownership, active policy, maximum visited items, and halt semantics;
- order policy, key and identity types/origins, tie rule, and validation;
- whether selection, compaction, ordering, initialization, and folding fused;
- accumulator source/target components, types, shapes, and access;
- step update type, maximum update count, and update application order;
- full or tighter proved read/write footprints and any halo requirement;
- exact workspace, order-buffer, validation-ring, and per-lease bytes;
- operation/transition types and source origins;
- phase and launch counts; and
- ordinary partial-target visibility on provider failure.

### Scientific ownership

LocalWorksets may own bounded selection, typed canonical traversal, accumulator
initialization, recurrence execution, update-address validation, engine-applied
updates, group-disjointness proof, evidence plumbing, workspace/lifetime, and
inspection.

Domain packages retain the meaning of state, items, keys, identities,
participation, transition equations, scientific invariants, failure evidence,
RNG, time, convergence, checkpoint continuation, and whether sequential order
is scientifically valid.  CorePotts specifically retains relationship schema,
request equivalence, Remove/Retune/Create precedence, priorities and endpoint
ordering, generation rules, capacity and idempotence meaning, status mapping,
MCS scheduling, and checkpoint semantics.  LocalWorksets never learns the
terms cell, edge, contact, species, adsorption, or reaction.

### Positive witness matrix

The declaration is implemented privately but remains fully inspectable while
its shape is being proven.  It is exported as an experimental explicit
constructor only after the first four witnesses below pass through the same
semantic value and execution path.  Macro notation waits until several full
authoring examples establish one clear spelling.

| Witness | Why prior accumulator visibility is necessary | State/update shape | Order and execution evidence |
|---|---|---|---|
| Core accepted relationships | Earlier remove/create/retune operations change degrees, idempotence, free slots, and incidence observed by later requests. | Heterogeneous edge, payload, degree, and bounded incidence components; update bound derived from payload width and maximum degree. | Core-owned request key and semantic identity; exactly one fused fold plus one existing guarded publication; delete both bespoke prepare and publish kernels with net production deletion. |
| 2D lattice random sequential adsorption | Every accepted particle changes the occupancy tested by later trials; one-shot per-site winners do not reproduce greedy A--B--C overlap cases. | Occupancy plus an all-or-none bounded polyomino footprint and acceptance evidence. | Domain-owned attempt ordinal/RNG priority and identity; exact scalar serial deposition oracle; one bounded domain. |
| 3D projected Gauss--Seidel contact sweep | A later contact sharing a body must read velocities and multipliers updated by earlier contacts; snapshot evaluation is a Jacobi method, not PGS. | Two body generalized-velocity replacements plus one contact-multiplier replacement per visit; disjoint contact islands become groups only after explicit partition proof. | Solver-owned contact order/identity; serial PGS oracle; qualified floating evidence and residual/complementarity checks. |
| Bounded stoichiometric event admission | An earlier event may produce a species consumed by a later event, so snapshot feasibility gives a different inventory. | Exact integer species inventory; at most `Z` signed species updates plus disposition per event; many independent voxel/compartment groups. | Domain-owned event order/identity; exact conservation and nonnegativity oracle; one fold plus one direct publication across many GPU groups. |

Additional useful witnesses include random-sequential TASEP/lattice-gas attempt
streams, bounded dynamic graph edits, and fixed-capacity agent birth/death/move
batches.  Dynamic graph editing is a valuable pre-Core stress case but does not
count as unrelated evidence because it is structurally close to relationships.
Agent allocation is likewise too close to Core lifecycle to justify the law by
itself.

Every positive witness requires an independently written scalar recurrence, a
paired snapshot/Jacobi counterexample proving that existing laws compute a
different model, CPU and real scalar-disabled Metal evidence, and exact or
declared floating comparison rules. Central law conformance tests masks,
prefixes, zero participants, invalid order/identity, multiple queued leases,
alias rejection, update bounds, partial-prefix visibility, and complete
inspection once rather than repeating the mechanism suite for every model.
CPU warm execution must allocate zero algorithm-owned storage. Metal requires
stable prepared storage and compiler-cache identities and reports provider
command-encoding allocation separately. Witness oracles MUST NOT call the
production transition helper.

### Negative controls

The following remain ordinary LocalWorksets laws or outside the bounded-fold
scope:

- same-color checkerboard Ising/Potts updates, D2Q9, Jacobi stencils,
  synchronous cellular automata, reaction--diffusion, and pointwise ODE updates,
  all of which read an immutable time-level snapshot;
- ordinary lattice-spring damage, local constitutive return maps, and bounded
  material-point histories that fit in one local isbits callable;
- matrix-free FEM assembly, penalty-contact force assembly, histograms, and
  commutative deposition, which use existing deterministic or relaxed folds;
- z-buffer/argmin and immutable-prestate selection, which use resolution;
- one-shot K-resource claims, which use conjunctive resolution;
- prefix sums and scans, which require a scan law rather than state recurrence;
- exact Gillespie/KMC batches, Eden growth, invasion percolation, fracture
  cascades with re-equilibration, and other algorithms that regenerate the item
  set or scheduler after each step; and
- bank copies, status resets, rollback restoration, and direct coherent state
  publication.

A witness is rejected as contrived if order was introduced only to exercise the
API, a standard snapshot/parallel formulation has the same scientific meaning,
future items must be recomputed after every transition, or an outer nonlinear,
time, or event scheduler is hidden inside the fold.

### Acceptance and rejection

Phase 8A passes only if:

- no transaction API, IR, mechanism, executor, publisher, status, receipt,
  rollback path, or strategy flag exists;
- exactly one new mathematical law, `ordered_fold`, is represented in the same
  `LocalWork -> _LoweredWork -> WorkPlan -> PreparedWork` architecture;
- transition callables are storage-free and receive read-only accumulator
  access while the engine alone applies validated bounded updates;
- `canonical_order` and closed typed `canonical_by` are deterministic and fully
  inspected on CPU and GPU;
- Core relationships, RSA, PGS, and stoichiometric admission use the same law
  without domain branches or parallel production implementations;
- the negative controls remain on their simpler existing laws;
- the Core tranche remains two launches, uses no more scratch, deletes both
  bespoke kernels and their generic orchestration, and produces net source and
  combined-kernel deletion; and
- all existing determinism, status, failure, lease, GPU, checkpoint, and
  benchmark evidence remains valid.

Revise or reject the feature if it needs a writable-array callback, persistent
patch language, arbitrary comparator, trusted private-bank trait, separate
sorter, second publisher/status path, public scheduler, backend semantic branch,
extra Core launch/scratch, or abstraction growth without production deletion.
If the bounded update representation causes material GPU regression, retain the
Core kernels while improving or rejecting the representation; do not conceal
mutation to force adoption.

## Phase 8B -- compacted canonical records and the Core-completeness basis

### Committee decision

The candidate expansion is not admitted as six peer laws.  Scan, stable
compaction, sorting, traversal, ragged topology, and top-K do not belong at the
same semantic level.  The smallest coherent public algebra adds only:

```text
compacted       bounded materialized filter/map/group/order
ordered_fold    bounded ordered state recurrence
```

and the non-executable typed descriptors:

```text
one_group()
group_by(group; count)
source_order()
canonical_by(key, identity)
```

Existing assignment, combination, resolution, conjunctive claims, pointwise
updates, runtime routing, bounded gathers, gates, and `sequence` retain their
current meanings and execution architecture.

`compacted` is the public semantic result that Core and external domains
actually consume: canonical records, a device-resident live count, and, when
grouped, a dynamic segment directory.  Scan, stable scatter, bounded sorting,
and segment-index construction are private ways to realize that result.  There
is no public traversal object, scan, sort, permutation, CSR builder, stream,
queue, or scheduler.

This basis is intended to make nearly all eligible CorePotts *mechanics*
expressible through LocalWorksets.  It does not make LocalWorksets the owner of
CPM science.  A retained Core kernel is acceptable when replacement deletes no
machinery or regresses launches, scratch, code size, or scientific clarity.

### The `compacted` law

For emissions `r_(i,l)` in canonical logical source order `(item, lane)`, let
`p` be participation, `g` an optional dense group key, `k` an order key, and
`q` a semantic identity.  For each group `d`:

\[
C_d = \operatorname{sort}_{(k,q,i,l)}
\left[ r_{i,l}\;\middle|\;p(r_{i,l}) \land g(r_{i,l})=d \right].
\]

With `source_order()`, the `(k,q)` portion is omitted and records retain
canonical `(item,lane)` order.  With `one_group()`, `d=1`.  A grouped result is
the concatenation `C_1, C_2, ..., C_G` in ascending dense-group order.

The logical result contains:

- `records[1:count]`, the authoritative compacted record sequence;
- one device-resident exact `Int32` count;
- for grouped output, one-based `segment_starts[1:G+1]`, where
  `segment_starts[d]:(segment_starts[d+1]-1)` is group `d`; and
- original `(item,lane)` provenance for every live record.

The physical record tail after `count` is inactive capacity and has no value
semantics.  It is not a second output and cannot be consumed by a sequenced
work without the corresponding live-count or group-bound proof.  A future
canonical-tail profile may fill it explicitly, but the initial law does not pay
for tail clearing merely to disguise bounded storage as a full-length vector.
On structural validation failure, no caller-visible record, count, segment, or
inverse projection is published.  Provider failure after publication begins
retains the existing nonrollback partial-visibility contract.

The map and filter are already supplied by the ordinary emitted value and its
condition.  Consequently there is no separate `filter_map`, `pack`, `collect`,
or `ordered_emit` operation.

### `compacted` API and authored UX

The intended explicit declaration is:

```julia
requests = compacted(
    value_type = Request,
    capacity = maximum_requests,
    groups = one_group(),
    order = canonical_by(RequestOrder(), RequestIdentity()),
)
```

It remains an ordinary port law in the mathematical front end:

```julia
request_work = @localwork candidate in 1:maximum_candidates begin
    @read proposals

    @port requests::Request = compacted(
        capacity = maximum_requests,
        groups = one_group(),
        order = canonical_by(RequestOrder(), RequestIdentity()),
    )

    request = make_request(@inbounds proposals[candidate])
    requests ← emit(request, request.enabled)
end
```

Grouped dynamic materialization uses the same law:

```julia
site_index_work = @localwork site in 1:site_capacity begin
    @read ownership

    @port owned_sites::SiteRecord = compacted(
        capacity = site_capacity,
        groups = group_by(CellOwner(); count = cell_capacity),
        order = canonical_by(SiteOrdinal(), SiteIdentity()),
    )

    owner = @inbounds ownership[site]
    owned_sites ← emit(SiteRecord(owner, site), owner > 0)
end
```

Ordinary authors do not manipulate physical count or directory arrays.
Sequenced consumers use typed binding references:

```julia
active_prefix(record_count(:requests))
bounded_group_read(:owned_sites; maximum = maximum_cell_sites)
```

`record_count` performs no host query.  `bounded_group_read` produces the same
kind of finite read-only gathered view as existing bounded reads and validates
the declared maximum group occupancy.  An optional inverse source-position
projection may be materialized only when a typed downstream consumer requests
it; this is a projection of the same compacted result, not an `inverse=true`
mode or another law.

The typed request is `source_position(:port)`.  For producer maximum `K`, one
consumer source item observes an allocation-free `SourcePositions{K}` value;
lane `l` reads the frozen flattening ordinal `(item - 1) * K + l` and returns
the one-based compacted position or `Int32(0)` when that lane did not
participate.  Gate A admits this typed read and its storage projection
semantics only.  Sequence demand propagation and execution binding remain a
Gate C responsibility and MUST NOT be inferred from the standalone allocator.

One logical compacted-storage authority owns records, count, directory, and
optional projections through one lifetime and alias contract.  It may be a
single concrete component-backed storage value, but MUST NOT become a hierarchy
of traversal/index objects.

### Ordering and grouping descriptors

`source_order()` means canonical logical LocalWork item/lane order after
selection.  It never means provider enumeration, thread scheduling, physical
buffer order, or an undocumented stable-sort tie.

`canonical_by(key, identity)` defines ascending package-owned lexicographic
order by a domain-owned key and exact semantic identity.  Both extractors are
concrete storage-free isbits callables or exact emitted fields.  Their results
are restricted to centrally qualified `Int32`, `UInt32`, and bounded flat
tuples.  No arbitrary comparator, external `isless`, stochastic shuffle, or
self-certified ordering is admitted.  Equal `(key,identity)` values reject
unless an explicit package-owned profile proves them observationally
interchangeable.  Canonical source ordinal remains recorded as provenance, not
as a substitute for a missing semantic identity.

`group_by(group, count)` accepts dense exact keys `1:G`, validates every
participating key, and orders groups numerically.  Zero skips only through an
ordinary false emission condition; it is not silently another group.  Overall
grouped order is `(group, order_key, semantic_identity)` or
`(group, source_item, source_lane)` under `source_order()`.

The descriptors have no plans, kernels, workspace, or execution lifecycle on
their own.  The same descriptor values and validation authority parameterize
`compacted`, `ordered_fold`, and any existing deterministic law that later
admits explicit canonical traversal.  There is never a separately materialized
public `Traversal`.

### Dynamic segment directories are not topology

A grouped compacted result is device-produced submission state.  Its segment
directory:

- has no topology epoch or topology fingerprint role;
- is not accepted by `topology(...)`;
- cannot prove immutable neighborhood or halo facts;
- may change on every submission; and
- is consumed only through declared produced bindings in a later sequence.

This is deliberately distinct from a future frozen bounded ragged route.  A
frozen route describes immutable plan topology through offsets and incidence
indices; a compacted segment directory describes a dynamic computed record
index.  Their similar physical prefix arrays do not merge their meanings,
lifetime, validation, or ownership.

### Public laws versus private execution substrate

The complete classification is:

| Capability | Classification |
|---|---|
| `compacted` | Public semantic output law after witness and deletion evidence. |
| `ordered_fold` | Public semantic recurrence law under Phase 8A gates. |
| `source_order`, `canonical_by`, `one_group`, `group_by` | Typed non-executable descriptors. |
| exact inclusive/exclusive scan | Private qualified compaction/grouping algorithm. |
| segmented scan | Private lifted head/value scan only if a lowering needs it. |
| stable scatter | Private compaction algorithm. |
| bounded total-key sort | Private implementation of `canonical_by`. |
| dynamic segment-directory builder | Private grouped-`compacted` publication profile. |
| canonical descriptor traversal | Inline typed callable utility; no phase or public object. |
| fused small-record terminal reduction | Private strategy for existing `combined` and `resolved`. |
| heterogeneous state-bank assignment | Direct use of existing named multi-port independent laws; no new LocalWorksets strategy or phase. |
| frozen bounded ragged read | Deferred topology representation beneath `bounded_read`. |
| top-K | Deferred `resolved(...; keep=Val(K))` cardinality extension. |

Scan is genuine mathematics, but the current Core consumers do not observe
prefixes; they observe compacted records and directories.  A public `scanned`
law is considered only after two unrelated domains require every prefix as a
scientific output.  Likewise, top-K is genuine selection mathematics but does
not solve greedy multi-resource lifecycle selection and currently deletes no
Core kernel.

### Private phase responsibilities

All private mechanisms lower through the same `_LoweredWork`, concrete plan
phase tuple, `_PreparedPipeline`, recursive phase runner, provider lane, lease
ring, validation status, and settlement path.  No public algorithm selector or
second executor family is permitted.

The compacted lowering may use these responsibilities:

1. **Collect and validate.** Evaluate the ordinary operation once per selected
   item and materialize private record, participation, group, key, identity, and
   source-provenance components.  Record the earliest structural failure in the
   existing lease-indexed validation status.
2. **Exact scan and stable scatter.** Produce unique stable positions and the
   exact count without atomics, host count reads, or hidden synchronization.
   Every physical scan level is a planned and inspected phase; there is no
   executor-hidden launch loop.
3. **Bounded total-key ordering.** Order private records by the closed tuple
   `(group,key,identity,source_ordinal)` using one centrally qualified strategy.
   A bitonic, merge, counting, or radix replacement is private and replaces the
   prior strategy directly after parity; selectable production algorithms are
   forbidden.
4. **Segment construction.** Derive the one-based directory, maximum observed
   group occupancy, and any requested inverse projection from canonical
   records.  Empty groups repeat the previous start.
5. **Guarded structured publication.** Publish the logical compacted storage
   only after every runtime structural check succeeds.  All components share
   one validation gate and lease.

Small singleton consumers may fuse collection, compaction, ordering, and
consumption.  Accepted relationships require this fusion so their ordered fold
does not first materialize an unnecessary public compacted value.  Inspection
reports `materialization=:inline` or `:records_count_directory` while preserving
identical participation and order facts.

The private exact scan initially admits only centrally qualified exact integer
and bitwise monoids.  If implemented hierarchically, its finite level tuple,
workspace, association, and physical launches are planned explicitly.  A
Hillis--Steele and hierarchical path MUST NOT coexist as selectable production
fallbacks.

The fused terminal reducer is not an `ordered_fold` shortcut.  It realizes an
already declared one-destination deterministic `combined` or top-1 `resolved`
law in one launch and no scratch when a closed accumulator/record byte profile
qualifies.  It targets report, due, and earliest-status folds without exposing
scan or recurrence.

State-bank copying uses no private LocalWorksets execution strategy.  Core
first constructs one cold canonical copy schema. Each entry records its
semantic path, original axes, element and concrete representation, strides,
backend/device identity, and zero-copy linear view. Relationship schema
validation additionally fixes canonical slots, bank count, payload arity, and
all packed offset/count/degree-bound arrays. Global within-bank and cross-bank
nonalias proofs precede planning. Zero-length leaves remain in that validation
census but produce neither bindings nor work. Core then projects every mutable
scientific physical leaf exactly once, excludes packed
offset/count/degree-bound metadata, groups leaves by equal linear extent, and
chunks each group into at most four named ports.  Every chunk is an ordinary
full-coverage identity-routed direct `LocalWork`; chunks compose with ordinary
`sequence`. Sequences partition only at the provider's fixed 32-stage admission
bound, into the minimum number of ordinary prepared batches on the same scope.
Both bank orientations are prepared once. Settlement retains the latest
cumulative event from every batch, allowing one grouped provider wait to
release every preparation's lease without adding an execution path.

The four-port limit is a Core qualification bound backed by real CPU and Metal
compilation, not a LocalWorksets semantic limit.  Matrices enter as reviewed
zero-copy linear reshape views.  Each private Core callable is concrete,
isbits, storage-free, load-only, and returns named unconditional `emit` values.
Lifecycle-enabled copies share one `_LifecycleStatusGate`; lifecycle-free
copies are ungated declarations and do not materialize a Boolean or add a
launch.  Equal-extent grouping gives identity routes with zero topology bytes,
zero algorithmic workspace, no idle lanes, and no out-of-bounds branch.

`PackedRelationshipBank` is the hard runtime representation boundary.  A
`ProgramRelationshipState` may exist only during cold host construction,
transaction import, or serialization.  Materialization packs once; runtime,
alternate, staged, scratch, snapshot, checkpoint-continuation, and adapted
device banks remain packed.  Warm execution must not pack, unpack, collect a
`BitVector`, or round-trip through `Array`. Packed copying duplicates mutable
science (`active`, endpoints, generations, payloads, degree, incidents) and the
offset/count/degree-bound schema arrays. Schema values remain semantically
immutable after construction, but independent banks, snapshots, and
checkpoints do not alias even their metadata storage.

Production execution has one hardware boundary: KernelAbstractions and the
qualified LocalWorksets provider. Root source, extensions, and every
`lib/*/src` package MUST NOT use raw Metal, CUDA, AMDGPU, or oneAPI kernel
macros, compiler entry points, synchronization, command buffers or encoders,
grid/thread intrinsics, vendor kernel objects, or direct vendor launch APIs.
Package-owned spatial kernels use KernelAbstractions exclusively. A provider
extension may adapt storage, select the KernelAbstractions backend, and declare
capability/evidence. An independent solver library may receive its documented
device backend through that library's public API, but this does not authorize a
package-owned raw vendor kernel path. Scalar-disabled witnesses may allocate
provider arrays and inspect compiler evidence, but invoke spatial production
work exclusively through the same KernelAbstractions path.

Accepted-relationship scratch stores a packed state and adapts it directly;
checkpoint, resumed continuation, snapshots, and host relationship transactions
retain the same packed bank identity and canonical slot mapping. None may
reconstruct a warm vector-of-relationship-states representation.

### AcceleratedKernels disposition

Do not add AcceleratedKernels as a current production dependency.  The reviewed
version did not establish one forceable common CPU/GPU kernel family with
caller-owned scratch, asynchronous enqueue, and inspectable physical launches
for the required scan and sort rows.  Requalify a future version only for exact
integer scan or total-key ordering after the package-owned implementation gives
an evidence baseline.  Adoption requires:

- the same forceable algorithm on CPU and GPU;
- exact caller-owned and inspectable scratch;
- no hidden wait, allocation, host count read, or fallback;
- exact CPU and scalar-disabled Metal parity;
- asynchronous operation on the existing provider lane; and
- deletion of the superseded package-owned collective.

AcceleratedKernels is not considered for ordered fold, top-K, direct maps,
component publication, gates, or semantic traversal.

### CorePotts compiler shapes

Accepted relationships compose transient canonical ordering and recurrence:

```julia
relationship_admission = localwork(
    EmitAcceptedRelationshipRequest(), 1:request_capacity;
    outputs = (
        next_relationships = ordered_fold(
            accumulator = initialized_state(
                :next_relationships;
                from = :relationships,
                schema = relationship_state_schema,
            ),
            active = active_mask(:request_enabled),
            order = canonical_by(
                CoreRelationshipRequestOrder(),
                CoreRequestIdentity(),
            ),
            step = CoreRelationshipAdmission(schema),
        ),
    ),
)

relationship_program = sequence(
    relationship_admission,
    relationship_status_work,
    guarded_relationship_publication,
)
```

The compact/order result is inline because it has one consumer.  The target
remains one fused fold launch plus one existing gated component-publication
launch.

Lifecycle requests are materialized once for reuse:

```julia
@port requests::LifecycleRequest = compacted(
    capacity = request_capacity,
    groups = one_group(),
    order = canonical_by(
        LifecycleRequestOrder(plan),
        LifecycleRequestIdentity(plan),
    ),
)
requests ← emit(request, request.active)
```

Planning stages consume `active_prefix(record_count(:requests))`.  Greedy
multi-footprint selection consumes the canonical request records through
`ordered_fold`; ordinary per-request planning remains ordinary snapshot work.

Lifecycle owner-to-site indexing is grouped dynamic materialization:

```julia
@port owned_sites::SiteRecord = compacted(
    capacity = site_capacity,
    groups = group_by(CellOwner(); count = cell_capacity),
    order = canonical_by(SiteOrdinal(), SiteIdentity()),
)
owned_sites ← emit(SiteRecord(owner, site), owner > 0)
```

Cell-domain work consumes `bounded_group_read(:owned_sites; maximum=K)`.
Core owns valid-owner meaning and status mapping; the directory is not frozen
topology.

Free resources are another compacted supply:

```julia
@port free_cells::Int32 = compacted(
    capacity = cell_capacity,
    groups = one_group(),
    order = canonical_by(CoreFreeCellPreference(), CellIdentity()),
)
free_cells ← emit(Int32(cell), is_free)
```

After Core-owned capacity and generation checks, an ordinary pointwise map zips
selected request position `j` to free resource position `j`.  No reservation or
supply-allocation law is introduced.

Status paths continue using `resolved`; reports continue using seeded
`combined`; accepted state and tracker application continue using independent,
combined, resolved, pointwise, gates, and sequence.  Private terminal and
component strategies improve their lowering without changing their declarations.

### Core coverage map

The current 35 production kernels divide as follows:

| Core family | Common-waist expression |
|---|---|
| accepted evaluation and lifecycle request emission/planning maps | Existing direct LocalWork plus typed static descriptor traversal. |
| accepted relationship preparation | Inline canonical ordering plus `ordered_fold`. |
| accepted relationship publication | Existing gated direct named-port publication over packed storage. |
| checkerboard commit and accepted-state application | Existing direct pointwise/named ports after conflict proof. |
| checkerboard report and due/counter summaries | Existing seeded `combined` with fused terminal strategy. |
| sticky/global status reductions | Existing `resolved` with fused terminal strategy. |
| lifecycle mark/scan/compact/request sort | One materialized canonical `compacted` output. |
| lifecycle site-key/sort/index | Grouped `compacted` plus optional inverse projection. |
| greedy lifecycle conflict selection | Canonical records plus `ordered_fold` over Core-owned footprints. |
| lifecycle capacity allocation | Compacted selected requests and free resources plus ordinary validation and positional assignment. |
| structure/relationship ordered staging | `ordered_fold` with Core transition callables. |
| state staging | Existing conflict-free direct map over selected canonical records. |
| clears, gated copies, failure stamps, bank publication, rollback restoration | Existing direct/pointwise/gated named ports; equal-extent chunks use ordinary sequence. |
| staged validation and finalization | Existing local calculation, `resolved` status, `combined` counters, and ordered fold only where recurrence is real. |

A mature implementation plausibly removes 25--30 of these 35 Core kernel
definitions while adding approximately 6--8 reusable LocalWorksets kernels or
kernel definitions.  The resulting combined-kernel reduction of roughly
17--22 is a research estimate, not an acceptance quota.  It MUST NOT motivate
hiding Core mutation, forcing poor replacements, or deleting the three compiler
probes.  Source deletion is expected to be smaller because Core scientific
transition helpers remain.  Every direct tranche must still delete more
production orchestration and kernel machinery than it adds.

### Scientific ownership after broad lowering

Even if every eligible mechanical launch lowers through LocalWorksets,
CorePotts retains:

- lattice ownership, cell, relationship, tracker, and descriptor meaning;
- checkerboard/color independence, proposal before/after views, Hamiltonian
  order and units, semantic RNG, Metropolis acceptance, and dispositions;
- MCS scheduling, attempt counts, accepted-copy timing, synchronization cuts,
  receipts, and continuation;
- relationship request equivalence, remove/retune/create precedence, degree,
  capacity, idempotence, payload, and generation semantics;
- lifecycle due, trigger, create/retire/remove/transition/divide, partition,
  conflict, filtering, free-resource preference, and rule-order semantics;
- all Core keys, ranks, identities, footprints, transition equations, and gate
  conditions;
- `ProgramStatus` construction, field meaning, precedence, sticky/fatal cuts,
  and mapping from scientific failures; and
- bank authority, rollback meaning, checkpoint identity, capability claims,
  and exact scientific replay.

LocalWorksets validates and executes the bounded mechanics of these values.  It
never infers or redefines their scientific meaning.

### Witnesses and counterexamples

Before `compacted` freezes, require at least:

- 2D/3D DEM broad-phase contact filtering into canonical compacted contacts;
- adaptive triangle/tetrahedron FEM active-element extraction with a later
  device-prefix consumer;
- 2D/3D active-particle cell grouping with exact segment directories and
  optional source-position projection; and
- the Core lifecycle request and owner-site consumers with independent oracles.

Every descriptor combination requires exact scalar references for empty, full,
overflow, invalid group/key/identity, equal-key, masked, and repeated-submission
cases.  CPU and real scalar-disabled Metal must use the same lowering.  Inspect
records, counts, segments, provenance, strategy, every physical launch, exact
scratch, validation bytes, leases, and failure visibility.  Warm execution
allocations remain zero and no test oracle may call the production extractor or
ordering helper.

Before a public scan is considered, require two domains that observe every
prefix, such as optical-depth integration and chain reconstruction.  Before
`resolved(...; keep=K)`, require unrelated K-nearest support and multi-hit
rendering witnesses.  Before frozen ragged routes, require unstructured-mesh
and irregular-network measurements showing material padding, transfer, or
compilation savings.

Negative controls remain important:

- a mask with unchanged logical item identity uses existing active selection,
  not `compacted`;
- a final aggregate uses `combined`, not scan or ordered fold;
- top-1 choice uses `resolved`, not compacted sorting;
- immutable fixed neighborhoods use existing bounded routes;
- snapshot/Jacobi science uses ordinary LocalWork rather than ordered fold;
- dynamic frontier generation, unbounded queues, adaptive SSA, and distributed
  cross-owner groups remain outside this bounded basis; and
- top-K cannot approximate greedy multi-resource selection.

### Direct implementation order

1. **Shared descriptors and storage.** Add `source_order`, `canonical_by`,
   `one_group`, `group_by`, one logical compacted-storage authority, accessors,
   construction validation, and complete declaration/storage inspection.  No
   execution path is added by descriptors; plan fingerprints arrive with the
   admitted lowering in Gate B.

   Gate A establishes only this semantic/storage foundation.  Its standalone
   allocator accepts a `LocalWork` declaration and an explicit typed
   source-position request; there is intentionally no `WorkPlan` allocator
   overload before compacted planning exists.  Capacity, dense-group count,
   and flattened candidate ordinals reserve `typemax(Int32)` as a terminal and
   therefore admit at most `typemax(Int32)-1`.  Extractors and record types use
   the shared recursive storage-free qualification, including rejection of
   nested pointers, references, and arrays.  Scalar and zero-field values use
   scalar arrays; tuples and named records use recursively componentized
   `StructArray` storage down to primitive leaves.  One
   recursive adaptation protocol covers `CompactedStorage` and bounded group
   views.  Allocation validates every physical leaf's exact shape/type,
   reviewed backend root, device identity, zero-copy component identity, and
   pairwise nonaliasing.  Adapted storage is revalidated when it enters the
   future prepare/Gate-B boundary because `Adapt.adapt_structure` does not and
   cannot infer the producer declaration.  Inspection reports allocation laws
   and immutable physical facts without reading device scalars.  Extractor
   result qualification truthfully remains `required_at_plan`, and the
   execution algorithm remains `not_selected` until Gate B.

   Focused Gate A evidence is 126/126 compacted-foundation assertions plus
   the existing API/authoring/construction slices (31/31, 23/23, 72/72, 4/4,
   93/93, 20/20, 19/19, and 14/14) and a zero-ambiguity check against Base.
   These are declaration, storage, adaptation, inspection, and CPU local-view
   results.  They are not execution evidence: Metal compacted kernels,
   plan-derived demand, prepared binding, and cross-backend parity remain
   explicitly deferred to Gates B and C.
2. **One-group source-order compacted.** Implement one qualified private exact
   scan and stable scatter through existing phase tuples.  Land external
   contact/FEM witnesses and replace lifecycle mark--scan--compact directly,
   deleting the old kernels and enqueue loop in the same edit.
3. **Canonical and grouped compacted.** Add one bounded total-key ordering and
   directory phase on the same record/status/workspace substrate.  Land the
   particle-group witness and replace lifecycle request ordering and site
   indexing directly.  Delete the old sort/index path rather than retaining a
   selector.

   Gate B implementation fact (2026-08-18): all four rows now lower through
   one `_CompactedLowering` and the existing plan/prepare/run lifecycle.  One
   collect kernel evaluates the operation once per selected item and
   materializes every port.  Each port then uses visible fixed-256
   hierarchical Blelloch levels, stable scatter, fixed-256 local bitonic
   ordering when required, deterministic ping-pong merge levels, lower-bound
   grouped-directory construction, one shared finalize gate, and guarded
   structured publication.  One private structured-binding protocol owns
   logical shape, representation, recursively flattened physical leaves,
   backend/device validation, prepared identity/revalidation, aliasing, and
   inspection for arrays and structured bindings. `CompactedStorage` registers
   once through that protocol.  Public records, candidate records, and tuple
   key/identity scratch use recursive component-backed storage, including
   nested tuples, rather than composite global load/store instructions.
   Invalid groups and duplicate canonical identities are
   found in parallel with deterministic atomic-min diagnostics; finalization
   inspects only the bounded per-port diagnostic/count scalars.  Overflow,
   invalid groups, and duplicate identities are invalid-complete and leave all
   bound `CompactedStorage` publication leaves unchanged.

   Focused CPU evidence is 95/95 Gate B execution assertions across the four
   rows, a two-port single-collect witness, scalar and nested-tuple records,
   recursively componentized tuple key/identity ranks and callable-extractor
   closure,
   255/256/257/513 boundaries, capacity-zero all-false output, three
   invalid-complete no-write cases, lease drainage/requeue, and a 513-item
   two-level scan plus deterministic merge witness.  The compacted foundation
   remains 126/126, the focused API slices remain green, and recursive
   ambiguity detection against Base is empty.  All production kernels are
   KernelAbstractions kernels; no raw Metal launch or device intrinsic is part
   of this lowering.  A real scalar-disabled Metal witness, warm-allocation
   evidence, and backend parity remain Gate C requirements and are not claimed
   here.  Executable callable group/key/identity extractors remain deliberately
   closed: field symbols are existence/type-qualified at plan time, while
   inert callable descriptors receive a truthful plan error until the ordinary
   load-only effect proof can qualify their exact method bodies.

   The prior four-structured-port compiler pathology is removed by prepared
   minimal phase views, type-erased cold identity evidence, and eliminating
   launch-time reconstruction of whole port-workspace NamedTuples.  In a fresh
   `--compiled-modules=no` CPU process the bounded representative measured
   29.20 seconds to plan, 48.70 seconds to prepare, and 16.36 seconds for its
   first run; all four structured ports completed exactly.  These are
   compile-latency facts, not steady-state performance claims.

   Gate C implementation fact (2026-08-18): ordered lowering now performs one
   typed compacted-demand prepass before stage admission. `record_count`,
   `source_position`, and `bounded_group_read` resolve one earlier compacted
   producer, reject missing, ambiguous, self, or future producers, and carry
   producer/consumer stage, role, bound, capacity, and lane count in the typed
   `_SequenceLowering` demand tuple. Planning remains the authority for the
   optional source-position projection: `allocate_compacted_storage(plan,
   :port)` derives it from admitted demand, and preparation requires exact
   agreement rather than silently adding or ignoring a projection.

   The prepared sequence remains one phase tuple and one provider lane.
   Record-count participation reads the device count in the consumer kernel;
   source positions materialize a fixed `SourcePositions{K}` value; grouped
   reads construct their bounded read-only view in the kernel. Group occupancy
   is checked by one KernelAbstractions validation phase per distinct
   `(producer, port)` demand using the producer's shared gate and status.
   Duplicate reads of one port coalesce to their minimum bound; validators are
   ordered by canonical producer-port ordinal, and that exact ordinal is
   written into diagnostic context. The single record-count active selector
   explicitly retains its own port rather than borrowing the first read port.
   Each occupancy phase launches one 256-lane workgroup: lanes scan strided
   groups, reduce the minimum violating group through 1 KiB of local Int32
   scratch, and lane one records the exact port, group, occupancy, and bound.
   There is no single-lane whole-directory scan, global synchronization, or
   extra phase. An
   invalid bound is invalid-complete for the affected consumer: it skips that
   consumer's evaluation and publication and is reported by ordinary
   settlement. The producer-owned gate also suppresses later consumers governed
   by that producer; it does not roll back earlier stages or suppress unrelated
   later stages, which retain ordinary nontransactional sequence semantics.
   Projection
   clearing, publication, validation, and consumers enqueue without an
   intermediate wait or host count transfer. Inspection reports the typed
   demands, exact planned/prepared phase parity, `count_transfer_bytes == 0`,
   and `intermediate_waits == 0`.

   Every compacted and direct-consumer launch is a statically bounded
   KernelAbstractions kernel prepared from the admitted capacity and called
   through the same backend-neutral path. Runtime device participation still
   changes only the active predicate; it does not construct another launch or
   execution family. On the focused CPU witnesses, every prepared phase is
   exactly zero-allocation when warm. Standalone compacted execution across all
   four semantic rows and the combined source-position/device-count sequence
   both measure `0 B` for warm `run!` plus `wait`. The allocation oracle stores
   the returned concrete `WorkEvent` in `Ref{typeof(event)}` so the measurement
   excludes an artificial `Ref{Any}` boxing allocation. The grouped valid and
   invalid-complete witnesses, projection requeue witness, demand-closure
   rejection, and planned/prepared inspection evidence use the same production
   phases. No raw Metal launch, host scalar read, fallback executor, or
   old/new selector was added. A two-port same-producer witness combines
   `source_position(:a)`, `record_count(:b)`, and different bounded-group laws;
   it proves independent projection/control selection, canonical validator
   order, exact `:a` versus `:b` failure attribution, invalid-complete no-write,
   and zero-allocation warm requeue.

   Warm validation preserves the same authority without rediscovering it per
   physical leaf. Cold preparation performs the full backend/device/layout
   proof and retains the exact immutable static array objects plus their
   identity, concrete type, and layout facts. Warm static validation rechecks
   those exact object/type/layout facts. One provider lane remains the sole
   current-device authority: its reviewed current-device getter is resolved and
   cached when the scope is created, while every submission still checks
   provider functionality and equality with the reviewed device. Dynamic
   submission arrays retain full warm backend/device validation. Replacement
   arrays and in-place static layout mutation are rejected before submission.

   A real scalar-disabled Metal remeasurement after this simplification found
   `0 B` for every warm preflight category, including topology freshness, lane
   currentness, static storage identities, workspace identities, topology
   arrays, canonical submission, and their combined validation. Direct
   lowering accounts for `77,712 B` of host-side KernelAbstractions/Metal
   command encoding, plus `240 B` when synchronized in isolation. An initial
   eight-run diagnostic using `Ref{Any}` measured `77,744 B` for `run!`; the
   extra `32 B` was measurement boxing, not a production LocalWorksets
   envelope. The authoritative typed-event witness measures `77,712 B` for
   `run!` and `1,120 B` for `wait` in both recorded repetitions, with the
   prepared provider cache stable at `28 -> 28`. The production wait is
   `1,056 B` of explicit validation-status transfer encoding plus `64 B` of
   provider-lane synchronization. These are reported provider-owned host
   encoding/transfer costs, not LocalWorksets algorithmic storage or device/
   unified-buffer allocation.

   The persistent witness is
   `run_localworksets_compacted_multiport_conformance` in
   `lib/LocalWorksets/test/backend_conformance.jl`, invoked by
   `benchmark/backends/metal/runtests.jl` after `Metal.allowscalar(false)`.
   It uses only the production KernelAbstractions lowering and proves exact A/B
   structured records, counts, segment directories, live provenance,
   `source_position(:a)`, `record_count(:b)` ownership, the final partial
   result, the two demanded validator phases, two warm cache-stable runs, and
   exact invalid-A and invalid-B diagnostics with no affected-consumer
   publication. No raw Metal
   path, scalar fallback, vendor branch, or duplicate Metal-only implementation
   is involved.

   Cross-domain witness implementation fact (2026-08-18): the external half of
   the Tranche-2 gate is complete. One backend-generic witness each now covers
   2D/3D DEM contact filtering, triangle/tetrahedron active-FEM extraction with
   a device-count-controlled consumer, and 2D/3D active-particle cell grouping
   with exact directories, bounded reads, and demand-driven source-position
   projection. They use independent serial scientific oracles and the same
   public `LocalWork`, plan, prepare, phase, and KernelAbstractions execution
   path. The focused CPU run passes six DEM cases, six FEM cases, two particle
   cases, and two exact invalid-bound diagnostics. The scalar-disabled Metal
   runner invokes those same functions by changing only array storage and the
   KernelAbstractions backend; the particle witness separately passed both
   device cases with launch counts 11 and 10 and both exact diagnostics.

   The scientific, Julia-architecture, and GPU/performance reviewers passed
   this external witness gate unanimously with no blockers. The review found
   no domain branch in LocalWorksets, no oracle reuse of production extraction
   or ordering helpers, no host count transfer, and no intermediate sequence
   wait. This does not yet pass Gate 8C.2: the named Core lifecycle conversion
   and deletion ledger below remain required.

   A package-quality source boundary now scans root source, extensions, and
   every `lib/*/src` package and rejects raw Metal/CUDA/AMDGPU/oneAPI launch
   macros, compiler APIs, vendor kernel objects, command queues/buffers/encoders,
   device grid intrinsics, direct launches, and vendor synchronization. The
   obsolete raw-Metal metrics probe in the
   static-evaluator qualification script was deleted; that script now compiles,
   launches, and synchronizes its evaluator only through KernelAbstractions.
   After the accepted-relationship and lifecycle-emission kernel deletions, the
   current production census contains 51 package-owned KernelAbstractions
   kernels (24 CorePotts, 27 LocalWorksets) and no raw vendor
   kernel, compiler, launch, synchronization, queue, or grid-intrinsic path.
   KernelAbstractions is a direct root dependency. `MtlArray` adaptation and
   provider capability checks remain storage/backend boundaries. The native
   extension validates `Metal.MetalBackend()` as a
   `KernelAbstractions.Backend` before supplying it to the documented
   `DiffEqGPU.EnsembleGPUKernel` KernelAbstractions interface; no vendor object
   is used as a package-owned kernel or launch path.
4. **Ordered fold.** Reuse the exact same descriptor validation and inline
   ordering facts.  Complete the Phase 8A witness matrix, then replace accepted
   relationships and eligible lifecycle greedy/staging loops without extra
   launch or scratch.
5. **Existing-law optimizations.** Add fused terminal reduction only alongside
   report/status tranches that delete their Core counterparts. State copying
   remains an ordinary direct multi-port sequence; no component subsystem
   exists.
6. **Broader lifecycle lowering.** Convert remaining eligible planning,
   selection, staging, validation, and finalization slices through the same
   laws and delete each superseded direct implementation immediately.
7. **Deferred decisions.** Consider frozen ragged routes, public scan, and
   `resolved(...; keep=K)` only after their independent evidence gates.  They do
   not count toward the Core-completeness claim beforehand.

These are direct architectural edits, not migration infrastructure.  There are
no compatibility shims, feature selectors, old/new modes, parallel production
paths, or per-domain adapters.

### Phase 8B acceptance and rejection

Accept a tranche only when:

- `compacted` and `ordered_fold` remain the only new semantic laws;
- all descriptors are typed inert values and ordering authority is shared;
- compacted storage is one logical lifetime with no topology confusion;
- device count and segment consumption require no host read;
- every private physical phase is planned and inspected, allocates no warm
  LocalWorksets algorithmic storage or device/unified buffer, and uses the
  existing runner, leases, gates, and settlement; backend-owned host command
  encoding must be separately attributed, bounded per planned phase, stable
  across replay, and reported rather than hidden;
- CPU and scalar-disabled Metal use the same semantic lowering and exact
  canonical record order;
- no backend algorithm selector, fallback, hidden launch, scratch, or wait is
  introduced;
- a converted Core slice preserves exact scientific order, status, RNG,
  checkpoint, failure, launch, and scratch behavior; and
- the complete direct tranche deletes more Core production source and
  orchestration than it adds to LocalWorksets.

Reject or revise if scan, compact, sort, grouping, traversal, and indexing
become separate public families; if grouped state is presented as frozen CSR;
if ordering is duplicated between compacted and ordered fold; if a histogram or
atomic cursor loses canonical stability; if a transition receives writable
arrays; if top-K is used as greedy selection; if dynamic work generation or a
scheduler enters the waist; or if broad expressibility is achieved only by
hiding domain mutation in opaque callables.

## Phase 8C -- migration-free direct implementation and review boundaries

### Development decision

Phase 8B is implemented as five deletion-bearing direct edits.  These are not
migration phases.  A tranche contains its complete LocalWorksets capability,
real external witnesses, immediate Core adoption, and deletion of the
superseded Core kernels, orchestration, workspace, inspection, and obsolete
internal tests in one working change.

There are no:

- compatibility constructors or aliases;
- deprecated names or checkpoint formats;
- old/new execution selectors or feature flags;
- shadow production evaluation;
- fallback scan, sort, fold, or publication algorithms;
- retained dormant kernels or workspace fields;
- per-domain adapter hierarchies; or
- migration suites whose purpose is preserving an obsolete internal shape.

Independent scalar and domain references remain test-only scientific oracles.
They do not share production transition, key, ordering, or publication helpers.
If a tranche fails its gate, its new production source and tests are revised or
removed.  Failure is never handled by shipping both paths.

Each tranche has one independent committee review at its completed dependency
boundary.  There are no committee subgates for individual files, kernels, scan
levels, or implementation steps.  Ordinary Julia design, focused unit tests,
and direct source review govern work inside the tranche.

### Common direct-edit rules

Every tranche MUST:

1. use the existing
   `LocalWork -> _LoweredWork -> phase tuple -> _PreparedPipeline -> recursive
   executor -> KernelAbstractions` path;
2. materialize every physical launch in the planned/prepared phase tuple;
3. use the same phase and kernel types on CPU and claimed GPU backends;
4. reuse the existing provider lane, leases, validation status, gates,
   settlement, poison, and event lifetime;
5. allocate no warm execution storage and perform no host count read, polling,
   wait, or hidden synchronization;
6. replace a complete Core operation family, not merely its `@kernel` spelling;
7. delete the replaced launch construction, helpers, scratch ownership,
   validators, inspection cases, and dead tests in the same edit;
8. preserve Core scientific values and callables only where they still express
   domain meaning; and
9. leave exactly one production implementation after review.

An individual Core operation that cannot meet semantic, launch, scratch,
compile, or deletion requirements remains untouched.  No unused generalized
profile is added on its behalf.

### Review committee

Every dependency-boundary committee has four explicit responsibilities:

1. **Compiler and Julia design:** semantic-authority count, concrete dispatch,
   inference, source provenance, lowering/path count, and absence of a second IR
   or executor.
2. **GPU and performance:** selected-device compilation, one CPU/GPU path,
   physical launches, scratch, transfers, allocations, register/code-size
   pressure, queue/lease behavior, and truthful provider-failure visibility.
3. **Scientific modeling and UX:** independent oracle parity, exact order and
   failure semantics, negative controls, domain ownership, diagnostics, and the
   ordinary versus compiler-author learning surface.
4. **Simplification and maintainability:** deleted kernels, helpers, workspace,
   validators, branches, adapters, phase types, and production lines versus the
   complete addition.

The committee returns only `pass`, `revise directly`, or `remove tranche`.
It does not approve half a tranche while retaining two production paths.

At every gate record one compact evidence row containing:

- public semantic laws and author-visible names;
- persistent semantic, lowering, prepared, executor, and kernel type counts;
- Core production-kernel count;
- affected launches, workspace, transfers, and warm allocations;
- validators, status/gate authorities, adapters, and strategy branches;
- LocalWorksets and Core production lines; and
- retained Core mechanisms with exact scientific or measured-performance reason.

Line and kernel counts are supporting evidence.  A generic callable that hides
the same mutation and leaves orchestration or workspace intact receives no
deletion credit.

### Tranche 1 -- existing-law execution consolidation

This tranche adds no public mathematical law.  It completes one private
strategy and one direct existing-law adoption:

- one-launch, zero-algorithmic-scratch terminal execution for centrally
  qualified one-destination deterministic/seeded `combined` and top-1
  `resolved` work; and
- Core state-bank projection into bounded named multi-port direct works grouped
  by equal extent, using ordinary phases, optional shared status gates, and no
  LocalWorksets component subsystem.

Likely LocalWorksets edit surface:

- `execution/pipeline_support.jl`;
- `execution/localworksets_combined.jl` and its evidence/workspace support;
- `execution/localworksets_single_resolved.jl`;
- `execution/localworksets_generic.jl`;
- `execution/fixed_lane_support.jl`;
- `execution/record_storage_support.jl`;
- `execution/mechanism_support.jl`;
- `preparation.jl`; and
- `inspection.jl`.

At most one cohesive private implementation unit may be added for terminal
execution. No `terminal_reduce`, `component_map`, copy,
bank, report, status, rollback, or transaction constructor becomes public.

Immediate Core candidates include:

- `_checkerboard_report_kernel!`;
- `_reduce_lifecycle_planning_status_kernel!`;
- `_reduce_lifecycle_status_kernel!`;
- `_clear_selected_division_workspace_backend_kernel!`;
- `_clear_lifecycle_policy_workspace_kernel!`;
- the now-deleted lifecycle-gated generic and relationship copy kernels;
- `_publish_program_bank_kernel!`;
- `_stamp_lifecycle_failure_kernel!`;
- `_finalize_lifecycle_backend_kernel!`;
- `_rollback_checkerboard_program_step_kernel!`; and
- `_checkerboard_commit_kernel!`.

Each candidate is converted only if the unchanged existing law produces an
equal-or-smaller complete execution.  K08 report remains one launch and zero
algorithmic scratch.  A complete winning status record comes from one resolved
candidate.  The shared lifecycle gate is sampled by every ordinary direct stage
before publication.  Extents are exact by construction, and multi-port provider
failure is never described as atomic.

#### Gate 8C.1

The committee verifies that no public semantic authority was added, every
selected Core kernel and its bespoke launch/helper machinery is gone, exact
report/status/bank/checkpoint behavior remains Core-owned, CPU and Metal compile
the same strategy, launches/scratch are noninferior, warm package-owned
algorithmic/device-buffer allocations remain zero, provider host-command
encoding remains stable and separately reported, and the complete production
edit is deletion-positive.

Here and below, **deletion-positive** is structural: the accepted edit must
remove more duplicated semantic authorities, bespoke kernels, launch/helper
families, and production execution paths than it introduces. Raw production
line count is recorded at every gate and may trigger compression review, but
it is supporting evidence rather than an absolute veto. Validation, schema
proof, and independent scientific evidence are not deleted merely to make the
physical line counter negative.

Profiles that do not qualify are removed from the tranche rather than retained
disabled.

### Tranche 2 -- complete compacted canonical materialization

Land all four semantic rows together through one declaration, storage, and
lowering contract:

```text
one_group + source_order
one_group + canonical_by
group_by  + source_order
group_by  + canonical_by
```

Also land `record_count`, `bounded_group_read`, and the demand-driven
source-position projection.  Do not land descriptors alone, a source-only
public subset, or temporary record layouts.

Likely LocalWorksets edit surface:

- `LocalWorksets.jl` and `model.jl`;
- `authoring/syntax.jl` and `authoring/lowering.jl`;
- `planning.jl`, `preparation.jl`, and `inspection.jl`;
- `execution/pipeline_support.jl`;
- validation, workspace, arbitration, evidence, and record-storage support;
- `execution/localworksets_keyed.jl`; and
- at most two cohesive compacted/canonical-record implementation units.

One public, inspectable `CompactedStorage` logical authority owns records,
device `Int32` count, optional segment directory,
provenance, and requested projections.  Planned/prepared responsibilities cover
collect/validate, the finite exact scan hierarchy, stable scatter, one qualified
total-key order, directory/projection construction, and guarded structured
publication.  Every scan/sort pass is visible in the phase tuple.  There is one
record/key/group validator and one validation gate shared or consolidated with
the existing keyed substrate.

External witnesses are complete 2D/3D DEM contact filtering, adaptive
triangle/tetrahedron FEM active-element extraction, and active-particle spatial
grouping.  They use independent serial filter/map/order/group oracles.

Core conversion in the same edit replaces lifecycle request materialization and
owner-to-site dynamic indexing.  Delete:

- `_mark_lifecycle_requests_kernel!`;
- `_lifecycle_scan_step_kernel!` and `_enqueue_lifecycle_scan!`;
- `_compact_lifecycle_requests_kernel!`;
- `_sort_lifecycle_backend_kernel!` and its launch assembly;
- `_lifecycle_site_key_kernel!`;
- `_lifecycle_sort_step_kernel!` and `_enqueue_lifecycle_sort!`;
- `_index_lifecycle_sites_kernel!`; and
- their obsolete debug, factory, CPU-production, and binary-search/index helpers.

Replace, rather than alias, `request_scan`, `request_scan_scratch`, `site_keys`,
mutable request order/count authority, and the independent site starts/counts/
records/position authority with the logical compacted bindings wherever the
conversion is complete.  Downstream lifecycle code consumes typed count/group
accessors directly.  No compatibility property layer shadows old fields.

Free-resource compaction is included only if the same edit deletes its complete
manual packing authority; otherwise it remains for Tranche 4.

#### Gate 8C.2

The committee verifies exact records, counts, segment directories, inverse
positions, representative sites, provenance, diagnostics, invalid no-write
behavior, device continuation without host reads, CPU/Metal one-path execution,
zero warm LocalWorksets algorithmic/device-buffer allocation, separately
reported stable provider host-command encoding, and exact phase/workspace
inspection.  All four rows must share one law and storage authority.  The seven
named Core kernels, their
enqueue loops, and obsolete control/workspace fields must be gone, and the
complete combined production edit must be deletion-positive.

No public scan, sort, traversal, scatter, CSR, queue, or algorithm selector may
exist after this gate.

Implementation evidence (2026-08-17): Core lifecycle owner-to-site indexing
and canonical request materialization now lower to `compacted` outputs and run
through the same prepared KernelAbstractions phases on CPU and Metal. The
lifecycle workspace owns the sole typed `CompactedResult` authority for each
index. All former starts/counts/cursor/site/position/representative arrays and
the mutable canonical-order authority were deleted; downstream code reads
typed count, group, record, and source-position accessors. `selected_order` is
a Core-owned post-compaction selection view and never mutates canonical
publication. Sequential execution uses prepared LocalWorksets compaction just
as checkerboard execution does, while checkerboard settlement retains
bank-specific completion tails for every prepared lease.

The focused backend-generic witness
`run_lifecycle_compaction_execution` passes the exact same site records,
directory, inverse positions, canonical request slots, keys, and identities on
`Array` and scalar-disabled `Metal.MtlArray`. Both executions report
`execution = :kernelabstractions_single_path`; the witness changes only array
storage and the backend inferred by KernelAbstractions. The package-quality
boundary independently rejects raw vendor kernel macros, compiler APIs, kernel
objects, command queues/buffers/encoders, device-grid intrinsics, direct
launches, and vendor synchronization throughout every production package.

Gate review (2026-08-17): the independent request-ordering, site-index, and
compiler/GPU integration reviewers all passed the direct conversion with no
remaining blockers. The only review defect was a stale ten-tail test
expectation; it was replaced by checks for all fifteen bank-specific scalar
completion tails plus the two state-copy event vectors. A complete two-MCS CPU
settlement subsequently passed with one settlement and ownership checksum
`95`, and the focused real-Metal compaction witness passed with scalar indexing
disabled.

### Tranche 3 -- ordered fold and state-dependent Core replacement

Implement the complete Phase 8A contract through one output declaration,
lowering, plan/prepared phase, and KernelAbstractions kernel.  It reuses Tranche
2 ordering descriptors and validation authority and Tranche 1 heterogeneous
publication.

The transition is a concrete storage-free callable receiving read-only current
accumulator access and returning one fixed bounded typed update record.  The
engine validates all step destinations before canonical application.  No
writable array, persistent patch AST, transaction status, commit mode, bank
trait, or publisher is admitted.

External witnesses are 3D PGS contact, 2D random sequential adsorption, and
grouped exact stoichiometric admission. Central conformance owns the mechanism
edge cases; paired snapshot/Jacobi counterexamples establish why existing laws
are scientifically different. A bounded graph case is optional because it is
not independent enough from Core relationships to justify another mandatory
witness.

Accepted relationships lower through one typed recurrence architecture.  The
Core-owned accepted-descriptor evaluator remains a KernelAbstractions producer;
ordinary LocalWorksets validation establishes whole-stage status precedence,
then one `ordered_fold` specialization per concrete packed representation bank
performs select--compact--canonicalize--initialize--fold, followed after the
accepted-state application by ordinary gated component publication.  Bank
count may specialize the number of physical phases, but never selects another
algorithm or backend path.  This is smaller and more Julian than padding or
type-erasing heterogeneous payloads merely to force a launch-count target.
Delete:

- `_checkerboard_prepare_relationships_kernel!`;
- `_checkerboard_publish_relationships_kernel!`;
- their raw launch construction and calls;
- relationship scratch wrappers now owned by prepared fold storage; and
- duplicated Core compact/sort/copy/publish helpers that no remaining host
  scientific oracle requires.

Core keeps request construction, keys, identities, precedence, admission,
generation, payload, degree/capacity, idempotence, filter/status, bank, MCS, and
checkpoint meaning.

The accepted-create order identity must be total. Preserve the semantic
attempt identity used by status and checkpoint meaning, while adding an
order-only flattened candidate/descriptor identity.  Within each bank the
canonical key begins with the logical relationship slot, then priority and
canonical endpoints, preserving the former per-schema processing order. Equal
order key/identity records reject. Core admission specializes the incidence
update bound with `Val(maximum_degree)` only for a reviewed static maximum;
schemas above that GPU-practical bound remain outside this adoption rather than
creating a runtime tuple or writable mutation escape.

#### Gate 8C.3

The committee verifies one recurrence law and ABI across all witnesses, no
domain branch or mutation escape, exact order/update/halt semantics, static
patch-capacity bounds, successful device compilation and stable compiler cache,
hostile alias/address failures, CPU and Metal execution, lease isolation, and
exact Core relationship parity.  Physical phase count must be inspectable and
derive only from the number of concrete packed representation banks and
ordinary publisher chunks; it is evidence, not a semantic contract.  There is
one algorithm, one prepared runner, and one KernelAbstractions backend path.
The two bespoke kernels and obsolete orchestration/storage are deleted, packed
bank staging has no scratch growth relative to the replaced authority, and
production source and combined kernel count decrease.

If bounded typed updates cannot meet the GPU evidence, remove the failed Core
conversion or the unused law.  Never replace the protocol with a writable-state
escape hatch.

Implementation evidence (2026-08-18): the direct Gate 8C.3 edit is present.
Accepted evaluator failures resolve through one ordinary `resolved` work;
each touched concrete `PackedRelationshipBank` owns one staged packed copy and
one `ordered_fold`; and live publication is an ordinary bounded multi-port
`independent` sequence.  The former relationship prepare/publish kernels,
their scratch wrapper, filtered counter, copy/sort/publish helpers, and the
checkerboard transaction-buffer field are absent.  Stores with no sequential
or after-MCS transaction demand now allocate no generic transaction buffer or
staged state copy.

Request addressing and scientific ordering are deliberately separate.  The
candidate-major storage slot continues to use the compiled buffer slot, while
`order_identity` uses candidate-major canonical descriptor traversal order.
Thus manually constructed plans with permuted buffer slots preserve Core's
source order, including the observable first-create/idempotent-payload case.
Logical relationship slots remain the leading canonical key field; packed
bank-local slots alone address accumulator schema arrays.

`success_gate` is the device-resident composition boundary between a validated
source `WorkEvent` and downstream LocalWork.  It combines the caller's gate
with the exact source lease's device validation words, performs no wait or host
copy, adapts recursively to an isbits device view, and closes every publisher
launch after a failed fold.  Ordered-fold successful-prefix visibility is
therefore confined to the private staged bank; it cannot reach live Core state.
This is an emergent finite-work composition, not a transaction law or second
execution path.

Focused evidence passed on CPU for the exact LocalWorksets API, all 24 base
ordered-fold checks, all 78 admission/composition checks, a normal Core
relationship MCS, two logical schemas sharing one packed bank, and permuted
descriptor buffer slots.  A scalar-disabled real-Metal witness compiled the
fold and gated publisher through KernelAbstractions, observed the intended late
validation error, and proved the live device target remained unchanged.  The
repository boundary scans `.jl` and `.ipynb` source under production, tests,
benchmarks, examples, and scripts.  Its exact scan finds no raw vendor kernel,
compiler, launch, synchronization, command-buffer, or grid-intrinsic path.
The post-deletion census is 52 package-owned KernelAbstractions kernels: 25 in
CorePotts and 27 in LocalWorksets.

Final Gate 8C.3 committee verdict (2026-08-18): **PASS**, unanimously, with
zero P0 or P1 findings.  The first review correctly rejected publication that
could expose a failed fold's staged prefix and ordering that conflated buffer
slots with source order.  Those designs were removed before approval.  The
second compiler/Julia, scientific-semantics, and GPU/performance audits each
verified the corrected typed boundary, direct deletion, packed-state invariant,
exact ordering, device-resident failure gate, and one KernelAbstractions path.
The GPU committee's sole P2 is a profiling-led opportunity to compact each
bank's disabled request range; it is not a semantic authority or alternate
path and is deliberately not addressed without measurements.  A separate cold
metadata observation was resolved immediately: zero-demand stage buffers now
store `nothing`, not a `RelationshipStorage` of placeholders.

### Tranche 4 -- lifecycle decision pipeline

This tranche uses only approved laws and strategies.  It adds no LocalWorksets
semantic feature or Core-named extension.

Its scientific boundary begins with authoritative state at a due MCS and ends
with one authoritative selected lifecycle request set, complete plans,
allocations, and canonical status.  Convert:

- request emission and canonical compacted materialization;
- owner/site grouped reads;
- create/retire/remove/transition and division planning;
- selected replanning and relationship-footprint validation;
- reject and greedy conflict policies;
- selected-request materialization;
- free-resource compaction, capacity/generation preflight, and positional
  allocation; and
- canonical planning/selection status resolution.

Ordinary snapshot/disjoint rows use direct, pointwise, combined, or resolved
work over compacted records.  Greedy prior-selected-footprint dependence uses
`ordered_fold`.  The Gate 8C.4 research audit established that division
connectivity is also a genuine bounded recurrence: the current scientific law
performs request-local labeling followed by two connectivity traversals.  It
must therefore lower either to a proved finite LocalWork sequence or to a
second `ordered_fold` recurrence.  It must not survive as a hidden raw planner,
and it must not acquire `maximum_requests * site_count` scratch without an
explicit memory bound.  Supply assignment is an ordinary validated positional
map, not a reservation or matching law.

Delete complete converted definitions and launch loops, including eligible:

- `_emit_lifecycle_backend_kernel!`;
- `_plan_lifecycle_effect_backend_kernel!`;
- `_plan_lifecycle_division_backend_kernel!`;
- `_validate_lifecycle_division_relationships_backend_kernel!`;
- `_replan_selected_lifecycle_division_backend_kernel!`; and
- `_select_lifecycle_backend_kernel!`.

Remove duplicated control/status/order/allocation scratch and host/backend
production planning implementations.  A separately written lifecycle decision
interpreter remains under tests only.

Implementation evidence (2026-08-18), first dependency boundary:

- lifecycle request emission is one two-stage LocalWork sequence: a
  full-coverage typed emission record followed by origin-complete canonical
  status resolution;
- sequential and checkerboard CPU/GPU execution prepare and run the same work
  and lowering identity; the packed host emitter and raw backend emission
  kernel are deleted;
- sequential execution prepares that one emission work for both physical
  transaction banks and selects the bound science view by the same ownership
  array identity used by site indexing.  Each view carries matching ownership,
  kinds, generations, trackers, packed relationships, descriptor state, and
  staged lifecycle wrapper; no immutable preparation retains the initially
  published bank after the candidate-bank swap;
- descriptor-major fixed lanes preserve model/cell domains, cadence,
  generation, trigger context, semantic RNG addresses, and request-local
  policy-workspace columns;
- portable lifecycle evaluators are total device-callable scalar functions:
  expected invalidity must be returned as a typed value (including the
  explicitly checked non-finite and non-Boolean trigger results), not raised as
  a Julia exception.  Host exception capture is not a second production
  semantic path; a future recoverable evaluator failure must use an explicit
  tagged result if it is to cross CPU and GPU identically;
- `ProgramStatus` is produced with complete MCS, stage, source, action, anchor,
  and detail provenance at emission, so no heuristic failure stamp is needed;
- status enums remain typed in component storage, backed by centrally reviewed
  primitive leaf stores;
- accepted-validation and lifecycle-emission receipts occupy distinct entries
  in the 19-slot cumulative event ledger, and inspection reports both;
- emission preparations from both checkerboard banks participate in the common
  provider/compiler/capability execution-identity proof.  Sequential and
  checkerboard also share the rule that a globally non-due MCS is lifecycle
  inert, including ownership validation and inactive request rows;
- cold preparation asserts both tuple cardinality and positional ownership
  identity for sequential science banks, making an accidental bank reorder a
  construction error rather than a warm-path semantic fault;
- focused CPU probes cover checkerboard and sequential success plus evaluator
  failure/provenance and an explicit sequential physical-bank selection case
  that distinguishes candidate science from the initially published bank.
  The repository's full Metal lifecycle witness entered
  device compilation without a semantic/adaptation failure but was stopped
  after prolonged LLVM compilation; a completed real-device run remains Gate
  evidence, not an architectural fallback.

The compiler/Julia, scientific-modeling, and GPU/performance dependency review
passed this boundary with zero P0 or P1 findings.  Its remaining P2 evidence
items are a completed real-Metal compilation and, if recoverable throwing
evaluators are ever required, an explicit portable tagged-failure result rather
than CPU exception capture.

The research committee also found two tranche-wide requirements.  Every phase
must construct complete status provenance at origin rather than relying on
`_lifecycle_failure_descriptor`, and the final gate needs a separately written
test-only decision interpreter rather than treating the sequential production
engine as an independent oracle.

#### Gate 8C.4

The committee compares emitted records, provenance, active/filtered/selected
masks, canonical order, planned sites and partitions, conflict identities,
free-resource order and allocation, and every `ProgramStatus` field against the
independent interpreter for all lifecycle actions, priorities, conflict
policies, failure/filter cases, capacity/generation conditions, 2D/3D shapes,
and semantic RNG policies.

The selected-plan boundary must be exact, device-resident, allocation-free, and
produced by one Core compiler/LocalWork production graph.  All replaced kernels,
workspace fields, raw launch assembly, and host production duplicates are
deleted; combined source decreases.  Do not proceed to application conversion
if the selected-plan meaning is only approximately equivalent.

Current Gate 8C.4 implementation evidence (2026-08-18):

- request indexing and lifecycle selection now lower to one 13-stage
  `LocalWorksets.sequence`, one `WorkPlan`, one `PreparedWork` per physical
  bank, and one returned event.  Sequential and checkerboard execution use the
  same prepared graph;
- validation of a later stage is controlled by the device-resident successful
  prefix of prior stage validation words.  There are no intermediate host
  waits, host copies, or alternative production selectors;
- `selection.ready` is the sole validity receipt for selected counts,
  positions, and allocations.  It is reset every MCS and published only after
  complete semantic success, so a due-to-non-due transition cannot expose
  stale selection state;
- direct logical bindings use the typed `_BindingRead{Name}` token and lower
  through statically unrolled read construction.  Inspection projects the
  token back to the authored symbol; a focused structural witness infers the
  exact `CompactedStorage` type and records zero allocations for warm `run!`
  and `wait`;
- downstream resource and publication stages read each canonical
  `CompactedStorage` authority directly.  The former component aliases for
  counts and records are deleted, including the illegal alias pairs they
  created;
- sequence `StructArray` facts recurse through physical components.  Sequence
  topology ownership is derived from each stage's actual phase payload rather
  than from a second full-stage payload interpretation;
- conflict, capacity, and generation-overflow statuses are complete at their
  origin.  Conflict action provenance uses the first descriptor for the
  normalized source; capacity uses the first selected semantic publication;
  overflow uses the selected publication matching the exhausted anchor;
- stable-priority packed relationship conflict is admitted through a bounded,
  cycle-rejecting transitive typed-IR verifier for exact residual invokes.  It
  retains the mutation, foreign-call, storage, selected-method, source-IR,
  optimized-IR, and world-age checks; no CorePotts helper name or external
  trait is trusted;
- runtime relationship reads remain canonical `PackedRelationshipBank`
  storage.  `ProgramRelationshipState` remains cold construction/transaction/
  serialization input and is not converted on a queued or warm path;
- the production scan contains no raw Metal launch.  Metal integration selects
  and adapts a KernelAbstractions backend and arrays; execution remains the one
  KernelAbstractions path;
- the independent physical differential passes all eight cases, including
  reversed-slot priority/dedup order, site and anchor conflict, reject and
  stable policies, mixed recycled/virgin resources, capacity provenance,
  both overflow provenance forms, and a packed relationship-only conflict.
  The older independent decision oracle passes all 15 checks.  The focused
  checkerboard/sequential lifecycle probes pass, and the ordered-fold base and
  admission/composition witnesses pass 24/24 and 78/78 respectively under
  reduced compilation.

The scientific and GPU/performance committee members give this boundary a
final **PASS** with no P0/P1 findings.  The Julia/compiler member approves warm
type stability, inspection meaning, the transitive effect verifier, and the
restriction of boxed vectors to cold evidence/schema metadata.  Gate 8C.4 is
nevertheless **OPEN / COMPILER-HEALTH BLOCKED**: an ordinary optimized Julia
run of the flagship 13-stage lifecycle initialization still did not complete
within an 80-second post-precompile observation, despite deletion of eager
per-stage phase/workspace evidence and boxing of cold leaf metadata.  Reduced
compilation proves behavior but is not sufficient release evidence.  Continue
profiling only cold construction/evidence boundaries; do not box executable
`_PreparedPipeline.phases`, split the scientific sequence, introduce an
old/new selector, or proceed to Tranche 5 until ordinary initialization
completes in a reasonable bounded time.

### Tranche 5 -- lifecycle application, publication, and control collapse

Starting from Tranche 4's authoritative selected plan, convert the complete
application half:

- structural staging for every lifecycle action;
- relationship inheritance/removal/retune/create effects;
- state/property/native-component transfer;
- tracker and ownership effects;
- staged validation and canonical status selection;
- guarded heterogeneous publication;
- counters, generations, receipts, and finalization; and
- remaining eligible accepted evaluation/application, reset, failure-stamp,
  commit, bank, rollback, and settlement mechanics.

Use `ordered_fold` only for true prior-state recurrence.  Conflict-free state
updates use existing direct laws; status and counters use existing resolved and
combined laws; publication uses existing gates and the Tranche 1 component
strategy.  LocalWorksets gains no transaction, bank, rollback, receipt, or
checkpoint law.

Eligible deletion includes:

- `_stage_lifecycle_structure_backend_kernel!`;
- `_stage_lifecycle_relationships_backend_kernel!`;
- `_stage_lifecycle_state_backend_kernel!`;
- `_finalize_lifecycle_effect_backend_kernel!`;
- `_validate_lifecycle_backend_kernel!`;
- remaining lifecycle finalization/control kernels;
- `_checkerboard_accepted_evaluation_kernel!` and
  `_checkerboard_apply_accepted_kernel!` only when their effects are explicit
  and deletion-positive; and
- raw backend lifecycle launch/control files or includes when they become empty.

Collapse the production host/backend lifecycle split when both express the same
mechanics.  Core should retain one prepared LocalWorksets lifecycle sequence and
its scientific compiler callables, not a registry of migrated kernel adapters.

#### Gate 8C.5 -- final integration and API freeze

The final committee requires exact ownership, kind/generation, property/state,
relationship/payload/incidence, tracker, status, counters, receipt, bank,
checkpoint, resumed-continuation, MCS, and semantic RNG parity against the
independent test interpreter.  It audits queued submissions, retaining fences,
failure injection, closed gates, CPU and scalar-disabled Metal, launches,
workspace, allocations, and complete source/kernel deletion.

There must be one production lifecycle graph, one LocalWork executor family,
one canonical-order authority, and one status/receipt/settlement path.  Delete
empty kernel/enqueue/control files rather than preserving architectural shells.
Every retained Core kernel receives an exact missing-law or measured-performance
justification and cannot coexist with an equivalent LocalWork path.

Only after this gate freeze the advanced explicit names and decide whether they
are exported or intentionally public-but-unexported.  Rewrite provisional names
directly; add no aliases.  Do not add ordered-fold macro sugar unless several
complete external examples prove it clearer than the explicit constructor.

### Rejection and source restoration

A rejected tranche is removed as source, not disabled at runtime.  Restore the
affected files to their exact pre-tranche contents and delete newly added files,
tests, and documentation that have no surviving consumer.  This policy never
authorizes destructive Git operations against unrelated user work; restoration
is a scoped direct edit of the tranche's own changes.

The following responses are forbidden:

- keeping a failed implementation private "for later";
- adding a CPU-only or direct-Core fallback;
- adding a strategy selector to preserve two algorithms;
- relaxing alias/effect validation;
- hiding mutation in a singleton callable;
- preserving old workspace fields as compatibility aliases; or
- counting a moved kernel body as architectural adoption.

AcceleratedKernels is outside these tranches.  It receives a separate future
dependency review only if one forceable CPU/Metal algorithm with caller-owned
scratch, asynchronous operation, fully inspectable launches, and no hidden
allocation/wait can directly delete the then-current package-owned scan or sort.
Both implementations are never retained.

## Final acceptance

The completed program requires:

- every faithfully representable Core mechanical operation uses LocalWorksets;
- retained direct Core kernels have an inspected missing-law or performance
  justification and contain no duplicated LocalWork production path;
- the three named probes remain the only non-production compiler kernels;
- Core direct AcceleratedKernels dependency and import: 0;
- retired scalar-authoring API references: 0;
- persistent DAG, SSA, liveness, scheduler, and authoring IR types: 0;
- one semantic waist, one private lowering envelope, and one provider/executor
  family;
- zero warm execution allocations and no hidden synchronization;
- exact deterministic integer/status/order/RNG/checkpoint evidence;
- backend-qualified floating numerical evidence without false cross-device
  bitwise claims; and
- structural deletion exceeds new adoption/planning authority in each accepted
  tranche, with the raw production-line delta reported explicitly.

The earlier 37-to-zero, at-most-30 combined-kernel, and ten-percent line-count
targets are withdrawn: the review showed that they reward concealed effects or
duplicated algorithms rather than semantic simplification.  Kernel and line
counts remain evidence, never semantic acceptance criteria.
