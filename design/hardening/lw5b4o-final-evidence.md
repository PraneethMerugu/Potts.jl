# LW-5B4O exact-candidate evidence

Date: 2026-08-13

Status: **SEALED; LW-5B4O-R PASSED WITH P0=0, P1=0**

Authority is the bounded phase in
[lw5b4o-mandatory-layout-and-execution-optimization.md](lw5b4o-mandatory-layout-and-execution-optimization.md).
This record does not promote the LocalWorksets checkerboard vertical to the
production-selected implementation. The direct CorePotts kernel remains both
selected and the independent performance/science oracle.

## Exact candidate

Composite digests below hash the sorted `shasum -a 256` records of every Julia
file in the stated tree. They bind paths as well as contents.

| Tree | SHA-256 |
|---|---|
| `lib/LocalWorksets/src` | `bc2f1a66f6499b90da4503a2e7590e1dc359b1ecd34130df2a5cfc040649c4bf` |
| `lib/CorePotts/src` | `97f1d8b88de73cb865a24590d7921680c349b1db00c18f05d7a83294a80f42b0` |
| `lib/LocalWorksets/test` | `55bc71385481a032b821afce7d969fce624c8d2e5d5f5795243a215553188b72` |
| `lib/CorePotts/test` | `822f23236263c462ae0ed7c611bbc9db53d2864586f57e51b7ae3cae82dc7509` |
| Local-work witnesses plus CPU/Metal benchmark sources/environments | `08e84b163a4bed8ba5696aa1b8a5812155801e494e00930d88e73a32e3a0c893` |

Selected individual identities:

```text
4c4f48bccc4afd10a292ecdaebc03e0f9260b385a9cd6ad84f4197d552e003f8  lib/CorePotts/src/execution/checkerboard_kernels.jl
b23f567c0f702915154f4358a507b0ff8413d59d498821e9e20005ae03c82740  lib/CorePotts/src/execution/checkerboard_program.jl
923a6e5ad702c8c8766a14027855a5cdcd04f2af18c8e13edc12e2c4f29d21f1  lib/CorePotts/src/execution/checkerboard_proposal_batch.jl
cc120e9a67a8dcee5b5aeea946e2c35bd821ac9826a23a57e0c3fc6a98b90480  lib/CorePotts/src/execution/localworksets_candidate_bridge.jl
eae1eed02088f6412762d9fbe1b7fd76f105b5cf1dee2e2bf184dfbfc5b710f2  lib/CorePotts/src/execution/localworksets_proposal_bridge.jl
10b779f0c4ec041116853e47d19b5c6a514b1f879e0bd795866ad5e94bc32004  lib/CorePotts/src/rng/semantic.jl
20cda7d6251d2c8052ede5c294a2364c03be920e20dcc28929d4b4b7c33eb10c  lib/LocalWorksets/src/execution/localworksets_generic.jl
87bef8260eacb8b4fe4b50c82438d2c04afce38e012eff664e2885637804fbd0  lib/LocalWorksets/src/execution/record_storage_support.jl
61db297125c49ac170550a093575ac761a6d2c274f8ee9a5f2388ed6bcc96295  lib/LocalWorksets/src/execution/fixed_lane_support.jl
728b53d93fc358b260446e725341bc8f8a147975f93793e11436c12ec037e0e4  lib/LocalWorksets/src/preparation.jl
d04b4ac944c586f0826f2b8aa6a6aff6f245f50a66517c0ea68862c7e87be88c  lib/LocalWorksets/src/execution.jl
e722f04cbf624aa47ff1f32dfbd88fb63a019a5fcb262986b9e28ddb785c83fb  ext/PottsToolkitMetalExt.jl
313636d48e6edf872a79f2e9b90ad74b92620ec17bb8f84a0d3cd65fddc85127  test/localworksets_witnesses/lbm_d2q9.jl
ac8ad3261e504bcf1755a9f7e6374f442b51ea703874c9e3b93252e7d491ea66  benchmark/src/lw5b4_candidate_parity.jl
5ad3c2fa07c0b6668e63ca2adf03c46e88293357ee025d1ac4937ce53499bbfa  benchmark/backends/metal/lw5b4_candidate_parity.jl
4917572338e3f7ef21266f3d714803b0a59da9ac566913e07f51033bf17414e7  benchmark/src/lw5b4o_dependency_footprint.jl
4a32638629533cc9676d77911e01f7f9dcca18fcd16ef67bd5babf4bd0a9c7c4  design/hardening/lw5b4o-performance-raw.md
```

The direct checkerboard kernel digest is byte-for-byte identical to O0. The
working tree remains intentionally dirty with the preserved LW-5 sequence;
no reset, checkout or unrelated cleanup was performed. `git diff --check`
passes.

## Implementation disposition

| Row | Final disposition | Evidence |
|---|---|---|
| O1 | Passed | The checkerboard program owns a layout-independent logical topology epoch over complete sites, color offsets, conflict displacements and proposal offsets. Candidate preparation proves both banks against that epoch and requires host-resident canonical arrays for host hashing. A nonzero submission count must equal the selected color's exact size; zero is the explicit no-emission case. Wrong sites/order, color offsets, conflict displacements, proposal offsets, bank, color and count reject before launch on CPU and Metal. |
| O2 | Passed | StaticArrays 1.9.18 and StructArrays 0.7.3 are ordinary direct dependencies/imports of both packages. Root tests and the Metal benchmark list the packages where directly imported. Capability identities include exact dependency versions. |
| O3 | Passed | LocalWorksets centrally validates concrete nonempty isbits record rows and every StructArray component's type, shape, strides, backend, device, access and alias behavior. Preparation records the complete facts; warm submission uses generated exact-leaf identity/type/rank/shape checks for the qualified stable-layout Array/MtlArray leaves. Preparation constructs/caches no-copy component views. Generated publication performs explicit leaf stores. Buffered combined/resolved workspaces also expose cached record batches. Mixed CPU/device components and cross-logical-leaf aliasing reject. |
| O4 | Passed | CorePotts owns one private seven-field `_CheckerboardCandidate` row and a no-copy StructArray over the existing authoritative arrays. K02 has one logical record port and seven physical components; K03 reads the same schema projection. Direct kernels/checkpoints keep the original component arrays and identities. |
| O5 | Passed | The existing fixed-lane algebra accepts tuples and `StaticVector{K}` through one lowering. The D2Q9 witness emits an `SVector{9}` lane bundle. Philox uses `SVector{4,UInt32}` and `SVector{2,UInt32}` internally while the tuple-facing contract and all known answers remain exact. Static vectors above the explicit 32-lane specialization budget reject; ordinary tuples remain available above that budget. |
| O6 | Passed | A centrally proved identity-route token transfers zero bytes and removes route loads. Prepared work caches its submission profile; scalar-only submissions avoid dynamic binding projection and boxed lease payloads. Owner-task proof removes a redundant host lock. A qualified CPU lane path removes the repeated functional probe. The Core adapter uses exact `invoke` in an unchanged Julia world and retains validated `invoke_in_world` for changed worlds and event draining. Task, topology, method/world, backend/device, identity, poison, capacity, bounds and alias checks remain. |
| O7 | Passed and frozen | Complete package/root CPU suites, complete qualified Metal suite, final paired CPU/Metal performance gates, exact hashes and source scans are recorded below. The fresh committee passed with P0=0 and P1=0; see [LW-5B4O-R](lw5b4o-review.md). |

One cohesion repair was made during final qualification: the generic lowering
crossed the 1,000-noncomment-line responsibility-review boundary. Shared
component-record validation/publication was extracted into
`record_storage_support.jl`; `localworksets_generic.jl` is 932 lines and the
new support unit is 112. The threshold was not raised. This does not erase the
already reviewed oversized CorePotts units: `checkerboard_program.jl` is
1,613 lines and `sequential_program.jl` is 1,279. Current source size is 9,346
noncomment lines for LocalWorksets and 23,465 for CorePotts. The two CorePotts
units and totals remain explicitly dispositioned complexity debt, not a
success metric or a reason to remove safeguards during this freeze.

## Correctness and regression evidence

| Command/profile | Result |
|---|---|
| `Pkg.test()` in `lib/LocalWorksets` | Passed complete package suite, including quality/API, external-operation, all execution families, admission piracy, lifetime/poison, `StaticVector` and StructArray tests. |
| `Pkg.test()` in `lib/CorePotts` | Passed complete package suite, including scientific oracle, Philox known answers, B2/B3/B4, queued execution, failure cuts, package quality, checkpoint continuation and replay-environment/RNG mismatch rejection. |
| Root `Pkg.test()` | **2,670/2,670 passed** in 18m40.8s. Absolute wall time is not used as hot-path evidence. The temporary test environment re-resolved compatible SciML dependencies without changing the workspace. |
| Complete qualified Metal `runtests.jl` | Passed with `Metal.allowscalar(false)`. Cross-domain LocalWorksets witnesses passed 13/13; native MTK/DiffEqGPU components passed 37/37; all checkerboard, lifecycle, failure, relationship, surface and generic LocalWorksets conformance sections completed. |

The first complete Metal attempt correctly failed closed before execution
because adding the mandatory dependencies changed the Core capability
environment digest. The remedy added only exact digest
`59a1602f9b521f627ae5ce84829b6a81fb45fc97975da8c8026d0dc50ef89fda`
to the already closed PottsToolkit Metal evidence tuple. The complete suite
then passed. No wildcard, backend claim, or external self-authorization was
added.

A later qualification attempt deliberately invoked the Metal environment with
Julia 1.10 and failed during dependency precompilation before tests because the
environment declares Julia 1.12 and its manifest was produced by Julia 1.12.6.
The qualified run used the declared Julia 1.12.6 environment. This invalid
runner attempt is preserved and is not reported as a source/test failure.

Selected Metal facts from the final run:

- B3: 12 queued MCSs, 24 proposal submissions, one final scope
  synchronization, zero intermediate waits, exact receipts and exact RNG
  trajectory.
- B4: one logical port, seven physical components, one launch per color,
  zero algorithmic workspace bytes, zero topology-transfer bytes, 19,600
  warm host-allocation bytes, direct-oracle parity, stable warm compiler
  cache, and no production promotion.
- D2Q9: `SVector{9}` lane operation plus one heterogeneous StructArray record;
  component object identity and identity-route facts passed. A deliberately
  mixed host/device StructArray was rejected before execution.
- Unreviewed external checkerboard, relationship, surface and lifecycle
  mechanisms continued to reject.

## Frozen performance evidence

The fixture, 50 paired batches, order vector, 10,000 bootstrap resamples,
seed and threshold were unchanged. The direct kernel is the O0 byte-identical
oracle.

| Backend | Direct median | LocalWorksets median | Median ratio | Paired bootstrap upper 95% | Rule | Result |
|---|---:|---:|---:|---:|---:|---|
| CPU | 0.0040234375 s | 0.0041447085 s | 1.0301411 | **1.0319632** | <= 1.05 | Pass |
| Apple M1 Pro / Metal | 0.000854583 s | 0.0008355625 s | 0.9777429 | **0.9842337** | <= 1.05 | Pass |

CPU median allocation facts were direct 17,920 bytes/60 allocations and
LocalWorksets 31,936 bytes/168 allocations for the measured batch. Metal was
196,112 bytes/2,264 allocations direct and 208,640 bytes/2,569 allocations
through the Core adapter. This is a
substantial reduction from O0's isolated 66,080-byte/403-allocation delta,
but it is not allocation parity and remains visible debt. Both paths retain
one K02 launch, zero algorithmic workspace and zero topology-transfer bytes
for the identity route.

Intermediate adverse results are preserved rather than hidden:

- O0 isolated B4 upper95 was about 1.5549;
- an intermediate CPU candidate missed the gate (about 1.064 upper bound);
- the first Metal optimization candidate missed the gate (about 1.0847 upper
  bound);
- a correct recursive warm validator re-querying every leaf's stride/device
  facts missed Metal (`upper95=1.1347952`) and was rejected in favor of the
  qualified stable-leaf invariant;
- the first exact run after the topology fix exposed stable-world Core adapter
  overhead (`upper95=1.1510607`). Four-layer attribution localized the cost
  above `LocalWorksets.run!`; the exact-invoke stable-world fast path removed
  70 allocations per CPU batch and retained the cross-world safety path;
- the exact final candidate passed on both backends as above.

Every final raw sample, the fixed order, and the rejected variants are in
[`lw5b4o-performance-raw.md`](lw5b4o-performance-raw.md).

## Dependency and compilation debt

The exact dependency probe imports StaticArrays first and then StructArrays in
one fresh CorePotts environment. These are sequential marginal diagnostics;
the second row benefits from anything shared with the first and the order must
not be interpreted as an order-independent package comparison.

| Marginal import | Seconds | Bytes | Allocations | Module delta | Method delta | Active cache bytes |
|---|---:|---:|---:|---:|---:|---:|
| StaticArrays | 0.188085459 | 13,571,584 | 246,692 | 7 | 1,956 | 521,352 |
| StructArrays after StaticArrays | 0.101709667 | 6,285,728 | 95,526 | 12 | 850 | 231,374 |

There is no historical O0 measurement produced by this exact method, so the
record does not manufacture a before/after load claim. The mandatory decision
carries measurable dependency and specialization debt, justified here by
concrete uses in both packages.

The exact Philox signature infers `SVector{4,UInt32}` and owns a Julia 1.12
`Core.MethodInstance` for the function-inclusive signature. Its CPU native
text was 4,548 bytes / 164 lines in the sealing process. Native-text hashes
are process-address-sensitive and are therefore not used as capability
identity. Real-Metal compilation evidence is the B4 cache growth 394→401 with
no further warm growth and the unrelated D2Q9 cache growth 0→20.

## Portability and ownership audit

- Portable LocalWorksets source contains no Metal, CUDA, AMDGPU, ROCm or
  scalar-indexing branch outside closed qualification metadata.
- The only provider synchronization remains one
  `KernelAbstractions.synchronize(scope.backend)` in the KernelAbstractions
  provider. Sequences depend on KernelAbstractions 0.9 implicit ordering.
- No native stream, queue, command buffer, scheduler, transferable-event
  fiction or host fallback was introduced.
- CPU and Metal are runtime-qualified. CUDA and ROCm remain unclaimed.
- LocalWorksets owns topology, output/conflict semantics, bounded lowering,
  workspace, lifetime and inspection. CorePotts still owns physics,
  Hamiltonian source-order folding, clocks, Philox addresses, proposal views,
  acceptance, settlement, checkpoints and production selection.

## Committee disposition

LW-5B4O-R independently answered the following questions with P0/P1/P2
findings and substantive dissent preserved:

1. Are mandatory StructArrays/StaticArrays integration and capability
   identities correct and honestly bounded?
2. Is component-record lowering genuinely reusable beyond CPM without hiding
   physical validation or semantics?
3. Did the CorePotts proposal schema reduce duplication while preserving all
   seven authoritative arrays, K03 meaning and scientific ownership?
4. Does K02 satisfy exact science, lifetime, launch/allocation and frozen
   CPU/Metal noninferiority requirements while remaining non-production?
5. Is corrected B3—including queued implicit ordering and exact RNG—fully
   preserved?
6. Do any present complexity, dependency-load or authoring debts block
   resuming the existing LW-5 sequence?

All three reviewers returned P0=0 and P1=0. The normalized carried P2 ledger
and complete ballots are in [LW-5B4O-R](lw5b4o-review.md). The pass does not
promote K02; it clears only this bounded optimization amendment and the return
to the existing LW-5 sequence.
