# Symbolic Potts V1 Cohesion, MTK, and Product Hardening Contract

Date: 2026-08-06

Status: Accepted

Phase: `G5H`, after cleared G5/R2 and before G6

## Authority and purpose

This contract is the sole authority for the work inserted between the cleared G5 execution
boundary and the unopened G6 public-integration boundary. It is accepted by
[Decision 0044](decisions/0044-pre-g6-cohesion-and-mtk-hardening.md).

The earlier Symbolic Potts contracts remain authority for compatible scientific and compiler
requirements. Where they conflict, this contract supersedes:

- the public `complete -> compile -> PottsExecutable` lifecycle;
- engine-, backend-, or scalar-selecting `mtkcompile` and public compilation;
- field-by-field assimilation of an external ModelingToolkit system into `PottsSystem`;
- `EquationComponent` or `EquationProcess` as a substitute for a native MTK component;
- manual duplication of an external system's equations, unknowns, parameters, defaults, events,
  or hierarchy;
- any use of an MTK discrete clock as the master Cellular Potts clock;
- any implication that arbitrary MTK, PDE, reaction, callback, CPU, or GPU combinations are
  supported without profile-specific evidence; and
- the claim that G6 follows G5 directly.

This contract does not reopen the cleared G0--G5 implementation evidence unless G5H changes an
invariant that evidence covered. A touched invariant is automatically reopened at the next G5H
review.

The hardening phase exists because G6 must freeze a cohesive public product, not legitimize a
half-finished integration boundary. G5H may replace unpublished APIs without compatibility wrappers.

## Required result

At G5H exit:

1. `PottsSystem` is the single public symbolic Potts model and behaves as a genuine
   ModelingToolkit system where the public MTK interfaces apply.
2. `mtkcompile(::PottsSystem)` performs structural completion and scheduling and returns a
   `PottsSystem`; it does not choose a numerical engine, backend, scalar type, device, seed, or
   runtime state.
3. Native MTK systems remain native component islands. PottsToolkit composes and schedules them
   through explicit coupling declarations rather than copying their fields into a Potts-shaped
   surrogate.
4. Numerical specialization and private CorePotts lowering happen late, during problem
   materialization, `init`, or `solve`.
5. CorePotts remains an MTK-free, mechanism-free execution kernel with one authority for each
   shared runtime concept.
6. Global, per-cell, and field component scopes have explicit lifecycle, time, coupling,
   checkpoint, ensemble, and capability semantics.
7. CPU and GPU support is reported by honest profiles. Unsupported combinations reject before
   execution and never fall back silently.
8. The final public API, examples, and documentation describe only behavior exercised by the exact
   implementation under review.

## Non-goals

G5H does not add:

- ProcessBigraphs, Mermaid, Vivarium, or a general workflow engine;
- an arbitrary dynamic execution DAG or unrestricted graph-rewriting runtime;
- a second lifecycle, scheduler, parameter store, checkpoint format, or model authority;
- an ODE representation of lattice ownership or stochastic copy attempts;
- an efficient sequential-GPU claim;
- blanket GPU support for arbitrary MTK systems or arbitrary Julia callbacks;
- a mandatory Dagger dependency;
- API or documentation compatibility with the pre-V1 `PottsModel` surface; or
- broad literature reproduction beyond the admitted Wortel and Merks proof workflows.

## Architectural invariants

### One model and one numerical boundary

The canonical public lifecycle is:

```text
functional constructors / @named / compose / extend
                         │
                         v
             incomplete PottsSystem
                         │ complete
                         v
              completed PottsSystem
                         │ mtkcompile
                         v
       scheduled, structurally compiled PottsSystem
                         │ PottsProblem
                         v
          immutable problem inputs and policies
                         │ init / solve + algorithm/backend
                         v
       private executable lowering + runtime state
                         │
                         v
          PottsIntegrator / PottsSolution
```

`complete` closes authoring meaning and validates names, units, resources, scope, IO, effects, and
provenance. `mtkcompile` may call `complete`, perform structural transformations, compile native
component systems through their public APIs, and build an immutable coupling schedule. Both
operations remain symbolic and deterministic.

The canonical authoring path uses `@named` and `@mtkcompile`. Functional constructors remain the
foundation. `@mtkmodel` is optional convenience only; the product must not depend on it or require
users to maintain parallel inventories of equations, unknowns, parameters, and subsystems.

`PottsProblem` owns the scheduled system, initial ownership and component values, parameter values,
integer MCS span, seed, replica identity, and explicit run policies. The selected Potts algorithm,
backend, and applicable numerical specialization are supplied at `init` or `solve`. A private
executable artifact may cache lowering results but is not a public authoring stage or a second
semantic authority.

### Native MTK component islands

A component declaration stores or references the originating `ModelingToolkitBase.AbstractSystem`
as a native symbolic subsystem until structural compilation. It declares, at minimum:

- stable name and namespace;
- scope: global, per-cell, or field;
- typed inputs and outputs and their ownership;
- cadence and physical duration per MCS;
- coupling publication phase and split policy;
- native problem family and numerical algorithm policy;
- initialization and event policy;
- lifecycle policy for creation, deletion, division, and kind transition where applicable; and
- required CPU/GPU capability profile.

PottsToolkit must not reconstruct the external system by copying accessor results into a
`PottsSystem`. Native hierarchy, defaults, initialization equations, observed equations, events,
and system-specific semantics stay owned by the native system and its standard problem
constructors. PottsToolkit owns the cross-domain IO map and coupled schedule.

Generic `AbstractSystem` admission is capability based, not type-name based. A system is admitted
only when PottsToolkit can identify a supported native problem constructor, initialize it through
public APIs, advance it according to the declared schedule, publish its outputs atomically, index
it symbolically, checkpoint the required state, and report its support profile. Otherwise
compilation rejects it with the originating system path and missing capability.

Domain adapters preserve semantic choices:

- Catalyst requires an explicit conversion such as `ode_model` or `hybrid_model`; PottsToolkit
  must not silently choose a deterministic, stochastic, jump, or hybrid interpretation.
- MethodOfLines uses `symbolic_discretize` to produce a native symbolic discretization, followed by
  real MTK compilation and a standard numerical problem. A checked grid map relates discretized
  coordinates to the Potts lattice; name matching or array-shape coincidence is not a grid map.
- ModelingToolkitStandardLibrary components use their native systems, connectors, initialization,
  events, and observations through public MTK behavior.

### Time and coupling

The canonical Potts clock is the nonnegative integer completed-MCS count. MTK clock constructs do
not replace it. The pinned MTK hybrid-clock surface can represent discrete clocks, but it is not a
general simplify/compile/solve authority and remains experimental upstream; G5H therefore does not
make it a product foundation.

Each time-dependent native component declares a positive physical duration per MCS. For constant
duration `delta_t`, completed MCS `m` corresponds to physical component time
`t_origin + m * delta_t`. Variable schedules require their own explicit accepted policy and cannot
silently redefine MCS.

The default coupled step is the named `CPMThenComponents` Lie split:

1. the CPM consumes component outputs settled at the start of the MCS;
2. CorePotts executes one MCS into an inactive candidate bank and produces a staged lifecycle
   receipt without changing the public completed-MCS state;
3. PottsToolkit applies that staged receipt to inactive component pools;
4. native components advance across their declared physical interval using settled CPM outputs;
   and
5. one status-gated commit publishes the Core and component candidate banks, receipt, outputs, and
   new completed-MCS count together.

Any Core or component failure before step 5 leaves the prior published boundary unchanged and
terminalizes the default integrator. This all-or-nothing publication rule is distinct from the Lie
split's computational order; it does not make components execute before the CPM.

Any components-first, Strang, subcycled, event-interrupted, or multirate policy has a distinct
semantic identity and must state read snapshots, publication order, failure atomicity, and restart
behavior. No policy invokes an external numerical solver from a copy-attempt or device proposal
kernel.

### Dynamic per-cell components

Per-cell dynamics compile once per component schema, not once per live cell and never in response
to a runtime lifecycle event. Runtime storage uses fixed-capacity, structure-of-arrays component
pools indexed by CorePotts slot and generation, with explicit active masks.

CorePotts publishes a compact generation-safe lifecycle receipt for created, removed, divided, and
transitioned cells. PottsToolkit applies the declared component-state policy in one transaction:
initialize, delete, copy, reset, transform, split, or reject. A stale generation cannot read,
write, restore, or inherit a new cell's component state.

Relationship and cell lifecycle transactions remain CorePotts semantic authority. G5H does not
generalize them into an arbitrary graph-rewrite engine.

### Ensembles, batching, and Dagger

A collection of independent complete Potts trajectories uses the SciML
`EnsembleProblem` interface, including `prob_func`, `output_func`, reductions, deterministic
replica/repeat identity, and supported serial, threaded, or distributed execution.

Per-cell vectorization is a different optimization: it advances columns within one trajectory's
component pool. Documentation, APIs, capability reports, and benchmarks must not call this an
ensemble or imply that SciML ensemble support automatically makes per-cell dynamics GPU capable.

Dagger may be evaluated as an optional coarse scheduler for independent trajectories, coarse
component islands, or distributed reductions. The G5H evidence must record an adopt-or-defer
decision based on measured benefit and semantic fit. Dagger must not own MCS order, coupling
visibility, lifecycle commit, randomness, or checkpoint meaning, and deferring it does not block
G6.

### Capability profiles

Capability is a structured conjunction, not a boolean. At minimum it identifies:

```text
algorithm x backend/device x dimension/topology x scalar policy x component scope
x native problem family x lifecycle features x checkpoint/replay class x observation/event mode
```

Execution admission requires one evidence row covering the whole conjunction. Interface-only and
compile-only maturity never authorize execution. Experimental functional rows require explicit
opt-in; checkpoint/exact-continuation requests require replay qualification.

The sequential CPU profile is the complete semantic reference. Checkerboard CPU and GPU are
distinct stochastic algorithms with their own guarantees; they are not accelerations that preserve
sequential trajectories or kinetics.

Global and per-cell component scopes target both CPU and GPU as first-class capability classes.
Promotion of either scope requires a CPU reference and at least one real GPU witness for the
explicitly admitted subset. This does not require arbitrary MTK systems to compile on a GPU.
Unsupported callbacks, allocations, solver algorithms, events, scalar types, or component
combinations reject during preflight. No host fallback, scalar device indexing, or hidden data
transfer can satisfy a GPU profile.

Other GPU vendors report `Unsupported` until they run the same applicable evidence. The absence of
one optional vendor does not block G5H after a real portable GPU profile qualifies.

## Preservation and consolidation rules

G5H begins with a disposition for every current public name, major internal protocol, test family,
and working feature: `keep`, `merge`, `replace`, `remove`, or `defer`. A behavior marked `keep`,
`merge`, or `replace` requires a black-box preservation witness before its old authority is removed.
Unpublished compatibility alone is not a preservation reason.

The following current strengths are presumed `keep` unless the G5H-0 review accepts a more precise
replacement:

- semantic counter-based RNG addressing and replica/repeat identity;
- sequential CPU scientific authority;
- checkerboard coloring, claims, deterministic commit, and backend settlement;
- immutable compiled CorePotts plans;
- generation-stamped cell identity and transactional lifecycle;
- relationship transactions and bounded stores;
- tracker deltas and independent recomputation;
- failure atomicity and settled publication boundaries;
- symbolic indexing, remake, observation, and checkpoint intent;
- no-fallback backend reporting; and
- MakiePotts consumption of explicit public host observations.

G5H removes accidental duplication rather than merely renaming it. The target has:

- one semantic traversal and one normalized source record per declaration;
- one resolved lifecycle IR shared by compilation and inspection;
- one compiled model schema, parameter schema, state/output schema, and capability lattice;
- one kernel-safe acceptance law used by sequential and checkerboard execution;
- one runtime-materialization path per admitted profile;
- one logical snapshot/checkpoint codec with explicit replay classes; and
- a narrow CorePotts public runtime API, with compiler and backend SPIs explicitly separated.

False surfaces are not preserved. These include generic hooks production execution rejects,
symbol-valued configuration languages around one implementation, algorithm names without their
claimed numerical methods, observation stages with no runtime effect, lossy external-system
assimilation, decorative equations, and support flags unsupported by executable evidence.

Source-line reduction is a useful result but not an exit criterion. Correctness, cohesion,
compile latency, allocations, memory use, and runtime performance are measured directly.

## Authoritative execution order

Only the following order may open G6:

```text
cleared G5/R2
    -> G5H-0 -> R2H-A
    -> G5H-1 -> G5H-2 -> G5H-3 -> R2H-B
    -> G5H-4 -> G5H-5 -> R2H-C
    -> LocalWorksets LW-0 through LW-R1 -> LW-4 disposition
    -> explicit owner send-off -> G6
```

Work may move within one gate to keep an implementation coherent. Dependent work pauses on a
failed exit or review and returns to the earliest incorrect artifact.

### G5H-0 — Authority, baseline, and preservation freeze

Deliver:

- this authority chain reflected in the specification index, decision index, roadmap, and all
  superseded-in-part documents;
- an honest temporary public documentation landing page, with legacy API pages removed from the
  active build but retained as draft source where useful;
- one living `design/hardening/g5h-control.md` created when implementation begins;
- a current source, test, API, dependency, feature, and duplication inventory;
- the `keep`/`merge`/`replace`/`remove`/`defer` disposition and preservation witness map;
- explicit package ownership, lifecycle, capability, time, and public-lifecycle decisions; and
- a verified Decision 0043 clean baseline with no active retired-package dependency or link.

Exit requires no unresolved material architecture choice and an exact candidate commit.

#### R2H-A — Authority and preservation review

An independent reviewer checks the supersession map, preservation coverage, MTK assumptions,
package ownership, capability profiles, scope, and recoverability of every destructive cleanup.
G5H-1 must not begin with a P0 or P1 finding. Every P2 has an owning later gate and explicit
disposition.

### G5H-1 — Semantic and CorePotts consolidation

Deliver:

- one shared acceptance implementation and sequential/checkerboard parity tests for shared laws;
- a single source traversal, normalized fact representation, lifecycle IR, schema family,
  capability lattice, initialization path, and checkpoint codec;
- generation-safe lifecycle receipts and bulk component-state lifecycle operations;
- an honest profile matrix for sequential CPU, checkerboard CPU, and checkerboard GPU;
- lifecycle, settlement, checkpoint, and rejection tests owned by CorePotts itself;
- compiler and backend SPI quarantine and a materially narrower stable CorePotts API; and
- measured disposition of whole-state rollback copies, lifecycle workspace memory, relationship
  algorithm scaling, and other whole-cell memory risks.

Exit requires all retained G0--G5 scientific witnesses touched by consolidation to pass. CorePotts
must load and test without PottsToolkit, MTK, SciML solvers, or GPU-vendor packages.

### G5H-2 — Cohesive pure-Potts authoring and SciML lifecycle

Deliver:

- one obvious functional and `@named` construction path for a small Potts model;
- predictable `compose`, `extend`, namespacing, completion, diagnostics, and inspection;
- `complete` and structural `mtkcompile` with idempotence and provenance tests; the pure-Potts
  `ModelingToolkitBase.mtkcompile(::PottsSystem)` method lives in base PottsToolkit and works in a
  fresh process without loading full ModelingToolkit;
- the scheduled-`PottsSystem -> PottsProblem -> init/solve -> solution` public spine;
- late algorithm/backend/scalar specialization with no public executable requirement;
- standard `remake`, SymbolicIndexingInterface, observation, saving, callback, termination,
  checkpoint, and restore behavior within the admitted Potts contract; and
- one authoritative public API inventory, with no compatibility aliases or duplicate constructors.

Exit requires a compact fresh-process pure-Potts authoring-through-solution witness and
source-located failure examples for every major invalid construction family.

### G5H-3 — Native global MTK integration

Deliver:

- an explicit native component declaration and typed IO/coupling map;
- preservation of native system hierarchy, initialization, events, observed values, and SII;
- real upstream `mtkcompile` and standard problem/integrator construction for native islands;
- the integer-MCS/physical-time map and explicit `CPMThenComponents` publication order;
- one genuinely coupled global MTK component whose output changes CPM-observable behavior and whose
  input changes native dynamics;
- representative ODE and DAE/event coverage where supported;
- a ModelingToolkitStandardLibrary component witness;
- a Catalyst adapter witness with explicit semantic conversion; and
- checkpoint/restart, remake, error propagation, cancellation, and failure-atomicity tests across
  the coupled boundary.

Exit rejects all lossy `EquationComponent`-style assimilation and proves CorePotts remains MTK
free.

#### R2H-B — Cohesion and real-MTK architecture review

An independent reviewer evaluates G5H-1 through G5H-3 as one vertical slice: semantic ownership,
CorePotts consolidation, public authoring, MTK structural compilation, native component retention,
time and coupling order, initialization/events, SII, checkpoints, and preservation witnesses.

G5H-4 must not begin with a P0 or P1 finding. A P2 affecting an interface consumed by G5H-4 must
be fixed before clearance; another P2 may be assigned explicitly to G5H-5.

### G5H-4 — Dynamic components, fields, ensembles, and backend profiles

Deliver:

- compile-once fixed-capacity per-cell component pools with active and generation masks;
- first-class create, delete, divide, and transition behavior across component state, observations,
  checkpoints, and symbolic indexing;
- serial and vectorized CPU component execution and an explicitly bounded real-GPU batched profile;
- native prescribed/discrete fields and a MethodOfLines extension using `symbolic_discretize`, real
  MTK compilation, and an explicit grid map;
- whole-trajectory `EnsembleProblem` support with serial, threaded, and distributed witnesses;
- a clear separation between SciML ensembles and per-cell batching;
- complete algorithm/backend/scalar/component/lifecycle/checkpoint capability reports; and
- a measured Dagger adopt-or-defer record.

Every advertised CPU and GPU profile requires applicable correctness, no-fallback, replay,
allocation, synchronization, and performance evidence. Unsupported combinations must be tested
rejections.

### G5H-5 — Product qualification and documentation rebuild

Deliver:

- executable final-interface documentation for each stable authoring and execution concept;
- complete serial Wortel and Merks authoring/integration programs running through the final public
  API in the strict docs build and on the target Mac, without claiming G7 paper-source scientific
  qualification;
- fresh-process package, extension load-order, integration, documentation, Aqua, ExplicitImports,
  stale-name, private-upstream, and dependency-boundary checks;
- preservation closure for every retained feature and removal proof for every retired public path;
- compile-time, allocation, runtime-throughput, checkpoint, component-pool, and lifecycle-memory
  measurements against the G5H-0 baseline; and
- an exact support and limitations matrix with no claim derived only from compilation success.

The full manual is rebuilt here rather than mechanically translating legacy `PottsModel` pages.
There is no migration guide for unpublished APIs.

#### R2H-C — Hardening exit review

An independent reviewer evaluates the final black-box authoring experience, dynamic identity and
lifecycle, native fields and MethodOfLines, ensembles and batching, CPU/GPU claims, docs/API
agreement, package quality, performance, and every preservation disposition.

Exit requires:

- zero P0 findings;
- zero P1 findings;
- zero unresolved in-scope P2 findings;
- every preservation row marked preserved, replaced with a passing witness, removed by accepted
  disposition, or explicitly owner-deferred;
- no unsupported public claim; and
- an exact cleared checkpoint followed by the accepted LocalWorksets implementation/review route
  and explicit owner authorization to begin G6.

R2H-C does not replace the G7 scientific review or G9 terminal review. It qualifies cohesion and
integration before the public surface is frozen.

## Shared review and recovery protocol

All three G5H reviews reuse the existing compiler-construction review policy:

- the reviewer did not author the reviewed slice and works read-only from a fresh context;
- the review names the exact commit, environment, specifications, diff, and commands;
- each blocking finding cites the normative clause, smallest code location, reproducer or static
  proof, violated invariant, affected preservation row, and earliest repair gate;
- P0 and P1 findings block progression;
- P2 means a concrete in-scope correctness, evidence, diagnostics, maintainability, or product
  defect, not a reviewer preference;
- P3 is optional polish or future scope and cannot silently expand G5H; and
- no copied-log ledger, calendar freshness ritual, or duplicate scientific oracle is created.

At R2H-A and R2H-B, a P2 may be carried only with an explicit owner and closing gate. R2H-C permits
no unresolved in-scope P2. A later change to an R2H-A authority reopens all three reviews; a change
to the G5H-1--G5H-3 architecture boundary reopens R2H-B and R2H-C.

Recovery repairs or intentionally reverts a bounded coherent slice at the earliest owning gate.
It never authorizes a destructive reset, weaker semantics, host fallback, or an unreviewed special
case.

There is intentionally no independent review after every subgate. G5H-1 through G5H-3 form one
end-to-end architecture proof, and G5H-4 becomes truthfully reviewable only with G5H-5's models,
documentation, and backend evidence.

## G6 handoff

After the cleared R2H-C checkpoint, the accepted
[LocalWorksets Implementation and Review Gate](localworksets-v1-implementation-gate.md) inserts
LW-0 through LW-R1 and an LW-4 disposition. G6 begins only after that route and explicit owner
send-off. Its job is to stabilize, classify, and
freeze the already functionally complete public integration spine, not finish missing G5H behavior
or redesign it. The scheduled `PottsSystem`, `PottsProblem`, algorithms, integrator, solution,
checkpoint, inspection, and SII lifecycle must already pass at G5H exit. Any executable lowering
type remains private unless a later accepted decision proves a public need.

## Research basis

The design follows public ecosystem contracts rather than private upstream representations:

- [ModelingToolkit model building and `mtkcompile`](https://docs.sciml.ai/ModelingToolkit/stable/API/model_building/)
- [ModelingToolkit composition](https://docs.sciml.ai/ModelingToolkit/stable/basics/Composition/)
- [ModelingToolkit events](https://docs.sciml.ai/ModelingToolkit/stable/basics/Events/)
- [ModelingToolkit initialization](https://docs.sciml.ai/ModelingToolkit/stable/tutorials/initialization/)
- [SymbolicIndexingInterface](https://docs.sciml.ai/SymbolicIndexingInterface/stable/complete_sii/)
- [SciML ensemble interface](https://docs.sciml.ai/SciMLBase/stable/interfaces/Ensembles/)
- [MethodOfLines discretizer interface](https://docs.sciml.ai/MethodOfLines/stable/)
- [Catalyst system conversion API](https://docs.sciml.ai/Catalyst/stable/api/core_api/)

The tracked integration project accepts ModelingToolkit major version `11`; its manifest is
intentionally ignored. Each gate records the exact resolved upstream versions in its review
evidence (the G5H-0 local run resolved `11.37.1`). A new resolution requires rerunning applicable
public-interface tests and cannot silently change this contract.
