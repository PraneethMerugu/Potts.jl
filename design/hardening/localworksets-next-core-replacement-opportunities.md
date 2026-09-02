# LocalWorksets: Next Core-Replacement Opportunities

Date: 2026-08-16

Status: Accepted research and active phased implementation specification; generic-law Gates 0,
1A, 2A, 3A, 4A, and 5A passed on 2026-08-16; timed performance noninferiority remains explicitly
unclaimed; corresponding Core-adoption gates were not attempted; final generic-law consolidation
review passed with P0=0, P1=0, P2=0, and P3=0

## Question

What additional capabilities can LocalWorksets acquire, while remaining a library for bounded local
computation, that would let CorePotts delete more bespoke execution machinery later?

The committee's answer is **yes**, but the useful frontier is narrower than “move more CPM code into
LocalWorksets.” The next work should deepen the existing axes of address selection, conflict
resolution, and publication. It should not add lifecycle, CPM, transaction, scheduler, RNG, or
scientific-state concepts.

The highest-confidence additions are:

1. one-launch fusion of the existing single-resolved lowering for one destination;
2. preserve-seeded deterministic combination, initially including qualified `UInt64` addition;
3. one efficient private keyed substrate shared by independent, combined, and resolved work;
4. runtime-keyed independent publication with domain and uniqueness validation; and
5. fixed named multi-port keyed composition behind one validation gate.

These form a coherent path. The first two expose immediate reduction seams, subject to the record,
gate, and launch qualifications below. The third makes the general address law credible for
adoption, but its implementation follows the fourth's semantic definition so the substrate is
built only once. The fourth completes the ordinary conflict-law product. The fifth is the minimum
composition needed for meaningful later K07 simplification; it remains nontransactional and
CorePotts retains the scientific commit boundary.

Stable bounded compaction/permutation is the strongest subsequent research candidate, but it has a
higher admission bar and should not be bundled into the first edit.

## Committee method

Three independent passes examined the current LocalWorksets contract, implementation, backend
lowerings, and remaining CorePotts execution machinery:

- a Julian architecture pass looked for the smallest compositional laws and API shapes;
- a GPU/backend pass examined launch count, workspace, synchronization, and portable lowering;
- an adversarial semantics pass looked for hidden domain ownership, transaction semantics, and
  abstractions that would merely rename CorePotts code.

The synthesis below includes only candidates that survived those passes. Agreement among reviewers
is not treated as proof: each item still has explicit admission, evidence, and deletion criteria.

## Mission boundary

LocalWorksets owns mechanical facts about a bounded local computation:

- a fixed maximum item and emission domain;
- immutable topology and bounded runtime addresses;
- conflict and canonical-order laws;
- prior-destination publication behavior;
- qualified value layouts and backend operations;
- exact workspace, phases, leases, completion, and failure visibility; and
- inspection of the facts used to validate and lower the work.

It does not own:

- Hamiltonian or biological meaning;
- proposal, acceptance, lifecycle, relationship, or tracker policy;
- RNG streams or semantic identities;
- MCS, event, or scientific-state clocks;
- state-bank selection, rollback, checkpoint, or recovery meaning;
- a general scheduler, task graph, transaction system, or mutable graph framework; or
- CorePotts status meanings and failure-cut policy.

The durable design remains the product:

```text
item selection
    × address source
    × conflict law
    × publication-state law
    × result layout
```

Every recommendation below adds a missing value on one of those axes, or improves the private
lowering of an existing value. None introduces a new domain-shaped execution family.

## Ranked recommendations

### A1. One-launch fusion of the existing single-resolved lowering

#### Law

When a resolved output has exactly one destination, select its canonical winning record and publish
it according to the already-declared empty behavior. The semantic law is unchanged:

- active records compete by the existing rank and tie-break order;
- a record value and its provenance are selected together;
- `on_empty = :preserve` leaves the destination untouched;
- declared replacement-on-empty behavior remains available where already supported; and
- results are invariant to workgroup size and backend scheduling.

#### Design

This is a replacement inside the existing private single-resolved specialization, not a public
mechanism, constructor, or parallel phase family. LocalWorksets already selects
`_PlanApplySingleResolved` followed by `_PlanPublishSingleResolved` for qualified one-port profiles.
For qualified `D == 1` profiles, refactor that two-phase plan into one fused launch and delete the
superseded phases for that profile. The ordinary generic buffered lowering remains for unsupported
profiles; do not add a second singleton family beside the existing one.

A backend may use only one of three proved one-launch strategies:

- a bounded serial device scan;
- a single-workgroup reduction whose item capacity is proved not to exceed the qualified workgroup
  bound; or
- an exactly qualified packed atomic value containing every field needed to identify the winner.

There is no portable grid barrier within a GPU launch, and a rank/identity atomic followed by an
uncoordinated record store is not a valid implementation. The chosen strategy must preserve the
existing canonical winner exactly. The specialization remains an ordinary resolved output carrying
an ordinary scalar or centrally qualified record. It must not accept a host callback for
interpreting a winning status.

The current resolved-record profile is limited to eight fields and sixteen bytes, so it cannot
carry CorePotts `ProgramStatus`. Direct status publication requires a separate, domain-neutral wide
component-record qualification. Such a profile must fix the maximum field count and size, exact
field types, physical scratch/output layout, alignment, and CPU/GPU load/store capabilities. Its
components must derive from one winning record after successful completion. It does not promise an
atomic multi-field store or rollback after provider failure.

The output may also have an explicit read-only publication gate. A closed gate means the operation
is not evaluated and the destination receives zero writes. This mechanical condition permits Core
to preserve sticky failure state without LocalWorksets interpreting that state.

#### Expected deletion

- `_checkerboard_acceptance_status_kernel!` in
  `lib/CorePotts/src/execution/checkerboard_kernels.jl`, only as a one-launch whole-kernel
  replacement after a wide-record profile and Core-open publication gate are qualified;
- `_reduce_lifecycle_planning_status_kernel!` and `_reduce_lifecycle_status_kernel!` in
  `lib/CorePotts/src/execution/lifecycle_backend_kernels.jl`, under the same whole-kernel condition;
  and
- future “first canonical error”, global arg-min, or earliest witness kernels.

CorePotts still constructs and interprets `ProgramStatus`; LocalWorksets only chooses one opaque
qualified record. A compact winner-index result followed by a Core-owned gated status-publication
kernel may be a useful experiment, but it is not CorePotts adoption: the existing reducers already
select and publish in one launch, so the split path deletes no production mechanism.

#### Non-CPM witnesses

- first failing validation record over a batch; and
- global nearest-hit or minimum-cost witness selection.

#### Admission tests

- empty, one-record, all-masked, and many-tie cases;
- record value and provenance derive from the same winner after successful completion;
- preserve-on-empty does not write the destination;
- a closed publication gate neither evaluates records nor writes the destination;
- provider failure retains the existing nontransactional publication semantics;
- canonical equality across CPU and every claimed GPU backend;
- workgroup-size invariance; and
- inspection reports the singleton lowering and exact phase/workspace facts.

### A2. Preserve-seeded deterministic combination

#### Law

A combined output may begin its canonical fold from either its qualified identity or the existing
destination value:

```julia
combined(route; combine = deterministic(+, zero(T)), initial = :identity)
combined(route; combine = deterministic(+, zero(T)), initial = :existing)
```

For `initial = :existing`, destination `d` is defined as:

```text
out[d] = foldl(combine, canonical_emissions_for(d); init = old(out[d]))
```

With no active emission, the destination is preserved. Validation and lowering must prove the
existing output is a legal publication-owned read as well as a write, including alias and lifetime
authority. Every other read/output alias rejects unless the lowering proves that all contribution
evaluation completes before the first destination write. A fused multi-destination implementation
must not let a later item observe an earlier destination's newly published value. There is no hidden
snapshot and no claim of atomicity across multiple destinations.

This adds one publication-state value to the existing combined law. It does not create an
“accumulator,” “counter,” “tracker,” or “report” family.

#### Initial qualification

The first implementation should qualify deterministic `UInt64 + UInt64` with identity `UInt64(0)`
on CPU and every claimed accelerator backend. Existing catalog rows can opt into seeded publication
only after the corresponding load/fold/store path is qualified.

The initial release rejects `fast(...), initial = :existing`. A fast seeded profile is a separate
qualification with explicitly stated numerical and scheduling semantics; deterministic admission
does not imply it.

Small fixed destination counts should receive a fused lowering when it reduces launches without
changing canonical order. This matters for replacing CorePotts report reduction; a four-phase
correctness reference that costs more than the current kernel does not constitute successful
adoption.

#### Expected deletion

- `_checkerboard_report_kernel!` in
  `lib/CorePotts/src/execution/checkerboard_kernels.jl`;
- bespoke “apply delta to existing total” kernels in tracker or lifecycle paths, when their value
  layouts become centrally qualified; and
- small histogram/report accumulation code elsewhere.

The CPM adapter should emit the five report deltas. LocalWorksets owns their deterministic seeded
fold; CorePotts owns what each counter means.

#### Non-CPM witnesses

- incremental bounded histogram updates; and
- repeated finite-element, particle, or graph contribution accumulation into an existing field.

#### Admission tests

- exact identity-versus-existing distinction;
- empty preserves, including under active masks;
- deterministic order under repeated keys;
- integer wraparound behavior where qualified;
- rejection of every other read/output alias unless evaluate-before-publish ordering is proved;
- repeated submissions, overlapping lease rejection, and failure poison behavior; and
- CPU/GPU equality and workgroup-size invariance.

### A3. Optimize the shared runtime-keyed lowering

#### Problem

Before Phase 4, runtime-keyed execution was intentionally a bounded correctness reference. It
materialized every record, validated through a publication gate, and visited the Cartesian product
of destinations and record capacity, giving `O(D × R)` work. Phase 4 replaced that production path
directly with stable `O(R + D)` counting groups; the former algorithm now survives only as pure
test-oracle logic.

#### Recommendation

The implemented optimization froze A4's independent key, uniqueness, coverage, and diagnostic
semantics, then replaced the shared keyed workspace/validation/grouping substrate once across
independent, combined, and resolved profiles. The public API and semantics remain unchanged. The
single package-private stable-grouped strategy provides:

- stable counting groups in `O(R + D)` for every admitted law; and
- immutable canonical-record selectors that preserve independent diagnostics, deterministic folds,
  and resolved rank/value coherence without law-specific execution paths.

The qualified fixed-capacity stable counting profile satisfies these requirements:

- every routed nonzero key is validated before any destination publication;
- invalid input publishes nothing, even if an earlier record was valid;
- deterministic combined records retain canonical item/lane order;
- resolved records retain their existing rank and tie-break law;
- all workspace is planned and leased;
- no device scalar indexing, host count read, host callback, or implicit synchronization occurs;
- after qualified optimized coverage lands, the `O(D × R)` implementation survives only as a pure
  test/reference evaluator, not as a selectable production lowering; unsupported production
  profiles reject at planning rather than silently choosing it; and
- inspection distinguishes implementation choice without changing the public contract.

A validation result produced by a normally completed validation phase is distinct from a provider
failure. Invalid input keeps the gate closed and publishes nothing. A provider or synchronization
failure after work has been queued may leave the partial writes allowed by the inspected phase
schedule, poisons the shared provider scope and affected preparations, releases no lease, and never
reports success.

An implementation may use dense winner state, stable key ordering, or backend-qualified atomics.
Atomics may implement a deterministic combined law only when the exact operation and representation
are proved bitwise order-independent, such as qualified modular integer addition or integer
min/max. Atomic floating-point addition cannot implement canonical deterministic addition.
Resolved atomics must select rank, identity, value, and provenance coherently. These are private
strategies, not public data structures or promises.

#### Expected payoff

This does not immediately delete a named CorePotts kernel. It removes the performance and scale
objection to adopting runtime-keyed publication for ownership scatter, accepted records, tracker
deltas, and later composed commit leaves.

#### Non-CPM witnesses

- particle-to-cell deposition;
- software z-buffer resolution; and
- bounded graph-edge aggregation.

#### Evidence

Measure launch count, workspace bytes, compile/cache behavior, generated kernel characteristics,
and runtime across `(R, D, collision density)`. Correctness must be compared directly with the
reference lowering on CPU and GPU.

### A4. Runtime-keyed independent publication

#### Law

Complete the existing conflict-law product with independent runtime keys:

```julia
independent(runtime_route(D); value_type = T, coverage = :partial)
```

Preserve the existing runtime-route zero sentinel. A record is routed exactly when its conditional
emission is enabled and its key is nonzero. Zero-key records participate in neither uniqueness nor
coverage. Every routed key must lie in `1:D`, and routed keys must be unique. The existing coverage
law extends without a new name:

- `:partial`: untouched destinations preserve their existing values;
- `:all`: routed records form a bijection onto `1:D`; because `D > 0`, an empty routed set fails
  coverage.

Domain and uniqueness validation must complete before any output publication. An invalid nonzero key,
duplicate key, or failed all-coverage check produces no destination writes. The first invalid-key
witness is the minimum canonical `(item, lane)`. The duplicate witness is the lexicographically
minimum pair of canonical record positions sharing a key.

Diagnostics use one total order. Every failure candidate is ordered by
`(failure_class, canonical_port_index, primary_record, secondary_record)`, where failure classes are
`invalid_domain < duplicate_key < incomplete_coverage`, the single-port index is one, absent record
positions use a declared terminal sentinel, and the minimum tuple wins. Mixed-failure tests must
prove the same witness on CPU and GPU.

Normal validation failure keeps the gate closed and produces zero writes. Provider or
synchronization failure after queued execution follows ordinary LocalWorksets semantics: inspected
phase-order partial visibility is permitted, the shared provider scope and affected preparation are
poisoned, no affected lease is released, and the event never reports success.

#### Initial scope

Admit exactly one output and ordinary qualified scalar or record values. Reuse the current runtime
route, emission grammar, validation status, publication gate, workspace authority, and wait-time
error handling. Do not introduce a “scatter” API.

#### Expected deletion

- unique owner/site or accepted-record scatter kernels whose uniqueness is already a CorePotts
  invariant; and
- typed leaf-copy portions of the checkerboard commit path.

It will not replace the whole checkerboard commit kernel by itself: tracker mutation, ownership
meaning, descriptor invalidation, and publication ordering remain Core-owned.

#### Non-CPM witnesses

- permutation scatter for a mesh field; and
- unique particle relocation into a fixed slot table.

#### Admission tests

- first invalid key and first duplicate are reported canonically;
- mixed invalid-domain, duplicate, and coverage failures obey the total diagnostic order;
- no partial publication on any validation failure;
- injected provider failure proves poison, lease retention, non-success, and inspected partial
  visibility for both the reference and optimized keyed paths;
- partial versus all coverage, including an empty all-coverage submission;
- masked/conditional records and stale workspace validity;
- record values remain coherent; and
- CPU/GPU equality, workgroup-size invariance, leases, and inspection.

### A5. Shared-gate multi-port runtime-keyed composition

The existing named-output result shape should admit multiple runtime-keyed independent, combined,
and resolved ports from one operation. This removes the artificial one-output restriction; it does
not introduce a new public noun.

The law is deliberately small:

- one operation returns a fixed named tuple of bounded records;
- every port retains its independently declared address, conflict, empty, and publication law;
- all ports share one validation phase, and every runtime key, uniqueness claim, coverage claim,
  value profile, and alias fact is valid before the first port publishes;
- simultaneous failures use A4's total diagnostic tuple with the plan's canonical inspected port
  index, so the same cross-port witness wins on every backend;
- validation failure on any port produces zero writes on every port;
- successful validation is followed by the plan's canonical inspected port-publication order; and
- workspace, gate state, phase order, and per-port laws remain inspectable.

This is nontransactional publication. A provider failure after publication begins may leave any
already-published prefix or subset permitted by the concrete phase schedule. There is no rollback,
atomic cross-port commit, or scientific success claim; the provider scope and affected preparation
are poisoned, affected leases are not released, and the event never reports success. Consequently,
a CorePotts transaction may adopt A5 only when all expected failures are resolved before publication
and the existing Core failure semantics tolerate provider failure at that cut.

For a K07 experiment, additionally require:

- every dynamic key and evaluator result is validated before the first tracker or state write;
- tracker evaluation observes the complete pre-K07 ownership snapshot;
- no expected failure can occur after the first live write;
- ownership and accepted-copy publication order exactly matches the current Core contract; and
- CorePotts continues to own the scientific transaction boundary.

A5 is promoted because without it A2–A4 merely split the current one-launch commit into multiple
submissions. Its implementation still follows stable A2–A4 single-port semantics, needs two
non-CPM consumers, and must show a smaller or faster lowering than sequencing single-output work.

## Conditional next work

These candidates fit the mission, but should be promoted only after the A-series establishes the
generic laws, backend economics, and any claimed CorePotts deletion.

### B1. Centrally qualified product records for combination

A fixed isbits product can be one logical combined value when one canonical operation combines the
whole product componentwise. This could express tracker moment deltas, multiple report counters, and
FEM vector contributions without separate output machinery.

The value must be centrally qualified by exact layout, component operation, backend, and address
space. Arbitrary user structs and runtime reflection reject. Prefer extending the existing record
qualification machinery over inventing vector-accumulator concepts.

### B2. Stable bounded active permutation

A possible generic law takes a fixed-capacity mask and canonical key/semantic identity and produces:

- a fixed-capacity permutation buffer;
- a device-resident active count; and
- a stated stable order, with unused positions carrying a declared sentinel.

No host read of the active count is required to continue bounded device work. This could replace the
lifecycle mark/scan/compact path and some K06 relationship ordering machinery. Outside CPM it is
useful for sparse particles, active graph edges, contact candidates, and bounded event batches.

This is more than selection and less than scheduling. It should be admitted only with two strong
external witnesses, a compact value grammar, exact stability semantics, fixed capacity, GPU-native
continuation, and net deletion in CorePotts. Do not expose the scan or sort implementation as the
law. Do not let the result become an unbounded stream or dynamic task list.

## Research-only candidates

### Frozen CSR or ragged immutable topology

Immutable bounded offsets and indices fit LocalWorksets topology ownership and could reduce padded
fixed-contact or neighborhood representations. They should wait for evidence that padding cost is a
real limitation in two unrelated applications. Mutable relationships do not belong here.

### Sorted-key segment index

A stable active permutation followed by segment-boundary discovery could produce a fixed-capacity
key-to-range index. It could replace lifecycle owner-to-site sorting/indexing. Initially keep this a
private lowering tool; expose a law only if external graph/particle/FEM consumers need the result
itself.

### Canonical bounded supply allocation

Assigning ordered requests to fixed free slots may serve cell-slot and relationship-edge allocation.
It remains research-only because supply exhaustion and priority policy can easily become domain
scheduling. Any future law must be a small canonical matching rule over fixed buffers.

### Multi-resource footprint arbitration

Generalizing exact two-key conjunctive arbitration to arbitrary bounded resource footprints could
express lifecycle conflict resolution. It is not recommended now. Priority, witness, greedy order,
and maximality are policy-laden; an apparently generic law could silently change scientific
semantics. Reconsider only with exact policy equivalence and convincing unrelated users.

## Existing laws to adopt before adding another API

Some remaining machinery may already be expressible with current capabilities:

- bounded lifecycle candidate enumeration, active masking, and fixed result-record storage may use
  LocalWorksets; evaluator meaning, due/domain/generation checks, Core status construction, and
  scientific failure cuts remain Core-owned, and expected failures returned by a Core callable must
  be Core-owned result/status values rather than exceptions that poison the provider;
- gated typed-leaf publication can often use partial independent outputs plus ordered sequence;
- status/witness selection can use resolved records with preserve-on-empty; and
- small fixed aggregations can use combined outputs once A2 supplies seeded publication.

These should be tested as adoption experiments. If adapters or launch schedules are worse than the
bespoke path, improve an existing lowering rather than naming a new mechanism.

## Explicit rejections

The following do not belong in LocalWorksets:

- a checkerboard, proposal, acceptance, tracker, lifecycle, relationship, status, or Hamiltonian
  execution family;
- a generic transaction, rollback, state-bank, or commit protocol;
- arbitrary callbacks that interpret winner, status, or scientific state;
- ownership of clocks, RNG addressing, event queues, or frontier iteration;
- unbounded streams, dynamic allocation, mutable graphs, or device-discovered launch structure;
- a universal monoid/reducer API without closed backend qualification;
- whole-K06 or whole-K07 replacement as a single law;
- arbitrary N-key arbitration before an exact generic semantic law exists; and
- vendor-specific public APIs or parallel CPU/GPU semantics.

## CorePotts replacement map

| CorePotts machinery | Enabling LocalWorksets work | Replacement expectation |
|---|---|---|
| K04 acceptance-status reduction | A1 fused single-resolved plus gate/wide-record qualification | One-launch whole-kernel replacement only after prerequisites |
| K08 report accumulation | A2 seeded `UInt64` combination | Conditional one-launch replacement with no extra production scratch |
| Lifecycle status reducers | A1 fused single-resolved plus gate/wide-record qualification | One-launch whole-kernel replacement only after prerequisites |
| Tracker delta application | A2 plus B1 product records | Partial replacement; scientific callable remains |
| Runtime-keyed aggregation/winner routing | A3 optimized lowering | Makes adoption viable; no semantic change |
| Unique ownership/accepted scatter leaves | A4 independent runtime keys | Partial replacement after uniqueness proof |
| K07 checkerboard commit | A2–A5 | Production composition only behind shared validation and exact Core cut |
| Lifecycle request packing | B2 stable active permutation | Direct mechanical replacement if admitted |
| Owner-to-site indexing | B2 plus private segment index | Potential replacement after evidence |
| Fixed contacts/topology | frozen CSR research | Conditional; immutable topology only |
| K06 relationship transaction | none wholesale | Core-owned; only mechanical sub-laws may move |

Replacement is judged by deleted production mechanism, not by whether CorePotts can call a new API.
Tests and domain adapters do not count as production deletion, but duplicate lowerings, bridges, and
compatibility shims do count against it.

## Phased implementation and committee gates

### Operating rule

This is a sequence of direct implementation dependencies, not a migration program. Work occurs on
one production design. Within each phase:

- edit the existing declarations, lowering, preparation, execution, inspection, tests, and
  benchmarks in place;
- delete every phase, helper, workspace leaf, kernel, and test made obsolete by the edit;
- do not add deprecation paths, compatibility constructors, feature flags, adapters between old and
  new LocalWorksets APIs, or runtime old/new selectors;
- keep a former production implementation only as a pure test oracle when this plan explicitly
  requires one; and
- do not keep a CorePotts direct kernel beside an adopted LocalWorksets path after the adoption gate
  passes.

The dependency order is:

```text
Phase 0: qualification and baselines
    |
Phase 1: A1 fused single-resolved
    |
Phase 2: A2 preserve-seeded combination
    |
Phase 3: A4 runtime-keyed independent semantics
    |
Phase 4: A3 shared optimized keyed substrate
    |
Phase 5: A5 shared-gate named ports
    |
Phase 6: final consolidation audit
```

A4 precedes A3 intentionally. Independent runtime-key semantics, diagnostics, uniqueness, and
coverage must be fixed before the shared keyed substrate is optimized, so that independent,
combined, and resolved work receive one design rather than two successive keyed architectures.

The estimated focused effort is not a schedule commitment:

| Phase | Scope | Expected effort |
|---|---|---:|
| 0 | Qualification facts and frozen baselines | 2–4 days |
| 1 | A1 fusion, wide records, and general gate | 1–2 weeks |
| 2 | A2 seeded combination and fixed-small fusion | 1–2 weeks |
| 3 | A4 keyed-independent law and reference evidence | 1–2 weeks |
| 4 | A3 optimized shared keyed substrate | 2–4 weeks |
| 5 | A5 shared-gate named ports | 1–3 weeks |
| 6 | Cross-phase consolidation and deletion audit | 2–4 days |

### Committee and decision rule

Every phase ends with one technical review by three independent roles:

- **Julian architecture:** type axes, public surface, lowering/lifecycle count, direct deletions, and
  whether ordinary multiple dispatch and concrete tuples are doing the work;
- **GPU/backend:** CPU and Metal qualification, launch/workspace/transfer behavior, compiler cache,
  failure visibility, and absence of fallback or synchronization; and
- **semantic adversary:** canonical order, aliasing, validation/publication cuts, diagnostics,
  provider failure, and preservation of Core scientific ownership.

The reviewers inspect the actual diff, tests, benchmark evidence, and `inspect` facts. This does not
require meetings, templates, migration ledgers, compatibility suites, or parallel implementations.
Each reviewer returns separate generic-law and Core-adoption verdicts with `PASS`, `NOT ATTEMPTED`,
or concrete P0/P1/P2 findings. Each verdict passes only with no unresolved finding in its own scope;
a generic pass cannot waive an adoption finding, and an adoption pass cannot waive a generic-law
finding. `NOT ATTEMPTED` is valid only when the phase proposes no named Core adoption. Remediation
edits the same design directly and repeats the review; it does not restore an old production path.

Every phase has two distinct verdicts:

1. **Generic-law verdict:** whether the LocalWorksets capability is independently correct, useful,
   Julian, and GPU-qualified.
2. **Core-adoption verdict:** whether a named CorePotts mechanism can be deleted without changing
   its scientific cut or worsening its production architecture.

Passing the generic-law gate never implies passing the Core-adoption gate. If the generic law passes
but adoption fails, retain the Core kernel unchanged and retain LocalWorksets only when its two
non-CPM witnesses justify it independently. A failed adoption does not block the next generic phase.

### Cross-cutting gate G0: laws and failure states

Before implementing each phase, freeze the relevant values of these existing axes:

- canonical item, lane, and port order;
- active, work-gate, and zero-key behavior;
- rank, tie, uniqueness, and coverage order;
- empty-destination and prior-destination behavior;
- validation witness order;
- read, write, read/write, and alias authority;
- validation and publication order; and
- provider-failure visibility.

Buffered and keyed work must retain the inspected logical cut:

```text
centrally qualify declarations and value profiles
    -> prove every bound-storage alias
    -> reject before enqueue and lease acquisition if either fails
    -> evaluate bounded records
    -> validate dynamic record facts
    -> select one canonical diagnostic
    -> open publication gate
    -> publish in inspected order
```

Value-profile and alias failures are host admission failures and never enter the keyed device
diagnostic. Only dynamic domain, uniqueness, and coverage candidates use its declared failure-class
order. Fusion may collapse the device steps into one launch only when it proves the same order
without a GPU grid barrier. Validation and destination publication may not interleave while an
expected validation failure remains discoverable.

Each applicable phase tests four distinct failure cases:

| Case | Destination visibility | Preparation/provider | Leases |
|---|---|---|---|
| Host rejection before enqueue | None | Healthy | None acquired |
| Normally completed device validation failure | Zero writes | Affected preparation invalid under existing validation semantics; provider remains usable | Ordinary `wait`/`waitall(release=...)` law |
| Provider failure before publication | No live output writes; scratch may be partial | Shared scope and affected preparations poisoned | No affected lease released |
| Provider failure after publication opens | Inspected phase prefix/subset may be visible | Shared scope and affected preparations poisoned; never success | No affected lease released |

Expected Core scientific failures are successful provider execution producing Core-owned result or
status values. They are not LocalWorksets validation errors or provider poison.

The canonical keyed diagnostic remains:

```text
(failure_class, canonical_port_index, primary_record, secondary_record)
```

Review includes simultaneous invalid-domain/duplicate, duplicate/coverage, cross-port, and
same-class failures. CPU, Metal, workgroup variants, and optimized/reference evaluators must choose
the same witness.

### Performance and backend gate

Use the repository's existing randomized paired sampling and fixed-seed bootstrap protocol. The
one-sided 95% upper bound for generic LocalWorksets qualification is
`upper95(candidate/current) <= 1.05`. A named Core adoption requires the stricter
`upper95(candidate/direct_Core) <= 1.02` on representative CPU and real-Metal workloads.

All claimed profiles additionally require:

- `Metal.allowscalar(false)` and real-device compilation/execution in the reviewed environment;
- the same public law on CPU and Metal;
- no CPU fallback, host callback, host-discovered device count, device scalar indexing, hidden
  synchronization, or intermediate host wait;
- fixed plan-time launch extents and workspace formulas;
- no warm-path allocation or topology transfer;
- stable compiler-cache identity after warm-up for repeated same-shaped submissions;
- inspected strategy, launch count, phase order, workgroup size, threadgroup bytes, global workspace
  bytes, validation-transfer bytes, and failure visibility; and
- workgroup-size invariance for every strategy that admits multiple workgroup sizes.

A1 status reducers and A2/K08 are mandatory one-launch replacement targets. A split path cannot pass
their Core-adoption gate even if its microbenchmark is fast. A5/K07 may use several queued device
phases because portable validate-all-before-publish semantics cannot assume a grid-wide barrier. It
must add no host synchronization or transfer, delete the direct K07 implementation, and beat current
K07 end-to-end. Any launch, workspace, transfer, or compile-size regression in a non-one-launch Core
leaf requires a predeclared material-improvement bound of
`upper95(candidate/direct_Core) <= 0.95`; it cannot be justified after seeing the samples.

## Phase 0: qualification substrate and frozen baselines

### Direct edits

- Extend central capability facts for qualified `UInt64` global load/store and deterministic
  addition. None of A1–A5 requires a `UInt64` atomic, and no such atomic is admitted without separate
  CPU/Metal evidence.
- Define a domain-neutral wide component-record profile with fixed field-count, byte-size,
  alignment, leaf-type, and component load/store limits. The admitted bound may support a later
  Core status record, but no CorePotts type or status meaning appears in LocalWorksets qualification.
- Freeze the exact grammar for one read-only scalar work gate. The preferred compact Julian shape is
  `localwork(...; when = :execution_open)`: a false same-device `Bool` binding is tested before any
  operation evaluation or write and composes conjunctively with the existing active selector. If
  implementation evidence rejects this shape, resolve it at this gate rather than adding a second
  gating mechanism later.
- Extend inspection with the private-strategy and resource facts required by the performance gate.
- Freeze direct CPU/Metal source, launch, workspace, transfer, compiler-cache, and runtime baselines
  for K04, K08, K07, and each candidate lifecycle reducer before changing them.

### Gate 0 exit

- Capability rows are closed, backend-specific facts rather than user extension hooks.
- Wide-record and scalar-gate rules contain no CPM vocabulary.
- Gate storage is read-only, same-device, leased, nonaliasing with outputs/workspace/topology, and
  visible through inspection.
- Unsupported backend environments reject at planning and never fall back.
- Every later adoption target has a reproducible direct baseline.

Stop if qualification depends on a Core type, host callback, runtime reflection, undocumented Metal
layout, or a public backend/vendor branch.

## Phase 1: A1 one-launch single-resolved fusion

### Direct edits

- Keep public `resolved(...)` unchanged.
- Replace the current `_PlanApplySingleResolved` plus `_PlanPublishSingleResolved` pair with one
  private fused phase for qualified `D == 1` profiles. Delete the superseded phase structs, kernels,
  preparation branches, record scratch leaves, and two-phase inspection assertions in the same edit.
- Keep only the existing generic buffered resolved lowering for unsupported profiles. Do not add a
  second singleton mechanism or selectable fused/reference pair.
- Begin with a portable one-device-thread bounded scan on CPU and Metal: evaluate each selected item
  once, retain the complete `(rank, identity, value, provenance)` winner locally, and publish once.
- Optionally qualify a one-workgroup reduction when its fixed item bound, workgroup size, complete
  winner entry, and threadgroup memory are proved. No cross-workgroup reduction is admissible; a
  rank/identity atomic followed by an uncoordinated value write rejects.
- Apply the Phase 0 scalar gate uniformly before operation evaluation. Closed means zero operation
  calls and zero output writes.
- Add two unrelated witnesses: first failing batch validation and nearest-hit/minimum-cost witness
  selection.

### Generic-law gate 1A

- Exactly one launch and one operation evaluation per selected item.
- Rank, tie, empty, active, gate, and record behavior equal the ordinary resolved law.
- All value fields and provenance derive from the same winner after successful completion.
- Wide-record CPU/Metal ABI and component stores pass without claiming atomic multi-field failure
  behavior.
- No global algorithmic record scratch, host transfer, hidden wait, or grid barrier.
- Inspection reports the one fused phase, strategy, admitted capacity, workspace, and failure law.

### Core-adoption gate 1B

K04 deletes only when one replacement launch:

- consumes the exact K03 dispositions;
- selects the minimum semantic identity among nonfinite and zero-temperature failures;
- carries the correct failure code and identity;
- respects an already-closed Core gate and publishes the exact sticky `ProgramStatus`;
- remains between K03 and K05 and makes the closed gate visible to K05 without synchronization; and
- represents expected acceptance failure as Core status rather than LocalWorksets poison.

Each lifecycle reducer is reviewed separately against its real canonical order. Planning status may
use canonical request position while another reducer uses candidate-array order; the adoption may
not assume that all reducers are semantic-identity minima.

A compact winner followed by a Core publication kernel is a valid experiment but not an adoption:
it adds a launch and deletes no whole reducer. If the wide-record/gate profile cannot replace a whole
Core kernel in one launch, retain that Core kernel unchanged.

### Stop/rework

Stop for a second singleton execution family, grid barrier, record tearing after successful
completion, Core-specific record qualification, extra Core launch, or status-code interpretation in
LocalWorksets.

## Phase 2: A2 preserve-seeded deterministic combination

### Direct edits

- Add only `initial = :identity | :existing` to `combined`; encode the value in
  `_CombinedOutput`'s type, validate it at construction, and include it in inspection, topology/cache
  identity, and determinism evidence.
- Initially reject `fast(...), initial = :existing`.
- Give an existing-seeded output publication-owned read/write authority. The old destination is
  invisible to the operation. Reject every other read/output, output/output, topology/output, and
  workspace/output alias unless the chosen lowering proves complete evaluate-before-publish order.
- In the ordinary deterministic publisher, load each destination seed exactly once and fold records
  in canonical item/lane order. No emission preserves the old destination.
- Qualify deterministic modular `UInt64` addition on CPU and Metal without relying on atomics.
- Add one private bounded-total-destination fused strategy. It must include one combined output with
  `D == 5` and five statically routed lanes so K08 can keep its existing five-element
  `Vector{UInt64}` layout: load all five seeds, evaluate the operation once per item, retain five
  fixed local accumulators, then write the same report array after evaluation. This is not a counter
  or report API.
- Add incremental histogram and finite-element/particle accumulation witnesses.

### Generic-law gate 2A

- Exact equality with
  `foldl(operation, canonical_emissions; init = old(destination))`.
- The old value participates exactly once; empty emission preserves it.
- No later item can observe a destination value published earlier in the same work.
- Dynamic submissions repeat the same alias proof.
- Integer wraparound is explicit; deterministic floating addition never uses unordered atomics.
- CPU/Metal equality, repeated submissions, failure injection, leases, inspection, and zero warm
  allocation pass.

### Core-adoption gate 2B

Delete K08 only if the production-shaped replacement:

- evaluates every disposition exactly once and emits the existing five counter deltas;
- accumulates across checkerboard subrounds into the same MCS report;
- observes the same Core-open gate;
- for every realized checkerboard subround, consumes final dispositions after K07 commit and K06
  accepted-copy publication, updates the already-cleared current-MCS report before the next
  subround or MCS settlement/bank activation, and leaves cumulative-statistics publication
  Core-owned;
- executes in one launch with no additional global workspace or transfer;
- preserves exact CPU/Metal counter and modular-overflow behavior under gate closure, one and
  multiple subrounds; and
- passes the paired performance gate against direct K08.

Core retains counter category meaning and cumulative-statistics publication. If the adapter
duplicates evaluation, adds scratch, or adds a launch, keep K08.

### Stop/rework

Stop for post-write seed loads, deterministic Float atomics, changed item/lane order, empty overwrite,
an accumulator-shaped API, or a separate seeded execution family.

## Phase 3: A4 runtime-keyed independent law

### Direct edits

- Add the ordinary overload
  `independent(runtime_route(D); value_type, maximum = 1, coverage = :all)`; add no `scatter` noun and
  no `:complete` synonym.
- Extend the existing one-port keyed lowering rather than create a second prepared-work type.
- A record is routed exactly when its conditional lane is enabled and its key is nonzero. Zero keys
  participate in neither uniqueness nor coverage.
- Validate every routed key in `1:D`, uniqueness, and `:all` bijection before opening publication.
  `:partial` preserves untouched destinations; empty routed work fails `:all` for `D > 0`.
- Extend the keyed completion status to carry invalid-domain, duplicate, and incomplete-coverage
  witnesses under the total diagnostic tuple.
- Publish exactly the unique record per destination, preserving key/value coherence.
- Add mesh permutation and unique particle-slot witnesses.

The existing bounded production reference machinery may be extended temporarily during this phase
because Phase 4 immediately replaces its mechanics. It is not a second public lifecycle and it may
not survive Phase 4 as a production fallback.

### Generic-law gate 3A

- Zero-key, mask, conditional, partial/all, duplicate, invalid-domain, and empty-all semantics are
  exact on CPU and Metal.
- Duplicate selection is independent of thread schedule and uses the canonical record-pair order.
- Every normal validation failure keeps the gate closed and writes no output.
- Provider-failure injection separately proves the cross-cutting failure matrix.
- Validation uses no host cardinality read, callback, or synchronization.
- Single-output scope remains enforced until A5.

### Core-adoption gate 3B

Adopt only a named scatter leaf whose Core invariant already proves uniqueness and key validity.
If invalidity is an expected scientific outcome, Core must convert it to a Core-owned result/status
before invoking the local work; it may not become keyed validation poison. Record a source and
launch census before deletion. A4 alone does not authorize K07 replacement.

### Stop/rework

Stop for thread-order diagnostics, context-dependent zero meanings, publication before validation,
host-discovered count, expected scientific rejection becoming provider poison, or a scatter-shaped
public API.

## Phase 4: A3 optimized shared keyed substrate

### Entry gate

A4 key, uniqueness, coverage, diagnostic, failure, and publication semantics must have passed Gate
3A. Combined and resolved reference semantics must also be frozen before changing the substrate.

### Direct edits

- Use one private `_KeyedGroupedLowering` parameterized by the port law
  and a qualified strategy. Preserve the one `_LoweredWork` / `_PreparedPipeline` lifecycle.
- Share record materialization, gate, canonical diagnostic, planned workspace, transfer, lease, and
  phase grammar across independent, combined, and resolved work.
- Use one stable grouped-record representation for every law: dense counts, exclusive offsets, and
  a canonical-record permutation. Independent derives first/second witnesses from segment heads;
  resolved retains a coherent immutable-record selector; deterministic combined folds each segment
  in canonical order. This is the dense first/winner equivalent without three production paths.
- Stable ordering is by `(key, canonical_record)`. A fixed-capacity counting, comparison, or radix
  builder is acceptable when its honest complexity and workspace are reported.
  Schedule-independent modular integer operations may later use qualified atomics; deterministic
  floating addition always retains canonical ordering.
- Every strategy allocates or validates only its exact prepare-time formula: common keys, values,
  validity, gate, and diagnostic leaves plus shared grouping scratch. `initial=:existing` alone adds
  a pre-evaluation destination-seed snapshot; resolved alone adds record ranks. Device results never
  resize work, and inspection exposes the selected strategy's exact formula.
- Move the old `O(D × R)` implementation out of production source into a pure test/reference
  evaluator. Delete `_KEYED_REFERENCE_VISIT_LIMIT`, `:runtime_keyed_reference_v1`, the Cartesian
  publisher, and every production fallback selector once optimized coverage handles all currently
  admitted keyed profiles. Unsupported profiles reject during planning.

### Generic-law gate 4A

- Exactly one production keyed workspace/status/gate pipeline exists.
- Optimized and pure-reference results, empty behavior, and canonical diagnostics match for all
  qualified matrix cases.
- Deterministic combined grouping preserves item/lane order; resolved and independent record values
  remain coherent.
- Validation finishes before publication, including under injected materialization, grouping,
  validation, and publication failures.
- Inspection reports the exact strategy, honest complexity, workspace formula, launch schedule,
  transfers, and failure visibility.
- No production profile silently falls back to the oracle; no host cardinality, hidden sync, warm
  allocation, or unbounded compile/workspace growth exists.
- Representative CPU/Metal profiles meet the `1.05` paired noninferiority gate, and the largest
  admitted `(R, D)` cases demonstrate improving scaling over the former Cartesian implementation.

### Core-adoption gate 4B

No Core deletion is required to promote A3. Core scatter or aggregation leaves are separate measured
edits that must name an exact seam, preserve its law, avoid increasing surrounding launches, and
delete more production mechanism than their adapter adds.

### Stop/rework

Stop for a selectable production oracle, divergent diagnostics, weakened validation cut, undeclared
dynamic allocation, Float deterministic atomics, or separate keyed mechanisms per conflict law.

## Phase 5: A5 shared-gate named ports

### Direct edits

- Add no public API. Existing named outputs, `independent`, `combined`, and `resolved` are sufficient.
- Delete the one-output rejection and every `only(...)` assumption in keyed lowering, preparation,
  execution, inspection, and evidence.
- Represent ports as concrete named tuples of declarations and planned workspace. Do not add a
  `_MultiKeyedLowering` or keyed transaction type.
- Evaluate one operation once per item and materialize every bounded port record.
- Keep the generated ABI bounded: admit at most four keyed ports, at most 32 lanes per port, and at
  most 32 lanes summed across ports. Specialize on the concrete port schema and laws, never on
  runtime `N`, `D`, or `R` values.
- Centrally qualify every port's value profile and prove global cross-port aliases before enqueue;
  reject before lease acquisition if either fails.
- Validate only dynamic domain, uniqueness, and coverage facts on device; select one diagnostic tuple;
  then open one shared gate.
- Select diagnostics by the total order `(failure_class, canonical_port_index, primary_record,
  secondary_record)`, with global class priority
  `invalid_domain < duplicate_key < incomplete_coverage`. Store mixed signed/unsigned witnesses as
  raw `UInt32` bits internally and decode through the selected port's planned key type, preserving
  the existing public `actual` tuple.
- Publish in the plan's inspected canonical port order under each port's existing conflict, empty,
  seeded, and publication law. Use three shared launches—initialize, apply, index/validate—followed
  by one monomorphic segment publisher per port, for `3 + P` launches rather than `4P` sequenced
  single-port works.
- Reuse A3's strategies and workspace templates. Share the materialization schedule, gate,
  diagnostic transfer, lane, and lease rather than sequence special keyed plans.
- Before the first write, freeze every evaluator result, seeded value, and read snapshot required by
  the declared publication order.
- Optionally qualify a private bounded one-launch strategy using one device thread or exactly one
  proved workgroup with fixed capacity, fixed threadgroup memory, and workgroup barriers between
  evaluation, validation, and ordered publication. It may serve K07 only when every participating
  thread and record fits that one group; no grid-wide variant is inferred.
- Add two unrelated multi-output particle/mesh, graph, rendering, or FEM witnesses.

Normal validation failure writes no port. Provider failure after publication starts may expose only
the inspected prefix/subset and follows the cross-cutting poison/no-release rule. No rollback,
cross-port atomicity, or transaction claim is made.

### Generic-law gate 5A

- Literally one operation evaluation and one shared validation gate cover all ports.
- No port publishes while another port can still discover an expected failure.
- Mixed-port failures choose the same total diagnostic on CPU, Metal, and all workgroup variants.
- Cross-port aliases, value profiles, and seeded reads are either proved or host-rejected before
  enqueue and never enter the device diagnostic tuple.
- Port order and partial provider-failure visibility are inspectable.
- A5 reuses one A3 keyed substrate and uses `3 + P` launches, shared gate/status/transfer/lease, and
  one operation evaluation instead of `4P` launches and `P` evaluations from sequencing equivalent
  single-port work.
- No transaction, commit, rollback, state-bank, lifecycle, tracker, ownership, or status noun enters
  LocalWorksets.

### Core-adoption gate 5B

K07 may move only when:

- every dynamic key, evaluator result, accepted effect, and expected scientific failure is resolved
  before the first tracker or state write;
- tracker calculations observe the complete pre-K07 ownership snapshot;
- the accepted mask and claim authorization equal the current Core results;
- tracker, ownership, descriptor invalidation, and accepted-copy publication order is
  observationally identical;
- destination-bank selection and final activation remain Core-owned;
- provider failure cannot activate or report success for a partially written bank;
- K08 observes the same committed dispositions and checkpoint/replay identity records the new
  lowering;
- the replacement adds no host synchronization or transfer; a one-launch qualified strategy must
  pass the `1.02` Core noninferiority bound, while a multi-device-phase replacement must pass the
  predeclared `0.95` material-improvement bound; and
- performance, workspace, compile-size, source, and launch censuses show that production deletion
  exceeds the adapter and specialization added.

Delete `_checkerboard_commit_kernel!` and superseded tracker leaf recursion only in the edit that
passes this gate. A partial or slower A5 decomposition does not justify keeping two commit
implementations.

### Stop/rework

Stop if A5 needs rollback, state-bank knowledge, domain interpretation, arbitrary mutating callbacks,
publication before all expected failures close, an imaginary grid-wide barrier, or a slower
multi-launch Core decomposition retained for architectural appearance.

## Phase 6: final consolidation audit

After all five generic phases, the same committee audits the complete result rather than trusting
the sum of earlier reviews.

The final gate requires:

- one public execution lifecycle and one shared keyed production substrate;
- one fused singleton path for qualified profiles and no duplicated singleton phases;
- no selectable production reference lowering, compatibility wrapper, feature flag, or old/new
  LocalWorksets branch;
- a public-surface delta limited to `combined(...; initial = ...)`,
  `independent(runtime_route(...))`, and the Phase 0 domain-neutral scalar work gate if retained;
- two unrelated non-CPM witnesses for every promoted public law;
- CPU and every claimed GPU backend using the same laws and truthful inspected evidence;
- every deleted Core mechanism replaced by an equal scientific oracle with a passing source,
  launch, workspace, compile, transfer, and performance census;
- every retained Core seam identified as scientific policy rather than duplicated mechanics; and
- P0=0, P1=0, and P2=0 in the final architecture, backend, and semantic reviews.

If a condition fails, rework the responsible lowering or withdraw the Core adoption. Do not add a
parallel mechanism to rescue it. B2 stable bounded permutation/compaction remains a separate later
project and is not allowed to expand the scope of A1–A5.

## Decision summary

The most principled route to replacing more CorePotts machinery is not to make LocalWorksets know
more about CPM. It is to complete and accelerate its small algebra of bounded publication:

```text
singleton resolved
    + seeded combined
    + efficient runtime keys
    + validated independent runtime keys
    + shared-gate named ports
```

That work fits the original mission, is broadly useful, and has identifiable deletion targets. A
stable bounded active permutation is likely the next substantial frontier, but should remain a
separate evidence-driven project. Transactions, lifecycle arbitration, mutable relationships, and
scientific commit semantics should stay in CorePotts.

## Implementation gate record

### 2026-08-16 — Gates 0 and 1A

The architecture, GPU/backend, and adversarial-semantics reviewers independently approved the
cross-cutting substrate and fused single-resolved implementation with P0=0, P1=0, and P2=0.

The admitted implementation now has one type-level scalar work gate, centrally qualified scalar
and record capabilities, recursive physical-alias validation, mandatory poison/no-release behavior
after admitted provider failure, and one fused single-resolved kernel path. The fused profile uses
one device thread, one launch, no global algorithmic workspace, no transferred segment arrays, one
gate snapshot before evaluation, and truthful scalar, narrow-record, or StructArray layout evidence.

The complete LocalWorksets CPU test suite passed. Focused real-Metal execution with scalar indexing
disabled passed for scalar and wide-record success cases and for invalid-rank failure. The failure
witness preserved the output, poisoned both preparation and lane, reported one submission and zero
drains, and retained the outstanding lease. No performance result is claimed by this gate record.

Core-adoption Gate 1B was not attempted. K04 remains the direct, tested CorePotts scientific-status
reducer; no deletion or Core adoption is implied by the generic-law approval.

### 2026-08-16 — Gate 2A

After remediation and re-audit, the architecture, GPU/backend, and adversarial-semantics reviewers
independently approved preserve-seeded deterministic combination with P0=0, P1=0, and P2=0.

`combined(...; initial=:existing)` is a type-level publication-state law, initially qualified only
for deterministic modular `UInt64 +`. Seeded output has exact read/write publication authority but
is invisible to the operation. The ordinary fixed-route and runtime-keyed publishers load each
destination seed once, retain canonical record order, and preserve an empty destination. Static,
dynamic, workspace, topology, and cross-binding aliases reject before enqueue.

The private five-lane/five-destination specialization uses one device thread, one launch, zero
algorithmic workspace, no fixed-route transfer, and one pre-evaluation snapshot of all five seeds.
It falls back to the ordinary publisher if the operation explicitly topology-reads that route.
Fused, ordinary seeded, runtime-keyed seeded, and exact per-port initial patterns have distinct
lowering/cache identities and truthful inspection.

The complete LocalWorksets CPU suite passed. Real Metal with scalar indexing disabled passed fused,
ordinary buffered, and runtime-keyed seeded paths, repeated execution, compiler-cache stability,
modular overflow, and isolated fused provider failure. Incremental histogram and particle-to-node
accumulation provide unrelated non-CPM witnesses. No performance result is claimed by this gate.

Core-adoption Gate 2B was not attempted. K08 remains Core-owned and unchanged; the generic-law
approval does not authorize its deletion.

### 2026-08-16 — Gate 3A

After an initial rejecting review and one direct remediation pass, the architecture, GPU/backend,
and adversarial-semantics reviewers independently approved runtime-keyed independent publication
with P0=0, P1=0, and P2=0. The architecture review retained one non-blocking P3 advisory to add a
second durable assertion of helper-derived visit-count equality; both inspection surfaces already
consume the same checked helpers and no correctness discrepancy remains.

`independent(runtime_route(D); coverage=:all|:partial)` now uses the existing one-port keyed
lowering and its four typed phases. Enabled nonzero keys are validated in canonical record order;
diagnostics have the total class order `invalid_domain < duplicate_key < incomplete_coverage`.
Normal validation failure opens no publication gate and writes no destination. Partial coverage
preserves unmatched destinations, while all coverage requires exactly one record for each
destination. The public law adds no scatter noun, host cardinality read, callback, synchronization,
prepared-work family, or backend-specific production branch.

The rejecting review found a real asynchronous-failure defect: a reused record workspace could
retain stale validity until after user code returned, and a record's validity bit was written before
its payload. The accepted implementation clears the entire validity buffer in the existing close
phase, also invalidates each item's fixed lanes before invoking user code, and writes key, value,
and rank before setting `valid=true`. A warm-success then failing-reuse witness on the same prepared
work proves that no stale warm record can publish under provider failure.

Inspection now derives validation visits, publication visits, diagnostic device bytes, host bytes,
completion-transfer bytes, and the separate publication-gate byte from shared checked helpers.
Normative documentation distinguishes fixed-route planning proof from runtime-keyed
prepublication validation and uses the generalized keyed-validation settlement terminology.

The complete LocalWorksets CPU package suite passed; the focused Phase 3 matrix contains 86 passing
assertions. Real Metal with scalar indexing disabled passed Int32 and UInt32 keys, narrow isbits
records, all and partial coverage, zero/disabled/masked records, a closed work gate, empty-all,
canonical two-lane diagnostics, repeated preparation use, stable workspace identities, and stable
compiler-cache cardinality (`40 -> 40`). The warm/failure device witness observed warm output
`(10, 20, 30)` followed by `(100, 82, 300)`, with no stale warm value, preparation and provider-lane
poison, `submitted=2`, `drained=1`, and one retained lease. No performance result is claimed by this
gate record.

Core-adoption Gate 3B was not attempted. K07 remains Core-owned and unchanged; Gate 3A qualifies a
general mechanical law only and authorizes no Core deletion.

### 2026-08-16 — Gate 4A correctness/architecture/backend acceptance

After an initial rejecting review and a direct coherence remediation, the architecture,
GPU/backend, and adversarial-semantics reviewers independently accepted the stable-grouped keyed
substrate with P0=0, P1=0, and P2=0. Architecture and semantics reported P3=0. GPU/backend retained
one explicit P3: timed old-versus-new performance noninferiority and near-envelope skew latency were
not measured, so this record makes no speed or nonregression claim.

The former Cartesian `O(D * R)` production validator/publisher has been deleted. One private
`_KeyedGroupedLowering` and one `_StableGroupedKeyed` strategy now serve independent, combined,
seeded combined, and resolved work through exactly four phases:
`initialize_keyed_workspace`, `apply_keyed_records`, `index_validate_keyed_records`, and
`publish_keyed_segments`. There is no old/new selector, alias, compatibility wrapper, host grouping
path, or production oracle.

The grouping phase constructs `counts::Int32[D]`, exclusive `offsets::Int32[D+1]`, and a stable
`permutation::Int32[R]` on device. Checked work is `2R + 3D` for independent and `2R + 2D` for
combined/resolved; aggregate segment publication visits at most `R` records. Planning, capability
inspection, and workspace inspection consume one shared checked `(law, R, D)` derivation. Resolved
work alone adds ranks; `combined(initial=:existing)` alone adds a `D`-value seed snapshot captured
in the initialization phase before evaluator execution.

The complete LocalWorksets CPU package suite passed on the stable-grouped implementation, including
164 pure-oracle Phase 4 assertions. Real Metal with scalar indexing disabled passed independent,
order-sensitive Float32 combined, repeated seeded UInt64, min/max resolved, packed-record coherence,
empty laws, canonical diagnostics, closed gates, and warm provider failure. A larger `R=512,
D=129` witness reported linear index bound `1282`, exact workspace `7710` bytes, skewed result `512`,
32 sparse live destinations, stable workspace identities, and compiler-cache cardinality `40 ->
40`; the independent matrix remained stable at `48 -> 48`.

The pure Cartesian evaluator exists only in tests. Production source and user-facing diagnostics
contain no reference-lowering identity or stale Cartesian claim. The serial device index builder is
a private throughput seam that may later be replaced directly by a parallel stable builder without
changing laws or creating a fallback.

Core-adoption Gate 4B was not attempted. No CorePotts helper was deleted or redirected by this
generic substrate edit.

### 2026-08-16 — Gate 5A

After two rejecting review passes and direct remediation, the architecture, GPU/backend, and
adversarial-semantics reviewers independently accepted shared-gate named runtime-keyed ports with
P0=0, P1=0, P2=0, and P3=0.

The existing `_KeyedGroupedLowering` now owns up to four canonical named ports and at most 32 total
fixed emission lanes. Runtime item and destination counts remain fields rather than type parameters.
One shared initialization phase, one shared application phase, and one shared grouping/validation
phase precede one name-specialized publisher per port, so the phase count is exactly `3 + P`.
The operation is evaluated once per selected item and materializes all port records. One gate and
one 17-byte status select diagnostics by
`(failure_class, canonical_port_index, primary_record, secondary_record)`; raw `UInt32` witness bits
are decoded through the selected port's planned `Int32` or `UInt32` key type. Normal validation
failure writes no port. Provider failure retains the ordinary nontransactional subset, poison, and
no-release rules.

The accepted CPU matrix contains 128 Phase 5 assertions, including accepted `P=4, sum(K)=32`,
rejected `P=5`, rejected per-port `K=33`, rejected aggregate `sum(K)=33`, same-schema/different-`N`
lowering identity, mixed law and key types, one evaluator invocation per item, global diagnostics,
all-output no-write validation, closed gates, aliases, seeded repeat execution, and warm provider
failure. The focused Phase 3--5 keyed matrix passed 378/378 assertions, and the complete
LocalWorksets package suite passed.

Real Metal with scalar indexing disabled passed the maximum `P=4`, `sum(K)=32` profile through the
same production path. It reported seven launches, 32 compiled lanes, 642 algorithmic workspace
bytes, a 17-byte device/host/completion status, one gate byte, and stable compiler-cache cardinality
`14 -> 14`. Cross-port invalid-domain priority preserved all four output canaries; a closed work
gate preserved every port; warm provider failure republished no stale value, poisoned preparation
and provider lane, reported `submitted=2` and `drained=1`, and retained one lease.

Particle/contact force plus closest-contact resolution and fragment coverage plus front-surface
resolution are two unrelated executable non-CPM consumers. Each uses two runtime-keyed named ports,
a direct domain oracle, five launches, canonical publication order, and a shared no-write validation
failure. Both pass on CPU and on real Metal with scalar indexing disabled.

Gate 5B was not attempted. K07 and its scientific commit, tracker, ownership, bank-activation, and
failure-cut policy remain CorePotts-owned and wired. No Core deletion, Core performance result,
timed A3/A5 speedup, or noninferiority result is claimed by Gate 5A.

### 2026-08-16 — Phase 6 final generic-law consolidation

The first full-tree review rejected consolidation because the A5 domain witnesses and current-state
documentation were incomplete. Direct remediation added the two executable consumers described in
Gate 5A, made both existing non-CPM scalar-gate witnesses exercise open and closed execution,
removed obsolete future/deferred language for implemented seeded and runtime-keyed laws, corrected
the Phase 3 assertion count and keyed workspace-byte evidence, and refreshed the normative status.

On the resulting frozen tree, the architecture, GPU/backend, and adversarial-semantics reviewers
independently accepted consolidation with P0=0, P1=0, P2=0, and P3=0. Their source census found:

- one public `LocalWork -> WorkPlan -> PreparedWork -> WorkEvent` lifecycle backed by one
  `_LoweredWork` and one `_PreparedPipeline` representation;
- one `_KeyedGroupedLowering` with one `_StableGroupedKeyed` strategy for every runtime-keyed
  independent, combined, seeded-combined, resolved, and named-port profile;
- one qualified fused singleton-resolved phase and one qualified fused five-destination seeded phase,
  with deleted predecessor singleton phases guarded absent by tests;
- no production reference selector, host grouping path, compatibility wrapper, feature flag,
  `_MultiKeyedLowering`, second keyed identity, or backend-specific semantic fork; and
- no CPM, Hamiltonian, proposal, acceptance, RNG, lifecycle, tracker, ownership, state-bank,
  checkpoint, rollback, or scientific-status policy in LocalWorksets.

The complete LocalWorksets package suite passed on the consolidated implementation. Focused Phase
1 gate evidence passed 31/31 assertions; the focused Phase 3--5 matrix passed 378/378. The complete
standalone cross-domain witness runner passed, including LBM, lattice spring, matrix-free FEM,
z-buffer, particle/contact named ports, and fragment/raster named ports. The two new consumers also
passed unchanged on real Metal with scalar indexing disabled. Focused real-Metal keyed evidence
passed the corrected 106-byte single-port workspace, the `R=512`, `D=129`, 7710-byte stable-grouped
profile, the 642-byte maximum named-port profile, exact validation cuts, repeat execution,
workspace/cache stability, and isolated warm provider failure.

This is final acceptance of the generic mechanical laws only. Core-adoption Gates 1B--5B were not
attempted; K04, K07, K08, lifecycle status reduction, scientific commit ordering, and state-bank
activation remain CorePotts-owned and wired. Timed old-versus-new noninferiority, near-envelope
latency, Core deletion, and Core performance were not measured and are not inferred from launch,
workspace, cache, or `O(R + D)` structural evidence.
