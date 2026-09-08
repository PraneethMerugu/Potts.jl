# [Architecture](@id architecture)

Potts.jl separates symbolic model authority, numerical execution, and presentation:

```text
Potts
  PottsSystem + native MTK component islands
          │ complete / structural mtkcompile
          v
  scheduled PottsSystem + coupling schemas
          │ PottsProblem / init / solve
          v
CorePotts CPM runtime <-> native SciML component integrators
     │ uses                    │ publishes settled observations
     v                         v
LocalMath              MakiePotts / analysis
     │ portable launches
     v
KernelAbstractions
```

## Potts

Potts owns the public symbolic and SciML-facing product:

- typed Potts statements, names, hierarchy, units, parameters, and observations;
- composition, completion, validation, source-located diagnostics, and inspection;
- structural `mtkcompile` and explicit component IO, time, scope, and coupling schedules;
- `PottsProblem`, late private lowering, integrator/solution integration, and symbolic indexing.

Source component bindings follow one chain: `PottsSystem(imports=...)` and
`ComponentReference` declarations in `systems.jl` → the existing source inventory
and `completion/component_imports.jl` → ordinary MTK-scoped symbols and qualified
statement records → the unchanged evaluator/state execution path. Imports do not
create a runtime registry or additional state. `component_replacement.jl` rebuilds
source and asks completion to validate it; it does not modify compiled plans.
Synchronous writer uniqueness is checked after qualification in
`completion/qualification.jl`, so aliases cannot conceal multiple writers.
The validator examines individual effects, including repeated targets inside
one process. `compiler/host/coverage.jl` validates their common iteration domain;
`compiler/lowering/stage_plan.jl` assigns each effect its own descriptor and
scratch slot, using its indexed normalized expression root. CorePotts owns
boundary-entry evaluation and publication; Potts does not execute assignments.
`test/test_compound_effects.jl` exercises this path through public models.
`completion/inference.jl` retains actual effect RHS reads even when the same
process writes those states. `compiler/host/footprints.jl` gives direct site-state
reads their iteration-site or proposal-target footprint; both inspection and
descriptor lowering consume this analyzed fact. Model-state reads do not acquire
a lattice footprint merely because the model also contains a lattice.
`test/test_component_replacement.jl` checks shared-input/state trajectories,
replacement, and binding failures through public constructors.

Native port imports follow the same source mapping through
`native/components.jl`'s endpoint rebuild. Original native systems and symbols
are retained. `completion/native_completion.jl` resolves endpoints against the
ephemeral enclosing source inventory, so an imported owner is not copied into a
child's state inventory. `ExternalIO` derives bindings from completed or scheduled
native declarations. Scheduling rejects a child that lacks an external endpoint
owner and directs the caller to compile its containing model.
`integration/test_native_component_replacement.jl` checks CPU shared-input and
replacement trajectories, sampled publication, native symbol identity, and failed
port reconnections. Native solver execution remains owned by the existing coupling
and native runtime path.

`completion/symbolic_interface.jl` projects completed equations, observations,
unknowns, parameters, IO roles, and initial conditions from qualified frozen source
references. It does not recursively namespace completed children or cache a second
symbol table. Incomplete source retains the ordinary MTK source query behavior;
the low-level `get_*` accessors still expose local source fields.

An external ModelingToolkit system remains native through structural compilation. Potts
does not recreate that system by copying equations, unknowns, parameters, defaults, events, or
hierarchy into a parallel Potts representation.

## CorePotts

CorePotts is the independently testable numerical kernel. It owns CPM state and invariants,
proposal and acceptance semantics, trackers, relationships, generation-safe lifecycle,
counter-based randomness, checkpoints, and backend execution. It has no ModelingToolkit dependency
and does not execute an external numerical solver.

CorePotts publishes settled coupling arrays and lifecycle receipts. Potts uses those public
boundaries to coordinate native component integrators.

## LocalMath

LocalMath is an independently testable execution substrate beneath
CorePotts. It owns validated local topology, declared reads and destinations,
bounded workspace, independent/combined/resolved output mechanisms, lifetime,
inspection, and central lowering to KernelAbstractions kernels. It relies on
KernelAbstractions implicit ordering and does not implement a scheduler.
Every package-owned spatial kernel uses that same KernelAbstractions path;
backend extensions adapt storage and report concrete device support but do not own raw
vendor kernel, launch, or synchronization implementations.

LocalMath does not own CPM physics, clocks, randomness, acceptance,
Hamiltonian folding, lifecycle transactions, checkpoints, or solver behavior.
Those remain domain responsibilities. Hardware-neutral kernel source is also
distinct from runtime support: the currently tested execution paths
are CPU and real Metal, not untested CUDA or ROCm claims.

## Time

The completed integer Monte Carlo step is the master CPM clock and lifecycle boundary. Each native
time-dependent component declares a physical duration per MCS and a named split policy. MTK clock
objects are not the master scheduler.

## MakiePotts

MakiePotts consumes explicit public observations and solutions. It cannot mutate simulation state,
advance time, trigger synchronization implicitly, or redefine scientific semantics.

See [Capability status](@ref capability-status) for the exact admitted
conjunctions. Architecture does not broaden a backend or solver claim.
