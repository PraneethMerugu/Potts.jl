# LW-5B4O mandatory layout and execution optimization

Date: 2026-08-13

Status: **COMPLETE AND FROZEN; LW-5B4O-R PASSED**

Authority:

- owner decision on 2026-08-13 making `StructArrays` and `StaticArrays`
  first-class, always-loaded dependencies;
- [LW-5B4 pre-implementation audit](lw5b4-preimplementation-audit.md);
- [post-LW-R1 roadmap](../../spec/localworksets-post-lwr1-roadmap.md);
- [ARV1 package boundary](../../spec/symbolic-potts-v1-architecture-redirection.md);
- [Phase-12 performance contract](../audits/phase-12-performance-contract.md).

## Decision

LW-5B4O is one bounded implementation phase followed by one fresh review. It
integrates `StructArrays.jl` and `StaticArrays.jl` directly into both
`LocalWorksets.jl` and `CorePotts.jl`, repairs the outstanding B4 admission
defects, and applies the already identified general execution optimizations.
It does not add scientific features, a new execution family, a scheduler, a
backend-specific path, or a new public lifecycle.

The dependencies are not conditional on fixing K02 performance:

- both packages MUST list `StructArrays` and `StaticArrays` in `[deps]` and
  `[compat]`;
- both base modules MUST import them directly;
- neither integration may use a weak dependency, package extension,
  `Requires`, or backend-specific loader;
- neither dependency is reexported; and
- a negative result for one representation selects a better bounded use; it
  does not remove either direct dependency.

Recommended compatibility bounds are `StructArrays = "0.7"` and
`StaticArrays = "1"`. Root, test, example and benchmark environments list a
package directly only when their own source imports it; ordinary transitive
resolution is not duplicated as an artificial direct dependency.

This owner decision explicitly supersedes:

1. the ARV1-002 sentence making `StructArrays` conditional on a retained
   hot-path benchmark; and
2. the Phase-12 classification of `StructArrays` and `StaticArrays` themselves
   as optional mechanisms.

The exact representation chosen for each hot path remains measured and
reviewed. Mandatory dependency and integration do not authorize an arbitrary
layout rewrite.

## Relationship to B4

LW-5B4O is a narrow authority amendment to B4. Before changing a
representation, O0 preserves exact source hashes and every existing B3/B4
functional, performance, allocation, transfer, launch, wait, compilation and
checkpoint result, including adverse results. Direct K02 remains the selected
implementation and independent oracle.

The B4 veto on LocalWorksets source changes is superseded only for the rows in
this document after O0 is recorded. B4, production promotion, later LW-5
migration, LW-R3 and G6 remain closed until their own gates pass.

## Closed ownership boundaries

- KernelAbstractions owns portable launches, implicit ordering and backend
  synchronization.
- LocalWorksets owns validated topology, logical output semantics, component
  storage qualification, bounded workspace, lifetime, lowering and
  inspection.
- CorePotts owns proposal records, physics, RNG addressing, colors, clocks,
  acceptance, settlement, checkpoints and scientific capability identity.
- StructArrays supplies a physical structure-of-arrays vocabulary. Field
  names or field order do not authorize semantics.
- StaticArrays supplies bounded fixed-size values. Static size does not
  authorize unbounded specialization.

The current public lifecycle and output meanings remain
`localwork -> plan -> prepare -> run! -> wait`, with `independent`, `combined`
and `resolved` outputs.

## Mandatory implementation matrix

The rows are ordered implementation work inside one mini-phase, not separate
product gates. Focused tests follow each row; the complete suites run once on
the exact final candidate.

| Row | Required implementation | Required focused evidence |
|---|---|---|
| O0 — authority and baseline | Record the exact pre-phase tree, source hashes, dependency/load facts and every B3/B4 baseline. Preserve the direct kernels. | Reproducible identities and unchanged raw evidence; no source rewrite before the record. |
| O1 — B4 safety repair | Prove exact canonical/executing checkerboard sites, color offsets, conflict displacements and proposal-offset values. Derive the topology epoch from logical contents, independent of physical Julia layout. Require nonzero `active_count` to equal the selected color's exact size; retain zero only as an explicit no-emission submission. | Wrong content, order, color, count, bank and epoch reject before launch on CPU and real Metal. |
| O2 — dependency admission | Add direct dependencies, compat bounds and explicit imports to both packages; update owned environments and exact capability identities. | Independent package load, Aqua/ExplicitImports/stale-dependency checks, load/precompile/method deltas and qualified version reporting. |
| O3 — LocalWorksets StructArrays | Add centrally validated component storage. Construct no-copy `StructArray` views during `prepare`, never during `run!` or in a kernel. Use them for generic buffered combined/resolved record batches and the specialized resolved path. Qualify and inspect every physical component separately. | Component identity, type, size, strides, backend, device, access, alias, bytes and adaptation; mixed components reject; workspace and launch facts remain exact. |
| O4 — CorePotts StructArrays | Define one private checkerboard proposal row and one no-copy StructArray batch over the seven authoritative arrays. Make it the shared component/schema authority for K02 output storage and K03 proposal reads. Derive repeated bindings, destination counts and inspection descriptions from one typed schema. | The seven component arrays remain object-identical; direct kernels and checkpoints retain their existing arrays and identities; K02/K03 family-specific adapter code is materially reduced. |
| O5 — StaticArrays | LocalWorksets admits a `StaticVector{K}` spelling for the existing bounded homogeneous `K`-lane tuple algebra through one shared fixed-lane interface. CorePotts uses `SVector{4,UInt32}` and `SVector{2,UInt32}` for Philox counter/key internals while retaining any required tuple-facing behavior. If the Philox representation fails qualified compilation, select another reviewed 2D/3D fixed-local numerical use rather than removing the dependency. | Tuple/static-lane parity, exact RNG known answers and addresses, inference, native-text and Metal cache growth, and an explicit static-size budget. |
| O6 — execution optimization | Add a centrally proved identity-route token with zero topology transfer; one record-level conditional mask; generated component publication; cached static binding projections and dynamic-name facts; a static-storage/scalar-submission fast path; scalar-only lease payload elision while retaining cumulative capacity accounting; owner-task lock elision where single-task ownership is already proved; and a qualified CPU lane fast path. Consolidate duplicate CorePotts/LocalWorksets trust checks only where one owner remains explicit. | Direct-kernel vs prepared-kernel vs `run!` vs CorePotts-adapter attribution; no skipped topology, method/world, device, task, poison, lease, scalar-bound, alias or cross-field check. |
| O7 — final qualification | Execute the consolidated evidence matrix below and bind it to exact final hashes. | All correctness rows pass; performance and footprint results are reported without threshold weakening; fresh LW-5B4O-R ballots. |

## StructArrays contract

### CorePotts proposal batch

The logical row has exactly these components:

| Component | Type | Meaning |
|---|---|---|
| `target_site` | `Int32` | canonical active-color site |
| `source_site` | `Int32` | neighbor site or zero |
| `old_owner` | `Int32` | target owner |
| `new_owner` | `Int32` | source or retained target owner |
| `priority` | `UInt32` | actionable semantic priority or zero |
| `semantic_id` | `Int32` | attempt-round/site identity |
| `disposition` | `UInt8` | pending or null disposition |

The StructArray is a zero-copy view over the existing plural workspace arrays.
It is transient execution storage, not checkpoint state or scientific
identity. Adaptation moves the owned component arrays and then reconstructs
and validates the view; neither CorePotts nor LocalWorksets silently adapts or
copies caller storage during submission.

### LocalWorksets component lowering

K02 may be declared as one logical partial-independent candidate record backed
by seven named physical components. This is a refinement of the existing
independent family, not a fourth output family. Central lowering MUST:

- validate the concrete isbits row schema and every component array;
- qualify every primitive component load/store for backend x type x operation
  x address space;
- lower publication into explicit generated component stores rather than
  trusting an opaque `StructArray.setindex!` call;
- preserve component names, types, access, aliases and bytes in `inspect`;
- use one record-level `when` value, where false means no component emits;
- use one topology-proved identity destination with zero transferred route
  bytes; and
- describe visibility honestly: publication is componentwise within one
  ordered kernel, and the complete record is host-visible after the kernel
  boundary and final wait, not through a fabricated atomic transaction.

Buffered combined and resolved workspaces may use private StructArray views
over their already validated rank/value/valid records. Caller-facing
workspace contracts remain compatible in this phase. No CPM type, field name,
clock or RNG concept enters LocalWorksets.

At least one unrelated D2Q9, spring, FEM or z-buffer witness MUST exercise the
same component-storage lowering before the implementation is described as
general.

## StaticArrays contract

StaticArrays is restricted by an explicit specialization budget recorded
before implementation:

- permitted: fixed lane bundles, Philox counter/key values, 2D/3D local
  coordinates or displacements, and small fixed spring/FEM values;
- forbidden: lattice-sized state, runtime topology, arbitrary neighborhoods,
  port counts, descriptor counts, cell counts, model-sized matrices or
  workspace capacities; and
- floating Hamiltonian/source folds may not be vectorized or reassociated.

`emit(SVector(...))` with one output remains one vector-valued emission. A
`StaticVector{K,<:Emission}` used for a declaration with fixed maximum `K` is
a lane container. Tuple and static-vector spellings share validation,
lowering and diagnostics rather than creating parallel mechanisms.

Proposal direction numbering and order remain unchanged by any static local
representation. RNG stream, operation, MCS, site identity, subround, draw
count, seed, replica and repeat mixing remain bitwise identical.

## Execution-optimization invariants

The optimized path MUST preserve:

- one KernelAbstractions launch for K02;
- implicit ordering with the following checkerboard stage;
- no intermediate host wait;
- exactly one final portable `KernelAbstractions.synchronize(backend)` when
  the host requests visibility;
- cumulative event and poison semantics;
- queued colors and MCSs on one owner lane;
- immutable scalar submission values;
- prebound storage/workspace and no device allocation; and
- vendor-neutral production source.

The static submission fast path is admitted only when the prepared schema
proves that every dynamic slot is an isbits scalar. It may cache derived names,
bindings and methods, but it may not skip owner task, method/world change,
topology, lane/backend/device, prepared identity, poison, capacity, scalar
bounds or CorePotts relational validation.

## Consolidated qualification matrix

| Area | CPU | Qualified real Metal | Exit rule |
|---|---|---|---|
| Packages | Independent LocalWorksets/CorePotts load, quality checks, load/precompile delta | Exact dependency and provider identities | Both are ordinary direct dependencies; public package APIs only. |
| Component layout | Zero-copy/object-identity and all negative component cases | Device-coherent component arrays with scalar indexing disabled | No host component, copy, double adaptation or opaque capability. |
| Science and RNG | Every color; actionable, same-owner, periodic/nonperiodic, gate, zero and tail cases; varied RNG known answers | Same plus ordered downstream evaluation | Exact seven-array/direct-oracle equality. |
| Topology and counts | Complete content/order/count mismatches reject prelaunch | Canonical/device provenance mismatch rejects | No coarse summary or physical-layout authorization. |
| Inspection | One logical record, seven physical components, one mask, identity route, exact aliases/bytes | Same facts | Semantic and physical evidence remain distinct. |
| Ordering and lifetime | Queued submissions, no intermediate wait, one final scope wait, lease drain and poison | Same on real Metal | No added launch, wait, allocation, queue or scheduler. |
| Host cost | Separate prepare, warm run, wait and end-to-end allocation/time ledgers | Host submission and synchronized batch ledgers | No hot-path StructArray construction/adaptation; attribution identifies remaining cost. |
| Performance | Frozen paired fixture, order and bootstrap; preserve all raw samples | Same qualified protocol | `upper95 <= 1.05` is required for a K02 noninferiority claim; failure retains direct K02 without removing the dependencies. |
| Compilation | Inference, method instances, first/warm latency and native text | Attributable compiler-cache growth and public hardware metrics where available | No unbounded specialization or unexplained code growth. |
| Regression | Focused rows, then complete LocalWorksets/CorePotts and one complete root CPU run | One complete qualified real-Metal run including B3 and the unrelated record witness | No weakening or duplicate full-suite churn. |
| Portability | Vendor-neutral source scan and CPU KA execution | Metal qualification only | CUDA/ROCm remain unclaimed without hardware evidence. |

Focused row tests replace repeated full-suite runs. Shared semantic fixtures
are executed once per backend through a representation matrix rather than
copied into package-specific test files. The complete suites run once on the
exact candidate submitted to LW-5B4O-R.

## Vetoes

- no StructArray construction, copying, conversion or adaptation in `run!`,
  an MCS loop or a device kernel;
- no AoS replacement of the authoritative SoA component storage;
- no opaque record capability or loss of component-level validation;
- no fusion across differing routes, coverage, visibility or masks;
- no private StructArrays/StaticArrays/GPUCompiler API or type piracy;
- no unbounded StaticArray arity or model-dependent type explosion;
- no new execution family, launch, pass, wait, workspace, event fiction,
  stream, command queue or backend branch;
- no changed RNG word, Hamiltonian fold order, checkpoint identity,
  scientific transaction or settlement boundary;
- no benchmark fixture enlargement, noise search or threshold weakening;
- no CUDA/ROCm qualification claim from source neutrality; and
- no deletion of the direct oracle or arbitrary line-count target.

## Pre-phase reviewer audit

Three reviewers independently inspected the source and authority documents.
They ran no tests and made no source edits.

| Reviewer | Ballot | P0 | P1 | P2 |
|---|---|---:|---:|---:|
| Package boundary, Julian API and adapter cohesion | **PASS WITH REQUIRED REMEDIATION** | 0 | 4 | 4 |
| JuliaGPU, KernelAbstractions and performance | **PASS TO IMPLEMENT; HOLD FREEZE** | 0 | 5 | 4 |
| Scientific correctness, RNG and determinism | **CONDITIONAL PASS TO IMPLEMENT** | 0 | 2 | 4 |
| Chair synthesis | **AUTHORIZED TO IMPLEMENT; HOLD LW-5B4O-R** | 0 | 7 normalized classes | 4 carried classes |

The normalized P1 classes are: authority conflict, exact B4 topology/count
admission, central component validation, honest record route/mask lowering,
fail-closed host fast path, bounded StaticArrays specialization, and preserved
caller workspace/inspection contracts. O0 through O7 own all seven.

Substantive dissent is preserved: the scientific reviewer opposed requiring
both dependencies in both base packages without demonstrated need because of
load and compilation debt. The owner nevertheless made the dependency and
integration decision mandatory. The dissent becomes a requirement to measure
and report that debt and to keep each use narrow; it is not a dependency
ballot.

## LW-5B4O-R exit

A fresh committee reviews exact final hashes, the full matrix, each adopted or
rejected micro-optimization, dependency/API hygiene, source portability,
scientific preservation and test cost. Freeze requires P0=0 and P1=0. Every P2
must have an owner and disposition.

LW-5B4O-R separately ballots:

1. mandatory package integration correctness;
2. LocalWorksets component-lowering generality;
3. CorePotts adapter/schema consolidation;
4. K02 scientific and performance disposition;
5. B3 preservation; and
6. readiness to resume the existing LW-5 sequence.

Passing package integration does not imply K02 production promotion. A
performance-negative K02 may remain an exact architectural witness while the
direct kernel stays selected.

Primary package references:

- [StructArrays overview](https://juliaarrays.github.io/StructArrays.jl/stable/)
- [StructArrays advanced/GPU use](https://juliaarrays.github.io/StructArrays.jl/stable/advanced/)
- [StaticArrays guidance](https://juliaarrays.github.io/StaticArrays.jl/stable/)
