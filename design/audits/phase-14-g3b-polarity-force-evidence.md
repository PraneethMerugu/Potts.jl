# Phase 14.1 G3-B Polarity and Force Evidence

Status: isolated sequential CPU and KernelAbstractions CPU portable reference accepted;
assembled Wang order and real GPU qualification remain open

Date: 2026-07-25

## Scope

This record covers two generic processes and their generic Potts consumer:

- synchronous finite-contact-neighbor vector alignment from a declared ownership relation; and
- a configurable Hill-scaled signed vector force; plus
- a dimension-generic per-cell vector boundary-potential energy component.

Neither runtime type contains a Wang identity or paper-specific branch. The Wang assembly supplies
property bindings and parameters.

## Implementation

`NeighborPolarityAlignment` owns a bounded backend-adaptable workspace with:

- immutable source x/y snapshots;
- a symmetric bit-packed contact adjacency with exactly
  `cell_capacity * cld(cell_capacity, 32)` `UInt32` words;
- deterministic ascending-neighbor sums and counts;
- candidate x/y/fraction arrays; and
- one packed `UInt32` failure key ordered by ascending cell and then failure class.

The portable reference launches five plan-constant kernels: initialize cell snapshots, clear
adjacency words, materialize adjacency from the post-Potts ownership snapshot, compute candidates,
and conditionally commit. Contact faces use idempotent integer atomic OR; duplicate faces collapse
to one bit, words and set bits are reduced in ascending neighbor identity, and no floating atomic
is used. The adjacency is ephemeral process workspace rather than authoritative or checkpointed
scientific state.

`HillVectorForce` owns four candidate columns plus bounded status. Its portable reference launches
initialize, compute, and conditional-commit kernels.

`CellVectorBoundaryPotentialHamiltonian` binds an arbitrary two- or three-component tuple of
per-cell properties and one declared surface relation. At proposal evaluation it applies the
relation's lattice offsets and weights to the losing/gaining boundary difference around the
recipient site. It is explicitly classified as non-equilibrium, rejected by
`SequentialEquilibrium`, and executes through the ordinary typed proposal-energy fold on both the
logical/compiled CPU reference and KernelAbstractions CPU path.

Both host references validate every active input and publish no output column when any active cell
fails. Portable failures likewise leave all authoritative output columns unchanged. A single
atomic minimum over the packed key prevents the failure class from one cell being paired with the
identity of another under simultaneous heterogeneous failures.

## Executed evidence

The focused polarity/force file passes 67/67 assertions:

- 15 synchronous alignment formula, empty-neighbor, zero-vector, bit-packed adjacency,
  cross-word identity, count, and clamp assertions;
- 15 host/portable agreement, five-launch, zero-transfer, negative-strength, canonical
  heterogeneous-failure, and failure-atomicity assertions;
- 11 exact Hill zero/half/double-threshold, magnitude, sign, and zero-polarity assertions;
- 16 Hill host/portable agreement, three-launch, zero-transfer, invalid-signal, canonical
  heterogeneous-failure, and failure-atomicity assertions;
- one zero-byte warm host-reference assertion; and
- nine coupled-plan uninterrupted/restarted agreement assertions.

The dedicated vector-boundary file additionally passes 24/24 assertions covering API/schema
metadata, extension, retraction, cell-to-cell replacement, interface orientation, zero force,
periodic wrapping, compiled proposal dispatch, non-equilibrium rejection, direct
KernelAbstractions CPU execution, zero-allocation warm local evaluation, a complete sequential
MCS, and 3D generality.

The [source audit](phase-14-g3b-polarity-force-source-audit.md) pins the exact radial steppable hash,
synchronous snapshot rule, unweighted finite-neighbor mean, clamp/normalization law, and Hill force
formula. It now also pins CC3D 4.2.5 `ExternalPotentialPlugin.cpp`, the empty-plugin
`BYCELLID`/pixel dispatch, losing/gaining boundary law, sign convention, and next-MCS visibility.

## Claim boundary

This evidence closes isolated generic CPU behavior and the KernelAbstractions CPU execution view.
It does not close:

- activation/order inside the assembled eleven-process Wang plan;
- source/target MCS boundary traces;
- whole-MCS allocation or launch accounting;
- real Metal or ROCm execution; or
- G3-B as a whole.
