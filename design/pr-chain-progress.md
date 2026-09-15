# PR-chain progress

Status: current implementation snapshot. Updated 2026-09-15.

The [consolidated dependency map](consolidated-pr-dependency-map.md) owns the
identified work and dependencies: **65 repository PRs = R01–R54 plus eleven
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
  MakiePotts. Core R08 is also merged as CorePotts PR32 (`7b46e4eb`); its Potts
  consumer R09 remains open.
- Nine demonstrated companions are merged: the PottsModels CI correction and
  LocalMath immutable products, execution prerequisites, fixed-value effect
  analysis, backend-owned transfer, identity-seeded reduction control, and
  ordered-fold step validation, plus exact keyed reduction and atomic keyed
  rebuild publication.
- The seventh identified companion is LocalMath PR18, merged as `9d3e1a24`.
  The eighth is LocalMath PR19, merged as `7082ed84`; both passed their complete
  hosted package, scientific, documentation, macOS, and real-Metal checks.
- The ninth is LocalMath PR20, merged as `cca004b9`; its complete hosted suite
  also passed.
- The complete delivery is not close to finished: G04/G05 and all later
  main-spine/breadth groups remain open unless listed above.

## Published active stack

| Plan item | Repository PR | Selected revision | Base | State |
| --- | --- | --- | --- | --- |
| R08 Core typed composition/lifecycle | [CorePotts PR32](https://github.com/PraneethMerugu/CorePotts.jl/pull/32) | `7b46e4eb` | main | merged |
| R09 Potts composition | [Potts PR53](https://github.com/PraneethMerugu/Potts.jl/pull/53) | `4fc9277f` | main | draft; incomplete |
| R10 Core maintained quantities | [CorePotts PR33](https://github.com/PraneethMerugu/CorePotts.jl/pull/33) | `a4fb6c88` | main | draft; G05 science gaps remain |
| R11 Potts maintained-quantity authoring | [Potts PR54](https://github.com/PraneethMerugu/Potts.jl/pull/54) | `4cec5535` | Potts PR53 | draft; depends on corrected R10 |
| R49 Core operational runtime boundary | [CorePotts PR34](https://github.com/PraneethMerugu/CorePotts.jl/pull/34) | `b4e5bda5` | CorePotts PR33 | draft; hosted suite green, blocked by R10 completion |
| R50 Potts resolved operational lowering | [Potts PR55](https://github.com/PraneethMerugu/Potts.jl/pull/55) | `6c5344d6` | Potts PR54 | draft/CLEAN; exact Symbolics 7.37 CPU/Metal correction and complete hosted suite green, blocked by R11 and downstream canary |
| C08 LocalMath exact keyed reduction | [LocalMath PR19](https://github.com/PraneethMerugu/LocalMath.jl/pull/19) | `7082ed84` | main after LocalMath PR18 | merged; exact-tip hosted package/scientific/docs/macOS/real-Metal green |
| C09 LocalMath atomic keyed rebuild publication | [LocalMath PR20](https://github.com/PraneethMerugu/LocalMath.jl/pull/20) | `cca004b9` | LocalMath main after PR19 | merged; exact-tip hosted package/scientific/docs/macOS/real-Metal green |
| C10 Core Cartesian domain ownership | — | — | Core R08 | identified; required before complete R10/R11 domain-query claims |
| C11 Potts Cartesian domain authoring | — | — | C10 and Potts R09 | identified; required before R11 can admit wall/exterior/obstacle filters |
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
demonstrated pair raises the identified count to 65.

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
| G04 structural baseline | Core R08 is merged; Potts R09 remains draft. | Record the complete R08/R09 structural lifecycle/history/compound-effect tuple and unchanged control before G05 qualification. |
| G05 relation and maintenance delta | Active Core/Potts candidates have focused evidence, but periodic geometry/connectivity and maintained-query science remain incomplete. | R10/R11 must measure exact contribution/update/rebuild/publication and geometry entrypoints plus unchanged controls on the joined C08/C09 tuple. |
| R49 canonical Core boundary | The draft candidate has hosted evidence, but it is stacked on incomplete R10. | Re-run root-`Any`, boundary-size, one/two/four/eight/sixteen-entry identity, value/name remake, AllocCheck, warmed allocation and actual-device probes on corrected R10. |
| R50 public lowering identity | The draft candidate has pinned-array CPU/Metal evidence; its parent R11 and downstream interface canary remain open. | Prove package-declared and interactive equivalence, author-name erasure, source diagnostics and the complete public workflow on the exact joined stack. |
| Retrospective compiler-debt sweep | PR19 supplied its own feature-local comparison; C09 has a policy-specialization probe; no completed cross-merge sweep is recorded for R06, R07 or the LocalMath companion sequence. | Run the bounded before/current comparisons before R49/R50 freeze; correct a measured defect in its open owner or count a targeted companion only if required. |
| G06/G07 interface canaries | Required by R49/R50; R50 is still recorded as blocked by its downstream canary. | Preserve G05's explicit rejection while proving the normalized boundary distinguishes a periodic/shared-owner/relation conflict from shared read-only and owner-proven commutative/associative compatibility; also exercise one held/native-snapshot case before interface freeze. |
| Canonical public benchmark runner | The design and corpus are specified; G09 is not implemented. | R49/R50 leave the focused reproducible runner; R20 later owns longitudinal fresh/warm, specialization, allocation, transfer and cache records. |

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
65. R10 implementation demonstrated C09, one narrowly owned reusable LocalMath
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
   graph. R52 additionally depends on G09's benchmark/observation corpus.

## Merge policy

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
65 identified PRs and any later demonstrated owner companions.
