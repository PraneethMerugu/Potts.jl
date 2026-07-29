# Potts.jl

```@raw html
<div class="potts-hero">
  <div>
    <div class="potts-kicker">Composable Cellular Potts modeling in Julia</div>
    <p class="potts-hero-copy">
      Declare cell types, mechanics, fields, lifecycle rules, observations, algorithms, and
      visualization as explicit parts of one reproducible experiment.
    </p>
    <div class="potts-actions">
      <a href="learn/first-simulation/">Build your first simulation</a>
      <a href="examples/">Explore the visual gallery</a>
    </div>
  </div>
  <img src="examples/sorting-preview.svg"
       alt="Two cell populations sorting beside their measured heterotypic-contact trace">
</div>
```

The image above is not a hand-authored illustration. It is produced during this documentation
build by the complete [differential-adhesion example](@ref differential-adhesion-example), using
MakiePotts on saved engine state.

## A model is a readable scientific object

Here is a complete simulation—not a wrapper around a hidden reference problem.

```@example homepage
using PottsToolkit
using MakiePotts
import CorePotts

medium = Medium(:Medium)
cell = CellType(:Cell)
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = 30, strength = 2)),
    Adhesion(
        (medium, medium) => 0,
        (medium, cell) => 8,
        (cell, cell) => 0,
    ),
)

mask = falses(18, 18)
mask[8:11, 8:11] .= true
problem = PottsProblem(
    model,
    CartesianDomain(size(mask)),
    Layout(Place(cell, mask; identity = 1));
    capacity = 2,
    tspan = (0, 15),
    seed = 2026,
)
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 3.0f0);
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
frames = renderframes(solution)
nothing # hide
```

```@example homepage
using CairoMakie

figure = Figure(size = (880, 390))
before_axis = Axis(figure[1, 1]; title = "Initial state", aspect = DataAspect())
after_axis = Axis(figure[1, 2]; title = "After 15 MCS", aspect = DataAspect())
before_plot = pottsplot!(before_axis, first(frames); boundaries = true)
pottsplot!(after_axis, last(frames); boundaries = true)
potts_legend(figure[1, 3], before_plot)
figure
```

That same public vocabulary scales to prescribed fields, cell properties, division and retirement,
typed observation, checkpointing, ensembles, two- and three-dimensional domains, and qualified CPU
or GPU execution.

## Choose a path

| Goal | Start here | Continue with |
|:--|:--|:--|
| Run the engine for the first time | [Install and verify](@ref install-and-verify) | [Your first simulation](@ref first-simulation) |
| Build a biological model | [Compose a biological model](@ref build-model) | [Adhesion and mechanics](@ref adhesion-and-mechanics) |
| Couple a field | [Fields and chemotaxis](@ref fields-and-chemotaxis) | [A cell follows a gradient](@ref chemotaxis-example) |
| Add lifecycle behavior | [Rules and lifecycle](@ref rules-and-lifecycle) | [Grow, divide, retire](@ref growth-division-example) |
| Design a reproducible study | [Research workflow](@ref research-workflow) | [Reproducible ensemble](@ref reproducible-ensemble) |
| Extend or integrate the engine | [Architecture](@ref architecture) | [Extension author reference](@ref extension-author-reference) |

## Three packages, three responsibilities

| Package | Use it for |
|:--|:--|
| `PottsToolkit` | Public model authoring, domains, initialization, rules, observations, and backend preflight |
| `CorePotts` | Solving, integrators, algorithms, checkpoints, ensembles, and extension protocols |
| `MakiePotts` | Semantic frames, encodings, Makie recipes, inspection, and recording |

Start with `using PottsToolkit`. Import `CorePotts` when selecting lower-level execution or
persistence operations, and add a Makie backend plus `MakiePotts` when producing figures or
animations.

ProcessBigraphs is a fourth, independently documented orchestration package in
qualified unpublished internal beta. Its
[standalone manual](https://praneethmerugu.github.io/Potts.jl/ProcessBigraphs/dev/) teaches typed stores,
multirate composition, engine adapters, structural transactions, replay, and
the complete inline Wortel and Merks source-bounded case studies. It is not
part of the public three-package workflow above.

## Scientific boundary

The manual distinguishes implemented mechanisms from qualified scientific claims. Pinned example
trajectories demonstrate APIs and bounded contracts; they are not automatically equilibrium
studies, published-model reproductions, or backend-agreement evidence. See
[Scientific guarantees](@ref scientific-guarantees) and
[Capability status](@ref capability-status) before making a stronger claim.
