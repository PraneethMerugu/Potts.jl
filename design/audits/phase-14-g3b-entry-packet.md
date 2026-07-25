# Phase 14.1 G3-B Wang Entry Packet

Status: accepted implementation entry, revision 4; fail-closed G3-B exit protocol registered

Date: 2026-07-25

Machine-readable contract:
[phase-14-g3b-entry-contract-v1.toml](phase-14-g3b-entry-contract-v1.toml)

## Decision

No further architecture interview is required before G3-B. The single semantic kernel, generic
fragment boundary, one-root-plan rule, CPU-reference role, and CPU/Metal/ROCm promotion policy are
already accepted. This packet freezes the implementation-level choices that G3-A intentionally
left structural:

- the source-backed Wang state and process inventory;
- backend-adaptable logical and physical storage;
- numerical profiles and source-runtime authority;
- exact read, write, snapshot, commit, and MCS-boundary behavior;
- conformance fixtures that must precede claims; and
- the three remaining foreign-runtime questions.

The CPU reference is an oracle for the same canonical model that will run on Metal and ROCm. It is
not permission to build CPU-owned arrays, host callbacks, a second runtime, or paper-specific
public types.

Revision 2 closed the pre-field implementation audit. In particular, it resolved the source-MCS
zero mapping, makes five field substeps internal to one atomic process, removes internal substep
checkpoints, requires two field staging grids, makes exchange mode a root-plan binding, normalizes
the shared uptake multiplier to global state, and freezes deterministic reduction and
cross-domain-publication requirements.

Revision 3 leaves those semantics unchanged and strengthens only the exit proof. It registers a
[machine-readable closure ledger](phase-14-g3b-closure-ledger-v1.toml), twelve non-substitutable
closure requirements, assembled-model evidence, all-process failure/allocation matrices,
hash-addressed foreign-runtime artifacts, exact restart rejection points, and a fail-closed claim
checker. Primitive results and KernelAbstractions CPU results remain useful increments but cannot
be promoted into a Wang, foreign-runtime, GPU, or paper-reproduction claim.

## Source time mapping

Potts.jl MCS 0 is the finalized initial condition. CompuCell3D 4.2.5 instead calls an actual
Potts/field/Python iteration `MCS 0`. Hiding that iteration in initialization would violate
normalized attempt accounting. The accepted mapping is therefore:

```text
normalized target MCS = CompuCell3D source MCS + 1
```

Source MCS `0:499` is target MCS `1:500`. `source_mcs` is an exactly derived paper-label metadata
column, not a second clock or scheduling authority. Only registered source `start()` hooks,
including the initial RoadRunner step, execute before finalized Potts.jl MCS 0.
Paper geometric labels source 90 and 270 likewise map to normalized targets 91 and 271.

## Canonical state and storage

The implementation has nine future-relevant state families:

| State | Owner | Backend-ready physical form |
| --- | --- | --- |
| secretome | field | one authoritative 256×256 matrix; two same-shape staging grids are workspace |
| centroid history | cell | SoA `x`/`y` bounded ring with per-slot head and count |
| self polarity | cell | SoA vector components and magnitude |
| signal | cell | SoA scalar column |
| uptake multiplier | global | one backend-resident scalar plus initialized status |
| intracellular state | cell | SoA `rac`, `a`, and semantic time |
| focal strength | cell | SoA scalar column |
| focal relationships | relationship | bounded canonical endpoint/generation/payload SoA |
| motility force | cell | SoA vector and derived scalar columns |
| Potts ownership/geometry/neighbors | existing CorePotts state | existing qualified storage |

Scratch is declared and preallocated at construction: two field staging grids, per-cell uptake and
fixed-tree global reduction scratch, polarity snapshots and neighbor reductions, relationship
transaction buffers, status/publication buffers, and observation reducers. The authoritative
field is not overwritten during its five internal substeps. No state is represented as a
dictionary, per-cell heap object, vector of variable-length vectors, live foreign solver, or
host-only closure.

The state declarations own meaning, lifecycle, persistence, and adaptation. The physical arrays do
not become a parallel model API. Cell slot and generation remain distinct, and relationship
endpoints always carry generations.

## Source-backed process plan

One normalized root plan executes:

1. Potts Metropolis and accepted-copy focal topology;
2. five secretome diffusion/reset substeps;
3. post-Potts centroid sampling;
4. source-faithful four-interval polarity after source MCS 120 / from target MCS 122;
5. signal reset, calibration, or uptake;
6. intracellular advancement;
7. focal payload retuning every ten MCS;
8. synchronous neighbor-polarity alignment;
9. protrusion-force publication for the next Potts MCS;
10. relationship lifecycle cleanup; and
11. declared observations.

This is a finer canonical spelling of the accepted CC3D scheduler order. It does not reorder source
effects: the processes split one Python steppable only where its internal statements already have a
fixed order and a visible commit dependency.

The exact source-label boundary consequences remain, with normalized targets made explicit:

- At source MCS 120 / target 121, Potts uses focal strength zero; the later phase of that same
  target transition retunes to 20, so source MCS 121 / target 122 is the first Potts step that
  reads 20.
- At source MCS 210 / target 211, uptake calibrates and mutates the field but does not write `s`;
  the ODE reads zero. The later retune writes the scanned strength and the same-MCS force update
  sees it.
- At source MCS 211 / target 212, uptake publishes `s` before the ODE, and Potts uses the force
  written at source MCS 210 / target 211.

## Numerical freeze

The source-faithful CPU profile and portable Float32 profile are separate, named profiles.

The Wang field is a Float32 logical 256×256 matrix. The source's singleton z extent remains
provenance rather than a runtime stencil dimension. It uses a two-dimensional periodic,
four-neighbor forward-Euler solve.
CC3D 4.2.5 scales diffusion coefficient 1 against its 0.23 square-2D stability limit, producing
five substeps with coefficient 0.2. Each substep diffuses first and then sets every Medium site to
concentration 1. Uptake occurs only after all five substeps.

The five substeps read one immutable post-Potts ownership/type snapshot and alternate between two
staging grids. They publish one field result only after all five substeps and validation succeed.
Internal substeps are not stable checkpoints. Stable capture remains the completed-MCS boundary
after required observation.

For every cell-owned site, source uptake removes:

```text
min(1, 0.0025 * concentration)
```

The raw cell signal is total removed mass divided by post-Potts cell volume. Source MCS 210 /
target 211 publishes the one global multiplier `4 / maximum(raw uptake)` but leaves `s` unchanged.
Later source MCS values publish `s = raw uptake * multiplier` before intracellular advancement.
The source duplicates the multiplier in each cell dictionary, but every value is identical; the
normalized model stores the scientifically global value once.

Exchange behavior is a plan-resolved mode, never an internal MCS branch:

| Normalized target | Source label | Mode |
| ---: | ---: | --- |
| 1–121 | 0–120 | inactive |
| 122–210 | 121–209 | reset `s` to zero without field mutation |
| 211 | 210 | uptake and calibrate without writing `s` |
| 212–500 | 211–499 | uptake and publish `s` |

Calibrate and publish use a staged candidate field. A zero or nonfinite calibration maximum is a
structured domain failure that publishes neither field, multiplier, nor signal.

The source-faithful CPU reduction visits ascending active cell slots and ascending linear site
indices. The portable profile uses one fixed-width-256 workgroup per active cell: each lane visits
its ascending strided sites and a fixed pairwise tree combines lane totals. The global maximum uses
a fixed pairwise tree. Floating atomics and scheduler-dependent sums are not admissible.

The Wang intracellular law is:

```text
drac/dt = a + s - 0.1rac
a = 1
```

with `s` constant over one 2880-time-unit invocation. The source uses libRoadRunner/CVODE. The CPU
source profile will be checked against an exact runtime trace; the portable implementation is
checked against the affine closed form rather than inheriting a host foreign solver. The generic
Euler, Heun, and RK4 capability remains part of G3, but the Wang production law may use a
registered source-equivalent affine advance if that is the only stable and efficient way to meet
the runtime oracle.

The force law remains:

```text
p = min(focal_strength / 1000, 1) * 0.4
aligned = normalize(p * mean(neighbor_polarity) + (1-p) * self_polarity)
h = rac^4 / (40^4 + rac^4)
lambdaVec = -force_max * h * aligned
```

Neighbor means are computed from one complete snapshot before any aligned polarity is committed.

## Conformance-first implementation

Each primitive starts with its smallest oracle:

| Slice | First fixtures |
| --- | --- |
| state/history | ring wrap, source `t-4`, zero displacement, restart at every head |
| intracellular | affine analytic cases, startup step, source 210/target 211, source 211/target 212, restart |
| field | constant invariant, impulse, periodic wrap, singleton-z collapse, five substeps, reset order, reservoir balance, failure atomicity |
| exchange | inactive/reset/calibrate/publish modes, cap/relative branches, volume normalization, fixed reduction, zero-maximum failure, cross-domain atomicity |
| relationships | create/remove/retune, capacity, proposal truth table, stale generation |
| alignment/force | empty neighbors, synchronous snapshot, clamp, zero vector, Hill limits |
| plan | source-to-target mapping and direct source 120/210/211 → target 121/211/212 visibility |
| storage | Adapt round trip, descriptor-free device-valid tree, authoritative field plus two staging grids, typed cross-domain write set, fixed capacities, zero warm allocation contract |

G3-B closes the source-faithful rows on sequential CPU and the portable structural/device-readiness
rows. Warm field and exchange execution on CPU must allocate zero bytes after construction.
G3-C then executes the identical canonical model on Metal and ROCm without redesign.

Revision 3 strengthens the allocation gate: the final closure packet must report every process and
the complete non-observing sequential CPU MCS transition at zero bytes after construction and
warm-up. Field and exchange already meet that rule; their local results do not waive the remaining
rows. Caller-owned observation serialization and checkpoint output buffers are measured
separately.

The field and exchange conformance profile preregisters local Float32 tolerances in the
machine-readable contract. Integer schedules, periodic index mapping, exact Medium overwrite,
identity/generation state, status, and publication epochs remain exact. Balance uses the registered
mass-scaled bound; tolerances cannot be widened after paper-scale results are inspected without a
new evidence revision.

## Remaining foreign-runtime work

Three narrow runtime oracles remain. None blocks starting the reusable state, field, history,
exchange, intracellular, relationship, or observation substrate, but all block a completed G3-B
claim:

1. Confirm default CC3D 4.2.5 Potts lattice boundary behavior and exact attempted-copy accounting
   for the Wang XML, including source MCS 0 / target MCS 1.
2. Record the pinned libRoadRunner integrator identity, tolerances, and `rac` outputs for controlled
   initial values and signals.
3. Record a CC3D 4.2.5 numerical field microtrace for impulse, periodic-edge, and a pattern that
   distinguishes Medium reset after every scaled substep from final-only reset.

Original source seed identities, archived pickle/UMAP execution, and final paper-classification
tolerances belong to Phase 14.3 rather than this implementation gate.

## Completion-claim protocol

The accepted exit is deliberately narrower than “the pieces exist.” Before the exact phrase
`G3-B complete` may appear:

1. the one generic Wang declaration must lower to the registered complete 11-process plan;
2. isolated and assembled source-faithful CPU conformance must both pass;
3. the portable state/plan tree must pass the structural KernelAbstractions CPU gate;
4. all-process transaction, failure, allocation, observation, and restart matrices must pass;
5. all three foreign-runtime oracles must be closed from pinned raw artifacts;
6. regression/API/fingerprint gates must pass on the exact clean commit; and
7. `scripts/check_phase14_g3b_closure.jl` must print `PASS`.

The live ledger may use only `pending`, `partial`, or `passed`. A `partial` row is never treated as
credit toward the final claim. G3-C still owns real Metal and ROCm numerical/runtime
qualification; G3-B cannot claim either backend merely because portable kernels ran through the
KernelAbstractions CPU backend.

Revision 4 resolves the accepted-copy focal-topology ambiguity exposed during implementation.
The pinned 4.2.5 plugin uses a randomized NeighborOrder-3 scan, a first-eligible neighbor rule,
activation-energy short circuit, acceptance-only creation, initial `0/0/100000` link parameters,
and at-most-one overlength removal per affected surviving endpoint. The
[primary-source audit](phase-14-g3b-focal-topology-source-audit.md) records the exact source
commit and hashes. Portable execution uses a registered semantic Philox namespace and does not
claim bitwise replay of the plugin's implicit `std::rand` state.

## Entry verdict

G3-B is ready to implement now. The first code slice should establish generic cell state/history
and fixed-capacity device storage together with their CPU fixtures and Adapt contracts. Field and
intracellular primitives can follow without changing this state ABI. A Wang assembly fixture is
added only after the generic laws exist; no Wang-named runtime export is introduced.

Implementation has started: the
[cell-history substrate evidence](phase-14-g3b-history-evidence.md) records the completed
backend-adaptable capacity-five ring and its 22-assertion CPU gate. This is an implementation
increment, not a G3-B or GPU qualification claim.

The
[atomic field evidence](phase-14-g3b-field-evidence.md) records the next sequential CPU increment:
one authoritative field, two preallocated staging grids, five internal substeps, exact
post-substep Medium reset, preflight stability rejection, failure atomicity, and zero-byte warm
execution. Backend-native execution, backend status publication, the CC3D microtrace, and
exchange/calibration remain open; this evidence is not a GPU qualification claim.

The
[exchange transaction evidence](phase-14-g3b-exchange-evidence.md) records the generic
root-plan-mode and immediate field/cell/global transaction: inactive/reset/calibrate/publish
boundaries, maximum calibration, source-faithful CPU reductions, checkpoint state, failure
atomicity, and zero-byte warm publication now pass. Portable fixed-tree kernels, device
conditional publication, and their KernelAbstractions CPU oracle now pass; Metal/ROCm execution
and foreign-runtime comparison remain open.

The same field/exchange state ABI now executes a portable KernelAbstractions reference: five
ordered field substeps, width-256 per-cell uptake trees, a fixed global maximum, backend status,
and conditional commits. This closes the reusable portable execution design on the CPU backend;
Metal/ROCm execution evidence remains the G3-C promotion step and cannot change the ABI or
reduction order.

The generic
[intracellular evidence](phase-14-g3b-intracellular-evidence.md) now records exact affine
advancement, semantic-RNG initialization, CPU/portable agreement, conditional publication,
zero-byte warm execution, exact target-122 start, and checkpoint epoch restore. The pinned
RoadRunner trace and assembled Wang visibility remain open.

All remaining implementation proceeds only against revision 4 of the machine-readable contract.
The old three-argument forcing-array exchange overload remains compatibility-only historical
prototype behavior. The mode-bound immediate transaction is the Wang execution target and owns
the frozen cross-domain write ABI.
