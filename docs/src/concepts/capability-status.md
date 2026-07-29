# [Capability status](@id capability-status)

This matrix distinguishes stable user workflows, stable extension contracts, experimental
interfaces, and unavailable roadmap behavior. Export status alone never changes a row.

| Capability | User support | Extension support | Evidence boundary |
|:--|:--|:--|:--|
| PottsToolkit model composition | Stable | Stable lowering contracts | Frozen stability inventory |
| 2D/3D Cartesian domains | Stable | Stable topology/domain access | Dimension-specific preflight |
| Volume, surface, adhesion, elongation | Stable | Stable component protocols | Component conformance plus applicable algorithm evidence |
| Connectivity constraint | Stable | Stable constraint protocol | Executability is not network validation |
| Prescribed fields and chemotaxis | Stable | Stable field/drive protocols | Mechanism evidence, not assay validation |
| Growth, division, transition, death | Stable | Stable lifecycle protocols | Capacity and generation-aware identity required |
| Typed observations | Stable | Stable observable access | Only declared retained values |
| Canonical checkpoints | Stable | Stable store adapters | Exact restore requires compatibility |
| CPU execution | Stable baseline | Stable backend contract | Clean-install smoke required |
| Metal and AMDGPU | Combination-dependent | Backend extension protocol | Consult `backend_report` and retained evidence |
| MakiePotts 2D and slices | Stable | Stable render-frame protocol | Explicit host materialization |
| Full volume explorer | Experimental | Experimental | Not a stable workflow |
| `Act` facade and persistence examples | Experimental | Experimental | Provisional API registry |
| ProcessBigraphs orchestration | Not yet a public Potts workflow | Qualified internal-beta integration | Public promotion requires a separate API decision |
| Dynamic hierarchy and structural rewiring | Not yet a public Potts workflow | Qualified internal-beta transactions | Public promotion requires a separate API decision |
| Published-model reproduction | No models currently admitted | Separate admission contract | Evidence required per model |

## How status changes

Package maintainers propose classifications. The project owner approves stable promotions.
Unclassified exports fail the API registry check. A successful local run, public export, roadmap
entry, or documentation draft is not a promotion.

Experimental pages must label their status visibly. Internal exports remain implementation
details even when Julia requires them to be exported between repository packages.

## Read machine-readable evidence

- `backend_report` and `compatibility_report` describe executability.
- `algorithm_guarantees` describes scientific profiles.
- `scientific_contract_versions` records frozen semantic identities.
- the frozen stability, provisional additive, and MakiePotts inventories classify public names.

See [Scientific guarantees](@ref scientific-guarantees) for claim interpretation and
[Experimental API](@ref experimental-api) for the visible provisional surface.
