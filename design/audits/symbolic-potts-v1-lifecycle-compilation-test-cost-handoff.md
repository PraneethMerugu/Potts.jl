# Lifecycle compilation and test-cost handoff

Date: 2026-08-03

Branch: `codex/symbolic-potts-v1`

Measured implementation commit: `63a3c4e58d3fb5f15fd596a6248bc8729e0c5b00`

Scope: bounded evidence for the active lifecycle architecture review. This document records
measurements and test ownership. It does not authorize another compiler refactor, remove a test,
or turn timing into an ordinary CI assertion.

## Disposition

The reduced state-kernel payload is the established architectural direction. For the representative
volume/surface/elongation division fixture, it reduced the concrete launch-runtime type description
from 6,405 to 1,003 characters, while the optimized typed IR for the combined evaluator was only
13.7% larger than the volume-only evaluator. Warm completion, lowering, initialization, enqueue,
and execution are short. The several-minute CPU and Metal profiles are dominated by cold Julia and
backend compilation of distinct fixtures, not warm model execution.

The exact candidate is not ready to clear, for one semantic reason independent of these timing
results. An independent adversarial probe found that request-local state-action failures are reduced
after every action/effect launch. A Create/Initialize failure can therefore be published before an
earlier canonical Divide/TransformDaughters failure. The sequential reference selects the canonical
request. This violates the accepted rule that request-local failures reduce in canonical request
order, never kernel launch order. The correction should remain local to state-stage status reduction
and receive an exact regression; it does not justify redesigning the evaluator or launch payload.

## Measurement boundaries

All measurements used Julia 1.12 on the current MacBook and the exact candidate above. Values are
engineering observations, not portable performance thresholds.

### Package load and precompilation

| Boundary | Observation |
|---|---:|
| PottsToolkit precompile after a source change | 39-46 s |
| CorePotts precompile after a source change | 2.8-3.1 s |
| Metal extension precompile after a source change | 7-9 s |
| already-precompiled `using PottsToolkit` in a fresh process | 5.58 s wall |
| separate `-g2` cache, including dependency-stack precompile | 286 s |

The `-g2` observation is a debug-cache/tooling cost and must not be attributed to model completion
or normal package precompilation.

### Symbolic completion, lowering, inference, and warm construction

The first row in a fresh process includes one-time Julia compilation of the completion and compiler
pipeline. Later cold rows still compile structurally new evaluator shapes. The second pass uses the
same four concrete fixture shapes in the same process.

| Reachable division evaluator | first completion | first compile/lower | first initialize | warm completion | warm compile/lower | warm initialize |
|---|---:|---:|---:|---:|---:|---:|
| volume | 7.565 s | 10.937 s | 0.723 s | 8.6 ms | 41.5 ms | 0.047 ms |
| surface | 0.703 s | 5.041 s | 0.724 s | 9.1 ms | 77.7 ms | 0.098 ms |
| elongation | 0.517 s | 2.523 s | 0.651 s | 8.8 ms | 42.7 ms | 0.047 ms |
| combined | 0.867 s | 4.530 s | 0.605 s | 11.2 ms | 84.5 ms | 0.041 ms |

Optimized `code_typed` inspection took 0.18, 0.12, 0.07, and 0.03 seconds on the first four
signatures and 0.8-0.9 milliseconds on the repeated signatures. It is inexpensive after the
relevant methods are compiled; repeatedly constructing structurally different fixtures is the
costly part.

### Real Metal boundary

The minimal combined tracker fixture was timed in one already-precompiled Metal process with scalar
device indexing disabled.

| Boundary | first | repeated in same process |
|---|---:|---:|
| symbolic completion | 13.337 s | reused completed system |
| CPU reference/checkerboard compile, initialize, and Metal adaptation | 27.570 s | 0.190 s |
| lifecycle enqueue, including first Metal kernel compilation | 22.232 s | 2.94 ms |
| explicit synchronization and completed execution | 3.13 ms | 0.682 ms |

Both runs returned `LifecycleStatusSuccess`. This separates first backend compilation from actual
warm execution: the 22-second first enqueue is compiler latency, while the completed warm
transaction is sub-millisecond at synchronization plus about three milliseconds of host enqueue
overhead for this fixture.

The complete Metal qualification took 668.15 seconds (about 11.1 minutes), with its first printed
result after about 120 seconds. It covered general checkerboard execution, surface tracking,
asynchronous settlement, sticky capacity failure, the public SciML path, the broad state-policy
fixture, the combined tracker fixture, eight division-policy variants, relationships,
retirement/extinction, external operations, and conflict behavior. It is an explicit backend
qualification profile, not an everyday test profile.

### Fast CPU profile

The already-green 426-assertion fast profile took about 6 minutes 15 seconds. A single instrumented
rerun reproduced 377.5 seconds across these owners:

| Test owner | Time | Main guarantee |
|---|---:|---|
| registered descriptor boundary | 19.87 s | external descriptor lowering, handles, concrete/adapted buffers |
| checkerboard conformance and boundary sizes | 30.69 s | CPU backend semantics, conflict accounting, boundary launch sizes |
| relationship conformance | 32.50 s | packed relationship reads and CPU/backend equality |
| surface conformance | 16.18 s | generic surface tracker/evaluator and independent tracker validation |
| asynchronous lifecycle settlement | 51.08 s | enqueue/settle counts, exact capacity failure MCS, consumers, warm allocation |
| compiler adversarial boundaries | 134.02 s | unbypassable evaluator route, qualified ownership, finite affected anchors, extension rejection |
| lifecycle compiler | 76.56 s | closed taxonomy, external operations, diagnostics, reachability, count/capacity specialization |
| checkpoint continuation | 16.49 s | exact continuation, checksum/seed/replica/engine incompatibility |

The two compiler-heavy files account for 210.6 seconds, or 55.8% of the profile. Static counts show
14 `complete`/13 `compile` calls in compiler-boundary repairs and 17 `complete`/3 `compile` calls in
the lifecycle compiler suite. Most completion calls construct distinct invalid or adversarial
programs and therefore cannot be merged merely because their syntax is similar.

The ordinary CorePotts package tests, bounds-check run, and Aqua checks are green. The bounds-check
environment precompiled in about 3.1 seconds; its test groups took about 34 seconds including about
10.8 seconds for Aqua. PottsToolkit's full package test remains the broad everyday integration
owner; the fast profile is a developer inner loop and should not be run immediately before or after
the full suite unless both signals are specifically required.

## Specialization and generated-code evidence

### Reachable evaluator and tracker structure

| Evaluator | evaluator banks | state banks | tracker entries | reduced payload chars | evaluator-plan chars | optimized typed IR bytes |
|---|---:|---:|---:|---:|---:|---:|
| volume | 5 | 3 | 2 | 850 | 2,492 | 13,420 |
| surface | 5 | 3 | 3 | 1,003 | 2,724 | 13,820 |
| elongation | 5 | 3 | 2 | 850 | 2,508 | 13,436 |
| combined | 5 | 3 | 3 | 1,003 | 4,156 | 15,252 |

These four reachable evaluator structures produce four concrete state-stage signatures. This is
intentional specialization on executable evaluator structure. The combined signature's typed IR is
1.137 times the volume-only IR, not the product of all three individual sizes.

The broad state-policy fixture reports six lifecycle descriptors, 43 evaluator slots, 36 state
rules, 11 admitted state actions, 12 reachable effect/action pairs, and one reachable division
variant. Backend orchestration launches only the pairs and division variants present in the frozen
masks. Action/effect diversity therefore creates bounded structural kernel variants; descriptor
occurrence count does not.

### Value-level growth guards already authoritative

- `test/test_lifecycle_compiler.jl` proves one versus four homogeneous lifecycle declarations and
  `max_cells = 4` versus `32` retain the same lifecycle-plan, descriptor-vector, and evaluator-store
  types. Counts and capacity change values and vector lengths only.
- `test/test_descriptor_compiler.jl` proves renamed and reversed state declarations retain the same
  representation-derived handle types; slots remain value-level; adding an earlier unrelated
  representation does not renumber the target representation type.
- The same file proves 1, 32, and 1,024 homogeneous built-in and external descriptors retain one
  kernel family and the same complete-program type; parameter-only changes do not add families.
- `scripts/qualify_specialization_growth.jl`, intentionally outside ordinary tests, extends those
  checks to 1/32/1,024 relationship stores, state/workspace layouts, handles, optimized typed IR,
  and external programs.
- Structural expression tests prove statement and anchor renaming does not alter descriptor, role,
  or evaluator-expression types.

These guards cover names, declaration order, capacities, slots, and homogeneous occurrence counts.
They should be preserved. No additional Cartesian stress matrix is warranted before a failing
structural probe exists.

### Irrelevant payload fields

The state-stage kernel no longer receives `CheckerboardExecutionState`. Its payload contains the
shape, periodicity, medium kind, tracker plan, descriptor domain resources, lifecycle relationship
rules, ownership/cell/tracker/relationship/state storage, parameters, RNG identity, MCS, the policy
workspace, lifecycle evaluators, state rules, and descriptors. It excludes checkerboard candidate,
claim, disposition, report, stage-buffer, and complete workspace state that the state evaluator does
not read. The representative combined full-state type was 6.4 times the reduced runtime type.

The evaluator payload still contains all lifecycle evaluator banks for the completed model, not a
per-action slice. Whether slicing it further reduces real backend compilation enough to justify
additional payload machinery remains a measurement hypothesis.

## Remaining complete-state kernel audit

No remaining kernel was rewritten during this audit.

Eleven lifecycle kernels still accept the complete checkerboard state: request sorting, generic
effect planning, division planning, division relationship validation, selected-division replanning,
conflict/capacity selection, structural staging, relationship staging, effect finalization, staged
validation, and request emission. Most call authoritative shared transaction functions that need
several state domains. Effect finalization appears narrower by inspection, but there is no measured
ABI, specialization, or Metal-compilation regression attributable to that argument alone.

All nine checkerboard kernels also accept complete state, including two clear kernels whose only
state dependency is sticky lifecycle status. The candidate/evaluate/commit kernels legitimately
consume broader scientific state; claim/select/report consume much less. This predates the current
lifecycle repair and already has real backend qualification. Narrowing these payloads is a
measurement-only opportunity, not a current change request.

The correct next evidence, if latency remains unacceptable after the semantic repair, is a per-kernel
Metal compilation inventory comparing concrete signatures and generated code. Source-level field
count alone is not evidence that a new wrapper improves Julia or GPU compilation.

## Guarantee-to-test ownership and safe cost options

| Guarantee | Cheapest authoritative owner | Expensive independent owner retained |
|---|---|---|
| inference and warm allocation | focused lifecycle enqueue test | explicit compiler qualification and real backend run |
| specialization growth | lifecycle count/capacity microfixture | `qualify_specialization_growth.jl` at 1/32/1,024 |
| external extensibility | descriptor/lifecycle compiler fixtures | CPU and real-GPU backend conformance |
| deterministic replay and canonical winners | sequential and CPU checkerboard fixtures | Metal conformance |
| canonical first failure | new two-request cross-action microfixture | same fixture on CPU KA and Metal |
| failure atomicity and exact failure MCS | lifecycle settlement microfixtures | public SciML and Metal capacity failure |
| checkpoint continuation | checkpoint microfixture | lifecycle checkpoint/settlement integration |
| generic surface and tracker correctness | surface microfixture with independent recomputation | combined lifecycle tracker Metal fixture |
| CPU scientific semantics | ordinary package tests | backend-neutral conformance bodies on CPU |
| real GPU correctness/no fallback | none; requires real device | explicit Metal qualification |

No test has been removed. The following reductions are safe only if implemented with the ownership
shown above:

1. Reuse one immutable completed system when the same source is compiled for sequential and
   checkerboard engines. This preserves the distinct engine fingerprints and execution checks while
   avoiding duplicate symbolic completion.
2. Reuse compiled fixtures within a test process only when every consumer treats them as immutable
   and independently initializes runtime state. Do not cache mutable integrators, workspaces, or
   registries.
3. Keep optimized-IR scale growth and 1/32/1,024 stress in the explicit compiler qualification
   script. Ordinary tests retain the small structural type guard.
4. Keep the broad 12-policy lifecycle fixture as orthogonal action/effect coverage; keep the minimal
   combined volume/surface/elongation fixture as compiler/backend qualification. Do not multiply
   every policy by every tracker expression.
5. Keep the 11-minute Metal suite explicit. A small real-Metal smoke may guard the common path, but
   it cannot replace the full qualification's division variants, failure status, relationships,
   replay, and no-fallback guarantees.

The checkpoint test's second completion of the same source exists to compile a checkerboard
executable and prove an engine fingerprint mismatch. It can reuse the already completed immutable
system without weakening that guarantee. The backend conformance helpers already complete once and
compile the same completed system for sequential and checkerboard execution where both are needed.

## Bounded recommendations

### Essential before clearance

- Restore canonical request-order reduction across all state-action/effect launches and add the
  exact two-failure sequential/KA CPU regression. Qualify the same rule on Metal.
- Rerun the focused fast/Core tests affected by that correction and the explicit Metal lifecycle
  qualification. Do not repeat unrelated compile-time experiments.
- Preserve the reduced state-kernel payload and all current structural guards.

### Measurement-only opportunities

- Record per-kernel Metal compilation and cache-family counts if latency remains material after the
  semantic repair.
- Compare a further evaluator-bank slice only against the current reduced payload on the broad and
  minimal fixtures.
- Time immutable completed/compiled fixture sharing before changing test structure.
- Audit the narrow clear/report/finalize kernels first if a complete-state ABI measurement identifies
  them as material.

### Explicitly deferred or rejected

- No speculative `@static`, generated function, function barrier, or compiler annotation.
- No whole-program payload rewrite without a measured kernel-specific regression.
- No deletion of an inference, allocation, specialization, extensibility, replay, atomicity,
  checkpoint, CPU, or real-GPU guarantee.
- No default-CI timing threshold and no attempt to make the 11-minute Metal qualification an
  everyday suite.
- No broad compiler refactor until independent review classifies the remaining latency as
  architectural rather than expected cold GPU compilation.
