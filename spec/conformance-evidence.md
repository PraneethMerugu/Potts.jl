# Specification-to-Conformance Evidence Index

Semantic status: Accepted index structure

Implementation maturity: Phase 13 complete; owner-approved API and contract versions frozen

This index is the authoritative map from accepted semantics to executable evidence. A green
package-local regression suite does not satisfy a row by itself: evidence must exercise a stable
logical contract, a scalar reference, a validator, or a defined statistical procedure.

| Semantic contract | Authoritative executable or archived evidence | Current maturity | Remaining gate |
| --- | --- | --- | --- |
| [State Model](state-model.md) | `lib/CorePotts/test/test_logical_state.jl`, `lib/CorePotts/test/test_logical_initialization.jl`, and `integration/conformance/test_phase13_production_adapter.jl` | Canonical logical/compiled state, validation, initialization, fingerprints, and CPU/Metal/ROCm lowering implemented; historical state graph removed | None in Phase 13 |
| [Time and MCS](time-and-mcs.md) | `lib/CorePotts/test/test_sequential_algorithms.jl`, `lib/CorePotts/test/test_checkerboard_algorithms.jl`, `integration/conformance/test_phase13_sequential.jl`, and checkerboard lifted-state records in `design/evidence/phase-13/exact/` | Sequential exact-`N` attempts and graph-colored normalized sweeps are explicit, tested processes; Lottery remains a limited later consumer | No kinetic or equilibrium interpretation beyond the final guarantee profiles |
| [Transition-Kernel Verification](transition-kernel-verification.md) | `integration/transition/TransitionKernelOracle.jl`; `design/evidence/phase-13/exact/index.toml`; empirical CPU/Metal/ROCm indices; registered CPU/Metal/ROCm realistic records and analyses | Independent primitive/sub-round/MCS oracles complete; sequential declared-law conformance and checkerboard non-equivalence are established; all applicable v2 transition rows pass; the full applicable realistic battery and frozen guarantee profiles are archived | None; negative equivalence results remain explicit limitations |
| [Auxiliary Constraints and Mechanical State](auxiliary-state-semantics.md) | `lib/CorePotts/test/test_scientific_mechanics.jl`, `lib/CorePotts/test/test_logical_lifecycle.jl`, and backend integration matrices | Accepted pressure/tension processes, clocks, replay, and lifecycle laws qualified; rejected historical HST implementation removed | Deferred components receive no Phase 13 claim |
| [Energy, Proposals, and Trackers](energy-proposals-and-trackers.md) | `lib/CorePotts/test/test_scientific_hamiltonians.jl`, `lib/CorePotts/test/test_proposal_acceptance.jl`, `lib/CorePotts/test/test_scientific_transactions.jl`, and Phase 13 oracle energy cross-checks | Adhesion and volume are the Phase 13 admitted transition domain; other implemented component families retain their earlier scoped evidence | Surface, connectivity, and auxiliary mechanics are not implied by the Phase 13 transition matrix |
| [Lifecycle](lifecycle.md) | `lib/CorePotts/test/test_logical_lifecycle.jl`, `lib/CorePotts/test/test_phase8_lifecycle.jl`, and cross-backend integration shards | Open lifecycle transactions, rollback, extinction/reuse, property repair, and compiled execution complete | No Phase 13 transition-law claim for lifecycle events |
| [Persistence](persistence.md) | `lib/CorePotts/test/test_phase8_persistence.jl`, extension tests, integrity/fault fixtures, and prior exact backend continuation records | Canonical checkpoints, strict continuation, logical import, HDF5/Zarr extensions, and integrity checks complete | No new Phase 13 gate |
| [Randomness and Reproducibility](randomness-and-reproducibility.md) | `lib/CorePotts/test/test_rng_semantics.jl`, `lib/CorePotts/test/test_sequential_algorithms.jl`, semantic-address fixtures, and evidence seed/provenance validators | RNG v1 and same-backend replay are frozen; Phase 13 records use fixed independent seed ranges | Future incompatible changes require an explicit versioned release decision |
| [Numerical and Cross-Backend Semantics](numerical-and-cross-backend-semantics.md) | `integration/conformance/ConformanceHarness.jl`, empirical transition validators, and realistic Holm/TOST analysis | Exact, deterministic, moderate statistical, and registered large-ensemble tiers implemented; portable qualification precision is `Float32`; registered CPU/Metal/ROCm evidence is admitted | No broader cross-backend-equivalence claim beyond the bounded admitted evidence |
| [Topology and Spatial Relations](topology-and-spatial-relations.md) | `lib/CorePotts/test/test_topology_abstractions.jl`, `lib/CorePotts/test/test_cartesian_relations.jl`, and Phase 13 von Neumann/Moore and periodic/no-flux exact fixtures | Built-in 2D/3D topology contracts complete; Phase 13 admitted grid is explicit and bounded | New topology families require a new qualification decision |
| [Cartesian Surface, Queries, and Fields](cartesian-surface-queries-and-fields.md) | `lib/CorePotts/test/test_scientific_hamiltonians.jl`, `lib/CorePotts/test/test_scientific_queries_connectivity.jl`, `lib/CorePotts/test/test_scientific_fields.jl`, and backend matrices | Implemented scoped semantics retain earlier qualification | Fields and surface are outside the initial Phase 13 transition claim |
| [CorePotts Public Interfaces](corepotts-public-interface-semantics.md) | `design/audits/phase-13-api-inventory.toml`, package Aqua/ambiguity/inference gates, and `scripts/check_phase13_api_inventory.jl` | Every export classified; stable APIs documented and tested; legacy/provisional production paths removed; final evidence admitted and metadata frozen | None |
| [Sequential Reference Engine](reference-engine-semantics.md) | `lib/CorePotts/src/reference/engine.jl`, reference tests, and independent Phase 13 oracle comparison | Checked CPU reference remains a validation engine, not a production backend | None; its scope remains deliberately narrow |
| [SciML Interface Semantics](sciml-interface-semantics.md) | `lib/CorePotts/test/test_phase9_sciml_interface.jl`, `integration/test_level2_integration.jl`, and backend compatibility reports | Integer-MCS init/step/solve, saving, observations, reports, and explicit algorithm selection complete; frozen guarantee metadata remains distinct from execution preflight | None |
| [PottsToolkit Rule and Model Semantics](pottstoolkit-rule-and-model-semantics.md) | `test/test_level1_authoring.jl`, `test/test_level2_authoring.jl`, `test/test_phase11_fragments.jl`, and reference-model integration tests | One normalized typed compiler path and five reference families complete; historical compiler removed | Deferred features remain outside the paper-core workspace |
| [PottsToolkit Authoring and API Semantics](pottstoolkit-authoring-composition-and-api-semantics.md) | PottsToolkit package suite, `test/test_phase11_inventory.jl`, strict docs/doctests, clean temporary-project exercise, and Phase 13 API inventory | Curated authoring surface, extension contracts, reports, errors, and public lowering complete and frozen | None |
| [Published-Model Reproduction Semantics](published-model-reproduction-semantics.md) | Phase 14 model source records, manifests, registered validation plans, clean-run checks, and content-addressed evidence archives | Specified; no published-model reproduction claim is made by the Phase 10 five-workload or Phase 13 realistic-model evidence | Phase 14.0 corpus audit, Phase 14.1 required-capability conformance, and Phase 14.3 per-model validation |
| [Phase 14 Single Semantic Kernel](phase-14-semantic-kernel.md) | `scripts/check_phase14_0.jl`, registry v2, Decisions 0031–0033, the [GPU-native plan](../design/audits/phase-14-gpu-native-implementation-plan.md), semantic and [generic authoring](../design/audits/phase-14-generic-authoring-simplification-audit.md) simplification audits, accepted 15-question interview, D9/Morpheus traceability matrices, [Wortel CPU/Metal/ROCm evidence](../design/audits/phase-14-wortel-vertical-slice-evidence.md), and the [Wang source/runtime order oracle](../design/audits/phase-14-wang-order-audit.md) | Seven-area architecture and generic hierarchical authoring accepted; Wortel Act G2 passed; Wang Potts/field/Python order and MCS 120/210/211 visibility accepted; contracts remain Provisional beyond proven slices | Implement named typed fragment requirements/exports and generic Wang lowering, then Wang CPU plus Metal/ROCm implementation and qualification; published-model reproduction evidence remains separate |

The Phase 13 inventory distinguishes execution support, scientific qualification, API stability,
and paper scope. An implemented or exported path receives no broader claim than the evidence named
above. The historical engine and compiler are deleted; CI now rejects their reintroduction through
`scripts/check_legacy_containment.jl`.

## Failure Reproduction Record

Every randomized conformance failure MUST report:

- semantic master seed and RNG contract version;
- model fingerprint;
- initial logical-state checksum;
- algorithm, numeric policy, dimension, and backend report; and
- one command that selects the failing suite or case.

The test-only `ReproductionContext` gives all Phase 3 cases a common record now. Final public
provenance is implemented through CorePotts and PottsToolkit interfaces in later phases.
