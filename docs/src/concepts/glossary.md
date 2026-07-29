# [Glossary](@id glossary)

These terms have precise meanings in this manual. When a scientific paper uses a term differently,
state that difference in the model's provenance record.

| Term | Meaning in Potts.jl |
|:--|:--|
| **Lattice site** | One discrete spatial location holding an owner label. A site is not itself a biological cell. |
| **Medium** | The distinguished non-cell owner occupying lattice sites outside cells. |
| **Cell identity** | The durable biological ID used to join observations and lineage records. It is not a mutable storage slot. |
| **Cell type** | A declared biological category used by interactions and rules. Multiple cells can share one type. |
| **Monte Carlo step (MCS)** | The schedule-defined unit reported by the solver. Its proposal count depends on the chosen algorithm and budget. |
| **Copy attempt** | One proposed change of a recipient site's owner, evaluated by the algorithm's acceptance rule. |
| **Proposal process** | The documented rule for choosing donors, recipients, ordering, and replacement behavior. |
| **Hamiltonian / energy** | The model-specific objective assembled from registered components. It is not automatically a physical free energy. |
| **Energy difference (`ΔH`)** | The proposed move's evaluated change in the configured objective. |
| **Temperature** | The acceptance-policy parameter controlling uphill moves. It has physical units only when the model establishes that calibration. |
| **Topology** | Neighborhood and adjacency semantics of the domain. |
| **Boundary condition** | The rule at a domain edge, such as periodic or fixed behavior. |
| **Observation** | A declared, typed measurement retained at a defined schedule boundary. |
| **Snapshot** | An observation-facing representation of state at a time; retention policy determines what is available later. |
| **Checkpoint** | Canonical continuation state intended for exact compatible restart. It is stronger than a visualization frame or imported lattice. |
| **Semantic RNG** | Randomness assigned by documented semantic keys so identity does not depend accidentally on storage order. |
| **Preflight** | Compatibility evaluation of the exact model, algorithm, backend, dimension, and policy before execution. |
| **Fingerprint** | A deterministic identity for a model or execution contract used in comparison and provenance. |
| **Stable** | Covered by the documented compatibility and migration policy for its public API class. |
| **Experimental** | Visible for evaluation but allowed to change; successful execution is not a stability promise. |
| **Qualified claim** | A bounded claim backed by the named evidence tier, exact algorithm, backend, precision, and model class. |

For operational choices, continue with [Capability status](@ref capability-status). For distinctions
between compatibility and scientific evidence, see
[Scientific guarantees](@ref scientific-guarantees).
