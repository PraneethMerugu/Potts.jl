# PR-chain progress

Status: current implementation snapshot. Updated 2026-09-23.

The [consolidated dependency map](consolidated-pr-dependency-map.md) owns the
identified work and dependencies: **68 repository PRs = R01–R54 plus fourteen
demonstrated companions**. The [compiler amendment](compiler-contract-chain-amendment.md)
owns compiler-tractability expectations, and the
[composition-first roadmap](composition-first-model-roadmap.md) owns the
fourteen-model delivery refinements. Historical investigation chronology is
archived in
[`archive/pr-chain-history-through-2026-09-14.md`](archive/pr-chain-history-through-2026-09-14.md).

Finish means every identified PR is implemented, documented, tested on its
declared CPU/GPU and integration boundaries, independently reviewed, and merged
in dependency order. Releases remain unauthorized.

## Completed foundation

- R01–R07 are merged across PottsModels, Potts, CorePotts, LocalMath, and
  MakiePotts. Core R08 merged as CorePotts PR32 (`7b46e4eb`), and its Potts
  consumer R09 merged as Potts PR53 (`0e0f4dfc`).
- All fourteen demonstrated companions are merged: the PottsModels CI correction and
  LocalMath immutable products, execution prerequisites, fixed-value effect
  analysis, backend-owned transfer, identity-seeded reduction control, and
  ordered-fold step validation, plus exact keyed reduction, atomic keyed
  rebuild publication, bounded runtime launch, direct source-order recurrence,
  validation-copy settlement, Core Cartesian domain ownership, and Potts
  Cartesian domain authoring.
- The seventh identified companion is LocalMath PR18, merged as `9d3e1a24`.
  The eighth is LocalMath PR19, merged as `7082ed84`; both passed their complete
  hosted package, scientific, documentation, macOS, and real-Metal checks.
- The ninth is LocalMath PR20, merged as `cca004b9`; its complete hosted suite
  also passed.
- C12 is merged as LocalMath PR21 (`12b3fa98`), with exact local KCT,
  allocation, full CPU, affected real-Metal, throughput and independent-review
  evidence green.
- C13 is merged as LocalMath PR22 (`dd5d2e0`); its exact KCT/allocation, full
  CPU, full real-Metal, independent review and complete hosted suite are green.
- C14 merged as LocalMath PR23 (`a26cbfe`); its fresh-session KCT, full CPU,
  full real-Metal, independent review and complete hosted suite are green.
- The non-counted LocalMath PR24 maintenance/compiler correction (`a1d60d1a`)
  merged on C14 and narrows pointwise temporary-identity segmentation. Fresh KCT,
  1,942 behavioral CPU assertions, real Metal 592/592, Core
  17,658/17,658, Potts 99/99, downstream Metal Core checkerboard 83/83 and
  continuation 116/116 are green. The one CPU-suite error is the baseline Aqua
  environment failure resolving KernelAbstractions' optional `EnzymeCore` weak
  dependency. Hosted `changes`, `macos-smoke`, `docs` and `scientific` are
  green; `package` and `metal` are pending, and conditional `macos-package` is
  skipped at observation.
- C10 merged as CorePotts PR35 (`b6ded93d`). Its reconstructed tip passed
  31,481 local CPU/quality assertions, strict documentation, independent review,
  the complete hosted package suite, macOS smoke, and the real-Metal suite. The
  obsolete broad domain fields were removed in the same cutover; the
  authoritative `CartesianOwnershipDomain` now owns immutable owners and the
  mutable-site attempt set.
- The non-counted CorePotts PR38 lifecycle-product device correction merged as
  `2ceb98ac` on C10. Its full hosted package, docs, macOS and real-Metal checks
  passed; local Core CPU/quality passed 31,497/31,497, Core Metal 82/82, and
  the downstream Potts structured-retirement Metal witness 52/52. R09's exact
  CI, replay and Metal profiles now consume this merged Core tree.
- Potts R09 merged as PR53 (`0e0f4dfc`) on 2026-09-23. The merged tree equals
  the qualified PR tip `b04e05fb`. The exact LocalMath `d3d2e553` / Core
  `2ceb98ac` tuple passed 5,078/5,078 local owner CPU assertions and the
  standalone mixed-symbolic real-Metal witness 416/416; hosted package,
  integration, exact replay, documentation, macOS smoke and full real-Metal
  checks all passed.
- Potts C11 merged as PR59 (`7bfc2d30`) on 2026-09-23, after documentation-only
  progress PR67 (`bb7d0bf7`). The merge tree equals qualified tip `43f293c3`.
  Local owner CPU passed 5,192/5,192; the post-restack exact-dependency focused
  suite passed 217/217, strict docs and integration passed, exact replay passed
  220/220, and the portable-KA real-Metal Cartesian parity witness passed 15/15.
  Required hosted package, docs, macOS smoke, integration, replay and real-Metal
  checks all passed. Corrected Core R10 is the next owner-level PR.
- The complete delivery is not close to finished: G04/G05 and all later
  main-spine/breadth groups remain open unless listed above.

## Published active stack

| Plan item | Repository PR | Selected revision | Base | State |
| --- | --- | --- | --- | --- |
| R08 Core typed composition/lifecycle | [CorePotts PR32](https://github.com/PraneethMerugu/CorePotts.jl/pull/32) | `7b46e4eb` | main | merged |
| R09 Potts composition | [Potts PR53](https://github.com/PraneethMerugu/Potts.jl/pull/53) | `0e0f4dfc` | main | merged; exact local CPU and full hosted package/integration/replay/docs/macOS/Metal green; merge tree equals qualified tip `b04e05fb` |
| R10 Core maintained quantities | [CorePotts PR33](https://github.com/PraneethMerugu/CorePotts.jl/pull/33) | `b26d4d8b` (clean local candidate; PR branch unchanged) | merged C10 and Core PR38 | local owner CPU 33,288/33,288, strict docs and full real-Metal suite green; PR33 restack/hosted qualification pending |
| R11 Potts maintained-quantity authoring | [Potts PR54](https://github.com/PraneethMerugu/Potts.jl/pull/54) | `4cec5535` (historical branch) | merged C11 | draft; restack depends on corrected R10 |
| R49 Core operational runtime boundary | [CorePotts PR34](https://github.com/PraneethMerugu/CorePotts.jl/pull/34) | `b4e5bda5` | CorePotts PR33 | draft; hosted suite green, blocked by R10 completion |
| R50 Potts resolved operational lowering | [Potts PR55](https://github.com/PraneethMerugu/Potts.jl/pull/55) | `6c5344d6` | Potts PR54 | draft/CLEAN; exact Symbolics 7.37 CPU/Metal correction and complete hosted suite green, blocked by R11 and downstream canary |
| C08 LocalMath exact keyed reduction | [LocalMath PR19](https://github.com/PraneethMerugu/LocalMath.jl/pull/19) | `7082ed84` | main after LocalMath PR18 | merged; exact-tip hosted package/scientific/docs/macOS/real-Metal green |
| C09 LocalMath atomic keyed rebuild publication | [LocalMath PR20](https://github.com/PraneethMerugu/LocalMath.jl/pull/20) | `cca004b9` | LocalMath main after PR19 | merged; exact-tip hosted package/scientific/docs/macOS/real-Metal green |
| C12 LocalMath bounded runtime collection launch | [LocalMath PR21](https://github.com/PraneethMerugu/LocalMath.jl/pull/21) | `12b3fa98` | LocalMath main after PR20 | merged; complete local/hosted CPU, real-Metal, KCT/allocation/performance and review green |
| C13 LocalMath direct source-order recurrence | [LocalMath PR22](https://github.com/PraneethMerugu/LocalMath.jl/pull/22) | `dd5d2e0` | LocalMath main after PR21 | merged; complete local/hosted CPU, real-Metal, KCT/allocation and review green |
| C14 LocalMath validation-copy settlement | [LocalMath PR23](https://github.com/PraneethMerugu/LocalMath.jl/pull/23) | `a26cbfe` | LocalMath main after PR22 | merged; complete local/hosted CPU, real-Metal, KCT and review green |
| LocalMath PR24 maintenance/compiler correction — pointwise temporary-identity segmentation (not counted) | [LocalMath PR24](https://github.com/PraneethMerugu/LocalMath.jl/pull/24) | `a1d60d1a` | merged C14 `a26cbfe` | merged; fresh KCT, LocalMath behavioral CPU 1,942 pass with baseline Aqua environment error, real Metal 592/592, Core 17,658/17,658, Potts 99/99, downstream Metal Core checkerboard 83/83 and continuation 116/116 green; hosted changes/macOS-smoke/docs/scientific green, package/Metal pending and conditional macOS-package skipped at observation |
| C10 Core Cartesian domain ownership | [CorePotts PR35](https://github.com/PraneethMerugu/CorePotts.jl/pull/35) | `b6ded93d` | Core R08 | merged; local/full hosted CPU, docs, quality, macOS, independent review, and real-Metal green |
| Core lifecycle-product device correction (not counted) | [CorePotts PR38](https://github.com/PraneethMerugu/CorePotts.jl/pull/38) | `2ceb98ac` | merged C10 | merged; exact local/downstream and complete hosted CPU/docs/macOS/real-Metal green |
| C11 Potts Cartesian domain authoring | [Potts PR59](https://github.com/PraneethMerugu/Potts.jl/pull/59) | `7bfc2d30` | merged C10 and Potts R09 | merged; local full CPU/docs/integration/replay/real Metal and complete required hosted suite green; merge tree equals qualified tip `43f293c3` |
| Canonical plan/API publication | [Potts PR56](https://github.com/PraneethMerugu/Potts.jl/pull/56) | `c33c930a` | main | merged; complete hosted suite green |
| Atomic keyed-rebuild plan | [Potts PR57](https://github.com/PraneethMerugu/Potts.jl/pull/57) | `a6b342b5` | main after PR56 | merged by auto-merge; complete hosted package/docs/macOS suite green |

Planning labels are not GitHub PR numbers. A green stacked child does not make
an incomplete parent ready.
For merged entries, the selected revision is the merge commit; for open entries,
it is the reviewed branch tip.

## Current corrections and blockers

### G05 periodic geometry and connectivity

The active Core candidate correctly moved toward persisted image-labelled
physical moments, canonical ownership-count authority, nearest-pretransaction-
center updates, lifecycle/checkpoint history, and a narrow allocation-free
connectivity view. Independent review blocked publication until it:

- accepts canonical negative medium/domain ownership while requiring zero image
  labels for non-finite sites;
- fully validates standalone connectivity descriptors, relation symmetry,
  volume authority, and initially connected owners;
- implements spacing-aware periodic minimum-image focal distance;
- restores independent full-Hamiltonian, accepted-copy, overlay, lifecycle,
  3D/Float32, checkpoint-corruption, and unrelated checkerboard coverage;
- removes rejected checkerboard moment machinery and makes backend-support
  claims match reachable execution; and
- supplies Kaimon or exact typed-code evidence for both connectivity and moment
  overlays without broad runtime payloads.

The candidate remains uncommitted and unpushed.

### G05 maintained spatial queries

Existing LocalMath destination grouping requires a pre-existing dense
destination and cannot exactly intern sparse generation-aware owner pairs with
O(E) storage. This demonstrates the eighth companion: an exact fixed-capacity
keyed collection reduction after LocalMath PR18 and before R10/R11 completion.

The complete R11 audit also found a separate accepted Cartesian-domain
regression. Current Core represents finite cells and medium domains only;
Potts exposes `FrozenBorder`, but lowers it identically to a closed CPM
boundary. There is no durable wall/exterior/obstacle owner, no virtual exterior
or obstacle incidence, and no authoritative mutable-site set excluding
obstacles. A wall filter therefore cannot truthfully be lowered as an empty
medium filter, and backing-array site count cannot stand in for the reference
attempt budget. The retired pre-refactor `e8706bcd` Cartesian implementation
and its relation/sequential/checkerboard/query tests are an independent semantic
oracle, not a parallel executor to restore.

C10 Core atomically replaces/extends the existing owner classification and
owner-at-site authority with compact domain-owner records, face/obstacle
realization, mutable-site scheduling, immutable-write rejection,
checkpoint/inspection and CPU/real-Metal behavior. C11 Potts owns typed
domain/axis/obstacle authoring and initialization/lowering. It first migrates
every current no-flux `FrozenBorder` consumer to `Closed`, then deletes the
ambiguous spelling; it never reinterprets it as `FixedExterior`. R10/R11 then
consume those facts for the complete explicit spatial-query surface. This
demonstrated pair raised the identified count to 65 before C12 raised it to 66.
C13 direct source-order recurrence and C14 validation-copy settlement then
raised the count to 68 after the exact LocalMath–KA audit demonstrated two
different reusable owner laws. The follow-on compiled-artifact reuse
investigation qualified LocalMath PR24's pointwise temporary-identity
segmentation as a non-counted maintenance/compiler correction.

CorePotts PR35 now implements C10 on top of merged R08. It owns the complete
Cartesian executable identity, uses one mutable-site attempt population for
sequential and checkerboard execution, retains fixed-owner contact incidences,
and excludes non-finite owners from lifecycle and relationship endpoints. The
final local candidate passed 99 Cartesian-domain tests, 124 LocalMath compiler-
boundary tests, 53 flagship compiler tests, 253 continuation/state tests, 63
checkerboard transaction oracles, 20 package-quality checks and the strict docs
build. Independent review is clean. Hosted real-Metal remains authoritative and
is running; C10 is not complete until those checks pass.

LocalMath PR19 remains inside the sole StageProgram and shared
KernelAbstractions executor, with canonical lexicographic keys, prior-then-
source/lane left-fold order, private bounded workspace, identity-key deletion,
and failure-atomic records/count publication. Review corrections removed the
zero-domain write, no-choice public axes, broad phase payloads, unsafe explicit
record constructor and incomplete device atomicity cases. Kaimon-backed typed
probes now show that operation/retention specialize only the fold boundary;
focused CPU 40/40, real Metal 24/24 with scalar indexing disabled, the complete
LocalMath suite 1,853/1,853, documentation and independent review are clean.
Its complete exact-tip hosted suite passed, and PR19 merged as `7082ed84`. The
stale PR17-parent draft was not published.

With that companion frozen, Core R10 owns generation-aware O(E) pair
multiplicity and maintained results behind the existing `ResourceOperation`
identities. Potts R11 lowers analyzed filter/property facts through public
compiler SPI. No detached query vocabulary, O(C²) directory, collision-unsafe
hashing, or GPU-only executor is accepted.

Repeated maintained relationship publication then demonstrated one additional
LocalMath gap. C08 intentionally folds stage-entry records before new
contributions, so replaying a complete pair rebuild accumulates stale totals.
`Collect` cannot fold duplicate runtime keys, and a consumer cannot clear or
alias `CompactedStorage.count` without violating storage ownership and failure
atomicity. C09 therefore adds only an exact rebuild seed policy to the same
`KeyedReduce` prepared stages and KernelAbstractions executor: ignore prior
records, fold the complete candidate canonically, and replace count plus records
only on success. The Core consumer confirmed this removes its otherwise
necessary fresh-allocation/copy workaround. Corrected candidate evidence includes
the complete CPU suite at 1,869/1,869, focused real Metal at 37/37 with scalar
indexing disabled, strict docs, and exact C08-base versus C09-candidate
`code_typed`/MethodInstance comparison. The isolated Core
checkerboard consumer now publishes `(1, 1.0)`, exactly matching its independent
pair oracle where the incremental policy had incorrectly produced `(3, 3.0)`;
its capacity-greater-than-emission duplicate-pair case also passes on CPU and
real Metal. Independent review initially found that a
rebuild whose destination capacity exceeded its emitted candidates passed the
destination capacity, rather than the actual zero prior-record count, into
duplicate-key classification. That can reject ordinary duplicate contributions
instead of folding them. The candidate now passes the actual prior capacity,
adds noncommutative CPU/Metal regression coverage, and is independently
re-review clean. Its complete exact-tip hosted suite passed before merge;
extended Core lifecycle qualification remains.

### R50 pinned array imports

Hosted Metal isolated a Symbolics 7.37 failure for whole-array component imports
and indexed/reordered leaves. Potts commits `0994c492` and `6c5344d6` preserve
the validated authored array-symbolic identity, install whole plus scalar substitution rules
at the sole import-resolution owner, and reject overlapping whole/scalar aliases
in either binding order.

- exact pinned focused CPU contract: 6/6;
- exact hosted dependency tuple, CPU plus real-Metal vector-parameter witness
  with scalar indexing disabled: 132/132;
- complete focused component-replacement owner suite: 139/139; and
- committed Metal Project/Manifest unchanged.

PR55's exact-tip hosted package, integration, replay, compiler, documentation,
macOS and both real-Metal shards all passed. It remains draft because R11 and
the required downstream canaries are incomplete.

## Compiler qualification status

The [compiler amendment](compiler-contract-chain-amendment.md) owns the contract;
this table records only the current evidence state. A green component does not
qualify a later joined package tuple.

| Qualification item | Current evidence | Remaining work and owner |
| --- | --- | --- |
| C08/C09 keyed reduction and rebuild | C08 and C09 are complete at merged LocalMath PR19/PR20 with full hosted qualification. C09 corrected its review blocker and its exact Core checkerboard consumer matches independent pair oracles, including capacity-greater-than-emission duplicate-key folding on real Metal. | Consume merged C09, then rerun the extended Core lifecycle/checkpoint/permanent Metal and affected full-suite witnesses before R10 publication. |
| G04 structural baseline | Core R08 and Potts R09 are merged. | Record the complete R08/R09 structural lifecycle/history/compound-effect tuple and unchanged control before G05 qualification. |
| G05 relation and maintenance delta | Active Core/Potts candidates have focused evidence, but periodic geometry/connectivity and maintained-query science remain incomplete. | R10/R11 must measure exact contribution/update/rebuild/publication and geometry entrypoints plus unchanged controls on the joined C08/C09 tuple. |
| R49 canonical Core boundary | The draft candidate has hosted evidence, but it is stacked on incomplete R10. | Warm the legitimate family basis; hard-check one versus 64 repeated entries plus rename/value/remake controls at the owner-defined family/signature boundary, AllocCheck, warmed allocation and actual-device probes on corrected R10. Retain the full 1/4/16/64 ladder, 256 and aggregate compiler counts in the dedicated compiler job or merge/nightly evidence. |
| R50 public lowering identity | The draft candidate has pinned-array CPU/Metal evidence; its parent R11 and downstream interface canary remain open. | Prove package-declared and interactive equivalence, author-name erasure, source diagnostics and the complete public workflow on the exact joined stack. |
| Retrospective compiler-debt sweep | PR19 supplied its own feature-local comparison; C09 has a policy-specialization probe; no completed cross-merge sweep is recorded for R06, R07 or the LocalMath companion sequence. | Run the bounded before/current comparisons before R49/R50 freeze; correct a measured defect in its open owner or count a targeted companion only if required. |
| G06/G07 interface canaries | Required by R49/R50; R50 is still recorded as blocked by its downstream canary. | Preserve G05's explicit rejection while proving the normalized boundary distinguishes a periodic/shared-owner/relation conflict from shared read-only and owner-proven commutative/associative compatibility; also exercise one held/native-snapshot case before interface freeze. |
| Canonical public benchmark runner | The design and corpus are specified; G09 is not implemented. | R49/R50 leave the focused reproducible runner; R20 later owns longitudinal fresh/warm, specialization, allocation, transfer and cache records. |

### KCT optimization arc status

The current qualification stack is LocalMath C09 `cca004b9`, CorePotts R49
`b4e5bda5`, Potts R50 `2d317fc0`, plus accepted Potts saved-state change
`40b2ddf3`. All observations below came from live registered Kaimon MCP tools in
fresh sessions unless explicitly identified as ordinary behavioral evidence.
They are diagnostic results, not implementation or backend qualification.

Phase 1 attributed LocalMath stage lowering and made no production change.
Fresh total inference for 1-, 4-, 8-stage and dependency-composed programs was
6,802 / 13,622 / 15,447 / 14,316 events; planning was 5,077 / 8,567 / 9,733 /
9,407, preparation 1,403 / 4,680 / 5,336 / 4,559, and warmed execution 338 /
434 / 457 / 157. The 8-stage helper self-costs were 216 binding-slice, 211
slot-projection, 2,331 draft-construction, 1,387 evaluator-admission and 251
callable-admission events. Although the slice typed IR was large (470 statements,
235 calls, 54 JET dispatch reports and 91 AllocCheck findings), MethodInstances
for slice/projection plateaued and no causal scaling leak was established.
Because no candidate reduced complete planning-through-execution inference
without displacement or small-case regression, the result is a formal no-change
and no companion.

Phase 2 built the Potts late-lowering atlas and also made no production change.
Author-only rename, literal change, equal-typed handle change and isomorphic
declaration renumbering reused operational execution types. State, stage and
maintained/tracker ladders localized expected host structural growth while Core
runtime/workspace families plateaued in the controlled cases. The corrected
capacity/extent controls found 331 fresh inference events for capacity 16→24 at
fixed 6×6 extent and 31 for extent 6×6→8×8 at fixed capacity 16, with identical
Potts/Core/runtime/integrator/workspace/LocalMath-plan types. The 331 events are
LocalMath/KernelAbstractions CPU `StaticSize{24/25}` lifecycle-compaction launch
specializations, so they are assigned to the LocalMath launch investigation,
not misreported as a Potts lowering defect. Metal MCP probes timed out and are
inconclusive; the prior exact-stack 11/11 real-Metal behavioral result remains
the backend evidence for its exact revision.

Phase 3's corrected warm-allocation protocol compiles the wrapper on a separate
subject, creates a fresh identical integrator for every sample, warms step one,
then measures only seeded step two with a typed sink and scientific/RNG equality
checks. Seven feature-off sequential samples were exactly 49,088 bytes each.
Core advance had a 37,712-byte median (one 40,000-byte sample); current-state
refresh was exactly 11,216 bytes. Refresh is 22.85% of total, below the declared
50% trigger, so the live `PottsCurrentState` prototype is rejected and was not
started. The interrupted `step!` AllocCheck request produced no final result and
is not evidence. Core advance is the next ranked owner; component measurements
are not assumed additive.

The three evidence-gated investigations are complete. Each used an isolated
exact worktree, fresh live Kaimon sessions, one-axis reuse controls, independent
review and real Metal for the qualifying candidate. The launch investigation
demonstrated C12; preparation and Core payload attribution closed with no
production change. Core/Potts fixes remain within R49/R50.

The LocalMath preparation/device-payload investigation is now a formal
no-change. On exact clean C09, fresh composed inference was 3,072 construction,
1,370 binding, 9,489 planning and 4,559 preparation events. Workspace authority
and collect preparation were the largest individual preparation timings, but
their MethodInstance populations remained bounded. Exact prepared-value
adaptation had no AllocCheck findings, one optimized statement, zero calls, a
concrete result and zero bytes in five warm samples. Warm preparation's 179,552
bytes combines required workspace/device construction with lease work; no
isolated scaling boundary justified slot ordinals, schema erasure or a second
binding representation. That workstream adds no code and no companion.

The LocalMath launch investigation qualified and merged C12. For
`_compacted_scan_add_kernel!`, the existing value-derived static
workgroup plus static `ndrange` produced 64 fresh inference events for 16→24 and
74 for 24→32. The final cutover uses the existing operation-family `Val{256}`
workgroup and runtime `ndrange`; extent never chooses a workgroup family. Fresh
KCT is 1 event for 16→24 and warmed 300→301, while the 24→32 delta is
KernelAbstractions' one-time dynamic-check admission rather than an extent
identity. Optimized IR fell from 40 statements/25 calls to 26/14. Warm allocation
is unchanged at 256 bytes in seven samples. Focused CPU passed 261/261, full CPU
1,880/1,880 and affected real Metal 254/254 with scalar indexing disabled.
Independent review found no issues, including the zero-extent path, and
alternating warm CPU/Metal samples found no material regression. LocalMath PR21
merged as `12b3fa98`; its complete hosted suite is also green.

The follow-on exact LocalMath–KernelAbstractions audit demonstrated C13 and
C14. C13 removes compaction/bitonic sorting only from `SourceOrder`, retaining
canonical folds on their compacted path and specializing recurrence on exactly
two semantic traversal laws. Launches at 32/300/301 fell from 21/51/51 to
6/6/6 and warmed allocations from 7,792/77,712/77,712 to
3,472/7,584/7,584 bytes. LocalMath PR22 merged as `dd5d2e0`; focused/full CPU,
focused/full real Metal, KCT, invalidation and complete hosted checks are green.

C14 narrows settlement to the prepared program's existing device/host
validation matrix. Pending wait fell from 208 to 176 bytes and grouped/combined
waits improved by 32 bytes at every measured dependency arity. KCT rejected an
intermediate broad-catch shape at 235 statements/135 calls/67 `Any` slots; the
final narrow failure boundary is 130/75/35 versus the 131/76/36 baseline, with
one MethodInstance per settlement boundary. On the combined PR22/PR23 tip,
focused CPU passed 443 assertions, full CPU 1,943/1,943, focused real Metal
137/137 and full real Metal 592/592. Independent review is clean. PR23 merged
as `a26cbfe` after its complete hosted suite passed. The
[audit record](localmath-kernelabstractions-audit.md) contains the exact KA
0.9.42 source contract, complete boundary atlas and rejected hypotheses.

LocalMath PR24's non-counted maintenance/compiler correction is the first
accepted result of the compiled-artifact reuse investigation.
Pointwise graph traversal had remained fused with reusable segmentation even
after the caller knew which publications were temporary. The candidate leaves
temporary extraction in a small graph-aware wrapper and passes only the runtime
temporary-identity set to the semantic segmentation law. It preserves bounded
pointwise segments and the one KernelAbstractions CPU/Metal execution path;
there is no cache, retained lookup table, second graph representation, alternate
executor or model-specific kernel. Fresh registered KCT supports the narrower
boundary. LocalMath behavioral CPU passes 1,942 assertions, with only the
pre-existing Aqua environment failure resolving KernelAbstractions' optional
`EnzymeCore` weak dependency; real Metal passes 592/592 with scalar indexing
disabled; Core passes 17,658/17,658; Potts passes 99/99; and downstream Metal
Core checkerboard passes 83/83 with continuation at 116/116. LocalMath PR24
merged as `a1d60d1a`. At observation, hosted `changes`, `macos-smoke`, `docs`
and `scientific` are green; `package` and `metal` are pending, and conditional
`macos-package` is skipped.

The subsequent top-down portable compiler investigation is recorded in
[portable-gpu-compiler-architecture-investigation.md](portable-gpu-compiler-architecture-investigation.md).
The current PR24 correction reuses execution families across author names,
runtime values and extents, and the isolated Potts late-lowering boundaries reuse tracker,
descriptor, stage, lifecycle and Core types across rename and declaration
reorder. One R50-owned defect is demonstrated: `PottsParameters` currently
places author-facing NamedTuple keys in problem/integrator type identity. A
runtime-name-tuple prototype reduces renamed-equivalent `init` inference from
43 records to the KCT root record while remaining AllocCheck- and JET-clean.
Ordinary CPU, remake/checkpoint and portable-Metal validation remain in
progress, so this is not yet merged evidence. The exact Metal 1.10.0 tuple is
blocked on macOS 27 because it reports no device; Metal 1.11.1 sees the M1 Pro
and is used only for supplemental behavior evidence pending a normal dependency
decision. The identified feature count remains 68.

The Core execution-payload investigation is a formal R49 no-change. Fresh
step-two decomposition found the proposal/descriptor/tracker/accepted-copy path
at 0 bytes, `_after_mcs!` at a 37,024-byte median, lifecycle site indexing at
7,136, emission at 7,056, request indexing at 11,360 and selection at 14,752
when measured independently; these figures are not additive. A direct LocalMath
site-plan execute/wait control reproduced the site-index scale exactly. Concrete
AllocCheck and JET findings cross immediately into LocalMath receipt/dependency
handling and KernelAbstractions CPU scheduling, while the exact Core wrapper and
LocalMath execute MethodInstances are concrete. No broad Core runtime-payload
defect or qualifying R49 cut was demonstrated. G09 retains provider-owned
receipt/task allocation pressure with an R49 consumer canary; it does not
broaden the launch companion unless that launch change directly improves these
bytes.

### Three-pass compiler-cardinality audit

The package-by-package audit identifies a new cross-chain requirement but no
qualified production correction yet. It is recorded as
**cardinality-independent execution identity**: after warming the bounded set of
legitimate backend, dimension, scalar/storage, operation, value-shape and
execution-law families, repeated model instances must not create new
owner-scoped device execution families or model-sized typed IR. This is not a
claim of universal constant Julia compilation.

- LocalMath already plateaus across runtime extent in the controlled pointwise
  case: extent 16→301 kept the same eight law families, with host compilation
  19.402→19.815 seconds, planning 9.047→9.117 and preparation 8.024→8.352.
  Stage cardinality does not yet plateau: 1→4→8→32 stages grew host compilation
  3.725→17.221→21.810→41.422 seconds, planning
  2.416→7.325→9.412→23.480 and warmed allocation
  608→8,640→15,552→65,568 bytes. `LocalLaw` stage tuples and global structural
  binding tuples are the leading investigation boundary; no runtime-row
  replacement has passed complete planning-through-settlement A/B validation.
- Minimal Core checkerboard construction reuses an exact repeated program in
  process, but its operational types remain graph-shaped: the observed
  `ProgramRuntime` and workspace type renderings were 79,868 and 78,119
  characters, and fresh initialization produced 78,298 inference records.
  Rendered length and raw record totals are diagnostic trends, not CI gates.
  R49 owns repeated tracker/update and maintained/state payloads consumed by its
  admitted contracts. Later lifecycle and relationship owners define their own
  families while reusing that law; R12/R13 own checkerboard conflict-closure
  execution without a prescribed phase or kernel layout.
- Potts already keeps completion/source graphs as host runtime data and reuses
  key late-lowering types across author rename, reorder and numerical changes.
  Remaining risks are graph-shaped operation expressions, alternating stage
  family grouping, tracker/lifecycle tuple combinations, manifest identity and
  saved/current state schemas. R50 owns demonstrated normalization and erasure;
  it must not hide novelty in `Any` storage or introduce an evaluator registry.
- PottsModels currently supplies valuable scientific factories but not the
  controlled public scaling matrix. G09/R20 owns the shared runner and minimal
  variants; R52–R54 extend it with realistic repeated and mixed-family models
  without inspecting upstream private compiler structures.

Owner-local hard CI warms the family basis and compares one versus 64 repeated
instances plus rename/value controls at a stable owner-defined signature, with
narrow JET/AllocCheck contracts. The dedicated compiler job covers 1/4/16/64;
the 256-instance case, exact MethodInstance/KA/GPUCompiler identities, aggregate
inference/IR counts, timings and private backend artifacts remain trends. The
identified total stays **68**. Another LocalMath companion remains conditional
and uncounted; it is added only if a direct cold-law/binding
candidate materially improves the complete
lifecycle without displacement, deletes the prior representation and cannot
coherently fit an open owner.

### Accepted checkerboard conflict-closure scope

G06 R12/R13 now owns the complete outcome contract: immutable batch-entry
evaluation; transitive read/write/effect closure through maintained quantities,
relationships, periodic aliases and shared logical owners; deterministic
backend-independent winners; read/read compatibility with arbitration only for
incompatible read/write, write/write or noncommuting effects; admitted owner-
proven commutative/associative effect sharing; and
atomic winner commit/rollback on the one CPU/GPU KernelAbstractions semantic
path. Diagnostics derive from the same dependency authority. This does not
freeze a graph, coloring, footprint representation, arbitration data structure
or kernel layout.

The completed claim graph remains runtime data. R13 lowers rich analyzed facts
to compact bounded tables/recipes and narrow state views; graph content, author
names, owner identities, adjacency and ordinary counts do not specialize the R12
executor or generate per-model kernels. Qualification compares execution
identity across renames, isomorphic renumberings, distinct graph contents and
bounded count ladders while reusing LocalMath laws whose semantics already fit.

Qualification must include truly independent proposals admitted together,
shared read-only and admitted commutative/associative positive controls, and
exact shared-owner conflicts. Periodic-moment/image-label gauge variants require
identical canonical physical observables and energies, closure and winners, and
gauge-equivalent moment state; raw identity is required only if G05 establishes
one unique canonical gauge. Sequential/full-state evaluation is only an
isolated-winner scientific oracle; checkerboard trajectory, ordering and kinetics
remain distinct.

For an admitted batch, scheduled attempts, non-no-op proposals, conflict losers
and winners are distinct counts. No-op, loser and semantically rejected proposals
leave state unchanged and receive no compensating attempts; a statically rejected
conjunction does not launch. Preserve declared semantic RNG addressing and
unrelated-stream invariance under filtering, arbitration and permitted launch
permutations without asserting unused draws. Subround time follows realized
checkerboard color fractions, not winner count.

G05 continues to reject unsupported checkerboard moment, shared-owner,
relationship and derived-dependency combinations explicitly. Before G05C
R49/R50 freezes, its downstream canary must prove that normalized operational
payloads retain enough dependency/effect meaning for R12/R13 without carrying
the authored graph into device execution. G07 adds held/native snapshot
pressure; G09 retains compiler/allocation evidence; E01, E03, E08, E11 and E12
add 3D periodic/shared-owner, opposite-endpoint relationship, exact-global-
predicate, compound-swap and weighted-graph cases. The identified count is now
68. R10 implementation demonstrated C09, one narrowly owned reusable LocalMath
keyed-rebuild law that cannot coherently live in Core or Potts. No further
checkerboard companion is presumed. C10/C11 are separately demonstrated
Cartesian-domain owners, not checkerboard work.
R12/R13 atomically delete a G05 rejection only when that exact conjunction is
qualified; unsupported conjunctions continue to reject explicitly.

### Checkerboard issue audit

As of 2026-09-14, GitHub reports zero open and zero closed issues in each current
repository: Potts.jl, CorePotts.jl, LocalMath.jl, PottsModels.jl and
MakiePotts.jl. The likely legacy Potts repositories CPMV2, PureArrayCPM.jl and
GPUPottsv1.jl also report zero open and zero closed issues. `SEM-ALG-001`
(checkerboard equilibrium guarantee) is a relevant unresolved specification
identifier, not a GitHub issue number. No issue was reopened; merged pull
requests, historical hardening records and PR-chain labels were not
misrepresented as issues. A different tracker would require its exact
repository or link before any reopen action.

### Portable compiler architecture and current dependencies

The top-down portable compiler audit is recorded in
`design/portable-gpu-compiler-architecture-investigation.md`. KCT demonstrated
one author-name leak in the audited R50 baseline: renamed runtime parameters
created 43 additional inference records. R50 base commit `61745a52` already
owns the direct correction through a runtime parameter schema; the independently
prepared duplicate PR #62 was closed after that base advance was discovered.
The corrected path reuses the execution family and adds only the KCT root
record. Behavioral validation passed 5,085 assertions, package quality passed
48/48, and the real-Metal vector-parameter witness passed 132/132.

The LocalMath PR24 correction passed all 592 assertions in its complete
portable-KA Metal suite on Metal 1.11.1/GPUCompiler 2.8.1 with scalar indexing
disabled. Potts PR #63
refreshes the reproducible Metal profile to current compatible external
releases. Its clean precompile took about 76 minutes and its focused Metal
witness 11 minutes 6 seconds; these remain benchmark evidence rather than CI
thresholds. Internal source heads are not independently interchangeable:
CorePotts `main` has the V2 RNG cutover but lacks later R49 SPI consumed by the
active R50 lineage. The later source join therefore remains a direct cutover,
without compatibility aliases. This maintenance PR does not change the 68-PR
identified feature-chain count.

PR #63 also refreshes the exact CPU replay profile to current released SciML
and MethodOfLines dependencies. An isolated qualification passed 249/249
checkpoint/restart assertions before the production replay row was advanced.
Docs and ordinary integration now admit MethodOfLines 1.x. The latest Metal
native tuple is not granted exact replay yet: its former bounded-failure
witness now succeeds under DiffEqGPU 3.21.2, so failure atomicity must be
re-established before that closed evidence row can move. Functional portable
KA-on-Metal support remains validated on the latest stack.

## Immediate dependency order

1. Correct, re-review, and qualify the periodic geometry/connectivity candidate;
   consume merged LocalMath PR19 plus qualified C09 as the exact keyed-reduction
   and atomic-rebuild prerequisites.
2. Integrate the joined Core R10 maintained spatial-query/geometry contracts and
   the matching Potts R11 lowering; finish the remaining native-output,
   full-field invalidation, lifecycle/division, and restore obligations.
3. Requalify the exact R10/R11/R49/R50 stack; only then mark or merge parents and
   children in dependency order.
4. Begin G06 R12/R13 conservative energy/drives and G07 R14–R16 native transfer,
   lifecycle, and first complete maintained model.
5. Continue G08/G09 and the breadth groups E01–E16 according to the canonical
   graph. Final G09/R20 follows joined R49/R50 and R12/R13 phase boundaries;
   R52–R54 all extend its one public benchmark/observation runner rather than
   creating paper-specific compiler harnesses.

## Merge policy

- LocalMath `main` now requires pull requests with zero approving reviews,
  enforces protection for administrators, and uses strict required checks
  `changes`, `package`, `scientific`, `macos-smoke`, `docs` and `metal`.
- Keep incomplete or failed-review PRs draft.
- Request auto-merge only after the exact current tip has passed applicable
  owning, integration, documentation, replay, and real-device checks plus
  independent review.
- Cancel superseded hosted runs when a newer tip replaces them.
- Do not infer branch protection from a successful auto-merge request; an
  unprotected repository may merge immediately.
- Never merge a stacked child before its parent or call green CI completion of
  an unresolved scientific contract.

## Next completion condition

The next milestone is a scientifically correct and joined G05 baseline: R10,
R11, the exact keyed-reduction companion, and their R49/R50 compiler-contract
children must all be current-tip green and independently review-clean. It does
not complete G06–G09 or any breadth group. Full project completion requires all
68 identified PRs and any later demonstrated owner companions.

### CI implementation arc and repository reconciliation

The independent CI implementation arc remains outside the 68-feature allocation.
Its Wave-1 telemetry changes are published as LocalMath PR25, CorePotts PR36,
Potts PR64, PottsModels PR3 and MakiePotts PR9. They measure environment
resolution, dependency precompilation, compilation-family fixture cost, cache
transfer and representative CPU/Metal consumers without changing scientific
test selection or adding timing thresholds. Wave 2 remains gated on hosted
fresh/warm evidence from these exact tips.

Potts PR64 is stacked on dependency-refresh PR63. PR63 is mergeable but its
`metal shard (quantities_and_components)` witness and aggregate `metal` check
failed on the observed tip, so neither PR is ready to merge or restack.

The 2026-09-18 repository reconciliation preserved previously uncommitted
implementation work on its owning branches: Core Cartesian ownership on the
existing PR35 branch, Core maintained spatial-relation integration on
`codex/relation-measure-sensing`, Potts diagnostic validation on
`codex/reconcile-diagnostic-validation`, and Potts structured-authoring
qualification on `codex/structured-authoring-integration`. Publication is a
recovery action, not implementation qualification or authorization to merge.
