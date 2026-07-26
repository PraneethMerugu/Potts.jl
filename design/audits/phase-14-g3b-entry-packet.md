# Phase 14.1 G3-B Wang Entry Packet

Status: accepted implementation entry, revision 7; derived-contact, packed-status, and
dimension-generic observation normalization accepted

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
- the three remaining Wang/CC3D/RoadRunner source-semantic studies.

The CPU reference is an oracle for the same canonical model that will run on Metal and ROCm. It is
not permission to build CPU-owned arrays, host callbacks, a second runtime, or paper-specific
public types.

Revision 2 closed the pre-field implementation audit. In particular, it resolved the source-MCS
zero mapping, makes five field substeps internal to one atomic process, removes internal substep
checkpoints, requires two field staging grids, makes exchange mode a root-plan binding, normalizes
the shared uptake multiplier to global state, and freezes deterministic reduction and
cross-domain-publication requirements.

Revision 3 leaves those semantics unchanged and strengthens only the exit proof. It registers a
[machine-readable closure ledger](phase-14-g3b-closure-ledger-v1.toml), thirteen non-substitutable
closure requirements, assembled-model evidence, all-process failure/allocation matrices,
hash-addressed source-study artifacts, exact restart rejection points, and a fail-closed claim
checker. Primitive results and KernelAbstractions CPU results remain useful increments but cannot
be promoted into a complete Wang, GPU, or paper-reproduction claim.

Revision 4 froze the accepted-copy FocalPointPlasticity law. Revision 5 closes the remaining
specification loopholes: it makes the Potts/relationship commit one preflighted transaction,
freezes portable topology RNG addressing, records the exact fourteen-column source observation
schema and lossless geometry snapshots, prohibits Wang exports and positional mega-constructors,
requires a non-Wang reuse proof for every new primitive, and adds a process-by-process proof
matrix. Final closure is now an attestation over one clean tested implementation commit: command
outputs, source inputs, analyses, uncertainty records, controlled fixtures, and matrices are SHA-256
addressed. Contract and ledger must already say `passed` in that tested commit; the later
attestation commit may add only the closure evidence root.

Revision 6 reconciles the implemented contact-neighbor execution view with the scientific state
contract. Contact adjacency is derived transiently from the immutable post-Potts ownership
snapshot, not transactionally maintained or checkpointed as a second authoritative graph. It is
stored as one symmetric bit-packed relation, built with idempotent integer atomic OR and reduced
in ascending neighbor identity. Revision 6 also replaces independently selected device status and
failing-cell scalars with one packed atomic key, so simultaneous different failures cannot report
a class from one cell and an identity from another. These corrections preserve the revision-5
closure proof and reduce adjacency storage by approximately 32 times.

Revision 7 closes the observation generality defects found before canonical assembly. The bounded
cell table now derives a dimension-generic coordinate tuple from compiled moments and binds
arbitrary typed named property columns. Its capacity is explicitly persistent cell-slot capacity,
not an ambiguous compact row count. Lossless ownership publication preserves the full
N-dimensional lattice shape. The exact two-dimensional Wang labels and schedules remain
declaration-layer configuration. Focused 2D/3D, failure, publication, and restart evidence passes;
assembled Wang observation order and real GPU qualification remain open.

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
| centroid history | cell | bounded capacity-by-history matrix of fixed-size vector samples with per-slot head, count, and generation |
| self polarity | cell | SoA vector components and magnitude |
| signal | cell | SoA scalar column |
| uptake multiplier | global | one backend-resident scalar plus initialized status |
| intracellular state | cell | SoA `rac`, `a`, and semantic time |
| focal strength | cell | SoA scalar column |
| focal relationships | relationship | bounded canonical endpoint/generation/payload SoA |
| motility force | cell | SoA vector and derived scalar columns |
| Potts ownership/geometry | existing CorePotts state | existing qualified storage |

Scratch is declared and preallocated at construction: two field staging grids, per-cell uptake and
fixed-tree global reduction scratch, polarity snapshots, bit-packed derived contact adjacency and
neighbor reductions, relationship transaction buffers, status/publication buffers, and observation reducers. The authoritative
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

The source-shaped per-cell publication is now exact rather than “an observation.” At targets
122–500 it contains, in order, `cell_id,x,y,x_self_polarity,y_self_polarity,a,s,rac,f,f_x,f_y,`
`fpp,f_coef,p_frac`; target/source MCS and slot generation are typed envelope metadata. Rows use
ascending persistent cell identity. Targets 91 and 271 publish lossless canonical ownership/type
snapshots labelled source 90 and 270 so Phase 14.3 can derive geometric features without rerunning
or reverse-engineering G3-B. Classifier, scaler, k-means, UMAP, and paper-figure claims remain
deferred.

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

with `s` constant over one 2880-time-unit invocation. The source uses libRoadRunner/CVODE. Wang's
construction, startup, time, input, and publication calls must be traced from pinned source; the
CPU and portable implementations are checked against the affine closed form rather than inheriting
a host foreign solver. The generic
Euler, Heun, and RK4 capability remains part of G3, but the Wang production law may use a
registered source-equivalent affine advance when it preserves the studied mathematical law,
timing, and publication boundary.

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
| observations | arbitrary named bindings, dimension-matched coordinates, 2D/3D shape preservation, exact Wang schema, capacity/failure atomicity, restart |
| plan | source-to-target mapping and direct source 120/210/211 → target 121/211/212 visibility |
| storage | Adapt round trip, descriptor-free device-valid tree, authoritative field plus two staging grids, typed cross-domain write set, fixed capacities, zero dynamic scientific-storage allocation, bounded size-independent CPU launch overhead |

G3-B closes the source-faithful rows on sequential CPU and the portable structural/device-readiness
rows. Warm isolated field and exchange execution on CPU must allocate zero bytes after construction.
G3-C then executes the identical canonical model on Metal and ROCm without redesign.

The final closure packet reports zero dynamic scientific-storage allocation for every isolated
process. For the complete portable KernelAbstractions CPU MCS transition it separately requires
unchanged tracked scientific allocation counters and no more than 65,536 Julia heap bytes of
size-independent launch/orchestration overhead after warm-up. The 48² and 64² fixtures must report
the same measured overhead, so a fixed runtime cost cannot conceal lattice-, cell-, edge-, field-,
or row-sized allocation. Caller-owned observation serialization and checkpoint output buffers are
measured separately.

The field and exchange conformance profile preregisters local Float32 tolerances in the
machine-readable contract. Integer schedules, periodic index mapping, exact Medium overwrite,
identity/generation state, status, and publication epochs remain exact. Balance uses the registered
mass-scaled bound; tolerances cannot be widened after paper-scale results are inspected without a
new evidence revision.

## Remaining source-semantic study

Three narrow studies remain. They do not require new external CC3D execution. None blocks starting
the reusable state, field, history, exchange, intracellular, relationship, or observation
substrate, but all block a completed G3-B claim:

1. Trace default CC3D 4.2.5 Potts boundaries, attempt accounting, NeighborOrder tables,
   FocalPointPlasticity behavior, and the per-cell pixel-based ExternalPotential law selected by
   Wang's empty plugin declaration from pinned source against the Wang XML/Python, recording every
   uncertainty and controlled distinguishing fixture.
2. Trace Wang's RoadRunner construction, startup, time advancement, input, and publication calls
   against the pinned Antimony law, and qualify the implementation against its closed-form affine
   solution.
3. Trace CC3D 4.2.5 DiffusionSolverFE stability scaling, substeps, stencil/boundary order,
   constant-concentration timing, and field publication from source, then exercise impulse,
   periodic-edge, singleton-z, and reset-every-substep fixtures.

Original source seed identities, archived pickle/UMAP execution, and final paper-classification
tolerances belong to Phase 14.3 rather than this implementation gate.

## Completion-claim protocol

The accepted exit is deliberately narrower than “the pieces exist.” Before the exact phrase
`G3-B complete` may appear:

1. the one generic Wang declaration must lower to the registered complete 11-process plan;
2. isolated and assembled source-faithful CPU conformance must both pass;
3. the portable state/plan tree must pass the structural KernelAbstractions CPU gate;
4. all-process transaction, failure, allocation, observation, and restart matrices must pass;
5. all three source-semantic studies must be accepted from pinned source, explicit uncertainty
   records, and controlled fixtures;
6. regression/API/fingerprint gates must pass on the exact clean commit; and
7. every process proof records the complete required-facet set, and every command output, runtime
   environment, raw artifact, comparison, and matrix must resolve through the SHA-256 closure
   manifest;
8. the diff after the clean tested implementation commit must be restricted to the closure
   evidence root; contract and ledger cannot be promoted after testing; and
9. `scripts/check_phase14_g3b_closure.jl` must print `PASS` from a clean attestation checkout.

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
execution. Backend-native execution, backend status publication, the CC3D field source study, and
exchange/calibration remain open; this evidence is not a GPU qualification claim.

The
[exchange transaction evidence](phase-14-g3b-exchange-evidence.md) records the generic
root-plan-mode and immediate field/cell/global transaction: inactive/reset/calibrate/publish
boundaries, maximum calibration, source-faithful CPU reductions, checkpoint state, failure
atomicity, and zero-byte warm publication now pass. Portable fixed-tree kernels, device
conditional publication, and their KernelAbstractions CPU oracle now pass; Metal/ROCm execution
and the CC3D source-semantic field study remain open.

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

The
[polarity and force evidence](phase-14-g3b-polarity-force-evidence.md) records source-backed
synchronous neighbor alignment and Hill-scaled vector force through generic named property
bindings. The revision-6 bit-packed adjacency, canonical heterogeneous-failure key, host/portable
agreement, fixed launch counts, zero-byte warm host path, and coupled restart pass 67 focused
assertions. Assembled Wang order and real Metal/ROCm qualification remain open.

The
[bounded observation evidence](phase-14-g3b-observation-evidence.md) records arbitrary typed named
property bindings, dimension-generic coordinate columns, shape-preserving ownership snapshots,
the exact configured fourteen-column Wang record, capacity/nonfinite failure atomicity, and
completed-MCS restart continuity across 107 focused assertions. The
[source audit](phase-14-g3b-observation-source-audit.md) pins the exact header and source
`mcs > 120` trigger. Assembled target 91/122/271/500 visibility, whole-plan allocation, and real
Metal/ROCm qualification remain open.

All remaining implementation proceeds only against revision 7 of the machine-readable contract.
The old three-argument forcing-array exchange overload remains compatibility-only historical
prototype behavior. The mode-bound immediate transaction is the Wang execution target and owns
the frozen cross-domain write ABI.
