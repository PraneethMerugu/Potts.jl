# Topology and Spatial Relations

Status: Accepted except where explicitly marked otherwise

## Purpose

This document defines the discrete space on which Potts.jl models operate. It separates geometric
embedding, finite-domain boundaries, scientific neighborhood roles, and device representation so
that changing an implementation does not silently change a model.

The normative abstraction is a collection of named spatial relations over one realized domain. A
single catch-all topology object is not sufficient semantic provenance.

## Scientific Scope

The paper-quality native scope is:

- Regular Cartesian lattices in two and three dimensions
- Isotropic or anisotropic Cartesian site spacing
- Periodic, closed, fixed-exterior, and mixed boundary configurations
- Explicit regular offset stencils
- CPU and supported GPU execution with identical compiled relation meaning

Hexagonal lattices, rhombic-dodecahedral 3D lattices, irregular lattices, and arbitrary graph
lattices are Experimental until their separate contracts and conformance suites are accepted. Their
existence MUST be accommodated by the architecture without weakening Cartesian guarantees.

## Separation of Concepts

### Lattice Geometry

`LatticeGeometry` defines:

- Spatial dimension
- Coordinate embedding
- Index-to-physical-coordinate conversion
- Site volume or area
- Distance and displacement interpretation
- The meaning of regular offsets or graph edges

Geometry does not determine which finite sites exist, how boundaries behave, which sites may copy,
or which edges contribute to an energy.

### Domain

`Domain` defines:

- The realized finite set of valid sites
- Cartesian dimensions or graph vertex set
- Boundary condition on each face or graph boundary
- Excluded sites and internal obstacles when supported
- The association between lattice indices and valid sites

Every valid ownership site has exactly one owner under the state-model contract. Exterior ghost
values, fixed walls, and excluded sites are not ordinary mutable lattice sites unless explicitly
modeled as such.

### Spatial Relation

A spatial relation is a named ordered relation over sites, declared for one scientific purpose. Its
semantic descriptor includes, as applicable:

- Role
- Ordered offsets or graph adjacency identity
- Direction IDs
- Edge weights and their interpretation
- Directed or symmetric character
- Opposite-direction mapping
- Boundary realization rule
- Physical or lattice-unit normalization
- Compatibility and conversion provenance

Applying a spatial relation to a domain produces its realized edges. The same abstract stencil may
therefore have different realized edges at closed boundaries while retaining the same bulk direction
set.

## Required Spatial Roles

A compiled model identifies all applicable roles explicitly:

1. **Proposal relation** — possible donor directions or proposal transitions
2. **Contact relation** — pairs contributing to contact Hamiltonians
3. **Surface relation** — edges contributing to surface or perimeter measurement
4. **Connectivity relation** — adjacency used by fragmentation constraints
5. **Spatial-query relation** — adjacency or measure used by DSL observations and rules
6. **Conflict relation** — sites whose simultaneous transactions may conflict
7. **Field-discretization relation** — field operators, interpolation, or gradients

Additional named roles MAY be introduced, but MUST state their edge meaning and consumers.

Two or more roles MAY reference one immutable descriptor. Sharing is an implementation and DRY
optimization; it does not make the roles semantically interchangeable. Components MUST request
relations by role rather than consulting a global topology.

## Presets and Defaults

CorePotts MUST NOT impose one universal scientific neighborhood bundle. Potts provides named,
reportable presets, including compatibility-oriented and native physics-oriented families.

Examples include:

- `ClassicCPM`
- `CC3DCompatibility`
- `MorpheusCompatibility`
- `ArtistooCompatibility`
- `IsotropicCartesianCPM`

The precise version and relation bundle selected by a preset are part of model provenance. Changing
a preset's bundle requires a semantic version change or a new preset version.

Native `CPMDynamics` and `EquilibriumCPM` presets use the first geometric shell for copy proposals:
four directions on a square 2D lattice and six directions on a cubic 3D lattice. Extending a contact,
surface, query, or conflict relation MUST NOT silently extend the proposal relation.

## Regular Stencils

### Explicit Representation

An explicit stencil is the primitive regular-lattice relation description. It contains a finite
ordered sequence of nonzero integer coordinate offsets and relation-specific metadata.

Named concepts such as Moore, Von Neumann, radius, or neighborhood order are constructors. A model
report and checkpoint record the resulting explicit stencil, not only the constructor name.

The following are invalid:

- A zero offset
- A repeated offset
- A non-integer regular-lattice offset
- A symmetric relation without the negative of every offset
- A non-finite weight
- A negative weight where the relation law requires a nonnegative measure or probability

Constructor-generated equivalent offsets are canonicalized before compilation. Duplicate offsets
provided explicitly by a user raise an error rather than silently changing edge multiplicity or
proposal probability.

### Distance-Shell Order

For conventional Cartesian CPM neighborhood orders, offsets are grouped into complete shells by
increasing distance from the source site. A requested order contains all offsets in the first `k`
shells, including all ties.

For a unit-spaced square lattice:

| Order | Newly included squared distance | New offsets | Cumulative offsets |
|---:|---:|---:|---:|
| 1 | 1 | 4 | 4 |
| 2 | 2 | 4 | 8 |
| 3 | 4 | 4 | 12 |
| 4 | 5 | 8 | 20 |

An axial-ray stencil, an `L1` ball, and an `L∞` ball are separately named constructors. They MUST
NOT be presented as equivalent to conventional nearest-distance order.

For anisotropic spacing, a constructor states whether its shell definition uses physical distance or
reference index geometry. The choice is visible in the model report.

### Canonical Direction IDs

Direction order is semantic because it may determine proposal probability addressing and RNG event
coordinates. The native canonical order is:

1. Increasing squared physical distance
2. Documented lexicographic ordering of the integer coordinate tuple within a distance tie

Direction IDs are one-based positions in that canonical sequence. The canonicalization version is
stored in provenance. Compatibility presets MAY use a different source-compatible order, but MUST
name and report it.

For every symmetric stencil, compilation constructs and verifies an involutive opposite mapping:

```text
opposite(opposite(direction)) == direction
offset(opposite(direction)) == -offset(direction)
```

Changing physical spacing can change physical-distance order and is therefore a visible semantic
change when direction-addressed randomness is promised.

## Directedness and Weights

Contact, surface, connectivity, and equilibrium neighbor-copy relations are symmetric. Their
realized reverse edge has the same measure weight unless a separately named model proves a different
law.

The general interface MAY represent directed relations for transport, fields, or explicitly
nonequilibrium proposals. Directionality MUST be declared and MUST NOT be inferred from a missing
reverse offset.

Weights belong to a specific relation and declare their interpretation. Distinct interpretations
include:

- Proposal probability or unnormalized proposal mass
- Contact quadrature
- Surface or perimeter quadrature
- Graph edge measure
- Unweighted Boolean adjacency

A universal `1 / distance` neighbor weight is not a semantic default. A weight selected for surface
estimation MUST NOT silently affect proposal selection, contact energy, connectivity, or spatial
queries.

## Physical Embedding and Spacing

Cartesian geometry declares a positive finite spacing tuple `(delta_x, delta_y)` or
`(delta_x, delta_y, delta_z)`. Index offsets remain integer tuples. Physical displacements are the
componentwise product of index displacement and spacing.

The spacing participates in:

- Physical coordinates and distances
- Physical site area or volume
- Surface/perimeter quadrature
- Field derivatives and interpolation
- Documented physical interpretation and solution-side unit annotation
- Anisotropy reports

Bare lattice metrics remain site or edge counts. Physical and normalized metrics are distinct as
defined by the energy and tracker specification.

Anisotropic spacing is supported but MUST NOT be described as rotationally isotropic. Proposal
directions remain governed by the declared proposal law; spacing alone does not silently reweight
their selection.

## Boundary Conditions

### Per-Face Declaration

Cartesian domains declare boundary behavior for every positive and negative face. Periodic faces
must form a consistent paired axis. Nonperiodic faces may differ where their semantics permit it.

The initial boundary families are:

- `Periodic`
- `Closed` or source-compatible `NoFlux`
- `FixedExterior`
- Experimental `CustomBoundary`

Mixed domains such as periodic x and closed y are ordinary domain configurations, not new topology
subtypes.

### Closed Boundaries

For an interaction, metric, connectivity, or query relation, an offset leaving a closed domain
produces no realized edge. It MUST NOT clamp to the nearest in-domain site or create a self-edge.

For a conventional neighbor-site proposal whose law draws uniformly from the bulk direction set,
the direction is drawn before boundary realization. An out-of-domain closed-boundary direction is a
null attempt. It consumes its proposal budget and addressed random coordinates exactly as specified
by the algorithm, but changes no state and contributes no reverse edge.

Algorithms that instead sample uniformly from valid realized edges are separately named proposal
families with distinct boundary kinetics and proposal probabilities.

### Exterior Ownership and Walls

The following are semantically distinct:

- An absent edge at a closed boundary
- A fixed exterior medium owner
- A fixed exterior cell or wall owner
- A fixed internal obstacle
- A mutable ordinary medium site

They can produce different contact energies, surface measures, field boundaries, and biological
behavior. A compatibility importer MUST preserve the source distinction. Detailed fixed-owner and
obstacle lifecycle laws remain under `SEM-TOP-005`.

## Periodic Realization

Periodic wrapping maps an offset through the paired axis. A regular periodic model is invalid if,
for any site and relation:

- A nonzero offset wraps onto the source site, or
- Two distinct stencil offsets wrap onto the same neighbor.

This prevents hidden self-interactions, duplicated contact energy, and changed proposal masses on
domains too small for their stencils. An explicit future multigraph relation MAY preserve edge
multiplicity, but ordinary CPM relations do not.

Validation occurs after the domain dimensions, boundaries, and relation stencils are known.

### Minimum-Image Displacement

Physical displacement on a periodic axis uses a documented minimum-image convention. When two
images are exactly half a box apart, the native convention selects a stable canonical sign derived
from the ordered endpoints rather than backend floating-point rounding.

Minimum-image displacement is appropriate only where the requested observable has that meaning.
Unwrapped incremental moments remain authoritative for tracking cells that cross periodic
boundaries. A component MUST NOT use minimum-image displacement as a substitute for the accepted
periodic moment contract.

## Connectivity Relations

Connectivity is independent of proposal, contact, and surface relations. A connectivity constraint
declares both the foreground adjacency used for each cell and the complementary-background
adjacency required by its topological proof.

Examples such as 4/8 adjacency in 2D or 6/26 adjacency in 3D are explicit paired choices, not
defaults inferred from a contact stencil. A rigorously symmetric constraint MUST identify the
connectivity theorem and domain assumptions that justify its local test.

Fragmentation remains valid model behavior unless an optional connectivity constraint prohibits it.

## Spatial Queries and Fields

Spatial queries request a named relation and an explicit aggregation meaning. Site count, directed
edge count, undirected interface count, distinct-owner count, and physical contact measure are not
interchangeable. Their detailed DSL behavior remains under `SEM-TOP-008`.

Field discretization relations are independent of CPM proposal and contact relations. Field grid
placement, interpolation, gradients, Laplacians, boundary conditions, and synchronization remain
under `SEM-TOP-009`.

## Parallel Conflict Relations

The conflict relation is derived from the complete read/write footprint of:

- Proposal construction
- Energy and drive evaluation
- Hard constraints
- Tracker deltas
- Lifecycle effects
- Any state inspected during validation or commit

A hard-coded Moore neighborhood is permitted only when it is a proven conservative realization of
that footprint. If a component cannot declare a finite safe footprint, the compiler rejects an
incompatible parallel algorithm or selects a documented conservative execution path.

Conflict derivation is algorithm-specific. It MUST NOT change the model's scientific proposal or
energy relations.

## Coloring and Independent Sets

Coloring validity is a property of the realized finite domain graph, not of the infinite bulk
stencil alone. Compilation verifies that no two simultaneously active sites conflict under the
complete conflict relation.

For example, the ordinary two-color parity pattern is not a valid independent-set partition for a
nearest-neighbor periodic Cartesian axis of odd length. A compiler MUST reject that schedule, derive
a valid schedule, or select another algorithm; it MUST NOT run the invalid coloring silently.

Obstacles, mixed boundaries, extended reads, and lifecycle footprints participate in the same
validation.

## Custom and Graph Relations

### Custom Regular Stencils

A custom regular relation is a reusable host-side value. Before execution, the compiler validates:

- Dimension and coordinate representation
- Offset uniqueness and nonzero displacement
- Direction ordering
- Directedness or reverse-edge symmetry
- Weight domain and interpretation
- Boundary compatibility
- Periodic alias freedom
- Required algorithm capabilities

Kernels receive a concrete compiled descriptor with no abstract-container dispatch, host pointer,
heap allocation, or runtime method lookup.

### Static and Backend-Resident Storage

Small fixed descriptors SHOULD use immutable isbits structures such as tuples or static vectors when
that improves a backend. Larger stencils MAY use compact backend-resident read-only arrays when
unrolling would produce excessive compilation time, code size, or register pressure.

The storage cutoff is selected by benchmark and may vary by algorithm and backend. It is not a
scientific semantic. Both representations MUST enumerate the same direction IDs, offsets, weights,
and realized edges.

### Irregular and Graph Lattices

Irregular lattices are represented as an explicit graph plus geometric embedding, not simulated as
fake regular offsets. A CSR-like adjacency representation is an expected implementation direction,
not yet a normative storage mandate.

Graph models may share component and proposal interfaces with regular lattices while retaining
distinct geometry, edge measure, boundary, proposal-probability, performance, and reproducibility
contracts. Their detailed semantics remain Experimental under `SEM-TOP-007`.

## Isotropy-Oriented Native Preset

`IsotropicCartesianCPM` is an accepted named preset direction, not yet a validated numerical
parameterization. It uses first-shell copy proposals and is intended to use:

- A fourth-order square-lattice contact/surface estimator in 2D
- A sixth-order cubic-lattice contact/surface estimator in 3D
- Explicit normalized physical surface mechanics
- Published and independently reproduced correction factors

The reference estimator is the published normalized-kernel measure defined in
[Cartesian Surface, Queries, and Fields](cartesian-surface-queries-and-fields.md). Exact calibration
tables are versioned scientific data. This preset MUST NOT make an isotropy or cross-resolution
claim until the prescribed rotation and parameter-conversion suite passes.

Compatibility presets continue to reproduce their source simulator's proposal, interaction,
surface, and boundary choices even when those choices are more anisotropic.

## Compiled Model Report

Every executable model reports:

- Geometry family and semantic version
- Dimension and physical spacing
- Domain dimensions and valid-site count
- Boundary condition on every face
- Every spatial role and the descriptor it references
- Explicit offsets or graph identity
- Canonical direction IDs and ordering version
- Weight values and interpretation
- Directedness and opposite-direction mapping
- Metric normalization and conversion provenance
- Compatibility target and feature-level claim
- Periodic alias validation result
- Parallel conflict relation and its derivation
- Coloring or independent-set validation result
- Experimental features and approximations

Checkpoints retain enough of this report to reject incompatible restoration.

## Conformance Requirements

### Exact Structural Tests

- Exhaustively enumerate realized neighbors on small 2D and 3D domains.
- Verify direction IDs, reverse edges, opposite mappings, and symmetric weights.
- Verify absence of closed-boundary edges and self-edges.
- Reject periodic self-aliases and duplicate aliases.
- Exercise periodic, closed, fixed, and mixed boundaries.
- Verify minimum-image half-box ties.
- Verify all color classes and transaction batches are conflict-free.

### Scientific Consistency Tests

- Compare every local contact delta with full global recomputation.
- Compare every incremental surface delta with independent recomputation.
- Test raw, weighted, normalized, and physical metrics separately.
- Measure orientation-dependent perimeter/surface error for standard rotated shapes.
- Measure equilibrium or statistical consequences of each advertised native preset.

### Backend Tests

- Compare compiled offsets, weights, direction IDs, and realized neighbors across CPU and every
  supported GPU backend.
- Test both static and backend-resident descriptor representations where applicable.
- Benchmark compilation time, code size, registers, occupancy, and runtime before selecting storage
  cutoffs.
- Verify that a representation change does not change RNG addressing or trajectories within an
  algorithm's reproducibility profile.

### Compatibility Tests

- Pin the version of every external simulator fixture.
- Record its proposal, interaction, surface, boundary, and lattice conventions independently.
- Test imported models at the feature-level compatibility claim stated in their report.
- Preserve conversion provenance and reject unsupported topology features by default.

## Literature and Software Basis

- [CompuCell3D Potts and neighborhood-order documentation](https://compucell3dreferencemanual.readthedocs.io/en/latest/potts.html)
- [CompuCell3D square and hexagonal lattice documentation](https://compucell3dreferencemanual.readthedocs.io/en/latest/lattice_type.html)
- [Morpheus: anisotropy of CPM shape-boundary estimation](https://morpheus.gitlab.io/post/2023/09/18/cell-surface-anisotropy/)
- [Morpheus: reproducible cell-surface mechanics](https://morpheus.gitlab.io/post/2023/06/12/cell-surface-mechanics/)
- [Durand and Guesnet: connectivity-preserving CPM algorithm](https://arxiv.org/abs/1609.03832)
- [Nemati and de Graaf: CPM on disordered lattices](https://arxiv.org/abs/2404.09055)
- [Julia performance guidance on specialization](https://docs.julialang.org/en/v1/manual/performance-tips/)
- [StaticArrays documentation](https://juliaarrays.github.io/StaticArrays.jl/stable/)
- [CUDA.jl performance guidance](https://cuda.juliagpu.org/stable/tutorials/performance/)
