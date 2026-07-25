# Phase 14.1 G3-B Wang Entry Packet

Status: accepted implementation entry; G3-B implementation may begin

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
- the two remaining foreign-runtime questions.

The CPU reference is an oracle for the same canonical model that will run on Metal and ROCm. It is
not permission to build CPU-owned arrays, host callbacks, a second runtime, or paper-specific
public types.

## Canonical state and storage

The implementation has nine future-relevant state families:

| State | Owner | Backend-ready physical form |
| --- | --- | --- |
| secretome | field | contiguous grid plus one ping-pong grid |
| centroid history | cell | SoA `x`/`y` bounded ring with per-slot head and count |
| self polarity | cell | SoA vector components and magnitude |
| signal and uptake multiplier | cell | SoA scalar columns plus initialized status |
| intracellular state | cell | SoA `rac`, `a`, and semantic time |
| focal strength | cell | SoA scalar column |
| focal relationships | relationship | bounded canonical endpoint/generation/payload SoA |
| motility force | cell | SoA vector and derived scalar columns |
| Potts ownership/geometry/neighbors | existing CorePotts state | existing qualified storage |

Scratch is declared and preallocated at construction: field ping-pong storage, per-cell uptake and
global reduction scratch, polarity snapshots and neighbor reductions, relationship transaction
buffers, status buffers, and observation reducers. No state is represented as a dictionary,
per-cell heap object, vector of variable-length vectors, live foreign solver, or host-only closure.

The state declarations own meaning, lifecycle, persistence, and adaptation. The physical arrays do
not become a parallel model API. Cell slot and generation remain distinct, and relationship
endpoints always carry generations.

## Source-backed process plan

One normalized root plan executes:

1. Potts Metropolis and accepted-copy focal topology;
2. five secretome diffusion/reset substeps;
3. post-Potts centroid sampling;
4. source-faithful four-interval polarity after MCS 120;
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

The exact boundary consequences remain:

- At MCS 120, Potts uses focal strength zero; the later retune writes 20 for MCS 121.
- At MCS 210, uptake calibrates and mutates the field but does not write `s`; the ODE reads zero.
  The later retune writes the scanned strength and the same-MCS force update sees it.
- At MCS 211, uptake publishes `s` before the ODE, and Potts uses the force written at MCS 210.

## Numerical freeze

The source-faithful CPU profile and portable Float32 profile are separate, named profiles.

The Wang field is a Float32, two-dimensional, periodic, nearest-neighbor forward-Euler solve.
CC3D 4.2.5 scales diffusion coefficient 1 against its 0.23 square-2D stability limit, producing
five substeps with coefficient 0.2. Each substep diffuses first and then sets every Medium site to
concentration 1. Uptake occurs only after all five substeps.

For every cell-owned site, source uptake removes:

```text
min(1, 0.0025 * concentration)
```

The raw cell signal is total removed mass divided by post-Potts cell volume. MCS 210 publishes the
global multiplier `4 / maximum(raw uptake)` but leaves `s` unchanged. Later MCS values publish
`s = raw uptake * multiplier` before intracellular advancement.

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
| intracellular | affine analytic cases, startup step, MCS 210/211, restart |
| field | constant invariant, impulse, periodic wrap, five substeps, reset order, balance |
| exchange | cap/relative branches, volume normalization, deterministic max, field balance |
| relationships | create/remove/retune, capacity, proposal truth table, stale generation |
| alignment/force | empty neighbors, synchronous snapshot, clamp, zero vector, Hill limits |
| plan | ordinary order and direct MCS 120/210/211 visibility |
| storage | Adapt round trip, device-valid tree, fixed capacities, zero warm allocation contract |

G3-B closes these on sequential CPU. Their logical data and workspaces are already constrained so
G3-C can execute the identical canonical model on Metal and ROCm without redesign.

## Remaining foreign-runtime work

Two narrow runtime oracles remain. Neither blocks starting the reusable state, field, history,
exchange, intracellular, relationship, or observation substrate, but both block a completed G3-B
claim:

1. Confirm default CC3D 4.2.5 Potts lattice boundary behavior and exact attempted-copy accounting
   for the Wang XML.
2. Record the pinned libRoadRunner integrator identity, tolerances, and `rac` outputs for controlled
   initial values and signals.

Original source seed identities, archived pickle/UMAP execution, and final paper-classification
tolerances belong to Phase 14.3 rather than this implementation gate.

## Entry verdict

G3-B is ready to implement now. The first code slice should establish generic cell state/history
and fixed-capacity device storage together with their CPU fixtures and Adapt contracts. Field and
intracellular primitives can follow without changing this state ABI. A Wang assembly fixture is
added only after the generic laws exist; no Wang-named runtime export is introduced.

Implementation has started: the
[cell-history substrate evidence](phase-14-g3b-history-evidence.md) records the completed
backend-adaptable capacity-five ring and its 22-assertion CPU gate. This is an implementation
increment, not a G3-B or GPU qualification claim.
