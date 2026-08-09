# [Observe, checkpoint, and reproduce](@id observe-checkpoint-reproduce)

Saved states expose ownership, generation/kind metadata, declared state, and
requested observations. SymbolicIndexingInterface getters work on problems,
integrators, saved states, and solutions. A declared-but-unsaved observation
raises a different error from an unknown identity.

`checkpoint(integrator)` captures the logical continuation state at a settled
boundary. Restore uses `init(...; checkpoint=...)` with the same scheduled
system and execution identity. Native state, lifecycle generations,
relationships, replica/repeat identity, and replay evidence participate in
compatibility.

```@example replay
using PottsToolkit

cell = CellKind(:cell; extinction=RetireAtZero())
medium = MediumKind(:medium)
scheduled = mtkcompile(PottsSystem(
    name=:replay_example,
    statements=StatementSet((
        Lattice((3, 3); boundary=Periodic()),
        cell,
        medium,
        Protocol(Sweep(; temperature=1.0); name=:main),
    )),
))
labels = zeros(Int, 3, 3)
labels[2, 2] = 1
problem = PottsProblem(
    scheduled,
    PottsInitialState(
        ownership=LabelledCells(labels; cells=[cell], medium),
    ),
    (0, 2);
    seed=0x71,
)
integrator = init(problem, SequentialCPM(); save_start=false)
step!(integrator)
captured = checkpoint(integrator)
restored = init(
    problem,
    SequentialCPM();
    checkpoint=captured,
    save_start=false,
)
step!(integrator)
step!(restored)
integrator.u.ownership == restored.u.ownership
```

`remake` creates a related problem and invalidates only affected materialized
profiles. `replica` identifies an ensemble trajectory; `repeat` identifies a
retry of that trajectory. Both are part of semantic RNG addressing and persist
through checkpoints.
