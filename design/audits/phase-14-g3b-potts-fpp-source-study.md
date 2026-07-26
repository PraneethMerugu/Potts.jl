# Phase 14 G3-B Wang/CC3D Potts and FPP Source Study

Status: accepted as a pinned semantic reference; controlled Potts.jl fixtures are the qualification
mechanism; no live CC3D oracle or runtime dependency

Date: 2026-07-25

## Source identity

The study pins Wang source commit
`60ebcf013aafefdff39ebe566114ee79f2a6e54d` and CompuCell3D tag `4.2.5`, commit
`4ca1f2919a5da53111d2027d2e00b626aba1cd28`.

| Source | SHA-256 | Relevant symbols or lines |
|---|---|---|
| Wang radial XML `fpp_polarity_force.xml` | `50f2c66d58ff85532bad671d90e6a247a101444a86324cca2b486f5ff98a6ee9` | 11–18, 27–33, 50–55, 66–89 |
| Wang steppables | `2633fd41c85b5256b2d2975b9bc60b28271bb1f7dd1c9b72e015788ac847cc30` | 220–238, 241–305 |
| `Potts3D.cpp` | `f50b155ca036c469d135d2bc292b5f9cf3048b2748e032aa42a19c07fec77574` | `metropolisFast`, 793–918; `update`, 1487–1507 |
| `BoundaryStrategy.cpp` | `8e71bea1b987abfbdcabcde1cc082814d8367ed154c2341854a36c26a71573a4` | constructor 58–70; offset construction 384–472; order selection 945–1039; lookup 1124–1183 |
| `NeighborFinder.cpp` | `e33d9215ea9ab57cf6c52bcae7f78d3fef7595c33728d7505fce52fa894dfae2` | `getMore`, 30–53; `addNeighbors`, 55–100 |
| `Simulator.cpp` | `731f0d8172b88f601548e9d955d2c3926ae784b197bea2d59e3e13ac7a90fbcd` | boundary parsing 742–771 |
| `FocalPointPlasticityPlugin.cpp` | `900adcfcc6559aa1ff897b100689ef00014f9482fb955057b9fc87c7c0c4a94f` | proposal, energy, accepted-copy callback, and removal symbols recorded in the focal-topology audit |
| `ExternalPotentialPlugin.cpp` | `7e87a6d130b6195db1da33f3743167faf081c48a66edb4053e03e2a1645324ba` | dispatch 95–130; pixel BYCELLID law 571–685 |

## Decided source semantics

Wang does not declare Potts boundary tags. `BoundaryStrategy` constructs all axes as no-flux, and
`Simulator` changes them only when a Potts boundary element is present. The Potts lattice is
therefore closed even though the secretome field has independent periodic X/Y boundary elements.
This distinction is now explicit in the assembled fixture.

For the 256×256×1 square lattice, CC3D builds neighbor orders as Euclidean-distance shells:

| Order | Newly included squared distance | Cumulative 2D direction count |
|---:|---:|---:|
| 1 | 1 | 4 |
| 2 | 2 | 8 |
| 3 | 4 | 12 |
| 4 | 5 | 20 |

Thus Wang uses eight proposal directions (`Potts/NeighborOrder=2`), twenty ordinary-contact
directions (`Contact/NeighborOrder=4`), and twelve candidate directions for the FPP plugin
(`FocalPointPlasticity/NeighborOrder=3`). `static_relation` canonicalizes the same exact sets for
the portable profile. CC3D's equivalent-distance insertion order is retained only as source
evidence; portable permutation uses the registered Philox namespace and does not claim
`std::rand` bit replay.

`metropolisFast` performs exactly `x*y*z*flip2DimRatio` activated attempts per MCS. Each attempt
draws a recipient site and a direction independently, rejects invalid/no-op cases, evaluates the
registered energy stack, and applies the accepted copy. Potts.jl's budgeted sequential algorithm
matches that accounting and visibility contract while assigning randomness to semantic counters.

The Wang energy stack is:

- quadratic volume, target 50.24 and strength 4;
- quadratic nearest-face surface, target 25 and strength 4;
- symmetric contact values Medium/Medium -1, Medium/cell -2, cell/cell -6 over order 4;
- local FPP activation -50, maximum degree four, order-3 candidate search, initial payload
  0/0/100000, then scheduled retune to the selected strength/8/12; and
- pixel-based BYCELLID external potential from the per-cell vector coefficients.

Controlled fixtures cover spring energy, extinction subtraction, capacity and degree rejection,
accepted-copy publication, canonical overlength cleanup, stale generations, vector-boundary
gaining/losing/two-cell/periodic/zero cases, and CPU/portable execution.

## Intentional normalizations

- Potts.jl uses explicit closed domain descriptors rather than CC3D's implicit no-flux default.
- Relation direction IDs are stable canonical IDs. Exact neighbor sets and shell membership are
  source-derived; portable random permutations are Philox-addressed.
- Relationship state is generation-aware and capacity-bounded.
- The field remains independently periodic; no Potts periodicity is inferred from PDE settings.

## Uncertainty register

1. Ordinary CC3D FPP uses `std::random_shuffle`; its exact permutation depends on the archived C
   runtime and seed state. No bitwise portability claim is made.
2. The inspected radial XML declares 391 steps, while the preregistered G3-B assembly extrapolates
   the same source schedules through source MCS 499/target MCS 500. The 500-MCS run is a closure
   workload, not evidence that this exact XML requested 500 steps.
3. Equivalent-distance native order is implementation evidence for CC3D test mode, not a public
   Potts.jl direction-order promise.

## Qualification mapping

- `lib/CorePotts/test/test_phase14_contact_relationships.jl`
- `lib/CorePotts/test/test_phase14_relationship_processes.jl`
- `lib/CorePotts/test/test_phase14_vector_boundary_potential.jl`
- `integration/conformance/test_phase14_wang_runtime.jl`

CC3D is studied and cited here as the semantic authority because Wang used it. Potts.jl is
qualified by deterministic, source-derived fixtures and its own CPU/portable execution paths.
