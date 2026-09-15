# PR-chain progress

Status: current implementation snapshot. Updated 2026-09-14.

The [consolidated dependency map](consolidated-pr-dependency-map.md) owns the
identified work and dependencies: **62 repository PRs = R01–R54 plus eight
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
- Eight demonstrated companions are merged: the PottsModels CI correction and
  LocalMath immutable products, execution prerequisites, fixed-value effect
  analysis, backend-owned transfer, identity-seeded reduction control, and
  ordered-fold step validation, plus exact keyed reduction.
- The seventh LocalMath companion is PR18, merged as `9d3e1a24`. The eighth is
  PR19, merged as `7082ed84`; both passed their complete hosted package,
  scientific, documentation, macOS, and real-Metal checks.
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
| R50 Potts resolved operational lowering | [Potts PR55](https://github.com/PraneethMerugu/Potts.jl/pull/55) | `0994c492` | Potts PR54 | draft; current-tip hosted checks active, blocked by R11 and downstream canary |
| C08 LocalMath exact keyed reduction | [LocalMath PR19](https://github.com/PraneethMerugu/LocalMath.jl/pull/19) | `7082ed84` | main after LocalMath PR18 | merged; exact-tip hosted package/scientific/docs/macOS/real-Metal green |
| Canonical plan/API publication | [Potts PR56](https://github.com/PraneethMerugu/Potts.jl/pull/56) | this change | main | draft; independent re-review clean, hosted checks pending |

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

### R50 pinned array imports

Hosted Metal isolated a Symbolics 7.37 failure for whole-array component imports
and indexed/reordered leaves. Potts commit `0994c492` preserves the validated
authored array-symbolic identity, installs whole plus scalar substitution rules
at the sole import-resolution owner, and rejects overlapping whole/scalar aliases
in either binding order.

- exact pinned focused CPU contract: 6/6;
- shared CPU plus real-Metal witness with scalar indexing disabled: 28/28;
- complete focused component-replacement owner suite: 139/139; and
- committed Metal Project/Manifest unchanged.

Current-tip PR55 hosted validation is the remaining authority.

## Compiler qualification status

The [compiler amendment](compiler-contract-chain-amendment.md) owns the contract;
this table records only the current evidence state. A green component does not
qualify a later joined package tuple.

| Qualification item | Current evidence | Remaining work and owner |
| --- | --- | --- |
| C08 exact keyed reduction | Complete at merged LocalMath PR19: feature-local Kaimon typed probes, narrow phase payloads, focused allocation comparison, CPU and real-Metal behavior, full package and docs. | Include the merged revision in the bounded LocalMath retrospective comparison; no C09. |
| G04 structural baseline | Core R08 is merged; Potts R09 remains draft. | Record the complete R08/R09 structural lifecycle/history/compound-effect tuple and unchanged control before G05 qualification. |
| G05 relation and maintenance delta | Active Core/Potts candidates have focused evidence, but periodic geometry/connectivity and maintained-query science remain incomplete. | R10/R11 must measure exact contribution/update/rebuild/publication and geometry entrypoints plus unchanged controls on the joined C08 tuple. |
| R49 canonical Core boundary | The draft candidate has hosted evidence, but it is stacked on incomplete R10. | Re-run root-`Any`, boundary-size, one/two/four/eight/sixteen-entry identity, value/name remake, AllocCheck, warmed allocation and actual-device probes on corrected R10. |
| R50 public lowering identity | The draft candidate has pinned-array CPU/Metal evidence; its parent R11 and downstream interface canary remain open. | Prove package-declared and interactive equivalence, author-name erasure, source diagnostics and the complete public workflow on the exact joined stack. |
| Retrospective compiler-debt sweep | PR19 supplied its own feature-local comparison; no completed cross-merge sweep is recorded for R06, R07 or the LocalMath PR12–PR19 sequence. | Run the bounded before/current comparisons before R49/R50 freeze; correct a measured defect in its open owner or count a targeted companion only if required. |
| G06/G07 interface canaries | Required by R49/R50; R50 is still recorded as blocked by its downstream canary. | Exercise one transition/relational-dependency case and one held/native-snapshot case against the actual candidate tuple before interface freeze. |
| Canonical public benchmark runner | The design and corpus are specified; G09 is not implemented. | R49/R50 leave the focused reproducible runner; R20 later owns longitudinal fresh/warm, specialization, allocation, transfer and cache records. |

## Immediate dependency order

1. Correct, re-review, and qualify the periodic geometry/connectivity candidate;
   consume merged LocalMath PR19 as the exact keyed-reduction prerequisite.
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
62 identified PRs and any later demonstrated owner companions.
