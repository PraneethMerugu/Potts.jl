# CorePotts execution boundary

The mechanism-free device boundary is split by ownership:

- `static_evaluator.jl`: concrete expressions, callables, evaluation, and probe kernels;
- `storage_schema.jl`: typed handles, schemas, layouts, and extension protocols;
- `storage_runtime.jl`: allocation, adaptation, reset, logical codecs, and checkpoint state;
- `descriptor_protocol.jl`: resource footprints, structural Hamiltonian roles, and the universal
  compiler-owned proposal descriptor;
- `domain_resources.jl`: value-level contact-offset and relationship-storage lookup tables;
- `descriptor_plan.jl`: closed launch groups, validation constraints, adaptation, source-order
  folding, and inspection; and
- `hamiltonian_runtime.jl`: immutable before/after views and finite affected-anchor energy
  differences. It is included after `program/v1.jl` because the views wrap its runtime types.

PottsToolkit supplies fully analyzed concrete values. CorePotts does not know biological mechanism
names and does not resolve symbols, registries, units, or Symbolics expressions.

Production plans contain only `ProposalDescriptor` values. They extract the compiler-supplied
`StaticEvaluator` directly and traverse it through a private CorePotts walker; public evaluator,
expression, and operation wrappers are inspection/probe conveniences and are never production
dispatch points. No public descriptor-evaluation hook exists. Registered extensions may provide
versioned concrete operation callables and inert payload codecs, but payload types cannot replace
evaluation, adaptation, grouping, source ownership, or resource selection. Hamiltonian domain
resources and auxiliary-state banks are explicit plan/runtime values and are required at plan
construction.

`program/v1.jl` is the surviving pre-consolidation runtime. G2 must not add generic symbolic
execution to that file; G3 integrates the cleared descriptor boundary, and G8 removes the legacy
mechanism-specific structures.
