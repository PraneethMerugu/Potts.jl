# LW-4B Bounded General Mechanism Implementation Matrix

Date: 2026-08-11

Status: LW-4B complete and LW-R2B passed; LW-4C open; LW-5 and G6 closed

Authority:

- [LocalWorksets V1 normative contract](../../spec/localworksets-v1.md)
- [Post-LW-R1 extraction and adoption roadmap](../../spec/localworksets-post-lwr1-roadmap.md)
- [LW-R2A standalone extraction review](lwr2a-localworksets-extraction-review.md)

## Purpose and boundary

This matrix closes the implementation uncertainty for LW-4B. It defines the smallest executable
mechanism set that can satisfy the accepted independent, combined, resolved, heterogeneous,
bounded-emission and ordered-composition requirements without turning LocalWorksets into a solver,
scheduler or domain framework.

LW-4B may add provisional Level-2 constructors needed to exercise real mechanisms. Their behavior
is evidence, not a public-surface freeze. LW-4C must reconcile names, exports, conveniences,
docstrings and the external-extension experience after all witnesses run. The lifecycle remains
`localwork -> plan -> prepare -> run! -> wait`; no second lifecycle or opaque executor is admitted.

## Execution-family algebra

Only two internal families are admitted:

1. **Direct** — planning proves disjoint publication. One apply launch evaluates each selected
   item once and writes independent outputs through fixed routes.
2. **Buffered** — one apply launch evaluates each selected item once and emits into bounded fixed
   record slots or qualified atomic destinations. Package-owned ordered phases then combine or
   resolve and publish. Every phase, launch, record and byte is fixed by `WorkPlan`.

Heterogeneous work is one buffered plan when any port conflicts; independent ports may publish in
the common apply launch. Deterministic combination, fast atomic combination and resolution are
semantic port laws, not user-selectable launch implementations. Central lowering chooses the
phases. Collective, frontier, iterative, segmented-runtime and arbitrary multi-pass families remain
absent.

## One external operation protocol

A package-author operation is a concrete isbits callable with the device signature:

```julia
result = operation(item::Int32, reads::NamedTuple, values::NamedTuple)
```

- `reads` contains only arrays named by `LocalWork.read` and bound through validated storage.
- `values` contains only scalar submission slots, in prepared schema order; storage slots remain in
  `reads`/bindings rather than being smuggled into scalar values.
- the result is a `NamedTuple` with exactly the declared output-port names;
- each port returns one fixed emission or an `NTuple{K}` matching its declared maximum;
- `emit(value, when=true)` is used by independent/combined ports;
- `candidate(rank, value, when=true)` is used by resolved ports;
- false `when` means no emission;
- destination keys and canonical semantic identities come from validated topology routes, never
  from an unvalidated dynamic callback; and
- LocalWorksets calls the operation once per selected item, even for heterogeneous outputs.

Ordinary functions are accepted on CPU when their exact call is inferred. GPU admission requires
an isbits function/functor and successful real device compilation. Captured arrays, dynamic
containers, host callbacks and opaque launch hooks reject during planning/preparation.

Scientific purity and correctness of the operation remain the caller/domain responsibility.
LocalWorksets proves only the declared access, route, bound, conflict and publication contract.

## Topology and route contract

The bounded LW-4B topology profile is an immutable `NamedTuple` exposing:

```julia
(;
    epoch::UInt64,
    item_count::Int,
    routes = (; port_name = route_matrix, ...),
    destination_counts = (; port_name = count, ...),
    semantic_ids = (; resolved_port = identity_matrix, ...),
)
```

The central lifecycle accepts a topology object by interface, but LW-4B does not claim that an
arbitrary external topology struct is supported by this generic lowering. A Julian external
topology adapter/protocol is an LW-4C authoring question, not a reason to add opaque dispatch or
to overstate the qualified profile here.

For a port with maximum `K`, its route is a `K x item_count` integer matrix. Positive entries are
one-based destinations; zero is a statically absent lane. Resolved ports additionally provide a
same-shaped concrete integer semantic-identity matrix. Planning canonicalizes records by
`(item, local_slot)`, validates every bound and identity, and precomputes immutable host segment
offsets/order for deterministic combination. Preparation copies/adapts route evidence exactly once
and reports its transfer bytes. Warm `run!` performs no topology transfer or workspace growth.

Topology shape, routes, destination domains, semantic identities or conflict footprints require a
new epoch/plan. Storage values on unchanged routes do not.

## Provisional mechanism declarations

The following constructors are provisional Level-2 spellings to be reconciled, not renamed by
preference, in LW-4C:

| Constructor/value | Exact LW-4B meaning |
|---|---|
| `independent(route; value_type, maximum=1, coverage=:all)` | disjoint fixed-route publication; `:all` proves exactly one writer per destination and forbids runtime masking/active truncation, while `:partial` proves at most one and preserves non-emitted destinations |
| `deterministic(op, identity)` | explicit canonical `(item, slot)` fold; no atomic/arrival-order implementation |
| `fast(op, identity)` | explicit qualified relaxed combination; initial implementation recognizes atomic `+` only and reports its reproducibility limits |
| `combined(route; value_type, maximum=1, combine)` | every destination publishes the declared identity when it receives no contribution; bare `+` or an unqualified callable rejects |
| `resolved(route; value_type, maximum, empty, rank, tie_break)` | total rank plus topology-owned canonical semantic identity; every empty destination publishes `empty` |
| `emit(value, when=true)` | one independent/combined fixed record lane |
| `candidate(rank, value, when=true)` | one resolved fixed record lane; identity is not dynamically supplied |

Initial qualified combination profiles are canonical or fast addition for `Int32`, `UInt32` and
`Float32`. Initial generic resolved profiles use `Int32` or `UInt32` rank, `UInt32` semantic
identity and concrete isbits scalar values supported by the reviewed provider. Float64 is rejected
on the reviewed Metal row. Extension-defined laws remain declarative but non-executable until
LW-4C defines the central qualification protocol.

## Type and function implementation mapping

| ID | Required implementation | Owning tests |
|---|---|---|
| T01 | `_AbstractOutputDeclaration` subtypes for independent, combined and generic resolved ports | A01–A05, H01–H05 |
| T02 | concrete emission/candidate values with Bool validity and exact scalar types | A06–A08, D01–D04 |
| T03 | concrete deterministic/fast combination law values; bare callable is not a law | A09–A12, C01–C08 |
| T04 | one generic direct lowering and one generic buffered lowering | L01–L08, P01–P08 |
| T05 | immutable per-port route/segment evidence and adapted device route values | R01–R10, G01–G08 |
| T06 | bounded per-port workspace description and prepared runtime | W01–W10, G03–G08 |
| F01 | `independent` validates route name, concrete isbits value type, positive maximum and coverage | A01–A03 |
| F02 | `deterministic`/`fast` validate explicit identity/op/type and create inspectable laws | A09–A12, C01–C08 |
| F03 | `combined` validates a qualified law and never accepts raw `+` | A04–A05, C01–C08 |
| F04 | generic `resolved` validates total rank, empty, identity type and bound | A04–A05, S01–S08 |
| F05 | `emit`/`candidate` retain exact value/rank/validity without allocation | A06–A08 |
| F06 | `localwork` accepts concrete callable structs and rejects noncallable scalar/data values during admission | A13–A16, G01 |
| F07 | `plan` validates every port/route/coverage/conflict/segment/capability fact centrally | R01–R10, S01–S08 |
| F08 | `prepare` validates operation call shape, storage/access/alias, workspace and device adaptation | P01–P08, G01–G08 |
| F09 | `run!` invokes the operation exactly once per selected item and appends only inspected phases | D01–D04, H01–H05, O01–O06 |
| F10 | `inspect` reports every port law, route, record bound, phase, launch, workspace, transfer, qualification and determinism fact | I01–I10 |

### Lifecycle, preparation and inspection rows

| ID | Executable requirement |
|---|---|
| L01 | `localwork` remains a declaration; it neither launches nor owns concrete storage |
| L02 | `plan(work, topology; backend)` centrally validates and selects only the internal direct or buffered family |
| L03 | a mixed-port plan uses one buffered plan and one operation application phase, rather than one evaluation per port |
| L04 | every prepared phase, launch and record bound is fixed and inspectable before `run!` |
| L05 | external operation, law, capability and lowering methods cannot self-authorize execution |
| L06 | `sequence` lowers to the ordered concatenation of admitted stage phases and launch counts |
| L07 | lowering introduces no queue, scheduler, native event, hidden host callback or arbitrary multi-pass hook |
| L08 | the specialized z-buffer and conjunctive lowerings remain bounded parity oracles, not extra public execution families |
| P01 | `prepare(workplan, storage; workspace)` fixes logical reads/outputs to exact concrete arrays |
| P02 | preparation validates backend/device, eltype, rank, shape, strides, access and alias contracts |
| P03 | preparation adapts immutable topology evidence once and reports its exact transfer bytes |
| P04 | caller-provided workspace is validated for exact named buffers, types, capacities, backend/device and aliasing |
| P05 | static prepared arrays cannot be substituted; submission-bound arrays receive the same bounded validation |
| P06 | stale topology identity, epoch or structural fingerprint rejects before launch |
| P07 | prepared lease capacity and retained arguments/workspace cover the complete queued prefix |
| P08 | warm execution reuses prepared topology, workspace and compiled lowering without growth |
| I01 | declaration inspection reports items, logical reads, named output laws and active-selection facts |
| I02 | plan inspection reports internal family, fixed phases and exact launch count |
| I03 | each port reports route, destination count, maximum, coverage/law, publication and determinism |
| I04 | plan inspection reports per-port and total workspace byte formulas |
| I05 | plan inspection reports topology-transfer bytes separately from algorithmic workspace |
| I06 | plan inspection reports exact qualified backend/type/operation/address-space evidence |
| I07 | prepared inspection reports array bindings, workspace identities, lease capacity and poison state |
| I08 | event/prepared inspection reports cumulative submitted/drained prefixes and wait count |
| I09 | fast numerical ports deny replay/bitwise guarantees; canonical ports report only their proved ordering |
| I10 | inspection does not report CUDA/ROCm, cross-backend bitwise identity or performance parity without evidence |

## Acceptance rows

### Declaration and authoring laws

| ID | Executable requirement |
|---|---|
| A01 | one independent port with `coverage=:all` accepts an exact permutation route |
| A02 | missing or duplicate destination rejects for full coverage; any duplicate rejects for partial coverage |
| A03 | full coverage with active selection, zero route or potentially false emission rejects; partial coverage preserves non-emitted output |
| A04 | output names and operation result names/types/tuple arities match exactly |
| A05 | heterogeneous names preserve source-independent NamedTuple meaning and stable inspection order |
| A06 | single-emission sugar is identical to a one-tuple emission |
| A07 | false emission is no record, not identity/empty; zero topology route is statically absent |
| A08 | emitted value/rank types must exactly match the port declaration |
| A09 | deterministic and fast combination are distinct concrete types and inspection facts |
| A10 | bare `combine=+`, unspecified identity, abstract value type and unsupported operation reject |
| A11 | deterministic floating addition reports canonical item/slot order and no stronger cross-backend claim than measured |
| A12 | fast floating addition reports qualified atomic arrival order and no bitwise/replay guarantee |
| A13 | do-block, function and concrete callable-functor construction are equivalent |
| A14 | captured arrays, non-isbits GPU functors and wrong call signatures reject before launch |
| A15 | common single-output declarations require no internal lowering/workspace/capability type |
| A16 | no declaration field is decorative: mutation of each field changes validation, lowering or inspection |

### Routing, bounds and workspace

| ID | Executable requirement |
|---|---|
| R01 | every route is concrete integer `K x item_count`; wrong rank/shape/type rejects |
| R02 | destinations are zero or within the exact per-port domain; negative/out-of-range rejects |
| R03 | generic resolved semantic IDs match route shape/type and are unique per destination among possible records |
| R04 | deterministic segment order is canonical `(item, slot)`, independent of route storage order and workgroup size |
| R05 | topology identity/epoch/fingerprint includes all route, domain, semantic-ID and segment evidence |
| R06 | route mutation/stale epoch rejects before launch; value-only read changes reuse the plan |
| R07 | `maximum` equals result tuple arity and record capacity `item_count * maximum` without overflow |
| R08 | masked/zero lanes consume fixed slots but emit no record; overflow cannot occur silently |
| R09 | route device-copy bytes occur only at prepare and are exact in inspection |
| R10 | mixed output domains and arities coexist without padding one port to another's semantic domain |
| W01 | direct independent work requires zero algorithmic workspace |
| W02 | deterministic combination requires exactly value plus validity records and segment evidence |
| W03 | fast atomic combination requires no record workspace beyond declared output initialization |
| W04 | resolved output requires exact rank/identity plus bounded candidate value/validity records |
| W05 | heterogeneous workspace is the named per-port sum with no hidden pool or allocation |
| W06 | caller-provided one-short/wrong-type/wrong-device/aliased workspace rejects |
| W07 | prepared workspace identities and byte formulas remain stable across warm submissions |
| W08 | active selection does not resize routes, records, workspace or launch geometry |
| W09 | warm `run!` has no topology transfer or algorithmic workspace growth |
| W10 | plan/preparation inspection agrees with actually indexed arrays and record slots |

### Independent, combined and resolved semantics

| ID | Executable requirement |
|---|---|
| D01 | direct independent permutation exactly matches a direct reference with one launch |
| D02 | partial independent masking preserves destinations receiving no emission |
| D03 | active selection is distinct from per-lane masking and does not evaluate inactive items |
| D04 | a post-launch direct failure may leave partial publication and poisons the shared provider scope honestly |
| C01 | deterministic integer sum matches canonical serial reference and publishes identity for empty destinations |
| C02 | deterministic Float32 sum matches the bitwise canonical serial fold; fixed record indices and segment order make the fold independent of apply scheduling, while no cross-backend floating claim is made |
| C03 | mixed FEM arities remain one combined port with canonical global `(item, slot)` order |
| C04 | fast Int32/UInt32/Float32 addition matches a tolerance/exact reference appropriate to the type |
| C05 | fast floating inspection denies scheduling/workgroup/cross-backend bitwise invariance |
| C06 | deterministic and fast paths have fixed, distinct launch/workspace reports |
| C07 | unsupported backend x type x op x address-space tuples fail closed centrally |
| C08 | external methods cannot self-authorize a new combine law or atomic capability |
| S01 | generic resolved selection publishes explicit empty for destinations with no candidate |
| S02 | min/max rank and canonical minimum semantic identity match a serial reference |
| S03 | false/zero lanes make no claim; total-rank bounds reject invalid dynamic ranks through backend failure/poison |
| S04 | generic one-/multi-destination resolution matches existing z-buffer and conjunctive oracles where profiles overlap |
| S05 | operation-supplied dynamic identity is impossible; topology duplicate identity rejects at planning |
| S06 | value publication is unique after rank/identity resolution and independent of arrival/workgroup order |
| S07 | generic resolved types/layouts are limited to exact centrally qualified profiles |
| S08 | old specialized lowerings remain available as parity oracles until LW-R2B accepts consolidation/removal disposition |

### Heterogeneous execution and ordering

| ID | Executable requirement |
|---|---|
| H01 | one spring operation emits independent edge state, two combined force contributions and one resolved fracture candidate |
| H02 | the operation invocation counter proves exactly one call per active item on CPU; device IR/behavior proves no per-port reevaluation on Metal |
| H03 | each port owns its route, destination domain, law, workspace and determinism inspection |
| H04 | invalid cross-port alias, duplicate output name, result mismatch or unsupported law rejects before launch |
| H05 | failure/publication facts state which direct ports may be partially visible and which buffered ports publish only after their phase |
| O01 | `sequence` accepts generic and legacy stages on one backend/lane in declared order |
| O02 | later stages read prior output only after provider-ordered publication launch |
| O03 | no intermediate host wait, fabricated event or scheduler node appears |
| O04 | one final `wait` establishes host visibility for the cumulative prefix |
| O05 | incompatible backend/topology/item domains and read-before-visible order reject |
| O06 | launch count equals the sum of inspected stage phases and warm allocation remains bounded |

### JuliaGPU, admission and performance

| ID | Executable requirement |
|---|---|
| G01 | operation, emissions, declarations, routes and kernel arguments are concrete/isbits or Adapt-compatible; device compilation has no dynamic dispatch |
| G02 | source contains no Metal/CUDA/AMDGPU branch, native queue/stream/event or scalar indexing path |
| G03 | all phases rely on KA implicit ordering and LocalWorksets still contains exactly one portable KA backend synchronize |
| G04 | `run!` remains asynchronous; exactly one final wait is used in each complete witness |
| G05 | invalid operation code/type/law/device rejects before partial execution where compile validation can prove it |
| G06 | launch count, route transfer and workspace equal inspection; compiler-cache entries and measured warm host allocations are recorded separately |
| G07 | direct-kernel parity meets the frozen 1.05 paired-bootstrap upper-95 bound on CPU and reviewed real Metal for representative direct and buffered mechanisms |
| G08 | source portability makes no CUDA/ROCm qualification claim; qualification remains CPU plus exact reviewed M1/Metal fingerprint |

## Durable witness matrix

Every witness lives outside `LocalWorksets/src`, imports only public LocalWorksets bindings, runs a
separate reference, exercises invalid declarations, inspects the full lifecycle and performs one
final wait.

| ID | Durable owner | Mechanisms proved | CPU | Metal |
|---|---|---|---|---|
| X01 | `test/localworksets_witnesses/lbm_d2q9.jl` | external functor; exclusive/permutation independent stream/collide | required | required |
| X02 | `test/localworksets_witnesses/lattice_spring.jl` | heterogeneous independent edge state, deterministic/fast force sum, resolved fracture | required | required |
| X03 | `test/localworksets_witnesses/matrix_free_fem.jl` | mixed-arity deterministic element scatter and empty identity | required | required |
| X04 | standalone z-buffer witness | generic resolved overlap with preserved specialized oracle | required | required |
| X05 | downstream CorePotts vertical | two-key claims remain domain-owned and match generic bounded arbitration where comparable | required | required |

These files are mechanism evidence, not production LBM/FEM/spring solvers. Domain names are vetoed
from package production source.

## Consolidation hold B0

Before adding the generic output family:

1. move only proven shared slot/binding facts, device copy, kernel factory, capability query and
   method-owner validation into a package-owned mechanism-support file;
2. retain exact specialized resolved/conjunctive behavior and hashes as oracles;
3. do not create an abstract executor hierarchy or callback registry;
4. rerun standalone, CorePotts, CPU parity and real Metal; and
5. reject the consolidation if launch count, allocation, cache, poison or throughput changes.

This satisfies the LW-R2A disposition that duplicated lowering/world-validation machinery be
consolidated before a third family without using cleanup as permission to redesign the lifecycle.

## Ordered holds

1. **B0 — common-mechanism consolidation**: no new behavior; exact parity required.
2. **B1 — declaration/route/operation protocol**: constructors, topology validation and negative
   tests only; no executable lowering.
3. **B2 — direct independent family**: D2Q9 CPU/Metal plus direct parity.
4. **B3 — combined laws**: deterministic then fast, each qualified separately; FEM witness.
5. **B4 — generic buffered heterogeneous/resolved family**: spring/z-buffer witnesses; old
   specialized paths remain oracles.
6. **B5 — complete witness and downstream qualification**: all X01–X05, full suites, hashes and
   quantitative evidence.
7. **LW-R2B — fresh mechanism committee**: no LW-4C code begins before clearance.

Any wrong result, unbounded/hidden work, unauthorized execution, false determinism or partial
buffered publication is P0. Any missing row, domain/vendor leak, bypassable admission, hidden
wait/allocation/transfer, false backend claim or >1.05 unexplained upper bound is P1. Maintainability
or diagnostics debt is P2 and requires an explicit owner/disposition before LW-R2B.

## Candidate row disposition and test ownership

Every acceptance ID is written explicitly below; no range inherits a result. `Pass` means that the
exact candidate has an executable assertion, durable witness, structural source check or recorded
measurement. It does not mean LW-R2B has voted to accept the mechanism.

| IDs | Disposition | Exact owner/evidence |
|---|---|---|
| T01, T02, T03 | Pass | `test_api.jl` bounded vocabulary/construction; `test_generic.jl` heterogeneous and combined-law testsets |
| T04, T05, T06 | Pass | `test_generic.jl`; `test_mechanisms.jl`; all four durable CPU/Metal witnesses; plan/prepared inspection assertions |
| F01, F02, F03, F04, F05 | Pass | `test_api.jl` declaration validation; `test_generic.jl` direct, combined, heterogeneous and bounded-emission testsets |
| F06, F07, F08 | Pass | `test_api.jl`; `test_admission.jl`; `test_runtime.jl`; `test_generic.jl` preparation-integrity cases; witness invalid-topology/workspace cases |
| F09, F10 | Pass | `test_generic.jl` operation counter and full inspection; witness launch/wait/workspace/transfer reports |
| L01, L02, L03, L04 | Pass | `test_api.jl`; `test_generic.jl`; plan inspection in D2Q9, spring, FEM and z-buffer witnesses |
| L05, L06, L07, L08 | Pass | hostile admission testsets; `test_mechanisms.jl` ordered stages and legacy parity; source synchronization/vendor scans |
| P01, P02, P03, P04 | Pass | `test_mechanisms.jl` logical storage; `test_generic.jl` workspace/transfer; FEM one-short rejection |
| P05, P06, P07, P08 | Pass | `test_runtime.jl` freshness/capacity/ownership and generated submissions; `test_generic.jl` exact concrete submission storage, operation-method freeze and immutable workspace-structure cases; queued real-Metal/Core vertical evidence |
| I01, I02, I03, I04, I05 | Pass | API, generic and mechanism inspection assertions; durable witness reports |
| I06, I07, I08, I09, I10 | Pass | hostile capability/admission tests; runtime poison/lifetime tests; CPU/Metal determinism reports |
| A01, A02, A03 | Pass | `test_generic.jl` direct independent and partial bounded multi-emission testsets; D2Q9 invalid route |
| A04, A05, A06, A07, A08 | Pass | `test_api.jl` construction; `test_generic.jl` heterogeneous result matching; z-buffer masked/empty result |
| A09, A10, A11, A12 | Pass | `test_generic.jl` deterministic/fast combined laws; spring deterministic/fast witnesses |
| A13, A14, A15, A16 | Pass | `test_api.jl`; hostile source/admission tests; real-Metal external-surface rejection |
| R01, R02, R03, R04, R05 | Pass | generic route/semantic-ID validation and fingerprint assertions; spring/z-buffer duplicate-ID rejection |
| R06, R07, R08, R09, R10 | Pass | generic exact-UInt64 epoch, stale-route, checked Int32 capacity, bounded multi-emission and mixed-port tests; all witness transfer/arity reports |
| W01, W02, W03, W04, W05 | Pass | D2Q9 zero-workspace; spring/FEM/z-buffer exact per-port workspace reports |
| W06, W07, W08, W09, W10 | Pass | generic one-short/wrong schema/alias tests; runtime reuse; witness warm runs and inspection agreement |
| D01, D02, D03, D04 | Pass | generic direct/partial/active tests; D2Q9 oracle; central failure/poison tests and direct publication inspection |
| C01, C02, C03, C04 | Pass | combined-law bitwise/exact tests; deterministic/fast spring; mixed-arity FEM serial oracle |
| C05, C06, C07, C08 | Pass | determinism/phase inspection; unsupported profile rejection; hostile external capability/law tests |
| S01, S02, S03, S04 | Pass | generic heterogeneous/resolved tests; z-buffer witness; preserved specialized z/conjunctive oracle tests |
| S05, S06, S07, S08 | Pass | topology identity validation; generic qualification rejection; specialized parity suites retained |
| H01, H02, H03, H04, H05 | Pass | spring operation/witness; CPU invocation counter; common apply-kernel structure plus real-Metal behavior; invalid cross-port tests |
| O01, O02, O03, O04, O05, O06 | Pass | `test_mechanisms.jl` ordered stages; provider implicit-order source check; one-final-wait and summed-launch assertions |
| G01, G02, G03, G04 | Pass | real-Metal device compilation; production vendor scan; exactly one KA synchronize; all witnesses use one final wait |
| G05, G06, G07, G08 | Pass | hostile prelaunch tests; inspection/measurement record; 1,000-sample paired-bootstrap CPU/Metal performance; qualification metadata |
| X01 | Pass | `test/localworksets_witnesses/lbm_d2q9.jl`, CPU and real Metal |
| X02 | Pass | `test/localworksets_witnesses/lattice_spring.jl`, deterministic and fast CPU/Metal modes |
| X03 | Pass | `test/localworksets_witnesses/matrix_free_fem.jl`, CPU and real Metal |
| X04 | Pass | `test/localworksets_witnesses/zbuffer.jl` plus standalone specialized z-buffer oracle, CPU and real Metal |
| X05 | Pass | `test_program_v1_localworksets_vertical.jl` plus full CorePotts and real-Metal queued checkerboard qualification; conjunctive ownership retained |

Two qualifications prevent overreading this table. H02's device result is structural compilation and
behavioral evidence, not a GPU side-effect counter. D04 proves honest poison and possible direct
partial visibility; the suite does not depend on a particular partially written array after a
backend failure.

## Required final evidence

- exact per-file hashes and old/new common-helper provenance;
- every T/F/A/R/W/D/C/S/H/O/G/X row disposition;
- standalone, CorePotts and authoritative root test totals;
- complete CPU and real-Metal witness commands;
- direct/reference results, launch counts, waits, transfers, workspace, warm allocations,
  specialization/cache counts and paired-bootstrap performance;
- hostile external-law/capability/operation tests;
- preserved checkpoint continuation, RNG mismatch rejection and Core scientific ownership; and
- an independent LW-R2B ballot on numerical laws, cross-domain generality, JuliaGPU behavior,
  invalid combinations, false unification and readiness for LW-4C.

LW-R2B clearance means the bounded mechanisms are correct. It does not freeze their spelling or
authorize LW-5. Only LW-4C plus the final LW-R2 public-surface review can finish LW-4.

## Preservation and complexity discipline

LocalWorksets is preserved because unrelated LBM, spring, FEM, resolved-selection and CorePotts
witnesses demonstrate a real layer above KernelAbstractions. That is not permission to equate
implementation size with success:

- KernelAbstractions owns portable kernel execution and implicit ordering;
- LocalWorksets owns validated local connectivity, conflict semantics, bounded lowering,
  workspace, lifetime and inspection; and
- domain packages own physics, clocks, RNG, solver behavior, transactions and checkpoints.

Every declaration type, validation layer, specialized lowering and evidence object must keep an
explicit consumer or safety/performance justification. The single-resolved specialization is
provisionally performance-earned; generic, specialized resolved and conjunctive duplication remains
debt for LW-4C. No additional execution family is admitted without two unrelated concrete
consumers. LW-5 succeeds only if real CorePotts/PottsToolkit operations become materially smaller,
clearer and easier to inspect; large per-operation adapters are evidence that the abstraction or
authoring surface must be simplified before expansion.

## Current implementation disposition

An implemented mechanism is not a passed LW-4B gate until B5 and LW-R2B finish.

| Hold | Current disposition | Exact boundary |
|---|---|---|
| B0 | complete | Shared capability, binding, device-copy and kernel-factory support consolidated with frozen parity. |
| B1 | complete | Provisional declarations, qualified laws, concrete emissions/candidates, callable functors, inspection and negative authoring tests pass. |
| B2 | mechanism complete | One-launch direct independent lowering; topology-proved disjoint routes; bounded multi-emission; full/partial coverage; active truncation; zero algorithmic workspace. CPU and reviewed M1/Metal execution pass. |
| B3 | mechanism complete | Canonical addition uses caller-owned records and topology segments; explicit fast addition uses centrally qualified atomics. CPU canonical Int32/Float32 and reviewed M1/Metal fast Float32 execution pass. |
| B4 | mechanism complete | One operation emits named heterogeneous independent, combined and resolved ports. Routes and semantic identities are topology-owned; empty and false-lane laws are explicit. CPU and reviewed M1/Metal execution pass. |
| B5 | corrected exact-source complete | The first exact candidate was vetoed; focused ballots then retained specialized-port completeness and resolved-mask/conjunctive-empty semantic P1s. The final corrected candidate closes operation-method substitution, mutable workspace-structure substitution, structural `PreparedWork` reassignment, pre-sync hostile-method wait stranding, generic and specialized checked-ABI gaps, late law rejection, truthful complete per-port inspection, generic submission-bound reads and evidence-gate defects. Standalone 511/511, CorePotts 17,462/17,462, root 2,232/2,232, all CPU witnesses/performance and the complete real-Metal runner pass. Root wall time is excluded because timing is not gate evidence; the earlier extended run specifically reflected laptop travel. |
| LW-R2B | passed | The decisive committee ballot on the exact manifest is unanimous: P0=0, P1=0, bounded correctness/honest narrowness/future room pass, and no extraction obstruction. The retained P2 is nonblocking consolidation/authoring debt; Metal z-buffer headroom remains monitored. |
| LW-4C | open | Implementation-backed consolidation and Julian/JuliaGPU authoring reconciliation may begin. |
| LW-R2 | closed | No API freeze, LW-5 adoption or G6 work begins before the fresh LW-R2 committee passes the LW-4C candidate. |

The historical B1-B4 candidate is recorded in `lw4b-b1-b4-mechanism-evidence.md`; the exact B5
candidate is recorded in `lw4b-b5-qualification-evidence.md`. No CUDA/ROCm runtime support is
claimed.
