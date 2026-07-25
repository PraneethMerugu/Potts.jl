# Phase 14 Wortel Act-CPM Vertical-Slice Evidence

Status: G2 passed on CPU, real Metal, and real ROCm; Wang gate open

Date: 2026-07-24; G2 closure updated 2026-07-25

Normative architecture:
[Phase 14 Single Semantic Kernel](../../spec/phase-14-semantic-kernel.md)

This record closes the first implementation gate after Decision 0031. It proves the reusable
Act-CPM mechanism and its semantic-kernel projections. It does **not** claim reproduction of
Wortel et al. Figure 2 or validation of the full 51-parameter/30-seed experiment. Decision 0032
preserves this CPU evidence and requires the Phase 14.1 backend-resident Metal/ROCm G2 records
before Wang may open. Both required hardware jobs and artifacts passed and were inspected on
2026-07-25, so G2 is closed. Full published-model reproduction remains Phase 14.3 evidence work.

## Source-backed semantics implemented

The CPU reference implements the Artistoo `ActivityConstraint` behavior required by the pinned
Wortel model:

1. the Act contribution is
   `lambda_act * (activity(target) - activity(source)) / MAX_ACT`;
2. site activity is reduced by the geometric mean over the site and same-cell query neighbors;
3. any zero-valued included site makes that geometric reduction zero;
4. an accepted copy whose gaining owner is a finite cell sets the recipient to `MAX_ACT`;
5. rejected, no-op, and background-gaining attempts do not activate the recipient; and
6. all activity values decay by one, saturating at zero, after the Potts attempts in each MCS.

The query relation is explicit and fingerprinted. The exact Float32 Wortel slice now preflights on
qualified Metal and ROCm backends only when its activity state, accepted-copy law, decay law,
observation scratch, ordered-launch capability, and semantic RNG contract all match the registered
profile. Other coupled GPU combinations remain unsupported before mutation.

## Single-kernel realization

`ActivityProgram` produces one `SemanticModel` containing:

- one site-owned activity `StateSpec`;
- accepted-copy, activity-bias, and decay `ProcessSpec` records;
- one ordered `PlanSpec` with Potts, decay, lifecycle, observation, and stable-boundary entries;
- one `LifecycleSpec`;
- one completed-MCS `ObservationSpec`;
- explicit activity-query `SpatialRoles`; and
- the source-budgeted sequential algorithm identity.

PottsToolkit `Act(...)` lowers to exactly this CorePotts record. Model fingerprinting, runtime
realization, coupled manifest, preflight, inspection, checkpoint compatibility, and restore all
consume or project from the same canonical model.

## Executable evidence

| Gate | Evidence |
| --- | --- |
| accepted copy updates once | `Phase 14 Wortel Act semantic-kernel vertical slice` truth table |
| rejected/no-op copies do not update | proposal-evaluation and same-owner fixtures |
| source geometric reduction and delta-H | hand-computed Moore-neighborhood fixture |
| declared decay position | complete coupled-MCS fixture; new values are at most `MAX_ACT - 1` at observation |
| direct Core/façade identity | `Level 1 Act façade canonical equivalence` |
| one-model projections | manifest and inspection equality assertions |
| persistence and exact continuation | checkpoint/restore followed by identical ownership, activity, and state fingerprint |
| device allocation identity | compiled-state realization allocates from ownership storage; state, workspace, and coupled view share one activity array |
| GPU production path | ordered Potts kernel contains Act energy and accepted-copy commit; a second backend-native kernel performs saturating decay |
| bounded observation | one device summary kernel and exactly two device-to-host scalar transfers |
| backend boundary | exact Metal/ROCm profile required; an unqualified AMDGPU capability record is rejected with unchanged state |
| real-hardware harness | `benchmark/phase14_wortel_qualification.jl` plus Metal/ROCm device-code capture scripts |
| frozen Phase 13 API | `scripts/check_phase13_api_inventory.jl` |

Verification results on Julia 1.12.6:

- CorePotts: 3005/3005 tests passed;
- PottsToolkit: 672/672 tests passed;
- focused Wortel slice: 27/27 assertions passed;
- coupled delay/event/multirate suite: 45/45 assertions passed;
- Phase 14 paper-profile qualification logic passes end-to-end on the CPU reference, including the
  geometric-energy probe, accepted/rejected/no-op trace, decay truth table, replay, and restart;
- Phase 14 architecture, repository structure, legacy containment, and Phase 13 API gates passed.

## API migration result

Registry-v1 prototype spellings are internalized. The unchanged Phase 13 inventories remain 727
CorePotts exports and 223 PottsToolkit exports. Additive Phase 14 exports are separately reviewed in
`phase-14-public-api-v2.toml`: 31 CorePotts values and four PottsToolkit values. The frozen
inventory was not regenerated around the prototype.

## G2 real-hardware closure

The Metal and ROCm jobs each run a 128×128 Float32 Act workload and archive:

- exact backend/device and source provenance;
- the device-versus-CPU geometric-energy probe;
- accepted/rejected/no-op production counts and the post-decay `{0, MAX_ACT - 1}` truth table;
- three unobserved MCS with zero recorded host synchronization, transfer, or device allocation;
- one declared observation with one synchronization and exactly two scalar transfers;
- same-backend replay and exact uninterrupted-versus-restart fingerprints;
- scientific/activity memory and synchronized warm-MCS timing; and
- backend-native device code containing both the ordered Potts/Act kernel and decay kernel.

G2 passed in [GPU Validation run 30141545845](https://github.com/PraneethMerugu/Potts.jl/actions/runs/30141545845)
at exact head `fedf56056ae166369095cf0b34ee3d79f0358fec`:

- Metal job `89635604612` passed, including the Wortel qualification and device-code capture;
- ROCm job `89635604619` passed, including the Wortel qualification and device-code capture; and
- retained artifacts `gpu-smoke-metal-dc0c6b81514231a905b1432bd3e06fc57a0e7b1f` and
  `gpu-smoke-rocm-dc0c6b81514231a905b1432bd3e06fc57a0e7b1f` were inspected.

This closes the Decision 0032 prerequisite and opens the Wang slice. It does not qualify any Wang
capability or broaden the bounded Wortel profile.

## Remaining published-model work

The reusable capability slice is separate from the full paper reproduction.

The published-model deliverable separately needs the paper-faithful model document, the pinned
150×150 setup and burn-in/runtime protocol, trajectory observations using the existing moment
tracker, the registered 51 parameter pairs and 30 seeds, analysis code, and preregistered Figure 2
validation. Those are Phase 14.3 reproduction/evidence work, not missing Act semantics.
