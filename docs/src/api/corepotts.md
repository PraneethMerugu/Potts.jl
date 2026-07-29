# [CorePotts API](@id corepotts-api)

CorePotts owns execution, logical state, persistence, backend contracts, and downstream extension
protocols. PottsToolkit remains the preferred biological authoring interface.

## Find the API by task

| I need to… | Start with | Contract |
|:--|:--|:--|
| solve a problem | `solve`, `init`, `step!` | algorithm and backend are part of execution identity |
| control saved data | [`HostSnapshotPolicy`](@ref), [`ObservableSnapshotPolicy`](@ref) | no undeclared device synchronization or reconstruction |
| inspect saved logical state | [`snapshot_state`](@ref), [`active_cell_ids`](@ref), [`finite_volume`](@ref), [`property_value`](@ref) | accessors preserve generation-aware identity |
| inspect algorithm evidence | [`algorithm_guarantees`](@ref), [`compatibility_report`](@ref), [`compilation_report`](@ref) | compatibility is not scientific equivalence |
| stop and continue exactly | [`capture_checkpoint`](@ref), [`restore_checkpoint`](@ref) | restore requires exact continuation compatibility |
| begin a related run | [`import_checkpoint`](@ref) | import is explicit and weaker than restore |
| run seeded replicates | `EnsembleProblem`, `EnsembleSerial` | trajectory seeds derive from semantic identity |
| test a downstream implementation | `test_*` and `validate_*` conformance helpers | use the protocol matching the component family |

## Execution boundary

```julia
algorithm = SequentialCPM(temperature = 2.0f0)
report = compatibility_report(problem, algorithm)
report.compatible || error(report)

solution = solve(
    problem,
    algorithm;
    saveat = 10,
    snapshot_policy = HostSnapshotPolicy(),
)
```

Use a complete host policy only when whole-state debugging or rendering requires it. Production
analysis should normally request the smallest typed observation set through PottsToolkit.

## Persistence boundary

```julia
integrator = init(problem, algorithm; save_start = false, save_end = false)
step!(integrator, 50)
checkpoint = capture_checkpoint(integrator)
continued = restore_checkpoint(checkpoint, problem, algorithm)
```

Never catch a restore incompatibility and silently import; that changes the scientific claim.

## Stable extension index

The index below is filtered through the owner-approved `stable_extension` mapping. Internal and
experimental exports are deliberately absent.

```@autodocs
Modules = [CorePotts]
Order = [:module, :constant, :type, :function, :macro]
Filter = is_stable_corepotts
```

The [Extension author reference](@ref extension-author-reference) organizes the protocol by
implementation sequence. See [Experimental API](@ref experimental-api) for provisional surfaces.
