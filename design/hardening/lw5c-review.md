# LW-5C exact-candidate committee review

Date: 2026-08-14

Status: **PASS; BOUNDED NON-DEFAULT CANDIDATE FROZEN**

Authority:

- [LW-5C bounded adoption matrix](lw5c-adoption-matrix.md);
- [exact-candidate qualification](lw5c-final-evidence.md);
- [consolidation ledger](lw5c-consolidation-ledger.md); and
- [paired performance evidence](lw5c-performance-evidence.md).

This review asks only whether the exact K02→K03 candidate is a correct,
bounded and worthwhile CorePotts adoption of LocalWorksets. It is not LW-R3,
does not promote the candidate to the public/default engine, and does not open
LW-5D, G6, or another operation family.

## Sealed candidate

| Surface | SHA-256 |
|---|---|
| `lib/LocalWorksets/src` | `bc2f1a66f6499b90da4503a2e7590e1dc359b1ecd34130df2a5cfc040649c4bf` |
| `lib/LocalWorksets/test` | `55bc71385481a032b821afce7d969fce624c8d2e5d5f5795243a215553188b72` |
| `lib/CorePotts/src` | `9071650dfd9e1ed988e9fdc34b64faf15b2cb71fd0267457126e83a52cb54057` |
| `lib/CorePotts/test` | `f12e69598e71d3ad43b48df651fdafa2e7c93ec00d39be56a2fac806bd735ecd` |
| root `src` | `c307aa522502a967bd8b060eb48e4424af28bdc7064a4fd89ae59d99aafe3ede` |
| root package-test Julia files | `7b70bd30ceadef3ee3835cfa80c2a6d83646334293281aae99ac15e369baf600` |
| witnesses plus CPU/Metal benchmark sources/environments | `7fc9fc80234cee5e27ba56be93a60575cda66a10314314d984fdde77ff6776dc` |
| root/CorePotts/LocalWorksets projects | `dff6aba68029e2a5260422239d11bd346ce84dd7fd075e287e46a7d68d1179de` / `acb0b9e2f2cf125329395bf90a210a47a8c8de6a322ea8f3e9d500af76e49033` / `a71dabb4f3bc0e38b7572d5e23826075b354f0e9d50fc2daf4be6dae371b6e4f` |

The chair completed the full exact-source CPU and real-Metal evidence before
balloting. Three reviewers then independently inspected the frozen candidate
read-only. They did not inherit the earlier B3/B4O ballots or treat recorded
hardware evidence as an independent rerun.

## Independent ballots

| Reviewer | P0 | P1 | P2 | Exact LW-5C | Default promotion | Later families |
|---|---:|---:|---:|---|---|---|
| CorePotts adapter, API and consolidation | 0 | 0 | 4 | **PASS** | **BLOCKED** | **BLOCKED** |
| JuliaGPU, KernelAbstractions and performance | 0 | 0 | 4 | **PASS** | **BLOCKED** | **BLOCKED** |
| Scientific preservation, Hamiltonians and ownership | 0 | 0 | 3 | **PASS** | **BLOCKED** | **BLOCKED** |
| Chair synthesis | **0** | **0** | **5 normalized classes** | **PASS** | **BLOCKED** | **BLOCKED** |

## Committee decisions

| Question | Decision |
|---|---|
| Correct bounded implementation | **PASS.** K02 and K03 are one centrally lowered sequence with exactly two launches per color, no intermediate wait, no algorithmic workspace and one final provider synchronization. |
| Scientific preservation | **PASS.** Exact proposal, disposition, RNG, expected-failure and checkpoint continuation evidence passes. Hamiltonian source-order folding, before/after views, acceptance, claims, transaction, publication and settlement remain CorePotts-owned. |
| KernelAbstractions ordering | **PASS.** Stage visibility uses KA 0.9 implicit launch ordering. LocalWorksets has no native queue, stream, command buffer, scheduler, fabricated event or host fallback. |
| Backend portability and qualification | **PASS, bounded.** Execution source is vendor-neutral; only CPU and the exact Apple M1/Metal environment are qualified. CUDA and ROCm remain unclaimed. |
| StructArrays/StaticArrays integration | **PASS.** Both are direct dependencies. The proposal ABI is a validated zero-copy StructArray over authoritative SoA components; Philox and fixed lanes use bounded StaticArrays while preserving public tuple behavior. |
| Deletion and second-use value | **PASS for LW-5C.** The adopted arm invokes neither direct proposal kernel; obsolete B0/B2/B3/B4 live pilots were removed; K02 reuses the K03 lifecycle and record authority with a smaller operation-specific integration. |
| Concision | **PASS WITH P2.** Matched surfaces fell from 3,406 to 1,189 lines, but the non-default candidate still carries about 339 lines of parallel lifecycle that must not become a second permanent engine. |
| Default promotion / direct oracle | **BLOCKED.** LW-R3 must merge or delete the parallel lifecycle and give the direct engine a reference-only disposition before promotion. |
| Additional operation family | **REJECT.** This result proves only K02→K03 and supplies no authority for K01, counters, trackers, accepted-copy effects, lifecycle emission or another conflict mechanism. |

## Contradiction and red-team disposition

The committee explicitly tested the favorable line-reduction claim against
the absolute retained footprint. The five principal implementation units are
1,054 physical lines and the adopted-only lifecycle/settlement branches bring
the selected/shared footprint to approximately 1,266 lines. The matched
2,217-line reduction is real, but it is not evidence that every retained line
has become permanent public architecture.

The adapter reviewer initially challenged downstream concision because the
parallel lifecycle appeared permanent. After separating the bounded
non-default LW-5C question from the later LW-R3 promotion question, that P1
was withdrawn: the current candidate passes deletion, derivation and second-
use vetoes, while permanent duplication remains forbidden. The scientific
reviewer preserves the same substantive dissent: this one safety-qualified
family does not justify admitting another family or keeping two complete
engines.

The GPU reviewer found no ordering or portability contradiction. The complete
runner's `322 -> 380 -> 380` compiler-cache counts are contextual diagnostics;
only no second warm growth is normative. First-use growth is permitted, not
required. The performance record's one-allocation arithmetic typo was
corrected to +2,381 before this seal. Raw paired samples were not required by
the frozen gate, though retaining them would improve future independent
recalculation.

## Carried P2 ledger

| P2 class | Owner | Required disposition |
|---|---|---|
| Parallel candidate lifecycle and direct oracle | LW-R3, if separately opened | Merge or delete the approximately 339-line capability/replay/checkpoint/settlement branch and make the direct engine reference-only or record another explicit disposition. Two permanent coequal engines are rejected. |
| Allocation debt | LW-R3 optimization qualification | Carry CPU +189,600 bytes/+1,273 allocations and Metal +281,440 bytes/+2,381 allocations per measured batch. Throughput passes; allocation parity is not claimed. |
| Fixed science ABI breadth | CorePotts compiler boundary | `ResourceAccess` validates and reports requirements; it does not derive a minimal device view. Do not generalize this fixed K02/K03 ABI into a later-family authoring claim. |
| Qualification provenance | Later evidence maintenance | Root replay versions are pinned, but the broader SciML stack was compatibly re-resolved. Cache counts and warm allocations are diagnostics. Preserve raw paired samples in a future promotion record where practical. |
| Documentation/status closure | This seal | Correct the cache invariant, allocation arithmetic and pre-ballot status wording atomically with this review and the control/roadmap update. **Closed here.** |

## Final ruling

LW-5C passes with P0=0 and P1=0. The exact candidate is frozen as a bounded,
private, non-default CorePotts consumer of LocalWorksets. Direct execution
remains the public/default engine. The P2 ledger is binding on any separately
authorized LW-R3; it cannot be interpreted as permission to open LW-5D.

LW-5D, LW-R3, G6, K01, counters, trackers, accepted-copy effects, lifecycle
emission, and every additional conflict or execution family remain closed.
The deferred MethodOfLines input-field integration remains deferred and is
unchanged by this review.
