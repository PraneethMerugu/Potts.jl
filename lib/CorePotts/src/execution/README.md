# CorePotts execution boundary

The mechanism-free device boundary is split by ownership:

- `static_evaluator.jl`: concrete expressions, callables, evaluation, and probe kernels;
- `storage_schema.jl`: typed handles, schemas, layouts, and extension protocols;
- `storage_runtime.jl`: allocation, adaptation, reset, logical codecs, and checkpoint state;
- `descriptor_protocol.jl`: resource footprints and the universal symbolic proposal descriptor; and
- `descriptor_plan.jl`: launch groups, validation constraints, adaptation, and inspection.

PottsToolkit supplies fully analyzed concrete values. CorePotts does not know biological mechanism
names and does not resolve symbols, registries, units, or Symbolics expressions.

`program/v1.jl` is the surviving pre-consolidation runtime. G2 must not add generic symbolic
execution to that file; G3 integrates the cleared descriptor boundary, and G8 removes the legacy
mechanism-specific structures.
