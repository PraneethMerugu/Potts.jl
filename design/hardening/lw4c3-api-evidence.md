# LW-4C3 public API reconciliation

Status: implementation complete; final all-layer CPU/Metal qualification and
fresh LW-R2 review remain required before freeze.

Baseline authority: commit `44389fc` and
`design/hardening/lw4b-b5-final-hashes.sha256`.

This slice changes authoring and construction only. It does not reopen the
accepted LocalWorksets charter, lifecycle, output semantics, execution-family
algebra, provider ordering, or qualification boundary.

## Frozen mental model

| Question | Decision | Reason |
|---|---|---|
| Package | `LocalWorksets.jl` | The declaration describes bounded local work over explicit connectivity; the name does not imply a solver or domain. |
| Declaration | `LocalWork` from `localwork` | Reads as ordinary Julia and names what a user authors, not a compiler artifact. |
| Reusable validation result | `WorkPlan` from `plan(work, topology; backend)` | Owns validated immutable topology, backend selection, lowering and evidence, but no concrete storage/workspace. |
| Concrete attachment | `PreparedWork` from `prepare(workplan, storage; workspace)` | Fixes arrays, submission schema, workspace, provider lane, leases and failure state. `workspace` may be omitted for one-time exact package allocation. |
| One submission | `WorkEvent` from `run!` | A cumulative lane-tail receipt, not a transferable native event or a scheduler object. Visibility follows `wait(event)`. |
| Output semantics | `independent`, `combined`, `resolved` | Names the scientific distinction directly. Compiler family names remain private. |
| Ordered stages | `sequence(a, b)` and `sequence((a, b))` | Both spellings are exact desugarings. Ordering and visibility use sequential launches on one KernelAbstractions lane with no intermediate host wait. |
| Evidence | `LocalWorksets.inspect` | Public but intentionally unexported to avoid collisions with domain-package inspection functions; non-synchronizing complete facts plus author-oriented groups derived from those same facts. Short `show` output is for orientation only. |

Rejected alternatives remain rejected: `Policy`, `WorkContract`, `Direct`,
`Settled`, `Seq`, `Certificate`, `compile_workset`, `bind`, `enqueue!`, opaque
execution callbacks, native event transfer and a LocalWorksets scheduler.

## Level 1 — concise single-output work

The accepted convenience is:

```julia
work = localwork(
    Scale(Int32(3)),
    1:3,
    :scaled => independent(:route; value_type = Int32);
    read = (source = :source,),
)
```

The operation returns one bare `emit(...)` or `candidate(...)`. A private,
concrete, isbits `_SingleOutputOperation{Name}` wraps that result in the exact
one-port named tuple consumed by Level 2. There is no separate lowering,
validation path, workspace rule, backend hook, or lifecycle.

The port name in the conventional Julia `Pair` is a setup-time value, so the
outer convenience constructor is not promised as an inference boundary. The
stored wrapper and its kernel invocation are fully concrete and inferred.
Both the wrapper method and the external user callback method are frozen at
`prepare`; a more-specific method installed afterward rejects before launch
without poisoning. The real-Metal conformance runner compiles and executes the
same wrapper on device.

## Level 2 — named heterogeneous work

The existing package-author surface is retained:

```julia
work = localwork(operation, items;
    read = (extension = :edge_extension,),
    outputs = (
        edge_state = independent(:edge_route; value_type = UInt32),
        force = combined(:vertex_route;
            value_type = Float32,
            maximum = 2,
            combine = deterministic(+, Float32(0))),
        fracture = resolved(:cell_route;
            value_type = UInt32,
            maximum = 1,
            empty = UInt32(0),
            rank = (type = Int32, order = :max,
                    lower = Int32(0), upper = Int32(10)),
            tie_break = (type = UInt32, order = :min)),
    ),
)
```

The operation returns a `NamedTuple` with exactly those port names. Each port
may emit its fixed bounded number of lanes. Routes, destination counts and
resolved semantic identities are explicit in `topology(work; ...)`. False
conditional lanes mean no emission. Independent coverage, combined identity,
resolved empty result, total rank and canonical tie-break rules remain exactly
the qualified LW-R2B contract.

The complete lattice-spring witness exercises independent edge publication,
deterministic or fast vertex force combination and cell fracture resolution in
one operation. It now uses automatic workspace and the accepted lifecycle;
its declaration remains fully explicit.

## Extension API

An external package supplies a concrete callable operation. The standalone API
test defines such an operation in a separate module, plans and prepares it
without modifying LocalWorksets, executes it, and confirms central capability
and provider evidence.

The semantic declarations are intentionally closed evidence inputs rather than
open execution hooks. An external combination-law subtype or a more-specific
capability/lowering/provider/compiler method cannot authorize execution. New
operation/type/backend/address-space combinations require centrally reviewed
qualification. This preserves static dispatch and device compilation while
preventing arbitrary host code, allocation, synchronization, launch schedules,
or fallback from entering through an extension.

## Construction and binding

The one public lifecycle is:

```julia
workplan = plan(work, topology; backend)
prepared = prepare(workplan, storage; workspace)
event = run!(prepared, submission)
wait(event)
```

`topology(work; epoch, routes, destination_counts, semantic_ids=(;))` derives
only the declared item count. It cannot infer away empty destinations or epoch
ownership. Static `storage` is an ordinary named tuple. `value_slot` and
`storage_slot` freeze submission-time scalar/storage contracts. Preparation
diagnostics identify missing/extra names, access and alias violations.

When `workspace` is omitted, `prepare` allocates the exact centrally validated
scratch once through `KernelAbstractions.allocate`; `lease_capacity` selects the
bounded number of unwaited submissions. `inspect(prepared)` reports package or
caller ownership, allocation class, algorithmic bytes and concrete
backend/device/layout/identity facts. `plan`, `run!` and `inspect` never allocate
algorithmic workspace.

## Event and ordering semantics

`WorkEvent` contains a `PreparedWork` reference and cumulative submission
serial. It deliberately does not pretend that KernelAbstractions exposes a
portable per-launch event. `run!` appends launches asynchronously where the
backend supports it. Sequential launches rely on KernelAbstractions 0.9
implicit ordering. `wait` performs exactly one portable
`KernelAbstractions.synchronize(backend)`, drains the actual cumulative prefix
and releases all covered leases. LocalWorksets implements no queue, stream,
command buffer, scheduler or intermediate barrier.

## Public surface and discovery

Exported public types:

- `LocalWork`, `WorkPlan`, `PreparedWork`, `WorkEvent`,
  `LocalWorkValidationError`

Exported public functions:

- `localwork`, `topology`, `plan`, `prepare`, `run!`, `sequence`
- `independent`, `combined`, `resolved`, `deterministic`, `fast`
- `emit`, `candidate`, `masked`, `value_slot`, `storage_slot`

`inspect` is public and documented but deliberately unexported. The complete
Metal integration runner loads PottsToolkit and LocalWorksets together; when
both exported their distinct `inspect` functions, ordinary unqualified
PottsToolkit inspection became ambiguous. Qualified `LocalWorksets.inspect`
preserves discovery and avoids contaminating a domain package's namespace.
`inspect(workplan/prepared/event)` derives `summary`, `outputs`, `execution`,
`memory`, and `qualification` groups from the same flat evidence fields used
by validation and lowering; it does not maintain a second evidence graph.

Validated lifecycle failures expose stable `stage`, `contract`, `port`,
`binding`, `workspace_leaf`, `expected`, `actual`, and `hint` fields through
`LocalWorkValidationError`. Tests assert fields rather than complete prose;
`showerror` stays concise. Constructor misuse before a declaration exists
continues to use Julia's conventional `ArgumentError`.

`masked` remains a documented compatibility constructor for the isolated
legacy resolved descriptor; new generic authoring uses conditional `emit` or
`candidate`. The legacy descriptor, flat topology, workspace, and four-launch
lowering are closed to new consumers and migrate as one unit only after generic
semantic/lifetime/inspection and CPU/Metal performance parity plus a warned
compatibility release. Compiler nodes, lowering types, provider lanes,
evidence builders, workspace specifications and construction tokens remain
private.

Semantic `propertynames` expose declaration fields on `LocalWork`,
`work/topology/backend` on `WorkPlan`, binding inputs on `PreparedWork`, and
only `serial` on `WorkEvent`. Runtime, lowering, provider and ownership internals
remain discoverable through `inspect`, not accidental field completion.

## Runnable authoring evidence

| Consumer | Complete declaration and lifecycle | Difficult semantics shown |
|---|---|---|
| D2Q9 stream/collide | `test/localworksets_witnesses/lbm_d2q9.jl` | nine independent permutation lanes; submission-bound source; exact coverage |
| lattice spring | `test/localworksets_witnesses/lattice_spring.jl` | heterogeneous ports; two emissions; qualified floating combination; resolved fracture |
| matrix-free FEM | `test/localworksets_witnesses/matrix_free_fem.jl` | four element-node emissions; deterministic fold; an empty node receives identity |
| z-buffer | `test/localworksets_witnesses/zbuffer.jl` | bounded total rank; canonical identity tie; false mask; explicit empty pixel |
| external operation | `lib/LocalWorksets/test/test_api.jl` | external module, Level 1 wrapper, complete lifecycle and central qualification |
| CorePotts arbitration | `lib/CorePotts/src/execution/checkerboard_program.jl` plus `lib/CorePotts/test/test_program_v1_localworksets_vertical.jl` | conjunctive old/new-owner claims below Core-owned RNG, acceptance, commit, settlement and checkpoints |

The first four execute together through
`test/localworksets_witnesses/runtests.jl`. Replacing `Array` and CPU backend
with qualified device storage/backend is the only LocalWorksets-side change;
the complete Metal runner mirrors them and separately executes the Level 1
wrapper. Backend-neutral source does not imply untested CUDA/ROCm support.

Package-level authoring documentation is in `lib/LocalWorksets/README.md`.

## Focused evidence on the current candidate

- standalone LocalWorksets suite: pass, including Aqua and ambiguity checks;
- Level 1 direct, combined and resolved CPU executions: pass;
- external module operation through central lifecycle: pass;
- hostile post-prepare replacement of the wrapped user callback: rejected
  before launch, with zero submissions and no poison;
- five cross-domain CPU rows after canonical-construction conversion: pass;
- automatic workspace and Level 2 construction on real Metal: pass from C2;
- Level 1 real-Metal compilation/execution: added to the complete final Metal
  qualification runner and not claimed until that runner passes.

Exact assertion totals, hashes, all-layer qualification and reviewer ballots
belong to the final LW-4C evidence record after the candidate stops changing.

## Remaining concerns before LW-R2

| Class | Concern | Disposition |
|---|---|---|
| Architectural | none identified | Architecture stays closed; LW-R2 may veto only a concrete contradiction. |
| Usability | `Pair{Symbol,...}` constructor result depends on the port-name value | Accepted as cold setup syntax; stored wrapper and kernel call are concrete. Reconsider only if real package-author use demonstrates a material problem. |
| Usability | common `inspect` name collides with PottsToolkit when exported | Resolved by keeping it public/documented but unexported; use `LocalWorksets.inspect`. |
| Usability | legacy `masked` is less cohesive than conditional emissions | Keep compatibility, document it as legacy-only, admit no new use. |
| Implementation | retained four-launch legacy resolved adapter duplicates generic obligations | Keep isolated until a source-compatible replacement proves all named-family/topology/workspace/inspection obligations; no new adoption. |
| Usability | complete inspection was compiler-oriented when read flat | Resolved additively with derived author groups; complete flat machine evidence remains authoritative. |
| Usability | message-only lifecycle failures were brittle to test and hard to recover from | Stable public diagnostic fields now cover high-value routes/results/bindings/aliases/submissions/workspace/capability/topology/poison paths; rare internal invariants may be enriched after freeze. |
| Implementation | final exact CPU/Metal timing and footprint evidence pending | Blocks LW-R2. |

## API-freeze checklist

- [x] one lifecycle spelling and explicit topology ownership;
- [x] concise single-output sugar desugars to named ports;
- [x] heterogeneous named ports retain all accepted semantics;
- [x] bare floating-point combination remains rejected;
- [x] external operations work without source edits;
- [x] external declarations cannot self-authorize execution;
- [x] concise wrapper method substitution is guarded;
- [x] topology/storage/workspace construction is materially smaller;
- [x] event, synchronization and implicit-order semantics are explicit;
- [x] public/private names, docstrings, property discovery, `show` and
  `inspect` are tested;
- [x] complete CPU authoring examples are runnable;
- [ ] complete final standalone/Core/root/CPU/Metal qualification;
- [ ] exact hashes and footprint disposition;
- [ ] fresh independent LW-R2 memos, contradiction round and ballots.
