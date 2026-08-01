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

execution/executable.jl
    define public engine/backend selections and the executable wrapper

host/coverage.jl
    validate compiler choices and complete statement/equation lowering coverage

lowering/parameters.jl
    lower units, defaults, and runtime parameter indices

execution/manifests.jl
    construct compiled statement/state/I/O manifests and time contracts

lowering/evaluator_protocols.jl
    own registered payload metadata, callable admission, and evaluator construction

lowering/evaluator_resources.jl
    resolve typed state, draw, kind, resource, and anchor leaves

lowering/evaluator_nodes.jl
    lower analyzed DAG nodes into bounded concrete callable expressions

lowering/descriptor_footprints.jl
    derive closed descriptor footprints and backend/engine support

lowering/relationship_policies.jl
    compile the single qualified relationship endpoint and runtime-slot authority

lowering/storage_layouts.jl
    submit qualified schemas to CorePotts and map returned canonical handles to compiler identities

lowering/domain_resources.jl
    lower finite spatial relations and relationship resources into value-level lookup tables

lowering/proposal_descriptors.jl
    construct the universal proposal descriptor and occurrence groups

lowering/stage_evaluators.jl
    lower shared stage roots, evaluators, state handles, and support

lowering/accepted_copy_descriptors.jl
    lower accepted-copy assignments and bounded relationship creation

lowering/relationship_stage_descriptors.jl
    lower relationship and lifecycle process effects

lowering/stage_grouping.jl
    group stage descriptors by compiler-owned concrete type

lowering/after_mcs_descriptors.jl
    lower field and history work at the after-MCS boundary

lowering/stage_plan.jl
    orchestrate the closed accepted-copy and after-MCS stage plan

lowering/constraints.jl
    lower prelaunch parameter-domain constraints and assemble the plan

lowering/trackers.jl
    infer, validate, canonicalize, and fingerprint typed derived-state trackers

execution/boundary.jl
    validate that only concrete compiled data crosses into CorePotts

lowering/core_program.jl
    lower non-descriptor universal runtime structures

compile.jl
    orchestrate the passes and assemble the final executable/fingerprint
```

Only `compile.jl` orchestrates the complete pipeline. Host IR and registries never cross
`execution/boundary.jl`. Registered scientific terms may contribute versioned operation callables,
inert descriptor payload metadata, and declared resources; they cannot replace the compiler-owned
evaluator or universal proposal descriptor. Descriptor execution plans require the analyzed
domain-resource table explicitly; there is no default or compatibility construction path.

Every stage file remains a private implementation unit. Further changes must preserve this include
order and may not create alternate lowering entry points.
