# Archived PR-chain chronology through 2026-09-14

Status: historical development record. This file is not a current status,
workflow, dependency, or completion authority. Current status lives in
[`../pr-chain-progress.md`](../pr-chain-progress.md); the dependency graph and
identified count live in
[`../consolidated-pr-dependency-map.md`](../consolidated-pr-dependency-map.md).

The entries below preserve investigation chronology, including superseded
counts, commands, process identifiers, timings, and evidence references. They
must not be followed as current instructions or treated as active gates.

The scope and dependencies remain in [the delivery map](../consolidated-pr-dependency-map.md).
The current identified allocation is 62 repository PRs: R01–R54 plus eight
demonstrated companions, including the merged G07 LocalMath ordered-fold
step-validation prerequisite and the active G05 exact keyed-reduction
prerequisite.
Finish means implemented, tested, documented, independently reviewed and
review-ready. R01–R07 and seven of the eight currently identified companions are merged. G04, G05, and the
remaining delivery work are incomplete. Individual PR readiness is recorded
separately from completion of the full chain. The user has authorized
necessary branches/worktrees, the PottsModels remote, and merging PRs judged fit
after testing, review, and dependency checks. Releases remain unauthorized.

## Active work

- **G05 exact keyed-reduction companion authorized (2026-09-14):** the real
  maintained spatial-query design proved that LocalMath's existing destination
  grouping can atomically combine multiple deltas only after Core already maps
  each canonical owner pair to one dense `Int32` destination. A dense pair
  directory is O(C²), hash destinations merge collisions, and current
  within-segment ordering cannot supply exact secondary composite-key grouping.
  The chain therefore counts an eighth companion, after LocalMath PR18 and
  before Core R10/Potts R11 completion. LocalMath owns a fixed-capacity exact
  keyed collection reduction with unique prior keys, canonical lexicographic
  key and source/lane order, identity-key removal, bounded private workspace,
  exact preparation/runtime validation and one atomic records/count publication.
  Capacity is runtime data and CPU/Metal share one KernelAbstractions stage
  sequence. Core will use it for generation-aware O(E) pair multiplicity behind
  the existing `ResourceOperation` identities; Potts will lower analyzed
  filters/property facts through public compiler SPI. No detached query API,
  hash semantics, O(C²) authority or GPU-only path is accepted. Implementation,
  allocation/compiler evidence and real-Metal qualification remain in progress.

- **R50 pinned array-import correction published (2026-09-14):** hosted Metal
  isolated a shared CPU/Metal scoped-quantity failure under Symbolics 7.37:
  whole-array component imports did not retain one stable alias identity and
  indexed/reordered leaves remained unresolved. Potts commit `0994c492` keeps
  the validated authored array-symbolic key and installs whole plus scalar rules
  at the sole import-resolution owner. Independent review found that a whole
  alias plus one separately imported component could otherwise resolve to two
  owners, so completion now rejects overlapping generated keys in either
  binding order. Exact pinned CPU passes 6/6, the shared CPU plus real-Metal
  witness passes 28/28 with scalar indexing disabled, and the complete focused
  component-replacement suite passes 139/139. The committed Metal environment
  is unchanged. PR #55 hosted qualification restarted at this tip.

- **G07 LocalMath prerequisite merged (2026-09-14):** the counted
  ordered-fold step-validation companion was committed as `2be4be7` and
  squash-merged as `9d3e1a24` in
  [LocalMath PR #18](https://github.com/PraneethMerugu/LocalMath.jl/pull/18),
  after local CPU, real-Metal and independent-review qualification. GitHub
  accepted the requested squash auto-merge immediately because this repository
  does not currently require the hosted checks; the complete post-merge run
  subsequently passed package, scientific, docs, macOS smoke and real Metal
  (14m46s), so no corrective PR is required. `FoldStep`
  carries runtime-computed validity and a bounded `Int32` witness; invalidity
  is diagnosed before any private recurrence write and final publication stays
  atomic. The existing 1024-byte update-plus-halt capacity is preserved within
  a 1032-byte total ceiling. One shared narrow `Int`/`Int32` read boundary fixes
  Metal recurrence-load hoisting without a GPU-specific semantic path: real
  Metal moved from 9/11 to 11/11, while typed transition IR moved from
  33/17/9 statements/calls/raw-`Any` entries to 12/5/3 with a concrete return.
  CPU A/B medians were 50.7085 versus 50.5830 microseconds with the same 11,424
  bytes. Final focused package tests pass 20/20, affected and quality cohorts
  pass, and independent re-review is clean. Hosted real Metal remains the
  merge authority; high-level `@ordered` syntax is deliberately unchanged.

- **Parent-G05 readiness and CPU-CI correction (2026-09-14):** Core R10/PR
  #33 is exact-tip green and its maintained sum/minimum, publication, lifecycle,
  history and checkpoint slice has no reviewed code/authority/parity defect, but
  it must not be marked ready merely from green CI. Its own declared remaining
  G05 audit still needs reconciliation against periodic/degenerate geometry,
  distinct-cell versus contact-weighted sensing, relation multiplicity/measure,
  native-output/full-field invalidation and division/restore obligations. A
  focused owner audit is locating existing versus absent coverage before scope
  is closed or changed. Potts R11/PR #54's prior Metal failure is the same
  reusable-fixture `CorePotts` import defect found on R50; parent commit
  `4de3114a` now owns the explicit import and a parent-focused run passes 344/344
  after 308 seconds of test-environment precompilation. Its preceding Ubuntu
  package run was still completing valid units when GitHub cancelled it at the
  180-minute limit, so the ordinary 90-file suite is being partitioned into
  durable semantic shards with exact inventory checks and a stable aggregate
  `package (ubuntu-latest)` status. No coverage removal or timeout-as-success is
  permitted. R50 tip `0994c492` records the repaired and package-sharded R11
  base plus the pinned Symbolics array-import correction; its
  superseded workflows were cancelled and current-base qualification was
  restarted.

- **G06/G07 next-owner audit and counted companion (2026-09-14):** R12 can
  reuse the existing sequential/gathered conservative evaluators, acceptance,
  transaction and KernelAbstractions paths; its material missing Core contract
  is a bounded semantic claim set that closes checkerboard arbitration over
  incident relationship edges and endpoint owners instead of only the two copy
  participants. R13 must preserve relationship resource identity and derive the
  transitive static/dynamic proof, with full tiny-system energy oracles and an
  opposite-endpoint spring conflict on CPU and Metal. R14 can reuse Core's
  staged program transaction, component pools and settlement receipts, but must
  provide one coordinated program/component transaction, receipt/MCS identity,
  narrow current/held input and output-publication views, global candidate state
  and bounded conservative exchange/lifecycle accounting. The current
  LocalMath `OrderedFold` already owns canonical bounded contention, evolving
  scratch state, heterogeneous paired writes and failure-atomic publication.
  It lacks one generic semantic late-validation channel for a transition whose
  computed result is invalid. The chain therefore now counts one G07 LocalMath
  companion before R14: add recurrence validity and a bounded diagnostic witness
  to `FoldStep`, without a transfer API, allocator framework or native/model
  concepts. This raises the identified allocation from 60 to 61. Core R14 owns
  transfer identities, requested/realized amounts, availability/capacity,
  conversion, conservation, lifecycle accounting and user-facing status.
  The first real R16 model remains `nutrient_limited_growth`: changing nutrient
  field → maintained per-cell amount/count → per-cell intracellular dynamics →
  conservative uptake and motion → division/retirement → observation and
  off-cadence continuation. Current Potts can prototype its one-way subset, but
  the full maintained model must wait for R14/R15 rather than freezing today's
  manual bridge state, tuple-path profiles and duplicated native initialization
  into PottsModels.

- **R49/R50 hosted-Metal correction (2026-09-14):** the current published
  Core R49 tip is `b4e5bda` and the current published Potts R50 tip is
  `0994c492`; both supersede the execution-identical compiler-contract tips
  recorded below. Core's current hosted run is now fully green: compiler
  evidence, docs, macOS smoke, all three real-Metal shards, the stable aggregate
  Metal status and the complete package job; the package job took 2h08m58s.
  Core's prior monolithic hosted Metal job was cancelled by its
  180-minute limit after its preceding semantic groups had passed through the
  lifecycle integer-bounds witnesses. It did not report a product assertion
  failure. The unchanged 25-witness inventory now runs through three durable
  semantic groups of 8/8/9 witnesses, while one stable aggregate `metal` status
  preserves branch-protection and automerge meaning. Potts's prior hosted Metal
  job reached 350 passing assertions and then reported six fixture errors
  because the reusable mixed-symbolic-mutation fixture referred to the public
  `CorePotts` SPI without importing its direct dependency in the standalone
  Metal process. The fixture now owns that explicit import; its focused CPU and
  inventory run passes 344/344. Potts's unchanged 19-witness semantic inventory
  now runs as two failure-local groups, again retaining a stable aggregate
  `metal` status and the no-selector complete local runner. Julia syntax, YAML,
  inventory uniqueness/completeness and diff checks pass for both changes.
  The first sharded Potts run exposed a host-runner inventory construction bug
  before compiling any witness: `reduce(vcat, values(named_tuple))` retained the
  two shard tuples as elements. Commit `53d9d47c` flattens the immutable groups
  explicitly for both inventory and no-selector execution; a direct Julia shape
  check passes and hosted witness qualification has restarted. This is a test
  dependency/CI-runtime correction, not a GPU-only scientific path or a claim
  that cold compilation has been solved.

- **R50 immutable CPU/replay qualification (2026-09-14):** at exact Potts
  commit `a82db270`, replay passes 249/249 (including the 29 new maintained
  native-snapshot assertions), integration passes 166/166 when combining the
  161 non-distributed assertions with the unsandboxed 5/5 distributed row, and
  the direct owning units pass scalar aggregates 149/149, operational operand
  canonicalization 16/16, aggregate operational ordering 6/6 and scientific
  operation SPI 69/69. Ordinary runner inventory parity passes for all 90 test
  files and 21 shared fixtures. The only first distributed attempt failed
  before testing because the filesystem sandbox denied the localhost worker
  socket; the ordinary unsandboxed rerun is the authority. Commit `b07a77de`
  changes only the Metal fixture dependency and CI runner partitioning, so this
  remains immutable product-behavior evidence while hosted checks qualify the
  current tip. Parent Potts R11/PR #54 now carries the same explicit fixture
  import and responsibility-sharded package qualification at `4cec5535`;
  R50 tip `53d9d47c` records that repaired parent and assigns its three
  additional aggregate units to the quantity/publication shard without changing
  the already-qualified R50 product tree. Superseded
  hosted runs were cancelled so the current parent and stacked tips own the
  remaining qualification work.

- **R49/R50 publication and review correction (2026-09-14):** Core R49 is
  published at `ddb52a9` in draft
  [CorePotts PR #34](https://github.com/PraneethMerugu/CorePotts.jl/pull/34);
  compiler evidence, docs, macOS smoke and the complete package job are green
  (the latter in 2h05m52s), while real Metal remains in progress. Potts R50 is
  published at `a82db270`
  in stacked draft [Potts PR #55](https://github.com/PraneethMerugu/Potts.jl/pull/55)
  on R11/PR #54. Its first hosted candidate passed compiler evidence, exact
  replay, integration and macOS smoke, but independent review correctly blocked
  readiness before final qualification. Commits `0d7fb80d`, `186a4772` and
  `ce7e03fa` remove unused duplicated aggregate-analysis fields and incidental
  graph-order assertions, memoize author-invariant expression topology per
  lowering traversal, and separate author-sensitive semantic/deduplication
  identity from physical aggregate layout identity. A forty-level shared DAG
  with over one trillion paths completes its two topology/observability checks
  in 0.2s. A two-descriptor direct/scaled aggregate witness that independently
  swaps author names passes 6/6 and preserves tracker-plan type, complete Core
  program type, one `advance_mcs!` MethodInstance and numerical behavior. The
  final host lowering report is 770 typed statements, 402 calls, 194 raw `Any`
  SSA entries, zero `Any` argument slots, a concrete return and one observed
  lowering MethodInstance; compared with 561/286/147 before layout separation,
  the larger cold compiler body is accepted evidence for the explicit semantic/
  operational boundary, not a hot-kernel improvement claim. Final commit
  `fb942644` additionally restores aggregate-closure validation during completion
  for reusable multi-domain children whose lattice-dependent analysis is
  deferred; its focused scalar aggregate unit passes 149/149. Independent final
  review reports no remaining code, authority, author-identity, CI-definition or
  documentation blocker. Clean-tip CPU/replay and exact-tip hosted Metal
  qualification remain in progress. Code-equivalent clean `ce7e03fa`
  real-Metal qualification passes 72/72 with scalar indexing disabled: 48/48
  evolving scalar/vector/
  tensor sum assertions in 17m16.7s and 24/24 bounded-minimum assertions in
  5m50.2s against Core `ddb52a9`, LocalMath `f41a37d`, Metal 1.11.0 and
  KernelAbstractions 0.9.42. The later final-tip changes affect only current
  documentation and completion-time validation/tests, not valid-model lowering
  or execution; hosted Metal on `fb942644` remains the exact-tip authority.
  The frozen `fb942644` exact replay passes 220/220 in 4m23.3s test time
  against the same Core/LocalMath tuple. The full integration rerun was stopped
  during cold precompilation because newly identified G06/G07 acceptance
  canaries will intentionally change its inventory; qualifying a superseded
  integration set would waste CI and local compilation time.
  Commit `cf27f286` adds the bounded G07 conjunctive canary without delivering
  G07 early: maintained per-cell sum → published cell state → `Every(2)` held
  native input/output → off-cadence checkpoint continuation passes 29/29 against
  an independent analytic ODE result. Commit `a82db270` reuses one shared
  bounded spatial-relation Hamiltonian fixture and ordered full-lattice oracle
  on Sequential/Checkerboard CPU and actual Metal. Its focused CPU file passes
  69/69; the Metal file passes 12/12, including 8/8 assertions for a favorable
  accepted transition, unfavorable energy rejection and CPU/device parity with
  scalar indexing disabled. No product executor or premature G06/G07 machinery
  was added. The actual package-declared maintained PottsModels composition
  versus interactive-equivalent execution identity remains a downstream-
  candidate freeze condition; current Models main has no maintained/native
  composition, and fabricating a canary-only production model would violate
  model ownership and dependency order.
  A clean exact-commit compiler report at `a82db270` is 57,851 bytes with
  SHA-256 `a3949eb1064e5120289a7458aa27344393d466be62daef076c4cd6573d57ac36`.
  It confirms the 770/402/194 aggregate metrics, zero `Any` arguments, concrete
  return, one method/MethodInstance across baseline/rename/numerical variants,
  identical typed IR and identical tracker/Core types. It retains the honest
  next-boundary evidence: complete execution lowering is 416 statements/231
  calls/123 raw `Any` entries with zero `Any` arguments but a non-concrete
  `_PottsExecutionPlan{P,...} where P` return; warm Core/public MCS paths still
  allocate 1,288/1,356 times and source/parameter publication 1,678/1,602 times.
  No zero-allocation whole-MCS or timing-threshold claim is made.

- **R50 readiness audit (2026-09-14):** the clean `dd1ef901` Potts candidate is
  compatible with local Core `ddb52a9` on its central 118/118 public aggregate
  canary, but is not review-ready. First publish and freeze the qualified Core
  dependency, then atomically repin the ordinary CI/docs, exact-replay and Metal
  environments and qualify that immutable tuple. R50 still owes the G06
  transition/relational-dependency and G07 held/native-snapshot canaries;
  package-declared PottsModels versus equivalent interactive-composition
  identity; current, entry/candidate/hypothetical, held/native-sampled and
  historical/retained aggregate consumption including negative hypothetical
  minima; relation multiplicity/measure, source-parent invalidation and explicit
  empty finalization; the complete scalar/minimum/vector/tensor/scheduled
  behavior cohort; integration, replay, strict docs, macOS and real-Metal
  qualification; and durable compiler/allocation evidence for the public
  lowering boundary. The current disposable environment is useful compatibility
  evidence only and does not substitute for that exact-tuple acceptance.

- **R50 local replay and integration canary (2026-09-14):** a disposable copy
  of the repository replay profile was resolved without changing checked-in
  manifests against LocalMath `f41a37da99c31781d4d2b23678a8e729845306a1`,
  Core `ddb52a9272777f442ab4194c7c16423aee169f28` and Potts
  `dd1ef901ce4daee7f2d145905df4d36ef755e2e9`. Native replay passes 220/220 in
  4m14.7s and the complete integration suite passes 166/166 in 6m27.9s. The
  resolved temporary Project/Manifest SHA-256 values are respectively
  `59796f7c3249ca1fd0f776209aee6e3edd4b23e0018162fc63fc809862dd8835` and
  `254a17408ed3af1f769de75b679eea1456f045eaf5ce50b41aef5583ebe3c09d`.
  This advances behavior and continuation confidence but is deliberately not
  called exact replay qualification: the checked-in immutable profile still
  requires the published Core commit and atomic repin described above.

- **Current compiler-chain pointers (2026-09-14):** Core R49 is published at
  `b4e5bda`; Potts R50 is published and clean at `0994c492`. Both remain draft
  dependencies under hosted qualification and review. These pointers supersede
  historical “published and clean” wording in dated checkpoints below.

- **R49 lifecycle relationship boundary qualified locally (2026-09-14):** the
  relationship staging kernel now receives a private prepared descriptor/rule
  recipe plus a state view containing only request selection, descriptor/anchor,
  staged cell kinds, staged relationships and status. It no longer receives the
  whole checkerboard program state or lifecycle workspace; the host wrapper also
  drops its unused runtime argument and the displaced action overload is deleted.
  On the same nonempty-rule scientific fixture, the exact boundary payload falls
  from 26,307 B to 4,368 B (83.4%). Optimized KernelAbstractions typed code grows
  from 348/188/97 to 546/278/166 statements/calls/`Any` SSA entries, with zero
  `Any` slots, one typed method match and concrete `Nothing` before and after.
  The first 80 post-cut `Any` entries inspected were branch/goto control-flow
  nodes; that partial inspection did not classify all 166 and is not a root-
  inference claim. The increase exposes more relationship control flow in the
  root kernel and is not claimed as an IR improvement. The
  ABI/readability cut is retained because it removes unrelated semantic payload,
  preserves one host/device path and passes the authorities: the new two-engine
  CPU witness passes 28/28, its real-Metal checkerboard witness passes 14/14 with
  scalar indexing disabled, the focused lifecycle/relationship cohort passes
  1,138/1,138, the complete 64-unit CPU suite passes 32,847/32,847, and strict
  docs pass. This selects the surviving relationship rule/slot control-flow
  family as later compiler evidence rather than motivating LLVM-facing tricks.

- **R49 relationship payload and evidence refinement (2026-09-14):** Core
  commit `ddb52a9` removes selection allocations/source maps
  from relationship staging, replaces the complete backend control with a
  cadence-counter view, and makes host/backend action filtering call the same
  relationship-rule mutation implementation. On the real nonempty incompatible-
  removal fixture, the aggregate kernel payload is 2,043 B (308 B recipe,
  1,671 B state, 64 B cadence), down 92.2% from the original 26,307 B boundary.
  Optimized KA typed code remains 546 statements/278 calls/166 raw `Any` SSA,
  with zero `Any` argument slots, concrete `Nothing`, and one typed method match;
  the checked-in classifier identifies all 166 as non-value control nodes.
  This is therefore an additional ABI/readability cut, not an IR-count claim.
  The new standalone report also records the prepared owner-transfer boundary
  at 819/454/230 and the unchanged proposal leaf at 72/35/26; 228 of the owner
  entries are non-value control and two remain conservatively `other` rather
  than being mislabeled. An explicit fresh-process MethodInstance probe proves
  reuse across a numerical destination-kind change and a one-to-two relationship-
  rule count change. The two admitted action tags intentionally form two
  MethodInstances under one generated kernel Method definition and have equal
  546/278 size but different typed IR. A path-filtered CI job uploads this TOML
  evidence plus the resolved Manifest without thresholding counts, bytes or
  time. The focused CPU behavior passes 51/51 and the real Metal relationship
  witness passes 14/14 in 5m33.4s with scalar indexing disabled. The complete
  CPU suite passes 32,877/32,877 across 65 units in 75m50.4s, including the
  focused allocation contract and new 1.86s report smoke. Strict docs pass
  through doctests, cross-references, checks and HTML rendering. An initial docs
  invocation used relative load-path entries that became invalid when
  Documenter changed directories; the authoritative absolute-path rerun passed.

- **Compiler-tractability plan precision strengthened (2026-09-14):** the
  identified allocation remains 60 PRs; no standalone optimization PR was
  added. The amendment, dependency map, composition roadmap, ideal API spec,
  contributor workflow and normative charter now agree on the complete
  declaration → semantic owner → dependency/effect analysis → operational
  recipe → narrow state view → kernel → inspection/test chain. Kaimon is the
  primary diagnostic; when it cannot attach to the exact candidate worktree,
  optimized exact-typed evidence is an accepted rapid-development fallback only
  with the reason, exact tuple, unchanged control, common metrics and a
  checked-in reproducible runner. R49 now delivers that runner rather than
  leaving the durable baseline in temporary scripts. The canonical R16/R17/R20
  PottsModels workload is now explicitly changing field → maintained per-cell
  aggregate → intracellular dynamics → conservative exchange/motion → division
  → observation → checkpoint continuation, with multiple consumers and
  finite-resource contention; R52 later extends the same workflow with FBA
  contention. Stable inexpensive contract properties may become ordinary tests,
  while statement/call counts and machine timings remain trend evidence. This
  strengthens existing R49/R50/R16/R17/R20/R52 responsibilities, not an
  implementation or qualification claim.

- **Compiler metric terminology correction (2026-09-14):** throughout dated
  notes below, a historical “one exact specialization” derived from
  `length(code_typed(...))` means only one typed method match for the queried
  exact signature. It does not establish MethodInstance reuse across authored
  names, numerical values, recipe counts or model compositions. R49's durable
  runner records `typed_method_matches` and must use a separate variant identity
  probe before making a specialization-family claim. Raw `Any` SSA is likewise
  syntax-classified: `GotoNode`, `GotoIfNot` and `ReturnNode` are non-value
  control; `PhiNode`, `PhiCNode`, `PiNode` and `UpsilonNode` remain separate
  classes and cannot be dismissed as control-flow erasure.

- **Operational-recipe compiler contract accepted across the chain
  (2026-09-12):** the identified allocation remains 60 PRs. The compiler
  amendment, dependency map and composition roadmap now require one traceable
  path from expressive authoring through rich semantics and validated
  normalization into compact operational recipes, narrow typed state views and
  small concrete kernels. Recipes are private sole execution lowering, not a
  second IR or scientific authority. R49/R50 establish the reusable boundary,
  specialization policy, boundary-size/root-inference probes and cutover; R20
  owns the longitudinal public-model workflow; every later feature owner must
  reuse an established operation family or supply feature-local evidence for a
  genuinely new semantic family. PottsModels corpora record recipe shape/count,
  payload size, staged cold latency, typed IR/calls, specialization/code growth,
  allocations and throughput while package and interactive equivalents share
  execution identity. Actual Metal and behavioral tests remain authoritative.
  The normative amendment now also retains the exact 3,730-statement/2,112-call/
  1,017-`Any` G05 owner-change baseline and its 480 B/232 B/9,600 B/392 B
  boundary inventory as a durable comparison point, explicitly treats root
  erasure, code shape, specialization and compile latency as joint fitness
  dimensions, and names representative stable operation families without
  prescribing a new hierarchy. The ideal API spec now carries the complete
  recipe → state-view → kernel contract and requires every new capability to
  identify that lowering path. This is accepted planning scope, not an
  implementation or performance claim.

- **G04/G05 publication-scope and recovery correction (2026-09-12):** R09 was
  rebuilt so the G04 parent no longer contains the G05 scalar aggregate commit;
  the displaced aggregate, fixed-array residual, minimum, and structured
  aggregate closure now form the R11 child in dependency order. R09 also pins
  the exact published G04 Core `9b130057` and LocalMath `22e7b429` tuple in
  ordinary docs and exact replay. Exact replay passes 220/220, the focused
  fixed-array/quality cohort passes 121/121, and the ordinary two-CPU-engine
  cell-process contract passes 23/23. The latter exposed and closes a shared
  initialization defect: symbolic array declaration keys were defensively
  copied into value arrays and lost their identity. Commit `4fc9277f`
  normalizes every supplied initial-state key once to its semantic `Symbol`
  before copying values. The exact typed boundary remains 12 statements, two
  calls, zero `Any` slots and one `Any` SSA entry before and after, while its
  retained key narrows from `Symbolics.Arr{Num,1}` to `Symbol`; this is a
  semantic-payload correction rather than an IR-size claim. R09 is published at
  that tip; protected changes, exact replay, integration, macOS smoke and docs
  pass, while package and actual Metal remain in progress. Independently, Core
  G05 hosted package and Metal exposed the same remaining recovery boundary:
  foreign-task receipt ownership was correctly rejected by LocalMath, but the
  checkerboard recovery translator wrapped that public validation in
  `LifecycleBackendFailure`. The package run otherwise passed 32,805 assertions
  and the Metal run otherwise passed 366 lifecycle assertions, including every
  preceding minimum and structured-sum group. Core commit `5900248` had
  centralized shared recovery translation without a GPU-only path; its earlier
  two-engine owner contract passed 83/83. Kaimon/code-typed comparison records enqueue at
  51/27 before and 47/27 after, settlement at 16/6 before and 18/8 after, a new
  two-statement/one-call helper, and an unchanged 202/112 control, all with zero
  `Any` slots and one exact specialization. Core commit `418197b` now preserves
  raw `LocalMathValidationError(contract=:receipt_owner)` through both ordinary
  settlement and recovery while retaining ranged lifecycle wrappers for actual
  backend failures. Against exact LocalMath `f41a37d`, the two pending/settled
  ownership regressions pass 42/42 in 5m43s. The predicate is four statements/
  two calls for an ownership validation and one/zero for an unrelated exception,
  with concrete `Bool`, zero `Any` slots and one specialization in each case.
  The complete exact lifecycle file also passes 773/773 in 29m24.3s. The commit
  is published; protected changes, docs and macOS smoke pass, while package and
  actual Metal are running. Corrected R11 is restacked from local tip
  `6c637757`. After its hosted Metal run exposed the product-coercion boundary
  described under R49 below, it now pins Core `a4fb6c8`/tree `08fdada3` plus
  LocalMath `f41a37d` independently in CI, docs, replay and Metal profiles. The exact-tuple
  cell-process, fixed-array, vector-aggregate and minimum-authoring cohort passes
  169/169 in 7m36.9s. The device-safe ref refresh is published at `9e3e105f`;
  all protected hosted jobs have restarted and are pending. Independent review
  remains authoritative for readiness.

- **Cold-compilation audit accepted into existing owners (2026-09-11):** the
  identified allocation remains 60 PRs. Research across ModelingToolkit/
  Symbolics, SciMLBase/OrdinaryDiffEq, Lux, StaticArrays and the JuliaGPU stack
  confirms architecture before caching: stable homogeneous cold representations,
  a preparation boundary, a small reusable hot signature, bounded static
  structure and a representative precompile corpus. R49 now owns canonical Core
  executor identity across author-only renames, numerical value changes and a
  one/two/four/eight/sixteen entry ladder within one admitted capacity. R50 owns
  author-identity/irregular-graph erasure and equivalence of PottsModels and
  interactive lowering. R20 owns the three-model public latency corpus,
  fresh-process stage decomposition, MethodInstance/code/cache growth, and
  optional developer sysimage/disk-cache experiments. The compiler amendment and
  ideal API spec explicitly reject arbitrary author facts in types, large static
  unrolling, combinatorial precompile matrices, premature public specialization
  modes, generated-device concealment, GPU-only science, cache-as-architecture
  and serialized device/compiler handles. This is accepted scope, not
  implementation, measured improvement or qualification.

- **Allocation-tooling amendment accepted into the chain (2026-09-11):** the
  identified allocation remains 60 PRs. R49/Core owns focused AllocCheck checks
  for exact prepared lifecycle/update signatures plus warmed observed zero-heap-
  allocation tests for declared fixed-capacity CPU boundaries. R50/Potts extends
  those checks through public lowering and requires author-only quantity identity
  changes to share the same hot payload/specialization class. R49/R50 and
  R20/Models use Chairmarks for preparation, first-execution, warm time,
  allocation-count and allocation-byte samples; R20 preserves the public-model
  longitudinal corpus. TestNoAllocations is not selected because it supplies no
  independent authority beyond the warmed observed-call checks. The target
  requires allocation-free device kernels; backend host launches, authoring,
  compilation, construction, resizing, checkpoint creation, diagnostics and
  transfers are measured separately and are not blanket zero-allocation claims.
  Kaimon still owns typed-IR/specialization evidence, ordinary tests own science,
  and real Metal remains the backend authority. The focused allocation target is
  deliberately small so it does not repeat or further lengthen the full package
  suite. This is accepted implementation scope, not completed tooling or a new
  qualification result.

- **R49 next-boundary audit (2026-09-11):** read-only review of G05 `dfe5c95`
  selects the structural-lifecycle accepted-update ABI as the first measured
  G05C cut after a correct G05 baseline. Cold preparation should derive compact
  update entries once from `TrackerExecutionPlan`/`TrackerContract`; launch
  binding should pass only values, ownership geometry, compiled sum expression,
  exact source arrays, parameters and descriptor-specific update data. Author
  quantity identities and support/checkpoint/cost metadata do not cross the
  device boundary, and reconstruction-only minimum entries remain exclusively
  owned by the existing LocalMath reconstruction law. The current path rebuilds
  contracts and walks the descriptor/state shape across entry preflight,
  validation, application, completion preflight and finish. Ordinary
  checkerboard accepted-copy lowering is already host-lowered into LocalMath
  laws and is explicitly outside this first replacement. The compiler amendment
  records exact probe families and specialization-identity checks. This is a
  measured implementation candidate, not completed code or a frozen public API.

- **R49 exact owner-change baseline (2026-09-12):** isolated branch
  `codex/quantity-consumption-contract` now starts from Core G05 tip
  `418197b`; its qualifying tuple uses LocalMath `f41a37d`. The canonical checkerboard lifecycle
  fixture includes ownership, moments, grouped minimum and grouped sum. Optimized
  `code_typed` for `_stage_owner_change!` is 3,730 statements/2,112 calls with a
  concrete `Bool` return, zero `Any` argument slots, 1,017 `Any` SSA entries and
  one exact specialization. Its arguments carry a 480-byte structure runtime,
  232-byte structure plan, 9,600-byte lifecycle workspace and 392-byte tracker
  source; only mode/index/new-owner are isbits. This selects the next measured
  cut: prepare an incremental accepted-update recipe on the host, exclude the
  reconstruction-only minimum, and bind a small staged owner-change state view
  rather than passing broad runtime/plan/workspace objects. The first isolated
  source cut now prepares only old/new-owner update entries and binds their
  staged values before launch. A 1,059-assertion focused run passed all 1,055
  non-ownership assertions; its four failures exactly reproduce the upstream
  G05 ownership-wrapper defect. That run used LocalMath G04 `22e7b429`, so it is
  diagnostic rather than qualifying evidence. A clean R49 environment pinned to
  `f41a37d` now owns the authoritative rerun and compiler probes. On that exact
  tuple, optimized `_stage_owner_change!` narrows from 3,730 statements/2,112
  calls/1,017 `Any` SSA entries to 3,660/2,083/991, with zero `Any` argument
  slots, concrete `Bool` and one exact specialization on both sides. This is a
  real but modest reduction: the narrowed runtime grows from 480 to 712 summary
  bytes because selected tracker values moved into it, while the still-broad
  9,600-byte lifecycle workspace, 232-byte plan and 392-byte source remain.
  Static review therefore finds the first cut insufficient for completion: its tuple-shaped recipe
  still specializes on entry count, so repeated incremental entries must move
  to a bounded value-level family representation before the required
  one/two/four/eight/sixteen identity test can pass. Nothing is committed or
  published; G05 correctness and actual Metal remain prerequisite authorities.
  Applying the accepted operational-recipe contract, the next isolated cut gives
  `_stage_owner_change!` an explicit state view containing only staged ownership,
  cell kinds, host tracker values (or `nothing` for backend execution), descriptor
  state and status. This reduces that argument's summary size from 9,600 to 1,012
  bytes while the optimized body remains exactly 3,660 statements/2,083 calls,
  991 `Any` SSA entries, zero `Any` argument slots, concrete `Bool` and one exact
  specialization. The unchanged IR counts make this a readability/runtime-ABI
  narrowing, not an inference claim, and select the tuple-shaped recipe as the
  next inference owner. Three exact focused lifecycle units passed; their run
  was stopped when the recipe representation changed, so it is diagnostic rather
  than qualification for the current candidate.
  The next candidate replaces the lifecycle-only dense update tuple with a
  power-of-two bounded recipe family whose active count is value-level: one,
  two, four, eight and sixteen members have exactly the same prepared type, and
  seventeen begins the next capacity class. The owning source-aware tracker unit
  passes 194/194, including the new identity test. For the canonical one-member
  fixture, the stable-capacity representation grows `_stage_owner_change!` from
  3,660/2,083/991 statements/calls/`Any` SSA entries to 3,825/2,131/1,061 and
  grows the structure runtime from 712 to 1,792 summary bytes; argument slots
  remain concrete, return type is `Bool`, and exact specialization count is one.
  This is a measured per-instance cost in exchange for eliminating count-driven
  types through sixteen. At the focused entry-validation boundary, the five old
  types total 513 typed statements, 282 calls and 136 `Any` SSA entries, while
  the one bounded type is 121/62/37—a 76%/78% reduction in aggregate statements/
  calls across the declared ladder. Probe compile-allocation/time values are
  order-sensitive because the bounded method was exercised during fixture
  construction, so they remain diagnostic rather than comparative evidence.
  The actual maintained-site-tracker lifecycle witness passes 370/370 on Metal
  in 37m01.8s, covering grouped sum, minimum reconstruction, overflow, recovery,
  rollback, continuation and receipt ownership on the exact candidate tuple.
  The final exact five-unit CPU cohort passes 1,349/1,349, including source-aware
  trackers and the comprehensive lifecycle unit; elapsed time is not a benchmark
  because the typed-IR probe initially ran concurrently. The strict documentation
  build also passes. The focused final-type Metal owner-change witness passes
  15/15 in 9m05.1s.
  A field-provenance audit removed the group quantity identity and cold source-
  handle tuple from the final runtime recipe because bound descriptors already
  own the resolved execution inputs; this accounts for the 64-byte reduction
  from the earlier 1,856-byte candidate without changing typed IR.
  Potts R11's hosted Metal suite then exposed a separate device boundary in the
  same Core parent: nested lifecycle state coercion retained a recursive
  `Tuple`/`Val` call after heterogeneous evaluator-bank dispatch, and Metal
  rejected it as an unsupported dynamic invocation. The G05 parent now
  lowers that target-shaped product check into explicit leaf checks while
  retaining the same host/device coercion path and failure semantics. The exact
  CPU conversion contract passes 26/26 direct checks and 460/460 lifecycle
  assertions; the corresponding real-Metal product-state witness passes
  230/230 in 55m05.6s. Kaimon on the exact G05 parent reports the deceptively
  small deferred recursive body at 38 statements/20 calls/13 `Any` SSA entries;
  exact-candidate `code_typed` reports the resolved leaf body at 126/71/43.
  Both return concrete `Bool` with zero `Any` slots and one specialization. The
  larger typed body is accepted because it replaces a hidden dynamic device
  call and the authoritative Metal behavior passes; raw IR size is evidence,
  not the goal. The coercion correction is published on its owning G05 parent
  as `a4fb6c8`, updating CorePotts PR #33. R49 is published as rebased commit
  `3de4f0c` in draft [CorePotts PR #34](https://github.com/PraneethMerugu/CorePotts.jl/pull/34),
  stacked on that parent. Its worktree is clean; hosted qualification and
  independent review remain pending.

- **R50 resolved aggregate-fact checkpoint (2026-09-12):** isolated branch
  `codex/resolved-quantity-lowering` is stacked on Potts R11 `9e3e105f` and
  selects Core R49 `3de4f0c` plus LocalMath `f41a37d`. Its first coherent slice
  gives aggregate analysis one concrete node-aligned `AnalyzedSiteAggregate`
  fact containing the maintenance law, contribution root, qualified site/cell
  resources, two policy operands and transitive contribution dependencies.
  Scope validation no longer repeats source interpretation. Tracker identity,
  descriptor construction, state retention and evaluator lowering consume the
  fact; evaluator lowering receives a node-aligned narrow union of sum/minimum
  qualified keys rather than recomputing a string identity. Canonical string
  identity remains only inside host deduplication and is discarded after recipe
  construction. The public rename witness proves two programs with different
  system, domain, kind, scope, process and protocol names retain distinct host
  resource identities while sharing analyzed-fact types, semantic indices,
  compiled Core program type and tracker-plan type.

  The first inline candidate exposed a real host compiler regression: exact
  optimized tracker lowering grew from the Kaimon R11 baseline
  787/392/236 statements/calls/`Any` SSA values to 1,213/663/320, with zero
  `Any` slots and one inferred result on both sides. Replacing the root
  `Vector{Any}` handle table and parametric fact with one concrete analyzed fact
  plus a bounded sum/minimum-key union reduced that candidate to 1,136/604/312.
  The final semantic split makes aggregate recipe construction its own named
  host owner. The unrelated tracker coordinator is now 509/272/149, while the
  new aggregate-recipe owner is 637/338/165; each has zero `Any` slots and one
  inferred result. Do not sum these as a claimed global reduction: the baseline
  also called separately compiled source/descriptor helpers that its root IR did
  not inline. The evidence establishes a narrower coordinator, local explicit
  host heterogeneity and the next measurable boundary; it does not yet establish
  lower total compile latency.

  Final focused public sum/minimum behavior passes 142/142 in 6m41.2s. The
  aggregate worker reports approximately 34.4 GB of allocation during its cold
  compile/setup/execution unit; this is not a warmed-runtime allocation claim
  and reinforces the R50/R20 staged-latency work. Nearest compiler source maps
  document the sole fact → recipe → handle path. This checkpoint is saved
  locally as `a6fb9d8c`.

  A second checkpoint at `857f1804` exercises ordinary symbolic composition
  across two maintained quantities and one direct cell-state read. Its public
  model derives per-cell average from maintained mass and ownership count,
  publishes the average plus a direct baseline to two consumers, changes both
  field and parameter sources, and proves checkpoint continuation under
  `SequentialCPM` and `CheckerboardSweepCPM`. It reuses exactly one sum tracker,
  one ownership-count tracker and the ordinary expression evaluator; no
  aggregate-specific executor was added. The focused owner unit passes 107/107
  in 7m53.5s. Relation/measure/numerical and temporal/context distinctions,
  external extension boundaries, allocation probes, downstream canaries,
  strict docs, full owner/integration and actual Metal remain required before
  R50 readiness. The branch remains local and unpublished.

  A third checkpoint at `3991655a` qualifies the public external-operation
  boundary inside maintained contributions. A versioned, context-free,
  extension-owned operation remains in the normalized graph, appears in the
  aggregate fact's transitive dependencies, lowers to the existing tracker
  evaluator and executes source refresh under both CPU algorithms. A declared
  pure operation whose concrete callable captures a mutable vector is rejected
  during public problem completion with
  `device_illegal_operation_callable`; purity metadata does not bypass the
  immutable execution-payload contract. The focused owner unit passes 114/114
  in 9m15.8s. Its worker reports approximately 44.3 GB of allocation across
  cold package loading, compilation, setup and execution, which remains setup
  evidence rather than a warm-runtime allocation claim. External contextual
  source bindings and the eventual Metal declaration still require applicable
  qualification before R50 readiness.

  A fourth checkpoint at `427bbd95` makes specialization reuse explicit across
  author identity and numerical configuration. Baseline, fully author-renamed
  and doubled-parameter-default systems retain one compiled Core program type,
  tracker-plan type and tracker-instance type family. The numerical default is
  still runtime scientific data: the baseline and doubled systems publish
  `Float32[3, 3, 0]` and `Float32[6, 6, 0]` respectively after the same accepted
  step. The focused owner unit passes 118/118 in 9m16.9s and reports about
  44.7 GB for its complete cold worker; the strict documentation build passes.
  This qualifies specialization-family stability for the exercised scalar CPU
  aggregate path, not a global compile-latency or device claim.

  The public staged-latency runner at `dd1ef901` uses Chairmarks 1.3.1 and the
  exact local Potts/CorePotts/LocalMath candidates (with ModelingToolkitBase
  1.70.0 and Symbolics 7.39.2) to separate authoring, problem reconstruction,
  preparation, first execution and warmed execution. A representative fresh
  run measured authoring 7.73s/1.22GB (7.19s compilation), problem reconstruction
  110ms/16.2MB, preparation 168.03s/18.39GB (166.83s compilation), and first
  public execution 2.94s/176.5MB (2.94s compilation). The warmed public step
  measured a 138.6μs median with 1,415 allocations/81.45KiB; the same model's
  already-lowered Core MCS measured 131.3μs with 1,345 allocations/75.91KiB.
  First source and parameter publication measured 3.21s/447.8MB and
  255ms/17.2MB respectively, almost entirely compilation. Warm source and
  parameter publication both measured about 3.7ms and 58 thousand
  allocations/3.35MiB.
  Whole-MCS execution is therefore not claimed allocation-free. The enforced
  zero-allocation contract remains the narrower prepared update/contribution
  leaves owned by R49; R50 demonstrates that public aggregate authoring lowers
  into that sole tracker/update implementation and reports the real surrounding
  costs without a brittle threshold.

  After the R49 interface froze locally at `ddb52a9`, an isolated R50
  qualification environment resolved the clean Potts `dd1ef901`, Core
  `ddb52a9` and the existing LocalMath worktree without modifying any package
  checkout. Its Project/Manifest SHA-256 values are respectively
  `fac356985fd31c747483bb502257c4deb6d03bdb8baf84c5f85fba944592aa8a` and
  `2ed5cbb0d928ab3e4ca45b6c947a8fcf56ce46119cf757a07006b70da38855fc`.
  The complete public scalar-aggregate owner unit passes 118/118, covering
  two-consumer maintenance, analyzed facts, author rename/numerical-value
  execution identity, extension-owned operations, mixed direct/aggregate reads,
  exact ownership-count reuse, scope isolation, atomic source/parameter
  publication, tolerance/physical-unit admission, both CPU algorithms and
  checkpoint continuation. Two older ad hoc environments first proved to lack
  direct setup dependencies; they precompiled the package but ran no assertions
  and are not qualification evidence. No R50 source change was required for the
  frozen Core contract.

  A 5% Julia allocation profile of the warmed source update captured 3,016
  samples. LocalMath closed-callable effect analysis owned 2,428 samples,
  followed by pointwise safety analysis, structural binding and stage planning.
  Core's `_execute_site_tracker_rebuild` currently rebuilds the LocalMath law and
  calls `prepare` for each source/parameter publication. This localizes the next
  tractability boundary: retain/reuse the already-validated operational recipe
  while preserving task ownership, candidate-state atomicity and the same
  backend execution path. Potts saved-state publication is not the first target;
  it accounted for only one sampled 1,008-byte allocation in this profile.

- **R49 retained tracker recipe refinement (2026-09-13):** Core commit
  `fdf5672` moves the unchanged source-dependent tracker law across a narrower
  operational boundary. Materialization validates and plans each LocalMath
  reduction once; the runtime retains that host-only plan with backend staging
  buffers and typed scratch output, while each invocation prepares the plan
  task-locally and executes the same LocalMath path. Current ownership,
  parameters and only the declared state blocks are copied into the recipe.
  The recipe is erased from `ProgramRuntime` specialization, and publication,
  staged transaction prevalidation and scheduled-source refresh all consume the
  same runtime-owned recipes. No prepared task state is shared and no CPU/GPU
  scientific fork was added. A real Metal structured-value test first exposed
  scalar iteration through generic `copyto!(MtlArray, BlockView)`; the final
  shared representation-level copy uses the contiguous block storage contract
  on every backend and then passed Metal input publication 79/79, structured
  owner sums 24/24 and site-tracker lifecycle 370/370.

  The exact Core CPU package suite passed 32,819/32,819 across 63 units in
  67m17.6s, and strict documentation passed doctests, references, link checks
  and HTML rendering. The final removal of now-unused backend/copy keyword
  arguments was followed by a focused 1,849/1,849 CPU cohort spanning combined
  publication, sequential/checkerboard transactions, source-aware and scheduled
  trackers, lifecycle reconstruction and adaptation. Potts R50 then passed its
  exact scalar/vector/tensor/scheduled aggregate cohort 234/234 against the
  committed Core checkout.

  On the same Julia 1.12.6 environment and manifest, seven-sample warmed
  sequential scheduled execution improved from 3.688ms/3,488,336 bytes at
  parent `a6faf5d` to 160.3μs/103,792 bytes, about 23× faster with 33.6× fewer
  bytes. Checkerboard remained effectively unchanged at 322.2μs/152,928 bytes
  versus 339.3μs/152,928 bytes. Construction remains expensive: sequential
  moved from 20.918s/3.769GB to 21.700s/3.923GB and checkerboard from
  206.392s/19.899GB to 206.466s/20.051GB. The R50 public runner likewise reduced
  warm source publication from 3.738ms/58,238 allocations/3.348MiB to
  157.3μs/1,682 allocations/126.2KiB, and parameter publication from
  3.721ms/58,185 allocations/3.347MiB to 147.7μs/1,606 allocations/121.7KiB.
  Public preparation increased from about 167.8s/18.39GB to
  183.5s/18.80GB, so retained-plan construction and duplicate cold work remain
  an explicit next tractability target rather than a hidden success claim.

  Exact final `code_typed` measurement reports one specialization for both
  boundaries: `_input_tracker_candidate` has 23 statements, 12 calls, no
  `Any` slots, six `Any` SSA values and a concrete `TrackerState` return;
  `_execute_input_tracker_recipe` has 483 statements, 216 calls, no `Any`
  slots, 177 `Any` SSA values and a concrete `Vector{Float32}` return. The
  20,205-byte retained plan payload is deliberately cold host state, not the
  final compact operational representation. The larger recipe body includes
  the device-safe `BlockView` copy revealed by Metal and is evidence for the
  next semantic narrowing boundary, not grounds for speculative inlining or a
  second executor.

- **R49 ownership-transfer operational boundary (2026-09-13):** Core commit
  `b33e8e4` replaces the broad `_stage_owner_change!` runtime/plan/workspace
  signature with an explicit `_OwnershipTransferRecipe` and
  `_LifecycleOwnerChangeState`. The recipe carries lattice shape, the caller's
  prepared tracker plan and ownership-clear rules. The state view carries only
  staged ownership, cell kinds, tracker values, descriptor state and status.
  Host structural staging retains its authoritative tracker representation;
  backend staging supplies the already bound admitted incremental subset. Both
  modes execute the same transfer implementation and identical tracker,
  clearing, status and transaction semantics.

  Against the retained G05 baseline, exact optimized `code_typed` measurement
  reduces the boundary from 3,730 to 2,868 statements, 2,112 to 1,610 calls and
  1,017 to 776 `Any` SSA values. It retains zero `Any` argument slots, one exact
  specialization and a concrete `Bool` return. Individually measured argument
  payload falls from about 10.7KB (broad runtime, plan, lifecycle workspace,
  tracker source and scalars) to 2,138 bytes (198-byte recipe, 1,292-byte state
  view, 636-byte source and scalars).

  The exact warmed fixed-capacity CPU path remains allocation-free: AllocCheck
  reports no findings and the observed-call contract passes 7/7 with zero heap
  bytes. Chairmarks reports owner-transfer construction at 61.67s/8.64GB
  (61.48s compilation), first execution at 147.9ms/49.5MB, and a 2.146μs warm
  median. The unchanged contribution control has an 11.25ns warm median. Thus
  the warm transfer is effectively unchanged from the 2.15μs parent reference,
  while first execution improves from 175ms; construction remains about 2.3s
  and 116MB heavier and is recorded as residual cold cost.

  A measured candidate that also forced the host through the backend's padded,
  bound tracker subset reached 2,832 statements, 1,588 calls and 768 `Any` SSA
  values, but regressed the warm transfer to 3.67–3.75μs and took 30m40.7s in
  the Metal lifecycle run. It was removed before the final commit. Retaining the
  host-native tracker representation restored the 2.146μs warm result, while
  exact final Metal lifecycle passed 370/370 in 27m27.3s. This rejects a smaller
  LLVM snapshot as sufficient evidence when it worsens a real admitted path.

  Exact final validation is Core CPU 32,819/32,819 across all 63 units in
  59m45.2s, focused CPU lifecycle 773/773, real Metal lifecycle 370/370, and a
  strict documentation build through doctests, references, checks and HTML.
  The long Metal compile remains concentrated above this smaller leaf; the next
  measured tractability target is the enclosing lifecycle structural
  descriptor/effect dispatch, not speculative micro-optimization inside the
  ownership transfer.

- **R49 lifecycle-structure recipe and state-view boundary (2026-09-13):**
  Core commit `59152a2` moves create, remove, retire, transition and divide
  staging behind one `_LifecycleStructureRecipe` and one
  `_LifecycleStructureState`. The recipe carries value-level lifecycle
  descriptors and the already qualified ownership-transfer recipe. The state
  view binds only cell/tracker state, structural request and partition arrays,
  staged mutation targets and status. A nested selection view retains only
  readiness, count, request/allocation vectors and source positions; a nested
  site index retains only owned-site records, segment starts and source
  positions. Kaimon repository search confirms the complete selection and
  LocalMath compaction workspaces remain on the host side of this binding
  boundary. Host and backend invoke the same effect implementation.

  The retained enclosing baseline crossed 14,234 summary bytes: 1,792 runtime,
  232 plan, 9,536 lifecycle workspace, 392 tracker source and 2,282 control. An
  initial recipe/state wrapper reduced this to 11,790 bytes but still embedded
  the complete selection and site-compaction objects. Real Metal rejected that
  first candidate after 8m28.1s because the new wrappers lacked adaptation;
  adding their ordinary `Adapt` contracts exposed the surviving broad payload
  in the kernel signature. The final purpose-built selection/site views reduce
  the same total to 7,143 bytes (1,636 recipe, 2,833 state, 392 source and 2,282
  control), a 49.8% reduction from the enclosing baseline and 39.4% from the
  intermediate wrapper.

  Exact optimized CPU KernelAbstractions/code-typed results compare as follows
  for statements/calls/`Any` SSA: create 415/224/112 to 412/220/113; retire
  409/221/111 to 406/217/112; remove 643/354/170 to 636/347/171; transition
  452/247/122 to 449/243/123; divide 415/224/112 to 412/220/113. The remove
  effect leaf improves from 229/131/58 to 225/128/58. Every measured boundary
  has zero `Any` argument slots, one exact specialization and a concrete result
  (`Nothing` for the KA kernel wrapper, `Bool` for the effect leaf). This is
  primarily a semantic ABI/readability win; it deliberately does not claim
  that the small `Any`-SSA change is the objective.

  The first final-shape Metal run reached 196 behavioral assertions and then
  exposed an invalid-IR method-error path in the separate lifecycle-state
  kernel. The cutover had accidentally narrowed the shared allocated-generation
  helper to `_LifecycleStructureState`. The correction replaces that implicit
  object contract with `_next_allocated_generation(cell_generations, slot)`;
  both structural and state callers now declare the only storage the semantic
  operation needs. Its focused CPU failure/recovery witness passes 13/13, and
  the corrected complete real-Metal lifecycle suite passes 370/370 in
  28m04.2s. The corrected final source also passes the complete CPU lifecycle
  suite 773/773. A standalone AllocCheck invocation did not terminate after
  extended compiler work and was interrupted without an allocation finding;
  the ordinary full-suite allocation unit subsequently passed the unchanged
  seven static and observed zero-allocation assertions in 89.79s. Final broad
  validation is 32,819/32,819 across all 63 Core units in 66m36.7s, plus a
  strict documentation build through doctests, cross-references, checks and
  HTML.

- **R49 lifecycle-state recipe and state-view boundary (2026-09-14):** Core
  commit `bcb3883` replaces the backend state-rule signature's separate
  descriptor/evaluator plan and complete `LifecycleWorkspace` with one
  `_LifecycleStateRecipe` and one `_LifecycleStateView`. The recipe references
  the already prepared descriptors, evaluators and state rules. The view binds
  only request descriptors/anchors, selected allocation, planned sites and
  partitions, owned-site lookup, staged generations/trackers/state and status.
  Shared selected-request and owned-site views now have durable names because
  both structural and state staging consume them. Host and Metal still execute
  the same state-rule implementation; no second evaluator or scientific
  authority was introduced.

  The exact state-kernel payload falls from 13,969 summary bytes (1,628 state
  runtime, 224 descriptors, 299 evaluator plan, 9,536 workspace and 2,282
  control) to 7,006 bytes (1,628 runtime, 531 recipe, 2,565 state view and
  2,282 control), a 49.8% reduction. Optimized CPU KernelAbstractions/code-typed
  results improve from 551/322/139 to 529/299/140 statements/calls/`Any` SSA
  for create, 495/289/124 to 477/270/125 for retire/remove/transition and
  570/334/143 to 548/311/144 for divide. Every measured action retains zero
  `Any` argument slots, one exact specialization and a concrete `Nothing`
  result. The single additional `Any` SSA is accepted: responsibility and call
  surface shrank materially without encoding the model into larger types.

  Focused CPU lifecycle validation passes 1,488 assertions. The final real
  Metal source passes 1,668 lifecycle assertions, including the canonical
  maintained site-tracker witness 370/370 in 27m22.9s, state composition,
  conversion, history, identity and failure behavior. The complete CPU suite
  passes 32,819/32,819 across all 63 units in 58m53.0s; its allocation contract
  unit remains green. Strict documentation passes through doctests,
  cross-references, checks and HTML. A temporary Metal environment initially
  omitted its direct KernelAbstractions test dependency under Julia 1.12; that
  environment-only defect was corrected before the final authoritative run.

- **Compiler warning follow-up (2026-09-12):** the R50 documentation build
  emitted Julia's `@nospecialize annotation only supported on the first 32
  arguments` warning twice while precompiling Potts. The build itself
  passed. Loading only ModelingToolkit with compiled modules disabled reproduces
  the same two warnings in the same environment, excluding Potts and CorePotts
  source as their owner. ModelingToolkit's public tracker records this warning
  under ModelingToolkitBase precompile work. Treat it as upstream diagnostic
  noise to monitor, not R49/R50 compiler evidence or a local qualification
  failure.

- **R49 focused allocation contract (2026-09-12):** Core commits `b5da131`
  and `a6faf5d`
  adds AllocCheck 0.2 as a test-only dependency and one ordinary focused unit
  over the exact prepared host `_stage_owner_change!` signature plus the
  unchanged bound site-contribution leaf. Both exact call chains report zero
  AllocCheck findings, and separately constructed warmed instances report zero
  observed heap bytes. After sharing its fixture with the measurement runner,
  the unit passes 7/7 in 1m17.5s; its approximately 9.42 GB
  worker allocation includes package/LLVM compilation and fixture construction,
  not the measured calls. The documentation explicitly excludes construction,
  first compilation, checkpoint creation, capacity changes, backend launch and
  transfers from the zero-allocation guarantee. The companion
  `benchmark/prepared_update_contract.jl` uses Chairmarks 1.3.1 and reports
  construction, first execution and warmed execution separately. One
  representative run measured owner construction 59.33s/8.52GB with 59.15s
  compilation, first owner update 175ms/49.6MB with 175ms compilation, warmed
  owner updates 1.92–2.33μs (median 2.15μs), and warmed contribution evaluation
  5.41–12.08ns (median 10.42ns), without imposing timing thresholds. A push to
  the existing Core PR
  was blocked by the environment's external-source-egress reviewer pending
  explicit user approval for that remote; no workaround was attempted. R50's
  amended local pin commit `3b77133f` now selects `a6faf5d`/tree `35dd91b`, but
  cannot qualify hosted checkout until the Core commit is published.

- **Core G04/G05 publication and CI gating (2026-09-11):** G04 Core R08
  [CorePotts PR #32](https://github.com/PraneethMerugu/CorePotts.jl/pull/32)
  merged at `9b13005`. G05 Core R10 remains published as stacked
  draft [CorePotts PR #33](https://github.com/PraneethMerugu/CorePotts.jl/pull/33)
  from `dfe5c95` against the now-merged G04 branch; retarget it to `main` with
  the next qualified candidate update. CorePotts `main` is now protected with strict required
  `changes`, `package`, `macos-smoke`, `docs`, and `metal` checks enforced for
  admins, so auto-merge cannot bypass hosted qualification. G04 parent CPU
  passes 31,016/31,016 and strict docs pass against LocalMath `22e7b429`. Its
  hosted Metal failure was localized to a non-isbits `Symbol` result crossing
  the remove-effect planning kernel. Commit `9b13005` replaces it atomically
  with the shared four-byte isbits disposition/detail payload. The exact changed
  boundary remains 172 statements/101 calls/zero `Any`/one specialization
  before and after, and the unchanged built-in tracker control remains exactly
  1,108/593; this is a representation correction, not an IR-size claim.
  Exact-tip focused CPU passes 408/408 and the formerly failing actual-Metal
  adaptation file passes 264/264 in 22m06.9s. Independent review found no
  semantic mapping, ownership, duplicate-path, or device-reachable diagnostic
  conversion blocker. G04 completed protected review qualification and merged
  through auto-merge at exact `9b13005`.
  G05's independently found zero-owner preflight mismatch is fixed at `13978fb`:
  both standalone and grouped backend entry checks now skip scientifically
  irrelevant contribution evaluation before creation from medium, matching the
  shared commit law. The new two-engine CPU witness passes and actual Metal
  passes 16/16 in 10m18.4s. Its current Kaimon entry measurements are standalone
  44 statements/26 calls and grouped-plan 98/56, with zero `Any`, concrete
  `Bool`, and one specialization; the latter removes two statements from the
  previous 100/56 plan, while typed IR confirms the zero-owner branch returns
  before contribution evaluation. Exact-tip G05 CPU now passes 32,800/32,800
  assertions across 62 units at `dfe5c95` with LocalMath `f41a37d`, forced
  bounds checks and two workers. The runner reports 479m45.3s aggregate/queued
  test time; observed wall was about 72 minutes, and neither is a benchmark.
  The local G05 candidate now advances to `30f7b1a`: backend preparation lowers
  the broad host `DenseScalarTrackerGroup` to one fixed isbits tuple payload
  instead of adapting descriptor/source-handle vectors across the kernel
  boundary. Exact Kaimon comparison against published `dfe5c95` reduces the
  qualified lookup from 124 statements/67 calls to 82/49, with zero `Any`, a
  concrete `Float32` return and one exact specialization on both sides. The
  unrelated built-in lookup remains exactly 22/13; payload summary size falls
  from 124 to 20 bytes. Exact focused CPU passes 1,627/1,627, full CPU passes
  32,804/32,804 across 62 units in 65m14.9s, and strict docs pass against
  LocalMath `f41a37d`. The full local Metal run passed every reported witness
  through scalar retirement, including 264 adaptation, 30 scheduling, 81
  minimum, 370 grouped lifecycle, 38 geometry, 78 structured transaction and
  the subsequent lifecycle/history banks. Its final process result was not
  retained by the polling client, and a fresh replay could not start because
  Metal.jl temporarily reported no devices despite the system GPU remaining
  visible. Substantive commit `30f7b1a` is now published in draft PR #33 at
  branch tip `5b2bdf3`, after reconciling the protected `main` merge, and the PR
  now targets `main`. Protected docs and macOS smoke pass. The first package and
  Metal jobs emitted no test failure but were canceled at their exact 90-minute
  and 120-minute ceilings. Metal passed 18 consecutive witness groups through
  85 heterogeneous lifecycle-value assertions, including 81 minimum and 370
  grouped lifecycle assertions. The CI-only tip raises both maximum execution
  windows to 180 minutes without changing tests or treating duration as a pass
  criterion. The protected rerun now passes its complete package job in
  1h37m45s; changes, docs and macOS smoke also pass. The actual Metal job and
  independent readiness review remain pending. No release is authorized.

- **G05 Potts bounded-minimum authoring candidate (2026-09-12):** local commit
  `c6c08214` on `codex/bounded-site-minimum-authoring` extends the single
  `aggregate` vocabulary with bounded scalar `combine=min`, a finite
  empty-owner policy, and an explicit Int32-sized lattice reconstruction bound.
  It lowers through the canonical quantity identity/handle map to Core's
  `SiteMinimumTracker`; there is no second gather reduction or model-specific
  executor. A corrected public witness distinguishes live cells from unused
  capacity slots and keeps Core as the empty-publication owner. Against exact
  Core `5b2bdf3`/substantive `30f7b1a` and LocalMath `f41a37d`, minimum
  authoring/execution passes 51/51 across both CPU algorithms; the unchanged
  additive control passes 81/81. A broader host/compiler/SPI/quality cohort
  passes 1,148/1,148 and strict docs pass doctests, cross-references, export
  checks and HTML rendering. Kaimon compares the additive descriptor at
  exactly 192 statements/117 calls and its identity at 81/54 before and after,
  with zero `Any` slots and one exact specialization. New minimum identity is
  175/115 and descriptor lowering is 384/238, also with zero `Any` and one exact
  specialization. Cold descriptor lowering still has an abstract declared
  return because analyzed graph nodes are runtime data, while the produced
  descriptor and Core execution plan are concrete. Local follow-up `01f46bf1`
  adds a same-model CPU/Metal semantic witness covering descriptor
  policy, initial publication, one step, source replacement, inactive capacity,
  and unchanged ownership. Its tracked Metal environment pins exact Core
  `5b2bdf3` and LocalMath `f41a37d`; local Metal is presently unavailable, so
  this witness is not yet a device pass. Actual Potts Metal coverage, complete
  package qualification and independent review remain required; these results
  do not complete R11.

- **Potts G04/G05 publication stack (2026-09-12):** G04 R09 is published as
  draft [Potts PR #53](https://github.com/PraneethMerugu/Potts.jl/pull/53) at
  `1953beda` against `main`, selecting published G04 Core `9b130057` and
  LocalMath `22e7b429`. Its exact-tuple package-quality check passes 48/48.
  G05 R11 is stacked as draft
  [Potts PR #54](https://github.com/PraneethMerugu/Potts.jl/pull/54) at
  `27928e6f` against the R09 branch, selecting Core `5b2bdf3` and LocalMath
  `f41a37d`. The ancestry-only merge leaves the R11 source tree byte-identical
  to qualified `65fba2db`. Both PRs remain draft pending their protected hosted
  checks and independent review; R11 additionally depends on Core PR #33.

- **R09/R11 joined aggregate audit (2026-09-12):** the first complete-package
  attempt exposed two R09 gaps before reaching the broader suite: Symbolics'
  constant-wrapped one-dimensional `array_literal` spelling was not canonicalized
  to the existing fixed-vector operation, and synchronous `FieldState` assignment
  was rejected despite the existing per-site stage path. Commit `b5933206`
  admits the field target without a new executor and isolates array-literal
  interpretation in a host-only helper that validates `(N,)` against N elements.
  Scheduled source-update behavior passes 24/24 and exact-tip vector maintained-
  quantity behavior passes 22/22 across both CPU algorithms. Kaimon measures
  field validation at exactly 105 statements/49 calls before and after, changing
  rejection to admission with zero `Any` and one specialization. Normalization
  moves from 891/430 to 908/435, rather than the rejected inline candidate's
  967/453; the isolated helper is 39/15. The unchanged scalar normalization
  control moves 219/121 to 225/121. Every measurement has zero `Any` and one
  exact specialization. Commit `b082903c` then selects the exact qualified
  dependency tuple Core `5b2bdf3` and LocalMath `f41a37d` in ordinary and Metal
  CI. The corrected complete-package run reached all 88 units in 106m15.5s:
  all 4,937 scientific and behavioral assertions passed, while three final
  package-quality assertions correctly rejected a private SymbolicUtils access
  and a test that duplicated one upstream tuple across the intentionally
  distinct replay and Metal profiles. Commit `65fba2db` recognizes the host-only
  array literal through its public function/module identity, keeps each immutable
  manifest authoritative for its own guarantee, and raises evidence-limited
  package/macOS-package/Metal CI ceilings to 180 minutes. The final focused
  vector/minimum/quality cohort passes 84/84 and strict docs pass. Kaimon measures
  the corrected helper at 43 statements/15 calls versus 39/15 before, with zero
  `Any` and the same concrete union return; the ordinary-leaf control remains
  1/0 and returns `Nothing`. The joined tip remains unpushed; hosted complete
  package, exact replay, integration, Metal and independent review remain.

- **Compiler-tractability standard accepted (2026-09-10):** the chain keeps its
  60 identified PRs and existing `G04 -> G05 -> G05C -> G06/G07` ordering; no
  speculative compiler PR was added. Every PR now declares compiler impact as
  `none`, `host-only`, or `device-reachable`. Relevant host compiler changes and
  all device-reachable changes require exact-tuple before/after Kaimon evidence
  at a changed boundary and an unchanged control, while actual Metal execution
  remains authoritative. There is no arbitrary IR-reduction quota; unexplained
  unrelated-kernel growth is specialization coupling and blocks completion
  until localized and removed or justified. G04 must establish the structural
  lifecycle/history baseline; active G05 R10/R11 are device-reachable and must
  compare source-aware sum/minimum and lifecycle paths against it. R49/R50 own
  the reproducible canonical probe set, with their existing G06 and G07 canaries.
  One bounded retrospective sweep covers merged R06, R07 and LocalMath
  PR12/PR13/PR14/PR16/PR17, using R01/R02 models as consumer baselines; CI-only
  completed work is excluded. Regressions are fixed in a coherent open owner PR
  or earn one counted targeted companion. This planning amendment changes no
  runtime code, qualification result, current worktree ownership, publication
  authority, or release authority.

- **User-approved composition-first amendment (2026-09-10):** the user accepted
  the four additional deliveries and confirmed **COBREXA.jl**. The shared
  [map](../consolidated-pr-dependency-map.md) now allocates **60 identified PRs =
  R01–R54 plus six companions**, in 26 groups. E13/R51 Potts owns metabolic
  coupling; E14/R52 Models owns FBCA; E15/R53 Models owns the vascular corpus;
  E16/R54 Models owns the multiscale tumor corpus. E07 completion gains E04
  for R35's compartment/field witness. Read the accepted
  [model amendment](../composition-first-model-roadmap.md) for existing-owner
  changes, all fourteen delivery owners, direct cutovers and scientific checks.
  This is planning acceptance only: no runtime changes, new test results,
  opened PRs, or additional merge/release authority. Current G04/G05 candidate
  work and its unresolved validation remain unchanged. Older 56-PR entries
  below are historical status records, superseded for allocation by this entry.
  The accepted scope, canonical paths, R51–R54 allocation, dependencies,
  cutovers and unresolved scientific checks were sent to the main implementation
  task “Check Main Branch Visibility” (`01a07f00-2309-78a0-b147-8a5a737d42ba`)
  at the user's request. Sending the handoff is not an implementation acknowledgment.

- **G04 complete-lineage correction (2026-09-10):** the clean, fully validated
  Core commit `779deae` is the final structured lifecycle/numeric slice, not by
  itself the complete R08 integration candidate. Reconstructing its ten commits
  on current Core `main` produced patch-equivalent `486380b`, but the first
  current-main public Potts canary failed during precompile because that slice
  does not contain the history-owned public `expression_state_handles` contract
  already consumed by the Potts integration branch. Core `386b02d` is the
  complete G04 lineage: it descends from current `main` and includes product
  fields, model reads, scheduled draws, histories, scoped anchors, transaction
  isolation and runtime adaptation. Its cell/numeric commits supersede the
  corresponding earlier slice commits; only the final `779deae` correction is
  patch-unique. The additive `codex/structured-lifecycle-complete` branch now
  joins `386b02d` plus only `779deae`, preserving both original branches; the
  union commit is `154762c`. A narrow follow-up cuts the sole ordinary Core CI
  LocalMath selection to authoritative merged `22e7b429`, producing candidate
  `852a043`. Potts `0c1bfa53` successfully precompiled and loaded
  against Core `154762c` and LocalMath `22e7b429`, closing the missing-SPI
  canary; the CI-only follow-up does not change that runtime interface. Strict
  Core docs pass on `852a043`/`22e7b429`. Independent review then identified one
  missing combined retained-history/lifecycle device witness. The test-only
  follow-up `1cfc778` makes its CPU and Metal fixtures share one independent
  oracle covering lifecycle change, bounded retention, checkpoint continuation,
  ineligibility, and late nonfinite rollback; it expands the ordinary Metal
  inventory from 19 to 20 files. The complete Core CPU package suite passed
  31,016/31,016 assertions across 56 units in 49m41.4s on exact `1cfc778`.
  Exact-tip strict docs, complete 20-file actual-Metal validation, and final
  review remain pending. Its focused CPU history,
  quality and inventory cohort passes 56/56; the first run correctly exposed
  and removed test-local executable code that was incompatible with exact
  checkpoint replay. No
  compatibility alias was added. The earlier 29,998 CPU/1,579 Metal results
  remain valid evidence for the exact lifecycle slice but do not qualify the
  complete R08/R09 tuple.
- **G05 compiler-boundary correction (2026-09-10):** the source-expression
  lifecycle crash is localized and corrected in the active uncommitted Core
  candidate. Checkerboard now cold-compiles each incremental `SiteSumTracker`
  expression and binds its exact staged state arrays plus a fixed parameter
  tuple; structural lifecycle kernels consume that private lowering while the
  public tracker remains the sole scientific contract and both engines retain
  the same subtract-before-clear/add-after-clear transaction. A compact
  structure runtime and `_LifecycleTrackerCommitSource` remove the full
  program/runtime, descriptor state and unrelated parameters from the kernel
  ABI while retaining staged ownership and the geometry required by volume,
  moment and surface trackers. Fresh Kaimon `code_typed` measurements on the
  exact sum-only commit boundary are 1,680 statements / 968 calls / zero `Any`
  slots / concrete `Bool` / one specialization; its direct bound contribution
  is 194 / 80 / zero `Any` / concrete `Float32` / one specialization. The
  pre-binding sum boundary was 2,270 / 1,198, and the unchanged built-in control
  is 1,217 / 695. Compact-source type text fell from 325 to 161 characters and
  live summary size from 636 to 392 bytes without changing the optimized
  scientific body. Actual Metal now passes both the sum-only and mixed
  minimum+sum structural ladder; measured `advance_mcs!` times in one cold
  process were 45.023s and 35.118s respectively. Total process time was
  845.60s, showing that host-side first-specialization/model construction—not
  the now-valid Metal kernel alone—is the next tractability target. A proposed
  fixed-tuple recursive traversal was rejected and removed: Kaimon timed out at
  ten minutes and Metal produced `jl_f_throw_methoderror` at that boundary.
  Focused CPU lifecycle, minimum, source-aware and scheduled-source suites pass.
  Independent audits found no semantic, failure-atomicity, adaptation or
  supported-tracker blocker. The permanent actual-Metal lifecycle fixture then
  passed 195/198 assertions before its intentional source-overflow case exposed
  one remaining backend contract: a nonfinite bound contribution escaped as a
  raw `Metal.KernelException`, leaving the candidate unsettled, instead of using
  the existing lifecycle status/recovery channel. A total backend preflight for
  the same contribution and owner-update arithmetic is now implemented without
  changing contribution meaning or the host exception path. Fresh Kaimon
  measurement is 2,054 statements / 1,182 calls / zero `Any` slots / concrete
  `Bool` / one specialization for the complete backend commit; the total
  preflight itself is 100 / 56 and the cold raw contribution is 186 / 75 with a
  concrete `Float32` return. This remains below the pre-binding 2,270 / 1,198
  boundary while adding structured device failure translation. The preflight
  now reports the same recoverable `tracker_commit_invalid` invariant as the
  host tracker transaction; evaluator/nonfinite status remains reserved for
  settled terminal scientific failures. The exact queue/publication-boundary
  CPU recovery matrix passes 88/88 in 6m35.8s. The focused actual-Metal overflow
  witness also passes structured failure, rollback, settled snapshot, repaired
  input, checkpoint restore and continued execution; its measured behavioral
  run was 572.413s. The next measured G05C tractability candidate is to compile
  the lifecycle SiteSum executable, handle slots and parameter arity once, then
  bind only staged arrays at launch; a following candidate can remove author
  quantity identities and generic `TrackerContract` reconstruction from the
  accepted-update device ABI. Neither refinement is folded into the G05
  correctness baseline without before/after Kaimon and actual-Metal evidence.
  The permanent actual-Metal lifecycle suite now passes 334/334 in 27m17.1s,
  including the overflow cases, repaired continuation and later history/minimum
  cases that the earlier raw-kernel failure never reached. G05 compiler
  review then found and corrected the equivalent standalone `SiteSumTracker`
  vector-storage preflight, which had been masked by grouped lifecycle fixtures;
  its focused two-engine CPU witness passes 39/39 in 6m25.4s and actual Metal
  passes 20/20 in 10m18.3s. The review also removed the premature public
  `FullLatticeReconstructionUpdateBound` compiler contract and restricts that
  private bound to its implemented `SiteMinimumTracker` owner; the general
  extension contract remains G05C scope. G05 compiler refactoring is frozen at
  this correct baseline. The full ordinary CorePotts
  CPU suite passes 31,934/31,934 in 47m58.6s against the exact Core candidate
  and LocalMath reduction-control companion; package quality, compiler/SPI
  boundaries, checkpoint/adaptation and unrelated scientific paths are green.
  Strict docs pass doctests, cross-references, export checks and HTML rendering.
  The immutable-commit review remains pending.
  G05C must resolve the separately identified contract gap for downstream
  custom full-lattice reconstruction trackers; G05 does not add an unqualified
  reconstruction SPI.
- **G05 latest-source qualification and scope (2026-09-10):** independent review found no
  remaining semantic or architectural blocker in the uncommitted Core minimum,
  retained-history, accepted-copy overflow and receipt-recovery implementation.
  A test-only backend parameterization passed 66/66 CPU assertions; the prior
  complete focused CPU cohort remains 438/438. Two actual-Metal attempts crash
  before assertions in LLVM's late inliner while compiling the first structural
  lifecycle kernel with source-expression trackers; the second reproduced in an
  otherwise idle process. A bounded compile-only capture produced 58,838 lines /
  5.5 MB of pre-late-inliner IR and proved that the explicitly cold
  `expression_state_handles` walker survived inside the structural kernel,
  including dynamic array allocation and `_growend!`. Direct evaluation through
  the existing authoritative site context removes that hot/cold leak and passes
  current CPU minimum 198/198 and lifecycle 702/702, but the exact Metal witness
  still crashes after about 1.05 billion allocations. An independently reviewed
  compact structure payload removes the full runtime/program and full lifecycle
  plan from that kernel ABI. Its exact actual-Metal settlement-owner run still
  crashed with exit 139 in LLVM's late inliner before assertions, after
  1,045,404,381 allocations and 145 garbage collections. This rules out the full
  runtime/lifecycle-plan ABI as the dominant cause, while remaining a
  compiler-safety blocker rather than a numerical assertion failure. Kaimon
  evaluation of exact adapted-payload construction exceeded its ten-minute
  evaluation window. Host exact type renders measured 8,344 characters for the
  full state, 2,151 for the compact runtime, 93 for the compact plan, and 325 for
  the source view. Direct sum/minimum `_site_tracker_contribution` optimized
  typed IR measured 173 statements and 73 calls with a concrete `Float32`
  return; its 72 `Any` entries were control-flow statements, not erased value
  results. The corrected scheduled-source owner passed 227/227 after comparing
  observable relationship collections. A four-rung actual-Metal localization
  ladder is active, beginning with built-ins-only; no rung has passed yet.
  Separately, a 25-row requirement/owner/evidence audit confirms that a green
  current slice would not complete G05: Potts still lacks public minimum and
  retained-history aggregate admission, periodic/anisotropic geometry and
  distinct/contact-weighted relation workflows; joined native-output invalidation
  and mass/count to mean/division/restore witnesses are also missing, and the
  useful model-level floating policy remains unresolved. Implemented structured
  and scheduled paths should be qualified, not rebuilt. Broader owner/quality/
  docs and the complete applicable Metal inventory remain required on immutable
  commits before R10/R11 readiness.
- **R09 joined Potts candidate audit (2026-09-10; published 2026-09-12):**
  draft Potts PR #53 at `1953beda` joins the dense authoring commits for
  declaration assembly/control flow, structured values and units, scoped
  components/imports/replacement, compound effects, histories, semantic draws,
  field rates, symbolic mutation, examples and device witnesses. Its prior full
  package run predates the final public-wrapper/fixture correction, so only the
  later 715/715 focused result and individual CPU/Metal witnesses are retained.
  The published parent now selects the exact G04 Core `9b130057`/LocalMath
  `22e7b429` tuple in ordinary CI and its Metal profile while leaving the closed
  exact-replay environment intentionally unchanged. Its exact-tuple quality
  check passes 48/48. Protected complete CPU/integration/docs/Metal and
  independent review remain required.
- **R49/R50 completion criteria clarified (2026-09-09):** retain exactly the
  two additional compiler-contract PRs and the 56-PR identified allocation.
  The shared amendment/map now explicitly require the public vertical workflow,
  all relevant consumption meanings, a concrete deletion/cutover inventory,
  before/after compile/preparation/fan-out/runtime measurements, actual-candidate
  G06 and G07 interface canaries before interface freeze, the external-operation
  trust boundary, source maps/docs/errors and full applicable validation.
  Post-G08/G09 audit findings may justify targeted owner follow-ups; no third
  speculative compiler/framework or cosmetic-cleanup PR is allocated. This is
  scope clarification, not completed implementation or new test evidence.

- **User-approved compiler-contract chain amendment (2026-09-09):** the shared
  [delivery map](../consolidated-pr-dependency-map.md) now identifies **56 PRs**:
  50 planned (original R01–R48 plus R49 Core/R50 Potts), plus the six already
  identified companions. New G05C depends on a correct G05 baseline; G06 and G07
  now depend on G05C completion. R49 refines Core quantity-consumption/maintenance
  contracts; R50 cuts over resolved aggregate facts and dependency lowering.
  Read [the agent-facing amendment](../compiler-contract-chain-amendment.md) before
  assigning these tasks. Both new PRs are **planned, not implemented or opened**.
  Existing G05 numerical/source/lifecycle obligations are not deferred. The
  isolated 60-assertion/14-testset conceptual probe is design evidence only,
  not package/device qualification. Remaining findings have named G06–G09 and
  breadth owners; no other automatic companions or merge/release authority
  are added by this planning change.

- [LocalMath PR14](https://github.com/PraneethMerugu/LocalMath.jl/pull/14)
  merged on 2026-09-09 after every hosted package, docs, scientific,
  macOS-smoke and Metal check passed. Its later physical array/view transfer
  correction was not part of that merge. Those five uncommitted files have now
  been moved intact to `codex/backend-owned-array-allocation` from current
  LocalMath `main`; this is the fifth merged companion. Exact candidate evidence
  is full CPU1,735/1,735,
  focused Metal37/37, complete actual-Metal owner exit zero, downstream Core
  structured-sum Metal24/24, strict docs, and independent review without a
  blocker. Commit `b4ecf27` was published as
  [LocalMath PR16](https://github.com/PraneethMerugu/LocalMath.jl/pull/16) and
  merged by the requested auto-merge command. Every applicable hosted check is
  terminal successful: changes, package, docs, scientific, macOS smoke, and
  Metal; macOS package was intentionally skipped by selection. The physical
  allocation prerequisite is therefore complete, and no CUDA/ROCm guarantee is
  inferred from its CPU/Metal qualification.
- G04 lifecycle authoring now passes complete same-task scalar and nested-product
  transactions on actual Metal with forced bounds and scalar indexing disabled:
  scalar RetireTo21/21 and nested named/positional product conversion230/230,
  including successful application and every rejected-leaf rollback case.
  Matching CPU product coverage passes486/486. The permanent fixture adapts the
  complete runtime and exercises the production device-resident lifecycle
  descriptor load; independent review found no remaining code or fixture
  blocker. The earlier ordering-race hypothesis was retracted because LocalMath
  owns ordered same-task submission and the installed Metal KernelAbstractions
  launch returns no event. The combined ordinary CPU cohort now passes
  2,506/2,506 across all11 selected lifecycle and inventory units. Its exact
  ten-file actual-Metal counterpart passes1,190/1,190 in a fresh same-task
  process on the same frozen source. After deleting the diagnostic-only
  slot/bank fixtures, the durable owner/quality cohort passes2,497/2,497,
  strict docs pass, and the complete ordinary Core CPU suite passes
  29,998/29,998 on clean commit `779deae`. Its complete14-file actual-Metal
  runner is live on that immutable commit; no PR-readiness claim precedes that
  result.
- [LocalMath PR17](https://github.com/PraneethMerugu/LocalMath.jl/pull/17)
  merged from clean `f41a37d` after focused CPU122/122, focused actual-Metal62/62,
  full CPU1,797/1,797, complete Metal483/483, strict docs, and independent
  review all passed. It makes identity-seeded reductions truthful total field
  producers for later controls, while rejecting `ExistingSeed` and any producer
  stage whose own gate can skip publication. Requested auto-merge completed
  immediately because required hosted checks are not configured. Every
  applicable hosted check is now terminal successful: package, docs,
  scientific, macOS smoke, and Metal; macOS package was intentionally skipped
  by selection.
- G05 SiteMinimumTracker work now uses a truthful
  `FullLatticeReconstructionUpdateBound`; the synthetic no-op tracker delta was
  deleted. Both engines now use one LocalMath-owned entry snapshot only for
  full-lattice reconstruction contracts, then compare entry ownership/source
  parents with the completed structural transaction before the sole tracker
  rebuild. A generic lifecycle recovery correction journals every submitted
  receipt immediately, preserves a valid queued MCS prefix without fabricating
  a lifecycle receipt, discards only an incomplete suffix, and leaves explicit
  settlement as the queued-publication owner. Focused CPU passes168/168 across
  direct enqueue, enqueue-through, staged and ordinary advance recovery plus
  mixed and minimum-only overflow rollback/retry on both engines; Boolean site
  capacities reject4/4. Retained-history lifecycle and accepted-copy nonfinite
  witnesses, broader owner/docs/quality validation, actual Metal, and final
  independent review remain before PR readiness.
- Scheduled source maintenance is saved as clean Core anchor0b4d604 atop
  1f40718. Its complete owner passed220/220, strict docs passed, and the public
  completed-MCS benchmark passed all assertions for ten MCS per CPU engine.
  Warm medians were6.440ms/3,488,256bytes Sequential and
  0.440ms/152,896bytes Checkerboard on this tiny shared-process fixture;
  these are diagnostics, not thresholds or speedup guarantees. Wider ordinary
  cohort62974 is live on the immutable commit; GPU remains pending.
- Independent review of Core structured values found and corrected three
  boundary issues after owner72604: all scalar/fixed reductions now use the one
  checked Core operation with LocalMath37838c6 exact-value analysis; new
  DenseOwnerValueStorage rejects undemonstrated integer/non-fixed payloads at
  the existing descriptor validator; scalar-only internal helper names are
  completed as owner-value names. Structured overflow atomicity and tolerance
  leaf-type negatives were added. Focused owner/SPI/quality rerun89913 is live.
- Core structured owner-value owner72604 passed155/155 in9m32.4s against
  immutable LocalMath37838c6. Fixed vectors/matrices now pass both CPU engines,
  input publication, checkpoint continuation and componentwise tolerance
  behavior. Broader ordinary regression/quality cohort58808 is live; the
  nearest architecture/API documentation now records the single shared
  LocalMath execution path.
- Lifecycle scalar-state-only actual Metal51426 still failed with one device
  error after7m13.8s, before its eight assertions. Together with CPU16/16, this
  rules out nested-product evaluator/state/schema inventory as necessary for
  the fault. Its bounded traceback remains blank until
  `call_lifecycle_state_rule` → `_apply_lifecycle_state_rules!` → the
  state-effect kernel, with no recovered bank operands or proven predicate.
  Further speculative diagnostics are paused.
- Full LocalMath Metal suite63779 is live on the clean detached37838c6
  snapshot after its environment was repointed away from the mutable authoring
  worktree. Independent read-only review is also active; the GPU is owned by
  this qualification run.
- Potts assignment-unit owner92683 passed73/73 in5m45.9s on immutable
  Core1f407187 and LocalMath37838c6. It covers both-engine scalar/vector/matrix
  scaling, compatible reference units, first/later effect mismatches,
  polymorphic zero, dimensional literals, and external-operation negatives.
  Broad twelve-unit behavioral cohort43858 is live; inventory follows under
  its actual runner key.
- Lifecycle scalar-state-only reduction61108 passed16/16 across both CPU
  engines on immutable LocalMath37838c6 after removing the unused product
  state/schema as well as its evaluator. Actual Metal51426 is live for that
  single shared case with functional Metal required and scalar indexing
  disabled. This is fixture isolation only; no production correction is
  inferred yet.
- Scheduled-source expanded owner37527 reached213 passes and one fixture
  observation error in14m02.9s. Real checkerboard cancellation, inactive lag
  refresh, iterated-result reset, AtMCS0 capture, and both late-overflow paths
  reached their intended behavior. Sequential rollback/retry passed; the sole
  error asked `program_snapshot` to inspect a correctly unsettled failed
  checkerboard runtime. Corrected owner39007 is live with production unchanged.
- Core structured owner-value retry72604 is live against immutable
  LocalMath37838c6 after adding the fixed-array checkerboard accumulator type,
  completing durable owner-value helper naming, and adding componentwise
  checkpoint-tolerance coverage. Source and tests remain frozen until the
  owning run terminates.
- Potts assignment-unit validation owner92683 is live against immutable Core
  and LocalMath snapshots. Review confirms the narrow check covers existing
  scalar and whole fixed-array symbolic RHS support; literal matrices and
  literal product RHS values were already unsupported by shape/evaluator
  lowering and remain explicit future authoring work.
- LocalMath companion37838c6 full ordinary suite passed1732/1732 in5m43.7s
  on its clean detached consumer snapshot. Focused regression207/207,
  quality/inventory19/19, strict docs and actual fixed-value Metal2/2 also
  remain green. Full Metal suite and independent review remain before PR
  readiness; downstream immutable reruns are active.
- Potts wrong-unit public diagnostic95513 passed as a diagnostic and proved a
  real missing contract: a length-valued fixed matrix assigned to a time-valued
  fixed-matrix state survives complete, PottsProblem and SequentialCPM init.
  Source/target dimensions are explicitly m versus s. The authoring track is
  locating the existing analyzed RHS/target fact owner before adding the narrow
  validation; no production edit is yet accepted.
- LocalMath fixed-value typed-IR companion is saved as37838c6 on branch
  codex/fixed-value-stage-operations. Physical AbstractArray storage
  still receives a host surrogate, while already-qualified immutable storage
  values such as SVector/SMatrix retain their exact scalar payload signature.
  Direct canonical Reduce owner/regression tests pass20/20 and207/207,
  package-quality/inventory19/19, strict docs exit0, and actual Metal2/2 for
  vector and matrix values. Metal attempt86734 never loaded source because its
  bare test environment was uninstantiated; instantiated retry3294 supplied the
  device result. Detached immutable consumer worktree
  localmath-fixed-value-validation now owns exact37838c6; Core structured retry
  81479 is live against it. This is the reusable owner fix
  required by Core structured sums, not relaxed validation or a second reducer.
- Dependency-freeze audit found Potts83983 and lifecycle Metal56578 referenced
  the shared LocalMath worktree by path while that companion was edited. Their
  exact results are preserved as diagnostic only: Potts56pass/1fail and
  lifecycle one device error. After LocalMath CPU/Metal qualification and save,
  create an immutable consumer snapshot and rerun both; do not infer regression
  or qualification from these mutable-dependency runs.
- Scheduled source owner1427 passed124/124 in7m51.6s across both CPU engines:
  source/history/lag refresh, checkpoint continuation, shared entry readers,
  iterated actual-write OR and Sequential cancellation/no-write behavior.
  Expanded boundary cohort11922 is live with real checkerboard cancellation,
  inactive lags, AtMCS0, iterated reset and late-overflow rollback. No Metal or
  full-owner claim yet.
- Lifecycle composition Metal65835 completed exit1 with4/4 execution errors in
  8m50.5s: scalar-only, numeric-product-only, coexisting numeric and matched
  typed rules all reached the real device path and failed before numerical
  assertions. Fresh task-local providers exclude a simple poisoned-scope
  follow-on. This disproves the hypothesis that product execution or numeric
  conversion is necessary. Next fixture-only isolation removes the unselected
  product evaluator, then its retained state/schema if needed, while preserving
  the selected scalar rule and lifecycle transaction. CPU remains80/80.
- Potts cold normalization diagnostic67769 proved production custom-operation
  admission is correct; the negative fixture omitted a lattice, so reusable
  subsystem completion intentionally deferred lattice-dependent fact analysis.
  Fixture-only correction adds a real 2D lattice/spacing and constructs
  unit-bearing arrays leafwise to avoid upstream StaticArray-DynamicQuantity
  ambiguity. Full fixed-array owner retry53459 is live; production unchanged.
- Scheduled source maintenance initial owner test1427 is live after review of
  physical history-parent invalidation. It covers both engines for maintained
  source sums and history lags, plus shared entry readers, actual no-write versus
  same-value publication and iterated-write OR. Source/tests are frozen until
  terminal.
- Structured owner sums CPU23116 completed119pass/1error in5m53.6s. All
  pre-existing source-aware cases passed; the new fixed-value case reached
  LocalMath admission and exposed the generic tracker reduction wrapper as
  returning a dynamic Vector in exact typed IR. The sole reduction declaration
  now selects native `+` for fixed arrays while retaining the checked generic
  operation for scalar/wide tracker values. Retry53528 never loaded source
  because the sandbox denied Julia's package-usage lock; escalated ordinary
  retry26775 is live on the otherwise unchanged branch.
- Potts fixed-array cohort36244 completed219pass/2fail/1error in14m56.4s.
  Scalar aggregates81, scientific operations65, fixed vectors25, inventory2,
  and ordinary scalar/vector/matrix scaling42 all passed. The unit-bearing case
  fails in upstream StaticArray-by-DynamicQuantity construction before Potts;
  its fixture will construct quantity leaves without type piracy. Both external
  custom-operation negative cases failed to reject, so cold normalization
  diagnostic73328 is live before any production edit. Tensor execution remains
  unrun.
- Lifecycle rule-composition CPU retry46312 passed80/80 in6m12.2s across both
  CPU engines. Shared ordinary Metal cohort65835 is live in fresh task-local
  owner contexts for scalar-only, product-only, combined and matched typed
  cases; no production correction is inferred until its exact case results are
  known.
- Scheduled source maintenance has a formatted initial implementation and
  ordinary fixture but no test claim. Root review verified that
  `state_read_source` is an admission check here: history projections retain
  the physical history bank/slot while that query returns the original source
  entry, so invalidation must compare the projected physical parent. A direct
  lag/history regression and explanatory comment are being added before the
  first focused run; source remains unfrozen until that launch.
- Root structured owner sums WIP compile-loaded successfully in isolated env.
  Direct cutover renames scalar-only delta types to OwnerValueDelta and
  OldNewOwnerValueDelta across current code/tests, adds distinct fixed-value
  owner storage, componentwise finite/tolerance validation, and reuses the sole
  LocalMath reduction path. Ordinary full source-aware owner test23116 is live;
  branch frozen until terminal. Log
  validation-logs/corepotts-structured-owner-sums-cpu.log.
- Numeric composition CPU46267 lost its process handle with no summary/error
  and no matching OS process; recorded interrupted and unqualified. Identical
  retry46312 is live on unchanged frozen source.
- Actual Metal29683 passed264/264 in7m54.6s on386b02d, covering independent
  CPU→Metal, Metal→Metal, and Metal→CPU publication/continuation, abort,
  lifecycle removal and failed-state retention. CPU409 and strict docs also
  passed. GPU released; adaptation-specific device correction is qualified,
  not full G04 numeric or cross-backend checkpoint/bitwise parity.
- G05 latest ancestry merge1f40718 is saved; detached Core validation worktree
  corepotts-aggregate-input-validation uses that exact commit. Potts ordinary
  cohort36244 is live against this snapshot: fixed-array scaling, scalar
  aggregates, fixed-vector operations, scientific operation SPI and inventory.
  Potts source/snapshot frozen; scheduled Core development is independent.
- Root structured owner sums branch/worktree created from1f40718 at
  corepotts-structured-owner-sums. It will extend existing value storage/delta,
  tolerance and canonical LocalMath reduction owners for fixed vectors/tensors;
  no test claim yet. Scheduled agent retains its separate source-aware tree.
- G05 CPU48442 passed798/798 in16m24.3s: source sums, input publication,
  lifecycle receipts and adaptation after ancestry merge and constructor fix.
  Reviewed tolerance fix saved d77c3e6. Dev source freeze released. Readability
  will merge386b02d and make an immutable detached validation worktree for
  Potts fixed-array/scalar tests; scheduled development can then proceed in
  separate source-aware worktree without changing any consumed source.
- Numeric reduction approved: preserve state/evaluator layout, vary only
  declared rule membership (scalar/product/both plus matched-leaf control),
  with full transaction and unselected-state assertions. CPU first; GPU waits
  root adaptation29683 release. No production semantics changed by reduction.
- Actual Metal adaptation29683 is live on clean386b02d after numeric GPU release;
  log validation-logs/corepotts-topology-tracker-adaptation-metal.log. G04 source
  remains frozen. This is the actual409-CPU-qualified correction retry.
- Numeric92221 ended exit1 after successful pre-target synchronization. The
  full isolated caller emitted blank exception name/reason despite validated
  control34/34; no trustworthy actual index/length recovered. No production
  patch inferred. Next read-only work seeks a minimal ordinary-model reduction
  distinguishing scalar, product, and combined state-rule failure, rather than
  repeated mailbox or annotation variants.
- Strict Core docs31828 completed exit0 for386b02d: ordinary doctests,
  cross-references, export checks and HTML passed; no deployment. Integration
  worktree clean, actual Metal retry still awaits numeric GPU release.
- G04 CPU98259 passed409/409 in5m37.2s: adaptation264 and capabilities145,
  including actual CPU-only tracker adaptation/independent execution. Reviewed
  topology identity retention and actual-target admission saved386b02d. Strict
  docs31828 running; GPU retry queued after numeric92221 releases device.
- G05 CPU48442 source-aware unit passed; remaining selected units still live,
  so G05 Core source remains frozen and scheduled implementation has not begun.
- Numeric mailbox control4212 passed34/34 plus cold49563 four checks: exact
  index/length bits for both real bank representations, valid access, BoundsError
  and no output mutation. Isolated actual target92221 now runs with validated
  existing-mailbox capture only; no production change. Log
  validation-logs/corepotts-lifecycle-bounds-mailbox-target-metal.log.
- G04 CPU98259 adaptation unit passed; capability unit still live. No cohort
  completion claim. G05 CPU48442 also remains live and frozen.
- Reviewed next scheduled maintenance map preserves entry-snapshot readers,
  actual enabled writes, iterated OR, and actual history due result. Lag-only
  quantities depend on physical history parent, not original source metadata;
  initialize_history! stays ShiftAppend-only. Implementation waits48442 terminal.
  Potts tensor/math diff reviewed; requested custom-multiply rejection and
  detached failure-retention assertions before runtime validation.
- Root CPU98259 is live on integrationCore4307646 plus reviewed topology epoch
  retention and actual-target tracker support correction. Existing tracker_adapt
  customization/structural checks remain; real CPU-only count descriptor test
  checks independent Array adaptation/advance and hook use. Ordinary adaptation
  and capabilities selected; integration source/tests frozen. Log
  validation-logs/corepotts-topology-tracker-adaptation-cpu.log.
- Root G05 CPU48442 is live on3971126 plus reviewed tolerance-constructor fix:
  sole inner conversion/finite/nonnegative validation, preserving keyword and
  inferred construction. Direct invalid/overflow and valid conversion tests
  added. Ordinary source sums, input publication, lifecycle receipts and
  adaptation selected; G05 Core frozen. Potts-only tensor/scalar-array authoring
  work may continue without loading Core. Log
  validation-logs/corepotts-merged-scalar-tolerances-cpu.log.
- Isolated Metal16450 ended exit1: pre-target synchronization succeeded, then
  unchanged single state kernel failed at immediate post-target synchronization,
  before later lifecycle work. Bank-index frames remain; branch/actual operands
  are still unknown. This excludes earlier/later queued submissions for this
  observed failure. Existing mailbox operand capture with deliberate-OOB control
  is the next diagnostic, with bounds checks/traps preserved.
- Root topology fix under review now retains the existing kernel-program
  reconstruction and tracker_adapt contract: an explicit topology_epoch keyword
  carries the already-owned epoch during adaptation, while initial construction
  computes it from canonical host storage. The direct Adapt draft was removed.
  No qualification claimed; unconditional GPU tracker admission during CPU Array
  adaptation also needs a real runtime witness and owner-consistent correction.
- Isolated lifecycle state-submission diagnostic16450 is live after96554
  preflight passed. Only process-local host pre/post synchronization differs;
  original kernel/payload/dispatcher/conversion remain. GPU owned by ci.
- Actual Metal adaptation52466 ended exit1 at same-device sibling creation:
  existing kernel-program reconstruction tries recomputing logical topology
  epoch from device-resident canonical sites. No adaptation device assertion
  passed before this error. Root is reviewing retention of the already-owned
  topology epoch without bypassing tracker_adapt customization/structural checks.
  Two-line direct Adapt prototype is unqualified WIP in integrationCore; no
  consumer remains. GPU released to ci's isolated-submission diagnostic.
- Reviewed G05 local anchors are saved clean: Core3f2cc79 (40 files, exact
  Core750-tested snapshot) and Potts50967f9 (32 files, scalar81/native52 and
  existing1366 assertions). Potts documentation now distinguishes scalar CPU
  qualification from required vector/scheduled/device work; registered WIP
  tests remain. Neither is pushed/merged or a full G05 completion claim.
  Readability is preparing a lineage-preserving merge of G04 Core4307646
  (including b6fd332), not duplicate cherry-picks.
- Numeric Metal traceback re-audit narrows the earlier first-throw claim:
  original specialized helper frames identify bank indexing in that compiled
  module, but a shared device mailbox across queued submissions does not prove
  first-fault provenance. No safety check or production annotation is changed.
- Actual Metal adaptation52466 is live on clean integrationCore4307646 and
  LocalMath a6 after GPU release. Ordinary shared fixture runs unchanged from
  CPU264pass, with functional Metal required and scalar indexing disabled.
  IntegrationCore source/tests frozen; log
  validation-logs/corepotts-owned-adaptation-metal.log.
- Public scalar32960 passed81/81 in6m43.3s. Native52 and prior existing1366
  selected regression assertions also passed. G05 source freeze released;
  agents are reviewing coherent local saves and G04 lineage integration.
  Vector, scheduled, actual GPU and full G05 scope remain unqualified.
- Inline-only Metal diagnostic92112 ended exit1 after6m40.2s. Captured module
  confirms no outlined bank-dispatch call remains, yet full consumer still
  raises BoundsError. Merged exception traceback cannot identify the failing
  check, so this does not prove the same bank check failed. No annotation or
  semantic change adopted; read-only localization review continues.
- Owned adaptation CPU12209 passed264/264 in4m22.9s. Reviewed implementation,
  CPU/Metal shared fixtures, capability correction and docs saved in integration
  Core4307646. Strict docs42910 also passed. Prior62791 supplied passing
  lifecycle257/capability118/inventory3 on identical production source. No
  current root consumer; actual Metal adaptation awaits GPU release after
  diagnostic92112. G04 final combined validation and numeric join remain open.
- Strict Core documentation42910 completed exit0 on the frozen owned-adaptation
  implementation: ordinary docs/make.jl doctests, cross-references, exported
  documentation checks and HTML passed; no deployment. Log
  validation-logs/corepotts-owned-adaptation-docs.log. Full264 adaptation CPU
  rerun12209 remains live; source/tests remain frozen until terminal.
- Adaptation28138 terminal exit1:263pass/1fail in4m19.2s. All independence,
  returned-CPU publication/continuation and failed-state branches ran. Sole
  assertion expected zero ownership after removal; configured replacement
  medium1 has authoritative label-1 (lifecycle_context.jl). Corrected expected
  value to-1, not production behavior. Full264 ordinary file rerun launched;
  log validation-logs/corepotts-owned-adaptation-medium-cpu.log.
- Public scalar retry32960 is live with only explicit scope-fixture spacing
  changed since80pass cohort. G05 tuple frozen; log
  validation-logs/potts-scalar-aggregate-scoped-owner.log.
- Metal call-site-inlining diagnostic92112 is live after preflight92011 passed.
  Process-local override adds only @inline at existing bank-dispatch call;
  original indexing/checks/generated dispatcher and numeric fixture remain.
  Captured module will establish whether outlined call disappears; outcome
  remains diagnostic until reviewed production integration and ordinary tests.
- Public scalar38884 terminal exit1:80pass/1error in6m47.6s. All numerical,
  mutation, tolerance, units and four negative scope assertions passed. The
  positive scope fixture omitted explicit spacing when replacing its former
  Lattice convenience declaration with LatticeDomain. Restore spacing1/1 as in
  the positive shared fixture, preserving all81 assertions, then rerun. No
  production correction is inferred from this fixture error.
- Metal capture97704 completed exit0 at its intentional pre-submission stop.
  Exact instrumented state-commit LLVM is saved for bounded operand review;
  adapted metadata remains correct. This is diagnostic capture, not numerical
  execution qualification. GPU released pending coordinated next use.
- G04 CPU62791 terminal exit1:520pass/1error in9m24.6s. Lifecycle receipts257,
  capabilities118 and inventory3 passed; adaptation142 passed before its new
  returned-CPU branch called nonexistent program_capability_report(::Runtime).
  Owner fixture now reads the actual returned runtime capability_report field,
  not the compiled program's potentially different backend report. No production
  change. Full ordinary adaptation file rerun launched; later branches remain
  unqualified. Log validation-logs/corepotts-owned-adaptation-cpu-corrected.log.
- Corrected public scalar owner38884 is live via ordinary Pkg.test, retaining
  all81 assertions. Root reviewed raw tracker expectations against the public
  cell identity table, full logical-capacity outputs/restore, and actual
  LatticeDomain scope setup. Production is unchanged from40638; G05 tuple
  frozen again. Log validation-logs/potts-scalar-aggregate-owner-corrected.log.
- Metal instrumented dispatch capture97704 is live after cold preflight68186
  passed. The diagnostic uses the existing compiler hook and intentionally
  stops before state-commit kernel submission, after normal preparation. It
  will inspect optimized bounds/logging operands, not qualify execution.
  Production remains unchanged; log
  validation-logs/corepotts-lifecycle-instrumented-bank-capture.log.
- Public scalar40638 is terminal exit1:1434pass/12fail/1error in15m08.1s.
  All six existing selected units passed; scalar aggregate unit68pass/12fail/
  1error. Failure review identifies fixture capacity expectations and a Sites
  resource supplied as nested declaration rather than LatticeDomain. Narrow
  fixture corrections are pending review; public numerical/shape assertions
  remain required. G05 consumer freeze released.
- G04 CPU62791 remains live; program_adaptation reported failure after151.56s,
  with details buffered until cohort completion. No source edits or restart.
  Separate ordinary Metal environment setup63861 completed exit0, with local
  integrationCore and LocalMath paths and broad package compatibility. No Metal
  adaptation execution has launched.
- G04 owned-adaptation CPU cohort62791 is running through ordinary Pkg.test:
  program_adaptation, capabilities, lifecycle_receipts and inventory, using
  verified integrationCore and LocalMath a6 paths. Shared adaptation coverage
  now also returns adapted storage to Array, checks CPU admission, publishes
  and advances independently while source/adapted/sibling states remain intact.
  This becomes device-to-CPU execution coverage only when the Metal fixture
  runs successfully. G04 source/tests frozen until terminal; log
  validation-logs/corepotts-owned-adaptation-cpu.log.
- Metal diagnostic64483 ended exit1 after6m14.5s. Actual adapted rule metadata
  was observed and is correct (bank lengths1/1, locations1/1 and2/1, range1/2).
  The bounds exception persists, without the conditional diagnostic output;
  silence is inconclusive. No semantic correction is inferred. Investigation
  proceeds to generated dispatch LLVM, with GPU qualification still incomplete.
- Public scalar40638 has reported a scalar-aggregate unit failure while other
  selected units continue; full traceback is buffered until completion. Native
  98057 remains terminal52/52. G05 sources remain frozen through scalar terminal.
- Public native98057 passed52/52 on the existing qualified Float64 CPU profile:
  new input-only/no-input retained-cache oracle30 and existing functional
  native22. Earlier63950 failed preflight because the new fixture requested
  unqualified Float32; only that fixture was corrected to Float64 with
  cancellation2^-54, preserving all assertions. Scalar40638 remains live on
  the G05 tuple; source freeze remains until terminal.
- G04 adaptation ownership implementation/test WIP is now complete enough for
  independent review: existing Adapt traversal copies array leaves through a
  private storage adaptor, existing lifecycle alias rebinding is retained,
  public host buffers are copied, and CPU Array target admission is corrected
  in the existing capability owner with mechanism revalidation. Shared ordinary
  CPU/Metal tests retain source/adapted/sibling runtimes, exercise staged abort
  and commit, independent stepping, lifecycle removal, counters/receipts and
  failed status. No runtime qualification yet; review/formatting precede launch.
- G04 ordinary13711 passed16859/16859 in8m37.7s. Reviewed transaction isolation,
  parameter bank-copy, abort and nonaggregate parity regression saved in
  integrationCore b6fd332. G05 corrected71959 passed750/750 in14m43.2s,
  including source/cell sums, both-engine inputs/alternating aborts, generic
  publication and lifecycle receipts. Public Potts scalar/native execution is
  now authorized on the frozen G05 tuple; actual device/vector/scheduled
  aggregate guarantees remain pending.
- Root public-adaptation host copying is WIP in integrationCore runtime.jl:
  explicit existing-rebuild buffer arguments copy mutable host science,
  parameters and proposal scratch without changing internal same-owner rebuild
  defaults. Checkerboard host scratch is immutable/absent; logically immutable
  receipts and compiled program remain shared. Complete execution-array/control
  ownership and same-backend adaptation are under review before tests; this
  partial implementation is not qualified.
- Metal36773 ended exit1 after6m40: literal product conversion compiles, but
  execution raises a state-rule-bank bounds exception. Exact frame/LLVM review
  localizes the first throw to generated bank dispatch, not the prior product
  tag check. Conversion remains unchanged while slot/length provenance is
  investigated; full lifecycle qualification is still incomplete.
- Read-only review found a separate adaptation ownership defect:
  adapt_program_runtime returns a distinct runtime with shared published host
  buffers, without transfer/invalidation. Updating/stepping it can alter the
  original host science while leaving its clock/banks unchanged. Same-backend
  adaptation may also reuse execution arrays. An owner-local fix and retained
  source-runtime device regression are required; design review is ongoing,
  no adaptation source edits made during active test freezes.
- G05 CPU71959 has consumed source-sum and staged-input units without reported
  failures, including corrected parity checks. It remains live for generic
  publication and lifecycle receipts; no terminal/pass claim yet.
- G04 transaction fixes are now ported to integrationCore without G05-derived
  tracker changes. Root ordinary Pkg.test13711 is live for
  compiled_program_execution, lifecycle_receipts and inventory, with
  LocalMath a6. Source and tests are frozen until terminal; log
  validation-logs/corepotts-integrated-bank-isolation.log. Changed-region
  formatting and diff checks passed; execution qualification is pending.
- G05 corrected four-unit cohort71959 is live with the full scientific-bank
  detachment, expanded parity assertions and ordinary selection-oracle fixture.
  Source-aware worktree remains frozen through terminal. Log:
  validation-logs/corepotts-independent-scientific-banks.log.
- Numeric77764 terminal exit1: type-indexed recursion still leaves unsupported
  tuple-tail expansion in the full device caller. The reviewed replacement
  emits a literal tuple from concrete target field types only; native runtime
  conversions and all admission guards remain. Cold72786 passed native parity
  and inference controls; full Metal36773 is running on frozen numeric sources.
- Transaction ownership/abort corrections also belong in unmerged G04 R08,
  because its public staged native path already has these defects. Root added
  a non-aggregate repeated commit/abort regression using the existing descriptor
  fixture in integrationCore test_compiled_program_execution.jl, both engines
  and four bank parities. It is unvalidated pending the qualified correction
  port; preserve this uncommitted test during the numeric join. G05 tracker
  reconstruction itself remains separate.
- CPU13976 terminal exit1:673pass/1fail/3errors,14m02. Source sums/cell readers
  passed102/102, generic publication158/158; alternating abort exposed two
  host-alias errors. The receipt failures were an incidental six-leaf count and
  an omitted ordinary lifecycle-selection oracle in the focused launcher.
  Root now copies complete primary science via existing copy owners before
  lifecycle workspace allocation, expands staged/aborted host-state assertions,
  and removes the hard-coded count while retaining profile/disjointness checks.
  Independent review and corrected four-unit rerun are queued; no pass claimed.
- Strict Potts docs98014 completed exit0 onPotts0c1bfa53/Core2da44a0/LM a6f4383:
  ordinary doctests, cross-references, export checks and HTML generation passed;
  deployment disabled, integration worktree remains clean. Integration source
  freeze released. This does not qualify the pending numeric Core join.
- Daughter-history redraw correlation remains a genuine scientific choice:
  accepted policies fix parent/daughter independence but not within-window
  correlation. User clarification requested: independently addressed retained
  samples versus one variate repeated across each descendant's window. Core
  still rejects stochastic history policies; specialized redraw occurrence0
  and expression-draw lag occurrence must be unified after the decision.
- Metal85302 ended exit1 after6m38.3s: runtime tuple-map type traversal is
  invalid in the full device caller. It was replaced directly by existing
  Type/Val-indexed traversal style, retaining native leaf/final conversion and
  admission guards. Cold44662 passed20 native shape/key controls plus three
  inference controls. Full Metal77764 now runs the type-indexed candidate;
  numeric sources/tests are frozen, and GPU qualification is still pending.
- CPU13976 remains live with two alternating-bank abort errors. Independent
  root/agent inspection confirms the remaining primary scientific buffers
  alias the host through identity adaptation: parameters alone were detached.
  The next correction will detach the complete primary scientific state using
  existing copy owners before lifecycle workspace allocation. No source edit
  occurs until13976 is terminal. Downstream Potts execution remains queued.
- Strict Potts documentation98014 is running on verified integration
  Potts0c1bfa53/Core2da44a0/LocalMath a6f4383 with deployment disabled and the
  unchanged ordinary docs/make.jl. These integration paths remain frozen until
  terminal. Log: validation-logs/potts-public-parameter-strict-docs.log.
- Agent-owned CPU13976 remains live and has consumed source-sum tests without
  reported errors; native-input/publication/receipt results are still pending.
  Potts G05 now carries public-wrapper correction as5256997d. Its ordinary
  aggregate tests are split into scalar, vector, and scheduled behavior owners
  with one shared model/oracle/maintenance fixture; all assertions remain
  registered. Independent review found no blocker. Downstream scalar/native
  launch awaits Core qualification and will retain the Core source freeze.
- Numeric lifecycle cold controls62112 passed20/20, including outer/nested
  named-key permutations against native conversion and recursive inference
  controls. Agent-owned full Metal transaction85302 is running against the
  production candidate and final LocalMath a6, with no diagnostic override;
  source/tests are frozen. Log: lifecycle-exact-product-mapped-metal.log under
  validation-logs with the corepotts prefix. Root transaction changes received
  independent review with no blocker; focused CPU qualification is preparing.
- Core61270 is terminal:327 passed,2 failed,3 errors. Root has now isolated
  initial host/primary/alternate parameter buffers, included parameters in the
  existing scientific bank-copy schema, preserved alternate parameters during
  adaptation, and bound the abort kernel index before its conditional. New
  repeated commit/abort tests exercise both bank parities and no-input steps.
  Independent review and focused execution are pending; this is not a pass.
- Cell aggregate executable-key correction is written and syntax/format checks
  pass. The full Metal lifecycle conversion candidate now uses ordinary nested
  tuple-map specialization with native leaf conversion; CPU inference controls
  pass, but named-key permutation semantics are under review before actual GPU
  execution. Neither blocker is yet qualified as resolved.
- Potts focused11309 completed exit0:715/715,8m13.6s, including strict quality
  checks and all selected parameter/mutation/lifecycle units. Reviewed fixes
  saved as integration commit0c1bfa53; worktree clean. This is a focused pass,
  not a new full-suite or final numeric-Core integration pass.
- Core61270 remains live with real checkerboard native transaction failures:
  pending parameters become visible early and abort hits a KA index-method
  error. Root read-only inspection found shared parameter storage in both bank
  constructors; correction must separate host/bank buffers and preserve values
  through the actual bank-copy owner, including alternating parity. No frozen
  source edits. Qualified cell capture errors separately require existing
  executable key/call projections, not LocalMath validation relaxation.
- Metal inline experiment88231 ended exit1,6m56.6s; boxing and type-tag check
  remain in the full caller. Annotation was not adopted into production.
  Julia-level inference investigation continues at the existing coercion owner.
- Root focused Potts11309 is running seven ordinary selected test units after
  package precompilation: quality, parameter contracts, fixed-vector parameters,
  vector units/imports, structured lifecycle literals, mixed and logical
  mutation. Uses corrected integration Potts with Core2da/LocalMath a6; that
  tuple is frozen until terminal. Log: potts-public-parameter-correction.log.
- Root extended staged parameter/state/combined and abort regressions to both
  CPU engines; no-input selected cancellation remains a genuine Sequential
  witness. Parsing passed; the both-engine extension awaits execution.
- Cell-stage sum/count read module load27536 passed. Actual two-consumer
  numerical tests are added and construction9173 is running; load alone is not
  execution qualification. Scheduled source-publication gating remains pending.
- Exact full-caller Metal inlining experiment88231 is running outside production.
  All native conversion guards and the target assertion are retained. Root
  independently reviewed boxed-payload/type-tag LLVM evidence before approval;
  no production fix or blanket backend-defect claim yet.
- Combined Core CPU69096 completed exit0:291/291,6m12.1s. This includes
  checkerboard accepted-source shadow updates/grouped continuation, root staged
  input transaction tests (including abort and no-input rounding retention),
  and generic publication tests. Shared source freeze released. This does not
  qualify actual Metal source-sum execution, vector sums or scheduled refresh.
- Potts quality correction will remove redundant symbolic-wrapper is_parameter
  forwarding and use upstream public unwrap/redispatch, preserving the existing
  BasicSymbolic manifest owner. Wrapped/unwrapped/indexed regression assertions
  are being added; no private-type exemption or new wrapper taxonomy.
- Full Potts19906 completed exit1:4588 passed,1 failed,1 error,4590 total,
  96m31.0s. The error is the confirmed ParameterManifest fixture tuple/vector
  mismatch; root corrected that test after terminal completion. The quality
  failure is private Symbolics.CallAndWrap access in symbolic_indexing.jl;
  its owner is replacing that access through a public semantic interface,
  without exempting the quality test. Final rerun remains required. Integration
  source freeze released; user-owned root worktree changes remain untouched.
- Combined CPU69096 is running with bounds checks against frozen source/shared
  fixtures. It includes source sums with new checkerboard accepted-shadow and
  grouped continuation tests, staged-input transactions and generic publication.
  Independent review found no blocker in the derived-law ordering: completed
  clear/assignment shadows feed derived updates before any publication commits.
- Actual Metal checked-evaluation probe11279 passed12/12, including production
  nonfinite/failure-sentinel handling and real storage arguments. The full state
  commit caller still fails. Exact compiled-caller inspection is next; these
  reduced passes do not establish a full lifecycle fix.
- Independent inspection verified the structured-lifecycle test's obsolete
  tuple arguments to ParameterManifest, whose fields require typed vectors.
  The fixture correction is queued until full Potts19906 terminates; no frozen
  integration files were edited.
- Full Potts19906 remains live and has reported a failed
  test_structured_lifecycle_literals unit. Detailed failure output has not yet
  been emitted. The integration tuple remains frozen; independent read-only
  inspection is checking the unit/fixture before any correction or rerun.
- Root native-input overflow regression now requires both LocalMath's validation
  exception and its runtime_stage_validation contract, so a setup error cannot
  satisfy the expected scientific rejection. Shared-source CPU launch awaits
  completion of the current KA source edits.
- Metal diagnostic precision: the failing source line includes native tuple
  conversion and Core's final target assertion. Native conversion also has an
  internal assertion; the exact lowered failing check is not yet isolated.
  Neither the outer assertion nor native conversion alone is proven defective.
- Root implemented ProgramStepTransaction explicit-state staging marker and
  effective-input tracker prevalidation, plus detached candidate snapshots
  validated against pending parameters. Initial independent review found no
  blocker. New inventoried test_program_step_inputs covers parameter/state/
  combined staging, repeated prevalidation, snapshot independence, valid/invalid
  abort and a constrained actual-copy cancellation witness proving no-input
  transactions must retain cached rounding. Syntax/whitespace checks pass;
  behavioral execution and checkerboard coverage remain pending.
- Packed-parameter reduction CPU90707 completed exit0,70/70. It reuses the
  existing packed parameter read view instead of forming a tuple from device
  storage. Actual accelerator aggregate execution is still pending.
- Reduced actual Metal conversion probe31315 passed12/12 across native/Core
  coercion and concrete/heterogeneous-bank inputs. This does not reproduce or
  fix the full lifecycle caller's failure. Probe91380 adds actual runtime
  workspace, descriptor and target BlockView argument representations.
- Corrected source-sum CPU89025 completed exit0:70/70. Scalar15, grouped10,
  accepted clear/assignment and rejection9, persisted cancellation and numeric
  comparison policy28, whole-MCS derived-overflow rollback8. The exact tracker
  accumulation exception matched, with original state/ownership/trackers/MCS
  and counters restored. Typed ownership-delta regression passed. This remains
  scalar Sequential maintenance, not the pending KA/vector/lifecycle breadth.
- Actual Metal debug97675 completed exit1,6m22.2s. The first device exception
  identifies the type assertion on native lifecycle conversion in
  lifecycle_commit_state.jl:190, during RetireTo state staging. It is not a
  lifecycle selection or Collect failure. A bounded native-conversion probe
  is next; removing the assertion alone is not a validated fix.
- Combined CPU57809 is terminal exit1:198 passed,6 failed,1 error,3m57s.
  Extracted generic publication passed158/158. Source scalar15, grouped10 and
  accepted clear/assignment/rejection9 also passed. Strict cancellation is
  rejected at checkpoint creation, earlier than the test's restore assertion;
  correct the assertion boundary without changing production policy. The late
  failure case completed only two accepted copies and never overflowed, so it
  did not exercise rollback. A deterministic actual derived-overflow witness
  remains required; these failures are not passing rollback evidence.
- Independent read-only review of the shared publication fixtures, declared
  Metal checkpoint path, numerical oracle, test inventories and Core docs found
  no blocker. Backend defaults and parameter defaults remain unchanged. This
  review does not replace pending CPU/Metal/documentation execution.
- Exact57809 remains live; source/shared tests are still frozen. A read-only
  review identified an intersection ambiguity between the new SiteSum ownership
  delta method and the existing typed fallback. The source-view/owner argument
  specialization and owning regression are queued until terminal completion.
- Combined source transition/tolerance and generic input-publication CPU57809
  is running with bounds checks; production and shared fixtures are frozen.
  An outer testset keeps an earlier source test failure from suppressing the
  independent generic publication tests. No competing GPU run was launched.
- Added nearest Core API documentation for combined settled input publication
  and the contributor path through validation, reduction, bank publication,
  snapshots and ordinary tests. Validation rollback is explicitly distinguished
  from arbitrary backend-copy failure. Whitespace checks pass; review and strict
  documentation execution remain pending on this source tuple.
- The publication Metal wrapper now declares its Metal backend before runtime
  construction and follows the existing history-tested restore-then-adapt
  pattern. Added exact all-block continuation checks over two boundaries.
  Shared fixture backend keywords preserve CPU defaults and parameter defaults;
  parsing and whitespace checks pass. Execution is pending, not a replay claim.
- Lifecycle Metal94656 is terminal exit1:14 passed,60 errors,12m27.3s.
  The first exact-typed positional product transaction passed10/10; the next
  numerical conversion caused the first kernel exception. Four direct integer
  checks passed; subsequent provider-poison errors do not qualify other cases.
  Single ordinary exact-numeric debug97675 is now running with debug information,
  unchanged production and no execution override.
- The SiteSum comparison now uses an overflow-safe relative difference rather
  than multiplying tolerances; opposite-sign finite-extreme regression cases
  were added. Independent review found no remaining blocker in this scalar
  comparison or grouped source-change finish; behavioral validation is pending.
- Shared input-publication assertions now serve the ordinary CPU entrypoint and
  an inventoried Metal wrapper. CPU checkpoint assertions remain intact; the
  Metal wrapper adds an independent two-boundary numerical oracle but does not
  yet claim checkpoint replay. All four changed test files parse, whitespace
  checks pass, and independent review found no blocker. GPU execution pending.
- Source-aware grouped/recovery cohort38068 completed exit0: scalar recovery
  and checkpoint publication15/15, grouped distinct quantities10/10. The later
  invalid contribution preserves both cached quantities and all input state.
- Lifecycle Metal94656 remains live but has reported a first actual kernel
  exception in nested exact-numeric conversion. Subsequent provider-poisoning
  errors are not independent diagnoses. An isolated debug-info reproduction
  awaits terminal completion; no production guards have been relaxed.
- Review of the new SiteSum tolerance owner found overflow could turn its
  comparison into Inf <= Inf for finite opposite-sign values. An overflow-safe
  comparison and regression are required before qualifying that policy.
- Scalar source-sum83625 completed exit0:11/11,20.5s, through actual LocalMath
  reduction. Sequential initialization/source-only/parameter-only/combined
  publication and invalid aggregate rollback passed. Earlier declaration
  failures remain failures. Grouped scalar instances, narrower overflow error,
  recovery/checkpoint, floating policy, accepted copies, vectors and Metal remain
  required; this is not complete G05 or general source-aware maintenance.
- Actual lifecycle Metal94656 is live on frozen numeric Core +final LocalMath a6,
  with five whole ordinary files: nested products, heterogeneous values,
  numeric conversion, integer bounds and capacity. No diagnostic override.
- Corrected lifecycle capacity88508 completed exit0 on final LocalMath a6:
  94/94 (construction4, identity mismatch atomicity20, both-engine allocation
  and rollback70), numerical section3m15.4s. No production change since67039;
  reviewed fixture corrections only. Actual Metal conversion/capacity validation
  is next on this source; diagnostic overrides are not used.
- Scalar source-sum retry42153 failed before assertions at typed-IR admission.
  Direct probe29868 returned the correct concrete contribution with full
  inference; the source screen rejected direct parametric context construction.
  Reviewed existing-pattern constructor boundary is now under scalar6404;
  LocalMath checks remain unchanged. No scalar execution pass yet.
- Corrected lifecycle cold preparation35652 passed4/4 on final LocalMath a6;
  ordinary whole capacity CPU88508 is running, with source/tests frozen.
- Potts aggregate lowering is under review: canonical contribution handles are
  ephemeral compile-time maps, consumers share the same tracker authority, and
  direct physical reads survive aggregate-source exclusion. Default literal
  zero tolerance now accepts unitful sources, with unitful regressions added.
  Unit-count aggregates must reuse existing ownership count; scalar/vector
  aggregate execution, numerical policy and remaining G05 breadth are unqualified.
- Root input publication97904 completed exit0:158/158,3m26.7s, on frozen
  G05 Core source +LocalMath a6. Both CPU engines cover rejection atomicity,
  independent numerical expectation, candidate detachment, single-input
  preservation and two-step checkpoint continuation. Source freeze released;
  scalar97113's reviewed packed-parameter correction can now be applied.
- Lifecycle67039 completed:2278 passed,0 failed,6 cold fixture errors,
  22m33.6s. Existing full cell lifecycle81, heterogeneous170, numeric1230,
  integer bounds307 and nested products470 passed; mismatch rejection20 passed.
  Six new capacity cases failed construction at the known request-bound fixture
  defect, not execution. Correct request bound and preservation of the previous
  published lifecycle receipt, then cold construction/focused CPU retry; actual
  numerical Metal on final LocalMath remains required.
- Root generic input publication cohort97904 is live on frozen G05 Core +LM a6,
  with bounds checks and ordinary compiled-program fixture. Scalar97113 ended
  before its first assertion: the new evaluator used named access on LocalMath's
  packed parameter tuple. Positional access is the reviewed correction, deferred
  until97904 releases the shared source. No scalar execution pass is claimed.
- First scalar source-sum cohort97113 is running against isolated G05 Core;
  all its source/tests are frozen until terminal. It covers initialization,
  source-only/parameter-only updates, combined finite result despite an
  overflowing intermediate, and invalid aggregate rollback. Import17681 passed
  earlier but is not execution evidence. Generic input tests await execution.
- Independent review found exact oracle equality at checkpoint reconstruction
  must be reconciled with declared floating accumulation/rebuild semantics once
  incremental sums are enabled. Persisted values must not be silently rebuilt;
  cancellation and continuation tests remain required before support claims.
- Final Models strict docs57968 completed exit0 on the verified clean
  e4b83f8/Pottsa9514e32/Core2da44a0/LocalMath a6f4383 tuple. Unchanged
  dev/docs.jl passed executable tutorials/templates, doctests, crossrefs and
  export checks, and rendered HTML without warnings or deployment. The prior
  missing terminal-status gap is closed. This documentation consumer released
  its source freeze; the full Potts19906 suite remains a live consumer.
- Core combined-input tests received independent review with no blocker; added
  parameter-only/state-only preservation checks are included. Execution still
  awaits stable source. G05's owner-routed reduction implementation is in
  progress, using LocalMath rather than a second executor.
- Final Models strict docs57968 is live on clean e4b83f8/Pottsa9514e32/
  Core2da44a0/LocalMath a6f4383 through unchanged dev/docs.jl, explicit checkout
  verification and a temporary docs environment. No deployment or relaxed
  documentation checks. Root Potts19906 remains live; history lifecycle has
  completed without a reported failure. CPU67039 also remains live with the
  known six cold fixture-bound errors, not a terminal result.
- Added ordinary Core test_program_input_publication.jl in the isolated G05
  worktree: combined invalid-input rejection, unchanged scientific snapshots,
  caller-buffer detachment, checkpoint continuation and two-step bank reuse.
  Julia syntax inspection and diff-check completed; behavioral execution awaits
  a stable matching Core implementation and independent review. This does not
  cover the still-required source-aware overflowing-intermediate witness.
- Scoped82487 completed successfully:28/28 shared CPU/actual Metal assertions
  on Pottsc16a4a5d/Core2da44a0/LocalMath a6f4383,17m17.2s. Two-population
  updates, structured imports through two consumers and cell/site anchors are
  covered. This complements scoped CPU116, not the still-running combined
  Potts suite. Device is released; numeric67039 remains live unchanged.
- Independent G05 native review requires derived validation after both staged
  inputs in existing ProgramStepTransaction prevalidation. Checkerboard's
  candidate snapshot and unpublished bank must agree before publication;
  sequential evaluation must use effective pending parameters. No fallible
  derived evaluation may be added to the final coordinated publish step.
- Potts atomic-input publication implementation is under independent review in
  potts-atomic-input-publication: one combined Core call replaces the parameter-
  first/state-second publication and rollback, including callback restoration.
  Existing native ProgramStepTransaction is preserved; its staged validation
  must incorporate derived quantities in Core. No matching-API tests yet.
- Early G05 Core review requires device source updates to use the existing
  LocalMath reduction path, not the host reconstruction loop, and expression
  admission to match actual source-context reads. Current source-view additions
  and initialization reorder are work in progress, not qualified support.
- CPU67039 found a cold capacity-test fixture mismatch: the generalized cell
  capacity retained the old request-count literal. The existing production
  bound correctly rejects it. The running cohort stays unchanged; after its
  terminal result the fixture will derive the correct request bound and receive
  cold construction coverage before the next numerical retry.
- Lifecycle CPU67039 now runs six ordinary whole test files, bounds checked,
  on the frozen isolated numeric change: capacity, cell lifecycle,
  heterogeneous values, numeric conversion, integer boundaries and nested
  products. Its LocalMath ec352f7 checkout differs from the final a6f4383
  integration tuple; a focused pass alone will not qualify the final join.
- G05 first additive consumer implementation is assigned to the isolated Core
  owner, with an independent Potts owner coordinating the direct cutover to
  combined settled-input publication. Accepted expressions must retain their
  entry-state reads while maintained values consume the existing completed
  source shadows. Scalar/vector work is an initial slice only; tensor,
  minimum removal/rebuild, relations and geometry remain required G05 scope.
- Combined strict Potts docs52839 completed successfully on the frozen
  a9514e32/2da44a0/a6f4383 tuple, with unchanged warning, doctest and export
  checks. Models89368 also passed65/65. Full Potts19906 remains live, freshly
  polled; eight parallel test units have completed without a reported failure.
- Independently reviewed the isolated lifecycle capacity traversal and new
  ordinary allocation tests: recycled-before-virgin, virgin allocation,
  unavailable holes below high-water with whole-MCS rollback, and short/long
  identity storage rejection. CPU qualification is approved; actual Metal
  follows scoped82487, which remains live. Neither production lifecycle
  qualification nor the full G04 group is complete.
- G05 review identified the existing accepted-state shadow publication as the
  source-after authority for maintained quantities. Tracker laws must observe
  final clear/assignment effects before commit without duplicating evaluation;
  entry-state dependencies and mixed source/parameter publication are under
  review before implementation.
- Downstream Models89368 passed65/65 against e4b83f8/Pottsa9514e32/
  Core2da44a0/LocalMath a6f4383 via the existing explicit-checkout helper.
  Combined docs52839 and full Potts19906 remain active on that frozen tuple.
- Typed-only lifecycle selection diagnostic15293 completed selection and
  publication, then intentionally stopped with zero transaction assertions.
  The existing plan-derived Int32 capacity/identity traversal is approved for
  transplant into the isolated sole selection owner, followed by ordinary
  mismatch/failure-atomicity/full-transaction CPU and Metal validation. This
  is not yet a qualified nested-lifecycle fix. Scoped Metal has device priority
  before the production numeric retry.
- G05 first-consumer owner planning starts independently of frozen G04 source:
  scalar/vector per-cell signal sums must cover existing accepted-copy tracker
  laws and source/parameter publication, not merely extend rebuild source views.
  No G05 production changes or support claim yet; full mapped scope remains.
- Scoped CPU26953 passed116/116 on c16a4a5d/Core2da44a0/LM a6, including
  both-engine two-consumer imported vector-state boundary-entry behavior.
  Scope joined root as a9514e32 after independent review of quantity-literal
  precedence, field/scoped footprints and diagnostic ownership.
- Full ordinary PottsPkg.test19906 is now active (--jobs=2), freezing
  Pottsa9514e32/Core2da44a0/LocalMath a6f4383. Log:
  .worktrees/potts-composed-authoring-full-package.log. Combined strict docs
  and downstream Models validation are assigned against this same immutable
  tuple. Do not edit its loaded files until all consumers terminate.
- Vector actual Metal2598 passed116/116 shared CPU/Metal assertions,8m15.6s,
  on826e8eb6/Core311394b/LM a6 with scalar indexing disabled: whole/indexed/imported
  parameters, physical units, invalid updates, continuation and detached solution
  history. Scoped Metal and nested lifecycle conversion remain pending.
- Root integration7239 completed328/328,21m11.1s on585f3283/Core2da44a0/LM a6:
  field157, reference scales68, structured history55, history source storage46,
  inventory2. Source freeze released. Reviewed field follow-up joined916be9b4,
  Metal runner fixes820c8a97, vector implementationf84b074b and reference cleanup
  b0eaea31. These later joins need combined validation; the328 result predates them.
- Vector join resolutions independently reviewed: retain shared expression
  reference scaling and new single parameter manifest; operation registration
  passes the owning record for both field operations and synthesized conversion.
  One obsolete unused PottsSystem reference-descriptor forwarding method removed
  and independently reviewed, savedf1d7f4e1; CompletedPottsData remains the sole
  invoked owner.
- Strict field docs45578 passed with unchanged doctest/warning/export checks,
  no warnings and no deployment. Numeric69549 failed before publication despite
  unprinted noinline observers; entry IR matches the printed experiment, so no
  compiler-defect claim follows. Input-copy audit found no missing synchronization.
  A bounded typed-capacity traversal prototype is approved outside production,
  with exact array-length checks and no unchecked conversion bypass.
- Vector actual Metal2598 is active on826e8eb6/Core311394b/LM a6; scalar indexing
  disabled, ordinary runner import context. Device outcome remains pending.
- Scoped/vector combined source savedf63a322e plus reviewed follow-upc16a4a5d.
  CPU26953 runs six ordinary scope/import/anchor/existing-cell units on
  Pottsc16a4a5d/Core2da44a0/LocalMath a6f4383. Standalone fixture namespace
  preflight25958 passed7/7 before launch; no combined numerical result yet.
- Strict field docs45578 is running unchanged docs/make.jl on
  Pottsa495e654/Core2da44a0/LocalMath a6f4383 after isolated setup86522 passed.
  Deployment disabled; warning/doctest/checkdocs policies unchanged.
- Root7239 still live; explicit field unit completed315.14s and remaining
  units continue. OS worker59325 was observed99% CPU; no restart warranted.
- Actual field42487 passed84/84 shared CPU/Metal assertions,7m15.4s,
  scalar indexing disabled: clipping, late multi-field/substep rollback,
  noncoherent units, addressed stochastic forcing, parity and same-declared
  device checkpoint continuation. Final tested field tree saveda495e654
  (fixture/docs follow-up atop24c9f1bd). Strict field docs are next; final
  combined package qualification remains pending.
- Corrected vector/reference compatibility71266 passed171/171. Reviewed
  follow-up saved826e8eb atop516c68d3; vector device run is queued after current
  numeric diagnostic69549. That diagnostic uses process-local unprinted checked
  conversion wrappers/full-module IR, not a production workaround.
- Existing randomness/polarity Metal runner namespace-only fix saved9997d8d0
  in separate potts-metal-runner-qualification worktree after independent review.
  Six calls now explicitly use Potts.MetalBackend; scientific assertions are
  unchanged. Join after root7239 terminates; full Metal validation still required.
- Vector implementation saved516c68d3. Compatibility70498 ended156 passes,
  one obsolete DeclaredReferenceUnits expectation and one missing launcher
  fixture prerequisite. Root reviewed enclosing lattice/protocol anchors and
  approved positive reconstruction coverage while retaining explicit incomplete
  reference and incompatible-dimension negatives; corrected retry is pending.
- Scoped/import integration will use a separate worktree based on immutable
  vector516c68d3 plus the saved scoped slice, not mutate either active branch.
  Quantity bounds must resolve in the once-qualified enclosing owner before
  scheduling/fingerprints; independent review precedes combined validation.
- Root7239 remains live on integration585f3283; five selected ordinary test
  units plus serial inventory have begun. No source changes are permitted there.
- Shared vector56938 passed97/97,4m57.3s, both CPU engines: whole/component
  updates, imported vector ownership, physical units, invalid-update rollback,
  continuation, solution getters and detached parameter history. Root reviewed
  shared fixture/wrapper expectations; implementation anchor may be saved while
  completion/reference compatibility70498 runs on unchanged source. Metal,
  full-owner tests and docs are still pending.
- Field namespace audit1853 passed7/7 with the ordinary Metal runner imports;
  backend/algorithm constructors are now explicitly qualified in the wrapper.
  This is setup validation, not numerical GPU evidence.
- Ownership refinement17361 passed132/132,4m29.3s: external field producer
  exclusion, history source retention, early completed-child ownership error,
  enclosing numerics, symbolic parameter queries and effective overlays.
  Shared vector56938 remains active on unchanged source; completion/reference
  compatibility is still required after the refinement.
- Reviewed final field fixture/docs corrections: explicit macro imports,
  qualified Potts.MetalBackend in the runner, and public draw-placement limits.
  Runner92168 stopped after8 CPU assertions on ambiguous backend naming, before
  device numerical execution. These corrections are not yet in the integration
  worktree, which remains frozen by live7239.
- Field integration merge saved as585f3283 after independent review of the
  additive test conflicts and operation-closure dispatch. Ordinary Pkg.test7239
  now freezes Potts585f3283/Core2da44a0/LocalMath a6f4383 for explicit field rates,
  expression reference scales, structured history, history source storage and
  test inventory. Log: .worktrees/potts-field-joined-integration.log.
- Independent vector parameter review found no concrete blocker in manifest
  ownership, component selection, remake overlays, mutation or checkpoint
  reconstruction. This does not qualify pending ownership/device tests.
- Field24c9f1bd is joined into the idle Potts integration worktree with the
  local merge staged, awaiting independent resolution review and commit.
  Only conflicts were additive test inventory and the concrete reference-scale
  literal test; both branches' tests are retained. Production auto-merged.
  No combined-snapshot numerical pass is inferred.
- Field Metal98828 stopped before numerical execution because the shared
  fixture lacked an explicit macro import. Corrected standalone fixture/docs
  snapshot is frozen under actual runner92168; device results remain pending.
- Ownership refinements17361 and shared vector fixture56938 are running on
  the vector branch. Those source/fixture snapshots must remain unchanged.
- Reviewed contextual completion refinements: external stored fields contribute
  declaration context without producer coefficients; HistoryState still reaches
  its source. Completed-child runtime ownership is checked before structural
  scheduling. New regressions cover field/history imports and missing lattice
  diagnostics. Full-enclosing lifecycle/reference validation remains authoritative;
  redundant subtree validation is being removed before the focused retry.
- Actual field CPU/Metal witness98828 is running on Potts24c9f1bd/Core31c1fd4/
  LocalMath a6f4383, with scalar indexing disabled. Source and fixtures are frozen.
  Device success is not yet claimed.
- Explicit field cohort59465 completed190/190 CPU assertions, including
  stochastic site/order/seed/checkpoint behavior and unchanged scientific
  activity/field tests. Subsequent cold35289 passed3/3 after narrowing draw
  admission to DiscreteFieldEuler rhs only. Saved24c9f1bd independently reviewed;
  actual Metal qualification remains pending. The190 result predates narrowing.
- Vector/context cohort30143 ended with312 passes and one test error from
  symbolic equality in an inspection comparison. The agent is correcting that
  fixture and the reviewed contextual dependency/preflight refinements before
  retrying; compatibility89539 remains682/682, not a full slice qualification.
- Models strict-docs handle1232 is now unavailable. Its log reaches HTML
  rendering and prints all four selected checkout paths, with no ERROR or
  Warning matches; terminal exit status was not recovered, so this is not
  recorded as a confirmed successful process exit. No root consumer remains
  live on the integration tuple.
- Numeric printed-observer capture95833 completed selection/publication then
  intentionally stopped without transaction assertions. This diagnostic is
  not a production fix. Uninstrumented selection still fails; comparison
  without print side effects is queued behind public field Metal validation.
- Once-qualified completion compatibility89539 passed682/682,7m45.5s:
  completion diagnostics, source traversal authority, units/parameters,
  mtkcompile, SciML indexing and mixed mutation. New parameter/import/ownership
  cohort30143 remains live on the same frozen source; no complete slice pass
  is inferred from compatibility alone. Root Models strict tutorials1232 remain
  live against their independently frozen integration tuple.
- Downstream Models47237 passed65/65: explicit checkout4, bounded model
  factories36, surface/calibration8 and package quality17. Verified loaded
  sources are Potts e50ace48/Core2da44a0/LocalMath a6f4383/Models e4b83f8.
  Strict tutorials now run via the existing Models dev/docs.jl helper against
  the same frozen checkouts; it resolves the declared docs project separately.
- Core manual navbar fix independently reviewed and saved as2da44a0 after
  strict docs76757 passed and generated HTML href verification. Root downstream
  Models47237 now freezes Potts e50ace48/Core2da44a0/LocalMath a6f4383 and Models
  e4b83f8. It uses Models' existing explicit-checkout helper followed by ordinary
  Pkg.test, with no copied model implementations or private upstream access.
- Numeric original-selection IR capture52465 reproduced checked conversion
  failure before publication, exit1,6m19.1s. Optimized guarded control flow agrees
  with the earlier original trace. Full IR stays on disk for comparison with
  instrumented variants; no production workaround is validated.
- Strict joined Core docs80716 passed. It emitted a missing repository-navbar
  warning, corrected with the verified origin URL via Documenter.HTML(repolink).
  Strict rebuild76757 passed without that warning; generated index HTML contains
  the expected GitHub href. One-line docs/make.jl change awaits review/save;
  Core integration source is otherwise745a8d8 and no root consumer remains live.
- Root strict Core documentation80716 is active on integration745a8d8 and
  LocalMath a6f4383, in a dedicated ordinary Documenter1 environment. Existing
  docs/make.jl retains doctest=true, warnonly=false and checkdocs=:exports.
  Freeze this Core integration snapshot until the documentation consumer ends.
- Once-qualified contextual ownership/vector CPU30143 is active, covering
  four parameter/dependency files and existing component replacement, including
  an independently executable closed child. Public PottsProblem preflight now
  uses the same ownership check before lattice/initial validation; its negative
  test catches construction as well as init. Numerical results are pending.
- Scoped60200 completed104 passes/1 indexed-import error,11m37.3s. Corrected
  cell/site anchor execution passed8/8; remaining error occurs during child
  normalization before runtime and is assigned to the shared context-owner fix.
  Its source freeze is released. Numeric exact-selection LLVM comparison setup
  verified15 checked conversion sites; upcoming device captures remain diagnostic.
- Shared physical-literal analysis saved as5af03258 after123 passing checks
  in17808 (including68 complete reference-scale assertions). Field stochastic
  admission is a separate pending diff, reviewed for non-rhs placement rejection;
  supported evolution semantics and ordinary stochastic results remain required.
- Field17808 completed123 passes before stochastic context admission failed.
  Reference-scale owner68/68 includes the new non-field constant; field cold4,
  concrete literal6, rollback15 and deterministic physical30 passed. Stochastic
  numerical and old shorthand files were not reached. Admit draws only in an
  evolving explicit field rhs through the existing draw-context validator;
  draws elsewhere in the field declaration remain errors. Whole-statement draw
  collection makes a blanket FieldState admission incorrect. Retain Hamiltonian
  rejection, distribution validation and mixed-placement negative coverage.
- Scoped60200 has passed the corrected cell/site anchor unit; indexed imported
  state normalization remains its recorded error, with final cohort completion
  pending. Shared source-context correction is owned on the vector branch.
- Context records must not become runtime declarations. Before materialization,
  derive an ownership-closure check from existing source nodes and qualified
  references: a completed child relying on enclosing-owned state/parameters
  requires enclosing-model materialization or explicit source recomposition.
  This is not a rejection of whole-root imports or ownership-closed standalone
  children. Require positive examples of both, no-cloned-ownership inspection,
  and an actionable failure naming missing owners; no cross-runtime storage
  authority, persistent registry or ownership flag is introduced.
- Core capability89253 passed74/74 in18s. All four units that errored in the
  full run now have ordinary passing results: checkerboard59, state113,
  execution16495, capabilities74. Independently reviewed test-only corrections
  saved as15b1e61 and joined idle Core integration as745a8d8. No complete joined
  owner/Metal pass is inferred; integration remains incomplete pending other G04
  source changes. Root owns no active test handles after89253.
- Core17518 completed16737 passes/1 error,17m11.9s: checkerboard59/59,
  history/state113/113, execution16495/16495. Remaining capability fixture
  now reaches target-domain validation and lacks its declared site storage.
  Corrected isolated fixture supplies a6x6 site schema, canonical target handle,
  matching write footprint and exclusive write access. CPU-only support flag
  and unsupported-device assertions remain unchanged. Ordinary capability89253
  is active; no production validation change or complete owner pass is claimed.
- Four-unit Core17518 has passed compiled_program_checkerboard_oracles and
  advanced to compiled_program_state. Preserve the active source snapshot;
  no complete four-unit result is claimed yet.
- Contextual import diagnosis locates parent-reference loss in child
  _source_subinventory before eager normalization. Proposed implementation must
  retain only reached external dependencies with canonical owner identities,
  not append unrelated parent parameters or infer declarations. Prefer sharing
  records from the existing enclosing qualifier and deriving child ownership,
  rather than reconstructing StateRecord metadata in a second authority.
- Numeric74830 completed exit1,6m25.9s: no-print noinline isolation of only
  high-water Int32(cell) still fails during selection synchronization, before
  LocalMath publication. Printed30031 success is not a valid call-boundary fix.
  Production remains unchanged; compare generated code before another expensive
  diagnostic variant. Corrected public scope/import CPU60200 now runs on frozen
  Coreea403e22/LocalMath a6f4383; scope Metal environment61747 resolved successfully.
- Vector compatibility3250 passed553/553 in6m46s. Source is released for the
  exact BasicSymbolic{SymReal} dispatch intersection and incomplete-system
  parameter_symbols delegation to MTK's existing owner. Root/scheduled manifest
  semantics remain unchanged. Indexed imported dependencies still need a shared
  canonical-context fix, preserving child ownership and unknown-name rejection.
- Vector52965 completed104 passes/7 errors: whole-vector runtime51/51,
  dimensional20/20 and schema-consistency9/9 passed, with additional mixed-length
  and finite-override checks passing. Six errors are introduced SII dispatch
  ambiguity against installed MTK's AbstractSystem/BasicSymbolic{SymReal}; the
  other is indexed imported-parent parameter resolution. Fix the exact method
  intersection and existing canonical import owner after live compatibility3250
  releases source. Do not replace indexed imports with private flat-slot access.
- Field57359 stopped in the new non-field test's host-inspection assumption:
  literal Assign is directly lowered, not enrolled as an effect expression root.
  Keep the actual6m-to3 numerical witness; inspect only genuine field RHS roots
  if host facts are needed. This failure does not justify a production change.
  Earlier53420 failed only on compiled-cache permissions;57359 used authorized
  access, with no source change between those attempts.
- Scoped27897 completed102 passes/1 error. The sole error is checkerboard
  scoped-site identity: analyzed footprint incorrectly retains BoundSiteAnchor
  instead of the synchronous iteration site. Correct only the exact resolved
  scoped binding through existing graph ownership; preserve energy-bound anchors
  and cross-scope rejection. Actual imported structured reads must join the
  shared CPU/Metal fixture, not be claimed from cold completion alone.
  Numeric no-print single-conversion diagnostic74830 now reserves the device;
  it is still process-local diagnosis, not a production fix.
- Field26725 stopped after4 passing cold diagnostics: a valid concrete rate
  was misclassified as the Quantity wrapper type, failing scalar-real admission.
  Reviewed shared term-analysis correction derives numerical type from the
  concrete payload while retaining separate physical units and one-time reference
  conversion. New non-field6m/reference2m witness joins the complete scale/field/
  activity retry53420, frozen at98132172 plus its reviewed two-file diff.
- Field source correction98132172 is saved; earliest-owner cold admission
  checks passed4/4. Full numerical/stochastic/shorthand/activity retry26725
  now runs against Core31c1fd4/LocalMath a6f4383. No new device-field claim.
- Vector52965 runs the corrected owner/import/unit/parameter contracts on its
  isolated frozen branch. Read-only review found no new blocker in the single
  transfer/callable schema insertion owner or source-problem parameter overlays.
  Required followups remain existing scalar/SII/mixed regressions and shared
  actual-Metal witnesses. Fixed-vector homogeneous-unit support is not a claim
  of arbitrary tensor/product parameter support.
- Independent review confirmed all four Core source-table corrections match
  existing source_handle1 declarations without changing effects, support flags,
  rollback assertions or history values. Four-unit17518 remains live.
- Full Core93479 completed29701 passes/4 errors out of29705,133m40.5s.
  Every error is a descriptor source_handle1 referencing an empty source table:
  callback rejection, bounded-history checkpoint state, injected-stage rollback,
  and CPU-only capability rejection. No failing numerical history expectation
  was reported. Preserve EveryMCS history semantics and existing assertions.
  Isolated test correction now supplies explicit source entries at all four
  call sites; helper default remains empty. Callback-only43887 passed3/3.
  Ordinary four-unit retry17518 freezes the corrected isolated Core source
  (base31c1fd4 plus test-only diff) and LocalMath a6f4383. Changed regions were
  Runic formatted; no production admission relaxation was introduced.
- Joined inventory51450 passed ordinary Pkg.test2/2 on Potts e50ace48/Core
  d3355c4/LocalMath a6f4383. This corrects the only failure in combined33106;
  it does not substitute for final joined scientific/device qualification.
- Oracle62612 completed56 passes/1 error,25m52s. All scalar-oracle and
  transactional scientific assertions passed. The remaining negative callback
  fixture errored at construction because source_handle1 had an empty source
  table. Idle test-only correction supplies that explicit source entry, keeps
  unsupported-effect rejection and adds callback-count0. Independently reviewed
  without blockers; existing-test-only cold43887 is active before cohort retry.
- Combined Potts33106 completed exit1:1838 passes/1 inventory failure across
  1839 assertions,37m18s. All selected scientific/operational units passed;
  failure is the known missing history_structured_samples fixture registration.
  On source release, joined926c07d8 as a9ad5f0e and reviewed benchmark8c44a238
  as e50ace48. Joined Core scopeea403e22 as d3355c4, resolving only an additive
  Metal inventory conflict by retaining both history tests and the scope test.
  Ordinary inventory retry51450 now freezes Potts e50ace48/Core d3355c4/LocalMath
  a6f4383 through the verified integration environment. Full Core93479 and
  isolated oracle62612 remain live on their original unchanged snapshots.
- Field56765 stopped with3/4 cold admission checks: the concrete wrong-unit
  diagnostic is now correct, but symbolic-valued Quantity fails earlier in
  reference metadata conversion. Move its explicit rejection to that first
  source-aware owner and remove the unreachable normalization rejection;
  retain the distinction from concrete quantities and all numerical checks.
- Numeric30031 terminated exit0 under process-local printing/noinline cast
  instrumentation,13m07.1s. Selection and publication completed, but the run
  intentionally stopped before transaction assertions. Only observed executed
  conversion was high-water loop cell index1. This compiler perturbation is
  diagnostic evidence, not a production fix or Metal support qualification.
  Original uninstrumented6056 failure remains authoritative. Scope68810 passed
  four input-topology contracts, including parent references and orphan rejection;
  these do not establish native numerical support.
- Current status remains10 merged of51 identified PRs; G04 is incomplete.
  Root93479/33106/62612 were verified live on the latest continuation. Combined
  dimensional-expression tests passed; structured history is now running.
- Field18960 terminated with47 passes/1 failure: concrete dimensional literal
  classification hit Num/Quantity equality ambiguity before the unit diagnostic.
  Reviewed correction249e0dab classifies concrete quantity payloads before
  symbolic binding equality and explicitly diagnoses symbolic-valued quantities.
  Both-engine constant-rate witnesses supplement unchanged scientific tests.
  Retry56765 is active; no stochastic or device-field pass is inferred.
- Vector11700 terminated with67 passes/2 fixture failures/1 import error.
  Both CPU engines exercised coefficients/setters/checkpoints, and dimensional
  vectors passed20/20. Import admission must recognize an exact declared array
  symbol through the existing owner, not create another import path. Malformed
  defaults are already rejected by Symbolics and tests must respect that owner.
  Prior-scalar9371 passed2/2: an explicit finite override of an infinite default
  remains valid while an unresolved infinite effective value rejects at init.
  Preserve that behavior while validating final published parameter values.
- Scope input qualification is correcting minimal native test-fixture protocol
  omissions; no native numerical execution claim follows from topology checks.
  Heavy scoped numerical validation is held until active compilation pressure
  subsides. Numeric30031 remains an isolated selection-kernel diagnostic.
- Core93479 now also reports compiled_program_state failed (in addition to
  checkerboard oracle); detailed buffered error is not yet available. It
  continues with logical ownership changes. Do not infer a shared cause or
  restart. Combined33106 history lifecycle passed and history feedback started.
- Reviewed Core scope bridge saved clean ea403e22 with10CPU/4Metal checks;
  join remains pending integration source release.
- Scoped-input3881 exposed over-eager unresolved rejection during child
  completion: a legitimate parent parameter is not in the child's reference
  subset yet. Defer only unresolved-leaf rejection to the existing hierarchy's
  enclosing root graph; retain resolved scope/domain validation in children.
  Standalone roots still reject orphan/plain unbound leaves. Do not infer this
  boundary from lattice presence or create a second graph/reference registry.
- Scope Core79900 completed4/4 actual-Metal identity checks,12m16.3s, after
  10/10 CPU. Numeric cast-observation30031 now owns the GPU; process-local
  instrumentation retains checked conversions and is diagnostic only.
- History inventory39368 completed ordinary Pkg.test exit0,2/2 on926c07d8.
  Ready to join after integration33106 releases its frozen test inventory.
  Its log retains a nonfatal upstream ModelingToolkit inference warning.
- Operation-schema review found silent first-wins identity/version collisions
  in both normalization insertion loops. Replace them with one insertion helper
  requiring equal complete transfer/callable semantics, retaining legitimate
  surface promotion and varied admitted arity. Conflicting-definition negatives
  and mixed-length positives are required before the vector slice qualifies.
- Parameter review confirmed mixed vector lengths require synthesized operation
  selection by the existing transfer arity range, not one observed schema arity.
  Preserve surface identity, transfer consistency, role/phase/context and callable
  validation; add a real length2+3 consumer after frozen11700 completes. This
  avoids per-length schema duplication while exercising composition explicitly.
- Combined33106 declaration-control-flow unit passed; history lifecycle is
  running. Root93479/33106/62612 handles were all re-polled live; no restarts.
- Scope orphan-anchor probe92478 exposed an unresolved symbolic read surviving
  completion as VariableBindingPayload. Resolve/reject it through the existing
  source-aware scoped-read validation, with ordinary unbound/orphan negatives
  and legitimate parent/import/native/input positives; do not restore spelling
  classification or add a second token/domain authority.
- Isolated codex/checkerboard-oracle-snapshots corrects a concrete test-ordering
  defect: complete color execution includes claims and ownership publication,
  while the old comparisons evaluated acceptance afterward and one omitted
  claims. Both expectations now use the existing independent scalar acceptance
  and conjunctive-selection oracles before execution. No production change.
  Ordinary focused Core62612 is active on this isolated source plusLocalMatha6;
  independent review requested. Original93479 continues; this is not yet proven
  to explain its buffered failure, and no passing result is claimed.
- Fixed-vector parameter candidate is under focused98048. Read-only review
  traced logical/component selection, overlap rejection, flat Core slots and
  checkpoint reconstruction through the single scheduled manifest. Followups:
  validate malformed/empty defaults before taking their first unit; ensure
  synthesized vector construction participates in operation admission; add
  unitful vector setter/history/restore witnesses. No array support is claimed
  before these tests and CPU/Metal/public-consumer validation complete.
- Field retry18960 is active on isolatede3c86268; history inventory39368 is
  active on correction926c07d8. Core scope Metal79900 and public scope-name
  CPU89673 are active separately. Root integration33106/Core93479 snapshots
  remain unchanged. The next numeric diagnostic is process-local instrumentation
  of checked Int32 conversions in the exact selection method, not a production
  workaround; a changed failure under instrumentation is not a fix.
- Numeric6056 completed exit1,6m40.8s: exact prepared selection kernel submitted
  to authorized bank2, immediate synchronization failed in checked Int32
  conversion before any selected-request publication submission. This isolates
  the failure to Core selection, not LocalMath Collect or logical-value coercion.
  Scope anchor Metal has the next device slot; continue selection diagnosis
  without unchecked casts or changing scientific ordering.
- Independent field correction review approved: additional implicit-center
  analyzed fact passes through existing union/materialization, retaining empty
  and nonspatial semantics. New shared witness checks clipping and two-field,
  six-site rollback when Float32 rate overflows only on the second substep;
  it inspects the live settled owner, not just the pre-step saved cache.
  Retry and actual Metal remain required; no pass inferred from review.
- Combined33106 now passed history ownership, mixed symbolic mutation and
  owning host-observation rollback units in addition to scheduling/boundary;
  expression scales and logical-state mutation are running. Core93479 passed
  structured transactions and parallel trackers and continues to later units.
- Root inventory audit found historyaff08847 omitted its shared
  history_structured_samples.jl fixture from POTTS_TEST_FIXTURES. Its ordinary
  scientific test does include/run that fixture, so this is registration debt,
  not missing numerical execution. Owning idle history branch will correct and
  test inventory separately; do not edit live integration33106. Expect its
  unchanged inventory assertion to expose this omission at the end.
- Field6049 finished exit1:15 deterministic Sequential checks passed, including
  physical recurrence/continuation, then Checkerboard correctly rejected a raw
  duplicate FootprintUnion. Correct at Potts' existing analyzed footprint union
  and materialization owner: normalize implicit Euler center and authored RHS
  together. No Core admission relaxation. Add negative-rate clipping and late
  multi-site/substep nonfinite rollback witnesses before retry.
- Corrected Core scope88431 completed10/10 CPU checks,2m51.8s; reviewed narrow
  production bridges unchanged. Actual Metal remains queued after numeric6056.
  Scope name decoding also needs full user-symbol preservation and protection
  against unrelated names containing reserved-prefix text.
- Next-group source audit confirms G05 must extend the existing tracker owner,
  not introduce a parallel aggregate store: TrackerSourceView currently carries
  only ownership, shape, periodicity and domain resources; its rebuild/oracle
  protocols cannot yet see user state or parameter publications. Current
  storage strategies cover owner scalars/groups and geometric moments, not
  arbitrary maintained vector/tensor values or bounded-rebuild minima. Keep
  source-aware invalidation and removal-of-minimum witnesses in G05 scope.
  No G05 implementation or capability is claimed by this read-only audit.
- Combined ordinary Potts Pkg.test33106 is live on frozen integration
  Potts2fdd5d87/Core215546e/LocalMatha6f4383, using a dedicated environment.
  Selected coverage is all history tests, logical/mixed mutation and host
  rollback, declaration control flow, expression scales, scheduling, public
  boundary and test inventory. This is combined focused validation, not the
  final full-suite/docs/GPU or completion of pending scope/field/array work.
- Core scope2095 failed before the new context evaluation:2 passes/2 errors
  from incorrect fixture scratch count/read footprint. Corrected to the
  existing site-stage contract; unchanged production rerun88431 is active.
  Numeric selection-boundary diagnostic6056 remains active on actual Metal.
- Focused root35016 completed exit0:844/844 structural scheduling, qualified
  initial selection/conflict, and public Core boundary checks,3m49.3s. The
  redundant declaration initial was removed without weakening conflict tests.
- Mixed60906 completed exit0:416/416 shared CPU/actual-Metal mutation and
  ordinary host-refresh rollback checks on2e88b7ba/Core311394b/LocalMatha6.
  GPU released for the numeric selection/publication isolation diagnostic.
- Shared scales60495 completed66/66 and saved3771488b; joined Potts integration
  a2d0508a. Core integration215546e joins history882 on31c without touching the
  live full-suite snapshot. Field brancha1862647 now runs ordinary explicit RHS
  plus existing field shorthand witnesses in6049; no field pass claimed yet.
- Read-only review of the narrow Core scheduled-anchor bridges and common
  identity fixture found no blocker. Owner CPU2095 is running; actual Metal
  and unchanged public scope-anchor checks remain before joining.
- Isolated codex/structured-authoring-integration now joins public boundary
  3fdbd18c, declaration9ed9a859, historyaff08847, state mutation910dd09d and
  mixed mutation2e88b7ba. Additive documentation/test-inventory conflicts were
  resolved preserving both histories and mutation tests; diff-check passes.
  No combined validation claim: it still needs Core history8822297, pending
  scope/units/field/array work, the scheduling fixture correction and full tests.
  Root focused35016 and Core full93479 remain live on unchanged snapshots.
- Full Potts70710 finished exit1:3438 passes,1 failure,1 error across3440
  assertions,112m45.2s. The boundary failure is the already-reviewed missing
  public initialize_history! allowlist entry; the scheduling fixture supplies
  initial0 plus system initial2 contrary to the explicit conflict contract.
  Joining the boundary fix and removing the fixture's redundant initial keeps
  its intended system-initial2 assertions. Focused rerun remains required.
  Potts source freeze released; Core93479 remains live and frozen.
- Step-boundary experiment61162 completed exit0 with numerical checks. The
  noinline call-site candidate still reported29.478s for concrete public step!
  compilation, first init238.180s and first step36.838s under concurrent load.
  Cache/flag conditions differ from the earlier baseline, so no comparative
  speedup is established. Removed the isolated uncommitted noinline change;
  retained the ordinary benchmark8c44a238 and both traces for diagnosis.
  Full owner sessions70710/93479 were polled and confirmed live afterward.
- Additional scope witnesses expose missing scheduled cell/site anchor context
  callables; the scoped source remains frozen while15671 completes. An isolated
  Core companion will delegate existing stage identity owners, including the
  compiled contexts, rather than add a second anchor representation.
- Fixed-array parameter implementation is assigned: one scheduled manifest
  owns logical shape and flat slot mapping; Core retains scalar storage.
  Derived immutable logical parameter snapshots replace ambiguous flat public
  indexing, with explicit documentation and overlap validation. The first vector
  consumer does not establish arbitrary tensor/dynamic-index support.
- Numeric72850 completed exit1 reproducing runtime Metal checked_trunc_sint
  after select_requests. Both observed banks: open/active true, count/slot/
  anchor/descriptor1, generation1, planned_site_count0, kind2, source101,
  action201, MCS0 and successful status. No observed out-of-range input; Core
  selection versus selected-request Collect remains unresolved. Next isolate
  actual submission boundaries or selection-specific code, not unchecked casts.
  Log is validation-logs/corepotts-product-selection-input-checked-metal.log.
  Mixed60906 now owns GPU on Potts2e88b7ba/Core311394b/LocalMatha6f4383.
- Shared dimensional-scale18386 completed60/60, exit0:48 arithmetic checks
  across both CPU engines/float widths,6 lifecycle creation,4 SI-intermediate,
  2 dimensionless-reference checks. Precompile329s and dense first testset
  11m24 explain the quiet interval. Add reviewed public scoped BigFloat precision
  plus negative-power/ambient-precision checks before saving and joining field
  RHS; no general unit guarantee inferred beyond exercised operations.
- Mixed symbolic transaction anchor saved2e88b7ba on its isolated branch after
  prior production/compatibility508CPU checks and independent fixture review.
  Includes shared mixed/host-refresh backend fixtures; the extracted CPU/Metal
  cohort is explicitly pending, not inferred from previous state-only checks.
  Root full-suite snapshots remain unchanged.
- Corrected scoped60259 completed25/25, exit0,9m24.4s: actual two-population
  structured updates/site process on both CPU engines, qualified Effects,
  same-kind captured-anchor rejection and parent-owned whole-array imports.
  Target-storage-kind validation, wrong-kind qualified-ID negative and actual
  anchor-valued execution control remain before saving the complete slice.
  Numeric Metal72850 remains active on its separately frozen source.
- Isolated codex/step-compilation from benchmark8c44a238 tests only a call-site
  Base.@noinline at CorePotts.advance_mcs! in Potts step!. No alternative path,
  source selector or semantic change. Environment setup37599/6944 completed;
  overlapping dependency versions match the baseline. Benchmark/trace61162 is
  live with --compiled-modules=existing. Before adoption, compare a baseline
  with the same flag/cache conditions and test correctness/warm execution;
  this uncommitted experiment is not a demonstrated optimization. Its sources
  and shared Core31c1fd4/LocalMatha6f4383 remain frozen while it runs.
- Compilation trace62801 completed exit0 and preserved benchmark correctness.
  Largest reported specialization: public step! on the concrete PottsIntegrator
  28.844s; initialize_program6.288s; LocalMath.prepare6.143s; checkerboard
  preparation/launch specializations also appear. These timings identify
  profiling targets, not exclusive costs or a proven optimization. Full run
  first-init356.577s/first-step33.359s under concurrent load; no speed comparison.
  Trace retained at potts-compound-model-checkerboard-compile-trace.jl.
- Public structured-history Metal64569 completed24/24, exit0,17m48.8s on
  immutable Pottsaff08847/Core8822297/LocalMathe51eeaf: vector/tensor/product
  samples, units, depth257/lag256, feedback and same-declared-Metal checkpoint
  continuation. Device released to corrected numeric selection diagnostic,
  then mixed-mutation Metal. Units18386 remains active; no history source edits.
- Mixed compatibility70965 completed508/508, exit0,13m42.6s: ordinary full
  SciML indexing, callbacks/replay and mixed transactions, including immutable
  problem ArgumentError. Production now unchanged while mixed and owning
  host-refresh fixtures are shared across ordinary CPU and Metal entrypoints.
  Actual mixed device publication/host-refresh rollback remains pending.
- Independent review of benchmark8c44a238 found no blocking issue: public
  execution path, simultaneous-swap oracle, fresh repeated init, checks outside
  timing, and qualified measurement guidance. Section totals are not total
  process startup: package loading and driver compilation before first @time
  are excluded. Built-in --trace-compile-timing support verified in Julia1.12.6;
  diagnostic62801 now collects per-specialization timings for model/checkerboard
  on unchanged sources. This is profiling, not a second executor or threshold.
- Compound compilation diagnostic saved8c44a238 with contributor instructions
  after all four configurations passed numerical/ownership/clock checks and
  diff-check. Final site/sequential52171 exit0: structural6.416s, first init
  41.262s (94.94% compile), first step13.346s (99.71% compile), second step
  0.002234s, repeated init0.841s, repeated first step0.000393s. Concurrent-load
  observations are not comparative performance claims. Independent review
  requested; root joined source remains frozen by full owner suites.
- Scoped91822 completed9 passes,2 failures,4 errors. One real completion gap:
  a scoped child reader cannot resolve an enclosing CellKind during subtree
  completion. Reuse context_inventory/qualified references; do not infer its
  consumer population. Other fixture corrections: public nonexported
  Potts.anchor_value qualification, actual public lattice-domain reference, and
  behavioral/Effects equivalence instead of provenance-sensitive structural
  keys. Source freeze released for the approved shared domain/bound correction.
- Compound site/checkerboard59323 completed exit0 with numerical/ownership/clock
  checks. Concurrent-load measurements: structural3.528s, scheduled problem
  0.000410s, first init338.097s (98.35% compile), first step48.938s (99.85%
  compile), second step0.044452s, repeated init2.904s, repeated first step
  0.009892s. Init13.554GiB is cumulative allocation. Benchmark was formatted
  only after its run ended; final site/sequential configuration now follows.
- Compound model/checkerboard70739 completed exit0, correctness checks passed.
  Under concurrent validation: authoring0.141s, structural4.870s, scheduled
  problem0.000647s, first init211.722s (98.90% compile), first step44.694s
  (99.86% compile), second step0.023075s, repeated init1.827s, repeated first
  step0.010170s. Allocation13.101GiB at init is cumulative, not peak memory.
  This identifies a reproducible cold checkerboard compilation consumer; no
  speed comparison claim under concurrent load. Site/checkerboard follows.
- Corrected mixed77852 completed404/404, exit0,6m24.1s: actual late Core
  descriptor rejection after parameter publication, pending/finalization rules,
  history/u/state/parameter preservation, continuation, all provider kinds and
  both-CPU state/parameter/mixed host-refresh rollback. Next is the identified
  immutable-target ArgumentError method and ordinary SciML/callback consumers;
  final mixed Metal validation is still required.
- Public state setter95562 completed134/134 (67CPU+67actualMetal), exit0,
  13m40.4s, on immutable Potts910dd09d/Core311394b/LocalMatha6f4383.
  Shared checks cover structured/full-slot values, units, histories, callbacks
  and checkpoint continuation with scalar indexing disabled on Metal. Device
  released to public structured history. This validates the original state
  setter, not the newer mixed setter; mixed77852 remains live, with an explicit
  immutable-target ArgumentError compatibility correction queued after it.
- Compound model/sequential20818 completed exit0 with both-value/ownership/clock
  checks passing. Julia1.12.6 under concurrent validation: package precompile177s
  outside timings; authoring0.127s; structural compile4.154s (93.92% compile);
  scheduled problem0.000537s; first init22.737s (96.21% compile); first step8.707s
  (99.76% compile); second step0.000523s; repeated init0.892s; repeated first step
  0.000276s. This isolates cold compilation, not a general speed claim. Fresh
  model/checkerboard diagnostic now follows; source and environment unchanged.
- Mixed30351 completed381 passes and one fixture error: checkpoint correctly
  rejects the fixture's intentionally pending parameter batch. Preserve that
  rejection; clean up through an ordinary successful public publication before
  continuation comparison. Production was unchanged; corrected fixture and
  late-Core rejection regression are next. Setter Metal95562 remains live.
- Explicit field RHS review found a shared reference-scale issue: independently
  normalized multiplicative operands are not automatically in the result's
  reference coordinates. A final Euler factor alone cannot fix internal sums.
  Review the existing lower_static_node/manifest unit invariant and correct its
  sole lowering owner with independent non-field numerical tests; no duplicate
  unit analysis or field-specific expression evaluator. Work remains isolated.
- Compound compilation diagnostic20818 launched for model/sequential after
  strict docs completed, using the existing joined environment. It is live;
  no timings or performance claims yet. Full Potts70710/Core93479 remain live.
- Strict Potts docs10016 completed exit0 on declaration9ed9a859/Core31c1fd4/
  LocalMatha6f4383: doctests, document checks, cross-references and HTML rendering
  passed with deployment disabled. Declaration checkout remains clean. This
  releases its docs source freeze, not the separate full Potts70710/Core93479
  freezes; newer unjoined history/setter/scope/field-RHS work is not covered.
- Isolated codex/compound-compilation starts from Pottsf082e909 and adds an
  ordinary benchmark/compound_compilation.jl consumer for model/site compound
  swaps on both CPU algorithms. Separate fresh-process runs report authoring,
  structural compilation, scheduled problem construction, init, first/second
  step and repeated-init costs using Julia @time. Both swapped values, ownership
  and clock are checked outside timings. Syntax parsed successfully; runtime
  execution remains pending until current heavy validation frees resources.
- Quiet strict docs10016 verified live by its handle and process tree: parent
  27868 has active OrdinaryDiffEqSDIRK and MTKOrdinaryDiffEqRosenbrockNonlinearSolveExt
  precompile children31454/31455, both consuming CPU. Empty buffered log is not
  a stopped build; no restart or source mutation. Full Potts70710/Core93479 also
  remain live; additional history/source-storage groups have completed.
- Existing whole-array parameter enrollment is not runtime array-parameter
  support: immutable setter-base910 probes reject indexed scientific use during
  fixed-shape analysis and reject an unused enrolled array's vector value at
  PottsProblem numeric validation. Mixed setter preserves prior selection
  expansion but must not claim array-valued parameter execution from inventory
  tests. Both diagnostic processes are terminal; this remains a feature gap.
- Mixed publication review requested an owning commit-boundary regression for
  actual Core descriptor rejection after valid parameter publication, using a
  detached candidate and public Core snapshot/state interfaces. Verify restored
  parameters/state, pending values, parameter history, saved observation and
  continuation. Add after the running mixed CPU candidate releases its freeze;
  this is not a claim that invalid values bypass public Potts normalization.
- Core history sampling Metal48896 completed35/35, exit0,8m25.6s on
  Core8822297/LocalMathe51: deferred initial capture, failed-candidate preservation,
  no checkpoint-zero resampling and two-lag continuation on restored Metal.
  State-setter Metal95562 now owns the device; public structured history follows.
  Mixed-mutation CPU30351 is running on its separate frozen candidate.
- Root full Potts70710, Core93479 and strict docs10016 were polled and remain
  live. ParallelTestRunner's installed source documents worker recycling at
  max_worker_rss and reads JULIA_TEST_MAXRSS_MB; the current2.441GiB threshold
  is its ordinary16GiB-macOS default. Recycling may add recompilation, but its
  contribution has not been measured. No live run or memory limit was changed.
- Selection observer CPU precheck83655 completed all34 array accesses across
  both selection banks without advancing simulation. Corrected device diagnostic
  remains queued; this establishes observer validity, not a Metal bug fix.
- Potts history followup saved aff08847a155b08b09a23264411f54e791eaa675,
  parent75dcb305: Eulerian field versus site ownership policy, shared structured
  history fixtures and docs/inventories. Public ownership16CPU and structured55CPU
  passed; structured Metal remains queued. Core8822297/Pottsaff08847 are clean
  and frozen; declared-provider sampling Metal48896 is live.
- Numeric input diagnostic29908 ended on a temporary observer field-path error
  before selection, not a new device failure: only MCS0 was observed. Corrected
  observer will verify all paths/keys before advance and await remaining queued
  history/setter device consumers. Previous select_requests localization89694
  remains the actual evidence; kernel versus publication is still unresolved.
- Complete CorePotts owner Pkg.test launched with one worker against frozen
  Core31c1fd4 and LocalMatha6f4383, alongside full Potts70710 and strict docs10016.
  Memory-pressure inspection reported61% free before launch; no heavy additional
  worker pool. Core source/tests stay frozen until all consumers finish. This
  validates the existing joined snapshot, not unjoined history-clear/mixed work.
- Full strict Potts manual/doctests launched on isolated declaration9ed9a859,
  joined Core31c1fd4 and LocalMatha6f4383 after docs environment5063 resolved
  successfully. Deployment explicitly disabled; all three source snapshots
  remain frozen during documentation execution. Root wholePotts70710 continues
  separately on Pottsf082e909.
- Mixed parameter staging boundary chosen explicitly: normal completed batches
  start from published values and discard prior pending values only on success;
  run_hook=false accumulates a copied pending candidate, finalize commits it,
  pure-state updates leave pending alone, all ordinary failures preserve it.
  This removes previously provider-dependent behavior, preserving integrator
  setp semantics while intentionally making system/problem cached setters agree.
  Document and test all three providers; no compatibility selector or alias.
- Declaration control-flow saved9ed9a859 on codex/declaration-control-flow
  after61 scoped checks and independent review; root joined integration remains
  frozen under70710. Executable loop documentation added; final joined strict
  documentation coverage remains pending.
- Mixed mutation plan approved on separate branch: one cached symbolic setter
  and one commit helper replace duplicate state/parameter publication paths;
  preconvert candidates, retain Core acceptance owners, roll back prior host
  publication on later ordinary validation/refresh failure. Existing pending
  parameter staging and standard run_hook=false remain distinct from commit;
  pure-state updates must not flush pending parameters. Backend-copy/terminal
  runtime failure atomicity is not inferred. Implementation/tests still pending.
- Corrected declaration88424 passed61/61, exit0,4m04.6s (+122s precompile):
  ordinary loops/branches, break/continue, empty loops, outer binding shadowing,
  conditional symbolic enrollment, duplicate rejection and both-engine actual
  model evolution, plus existing lexical/assembly regressions. Independent
  review passed. Saved on isolated branch; final joined docs/owner suite remain
  required, and scientific domain/anchor scopes are still separate unfinished work.
- Core history clear anchor8822297679d04d178a6fcded7607dcb790d85d41 saved
  clean after owningCPU201/shared46/Metal24. Latest samplingCPU count is155,
  including two admission checks omitted from earlier153 summaries. Initial
  capture/feedback same-declared-provider Metal remains pending. Root full suite
  still freezes the joined candidates, so this anchor is not yet integrated.
- Public setter anchors saved on isolated Potts mutation branch: test-only
  1a9d3e97 admits existing public initialize_history! after boundary42412 passed
  764/764;910dd09d saves logical-state mutation with192 shared CPU checks.
  Metal remains pending. Root70710 is frozen, so both commits await integration;
  original mutation checkout stays frozen for device validation while required
  mixed-mutation work moves to its own branch.
- Isolated history ownership95593 passed24/24 on actual Metal, exit0,
  10m50.5s: every retained sample, unchanged/rejected/accepted copies, partial
  batches and late failure rollback. Other history GPU guarantees still await
  declared-device sampling and public structured-history consumers. GPU passed
  to synchronized numeric input diagnostic29908, then Core history sampling,
  public setter, and public structured histories in that order.
- Shared mutation66806 passed192 behavioral checks; Core boundary763pass/1fail
  reflects inherited omission of explicitly public Core initialize_history!
  from the downstream allowlist. Exact test-only correction42412 runs alone.
  Save it separately for the frozen root suite's later integration; do not
  widen the boundary or claim a production private-API defect.
- Declaration13806 ended50pass/1error: nine executed-control-flow checks and
  all41 existing assembly/enrollment checks passed; the numerical fixture used
  a semicolon block default rejected by native Symbolics @parameters parsing.
  Replaced that default with an ordinary helper call, added outer loop-index
  shadow preservation, and restored unrelated Runic hunks. Corrected88424 is
  active on the frozen isolated branch; numerical control-flow claim still pending.
- History device restore investigation resolved an important fixture distinction:
  Potts declares AdaptedProgramBackend{:MetalBackend} before materialization;
  CPU-origin raw Core adaptation has a different capability identity. Same-device
  history continuation will use the declared-provider public construction and
  unchanged restore/adapt path, as existing polarity tests do. No fingerprint
  relaxation, generic restore-bug claim, or production restore change is justified.
- Whole Potts70710 compound-effects group completed successfully:1027.70s test
  time,95.94% reported compilation,47,097MB cumulative allocation (not peak
  live memory). The one-second LLVM sample is consistent with this larger test
  timing. This is a measured developer-latency issue to investigate with the
  actual compound consumer, not an acceptance timing threshold or finished
  performance claim. Full suite continues with lifecycle/cell process groups.
- One-second non-interrupting sample of full-suite compound worker23517 caught
  Julia LLVM module/function optimization, notably dead-store and alias analysis.
  The worker remains live; retained potts-compound-worker-sample.txt is a bounded
  diagnostic, not proof of the complete elapsed-time breakdown. Once current
  validation finishes, measure the actual compound model's compilation cost in
  the ordinary benchmark workflow; do not skip it or introduce timing gates.
- Declaration control-flow independent review found no blocking hygiene or
  execution-order issue. Add an explicit outer-loop-binding shadow preservation
  assertion after13806 releases its source/test freeze, and restore the two
  incidental Runic hunks outside the changed functions before saving.
- [LocalMath PR13](https://github.com/PraneethMerugu/LocalMath.jl/pull/13)
  merged2026-09-09 at b060cf6cecc0a6efb0b5f4029d46b4d433d2d1ab after every
  relevant hosted check passed (package, scientific, docs, macOS smoke, Metal).
  Normal auto-merge request matched exact reviewed head a6f4383; no bypass.
  The chain now has10 merged PRs (7 base +3 demonstrated companions), with41
  identified PRs still unmerged. G04 remains incomplete; full scope unchanged.
- Isolated Potts codex/declaration-control-flow branches from f082e909. Both
  @statements forms now share recursive capture of executed leaves in ordinary
  begin/if/elseif/for/while syntax, preserving condition/iterator evaluation,
  break/continue and duplicate declaration rejection. No runtime scheduler or
  retained control-flow model is added. New helper-splicing/conditional-inventory
  and two-engine numerical tests plus existing lexical/assembly tests run13806;
  this is unqualified until those finish. Source and included tests are frozen.
- Numeric89694 localized its checked integer-narrowing failure to submitted
  select_requests work, before state conversion. Kernel versus Collect
  publication remains unresolved; synchronized input inspection follows after
  history95593 releases the GPU. No conversion-guard weakening is justified.
- Read-only parameter mutation review identified an unclosed atomicity path:
  setp and finalize_parameters_hook duplicate publish/history/refresh work;
  refresh failure currently has no matching restoration, and generic sequential
  parameter staging can leave pending values after a late conversion error.
  Reproduction and a shared commit owner are assigned after saving the validated
  state-setter anchor, together with mixed state/parameter transactions. This
  is not covered by the186 passing state-setter checks or a proven fix yet.
- Public state-mutation42311 passed186/186, exit0,7m24.7s after precompilation.
  Both CPU engines cover canonical scalar/vector/product/site/cell/medium writes,
  chronological histories, invalid batch rollback, parameter setter compatibility,
  callback rollback, checkpoints and injected host-observation refresh failure.
  Scheduled-system reuse/empty-subset additions and actual Metal remain pending;
  no cross-model setter portability or backend-failure rollback claim.
- [LocalMath PR13](https://github.com/PraneethMerugu/LocalMath.jl/pull/13) is open
  review-ready from codex/typed-stage-execution at a6f4383: native trigonometric
  stages and bounds-checked canonical collection. Local validation is complete;
  hosted CI remains pending. Do not request merge until all relevant checks pass
  because this repository has no required-check protection configured.
- LocalMath full actual Metal41962 passed416/416, exit0, including all ordinary
  device inventory and cross-domain scientific witnesses, bounds checked and
  scalar indexing disabled. Together with fullCPU1730, scientificCPU29, strict
  docs and final independent review, the a6f4383 companion is locally ready.
  Preparing its remote PR; hosted CI still required before merging. GPU handed
  to the bounded numeric phase-localization diagnostic89694.
- Isolated history Core58980 passed201/201, exit0, including per-engine failed
  accepted-copy rollback of ownership/source/every retained sample and rejection
  of model/model-history ownership targets. Public Eulerian field/site policy
  witness73459 passed16/16 on both CPU engines. These changes remain unjoined
  pending ordinary fixture factoring, actual Metal and final owner coverage.
- Root read-only review of the corrected public state-mutation path found its
  shared initial normalization/descriptor packing and public single publication
  coherent. Requested explicit scheduled-system setter and empty named-subset
  witnesses after active42311 terminates; no cross-model cached-setter portability
  claim. Full mutation validation and device coverage remain pending.
- LocalMath complete ordinary scientific CPU86402 passed29/29, exit0:
  numerical scientific examples17, compacted examples4, authored-domain examples8.
  Full Metal41962 remains the final active local companion validation. The joined
  wholePotts70710 is separate downstream integration coverage, still active.
- Read-only GitHub verification found LocalMath main has neither classic branch
  protection (404 Branch not protected) nor active branch rules (empty list).
  Repository auto-merge is enabled but does not itself enforce CI completion.
  Do not issue its merge request until all relevant hosted checks pass and final
  review is satisfied; protections were not changed. Recheck exact head and
  checks immediately before merging, with no administrator bypass.
- Final independent LocalMath review of all15 changed files at a6f4383 found
  no blocker. Checked sole comparator ordering/padding/barriers, closed native
  math provenance and recursive fallback, unsafe extension nonexecution tests,
  ordinary inventories and bounded numerical/performance claims. FullMetal41962,
  scientificCPU86402 and wholePotts70710 remain confirmed live; no restarts.
- Complete joined Potts package70710 runs against Pottsf082e909,
  Core31c1fd4 and LocalMatha6f4383 with ordinary two-worker Pkg.test; all three
  production snapshots and included tests are frozen. LocalMath full Metal41962
  and ordinary cross-domain scientific CPU86402 also run on that same LocalMath
  candidate. Final independent combined LocalMath review requested; its PR body
  is prepared locally with pending results explicitly marked, not yet published.
- LocalMath strict full docs71585 completed exit0, including doctests and
  exported API coverage. Documenter emitted a non-fatal missing-navbar-repository
  link warning; no scientific or doctest failure. Complete bounds-checked Metal
  inventory now launched after numeric diagnostic50195 released the GPU.
- Joined Core31c1fd4/Pottsf082e909 now include independently reviewed scalar
  trigonometry, held-turn polarity, and deterministic retained-cell lifecycle
  policies. Integration preserved the scalar/vector numeric conversion contract
  and the move of model-library factories to PottsModels; only overlapping docs
  required manual resolution. Full combined coverage remains pending. New
  site-history clearing and public state mutation remain in isolated worktrees.
- GitHub auto-merge is enabled and verified for Potts, CorePotts, LocalMath,
  MakiePotts and PottsModels. PottsModels remains public. Enable per-PR
  auto-merge after independent review; required checks and ordinary branch
  protections remain authoritative. Older unrelated open PRs were not changed.
- LocalMath complete ordinary suite23934 passed1730/1730, exit0. Public math
  method-owner reflection saved0462339; current main4b2ab42 merged as a6f4383
  with no tree change. Strict full docs71585 now runs on this immutable joined
  candidate. Full Metal awaits the active numeric diagnostic's device release.
- Full strict Potts manual/doctest30840 completed exit0 on lexical16deb2ce and
  Core311394b, deployment disabled. This releases those source freezes; later
  joined exchange/history/mutation changes still need their own final coverage.
- Site-history ownership Core13788 passed74/74 scoped checks, including uneven
  checkerboard batches and every retained sample. Public field/site witness
  remains active. Nested numeric Metal16786 ended with an initial checked
  integer-narrowing exception and follow-on provider failures; isolated compiled
  kernel trace50195 is investigating the actual call site, not claiming a fix.
- LocalMath full14578 terminated1729pass/1fail, exit1. Every functional test
  unit passed; only ExplicitImports rejected the newly qualified private
  Base.Math module access. Replaced it with public parentmodule(binding,
  Tuple{Float64}) reflection guarded by parentmodule(native_owner)===Base and
  exact selected-method owner equality. Independent review confirms user
  Float32/Float64 overrides do not become trusted; recursive fallback remains.
  Full rerun23934 is active and its package_quality unit has passed.
- Deterministic history anchors saved Coree57092c/Potts75dcb305 after Core283
  and public102 scoped checks. Uncommitted site-history clearing is separately
  under review. Potts source-declaration field filtering and Core canonical
  source/shape admission received bounded root review with no blocker;
  numerical clear/field-override witnesses still required.
- Numeric Metal16786 exposed a remaining checked integer-narrowing exception
  during advance/settlement after corrected Collect preparation. Run is still
  live; later provider errors are follow-ons. No nested numeric Metal support
  claim or generalized attribution to Float-to-Int conversion is established.
- Complete lexical exchange factory53343 completed20/20, exit0,2m51.5s.
  The one-block example preserves both-engine geometric depletion/conservation
  and invalid-fraction checks. Example/docs update saved on joined Potts; full
  strict manual remains active on its earlier immutable lexical snapshot.
- Combined LocalMath companion is clean5ccb6a3 on codex/typed-stage-execution,
  joining Collectec352f7 and sined98af55 with only additive contributor/Metal
  inventory conflict resolutions. Complete ordinary Pkg.test14578 runs with
  bounds checks; full joined docs/Metal and downstream numeric still pending.
  Collect's final independent CPU/Metal cohorts passed65/65 each, including
  equal-key/distinct-identity ordering.
- FieldState lifecycle policy mismatch needs semantic resolution, not a rule
  inferred from :site storage. Completion currently differs from lowering;
  independent review is checking Eulerian field meaning and actual consumers.
  Do not impose cell-ownership policies or silently select defaults solely from
  physical layout. Existing SiteState-history clearing continues independently.
- Joined Potts1583d3fc now contains validated lexical16deb2ce and the
  random/history witness8dcbf278. Updated its complete compartment_exchange
  factory to declare variables/parameters inside the explicit-constructor
  @statements block, deleting the separate positional assembly line. Existing
  two-engine conservation oracle runs as53343; source frozen pending result.
- History Core5944 completed283/283, exit0, across physical block extent
  bounds, descriptor SPI, initial sampling/failure and read-only lag feedback.
  Public35765 stopped on one expected namespace mismatch: actual full
  (:parent,:child) rather than (:child,); lifecycle creation file was not reached.
  Corrected frontend retry remains required, not a production-failure claim.
- LocalMath final tie-break witness now requires equal keys with distinct
  identities to reverse source order, alongside unique-key/duplicate controls.
  Earlier warm submission timings have overlapping ranges; they support no
  general speed claim. Final owning CPU/Metal runs remain pending.
- Joined public80528 completed419/419, exit0,16m24.4s after substantial
  precompilation: random-state/history feedback including checkpoint0,
  initialization callback ordering, structured history, scheduled draws,
  declaration assembly and actual assembled model. Source freeze released;
  changed-block formatting/save and lexical integration follow. No full
  owner/docs/device guarantee is inferred from this cohort.
- Strict full Potts manual/doctest30840 is active on lexical16deb2ce and
  Core311394b with deployment explicitly disabled. Those exact source trees
  remain frozen. Its broad docs environment currently resolves Symbolics7.39.0;
  the numerical test environment used7.39.2, so a docs pass would add compatibility
  evidence rather than imply an exact dependency replay claim.
- Lexical54132 completed65/65, exit0,2m46.7s after precompilation. Existing
  constructor equivalence, explicit/automatic inventory ownership, qualified
  symbolic macros, duplicate/alias entries, independent variables, unit-bearing
  unused parameter getp/remake and actual dimensional state evolution on both
  CPU engines passed. Changed-block/new-test Runic followed this run; final
  combined validation and docs execution remain required.
- LocalMath single-comparator candidate also passed primitive89550 at3/3 and
  stronger public21399 at55/55 on forced-bounds Metal. Ordinary fixture
  transplantation, owner suite/docs and reproducible timing are next. These
  results do not yet establish the separate nested lifecycle numeric fix.
- Readability completed actual polarity17796 at122/122, exit0; clean local
  anchors Core12873dc/Potts7d2e5015/LocalMathd98af55 remain unjoined while root
  integration tests hold their source snapshots. This is held-turn polarity,
  not migration/energy coupling or arbitrary public stochastic field RHS.
- LocalMath single-comparator argument-selection experiment now passes original
  forced-bounds public Collect51087 at18/18 on Metal. Primitive and stronger
  ordering/partial/duplicate-identity tests remain pending; no finalized sort fix
  or performance claim yet. No bypass of bounds checks was used.
- Readability's next bounded task is public SII logical-state mutation using
  existing state conversion and Core publication owners, with a scoped API plan
  before implementation. Multi-target failure atomicity, structured values,
  callback-before-initial-history capture, continuation and both engines require
  direct tests; no alternate state registry or private Core contract is allowed.
- Physical history extent errors remain owned by Core layout construction.
  Do not publish BlockLocation just for frontend validation or duplicate Int32
  bounds in Potts completion. Core errors can identify the qualified schema;
  mathematical history errors retain ordinary source-location diagnostics.
- Lexical50853 completed37 passes/1 failure/1 error, exit1. The macro retained
  declarations/evaluation order; the nested-array witness required the already
  implemented whole-symbolic qualification fix, and the missing-state oracle
  incorrectly expected completion rather than lowering rejection. Corrected
  the oracle to the existing exact lowering diagnostic. Saved local unqualified
  lexical754b183b, then integrated joined Potts8d3ad5a3 as61a47f56; additive
  conflicts retained lexical helpers/docs/tests and history changes. These are
  development anchors, not passing/merge-ready evidence.
- Lexical54132 now runs enrollment, declaration assembly and a new dimensional
  two-engine model against joined Core311394b. The numerical witness checks
  default evaluation once, unused unit-bearing parameter retention/getp/remake,
  incompatible-unit rejection and observable stride changes. Public80528 has
  finished history feedback without logged failures and is in initialization.
- Lexical83460 terminatedexit1 before assertions: older Potts lexical branch
  was incorrectly paired with Core's completed-MCS cadence cutover. Created
  matching isolated Core checkout022eb32 (lexical-authoring-support), corrected
  only the idle lexical-enrollment environment, and started50853 with the
  reviewed tests. No production compatibility alias or duplicate execution path
  was added. Source is frozen under50853; docs/example and independent source
  review are present, but numerical/default override witnesses and full lexical
  capture/scopes are still unfinished.
- Independent lexical review found no material macro hygiene/keyword AST or
  ownership issue. Added explicit-entry alias duplicate and independent-variable
  exclusion assertions; source/contributor docs explain evaluation order,
  shallow whole-symbolic enrollment, missing physical-state distinction and
  limitations on helper/control-flow capture. These claims await50853 and docs
  execution; no broader alias recognition or scientific scopes are implied.
- Joined Core48359 completed352/352, exit0,8m04.6s: history sample storage,
  completed-MCS cadence and scheduled-process draws on the merged311394b
  candidate. Public80528 remains live; no full package/docs/device claim.
- Optional @statements PottsSystem keyword-constructor form is implemented in
  isolated lexical worktree, not yet validated or saved. It captures real
  declaration-macro results shallowly, evaluates block then keywords once, and
  calls ordinary positional PottsSystem with merged inventories. Focused83460
  tests unused parameters, declaration defaults/order, qualified macro identity,
  whole arrays/imports, missing physical state and duplicate declarations.
  Plain statement capture remains unchanged; aliases and scientific scopes are
  not broader completion claims. Independent source review is pending.
- Root48359 has completed the history-storage and cadence files without logged
  failures and is executing scheduled-draw tests; public80528 is still in active
  dependency precompilation. Live process inspection confirms CPU activity in
  the compiler descendants; no stalled-run diagnosis or restart is warranted.
- Remaining lexical enrollment review favors an optional explicit constructor
  form on existing @statements, lowering immediately into PottsSystem and its
  inventories. This is not implemented. Preserve ordinary Julia evaluation once,
  resolve actual parameter/variable declaration macro bindings, and distinguish
  symbolic inventory from physical state ownership. Never deduplicate immutable
  statements by equality/identity/name: separate equal constructor results can
  represent colliding declarations. Alias handling needs explicit lexical
  enrollment rules, not hidden tokens or a second registry.
- History lifecycle occurrence review supports reusing the existing occurrence
  coordinate as newest-relative lag, removing the additional sample field.
  Before/Planned semantics need a witness where the values differ; both current
  accessors read the pre-transaction runtime. Agent is checking that baseline
  behavior before claiming planned-state correctness or freezing the next run.
- Joined validated history anchors into Core311394b and Potts8d3ad5a3.
  Conflict resolution preserves both history read proofs and scheduled RNG
  trajectory/boundary/invocation arguments; MCS-zero history uses the shared
  submission-parameter owner. Added public random-state/history feedback and
  checkpoint-zero interaction test using the positional constructor. Root
  public80528 and corrected Core48359 owner run are active; combined validation is
  not yet established. First Core59199 omitted shared test fixtures and was
  deliberately stopped (terminal143); its log is retained, not passing evidence.
- Independent bounded review found no material history/RNG merge issue:
  initialization filters actual history effects, projected reads use the sole
  state-read proof, and ordinary draws retain boundary/invocation identity.
  The new public interaction oracle covers initial no-draw behavior, prior-sample
  feedback, newly published sample retention, checkpoint-zero continuation and
  cross-engine sample equality. This is source review, not a substitute for the
  still-running combined tests.
- Public polarity23384 completed306/306 CPU checks; isolated LocalMath sine
  anchor d98af55 saved after formatted CPU96/96 and prior Metal6/6. Core trig
  followup12873dc saved. Public polarity Metal17796 remains pending. LocalMath
  Collect noinline experiment failed and was reverted; no sort fix claimed.
- User reaffirmed auto-merge: reviewed chain PRs use ordinary required checks
  and protections, without bypass. Current open PR inventory contains no new
  eligible chain PR to enable; older unrelated PRs were left untouched.
- Saved lexical constructor/example anchor0e3a0b76 after227 source-consumer
  checks and20 actual two-engine exchange checks, independent review, and
  changed-block/new-file Runic formatting. Formatting followed the test runs;
  final combined validation remains required. Full lexical enrollment and
  scientific scopes are still missing, not implied by this constructor slice.
- LocalMath sine owner actualMetal53701 completed6/6, exit0, in addition to
  corrected CPU96/96. Public polarity23384 remains live; no full companion or
  whole-model backend completion claim yet.
- Root source-consumer12677 completed227/227, exit0,17m22.2s: declaration
  assembly, ordinary traversal, component replacement, structured authoring and
  compound effects. Together with assembled exchange20/20, this validates the
  current positional-constructor slice. Lexical worktree released; changed-line
  formatting and saving reviewed anchor follow. Full lexical capture/scopes and
  final combined G04 owner/docs/device validation remain unfinished.
- LocalMath corrected unary admission24927 completed96/96, exit0: native
  floating unary methods, unsafe named/captured extension negatives, existing
  access/capture checks and numerical Stage CPU execution. Public polarity23384
  and actual device followup remain pending; no broader device claim yet.
- Initial capture public42240 completed34/34, exit0: callback ordering separate
  from callback-free checkpoint0, whose source99/history7 restore retains both
  without recapture. Saved clean Core6b65f33/Potts84eb91d4 anchors; complete
  owner/docs/Metal validation and explicit whole-window lifecycle remain pending.
- LocalMath intrinsic review reproduced unsafe custom AbstractFloat sine
  qualification when trusting only function name/type. The shortcut now checks
  Base.Math method provenance; literal captured singleton functions reuse that
  same owner after exact type proof. Current corrected owner24927 is pending;
  prior18357 exposed the missing captured-call route, not a reason to relax
  effect checks. Superseded public51276 deliberately stopped before edits.
- History RedrawDaughters correlation is awaiting a nonblocking user choice:
  independent retained-sample draws versus one repeated whole-window draw.
  Deterministic history lifecycle implementation continues; no implicit
  correlation policy has been selected.
- Core initial-history20798 completed187/187, exit0, including actual initial
  capture30 and candidate-abandonment protocol11. Public restore0 oracle remains
  under revision/testing; these Core tests do not establish outer-callback replay.
- Minimal canonical Collect CPU65056 passed18/18; actual Metal19961 reproduced
  the same capacity1 preparation bounds failure without Core, establishing an
  independent LocalMath defect. Isolated owner fix and sine-admission work will
  combine into one G04 LocalMath execution-prerequisite companion after validation.
  Delivery map now records51 identified PRs (48 base plus3 companions).
- Public initial-history45832 passed its first5 callback/prehistory assertions,
  then encountered the existing prohibition on checkpointing outer callbacks.
  Split the tests: preserve that prohibition and exercise restore0 on a separate
  callback-free integrator with deliberately distinct source/held-history values.
  No callback persistence guarantee or widened restoration admission is implied.
- Numeric owner minimal public Collect baseline2032 demonstrated preparation,
  canonical open order and backing values at sizes1/2/257; only its closed-count
  expectation was wrong (closed publication correctly reports0). Corrected
  CPU65056/actual Metal19961 run against unchanged LocalMath e51. No production
  compacted-sort bug is established by this minimal witness yet.
- Assembled exchange19444 completed20/20, exit0,2m47.6s on both CPU engines.
  Independent readability review confirms lexical bindings/provenance, declared
  ownership and geometric conservation oracle. Broader12677 remains live in
  structured-state tests after completed assembly/traversal/component sections.
- Polarity99550 completed129 passes/2 errors: scalar/unit12, complex rejection2,
  Sequential dynamics/reorder/continuation115. Array-trig rejection occurred
  before the fixture's catch; checkerboard hit LocalMath typed-effect admission
  with concrete structured result, so its dynamics and later Float64 case are
  unproved. Owner diagnoses closed-IR rejection without relaxing admission.
- Numeric debug73317 stopped on LocalMath compacted-sort bounds during backend
  preparation, before advance_mcs!. This does not locate the original71042
  lifecycle device exception. Distinct preparation failure is under owning-code
  investigation; no production workaround or broad failure attribution yet.
- Initial capture reruns20798/45832 follow centralized actual-history filtering
  in _history_descriptors; prior Core55577 had accessed cadence on an ordinary
  assignment, and obsolete public29853 was deliberately stopped before editing.
- Added public compartment_exchange factory and ordinary two-engine test on the
  lexical branch: one @statements enrollment, positional construction without
  separate state/parameter tuples, simultaneous conservative discrete exchange.
  Independent geometric depletion values and invalid fraction checks run19444;
  no result yet. Broader12677 passed assembly/traversal sections and is executing
  component replacement; remaining structured/compound sections still pending.
- Initial-history owner55577 and public29853 are live with shared-provenance
  cadence selection, prehistory/callback/save_start and checkpoint0 witnesses.
  Failure test exercises a real inactive candidate then owning expected-status
  injection; it is a publication-protocol oracle, not a fabricated scientific
  evaluator failure or proof of unrelated logical-state mutation ergonomics.
- Root array-owner79324 completed50/50, exit0, covering assembly and ordinary
  traversal. Applied independent-review correction to exclude exact indexed
  import aliases before descending to parameter roots; added completed parent
  ownership regression. Broader source-consumer12677 now runs assembly,
  traversal, component replacement, structured state and compound effects on the
  frozen lexical worktree. No wider compiler regression claim until terminal.
- Initial-history concrete review approves the existing inactive-bank/settlement/
  publisher route and effect-based AtMCS0 selection. Tests must still prove
  shared provenance, callback source updates, old prehistory preservation,
  failure atomicity and checkpoint0 restoration without recapture. Public
  logical-state mutation and arbitrary stochastic DiscreteFieldEuler authoring
  remain separate unimplemented scope; owning tests/internal SPI are not their
  user-facing replacements.
- Structured history14811 completed90/90, exit0: traversal28, atomic scoped
  vector/tensor7, typed lag6 and actual structured history49 across both CPU
  engines. Depth257/lag256, units, product leaves and continuation now execute;
  actual Metal and initial/lifecycle history work remain required.
- Root declaration72546 exposed an unintended fixture observation/state name
  collision, corrected without changing validation. Retry62170 completed20 pass/
  1 failure: whole/indexed parameter reads enrolled separate identities. Public
  Symbolics query probe40304 confirms discovery-only getindex descent yields the
  array owner and symbolic index dependencies. Correction plus ordinary traversal
  runs79324; indexed import aliases must additionally be excluded before descent
  after the active run ends. Full collector regression coverage remains pending.
- Nested product Metal71042 completed10 pass/16 errors: matched positional
  values passed, first numeric conversion threw on-device, later errors followed
  provider poisoning. The type assertion is not an established fix. Owner now
  isolates that same complete transaction with debug information before changing
  code. No unsupported-device or broad product guarantee is inferred.
- Root lexical branch implements a positional StatementSet constructor that
  normalizes owned-state and declared-parameter inventories into the existing
  keyword constructor. Reuses state-declaration discovery and the existing
  symbolic collector; no persistent builder graph. Initial independent review
  found no source blocker and requested array-parameter, external-payload and
  resolved-import witnesses, now added. Environment23048 resolved/precompiled
  successfully; focused declaration-assembly tests are starting. Full lexical
  enrollment and explicit scientific scopes remain separate unfinished work.
- Scheduled actual Metal47677 completed106/106, exit0,14m43: exact addressed
  model/cell/site/substeps and rollback/source diagnostics30, public vector draws
  and same-device continuation/CPU comparisons76, scalar indexing disabled.
  Saved Corecb45fb3/Potts3bc1cc9 anchors integrate cleanly into joined
  Core022eb32/Potts4ad917e3. Focused evidence predates final formatting; combined
  full owner/docs/device validation remains required after remaining G04 changes.
- Reviewed history evaluator simplification removes unused N/Axis/Depth type
  parameters; existing gather relations remain sole indexing authority. Long
  retention run14811 is pending. Earlier structured18674 passed6 typed checks
  and25 Sequential runtime checks, then rejected depth257 in checkerboard law
  admission; no broad structured-history device claim yet.
- Root component86308 completed140/140, exit0,8m03.8s after successful
  precompilation. Shared input/state ownership, flattening, nested readers,
  explicit replacement and initial-unit tests now defend both CPU engines where
  exercised; ci_chain independently reviewed the test-only extension. Joined
  worktrees released. This run does not establish Metal component coverage.
- Expanded Core scheduled86082 completed407/407, exit0: sampler preservation,
  reorder/continuation, late rollback/restored retry, real lifecycle generation
  reuse, coordinate/substep checks and existing compiled proposal consumers.
  Actual scheduled Metal remains pending.
- G04 scope audit confirms lexical one-time assembly is still missing: current
  @statements captures statement expressions, while ordinary PottsSystem keeps
  an explicit MTK variable/parameter inventory separate from discovered storage.
  New isolated potts-lexical-authoring worktree/branch codex/lexical-authoring
  starts at joined1d3fb22. Reuse existing declaration/source traversal rather than
  introduce an ambient builder or retained second graph. No implementation or
  ergonomic-completion claim yet; joined source remains frozen under86308.
- Declared-target conversion CPU94000 completed470/470, exit0, including the
  reviewed native-convert result type assertion. Final actual Metal retry waits
  for the scheduled-process device run; CPU success is not GPU proof.
- Existing public random-consumer regression78410 completed55/55, exit0:
  authored proposal identity/Float32+64 continuation, named initialization and
  lifecycle redraw/partition/relationship policies. Expanded Core scheduled and
  actual Metal runs remain pending.
- Initialization review found source_handle is provenance, not unique descriptor
  identity. History boundary entries will retain their existing immutable effect
  instead of its symbolic reporting tag; inspection derives the label. Initial
  capture must select actual AtMCS0 effects even with shared provenance, without
  a second cadence registry or new source-handle uniqueness requirement.
- Early E09/E10 hardware discovery: configured SSH alias nucbox-rocm resolves
  in ssh configuration to praneeth-nucbox-evo-x2:22, but the connection attempt
  failed hostname resolution before authentication or any remote command ran.
  No CUDA/ROCm device inventory or execution claim follows. Local Metal/G04 work
  continues; remote reachability needs rechecking before accelerator validation.
- The public held-turn polarity consumer requires sine/cosine, absent from the
  current canonical operation catalogs. Extend those existing Potts/Core owners
  with dimensionless scalar contracts and owning CPU/Metal witnesses; do not
  replace the angular law with an easier rational approximation or add a second
  operation registry. Implementation waits for scheduled-source runs to finish.
- Root extended component-sharing and explicit replacement examples' ordinary
  runtime tests from Sequential-only to both CPU engines. Run86308 checks those
  complete owning files plus component initial-unit handling on joined
  Corefdca1f7/Potts1d3fb22; production unchanged, run pending and worktrees frozen.
- Structured history17591 passed6 symbolic type/shape/field-commutation checks
  but exposed namespacing treating a symbolic array as a concrete array to map.
  Existing traversal owners must preserve symbolic-array atomicity while still
  mapping ordinary arrays elementwise; runtime structured-history support is
  not yet established.
- Expanded scheduled Core45749 completed261 pass/6 oracle failures. The
  independent oracle used repeat0 while the lifecycle fixture initializes with
  default repeat1; public RNGAddress reconstruction reproduced all three observed
  values with repeat1. Test-only correction now runs with existing proposal-draw
  regression consumers (86082). Actual scheduled Metal47677 runs a separate,
  explicit-repeat fixture; neither pending run is claimed passed.
- Reviewed typed lag implementation preserves Symbolics type/shape and commutes
  existing product-field selection through whole-sample lag. Structured public
  tests now exercise physical vector arithmetic, whole product/tensor assignment,
  namespaced fields, depth257 runtime windows and continuation. Results remain
  pending; deep retained-index reads still need an explicit witness.
- Type-indexed nested conversion CPU84155 completed470/470, exit0. Actual
  Metal89480 completed130 pass/7 errors: matched positional and all named
  products execute, while numeric positional conversion loses inference before
  the existing finite-value check. The next correction asserts the declared
  target type at the sole native convert boundary; CPU/device retries remain
  required. No broader product-device guarantee is claimed.
- Public scheduled41950 completed131/131, exit0: authored model/cell/site
  draws, vector Uniform/Normal and Bernoulli, unequal selected cell areas,
  declaration reorder/noninterference and checkpoint continuation on both CPU
  engines. Expanded Core transaction and actual Metal witnesses remain pending.
- Public history26738 completed120/120, exit0: scalar cadence/two-lag feedback
  and continuation on both CPU engines plus source, units, capacity, malformed
  lag and external-operation admission checks. Structured lag authoring,
  initialization capture and history lifecycle behavior remain incomplete.
- Installed Symbolics7.39.2/SymbolicUtils4.46.4 shape probe47050 completed0:
  owned term promotion preserves typed array indexed arithmetic and whole
  NamedTuple symbolic type; returned product term has no dot accessor. Approved
  whole `lag(history_variable,n)` and leaf `lag(history_declaration.amount,n)`
  through existing product projection, with explicit docs and runtime/unit/
  namespace witnesses. No wrapper or reconstructed-product authority.
- Public history1321 stopped on fixture capacity expectation after correctly
  selecting source value2 rather than policy-input9. Declared max_cells1 aligns
  that source-selection fixture; no production change. Retry26738 runs feedback
  first, then source-storage cases. Separate reserved-capacity witnesses remain.
- Public scheduled41950 and expanded Core45749 are live after correcting the
  fixture's explicit Normal(0,1) constructor and affine-uniform endpoint bounds.
  Expanded tests cover reorder/continuation, late iterated rollback with
  restored-checkpoint corrected retry, and real remove/create generation reuse.
- Public scheduled RNG review caught an overly strict affine-uniform range
  assertion: Float32 muladd(prevfloat(1f0),1f0,2f0) equals3f0. Preserve existing
  RNG arithmetic and adjust bounded-range expectation; primitive open01 and
  transformed distribution endpoint guarantees are distinct.
- Structured history API review requires preserving both whole-product lag
  assignment and leaf/index access. Existing typed symbolic promotion/field
  projection mechanisms are being evaluated; returning only reconstructed fields
  or introducing generic Symbolics property piracy is not an acceptable shortcut.
- Initial recursive productCPU52403 completed470/470, exit0,9m36.2. Actual
  Metal19005 exposes runtime DataType-tuple/fieldtypes inference errors before
  execution despite direct inferred-Bool checks. Keep source frozen until that
  run terminates, then use type-indexed recursion without changing conversion
  semantics or weakening device admission.
- Isolated inference of the logged SciML tuple-conversion signatures completed
  without assertion (one/three inferred methods), exit0; this does not reproduce
  the MTKBase precompile-context failure. Exact environment is Julia1.12.6,
  MTKBase1.69.0/SciMLBase3.53.1/SymbolicUtils4.46.4. No matching upstream issue
  was located and no dependency/runtime compiler settings were changed.
- Core history7857 completed151 checks, exit0:77 sample storage,12 readonly
  admission,18 actual two-lag/continuation across both CPU engines,30 existing
  model read checks,14 cadence. Public Potts73549 failed after37 source-storage
  checks because host admission still expects a runtime :lag operation rather
  than the authenticated projected read. Frontend correction required.
- Scheduled Core18456 completed48 sampler checks plus28 actual model/cell/site/
  substep coordinate assertions across both CPU engines, exit0,4m49.4. Inline
  constructor helper resolved LocalMath source admission without weakening it.
  Public authoring/rollback/device witnesses remain outstanding.
- Root merged-main completion59540 completed98/98, exit0. Dependency
  precompilation succeeded but MTKBase emitted a Julia1.12.6 compiler assertion
  about irinterp heavy recursion while inferring a SciML DynamicalODEFunction
  tuple conversion. Preserve full log; passing tests do not establish a
  warning-free cold build. Original joined worktrees released.
- Joined validated numeric67846 into current Core asfdca1f7542f1eb286344b3e16a6776e71fee30ff.
  Production merged cleanly; docs conflicts replace obsolete conversion caveats
  while explicitly limiting the new claim to scalar/fixed-vector values until
  nested-product fix joins. Full joined validation remains required.
- Reviewed cancellation fix committedbe325210 in joined Core (workflow only;
  active Julia source unchanged). Independent review confirms noncancelled
  failed/malformed selection still fails closed; cancelled workflow can stop.
  Updated merged Core31/Potts52 bodies with exact final hosted results and tree
  equivalence rather than leaving publication-time pending status authoritative.
- Settlement source review confirms true initialization failures need a narrow
  InitializationSettlement reason: allow failure MCS0 only when submitted and
  committed are both0 for that reason. Ordinary publication invariants remain;
  history owner must present implementation and atomicity/restore witnesses.
- Workflow-only Core joined change replaces Metal job always() with explicit
  !cancelled(), preserving conservative selection and first-step invalid-selection
  failure. Motivated by observed superseded run requiring force-cancel; official
  GitHub cancellation docs confirm behavior. Ruby YAML parse and diff check pass;
  independent review requested. Active Julia source/tests remain unchanged.
- History corrected-ABI owner7857 is live with the approved public expression
  handle query reused by owning Core validation. Runtime/frontend history support
  remains under implementation, with initialization/lifecycle captures pending.
- Recursive product guard reviewed: standard convert applicability and exact
  field count precede one tuple traversal, reusing existing scalar/vector leaf
  checks. CorrectedCPU52403 and actualMetal19005 now run full nested product
  transactions, standard conversion controls and inference; sources frozen.
- History79484 passed77 sample-proof,12 complete-program read/write-admission
  and9 Sequential two-lag/checkpoint checks, then failed checkerboard history
  inference. Owner identified positional parameter access and gathered sample
  value extraction errors in the new law; correction precedes next run.
- Nested product baseline28213 completed266 pass/2 guard failures/12
  checkerboard conversion errors, exit1,6m43.8. Sequential220 and checkerboard
  valid40 demonstrate actual admitted product storage; invalid leaves and tuple
  arity remain genuine guard defects. All numeric cohorts terminal; owner now
  implements shared field-count/applicability/recursive leaf validation.
- Merged published mains into idle joined worktrees: Core1b3ba97 and
  Potts1d3fb22. Neither changes production src versus prior6408/918. Potts
  documentation conflict preserved structured authoring; diagnostic conflict
  preserves enclosing-root namespace. Root59540 runs ordinary completion/
  diagnostics file in verified joined environment; original joined paths frozen.
- Numeric validated scalar/vector anchor67846c622aeb64e19e58f948c095a8ba8730c72a
  excludes pending nested-product tests. Baseline28213 confirms throwing
  checkerboard conversions for nested leaves plus incorrect tuple-arity guard
  admission; preserve terminal outcome before recursive predicate correction.
- Corrected numeric actualMetal37155 completed719/719, exit0,12m31.5s,
  complementing CPU1537. Covers admitted scalar/vector integer/Bool checked
  transactions including subnormals and primitive device conversion predicates.
  GPU released; nested-product baseline28213 still live, so its additional
  conversion semantics are not credited to this passing scalar/vector anchor.
- Core PR31 reviewed headd7a4d08 passed all applicable hosted checks:
  package25m44, Metal11m28, docs2m18 and macOS smoke1m20. Marked ready and
  normal auto-merge succeeded preserving ancestry as
  7b30a1d46a579d35f9cc29ed13dadc8ce5b9996f at2026-09-09 01:59:59UTC.
  R01–R07 and both identified companions are now merged; this does not mark
  G04 or the remaining full chain complete. Integrate current mains into the
  next coherent candidate and validate its exact selection.
- Corrected numericCPU11372 completed1537/1537, exit0,10m41. Includes scalar/
  vector transactions, admitted checkerboard integer bounds, Sequential Int8/
  Int64 and direct Float32/Float64 conversion oracles. Metal37155 and nested
  product baseline28213 remain separate live cohorts; production frozen.
- Scheduled/history merge point coordinated explicitly: shared submission
  helper defaults to minimum_mcs1, history alone requests minimum_mcs0 and
  initialization invocation0. Initial execution must select only actual AtMCS0
  sampling entries; this does not authorize ordinary stage execution at zero.
- Potts PR52 passed every applicable current-head hosted check: package51m12,
  Metal33m08, docs11m37, integration27m47, exact replay11m19 and macOS smoke22m18.
  Marked reviewed8e666dd0 ready. Normal merge-commit attempt was rejected by
  GitHub's merge policy; normal auto-squash succeeded without bypass as
  4c4c9ebb0681973863bd5a2f8c0eacf5efa2e18c at2026-09-09 01:56UTC. Downstream
  branches must incorporate the merged main and validate their final selection.
- Potts PR52 hosted Metal passed33m08; Core PR31 hosted Metal passed11m28.
  Both current reviewed heads now await only their package checks. No pending
  job is credited as passing and both remain draft until complete.
- Reviewed actual history descriptor-factory extraction: no duplicate layout,
  draw allocation or sampling descriptor owner. Approved moving contextual
  proposal/parameter-constraint state-read validation from DescriptorExecutionPlan
  to CompiledPottsProgram, where actual history sampling effects exist. Keep
  intrinsic descriptor/source checks in the former; one cross-plan validator
  must reject invalid reads before runtime preparation, with updated tests/docs.
- Core history cold-contract10137 completed91/91, exit0:77 sample-view,
  no-copy/range/empty-domain checks with retention257 plus14 shared cadence/
  direct lifecycle-admission checks. Initial fixture write footprint was invalid
  and corrected before rerun. Runtime lag/initial capture and device behavior
  are not established by these cold checks.
- Shared sampler preservation/inference fixture passed48/48 for Float32/64,
  three semantic streams and all existing distribution transforms. Approved a
  small immutable invocation context reused across actual host/gathered stage
  consumers, retaining only facts needed by the existing address protocol.
- Numeric subnormal correction now runsCPU11372 and actualMetal37155 on frozen
  source/tests. Full transactions cover signed zeros, both subnormal signs,
  normal fractions and scalar/vector Int32/UInt32/Bool. Int8/Int64 keep
  sequential transactions and direct conversion oracles without claiming
  unsupported checkerboard state banks. No passing result inferred yet.
- Scheduled sampler extraction review matched prior proposal, gathered-proposal
  and lifecycle addresses, trajectory keys and distribution transform ordering.
  One shared RNG-owner transform replaces the three copies; existing-context
  exactness tests and new scheduled context tests remain required.
- Joined Potts22725 completed261/261, exit0,37m14 at918e8e29/fd47f9a/e51.
  All ten selected ordinary files completed, including compound effects. This
  joins Core525 and model/cellMetal17 evidence; full owner/docs/history/numeric/
  process-RNG integration remains separate. Original joined worktrees are now
  released for reviewed helper/docs cleanup.
- G05 source audit confirms no maintained-minimum implementation: current
  tracker contracts admit ownership/relation sources only, source views omit
  logical state/parameters, and updates assume bounded additive owner deltas.
  Potts minimum currently lowers as a gathered reduction, which does not meet
  current-minimum removal or source-mutation invalidation requirements. Extend
  the existing tracker owner/public source contract, not a parallel quantity
  registry; include stage/native/parameter/lifecycle mutation witnesses before
  claiming maintained quantities.
- Numeric final-sourceCPU14458 terminated750 pass/8 admission errors (Int8 and
  Int64 checkerboard banks); Metal47485 terminated314 pass/8 fail/7 errors.
  Numeric main files passed450CPU/225Metal, but UInt32 lower-bound tests found
  negative Float32 subnormal accepted as zero on device. This is a conversion
  contract defect, not a permitted scope restriction. Approved reuse of Base's
  bit-based issubnormal in existing float→integer/Bool predicates; reject both
  signs of nonzero subnormal, preserve signed zero, and rerun actual Metal.
- Cadence audit found direct Core lifecycle plans lacked positive-value
  admission even though Potts validated it. History owner added one cold shared
  validator before the lifecycle zero-request shortcut; direct-SPI negative
  tests still required. History alone admits explicit AtMCS0 capture.
- Joined Potts22725 is authoritatively still live in its last compound-effects
  file. Preserve those original worktrees, but begin the approved scheduled RNG
  slice in separate worktrees from committed fd47f9a/918e8e29 with the reviewed
  d7 cleanup there. Independent implementation need not wait for a frozen
  source run; no overlapping local Metal job is authorized while numeric runs.
- History source/storage92555 completed36/36, exit0:33 source-domain,
  dimensional sample and Every(2) checks plus3 ordinary CellState canonical
  capacity checks. This is SequentialCPU evidence, not lag/AtMCS0/checkerboard
  validation. Frozen sources released for the next implementation slice.
- Followup history source/storage review found Bool retention accepted through
  Julia's Integer subtype relation; the owner will reject it with an ordinary
  public diagnostic test after frozen92555. Verified canonical layout/schema
  replaces private handle_shape at the downstream capacity consumer. Shared
  cadence keeps Every/periodic on positive MCS and reserves zero for explicit
  AtMCS initialization; lag/capture consumer validation is still outstanding.
- Final numeric CPU14458 exposed an Int8 state-bank admission limitation before
  conversion in LocalMath preparation. Do not expand storage support inside the
  conversion fix or infer a guard failure. Keep independent Int8 guard tests,
  and full-transaction bounds on admitted bank types after live cohorts finish.
- Superseded Core run34297755409 is confirmed cancelled after force-cancelling
  its still-running Metal job. Corrected-head run34298020049 is now executing:
  docs and macOS smoke pass; package and Metal remain pending. Do not change
  this tested head merely to improve cancellation policy; queue the cancellable
  fail-closed job condition for the next ordinary CI-touching change.
- Potts PR52 current-head hosted docs, integration, exact replay and macOS
  smoke pass; Ubuntu package and Metal remain running. R06 and R07 remain
  draft until all applicable checks pass, then use the authorized auto-merge
  workflow without bypassing checks.
- History79071 exposed a private handle_shape dependency after20 model/site
  passes. The owner replaced it with canonical layout/schema lookup, corrected
  the history_source docstring attachment, and started92555. Source storage,
  dimensional lag feedback and runtime capture remain separate claims.
- Approved the next bounded scheduled-process RNG implementation using the
  existing ScheduledProcessDrawStream and address protocol: actual completed
  boundary, scientific before/after-lifecycle boundary, model/site/cell identity,
  cell generation and declared iterative substep. Preserve existing transform
  math and address mapping, reuse one sampler, and test continuation/retry and
  CPU/Metal parity. Implementation waits for the frozen joined Potts test.
- Numeric prior native-comparison CPU78420 completed620/620 (450 numeric,
 170 existing shape checks). Final source-float inference26940 completed with
  no Float64 for tested Float32→integer predicates. Final CPU14458 and
  actualMetal47485 now validate the revised guard and independent integer bounds;
  these results are not inferred from the prior CPU pass.
- Independent cold history projection review found no blocking semantic issue:
  exact declared parent/effect, source shape/type, bank/slot/representation,
  aligned offset, overflow and empty-domain handling. Public history_source's
  docstring currently attaches to a helper and is queued for correction after
  frozen79071. Consumer admission/write rejection and lag runtime still pending.
- MakiePotts PR8 passed complete hosted run34296101494 (Ubuntu package/
  rendering/docs41m52, macOS smoke11m32). Verified exact reviewed heade45eab8,
  marked ready and auto-merged as1ee091a629be76cd18a8a7aee1dabb8659e24fac.
- History singleton61154 passed20 checks before exposing an existing ordinary
  cell-storage capacity mismatch with ForbidExtinction/max_cells3/one active
  cell. Approved using canonical handle/source storage shape for initial padding
  while preserving actual runtime identity count; no dynamic growth or weaker
  fixture. Ordinary CellState and history regression tests are required.
- Source audit confirms remaining G04 user-process randomness gap: public draw
  transfer currently admits Proposal/AcceptedCopy/Lifecycle but not AfterMCS,
  and Core stage contexts have no draw execution. Extend addressed model/cell/
  site processes through the existing RNG owner, with cell generation and
  boundary identity, before claiming the full namespaced process API. Existing
  proposal/lifecycle RNG evidence does not cover those missing contexts.
- Joined public model/cell actualMetal10592 completed17/17, exit0, on
  Potts918e8e29/Corefd47f9a/LocalMath e51. Shared oracle covers boundary-entry
  model input in RHS/condition, typed vectors, unequal areas, wrong-kind/inactive
  slots, ownership and checkpoint continuation. Potts CPU22725 still running.
- Numeric predicate inference37306 exposed Float64 promotion in native mixed
  float/integer comparisons, unsuitable for Metal. Approved source-float bounds
  matching Julia's existing conversion interval, with exclusive upper limit;
  maintain exact boundary tests and no unsafe conversion. Prior78420 scope
  remains distinct from this next device-compatible guard.
- History81793 failed before numerical assertions because canonical model
  source storage is zero-dimensional while history uses a singleton sample
  domain. Preserve model layout/checkpoints and normalize only history view/
  binding; no global representation change. Readability is reviewing dense
  sample projection design with the history owner before implementation.
- Joined Core60076 completed525/525 atfd47f9a/LocalMath e51, exit0.
  Potts22725 and bounded model/cell actualMetal10592 remain separate running
  cohorts; do not mutate their shared Core source before they finish.
- Corrected R07 head d7a4d08 has pending hosted run34298020049 with no check
  rows yet. Superseded old-head041f71b7 run34297755409 was queued and its
  cancellation was requested to avoid redundant CI. Missing check rows are
  not passing validation or grounds for auto-merge.
- History first source/storage/units slice81793 is running in isolated history
  worktrees. Approved construction-only deferred initial capture plus one public
  Core initialize_history! operation: direct freshCore defaults to capture,
  Potts captures after callbacks/before save_start, restore never resamples.
  AtMCS0 replaces newest sample only, preserving earlier supplied prehistory.
- Numeric baseline10976 completed221pass,4 fixture-detail failures and7
  checkerboard InexactError failures. Approved narrow conversion-owner predicate
  for applicable/exact/in-range scalar and recursive fixed-vector conversion;
  preserve existing early nonfinite status rather than changing policy. Native
  Julia boundary comparisons were checked at signed/unsigned float upper bounds.
- Approved direct CompletedMCSCadence semantic cutover to share one pure due
  predicate across lifecycle and history; preserve lifecycle positive-boundary
  validation and history's explicit AtMCS0 initialization contract. No parallel
  scheduler, compatibility enum or retained cadence-report authority.
- Shared mixed model/cell checkpoint fixture finished its public CPU file
  without errors within still-running22725. Bounded actualMetal execution of
  the same fixture is authorized against the frozen joined source, coordinated
  with the independent numeric-conversion branch.
- R07 final independent review found one unused displaced decoder-width helper.
  Root removed its nine lines ind7a4d08, verified no callers, and pushed PR31.
  Fresh corrected-head hosted validation is pending; the cleanup is queued
  for downstream joins after their frozen tests finish. No other blocking
  numerical or concrete-layout review issue was found.
- Numeric lifecycle baseline10976 has reproduced escaping checkerboard
  InexactError for fractional/out-of-range integer and out-of-range Boolean
  conversion. Existing evaluator nonfinite errors remain their original status
  owner; adjust fixture expectations, not scientific failure policy. Baseline
  fixed-vector cases were still running at this observation.
- R07 published as draft CorePotts PR31 at041f71b7, worktree
  corepotts-scientific-contexts/codex/scientific-contexts. Merged maina751963e
  changes only CI/guidance relative to locally validateda4389f4; source/tests
  unchanged. Reinspected CPU18065, geometry253 and actualMetal38+2 logs.
  Fresh hosted validation and final independent review remain pending.
- R06 PR52 final independent source review completed with no blocking finding:
  named operation-contract cutover, sole runtime manifests, preserved fingerprint
  field/value semantics, resolved integration subprocess environment and defending
  tests reviewed. Fresh hosted checks remain pending before auto-merge.
- R06 published as draft Potts PR52 at8e666dd0 on codex/operation-contracts,
  isolated worktree potts-operation-contracts. Integrated verified merged
  main415442dd into previously tested5b092e8f without conflicts; production src
  is unchanged by that integration. PR diff contains only30 operation/runtime
  ownership files, not inherited R02 changes. Combined tests/docs and final
  independent review remain pending; prior scoped evidence stays distinguished
  in the PR body. No auto-merge until ready.
- Corrected lifecycle actualMetal24435 completed85/85, exit0, at the frozen
  Core28600d7/LocalMath e51 pair; CPU45765 passed170/170. Shared fixtures cover
  mixed scalar/vector banks, different vector lengths, failure rollback and
  valid equal-length reshape. Integer/Bool conversion cases remain separate.
- Independent joined binding review found no blocker: one shared model-read
  relation/binding path serves site and cell laws, model-domain identity is
  preserved, and BlockViews rebind existing bank regions without state copies.
  Obsolete model-storage helper and cell-domain validator names are deleted.
  Joined syntax and whitespace checks pass; scientific joined tests are next.
- CorePotts PR30 completed all applicable hosted checks in34295861847:
  full package18m02, strict docs, macOS smoke and actualMetal9m14. Verified
  reviewed headb1f0e2f, marked ready and auto-merged preserving ancestry as
  a751963e0c9716b6f08809e9be75c90149fbdedf. Main/manual-only macOS suite was
  skipped, not tested. This closes R03, not runtime G04.
- Corrected lifecycle conversion CPU45765 completed170/170 at Core28600d7
  and LocalMath e51, including both engines, mixed scalar/vector banks,
  mismatched-length rollback and valid equal-length reshape. ActualMetal24435
  remains pending. This does not establish arbitrary integer/Bool conversions.
- Reviewed the new public mixed model/cell oracle and scoped read-admission
  change; requested direct ownership preservation assertions in addition to
  independently computed vector values, wrong-kind/inactive slots and restart.
- History design decision: explicit initial samples fill prehistory; lag0 is
  newest stored sample and lags count samples, not elapsed MCS. AtMCS0 explicitly
  samples the source once at settled initialization, not on checkpoint restore.
  Ordinary periodic sampling retains its positive-MCS timing. Preserve dense
  retention storage rather than packing whole windows into bounded static values.
- Core cell execution saved cleanly at28600d7fcf55d13f20363d52288de42c16615c5c
  while correctedCPU45765 and actualMetal24435 remain pending. This Git-only
  checkpoint unblocks the isolated final Core join without mutating either run.
  Final Potts branch already includes cell production/fixture commits as
  d1f6ccf6 and679cfb75; integration changes and mixed model/cell tests follow.
- Public cell/retirement run68812 completed18/18 (9 checkerboard CPU,
  9 actualMetal, scalar indexing disabled), Potts c72a4d56/938b9240 and
  LocalMath e51 with the already-loaded applicability-only Core source.
  Corrected conversion actualMetal24435 is now running with the additional
  reviewed length guard; CPU45765 remains active. These are distinct cohorts.
- Further typed-lifecycle validation must include integer/Boolean conversions:
  backend convert can have an applicable method yet throw InexactError, unlike
  the host catch path. Matched and invalid numerical-conversion rollback tests
  are needed before any general structured-value lifecycle guarantee.
- Public cell fixture/docs saved cleanly at Potts c72a4d56 after938b9240;
  CPU40/40 passed, actualMetal68812 still pending on its previously loaded
  applicability-only Core snapshot. Git-only commit did not mutate live source.
  The final Potts join can now proceed independently of that running test.
- CorePotts PR30 hosted Metal and strict docs now passed; full package job
  remains active. It stays draft until complete validation.
- Final join worktrees are prepared without copying frozen cell changes:
  Core `corepotts-logical-state-execution` at fecf5f5 and Potts
  `potts-logical-state-authoring` at e77f7f15. Reviewed integration map preserves
  one stage-domain validator, realized-capacity-only runtime checking, sole
  layout-driven model/cell/site fields, and shared identity execution. Required
  new oracle combines changing model input, unequal-area cell identities,
  fixed-vector updates, inactive/wrong-kind preservation and checkpoint resume.
- History followup must also inspect cadence: current ShiftAppend lowering
  emits a literal-true condition and effect stores target/source/axis only.
  Wider sampling cadence is not established by the existing EveryMCS witness.
- Corrected lifecycle conversion owner test45765 is running against the
  reviewed StaticArray length check; public cell68812 remains a separately
  loaded applicability-only source cohort. Final joined validation must use
  the eventual saved Core anchor, not combine these scopes into one claim.
- Next G04 history investigation: existing ShiftAppend lowering and Wortel
  observation tests exercise retained buffers, but public `lag` feedback is not
  established. Current host operation transfer classifies lag as incident
  relationship access; inspected Core execution has lifecycle history_value
  but no lag implementation. Resolve public lag semantics and ordinary feedback
  tests through the existing history owner after the cell join.
- Additional lifecycle mixed-length witness20536 reproduced a real failure:
  55 assertions passed, one checkerboard invalid-vector-length case threw
  DimensionMismatch instead of reporting failure atomically. Matched vector2
  and vector3 channels and equal-length matrix-to-vector reshape passed.
  The next correction must preserve valid reshapes and use the existing
  invalid-value status/rollback path; plain conversion applicability is
  insufficient. This finding is not a complete backend support claim.
- MakiePotts R05 is draft PR8 at `e45eab8`, based on verified main924ba0a5.
  Reinspected local package, strict-doc, Cairo/GL/WGL, visual regression,
  clean-rendering and native-recipe logs before publication. Fresh hosted
  validation remains pending; WGL evidence is HTML serialization, not browser
  rendering. No rendering implementation or visual reference changed.
- LocalMath companion PR12 is now merged as
  `4b2ab4203ece84b2c23b61467673173b478310d1`. Before marking ready and enabling
  auto-merge, verified main c595f91 and original tested parent135afe4 have
  identical trees, so retargeting introduced no untested source. All applicable
  hosted checks and independent reviews passed. This closes this companion,
  not the broader G04 authoring group.
- CorePotts R03 is draft PR30 at `b1f0e2f`, published against verified main
  `7183bcec`; fresh hosted validation is pending. Independent read-only review
  found no blocker in whole-PR selection, failure handling, immutable sibling
  selection or contributor documentation. Historical docs evidence is not
  substituted for the new hosted run.
- LocalMath PR11 hosted run34294535400 passed package, docs, scientific,
  macOS smoke and Metal checks. Reviewed PR11 was marked ready and auto-merged
  with ancestry preserved as `c595f91c77f72b51d0262f3f27db135ebf8133b7`.
  Companion PR12's stacked-base run34294897711 also passed all applicable jobs;
  it is now retargeted to main and remains draft pending final base validation.
- User explicitly requested auto-merge. After rechecking independent review,
  exact heads, dependencies and all applicable hosted checks, auto-merge
  immediately merged Models PR2 as `51d958586c3656c320cd87962e7edf77657ee499`
  and Potts PR51 as `415442dd556b527342f1b73074a302febc103e80` on September9 UTC.
  Drafts and unresolved validation remain excluded; no release was performed.
- Joined Core `fecf5f5` passed261/261 focused assertions; joined Potts
  `ff1d4607` passed273/273 across14 ordinary authoring files. Three reviewed
  followups then joined cleanly at Potts `e77f7f15`; those subsequent changes
  still require final joined validation with cell execution.
- Models CI companion PR2 was validated at e4b83f8 before merging: independent
  review approved its one-line timeout change, and hosted run34291753484 passed
  the complete model/tests/tutorial workflow in41m29. R01's bounded library
  content remains the user-merged PR1; this closes the pending hosted tutorial
  evidence without claiming calibrated model-corpus or new GPU support.
- Accepted-copy fixture follow-up9b839338 completed the ordinary compound file
 49/49. Independent final diff review confirmed only an extension-only proposal
  constraint and accepted>0 assertion were added; all original mathematical
  assertions remain. It is queued for integration with e1228dba and b2a8f3b7.

- Root quality88066 completed52/52 with exit0 after all three symbolic-type
  accesses use their public owner and optional-dependency expectations match
  the direct StaticArrays dependency. Independent review approved the full
  small diff; the correction is saved for the final joined Potts branch.

- LocalMath structured-value companion is draft [PR12](https://github.com/PraneethMerugu/LocalMath.jl/pull/12),
  head e51eeaf on codex/structured-state-values, stacked on PR11's
  codex/ecosystem-candidate-ci base135afe4. Final-head local CPU1624, Metal345,
  and strict-docs results are recorded in its published body; hosted checks
  remain pending. Neither PR was merged.
- Root quality63122 completed50 passes and2 import-owner failures, now in the
  product getproperty/propertynames implementations rather than statement
  completion. Both remaining Symbolics.symtype qualifications were corrected
  to the same public SymbolicUtils owner and independently reviewed.
  Complete quality rerun88066 is active, log
  `/private/tmp/potts-state-contract-quality-owners.log`.
- The narrow existing backend lifecycle conversion guard is implemented and
  under ordinary heterogeneous CPU/device testing; its actual GPU success is
  not inferred from standalone inference probes.

- Mixed checkpoint follow-up commit is Potts e1228dba (test-only), queued for
  integration after the current frozen conjunction run finishes.
- Corrected Core mixed-domain Metal run7052 (the later reused tool handle,
  log `corepotts-cell-mixed-metal.log`) completed16/16. This supplements the
  unaffected97 prior device assertions; the separate public heterogeneous
  lifecycle conversion failure still prevents a full cell GPU handoff.

- R04 LocalMath CI is published as draft [PR11](https://github.com/PraneethMerugu/LocalMath.jl/pull/11),
  head135afe4 on codex/ecosystem-candidate-ci, verified base mainb699002. Fresh
  hosted CPU/docs results are pending; body explicitly distinguishes historical
  pre-recovery1500/docs evidence from recovered-source Metal207. No merge.
- Root coupled model/site checkpoint3215 completed20/20 with exit0. Independent
  review confirmed the fixed oracle detects early model publication and checks
  continued/restored amounts3,6,10 against model values3,4,5. The test-only
  follow-up is saved for the final joined source; no stronger device claim.

- Joined Core12776 completed261/261 on fecf5f5 plus LocalMath e51eeaf. Coverage
  includes product callable inference/invalid ordinals, model domain/read
  controls, signed energy differences, and complete scalar/vector/record model
  transactions with ordering, zero-dimensional storage, checkpoints, conversion
  and rollback. The new cold validator was active. Joined Potts97338 is pending.
- Root quality63122 has now loaded corrected source after confirmed live
  precompilation; it and mixed-domain checkpoint3215 remain active. No restarts.
- Lifecycle GPU probe found that a plain applicability guard still leaves a
  dynamic MethodError path in inferred code. No production guard was adopted;
  concrete-type dispatch is being investigated without a second evaluator bank
  or excluding the required heterogeneous policies.

- Public cell Metal99059 exited1: its9 CPU assertions passed, but the Metal
  fixture failed compilation before the first device assertion. Invalid IR
  points to heterogeneous lifecycle state conversion in
  `_coerce_lifecycle_state_value` while scalar and fixed-vector retirement
  policies coexist. The required retirement policy remains in the test;
  agents are diagnosing the production path. No public cell GPU pass is claimed.
- Root added an ordinary coupled model/site transaction witness on the idle
  model-read branch: both domains update synchronously, sites consume the
  boundary-entry model value, and checkpoint restoration continues the same
  numerical sequence. Run3215 has20 pending assertions across both CPU engines
  at `/private/tmp/potts-model-site-transactions.log`; production source is unchanged.

- Root isolated `codex/state-contract-quality` from Potts53ad40e8 fixes the
  Symbolics.symtype import-owner failure by calling public SymbolicUtils.symtype
  (already a direct dependency in this branch) and removes StaticArrays from
  two obsolete optional-only checks. Complete quality-file run63122 is pending
  at `/private/tmp/potts-state-contract-quality.log`; no source edits during it.
- Accepted-copy diagnostic95975 reproduced the full-suite assertion failure:
  Sequential accepted7 moves and exercised swaps; checkerboard accepted2
  retractions, so the extension-only authored effect never executed. The fix
  will constrain this swap witness to extensions, preserving all numerical
  assertions rather than treating a no-action trajectory as an execution proof.
- New integration anchors: Core fecf5f5 and Potts18b9b44a join model reads with
  product fields and product-state documentation. Focused conjunction tests
  will use LocalMath e51eeaf; full suites await the cell/validator join.

- Scoped model-read implementation anchors are committed: Core d5bd5a0 and
  Potts43e08f6c. Unrelated formatter wrapping was removed before committing;
  focused pre-cleanup results remain Core30+6 and Potts16+18. These are local
  integration anchors, not review-ready full-group PRs. Readability is joining
  them in new worktrees with product fields d4f76aa/53ad40e8 and docs a34ade45;
  current joined behavior must be tested before stronger claims.
- Full Potts14306 is terminal failed:2322 passes and6 failures out of2328.
  Failures: one accepted-copy seeded numerical assertion, two import-owner
  checks for Symbolics.symtype, two obsolete StaticArrays optional-dependency
  expectations, and one missing vector_rotation fixture inventory entry.
  The accepted-copy case is being diagnosed without weakening its execution
  witness. Fixes belong in the final joined source before a full-suite rerun.
- Corrected Core cell CPU52506 completed153/153: mixed domains60, real zero-area
  retirement12, lifecycle admission47, removal/creation/checkpoint28, and actual
  Reset/Transition6. Corrected mixed Metal remains queued; prior failed fixture
  runs do not substitute for this result.

- Root7052 completed16/16 with exit0 on the corrected authoritative-layout
  preparation and shared cold validator:10 actionable Boolean proposal checks
  and6 mixed model/site update checks on both CPU algorithms. Model-read source
  is now idle, with scoped Core30+6 and Potts16+18 results. Independent final
  review, local anchors, product-field/cell joins, complete owner suites,
  strict joined docs, and actual-device combinations remain required.

- Core cell strict documentation run63405 completed successfully on the frozen
  cell/cold-validation source plus LocalMath e51eeaf. No full joined-docs claim.
- Core actual-Metal82389 exited1 after97 passes: scalar/structured transactions,
  failure atomicity, conditionals, empty domains, and actual Remove/Create reuse.
  Its final mixed-domain test used the already-loaded, incorrect layout-order
  fixture. Corrected CPU52506 and a subsequent corrected mixed-device witness
  remain required. Full Metal inventory is reserved for the final joined tree.

- Public model-energy64218 completed18/18 with exit0: both SequentialCPM and
  CheckerboardSweepCPM executed positive/negative model-coefficient Hamiltonian
  models, with actual accepted growth versus energy rejection and preserved
  coefficient values. This establishes the tested two-dimensional CPU
  occupied-site energy combination, not arbitrary contact/product/device energy.
  Mixed-site7052 remains live and is a separate validation requirement.

- Potts PR51's published body now records its actual successful hosted checks,
  explicitly skipped checks, and the Models tutorial timeout/PR2 follow-up.
  No merge was performed. Local body remains at
  `.worktrees/pr-bodies/potts-model-library.md`.

- Dependency-map allocation is now50 identified PRs: the unchanged48 base PRs,
  required LocalMath structured-value companion, and published Models CI PR2.
  This records actual in-scope work rather than treating the original count as
  a ceiling. Models PR2 still requires successful hosted tutorial completion.
- Independent shared cell/retirement fixture review found no lost numerical
  assertions in the CPU/Metal extraction: selected and inactive/kind controls,
  simultaneous scalar/vector writes, and unit-scaled/product retirement remain.
  The changed ordinary run95853 and actual-device execution remain pending.

- Public model-energy run64218 is testing complete solves on both CPU engines:
  H equals a model coefficient times occupied-site count, and only extensions
  are allowed. Negative coefficients must produce accepted growth; positive
  coefficients must produce actual energy rejection with unchanged ownership.
  Eighteen assertions are pending at `/private/tmp/potts-model-energy.log`.
  This complements, but does not inherit success from, the six Core energy
  evaluator checks. Root source is frozen for this run and7052.

- Core68103 completed30/30: twelve cold stage read/write-domain negatives,
  six proposal-domain negatives, and twelve actionable predicate/continuation
  checks. Independent review found no defect in bounded model/site validation;
  valid joined stage workflows still require execution regression tests.
- Mixed gather64995 exited1 (13 passes, one checkerboard error): preparation
  incorrectly requested descriptor_plan from execution-only CheckerboardKernelProgram.
  The fix threads the authoritative layout through existing cold preparation
  calls instead of adding it to kernel state. Public rerun7052 is live at
  `/private/tmp/potts-model-site-layout.log` with the new validator as well.
- Model energy77870 completed6/6 on its confirmed loaded snapshot: positive and
  negative model coefficients multiply the independent four-to-five-site cell
  energy difference, through both sequential Hamiltonian and gathered anchor
  evaluation; the source model coefficient remains unchanged. This is not yet
  full simulation/Metal/contact-energy coverage. Log:
  `/private/tmp/corepotts-model-energy.log`.

- Run64995 confirmed its source-loaded marker before subsequent Core edits; it
  continues as the prior-loaded mixed-gather snapshot, not evidence for the new
  cold validator. Independent review found the one-endpoint-per-site relation,
  singleton storage view, and site-only publication internally consistent.
- Core now validates stage expression/model ownership and assignment targets
  at the existing CompiledPottsProgram layout/plan join. No second layout is
  stored. Bounds-checked owner run68103 tests twelve wrong-domain controls
  across both engines plus the existing eighteen model-proposal checks;
  `/private/tmp/corepotts-stage-model-domains.log` is pending.

- Corrected mixed-gather test is session64995. Independent review located the
  common cold stage validation join in CompiledPottsProgram, which receives both
  the descriptor layout and stage plan; follow-up will reuse model-read
  validation there without storing a second layout in StageExecutionPlan.
- Public cell/lifecycle run11270 completed40/40 on both CPU algorithms:24 cell
  authoring/domain/scoping checks,8 actual structured retirement checks, and8
  invalid literal controls. Independent review approved the shared manifest
  and existing recursive conversion ownership. Joined/full/GPU qualification
  remains pending; this does not establish every lifecycle/model combination.

- Mixed-read run66462 is terminal:13 passes and1 error. Actionable proposal
  predicates passed10/10; the multi-site update passed3 SequentialCPM checks,
  but checkerboard rejected the model-bound selector in site context. The
  isolated shared stage compiler now routes model reads by declared layout
  ownership through a degree-one relation to the original one-value bank view,
  while retaining lattice-owned publication targets. The corrected test is
  running with log `/private/tmp/potts-model-mixed-gather.log`; no passing
  mixed-checkerboard claim is made yet. Cold malformed-stage validation review
  remains required before this slice can be completed.

- Models CI companion [PR2](https://github.com/PraneethMerugu/PottsModels.jl/pull/2)
  is open at e4b83f8 from merged main4f259dc. Independent diff review confirms
  its only change is the job timeout60→120; tests, strict tutorials, dependency
  selection, and job ordering are unchanged. Hosted completion remains pending.

- Product-field run69343 completed14/14: the shared two-boundary scalar,
  fixed-vector, and nested-Boolean oracle passed7 CPU and7 actual-Metal checks
  with scalar indexing disabled. This is the isolated product-fields source,
  not joined model/cell/relationship support or cross-backend exact replay.
  Full joined owner suites and strict docs remain required.

- Models cancellation cause is confirmed by hosted check102263611821:
  the job exceeded its configured one-hour timeout. Cold setup took23m17 and
  model tests34m51 (65/65 passed); strict docs had only1m46 before cancellation
  while dependencies were compiling. A scoped CI companion will raise the job
  timeout to120 minutes, preserving test coverage and strict executable tutorials.
- Independent review of Core lifecycle action validation matched admission to
  actual source/destination accesses in lifecycle_commit_state.jl. Run37628
  exited1 with75 passes:47 constructor controls and28 lifecycle/checkpoint
  checks. A new Transition test needed a four-request bound rather than the
  three-request Create fixture bound; later transaction/domain files were not
  reached. The agent is correcting that fixture and rerunning the full batch.

- Hosted PR51 checks are terminal successful: docs, changes, exact replay,
  integration, macOS smoke, Metal, and Ubuntu package tests. macOS package and
  sibling-main were intentionally skipped by workflow selection, not tested.
  Models runs34286627599 (merged main) and34286477703 (PR) are terminal cancelled.
  The merged run's model-library test step succeeded, but executable tutorials
  were cancelled around the job's sixty-minute duration. Cause investigation
  remains open; the complete Models workflow is not credited as passing.

- LocalMath empty-domain fix e51eeaf completed its full actual-Metal inventory:
  run85126 exited0 with345/345 assertions, including72 empty-domain controls.
  This supplements full CPU1624/1624 and strict documentation success on the
  same commit. No broader ecosystem GPU claim follows from this owner result.
- Review of model reads found target-context binding overriding a ModelState
  operand's owner in site assignments. The isolated Potts model-state-reads
  branch now selects model binding from operand ownership independently of the
  effect target. Bounds-checked run66462 tests actionable Boolean proposals
  and a three-boundary, nine-site model-plus-site update on both CPU algorithms;
  it is pending, with log `/private/tmp/potts-model-mixed-reads.log`.

| Planned PR | Checkout | Branch | State |
| --- | --- | --- | --- |
| R01 Models library | `/Users/praneethmerugu/Documents/Jiang/CPM 1.6/Potts.jl/.worktrees/PottsModels.jl` | `model-library` | User merged PR1; local tests65/comparison12/docs passed; public remote verified; companion PR2 merged after complete hosted model/tutorial workflow passed |
| R02 Potts library ownership and CI | `/Users/praneethmerugu/Documents/Jiang/CPM 1.6/Potts.jl/.worktrees/potts-model-library` | `model-library-workspace` | PR51 merged as415442dd; 39 focused and1,905 full-owner assertions plus strict docs passed locally; all applicable hosted checks passed |
| R03 Core CI | `/Users/praneethmerugu/Documents/Jiang/CPM 1.6/Potts.jl/.worktrees/corepotts-candidate-ci` | `ecosystem-candidate-ci` | PR30 independently reviewed, all applicable hosted checks passed, merged asa751963e |
| R04 LocalMath CI | `/Users/praneethmerugu/Documents/Jiang/CPM 1.6/Potts.jl/.worktrees/localmath-candidate-ci` | `ecosystem-candidate-ci` | PR11 merged asc595f91 after all applicable hosted checks passed; structured-value companion PR12 also reviewed, fully validated and merged as4b2ab42 |
| R05 Makie CI | `/Users/praneethmerugu/Documents/Jiang/CPM 1.6/Potts.jl/.worktrees/makiepotts-candidate-ci` | `ecosystem-candidate-ci` | PR8 reviewed; local package589/docs/backend matrix and all hosted checks passed; merged as1ee091a |
| R06 Potts operation and runtime ownership | `/Users/praneethmerugu/Documents/Jiang/CPM 1.6/Potts.jl/.worktrees/potts-operation-contracts` | `codex/operation-contracts` | PR52 independently reviewed and all applicable hosted checks passed; merged as4c4c9ebb, tree verified identical to tested8e666dd0 |
| R07 Core scientific contexts | `/Users/praneethmerugu/Documents/Jiang/CPM 1.6/Potts.jl/.worktrees/corepotts-scientific-contexts` | `codex/scientific-contexts` | PR31 independently reviewed and all applicable hosted checks passed; merged as7b30a1d4 with ancestry preserved |

All four active ecosystem main checkouts were inspected clean before work:
Potts `868a22ff`, Core `7183bcec`, LocalMath `b699002a`, Makie `924ba0a5`.
The older planning checkout's unrelated changes are preserved. Worktrees are
isolated from main; local implementation commits are listed below. Published
work includes merged Potts PR51, LocalMath PR11/PR12, Models PR1/PR2,
CorePotts PR30/PR31, MakiePotts PR8 and Potts PR52.
Models PR1 was merged by the user;
the other merges followed the user's explicit auto-merge instruction after
review and applicable checks passed. No release was performed.

The current Models environment is `.worktrees/environments/models`, using the
recovered CI/ownership feature checkouts and the new Models checkout.
Dependency resolution, package precompilation and full `Pkg.test("PottsModels")`
succeeded on Julia 1.12.6: 4 developer-checkout, 36 model, 8 analysis and 17
package-quality assertions. The final Models documentation helper executed all
three tutorials successfully, resolving an isolated copy of `docs/Project.toml`
without modifying the checkout. A one-time comparison against the active
original examples passed 12 saved-trajectory/channel assertions. That comparison
is not retained as another production implementation or permanent downstream
dependency on the old examples.

Aqua's persistent-task check is excluded with an inline explanation: it creates
a fresh project unable to resolve unregistered path-developed dependencies.
Ordinary selected-environment precompilation and loading succeed; the exclusion
does not establish the stronger persistent-task guarantee.

R03/R04/R05 and Models workflows passed YAML parsing, job-dependency checks and
embedded shell syntax checks. Independent review caught and prompted fixes for
selector failures skipping required jobs, rename misclassification, floating
cross-job refs, unchecked developer package identities and bypassed docs compat.
Selected jobs now fail closed, whole-PR diffs disable rename detection, and
multi-job sibling selections require full commit SHAs. Models validates source
identities/paths and builds the declared docs contract. Hosted Actions have not
run. LocalMath's full CPU suite and strict docs passed; CorePotts docs passed.
Generated ordinary test/doc manifests are not PR artifacts.

The first LocalMath GPU attempt used an incomplete disposable environment:
real-Metal stage/receipt checks passed before missing StaticArrays stopped it.
The retry uses the actual `test/metal/Project.toml`, not an invented dependency
subset. That pre-recovery attempt did not finish; the subsequent recovered-source
run completed all 207 assertions successfully.

## Environment recovery and live validation

An environment reset removed all temporary checkouts and Julia processes.
The prior session handles are invalid and unfinished runs did not complete.
The implementation was recovered from the thread's recorded patch calls into
persistent, ignored `.worktrees/` directories in the planning workspace.

Recovered commits:

- Models: `58eec61` (license-only base `9c36b8f`).
- Potts model ownership: `9208ed35`; candidate CI and contributor guidance: `a81e3b09`.
- LocalMath CI: `135afe4`.
- CorePotts CI: `b1f0e2f`.
- MakiePotts CI: `e45eab8`.

The previous Models `1109209` commit was in the removed standalone temporary
repository and is not the current commit. The recovered package has the same
27-file, 963-line implementation allocation; fresh package and docs validation passed.
Prior completed test results above are historical evidence, not completion
claims for unfinished or reconstructed runs.

Recovered-source validation (reinspect live sessions before restarting):

- LocalMath declared Metal suite: completed successfully, 207 assertions; generated test manifest removed.
- Potts model-ownership focused cutover tests: completed successfully, 39 assertions.
- Models setup and complete package suite against recovered siblings: completed successfully, 65 assertions.
- Models strict documentation/tutorial build: completed successfully, including all three executable tutorials; checkout remains clean.
- MakiePotts ordinary package suite with the existing AMD 0.5.3 selection: completed successfully, 589 assertions.
- Potts operational-manifest focused run: original handle disappeared; its OS process tree is now confirmed absent. Three files have successful runner completion rows (initial/remake, runtime/SII, callbacks/replay); the relationship file has no terminal result and is being rerun separately with a persistent exit status.
- R06 latest-source strict docs passed with exit 0 (`potts-authoring-docs-current.log`), including the new executable operation-authoring explanation.
- One-time operational-manifest comparison passed in both checkouts: identical selected dependencies, runtime fingerprints, chosen stored-state/observation/relationship trajectories, and checkpoint checksums; current code restores the baseline MCS2 checkpoint through matching MCS3/4 results (11 accepted copies). Logs: `runtime-continuation-baseline-run.log` and `runtime-continuation-current.log`.
- R06 ordinary integration suite (native coupling, optional extensions, fields, distributed execution): `28689`, isolated copy of declared integration environment; `potts-authoring-integration.log` records terminal status.
- Integration results: 95 checks passed, three child-process checks errored because they used the unresolved repository project instead of the resolved parent. Fix `5b092e8f` inherits the parent's active project; all three checks then passed (`potts-extension-load-order.log`). No runtime/scientific failure was observed in this suite.
- R06 remaining owner suite plus inventory: `27544`, frozen checkout `5b092e8f`, excluding the four focused files above. Logs and exit status are persistent.

Persistent output lives under `.worktrees/validation-logs/`. CorePotts full
suite, Potts full suite/manual, and Makie suite must be resumed or rerun after
checking actual process state; their earlier incomplete runs provide no pass.
The named operation-constructor slice (`7b81d805`) is implemented and undergoing
focused testing and independent review; its 32 constructor assertions passed.
The cold read-group decoder slice passed 21
focused assertions, but compiler-boundary validation rejected its captured
`Val` representation. That slice is being corrected without changing LocalMath
admission; commit `126b953` is not review-ready. The correction passes 26 focused
assertions, including actual evaluator admission and inferred decoding after a
40-read group. Correction commit `ebbeae3` passes the complete 118-assertion
compiler-boundary suite and all 90 real-Metal assertions. Its full CPU suite
remains active; compiled state, decoder, quality and inventory tests have passed.
The geometry/proposal-context slice is committed as `eefe2a0` and passes 253
focused scientific geometry assertions, 118 compiler-boundary assertions, 258
lifecycle-receipts assertions and 90 generic real-Metal assertions. Full CPU
remains active. A separate moment-geometry Metal witness is being added in its
own worktree because generic Metal success alone does not prove centroid and
elongation execution on the device.

Potts CI commit `a81e3b09` passes YAML parsing, all 46 embedded shell syntax
checks, and ten inline-selector cases covering whole-PR changes and failures.
No Actions jobs have been dispatched. Review is checking the combined workflow's
AMD selection against Makie's existing owner workflow and the scope of candidate
continuation claims. Constructor review found the example's arithmetic unit rule
was inappropriate for its custom identity; the current commit explicitly uses
dimensionless units. No further bounded constructor regression was identified.

The proposed additional AMD pin was not committed: a runtime check of actual
AMD 0.5.4 / SparseColumnPivotedQR 2.1.8 confirmed its loaded extension uses the
public `colamd` interface and successfully orders a matrix. An older cached
extension had been mistakenly associated with the current manifest. Existing
Makie package-job selection remains unchanged; combined CI remains unpinned.

R06 source diagnostics are committed separately as `2bd75d4a` with qualified-path
test correction `c2fde695`, pending complete behavior validation. Constructor
scientific operation and external SPI suites completed successfully (65 and 45
assertions). Root committed the operational `reports` cutover as `94544bb3`: explicit
state/relationship/kind manifests replace stored derived reports. Core execution
and capability inspection are derived from Core's public authority. Independent
source review confirms fingerprint payload ordering and projected values are
preserved; the representative pre/post runtime identity and checkpoint comparison
also passed. Test consumers now derive inspection from the owned Core
program, and no live `.reports`/`:reports` access remains in source, tests,
extensions, examples or current docs. Initial/remake and runtime/indexing tests
have passed within the still-running focused suite. This is not yet a completed PR.

The old Core full-CPU run's tool handle also disappeared while OS PIDs remained
live. Its earlier completed subsets are known, but its output was not persisted;
no full-suite pass is claimed from the lost handle. Subsequent Core validation
uses persistent logs. Diagnostic rerun only proves the new 19-assertion source
testset so far, not the whole file. The remaining P03 work is an executable opaque
operation example and ordinary-helper equivalence/documentation, using existing
dispatch rather than adding a new registration or execution path. Example and
equivalence-test commit `8dbe8d25` is present; both example variants independently
passed actual CPU execution. Documentation integration is committed as `933457f0`;
the previous strict build had already parsed its prior pages, so a latest-source
build remains required. The incidental `hasmethod` assertion was removed.
Core ordering confirms Hamiltonian execution occurs before guard rejection.
The additional independent external-energy oracle (`2f24ad47`) passes all eight
checks and verifies nonzero energy signs through acceptance versus rejection.

R05 Makie documentation/backend environments are being resolved separately from
the already-passing package environment. These runs use copies of the declared
projects and do not add dependency pins. Strict documentation and Cairo passed;
GL, WGL, visual, clean frame-to-PNG and the ordinary native-recipe example also
passed. WGL covers HTML serialization, not an in-browser GPU guarantee; its
background-timer precompilation warnings remain in the log. No visual reference
was accepted or changed. The local R05 description is
`.worktrees/pr-bodies/makiepotts-ci.md`.

Local publication drafts are prepared at `.worktrees/pr-descriptions/models-library.md`
and `.worktrees/localmath-ci-pr.md`; these are local drafts, not GitHub PRs.

`gh repo view PraneethMerugu/PottsModels.jl` could not resolve the repository.
The user has been asked asynchronously whether to create it private/public or
keep it local; no visibility/publication assumption has been made.

Automatic security review denied the attempted LocalMath branch push/draft PR
before execution. No remote branch or PR was created. Explicit approval to push
feature branches and create draft PRs in the four existing repositories has been
requested asynchronously; local implementation and validation continue.

## Structured-state continuation

Frozen R07 (`eefe2a0`) completed its full ordinary CPU suite: 18,065 assertions
across 24 files, exit status zero (`corepotts-context-full.log`). The specific
moment-geometry Metal witness remains under validation in its separate test-only
worktree; the generic Metal pass alone is not a geometry-specific guarantee.

R06's separate relationship-transaction run completed all 22 assertions with
exit status zero (`potts-relationship-transactions.log`). The remaining ordinary
owner suite completed 1,878 assertions with exit status zero
(`potts-owner-remaining.log`); the closed-profile Metal run is still active.
R02's strict model-library documentation build also passed on its actual
`a81e3b09` checkout (`potts-model-library-strict-docs.log`).

R07's test-only follow-up is committed at `a4389f4`: the geometry-specific
Metal witness passed 38 assertions, plus two existing stage checks. The shared
CPU geometry oracle rerun passed 253 checks. These complement, rather than
replace, the frozen production full-CPU and original Metal-suite results.

G04 implementation has begun in isolated worktrees, leaving validated R06/R07
sources unchanged. `corepotts-logical-state` (`codex/logical-state`, based on
`eefe2a0`) extends the existing storage owner with recursive finite validation
and product initialization. Its first focused storage run passed 79 assertions
(`corepotts-logical-values.log`); after a generic-value fallback adjustment and
Runic formatting, ordinary storage/descriptor-state/inventory tests are running
(`corepotts-logical-values-owner.log`, session 54958) completed 114 assertions
with exit status zero. Review found and corrected a custom-number finite
protocol regression; its focused rerun passed 80 assertions. Typed stage buffers
now derive logical value types from existing handles, with structured model-stage
and checkpoint tests added for sequential and checkerboard CPU. The first run
failed before tests due to a formatter-altered generated callable signature;
that signature has been corrected and the same ordinary tests are running again
(`corepotts-typed-stages-rerun.log`, session 23940). The separate actual
structured lifecycle failure-atomicity witness passed all 30 assertions
(`corepotts-logical-state-lifecycle.log`, exit status zero): a valid named-product
transition publishes, while later nested NaN/Inf transforms preserve both old
state blocks, ownership, kind, generation, trackers and completed MCS. Tests for
simultaneous versus ordered structured stage updates are being added separately.
Independent review found no demonstrated typed-buffer indexing regression:
slots are resolved separately for accepted-copy, site and model effects and
value types derive from existing handles. Mixed-type/permuted-slot execution
coverage and allocation measurements remain required before stronger claims.
Source inspection also identified a likely existing checkerboard discrepancy:
its boundary compiler schedules evaluate/publication per descriptor, whereas
the sequential path evaluates ordinary assignments before publishing any.
The new swap test must expose and defend the common intended semantics; backend
divergence is not an acceptable alternative expected result.
This alone does
not establish structured stage execution, lifecycle, GPU or full checkpoint
continuation support. `potts-component-replacement`
(`codex/component-replacement`, based on `5b092e8f`) is developing explicit
source imports and identity-preserving replacement through existing qualification,
not a separate builder graph. Neither R08 nor R09 is complete.

### Compound publication and LocalMath product support

R06 closed-profile Metal completed 56 assertions with exit zero; both parent
and child loaded frozen `5b092e8f`, and non-Potts pins were unchanged. The local
R06 body is `.worktrees/pr-bodies/potts-authoring-ownership.md`.

R08 source is anchored at `1eacd82` (not review-ready). Its ordinary rerun
finished with 216 passes and one error: existing state tests passed 113, but
structured checkerboard initialization reached an unsupported global-memory
record-load contract. The swap witness (`3d891ce`, test-only follow-up) separately
passed 30 sequential checks and failed six checkerboard initializations for
SVector physical admission and NamedTuple field admission. These are actual
missing support, not reasons to weaken the intended API or skip the tests.

`corepotts-compound-publication` (`codex/compound-publication`) isolates the
ordering fix from the frozen anchor. It exposes existing evaluation/publication
laws, reuses their allocated scratch through public LocalMath storage access,
and preserves the existing receipt queue and failure bridge. Validation is
pending; a scalar control is being added to distinguish ordering from value
admission.

A necessary LocalMath companion has started in `localmath-product-values`
(`codex/product-values`, based on `135afe4`). It extends the existing storage
predicate to immutable named products and the existing bounded record-layout
validation to nested admitted values. The first invocation selected zero tests
because LocalMath retains `test_` in runner names; this is not validation evidence.
The corrected ordinary run (`localmath-product-values-owner.log`) passed 147
assertions, including nine actual CPU product-publication/rejection checks, and
failed one displaced blanket NamedTuple-rejection assertion. That assertion now
rejects a named product with a runtime Symbol leaf, preserving the metadata
boundary under the new contract. Full ordinary CPU validation is running in
`localmath-product-full.log`; GPU checks, review, and documentation remain required.

The focused actual-Metal product update passed three hardware assertions
(`localmath-product-metal.log`, exit zero), alongside nine CPU checks from the
shared fixture. It preserves Boolean/integer/Float32-vector leaves and input
ownership through the same publication law with scalar GPU indexing disabled.
The full Metal suite and strict docs (including an executable ordinary helper
over a named-product Field) are now running; this focused result alone is not a
general arbitrary-product or atomic/reduction guarantee.

LocalMath's full CPU suite passed 1,509 assertions, exit zero
(`localmath-product-full.log`), and strict docs including the new named-product
example passed (`localmath-product-docs.log`). Full Metal remains active.
Independent review requested routed Unique/Resolve payload and nested-layout
rejection witnesses because the shared record helper also serves those consumers.
Their shared fixture is `test/fixtures/product_publication_contracts.jl`;
the initial targeted run had a test-constructor rank/value argument ordering
mistake, now corrected. The rerun is `localmath-product-routing-rerun.log`,
session 99924; integration into ordinary runners awaits that result.

The compound-publication scalar control now passes eight assertions on both
engines against unchanged LocalMath (`corepotts-compound-scalar-current.log`).
Structured and mixed relationship/state coverage is still in progress; an
existing missing relationship `field_value` bridge is being connected to the
already-owned `state_value` operation, not reimplemented.

R09's ordinary shared-input and explicit replacement examples now have 34
passing focused assertions, including actual trajectories, nested state imports,
single enrollment, and repeated completion. They remain under broader validation
and independent API review in their isolated worktree.

## Latest structured-publication integration

The LocalMath companion's full Metal suite completed successfully
(`localmath-product-metal-full.log`, exit zero). Independent review's additional
routed Unique/Resolve and nested-layout rejection cases now run in the ordinary
CPU and Metal inventories. The integrated CPU selection passed 21/21 including
runner inventory (`localmath-product-integrated.log`); the shared Metal fixture
passed 20 CPU and 14 actual-device assertions
(`localmath-product-metal-integrated.log`). Production source is unchanged from
the full 1,509-assertion CPU suite and strict documentation build above. The
scientific witness suite is additionally running; no result is claimed yet.
Runic checks of all ten changed Julia files and `git diff --check` passed.
Generated documentation/device manifests were removed after those runs; broad
compatibility remains the ordinary contract, not an exact-environment promise.

Core's compound-publication correction now passes all 90 preserved scalar,
vector and named-product transaction checks. The final named-product obstacle
was non-concrete Boolean inference through `all`: the single storage owner now
uses structural Tuple recursion and NamedTuple value delegation. Its standalone
compiled-result IR check also passes without weakening LocalMath admission.
Mixed relationship/state fixture validation and structured site ownership-clear
coverage remain in progress; this is not complete R08 coverage.

R09's scalar component-import/replacement slice is committed at `78cec8cd`, with
200 combined focused assertions and strict documentation passing. Native
source-import/reconnection support is the next bounded implementation; full
R09 owner/integration/backend validation remains outstanding.

LocalMath's companion is locally committed at `87de468` on
`codex/product-values`; its worktree is clean and no remote publication occurred.
The local PR description is `.worktrees/pr-bodies/localmath-product-values.md`.
Final independent review of this anchor reported no blocking findings, checking
actual pointwise/routed payload tests, negative captures/layout cases, unchanged
atomic boundaries and the documented ownership chain. No reviewer edits occurred.
LocalMath's additional ordinary scientific suite completed: 29/29 assertions,
exit zero (`localmath-product-scientific.log`). The final full owner rerun with
the integrated reviewer tests is active as session 11608
(`localmath-product-final-full.log`). R02's outstanding full owner suite is
also active as session 74362 (`potts-model-library-full.log`), with the intended
R02/R03/R04 candidate package paths confirmed by Pkg's test environment output.
The final LocalMath owner suite subsequently passed 1,520/1,520 assertions,
exit zero (`localmath-product-final-full.log`, session 11608 terminal), including
reviewer additions, package quality and inventory checks. Companion `87de468`
is locally review-ready with its documented bounded support; full G04 is not.
R02's suite remains active and no pass is claimed for it. R02's local draft description
is `.worktrees/pr-bodies/potts-model-library.md`. Its copied proposed map still
needs the later companion-count update before publication; no test-running
source checkout was changed for that documentation synchronization.

The next Core focused batch (`corepotts-compound-final-focused.log`, 55898)
finished with ownership-clear 32/32 and mixed Sequential 21/21, but three
checkerboard fixture-construction errors (missing finite read footprint).
The preserved 90-case structured suite was not reached in that command;
its earlier pass remains distinct. The fixture footprint and untouched-value
coverage were corrected without changing production; rerun 99807 completed
with ownership-clear 40/40 and mixed state/relationship 42/42, exit zero in
`corepotts-compound-ownership-relationships.log`. Both CPU engines are exercised.

Root extracted the structured model transaction helpers into
`test/fixtures/structured_stage_support.jl`, deleting their former inline
definitions, and added an ordinary Metal inventory entry exercising actual
SVector/named-product swap and late-failure rollback. The initial invocation
failed before execution because StaticArrays was not declared in the Metal
test project. The dependency is now explicit with broad compat; rerun 78526
is active in `corepotts-structured-metal-declared.log`. No device pass is claimed
yet. CPU 90-case validation after fixture extraction is now running as 37981
in `corepotts-structured-shared-cpu.log`. All four changed root-owned Julia test
files pass Runic and whitespace checks. Independent review confirmed actual GPU
adaptation and meaningful swap/late-failure assertions; after the current frozen
run, strengthen exact failure-source/detail and retained-snapshot checks. Current
ownership is intentionally quiescent, so this fixture does not claim accepted-copy
rollback coverage. Metal run 78526 subsequently completed with 34 passes and two
test failures: successful MCS settlement returns an empty LifecycleReceipt, not
`nothing`. Swap and rollback assertions passed. The fixture now tests empty
success receipts, absent failed receipts, exact nonfinite source/detail, and
retained entry-snapshot logical values. Reviewed rerun 23914 is active in
`corepotts-structured-metal-reviewed.log`; production source is unchanged.
That reviewed actual-Metal rerun completed 48/48, exit zero. Exact nonfinite
diagnostics, entry-snapshot independence and success/failure receipt semantics
are exercised. The root GPU is idle, permitting the separate test-only RNG
arithmetic experiment to use actual hardware without benchmark contention.
The Core strict documentation build completed at 67524, exit zero in
`corepotts-compound-strict-docs.log` (doctests, checks and HTML). CPU shared-fixture
rerun 37981 also completed 90/90, exit zero. The CI owner has been assigned the
full ordinary Core suite next; run 19593 is active in
`corepotts-compound-full-owner.log`. Inventory passed, but the serial package
quality row reports failure; its detailed cause has not yet been emitted. No
full-suite pass or joint compound commit is claimed. Read-only review also
identified a possible conditional model-write ordering discrepancy; the CI owner
is reproducing it independently without editing the frozen source. A quality-only
diagnostic (20274, `corepotts-compound-quality-diagnostic.log`) completed 16 passes
and one failure: private Base.RefValue in three stage-buffer signatures. The
approved repair is the public Ref interface, not an import-check exemption; it
was initially held for the baseline run. The conditional reproduction then
confirmed a defect (34116: 11 passes, one failure): true-then-false writes to one
model target retain 3 sequentially but restore 1 under checkerboard execution.
All-false and false-then-true controls pass. The CI owner is authorized to stop
its exact already-failing full-owner process, record partial coverage, fix both
known defects using public Ref and the existing StageEvaluation enabled/value
carrier, and rerun focused then full validation. This avoids completing a known
invalidated full run; it is not a restart due to observation latency. The exact
19593 process tree was stopped and verified absent. Its wrapper returned exit
zero with `Tests interrupted`, which is explicitly not a pass. Partial file
rows are inventory passed, logical_state_values passed, package_quality failed.
The CI owner now owns the shared CPU/Metal structured fixtures for the actual
conditional-write regression and correction.

The addressed-process RNG audit found that extending the closed existing stream
encoding does not satisfy the accepted namespace/address requirements. A proposed
versioned Philox4x64 contract remains unapproved and outside production. Its
test-only arithmetic experiment in `.worktrees/rng-experiment/` passed 8,322 CPU
assertions and 16 actual-Metal assertions covering full multiplication/generator
arrays and upstream known-answer vectors at three workgroup sizes. This is not
semantic-address, process, checkpoint, or end-to-end performance validation.
Busy-host microbenchmark samples are noisy; no speed claim is made. User approval
was requested asynchronously for a trajectory-changing cutover and rejection of
old-contract exact continuation, subject to further validation. The user delegated
the choice to favor rapid development; root selected the versioned direct cutover,
subject to validation, with no compatibility executor. Implementation must include
the actual public operation-key/address consumers, process scopes and checkpoint
identity; arithmetic feasibility alone is not completion. Current runtime and RNG
contract are still unchanged; other G04 work continues independently. The RNG
owner is authorized to create isolated `codex/addressed-process-rng` at
`.worktrees/corepotts-addressed-rng` from committed `1a5031c`, then integrate the
compound correction by explicit commit after its validation. The approved cold
interface uses a semantic namespace, a concrete operation key, and batch
duplicate/collision-checked derivation; no persistent registry or live fallback.
This remains existing open R08/R09 scope, not automatically two additional PRs.

Native/contextual source is now locally committed at `6f1cbc74` on
`codex/component-replacement`, clean and unpublished. The unchanged-production
combined regression passed 445/445; expanded component/getter edge coverage
passed 106/106; strict docs passed. This is a completed slice, not all of R09.
Root's next isolated branch `codex/compound-effects` starts from that commit to
implement ordinary public compound effect authoring through the existing
effect-indexed expression roots and descriptor execution path.

Earlier native component focused coverage progressed to 36 native, 51 scalar/contextual
replacement, 31 source-traversal and 25 units assertions in the author's latest
combined run. A displaced nested diagnostic path expectation and contextual MTK
getter consistency remain unresolved. Full enclosing qualification must agree
across inspection, runtime and completed symbolic getters in the same cutover;
the original independently completed source remains independently scoped.

The dependency map now explicitly counts the required LocalMath product-value
companion: 49 identified repository PRs, including the 48 base allocations.

## Remaining work

### Updated remote and merge authority

The user explicitly authorized creating a remote for PottsModels.jl and then
authorized merging PRs judged fit. The earlier no-merge restriction is superseded
by that permission; testing, independent review, dependency ordering, and
accurate supported-combination claims still apply. This does not authorize
releases or treating incomplete implementation slices as merge-ready.

Created `https://github.com/PraneethMerugu/PottsModels.jl` as private and connected
the existing local Models repository's `origin`. Verified account/owner and
remote visibility; the repository is still empty and no code was pushed in this
creation step. Existing package PRs have not been merged by this step.

Latest validation and integration update:

- Public model-state proposal run `77298` passed10/10 on the isolated Potts/Core
  model-state-reads branches with LocalMath e51eeaf. Both CPU algorithms execute
  actual model-Boolean predicate rejections; this is not a product-field,
  Hamiltonian/contact, or device guarantee. Additional Potts lowering review is
  requested before integration.
- LocalMath strict docs `91894` completed exit0 on frozen e51eeaf with the full
  declared docs environment, including executable examples and HTML rendering.
  A nonfatal existing remote-link warning remains; no example/check suppression
  was added. Full ordinary owner1,624 and focusedMetal72 already pass; full
  Metal85126 still running at last confirmed agent update.

- Empty-domain diagnosis precision: the confirmed LocalMath defect was an
  out-of-bounds destination READ before traversal guards, not a demonstrated
  write. Independently, the malformed Core Create+Reset lifecycle fixture
  attempts a source-zero WRITE. It was stopped as obsolete (40969 exit143).
  Correct fixture to Initialize and add cold action/effect compatibility
  validation in the existing lifecycle owner; do not change genuine Reset
  semantics. Neither observation alone proves the cause of the earlier GC crash.

- Full ordinary LocalMath `14205` passed1,624/1,624 on e51eeaf (4m07.4s),
  including inventory and quality checks. Strict docs33598 used an incomplete
  loaded environment and failed to import KernelAbstractions; corrected full
  declared environment is now frozen for rerun91894. FullMetal85126 remains
  active; focused actualMetal72 already passed.
- Product component-reference run53416 passed111/111, including the new
  explicit/system-only reference choice and all existing replacement tests.
  A separate symbolic substitution probe found stale shape/ordinal risk when
  changing a product's concrete declared type. Approved same-declared-type
  promotion validation with changedshape/reorderedfield/nestedtype negatives;
  same-type namespaces/imports remain supported, no mutable metadata registry.
- Public structured-lifecycle literal conversion reuses the existing compiled
  state manifest, constructed once earlier, and the existing recursive value
  converter. Root reviewed the plumbing: nine state-value policy branches use
  target type/unit; split fractions and distribution parameters remain separate.
  Ordinary actual retirement and cell focused35772 remain active.

- Model-read domain run `13625` passed18/18 (6 malformed-domain negatives,
  12 actual proposal/continuation checks). Restored the DescriptorExecutionPlan
  docstring after helper insertion and added contributor ownership guidance.
  Root's isolated Potts branch now resolves each model leaf through its declared
  owner and emits the existing model-bound operation. Public Boolean proposal
  witness `77298` is live on both CPU algorithms, not yet a product/Metal claim.
- Full LocalMath owner `14205` and actual full Metal `85126` remain active on
  frozen `e51eeaf`; strict docs `33598` launched with the declared documentation
  dependencies. Corrected Core empty/domain bounds run `91332` passed179/179;
  lifecycle/checkpoint `40969` remains active.

- Model-global gathered predicate `17181` passed12/12 across both CPU engines,
  real rejections and continuation. Root added central descriptor validation
  that requires model-bound operations to reference declared one-value model
  storage and prevents spatial resource reads of model handles. Bounds-checked
  `13625` is running with new malformed-domain negatives. Contact/Hamiltonian
  coefficient and actual device witnesses remain required followups.
- LocalMath empty-domain actual Metal `28752` passed72/72, scalar indexing
  disabled and bounds checking enabled. Reviewed source has matching CPU135
  evidence; approved committing its local anchor before full owner/docs/device
  regression, not declaring the companion complete.
- Corrected field batch `34466`:58 passed,0failed,1error. Effective-initial12
  and field/import/scheduled/checkpoint46 all passed. New system-only component
  reconnection exposed missing explicit reference-option forwarding through
  replace_component's two completion validations. Approved a reference_units
  keyword with unchanged declared-reference default; returned source stays
  editable and does not store a duplicate reference manifest.

- Model predicate context run `52106` passed all6 sequential checks, including
  nonzero actual constraint rejection and checkpoint continuation; checkerboard
  correctly exposed its missing model storage gather. Root implemented a
  model-owned one-value field with a shared repeated-address relation (no
  per-site state copy), bank-view binding, and model context selection in the
  isolated Core branch. Bounds-checked `17181` is live; independent review and
  central model-read domain validation remain outstanding.
- LocalMath empty-domain strengthened CPU run `51434` passed135/135:72 new
  empty/single/fused/control assertions and63 existing direct-pointwise checks.
  Actual Metal validation is next. Public Potts cell consumer `30339` is now
  running against the coordinated isolated corrected Core/LocalMath pair.
- Potts PR #51 hosted exact-replay and macOS smoke checks passed; package,
  integration, Metal and strict docs are still pending. Models hosted runs
  `34286477703` and `34286627599` remain verified in progress.

- Root model-read baseline `24034` terminated on a real actionable sequential
  proposal: missing `stage_site(ModelStageSite, _ProposalEvaluationContext)`.
  Added that sole-value selection and the corresponding public operation
  context admission in isolated Core, with each engine in its own testset.
  Bounds-checked `52106` now tests this step; checkerboard gathered model
  domains and central declared-domain validation remain required, not waived.
- Independently reviewed LocalMath empty-domain shared-kernel correction in
  `localmath-empty-domains`: no value reads before the source-count guard;
  empty lanes retain existing gate/prefix diagnostics. Requested both a single
  LocalLaw and fused sequence witness before adoption. Owner validation active.
- Field run `54711` intentionally stopped as an obsolete, proven-invalid
  tuple-keyed initial-condition fixture (exit143, no pending-case credit).
  Corrected Dict-based full intended focused batch `34466` is active and
  includes the new system-initialized component-unit reconnection witness.

- Joined full actual Core Metal `33504` passed302/302 with scalar indexing
  disabled and all inventory enabled. Reviewed provider-failure fixture
  isolation committed as `aa94e1cd3d2e0e464eebfb51ddf073b9734a1a4e`;
  production is unchanged from5d425e1, LocalMath isdf9a650. This does not
  include the separate cell-stage or model-global-read work.
- Root added the ordinary `test_model_state_proposal_reads.jl` regression and
  inventory entry in isolated Core model-state-reads: actionable cell/medium
  boundaries, nonzero constraint rejection, preserved Boolean model state,
  and checkpoint continuation. Bounds-checked baseline `24034` is live in
  `corepotts-model-state-reads-baseline.log`; no support is claimed before the
  actual missing dereference/gather implementation and owner/device validation.

- Full strict product-state documentation build `79469` completed exit0,
  including executable examples, doctests, cross-references and HTML rendering.
  Source `9b7dfc29` plus the new product documentation; no blanket warning or
  example suppression. The initial environment dependency omission is resolved.

- Bounds-checked cell run `87795` found a concrete empty-domain failure:
  empty logical storage93/93 and sequential cell execution23/23 passed, then
  checkerboard preparation attempted index1 of a zero-length tracker array in
  `checkerboard_tracker_initialize_1_1` through backend qualification.
  Earlier GC crash causality is not proven, but an unchecked write is now the
  actionable owner investigation. Any LocalMath correction must be isolated
  from the frozen joined fullMetal tuple, with ordinary zero-domain no-write
  CPU/device witnesses; do not remove required no-cell support.
- Root created isolated Core and Potts `codex/model-state-reads` branches
  (`corepotts-model-state-reads` from5d425e1,
  `potts-model-state-reads` from9b7dfc29). Initial investigation confirms
  plain proposal StateExpression evaluates to a handle unless explicitly
  dereferenced. The earlier homogeneous-cell fixture could produce only null
  attempts, so it does not prove sequential Boolean proposal evaluation.
  Required witnesses use actionable cell/medium boundaries and nonzero
  rejection/evaluation evidence. No global-read support claim yet.
- Scheduled product-field/initial-selection batch `54711` is running in the
  isolated field branches; the separately inventoried model-product proposal
  regression remains required and is intentionally not counted in this focused
  run. Public cell authoring first implementation is parsed in its isolated
  branch but consumer execution waits for the concrete empty-domain owner fix.

- Product-field Potts `67396` terminated with34 passes,1 failure,1 error.
  Projection declarations/catalog/dimensions and sequential scheduled consumer
  checks passed, but the imported-owner fixture omitted explicit root unknown
  enrollment and the checkerboard proposal fixture exposed missing model-global
  state reads. Keep a real model-product Boolean proposal witness; do not erase
  it to claim completed field support. Root located the paired gap: Core
  proposal fields/relations assume lattice state, while Potts chooses bound
  operations by process context rather than each state owner's domain.
  Resolving model-global reads therefore needs coherent lowering and gathered
  execution changes, not relaxing a shape guard. Scheduled field and unit-owner
  work continues independently. Core field operation tests now pass31/31,
  alongside the earlier223/223 combined regression snapshot.
- Cell descriptor review found expression handles can be absent from declared
  access.reads. Approved reusing the existing expression-requirements walker
  in central validation, rejecting undeclared condition/value reads on both
  engines before mutation. Move that one walker to its static-expression owner
  rather than maintaining a second inventory implementation.

- Cell batch `99467` terminated with signal11/exit139 during Julia GC/type
  inference at the lifecycle test entry. No aggregate pass credited. Root
  reviewed typed empty allocations, exact-length bank copies, and existing
  BlockView bounds checks without finding an obvious new invalid access; this
  does not establish a compiler bug. CI owner is isolating ordinary files in
  fresh `--check-bounds=yes` processes before changing production behavior.
- Assigned a separate `codex/cell-process-authoring` Potts worktree from
  `9b7dfc29` for the existing `Synchronous(...; domain=cells(kind))` public
  syntax. Completion already models per-cell cardinality; remaining work is
  exact kind/domain admission, bound-cell evaluator lowering, distinct cell
  buffer slots, and ordinary public numerical witnesses through Core's cell
  execution path. Initial cell-only reads are a first implementation witness,
  not a reduction of the required final model/cell composition scope.

- Strict product docs `54699` terminated on missing documentation dependencies
  in the isolated test environment (ModelingToolkit and the executable PDE
  tutorial dependencies), not a new product-state assertion. Added the complete
  declared docs dependency set to that isolated environment and started full
  strict docs `79469`, log `potts-product-state-full-docs.log`.
  Core field regression `91259` passed223/223. Full Metal rerun `33504` uses
  unchanged joined production plus the reviewed provider-failure task-isolation
  test correction; all ordinary Metal inventory remains enabled.

- Published R02 as https://github.com/PraneethMerugu/Potts.jl/pull/51 after
  verifying remote main remains `868a22ff` and the local diff is clean.
  Verified open head `74d70521122fecf7780031daf7d27c9ce39f6b7a`.
  Hosted CI `34287840616` and docs `34287840569` are running; the whole-PR
  change selector passed. No merge performed or hosted pass claimed.
- Joined full Core Metal `50240` terminated after186 successful assertions:
  the compiled-draw continuation encountered a poisoned provider scope left by
  the preceding intentional provider-failure fixture. Review approved matching
  LocalMath's ordinary owner test pattern: create, execute, and settle the
  deliberately failing runtime in one child task. Keep failure assertions and
  the following continuation tests; no provider reset or skipped test. The
  minimal test-only correction and full inventory rerun are pending.

- Added current user/contributor documentation for product initialization,
  recursive defaults, and field-specific reference conversion in
  `potts-product-state`; strict documentation build `54699` is live in
  `potts-product-state-docs.log`. Its source remains `9b7dfc29` with docs-only
  edits. Joined Core full Metal `50240` is live against `5d425e1`/`df9a650`.
  Product-field focused Potts run `67396` and Core regression run `91259`
  are separate isolated snapshots, not evidence for merged production yet.

- Product defaults/reference run `13307` completed successfully: 18/18 on
  Potts `9b7dfc29`, Core `5d425e1`, LocalMath `df9a650`. This exercises
  recursive product-array defaults and dimensional reference conversion, not
  field-expression execution. Independent field review accepted the canonical
  operation and cold literal specialization for focused testing, and identified
  system-level initial-condition unit selection as a required owner fix.
  Models PR and merged-main hosted runs `34286477703`/`34286627599` are both
  verified in progress; neither is credited as a hosted pass.

- User merged Models PR #1; verified merge commit
  `4f259dc1116be7b311a2e8a7e63e4618b47a7a89`. The PR CI was still in progress
  when checked, so the merge is not recorded as a hosted test pass. At the
  user's explicit request, changed PottsModels visibility to public and verified
  it through GitHub. The first immediate fetch hit a transient disabled-repo
  response; API verification showed `disabled=false` and retry succeeded.
  Local `main` and `origin/main` now match the verified merge commit.
- Joined Core full ordinary suite `65016` passed 27,083/27,083 across33 files
  on `5d425e1`/`df9a650`; full joined Metal validation is being prepared.
  Full Potts `14306` remains active. Its declared fixture inventory is missing
  vector_rotation.jl; that known runner-only correction will follow the frozen
  run, without crediting a failing inventory as a complete suite pass.
- Published the Models license-only base `9c36b8f` to remote `main` and the
  reviewed library `58eec61` to `codex/model-library`, then opened
  `https://github.com/PraneethMerugu/PottsModels.jl/pull/1`. Verified the head
  SHA and open state. Hosted `models` CI job is in progress (run34286477703);
  no merge has occurred. The repository remains private.
- Product default/reference run `13307` is active against clean `9b7dfc29`
  after all field-authoring edits moved to isolated `potts-product-fields`.
  Its results must not be inferred from the earlier88-check initialization run.
- Joined focused run `1486` passed 58/58 on `a80ecd1b`/`5d425e1`/`df9a650`.
  Full ordinary Potts owner run `14306` is now active with no selectors,
  alongside joined Core owner `65016`; their sources remain frozen.
- Product initialization `11217` is terminal exit 0, 88/88 on loaded
  implementation `792576ca` (5 declaration,21 product initialization/restore,
  32 typed state,30 dimensional arrays). This does not cover the subsequent
  recursive default/reference-anchor corrections or field-expression work.
- Root applied recursive fixed-array defaults and recursive named-field
  reference-anchor discovery in their existing owners, plus the reviewed
  indexed-read projection. New default/reference tests remain to run.
  Field implementation is moving to a separate Potts worktree to keep owner
  validation independent of further symbolic-surface edits.
- Indexed-array read projection is saved as `a80ecd1b` after root review:
  completion retains the indexed symbolic dependency, and storage lowering
  resolves its exact declared array owner to that owner's existing handle.
  Original focused batch `1486` is active; no runtime read guard was weakened.
- Root added ordinary nested-product reference tests covering fieldwise
  inferred scales, compatible overrides, ambiguity, explicit scales, and
  incompatible/missing units. They are not part of active `11217` and are
  unrun pending the reviewed reference-anchor correction. Product production
  source remains frozen for the current initialization test.
- Field-access research found that a raw generic `getproperty` symbolic term
  loses its result type during substitution. Registering a global NamedTuple
  wrapper would violate ownership. The candidate ergonomic direction uses
  existing Potts declaration objects and one package-owned field operation
  whose type/shape rules survive namespacing, with no additional state owner or
  symbolic registry. This remains a prototype investigation, not a shipped API.
- Actual joined vector witness `86124` is terminal exit 0: 16/16 across
  checkerboard CPU and actual Metal, with scalar indexing disabled. This
  validates the shared four-step model/site rotation, not mixed compound
  expressions or a performance claim.
- Seeded focused `5101` exposed a real indexed-array dependency omission:
  rotation16 and sequential mixed5 passed, but checkerboard mixed construction
  rejected an uninventoried vector-state handle. The Potts owner is tracing and
  fixing read identity resolution; Core's declared-read check remains intact.
- Product declaration run `80871` passed5/5. The isolated product candidate now
  uses declaration-directed recursive initial conversion for named fields and
  fixed arrays, preserving Bool/Int and selected floating precision through
  the existing layout/runtime owners. Broader initial/checkpoint/unit regression
  run `11217` is active on frozen source; no product execution pass yet.
  Review identified missing recursive inferred-unit anchors and default arrays
  of products; those will be corrected after the current run terminates.
- Cell-stage validation now resolves handles through canonical layout schema
  domains. The first run stopped before behavior; corrected `26180` tests the
  cell cases plus existing model194 after replacing a rejected direct context
  constructor with the existing inline construction pattern. Typed admission
  is unchanged, and the candidate is not yet considered validated.
- Joined focused `9879` terminated with 16/16 CPU rotation assertions and
  four sequential mixed scalar/vector assertions before an omitted required
  seed in a negative test fixture. Test-only correction `e443a771` supplies
  both missing seeds; original focused batch is rerunning as `5101` on the
  same production source. Metal `86124` uses the unchanged shared rotation
  fixture and remains active. No skipped checkerboard mixed case is counted.
- Root opened isolated `codex/product-state-authoring` at the joined base.
  Its first uncommitted change replaces Num/Arr-only constructor dispatch with
  the existing symbolic classification trait, and adds ordinary single-owner
  named-product declaration tests. Focused `80871` is active after recovering
  Julia's denied compilation-cache lock; named-product initialization and
  field-expression execution remain unimplemented, not claimed by this test.
- Root's first cell-stage review found domain validation relying only on shape:
  same-sized non-cell state could be reinterpreted as cell storage. The owner
  will use existing canonical state-layout schema domains and add wrong-domain
  regressions after its frozen initial run terminates. No second domain registry
  or descriptor-state representation is authorized.
- Initializer run `8862` confirmed terminal exit 0: 32/32 in 4m43.4s on
  structured Potts `e5bc8259`, including both model/site nested-leaf rejection
  regressions. Independent review has no remaining material finding in this
  slice. Joined CPU execution and actual Metal rotation remain separate work.
- Joined Potts is clean at `8bddd339` on `codex/authoring-workflow` after
  root review of manual conflicts. Per-effect shape validation, compound
  Assign/Create selection, named RNG placement keys, and both test inventories
  are preserved. The new ordinary test exchanges a scalar with a vector's
  first component over two boundaries and rejects an invalid second effect.
  Focused run `9879` is active on Core `5d425e1` and LocalMath `df9a650`;
  actual Metal rotation will use the same frozen tuple.
- Read-only product-authoring probes completed successfully: Symbolics accepts
  a variable typed as `NamedTuple{(:amount, :enabled), Tuple{Float64, Bool}}`
  and classifies it as scalar symbolic while preserving its declared type.
  Ordinary dot access rejects both fields. Public `Symbolics.term(getproperty,
  product, field; type=...)` preserves the requested field type, but requires
  explicit author work. The next product-authoring implementation must provide
  ergonomic field access through an owned public interface and the existing
  symbolic graph, not assume raw named-product variables already work or
  create unrelated scalar state owners. These probes are not product execution
  or continuation support.
- The isolated Core cell-stage design is approved for implementation: runtime
  kind/generation metadata owns eligible identities, a true one-dimensional
  cell domain uses the existing execution/publication path, and extra allocated
  state slots use a prefix view rather than creating scientific identities.
  Cell-bound reads must not masquerade as site selectors. Ordinary tests will
  defend all-RHS-before-publication, inactive evaluation avoidance, capacity
  validation, and the actual existing lifecycle boundary.
- Structured Potts implementation is saved as `e5bc8259` on
  `codex/structured-state-authoring` after root/independent review. The review
  reproduced a nested-vector initializer accepted under a scalar-element
  symbolic vector declaration; the existing initialization owner now rejects
  that mismatch and owning model/site regressions are included. Run `8862`
  is validating the frozen initializer suite. The isolated Potts workflow is
  integrating this anchor with compound/RNG and will add a mixed scalar/vector
  compound witness to defend per-effect shape checking. No joined pass yet.
- LocalMath `df9a650` separate scientific CPU suite `15111` also completed
  successfully (29/29); all scheduled owning validation is now terminal.
  CI is preparing an isolated Core branch for genuine cell-domain stages,
  with design/owner review before edits; tested joined Core stays frozen.
- Root compound retry `88457` is now terminal exit 0: 47/47 assertions in
  12m47.8s on Potts `e5763ed5`, Core `d1db5e3`, and LocalMath `df9a650`.
  This exercises the authored CPU swaps, late-failure rollback, and mixed
  assignment/relationship transactions after both owning fixes. The local
  compound PR body records this bounded pass, not a full G04 completion.
- Independent structured-state review is checking a possible nested-array
  initializer admission inconsistent with a scalar-element symbolic shape;
  integration waits for that finding to be resolved, not for changes to tested
  Core or LocalMath sources.
- The user's rapid-development preference authorizes the direct versioned RNG
  cutover, including changed seeded trajectories and rejection of exact old-RNG
  checkpoint continuation. One production RNG path remains the requirement;
  correctness and performance validation are not waived.
- LocalMath `df9a650` passed the complete ordinary owner suite (1552/1552),
  strict documentation build, and complete Metal runner (`20605`, 273/273,
  including its host product fixtures). Actual Metal was functional with scalar
  indexing disabled. The separate ordinary scientific suite `15111` is active.
- Core compound `d1db5e3` with LocalMath `df9a650` passed the complete declared
  Metal inventory (168/168). This is not evidence for the later joined Core.
- Joined Core `5d425e1` with LocalMath `df9a650` has started its full ordinary
  owner suite (`65016`); sources are frozen and no full pass is claimed yet.
- Isolated Potts `codex/authoring-workflow` is clean at `c0f1fa54`, joining
  compound `e5763ed5` and RNG `32274682`. Structured-state integration and
  joined behavioral validation remain pending.
- Fixed-vector analysis passed 25/25, including literal bounds, dynamic-index
  and unit rejection. Actual rotation has 12 CPU assertions so far; the
  checkerboard site case still requires the existing compound footprint fix
  through integration. Actual Metal rotation remains untested.
- Root compound retry `88457` remains active on Core `d1db5e3` and LocalMath
  `df9a650`; no result is inferred from the owning-package passes.

The isolated Core join is now clean at `5d425e1` on
`codex/authoring-execution`: compound `d1db5e3`, reviewed RNG integration
`4562ed5` (from `334cbe6`), and fixed-vector callable integration `5d425e1`
(from `809334a`). Parent ordinary/Metal inventory entries are retained. This
anchor has not yet run joined package tests; a dedicated environment and full
behavioral validation are the next required integration step.

LocalMath gate correction `df9a650` is committed clean after root review, with
69 CPU checks (26 gate +43 existing fold) and26 actual Metal checks passing.
Root's original compound retry `88457` is active on Core `d1db5e3` plus that
LocalMath anchor. Core full Metal `59772` is active on the same pair; neither is
claimed passed yet.

Joined fixed-vector run `95399` terminated with reference-inference6 passes
and6 errors. Two fixture mistakes were corrected by their owner; actual rotation
exposed lowering's unhandled already-proven `fixed_index` totality. Root now
hands that literal in-bounds proof through the same static skip as proven
integer powers, without adding another predicate or bypassing unproved inputs.
Corrected batch `57136` has loaded the frozen source and remains active.

Core fixed-vector callable slice is saved as clean `809334a`, with10 focused
numerical/inference checks and root review; actual stage/device validation is
still pending. Authoring_gaps is integrating compound, RNG and callable anchors
in an isolated `codex/authoring-execution` worktree. Root reviewed the RNG
conflict resolutions (V3 full trajectory keys plus gathered target selector)
without material findings. This join does not mutate active validation trees
and still requires ordinary joined owner/integration/device tests.

Root completed the array reference-inference cutover: completion's existing
anchor discovery now visits fixed-array quantity components, and lowering
reuses that owner instead of retaining its duplicate discovery loop. Existing
finite/nonzero and ambiguity rules are preserved; no arbitrary component scale
is selected. New ordinary `test_state_reference_inference.jl` covers consistent
inference, explicit resolution, ambiguity, zero scale and mixed declarations.
It is included with vector analysis/rotation in active joined run `95399`.

RNG full owner `44568` is terminal: 26,712 passes, two failures, one error;
not a full pass. All three exact failures belong to the pre-compound snapshot:
private RefValue, missing structured-test inventory, and NamedTuple zero in
checkerboard storage. No exemptions were added. The new local RNG PR body
records this result and the required joined validation, rather than claiming
the newer fixes already prove a successful integration.

Root independently reviewed the LocalMath closed-gate fix and its shared
field/parameter gate fixture without material findings. The fixture distinguishes
retained destination from private initializer, exercises repeated gate toggles,
and retains live duplicate-identity rejection. Focused CPU/Metal validation and
the downstream compound retry remain required before its completion claim.

Dimensional run `13312` is now terminal exit 0: 55/55 checks passed across
dimensional fixed-array reference scaling, compatible/incompatible overrides,
execution and checkpoint preservation, the tensor value witness, and existing
scalar unit/parameter tests. This validates the loaded unit-conversion slice,
not the subsequently edited fixed-vector expression analysis or the pending
LocalMath closed-gate fix.

Clean local implementation anchors are now Core compound `d1db5e3`, Potts RNG
`32274682`, and LocalMath recursive admission `121a385`. Potts's actual authored
CPU/Metal conjunction passed 11/11 with Core RNG `334cbe6` and LocalMath
`121a385`; its local body and the companion body accurately record that tuple.
These are implementation slices within G04, not additional completed base PRs.

The remaining duplicate-order failure is now traced to LocalMath's ordered-fold
evaluation path checking prefix/mask/subset but not its explicit closed gate
before order validation. Later recurrence checks the gate too late, exposing
zero-initialized inactive event identities after the invalid payload. CI is
authorized to add the owning closed-gate regression and fix the existing fold
evaluation/finalization path; normal Core request identities and duplicate
validation must remain unchanged. Root will review before its follow-up commit.

Fixed-vector host analysis work is proceeding on the structured Potts branch;
the independent Core callable branch starts from `d1db5e3`. Root added a
logical RHS/target shape check in existing assignment lowering, with an ordinary
shape-mismatch witness. Dimensional run `13312` is still active on its earlier
loaded snapshot; no newer combined structured-expression pass is implied.

Root type/expression run `1306` terminated with 50 passes and one error:
20 vector retention/execution/checkpoint plus 30 declared Int32/Bool, tensor,
supplied-value/default/invalid-value checks passed. Rotation stopped at the
obsolete scalar-only ModelState admission check. That check is now removed;
readability is implementing aggregate normalization, fixed indexing and vector
construction in the existing host operation/type/shape/unit analysis owners.
No vector equation support is claimed until the actual rotation passes.
Root dimensional run `13312` is active with the unit conversion slice; it loaded
before those subsequent host-analysis edits and remains separate evidence.

Root compound `88049` terminated with 38 passes and two errors: 8 synchronous
swaps, 8 accepted-copy swaps, 2 writer/domain diagnostics, 10 partial failure
checks and 10 mixed-effect checks. The site parameter-view shape issue is now
corrected by Core, whose expanded focused suite passed 79 checks (68 scientific
conversion/rollback plus 11 view shape/indexing/shared storage/adaptation).
Root reviewed the N-D view correction without material findings and authorized
a local implementation anchor, not review-ready status. The remaining mixed
test error is duplicate ordering identity in the boundary relationship fold
after invalid payload, being traced to gate/initialization semantics rather
than suppressed. The prior full owner continues only as its accurately stated
loaded/test snapshot; no process was terminated on a stale status assumption.

LocalMath's recursive storage-admission world-age correction is committed as
`121a385` on clean `codex/product-values`, following independent root review.
Its ordinary nested callable publication/rejection and product owner tests
passed 26/26. The companion PR body now explicitly separates broad `87de468`
validation from this focused follow-up. Actual downstream authored CPU/Metal
retry remains pending. Core's existing broadcast parameter view is also being
cut over directly to N-dimensional shape by its owner, with explicit shapes
from the four existing consumers; no duplicate wrapper or relaxed Field
validation is authorized.

Structured unit conversion is now implemented in the uncommitted candidate:
`_state_initial_reference` derives one compatible reference from fixed-array
leaves using the existing reference-unit owner, and the single numeric
conversion owner enforces dimensional/dimensionless leaf compatibility for both
declarations and supplied values. `test_dimensional_state_values.jl` is in the
ordinary inventory (reference scaling, centimetre/metre override, execution,
checkpoint, incompatible units). This new unit slice is not yet validated;
`1306` had loaded the preceding typed-state snapshot before this edit.

Two concrete integration findings are being fixed by their owners. The authored
RNG witness exposed a LocalMath generated-function world-age problem in
recursive storage type admission; authoring_gaps is correcting that sole owner
and adding a public owner witness before commit. Root compound `88049` remains
active but reports a checkerboard site parameter-view binding failure: field
Space shape `(2,2)` versus parameter-view shape `(4,)`. CI/Core owner is
investigating the canonical binding shape; this is not a fixture error or a
reason to weaken LocalMath validation. Current full-owner runs remain explicitly
loaded-snapshot evidence and are not restarted merely for these new findings.

Root structured packing run `76231` is terminal exit 0: fixed-vector
initialization/execution/checkpoint preservation passed 20 assertions; existing
initialization/remake and multiple-medium regression passed 36 + 3. This is
the loaded snapshot before the next declared-type correction. Installed
Symbolics probe `88918` directly confirmed Int32/Bool symbolic types and whole
array/vector-expression representation. Potts completion now retains those
declared types; initial and supplied-value conversion preserve integer/Boolean
meaning instead of casting to the selected floating type. New frozen run
`1306` covers vector retention, typed values, tensor initialization, and actual
vector rotation authoring. The rotation test is expected to expose remaining
expression/coverage gaps; no broad structured-authoring completion is claimed.

Independent review of structured storage found canonical-domain packing sound
but identified missing fixed-array units: reference extraction and runtime
unit validation currently inspect only the outer value. Homogeneous dimensional
vectors/tensors require shared leaf-aware reference extraction and ordinary
override tests; mixed-dimension named products require their own per-leaf unit
semantics. These remain required implementation work, not deferred features.

Core compound owner reports 294 focused assertions passed (194 structured and
overflow, 42 relationships, 58 checkerboard oracles), with its mixed loaded
snapshot accurately recorded. Corrected site-conversion 34 and latest strict
docs separately passed. Full owner run `2970` is active on the fully frozen
corrected snapshot; root compound `88049` is also active. No full-owner pass or
review-ready G04 PR is inferred from these focused results.

Current root validation handles: structured packing plus scalar initialization
regression `76231` remains active; corrected compound rollback run `88049`
started against the Core owner's site RHS conversion correction. Both are
uncommitted candidates, not completed PRs. The structured branch additionally
inventories `test_state_initial_value_types.jl` for typed Boolean/integer state,
matrix values, supplied logical shape, zero defaults, precision selection,
nonfinite rejection, and checkpoint preservation. That expanded baseline has
not run; current scalar symbolic-type inference still erases Boolean/integer
meaning and needs an evidence-backed correction. Nearest authoring and
architecture docs now explain logical shape versus outer storage shape.

Core RNG commit `334cbe6` now has 116 compiled CPU and 116 actual Metal checks
for Bernoulli constraints, Uniform drives, qualified key literals, settled
snapshot/counter parity, and checkpoint continuation. Full-owner validation is
still running and has reported inherited inventory/private-Ref failures to be
resolved through the pending compound integration, not exemptions. Potts's
authored RNG GPU witness is separately active; no scheduled once-per-cell draw
support follows from these proposal-draw tests.

Structured candidate run `55113` is now terminal (zero passes, one error):
conversion and canonical SVector element-type selection advanced to allocation,
where model initial-value packing incorrectly treated the vector's components
as outer storage entries. Packing now branches on the canonical model/medium
storage domain before generic array handling. The corrected run includes the
existing scalar initialization/remake regression as well as the structured
execution/checkpoint witness; no successful result yet.

Latest G04 work: compound public-authoring run `24009` terminated with 21
passes and two fixture errors. Synchronous model/site swaps (8), accepted-copy
site swaps (8), duplicate-writer/common-domain diagnostics (2), and sequential
Assign/Create success (3) passed. The failing-RHS fixtures incorrectly expected
a solver Failure from the sequential engine, whose existing contract throws
DomainError. They now preserve that contract and inspect fresh settled state,
not cached integrator state, for rollback. Their corrected rerun is pending the
Core owner's site-conversion snapshot; no complete compound pass is claimed.

Structured public-authoring baseline `4765` terminated with zero passes and one
error: `_compiled_state_initial` rejects SVector through scalar `_numeric_value`.
The isolated `codex/structured-state-authoring` candidate now preserves static
array logical shape during initial conversion and derives the Core element type
from that conversion; StaticArrays is a direct dependency. Run `55113` is active
against this candidate. It is uncommitted and not validated; model-value packing,
supplied-value shape tests, documentation, and full regression remain necessary.

Core's RNG owner committed the direct addressed-RNG cutover locally as
`334cbe6`. Actual compiled Bernoulli/Uniform CPU controls passed 116 assertions
after cold literal-family specialization. Its latest full CPU and actual Metal
compiled-consumer runs remain active; prior raw-address device tests alone do
not establish authored draw support. Existing lifecycle matrix fixtures in Potts
are being cut over to explicit unique DrawKey labels under the established
component-local uniqueness rule, without weakening conservation/replay tests.

Core selector/public-parameter fixes are frozen for root compound run `24009`
(`potts-compound-effects-bound-target.log`) and structured baseline run `4765`
(`potts-structured-state-baseline.log`). Both scripts now flush an explicit
package-loaded marker. Structured environment resolution `5413` completed; no
structured production edits yet. Installed Symbolics 7.39 probe `19476` confirmed
`@variables position[1:2]` is `Symbolics.Arr{Num,1}`, shape `(2,)`, symbolic type
`Vector{Real}`. Whole-array identity must be preserved rather than masquerading
as scalar Num state. The official array documentation confirms this distinction.

Root approved a focused site Float64-to-Float32 overflow witness/correction in
the same Core target-conversion owner after frozen runs; current site evaluation
appears to validate before target conversion, unlike sequential execution.
This is not an assertion that the untested case already works or an expansion
to unsupported Float16 storage.

Public compound run `49774` is terminal: 13 passes, one test failure and three
errors. All model/site swaps passed on both CPU algorithms (eight assertions).
Accepted-copy sequential swap passed four assertions, but checkerboard execution
hit a missing `stage_site(ProposalTargetStageSite(), _GatheredProposalContext)`
method; the subsequent poisoned provider scope prevented the two later transaction
testsets from running. Those are not independent scientific failures or passes.
Core owner is fixing the existing selector dispatch. The remaining test failure
expected lowering coverage during `complete`; it now correctly asks `mtkcompile`
to reject mixed iteration domains. The footprint correction received independent
review with no material defect found; implicit anchors can conservatively add
reads for explicit site operations, a possible admission/performance limitation.

Root created isolated `.worktrees/potts-structured-state`, branch
`codex/structured-state-authoring`, from `6f1cbc74`. It currently adds only an
ordinary registered vector-state execution/checkpoint witness, not implemented
structured authoring. Source inspection identified scalar-only conversion in
the existing state layout, compiled initial-value manifest and runtime initializer.
These owners must be corrected coherently; no structured public support claim is
made from the new test or branch.

Root's consumer review confirmed the RNG checkpoint rejection witness recomputes
a valid checksum before asserting the explicit RNG-contract mismatch. The actual
Core RNG focused runtime/lifecycle/geometry batch completed with exit zero
(`corepotts-addressed-rng-runtime.log`, 8,947 assertions reported by its owner).
The ordinary Metal runner also finished with 108/108 and exit zero, including
83 full-checkerboard assertions and 18 raw address/arithmetic assertions. Review
identified that this did not exercise a compiled authored draw carrying the new
operation key. The RNG owner is adding that ordinary shared CPU/Metal witness,
including non-vacuous acceptance and constraint-rejection outcomes. No compiled
GPU authored-draw guarantee is claimed until it passes.

Potts RNG authoring's 14 identity/scoping/large-declaration/Float32/Float64 checks
passed before initialization exposed the last-slot swap-delete bug. Its owner is
correcting the actual initializer and adding a fully occupied layout witness;
this is separate from the still-active compound transaction run `49774`.

Public run `26448` is terminal exit one: model swaps passed on both CPU engines
(four assertions), site swap passed sequentially (two assertions), and site
checkerboard preparation rejected an empty read footprint. The Potts analyzed
leaf-footprint owner now marks direct SiteState leaves with the actual iteration
site/proposal-target anchor for these process kinds. This keeps inspection and
descriptor lowering derived from the same analyzed footprint, rather than adding
a descriptor-only fallback. The ordinary test file now has one enclosing testset
so later transaction cases still report when a sibling case fails. New validation
awaits the Core owner's source-ready signal after its public-binding cleanup.

Core run `51621` ended with 205 passes and five errors confined to unsupported
Float16 checkerboard storage admission, before evaluation. Float32/SVector/
NamedTuple and zero-dimensional model/checkpoint controls passed. The replacement
overflow witness will use admitted Float64-to-Float32 CPU conversion; no Metal
overflow guarantee is claimed from this run. The new LocalMath Field-space access
is being removed in favor of an explicitly passed Core-owned model space.

Independent Potts compound source review found no material defect in indexed
roots, common-domain validation, individual writer detection or retained RHS
reads. It identified missing mixed assignment/relationship and late-failure
witnesses, now added to `test_compound_effects.jl` with non-vacuity assertions.
Expanded public transaction run `26448` is active against the frozen Core
singleton-binding and post-conversion finiteness correction, log
`potts-compound-effects-transactions.log`. No expanded-suite pass is claimed.

R02 documentation-only commit `74d70521` synchronizes its copied dependency map
with the planning workspace's counted LocalMath companion. The worktree is clean;
full-owner and strict-docs results apply to its unchanged executable/manual source.
Its local PR description distinguishes the tested parent and this follow-up.

Root independently reviewed the RNG primitive/address/key owners and found no
material defect in framing, bit partition, bounded fixed-trajectory injection,
uniform mapping or retry separation. Remaining consumer/checkpoint integration
validation is still the RNG owner's active work; this is not complete R08 review.

Public compound rerun `32078` is terminal exit one: sequential swap 2/2 passed,
checkerboard now correctly inventories both RHS handles but rejects the public
Potts zero-dimensional ModelState storage against Core's one-dimensional singleton
model space. This is a distinct actual integration gap, not a missing-handle
regression. Core owner has the concrete stack and will resolve the model-domain
binding contract alongside the approved post-conversion finiteness correction;
no root test is holding the Core source snapshot. The next root test file now
includes model/site swaps, non-vacuous accepted-copy swaps, and duplicate-writer
and mixed-domain failures. None of these expanded cases has yet passed as a set.

R02 owner session `74362` completed with exit zero: 1,905/1,905 assertions,
including the ordinary test inventory and package quality checks. The terminal
log is `potts-model-library-full.log`; its local PR body now records the pass.
This closes the pending owner run, not hosted CI or remote publication.

The first public compound swap run `5630` finished with two sequential passes
and a checkerboard preparation error: a RHS state was absent from declared reads
because `_statement_reads` removed every written target. The correction retains
actual effect RHS reads, including self/cross-target reads, at the completion
owner. Latest-source run `32078` is active in
`potts-compound-effects-read-correction.log`. Accepted-copy varargs/indexed
assignment and relationship-create lowering are now implemented in the same
worktree, with a non-vacuous accepted-copy swap test added for the next run.
Core shared structured CPU run `96106` passed 144/144; a target-conversion
overflow witness and corresponding validation remain pending before handoff.

Root's public compound-effect slice is now in
`.worktrees/potts-compound-effects` on `codex/compound-effects`, based on
`6f1cbc74`. Synchronous varargs lower through indexed expression roots and the
existing descriptors with distinct scratch slots. Coverage checks one iteration
domain, and qualified writer validation examines individual effects rather than
the deduplicated write summary, so duplicate targets within one process are not
hidden. Public swap and writer/domain rejection tests are registered in the
ordinary owner suite; nearest authoring and architecture documentation is updated.
Runic and diff checks pass. Focused validation session `5630`, log
`potts-compound-effects-focused.log`, is running (PID 32880 verified active);
no behavioral pass is claimed. Later writer edits require a latest-source rerun.
Accepted-copy/relationship compound authoring, cell-scoped execution, structured
public authoring, and full R08/R09 validation remain unfinished.

Core conditional model publication now uses the existing partial-coverage,
preserve-empty law. Its scalar reproducer passed 12/12 and strict docs passed;
the owning agent is rerunning the shared structured CPU and actual-Metal tests
before full owner validation. R02 owner session `74362` remains live and has
produced additional completed test-file rows; no full-suite pass is claimed.

Finish and independently review R01–R07, including all applicable owner,
integration and hardware checks. Then follow G04 onward and all twelve breadth groups in the
delivery map, including necessary companion PRs. G04 has started as described
above; groups after G04 have not started.

Preserve the exact-replay environment's declared dependency profile during
ordinary CI changes. Models preserves the existing bounded OpenVT mechanism,
with explicit limits: scalar span calibration and saved-state classification
are not a growing contact-inhibited CPM tissue law.
