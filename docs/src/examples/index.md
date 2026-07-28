# [Example gallery](@id example-gallery)

Examples are small, reusable programs that demonstrate supported behavior. They are not automatically
published-model reproductions.

| Example | Quantitative contract | Visual |
|:--|:--|:--|
| [Relaxing Cell](@ref relaxing-cell) | Target-volume error trace | Figure |
| [Two Populations Sort](@ref differential-adhesion-example) | Heterotypic contacts and energy contrast | MakiePotts figure |
| [Follow the Gradient](@ref chemotaxis-example) | Positive centroid displacement | MakiePotts figure |
| [Grow, Divide, Retire](@ref growth-division-example) | Division increases the population; scheduled retirement removes its typed seed | MakiePotts figure |
| [Elongated Network](@ref elongated-network) | Elongation trace plus population and connectivity invariants | MakiePotts figure |
| [Fluctuating Droplet](@ref fluctuating-droplet) | Volume mean and variance | Figure |
| [Boundaries and Obstacles](@ref boundaries-and-obstacles) | Immutable-owner equality | Figure |
| [Same Model in 2D and 3D](@ref same-model-2d-3d) | Both dimensions preflight and complete | Figure |
| [Stop and Resume](@ref stop-and-resume) | Exact final lattice equality | MakiePotts figure |
| [Reproducible Ensemble](@ref reproducible-ensemble) | Distinct semantic seeds and final volumes | Figure |

Every page shows and executes its complete canonical Julia source under `docs/models/examples`,
then renders the resulting frame with the native MakiePotts recipe and CairoMakie backend. There is
no parallel custom image pipeline. Reusable biological constructors remain in
`PottsToolkit.ReferenceModels`; workflow-specific assertions stay with the documentation source.

## Example versus reproduction

An **Example** teaches implemented behavior. An **Inspired Example** discloses a literature-derived
simplification. A **Published Model** additionally pins the source, model manifest, validation
target, evidence, deviations, and fidelity classification. See [Published Models](@ref
published-models) for the current portfolio status.

The optional Act examples remain withheld from navigation while Act is experimental.
