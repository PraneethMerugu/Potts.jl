# LW-5D checkerboard-execution convergence and adoption qualification

Date: 2026-08-14

Status: **LW-5D AND LW-R3 COMPLETE; PROMOTION SEALED**

Authority:

- [post-LW-R1 roadmap](../../spec/localworksets-post-lwr1-roadmap.md);
- [LW-5C exact-candidate review](lw5c-review.md);
- [LW-5C exact qualification](lw5c-final-evidence.md); and
- [LocalWorksets V1 contract](../../spec/localworksets-v1.md).

LW-5D converges the temporary K02→K03 candidate lifecycle into one
CorePotts-owned checkerboard execution shell, qualifies that production-shaped
candidate, and promotes it after LW-R3. It migrates no additional operation
family and changes no accepted LocalWorksets architecture, lifecycle, naming,
or execution-family algebra.

## Frozen entry

The exact LW-5C source/test/project hashes in `lw5c-final-evidence.md` are the
behavioral and performance baseline. In particular, the direct K02/K03 kernel
source remains frozen at
`4c4f48bccc4afd10a292ecdaebc03e0f9260b385a9cd6ad84f4197d552e003f8`
through final paired qualification.

## Required execution shell

CorePotts owns one private concrete shell equivalent to:

```julia
struct _CheckerboardExecutionWorkspace{W,C,P}
    core::W
    claims::C
    proposal_stages::P
end
```

`W`, `C`, and `P` are concrete type parameters. There is no `Any`, abstract
field, symbol-selected hot-path branch, mutable global registry, callback, or
`getproperty` forwarding.

The admitted combinations are:

| Profile | Claims | Proposal stages | Disposition |
|---|---|---|---|
| promoted K02→K03 conjunction | direct CorePotts claims | prepared LocalWorksets sequence | production default for the exact qualified profile after LW-R3 |
| direct reference/fallback | direct CorePotts claims | frozen direct K02/K03 stages | paired oracle, legacy replay, or a disjoint supported profile |
| retained conjunctive witness | LocalWorksets two-key claims | direct proposal stages | reusable-mechanism evidence only; not combined with the promoted stages |

No supported LW-5D selector or reconstruction path admits simultaneous
LocalWorksets claim and proposal-stage mechanisms because their combined
lease/completion contract has not been reviewed. The fresh LW-R3 review found
that deliberately bypassing those paths with private underscored constructors
does not yet reject during preflight; adding that defensive rejection is P2
hardening debt and becomes P1 if a supported path can construct the profile.

The shell owns no science. CorePotts continues to own the color/attempt loop,
immutable color values, proposal views, canonical Hamiltonian source-order
fold, semantic RNG, acceptance, scientific failure, claims, accepted-copy
commit, trackers, lifecycle, transaction/publication cuts, checkpoints,
clocks, and settlement.

## Central selection and fallback

One CorePotts selector is used by initialization, settled backend adaptation,
and checkpoint reconstruction. The LocalWorksets proposal stages may be
selected only for the exact conjunction proved by LW-5C:

- checkerboard engine with an admitted backend/device/type capability;
- one attempt per site;
- no host `after_mcs` stage;
- no active lifecycle descriptors, evaluators, state/relationship/ownership
  rules, or lifecycle requests; an inert transaction plan may retain only the
  extinction table already read by CorePotts proposal science;
- a prepared proposal-stage descriptor/topology identity;
- descriptors admitted by the fixed read-only proposal-science ABI;
- sufficient explicit queue and per-bank lease capacity; and
- centrally inspected LocalWorksets provider/compiler/lowering evidence.

Once that conjunction is selected, preparation or admission failure rejects;
there is no silent direct fallback after selection. A disjoint program outside
the conjunction may use direct stages only if its existing CorePotts capability
admits it. Accepted-copy and host-stage coexistence must be either qualified
with the LocalWorksets proposal stages or explicitly reported as disjoint
direct fallback; support may not be removed to simplify promotion.

Backend adaptation unwraps the authoritative Core workspace, adapts its
scientific storage, and freshly prepares the selected proposal stages from the
canonical host plan. Prepared work, leases, events, and workspaces are never
adapted or transferred between providers.

## Common lifecycle requirements

The implementation must leave exactly one ordinary path for each of:

- runtime construction and execution-profile selection;
- enqueue and prelaunch complete-MCS capacity validation;
- state-bank selection, copy, lifecycle indexing, and publication;
- completion-prefix collection and one final settlement wait;
- capability/evidence construction;
- checkpoint identity construction and restoration;
- backend adaptation/repreparation; and
- inspection.

Stage-specific hooks are bounded to execution, capacity preflight, a static
zero/one/two-event completion tuple, and mechanism inspection. LocalWorksets
ordering remains two sequential KernelAbstractions launches, no intermediate
wait, and one cumulative final `waitall`. The shell is not a scheduler or
event collector.

The following temporary units must disappear or be absorbed:

- `_LocalWorksetsAdoptedCheckerboardWorkspace`;
- its separate execute, enqueue, settlement, experimental-capability,
  checkpoint, and restore lifecycle;
- duplicated execution-position, freely supplied mechanism-identity, and
  queue/lease-capacity fields;
- ordinary runtime unions enumerating the adopted candidate separately; and
- private `_localworksets_adopted_*` construction as a second runtime family.

Queue and lease capacity belong to the concrete LocalWorksets proposal-stage
object. `core.execution` is the sole mutable execution position. Mechanism
identity is derived by trusted dispatch, not caller data.

## Direct and checkpoint disposition

The frozen direct K02/K03 kernels retain three explicit roles:

1. independent paired scientific/performance oracle;
2. exact legacy direct-checkpoint replay; and
3. production fallback for a genuinely disjoint supported profile not covered
   by the promoted conjunction.

For an exact promoted profile they are not an automatic alternate after
LocalWorksets selection. Benchmarks request the direct stage strategy
explicitly through the common shell.

The promoted mechanism receives a new canonical identity; the experimental
LW-5C identity is not reused. Checkpoints record both bank lowerings,
provider/compiler, queue capacity, capability/evidence identity, RNG contract,
and compiled program identity. Public restore reconstructs Core scientific
storage and freshly prepares the recorded strategy. Cross-profile restore is
rejected. Any legacy migration is explicit and logical-state-only.

## Implementation matrix

| Gate | Required change | Evidence |
|---|---|---|
| D0 contract | freeze this matrix and exact LW-5C entry | source hashes reproduce; three-role preimplementation audit agrees on the concrete shell |
| D1 shell | introduce the concrete shell; merge enqueue, settlement, capability, checkpoint, restore, adaptation, and inspection; keep direct selected | focused direct/shell parity; deletion ledger; inference and no-`Any` audit |
| D2 candidate | use one central selector for initialization, adaptation, and restore; enable automatic LocalWorksets selection only through an internal promotion entrypoint | exact conjunction/fallback matrix; no silent fallback; no author-visible LocalWorksets vocabulary |
| D3 qualification | qualify final production-shaped candidate and freeze hashes | all rows below pass on CPU and real Metal |
| LW-R3 | fresh independent product/adoption committee; contradiction round | P0=0/P1=0 required before default-selection delta |
| promotion seal | **passed** — apply only the reviewed selector default, rerun affected/full qualification, freeze final hashes | direct is reference/fallback/replay only; docs/control atomically reconciled |

The pre-review and final promoted hashes, qualification results, and carried
P2 ledger are frozen in [the LW-5D qualification packet](lw5d-final-evidence.md).
LW-R3 passed with P0=0/P1=0 and the public/default selector now chooses the
promoted profile only for the exact admitted conjunction. Disjoint or
insufficiently qualified profiles remain explicit direct fallbacks.

## LW-5D evidence matrix

| Boundary | Required proof |
|---|---|
| science | exact proposals, contributions, dispositions, trajectory, ownership, counters, trackers, relationships, descriptor state, lifecycle and publication parity |
| Hamiltonians | `Volume`, `ContactEnergy`, `Elongation`, adversarial ordered terms, and a registered external Hamiltonian through `complete`/`mtkcompile`; no unordered LocalWorksets fold |
| RNG/replay | Philox known answers, semantic address coordinates, color/direction/priority/acceptance draws, replica/repeat isolation, uninterrupted and checkpoint continuation |
| checkpoint transition | promoted continuation, explicit direct legacy replay, cross-profile/environment/dependency rejection, no serialized/adapted prepared work |
| failure | constraint/nonfinite/zero-temperature/provider failure; prelaunch rejection does not poison; postlaunch failure poisons; failed MCS does not publish |
| lifetime | twelve queued MCSs, thirteenth prelaunch rejection, full-tail drain and reuse; immutable scalar color; no intermediate wait |
| execution | two K02→K03 launches/color, one sequence submission/color, one final synchronization, zero algorithmic workspace and fixed-topology transfer |
| portability | no vendor branch, queue, stream, command buffer, scheduler or host fallback in reusable source; CPU and exact Metal only; CUDA/ROCm unclaimed |
| performance | frozen 128×128, 10-warm/50-paired, ten-MCS, 10,000-bootstrap CPU/Metal upper-95 ≤ 1.05; consolidated versus LW-5C nonregression upper-95 ≤ 1.02 |
| allocations | no increase over LW-5C medians: CPU 1,508,896 bytes/11,500 allocations; Metal 17,986,160 bytes/263,919 allocations; preparation separate |
| specialization | no second identical-schema, changed-storage, or changed-scalar cache growth; second descriptor schedule cost reported; inferred concrete host paths and real-device compile |
| ecosystem | complete LocalWorksets, CorePotts and PottsToolkit suites, MTK/SciML integration, unchanged scientific fingerprints and Potts authoring surface |
| fallback | qualified CPU/Metal; external CPU; external Metal rejection; accepted-copy/host-stage disposition; unsupported type/backend rejection; settled adaptation/repreparation; legacy direct replay |

## Review vetoes

P0/P1 findings block LW-R3 or promotion for:

- defaulting the old wrapper without lifecycle convergence;
- removing a currently supported checkerboard profile;
- silent direct fallback after LocalWorksets selection;
- adapting/serializing prepared work, events, leases, or backend workspace;
- more than one final wait or any intermediate host wait;
- moving CorePotts science, transactions, clocks, RNG, lifecycle, checkpoint
  meaning, or settlement into LocalWorksets;
- exposing LocalWorksets construction to Potts/MTK authors;
- changing the direct oracle before paired evidence;
- widening backend or operation-family claims;
- increasing frozen allocation/throughput ceilings without a fresh veto review;
  or
- replacing the duplicate lifecycle with another policy framework.

The MethodOfLines input-field integration remains deferred and untouched.
LW-5D/LW-R3 do not open G6.
