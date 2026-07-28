# [PottsToolkit API](@id pottstoolkit-api)

PottsToolkit is the preferred biological authoring interface. Use this page as a task map first and
an exhaustive symbol index second.

## Find the API by task

| I need to… | Start with | See it used |
|:--|:--|:--|
| name media and cells | [`Medium`](@ref), [`CellType`](@ref) | [Compose a biological model](@ref build-model) |
| declare volume, shape, or contacts | `Volume`, `Surface`, [`Elongation`](@ref), [`Adhesion`](@ref) | [Adhesion and mechanics](@ref adhesion-and-mechanics) |
| couple a prescribed field | [`Field`](@ref), [`Chemotaxis`](@ref) | [A cell follows a gradient](@ref chemotaxis-example) |
| add growth or lifecycle behavior | [`Growth`](@ref), [`Division`](@ref), [`Transition`](@ref), [`ImmediateDeath`](@ref) | [Cells grow, divide, and retire](@ref growth-division-example) |
| create an executable problem | `CartesianDomain`, [`Layout`](@ref), [`Place`](@ref), `PottsProblem` | [Your first simulation](@ref first-simulation) |
| validate before running | `validate`, `isvalid`, [`backend_report`](@ref) | [Backends and performance](@ref backends-and-performance) |
| retain scientific observations | `ObservationSet`, `CellVolume`, [`observation_policy`](@ref), `observe` | [Observe and analyze](@ref observe-and-analyze) |
| identify a model or run | `semantic_fingerprint`, [`execution_fingerprint`](@ref), [`semantic_manifest`](@ref) | [Compose a biological model](@ref build-model) |

## The normal construction order

```julia
medium = Medium(:Medium)
cell = CellType(:Cell)
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = 36, strength = 2)),
)
problem = PottsProblem(
    model,
    CartesianDomain((64, 64)),
    Layout(Place(cell, initial_mask; identity = 1));
    capacity = 16,
    tspan = (0, 100),
    seed = 42,
)
report = backend_report(problem, SequentialCPM())
```

The model remains reusable; domain, layout, capacity, duration, seed, algorithm, backend, and
observation policy are explicit experiment choices.

Execution algorithms are re-exported for convenient scripts, but CorePotts owns their semantics,
integrators, checkpoints, and guarantee profiles.

## Stable authoring index

```@autodocs
Modules = [PottsToolkit.Authoring]
Order = [:type, :function, :macro]
Filter = is_stable_pottstoolkit
```

## Stable reference-model index

Reference constructors are reusable fixtures and shortcuts after you understand the declarations
they package. The Learn path and gallery intentionally use the direct API so these helpers never
hide the mechanism being taught. They are not automatically published-model reproductions.

```@autodocs
Modules = [PottsToolkit.ReferenceModels]
Order = [:type, :function]
Filter = is_stable_pottstoolkit
```

The index is filtered through the owner-approved Phase 13 stable inventory. Internal and
experimental exports do not appear here; see [Experimental API](@ref experimental-api).
