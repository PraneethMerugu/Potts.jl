# CorePotts execution boundary

`descriptor_runtime.jl` owns the mechanism-free device boundary:

- concrete static expressions and callables;
- typed state/workspace handles and storage;
- the universal symbolic proposal descriptor;
- descriptor launch groups and validation constraints;
- adaptation, logical codecs, inspection, and probe kernels.

PottsToolkit supplies fully analyzed concrete values. CorePotts does not know biological mechanism
names and does not resolve symbols, registries, units, or Symbolics expressions.

`program/v1.jl` is the surviving pre-consolidation runtime. G2 must not add generic symbolic
execution to that file; G3 integrates the cleared descriptor boundary, and G8 removes the legacy
mechanism-specific structures.
