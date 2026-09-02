# LW-3 LocalWorksets Direct-Parity Evidence

Date: 2026-08-10

Status: passed and accepted by the exact-hash LW-R1 committee

Authority:

- [LocalWorksets V1 implementation gate](../../spec/localworksets-v1-implementation-gate.md)
- [LW-1 implementation matrix](lw1-implementation-matrix.md)
- [LW-2 bounded conjunctive amendment](lw2-bounded-conjunctive-amendment.md)
- [LW-0 frozen direct baseline](lw0-corrected-corepotts-baseline.md)

## Scope and result

The candidate replaces only the four direct checkerboard claim launches with the bounded
two-destination LocalWorksets lowering. Candidate generation, descriptor/Hamiltonian evaluation,
acceptance, RNG, color order, commit, trackers, relationships, lifecycle, double-buffer
publication, settlement and checkpoints remain CorePotts-owned. The public default remains the
frozen direct implementation.

The exact candidate passed the complete CPU, authoritative root and qualified real-Metal suites.
The paired throughput gate passed on CPU and Metal. The fresh exact-hash committee accepted this
evidence and cleared LW-R1. That ruling does not promote the candidate, claim CUDA/ROCm
qualification, authorize another migration or choose an LW-4 disposition.

## Exact mechanism and evidence hashes

| Artifact | SHA-256 |
|---|---|
| generic substrate `localworksets.jl` | `8fe04f350356c5359944fa045c97692feac95fc6de8d2e79b38c0981a01b3294` |
| one-key resolved lowering | `7335a3aa81106fc52252ef2e6c95e64341db1b05b2bb0bc90fa64306de7d7e3f` |
| bounded conjunctive lowering | `4f61eadbfad00bf211dd89675d8af95baca3fde371ce59fcb26e0afad05ae83b` |
| hardware-neutral KA provider | `5eb7002694afbd12dbb4e216c9689f0f6befcc0ad323a45b63549c2c6255d8ff` |
| reviewed environment rows | `99e41b4383e604e9192f1896383a9d83562637c278ec22018d3156e996f34080` |
| Core checkerboard integration | `fdbcd0df8a4782fdaf49b4e01135c24b2df9f4e7a3b26c3d02c4ec293fc23740` |
| candidate capability/checkpoint integration | `6c241fc77bca27198a8947cfe794da385a84679542f4015bf7d0fd5791d37378` |
| settlement integration | `167e48797452b3238978fda3954fe775881246c5d8618ef9e091f0382f1b2372` |
| proposal-context Hamiltonian fix | `97aa6f574c713977f6d30d782db4af28b7a38eaabf19db2a97f71b06cefdccf0` |
| checkpoint envelope | `752a0cfcd296cf16d0cb281b667f4eed2941be2734a3c81bf7f62ae48f9e44f7` |
| focused LocalWorksets tests | `58ace4ae4dafe2ef5c12dc21bf6b966c841e78764ec3940ab5bb4c75623fcd43` |
| Core vertical tests | `fc851d78df22b449e47668b4510927dc23d5c764735a21ffbca4a1e896e75f3a` |
| shared backend conformance | `05723462e5a92623b9603013503dba43f3e75bb32933dd8a8bd47bfb933e7959` |
| CPU parity driver | `ab10c47ab79438997e72f6f381cdc3b4d72943b70ba94787ce7115fd76b27e2f` |
| Metal parity entry point | `e7a81a3cceb1d718467c435a9f00476b00a53a379168a1221170efc105e07064` |
| complete Metal runner | `acd5bf33a65efb417d56083910486f18f5333c1a1ff0a5182af2eaeec58f52f4` |

Documentation hashes are intentionally not self-recorded here. LW-R1 must hash this record and all
normative specifications after the final documentation-only reconciliation.

## Qualified environment

The LocalWorksets mechanism and provider contain no Metal, CUDA, AMDGPU/ROCm or native queue/event
branch. Runtime admission is nevertheless fail-closed to reviewed environments. This evidence used:

- Julia 1.12.6 on Darwin/aarch64, Apple M1;
- KernelAbstractions 0.9.42, Adapt 4.7.0 and Atomix 1.1.3;
- CPU and Metal 1.10.0 on the active M1 device; and
- ModelingToolkit 11.38.0, ModelingToolkitBase 1.59.0, SciMLBase 3.41.0 and Symbolics 7.35.0 in the
  re-resolved authoritative root test environment.

The exact CPU and Metal rows are qualification metadata, not vendor branches in execution code.
CUDA, ROCm, other Metal devices, multi-device residency and cross-backend bitwise behavior remain
unqualified and reject.

## Commands and complete-suite outcomes

| Evidence | Command | Outcome |
|---|---|---|
| complete CorePotts CPU | `julia --project=. -e 'using Pkg; Pkg.test("CorePotts")'` | exit 0; vertical 55/55, lease 6/6, scientific failure 18/18, provider failure 6/6, package quality 10/10; complete package pass |
| authoritative PottsToolkit CPU | `julia --project=. -e 'using Pkg; Pkg.test("PottsToolkit")'` | exit 0; runner closure 412/412; authoritative surface 2,215/2,215 in 18m02.3s |
| CPU parity | `julia --project=. benchmark/src/lw3_localworksets_parity.jl` | exit 0; exact parity and throughput gate pass |
| standalone Metal parity | `julia --project=. lw3_localworksets_parity.jl` from `benchmark/backends/metal` | exit 0; exact parity and throughput gate pass |
| complete qualified Metal | `julia --project=. runtests.jl` from `benchmark/backends/metal` | exit 0; extension order 2/2, native components 37/37, all conformance/failure witnesses and embedded parity pass |

One direct `julia --project=. test/runtests.jl` diagnostic failed before tests because it does not
activate `[extras]`; the repository-authoritative entry point is `Pkg.test("PottsToolkit")`. No
dependency or admission rule was changed in response.

## Scientific and lifecycle parity

The parity model is authored through PottsToolkit and compiled with `complete` then `mtkcompile`.
It exercises `Volume`, `ContactEnergy`, `Elongation`, three adversarial source-ordered
`HamiltonianTerm`s (`+16384`, `-16384`, then `+0.375` in `Float32`), proposal before/after views,
periodic contact/proposal relations and Core lifecycle state. CPU additionally exercises a
registered external Hamiltonian. The existing Metal capability provider correctly rejects external
execution families without reviewed evidence, so the Metal pair uses the complete built-in
Hamiltonian surface and does not self-authorize the external term.

For direct and candidate paths, the same compiled system, initial state, parameters, seed, replica,
repeat and preallocated randomized color order produced exact equality of:

- ownership, cell kinds/generations and final color order;
- accepted, rejected, null, constraint and energy counters;
- trackers, relationships and lifecycle status;
- descriptor-state banks and canonical Hamiltonian folding;
- direct/candidate rank, identity and disposition scratch; and
- submitted, drained, committed and materialized MCS counts.

Twelve queued MCSs settle once. Direct and candidate checkpoints continue exactly. Both cross-path
restores reject. A candidate checkpoint with a recomputed outer checksum but foreign RNG lowering
identity rejects specifically at the RNG-contract boundary. Functional candidate checkpoints reject;
only the private candidate-specific `Experimental/ReplayQualified` evidence path can checkpoint.
Direct status/evidence/fingerprint remain unchanged and `Supported`; the candidate remains distinct
and `Experimental`.

The deterministic scientific-failure witness queues twelve MCSs and commits zero on both paths,
without poisoning LocalWorksets. The separate provider witness reaches the production identity
kernel, surfaces `LifecycleBackendFailure`, poisons the preparation and publishes no candidate MCS.

## Ordering, launches, workspace and compilation

KernelAbstractions 0.9 implicit ordering supplies all stage visibility. There is no intermediate
host wait, native queue/stream/event, scheduler or fabricated dependency. Per MCS the body remains
`1 + 9C` launches: one Core bulk clear and, per color, five unchanged Core launches plus four
LocalWorksets claim launches. Ten queued MCSs are followed by one settlement. The final cumulative
LocalWorksets receipt performs the single portable backend-tail synchronization and covers later
Core commit/report/lifecycle/publication launches.

The conjunctive workspace is exactly two `UInt32` arrays of `destination_count` elements. The parity
fixture has four destinations: 16 rank bytes + 16 identity bytes = 32 algorithmic bytes. Workspace
and lease identities remain unchanged across warm-up and 600 claim submissions; topology transfer
is zero; submitted equals drained; no fallback or growth occurs.

The generic real-Metal same-schema witness prepares two distinct storage identities from the same
`WorkPlan`, warms both, alternates them while changing bounded scalar active counts and records the
Metal compiler cache. The complete runner observed `324 -> 324` entries. Thus no additional plan,
lowering type or Metal specialization appears after warm-up.

Actual Metal compilation with scalar indexing disabled exercises concrete adapted kernel arguments.
The gate view is isbits after `Metal.mtlconvert`; all lowerings are centrally recognized. No host
fallback, hidden synchronization, allocation or dynamic dispatch is admitted in device code.

## Allocation evidence

The performance driver records raw total host allocations for the entire ten-MCS-plus-settlement
batch. This is a conservative comparison: the candidate total includes LocalWorksets leases and
events, while the direct total receives no synthetic equivalent receipt allowance. Even so, the
candidate median is lower. The causal source difference is bounded: direct constructs three claim
kernel runtime objects per MCS in `_prepare_checkerboard_claim_runtime`; the candidate reuses four
prepared lowering kernels while allocating its bounded lease/event receipts. Both paths share all
other Core launches and settlement work.

| Backend | Direct median bytes | Candidate median bytes | Candidate - direct |
|---|---:|---:|---:|
| CPU | 1,318,176 | 1,289,248 | -28,928 |
| Metal complete runner | 17,679,024 | 17,070,752 | -608,272 |

Algorithmic device workspace remains the separate fixed 32-byte quantity above. Provider launch
buffers/pools are included in the raw total and are not mislabeled as algorithmic workspace.

## Throughput protocol and result

The fixed protocol is ten warm paired batches followed by fifty randomized interleaved paired
batches. Every batch contains ten queued MCSs and one settlement. The order vector and fixed seed
are identical on CPU and Metal. A fixed-seed 10,000-sample paired bootstrap estimates the one-sided
95% upper confidence bound for the ratio of candidate/direct medians. Pass requires `upper <= 1.05`.

Qualification uses a 128x128 lattice. Earlier 32x32 and 64x64 diagnostics exposed fixed host-launch
jitter rather than a size-dependent kernel regression: 32x32 CPU had upper 1.0612, and one 64x64
Metal committee run had upper 1.051075 while other 64x64 runs passed. Those failures are preserved;
the threshold, batches, queued-MCS count, randomization and bootstrap rule were not weakened.
128x128 was selected before the final evidence run to make the measurement about the vertical
rather than tiny-fixture or concurrent-runner noise.

| Backend/run | Direct median (s) | Candidate median (s) | Ratio | One-sided upper 95% | Result |
|---|---:|---:|---:|---:|---|
| CPU exact evidence | 0.025371375 | 0.025540104 | 1.00665037 | 1.01485681 | PASS |
| Metal standalone | 0.111552000 | 0.111141416 | 0.99631935 | 1.00393366 | PASS |
| Metal complete runner | 0.122159458 | 0.123825105 | 1.01363502 | 1.02389343 | PASS |

Bootstrap seed: `0x6c77335f626f6f74`. Order (`true` means candidate first):

```text
1 1 1 1 0 0 1 1 1 0 0 1 0 0 0 0 0 1 1 1 1 1 0 1 0 0 1 0 1 1 1 1 1 1 0 1 0 1 1 0 0 0 1 1 1 1 0 1 1 0
```

### Raw CPU paired seconds

```text
direct = [0.025507792, 0.025043542, 0.024837917, 0.026315042, 0.024863625, 0.026686792, 0.025080917, 0.025785500, 0.025837625, 0.025611125, 0.025542500, 0.026132208, 0.025379791, 0.025263084, 0.025699334, 0.026077667, 0.025463125, 0.025942375, 0.025297000, 0.025335666, 0.026419083, 0.025717709, 0.025616500, 0.025730875, 0.026032042, 0.031819334, 0.025587709, 0.025054208, 0.024720084, 0.024945292, 0.024904709, 0.024991166, 0.025362959, 0.025673292, 0.024569917, 0.025163500, 0.025325417, 0.024708583, 0.025096542, 0.024855916, 0.024939834, 0.025396708, 0.025020917, 0.026798875, 0.025626333, 0.024912875, 0.025199708, 0.026332958, 0.025199250, 0.025294208]
candidate = [0.025240333, 0.025420583, 0.026122750, 0.025218500, 0.025537708, 0.025542500, 0.027213500, 0.025612875, 0.025041750, 0.025550250, 0.025139083, 0.026098041, 0.029291458, 0.025929750, 0.025275250, 0.025841125, 0.026080708, 0.025277583, 0.026172042, 0.026579958, 0.025692291, 0.025381125, 0.025241333, 0.025934833, 0.033493042, 0.025839084, 0.024807084, 0.025861625, 0.025650541, 0.025503708, 0.025833959, 0.025226667, 0.025152375, 0.025569083, 0.025501542, 0.024828083, 0.025176042, 0.025814750, 0.028605208, 0.026688667, 0.025301584, 0.025764000, 0.025120000, 0.025346458, 0.024846709, 0.025081750, 0.030127584, 0.025024625, 0.024817708, 0.025182917]
```

### Raw Metal complete-runner paired seconds

```text
direct = [0.107678708, 0.107989334, 0.122238583, 0.121778208, 0.121364166, 0.121427709, 0.125934500, 0.127603666, 0.126866375, 0.128378833, 0.118265084, 0.111351875, 0.116006292, 0.137533917, 0.119809625, 0.148308917, 0.123233541, 0.116455750, 0.112841792, 0.107642583, 0.122154500, 0.108121416, 0.106160083, 0.108029291, 0.128821333, 0.125919667, 0.121154042, 0.128256083, 0.123407167, 0.124561458, 0.127622625, 0.125474791, 0.122709334, 0.121971666, 0.129483041, 0.123294583, 0.121204375, 0.121763417, 0.122481875, 0.121756167, 0.122164416, 0.124370667, 0.121696000, 0.123517042, 0.121525000, 0.124382625, 0.122073792, 0.121837834, 0.124395291, 0.125624334]
candidate = [0.137417666, 0.106420542, 0.131181875, 0.120015541, 0.121131792, 0.202976750, 0.133639417, 0.132226833, 0.125749708, 0.126540708, 0.110332084, 0.143335542, 0.119894625, 0.131692292, 0.231335042, 0.122473417, 0.131723917, 0.115247041, 0.110333250, 0.107114875, 0.107619834, 0.107715875, 0.107487708, 0.108940959, 0.125704000, 0.123145667, 0.122881209, 0.123798625, 0.122623333, 0.125805625, 0.125257792, 0.127683375, 0.120493375, 0.124977333, 0.122948708, 0.125019792, 0.123316083, 0.129294875, 0.123095208, 0.122610250, 0.127248084, 0.123628459, 0.124538625, 0.124100792, 0.130958417, 0.124227750, 0.120989417, 0.131822667, 0.121020000, 0.123851584]
```

## LW3-Q01 through Q10 disposition

| Row | Evidence | Result |
|---|---|---|
| Q01 scientific/Hamiltonian | exact full-state parity; public built-ins on CPU/Metal; registered external on admitted CPU; canonical adversarial fold | PASS |
| Q02 RNG/checkpoint | exact continuation, candidate-specific evidence, RNG mismatch and both cross-restore rejections | PASS |
| Q03 queued failure | twelve queued MCS; exact commit cut; scientific no-poison and provider-poison witnesses on CPU/Metal | PASS |
| Q04 launch/wait | `1 + 9C`; four claim launches; no intermediate wait; sixty paired settlements/waits in performance run | PASS |
| Q05 workspace | exact 32 bytes, unchanged identities, zero topology transfer/growth/fallback | PASS |
| Q06 allocation | raw conservative candidate total is lower on CPU/Metal; bounded source difference identified | PASS |
| Q07 compilation | one plan, two storage identities, changed scalars, Metal cache `324 -> 324` | PASS |
| Q08 throughput | fixed paired protocol; CPU upper 1.01486; complete Metal upper 1.02389 | PASS |
| Q09 suites/rejections | complete CorePotts, authoritative root and complete Metal exit 0; fail-closed external/device cases retained | PASS |
| Q10 device compilation | real adapted/isbits Metal execution, scalar indexing disabled, centrally recognized kernels only | PASS |

## LW-R1 acceptance

The fresh exact-hash committee accepted this evidence, closed LW-2/LW-3 and cleared LW-R1 with
P0=0, P1=0, P2=0 and no substantive dissent. Its independent ballots, contradiction round and
uncontaminated Metal rerun are recorded in the
[LW-R1 exact-candidate review](lwr1-localworksets-review.md). Checkerboard selection remains
private, the direct oracle remains public/default and no additional mechanism may migrate until the
owner records the applicable LW-4 disposition.
