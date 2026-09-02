# [Fields, batching, and ensembles](@id fields-batching-ensembles)

## Fields

`DiscreteFieldEuler()` is an explicit `FieldState` evolution policy and the
built-in prescribed lattice stencil. Its
boundary, neighborhood, substeps, duration per MCS, secretion source, and
ownership semantics are explicit. It is not presented as a generic PDE
solver and does not copy a symbolic equation into a Potts process surrogate.
The complete public form is exercised by the
[Merks program](@ref merks-2006-integration).

`MethodOfLinesComponent` is the checked CPU PDE adapter. It calls
`symbolic_discretize`, retains the upstream compiled system, constructs a
standard SciML problem, and maps ordered spatial coordinates to an exact Potts
lattice shape.

```@example method_of_lines
using Potts
using ModelingToolkit
using DomainSets
using MethodOfLines
using OrdinaryDiffEqTsit5: Tsit5

@parameters t x y
@variables u(..) field(t)
Dt = Differential(t)
Dxx = Differential(x)^2
Dyy = Differential(y)^2
equations = [Dt(u(t, x, y)) ~ 0.1 * (Dxx(u(t, x, y)) + Dyy(u(t, x, y)))]
boundaries = [
    u(0, x, y) ~ 1 + x + y,
    u(t, 0, y) ~ u(t, 1, y),
    u(t, x, 0) ~ u(t, x, 1),
]
domains = [
    t ∈ Interval(0.0, 1.0),
    x ∈ Interval(0.0, 1.0),
    y ∈ Interval(0.0, 1.0),
]
@named pde = PDESystem(equations, boundaries, domains, [t, x, y], [u(t, x, y)])
discretization = MOLFiniteDifference([x=>4, y=>4], t; grid_align=center_align)

cell = CellKind(:cell; extinction=RetireAtZero())
medium = MediumKind(:medium)
field_state = FieldState(field; name=:field, initial=0.0, stencil=:field_stencil)
component = MethodOfLinesComponent(
    pde,
    discretization,
    u(t, x, y),
    field_state;
    spatial=(x, y),
    name=:pde,
    time=FixedPhysicalTime(0.0, 0.125),
)
scheduled = mtkcompile(PottsSystem(
    name=:mol_potts,
    statements=StatementSet((
        Lattice(
            (4, 4);
            boundary=Periodic(),
            relations=(field_stencil=VonNeumann(),),
        ),
        cell,
        medium,
        field_state,
        ProposalConstraint(:frozen, false),
        Protocol(Sweep(; temperature=0.0); name=:main),
    )),
    unknowns=[field],
    native_components=(component,),
))
path = (:mol_potts, :pde)
labels = zeros(Int, 4, 4)
labels[2, 2] = 1
problem = PottsProblem(
    scheduled,
    PottsInitialState(
        ownership=LabelledCells(labels; cells=[cell], medium),
        native=(NativeOperatingPoint(path),),
    ),
    (0, 1);
    seed=0x54e,
)
profile = NativeSolveProfile(
    path,
    Tsit5();
    profile_id="docs-mol-tsit5-fixed-v1",
    deterministic=true,
    exact_replay=true,
    adaptive=false,
    dt=0.015625,
)
(size(labels), profile.deterministic, profile.exact_replay)
```

This profile explicitly requests exact replay and therefore requires the pinned
dependency and Julia runtime recorded by the replay environment. Set
`exact_replay=false` for ordinary functional execution; structural and
numerical preflight still completes before any CPM or native state advances.

## Whole-trajectory ensembles

`SciMLBase.EnsembleProblem(::PottsProblem)` assigns deterministic `replica`
identity. Serial, threaded, and distributed ensemble algorithms own
trajectory scheduling, retries, reductions, and failures. The inner Potts
trajectory still requires an admitted algorithm/backend/component profile.

```@example ensembles
using Potts
using SciMLBase

cell = CellKind(:cell; extinction=RetireAtZero())
medium = MediumKind(:medium)
scheduled = mtkcompile(PottsSystem(
    name=:ensemble_model,
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
    seed=0x5eed,
)
ensemble = EnsembleProblem(problem)
serial = solve(
    ensemble,
    SequentialCPM(),
    EnsembleSerial();
    trajectories=2,
    backend=CPUBackend(),
)
([trajectory.prob.replica for trajectory in serial.u], length(serial.u))
```

Per-cell batching solves many fixed-shape component lanes inside one Potts
trajectory. An ensemble solves multiple whole trajectories. Neither API is an
alias for the other, and Dagger is not an internal scheduler.
