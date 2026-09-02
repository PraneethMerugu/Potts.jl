# LW-4A Standalone Extraction Evidence

Date: 2026-08-10

Status: exact amended candidate qualified and cleared by LW-R2A; LW-4B not started

Authority:

- [LW-4A implementation matrix](lw4a-extraction-implementation-matrix.md)
- [Post-LW-R1 roadmap](../../spec/localworksets-post-lwr1-roadmap.md)
- [LW-R1 review](lwr1-localworksets-review.md)
- [LW-3 parity protocol](lw3-localworksets-parity.md)

## Result

The exact LW-R1 substrate is now a standalone experimental `LocalWorksets.jl` package. CorePotts
is an ordinary downstream dependency, the old nested sources are deleted, and no production
LocalWorksets source depends on CorePotts, PottsToolkit, ModelingToolkit, SciML, or a vendor GPU
package. The package remains deliberately narrow: it implements the reviewed resolved and bounded
conjunctive mechanisms only.

All 89 acceptance rows pass on the candidate recorded below. No admission, evidence, allocation,
or throughput threshold was weakened. The direct CorePotts checkerboard path remains the public,
default `Supported` oracle; the LocalWorksets path remains private and experimental.

## Qualified environment

- Julia 1.12.6, official build, LLVM 18.1.7;
- macOS arm64 Darwin 24, Apple M1 Pro, eight CPU cores, one Julia compute thread;
- KernelAbstractions 0.9.42, Adapt 4.7.0, Atomix 1.1.3;
- Metal 1.10.0 on the real Apple GPU with `Metal.allowscalar(false)`;
- root authoritative test sandbox additionally re-resolved compatible MTK 11.38.2,
  ModelingToolkitBase 1.62.0, SciMLBase 3.44.0, SII 0.3.53, and Symbolics 7.36.0.

Hardware-neutral source is not a CUDA or ROCm qualification claim. Runtime admission remains
fail-closed outside the exact reviewed CPU and Apple M1/Metal rows.

## Package identity and graph

`LocalWorksets` has UUID `82808884-8acc-4a5c-a056-be440a0fbea1`, version `0.1.0`, Julia compat
`1.12`, and runtime dependencies exactly `Adapt`, `Atomix`, `KernelAbstractions`, and `SHA`.
`Aqua` and `Test` are test-only. There are no weak dependencies, extensions, preferences,
artifacts, build scripts, or vendor dependencies.

The active graph is:

```text
PottsToolkit -> CorePotts -> LocalWorksets
LocalWorksets -> Adapt, Atomix, KernelAbstractions, SHA
```

The root names LocalWorksets only as a test extra so Julia's sandboxed `Pkg.test` environment can
resolve CorePotts' local transitive source. PottsToolkit neither imports nor re-exports the API.

## Old-to-new provenance

| Frozen source | Standalone disposition |
|---|---|
| `CorePotts/src/localworksets.jl` | mechanically split into `model.jl`, `planning.jl`, `preparation.jl`, `execution.jl`, and `inspection.jl`; package-owned trust root replaces the Core UUID list |
| `execution/localworksets_resolved.jl` | moved to the standalone execution directory; sequence admission now crosses the same sealed exact central boundary as top-level planning |
| `execution/localworksets_conjunctive.jl` | moved to the standalone execution directory with the reviewed bounded two-key mechanism retained |
| `execution/localworksets_kernelabstractions.jl` | moved to the standalone execution directory as the only hardware-neutral provider |
| `execution/localworksets_evidence.jl` | moved as inert reviewed-environment data; it contains no executable method or vendor import |
| `CorePotts/test/test_localworksets.jl` | split into standalone API, mechanism, runtime, admission, support, and runner files |
| repository backend conformance | generic mechanisms moved to the package; only the Core checkerboard vertical/failure witnesses remain repository-owned |

### Symbol provenance

| Frozen symbol/responsibility | Exact standalone owner | Downstream status |
|---|---|---|
| `LocalWork`, declaration token/error, `localwork`, `sequence`, `value_slot`, `storage_slot`, `masked`, generic `resolved` declaration | `src/model.jl` | CorePotts constructs declarations only through public functions |
| `WorkPlan`, topology identity/epoch/fingerprint, sequence validation, central admission, `plan` | `src/planning.jl` plus the package-owned central lowering method in `src/execution/localworksets_resolved.jl` | topology remains supplied explicitly by CorePotts |
| `PreparedWork`, binding/schema/alias/device/workspace validation, `prepare` | `src/preparation.jl` | CorePotts supplies storage/workspace but owns neither package validation nor leases |
| `WorkEvent`, submission canonicalization, leases, poison, `run!`, cumulative `wait` | `src/execution.jl` | CorePotts retains the event and owns scientific settlement around it |
| `inspect` and lifecycle `show` methods | `src/inspection.jl` | CorePotts uses public inspection only for capability and diagnostic facts |
| one-key output/selection/lowering/prepared types, routing/capability/binding/workspace methods, four kernels | `src/execution/localworksets_resolved.jl` | no Core-specific branch or identifier |
| bounded conjunctive output/operation/lowering/prepared types, two-key validation and four kernels | `src/execution/localworksets_conjunctive.jl` | CorePotts supplies claim data and retains acceptance, RNG, lifecycle, commit and settlement semantics |
| KA lane, environment/device identity, sole synchronization, atomic/value capability and compiler identity | `src/execution/localworksets_kernelabstractions.jl` | no vendor extension or downstream callback owns execution admission |
| reviewed CPU/M1-Metal rows | `src/execution/localworksets_evidence.jl` | qualification data are distinct from mechanism/source portability |
| private checkerboard declaration, topology, storage/schema/workspace construction and submission | `CorePotts/src/execution/checkerboard_program.jl` | remains a CorePotts adapter over the public LocalWorksets lifecycle |
| Hamiltonians, descriptor evaluation, proposal views, clocks, RNG, acceptance, lifecycle, checkpoints, commit and settlement | CorePotts sources, unchanged in ownership | never moved into LocalWorksets |

### Test and assertion provenance

| Frozen evidence region | Exact current owner | Assertions retained or added |
|---|---|---|
| package quality and public/raw-constructor boundary | `lib/LocalWorksets/test/runtests.jl`, `test_api.jl` | Aqua, exact 15 public bindings, exact export/type/function inventories, doc metadata, private inventory and inapplicable raw constructors |
| generic one-key mechanism | `test_mechanisms.jl` testsets 1, 3, 4 and 5 | routing, rank/tie order, empty/mask/active rules, binding/workspace facts and submission-bound storage |
| bounded conjunctive mechanism | `test_mechanisms.jl` testset 2 | exact two-key wins, absent/idempotent keys, gate/active behavior, four launches and workspace |
| sequence and KA implicit ordering | `test_mechanisms.jl` final testset | retained declarations/order/visibility, eight ordered launches and no intermediate wait |
| topology, storage, lifetime, leases, cumulative events and poison | `test_runtime.jl` | stale topology, capacity, aliases, queued retention, task ownership, wait/drain and failure boundaries |
| source and hostile-method admission tests | `test_admission.jl` | generic-source vetoes; capability/compiler/lowering/lane/kernel/execution/submission/binding/topology piracy rejection; absent replaceable admission wrapper; exact cached-execution and central-method replacement rejection |
| generic CPU/Metal conformance helpers | `lib/LocalWorksets/test/backend_conformance.jl` | backend-generic one-key, sequence and bounded-conjunctive execution/failure facts |
| checkerboard vertical and failure cut | `lib/CorePotts/test/test_program_v1_localworksets_vertical.jl` | queued CPU execution, whole-MCS lease precheck, scientific failure cut and provider poison mapping |
| repository backend conformance | `test/backend_conformance/localworksets_execution.jl` | Core-owned CPU/Metal vertical and failure witnesses only |
| fixed direct/candidate parity | `benchmark/src/lw3_localworksets_parity.jl`, `benchmark/backends/metal/lw3_localworksets_parity.jl` | exact state, continuation, RNG mismatch, launches/waits/workspace/allocation/cache and throughput bound |

No active include or duplicate nested module remains. Every production source file has fewer than
1,000 nonblank/noncomment lines. The exact final total is 4,137 nonblank/noncomment production
lines; the largest file has 952 and per-file counts are recorded in the static transcript. The
final hash manifest inventories the exact source bytes.

## Acceptance disposition

Every ID below is an individual `Pass`; grouping records the common executable evidence without
collapsing the requirements.

### Package and API

| IDs | Disposition and evidence |
|---|---|
| E01, E02, E03, E04, E05 | Pass — parsed package/workspace projects, unique UUID/version/compat, exact dependency inventory, isolated `Pkg.test`. |
| E06 | Pass — clean `--startup-file=no` load excludes CorePotts, PottsToolkit, MTK, Metal, CUDA, and AMDGPU. |
| E07, E08 | Pass — independently active LocalWorksets, CorePotts, root, and Metal environments resolve explicit relative sources; `Pkg.resolve` reports no stale root manifest change. |
| E09 | Pass — 2,198-test root inventory remains exact; PottsToolkit exposes no LocalWorksets name. |
| E10 | Pass — duplicate/source scan finds no old nested files or active include. |
| A01 | Pass — exact 15-binding public inventory including the module self-binding; no wildcard exports or public raw constructors. |
| A02, A03, A04 | Pass — construction equivalence, canonical NamedTuple order, and declaration rejection tests. |
| A05 | Pass — ordered-stage, duplicate-port, item-domain, and visibility tests. |
| A06, A07 | Pass — exact slot/mask/resolved profiles and rejection of unimplemented families. |
| A08, A09 | Pass — sole lifecycle spellings are `plan(work, topology; backend)` then `prepare(workplan, storage; workspace, submission)`. |
| A10, A11, A12 | Pass — exact submission schema, real asynchronous receipt, cumulative/idempotent wait tests. |
| A13, A14 | Pass — non-waiting inspection/show tests and constrained Base extensions. |

### Admission and mechanisms

| IDs | Disposition and evidence |
|---|---|
| S01, S02, S03, S04 | Pass — hostile more-specific admission, lowering, capability, lane, kernel, execution, submission, binding, topology, and wait methods cannot replace package-owned methods or exact invokes. CorePotts additionally uses a named trusted adapter that exact-invokes and world-validates the accepted public `run!` and `wait` signatures; arbitrary callers using ordinary Julia public dispatch are not falsely claimed to be globally sealed. |
| S05 | Pass — world-counter and cached-method validation rejects post-prepare replacement, including the concrete submission/binding and execution specializations. |
| S06 | Pass — construction-token tests reject forged lifecycle values and receipts. |
| S07 | Pass — generated missing/extra/wrong-type/out-of-bounds/shape rejection is prelaunch and non-poisoning. A synchronous CPU failure after the clear launch poisons the full shared backend/device/owner-task scope and blocks its peer preparation; real Metal proves the same shared scope observes and retains asynchronous poison at the portable wait boundary. |
| S08 | Pass — source scan finds no Core UUID/name, external trust registry, or mutable registration path. Trust is `method.module === LocalWorksets`. |
| M01, M02, M03, M04, M05, M06 | Pass — 111 one-key resolved/z-buffer assertions plus final CPU/Metal conformance prove routing, total ordering, empty/mask/active behavior, four launches, workspace, permutation, sentinel, and result identity. |
| M07, M08, M09, M10, M11 | Pass — 33 bounded two-key assertions plus Core vertical prove conjunctive selection, absent/nonpositive keys, idempotence, gate/active rules, four launches, and two UInt32 destination workspaces. |

### Runtime and JuliaGPU

| IDs | Disposition and evidence |
|---|---|
| R01, R02, R03 | Pass — topology identity/epoch/fingerprint, stale-route rejection, and one-logical-adapter implicit-order sequence tests. |
| R04, R05, R06, R07, R08 | Pass — static/value/storage/device/layout/access/alias rejection and repeated-submission tests. |
| R09, R10 | Pass — exact workspace/capacity/one-short and all-preappend canonicalization tests. |
| R11, R12, R13 | Pass — fixed leases, dropped argument references while preparation remains live, cumulative-tail release, idempotence, queued same-task use, and no fabricated selective completion. |
| R14 | Pass for the bounded accepted contract — owner-task abandonment/cross-task recovery are unsupported; wrong-task submission/wait reject. No cancellation, transferable event, dropped-preparation reclamation, or provider-wide recovery is claimed. |
| R15, R16 | Pass — scientific/provider poison distinction, exact shared backend-owner-task failure scope, and complete non-synchronizing inspection facts. |
| G01 | Pass — provider/lowerings contain no vendor execution branch, native queue/stream/command buffer, or scalar-indexing path. The sole Metal strings are inert reviewed-environment metadata. |
| G02 | Pass — real-Metal compilation/execution succeeds with scalar indexing disabled and concrete adapted arguments. |
| G03, G04 | Pass — source scan finds exactly one `KernelAbstractions.synchronize(backend)` in the provider; sequences and four-stage lowerings insert no intermediate wait. |
| G05 | Pass — same-schema compiler-cache entries remain `324 -> 324` on real Metal. |
| G06, G07, G08, G09 | Pass — qualified backend/type/operation/address-space rejection, inert complete runtime/device fingerprint rows, exact warm current-device validation, unreviewed environment rejection, and hostile capability tests. |
| G10 | Pass — complete final real-Metal runner, including mechanisms, sequence, conjunction, isolated and shared-scope failures, cache, Core vertical, lifecycle policies, and parity. |

### CorePotts and quality

| IDs | Disposition and evidence |
|---|---|
| C01, C02, C03 | Pass — `CorePotts.LocalWorksets === LocalWorksets`; the private adapter uses public lifecycle signatures through exact trusted invocation, and a seven-assertion hostile-dispatch witness proves external more-specific `run!`/`wait` methods cannot intercept it; only the four claim launches move beneath Core orchestration. |
| C04, C05 | Pass — full Core/root Hamiltonian, descriptor, RNG, color, acceptance, bank, tracker, relationship, lifecycle, publication, and settlement suites pass. |
| C06 | Pass — exact direct/candidate continuation, mechanism mismatch, cross-lowering restore, and RNG evidence mismatch rejection. |
| C07 | Pass — candidate remains private `Experimental/ReplayQualified`; direct remains default `Supported`. |
| C08 | Pass — 18 scientific-failure and 6 provider-failure CPU assertions plus real-Metal failure witnesses. |
| C09 | Pass — complete real-Metal runner uses both standalone and Core packages with no LocalWorksets extension. |
| C10 | Pass — complete independently activated CorePotts suite. |
| C11 | Pass — authoritative PottsToolkit suite: 2,198/2,198 under current compatible SciML patches. |
| C12 | Pass — exact final CPU and Metal parity results below. |
| Q01 | Pass — Aqua plus an explicit recursive `Test.detect_ambiguities(LocalWorksets, Base)` assertion and exact Base-extension/piracy tests. |
| Q02, Q03 | Pass — source/load boundary scans and isolated package test/load. |
| Q04 | Pass — TOML/source/path/compat checks; all manifests produced by Pkg. |
| Q05 | Pass — every public binding has package metadata documentation; executable 15-binding coverage assertion. |
| Q06 | Pass for extraction — no duplicate old/new source and no production file above the 1,000-line ceiling. The resolved/conjunctive pipeline duplication and repeated world validation are explicitly deferred to bounded LW-4B consolidation before any third family; they are not changed under extraction evidence. |
| Q07 | Pass — clean-process load, root fresh-process, Metal extension-order, and stable trust/admission identity tests. |
| Q08 | Pass — `git diff --check`, local-link/source inventory, and dirty-worktree preservation. |

## Exact final quantitative evidence

### CPU fixed protocol

Command: `julia --project=. benchmark/src/lw3_localworksets_parity.jl`

- 128x128, 10 warm batches, 50 measured ten-MCS batches, 10,000 paired bootstrap samples;
- direct median `0.0256941670` s;
- candidate median `0.0259340415` s;
- median ratio `1.0093357570`;
- paired bootstrap upper95 `1.0123282545 <= 1.05`;
- direct median allocation `1,318,176` bytes;
- candidate median allocation `1,303,296` bytes, delta `-14,880`;
- 60 direct/candidate settlements, 60 LocalWorksets waits, 600 submitted/drained claims;
- four claim launches, zero topology transfer bytes, 12 leases, no poison;
- final ownership checksum `3,507,575` with exact receipt/state parity.

### Real-Metal fixed protocol

Command: `julia --project=benchmark/backends/metal benchmark/backends/metal/runtests.jl`

- direct median `0.1107828535` s;
- candidate median `0.1109990625` s;
- median ratio `1.0019516468`;
- paired bootstrap upper95 `1.0052174352 <= 1.05`;
- direct median allocation `17,678,968` bytes;
- candidate median allocation `17,149,648` bytes, delta `-529,320`;
- 60 direct/candidate settlements, 60 LocalWorksets waits, 600 submitted/drained claims;
- four claim launches, zero topology transfer bytes, 12 leases, no poison;
- final ownership checksum `3,507,575` with exact receipt/state parity.

Standalone Metal mechanism facts were four launches, 32 workspace bytes, 40 topology-transfer bytes
for the generic z-buffer topology, eight sequence launches, compiler cache `324 -> 324`, and a
provider `KernelException` observed at wait with poison set. A second exact witness prepared good
and failing work on the same backend/device/owner task: both waits observed `KernelException`, both
preparations were poisoned, and neither falsely claimed a selectively drained prefix.

## Failures retained and resolved

1. Extraction initially allocated `1,672,000` candidate bytes versus `1,318,176` direct. The
   cause was CorePotts calling the complete diagnostic `inspect(prepared)` once per MCS for a
   private lease precheck after the package boundary inhibited elimination. CorePotts now caches
   its own queue capacity and computes outstanding complete-MCS claims from its orchestration
   position; LocalWorksets' own lease rejection remains authoritative. The corrected trusted
   adapter candidate remains below direct at `1,303,296` bytes.
2. Root `Pkg.test` initially rejected a copied `[sources] LocalWorksets` without a test target.
   LocalWorksets is now an explicit root test extra/target only, preserving the runtime graph.
3. Aqua then required an exact compat for that extra; `LocalWorksets = "0.1"` was added. The full
   authoritative suite subsequently passed 2,198/2,198.
4. The new public-doc coverage test first used obsolete/ambiguous Docs reflection calls. It now
   checks Julia 1.12's package documentation metadata table and passes 14/14 API assertions.
5. Initial LW-R2A review reproduced an exact-signature external replacement of
   `_central_admission`; the first remediation then left the surrounding `_admit` wrapper open to
   more-specific dispatch. Each permitted an unauthorized four-launch execution and independently
   invalidated its candidate. The replaceable wrapper no longer exists. Top-level and recursive
   sequence planning now verify the exact `Tuple{LocalWork,Any,Any}` method owner inline and use
   exact `invoke`; more-specific external methods are bypassed, while exact-signature replacement
   is rejected before lowering or launch. Final hostile tests prove both cases. Every quantitative
   result in this record was regenerated after that second remediation; no earlier ballot or hash
   is inherited.
6. The same review then found that a more-specific `_execute_cached_lowering!` could replace the
   cached execution wrapper. Package-owned exact-invoke and world-checked execution boundaries now
   reject specialized and exact replacements before launch. The final hostile suite also covers
   lane creation, kernel factories, submission validation, binding derivation, and topology
   validation.
7. The initial KA adapter treated nominal preparations as independent failure scopes even though
   its only portable wait was backend-wide `KernelAbstractions.synchronize(backend)`. That could
   misattribute an asynchronous Metal failure. Exact backend/device/owner-task preparations now
   share one scope; the real-Metal witness proves both affected preparations observe the failure,
   both remain poisoned, and neither reports a selective drain.
8. The first Metal qualification row identified only a backend value, not the exact device and
   runtime. Planning/preparation now freeze the complete reviewed Apple M1 Pro registry/runtime/
   preference fingerprint. Warm submissions validate the exact current-device token without
   rebuilding diagnostic evidence.
9. CorePotts could initially derive candidate `Functional`/`ReplayQualified` evidence from an
   unsupported direct base and reached into `PreparedWork` fields. Candidate evidence is now
   conjunctive with the base execution/replay authority and nonempty evidence; a seven-assertion
   test proves it cannot mint support. Core uses exact public `inspect`, while lease capacity is
   retained as Core-owned adapter state.
10. Sealing the generic submission/binding path through abstract exact invokes caused a final CPU
    allocation regression (`1,348,160 > 1,318,176` bytes). Concrete package-owned submission and
    binding specializations are now cached, owner-checked, and world-checked; fixed-schema
    validation is unrolled without weakening type/bounds/backend/device/layout checks. The final
    candidate is below the direct allocation baseline on CPU and Metal.
11. An earlier full Metal rerun rebuilt the complete environment probe on every warm submission,
    causing an allocation/parity failure. Splitting complete preparation-time evidence from the
    cheap exact current-device token removed that diagnostic hot-path work. Failed intermediate
    transcripts remain in `lw4a-logs`; the later `*-remediated.txt` records and final hashes support
    the corrected candidate, while `*-qualified.txt` files remain prior-candidate audit history.
12. Fresh LW-R2A review found that synchronous CPU kernel failure poisoned only its
    `PreparedWork`, even though the preceding clear launch had already modified output and the KA
    wait/error scope is shared. Validation and method ownership now complete before lowering entry;
    every failure after that boundary conservatively poisons the shared provider scope. A dedicated
    two-preparation CPU witness proves the failing and peer preparations both become unusable while
    generated prelaunch rejection remains non-poisoning.
13. The same review demonstrated that ordinary Julia dispatch at CorePotts' public `run!` and
    `wait` calls could be intercepted by a more-specific external method. CorePotts now owns a
    narrow trusted adapter that stores the accepted public methods, revalidates them after world
    changes, and exact-invokes their public signatures. The threat statement now distinguishes
    these named trusted boundaries from arbitrary external callers, which Julia cannot globally
    seal.
14. API/package-quality review found three P2 traceability/maintenance seams. Generated negative
    schema branches, the exact raw-constructor arity, full non-evidence source portability, and
    recursive ambiguities now have executable tests. Lowering-pipeline and world-validation
    duplication is explicitly deferred to bounded LW-4B consolidation before a third family;
    changing it during extraction would invalidate rather than strengthen parity evidence.
15. The first corrected-candidate API ballot then rejected four matrix claims that the runtime
    evidence did not exercise: do-block equivalence, declaration-shape validation, typed/nonempty
    value-slot bounds, storage-template element types, and closure of the reviewed one-key/two-key
    destination profiles. The
    bounded correction makes output declarations package-recognizable, restricts `localwork` to
    the reviewed unit-range/read/output/operation/active shapes, restricts `value_slot` bounds to
    nonempty exact-typed unit ranges, requires concrete storage element types, and replaces the
    catch-all one-key `resolved` constructor with its exact symbolic destination form. New
    executable rows cover all four findings. The
    README and roadmap traceability P2s were corrected at the same time. These changes do not add
    an output family, public executor, backend claim, or LW-4B authoring convenience.

Registry download warnings during early standalone/Core tests did not alter results; later root
testing successfully resolved compatible patch releases in its disposable sandbox.

## Final hashes and command record

The complete, full-length per-file SHA-256 inventory is
[`lw4a-final-hashes.sha256`](lw4a-final-hashes.sha256). It includes every LocalWorksets source and
test, every affected CorePotts/root/Metal source or test, all active project/manifests, the parity
drivers, and this gate packet. Exact per-source line counts are recorded in the static evidence;
the digest inventory excludes only itself, because a file cannot contain its own stable digest.

Exact commands, exit status, all test-summary counts, the qualified environment and the full CPU
and Metal quantitative summaries are in
[`lw4a-command-outcomes.md`](lw4a-command-outcomes.md). This evidence file does not abbreviate a
hash or rely on a pre-remediation result.

## Gate disposition

The exact candidate passed the fresh
[`LW-R2A committee review`](lwr2a-localworksets-extraction-review.md) unanimously with P0=0, P1=0
and P2=0. LW-4A is complete. This clearance makes LW-4B eligible for a separately directed start;
it does not implement independent/combined/heterogeneous outputs, freeze the final authoring API,
promote the CorePotts candidate, remove the direct oracle, begin LW-4B or open G6.
