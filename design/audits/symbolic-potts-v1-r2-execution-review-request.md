# Symbolic Potts V1 R2 execution review request

Date: 2026-08-04

Branch: `codex/symbolic-potts-v1`

Candidate: the exact clean commit containing this request, supplied separately to the reviewer

Implementation boundary: production last changed at
`e22c660e41d358aad15d3e7c92db9b627ec04c96`; later commits record read-only qualification and
handoff evidence only

Status: fresh whole-G5 `R2Execution` review requested; G6 remains closed

## Review authority and restraint

Review the whole G5 execution boundary against
`spec/symbolic-potts-v1-compiler-construction.md`, the accepted lifecycle consolidation in
`design/audits/symbolic-potts-v1-lifecycle-language-consolidation-candidate.md`, the architecture
freeze, the surviving `symbolic-potts-v1-g5-l-exit-audit.md`, and the final
`symbolic-potts-v1-r2-execution-review.md`. The former execution-control and asynchronous-review
records remain reproducible at parent commit `3591eccd` as
`design/audits/symbolic-potts-v1-execution-control-audit.md` and
`design/audits/symbolic-potts-v1-asynchronous-execution-settlement-review.md`; they are historical
inputs, not required living status files. Treat every claim below as a hypothesis. Inspect
production and tests and remain read-only.

The reviewer did not author this slice. A blocking finding must cite the exact normative clause,
smallest production location, reproducer or static proof, violated invariant, and earliest repair
gate. Do not expand V1, weaken an accepted invariant, request another evidence system, or turn a
timing observation into a correctness requirement.

R2 clears only with zero P0 and zero P1 findings. If it clears, work stops before G6 for owner
review. If it does not clear, only confirmed blockers return to their earliest owning boundary.

## Exact scope

R2 owns:

- compiler-derived footprints and verified checkerboard plans;
- evaluation, claims, canonical conflict winners, deterministic commit, and attempts-per-site;
- generic tracker and surface support, independent reconstruction, and concurrent updates;
- incident-local relationship reads and atomic bounded relationship transactions;
- fixed-capacity lifecycle requests, deterministic conflicts, allocation/generation, immutable
  validation snapshots, staged publication, failure atomicity, and canonical device failure;
- backend adaptation, real-GPU legality, no host fallback, and one settlement authority;
- exact replay and checkpoint continuation;
- external descriptors, trackers, operations, relationships, and lifecycle operations receiving
  the same CPU/GPU/inference/diagnostic treatment without central executor edits;
- hardcoded scientific-policy leakage, code and test DRYness, and ordinary-versus-qualification
  test ownership; and
- the retained R1/R1.5 compiler invariants: one production evaluator route, representation-derived
  banks, qualified identities, inference, warm allocation, generated-code growth, and structural
  specialization.

R2 does not own G6 public-integration expansion, proof-model migration, Wortel/Merks/Act scientific
qualification, documentation, new lifecycle vocabulary, or a broad compiler refactor.

## Prior R2 findings that must be re-audited

Do not assume earlier repairs remain sound. Recheck that:

1. footprint analysis is closed, compositional, anchor-aware, and distinguishes shared reads,
   commutative updates, and exclusive writes;
2. `CheckerboardPlan` shape, periodicity, realized colors, and owned storage are bound to the
   compiled program and cannot be forged or mutated through caller-owned arrays;
3. proposal evaluation precedes claims, so a rejected high-priority proposal cannot suppress a
   lower-priority admissible conflict;
4. actual launch workgroup sizes and `W-1/W/W+1` ndranges are qualified with scalar device indexing
   disabled;
5. external tracker admission uses a typed bounded contract and an independent recomputation
   oracle rather than an arbitrary inspection tuple or full-storage mutation access;
6. relationship queries are incident-local and accepted-copy failure policies preserve ownership
   and atomic publication;
7. the authoritative nonempty exclusive-footprint-to-color test exercises the production conflict
   reducer and proves collision freedom and order independence; and
8. names, declaration order, capacities, slots, parameter values, and homogeneous descriptor
   counts do not create unnecessary program or kernel families.

## Lifecycle additions since the previous R2 candidate

Challenge these claims:

- CorePotts executes a closed typed lifecycle transaction language, not named biological
  mechanisms.
- Cell and relationship storage are fixed-capacity on CPU and GPU; runtime execution never resizes.
- Sequential and KernelAbstractions paths consume one immutable `LifecycleExecutionPlan` and share
  request emission, canonical keys, validation, conflict, allocation, state/relationship rules,
  status, and publication contracts.
- Lifecycle work remains backend-resident. Kernels do not poll, materialize, or synchronize on the
  host. The only production `KernelAbstractions.synchronize` is the common settlement authority in
  `lib/CorePotts/src/execution/program_settlement.jl`.
- Submitted, drained, committed, and materialized positions remain distinct. Capacity exhaustion
  and evaluator failure are sticky device statuses; later queued work becomes inert; settlement
  reports the exact failing MCS and SciML-facing typed failure without later mutation.
- Canonical first failure is selected by canonical request order and canonical state-rule order,
  never kernel launch order.
- All five effects and admitted policies, including external trigger/placement/partition/state
  operations, execute through the same CPU and real-Metal boundary.
- The public lifecycle path has no special host executor hidden behind adaptable storage.

The independent G5-L2Q rereview at
`design/audits/symbolic-potts-v1-g5-l2-quality-rereview.md` cleared its narrower boundary with no
findings. It is evidence, not authority for this wider R2 verdict.

## Compilation and test-cost evidence

Use `design/audits/symbolic-potts-v1-lifecycle-compilation-test-cost-handoff.md` as the detailed
measurement record. Do not restart the investigation or propose annotations without a new failing
measurement.

### Cold and warm boundaries

| Boundary | Cold observation | Warm observation |
|---|---:|---:|
| CorePotts source-change precompile | 2.733 s | already-precompiled load is part of the 5.58 s package load observation |
| PottsToolkit source-change precompile | 39.947 s | already-precompiled `using PottsToolkit`: 5.58 s fresh-process wall |
| Metal extension source-change precompile | 6.773 s | reused in the same process |
| symbolic completion, four evaluator shapes | 0.517--7.565 s each | 8.6--11.2 ms each |
| compile/lower, four evaluator shapes | 2.523--10.937 s each | 41.5--84.5 ms each |
| initialization | 0.605--0.724 s | 0.041--0.098 ms |
| combined Metal lifecycle enqueue | 22.232 s including first backend compilation | 2.94 ms |
| explicit Metal settlement/execution | 3.13 ms first | 0.682 ms repeated |

The 469-assertion fast profile took 386.1 seconds of test time and 437.34 seconds process wall. Its
compiler-boundary and lifecycle-compiler owners account for 210.6 seconds. The real Metal profile
took 1,035.94 seconds including 46.59 seconds of source-change precompilation and many distinct cold
program/kernel families. It is explicit backend qualification, not an everyday test.

### Structural specialization and generated code

| Evaluator structure | tracker entries | reduced payload chars | evaluator-plan chars | optimized typed IR bytes |
|---|---:|---:|---:|---:|
| volume | 2 | 850 | 2,492 | 13,420 |
| surface | 3 | 1,003 | 2,724 | 13,820 |
| elongation | 2 | 850 | 2,508 | 13,436 |
| combined | 3 | 1,003 | 4,156 | 15,252 |

These are four intentional state-stage signatures for four reachable evaluator structures. The
combined typed IR is 1.137 times volume-only, not the product of the component sizes. The broad
policy fixture has six lifecycle descriptors, 43 evaluator slots, 36 state rules, 11 admitted
actions, 12 reachable effect/action pairs, and one reachable division variant. Reachability, action
diversity, effect diversity, and tracker representation may create structural families; occurrence
count and names must not.

The reduced state-kernel payload is the established architectural direction: the representative
complete-state type description was 6,405 characters and the reduced runtime type is 1,003. Audit
the remaining complete-state kernel arguments, but do not recommend rewriting one unless a concrete
signature, ABI, generated-code, or backend-compilation measurement attributes material cost to it.

Permanent guards already cover renamed/reordered declarations, representation-derived handles,
value-level slots and capacities, parameter-only changes, and 1/32/1,024 homogeneous descriptor
growth. The reviewer should verify the guards are authoritative and that the lifecycle additions do
not bypass them.

## Guarantee-to-test map

| Guarantee | Cheapest authoritative owner | Independent expensive owner retained |
|---|---|---|
| inference and warm allocation | focused lifecycle enqueue/compiler microfixtures | explicit compiler qualification and real backend execution |
| specialization and generated-code growth | count/capacity and renamed/reordered structural microfixtures | `scripts/qualify_specialization_growth.jl` |
| external extensibility | descriptor/tracker/lifecycle compiler fixtures | shared CPU and real-Metal conformance |
| deterministic claims, winners, and replay | sequential and CPU checkerboard fixtures | Metal conformance |
| canonical first failure | two-request cross-action microfixture | same backend-neutral fixture on CPU KA and Metal |
| failure atomicity and exact failure MCS | lifecycle settlement microfixtures | public SciML boundary and Metal capacity failure |
| checkpoint continuation | focused checkpoint fixture | lifecycle settlement/checkpoint integration |
| generic surface/tracker correctness | independent recomputation microfixture | combined lifecycle tracker Metal fixture |
| relationship locality and atomicity | focused incident/transaction fixtures | checkerboard CPU and Metal read conformance |
| CPU scientific semantics | ordinary package tests and shared CPU bodies | backend-neutral conformance reused by Metal |
| real GPU correctness/no fallback | no CPU substitute | explicit Metal qualification with scalar indexing disabled |

No test may be removed unless its exact guarantee remains with an equally strong authoritative
owner. Candidate cost reductions are limited to sharing immutable completed/compiled fixtures,
removing repeated compilation of structurally identical fixtures, and replacing redundant
cross-products with orthogonal microfixtures. Mutable runtimes, workspaces, registries, and
independent recomputation oracles must remain isolated.

The reviewer must classify proposals as:

- essential before R2 clearance;
- measurement-only additions;
- explicit qualification that stays outside everyday testing; or
- rejected complexity.

## Source and payload audit questions

1. Does every production symbolic expression still reach exactly one concrete callable evaluator
   through the frozen closure?
2. Do any compiler or CorePotts types, fields, dispatches, capability flags, or branches privilege a
   biological mechanism rather than a generic primitive?
3. Are constraints, Hamiltonians, drives, trackers, relationship policies, lifecycle effects, and
   neighborhoods compiled around generic primitives rather than hardcoded into the engine?
4. Is lifecycle retirement compiler-synthesized (`RetireAtZero`/`ForbidExtinction`) rather than
   inferred by the executor?
5. Are all runtime cell, relationship, request, mask, rank, tracker, and staging buffers fixed
   capacity, with graceful deterministic exhaustion?
6. Does any kernel receive the complete program or complete execution state unnecessarily, and is
   there measured evidence that this creates a harmful family or ABI?
7. Do kernel families scale with reachable evaluator/action/effect/tracker structure rather than
   names, order, slots, capacities, or homogeneous occurrence counts?
8. Is all GPU lifecycle scientific work performed by backend kernels without host scalar indexing,
   hidden `Array`/`collect`, or per-stage settlement?
9. Does one settlement authority own synchronization, status translation, counters,
   materialization, and host-visible failure semantics?
10. Do the fast and Core suites retain every exact guarantee while keeping the 11-minute Metal run
    in explicit backend qualification?
11. Are there duplicated equivalent fixture completions or compiler cross-products that can be
    reduced without losing an independent oracle, backend witness, or adversarial condition?
12. Is the remaining latency architectural, or expected cold Julia/Metal compilation for the
    intentionally distinct structural programs?

## Existing exact-candidate evidence

- fast profile: 469/469 assertions, 386.1 s test time, 437.34 s process wall;
- CorePotts: 223 functional assertions and Aqua 10/10, 38.01 s process wall;
- sequential lifecycle property owner: 222/222, 554.76 s;
- direct host/backend CPU lifecycle: one selected request, two active cells, checksum 95;
- true sequential/checkerboard planned-tracker CPU equivalence: parent 10.0, daughter 20.0, every
  scientific bank equal;
- real Metal qualification: green with `Metal.allowscalar(false)`, including all lifecycle effects
  and policies, relationships, asynchronous settlement, capacity and canonical failure, public
  execution, and external operations; and
- clean source audit: no runtime resizing, one production synchronization authority, no numbered
  planning artifacts in production or tests, and no speculative compiler annotation introduced by
  this investigation.

The implementation did not change after these runs. Later commits added only the independent
review, exit audit, former implementation-control disposition, and this handoff. The deleted
historical implementation-control record remains at parent commit `3591eccd` as
`design/audits/symbolic-potts-v1-implementation-control.md`; the living post-G5 status authority is
now `design/hardening/g5h-control.md`. The reviewer may reuse expensive exact-implementation
evidence and should run focused decisive probes rather than ceremonially repeating the 17-minute
Metal suite unless a disputed backend claim requires it.

## Required verdict

Return:

1. exact reviewed commit and clean-tree proof;
2. P0--P3 findings with required citations and reproducers;
3. disposition of every prior R2 blocker and the lifecycle claims above;
4. cold/warm, specialization, generated-code, payload, and test-cost conclusions;
5. guarantees retained by any proposed test-suite reduction;
6. essential changes versus measurement-only opportunities and explicitly rejected complexity;
7. a clear `R2 clears` or `R2 does not clear`; and
8. confirmation that no G6 or proof-model work was reviewed or authorized.
