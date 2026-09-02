# LW-1 implementation and semantic-portability review

Date: 2026-08-10

Status: historical PASS for the exact bounded one-key LW-1 artifact; P0=0, P1=0, P2=0

This was not LW-R1 and did not authorize checkerboard integration. The exact hashes below remain the
scope of this ballot. The current tree's separately authorized conjunctive amendment, vertical and
parity evidence are recorded in [LW-2 bounded amendment](lw2-bounded-conjunctive-amendment.md) and
[LW-3 parity evidence](lw3-localworksets-parity.md); they cannot inherit this ballot.

Authority:

- [LW-1 implementation matrix](lw1-implementation-matrix.md)
- [LW-1 semantic-portability evidence](lw1-semantic-portability-evidence.md)

## Exact reviewed candidate

| Artifact | SHA-256 |
|---|---|
| `lib/CorePotts/src/localworksets.jl` | `0503e404beab60f602b73d40a9e910a1a3b76f61804c8053cec4ebdc8bfabe73` |
| `lib/CorePotts/src/execution/localworksets_resolved.jl` | `d0a5ef0108f1bd7c7ebc702f2d45974a783643781104fe80a17b66253d91905a` |
| `lib/CorePotts/src/execution/localworksets_kernelabstractions.jl` | `baf761cd7709afa1fca38ee34935df20e1f77107831d65b4b7e4defd7c075c37` |
| `lib/CorePotts/src/execution/localworksets_evidence.jl` | `99e41b4383e604e9192f1896383a9d83562637c278ec22018d3156e996f34080` |
| `lib/CorePotts/src/CorePotts.jl` | `82ac2d99b53531a6c2182a92ff6cbac24a2dddacf556cb81731c4de5be5a581a` |
| `lib/CorePotts/test/test_localworksets.jl` | `c5eedfd1cc0c9f47ba7bbe6c6d9c9dd4abb6b9e4b244c3065931eeeca628a61d` |
| `test/backend_conformance/localworksets_execution.jl` | `194d9fc45a830d91607da0d71679101efce67c59a697b0f1fca5f1cc63a0006c` |
| `benchmark/backends/metal/runtests.jl` | `c653d31281659611f6e8a242a7aa6c43af26d175edd7e0279403c4415edbed37` |
| `ext/PottsToolkitMetalExt.jl` | `42f27a853dbde03729e13c95abdc24aac9cb7dce1c83c2c75e304211c29171b1` |
| `design/hardening/lw1-implementation-matrix.md` | `1a283f2dc164acf79af520f1abc1acf1cd0a2caa97a791189aca78b49301ff0a` |
| `design/hardening/lw1-semantic-portability-evidence.md` | `3145cda9a7d454cf56ad90212eb3e56bfa23a6fcc282234f5a8f4d8bb3552f03` |

The evidence document received a final documentation-only hash change after remeasuring the
hardened hot path. All reviewers verified that hash and retained their ballots. No reviewed source,
test, runner, extension, or matrix changed after the main ballot.

## Fresh evidence

| Evidence | Result |
|---|---|
| focused CPU LocalWorksets suite | PASS, 228/228 assertions across eleven testsets |
| complete CorePotts CPU suite | PASS, including package-quality checks; one non-fatal registry-download warning |
| focused real-Metal witness | PASS, four launches for one stage, eight for an ordered sequence, zero intermediate waits, one cumulative tail wait |
| real-Metal failure witness | PASS, production kernel raises `KernelException` at `wait` and poisons the preparation |
| complete qualified real-Metal suite | PASS, including fresh extension load orders, 37/37 native components, LocalWorksets, direct checkerboard boundaries, descriptors, relationships, surfaces, lifecycle, continuation, and rejection paths |
| source/diff audit | PASS, no whitespace errors and no vendor branch in the generic substrate, resolved lowering, or KA provider |

KernelAbstractions 0.9 implicit launch ordering is the execution contract. `run!` appends launches
asynchronously where supported. Ordered stages add no host wait or fabricated event. The first
uncovered `wait` calls `KernelAbstractions.synchronize(backend)` exactly once and drains the actual
cumulative submitted prefix. LocalWorksets creates no scheduler, native queue, stream, command
buffer, or transferable event.

## Findings closed during review

Independent review rounds found and closed the following bounded defects:

1. backend-environment and capability facts could be replaced by more-specific methods;
2. compiler and lowering evidence could be replaced after central admission;
3. topology fingerprint specialization could conceal stale routing;
4. concrete type-object dispatch could differ between capability validation and execution;
5. default lifecycle constructors permitted fabricated plans and receipts;
6. declaration named-tuple order was not canonical;
7. caller-owned workspace/runtime types could replace preparation or execution callbacks;
8. cumulative waiting of an older receipt did not originally release the entire completed tail;
9. endpoint rank evidence and exact performance measurements were incomplete or stale.

The final candidate uses exact concrete-signature method selection with centrally reviewed method
origins for topology, lowering, provider, binding, workspace, preparation, execution, inspection,
and capability paths. It rejects external callback substitution, validates receipt serials, retains
queued resources through cumulative completion, canonicalizes declaration order, and exercises
closed rank endpoints.

## Committee ballots

The committee evaluated two independent questions. A positive answer to the first neither implies
nor requires that the general library already exists:

1. Is the exact candidate a correct, bounded LW-1 implementation?
2. Does any present choice materially obstruct the eventual general LocalWorksets library?

The first question passed on the deliberately narrow implemented profile. The second found no
material obstruction, while retaining the separate work and qualification obligations below.

| Reviewer | P0 | P1 | P2 | Bounded LW-1 | Future-library obstruction |
|---|---:|---:|---:|---|---|
| JuliaGPU/backend portability | 0 | 0 | 0 | PASS | none |
| Julia API/package boundary | 0 | 0 | 0 | PASS | none; extraction coupling is mechanical/moderate |
| semantic trace and determinism | 0 | 0 | 0 | PASS | none; standalone qualification remains substantive work |

The committee separately agreed that:

- the implementation is honestly narrow: one resolved output, one destination per item, fixed
  `Int32`/`UInt32` arbitration, and exact single-device CPU/Metal qualification;
- `independent`, `combined`, heterogeneous outputs, arbitrary caller operations, and
  multi-destination claims are not implemented or implied;
- the public lifecycle leaves room for those mechanisms as separately reviewed lowerings;
- extraction requires replacing the CorePotts UUID trust root, relocating qualification evidence,
  factoring KA-specific storage/device helpers behind the provider boundary, and adding standalone
  package-boundary tests, but no lifecycle or algorithmic redesign;
- CorePotts' dual-owner conjunctive checkerboard claim is not expressible by LW-1 and may not be
  approximated as independent keyed winners.

The resulting gate ballot is therefore five separate rulings:

| Question | Ruling |
|---|---|
| exact LW-1 correctness and reviewability | PASS |
| honest narrowness | PASS |
| architectural room for independent, combined, heterogeneous, and multi-destination mechanisms | PASS; room exists, mechanisms are not implemented |
| material obstruction to eventual extraction | none; moderate factoring and standalone qualification remain |
| checkerboard/LW-2 and LW-R1 authorization | BLOCKED pending an approved bounded amendment, actual CorePotts vertical, and direct-parity qualification |

## Preserved performance dissent

The corrected 100-submission five-item diagnostics are 0.002679166 seconds and 1,850,912 host bytes
on CPU, and 0.0106173125 seconds and 2,816,288 host bytes on real Metal. These are diagnostics, not
CorePotts parity.

Exact-concrete-signature origin checks currently execute on the hot submission path. They materially
increase host overhead for tiny work. Before a performance-sensitive vertical can pass LW-3 or
LW-R1, equivalent qualification must be consolidated or cached in centrally validated plan or
preparation state without weakening fail-closed admission. This is an implementation optimization
obligation, not an LW-1 semantic or architectural failure.

## Gate ruling

The bounded one-key LW-1 implementation and semantic-portability review was complete for the exact
hashes above. This historical ruling does not authorize checkerboard migration, LW-2, LW-3, LW-4,
or claim LW-R1/direct-performance parity for any later artifact.
