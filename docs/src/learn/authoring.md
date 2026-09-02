# [Author and compose](@id author-and-compose)

A model is a `PottsSystem` containing typed statements. States, parameters,
spatial relations, schedules, and observations remain symbolic until runtime.
`complete` closes declarations and reports source-located errors;
`mtkcompile` performs structural scheduling and is idempotent.

```@example authoring
using Potts
using Symbolics
using ModelingToolkitBase: @parameters

@parameters target = 4.0 strength = 1.0 temperature = 2.0
cell = CellKind(:cell; extinction=RetireAtZero())
medium = MediumKind(:medium)

source = PottsSystem(
    name=:minimal,
    statements=(@statements begin
        Lattice((4, 4); boundary=Periodic())
        cell
        medium
        Volume(cell; target, strength)
        Protocol(Sweep(; temperature); name=:main)
        Observation(:occupied, occupancy(cell, :lattice))
    end),
    parameters=[target, strength, temperature],
)
completed = complete(source)
scheduled = mtkcompile(completed)

(
    iscomplete(completed),
    is_scheduled(scheduled),
    length(inspect(scheduled, Statements())),
    only(inspect(scheduled, Observations())).name,
)
```

Use `@named` when a parent expression should supply the component name. Use
`compose` for hierarchy, `extend` for explicit inherited declarations, and
`flatten` only when a downstream operation genuinely needs a flat namespace.
Namespacing is structural identity, not display metadata.

The stable statement families are:

- domains, cell/media kinds, relations, and stored site/cell/medium/model/field/history state;
- Hamiltonian terms, drives, constraints, modifiers, synchronous and accepted-copy effects;
- lifecycle and relationship processes with explicit policies;
- observations and protocols; and
- native component declarations with typed inputs and outputs.

Inspection (`Statements`, `Variables`, `Effects`, `Schedule`, `Capabilities`,
`StateSchema`, `Observations`, `ReplayContract`, and `LifecyclePlans`) reads the
same completed authority used by lowering. It does not reconstruct a second
model description.
