# Compiler layout

The compiler is ordered by ownership stage:

```text
host/ir.jl
    freeze source → normalize expressions → analyze semantic facts

lowering/parameters.jl
    lower units, defaults, and runtime parameter indices

lowering/descriptors.jl
    lower the analyzed DAG → callable evaluator → universal descriptor
    assign state/workspace layouts → group occurrences → validate domains

execution/executable.jl
    define public engine/backend selections and the executable wrapper

execution/boundary.jl
    validate that only concrete compiled data crosses into CorePotts

lowering/core_program.jl
    lower non-descriptor universal runtime structures

compile.jl
    orchestrate the passes and assemble reports/fingerprints
```

Only `compile.jl` orchestrates the complete pipeline. Host IR and registries never cross
`execution/boundary.jl`. Registered scientific terms may contribute versioned operation callables,
inert descriptor payload metadata, and declared resources; they cannot replace the compiler-owned
evaluator or universal proposal descriptor.

The large stage files remain private implementation units during G2. Further splits must preserve
this include order and may not create alternate lowering entry points.
