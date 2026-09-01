# LW-5B2 proposal bridge evidence and bounded review

Status: **PASS**; B2 complete; isolated B3 one-for-one adoption work may
begin; production/default execution, later operation families, LW-R3 and G6
remain closed

Date: 2026-08-13

Authority:

- [LW-5A adoption-and-consolidation amendment](lw5a-adoption-consolidation-amendment.md)
- [LW-5A focused review](lw5a-adoption-consolidation-review.md)
- [LW-5B0 integration-probe review](lw5b0-integration-probe-review.md)
- [post-LW-R1 roadmap](../../spec/localworksets-post-lwr1-roadmap.md)

## Scope and ruling

LW-5B2 resolves the two implementation holds left by LW-5A: a reusable,
device-callable projection of compiled CorePotts proposal science and a
bounded, inferred return bridge for a source-count-fixed descriptor plan. The
candidate is deliberately isolated. No production checkerboard entrypoint
selects it, the direct evaluator remains the oracle, and this review does not
authorize migration of candidate generation or any later operation family.

The result corrects one premise in the provisional pilot specification. The
checkerboard contribution matrix is transient evaluator scratch: no later
stage consumes it. It is also parameterized by the native scientific scalar
(`Float64` on CPU and `Float32` on qualified Metal), whereas the frozen
LocalWorksets independent store profile does not admit `Float64`. Therefore
the honest existing-mechanism bridge is:

1. evaluate each descriptor into an inferred
   `NTuple{N,ProposalEvaluation{T}}` inside the CorePotts operation;
2. fold that tuple in canonical source order inside CorePotts; and
3. return one partial independent `UInt8` disposition emission.

This is not a hidden combined output. It removes eventual contribution
scratch instead of publishing it, keeps Hamiltonian ordering and acceptance
inside CorePotts, and requires no LocalWorksets capability amendment.

## Exact candidate

Repository base: `bc5729f3db636c936ad2dfee46c5d1f1ced56059`

| Artifact | SHA-256 |
|---|---|
| `lib/CorePotts/src/execution/descriptor_plan.jl` | `3daa3597a8a40a0dac1e90ef1572cfc01c2de44c8188fdeddf0b73c52bca6454` |
| `lib/CorePotts/src/execution/localworksets_adapter.jl` | `659ef2ac9db272e0ed3814503738555ca7518278e18481984d9b5c9903f795dc` |
| `lib/CorePotts/src/execution/localworksets_proposal_bridge.jl` | `1e0be6e82a22ac8d7e4cd0d57892501c3ae3651d34ac09864242577a0ad8d21c` |
| `lib/CorePotts/src/program/v1.jl` | `c5026e5d0879595cd2b5b04a4a01c4b1f133e83f9c9a853b98d069bdc4515344` |
| `lib/CorePotts/test/lw5b2_proposal_bridge_support.jl` | `b42c044618f62a37d234fa22e3232cdffbbf9c79685a8aa3cdbae294c8b71f20` |
| `lib/CorePotts/test/test_program_v1_localworksets_vertical.jl` | `3cb01989a6c0267e2de730b45d54af4243169e9e81e59c8724e6c1564b653465` |
| `benchmark/backends/metal/lw5b2_probe.jl` | `d14d2f0c692f64e5d005c16e28b0cd27d30e55d4d1eac8ade114fed65965f073` |
| `benchmark/backends/metal/runtests.jl` | `1c2a208a886018519371cde72cb1c025d5425ae36636e772a5fd6571045b2c11` |

The candidate is a preserved dirty-tree product containing the preceding
LW-5A/B0 work. Hashes, rather than an uncommitted tree label, identify the B2
artifacts exactly.

## Implementation map

| Obligation | Implementation | Evidence |
|---|---|---|
| fixed-size return bridge | `_proposal_contributions_tuple` and `_fold_proposal_contributions` | inferred five-source and zero-source CPU paths; real-Metal compilation |
| canonical source order | source-handle recursion and ordered tuple fold | descriptor groups deliberately stored out of order; exact role/value tuple remains source ordered |
| reusable science projection | `_ProposalEvaluationProgramView`, `_ProposalEvaluationRuntimeView`, `_ProposalEvaluationScienceRead` | one shared construction; recursive backend check; `Adapt` qualification |
| compiler-derived read evidence | `_proposal_resource_manifest` | five sorted source records; writing descriptor rejected before preparation |
| no hidden output access | `_ProposalEvaluationOperation` | operation is isbits, returns only `dispositions`, and leaves the destination unchanged when called directly |
| bounded public lowering | `_prepare_core_localwork_phase` through public LocalWorksets lifecycle | one independent port, one identity route, one launch, zero algorithmic workspace |
| domain ownership | `_proposal_result_disposition` and CorePotts tuple fold | existing failure mapping, Metropolis RNG address, extinction rule and canonical fold retained above LocalWorksets |
| asynchronous ordering | bridge launch followed directly by existing claim-priority kernel | no intermediate wait; one final `KernelAbstractions.synchronize` observes priority `73` on CPU and Metal |
| isolation | bridge preparation/run helpers have no production caller | only focused CPU and Metal probes reference them |

The operation reconstructs actionability from the proposal ABI and the
program-open gate. `dispositions` is not in its logical reads, and no output
array is captured in its callable or science projection.

## Semantic and portability evidence

The five-source fixture includes a Hamiltonian term, log-bias drive,
energy-drive term, kinetic modifier and constraint. Its descriptor groups are
intentionally ordered `(3, 1, 5, 2, 4)` while the returned tuple and fold are
canonical `(1, 2, 3, 4, 5)`. The direct checkerboard evaluator and B2 bridge
produce identical dispositions. A zero-source descriptor plan is inferred
and executes without manufacturing a contribution.

Production bridge and adapter sources contain no Metal, CUDA, AMDGPU or
vendor-array branch. Runtime qualification remains honest: CPU and Apple
M1/Metal are tested; CUDA and ROCm are not claimed. Sequential launch
visibility relies on KernelAbstractions 0.9 implicit ordering, not a private
queue, event or scheduler.

## Qualification record

| Command/profile | Result |
|---|---|
| focused CorePotts vertical | **PASS**; B2 `36/36`, zero-source `3/3`, B0 `37/37`, all retained vertical groups pass |
| complete CorePotts CPU package suite | **PASS** on the exact test/source candidate, including Aqua, checkpoint continuation and RNG/mechanism mismatch rejection |
| complete qualified real-Metal suite | **PASS** on the exact executed Metal and shared-support candidate, including B0/B2, cross-domain, checkerboard, descriptor, lifecycle, relationship, MTK and checkpoint rows |
| `git diff --check` | **PASS** |
| vendor-name scan of production B2 sources | **PASS**; no matches |

Exact diagnostic records:

```text
(schema=:lw5b2_proposal_bridge_v1, backend=:cpu, sources=5,
 launches=1, waits=3, algorithmic_workspace_bytes=0,
 topology_transfer_bytes=72, warm_host_allocations=23824,
 direct_contribution_parity=true, direct_disposition_parity=true,
 inferred_source_tuple=true, implicit_ordering=true,
 hidden_output_mutation=false, production_promoted=false)

(schema=:lw5b2_proposal_bridge_v1, backend=:metal, sources=5,
 launches=1, waits=2, algorithmic_workspace_bytes=0,
 topology_transfer_bytes=72, warm_host_allocations=43824,
 compiler_cache_before=332, compiler_cache_after=339,
 direct_disposition_parity=true,
 source_ordered_native_float_tuple=true, implicit_ordering=true,
 hidden_output_mutation=false, production_promoted=false)
```

These small-fixture allocation values are diagnostics, not throughput or
production-parity claims.

## Findings and B3 holds

- **P0: 0.** No semantic corruption, hidden synchronization, vendor branch or
  production-path change was found.
- **P1: 0 for B2.** The fixed-source tuple and real-Metal device compilation
  resolve the LW-5A derivability hold without a new LocalWorksets mechanism.
- **P2/B3-1:** the single composite science read is intentionally conservative.
  B3 inspection must expose or justify leaf ownership, backend, lifetime and
  alias evidence; split it only if the one-for-one production comparison
  proves that necessary. It may not become per-model binding assembly.
- **P2/B3-2:** paired B3 evidence must account for the measured host event
  allocations and compare end-to-end launch, workspace, transfer, throughput
  and queued-MCS behavior with the frozen direct path.
- **P2/B3-3:** the 355-line isolated bridge must earn its complexity through
  deletion and cohesion in B3. If one-for-one adoption still needs a large
  second adapter, the pilot fails the LW-5 value test.

## Decision

LW-5B2 passes as an honestly narrow derivation and return-bridge proof. B3 may
now attempt an isolated one-for-one replacement of the proposal-evaluation
launch, with direct/pilot state, RNG, checkpoint, queued-ordering and
performance parity. Production/default promotion remains closed until that
comparison passes its separate hold. K02 second-use construction is still
required before the decisive proposal-pilot review; no later operation family
is opened by this ruling. The deferred MethodOfLines input-field integration
is unchanged.
