# [PottsToolkit API](@id pottstoolkit-api)

PottsToolkit is the preferred biological authoring interface. Its public surface includes model
declarations, normalized composition, problem construction, observation requests, reports,
fingerprints, and reference-model constructors.

Execution algorithms are re-exported for convenient model scripts, but CorePotts owns their
semantics and guarantee profiles. The reference below is filtered through the owner-approved
Phase 13 stable inventory. Internal and experimental exports do not appear here.

## Authoring

```@autodocs
Modules = [PottsToolkit.Authoring]
Order = [:type, :function, :macro]
Filter = is_stable_pottstoolkit
```

## Reference models

Reference models are reusable examples and qualification fixtures. They are not automatically
published-model reproductions.

```@autodocs
Modules = [PottsToolkit.ReferenceModels]
Order = [:type, :function]
Filter = is_stable_pottstoolkit
```

See [Experimental API](@ref experimental-api) for visible provisional names.
