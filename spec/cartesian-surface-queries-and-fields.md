# Cartesian Surface, Queries, and Fields

Status: Accepted except where explicitly marked otherwise

## Purpose and Scope

This document completes the refactor-critical Cartesian spatial contract. It defines boundary
measurement, fixed owner domains, core spatial queries, spatial-field identity, and chemotactic
sampling. Hexagonal and irregular graph lattices remain Deferred or Experimental.

## Boundary Measures

### Owner Incidences

For an owner `a`, metric relation `R`, and realized directed incidence `(x, y)`:

```text
x contributes to boundary(a) iff owner(x) == a and owner(y) != a
```

The per-owner boundary is the sum over outward incidences from sites owned by that owner. An
interface between two finite cells contributes to both cells' individual measures. An interface
between a finite cell and a medium or wall domain contributes to the finite cell.

Distinct cells of the same type form a boundary. Equal owner identity is the only identity-based
condition that removes an interface.

A global interface measure instead sums canonical undirected unlike-owner edges once. Per-owner
boundary and global interface measure MUST NOT be obtained from one another without accounting for
their different incidence multiplicity and owner filters.

### Metric Families

The following are distinct metric types:

1. `BoundaryEdgeCount` — exact number of outward incidences
2. `WeightedBoundaryCount` — sum of declared relation weights
3. `NormalizedBoundaryMeasure` — a declared lattice estimator lowered to geometric units
4. `PhysicalBoundaryMeasure` — perimeter in 2D or surface area in 3D with physical units

Dimension-generic code uses `BoundaryMeasure`. User-facing documentation uses perimeter in 2D and
surface area in 3D. The unqualified phrase "surface area" MUST NOT describe a 2D raw edge count.

Metric descriptors include dimension, relation identity, weights, normalization scheme and version,
physical spacing, and accumulator policy. Equality of descriptors is structural and permits tracker
sharing.

### Accumulation and Targets

`BoundaryEdgeCount` uses a checked integer accumulator. Its target MUST be exactly representable as
an integer; implicit rounding is forbidden.

Weighted, normalized, and physical measures use the numerical policy's declared floating
accumulator. A physical target is interpreted as length in 2D and area in 3D, but model inputs remain
plain numbers and no Unitful value is lowered. Optional unit annotation is solution-side
post-processing under Decision 0026.

Conversion between metric families is explicit, versioned, and reported. A tracker field MUST NOT
be generically named `surface_areas` when its metric cannot be recovered from its schema or compiled
model report.

### Tracker Law

For every metric descriptor `M`:

```text
tracked_M(owner) == recompute_M(lattice, domain, relation_M, owner)
```

after every committed transaction. A proposal delta is computed from the pre-commit snapshot and
applied exactly once on commit. Weighted and raw deltas may coexist and are not derived from one
another unless their descriptor provides an exact conversion.

Finite-cell trackers are allocated only when required. Medium and wall boundary measures are
available through explicit domain or global queries; they are not automatically allocated in the
finite-cell property schema.

## Normalized Surface Mechanics

### Reference Normalized-Kernel Measure

The first native literature-backed estimator is `NormalizedKernelMeasure`. For a symmetric relation
with unweighted incidence sum `K`, lattice spacing scale `a`, spatial dimension `d`, and published
correction factor `xi`:

```text
S_normalized = K * a^(d - 1) / xi
```

For anisotropic spacing, the estimator MUST provide a derived direction-aware conversion rather than
substitute one scalar `a`. If no validated conversion exists, compilation rejects physical
normalization while raw and explicitly weighted metrics remain usable.

The relation, `xi`, calibration method, source, and table version are scientific provenance. A bare
`isotropic=true` flag and a universal inverse-distance rule are forbidden.

`IsotropicCartesianCPM` uses first-shell copy proposals and is intended to use a fourth-order square
kernel in 2D and sixth-order cubic kernel in 3D. The exact calibration table is versioned. Advertising
isotropy or cross-resolution equivalence requires the rotational and scaling conformance suite.

### Experimental Estimators

Direction-class and Crofton-style quadrature can provide different orientation-error behavior. Such
estimators are Experimental until their 2D and 3D derivations, weights, local/global delta law,
resolution scaling, and benchmark tolerances are accepted. They use separate names and MUST NOT
silently replace the normalized-kernel reference.

## Contact and Surface Energy

Contact and surface components independently select a relation and metric. Compatibility presets may
use, for example, a first-order perimeter relation and a higher-order contact relation.

For a finite cell `c`, the ordinary conservative surface Hamiltonian is:

```text
H_surface(c) = lambda_surface(c) * (S(c) - S_target(c))^2
```

The total surface energy is the sum over applicable finite cells. A host API accepting physical
Hookean stiffness `kappa` lowers it using the documented convention
`lambda_surface = kappa / 2`.

Physical contact coefficients have energy per length units in 2D or energy per area units in 3D and
multiply the declared physical contact quadrature. Lattice-scaled `J` values instead name their raw
or weighted lattice metric. Changing a relation does not reinterpret either parameter silently.

`SurfaceConstraint` defaults to this ordinary Hamiltonian and provides global energy plus exact
local delta. An equilibrium auxiliary formulation is selected explicitly and must satisfy
[Auxiliary Constraints and Mechanical State](auxiliary-state-semantics.md). A fluctuating-surface-
tension component is distinct mechanical state. Neither auxiliary category may be selected silently
or presented as an implementation detail of the ordinary quadratic constraint.

## Fixed Owners and Obstacles

### Closed Boundary

A closed CPM boundary realizes no ownership edge beyond the domain. It has no exterior owner and
contributes no contact or boundary measure. Conventional bulk-direction proposals may still select
the invalid direction as a null attempt under the accepted proposal law.

### Fixed Exterior

`FixedExterior(domain_owner)` realizes an immutable owner beyond a declared face. It can contribute
to contact energy, finite-cell boundary measure, spatial queries, and field coupling. It is never a
recipient site and does not contribute to finite-domain volume.

The exterior owner is a medium or wall domain with type-level properties. It has no finite-cell ID,
slot generation, volume target, division, death, or per-cell lifecycle.

### Obstacles

`Obstacle(mask, owner=wall_domain)` excludes masked storage locations from the mutable ownership
site set. Its interface is realized against the declared immutable domain owner. Masked storage is
not an ordinary lattice site, recipient, or lifecycle participant.

Let `N` be the number of mutable ownership sites after exclusions. The reference MCS budget is `N`,
not the backing array's element count. Implementations may retain rectangular masked storage for GPU
efficiency but MUST sample mutable recipient sites uniformly according to the declared proposal law.

### Immobilized Finite Cells

An immobilized biological cell remains a finite cell with ordinary ID, generation, type, properties,
and ownership sites. A named hard constraint prevents selected copy transitions. It is not converted
to a wall domain. Whether it may grow, die, or divide is controlled by separately declared lifecycle
rules.

### Mutation Safety

Exterior and obstacle owners are immutable. A statically evident attempt to mutate them is a model
compilation error. A dynamically constructed invalid transaction is rejected and counted in a
diagnostic category; it MUST NOT be committed partially.

CPM ownership boundaries and field boundaries are independent. A closed ownership boundary is not
synonymous with a field Neumann condition, and a fixed owner is not synonymous with a field
Dirichlet value.

## Core Spatial Queries

### Query Vocabulary

The core API uses names that reveal the aggregation:

- `contact_edge_count`
- `contact_measure`
- `boundary_site_count`
- `neighbor_cells`
- `neighbor_cell_count`
- `neighbor_property_sum`
- `neighbor_property_mean`
- `global_interface_measure`

The ambiguous names `ContactArea` and unqualified `neighbor_count` are removed from the primary API.
Compatibility aliases, if temporarily retained, emit migration guidance and preserve one documented
legacy meaning.

### Edge and Site Queries

For queried owner `a` and owner filter `F`:

- `contact_edge_count(a, F)` counts outward realized incidences from `a` whose other owner matches
  `F`.
- `contact_measure(a, F, metric)` sums the selected metric weight over those incidences.
- `boundary_site_count(a, F)` counts sites owned by `a` that have at least one matching outgoing
  incidence, once per owned site.
- `global_interface_measure(F1, F2, metric)` counts canonical undirected matching interfaces once.

The word area appears only when the returned metric is a physical area.

### Distinct-Owner Queries

`neighbor_cells(a, F)` denotes the set of distinct neighboring finite-cell identities reached by the
query relation. Contact multiplicity does not duplicate an identity. Its ordinary query form makes
no semantic ordering promise. An explicitly ordered host query MAY return canonical stable-identity
order; device reductions need not materialize a set if they produce the same scientific result.

`neighbor_cell_count` is the cardinality of that set. `neighbor_property_sum` reads each matching
finite cell once and sums its property once. `neighbor_property_mean` uses the same distinct set.

Medium and wall domains are excluded from `neighbor_cells` unless an owner-domain query is explicitly
requested. A property query including a domain owner requires that property to exist at the domain
type level.

### Filters

Every query declares whether its filter matches cell identity, cell type, medium domain, wall domain,
owner category, or a compiled predicate. A type filter and identity filter are never inferred from
the same integer.

### Empty and Snapshot Behavior

Counts and sums over an empty set return their additive zero. `any` returns `false` and `all` returns
`true`. Mean, minimum, and maximum produce a semantic error for an empty set unless the query supplies
an explicit empty policy. Host and device meanings are identical; a dynamically discovered device
failure uses the accepted transactional device-error mechanism rather than returning `missing`,
synchronizing silently, or partially committing a rule.

All queries in one rule-evaluation phase observe the same lattice ownership and property snapshot.
Writes from that phase become visible only at the next declared phase. Query cache construction is a
derived computation and MUST reproduce an independent evaluation from the same snapshot.

Integer counts and canonical identity results are exact and deterministic. Floating reductions obey
the numerical-backend contract and expose their determinism or conformance level.

## Spatial Fields

### Explicit Sampling Location

A field sample always names its spatial argument. Level 1 may use callable field values such as
`field(site)` and `field(center(cell))`, reductions such as `mean(field, sites(cell))`, and an
explicit differential operator such as `gradient(field, center(cell))` when supported by the field
descriptor. Calling `field(cell)` does not silently select a center value, site average, centroid
interpolation, membrane value, or another aggregate.

Proposal-local coupling laws independently declare their donor/recipient, source/destination, or
other sampling locations. Cell-level sampling syntax never changes the accepted chemotaxis law.

### Field Identity

A `SpatialField` is not a bare array. Its semantic descriptor contains:

- Geometry, axes, origin, extent, and spacing
- Dimension and shape
- Cell-centered, vertex-centered, or edge-centered placement
- Boundary condition on every face
- Value units and element type
- Semantic time stamp
- Backend ownership
- Interpolation policy
- Provenance and compatibility target

An array may be wrapped with `SameAsPottsLattice()` only when its shape, placement, dimension, and
boundary declaration are compatible. No constructor silently reshapes, rescales, transposes, or
changes periodicity.

### Independent Resolution

A field may be coarser or finer than the CPM lattice. Every CPM-to-field sample then uses an explicit
interpolation policy such as nearest-site, multilinear, or conservative cell average. Sampling is
defined in physical coordinates, not by reusing CPM array indices.

Interpolation declares exterior behavior and differentiability where relevant. Backend
implementations MUST agree within the numerical policy's advertised tolerance.

### Boundary Conditions

Each field independently declares periodic, Dirichlet, Neumann, Robin, or another supported
condition. Potts may offer a convenience that copies compatible CPM boundary choices, but the
resulting field conditions remain explicit in the compiled report.

Field no-flux means zero normal flux or derivative under the selected discretization. It does not
mean an absent CPM ownership edge.

## Chemotaxis

### Component Category

Native chemotaxis is a nonconservative drive. It reports chemotactic work or log bias separately from
Hamiltonian energy. A conservative external-field coupling is separately named and must satisfy the
global/local energy law.

The primary drive API is not named `ChemotaxisPenalty`.

### Response Law

For donor position `x_d`, recipient position `x_r`, response function `phi`, and sensitivity
`lambda`, the elementary extension contribution is:

```text
work_chem = -lambda * (phi(c(x_r)) - phi(c(x_d)))
```

Field values are sampled at physical site centers through the field interpolation contract. This is
a finite potential difference over the proposal displacement and is not divided by distance. A
directional-derivative model is separately named.

The native response families are:

```text
LinearResponse:                 phi(c) = c
MichaelisMentenResponse(s):     phi(c) = c / (s + c)
SaturationLinearResponse(s):    phi(c) = c / (1 + s*c)
```

`LogScaledResponse(s)` is a separate compatibility law whose sensitivity depends on a declared
center-of-mass field sample. Every response declares its parameter units and valid concentration
domain. Values crossing a singularity produce validation or execution error according to whether
the violation is statically detectable; silent clamping is forbidden.

The historical `difference / (s + abs(difference))` formula is not a native saturation response. It
may exist only under an explicit legacy name and makes no CC3D saturation claim.

### Responding-Owner Modes

Chemotaxis declares one of:

- `ExtensionChemotaxis` — the gaining non-medium cell responds
- `RetractionChemotaxis` — the losing finite cell responds
- `ReciprocalChemotaxis` — both contribute using declared parameters
- `InterfaceChemotaxis(filter)` — response is restricted to selected owner interfaces

The native simple preset is `ExtensionChemotaxis` with `LinearResponse`. No generic implementation
infers a mode from whichever owner happens to have a nonzero parameter. Compatibility presets expose
source-specific regular, reciprocated, saturation, and interface modes.

### Snapshot and Time

All proposals in one transaction round observe one immutable field snapshot and its semantic time
stamp. A field update becomes visible only at a declared synchronization point. It MUST NOT appear
partway through a simultaneous batch.

The exact Lie, Strang, or other operator splitting; PDE substeps; secretion; uptake; and conservation
laws belong to a separately scoped evolving-field semantics phase after the Phase 13 core. A
selected Phase 14 published model promotes only the laws it actually requires through Decision
0029's reference-first semantic gate. The present contract does not freeze a speculative universal
coupled-problem or split-integrator API. The compiled model nevertheless reports every CPM/field
synchronization point and rejects sampling a field whose time relation is undefined.

### Backend Residency

During GPU execution, field storage, interpolation, drive evaluation, and any compiled source/sink
accumulation remain on the active backend. Host synchronization inside MCS execution is forbidden
except for an explicitly requested diagnostic, observation, or saving operation.

## Deferred Features

The following do not block the Cartesian refactor:

- Arbitrary custom exterior boundary programs
- Hexagonal and graph-lattice surface quadrature
- Crofton estimators as native defaults
- Secretion, uptake, PDE stepping, or operator-splitting families not promoted by the selected
  published-model corpus
- Membrane-local or moving-mesh fields
- Every possible spatial aggregation

Their extension points are reserved, but their semantics MUST NOT be guessed from the present core
contract.

## Conformance Evidence

### Metrics

- Exact local delta versus full recomputation for every metric descriptor
- Checked overflow tests for raw counts
- No implicit target rounding
- Published correction-factor fixtures
- 2D and 3D resolution-scaling fixtures
- Rotated square, circle, cube, and sphere orientation-error profiles
- Young-Laplace and single-cell surface-mechanics reference problems

### Domains and Clock

- Closed, fixed-exterior, obstacle, and immobilized-cell fixtures
- No mutation of immutable domain owners
- Uniform recipient sampling over mutable sites
- Exact reference attempt budget using mutable-site `N`
- Independence from backing-array padding and obstacle storage

### Queries

- Hand-enumerated edge, site, distinct-owner, and global-interface fixtures
- Same-type distinct-cell interfaces
- Medium and wall filter behavior
- Empty reductions and snapshot visibility
- Exact CPU/GPU identity and integer-count results

### Fields and Chemotaxis

- Aligned, coarse, and fine field interpolation fixtures
- Independent CPM and field boundary fixtures
- Exact named response-law values
- Extension, retraction, reciprocal, and filtered-interface fixtures
- Transaction-round snapshot tests
- Backend residency and forbidden-synchronization checks
- Version-pinned cross-simulator compatibility fixtures

## Literature and Software Basis

- [Magno, Grieneisen, and Marée: cell surface mechanics and CPM scaling](https://doi.org/10.1186/s13628-015-0022-x)
- [Morpheus: reproducible cell-surface mechanics](https://morpheus.gitlab.io/post/2023/06/12/cell-surface-mechanics/)
- [Morpheus: neighborhood anisotropy](https://morpheus.gitlab.io/post/2023/09/18/cell-surface-anisotropy/)
- [CompuCell3D chemotaxis response laws](https://compucell3dreferencemanual.readthedocs.io/en/4.3.0/chemotaxis_plugin.html)
- [Morpheus field and cell boundary distinctions](https://morpheus.gitlab.io/faq/modeling/boundary-conditions/)
- [Artistoo chemotaxis and coarse-grid field interface](https://artistoo.net/class/src/hamiltonian/ChemotaxisConstraint.js~ChemotaxisConstraint.html)
- [MethodOfLines field grids and placement](https://docs.sciml.ai/MethodOfLines/stable/)
