# LW-4B B5 Exact-Source Qualification Evidence

Date: 2026-08-11

Status: corrected B5 exact-source qualification complete; LW-R2B passed

## Candidate and boundary

This record qualifies the bounded LW-4B implementation described by
`lw4b-general-mechanism-implementation-matrix.md`. It does not freeze Level-1 spelling, authorize
arbitrary external execution laws, qualify CUDA/ROCm, remove the specialized parity oracles, begin
LW-4C, or authorize LW-5.

The candidate implements reusable declarations, validation, lowering, preparation, execution,
lifetime and inspection only. LBM, spring, FEM, z-buffer and CPM names occur in witnesses or domain
packages, not in LocalWorksets mechanism source. CorePotts retains RNG, acceptance, Hamiltonian
folding, checkerboard colors, conjunctive claims, settlement, commits, lifecycle and checkpoints.

The B0 provenance remains separately auditable in `lw4b-b0-consolidation-evidence.md`: it records
the pre-consolidation hashes, the first B0 hashes, and the six helpers moved into
`execution/mechanism_support.jl`. Later generic work reused that package-owned support file; it did
not rewrite the preserved conjunctive oracle or introduce an executor hierarchy.

## First-candidate veto and bounded remediation

The first exact B5 candidate passed its numerical suites but did not pass LW-R2B. Independent
reviewers reproduced two P0 preparation-integrity defects: a more-specific external operation
method could replace the method validated at preparation, and a caller could mutate a structural
workspace container so execution indexed different scratch arrays than validation inspected. The
committee also retained P1 findings for late external-law rejection, unchecked Int32 ABI/capacity
arithmetic, incomplete plan inspection, missing generic submission-bound reads, inaccurate failed-
tail prose and a CPU performance script that did not fail its process.

The corrected candidate remains within the accepted two-family architecture. It:

- records the exact selected external operation/qualified deterministic-law methods and rechecks
  them before a new submission when Julia's world age changes;
- requires recursively immutable workspace structure while permitting mutable array leaves, so a
  caller cannot substitute validated scratch references after preparation;
- freezes each `storage_slot` to the exact qualified concrete array representation and exercises a
  distinct warm submission array on CPU and real Metal;
- rejects unknown combination-law subtypes during declaration construction;
- uses checked Int/Int32 arithmetic for item, destination, route, record, segment, transfer and
  workspace bounds, with lazy oversized hostile fixtures;
- exposes planned phases and per-port publication/failure/empty facts in `inspect(WorkPlan)`;
- requires exact `UInt64` topology epochs and rejects empty resolved-route names; and
- makes a failed CPU performance row terminate the evidence command unsuccessfully.

The refreshed review then found a second bounded set of issues before ballot: per-port plan
evidence still omitted route/count/maximum/coverage-law/determinism facts; invariant
`PreparedWork` fields could be reassigned; the preserved resolved/conjunctive profiles did not
apply the generic exact-`UInt64`/Int32 ABI and checked-byte rules; and `wait(event)` could revalidate
hostile methods before synchronizing an already submitted prefix. The final candidate closes those
issues by making structural prepared fields `const`, completing per-port inspection, applying the
same checked ABI to the specialized profiles, and invoking the already-admitted wait path in the
last successfully validated submission world. A lease retains only submission-bound storage;
prepared static storage, workspace and runtime remain retained by `PreparedWork` itself.

On the first final-hash ballot, the API reviewer retained one P1: generic buffered ports were
complete, but the preserved resolved-selection and conjunctive plans still reported `ports =
nothing`, and direct independent ports did not state empty-destination behavior explicitly. The
final inspection remediation gives every accepted specialized port its route, destination count,
emission bound, coverage applicability, law, publication/failure behavior, empty result and
determinism. Independent ports now explicitly distinguish impossible empties under total coverage
from preserved storage under partial coverage. Regression tests exercise all three cases.

The next focused ballot found one further semantic inspection mismatch: literal `true` and `false`
resolved emission masks appeared identical because evidence reported only the optional storage-mask
binding, and the item-aligned conjunctive result mislabeled its loser value as a keyed empty-
destination publication. The final candidate reports both actual emission mask and optional mask
binding. Conjunctive evidence now distinguishes item-result publication and its empty loser value
from the private keyed arbitration tables and their explicit no-winner rank/identity state.

No admission rule, performance threshold, mechanism family or scientific ownership boundary was
weakened to close these findings.

## Exact commands and suite results

Run from the repository root:

```sh
julia --project=lib/LocalWorksets/test lib/LocalWorksets/test/runtests.jl
julia --project=lib/CorePotts -e 'using Pkg; Pkg.test()'
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=test/localworksets_witnesses test/localworksets_witnesses/runtests.jl
julia --project=test/localworksets_witnesses test/localworksets_witnesses/performance.jl
julia --project=benchmark/backends/metal benchmark/backends/metal/runtests.jl
```

| Command | Exact result |
|---|---|
| standalone LocalWorksets | 511/511 passed |
| complete CorePotts | 17,462/17,462 passed; `CorePotts tests passed` |
| authoritative root | 2,232/2,232 passed; `PottsToolkit tests passed` (wall time excluded because the laptop travelled during the run) |
| CPU cross-domain witnesses | all five reports completed with exact/tolerance-qualified references and invalid-case rejection |
| CPU performance | both frozen paired-bootstrap upper-95 bounds passed |
| complete reviewed real Metal | exit 0; cross-domain, native component, hostile admission, boundary, failure, queued checkerboard and LW-3 parity evidence passed |

## Durable witness facts

The CPU witness command reported:

| Witness | Result | Launches | Wait count after measured run plus warm run | Topology transfer | Algorithmic workspace | Warm host bytes |
|---|---|---:|---:|---:|---:|---:|
| D2Q9 independent | exact, submission-bound read exercised with distinct arrays | 1 | 2 | 432 | 0 | 3,456 |
| spring deterministic | exact | 2 | 2 | 168 | 76 | 3,888 |
| spring fast Float32 | qualified tolerance, exact for this fixture | 3 | 2 | 112 | 36 | 3,280 |
| matrix-free FEM | exact canonical fold, empty destination `0f0` | 2 | 2 | 132 | 60 | 2,512 |
| generic z-buffer | exact rank/identity winner, explicit empty `0x00` | 2 | 2 | 80 | 45 | 3,056 |

Each individual submission is followed by one final `wait`; the reported count is two because each
witness deliberately performs one evidence submission and one warm-allocation submission. The
host-byte measurement is diagnostic Julia submission overhead, not algorithmic workspace and not a
zero-allocation claim.

All witnesses import only public LocalWorksets bindings, construct an external isbits operation,
bind real storage/workspace, compare against a separately written reference, exercise an invalid
declaration/topology/workspace case, inspect the lifecycle, execute, and establish host visibility.

## Frozen direct-parity measurement

Both fixtures use 1,000 paired samples, batch size 16, a fixed randomized direct/candidate ordering,
10,000 fixed-seed bootstrap resamples, and the unchanged upper-95 threshold of 1.05.

| Backend/profile | Direct median | Candidate median | Median ratio | Bootstrap upper 95 | Result | Median direct/candidate host bytes |
|---|---:|---:|---:|---:|---|---:|
| CPU D2Q9, side 512 | 0.0302677505 | 0.0292718125 | 0.9670957378 | 0.9691686842 | pass | 3,584 / 5,712 |
| CPU z-buffer, 131,072 destinations | 0.0261491040 | 0.0263545835 | 1.0078579939 | 1.0111241115 | pass | 5,632 / 30,544 |
| Apple M1/Metal D2Q9, side 256 | 0.0017390840 | 0.0017558750 | 1.0096550828 | 1.0102096167 | pass | 50,416 / 95,600 |
| Apple M1/Metal z-buffer, 262,144 destinations | 0.0049110840 | 0.0050273540 | 1.0236750176 | 1.0433520766 | pass | 98,432 / 163,328 |

The direct D2Q9 oracle is one kernel. The direct z-buffer oracle uses the same declared operation,
rank bounds, empty value, fixed records and two apply/publish launches as the candidate profile; it
does not omit semantic work to manufacture parity.

One P1 performance failure was found during B5: the first exact full-load Metal z-buffer upper bound
was 1.063279. The threshold, workload, sampling, randomization and bootstrap were preserved. A
generic fixed-arity lowering for one to four flat logical reads, static named-port extraction,
scalar rank bounds and branchless fixed scratch-slot writes reduced the final upper bound to
1.0274028498. The arbitrary-read fallback remains. A false candidate still sets `valid=false` and
therefore emits no record; dynamic rank bounds apply only to valid candidates.

During refreshed review, one full old-candidate run also produced D2Q9 upper 95 of 1.0584; its
isolated repeat and a second complete run passed. The failure is preserved rather than averaged
away. After the final lease-retention correction, the complete exact-candidate run passed at
1.0358971632 and 1.0184187012. A separate fresh-process repeat passed at 1.0363709245 and
1.0177378316. The 1.05 threshold and all sampling parameters remained unchanged.

## Complete real-Metal qualification

The exact runner used `Metal.allowscalar(false)` and the centrally admitted Apple M1/Metal identity.
It reported:

- extension load order: 2/2;
- cross-domain mechanisms: 8/8, compiler cache 0 to 20 (20 compiled entries);
- native components: 37/37;
- legacy resolved profile: four launches, 32 workspace bytes, 40 topology-transfer bytes, 12
  leases, eight sequence launches, and same-schema cache 353 to 353;
- backend failure: `KernelException`; both waits observed the shared failure, both provider scopes
  were poisoned, retained leases were not reclaimed, and both drained counters remained zero;
- queued checkerboard: 12 submitted and committed MCSs, 12 claim submissions, one synchronization,
  checksum 8;
- expected scientific failure: commit 0 and no provider poison; provider failure:
  `LifecycleBackendFailure` and poison;
- external Metal, relationship, surface and lifecycle mechanisms failed closed (2/2, 3/3, 2/2,
  1/1);
- boundary shapes `(1,1)`, `(255,1)`, `(256,1)`, `(257,1)`, `(17,19)` matched CPU across
  workgroup sizes 32, 64, 128 and 256; and
- LW-3 checkerboard direct/candidate parity used 60 settlements each, 60 synchronizations each,
  60 LocalWorksets waits, 600 submitted/drained operations, zero topology-transfer bytes, record
  capacity 12 and no poison. Its ratio was 1.0047053473 and upper 95 was 1.0237674656.

The tiny historical z-buffer rows remain diagnostics only. Performance qualification rests on the
full-load measurements above.

## Portability, ordering and admission checks

The production scan:

```sh
rg -n 'Metal|CUDA|AMDGPU|CuArray|ROC' lib/LocalWorksets/src
rg -n 'KernelAbstractions\.synchronize|synchronize\(' lib/LocalWorksets/src
```

finds no vendor branch. The only `Metal` strings are exact reviewed qualification metadata in
`execution/localworksets_evidence.jl`; no extension contains LocalWorksets execution code. This is
intentionally isolated qualification data and is not a CUDA/ROCm claim.

There is exactly one executable portable synchronization call:
`KernelAbstractions.synchronize(scope.backend)` in
`execution/localworksets_kernelabstractions.jl`. Sequential launches rely on KernelAbstractions
0.9 implicit ordering. `run!` remains asynchronous where the backend supports it; `wait` drains the
actual cumulative submitted prefix. LocalWorksets contains no native queues, streams, command
buffers, scheduler or transferable-event fiction.

Standalone hostile tests cover source-level mechanism ownership, wrapper replacement, more-specific
capability methods, compiler-evidence piracy, lowering piracy, cached-execution replacement and
central-admission replacement. The complete Metal runner also proves external unreviewed mechanism
rows fail closed on the actual device. External declarations therefore cannot self-authorize
backend execution.

Static prepared bindings validate backend/device during preparation and retain exact object
identity. Dynamic submission storage revalidates exact concrete array type, eltype, rank, shape,
strides, access, aliases, backend and device on each use. Workspace structural containers are
recursively immutable; mutable array leaves retain their validated identities. Queued submissions
retain submission-bound arrays and scalar arguments until their cumulative event is covered;
`PreparedWork` itself retains static arrays, workspaces and runtime. Older successful waits release
the completed tail, already-covered waits are idempotent, a hostile method added after submission
cannot prevent the admitted synchronization/drain, failed shared
provider tails retain leases with drained counters at zero, and unsupported cross-task recovery is
rejected rather than simulated.

## Determinism and scientific ownership

Canonical combination is an explicit `(item, local_slot)` fold with a declared identity. Fast
addition is a separate qualified law and explicitly denies replay, workgroup and cross-backend
bitwise guarantees. Resolved output uses a total bounded rank and topology-owned canonical UInt32
semantic identity; empty destinations publish the declared empty value and false/zero lanes make no
claim. No floating-point or cross-backend determinism is inferred from device portability.

CorePotts qualification preserves:

- canonical source-order Hamiltonian folding and Hamiltonian authoring above LocalWorksets;
- current before/after proposal views, acceptance, RNG addressing and conjunctive old/new-owner
  claims in CorePotts;
- queued checkerboard color generation without intermediate waits;
- settlement, commit cuts, lifecycle receipts and failure mapping in CorePotts; and
- exact checkpoint continuation plus execution-environment/RNG mismatch rejection.

The generic resolved witness resembles keyed arbitration but does not contain CPM claims. The
preserved conjunctive lowering remains the CorePotts parity/adoption mechanism until LW-R2B decides
the consolidation/removal disposition.

## Review-unit and footprint facts

Every production review unit remains below the 1,000 nonblank, noncomment-line cap. The largest
units are `localworksets_combined.jl` at 945 such lines, `localworksets_resolved.jl` at 907 and
`localworksets_conjunctive.jl` at 854. The 18 unique production source files total 7,745 physical
lines. This is a reviewability fact, not a
claim that the implementation is already consolidated or has a finished authoring surface.
Generic, specialized single-resolved and conjunctive machinery, declaration density and validation
layering remain explicit complexity debt for LW-4C; safety and evidence layers may not be removed
merely to reduce this count.

## Exact hashes

`lw4b-b5-final-hashes.sha256` records the final production, test, witness, benchmark, matrix and
evidence files. The hash manifest deliberately does not hash itself.

## Gate disposition

B5 is corrected exact-source complete and LW-R2B passed on this exact source. LW-4C may begin. This
record is not an API freeze and does not authorize LW-5 or G6.
