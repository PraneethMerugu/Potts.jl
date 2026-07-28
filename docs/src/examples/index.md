# [Example gallery](@id example-gallery)

Examples are small, reusable programs that demonstrate supported behavior. They are not automatically
published-model reproductions.

![Relaxing-cell example output.](../assets/gallery/relaxing-cell.svg)

| Example | Quantitative contract | Visual |
|:--|:--|:--|
| [Relaxing Cell](@ref relaxing-cell) | Target-volume error trace | Figure |
| [Two Populations Sort](@ref differential-adhesion-example) | Heterotypic contacts and energy contrast | Animation |
| [Follow the Gradient](@ref chemotaxis-example) | Positive centroid displacement | Animation |
| [Grow, Divide, Retire](@ref growth-division-example) | Division increases the population; scheduled retirement removes its typed seed | Animation |
| [Elongated Network](@ref elongated-network) | Elongation trace plus population and connectivity invariants | Animation |
| [Fluctuating Droplet](@ref fluctuating-droplet) | Volume mean and variance | Figure |
| [Boundaries and Obstacles](@ref boundaries-and-obstacles) | Immutable-owner equality | Figure |
| [Same Model in 2D and 3D](@ref same-model-2d-3d) | Both dimensions preflight and complete | Figure |
| [Stop and Resume](@ref stop-and-resume) | Exact final lattice equality | Diagram |
| [Reproducible Ensemble](@ref reproducible-ensemble) | Distinct semantic seeds and final volumes | Figure |

Every page executes a canonical Julia source under `docs/models/examples`. Reusable biological
constructors remain in `PottsToolkit.ReferenceModels`; workflow-specific assertions stay with the
documentation source.

## Example versus reproduction

An **Example** teaches implemented behavior. An **Inspired Example** discloses a literature-derived
simplification. A **Published Model** additionally pins the source, model manifest, validation
target, evidence, deviations, and fidelity classification. See [Published Models](@ref
published-models) for the current portfolio status.

The optional Act examples remain withheld from navigation while Act is experimental.
