# K09 gated state-copy cleanup and adoption plan

Status: **K09-R1 complete; corrected direct path sealed; K09-2/K09-3 rejected**  
Date: 2026-08-15  
Authority: [post-LW-R1 roadmap](../../spec/localworksets-post-lwr1-roadmap.md),
[K01/K09/L01 suitability audit](k01-k09-l01-suitability-audit.md)

Final disposition: [K09-R0 census and admission](k09-r0-census-and-admission.md)
and [K09-R1 review](k09-r1-review.md). K09-1 found that supported CPU
relationship storage requires a specialized direct field-wise copy unit and
cannot satisfy the current LocalWorksets independent-output binding profile.
The stop condition fired before K09-2; no K09-3 candidate was built.

## Purpose and boundary

K09 is reopened as one separately reviewed post-simplification operation. This
does not reopen the LocalWorksets architecture, LW-5C, LW-5D, LW-R3, K01, L01,
or another operation family.

K09 contains three mechanically related but semantically distinct paths:

1. the genuine pre-MCS copy from the active checkerboard state bank into the
   inactive transaction bank;
2. two selected-gated lifecycle state copies that are physical self-copies on
   supported checkerboard constructions; and
3. the conditional lifecycle scan-tail array copy.

Only path 1 may become a LocalWorksets adoption candidate. Path 2 must first be
proved and deleted directly. Path 3 remains a direct CorePotts scan mechanic.

CorePotts continues to own bank choice, transaction placement, program and
lifecycle state, publication, settlement, checkpoint meaning, and capability
selection. KernelAbstractions continues to own portable launch execution and
implicit ordering. LocalWorksets may own only the validated grouped independent
copy mechanics, concrete preparation, lifetime, and inspection.

## Frozen order

```text
K09-0 direct alias correction -> K09-R0 corrected direct baseline
  -> K09-1 schema/capacity census and admission ledger
  -> K09-2 exact grouped-copy design
  -> K09-3 disposable production-shaped candidate (only if admitted)
  -> K09-R1 fresh adoption review
```

No later step begins early. A failed step retains the corrected direct path and
closes K09 without opening another family or LocalWorksets mechanism.

## K09-0 — direct alias correction

### Required change

Prove the centrally constructed/adapted checkerboard invariant for both banks:

```text
lifecycle_workspace.staged_ownership        === state.ownership
lifecycle_workspace.staged_cell_kinds       === state.cell_kinds
lifecycle_workspace.staged_cell_generations === state.cell_generations
lifecycle_workspace.staged_trackers         === state.trackers
lifecycle_workspace.staged_relationships    === state.relationships
lifecycle_workspace.staged_descriptor_state === state.descriptor_state
```

Primary and alternate science leaves must remain mutually disjoint. The
constructor must reject a lifecycle bank that violates the invariant rather
than relying only on tests or permitting a forged private alternate state.

After the invariant is executable, remove only the unused `staged_state` tuple,
the two selected-gated recursive copy calls, and their obsolete debug markers
from `enqueue_lifecycle_backend_index!`. Do not remove the gated array kernel,
the genuine pre-MCS state recursion, or the scan-tail copy.

### K09-0 evidence

- CPU and adapted real-Metal structural identity for both banks;
- tracker, `CellMomentsState`, relationship fixed/payload, and descriptor-bank
  coverage;
- primary/alternate disjointness;
- no-, inert-, and active-lifecycle construction;
- due false, due true/selected zero, selected nonzero, sticky failure, abort,
  receipt, continuation, and checkpoint/replay coverage;
- no new wait or synchronization;
- exactly `2U` launches removed per active-lifecycle MCS; and
- no scientific, RNG, failure, publication, or checkpoint change.

## K09-R0 — corrected direct baseline

Freeze the exact post-cleanup source, tests, environments, and evidence before
measuring LocalWorksets. Record:

- physical state-leaf count `P` and direct copy-unit count `U` for every
  benchmark schema;
- direct pre-MCS launches `U` and scan-tail `delta` separately; unpacked CPU
  relationship records are one field-wise copy unit containing multiple
  physical leaves, so `P == U` is not assumed;
- complete-MCS launch and synchronization counts;
- warm submit and submit-plus-settle allocations;
- topology and lifecycle transfer accounting;
- twelve queued MCS settlement behavior;
- CPU and real-Metal throughput; and
- capability/checkpoint identities and mismatch rejection.

The removed `2U` self-copy launches and 16 source lines are booked exclusively
to K09-0 and can never be counted as LocalWorksets adoption credit.

## K09-1 — schema and capacity census

For minimal, tracker-heavy, relationship-heavy, descriptor-heavy, and combined
programs, census both the genuine inter-bank physical leaves and the direct
copy units without changing production execution. Record for each leaf/unit:

- stable semantic path/name;
- element type;
- axes and item count;
- backend and address space;
- source/destination alias and bank identity; and
- exact capacity-group membership.

Let `g` be the number of groups with identical item domains that are safe to
copy in one heterogeneous independent launch. Admission requires a material
`U -> g` launch reduction on representative lifecycle-rich programs. A
physical leaf is not automatically an admissible LocalWorksets output: its
storage and value types must pass the reviewed backend binding profile. If
`g` approaches `U`, or any supported copy unit requires a retained direct
fallback, K09 closes direct.

The census must also prove that stable named read/output tuples can be derived
without a new generated-schema framework, per-program handwritten adapter, or
CorePotts-specific LocalWorksets API.

## K09-2 — exact grouped-copy design

If K09-1 passes, define one LocalWork per admitted capacity group:

- one corresponding source read and named independent output per leaf;
- exact full-coverage identity routes with zero topology payload/transfer;
- one shared lifecycle-open read/mask;
- zero algorithmic workspace;
- concrete CPU/Metal-compatible static dispatch; and
- CorePotts-owned submission-time source/destination bank binding.

`NoLifecycleWorkspace` makes the lifecycle-open gate unconditionally true.
Inert and active lifecycle use the existing lifecycle status. The copy must not
silently acquire the checkerboard proposal program-open gate or otherwise alter
the direct K09 gate.

The works are independent preparations, not one public `sequence`: grouping is
by compatible item domain, while CorePotts owns phase placement. The design may
not add a prefix-identity route, new execution family, hidden synchronization,
event scheduler, dynamic lease growth, vendor branch, or explicit Metal path.

Before implementation, freeze:

- output/read port names and types;
- group count and launches;
- preparation and submission binding shapes;
- required lease capacity for twelve queued MCSs;
- one-scope completion-event aggregation;
- inspection and evidence shape;
- mechanism, capability, and checkpoint identity; and
- an implementation/deletion matrix mapping every new type/function to tests
  and the old recursive machinery it can replace.

## K09-3 — disposable production-shaped candidate

The candidate is private, fail-closed, and non-default until K09-R1. It must
compose with both direct and promoted K02/K03 claim/proposal profiles and with
no-, inert-, and active-lifecycle profiles. Unsupported schemas, types,
backends, aliases, epochs, storage, workspaces, lease capacity, and compiler
identities must reject before launch.

Required evidence:

| Dimension | Requirement |
|---|---|
| semantics | exact destination-bank leaves and unchanged active bank before publication |
| gates | lifecycle open/closed parity, including unconditional no-lifecycle open |
| ordering | KernelAbstractions implicit ordering; no intermediate host wait |
| queueing | twelve MCSs preflight completely; one final same-scope synchronization |
| lifetime | every preparation retains arrays/workspace through the cumulative event and releases the complete tail |
| failure | prelaunch rejection does not poison; backend failure poisons at synchronization boundary |
| topology | identity tokens only; zero topology payload and transfer |
| workspace | zero algorithmic device workspace; preparation/lease memory reported separately |
| compilation | first and second warm CPU/Metal compile-cache and host-allocation evidence |
| performance | paired CPU and real-Metal comparison against frozen K09-R0 |
| inspection | exact groups, ports, lowering, launches, provider/compiler, leases, and qualification |
| checkpoints | exact new execution identity and direct/candidate mismatch rejection |
| source | old state-specific recursion is deleted in the candidate disposition, not retained in parallel |

The scan-tail copy remains direct and its array kernel/wrapper remains honestly
live. K09-3 cannot claim deletion of the whole gated-copy family.

## K09-R1 — fresh adoption review

K09-R1 reviews the exact candidate and corrected direct oracle. Independent
review must cover:

1. CorePotts lifecycle/transaction/checkpoint preservation;
2. LocalWorksets API and package-boundary integrity;
3. JuliaGPU compilation, ordering, allocation, launch, and real-Metal evidence;
4. source consolidation and maintainability; and
5. capability identity, fail-closed admission, and replay.

The contradiction round must attempt to show that a smaller direct grouped-copy
kernel would be clearer or faster than the LocalWorksets candidate.

Production adoption passes only if all are true:

- P0=0 and P1=0;
- `U -> g` is material on representative schemas;
- the state-specific recursive block (211 raw / 201 executable lines at the
  opening audit) is actually removed;
- the complete production delta, including schema projection, preparation,
  settlement, adaptation, capability, checkpoint, and inspection, produces
  material net source reduction;
- CPU and real-Metal behavior and performance are noninferior under the frozen
  protocol;
- no new LocalWorksets family/API was admitted for this operation;
- no safety, determinism, alias, evidence, or qualification rule was weakened;
  and
- the result makes the CorePotts operation materially smaller and clearer.

Otherwise K09-R1 rejects adoption, removes the disposable candidate, and seals
the corrected direct path. Rejection is a successful completion of this gate,
not authority to tune thresholds or open K01, L01, or another operation.

## Immediate stop conditions

Stop and retain direct execution if any of the following occurs:

- the supported construction/adaptation alias invariant is false;
- self-copy removal changes scientific or transactional results;
- K09-1 finds no material grouping;
- grouping requires dense routes, a new route type, or a new execution family;
- event/lease aggregation requires a general CorePotts scheduler;
- the candidate retains the old recursion beside the new implementation;
- the final source ledger is non-negative or creates a larger operation adapter;
- CPU or real-Metal qualification/performance fails; or
- checkpoint/capability identity cannot distinguish the candidate exactly.
