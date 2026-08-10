# Deferred MethodOfLines Input-Field Integration

Status: Deferred pending released upstream support

Date: 2026-08-09

## Purpose

PottsToolkit should revisit native moving-field coupling when MethodOfLines can discretize a
fixed-grid dependent field marked as a ModelingToolkit input without requiring a dummy evolution
equation. This document preserves that intended integration boundary without opening an active
implementation phase or blocking unrelated work.

The existing output-only `MethodOfLinesComponent`, `DiscreteFieldEuler`, and current Merks model
remain the supported implementations until a replacement passes the acceptance checks below.

## Intended upstream authoring experience

The target PDE should be expressible directly through public APIs:

```julia
@parameters t x y diffusion secretion
@variables concentration(..)
@variables occupancy(..) [input = true]

Dt = Differential(t)
Dx = Differential(x)
Dy = Differential(y)
Dxx = Dx^2
Dyy = Dy^2

equations = [
    Dt(concentration(t, x, y)) ~
        diffusion * (
            Dxx(concentration(t, x, y)) + Dyy(concentration(t, x, y))
        ) +
        secretion * occupancy(t, x, y),
]
```

`occupancy(t, x, y)` is an externally supplied field. It has no PDE, initial condition, or dummy
`Dt(occupancy) ~ 0` equation. Its complete discrete grid, including values needed at boundaries,
is supplied by the coupled model.

## Upstream readiness trigger

Revisit this integration only after a released MethodOfLines/PDEBase/ModelingToolkit stack satisfies
all of the following in the repository's integration environment:

1. `symbolic_discretize` accepts the input field without requiring one PDE per input field.
2. The generated fixed-grid variables preserve ModelingToolkit input identity through public APIs.
3. The complete generated input grid can be passed to `mtkcompile`; partial-grid inputs fail
   clearly.
4. Input values can change between coupled intervals without rerunning `symbolic_discretize` or
   structural compilation.
5. Scalarized and array discretization strategies either both work or have a documented public
   limitation that PottsToolkit can reject during preflight.
6. The required behavior uses no private upstream fields, post-discretization equation surgery,
   mutable global registry, or unowned closure state.

When those conditions hold, record the first supported upstream versions in package compatibility
and add a minimal executable regression before changing PottsToolkit production code.

## PottsToolkit integration to revisit

The smallest coherent downstream feature is:

- a fixed-shape native field-input declaration symmetric with `NativeFieldOutput`;
- a `MethodOfLinesComponent` input binding from a `FieldState` or a typed projection of staged CPM
  ownership;
- one owned, preallocated numerical buffer per component instance or ensemble trajectory;
- cached public MTK input indices or setters;
- value updates at declared coupled boundaries without symbolic recompilation;
- ModelingToolkit ownership of the semidiscrete equations and internal component connections; and
- PottsToolkit ownership only of projection, scheduling, transactional publication, and capability
  checks.

For `CPMThenComponents`, a moving occupancy source must be projected from the successfully staged
post-MCS ownership snapshot and held according to the component's declared coupling interval. A
failed field advance must not publish either the staged CPM state or a partial field result.

## Acceptance checks after reopening

The implementation is complete only when it demonstrates:

- a minimal upstream input-field regression through `symbolic_discretize` and `mtkcompile`;
- compile-once behavior with instrumented zero rediscretizations and zero structural compilations
  during steady coupled stepping;
- source appearance, translation, and disappearance on the fixed grid;
- correct empty occupancy, multiple-cell, cell-kind, secretion-strength, and boundary behavior;
- failure atomicity and deterministic checkpoint/restore on serial CPU;
- distinct owned input buffers for independently initialized trajectories;
- preservation of the existing output-only MethodOfLines path; and
- a readable Merks authoring comparison showing that migration preserves its intended mechanism
  and removes more custom machinery than it adds.

The target Mac serial path is the first required qualification. GPU execution, persistent solver
integrator optimization, threaded or distributed ensembles, Dagger orchestration, remeshing, and
general time-continuous forcing require separate evidence and must not be inferred from CPU input
support.

## Non-goals while deferred

Until the upstream readiness trigger is met, this specification does not authorize:

- a local fork or reimplementation of MethodOfLines equation matching;
- a PottsToolkit-specific symbolic discretizer or explicit diffusion replacement;
- removal of `DiscreteFieldEuler` or migration of Merks;
- new public capability claims; or
- an additional phase gate, committee, or G6 blocker.

A merged but unreleased upstream change may be tested in an isolated temporary environment, but it
does not reopen implementation or narrow package compatibility by itself.
