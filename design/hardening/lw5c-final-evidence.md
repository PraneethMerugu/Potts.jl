# LW-5C exact-candidate qualification

Date: 2026-08-14

Status: **QUALIFIED AND REVIEWED; BOUNDED NON-DEFAULT CANDIDATE FROZEN**

This packet qualifies only the bounded, non-default K02→K03 adoption
candidate in the [adoption matrix](lw5c-adoption-matrix.md). It does not make
LocalWorksets the public/default checkerboard engine, open another operation
family, open LW-5D/LW-R3, or open G6.

## Exact candidate

Composite digests hash the sorted `shasum -a 256` records of every Julia file
in the stated tree, binding paths and contents.

| Surface | SHA-256 |
|---|---|
| `lib/LocalWorksets/src` | `bc2f1a66f6499b90da4503a2e7590e1dc359b1ecd34130df2a5cfc040649c4bf` |
| `lib/LocalWorksets/test` | `55bc71385481a032b821afce7d969fce624c8d2e5d5f5795243a215553188b72` |
| `lib/CorePotts/src` | `9071650dfd9e1ed988e9fdc34b64faf15b2cb71fd0267457126e83a52cb54057` |
| `lib/CorePotts/test` | `f12e69598e71d3ad43b48df651fdafa2e7c93ec00d39be56a2fac806bd735ecd` |
| root `src` | `c307aa522502a967bd8b060eb48e4424af28bdc7064a4fd89ae59d99aafe3ede` |
| root package-test Julia files | `7b70bd30ceadef3ee3835cfa80c2a6d83646334293281aae99ac15e369baf600` |
| LocalWorksets witnesses plus CPU/Metal benchmark sources/environments | `7fc9fc80234cee5e27ba56be93a60575cda66a10314314d984fdde77ff6776dc` |
| root `Project.toml` | `dff6aba68029e2a5260422239d11bd346ce84dd7fd075e287e46a7d68d1179de` |
| `lib/CorePotts/Project.toml` | `acb0b9e2f2cf125329395bf90a210a47a8c8de6a322ea8f3e9d500af76e49033` |
| `lib/LocalWorksets/Project.toml` | `a71dabb4f3bc0e38b7572d5e23826075b354f0e9d50fc2daf4be6dae371b6e4f` |

Selected identities:

```text
4c4f48bccc4afd10a292ecdaebc03e0f9260b385a9cd6ad84f4197d552e003f8  lib/CorePotts/src/execution/checkerboard_kernels.jl
2e3a5936d7ee42b8b82f9a49444137bbf8d8b6746d8470864e28c8184f1c8c33  benchmark/src/lw5b3_proposal_parity.jl
6b4ea91ed1df19617c61b91bd4dee474d392fdae52815e5057cdb7269b1f7135  benchmark/backends/metal/lw5c_probe.jl
198315d8c623e6086fd4ca91b15ee75583eb6d745e7d5eb88a414d9af06edc37  benchmark/backends/metal/runtests.jl
```

The direct K02/K03 oracle is byte-for-byte unchanged from the LW-5B4O entry.

## Final implementation facts

- K02 candidate generation and K03 descriptor evaluation are one
  `LocalWorksets.sequence` with two launches per color.
- KernelAbstractions implicit ordering supplies stage visibility; there is no
  intermediate wait or fabricated event.
- `waitall` reaches the one portable
  `KernelAbstractions.synchronize(backend)` provider boundary and drains the
  cumulative submitted prefix.
- Twelve MCSs queue on one lane. Capacity exhaustion rejects before launch,
  does not poison, and the admitted tail remains drainable.
- Topology identity covers sites, color offsets, conflict displacements,
  proposal offsets, descriptor fingerprint/source table, and canonical source
  schedule.
- Hamiltonian source-order folding, proposal before/after views, RNG,
  acceptance, claims, transactions, clocks, publication, checkpoints, and
  settlement remain CorePotts-owned.
- The adopted arm never invokes `_checkerboard_candidates_kernel!` or
  `_checkerboard_evaluate_kernel!`; they remain the independent direct oracle.
- No later operation family is opened.

## Mandatory layout integration

`StaticArrays` and `StructArrays` are ordinary direct dependencies of both
reusable packages, not optional extensions.

- CorePotts uses one zero-copy `StructArray` proposal schema over the existing
  authoritative component arrays. K02 publishes it and K03 reads its six-field
  projection without replacing the underlying SoA storage.
- LocalWorksets validates every record component's type, shape, strides,
  backend, device, access, aliasing, and identity before execution and performs
  explicit generated leaf stores.
- LocalWorksets accepts bounded `StaticVector` lane bundles through the same
  fixed-lane algebra as tuples; arities above 32 reject for static vectors.
- CorePotts Philox uses `SVector{4,UInt32}` counters and
  `SVector{2,UInt32}` keys while preserving tuple-facing known answers and
  semantic RNG addresses.
- D2Q9 and other non-CPM witnesses exercise the same component-record and
  fixed-lane mechanisms on CPU and real Metal.

The root product pins `StaticArrays = 1.9.18` and `StructArrays = 0.7.3`
because its authoritative checkpoint/replay tests require the already reviewed
exact dependency identity. CorePotts and LocalWorksets retain broad compatible
bounds (`1` and `0.7`) so the reusable packages do not claim that other patch
versions are broken; they simply do not acquire this exact replay evidence.

## Complete qualification

All commands used Julia 1.12.6, one Julia thread, and the Apple M1 Pro host.

| Lane | Command | Result |
|---|---|---|
| focused Core program | `julia --project=lib/CorePotts --startup-file=no --threads=1 -e 'using Test, CorePotts; include("lib/CorePotts/test/test_program_v1.jl")'` | passed every focused testset, including the 12-MCS vertical, identity rejection, failure boundary, and checkpoints |
| CorePotts package | `julia --project=lib/CorePotts --startup-file=no --threads=1 -e 'using Pkg; Pkg.test("CorePotts")'` | `CorePotts tests passed` |
| LocalWorksets package | `julia --project=lib/LocalWorksets --startup-file=no --threads=1 -e 'using Pkg; Pkg.test("LocalWorksets")'` | `LocalWorksets tests passed`, including API, piracy/admission, sequence ordering, `StaticVector`, and `StructArray` rows |
| authoritative root | `julia --project=. --startup-file=no --threads=1 -e 'using Pkg; Pkg.test("PottsToolkit")'` | 2,664/2,664 passed in 18m42.0s |
| complete real Metal | `julia --project=. --startup-file=no --threads=1 runtests.jl` from `benchmark/backends/metal` | exit 0; extension load order, cross-domain, native components, LW-5C, backend failure, lifecycle, and all fail-closed rows passed |

The root manifest could not be reused because its older
StateSelection/OrderedCollections conjunction is incompatible with the test
extras. `Pkg.test` therefore performed its intended compatibility
re-resolution. The root product pin retained StaticArrays 1.9.18 and
StructArrays 0.7.3 while the SciML stack resolved forward. The earlier run that
selected StaticArrays 1.9.19 correctly failed exact replay and is diagnostic,
not evidence; no new environment digest was self-authorized.

## Real-Metal persistent probe

The final complete runner reported:

```text
schema = :lw5c_proposal_stages_adoption_v1
queued_mcs = 12
colors = 2
launches_per_color = 2
submissions = 24
waits = 1
scope_synchronizations = 1
algorithmic_workspace_bytes = 0
topology_transfer_bytes = 0
warm_host_allocations = 299584
compiler_cache = 322 -> 380 -> 380
exact_receipt_parity = true
exact_rng_trajectory = true
expected_failure_parity = true
intermediate_waits = 0
production_default = false
```

Compiler-cache counts are diagnostic and depend on which earlier runner blocks
have compiled. First-use growth is permitted but not required; the executable
invariant is no second warm growth. The isolated run's earlier
`4 -> 62 -> 62` observation is consistent but is not treated as a fixed count.

## Paired performance

The exact cleaned source was rerun after dead-helper removal. The protocol is
128×128, ten warm batches, fifty paired measured ten-MCS batches, deterministic
arm order, 10,000 paired bootstrap resamples, and unchanged upper-95
noninferiority threshold 1.05.

| Measure | CPU | real Metal |
|---|---:|---:|
| direct median seconds | 0.0251879795 | 0.1126387920 |
| adopted median seconds | 0.0259179585 | 0.1125552710 |
| median ratio | 1.0289812448 | 0.9992585059 |
| paired bootstrap upper 95% | 1.0423004818 | 1.0043324310 |
| threshold | 1.05 | 1.05 |
| direct median bytes | 1,319,296 | 17,704,720 |
| adopted median bytes | 1,508,896 | 17,986,160 |
| byte delta | +189,600 | +281,440 |
| direct median allocations | 10,227 | 261,538 |
| adopted median allocations | 11,500 | 263,919 |

CPU includes a genuinely registered external Hamiltonian lowered through
PottsToolkit `complete` and `mtkcompile`. Metal uses the reviewed built-in
surface and proves that external Metal mechanisms remain fail-closed.
Allocation deltas remain optimization debt and are not relabeled as parity.

## Portability and scope audit

- Reusable LocalWorksets execution source contains no Metal, CUDA, AMDGPU,
  ROCm, native queue, stream, command-buffer, scheduler, or host-fallback
  branch.
- The only vendor tokens in LocalWorksets are inert, centrally reviewed Metal
  qualification metadata.
- The only provider synchronization site is one
  `KernelAbstractions.synchronize(scope.backend)` call.
- CPU and this exact Apple M1/Metal environment are runtime-qualified. CUDA
  and ROCm remain unclaimed.
- Direct claims and every CorePotts scientific/transactional authority remain
  outside LocalWorksets.

## Consolidation and remaining debt

The matched surfaces fell from 3,406 to 1,189 physical lines: 740 loaded
production lines and 1,477 regular-test lines removed. The last cleanup deleted
49 physical lines of uncalled lifecycle, wait, science-view, and proposal-fact
helpers. This is evidence of ownership cleanup, not an arbitrary size target.

The candidate remains deliberately non-default. Its temporary parallel
workspace/capability/replay/checkpoint/settlement lifecycle is approximately
339 lines. LW-R3 must merge or delete that parallel lifecycle and give the
direct implementation a reference-only disposition before any default
promotion. A permanent pair of coequal engines is rejected. The current
result does not justify adding another operation family.

Carried optimization debt:

- CPU: +189,600 bytes and +1,273 allocations per measured batch;
- Metal: +281,440 bytes and +2,381 allocations per measured batch; and
- compiler-cache absolute counts and warm host allocations remain diagnostics,
  while the no-second-growth and throughput gates are normative.

The fresh committee disposition is recorded in the
[LW-5C exact-candidate review](lw5c-review.md). It returned P0=0 and P1=0,
accepted this exact bounded candidate, preserved the P2 debt above, and kept
default promotion, LW-5D, LW-R3, G6, and every later operation family closed.
