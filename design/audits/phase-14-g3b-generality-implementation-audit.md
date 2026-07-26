# Phase 14.1 G3-B Generality and Implementation Audit

Status: generic architecture retained; revision-7 normalization implemented; assembly remains open

Date: 2026-07-25

## Executive verdict

G3-B has not made CorePotts Wang-specific. The runtime additions are generic accepted-copy,
relationship, field, cell-process, schedule, observation, and backend-adaptation mechanisms.
CorePotts runtime source contains no Wang-named type or branch, the public `PottsModel` constructor
has not gained paper-specific positional arguments, and the new process execution paths extend by
typed dispatch rather than by a central selected-model switch.

The focused revision-6 correction is implemented before complete Wang assembly. It reconciles
the contact-neighbor specification with the derived-state design, makes portable failure identity
deterministic under simultaneous heterogeneous failures, and replaces the dense adjacency matrix
with a bit-packed execution view.

Revision 7 additionally corrects the newest observation substrate before canonical assembly. The
bounded cell table now has dimension-matched coordinate columns and explicit persistent cell-slot
capacity; lossless ownership publication preserves the N-dimensional lattice shape. A
three-dimensional non-Wang fixture proves those semantics independently of the configured
fourteen-column Wang record.

The implementation entry contract and focused relationship/polarity/force files pass. The bounded
observation file passes 107/107 assertions across exact 2D publication, failure atomicity,
shape-preserving ownership, genuine 3D reuse, and restart. The complete CorePotts suite passes
3,518/3,518 assertions on Julia 1.12.6. The fail-closed G3-B closure checker remains open, as it
should: the assembled eleven-process model, full-plan resource/order/restart evidence, and
complete source-semantic studies do not yet exist.

## Generality boundary

### What is correctly generic

- Accepted ownership copies expose a staged `begin`/`prepare`/`preflight`/`commit` extension
  protocol. Dynamic relationships are one consumer; the Potts kernel contains no paper branch.
- Contact-triggered elastic relationships are configured by relation, pair policy, payload,
  activation energy, capacity, degree, and semantic RNG namespace.
- `NeighborPolarityAlignment` binds arbitrary named vector, strength, and diagnostic columns and a
  declared contact relation. It derives its finite-cell neighborhood from ownership and does not
  read a Wang object.
- `HillVectorForce` binds arbitrary named input/output columns and configurable threshold,
  exponent, magnitude, and direction. The Wang Hill law is one parameterization.
- Field/exchange reduction width comes from the execution plan. A width selected by the Wang
  assembly is not embedded in the reusable primitive.
- Coupled execution extends by typed `_execute_host_process!` and `_execute_portable_process!`
  methods. The central executor contains no selected-paper process list.
- Mutable workspaces belong to compiled runtime processes. The user-facing `PottsModel`
  constructor remains two required positional arguments plus named configuration.
- Wang identities, source MCS boundaries, exact parameters, and observation columns remain in the
  paper assembly contract and evidence. Paper-specific configuration in that layer is intended
  and is not engine specialization.

### What remains intentionally model-scoped

- The G3-B degree-four rule proves the Wang model's single admitted finite endpoint type. It does
  not claim general CC3D typed-pair degree parity.
- The elastic-link Hamiltonian proves one reusable spring law, not an open-ended relationship
  energy algebra.
- The exact fourteen-column record and target-91/271 geometry snapshots are Wang observation
  declarations. Their storage and publication mechanisms must be generic.
- Source-faithful CC3D random-neighbor behavior and portable Philox behavior are separate declared
  profiles. The portable profile does not claim bitwise replay of CC3D `std::random_shuffle`.

## Revision-6 correction results

### 1. Normalize contact-neighbor state in the specification

Original severity: high specification defect, low code risk. Status: corrected.

The earlier entry contract said Potts wrote an authoritative `contact-neighbor graph`, said
alignment read that graph, and sized the polarity workspace only as `cell_capacity`. Revision 6
now specifies that the implementation derives symmetric adjacency from the immutable post-Potts
ownership snapshot at the start of alignment. No process consumes a contact graph between Potts
and alignment, so this derived representation is semantically equivalent and avoids a second
authoritative topology that would need accepted-copy transactions, checkpointing, lifecycle
repair, and backend adaptation.

Revision 6 now:

1. remove `contact-neighbor graph` from the authoritative Potts write set;
2. state that alignment reads post-Potts ownership through its declared contact relation;
3. register contact adjacency as ephemeral, non-checkpointed process workspace;
4. define finite-cell/self/Medium exclusion, duplicate-face collapse, symmetry, and canonical
   ascending-neighbor reduction;
5. correct the workspace capacity from `cell_capacity` to its actual representation; and
6. make the entry checker reject any future return to an undeclared authoritative graph.

The accepted-copy transaction still publishes ownership, geometry, site effects, and dynamic
relationships atomically. It does not need to publish the derived alignment workspace.

### 2. Make portable failure class and identity one atomic decision

Original severity: medium correctness defect, localized code change. Status: corrected.

The earlier alignment and force kernels atomically maximized a status code while separately
minimizing the failing cell. If two cells failed with different classes, the reported class could
come from one cell and the identity from another.

The implemented repair is one packed bounded failure key, selected by atomic minimum. It orders
first by ascending cell identity and then by failure class, matching the host reference.
Commit kernels test one sentinel and host synchronization decodes one internally consistent pair.
Both processes now have simultaneous different-class failure fixtures.

This change is shared infrastructure for the two processes, not Wang-specific code.

### 3. Freeze the contact-adjacency scaling contract

Original severity: medium performance/generality risk. Status: compact path implemented.

The earlier workspace stored one `UInt32` per cell pair. The replacement stores
`cld(cell_capacity,32)` words per cell, sets neighbor bits through idempotent integer atomic OR,
and scans words/set bits in ascending identity. It preserves exact duplicate collapse and full
pair capacity while reducing storage by approximately 32 times and empty-neighbor scan work by
the same factor. The representation remains construction-time bounded and requires no declared
model-specific maximum-neighbor degree.

### 4. Update evidence credit without relaxing closure

Original severity: bookkeeping defect. Status: corrected for the new isolated evidence.

The closure ledger now credits these supported facets for both processes:

- generic declaration;
- source traceability;
- isolated sequential CPU;
- KernelAbstractions CPU execution view;
- failure atomicity, after the packed-key repair;
- completed-plan restart;
- warm host-reference allocation.

Assembled sequential behavior and order/boundary visibility remain open. The ledger should credit
only the supported isolated facets and retain those assembled facets.

## Other code work that is not a generality repair

These items are necessary for G3-B closure but do not mean the engine architecture was lost:

- instantiate the accepted generic observation reducers in the canonical Wang declaration;
- assemble the canonical eleven-process Wang plan through generic declarations;
- replace the CPU phase-wide `deepcopy` path with preallocated phase transactions or
  process-owned bounded candidates for whole-MCS zero-allocation evidence;
- run complete-plan adaptation, launch/transfer, failure, restart, and source/target-boundary
  matrices;
- complete the pinned CC3D Potts/FocalPointPlasticity and field source studies, their uncertainty
  registers and controlled fixtures, plus the RoadRunner source study and closed-form numerical
  reference; and
- produce the clean tested commit, evidence manifest, and restricted attestation diff.

The phase-wide `deepcopy` path is a resource-contract problem, not a paper-specific API problem.
It should be repaired once at the coupled executor layer and will benefit every coupled model.

## Completed correction sequence and remaining effort

1. **Revision-6 spec and checker normalization:** implemented.
2. **Packed portable failure key plus adversarial tests:** implemented.
3. **Compact bit-packed generic execution view:** implemented.
4. **Ledger/evidence reconciliation and full regression:** implemented; 3411/3411 pass.
5. **Revision-7 observation correction:** implemented with 2D and 3D focused evidence.
6. **Remaining G3-B implementation and closure:** executor allocation repair, assembly, matrices,
   and source-semantic studies are several additional focused days and are independent of these
   generality corrections.

## Final assessment

- **Engine semantic generality:** strong. No Wang runtime hierarchy, branch, or positional API
  expansion was introduced.
- **Specification/implementation agreement:** strong for the derived-contact and packed-status
  slice after revision 6.
- **Primitive correctness:** strong on focused evidence; the prior multi-failure diagnostic race
  is repaired and covered.
- **Portable design:** structurally sound; real Metal/ROCm remains G3-C, and dense-adjacency
  scalability must be bounded or redesigned.
- **Assembled-model readiness:** incomplete. The generic ingredients, including observation
  storage/publication, are mostly present, but root assembly, full-plan resource repair, and
  source-semantic evidence remain.

Revisions 6 and 7 confirm that surgical corrections were sufficient; no broad semantics redesign
was needed.
