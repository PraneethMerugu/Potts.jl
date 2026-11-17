# [Relation to ModelingToolkit](@id modelingtoolkit)

This page states exactly what Potts.jl takes from
[ModelingToolkit](https://docs.sciml.ai/ModelingToolkit/stable/) (MTK) and what it does
itself. Each claim below comes with the public function that makes it true and a short
example that you can run. The acceptance test
`lib/PottsModels/test/acceptance/p6_0bs_mtk_claims.jl` checks every claim on every
published model, and checks that this page keeps saying them. The test's testset for a
claim is given in brackets, e.g. [C1].

## The claim in brief

Potts.jl is built on ModelingToolkit. Every Potts model is a ModelingToolkit system: an
`AbstractSystem` whose parameters, state variables, equations, observables, update rules
and Hamiltonian are Symbolics expressions that ModelingToolkit's generic tools can
inspect and index. The model wraps a complete ModelingToolkit `System`,
`Potts.inner(sys)`, which MTK's tools take where they need a `System`. The continuous parts of a model, its cell- and model-scale
ODEs, are ModelingToolkit systems compiled by `mtkcompile`; Potts.jl lowers the simplified
equations into its batched kernels. Entity-local initialization equations are
ModelingToolkit initialization systems, solved per cell by MTK's `InitializationProblem`.
Existing ModelingToolkit models plug in as components, continuous ones and clocked ones.
The stochastic lattice dynamics, a Markov operator over cell ownership with no equation
form in ModelingToolkit, are compiled from the symbolic Hamiltonian by Potts.jl's own code
generator into fused CPU and GPU kernels. This is the same division of labor Catalyst
uses for spatial reaction networks.

## One model with every part

The examples on this page use one small model. It has a cell ODE with an algebraic
variable, a model ODE, a diffusing field from a `PDESystem`, an update rule, an
initialization equation and a ModelingToolkit component in every cell:

```@example mtk
using Potts
using Potts.ModelingToolkitBase: System, PDESystem, Differential, @variables, @parameters
using Potts.LatticePDE: Δ, lattice_domain

@variables y(Potts.t) = 1.0
@parameters kc = 0.1
@named decay = System([Potts.D(y) ~ -kc * y], Potts.t)   # an ordinary MTK model

@parameters px py Dc = 0.1
@variables c(..) = 0.0
C = c(Potts.t, px, py)
@named heat = PDESystem([Differential(Potts.t)(C) ~ Dc * Δ(C) - 0.1 * C], [],   # a field PDE, stepped by Potts
    lattice_domain(Potts.t, (px, py), (12, 8)), [Potts.t, px, py], [C], [Dc])

@potts_model AllParts begin
    @kinds medium A
    @parameters begin
        k = 0.1
        r = 0.2
    end
    @variables begin
        x(cell) = 2.0
        excess(cell) = 0.0
        m(model) = 0.0
        gap(model) = 0.0
        acc(cell) = 0.0
        rt(cell), [guess = 1.0]
    end
    @components cells(A) decay = decay
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @fields heat
    @equations begin
        D(x) ~ -k * excess
        excess ~ x                     # algebraic: eliminated by mtkcompile
        D(m) ~ r * gap
        gap ~ 1 - m
    end
    @initialization_equations rt^2 ~ volume
    @after_mcs acc ~ Pre(acc) + excess
    @sweep Metropolis(; temperature = 1.0)
end

@named sys = AllParts()
σ = zeros(Int32, 12, 8); σ[3:6, 3:6] .= 1; σ[7:10, 3:5] .= 2   # cells of 16 and 12 sites
prob = PottsProblem(sys, [ownership => σ, kind => [:A, :A]], (0, 5);
    seed = 3, field_solver = ExplicitEuler(substeps = 2))
nothing # hide
```

## A model is an `AbstractSystem` [C1, C2]

A Potts model is a `PottsSystem`, a subtype of ModelingToolkit's `AbstractSystem` that
holds a complete MTK `System` (`Potts.inner(sys)`) for its quantities, equations and
observed quantities. The lattice, kinds and sweep are the Potts layer around it.

```@example mtk
const MTK = Potts.ModelingToolkitBase
(sys isa MTK.AbstractSystem, sys isa MTK.System, Potts.inner(sys) isa MTK.System, MTK.iscomplete(Potts.inner(sys)))
```

MTK's own accessors work on it and return Symbolics objects:

```@example mtk
MTK.parameters(sys)
```

```@example mtk
MTK.equations(sys)
```

Parameters are MTK parameters, and built-ins such as `kind` and `volume` are MTK inputs
`kind(t)`, `volume(t)` whose values the CPM supplies. What each symbol is in the model (a
cell variable, a built-in, …) is its `potts_entity` metadata:

```@example mtk
(all(MTK.isparameter, MTK.parameters(sys)), MTK.isinput(kind), Potts.LatticePDE.get_potts_entity(kind))
```

`MTK.unknowns`, `MTK.observed`, `MTK.initial_conditions` (each parameter's value),
`MTK.guesses`, `MTK.inputs`, `MTK.outputs`, `MTK.independent_variable`, the metadata and
`nameof` work too, and `sys.k` is the declared symbol `k`. A model is complete
(`MTK.iscomplete(sys)` is `true`), so `sys.k` is never namespaced. Potts models merge with
MTK's `extend` (`@extend`), compose with MTK's `compose`, and rename with MTK's `rename` (and
`@named models[1:n] = Model()`). `Potts.component(name, system, model)` makes an MTK `System` a
component of the model (for a Catalyst reaction network the system is
`Catalyst.ode_model(complete(rn))`). The component joins as a model-scope component, as with
`@components model name = system`, and its quantities are namespaced, `name₊x`:

```@example mtk
@variables z(Potts.t) = 1.0
@parameters kz = 0.5
@named zdecay = System([Potts.D(z) ~ -kz * z], Potts.t)
composed = compose(sys, [zdecay])
zsol = solve(PottsProblem(composed, [ownership => σ, kind => [:A, :A]], (0, 5); seed = 3,
    field_solver = ExplicitEuler(substeps = 2)), SequentialCPM(); save_everystep = false)
zsol[:zdecay₊z][end]
```

A problem's `p` implements SciMLStructures: `Tunable` is
the floating-point scalar parameters, `Constants` the kind tables (and integer scalars), and CPM
parameters stay plain numbers. A `tunable = false` parameter is in `Constants`. Computed
parameters (a default such as `λ2 = 2λ`) are in neither portion: they are read-only (D-F2-1),
and `SciMLStructures.replace` and `repack` derive them again through the model's derivation,
which is registered when a problem of the model is built in the process. Distributed workers
must therefore build the problem themselves before they `repack`; each `repack` of a model with
computed parameters costs one call of one compiled function (`LatticePDE.derivation`).
SymbolicIndexingInterface (SII) indexes a problem, a solution and an integrator by name,
including an algebraic variable that is not stored:

```@example mtk
using Potts.SymbolicIndexingInterface: getp, getu
sol = solve(prob, SequentialCPM(); saveat = 1)
(k = getp(prob, :k)(prob), x = getu(sol, :x)(sol)[end], excess = sol[:excess][end])
```

`LatticePDE.discretize(Potts.fields(sys), disc)` gives one SciML problem: an `ODEProblem` of
the rates, or a `DiscreteProblem` of the maps. A field algorithm steps it,
`solve(prob, BackwardEuler(); dt = 0.1, save_everystep = false)`, and so does an OrdinaryDiffEq solver,
`solve(prob, Rodas5P())`. The problem's `p` holds the parameters, the tables and the inputs.
On the integrator of a field algorithm, `integ[c]` returns a copy of the field's values, on the
problem's device.
Writing into the copy, `integ[c][1, 1] = v`, changes nothing; to change the field, assign it:
`integ[c] = values`.
Parameters, tables and inputs go through `integ.ps`, as in SciML: `integ.ps[:k] = 2.0`,
`integ.ps[:δ] = values`, `integ.ps[δ[2]] = v` and `integ.ps[:kind] = K`. They work the same
way on an OrdinaryDiffEq integrator. Each write runs the checks of `setp`, the
substep count and the masks again, or changes nothing. `integ[:k]` of a parameter is an error
that gives this route.
`discretize` takes SciML's keywords `u0`, `p` and `tspan`, with the rule of `remake`: `discretize(Potts.fields(sys), disc; p = [:k => 2.0], u0 = [:c => 0.5],
tspan = (0, 10))` builds the problem at those values, with no `remake`. It also takes the
Jacobian keywords of an implicit OrdinaryDiffEq solver. `sparse = true` gives the problem the
sparse pattern of its Jacobian, read off the compiled program (`jacobian_sparsity(prob)`), and
a coloring of it, so `Rodas5P()` forms the Jacobian with a few evaluations of the right side
instead of a dense one. `jac = true` gives it the Jacobian itself (colored Duals). Both are
host only. The Jacobian-vector product `prob.f.jvp` is always set, so a Krylov linear solver
runs matrix-free, also on a device, and the lattice multigrid preconditions it:
`solve(prob, FBDF(; linsolve = KrylovJL_GMRES(; precs = LatticeMultigrid(), gmres_restart = 10)))`.
With `LatticeMultigrid`, GMRES takes a few iterations per solve, so a small memory,
`gmres_restart = 10`, is enough: LinearSolve currently allocates the GMRES workspace again
at each new `W` (SciML/LinearSolve.jl#1378 fixes it). For a symmetric
system, `linsolve = LatticePCG()` takes conjugate gradients with the same preconditioner.
Any other keyword is an error that names it.

A `PDESystem` coupled by `@fields` or `Potts.couple` stays a plain ModelingToolkit system.
`Potts.fields(model)` is the `PDESystem` of the model's fields, and
`Potts.field_inputs(integ)` gives its inputs at the CPM state of an integrator, so
`discretize(Potts.fields(model), disc; inputs = collect(Potts.field_inputs(integ)))` solves the
fields with any SciML solver. The result matches the owned run only while σ is frozen: see
[The SciML path](@ref manual-sciml-path).

A field algorithm returns SciML's `ODESolution`, with linear interpolation between the saves:
`sol(t)`, `Array(sol)`, `sol.ps` (the values at the end of the run) and `sol.stats` work. A
field reads as SciML reads a variable, on every solver and in a Potts solution too: `sol[c]` (or
`sol[:c]`, or the bare `c`) is one grid per save, so `sol[c][end]` is the last grid;
`sol[c, i]` is the grid at save `i`, `sol(t; idxs = c)` the grid at time `t`, `sol[x]` holds the
site centers, and `sol(t, x, y)` interpolates between them. `field_series(sol, :c)` is the
time-first view, as in MethodOfLines: an array of size `(length(sol.t), nx, ny)` that reads the
saves when indexed. On a Potts solution it gives the same view of a field over the saved MCS.
On a large lattice, pass `saveat` (the times to keep) or `save_everystep = false` (the end
only) to an OrdinaryDiffEq solver. By default it saves every step with its dense output, about
seven state vectors per step for `FBDF` (14 MiB per step at 512²).

## The Hamiltonian as Symbolics expressions [C3]

`Potts.hamiltonian(sys)` gives the `@energy` terms as `domain => expr` pairs of Symbolics
expressions; `Potts.drives(sys)` gives the drives, and the sweep payload's `constraints`
gives the constraints. Generic code reads the whole sweep definition through MTK's metadata API:

```@example mtk
Potts.hamiltonian(sys)
```

```@example mtk
spec = MTK.getmetadata(Potts.inner(sys), Potts.PottsSweepSpec, nothing)
(MTK.hasmetadata(Potts.inner(sys), Potts.PottsSweepSpec), MTK.hasmetadata(decay, Potts.PottsSweepSpec),
 isequal(spec.hamiltonian, Potts.hamiltonian(sys)))
```

## Cell and model ODEs through `mtkcompile` [C4]

`Potts.ode_system(csys, :cell)` and `Potts.ode_system(csys, :model)` return the
ModelingToolkit `System` that `mtkcompile` produced from a compiled model `csys` (`nothing`
for a scope without ODEs). The algebraic variable `excess` is one of its `observed`
equations, not an unknown, and the problem does not store it:

```@example mtk
csys = mtkcompile(sys)
o = Potts.ode_system(csys, :cell)
(MTK.isscheduled(o), MTK.unknowns(o), MTK.observed(o))
```

```@example mtk
propertynames(prob.u0.cell)
```

Potts then lowers these simplified equations into one batched kernel that steps every
cell at once (see [Equations and solvers](@ref manual-equations)).

## Components [C5]

A ModelingToolkit `System` given to `@components` goes through `mtkcompile` like any MTK
model. Only its unknowns after simplification become cell variables (here `decay₊y`, one
per cell), and a clocked system with a `ShiftIndex` goes through MTK's discrete pass (see
[Tutorial 5](@ref tutorial-cell-odes)):

```@example mtk
sol[:decay₊y][end]
```

## Update rules in MTK's `Pre` form [C6]

A model's update rules are Symbolics equations in ModelingToolkit's `Pre` form that MTK's
generic tools can inspect. `Potts.updates(sys)` lists each `@before_mcs`, `@after_mcs` and
`@on_copy` statement with its phase, scope and cadence:

```@example mtk
u = only(Potts.updates(sys))
(u.phase, u.scope, u.every, u.eq)
```

Update rules are not ModelingToolkit events: Potts compiles and runs them in its sweep,
and the events of its inner `System`, `MTK.discrete_events(Potts.inner(sys))` and
`MTK.continuous_events(Potts.inner(sys))`, are empty:

```@example mtk
(MTK.discrete_events(Potts.inner(sys)), MTK.continuous_events(Potts.inner(sys)))
```

## Initialization per cell [C7]

`Potts.initialization_system(csys, :cell)` is a complete `System` whose
`initialization_equations` are the model's `@initialization_equations`, with inputs such
as `volume` as its parameters. When a problem is built, Potts builds MTK's
`InitializationProblem` of that system and solves its residual for every cell. Here `rt = √volume`, so the two
cells start with different values:

```@example mtk
isys = Potts.initialization_system(csys, :cell)
(MTK.initialization_equations(isys), prob.u0.cell.rt)
```

Cross-entity and lattice initialization stay in Potts' own initialization phase (see
[Variables](@ref manual-variables)).

## What ModelingToolkit does not do

- **It does not simulate the CPM sweep** [C9]. `mtkcompile` of a Potts model is Potts'
  own method and returns a `CompiledPottsSystem`, not an MTK `System`. A Potts model is
  solved through `PottsProblem`; MTK's `ODEProblem` and `JumpProblem` of a Potts model are
  `ArgumentError`s that point there:

  ```@example mtk
  try
      MTK.ODEProblem(sys, [], (0.0, 1.0))
  catch err
      sprint(showerror, err)
  end
  ```

- **Fields are not compiled by MTK** [C8]. A field's equations come from a
  ModelingToolkit `PDESystem`, and `MTK.equations` lists them. MTK does not discretize or
  step them. LatticePDE lowers the `PDESystem` to lattice kernels, and Potts steps them in
  the MCS loop with the problem's `field_solver`. `Potts.ode_system(csys, :field)` is an
  `ArgumentError` that gives the SciML route below.

- **Update rules are not MTK events** [C6]. They are compiled and run by Potts, so a
  reader of `MTK.discrete_events` sees none.

Planned: update rules as ModelingToolkit callbacks (`SymbolicDiscreteCallback`), and
cross-entity initialization through MTK. When either lands, this page changes with it.
