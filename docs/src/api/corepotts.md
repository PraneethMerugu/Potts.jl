# [CorePotts API](@id corepotts-api)

CorePotts owns execution, logical state, persistence, backend, observation, and downstream extension
protocols. PottsToolkit is the preferred biological authoring interface.

The index below is filtered through the owner-approved `stable_extension` mapping. Internal and
experimental exports are deliberately absent. For normal workflows begin with:

- `solve`, `PottsSolution`, and snapshot policies;
- `compatibility_report`, `compilation_report`, and `algorithm_guarantees`;
- `capture_checkpoint`, `restore_checkpoint`, and checkpoint stores;
- logical-state accessors such as `active_cell_ids`, `finite_volume`, and `property_value`;
- component validation and conformance helpers for downstream extensions.

```@autodocs
Modules = [CorePotts]
Order = [:module, :constant, :type, :function, :macro]
Filter = is_stable_corepotts
```

The [Extension author reference](@ref extension-author-reference) organizes the protocol by task.
See [Experimental API](@ref experimental-api) for provisional surfaces.
