# [Native MTK components](@id native-mtk-components)

A `NativeComponent` retains its upstream ModelingToolkit system. The
declaration adds only Potts-facing scope, typed IO, physical-time mapping,
cadence, split order, lifecycle policy, and capability requirement. Full MTK
structural compilation and standard SciML problem construction live in the
weak extension.

```@example native_global
using Potts
using ModelingToolkit
using OrdinaryDiffEqTsit5: Tsit5

@independent_variables t
@variables x(t) = 1.0 drive(t)
D = Differential(t)
@named ode = System([D(x) ~ -x + drive], t)

@variables potts_drive potts_output
input_state = ModelState(potts_drive; name=:drive, initial=2.0)
output_state = ModelState(potts_output; name=:output, initial=0.0)
component = NativeComponent(
    ode;
    name=:island,
    family=ODEComponent(),
    scope=Global(),
    time=FixedPhysicalTime(0.0, 0.1),
    inputs=(NativeInput(drive, input_state; value_type=Float64),),
    outputs=(NativeOutput(x, output_state; value_type=Float64),),
)

cell = CellKind(:cell; extinction=RetireAtZero())
medium = MediumKind(:medium)
scheduled = mtkcompile(PottsSystem(
    name=:coupled,
    statements=StatementSet((
        Lattice((3, 3); boundary=Closed()),
        cell,
        medium,
        input_state,
        output_state,
        ProposalConstraint(:frozen, false),
        Protocol(Sweep(; temperature=0.0); name=:main),
    )),
    unknowns=[potts_drive, potts_output],
    native_components=(component,),
))
path = (:coupled, :island)
labels = zeros(Int, 3, 3)
labels[2, 2] = 1
initial = PottsInitialState(
    ownership=LabelledCells(labels; cells=[cell], medium),
    native=(NativeOperatingPoint(path; values=(x=>1.0,)),),
)
problem = PottsProblem(scheduled, initial, (0, 1); seed=0x503)
profile = NativeSolveProfile(
    path,
    Tsit5();
    deterministic=true,
    adaptive=false,
    dt=0.01,
)
integrator = init(problem, SequentialCPM(); native_profiles=(profile,))
step!(integrator)
integrator.u.output
```

Functional execution is admitted by structural, solver, backend, and event
preflight. Set `exact_replay=true` with a pinned `profile_id` and
`deterministic=true` only when the stronger checkpoint/replay contract is
needed; that request additionally requires a matching closed replay row.

For `PerCell()`, declare `PerCellNativeLifecycle` explicitly. The component
pool has fixed capacity, active/generation/kind masks, and two-bank atomic
publication. `SerialNativeExecution()` is the reference;
`BatchedNativeExecution(width)` vectorizes live lanes on CPU; and
`MetalNativeExecution(width)` is a separately evidenced GPU profile executed
through DiffEqGPU's KernelAbstractions backend contract. These are
within-trajectory component modes, not SciML ensemble algorithms.

Every native solve needs a `NativeSolveProfile`. Unsupported family, scalar,
events/callbacks, adaptivity, solver, backend, or field structure fails during
preflight before CPM state advances. An unmatched dependency stack rejects an
explicit exact-replay request, not an otherwise supported functional run.
