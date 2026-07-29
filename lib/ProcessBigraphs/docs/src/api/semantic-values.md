# Semantic values and identity API

> **Support level:** supported internal beta.

Semantic identity answers whether two declarations mean the same thing, not
whether their mutable runtime objects happen to share storage. Fingerprints
are deterministic across sessions for admitted values and include the
versions and parameters that affect behavior.

```@docs
ProcessBigraphs.semantic_fingerprint
ProcessBigraphs.problem_fingerprint
ProcessBigraphs.origin_map
```

## Inspect schemas without reading representation fields

`schema_at` and `schema_leaves` are the complete supported inspection route.
Do not read `BranchSchema.children`: that tuple is free to change without an
API migration.

```@docs
ProcessBigraphs.schema_at
ProcessBigraphs.schema_leaves
```

```julia
mass_schema = schema_at(schema, path(:cell, :mass))
for (store_path, leaf) in schema_leaves(schema)
    @info "declared leaf" store_path leaf
end
```

Both accessors return immutable semantic values. Mutating a default value
obtained elsewhere cannot alter a compiled model.
