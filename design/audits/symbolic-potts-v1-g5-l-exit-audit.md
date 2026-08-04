# Symbolic Potts V1 G5-L exit audit

Date: 2026-08-04

Branch: `codex/symbolic-potts-v1`

Reviewed implementation: `e22c660e41d358aad15d3e7c92db9b627ec04c96`

Reviewed evidence boundary: `b4b2628f269017f06365756e19dc8cbe0648cdc4`

Status: **G5-L exit matrix clear; ready for, but stopped before, R2 handoff**

## Scope and authority

This audit closes the nine-item G5-L exit matrix in CCV1-027 and Section 14.2 of the accepted
lifecycle-language consolidation candidate. It does not perform or claim the later whole-G5
`R2Execution` review. The owner explicitly required work to stop before that handoff. G6 and proof
model migration remain closed.

The exact implementation was already cleared by the independent
[G5-L2Q rereview](symbolic-potts-v1-g5-l2-quality-rereview.md), with no P0--P3 findings. This audit
maps the complete G5-L exit contract to current production code, exact-candidate test results, and
the existing bounded compilation/performance report. It creates no new runtime authority, oracle,
test framework, CI gate, or freshness record.

## Exact qualification results

| Qualification | Exact result |
|---|---|
| Fast compiler/runtime profile | 469/469 assertions; 386.1 s test time, 437.34 s complete process |
| CorePotts package and bounds checks | 223 functional assertions; 10/10 Aqua assertions; 38.01 s |
| Sequential lifecycle property owner | 222/222 assertions; 554.76 s |
| Direct host/backend CPU lifecycle | selected 1; active cells 2; ownership checksum 95; 55.41 s |
| Direct SequentialEngine/CheckerboardEngine CPU lifecycle | planned parent 10.0; daughter 20.0; every scientific bank equal; 66.90 s |
| Real Metal qualification | complete green run with `Metal.allowscalar(false)`; 1,035.94 s including 46.59 s package/extension precompile |
| Independent G5-L2Q rereview | Clear; no P0, P1, P2, or P3 findings |

The Metal duration is qualification cost, not warm execution time. The accepted
[compilation/test-cost handoff](symbolic-potts-v1-lifecycle-compilation-test-cost-handoff.md)
separates package precompilation, completion/lowering, CPU compilation, Metal compilation, first
synchronized execution, and warm execution. It records a 2.94 ms warm enqueue and 0.682 ms warm
synchronization/execution for the representative lifecycle fixture.

## Required exit evidence

| # | Accepted requirement | Authoritative evidence | Disposition |
|---:|---|---|---|
| 1 | Syntax, completion, frozen closure, analysis, policies, bounds, capabilities, and negative diagnostics | The 469-assertion fast profile includes `test_lifecycle_compiler.jl` and compiler-boundary adversarial tests. It proves the five-effect taxonomy, qualified bindings, reachable frozen operation ABIs, mandatory policies, fixed capacities, inspection, and exact rejection diagnostics. | **Proven** |
| 2 | One exact CPU microfixture for all five effects and every stable built-in policy | The 222-assertion sequential owner executes Create, Remove, Retire, Transition, and Divide; every state, relationship, partition, side, conflict, inadmissibility, and extinction policy family; and the external operation family. The backend-neutral policy suite independently executes the same closed families. | **Proven** |
| 3 | Common snapshot, inadmissible-high-priority filtering, permutation, ties, capacity, reuse/allocation/generation, stale identity, and failure atomicity | Exact sequential testsets cover fixed-capacity transactions, exact-fit/overflow, request-local planned views, inadmissible competitors before priority, declaration permutation, direct conflict priority, and canonical diagnostics. Fast CPU and Metal settlement fixtures prove exact first failure, submitted/drained/committed/materialized positions, and unchanged published state. | **Proven** |
| 4 | Ownership conservation/transfer and independent tracker, relationship, and invariant recomputation | Sequential effect/policy tests inspect ownership, state, generations, relationship endpoints/incidence/payload, and trackers. Shared CPU/Metal equivalence compares every scientific bank. Surface and planned volume/surface/elongation fixtures independently recompute tracker values. | **Proven** |
| 5 | Exact RNG addresses, stream isolation, replay, replica divergence, and checkpoint continuation | Addressed daughter redraw proves stable named draws, exact replay, and changed-seed divergence. CorePotts package tests prove semantic RNG addressing and replica divergence. Fast checkpoint and sequential public-MCS tests prove exact uninterrupted continuation and reject incompatible seed/replica/engine restores. | **Proven** |
| 6 | Direct sequential/checkerboard CPU equivalence from one snapshot | The planned-tracker conformance body compiled `SequentialEngine` and `CheckerboardEngine` from one completed system, ran one successful lifecycle boundary on CPU, compared every scientific bank, and returned parent 10.0/daughter 20.0. The adversarial failure body independently passed both declaration permutations and produced byte-for-byte equal status and scientific state. | **Proven** |
| 7 | External lifecycle extension through CPU, checkpoint, inference, and real GPU | The separate `LifecycleOperationFixtures` module supplies registered trigger, placement, partition, and transform operations. Its 35-assertion sequential fixture proves adaptation, checkpoint/restore, inference, zero warm allocation, and late-failure atomicity. The same frozen operations execute on Metal and report four operations and three active cells without central compiler or executor edits. | **Proven** |
| 8 | Functional Metal execution of every effect/kernel/policy family without host semantic work | The explicit Metal profile runs the primary transaction, MCS chunking, capacity failure, canonical failure ordering, public solve/step, all state actions, volume/surface/elongation planning, eight division variants, every relationship policy, RetireAtZero, ForbidExtinction, external operations, and both conflict policies with scalar indexing disabled. | **Proven** |
| 9 | Warm allocation, bounded workspace, locality, specialization, inspection, and measured performance | Fast tests prove inferred bounded execution, the warm allocation ceiling, fixed workspace reports, and count/capacity type invariance. Existing 1/32/1,024 guards prove names, order, slots, capacities, and homogeneous descriptor counts do not create kernel families. The measured payload reduction is 6,405 to 1,003 type-description characters; combined optimized IR is 1.137x volume-only, not multiplicative. Hardware timing remains outside ordinary CI. | **Proven** |

## Source and architecture audit

- CorePotts contains no Wortel, Merks, Act, focal-point, apoptosis, mitosis, or other biological
  mechanism identity. Merks connectivity and Act remain scientific registered operations in the
  PottsToolkit operation-library layer under the accepted architecture-freeze decision; they enter
  the same frozen admission route as external operations and create no central compiler or engine
  branch.
- The old executor-inferred zero-volume retirement path is absent. `RetireAtZero` is synthesized by
  completion into an ordinary lifecycle process; `ForbidExtinction` is a compiler-synthesized
  constraint. The exact CorePotts test proves the executor does not infer an undeclared extinction
  mechanism.
- Lifecycle plan construction may use ordinary host `push!`/`append!`, but runtime cell, request,
  relationship, state, tracker, status, rank, scan, partition, and staging storage is allocated to
  fixed capacity before execution. No lifecycle runtime file calls `resize!`.
- Sequential and checkerboard consume one immutable `LifecycleExecutionPlan`. Host execution and
  backend execution share request emission, canonical keys, validation, conflict, allocation,
  state/relationship rules, status, and publication contracts; there is no second scientific
  lifecycle executor.
- The only production `KernelAbstractions.synchronize` in CorePotts or PottsToolkit is the common
  settlement authority in `program_settlement.jl`. Lifecycle kernels perform no `Array`/`collect`
  materialization, status polling, or per-stage host synchronization.
- A case-insensitive inventory of `src/`, `lib/CorePotts/src/`, `test/`, and `lib/CorePotts/test/`
  contains no G5/L2/L3/L4/L5/R2 or numbered-phase artifact in executable identifiers or filenames.
- No speculative `@static`, `@generated`, `@nospecialize`, or function-barrier change was used to
  obtain qualification. Remaining complete-state kernel arguments are measurement-only candidates
  unless a kernel-specific ABI, specialization, or compilation regression is demonstrated.

## Test-profile disposition

No accepted guarantee was removed. The fast profile owns compiler legality, deterministic CPU
semantics, failure atomicity, inference/allocation, and checkpointing. The sequential property file
owns the dense lifecycle policy/property matrix. The real Metal suite is an explicit backend
qualification profile, not an everyday test. The specialization-growth script remains an explicit
compiler qualification. This preserves a one-to-one guarantee map without putting cold hardware,
long statistical, or repeated package-wide qualification into ordinary CI.

## Exit and stop boundary

All nine G5-L exit requirements are proven on the current implementation. G5-L0, G5-L1, G5-L2,
the amended backend-resident G5-L2Q, G5-L3, G5-L4, and the pre-R2 G5-L5 qualification obligations
are complete.

The next authorized review would be one fresh `R2Execution` over the complete G5 surface,
relationships, lifecycle, concurrency, GPU, checkpoint, external-extension, and no-fallback
boundary. It is deliberately **not launched here**. Whole G5 therefore remains open at its R2
review boundary, while the narrower G5-L implementation objective is complete. G6, Wortel/Merks
migration, focal-point/Act reconstruction, polished documentation, and new lifecycle vocabulary
remain unauthorized.
