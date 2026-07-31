# Compiler layout

The compiler is ordered by ownership stage:

```text
host/source_graph.jl
    freeze qualified source into indexed, host-only compiler data

host/operations.jl
    define the versioned operation-transfer authority

host/normalization.jl
    normalize symbolic expressions into the ordered term DAG

host/energy_domains.jl
    prove conservative energy domains and finite affected-anchor plans

host/analysis.jl
    infer and verify semantic facts over the normalized DAG

lowering/parameters.jl
    lower units, defaults, and runtime parameter indices

lowering/static_evaluators.jl
    lower analyzed DAG nodes into bounded concrete callable expressions

lowering/storage_layouts.jl
    assign canonical state/workspace representations, banks, and slots

lowering/domain_resources.jl
    lower finite spatial relations and relationship resources into value-level lookup tables

lowering/proposal_descriptors.jl
    construct the universal proposal descriptor and occurrence groups

lowering/constraints.jl
    lower prelaunch parameter-domain constraints and assemble the plan

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
evaluator or universal proposal descriptor. Descriptor execution plans require the analyzed
domain-resource table explicitly; there is no default or compatibility construction path.

Every stage file remains a private implementation unit. Further changes must preserve this include
order and may not create alternate lowering entry points.
